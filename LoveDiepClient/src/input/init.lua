local bit = require("bit")
local Enums = require("src.protocol.enums")
local Render = require("src.render")

local Input = {}

local F = Enums.InputFlags
Input._pressed = {}

function Input.keypressed(key)
    Input._pressed[key] = true
end

function Input.clear()
    Input._pressed = {}
end

local function down(key)
    return love.keyboard.isDown(key)
end

function Input.flags(noClick, allowCheats)
    local flags = 0
    if not noClick then
        if love.mouse.isDown(1) then flags = bit.bor(flags, F.leftclick) end
        if love.mouse.isDown(2) then flags = bit.bor(flags, F.rightclick) end
    end
    if down("w") or down("up") then flags = bit.bor(flags, F.up) end
    if down("a") or down("left") then flags = bit.bor(flags, F.left) end
    if down("s") or down("down") then flags = bit.bor(flags, F.down) end
    if down("d") or down("right") then flags = bit.bor(flags, F.right) end
    if allowCheats then
        if down("u") then flags = bit.bor(flags, F.levelup) end
        if Input._pressed["k"] then flags = bit.bor(flags, F.suicide) end
        if Input._pressed[";"] then flags = bit.bor(flags, F.switchtank) end
        if Input._pressed["g"] then flags = bit.bor(flags, F.godmode) end
    end
    return flags
end

function Input.screenToWorld(mx, my, camX, camY, fov)
    local scale, _, _, sw, sh = Render.viewMetrics(fov)
    local wx = camX + (mx - sw / 2) / scale
    local wy = camY + (my - sh / 2) / scale
    return wx, wy
end

return Input
