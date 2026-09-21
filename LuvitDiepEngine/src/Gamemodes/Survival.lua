--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")
local ShapeManager = require("../Misc/ShapeManager")
local Entity = require("../Native/Entity")
local Enums = require("../Const/Enums")
local config = require("../config")

local ArenaFlags = Enums.ArenaFlags
local ArenaState = ArenaEntity.ArenaState

local MIN_PLAYERS = 2
local SCORE_PER_TICK = 0.2

local SurvivalShapeManager = class(ShapeManager)
function SurvivalShapeManager:wantedShapes()
    local ratio = math.ceil((self.game.arena.width / 2500) ^ 2)
    return math.floor(12.5 * ratio)
end

local SurvivalArena = class(ArenaEntity)
SurvivalArena.GAMEMODE_ID = "survival"

local function awaitingCount(game)
    local n = 0
    for _ in pairs(game.clientsAwaitingSpawn) do
        n = n + 1
    end
    return n
end

function SurvivalArena:init(game)
    ArenaEntity.init(self, game)
    self.shapes = SurvivalShapeManager:new(self)
    self.shapeScoreRewardMultiplier = 3.0
    self.arenaData.values.flags = bit.band(self.arenaData.values.flags, bit.bnot(ArenaFlags.gameReadyStart))
    self.arenaData.values.playersNeeded = MIN_PLAYERS
    self:setSurvivalArenaSize(0)
end

function SurvivalArena:setSurvivalArenaSize(playerCount)
    local arenaSize = math.floor(25 * math.sqrt(math.max(playerCount, 1))) * 100
    if self.width == arenaSize and self.height == arenaSize then return end
    self:updateBounds(arenaSize, arenaSize)
end

function SurvivalArena:updateArenaState()
    local players = self:getAlivePlayers()
    local aliveCount = #players
    self:setSurvivalArenaSize(aliveCount)

    if (self.game.tick % config.scoreboardUpdateInterval) == 0 then
        self:updateScoreboard(players)
    end

    if aliveCount <= 1 and self.state == ArenaState.OPEN then
        self.state = ArenaState.OVER
        self:close()
    end

    if aliveCount == 0 and self.state == ArenaState.CLOSING then
        self.state = ArenaState.CLOSED
        local timer = require("timer")
        local game = self.game
        timer.setTimeout(5000, function()
            game:endGame()
        end)
    end
end

function SurvivalArena:manageCountdown()
    if self.state == ArenaState.COUNTDOWN then
        self.arenaData.playersNeeded = MIN_PLAYERS - awaitingCount(self.game)
        if self.arenaData.values.playersNeeded <= 0 then
            self.arenaData.flags = bit.bor(self.arenaData.values.flags, ArenaFlags.gameReadyStart)
        else
            self.arenaData.ticksUntilStart = config.countdownDuration
            if bit.band(self.arenaData.values.flags, ArenaFlags.gameReadyStart) ~= 0 then
                self.arenaData.flags = bit.band(self.arenaData.values.flags, bit.bnot(ArenaFlags.gameReadyStart))
            end
        end
    end
    ArenaEntity.manageCountdown(self)
end

function SurvivalArena:onGameStarted()
    ArenaEntity.onGameStarted(self)
    self:setSurvivalArenaSize(awaitingCount(self.game))
    self.arenaData.flags = bit.bor(self.arenaData.values.flags, ArenaFlags.noJoining)
end

function SurvivalArena:tick(tick)
    for client in pairs(self.game.clients) do
        if client ~= "size" then
            local camera = client.camera
            if camera and Entity.exists(camera.cameraData.values.player) then
                camera:addScore(SCORE_PER_TICK)
            end
        end
    end
    ArenaEntity.tick(self, tick)
end

return SurvivalArena
