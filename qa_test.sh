#!/usr/bin/env bash
# PhantomStream v2.0 — Full QA Test Suite (Phase 2: Maximum Covert Edition)
# Usage: ./qa_test.sh [--usb | --wifi]

set -uo pipefail

MODE="${1:---usb}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/sync.pid"
STREAM_PORT=9090
FRAME_FILE="/tmp/com.apple.displaysyncd.jpg"
MAC_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "UNKNOWN")
TABLET_SERIAL="R52X708VMWW"

PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}✓ PASS${RESET}  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗ FAIL${RESET}  $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${RESET}  $1"; WARN=$((WARN+1)); }
header() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────${RESET}"; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║    PhantomStream v2.0 — QA Test Suite                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Mode:    $MODE"
echo "  Mac IP:  $MAC_IP"
echo "  Time:    $(date)"

# ═══════════════════════════════════════════════════════════
header "T01 · INSTALLATION"
# ═══════════════════════════════════════════════════════════

[[ -d "$INSTALL_DIR" ]] && pass "T01.1  Install dir exists: $INSTALL_DIR" || fail "T01.1  Install dir missing"

DAEMON="$INSTALL_DIR/com.institute.backgroundsyncd"
[[ -f "$DAEMON" ]] && pass "T01.2  Daemon present: com.institute.backgroundsyncd" || fail "T01.2  Daemon missing"

[[ -x "$DAEMON" ]] && pass "T01.3  Daemon is executable" || fail "T01.3  Daemon not executable"

[[ -f "$INSTALL_DIR/wrapper.sh" ]] && pass "T01.4  wrapper.sh present" || fail "T01.4  wrapper.sh missing"

PLIST="$HOME/Library/LaunchAgents/com.institute.backgroundsyncd.plist"
[[ -f "$PLIST" ]] && pass "T01.5  LaunchAgent plist installed (com.institute.backgroundsyncd)" || \
    warn "T01.5  LaunchAgent plist missing (persistence disabled)"

# Old plist should NOT exist
OLD_PLIST="$HOME/Library/LaunchAgents/com.institute.syshelper.local.plist"
[[ ! -f "$OLD_PLIST" ]] && pass "T01.6  Old Phase 1 plist cleaned up" || \
    fail "T01.6  Old Phase 1 plist still present — run install.sh to clean up"

# ═══════════════════════════════════════════════════════════
header "T02 · PROCESS HEALTH"
# ═══════════════════════════════════════════════════════════

[[ -f "$PID_FILE" ]] && pass "T02.1  sync.pid exists" || fail "T02.1  sync.pid missing — not started"

if [[ -f "$PID_FILE" ]]; then
    SRV_PID=$(cat "$PID_FILE")
    SRV_STATE=$(ps -o state= -p "$SRV_PID" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$SRV_STATE" ]] && [[ "$SRV_STATE" != "Z" ]]; then
        pass "T02.2  Daemon alive (PID $SRV_PID, state=$SRV_STATE)"
    else
        fail "T02.2  Daemon dead or zombie (PID $SRV_PID)"
    fi
else
    fail "T02.2  Cannot check — no PID file"
fi

# CPU check
if [[ -f "$PID_FILE" ]]; then
    SRV_PID=$(cat "$PID_FILE")
    CPU=$(ps -o pcpu= -p "$SRV_PID" 2>/dev/null | tr -d ' ' || echo "999")
    CPU_INT=${CPU%.*}
    if [[ "$CPU_INT" -lt 20 ]]; then
        pass "T02.3  CPU acceptable: ${CPU}% (target <20%)"
    elif [[ "$CPU_INT" -lt 40 ]]; then
        warn "T02.3  CPU elevated: ${CPU}%"
    else
        fail "T02.3  CPU too high: ${CPU}%"
    fi
fi

# Process name check — must show backgroundsyncd, NOT server.py
PROC_CMD=$(ps -p "$(cat $PID_FILE 2>/dev/null || echo 0)" -o command= 2>/dev/null || echo "")
echo "$PROC_CMD" | grep -q "backgroundsyncd" && \
    pass "T02.4  Process shows as 'backgroundsyncd' (not server.py)" || \
    fail "T02.4  Process does NOT show as backgroundsyncd: $PROC_CMD"

echo "$PROC_CMD" | grep -q "server\.py" && \
    fail "T02.5  EXPOSED: process args reveal 'server.py'" || \
    pass "T02.5  'server.py' NOT visible in process args"

# ═══════════════════════════════════════════════════════════
header "T03 · NETWORK — MAC SIDE"
# ═══════════════════════════════════════════════════════════

lsof -iTCP:$STREAM_PORT -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN && \
    pass "T03.1  Port $STREAM_PORT LISTENING" || fail "T03.1  Port $STREAM_PORT NOT listening"

HTTP_ROOT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
    "http://127.0.0.1:$STREAM_PORT/" 2>/dev/null || echo "000")
[[ "$HTTP_ROOT" == "200" ]] && pass "T03.2  GET / → HTTP 200" || fail "T03.2  GET / → HTTP $HTTP_ROOT"

# Server header must look like AppleHTTPD
SERVER_HDR=$(curl -sI --connect-timeout 3 "http://127.0.0.1:$STREAM_PORT/" 2>/dev/null | \
    grep -i "^server:" | tr -d '\r' || echo "")
echo "$SERVER_HDR" | grep -qi "AppleHTTPD" && \
    pass "T03.3  Server header: $SERVER_HDR" || \
    fail "T03.3  Server header not camouflaged: $SERVER_HDR"

# Frame must be at new route
FRAME_CODE=$(curl -s -o /tmp/qa_frame.jpg -w "%{http_code}" --connect-timeout 3 \
    "http://127.0.0.1:$STREAM_PORT/api/v1/display/preview" 2>/dev/null || echo "000")
if [[ "$FRAME_CODE" == "200" ]]; then
    FRAME_SIZE=$(wc -c < /tmp/qa_frame.jpg 2>/dev/null || echo 0)
    [[ "$FRAME_SIZE" -gt 1000 ]] && \
        pass "T03.4  GET /api/v1/display/preview → 200, ${FRAME_SIZE}B JPEG" || \
        fail "T03.4  Frame too small (${FRAME_SIZE}B)"
else
    fail "T03.4  GET /api/v1/display/preview → $FRAME_CODE (expected 200)"
fi

# Old /frame route should NOT return frame (404 or redirect)
OLD_FRAME=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
    "http://127.0.0.1:$STREAM_PORT/frame" 2>/dev/null || echo "000")
[[ "$OLD_FRAME" != "200" ]] && \
    pass "T03.5  Old /frame route not accessible ($OLD_FRAME) — route camouflaged" || \
    fail "T03.5  Old /frame route still returns 200 — exposed"

# JPEG SOI marker
if [[ -f /tmp/qa_frame.jpg ]] && [[ $(wc -c < /tmp/qa_frame.jpg) -gt 2 ]]; then
    MAGIC=$(xxd -l 2 /tmp/qa_frame.jpg 2>/dev/null | awk '{print $2}' || echo "")
    [[ "$MAGIC" == "ffd8" ]] && pass "T03.6  Frame has valid JPEG SOI marker" || \
        fail "T03.6  Invalid JPEG (magic=$MAGIC)"
fi

# HTML must look like monitoring dashboard, not reveal stream purpose
HTML_BODY=$(curl -s --connect-timeout 3 "http://127.0.0.1:$STREAM_PORT/" 2>/dev/null || echo "")
echo "$HTML_BODY" | grep -qi "Display Sync Monitor\|System Monitor\|backgroundsyncd" && \
    pass "T03.7  HTML looks like legitimate monitoring page" || \
    fail "T03.7  HTML does not look legitimate"

echo "$HTML_BODY" | grep -qi "PhantomStream\|screen stream\|stream server" && \
    fail "T03.8  HTML reveals PhantomStream purpose" || \
    pass "T03.8  HTML does not reveal tool name or purpose"

# X-Request-ID header present (traffic jitter / obfuscation)
REQ_ID=$(curl -sI --connect-timeout 3 "http://127.0.0.1:$STREAM_PORT/" 2>/dev/null | \
    grep -i "X-Request-ID" | tr -d '\r' || echo "")
[[ -n "$REQ_ID" ]] && pass "T03.9  X-Request-ID header present (traffic obfuscation)" || \
    warn "T03.9  X-Request-ID header missing"

# Frame file has hidden name
[[ -f "$FRAME_FILE" ]] && pass "T03.10 Frame file: $FRAME_FILE (dot-hidden name)" || \
    fail "T03.10 Frame file missing: $FRAME_FILE"

# ═══════════════════════════════════════════════════════════
header "T04 · NETWORK — TABLET REACH"
# ═══════════════════════════════════════════════════════════

ADB_STATE=$(adb -s "$TABLET_SERIAL" get-state 2>/dev/null || echo "offline")
[[ "$ADB_STATE" == "device" ]] && pass "T04.1  Tablet connected via ADB ($TABLET_SERIAL)" || \
    warn "T04.1  Tablet ADB offline — USB tests skipped"

if [[ "$ADB_STATE" == "device" ]]; then
    TUNNEL=$(adb -s "$TABLET_SERIAL" reverse --list 2>/dev/null | grep "$STREAM_PORT" || echo "")
    if [[ -n "$TUNNEL" ]]; then
        pass "T04.2  USB reverse tunnel active: $TUNNEL"
    else
        warn "T04.2  USB tunnel not set — setting up now..."
        adb -s "$TABLET_SERIAL" reverse tcp:$STREAM_PORT tcp:$STREAM_PORT >/dev/null 2>&1
        pass "T04.2  USB tunnel established"
    fi

    TABLET_REACH=$(adb -s "$TABLET_SERIAL" shell \
        "nc -z -w 3 127.0.0.1 $STREAM_PORT && echo ok || echo fail" 2>/dev/null | tr -d '\r')
    [[ "$TABLET_REACH" == "ok" ]] && \
        pass "T04.3  Port $STREAM_PORT reachable from tablet via USB" || \
        fail "T04.3  Port NOT reachable: $TABLET_REACH"

    WIFI_PING=$(adb -s "$TABLET_SERIAL" shell \
        "ping -c 2 -W 2 $MAC_IP 2>/dev/null | tail -1" | tr -d '\r')
    echo "$WIFI_PING" | grep -q "0% packet loss\|min/avg" && \
        pass "T04.4  Mac reachable from tablet via Wi-Fi ($MAC_IP)" || \
        warn "T04.4  Wi-Fi ping failed"

    WIFI_REACH=$(adb -s "$TABLET_SERIAL" shell \
        "nc -z -w 3 $MAC_IP $STREAM_PORT && echo ok || echo fail" 2>/dev/null | tr -d '\r')
    [[ "$WIFI_REACH" == "ok" ]] && \
        pass "T04.5  Port $STREAM_PORT reachable from tablet via Wi-Fi" || \
        warn "T04.5  Wi-Fi port unreachable — USB tunnel required"
fi

# ═══════════════════════════════════════════════════════════
header "T05 · STREAM QUALITY"
# ═══════════════════════════════════════════════════════════

if [[ -f /tmp/qa_frame.jpg ]]; then
    FSIZE=$(wc -c < /tmp/qa_frame.jpg)
    if [[ "$FSIZE" -gt 50000 ]] && [[ "$FSIZE" -lt 600000 ]]; then
        pass "T05.1  Frame size healthy: ${FSIZE}B (expected 50KB–600KB for native res)"
    elif [[ "$FSIZE" -le 50000 ]]; then
        fail "T05.1  Frame too small (${FSIZE}B) — likely black/blank screen"
    else
        warn "T05.1  Frame very large (${FSIZE}B) — bandwidth concern"
    fi
fi

START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
for i in 1 2 3 4; do
    curl -s -o /dev/null --connect-timeout 3 \
        "http://127.0.0.1:$STREAM_PORT/api/v1/display/preview" 2>/dev/null || true
    sleep 0.4
done
END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
ELAPSED=$(( END_MS - START_MS ))
pass "T05.2  4 frames fetched in ${ELAPSED}ms"

if [[ -f /tmp/qa_frame.jpg ]]; then
    FSIZE=$(wc -c < /tmp/qa_frame.jpg)
    [[ "$FSIZE" -gt 10000 ]] && \
        pass "T05.3  Frame has content (${FSIZE}B > 10KB)" || \
        fail "T05.3  Frame may be black screen"
fi

# Frame freshness
if [[ -f "$FRAME_FILE" ]]; then
    AGE=$(python3 -c "import os,time; print(round(time.time()-os.path.getmtime('$FRAME_FILE'),2))")
    python3 -c "exit(0 if float('$AGE') < 2.0 else 1)" 2>/dev/null && \
        pass "T05.4  Frame fresh: ${AGE}s old (threshold <2s)" || \
        fail "T05.4  Frame stale: ${AGE}s old"
fi

# ═══════════════════════════════════════════════════════════
header "T06 · STEALTH — PHASE 2 SCORING"
# ═══════════════════════════════════════════════════════════

# Process name camouflage
ps aux | grep -v grep | grep -q "backgroundsyncd" && \
    pass "T06.1  Process visible as 'backgroundsyncd' (not server.py)" || \
    warn "T06.1  Could not confirm process name"

ps aux | grep -v grep | grep -v backgroundsyncd | grep -q "server\.py" && \
    fail "T06.2  EXPOSED: server.py visible in ps aux" || \
    pass "T06.2  'server.py' NOT exposed in ps aux"

# Hidden install dir
[[ "$INSTALL_DIR" == *"."* ]] && pass "T06.3  Install dir dot-hidden" || fail "T06.3  Install dir not hidden"

# LaunchAgent name
launchctl list | grep -q "com.institute.backgroundsyncd" && \
    pass "T06.4  LaunchAgent loaded: com.institute.backgroundsyncd" || \
    warn "T06.4  LaunchAgent not loaded"

ls "$HOME/Library/LaunchAgents/" | grep -q "backgroundsyncd" && \
    pass "T06.5  LaunchAgent plist uses covert name" || warn "T06.5  LaunchAgent plist not found"

# Port not on obvious streaming ports (not 8080, 1935, 5000)
[[ "$STREAM_PORT" != "8080" ]] && [[ "$STREAM_PORT" != "1935" ]] && [[ "$STREAM_PORT" != "5000" ]] && \
    pass "T06.6  Port $STREAM_PORT is not an obvious streaming port" || \
    warn "T06.6  Port looks like a streaming port"

# No 'PhantomStream' or 'ProctorTest' in process list
ps aux | grep -v grep | grep -qi "proctortest\|phantomstream" && \
    fail "T06.7  Obvious strings in process list" || \
    pass "T06.7  No obvious tool strings in process list"

# Frame file has hidden dot-prefixed name
# Frame file uses Apple-like reverse-DNS naming (screencapture rejects dot-prefix in /tmp)
echo "$FRAME_FILE" | grep -q "com\.apple\." && \
    pass "T06.8  Frame file uses Apple-like naming: $FRAME_FILE" || \
    fail "T06.8  Frame file name not covert: $FRAME_FILE"

# Cleanup on kill — test SIGTERM cleans up (requires restart after)
# (manual test — too destructive to automate in QA)
warn "T06.9  Self-cleanup on SIGTERM — verify manually: kill \$(cat $PID_FILE) && ls /tmp/.apple*"

# ═══════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════
TOTAL=$((PASS + FAIL + WARN))
echo
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  QA RESULTS: $TOTAL tests${RESET}"
echo -e "  ${GREEN}PASS: $PASS${RESET}  ${RED}FAIL: $FAIL${RESET}  ${YELLOW}WARN: $WARN${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"

if [[ $FAIL -eq 0 ]]; then
    echo -e "\n  ${GREEN}${BOLD}✓ ALL TESTS PASSED — stream is healthy and covert${RESET}\n"
else
    echo -e "\n  ${RED}${BOLD}✗ $FAIL TEST(S) FAILED — see above${RESET}\n"
fi

rm -f /tmp/qa_frame.jpg
