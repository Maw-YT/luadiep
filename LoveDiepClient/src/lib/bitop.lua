-- LuaJIT-compatible bit operations for the web build, which is PUC Lua.
-- Results are signed 32-bit integers, and shift counts use the low 5 bits.

local bit = {}

local TWO32 = 4294967296
local TWO31 = 2147483648

local function tobit(x)
    x = tonumber(x) or 0
    if x ~= x or x == math.huge or x == -math.huge then
        return 0
    end
    -- LuaJIT bit converts with round-to-nearest (the 2^52 + 2^51 trick).
    if x > -2251799813685248 and x < 2251799813685248 then
        x = (x + 6755399441055744.0) - 6755399441055744.0
    elseif x >= 0 then
        x = math.floor(x + 0.5)
    else
        x = math.ceil(x - 0.5)
    end
    x = x % TWO32
    if x < 0 then
        x = x + TWO32
    end
    if x >= TWO31 then
        x = x - TWO32
    end
    return x
end

local function u32(x)
    x = tobit(x)
    if x < 0 then
        return x + TWO32
    end
    return x
end

local function shiftCount(n)
    return u32(n) % 32
end

local function combine(a, b, pick)
    local ua, ub = u32(a), u32(b)
    local result, place = 0, 1
    for _ = 1, 32 do
        local ba, bb = ua % 2, ub % 2
        if pick(ba == 1, bb == 1) then
            result = result + place
        end
        ua = math.floor(ua / 2)
        ub = math.floor(ub / 2)
        place = place * 2
    end
    return tobit(result)
end

local function varop(binary, a, ...)
    local n = select("#", ...)
    local r = a
    for i = 1, n do
        r = binary(r, select(i, ...))
    end
    return tobit(r)
end

function bit.tobit(x)
    return tobit(x)
end

function bit.band(a, ...)
    return varop(function(x, y)
        return combine(x, y, function(p, q) return p and q end)
    end, a, ...)
end

function bit.bor(a, ...)
    return varop(function(x, y)
        return combine(x, y, function(p, q) return p or q end)
    end, a, ...)
end

function bit.bxor(a, ...)
    return varop(function(x, y)
        return combine(x, y, function(p, q) return p ~= q end)
    end, a, ...)
end

function bit.bnot(x)
    return tobit(TWO32 - 1 - u32(x))
end

function bit.lshift(x, n)
    n = shiftCount(n)
    if n == 0 then
        return tobit(x)
    end
    local u = u32(x)
    while n > 0 do
        local step = n > 16 and 16 or n
        u = (u * (2 ^ step)) % TWO32
        n = n - step
    end
    return tobit(u)
end

function bit.rshift(x, n)
    n = shiftCount(n)
    if n == 0 then
        return tobit(x)
    end
    return tobit(math.floor(u32(x) / (2 ^ n)))
end

function bit.arshift(x, n)
    n = shiftCount(n)
    local s = tobit(x)
    if s >= 0 or n == 0 then
        return bit.rshift(s, n)
    end
    local shifted = math.floor(u32(s) / (2 ^ n))
    local fill = TWO32 - (2 ^ (32 - n))
    return tobit(shifted + fill)
end

function bit.rol(x, n)
    n = shiftCount(n)
    if n == 0 then
        return tobit(x)
    end
    return bit.bor(bit.lshift(x, n), bit.rshift(x, 32 - n))
end

function bit.ror(x, n)
    n = shiftCount(n)
    if n == 0 then
        return tobit(x)
    end
    return bit.bor(bit.rshift(x, n), bit.lshift(x, 32 - n))
end

function bit.tohex(x, n)
    n = tonumber(n) or 8
    local upper = n < 0
    n = math.floor(math.abs(n))
    if n < 1 then n = 1 end
    if n > 8 then n = 8 end
    local hex = upper and "0123456789ABCDEF" or "0123456789abcdef"
    local u = u32(x)
    local chars = {}
    for i = n, 1, -1 do
        local d = u % 16
        chars[i] = hex:sub(d + 1, d + 1)
        u = math.floor(u / 16)
    end
    return table.concat(chars)
end

return bit
