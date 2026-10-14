-- KOReader full-screen widget hosting the InkDeck dashboard.
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

local Canvas = require("inkdeck/canvas_ko")
local Core = require("inkdeck/core")

-- Logical layout is designed for a 600 px wide screen; bigger screens are scaled up.
-- config.ui_scale overrides the automatic factor (e.g. 1.2 for bigger text).
local function uiScale(config)
    local manual = tonumber(config and config.ui_scale)
    if manual and manual > 0.3 then return manual end
    local short = math.min(Screen:getWidth(), Screen:getHeight())
    return math.max(1, short / 600)
end

local View = InputContainer:extend{
    name = "inkdeck_view",
    covers_fullscreen = true,
    plugin = nil, -- the InkDeck plugin instance (for config load/save)
    config = nil,
    ctx = nil,
}

local KEYS = { "Up", "Down", "Left", "Right", "Press", "Menu" }

function View:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.scale = uiScale(self.config)
    self.dash = Core.new{ config = self.config, ctx = self.ctx,
        W = math.floor(self.dimen.w / self.scale), H = math.floor(self.dimen.h / self.scale) }
    if Device:hasKeys() then
        for _, k in ipairs(KEYS) do
            self.key_events["InkKey" .. k] = { { k }, event = "InkKey", args = k }
        end
        self.key_events.InkKeyBack = { { Device.input.group.Back }, event = "InkKey", args = "Back" }
        self.key_events.InkKeyPgFwd = { { Device.input.group.PgFwd }, event = "InkKey", args = "PgFwd" }
        self.key_events.InkKeyPgBack = { { Device.input.group.PgBack }, event = "InkKey", args = "PgBack" }
    end
    if Device:isTouchDevice() then
        self:setupTouch()
    end
    self.partial_count = 0
    self.last_minute = math.floor(os.time() / 60)
    self.tick_fn = function() self:onTick() end
end

function View:setupTouch()
    local range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        InkTap = { GestureRange:new{ ges = "tap", range = range } },
        InkSwipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
end

function View:onInkTap(_, ges)
    self:apply(self.dash:tap(ges.pos.x / self.scale, ges.pos.y / self.scale))
    return true
end

function View:onInkSwipe(_, ges)
    local map = { west = "PgFwd", east = "PgBack", north = "Down", south = "Up" }
    if self.dash.expanded and (ges.direction == "south") then
        self:apply(self.dash:key("Back"))
    elseif map[ges.direction] then
        self:apply(self.dash:key(map[ges.direction]))
    end
    return true
end

function View:onInkKey(k)
    self:apply(self.dash:key(k))
    return true
end

-- Home key (KOReader default binding): leave the dashboard
function View:onHome()
    self:close()
    return true
end

function View:apply(res)
    if not res then return end
    if res.action == "close" then self:close() return end
    if res.action == "rotate" then self:rotate(res.orientation) return end
    if res.action == "reload" then
        if self.plugin then self.plugin:reload(self) end
        return
    end
    if res.action == "refresh_all" then
        for _, e in ipairs(self.dash:allInstances()) do e.inst.last_update = 0 end
        self:scheduleTick(0.2)
    end
    if res.expanded or res.page_changed then
        -- fetch fresh data for what just became visible
        self:scheduleTick(0.3)
    end
    if res.redraw then self:repaint(res.refresh or "ui", res.region) end
end

function View:repaint(mode, region)
    if mode == "ui" or mode == "fast" then
        self.partial_count = self.partial_count + 1
    else
        self.partial_count = self.partial_count + 3
    end
    local every = tonumber(self.config.full_refresh_every) or 12
    if every > 0 and self.partial_count >= every and not region then
        mode = "full"
        self.partial_count = 0
    end
    local s = self.scale
    local geom = region and Geom:new{
        x = math.floor(region.x * s), y = math.floor(region.y * s),
        w = math.ceil(region.w * s) + 1, h = math.ceil(region.h * s) + 1,
    } or self.dimen
    UIManager:setDirty(self, function() return mode, geom end)
end

function View:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local c = Canvas.new(bb, x, y, self.dash.W, self.dash.H, self.scale)
    local ok, err = pcall(self.dash.draw, self.dash, c)
    if not ok then
        logger.err("InkDeck: draw failed:", err)
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, Canvas.color("white"))
        pcall(c.text, c, "InkDeck error: " .. tostring(err), 20, 60, { size = 16, maxw = self.dash.W - 40 })
    end
end

----------------------------------------------------------------- timer
function View:scheduleTick(seconds)
    UIManager:unschedule(self.tick_fn)
    UIManager:scheduleIn(seconds, self.tick_fn)
end

function View:onTick()
    if self.closed then return end
    local now = os.time()
    -- minute change: clock + status bar
    local m = math.floor(now / 60)
    if m ~= self.last_minute then
        self.last_minute = m
        if self.ctx.refreshOnline then self.ctx.refreshOnline() end
        for _, r in ipairs(self.dash:minuteRegions()) do self:repaint("ui", r) end
    end
    -- one widget update per tick so key presses stay responsive
    local due = self.dash:due(now)
    if #due > 0 and not self.dash.menu then
        local inst = due[1]
        local changed = inst:safeUpdate(now)
        if changed then
            local r = self.dash:regionOf(inst)
            if r then self:repaint("ui", r) end
        end
        self:scheduleTick(#due > 1 and 0.5 or 5)
        return
    end
    -- next check: soon after the next minute boundary, but at least every 15 s
    local to_minute = 60 - (now % 60) + 1
    self:scheduleTick(math.min(15, to_minute))
end

----------------------------------------------------------------- rotation
function View:rotate(orientation)
    local mode = orientation == "landscape" and Screen.DEVICE_ROTATED_CLOCKWISE or Screen.DEVICE_ROTATED_UPRIGHT
    self.config.orientation = orientation
    if self.plugin then self.plugin:saveConfig(self.config) end
    if Screen:getRotationMode() ~= mode then
        UIManager:broadcastEvent(Event:new("SetRotationMode", mode))
        -- if nothing below us handled it, do it ourselves
        UIManager:nextTick(function()
            if Screen:getRotationMode() ~= mode then Screen:setRotationMode(mode) end
            self:relayout()
        end)
    else
        self:relayout()
    end
end

function View:onSetRotationMode()
    UIManager:nextTick(function() self:relayout() end)
end

function View:relayout()
    if self.closed then return end
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.scale = uiScale(self.config)
    self.dash:setSize(math.floor(self.dimen.w / self.scale), math.floor(self.dimen.h / self.scale))
    if Device:isTouchDevice() then self:setupTouch() end
    Canvas.clearImageCache()
    self.partial_count = 0
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

----------------------------------------------------------------- lifecycle
function View:onShow()
    self:scheduleTick(0.5)
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function View:close()
    if self.closed then return end
    self.closed = true
    UIManager:unschedule(self.tick_fn)
    Canvas.clearImageCache()
    UIManager:close(self, "full")
    if self.plugin then self.plugin:onViewClosed(self) end
end

function View:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.tick_fn)
end

-- Kindle/Kobo sent us to sleep and back: repaint everything
function View:onResume()
    if self.closed then return end
    self.last_minute = 0
    self:scheduleTick(1)
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

return View
