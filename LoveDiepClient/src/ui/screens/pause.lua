local Render = require("src.render")
local State = require("src.ui.state")
local W = require("src.ui.widgets")
local box = W.box
local roundrect = W.roundrect
local buttonShadow = W.buttonShadow
local buttonOutline = W.buttonOutline
local buttonFlash = W.buttonFlash

local M = {}
function M.drawPause(game, buttons, sw, sh, markHover, hoverScaleFn)
    if not game.paused or game.optionsOpen then return end
    State.lastHoverKey = ""
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
return M
