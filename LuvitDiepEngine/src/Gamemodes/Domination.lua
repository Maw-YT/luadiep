--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")
local TeamBase = require("../Entity/Misc/TeamBase")
local TeamEntity = require("../Entity/Misc/TeamEntity")
local Dominator = require("../Entity/Misc/Dominator")
local Entity = require("../Native/Entity")
local Enums = require("../Const/Enums")
local util = require("../util")

local Color = Enums.Color
local ColorsHexCode = Enums.ColorsHexCode
local ArenaFlags = Enums.ArenaFlags
local ClientBound = Enums.ClientBound
local ArenaState = ArenaEntity.ArenaState

local arenaSize = 11150
local baseSize = arenaSize / (3 + 1 / 3)
local domBaseSize = baseSize / 2
local TEAM_COLORS = { Color.TeamBlue, Color.TeamRed }

local DominationArena = class(ArenaEntity)
DominationArena.GAMEMODE_ID = "dom"

function DominationArena:init(game)
    ArenaEntity.init(self, game)
    self.shapeScoreRewardMultiplier = 2.0
    self:updateBounds(arenaSize * 2, arenaSize * 2)
    self.arenaData.values.flags = bit.bor(self.arenaData.values.flags, ArenaFlags.hiddenScores)
    self.playerTeamMap = {}
    self.dominators = {}
    self.teams = {}

    local flipLeft = math.random() > 0.5 and 1 or -1
    local flipRight = math.random() > 0.5 and -1 or 1
    for i = 1, #TEAM_COLORS do
        local teamColor = TEAM_COLORS[i]
        local team = TeamEntity:new(self.game, teamColor)
        local side = (i % 2 ~= 0) and -1 or 1
        local x = side * arenaSize - side * baseSize / 2
        local y = side * (side == 1 and flipLeft or flipRight) * (arenaSize - baseSize / 2)
        flipLeft = flipLeft * side
        flipRight = flipRight * -side
        TeamBase:new(game, team, x, y, baseSize, baseSize)
        self.teams[#self.teams + 1] = team
    end

    local se = Dominator:new(self, TeamBase:new(game, self, arenaSize / 2.5, arenaSize / 2.5, domBaseSize, domBaseSize, false))
    se.prefix = "SE "
    local sw = Dominator:new(self, TeamBase:new(game, self, arenaSize / -2.5, arenaSize / 2.5, domBaseSize, domBaseSize, false))
    sw.prefix = "SW "
    local nw = Dominator:new(self, TeamBase:new(game, self, arenaSize / -2.5, arenaSize / -2.5, domBaseSize, domBaseSize, false))
    nw.prefix = "NW "
    local ne = Dominator:new(self, TeamBase:new(game, self, arenaSize / 2.5, arenaSize / -2.5, domBaseSize, domBaseSize, false))
    ne.prefix = "NE "
    self.dominators = { se, sw, nw, ne }
end

function DominationArena:decideTeam(client)
    local team = self.playerTeamMap[client]
    if not team then
        team = util.randomFrom(self.teams)
        self.playerTeamMap[client] = team
    end
    return team
end

function DominationArena:spawnPlayer(tank, client)
    local team = self:decideTeam(client)
    TeamEntity.setTeam(team, tank)
    local ok, used = pcall(self.attemptFactorySpawn, self, tank)
    if ok and used then return end
    local teamBase = team.base
    if not teamBase then
        return ArenaEntity.spawnPlayer(self, tank, client)
    end
    local pos = util.getRandomPosition(teamBase)
    tank.positionData.values.x = pos.x
    tank.positionData.values.y = pos.y
end

function DominationArena:getTeamDominatorCount(team)
    local n = 0
    for i = 1, #self.dominators do
        if self.dominators[i].relationsData.values.team == team then
            n = n + 1
        end
    end
    return n
end

function DominationArena:updateArenaState()
    local dominatorCount = #self.dominators
    for i = 1, #self.teams do
        local team = self.teams[i]
        if self:getTeamDominatorCount(team) == dominatorCount then
            if self.state == ArenaState.OPEN then
                self.game:broadcast()
                    :u8(ClientBound.Notification)
                    :stringNT((team.teamName or "A TEAM") .. " HAS WON THE GAME!")
                    :u32(ColorsHexCode[team.teamData.values.teamColor] or 0)
                    :float(-1)
                    :stringNT("")
                    :send()
                self.state = ArenaState.OVER
                local timer = require("timer")
                local arena = self
                timer.setTimeout(5000, function()
                    arena:close()
                end)
            end
        end
    end

    for i = #self.dominators, 1, -1 do
        if not Entity.exists(self.dominators[i]) then
            table.remove(self.dominators, i)
        end
    end

    if self.state == ArenaState.CLOSING and #self:getAlivePlayers() == 0 then
        self.state = ArenaState.CLOSED
        local timer = require("timer")
        local game = self.game
        timer.setTimeout(10000, function()
            game:endGame()
        end)
    end
end

return DominationArena
