-- Browser transport for the love.js build. Desktop play never calls into here
-- except for Web.active(), which is false when love.js is not loaded.
-- Binary payloads cross the Lua/JS boundary as base64 because love.js.eval
-- returns a single text line.

local B64 = require("src.lib.b64")
local Url = require("src.net.url")

local Web = {}

local checked = false
local enabled = false
local queues = {}
local pageHost
local pageHttps

local function js(expr)
    local ok, result = pcall(love.js.eval, expr)
    if not ok or result == nil then
        return ""
    end
    result = tostring(result)
    if result == "nil" then
        return ""
    end
    return result
end

function Web.active()
    if checked then
        return enabled
    end
    checked = true
    if love.js == nil then
        pcall(require, "normalize1")
    end
    enabled = type(love.js) == "table" and type(love.js.eval) == "function"
    return enabled
end

local function refreshPage()
    if pageHost ~= nil then
        return
    end
    local line = js("(function(){return window.DiepWeb ? DiepWeb.page() : '';})()")
    local flag, host = line:match("^([01])\t(.+)$")
    if not host or host == "" then
        pageHost = ""
        pageHttps = false
        return
    end
    pageHost = host
    pageHttps = flag == "1"
end

function Web.pageHost()
    if not Web.active() then
        return nil
    end
    refreshPage()
    if pageHost == "" then
        return nil
    end
    return pageHost
end

function Web.pageHttps()
    if not Web.active() then
        return false
    end
    refreshPage()
    return pageHttps == true
end

function Web.sameHost(target)
    local host = Web.pageHost()
    if not host or type(target) ~= "table" then
        return false
    end
    return Url.hostHeader(target):lower() == host:lower()
end

function Web.socketUrl(target)
    local tls = target.tls
    if Web.sameHost(target) then
        tls = Web.pageHttps()
    end
    local scheme = tls and "wss" or "ws"
    return scheme .. "://" .. Url.hostHeader(target) .. Url.requestPath(target)
end

function Web.httpUrl(target)
    local path = Url.requestPath(target)
    if Web.sameHost(target) then
        return path
    end
    local tls = target.tls or Web.pageHttps()
    local scheme = tls and "https" or "http"
    return scheme .. "://" .. Url.hostHeader(target) .. path
end

function Web.pump()
    if not Web.active() then
        return
    end
    for _ = 1, 64 do
        local line = js("(function(){return window.DiepWeb ? DiepWeb.pull() : '';})()")
        if line == "" then
            return
        end
        local id, rest = line:match("^(%d+)\t(.*)$")
        if id then
            local q = queues[id]
            if not q then
                q = {}
                queues[id] = q
            end
            q[#q + 1] = rest
        end
    end
end

function Web.poll(id)
    Web.pump()
    id = tostring(id or "")
    local q = queues[id]
    if not q or #q == 0 then
        return nil
    end
    return table.remove(q, 1)
end

local function quote(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub("'", "\\'")
    s = s:gsub("[\r\n]", "")
    return "'" .. s .. "'"
end

function Web.openSocket(url)
    local id = js("(function(){return window.DiepWeb ? DiepWeb.open(" .. quote(url) .. ") : '';})()")
    if id == "" or not id:match("^%d+$") then
        return nil, "socket failed"
    end
    return id
end

function Web.send(id, data)
    local payload = B64.encode(data or "")
    js("(function(){return window.DiepWeb ? DiepWeb.send(" .. quote(id) .. "," .. quote(payload) .. ") : '0';})()")
end

function Web.close(id)
    if not id then
        return
    end
    js("(function(){return window.DiepWeb ? DiepWeb.close(" .. quote(id) .. ") : '0';})()")
    queues[tostring(id)] = nil
end

function Web.fetch(url)
    local id = js("(function(){return window.DiepWeb ? DiepWeb.fetchGet(" .. quote(url) .. ") : '';})()")
    if id == "" or not id:match("^%d+$") then
        return nil, "request failed"
    end
    return id
end

function Web.body(id, index)
    local part = js("(function(){return window.DiepWeb ? DiepWeb.body(" .. quote(id) .. "," .. tostring(tonumber(index) or 0) .. ") : '';})()")
    if part == "" then
        return ""
    end
    return B64.decode(part)
end

return Web
