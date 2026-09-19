--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local AbstractBoss = require("../../Boss/AbstractBoss")
local AIMod = require("../../AI")

local AIState = AIMod.AIState

local FallenSpike = class(AbstractBoss)

function FallenSpike:init(game)
    AbstractBoss.init(self, game)
    self.movementSpeed = 3.0
    self.nameData.values.name = "Fallen Spike"
    self.damagePerTick = self.damagePerTick * 2
    local SpikeAddon = require("../../Tank/Addons").AddonById.spike
    if SpikeAddon then SpikeAddon:new(self) end
    self:scale(1.01 ^ 74)
end

function FallenSpike:getSizeFactor()
    return self.physicsData.values.size / 50
end

function FallenSpike:moveAroundMap()
    if self.ai.state == AIState.idle then
        self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
        self:setVelocity(0, 0)
    else
        local x = self.positionData.values.x
        local y = self.positionData.values.y
        self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - y, self.ai.inputs.mouse.x - x)
    end
end

return FallenSpike
