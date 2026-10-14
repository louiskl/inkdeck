-- Minimal JSON encoder/decoder (pure Lua, no dependencies).
-- Decoding: objects -> tables, arrays -> tables with sequence, null -> json.null
local json = {}

json.null = setmetatable({}, { __tostring = function() return "null" end })

---------------------------------------------------------------- encode
local escape_map = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_str(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return escape_map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

local function encode(v, indent, cur, seen)
    local t = type(v)
    if v == nil or v == json.null then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v % 1 == 0 and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.14g", v)
    elseif t == "string" then return escape_str(v)
    elseif t == "table" then
        if seen[v] then error("json: circular reference") end
        seen[v] = true
        local nl, ind, ind2, sep = "", "", "", ":"
        if indent then
            nl = "\n"; ind = cur .. indent; ind2 = cur; sep = ": "
        end
        local out = {}
        local arr, n = is_array(v)
        local res
        if arr and (n > 0 or getmetatable(v) == json.array_mt) then
            for i = 1, n do
                out[#out + 1] = ind .. encode(v[i], indent, ind, seen)
            end
            res = n == 0 and "[]" or "[" .. nl .. table.concat(out, "," .. nl) .. nl .. ind2 .. "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local val = v[k]
                if val == nil then val = v[tonumber(k)] end
                out[#out + 1] = ind .. escape_str(k) .. sep .. encode(val, indent, ind, seen)
            end
            res = #out == 0 and "{}" or "{" .. nl .. table.concat(out, "," .. nl) .. nl .. ind2 .. "}"
        end
        seen[v] = nil
        return res
    end
    error("json: cannot encode type " .. t)
end

json.array_mt = {}
function json.array(t) return setmetatable(t or {}, json.array_mt) end

function json.encode(v, pretty)
    return encode(v, pretty and "  " or nil, "", {})
end

---------------------------------------------------------------- decode
local function decode_error(str, pos, msg)
    error(string.format("json: %s at position %d", msg, pos), 0)
end

local function skip_ws(str, pos)
    return str:find("[^ \t\r\n]", pos) or #str + 1
end

local function utf8_char(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    else
        return string.char(0xF0 + math.floor(cp / 0x40000),
            0x80 + math.floor(cp / 0x1000) % 0x40,
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
end

local parse

local function parse_string(str, pos)
    local buf = {}
    local i = pos + 1
    while true do
        local c = str:sub(i, i)
        if c == "" then decode_error(str, i, "unterminated string") end
        if c == '"' then return table.concat(buf), i + 1 end
        if c == "\\" then
            local e = str:sub(i + 1, i + 1)
            if e == "u" then
                local hex = str:sub(i + 2, i + 5)
                local cp = tonumber(hex, 16)
                if not cp then decode_error(str, i, "bad unicode escape") end
                i = i + 6
                if cp >= 0xD800 and cp <= 0xDBFF and str:sub(i, i + 1) == "\\u" then
                    local lo = tonumber(str:sub(i + 2, i + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        i = i + 6
                    end
                end
                buf[#buf + 1] = utf8_char(cp)
            else
                local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                buf[#buf + 1] = map[e] or e
                i = i + 2
            end
        else
            local j = str:find('["\\]', i)
            if not j then decode_error(str, i, "unterminated string") end
            buf[#buf + 1] = str:sub(i, j - 1)
            i = j
        end
    end
end

parse = function(str, pos)
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "{" then
        local obj = {}
        pos = skip_ws(str, pos + 1)
        if str:sub(pos, pos) == "}" then return obj, pos + 1 end
        while true do
            pos = skip_ws(str, pos)
            if str:sub(pos, pos) ~= '"' then decode_error(str, pos, "expected key") end
            local key
            key, pos = parse_string(str, pos)
            pos = skip_ws(str, pos)
            if str:sub(pos, pos) ~= ":" then decode_error(str, pos, "expected ':'") end
            local val
            val, pos = parse(str, pos + 1)
            obj[key] = val
            pos = skip_ws(str, pos)
            local d = str:sub(pos, pos)
            if d == "}" then return obj, pos + 1 end
            if d ~= "," then decode_error(str, pos, "expected ',' or '}'") end
            pos = pos + 1
        end
    elseif c == "[" then
        local arr = json.array()
        pos = skip_ws(str, pos + 1)
        if str:sub(pos, pos) == "]" then return arr, pos + 1 end
        while true do
            local val
            val, pos = parse(str, pos)
            arr[#arr + 1] = val
            pos = skip_ws(str, pos)
            local d = str:sub(pos, pos)
            if d == "]" then return arr, pos + 1 end
            if d ~= "," then decode_error(str, pos, "expected ',' or ']'") end
            pos = pos + 1
        end
    elseif c == '"' then
        return parse_string(str, pos)
    elseif str:sub(pos, pos + 3) == "true" then return true, pos + 4
    elseif str:sub(pos, pos + 4) == "false" then return false, pos + 5
    elseif str:sub(pos, pos + 3) == "null" then return json.null, pos + 4
    else
        local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if not num or num == "" then decode_error(str, pos, "unexpected character '" .. c .. "'") end
        return tonumber(num), pos + #num
    end
end

function json.decode(str)
    if type(str) ~= "string" then error("json: expected string") end
    local ok, res = pcall(function()
        local v, pos = parse(str, 1)
        pos = skip_ws(str, pos)
        if pos <= #str then decode_error(str, pos, "trailing garbage") end
        return v
    end)
    if not ok then return nil, res end
    return res
end

-- Treat json.null as nil-ish helper
function json.val(v)
    if v == json.null then return nil end
    return v
end

return json
