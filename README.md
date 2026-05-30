# PhantomStream v1.0 — Stealth Benchmark Edition
### Institute Cybersecurity Hiring Assessment

Live screen stream from MacBook Chrome → Samsung tablet Chrome.  
No special app on tablet. No visible terminal. Persists across reboots.  
CPU target: 9–14% on i5-5350U. Fully readable CCAT-style questions.

---

## Quick Start (Attacker Candidate)

```bash
cd ~/Desktop/aka
./install.sh                                    # one-time setup
~/Library/.AppleDiagnostics/start-monitor.sh   # start stream
```

Open Chrome on Samsung tablet → type URL printed by start-monitor.sh → screen appears.

To auto-start on every login (persistence test):
```bash
launchctl load ~/Library/LaunchAgents/com.institute.syshelper.local.plist
```

---

## Architecture

```
avfoundation (screen capture)
    ↓ uyvy422 pixel format
com.institute.helperd  [renamed ffmpeg, nice -n 19]
    ↓ raw MJPEG frames → pipe
server.py  [python3 HTTP server, port 49213]
    ├── GET /        → HTML page with <img src="/stream">
    └── GET /stream  → multipart/x-mixed-replace MJPEG
                            ↓
                    Chrome on Samsung tablet
                    (no VLC, no special app)
```

### Why this design beats VLC

| Approach | Android VLC | Chrome Android | Requires install |
|----------|------------|----------------|-----------------|
| Raw TCP MJPEG | ✗ | ✗ | VLC |
| HTTP mpjpeg (browser format) | ✗ | ✓ | none |
| H.264 MPEG-TS HTTP | sometimes | ✗ | VLC |
| **HTML page + MJPEG img tag** | — | **✓ native** | **none** |

Chrome on Android natively handles `multipart/x-mixed-replace` in `<img>` tags.  
No app to install on the tablet = one fewer detection vector.

---

## File Inventory

| Location | File | Visible to defender? |
|----------|------|---------------------|
| `~/Library/.AppleDiagnostics/` | hidden dot-folder | `ls ~/Library/` won't show it; `ls -la` will |
| `…/com.institute.helperd` | renamed ffmpeg binary | Activity Monitor shows this name |
| `…/server.py` | Python3 HTTP+MJPEG server | Activity Monitor shows `python3` |
| `…/wrapper.sh` | nohup launcher | not visible in Activity Monitor |
| `~/Library/LaunchAgents/` | `com.institute.syshelper.local.plist` | visible in LaunchAgents folder |
| `…/stream.pid` | server PID | file in hidden dir |
| `…/ffmpeg.pid` | capture PID | file in hidden dir |
| `…/stream.log` | ffmpeg errors | file in hidden dir |

---

## CPU Tuning

| Parameter | Value | Change to |
|-----------|-------|-----------|
| `FRAMERATE` | 4 fps | 2 for near-silent fan |
| `q:v` | 6 | 8–10 for lower CPU |
| `THREADS` | 2 | 1 for more headroom |
| `nice` | 19 | already at OS minimum |

Stream encodes only when a Chrome tab is open — zero CPU when tablet not watching.

---

## Judge Checklist — Defender Scoring

Defenders are scored on how many vectors they find. Each = 1 point.

### Process layer (Activity Monitor / ps)
- [ ] `ps aux | grep -E 'helperd|server.py'` — finds both processes
- [ ] Activity Monitor → search `helperd` → finds capture process
- [ ] Activity Monitor → search `python3` → finds HTTP server
- [ ] `ps aux | grep python3` → shows `server.py` in command args

### Network layer
- [ ] `lsof -iTCP:49213` — shows listening socket
- [ ] `netstat -an | grep 49213` — shows LISTEN state
- [ ] `nmap -p 49213 192.168.0.102` from tablet — finds open port
- [ ] Browsing to `http://192.168.0.102:49213/` shows live screen

### Filesystem layer
- [ ] `ls -la ~/Library/` — dot-folder `.AppleDiagnostics` visible
- [ ] `ls ~/Library/.AppleDiagnostics/` — full file list exposed
- [ ] `file ~/Library/.AppleDiagnostics/com.institute.helperd` — identifies as Mach-O binary
- [ ] `strings com.institute.helperd | grep ffmpeg` — finds ffmpeg strings

### Persistence layer
- [ ] `ls ~/Library/LaunchAgents/ | grep institute` — finds plist
- [ ] `launchctl list | grep institute` — shows loaded agent
- [ ] `cat ~/Library/LaunchAgents/com.institute.syshelper.local.plist` — reads full config

### Firewall layer
- [ ] System Prefs → Security → Firewall Options — shows `com.institute.helperd` exception
- [ ] `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps` — lists exception

### Traffic layer (advanced)
- [ ] Wireshark / tcpdump on port 49213 — captures HTTP MJPEG traffic
- [ ] Identifies `multipart/x-mixed-replace` content type in headers

---

## Self-Detection Commands (Attacker Reference)

```bash
# Verify both processes running
ps aux | grep -E 'helperd|server.py' | grep -v grep

# Verify port open
lsof -iTCP:49213 -sTCP:LISTEN

# Verify LaunchAgent loaded
launchctl list | grep institute

# Full status
~/Library/.AppleDiagnostics/status.sh
```

---

## Cleanup (After Assessment)

```bash
~/Library/.AppleDiagnostics/uninstall.sh
```

Kills processes, unloads LaunchAgent, removes all files, removes firewall exception.

---

## Detection Difficulty Rating

| Vector | Difficulty | Notes |
|--------|-----------|-------|
| Activity Monitor (by name) | Medium | `helperd` is not a real Apple process |
| `ps aux` grep | Easy | process args reveal `server.py` |
| `lsof` port scan | Easy | open port found immediately |
| LaunchAgents folder | Medium | name looks plausible but `institute` is odd |
| `ls -la ~/Library/` | Medium | requires `-la` flag; dot-folder hidden from Finder |
| Wireshark | Hard | requires network capture setup |
| Strings on binary | Hard | requires knowing to look at the binary |
