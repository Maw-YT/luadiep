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
local config = require("../../config")
local ArenaEntity = require("../../Native/Arena")

local Color = Enums.Color
local ColorsHexCode = Enums.ColorsHexCode
local Tank = Enums.Tank
local Stat = Enums.Stat
local ClientBound = Enums.ClientBound
local TeamFlags = Enums.TeamFlags
local CameraEntity = Camera.CameraEntity
local AI = AIMod.AI
local AIState = AIMod.AIState
local Inputs = AIMod.Inputs
local ArenaState = ArenaEntity.ArenaState

local POSSESSION_TIMER = config.tps * 60 * 5

local Mothership = class(TankBody)

function Mothership:init(game)
    local inputs = Inputs:new()
    local camera = CameraEntity:new(game)

    TankBody.init(self, game, camera, inputs)

    self.relationsData.values.team = game.arena
    self.styleData.values.color = Color.Neutral

    self.ai = AI:new(self, true)
    self.ai.inputs = inputs
    self.ai.viewRange = 2000

    camera.cameraData.player = self
    self:setTank(Tank.Mothership)
    camera:setLevel(140)
    self.nameData.values.name = "Mothership"
    self.scoreReward = 0
    camera.cameraData.player = self
    self.possessionStartTick = -1

    for i = Stat.MovementSpeed, Stat.HealthRegen - 1 do
        camera:setStat(i, 7)
    end
    camera:setStat(Stat.HealthRegen, 1)

    self.healthData.maxHealth = 7000
    self.healthData.health = 7000
end

function Mothership:onDeath(killer)
    if self.game.arena.state >= ArenaState.OVER then return end

    local team = self.relationsData.values.team
    local teamIsATeam = TeamEntity.isTeam(team)
    local killerTeam = killer.relationsData and killer.relationsData.values.team
    local killerTeamIsATeam = TeamEntity.isTeam(killerTeam)

    local killerName
    if killerTeamIsATeam then
        killerName = killerTeam.teamName or "a mysterious group"
    else
        killerName = (killer.nameData and killer.nameData.values.name ~= "" and killer.nameData.values.name) or "an unnamed tank"
    end
    local victimName
    if teamIsATeam then
        victimName = (team.teamName or "a mysterious group") .. "'s"
    else
        victimName = "a"
    end

    self.game:broadcast()
        :u8(ClientBound.Notification)
        :stringNT(killerName .. " has destroyed " .. victimName .. " Mothership!")
        :u32(killerTeamIsATeam and (ColorsHexCode[killerTeam.teamData.values.teamColor] or 0) or 0)
        :float(-1)
        :stringNT("")
        :send()
end

function Mothership:delete()
    local team = self.relationsData.values.team
    if team and team.teamData then
        team.teamData.flags = bit.band(team.teamData.values.flags, bit.bnot(TeamFlags.hasMothership))
    end
    TankBody.delete(self)
end

function Mothership:tick(tick)
    if #self.barrels == 0 then
        return TankBody.tick(self, tick)
    end

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
    elseif self.ai.state == AIState.possessed and self.possessionStartTick == -1 then
        self.possessionStartTick = tick
    end

    if self.possessionStartTick ~= -1 and self.ai.state ~= AIState.possessed then
        self.possessionStartTick = -1
    end

    if self.possessionStartTick ~= -1 and self.inputs.client then
        if tick - self.possessionStartTick >= POSSESSION_TIMER then
            self.inputs.deleted = true
        elseif tick - self.possessionStartTick == math.floor(POSSESSION_TIMER - 10 * config.tps) then
            self.inputs.client:notify(
                "You only have 10 seconds left in control of the Mothership",
                ColorsHexCode[self.styleData.values.color] or 0,
                5000
            )
        end
    end

    local team = self.relationsData.values.team
    if team and team.teamData then
        team.teamData.mothershipX = self.positionData.values.x
        team.teamData.mothershipY = self.positionData.values.y
        team.teamData.flags = bit.bor(team.teamData.values.flags, TeamFlags.hasMothership)
    end

    TankBody.tick(self, tick)
end

return Mothership
