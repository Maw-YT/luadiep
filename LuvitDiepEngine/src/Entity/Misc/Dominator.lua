--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local TankBody = require("../Tank/TankBody")
local Camera = require("../../Native/Camera")
local AIMod = require("../AI")
local TeamEntity = require("./TeamEntity")
local Enums = require("../../Const/Enums")
local util = require("../../util")

local Color = Enums.Color
local ColorsHexCode = Enums.ColorsHexCode
local NameFlags = Enums.NameFlags
local StyleFlags = Enums.StyleFlags
local EntityTags = Enums.EntityTags
local Tank = Enums.Tank
local ClientBound = Enums.ClientBound
local CameraEntity = Camera.CameraEntity
local AI = AIMod.AI
local AIState = AIMod.AIState
local Inputs = AIMod.Inputs

local Dominator = class(TankBody)
Dominator.SIZE = 160
Dominator.DOMINATOR_CLASSES = { Tank.DominatorD, Tank.DominatorG, Tank.DominatorT }

function Dominator.isDominator(entity)
    if not entity then return false end
    return bit.band(entity.entityTags or 0, EntityTags.isDominator) ~= 0
end

function Dominator:init(arena, base, tankId)
    tankId = tankId or util.randomFrom(Dominator.DOMINATOR_CLASSES)
    local inputs = Inputs:new()
    local camera = CameraEntity:new(arena.game)

    TankBody.init(self, arena.game, camera, inputs)
    camera.cameraData.player = self
    camera:setLevel(75)

    self.scaleFactor = 1
    self:scale(Dominator.SIZE / self.baseSize)
    self:setTank(tankId)

    self.relationsData.values.team = arena
    self.physicsData.values.size = Dominator.SIZE
    self.styleData.values.color = Color.Neutral

    self.ai = AI:new(self, true)
    self.ai.inputs = inputs
    self.ai.movementSpeed = 0
    self.ai.viewRange = 2000
    self.ai.doAimPrediction = true

    local def = {}
    for k, v in pairs(self.definition) do
        def[k] = v
    end
    def.speed = 0
    self.definition = def
    camera.cameraData.movementSpeed = 0

    self.nameData.values.name = "Dominator"
    self.nameData.values.flags = bit.bor(self.nameData.values.flags, NameFlags.hiddenName)
    self.physicsData.values.absorbtionFactor = 0
    self.positionData.values.x = base.positionData.values.x
    self.positionData.values.y = base.positionData.values.y
    self.scoreReward = 0
    camera.cameraData.player = self
    self.base = base
    self.prefix = ""
    self.damagePerTick = 10

    if bit.band(self.styleData.values.flags, StyleFlags.isFlashing) ~= 0 then
        self.styleData.flags = bit.bxor(self.styleData.values.flags, StyleFlags.isFlashing)
        self.damageReduction = 1.0
    end

    self.entityTags = bit.bor(self.entityTags, EntityTags.isDominator)
end

function Dominator:onDeath(killer)
    local killerTeam = killer.relationsData and killer.relationsData.values.team
    if TeamEntity.isTeam(killerTeam) and self.relationsData.values.team == self.game.arena then
        self.relationsData.team = killerTeam
        self.styleData.color = killerTeam.teamData.values.teamColor
        self.game:broadcast()
            :u8(ClientBound.Notification)
            :stringNT("The " .. (self.prefix or "") .. self.nameData.values.name .. " is now controlled by " .. (killerTeam.teamName or "a mysterious group"))
            :u32(ColorsHexCode[killerTeam.teamData.values.teamColor] or 0)
            :float(7500)
            :stringNT("")
            :send()
        for client in pairs(self.game.clients) do
            if client ~= "size" then
                local camera = client.camera
                if camera and camera.relationsData.values.team == self.relationsData.values.team then
                    client:notify(
                        "Press H to take control of the " .. self.nameData.values.name,
                        ColorsHexCode[killerTeam.teamData.values.teamColor] or 0
                    )
                end
            end
        end
    else
        self.relationsData.team = self.game.arena
        self.styleData.color = self.game.arena.teamData.values.teamColor
        self.game:broadcast()
            :u8(ClientBound.Notification)
            :stringNT("The " .. (self.prefix or "") .. self.nameData.values.name .. " is being contested")
            :u32(ColorsHexCode[Color.Neutral] or 0)
            :float(7500)
            :stringNT("")
            :send()
    end

    self.base.styleData.color = self.styleData.values.color
    self.base.relationsData.team = self.relationsData.values.team
    self.healthData.health = self.healthData.values.maxHealth

    for id = 0, self.game.entities.lastId do
        local entity = self.game.entities.inner[id]
        if entity and entity.barrelEntity and entity.relationsData and entity.relationsData.values.owner == self then
            entity:destroy()
        end
    end

    if self.ai.state == AIState.possessed then
        self.ai.inputs.deleted = true
        self.ai.inputs = Inputs:new()
        self.inputs = self.ai.inputs
        self.ai.state = AIState.idle
    end
end

function Dominator:tick(tick)
    if #self.barrels == 0 then
        return TankBody.tick(self, tick)
    end
    self.ai.aimSpeed = self.barrels[1].bulletAccel
    self.inputs = self.ai.inputs
    self.cameraEntity.cameraData.movementSpeed = 0

    if self.ai.state == AIState.idle then
        local angle = self.positionData.values.angle + self.ai.passiveRotation
        local dx = self.inputs.mouse.x - self.positionData.values.x
        local dy = self.inputs.mouse.y - self.positionData.values.y
        local mag = math.sqrt(dx * dx + dy * dy)
        self.inputs.mouse:set({
            x = self.positionData.values.x + math.cos(angle) * mag,
            y = self.positionData.values.y + math.sin(angle) * mag
        })
    end

    TankBody.tick(self, tick)
end

return Dominator
