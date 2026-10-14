-- Grid layout: packs widgets (in list order) into a cols x rows grid,
-- computes pixel rectangles and handles directional focus navigation.
local L = {}

-- size code -> {cols, rows}
L.SIZES = {
    s = { 1, 1 }, -- klein
    w = { 2, 1 }, -- breit
    t = { 1, 2 }, -- hoch
    l = { 2, 2 }, -- groß
}
L.SIZE_NAMES = { s = "Klein", w = "Breit", t = "Hoch", l = "Groß" }

-- returns list of placements {index, col, row, cw, ch} (0-based col/row) and list of overflow indices
function L.pack(items, cols, rows)
    local occ = {}
    local function free(c, r, cw, ch)
        if c + cw > cols or r + ch > rows then return false end
        for y = r, r + ch - 1 do
            for x = c, c + cw - 1 do
                if occ[y * cols + x] then return false end
            end
        end
        return true
    end
    local placed, overflow = {}, {}
    for i, item in ipairs(items) do
        local sz = L.SIZES[item.size or "s"] or L.SIZES.s
        local cw, ch = math.min(sz[1], cols), math.min(sz[2], rows)
        local done = false
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                if free(c, r, cw, ch) then
                    for y = r, r + ch - 1 do
                        for x = c, c + cw - 1 do occ[y * cols + x] = true end
                    end
                    placed[#placed + 1] = { index = i, col = c, row = r, cw = cw, ch = ch }
                    done = true
                    break
                end
            end
            if done then break end
        end
        if not done then overflow[#overflow + 1] = i end
    end
    return placed, overflow
end

-- assign pixel rects to placements inside area {x,y,w,h}
function L.rects(placed, cols, rows, area, gap)
    gap = gap or 8
    local cw = (area.w - gap * (cols + 1)) / cols
    local ch = (area.h - gap * (rows + 1)) / rows
    for _, p in ipairs(placed) do
        local x = area.x + gap + p.col * (cw + gap)
        local y = area.y + gap + p.row * (ch + gap)
        p.x = math.floor(x + 0.5)
        p.y = math.floor(y + 0.5)
        p.w = math.floor(x + p.cw * cw + (p.cw - 1) * gap + 0.5) - p.x
        p.h = math.floor(y + p.ch * ch + (p.ch - 1) * gap + 0.5) - p.y
    end
    return placed
end

-- find the placement index to move to from `cur` in direction dir
-- returns new position in `placed` or nil when at the edge
function L.navigate(placed, cur, dir)
    local a = placed[cur]
    if not a then return placed[1] and 1 or nil end
    local acx, acy = a.x + a.w / 2, a.y + a.h / 2
    local best, best_score
    for i, b in ipairs(placed) do
        if i ~= cur then
            local bcx, bcy = b.x + b.w / 2, b.y + b.h / 2
            local primary, secondary, overlap
            if dir == "Right" then
                primary = b.x - (a.x + a.w) ; secondary = math.abs(bcy - acy)
                overlap = b.y < a.y + a.h and b.y + b.h > a.y
            elseif dir == "Left" then
                primary = a.x - (b.x + b.w) ; secondary = math.abs(bcy - acy)
                overlap = b.y < a.y + a.h and b.y + b.h > a.y
            elseif dir == "Down" then
                primary = b.y - (a.y + a.h) ; secondary = math.abs(bcx - acx)
                overlap = b.x < a.x + a.w and b.x + b.w > a.x
            elseif dir == "Up" then
                primary = a.y - (b.y + b.h) ; secondary = math.abs(bcx - acx)
                overlap = b.x < a.x + a.w and b.x + b.w > a.x
            end
            if primary and primary >= -2 then
                local score = primary + secondary * 2 + (overlap and 0 or 10000)
                if not best_score or score < best_score then
                    best, best_score = i, score
                end
            end
        end
    end
    return best
end

-- placement index at pixel position
function L.hit(placed, x, y)
    for i, p in ipairs(placed) do
        if x >= p.x and x < p.x + p.w and y >= p.y and y < p.y + p.h then return i end
    end
end

-- first placement in a given column side ("left"/"right") nearest to a y
function L.edge(placed, side, y)
    local best, bd
    for i, p in ipairs(placed) do
        local d = math.abs(p.y + p.h / 2 - (y or 0))
        local xs = side == "left" and p.x or -(p.x + p.w)
        local score = xs * 10 + d
        if not bd or score < bd then best, bd = i, score end
    end
    return best
end

return L
