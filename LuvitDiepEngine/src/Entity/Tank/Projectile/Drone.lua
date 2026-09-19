--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Bullet = require("./Bullet")
local Enums = require("../../../Const/Enums")
local Entity = require("../../../Native/Entity")
local AIMod = require("../../AI")

local PhysicsFlags = Enums.PhysicsFlags
local StyleFlags = Enums.StyleFlags
local AI = AIMod.AI
local AIState = AIMod.AIState

local Drone = class(Bullet)
Drone.MAX_RESTING_RADIUS = 400 ^ 2

function Drone:init(barrel, tank, tankDefinition, shootAngle)
    Bullet.init(self, barrel, tank, tankDefinition, shootAngle)
    local bulletDefinition = barrel.definition.bullet
    self.usePosAngle = true
    self.ai = AI:new(self)
    self.ai.viewRange = 900
    self.ai.targetFilter = function(targetPos)
        local dx = targetPos.x - self.tank.positionData.values.x
        local dy = targetPos.y - self.tank.positionData.values.y
        return dx * dx + dy * dy <= self.ai.viewRange ^ 2
    end
    self.canControlDrones = barrel.definition.canControlDrones == true
    self.physicsData.values.sides = 3
    if bit.band(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision) ~= 0 then
        self.physicsData.values.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision)
    end
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.onlySameOwnerCollision)
    self.physicsData.values.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.canEscapeArena)
    self.styleData.values.flags = bit.band(self.styleData.values.flags, bit.bnot(StyleFlags.hasNoDmgIndicator))
    if barrel.definition.bullet.lifeLength ~= -1 then
        self.lifeLength = 88 * barrel.definition.bullet.lifeLength
    else
        self.lifeLength = math.huge
    end
    self.deathAccelFactor = 1
    self.physicsData.values.pushFactor = 4
    self.physicsData.values.absorbtionFactor = bulletDefinition.absorbtionFactor
    self.baseSpeed = self.baseSpeed / 3
    barrel.droneCount = barrel.droneCount + 1
    self.ai.movementSpeed = self.baseAccel
    self.ai.aimSpeed = self.baseAccel
    self.minDamageMultiplier = 1
    self.maxDamageMultiplier = 1
    self.restCycle = true
end

function Drone:destroy(animate)
    if animate == nil then animate = true end
    if not animate then
        self.barrelEntity.droneCount = self.barrelEntity.droneCount - 1
    end
    Bullet.destroy(self, animate)
end

function Drone:tickMixin(tick)
    Bullet.tick(self, tick)
end

function Drone:tick(tick)
    local usingAI = (not self.canControlDrones) or self.tank.inputs.deleted or (not self.tank.inputs:attemptingShot() and not self.tank.inputs:attemptingRepel())
    local inputs = usingAI and self.ai.inputs or self.tank.inputs
    if usingAI and self.ai.state == AIState.idle then
        local delta = {
            x = self.positionData.values.x - self.tank.positionData.values.x,
            y = self.positionData.values.y - self.tank.positionData.values.y
        }
        local base = self.baseAccel
        local unitDist = (delta.x ^ 2 + delta.y ^ 2) / Drone.MAX_RESTING_RADIUS
        if unitDist <= 1 and self.restCycle then
            self.baseAccel = self.baseAccel / 6
            self.positionData.angle = self.positionData.values.angle + 0.01 + 0.012 * unitDist
        else
            local offset = math.atan2(delta.y, delta.x) + math.pi / 2
            delta.x = self.tank.positionData.values.x + math.cos(offset) * self.tank.physicsData.values.size * 1.2 - self.positionData.values.x
            delta.y = self.tank.positionData.values.y + math.sin(offset) * self.tank.physicsData.values.size * 1.2 - self.positionData.values.y
            self.positionData.angle = math.atan2(delta.y, delta.x)
            if unitDist < 0.5 then self.baseAccel = self.baseAccel / 3 end
            self.restCycle = (delta.x ^ 2 + delta.y ^ 2) <= 4 * (self.tank.physicsData.values.size ^ 2)
        end
        if not Entity.exists(self.barrelEntity) then self:destroy() end
        self:tickMixin(tick)
        self.baseAccel = base
        return
    else
        self.positionData.angle = math.atan2(inputs.mouse.y - self.positionData.values.y, inputs.mouse.x - self.positionData.values.x)
        self.restCycle = false
    end
    if self.canControlDrones and inputs:attemptingRepel() then
        self.positionData.angle = self.positionData.values.angle + math.pi
    end
    if not Entity.exists(self.barrelEntity) then self:destroy() end
    self:tickMixin(tick)
end

return Drone
