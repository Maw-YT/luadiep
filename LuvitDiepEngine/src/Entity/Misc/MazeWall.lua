--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local ObjectEntity = require("../Object")
local Enums = require("../../Const/Enums")

local MazeWall = class(ObjectEntity)

function MazeWall:init(arena, x, y, width, height)
    ObjectEntity.init(self, arena.game)
    self:setGlobalEntity()
    self.positionData.values.x = x
    self.positionData.values.y = y
    self.physicsData.values.width = height
    self.physicsData.values.size = width
    self.physicsData.values.sides = 2
    self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, Enums.PhysicsFlags.isSolidWall)
    self.physicsData.values.pushFactor = 2
    self.physicsData.values.absorbtionFactor = 0
    self.relationsData.values.team = arena
    self.styleData.values.borderWidth = 10
    self.styleData.values.color = Enums.Color.Box
end

function MazeWall:tick(tick)
end

function MazeWall:applyPhysics()
end

return MazeWall
