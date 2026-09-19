--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local TankBody = require("../Tank/TankBody")
local Camera = require("../../Native/Camera")
local AIMod = require("../AI")
local Enums = require("../../Const/Enums")

local Color = Enums.Color
local PhysicsFlags = Enums.PhysicsFlags
local PositionFlags = Enums.PositionFlags
local Stat = Enums.Stat
local Tank = Enums.Tank
local CameraEntity = Camera.CameraEntity
local AI = AIMod.AI
local AIState = AIMod.AIState
local Inputs = AIMod.Inputs

local ArenaCloser = class(TankBody)
ArenaCloser.BASE_SIZE = 175

function ArenaCloser.isCloser(entity)
    return entity ~= nil and entity._isArenaCloser == true
end

function ArenaCloser:init(game)
    local inputs = Inputs:new()
    local camera = CameraEntity:new(game)

    TankBody.init(self, game, camera, inputs)
    self._isArenaCloser = true

    camera.cameraData.player = self
    camera:setLevel(300)

    self.scaleFactor = 1
    self:scale(ArenaCloser.BASE_SIZE / self.baseSize)

    self.relationsData.values.team = game.arena

    self.ai = AI:new(self)
    self.ai.inputs = inputs
    self.ai.viewRange = math.huge

    self:setTank(Tank.ArenaCloser)

    self.nameData.values.name = "Arena Closer"
    self.styleData.values.color = Color.Neutral
    self.positionData.flags = bit.bor(self.positionData.values.flags, PositionFlags.canMoveThroughWalls)
    self.physicsData.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.canEscapeArena)

    for i = Stat.MovementSpeed, Stat.BodyDamage - 1 do
        camera:setStat(i, 7)
    end

    self.ai.aimSpeed = self.barrels[1].bulletAccel * 1.6
    self:setInvulnerability(true)

    self.ai.movementSpeed = 5
    self.cameraEntity.cameraData.movementSpeed = 5
    self.healthData.maxHealth = 10000
    self.healthData.health = 10000
    self.damagePerTick = 45
end

function ArenaCloser:tick(tick)
    self.inputs = self.ai.inputs

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

return ArenaCloser
