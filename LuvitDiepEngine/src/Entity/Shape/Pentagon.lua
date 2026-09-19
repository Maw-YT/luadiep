--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local AbstractShape = require("./AbstractShape")
local Enums = require("../../Const/Enums")
local config = require("../../config")

local Pentagon = class(AbstractShape)
Pentagon.BASE_ROTATION = AbstractShape.BASE_ROTATION / 2
Pentagon.BASE_ORBIT = AbstractShape.BASE_ORBIT / 2
Pentagon.BASE_VELOCITY = AbstractShape.BASE_VELOCITY / 2

function Pentagon:init(game, isAlpha, shiny)
    if isAlpha == nil then isAlpha = false end
    if shiny == nil then shiny = (math.random() < config.shinyChance) and not isAlpha end
    AbstractShape.init(self, game)
    self.nameData.values.name = isAlpha and "Alpha Pentagon" or "Pentagon"
    self.healthData.values.health = isAlpha and 3000 or 100
    self.healthData.values.maxHealth = self.healthData.values.health
    self.physicsData.values.size = (isAlpha and 200 or 75) * math.sqrt(0.5)
    self.physicsData.values.sides = 5
    self.styleData.values.color = shiny and Enums.Color.Shiny or Enums.Color.EnemyPentagon
    self.physicsData.values.absorbtionFactor = isAlpha and 0.05 or 0.5
    self.physicsData.values.pushFactor = 11
    self.isAlpha = isAlpha
    self.isShiny = shiny
    self.damagePerTick = isAlpha and 5 or 3
    self.scoreReward = isAlpha and 3000 or 130
    if shiny then
        self.scoreReward = self.scoreReward * 100
        self.healthData.values.health = self.healthData.values.health * 10
        self.healthData.values.maxHealth = self.healthData.values.health
        self.entityTags = bit.bor(self.entityTags, Enums.EntityTags.isShiny)
    end
    self.arenaMobID = isAlpha and "alphaPentagon" or "pentagon"
end

return Pentagon
