# Hephaestus Management Scripts

This directory contains utility scripts for managing and monitoring Hephaestus workflows.

## Scripts

### `hephaestus.sh`
Main startup/management script for Hephaestus services.

**Usage:**
```bash
./scripts/management/hephaestus.sh [start|restart|stop|status]
```

**Features:**
- Starts/stops MCP server, monitor, frontend, and Qdrant
- Automatically starts Qdrant via Docker if not running
- Validates configuration before starting
- Shows service status

**Examples:**
```bash
# Start all services
./scripts/management/hephaestus.sh start

# Restart all services
./scripts/management/hephaestus.sh restart

# Check status
./scripts/management/hephaestus.sh status

# Stop all services
./scripts/management/hephaestus.sh stop
```

### `check_workflow_status.py`
Check workflow completion status via API or database.

**Usage:**
```bash
python3 scripts/management/check_workflow_status.py [--workflow-id ID] [--method api|db|both] [--json]
```

**Features:**
- Checks if workflow is complete
- Shows phase and task completion statistics
- Provides progress percentages
- Can check via API or database (or both)

**Examples:**
```bash
# Human-readable output
python3 scripts/management/check_workflow_status.py

# JSON output
python3 scripts/management/check_workflow_status.py --json

# Check specific workflow
python3 scripts/management/check_workflow_status.py --workflow-id <id>
```

### `restart_stalled_workflow.py`
Restart stalled workflows by resetting failed tasks and enqueuing them.

**Usage:**
```bash
python3 scripts/management/restart_stalled_workflow.py [--check-blocked] [--unblock]
```

**Features:**
- Finds failed tasks (e.g., due to worktree issues)
- Resets them to `queued` status
- Enqueues them for the queue processor
- Optionally checks blocked tasks

**Examples:**
```bash
# Restart failed tasks
python3 scripts/management/restart_stalled_workflow.py

# Also check blocked tasks
python3 scripts/management/restart_stalled_workflow.py --check-blocked
```

### `restart_stalled_agents.py`
Legacy script for restarting agents that were running when API limits were hit.

**Note:** This script is kept for reference but `restart_stalled_workflow.py` is preferred for most use cases.

## Quick Reference

**Start Hephaestus:**
```bash
./scripts/management/hephaestus.sh start
```

**Check if workflow is complete:**
```bash
python3 scripts/management/check_workflow_status.py
```

**Restart stalled workflow:**
```bash
python3 scripts/management/restart_stalled_workflow.py
```

**Monitor progress:**
- Frontend UI: http://localhost:5173/
- API: `curl http://localhost:8000/api/workflow`
- Queue status: `curl http://localhost:8000/api/queue_status`

## Requirements

All scripts require:
- Python 3.10+
- Virtual environment activated (or dependencies installed)
- Hephaestus services running (for status/restart scripts)

The `hephaestus.sh` script also requires:
- Docker (for Qdrant)
- Node.js & npm (for frontend)

