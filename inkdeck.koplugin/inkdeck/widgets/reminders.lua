-- Reminders / to-dos stored on the Kindle (reminders.json in the InkDeck folder)
local Base = require("inkdeck/widgets/base")
local UI = require("inkdeck/ui")
local U = require("inkdeck/util")
local T = require("inkdeck/i18n").t
local F = require("inkdeck/i18n").f

local Reminders = Base.define{
    type = "reminders",
    name = "Reminders",
    icon = UI.ICON.reminders,
    interval = 300,
    defaults = { items = {} },
}

function Reminders:path() return self.ctx.data_dir .. "/reminders.json" end

function Reminders:init()
    self.sel = 1
    self:load()
end

function Reminders:load()
    local data = U.loadJson(self:path())
    if type(data) ~= "table" then
        data = {}
        for _, it in ipairs(self.s.items or {}) do
            data[#data + 1] = type(it) == "string" and { text = it, done = false } or it
        end
    end
    self.items = data
end

function Reminders:save()
    U.saveJson(self:path(), self.items)
end

function Reminders:update()
    -- pick up edits made over USB
    local before = #self.items
    self:load()
    return #self.items ~= before
end

function Reminders:sorted()
    local open, done = {}, {}
    for _, it in ipairs(self.items) do
        if it.done then done[#done + 1] = it else open[#open + 1] = it end
    end
    for _, it in ipairs(done) do open[#open + 1] = it end
    return open
end

function Reminders:openCount()
    local n = 0
    for _, it in ipairs(self.items) do if not it.done then n = n + 1 end end
    return n
end

function Reminders:tileRight()
    local n = self:openCount()
    return n > 0 and F("%d open", n) or nil
end

local function due_text(it)
    if not it.due then return nil end
    local e = U.parseIsoLocal(it.due)
    if not e then return tostring(it.due) end
    local t = U.localTable(e)
    local rel = U.relDay(e)
    if t.hour == 0 and t.min == 0 then return rel end
    return rel .. " " .. U.hhmm(e)
end

function Reminders:drawContent(c, x, y, w, h, p)
    local items = self:sorted()
    if #items == 0 then
        UI.message(c, x, y, w, h, T("All done!"), UI.ICON.check)
        return
    end
    local yy = y
    for _, it in ipairs(items) do
        if yy + 26 > y + h then break end
        local rh = UI.row(c, x, yy, w, {
            icon = it.done and UI.ICON.check or UI.ICON.box,
            text = it.text, size = 15, dim = it.done, strike = it.done,
            right = (p.cw >= 2) and due_text(it) or nil,
        })
        yy = yy + rh
    end
end

function Reminders:hint()
    return T("▲ ▼ select   ·   OK: check off   ·   ◀ delete   ·   Back: close")
end

function Reminders:key(k)
    local items = self:sorted()
    local n = #items + 1 -- last row: "+ Neu"
    if k == "Down" then self.sel = math.min(n, self.sel + 1) return true end
    if k == "Up" then self.sel = math.max(1, self.sel - 1) return true end
    if k == "Press" then
        if self.sel == n then
            if self.ctx.input then
                self.ctx.input(T("New reminder"), "", function(text)
                    if text and U.trim(text) ~= "" then
                        table.insert(self.items, 1, { text = U.trim(text), done = false })
                        self:save()
                        self.sel = 1
                    end
                end)
            end
            return false
        end
        local it = items[self.sel]
        it.done = not it.done
        self:save()
        return true
    end
    if k == "Left" and self.sel < n then
        local it = items[self.sel]
        for i, x in ipairs(self.items) do
            if x == it then table.remove(self.items, i) break end
        end
        self:save()
        self.sel = math.max(1, math.min(self.sel, #self.items))
        return true
    end
    return false
end

function Reminders:drawFull(c, W, H)
    local x, y, w, h = UI.fullFrame(c, W, H, self:title(), self.icon, self:hint(), F("%d open", self:openCount()))
    local items = self:sorted()
    local yy = y
    local start = math.max(1, self.sel - 9)
    for i = start, #items + 1 do
        local it = items[i]
        if yy + 44 > y + h then break end
        local rh
        if it then
            rh = UI.row(c, x, yy, w, {
                icon = it.done and UI.ICON.check or UI.ICON.box, text = it.text, size = 20,
                dim = it.done, strike = it.done, selected = (i == self.sel), right = due_text(it), height = 46,
            })
        else
            rh = UI.row(c, x, yy, w, { text = T("+  New reminder …"), size = 20, selected = (i == self.sel),
                bold = true, height = 46 })
        end
        yy = yy + rh + 4
    end
end

return Reminders
