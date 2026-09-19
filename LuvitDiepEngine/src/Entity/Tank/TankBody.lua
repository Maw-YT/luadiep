--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local LivingEntity = require("../Live")
local ObjectEntity = require("../Object")
local FieldGroups = require("../../Native/FieldGroups")
local Enums = require("../../Const/Enums")
local config = require("../../config")
local util = require("../../util")
local Entity = require("../../Native/Entity")
local TankDefs = require("../../Const/TankDefinitions")
local DevTankDefinitions = require("../../Const/DevTankDefinitions")

local Color = Enums.Color
local StyleFlags = Enums.StyleFlags
local StatCount = Enums.StatCount
local Tank = Enums.Tank
local CameraFlags = Enums.CameraFlags
local Stat = Enums.Stat
local InputFlags = Enums.InputFlags
local PhysicsFlags = Enums.PhysicsFlags
local PositionFlags = Enums.PositionFlags
local NameFlags = Enums.NameFlags
local HealthFlags = Enums.HealthFlags
local EntityTags = Enums.EntityTags
local EntityStateFlags = Enums.EntityStateFlags

local TankBody = class(LivingEntity)

function TankBody.isTank(entity)
    if not ObjectEntity.isObject(entity) then return false end
    return bit.band(entity.entityTags or 0, EntityTags.isTank) ~= 0
end

function TankBody:init(game, camera, inputs)
    LivingEntity.init(self, game)
    self.nameData = FieldGroups.NameGroup:new(self)
    self.scoreData = FieldGroups.ScoreGroup:new(self)
    self.cameraEntity = camera
    self.inputs = inputs
    self.barrels = {}
    self.addons = {}
    self.baseSize = 50
    self.reloadTime = 15
    self._currentTank = Tank.Basic
    self.isInvulnerable = false
    self.physicsData.values.size = 50
    self.physicsData.values.sides = 1
    self.styleData.values.color = Color.Tank
    self.relationsData.values.team = camera
    self.relationsData.values.owner = camera
    self.cameraEntity.cameraData.spawnTick = game.tick
    self.cameraEntity.cameraData.flags = bit.bor(self.cameraEntity.cameraData.values.flags, CameraFlags.showingDeathStats)
    self.cameraEntity.cameraData.killedBy = ""
    self.styleData.values.flags = bit.bor(self.styleData.values.flags, StyleFlags.isFlashing)
    self.damageReduction = 0
    if self.game.playersOnMap then self:setGlobalEntity() end
    self.damagePerTick = 5
    self.maxDamageMultiplier = 6
    self.entityTags = bit.bor(self.entityTags, EntityTags.isTank)
    self.definition = TankDefs.getTankById(Tank.Basic)
    self:setTank(Tank.Basic)
end

function TankBody:setTank(id)
    local AddonById = require("./Addons").AddonById
    local Barrel = require("./Barrel")
    for i = 1, #self.children do
        self.children[i].isChild = false
        self.children[i]:delete()
    end
    self.children = {}
    self.barrels = {}
    self.addons = {}
    local tank = TankDefs.getTankById(id)
    local camera = self.cameraEntity
    if not tank then error("Invalid tank ID: " .. tostring(id)) end
    self.definition = tank
    if not Entity.exists(camera) then error("No camera") end
    self.physicsData.sides = tank.sides
    self.styleData.opacity = 1.0
    for i = 0, StatCount - 1 do
        local stat = tank.stats[i + 1] or tank.stats[i]
        if stat then
            camera.cameraData.values.statLimits:set(i, stat.max)
            camera.cameraData.values.statNames:set(i, stat.name)
            if camera.cameraData.values.statLevels:get(i) > stat.max then
                local extra = camera.cameraData.values.statLevels:get(i) - stat.max
                camera.cameraData.values.statLevels:set(i, stat.max)
                camera.cameraData.statsAvailable = camera.cameraData.values.statsAvailable + extra
            end
        end
    end
    if tank.baseSizeOverride then
        self.baseSize = tank.baseSizeOverride
    elseif tank.sides == 4 then
        self.baseSize = util.SQRT2 * 32.5
    elseif tank.sides == 16 then
        self.baseSize = util.SQRT2 * 25
    else
        self.baseSize = 50
    end
    self.physicsData.size = self.baseSize * self.scaleFactor
    self.physicsData.absorbtionFactor = self.isInvulnerable and 0 or tank.absorbtionFactor
    if tank.absorbtionFactor == 0 then
        self.positionData.flags = bit.bor(self.positionData.values.flags, PositionFlags.canMoveThroughWalls)
    elseif bit.band(self.positionData.values.flags, PositionFlags.canMoveThroughWalls) ~= 0 then
        self.positionData.flags = bit.bxor(self.positionData.values.flags, PositionFlags.canMoveThroughWalls)
    end
    self._currentTank = id
    camera.cameraData.tank = id
    if tank.preAddon then
        local AddonConstructor = AddonById[tank.preAddon]
        if AddonConstructor then self.addons[#self.addons + 1] = AddonConstructor:new(self) end
    end
    if tank.barrels then
        for _, barrel in ipairs(tank.barrels) do
            self.barrels[#self.barrels + 1] = Barrel:new(self, barrel)
        end
    end
    if tank.postAddon then
        local AddonConstructor = AddonById[tank.postAddon]
        if AddonConstructor then self.addons[#self.addons + 1] = AddonConstructor:new(self) end
    end
    self.cameraEntity.cameraData.tankOverride = tank.name
    camera:setFieldFactor(tank.fieldFactor)
    self:scale(1)
    self:calculateStatData()
    local client = camera:getClient()
    if client and tank.upgradeMessage and tank.upgradeMessage ~= "" then
        client:notify(tank.upgradeMessage, 0x000000, 10000)
    end
    if client and self.game.enableAchievements then
        require("../../Const/Achievements").sendEvent(client, "classChange", {
            class = id
        })
    end
end

function TankBody:onKill(entity, weapon)
    if Entity.exists(self.cameraEntity.cameraData.values.player) and entity ~= self then
        self.cameraEntity:addScore(entity.scoreReward)
    end
    local client = self.cameraEntity:getClient()
    if client then
        if entity.nameData and bit.band(entity.nameData.values.flags, NameFlags.hiddenName) == 0 then
            client:notify("You've killed " .. ((entity.nameData.values.name ~= "" and entity.nameData.values.name) or "an unnamed tank"))
        end
        if self.game.enableAchievements then
            local AbstractBoss = require("../Boss/AbstractBoss")
            local victimIsTank = TankBody.isTank(entity)
            require("../../Const/Achievements").sendEvent(client, "kill", {
                ["weapon.isTank"] = TankBody.isTank(weapon),
                ["victim.arenaMobID"] = entity.arenaMobID,
                ["victim.isTank"] = victimIsTank,
                ["victim.isBoss"] = AbstractBoss.isBoss(entity),
                ["victim.isShiny"] = bit.band(entity.entityTags or 0, EntityTags.isShiny) ~= 0,
                class = self._currentTank,
                ["victim.class"] = victimIsTank and (entity._currentTank or -1) or -1
            })
        end
    end
    if entity.arenaMobID == "square" and self.definition.flags and self.definition.flags.canClaimSquares and #self.barrels > 0 then
        local MAX_DRONES_PER_BARREL = 11 + self.cameraEntity.cameraData.values.statLevels:get(Stat.Reload)
        local barrelsToShoot = {}
        for i = 1, #self.barrels do
            local e = self.barrels[i]
            if e.definition.bullet and e.definition.bullet.type == "necrodrone" and e.droneCount < MAX_DRONES_PER_BARREL then
                barrelsToShoot[#barrelsToShoot + 1] = e
            end
        end
        if #barrelsToShoot > 0 then
            local barrelToShoot = util.randomFrom(barrelsToShoot)
            entity:destroy(true)
            if entity.deletionAnimation then
                entity.deletionAnimation.frame = 0
                entity.styleData.opacity = 1
                entity.healthData.flags = HealthFlags.hiddenHealthbar
            end
            local NecromancerSquare = require("./Projectile/NecromancerSquare")
            NecromancerSquare.fromShape(barrelToShoot, self, self.definition, entity)
        end
    end
end

function TankBody:setInvulnerability(invulnerable)
    if bit.band(self.styleData.flags, StyleFlags.isFlashing) ~= 0 then
        self.styleData.flags = bit.bxor(self.styleData.values.flags, StyleFlags.isFlashing)
    end
    if self.isInvulnerable == invulnerable then return end
    if invulnerable then
        self.damageReduction = 0.0
        self.physicsData.absorbtionFactor = 0.0
    else
        self.damageReduction = 1.0
        self.physicsData.absorbtionFactor = self.definition.absorbtionFactor
    end
    self.isInvulnerable = invulnerable
end

function TankBody:receiveDamage(source, amount)
    if amount > 0 and self.damageReduction ~= 0 then
        if self.game.tick ~= self.lastDamageTick and self.styleData.values.opacity < 1 then
            self.styleData.opacity = self.styleData.values.opacity + TankDefs.visibilityRateDamage
        end
        if self.styleData.values.opacity > 1 then self.styleData.opacity = 1 end
    end
    LivingEntity.receiveDamage(self, source, amount)
end

function TankBody:calculateStatData()
    self.damagePerTick = self.cameraEntity.cameraData.values.statLevels:get(Stat.BodyDamage) + 5 + (self.definition.bodyDamage or 0)
    local maxHealthCache = self.healthData.values.maxHealth
    self.healthData.maxHealth = self.definition.maxHealth + 2 * (self.cameraEntity.cameraData.values.level - 1) + self.cameraEntity.cameraData.values.statLevels:get(Stat.MaxHealth) * 20
    if self.healthData.values.health == maxHealthCache then
        self.healthData.health = self.healthData.maxHealth
    elseif self.healthData.values.maxHealth ~= maxHealthCache then
        self.healthData.health = self.healthData.values.health * self.healthData.values.maxHealth / maxHealthCache
    end
    self.regenPerTick = (self.healthData.values.maxHealth * 4 * self.cameraEntity.cameraData.values.statLevels:get(Stat.HealthRegen) + self.healthData.values.maxHealth) / 25000
    self.reloadTime = 15 * (0.914 ^ self.cameraEntity.cameraData.values.statLevels:get(Stat.Reload))
    self.cameraEntity.cameraData.movementSpeed =
        self.definition.speed * 2.55 * (1.07 ^ self.cameraEntity.cameraData.values.statLevels:get(Stat.MovementSpeed)) / (1.015 ^ (self.cameraEntity.cameraData.values.level - 1))
    for i = 1, #self.barrels do
        self.barrels[i]:calculateStatData()
    end
end

function TankBody:onDeath(killer)
    local client = self.cameraEntity:getClient()
    if not client then
        self.cameraEntity:delete()
        return
    end
    if self.cameraEntity.cameraData.player ~= self then return end
    self.cameraEntity.spectatee = killer
    self.cameraEntity.cameraData.killedBy = (killer.nameData and killer.nameData.values.name) or ""
end

function TankBody:destroy(animate)
    if animate == nil then animate = true end
    if not animate and Entity.exists(self.cameraEntity) then
        if self.cameraEntity.cameraData.player == self then
            self.cameraEntity.cameraData.deathTick = self.game.tick
            self.cameraEntity.cameraData.respawnLevel = math.min(math.max(self.cameraEntity.cameraData.values.level - 1, 1), math.floor(math.sqrt(self.cameraEntity.cameraData.values.level) * 3.2796))
        end
        self.barrels = {}
        self.addons = {}
    end
    LivingEntity.destroy(self, animate)
end

function TankBody:delete()
    if self.cameraEntity.cameraData.values.player == self then
        self.cameraEntity.cameraData.FOV = 0.4
        -- Drop the player pointer so the client does not keep a stale
        -- {id,hash} that can be reused by the next entity (AC bullets, etc).
        self.cameraEntity.cameraData.player = nil
    end
    LivingEntity.delete(self)
end

function TankBody:tick(tick)
    self.positionData.angle = math.atan2(self.inputs.mouse.y - self.positionData.values.y, self.inputs.mouse.x - self.positionData.values.x)
    if self.isInvulnerable then
        if self.game.clients.size ~= 1 or self.game.arena:isOpen() == false then
            local client = self.cameraEntity:getClient()
            if client and client.accessLevel < config.AccessLevel.FullAccess then
                self:setInvulnerability(false)
            end
        end
    end
    if self.deletionAnimation or self.inputs.deleted then self.regenPerTick = 0 end
    LivingEntity.tick(self, tick)
    if self.deletionAnimation then return end
    if self.inputs.deleted then
        if self.cameraEntity.cameraData.values.level <= 5 then
            self:destroy()
            return
        end
        self.lastDamageTick = tick
        self.healthData.health = self.healthData.values.health - (2 + self.healthData.values.maxHealth / 500)
        if self.isInvulnerable then self:setInvulnerability(false) end
        if bit.band(self.styleData.values.flags, StyleFlags.isFlashing) ~= 0 then
            self.styleData.flags = bit.bxor(self.styleData.values.flags, StyleFlags.isFlashing)
            self.damageReduction = 1.0
        end
        return
    end
    if self.definition.flags and self.definition.flags.zoomAbility and bit.band(self.inputs.flags, InputFlags.rightclick) ~= 0 then
        if bit.band(self.cameraEntity.cameraData.values.flags, CameraFlags.usesCameraCoords) == 0 then
            local angle = math.atan2(self.inputs.mouse.y - self.positionData.values.y, self.inputs.mouse.x - self.positionData.values.x)
            self.cameraEntity.cameraData.cameraX = math.cos(angle) * 1500 + self.positionData.values.x
            self.cameraEntity.cameraData.cameraY = math.sin(angle) * 1500 + self.positionData.values.y
            self.cameraEntity.cameraData.flags = bit.bor(self.cameraEntity.cameraData.values.flags, CameraFlags.usesCameraCoords)
        end
    elseif bit.band(self.cameraEntity.cameraData.values.flags, CameraFlags.usesCameraCoords) ~= 0 then
        self.cameraEntity.cameraData.flags = bit.bxor(self.cameraEntity.cameraData.values.flags, CameraFlags.usesCameraCoords)
    end
    if self.definition.flags and self.definition.flags.invisibility then
        if bit.band(self.inputs.flags, InputFlags.leftclick) ~= 0 then
            self.styleData.opacity = self.styleData.values.opacity + (self.definition.visibilityRateShooting or 0)
        end
        if bit.band(self.inputs.flags, bit.bor(InputFlags.up, InputFlags.down, InputFlags.left, InputFlags.right)) ~= 0
            or self.inputs.movement.x ~= 0 or self.inputs.movement.y ~= 0 then
            self.styleData.opacity = self.styleData.values.opacity + (self.definition.visibilityRateMoving or 0)
        end
        self.styleData.opacity = self.styleData.values.opacity - (self.definition.invisibilityRate or 0)
        self.styleData.opacity = util.constrain(self.styleData.values.opacity, 0, 1)
    end
    if bit.band(self.styleData.values.flags, StyleFlags.isFlashing) ~= 0
        and (self.game.tick >= self.cameraEntity.cameraData.values.spawnTick + 374
            or self.inputs:attemptingShot() or self.inputs.movement.magnitude > 0) then
        self.styleData.flags = bit.bxor(self.styleData.values.flags, StyleFlags.isFlashing)
        self.damageReduction = 1.0
    end
    if self.definition.sides == 2 then
        self.physicsData.width = self.physicsData.size * (self.definition.widthRatio or 1)
        if self.definition.flags and self.definition.flags.displayAsTrapezoid then
            self.physicsData.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.isTrapezoid)
        end
    elseif self.definition.flags and self.definition.flags.displayAsStar then
        self.styleData.flags = bit.bor(self.styleData.values.flags, StyleFlags.isStar)
    end
    self.velocity:add({
        x = self.inputs.movement.x * self.cameraEntity.cameraData.values.movementSpeed,
        y = self.inputs.movement.y * self.cameraEntity.cameraData.values.movementSpeed
    })
    self.inputs.movement:set({ x = 0, y = 0 })
end

return TankBody
