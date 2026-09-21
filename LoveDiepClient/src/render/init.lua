local Render = {}
Render._scale = 1
Render._camX = 0
Render._camY = 0
Render._fov = 0.35
Render._viewW = 1920 / 0.35
Render._viewH = 1080 / 0.35
Render._style = "new"
Render._innerShadow = 0.15

function Render.setStyle(style)
    local nextStyle = "new"
    if style == "old" then
        nextStyle = "old"
    elseif style == "shaded" then
        nextStyle = "shaded"
    end
    if Render._style ~= nextStyle then
        Render._style = nextStyle
        Render.invalidateIconCache()
    end
end

function Render.setInnerShadow(coverage)
    coverage = tonumber(coverage) or 0.15
    if coverage ~= coverage then coverage = 0.15 end
    if coverage < 0 then coverage = 0 end
    if coverage > 1 then coverage = 1 end
    if Render._innerShadow ~= coverage then
        Render._innerShadow = coverage
        Render.invalidateIconCache()
    end
end

require("src.render.color")(Render)
require("src.render.text")(Render)
require("src.render.camera")(Render)
require("src.render.arena")(Render)
require("src.render.scene")(Render)

return Render
