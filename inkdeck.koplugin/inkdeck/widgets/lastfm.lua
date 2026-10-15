-- Now Playing via Last.fm (no OAuth, no server): shows what you're listening to on any
-- service that scrobbles to Last.fm (Spotify, Apple Music via apps, YouTube Music, …).
-- Needs a free Last.fm API key: https://www.last.fm/api/account/create
local Base = require("inkdeck/widgets/base")
local NP = require("inkdeck/nowplaying")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local json = require("inkdeck/json")

local LastFM = Base.define{
    type = "lastfm",
    name = "Now Playing",
    icon = UI.ICON.music,
    interval = 30,
    defaults = { username = "", api_key = "" },
}

-- Poll faster while something is playing, slower when idle. Each poll is one small
-- HTTPS request (~1 s on a Kindle 4, input is blocked meanwhile), so 15 s is a good balance.
local FAST, SLOW = 15, 60
function LastFM:fullInterval() return 10 end

-- Last.fm's grey star placeholder image
local PLACEHOLDER = "2a96cbd8b46e442fc41c2b86b821562f"

local function text_of(v)
    if type(v) == "table" then return json.val(v["#text"]) or json.val(v.name) end
    return json.val(v)
end

function LastFM:update(now)
    if self.ctx.demo_music and (self.s.username or "") == "" then
        self.now = self.ctx.demo_music
        self.cover_path = self.ctx.demo_music.cover_path
        self.fetched_at = now
        self.has_data = true
        return true
    end
    local user, key = U.trim(self.s.username or ""), U.trim(self.s.api_key or "")
    if user == "" or key == "" then
        self.error = T("Add your Last.fm username and API key in the editor.")
        return true
    end
    local url = "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&limit=1&format=json"
        .. "&user=" .. U.urlencode(user) .. "&api_key=" .. U.urlencode(key)
    local data, err = self.ctx.net.getJson(url, nil, 10)
    if not data then self.error = T("Last.fm unavailable") .. "\n" .. tostring(err) return true end
    if data.error then self.error = "Last.fm: " .. tostring(json.val(data.message) or data.error) return true end
    local tracks = data.recenttracks and data.recenttracks.track
    if type(tracks) == "table" and tracks.name then tracks = { tracks } end -- single object
    local tr = type(tracks) == "table" and tracks[1]
    if not tr then
        self.now = nil
        self.error = T("Nothing scrobbled yet")
        return true
    end
    local attr = tr["@attr"]
    local playing = type(attr) == "table" and attr.nowplaying == "true"
    local when = tr.date and tonumber(json.val(tr.date.uts))
    local n = {
        title = text_of(tr.name),
        artist = text_of(tr.artist),
        album = text_of(tr.album),
        playing = playing,
        when = (not playing) and when or nil,
    }
    if n.album == "" then n.album = nil end
    -- cover: largest image, skip Last.fm's placeholder
    local img
    if type(tr.image) == "table" then
        for _, im in ipairs(tr.image) do
            local u = text_of(im)
            if u and u ~= "" and not u:find(PLACEHOLDER, 1, true) then img = u end
        end
    end
    local changed = not self.now or self.now.title ~= n.title or self.now.playing ~= n.playing
    if img and img ~= self.cover_url then
        -- unique file per cover, so image caches never show a stale picture
        self.cover_n = ((self.cover_n or 0) % 1000) + 1
        local path = self.ctx.cache_dir .. "/lastfm_cover_" .. self.cover_n .. ".img"
        if self.ctx.net.download(img, path) then
            if self.cover_path and self.cover_path ~= path then os.remove(self.cover_path) end
            self.cover_url = img
            self.cover_path = path
            changed = true
        end
    elseif not img then
        self.cover_url, self.cover_path = nil, nil
    end
    self.now = n
    self.interval = n.playing and FAST or SLOW
    self.fetched_at = now
    self.error = nil
    self.has_data = true
    return changed or not n.playing -- "x min ago" changes over time
end

function LastFM:hint() return T("Shows your latest Last.fm scrobble   ·   Back: close") end

NP.install(LastFM)

return LastFM
