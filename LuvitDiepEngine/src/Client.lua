--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("./class")
local config = require("./config")
local util = require("./util")
local Reader = require("./Coder/Reader")
local Writer = require("./Coder/Writer")
local Entity = require("./Native/Entity")
local Enums = require("./Const/Enums")
local TankDefs = require("./Const/TankDefinitions")
local DevTankDefinitions = require("./Const/DevTankDefinitions")
local AIMod = require("./Entity/AI")

local ClientBound = Enums.ClientBound
local ServerBound = Enums.ServerBound
local InputFlags = Enums.InputFlags
local ArenaFlags = Enums.ArenaFlags
local CameraFlags = Enums.CameraFlags
local NameFlags = Enums.NameFlags
local StatCount = Enums.StatCount
local Tank = Enums.Tank
local EntityStateFlags = Enums.EntityStateFlags
local DevTank = DevTankDefinitions.DevTank
local Inputs = AIMod.Inputs
local AIState = AIMod.AIState

local TANK_XOR = config.magicNum % TankDefs.TankCount
local STAT_XOR = config.magicNum % StatCount
local PING_PACKET = string.char(ClientBound.Ping)

local WSWriterStream = class(Writer)
function WSWriterStream:init(client)
    Writer.init(self)
    self.client = client
end
function WSWriterStream:send()
    self.client:send(self:write())
end

local ClientInputs = class(Inputs)
function ClientInputs:init(client)
    Inputs.init(self)
    self.client = client
    self.cachedFlags = 0
    self.isPossessing = false
end

local Client = class()

function Client:init(ws, game, ipAddress)
    self.terminated = false
    self.game = game
    self.ws = ws
    self.ipAddress = ipAddress or "unknown"
    self.accessLevel = config.AccessLevel.NoAccess
    self.incomingCache = {}
    self.inputs = ClientInputs:new(self)
    self.camera = nil
    self.devCheatsUsed = false
    self.isInvulnerable = false
    self.pendingAchievements = {}
    self.connectTick = game.tick
    self.lastPingTick = game.tick
    game:addClient(self)
end

function Client:write()
    return WSWriterStream:new(self)
end

function Client:send(data)
    if not self.ws or self.ws.closed then
        return
    end
    pcall(function()
        self.ws:sendBinary(data)
    end)
end

function Client:acceptClient()
    local GameServer = require("./Game")
    self:write():u8(ClientBound.ServerInfo):stringNT(self.game.gamemode):stringNT(config.host):send()
    self:write():u8(ClientBound.PlayerCount):vu(GameServer.globalPlayerCount):send()
    self:write():u8(ClientBound.Accept):vi(self.accessLevel):send()
    local Camera = require("./Native/Camera")
    if Entity.exists(self.camera) then
        self.camera:delete()
    end
    self.camera = Camera.ClientCamera:new(self.game, self)
end

function Client:onClose()
    self.ws = nil
    self:terminate()
end

function Client:terminate()
    if self.terminated then return end
    if self.ws then
        self.ws:close()
        return
    end
    self.terminated = true
    self.game:removeClient(self)
    self.inputs.deleted = true
    self.inputs.movement.magnitude = 0
    if Entity.exists(self.camera) then self.camera:delete() end
end

function Client:onMessage(data)
    if type(data) ~= "string" then return self:terminate() end
    if #data < 1 then return end
    if #data == 1 and data:byte(1) == 0x00 then return self:terminate() end
    self.lastPingTick = self.game.tick
    local header = data:byte(1)
    if header == ServerBound.Ping then
        self:send(PING_PACKET)
    else
        if header == ServerBound.Init then
            util.log("Init packet (" .. tostring(#data) .. " bytes)")
        end
        if not self.incomingCache[header] then self.incomingCache[header] = {} end
        if #self.incomingCache[header] > 0 then
            if header == ServerBound.Input then
                local r = Reader:new(data)
                r.at = 1
                local flags = r:vu()
                self.inputs.cachedFlags = bit.bor(self.inputs.cachedFlags, bit.band(flags, 0x6F1))
            elseif header == ServerBound.StatUpgrade or header == ServerBound.TankUpgrade or header == ServerBound.Spawn or header == ServerBound.TCPInit then
                self.incomingCache[header][#self.incomingCache[header] + 1] = data
            end
            return
        end
        self.incomingCache[header][1] = data
    end
end

function Client:handleIncoming(header, data)
    if self.terminated then return end
    local r = Reader:new(data)
    r.at = 1
    local camera = self.camera
    local TankBody = require("./Entity/Tank/TankBody")
    local GameServer = require("./Game")

    if header == ServerBound.Init then
        if camera then return self:terminate() end
        local buildHash = r:stringNT()
        local pw = r:stringNT()
        if buildHash ~= config.buildHash then
            util.log("Kicking client. Invalid build hash " .. tostring(buildHash))
            self:write():u8(ClientBound.OutdatedClient):stringNT(config.buildHash):send()
            local timer = require("timer")
            local selfRef = self
            timer.setTimeout(100, function() selfRef:terminate() end)
            return
        end
        if config.devPasswordHash and pw and pw ~= "" then
            local okHash, hash = pcall(function()
                local openssl = require("openssl")
                return openssl.digest.digest("sha256", pw)
            end)
            local got = tostring(okHash and hash or ""):lower():gsub("%s+", "")
            local want = tostring(config.devPasswordHash):lower():gsub("%s+", "")
            if got ~= "" and got == want then
                self.accessLevel = config.AccessLevel.FullAccess
                util.saveToLog("Developer Connected", "A client connected with full access.", 0x5A65EA)
            else
                self.accessLevel = config.defaultAccessLevel
            end
        else
            self.accessLevel = config.defaultAccessLevel
        end
        if self.accessLevel == config.AccessLevel.NoAccess then
            return self:terminate()
        end
        self:acceptClient()
        util.log("Client accepted (" .. tostring(self.accessLevel) .. ")")
        if self.accessLevel == config.AccessLevel.FullAccess then
            self:notify("Full access granted", 0x5A65EA, 4000, "access")
        elseif pw and pw ~= "" then
            if not config.devPasswordHash then
                self:notify("Server has no DEV_PASSWORD_HASH set", 0xFFAA00, 6000, "access")
            else
                self:notify("Dev password rejected", 0xFF0000, 4000, "access")
            end
        end
        return
    end

    if not Entity.exists(camera) then return end

    if header == ServerBound.Input then
        local previousFlags = self.inputs.flags
        local flags = bit.bor(r:vu(), self.inputs.cachedFlags)
        self.inputs.flags = flags
        self.inputs.cachedFlags = 0
        local fov = camera.cameraData.values.FOV
        local width = (1920 / fov) / 2
        local height = (1080 / fov) / 2
        local minX = camera.cameraData.values.cameraX - width
        local maxX = camera.cameraData.values.cameraX + width
        local minY = camera.cameraData.values.cameraY - height
        local maxY = camera.cameraData.values.cameraY + height
        local mouseX = r:vf()
        local mouseY = r:vf()
        if not util.isFinite(mouseX) or not util.isFinite(mouseY) then return end
        self.inputs.mouse.x = util.constrain(mouseX, minX, maxX)
        self.inputs.mouse.y = util.constrain(mouseY, minY, maxY)
        local player = camera.cameraData.values.player
        if not Entity.exists(player) or not TankBody.isTank(player) then return end
        if self.inputs.isPossessing and self.accessLevel ~= config.AccessLevel.FullAccess then return end
        if bit.band(flags, InputFlags.godmode) ~= 0 then
            if self.accessLevel == config.AccessLevel.FullAccess then
                self:setHasCheated(true)
                player:setTank(player._currentTank < 0 and Tank.Basic or DevTank.Developer)
            elseif bit.band(self.game.arena.arenaData.values.flags, ArenaFlags.canUseCheats) ~= 0 then
                if self.game.clients.size == 1 and self.game.arena:isOpen() then
                    self:setHasCheated(true)
                    player:setInvulnerability(not player.isInvulnerable)
                    self:notify("God mode: " .. (player.isInvulnerable and "ON" or "OFF"), 0x000000, 5000, "godmode_toggle")
                end
            end
        end
        if bit.band(flags, InputFlags.rightclick) ~= 0 and bit.band(previousFlags, InputFlags.rightclick) == 0
            and (player._currentTank == DevTank.Developer or player._currentTank == DevTank.Spectator) then
            player.positionData.x = self.inputs.mouse.x
            player.positionData.y = self.inputs.mouse.y
            player:setVelocity(0, 0)
            player.entityState = bit.bor(player.entityState, EntityStateFlags.needsCreate, EntityStateFlags.needsDelete)
        end
        if bit.band(flags, InputFlags.switchtank) ~= 0 and bit.band(previousFlags, InputFlags.switchtank) == 0 then
            if self.accessLevel == config.AccessLevel.FullAccess or bit.band(self.game.arena.arenaData.values.flags, ArenaFlags.canUseCheats) ~= 0 then
                self:setHasCheated(true)
                local tank = player._currentTank
                if tank >= 0 then
                    local defs = TankDefs.TankDefinitions
                    local len = 0
                    for k in pairs(defs) do if type(k) == "number" and k + 1 > len then len = k + 1 end end
                    tank = (tank + len - 1) % len
                    while not defs[tank] or (defs[tank].flags and defs[tank].flags.devOnly and self.accessLevel < config.AccessLevel.FullAccess) do
                        tank = (tank + len - 1) % len
                    end
                else
                    local isDeveloper = self.accessLevel == config.AccessLevel.FullAccess
                    tank = -tank - 1
                    tank = (tank + 1) % #DevTankDefinitions
                    while not DevTankDefinitions[tank + 1] or (DevTankDefinitions[tank + 1].flags.devOnly and not isDeveloper) do
                        tank = (tank + 1) % #DevTankDefinitions
                    end
                    tank = -(tank + 1)
                end
                player:setTank(tank)
            end
        end
        if bit.band(flags, InputFlags.levelup) ~= 0 then
            if self.accessLevel == config.AccessLevel.FullAccess
                or (camera.cameraData.values.level < config.maxPlayerLevel
                    and bit.band(self.game.arena.arenaData.values.flags, ArenaFlags.canUseCheats) ~= 0) then
                self:setHasCheated(true)
                camera:setLevel(camera.cameraData.values.level + 1)
            end
        end
        if bit.band(flags, InputFlags.suicide) ~= 0 and not player.deletionAnimation then
            if self.accessLevel == config.AccessLevel.FullAccess or bit.band(self.game.arena.arenaData.values.flags, ArenaFlags.canUseCheats) ~= 0 then
                self:setHasCheated(true)
                player:destroy()
                player:onDeath(player)
                player:onKill(player, player)
            end
        end
        return
    elseif header == ServerBound.Spawn then
        if bit.band(self.game.arena.arenaData.values.flags, ArenaFlags.noJoining) ~= 0 then return end
        if Entity.exists(camera.cameraData.values.player) then
            return
        end
        util.log("Client wants to spawn")
        local name = r:stringNT():sub(1, 16)
        self.game.clientsAwaitingSpawn[self] = name
        return
    elseif header == ServerBound.StatUpgrade then
        if camera.cameraData.statsAvailable <= 0 then return end
        local player = camera.cameraData.values.player
        if not TankBody.isTank(player) then return end
        local definition = TankDefs.getTankById(player._currentTank)
        if not definition or not definition.stats or #definition.stats == 0 then return end
        local statId = bit.bxor(r:vi(), STAT_XOR)
        if statId < 0 or statId >= StatCount then return end
        local statLimit = camera.cameraData.values.statLimits:get(statId)
        if camera.cameraData.values.statLevels:get(statId) >= statLimit then return end
        camera:addStat(statId, 1)
        camera.cameraData.statsAvailable = camera.cameraData.values.statsAvailable - 1
        return
    elseif header == ServerBound.TankUpgrade then
        local player = camera.cameraData.values.player
        if not TankBody.isTank(player) then return end
        local definition = TankDefs.getTankById(player._currentTank)
        local tankId = bit.bxor(r:vi(), TANK_XOR)
        tankId = math.floor(tonumber(tankId) or 0)
        local tankDefinition = TankDefs.getTankById(tankId)
        if not definition or not util.includes(definition.upgrades, tankId) or not tankDefinition then return end
        if (tonumber(tankDefinition.levelRequirement) or 0) > (tonumber(camera.cameraData.values.level) or 0) then return end
        player:setTank(tankId)
        return
    elseif header == ServerBound.ExtensionFound then
        util.log("Someone is cheating")
        self:ban()
        return
    elseif header == ServerBound.ToRespawn then
        camera.cameraData.flags = bit.band(camera.cameraData.values.flags, bit.bnot(CameraFlags.showingDeathStats))
        return
    elseif header == ServerBound.TakeTank then
        if not Entity.exists(camera.cameraData.player) then return end
        if #self.game.entities.AIs == 0 then
            return self:notify("Someone has already taken this tank", 0x000000, 5000, "cant_claim_info")
        end
        if not self.inputs.isPossessing then
            local player = camera.cameraData.player
            local x = (player.positionData and player.positionData.values.x) or 0
            local y = (player.positionData and player.positionData.values.y) or 0
            local AIs = {}
            for i = 1, #self.game.entities.AIs do AIs[i] = self.game.entities.AIs[i] end
            table.sort(AIs, function(a, b)
                local p1 = a.owner:getWorldPosition()
                local p2 = b.owner:getWorldPosition()
                return ((p1.x - x) ^ 2 + (p1.y - y) ^ 2) < ((p2.x - x) ^ 2 + (p2.y - y) ^ 2)
            end)
            for i = 1, #AIs do
                if AIs[i].state ~= AIState.possessed
                    and ((AIs[i].owner.relationsData.values.team == camera.relationsData.values.team and AIs[i].isClaimable)
                        or self.accessLevel == config.AccessLevel.FullAccess) then
                    if self:possess(AIs[i]) then return end
                end
            end
            self:notify("Someone has already taken that tank", 0x000000, 5000, "cant_claim_info")
        else
            camera.cameraData.FOV = 0.35
            self.inputs.deleted = true
        end
        return
    elseif header == ServerBound.TCPInit then
        if not config.enableCommands then return end
        local cmd = r:stringNT()
        local argsLength = r:u8()
        local args = {}
        for i = 1, argsLength do args[i] = r:stringNT() end
        require("./Const/Commands").executeCommand(self, cmd, args)
        return
    else
        util.log("Suspicious activies have been evaded")
        return self:ban()
    end
end

function Client:setHasCheated(value)
    local player = self.camera and self.camera.cameraData.values.player
    if player and player.nameData then
        if value then
            player.nameData.flags = bit.bor(player.nameData.values.flags, NameFlags.highlightedName)
        else
            player.nameData.flags = bit.band(player.nameData.values.flags, bit.bnot(NameFlags.highlightedName))
        end
    end
    self.devCheatsUsed = value
end

function Client:hasCheated()
    return self.devCheatsUsed
end

function Client:possess(ai)
    local TankBody = require("./Entity/Tank/TankBody")
    local ObjectEntity = require("./Entity/Object")
    if not self.camera or not self.camera.cameraData or ai.state == AIState.possessed then return false end
    self.inputs.deleted = true
    self.inputs = ClientInputs:new(self)
    ai.inputs = self.inputs
    self.inputs.isPossessing = true
    ai.state = AIState.possessed
    if ObjectEntity.isObject(self.camera.cameraData.values.player) then
        local color = self.camera.cameraData.values.player.styleData.values.color
        self.camera.cameraData.values.player.styleData.values.color = -1
        self.camera.cameraData.values.player.styleData.color = color
    end
    self.camera.cameraData.tankOverride = (ai.owner.nameData and ai.owner.nameData.values.name) or ""
    self.camera.cameraData.tank = 53
    for i = 0, StatCount - 1 do
        self.camera.cameraData.values.statLevels:set(i, 0)
        self.camera.cameraData.values.statLimits:set(i, 7)
        self.camera.cameraData.values.statNames:set(i, "")
    end
    self.camera.cameraData.killedBy = ""
    self.camera.cameraData.player = ai.owner
    self.camera.cameraData.movementSpeed = ai.movementSpeed
    if TankBody.isTank(ai.owner) then
        self.camera.cameraData.tank = ai.owner.cameraEntity.cameraData.values.tank
        self.camera:setLevel(ai.owner.cameraEntity.cameraData.values.level)
        for i = 0, StatCount - 1 do
            self.camera.cameraData.values.statLevels:set(i, ai.owner.cameraEntity.cameraData.values.statLevels:get(i))
            self.camera.cameraData.values.statLimits:set(i, ai.owner.cameraEntity.cameraData.values.statLimits:get(i))
            self.camera.cameraData.values.statNames:set(i, ai.owner.cameraEntity.cameraData.values.statNames:get(i))
        end
        self.camera.cameraData.FOV = ai.owner.cameraEntity.cameraData.FOV
    else
        self.camera:setLevel(30)
        self.camera.cameraData.FOV = 0.35
    end
    self.camera.cameraData.statsAvailable = 0
    self.camera.cameraData.score = 0
    self.camera.entityState = bit.bor(EntityStateFlags.needsCreate, EntityStateFlags.needsDelete)
    self:notify("Press H to surrender control of the tank", 0x000000, 15000)
    return true
end

function Client:notify(text, color, time, id)
    if not self.ws then return end
    self:write():u8(ClientBound.Notification):stringNT(text or ""):u32(color or 0):float(time or 5000):stringNT(id or ""):send()
end

function Client:giveAchievements(hashes)
    if type(hashes) ~= "table" then return end
    for i = 1, #hashes do
        self.pendingAchievements[#self.pendingAchievements + 1] = hashes[i]
    end
end

function Client:ban()
    if not self.ws then return end
    util.saveToLog("IP Banned", "Banned " .. self.ipAddress, 0xEE326A)
    if self.accessLevel >= config.unbannableLevelMinimum then
        util.saveToLog("IP Ban Cancelled", "Cancelled ban on " .. self.ipAddress, 0x6A32EE)
        return
    end
    local GameServer = require("./Game")
    GameServer.bannedClients[self.ipAddress] = true
    for client in pairs(self.game.clients) do
        if client ~= "size" and client.ipAddress == self.ipAddress then
            client:terminate()
        end
    end
end

function Client:createAndSpawnPlayer(name)
    local TankBody = require("./Entity/Tank/TankBody")
    local camera = self.camera
    if not Entity.exists(camera) then return end
    camera.cameraData.values.statsAvailable = 0
    camera.cameraData.values.level = 1
    for i = 0, StatCount - 1 do
        camera.cameraData.values.statLevels:set(i, 0)
    end
    local tank = TankBody:new(self.game, camera, self.inputs)
    camera.cameraData.player = tank
    camera.relationsData.owner = tank
    camera.relationsData.parent = tank
    tank:setTank(Tank.Basic)
    tank.nameData.values.name = name
    camera:setLevel(camera.cameraData.values.respawnLevel)
    if self:hasCheated() then self:setHasCheated(true) end
    camera.entityState = bit.bor(EntityStateFlags.needsCreate, EntityStateFlags.needsDelete)
    camera.spectatee = nil
    self.inputs.isPossessing = false
    self.inputs.movement.magnitude = 0
    self.game.arena:spawnPlayer(tank, self)
    -- Leave death-cam / spectate coords so the first updateView is around
    -- the new tank, not the killer (arena closer).
    camera.cameraData.flags = bit.band(camera.cameraData.values.flags, bit.bnot(CameraFlags.usesCameraCoords))
    camera.cameraData.cameraX = tank.positionData.values.x
    camera.cameraData.cameraY = tank.positionData.values.y
    util.log("Spawned '" .. tostring(name) .. "' in " .. self.game.gamemode)
end

function Client:tick(tick)
    local movement = { x = 0, y = 0 }
    if bit.band(self.inputs.flags, InputFlags.up) ~= 0 then movement.y = movement.y - 1 end
    if bit.band(self.inputs.flags, InputFlags.down) ~= 0 then movement.y = movement.y + 1 end
    if bit.band(self.inputs.flags, InputFlags.right) ~= 0 then movement.x = movement.x + 1 end
    if bit.band(self.inputs.flags, InputFlags.left) ~= 0 then movement.x = movement.x - 1 end
    if movement.x ~= 0 or movement.y ~= 0 then
        local angle = math.atan2(movement.y, movement.x)
        local magnitude = util.constrain(math.sqrt(movement.x ^ 2 + movement.y ^ 2), -1, 1)
        self.inputs.movement.magnitude = magnitude
        self.inputs.movement.angle = angle
    end
    local function flushHeader(header)
        local packets = self.incomingCache[header]
        if not packets then return end
        for i = 1, #packets do
            self:handleIncoming(header, packets[i])
        end
        self.incomingCache[header] = {}
    end
    flushHeader(ServerBound.Init)
    for header, packets in pairs(self.incomingCache) do
        if header ~= ServerBound.Ping and header ~= ServerBound.Init and packets then
            flushHeader(header)
        end
    end
    if not self.camera then
        if tick == self.connectTick + 300 then
            return self:terminate()
        end
    elseif self.inputs.deleted then
        self.inputs = ClientInputs:new(self)
        self.camera.cameraData.player = nil
        self.camera.cameraData.respawnLevel = 0
        self.camera.cameraData.cameraX = 0
        self.camera.cameraData.cameraY = 0
        self.camera.cameraData.flags = bit.band(self.camera.cameraData.values.flags, bit.bnot(CameraFlags.showingDeathStats))
    end
    if tick >= self.lastPingTick + 90 * config.tps then
        return self:terminate()
    end
    if #self.pendingAchievements > 0 then
        require("./Const/Achievements").sendAchievements(self, self.pendingAchievements)
        self.pendingAchievements = {}
    end
end

Client.ClientInputs = ClientInputs

return Client
