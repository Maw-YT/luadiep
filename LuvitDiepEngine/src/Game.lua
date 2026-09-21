--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("./class")
local config = require("./config")
local util = require("./util")
local Writer = require("./Coder/Writer")
local EntityManager = require("./Native/Manager")
local Enums = require("./Const/Enums")

local ClientBound = Enums.ClientBound

local GameServer = class()
GameServer.games = {}
GameServer.globalPlayerCount = 0
GameServer.bannedClients = {}

local WSSWriterStream = class(Writer)
function WSSWriterStream:init(game)
    Writer.init(self)
    self.game = game
end
function WSSWriterStream:send()
    local bytes = self:write()
    for client in pairs(self.game.clients) do
        if client ~= "size" then
            client:send(bytes)
        end
    end
end

function GameServer.broadcastPlayerCount()
    for i = 1, #GameServer.games do
        local game = GameServer.games[i]
        game:broadcast():vu(ClientBound.PlayerCount):vu(GameServer.globalPlayerCount):send()
    end
end

function GameServer:init(ArenaClass, name)
    if type(ArenaClass) == "string" then
        self.gamemode = ArenaClass
        local map = {
            ffa = require("./Gamemodes/FFA"),
            teams = require("./Gamemodes/Teams"),
            ["4teams"] = require("./Gamemodes/FourTeams"),
            maze = require("./Gamemodes/Maze"),
            survival = require("./Gamemodes/Survival"),
            dom = require("./Gamemodes/Domination"),
            mot = require("./Gamemodes/Mothership"),
            sandbox = require("./Gamemodes/Sandbox")
        }
        ArenaClass = map[ArenaClass] or require("./Gamemodes/Sandbox")
    elseif ArenaClass.GAMEMODE_ID then
        self.gamemode = ArenaClass.GAMEMODE_ID
    else
        self.gamemode = "sandbox"
    end
    self.name = name
    self.running = true
    self.playersOnMap = false
    self.clients = { size = 0 }
    self.clientsAwaitingSpawn = {}
    self.enableAchievements = config.enableAchievements
    self.tick = 0
    self._arenaClass = ArenaClass
    self.entities = EntityManager:new(self)
    self.arena = ArenaClass:new(self)
    self:_startTick()
    GameServer.games[#GameServer.games + 1] = self
end

function GameServer:addClient(client)
    if not self.clients[client] then
        self.clients[client] = true
        self.clients.size = self.clients.size + 1
        GameServer.globalPlayerCount = GameServer.globalPlayerCount + 1
        GameServer.broadcastPlayerCount()
    end
end

function GameServer:removeClient(client)
    if self.clients[client] then
        self.clients[client] = nil
        self.clients.size = self.clients.size - 1
        GameServer.globalPlayerCount = GameServer.globalPlayerCount - 1
        GameServer.broadcastPlayerCount()
        self.clientsAwaitingSpawn[client] = nil
    end
end

function GameServer:_startTick()
    local timer = require("timer")
    local selfRef = self
    self._tickInterval = timer.setInterval(config.mspt, function()
        if selfRef.clients.size > 0 then
            local ok, err = xpcall(function()
                selfRef:tickLoop()
            end, debug.traceback)
            if not ok then
                util.log("Tick error: " .. tostring(err))
            end
        end
    end)
end

function GameServer:broadcast()
    return WSSWriterStream:new(self)
end

function GameServer:broadcastMessage(text, color, time, id)
    self:broadcast():u8(ClientBound.Notification):stringNT(text):u32(color or 0):float(time or 5000):stringNT(id or ""):send()
end

function GameServer:endGame()
    util.saveToLog("Game Instance Ending", "Game running " .. self.gamemode .. " is now closing.", 0xEE4132)
    util.log("Ending Game instance")
    local timer = require("timer")
    if self._tickInterval then timer.clearInterval(self._tickInterval) end
    self.tick = 0
    self.entities:clear()
    self.running = false
    self:onEnd()
end

function GameServer:onEnd()
    util.log("Game instance is now over")
    self:start()
end

function GameServer:start()
    if self.running then return end
    util.log("New game instance booting up")
    self.entities = EntityManager:new(self)
    self.tick = 0
    self.arena = self._arenaClass:new(self)
    for client in pairs(self.clients) do
        if client ~= "size" then
            client:acceptClient()
        end
    end
    self.running = true
    self:_startTick()
end

function GameServer:tickLoop()
    self.tick = self.tick + 1
    self.entities:preTick(self.tick)
    for client in pairs(self.clients) do
        if client ~= "size" then
            client:tick(self.tick)
        end
    end
    self.entities:tick(self.tick)
    self.entities:postTick(self.tick)
end

return GameServer
