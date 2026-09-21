--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")
local TeamBase = require("../Entity/Misc/TeamBase")
local TeamEntity = require("../Entity/Misc/TeamEntity")
local Enums = require("../Const/Enums")
local util = require("../util")

local Color = Enums.Color

local arenaSize = 11150
local baseSize = arenaSize / (3 + 1 / 3)

local FourTeamsArena = class(ArenaEntity)
FourTeamsArena.GAMEMODE_ID = "4teams"

function FourTeamsArena:init(game)
    ArenaEntity.init(self, game)
    self:updateBounds(arenaSize * 2, arenaSize * 2)
    self.playerTeamMap = {}
    self.blueTeamEntity = TeamEntity:new(self.game, Color.TeamBlue)
    self.redTeamEntity = TeamEntity:new(self.game, Color.TeamRed)
    self.purpleTeamEntity = TeamEntity:new(self.game, Color.TeamPurple)
    self.greenTeamEntity = TeamEntity:new(self.game, Color.TeamGreen)
    TeamBase:new(game, self.blueTeamEntity, -arenaSize + baseSize / 2, -arenaSize + baseSize / 2, baseSize, baseSize)
    TeamBase:new(game, self.redTeamEntity, arenaSize - baseSize / 2, arenaSize - baseSize / 2, baseSize, baseSize)
    TeamBase:new(game, self.purpleTeamEntity, arenaSize - baseSize / 2, -arenaSize + baseSize / 2, baseSize, baseSize)
    TeamBase:new(game, self.greenTeamEntity, -arenaSize + baseSize / 2, arenaSize - baseSize / 2, baseSize, baseSize)
end

function FourTeamsArena:decideTeam(client)
    local team = self.playerTeamMap[client]
    if not team then
        team = util.randomFrom({
            self.blueTeamEntity,
            self.redTeamEntity,
            self.purpleTeamEntity,
            self.greenTeamEntity
        })
        self.playerTeamMap[client] = team
    end
    return team
end

function FourTeamsArena:spawnPlayer(tank, client)
    local team = self:decideTeam(client)
    TeamEntity.setTeam(team, tank)
    local ok, used = pcall(self.attemptFactorySpawn, self, tank)
    if ok and used then return end
    local base = team.base
    if not base then
        return ArenaEntity.spawnPlayer(self, tank, client)
    end
    local pos = util.getRandomPosition(base)
    tank.positionData.values.x = pos.x
    tank.positionData.values.y = pos.y
end

return FourTeamsArena
