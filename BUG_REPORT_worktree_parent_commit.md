# Bug Report: Agent Creation Fails When Parent Worktree Was Cleaned Up

## Summary
When creating a new agent for a task that was created by a parent agent, Hephaestus fails with an unhelpful error if the parent agent's worktree was cleaned up but the database record still exists.

## Environment
- Hephaestus version: Latest main branch
- Python version: 3.x
- OS: macOS/Linux

## Steps to Reproduce
1. Start a workflow with multiple phases where agents create tasks for child agents
2. Allow parent agents to complete and their worktrees to be cleaned up (either automatically or manually)
3. Database records for `AgentWorktree` remain with status `cleaned`, `merged`, or `abandoned`
4. When a new agent is created for a task created by one of these parent agents, the system attempts to inherit from the parent's worktree
5. The `_prepare_parent_commit` method in `src/core/worktree_manager.py` finds the parent worktree record but the actual worktree directory no longer exists on disk
6. The code crashes when trying to open the non-existent repository path

## Expected Behavior
When a parent worktree has been cleaned up, the system should gracefully fall back to using the main branch instead of failing.

## Actual Behavior
Agent creation fails with an error message showing only the worktree path:
```
Agent creation failed: /tmp/hephaestus_worktrees/wt_<agent-id>
```

The underlying exception (from `Repo(parent_worktree.worktree_path)`) is not properly handled, causing the entire agent creation process to fail.

## Root Cause
In `src/core/worktree_manager.py`, the `_prepare_parent_commit` method (around line 1087-1118) does not check if the parent worktree path exists before attempting to open it with `Repo()`. When worktrees are cleaned up:

1. The `cleanup_worktree` method removes the worktree directory and marks the record as `cleaned` in the database
2. The database record remains for historical tracking
3. When a new agent tries to inherit from this parent, `_prepare_parent_commit` finds the record but the path doesn't exist
4. `Repo(parent_worktree.worktree_path)` raises an exception that isn't properly caught
5. The exception propagates up and causes agent creation to fail

## Proposed Fix
Add defensive checks in `_prepare_parent_commit`:

1. Check if the parent worktree path exists on disk before attempting to open it
2. Wrap `Repo()` call in try/except to handle any exceptions
3. Return `None` if the path doesn't exist or can't be opened, which causes the code to fall back to main branch
4. Add informative logging to help diagnose the issue

## Impact
- **Severity**: Medium-High
- **Frequency**: Occurs whenever parent agents complete and their worktrees are cleaned up before child agents are created
- **Workaround**: Manually clean up stale worktree records from the database or restart the workflow

## Additional Context
This bug was discovered when running a multi-phase workflow where:
- Phase 1 agents created tasks for Phase 2
- Phase 1 agents completed and their worktrees were cleaned up
- Phase 2 agents failed to start because they couldn't inherit from non-existent parent worktrees

The fix has been tested and successfully resolves the issue by gracefully falling back to the main branch when parent worktrees are unavailable.

## Suggested Code Changes
```python
# In src/core/worktree_manager.py, _prepare_parent_commit method

# After line 1098 (after finding parent_worktree):
# Check if parent worktree path actually exists
if not Path(parent_worktree.worktree_path).exists():
    logger.warning(
        f"[WORKTREE] Parent worktree path does not exist: {parent_worktree.worktree_path}\n"
        f"  Parent worktree status: {parent_worktree.merge_status}\n"
        f"  This likely means the worktree was cleaned up. Falling back to main branch."
    )
    return None

# Open parent worktree repository
try:
    parent_repo = Repo(parent_worktree.worktree_path)
except Exception as e:
    logger.warning(
        f"[WORKTREE] Failed to open parent worktree repository: {e}\n"
        f"  Path: {parent_worktree.worktree_path}\n"
        f"  Falling back to main branch."
    )
    return None
```

