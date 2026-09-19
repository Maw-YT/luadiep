--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local openssl = require("openssl")
local bit = require("bit")

local MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
local OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 8, 9, 10
local MAX_PAYLOAD = 1 * 1024 * 1024

local function sha1b64(data)
    local raw = openssl.digest.digest("sha1", data, true)
    local b64 = openssl.base64(raw)
    return (b64:gsub("%s+", ""))
end

local function encodeFrame(opcode, payload)
    payload = payload or ""
    local len = #payload
    local bytes = { bit.bor(0x80, opcode) }
    if len < 126 then
        bytes[#bytes + 1] = len
    elseif len < 65536 then
        bytes[#bytes + 1] = 126
        bytes[#bytes + 1] = bit.rshift(len, 8)
        bytes[#bytes + 1] = bit.band(len, 0xFF)
    else
        bytes[#bytes + 1] = 127
        for i = 7, 0, -1 do
            bytes[#bytes + 1] = bit.band(math.floor(len / (2 ^ (i * 8))), 0xFF)
        end
    end
    local unpackFn = unpack or table.unpack
    local header = string.char(unpackFn(bytes))
    return header .. payload
end

local function unmask(payload, mask)
    local out = {}
    for i = 1, #payload do
        out[i] = string.char(bit.bxor(payload:byte(i), mask:byte(((i - 1) % 4) + 1)))
    end
    return table.concat(out)
end

local function headerValue(headers, name)
    if not headers then return nil end
    name = name:lower()
    local value = headers[name] or headers[name:upper()] or headers[name:gsub("^%l", string.upper)]
    if type(value) == "table" then
        value = value[1] or value[2]
    end
    if type(value) ~= "string" then return nil end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local WebSocket = class()

function WebSocket:init(socket)
    self.socket = socket
    self.buffer = ""
    self.closed = false
    self.cont = nil
    self.onMessage = nil
    self.onClose = nil
    self.onOpen = nil
    local selfRef = self
    socket:on("data", function(chunk)
        selfRef:onData(chunk)
    end)
    socket:on("end", function()
        selfRef:handleClose()
    end)
    socket:on("error", function()
        selfRef:handleClose()
    end)
    pcall(function()
        -- 0 can mean "timeout now" in some luvit builds; keep the socket alive.
        if socket.setTimeout then socket:setTimeout(120000) end
        if socket.resume then socket:resume() end
        if socket.read_start then socket:read_start() end
    end)
end

function WebSocket.handshake(req, socket, leftover)
    local key = headerValue(req.headers, "sec-websocket-key")
    if not key or key == "" then return nil end
    local accept = sha1b64(key .. MAGIC)
    local res = table.concat({
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Accept: " .. accept,
        "",
        ""
    }, "\r\n")
    socket:write(res)
    local ws = WebSocket:new(socket)
    if leftover and #leftover > 0 then
        ws:onData(leftover)
    end
    return ws
end

function WebSocket:onData(chunk)
    if self.closed then return end
    self.buffer = self.buffer .. chunk
    while true do
        local frame, rest = self:readFrame(self.buffer)
        if not frame then break end
        self.buffer = rest
        self:dispatch(frame)
        if self.closed then break end
    end
end

function WebSocket:readFrame(buf)
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
        self:handleClose()
        return nil
    end
    local mask
    if masked then
        if #buf < offset + 4 then return nil end
        mask = buf:sub(offset + 1, offset + 4)
        offset = offset + 4
    end
    if #buf < offset + len then return nil end
    local payload = buf:sub(offset + 1, offset + len)
    if masked then payload = unmask(payload, mask) end
    local rest = buf:sub(offset + len + 1)
    return { opcode = opcode, payload = payload, fin = fin }, rest
end

function WebSocket:dispatch(frame)
    if frame.opcode == OP_CONT then
        if self.cont then
            self.cont.payload = self.cont.payload .. frame.payload
            if frame.fin then
                local full = self.cont
                self.cont = nil
                full.fin = true
                self:dispatch(full)
            end
        end
        return
    end
    if not frame.fin and (frame.opcode == OP_BIN or frame.opcode == OP_TEXT) then
        self.cont = { opcode = frame.opcode, payload = frame.payload, fin = false }
        return
    end
    if frame.opcode == OP_CLOSE then
        self:handleClose()
    elseif frame.opcode == OP_PING then
        self:sendRaw(encodeFrame(OP_PONG, frame.payload))
    elseif frame.opcode == OP_PONG then
        -- ignore
    elseif frame.opcode == OP_BIN or frame.opcode == OP_TEXT then
        if self.onMessage then
            self.onMessage(frame.payload, frame.opcode == OP_BIN)
        end
    end
end

function WebSocket:sendRaw(data)
    if self.closed or not self.socket then return end
    self.socket:write(data)
end

function WebSocket:sendBinary(data)
    self:sendRaw(encodeFrame(OP_BIN, data))
end

function WebSocket:sendText(data)
    self:sendRaw(encodeFrame(OP_TEXT, data))
end

function WebSocket:close()
    if self.closed then return end
    self:sendRaw(encodeFrame(OP_CLOSE, ""))
    self:handleClose()
end

function WebSocket:handleClose()
    if self.closed then return end
    self.closed = true
    if self.socket then
        pcall(function() self.socket:destroy() end)
        self.socket = nil
    end
    if self.onClose then self.onClose() end
end

return WebSocket
