-- Helpers: time zones, German date strings, files, text, ICS + RSS parsing.
-- Pure Lua, no KOReader dependencies (so it can be unit tested on a PC).
local json = require("inkdeck/json")

local U = {}

---------------------------------------------------------------- files
function U.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function U.writeFile(path, data)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return false, err end
    f:write(data)
    f:close()
    os.remove(path)
    return os.rename(tmp, path)
end

function U.fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

function U.mkdir(path)
    os.execute('mkdir -p "' .. path .. '"')
end

function U.loadJson(path)
    local s = U.readFile(path)
    if not s then return nil, "missing" end
    return json.decode(s)
end

function U.saveJson(path, t)
    return U.writeFile(path, json.encode(t, true))
end

function U.listDir(path, pattern)
    local out = {}
    local p = io.popen('ls -1 "' .. path .. '" 2>/dev/null')
    if not p then return out end
    for line in p:lines() do
        if not pattern or line:lower():match(pattern) then out[#out + 1] = line end
    end
    p:close()
    table.sort(out)
    return out
end

---------------------------------------------------------------- tables
function U.merge(defaults, t)
    local out = {}
    for k, v in pairs(defaults or {}) do out[k] = v end
    for k, v in pairs(t or {}) do
        if v ~= json.null then out[k] = v end
    end
    return out
end

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

---------------------------------------------------------------- time
-- We never trust the system time zone (old Kindles often run in UTC).
-- All wall-clock values go through U.localTable(epoch) using the configured zone.

-- days since 1970-01-01 for a civil date (Howard Hinnant's algorithm)
local function days_from_civil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
U.days_from_civil = days_from_civil

-- epoch seconds for a UTC wall-clock table
function U.timegm(t)
    local y, m = t.year, t.month
    y = y + math.floor((m - 1) / 12)
    m = (m - 1) % 12 + 1
    return days_from_civil(y, m, t.day) * 86400
        + (t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
end

-- weekday (1=Monday..7=Sunday) of a civil date
function U.weekday(y, m, d)
    local days = days_from_civil(y, m, d)
    return (days + 3) % 7 + 1 -- 1970-01-01 was a Thursday
end

local function last_sunday(y, m)
    local dim = ({ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
    for d = dim, dim - 6, -1 do
        if U.weekday(y, m, d) == 7 then return d end
    end
end

-- Built-in zones with EU-style DST (last Sun Mar 01:00 UTC -> last Sun Oct 01:00 UTC)
local ZONES = {
    ["Europe/Berlin"] = 1, ["Europe/Vienna"] = 1, ["Europe/Zurich"] = 1,
    ["Europe/Paris"] = 1, ["Europe/Amsterdam"] = 1, ["Europe/Rome"] = 1,
    ["Europe/Madrid"] = 1, ["Europe/Brussels"] = 1, ["Europe/Warsaw"] = 1,
    ["Europe/Prague"] = 1, ["Europe/Stockholm"] = 1, ["Europe/Copenhagen"] = 1,
    ["Europe/Oslo"] = 1, ["Europe/London"] = 0, ["Europe/Dublin"] = 0,
    ["Europe/Lisbon"] = 0, ["Europe/Helsinki"] = 2, ["Europe/Athens"] = 2,
}

-- North American zones (DST: 2nd Sunday March 02:00 -> 1st Sunday November 02:00 local)
local ZONES_US = {
    ["America/New_York"] = -5, ["America/Toronto"] = -5, ["America/Chicago"] = -6,
    ["America/Denver"] = -7, ["America/Los_Angeles"] = -8, ["America/Vancouver"] = -8,
}

local function nth_sunday(y, m, n)
    local count = 0
    for d = 1, 31 do
        if U.weekday(y, m, d) == 7 then
            count = count + 1
            if count == n then return d end
        end
    end
end

U.timezone = "system"

-- Offset in seconds from UTC at a given UTC epoch
function U.offset(epoch)
    local tz = U.timezone
    if tz == "system" then
        local lt = os.date("*t", epoch)
        local ut = os.date("!*t", epoch)
        lt.isdst = false
        return U.timegm(lt) - U.timegm(ut)
    end
    local base = ZONES[tz]
    if base then
        local y = tonumber(os.date("!%Y", epoch))
        local s = U.timegm({ year = y, month = 3, day = last_sunday(y, 3), hour = 1 })
        local e = U.timegm({ year = y, month = 10, day = last_sunday(y, 10), hour = 1 })
        if epoch >= s and epoch < e then return (base + 1) * 3600 end
        return base * 3600
    end
    local us = ZONES_US[tz]
    if us then
        local y = tonumber(os.date("!%Y", epoch))
        local s = U.timegm({ year = y, month = 3, day = nth_sunday(y, 3, 2), hour = 2 - us })
        local e = U.timegm({ year = y, month = 11, day = nth_sunday(y, 11, 1), hour = 2 - (us + 1) })
        if epoch >= s and epoch < e then return (us + 1) * 3600 end
        return us * 3600
    end
    if tz == "UTC" then return 0 end
    -- fixed offsets: "+02:00", "-5"
    local sign, h, m = tostring(tz):match("^([+-]?)(%d%d?):?(%d?%d?)$")
    if h then
        local off = tonumber(h) * 3600 + (tonumber(m) or 0) * 60
        return sign == "-" and -off or off
    end
    return 0
end

U.now = function() return os.time() end

-- wall-clock table {year,month,day,hour,min,sec,wday(1=Mon)} for an epoch
function U.localTable(epoch)
    epoch = epoch or U.now()
    local t = os.date("!*t", epoch + U.offset(epoch))
    t.wday = U.weekday(t.year, t.month, t.day)
    return t
end

-- epoch for a local wall-clock table
function U.localEpoch(t)
    local guess = U.timegm(t)
    local off = U.offset(guess - U.offset(guess))
    return guess - off
end

-- local midnight epoch of the day containing epoch (+ n days)
function U.dayStart(epoch, plus_days)
    local t = U.localTable(epoch)
    return U.localEpoch({ year = t.year, month = t.month, day = t.day + (plus_days or 0), hour = 0 })
end

-- Day/month names come from the active language (see i18n.lua)
local I18N = require("inkdeck/i18n")
setmetatable(U, { __index = function(_, k)
    if k == "DAYS" or k == "DAYS_SHORT" or k == "MONTHS" or k == "MONTHS_SHORT" then return I18N.names()[k] end
end })

U.clock12 = false -- 12-hour clock ("7:46 PM")

function U.hhmm(epoch)
    local t = U.localTable(epoch)
    if U.clock12 then
        local h = t.hour % 12
        if h == 0 then h = 12 end
        return string.format("%d:%02d %s", h, t.min, t.hour < 12 and "AM" or "PM")
    end
    return string.format("%02d:%02d", t.hour, t.min)
end

-- time without AM/PM suffix (for huge clock digits) + suffix separately
function U.hhmmParts(epoch)
    local s = U.hhmm(epoch)
    local main, suffix = s:match("^(.-) ([AP]M)$")
    return main or s, suffix
end

function U.dateLong(epoch)
    local t = U.localTable(epoch)
    if I18N.lang == "de" then
        return string.format("%s, %d. %s", U.DAYS[t.wday], t.day, U.MONTHS[t.month])
    end
    return string.format("%s, %s %d", U.DAYS[t.wday], U.MONTHS[t.month], t.day)
end

-- "Wed 14 Oct" / "Mi 14.10."
function U.dateShort(epoch)
    local t = U.localTable(epoch)
    if I18N.lang == "de" then
        return string.format("%s %d.%d.", U.DAYS_SHORT[t.wday], t.day, t.month)
    end
    return string.format("%s %d %s", U.DAYS_SHORT[t.wday], t.day, U.MONTHS_SHORT[t.month])
end

-- "14 October 2026" / "14. Oktober 2026"
function U.dateFull(epoch)
    local t = U.localTable(epoch)
    if I18N.lang == "de" then return string.format("%d. %s %d", t.day, U.MONTHS[t.month], t.year) end
    return string.format("%d %s %d", t.day, U.MONTHS[t.month], t.year)
end

-- "14 October" / "14. Oktober"
function U.dayMonth(epoch)
    local t = U.localTable(epoch)
    if I18N.lang == "de" then return string.format("%d. %s", t.day, U.MONTHS[t.month]) end
    return string.format("%d %s", t.day, U.MONTHS[t.month])
end

-- ISO week number
function U.isoWeek(epoch)
    local t = U.localTable(epoch)
    local days = days_from_civil(t.year, t.month, t.day)
    local thursday = days - (t.wday - 1) + 3
    local ty = tonumber(os.date("!%Y", thursday * 86400))
    local jan1 = days_from_civil(ty, 1, 1)
    return math.floor((thursday - jan1) / 7) + 1
end

-- "Today", "Tomorrow", or a short date
function U.relDay(epoch, now)
    now = now or U.now()
    local d0 = U.dayStart(now)
    if epoch >= d0 and epoch < U.dayStart(now, 1) then return I18N.t("Today") end
    if epoch >= U.dayStart(now, 1) and epoch < U.dayStart(now, 2) then return I18N.t("Tomorrow") end
    return U.dateShort(epoch)
end

-- parse "2026-10-14T13:00" / "2026-10-14" as local time
function U.parseIsoLocal(s)
    local y, mo, d, h, mi = tostring(s):match("^(%d+)-(%d+)-(%d+)T?(%d*):?(%d*)")
    if not y then return nil end
    return U.localEpoch({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h) or 0, min = tonumber(mi) or 0 })
end

---------------------------------------------------------------- text
function U.trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
    auml = "ä", ouml = "ö", uuml = "ü", Auml = "Ä", Ouml = "Ö", Uuml = "Ü",
    szlig = "ß", eacute = "é", egrave = "è", hellip = "…", ndash = "–",
    mdash = "—", bdquo = "„", ldquo = "“", rdquo = "”", lsquo = "‘", rsquo = "’",
    laquo = "«", raquo = "»", euro = "€",
}

local function utf8_char(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
        0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
U.utf8_char = utf8_char

function U.decodeEntities(s)
    s = s:gsub("&#[xX](%x+);", function(h) return utf8_char(tonumber(h, 16)) end)
    s = s:gsub("&#(%d+);", function(d) return utf8_char(tonumber(d)) end)
    s = s:gsub("&(%a+);", function(n) return ENTITIES[n] or ("&" .. n .. ";") end)
    return s
end

function U.stripHtml(s)
    s = tostring(s or "")
    s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    for _ = 1, 2 do -- twice: feeds often contain entity-encoded HTML
        s = s:gsub("<[bB][rR]%s*/?>", "\n"):gsub("</[pP]>", "\n")
        s = s:gsub("<[^>]*>", "")
        s = U.decodeEntities(s)
    end
    s = s:gsub("[ \t]+", " "):gsub("\n%s*\n+", "\n")
    return U.trim(s)
end

function U.urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- count UTF-8 characters
function U.ulen(s)
    local _, n = tostring(s):gsub("[^\128-\191]", "")
    return n
end

---------------------------------------------------------------- RSS / Atom
function U.parseFeed(xml)
    local items = {}
    if not xml then return items end
    local function tag(block, name)
        local v = block:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
        return v and U.stripHtml(v) or nil
    end
    for block in xml:gmatch("<item[%s>].-</item>") do
        items[#items + 1] = {
            title = tag(block, "title") or "",
            text = tag(block, "description") or tag(block, "content:encoded") or "",
            date = tag(block, "pubDate"),
        }
    end
    if #items == 0 then
        for block in xml:gmatch("<entry[%s>].-</entry>") do
            items[#items + 1] = {
                title = tag(block, "title") or "",
                text = tag(block, "summary") or tag(block, "content") or "",
                date = tag(block, "updated") or tag(block, "published"),
            }
        end
    end
    local feed_title = xml:match("<channel[^>]*>.-<title[^>]*>(.-)</title>") or xml:match("<feed[^>]*>.-<title[^>]*>(.-)</title>")
    return items, feed_title and U.stripHtml(feed_title) or nil
end

---------------------------------------------------------------- ICS
local function ics_unfold(s)
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    s = s:gsub("\n[ \t]", "")
    return s
end

local function ics_unescape(v)
    return (v:gsub("\\[nN]", "\n"):gsub("\\([,;\\])", "%1"))
end

-- returns epoch, all_day
local function ics_time(value, params)
    local y, m, d = value:match("^(%d%d%d%d)(%d%d)(%d%d)$")
    if y then
        return U.localEpoch({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 }), true
    end
    local h, mi, s
    y, m, d, h, mi, s = value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)")
    if not y then return nil end
    local t = { year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) }
    if value:sub(-1) == "Z" then return U.timegm(t), false end
    -- TZID or floating time: interpreted in the configured zone
    return U.localEpoch(t), false
end

local WD = { MO = 1, TU = 2, WE = 3, TH = 4, FR = 5, SA = 6, SU = 7 }

local function parse_rrule(s)
    local r = {}
    for k, v in s:gmatch("([%u]+)=([^;]+)") do r[k] = v end
    r.INTERVAL = tonumber(r.INTERVAL) or 1
    r.COUNT = tonumber(r.COUNT)
    if r.UNTIL then r.UNTIL_E = ics_time(r.UNTIL) end
    if r.BYDAY then
        local days = {}
        for dd in r.BYDAY:gmatch("[%+%-]?%d*(%u%u)") do days[WD[dd]] = true end
        r.DAYS = days
    end
    return r
end

-- expand one event into occurrences within [from, to)
local function expand(ev, from, to, out)
    local dur = (ev.dtend or ev.start) - ev.start
    local function add(st)
        if ev.exdates[st] then return end
        if st + math.max(dur, 1) > from and st < to then
            out[#out + 1] = { start = st, ["end"] = st + dur, all_day = ev.all_day,
                title = ev.title, location = ev.location }
        end
    end
    if not ev.rrule then add(ev.start) return end
    local r = ev.rrule
    local base = U.localTable(ev.start)
    local count, n = 0, 0
    local limit = r.UNTIL_E and (r.UNTIL_E + 1) or math.huge
    local max_iter = 3000
    local function occ(st)
        if st > limit then return false end
        if r.COUNT and count >= r.COUNT then return false end
        if st >= ev.start then
            count = count + 1
            add(st)
        end
        return st < to
    end
    if r.FREQ == "DAILY" then
        while n < max_iter do
            local st = U.localEpoch({ year = base.year, month = base.month, day = base.day + n * r.INTERVAL,
                hour = base.hour, min = base.min, sec = base.sec })
            if not occ(st) then break end
            n = n + 1
        end
    elseif r.FREQ == "WEEKLY" then
        local days = r.DAYS or { [base.wday] = true }
        local week0 = base.day - (base.wday - 1)
        while n < max_iter do
            local stop = false
            for wd = 1, 7 do
                if days[wd] then
                    local st = U.localEpoch({ year = base.year, month = base.month,
                        day = week0 + n * 7 * r.INTERVAL + (wd - 1), hour = base.hour, min = base.min, sec = base.sec })
                    if not occ(st) then stop = true break end
                end
            end
            if stop then break end
            n = n + 1
        end
    elseif r.FREQ == "MONTHLY" then
        while n < max_iter do
            local st = U.localEpoch({ year = base.year, month = base.month + n * r.INTERVAL, day = base.day,
                hour = base.hour, min = base.min, sec = base.sec })
            if not occ(st) then break end
            n = n + 1
        end
    elseif r.FREQ == "YEARLY" then
        while n < 200 do
            local st = U.localEpoch({ year = base.year + n * r.INTERVAL, month = base.month, day = base.day,
                hour = base.hour, min = base.min, sec = base.sec })
            if not occ(st) then break end
            n = n + 1
        end
    else
        add(ev.start)
    end
end

-- Parse ICS text and return occurrences sorted by start within [from, to)
function U.parseICS(text, from, to, out)
    out = out or {}
    if not text then return out end
    text = ics_unfold(text)
    for block in text:gmatch("BEGIN:VEVENT(.-)END:VEVENT") do
        local ev = { exdates = {} }
        local cancelled = false
        for line in block:gmatch("[^\n]+") do
            local name, params, value = line:match("^([%w%-]+)([^:]*):(.*)$")
            if name then
                if name == "SUMMARY" then ev.title = ics_unescape(value)
                elseif name == "LOCATION" then ev.location = ics_unescape(value)
                elseif name == "DTSTART" then ev.start, ev.all_day = ics_time(value, params)
                elseif name == "DTEND" then ev.dtend = ics_time(value, params)
                elseif name == "DURATION" then ev.duration = value
                elseif name == "RRULE" then ev.rrule = parse_rrule(value)
                elseif name == "EXDATE" then
                    for v in value:gmatch("[^,]+") do
                        local e = ics_time(v, params)
                        if e then ev.exdates[e] = true end
                    end
                elseif name == "STATUS" and value == "CANCELLED" then cancelled = true
                elseif name == "RECURRENCE-ID" then ev.is_override = true
                end
            end
        end
        if ev.start and not cancelled then
            if not ev.dtend and ev.duration then
                local w = tonumber(ev.duration:match("(%d+)W")) or 0
                local d = tonumber(ev.duration:match("(%d+)D")) or 0
                local h = tonumber(ev.duration:match("(%d+)H")) or 0
                local m = tonumber(ev.duration:match("(%d+)M")) or 0
                ev.dtend = ev.start + w * 604800 + d * 86400 + h * 3600 + m * 60
            end
            if not ev.dtend and ev.all_day then ev.dtend = ev.start + 86400 end
            ev.title = ev.title or "(ohne Titel)"
            expand(ev, from, to, out)
        end
    end
    table.sort(out, function(a, b)
        if a.start == b.start then return (a.all_day and 1 or 0) > (b.all_day and 1 or 0) end
        return a.start < b.start
    end)
    return out
end

return U
