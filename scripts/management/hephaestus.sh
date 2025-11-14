#!/bin/bash
# Hephaestus Start/Restart Script
# Usage: ./hephaestus.sh [start|restart|stop|status]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

kill_hephaestus_processes() {
    print_info "Stopping existing Hephaestus processes..."
    
    # Kill processes on port 8000 (MCP server)
    local pids=$(lsof -ti :8000 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs kill -9 2>/dev/null || true
        print_success "Killed processes on port 8000"
    fi
    
    # Kill processes on port 5173 (Frontend)
    local frontend_pids=$(lsof -ti :5173 2>/dev/null || true)
    if [ -n "$frontend_pids" ]; then
        echo "$frontend_pids" | xargs kill -9 2>/dev/null || true
        print_success "Killed processes on port 5173"
    fi
    
    # Kill monitor processes
    local monitor_pids=$(pgrep -f "run_monitor.py" 2>/dev/null || true)
    if [ -n "$monitor_pids" ]; then
        echo "$monitor_pids" | xargs kill -9 2>/dev/null || true
        print_success "Killed monitor processes"
    fi
    
    # Kill server processes
    local server_pids=$(pgrep -f "run_server.py" 2>/dev/null || true)
    if [ -n "$server_pids" ]; then
        echo "$server_pids" | xargs kill -9 2>/dev/null || true
        print_success "Killed server processes"
    fi
    
    # Kill frontend processes (npm/vite)
    local vite_pids=$(pgrep -f "vite.*frontend\|npm.*run.*dev" 2>/dev/null || true)
    if [ -n "$vite_pids" ]; then
        echo "$vite_pids" | xargs kill -9 2>/dev/null || true
        print_success "Killed frontend processes"
    fi
    
    # Give processes time to die
    sleep 1
}

stop_qdrant() {
    print_info "Stopping Qdrant..."
    if docker ps --format '{{.Names}}' | grep -q "^hephaestus-qdrant$"; then
        docker stop hephaestus-qdrant >/dev/null 2>&1 && print_success "Qdrant stopped" || print_warning "Failed to stop Qdrant"
    elif docker ps -a --format '{{.Names}}' | grep -q "^hephaestus-qdrant$"; then
        print_info "Qdrant container exists but is not running"
    else
        print_info "Qdrant container not found"
    fi
}

check_services() {
    print_info "Checking service status..."
    
    local server_running=false
    local monitor_running=false
    local frontend_running=false
    
    # Check if server is running (port 8000)
    if lsof -ti :8000 >/dev/null 2>&1; then
        server_running=true
        print_success "Server is running (port 8000)"
    else
        print_warning "Server is not running"
    fi
    
    # Check if monitor is running
    if pgrep -f "run_monitor.py" >/dev/null 2>&1; then
        monitor_running=true
        print_success "Monitor is running"
    else
        print_warning "Monitor is not running"
    fi
    
    # Check if frontend is running (port 5173)
    if lsof -ti :5173 >/dev/null 2>&1; then
        frontend_running=true
        print_success "Frontend is running (port 5173)"
    else
        print_warning "Frontend is not running"
    fi
    
    if [ "$server_running" = true ] && [ "$monitor_running" = true ] && [ "$frontend_running" = true ]; then
        return 0
    else
        return 1
    fi
}

start_services() {
    print_info "Starting Hephaestus services..."
    
    # Check if virtual environment exists
    if [ ! -d "venv" ]; then
        print_error "Virtual environment not found. Please run: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
        exit 1
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        print_warning ".env file not found. Some features may not work without API keys."
    fi
    
    # Check and start Qdrant if needed
    if ! curl -s http://localhost:6333/health >/dev/null 2>&1; then
        print_info "Starting Qdrant vector database..."
        if command -v docker >/dev/null 2>&1; then
            # Check if Qdrant container already exists
            if docker ps -a --format '{{.Names}}' | grep -q "^hephaestus-qdrant$"; then
                docker start hephaestus-qdrant >/dev/null 2>&1 || true
            else
                # Start Qdrant container
                docker run -d --name hephaestus-qdrant -p 6333:6333 qdrant/qdrant >/dev/null 2>&1 || {
                    print_warning "Failed to start Qdrant via docker. Trying docker-compose..."
                    if [ -f "docker-compose.yml" ] && command -v docker-compose >/dev/null 2>&1; then
                        docker-compose up -d qdrant >/dev/null 2>&1 || {
                            print_warning "Failed to start Qdrant. Please start manually:"
                            print_info "  docker run -d -p 6333:6333 qdrant/qdrant"
                            print_info "  or: docker-compose up -d qdrant"
                        }
                    else
                        print_warning "docker-compose not found. Please start Qdrant manually:"
                        print_info "  docker run -d -p 6333:6333 qdrant/qdrant"
                    fi
                }
            fi
            # Wait for Qdrant to be ready
            sleep 2
            local qdrant_attempts=0
            while [ $qdrant_attempts -lt 10 ]; do
                if curl -s http://localhost:6333/health >/dev/null 2>&1; then
                    print_success "Qdrant started successfully"
                    break
                fi
                qdrant_attempts=$((qdrant_attempts + 1))
                sleep 1
            done
            if [ $qdrant_attempts -eq 10 ]; then
                print_warning "Qdrant did not become healthy. Continuing anyway..."
            fi
        else
            print_warning "Docker not found. Qdrant must be started manually:"
            print_info "  docker run -d -p 6333:6333 qdrant/qdrant"
        fi
    else
        print_success "Qdrant is already running"
    fi
    
    # Ensure logs directory exists
    mkdir -p logs
    
    # Validate configuration
    print_info "Validating configuration..."
    if ! python3 -c "from src.core.simple_config import get_config; config = get_config(); config.validate()" 2>/dev/null; then
        print_error "Configuration validation failed. Please check hephaestus_config.yaml"
        print_info "Common issues:"
        print_info "  - Invalid paths in 'paths.project_root' or 'git.main_repo_path'"
        print_info "  - Missing API keys in .env file"
        exit 1
    fi
    
    # Start server in background
    print_info "Starting MCP server..."
    nohup python3 run_server.py > logs/server_startup.log 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 3
    
    # Check if process is still running (might have failed immediately)
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        print_error "Server process died immediately. Check logs/server_startup.log for details."
        if [ -f "logs/server_startup.log" ]; then
            print_info "Last 10 lines of server log:"
            tail -10 logs/server_startup.log
        fi
        exit 1
    fi
    
    # Check if server is responding
    local max_attempts=10
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            print_success "Server is healthy"
            break
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_error "Server did not become healthy after $max_attempts attempts"
        exit 1
    fi
    
    # Start monitor in background
    print_info "Starting monitor..."
    nohup python3 run_monitor.py > logs/monitor.log 2>&1 &
    MONITOR_PID=$!
    
    # Wait for monitor to start
    sleep 2
    
    # Check if monitor started successfully
    if ! kill -0 $MONITOR_PID 2>/dev/null; then
        print_warning "Monitor may have failed to start. Check logs for details."
    else
        print_success "Monitor started (PID: $MONITOR_PID)"
    fi
    
    # Start frontend if directory exists
    if [ -d "frontend" ]; then
        print_info "Starting frontend..."
        if command -v npm >/dev/null 2>&1; then
            cd frontend
            # Check if node_modules exists
            if [ ! -d "node_modules" ]; then
                print_warning "node_modules not found. Installing dependencies..."
                npm install >/dev/null 2>&1 || {
                    print_error "Failed to install frontend dependencies"
                    cd ..
                    print_warning "Frontend will not start. Run 'cd frontend && npm install' manually"
                }
            fi
            
            # Start frontend in background
            nohup npm run dev > ../logs/frontend.log 2>&1 &
            FRONTEND_PID=$!
            cd ..
            
            # Wait for frontend to start
            sleep 3
            
            # Check if frontend is responding
            local frontend_attempts=0
            while [ $frontend_attempts -lt 10 ]; do
                if curl -s http://localhost:5173 >/dev/null 2>&1; then
                    print_success "Frontend started successfully (PID: $FRONTEND_PID)"
                    break
                fi
                frontend_attempts=$((frontend_attempts + 1))
                sleep 1
            done
            
            if [ $frontend_attempts -eq 10 ]; then
                print_warning "Frontend did not become responsive. Check logs/frontend.log for details."
            fi
        else
            print_warning "npm not found. Frontend will not start."
            print_info "Install Node.js and npm, then run: cd frontend && npm install && npm run dev"
        fi
    else
        print_info "Frontend directory not found. Skipping frontend startup."
    fi
    
    print_success "Hephaestus services started successfully"
    print_info "Server PID: $SERVER_PID"
    print_info "Monitor PID: $MONITOR_PID"
    print_info "Server URL: http://localhost:8000"
    print_info "Frontend URL: http://localhost:5173"
    print_info "Health check: curl http://localhost:8000/health"
}

stop_services() {
    print_info "Stopping Hephaestus services..."
    kill_hephaestus_processes
    
    # Optionally stop Qdrant (commented out by default - Qdrant is often shared)
    # Uncomment the next line if you want to stop Qdrant when stopping Hephaestus
    # stop_qdrant
    
    print_success "All Hephaestus services stopped"
}

show_status() {
    echo ""
    echo "=========================================="
    echo "Hephaestus Service Status"
    echo "=========================================="
    echo ""
    
    # Server status
    if lsof -ti :8000 >/dev/null 2>&1; then
        local server_pid=$(lsof -ti :8000 | head -1)
        print_success "Server: RUNNING (PID: $server_pid, Port: 8000)"
        
        # Check health
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            print_success "Server health: OK"
        else
            print_warning "Server health: UNRESPONSIVE"
        fi
    else
        print_error "Server: NOT RUNNING"
    fi
    
    echo ""
    
    # Monitor status
    local monitor_pids=$(pgrep -f "run_monitor.py" 2>/dev/null || true)
    if [ -n "$monitor_pids" ]; then
        print_success "Monitor: RUNNING (PIDs: $monitor_pids)"
    else
        print_error "Monitor: NOT RUNNING"
    fi
    
    echo ""
    
    # Frontend status
    if lsof -ti :5173 >/dev/null 2>&1; then
        local frontend_pid=$(lsof -ti :5173 | head -1)
        print_success "Frontend: RUNNING (PID: $frontend_pid, Port: 5173)"
        if curl -s http://localhost:5173 >/dev/null 2>&1; then
            print_success "Frontend health: OK"
        else
            print_warning "Frontend health: UNRESPONSIVE"
        fi
    else
        print_error "Frontend: NOT RUNNING"
        if [ -d "frontend" ]; then
            print_info "Start frontend with: cd frontend && npm run dev"
        fi
    fi
    
    echo ""
    
    # Check Qdrant
    if curl -s http://localhost:6333/health >/dev/null 2>&1; then
        print_success "Qdrant: RUNNING (Port: 6333)"
    else
        print_warning "Qdrant: NOT RUNNING (required for vector store)"
        print_info "Start Qdrant with: docker run -d -p 6333:6333 qdrant/qdrant"
        print_info "Or use docker-compose: docker-compose up -d qdrant"
    fi
    
    echo ""
    echo "=========================================="
}

# Main script logic
ACTION="${1:-restart}"

case "$ACTION" in
    start)
        if check_services >/dev/null 2>&1; then
            print_warning "Services are already running"
            show_status
            exit 0
        fi
        start_services
        sleep 2
        show_status
        ;;
    restart)
        print_info "Restarting Hephaestus..."
        kill_hephaestus_processes
        sleep 2
        start_services
        sleep 2
        show_status
        ;;
    stop)
        stop_services
        show_status
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 [start|restart|stop|status]"
        echo ""
        echo "Commands:"
        echo "  start   - Start Hephaestus services (if not running)"
        echo "  restart - Stop and start Hephaestus services"
        echo "  stop    - Stop all Hephaestus services"
        echo "  status  - Show status of all services"
        exit 1
        ;;
esac

