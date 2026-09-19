--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local ObjectEntity = require("../Object")
local Enums = require("../../Const/Enums")
local AIMod = require("../AI")
local util = require("../../util")
local LivingEntity = require("../Live")

local Color = Enums.Color
local PositionFlags = Enums.PositionFlags
local PhysicsFlags = Enums.PhysicsFlags
local StyleFlags = Enums.StyleFlags
local AI = AIMod.AI
local AIState = AIMod.AIState
local Inputs = AIMod.Inputs

local AutoTurretMiniDefinition = {
    angle = 0, offset = 0, size = 55, width = 42 * 0.7, delay = 0.01, reload = 1, recoil = 0.3,
    isTrapezoid = false, trapezoidDirection = 0, addon = nil,
    bullet = { type = "bullet", health = 1, damage = 0.4, speed = 1.2, scatterRate = 1, lifeLength = 1, sizeRatio = 1, absorbtionFactor = 1 }
}

local Addon = class()
function Addon:init(owner)
    self.owner = owner
    self.game = owner.game
end

local GuardObject = class(ObjectEntity)
function GuardObject:init(game, owner, sides, scaleFactor, offsetAngle, radiansPerTick)
    ObjectEntity.init(self, game)
    self.owner = owner
    self.inputs = owner.inputs
    self.cameraEntity = owner.cameraEntity
    scaleFactor = scaleFactor * util.SQRT1_2
    self.scaleFactor = scaleFactor
    self.radiansPerTick = radiansPerTick
    self:setParent(owner)
    self.relationsData.values.owner = owner
    self.relationsData.values.team = owner.relationsData.values.team
    self.styleData.values.color = Color.Border
    self.positionData.values.flags = bit.bor(self.positionData.values.flags, PositionFlags.absoluteRotation)
    self.positionData.values.angle = offsetAngle
    self.physicsData.values.sides = sides
    self.reloadTime = owner.reloadTime
    self.physicsData.values.size = owner.physicsData.values.size * scaleFactor
end
function GuardObject:onKill(killedEntity, weapon)
    if LivingEntity.isLive(self.owner) then
        self.owner:onKill(killedEntity, weapon)
    end
end
function GuardObject:tick(tick)
    self.reloadTime = self.owner.reloadTime
    self.positionData.angle = self.positionData.values.angle + self.radiansPerTick
end

function Addon:createGuard(sides, sizeRatio, offsetAngle, radiansPerTick)
    return GuardObject:new(self.game, self.owner, sides, sizeRatio, offsetAngle, radiansPerTick)
end

function Addon:createAutoTurrets(count)
    local AutoTurret = require("./AutoTurret")
    local rotPerTick = AI.PASSIVE_ROTATION
    local MAX_ANGLE_RANGE = util.PI2 / 4
    local rotator = self:createGuard(1, 0.1, 0, rotPerTick)
    rotator.turrets = {}
    local ROT_OFFSET = 0.8
    if bit.band(rotator.styleData.values.flags, StyleFlags.isVisible) ~= 0 then
        rotator.styleData.values.flags = bit.bxor(rotator.styleData.values.flags, StyleFlags.isVisible)
    end
    for i = 0, count - 1 do
        local base = AutoTurret:new(rotator, AutoTurretMiniDefinition)
        base.influencedByOwnerInputs = true
        local angle = util.PI2 * (i / count)
        base.ai.inputs.mouse.angle = angle
        base.ai.passiveRotation = rotPerTick
        base.ai.targetFilter = function(targetPos)
            local pos = base:getWorldPosition()
            local angleToTarget = math.atan2(targetPos.y - pos.y, targetPos.x - pos.x)
            local deltaAngle = util.normalizeAngle(angleToTarget - (angle + rotator.positionData.values.angle))
            return deltaAngle < MAX_ANGLE_RANGE or deltaAngle > (util.PI2 - MAX_ANGLE_RANGE)
        end
        base.positionData.values.y = self.owner.physicsData.values.size * math.sin(angle) * ROT_OFFSET
        base.positionData.values.x = self.owner.physicsData.values.size * math.cos(angle) * ROT_OFFSET
        if bit.band(base.styleData.values.flags, StyleFlags.showsAboveParent) ~= 0 then
            base.styleData.values.flags = bit.bxor(base.styleData.values.flags, StyleFlags.showsAboveParent)
        end
        base.physicsData.values.flags = bit.bor(base.physicsData.values.flags, PositionFlags.absoluteRotation)
        local tickBase = base.tick
        base.tick = function(selfBase, tick)
            if selfBase.ai.state == AIState.idle then
                selfBase.positionData.angle = angle + rotator.positionData.values.angle
            end
            tickBase(selfBase, tick)
        end
        rotator.turrets[#rotator.turrets + 1] = base
    end
    return rotator
end

local function makeAddon(fn)
    local A = class(Addon)
    function A:init(owner)
        Addon.init(self, owner)
        fn(self, owner)
    end
    return A
end

local SpikeAddon = makeAddon(function(self)
    self:createGuard(3, 1.3, 0, 0.17)
    self:createGuard(3, 1.3, math.pi / 3, 0.17)
    self:createGuard(3, 1.3, math.pi / 6, 0.17)
    self:createGuard(3, 1.3, math.pi / 2, 0.17)
end)

local DomBaseAddon = makeAddon(function(self)
    self:createGuard(6, 1.24, 0, 0)
end)

local SmasherAddon = makeAddon(function(self)
    self:createGuard(6, 1.15, 0, 0.1)
end)

local LandmineAddon = makeAddon(function(self)
    self:createGuard(6, 1.15, 0, 0.1)
    self:createGuard(6, 1.15, 0, 0.05)
end)

local LauncherAddon = makeAddon(function(self)
    local launcher = ObjectEntity:new(self.game)
    local sizeRatio = 65.5 * util.SQRT2 / 50
    local widthRatio = 33.6 / 50
    local size = self.owner.physicsData.values.size
    launcher:setParent(self.owner)
    launcher.relationsData.values.owner = self.owner
    launcher.relationsData.values.team = self.owner.relationsData.values.team
    launcher.physicsData.values.size = sizeRatio * size
    launcher.physicsData.values.width = widthRatio * size
    launcher.positionData.values.x = launcher.physicsData.values.size / 2
    launcher.styleData.values.color = Color.Barrel
    launcher.physicsData.values.flags = bit.bor(launcher.physicsData.values.flags, PhysicsFlags.isTrapezoid)
    launcher.physicsData.values.sides = 2
end)

local AutoTurretAddon = makeAddon(function(self)
    require("./AutoTurret"):new(self.owner)
end)

local AutoSmasherAddon = makeAddon(function(self)
    self:createGuard(6, 1.15, 0, 0.1)
    require("./AutoTurret"):new(self.owner)
end)

local Auto5Addon = makeAddon(function(self) self:createAutoTurrets(5) end)
local Auto3Addon = makeAddon(function(self) self:createAutoTurrets(3) end)
local Auto2Addon = makeAddon(function(self) self:createAutoTurrets(2) end)
local Auto7Addon = makeAddon(function(self) self:createAutoTurrets(7) end)

local PronouncedAddon = makeAddon(function(self)
    local pronounce = ObjectEntity:new(self.game)
    local size = self.owner.physicsData.values.size
    pronounce:setParent(self.owner)
    pronounce.relationsData.values.owner = self.owner
    pronounce.relationsData.values.team = self.owner.relationsData.values.team
    pronounce.physicsData.values.size = size
    pronounce.physicsData.values.width = 42 / 50 * size
    pronounce.positionData.values.x = 40 / 50 * size
    pronounce.positionData.values.angle = math.pi
    pronounce.styleData.values.color = Color.Barrel
    pronounce.physicsData.values.flags = bit.bor(pronounce.physicsData.values.flags, PhysicsFlags.isTrapezoid)
    pronounce.physicsData.values.sides = 2
end)

local PronouncedDomAddon = makeAddon(function(self)
    local pronounce = ObjectEntity:new(self.game)
    local size = self.owner.physicsData.values.size
    pronounce:setParent(self.owner)
    pronounce.relationsData.values.owner = self.owner
    pronounce.relationsData.values.team = self.owner.relationsData.values.team
    pronounce.physicsData.values.size = 22 / 50 * size
    pronounce.physicsData.values.width = 35 / 50 * size
    pronounce.positionData.values.x = size
    pronounce.positionData.values.angle = math.pi
    pronounce.styleData.values.color = Color.Barrel
    pronounce.physicsData.values.flags = bit.bor(pronounce.physicsData.values.flags, PhysicsFlags.isTrapezoid)
    pronounce.physicsData.values.sides = 2
end)

local WeirdSpikeAddon = makeAddon(function(self)
    self:createGuard(3, 1.5, 0, 0.17)
    self:createGuard(3, 1.5, 0, -0.16)
end)

local SpieskAddon = makeAddon(function(self)
    self:createGuard(4, 1.3, 0, 0.17)
    self:createGuard(4, 1.3, math.pi / 6, 0.17)
    self:createGuard(4, 1.3, 2 * math.pi / 6, 0.17)
end)

local AutoRocketAddon = makeAddon(function(self)
    local AutoTurret = require("./AutoTurret")
    local base = AutoTurret:new(self.owner, {
        angle = 0, offset = 0, size = 40, width = 26.25, delay = 0, reload = 2, recoil = 0.75,
        isTrapezoid = true, trapezoidDirection = math.pi, addon = nil,
        bullet = { type = "rocket", sizeRatio = 1, health = 2.5, damage = 0.5, speed = 0.3, scatterRate = 1, lifeLength = 0.75, absorbtionFactor = 0.1 }
    })
    LauncherAddon:new(base)
    base.turret.styleData.zIndex = base.turret.styleData.values.zIndex + 2
end)

local AddonById = {
    spike = SpikeAddon,
    dombase = DomBaseAddon,
    launcher = LauncherAddon,
    dompronounced = PronouncedDomAddon,
    auto5 = Auto5Addon,
    auto3 = Auto3Addon,
    autosmasher = AutoSmasherAddon,
    pronounced = PronouncedAddon,
    smasher = SmasherAddon,
    landmine = LandmineAddon,
    autoturret = AutoTurretAddon,
    weirdspike = WeirdSpikeAddon,
    auto7 = Auto7Addon,
    auto2 = Auto2Addon,
    autorocket = AutoRocketAddon,
    spiesk = SpieskAddon
}

return {
    Addon = Addon,
    GuardObject = GuardObject,
    AddonById = AddonById
}
