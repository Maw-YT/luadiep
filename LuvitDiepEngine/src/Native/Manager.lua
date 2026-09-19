--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local HashGrid = require("../Physics/HashGrid")
local ObjectEntity = require("../Entity/Object")
local LivingEntity = require("../Entity/Live")
local Entity = require("./Entity")
local util = require("../util")

local EntityManager = class()

function EntityManager:init(game)
    self.game = game
    self.collisionManager = HashGrid:new(game)
    self.zIndex = 0
    self.cameras = {}
    self.otherEntities = {}
    self.globalEntities = {}
    self.inner = {}
    self.AIs = {}
    self.hashTable = {}
    for i = 0, 16383 do
        self.inner[i] = nil
        self.hashTable[i] = 0
    end
    self.lastId = -1
end

function EntityManager:add(entity)
    local lastId = self.lastId + 1
    for id = 0, lastId do
        if not self.inner[id] then
            entity.id = id
            local h = (self.hashTable[id] or 0) + 1
            if h > 255 then h = 1 end
            if h == 0 then h = 1 end
            self.hashTable[id] = h
            entity.hash = h
            entity.preservedHash = h
            self.inner[id] = entity
            if entity._isObject then
                -- ObjectEntity, inserted in preTick
            elseif entity._isCamera then
                self.cameras[#self.cameras + 1] = id
            else
                self.otherEntities[#self.otherEntities + 1] = id
            end
            if self.lastId < id then self.lastId = entity.id end
            return entity
        end
    end
    error("OOEI: Out Of Entity IDs")
end

function EntityManager:delete(id)
    local entity = self.inner[id]
    if not entity then
        error("Deleting entity that isn't in the game?")
    end
    entity.hash = 0
    if entity._isObject then
        -- collision manager
    elseif entity._isCamera then
        local idx = util.indexOf(self.cameras, id)
        if idx ~= -1 then util.removeFast(self.cameras, idx) end
    else
        local idx = util.indexOf(self.otherEntities, id)
        if idx ~= -1 then util.removeFast(self.otherEntities, idx) end
    end
    self.inner[id] = nil
end

function EntityManager:clear()
    self.lastId = -1
    self.collisionManager:postTick(self.game.tick)
    for i = 0, 16383 do self.hashTable[i] = 0 end
    self.AIs = {}
    self.otherEntities = {}
    self.cameras = {}
    for i = 0, 16383 do
        local entity = self.inner[i]
        if entity then
            entity.hash = 0
            self.inner[i] = nil
        end
    end
end

function EntityManager:handleCollision(entityA, entityB)
    if not ObjectEntity.isColliding(entityA, entityB) then return end
    ObjectEntity.handleCollision(entityA, entityB)
    if LivingEntity.isLive(entityA) and LivingEntity.isLive(entityB) then
        LivingEntity.handleCollision(entityA, entityB)
    end
end

function EntityManager:preTick(tick)
    self.collisionManager:preTick(tick)
    while not self.inner[self.lastId] and self.lastId >= 0 do
        self.lastId = self.lastId - 1
    end
    for id = 0, self.lastId do
        local entity = self.inner[id]
        if Entity.exists(entity) then
            if ObjectEntity.isObject(entity) and entity.isPhysical then
                self.collisionManager:insert(entity)
            end
        end
    end
end

function EntityManager:postTick(tick)
    self.collisionManager:postTick(tick)
    for id = 0, self.lastId do
        local entity = self.inner[id]
        if entity then
            entity:wipeState()
        end
    end
end

function EntityManager:tick(tick)
    local this = self
    self.collisionManager:forEachCollisionPair(function(a, b)
        this:handleCollision(a, b)
    end)

    for id = 0, self.lastId do
        local entity = self.inner[id]
        if entity and entity.hash ~= 0 then
            if entity.cameraData then
                -- cameras later
            elseif ObjectEntity.isObject(entity) then
                if entity.isPhysical then
                    entity:applyPhysics()
                end
                if not entity.isChild then
                    entity:tick(tick)
                end
            else
                entity:tick(tick)
            end
        end
    end

    for i = #self.AIs, 1, -1 do
        if not Entity.exists(self.AIs[i].owner) then
            util.removeFast(self.AIs, i)
        else
            self.AIs[i]:tick(tick)
        end
    end

    for i = 1, #self.cameras do
        local cam = self.inner[self.cameras[i]]
        if cam then cam:tick(tick) end
    end
end

return EntityManager
