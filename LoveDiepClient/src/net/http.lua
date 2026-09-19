local class = require("src.class")
local Tcp = require("src.net.tcp")

local HttpGet = class()

function HttpGet:init()
    self.tcp = Tcp:new()
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
    self.tcp:close()
    local cb = self.callback
    self.callback = nil
    if cb then
        cb(ok, body)
    end
end

function HttpGet:get(host, port, path, callback)
    self.callback = callback
    self.startedAt = love.timer.getTime()
    local ok, err = self.tcp:connect(host, tonumber(port) or 8080)
    if not ok then
        self:finish(false, err or "connect failed")
        return self
    end
    local req = table.concat({
        "GET " .. (path or "/") .. " HTTP/1.1",
        "Host: " .. tostring(host) .. ":" .. tostring(port),
        "Accept: application/json",
        "Connection: close",
        "",
        ""
    }, "\r\n")
    self.tcp:send(req)
    return self
end

function HttpGet:update()
    if self.done then return end
    if self.startedAt > 0 and (love.timer.getTime() - self.startedAt) > 8 then
        self:finish(false, "timed out")
        return
    end
    self.tcp:update()
    self.buf = self.buf .. self.tcp:readAll()
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
