local bit = require("bit")
local class = require("src.class")
local Tcp = require("src.net.tcp")
local Url = require("src.net.url")

local OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 8, 9, 10
local MAX_PAYLOAD = 1 * 1024 * 1024

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
    local out = {}
    local n = #data
    for i = 1, n, 3 do
        local a, b, c = data:byte(i, i + 2)
        b = b or 0
        c = c or 0
        local n24 = a * 65536 + b * 256 + c
        local pad = (i + 1 > n) and 2 or (i + 2 > n) and 1 or 0
        local s = {
            b64chars:sub(math.floor(n24 / 262144) + 1, math.floor(n24 / 262144) + 1),
            b64chars:sub(math.floor(n24 / 4096) % 64 + 1, math.floor(n24 / 4096) % 64 + 1),
            pad == 2 and "=" or b64chars:sub(math.floor(n24 / 64) % 64 + 1, math.floor(n24 / 64) % 64 + 1),
            pad >= 1 and "=" or b64chars:sub(n24 % 64 + 1, n24 % 64 + 1)
        }
        out[#out + 1] = table.concat(s)
    end
    return table.concat(out)
end

local function randomKey()
    local bytes = {}
    for i = 1, 16 do
        bytes[i] = string.char(love.math.random(0, 255))
    end
    return b64encode(table.concat(bytes))
end

local function maskKey()
    return string.char(
        love.math.random(0, 255),
        love.math.random(0, 255),
        love.math.random(0, 255),
        love.math.random(0, 255)
    )
end

local function applyMask(payload, mask)
    local out = {}
    for i = 1, #payload do
        out[i] = string.char(bit.bxor(payload:byte(i), mask:byte(((i - 1) % 4) + 1)))
    end
    return table.concat(out)
end

local function encodeFrame(opcode, payload, doMask)
    payload = payload or ""
    local len = #payload
    local bytes = { bit.bor(0x80, opcode) }
    local maskBit = doMask and 0x80 or 0
    if len < 126 then
        bytes[#bytes + 1] = bit.bor(maskBit, len)
    elseif len < 65536 then
        bytes[#bytes + 1] = bit.bor(maskBit, 126)
        bytes[#bytes + 1] = bit.rshift(len, 8)
        bytes[#bytes + 1] = bit.band(len, 0xFF)
    else
        bytes[#bytes + 1] = bit.bor(maskBit, 127)
        local n = len
        local parts = {}
        for i = 1, 8 do
            parts[9 - i] = bit.band(n, 0xFF)
            n = math.floor(n / 256)
        end
        for i = 1, 8 do
            bytes[#bytes + 1] = parts[i]
        end
    end
    local header = string.char(unpack(bytes))
    if doMask then
        local key = maskKey()
        return header .. key .. applyMask(payload, key)
    end
    return header .. payload
end

local WebSocket = class()

function WebSocket:init()
    self.tcp = Tcp:new()
    self.state = "closed"
    self.buffer = ""
    self.cont = nil
    self.onOpen = nil
    self.onMessage = nil
    self.onClose = nil
    self.err = nil
    self.host = nil
    self.port = nil
    self.hostHeader = nil
    self.origin = nil
end

function WebSocket:connect(target)
    if type(target) == "string" then
        local parsed, err = Url.parse(target)
        if not parsed then
            self.state = "closed"
            self.err = err
            return false, err
        end
        target = parsed
    end
    if type(target) ~= "table" or not target.host then
        self.state = "closed"
        self.err = "invalid url"
        return false, self.err
    end
    self.host = target.host
    self.port = tonumber(target.port) or 8080
    self.hostHeader = Url.hostHeader(target)
    self.origin = Url.origin(target)
    self.path = Url.requestPath(target)
    self.buffer = ""
    self.cont = nil
    self.err = nil
    self.state = "connecting"
    local ok, err = self.tcp:connect(self.host, self.port, target.tls)
    if not ok then
        self.state = "closed"
        self.err = err
        return false, err
    end
    return true
end

function WebSocket:_sendHandshake()
    local key = randomKey()
    local req = table.concat({
        "GET " .. self.path .. " HTTP/1.1",
        "Host: " .. (self.hostHeader or self.host),
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Origin: " .. (self.origin or Url.origin({ host = self.host, port = self.port, scheme = "ws" })),
        "User-Agent: LoveDiepClient",
        "ngrok-skip-browser-warning: 1",
        "Sec-WebSocket-Key: " .. key,
        "Sec-WebSocket-Version: 13",
        "",
        ""
    }, "\r\n")
    self.tcp:send(req)
    self.state = "handshake"
    self.handshakeAt = love.timer.getTime()
end

function WebSocket:_readFrame(buf)
    if #buf < 2 then return nil end
    local b1, b2 = buf:byte(1, 2)
    local fin = bit.band(b1, 0x80) ~= 0
    local opcode = bit.band(b1, 0x0F)
    local masked = bit.band(b2, 0x80) ~= 0
    local len = bit.band(b2, 0x7F)
    local offset = 2
    if len == 126 then
        if #buf < 4 then return nil end
        len = buf:byte(3) * 256 + buf:byte(4)
        offset = 4
    elseif len == 127 then
        if #buf < 10 then return nil end
        len = 0
        for i = 3, 10 do
            len = len * 256 + buf:byte(i)
        end
        offset = 10
    end
    if len > MAX_PAYLOAD then
        self.err = "network buffer overflow"
        self:close()
        return nil
    end
    if masked then
        if #buf < offset + 4 then return nil end
        offset = offset + 4
    end
    if #buf < offset + len then return nil end
    local payload = buf:sub(offset + 1, offset + len)
    if masked then
        local mask = buf:sub(offset - 3, offset)
        payload = applyMask(payload, mask)
    end
    return { opcode = opcode, payload = payload, fin = fin }, buf:sub(offset + len + 1)
end

function WebSocket:_dispatch(frame)
    if frame.opcode == OP_CONT then
        if self.cont then
            self.cont.payload = self.cont.payload .. frame.payload
            if frame.fin then
                local full = self.cont
                self.cont = nil
                full.fin = true
                self:_dispatch(full)
            end
        end
        return
    end
    if not frame.fin and (frame.opcode == OP_BIN or frame.opcode == OP_TEXT) then
        self.cont = { opcode = frame.opcode, payload = frame.payload, fin = false }
        return
    end
    if frame.opcode == OP_CLOSE then
        self:close()
    elseif frame.opcode == OP_PING then
        self.tcp:send(encodeFrame(OP_PONG, frame.payload, true))
    elseif frame.opcode == OP_BIN or frame.opcode == OP_TEXT then
        if self.onMessage then
            self.onMessage(frame.payload, frame.opcode == OP_BIN)
        end
    end
end

function WebSocket:update()
    if self.state == "closed" then return end
    self.tcp:update()
    if self.tcp.err and self.state ~= "closed" then
        self.err = self.tcp.err
        self:close()
        return
    end
    if self.state == "connecting" and self.tcp.connected then
        self:_sendHandshake()
    end
    local chunk = self.tcp:readAll()
    if chunk ~= "" then
        if #self.buffer + #chunk > 2 * 1024 * 1024 then
            self.err = "network buffer overflow"
            self:close()
            return
        end
        self.buffer = self.buffer .. chunk
    end
    if self.state == "handshake" then
        local headerEnd = self.buffer:find("\r\n\r\n", 1, true)
        if headerEnd then
            local headers = self.buffer:sub(1, headerEnd - 1)
            self.buffer = self.buffer:sub(headerEnd + 4)
            if not headers:find("101", 1, true) then
                self.err = "websocket handshake failed"
                self:close()
                return
            end
            self.state = "open"
            if self.onOpen then self.onOpen() end
        elseif self.tcp.closed then
            self.err = self.tcp.err or "connection closed"
            self:close()
        elseif self.handshakeAt and (love.timer.getTime() - self.handshakeAt) > 12 then
            self.err = "timed out"
            self:close()
            return
        end
    end
    if self.state == "open" then
        local frames = 0
        while frames < 64 do
            local frame, rest = self:_readFrame(self.buffer)
            if not frame then break end
            if rest == self.buffer then break end
            self.buffer = rest
            self:_dispatch(frame)
            frames = frames + 1
            if self.state ~= "open" then break end
        end
        if #self.buffer > 2 * 1024 * 1024 then
            self.err = "network buffer overflow"
            self:close()
            return
        end
        if self.tcp.closed then
            self.err = self.tcp.err or "connection closed"
            self:close()
        end
    end
end

function WebSocket:sendBinary(data)
    if self.state ~= "open" then return end
    self.tcp:send(encodeFrame(OP_BIN, data, true))
end

function WebSocket:close()
    if self.state == "closed" then return end
    if self.state == "open" then
        pcall(function() self.tcp:send(encodeFrame(OP_CLOSE, "", true)) end)
    end
    self.state = "closed"
    self.tcp:close()
    if self.onClose then self.onClose(self.err) end
end

return WebSocket
