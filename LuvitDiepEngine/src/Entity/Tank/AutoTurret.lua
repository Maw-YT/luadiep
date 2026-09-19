--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local ObjectEntity = require("../Object")
local Barrel = require("./Barrel")
local FieldGroups = require("../../Native/FieldGroups")
local Enums = require("../../Const/Enums")
local AIMod = require("../AI")

local Color = Enums.Color
local PositionFlags = Enums.PositionFlags
local NameFlags = Enums.NameFlags
local PhysicsFlags = Enums.PhysicsFlags
local StyleFlags = Enums.StyleFlags
local InputFlags = Enums.InputFlags
local AI = AIMod.AI
local AIState = AIMod.AIState

local AutoTurretDefinition = {
    angle = 0, offset = 0, size = 55, width = 42 * 0.7, delay = 0.01, reload = 1, recoil = 0.3,
    isTrapezoid = false, trapezoidDirection = 0, addon = nil,
    bullet = { type = "bullet", health = 1, damage = 0.3, speed = 1.2, scatterRate = 1, lifeLength = 1, sizeRatio = 1, absorbtionFactor = 1 }
}

local AutoTurret = class(ObjectEntity)

function AutoTurret:init(owner, turretDefinition, baseSize)
    ObjectEntity.init(self, owner.game)
    turretDefinition = turretDefinition or AutoTurretDefinition
    baseSize = baseSize or 25
    self.owner = owner
    self.cameraEntity = owner.cameraEntity
    self.ai = AI:new(self)
    self.ai.doAimPrediction = true
    self.inputs = self.ai.inputs
    self:setParent(owner)
    self.relationsData.values.owner = owner
    self.relationsData.values.team = owner.relationsData.values.team
    self.baseSize = baseSize
    self.physicsData.values.sides = 1
    self.physicsData.values.size = self.baseSize * self.owner.rootParent.scaleFactor
    self.scaleFactor = self.owner.rootParent.scaleFactor
    self.styleData.values.color = Color.Barrel
    self.styleData.values.flags = bit.bor(self.styleData.values.flags, StyleFlags.showsAboveParent)
    self.positionData.values.flags = bit.bor(self.positionData.values.flags, PositionFlags.absoluteRotation)
    self.nameData = FieldGroups.NameGroup:new(self)
    self.nameData.values.name = "Mounted Turret"
    self.nameData.values.flags = bit.bor(self.nameData.values.flags, NameFlags.hiddenName)
    self.reloadTime = 15
    self.influencedByOwnerInputs = false
    self.turret = Barrel:new(self, turretDefinition)
    self.turret.physicsData.values.flags = bit.bor(self.turret.physicsData.values.flags, PhysicsFlags.doChildrenCollision)
end

function AutoTurret:onKill(killedEntity, weapon)
    if self.owner and self.owner.onKill then
        self.owner:onKill(killedEntity, weapon)
    end
end

function AutoTurret:tick(tick)
    if self.inputs ~= self.ai.inputs then self.inputs = self.ai.inputs end
    self.relationsData.values.team = self.owner.relationsData.values.team
    if self.ai.state == AIState.hasTarget then
        self.ai.passiveRotation = (math.random() < 0.5) and AI.PASSIVE_ROTATION or -AI.PASSIVE_ROTATION
    end
    self.ai.aimSpeed = self.turret.bulletAccel
    self.ai.movementSpeed = 0
    self.reloadTime = self.owner.reloadTime
    self.turret:calculateStatData()
    local useAI = not (self.influencedByOwnerInputs and (self.owner.inputs:attemptingRepel() or self.owner.inputs:attemptingShot()))
    if not useAI then
        local pos = self:getWorldPosition()
        local flip = self.owner.inputs:attemptingRepel() and -1 or 1
        local deltaPos = { x = (self.owner.inputs.mouse.x - pos.x) * flip, y = (self.owner.inputs.mouse.y - pos.y) * flip }
        if self.ai.targetFilter({ x = pos.x + deltaPos.x, y = pos.y + deltaPos.y }) == false then
            useAI = true
        else
            self.inputs.flags = bit.bor(self.inputs.flags, InputFlags.leftclick)
            self.positionData.angle = math.atan2(deltaPos.y, deltaPos.x)
            self.ai.state = AIState.hasTarget
        end
    end
    if useAI then
        if self.ai.state == AIState.idle then
            self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
            self.turret.attemptingShot = false
        else
            local pos = self:getWorldPosition()
            self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - pos.y, self.ai.inputs.mouse.x - pos.x)
        end
    end
end

AutoTurret.AutoTurretDefinition = AutoTurretDefinition

return AutoTurret
