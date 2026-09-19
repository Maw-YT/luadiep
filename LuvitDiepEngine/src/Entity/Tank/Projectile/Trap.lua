--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")
local Enums = require("../../../Const/Enums")
local util = require("../../../util")
local DevTank = require("../../../Const/DevTankDefinitions").DevTank

local PhysicsFlags = Enums.PhysicsFlags
local StyleFlags = Enums.StyleFlags

local Trap = class(Bullet)

function Trap:init(barrel, tank, tankDefinition, shootAngle)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)
    self.baseSpeed = (barrel.bulletAccel / 2) + 30 - math.random() * barrel.definition.bullet.scatterRate
    self.baseAccel = 0
    self.physicsData.values.sides = 3
    if bit.band(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision) ~= 0 then
        self.physicsData.values.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision)
    end
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.onlySameOwnerCollision)
    self.styleData.values.flags = bit.bor(self.styleData.values.flags, StyleFlags.isStar, StyleFlags.isCachable)
    self.styleData.values.flags = bit.band(self.styleData.values.flags, bit.bnot(StyleFlags.hasNoDmgIndicator))
    self.collisionEnd = bit.rshift(self.lifeLength, 3)
    self.lifeLength = bit.rshift(600 * barrel.definition.bullet.lifeLength, 3)
    if tankDefinition and tankDefinition.id == DevTank.Bouncy then
        self.collisionEnd = self.lifeLength - 1
    end
    self.positionData.values.angle = math.random() * util.PI2
end

function Trap:tick(tick)
    Bullet.tick(self, tick)
    if tick - self.spawnTick == self.collisionEnd then
        if bit.band(self.physicsData.values.flags, PhysicsFlags.onlySameOwnerCollision) ~= 0 then
            self.physicsData.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.onlySameOwnerCollision)
        end
        self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision)
    end
end

return Trap
