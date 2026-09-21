--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")
local TeamEntity = require("../Entity/Misc/TeamEntity")
local Mothership = require("../Entity/Misc/Mothership")
local Entity = require("../Native/Entity")
local Enums = require("../Const/Enums")
local util = require("../util")

local Color = Enums.Color
local ArenaFlags = Enums.ArenaFlags
local ArenaState = ArenaEntity.ArenaState

local arenaSize = 11150
local TEAM_COLORS = { Color.TeamBlue, Color.TeamRed }

local MothershipArena = class(ArenaEntity)
MothershipArena.GAMEMODE_ID = "mot"

function MothershipArena:init(game)
    ArenaEntity.init(self, game)
    self:updateBounds(arenaSize * 2, arenaSize * 2)
    self.shapeScoreRewardMultiplier = 3.0
    self.arenaData.values.flags = bit.bor(self.arenaData.values.flags, ArenaFlags.hiddenScores)
    self.playerTeamMap = {}
    self.teams = {}
    self.motherships = {}

    local randAngle = math.random() * util.PI2
    for i = 1, #TEAM_COLORS do
        local team = TeamEntity:new(self.game, TEAM_COLORS[i])
        self.teams[#self.teams + 1] = team
        local mot = Mothership:new(self.game)
        self.motherships[#self.motherships + 1] = mot
        mot.relationsData.values.team = team
        mot.styleData.values.color = team.teamData.values.teamColor
        mot.positionData.values.x = math.cos(randAngle) * arenaSize * 0.8
        mot.positionData.values.y = math.sin(randAngle) * arenaSize * 0.8
        randAngle = randAngle + util.PI2 / #TEAM_COLORS
    end
end

function MothershipArena:decideTeam(client)
    local team = self.playerTeamMap[client]
    if not team then
        team = util.randomFrom(self.teams)
        self.playerTeamMap[client] = team
    end
    return team
end

function MothershipArena:spawnPlayer(tank, client)
    local team = self:decideTeam(client)
    TeamEntity.setTeam(team, tank)
    local ok, used = pcall(self.attemptFactorySpawn, self, tank)
    if ok and used then return end

    local mot
    for i = 1, #self.motherships do
        if Entity.exists(self.motherships[i]) and self.motherships[i].relationsData.values.team == team then
            mot = self.motherships[i]
            break
        end
    end
    if mot then
        local angle = math.random() * util.PI2
        local dist = 400 + math.random() * 400
        tank.positionData.values.x = mot.positionData.values.x + math.cos(angle) * dist
        tank.positionData.values.y = mot.positionData.values.y + math.sin(angle) * dist
        return
    end

    local pos = self:findPlayerSpawnLocation()
    tank.positionData.values.x = pos.x
    tank.positionData.values.y = pos.y
end

function MothershipArena:updateScoreboard()
    table.sort(self.motherships, function(a, b)
        return a.healthData.values.health > b.healthData.values.health
    end)
    local length = math.min(10, #self.motherships)
    for i = 0, length - 1 do
        local mot = self.motherships[i + 1]
        local team = mot.relationsData.values.team
        local isTeamATeam = TeamEntity.isTeam(team)
        if mot.styleData.values.color == Color.Tank then
            self.arenaData.values.scoreboardColors:set(i, Color.ScoreboardBar)
        else
            self.arenaData.values.scoreboardColors:set(i, mot.styleData.values.color)
        end
        self.arenaData.values.scoreboardNames:set(i, isTeamATeam and team.teamName or ("Mothership " .. (i + 1)))
        self.arenaData.values.scoreboardTanks:set(i, -1)
        self.arenaData.values.scoreboardScores:set(i, mot.healthData.values.health)
        self.arenaData.values.scoreboardSuffixes:set(i, " HP")
    end
    self.arenaData.scoreboardAmount = length
end

function MothershipArena:updateArenaState()
    for i = #self.motherships, 1, -1 do
        if not Entity.exists(self.motherships[i]) then
            table.remove(self.motherships, i)
        end
    end

    if #self.motherships <= 1 then
        if self.state == ArenaState.OPEN then
            self.state = ArenaState.OVER
            local timer = require("timer")
            local arena = self
            timer.setTimeout(5000, function()
                arena:close()
            end)
        end
    end

    local players = self:getAlivePlayers()
    if #players == 0 and self.state == ArenaState.CLOSING then
        self.state = ArenaState.CLOSED
        local timer = require("timer")
        local game = self.game
        timer.setTimeout(10000, function()
            game:endGame()
        end)
        return
    end
    self:updateScoreboard()
end

return MothershipArena
