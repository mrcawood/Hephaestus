#!/bin/bash
# Import Hephaestus workspace state on target system
# Usage: ./import_workspace.sh <export_directory> [target_repo_path]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <export_directory> [target_repo_path]"
    echo "Example: $0 ~/workspace_export_20241114_213800 ~/Hephaestus"
    exit 1
fi

EXPORT_DIR="$1"
TARGET_REPO="${2:-$(pwd)}"

if [ ! -d "$EXPORT_DIR" ]; then
    echo "Error: Export directory not found: $EXPORT_DIR"
    exit 1
fi

if [ ! -d "$TARGET_REPO" ]; then
    echo "Error: Target repository not found: $TARGET_REPO"
    exit 1
fi

echo "=== Hephaestus Workspace Import ==="
echo "Export directory: $EXPORT_DIR"
echo "Target repository: $TARGET_REPO"
echo ""

# Verify manifest exists
if [ ! -f "$EXPORT_DIR/MIGRATION_MANIFEST.txt" ]; then
    echo "⚠ Warning: MIGRATION_MANIFEST.txt not found - proceeding anyway"
fi

# 1. Import Database
echo "[1/4] Importing SQLite database..."
DB_SOURCE="$EXPORT_DIR/database/hephaestus.db"
if [ -f "$DB_SOURCE" ]; then
    DB_TARGET="$TARGET_REPO/hephaestus.db"
    if [ -f "$DB_TARGET" ]; then
        BACKUP="${DB_TARGET}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "  ⚠ Existing database found - backing up to $BACKUP"
        cp "$DB_TARGET" "$BACKUP"
    fi
    cp "$DB_SOURCE" "$DB_TARGET"
    echo "  ✓ Database imported"
else
    echo "  ⚠ Database file not found in export"
fi

# 2. Restore Worktrees
echo "[2/4] Restoring git worktrees..."
WORKTREE_ARCHIVE="$EXPORT_DIR/worktrees/worktrees.tar.gz"
if [ -f "$WORKTREE_ARCHIVE" ]; then
    WORKTREE_BASE="${WORKTREE_BASE:-/tmp/hephaestus_worktrees}"
    if [ -d "$WORKTREE_BASE" ]; then
        echo "  ⚠ Worktree directory exists - backing up"
        mv "$WORKTREE_BASE" "${WORKTREE_BASE}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    mkdir -p "$(dirname "$WORKTREE_BASE")"
    tar -xzf "$WORKTREE_ARCHIVE" -C "$(dirname "$WORKTREE_BASE")"
    echo "  ✓ Worktrees restored to $WORKTREE_BASE"
    echo "  ℹ Verify worktree paths match configuration"
else
    echo "  ℹ No worktree archive found - skipping"
fi

# 3. Restore Configuration
echo "[3/4] Restoring configuration..."
if [ -f "$EXPORT_DIR/config/hephaestus_config.yaml" ]; then
    CONFIG_TARGET="$TARGET_REPO/hephaestus_config.yaml"
    if [ -f "$CONFIG_TARGET" ]; then
        echo "  ⚠ Configuration file exists - creating backup"
        cp "$CONFIG_TARGET" "${CONFIG_TARGET}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    cp "$EXPORT_DIR/config/hephaestus_config.yaml" "$CONFIG_TARGET"
    echo "  ✓ Configuration restored"
    echo "  ⚠ Review and update paths/API keys as needed"
fi

if [ -f "$EXPORT_DIR/config/.env.template" ]; then
    echo "  ℹ Environment template available at: $EXPORT_DIR/config/.env.template"
    echo "  ℹ Copy to $TARGET_REPO/.env and add your API keys"
fi

# 4. Qdrant Data (Manual Steps Required)
echo "[4/4] Qdrant vector store..."
echo "  ℹ Qdrant data requires manual restoration:"
echo "     Option A: If using Docker volumes, restore the qdrant_data volume"
echo "     Option B: Re-index collections using Hephaestus initialization scripts"
echo "     Option C: Use Qdrant snapshot API (if available)"
echo ""
echo "  Collections found in export:"
if [ -f "$EXPORT_DIR/qdrant/collections.txt" ]; then
    cat "$EXPORT_DIR/qdrant/collections.txt" | sed 's/^/    - /'
else
    echo "    (none listed)"
fi

# 5. Path Verification
echo ""
echo "=== Path Verification ==="
CONFIG_FILE="$TARGET_REPO/hephaestus_config.yaml"
if [ -f "$CONFIG_FILE" ]; then
    echo "Checking configuration paths..."
    WORKTREE_PATH=$(grep -A 1 "worktree_base:" "$CONFIG_FILE" | tail -1 | sed 's/.*: *//' | tr -d '"' || echo "")
    DB_PATH=$(grep -A 1 "database:" "$CONFIG_FILE" | tail -1 | sed 's/.*: *//' | tr -d '"' || echo "")
    
    if [ -n "$WORKTREE_PATH" ]; then
        if [ -d "$WORKTREE_PATH" ]; then
            echo "  ✓ Worktree path exists: $WORKTREE_PATH"
        else
            echo "  ⚠ Worktree path missing: $WORKTREE_PATH"
            echo "     Update hephaestus_config.yaml or create directory"
        fi
    fi
    
    if [ -n "$DB_PATH" ]; then
        DB_FULL_PATH="$TARGET_REPO/$DB_PATH"
        if [ -f "$DB_FULL_PATH" ]; then
            echo "  ✓ Database path exists: $DB_FULL_PATH"
        else
            echo "  ⚠ Database path missing: $DB_FULL_PATH"
        fi
    fi
fi

echo ""
echo "=== Import Complete ==="
echo ""
echo "Next steps:"
echo "1. Review and update hephaestus_config.yaml paths"
echo "2. Copy .env.template to .env and add API keys"
echo "3. Start Qdrant: docker-compose up -d qdrant"
echo "4. Initialize Qdrant: python scripts/init_qdrant.py (if needed)"
echo "5. Start Hephaestus: ./scripts/management/hephaestus.sh start"
echo ""
echo "To verify workflow state:"
echo "  python scripts/management/check_workflow_status.py"

