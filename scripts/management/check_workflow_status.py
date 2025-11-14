#!/usr/bin/env python3
"""Check Hephaestus workflow completion status.

This script provides multiple ways to determine if a workflow is complete:
1. Check workflow status via API
2. Check phase completion status
3. Check task completion statistics
4. Check for validated workflow results
"""

import sys
import json
from typing import Dict, Any, Optional
from pathlib import Path

try:
    import httpx
    HAS_HTTPX = True
except ImportError:
    try:
        import urllib.request
        HAS_HTTPX = False
    except ImportError:
        HAS_HTTPX = None

# Add repo root to path (go up two levels from scripts/management/)
repo_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(repo_root))

from src.core.database import DatabaseManager, Workflow, Phase, Task, WorkflowResult


def check_workflow_completion_via_api(workflow_id: Optional[str] = None) -> Dict[str, Any]:
    """Check workflow completion via API endpoint."""
    try:
        if HAS_HTTPX:
            response = httpx.get("http://localhost:8000/api/workflow", timeout=5.0)
            response.raise_for_status()
            workflow_info = response.json()
        elif HAS_HTTPX is False:
            # Use urllib as fallback
            import urllib.request
            req = urllib.request.Request("http://localhost:8000/api/workflow")
            with urllib.request.urlopen(req, timeout=5.0) as response:
                workflow_info = json.loads(response.read().decode())
        else:
            return {
                "complete": False,
                "error": "No HTTP library available (httpx or urllib)",
                "reason": "Cannot check via API"
            }
        
        if workflow_info.get("status") == "inactive":
            return {
                "complete": True,
                "reason": "No active workflow",
                "workflow_info": workflow_info
            }
        
        if workflow_info.get("status") == "completed":
            return {
                "complete": True,
                "reason": "Workflow marked as completed",
                "workflow_info": workflow_info
            }
        
        # Check if all phases are complete
        phases = workflow_info.get("phases", [])
        all_phases_complete = all(
            phase.get("completed_tasks", 0) > 0 and 
            phase.get("active_tasks", 0) == 0 and
            phase.get("pending_tasks", 0) == 0
            for phase in phases
        )
        
        if all_phases_complete and len(phases) > 0:
            return {
                "complete": True,
                "reason": "All phases complete (all tasks done)",
                "workflow_info": workflow_info
            }
        
        # Calculate progress
        total_tasks = sum(p.get("total_tasks", 0) for p in phases)
        completed_tasks = sum(p.get("completed_tasks", 0) for p in phases)
        active_tasks = sum(p.get("active_tasks", 0) for p in phases)
        pending_tasks = sum(p.get("pending_tasks", 0) for p in phases)
        
        return {
            "complete": False,
            "reason": "Workflow still in progress",
            "workflow_info": workflow_info,
            "progress": {
                "total_tasks": total_tasks,
                "completed_tasks": completed_tasks,
                "active_tasks": active_tasks,
                "pending_tasks": pending_tasks,
                "completion_percentage": (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
            }
        }
        
    except Exception as e:
        return {
            "complete": False,
            "error": str(e),
            "reason": "Failed to check workflow status"
        }


def check_workflow_completion_via_db(workflow_id: Optional[str] = None) -> Dict[str, Any]:
    """Check workflow completion via database."""
    db_manager = DatabaseManager()
    session = db_manager.get_session()
    
    try:
        # Get active workflow
        if workflow_id:
            workflow = session.query(Workflow).filter_by(id=workflow_id).first()
        else:
            workflow = session.query(Workflow).filter(
                Workflow.status.in_(["active", "paused"])
            ).first()
        
        if not workflow:
            return {
                "complete": True,
                "reason": "No active workflow found",
                "workflow_id": None
            }
        
        # Check workflow status
        if workflow.status == "completed":
            return {
                "complete": True,
                "reason": "Workflow marked as completed",
                "workflow_id": workflow.id,
                "workflow_name": workflow.name,
                "status": workflow.status
            }
        
        # Check for validated workflow results
        validated_result = session.query(WorkflowResult).filter_by(
            workflow_id=workflow.id,
            status="validated"
        ).first()
        
        if validated_result:
            return {
                "complete": True,
                "reason": "Workflow has validated result",
                "workflow_id": workflow.id,
                "workflow_name": workflow.name,
                "result_id": validated_result.id,
                "result_summary": validated_result.summary[:100] if validated_result.summary else None
            }
        
        # Check phase completion
        phases = session.query(Phase).filter_by(
            workflow_id=workflow.id
        ).order_by(Phase.order).all()
        
        phase_statuses = []
        all_phases_complete = True
        
        for phase in phases:
            total_tasks = session.query(Task).filter_by(phase_id=phase.id).count()
            completed_tasks = session.query(Task).filter_by(
                phase_id=phase.id, status="done"
            ).count()
            active_tasks = session.query(Task).filter_by(phase_id=phase.id).filter(
                Task.status.in_(["assigned", "in_progress"])
            ).count()
            pending_tasks = session.query(Task).filter_by(
                phase_id=phase.id, status="pending"
            ).count()
            
            phase_complete = (
                completed_tasks > 0 and 
                active_tasks == 0 and 
                pending_tasks == 0
            )
            
            if not phase_complete:
                all_phases_complete = False
            
            phase_statuses.append({
                "phase_id": phase.id,
                "phase_order": phase.order,
                "phase_name": phase.name,
                "total_tasks": total_tasks,
                "completed_tasks": completed_tasks,
                "active_tasks": active_tasks,
                "pending_tasks": pending_tasks,
                "complete": phase_complete
            })
        
        if all_phases_complete and len(phases) > 0:
            return {
                "complete": True,
                "reason": "All phases complete (all tasks done)",
                "workflow_id": workflow.id,
                "workflow_name": workflow.name,
                "phases": phase_statuses
            }
        
        # Calculate overall progress
        total_tasks = sum(p["total_tasks"] for p in phase_statuses)
        completed_tasks = sum(p["completed_tasks"] for p in phase_statuses)
        active_tasks = sum(p["active_tasks"] for p in phase_statuses)
        pending_tasks = sum(p["pending_tasks"] for p in phase_statuses)
        
        return {
            "complete": False,
            "reason": "Workflow still in progress",
            "workflow_id": workflow.id,
            "workflow_name": workflow.name,
            "status": workflow.status,
            "phases": phase_statuses,
            "progress": {
                "total_tasks": total_tasks,
                "completed_tasks": completed_tasks,
                "active_tasks": active_tasks,
                "pending_tasks": pending_tasks,
                "completion_percentage": (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
            }
        }
        
    finally:
        session.close()


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Check Hephaestus workflow completion status")
    parser.add_argument("--workflow-id", help="Specific workflow ID to check")
    parser.add_argument("--method", choices=["api", "db", "both"], default="both",
                       help="Method to use for checking (default: both)")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    
    args = parser.parse_args()
    
    results = {}
    
    if args.method in ["api", "both"]:
        results["api"] = check_workflow_completion_via_api(args.workflow_id)
    
    if args.method in ["db", "both"]:
        results["db"] = check_workflow_completion_via_db(args.workflow_id)
    
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        # Human-readable output
        for method, result in results.items():
            print(f"\n{'='*60}")
            print(f"Method: {method.upper()}")
            print(f"{'='*60}")
            
            if result.get("complete"):
                print(f"✅ WORKFLOW IS COMPLETE")
                print(f"Reason: {result.get('reason', 'Unknown')}")
            else:
                print(f"⏳ WORKFLOW IN PROGRESS")
                print(f"Reason: {result.get('reason', 'Unknown')}")
            
            if "workflow_id" in result:
                print(f"Workflow ID: {result['workflow_id']}")
            if "workflow_name" in result:
                print(f"Workflow Name: {result['workflow_name']}")
            if "status" in result:
                print(f"Status: {result['status']}")
            
            if "progress" in result:
                prog = result["progress"]
                print(f"\nProgress:")
                print(f"  Total Tasks: {prog['total_tasks']}")
                print(f"  Completed: {prog['completed_tasks']}")
                print(f"  Active: {prog['active_tasks']}")
                print(f"  Pending: {prog['pending_tasks']}")
                print(f"  Completion: {prog['completion_percentage']:.1f}%")
            
            if "phases" in result:
                print(f"\nPhase Status:")
                for phase in result["phases"]:
                    status_icon = "✅" if phase.get("complete") else "⏳"
                    print(f"  {status_icon} Phase {phase['phase_order']}: {phase['phase_name']}")
                    print(f"     Tasks: {phase['completed_tasks']}/{phase['total_tasks']} done, "
                          f"{phase['active_tasks']} active, {phase['pending_tasks']} pending")
        
        print(f"\n{'='*60}")
        print("\n💡 TIP: Monitor progress at http://localhost:5173/")
        print("💡 TIP: Check API directly: curl http://localhost:8000/api/workflow")


if __name__ == "__main__":
    main()

