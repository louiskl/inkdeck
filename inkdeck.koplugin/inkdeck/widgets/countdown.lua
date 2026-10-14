-- Countdown: days until an event
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Countdown = Base.define{
    type = "countdown",
    name = "Countdown",
    icon = UI.ICON.countdown,
    interval = 3600,
    defaults = { label = "Holidays", date = "2026-12-24" },
}

function Countdown:days()
    local target = U.parseIsoLocal(self.s.date or "")
    if not target then return nil end
    return math.floor((U.dayStart(target) - U.dayStart(U.now())) / 86400 + 0.5), target
end

function Countdown:drawContent(c, x, y, w, h, p)
    local d, target = self:days()
    if not d then UI.message(c, x, y, w, h, T("Date missing (YYYY-MM-DD)")) return end
    local num = tostring(math.abs(d))
    if d == 0 then num = T("Today") end
    local size = UI.fit(c, num, w * (p.cw >= 2 and 0.45 or 0.9), math.floor(h * 0.58), { font = "serif", bold = true })
    local _, th = c:measure(num, { size = size, font = "serif", bold = true })
    local yy = y + math.floor((h - th - 40) / 2)
    c:text(num, x, yy, { size = size, font = "serif", bold = true, w = w, align = "center" })
    yy = yy + th
    local label = self.s.label or ""
    local sub
    if d > 0 then sub = F(math.abs(d) == 1 and "day until %s" or "days until %s", label)
    elseif d < 0 then sub = F(math.abs(d) == 1 and "day since %s" or "days since %s", label)
    else sub = label end
    c:text(sub, x, yy + 2, { size = 16, bold = true, w = w, align = "center" })
    c:text(U.dateShort(target), x, yy + 24, { size = 13, color = "dark", w = w, align = "center" })
end

return Countdown
