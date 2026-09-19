--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local Barrel = require("../Tank/Barrel")
local AbstractBoss = require("./AbstractBoss")
local TankDefs = require("../../Const/TankDefinitions")
local Enums = require("../../Const/Enums")
local AIMod = require("../AI")

local Tank = Enums.Tank
local AIState = AIMod.AIState

local FallenOverlord = class(AbstractBoss)

function FallenOverlord:init(game)
    AbstractBoss.init(self, game)
    self.nameData.values.name = "Fallen Overlord"
    local tank = TankDefs.getTankById(Tank.Overlord)
    for _, barrelDefinition in ipairs(tank.barrels) do
        self.barrels[#self.barrels + 1] = Barrel:new(self, AbstractBoss.cloneBarrelDefinition(barrelDefinition, {
            droneCount = 7,
            reload = 0.36,
            bullet = { sizeRatio = 0.5, speed = 1.7, damage = 0.56, health = 12.5 }
        }))
    end
    self:scale(1.01 ^ 74)
end

function FallenOverlord:tick(tick)
    AbstractBoss.tick(self, tick)
    if self.ai.state ~= AIState.possessed then
        self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
    end
end

return FallenOverlord
