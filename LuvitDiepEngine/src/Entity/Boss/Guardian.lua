--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local Barrel = require("../Tank/Barrel")
local AbstractBoss = require("./AbstractBoss")
local Enums = require("../../Const/Enums")
local util = require("../../util")

local Color = Enums.Color

local GuardianSpawnerDefinition = {
    angle = math.pi,
    offset = 0,
    size = 100,
    width = 71.4,
    delay = 0,
    reload = 0.36,
    recoil = 1,
    isTrapezoid = true,
    trapezoidDirection = 0,
    addon = nil,
    droneCount = 24,
    canControlDrones = true,
    bullet = {
        type = "drone",
        sizeRatio = 21 / (71.4 / 2),
        health = 12.5,
        damage = 0.56,
        speed = 1.7,
        scatterRate = 1,
        lifeLength = 1.5,
        absorbtionFactor = 1
    }
}

local GUARDIAN_SIZE = 135

local Guardian = class(AbstractBoss)

function Guardian:init(game)
    AbstractBoss.init(self, game)
    self.nameData.values.name = "Guardian"
    self.altName = "Guardian of the Pentagons"
    self.styleData.values.color = Color.EnemyCrasher
    self.relationsData.values.team = self.game.arena
    self.physicsData.values.size = GUARDIAN_SIZE * util.SQRT1_2
    self.physicsData.values.sides = 3
    self.barrels[#self.barrels + 1] = Barrel:new(self, GuardianSpawnerDefinition)
end

function Guardian:getSizeFactor()
    return (self.physicsData.values.size / util.SQRT1_2) / GUARDIAN_SIZE
end

function Guardian:moveAroundMap()
    AbstractBoss.moveAroundMap(self)
    self.positionData.angle = math.atan2(self.inputs.movement.y, self.inputs.movement.x)
end

return Guardian
