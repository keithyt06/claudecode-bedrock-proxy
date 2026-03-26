#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PIDFILE="$SCRIPT_DIR/proxy.pid"
LOGFILE="$SCRIPT_DIR/proxy.log"
WATCHDOG_PIDFILE="$SCRIPT_DIR/watchdog.pid"

export AWS_REGION="${AWS_REGION:-ap-northeast-1}"

# Resolve binary: pre-built download > go build > Python fallback
resolve_binary() {
    # 1. Pre-built binary (from GitHub Releases)
    for name in bedrock-effort-proxy-linux-amd64 bedrock-effort-proxy bedrock-proxy-go; do
        if [ -x "$SCRIPT_DIR/$name" ]; then
            echo "$SCRIPT_DIR/$name"
            return 0
        fi
    done
    # 2. Build from source if Go available
    if command -v go &>/dev/null && [ -f "$SCRIPT_DIR/main.go" ]; then
        echo "Building Go proxy..." >&2
        go build -o "$SCRIPT_DIR/bedrock-proxy-go" "$SCRIPT_DIR" && echo "$SCRIPT_DIR/bedrock-proxy-go"
        return $?
    fi
    # 3. Python fallback (deprecated)
    if [ -f "$SCRIPT_DIR/deprecated/proxy.py" ]; then
        echo "python3 $SCRIPT_DIR/deprecated/proxy.py"
        return 0
    elif [ -f "$SCRIPT_DIR/proxy.py" ]; then
        echo "python3 $SCRIPT_DIR/proxy.py"
        return 0
    fi
    return 1
}

is_running() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

wait_healthy() {
    for _ in $(seq 1 20); do
        curl -sf http://127.0.0.1:8888/health > /dev/null 2>&1 && return 0
        sleep 0.25
    done
    return 1
}

start_watchdog() {
    if [ -f "$SCRIPT_DIR/watchdog.sh" ] && ! is_running "$WATCHDOG_PIDFILE"; then
        nohup bash "$SCRIPT_DIR/watchdog.sh" >> "$LOGFILE" 2>&1 &
        sleep 0.5
        echo "Watchdog started (PID: $(cat "$WATCHDOG_PIDFILE" 2>/dev/null))"
    fi
}

# Already fully running
if is_running "$PIDFILE" && is_running "$WATCHDOG_PIDFILE"; then
    echo "Proxy already running (PID: $(cat "$PIDFILE"), watchdog: $(cat "$WATCHDOG_PIDFILE"))"
    exit 0
fi

# Proxy running but no watchdog
if is_running "$PIDFILE"; then
    echo "Proxy running (PID: $(cat "$PIDFILE")), attaching watchdog..."
    start_watchdog
    exit 0
fi

# Resolve binary
BINARY=$(resolve_binary)
if [ -z "$BINARY" ]; then
    echo "ERROR: No proxy binary found. Download from GitHub Releases or install Go to build."
    exit 1
fi

# Fresh start
echo "Starting Bedrock Effort Max Proxy..."
: > "$LOGFILE"
nohup $BINARY >> "$LOGFILE" 2>&1 &
PROXY_PID=$!
disown $PROXY_PID
echo $PROXY_PID > "$PIDFILE"

if wait_healthy; then
    echo "Proxy started (PID: $(cat "$PIDFILE"))"
    curl -s http://127.0.0.1:8888/health | python3 -m json.tool 2>/dev/null || curl -s http://127.0.0.1:8888/health
    start_watchdog
    exit 0
fi

echo "ERROR: Proxy failed to start. Last 20 lines of log:"
tail -20 "$LOGFILE"
kill "$(cat "$PIDFILE")" 2>/dev/null || true
rm -f "$PIDFILE"
exit 1
