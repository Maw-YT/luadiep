--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local Barrel = require("../Tank/Barrel")
local AbstractBoss = require("./AbstractBoss")
local Enums = require("../../Const/Enums")
local util = require("../../util")
local AIMod = require("../AI")

local Color = Enums.Color
local AIState = AIMod.AIState

local SummonerSpawnerDefinition = {
    angle = math.pi,
    offset = 0,
    size = 135,
    width = 71.4,
    delay = 0,
    reload = 0.36,
    recoil = 1,
    isTrapezoid = true,
    trapezoidDirection = 0,
    addon = nil,
    droneCount = 7,
    canControlDrones = true,
    bullet = {
        type = "drone",
        sizeRatio = 55 * util.SQRT1_2 / (71.4 / 2),
        health = 12.5,
        damage = 0.56,
        speed = 1.7,
        scatterRate = 1,
        lifeLength = -1,
        absorbtionFactor = 1,
        color = Color.NecromancerSquare,
        sides = 4
    }
}

local SUMMONER_SIZE = 150

local Summoner = class(AbstractBoss)

function Summoner:init(game)
    AbstractBoss.init(self, game)
    self.nameData.values.name = "Summoner"
    self.styleData.values.color = Color.EnemySquare
    self.relationsData.values.team = self.game.arena
    self.physicsData.values.size = SUMMONER_SIZE * util.SQRT1_2
    self.physicsData.values.sides = 4

    local count = self.physicsData.values.sides
    for i = 0, count - 1 do
        self.barrels[#self.barrels + 1] = Barrel:new(self, AbstractBoss.cloneBarrelDefinition(SummonerSpawnerDefinition, {
            angle = util.PI2 * (i / 4)
        }))
    end
end

function Summoner:getSizeFactor()
    return (self.physicsData.values.size / util.SQRT1_2) / SUMMONER_SIZE
end

function Summoner:tick(tick)
    AbstractBoss.tick(self, tick)
    if self.ai.state ~= AIState.possessed then
        self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
    end
end

return Summoner
