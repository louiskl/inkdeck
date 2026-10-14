-- Photo frame: shows images from the "photos" folder in the InkDeck directory
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Photo = Base.define{
    type = "photo",
    name = "Photo frame",
    icon = UI.ICON.photo,
    interval = 600,
    defaults = { folder = "photos", change_minutes = 10, shuffle = true },
}

function Photo:init()
    self.interval = (self.s.change_minutes or 10) * 60
    self.idx = 0
    self:scan()
end

function Photo:dir()
    local f = self.s.folder or "photos"
    if f:sub(1, 1) == "/" then return f end
    return self.ctx.data_dir .. "/" .. f
end

function Photo:scan()
    self.files = U.listDir(self:dir(), "%.[jp][pn]e?g$")
end

function Photo:update()
    self:scan()
    if #self.files == 0 then return false end
    if self.s.shuffle and #self.files > 2 then
        local nxt = self.idx
        while nxt == self.idx do nxt = math.random(1, #self.files) end
        self.idx = nxt
    else
        self.idx = self.idx % #self.files + 1
    end
    return true
end

function Photo:currentFile()
    if #self.files == 0 then return nil end
    if self.idx < 1 then self.idx = 1 end
    return self:dir() .. "/" .. self.files[self.idx], self.files[self.idx]
end

function Photo:drawTile(c, p, focused)
    local r = UI.RADIUS
    c:roundrect(p.x, p.y, p.w, p.h, "black", r)
    local path = self:currentFile()
    local inset = focused and 8 or 4
    if not path or not c:image(path, p.x + inset, p.y + inset, p.w - 2 * inset, p.h - 2 * inset, { fill = self.s.fill ~= false }) then
        c:roundrect(p.x + 2, p.y + 2, p.w - 4, p.h - 4, "white", r)
        UI.message(c, p.x + 12, p.y + 8, p.w - 24, p.h - 16,
            F("Put photos (JPG/PNG) into the folder\ninkdeck/%s", self.s.folder or "photos"), UI.ICON.photo)
    end
    if focused then
        -- label strip at the bottom
        local lh = 28
        c:roundrect(p.x + p.w / 2 - 70, p.y + p.h - lh - 6, 140, lh, "black", 8)
        c:text(T("PHOTO FRAME"), p.x, p.y + p.h - lh - 1, { size = 12, bold = true, color = "white", w = p.w, align = "center" })
        c:frame(p.x, p.y, p.w, p.h, 4, "black", r)
    end
end

function Photo:hint() return T("◀ ▶ previous / next photo   ·   Back: close") end

function Photo:key(k)
    if #self.files == 0 then return false end
    if k == "Right" or k == "Down" or k == "Press" then self.idx = self.idx % #self.files + 1 return true end
    if k == "Left" or k == "Up" then self.idx = (self.idx - 2) % #self.files + 1 return true end
    return false
end

function Photo:drawFull(c, W, H)
    c:rect(0, 0, W, H, "black")
    local path, name = self:currentFile()
    if not path or not c:image(path, 0, 0, W, H - 30) then
        c:rect(0, 0, W, H, "white")
        UI.message(c, 40, 0, W - 80, H, F("No photos found.\nCopy JPG or PNG files into the folder inkdeck/%s on your device.", self.s.folder or "photos"), UI.ICON.photo)
        return
    end
    c:text(string.format("%s   ·   %d / %d   ·   %s", name, self.idx, #self.files, self:hint()), 12, H - 24,
        { size = 12, color = "light", maxw = W - 24 })
end

return Photo
