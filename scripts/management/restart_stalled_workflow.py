#!/usr/bin/env python3
"""Restart stalled Hephaestus workflow by resetting failed/blocked tasks and enqueuing them.

This script:
1. Finds failed tasks (due to worktree issues or other errors)
2. Resets them to 'queued' status
3. Enqueues them so the queue processor picks them up
4. Optionally handles blocked tasks
"""

import sys
import asyncio
from pathlib import Path

# Add repo root to path (go up two levels from scripts/management/)
repo_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(repo_root))

from src.core.database import DatabaseManager, Task
from src.core.simple_config import get_config
from src.services.queue_service import QueueService


def restart_failed_tasks():
    """Reset failed tasks and enqueue them."""
    db_manager = DatabaseManager()
    config = get_config()
    session = db_manager.get_session()
    queue_service = QueueService(db_manager, max_concurrent_agents=config.max_concurrent_agents)
    
    try:
        # Find failed tasks
        failed_tasks = session.query(Task).filter_by(status='failed').all()
        
        if not failed_tasks:
            print("No failed tasks found.")
            return
        
        print(f"Found {len(failed_tasks)} failed task(s):")
        for task in failed_tasks:
            desc = (task.raw_description or task.enriched_description or "N/A")[:60]
            print(f"  - Task {task.id[:8]}: {desc}...")
            if task.failure_reason:
                print(f"    Failure: {task.failure_reason[:80]}...")
        
        print(f"\nResetting {len(failed_tasks)} task(s) to queued status...")
        
        task_ids = []
        for task in failed_tasks:
            # Reset task status
            task.status = 'queued'
            task.failure_reason = None
            task.assigned_agent_id = None
            task.started_at = None
            task.completed_at = None
            task_ids.append(task.id)
        
        session.commit()
        print(f"✓ Reset {len(task_ids)} task(s) to queued status")
        
        # Enqueue the tasks
        print(f"\nEnqueuing {len(task_ids)} task(s)...")
        for task_id in task_ids:
            try:
                queue_service.enqueue_task(task_id)
                print(f"  ✓ Enqueued task {task_id[:8]}")
            except Exception as e:
                print(f"  ✗ Failed to enqueue task {task_id[:8]}: {e}")
        
        print(f"\n✓ Completed! {len(task_ids)} task(s) are now queued and will be picked up by the queue processor.")
        print("The queue processor runs every 60 seconds and will assign agents to these tasks.")
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        session.rollback()
    finally:
        session.close()


def check_blocked_tasks():
    """Check what tasks are blocked and why."""
    db_manager = DatabaseManager()
    session = db_manager.get_session()
    
    try:
        blocked_tasks = session.query(Task).filter_by(status='blocked').all()
        
        if not blocked_tasks:
            print("No blocked tasks found.")
            return
        
        print(f"\nFound {len(blocked_tasks)} blocked task(s):")
        for task in blocked_tasks[:10]:  # Show first 10
            desc = (task.raw_description or task.enriched_description or "N/A")[:60]
            print(f"  - Task {task.id[:8]}: {desc}...")
            if hasattr(task, 'blocked_by') and task.blocked_by:
                print(f"    Blocked by: {task.blocked_by}")
        
        if len(blocked_tasks) > 10:
            print(f"  ... and {len(blocked_tasks) - 10} more")
        
        print("\nNote: Blocked tasks are waiting for dependencies. They will be unblocked automatically when dependencies complete.")
        
    except Exception as e:
        print(f"Error checking blocked tasks: {e}")
    finally:
        session.close()


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Restart stalled Hephaestus workflow")
    parser.add_argument("--check-blocked", action="store_true", 
                       help="Also check blocked tasks")
    parser.add_argument("--unblock", action="store_true",
                       help="Attempt to unblock blocked tasks (use with caution)")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("Hephaestus Workflow Restart")
    print("=" * 60)
    
    restart_failed_tasks()
    
    if args.check_blocked:
        check_blocked_tasks()
    
    if args.unblock:
        print("\n⚠️  Unblocking blocked tasks is not yet implemented.")
        print("Blocked tasks should be automatically unblocked when dependencies complete.")
    
    print("\n" + "=" * 60)
    print("💡 Monitor progress:")
    print("   - Frontend: http://localhost:5173/")
    print("   - API: curl http://localhost:8000/api/workflow")
    print("   - Status: python3 check_workflow_status.py")
    print("=" * 60)


if __name__ == "__main__":
    main()

