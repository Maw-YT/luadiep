return function(Render)
local function drawGrid(camX, camY, viewW, viewH)
    local cell = 50
    local padX, padY = viewW * 0.6, viewH * 0.6
    local x0 = math.floor((camX - padX) / cell) * cell
    local y0 = math.floor((camY - padY) / cell) * cell
    love.graphics.setColor(Render.hex(0xC4C4C4))
    love.graphics.setLineWidth(Render.pixel())
    love.graphics.setLineStyle("rough")
    for x = x0, camX + padX, cell do
        love.graphics.line(x, camY - padY, x, camY + padY)
    end
    for y = y0, camY + padY, cell do
        love.graphics.line(camX - padX, y, camX + padX, y)
    end
    love.graphics.setLineStyle("smooth")
end

local function drawArenaFloor(arena)
    if not arena then return end
    local l, t, r, b = arena.leftX, arena.topY, arena.rightX, arena.bottomY
    if not l then return end
    love.graphics.setColor(Render.hex(0xB0B0B0))
    love.graphics.rectangle("fill", l - 8000, t - 8000, (r - l) + 16000, (b - t) + 16000)
    love.graphics.setColor(Render.hex(0xCDCDCD))
    love.graphics.rectangle("fill", l, t, r - l, b - t)
end

local function drawArenaBorder(arena)
    if not arena then return end
    local l, t, r, b = arena.leftX, arena.topY, arena.rightX, arena.bottomY
    if not l then return end
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setColor(Render.hex(0x555555, 0.9))
    love.graphics.setLineWidth(math.max(6, 8 * Render.pixel()))
    love.graphics.rectangle("line", l, t, r - l, b - t)
end

Render.drawGrid = drawGrid
Render.drawArenaFloor = drawArenaFloor
Render.drawArenaBorder = drawArenaBorder
end
