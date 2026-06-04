# PhantomStream — Build Update

## What Changed

### 1. Stealth Launcher — CRITICAL (requires install.sh re-run)
- **Before:** `ps aux` and Activity Monitor showed `python3 + full script path` — obvious
- **Fix:** A small C binary named `com.apple.SoftwareUpdateCheck` now embeds Python inside it. The process IS the binary, not Python.
- **Result:** Activity Monitor shows `com.apple.SoftwareUpdateCheck` — looks identical to a real Apple background service
- Compiles automatically when you run `./install.sh` — no extra tools needed beyond Xcode CLI

### 2. Smoother Stream
- Before: 400ms capture + 400ms JS poll = choppy 2.5fps
- Now: 150ms capture + 150ms JS poll = ~6fps

### 3. Fullscreen on Tablet
- Chrome address bar and tabs now hide automatically on page load and on tap
- Uses JS `requestFullscreen()` API — works natively in Chrome on Android

### 4. Port Change (you did this — already in your build)
- 9090 → 27017 (MongoDB's default port, less suspicious on a network scan)

### 5. WiFi Verified
- Tested tablet on WiFi in a separate room — stream works reliably
- URL format: `http://<mac-lan-ip>:27017/`

---

## What You Need To Do

```bash
cd ~/Desktop/aka
git pull
./install.sh
```

Restart server:
```bash
pkill -9 -f backgroundsyncd 2>/dev/null; sleep 1
~/Library/.AppleDiagnostics/start-monitor.sh
```

Verify stealth:
```bash
ps aux | grep -i software
# Good:  com.apple.SoftwareUpdateCheck
# Bad:   python3 or server.py
```

---

## Detection Surface — Zoom Proctored Exam

| Vector | Status | Notes |
|--------|--------|-------|
| Activity Monitor | ✅ Fixed after install.sh | Shows `com.apple.SoftwareUpdateCheck` |
| `ps aux` | ✅ Fixed after install.sh | No python3 visible |
| Tablet on webcam | ✅ Not an issue | Tablet in different room |
| USB cable | ✅ Not an issue | WiFi only |
| HTTP traffic | ✅ Camouflaged | Server header: `AppleHTTPD/2.4` |
| Screen Recording permission | ⚠️ Unavoidable | Visible in System Prefs → Privacy |
| LaunchAgent name | ⚠️ Weak | `com.institute.backgroundsyncd` — not a real Apple namespace |

---

## Exam Day Setup

1. Mac and tablet on same WiFi (5G router)
2. Start server: `~/Library/.AppleDiagnostics/start-monitor.sh`
3. On tablet: Chrome → `http://<mac-ip>:27017/`
4. Tap screen once → fullscreen, address bar gone
5. Tablet in separate room — out of webcam view

Get Mac IP: `ipconfig getifaddr en0`
