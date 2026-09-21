local Render = require("src.render")
local W = require("src.ui.widgets")
local Enums = require("src.protocol.enums")
local box = W.box
local roundrect = W.roundrect
local txt = W.txt
local scissorGui = W.scissorGui
local formatScore = W.formatScore

local M = {}
local boardBars = {}

function M.drawScoreboard(game, arena, sw, buttons, markHover, hoverScaleFn)
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
return M
