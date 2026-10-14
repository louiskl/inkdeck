# Writing an InkDeck widget

A widget is one Lua file in `inkdeck.koplugin/inkdeck/widgets/`. It draws itself with a small canvas API and,
optionally, fetches data and reacts to keys in its full-screen view. The same code runs on the device and in the
PC preview (`tools/preview.py`), so you can iterate without touching a Kindle.

## 1. Minimal widget

```lua
-- inkdeck.koplugin/inkdeck/widgets/hello.lua
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local T = require("inkdeck/i18n").t

local Hello = Base.define{
    type = "hello",            -- must match the file name
    name = "Hello",            -- shown in the tile header (translated through T)
    icon = UI.ICON.star,       -- a Nerd Font codepoint, see UI.ICON
    interval = 3600,           -- seconds between update() calls
    defaults = { greeting = "Hello, e-ink!" },
}

-- x, y, w, h: content area inside the tile; p: placement (p.cw / p.ch = size in grid cells)
function Hello:drawContent(c, x, y, w, h, p)
    local size = p.cw * p.ch >= 2 and 28 or 20
    c:textbox(self.s.greeting, x, y, w, h, { size = size, font = "serif" })
end

return Hello
```

Then register it:

1. add `"hello"` to `Core.WIDGET_TYPES` in `inkdeck/core.lua`
2. add `hello: { name: "Hello" }` to `TYPES` in `editor/index.html` (and a settings form in `settingsForm()` if needed)

Settings from the editor arrive in `self.s` (merged with `defaults`).

## 2. Fetching data

```lua
function Hello:update(now)
    local data, err = self.ctx.net.getJson("https://api.example.com/thing")
    if not data then
        self.error = T("Thing unavailable") .. "\n" .. tostring(err)   -- shown in the tile
        return true                                                       -- true = redraw
    end
    self.data = data
    self.has_data = true   -- with has_data, errors no longer replace the tile content
    self.error = nil
    return true
end
```

`update()` runs on KOReader's UI thread, one widget at a time – keep requests small and use timeouts.
Available helpers on `self.ctx`:

| | |
|---|---|
| `net.get(url, headers, timeout)` | body or `nil, err` |
| `net.getJson(url, headers, timeout)` | decoded table or `nil, err` |
| `net.request(method, url, body, headers, timeout)` | for POST/PUT |
| `net.download(url, path, headers)` | save to a file (e.g. into `ctx.cache_dir`) |
| `data_dir`, `cache_dir` | the `inkdeck/` folder on the device and its cache |
| `config` | the whole config (e.g. `config.homeassistant`) |
| `input(title, default, callback)` | on-screen keyboard |
| `demo` | true in the preview tool – return demo data so screenshots look nice |

## 3. Full-screen view and keys

```lua
function Hello:drawFull(c, W, H)
    local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, self:hint())
    c:text(self.s.greeting, x, y, { size = 40, bold = true, w = w, align = "center" })
end

function Hello:hint() return T("OK: wave   ·   Back: close") end

-- k is "Up", "Down", "Left", "Right" or "Press". Return true to redraw.
function Hello:key(k)
    if k == "Press" then self.s.greeting = "👋"; return true end
    return false
end
```

If you don't define `drawFull`, the tile content is drawn big. `Back` and the page keys are handled by InkDeck
(optionally define `:back()` returning true to consume Back first, e.g. to leave a sub-view).

Other optional hooks: `:tileRight()` (small text on the right of the tile header), `:fullInterval()` (faster updates
while open), `tick_minute = true` (repaint every minute, like the clock).

## 4. Canvas API

Coordinates are pixels; colors are `"black" "dark" "gray" "mid" "light" "white"` or 0–255.

| | |
|---|---|
| `c:rect(x, y, w, h, color)` | filled rectangle |
| `c:roundrect(x, y, w, h, color, radius)` | filled rounded rectangle |
| `c:frame(x, y, w, h, border, color, radius)` | outline |
| `c:hline(x, y, w, t, color)` / `c:vline(x, y, h, t, color)` | lines |
| `c:circle(cx, cy, r, color, ring)` | filled circle (or ring of width `ring`) |
| `c:text(s, x, y, o)` → `w, h` | single line; `o = {size, bold, font="sans"/"serif"/"mono", color, w, align, maxw}` – truncates with … |
| `c:measure(s, o)` → `w, h` | text size |
| `c:textbox(s, x, y, w, h, o)` → used height | wrapped text, ellipsis on overflow; `o.bg` = background color |
| `c:icon(codepoint, x, y, size, o)` | Nerd Font icon (weather, Font Awesome, …) |
| `c:image(path, x, y, w, h, {fill=true})` | JPG/PNG, fitted or cropped to fill |
| `c:invert(x, y, w, h)` | invert a region |

Shared building blocks in `inkdeck/ui.lua`: `UI.tile`, `UI.fullFrame`, `UI.row` (list rows with icon/checkbox/selection),
`UI.progress`, `UI.message`, `UI.fit` (largest font size that fits).

## 5. Translations

Wrap user-visible strings in `T("…")` (or `F("…%d…", n)` for formats) and add the German text to
`inkdeck/i18n.lua`. `python3 tools/test_util.py` fails if a translation is missing. New languages: add a table to
`TRANSLATIONS` and day/month names to `NAMES`.

## 6. Preview and test

```bash
python3 tools/preview.py --fonts koreader-fonts --out previews
python3 tools/test_util.py && python3 tools/test_glue.py
```

Add a scene to the `scenes` list in `tools/preview.py` to screenshot your widget (keys are simulated before the
screenshot).

## E-ink design tips

- Black, white and a few grays. Big type, generous spacing; small text below ~12 px is hard to read on old panels.
- Avoid constantly changing content – every change costs a refresh. Return `false` from `update()` if nothing changed.
- Prefer bold shapes for state (filled = on) over subtle color differences.
