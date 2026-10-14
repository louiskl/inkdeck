--[[--
InkDeck – a home dashboard for e-ink devices, running inside KOReader.

Menu: Tools → InkDeck. Configuration lives in the "inkdeck" folder
(on a Kindle: the USB drive root, i.e. /mnt/us/inkdeck/config.json).

@module koplugin.InkDeck
--]]

local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local I18N = require("inkdeck/i18n")
local T = I18N.t
local Screen = Device.screen

local Core = require("inkdeck/core")
local U = require("inkdeck/util")

-- pick the language before any text is created
local function applyLanguage(cfg)
    local lang = cfg and cfg.language or "auto"
    if lang == "auto" or not lang then
        lang = G_reader_settings and G_reader_settings:readSetting("language") or "en"
    end
    I18N.set(lang)
end
applyLanguage(nil)
local json = require("inkdeck/json")

local InkDeck = WidgetContainer:extend{
    name = "inkdeck",
    is_doc_only = false,
}

local autostart_done = false

function InkDeck:init()
    Dispatcher:registerAction("inkdeck_show", {
        category = "none", event = "ShowInkDeck", title = T("Open InkDeck"), general = true,
    })
    self.ui.menu:registerToMainMenu(self)
    if not autostart_done and G_reader_settings:isTrue("inkdeck_autostart") and not self.ui.document then
        autostart_done = true
        UIManager:nextTick(function() self:show() end)
    end
end

function InkDeck:dataDir()
    if Device:isKindle() then return "/mnt/us/inkdeck" end
    if Device:isKobo() then return "/mnt/onboard/inkdeck" end
    return DataStorage:getDataDir() .. "/inkdeck"
end

function InkDeck:configPath() return self:dataDir() .. "/config.json" end

function InkDeck:loadConfig()
    local dir = self:dataDir()
    U.mkdir(dir)
    U.mkdir(dir .. "/photos")
    U.mkdir(dir .. "/cache")
    local path = self:configPath()
    if not U.fileExists(path) then
        local cfg = Core.defaultConfig()
        U.saveJson(path, cfg)
        return cfg
    end
    local cfg, err = U.loadJson(path)
    if type(cfg) ~= "table" then
        UIManager:show(InfoMessage:new{
            text = T("InkDeck: config.json is invalid and was ignored.") .. "\n\n" .. tostring(err),
        })
        return Core.defaultConfig()
    end
    -- fill in missing top-level defaults
    local def = Core.defaultConfig()
    for k, v in pairs(def) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

function InkDeck:saveConfig(cfg)
    local ok, err = pcall(U.saveJson, self:configPath(), cfg)
    if not ok then logger.warn("InkDeck: could not save config", err) end
end

function InkDeck:makeContext(cfg)
    local NetworkMgr = require("ui/network/manager")
    local online = true
    local ctx = {
        net = require("inkdeck/net"),
        data_dir = self:dataDir(),
        cache_dir = self:dataDir() .. "/cache",
        config = cfg,
    }
    ctx.battery = function()
        local ok, v = pcall(function() return Device:getPowerDevice():getCapacity() end)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    ctx.refreshOnline = function()
        local ok, v = pcall(NetworkMgr.isConnected, NetworkMgr)
        online = not ok or v
    end
    ctx.offline = function() return not online end
    ctx.input = function(title, default, callback)
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = title,
            input = default or "",
            buttons = { {
                { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                {
                    text = T("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText()
                        UIManager:close(dialog)
                        callback(text)
                        if self.view then self.view:repaint("partial") end
                    end,
                },
            } },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end
    return ctx
end

function InkDeck:keepAwake(on)
    if self.config and self.config.keep_awake == false then return end
    local PluginShare = require("pluginshare")
    PluginShare.pause_auto_suspend = on
    if Device:isKindle() then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver " .. (on and "1" or "0") .. " 2>/dev/null")
    end
end

function InkDeck:show()
    if self.view and not self.view.closed then return end
    local cfg = self:loadConfig()
    self.config = cfg
    applyLanguage(cfg)
    U.timezone = cfg.timezone or "system"
    U.clock12 = cfg.clock_12h == true
    math.randomseed(os.time())
    -- orientation
    self.prev_rotation = Screen:getRotationMode()
    local want = cfg.orientation == "landscape" and Screen.DEVICE_ROTATED_CLOCKWISE or Screen.DEVICE_ROTATED_UPRIGHT
    if Screen:getRotationMode() ~= want then
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("SetRotationMode", want))
        if Screen:getRotationMode() ~= want then Screen:setRotationMode(want) end
    end
    local View = require("inkdeck/view")
    self.view = View:new{ plugin = self, config = cfg, ctx = self:makeContext(cfg) }
    self:keepAwake(true)
    UIManager:show(self.view, "full")
    -- make sure Wi-Fi is on; refresh everything once we are online
    local NetworkMgr = require("ui/network/manager")
    pcall(NetworkMgr.runWhenOnline, NetworkMgr, function()
        if self.view and not self.view.closed then
            for _, e in ipairs(self.view.dash:allInstances()) do e.inst.last_update = 0 end
            self.view:scheduleTick(0.5)
        end
    end)
end

function InkDeck:reload(view)
    view:close()
    UIManager:nextTick(function() self:show() end)
end

function InkDeck:onViewClosed(view)
    if self.view == view then self.view = nil end
    self:keepAwake(false)
    if self.prev_rotation and Screen:getRotationMode() ~= self.prev_rotation then
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("SetRotationMode", self.prev_rotation))
    end
end

function InkDeck:onShowInkDeck()
    self:show()
    return true
end

function InkDeck:addToMainMenu(menu_items)
    menu_items.inkdeck = {
        text = T("InkDeck dashboard"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = T("Open InkDeck"),
                callback = function() self:show() end,
            },
            {
                text = T("Open when KOReader starts"),
                checked_func = function() return G_reader_settings:isTrue("inkdeck_autostart") end,
                callback = function() G_reader_settings:flipNilOrFalse("inkdeck_autostart") end,
            },
            {
                text = T("About & folders"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = "InkDeck " .. Core.VERSION .. "\n\n" .. T("Configuration:") .. "\n" .. self:configPath()
                            .. "\n\n" .. T("Photos:") .. "\n" .. self:dataDir() .. "/photos"
                            .. "\n\n" .. T("Controls: the d-pad moves the selection, OK opens a widget, the page keys switch pages, the Menu key opens the InkDeck menu."),
                    })
                end,
            },
        },
    }
end

return InkDeck
