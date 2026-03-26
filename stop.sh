#!/bin/bash
cd "$(dirname "$0")"

# Stop watchdog first
if [ -f watchdog.pid ]; then
    WPID=$(cat watchdog.pid)
    if kill -0 "$WPID" 2>/dev/null; then
        kill "$WPID"
        echo "Watchdog stopped (PID: $WPID)"
    else
        echo "Watchdog $WPID not running"
    fi
    rm -f watchdog.pid
fi

# Stop proxy
if [ -f proxy.pid ]; then
    PID=$(cat proxy.pid)
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo "Proxy stopped (PID: $PID)"
    else
        echo "Proxy $PID not running"
    fi
    rm -f proxy.pid
else
    echo "No PID file found"
    pkill -f "bedrock-proxy-go|bedrock-effort-proxy|python3.*proxy.py" 2>/dev/null && echo "Killed orphan proxy process" || true
fi
