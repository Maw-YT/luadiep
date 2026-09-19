--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Barrel = require("../../Tank/Barrel")
local AbstractBoss = require("../../Boss/AbstractBoss")
local TankDefs = require("../../../Const/TankDefinitions")
local Enums = require("../../../Const/Enums")
local AIMod = require("../../AI")

local Tank = Enums.Tank
local AIState = AIMod.AIState

local FallenMegaTrapper = class(AbstractBoss)

function FallenMegaTrapper:init(game)
    AbstractBoss.init(self, game)
    self.movementSpeed = 1
    self.nameData.values.name = "Fallen Mega Trapper"
    local tank = TankDefs.getTankById(Tank.MegaTrapper)
    for _, barrelDefinition in ipairs(tank.barrels) do
        self.barrels[#self.barrels + 1] = Barrel:new(self, AbstractBoss.cloneBarrelDefinition(barrelDefinition, {
            reload = 4,
            bullet = { speed = 1.7, damage = 20, health = 20 }
        }))
    end
    self:scale(1.01 ^ 74)
    if self.barrels[1] then
        self.ai.aimSpeed = self.barrels[1].bulletAccel
    end
end

function FallenMegaTrapper:getSizeFactor()
    return self.physicsData.values.size / 50
end

function FallenMegaTrapper:moveAroundMap()
    if self.ai.state == AIState.idle then
        self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
        self:setVelocity(0, 0)
    else
        local x = self.positionData.values.x
        local y = self.positionData.values.y
        self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - y, self.ai.inputs.mouse.x - x)
    end
end

return FallenMegaTrapper
