local Encode = require("src.protocol.encode")
local Render = require("src.render")
local Console = require("src.ui.console")
local Settings = require("src.ui.settings")
local TankTree = require("src.ui.tanktree")
local Changelog = require("src.data.changelog")
local State = require("src.ui.state")
local Layout = require("src.ui.layout")
local W = require("src.ui.widgets")
local Home = require("src.ui.screens.home")
local Pause = require("src.ui.screens.pause")
local Options = require("src.ui.screens.options")
local Scoreboard = require("src.ui.screens.scoreboard")
local Play = require("src.ui.screens.play")

local Hud = {}
Hud.GUI_W = Layout.GUI_W
Hud.GUI_H = Layout.GUI_H
Hud.metrics = Layout.metrics
Hud.screenToGui = Layout.screenToGui
Hud.push = Layout.push

function Hud.update(dt)
    dt = math.min(dt or 0.016, 0.05)
    local a = 1 - math.exp(-dt * 12)
    local mx, my = love.mouse.getPosition()
    mx, my = Hud.screenToGui(mx, my)
    local anim = State.anim
    local over = State.lastHoverKey or ""
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
    local presses = State.presses
    for key, p in pairs(presses) do
        p.flash = p.flash * math.exp(-dt * 9)
        if held and State.holdKey == key then
            p.down = 1
        else
            p.down = p.down * math.exp(-dt * 14)
        end
        if p.flash < 0.02 and p.down < 0.02 then
            presses[key] = nil
        end
    end
    if not held then
        State.holdKey = nil
    end
end

function Hud.resetMap()
    State.resetMap()
end

function Hud.over(buttons, x, y)
    if not buttons then return false end
    for i = #buttons, 1, -1 do
        if W.inRect(buttons[i], x, y, 6) then
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
    State.presses[key] = { flash = 1, down = 1 }
    State.holdKey = key
end

function Hud.holdPress(key)
    if key == nil then return end
    local p = State.presses[key]
    if not p then
        State.presses[key] = { flash = 0, down = 1 }
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

function Hud.draw(game)
    Changelog.hide()
    while love.graphics.getStackDepth() > 0 do
        love.graphics.pop()
    end
    love.graphics.origin()
    love.graphics.setLineWidth(1)
    love.graphics.setStencilTest()
    love.graphics.setShader()

    local _, _, _, vw, vh = Layout.push()

    local buttons = {}
    local world = game.world
    local cam = world:cameraValues()
    local arena = world:arenaValues()
    local sw, sh = vw, vh
    local player = world:player()
    local spawned = world:isSpawned()
    local waiting = world:isWaitingStart()
    if world._respawned then
        State.resetMap()
        world._respawned = false
    end
    if not spawned then
        State.anim.tankShow = 0
        State.anim.statShow = 0
    end
    local mx, my = Layout.screenToGui(love.mouse.getPosition())
    State.lastHoverKey = ""
    State.wantTank = false
    State.wantStat = false
    local overlayOpen = game.optionsOpen or game.treeOpen or game.paused

    local function markHoverAll(key, x, y, w, h)
        if mx >= x - 6 and my >= y - 6 and mx <= x + w + 6 and my <= y + h + 6 then
            State.lastHoverKey = key
        end
    end

    local function markHover(key, x, y, w, h)
        if overlayOpen then return end
        markHoverAll(key, x, y, w, h)
    end

    local function frozenScale(_, x, y, w, h)
        return x, y, w, h, 1
    end
    local underScale = overlayOpen and frozenScale or W.hoverScale

    local function overRect(x, y, w, h, pad)
        pad = pad or 10
        return mx >= x - pad and my >= y - pad and mx <= x + w + pad and my <= y + h + pad
    end

    if game.treeOpen then
        TankTree.draw(game, buttons, sw, sh, W.box)
        Console.draw(game, buttons, sw, sh, W.box)
        if Settings.showFps then
            local fps = love.timer.getFPS()
            local label = string.format("%d FPS", fps)
            love.graphics.setColor(0, 0, 0, 0.48)
            W.roundrect(10, 8, 92, 28, 8)
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
                local slide = W.easeOut(math.min(1, (4 - math.min(4, life)) * 4))
                love.graphics.setColor(0, 0, 0, 0.55 * fade)
                W.roundrect(sw / 2 - 220, y - 10 * (1 - slide), 440, 36, 8)
                love.graphics.setColor(1, 1, 1, fade)
                Render.printf(W.txt(n.text), sw / 2 - 210, y + 8 - 10 * (1 - slide), 420, "center")
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
        State.anim.up = 0
        State.anim.tankShow = 0
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
        State.wantTank = canUpgrade or overRect(ox, oy, panelW, panelH, 16)
        State.anim.tankShow = W.followShow(State.anim.tankShow, State.wantTank)
        local show = W.easeOut(State.anim.tankShow)
        local slide = (1 - show) * (panelW + ox + 28)
        if show > 0.01 then
            local px = ox - slide
            love.graphics.setColor(0.06, 0.07, 0.09, 0.42 * show)
            W.roundrect(px - 8, oy - 8, panelW + 16, panelH + 16, 12)
            if show > 0.2 then
                W.box(buttons, px - 8, oy - 8, panelW + 16, panelH + 16, function() end, "tanks", "arrow")
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
                local dx, dy, dw, dh = W.hoverScale(key, x, y, size, size)
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
                W.roundrect(dx, dy, dw, dh, 10)
                W.buttonShadow(dx, dy, dw, dh, 10, show, key)
                W.buttonOutline(dx, dy, dw, dh, 10, show, fr, fg, fb)
                W.scissorGui(dx + 4, dy + 4, dw - 8, dh - 22)
                Render.drawTankIcon(ud, dx + dw * 0.5, dy + dh * 0.42, dw - 18, show * (can and 1 or 0.45))
                love.graphics.setScissor()
                love.graphics.setColor(1, 1, 1, show)
                love.graphics.push()
                love.graphics.translate(dx, dy + dh - 18)
                love.graphics.scale(0.72, 0.72)
                Render.outlinedPrintf(W.txt(ud.name or ("Tank " .. tostring(upgradeList[i].id))), 0, 0, dw / 0.72, "center", 3)
                love.graphics.pop()
                if not can then
                    love.graphics.setColor(0, 0, 0, 0.4 * show)
                    W.roundrect(dx, dy, dw, dh, 10)
                    love.graphics.setColor(1, 1, 1, 0.95 * show)
                    Render.outlinedPrintf("Lv " .. tostring(req), dx, dy + dh * 0.38, dw, "center", 2)
                end
                W.buttonFlash(dx, dy, dw, dh, 10, key, show)
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
        Play.drawXpHud(game, cam, camEnt, sw, sh, buttons)

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
            State.anim.statShow = 0
        else
            local panelY = statsY - headerH
            local panelH = headerH + #statRows * rowH
            local havePts = (tonumber(cam.statsAvailable) or 0) > 0
            State.wantStat = havePts or overRect(statsX, panelY, statsW, panelH, 14)
            State.anim.statShow = W.followShow(State.anim.statShow, State.wantStat)
            local show = W.easeOut(State.anim.statShow)
            local slide = (1 - show) * (statsW + statsX + 28)
            if show > 0.01 then
                local px = statsX - slide
                love.graphics.setColor(0.06, 0.07, 0.09, 0.5 * show)
                W.roundrect(px - 8, panelY - 6, statsW + 16, panelH + 12, 12)
                love.graphics.setColor(1, 1, 1, 0.08 * show)
                love.graphics.setLineWidth(1.4)
                W.roundrect(px - 8, panelY - 6, statsW + 16, panelH + 12, 12, "line")
                if show > 0.2 then
                    W.box(buttons, px - 8, panelY - 6, statsW + 16, panelH + 12, function() end, "stats", "arrow")
                end
                if havePts then
                    local pulse = 0.55 + 0.45 * math.sin(State.anim.pulse * 6)
                    love.graphics.setColor(1, 1, 1, (0.55 + 0.45 * pulse) * show)
                    Render.print("Stat points: " .. tostring(cam.statsAvailable), px, panelY)
                else
                    love.graphics.setColor(0.70, 0.76, 0.84, 0.72 * show)
                    Render.print("STATS", px, panelY)
                end
                for r = 1, #statRows do
                    local i = statRows[r]
                    local name = W.txt(cam.statNames[i])
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
                    local dx, dy, dw, dh = W.hoverScale(key, x, y, statsW, 22)
                    W.outlinedBar(dx, dy, dw, dh, fillR, W.statFill(i, can), 5, show)
                    love.graphics.setColor(1, 1, 1, show)
                    Render.print(name .. "  " .. tostring(math.floor(level)) .. "/" .. tostring(math.floor(limit)), dx + 8, dy + 3)
                    W.buttonFlash(dx, dy, dw, dh, 5, key, show)
                    if show > 0.75 then
                        local statId = i
                        W.box(buttons, x, y, statsW, 26, function()
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
        Play.drawMatchInfo(game, cam, sw, sh, buttons)
        Play.drawMinimap(game, world, arena, player, cam, sw, sh, buttons)
    end

    local showingDeath = world:isDead()
    if showingDeath then
        local a = math.min(1, 0.55 + State.anim.overlay * 3)
        love.graphics.setColor(0, 0, 0, 0.55 * a)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1, a)
        Render.printf("You were killed" .. ((cam.killedBy and cam.killedBy ~= "") and (" by " .. W.txt(cam.killedBy)) or ""), 0, sh / 2 - 40, sw, "center")
        Render.printf("Click or press Enter to continue", 0, sh / 2, sw, "center")
        W.box(buttons, 0, 0, sw, sh, function()
            game:send(Encode.toRespawn())
        end, "death")
    elseif waiting then
        local okCount, errCount = pcall(Play.drawCountdown, game, arena, sw, sh)
        if not okCount then
            print("[LoveDiepClient] countdown: " .. tostring(errCount))
        end
    elseif not spawned then
        local okHome, errHome = pcall(Home.drawHome, game, buttons, sw, sh, markHover, underScale)
        if not okHome then
            print("[LoveDiepClient] menu: " .. tostring(errHome))
        end
    end

    local okBoard, errBoard = pcall(Scoreboard.drawScoreboard, game, arena, sw, buttons, markHover, underScale)
    if not okBoard then
        print("[LoveDiepClient] scoreboard: " .. tostring(errBoard))
    end

    for i = 1, #upgradeHits do
        local u = upgradeHits[i]
        W.box(buttons, u.x, u.y, u.w, u.h, function()
            game:queueTankUpgrade(u.id)
        end, u.key)
    end

    Console.draw(game, buttons, sw, sh, W.box)
    Pause.drawPause(game, buttons, sw, sh, markHoverAll, W.hoverScale)
    Options.drawOptions(game, buttons, sw, sh, markHoverAll, W.hoverScale)
    TankTree.draw(game, buttons, sw, sh, W.box, markHover, W.hoverScale)

    if Settings.showFps then
        local fps = love.timer.getFPS()
        local label = string.format("%d FPS", fps)
        love.graphics.setColor(0, 0, 0, 0.48)
        W.roundrect(10, 8, 92, 28, 8)
        love.graphics.setColor(1, 1, 1, 0.96)
        Render.outlinedPrintf(label, 10, 13, 92, "center", 2)
    end

    love.graphics.pop()
    return buttons
end

return Hud
