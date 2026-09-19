--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local AbstractShape = require("./AbstractShape")
local Enums = require("../../Const/Enums")
local AIMod = require("../AI")
local config = require("../../config")

local Crasher = class(AbstractShape)

function Crasher:init(game, large)
    AbstractShape.init(self, game)
    self.nameData.values.name = "Crasher"
    self.positionData.values.flags = bit.bor(self.positionData.values.flags, Enums.PositionFlags.canMoveThroughWalls)
    self.healthData.values.health = large and 30 or 10
    self.healthData.values.maxHealth = self.healthData.values.health
    self.physicsData.values.size = (large and 55 or 35) * math.sqrt(0.5)
    self.physicsData.values.sides = 3
    self.physicsData.values.absorbtionFactor = large and 0.1 or 2
    self.physicsData.values.pushFactor = large and 12 or 8
    self.styleData.values.color = Enums.Color.EnemyCrasher
    self.scoreReward = large and 25 or 15
    self.damagePerTick = 2
    self.isLarge = large and true or false
    self.targettingSpeed = large and 2.64 or 2.602
    self.ai = AIMod.AI:new(self)
    self.ai.viewRange = 2000
    self.ai.aimSpeed = self.targettingSpeed
    self.ai.movementSpeed = self.targettingSpeed
    self.ai._findTargetInterval = config.tps
    self.arenaMobID = "crasher"
end

function Crasher:tick(tick)
    self.ai.aimSpeed = 0
    self.ai.movementSpeed = self.targettingSpeed
    if self.ai.state == AIMod.AIState.idle then
        self.doIdleRotate = true
    else
        self.doIdleRotate = false
        self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - self.positionData.values.y, self.ai.inputs.mouse.x - self.positionData.values.x)
        self.velocity:add({
            x = self.ai.inputs.movement.x * self.targettingSpeed,
            y = self.ai.inputs.movement.y * self.targettingSpeed
        })
    end
    self.ai.inputs.movement:set({ x = 0, y = 0 })
    AbstractShape.tick(self, tick)
end

return Crasher
