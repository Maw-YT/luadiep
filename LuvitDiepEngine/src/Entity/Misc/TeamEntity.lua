--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local Entity = require("../../Native/Entity")
local FieldGroups = require("../../Native/FieldGroups")
local Enums = require("../../Const/Enums")
local ObjectEntity = require("../Object")

local Color = Enums.Color

local ColorsTeamName = {
    [Color.Border] = "BORDER",
    [Color.Barrel] = "BARREL",
    [Color.Tank] = "TANK",
    [Color.TeamBlue] = "BLUE",
    [Color.TeamRed] = "RED",
    [Color.TeamPurple] = "PURPLE",
    [Color.TeamGreen] = "GREEN",
    [Color.Shiny] = "SHINY",
    [Color.EnemySquare] = "SQUARE",
    [Color.EnemyTriangle] = "TRIANGLE",
    [Color.EnemyPentagon] = "PENTAGON",
    [Color.EnemyCrasher] = "CRASHER",
    [Color.Neutral] = "NEUTRAL",
    [Color.ScoreboardBar] = "SCOREBOARD",
    [Color.Box] = "MAZE",
    [Color.EnemyTank] = "ENEMY",
    [Color.NecromancerSquare] = "SUNCHIP",
    [Color.Fallen] = "FALLEN"
}

local TeamEntity = class(Entity)

function TeamEntity.isTeam(entity)
    return entity ~= nil and entity.teamData ~= nil
end

function TeamEntity.setTeam(team, entity)
    if not Entity.exists(entity) then return end
    entity.relationsData.values.team = team
    entity.styleData.color = team.teamData.values.teamColor
    local TankBody = require("../Tank/TankBody")
    if TankBody.isTank(entity) then
        entity.cameraEntity.relationsData.values.team = team
    end
end

function TeamEntity:init(game, color, name)
    Entity.init(self, game)
    self.teamData = FieldGroups.TeamGroup:new(self)
    self.teamData.values.teamColor = color
    self.teamName = name or ColorsTeamName[color] or "UNKNOWN"
    self.base = nil
end

TeamEntity.ColorsTeamName = ColorsTeamName

return TeamEntity
