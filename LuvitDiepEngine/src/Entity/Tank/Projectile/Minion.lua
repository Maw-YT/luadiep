--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Drone = require("./Drone")
local Barrel = require("../Barrel")
local Enums = require("../../../Const/Enums")
local AIMod = require("../../AI")

local InputFlags = Enums.InputFlags
local PhysicsFlags = Enums.PhysicsFlags
local Inputs = AIMod.Inputs
local AIState = AIMod.AIState

local MinionBarrelDefinition = {
    angle = 0, offset = 0, size = 85, width = 50.4, delay = 0, reload = 1, recoil = 1,
    isTrapezoid = false, trapezoidDirection = 0, addon = nil,
    bullet = { type = "bullet", health = 0.4, damage = 0.4, speed = 0.8, scatterRate = 1, lifeLength = 1, sizeRatio = 1, absorbtionFactor = 1 }
}

local Minion = class(Drone)
Minion.FOCUS_RADIUS = 800 ^ 2

function Minion:init(barrel, tank, tankDefinition, shootAngle)
    Drone.init(self, barrel, tank, tankDefinition, shootAngle)
    self.inputs = self.ai.inputs
    self.ai.viewRange = 900
    self.usePosAngle = false
    self.physicsData.values.sides = 1
    self.physicsData.values.size = self.physicsData.values.size * 1.2
    self.scaleFactor = self.physicsData.values.size / 50
    if bit.band(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision) ~= 0 then
        self.physicsData.values.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision)
    end
    if bit.band(self.physicsData.values.flags, PhysicsFlags.canEscapeArena) ~= 0 then
        self.physicsData.values.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.canEscapeArena)
    end
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.onlySameOwnerCollision)
    self.cameraEntity = tank.cameraEntity
    self.reloadTime = 1
    self.minionBarrel = Barrel:new(self, MinionBarrelDefinition)
    self.ai.movementSpeed = self.baseAccel
    self.ai.aimSpeed = self.baseAccel
    self.arenaMobID = "factoryDrone"
end

function Minion:tickMixin(tick)
    self.reloadTime = self.tank.reloadTime
    local usingAI = (not self.canControlDrones) or (not self.tank.inputs:attemptingShot() and not self.tank.inputs:attemptingRepel())
    local inputs = usingAI and self.ai.inputs or self.tank.inputs
    if usingAI and self.ai.state == AIState.idle then
        self.movementAngle = self.positionData.values.angle
    else
        self.inputs.flags = bit.bor(self.inputs.flags, InputFlags.leftclick)
        local dist = inputs.mouse:distanceToSQ(self.positionData.values)
        if dist < Minion.FOCUS_RADIUS / 7 then
            self.movementAngle = self.positionData.values.angle + math.pi
        elseif dist < Minion.FOCUS_RADIUS then
            self.movementAngle = self.positionData.values.angle + math.pi / 2
        else
            self.movementAngle = self.positionData.values.angle
        end
    end
    Drone.tickMixin(self, tick)
end

return Minion
