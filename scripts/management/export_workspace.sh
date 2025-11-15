#!/bin/bash
# Export Hephaestus workspace state for migration to another system
# Usage: ./export_workspace.sh [output_directory]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${1:-${REPO_ROOT}/workspace_export_$(date +%Y%m%d_%H%M%S)}"

echo "=== Hephaestus Workspace Export ==="
echo "Repository: $REPO_ROOT"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Create output directory structure
mkdir -p "$OUTPUT_DIR"/{database,qdrant,worktrees,config,logs}

# 1. Export SQLite Database
echo "[1/5] Exporting SQLite database..."
DB_PATH="${REPO_ROOT}/hephaestus.db"
if [ -f "$DB_PATH" ]; then
    cp "$DB_PATH" "$OUTPUT_DIR/database/hephaestus.db"
    echo "  ✓ Database exported ($(du -h "$DB_PATH" | cut -f1))"
else
    echo "  ⚠ Database not found at $DB_PATH"
fi

# 2. Export Qdrant Collections
echo "[2/5] Exporting Qdrant vector store..."
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"

# Check if Qdrant is running
if curl -s "$QDRANT_URL/health" > /dev/null 2>&1; then
    # Get list of collections
    COLLECTIONS=$(curl -s "$QDRANT_URL/collections" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    collections = data.get('result', {}).get('collections', [])
    for col in collections:
        print(col['name'])
except:
    pass
" 2>/dev/null || echo "")
    
    if [ -n "$COLLECTIONS" ]; then
        echo "$COLLECTIONS" > "$OUTPUT_DIR/qdrant/collections.txt"
        echo "  ✓ Found collections:"
        echo "$COLLECTIONS" | while read -r col; do
            echo "    - $col"
            # Export collection snapshot (if Qdrant supports it)
            curl -s "$QDRANT_URL/collections/$col" > "$OUTPUT_DIR/qdrant/${col}_info.json" 2>/dev/null || true
        done
        echo "  ⚠ Note: Qdrant snapshot export requires manual steps (see migration guide)"
    else
        echo "  ⚠ No collections found or Qdrant API error"
    fi
else
    echo "  ⚠ Qdrant not running at $QDRANT_URL - skipping collection export"
    echo "  ℹ You can export Qdrant data manually using Docker volumes"
fi

# 3. Archive Worktrees
echo "[3/5] Archiving git worktrees..."
WORKTREE_BASE="${WORKTREE_BASE:-/tmp/hephaestus_worktrees}"
if [ -d "$WORKTREE_BASE" ] && [ "$(ls -A $WORKTREE_BASE 2>/dev/null)" ]; then
    WORKTREE_COUNT=$(find "$WORKTREE_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    if [ "$WORKTREE_COUNT" -gt 0 ]; then
        tar -czf "$OUTPUT_DIR/worktrees/worktrees.tar.gz" -C "$(dirname "$WORKTREE_BASE")" "$(basename "$WORKTREE_BASE")" 2>/dev/null || {
            echo "  ⚠ Failed to create worktree archive (may need sudo for /tmp access)"
            echo "  ℹ Worktrees directory: $WORKTREE_BASE"
            echo "  ℹ You may need to manually copy this directory"
        }
        echo "  ✓ Archived $WORKTREE_COUNT worktree directories"
    else
        echo "  ℹ No worktrees found"
    fi
else
    echo "  ℹ Worktree directory does not exist or is empty"
fi

# 4. Export Configuration Files
echo "[4/5] Exporting configuration..."
if [ -f "${REPO_ROOT}/hephaestus_config.yaml" ]; then
    cp "${REPO_ROOT}/hephaestus_config.yaml" "$OUTPUT_DIR/config/"
    echo "  ✓ Configuration exported"
fi

if [ -f "${REPO_ROOT}/.env" ]; then
    # Remove sensitive data or create template
    grep -v -E "^(API_KEY|SECRET|TOKEN|PASSWORD)=" "${REPO_ROOT}/.env" > "$OUTPUT_DIR/config/.env.template" 2>/dev/null || true
    echo "  ✓ Environment template created (sensitive values removed)"
    echo "  ⚠ Remember to add API keys on the new system"
fi

# Export git remotes info (for reference)
if [ -d "${REPO_ROOT}/.git" ]; then
    git -C "$REPO_ROOT" remote -v > "$OUTPUT_DIR/config/git_remotes.txt" 2>/dev/null || true
fi

# 5. Create Migration Manifest
echo "[5/5] Creating migration manifest..."
cat > "$OUTPUT_DIR/MIGRATION_MANIFEST.txt" <<EOF
Hephaestus Workspace Export
Generated: $(date)
Source System: $(hostname)
Repository Root: $REPO_ROOT

Contents:
- database/hephaestus.db: SQLite database with all workflow state
- qdrant/: Qdrant collection metadata (full export requires Docker volume backup)
- worktrees/: Git worktrees archive (if available)
- config/: Configuration files and templates

Migration Steps:
1. Transfer this entire directory to the target system
2. Follow instructions in MIGRATION_GUIDE.md
3. Restore database, Qdrant data, and worktrees
4. Update configuration paths and API keys
5. Restart Hephaestus services

Database Size: $(du -h "$OUTPUT_DIR/database/hephaestus.db" 2>/dev/null | cut -f1 || echo "N/A")
Worktree Count: ${WORKTREE_COUNT:-0}
EOF

echo ""
echo "=== Export Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Review $OUTPUT_DIR/MIGRATION_MANIFEST.txt"
echo "2. Transfer directory to target system (rsync, scp, or tar)"
echo "3. Follow migration guide on target system"
echo ""
echo "To create a compressed archive:"
echo "  tar -czf workspace_export.tar.gz -C $(dirname "$OUTPUT_DIR") $(basename "$OUTPUT_DIR")"

