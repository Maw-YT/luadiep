--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")
local Barrel = require("../Barrel")
local Enums = require("../../../Const/Enums")
local AIMod = require("../../AI")

local SkimmerBarrelDefinition = {
    angle = 0, offset = 0, size = 70, width = 42, delay = 0, reload = 0.35, recoil = 0,
    isTrapezoid = false, trapezoidDirection = 0, addon = nil,
    bullet = { type = "bullet", health = 0.3, damage = 3 / 5, speed = 1.1, scatterRate = 1, lifeLength = 0.25, sizeRatio = 1, absorbtionFactor = 1 }
}

local Skimmer = class(Bullet)
Skimmer.BASE_ROTATION = 0.1

function Skimmer:init(barrel, tank, tankDefinition, shootAngle, direction)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)
    self.scaleFactor = self.physicsData.values.size / 50
    self.rotationPerTick = direction or Skimmer.BASE_ROTATION
    self.cameraEntity = tank.cameraEntity
    self.reloadTime = 15
    local s1 = Barrel:new(self, SkimmerBarrelDefinition)
    local orig1 = s1.scale
    s1.scale = function(b, value)
        orig1(b, value)
        if not self.deletionAnimation then s1.physicsData.width = s1.definition.width end
    end
    local s2Def = {}
    for k, v in pairs(SkimmerBarrelDefinition) do s2Def[k] = v end
    s2Def.angle = s2Def.angle + math.pi
    local s2 = Barrel:new(self, s2Def)
    local orig2 = s2.scale
    s2.scale = function(b, value)
        orig2(b, value)
        if not self.deletionAnimation then s2.physicsData.width = s2.definition.width end
    end
    s1.styleData.values.color = self.styleData.values.color
    s2.styleData.values.color = self.styleData.values.color
    self.skimmerBarrels = { s1, s2 }
    self.inputs = AIMod.Inputs:new()
    self.inputs.flags = bit.bor(self.inputs.flags, Enums.InputFlags.leftclick)
    self:scale(1)
end

function Skimmer:tick(tick)
    self.reloadTime = self.tank.reloadTime
    self.positionData.angle = self.positionData.values.angle + self.rotationPerTick
    Bullet.tick(self, tick)
end

return Skimmer
