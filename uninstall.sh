#!/usr/bin/env bash
# uninstall.sh — PhantomStream complete removal
# Kills processes, unloads LaunchAgent, removes all files

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[REMOVE]${RESET} $*"; }
info() { echo -e "${CYAN}[REMOVE]${RESET} $*"; }
warn() { echo -e "${YELLOW}[REMOVE]${RESET} $*"; }

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PLIST_DST="$HOME/Library/LaunchAgents/com.institute.syshelper.local.plist"
PID_FILE="$INSTALL_DIR/stream.pid"
FPID_FILE="$INSTALL_DIR/ffmpeg.pid"

echo -e "${BOLD}PhantomStream — Complete Removal${RESET}"
echo
read -r -p "Remove PhantomStream and all traces? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Cancelled."; exit 0; }

# ── Unload LaunchAgent ─────────────────────────────────────────────────────────
if [[ -f "$PLIST_DST" ]]; then
    launchctl unload "$PLIST_DST" 2>/dev/null && ok "LaunchAgent unloaded" || \
        warn "LaunchAgent was not loaded"
    rm -f "$PLIST_DST"
    ok "LaunchAgent plist removed"
fi

# ── Kill server via PID file ───────────────────────────────────────────────────
for pidfile in "$PID_FILE" "$FPID_FILE"; do
    if [[ -f "$pidfile" ]]; then
        PID=$(cat "$pidfile" 2>/dev/null || true)
        if [[ -n "$PID" ]]; then
            kill "$PID" 2>/dev/null && ok "Killed PID $PID" || true
            sleep 1
            kill -9 "$PID" 2>/dev/null || true
        fi
    fi
done

# ── Belt-and-suspenders kill ───────────────────────────────────────────────────
pkill -f "server.py" 2>/dev/null && ok "Killed server.py" || true
pkill -f "com.institute.helperd" 2>/dev/null && ok "Killed com.institute.helperd" || true
pkill -f "wrapper.sh" 2>/dev/null || true

# ── Remove firewall exceptions ────────────────────────────────────────────────
if [[ -f "$INSTALL_DIR/com.institute.helperd" ]]; then
    /usr/libexec/ApplicationFirewall/socketfilterfw \
        --remove "$INSTALL_DIR/com.institute.helperd" >/dev/null 2>&1 || true
    ok "Firewall exception removed"
fi

# ── Remove install directory ───────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "Removed $INSTALL_DIR"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
if lsof -iTCP:49213 -n -P 2>/dev/null | grep -q 49213; then
    warn "Port 49213 still in use — may need reboot"
else
    ok "Port 49213 is free"
fi

echo
echo -e "${GREEN}${BOLD}PhantomStream fully removed. No traces remain.${RESET}"
echo
