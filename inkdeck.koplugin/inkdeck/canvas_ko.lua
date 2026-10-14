-- Canvas implementation on top of KOReader's Blitbuffer + text widgets.
-- The PC preview tool implements the same API with Pillow.
--
-- All widgets draw in *logical* pixels of a 600 px-wide reference screen (Kindle 4).
-- On bigger/denser screens the canvas multiplies every coordinate and font size by
-- `scale`, so layouts look the same on a Paperwhite (1072 × 1448) or a Kobo Sage.
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Screen = require("device").screen

local Canvas = {}
Canvas.__index = Canvas

local NAMED = { black = 0x00, dark = 0x44, gray = 0x88, mid = 0xAA, light = 0xDD, white = 0xFF }

local color_cache = {}
local function col(c)
    if c == nil then c = "black" end
    local v = type(c) == "number" and c or NAMED[c] or 0
    local cc = color_cache[v]
    if not cc then
        cc = Blitbuffer.Color8(v)
        color_cache[v] = cc
    end
    return cc
end
Canvas.color = col

local FONTS = {
    sans = { "NotoSans-Regular.ttf", "NotoSans-Bold.ttf" },
    serif = { "NotoSerif-Regular.ttf", "NotoSerif-Bold.ttf" },
    mono = { "DroidSansMono.ttf", "DroidSansMono.ttf" },
}
local ICON_FONT = "nerdfonts/symbols.ttf"

-- KOReader scales font sizes by screen size; we want real pixels.
local scale = Screen:scaleBySize(1000) / 1000
local face_cache = {}
local function face(o)
    local family = FONTS[o.font or "sans"] or FONTS.sans
    local name = o.icon and ICON_FONT or family[o.bold and 2 or 1]
    local size = math.max(6, math.floor((o.size or 16) / scale + 0.5))
    local key = name .. "@" .. size
    local f = face_cache[key]
    if not f then
        f = Font:getFace(name, size)
        face_cache[key] = f
    end
    return f
end

-- w, h: logical size; scale: physical pixels per logical pixel
function Canvas.new(bb, ox, oy, w, h, scale)
    return setmetatable({ bb = bb, ox = ox or 0, oy = oy or 0, W = w, H = h, s = scale or 1, images = {} }, Canvas)
end

local floor = math.floor
-- logical -> physical (absolute position)
function Canvas:px(x) return self.ox + floor(x * self.s + 0.5) end
function Canvas:py(y) return self.oy + floor(y * self.s + 0.5) end
-- logical length -> physical length (edges rounded consistently)
local function len(self, a, l) return floor((a + l) * self.s + 0.5) - floor(a * self.s + 0.5) end

function Canvas:rect(x, y, w, h, c)
    if w <= 0 or h <= 0 then return end
    self.bb:paintRect(self:px(x), self:py(y), len(self, x, w), len(self, y, h), col(c))
end

function Canvas:frame(x, y, w, h, bw, c, r)
    self.bb:paintBorder(self:px(x), self:py(y), len(self, x, w), len(self, y, h),
        math.max(1, floor((bw or 1) * self.s + 0.5)), col(c), r and floor(r * self.s + 0.5) or nil)
end

function Canvas:roundrect(x, y, w, h, c, r)
    if w <= 0 or h <= 0 then return end
    if r and r > 0 then
        self.bb:paintRoundedRect(self:px(x), self:py(y), len(self, x, w), len(self, y, h), col(c), floor(r * self.s + 0.5))
    else
        self:rect(x, y, w, h, c)
    end
end

function Canvas:hline(x, y, w, t, c) self:rect(x, y, w, t or 1, c) end
function Canvas:vline(x, y, h, t, c) self:rect(x, y, t or 1, h, c) end

function Canvas:circle(cx, cy, r, c, ring)
    self.bb:paintCircle(self:px(cx), self:py(cy), floor(r * self.s + 0.5), col(c),
        ring and math.max(1, floor(ring * self.s + 0.5)) or nil)
end

function Canvas:invert(x, y, w, h)
    self.bb:invertRect(self:px(x), self:py(y), len(self, x, w), len(self, y, h))
end

local function make_text(self, s, o)
    local so = { font = o.font, bold = o.bold, icon = o.icon, size = (o.size or 16) * self.s }
    return TextWidget:new{
        text = tostring(s),
        face = face(so),
        bold = (o.bold and o.font == "mono") and true or false, -- other fonts use real bold files
        fgcolor = col(o.color),
        max_width = o.maxw and floor(o.maxw * self.s) or nil,
        padding = 0,
    }
end

-- returns logical width/height
function Canvas:measure(s, o)
    o = o or {}
    local tw = make_text(self, s, o)
    local sz = tw:getSize()
    tw:free()
    return sz.w / self.s, sz.h / self.s
end

-- o: size, bold, font, color, w (box width for align), align, maxw
function Canvas:text(s, x, y, o)
    o = o or {}
    if s == nil or s == "" then return 0, 0 end
    if o.w and not o.maxw then o.maxw = o.w end
    local tw = make_text(self, s, o)
    local sz = tw:getSize()
    local pw = o.w and floor(o.w * self.s) or 0
    local dx = 0
    if o.w and o.align == "center" then dx = floor((pw - sz.w) / 2)
    elseif o.w and o.align == "right" then dx = pw - sz.w end
    tw:paintTo(self.bb, self:px(x) + dx, self:py(y))
    tw:free()
    return sz.w / self.s, sz.h / self.s
end

function Canvas:icon(cp, x, y, size, o)
    o = o or {}
    local s = type(cp) == "number" and require("inkdeck/util").utf8_char(cp) or cp
    local oo = { icon = true, size = size, color = o.color, w = o.w, align = o.align }
    return self:text(s, x, y, oo)
end

-- multi-line text, wraps to w, clipped to h (with ellipsis). returns used height
function Canvas:textbox(s, x, y, w, h, o)
    o = o or {}
    if s == nil or s == "" or w <= 0 or h <= 0 then return 0 end
    local tb = TextBoxWidget:new{
        text = tostring(s),
        face = face({ font = o.font, bold = o.bold, size = (o.size or 16) * self.s }),
        width = len(self, x, w),
        height = len(self, y, h),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = o.align or "left",
        fgcolor = col(o.color),
        bgcolor = col(o.bg or "white"),
        line_height = o.line_height or 0.2,
    }
    local sz = tb:getSize()
    tb:paintTo(self.bb, self:px(x), self:py(y))
    local used = (tb.text_height or sz.h) / self.s
    tb:free()
    return math.min(used, h)
end

-- Draw an image file into a box. o.fill = true crops to fill the box ("cover"),
-- otherwise the image is fitted and centered. Scaled images are cached.
local RenderImage = require("ui/renderimage")
local img_cache, img_order = {}, {}
local IMG_CACHE_MAX = 4

local function cached_image(path, w, h, fill)
    local key = table.concat({ path, w, h, fill and "f" or "c" }, "|")
    local e = img_cache[key]
    if e then return e end
    local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, path, false)
    if not ok or not bb then return nil end
    local iw, ih = bb:getWidth(), bb:getHeight()
    local s = fill and math.max(w / iw, h / ih) or math.min(w / iw, h / ih)
    local nw, nh = math.max(1, math.floor(iw * s + 0.5)), math.max(1, math.floor(ih * s + 0.5))
    local ok2, sbb = pcall(RenderImage.scaleBlitBuffer, RenderImage, bb, nw, nh, true)
    if not ok2 or not sbb then return nil end
    e = { bb = sbb, w = nw, h = nh }
    img_cache[key] = e
    table.insert(img_order, key)
    while #img_order > IMG_CACHE_MAX do
        local old = table.remove(img_order, 1)
        if img_cache[old] then img_cache[old].bb:free() end
        img_cache[old] = nil
    end
    return e
end

function Canvas:image(path, x, y, w, h, o)
    if not path or w <= 0 or h <= 0 then return false end
    local X, Y = self:px(x) - self.ox, self:py(y) - self.oy
    w, h = len(self, x, w), len(self, y, h)
    x, y = X, Y
    local e = cached_image(path, w, h, o and o.fill)
    if not e then return false end
    local sx, sy = math.max(0, math.floor((e.w - w) / 2)), math.max(0, math.floor((e.h - h) / 2))
    local dx, dy = math.max(0, math.floor((w - e.w) / 2)), math.max(0, math.floor((h - e.h) / 2))
    local ok = pcall(self.bb.blitFrom, self.bb, e.bb, self.ox + x + dx, self.oy + y + dy, sx, sy,
        math.min(w, e.w), math.min(h, e.h))
    return ok
end

function Canvas.clearImageCache()
    for _, e in pairs(img_cache) do e.bb:free() end
    img_cache, img_order = {}, {}
end

return Canvas
