local class = require("src.lib.class")
local Url = require("src.net.url")
local Web = require("src.net.web")

local HttpGet = class()

function HttpGet:init()
    self._web = Web.active()
    if not self._web then
        self.tcp = require("src.net.tcp"):new()
    end
    self.done = false
    self.buf = ""
    self.headerDone = false
    self.status = 0
    self.length = nil
    self.callback = nil
    self.startedAt = 0
end

function HttpGet:finish(ok, body)
    if self.done then return end
    self.done = true
    if self.tcp then
        self.tcp:close()
    end
    local cb = self.callback
    self.callback = nil
    if cb then
        cb(ok, body)
    end
end

function HttpGet:get(target, callback)
    if type(target) == "string" then
        local parsed, err = Url.parse(target)
        if not parsed then
            self.callback = callback
            self:finish(false, err or "invalid url")
            return self
        end
        target = parsed
    end
    self.callback = callback
    self.startedAt = love.timer.getTime()
    if self._web then
        if type(target) ~= "table" or not target.host then
            self:finish(false, "invalid url")
            return self
        end
        local id, err = Web.fetch(Web.httpUrl(target))
        if not id then
            self:finish(false, err or "request failed")
            return self
        end
        self._fetchId = id
        return self
    end
    if type(target) ~= "table" or not target.host then
        self:finish(false, "invalid url")
        return self
    end
    local host = target.host
    local port = tonumber(target.port) or 8080
    local path = Url.requestPath(target)
    local ok, err = self.tcp:connect(host, port, target.tls)
    if not ok then
        self:finish(false, err or "connect failed")
        return self
    end
    local req = table.concat({
        "GET " .. path .. " HTTP/1.1",
        "Host: " .. Url.hostHeader(target),
        "Accept: application/json",
        "User-Agent: LoveDiepClient",
        "ngrok-skip-browser-warning: 1",
        "Connection: close",
        "",
        ""
    }, "\r\n")
    self.tcp:send(req)
    return self
end

function HttpGet:update()
    if self.done then return end
    if self._web then
        if self.startedAt > 0 and (love.timer.getTime() - self.startedAt) > 12 then
            self:finish(false, "timed out")
            return
        end
        local ev = Web.poll(self._fetchId)
        if not ev then
            return
        end
        local okFlag, status, count = ev:match("^http\t([01])\t(%d+)\t(%d+)$")
        if not okFlag then
            self:finish(false, "bad response")
            return
        end
        local parts = {}
        local n = tonumber(count) or 0
        for i = 0, n - 1 do
            parts[#parts + 1] = Web.body(self._fetchId, i)
        end
        local body = table.concat(parts)
        if okFlag == "1" and tonumber(status) == 200 then
            self:finish(true, body)
        else
            self:finish(false, "http " .. tostring(status))
        end
        return
    end
    if self.startedAt > 0 and (love.timer.getTime() - self.startedAt) > 12 then
        self:finish(false, "timed out")
        return
    end
    self.tcp:update()
    self.buf = self.buf .. self.tcp:readAll()
    if #self.buf > 1048576 then
        self:finish(false, "network buffer overflow")
        return
    end
    if not self.headerDone then
        local sep = self.buf:find("\r\n\r\n", 1, true)
        local sepLen = 4
        if not sep then
            sep = self.buf:find("\n\n", 1, true)
            sepLen = 2
        end
        if not sep then
            if self.tcp.closed then
                self:finish(false, self.tcp.err or "closed")
            end
            return
        end
        local header = self.buf:sub(1, sep - 1)
        self.buf = self.buf:sub(sep + sepLen)
        self.status = tonumber(header:match("^HTTP/%d%.%d%s+(%d+)")) or 0
        local cl = header:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")
        if cl then
            self.length = tonumber(cl)
        end
        self.headerDone = true
    end
    if self.length then
        if #self.buf >= self.length then
            local body = self.buf:sub(1, self.length)
            if self.status == 200 then
                self:finish(true, body)
            else
                self:finish(false, "http " .. tostring(self.status))
            end
        elseif self.tcp.closed then
            self:finish(false, self.tcp.err or "closed")
        end
        return
    end
    if self.tcp.closed then
        if self.status == 200 then
            self:finish(true, self.buf)
        else
            self:finish(false, self.tcp.err or ("http " .. tostring(self.status)))
        end
    end
end

return HttpGet
