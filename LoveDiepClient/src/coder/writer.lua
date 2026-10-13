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

local CHUNK = 2048

local function f32(val)
    if conv then
        conv.f = val + 0.0
        return conv.b[0], conv.b[1], conv.b[2], conv.b[3], conv.i
    end
    local packed = love.data.pack("string", "<f", val + 0.0)
    local b0, b1, b2, b3 = packed:byte(1, 4)
    local u = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
    if u >= 2147483648 then
        u = u - 4294967296
    end
    return b0, b1, b2, b3, u
end

local Writer = class()

function Writer:init()
    self._at = 0
    if ffi then
        self._cap = CHUNK
        self._buf = ffi.new("uint8_t[?]", self._cap)
    else
        self._bytes = {}
    end
end

function Writer:_ensure(n)
    if not ffi then return end
    if self._at + n + 8 <= self._cap then return end
    local newCap = self._cap + CHUNK
    while self._at + n + 8 > newCap do
        newCap = newCap + CHUNK
    end
    local newBuf = ffi.new("uint8_t[?]", newCap)
    ffi.copy(newBuf, self._buf, self._at)
    self._buf = newBuf
    self._cap = newCap
end

function Writer:_put(val)
    val = bit.band(val, 0xFF)
    if ffi then
        self:_ensure(1)
        self._buf[self._at] = val
        self._at = self._at + 1
        return
    end
    self._at = self._at + 1
    self._bytes[self._at] = string.char(val)
end

function Writer:u8(val)
    self:_put(val)
    return self
end

function Writer:u16(val)
    val = bit.band(val, 0xFFFF)
    self:_put(val)
    self:_put(bit.rshift(val, 8))
    return self
end

function Writer:u32(val)
    val = bit.tobit(val)
    self:_put(val)
    self:_put(bit.rshift(val, 8))
    self:_put(bit.rshift(val, 16))
    self:_put(bit.rshift(val, 24))
    return self
end

function Writer:float(val)
    local b0, b1, b2, b3 = f32(val)
    self:_put(b0)
    self:_put(b1)
    self:_put(b2)
    self:_put(b3)
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
    local _, _, _, _, num = f32(val)
    local swapped = bit.bor(
        bit.lshift(bit.band(num, 0xFF), 24),
        bit.lshift(bit.band(num, 0xFF00), 8),
        bit.band(bit.rshift(num, 8), 0xFF00),
        bit.rshift(num, 24)
    )
    return self:vi(swapped)
end

function Writer:stringNT(s)
    s = s or ""
    for i = 1, #s do
        self:_put(s:byte(i))
    end
    self:_put(0)
    return self
end

function Writer:write()
    if ffi then
        return ffi.string(self._buf, self._at)
    end
    return table.concat(self._bytes, "", 1, self._at)
end

return Writer
