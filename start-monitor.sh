#!/usr/bin/env bash
# start-monitor.sh — On-demand PhantomStream launcher (no Terminal window stays open)

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RED='\033[0;31m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[PhantomStream]${RESET} $*"; }
warn() { echo -e "${YELLOW}[PhantomStream]${RESET} $*"; }
die()  { echo -e "${RED}[PhantomStream]${RESET} $*" >&2; exit 1; }

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/stream.pid"
LOG_FILE="$INSTALL_DIR/stream.log"
STREAM_PORT=49213

[[ -x "$INSTALL_DIR/com.institute.helperd" ]] || \
    die "Not installed. Run install.sh first."

# ── Guard: already running? ────────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    EXISTING=$(cat "$PID_FILE")
    STATE=$(ps -o state= -p "$EXISTING" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$STATE" ]] && [[ "$STATE" != "Z" ]]; then
        warn "Already running (PID $EXISTING). Stop first: kill $EXISTING"
        exit 0
    fi
    kill -9 "$EXISTING" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

# ── Detect LAN IP ──────────────────────────────────────────────────────────────
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || \
         ipconfig getifaddr en1 2>/dev/null || \
         ifconfig | awk '/inet / && !/127\.0\.0/ {print $2; exit}' || \
         echo "UNKNOWN")

# ── Launch ─────────────────────────────────────────────────────────────────────
"$INSTALL_DIR/wrapper.sh"

# ── Wait for port to open (up to 12s) ─────────────────────────────────────────
PORT_OPEN=0
for i in {1..12}; do
    PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$PID" ]]; then
        STATE=$(ps -o state= -p "$PID" 2>/dev/null | tr -d ' ' || echo "")
        if [[ -z "$STATE" ]] || [[ "$STATE" == "Z" ]]; then
            echo
            die "Server crashed immediately. Check: tail $LOG_FILE"
        fi
    fi
    if lsof -iTCP:"$STREAM_PORT" -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
        PORT_OPEN=1; break
    fi
    echo -ne "\r  ${CYAN}Waiting for port $STREAM_PORT...${RESET} (${i}s)"
    sleep 1
done
echo

STREAM_PID=$(cat "$PID_FILE" 2>/dev/null || echo "?")

echo
if [[ $PORT_OPEN -eq 1 ]]; then
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║    PhantomStream — ACTIVE · Port LISTENING            ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
else
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${YELLOW}║    PhantomStream — Started · Port Pending             ║${RESET}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${RESET}"
fi
echo
ok "Server PID:   $STREAM_PID (shows as python3)"
ok "Capture PID:  $(cat "$INSTALL_DIR/ffmpeg.pid" 2>/dev/null || echo 'pending') (shows as com.institute.helperd)"
echo
echo -e "  ${BOLD}Tablet URL (Chrome — no app needed):${RESET}"
echo -e "  ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo
echo -e "  ${BOLD}To stop:${RESET}  kill $STREAM_PID   (or: $INSTALL_DIR/uninstall.sh)"
echo
