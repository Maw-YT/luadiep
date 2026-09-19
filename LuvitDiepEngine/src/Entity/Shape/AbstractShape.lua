--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local LivingEntity = require("../Live")
local ObjectEntity = require("../Object")
local FieldGroups = require("../../Native/FieldGroups")
local Enums = require("../../Const/Enums")
local util = require("../../util")
local AIMod = require("../AI")

local Color = Enums.Color
local PositionFlags = Enums.PositionFlags
local NameFlags = Enums.NameFlags
local EntityTags = Enums.EntityTags

local TURN_TIMEOUT = 300

local AbstractShape = class(LivingEntity)
AbstractShape.BASE_ROTATION = AIMod.AI.PASSIVE_ROTATION
AbstractShape.BASE_ORBIT = 0.005
AbstractShape.BASE_VELOCITY = 1

function AbstractShape.isShape(entity)
    if not ObjectEntity.isObject(entity) then return false end
    return bit.band(entity.entityTags or 0, EntityTags.isShape) ~= 0
end

function AbstractShape:init(game)
    LivingEntity.init(self, game)
    self.nameData = FieldGroups.NameGroup:new(self)
    self.isShiny = false
    self.doIdleRotate = true
    self.relationsData.values.team = game.arena
    self.nameData.values.flags = NameFlags.hiddenName
    self.positionData.values.flags = bit.bor(self.positionData.values.flags, PositionFlags.absoluteRotation)
    self.orbitAngle = math.random() * util.PI2
    self.positionData.values.angle = self.orbitAngle
    self.maxDamageMultiplier = 4.0
    self.entityTags = bit.bor(self.entityTags, EntityTags.isShape)
    local ctor = getmetatable(self)
    local baseOrbit = (ctor and ctor.BASE_ORBIT) or AbstractShape.BASE_ORBIT
    local baseRot = (ctor and ctor.BASE_ROTATION) or AbstractShape.BASE_ROTATION
    local baseVel = (ctor and ctor.BASE_VELOCITY) or AbstractShape.BASE_VELOCITY
    self.orbitRate = ((math.random() < 0.5) and -1 or 1) * baseOrbit
    self.rotationRate = ((math.random() < 0.5) and -1 or 1) * baseRot
    self.shapeVelocity = baseVel
    self.isTurning = 0
    self.targetTurningAngle = 0
end

function AbstractShape:turnTo(angle)
    if util.normalizeAngle(self.orbitAngle - angle) < 0.20 then return end
    self.targetTurningAngle = angle
    self.isTurning = TURN_TIMEOUT
end

function AbstractShape:tick(tick)
    if not self.doIdleRotate then
        return LivingEntity.tick(self, tick)
    end
    local y = self.positionData.values.y
    local x = self.positionData.values.x
    if self.isTurning == 0 then
        if x > self.game.arena.arenaData.values.rightX - 400
            or x < self.game.arena.arenaData.values.leftX + 400
            or y < self.game.arena.arenaData.values.topY + 400
            or y > self.game.arena.arenaData.values.bottomY - 400 then
            self:turnTo(math.pi + math.atan2(y, x))
        elseif x > self.game.arena.arenaData.values.rightX - 500 then
            self:turnTo((self.orbitRate >= 0 and 1 or -1) * math.pi / 2)
        elseif x < self.game.arena.arenaData.values.leftX + 500 then
            self:turnTo(-1 * (self.orbitRate >= 0 and 1 or -1) * math.pi / 2)
        elseif y < self.game.arena.arenaData.values.topY + 500 then
            self:turnTo(self.orbitRate > 0 and 0 or math.pi)
        elseif y > self.game.arena.arenaData.values.bottomY - 500 then
            self:turnTo(self.orbitRate > 0 and math.pi or 0)
        end
    end
    self.positionData.angle = self.positionData.values.angle + self.rotationRate
    self.orbitAngle = self.orbitAngle + self.orbitRate + ((self.isTurning == TURN_TIMEOUT) and self.orbitRate * 10 or 0)
    if self.isTurning == TURN_TIMEOUT and util.normalizeAngle(self.orbitAngle - self.targetTurningAngle) < 0.20 then
        self.isTurning = self.isTurning - 1
    elseif self.isTurning ~= TURN_TIMEOUT and self.isTurning ~= 0 then
        self.isTurning = self.isTurning - 1
    end
    self:maintainVelocity(self.orbitAngle, self.shapeVelocity)
    LivingEntity.tick(self, tick)
end

return AbstractShape
