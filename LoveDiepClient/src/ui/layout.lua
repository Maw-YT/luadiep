local Settings = require("src.ui.settings")

local Layout = {}
Layout.GUI_W = 1280
Layout.GUI_H = 720

-- Same cover-zoom as the world camera: on a tall or wide window, scale
-- up so the 16:9 GUI fills the window instead of stretching across extra space.
function Layout.metrics()
    local sw, sh = love.graphics.getDimensions()
    local scale = math.max(sw / Layout.GUI_W, sh / Layout.GUI_H)
    local ui = tonumber(Settings.hudScale) or 1
    if ui < 0.5 then ui = 0.5 end
    if ui > 2 then ui = 2 end
    scale = scale * ui
    if scale <= 0 then scale = 1 end
    return scale, 0, 0, sw / scale, sh / scale
end

function Layout.screenToGui(x, y)
    local scale, ox, oy = Layout.metrics()
    return (x - ox) / scale, (y - oy) / scale
end

function Layout.push()
    local scale, ox, oy, vw, vh = Layout.metrics()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
    return scale, ox, oy, vw, vh
end

return Layout
