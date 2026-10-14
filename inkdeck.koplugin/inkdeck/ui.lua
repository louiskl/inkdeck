-- Shared drawing helpers ("design system") used by all widgets.
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local UI = {}

UI.ICON = {
    clock = 0xF017, weather = 0xE302, calendar = 0xF073, news = 0xF1EA,
    reminders = 0xF046, photo = 0xF03E, home = 0xF015, music = 0xF001,
    spotify = 0xF1BC, countdown = 0xF254, note = 0xF249, bulb = 0xF0EB,
    power = 0xF011, wifi = 0xF1EB, check = 0xF14A, box = 0xF096,
    play = 0xF04B, pause = 0xF04C, next = 0xF051, prev = 0xF048,
    vol_up = 0xF028, vol_down = 0xF027, left = 0xF104, right = 0xF105,
    up = 0xF106, down = 0xF107, refresh = 0xF021, cog = 0xF013,
    bolt = 0xF0E7, thermo = 0xF2C9, pin = 0xF08D, star = 0xF005, bell = 0xF0F3,
    sunrise = 0xE34C, sunset = 0xE34D, drop = 0xE373, wind = 0xE34B,
    battery = { 0xF244, 0xF243, 0xF242, 0xF241, 0xF240 },
    quote = 0xF10D, plug = 0xF1E6, toggle_on = 0xF205, toggle_off = 0xF204,
}

UI.RADIUS = 12
UI.HEADER = 30
UI.PAD = 12

-- Draws a tile frame with header label. Returns content rect x,y,w,h.
function UI.tile(c, p, title, icon, focused, opts)
    opts = opts or {}
    local r = UI.RADIUS
    c:roundrect(p.x, p.y, p.w, p.h, "white", r)
    local hh = UI.HEADER
    if focused then
        -- inverted header band
        c:roundrect(p.x, p.y, p.w, hh + r, "black", r)
        c:rect(p.x, p.y + hh, p.w, r, "white")
        c:frame(p.x, p.y, p.w, p.h, 4, "black", r)
    else
        c:frame(p.x, p.y, p.w, p.h, 2, "black", r)
        c:hline(p.x + 2, p.y + hh, p.w - 4, 1, "gray")
    end
    local fg = focused and "white" or "black"
    local tx = p.x + UI.PAD
    if icon then
        c:icon(icon, tx, p.y + 5, 16, { color = fg, w = 20, align = "center" })
        tx = tx + 26
    end
    local label = tostring(title or ""):upper()
    local right = opts.right and tostring(opts.right) or nil
    local rw = 0
    if right then
        rw = c:measure(right, { size = 13 })
        local lw = c:measure(label, { size = 13, bold = true })
        if tx + lw + rw + 12 > p.x + p.w - UI.PAD then
            rw = 0 -- not enough room: drop the extra info
        else
            c:text(right, p.x + p.w - UI.PAD - rw, p.y + 6, { size = 13, color = fg })
        end
    end
    c:text(label, tx, p.y + 6, { size = 13, bold = true, color = fg, maxw = p.x + p.w - UI.PAD - tx - rw - 8 })
    return p.x + UI.PAD, p.y + hh + 8, p.w - 2 * UI.PAD, p.h - hh - 8 - UI.PAD + 2
end

-- Full-screen header + footer. Returns content rect.
function UI.fullFrame(c, W, H, title, icon, hint, right)
    c:rect(0, 0, W, H, "white")
    local hh = 52
    c:rect(0, 0, W, hh, "black")
    local x = 18
    if icon then
        c:icon(icon, x, 12, 26, { color = "white", w = 34, align = "center" })
        x = x + 46
    end
    local rw = 0
    if right then
        rw = c:measure(right, { size = 18 })
        c:text(right, W - 18 - rw, 14, { size = 18, color = "white" })
    end
    c:text(tostring(title or ""), x, 11, { size = 22, bold = true, color = "white", maxw = W - x - rw - 30 })
    local fh = 36
    c:hline(0, H - fh, W, 2, "black")
    c:text(hint or T("Back: close"), 18, H - fh + 8, { size = 14, color = "dark", maxw = W - 36 })
    return 20, hh + 16, W - 40, H - hh - 16 - fh - 12
end

function UI.progress(c, x, y, w, h, frac, opts)
    opts = opts or {}
    frac = U.clamp(frac or 0, 0, 1)
    c:roundrect(x, y, w, h, opts.bg or "white", math.floor(h / 2))
    if (opts.border or 2) > 0 then c:frame(x, y, w, h, opts.border or 2, "black", math.floor(h / 2)) end
    local fw = math.floor((w - 4) * frac)
    if fw > 0 then c:roundrect(x + 2, y + 2, fw, h - 4, opts.color or "black", math.floor((h - 4) / 2)) end
end

-- centered message for loading / error states
function UI.message(c, x, y, w, h, text, icon)
    local cy = y + math.floor(h / 2) - 22
    if icon then
        c:icon(icon, x, cy - 10, 26, { w = w, align = "center", color = "gray" })
        cy = cy + 30
    end
    c:textbox(text, x, cy, w, math.max(20, y + h - cy), { size = 14, align = "center", color = "dark" })
end

-- a list row with optional checkbox/icon and right text; returns row height
function UI.row(c, x, y, w, o)
    local size = o.size or 16
    local _, th = c:measure("Ag", { size = size })
    local rh = o.height or (th + 10)
    local fg = "black"
    if o.selected then
        c:roundrect(x - 6, y, w + 12, rh, "black", 6)
        fg = "white"
    end
    local tx = x
    if o.icon then
        local iconw = math.floor(size * 1.5)
        c:icon(o.icon, x, y + math.floor((rh - size - 4) / 2), size + 2, { color = fg, w = iconw, align = "center" })
        tx = x + iconw + 8
    end
    local rw = 0
    if o.right then
        rw = c:measure(o.right, { size = size - 2, bold = o.right_bold })
        c:text(o.right, x + w - rw, y + math.floor((rh - th) / 2) + 1,
            { size = size - 2, color = o.selected and "white" or "dark", bold = o.right_bold })
        rw = rw + 10
    end
    c:text(o.text or "", tx, y + math.floor((rh - th) / 2),
        { size = size, bold = o.bold, color = o.dim and not o.selected and "gray" or fg, maxw = x + w - tx - rw })
    if o.strike then
        local sw = math.min(c:measure(o.text or "", { size = size }), x + w - tx - rw)
        c:hline(tx, y + math.floor(rh / 2), sw, 2, fg)
    end
    return rh
end

-- largest font size (<= max) so that s fits into maxw
function UI.fit(c, s, maxw, max, o)
    o = o or {}
    local size = max
    while size > 10 do
        local w = c:measure(s, { size = size, bold = o.bold, font = o.font })
        if w <= maxw then return size end
        size = math.floor(size * 0.92)
    end
    return size
end

-- small page-indicator / scroll arrows
function UI.scrollHint(c, x, y, w, can_up, can_down)
    if can_up then c:icon(UI.ICON.up, x + w - 14, y, 14, { color = "gray" }) end
    if can_down then c:icon(UI.ICON.down, x + w - 14, y + 16, 14, { color = "gray" }) end
end

return UI
