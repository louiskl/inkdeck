-- News headlines from RSS/Atom feeds
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local News = Base.define{
    type = "news",
    name = "News",
    icon = UI.ICON.news,
    interval = 1800,
    defaults = {
        
        max_items = 30,
    },
}

local DEFAULT_FEEDS = {
    en = { { name = "BBC News", url = "https://feeds.bbci.co.uk/news/rss.xml" } },
    de = { { name = "tagesschau", url = "https://www.tagesschau.de/index~rss2.xml" } },
}

function News:init()
    if not self.s.feeds or #self.s.feeds == 0 then
        self.s.feeds = DEFAULT_FEEDS[require("inkdeck/i18n").lang] or DEFAULT_FEEDS.en
    end
    self.feeds = {}
    self.feed_idx = 1
    self.sel = 1
    self.reading = false
end

function News:update(now)
    local feeds = self.s.feeds or {}
    local got, err = 0, nil
    for i, f in ipairs(feeds) do
        if type(f) == "string" then f = { url = f } end
        local body, e = self.ctx.net.get(f.url, nil, 20)
        if body then
            local items, ftitle = U.parseFeed(body)
            while #items > (self.s.max_items or 30) do table.remove(items) end
            self.feeds[i] = { name = f.name or ftitle or ("Feed " .. i), items = items }
            got = got + 1
        else
            err = e
        end
    end
    if got == 0 then
        self.error = #feeds == 0 and T("No feed configured") or (T("News unavailable") .. "\n" .. tostring(err))
    else
        self.error = nil
        self.has_data = true
    end
    return true
end

function News:current()
    return self.feeds[self.feed_idx] or self.feeds[1] or { name = "", items = {} }
end

function News:title()
    local f = self:current()
    return self.s.title or ((f.name and f.name ~= "") and f.name) or T("News")
end

function News:drawContent(c, x, y, w, h, p)
    local items = self:current().items
    if #items == 0 then UI.message(c, x, y, w, h, T("Loading news …"), UI.ICON.refresh) return end
    if p.cw == 1 and p.ch == 1 then
        c:textbox(items[1].title, x, y, w, h, { size = 17, bold = true })
        return
    end
    local yy = y
    local first = true
    for i, it in ipairs(items) do
        local size = first and 19 or 15
        local avail = y + h - yy
        if avail < size + 8 then break end
        if first then
            local used = c:textbox(it.title, x, yy, w, math.min(avail, size * 3), { size = size, bold = true })
            yy = yy + used + 4
            if p.ch >= 2 and it.text ~= "" then
                local u2 = c:textbox(it.text, x, yy, w, math.min(y + h - yy, 66), { size = 13, color = "dark" })
                yy = yy + u2 + 6
            end
            c:hline(x, yy + 2, w, 1, "gray")
            yy = yy + 10
            first = false
        else
            c:rect(x, yy + 8, 5, 5, "black")
            local used = c:textbox(it.title, x + 14, yy, w - 14, math.min(avail, (size + 6) * 2), { size = size })
            yy = yy + used + 8
        end
    end
end

function News:hint()
    if self.reading then return T("▲ ▼ next/previous article   ·   OK/Back: list") end
    local n = #(self.s.feeds or {})
    return T("▲ ▼ select   ·   OK: read") .. (n > 1 and T("   ·   ◀ ▶ source") or "") .. T("   ·   Back: close")
end

function News:key(k)
    local items = self:current().items
    if k == "Down" then self.sel = math.min(#items, self.sel + 1) return true end
    if k == "Up" then self.sel = math.max(1, self.sel - 1) return true end
    if k == "Press" then self.reading = not self.reading return true end
    if (k == "Left" or k == "Right") and not self.reading then
        local n = math.max(1, #self.feeds)
        self.feed_idx = (self.feed_idx - 1 + (k == "Right" and 1 or -1)) % n + 1
        self.sel = 1
        return true
    end
    return false
end

-- Back key inside full view: leave reading mode first
function News:back()
    if self.reading then self.reading = false return true end
    return false
end

function News:drawFull(c, W, H)
    local feed = self:current()
    local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, self:hint(),
        #self.feeds > 1 and (self.feed_idx .. "/" .. #self.feeds) or nil)
    local items = feed.items
    if #items == 0 then UI.message(c, x, y, w, h, self.error or T("Loading news …"), UI.ICON.refresh) return end
    if self.reading then
        local it = items[self.sel] or items[1]
        local used = c:textbox(it.title, x, y, w, 120, { size = 26, bold = true, font = "serif" })
        local yy = y + used + 10
        if it.date then
            c:text((it.date:gsub(" %+%d+$", "")), x, yy, { size = 13, color = "dark" })
            yy = yy + 24
        end
        c:hline(x, yy, w, 2, "black")
        c:textbox(it.text ~= "" and it.text or T("(No text in this feed)"), x, yy + 14, w, y + h - yy - 14,
            { size = 18, font = "serif", line_height = 0.35 })
        c:text(self.sel .. " / " .. #items, x, y + h - 2, { size = 12, color = "gray", w = w, align = "right" })
        return
    end
    -- list with selection; keep the selected item visible
    local yy = y
    local start = math.max(1, self.sel - 4)
    for i = start, #items do
        local it = items[i]
        local selected = (i == self.sel)
        local hh = 64
        if yy + hh > y + h then break end
        if selected then c:roundrect(x - 8, yy - 4, w + 16, hh - 4, "black", 8) end
        c:textbox(it.title, x + 4, yy, w - 8, 48, { size = 18, bold = selected, color = selected and "white" or "black",
            bg = selected and "black" or "white" })
        if not selected then c:hline(x, yy + hh - 6, w, 1, "light") end
        yy = yy + hh
    end
    UI.scrollHint(c, x, y, w + 14, start > 1, false)
end

return News
