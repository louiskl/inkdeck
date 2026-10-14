-- Base "class" for widgets.
--
-- A widget module defines (all optional except name/type):
--   type, name, icon, interval (seconds between update() calls),
--   defaults = { setting = value },
--   :init()                      after creation
--   :update(now)                 fetch data (may block on network); return true if content changed
--   :drawTile(c, p, focused)     draw inside placement p {x,y,w,h,cw,ch}
--   :drawFull(c, W, H)           draw expanded full-screen view
--   :key(k)                      key in full view: Up/Down/Left/Right/Press -> true if redraw needed
--   :hint()                      footer text for full view
--   :fullInterval()              faster update interval while expanded (optional)
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Base = {}

function Base.define(def)
    def.__index = def
    def.interval = def.interval or 1800
    def.defaults = def.defaults or {}
    def.icon = def.icon or UI.ICON.star

    function def.new(settings, ctx)
        local self = setmetatable({}, def)
        self.s = U.merge(def.defaults, settings or {})
        self.ctx = ctx
        self.last_update = 0
        self.error = nil
        if self.init then self:init() end
        return self
    end

    if not def.title then
        function def:title() return self.s.title or T(def.name) end
    end
    if not def.hint then
        function def:hint() return T("Back: close   ·   Page keys: next widget") end
    end
    if not def.drawFull then
        -- default: draw the tile content big
        function def:drawFull(c, W, H)
            local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, self:hint())
            local p = { x = x - UI.PAD, y = y - UI.HEADER - 8, w = w + 2 * UI.PAD, h = h + UI.HEADER + 8, cw = 2, ch = 2, full = true }
            self:drawContent(c, x, y, w, h, p)
        end
    end
    if not def.drawTile then
        function def:drawTile(c, p, focused)
            local x, y, w, h = UI.tile(c, p, self:title(), self.icon, focused, { right = self.tileRight and self:tileRight() })
            if self.error and not self.has_data then
                UI.message(c, x, y, w, h, self.error, UI.ICON.wifi)
                return
            end
            self:drawContent(c, x, y, w, h, p)
        end
    end
    if not def.key then
        function def:key() return false end
    end
    -- run update() with error capture
    function def:safeUpdate(now)
        if not self.update then return false end
        local ok, res = pcall(self.update, self, now)
        self.last_update = now
        if not ok then
            self.error = T("Error: ") .. (tostring(res):gsub("^.-:%d+: ", ""))
            return true
        end
        return res
    end
    return def
end

return Base
