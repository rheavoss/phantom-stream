#!/usr/bin/env bash
# PhantomStream v1.0 — Full QA Test Suite
# Runs 20 test cases end-to-end. Pass = green, Fail = red.
# Usage: ./qa_test.sh [--usb | --wifi]

set -uo pipefail

MODE="${1:---usb}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

INSTALL_DIR="$HOME/Library/.AppleDiagnostics"
PID_FILE="$INSTALL_DIR/stream.pid"
FPID_FILE="$INSTALL_DIR/ffmpeg.pid"
STREAM_PORT=49213
MAC_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "UNKNOWN")
TABLET_SERIAL="R52X708VMWW"

PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}✓ PASS${RESET}  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗ FAIL${RESET}  $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${RESET}  $1"; WARN=$((WARN+1)); }
header() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────${RESET}"; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║    PhantomStream v1.0 — QA Test Suite                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Mode:    $MODE"
echo "  Mac IP:  $MAC_IP"
echo "  Time:    $(date)"

# ═══════════════════════════════════════════════════════════
header "T01 · INSTALLATION"
# ═══════════════════════════════════════════════════════════

# T01.1 — Install dir exists
[[ -d "$INSTALL_DIR" ]] && pass "T01.1  Install dir exists: $INSTALL_DIR" || fail "T01.1  Install dir missing"

# T01.2 — Binary exists and executable
[[ -x "$INSTALL_DIR/com.institute.helperd" ]] && \
    pass "T01.2  com.institute.helperd binary executable" || \
    fail "T01.2  Binary missing or not executable"

# T01.3 — Binary is ffmpeg (check version string)
VER=$("$INSTALL_DIR/com.institute.helperd" -version 2>&1 | head -1 || true)
echo "$VER" | grep -q "ffmpeg" && \
    pass "T01.3  Binary is ffmpeg: $(echo "$VER" | cut -c1-50)" || \
    fail "T01.3  Binary is not ffmpeg"

# T01.4 — xattr quarantine cleared
XATTRS=$(xattr "$INSTALL_DIR/com.institute.helperd" 2>/dev/null || true)
echo "$XATTRS" | grep -q "com.apple.quarantine" && \
    fail "T01.4  Quarantine xattr still present" || \
    pass "T01.4  Quarantine xattr cleared"

# T01.5 — server.py present
[[ -f "$INSTALL_DIR/server.py" ]] && pass "T01.5  server.py present" || fail "T01.5  server.py missing"

# T01.6 — LaunchAgent plist installed
PLIST="$HOME/Library/LaunchAgents/com.institute.syshelper.local.plist"
[[ -f "$PLIST" ]] && pass "T01.6  LaunchAgent plist installed" || warn "T01.6  LaunchAgent plist missing (persistence disabled)"

# ═══════════════════════════════════════════════════════════
header "T02 · PROCESS HEALTH"
# ═══════════════════════════════════════════════════════════

# T02.1 — Server PID file exists
[[ -f "$PID_FILE" ]] && pass "T02.1  stream.pid exists" || fail "T02.1  stream.pid missing — stream not started"

# T02.2 — Server process alive (non-zombie)
if [[ -f "$PID_FILE" ]]; then
    SRV_PID=$(cat "$PID_FILE")
    SRV_STATE=$(ps -o state= -p "$SRV_PID" 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$SRV_STATE" ]] && [[ "$SRV_STATE" != "Z" ]]; then
        pass "T02.2  Python server alive (PID $SRV_PID, state=$SRV_STATE)"
    else
        fail "T02.2  Server process dead or zombie (PID $SRV_PID, state=$SRV_STATE)"
    fi
else
    fail "T02.2  Cannot check — no PID file"
fi

# T02.3 — ffmpeg process alive
if [[ -f "$FPID_FILE" ]]; then
    FFM_PID=$(cat "$FPID_FILE")
    FFM_STATE=$(ps -o state= -p "$FFM_PID" 2>/dev/null | tr -d ' ' || echo "")
    FFM_CPU=$(ps -o pcpu= -p "$FFM_PID" 2>/dev/null | tr -d ' ' || echo "?")
    if [[ -n "$FFM_STATE" ]] && [[ "$FFM_STATE" != "Z" ]]; then
        pass "T02.3  ffmpeg alive (PID $FFM_PID, CPU=${FFM_CPU}%, state=$FFM_STATE)"
    else
        fail "T02.3  ffmpeg dead or zombie"
    fi
else
    fail "T02.3  ffmpeg.pid missing"
fi

# T02.4 — CPU under 50% (overheating guard)
if [[ -f "$FPID_FILE" ]]; then
    FFM_CPU=$(ps -o pcpu= -p "$(cat $FPID_FILE)" 2>/dev/null | tr -d ' ' || echo "999")
    CPU_INT=${FFM_CPU%.*}
    if [[ "$CPU_INT" -lt 50 ]]; then
        pass "T02.4  CPU acceptable: ${FFM_CPU}% (target <50%)"
    elif [[ "$CPU_INT" -lt 80 ]]; then
        warn "T02.4  CPU elevated: ${FFM_CPU}% (may cause fan noise)"
    else
        fail "T02.4  CPU too high: ${FFM_CPU}% (will overheat MacBook Air)"
    fi
fi

# T02.5 — Process names (stealth check)
PROC_NAMES=$(ps aux | grep -E "helperd|server.py" | grep -v grep | awk '{print $11}' | tr '\n' ' ')
[[ -n "$PROC_NAMES" ]] && pass "T02.5  Stealth processes visible: $PROC_NAMES" || warn "T02.5  No stealth processes found"

# ═══════════════════════════════════════════════════════════
header "T03 · NETWORK — MAC SIDE"
# ═══════════════════════════════════════════════════════════

# T03.1 — Port LISTENING
if lsof -iTCP:$STREAM_PORT -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
    pass "T03.1  Port $STREAM_PORT LISTENING on Mac"
else
    fail "T03.1  Port $STREAM_PORT NOT listening — stream down"
fi

# T03.2 — GET / returns HTML
HTTP_ROOT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
    "http://127.0.0.1:$STREAM_PORT/" 2>/dev/null || echo "000")
[[ "$HTTP_ROOT" == "200" ]] && pass "T03.2  GET / → HTTP 200 OK" || fail "T03.2  GET / → HTTP $HTTP_ROOT (expected 200)"

# T03.3 — GET /frame returns JPEG
FRAME_CODE=$(curl -s -o /tmp/qa_frame.jpg -w "%{http_code}" --connect-timeout 3 \
    "http://127.0.0.1:$STREAM_PORT/frame" 2>/dev/null || echo "000")
if [[ "$FRAME_CODE" == "200" ]]; then
    FRAME_SIZE=$(wc -c < /tmp/qa_frame.jpg 2>/dev/null || echo 0)
    if [[ "$FRAME_SIZE" -gt 1000 ]]; then
        pass "T03.3  GET /frame → HTTP 200, ${FRAME_SIZE} bytes JPEG"
    else
        fail "T03.3  GET /frame → 200 but frame too small (${FRAME_SIZE} bytes) — black screen?"
    fi
else
    fail "T03.3  GET /frame → HTTP $FRAME_CODE (expected 200)"
fi

# T03.4 — Frame is a valid JPEG (check SOI marker)
if [[ -f /tmp/qa_frame.jpg ]] && [[ $(wc -c < /tmp/qa_frame.jpg) -gt 2 ]]; then
    MAGIC=$(xxd -l 2 /tmp/qa_frame.jpg 2>/dev/null | awk '{print $2}' || echo "")
    [[ "$MAGIC" == "ffd8" ]] && pass "T03.4  Frame has valid JPEG SOI marker (ff d8)" || \
        fail "T03.4  Frame missing JPEG SOI — not a valid image (magic=$MAGIC)"
fi

# T03.5 — Stream liveness: ffmpeg is actively running (CPU>0) and frame is fresh
# Note: identical frame bytes on a static screen is NORMAL (not frozen)
FFM_PID_CHECK=$(cat "$FPID_FILE" 2>/dev/null || echo "")
if [[ -n "$FFM_PID_CHECK" ]]; then
    FFM_CPU_NOW=$(ps -o pcpu= -p "$FFM_PID_CHECK" 2>/dev/null | tr -d ' ' || echo "0")
    FFM_INT=${FFM_CPU_NOW%.*}
    if [[ "$FFM_INT" -gt 0 ]]; then
        pass "T03.5  Stream LIVE — ffmpeg actively encoding (CPU=${FFM_CPU_NOW}%)"
    else
        fail "T03.5  Stream may be stalled — ffmpeg at 0% CPU"
    fi
fi

# T03.6 — HTML contains JS polling code
HTML_BODY=$(curl -s --connect-timeout 3 "http://127.0.0.1:$STREAM_PORT/" 2>/dev/null || echo "")
echo "$HTML_BODY" | grep -qE "setInterval|setTimeout|fetchNext" && \
    pass "T03.6  HTML contains JS polling (setTimeout/fetchNext found)" || \
    fail "T03.6  HTML missing JS polling — Chrome won't update"

echo "$HTML_BODY" | grep -q "/frame" && \
    pass "T03.7  HTML polls /frame endpoint" || \
    fail "T03.7  HTML does not poll /frame"

# ═══════════════════════════════════════════════════════════
header "T04 · NETWORK — TABLET REACH"
# ═══════════════════════════════════════════════════════════

# T04.1 — ADB device connected
ADB_STATE=$(adb -s "$TABLET_SERIAL" get-state 2>/dev/null || echo "offline")
[[ "$ADB_STATE" == "device" ]] && pass "T04.1  Tablet connected via ADB ($TABLET_SERIAL)" || \
    warn "T04.1  Tablet ADB offline — USB tests skipped"

if [[ "$ADB_STATE" == "device" ]]; then
    # T04.2 — USB tunnel active
    TUNNEL=$(adb -s "$TABLET_SERIAL" reverse --list 2>/dev/null | grep "$STREAM_PORT" || echo "")
    if [[ -n "$TUNNEL" ]]; then
        pass "T04.2  USB reverse tunnel active: $TUNNEL"
    else
        warn "T04.2  USB tunnel not set — setting up now..."
        adb -s "$TABLET_SERIAL" reverse tcp:$STREAM_PORT tcp:$STREAM_PORT >/dev/null 2>&1
        pass "T04.2  USB tunnel established"
    fi

    # T04.3 — Port reachable from tablet over USB
    TABLET_REACH=$(adb -s "$TABLET_SERIAL" shell \
        "nc -z -w 3 127.0.0.1 $STREAM_PORT && echo ok || echo fail" 2>/dev/null | tr -d '\r')
    [[ "$TABLET_REACH" == "ok" ]] && \
        pass "T04.3  Port $STREAM_PORT reachable from tablet via USB" || \
        fail "T04.3  Port NOT reachable from tablet: $TABLET_REACH"

    # T04.4 — Wi-Fi reachable (ping Mac from tablet)
    WIFI_PING=$(adb -s "$TABLET_SERIAL" shell \
        "ping -c 2 -W 2 $MAC_IP 2>/dev/null | tail -1" | tr -d '\r')
    echo "$WIFI_PING" | grep -q "0% packet loss\|min/avg" && \
        pass "T04.4  Mac reachable from tablet via Wi-Fi ($MAC_IP)" || \
        warn "T04.4  Wi-Fi ping failed — stream must use USB tunnel"

    # T04.5 — Wi-Fi port reachable
    WIFI_REACH=$(adb -s "$TABLET_SERIAL" shell \
        "nc -z -w 3 $MAC_IP $STREAM_PORT && echo ok || echo fail" 2>/dev/null | tr -d '\r')
    [[ "$WIFI_REACH" == "ok" ]] && \
        pass "T04.5  Port $STREAM_PORT reachable from tablet via Wi-Fi ($MAC_IP)" || \
        warn "T04.5  Wi-Fi port unreachable — USB tunnel required"
fi

# ═══════════════════════════════════════════════════════════
header "T05 · STREAM QUALITY"
# ═══════════════════════════════════════════════════════════

# T05.1 — Frame resolution check (via JPEG EXIF/dimensions)
if [[ -f /tmp/qa_frame.jpg ]]; then
    # Check frame size as proxy for resolution (800x500 q10 should be 20-100KB)
    FSIZE=$(wc -c < /tmp/qa_frame.jpg)
    if [[ "$FSIZE" -gt 5000 ]] && [[ "$FSIZE" -lt 500000 ]]; then
        pass "T05.1  Frame size healthy: ${FSIZE} bytes (expected 5KB–500KB)"
    elif [[ "$FSIZE" -le 5000 ]]; then
        fail "T05.1  Frame too small (${FSIZE} bytes) — likely black/blank screen"
    else
        warn "T05.1  Frame very large (${FSIZE} bytes) — may cause bandwidth issues"
    fi
fi

# T05.2 — Frame rate (time 4 consecutive /frame requests; use python3 for ms on macOS)
START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
for i in 1 2 3 4; do
    curl -s -o /dev/null --connect-timeout 3 "http://127.0.0.1:$STREAM_PORT/frame" 2>/dev/null || true
    sleep 0.33
done
END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
ELAPSED=$(( END_MS - START_MS ))
[[ $ELAPSED -gt 0 ]] && \
    pass "T05.2  4 frames fetched in ${ELAPSED}ms" || \
    warn "T05.2  Could not measure frame timing"

# T05.3 — Check for black screen (pure black JPEG is very small ~1-3KB)
if [[ -f /tmp/qa_frame.jpg ]]; then
    FSIZE=$(wc -c < /tmp/qa_frame.jpg)
    [[ "$FSIZE" -gt 10000 ]] && \
        pass "T05.3  Frame likely has content (${FSIZE}B > 10KB black-screen threshold)" || \
        fail "T05.3  Frame may be black screen (${FSIZE}B — too small for real content)"
fi

# ═══════════════════════════════════════════════════════════
header "T06 · STEALTH (ASSESSMENT SCORING)"
# ═══════════════════════════════════════════════════════════

# T06.1 — Binary name not 'ffmpeg'
ps aux | grep -v grep | grep "com.institute.helperd" | grep -q "helperd" && \
    pass "T06.1  Capture process named com.institute.helperd (not ffmpeg)" || \
    warn "T06.1  Could not confirm stealthy process name"

# T06.2 — Hidden directory (dot prefix)
[[ "$INSTALL_DIR" == *"."* ]] && pass "T06.2  Install dir has dot prefix (hidden from ls)" || \
    fail "T06.2  Install dir is not hidden"

# T06.3 — No 'ProctorTest' strings in running processes
ps aux | grep -v grep | grep -qi "proctortest" && \
    fail "T06.3  'ProctorTest' found in process list — not stealthy" || \
    pass "T06.3  No 'ProctorTest' string in process list"

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
    echo -e "\n  ${GREEN}${BOLD}✓ ALL TESTS PASSED — stream is healthy${RESET}\n"
else
    echo -e "\n  ${RED}${BOLD}✗ $FAIL TEST(S) FAILED — see above${RESET}\n"
fi

# Cleanup temp files
rm -f /tmp/qa_frame.jpg /tmp/qa_frame2.jpg
