return function(Render)
function Render.safeText(s)
    if s == nil then return "" end
    if type(s) ~= "string" then s = tostring(s) end
    local n = #s
    if n == 0 then return s end
    if not s:find("%c") then
        return s
    end
    local out, o = {}, 0
    local i = 1
    while i <= n do
        local c = s:byte(i)
        if not c or c == 0 then
            break
        elseif c < 32 then
            i = i + 1
        elseif c < 128 then
            o = o + 1
            out[o] = string.char(c)
            i = i + 1
        elseif c >= 194 and c <= 223 and i + 1 <= n then
            local c2 = s:byte(i + 1)
            if c2 and c2 >= 128 and c2 <= 191 then
                o = o + 1
                out[o] = s:sub(i, i + 1)
                i = i + 2
            else
                i = i + 1
            end
        elseif c >= 224 and c <= 239 and i + 2 <= n then
            local c2, c3 = s:byte(i + 1), s:byte(i + 2)
            if c2 and c3 and c2 >= 128 and c2 <= 191 and c3 >= 128 and c3 <= 191
                and not (c == 224 and c2 < 160) and not (c == 237 and c2 >= 160) then
                o = o + 1
                out[o] = s:sub(i, i + 2)
                i = i + 3
            else
                i = i + 1
            end
        elseif c >= 240 and c <= 244 and i + 3 <= n then
            local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if c2 and c3 and c4 and c2 >= 128 and c2 <= 191 and c3 >= 128 and c3 <= 191 and c4 >= 128 and c4 <= 191
                and not (c == 240 and c2 < 144) and not (c == 244 and c2 >= 144) then
                o = o + 1
                out[o] = s:sub(i, i + 3)
                i = i + 4
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return table.concat(out)
end

local function outlineOffsets(width)
    width = math.max(1, math.floor((width or 2) + 0.5))
    local pts, n = {}, 0
    local max2 = width * width + width
    for ox = -width, width do
        for oy = -width, width do
            if (ox ~= 0 or oy ~= 0) and ox * ox + oy * oy <= max2 then
                n = n + 1
                pts[n] = { ox, oy }
            end
        end
    end
    return pts
end

local outlineCache = {}
local function outlinePts(width)
    width = math.max(1, math.floor((width or 2) + 0.5))
    local cached = outlineCache[width]
    if cached then return cached end
    cached = outlineOffsets(width)
    outlineCache[width] = cached
    return cached
end

local fontCache = {}
local function fontAt(size)
    size = math.max(8, math.floor(size + 0.5))
    local f = fontCache[size]
    if f then return f end
    f = love.graphics.newFont(size)
    fontCache[size] = f
    return f
end

local function currentScale()
    local ok, x1, y1, x2, y2 = pcall(function()
        local a, b = love.graphics.transformPoint(0, 0)
        local c, d = love.graphics.transformPoint(1, 0)
        return a, b, c, d
    end)
    if not ok then return 1 end
    local dx, dy = x2 - x1, y2 - y1
    local s = math.sqrt(dx * dx + dy * dy)
    if s ~= s or s < 1e-4 then return 1 end
    return s
end

local function crisp(baseSize, draw)
    local s = currentScale()
    local prev = love.graphics.getFont()
    love.graphics.setFont(fontAt((baseSize or 16) * s))
    love.graphics.push()
    love.graphics.scale(1 / s, 1 / s)
    draw(s)
    love.graphics.pop()
    if prev then
        love.graphics.setFont(prev)
    end
end

function Render.print(text, x, y)
    text = Render.safeText(text)
    if text == "" then return end
    crisp(16, function(s)
        love.graphics.print(text, x * s, y * s)
    end)
end

function Render.printf(text, x, y, limit, align)
    text = Render.safeText(text)
    if text == "" then return end
    crisp(16, function(s)
        love.graphics.printf(text, x * s, y * s, limit * s, align)
    end)
end

function Render.outlinedPrintf(text, x, y, limit, align, width)
    text = Render.safeText(text)
    if text == "" then return end
    local r, g, b, a = love.graphics.getColor()
    crisp(16, function(s)
        local ox, oy, lim = x * s, y * s, limit * s
        local w = math.max(1, math.min(8, math.floor((width or 2) * s + 0.5)))
        local pts = outlinePts(w)
        love.graphics.setColor(0, 0, 0, a)
        for i = 1, #pts do
            love.graphics.printf(text, ox + pts[i][1], oy + pts[i][2], lim, align)
        end
        love.graphics.setColor(r, g, b, a)
        love.graphics.printf(text, ox, oy, lim, align)
    end)
end

function Render.outlinedPrint(text, x, y, width)
    text = Render.safeText(text)
    if text == "" then return end
    local r, g, b, a = love.graphics.getColor()
    crisp(16, function(s)
        local ox, oy = x * s, y * s
        local w = math.max(1, math.min(8, math.floor((width or 2) * s + 0.5)))
        local pts = outlinePts(w)
        love.graphics.setColor(0, 0, 0, a)
        for i = 1, #pts do
            love.graphics.print(text, ox + pts[i][1], oy + pts[i][2])
        end
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(text, ox, oy)
    end)
end

-- Horizontal bar fill whose leading edge is a cosine that travels up/down.
function Render.drawWaveFill(x, y, w, h, ratio)
    ratio = tonumber(ratio) or 0
    if ratio ~= ratio or ratio <= 0 or w < 0.4 or h < 0.4 then
        return
    end
    if ratio > 1 then ratio = 1 end
    local fillW = w * ratio
    if fillW < 0.4 then return end
    local time = love.timer.getTime() or 0
    local seed = x * 0.017 + y * 0.029 + w * 0.011 + h * 0.007
    local t = time * (4.4 + 1.35 * math.sin(seed * 1.8))
    local amp = h * 0.30
    if amp > 7 then amp = 7 end
    if amp < 1.6 then amp = math.min(1.6, h * 0.42) end
    amp = amp * (0.78 + 0.22 * math.cos(time * 0.37 + seed * 2.1))
    local steps = math.max(10, math.min(32, math.floor(h * 1.25 + 0.5)))
    local left, right = x, x + w
    local twoPi = math.pi * 2
    local function edge(u)
        local ripple =
            0.52 * math.cos(u * twoPi + t + seed)
            + 0.27 * math.cos(u * twoPi * 2.17 + t * 1.43 + seed * 1.9)
            + 0.14 * math.cos(u * twoPi * 3.61 - t * 0.81 + seed * 2.6)
            + 0.10 * math.cos(u * twoPi * 5.07 + t * 2.11 + seed * 0.7)
        return left + fillW + ripple * amp
    end
    for i = 0, steps - 1 do
        local u0 = i / steps
        local u1 = (i + 1) / steps
        local y0 = y + h * u0
        local y1 = y + h * u1
        local x0 = edge(u0)
        local x1 = edge(u1)
        if x0 < left then x0 = left end
        if x1 < left then x1 = left end
        if x0 > right then x0 = right end
        if x1 > right then x1 = right end
        love.graphics.polygon("fill", left, y0, x0, y0, x1, y1, left, y1)
    end
end
end
