--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ObjectEntity = require("./Object")
local FieldGroups = require("../Native/FieldGroups")
local Enums = require("../Const/Enums")

local StyleFlags = Enums.StyleFlags

local LivingEntity = class(ObjectEntity)

function LivingEntity.isLive(entity)
    if not ObjectEntity.isObject(entity) then return false end
    return entity.healthData ~= nil
end

function LivingEntity:init(game)
    ObjectEntity.init(self, game)
    self.healthData = FieldGroups.HealthGroup:new(self)
    self.scoreReward = 0
    self.regenPerTick = 0
    self.damagePerTick = 8
    self.damagedEntities = {}
    self.lastDamageTick = -1
    self.lastDamageAnimationTick = -1
    self.damageReduction = 1.0
    self.minDamageMultiplier = 1.0
    self.maxDamageMultiplier = 4.0
    self.opacityGainOnDamage = 0.0
end

function LivingEntity:destroy(animate)
    if animate == nil then animate = true end
    if self.hash == 0 then return end
    if animate then
        self.healthData.health = 0
    end
    ObjectEntity.destroy(self, animate)
end

function LivingEntity.handleCollision(entity1, entity2)
    if entity1.relationsData.values.team and entity1.relationsData.values.team == entity2.relationsData.values.team then
        return
    end
    if entity1.healthData.values.health <= 0 or entity2.healthData.values.health <= 0 then return end
    for i = 1, #entity1.damagedEntities do
        if entity1.damagedEntities[i] == entity2 then return end
    end
    for i = 1, #entity2.damagedEntities do
        if entity2.damagedEntities[i] == entity1 then return end
    end
    if entity1.damageReduction == 0 and entity2.damageReduction == 0 then return end
    if (entity1.damagePerTick == 0 and entity1.physicsData.values.pushFactor == 0)
        or (entity2.damagePerTick == 0 and entity2.physicsData.values.pushFactor == 0) then
        return
    end

    local common = math.max(entity2.minDamageMultiplier, entity1.minDamageMultiplier)
    common = common * math.min(entity2.maxDamageMultiplier, entity1.maxDamageMultiplier)
    local dF1 = (entity1.damagePerTick * common) * entity2.damageReduction
    local dF2 = (entity2.damagePerTick * common) * entity1.damageReduction
    local ratio = math.max(1 - entity1.healthData.values.health / dF2, 1 - entity2.healthData.values.health / dF1)
    local damage1to2 = dF1 * math.min(1, 1 - ratio)
    local damage2to1 = dF2 * math.min(1, 1 - ratio)
    entity1:receiveDamage(entity2, damage2to1)
    entity2:receiveDamage(entity1, damage1to2)
end

function LivingEntity:receiveDamage(source, amount)
    if self.healthData.values.health <= 0.0001 then
        self.healthData.health = 0
        return
    end
    self.damagedEntities[#self.damagedEntities + 1] = source
    if self.lastDamageAnimationTick ~= self.game.tick
        and bit.band(self.styleData.values.flags, StyleFlags.hasNoDmgIndicator) == 0 then
        self.styleData.flags = bit.bxor(self.styleData.values.flags, StyleFlags.hasBeenDamaged)
        self.lastDamageAnimationTick = self.game.tick
    end
    self.lastDamageTick = self.game.tick
    self.healthData.health = self.healthData.values.health - amount
    if self.healthData.health <= 0.0001 then
        self.healthData.health = 0
        local killer = source
        while ObjectEntity.isObject(killer.relationsData.values.owner) and killer.relationsData.values.owner.hash ~= 0 do
            killer = killer.relationsData.values.owner
        end
        if LivingEntity.isLive(killer) then
            self:onDeath(killer)
        end
        source:onKill(self, source)
    end
end

function LivingEntity:onKill(entity, weapon)
end

function LivingEntity:onDeath(killer)
end

function LivingEntity:applyPhysics()
    ObjectEntity.applyPhysics(self)
    if self.healthData.values.health <= 0 then
        self:destroy(true)
        self.damagedEntities = {}
        return
    end
    if self.healthData.values.health < self.healthData.values.maxHealth then
        self.healthData.health = self.healthData.values.health + self.regenPerTick
        if self.game.tick - self.lastDamageTick >= 750 then
            self.healthData.health = self.healthData.values.health + self.healthData.values.maxHealth / 250
        end
    end
    if self.healthData.values.health > self.healthData.values.maxHealth then
        self.healthData.health = self.healthData.values.maxHealth
    end
    self.damagedEntities = {}
end

function LivingEntity:tick(tick)
    ObjectEntity.tick(self, tick)
end

return LivingEntity
