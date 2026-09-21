--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Entity = require("./Entity")
local FieldGroups = require("./FieldGroups")
local Enums = require("../Const/Enums")
local config = require("../config")
local util = require("../util")
local ObjectEntity = require("../Entity/Object")
local compiler = require("./UpcreateCompiler")

local CameraFlags = Enums.CameraFlags
local ClientBound = Enums.ClientBound
local EntityStateFlags = Enums.EntityStateFlags
local maxPlayerLevel = config.maxPlayerLevel

local CameraEntity = class(Entity)

function CameraEntity:init(game)
    self._isCamera = true
    Entity.init(self, game)
    self.cameraData = FieldGroups.CameraGroup:new(self)
    self.relationsData = FieldGroups.RelationsGroup:new(self)
    self.spectatee = nil
end

function CameraEntity:getClient()
    return nil
end

function CameraEntity:setFieldFactor(fieldFactor)
    self.cameraData.FOV = (0.55 * fieldFactor) / (1.01 ^ ((self.cameraData.values.level - 1) / 2))
end

function CameraEntity.calculateStatCount(level)
    if level <= 0 then return 0 end
    if level <= 28 then return level - 1 end
    return math.floor(level / 3) + 18
end

function CameraEntity:setLevel(level)
    local TankBody = require("../Entity/Tank/TankBody")
    local TankDefinitions = require("../Const/TankDefinitions")
    local previousLevel = self.cameraData.values.level
    self.cameraData.level = level
    self.cameraData.levelbarMax = level < maxPlayerLevel and 1 or 0
    local levelScore = Enums.levelToScore(level)
    local isMaxLevel = level <= maxPlayerLevel
    local player = self.cameraData.values.player
    if isMaxLevel then self.cameraData.score = levelScore end
    local client = self:getClient()
    if client and client.inputs.isPossessing then return end
    if TankBody.isTank(player) then
        local scaleFactor = 1.01 ^ (level - previousLevel)
        player:scale(scaleFactor)
        player:calculateStatData()
        if isMaxLevel then
            player.scoreData.score = levelScore
            player.scoreReward = levelScore
        end
    end
    local statIncrease = CameraEntity.calculateStatCount(level) - CameraEntity.calculateStatCount(previousLevel)
    self.cameraData.statsAvailable = self.cameraData.values.statsAvailable + statIncrease
    local def = TankDefinitions.getTankById(self.cameraData.values.tank)
    self:setFieldFactor(def and def.fieldFactor or 1)
    self:calculateLevelData()
    if not self.game.enableAchievements then return end
    client = self:getClient()
    if not client then return end
    require("../Const/Achievements").sendEvent(client, "levelUp", {
        level = level,
        class = self.cameraData.values.tank
    })
end

function CameraEntity:addScore(score)
    local TankBody = require("../Entity/Tank/TankBody")
    self.cameraData.score = self.cameraData.values.score + score
    local player = self.cameraData.values.player
    if player and player.scoreData then
        player.scoreData.score = player.scoreData.values.score + score
    end
    self:calculateLevelData()
    if not self.game.enableAchievements then return end
    local client = self:getClient()
    if not client then return end
    require("../Const/Achievements").sendEvent(client, "score", {
        total = self.cameraData.values.score,
        delta = score,
        class = self.cameraData.values.tank
    })
end

function CameraEntity:setScore(score)
    self.cameraData.score = score
    local player = self.cameraData.values.player
    if player and player.scoreData then
        player.scoreData.score = score
    end
    self:calculateLevelData()
    if not self.game.enableAchievements then return end
    local client = self:getClient()
    if not client then return end
    require("../Const/Achievements").sendEvent(client, "score", {
        total = self.cameraData.values.score,
        delta = score,
        class = self.cameraData.values.tank
    })
end

function CameraEntity:addStat(statId, amount)
    local TankBody = require("../Entity/Tank/TankBody")
    self.cameraData.values.statLevels:set(statId, self.cameraData.values.statLevels:get(statId) + amount)
    local player = self.cameraData.values.player
    if TankBody.isTank(player) then player:calculateStatData() end
    if not self.game.enableAchievements then return end
    local client = self:getClient()
    if not client then return end
    require("../Const/Achievements").sendEvent(client, "statUpgraded", {
        id = statId,
        isMaxLevel = self.cameraData.values.statLevels:get(statId) >= self.cameraData.values.statLimits:get(statId)
    })
end

function CameraEntity:setStat(statId, amount)
    local TankBody = require("../Entity/Tank/TankBody")
    self.cameraData.values.statLevels:set(statId, amount)
    local player = self.cameraData.values.player
    if TankBody.isTank(player) then player:calculateStatData() end
    if not self.game.enableAchievements then return end
    local client = self:getClient()
    if not client then return end
    require("../Const/Achievements").sendEvent(client, "statUpgraded", {
        id = statId,
        isMaxLevel = self.cameraData.values.statLevels:get(statId) >= self.cameraData.values.statLimits:get(statId)
    })
end

function CameraEntity:calculateLevelData()
    local TankBody = require("../Entity/Tank/TankBody")
    local player = self.cameraData.values.player
    if not TankBody.isTank(player) then return end
    local score = self.cameraData.values.score
    local newLevel = self.cameraData.values.level
    while newLevel < #Enums.levelToScoreTable + 1 and score - Enums.levelToScore(newLevel + 1) >= 0 do
        newLevel = newLevel + 1
        if newLevel >= config.maxPlayerLevel then break end
    end
    if newLevel ~= self.cameraData.values.level then
        self:setLevel(newLevel)
        self.cameraData.score = score
        player.scoreData.score = score
    end
    if newLevel < config.maxPlayerLevel then
        local levelScore = Enums.levelToScore(self.cameraData.values.level)
        self.cameraData.levelbarMax = Enums.levelToScore(self.cameraData.values.level + 1) - levelScore
        self.cameraData.levelbarProgress = score - levelScore
    end
end

function CameraEntity:tick(tick)
    if Entity.exists(self.cameraData.values.player) then
        local focus = self.cameraData.values.player
        if bit.band(self.cameraData.values.flags, CameraFlags.usesCameraCoords) == 0 and ObjectEntity.isObject(focus) then
            self.cameraData.cameraX = focus.rootParent.positionData.values.x
            self.cameraData.cameraY = focus.rootParent.positionData.values.y
        end
    else
        self.cameraData.flags = bit.bor(self.cameraData.values.flags, CameraFlags.usesCameraCoords)
    end
end

local ClientCamera = class(CameraEntity)

function ClientCamera:init(game, client)
    CameraEntity.init(self, game)
    self.client = client
    self.view = {}
    self.cameraData.values.respawnLevel = 1
    self.cameraData.values.level = 1
    self.cameraData.values.score = 1
    self.cameraData.values.FOV = 0.35
    self.relationsData.values.team = self
end

function ClientCamera:getClient()
    return self.client
end

function ClientCamera:addToView(entity)
    self.view[#self.view + 1] = entity
end

function ClientCamera:removeFromView(id)
    for i = 1, #self.view do
        if self.view[i].id == id then
            util.removeFast(self.view, i)
            return
        end
    end
end

function ClientCamera:inView(entity)
    for i = 1, #self.view do
        local seen = self.view[i]
        if seen == entity then return true end
        if entity and seen.id == entity.id and seen.hash == entity.hash then
            return true
        end
    end
    return false
end

function ClientCamera:updateView(tick)
    local w = self.client:write():u8(ClientBound.Update):vu(tick)
    local deletes, updates, creations = {}, {}, {}
    local fov = self.cameraData.values.FOV
    if not fov or fov <= 0.01 then fov = 0.35 end
    local viewW = 1920 / fov
    local viewH = 1080 / fov
    local client = self.client
    if client and client.viewW and client.viewW > 1 then viewW = client.viewW end
    if client and client.viewH and client.viewH > 1 then viewH = client.viewH end
    -- Same slack as diepcustom: half-extent is full view / 1.5, so the
    -- network box is a bit larger than the on-screen frustum.
    local width = viewW / 1.5
    local height = viewH / 1.5
    local entitiesNearRange = self.game.entities.collisionManager:retrieve(
        self.cameraData.values.cameraX, self.cameraData.values.cameraY, width, height
    )
    local entitiesInRange = {}
    local seen = {}
    local l = self.cameraData.values.cameraX - width
    local r = self.cameraData.values.cameraX + width
    local t = self.cameraData.values.cameraY - height
    local b = self.cameraData.values.cameraY + height

    local function consider(id)
        local entity = self.game.entities.inner[id]
        if not entity or not ObjectEntity.isObject(entity) then return end
        local p = entity.physicsData.values
        local wdt = p.sides == 2 and p.size / 2 or p.size
        local size = p.sides == 2 and p.width / 2 or p.size
        if bit.band(p.flags or 0, Enums.PhysicsFlags.isBeam) ~= 0 then
            local rad = math.max(wdt, size)
            wdt, size = rad, rad
        end
        local pos = entity.positionData.values
        if pos.x - wdt < r and pos.y + size > t and pos.x + wdt > l and pos.y - size < b then
            if entity ~= self.cameraData.values.player and not (entity.styleData.values.opacity == 0 and not entity.deletionAnimation) then
                if not seen[id] then
                    entitiesInRange[#entitiesInRange + 1] = entity
                    seen[id] = true
                end
            end
        end
    end

    entitiesNearRange:forEach(consider)

    for i = 1, #self.game.entities.globalEntities do
        local entity = self.game.entities.inner[self.game.entities.globalEntities[i]]
        if entity and not seen[entity.id] then
            entitiesInRange[#entitiesInRange + 1] = entity
            seen[entity.id] = true
        end
    end

    if Entity.exists(self.cameraData.values.player) and ObjectEntity.isObject(self.cameraData.values.player) then
        entitiesInRange[#entitiesInRange + 1] = self.cameraData.values.player
    end

    local inRangeSet = {}
    for i = 1, #entitiesInRange do
        inRangeSet[entitiesInRange[i]] = true
    end

    for i = #self.view, 1, -1 do
        local entity = self.view[i]
        if ObjectEntity.isObject(entity) then
            if not inRangeSet[entity.rootParent] then
                deletes[#deletes + 1] = { id = entity.id, hash = entity.preservedHash }
            elseif entity.hash == 0 then
                deletes[#deletes + 1] = { id = entity.id, hash = entity.preservedHash }
            elseif bit.band(entity.entityState, EntityStateFlags.needsCreate) ~= 0 then
                if bit.band(entity.entityState, EntityStateFlags.needsDelete) ~= 0 then
                    deletes[#deletes + 1] = { hash = entity.hash, id = entity.id, noDelete = true }
                end
                creations[#creations + 1] = entity
            elseif bit.band(entity.entityState, EntityStateFlags.needsUpdate) ~= 0 then
                updates[#updates + 1] = entity
            end
        else
            if entity.hash == 0 then
                deletes[#deletes + 1] = { id = entity.id, hash = entity.preservedHash }
            elseif bit.band(entity.entityState, EntityStateFlags.needsCreate) ~= 0 then
                if bit.band(entity.entityState, EntityStateFlags.needsDelete) ~= 0 then
                    deletes[#deletes + 1] = { hash = entity.hash, id = entity.id, noDelete = true }
                end
                creations[#creations + 1] = entity
            elseif bit.band(entity.entityState, EntityStateFlags.needsUpdate) ~= 0 then
                updates[#updates + 1] = entity
            end
        end
    end

    w:vu(#deletes)
    for i = 1, #deletes do
        w:entid(deletes[i])
        if not deletes[i].noDelete then
            self:removeFromView(deletes[i].id)
        end
    end

    if #self.view == 0 then
        creations[#creations + 1] = self.game.arena
        creations[#creations + 1] = self
        self.view[#self.view + 1] = self.game.arena
        self.view[#self.view + 1] = self
    end

    local entities = self.game.entities
    for i = 1, #entities.otherEntities do
        local id = entities.otherEntities[i]
        local found = false
        for j = 1, #self.view do
            if self.view[j].id == id then found = true break end
        end
        if not found then
            local entity = entities.inner[id]
            if entity and not entity.cameraData then
                creations[#creations + 1] = entity
                self:addToView(entity)
            end
        end
    end

    for i = 1, #entitiesInRange do
        local entity = entitiesInRange[i]
        if not self:inView(entity) then
            creations[#creations + 1] = entity
            self:addToView(entity)
            if ObjectEntity.isObject(entity) and #entity.children > 0 and not entity.isChild then
                for c = 1, #entity.children do
                    self.view[#self.view + 1] = entity.children[c]
                    creations[#creations + 1] = entity.children[c]
                end
            end
        else
            if ObjectEntity.isObject(entity) and #entity.children > 0 and not entity.isChild then
                for c = 1, #entity.children do
                    local child = entity.children[c]
                    if not self:inView(child) then
                        for cc = 1, #entity.children do
                            self.view[#self.view + 1] = entity.children[cc]
                            creations[#creations + 1] = entity.children[cc]
                        end
                        break
                    end
                end
            end
        end
    end

    w:vu(#creations + #updates)
    for i = 1, #updates do
        compiler.compileUpdate(self, w, updates[i])
    end
    for i = 1, #creations do
        compiler.compileCreation(self, w, creations[i])
    end
    w:send()
end

function ClientCamera:tick(tick)
    CameraEntity.tick(self, tick)
    if not Entity.exists(self.cameraData.values.player) then
        if Entity.exists(self.spectatee) then
            local pos = self.spectatee.rootParent.positionData.values
            self.cameraData.cameraX = pos.x
            self.cameraData.cameraY = pos.y
            self.cameraData.flags = bit.bor(self.cameraData.values.flags, CameraFlags.usesCameraCoords)
        end
    end
    self:updateView(tick)
end

return {
    CameraEntity = CameraEntity,
    ClientCamera = ClientCamera
}
