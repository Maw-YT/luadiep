--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")
local Barrel = require("../Barrel")
local Enums = require("../../../Const/Enums")
local AIMod = require("../../AI")

local RocketBarrelDefinition = {
    angle = math.pi, offset = 0, size = 70, width = 36, delay = 0, reload = 0.15, recoil = 3.3,
    isTrapezoid = true, trapezoidDirection = 0, addon = nil,
    bullet = { type = "bullet", health = 0.3, damage = 3 / 5, speed = 1.5, scatterRate = 5, lifeLength = 0.1, sizeRatio = 1, absorbtionFactor = 1 }
}

local Rocket = class(Bullet)

function Rocket:init(barrel, tank, tankDefinition, shootAngle)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)
    self.scaleFactor = self.physicsData.values.size / 50
    self.cameraEntity = tank.cameraEntity
    self.reloadTime = 1
    self.inputs = AIMod.Inputs:new()
    local rocketBarrel = Barrel:new(self, RocketBarrelDefinition)
    local origScale = rocketBarrel.scale
    rocketBarrel.scale = function(b, value)
        origScale(b, value)
        if not self.deletionAnimation then
            rocketBarrel.physicsData.width = rocketBarrel.definition.width
        end
    end
    rocketBarrel.styleData.values.color = self.styleData.values.color
    self.rocketBarrel = rocketBarrel
    self:scale(1)
end

function Rocket:tick(tick)
    self.reloadTime = self.tank.reloadTime
    Bullet.tick(self, tick)
    if self.deletionAnimation then return end
    if tick - self.spawnTick >= self.tank.reloadTime then
        self.inputs.flags = bit.bor(self.inputs.flags, Enums.InputFlags.leftclick)
    end
end

return Rocket
