local bit = require("bit")
local Enums = require("src.protocol.enums")

return function(Render)
local StyleFlags = Enums.StyleFlags
local PhysicsFlags = Enums.PhysicsFlags
local PositionFlags = Enums.PositionFlags
local HealthFlags = Enums.HealthFlags
local NameFlags = Enums.NameFlags

local polyCache = {}
local function polyRegular(sides, size, star)
    local q = math.floor((size or 0) * 16 + 0.5)
    local key = q * 512 + (sides or 0) * 2 + (star and 1 or 0)
    local cached = polyCache[key]
    if cached then return cached end
    size = q / 16
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
    polyCache[key] = pts
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
    return Render.darker(fill)
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
    { "VertexNormal", "float", 3 }
}
local MODE_SPHERE, MODE_CYL, MODE_RAW, MODE_FLAT = 0, 1, 2, 3
local depthShader
local sphereMesh, cylMesh
local prismCache, prismCacheN, PRISM_CACHE_MAX = {}, 0, 384
do
    local src = [[
        varying float vDepth;
        varying float vNd;
        uniform vec3 uOrigin;
        uniform vec2 uRot;
        uniform vec3 uCam;
        uniform float uFocal;
        uniform float uDepthFar;
        uniform float uDepthBias;
        uniform vec3 uLight;
        uniform vec2 uCel;
        uniform float uMode;
        uniform float uRadius;
        uniform vec4 uCyl;
        uniform vec2 uCylOff;
        #ifdef VERTEX
        ATTRIBUTE_NORMAL
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            vec3 local = vertex_position.xyz;
            vec3 nrm = VertexNormal;
            if (uMode > 2.5) {
                vDepth = clamp(local.z + uDepthBias, 0.001, 0.999);
                vNd = 2.0;
                return transform_projection * vec4(local.xy, 0.0, 1.0);
            }
            if (uMode > 0.5 && uMode < 1.5) {
                float u = local.x;
                float r = mix(uCyl.z, uCyl.w, u);
                local = vec3(mix(uCyl.x, uCyl.y, u), uCylOff.x + local.y * r, uCylOff.y + local.z * r);
                if (abs(nrm.x) < 0.5) {
                    float L = uCyl.y - uCyl.x;
                    float sl = (uCyl.z - uCyl.w) / max(abs(L), 0.0001);
                    float den = sqrt(1.0 + sl * sl);
                    nrm = vec3(sl / den, nrm.y / den, nrm.z / den);
                }
            } else if (uMode < 0.5) {
                local *= uRadius;
            }
            float rx = local.x * uRot.x - local.y * uRot.y;
            float ry = local.x * uRot.y + local.y * uRot.x;
            vec3 world = vec3(uOrigin.x + rx, uOrigin.y + ry, local.z + uOrigin.z);
            float dz = max(uCam.z - world.z, 12.0);
            float f = uFocal / dz;
            vec2 screen = vec2(
                uCam.x + (world.x - uCam.x) * f - uOrigin.x,
                uCam.y + (world.y - uCam.y) * f - uOrigin.y
            );
            vDepth = clamp(dz * uDepthFar + uDepthBias, 0.001, 0.999);
            if (length(nrm) > 1.5) {
                vNd = 2.0;
            } else {
                vec3 nw = vec3(nrm.x * uRot.x - nrm.y * uRot.y, nrm.x * uRot.y + nrm.y * uRot.x, nrm.z);
                vNd = dot(nw, uLight);
            }
            return transform_projection * vec4(screen, 0.0, 1.0);
        }
        #endif
        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            gl_FragDepth = vDepth;
            float t = 1.0;
            if (vNd < 1.5) {
                if (vNd > uCel.x) {
                    t = 1.0;
                } else {
                    t = uCel.y;
                }
            }
            return vec4(color.rgb * t, color.a);
        }
        #endif
    ]]
    local attempts = {
        src:gsub("ATTRIBUTE_NORMAL", "attribute vec3 VertexNormal;"),
        src:gsub("ATTRIBUTE_NORMAL", "")
    }
    local lastErr
    for i = 1, #attempts do
        local ok, sh = pcall(love.graphics.newShader, attempts[i])
        if ok then
            depthShader = sh
            lastErr = nil
            break
        end
        lastErr = sh
    end
    if lastErr then
        print("[LoveDiepClient] 3D depth shader: " .. tostring(lastErr))
    end
end

local function addTri(verts, ax, ay, az, anx, any, anz, bx, by, bz, bnx, bny, bnz, cx, cy, cz, cnx, cny, cnz)
    verts[#verts + 1] = { ax, ay, az, 1, 1, 1, 1, anx, any, anz }
    verts[#verts + 1] = { bx, by, bz, 1, 1, 1, 1, bnx, bny, bnz }
    verts[#verts + 1] = { cx, cy, cz, 1, 1, 1, 1, cnx, cny, cnz }
end

local function newStaticMesh(verts)
    if not verts or #verts < 3 then return nil end
    return love.graphics.newMesh(MESH_FORMAT, verts, "triangles", "static")
end

do
    local verts = {}
    for st = SPHERE_STACKS - 1, 0, -1 do
        local outer, inner = sphereLat[st + 1], sphereLat[st]
        for i = 0, SPHERE_SLICES - 1 do
            local a, b = outer[i], outer[i + 1]
            local c, d = inner[i], inner[i + 1]
            if st == SPHERE_STACKS - 1 then
                addTri(verts,
                    c[1], c[2], c[3], c[1], c[2], c[3],
                    d[1], d[2], d[3], d[1], d[2], d[3],
                    a[1], a[2], a[3], a[1], a[2], a[3])
            elseif st == 0 then
                addTri(verts,
                    a[1], a[2], a[3], a[1], a[2], a[3],
                    b[1], b[2], b[3], b[1], b[2], b[3],
                    c[1], c[2], c[3], c[1], c[2], c[3])
            else
                addTri(verts,
                    a[1], a[2], a[3], a[1], a[2], a[3],
                    b[1], b[2], b[3], b[1], b[2], b[3],
                    c[1], c[2], c[3], c[1], c[2], c[3])
                addTri(verts,
                    b[1], b[2], b[3], b[1], b[2], b[3],
                    d[1], d[2], d[3], d[1], d[2], d[3],
                    c[1], c[2], c[3], c[1], c[2], c[3])
            end
        end
    end
    sphereMesh = newStaticMesh(verts)
end

do
    local verts = {}
    for i = 0, CYL_SEGS - 1 do
        local a, b = cylRing[i], cylRing[i + 1]
        addTri(verts,
            0, a[1], a[2], 0, a[1], a[2],
            1, a[1], a[2], 0, a[1], a[2],
            0, b[1], b[2], 0, b[1], b[2])
        addTri(verts,
            1, a[1], a[2], 0, a[1], a[2],
            1, b[1], b[2], 0, b[1], b[2],
            0, b[1], b[2], 0, b[1], b[2])
        addTri(verts,
            0, 0, 0, -1, 0, 0,
            0, a[1], a[2], -1, 0, 0,
            0, b[1], b[2], -1, 0, 0)
        addTri(verts,
            1, 0, 0, 1, 0, 0,
            1, b[1], b[2], 1, 0, 0,
            1, a[1], a[2], 1, 0, 0)
    end
    cylMesh = newStaticMesh(verts)
end

local _shadeOn = false
local function sendU(name, value)
    if not depthShader then return end
    pcall(depthShader.send, depthShader, name, value)
end

local function sendCam()
    sendU("uCam", { _camX, _camY, _camZ })
    sendU("uFocal", _focal)
    sendU("uDepthFar", DEPTH_FAR)
    sendU("uLight", { _lx, _ly, _lz })
    sendU("uCel", { CEL_THRESH, CEL_SHADOW })
end

local function sendObj()
    sendU("uOrigin", { _ox, _oy, _oz })
    sendU("uRot", { _angC, _angS })
    sendU("uDepthBias", _depthBias)
end

local function bindShade()
    if not depthShader then return end
    if not _shadeOn then
        love.graphics.setShader(depthShader)
        _shadeOn = true
        sendCam()
    end
    sendObj()
end

local function unbindShade()
    if _shadeOn then
        love.graphics.setShader()
        _shadeOn = false
    end
end

local function setMode(mode, radius, cyl, off)
    sendU("uMode", mode or MODE_RAW)
    sendU("uRadius", radius or 1)
    sendU("uCyl", cyl or { 0, 1, 1, 1 })
    sendU("uCylOff", off or { 0, 0 })
end

local function drawGpuMesh(mesh, mode, radius, cyl, off)
    if not mesh then return end
    bindShade()
    setMode(mode, radius, cyl, off)
    love.graphics.draw(mesh)
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
    local r, g, b = Render.hex(fill)
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

local function meshPush(x, y, z, r, g, b, a, nx, ny, nz)
    meshN = meshN + 1
    local v = meshVerts[meshN]
    nx, ny, nz = nx or 0, ny or 0, nz or 2
    if v then
        v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10] = x, y, z, r, g, b, a, nx, ny, nz
    else
        meshVerts[meshN] = { x, y, z, r, g, b, a, nx, ny, nz }
    end
end

local function meshTri(x1, y1, z1, r1, g1, b1, a1, x2, y2, z2, r2, g2, b2, a2, x3, y3, z3, r3, g3, b3, a3, n1x, n1y, n1z, n2x, n2y, n2z, n3x, n3y, n3z)
    meshPush(x1, y1, z1, r1, g1, b1, a1, n1x, n1y, n1z)
    meshPush(x2, y2, z2, r2, g2, b2, a2, n2x, n2y, n2z)
    meshPush(x3, y3, z3, r3, g3, b3, a3, n3x, n3y, n3z)
end

local compactVerts = {}

local function meshFlush(mode)
    if meshN < 3 then
        meshN = 0
        return
    end
    if not triMesh or triMesh:getVertexCount() < meshN then
        triMesh = love.graphics.newMesh(MESH_FORMAT, math.max(meshN * 2, 4096), "triangles", "stream")
    end
    for i = 1, meshN do
        compactVerts[i] = meshVerts[i]
    end
    for i = #compactVerts, meshN + 1, -1 do
        compactVerts[i] = nil
    end
    triMesh:setVertices(compactVerts)
    triMesh:setDrawRange(1, meshN)
    drawGpuMesh(triMesh, mode or MODE_RAW)
    meshN = 0
end

local hullPts = {}
local hullN = 0

local function hullReset()
    hullN = 0
end

local function hullAdd(x, y, z)
    hullN = hullN + 1
    local p = hullPts[hullN]
    if p then
        p[1], p[2], p[3] = x, y, z or 0.5
    else
        hullPts[hullN] = { x, y, z or 0.5 }
    end
end

local function hullList()
    for i = #hullPts, hullN + 1, -1 do
        hullPts[i] = nil
    end
    return hullPts
end

local function meshLitTri(ax, ay, az, anx, any, anz,
                          bx, by, bz, bnx, bny, bnz,
                          cx, cy, cz, cnx, cny, cnz,
                          fill, opacity)
    local r, g, b, a = Render.hex(fill, opacity)
    meshTri(
        ax, ay, az, r, g, b, a,
        bx, by, bz, r, g, b, a,
        cx, cy, cz, r, g, b, a,
        anx, any, anz, bnx, bny, bnz, cnx, cny, cnz)
end

-- 2D silhouette ring in already-projected XY. Depth sits just behind this
-- mesh so nearer parts (barrels, other tanks) occlude it.
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
    local r, g, b, a = Render.hex(border, opacity)
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
            i1[1], i1[2], z, r, g, b, a,
            0, 0, 2, 0, 0, 2, 0, 0, 2)
        meshTri(
            i1[1], i1[2], z, r, g, b, a,
            o0[1], o0[2], z, r, g, b, a,
            o1[1], o1[2], z, r, g, b, a,
            0, 0, 2, 0, 0, 2, 0, 0, 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
    meshFlush(MODE_FLAT)
end

local function strokeOutline(points, border, opacity, stroke)
    strokeLoop(convexHull(points), border, opacity, stroke)
end

local function hullProject(lx, ly, lz)
    local sx, sy, depth = proj(lx, ly, lz)
    hullAdd(sx, sy, depth)
end

local function strokeProjected(border, opacity, stroke)
    if not stroke or stroke <= 0.2 or opacity <= 0.02 or hullN < 3 then
        hullReset()
        return
    end
    strokeOutline(hullList(), border, opacity, stroke)
    hullReset()
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
    local r, g, b, a = Render.hex(border, opacity)
    local function emit(ax, ay, az, bx, by, bz, cx, cy, cz)
        meshTri(
            ax, ay, az, r, g, b, a,
            bx, by, bz, r, g, b, a,
            cx, cy, cz, r, g, b, a,
            0, 0, 2, 0, 0, 2, 0, 0, 2)
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
    love.graphics.setColor(1, 1, 1, 1)
    meshFlush()
end

local function qk(n)
    return math.floor((n or 0) * 4 + 0.5)
end

local function ptsCacheKey(prefix, pts, extra)
    local t = { prefix, extra or 0 }
    for i = 1, #pts do
        t[#t + 1] = qk(pts[i])
    end
    return table.concat(t, ",")
end

local function rememberMesh(key, mesh)
    if not mesh then return nil end
    if prismCacheN >= PRISM_CACHE_MAX then
        local drop
        for k in pairs(prismCache) do
            drop = k
            break
        end
        if drop then
            local old = prismCache[drop]
            prismCache[drop] = nil
            prismCacheN = prismCacheN - 1
            if old and old.release then
                pcall(old.release, old)
            end
        end
    end
    prismCache[key] = mesh
    prismCacheN = prismCacheN + 1
    return mesh
end

local function cachedMesh(key, builder)
    local mesh = prismCache[key]
    if mesh then return mesh end
    return rememberMesh(key, builder())
end

local function drawSphere3D(radius, fill, border, opacity, stroke, angle, ox, oy, oz)
    if not radius or radius < 0.35 or opacity < 0.02 then return end
    begin3D(angle, ox, oy, oz)
    love.graphics.setColor(Render.hex(fill, opacity))
    drawGpuMesh(sphereMesh, MODE_SPHERE, radius)
    if stroke and stroke > 0.2 and opacity > 0.02 then
        hullReset()
        for st = 0, SPHERE_STACKS do
            local ring = sphereLat[st]
            for i = 0, SPHERE_SLICES - 1 do
                local p = ring[i]
                hullProject(p[1] * radius, p[2] * radius, p[3] * radius)
            end
        end
        strokeProjected(border, opacity, stroke)
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
    love.graphics.setColor(Render.hex(fill, opacity))
    drawGpuMesh(cylMesh, MODE_CYL, 1, { x0, x1, r0, r1 }, { yOff, zOff })
    if stroke and stroke > 0.2 and opacity > 0.02 then
        hullReset()
        for i = 0, CYL_SEGS - 1 do
            local a = cylRing[i]
            hullProject(x0, yOff + a[1] * r0, zOff + a[2] * r0)
            hullProject(x1, yOff + a[1] * r1, zOff + a[2] * r1)
        end
        strokeProjected(border, opacity, stroke)
    end
end

local function buildPrismMesh(pts, z0, z1)
    local verts = {}
    local n = #pts / 2
    for i = 1, n do
        local j = (i % n) + 1
        local x0, y0 = pts[i * 2 - 1], pts[i * 2]
        local x1, y1 = pts[j * 2 - 1], pts[j * 2]
        addTri(verts, 0, 0, z1, 0, 0, 1, x0, y0, z1, 0, 0, 1, x1, y1, z1, 0, 0, 1)
        addTri(verts, 0, 0, z0, 0, 0, -1, x1, y1, z0, 0, 0, -1, x0, y0, z0, 0, 0, -1)
        local dx, dy = x1 - x0, y1 - y0
        local nx, ny = dy, -dx
        if nx * (x0 + x1) + ny * (y0 + y1) < 0 then
            nx, ny = -nx, -ny
        end
        nx, ny = nrm3(nx, ny, 0)
        addTri(verts, x0, y0, z1, nx, ny, 0, x1, y1, z1, nx, ny, 0, x0, y0, z0, nx, ny, 0)
        addTri(verts, x1, y1, z1, nx, ny, 0, x1, y1, z0, nx, ny, 0, x0, y0, z0, nx, ny, 0)
    end
    return newStaticMesh(verts)
end

local function drawPrism3D(pts, height, fill, border, opacity, stroke, angle, ox, oy, oz)
    if not pts or #pts < 6 or opacity < 0.02 then return end
    begin3D(angle, ox, oy, oz)
    local h = height or 0
    if h < 0 then h = 0 end
    local z0, z1 = -h * 0.5, h * 0.5
    local mesh = cachedMesh(ptsCacheKey("p", pts, qk(z0) * 10000 + qk(z1)), function()
        return buildPrismMesh(pts, z0, z1)
    end)
    love.graphics.setColor(Render.hex(fill, opacity))
    drawGpuMesh(mesh, MODE_RAW)
    if stroke and stroke > 0.2 and opacity > 0.02 then
        if ptsConvex(pts) then
            hullReset()
            local n = #pts / 2
            for i = 1, n do
                local x, y = pts[i * 2 - 1], pts[i * 2]
                hullProject(x, y, z0)
                hullProject(x, y, z1)
            end
            strokeProjected(border, opacity, stroke)
        else
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
local function buildRingMesh(outer, inner, z0, z1)
    local verts = {}
    local n = #outer / 2
    for i = 1, n do
        local j = (i % n) + 1
        local x0, y0 = outer[i * 2 - 1], outer[i * 2]
        local x1, y1 = outer[j * 2 - 1], outer[j * 2]
        local u0, v0 = inner[i * 2 - 1], inner[i * 2]
        local u1, v1 = inner[j * 2 - 1], inner[j * 2]
        addTri(verts, x0, y0, z1, 0, 0, 1, x1, y1, z1, 0, 0, 1, u0, v0, z1, 0, 0, 1)
        addTri(verts, x1, y1, z1, 0, 0, 1, u1, v1, z1, 0, 0, 1, u0, v0, z1, 0, 0, 1)
        addTri(verts, x0, y0, z0, 0, 0, -1, u0, v0, z0, 0, 0, -1, x1, y1, z0, 0, 0, -1)
        addTri(verts, x1, y1, z0, 0, 0, -1, u0, v0, z0, 0, 0, -1, u1, v1, z0, 0, 0, -1)
        local dx, dy = x1 - x0, y1 - y0
        local nx, ny = dy, -dx
        if nx * (x0 + x1) + ny * (y0 + y1) < 0 then
            nx, ny = -nx, -ny
        end
        nx, ny = nrm3(nx, ny, 0)
        addTri(verts, x0, y0, z1, nx, ny, 0, x1, y1, z1, nx, ny, 0, x0, y0, z0, nx, ny, 0)
        addTri(verts, x1, y1, z1, nx, ny, 0, x1, y1, z0, nx, ny, 0, x0, y0, z0, nx, ny, 0)
        dx, dy = u1 - u0, v1 - v0
        nx, ny = -dy, dx
        if nx * (u0 + u1) + ny * (v0 + v1) > 0 then
            nx, ny = -nx, -ny
        end
        nx, ny = nrm3(nx, ny, 0)
        addTri(verts, u0, v0, z1, nx, ny, 0, u0, v0, z0, nx, ny, 0, u1, v1, z1, nx, ny, 0)
        addTri(verts, u1, v1, z1, nx, ny, 0, u0, v0, z0, nx, ny, 0, u1, v1, z0, nx, ny, 0)
    end
    return newStaticMesh(verts)
end

local function drawRingPrism3D(outer, inner, height, fill, border, opacity, stroke, angle, ox, oy, oz)
    if not outer or not inner or #outer < 6 or #inner < 6 or opacity < 0.02 then return end
    begin3D(angle, ox, oy, oz)
    local h = height or 0
    if h < 0 then h = 0 end
    local z0, z1 = -h * 0.5, h * 0.5
    local key = ptsCacheKey("r", outer, qk(z0) * 10000 + qk(z1)) .. ptsCacheKey("i", inner, 0)
    local mesh = cachedMesh(key, function()
        return buildRingMesh(outer, inner, z0, z1)
    end)
    love.graphics.setColor(Render.hex(fill, opacity))
    drawGpuMesh(mesh, MODE_RAW)
    if stroke and stroke > 0.2 and opacity > 0.02 then
        hullReset()
        local n = #outer / 2
        for i = 1, n do
            local x, y = outer[i * 2 - 1], outer[i * 2]
            hullProject(x, y, z0)
            hullProject(x, y, z1)
        end
        strokeProjected(border, opacity, stroke)
    end
end

local function isSmasherGuard(e)
    local phy = e and e.physics
    local sty = e and e.style
    if not phy or not sty then return false end
    if (phy.sides or 0) < 3 then return false end
    if Render.flagged(sty, StyleFlags.isStar) then return false end
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
    love.graphics.setColor(Render.hex(fill, opacity))
    drawFill()
    love.graphics.setColor(Render.hex(border, opacity))
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
    if ptsConvex(pts) then
        love.graphics.polygon("fill", pts)
        return
    end
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

local function updateBeamParticles(e, hl, hw, dt)
    local parts = e._beamFx
    if not parts then
        parts = {}
        e._beamFx = parts
    end
    local acc = (e._beamAcc or 0) + dt
    local step = 0.02
    while acc >= step do
        acc = acc - step
        for side = -1, 1, 2 do
            for _ = 1, 3 do
                local spread = (math.random() - 0.5) * 1.35
                local ang = (side > 0 and 0 or math.pi) + spread
                local spd = 55 + math.random() * 110
                parts[#parts + 1] = {
                    x = side * hl,
                    y = (math.random() - 0.5) * hw * 0.7,
                    vx = math.cos(ang) * spd,
                    vy = math.sin(ang) * spd + (math.random() - 0.5) * 40,
                    age = 0,
                    life = 0.16 + math.random() * 0.32,
                    size = hw * (0.28 + math.random() * 0.7),
                    layer = (math.random() * 2 - 1)
                }
            end
        end
    end
    e._beamAcc = acc
    local i = 1
    while i <= #parts do
        local p = parts[i]
        p.age = p.age + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * (1 - dt * 2.4)
        p.vy = p.vy * (1 - dt * 2.4)
        if p.age >= p.life then
            parts[i] = parts[#parts]
            parts[#parts] = nil
        else
            i = i + 1
        end
    end
    while #parts > 72 do
        table.remove(parts, 1)
    end
    return parts
end

local function drawBeamRibbon(hl, hw, fill, opacity, time, layer, amp, freq, phase, widthMul, alphaMul)
    local segs = math.min(42, math.max(14, math.floor(hl / 48)))
    local top, bot = {}, {}
    for i = 0, segs do
        local u = i / segs
        local x = -hl + u * hl * 2
        local wave = math.sin(u * freq + time * 6.4 + phase) * amp
            + math.sin(u * (freq * 0.45) - time * 3.1 + phase * 0.7) * amp * 0.45
        local swell = 1 + 0.22 * math.sin(u * 8.2 + time * 5.5 + layer)
        local half = hw * widthMul * swell
        top[#top + 1] = x
        top[#top + 1] = -half + wave
        bot[#bot + 1] = x
        bot[#bot + 1] = half + wave
    end
    for i = 0, segs - 1 do
        local u = (i + 0.5) / segs
        local r, g, b = Render.beamTint(fill, u, time, layer)
        love.graphics.setColor(r, g, b, opacity * alphaMul)
        local i0 = i * 2 + 1
        local i1 = (i + 1) * 2 + 1
        love.graphics.polygon("fill",
            top[i0], top[i0 + 1],
            top[i1], top[i1 + 1],
            bot[i1], bot[i1 + 1],
            bot[i0], bot[i0 + 1])
    end
end

local function drawBeam(e, hl, hw, fill, opacity, worldAngle)
    if hl < 2 or hw < 0.4 or opacity <= 0.02 then return end
    local time = love.timer.getTime()
    local dt = love.timer.getDelta()
    if dt > 0.05 then dt = 0.05 end
    local parts = updateBeamParticles(e, hl, hw, dt)
    local amp = math.max(hw * 0.85, 6)

    local function paint()
        local mode, alphaMode = love.graphics.getBlendMode()
        love.graphics.setBlendMode("add", "alphamultiply")
        drawBeamRibbon(hl, hw, fill, opacity, time, -1.1, amp * 1.35, 9.2, 0.4, 1.85, 0.16)
        drawBeamRibbon(hl, hw, fill, opacity, time, 0.9, amp * 1.05, 11.5, 1.7, 1.35, 0.28)
        drawBeamRibbon(hl, hw, fill, opacity, time, 0.0, amp * 0.7, 14.0, 0.2, 0.95, 0.55)
        love.graphics.setBlendMode("alpha", "alphamultiply")
        drawBeamRibbon(hl, hw, fill, opacity, time, 0.15, amp * 0.35, 16.5, 2.3, 0.42, 0.85)
        love.graphics.setBlendMode(mode, alphaMode)

        for side = -1, 1, 2 do
            local u = side > 0 and 1 or 0
            local r, g, b = Render.beamTint(fill, u, time, side)
            local pulse = 0.65 + 0.35 * math.sin(time * 11 + side * 2)
            love.graphics.setColor(r, g, b, opacity * 0.55 * pulse)
            love.graphics.circle("fill", side * hl, 0, hw * (1.15 + 0.35 * pulse))
            love.graphics.setColor(1, 1, 1, opacity * 0.35 * pulse)
            love.graphics.circle("fill", side * hl, 0, hw * 0.45)
        end

        for i = 1, #parts do
            local p = parts[i]
            local fade = 1 - (p.age / p.life)
            fade = fade * fade
            local u = (p.x / math.max(hl, 1) + 1) * 0.5
            local r, g, b = Render.beamTint(fill, u, time + p.age, p.layer)
            love.graphics.setColor(r, g, b, opacity * fade * 0.85)
            love.graphics.circle("fill", p.x, p.y, p.size * (0.45 + fade * 0.7))
        end
    end

    if Render._style == "shaded" then
        unbindShade()
        love.graphics.push()
        love.graphics.rotate(worldAngle or 0)
        love.graphics.setDepthMode("always", false)
        paint()
        love.graphics.setDepthMode("lequal", true)
        love.graphics.pop()
    else
        paint()
    end
end

local function drawBody(e, opacity, hit, worldAngle, worldX, worldY, worldZ)
    local phy = e.physics
    local sty = e.style
    if not phy or not sty then return end
    if not Render.flagged(sty, StyleFlags.isVisible) then return end
    if opacity <= 0.02 then return end
    local size = phy.size or 0
    if size <= 0 then return end
    local sides = phy.sides or 0
    if sides < 1 then return end
    local fill = Render.applyHit(Render.colorOf(e), hit)
    local border = Render.applyHit(strokeHex(Render.colorOf(e)), hit)
    local trap = bit.band(phy.flags or 0, PhysicsFlags.isTrapezoid) ~= 0
    local stroke = math.max(Render.pixel() * 2.5, math.min((sty.borderWidth or 7.5) * 0.78, size * 0.2))
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
        -- Protocol sides=2 is a rectangle. Barrels / trapezoid launchers stay
        -- cylinders; maze walls are boxes. Team bases stay flat 2D even in 3D.
        local isBarrelShape = e.barrel or trap
        local isBase = bit.band(phy.flags or 0, PhysicsFlags.isBase) ~= 0
        local isWall = bit.band(phy.flags or 0, PhysicsFlags.isSolidWall) ~= 0
        local isBeam = bit.band(phy.flags or 0, PhysicsFlags.isBeam) ~= 0
            or (trap and not e.barrel and not isBase and not isWall and size >= math.max(w, 1) * 8)
        if isBase then
            love.graphics.push()
            love.graphics.rotate(worldAngle or 0)
            if Render._style == "shaded" then
                unbindShade()
                love.graphics.setDepthMode("always", false)
            end
            love.graphics.setColor(Render.hex(fill, opacity))
            love.graphics.polygon("fill", -hl, -hw, hl, -hw, hl, hw, -hl, hw)
            if Render._style == "shaded" then
                love.graphics.setDepthMode("lequal", true)
            end
            love.graphics.pop()
        elseif isBeam then
            drawBeam(e, hl, hw, fill, opacity, worldAngle)
        elseif Render._style == "shaded" and not isBarrelShape then
            local thick = math.min(size, w)
            local height = isWall and prismHeight(math.min(thick, 900)) or prismHeight(math.min(thick, 400))
            local pts = {
                -hl, -hw,
                hl, -hw,
                hl, hw,
                -hl, hw
            }
            local boxStroke = ((sty.borderWidth or 0) > 0.5) and stroke or 0
            -- Sit on the play plane so walls rise up instead of hanging through it.
            drawPrism3D(pts, height, fill, border, opacity, boxStroke, worldAngle, worldX, worldY, worldZ + height * 0.5)
        else
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
                local chamfer = isBarrelShape and (math.min(hl, hw) * 0.18) or math.min(hl, hw, 12) * 0.08
                local pts = chamferPoly({
                    inner, -hw,
                    outer, -hw * tip,
                    outer, hw * tip,
                    inner, hw
                }, chamfer)
                fillStroke(fill, border, opacity, stroke, function()
                    if #pts >= 6 then love.graphics.polygon("fill", pts) end
                end, function()
                    strokePoly(pts)
                end, math.min(hl, hw))
            end
        end
    else
        local star = Render.flagged(sty, StyleFlags.isStar)
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
    local af = Render.flagged(a.style, StyleFlags.renderFirst) and 0 or 1
    local bf = Render.flagged(b.style, StyleFlags.renderFirst) and 0 or 1
    if af ~= bf then return af < bf end
    local az = (a.style and a.style.zIndex) or 0
    local bz = (b.style and b.style.zIndex) or 0
    return az < bz
end

local splitPool = {}
local splitDepth = 0

local function splitChildren(e)
    splitDepth = splitDepth + 1
    local slot = splitPool[splitDepth]
    if not slot then
        slot = { {}, {} }
        splitPool[splitDepth] = slot
    end
    local below, above = slot[1], slot[2]
    local nb, na = 0, 0
    local kids = e.children
    if kids then
        for i = 1, #kids do
            local c = kids[i]
            if Render.flagged(c.style, StyleFlags.showsAboveParent) then
                na = na + 1
                above[na] = c
            else
                nb = nb + 1
                below[nb] = c
            end
        end
    end
    for i = #below, nb + 1, -1 do
        below[i] = nil
    end
    for i = #above, na + 1, -1 do
        above[i] = nil
    end
    table.sort(below, childSort)
    table.sort(above, childSort)
    return below, above
end

local drawNode

drawNode = function(e, parentAngle, parentOpacity, parentFlash, parentHit, parentWX, parentWY, parentWZ)
    if e.camera or e.arena then return end
    if not e.physics and #(e.children or {}) == 0 then return end
    local lx, ly, la, flags = Render.localPos(e)
    local abs = bit.band(flags, PositionFlags.absoluteRotation) ~= 0
    local worldAngle = abs and la or (parentAngle + la)
    local opacity = parentOpacity * ((e.style and e.style.opacity) or 1)
    local flash = parentFlash or Render.flagged(e.style, StyleFlags.isFlashing)
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
        if Render.flagged(e.style, StyleFlags.showsAboveParent) then
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
        if e.physics and Render.flagged(e.style, StyleFlags.isVisible) then
            unbindShade()
            love.graphics.setDepthMode("always", false)
            drawHealth(e, drawOp)
            drawName(e, drawOp)
            love.graphics.setDepthMode("lequal", true)
        end
        love.graphics.pop()
        kids(above)
        splitDepth = splitDepth - 1
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
    if e.physics and Render.flagged(e.style, StyleFlags.isVisible) then
        drawHealth(e, drawOp)
        drawName(e, drawOp)
    end
    love.graphics.pop()
    splitDepth = splitDepth - 1
end

function Render.draw(world)
    splitDepth = 0
    local camX, camY, fov = Render.view(world)
    Render._camX, Render._camY, Render._fov = camX, camY, fov
    do
        local r, g, b, a = Render.hex(0xCDCDCD)
        if Render._style == "shaded" then
            love.graphics.clear(r, g, b, a, 0, 1)
        else
            love.graphics.clear(r, g, b, a)
        end
    end
    love.graphics.push()
    local scale, viewW, viewH = Render.applyCamera(camX, camY, fov)
    Render._scale = scale
    if Render._style == "shaded" then
        syncCamera3D(viewH)
    end
    Render._selfEntity = world:player()
    local arena = world:arenaValues()
    Render.drawArenaFloor(arena)
    Render.drawGrid(camX, camY, viewW, viewH)
    Render.drawArenaBorder(arena)

    local roots = {}
    local _, visW, visH = Render.viewMetrics(fov)
    Render._viewW, Render._viewH = visW, visH
    local margin = math.max(320, math.max(visW, visH) * 0.05)
    local x0, x1 = camX - visW * 0.5 - margin, camX + visW * 0.5 + margin
    local y0, y1 = camY - visH * 0.5 - margin, camY + visH * 0.5 + margin
    for _, e in pairs(world.entities) do
        if e.physics and not e.parentEntity and not e.camera and not e.arena and not e.barrel then
            local wx, wy = world:ensureWorld(e)
            local phy = e.physics
            local size = phy.size or 0
            local width = phy.width or 0
            local rad
            if (phy.sides or 0) == 2 then
                local ang = e.ia or (e.position and e.position.angle) or 0
                local hl, hw = size * 0.5, width * 0.5
                local c, s = math.abs(math.cos(ang)), math.abs(math.sin(ang))
                rad = math.max(hl * c + hw * s, hl * s + hw * c)
            else
                rad = size * math.sqrt(2)
            end
            if wx + rad >= x0 and wx - rad <= x1 and wy + rad >= y0 and wy - rad <= y1 then
                roots[#roots + 1] = e
            end
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
        unbindShade()
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

local paintTankIcon, bakeTankIcon

function Render.drawTankIcon(def, cx, cy, box, alpha)
    if not def or box <= 4 then return end
    alpha = alpha or 1
    local canvas = bakeTankIcon(def)
    if canvas then
        local w = canvas:getWidth()
        local mode, alphamode = love.graphics.getBlendMode()
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setColor(alpha, alpha, alpha, alpha)
        love.graphics.draw(canvas, cx, cy, 0, box / w, box / w, w * 0.5, w * 0.5)
        love.graphics.setBlendMode(mode, alphamode)
        return
    end
    paintTankIcon(def, cx, cy, box, alpha)
end

paintTankIcon = function(def, cx, cy, box, alpha)
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
        unbindShade()
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
        unbindShade()
        _camX, _camY, _camZ, _focal = savedX, savedY, savedZ, savedF
    end
end

local iconCache = {}
local ICON_PX = 256

function Render.invalidateIconCache()
    for k, canvas in pairs(iconCache) do
        if canvas and canvas.release then
            pcall(canvas.release, canvas)
        end
        iconCache[k] = nil
    end
end

local function iconCacheKey(def)
    return tostring(def.id or def.name or def) .. "\0" .. Render._style .. "\0" .. string.format("%.3f", Render._innerShadow or 0)
end

bakeTankIcon = function(def)
    local key = iconCacheKey(def)
    local cached = iconCache[key]
    if cached then return cached end
    local canvas = love.graphics.newCanvas(ICON_PX, ICON_PX, { dpiscale = 1, msaa = 0 })
    canvas:setFilter("linear", "linear")
    love.graphics.push()
    love.graphics.origin()
    local prevShader = love.graphics.getShader()
    local prevScissor = { love.graphics.getScissor() }
    love.graphics.setScissor()
    love.graphics.setShader()
    local okDepth = pcall(love.graphics.setCanvas, { canvas, depth = true })
    if not okDepth then
        love.graphics.setCanvas(canvas)
    end
    love.graphics.clear(0, 0, 0, 0, true, true)
    paintTankIcon(def, ICON_PX * 0.5, ICON_PX * 0.5, ICON_PX, 1)
    love.graphics.setCanvas()
    if prevShader then
        love.graphics.setShader(prevShader)
    else
        love.graphics.setShader()
    end
    if prevScissor[1] then
        love.graphics.setScissor(unpack(prevScissor))
    end
    love.graphics.pop()
    iconCache[key] = canvas
    return canvas
end
end
