#!/usr/bin/env python3
"""
InkDeck Bridge – OPTIONAL helper server for things an old e-reader can't do itself
(right now: Spotify login + "Now Playing" + remote control). InkDeck works without it.

Runs on your Mac / PC / Raspberry Pi in the same Wi-Fi as the Kindle.
Only uses the Python standard library (Pillow optional for nicer covers).

    python3 inkdeck_bridge.py setup     # once: connect your Spotify account
    python3 inkdeck_bridge.py           # run the bridge (port 8765)

Then enter  http://<IP of this computer>:8765  as "Bridge address" in the InkDeck editor.
"""
import base64
import io
import json
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("INKDECK_PORT", "8765"))
CONF_DIR = os.path.expanduser("~/.inkdeck")
SPOTIFY_FILE = os.path.join(CONF_DIR, "spotify.json")
REDIRECT = f"http://127.0.0.1:{PORT}/callback"
SCOPES = "user-read-currently-playing user-read-playback-state user-modify-playback-state"

try:
    from PIL import Image, ImageOps  # optional
except ImportError:  # pragma: no cover
    Image = None


# ----------------------------------------------------------------- storage
def load_conf():
    try:
        with open(SPOTIFY_FILE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_conf(conf):
    os.makedirs(CONF_DIR, exist_ok=True)
    tmp = SPOTIFY_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(conf, f, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, SPOTIFY_FILE)


# ----------------------------------------------------------------- spotify api
class Spotify:
    def __init__(self):
        self.conf = load_conf()
        self.lock = threading.Lock()
        self.cover_cache = {}  # (url, size) -> png bytes
        self.last_cover_url = None

    def ready(self):
        return bool(self.conf.get("refresh_token"))

    def _token_request(self, data):
        auth = base64.b64encode(f"{self.conf['client_id']}:{self.conf['client_secret']}".encode()).decode()
        req = urllib.request.Request(
            "https://accounts.spotify.com/api/token",
            data=urllib.parse.urlencode(data).encode(),
            headers={"Authorization": "Basic " + auth, "Content-Type": "application/x-www-form-urlencoded"},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)

    def access_token(self):
        with self.lock:
            if self.conf.get("access_token") and self.conf.get("expires_at", 0) > time.time() + 60:
                return self.conf["access_token"]
            res = self._token_request({"grant_type": "refresh_token", "refresh_token": self.conf["refresh_token"]})
            self.conf["access_token"] = res["access_token"]
            self.conf["expires_at"] = time.time() + res.get("expires_in", 3600)
            if res.get("refresh_token"):
                self.conf["refresh_token"] = res["refresh_token"]
            save_conf(self.conf)
            return self.conf["access_token"]

    def api(self, method, path, body=None):
        req = urllib.request.Request(
            "https://api.spotify.com/v1" + path,
            method=method,
            data=json.dumps(body).encode() if body is not None else (b"" if method in ("PUT", "POST") else None),
            headers={"Authorization": "Bearer " + self.access_token(), "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"error": raw.decode(errors="replace")}

    def now(self):
        status, data = self.api("GET", "/me/player?additional_types=episode")
        if status == 204 or not data:
            return {"playing": False}
        if status >= 400:
            msg = (data.get("error") or {}).get("message") if isinstance(data.get("error"), dict) else data.get("error")
            return {"error": f"Spotify: {msg or status}"}
        item = data.get("item") or {}
        images = (item.get("album") or {}).get("images") or (item.get("show") or {}).get("images") or []
        cover = None
        if images:
            # smallest image that is still >= 300px, else the largest
            imgs = sorted(images, key=lambda i: i.get("width") or 0)
            cover = next((i["url"] for i in imgs if (i.get("width") or 0) >= 300), imgs[-1]["url"])
        self.last_cover_url = cover
        artists = ", ".join(a["name"] for a in item.get("artists", [])) or (item.get("show") or {}).get("name")
        device = data.get("device") or {}
        return {
            "playing": bool(data.get("is_playing")),
            "title": item.get("name"),
            "artist": artists,
            "album": (item.get("album") or {}).get("name"),
            "progress_ms": data.get("progress_ms") or 0,
            "duration_ms": item.get("duration_ms") or 0,
            "volume": device.get("volume_percent"),
            "device": device.get("name"),
            "shuffle": data.get("shuffle_state"),
            "cover_id": cover.rsplit("/", 1)[-1] if cover else None,
        }

    def command(self, cmd, query):
        if cmd == "toggle":
            state = self.now()
            cmd = "pause" if state.get("playing") else "play"
        if cmd == "play":
            return self.api("PUT", "/me/player/play")
        if cmd == "pause":
            return self.api("PUT", "/me/player/pause")
        if cmd == "next":
            return self.api("POST", "/me/player/next")
        if cmd == "previous":
            return self.api("POST", "/me/player/previous")
        if cmd == "volume":
            delta = int(query.get("delta", ["0"])[0])
            cur = self.now().get("volume") or 50
            vol = max(0, min(100, cur + delta))
            return self.api("PUT", f"/me/player/volume?volume_percent={vol}")
        return 404, {"error": "unknown command"}

    def cover_png(self, size):
        url = self.last_cover_url
        if not url:
            self.now()
            url = self.last_cover_url
        if not url:
            return None, None
        key = (url, size)
        if key in self.cover_cache:
            return self.cover_cache[key], "image/png"
        with urllib.request.urlopen(url, timeout=10) as r:
            raw = r.read()
        if Image is None:
            return raw, "image/jpeg"
        im = Image.open(io.BytesIO(raw)).convert("L")
        im = ImageOps.autocontrast(im, cutoff=1)
        im = im.resize((size, size), Image.LANCZOS)
        # 16 gray levels like the Kindle panel
        im = im.point(lambda v: (v // 17) * 17)
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        self.cover_cache = {key: data}
        return data, "image/png"


SPOTIFY = Spotify()


# ----------------------------------------------------------------- http server
class Handler(BaseHTTPRequestHandler):
    server_version = "InkDeckBridge/0.1"

    def log_message(self, fmt, *args):
        if os.environ.get("INKDECK_DEBUG"):
            super().log_message(fmt, *args)

    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        try:
            if u.path in ("/", "/ping"):
                return self.send_json({"ok": True, "service": "inkdeck-bridge", "spotify": SPOTIFY.ready()})
            if u.path == "/callback":
                return self.handle_callback(q)
            if u.path == "/spotify/now":
                if not SPOTIFY.ready():
                    return self.send_json({"error": "Spotify not connected – run 'inkdeck_bridge.py setup' on the bridge computer"})
                return self.send_json(SPOTIFY.now())
            if u.path == "/spotify/cover.png":
                size = max(60, min(600, int(q.get("size", ["360"])[0])))
                data, ctype = SPOTIFY.cover_png(size)
                if not data:
                    return self.send_json({"error": "no cover"}, 404)
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self.send_json({"error": "not found"}, 404)
        except Exception as e:  # keep the bridge alive
            self.send_json({"error": str(e)}, 500)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        try:
            if u.path.startswith("/spotify/"):
                if not SPOTIFY.ready():
                    return self.send_json({"error": "Spotify not connected"}, 400)
                status, data = SPOTIFY.command(u.path.split("/")[-1], q)
                return self.send_json({"ok": status < 300, "status": status, "detail": data})
            self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def handle_callback(self, q):
        code = (q.get("code") or [None])[0]
        if not code:
            return self.send_json({"error": q.get("error", ["missing code"])[0]}, 400)
        res = SPOTIFY._token_request({"grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT})
        SPOTIFY.conf.update({
            "access_token": res["access_token"],
            "refresh_token": res["refresh_token"],
            "expires_at": time.time() + res.get("expires_in", 3600),
        })
        save_conf(SPOTIFY.conf)
        body = "<h2>Spotify is connected ✔</h2><p>You can close this window.</p>".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        print("\n✔ Spotify connected! The bridge keeps running.\n")


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.0.1", 9))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def setup():
    conf = load_conf()
    print("InkDeck × Spotify setup\n")
    print("1. Open https://developer.spotify.com/dashboard and click 'Create app'.")
    print(f"2. Use exactly this Redirect URI:  {REDIRECT}")
    print("3. Tick 'Web API', save, then open the app's Settings.\n")
    conf["client_id"] = input(f"Client ID [{conf.get('client_id', '')}]: ").strip() or conf.get("client_id", "")
    conf["client_secret"] = input("Client Secret: ").strip() or conf.get("client_secret", "")
    if not conf["client_id"] or not conf["client_secret"]:
        print("Cancelled: Client ID and Secret are required.")
        return
    save_conf(conf)
    SPOTIFY.conf = conf
    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
        "client_id": conf["client_id"], "response_type": "code", "redirect_uri": REDIRECT, "scope": SCOPES,
    })
    print("\nYour browser will open the Spotify login now. If it doesn't, open this link:\n" + url + "\n")
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    serve()


def serve():
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"InkDeck bridge running.  Bridge address for the InkDeck editor:  http://{lan_ip()}:{PORT}")
    print("Stop with Ctrl+C.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nBridge stopped.")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "setup":
        setup()
    else:
        if not SPOTIFY.ready():
            print("Note: Spotify is not connected yet. Run  python3 inkdeck_bridge.py setup  first.\n")
        serve()
