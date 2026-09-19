--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")

local Flame = class(Bullet)

function Flame:init(barrel, tank, tankDefinition, shootAngle)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)
    self.baseSpeed = self.baseSpeed * 2
    self.baseAccel = 0
    self.damageReduction = 1
    self.physicsData.values.sides = 4
    self.physicsData.values.absorbtionFactor = 0
    self.physicsData.values.pushFactor = 0
    self.lifeLength = 25 * barrel.definition.bullet.lifeLength
end

function Flame:destroy(animate)
    Bullet.destroy(self, false)
end

function Flame:tick(tick)
    Bullet.tick(self, tick)
    self.damageReduction = self.damageReduction + 1 / 25
    self.styleData.opacity = self.styleData.values.opacity - 1 / 25
end

return Flame
