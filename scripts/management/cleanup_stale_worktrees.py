#!/usr/bin/env python3
"""Clean up stale worktree records from the database.

Stale worktrees are worktree records that exist in the database but:
- Don't exist on disk
- Aren't in git's worktree list
- Are associated with terminated agents

This script marks them as 'cleaned' in the database.
"""

import sys
from pathlib import Path

# Add repo root to path
repo_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(repo_root))

from src.core.database import DatabaseManager, AgentWorktree, Agent
import git
import os


def cleanup_stale_worktrees(dry_run=True):
    """Clean up stale worktree records.
    
    Args:
        dry_run: If True, only report what would be cleaned, don't actually clean
    """
    db_manager = DatabaseManager()
    session = db_manager.get_session()
    
    try:
        # Get git repo
        from src.core.simple_config import get_config
        config = get_config()
        repo = git.Repo(os.path.expanduser(config.main_repo_path))
        git_worktrees = repo.git.worktree('list', '--porcelain').split('worktree ')
        
        # Find stale worktrees
        worktrees = session.query(AgentWorktree).filter_by(merge_status='active').all()
        
        stale_worktrees = []
        for wt in worktrees:
            exists_on_disk = os.path.exists(wt.worktree_path)
            in_git_list = any(wt.worktree_path in w for w in git_worktrees)
            
            if not exists_on_disk or not in_git_list:
                # Check if agent is terminated
                agent = session.query(Agent).filter_by(id=wt.agent_id).first()
                agent_status = agent.status if agent else 'NOT_FOUND'
                
                stale_worktrees.append({
                    'worktree': wt,
                    'exists_on_disk': exists_on_disk,
                    'in_git_list': in_git_list,
                    'agent_status': agent_status
                })
        
        if not stale_worktrees:
            print("No stale worktrees found.")
            return
        
        print(f"Found {len(stale_worktrees)} stale worktree(s):\n")
        
        for item in stale_worktrees:
            wt = item['worktree']
            print(f"  Worktree: {wt.worktree_path}")
            print(f"    Agent ID: {wt.agent_id}")
            print(f"    Branch: {wt.branch_name}")
            print(f"    Exists on disk: {item['exists_on_disk']}")
            print(f"    In git list: {item['in_git_list']}")
            print(f"    Agent status: {item['agent_status']}")
            print()
        
        if dry_run:
            print("DRY RUN: Would mark these worktrees as 'cleaned'")
            print("Run with --execute to actually clean them up")
        else:
            print("Cleaning up stale worktrees...")
            
            # Mark as cleaned
            for item in stale_worktrees:
                wt = item['worktree']
                wt.merge_status = 'cleaned'
                print(f"  ✓ Marked {wt.worktree_path} as cleaned")
            
            session.commit()
            print(f"\n✓ Cleaned up {len(stale_worktrees)} stale worktree(s)")
            
            # Also try to clean up branches if they exist
            print("\nCleaning up orphaned branches...")
            branches_to_delete = []
            for item in stale_worktrees:
                wt = item['worktree']
                try:
                    # Check if branch exists
                    if wt.branch_name in [b.name for b in repo.branches]:
                        branches_to_delete.append(wt.branch_name)
                except Exception as e:
                    print(f"  ⚠ Could not check branch {wt.branch_name}: {e}")
            
            if branches_to_delete:
                print(f"Found {len(branches_to_delete)} orphaned branch(es) to clean:")
                for branch in branches_to_delete:
                    try:
                        repo.git.branch('-D', branch)
                        print(f"  ✓ Deleted branch: {branch}")
                    except Exception as e:
                        print(f"  ✗ Failed to delete branch {branch}: {e}")
            else:
                print("No orphaned branches found")
    
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        session.rollback()
    finally:
        session.close()


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Clean up stale worktree records")
    parser.add_argument("--execute", action="store_true",
                       help="Actually clean up (default is dry-run)")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("Stale Worktree Cleanup")
    print("=" * 60)
    print()
    
    cleanup_stale_worktrees(dry_run=not args.execute)
    
    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()

