#!/usr/bin/env python3
"""Restart agents that were running when API limit was hit.

This script:
1. Finds all agents with status 'working' or 'running'
2. Terminates them via API (which marks their tasks as failed)
3. Restarts their tasks via API (which creates new agents with GLM-4.6 config)
"""

import asyncio
import httpx
from src.core.database import DatabaseManager, Agent, Task

API_BASE_URL = "http://localhost:8000"

async def restart_stalled_agents():
    """Restart agents that were running when API limit was hit."""
    db_manager = DatabaseManager()
    session = db_manager.get_session()
    
    try:
        # Find all active agents
        active_agents = session.query(Agent).filter(
            Agent.status.in_(['working', 'running', 'stuck'])
        ).all()
        
        if not active_agents:
            print("No active agents found.")
            return
        
        print(f"Found {len(active_agents)} active agent(s) to restart:")
        task_ids_to_restart = []
        for agent in active_agents:
            task = session.query(Task).filter_by(id=agent.current_task_id).first()
            if task:
                task_desc = (task.raw_description or task.enriched_description or "Unknown task")[:50]
            else:
                task_desc = "Unknown task"
            print(f"  - Agent {agent.id[:8]}: {agent.status} (Task: {task_desc}...)")
            if agent.current_task_id:
                task_ids_to_restart.append(agent.current_task_id)
        
        print(f"\nStep 1: Terminating {len(active_agents)} agent(s)...")
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Terminate all agents
            for agent in active_agents:
                try:
                    print(f"  Terminating agent {agent.id[:8]}...")
                    response = await client.post(
                        f"{API_BASE_URL}/api/terminate_agent",
                        json={
                            "agent_id": agent.id,
                            "reason": "API limit reached, restarting with GLM-4.6"
                        }
                    )
                    response.raise_for_status()
                    print(f"    ✓ Agent terminated")
                except Exception as e:
                    print(f"    ✗ Error terminating agent {agent.id[:8]}: {e}")
            
            # Wait a moment for termination to complete
            await asyncio.sleep(2)
            
            print(f"\nStep 2: Restarting {len(task_ids_to_restart)} task(s)...")
            
            # Restart all tasks
            for task_id in task_ids_to_restart:
                try:
                    print(f"  Restarting task {task_id[:8]}...")
                    response = await client.post(
                        f"{API_BASE_URL}/api/restart_task",
                        json={"task_id": task_id}
                    )
                    response.raise_for_status()
                    result = response.json()
                    if result.get("success"):
                        new_agent_id = result.get("agent_id", "unknown")
                        print(f"    ✓ Task restarted with new agent {new_agent_id[:8]}")
                    else:
                        print(f"    ✗ Failed to restart: {result.get('message', 'Unknown error')}")
                except httpx.HTTPStatusError as e:
                    try:
                        error_detail = e.response.json().get("detail", e.response.text)
                    except:
                        error_detail = e.response.text
                    if e.response.status_code == 400:
                        print(f"    ⚠ Task not ready to restart: {error_detail}")
                    else:
                        print(f"    ✗ HTTP {e.response.status_code} error: {error_detail}")
                except httpx.RequestError as e:
                    print(f"    ✗ Request error: {e}")
                except Exception as e:
                    print(f"    ✗ Error restarting task {task_id[:8]}: {e}")
                    import traceback
                    traceback.print_exc()
        
        print(f"\n✓ Completed! Processed {len(task_ids_to_restart)} task(s).")
        print("Note: New agents will use GLM-4.6 with Novita AI.")
        
    finally:
        session.close()

if __name__ == "__main__":
    asyncio.run(restart_stalled_agents())

