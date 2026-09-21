local Render = require("src.render")
local W = require("src.ui.widgets")
local Servers = require("src.data.servers")
local ChangelogPanel = require("src.ui.panels.changelog")
local AchievementsPanel = require("src.ui.panels.achievements")
local box = W.box
local roundrect = W.roundrect
local buttonShadow = W.buttonShadow
local buttonOutline = W.buttonOutline
local buttonFlash = W.buttonFlash
local txt = W.txt
local scissorGui = W.scissorGui
local drawCogIcon = W.drawCogIcon

local M = {}
function M.drawHome(game, buttons, sw, sh, markHover, hoverScaleFn)
    if game.optionsOpen or game.treeOpen or game.paused then
        markHover = function() end
        hoverScaleFn = function(_, x, y, w, h) return x, y, w, h, 1 end
    end
    local a = math.min(1, 0.45 + W.anim.overlay * 0.9)
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

    ChangelogPanel.drawChangelog(buttons, sw, sh)
    AchievementsPanel.drawAchievements(sw, sh)
end
return M
