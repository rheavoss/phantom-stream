#!/usr/bin/env bash
# install.sh — PhantomStream v1.0 installer
# Installs to ~/Library/.AppleDiagnostics/ (hidden dot-folder, passes casual inspection)
# Binary renamed to com.institute.helperd; LaunchAgent: com.institute.syshelper.local.plist

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
BINARY="$INSTALL_DIR/com.institute.helperd"
PLIST_NAME="com.institute.syshelper.local.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"
STREAM_PORT=49213
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXISTING_FFMPEG="$HOME/Library/ProctorTest/ffmpeg"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PhantomStream v1.0 — Stealth Benchmark Edition     ║"
echo "║   Institute Cybersecurity Hiring Assessment           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Create hidden install directory ──────────────────────────────────────────
info "Creating install dir: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
# Set hidden flag so Finder doesn't show it (dot-prefix already hides from ls)
chflags hidden "$INSTALL_DIR" 2>/dev/null || true
ok "Directory ready"

# ── Copy / download ffmpeg binary ─────────────────────────────────────────────
if [[ -x "$EXISTING_FFMPEG" ]]; then
    info "Copying existing ffmpeg from ProctorTest install …"
    cp "$EXISTING_FFMPEG" "$BINARY"
    ok "Binary copied"
elif [[ ! -x "$BINARY" ]]; then
    info "Downloading static ffmpeg from evermeet.cx …"
    TMP_ZIP=$(mktemp /tmp/ffmpeg_XXXXXX.zip)
    trap 'rm -f "$TMP_ZIP"' EXIT
    curl -L --progress-bar --max-time 300 \
        -o "$TMP_ZIP" "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" || \
        die "Download failed"
    unzip -q -o "$TMP_ZIP" ffmpeg -d "$INSTALL_DIR" || \
        die "Extraction failed"
    mv "$INSTALL_DIR/ffmpeg" "$BINARY"
    ok "Binary downloaded"
else
    warn "Binary already present at $BINARY — skipping"
fi

chmod +x "$BINARY"

# ── Strip quarantine and extended attributes ──────────────────────────────────
# Removes com.apple.quarantine so macOS won't block execution
xattr -c "$BINARY" 2>/dev/null && ok "xattr cleared" || warn "xattr clear skipped"

# ── Copy scripts ──────────────────────────────────────────────────────────────
for f in server.py wrapper.sh start-monitor.sh status.sh uninstall.sh; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then
        cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"
        chmod +x "$INSTALL_DIR/$f"
        ok "Installed: $f"
    else
        warn "Missing source: $SCRIPT_DIR/$f — skipping"
    fi
done

# ── Install LaunchAgent plist ─────────────────────────────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"
if [[ -f "$SCRIPT_DIR/$PLIST_NAME" ]]; then
    # Stamp real INSTALL_DIR path into plist before copying
    sed "s|INSTALL_DIR_PLACEHOLDER|$INSTALL_DIR|g" \
        "$SCRIPT_DIR/$PLIST_NAME" > "$PLIST_DST"
    ok "LaunchAgent installed: $PLIST_DST"
else
    warn "Plist source not found — LaunchAgent not installed"
fi

# ── Firewall: allow the binary (prevents 'refused to connect' on tablet) ─────
info "Adding firewall exception for stream binary …"
if /usr/libexec/ApplicationFirewall/socketfilterfw \
        --add "$BINARY" >/dev/null 2>&1; then
    /usr/libexec/ApplicationFirewall/socketfilterfw \
        --unblockapp "$BINARY" >/dev/null 2>&1 || true
    ok "Firewall exception added"
else
    warn "Firewall: could not add exception automatically"
    warn "If tablet gets 'refused to connect', run:"
    warn "  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $BINARY"
fi
# Also allow python3 (the HTTP server process) through firewall
/usr/libexec/ApplicationFirewall/socketfilterfw \
    --add /usr/bin/python3 >/dev/null 2>&1 || true
/usr/libexec/ApplicationFirewall/socketfilterfw \
    --unblockapp /usr/bin/python3 >/dev/null 2>&1 || true

# ── Detect LAN IP ─────────────────────────────────────────────────────────────
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || \
         ipconfig getifaddr en1 2>/dev/null || \
         ifconfig | awk '/inet / && !/127\.0\.0/ {print $2; exit}' || \
         echo "UNKNOWN")

# ── Check Screen Recording permission ────────────────────────────────────────
info "Checking Screen Recording permission …"
PERM_CHECK=$("$BINARY" -f avfoundation -list_devices true -i "" 2>&1 || true)
if echo "$PERM_CHECK" | grep -q "\[1\]"; then
    ok "Screen Recording granted — Capture screen 0 at index 1"
else
    warn "Screen Recording NOT granted to this terminal's app."
    warn "Grant: System Preferences → Security & Privacy → Privacy → Screen Recording"
    warn "Then quit and reopen your terminal completely."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  PhantomStream v1.0 — Installation complete${RESET}"
echo -e "${GREEN}══════════════════════════════════════════════════════${RESET}"
echo
echo -e "  Install dir:   ${CYAN}$INSTALL_DIR${RESET}"
echo -e "  Binary:        ${CYAN}com.institute.helperd${RESET}"
echo -e "  LaunchAgent:   ${CYAN}$PLIST_DST${RESET}"
echo -e "  Stream URL:    ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo
echo -e "  ${BOLD}Start now (manual):${RESET}"
echo -e "    ${CYAN}$INSTALL_DIR/start-monitor.sh${RESET}"
echo
echo -e "  ${BOLD}Start on login (persistent):${RESET}"
echo -e "    ${CYAN}launchctl load $PLIST_DST${RESET}"
echo
echo -e "  ${BOLD}On tablet Chrome:${RESET}"
echo -e "    ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo
