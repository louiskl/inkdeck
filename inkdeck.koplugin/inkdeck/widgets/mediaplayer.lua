-- Media player via Home Assistant (media_player.* entity): Spotify, Sonos, Chromecast, Plex, …
-- Shows what's playing and controls it – no extra login, uses your Home Assistant token.
local Base = require("inkdeck/widgets/base")
local NP = require("inkdeck/nowplaying")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local json = require("inkdeck/json")

local Media = Base.define{
    type = "mediaplayer",
    name = "Media Player",
    icon = UI.ICON.music,
    interval = 20,
    controls = true,
    defaults = { entity = "" },
}

function Media:fullInterval() return 5 end

function Media:cfg()
    local g = (self.ctx.config and self.ctx.config.homeassistant) or {}
    return (U.trim(g.url or ""):gsub("/+$", "")), g.token
end

-- "2026-10-14T17:40:12.345+00:00" -> epoch
local function parse_iso_utc(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, h, mi, se = s:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return nil end
    local e = U.timegm({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
    local sign, oh, om = s:match("([+-])(%d%d):?(%d%d)$")
    if sign then
        local off = tonumber(oh) * 3600 + tonumber(om) * 60
        e = sign == "+" and (e - off) or (e + off)
    end
    return e
end

function Media:update(now)
    local url, token = self:cfg()
    if self.ctx.demo_music and (url == "" or not token or token == "") then
        self.now = self.ctx.demo_music
        self.cover_path = self.ctx.demo_music.cover_path
        self.fetched_at = now
        self.has_data = true
        return true
    end
    if url == "" or not token or token == "" then
        self.error = T("Home Assistant not set up.\nAdd URL and token in the editor.")
        return true
    end
    local id = U.trim(self.s.entity or "")
    if id == "" then self.error = T("Choose a media_player entity in the editor.") return true end
    local st, err = self.ctx.net.getJson(url .. "/api/states/" .. id, { Authorization = "Bearer " .. token }, 8)
    if not st then self.error = T("Home Assistant unreachable") .. "\n" .. tostring(err) return true end
    local a = st.attributes or {}
    local state = json.val(st.state)
    if state == "off" or state == "unavailable" or state == "standby" or not json.val(a.media_title) then
        local changed = self.now ~= nil
        self.now = nil
        self.error = (json.val(a.friendly_name) or id) .. ": " .. T("nothing playing")
        return changed
    end
    local pos = tonumber(json.val(a.media_position))
    local upd = parse_iso_utc(json.val(a.media_position_updated_at))
    local playing = state == "playing"
    if pos and upd and playing then pos = pos + math.max(0, now - upd) end
    local n = {
        title = json.val(a.media_title),
        artist = json.val(a.media_artist) or json.val(a.media_album_artist),
        album = json.val(a.media_album_name),
        playing = playing,
        progress_ms = pos and pos * 1000 or nil,
        duration_ms = tonumber(json.val(a.media_duration)) and tonumber(json.val(a.media_duration)) * 1000 or nil,
        volume = tonumber(json.val(a.volume_level)) and math.floor(tonumber(json.val(a.volume_level)) * 100 + 0.5) or nil,
        device = json.val(a.friendly_name),
    }
    local changed = not self.now or self.now.title ~= n.title or self.now.playing ~= n.playing or self.now.volume ~= n.volume
    local pic = json.val(a.entity_picture)
    if pic and pic ~= self.pic then
        local full = pic:match("^https?://") and pic or (url .. pic)
        local path = self.ctx.cache_dir .. "/media_cover.img"
        if self.ctx.net.download(full, path, { Authorization = "Bearer " .. token }) then
            self.pic, self.cover_path = pic, path
            changed = true
        end
    elseif not pic then
        self.pic, self.cover_path = nil, nil
    end
    self.now = n
    self.fetched_at = now
    self.error = nil
    self.has_data = true
    return changed
end

function Media:service(name, extra)
    local url, token = self:cfg()
    if url == "" or not token or token == "" then
        if self.now and name == "media_play_pause" then self.now.playing = not self.now.playing end
        return
    end
    local body = { entity_id = U.trim(self.s.entity or "") }
    for k, v in pairs(extra or {}) do body[k] = v end
    local ok, err = self.ctx.net.request("POST", url .. "/api/services/media_player/" .. name, json.encode(body),
        { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" }, 8)
    if not ok then self.error = T("Action failed: ") .. tostring(err) end
    self:update(U.now())
end

function Media:key(k)
    if k == "Press" then self:service("media_play_pause") return true end
    if k == "Right" then self:service("media_next_track") return true end
    if k == "Left" then self:service("media_previous_track") return true end
    if k == "Up" then self:service("volume_up") return true end
    if k == "Down" then self:service("volume_down") return true end
    return false
end

NP.install(Media)

return Media
