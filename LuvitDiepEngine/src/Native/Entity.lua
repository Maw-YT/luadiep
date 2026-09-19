--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Enums = require("../Const/Enums")

local Entity = class()

function Entity.exists(entity)
    return entity ~= nil and (entity.hash or 0) ~= 0
end

function Entity:init(game)
    self.game = game
    self.entityState = 0
    self.relationsData = nil
    self.barrelData = nil
    self.physicsData = nil
    self.healthData = nil
    self.arenaData = nil
    self.nameData = nil
    self.cameraData = nil
    self.positionData = nil
    self.styleData = nil
    self.scoreData = nil
    self.teamData = nil
    self.id = -1
    self.hash = 0
    self.preservedHash = 0
    game.entities:add(self)
end

function Entity:wipeState()
    if self.relationsData then self.relationsData:wipe() end
    if self.barrelData then self.barrelData:wipe() end
    if self.physicsData then self.physicsData:wipe() end
    if self.healthData then self.healthData:wipe() end
    if self.arenaData then self.arenaData:wipe() end
    if self.nameData then self.nameData:wipe() end
    if self.cameraData then self.cameraData:wipe() end
    if self.positionData then self.positionData:wipe() end
    if self.styleData then self.styleData:wipe() end
    if self.scoreData then self.scoreData:wipe() end
    if self.teamData then self.teamData:wipe() end
    self.entityState = 0
end

function Entity:delete()
    self:wipeState()
    self.game.entities:delete(self.id)
end

function Entity:tick(tick)
end

return Entity
