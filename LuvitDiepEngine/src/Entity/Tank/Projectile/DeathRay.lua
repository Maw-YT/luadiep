--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")
local LivingEntity = require("../../Live")
local Entity = require("../../../Native/Entity")
local Enums = require("../../../Const/Enums")
local util = require("../../../util")

local PhysicsFlags = Enums.PhysicsFlags
local PositionFlags = Enums.PositionFlags
local StyleFlags = Enums.StyleFlags

local DeathRay = class(Bullet)
DeathRay.LENGTH = 2800

function DeathRay:init(barrel, tank, tankDefinition, shootAngle)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)

    local bullet = barrel.definition.bullet
    local thickness = math.max(10, barrel.physicsData.values.width * (bullet.sizeRatio or 1))
    self.beamLength = DeathRay.LENGTH * math.max(bullet.speed or 1, 0.35)
    self.baseSpeed = 0
    self.baseAccel = 0
    self.damageReduction = 0
    self.physicsData.values.sides = 2
    self.physicsData.values.size = self.beamLength
    self.physicsData.values.width = thickness
    self.physicsData.values.absorbtionFactor = 0
    self.physicsData.values.pushFactor = 0
    self.physicsData.flags = bit.bor(
        self.physicsData.values.flags,
        PhysicsFlags.isBeam,
        PhysicsFlags.isTrapezoid,
        PhysicsFlags.canEscapeArena,
        PhysicsFlags.noOwnTeamCollision
    )
    -- Stay in the spatial hash so cameras actually send the entity, but do not
    -- bounce off walls or other objects (strike() handles hits).
    self.isPhysical = true
    self.styleData.zIndex = self.game.entities.zIndex
    self.game.entities.zIndex = self.game.entities.zIndex + 1
    self.positionData.flags = bit.bor(self.positionData.values.flags, PositionFlags.canMoveThroughWalls)
    self.lifeLength = math.max(8, math.floor((bullet.lifeLength or 0.2) * 75))
    self.minDamageMultiplier = 1
    self.maxDamageMultiplier = 1
    self:aimFromTank(shootAngle)
    local grid = self.game.entities.collisionManager
    if grid and not grid.isLocked then
        grid:insert(self)
    end
end

function DeathRay:aimFromTank(shootAngle)
    if not Entity.exists(self.tank) or not Entity.exists(self.barrelEntity) then return end
    local angle = shootAngle or (self.tank.positionData.values.angle + (self.barrelEntity.definition.angle or 0))
    local pos = self.tank:getWorldPosition()
    local barrelSize = self.barrelEntity.physicsData.values.size
    local dist = barrelSize + self.beamLength * 0.5
    self.positionData.angle = angle
    self.positionData.x = pos.x + math.cos(angle) * dist
    self.positionData.y = pos.y + math.sin(angle) * dist
end

function DeathRay:strike()
    if not Entity.exists(self.tank) then return end
    local pos = self.positionData.values
    local halfLen = self.physicsData.values.size * 0.5
    local halfW = self.physicsData.values.width * 0.5
    local c, s = math.cos(pos.angle), math.sin(pos.angle)
    local reach = halfLen + halfW + 80
    local nearby = self.game.entities.collisionManager:retrieve(pos.x, pos.y, reach, reach)
    local team = self.relationsData.values.team

    local function hit(id)
        local entity = self.game.entities.inner[id]
        if not LivingEntity.isLive(entity) then return end
        if entity == self or entity == self.tank then return end
        if entity.relationsData.values.team == team then return end
        if entity.healthData.values.health <= 0 then return end
        if bit.band(entity.physicsData.values.flags or 0, PhysicsFlags.isBase) ~= 0 then return end
        for i = 1, #self.damagedEntities do
            if self.damagedEntities[i] == entity then return end
        end
        local dx = entity.positionData.values.x - pos.x
        local dy = entity.positionData.values.y - pos.y
        local lx = dx * c + dy * s
        local ly = -dx * s + dy * c
        local r = entity.physicsData.values.size or 0
        local cx = util.constrain(lx, -halfLen, halfLen)
        local cy = util.constrain(ly, -halfW, halfW)
        if (lx - cx) * (lx - cx) + (ly - cy) * (ly - cy) <= r * r then
            entity:receiveDamage(self, self.damagePerTick)
        end
    end

    if nearby then
        nearby:forEach(hit)
    end
end

function DeathRay:destroy(animate)
    Bullet.destroy(self, false)
end

function DeathRay:tick(tick)
    LivingEntity.tick(self, tick)
    if not Entity.exists(self.tank) then
        self:destroy(false)
        return
    end
    self:aimFromTank()
    self:strike()
    self.damagedEntities = {}
    local age = tick - self.spawnTick
    if age >= self.lifeLength then
        self:destroy(false)
        return
    end
    local fade = 1 - (age / self.lifeLength)
    self.styleData.opacity = math.max(0.2, fade)
end

return DeathRay
