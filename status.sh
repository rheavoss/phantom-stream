#!/usr/bin/env bash
# status.sh — PhantomStream runtime status + judge detection hints

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/stream.pid"
FPID_FILE="$INSTALL_DIR/ffmpeg.pid"
STREAM_PORT=49213

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || \
         ipconfig getifaddr en1 2>/dev/null || \
         ifconfig | awk '/inet / && !/127\.0\.0/ {print $2; exit}' || \
         echo "UNKNOWN")

echo -e "${BOLD}PhantomStream v1.0 — Runtime Status${RESET}"
echo "──────────────────────────────────────────────────────"

# ── Server process (python3) ──────────────────────────────────────────────────
TRACKED_PID=""
if [[ -f "$PID_FILE" ]]; then
    TRACKED_PID=$(cat "$PID_FILE")
    STATE=$(ps -o state= -p "$TRACKED_PID" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$STATE" ]] && [[ "$STATE" != "Z" ]]; then
        PS_LINE=$(ps -p "$TRACKED_PID" -o pid=,pcpu=,pmem=,etime= 2>/dev/null || true)
        echo -e "  HTTP server: ${GREEN}RUNNING${RESET} (python3)"
        echo -e "    PID $(echo $PS_LINE | awk '{print $1}')  CPU ${YELLOW}$(echo $PS_LINE | awk '{print $2}')%${RESET}  MEM $(echo $PS_LINE | awk '{print $3}')%  up $(echo $PS_LINE | awk '{print $4}')"
    else
        echo -e "  HTTP server: ${RED}NOT RUNNING${RESET}"
        TRACKED_PID=""
    fi
else
    echo -e "  HTTP server: ${RED}NOT RUNNING${RESET}"
fi

# ── ffmpeg process (renamed) ──────────────────────────────────────────────────
if [[ -f "$FPID_FILE" ]]; then
    FPID=$(cat "$FPID_FILE")
    FSTATE=$(ps -o state= -p "$FPID" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$FSTATE" ]] && [[ "$FSTATE" != "Z" ]]; then
        FPS_LINE=$(ps -p "$FPID" -o pid=,pcpu=,pmem=,etime= 2>/dev/null || true)
        echo -e "  Capture:     ${GREEN}RUNNING${RESET} (com.institute.helperd)"
        echo -e "    PID $(echo $FPS_LINE | awk '{print $1}')  CPU ${YELLOW}$(echo $FPS_LINE | awk '{print $2}')%${RESET}  MEM $(echo $FPS_LINE | awk '{print $3}')%  up $(echo $FPS_LINE | awk '{print $4}')"
    else
        echo -e "  Capture:     ${RED}NOT RUNNING${RESET}"
    fi
fi

# ── Port ──────────────────────────────────────────────────────────────────────
echo
echo -e "Port $STREAM_PORT:"
if lsof -iTCP:$STREAM_PORT -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
    echo -e "  ${GREEN}LISTENING${RESET} — ready for tablet connection"
elif lsof -iTCP:$STREAM_PORT -n -P 2>/dev/null | grep -q ESTABLISHED; then
    echo -e "  ${GREEN}ESTABLISHED${RESET} — tablet connected, stream active"
else
    echo -e "  ${RED}NOT OPEN${RESET}"
fi

# ── Tablet URL ────────────────────────────────────────────────────────────────
echo
echo -e "  Stream URL:  ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo -e "  Tablet:      Open URL in Chrome — no app needed"

# ── Stop commands ─────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}━━━ STOP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
[[ -n "$TRACKED_PID" ]] && \
    echo -e "  ${RED}${BOLD}kill $TRACKED_PID${RESET}                ← kills server + capture"
echo -e "  ${YELLOW}pkill -f server.py${RESET}              ← by script name"
echo -e "  ${YELLOW}pkill com.institute.helperd${RESET}     ← kills capture only"
echo -e "  ${YELLOW}$INSTALL_DIR/uninstall.sh${RESET}       ← full removal"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ── Judge detection hints ─────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}── JUDGE / DEFENDER DETECTION VECTORS ──────────────────${RESET}"
echo -e "  1. Activity Monitor → search 'helperd' or 'server.py'"
echo -e "  2. lsof -iTCP:$STREAM_PORT"
echo -e "  3. ls ~/Library/.AppleDiagnostics/"
echo -e "  4. ls ~/Library/LaunchAgents/ | grep institute"
echo -e "  5. launchctl list | grep institute"
echo -e "  6. netstat -an | grep $STREAM_PORT"
echo -e "  7. Firewall exceptions: System Prefs → Security → Firewall Options"
echo -e "  8. ps aux | grep -E 'helperd|server.py'"
echo
