-- Spotify "Now Playing" + remote control through the InkDeck bridge (runs on a PC / Raspberry Pi)
local Base = require("inkdeck/widgets/base")
local NP = require("inkdeck/nowplaying")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t

local Spotify = Base.define{
    type = "spotify",
    name = "Spotify",
    icon = UI.ICON.music,
    interval = 20,
    controls = true,
    defaults = {},
}

function Spotify:init()
    self.now = nil
    self.cover_path = nil
end

function Spotify:fullInterval() return 5 end

function Spotify:bridge()
    local b = (self.ctx.config and self.ctx.config.bridge) or {}
    local url = U.trim(b.url or "")
    return (url:gsub("/+$", ""))
end

function Spotify:update(now)
    local base = self:bridge()
    if base == "" then
        if self.ctx.demo_music then
            self.now = self.ctx.demo_music
            self.cover_path = self.ctx.demo_music.cover_path
            self.fetched_at = now
            self.has_data = true
            return true
        end
        self.error = T("Spotify needs the optional InkDeck bridge.\nSet the bridge address in the editor – or use the Last.fm widget instead.")
        return true
    end
    local data, err = self.ctx.net.getJson(base .. "/spotify/now", nil, 6)
    if not data then
        self.error = T("Bridge unreachable") .. "\n" .. tostring(err)
        return true
    end
    if data.error then self.error = tostring(data.error) self.has_data = false return true end
    self.error = nil
    self.has_data = true
    local changed = not self.now or self.now.title ~= data.title or self.now.playing ~= data.playing
        or self.now.volume ~= data.volume
    self.now = data
    self.fetched_at = now
    if data.cover_id and data.cover_id ~= self.cover_id then
        local path = self.ctx.cache_dir .. "/spotify_cover.png"
        if self.ctx.net.download(base .. "/spotify/cover.png?size=360", path) then
            self.cover_path = path
            self.cover_id = data.cover_id
            changed = true
        end
    elseif not data.cover_id then
        self.cover_path = nil
    end
    return changed or self.expanded_progress
end

function Spotify:send(cmd)
    local base = self:bridge()
    if base == "" then
        if self.now and cmd == "toggle" then self.now.playing = not self.now.playing end
        return
    end
    self.ctx.net.request("POST", base .. "/spotify/" .. cmd, "", nil, 6)
    self:update(U.now())
end

function Spotify:key(k)
    if k == "Press" then self:send("toggle") return true end
    if k == "Right" then self:send("next") return true end
    if k == "Left" then self:send("previous") return true end
    if k == "Up" then self:send("volume?delta=10") return true end
    if k == "Down" then self:send("volume?delta=-10") return true end
    return false
end

NP.install(Spotify)

return Spotify
