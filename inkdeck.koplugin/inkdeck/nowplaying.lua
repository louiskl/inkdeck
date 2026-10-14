-- Shared "Now Playing" layout used by the Last.fm, Media Player and Spotify widgets.
--
-- A widget using it sets:
--   self.now = { title, artist, album, playing, progress_ms, duration_ms, volume, device, when }
--   self.cover_path  (optional local image file)
--   self.fetched_at  (epoch of the last fetch, for progress interpolation)
--   def.controls     (true if the widget handles Press/Left/Right/Up/Down as transport keys)
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local NP = {}

local function mmss(ms)
    if not ms then return "0:00" end
    local s = math.floor(ms / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
NP.mmss = mmss

local function ago(epoch)
    if not epoch then return nil end
    local d = math.max(0, U.now() - epoch)
    if d < 90 then return T("just now") end
    if d < 3600 then return F("%d min ago", math.floor(d / 60)) end
    if d < 86400 then return F("%d h ago", math.floor(d / 3600)) end
    return U.relDay(epoch)
end

function NP.install(def)
    function def:progress()
        local n = self.now
        if not n or not n.duration_ms or n.duration_ms == 0 then return 0, 0, 0 end
        local p = n.progress_ms or 0
        if n.playing and self.fetched_at then p = p + (U.now() - self.fetched_at) * 1000 end
        p = math.min(p, n.duration_ms)
        return p / n.duration_ms, p, n.duration_ms
    end

    function def:tileRight()
        local n = self.now
        if not (n and n.title) then return nil end
        if n.playing then return T("playing") end
        return ago(n.when) or T("paused")
    end

    function def:statusLine()
        local n = self.now
        if n.playing then return T("Now playing") end
        if n.when then return F("Last played %s", ago(n.when)) end
        return T("Paused")
    end

    function def:drawContent(c, x, y, w, h, p)
        local n = self.now
        if not n or not n.title then
            UI.message(c, x, y, w, h, self.error or T("Nothing playing right now"), UI.ICON.music)
            return
        end
        local frac, pos, dur = self:progress()
        local has_progress = dur and dur > 0
        local cs = 0
        if self.cover_path and (p.cw >= 2 or p.ch >= 2) then
            if p.ch >= 2 and p.cw == 1 then
                -- tall: cover on top
                cs = math.min(w, h - 60)
                c:image(self.cover_path, x, y, w, cs, { fill = true })
                local ty = y + cs + 10
                c:text(n.title, x, ty, { size = 17, bold = true, maxw = w })
                c:text(n.artist or "", x, ty + 24, { size = 14, color = "dark", maxw = w })
                if has_progress then UI.progress(c, x, y + h - 12, w, 10, frac) end
                return
            end
            cs = h
            c:image(self.cover_path, x, y, cs, cs, { fill = true })
            c:frame(x, y, cs, cs, 1, "black")
            cs = cs + 16
        end
        local tx, tw = x + cs, w - cs
        local big = p.ch >= 2 and 24 or 19
        local used = c:textbox(n.title, tx, y, tw, big * 2 + 12, { size = big, bold = true })
        c:text(n.artist or "", tx, y + used + 4, { size = 15, maxw = tw })
        if p.ch >= 2 and n.album then c:text(n.album, tx, y + used + 26, { size = 13, color = "dark", maxw = tw }) end
        local by = y + h - 22
        if has_progress then
            c:icon(n.playing and UI.ICON.pause or UI.ICON.play, tx, by - 4, 18)
            UI.progress(c, tx + 28, by, tw - 28, 10, frac)
            if tw > 200 then
                c:text(mmss(pos) .. " / " .. mmss(dur), tx + 28, by - 22, { size = 12, color = "dark", w = tw - 28, align = "right" })
            end
        else
            c:text(self:statusLine(), tx, by - 2, { size = 13, color = "dark", maxw = tw })
        end
    end

    function def:drawFull(c, W, H)
        local n = self.now
        local x, y, w, h = UI.fullFrame(c, W, H, self:title(), UI.ICON.music, self:hint(), n and n.device or nil)
        if not n or not n.title then UI.message(c, x, y, w, h, self.error or T("Nothing playing right now"), UI.ICON.music) return end
        local landscape = W > H
        local cs = landscape and math.min(h, math.floor(w * 0.45)) or math.min(w - 80, math.floor(h * 0.52))
        local cx = landscape and x or x + math.floor((w - cs) / 2)
        if landscape then
            cs = math.min(cs, h - 10)
            y = y + math.floor((h - cs) / 2)
        end
        if self.cover_path then
            c:image(self.cover_path, cx, y, cs, cs, { fill = true })
            c:frame(cx - 1, y - 1, cs + 2, cs + 2, 2, "black")
        else
            c:roundrect(cx, y, cs, cs, "light", 12)
            c:icon(UI.ICON.music, cx + math.floor(cs / 2) - 40, y + math.floor(cs / 2) - 40, 80, { color = "gray" })
        end
        local tx, ty, tw
        if landscape then tx, ty, tw = x + cs + 28, y + 10, w - cs - 28
        else tx, ty, tw = x, y + cs + 20, w end
        local align = landscape and "left" or "center"
        local used = c:textbox(n.title, tx, ty, tw, 76, { size = 28, bold = true, align = align })
        ty = ty + used + 6
        c:text(n.artist or "", tx, ty, { size = 20, w = tw, align = align })
        ty = ty + 30
        if n.album then c:text(n.album, tx, ty, { size = 15, color = "dark", w = tw, align = align }) ty = ty + 26 end
        local frac, pos, dur = self:progress()
        ty = ty + 10
        if dur and dur > 0 then
            UI.progress(c, tx, ty, tw, 14, frac)
            c:text(mmss(pos), tx, ty + 20, { size = 13, color = "dark" })
            c:text(mmss(dur), tx, ty + 20, { size = 13, color = "dark", w = tw, align = "right" })
        else
            c:text(self:statusLine(), tx, ty, { size = 16, color = "dark", w = tw, align = align })
        end
        if not def.controls then return end
        -- transport buttons
        local by = ty + 52
        local bsz = 56
        local gap = 40
        local total = bsz * 3 + gap * 2
        local bx = landscape and tx or tx + math.floor((tw - total) / 2)
        local icons = { UI.ICON.prev, n.playing and UI.ICON.pause or UI.ICON.play, UI.ICON.next }
        for i, ic in ipairs(icons) do
            local ox = bx + (i - 1) * (bsz + gap)
            local mid = i == 2
            c:roundrect(ox, by, bsz, bsz, mid and "black" or "white", bsz / 2)
            if not mid then c:frame(ox, by, bsz, bsz, 2, "black", bsz / 2) end
            c:icon(ic, ox, by + 15, 24, { w = bsz, align = "center", color = mid and "white" or "black" })
        end
        if n.volume then
            local vy = by + bsz + 22
            local vx = landscape and tx or tx + math.floor((tw - 200) / 2)
            c:icon(UI.ICON.vol_up, vx, vy - 4, 18)
            UI.progress(c, vx + 30, vy, 170, 8, n.volume / 100)
        end
    end

    if def.controls then
        function def:hint()
            return T("OK: play/pause   ·   ◀ ▶ track   ·   ▲ ▼ volume   ·   Back: close")
        end
    end
    return def
end

return NP
