#!/usr/bin/env bash
# monitor-wrapper.sh — Low-CPU screen stream wrapper
# Transparent: process named "monitor-wrapper.sh" visible in Activity Monitor
# Kill: Ctrl+C here, or `pkill -f monitor-wrapper`, or `pkill ffmpeg`
#
# Hardware: MacBook Air 2017 · i5-5350U · 8GB · Intel HD 6000 · Monterey 12.7.6
# CPU target: <14% while idle/scrolling at 4 fps

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${CYAN}[STREAM]${RESET} $*"; }
ok()    { echo -e "${GREEN}[STREAM]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[STREAM]${RESET} $*"; }
die()   { echo -e "${RED}[STREAM]${RESET} $*" >&2; exit 1; }

# ── Locate ffmpeg ─────────────────────────────────────────────────────────────
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG="$INSTALL_DIR/ffmpeg"

[[ -x "$FFMPEG" ]] || die "ffmpeg not found at $FFMPEG — run install.sh first"

# ── Config ────────────────────────────────────────────────────────────────────
STREAM_PORT=49213
AVFOUNDATION_DEVICE="1"   # device index 1 = main display (verify with ffmpeg -list_devices)
FRAMERATE=4               # fps — key CPU lever; raise to 6 max before fan spins
VIDEO_SIZE="1024x768"     # capture resolution
THREADS=2                 # cap CPU threads; i5-5350U has 4 logical, leave 2 free
PIX_FMT="uyvy422"         # avfoundation on Monterey won't give yuv420p; scale filter converts to yuv420p
BITRATE="1500k"           # CBR target; enough for text/exam at 4fps
MAXRATE="2000k"           # burst ceiling
BUFSIZE="400k"            # ~0.2s buffer at target bitrate

# ── Detect LAN IP for display ─────────────────────────────────────────────────
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || \
         ipconfig getifaddr en1 2>/dev/null || \
         ifconfig | awk '/inet / && !/127\.0\.0/ {print $2; exit}' || \
         echo "UNKNOWN")

# ── Check Screen Recording permission ────────────────────────────────────────
# avfoundation will silently capture a black screen without this permission.
PERM_CHECK=$("$FFMPEG" -f avfoundation -list_devices true -i "" 2>&1 || true)
# "Input/output error" on the screen device = permission denied on Monterey
if echo "$PERM_CHECK" | grep -qi "permission denied\|not permitted\|refused"; then
    die "Screen Recording permission denied. Grant: System Preferences → Security & Privacy → Privacy → Screen Recording → Terminal, then quit+reopen Terminal."
fi
if ! echo "$PERM_CHECK" | grep -q "\[1\]"; then
    die "Screen capture device not found at index 1. Run install.sh to see current device list."
fi

# ── Print banner ──────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║       ProctorTest — Screen Stream ACTIVE              ║"
echo "║  Visible in Activity Monitor · Ctrl+C to stop        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
info "Device:      avfoundation index $AVFOUNDATION_DEVICE"
info "Resolution:  $VIDEO_SIZE @ ${FRAMERATE}fps"
info "Codec:       H.264 ${BITRATE} ultrafast baseline (VLC Android native)"
info "Threads:     $THREADS"
info "Port:        $STREAM_PORT (HTTP MJPEG)"
echo
ok  "Serving  http://0.0.0.0:$STREAM_PORT/"
ok  "Android: open  http://${LAN_IP}:${STREAM_PORT}/  in VLC or any browser"
echo
warn "Any client can connect — VLC, browser, or ffplay."
warn "Kill: Ctrl+C  |  pkill -f monitor-wrapper  |  pkill ffmpeg"
echo

# ── Cleanup trap ──────────────────────────────────────────────────────────────
FFMPEG_PID=""
cleanup() {
    warn "Stream stopped."
    [[ -n "$FFMPEG_PID" ]] && kill "$FFMPEG_PID" 2>/dev/null || true
    pkill -P $$ ffmpeg 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── The exact low-CPU command ─────────────────────────────────────────────────
# nice -n 19         → lowest OS scheduling priority; kernel yields CPU to everything else
# -f avfoundation    → macOS native screen capture API
# -framerate 4       → 4 fps is the primary CPU lever (each frame triggers JPEG encode)
# -video_size        → capture at 1024x768; avoids full-res downscale on HD 6000
# scale:fast_bilinear → cheapest software scaler (bypasses lanczos/bicubic)
# -c:v mjpeg         → JPEG per frame; no inter-frame dependency = low decode CPU on viewer
# -q:v 6             → quality factor; 6 ≈ 85% JPEG, good readability at ~50-80 KB/frame
# -preset ultrafast  → ffmpeg internal speed preset (minimal effect on mjpeg but harmless)
# -threads 2         → cap worker threads; leave 2 cores free for browser/exam app
# -pixel_format      → must match avfoundation output; Monterey supports uyvy422/nv12/0rgb/bgr0
# H.264 in MPEG-TS over HTTP — Grok-validated format for Android VLC 3.7
# -pixel_format uyvy422  → avfoundation input; Monterey won't give yuv420p
# -pix_fmt yuv420p       → output to libx264; scale filter converts from uyvy422
# -profile:v baseline    → widest tablet decoder compatibility (Grok rec)
# -level 3.1             → safe ceiling for Samsung SM-X510 hardware decoder
# -preset ultrafast      → lowest encoder CPU
# -tune zerolatency      → disables B-frames/lookahead; minimises latency
# -b:v / -maxrate        → CBR-style control; stable bitrate for LAN streaming
# -g 8                   → keyframe every 8 frames (2s at 4fps); fast VLC connect
# -f mpegts -listen 1    → MPEG-TS container; ffmpeg HTTP server mode
# URL path /live.ts      → .ts extension helps VLC identify container (Grok rec)
# -loglevel error        → suppress per-frame info; still log errors to stream.log

# Run as background child (not exec) so this wrapper can catch exit code + clean up
nice -n 19 "$FFMPEG" \
    -f avfoundation \
    -framerate "$FRAMERATE" \
    -video_size "$VIDEO_SIZE" \
    -pixel_format "$PIX_FMT" \
    -i "$AVFOUNDATION_DEVICE" \
    -vf "scale=${VIDEO_SIZE}:flags=fast_bilinear" \
    -c:v libx264 \
    -preset ultrafast \
    -tune zerolatency \
    -profile:v baseline \
    -level:v 3.1 \
    -pix_fmt yuv420p \
    -b:v "$BITRATE" \
    -maxrate "$MAXRATE" \
    -bufsize "$BUFSIZE" \
    -g 8 \
    -threads "$THREADS" \
    -f mpegts \
    -listen 1 \
    "http://0.0.0.0:${STREAM_PORT}/live.ts" \
    -loglevel error &
FFMPEG_PID=$!

# Wait for ffmpeg; report non-zero exit so start-monitor can see it in the log
wait "$FFMPEG_PID"
FFMPEG_EXIT=$?
if [[ $FFMPEG_EXIT -ne 0 ]]; then
    warn "ffmpeg exited with code $FFMPEG_EXIT — check permissions or device index"
fi
