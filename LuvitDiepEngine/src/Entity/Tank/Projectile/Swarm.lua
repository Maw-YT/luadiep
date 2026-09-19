--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../../class")
local Drone = require("./Drone")
local Enums = require("../../../Const/Enums")

local Swarm = class(Drone)

function Swarm:init(barrel, tank, tankDefinition, shootAngle)
    Drone.init(self, barrel, tank, tankDefinition, shootAngle)
    self.ai.viewRange = 2000
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, Enums.PhysicsFlags.canEscapeArena, Enums.PhysicsFlags.noOwnTeamCollision)
end

return Swarm
