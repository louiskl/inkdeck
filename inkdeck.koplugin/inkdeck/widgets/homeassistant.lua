-- Home Assistant: show and control entities via the REST API
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local json = require("inkdeck/json")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local HA = Base.define{
    type = "homeassistant",
    name = "Smart Home",
    icon = UI.ICON.home,
    interval = 60,
    defaults = { entities = {} },
}

local TOGGLE = { light = true, switch = true, fan = true, input_boolean = true, automation = true, cover = true, media_player = true }
local ACTIVATE = { scene = true, script = true, button = "press", input_button = "press" }

local function domain(id) return tostring(id):match("^([%w_]+)%.") or "" end

local function icon_for(id, on)
    local d = domain(id)
    if d == "light" then return UI.ICON.bulb end
    if d == "switch" or d == "input_boolean" then return on and UI.ICON.toggle_on or UI.ICON.toggle_off end
    if d == "sensor" then return UI.ICON.thermo end
    if d == "scene" or d == "script" then return UI.ICON.star end
    if d == "media_player" then return UI.ICON.music end
    return UI.ICON.power
end

function HA:init()
    self.states = {}
    self.sel = 1
end

function HA:cfg()
    local g = (self.ctx.config and self.ctx.config.homeassistant) or {}
    return U.trim(g.url or ""):gsub("/+$", ""), g.token
end

function HA:entities()
    local out = {}
    for _, e in ipairs(self.s.entities or {}) do
        if type(e) == "string" then e = { id = e } end
        if e.id then out[#out + 1] = e end
    end
    return out
end

local DEMO = {
    ["light.living_room"] = { state = "on", attributes = { friendly_name = "Living room", brightness = 180 } },
    ["light.desk"] = { state = "off", attributes = { friendly_name = "Desk lamp" } },
    ["switch.coffee_machine"] = { state = "off", attributes = { friendly_name = "Coffee" } },
    ["sensor.room_temperature"] = { state = "21.4", attributes = { friendly_name = "Room", unit_of_measurement = "°C" } },
    ["scene.movie_night"] = { state = "scening", attributes = { friendly_name = "Movie night" } },
}

function HA:update()
    local url, token = self:cfg()
    local ents = self:entities()
    if self.ctx.demo and (url == "" or not token) then
        for _, e in ipairs(ents) do self.states[e.id] = self.states[e.id] or DEMO[e.id] end
        self.has_data = true
        return true
    end
    if url == "" or not token or token == "" then
        self.error = T("Home Assistant not set up.\nAdd URL and token in the editor.")
        return true
    end
    if #ents == 0 then self.error = T("No devices selected") return true end
    local errs = 0
    for _, e in ipairs(ents) do
        local data, err = self.ctx.net.getJson(url .. "/api/states/" .. e.id,
            { Authorization = "Bearer " .. token }, 8)
        if data then self.states[e.id] = data else errs = errs + 1; self.last_err = err end
    end
    if errs == #ents then
        self.error = T("Home Assistant unreachable") .. "\n" .. tostring(self.last_err)
    else
        self.error = nil
        self.has_data = true
    end
    return true
end

function HA:stateText(id)
    local st = self.states[id]
    if not st then return "…", false end
    local s = st.state
    local a = st.attributes or {}
    local d = domain(id)
    local on = (s == "on" or s == "open" or s == "playing" or s == "home")
    if d == "sensor" or d == "input_number" then
        local v = tonumber(s)
        local txt = v and (math.abs(v) < 100 and (string.format("%.1f", v):gsub("%.", require("inkdeck/i18n").lang == "de" and "," or ".")) or tostring(math.floor(v + 0.5))) or s
        return txt .. (a.unit_of_measurement and (" " .. a.unit_of_measurement) or ""), false
    end
    if ACTIVATE[d] then return T("Run"), false end
    if s == "unavailable" then return "offline", false end
    local txt = ({ on = "On", off = "Off", open = "Open", closed = "Closed", playing = "Playing", paused = "Paused",
        idle = "Idle", home = "Home", not_home = "Away", locked = "Locked", unlocked = "Unlocked" })[s]
    txt = txt and T(txt) or s
    if d == "light" and on and a.brightness then
        txt = txt .. " · " .. math.floor(a.brightness / 255 * 100 + 0.5) .. "%"
    end
    return txt, on
end

function HA:entityName(e)
    local st = self.states[e.id]
    return e.name or (st and st.attributes and st.attributes.friendly_name) or e.id
end

function HA:call(service, id, extra)
    local url, token = self:cfg()
    local body = { entity_id = id }
    for k, v in pairs(extra or {}) do body[k] = v end
    if self.ctx.demo and (url == "" or not token) then
        local st = self.states[id]
        if st and service:match("toggle") then st.state = st.state == "on" and "off" or "on" end
        if st and extra and extra.brightness_step_pct then
            st.state = "on"
            local b = (st.attributes.brightness or 0) + extra.brightness_step_pct * 2.55
            st.attributes.brightness = U.clamp(b, 3, 255)
        end
        return true
    end
    local res, err = self.ctx.net.request("POST", url .. "/api/services/" .. service, json.encode(body),
        { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" }, 8)
    if not res then self.error = T("Action failed: ") .. tostring(err) return false end
    -- refresh the single entity
    local data = self.ctx.net.getJson(url .. "/api/states/" .. id, { Authorization = "Bearer " .. token }, 8)
    if data then self.states[id] = data end
    return true
end

function HA:activate(e)
    local d = domain(e.id)
    if TOGGLE[d] then return self:call(d == "cover" and "cover/toggle" or (d .. "/toggle"), e.id) end
    if ACTIVATE[d] == "press" then return self:call(d .. "/press", e.id) end
    if ACTIVATE[d] then return self:call(d .. "/turn_on", e.id) end
    return false
end

function HA:tileRight()
    local n = 0
    for _, e in ipairs(self:entities()) do
        local _, on = self:stateText(e.id)
        if on then n = n + 1 end
    end
    return n > 0 and F("%d on", n) or nil
end

function HA:drawContent(c, x, y, w, h, p)
    local ents = self:entities()
    if #ents == 0 then UI.message(c, x, y, w, h, T("No devices selected"), UI.ICON.home) return end
    if p.cw >= 2 and p.ch >= 2 then
        -- button grid
        local cols = 2
        local rows = math.ceil(math.min(#ents, 6) / cols)
        local bw = (w - 10) / cols
        local bh = math.min(150, (h - (rows - 1) * 10) / rows)
        for i, e in ipairs(ents) do
            if i > cols * rows then break end
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local bx = x + math.floor(col * (bw + 10))
            local by = y + math.floor(row * (bh + 10))
            local txt, on = self:stateText(e.id)
            local fg = on and "white" or "black"
            c:roundrect(bx, by, math.floor(bw), math.floor(bh), on and "black" or "white", 10)
            if not on then c:frame(bx, by, math.floor(bw), math.floor(bh), 2, "black", 10) end
            c:icon(icon_for(e.id, on), bx + 12, by + 10, 24, { color = fg })
            c:text(txt, bx + 48, by + 14, { size = 14, bold = true, color = fg, maxw = bw - 60 })
            c:text(self:entityName(e), bx + 12, by + bh - 30, { size = 16, color = fg, maxw = bw - 24 })
        end
        return
    end
    local yy = y
    for _, e in ipairs(ents) do
        if yy + 28 > y + h then break end
        local txt, on = self:stateText(e.id)
        yy = yy + UI.row(c, x, yy, w, { icon = icon_for(e.id, on), text = self:entityName(e), right = txt, size = 15, right_bold = on })
    end
end

function HA:hint()
    return T("▲ ▼ select   ·   OK: switch   ·   ◀ ▶ dim   ·   Back: close")
end

function HA:key(k)
    local ents = self:entities()
    if #ents == 0 then return false end
    if k == "Down" then self.sel = math.min(#ents, self.sel + 1) return true end
    if k == "Up" then self.sel = math.max(1, self.sel - 1) return true end
    local e = ents[self.sel]
    if not e then return false end
    if k == "Press" then self:activate(e) return true end
    if (k == "Left" or k == "Right") and domain(e.id) == "light" then
        self:call("light/turn_on", e.id, { brightness_step_pct = k == "Right" and 10 or -10 })
        return true
    end
    return false
end

function HA:drawFull(c, W, H)
    local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, self:hint())
    local ents = self:entities()
    if self.error and not self.has_data then UI.message(c, x, y, w, h, self.error, UI.ICON.home) return end
    local yy = y
    local start = math.max(1, self.sel - 7)
    for i = start, #ents do
        local e = ents[i]
        if yy + 58 > y + h then break end
        local txt, on = self:stateText(e.id)
        local sel = (i == self.sel)
        UI.row(c, x, yy, w, { icon = icon_for(e.id, on), text = self:entityName(e), right = txt, size = 22,
            selected = sel, right_bold = on, height = 54 })
        local st = self.states[e.id]
        if domain(e.id) == "light" and on and st and st.attributes and st.attributes.brightness then
            local bw = 120
            UI.progress(c, x + w - bw - 150, yy + 22, bw, 12, st.attributes.brightness / 255,
                { color = sel and "white" or "black", bg = sel and "dark" or "white", border = sel and 0 or 2 })
        end
        yy = yy + 58
    end
end

return HA
