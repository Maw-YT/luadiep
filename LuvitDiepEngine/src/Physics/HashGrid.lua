--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local PackedEntitySet = require("./PackedEntitySet")

local CELL_SHIFT = 8
local MAX_ENTITY_COUNT = 16384
local PAIR_WORDS = math.floor(MAX_ENTITY_COUNT * (MAX_ENTITY_COUNT - 1) / 2 / 32)

local HashGrid = class()

function HashGrid:init(game)
    self.game = game
    self.resultSet = PackedEntitySet:new()
    self.lastQueryId = 0
    self.queryIdMap = {}
    for i = 0, 16383 do self.queryIdMap[i] = 0 end
    self.isLocked = true
    self.hashMul = 1
    self.hashMap = {}
    self.gameLeftX = 0
    self.gameTopY = 0
    self.collisionPairsSeen = {}
    for i = 0, PAIR_WORDS - 1 do
        self.collisionPairsSeen[i] = 0
    end
end

function HashGrid:preTick(tick)
    local widthInCells = bit.rshift(self.game.arena.width + 255, CELL_SHIFT)
    local heightInCells = bit.rshift(self.game.arena.height + 255, CELL_SHIFT)
    self.hashMul = widthInCells
    self.hashMap = {}
    for i = 0, 16383 do self.queryIdMap[i] = 0 end
    self.lastQueryId = 0
    self.gameLeftX = self.game.arena.arenaData.values.leftX
    self.gameTopY = self.game.arena.arenaData.values.topY
    self.isLocked = false
end

function HashGrid:postTick(tick)
    self.isLocked = true
    self.hashMap = {}
end

local function cellKey(self, x, y)
    return math.abs(x + (y * self.hashMul))
end

function HashGrid:insert(entity)
    local physics = entity.physicsData.values
    local pos = entity.positionData.values
    local isLine = physics.sides == 2
    local halfWidth = isLine and (physics.size / 2) or physics.size
    local halfHeight = isLine and (physics.width / 2) or physics.size

    local topX = bit.arshift(bit.tobit(pos.x - halfWidth - self.gameLeftX), CELL_SHIFT)
    local topY = bit.arshift(bit.tobit(pos.y - halfHeight - self.gameTopY), CELL_SHIFT)
    local bottomX = bit.arshift(bit.tobit(pos.x + halfWidth - self.gameLeftX), CELL_SHIFT)
    local bottomY = bit.arshift(bit.tobit(pos.y + halfHeight - self.gameTopY), CELL_SHIFT)

    for y = topY, bottomY do
        for x = topX, bottomX do
            local key = cellKey(self, x, y)
            local cell = self.hashMap[key]
            if not cell then
                self.hashMap[key] = { entity.id }
            else
                cell[#cell + 1] = entity.id
            end
        end
    end
end

function HashGrid:_nextQueryId()
    local queryId = (self.lastQueryId == 0xFFFF) and 1 or (self.lastQueryId + 1)
    self.lastQueryId = queryId
    return queryId
end

function HashGrid:retrieve(centerX, centerY, halfWidth, halfHeight)
    local result = self.resultSet
    result:clear()

    local startX = bit.arshift(bit.tobit(centerX - halfWidth - self.gameLeftX), CELL_SHIFT)
    local startY = bit.arshift(bit.tobit(centerY - halfHeight - self.gameTopY), CELL_SHIFT)
    local endX = bit.arshift(bit.tobit(centerX + halfWidth - self.gameLeftX), CELL_SHIFT)
    local endY = bit.arshift(bit.tobit(centerY + halfHeight - self.gameTopY), CELL_SHIFT)

    local queryId = self:_nextQueryId()

    for y = startY, endY do
        for x = startX, endX do
            local cell = self.hashMap[cellKey(self, x, y)]
            if cell then
                for i = 1, #cell do
                    local entityId = cell[i]
                    if self.queryIdMap[entityId] ~= queryId then
                        self.queryIdMap[entityId] = queryId
                        local entity = self.game.entities.inner[entityId]
                        if entity and entity.hash ~= 0 then
                            result:add(entityId)
                        end
                    end
                end
            end
        end
    end

    return result
end

function HashGrid:getFirstMatch(centerX, centerY, halfWidth, halfHeight, predicate)
    local startX = bit.arshift(bit.tobit(centerX - halfWidth - self.gameLeftX), CELL_SHIFT)
    local startY = bit.arshift(bit.tobit(centerY - halfHeight - self.gameTopY), CELL_SHIFT)
    local endX = bit.arshift(bit.tobit(centerX + halfWidth - self.gameLeftX), CELL_SHIFT)
    local endY = bit.arshift(bit.tobit(centerY + halfHeight - self.gameTopY), CELL_SHIFT)

    local queryId = self:_nextQueryId()

    for y = startY, endY do
        for x = startX, endX do
            local cell = self.hashMap[cellKey(self, x, y)]
            if cell then
                for i = 1, #cell do
                    local entityId = cell[i]
                    if self.queryIdMap[entityId] ~= queryId then
                        self.queryIdMap[entityId] = queryId
                        local entity = self.game.entities.inner[entityId]
                        if entity and entity.hash ~= 0 and predicate(entity) then
                            return entity
                        end
                    end
                end
            end
        end
    end

    return nil
end

function HashGrid:retrieveEntitiesByEntity(entity)
    local physics = entity.physicsData.values
    local pos = entity.positionData.values
    local isLine = physics.sides == 2
    local halfWidth = isLine and (physics.size / 2) or physics.size
    local halfHeight = isLine and (physics.width / 2) or physics.size
    return self:retrieve(pos.x, pos.y, halfWidth, halfHeight)
end

function HashGrid:forEachCollisionPair(callback)
    local collisionsSeen = self.collisionPairsSeen
    for i = 0, PAIR_WORDS - 1 do
        collisionsSeen[i] = 0
    end

    for _, cell in pairs(self.hashMap) do
        if cell and #cell >= 2 then
            for a = 1, #cell - 1 do
                local eidA = cell[a]
                local entityA = self.game.entities.inner[eidA]
                if entityA and entityA.hash ~= 0 then
                    for b = a + 1, #cell do
                        local eidB = cell[b]
                        if eidA ~= eidB then
                            local entityB = self.game.entities.inner[eidB]
                            if entityB and entityB.hash ~= 0 then
                                local idA, idB, entA, entB
                                if eidA < eidB then
                                    idA, idB, entA, entB = eidA, eidB, entityA, entityB
                                else
                                    idA, idB, entA, entB = eidB, eidA, entityB, entityA
                                end
                                local triangularIndex = math.floor(idB * (idB - 1) / 2) + idA
                                local arrayIndex = bit.rshift(triangularIndex, 5)
                                local bitIndex = bit.band(triangularIndex, 31)
                                local bitMask = bit.lshift(1, bitIndex)
                                if bit.band(collisionsSeen[arrayIndex] or 0, bitMask) == 0 then
                                    collisionsSeen[arrayIndex] = bit.bor(collisionsSeen[arrayIndex] or 0, bitMask)
                                    callback(entA, entB)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

return HashGrid
