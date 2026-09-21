local bit = require("bit")
local Enums = require("src.protocol.enums")

return function(Render)
local function hex(c, a)
    c = tonumber(c) or 0
    if c < 0 then c = 0 end
    local r = bit.rshift(bit.band(c, 0xFF0000), 16) / 255
    local g = bit.rshift(bit.band(c, 0x00FF00), 8) / 255
    local b = bit.band(c, 0x0000FF) / 255
    return r, g, b, a or 1
end

local function darker(c, f)
    f = f or 0.62
    c = tonumber(c) or 0
    if c < 0 then c = 0 end
    local r = math.max(0, math.floor(bit.rshift(bit.band(c, 0xFF0000), 16) * f))
    local g = math.max(0, math.floor(bit.rshift(bit.band(c, 0x00FF00), 8) * f))
    local b = math.max(0, math.floor(bit.band(c, 0x0000FF) * f))
    return r * 65536 + g * 256 + b
end

local function mixHex(a, b, t)
    t = math.max(0, math.min(1, t or 0))
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    local ar = bit.rshift(bit.band(a, 0xFF0000), 16)
    local ag = bit.rshift(bit.band(a, 0x00FF00), 8)
    local ab = bit.band(a, 0x0000FF)
    local br = bit.rshift(bit.band(b, 0xFF0000), 16)
    local bg = bit.rshift(bit.band(b, 0x00FF00), 8)
    local bb = bit.band(b, 0x0000FF)
    local r = math.floor(ar + (br - ar) * t)
    local g = math.floor(ag + (bg - ag) * t)
    local bl = math.floor(ab + (bb - ab) * t)
    return r * 65536 + g * 256 + bl
end

local function rgbToHsv(r, g, b)
    local maxv = math.max(r, g, b)
    local minv = math.min(r, g, b)
    local d = maxv - minv
    local h = 0
    if d > 1e-5 then
        if maxv == r then
            h = ((g - b) / d) % 6
        elseif maxv == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
        if h < 0 then h = h + 1 end
    end
    return h, (maxv <= 0 and 0 or d / maxv), maxv
end

local function hsvToRgb(h, s, v)
    h = h % 1
    if h < 0 then h = h + 1 end
    s = math.max(0, math.min(1, s))
    v = math.max(0, math.min(1.2, v))
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

local function beamTint(fill, u, time, layer)
    local r, g, b = hex(fill)
    local h, s, v = rgbToHsv(r, g, b)
    if s < 0.18 then
        s = 0.55
        v = math.max(v, 0.7)
    end
    local wobble = math.sin(u * 13.7 + time * 7.4 + layer * 1.9) * 0.075
        + math.sin(u * 4.6 - time * 4.3 + layer) * 0.05
    h = h + wobble + layer * 0.04
    s = math.min(1, math.max(0.28, s * 0.82 + 0.22 + 0.2 * math.sin(time * 5.2 + u * 9 + layer * 2)))
    v = math.min(1.15, 0.55 + v * (0.5 + 0.42 * (0.5 + 0.5 * math.sin(time * 8.5 + u * 12 + layer))))
    return hsvToRgb(h, s, v)
end

-- hit=1 red, hit=0.5 white, hit=0 original color
local function applyHit(fill, hit)
    if not hit or hit <= 0 then return fill end
    if hit > 0.5 then
        return mixHex(0xFFFFFF, 0xF14E54, (hit - 0.5) * 2)
    end
    return mixHex(fill, 0xFFFFFF, hit / 0.5)
end

local function colorOf(e)
    local id = (e.style and e.style.color) or 0
    return Enums.ColorsHexCode[id] or 0x555555
end

local function flagged(style, flag)
    return style and bit.band(style.flags or 0, flag) ~= 0
end

Render.hex = hex
Render.darker = darker
Render.mixHex = mixHex
Render.rgbToHsv = rgbToHsv
Render.hsvToRgb = hsvToRgb
Render.beamTint = beamTint
Render.applyHit = applyHit
Render.colorOf = colorOf
Render.flagged = flagged
end
