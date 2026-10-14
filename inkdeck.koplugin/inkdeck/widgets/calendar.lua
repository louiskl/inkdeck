-- Calendar from one or more ICS links (Google, iCloud, Outlook, Uni-Stundenplan, …)
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Calendar = Base.define{
    type = "calendar",
    name = "Calendar",
    icon = UI.ICON.calendar,
    interval = 900,
    defaults = { urls = {}, days = 30 },
}

function Calendar:init()
    self.events = {}
    self.mode = "agenda"
    self.scroll = 0
    self.month_offset = 0
end

local function demo_events(now)
    local d0 = U.dayStart(now)
    local function at(day, h, m) return d0 + day * 86400 + h * 3600 + (m or 0) * 60 end
    return {
        { start = at(0, 10, 0), ["end"] = at(0, 11, 30), title = "Lecture", location = "Hall 3" },
        { start = at(0, 18, 30), ["end"] = at(0, 20, 0), title = "Climbing with friends" },
        { start = at(1, 0), ["end"] = at(2, 0), title = "Project deadline", all_day = true },
        { start = at(1, 14, 15), ["end"] = at(1, 15, 45), title = "Dentist" },
        { start = at(3, 9, 0), ["end"] = at(3, 12, 0), title = "Exam" },
        { start = at(5, 19, 0), ["end"] = at(5, 23, 0), title = "Lena's birthday" },
    }
end

function Calendar:update(now)
    local urls = self.s.urls or {}
    if type(urls) == "string" then urls = { urls } end
    local from = U.dayStart(now)
    local to = from + (self.s.days or 30) * 86400
    local out = {}
    local errors = {}
    local local_file = self.ctx.data_dir .. "/calendar.ics"
    if U.fileExists(local_file) then U.parseICS(U.readFile(local_file), from, to, out) end
    for _, url in ipairs(urls) do
        url = tostring(url):gsub("^webcal://", "https://")
        local body, err = self.ctx.net.get(url, nil, 20)
        if body then U.parseICS(body, from, to, out)
        else errors[#errors + 1] = err end
    end
    if #urls == 0 and #out == 0 and self.ctx.demo then out = demo_events(now) end
    table.sort(out, function(a, b) return a.start < b.start end)
    self.events = out
    self.has_data = true
    if #urls == 0 and not U.fileExists(local_file) and not self.ctx.demo then
        self.error = T("No calendar linked yet.\nAdd an ICS link in the editor.")
        self.has_data = false
    elseif #errors > 0 and #out == 0 then
        self.error = T("Calendar unavailable") .. "\n" .. tostring(errors[1])
        self.has_data = false
    else
        self.error = nil
    end
    return true
end

-- events from now on (ongoing included)
function Calendar:upcoming(now)
    local out = {}
    for _, e in ipairs(self.events) do
        if e["end"] > now or (e.all_day and e.start >= U.dayStart(now)) then out[#out + 1] = e end
    end
    return out
end

local function when(e)
    if e.all_day then return T("all day") end
    return U.hhmm(e.start)
end

function Calendar:tileRight()
    local n = 0
    local now = U.now()
    local d1 = U.dayStart(now, 1)
    for _, e in ipairs(self:upcoming(now)) do if e.start < d1 then n = n + 1 end end
    return n > 0 and F("%d today", n) or nil
end

-- draws an agenda list; returns number of drawn events
function Calendar:drawAgenda(c, x, y, w, h, events, start_idx, size)
    size = size or 15
    local yy = y
    local last_day
    local drawn = 0
    local now = U.now()
    for i = start_idx or 1, #events do
        local e = events[i]
        local day = U.dayStart(e.start)
        if day ~= last_day then
            if yy + 24 + size * 2 > y + h then break end
            local label = U.relDay(e.start, now)
            if label == T("Today") or label == T("Tomorrow") then label = label .. ", " .. U.dateShort(e.start):sub(4) end
            c:text(label:upper(), x, yy, { size = 12, bold = true, color = "dark" })
            yy = yy + 18
            c:hline(x, yy, w, 1, "light")
            yy = yy + 5
            last_day = day
        end
        local rh = size + 12 + (e.location and size > 15 and 18 or 0)
        if yy + rh > y + h then break end
        local tw = math.max(56, c:measure(U.clock12 and "12:00 PM" or "00:00", { size = size - 2, bold = true }) + 10,
            c:measure(T("All day"), { size = size - 2, bold = true }) + 10)
        local ongoing = e.start <= now and e["end"] > now and not e.all_day
        if ongoing then
            c:roundrect(x - 4, yy - 2, w + 8, rh - 2, "black", 5)
        end
        local fg = ongoing and "white" or "black"
        c:text(e.all_day and T("All day") or U.hhmm(e.start), x, yy + 2, { size = size - 2, bold = true, color = fg })
        c:text(e.title, x + tw, yy, { size = size, color = fg, maxw = w - tw })
        if e.location and size > 15 then
            c:text(e.location, x + tw, yy + size + 6, { size = 13, color = ongoing and "white" or "dark", maxw = w - tw })
        end
        yy = yy + rh
        drawn = drawn + 1
    end
    return drawn
end

function Calendar:drawMonth(c, x, y, w, h, offset, compact)
    local now = U.now()
    local t = U.localTable(now)
    local ym = t.year * 12 + (t.month - 1) + (offset or 0)
    local year, month = math.floor(ym / 12), ym % 12 + 1
    local hh = compact and 0 or 34
    if not compact then
        c:text(U.MONTHS[month] .. " " .. year, x, y, { size = 20, bold = true, w = w, align = "center" })
    end
    local first_wd = U.weekday(year, month, 1)
    local ny, nm = year, month + 1
    if nm > 12 then ny, nm = year + 1, 1 end
    local dim = U.days_from_civil(ny, nm, 1) - U.days_from_civil(year, month, 1)
    local cw = w / 7
    local rows = math.ceil((first_wd - 1 + dim) / 7)
    local lh = compact and 18 or 26
    local ch = (h - hh - lh) / rows
    for i = 1, 7 do
        c:text(U.DAYS_SHORT[i], x + math.floor((i - 1) * cw), y + hh, { size = compact and 11 or 14, bold = true,
            w = math.floor(cw), align = "center", color = i >= 6 and "gray" or "dark" })
    end
    -- days with events
    local marks = {}
    for _, e in ipairs(self.events) do
        local lt = U.localTable(e.start)
        if lt.year == year and lt.month == month then marks[lt.day] = (marks[lt.day] or 0) + 1 end
    end
    local size = compact and math.min(13, math.floor(ch * 0.55)) or math.min(22, math.floor(ch * 0.4))
    for day = 1, dim do
        local idx = first_wd - 1 + day - 1
        local col, row = idx % 7, math.floor(idx / 7)
        local cx = x + math.floor(col * cw)
        local cy = y + hh + lh + math.floor(row * ch)
        local is_today = (year == t.year and month == t.month and day == t.day)
        local _, th = c:measure("0", { size = size })
        if is_today then
            local r = math.floor(math.min(cw, ch) / 2) - 1
            c:circle(cx + math.floor(cw / 2), cy + math.floor(th / 2) + 1, math.max(r, math.floor(th * 0.75)), "black")
        end
        c:text(tostring(day), cx, cy, { size = size, bold = is_today or marks[day] ~= nil, w = math.floor(cw), align = "center",
            color = is_today and "white" or (col >= 5 and "dark" or "black") })
        if marks[day] and not compact then
            c:rect(cx + math.floor(cw / 2) - 8, cy + th + 6, 16, 3, "black")
        elseif marks[day] and not is_today then
            c:rect(cx + math.floor(cw / 2) - 4, cy + th + 1, 8, 2, "black")
        end
    end
end

function Calendar:drawContent(c, x, y, w, h, p)
    local now = U.now()
    local evs = self:upcoming(now)
    if #evs == 0 and p.cw * p.ch < 4 then
        UI.message(c, x, y, w, h, F("No events in the next %d days", self.s.days or 30), UI.ICON.calendar)
        return
    end
    if p.cw == 1 and p.ch == 1 then
        local e = evs[1]
        local rel = U.relDay(e.start, now)
        c:text(rel:upper() .. (e.all_day and "" or (" · " .. U.hhmm(e.start))), x, y, { size = 13, bold = true, color = "dark", maxw = w })
        local used = c:textbox(e.title, x, y + 22, w, math.max(24, h - 50), { size = 20, bold = true })
        local more = #evs - 1
        if more > 0 then
            local nx = evs[2]
            c:text(T("Next: ") .. (nx.all_day and "" or U.hhmm(nx.start) .. " ") .. nx.title, x, y + h - 20, { size = 13, color = "dark", maxw = w })
        end
        return
    end
    if p.cw >= 2 and p.ch == 1 then
        -- date block left, list right
        local t = U.localTable(now)
        local bw = 96
        c:roundrect(x, y + 2, bw, h - 4, "black", 10)
        c:text(U.DAYS_SHORT[t.wday]:upper(), x, y + 10, { size = 14, bold = true, color = "white", w = bw, align = "center" })
        c:text(tostring(t.day), x, y + 26, { size = math.min(52, h - 60), bold = true, font = "serif", color = "white", w = bw, align = "center" })
        c:text(U.MONTHS_SHORT[t.month], x, y + h - 30, { size = 14, color = "white", w = bw, align = "center" })
        self:drawAgenda(c, x + bw + 16, y, w - bw - 16, h, evs, 1, 15)
        return
    end
    if p.cw >= 2 and p.ch >= 2 then
        local mh = math.floor(h * 0.48)
        self:drawMonth(c, x, y, w, mh, 0, true)
        c:hline(x, y + mh + 4, w, 2, "black")
        if #evs == 0 then
            UI.message(c, x, y + mh + 8, w, h - mh - 8, T("No upcoming events"))
        else
            self:drawAgenda(c, x, y + mh + 14, w, h - mh - 14, evs, 1, 15)
        end
        return
    end
    self:drawAgenda(c, x, y, w, h, evs, 1, 15)
end

function Calendar:hint()
    if self.mode == "month" then return T("◀ ▶ change month   ·   OK: agenda   ·   Back: close") end
    return T("▲ ▼ scroll   ·   OK: month view   ·   Back: close")
end

function Calendar:key(k)
    if k == "Press" then
        self.mode = self.mode == "agenda" and "month" or "agenda"
        self.month_offset = 0
        return true
    end
    if self.mode == "agenda" then
        if k == "Down" then self.scroll = math.min(self.scroll + 1, math.max(0, #self:upcoming(U.now()) - 1)) return true end
        if k == "Up" then self.scroll = math.max(0, self.scroll - 1) return true end
    else
        if k == "Right" or k == "Down" then self.month_offset = self.month_offset + 1 return true end
        if k == "Left" or k == "Up" then self.month_offset = self.month_offset - 1 return true end
    end
    return false
end

function Calendar:drawFull(c, W, H)
    local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, self:hint(),
        self.mode == "month" and T("Month") or T("Agenda"))
    if self.error and not self.has_data then UI.message(c, x, y, w, h, self.error, UI.ICON.calendar) return end
    if self.mode == "month" then
        self:drawMonth(c, x, y, w, h, self.month_offset, false)
        return
    end
    local evs = self:upcoming(U.now())
    if #evs == 0 then UI.message(c, x, y, w, h, T("No upcoming events"), UI.ICON.calendar) return end
    local n = self:drawAgenda(c, x, y, w, h, evs, self.scroll + 1, 19)
    UI.scrollHint(c, x, y, w, self.scroll > 0, self.scroll + n < #evs)
end

return Calendar
