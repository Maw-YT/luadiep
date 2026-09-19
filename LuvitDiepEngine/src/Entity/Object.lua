--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Entity = require("../Native/Entity")
local Vector = require("../Physics/Vector")
local FieldGroups = require("../Native/FieldGroups")
local Enums = require("../Const/Enums")
local util = require("../util")

local PhysicsFlags = Enums.PhysicsFlags
local PositionFlags = Enums.PositionFlags

local DeletionAnimation = class()
function DeletionAnimation:init(entity)
    self.entity = entity
    self.frame = 5
end
function DeletionAnimation:tick()
    if self.frame == -1 then
        error("Animation failed. Entity should be gone by now")
    end
    if self.frame == 0 then
        self.entity:destroy(false)
        self.frame = -1
        return
    end
    if self.frame == 5 then
        self.entity.styleData.opacity = 1 - (1 / 6)
    end
    self.entity.velocity.magnitude = self.entity.velocity.magnitude * self.entity.deathAccelFactor
    self.entity:scale(1.1)
    self.entity.styleData.opacity = self.entity.styleData.opacity - 1 / 6
    if self.entity.styleData.values.opacity < 0 then
        self.entity.styleData.opacity = 0
    end
    self.frame = self.frame - 1
end

local ObjectEntity = class(Entity)

function ObjectEntity.isObject(entity)
    return entity ~= nil and (entity._isObject == true or entity.physicsData ~= nil)
end

function ObjectEntity:init(game)
    self._isObject = true
    Entity.init(self, game)
    self.relationsData = FieldGroups.RelationsGroup:new(self)
    self.physicsData = FieldGroups.PhysicsGroup:new(self)
    self.positionData = FieldGroups.PositionGroup:new(self)
    self.styleData = FieldGroups.StyleGroup:new(self)
    self.deletionAnimation = nil
    self.isPhysical = true
    self.isChild = false
    self.children = {}
    self.rootParent = self
    self.scaleFactor = 1
    self.entityTags = 0
    self.arenaMobID = nil
    self.velocity = Vector:new()
    self.deathAccelFactor = 0.9
    self.styleData.zIndex = game.entities.zIndex
    game.entities.zIndex = game.entities.zIndex + 1
end

function ObjectEntity.isColliding(objA, objB)
    if objA == objB then return false end
    if not objA.isPhysical or not objB.isPhysical then return false end
    local physicsA = objA.physicsData.values
    local physicsB = objB.physicsData.values
    local relationsA = objA.relationsData.values
    local relationsB = objB.relationsData.values
    local positionA = objA.positionData.values
    local positionB = objB.positionData.values

    if physicsA.sides == 0 or physicsB.sides == 0 then return false end
    if objA.deletionAnimation or objB.deletionAnimation then return false end

    if relationsA.team == relationsB.team then
        if bit.band(physicsA.flags, PhysicsFlags.noOwnTeamCollision) ~= 0
            or bit.band(physicsB.flags, PhysicsFlags.noOwnTeamCollision) ~= 0 then
            return false
        end
        if relationsA.owner ~= relationsB.owner then
            if bit.band(physicsA.flags, PhysicsFlags.onlySameOwnerCollision) ~= 0
                or bit.band(physicsB.flags, PhysicsFlags.onlySameOwnerCollision) ~= 0 then
                return false
            end
        end
    end

    if relationsB.team == objB.game.arena and bit.band(physicsA.flags, PhysicsFlags.isBase) ~= 0 then
        return false
    end

    local isARect = physicsA.sides == 2
    local isBRect = physicsB.sides == 2

    if isARect and isBRect then
        return false
    elseif isARect and not isBRect then
        local dX = util.constrain(positionB.x, positionA.x - physicsA.size / 2, positionA.x + physicsA.size / 2) - positionB.x
        local dY = util.constrain(positionB.y, positionA.y - physicsA.width / 2, positionA.y + physicsA.width / 2) - positionB.y
        return dX * dX + dY * dY <= physicsB.size * physicsB.size
    elseif isBRect and not isARect then
        local dX = util.constrain(positionA.x, positionB.x - physicsB.size / 2, positionB.x + physicsB.size / 2) - positionA.x
        local dY = util.constrain(positionA.y, positionB.y - physicsB.width / 2, positionB.y + physicsB.width / 2) - positionA.y
        return dX * dX + dY * dY <= physicsA.size * physicsA.size
    else
        local dX = positionA.x - positionB.x
        local dY = positionA.y - positionB.y
        local rSum = physicsA.size + physicsB.size
        return dX * dX + dY * dY <= rSum * rSum
    end
end

function ObjectEntity.handleCollision(objA, objB)
    objA:receiveKnockback(objB)
    objB:receiveKnockback(objA)
end

function ObjectEntity:destroy(animate)
    if animate == nil then animate = true end
    if not animate then
        self.deletionAnimation = nil
        self:delete()
    elseif not self.deletionAnimation then
        self.deletionAnimation = DeletionAnimation:new(self)
    end
end

function ObjectEntity:delete()
    if self.isChild then
        local idx = util.indexOf(self.rootParent.children, self)
        if idx ~= -1 then util.removeFast(self.rootParent.children, idx) end
    else
        for i = 1, #self.children do
            self.children[i].isChild = false
            self.children[i]:delete()
        end
        self.children = {}
    end

    if bit.band(self.physicsData.values.flags, PhysicsFlags.showsOnMap) ~= 0 then
        local globalEntities = self.game.entities.globalEntities
        local idx = util.indexOf(globalEntities, self.id)
        if idx ~= -1 then util.removeFast(globalEntities, idx) end
    end

    Entity.delete(self)
end

function ObjectEntity:addVelocity(angle, magnitude)
    self.velocity:add(Vector.fromPolar(angle, magnitude))
end

function ObjectEntity:setVelocity(angle, magnitude)
    self.velocity:set(Vector.fromPolar(angle, magnitude))
end

function ObjectEntity:addAcceleration(angle, acceleration)
    self:addVelocity(angle, acceleration)
end

function ObjectEntity:maintainVelocity(angle, maxSpeed)
    self:addVelocity(angle, maxSpeed * 0.1)
end

function ObjectEntity:applyPhysics()
    if self.velocity.magnitude < 0.01 then
        self.velocity.magnitude = 0
    end
    self.positionData.x = self.positionData.values.x + self.velocity.x
    self.positionData.y = self.positionData.values.y + self.velocity.y
    self:addVelocity(self.velocity.angle, self.velocity.magnitude * -0.1)
end

function ObjectEntity:receiveKnockback(entity)
    local kbMagnitude = self.physicsData.values.absorbtionFactor * entity.physicsData.values.pushFactor
    local diffY = self.positionData.values.y - entity.positionData.values.y
    local diffX = self.positionData.values.x - entity.positionData.values.x
    local kbAngle
    if diffX == 0 and diffY == 0 then
        kbAngle = math.random() * util.PI2
    else
        kbAngle = math.atan2(diffY, diffX)
    end

    if (bit.band(entity.physicsData.values.flags, PhysicsFlags.isSolidWall) ~= 0
        or bit.band(entity.physicsData.values.flags, PhysicsFlags.isBase) ~= 0)
        and bit.band(self.positionData.values.flags, PositionFlags.canMoveThroughWalls) == 0 then
        if bit.band(entity.physicsData.values.flags, PhysicsFlags.isSolidWall) ~= 0 then
            local owner = self.relationsData.values.owner
            if owner and owner.positionData and self.relationsData.values.team ~= entity.relationsData.values.team then
                self:setVelocity(0, 0)
                self:destroy(true)
                return
            end
            self.velocity.magnitude = self.velocity.magnitude * 0.3
        end
        kbMagnitude = kbMagnitude / 0.3
    end

    if entity.physicsData.values.sides == 2 then
        if bit.band(self.positionData.values.flags, PositionFlags.canMoveThroughWalls) ~= 0 then
            kbMagnitude = 0
        else
            local relA = math.cos(kbAngle + entity.positionData.values.angle) / entity.physicsData.values.size
            local relB = math.sin(kbAngle + entity.positionData.values.angle) / entity.physicsData.values.width
            if math.abs(relA) <= math.abs(relB) then
                if relB < 0 then
                    self:addVelocity(math.pi * 3 / 2, kbMagnitude)
                else
                    self:addVelocity(math.pi / 2, kbMagnitude)
                end
            else
                if relA < 0 then
                    self:addVelocity(math.pi, kbMagnitude)
                else
                    self:addVelocity(0, kbMagnitude)
                end
            end
        end
    else
        self:addVelocity(kbAngle, kbMagnitude)
    end
end

function ObjectEntity:setParent(parent)
    self.relationsData.parent = parent
    self.rootParent = parent.rootParent
    self.rootParent.children[#self.rootParent.children + 1] = self
    self.isChild = true
    self.isPhysical = false
end

function ObjectEntity:getWorldPosition()
    local pos = Vector:new(self.positionData.values.x, self.positionData.values.y)
    local x, y = pos.x, pos.y
    local px, py, par = 0, 0, 0
    local entity = self
    while ObjectEntity.isObject(entity.relationsData.values.parent) do
        if bit.band(entity.relationsData.values.parent.positionData.values.flags, PositionFlags.absoluteRotation) == 0 then
            pos.angle = pos.angle + entity.positionData.values.angle
        end
        entity = entity.relationsData.values.parent
        px = px + entity.positionData.values.x
        py = py + entity.positionData.values.y
        if bit.band(entity.positionData.values.flags, PositionFlags.absoluteRotation) ~= 0 then
            par = par + entity.positionData.values.angle
        end
    end
    local cos = math.cos(par)
    local sin = math.sin(par)
    pos.x = px + x * cos - y * sin
    pos.y = py + x * sin + y * cos
    return pos
end

function ObjectEntity:setGlobalEntity()
    self.physicsData.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.showsOnMap)
    self.game.entities.globalEntities[#self.game.entities.globalEntities + 1] = self.id
end

function ObjectEntity:keepInArena()
    local arena = self.game.arena.arenaData
    local padding = self.game.arena.ARENA_PADDING
    if self.positionData.values.x < arena.values.leftX - padding then
        self.positionData.x = arena.values.leftX - padding
    elseif self.positionData.values.x > arena.values.rightX + padding then
        self.positionData.x = arena.values.rightX + padding
    end
    if self.positionData.values.y < arena.values.topY - padding then
        self.positionData.y = arena.values.topY - padding
    elseif self.positionData.values.y > arena.values.bottomY + padding then
        self.positionData.y = arena.values.bottomY + padding
    end
end

function ObjectEntity:scale(value)
    self.scaleFactor = self.scaleFactor * value
    self.physicsData.size = self.physicsData.values.size * value
    self.physicsData.width = self.physicsData.values.width * value
    if self.isChild then
        self.positionData.x = self.positionData.values.x * value
        self.positionData.y = self.positionData.values.y * value
    end
    for i = 1, #self.children do
        self.children[i]:scale(value)
    end
end

function ObjectEntity:tick(tick)
    if self.deletionAnimation then
        self.deletionAnimation:tick()
    end
    for i = 1, #self.children do
        self.children[i]:tick(tick)
    end
    if self.isPhysical and bit.band(self.physicsData.values.flags, PhysicsFlags.canEscapeArena) == 0 then
        self:keepInArena()
    end
end

ObjectEntity.DeletionAnimation = DeletionAnimation

return ObjectEntity
