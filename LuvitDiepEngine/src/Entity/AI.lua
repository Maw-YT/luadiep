--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Vector = require("../Physics/Vector")
local ObjectEntity = require("./Object")
local Entity = require("../Native/Entity")
local Enums = require("../Const/Enums")
local PackedEntitySet = require("../Physics/PackedEntitySet")

local InputFlags = Enums.InputFlags
local PhysicsFlags = Enums.PhysicsFlags

local AIState = {
    idle = 0,
    hasTarget = 1,
    possessed = 3
}

local Inputs = class()
function Inputs:init()
    self.flags = 0
    self.mouse = Vector:new()
    self.movement = Vector:new()
    self.deleted = false
    self.cachedFlags = 0
    self.isPossessing = false
    self.client = nil
end
function Inputs:attemptingShot()
    return bit.band(self.flags, InputFlags.leftclick) ~= 0
end
function Inputs:attemptingRepel()
    return bit.band(self.flags, InputFlags.rightclick) ~= 0
end

local AI = class()
AI.PASSIVE_ROTATION = 0.01
AI._aiHashCounter = 0

function AI:init(owner, claimable)
    self.owner = owner
    self.game = owner.game
    self.isClaimable = claimable and true or false
    self.passiveRotation = (math.random() < 0.5) and AI.PASSIVE_ROTATION or -AI.PASSIVE_ROTATION
    self.viewRange = 1700
    self.state = AIState.idle
    self.inputs = Inputs:new()
    self.target = nil
    self.movementSpeed = 1
    self.aimSpeed = 1
    self.doAimPrediction = false
    self.targetFilterNonLiving = true
    self.targetFilter = function() return true end
    AI._aiHashCounter = (AI._aiHashCounter + 1) % 16384
    self._aiHash = AI._aiHashCounter
    self._findTargetInterval = 2
    self.inputs.mouse:set({ x = 0, y = 0 })
    self.game.entities.AIs[#self.game.entities.AIs + 1] = self
end

function AI:findTarget(tick)
    if self._findTargetInterval ~= 0 and ((tick + self._aiHash) % self._findTargetInterval) ~= 1 then
        if Entity.exists(self.target) then
            return self.target
        end
        self.target = nil
        return nil
    end

    local rootPos = self.owner.rootParent.positionData.values
    local team = self.owner.relationsData.values.team

    if Entity.exists(self.target) then
        if team ~= self.target.relationsData.values.team and self.target.physicsData.values.sides ~= 0 then
            local dx = self.target.positionData.values.x - rootPos.x
            local dy = self.target.positionData.values.y - rootPos.y
            if self.targetFilter(self.target.positionData.values) and (dx * dx + dy * dy) < (self.viewRange ^ 2) * 2 then
                return self.target
            end
        end
    end

    local root = self.owner
    if self.owner.rootParent == self.owner then
        local owner = self.owner.relationsData.values.owner
        if owner and owner.positionData then
            root = owner
        end
    else
        root = self.owner.rootParent
    end

    local entities
    if self.viewRange == math.huge then
        entities = nil
    else
        entities = self.game.entities.collisionManager:retrieve(
            root.positionData.values.x, root.positionData.values.y,
            self.viewRange, self.viewRange
        )
    end

    local closestEntity = nil
    local closestDistSq = self.viewRange ^ 2

    local function consider(id)
        local entity = self.game.entities.inner[id]
        if not entity or entity.hash == 0 then return end
        if not ObjectEntity.isObject(entity) then return end
        if not entity.isPhysical then return end
        if self.targetFilterNonLiving and not entity.healthData then return end
        if bit.band(entity.physicsData.values.flags, PhysicsFlags.isBase) ~= 0 then return end
        if entity.relationsData.values.owner ~= nil and entity.relationsData.values.owner.positionData then return end
        if entity.relationsData.values.team == team then return end
        if entity.physicsData.values.sides == 0 then return end
        if not self.targetFilter(entity.positionData.values) then return end
        local dX = entity.positionData.values.x - rootPos.x
        local dY = entity.positionData.values.y - rootPos.y
        local distSq = dX * dX + dY * dY
        if distSq < closestDistSq then
            closestEntity = entity
            closestDistSq = distSq
        end
    end

    if entities then
        entities:forEach(consider)
    else
        for id = 0, self.game.entities.lastId do
            consider(id)
        end
    end

    self.target = closestEntity
    return closestEntity
end

function AI:aimAtTarget()
    if not self.target then return end
    local movementSpeed = self.aimSpeed * 1.6
    local ownerPos = self.owner:getWorldPosition()
    local pos = {
        x = self.target.positionData.values.x,
        y = self.target.positionData.values.y
    }

    if movementSpeed <= 0.001 then
        self.inputs.movement:set({ x = pos.x - ownerPos.x, y = pos.y - ownerPos.y })
        self.inputs.mouse:set(pos)
        self.inputs.movement.magnitude = 1
        return
    end

    if self.doAimPrediction then
        local delta = { x = pos.x - ownerPos.x, y = pos.y - ownerPos.y }
        local dist = math.sqrt(delta.x ^ 2 + delta.y ^ 2)
        if dist == 0 then dist = 1 end
        local unitDistancePerp = { x = delta.y / dist, y = -delta.x / dist }
        local entPerpComponent = unitDistancePerp.x * self.target.velocity.x + unitDistancePerp.y * self.target.velocity.y
        if entPerpComponent > movementSpeed * 0.9 then entPerpComponent = movementSpeed * 0.9 end
        if entPerpComponent < movementSpeed * -0.9 then entPerpComponent = movementSpeed * -0.9 end
        local directComponent = math.sqrt(movementSpeed ^ 2 - entPerpComponent ^ 2)
        local offset = (entPerpComponent / directComponent * dist) / 2
        self.inputs.mouse:set({
            x = pos.x + offset * unitDistancePerp.x,
            y = pos.y + offset * unitDistancePerp.y
        })
    else
        self.inputs.mouse:set(pos)
    end

    self.inputs.movement.magnitude = 1
    self.inputs.movement.angle = math.atan2(self.inputs.mouse.y - ownerPos.y, self.inputs.mouse.x - ownerPos.x)
end

function AI:tick(tick)
    if self.state == AIState.possessed then
        if not self.inputs.deleted then return end
        self.inputs = Inputs:new()
    end

    local target = self:findTarget(tick)
    if not target then
        self.inputs.flags = 0
        self.state = AIState.idle
        local angle = self.inputs.mouse.angle + self.passiveRotation
        self.inputs.mouse:set({
            x = math.cos(angle) * 100,
            y = math.sin(angle) * 100
        })
    else
        self.state = AIState.hasTarget
        self.inputs.flags = bit.bor(self.inputs.flags, InputFlags.leftclick)
        self:aimAtTarget()
    end
end

return {
    AI = AI,
    AIState = AIState,
    Inputs = Inputs
}
