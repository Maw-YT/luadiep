local Render = require("src.render")
local State = require("src.ui.state")
local W = require("src.ui.widgets")
local Layout = require("src.ui.layout")
local Settings = require("src.ui.settings")
local box = W.box
local roundrect = W.roundrect
local buttonShadow = W.buttonShadow
local buttonOutline = W.buttonOutline
local buttonFlash = W.buttonFlash

local M = {}
function M.drawOptions(game, buttons, sw, sh, markHover, hoverScaleFn)
    if not game.optionsOpen then return end
    State.lastHoverKey = ""
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
        local gx = Layout.screenToGui(love.mouse.getPosition())
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
        local gx = Layout.screenToGui(love.mouse.getPosition())
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
return M
