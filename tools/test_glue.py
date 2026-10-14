#!/usr/bin/env python3
"""
Smoke test for the KOReader glue (main.lua, view.lua, canvas_ko.lua) using
minimal stubs of the KOReader APIs it touches. Catches typos / nil calls
without needing a real KOReader build.   python3 tools/test_glue.py
"""
import os
import sys
import tempfile

from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(ROOT, "inkdeck.koplugin")
DATA = tempfile.mkdtemp(prefix="inkdeck_test_")

STUBS = r'''
local calls = {}
_G.CALLS = calls
local function log(name) calls[name] = (calls[name] or 0) + 1 end

local function class(base)
    local C = base or {}
    function C:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
    function C:new(o) o = self:extend(o); if o._init then o:_init() end; if o.init then o:init() end; return o end
    return C
end

local Widget = class({})
function Widget:handleEvent(ev)
    local h = self["on" .. ev.name]
    if h then return h(self, unpack(ev.args or {})) end
end
local WidgetContainer = Widget:extend{}
local InputContainer = WidgetContainer:extend{}
function InputContainer:_init()
    self.key_events = self.key_events or {}
    self.key_events.Home = { { "Home" } }
    self.ges_events = self.ges_events or {}
end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end

local W, H, rot = SCREEN_W or 600, SCREEN_H or 800, 0
local Screen = {
    DEVICE_ROTATED_UPRIGHT = 0, DEVICE_ROTATED_CLOCKWISE = 1,
    DEVICE_ROTATED_UPSIDE_DOWN = 2, DEVICE_ROTATED_COUNTER_CLOCKWISE = 3,
}
function Screen:getWidth() return (rot % 2 == 1) and H or W end
function Screen:getHeight() return (rot % 2 == 1) and W or H end
function Screen:scaleBySize(x) return x end
function Screen:getRotationMode() return rot end
function Screen:setRotationMode(m) log("setRotationMode"); rot = m end

local Device = {
    screen = Screen,
    input = { group = { PgFwd = { "RPgFwd", "LPgFwd" }, PgBack = { "RPgBack", "LPgBack" }, Back = { "Back" } } },
}
function Device:hasKeys() return true end
function Device:isTouchDevice() return TOUCH end
function Device:isKindle() return false end
function Device:isKobo() return false end
function Device:getPowerDevice() return { getCapacity = function() return 81 end } end
package.preload["device"] = function() return Device end

package.preload["ui/geometry"] = function()
    local G = {}
    function G:new(o) return setmetatable(o or {}, { __index = G }) end
    return G
end
package.preload["ui/gesturerange"] = function() return { new = function(_, o) return o end } end
package.preload["logger"] = function()
    return { err = function(...) print("LOGGER.ERR", ...) ; log("logger.err") end,
             warn = function(...) print("LOGGER.WARN", ...) end, dbg = function() end, info = function() end }
end
package.preload["gettext"] = function() return function(s) return s end end
package.preload["ui/event"] = function()
    return { new = function(_, name, ...) return { name = name, args = { ... } } end }
end

local shown = {}
local UIManager = { scheduled = {}, dirty = {} }
_G.UIM = UIManager
function UIManager:show(w) table.insert(shown, w); log("show"); if w.handleEvent then w:handleEvent({ name = "Show", args = {} }) end end
function UIManager:close(w) for i, x in ipairs(shown) do if x == w then table.remove(shown, i) end end; log("close")
    if w.onCloseWidget then w:onCloseWidget() end end
function UIManager:setDirty(w, f)
    local mode, geom = f()
    assert(type(mode) == "string", "bad refresh mode")
    assert(geom and geom.w and geom.h, "bad refresh region")
    table.insert(self.dirty, mode); log("setDirty:" .. mode)
end
function UIManager:scheduleIn(s, f) self.scheduled[f] = s; log("scheduleIn") end
function UIManager:unschedule(f) self.scheduled[f] = nil end
function UIManager:nextTick(f) f() end
function UIManager:broadcastEvent(ev)
    log("broadcast:" .. ev.name)
    if ev.name == "SetRotationMode" then Screen:setRotationMode(ev.args[1]) end
    for _, w in ipairs(shown) do if w.handleEvent then w:handleEvent(ev) end end
end
package.preload["ui/uimanager"] = function() return UIManager end

-- blitbuffer / fonts / text
local BB = { Color8 = function(v) return { v = v } end }
package.preload["ffi/blitbuffer"] = function() return BB end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) assert(name and size); return { name = name, size = size } end } end
local function textclass(kind)
    local T = {}
    function T:new(o)
        assert(o.face, kind .. " needs face")
        assert(type(o.text) == "string", kind .. " needs string text")
        o.free = function() end
        o.getSize = function(s) return { w = #s.text * 8, h = 20 } end
        o.paintTo = function(s, bb, x, y) assert(bb and x and y); log(kind .. ".paintTo") end
        o.text_height = 20
        return o
    end
    return T
end
package.preload["ui/widget/textwidget"] = function() return textclass("TextWidget") end
package.preload["ui/widget/textboxwidget"] = function() return textclass("TextBoxWidget") end
package.preload["ui/renderimage"] = function()
    local R = {}
    function R:renderImageFile(path) return nil end
    function R:scaleBlitBuffer(bb) return bb end
    return R
end
package.preload["datastorage"] = function() return { getDataDir = function() return DATA_DIR end } end
package.preload["dispatcher"] = function() return { registerAction = function() end } end
package.preload["ui/widget/infomessage"] = function() return { new = function(_, o) log("InfoMessage"); print("INFO:", o.text); return o end } end
package.preload["ui/network/manager"] = function()
    return { runWhenOnline = function(_, cb) cb() end, isConnected = function() return true end }
end
package.preload["pluginshare"] = function() return {} end
package.preload["ui/widget/inputdialog"] = function()
    return { new = function(_, o) o.getInputText = function() return "Testeintrag" end; o.onShowKeyboard = function() o.buttons[1][2].callback() end; return o end }
end

G_reader_settings = { isTrue = function() return false end, flipNilOrFalse = function() end, readSetting = function(_, k) if k == "language" then return "de" end end }

-- fake framebuffer
FakeBB = {}
for _, m in ipairs({ "paintRect", "paintBorder", "paintRoundedRect", "paintCircle", "invertRect", "blitFrom" }) do
    FakeBB[m] = function(self, ...) local a = { ... }; assert(type(a[1]) == "number" or m == "blitFrom", m .. " bad x"); log("bb." .. m) end
end
'''

TEST = r'''
local InkDeck = dofile(PLUGIN .. "/main.lua")
local plugin = InkDeck:new{ ui = { menu = { registerToMainMenu = function() end } } }
local menu = {}
plugin:addToMainMenu(menu)
assert(menu.inkdeck and #menu.inkdeck.sub_item_table == 3)
plugin:show()
local view = plugin.view
assert(view, "view not created")
view:paintTo(FakeBB, 0, 0)
local keys = { "Down", "Right", "Press", "Up", "Down", "Back", "PgFwd", "Press", "Press", "Back", "PgFwd",
               "Down", "Press", "Down", "Press", "Back", "Back", "PgBack", "Left", "Menu", "Down", "Press" }
for _, k in ipairs(keys) do
    view:onInkKey(k)
    view:paintTo(FakeBB, 0, 0)
end
-- reminders: add via input dialog
view.dash.page_idx = 1
view.dash.focus[1] = 4
view:onInkKey("Press")
for i = 1, 6 do view:onInkKey("Down") end
view:onInkKey("Press")
view:paintTo(FakeBB, 0, 0)
view:onInkKey("Back")
-- ticks (network will fail: no socket in test)
for i = 1, 12 do view:onTick() end
view:paintTo(FakeBB, 0, 0)
-- rotate via menu
view:onInkKey("Menu")
view:onInkKey("Press")   -- first item: Querformat
assert(view.dimen.w == (SCREEN_H or 800) and view.dimen.h == (SCREEN_W or 600), "rotation failed: " .. view.dimen.w .. "x" .. view.dimen.h)
view:paintTo(FakeBB, 0, 0)
for _, k in ipairs({ "Down", "Right", "Right", "Press", "Back" }) do view:onInkKey(k); view:paintTo(FakeBB, 0, 0) end
view:onResume()
-- close via menu
view:onInkKey("Menu")
for i = 1, 4 do view:onInkKey("Down") end
view:onInkKey("Press")
assert(view.closed, "view should be closed")
assert(plugin.view == nil)
return true
'''


TAP_TEST = r'''
local InkDeck = dofile(PLUGIN .. "/main.lua")
local plugin = InkDeck:new{ ui = { menu = { registerToMainMenu = function() end } } }
plugin:show()
local v = plugin.view
assert(v.ges_events.InkTap, "touch gestures missing")
v:onInkTap(nil, { pos = { x = 300, y = 100 } })   -- tap clock tile -> expand
assert(v.dash.expanded, "tap should expand")
v:paintTo(FakeBB, 0, 0)
v:onInkSwipe(nil, { direction = "south" })        -- swipe down -> back
assert(not v.dash.expanded, "swipe south should collapse")
v:onInkSwipe(nil, { direction = "west" })         -- next page
assert(v.dash.page_idx == 2)
v:onInkTap(nil, { pos = { x = 300, y = 10 } })    -- status bar -> menu
assert(v.dash.menu, "menu should open")
v:paintTo(FakeBB, 0, 0)
v:onInkTap(nil, { pos = { x = 5, y = 5 } })       -- outside -> close menu
assert(not v.dash.menu)
v:close()
'''


HIRES_TEST = r'''
local InkDeck = dofile(PLUGIN .. "/main.lua")
local plugin = InkDeck:new{ ui = { menu = { registerToMainMenu = function() end } } }
plugin:show()
local v = plugin.view
assert(math.abs(v.scale - 1072 / 600) < 0.01, "scale " .. v.scale)
assert(v.dash.W == 600, "logical width " .. v.dash.W)
v:paintTo(FakeBB, 0, 0)
v:onInkKey("Down"); v:onInkKey("Press"); v:paintTo(FakeBB, 0, 0)
v:close()
'''


def run(touch, hires=False):
    for f in ("config.json", "reminders.json"):
        if os.path.exists(os.path.join(DATA, "inkdeck", f)):
            os.remove(os.path.join(DATA, "inkdeck", f))
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{PLUGIN}/?.lua;" .. package.path')
    lua.globals().DATA_DIR = DATA
    lua.globals().PLUGIN = PLUGIN
    lua.globals().TOUCH = touch
    if hires:
        lua.globals().SCREEN_W = 1072
        lua.globals().SCREEN_H = 1448
    lua.execute(STUBS)
    lua.execute(HIRES_TEST if hires else TEST)
    if touch:
        lua.execute(TAP_TEST)
    calls = lua.globals().CALLS
    return {k: calls[k] for k in calls.keys()}


if __name__ == "__main__":
    c = run(True, hires=True)
    assert c.get("logger.err") is None, "draw errors logged (hires)"
    print("hires 1072x1448 OK")
    for touch in (False, True):
        c = run(touch)
        assert c.get("logger.err") is None, "draw errors logged"
        print("touch" if touch else "keys", "OK", {k: v for k, v in sorted(c.items()) if not k.startswith("TextWidget")})
    rem = os.path.join(DATA, "inkdeck", "reminders.json")
    print("reminders.json:", open(rem).read()[:200] if os.path.exists(rem) else "missing")
    print("config.json exists:", os.path.exists(os.path.join(DATA, "inkdeck", "config.json")))
