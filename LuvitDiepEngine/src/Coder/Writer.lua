--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local ffi = require("ffi")
local class = require("../class")
local config = require("../config")

pcall(function()
    ffi.cdef[[
        typedef union { float f; int32_t i; uint32_t u; uint8_t b[4]; } f32conv;
    ]]
end)

local conv = ffi.new("f32conv")

local Writer = class()

function Writer:init()
    self._at = 0
    self._cap = config.writtenBufferChunkSize
    self._buf = ffi.new("uint8_t[?]", self._cap)
end

function Writer:_ensure(n)
    if self._at + n + 8 <= self._cap then return end
    local newCap = self._cap + config.writtenBufferChunkSize
    while self._at + n + 8 > newCap do
        newCap = newCap + config.writtenBufferChunkSize
    end
    local newBuf = ffi.new("uint8_t[?]", newCap)
    ffi.copy(newBuf, self._buf, self._at)
    self._buf = newBuf
    self._cap = newCap
end

function Writer:u8(val)
    self:_ensure(1)
    self._buf[self._at] = bit.band(val, 0xFF)
    self._at = self._at + 1
    return self
end

function Writer:u16(val)
    self:_ensure(2)
    val = bit.band(val, 0xFFFF)
    self._buf[self._at] = bit.band(val, 0xFF)
    self._buf[self._at + 1] = bit.rshift(val, 8)
    self._at = self._at + 2
    return self
end

function Writer:u32(val)
    self:_ensure(4)
    val = bit.tobit(val)
    self._buf[self._at] = bit.band(val, 0xFF)
    self._buf[self._at + 1] = bit.band(bit.rshift(val, 8), 0xFF)
    self._buf[self._at + 2] = bit.band(bit.rshift(val, 16), 0xFF)
    self._buf[self._at + 3] = bit.band(bit.rshift(val, 24), 0xFF)
    self._at = self._at + 4
    return self
end

function Writer:float(val)
    self:_ensure(4)
    conv.f = val + 0.0
    self._buf[self._at] = conv.b[0]
    self._buf[self._at + 1] = conv.b[1]
    self._buf[self._at + 2] = conv.b[2]
    self._buf[self._at + 3] = conv.b[3]
    self._at = self._at + 4
    return self
end

function Writer:vu(val)
    val = bit.tobit(val)
    repeat
        local part = val
        val = bit.rshift(val, 7)
        if val ~= 0 then
            part = bit.bor(part, 0x80)
        end
        self:u8(part)
    until val == 0
    return self
end

function Writer:vi(val)
    val = bit.tobit(val)
    local n = (val < 0) and 1 or 0
    return self:vu(bit.bxor(-n, bit.lshift(val, 1)))
end

function Writer:vf(val)
    conv.f = val + 0.0
    local num = conv.i
    local swapped = bit.bor(
        bit.lshift(bit.band(num, 0xFF), 24),
        bit.lshift(bit.band(num, 0xFF00), 8),
        bit.band(bit.rshift(num, 8), 0xFF00),
        bit.rshift(num, 24)
    )
    return self:vi(swapped)
end

function Writer:float64Precision(float)
    return self:vi(math.floor(float * 64 + 0.5 * (float >= 0 and 1 or -1)))
end

function Writer:stringNT(str)
    str = str or ""
    self:_ensure(#str + 1)
    for i = 1, #str do
        self._buf[self._at] = str:byte(i)
        self._at = self._at + 1
    end
    self._buf[self._at] = 0
    self._at = self._at + 1
    return self
end

function Writer:raw(...)
    local n = select("#", ...)
    self:_ensure(n)
    for i = 1, n do
        self._buf[self._at] = bit.band(select(i, ...), 0xFF)
        self._at = self._at + 1
    end
    return self
end

function Writer:entid(entity)
    if not entity or (entity.hash or 0) == 0 then
        return self:u8(0)
    end
    return self:vu(entity.hash):vu(entity.id)
end

function Writer:write()
    return ffi.string(self._buf, self._at)
end

return Writer
