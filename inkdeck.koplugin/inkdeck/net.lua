-- HTTP helper using KOReader's bundled LuaSocket/LuaSec (http + https).
-- The PC preview tool replaces this module with a mock.
local Net = {}

local function request(method, url, body, headers, timeout)
    local ok_http, http = pcall(require, "socket.http")
    if not ok_http then return nil, "no socket.http" end
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local ok_su, socketutil = pcall(require, "socketutil")
    local sink = {}
    headers = headers or {}
    if body then
        headers["Content-Length"] = tostring(#body)
        headers["Content-Type"] = headers["Content-Type"] or "application/json"
    end
    headers["User-Agent"] = headers["User-Agent"] or "InkDeck/0.1 (KOReader)"
    if ok_su then socketutil:set_timeout(timeout or 10, (timeout or 10) * 3) end
    local ok, code, resp_headers, status = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            method = method,
            headers = headers,
            source = body and ltn12.source.string(body) or nil,
            sink = ltn12.sink.table(sink),
        })
    end)
    if ok_su then socketutil:reset_timeout() end
    if not ok then return nil, tostring(code) end
    local content = table.concat(sink)
    if type(code) ~= "number" then return nil, tostring(code or status or "Netzwerkfehler") end
    if code >= 400 then return nil, "HTTP " .. code, code, content end
    return content, nil, code
end

function Net.get(url, headers, timeout)
    return request("GET", url, nil, headers, timeout)
end

function Net.request(method, url, body, headers, timeout)
    return request(method, url, body, headers, timeout)
end

function Net.getJson(url, headers, timeout)
    local json = require("inkdeck/json")
    local body, err, code = Net.get(url, headers, timeout)
    if not body then return nil, err, code end
    local data, jerr = json.decode(body)
    if data == nil then return nil, "JSON: " .. tostring(jerr) end
    return data
end

function Net.download(url, path, headers)
    local body, err = Net.get(url, headers, 20)
    if not body then return false, err end
    local f = io.open(path, "wb")
    if not f then return false, "cannot write " .. path end
    f:write(body)
    f:close()
    return true
end

return Net
