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

local FallenBooster = class(AbstractBoss)

function FallenBooster:init(game)
    AbstractBoss.init(self, game)
    self.movementSpeed = 1
    self.nameData.values.name = "Fallen Booster"
    local tank = TankDefs.getTankById(Tank.Booster)
    for _, barrelDefinition in ipairs(tank.barrels) do
        self.barrels[#self.barrels + 1] = Barrel:new(self, AbstractBoss.cloneBarrelDefinition(barrelDefinition, {
            bullet = {
                speed = 1.7,
                health = 6.25,
                damage = barrelDefinition.bullet.damage * 0.8
            }
        }))
    end
    self:scale(1.01 ^ 74)
end

function FallenBooster:moveAroundMap()
    local x = self.positionData.values.x
    local y = self.positionData.values.y
    if self.ai.state == AIState.idle then
        AbstractBoss.moveAroundMap(self)
        self.positionData.angle = math.atan2(self.inputs.movement.y, self.inputs.movement.x)
    else
        self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - y, self.ai.inputs.mouse.x - x)
    end
end

return FallenBooster
