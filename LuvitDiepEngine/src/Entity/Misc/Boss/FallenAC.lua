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

local FallenAC = class(AbstractBoss)

function FallenAC:init(game)
    AbstractBoss.init(self, game)
    self.nameData.values.name = "Fallen Arena Closer"
    self.movementSpeed = 20
    local tank = TankDefs.getTankById(Tank.ArenaCloser)
    for _, barrelDefinition in ipairs(tank.barrels) do
        self.barrels[#self.barrels + 1] = Barrel:new(self, AbstractBoss.cloneBarrelDefinition(barrelDefinition))
    end
    self:scale(1.01 ^ 74)
end

function FallenAC:getSizeFactor()
    return self.physicsData.values.size / 50
end

function FallenAC:moveAroundMap()
    if self.ai.state == AIState.idle then
        self.positionData.angle = self.positionData.values.angle + self.ai.passiveRotation
        self:setVelocity(0, 0)
    else
        local x = self.positionData.values.x
        local y = self.positionData.values.y
        self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - y, self.ai.inputs.mouse.x - x)
    end
end

return FallenAC
