local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Clock = Base.define{
    type = "clock",
    name = "Clock",
    icon = UI.ICON.clock,
    interval = 3600,
    tick_minute = true,
    defaults = { seconds = false },
}

function Clock:drawContent(c, x, y, w, h, p)
    local now = U.now()
    local t = U.localTable(now)
    local time = U.hhmm(now)
    local wide = p.cw >= 2 and p.ch == 1
    if wide then
        -- time on the left, date block on the right
        local tw = math.floor(w * 0.58)
        local size = UI.fit(c, time, tw, math.floor(h * 0.95), { font = "serif", bold = true })
        local _, th = c:measure(time, { size = size, font = "serif", bold = true })
        c:text(time, x, y + math.floor((h - th) / 2) - 4, { size = size, font = "serif", bold = true })
        local rx = x + tw + 16
        local rw = w - tw - 16
        c:vline(rx - 10, y + 6, h - 12, 2, "black")
        local yy = y + math.floor(h / 2) - 44
        c:text(U.DAYS[t.wday], rx, yy, { size = 22, bold = true, maxw = rw })
        c:text(U.dayMonth(now), rx, yy + 32, { size = 18, maxw = rw })
        c:text(F("Week %d  ·  %d", U.isoWeek(now), t.year), rx, yy + 60, { size = 14, color = "dark", maxw = rw })
        return
    end
    local size = UI.fit(c, time, w, math.floor(h * (p.ch >= 2 and 0.42 or 0.62)), { font = "serif", bold = true })
    local _, th = c:measure(time, { size = size, font = "serif", bold = true })
    local block = th + 50
    local yy = y + math.floor((h - block) / 2)
    c:text(time, x, yy, { size = size, font = "serif", bold = true, w = w, align = "center" })
    yy = yy + th + 4
    local date = w > 240 and U.dateLong(now) or U.dateShort(now)
    c:text(date, x, yy, { size = 16, w = w, align = "center" })
    if p.ch >= 2 then
        c:text(F("Week %d", U.isoWeek(now)), x, yy + 26, { size = 14, color = "dark", w = w, align = "center" })
    end
end

function Clock:drawFull(c, W, H)
    local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, T("Back: close"))
    local now = U.now()
    local t = U.localTable(now)
    local time = U.hhmm(now)
    local size = UI.fit(c, time, w, math.floor(h * 0.45), { font = "serif", bold = true })
    local _, th = c:measure(time, { size = size, font = "serif", bold = true })
    local yy = y + math.floor(h * 0.18)
    c:text(time, x, yy, { size = size, font = "serif", bold = true, w = w, align = "center" })
    yy = yy + th + 10
    c:hline(x + w * 0.2, yy, w * 0.6, 3, "black")
    yy = yy + 24
    c:text(U.DAYS[t.wday], x, yy, { size = 34, bold = true, w = w, align = "center" })
    yy = yy + 50
    c:text(U.dateFull(now), x, yy, { size = 24, w = w, align = "center" })
    yy = yy + 40
    local doy = U.days_from_civil(t.year, t.month, t.day) - U.days_from_civil(t.year, 1, 1) + 1
    c:text(F("Week %d  ·  Day %d of the year", U.isoWeek(now), doy), x, yy,
        { size = 16, color = "dark", w = w, align = "center" })
end

return Clock
