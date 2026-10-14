-- InkDeck core: pages, layout, focus navigation, expanded view, menu.
-- Independent of KOReader so it can run in the PC preview tool.
local Layout = require("inkdeck/layout")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Core = {}
Core.__index = Core

Core.VERSION = "0.1.0"

Core.WIDGET_TYPES = {
    "clock", "weather", "calendar", "news", "reminders", "lastfm",
    "mediaplayer", "homeassistant", "photo", "countdown", "note", "spotify",
}

local registry = {}
function Core.widgetClass(t)
    if registry[t] == nil then
        local ok, mod = pcall(require, "inkdeck/widgets/" .. t)
        registry[t] = ok and mod or false
        if not ok then Core.load_error = tostring(mod) end
    end
    return registry[t] or nil
end

function Core.defaultConfig(lang)
    local de = (lang or require("inkdeck/i18n").lang) == "de"
    local city = de and { city = "Berlin", lat = 52.52, lon = 13.405 } or { city = "London", lat = 51.5072, lon = -0.1276 }
    local function cp(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
    return {
        version = 1,
        language = "auto",
        orientation = "portrait",
        timezone = de and "Europe/Berlin" or "system",
        clock_12h = false,
        hide_focus_after = 120,
        full_refresh_every = 12,
        keep_awake = true,
        bridge = { url = "" },
        homeassistant = { url = "", token = "" },
        grid = { portrait = { cols = 2, rows = 4 }, landscape = { cols = 4, rows = 2 } },
        pages = {
            {
                name = "Home",
                widgets = {
                    { type = "clock", size = "w" },
                    { type = "weather", size = "s", settings = cp(city) },
                    { type = "calendar", size = "t", settings = { urls = {} } },
                    { type = "reminders", size = "s", settings = { items = de
                        and { "InkDeck einrichten", "Fotos kopieren" }
                        or { "Set up InkDeck", "Copy some photos" } } },
                    { type = "lastfm", size = "w", settings = { username = "", api_key = "" } },
                },
            },
            {
                name = de and "Zuhause" or "House",
                widgets = {
                    { type = "homeassistant", size = "l", settings = { entities = {
                        { id = "light.living_room", name = de and "Wohnzimmer" or "Living room" },
                        { id = "light.desk", name = de and "Schreibtisch" or "Desk lamp" },
                        { id = "switch.coffee_machine", name = de and "Kaffee" or "Coffee" },
                        { id = "sensor.room_temperature", name = de and "Zimmer" or "Room" },
                    } } },
                    { type = "photo", size = "w" },
                    { type = "countdown", size = "s", settings = { label = de and "Weihnachten" or "Christmas", date = "2026-12-24" } },
                    { type = "note", size = "s", settings = { text = de and "Bleib neugierig." or "Stay curious." } },
                },
            },
            {
                name = "News",
                widgets = {
                    { type = "news", size = "l" },
                    { type = "weather", size = "w", settings = cp(city) },
                    { type = "calendar", size = "w", settings = { urls = {} } },
                },
            },
        },
    }
end

-- opts: config, ctx, W, H
function Core.new(opts)
    local self = setmetatable({}, Core)
    self.config = opts.config or Core.defaultConfig()
    self.ctx = opts.ctx or {}
    self.ctx.config = self.config
    U.timezone = self.config.timezone or "system"
    U.clock12 = self.config.clock_12h == true
    self.page_idx = 1
    self.focus = {}
    self.focus_visible = true
    self.last_key = U.now()
    self:buildPages()
    self:setSize(opts.W or 600, opts.H or 800)
    return self
end

function Core:buildPages()
    self.pages = {}
    for pi, pg in ipairs(self.config.pages or {}) do
        local page = { name = pg.name or F("Page %d", pi), items = {} }
        for wi, wd in ipairs(pg.widgets or {}) do
            local cls = Core.widgetClass(wd.type)
            if cls then
                local inst = cls.new(wd.settings or {}, self.ctx)
                inst.uid = pi .. ":" .. wi
                page.items[#page.items + 1] = { inst = inst, size = wd.size or "s" }
            end
        end
        self.pages[#self.pages + 1] = page
    end
    if #self.pages == 0 then
        self.pages[1] = { name = T("Empty"), items = {} }
    end
end

Core.STATUS_H = 40

function Core:setSize(W, H)
    self.W, self.H = W, H
    self.orientation = W > H and "landscape" or "portrait"
    local g = (self.config.grid or {})[self.orientation] or (self.orientation == "landscape" and { cols = 4, rows = 2 } or { cols = 2, rows = 4 })
    self.cols, self.rows = g.cols or 2, g.rows or 4
    local area = { x = 0, y = Core.STATUS_H, w = W, h = H - Core.STATUS_H }
    for _, page in ipairs(self.pages) do
        local placed, overflow = Layout.pack(page.items, self.cols, self.rows)
        Layout.rects(placed, self.cols, self.rows, area, 10)
        for _, p in ipairs(placed) do p.item = page.items[p.index] end
        page.placed = placed
        page.overflow = overflow
    end
    if self.expanded then
        -- keep expanded widget, nothing to relayout
    end
end

function Core:page() return self.pages[self.page_idx] end

function Core:focusIdx()
    local page = self:page()
    local f = self.focus[self.page_idx] or 1
    if f > #page.placed then f = #page.placed end
    if f < 1 then f = 1 end
    return f
end

function Core:allInstances()
    local out = {}
    for pi, page in ipairs(self.pages) do
        for _, it in ipairs(page.items) do out[#out + 1] = { inst = it.inst, page = pi } end
    end
    return out
end

----------------------------------------------------------------- drawing
function Core:drawStatus(c)
    local W = self.W
    c:rect(0, 0, W, Core.STATUS_H, "white")
    local x = 10
    for i, page in ipairs(self.pages) do
        local label = page.name
        local tw = c:measure(label, { size = 14, bold = true })
        local pw = tw + 22
        if i == self.page_idx then
            c:roundrect(x, 7, pw, 26, "black", 13)
            c:text(label, x, 11, { size = 14, bold = true, color = "white", w = pw, align = "center" })
        else
            c:frame(x, 7, pw, 26, 1, "gray", 13)
            c:text(label, x, 11, { size = 14, color = "dark", w = pw, align = "center" })
        end
        x = x + pw + 6
    end
    -- right side: battery + time
    local rx = W - 12
    local time = U.hhmm(U.now())
    local tw = c:measure(time, { size = 18, bold = true })
    rx = rx - tw
    c:text(time, rx, 8, { size = 18, bold = true })
    local batt = self.ctx.battery and self.ctx.battery()
    if batt then
        local lvl = UI.ICON.battery[math.min(5, math.floor(batt / 20.01) + 1)]
        local bt = batt .. "%"
        local btw = c:measure(bt, { size = 13 })
        rx = rx - btw - 14
        c:text(bt, rx, 12, { size = 13, color = "dark" })
        local iw = c:measure(require("inkdeck/util").utf8_char(lvl), { icon = true, size = 16 })
        rx = rx - iw - 6
        c:icon(lvl, rx, 10, 16, { color = "dark" })
    end
    if self.ctx.offline and self.ctx.offline() then
        rx = rx - 26
        c:icon(UI.ICON.wifi, rx, 10, 16, { color = "gray" })
        c:hline(rx - 2, 19, 22, 2, "black")
    end
    c:hline(0, Core.STATUS_H - 1, W, 1, "black")
end

function Core:drawTile(c, p, focused)
    local inst = p.item.inst
    local ok, err = pcall(inst.drawTile, inst, c, p, focused)
    if not ok then
        c:roundrect(p.x, p.y, p.w, p.h, "white", UI.RADIUS)
        c:frame(p.x, p.y, p.w, p.h, 2, "black", UI.RADIUS)
        UI.message(c, p.x + 10, p.y + 10, p.w - 20, p.h - 20, T("Widget error:") .. "\n" .. tostring(err):sub(1, 160))
    end
end

function Core:draw(c)
    if self.expanded then
        local inst = self.expanded.item.inst
        local ok, err = pcall(inst.drawFull, inst, c, self.W, self.H)
        if not ok then
            c:rect(0, 0, self.W, self.H, "white")
            UI.message(c, 20, 60, self.W - 40, self.H - 120, T("Widget error:") .. "\n" .. tostring(err))
        end
    else
        c:rect(0, 0, self.W, self.H, "white")
        self:drawStatus(c)
        local page = self:page()
        local f = self:focusIdx()
        for i, p in ipairs(page.placed) do
            self:drawTile(c, p, self.focus_visible and i == f)
        end
        if #page.placed == 0 then
            UI.message(c, 40, 100, self.W - 80, self.H - 200,
                T("This page is empty.\nAdd widgets in the editor and copy config.json to your device."), UI.ICON.cog)
        end
    end
    if self.menu then self:drawMenu(c) end
end

----------------------------------------------------------------- menu
function Core:openMenu()
    local items = {
        { label = self.orientation == "portrait" and T("Landscape") or T("Portrait"), action = "rotate", icon = UI.ICON.refresh },
        { label = T("Refresh everything"), action = "refresh_all", icon = UI.ICON.refresh },
        { label = T("Reload configuration"), action = "reload", icon = UI.ICON.cog },
        { label = self.focus_visible and T("Hide selection frame") or T("Show selection frame"), action = "toggle_focus", icon = UI.ICON.box },
        { label = T("Exit InkDeck"), action = "close", icon = UI.ICON.power },
    }
    self.menu = { items = items, sel = 1 }
end

function Core:menuRect()
    local mw = math.min(self.W - 60, 380)
    local mh = 70 + #self.menu.items * 50
    return math.floor((self.W - mw) / 2), math.floor((self.H - mh) / 2), mw, mh
end

function Core:drawMenu(c)
    local x, y, w, h = self:menuRect()
    c:roundrect(x + 6, y + 6, w, h, "gray", 16)
    c:roundrect(x, y, w, h, "white", 16)
    c:frame(x, y, w, h, 3, "black", 16)
    c:text("InkDeck " .. Core.VERSION, x, y + 16, { size = 18, bold = true, w = w, align = "center" })
    c:hline(x + 20, y + 50, w - 40, 1, "gray")
    local yy = y + 60
    for i, it in ipairs(self.menu.items) do
        UI.row(c, x + 24, yy, w - 48, { text = it.label, icon = it.icon, size = 18, selected = i == self.menu.sel, height = 44 })
        yy = yy + 50
    end
end

----------------------------------------------------------------- input
-- returns result table: {redraw=bool, refresh="ui"|"partial"|"full", region={x,y,w,h}, action=...}
function Core:key(k)
    self.last_key = U.now()
    -- menu captures keys
    if self.menu then
        local m = self.menu
        if k == "Down" then m.sel = m.sel % #m.items + 1
        elseif k == "Up" then m.sel = (m.sel - 2) % #m.items + 1
        elseif k == "Back" or k == "Menu" then self.menu = nil return { redraw = true, refresh = "partial" }
        elseif k == "Press" then
            local act = m.items[m.sel].action
            self.menu = nil
            return self:doAction(act)
        else return {} end
        local x, y, w, h = self:menuRect()
        return { redraw = true, refresh = "ui", region = { x = x, y = y, w = w + 8, h = h + 8 } }
    end
    if k == "Menu" then
        self:openMenu()
        local x, y, w, h = self:menuRect()
        return { redraw = true, refresh = "ui", region = { x = x, y = y, w = w + 8, h = h + 8 } }
    end

    if self.expanded then
        local inst = self.expanded.item.inst
        if k == "Back" then
            if inst.back and inst:back() then return { redraw = true, refresh = "ui" } end
            self.expanded = nil
            return { redraw = true, refresh = "partial", collapsed = true }
        end
        if k == "PgFwd" or k == "PgBack" then
            local page = self:page()
            local n = #page.placed
            if n > 0 then
                local f = self:focusIdx()
                f = (f - 1 + (k == "PgFwd" and 1 or -1)) % n + 1
                self.focus[self.page_idx] = f
                self.expanded = page.placed[f]
                return { redraw = true, refresh = "partial", expanded = self.expanded }
            end
            return {}
        end
        local ok, res = pcall(inst.key, inst, k)
        if ok and res then return { redraw = true, refresh = "ui" } end
        return {}
    end

    -- dashboard: Back never exits (wall display!) – it jumps to the first page and hides the frame.
    -- Leave InkDeck via Menu → "Exit InkDeck" or the Home key.
    if k == "Back" then
        local changed = self.page_idx ~= 1 or self.focus_visible
        self.page_idx = 1
        self.focus_visible = false
        return changed and { redraw = true, refresh = "partial" } or {}
    end
    local page = self:page()
    if not self.focus_visible and (k == "Up" or k == "Down" or k == "Left" or k == "Right") then
        self.focus_visible = true
        local p = page.placed[self:focusIdx()]
        return { redraw = true, refresh = "ui", region = p and { x = p.x, y = p.y, w = p.w, h = p.h } }
    end
    self.focus_visible = true
    if k == "PgFwd" or k == "PgBack" then
        return self:switchPage(k == "PgFwd" and 1 or -1)
    end
    if k == "Up" or k == "Down" or k == "Left" or k == "Right" then
        local cur = self:focusIdx()
        local nxt = Layout.navigate(page.placed, cur, k)
        if not nxt then
            if k == "Right" and #self.pages > 1 then return self:switchPage(1, "left", page.placed[cur]) end
            if k == "Left" and #self.pages > 1 then return self:switchPage(-1, "right", page.placed[cur]) end
            return {}
        end
        self.focus[self.page_idx] = nxt
        local a, b = page.placed[cur], page.placed[nxt]
        return { redraw = true, refresh = "ui", region = self:union(a, b) }
    end
    if k == "Press" then
        local p = page.placed[self:focusIdx()]
        if p then
            self.expanded = p
            return { redraw = true, refresh = "partial", expanded = p }
        end
    end
    return {}
end

function Core:switchPage(dir, edge, from)
    local n = #self.pages
    self.page_idx = (self.page_idx - 1 + dir) % n + 1
    if edge then
        local page = self:page()
        local y = from and (from.y + from.h / 2) or 0
        local f = Layout.edge(page.placed, edge, y)
        if f then self.focus[self.page_idx] = f end
    end
    return { redraw = true, refresh = "partial", page_changed = true }
end

function Core:union(a, b)
    if not a then return b and { x = b.x, y = b.y, w = b.w, h = b.h } end
    if not b then return { x = a.x, y = a.y, w = a.w, h = a.h } end
    local x0, y0 = math.min(a.x, b.x), math.min(a.y, b.y)
    local x1, y1 = math.max(a.x + a.w, b.x + b.w), math.max(a.y + a.h, b.y + b.h)
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

function Core:doAction(act)
    if act == "rotate" then
        return { action = "rotate", orientation = self.orientation == "portrait" and "landscape" or "portrait" }
    elseif act == "toggle_focus" then
        self.focus_visible = not self.focus_visible
        self.config.hide_focus_after = self.focus_visible and self.config.hide_focus_after or 0
        return { redraw = true, refresh = "partial" }
    end
    return { action = act, redraw = true, refresh = "partial" }
end

-- touch: tap at x,y
function Core:tap(x, y)
    if self.menu then
        local mx, my, mw = self:menuRect()
        local i = math.floor((y - my - 60) / 50) + 1
        if x >= mx and x <= mx + mw and i >= 1 and i <= #self.menu.items then
            self.menu.sel = i
            return self:key("Press")
        end
        self.menu = nil
        return { redraw = true, refresh = "partial" }
    end
    if self.expanded then
        if y < 52 then return self:key("Back") end
        if x < self.W * 0.25 then return self:key("Left") end
        if x > self.W * 0.75 then return self:key("Right") end
        if y < self.H * 0.3 then return self:key("Up") end
        if y > self.H * 0.75 then return self:key("Down") end
        return self:key("Press")
    end
    if y < Core.STATUS_H then return self:key("Menu") end
    local page = self:page()
    local i = Layout.hit(page.placed, x, y)
    if i then
        self.focus[self.page_idx] = i
        self.focus_visible = true
        return self:key("Press")
    end
    return {}
end

----------------------------------------------------------------- timing
-- widgets that should update now (current page first, then others lazily)
function Core:due(now)
    local list = {}
    local function interval(inst, expanded)
        if expanded and inst.fullInterval then return inst:fullInterval() end
        return inst.interval or 1800
    end
    if self.expanded then
        local inst = self.expanded.item.inst
        if now - inst.last_update >= interval(inst, true) then list[#list + 1] = inst end
        return list
    end
    for _, p in ipairs(self:page().placed) do
        local inst = p.item.inst
        if now - inst.last_update >= interval(inst) then list[#list + 1] = inst end
    end
    return list
end

-- region of an instance on the current screen (or full screen when expanded)
function Core:regionOf(inst)
    if self.expanded then
        if self.expanded.item.inst == inst then return { x = 0, y = 0, w = self.W, h = self.H } end
        return nil
    end
    for _, p in ipairs(self:page().placed) do
        if p.item.inst == inst then return { x = p.x, y = p.y, w = p.w, h = p.h } end
    end
end

-- regions to repaint when the minute changes
function Core:minuteRegions()
    local out = {}
    if self.menu then return out end
    if self.expanded then
        local inst = self.expanded.item.inst
        if inst.tick_minute or inst.progress then out[#out + 1] = { x = 0, y = 0, w = self.W, h = self.H } end
        return out
    end
    out[#out + 1] = { x = 0, y = 0, w = self.W, h = Core.STATUS_H }
    for _, p in ipairs(self:page().placed) do
        if p.item.inst.tick_minute or p.item.inst.progress then
            out[#out + 1] = { x = p.x, y = p.y, w = p.w, h = p.h }
        end
    end
    -- idle: hide focus frame
    local idle = self.config.hide_focus_after or 0
    if idle > 0 and self.focus_visible and U.now() - self.last_key > idle then
        self.focus_visible = false
        local p = self:page().placed[self:focusIdx()]
        if p then out[#out + 1] = { x = p.x, y = p.y, w = p.w, h = p.h } end
    end
    return out
end

return Core
