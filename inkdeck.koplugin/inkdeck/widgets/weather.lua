-- Weather via Open-Meteo (free, no API key)
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Weather = Base.define{
    type = "weather",
    name = "Weather",
    icon = UI.ICON.weather,
    interval = 1800,
    defaults = { city = "London", lat = 51.5072, lon = -0.1276 },
}

-- WMO weather code -> text, day icon, night icon
local CODES = {
    [0] = { "Clear", 0xE30D, 0xE32B },
    [1] = { "Mostly clear", 0xE30C, 0xE37B },
    [2] = { "Partly cloudy", 0xE302, 0xE37E },
    [3] = { "Overcast", 0xE312, 0xE312 },
    [45] = { "Fog", 0xE313, 0xE313 }, [48] = { "Rime fog", 0xE313, 0xE313 },
    [51] = { "Light drizzle", 0xE31B, 0xE31B }, [53] = { "Drizzle", 0xE31B, 0xE31B }, [55] = { "Heavy drizzle", 0xE31B, 0xE31B },
    [56] = { "Freezing drizzle", 0xE3AD, 0xE3AD }, [57] = { "Freezing drizzle", 0xE3AD, 0xE3AD },
    [61] = { "Light rain", 0xE318, 0xE318 }, [63] = { "Rain", 0xE318, 0xE318 }, [65] = { "Heavy rain", 0xE318, 0xE318 },
    [66] = { "Freezing rain", 0xE3AD, 0xE3AD }, [67] = { "Freezing rain", 0xE3AD, 0xE3AD },
    [71] = { "Light snow", 0xE31A, 0xE31A }, [73] = { "Snow", 0xE31A, 0xE31A }, [75] = { "Heavy snow", 0xE31A, 0xE31A },
    [77] = { "Snow grains", 0xE31A, 0xE31A },
    [80] = { "Showers", 0xE319, 0xE319 }, [81] = { "Showers", 0xE319, 0xE319 }, [82] = { "Heavy showers", 0xE319, 0xE319 },
    [85] = { "Snow showers", 0xE31A, 0xE31A }, [86] = { "Snow showers", 0xE31A, 0xE31A },
    [95] = { "Thunderstorm", 0xE31D, 0xE31D }, [96] = { "Thunderstorm, hail", 0xE31D, 0xE31D }, [99] = { "Thunderstorm, hail", 0xE31D, 0xE31D },
}

local function code(c, is_day)
    local e = CODES[tonumber(c) or -1] or { "–", 0xE312, 0xE312 }
    return T(e[1]), (is_day == false) and e[3] or e[2]
end
Weather.code = code

local function num(v) return type(v) == "number" and v or nil end

local function deg(v) v = num(v) return v and string.format("%d°", math.floor(v + 0.5)) or "–" end

function Weather:title() return self.s.title or self.s.city or T("Weather") end

function Weather:update(now)
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
        .. "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,is_day"
        .. "&hourly=temperature_2m,weather_code,precipitation_probability"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"
        .. "&timezone=auto&forecast_days=7&forecast_hours=24",
        self.s.lat, self.s.lon)
    local data, err = self.ctx.net.getJson(url)
    if not data then self.error = T("Weather unavailable") .. "\n" .. tostring(err) return true end
    self.data = data
    self.has_data = true
    self.error = nil
    return true
end

local function hourly(d, n)
    local out = {}
    if not (d and d.hourly and d.hourly.time) then return out end
    local h = d.hourly
    for i = 1, math.min(n, #h.time) do
        out[#out + 1] = { time = h.time[i]:sub(12, 13), temp = num(h.temperature_2m[i]) or 0,
            code = num(h.weather_code[i]), rain = h.precipitation_probability and num(h.precipitation_probability[i]) }
    end
    return out
end

local function daily(d)
    local out = {}
    if not (d and d.daily and d.daily.time) then return out end
    local dd = d.daily
    for i = 1, #dd.time do
        local y, m, day = dd.time[i]:match("(%d+)-(%d+)-(%d+)")
        local wd = U.weekday(tonumber(y), tonumber(m), tonumber(day))
        out[#out + 1] = { label = i == 1 and T("Today") or U.DAYS_SHORT[wd], max = num(dd.temperature_2m_max[i]),
            min = num(dd.temperature_2m_min[i]), code = num(dd.weather_code[i]),
            rain = dd.precipitation_probability_max and num(dd.precipitation_probability_max[i]),
            sunrise = dd.sunrise and dd.sunrise[i], sunset = dd.sunset and dd.sunset[i] }
    end
    return out
end

function Weather:drawContent(c, x, y, w, h, p)
    local d = self.data
    if not d then UI.message(c, x, y, w, h, T("Loading weather …"), UI.ICON.refresh) return end
    local cur = d.current or {}
    local text, icon = code(cur.weather_code, cur.is_day ~= 0)
    local days = daily(d)
    local today = days[1] or {}

    local big = math.min(64, math.floor(h * 0.48))
    if p.cw == 1 and p.ch == 1 then
        -- compact: icon + temp, text, min/max
        local iw = math.floor((big) * 1.45)
    c:icon(icon, x, y + 2, big, {})
        local ts = UI.fit(c, deg(cur.temperature_2m), w - iw - 10, big, { bold = true })
        c:text(deg(cur.temperature_2m), x + iw + 10, y, { size = ts, bold = true })
        local yy = y + h - 44
        c:text(text, x, yy, { size = 15, bold = true, maxw = w })
        c:text(F("%s / %s   ·  Rain %s%%", deg(today.max), deg(today.min), today.rain or 0),
            x, yy + 22, { size = 13, color = "dark", maxw = w })
        return
    end

    if p.cw >= 2 and p.ch == 1 then
        -- wide: current conditions left, next hours right
        local lw = math.floor(w * 0.46)
        local isz = math.min(56, math.floor(h * 0.45))
        local iw = math.floor((isz) * 1.45)
    c:icon(icon, x, y, isz, {})
        c:text(deg(cur.temperature_2m), x + iw + 10, y - 2, { size = isz, bold = true })
        c:text(text, x, y + h - 42, { size = 16, bold = true, maxw = lw })
        c:text(F("%s / %s  ·  Wind %d km/h", deg(today.max), deg(today.min), math.floor((cur.wind_speed_10m or 0) + 0.5)),
            x, y + h - 20, { size = 12, color = "dark", maxw = lw })
        c:vline(x + lw + 8, y + 4, h - 8, 1, "gray")
        local hrs = {}
        for i, hh in ipairs(hourly(d, 13)) do
            if i > 1 and i % 3 == 1 then hrs[#hrs + 1] = hh end
        end
        local rx, rw = x + lw + 18, w - lw - 18
        local colw = rw / math.max(1, #hrs)
        for i, hh in ipairs(hrs) do
            local cx = rx + math.floor((i - 1) * colw)
            local _, ic = code(hh.code, true)
            c:text(U.clock12 and hh.time or (hh.time .. ":00"), cx, y, { size = 13, bold = true, w = math.floor(colw), align = "center" })
            c:icon(ic, cx, y + math.floor(h * 0.25), math.min(28, math.floor(h * 0.26)), { w = math.floor(colw), align = "center" })
            c:text(deg(hh.temp), cx, y + h - 42, { size = 15, bold = true, w = math.floor(colw), align = "center" })
            if hh.rain and hh.rain > 0 then
                c:text(hh.rain .. "%", cx, y + h - 20, { size = 11, color = "dark", w = math.floor(colw), align = "center" })
            end
        end
        return
    end

    -- header block: icon + big temp + details
    local iw = math.floor((big) * 1.45)
    c:icon(icon, x, y + 2, big, {})
    local tx = x + iw + 14
    local tw = c:text(deg(cur.temperature_2m), tx, y - 2, { size = big, bold = true })
    local dx = tx + tw + 18
    c:text(text, dx, y + 4, { size = 18, bold = true, maxw = x + w - dx })
    c:text(F("Feels %s  ·  %s / %s", deg(cur.apparent_temperature), deg(today.max), deg(today.min)),
        dx, y + 30, { size = 13, color = "dark", maxw = x + w - dx })
    c:text(F("Wind %d km/h  ·  Humidity %d%%", math.floor((cur.wind_speed_10m or 0) + 0.5), cur.relative_humidity_2m or 0),
        dx, y + 50, { size = 13, color = "dark", maxw = x + w - dx })

    local top = y + math.max(big, 72) + 10
    local rest = y + h - top
    if rest < 60 then return end
    c:hline(x, top - 4, w, 1, "gray")
    -- forecast row: hourly in wide tiles, daily in tall/large
    local items = {}
    if p.ch >= 2 then
        for i = 2, math.min(#days, p.cw >= 2 and 7 or 5) do items[#items + 1] = days[i] end
    else
        for i, hh in ipairs(hourly(d, 18)) do
            if i % 3 == 1 then items[#items + 1] = { label = U.clock12 and hh.time or (hh.time .. ":00"), max = hh.temp, code = hh.code, hourly = true } end
        end
    end
    if p.cw == 1 and p.ch >= 2 then
        -- vertical list of days
        local rh = math.min(38, math.floor(rest / math.max(1, #items)))
        local yy = top + 2
        for _, it in ipairs(items) do
            if yy + rh > y + h + 4 then break end
            local _, ic = code(it.code, true)
            c:text(it.label, x, yy + 6, { size = 15, bold = true })
            c:icon(ic, x + 44, yy + 2, 22, {})
            c:text(deg(it.max) .. " / " .. deg(it.min), x + 76, yy + 6, { size = 15, w = w - 76, align = "right" })
            yy = yy + rh
        end
        return
    end
    local n = #items
    if n == 0 then return end
    local colw = w / n
    for i, it in ipairs(items) do
        local cx = x + math.floor((i - 1) * colw)
        local _, ic = code(it.code, true)
        c:text(it.label, cx, top + 2, { size = 13, bold = true, w = math.floor(colw), align = "center" })
        local isz = math.min(30, math.floor(rest * 0.32))
        c:icon(ic, cx, top + 22, isz, { w = math.floor(colw), align = "center" })
        local tt = it.hourly and deg(it.max) or (deg(it.max) .. "/" .. deg(it.min))
        c:text(tt, cx, top + 26 + isz + 6, { size = 14, w = math.floor(colw), align = "center" })
    end
end

function Weather:drawFull(c, W, H)
    local x, y, w, h = UI.fullFrame(c, W, H, T("Weather") .. " · " .. (self.s.city or ""), self.icon,
        T("Back: close"), self.data and self.last_update > 0 and F("Updated %s", U.hhmm(self.last_update)) or nil)
    local d = self.data
    if not d then UI.message(c, x, y, w, h, self.error or T("Loading weather …"), UI.ICON.refresh) return end
    local cur = d.current or {}
    local text, icon = code(cur.weather_code, cur.is_day ~= 0)
    local days = daily(d)
    local today = days[1] or {}
    local iw = math.floor((110) * 1.45)
    c:icon(icon, x, y, 110, {})
    local tw = c:text(deg(cur.temperature_2m), x + iw + 20, y - 4, { size = 96, bold = true })
    local dx = x + iw + tw + 44
    c:text(text, dx, y + 8, { size = 24, bold = true, maxw = x + w - dx })
    local lines = {
        F("Feels like %s", deg(cur.apparent_temperature)),
        F("High %s  ·  Low %s", deg(today.max), deg(today.min)),
        F("Wind %d km/h  ·  Humidity %d%%", math.floor((cur.wind_speed_10m or 0) + 0.5), cur.relative_humidity_2m or 0),
        F("Sun %s – %s", (today.sunrise or ""):sub(12, 16), (today.sunset or ""):sub(12, 16)),
    }
    for i, l in ipairs(lines) do c:text(l, dx, y + 18 + i * 24, { size = 15, color = "dark", maxw = x + w - dx }) end

    -- hourly strip with temperature curve
    local top = y + 150
    c:text(T("NEXT HOURS"), x, top, { size = 13, bold = true })
    local hrs = hourly(d, 24)
    local n = math.min(#hrs, W > H and 12 or 8)
    local step = math.max(1, math.floor(#hrs / n))
    local pts = {}
    for i = 1, #hrs, step do if #pts < n then pts[#pts + 1] = hrs[i] end end
    local colw = w / math.max(1, #pts)
    local tmin, tmax = 99, -99
    for _, pnt in ipairs(pts) do tmin = math.min(tmin, pnt.temp); tmax = math.max(tmax, pnt.temp) end
    local gy, gh = top + 78, 50
    for i, pnt in ipairs(pts) do
        local cx = x + math.floor((i - 1) * colw)
        local _, ic = code(pnt.code, true)
        c:text(pnt.time, cx, top + 24, { size = 13, w = math.floor(colw), align = "center", color = "dark" })
        c:icon(ic, cx, top + 44, 22, { w = math.floor(colw), align = "center" })
        local fy = gy + gh - math.floor((pnt.temp - tmin) / math.max(1, tmax - tmin) * gh)
        local mx = cx + math.floor(colw / 2)
        c:circle(mx, fy + 18, 4, "black")
        c:text(deg(pnt.temp), cx, fy + 26, { size = 13, bold = true, w = math.floor(colw), align = "center" })
        if pnt.rain and pnt.rain > 0 then
            c:text(pnt.rain .. "%", cx, gy + gh + 50, { size = 11, w = math.floor(colw), align = "center", color = "gray" })
        end
    end

    -- daily list
    local dtop = gy + gh + 80
    c:hline(x, dtop - 8, w, 2, "black")
    c:text(T("7 DAYS"), x, dtop, { size = 13, bold = true })
    local rows = #days
    local rh = math.min(44, math.floor((y + h - dtop - 24) / math.max(1, rows)))
    local yy = dtop + 24
    for _, dd in ipairs(days) do
        if yy + rh > y + h + 6 then break end
        local t, ic = code(dd.code, true)
        c:text(dd.label, x, yy + 8, { size = 17, bold = true })
        c:icon(ic, x + 70, yy + 2, 26, {})
        c:text(t, x + 112, yy + 9, { size = 15, maxw = w * 0.42 })
        c:text(string.format("%s%%", dd.rain or 0), x + w * 0.62, yy + 9, { size = 14, color = "dark" })
        c:text(deg(dd.max) .. "  " .. deg(dd.min), x, yy + 8, { size = 17, bold = true, w = w, align = "right" })
        yy = yy + rh
    end
end

return Weather
