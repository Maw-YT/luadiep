--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local ffi = require("ffi")
local class = require("../class")

pcall(function()
    ffi.cdef[[
        typedef union { float f; int32_t i; uint32_t u; uint8_t b[4]; } f32conv;
    ]]
end)

local conv = ffi.new("f32conv")

local Reader = class()

function Reader:init(buf)
    if type(buf) == "string" then
        self.buffer = buf
        self.len = #buf
    else
        self.buffer = tostring(buf)
        self.len = #self.buffer
    end
    self.at = 0
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
    while bit.band(self:_byte(self.at), 0x80) ~= 0 do
        out = bit.bor(out, bit.lshift(bit.band(self:_byte(self.at), 0x7F), i))
        self.at = self.at + 1
        i = i + 7
    end
    out = bit.bor(out, bit.lshift(bit.band(self:_byte(self.at), 0x7F), i))
    self.at = self.at + 1
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
    conv.i = swapped
    return conv.f + 0.0
end

function Reader:float()
    conv.b[0] = self:_byte(self.at)
    conv.b[1] = self:_byte(self.at + 1)
    conv.b[2] = self:_byte(self.at + 2)
    conv.b[3] = self:_byte(self.at + 3)
    self.at = self.at + 4
    return conv.f + 0.0
end

function Reader:stringNT()
    local start = self.at
    while self.at < self.len and self:_byte(self.at) ~= 0 do
        self.at = self.at + 1
    end
    local s = self.buffer:sub(start + 1, self.at)
    self.at = self.at + 1
    return s
end

return Reader
