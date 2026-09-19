--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Crasher = require("../Entity/Shape/Crasher")
local Pentagon = require("../Entity/Shape/Pentagon")
local Triangle = require("../Entity/Shape/Triangle")
local Square = require("../Entity/Shape/Square")

local ShapeManager = class()

function ShapeManager:init(arena)
    self.arena = arena
    self.game = arena.game
    self.shapes = {}
end

function ShapeManager:wantedShapes()
    return 1000
end

function ShapeManager:spawnShape()
    local pos = self.arena:findSpawnLocation()
    local rightX = self.arena.arenaData.values.rightX
    local leftX = self.arena.arenaData.values.leftX
    local shape
    if math.max(pos.x, pos.y) < rightX / 10 and math.min(pos.x, pos.y) > leftX / 10 then
        shape = Pentagon:new(self.game, math.random() <= 0.05)
    elseif math.max(pos.x, pos.y) < rightX / 5 and math.min(pos.x, pos.y) > leftX / 5 then
        shape = Crasher:new(self.game, math.random() < 0.2)
    else
        local rand = math.random()
        if rand < 0.04 then
            shape = Pentagon:new(self.game)
        elseif rand < 0.20 then
            shape = Triangle:new(self.game)
        else
            shape = Square:new(self.game)
        end
    end
    shape.positionData.values.x = pos.x
    shape.positionData.values.y = pos.y
    shape.relationsData.values.owner = self.arena
    shape.relationsData.values.team = self.arena
    shape.scoreReward = shape.scoreReward * self.arena.shapeScoreRewardMultiplier
    return shape
end

function ShapeManager:killAll()
    for i = 1, #self.shapes do
        if self.shapes[i] then self.shapes[i]:delete() end
    end
end

function ShapeManager:tick()
    local wanted = self:wantedShapes()
    local spawned = 0
    for i = 1, wanted do
        local shape = self.shapes[i]
        if not shape or shape.hash == 0 then
            self.shapes[i] = self:spawnShape()
            spawned = spawned + 1
            -- Keep the event loop free so WebSocket traffic is not stalled.
            if spawned >= 40 then
                break
            end
        end
    end
end

return ShapeManager
