--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local AbstractShape = require("./AbstractShape")
local Enums = require("../../Const/Enums")
local config = require("../../config")

local Triangle = class(AbstractShape)

function Triangle:init(game, shiny)
    if shiny == nil then shiny = math.random() < config.shinyChance end
    AbstractShape.init(self, game)
    self.nameData.values.name = "Triangle"
    self.healthData.values.health = 30
    self.healthData.values.maxHealth = 30
    self.physicsData.values.size = 55 * math.sqrt(0.5)
    self.physicsData.values.sides = 3
    self.styleData.values.color = shiny and Enums.Color.Shiny or Enums.Color.EnemyTriangle
    self.damagePerTick = 2
    self.scoreReward = 25
    self.isShiny = shiny
    if shiny then
        self.scoreReward = self.scoreReward * 100
        self.healthData.values.health = self.healthData.values.health * 10
        self.healthData.values.maxHealth = self.healthData.values.health
        self.entityTags = bit.bor(self.entityTags, Enums.EntityTags.isShiny)
    end
    self.arenaMobID = "triangle"
end

return Triangle
