local bit = require("bit")
local config = require("src.config")
local WebSocket = require("src.net.websocket")
local Url = require("src.net.url")
local Reader = require("src.coder.reader")
local Encode = require("src.protocol.encode")
local Enums = require("src.protocol.enums")
local Console = require("src.ui.console")
local Settings = require("src.ui.settings")
local Achievements = require("src.data.achievements")
local Servers = require("src.data.servers")
local Changelog = require("src.data.changelog")

return function(Game)
function Game:persistPassword()
    Settings.setDevPassword(self.password or "")
end

function Game:notify(text, color, time)
    self.notifications[#self.notifications + 1] = {
        text = text or "",
        color = color or 0,
        untilTime = love.timer.getTime() + ((time and time > 0) and (time / 1000) or 4)
    }
    Console.push(self, text or "", color or 0xEEEEEE)
end

function Game:send(payload)
    if self.ws and self.ws.state == "open" then
        self.ws:sendBinary(payload)
    end
end

function Game:arenaClosed()
    local arena = self.world and self.world:arenaValues()
    if not arena then return false end
    return bit.band(arena.flags or 0, Enums.ArenaFlags.noJoining) ~= 0
end

function Game:isWaitingStart()
    return self.world:isWaitingStart()
end

local PLAY_READY = 0.5
local TANK_READY = 0.25

function Game:spawn()
    if self.world:isSpawned() then
        self.pendingSpawn = false
        self.spawnRetry = 0
        self.wantSpawn = false
        return
    end
    self.pendingSpawn = true
    if self.world:isWaitingStart() then
        return
    end
    if self:arenaClosed() then
        return
    end
    local now = love.timer.getTime()
    if self._lastSpawnSend and (now - self._lastSpawnSend) < 0.5 then
        return
    end
    self._lastSpawnSend = now
    self.spawnRetry = 0
    local name = (self.spawnName or ""):sub(1, 16)
    self:send(Encode.spawn(name))
end

function Game:playTarget()
    local raw = self.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    return Url.resolvePlay(raw, self.gamemode, self.modes)
end

function Game:endpointKey()
    local target = self:playTarget()
    if not target then
        return tostring(self.url or "") .. "/" .. tostring(self.gamemode or "ffa")
    end
    return target.host .. ":" .. tostring(target.port) .. Url.requestPath(target)
end

function Game:connected()
    return self.ws ~= nil and self.ws.state == "open"
end

function Game:sameSession()
    return self._connectedTo == self:endpointKey()
        and (self._authPassword or "") == (self.password or "")
end

function Game:needsAuth()
    return (self.password or "") ~= "" and (self._authPassword or "") ~= (self.password or "")
end

function Game:canCheat()
    if (self.accessLevel or 0) >= 3 then return true end
    if tostring(self.gamemode or "") == "sandbox" then return true end
    local arena = self.world and self.world:arenaValues()
    local flags = arena and arena.flags or 0
    return bit.band(flags, Enums.ArenaFlags.canUseCheats) ~= 0
end

function Game:showingDeath()
    return self.world:isDead()
end

function Game:dropSocket()
    if not self.ws then return end
    self.ws.onOpen = nil
    self.ws.onMessage = nil
    self.ws.onClose = nil
    self.ws:close()
    self.ws = nil
end

function Game:selectGamemode(id)
    if not id then return end
    local same = self.gamemode == id and self:sameSession()
    self.gamemode = id
    self.focus = "gamemode"
    if same and (self:connected() or self.state == "connecting") then
        return
    end
    self.wantSpawn = false
    self.pendingSpawn = false
    self.readyDelay = 0
    self:connect()
end

function Game:syncGamemodeFromUrl()
    local raw = self.url
    if type(raw) ~= "string" or raw:match("^%s*$") then return end
    local parsed = Url.parse(raw)
    if not parsed then return end
    local last = Url.lastSegment(parsed.path)
    if last == "" then return end
    last = last:lower()
    local modes = self.modes or Servers.fallback()
    for i = 1, #modes do
        if modes[i].id == last then
            self.gamemode = last
            return
        end
    end
end

function Game:play()
    if self.world:isSpawned() or self.world:isWaitingStart() then
        return
    end
    self:syncGamemodeFromUrl()
    self.wantSpawn = true
    self.focus = "spawnName"
    if not self.readyDelay or self.readyDelay <= 0 then
        self.readyDelay = PLAY_READY
    end
    if self:connected() and self:sameSession() then
        return
    end
    if self.state == "connecting" and self:sameSession() then
        return
    end
    self:connect()
end

function Game:queueTankUpgrade(id)
    id = tonumber(id)
    if not id then return end
    self.pendingTankId = id
    self.tankDelay = TANK_READY
end

function Game:cycleGamemode(dir)
    local modes = self.modes or Servers.fallback()
    if #modes < 1 then return end
    local idx = 1
    for i = 1, #modes do
        if modes[i].id == self.gamemode then
            idx = i
            break
        end
    end
    idx = ((idx - 1 + dir) % #modes) + 1
    self:selectGamemode(modes[idx].id)
end

function Game:connect()
    self.error = nil
    self.pendingSpawn = false
    self.spawnRetry = 0
    self.world:clear()
    self.notifications = {}
    local target, targetErr = self:playTarget()
    if not target then
        self:dropSocket()
        self.state = "menu"
        self.error = targetErr or "invalid url"
        self._connectedTo = ""
        self._authPassword = ""
        self.wantSpawn = false
        return
    end
    self:dropSocket()
    self.ws = WebSocket:new()
    local game = self
    self.ws.onOpen = function()
        game.error = nil
        game.lastPacketAt = love.timer.getTime()
        game:send(Encode.init(game.password))
        game:send(Encode.ping())
        game.pingAcc = 0
        Console.fetch(game)
        Servers.fetch(game)
        Changelog.fetch(game)
    end
    self.ws.onMessage = function(payload)
        game:onPacket(payload)
    end
    self.ws.onClose = function(err)
        game.state = "menu"
        game.error = err or "disconnected"
        game.wantSpawn = false
        game.pendingSpawn = false
        game.readyDelay = 0
        game.tankDelay = 0
        game.pendingTankId = nil
        game._connectedTo = ""
        game._authPassword = ""
        game.paused = false
        game.optionsOpen = false
        game.styleMenuOpen = false
        game.treeOpen = false
    end
    self.state = "connecting"
    self._connectedTo = target.host .. ":" .. tostring(target.port) .. Url.requestPath(target)
    self._authPassword = self.password or ""
    local ok, err = self.ws:connect(target)
    if not ok then
        self.state = "menu"
        self.error = err or "connect failed"
        self._connectedTo = ""
        self._authPassword = ""
        self.wantSpawn = false
        return
    end
end

function Game:disconnect()
    self.wantSpawn = false
    self.pendingSpawn = false
    self.readyDelay = 0
    self.tankDelay = 0
    self.pendingTankId = nil
    self.paused = false
    self.optionsOpen = false
    self.styleMenuOpen = false
    self.treeOpen = false
    self:dropSocket()
    self.state = "menu"
    self._connectedTo = ""
    self._authPassword = ""
    self.world:clear()
end

function Game:inMatch()
    return self.world:isSpawned() or self:showingDeath() or self.world:isWaitingStart()
end

function Game:pause()
    if not self:inMatch() then return end
    self.paused = true
    self.optionsOpen = false
    self.styleMenuOpen = false
    self.treeOpen = false
end

function Game:resume()
    self.paused = false
    self.optionsOpen = false
    self.styleMenuOpen = false
end

function Game:exitToMenu()
    self.paused = false
    self.optionsOpen = false
    self.styleMenuOpen = false
    self.treeOpen = false
    self:goHome()
end

function Game:goHome()
    self.wantSpawn = false
    self.pendingSpawn = false
    self.readyDelay = 0
    self.tankDelay = 0
    self.pendingTankId = nil
    self.spawnRetry = 0
    self.focus = "spawnName"
    self.paused = false
    self.optionsOpen = false
    self.styleMenuOpen = false
    self.treeOpen = false
    self:connect()
end

function Game:markReady()
    if self.state == "connecting" then
        self.state = "playing"
    end
    self.error = nil
    if self.wantSpawn and not self.world:isSpawned() then
        if not self.readyDelay or self.readyDelay <= 0 then
            self:spawn()
        end
    end
end

function Game:onPacket(data)
    if type(data) ~= "string" or #data < 1 then return end
    self.lastPacketAt = love.timer.getTime()
    local r = Reader:new(data)
    local header = r:u8()
    local CB = Enums.ClientBound
    if header == CB.Update then
        self.world:applyUpdate(r)
        self:markReady()
    elseif header == CB.OutdatedClient then
        local hash = r:stringNT()
        self.error = "outdated client, server hash " .. hash
        self:disconnect()
    elseif header == CB.Notification then
        local text = r:stringNT()
        local color = r:u32()
        local time = r:float()
        r:stringNT()
        self:notify(text, color, time)
    elseif header == CB.ServerInfo then
        local mode = r:stringNT()
        self.serverHost = r:stringNT()
        if type(mode) == "string" and mode ~= "" then
            self.gamemode = mode
        end
    elseif header == CB.Ping then
        -- round trip complete
    elseif header == CB.Accept then
        self.accessLevel = r:vi()
        self:markReady()
        if self.accessLevel >= 3 then
            Console.push(self, "Full access granted", 0x5A65EA)
        end
    elseif header == CB.PlayerCount then
        self.playerCount = r:vu()
    elseif header == CB.InvalidParty then
        self:notify("Invalid party", 0xFF0000, 4000)
    elseif header == CB.Achievement then
        local n = r:vu()
        for _ = 1, n do
            local unlocked = Achievements.unlock(r:stringNT())
            if unlocked then
                self:notify("Achievement: " .. unlocked.name, 0xFFD76A, 5000)
            end
        end
    end
end
end
