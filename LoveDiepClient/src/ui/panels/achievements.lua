local Render = require("src.render")
local W = require("src.ui.widgets")
local Layout = require("src.ui.layout")
local Achievements = require("src.data.achievements")
local roundrect = W.roundrect

local M = {}
function M.drawAchievements(sw, sh)
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

    local scale, sox, soy = Layout.metrics()
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
return M
