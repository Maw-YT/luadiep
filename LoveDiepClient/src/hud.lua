local bit = require("bit")
local Enums = require("src.protocol.enums")
local Encode = require("src.protocol.encode")
local Render = require("src.render")
local Console = require("src.console")
local Settings = require("src.settings")
local TankTree = require("src.tanktree")
local Achievements = require("src.achievements")
local Changelog = require("src.changelog")
local Servers = require("src.servers")

local Hud = {}

Hud.GUI_W = 1280
Hud.GUI_H = 720

local STAT_COLORS = {
    [0] = { 0.18, 0.72, 0.92, 0.95 },
    [1] = { 0.98, 0.82, 0.22, 0.95 },
    [2] = { 0.94, 0.32, 0.33, 0.95 },
    [3] = { 1.00, 0.55, 0.20, 0.95 },
    [4] = { 0.22, 0.52, 0.95, 0.95 },
    [5] = { 0.75, 0.48, 0.96, 0.95 },
    [6] = { 0.18, 0.86, 0.42, 0.95 },
    [7] = { 0.98, 0.42, 0.70, 0.95 }
}

local PhysicsFlags = Enums.PhysicsFlags
local NameFlags = Enums.NameFlags

local anim = {
    hover = 0,
    hoverKey = "",
    pulse = 0,
    notify = 0,
    mapX = 0,
    mapY = 0,
    mapA = 0,
    up = 0,
    overlay = 0,
    tankShow = 0,
    statShow = 0
}

local presses = {}
local holdKey = nil

function Hud.metrics()
    local sw, sh = love.graphics.getDimensions()
    local scale = math.min(sw / Hud.GUI_W, sh / Hud.GUI_H)
    local ui = tonumber(Settings.hudScale) or 1
    if ui < 0.5 then ui = 0.5 end
    if ui > 2 then ui = 2 end
    scale = scale * ui
    if scale <= 0 then scale = 1 end
    -- Uniform scale from 1280x720, then fill leftover window space so
    -- corners (minimap, stats, scoreboard) sit on the real screen edges.
    return scale, 0, 0, sw / scale, sh / scale
end

function Hud.screenToGui(x, y)
    local scale, ox, oy = Hud.metrics()
    return (x - ox) / scale, (y - oy) / scale
end

function Hud.push()
    local scale, ox, oy, vw, vh = Hud.metrics()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
    return scale, ox, oy, vw, vh
end

function Hud.update(dt)
    dt = math.min(dt or 0.016, 0.05)
    local a = 1 - math.exp(-dt * 12)
    local mx, my = love.mouse.getPosition()
    mx, my = Hud.screenToGui(mx, my)
    local over = Hud._lastHoverKey or ""
    if over ~= anim.hoverKey then
        anim.hoverKey = over
        anim.hover = 0
    end
    anim.hover = anim.hover + (1 - anim.hover) * a
    anim.pulse = anim.pulse + dt
    anim.notify = anim.notify + (1 - anim.notify) * (1 - math.exp(-dt * 8))
    anim.up = math.min(1, anim.up + dt * 2.4)
    anim.overlay = anim.overlay + dt
    local held = love.mouse.isDown(1)
    for key, p in pairs(presses) do
        p.flash = p.flash * math.exp(-dt * 9)
        if held and holdKey == key then
            p.down = 1
        else
            p.down = p.down * math.exp(-dt * 14)
        end
        if p.flash < 0.02 and p.down < 0.02 then
            presses[key] = nil
        end
    end
    if not held then
        holdKey = nil
    end
end

function Hud.resetMap()
    anim.mapX, anim.mapY, anim.mapA = 0, 0, 0
end

local function statFill(i, can)
    local c = STAT_COLORS[i] or { 0.18, 0.52, 0.82, 0.95 }
    if can then
        local pulse = 0.5 + 0.5 * math.sin(anim.pulse * 5.2)
        return {
            math.min(1, c[1] + 0.10 * pulse),
            math.min(1, c[2] + 0.08 * pulse),
            math.min(1, c[3] + 0.06 * pulse),
            0.95
        }
    end
    return {
        c[1] * 0.38 + 0.10,
        c[2] * 0.38 + 0.10,
        c[3] * 0.38 + 0.10,
        0.9
    }
end

local function box(list, x, y, w, h, click, key, cursor)
    local c = cursor or "hand"
    list[#list + 1] = {
        x = x, y = y, w = w, h = h,
        click = click or function() end,
        key = key or (#list + 1),
        cursor = c,
        press = c == "hand" and key ~= "death"
    }
end

local function inRect(b, x, y, pad)
    pad = pad or 0
    return x >= b.x - pad and y >= b.y - pad and x <= b.x + b.w + pad and y <= b.y + b.h + pad
end

function Hud.over(buttons, x, y)
    if not buttons then return false end
    for i = #buttons, 1, -1 do
        if inRect(buttons[i], x, y, 6) then
            return true, buttons[i]
        end
    end
    return false
end

function Hud.hit(buttons, x, y)
    local ok, b = Hud.over(buttons, x, y)
    if ok and b and b.click then
        if b.press then
            Hud.press(b.key)
        end
        b.click()
        return true
    end
    return false
end

function Hud.press(key)
    if key == nil then return end
    presses[key] = { flash = 1, down = 1 }
    holdKey = key
end

function Hud.holdPress(key)
    if key == nil then return end
    local p = presses[key]
    if not p then
        presses[key] = { flash = 0, down = 1 }
    else
        p.down = 1
    end
end

local cursors = {}
local function systemCursor(name)
    local cached = cursors[name]
    if cached ~= nil then return cached end
    local ok, cur = pcall(love.mouse.getSystemCursor, name)
    cached = (ok and cur) or false
    cursors[name] = cached
    return cached
end

function Hud.syncCursor(buttons, x, y)
    local kind = "arrow"
    local ok, b = Hud.over(buttons, x, y)
    if ok and b then
        kind = b.cursor or "hand"
    end
    if kind ~= "hand" and kind ~= "ibeam" then
        kind = "arrow"
    end
    if Hud._cursor == kind then return end
    Hud._cursor = kind
    local cur = systemCursor(kind)
    if cur then
        love.mouse.setCursor(cur)
    else
        love.mouse.setCursor()
    end
end

local function roundrect(x, y, w, h, r, mode)
    love.graphics.rectangle(mode or "fill", x, y, w, h, r or 6, r or 6)
end

local function pressDown(key)
    local p = presses[key]
    return (p and p.down) or 0
end

local function buttonShadow(x, y, w, h, r, alpha, key)
    alpha = alpha or 1
    local lip = h * 0.2 * (1 - pressDown(key))
    if lip < 0.4 then return end
    love.graphics.stencil(function()
        roundrect(x, y, w, h, r)
    end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(0, 0, 0, 0.32 * alpha)
    love.graphics.rectangle("fill", x, y + h - lip, w, lip)
    love.graphics.setStencilTest()
end

local function darkenRgb(r, g, b, f)
    f = f or 0.62
    return r * f, g * f, b * f
end

local function buttonOutline(x, y, w, h, r, alpha, fr, fg, fb)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2.4)
    local dr, dg, db = darkenRgb(fr or 0.2, fg or 0.2, fb or 0.2, 0.62)
    love.graphics.setColor(dr, dg, db, alpha or 1)
    roundrect(x, y, w, h, r, "line")
end

local function buttonFlash(x, y, w, h, r, key, alpha)
    local p = presses[key]
    if not p or p.flash <= 0.02 then return end
    love.graphics.setColor(1, 1, 1, 0.58 * p.flash * (alpha or 1))
    roundrect(x, y, w, h, r)
end

local function txt(s)
    return Render.safeText(s)
end

local function drawCogIcon(cx, cy, r)
    local teeth = 8
    love.graphics.push()
    love.graphics.translate(cx, cy)
    for i = 0, teeth - 1 do
        love.graphics.push()
        love.graphics.rotate(i * math.pi * 2 / teeth)
        love.graphics.rectangle("fill", -r * 0.22, -r * 1.02, r * 0.44, r * 0.55, 2, 2)
        love.graphics.pop()
    end
    love.graphics.circle("fill", 0, 0, r * 0.68)
    love.graphics.setColor(0.10, 0.12, 0.16, 1)
    love.graphics.circle("fill", 0, 0, r * 0.28)
    love.graphics.pop()
end

local function outlinedBar(x, y, w, h, ratio, fill, radius, alpha)
    radius = radius or 6
    alpha = alpha or 1
    ratio = math.max(0, math.min(1, ratio or 0))
    love.graphics.setColor(0.08, 0.08, 0.08, 0.72 * alpha)
    roundrect(x, y, w, h, radius)
    if w * ratio > 0.5 then
        love.graphics.stencil(function()
            roundrect(x, y, w, h, radius)
        end, "replace", 1)
        love.graphics.setStencilTest("equal", 1)
        love.graphics.setColor(fill[1], fill[2], fill[3], (fill[4] or 1) * alpha)
        Render.drawWaveFill(x, y, w, h, ratio)
        love.graphics.setStencilTest()
    end
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.05, 0.05, 0.05, alpha)
    roundrect(x, y, w, h, radius, "line")
end

local function scissorGui(x, y, w, h)
    local scale, ox, oy = Hud.metrics()
    love.graphics.setScissor(
        math.floor(ox + x * scale + 0.5),
        math.floor(oy + y * scale + 0.5),
        math.max(0, math.floor(w * scale + 0.5)),
        math.max(0, math.floor(h * scale + 0.5))
    )
end

local function easeOut(t)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return 1 - (1 - t) * (1 - t)
end

local function followShow(current, want, speed)
    local dt = math.min(love.timer.getDelta() or 0.016, 0.05)
    local a = 1 - math.exp(-dt * (speed or 14))
    local next = current + ((want and 1 or 0) - current) * a
    if next < 0.002 then return 0 end
    if want and next > 0.998 then return 1 end
    return next
end

local function hoverScale(key, x, y, w, h)
    local s = 1
    if anim.hoverKey == key then
        s = 1 + 0.055 * anim.hover
    end
    local nx = x - (w * (s - 1)) * 0.5
    local ny = y - (h * (s - 1)) * 0.5
    local nw, nh = w * s, h * s
    local down = pressDown(key)
    if down > 0 then
        ny = ny + math.min(7, nh * 0.14) * down
    end
    return nx, ny, nw, nh, s
end

local function formatScore(n)
    n = tonumber(n) or 0
    if n ~= n or n < 0 then n = 0 end
    n = math.floor(n + 0.5)
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fk", n / 1000)
    elseif n >= 1000 then
        local s = tostring(n)
        return s:sub(1, #s - 3) .. "," .. s:sub(#s - 2)
    end
    return tostring(n)
end

local function mapRect(sw, sh)
    local size = 176
    local pad = 18
    return sw - pad - size, sh - pad - size, size
end

local function caption(text, x, y, align, w)
    w = w or 80
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(0.64, 0.64)
    if align == "right" then
        Render.printf(text, -w, 0, w, "right")
    elseif align == "center" then
        Render.printf(text, -w * 0.5, 0, w, "center")
    else
        Render.print(text, 0, 0)
    end
    love.graphics.pop()
end

local function modeTitle(game)
    local id = tostring(game.gamemode or "ffa")
    local modes = game.modes
    if modes then
        for i = 1, #modes do
            if modes[i].id == id then
                return tostring(modes[i].label or id)
            end
        end
    end
    return string.upper(id)
end

local function currentTankName(game, cam)
    local tankId = math.floor(tonumber(cam and cam.tank) or 0)
    if tankId == 53 then tankId = 0 end
    local def = game.tanksById and game.tanksById[tankId]
    if def and type(def.name) == "string" and def.name ~= "" then
        return txt(def.name)
    end
    return "Unknown"
end

local function drawMatchInfo(game, cam, sw, sh, buttons)
    local mapX, mapY, mapSize = mapRect(sw, sh)
    local w = 150
    local gap = 10
    local x = mapX - gap - w
    local y = mapY
    local h = mapSize
    box(buttons, x, y, w, h, function() end, "status", "arrow")

    love.graphics.setColor(0.06, 0.07, 0.09, 0.78)
    roundrect(x, y, w, h, 10)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(1.6)
    love.graphics.setColor(1, 1, 1, 0.08)
    roundrect(x, y, w, h, 10, "line")

    local rows = {
        { label = "MODE", value = modeTitle(game) },
        { label = "PLAYERS", value = tostring(game.playerCount or 0) },
        { label = "TANK", value = currentTankName(game, cam) }
    }
    local rowH = h / #rows
    for i = 1, #rows do
        local ry = y + (i - 1) * rowH
        if i > 1 then
            love.graphics.setColor(1, 1, 1, 0.06)
            love.graphics.setLineWidth(1)
            love.graphics.line(x + 14, ry, x + w - 14, ry)
        end
        love.graphics.setColor(0.62, 0.68, 0.76, 0.72)
        caption(rows[i].label, x + w * 0.5, ry + 10, "center", 140)
        love.graphics.setColor(1, 1, 1, 0.96)
        scissorGui(x + 8, ry + 22, w - 16, rowH - 26)
        Render.printf(rows[i].value, x + 8, ry + rowH * 0.5 - 4, w - 16, "center")
        love.graphics.setScissor()
    end
end

local function drawXpHud(game, cam, camEnt, sw, sh, buttons)
    local level = math.floor(tonumber(cam.level) or 1)
    local score = math.floor(tonumber(cam.score) or 0)
    local prog = (camEnt and camEnt.ibar) or cam.levelbarProgress or 0
    local maxp = (camEnt and camEnt.ibarMax) or cam.levelbarMax or 1
    local ratio = (maxp > 0) and math.min(1, math.max(0, prog / maxp)) or 1

    local barW = math.min(448, sw * 0.38)
    local barH = 22
    local padX, padY = 14, 10
    local head = 28
    local hint = 16
    local cardW = barW + padX * 2
    local cardH = padY + head + 4 + barH + 6 + hint + padY - 4
    local cx = (sw - cardW) / 2
    local cy = sh - 16 - cardH
    box(buttons, cx, cy, cardW, cardH, function() end, "xp", "arrow")

    love.graphics.setColor(0.06, 0.07, 0.09, 0.78)
    roundrect(cx, cy, cardW, cardH, 12)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(1.6)
    love.graphics.setColor(1, 1, 1, 0.08)
    roundrect(cx, cy, cardW, cardH, 12, "line")

    local player = game.world and game.world:player()
    local nametag = ""
    local gold = false
    if player and player.name then
        nametag = txt(player.name.name)
        gold = bit.band(player.name.flags or 0, NameFlags.highlightedName) ~= 0
    end
    if nametag == "" then
        nametag = txt(game.spawnName or "")
    end
    if nametag ~= "" then
        if gold then
            love.graphics.setColor(1, 0.85, 0.2, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        Render.outlinedPrintf(nametag, 0, cy - 22, sw, "center", 2)
    end

    local pillW, pillH = 62, 20
    local pillX, pillY = cx + padX, cy + padY + 1
    love.graphics.setColor(0.95, 0.78, 0.22, 0.22)
    roundrect(pillX, pillY, pillW, pillH, 8)
    love.graphics.setColor(0.98, 0.88, 0.42, 0.98)
    Render.printf("Lv " .. tostring(level), pillX, pillY + 3, pillW, "center")
    local ox = pillX + pillW + 6
    if game.autoFire then
        love.graphics.setColor(0.18, 0.72, 0.38, 0.38)
        roundrect(ox, pillY, 52, pillH, 8)
        love.graphics.setColor(0.55, 1, 0.72, 1)
        Render.printf("FIRE", ox, pillY + 3, 52, "center")
        ox = ox + 58
    end
    if game.autoSpin then
        love.graphics.setColor(0.16, 0.50, 0.82, 0.38)
        roundrect(ox, pillY, 52, pillH, 8)
        love.graphics.setColor(0.65, 0.88, 1, 1)
        Render.printf("SPIN", ox, pillY + 3, 52, "center")
    end

    love.graphics.setColor(0.62, 0.68, 0.76, 0.7)
    caption("SCORE", cx + cardW - padX, cy + padY - 1, "right", 90)
    love.graphics.setColor(1, 1, 1, 0.98)
    love.graphics.push()
    love.graphics.translate(cx + cardW - padX, cy + padY + 8)
    love.graphics.scale(1.12, 1.12)
    Render.printf(formatScore(score), -180, 0, 180, "right")
    love.graphics.pop()

    local bx, by = cx + padX, cy + padY + head + 2
    outlinedBar(bx, by, barW, barH, ratio, { 0.95, 0.78, 0.22, 0.96 }, 8)

    love.graphics.setColor(0.70, 0.76, 0.84, 0.55)
    local hintText = "WASD  LMB  E auto fire  C auto spin  Esc  pause  Y  F11"
    if game.canCheat and game:canCheat() then
        hintText = "WASD  LMB  E C  U K  Esc  pause  Y  F11"
    end
    caption(hintText, cx + cardW * 0.5, by + barH + 7, "center", 560)
end

local function drawMinimap(game, world, arena, player, cam, sw, sh, buttons)
    local x, y, size = mapRect(sw, sh)
    box(buttons, x - 6, y - 6, size + 12, size + 12, function() end, "minimap", "arrow")

    love.graphics.setColor(0.07, 0.08, 0.10, 0.78)
    roundrect(x, y, size, size, 10)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.04, 0.05, 0.06, 1)
    roundrect(x, y, size, size, 10, "line")

    local l = arena and tonumber(arena.leftX)
    local t = arena and tonumber(arena.topY)
    local r = arena and tonumber(arena.rightX)
    local btm = arena and tonumber(arena.bottomY)
    if not l or not t or not r or not btm or r <= l or btm <= t then
        love.graphics.setColor(1, 1, 1, 0.45)
        Render.printf("Map", x, y + size * 0.5 - 8, size, "center")
        return
    end

    local pad = 10
    local inner = size - pad * 2
    local aw, ah = r - l, btm - t
    local s = math.min(inner / aw, inner / ah)
    local ox = x + pad + (inner - aw * s) * 0.5
    local oy = y + pad + (inner - ah * s) * 0.5

    local function toMap(wx, wy)
        return ox + (wx - l) * s, oy + (wy - t) * s
    end

    love.graphics.setColor(0.80, 0.80, 0.80, 0.55)
    love.graphics.rectangle("fill", ox, oy, aw * s, ah * s, 4, 4)
    love.graphics.setColor(0.12, 0.12, 0.12, 0.9)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", ox, oy, aw * s, ah * s, 4, 4)

    local fov = (cam and cam.FOV) or 0.35
    if fov < 0.05 then fov = 0.35 end
    local camX, camY = Render.view(world)
    local vw, vh = 1920 / fov, 1080 / fov
    local vx, vy = toMap(camX - vw * 0.5, camY - vh * 0.5)
    local vx2, vy2 = toMap(camX + vw * 0.5, camY + vh * 0.5)
    love.graphics.setColor(1, 1, 1, 0.28)
    love.graphics.rectangle("line", vx, vy, vx2 - vx, vy2 - vy)

    scissorGui(x + 4, y + 4, size - 8, size - 8)
    for _, e in pairs(world.entities) do
        if e.physics and not e.barrel and not e.camera and not e.arena then
            local onMap = bit.band(e.physics.flags or 0, PhysicsFlags.showsOnMap) ~= 0
            local name = e.name and e.name.name
            local hidden = e.name and bit.band(e.name.flags or 0, NameFlags.hiddenName) ~= 0
            local named = type(name) == "string" and name ~= "" and not hidden
            if onMap or named then
                world:ensureWorld(e)
                local px, py = toMap(e.worldX or e.ix or 0, e.worldY or e.iy or 0)
                local col = Render.colorOf(e)
                local rr, gg, bb = Render.hex(col)
                if onMap then
                    love.graphics.setColor(rr, gg, bb, 0.95)
                    love.graphics.rectangle("fill", px - 3, py - 3, 6, 6)
                else
                    love.graphics.setColor(rr, gg, bb, 0.9)
                    love.graphics.circle("fill", px, py, 2.4)
                end
            end
        end
    end

    if player and player.physics then
        world:ensureWorld(player)
        local tx = player.worldX or player.ix or 0
        local ty = player.worldY or player.iy or 0
        local ta = player.worldAngle or player.ia or 0
        local follow = 1 - math.exp(-(love.timer.getDelta() or 0.016) * 10)
        if anim.mapX == 0 and anim.mapY == 0 then
            anim.mapX, anim.mapY, anim.mapA = tx, ty, ta
        else
            anim.mapX = anim.mapX + (tx - anim.mapX) * follow
            anim.mapY = anim.mapY + (ty - anim.mapY) * follow
            local d = ta - anim.mapA
            while d > math.pi do d = d - math.pi * 2 end
            while d < -math.pi do d = d + math.pi * 2 end
            anim.mapA = anim.mapA + d * follow
        end
        local px, py = toMap(anim.mapX, anim.mapY)
        love.graphics.push()
        love.graphics.translate(px, py)
        love.graphics.rotate(anim.mapA)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.polygon("fill", 7, 0, -5, -4.5, -5, 4.5)
        love.graphics.setColor(0.05, 0.05, 0.05, 1)
        love.graphics.setLineWidth(1.4)
        love.graphics.polygon("line", 7, 0, -5, -4.5, -5, 4.5)
        love.graphics.pop()
    end
    love.graphics.setScissor()
end

local function drawAchievements(sw, sh)
    local list = Achievements.list()
    local panelW = 268
    local panelX = sw - panelW - 24
    local panelY = 82
    local panelH = sh - 118
    if panelH < 160 then return end

    love.graphics.setColor(0.07, 0.08, 0.10, 0.72)
    roundrect(panelX, panelY, panelW, panelH, 14)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.setLineWidth(1.4)
    roundrect(panelX, panelY, panelW, panelH, 14, "line")
    love.graphics.setColor(1, 1, 1, 0.95)
    Render.outlinedPrintf("Achievements", panelX + 12, panelY + 12, panelW - 24, "center", 2)
    love.graphics.setColor(0.70, 0.76, 0.84, 0.8)
    Render.printf(#list .. " unlocked", panelX + 12, panelY + 36, panelW - 24, "center")

    local innerX, innerY = panelX + 12, panelY + 62
    local innerW, innerH = panelW - 24, panelH - 74
    love.graphics.setColor(0.04, 0.05, 0.07, 0.55)
    roundrect(innerX, innerY, innerW, innerH, 10)

    local scale, sox, soy = Hud.metrics()
    love.graphics.setScissor(sox + innerX * scale, soy + innerY * scale, innerW * scale, innerH * scale)

    if #list < 1 then
        love.graphics.setColor(0.62, 0.68, 0.76, 0.85)
        Render.printf("Play to unlock achievements.\nThey stay on this client.", innerX + 10, innerY + innerH * 0.38, innerW - 20, "center")
    else
        local cardH, gap = 86, 10
        local stride = cardH + gap
        local total = #list * stride
        local off = Achievements.scrollOffset() % total
        local copies = math.max(2, math.ceil(innerH / total) + 2)
        for copy = 0, copies - 1 do
            for i = 1, #list do
                local y = innerY + 8 + copy * total + (i - 1) * stride - off
                if y + cardH > innerY - 4 and y < innerY + innerH + 4 then
                    local a = list[i]
                    love.graphics.setColor(0.12, 0.16, 0.22, 0.96)
                    roundrect(innerX + 8, y, innerW - 16, cardH, 10)
                    love.graphics.setColor(0.16, 0.55, 0.85, 0.95)
                    love.graphics.rectangle("fill", innerX + 8, y, 4, cardH)
                    love.graphics.setColor(1, 1, 1, 0.96)
                    Render.outlinedPrintf(Render.safeText(a.name), innerX + 18, y + 10, innerW - 36, "left", 1)
                    love.graphics.setColor(0.78, 0.84, 0.90, 0.9)
                    Render.printf(Render.safeText(a.desc), innerX + 18, y + 36, innerW - 36, "left")
                end
            end
        end
    end
    love.graphics.setScissor()
end

local function wrapCount(text, width)
    local font = love.graphics.getFont()
    if not font or not text or text == "" then
        return 1
    end
    local _, lines = font:getWrap(text, width)
    return math.max(1, #lines)
end

local function drawChangelog(buttons, sw, sh)
    local list = Changelog.entries()
    local panelW = 268
    local panelX = 24
    local panelY = 82
    local panelH = sh - 118
    if panelH < 160 then
        Changelog.hide()
        return
    end

    Changelog.show(panelX, panelY, panelW, panelH)
    if buttons then
        box(buttons, panelX, panelY, panelW, panelH, function() end, "changelog", "arrow")
    end

    love.graphics.setColor(0.07, 0.08, 0.10, 0.72)
    roundrect(panelX, panelY, panelW, panelH, 14)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.setLineWidth(1.4)
    roundrect(panelX, panelY, panelW, panelH, 14, "line")
    love.graphics.setColor(1, 1, 1, 0.95)
    Render.outlinedPrintf("Changelog", panelX + 12, panelY + 12, panelW - 24, "center", 2)

    local innerX, innerY = panelX + 12, panelY + 48
    local innerW, innerH = panelW - 24, panelH - 60
    love.graphics.setColor(0.04, 0.05, 0.07, 0.55)
    roundrect(innerX, innerY, innerW, innerH, 10)

    local textW = innerW - 20
    local y = innerY + 10
    local blocks = {}
    for i = 1, #list do
        local e = list[i]
        local h = 0
        if e.date and e.date ~= "" then
            h = h + 22
        end
        local items = e.items or {}
        for j = 1, #items do
            h = h + wrapCount("• " .. items[j], textW) * 18
        end
        h = h + 12
        blocks[#blocks + 1] = { e = e, h = h, y = y }
        y = y + h
    end

    local contentH = y - (innerY + 10)
    Changelog.setMaxScroll(math.max(0, contentH - innerH + 16))
    local off = Changelog.scrollOffset()

    scissorGui(innerX, innerY, innerW, innerH)
    if #list < 1 then
        love.graphics.setColor(0.62, 0.68, 0.76, 0.85)
        Render.printf("No notes yet.", innerX + 10, innerY + innerH * 0.42, innerW - 20, "center")
    else
        for i = 1, #blocks do
            local b = blocks[i]
            local by = b.y - off
            if by + b.h > innerY - 4 and by < innerY + innerH + 4 then
                local e = b.e
                local iy = by
                if e.date and e.date ~= "" then
                    love.graphics.setColor(0.98, 0.82, 0.22, 0.95)
                    Render.outlinedPrintf(Render.safeText(e.date), innerX + 10, iy, textW, "left", 1)
                    iy = iy + 22
                end
                local items = e.items or {}
                for j = 1, #items do
                    local line = "• " .. items[j]
                    local lh = wrapCount(line, textW) * 18
                    love.graphics.setColor(0.84, 0.88, 0.93, 0.92)
                    Render.printf(Render.safeText(line), innerX + 10, iy, textW, "left")
                    iy = iy + lh
                end
            end
        end
    end
    love.graphics.setScissor()
end

local function drawHome(game, buttons, sw, sh, markHover, hoverScaleFn)
    if game.optionsOpen or game.treeOpen or game.paused then
        markHover = function() end
        hoverScaleFn = function(_, x, y, w, h) return x, y, w, h, 1 end
    end
    local a = math.min(1, 0.45 + anim.overlay * 0.9)
    love.graphics.setColor(0, 0, 0, 0.42 * a)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local fieldW = 420
    local fx = (sw - fieldW) / 2
    local fy = sh * 0.38
    local connecting = game.state == "connecting"
    local ready = game.ws and game.ws.state == "open"
    local modes = game.modes or Servers.fallback()
    local gap = 12
    local count = math.max(1, #modes)
    local cols = math.min(count, 4)
    local rows = math.ceil(count / cols)
    local extraH = (rows - 1) * 52

    love.graphics.setColor(0.07, 0.08, 0.10, 0.72 * a)
    local panelX, panelY, panelW, panelH = fx - 28, fy - 132, fieldW + 56, 448 + extraH
    roundrect(panelX, panelY, panelW, panelH, 18)

    love.graphics.push()
    love.graphics.translate(sw * 0.5, fy - 108)
    love.graphics.scale(1.85, 1.85)
    love.graphics.setColor(1, 1, 1, a)
    Render.printf("LoveDiep", -200, 0, 400, "center")
    love.graphics.pop()

    love.graphics.setColor(0.75, 0.82, 0.9, 0.9 * a)
    Render.printf("Gamemode", fx, fy - 58, fieldW, "center")

    local bw = (fieldW - gap * (cols - 1)) / cols
    for i = 1, #modes do
        local mode = modes[i]
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = fx + col * (bw + gap)
        local by = fy - 32 + row * 52
        local key = "mode" .. mode.id
        markHover(key, bx, by, bw, 44)
        local dx, dy, dw, dh = hoverScaleFn(key, bx, by, bw, 44)
        local selected = game.gamemode == mode.id
        local fr, fg, fb, fa
        if selected then
            fr, fg, fb, fa = 0.16, 0.55, 0.85, 0.96 * a
        else
            fr, fg, fb, fa = 0.18, 0.22, 0.28, 0.92 * a
        end
        love.graphics.setColor(fr, fg, fb, fa)
        roundrect(dx, dy, dw, dh, 10)
        buttonShadow(dx, dy, dw, dh, 10, a, key)
        buttonOutline(dx, dy, dw, dh, 10, a, fr, fg, fb)
        love.graphics.setColor(1, 1, 1, a)
        Render.outlinedPrintf(mode.label, dx, dy + 12, dw, "center", 2)
        buttonFlash(dx, dy, dw, dh, 10, key, a)
        local id = mode.id
        box(buttons, bx, by, bw, 44, function()
            game:selectGamemode(id)
        end, key)
    end

    local nameY = fy + 28 + extraH
    local focused = (game.focus or "spawnName") == "spawnName"
    markHover("spawnname", fx, nameY, fieldW, 44)
    if focused then
        love.graphics.setColor(1, 1, 1, 0.98 * a)
    else
        love.graphics.setColor(0.93, 0.95, 0.98, 0.92 * a)
    end
    roundrect(fx, nameY, fieldW, 44, 8)
    love.graphics.setColor(0.12, 0.13, 0.16, a)
    local name = txt(game.spawnName or "")
    if name == "" and not focused then
        love.graphics.setColor(0.45, 0.48, 0.52, a)
        Render.print("This is your name", fx + 14, nameY + 12)
    else
        local shown = name
        if focused then
            local raw = tostring(game.spawnName or "")
            local pos = game.caret or #raw
            if pos < 0 then pos = 0 elseif pos > #raw then pos = #raw end
            local mark = (love.timer.getTime() % 1 < 0.5) and "|" or ""
            shown = txt(raw:sub(1, pos)) .. mark .. txt(raw:sub(pos + 1))
        end
        Render.print(shown, fx + 14, nameY + 12)
    end
    box(buttons, fx, nameY, fieldW, 44, function()
        game:focusField("spawnName")
    end, "spawnname", "ibeam")

    local playY = nameY + 56
    markHover("spawnbtn", fx, playY, fieldW, 48)
    local sx, sy, swb, shb = hoverScaleFn("spawnbtn", fx, playY, fieldW, 48)
    local playLabel = "Play"
    local fr, fg, fb = 0.15, 0.55, 0.85
    if game.pendingSpawn then
        playLabel = "Spawning..."
        fr, fg, fb = 0.30, 0.32, 0.36
    elseif connecting then
        playLabel = "Connecting..."
        fr, fg, fb = 0.30, 0.32, 0.36
    end
    love.graphics.setColor(fr, fg, fb, a)
    roundrect(sx, sy, swb, shb, 10)
    buttonShadow(sx, sy, swb, shb, 10, a, "spawnbtn")
    buttonOutline(sx, sy, swb, shb, 10, a, fr, fg, fb)
    love.graphics.setColor(1, 1, 1, a)
    Render.outlinedPrintf(playLabel, sx, sy + 13, swb, "center", 2)
    buttonFlash(sx, sy, swb, shb, 10, "spawnbtn", a)
    box(buttons, fx, playY, fieldW, 48, function()
        game:play()
    end, "spawnbtn")

    local rowY = playY + 68
    love.graphics.setColor(0.7, 0.75, 0.82, 0.7 * a)
    Render.print("URL", fx, rowY - 18)

    local function smallField(key, x, y, w)
        local on = game.focus == key
        markHover(key, x, y, w, 32)
        if on then
            love.graphics.setColor(0.95, 0.97, 1, 0.9 * a)
        else
            love.graphics.setColor(0.82, 0.86, 0.9, 0.55 * a)
        end
        roundrect(x, y, w, 32, 6)
        love.graphics.setColor(0.1, 0.1, 0.12, a)
        local raw = tostring(game[key] or "")
        local pos = game.caret or #raw
        if pos < 0 then pos = 0 elseif pos > #raw then pos = #raw end
        local emptyHint = (key == "url" and raw == "" and not on)
        local value
        if emptyHint then
            love.graphics.setColor(0.45, 0.48, 0.52, a)
            value = "127.0.0.1:8080"
        elseif key == "password" then
            local mark = (on and love.timer.getTime() % 1 < 0.5) and "|" or ""
            value = string.rep("*", pos) .. (on and mark or "") .. string.rep("*", #raw - pos)
        elseif on then
            local mark = (love.timer.getTime() % 1 < 0.5) and "|" or ""
            value = txt(raw:sub(1, pos)) .. mark .. txt(raw:sub(pos + 1))
        else
            value = txt(raw)
        end
        local pad = 10
        local inner = w - pad * 2
        local font = love.graphics.getFont()
        local ox = 0
        if font and not emptyHint then
            local prefix = on and (key == "password" and string.rep("*", pos) or txt(raw:sub(1, pos))) or value
            local prefixW = font:getWidth(prefix)
            if prefixW > inner - 8 then
                ox = (inner - 8) - prefixW
            end
        end
        scissorGui(x + 8, y + 2, w - 16, 28)
        Render.print(value, x + pad + ox, y + 6)
        love.graphics.setScissor()
        box(buttons, x, y, w, 32, function()
            game:focusField(key)
        end, key, "ibeam")
    end
    smallField("url", fx, rowY, fieldW)

    love.graphics.setColor(0.7, 0.75, 0.82, 0.7 * a)
    Render.print("Dev password", fx, rowY + 42)
    smallField("password", fx, rowY + 60, fieldW)

    local statusY = rowY + 104
    local modeLabel = tostring(game.gamemode or "ffa")
    for i = 1, #modes do
        if modes[i].id == game.gamemode then
            modeLabel = modes[i].label
            break
        end
    end
    if game.error then
        love.graphics.setColor(1, 0.42, 0.42, a)
        Render.printf(txt(game.error), fx - 20, statusY, fieldW + 40, "center")
    elseif connecting then
        love.graphics.setColor(0.75, 0.82, 0.9, 0.8 * a)
        Render.printf("Joining " .. modeLabel .. "...", fx, statusY, fieldW, "center")
    elseif ready then
        love.graphics.setColor(0.62, 0.86, 0.70, 0.9 * a)
        Render.printf("Watching " .. modeLabel, fx, statusY, fieldW, "center")
    end
    love.graphics.setColor(0.62, 0.70, 0.78, 0.75 * a)
    Render.printf("Home  console   Y  tank tree   F11  fullscreen", fx, panelY + panelH - 28, fieldW, "center")

    local cogS = 44
    local cogX, cogY = sw - 22 - cogS, 22
    markHover("cog", cogX, cogY, cogS, cogS)
    local dx, dy, dw, dh = hoverScaleFn("cog", cogX, cogY, cogS, cogS)
    local open = game.optionsOpen
    local fr, fg, fb = 0.22, 0.26, 0.32
    if open then
        fr, fg, fb = 0.16, 0.55, 0.85
    end
    love.graphics.setColor(fr, fg, fb, 0.96 * a)
    roundrect(dx, dy, dw, dh, 10)
    buttonShadow(dx, dy, dw, dh, 10, a, "cog")
    buttonOutline(dx, dy, dw, dh, 10, a, fr, fg, fb)
    love.graphics.setColor(1, 1, 1, a)
    drawCogIcon(dx + dw * 0.5, dy + dh * 0.5, math.min(dw, dh) * 0.28)
    buttonFlash(dx, dy, dw, dh, 10, "cog", a)
    box(buttons, cogX, cogY, cogS, cogS, function()
        game.optionsOpen = not game.optionsOpen
        game.styleMenuOpen = false
        if game.optionsOpen then
            game.treeOpen = false
        end
    end, "cog")

    drawChangelog(buttons, sw, sh)
    drawAchievements(sw, sh)
end

local function drawPause(game, buttons, sw, sh, markHover, hoverScaleFn)
    if not game.paused or game.optionsOpen then return end
    Hud._lastHoverKey = ""
    box(buttons, 0, 0, sw, sh, function()
        game:resume()
    end, "pauseback", "arrow")

    local pw, ph = 420, 340
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setColor(0.08, 0.09, 0.12, 0.96)
    roundrect(px, py, pw, ph, 16)
    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.setLineWidth(1.6)
    roundrect(px, py, pw, ph, 16, "line")
    box(buttons, px, py, pw, ph, function() end, "pausepanel", "arrow")

    love.graphics.setColor(1, 1, 1, 1)
    Render.outlinedPrintf("Paused", px, py + 22, pw, "center", 2)

    local bx, bw, bh = px + 36, pw - 72, 44
    local function pauseBtn(key, y, label, fr, fg, fb, click)
        markHover(key, bx, y, bw, bh)
        local hx, hy, hw, hh = hoverScaleFn(key, bx, y, bw, bh)
        love.graphics.setColor(fr, fg, fb, 0.96)
        roundrect(hx, hy, hw, hh, 10)
        buttonShadow(hx, hy, hw, hh, 10, 1, key)
        buttonOutline(hx, hy, hw, hh, 10, 1, fr, fg, fb)
        love.graphics.setColor(1, 1, 1, 1)
        Render.outlinedPrintf(label, hx, hy + 12, hw, "center", 2)
        buttonFlash(hx, hy, hw, hh, 10, key, 1)
        box(buttons, bx, y, bw, bh, click, key)
    end

    pauseBtn("pauseresume", py + 90, "Resume", 0.16, 0.55, 0.85, function()
        game:resume()
    end)
    pauseBtn("pauseopts", py + 150, "Options", 0.16, 0.55, 0.85, function()
        game.optionsOpen = true
        game.styleMenuOpen = false
        game.treeOpen = false
    end)
    pauseBtn("pauseexit", py + 210, "Exit to Main Menu", 0.18, 0.22, 0.28, function()
        game:exitToMenu()
    end)
end

local function drawOptions(game, buttons, sw, sh, markHover, hoverScaleFn)
    if not game.optionsOpen then return end
    Hud._lastHoverKey = ""
    box(buttons, 0, 0, sw, sh, function()
        if game.styleMenuOpen then
            game.styleMenuOpen = false
        else
            game.optionsOpen = false
        end
    end, "optback", "arrow")

    local pw, ph = 420, 610
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setColor(0.08, 0.09, 0.12, 0.96)
    roundrect(px, py, pw, ph, 16)
    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.setLineWidth(1.6)
    roundrect(px, py, pw, ph, 16, "line")
    box(buttons, px, py, pw, ph, function()
        game.styleMenuOpen = false
    end, "optpanel", "arrow")

    love.graphics.setColor(1, 1, 1, 1)
    Render.outlinedPrintf("Options", px, py + 22, pw, "center", 2)

    love.graphics.setColor(0.72, 0.78, 0.86, 0.9)
    Render.print("Style", px + 36, py + 78)

    local style = "new"
    if Settings.style == "old" then
        style = "old"
    elseif Settings.style == "shaded" then
        style = "shaded"
    end
    local label = "New (default)"
    if style == "old" then
        label = "Old"
    elseif style == "shaded" then
        label = "3D"
    end
    local bx, by, bw, bh = px + 36, py + 104, pw - 72, 44
    markHover("style", bx, by, bw, bh)
    local dx, dy, dw, dh = hoverScaleFn("style", bx, by, bw, bh)
    local fr, fg, fb = 0.16, 0.55, 0.85
    love.graphics.setColor(fr, fg, fb, 0.96)
    roundrect(dx, dy, dw, dh, 10)
    buttonShadow(dx, dy, dw, dh, 10, 1, "style")
    buttonOutline(dx, dy, dw, dh, 10, 1, fr, fg, fb)
    love.graphics.setColor(1, 1, 1, 1)
    Render.outlinedPrintf(label, dx, dy + 12, dw, "center", 2)
    buttonFlash(dx, dy, dw, dh, 10, "style", 1)
    box(buttons, bx, by, bw, bh, function()
        game.styleMenuOpen = not game.styleMenuOpen
    end, "style")

    love.graphics.setColor(0.72, 0.78, 0.86, 0.9)
    Render.print("HUD Scale", px + 36, py + 168)
    local t, scaleVal = Settings.hudScaleT()
    local pct = string.format("%d%%", math.floor(scaleVal * 100 + 0.5))
    love.graphics.setColor(0.85, 0.90, 0.96, 0.95)
    Render.printf(pct, bx, py + 168, bw, "right")
    local minusX, rowY, btnS = bx, py + 194, 44
    local plusX = bx + bw - btnS
    local barX, barW = minusX + btnS + 10, bw - btnS * 2 - 20
    local barH = 16
    local barY = rowY + (btnS - barH) * 0.5

    local function scaleBtn(x, y, key, label, onClick)
        markHover(key, x, y, btnS, btnS)
        local hx, hy, hw, hh = hoverScaleFn(key, x, y, btnS, btnS)
        local rr, gg, bb = 0.16, 0.55, 0.85
        love.graphics.setColor(rr, gg, bb, 0.96)
        roundrect(hx, hy, hw, hh, 10)
        buttonShadow(hx, hy, hw, hh, 10, 1, key)
        buttonOutline(hx, hy, hw, hh, 10, 1, rr, gg, bb)
        love.graphics.setColor(1, 1, 1, 1)
        Render.outlinedPrintf(label, hx, hy + 12, hw, "center", 2)
        buttonFlash(hx, hy, hw, hh, 10, key, 1)
        box(buttons, x, y, btnS, btnS, function()
            game.styleMenuOpen = false
            onClick()
        end, key)
    end
    local function drawBar(barX, barY, barW, barH, t, storeKey, dragKey, onBegin)
        love.graphics.setColor(0.14, 0.16, 0.20, 0.96)
        roundrect(barX, barY, barW, barH, 8)
        love.graphics.setColor(0.16, 0.55, 0.85, 0.95)
        local fillW = math.max(8, barW * t)
        roundrect(barX, barY, fillW, barH, 8)
        love.graphics.setColor(1, 1, 1, 0.95)
        local knobW = 14
        local knobX = barX + (barW - knobW) * t
        roundrect(knobX, barY - 4, knobW, barH + 8, 6)
        game[storeKey] = { x = barX, y = barY - 8, w = barW, h = barH + 16 }
        box(buttons, barX, barY - 8, barW, barH + 16, function()
            game.styleMenuOpen = false
            game[dragKey] = true
            onBegin()
        end, dragKey, "hand")
    end

    scaleBtn(minusX, rowY, "hudminus", "-", function()
        Settings.nudgeHudScale(-1)
    end)
    scaleBtn(plusX, rowY, "hudplus", "+", function()
        Settings.nudgeHudScale(1)
    end)
    drawBar(barX, barY, barW, barH, t, "_hudScaleBar", "hudScaleDrag", function()
        local gx = Hud.screenToGui(love.mouse.getPosition())
        Settings.setHudScaleFromBar(gx, game._hudScaleBar)
    end)

    love.graphics.setColor(0.72, 0.78, 0.86, 0.9)
    Render.print("3D Depth", px + 36, py + 258)
    local st, shadowVal = Settings.innerShadowT()
    local spct = string.format("%d%%", math.floor(shadowVal * 100 + 0.5))
    love.graphics.setColor(0.85, 0.90, 0.96, 0.95)
    Render.printf(spct, bx, py + 258, bw, "right")
    local sRowY = py + 284
    local sBarY = sRowY + (btnS - barH) * 0.5
    scaleBtn(minusX, sRowY, "shadminus", "-", function()
        Settings.nudgeInnerShadow(-1)
        Render.setInnerShadow(Settings.innerShadow)
    end)
    scaleBtn(plusX, sRowY, "shadplus", "+", function()
        Settings.nudgeInnerShadow(1)
        Render.setInnerShadow(Settings.innerShadow)
    end)
    drawBar(barX, sBarY, barW, barH, st, "_innerShadowBar", "innerShadowDrag", function()
        local gx = Hud.screenToGui(love.mouse.getPosition())
        Settings.setInnerShadowFromBar(gx, game._innerShadowBar)
        Render.setInnerShadow(Settings.innerShadow)
    end)

    love.graphics.setColor(0.72, 0.78, 0.86, 0.9)
    Render.print("FPS Counter", px + 36, py + 348)
    local fpsOn = Settings.showFps == true
    local fpsLabel = fpsOn and "On" or "Off"
    local fx, fy, fw, fh = bx, py + 374, bw, 44
    markHover("showfps", fx, fy, fw, fh)
    local hx, hy, hw, hh = hoverScaleFn("showfps", fx, fy, fw, fh)
    local fpr, fpg, fpb = fpsOn and 0.16 or 0.18, fpsOn and 0.55 or 0.22, fpsOn and 0.85 or 0.28
    love.graphics.setColor(fpr, fpg, fpb, 0.96)
    roundrect(hx, hy, hw, hh, 10)
    buttonShadow(hx, hy, hw, hh, 10, 1, "showfps")
    buttonOutline(hx, hy, hw, hh, 10, 1, fpr, fpg, fpb)
    love.graphics.setColor(1, 1, 1, 1)
    Render.outlinedPrintf(fpsLabel, hx, hy + 12, hw, "center", 2)
    buttonFlash(hx, hy, hw, hh, 10, "showfps", 1)
    box(buttons, fx, fy, fw, fh, function()
        game.styleMenuOpen = false
        Settings.setShowFps(not Settings.showFps)
    end, "showfps")

    local closeY = py + ph - 70
    markHover("optclose", bx, closeY, bw, 44)
    local cx, cy, cw, ch = hoverScaleFn("optclose", bx, closeY, bw, 44)
    local cr, cg, cb = 0.18, 0.22, 0.28
    love.graphics.setColor(cr, cg, cb, 0.96)
    roundrect(cx, cy, cw, ch, 10)
    buttonShadow(cx, cy, cw, ch, 10, 1, "optclose")
    buttonOutline(cx, cy, cw, ch, 10, 1, cr, cg, cb)
    love.graphics.setColor(1, 1, 1, 1)
    Render.outlinedPrintf("Close", cx, cy + 12, cw, "center", 2)
    buttonFlash(cx, cy, cw, ch, 10, "optclose", 1)
    box(buttons, bx, closeY, bw, 44, function()
        game.optionsOpen = false
        game.styleMenuOpen = false
    end, "optclose")

    if game.styleMenuOpen then
        local opts = {
            { id = "new", label = "New (default)" },
            { id = "shaded", label = "3D" },
            { id = "old", label = "Old" }
        }
        local dropY = by + bh + 6
        local dropH = #opts * 40 + 8
        love.graphics.setColor(0.10, 0.12, 0.16, 0.98)
        roundrect(bx, dropY, bw, dropH, 10)
        love.graphics.setColor(1, 1, 1, 0.10)
        roundrect(bx, dropY, bw, dropH, 10, "line")
        for i = 1, #opts do
            local oy = dropY + 4 + (i - 1) * 40
            local key = "style" .. opts[i].id
            markHover(key, bx + 6, oy, bw - 12, 36)
            local hx, hy, hw, hh = hoverScaleFn(key, bx + 6, oy, bw - 12, 36)
            local selected = style == opts[i].id
            if selected then
                love.graphics.setColor(0.16, 0.55, 0.85, 0.9)
                roundrect(hx, hy, hw, hh, 8)
            end
            love.graphics.setColor(1, 1, 1, 1)
            Render.outlinedPrintf(opts[i].label, hx, hy + 8, hw, "center", 1)
            local sid = opts[i].id
            box(buttons, bx + 6, oy, bw - 12, 36, function()
                Settings.setStyle(sid)
                Render.setStyle(sid)
                game.styleMenuOpen = false
            end, key)
        end
    end
end

local boardBars = {}

local function drawScoreboard(game, arena, sw, buttons, markHover, hoverScaleFn)
    if not arena then return end
    local n = tonumber(arena.scoreboardAmount) or 0
    if n ~= n or n < 0 then n = 0 end
    if n > 10 then n = 10 end
    n = math.floor(n)
    if n < 1 then
        boardBars = {}
        return
    end

    local names = arena.scoreboardNames or {}
    local scores = arena.scoreboardScores or {}
    local colors = arena.scoreboardColors or {}
    local suffixes = arena.scoreboardSuffixes or {}
    local mine = txt(game.spawnName or ""):lower()

    local w = 252
    local x = sw - 16 - w
    local y = 14
    local rowH, gap = 22, 3
    local head = 26
    local h = head + n * (rowH + gap) + 10
    box(buttons, x, y, w, h, function() end, "scoreboard", "arrow")

    love.graphics.setColor(0.06, 0.07, 0.09, 0.72)
    roundrect(x, y, w, h, 12)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.setLineWidth(1.4)
    roundrect(x, y, w, h, 12, "line")

    love.graphics.setColor(0.70, 0.76, 0.84, 0.72)
    love.graphics.push()
    love.graphics.translate(x + 12, y + 9)
    love.graphics.scale(0.7, 0.7)
    Render.print("SCOREBOARD", 0, 0)
    love.graphics.pop()
    if game.playerCount then
        love.graphics.setColor(0.52, 0.60, 0.68, 0.8)
        love.graphics.push()
        love.graphics.translate(x + w - 12, y + 9)
        love.graphics.scale(0.7, 0.7)
        Render.printf(tostring(game.playerCount), -80, 0, 80, "right")
        love.graphics.pop()
    end

    local top = tonumber(scores[0]) or 0
    if top < 1 then top = 1 end
    local dt = math.min(love.timer.getDelta() or 0.016, 0.05)
    local follow = 1 - math.exp(-dt * 11)

    for i = 0, n - 1 do
        local rawName = names[i]
        if type(rawName) ~= "string" then rawName = "" end
        rawName = txt(rawName)
        local label = rawName
        if label == "" then label = "unnamed" end
        local suffix = suffixes[i]
        if type(suffix) == "string" and suffix ~= "" then
            label = label .. txt(suffix)
        end
        local score = tonumber(scores[i]) or 0
        if score ~= score then score = 0 end
        local ratio = math.max(0.1, math.min(1, score / top))
        boardBars[i] = (boardBars[i] or 0) + (ratio - (boardBars[i] or 0)) * follow
        local fill = boardBars[i]
        local col = Enums.ColorsHexCode[colors[i] or 13] or 0x43FF91
        local cr, cg, cb = Render.hex(col)
        local selfRow = mine ~= "" and rawName:lower() == mine
        local rx, ry = x + 8, y + head + i * (rowH + gap)
        local rw, rh = w - 16, rowH
        local key = "sb" .. tostring(i)
        markHover(key, rx, ry, rw, rh)
        local dx, dy, dw, dh = hoverScaleFn(key, rx, ry, rw, rh)

        love.graphics.setColor(0.10, 0.11, 0.14, 0.62)
        roundrect(dx, dy, dw, dh, 6)
        if dw * fill > 3 then
            love.graphics.stencil(function()
                roundrect(dx, dy, dw, dh, 6)
            end, "replace", 1)
            love.graphics.setStencilTest("equal", 1)
            love.graphics.setColor(cr, cg, cb, selfRow and 0.78 or 0.50)
            Render.drawWaveFill(dx, dy, dw, dh, fill)
            love.graphics.setStencilTest()
        end
        if selfRow then
            love.graphics.setColor(1, 1, 1, 0.22)
            love.graphics.setLineWidth(1.4)
            roundrect(dx, dy, dw, dh, 6, "line")
        end

        if i == 0 then
            love.graphics.setColor(1.00, 0.84, 0.28, 0.95)
        elseif i == 1 then
            love.graphics.setColor(0.80, 0.86, 0.92, 0.95)
        elseif i == 2 then
            love.graphics.setColor(0.90, 0.62, 0.36, 0.95)
        else
            love.graphics.setColor(1, 1, 1, 0.38)
        end
        Render.print(tostring(i + 1), dx + 6, dy + 3)

        local scoreText = formatScore(score)
        love.graphics.setColor(1, 1, 1, 0.90)
        Render.printf(scoreText, dx, dy + 3, dw - 8, "right")

        scissorGui(dx + 22, dy, dw - 70, dh)
        love.graphics.setColor(1, 1, 1, selfRow and 1 or 0.92)
        Render.outlinedPrint(label, dx + 24, dy + 3, 2)
        love.graphics.setScissor()
    end
    for i = n, 9 do
        boardBars[i] = nil
    end
end

local function drawCountdown(game, arena, sw, sh)
    local a = math.min(1, 0.55 + anim.overlay * 2)
    love.graphics.setColor(0, 0, 0, 0.58 * a)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local ticks = tonumber(arena and arena.ticksUntilStart) or 0
    if ticks ~= ticks then ticks = 0 end
    local seconds = math.max(0, math.ceil(ticks * 0.04 - 1e-6))
    local needed = math.max(0, math.floor(tonumber(arena and arena.playersNeeded) or 0))

    local cx, cy = sw * 0.5, sh * 0.42
    love.graphics.setColor(1, 1, 1, 0.92 * a)
    if needed > 0 then
        local who = needed == 1 and "player" or "players"
        Render.printf("Waiting for " .. tostring(needed) .. " more " .. who, 0, cy - 92, sw, "center")
    end
    Render.printf("This game is starting in", 0, cy - 48, sw, "center")

    local pulse = 0.97 + 0.03 * math.sin((love.timer.getTime() or 0) * 6)
    love.graphics.push()
    love.graphics.translate(cx, cy + 36)
    love.graphics.scale(4.4 * pulse, 4.4 * pulse)
    love.graphics.setColor(1, 1, 1, a)
    Render.printf(tostring(seconds), -80, -12, 160, "center")
    love.graphics.pop()

    love.graphics.setColor(0.75, 0.80, 0.86, 0.7 * a)
    Render.printf("Esc to pause", 0, cy + 118, sw, "center")
end

function Hud.draw(game)
    Changelog.hide()
    while love.graphics.getStackDepth() > 0 do
        love.graphics.pop()
    end
    love.graphics.origin()
    love.graphics.setLineWidth(1)
    love.graphics.setStencilTest()
    love.graphics.setShader()

    local _, _, _, vw, vh = Hud.push()

    local buttons = {}
    local world = game.world
    local cam = world:cameraValues()
    local arena = world:arenaValues()
    local sw, sh = vw, vh
    local player = world:player()
    local spawned = world:isSpawned()
    local waiting = world:isWaitingStart()
    if world._respawned then
        Hud.resetMap()
        world._respawned = false
    end
    if not spawned then
        anim.tankShow = 0
        anim.statShow = 0
    end
    local mx, my = Hud.screenToGui(love.mouse.getPosition())
    Hud._lastHoverKey = ""
    Hud._wantTank = false
    Hud._wantStat = false
    local overlayOpen = game.optionsOpen or game.treeOpen or game.paused

    local function markHoverAll(key, x, y, w, h)
        if mx >= x - 6 and my >= y - 6 and mx <= x + w + 6 and my <= y + h + 6 then
            Hud._lastHoverKey = key
        end
    end

    local function markHover(key, x, y, w, h)
        if overlayOpen then return end
        markHoverAll(key, x, y, w, h)
    end

    local function frozenScale(_, x, y, w, h)
        return x, y, w, h, 1
    end
    local underScale = overlayOpen and frozenScale or hoverScale

    local function overRect(x, y, w, h, pad)
        pad = pad or 10
        return mx >= x - pad and my >= y - pad and mx <= x + w + pad and my <= y + h + pad
    end

    if game.treeOpen then
        TankTree.draw(game, buttons, sw, sh, box)
        Console.draw(game, buttons, sw, sh, box)
        if Settings.showFps then
            local fps = love.timer.getFPS()
            local label = string.format("%d FPS", fps)
            love.graphics.setColor(0, 0, 0, 0.48)
            roundrect(10, 8, 92, 28, 8)
            love.graphics.setColor(1, 1, 1, 0.96)
            Render.outlinedPrintf(label, 10, 13, 92, "center", 2)
        end
        love.graphics.pop()
        return buttons
    end

    if game.notifications then
        local y = 72
        for i = #game.notifications, 1, -1 do
            local n = game.notifications[i]
            if love.timer.getTime() > n.untilTime then
                table.remove(game.notifications, i)
            else
                local life = n.untilTime - love.timer.getTime()
                local fade = math.min(1, life * 3, 1)
                local slide = easeOut(math.min(1, (4 - math.min(4, life)) * 4))
                love.graphics.setColor(0, 0, 0, 0.55 * fade)
                roundrect(sw / 2 - 220, y - 10 * (1 - slide), 440, 36, 8)
                love.graphics.setColor(1, 1, 1, fade)
                Render.printf(txt(n.text), sw / 2 - 210, y + 8 - 10 * (1 - slide), 420, "center")
                y = y + 44
            end
        end
    end

    local tankId = math.floor(tonumber(cam and cam.tank) or 0)
    if tankId == 53 then tankId = 0 end
    local def = game.tanksById[tankId]
    local upgradeList = {}
    local upgradeHits = {}
    local level = math.floor(tonumber(cam and cam.level) or 1)
    if def and def.upgrades and spawned then
        local seen = {}
        local function addUpgrade(uid)
            uid = tonumber(uid)
            if not uid or seen[uid] then return end
            local ud = game.tanksById[uid]
            if type(ud) ~= "table" or not ud.name or ud.name == "" then return end
            if ud.flags and ud.flags.devOnly then return end
            seen[uid] = true
            upgradeList[#upgradeList + 1] = { id = uid, def = ud }
        end
        for i = 1, #def.upgrades do
            addUpgrade(def.upgrades[i])
        end
        if #upgradeList == 0 then
            for _, uid in pairs(def.upgrades) do
                addUpgrade(uid)
            end
        end
    end
    if #upgradeList == 0 then
        anim.up = 0
        anim.tankShow = 0
    end
    if #upgradeList > 0 then
        local size, gap, ox, oy = 84, 8, 12, 12
        local cols = 2
        local rows = math.ceil(#upgradeList / 2)
        local panelW = cols * size + (cols - 1) * gap
        local panelH = rows * size + (rows - 1) * gap
        local canUpgrade = false
        for i = 1, #upgradeList do
            local req = tonumber(upgradeList[i].def.levelRequirement) or 0
            if level >= req then
                canUpgrade = true
                break
            end
        end
        Hud._wantTank = canUpgrade or overRect(ox, oy, panelW, panelH, 16)
        anim.tankShow = followShow(anim.tankShow, Hud._wantTank)
        local show = easeOut(anim.tankShow)
        local slide = (1 - show) * (panelW + ox + 28)
        if show > 0.01 then
            local px = ox - slide
            love.graphics.setColor(0.06, 0.07, 0.09, 0.42 * show)
            roundrect(px - 8, oy - 8, panelW + 16, panelH + 16, 12)
            if show > 0.2 then
                box(buttons, px - 8, oy - 8, panelW + 16, panelH + 16, function() end, "tanks", "arrow")
            end
            for i = 1, #upgradeList do
                local col = (i - 1) % 2
                local row = math.floor((i - 1) / 2)
                local x = px + col * (size + gap)
                local y = oy + row * (size + gap)
                local key = "up" .. tostring(upgradeList[i].id)
                if show > 0.55 then
                    markHover(key, x, y, size, size)
                end
                local dx, dy, dw, dh = hoverScale(key, x, y, size, size)
                local ud = upgradeList[i].def
                local req = tonumber(ud.levelRequirement) or 0
                local can = level >= req
                local fr, fg, fb, fa
                if can then
                    fr, fg, fb, fa = 0.10, 0.48, 0.28, 0.55 + 0.37 * show
                else
                    fr, fg, fb, fa = 0.16, 0.16, 0.18, 0.55 * show
                end
                love.graphics.setColor(fr, fg, fb, fa)
                roundrect(dx, dy, dw, dh, 10)
                buttonShadow(dx, dy, dw, dh, 10, show, key)
                buttonOutline(dx, dy, dw, dh, 10, show, fr, fg, fb)
                scissorGui(dx + 4, dy + 4, dw - 8, dh - 22)
                Render.drawTankIcon(ud, dx + dw * 0.5, dy + dh * 0.42, dw - 18, show * (can and 1 or 0.45))
                love.graphics.setScissor()
                love.graphics.setColor(1, 1, 1, show)
                love.graphics.push()
                love.graphics.translate(dx, dy + dh - 18)
                love.graphics.scale(0.72, 0.72)
                Render.outlinedPrintf(txt(ud.name or ("Tank " .. tostring(upgradeList[i].id))), 0, 0, dw / 0.72, "center", 3)
                love.graphics.pop()
                if not can then
                    love.graphics.setColor(0, 0, 0, 0.4 * show)
                    roundrect(dx, dy, dw, dh, 10)
                    love.graphics.setColor(1, 1, 1, 0.95 * show)
                    Render.outlinedPrintf("Lv " .. tostring(req), dx, dy + dh * 0.38, dw, "center", 2)
                end
                buttonFlash(dx, dy, dw, dh, 10, key, show)
                if show > 0.75 then
                    upgradeHits[#upgradeHits + 1] = {
                        x = x, y = y, w = size, h = size, key = key, can = can, id = upgradeList[i].id
                    }
                end
            end
        end
    end

    if spawned and cam then
        local camEnt = world.camera
        drawXpHud(game, cam, camEnt, sw, sh, buttons)

        local statsX, statsW = 16, 228
        local rowH = 26
        local headerH = 24
        local statsY = sh - 250
        local statRows = {}
        for i = 0, 7 do
            local names = cam.statNames
            local name = names and names[i]
            if type(name) == "string" and name ~= "" then
                statRows[#statRows + 1] = i
            end
        end
        if #statRows == 0 then
            anim.statShow = 0
        else
            local panelY = statsY - headerH
            local panelH = headerH + #statRows * rowH
            local havePts = (tonumber(cam.statsAvailable) or 0) > 0
            Hud._wantStat = havePts or overRect(statsX, panelY, statsW, panelH, 14)
            anim.statShow = followShow(anim.statShow, Hud._wantStat)
            local show = easeOut(anim.statShow)
            local slide = (1 - show) * (statsW + statsX + 28)
            if show > 0.01 then
                local px = statsX - slide
                love.graphics.setColor(0.06, 0.07, 0.09, 0.5 * show)
                roundrect(px - 8, panelY - 6, statsW + 16, panelH + 12, 12)
                love.graphics.setColor(1, 1, 1, 0.08 * show)
                love.graphics.setLineWidth(1.4)
                roundrect(px - 8, panelY - 6, statsW + 16, panelH + 12, 12, "line")
                if show > 0.2 then
                    box(buttons, px - 8, panelY - 6, statsW + 16, panelH + 12, function() end, "stats", "arrow")
                end
                if havePts then
                    local pulse = 0.55 + 0.45 * math.sin(anim.pulse * 6)
                    love.graphics.setColor(1, 1, 1, (0.55 + 0.45 * pulse) * show)
                    Render.print("Stat points: " .. tostring(cam.statsAvailable), px, panelY)
                else
                    love.graphics.setColor(0.70, 0.76, 0.84, 0.72 * show)
                    Render.print("STATS", px, panelY)
                end
                for r = 1, #statRows do
                    local i = statRows[r]
                    local name = txt(cam.statNames[i])
                    local level = tonumber(cam.statLevels and cam.statLevels[i]) or 0
                    local shown = (camEnt and camEnt.istat and camEnt.istat[i]) or level
                    local limit = tonumber(cam.statLimits and cam.statLimits[i]) or 7
                    if level ~= level then level = 0 end
                    if limit ~= limit then limit = 7 end
                    local x, y = px, statsY + (r - 1) * rowH
                    local can = havePts and level < limit
                    local fillR = (limit > 0) and math.max(0, math.min(1, (tonumber(shown) or 0) / limit)) or 0
                    local key = "stat" .. tostring(i)
                    if show > 0.55 then
                        markHover(key, x, y, statsW, 24)
                    end
                    local dx, dy, dw, dh = hoverScale(key, x, y, statsW, 22)
                    outlinedBar(dx, dy, dw, dh, fillR, statFill(i, can), 5, show)
                    love.graphics.setColor(1, 1, 1, show)
                    Render.print(name .. "  " .. tostring(math.floor(level)) .. "/" .. tostring(math.floor(limit)), dx + 8, dy + 3)
                    buttonFlash(dx, dy, dw, dh, 5, key, show)
                    if show > 0.75 then
                        local statId = i
                        box(buttons, x, y, statsW, 26, function()
                            if can then
                                game:send(Encode.statUpgrade(statId))
                            end
                        end, key)
                    end
                end
            end
        end
    end

    if spawned then
        drawMatchInfo(game, cam, sw, sh, buttons)
        drawMinimap(game, world, arena, player, cam, sw, sh, buttons)
    end

    local showingDeath = world:isDead()
    if showingDeath then
        local a = math.min(1, 0.55 + anim.overlay * 3)
        love.graphics.setColor(0, 0, 0, 0.55 * a)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1, a)
        Render.printf("You were killed" .. ((cam.killedBy and cam.killedBy ~= "") and (" by " .. txt(cam.killedBy)) or ""), 0, sh / 2 - 40, sw, "center")
        Render.printf("Click or press Enter to continue", 0, sh / 2, sw, "center")
        box(buttons, 0, 0, sw, sh, function()
            game:send(Encode.toRespawn())
        end, "death")
    elseif waiting then
        local okCount, errCount = pcall(drawCountdown, game, arena, sw, sh)
        if not okCount then
            print("[LoveDiepClient] countdown: " .. tostring(errCount))
        end
    elseif not spawned then
        local okHome, errHome = pcall(drawHome, game, buttons, sw, sh, markHover, underScale)
        if not okHome then
            print("[LoveDiepClient] menu: " .. tostring(errHome))
        end
    end

    local okBoard, errBoard = pcall(drawScoreboard, game, arena, sw, buttons, markHover, underScale)
    if not okBoard then
        print("[LoveDiepClient] scoreboard: " .. tostring(errBoard))
    end

    for i = 1, #upgradeHits do
        local u = upgradeHits[i]
        box(buttons, u.x, u.y, u.w, u.h, function()
            game:queueTankUpgrade(u.id)
        end, u.key)
    end

    Console.draw(game, buttons, sw, sh, box)
    drawPause(game, buttons, sw, sh, markHoverAll, hoverScale)
    drawOptions(game, buttons, sw, sh, markHoverAll, hoverScale)
    TankTree.draw(game, buttons, sw, sh, box, markHover, hoverScale)

    if Settings.showFps then
        local fps = love.timer.getFPS()
        local label = string.format("%d FPS", fps)
        love.graphics.setColor(0, 0, 0, 0.48)
        roundrect(10, 8, 92, 28, 8)
        love.graphics.setColor(1, 1, 1, 0.96)
        Render.outlinedPrintf(label, 10, 13, 92, "center", 2)
    end

    love.graphics.pop()
    return buttons
end

return Hud
