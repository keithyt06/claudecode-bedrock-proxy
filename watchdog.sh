#!/bin/bash
# Proxy watchdog — runs as a background daemon, restarts proxy if it dies.
# Launched by start.sh via nohup.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$SCRIPT_DIR/proxy.pid"
LOGFILE="$SCRIPT_DIR/proxy.log"
WATCHDOG_PIDFILE="$SCRIPT_DIR/watchdog.pid"

echo $$ > "$WATCHDOG_PIDFILE"

log() { echo "[$(date '+%H:%M:%S')] watchdog: $*" >> "$LOGFILE"; }

# Resolve binary (same logic as start.sh)
resolve_binary() {
    for name in bedrock-effort-proxy-linux-amd64 bedrock-effort-proxy bedrock-proxy-go; do
        [ -x "$SCRIPT_DIR/$name" ] && echo "$SCRIPT_DIR/$name" && return 0
    done
    [ -f "$SCRIPT_DIR/deprecated/proxy.py" ] && echo "python3 $SCRIPT_DIR/deprecated/proxy.py" && return 0
    [ -f "$SCRIPT_DIR/proxy.py" ] && echo "python3 $SCRIPT_DIR/proxy.py" && return 0
    return 1
}

start_proxy() {
    cd "$SCRIPT_DIR"
    export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
    BINARY=$(resolve_binary)
    if [ -z "$BINARY" ]; then
        log "ERROR: no proxy binary found"
        return 1
    fi
    nohup $BINARY >> "$LOGFILE" 2>&1 &
    local pid=$!
    disown $pid
    echo $pid > "$PIDFILE"
    log "started proxy PID $pid ($BINARY)"
}

log "watchdog started (PID $$)"

while true; do
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ! kill -0 "$PID" 2>/dev/null; then
            log "proxy PID $PID dead, restarting..."
            start_proxy
            sleep 3
        fi
    else
        log "no PID file, starting proxy..."
        start_proxy
        sleep 3
    fi
    sleep 5
done
