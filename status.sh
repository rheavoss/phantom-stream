#!/usr/bin/env bash
# status.sh — PhantomStream v2.0 runtime status

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/sync.pid"
STREAM_PORT=27017
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "UNKNOWN")

echo -e "${BOLD}PhantomStream v2.0 — Runtime Status${RESET}"
echo "──────────────────────────────────────────────────────"

# ── Daemon process ────────────────────────────────────────────────────────────
TRACKED_PID=""
if [[ -f "$PID_FILE" ]]; then
    TRACKED_PID=$(cat "$PID_FILE")
    STATE=$(ps -o state= -p "$TRACKED_PID" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$STATE" ]] && [[ "$STATE" != "Z" ]]; then
        PS_LINE=$(ps -p "$TRACKED_PID" -o pid=,pcpu=,pmem=,etime= 2>/dev/null || true)
        echo -e "  Daemon:  ${GREEN}RUNNING${RESET} (com.institute.backgroundsyncd)"
        echo -e "    PID $(echo $PS_LINE | awk '{print $1}')  CPU ${YELLOW}$(echo $PS_LINE | awk '{print $2}')%${RESET}  uptime $(echo $PS_LINE | awk '{print $4}')"
    else
        echo -e "  Daemon:  ${RED}NOT RUNNING${RESET}"
    fi
else
    echo -e "  Daemon:  ${RED}NOT RUNNING${RESET}"
fi

# ── Frame freshness ───────────────────────────────────────────────────────────
FRAME="/tmp/.apple-display-sync.jpg"
if [[ -f "$FRAME" ]]; then
    AGE=$(python3 -c "import os,time; print(f'{time.time()-os.path.getmtime(\"$FRAME\"):.1f}s')" 2>/dev/null || echo "?")
    SIZE=$(wc -c < "$FRAME" 2>/dev/null || echo "?")
    echo -e "  Frame:   ${GREEN}FRESH${RESET} — age=${AGE} size=${SIZE}B"
else
    echo -e "  Frame:   ${RED}MISSING${RESET}"
fi

# ── Port ──────────────────────────────────────────────────────────────────────
echo
if lsof -iTCP:$STREAM_PORT -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
    echo -e "  Port $STREAM_PORT:  ${GREEN}LISTENING${RESET}"
else
    echo -e "  Port $STREAM_PORT:  ${RED}NOT OPEN${RESET}"
fi

echo -e "  URL:     ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo

# ── LaunchAgent ───────────────────────────────────────────────────────────────
launchctl list | grep -q "com.institute.backgroundsyncd" && \
    echo -e "  LaunchAgent: ${GREEN}LOADED${RESET} (auto-start on login)" || \
    echo -e "  LaunchAgent: ${YELLOW}NOT LOADED${RESET}"

echo
echo -e "${BOLD}━━━ STOP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
[[ -n "$TRACKED_PID" ]] && echo -e "  ${RED}kill $TRACKED_PID${RESET}  ← kills daemon"
echo -e "  ${YELLOW}pkill -f com.institute.backgroundsyncd${RESET}"
echo -e "  ${YELLOW}$INSTALL_DIR/uninstall.sh${RESET}  ← full removal"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ── Defender hint ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}${BOLD}── PHASE 2 DETECTION VECTORS ────────────────────────────${RESET}"
echo -e "  1. ps aux | grep backgroundsyncd"
echo -e "  2. lsof -iTCP:$STREAM_PORT"
echo -e "  3. ls ~/Library/.AppleDiagnostics/"
echo -e "  4. launchctl list | grep institute"
echo -e "  5. http://localhost:$STREAM_PORT/ — live screen visible"
echo -e "  6. Activity Monitor: screencapture flashes every 400ms"
echo -e "  7. System Prefs → Privacy → Screen Recording"
echo
