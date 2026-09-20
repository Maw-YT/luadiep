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

local function depthAmt()
    local c = Render._innerShadow or 0.15
    if c ~= c or c < 0 then c = 0 elseif c > 1 then c = 1 end
    return c
end

local function prismHeight(size)
    size = tonumber(size) or 0
    if size < 0 then size = 0 end
    return size * (0.88 + 0.70 * depthAmt())
end

-- Full unit sphere. phi=0 is the +Z pole (toward the light).
local SPHERE_SLICES, SPHERE_STACKS = 16, 10
local sphereLat = {}
for st = 0, SPHERE_STACKS do
    local phi = st / SPHERE_STACKS * math.pi
    local sp, cp = math.sin(phi), math.cos(phi)
    local ring = {}
    for i = 0, SPHERE_SLICES do
        local th = i / SPHERE_SLICES * math.pi * 2
        ring[i] = { sp * math.cos(th), sp * math.sin(th), cp }
    end
    sphereLat[st] = ring
end

-- Circumference samples: {ny, nz} with theta=0 on +Z.
local CYL_SEGS = 20
local cylRing = {}
for i = 0, CYL_SEGS do
    local t = i / CYL_SEGS * math.pi * 2
    cylRing[i] = { math.sin(t), math.cos(t) }
end
local cylOrder = {}
for i = 0, CYL_SEGS - 1 do
    cylOrder[#cylOrder + 1] = i
end
table.sort(cylOrder, function(a, b)
    return (cylRing[a][2] + cylRing[a + 1][2]) < (cylRing[b][2] + cylRing[b + 1][2])
end)

-- One camera: above the 2D view, looking straight down -Z. Projection, depth,
-- facing, and lighting all use this position instead of separate hacks.
local _angC, _angS = 1, 0
local _ox, _oy, _oz = 0, 0, 0
local _camX, _camY, _camZ, _focal = 0, 0, 900, 900
local _depthBias = 0
local DEPTH_FAR = 1 / 2800
local CEL_THRESH, CEL_SHADOW = 0.12, 0.82
local _lx, _ly, _lz = LIGHT_X, LIGHT_Y, 0.74
do
    local len = math.sqrt(_lx * _lx + _ly * _ly + _lz * _lz)
    _lx, _ly, _lz = _lx / len, _ly / len, _lz / len
end
local triMesh, meshVerts, meshN = nil, {}, 0
local MESH_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexColor", "byte", 4 },
    { "VertexTexCoord", "float", 2 }
}
local depthShader
do
    local src = [[
        varying float vDepth;
        varying float vNd;
        #ifdef VERTEX
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            vDepth = vertex_position.z;
            vNd = VertexTexCoord.x;
            return transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
        }
        #endif
        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            gl_FragDepth = vDepth;
            float t = 1.0;
            if (vNd < 1.5) {
                if (vNd > 0.12) {
                    t = 1.0;
                } else {
                    t = 0.82;
                }
            }
            return vec4(color.rgb * t, color.a);
        }
        #endif
    ]]
    local ok, sh = pcall(love.graphics.newShader, src)
    if ok then
        depthShader = sh
    else
        print("[LoveDiepClient] 3D depth shader: " .. tostring(sh))
    end
end

local function syncCamera3D(viewH)
    _camX = Render._camX or 0
    _camY = Render._camY or 0
    viewH = viewH or (1080 / math.max(Render._fov or 0.35, 0.05))
    _camZ = math.max(viewH * 0.72, 420)
    _focal = _camZ
end

local function begin3D(angle, ox, oy, oz)
    angle = angle or 0
    _angC, _angS = math.cos(angle), math.sin(angle)
    _ox, _oy, _oz = ox or 0, oy or 0, oz or 0
end

local function worldPoint(lx, ly, lz)
    local rx = lx * _angC - ly * _angS
    local ry = lx * _angS + ly * _angC
    return _ox + rx, _oy + ry, (lz or 0) + _oz
end

-- Direction from a world point to the camera.
local function toCam(wx, wy, wz)
    local dx = _camX - wx
    local dy = _camY - wy
    local dz = _camZ - wz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if not len or len < 1e-8 then return 0, 0, 1 end
    return dx / len, dy / len, dz / len
end

-- Perspective about the real camera. The z=0 plane keeps gameplay XY.
local function proj(lx, ly, lz)
    local wx, wy, wz = worldPoint(lx, ly, lz)
    local dz = _camZ - wz
    if dz < 12 then dz = 12 end
    local f = _focal / dz
    local sx = _camX + (wx - _camX) * f - _ox
    local sy = _camY + (wy - _camY) * f - _oy
    local depth = dz * DEPTH_FAR + _depthBias
    if depth < 0.001 then depth = 0.001 elseif depth > 0.999 then depth = 0.999 end
    return sx, sy, depth
end

-- Front face = normal points toward the camera from this point.
local function facing(nx, ny, nz, px, py, pz)
    local nwx = nx * _angC - ny * _angS
    local nwy = nx * _angS + ny * _angC
    local wx, wy, wz = worldPoint(px or 0, py or 0, pz or 0)
    local cx, cy, cz = toCam(wx, wy, wz)
    return nwx * cx + nwy * cy + nz * cz > 0.02
end

local function nrm3(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if not l or l < 1e-8 then return 0, 0, 1 end
    return x / l, y / l, z / l
end

local function litCol(fill, nx, ny, nz, opacity)
    local nwx = nx * _angC - ny * _angS
    local nwy = nx * _angS + ny * _angC
    local nd = nwx * _lx + nwy * _ly + nz * _lz
    local r, g, b = hex(fill)
    if not depthShader then
        local t = nd > CEL_THRESH and 1 or CEL_SHADOW
        return r * t, g * t, b * t, opacity, 2
    end
    return r, g, b, opacity, nd
end

local function hullCross(o, a, b)
    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end

local function convexHull(points)
    local n = #points
    if n <= 2 then return points end
    table.sort(points, function(a, b)
        if a[1] == b[1] then return a[2] < b[2] end
        return a[1] < b[1]
    end)
    local lower = {}
    for i = 1, n do
        while #lower >= 2 and hullCross(lower[#lower - 1], lower[#lower], points[i]) <= 0 do
            lower[#lower] = nil
        end
        lower[#lower + 1] = points[i]
    end
    local upper = {}
    for i = n, 1, -1 do
        while #upper >= 2 and hullCross(upper[#upper - 1], upper[#upper], points[i]) <= 0 do
            upper[#upper] = nil
        end
        upper[#upper + 1] = points[i]
    end
    lower[#lower] = nil
    upper[#upper] = nil
    for i = 1, #upper do
        lower[#lower + 1] = upper[i]
    end
    return lower
end

local function signedArea(poly)
    local n = #poly
    local a = 0
    for i = 1, n do
        local j = (i % n) + 1
        a = a + poly[i][1] * poly[j][2] - poly[j][1] * poly[i][2]
    end
    return a * 0.5
end

-- Offset a polygon by `amount` using winding so concave stars (traps) outset
-- into the notches instead of wrapping a convex hull.
local function outsetPoly(poly, amount)
    local n = #poly
    if n < 3 or amount <= 0 then return poly end
    local sign = signedArea(poly) >= 0 and 1 or -1
    local out = {}
    local maxM = amount * 3.5
    for i = 1, n do
        local prev = poly[((i - 2) % n) + 1]
        local cur = poly[i]
        local nxt = poly[(i % n) + 1]
        local e0x, e0y = cur[1] - prev[1], cur[2] - prev[2]
        local e1x, e1y = nxt[1] - cur[1], nxt[2] - cur[2]
        local l0 = math.sqrt(e0x * e0x + e0y * e0y)
        local l1 = math.sqrt(e1x * e1x + e1y * e1y)
        if l0 > 1e-8 then e0x, e0y = e0x / l0, e0y / l0 else e0x, e0y = 1, 0 end
        if l1 > 1e-8 then e1x, e1y = e1x / l1, e1y / l1 else e1x, e1y = 1, 0 end
        local n0x, n0y = sign * e0y, -sign * e0x
        local n1x, n1y = sign * e1y, -sign * e1x
        local bx, by = n0x + n1x, n0y + n1y
        local bl = math.sqrt(bx * bx + by * by)
        if bl < 1e-8 then
            out[i] = { cur[1] + n0x * amount, cur[2] + n0y * amount, cur[3] }
        else
            bx, by = bx / bl, by / bl
            local d = bx * n0x + by * n0y
            if d < 0.2 then d = 0.2 end
            local m = amount / d
            if m > maxM then m = maxM end
            out[i] = { cur[1] + bx * m, cur[2] + by * m, cur[3] }
        end
    end
    return out
end

local function ptsConvex(pts)
    local n = #pts / 2
    if n < 4 then return true end
    local prev = 0
    for i = 1, n do
        local pi = ((i - 2) % n) + 1
        local ni = (i % n) + 1
        local ax, ay = pts[pi * 2 - 1], pts[pi * 2]
        local bx, by = pts[i * 2 - 1], pts[i * 2]
        local cx, cy = pts[ni * 2 - 1], pts[ni * 2]
        local cr = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
        if cr * cr > 1e-10 then
            local s = cr > 0 and 1 or -1
            if prev == 0 then
                prev = s
            elseif s ~= prev then
                return false
            end
        end
    end
    return true
end

local function meshReset()
    meshN = 0
end

local function meshPush(x, y, z, r, g, b, a, nd)
    meshN = meshN + 1
    local v = meshVerts[meshN]
    nd = nd or 2
    if v then
        v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9] = x, y, z, r, g, b, a, nd, 0
    else
        meshVerts[meshN] = { x, y, z, r, g, b, a, nd, 0 }
    end
end

local function meshTri(x1, y1, z1, r1, g1, b1, a1, x2, y2, z2, r2, g2, b2, a2, x3, y3, z3, r3, g3, b3, a3, n1, n2, n3)
    meshPush(x1, y1, z1, r1, g1, b1, a1, n1)
    meshPush(x2, y2, z2, r2, g2, b2, a2, n2)
    meshPush(x3, y3, z3, r3, g3, b3, a3, n3)
end

local function meshFlush()
    if meshN < 3 then
        meshN = 0
        return
    end
    if not triMesh or triMesh:getVertexCount() < meshN then
        triMesh = love.graphics.newMesh(MESH_FORMAT, math.max(meshN, 1024), "triangles", "stream")
    end
    for i = 1, meshN do
        triMesh:setVertex(i, meshVerts[i])
    end
    triMesh:setDrawRange(1, meshN)
    local prev
    if depthShader then
        prev = love.graphics.getShader()
        love.graphics.setShader(depthShader)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(triMesh)
    if depthShader then
        if prev then
            love.graphics.setShader(prev)
        else
            love.graphics.setShader()
        end
    end
    meshN = 0
end

local hullPts = {}

local function hullReset()
    hullPts = {}
end

local function hullAdd(x, y, z)
    hullPts[#hullPts + 1] = { x, y, z or 0.5 }
end

local function meshLitTri(ax, ay, az, anx, any, anz,
                          bx, by, bz, bnx, bny, bnz,
                          cx, cy, cz, cnx, cny, cnz,
                          fill, opacity, specPow, wrap)
    local axp, ayp, azp = proj(ax, ay, az)
    local bxp, byp, bzp = proj(bx, by, bz)
    local cxp, cyp, czp = proj(cx, cy, cz)
    hullAdd(axp, ayp, azp)
    hullAdd(bxp, byp, bzp)
    hullAdd(cxp, cyp, czp)
    local ar, ag, ab, aa, na = litCol(fill, anx, any, anz, opacity)
    local br, bg, bb, ba, nb = litCol(fill, bnx, bny, bnz, opacity)
    local cr, cg, cb, ca, nc = litCol(fill, cnx, cny, cnz, opacity)
    meshTri(axp, ayp, azp, ar, ag, ab, aa, bxp, byp, bzp, br, bg, bb, ba, cxp, cyp, czp, cr, cg, cb, ca, na, nb, nc)
end

-- Outer silhouette ring. Depth sits at the back of this mesh so closer
-- parts (barrels, other tanks) occlude it; width is fully outside the fill.
local function strokeLoop(loop, border, opacity, stroke)
    if not loop or #loop < 3 then return end
    local w = math.max(tonumber(stroke) or 3, 0.8)
    local farZ = 0.001
    for i = 1, #loop do
        local z = loop[i][3]
        if z and z > farZ then farZ = z end
    end
    local z = math.min(0.999, farZ + 0.0002)
    local outer = outsetPoly(loop, w)
    local r, g, b, a = hex(border, opacity)
    if Render._style == "shaded" then
        love.graphics.setDepthMode("lequal", true)
    end
    meshReset()
    local n = #loop
    for i = 1, n do
        local j = (i % n) + 1
        local i0, i1 = loop[i], loop[j]
        local o0, o1 = outer[i], outer[j]
        meshTri(
            i0[1], i0[2], z, r, g, b, a,
            o0[1], o0[2], z, r, g, b, a,
            i1[1], i1[2], z, r, g, b, a)
        meshTri(
            i1[1], i1[2], z, r, g, b, a,
            o0[1], o0[2], z, r, g, b, a,
            o1[1], o1[2], z, r, g, b, a)
    end
    meshFlush()
end

local function strokeOutline(points, border, opacity, stroke)
    strokeLoop(convexHull(points), border, opacity, stroke)
end

-- 3D bevel rim around a prism. Offset lives in object XY so side walls stay
-- visible instead of getting covered by a flat top-face ring.
local function strokePrism3D(pts, z0, z1, border, opacity, stroke)
    local n = #pts / 2
    if n < 3 then return end
    local w = math.max(tonumber(stroke) or 3, 0.8)
    local px, py = {}, {}
    for i = 1, n do
        px[i] = pts[i * 2 - 1]
        py[i] = pts[i * 2]
    end
    local area = 0
    for i = 1, n do
        local j = (i % n) + 1
        area = area + px[i] * py[j] - px[j] * py[i]
    end
    local sign = area >= 0 and 1 or -1
    local nx, ny = {}, {}
    for i = 1, n do
        local j = (i % n) + 1
        local dx, dy = px[j] - px[i], py[j] - py[i]
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1e-8 then
            nx[i], ny[i] = sign * dy / len, -sign * dx / len
        else
            nx[i], ny[i] = 0, 0
        end
    end
    local r, g, b, a = hex(border, opacity)
    local function emit(ax, ay, az, bx, by, bz, cx, cy, cz)
        local apx, apy, apz = proj(ax, ay, az)
        local bpx, bpy, bpz = proj(bx, by, bz)
        local cpx, cpy, cpz = proj(cx, cy, cz)
        meshTri(
            apx, apy, apz, r, g, b, a,
            bpx, bpy, bpz, r, g, b, a,
            cpx, cpy, cpz, r, g, b, a)
    end
    if Render._style == "shaded" then
        love.graphics.setDepthMode("lequal", true)
    end
    meshReset()
    for i = 1, n do
        local j = (i % n) + 1
        if nx[i] ~= 0 or ny[i] ~= 0 then
            local x0, y0, x1, y1 = px[i], py[i], px[j], py[j]
            local ox, oy = nx[i] * w, ny[i] * w
            emit(x0, y0, z1, x0 + ox, y0 + oy, z1, x1, y1, z1)
            emit(x1, y1, z1, x0 + ox, y0 + oy, z1, x1 + ox, y1 + oy, z1)
            emit(x0, y0, z0, x1, y1, z0, x0 + ox, y0 + oy, z0)
            emit(x1, y1, z0, x1 + ox, y1 + oy, z0, x0 + ox, y0 + oy, z0)
            emit(x0 + ox, y0 + oy, z1, x0 + ox, y0 + oy, z0, x1 + ox, y1 + oy, z1)
            emit(x1 + ox, y1 + oy, z1, x0 + ox, y0 + oy, z0, x1 + ox, y1 + oy, z0)
        end
    end
    for i = 1, n do
        local prev = ((i - 2) % n) + 1
        if (nx[prev] ~= 0 or ny[prev] ~= 0) and (nx[i] ~= 0 or ny[i] ~= 0) then
            local turn = nx[prev] * ny[i] - ny[prev] * nx[i]
            if turn * sign > 1e-5 then
                local x, y = px[i], py[i]
                local ax, ay = nx[prev] * w, ny[prev] * w
                local bx, by = nx[i] * w, ny[i] * w
                emit(x, y, z1, x + ax, y + ay, z1, x + bx, y + by, z1)
                emit(x, y, z0, x + bx, y + by, z0, x + ax, y + ay, z0)
                emit(x + ax, y + ay, z1, x + ax, y + ay, z0, x + bx, y + by, z1)
                emit(x + bx, y + by, z1, x + ax, y + ay, z0, x + bx, y + by, z0)
            end
        end
    end
    meshFlush()
end

local function finishMesh(border, opacity, stroke, emit)
    hullReset()
    meshReset()
    emit()
    meshFlush()
    if stroke and stroke > 0.2 and opacity > 0.02 then
        strokeOutline(hullPts, border, opacity, stroke)
    end
end

local function drawSphere3D(radius, fill, border, opacity, stroke, angle, ox, oy, oz)
    if not radius or radius < 0.35 or opacity < 0.02 then return end
    begin3D(angle, ox, oy, oz)
    local function emit()
        for st = SPHERE_STACKS - 1, 0, -1 do
            local outer, inner = sphereLat[st + 1], sphereLat[st]
            for i = 0, SPHERE_SLICES - 1 do
                local a, b = outer[i], outer[i + 1]
                local c, d = inner[i], inner[i + 1]
                if facing(a[1], a[2], a[3], a[1] * radius, a[2] * radius, a[3] * radius)
                    or facing(c[1], c[2], c[3], c[1] * radius, c[2] * radius, c[3] * radius) then
                    if st == SPHERE_STACKS - 1 then
                        meshLitTri(
                            c[1] * radius, c[2] * radius, c[3] * radius, c[1], c[2], c[3],
                            d[1] * radius, d[2] * radius, d[3] * radius, d[1], d[2], d[3],
                            a[1] * radius, a[2] * radius, a[3] * radius, a[1], a[2], a[3],
                            fill, opacity, 22)
                    elseif st == 0 then
                        meshLitTri(
                            a[1] * radius, a[2] * radius, a[3] * radius, a[1], a[2], a[3],
                            b[1] * radius, b[2] * radius, b[3] * radius, b[1], b[2], b[3],
                            c[1] * radius, c[2] * radius, c[3] * radius, c[1], c[2], c[3],
                            fill, opacity, 22)
                    else
                        meshLitTri(
                            a[1] * radius, a[2] * radius, a[3] * radius, a[1], a[2], a[3],
                            b[1] * radius, b[2] * radius, b[3] * radius, b[1], b[2], b[3],
                            c[1] * radius, c[2] * radius, c[3] * radius, c[1], c[2], c[3],
                            fill, opacity, 22)
                        meshLitTri(
                            b[1] * radius, b[2] * radius, b[3] * radius, b[1], b[2], b[3],
                            d[1] * radius, d[2] * radius, d[3] * radius, d[1], d[2], d[3],
                            c[1] * radius, c[2] * radius, c[3] * radius, c[1], c[2], c[3],
                            fill, opacity, 22)
                    end
                end
            end
        end
    end
    finishMesh(border, opacity, stroke, emit)
end

local function drawCylinderCap(x, radius, yOff, zOff, nx, fill, opacity)
    if radius < 0.25 then return end
    zOff = zOff or 0
    for i = 0, CYL_SEGS - 1 do
        local a, b = cylRing[i], cylRing[i + 1]
        meshLitTri(
            x, yOff, zOff, nx, 0, 0,
            x, yOff + a[1] * radius, zOff + a[2] * radius, nx, 0, 0,
            x, yOff + b[1] * radius, zOff + b[2] * radius, nx, 0, 0,
            fill, opacity, 16, true)
    end
end

local function drawCylinder3D(x0, x1, r0, r1, fill, border, opacity, stroke, yOff, angle, ox, oy, zOff, oz)
    yOff = yOff or 0
    zOff = zOff or 0
    if opacity < 0.02 then return end
    r0 = math.max(0, r0 or 0)
    r1 = math.max(0, r1 or 0)
    if r0 < 0.25 and r1 < 0.25 then return end
    begin3D(angle, ox, oy, oz)
    local L = x1 - x0
    local sl = (r0 - r1) / math.max(math.abs(L), 1e-4)
    local den = math.sqrt(1 + sl * sl)
    local nxx = sl / den
    local nScale = 1 / den
    local innerN = x1 >= x0 and -1 or 1
    local function emit()
        if facing(innerN, 0, 0, x0, yOff, zOff) then
            drawCylinderCap(x0, r0, yOff, zOff, innerN, fill, opacity)
        end
        for o = 1, #cylOrder do
            local i = cylOrder[o]
            local a, b = cylRing[i], cylRing[i + 1]
            local n0y, n0z = a[1] * nScale, a[2] * nScale
            local n1y, n1z = b[1] * nScale, b[2] * nScale
            local mx = (x0 + x1) * 0.5
            local my = yOff + (a[1] + b[1]) * 0.25 * (r0 + r1)
            local mz = zOff + (a[2] + b[2]) * 0.25 * (r0 + r1)
            if facing(nxx, n0y, n0z, mx, my, mz) or facing(nxx, n1y, n1z, mx, my, mz) then
                meshLitTri(
                    x0, yOff + a[1] * r0, zOff + a[2] * r0, nxx, n0y, n0z,
                    x1, yOff + a[1] * r1, zOff + a[2] * r1, nxx, n0y, n0z,
                    x0, yOff + b[1] * r0, zOff + b[2] * r0, nxx, n1y, n1z,
                    fill, opacity, 16)
                meshLitTri(
                    x1, yOff + a[1] * r1, zOff + a[2] * r1, nxx, n0y, n0z,
                    x1, yOff + b[1] * r1, zOff + b[2] * r1, nxx, n1y, n1z,
                    x0, yOff + b[1] * r0, zOff + b[2] * r0, nxx, n1y, n1z,
                    fill, opacity, 16)
            end
        end
        if facing(-innerN, 0, 0, x1, yOff, zOff) then
            drawCylinderCap(x1, r1, yOff, zOff, -innerN, fill, opacity)
        end
    end
    finishMesh(border, opacity, stroke, emit)
end

local function drawPrism3D(pts, height, fill, border, opacity, stroke, angle, ox, oy, oz)
    if not pts or #pts < 6 or opacity < 0.02 then return end
    begin3D(angle, ox, oy, oz)
    local h = height or 0
    if h < 0 then h = 0 end
    local z0, z1 = -h * 0.5, h * 0.5
    local n = #pts / 2
    local function emit()
        if facing(0, 0, 1, 0, 0, z1) then
            for i = 1, n do
                local j = (i % n) + 1
                local x0, y0 = pts[i * 2 - 1], pts[i * 2]
                local x1, y1 = pts[j * 2 - 1], pts[j * 2]
                meshLitTri(
                    0, 0, z1, 0, 0, 1,
                    x0, y0, z1, 0, 0, 1,
                    x1, y1, z1, 0, 0, 1,
                    fill, opacity)
            end
        end
        if facing(0, 0, -1, 0, 0, z0) then
            for i = 1, n do
                local j = (i % n) + 1
                local x0, y0 = pts[i * 2 - 1], pts[i * 2]
                local x1, y1 = pts[j * 2 - 1], pts[j * 2]
                meshLitTri(
                    0, 0, z0, 0, 0, -1,
                    x1, y1, z0, 0, 0, -1,
                    x0, y0, z0, 0, 0, -1,
                    fill, opacity, nil, true)
            end
        end
        for i = 1, n do
            local j = (i % n) + 1
            local x0, y0 = pts[i * 2 - 1], pts[i * 2]
            local x1, y1 = pts[j * 2 - 1], pts[j * 2]
            local dx, dy = x1 - x0, y1 - y0
            local nx, ny = dy, -dx
            if nx * (x0 + x1) + ny * (y0 + y1) < 0 then
                nx, ny = -nx, -ny
            end
            nx, ny = nrm3(nx, ny, 0)
            if facing(nx, ny, 0, (x0 + x1) * 0.5, (y0 + y1) * 0.5, 0) then
                meshLitTri(
                    x0, y0, z1, nx, ny, 0,
                    x1, y1, z1, nx, ny, 0,
                    x0, y0, z0, nx, ny, 0,
                    fill, opacity)
                meshLitTri(
                    x1, y1, z1, nx, ny, 0,
                    x1, y1, z0, nx, ny, 0,
                    x0, y0, z0, nx, ny, 0,
                    fill, opacity)
            end
        end
    end
    if ptsConvex(pts) then
        finishMesh(border, opacity, stroke, emit)
    else
        finishMesh(border, opacity, 0, emit)
        if stroke and stroke > 0.2 and opacity > 0.02 then
            strokePrism3D(pts, z0, z1, border, opacity, stroke)
        end
    end
end

local function scalePts(pts, s)
    local out = {}
    for i = 1, #pts do
        out[i] = pts[i] * s
    end
    return out
end

-- Thin ring (saw blade) for smasher guards. Outer walls plus a hole so the
-- sphere reads through the middle.
local function drawRingPrism3D(outer, inner, height, fill, border, opacity, stroke, angle, ox, oy, oz)
    if not outer or not inner or #outer < 6 or #inner < 6 or opacity < 0.02 then return end
    begin3D(angle, ox, oy, oz)
    local h = height or 0
    if h < 0 then h = 0 end
    local z0, z1 = -h * 0.5, h * 0.5
    local n = #outer / 2
    local function emit()
        if facing(0, 0, 1, 0, 0, z1) then
            for i = 1, n do
                local j = (i % n) + 1
                local x0, y0 = outer[i * 2 - 1], outer[i * 2]
                local x1, y1 = outer[j * 2 - 1], outer[j * 2]
                local u0, v0 = inner[i * 2 - 1], inner[i * 2]
                local u1, v1 = inner[j * 2 - 1], inner[j * 2]
                meshLitTri(x0, y0, z1, 0, 0, 1, x1, y1, z1, 0, 0, 1, u0, v0, z1, 0, 0, 1, fill, opacity)
                meshLitTri(x1, y1, z1, 0, 0, 1, u1, v1, z1, 0, 0, 1, u0, v0, z1, 0, 0, 1, fill, opacity)
            end
        end
        if facing(0, 0, -1, 0, 0, z0) then
            for i = 1, n do
                local j = (i % n) + 1
                local x0, y0 = outer[i * 2 - 1], outer[i * 2]
                local x1, y1 = outer[j * 2 - 1], outer[j * 2]
                local u0, v0 = inner[i * 2 - 1], inner[i * 2]
                local u1, v1 = inner[j * 2 - 1], inner[j * 2]
                meshLitTri(x0, y0, z0, 0, 0, -1, u0, v0, z0, 0, 0, -1, x1, y1, z0, 0, 0, -1, fill, opacity, nil, true)
                meshLitTri(x1, y1, z0, 0, 0, -1, u0, v0, z0, 0, 0, -1, u1, v1, z0, 0, 0, -1, fill, opacity, nil, true)
            end
        end
        for i = 1, n do
            local j = (i % n) + 1
            local x0, y0 = outer[i * 2 - 1], outer[i * 2]
            local x1, y1 = outer[j * 2 - 1], outer[j * 2]
            local dx, dy = x1 - x0, y1 - y0
            local nx, ny = dy, -dx
            if nx * (x0 + x1) + ny * (y0 + y1) < 0 then
                nx, ny = -nx, -ny
            end
            nx, ny = nrm3(nx, ny, 0)
            if facing(nx, ny, 0, (x0 + x1) * 0.5, (y0 + y1) * 0.5, 0) then
                meshLitTri(x0, y0, z1, nx, ny, 0, x1, y1, z1, nx, ny, 0, x0, y0, z0, nx, ny, 0, fill, opacity)
                meshLitTri(x1, y1, z1, nx, ny, 0, x1, y1, z0, nx, ny, 0, x0, y0, z0, nx, ny, 0, fill, opacity)
            end
        end
        for i = 1, n do
            local j = (i % n) + 1
            local x0, y0 = inner[i * 2 - 1], inner[i * 2]
            local x1, y1 = inner[j * 2 - 1], inner[j * 2]
            local dx, dy = x1 - x0, y1 - y0
            local nx, ny = -dy, dx
            if nx * (x0 + x1) + ny * (y0 + y1) > 0 then
                nx, ny = -nx, -ny
            end
            nx, ny = nrm3(nx, ny, 0)
            if facing(nx, ny, 0, (x0 + x1) * 0.5, (y0 + y1) * 0.5, 0) then
                meshLitTri(x0, y0, z1, nx, ny, 0, x0, y0, z0, nx, ny, 0, x1, y1, z1, nx, ny, 0, fill, opacity)
                meshLitTri(x1, y1, z1, nx, ny, 0, x0, y0, z0, nx, ny, 0, x1, y1, z0, nx, ny, 0, fill, opacity)
            end
        end
    end
    finishMesh(border, opacity, stroke, emit)
end

local function isSmasherGuard(e)
    local phy = e and e.physics
    local sty = e and e.style
    if not phy or not sty then return false end
    if (phy.sides or 0) < 3 then return false end
    if flagged(sty, StyleFlags.isStar) then return false end
    if (sty.color or 0) ~= 0 then return false end
    local parent = e.parentEntity
    if not parent or not parent.physics then return false end
    return (parent.physics.sides or 0) == 1
end

local function smasherBladeHeight(size)
    size = tonumber(size) or 0
    return math.max(size * (0.16 + 0.10 * depthAmt()), 5)
end

local function smasherBladeZ(e)
    local parent = e.parentEntity
    if not parent then return 0 end
    local n, idx = 0, 1
    local kids = parent.children or {}
    for i = 1, #kids do
        local c = kids[i]
        if isSmasherGuard(c) then
            n = n + 1
            if c == e then idx = n end
        end
    end
    if n <= 1 then return 0 end
    local spacing = smasherBladeHeight((e.physics and e.physics.size) or 20) * 1.2
    return (idx - (n + 1) * 0.5) * spacing
end

local function mountedLift(e)
    local parent = e.parentEntity
    if not parent or not parent.physics then return 0 end
    local psize = parent.physics.size or 0
    local psides = parent.physics.sides or 0
    if psides == 1 then
        return math.max(psize - 4, psize * 0.72) * 0.95
    end
    if psides >= 3 then
        return prismHeight(psize) * 0.5
    end
    return psize * 0.35
end

local function fillStroke(fill, border, opacity, stroke, drawFill, drawStroke)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin(Render._style == "old" and "miter" or "bevel")
    love.graphics.setColor(hex(fill, opacity))
    drawFill()
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

-- Shot kick on a barrel, or on a trapoid / launcher parented to one.
-- flip: trapezoidDirection ≈ π, so local +X faces the tank.
local function shootRecoil(e)
    local src = e
    if not (src and src.barrel) and e then
        if e.parentEntity and e.parentEntity.barrel then
            src = e.parentEntity
        else
            local kids = e.parentEntity and e.parentEntity.children
            if kids then
                for i = 1, #kids do
                    local k = kids[i]
                    if k ~= e and k.barrel then
                        src = k
                        break
                    end
                end
            end
        end
    end
    if not (src and src.barrel) then return 1, 0, false, false end
    local t = src._shootAnim
    if t == nil then t = 1 end
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local rec = 0.82 + 0.18 * (t * t * (3 - 2 * t))
    local hl = ((src.physics and src.physics.size) or 0) / 2
    local dir = src.barrel.trapezoidDirection or 0
    return rec, 2 * hl * (rec - 1), math.cos(dir) < 0, src == e
end

local function drawBody(e, opacity, hit, worldAngle, worldX, worldY, worldZ)
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
    worldAngle = worldAngle or 0
    worldX, worldY, worldZ = worldX or 0, worldY or 0, worldZ or 0

    if sides == 1 then
        -- Keep the outline inside physics.size so the fill doesn't balloon past barrels.
        local r = math.max(size - stroke * 0.5, size * 0.72)
        if Render._style == "shaded" then
            drawSphere3D(r, fill, border, opacity, stroke, worldAngle, worldX, worldY, worldZ)
        else
            fillStroke(fill, border, opacity, stroke, function()
                love.graphics.circle("fill", 0, 0, r)
            end, function()
                love.graphics.circle("line", 0, 0, r)
            end, r)
        end
    elseif sides == 2 then
        local w = phy.width or size
        local hl, hw = size / 2, w / 2
        local tip = 1
        if trap then
            local dir = (e.barrel and e.barrel.trapezoidDirection) or 0
            tip = 1 + 0.5 * math.cos(dir)
            if tip < 0.2 then tip = 0.2 end
        end
        local rec, shift, flip, isGun = shootRecoil(e)
        local inner, outer
        if isGun then
            if flip then
                outer = hl
                inner = outer - (2 * hl) * rec
            else
                inner = -hl
                outer = inner + (2 * hl) * rec
            end
        else
            inner = -hl + shift
            outer = hl + shift
        end
        if Render._style == "shaded" then
            -- Sit on the tank midplane so the lid wins depth and the barrel
            -- comes out the sides instead of through the top.
            drawCylinder3D(inner, outer, hw, hw * tip, fill, border, opacity, stroke, 0, worldAngle, worldX, worldY, -hw * 0.35, worldZ)
        else
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
        end
    else
        local star = flagged(sty, StyleFlags.isStar)
        -- Protocol size is the collision incircle. Diep draws polygons out to
        -- the vertices at size * sqrt(2).
        local rad = size * math.sqrt(2)
        local pts = polyRegular(sides, rad, star)
        if Render._style == "shaded" then
            if star then
                pts = chamferPoly(pts, rad * 0.06)
            end
            pts = insetPts(pts, stroke * 0.5, rad)
            if #pts >= 6 then
                if isSmasherGuard(e) then
                    local bladeZ = worldZ + smasherBladeZ(e)
                    local bladeH = smasherBladeHeight(size)
                    if sides >= 6 then
                        drawRingPrism3D(pts, scalePts(pts, 0.62), bladeH, fill, border, opacity, stroke, worldAngle, worldX, worldY, bladeZ)
                    else
                        drawPrism3D(pts, bladeH, fill, border, opacity, stroke, worldAngle, worldX, worldY, bladeZ)
                    end
                else
                    drawPrism3D(pts, prismHeight(size), fill, border, opacity, stroke, worldAngle, worldX, worldY, worldZ)
                end
            end
        else
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

drawNode = function(e, parentAngle, parentOpacity, parentFlash, parentHit, parentWX, parentWY, parentWZ)
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

    if Render._style == "shaded" then
        parentWX, parentWY, parentWZ = parentWX or 0, parentWY or 0, parentWZ or 0
        local c, s = math.cos(parentAngle), math.sin(parentAngle)
        local wx = parentWX + lx * c - ly * s
        local wy = parentWY + lx * s + ly * c
        local wz = parentWZ
        if flagged(e.style, StyleFlags.showsAboveParent) then
            wz = wz + mountedLift(e)
        end
        local below, above = splitChildren(e)
        local function kids(list)
            for i = 1, #list do
                drawNode(list[i], worldAngle, opacity, flash, hit, wx, wy, wz)
            end
        end
        kids(below)
        love.graphics.push()
        love.graphics.translate(wx, wy)
        if e.physics then
            drawBody(e, drawOp, hit, worldAngle, wx, wy, wz)
        end
        if e.physics and flagged(e.style, StyleFlags.isVisible) then
            love.graphics.setDepthMode("always", false)
            drawHealth(e, drawOp)
            drawName(e, drawOp)
            love.graphics.setDepthMode("lequal", true)
        end
        love.graphics.pop()
        kids(above)
        return
    end

    love.graphics.push()
    love.graphics.translate(lx, ly)
    local rot = abs and (la - parentAngle) or la
    love.graphics.push()
    love.graphics.rotate(rot)
    local below, above = splitChildren(e)
    local function drawKids(list)
        for i = 1, #list do
            drawNode(list[i], worldAngle, opacity, flash, hit)
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
    do
        local r, g, b, a = hex(0xCDCDCD)
        if Render._style == "shaded" then
            love.graphics.clear(r, g, b, a, 0, 1)
        else
            love.graphics.clear(r, g, b, a)
        end
    end
    love.graphics.push()
    local scale, viewW, viewH = applyCamera(camX, camY, fov)
    Render._scale = scale
    if Render._style == "shaded" then
        syncCamera3D(viewH)
    end
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
    if Render._style == "shaded" then
        pcall(love.graphics.setMeshCullMode, "none")
        love.graphics.setDepthMode("lequal", true)
    end
    for i = 1, #roots do
        drawNode(roots[i], 0, 1, false, 0)
    end
    if Render._style == "shaded" then
        love.graphics.setDepthMode()
    end
    love.graphics.pop()
    return camX, camY, fov
end

local SQRT1_2 = math.sqrt(0.5)
local SQRT2 = math.sqrt(2)

local function iconPoly(sides, rad, stroke, fill, alpha, angle, height, oz, ring)
    local pts = polyRegular(sides, rad, false)
    if Render._style == "shaded" then
        pts = insetPts(pts, stroke * 0.5, rad)
        if #pts >= 6 then
            local h = height or prismHeight(rad * 0.70710678118)
            if ring then
                drawRingPrism3D(pts, scalePts(pts, 0.62), h, fill, strokeHex(fill), alpha, stroke, angle or 0, 0, 0, oz)
            else
                drawPrism3D(pts, h, fill, strokeHex(fill), alpha, stroke, angle or 0, 0, 0, oz)
            end
        end
        return
    end
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

local function iconCircle(r, stroke, fill, alpha, oz)
    local cr = r - stroke * 0.5
    if cr < r * 0.72 then cr = r * 0.72 end
    if Render._style == "shaded" then
        drawSphere3D(cr, fill, strokeHex(fill), alpha, stroke, 0, 0, 0, oz)
        return
    end
    fillStroke(fill, strokeHex(fill), alpha, stroke, function()
        love.graphics.circle("fill", 0, 0, cr)
    end, function()
        love.graphics.circle("line", 0, 0, cr)
    end, cr)
end

local function iconBarrel(size, width, ang, off, trap, trapDir, stroke, fill, alpha, oz)
    local hw = width / 2
    local tip = 1
    if trap then
        tip = 1 + 0.5 * math.cos(trapDir or 0)
        if tip < 0.2 then tip = 0.2 end
    end
    if Render._style == "shaded" then
        drawCylinder3D(0, size, hw, hw * tip, fill, strokeHex(fill), alpha, stroke, off, ang, 0, 0, -hw * 0.35, oz)
        return
    end
    love.graphics.push()
    love.graphics.rotate(ang)
    local pts = chamferPoly({
        0, off - hw,
        size, off - hw * tip,
        size, off + hw * tip,
        0, off + hw
    }, math.min(size, hw) * 0.16)
    fillStroke(fill, strokeHex(fill), alpha, stroke, function()
        if #pts >= 6 then love.graphics.polygon("fill", pts) end
    end, function()
        if #pts >= 6 then love.graphics.polygon("line", pts) end
    end, math.min(size, hw))
    love.graphics.pop()
end

local function iconGuard(sides, sizeRatio, offsetAngle, bodyR, stroke, alpha, oz)
    -- GuardObject multiplies sizeRatio by SQRT1_2; world polygons draw at size * sqrt(2).
    local rad = bodyR * sizeRatio * SQRT1_2 * SQRT2
    if Render._style == "shaded" then
        iconPoly(sides, rad, stroke, 0x555555, alpha, offsetAngle or 0, smasherBladeHeight(rad * 0.70710678118), oz, sides >= 6)
        return
    end
    love.graphics.push()
    love.graphics.rotate(offsetAngle or 0)
    iconPoly(sides, rad, stroke, 0x555555, alpha)
    love.graphics.pop()
end

local function iconTurret(x, y, ang, stroke, alpha, lift)
    local barrelFill = 0x999999
    love.graphics.push()
    love.graphics.translate(x, y)
    if Render._style == "shaded" then
        iconBarrel(55, 42 * 0.7, ang or 0, 0, false, 0, stroke, barrelFill, alpha, lift)
        iconCircle(25, stroke, barrelFill, alpha, lift)
    else
        love.graphics.rotate(ang or 0)
        iconBarrel(55, 42 * 0.7, 0, 0, false, 0, stroke, barrelFill, alpha)
        iconCircle(25, stroke, barrelFill, alpha)
    end
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
        local bladeH = smasherBladeHeight(bodyR * 1.15 * SQRT1_2)
        if id == "smasher" or id == "autosmasher" then
            iconGuard(6, 1.15, 0, bodyR, stroke, alpha)
        elseif id == "landmine" then
            iconGuard(6, 1.15, 0, bodyR, stroke, alpha, -bladeH * 0.6)
            iconGuard(6, 1.15, math.pi / 6, bodyR, stroke, alpha, bladeH * 0.6)
        elseif id == "spike" then
            iconGuard(3, 1.3, 0, bodyR, stroke, alpha, -bladeH * 1.5)
            iconGuard(3, 1.3, math.pi / 3, bodyR, stroke, alpha, -bladeH * 0.5)
            iconGuard(3, 1.3, math.pi / 6, bodyR, stroke, alpha, bladeH * 0.5)
            iconGuard(3, 1.3, math.pi / 2, bodyR, stroke, alpha, bladeH * 1.5)
        elseif id == "weirdspike" then
            iconGuard(3, 1.5, 0, bodyR, stroke, alpha, -bladeH * 0.6)
            iconGuard(3, 1.5, math.pi / 6, bodyR, stroke, alpha, bladeH * 0.6)
        elseif id == "spiesk" then
            iconGuard(4, 1.3, 0, bodyR, stroke, alpha, -bladeH)
            iconGuard(4, 1.3, math.pi / 6, bodyR, stroke, alpha, 0)
            iconGuard(4, 1.3, math.pi / 3, bodyR, stroke, alpha, bladeH)
        elseif id == "pronounced" then
            iconBarrel(bodyR, 42 / 50 * bodyR, math.pi, 0, true, math.pi, stroke, barrelFill, alpha)
        elseif id == "dompronounced" then
            iconBarrel(22 / 50 * bodyR, 35 / 50 * bodyR, math.pi, bodyR * 0.5, true, math.pi, stroke, barrelFill, alpha)
        end
        return
    end
    if id == "autoturret" or id == "autosmasher" then
        iconTurret(0, 0, 0, stroke, alpha, bodyR * 0.9)
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
    local savedX, savedY, savedZ, savedF = _camX, _camY, _camZ, _focal
    if Render._style == "shaded" then
        _camX, _camY = 0, 0
        _camZ, _focal = 300, 300
        pcall(love.graphics.clear, false, false, true)
        pcall(love.graphics.setMeshCullMode, "none")
        love.graphics.setDepthMode("lequal", true)
    end
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
    if Render._style == "shaded" then
        love.graphics.setDepthMode()
        _camX, _camY, _camZ, _focal = savedX, savedY, savedZ, savedF
    end
end

Render.hex = hex
Render.colorOf = colorOf

return Render
