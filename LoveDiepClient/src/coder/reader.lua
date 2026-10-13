local bit = require("bit")
local class = require("src.lib.class")

local ffiOk, ffi = pcall(require, "ffi")
local conv
if ffiOk then
    pcall(function()
        ffi.cdef[[
            typedef union { float f; int32_t i; uint32_t u; uint8_t b[4]; } f32conv;
        ]]
    end)
    conv = ffi.new("f32conv")
else
    ffi = nil
end

local function floatFromBits(b0, b1, b2, b3)
    if conv then
        conv.b[0] = b0
        conv.b[1] = b1
        conv.b[2] = b2
        conv.b[3] = b3
        return conv.f + 0.0
    end
    return love.data.unpack("<f", string.char(b0, b1, b2, b3))
end

local function floatFromInt(swapped)
    if conv then
        conv.i = swapped
        return conv.f + 0.0
    end
    local u = swapped
    if u < 0 then
        u = u + 4294967296
    end
    return love.data.unpack("<f", string.char(
        u % 256,
        math.floor(u / 256) % 256,
        math.floor(u / 65536) % 256,
        math.floor(u / 16777216) % 256
    ))
end

local Reader = class()

function Reader:init(buf)
    self.buffer = buf or ""
    self.len = #self.buffer
    self.at = 0
    self.bad = false
end

function Reader:_byte(i)
    if i >= self.len then return 0 end
    return self.buffer:byte(i + 1) or 0
end

function Reader:remaining()
    return self.len - self.at
end

function Reader:u8()
    local v = self:_byte(self.at)
    self.at = self.at + 1
    return v
end

function Reader:u16()
    local a = self:_byte(self.at)
    local b = self:_byte(self.at + 1)
    self.at = self.at + 2
    return a + b * 256
end

function Reader:u32()
    local a = self:_byte(self.at)
    local b = self:_byte(self.at + 1)
    local c = self:_byte(self.at + 2)
    local d = self:_byte(self.at + 3)
    self.at = self.at + 4
    return a + b * 256 + c * 65536 + d * 16777216
end

function Reader:vu()
    local out = 0
    local i = 0
    while self.at < self.len and bit.band(self:_byte(self.at), 0x80) ~= 0 do
        out = bit.bor(out, bit.lshift(bit.band(self:_byte(self.at), 0x7F), i))
        self.at = self.at + 1
        i = i + 7
        if i > 35 then break end
    end
    out = bit.bor(out, bit.lshift(bit.band(self:_byte(self.at), 0x7F), i))
    if self.at < self.len then
        self.at = self.at + 1
    elseif self.at == self.len then
        self.at = self.at + 1
    end
    return out
end

function Reader:vi()
    local out = self:vu()
    return bit.bxor(-(bit.band(out, 1)), bit.rshift(out, 1))
end

function Reader:vf()
    local n = self:vi()
    local swapped = bit.bor(
        bit.lshift(bit.band(n, 0xFF), 24),
        bit.lshift(bit.band(n, 0xFF00), 8),
        bit.band(bit.rshift(n, 8), 0xFF00),
        bit.rshift(n, 24)
    )
    return floatFromInt(swapped)
end

function Reader:float()
    local b0 = self:_byte(self.at)
    local b1 = self:_byte(self.at + 1)
    local b2 = self:_byte(self.at + 2)
    local b3 = self:_byte(self.at + 3)
    self.at = self.at + 4
    return floatFromBits(b0, b1, b2, b3)
end

function Reader:float64Precision()
    return self:vi() / 64
end

function Reader:stringNT()
    local start = self.at
    local maxAt = start + 256
    if maxAt > self.len then maxAt = self.len end
    while self.at < maxAt and self:_byte(self.at) ~= 0 do
        self.at = self.at + 1
    end
    local s = self.buffer:sub(start + 1, self.at)
    if self.at < self.len and self:_byte(self.at) == 0 then
        self.at = self.at + 1
    else
        self.bad = true
    end
    return s
end

function Reader:entid()
    local hash = self:vu()
    if hash == 0 then
        return nil
    end
    return { hash = hash, id = self:vu() }
end

return Reader
