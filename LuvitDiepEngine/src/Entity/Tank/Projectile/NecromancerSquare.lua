--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Drone = require("./Drone")
local Enums = require("../../../Const/Enums")
local AIMod = require("../../AI")

local Color = Enums.Color
local PhysicsFlags = Enums.PhysicsFlags

local NecromancerSquare = class(Drone)

function NecromancerSquare:init(barrel, tank, tankDefinition, shootAngle)
    Drone.init(self, barrel, tank, tankDefinition, shootAngle)
    local bulletDefinition = barrel.definition.bullet
    self.ai = AIMod.AI:new(self)
    self.ai.viewRange = 900
    self.physicsData.values.sides = 4
    local team = tank.relationsData.values.team
    self.styleData.values.color = (team and team.teamData and team.teamData.values.teamColor) or Color.NecromancerSquare
    if bit.band(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision) ~= 0 then
        self.physicsData.values.flags = bit.bxor(self.physicsData.values.flags, PhysicsFlags.noOwnTeamCollision)
    end
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.onlySameOwnerCollision)
    self.minDamageMultiplier = 1
    self.maxDamageMultiplier = 4
    self.physicsData.values.pushFactor = 4
    self.physicsData.values.absorbtionFactor = bulletDefinition.absorbtionFactor
    self.baseSpeed = 0
end

function NecromancerSquare.fromShape(barrel, tank, tankDefinition, shape)
    local sunchip = NecromancerSquare:new(barrel, tank, tankDefinition, shape.positionData.values.angle)
    sunchip.physicsData.values.sides = shape.physicsData.values.sides
    sunchip.physicsData.values.size = shape.physicsData.values.size
    sunchip.positionData.values.x = shape.positionData.values.x
    sunchip.positionData.values.y = shape.positionData.values.y
    sunchip.positionData.values.angle = shape.positionData.values.angle
    local shapeDamagePerTick = shape.damagePerTick
    sunchip.damagePerTick = sunchip.damagePerTick * shapeDamagePerTick / 2
    sunchip.healthData.values.health = sunchip.healthData.values.health * (shapeDamagePerTick / 2)
    sunchip.healthData.values.maxHealth = sunchip.healthData.values.health
    sunchip.scoreReward = shape.scoreReward
    return sunchip
end

return NecromancerSquare
