local bit = require("bit")
local Enums = require("src.protocol.enums")

local CameraFlags = Enums.CameraFlags

return function(Render)
local function localPos(e)
    local pos = e.position
    return (e.ix or (pos and pos.x) or 0),
        (e.iy or (pos and pos.y) or 0),
        (e.ia or (pos and pos.angle) or 0),
        (pos and pos.flags) or 0
end

function Render.view(world)
    local cam = world:cameraValues()
    local fov = (cam and cam.FOV) or 0.35
    if fov <= 0.01 then fov = 0.35 end
    local flags = (cam and cam.flags) or 0
    local player = world:player()
    if player and player.position then
        -- Follow the tank unless the server is explicitly driving the camera (e.g. predator zoom).
        if bit.band(flags, CameraFlags.usesCameraCoords) == 0 then
            world:ensureWorld(player)
            return player.worldX or 0, player.worldY or 0, fov
        end
    end
    return (cam and cam.cameraX) or 0, (cam and cam.cameraY) or 0, fov
end

-- Uniform scale from the 16:9 diep view (1920x1080 / FOV). Zoom in on
-- non-16:9 windows so neither axis shows more world than that reference.
function Render.viewMetrics(fov)
    local sw, sh = love.graphics.getDimensions()
    fov = tonumber(fov) or Render._fov or 0.35
    if not fov or fov <= 0.01 or fov ~= fov then fov = 0.35 end
    local refW = 1920 / fov
    local refH = 1080 / fov
    local scale = math.max(sw / refW, sh / refH)
    if not scale or scale <= 0 or scale ~= scale then scale = 1 end
    return scale, sw / scale, sh / scale, sw, sh
end

local function applyCamera(camX, camY, fov)
    local scale, visW, visH, sw, sh = Render.viewMetrics(fov)
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-camX, -camY)
    Render._viewW, Render._viewH = visW, visH
    return scale, visW, visH
end

local function pixel()
    return 1 / math.max(Render._scale or 1, 0.0001)
end

Render.localPos = localPos
Render.applyCamera = applyCamera
Render.pixel = pixel
end
