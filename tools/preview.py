#!/usr/bin/env python3
"""
InkDeck PC preview: runs the real plugin Lua code (core + widgets) in LuaJIT
via `lupa`, draws with Pillow using KOReader's fonts, and writes PNG screenshots
at Kindle resolution. Uses mock data (no network needed).

    pip install lupa pillow
    python3 tools/preview.py --fonts /path/to/koreader-fonts --out previews/

Keys can be simulated:  --keys "Down,Press"   (applied before the screenshot)
"""
import argparse
import json
import math
import os
import sys
import time

from PIL import Image, ImageDraw, ImageFont
import lupa
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(ROOT, "inkdeck.koplugin")

NAMED = {"black": 0, "dark": 0x44, "gray": 0x88, "mid": 0xAA, "light": 0xDD, "white": 0xFF}


def col(c):
    if c is None:
        return 0
    if isinstance(c, (int, float)):
        return int(c)
    return NAMED.get(c, 0)


class Fonts:
    def __init__(self, fontdir):
        self.dir = fontdir
        self.cache = {}
        self.files = {
            ("sans", False): "noto/NotoSans-Regular.ttf",
            ("sans", True): "noto/NotoSans-Bold.ttf",
            ("serif", False): "noto/NotoSerif-Regular.ttf",
            ("serif", True): "noto/NotoSerif-Bold.ttf",
            ("mono", False): "droid/DroidSansMono.ttf",
            ("mono", True): "droid/DroidSansMono.ttf",
            ("icon", False): "nerdfonts/symbols.ttf",
            ("icon", True): "nerdfonts/symbols.ttf",
        }
        self.fallbacks = ["nerdfonts/symbols.ttf", "freefont/FreeSans.ttf"]
        from fontTools.ttLib import TTFont
        self.cmaps = {}
        for f in set(list(self.files.values()) + self.fallbacks):
            self.cmaps[f] = set(TTFont(os.path.join(fontdir, f)).getBestCmap().keys())

    def font(self, file, size):
        key = (file, size)
        if key not in self.cache:
            self.cache[key] = ImageFont.truetype(os.path.join(self.dir, file), size)
        return self.cache[key]

    def runs(self, text, family, bold, size):
        """split text into (font, substring) runs with glyph fallback"""
        primary = self.files[(family, bool(bold))]
        out = []
        for ch in text:
            f = primary
            if ord(ch) not in self.cmaps[primary] and ch not in "\n":
                for fb in self.fallbacks:
                    if ord(ch) in self.cmaps[fb]:
                        f = fb
                        break
            if out and out[-1][0] == f:
                out[-1][1] += ch
            else:
                out.append([f, ch])
        return [(self.font(f, size), s) for f, s in out]

    def metrics(self, family, bold, size):
        f = self.font(self.files[(family, bool(bold))], size)
        asc, desc = f.getmetrics()
        return asc, desc


class Canvas:
    def __init__(self, W, H, fonts, datadir):
        self.W, self.H = W, H
        self.img = Image.new("L", (W, H), 255)
        self.d = ImageDraw.Draw(self.img)
        self.fonts = fonts

    # ---------- shapes
    def rect(self, x, y, w, h, c):
        if w <= 0 or h <= 0:
            return
        self.d.rectangle([x, y, x + w - 1, y + h - 1], fill=col(c))

    def roundrect(self, x, y, w, h, c=None, r=None):
        if w <= 0 or h <= 0:
            return
        r = max(0, min(r or 0, w / 2, h / 2))
        self.d.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=r, fill=col(c))

    def frame(self, x, y, w, h, bw=1, c=None, r=None):
        r = max(0, min(r or 0, w / 2, h / 2))
        self.d.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=r, outline=col(c), width=int(bw or 1))

    def circle(self, cx, cy, r, c=None, ring=None):
        if ring is None or ring >= r:
            self.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col(c))
        else:
            self.d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col(c), width=int(ring))

    def invert(self, x, y, w, h):
        box = (int(x), int(y), int(x + w), int(y + h))
        reg = self.img.crop(box).point(lambda v: 255 - v)
        self.img.paste(reg, box)

    # ---------- text
    def _family(self, o):
        if o.get("icon"):
            return "icon"
        return o.get("font") or "sans"

    def _width(self, s, o):
        fam, bold, size = self._family(o), o.get("bold"), int(o.get("size") or 16)
        return sum(f.getlength(t) for f, t in self.fonts.runs(s, fam, bold, size))

    def _height(self, o):
        asc, desc = self.fonts.metrics(self._family(o), o.get("bold"), int(o.get("size") or 16))
        return asc + desc

    def _fit(self, s, o, maxw):
        if maxw is None or self._width(s, o) <= maxw:
            return s
        while s and self._width(s + "…", o) > maxw:
            s = s[:-1]
        return s.rstrip() + "…"

    def measure(self, s, o=None):
        o = dict(o or {})
        s = str(s)
        if o.get("maxw"):
            s = self._fit(s, o, o["maxw"])
        return math.ceil(self._width(s, o)), self._height(o)

    def text(self, s, x, y, o=None):
        o = dict(o or {})
        if s is None or s == "":
            return 0, 0
        s = str(s).replace("\n", " ")
        maxw = o.get("maxw") or o.get("w")
        s = self._fit(s, o, maxw)
        w = self._width(s, o)
        dx = 0
        if o.get("w") and o.get("align") == "center":
            dx = (o["w"] - w) // 2
        elif o.get("w") and o.get("align") == "right":
            dx = o["w"] - w
        fam, bold, size = self._family(o), o.get("bold"), int(o.get("size") or 16)
        asc, desc = self.fonts.metrics(fam, bold, size)
        px = x + dx
        for f, t in self.fonts.runs(s, fam, bold, size):
            self.d.text((px, y + asc), t, font=f, fill=col(o.get("color")), anchor="ls")
            px += f.getlength(t)
        return math.ceil(w), asc + desc

    def icon(self, cp, x, y, size, o=None):
        o = dict(o or {})
        s = chr(cp) if isinstance(cp, int) else str(cp)
        o2 = {"icon": True, "size": size, "color": o.get("color"), "w": o.get("w"), "align": o.get("align")}
        return self.text(s, x, y, o2)

    def textbox(self, s, x, y, w, h, o=None):
        o = dict(o or {})
        if s is None or s == "" or w <= 0 or h <= 0:
            return 0
        size = int(o.get("size") or 16)
        lh = round((1 + (o.get("line_height") or 0.2)) * size)
        maxlines = max(1, int(h // lh))
        lines = []
        for para in str(s).split("\n"):
            words = para.split(" ")
            cur = ""
            for wd in words:
                t = (cur + " " + wd) if cur else wd
                if self._width(t, o) <= w:
                    cur = t
                else:
                    if cur:
                        lines.append(cur)
                    cur = wd
                    while self._width(cur, o) > w and len(cur) > 1:
                        # hard break very long words
                        k = len(cur)
                        while k > 1 and self._width(cur[:k], o) > w:
                            k -= 1
                        lines.append(cur[:k])
                        cur = cur[k:]
            lines.append(cur)
        truncated = len(lines) > maxlines
        lines = lines[:maxlines]
        if truncated:
            lines[-1] = self._fit(lines[-1] + " …", o, w)
            if not lines[-1].endswith("…"):
                lines[-1] = lines[-1] + "…"
        asc, desc = self.fonts.metrics(self._family(o), o.get("bold"), size)
        top = (lh - (asc + desc)) // 2
        for i, line in enumerate(lines):
            ow = self._width(line, o)
            dx = 0
            if o.get("align") == "center":
                dx = (w - ow) // 2
            elif o.get("align") == "right":
                dx = w - ow
            self.text(line, x + dx, y + i * lh + top, {k: v for k, v in o.items() if k not in ("w", "align", "maxw")})
        return min(len(lines) * lh, h)

    def image(self, path, x, y, w, h, o=None):
        o = o or {}
        try:
            im = Image.open(path).convert("L")
        except Exception:
            return False
        w, h = int(w), int(h)
        if o.get("fill"):
            s = max(w / im.width, h / im.height)
            im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
            l, t = (im.width - w) // 2, (im.height - h) // 2
            im = im.crop((l, t, l + w, t + h))
        else:
            im.thumbnail((w, h), Image.LANCZOS)
        self.img.paste(im, (int(x + (w - im.width) // 2), int(y + (h - im.height) // 2)))
        return True


# ------------------------------------------------------------------ mock data
def weather_json(now_local_hour=19):
    import random
    random.seed(4)
    hours = [f"2026-10-14T{(now_local_hour + i) % 24:02d}:00" for i in range(24)]
    temps = [round(12.5 - 3 * math.sin((i + 2) / 5) - i * 0.1, 1) for i in range(24)]
    codes = [2, 2, 3, 3, 61, 61, 3, 2, 1, 0, 0, 1, 2, 2, 3, 3, 80, 61, 3, 2, 2, 1, 1, 0]
    rain = [0, 0, 10, 20, 60, 70, 40, 10, 0, 0, 0, 0, 0, 5, 10, 30, 55, 40, 10, 0, 0, 0, 0, 0]
    days = ["2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20"]
    return {
        "current": {"temperature_2m": 12.4, "apparent_temperature": 10.1, "weather_code": 2,
                    "wind_speed_10m": 14.2, "relative_humidity_2m": 78, "is_day": 0},
        "hourly": {"time": hours, "temperature_2m": temps, "weather_code": codes, "precipitation_probability": rain},
        "daily": {"time": days, "weather_code": [2, 61, 3, 0, 1, 80, 3],
                  "temperature_2m_max": [15.1, 13.2, 12.0, 14.8, 16.3, 11.9, 10.4],
                  "temperature_2m_min": [7.2, 8.1, 6.0, 4.3, 6.8, 5.5, 3.9],
                  "precipitation_probability_max": [20, 75, 30, 0, 5, 60, 35],
                  "sunrise": [d + "T07:42" for d in days], "sunset": [d + "T18:31" for d in days]},
    }


RSS = """<?xml version="1.0"?><rss><channel><title>tagesschau.de - Die Nachrichten der ARD</title>
<item><title>Bundestag beschließt neues Gesetz zur Digitalisierung der Verwaltung</title>
<description>&lt;p&gt;Behördengänge sollen künftig vollständig online möglich sein. Die Länder haben zwei Jahre Zeit für die Umsetzung.&lt;/p&gt;</description><pubDate>Wed, 14 Oct 2026 18:12:00 +0200</pubDate></item>
<item><title>Herbststurm erreicht Norddeutschland – Bahn warnt vor Ausfällen</title><description>Böen bis 100 km/h erwartet.</description></item>
<item><title>Forschende entwickeln Akku, der in fünf Minuten lädt</title><description>Labortests vielversprechend.</description></item>
<item><title>Champions League: Deutsche Teams mit gemischter Bilanz</title><description>Ein Sieg, ein Remis.</description></item>
<item><title>Inflation sinkt im September auf 1,9 Prozent</title><description>Energiepreise rückläufig.</description></item>
<item><title>Neue Studie: Deutsche lesen wieder mehr Bücher</title><description>Vor allem E-Reader legen zu.</description></item>
<item><title>Raumfahrt: ESA plant Mondlandung für 2031</title><description>Europa will eigenen Lander bauen.</description></item>
</channel></rss>"""


def make_assets(datadir, lang="en"):
    os.makedirs(os.path.join(datadir, "photos"), exist_ok=True)
    os.makedirs(os.path.join(datadir, "cache"), exist_ok=True)
    # procedural landscape photo
    p = os.path.join(datadir, "photos", "berge.png")
    if not os.path.exists(p):
        W, H = 900, 600
        im = Image.new("L", (W, H), 255)
        d = ImageDraw.Draw(im)
        for y in range(H):
            d.line([(0, y), (W, y)], fill=int(235 - y * 0.12))
        d.ellipse([620, 70, 720, 170], fill=250)
        for layer, (base, amp, shade) in enumerate([(330, 120, 150), (400, 90, 105), (470, 60, 60)]):
            pts = [(0, H)]
            for x in range(0, W + 30, 30):
                yv = base - amp * abs(math.sin(x / (140 + layer * 40) + layer)) - 20 * math.sin(x / 37.0)
                pts.append((x, yv))
            pts.append((W, H))
            d.polygon(pts, fill=shade)
        d.rectangle([0, 540, W, H], fill=40)
        im.save(p)
    cover = os.path.join(datadir, "cache", "demo_cover.png")
    if not os.path.exists(cover):
        S = 400
        im = Image.new("L", (S, S), 30)
        d = ImageDraw.Draw(im)
        for i in range(14):
            r = S - i * 28
            d.ellipse([(S - r) / 2, (S - r) / 2 + 30, (S + r) / 2, (S + r) / 2 + 30], outline=230 - i * 10, width=6)
        d.rectangle([0, 0, S, 90], fill=235)
        d.text((24, 22), "PIXEL HARBOR", fill=20, font=ImageFont.truetype(FONTDIR + "/noto/NotoSans-Bold.ttf", 34))
        im.save(cover)
    rem = os.path.join(datadir, "reminders.json")
    with open(rem, "w") as f:
        if lang == "de":
            items = [("Altglas wegbringen", False, "2026-10-15"), ("Mama zurückrufen", False, None),
                     ("Paket abholen", False, "2026-10-14T18:00"), ("Pflanzen gießen", True, None)]
        else:
            items = [("Take out the recycling", False, "2026-10-15"), ("Call mum back", False, None),
                     ("Pick up parcel", False, "2026-10-14T18:00"), ("Water the plants", True, None)]
        json.dump([dict(text=t, done=d, **({"due": due} if due else {})) for t, d, due in items], f)
    return cover


RSS_EN = """<?xml version="1.0"?><rss><channel><title>BBC News</title>
<item><title>Parliament passes landmark bill to digitise public services</title>
<description>&lt;p&gt;Most dealings with government offices should be possible online within two years, ministers say.&lt;/p&gt;</description><pubDate>Wed, 14 Oct 2026 18:12:00 +0100</pubDate></item>
<item><title>Autumn storm set to bring 60mph gusts and rail disruption</title><description>Travellers are advised to check before setting off.</description></item>
<item><title>Researchers unveil battery that charges in five minutes</title><description>Lab tests look promising.</description></item>
<item><title>Inflation falls to 1.9% as energy prices ease</title><description>Lowest level in three years.</description></item>
<item><title>Survey: e-readers drive a comeback in book reading</title><description>Older devices get a second life.</description></item>
<item><title>Space agency targets 2031 for crewed Moon landing</title><description>Europe plans its own lander.</description></item>
</channel></rss>"""

FONTDIR = None


def main():
    global FONTDIR
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", required=True)
    ap.add_argument("--out", default=os.path.join(ROOT, "previews"))
    ap.add_argument("--config", default=None)
    ap.add_argument("--scenes", default="all")
    ap.add_argument("--lang", default="en", help="en or de")
    args = ap.parse_args()
    FONTDIR = args.fonts
    os.makedirs(args.out, exist_ok=True)
    datadir = os.path.join(args.out, "_data_" + args.lang)
    cover = make_assets(datadir, args.lang)
    fonts = Fonts(args.fonts)

    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{PLUGIN}/?.lua;" .. package.path')
    lua.execute(f'require("inkdeck/i18n").set("{args.lang}")')
    # fixed clock: Wed 2026-10-14 19:41 Europe/Berlin (17:41 UTC)
    lua.execute('local U = require("inkdeck/util"); U.now = function() return 1792000000 end')
    fixed = lua.eval('require("inkdeck/util").now()')

    responses = {}

    def net_get(url, headers=None, timeout=None):
        if "open-meteo" in url:
            return json.dumps(weather_json())
        if "rss" in url or "xml" in url:
            return RSS if args.lang == "de" else RSS_EN
        return None, "offline (preview)"

    lua_net = lua.eval("""
        function(get)
            local json = require("inkdeck/json")
            local N = {}
            N.get = function(url, headers, timeout) return get(url) end
            N.getJson = function(url, headers, timeout)
                local body, err = get(url)
                if not body then return nil, err end
                return json.decode(body)
            end
            N.request = function() return "{}" end
            N.download = function() return false end
            return N
        end""")(net_get)

    def run_scene(name, W, H, keys, config=None):
        canvas = Canvas(W, H, fonts, datadir)
        ctx = lua.eval("{}")
        ctx["net"] = lua_net
        ctx["data_dir"] = datadir
        ctx["cache_dir"] = os.path.join(datadir, "cache")
        ctx["demo"] = True
        demo_sp = lua.eval("{}")
        for k, v in {"title": "Neon Nights", "artist": "Pixel Harbor", "album": "Lights Over Water",
                     "playing": True, "progress_ms": 98000, "duration_ms": 214000, "volume": 60,
                     "device": "MacBook", "cover_path": cover}.items():
            demo_sp[k] = v
        ctx["demo_music"] = demo_sp
        ctx["battery"] = lua.eval("function() return 76 end")
        Core = lua.eval('require("inkdeck/core")')
        cfg = config or Core.defaultConfig()
        dash = Core.new(lua.eval("function(c, x, W, H) return {config=c, ctx=x, W=W, H=H} end")(cfg, ctx, W, H))
        dash["config"]["hide_focus_after"] = 0
        # update all widgets once
        upd = lua.eval("""function(dash, now)
            for _, e in ipairs(dash:allInstances()) do e.inst:safeUpdate(now) end
        end""")
        upd(dash, fixed)
        for k in keys:
            dash.key(dash, k)
        cobj = lua.eval("""function(py)
            local C = {}
            local mt = { __index = function(t, k)
                local f = py[k]
                if type(f) == "number" or f == nil then return f end
                local w = function(self, ...) return f(...) end
                rawset(t, k, w)
                return w
            end }
            return setmetatable(C, mt)
        end""")
        luacanvas = cobj(canvas_proxy(lua, canvas))
        dash.draw(dash, luacanvas)
        path = os.path.join(args.out, name + ".png")
        canvas.img.save(path)
        return path

    scenes = [
        ("01_home_portrait", 600, 800, ["Down"]),
        ("02_home_landscape", 800, 600, ["Right"]),
        ("03_house_portrait", 600, 800, ["PgFwd"]),
        ("04_news_portrait", 600, 800, ["PgFwd", "PgFwd"]),
        ("05_weather_full", 600, 800, ["Down", "Press"]),
        ("06_calendar_full", 600, 800, ["Down", "Right", "Press"]),
        ("07_calendar_month", 600, 800, ["Down", "Right", "Press", "Press"]),
        ("08_nowplaying_full", 600, 800, ["Down", "Down", "Down", "Press"]),
        ("08b_home_nowplaying_focus", 600, 800, ["Down", "Down", "Down"]),
        ("09_reminders_full", 600, 800, ["Down", "Down", "Press", "Down"]),
        ("10_ha_full", 600, 800, ["PgFwd", "Press", "Down"]),
        ("11_news_full", 600, 800, ["PgFwd", "PgFwd", "Press", "Down"]),
        ("12_news_article", 600, 800, ["PgFwd", "PgFwd", "Press", "Down", "Press"]),
        ("13_menu", 600, 800, ["Menu"]),
        ("14_clock_full", 600, 800, ["Press"]),
        ("15_nowplaying_landscape", 800, 600, ["Down", "Right", "Press"]),
        ("16_house_landscape", 800, 600, ["PgFwd"]),
        ("17_photo_full", 600, 800, ["PgFwd", "Down", "Press"]),
    ]
    out = []
    for name, W, H, keys in scenes:
        if args.scenes != "all" and name not in args.scenes.split(","):
            continue
        out.append(run_scene(name, W, H, keys))
        print("wrote", out[-1])


def canvas_proxy(lua, canvas):
    """expose python canvas methods to Lua, converting Lua tables to dicts"""
    def conv(v):
        if luajit21.lua_type(v) == "table":
            return {k: v[k] for k in v.keys()}
        return v

    class P:
        pass

    p = lua.eval("{}")
    for name in ["rect", "roundrect", "frame", "circle", "invert", "measure", "text", "icon", "textbox", "image"]:
        fn = getattr(canvas, name)

        def mk(fn):
            def f(*a):
                a = [conv(x) for x in a]
                return fn(*a)
            return f
        p[name] = mk(fn)
    p["hline"] = lambda x, y, w, t=1, c=None: canvas.rect(x, y, w, t or 1, c)
    p["vline"] = lambda x, y, h, t=1, c=None: canvas.rect(x, y, t or 1, h, c)
    p["W"] = canvas.W
    p["H"] = canvas.H
    return p


if __name__ == "__main__":
    main()
