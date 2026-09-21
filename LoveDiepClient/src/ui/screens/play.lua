local bit = require("bit")
local Render = require("src.render")
local W = require("src.ui.widgets")
local PhysicsFlags = W.PhysicsFlags
local NameFlags = W.NameFlags
local box = W.box
local roundrect = W.roundrect
local txt = W.txt
local caption = W.caption
local outlinedBar = W.outlinedBar
local scissorGui = W.scissorGui
local formatScore = W.formatScore
local mapRect = W.mapRect
local modeTitle = W.modeTitle
local currentTankName = W.currentTankName

local M = {}
function M.drawMatchInfo(game, cam, sw, sh, buttons)
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

function M.drawXpHud(game, cam, camEnt, sw, sh, buttons)
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

function M.drawMinimap(game, world, arena, player, cam, sw, sh, buttons)
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
    local _, vw, vh = Render.viewMetrics(fov)
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
        if W.anim.mapX == 0 and W.anim.mapY == 0 then
            W.anim.mapX, W.anim.mapY, W.anim.mapA = tx, ty, ta
        else
            W.anim.mapX = W.anim.mapX + (tx - W.anim.mapX) * follow
            W.anim.mapY = W.anim.mapY + (ty - W.anim.mapY) * follow
            local d = ta - W.anim.mapA
            while d > math.pi do d = d - math.pi * 2 end
            while d < -math.pi do d = d + math.pi * 2 end
            W.anim.mapA = W.anim.mapA + d * follow
        end
        local px, py = toMap(W.anim.mapX, W.anim.mapY)
        love.graphics.push()
        love.graphics.translate(px, py)
        love.graphics.rotate(W.anim.mapA)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.polygon("fill", 7, 0, -5, -4.5, -5, 4.5)
        love.graphics.setColor(0.05, 0.05, 0.05, 1)
        love.graphics.setLineWidth(1.4)
        love.graphics.polygon("line", 7, 0, -5, -4.5, -5, 4.5)
        love.graphics.pop()
    end
    love.graphics.setScissor()
end

function M.drawCountdown(game, arena, sw, sh)
    local a = math.min(1, 0.55 + W.anim.overlay * 2)
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
return M
