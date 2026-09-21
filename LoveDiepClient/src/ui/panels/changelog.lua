local Render = require("src.render")
local W = require("src.ui.widgets")
local Changelog = require("src.data.changelog")
local box = W.box
local roundrect = W.roundrect
local scissorGui = W.scissorGui

local M = {}
local function wrapCount(text, width)
    local font = love.graphics.getFont()
    if not font or not text or text == "" then
        return 1
    end
    local _, lines = font:getWrap(text, width)
    return math.max(1, #lines)
end

function M.drawChangelog(buttons, sw, sh)
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
return M
