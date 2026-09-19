--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local LivingEntity = require("../Live")
local ObjectEntity = require("../Object")
local TankBody = require("../Tank/TankBody")
local FieldGroups = require("../../Native/FieldGroups")
local Enums = require("../../Const/Enums")
local AIMod = require("../AI")

local Color = Enums.Color
local PositionFlags = Enums.PositionFlags
local EntityTags = Enums.EntityTags
local AI = AIMod.AI
local AIState = AIMod.AIState

local Target = {
    None = -1,
    BottomRight = 0,
    TopRight = 1,
    TopLeft = 2,
    BottomLeft = 3
}

local BossMovementControl = class()

function BossMovementControl:init(boss)
    self.target = Target.None
    self.boss = boss
end

function BossMovementControl:moveBoss()
    local x = self.boss.positionData.values.x
    local y = self.boss.positionData.values.y
    if self.target == Target.None then
        if x >= 0 and y >= 0 then
            self.target = Target.BottomRight
        elseif x <= 0 and y >= 0 then
            self.target = Target.BottomLeft
        elseif x <= 0 and y <= 0 then
            self.target = Target.TopLeft
        else
            self.target = Target.TopRight
        end
    end

    local arena = self.boss.game.arena.arenaData.values
    local target
    if self.target == Target.BottomRight then
        target = { x = 3 * arena.rightX / 4, y = 3 * arena.bottomY / 4 }
    elseif self.target == Target.BottomLeft then
        target = { x = 3 * arena.leftX / 4, y = 3 * arena.bottomY / 4 }
    elseif self.target == Target.TopLeft then
        target = { x = 3 * arena.leftX / 4, y = 3 * arena.topY / 4 }
    else
        target = { x = 3 * arena.rightX / 4, y = 3 * arena.topY / 4 }
    end

    target.x = target.x - x
    target.y = target.y - y
    local dist = target.x * target.x + target.y * target.y
    if dist < 90000 then
        self.target = (self.target + 1) % 4
    else
        local angle = math.atan2(target.y, target.x)
        self.boss.inputs.movement.x = math.cos(angle)
        self.boss.inputs.movement.y = math.sin(angle)
    end
end

local AbstractBoss = class(LivingEntity)

function AbstractBoss.cloneBarrelDefinition(definition, extra)
    local out = {}
    for k, v in pairs(definition) do
        if k == "bullet" and type(v) == "table" then
            local bullet = {}
            for bk, bv in pairs(v) do
                bullet[bk] = bv
            end
            out.bullet = bullet
        else
            out[k] = v
        end
    end
    if extra then
        for k, v in pairs(extra) do
            if k == "bullet" and type(v) == "table" then
                out.bullet = out.bullet or {}
                for bk, bv in pairs(v) do
                    out.bullet[bk] = bv
                end
            else
                out[k] = v
            end
        end
    end
    return out
end

function AbstractBoss.isBoss(entity)
    if not ObjectEntity.isObject(entity) then return false end
    return bit.band(entity.entityTags or 0, EntityTags.isBoss) ~= 0
end

function AbstractBoss:init(game)
    LivingEntity.init(self, game)
    self.nameData = FieldGroups.NameGroup:new(self)
    self.altName = nil
    self.reloadTime = 15
    self.barrels = {}
    self.movementSpeed = 0.5
    self.hasBeenWelcomed = false
    self.cameraEntity = self
    self.movementControl = BossMovementControl:new(self)

    self.relationsData.values.team = self.cameraEntity
    self.physicsData.values.absorbtionFactor = 0.05
    self.positionData.values.flags = bit.bor(self.positionData.values.flags, PositionFlags.absoluteRotation)
    self.scoreReward = 30000 * self.game.arena.shapeScoreRewardMultiplier
    self.damagePerTick = 10

    self.ai = AI:new(self)
    self.ai.viewRange = 2000
    self.ai._findTargetInterval = 0
    self.inputs = self.ai.inputs

    self.styleData.values.color = Color.Fallen
    self.physicsData.values.sides = 1
    self.physicsData.values.size = 50
    self.reloadTime = 15 * (0.914 ^ 7)
    self.healthData.values.maxHealth = 3000
    self.healthData.values.health = 3000
    self.entityTags = bit.bor(self.entityTags, EntityTags.isBoss)
end

function AbstractBoss:getSizeFactor()
    return self.physicsData.values.size / 50
end

function AbstractBoss:moveAroundMap()
    self.movementControl:moveBoss()
end

function AbstractBoss:onDeath(killer)
    local killerName = "an unnamed tank"
    if TankBody.isTank(killer) or AbstractBoss.isBoss(killer) then
        killerName = (killer.nameData and killer.nameData.values.name) or "an unnamed tank"
        if killerName == "" then killerName = "an unnamed tank" end
    end
    local bossName = self.altName or (self.nameData and self.nameData.values.name) or "unnamed boss"
    self.game:broadcastMessage("The " .. bossName .. " has been defeated by " .. killerName .. "!", 0x000000, 10000, "")
end

function AbstractBoss:tick(tick)
    if self.inputs ~= self.ai.inputs then
        self.inputs = self.ai.inputs
    end

    self.ai.movementSpeed = self.movementSpeed

    if self.ai.state ~= AIState.possessed then
        self:moveAroundMap()
    else
        local x = self.positionData.values.x
        local y = self.positionData.values.y
        self.positionData.angle = math.atan2(self.ai.inputs.mouse.y - y, self.ai.inputs.mouse.x - x)
    end

    self.velocity:add({
        x = self.inputs.movement.x * self.movementSpeed,
        y = self.inputs.movement.y * self.movementSpeed
    })
    self.inputs.movement:set({ x = 0, y = 0 })

    self.regenPerTick = self.healthData.values.maxHealth / 25000

    if not self.hasBeenWelcomed then
        local message = "An unnamed boss has spawned!"
        local name = self.nameData and self.nameData.values.name
        if name and name ~= "" then
            message = "The " .. (self.altName or name) .. " has spawned!"
        end
        self.game:broadcastMessage(message, 0x000000, 10000, "")
        self.hasBeenWelcomed = true
    end

    LivingEntity.tick(self, tick)
end

AbstractBoss.BossMovementControl = BossMovementControl
AbstractBoss.AIState = AIState

return AbstractBoss
