--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")
local Barrel = require("../Barrel")
local Enums = require("../../../Const/Enums")
local AIMod = require("../../AI")

local CrocSkimmerBarrelDefinition = {
    angle = math.pi / 2, offset = 0, size = 70, width = 42, delay = 0, reload = 0.5, recoil = 0,
    isTrapezoid = false, trapezoidDirection = 0, addon = nil,
    bullet = { type = "bullet", health = 0.3, damage = 3 / 5, speed = 0.2, scatterRate = 1, lifeLength = 0.25, sizeRatio = 1, absorbtionFactor = 1 }
}

local CrocSkimmer = class(Bullet)

function CrocSkimmer:init(barrel, tank, tankDefinition, shootAngle)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)
    self.cameraEntity = tank.cameraEntity
    self.reloadTime = 15
    local s1 = Barrel:new(self, CrocSkimmerBarrelDefinition)
    local s2Def = {}
    for k, v in pairs(CrocSkimmerBarrelDefinition) do s2Def[k] = v end
    s2Def.angle = s2Def.angle + math.pi
    local s2 = Barrel:new(self, s2Def)
    s1.styleData.values.color = self.styleData.values.color
    s2.styleData.values.color = self.styleData.values.color
    self.skimmerBarrels = { s1, s2 }
    self.inputs = AIMod.Inputs:new()
    self.inputs.flags = bit.bor(self.inputs.flags, Enums.InputFlags.leftclick)
end

function CrocSkimmer:tick(tick)
    self.reloadTime = self.tank.reloadTime
    Bullet.tick(self, tick)
end

return CrocSkimmer
