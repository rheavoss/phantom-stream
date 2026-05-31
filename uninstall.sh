#!/usr/bin/env bash
# uninstall.sh — PhantomStream complete removal

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[REMOVE]${RESET} $*"; }
warn() { echo -e "${YELLOW}[REMOVE]${RESET} $*"; }

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PLIST_V2="$HOME/Library/LaunchAgents/com.institute.backgroundsyncd.plist"
PLIST_V1="$HOME/Library/LaunchAgents/com.institute.syshelper.local.plist"
PID_FILE="$INSTALL_DIR/sync.pid"
STREAM_PORT=27017

echo -e "${BOLD}PhantomStream — Complete Removal${RESET}"
echo
read -r -p "Remove PhantomStream and all traces? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Cancelled."; exit 0; }

# ── Unload LaunchAgents ────────────────────────────────────────────────────────
for plist in "$PLIST_V2" "$PLIST_V1"; do
    if [[ -f "$plist" ]]; then
        launchctl unload "$plist" 2>/dev/null && ok "LaunchAgent unloaded: $(basename $plist)" || true
        rm -f "$plist"
        ok "Removed: $plist"
    fi
done

# ── Kill processes ─────────────────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || true)
    [[ -n "$PID" ]] && kill "$PID" 2>/dev/null && sleep 1 && kill -9 "$PID" 2>/dev/null || true
fi

pkill -f "com.institute.backgroundsyncd" 2>/dev/null && ok "Killed backgroundsyncd" || true
pkill -f "com.institute.helperd" 2>/dev/null && ok "Killed helperd" || true
pkill -f "wrapper.sh" 2>/dev/null || true

# ── Remove firewall exceptions ────────────────────────────────────────────────
/usr/libexec/ApplicationFirewall/socketfilterfw \
    --remove /usr/bin/python3 >/dev/null 2>&1 || true

# ── Remove all files ──────────────────────────────────────────────────────────
for f in /tmp/com.apple.displaysyncd.jpg /tmp/com.apple.displaysyncd.jpg.tmp; do
    rm -f "$f" 2>/dev/null || true
done

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "Removed $INSTALL_DIR"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
lsof -iTCP:$STREAM_PORT -n -P 2>/dev/null | grep -q $STREAM_PORT && \
    warn "Port $STREAM_PORT still in use — may need reboot" || ok "Port $STREAM_PORT is free"

echo
echo -e "${GREEN}${BOLD}PhantomStream fully removed.${RESET}"
echo
