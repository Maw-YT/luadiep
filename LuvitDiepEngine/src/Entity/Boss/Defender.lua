--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local Barrel = require("../Tank/Barrel")
local AutoTurret = require("../Tank/AutoTurret")
local AbstractBoss = require("./AbstractBoss")
local Enums = require("../../Const/Enums")
local util = require("../../util")
local AIMod = require("../AI")

local Color = Enums.Color
local PositionFlags = Enums.PositionFlags
local AIState = AIMod.AIState

local MountedTurretDefinition = AbstractBoss.cloneBarrelDefinition(AutoTurret.AutoTurretDefinition, {
    bullet = {
        speed = 2.46,
        damage = 1.2,
        health = 5.75,
        color = Color.Neutral
    }
})

local TrapperDefinition = {
    angle = 0,
    offset = 0,
    size = 120,
    width = 71.4,
    delay = 0,
    reload = 5,
    recoil = 2,
    isTrapezoid = false,
    trapezoidDirection = 0,
    addon = "trapLauncher",
    forceFire = true,
    bullet = {
        type = "trap",
        sizeRatio = 0.8,
        health = 12.5,
        damage = 4,
        speed = 5,
        scatterRate = 1,
        lifeLength = 8,
        absorbtionFactor = 1,
        color = Color.Neutral
    }
}

local DEFENDER_SIZE = 150

local Defender = class(AbstractBoss)

function Defender:init(game)
    AbstractBoss.init(self, game)
    self.movementSpeed = 0.2
    self.nameData.values.name = "Defender"
    self.styleData.values.color = Color.EnemyTriangle
    self.relationsData.values.team = self.game.arena
    self.ai.viewRange = 0
    self.ai.passiveRotation = self.ai.passiveRotation * 2
    self.physicsData.values.sides = 3
    self.physicsData.values.size = DEFENDER_SIZE * util.SQRT1_2

    local count = self.physicsData.values.sides
    local offset = 60 / (DEFENDER_SIZE * util.SQRT1_2)
    for i = 0, count - 1 do
        self.barrels[#self.barrels + 1] = Barrel:new(self, AbstractBoss.cloneBarrelDefinition(TrapperDefinition, {
            angle = util.PI2 * ((i / count) + 1 / (count * 2))
        }))

        local base = AutoTurret:new(self, MountedTurretDefinition)
        base.influencedByOwnerInputs = true
        local angle = util.PI2 * (i / count)
        base.ai.inputs.mouse.angle = angle
        base.positionData.values.y = self.physicsData.values.size * math.sin(angle) * offset
        base.positionData.values.x = self.physicsData.values.size * math.cos(angle) * offset
        base.positionData.values.flags = bit.bor(base.positionData.values.flags, PositionFlags.absoluteRotation)
    end
end

function Defender:getSizeFactor()
    return (self.physicsData.values.size / util.SQRT1_2) / DEFENDER_SIZE
end

function Defender:tick(tick)
    AbstractBoss.tick(self, tick)
    if self.ai.state ~= AIState.possessed then
        self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
    end
end

return Defender
