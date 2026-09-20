local bit = require("bit")
local Enums = require("src.protocol.enums")

local Render = {}
Render._scale = 1
Render._camX = 0
Render._camY = 0
Render._fov = 0.35
Render._style = "new"
Render._innerShadow = 0.15

function Render.setStyle(style)
    if style == "old" then
        Render._style = "old"
    elseif style == "shaded" then
        Render._style = "shaded"
    else
        Render._style = "new"
    end
end

function Render.setInnerShadow(coverage)
    coverage = tonumber(coverage) or 0.15
    if coverage ~= coverage then coverage = 0.15 end
    if coverage < 0 then coverage = 0 end
    if coverage > 1 then coverage = 1 end
    Render._innerShadow = coverage
end

local StyleFlags = Enums.StyleFlags
local PhysicsFlags = Enums.PhysicsFlags
local PositionFlags = Enums.PositionFlags
local HealthFlags = Enums.HealthFlags
local NameFlags = Enums.NameFlags
local CameraFlags = Enums.CameraFlags

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

function Render.safeText(s)
    if s == nil then return "" end
    if type(s) ~= "string" then s = tostring(s) end
    local n = #s
    if n == 0 then return s end
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

local function localPos(e)
    local pos = e.position
    return (e.ix or (pos and pos.x) or 0),
        (e.iy or (pos and pos.y) or 0),
        (e.ia or (pos and pos.angle) or 0),
        (pos and pos.flags) or 0
end

function Render.view(world)
    local cam = world:cameraValues()
    local fov = (cam and cam.FOV) or 0.35
    if fov <= 0.01 then fov = 0.35 end
    local flags = (cam and cam.flags) or 0
    local player = world:player()
    if player and player.position then
        -- Follow the tank unless the server is explicitly driving the camera (e.g. predator zoom).
        if bit.band(flags, CameraFlags.usesCameraCoords) == 0 then
            world:ensureWorld(player)
            return player.worldX or 0, player.worldY or 0, fov
        end
    end
    return (cam and cam.cameraX) or 0, (cam and cam.cameraY) or 0, fov
end

local function applyCamera(camX, camY, fov)
    local sw, sh = love.graphics.getDimensions()
    local viewW = 1920 / fov
    local viewH = 1080 / fov
    local scale = math.min(sw / viewW, sh / viewH)
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-camX, -camY)
    return scale, viewW, viewH
end

local function pixel()
    return 1 / math.max(Render._scale or 1, 0.0001)
end

local function drawGrid(camX, camY, viewW, viewH)
    local cell = 50
    local padX, padY = viewW * 0.6, viewH * 0.6
    local x0 = math.floor((camX - padX) / cell) * cell
    local y0 = math.floor((camY - padY) / cell) * cell
    love.graphics.setColor(hex(0xC4C4C4))
    love.graphics.setLineWidth(pixel())
    love.graphics.setLineStyle("rough")
    for x = x0, camX + padX, cell do
        love.graphics.line(x, camY - padY, x, camY + padY)
    end
    for y = y0, camY + padY, cell do
        love.graphics.line(camX - padX, y, camX + padX, y)
    end
    love.graphics.setLineStyle("smooth")
end

local function drawArenaFloor(arena)
    if not arena then return end
    local l, t, r, b = arena.leftX, arena.topY, arena.rightX, arena.bottomY
    if not l then return end
    love.graphics.setColor(hex(0xB0B0B0))
    love.graphics.rectangle("fill", l - 8000, t - 8000, (r - l) + 16000, (b - t) + 16000)
    love.graphics.setColor(hex(0xCDCDCD))
    love.graphics.rectangle("fill", l, t, r - l, b - t)
end

local function drawArenaBorder(arena)
    if not arena then return end
    local l, t, r, b = arena.leftX, arena.topY, arena.rightX, arena.bottomY
    if not l then return end
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setColor(hex(0x555555, 0.9))
    love.graphics.setLineWidth(math.max(6, 8 * pixel()))
    love.graphics.rectangle("line", l, t, r - l, b - t)
end

local function polyRegular(sides, size, star)
    local pts = {}
    -- Triangles: vertex on +X (facing). Squares: pi/4 so they sit on a face.
    local start = (sides == 3) and 0 or ((sides % 2 == 0) and (math.pi / sides) or 0)
    if star then
        local n = sides * 2
        for i = 0, n - 1 do
            local rad = (i % 2 == 0) and size or size * 0.38
            local a = start + i * math.pi / sides
            pts[#pts + 1] = math.cos(a) * rad
            pts[#pts + 1] = math.sin(a) * rad
        end
    else
        for i = 0, sides - 1 do
            local a = start + i * 2 * math.pi / sides
            pts[#pts + 1] = math.cos(a) * size
            pts[#pts + 1] = math.sin(a) * size
        end
    end
    return pts
end

-- Chamfer each vertex so filled shapes have slightly softened corners.
local function chamferPoly(pts, radius)
    if Render._style == "old" then return pts end
    local n = #pts / 2
    if n < 3 or not radius or radius <= 0 then return pts end
    local out = {}
    for i = 1, n do
        local pi = ((i - 2) % n) + 1
        local ni = (i % n) + 1
        local px, py = pts[pi * 2 - 1], pts[pi * 2]
        local cx, cy = pts[i * 2 - 1], pts[i * 2]
        local nx, ny = pts[ni * 2 - 1], pts[ni * 2]
        local dpx, dpy = cx - px, cy - py
        local dnx, dny = nx - cx, ny - cy
        local lp = math.sqrt(dpx * dpx + dpy * dpy)
        local ln = math.sqrt(dnx * dnx + dny * dny)
        if lp < 1e-4 or ln < 1e-4 then
            out[#out + 1] = cx
            out[#out + 1] = cy
        else
            local r = math.min(radius, lp * 0.32, ln * 0.32)
            out[#out + 1] = cx - dpx / lp * r
            out[#out + 1] = cy - dpy / lp * r
            out[#out + 1] = cx + dnx / ln * r
            out[#out + 1] = cy + dny / ln * r
        end
    end
    return out
end

local function strokeHex(fill)
    if Render._style == "old" then return 0x000000 end
    return darker(fill)
end

-- Screen-space light (top-left) expressed in the current local transform.
local LIGHT_X, LIGHT_Y = -0.70710678118, -0.70710678118

local function localLight()
    local ok, x0, y0, x1, y1 = pcall(function()
        local a, b = love.graphics.transformPoint(0, 0)
        local c, d = love.graphics.transformPoint(1, 0)
        return a, b, c, d
    end)
    if not ok then return LIGHT_X, LIGHT_Y end
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if not len or len < 1e-8 then return LIGHT_X, LIGHT_Y end
    dx, dy = dx / len, dy / len
    return dx * LIGHT_X + dy * LIGHT_Y, -dy * LIGHT_X + dx * LIGHT_Y
end

-- Inset indent: a smaller copy of the same silhouette, so the shade is a rim
-- that warps around circles, corners, and barrels instead of a flat crescent.
local function paintInnerShadow(fill, opacity, drawFill, size)
    if Render._style ~= "shaded" or not size or size < 1.4 or opacity < 0.05 then
        return
    end
    local cover = Render._innerShadow or 0.15
    if cover <= 0.001 then return end
    if cover > 1 then cover = 1 end
    local inner = 1 - cover
    if inner < 0.02 then inner = 0.02 end
    local lx, ly = localLight()
    local shift = size * cover * 0.45
    love.graphics.stencil(drawFill, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(0, 0, 0, opacity * 0.32)
    drawFill()
    love.graphics.setColor(hex(fill, opacity))
    love.graphics.push()
    love.graphics.translate(lx * shift, ly * shift)
    love.graphics.scale(inner, inner)
    drawFill()
    love.graphics.pop()
    love.graphics.setStencilTest()
end

local function fillStroke(fill, border, opacity, stroke, drawFill, drawStroke, shadeSize)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin(Render._style == "old" and "miter" or "bevel")
    love.graphics.setColor(hex(fill, opacity))
    drawFill()
    paintInnerShadow(fill, opacity, drawFill, shadeSize)
    love.graphics.setColor(hex(border, opacity))
    love.graphics.setLineWidth(stroke)
    drawStroke()
end

-- Scale polygon vertices toward the origin so the stroke sits on the silhouette
-- instead of letting fill tips poke past a beveled outline.
local function insetPts(pts, amount, maxR)
    if not pts or #pts < 6 or amount <= 0 or not maxR or maxR <= amount then
        return pts
    end
    local s = (maxR - amount) / maxR
    local out = {}
    for i = 1, #pts do
        out[i] = pts[i] * s
    end
    return out
end

-- Fan from the origin so concave stars (traps) fill only the star, not the hull.
local function fillCenteredPoly(pts)
    local n = #pts / 2
    if n < 3 then return end
    for i = 1, n do
        local j = (i % n) + 1
        love.graphics.polygon("fill",
            0, 0,
            pts[i * 2 - 1], pts[i * 2],
            pts[j * 2 - 1], pts[j * 2])
    end
end

local function strokePoly(pts)
    if #pts >= 6 then
        love.graphics.polygon("line", pts)
    end
end

-- Keep the barrel base on the tank; returns (lengthScale, muzzleShiftX).
local function shootRecoil(e)
    if not e.barrel then return 1, 0 end
    local t = e._shootAnim
    if t == nil then t = 1 end
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local rec = 0.82 + 0.18 * (t * t * (3 - 2 * t))
    local hl = ((e.physics and e.physics.size) or 0) / 2
    return rec, 2 * hl * (rec - 1)
end

local function drawBody(e, opacity, hit)
    local phy = e.physics
    local sty = e.style
    if not phy or not sty then return end
    if not flagged(sty, StyleFlags.isVisible) then return end
    if opacity <= 0.02 then return end
    local size = phy.size or 0
    if size <= 0 then return end
    local sides = phy.sides or 0
    if sides < 1 then return end
    local fill = applyHit(colorOf(e), hit)
    local border = applyHit(strokeHex(colorOf(e)), hit)
    local trap = bit.band(phy.flags or 0, PhysicsFlags.isTrapezoid) ~= 0
    local stroke = math.max(pixel() * 2.5, math.min((sty.borderWidth or 7.5) * 0.78, size * 0.2))

    if sides == 1 then
        -- Keep the outline inside physics.size so the fill doesn't balloon past barrels.
        local r = math.max(size - stroke * 0.5, size * 0.72)
        fillStroke(fill, border, opacity, stroke, function()
            love.graphics.circle("fill", 0, 0, r)
        end, function()
            love.graphics.circle("line", 0, 0, r)
        end, r)
    elseif sides == 2 then
        local w = phy.width or size
        local hl, hw = size / 2, w / 2
        local tip = 1
        if trap then
            local dir = (e.barrel and e.barrel.trapezoidDirection) or 0
            tip = 1 + 0.5 * math.cos(dir)
            if tip < 0.2 then tip = 0.2 end
        end
        local rec = shootRecoil(e)
        local inner = -hl
        local outer = inner + (2 * hl) * rec
        local pts = chamferPoly({
            inner, -hw,
            outer, -hw * tip,
            outer, hw * tip,
            inner, hw
        }, math.min(hl, hw) * 0.18)
        fillStroke(fill, border, opacity, stroke, function()
            if #pts >= 6 then love.graphics.polygon("fill", pts) end
        end, function()
            strokePoly(pts)
        end, math.min(hl, hw))
    else
        local star = flagged(sty, StyleFlags.isStar)
        -- Protocol size is the collision incircle. Diep draws polygons out to
        -- the vertices at size * sqrt(2).
        local rad = size * math.sqrt(2)
        local pts = polyRegular(sides, rad, star)
        if star then
            pts = chamferPoly(pts, rad * 0.06)
        else
            pts = chamferPoly(pts, rad * (sides == 3 and 0.045 or (sides <= 4 and 0.11 or 0.08)))
        end
        if Render._style ~= "old" then
            pts = insetPts(pts, stroke * 0.5, rad)
        end
        if #pts >= 6 then
            fillStroke(fill, border, opacity, stroke, function()
                fillCenteredPoly(pts)
            end, function()
                strokePoly(pts)
            end, size)
        end
    end
end

local function drawHealth(e, opacity)
    if opacity <= 0.12 then return end
    if e.barrel then return end
    local h = e.health
    local phy = e.physics
    if not h or not phy then return end
    if bit.band(h.flags or 0, HealthFlags.hiddenHealthbar) ~= 0 then return end
    if (phy.sides or 0) == 2 then return end
    local maxH = e.imh or h.maxHealth or 1
    if maxH <= 0 then return end
    local hp = e.ih or h.health or 0
    local ratio = math.max(0, math.min(1, hp / maxH))
    local lag = e._hpLag or ratio
    if lag < ratio then lag = ratio end
    if ratio >= 0.995 and lag >= 0.995 then return end
    local size = phy.size or 20
    local px = math.max(Render._scale or 1, 0.0001)
    love.graphics.push()
    love.graphics.scale(1 / px, 1 / px)
    local barW = math.max(52, size * px * 1.55)
    local y = size * px + 8
    local bx, by, bw, bh = -barW / 2, y, barW, 8
    love.graphics.setColor(0.12, 0.12, 0.12, 0.7 * opacity)
    love.graphics.rectangle("fill", bx, by, bw, bh, 2, 2)
    love.graphics.stencil(function()
        love.graphics.rectangle("fill", bx, by, bw, bh, 2, 2)
    end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    if lag > ratio + 0.008 then
        love.graphics.setColor(0.945, 0.306, 0.329, 0.92 * opacity)
        Render.drawWaveFill(bx, by, bw, bh, lag)
    end
    love.graphics.setColor(0.45, 0.92, 0.45, 0.95 * opacity)
    Render.drawWaveFill(bx, by, bw, bh, ratio)
    love.graphics.setStencilTest()
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.05, 0.05, 0.05, 0.95 * opacity)
    love.graphics.rectangle("line", bx, by, bw, bh, 2, 2)
    love.graphics.pop()
end

local function drawName(e, opacity)
    if Render._selfEntity and e == Render._selfEntity then return end
    if opacity <= 0.12 then return end
    if e.barrel then return end
    local n = e.name
    if not n or not n.name or n.name == "" then return end
    if bit.band(n.flags or 0, NameFlags.hiddenName) ~= 0 then return end
    local phy = e.physics
    if not phy then return end
    local highlight = bit.band(n.flags or 0, NameFlags.highlightedName) ~= 0
    local px = math.max(Render._scale or 1, 0.0001)
    local label = Render.safeText(n.name)
    if label == "" then return end
    love.graphics.push()
    love.graphics.scale(1 / px, 1 / px)
    local y = -(phy.size or 20) * px - 28
    if highlight then
        love.graphics.setColor(1, 0.85, 0.2, opacity)
    else
        love.graphics.setColor(1, 1, 1, opacity)
    end
    Render.outlinedPrintf(label, -200, y, 400, "center", 2)
    love.graphics.pop()
end

local function childSort(a, b)
    local af = flagged(a.style, StyleFlags.renderFirst) and 0 or 1
    local bf = flagged(b.style, StyleFlags.renderFirst) and 0 or 1
    if af ~= bf then return af < bf end
    local az = (a.style and a.style.zIndex) or 0
    local bz = (b.style and b.style.zIndex) or 0
    return az < bz
end

local function splitChildren(e)
    local below, above = {}, {}
    for i = 1, #(e.children or {}) do
        local c = e.children[i]
        if flagged(c.style, StyleFlags.showsAboveParent) then
            above[#above + 1] = c
        else
            below[#below + 1] = c
        end
    end
    table.sort(below, childSort)
    table.sort(above, childSort)
    return below, above
end

local drawNode

drawNode = function(e, parentAngle, parentOpacity, parentFlash, parentHit)
    if e.camera or e.arena then return end
    if not e.physics and #(e.children or {}) == 0 then return end
    local lx, ly, la, flags = localPos(e)
    local abs = bit.band(flags, PositionFlags.absoluteRotation) ~= 0
    local worldAngle = abs and la or (parentAngle + la)
    local opacity = parentOpacity * ((e.style and e.style.opacity) or 1)
    local flash = parentFlash or flagged(e.style, StyleFlags.isFlashing)
    local hit = parentHit or 0
    if (e._hitFlash or 0) > hit then hit = e._hitFlash end
    local drawOp = opacity
    if flash and (love.timer.getTime() % 0.16 < 0.08) then
        drawOp = opacity * 0.4
    end

    love.graphics.push()
    love.graphics.translate(lx, ly)
    local rot = abs and (la - parentAngle) or la
    love.graphics.push()
    love.graphics.rotate(rot)
    local _, recoilX = shootRecoil(e)
    local below, above = splitChildren(e)
    local function drawKids(list)
        if recoilX ~= 0 then
            love.graphics.push()
            love.graphics.translate(recoilX, 0)
        end
        for i = 1, #list do
            drawNode(list[i], worldAngle, opacity, flash, hit)
        end
        if recoilX ~= 0 then
            love.graphics.pop()
        end
    end
    drawKids(below)
    if e.physics then
        drawBody(e, drawOp, hit)
    end
    drawKids(above)
    love.graphics.pop()
    if e.physics and flagged(e.style, StyleFlags.isVisible) then
        drawHealth(e, drawOp)
        drawName(e, drawOp)
    end
    love.graphics.pop()
end

function Render.draw(world)
    local camX, camY, fov = Render.view(world)
    Render._camX, Render._camY, Render._fov = camX, camY, fov
    love.graphics.clear(hex(0xCDCDCD))
    love.graphics.push()
    local scale, viewW, viewH = applyCamera(camX, camY, fov)
    Render._scale = scale
    Render._selfEntity = world:player()
    local arena = world:arenaValues()
    drawArenaFloor(arena)
    drawGrid(camX, camY, viewW, viewH)
    drawArenaBorder(arena)

    local roots = {}
    for _, e in pairs(world.entities) do
        if e.physics and not e.parentEntity and not e.camera and not e.arena and not e.barrel then
            roots[#roots + 1] = e
        end
    end
    table.sort(roots, childSort)
    for i = 1, #roots do
        drawNode(roots[i], 0, 1, false, 0)
    end
    love.graphics.pop()
    return camX, camY, fov
end

local SQRT1_2 = math.sqrt(0.5)
local SQRT2 = math.sqrt(2)

local function iconPoly(sides, rad, stroke, fill, alpha)
    local pts = polyRegular(sides, rad, false)
    pts = chamferPoly(pts, rad * (sides == 3 and 0.045 or (sides <= 4 and 0.11 or 0.08)))
    if Render._style ~= "old" then
        pts = insetPts(pts, stroke * 0.5, rad)
    end
    if #pts < 6 then return end
    fillStroke(fill, strokeHex(fill), alpha, stroke, function()
        fillCenteredPoly(pts)
    end, function()
        strokePoly(pts)
    end, rad * 0.72)
end

local function iconCircle(r, stroke, fill, alpha)
    local cr = r - stroke * 0.5
    if cr < r * 0.72 then cr = r * 0.72 end
    fillStroke(fill, strokeHex(fill), alpha, stroke, function()
        love.graphics.circle("fill", 0, 0, cr)
    end, function()
        love.graphics.circle("line", 0, 0, cr)
    end, cr)
end

local function iconBarrel(size, width, ang, off, trap, trapDir, stroke, fill, alpha)
    local hw = width / 2
    local tip = 1
    if trap then
        tip = 1 + 0.5 * math.cos(trapDir or 0)
        if tip < 0.2 then tip = 0.2 end
    end
    local pts = chamferPoly({
        0, off - hw,
        size, off - hw * tip,
        size, off + hw * tip,
        0, off + hw
    }, math.min(size, hw) * 0.16)
    love.graphics.push()
    love.graphics.rotate(ang)
    fillStroke(fill, strokeHex(fill), alpha, stroke, function()
        if #pts >= 6 then love.graphics.polygon("fill", pts) end
    end, function()
        if #pts >= 6 then love.graphics.polygon("line", pts) end
    end, math.min(size, hw))
    love.graphics.pop()
end

local function iconGuard(sides, sizeRatio, offsetAngle, bodyR, stroke, alpha)
    -- GuardObject multiplies sizeRatio by SQRT1_2; world polygons draw at size * sqrt(2).
    local rad = bodyR * sizeRatio * SQRT1_2 * SQRT2
    love.graphics.push()
    love.graphics.rotate(offsetAngle or 0)
    iconPoly(sides, rad, stroke, 0x555555, alpha)
    love.graphics.pop()
end

local function iconTurret(x, y, ang, stroke, alpha)
    local barrelFill = 0x999999
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(ang or 0)
    iconBarrel(55, 42 * 0.7, 0, 0, false, 0, stroke, barrelFill, alpha)
    iconCircle(25, stroke, barrelFill, alpha)
    love.graphics.pop()
end

local function iconAddonFit(id, bodyR)
    if not id then return 0 end
    if id == "smasher" or id == "landmine" then return bodyR * 1.15 end
    if id == "autosmasher" then return math.max(bodyR * 1.15, 80) end
    if id == "spike" or id == "spiesk" then return bodyR * 1.3 end
    if id == "weirdspike" then return bodyR * 1.5 end
    if id == "dombase" then return bodyR * 1.24 end
    if id == "autoturret" then return 80 end
    if id == "auto2" or id == "auto3" or id == "auto5" or id == "auto7" then
        return bodyR * 0.8 + 55
    end
    if id == "launcher" then return 65.5 * SQRT2 end
    if id == "pronounced" then return bodyR * 1.25 end
    if id == "dompronounced" then return bodyR * 1.45 end
    return 0
end

local function iconAddon(id, layer, bodyR, stroke, alpha)
    if not id then return end
    local barrelFill = 0x999999
    if layer == "pre" then
        if id == "dombase" then
            iconGuard(6, 1.24, 0, bodyR, stroke, alpha)
        elseif id == "launcher" then
            iconBarrel(65.5 * SQRT2 / 50 * bodyR, 33.6 / 50 * bodyR, 0, 0, true, 0, stroke, barrelFill, alpha)
        end
        return
    end
    if layer == "under" then
        if id == "smasher" or id == "autosmasher" then
            iconGuard(6, 1.15, 0, bodyR, stroke, alpha)
        elseif id == "landmine" then
            iconGuard(6, 1.15, 0, bodyR, stroke, alpha)
            iconGuard(6, 1.15, math.pi / 6, bodyR, stroke, alpha)
        elseif id == "spike" then
            iconGuard(3, 1.3, 0, bodyR, stroke, alpha)
            iconGuard(3, 1.3, math.pi / 3, bodyR, stroke, alpha)
            iconGuard(3, 1.3, math.pi / 6, bodyR, stroke, alpha)
            iconGuard(3, 1.3, math.pi / 2, bodyR, stroke, alpha)
        elseif id == "weirdspike" then
            iconGuard(3, 1.5, 0, bodyR, stroke, alpha)
            iconGuard(3, 1.5, math.pi / 6, bodyR, stroke, alpha)
        elseif id == "spiesk" then
            iconGuard(4, 1.3, 0, bodyR, stroke, alpha)
            iconGuard(4, 1.3, math.pi / 6, bodyR, stroke, alpha)
            iconGuard(4, 1.3, math.pi / 3, bodyR, stroke, alpha)
        elseif id == "pronounced" then
            iconBarrel(bodyR, 42 / 50 * bodyR, math.pi, 0, true, math.pi, stroke, barrelFill, alpha)
        elseif id == "dompronounced" then
            iconBarrel(22 / 50 * bodyR, 35 / 50 * bodyR, math.pi, bodyR * 0.5, true, math.pi, stroke, barrelFill, alpha)
        end
        return
    end
    if id == "autoturret" or id == "autosmasher" then
        iconTurret(0, 0, 0, stroke, alpha)
    elseif id == "auto2" or id == "auto3" or id == "auto5" or id == "auto7" then
        local n = tonumber(id:sub(5)) or 3
        for i = 0, n - 1 do
            local ang = i * math.pi * 2 / n
            iconTurret(math.cos(ang) * bodyR * 0.8, math.sin(ang) * bodyR * 0.8, ang, stroke, alpha)
        end
    end
end

function Render.drawTankIcon(def, cx, cy, box, alpha)
    if not def or box <= 4 then return end
    alpha = alpha or 1
    local bodyR = 50
    local maxR = bodyR
    local barrels = def.barrels or {}
    for i = 1, #barrels do
        local b = barrels[i]
        if type(b) == "table" then
            local reach = (tonumber(b.size) or 0) + math.abs(tonumber(b.offset) or 0)
            if reach > maxR then maxR = reach end
        end
    end
    local pre = def.preAddon
    local post = def.postAddon
    maxR = math.max(maxR, iconAddonFit(pre, bodyR), iconAddonFit(post, bodyR))
    local s = (box * 0.40) / math.max(maxR, 1)
    local fill = 0x00B2E1
    local barrelFill = 0x999999
    local stroke = math.max(2.2 / s, bodyR * 0.08)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(s, s)
    iconAddon(pre, "pre", bodyR, stroke, alpha)
    iconAddon(post, "under", bodyR, stroke, alpha)
    for i = 1, #barrels do
        local b = barrels[i]
        if type(b) == "table" then
            iconBarrel(
                tonumber(b.size) or 0,
                tonumber(b.width) or 42,
                tonumber(b.angle) or 0,
                tonumber(b.offset) or 0,
                b.isTrapezoid,
                tonumber(b.trapezoidDirection) or 0,
                stroke, barrelFill, alpha
            )
        end
    end
    local sides = tonumber(def.sides) or 1
    if sides <= 1 then
        iconCircle(bodyR, stroke, fill, alpha)
    else
        iconPoly(sides, bodyR * SQRT2, stroke, fill, alpha)
    end
    iconAddon(post, "over", bodyR, stroke, alpha)
    love.graphics.pop()
end

Render.hex = hex
Render.colorOf = colorOf

return Render
