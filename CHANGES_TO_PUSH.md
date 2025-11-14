# Changes to Push to Fork (mrcawood/Hephaestus)

## Summary
This document lists all local changes that should be pushed to the fork, including management scripts and code fixes.

---

## Modified Files

### 1. Core Code Fixes

#### `src/core/worktree_manager.py`
**Change:** Fixed bug where agent creation fails when parent worktree was cleaned up  
**Details:**
- Added `_get_parent_commit_from_database()` method to preserve knowledge inheritance
- Modified `_prepare_parent_commit()` to gracefully handle non-existent parent worktree paths
- Implements 4 fallback strategies to use parent's branch/commit from database instead of falling back to main
- **Impact:** Prevents workflow failures when parent agents complete before child agents start

#### `src/core/simple_config.py`
**Change:** Added GLM configuration options  
**Details:**
- Added `glm_api_base_url` and `glm_model_name` configuration options
- Allows configurable GLM API endpoints (Novita AI, z.ai, or custom)
- **Impact:** Enables flexible GLM-4.6 provider configuration

#### `src/agents/manager.py`
**Change:** Updated GLM environment variable setup  
**Details:**
- Uses configurable `glm_api_base_url` and `glm_model_name` from config
- Supports custom GLM endpoints (Novita AI, z.ai, etc.)
- **Impact:** Better GLM integration flexibility

### 2. Configuration Files

#### `hephaestus_config.yaml`
**Changes:**
- Updated LLM provider from `openrouter` to `openai`
- Added GLM configuration: `glm_api_base_url` and `glm_model_name`
- Configured for Novita AI GLM-4.6 endpoint
- **Impact:** Current working configuration

### 3. Management Scripts (New Directory)

#### `scripts/management/`
**New directory containing workflow management tools:**

- **`hephaestus.sh`** - Start/stop/restart/status script for Hephaestus services
  - Automatically starts Qdrant via Docker
  - Automatically starts frontend
  - Health checks and service management
  
- **`check_workflow_status.py`** - Check workflow completion status
  - Shows phase progress
  - Lists active agents and tasks
  - Displays recent completions
  
- **`restart_stalled_workflow.py`** - Restart failed/stalled tasks
  - Resets failed tasks to queued status
  - Enqueues tasks for processing
  - Handles blocked tasks
  
- **`cleanup_stale_worktrees.py`** - Clean up stale git worktree records
  - Identifies orphaned worktree records
  - Marks stale worktrees as cleaned
  - Removes orphaned git branches
  
- **`README.md`** - Documentation for management scripts

### 4. Documentation

#### `BUG_REPORT_worktree_parent_commit.md`
**New file:** Bug report for upstream repository  
**Details:**
- Documents the worktree parent commit bug
- Includes root cause analysis
- Proposes fix (already implemented)
- Ready to submit as GitHub issue or PR

#### `LOCAL_INFERENCE_IMPLEMENTATION_PLAN.md`
**New file:** Implementation plan for local GLM-4.6 inference  
**Details:**
- Complete guide for deploying GLM-4.6 on multi-node GH200
- Step-by-step instructions
- Troubleshooting guide
- Ready to use on GPU nodes

---

## Files to Exclude (Do NOT Push)

These are local development files that shouldn't be committed:

- `.cursorindexingignore` - Cursor IDE config
- `.specstory/` - Cursor IDE data
- `create_followup_task.py` - Temporary script (can delete)
- `PRD.md`, `PRD_REVIEW.md`, `PRD_v2.md` - Local PRD files (if not needed)

---

## Git Commands to Push

```bash
# 1. Stage all important changes
git add src/core/worktree_manager.py
git add src/core/simple_config.py
git add src/agents/manager.py
git add hephaestus_config.yaml
git add scripts/management/
git add BUG_REPORT_worktree_parent_commit.md
git add LOCAL_INFERENCE_IMPLEMENTATION_PLAN.md
git add CHANGES_TO_PUSH.md

# 2. Commit with descriptive message
git commit -m "feat: Add worktree parent commit fix and management scripts

- Fix: Handle non-existent parent worktrees gracefully with database fallback
- Add: Management scripts for workflow monitoring and restart
- Add: GLM configuration options for flexible provider setup
- Add: Bug report and local inference implementation plan
- Fix: Preserve knowledge inheritance when parent worktrees cleaned up"

# 3. Push to fork
git push fork main

# Or if you want to create a feature branch:
git checkout -b feature/worktree-fixes-and-management-scripts
git push fork feature/worktree-fixes-and-management-scripts
```

---

## Commit Message Template

```
feat: Add worktree parent commit fix and management scripts

Core Fixes:
- Fix agent creation failure when parent worktree cleaned up
- Add _get_parent_commit_from_database() with 4 fallback strategies
- Preserve knowledge inheritance using parent branch/commit from DB

Management Tools:
- Add hephaestus.sh for service management (Qdrant, frontend, server, monitor)
- Add check_workflow_status.py for workflow monitoring
- Add restart_stalled_workflow.py for task recovery
- Add cleanup_stale_worktrees.py for worktree maintenance

Configuration:
- Add glm_api_base_url and glm_model_name options
- Support configurable GLM endpoints (Novita AI, z.ai, custom)

Documentation:
- Add BUG_REPORT_worktree_parent_commit.md for upstream
- Add LOCAL_INFERENCE_IMPLEMENTATION_PLAN.md for GPU nodes
```

---

## Verification After Push

After pushing, verify:
- [ ] All files visible on GitHub fork
- [ ] Management scripts are executable
- [ ] Code changes don't break existing functionality
- [ ] Configuration file is valid YAML

---

## Next Steps After Push

1. **On GPU Nodes:**
   - Clone or pull the fork
   - Follow `LOCAL_INFERENCE_IMPLEMENTATION_PLAN.md`
   - Set up local GLM-4.6 inference

2. **Optional:**
   - Create PR to upstream with worktree fix
   - Share management scripts with community
   - Document local inference setup in fork

---

**Last Updated:** 2025-11-14

