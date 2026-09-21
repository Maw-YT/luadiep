--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local LivingEntity = require("../Live")
local TeamEntity = require("./TeamEntity")
local Enums = require("../../Const/Enums")

local PhysicsFlags = Enums.PhysicsFlags
local StyleFlags = Enums.StyleFlags
local HealthFlags = Enums.HealthFlags

local TeamBase = class(LivingEntity)

function TeamBase:init(game, team, x, y, width, height, shielded)
    LivingEntity.init(self, game)
    if shielded == nil then shielded = true end

    self:setGlobalEntity()
    self.relationsData.values.team = team
    if TeamEntity.isTeam(team) then
        team.base = self
    end

    self.positionData.values.x = x
    self.positionData.values.y = y
    self.physicsData.values.width = width
    self.physicsData.values.size = height
    self.physicsData.values.sides = 2
    self.physicsData.values.flags = bit.bor(
        self.physicsData.values.flags,
        PhysicsFlags.noOwnTeamCollision,
        PhysicsFlags.isBase
    )
    self.physicsData.values.pushFactor = 2
    self.physicsData.values.absorbtionFactor = 0

    self.styleData.values.opacity = 0.1
    self.styleData.values.borderWidth = 0
    self.styleData.values.color = team.teamData.values.teamColor
    self.styleData.values.flags = bit.bor(
        self.styleData.values.flags,
        StyleFlags.renderFirst,
        StyleFlags.hasNoDmgIndicator
    )

    self.damagePerTick = 5
    self.minDamageMultiplier = 1
    self.maxDamageMultiplier = 1
    self.damageReduction = 0

    if not shielded then
        self.physicsData.values.pushFactor = 0
        self.damagePerTick = 0
    end

    self.healthData.flags = bit.bor(self.healthData.values.flags, HealthFlags.hiddenHealthbar)
    self.healthData.maxHealth = 0xABCFF
    self.healthData.health = 0xABCFF
end

function TeamBase:tick(tick)
    self.healthData.health = self.healthData.values.maxHealth
    self.lastDamageTick = tick
end

return TeamBase
