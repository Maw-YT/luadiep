--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Entity = require("./Entity")
local FieldGroups = require("./FieldGroups")
local Enums = require("../Const/Enums")
local config = require("../config")
local util = require("../util")

local Color = Enums.Color
local ArenaFlags = Enums.ArenaFlags
local CameraFlags = Enums.CameraFlags
local Tank = Enums.Tank

local ArenaState = {
    COUNTDOWN = -1,
    OPEN = 0,
    OVER = 1,
    CLOSING = 2,
    CLOSED = 3
}

local ArenaEntity = class(Entity)
ArenaEntity.GAMEMODE_ID = nil

function ArenaEntity:init(game)
    Entity.init(self, game)
    self.arenaData = FieldGroups.ArenaGroup:new(self)
    self.teamData = FieldGroups.TeamGroup:new(self)
    self.width = 22300
    self.height = 22300
    self.state = ArenaState.COUNTDOWN
    self.shapeScoreRewardMultiplier = 1
    self.leader = nil
    self.ARENA_PADDING = 200
    self:updateBounds(self.width, self.height)
    self.arenaData.values.flags = ArenaFlags.gameReadyStart
    self.arenaData.values.playersNeeded = 0
    self.arenaData.values.ticksUntilStart = config.countdownDuration
    self.teamData.values.teamColor = Color.Neutral
    local ShapeManager = require("../Misc/ShapeManager")
    self.shapes = ShapeManager:new(self)
    local BossManager = require("../Misc/BossManager")
    self.bossManager = BossManager:new(self)
end

function ArenaEntity:isOpen() return self.state == ArenaState.OPEN end
function ArenaEntity:isCountingDown() return self.state == ArenaState.COUNTDOWN end
function ArenaEntity:isGameOver() return self.state == ArenaState.OVER end
function ArenaEntity:isClosing() return self.state == ArenaState.CLOSING end
function ArenaEntity:isClosed() return self.state == ArenaState.CLOSED end

function ArenaEntity:isValidSpawnLocation(x, y)
    return true
end

function ArenaEntity:findSpawnLocation(width, height)
    local TankBody = require("../Entity/Tank/TankBody")
    width = width or self.width
    height = height or self.height
    local pos = {
        x = math.floor(math.random() * width - width / 2),
        y = math.floor(math.random() * height - height / 2)
    }
    for _ = 1, 20 do
        if not self:isValidSpawnLocation(pos.x, pos.y) then
            pos.x = math.floor(math.random() * width - width / 2)
            pos.y = math.floor(math.random() * height - height / 2)
        else
            local entity = self.game.entities.collisionManager:getFirstMatch(pos.x, pos.y, 1000, 1000, function(e)
                if not (TankBody.isTank(e) or (e.entityTags and bit.band(e.entityTags, Enums.EntityTags.isBoss) ~= 0)) then
                    return false
                end
                local dX = e.positionData.values.x - pos.x
                local dY = e.positionData.values.y - pos.y
                return (dX * dX + dY * dY) < 1000000
            end)
            if entity then
                pos.x = math.floor(math.random() * width - width / 2)
                pos.y = math.floor(math.random() * height - height / 2)
            else
                break
            end
        end
    end
    return pos
end

function ArenaEntity:findPlayerSpawnLocation()
    local pos = self:findSpawnLocation()
    for _ = 1, 20 do
        if math.max(pos.x, pos.y) < self.arenaData.values.rightX / 2
            and math.min(pos.x, pos.y) > self.arenaData.values.leftX / 2 then
            pos = self:findSpawnLocation()
        else
            break
        end
    end
    return pos
end

function ArenaEntity:updateScoreboard(scoreboardPlayers)
    local hidden = bit.band(self.arenaData.values.flags, ArenaFlags.hiddenScores) ~= 0
    local scoreboardCount = hidden and 0 or math.min(#scoreboardPlayers, 10)
    self.arenaData.scoreboardAmount = scoreboardCount
    if scoreboardCount == 0 then
        if bit.band(self.arenaData.values.flags, ArenaFlags.showsLeaderArrow) ~= 0 then
            self.arenaData.flags = bit.bxor(self.arenaData.values.flags, ArenaFlags.showsLeaderArrow)
        end
        return
    end
    table.sort(scoreboardPlayers, function(p1, p2)
        return p2.scoreData.values.score < p1.scoreData.values.score
    end)
    -- wait, we want descending score: p2 - p1 means higher first
    table.sort(scoreboardPlayers, function(p1, p2)
        return p1.scoreData.values.score > p2.scoreData.values.score
    end)
    self.leader = scoreboardPlayers[1]
    self.arenaData.flags = bit.bor(self.arenaData.values.flags, ArenaFlags.showsLeaderArrow)
    for i = 0, scoreboardCount - 1 do
        local player = scoreboardPlayers[i + 1]
        if player.styleData.values.color == Color.Tank then
            self.arenaData.values.scoreboardColors:set(i, Color.ScoreboardBar)
        else
            self.arenaData.values.scoreboardColors:set(i, player.styleData.values.color)
        end
        self.arenaData.values.scoreboardNames:set(i, player.nameData.values.name)
        self.arenaData.values.scoreboardScores:set(i, player.scoreData.values.score)
        self.arenaData.values.scoreboardTanks:set(i, player._currentTank)
    end
end

function ArenaEntity:getAlivePlayers()
    local TankBody = require("../Entity/Tank/TankBody")
    local players = {}
    for client in pairs(self.game.clients) do
        if client ~= "size" then
            local entity = client.camera and client.camera.cameraData.values.player
            if Entity.exists(entity) and TankBody.isTank(entity) then
                players[#players + 1] = entity
            end
        end
    end
    return players
end

function ArenaEntity:getTeamPlayers(team)
    local players = self:getAlivePlayers()
    local teamPlayers = {}
    for i = 1, #players do
        if players[i].relationsData.values.team == team then
            teamPlayers[#teamPlayers + 1] = players[i]
        end
    end
    return teamPlayers
end

function ArenaEntity:updateArenaState()
    if (self.game.tick % config.scoreboardUpdateInterval) ~= 0 then return end
    local players = self:getAlivePlayers()
    self:updateScoreboard(players)
    if #players == 0 and self.state == ArenaState.CLOSING then
        self.state = ArenaState.CLOSED
        local timer = require("timer")
        local game = self.game
        timer.setTimeout(10000, function()
            game:endGame()
        end)
    end
end

function ArenaEntity:manageCountdown()
    local isReady = bit.band(self.arenaData.values.flags, ArenaFlags.gameReadyStart) ~= 0
    if isReady then
        self.arenaData.ticksUntilStart = self.arenaData.values.ticksUntilStart - 1
    end
    if self.state == ArenaState.COUNTDOWN and isReady and self.arenaData.values.ticksUntilStart < 0 then
        self:onGameStarted()
    end
    local toRemove = {}
    for client, name in pairs(self.game.clientsAwaitingSpawn) do
        local camera = client.camera
        if Entity.exists(camera) then
            if self.state == ArenaState.COUNTDOWN then
                camera.cameraData.flags = CameraFlags.gameWaitingStart
            else
                client:createAndSpawnPlayer(name)
                if bit.band(camera.cameraData.values.flags, CameraFlags.gameWaitingStart) ~= 0 then
                    camera.cameraData.values.flags = bit.band(camera.cameraData.values.flags, bit.bnot(CameraFlags.gameWaitingStart))
                end
                toRemove[#toRemove + 1] = client
            end
        end
    end
    for i = 1, #toRemove do
        self.game.clientsAwaitingSpawn[toRemove[i]] = nil
    end
end

function ArenaEntity:updateBounds(arenaWidth, arenaHeight)
    self.width = arenaWidth
    self.height = arenaHeight
    self.arenaData.topY = -arenaHeight / 2
    self.arenaData.bottomY = arenaHeight / 2
    self.arenaData.leftX = -arenaWidth / 2
    self.arenaData.rightX = arenaWidth / 2
end

function ArenaEntity:attemptFactorySpawn(tank)
    if math.random() > config.factorySpawnChance then return false end
    local TeamEntity = require("../Entity/Misc/TeamEntity")
    if TeamEntity.TeamEntity then TeamEntity = TeamEntity.TeamEntity end
    local team = tank.relationsData and tank.relationsData.values and tank.relationsData.values.team
    if type(TeamEntity.isTeam) ~= "function" or not TeamEntity.isTeam(team) then return false end
    local teammates = self:getTeamPlayers(team)
    local factories = {}
    for i = 1, #teammates do
        if teammates[i]._currentTank == Tank.Factory and not teammates[i].deletionAnimation then
            factories[#factories + 1] = teammates[i]
        end
    end
    if #factories == 0 then return false end
    local factory = util.randomFrom(factories)
    local pos = factory:getWorldPosition()
    local barrel = factory.barrels[1]
    local shootAngle = barrel.definition.angle + factory.positionData.values.angle
    tank.positionData.values.x = pos.x + (math.cos(shootAngle) * barrel.physicsData.values.size) - math.sin(shootAngle) * barrel.definition.offset * factory.scaleFactor
    tank.positionData.values.y = pos.y + (math.sin(shootAngle) * barrel.physicsData.values.size) + math.cos(shootAngle) * barrel.definition.offset * factory.scaleFactor
    tank:addVelocity(shootAngle, 25)
    return true
end

function ArenaEntity:spawnPlayer(tank, client)
    local ok, used = pcall(self.attemptFactorySpawn, self, tank)
    if ok and used then return end
    local pos = self:findPlayerSpawnLocation()
    tank.positionData.values.x = pos.x
    tank.positionData.values.y = pos.y
end

function ArenaEntity:close()
    for client in pairs(self.game.clients) do
        if client ~= "size" and type(client.notify) == "function" then
            client:notify("Arena closed: No players can join", 0xFF0000, -1)
        end
    end
    self.state = ArenaState.CLOSING
    self.arenaData.flags = bit.bor(self.arenaData.values.flags, ArenaFlags.noJoining)

    local ArenaCloser = require("../Entity/Misc/ArenaCloser")
    local acCount = math.floor(math.sqrt(self.width) / 10)
    local radius = self.width * util.SQRT1_2 + 5000
    for i = 0, acCount - 1 do
        local ac = ArenaCloser:new(self.game)
        local angle = (i / acCount) * util.PI2
        ac.positionData.values.x = math.cos(angle) * radius
        ac.positionData.values.y = math.sin(angle) * radius
        ac.positionData.values.angle = angle + math.pi
    end

    util.saveToLog("Arena Closing", "Arena running at `" .. self.game.gamemode .. "` is now closing.", 0xFFE869)
end

function ArenaEntity:onGameStarted()
    self.state = ArenaState.OPEN
end

function ArenaEntity:tick(tick)
    self.shapes:tick()
    self:updateArenaState()
    self:manageCountdown()
    if self.leader and bit.band(self.arenaData.values.flags, ArenaFlags.showsLeaderArrow) ~= 0 then
        self.arenaData.leaderX = self.leader.positionData.values.x
        self.arenaData.leaderY = self.leader.positionData.values.y
    end
    if self.bossManager then
        self.bossManager:tick(tick)
    end
end

ArenaEntity.ArenaState = ArenaState

return ArenaEntity
