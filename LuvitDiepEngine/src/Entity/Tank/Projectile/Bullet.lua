--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local LivingEntity = require("../../Live")
local Enums = require("../../../Const/Enums")
local Entity = require("../../../Native/Entity")

local HealthFlags = Enums.HealthFlags
local PositionFlags = Enums.PositionFlags
local PhysicsFlags = Enums.PhysicsFlags
local Stat = Enums.Stat
local StyleFlags = Enums.StyleFlags
local EntityStateFlags = Enums.EntityStateFlags

local Bullet = class(LivingEntity)

function Bullet:init(barrel, tank, tankDefinition, shootAngle)
    LivingEntity.init(self, barrel.game)
    self.tank = tank
    self.tankDefinition = tankDefinition
    self.movementAngle = shootAngle
    self.barrelEntity = barrel
    self.spawnTick = barrel.game.tick
    self.usePosAngle = false
    self.deathAccelFactor = 0.5
    self.relationsData.values.owner = tank
    tank.rootParent.styleData.zIndex = barrel.game.entities.zIndex
    barrel.game.entities.zIndex = barrel.game.entities.zIndex + 1
    local bulletDefinition = barrel.definition.bullet
    local scaleFactor = tank.scaleFactor
    local statLevels = tank.cameraEntity.cameraData and tank.cameraEntity.cameraData.values.statLevels
    self.relationsData.values.team = barrel.relationsData.values.team
    self.physicsData.values.sides = 1
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision, PhysicsFlags.canEscapeArena)
    if bit.band(tank.positionData.values.flags, PositionFlags.canMoveThroughWalls) ~= 0 then
        self.positionData.values.flags = bit.bor(self.positionData.values.flags, PositionFlags.canMoveThroughWalls)
    end
    self.physicsData.values.size = (barrel.physicsData.values.width / 2) * bulletDefinition.sizeRatio
    self.styleData.values.color = tank.rootParent.styleData.values.color
    self.styleData.values.flags = bit.bor(self.styleData.values.flags, StyleFlags.hasNoDmgIndicator)
    self.healthData.values.flags = HealthFlags.hiddenHealthbar
    local bulletDamage = statLevels and statLevels:get(Stat.BulletDamage) or 0
    local bulletPenetration = statLevels and statLevels:get(Stat.BulletPenetration) or 0
    self.physicsData.values.absorbtionFactor = bulletDefinition.absorbtionFactor
    self.physicsData.values.pushFactor = ((7 / 3) + bulletDamage) * bulletDefinition.damage * bulletDefinition.absorbtionFactor
    self.baseAccel = barrel.bulletAccel
    self.baseSpeed = barrel.bulletAccel + 30 - math.random() * bulletDefinition.scatterRate
    self.healthData.values.health = (1.5 * bulletPenetration + 2) * bulletDefinition.health
    self.healthData.values.maxHealth = self.healthData.values.health
    self.damagePerTick = (7 + bulletDamage * 3) * bulletDefinition.damage
    self.minDamageMultiplier = 0.25
    self.maxDamageMultiplier = 1
    self.lifeLength = bulletDefinition.lifeLength * 75
    local pos = tank:getWorldPosition()
    self.positionData.values.x = pos.x + (math.cos(shootAngle) * barrel.physicsData.values.size) - math.sin(shootAngle) * barrel.definition.offset * scaleFactor + math.cos(shootAngle) * (barrel.definition.distance or 0)
    self.positionData.values.y = pos.y + (math.sin(shootAngle) * barrel.physicsData.values.size) + math.cos(shootAngle) * barrel.definition.offset * scaleFactor + math.sin(shootAngle) * (barrel.definition.distance or 0)
    self.positionData.values.angle = shootAngle
end

function Bullet:onKill(killedEntity, weapon)
    if self.tank and self.tank.onKill then
        self.tank:onKill(killedEntity, weapon)
    end
end

function Bullet:tick(tick)
    LivingEntity.tick(self, tick)
    if tick == self.spawnTick + 1 then
        self:addVelocity(self.movementAngle, self.baseSpeed)
    else
        local ang = self.usePosAngle and self.positionData.values.angle or self.movementAngle
        self:maintainVelocity(ang, self.baseAccel)
    end
    if tick - self.spawnTick >= self.lifeLength then
        self:destroy(true)
    end
    local team = self.relationsData.values.team
    if team and bit.band(team.entityState or 0, EntityStateFlags.needsDelete) ~= 0 then
        self.relationsData.values.team = nil
    end
end

return Bullet
