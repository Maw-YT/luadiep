local bit = require("bit")
local class = require("src.lib.class")
local config = require("src.config")
local Encode = require("src.protocol.encode")
local Enums = require("src.protocol.enums")
local World = require("src.world")
local Input = require("src.input")
local Render = require("src.render")
local Hud = require("src.ui")
local Console = require("src.ui.console")
local Settings = require("src.ui.settings")
local TankTree = require("src.ui.tanktree")
local Achievements = require("src.data.achievements")
local Servers = require("src.data.servers")
local Changelog = require("src.data.changelog")
local Tanks = require("src.data.tanks")

local Game = class()
require("src.app.session")(Game)
require("src.app.controls")(Game)

function Game:init()
    self.tanksById, self.tankCount = {}, 1
    self.world = World:new()
    self.ws = nil
    self.state = "menu"
    self.error = nil
    self.url = config.defaultUrl
    self.gamemode = config.defaultGamemode
    self.password = ""
    self.spawnName = ""
    self.playerCount = 0
    self.accessLevel = 0
    self.notifications = {}
    self.buttons = {}
    self.inputAcc = 0
    self.pingAcc = 0
    self.uiConsumed = false
    self.focus = "spawnName"
    self.pendingSpawn = false
    self.spawnRetry = 0
    self.wantSpawn = false
    self._lastSpawnSend = nil
    self.modes = Servers.fallback()
    self._started = false
    self._connectedTo = ""
    self._authPassword = ""
    self.readyDelay = 0
    self.tankDelay = 0
    self.pendingTankId = nil
    self.treeOpen = false
    self.optionsOpen = false
    self.styleMenuOpen = false
    self.paused = false
    self.treeCamX = 0
    self.treeCamY = 0
    self.treeZoom = nil
    self.treeNeedFit = false
    self.autoFire = false
    self.autoSpin = false
    self.autoSpinAngle = 0
    Settings.load()
    Achievements.load()
    Changelog.load()
    Render.setStyle(Settings.style)
    Render.setInnerShadow(Settings.innerShadow)
    self.password = Settings.devPassword or ""
    Console.ensure(self)
    Servers.fetch(self)
    Changelog.fetch(self)
    Tanks.fetch(self)
end

function Game:apiModes()
    local out = {}
    local seen = {}
    local function add(id, label)
        if type(id) ~= "string" or id == "" then return end
        id = id:lower()
        if seen[id] then return end
        seen[id] = true
        out[#out + 1] = { id = id, label = label or id }
    end
    add(self.gamemode)
    local fallback = Servers.fallback()
    local src = self.modes or fallback
    for i = 1, #src do
        add(src[i].id, src[i].label)
    end
    for i = 1, #fallback do
        add(fallback[i].id, fallback[i].label)
    end
    return out
end

function Game:update(dt)
    if dt > 0.25 then dt = 0.25 end
    if not self._started then
        self._started = true
        self:connect()
    end
    if self.ws then
        self.ws:update()
        if self.ws.state == "open" then
            self.pingAcc = self.pingAcc + dt
            if self.pingAcc >= config.pingInterval then
                self.pingAcc = 0
                self:send(Encode.ping())
            end
            local last = self.lastPacketAt
            if last and (love.timer.getTime() - last) > 8 then
                self.ws.err = "timed out"
                self.ws:close()
            end
        elseif self.ws.err then
            self.error = self.ws.err
            if self.state == "connecting" then
                self.state = "menu"
                self._connectedTo = ""
            end
        end
    end
    self.world:interpolate(dt)
    self.world:tickAlive()
    if self.autoSpin and not self.paused then
        self.autoSpinAngle = (self.autoSpinAngle or 0) + dt * 2.35
    end
    Hud.update(dt)
    Console.update(self, dt)
    Servers.update(self, dt)
    Changelog.update(self, dt)
    Tanks.update(self, dt)
    TankTree.update(self, dt)
    Achievements.update(dt)
    if self.treeOpen or self.optionsOpen or self.paused then
        self.uiConsumed = true
    end
    if self.readyDelay and self.readyDelay > 0 then
        self.readyDelay = self.readyDelay - dt
        if self.wantSpawn then
            Hud.holdPress("spawnbtn")
        end
        if self.readyDelay <= 0 then
            self.readyDelay = 0
            if self.wantSpawn and self:connected() and not self.world:isSpawned() then
                self:spawn()
            end
        end
    end
    if self.tankDelay and self.tankDelay > 0 then
        self.tankDelay = self.tankDelay - dt
        if self.pendingTankId then
            Hud.holdPress("up" .. tostring(self.pendingTankId))
        end
        if self.tankDelay <= 0 then
            self.tankDelay = 0
            local id = self.pendingTankId
            self.pendingTankId = nil
            if id then
                self:send(Encode.tankUpgrade(id, self.tankCount))
            end
        end
    end
    if self.pendingSpawn and self.world:isSpawned() then
        self.pendingSpawn = false
        self.spawnRetry = 0
        self.wantSpawn = false
    elseif self.pendingSpawn and not self.world:isSpawned() then
        self.spawnRetry = self.spawnRetry + dt
        if self.spawnRetry >= 1.0 then
            self.spawnRetry = 0
            self:spawn()
        end
    end
    local player = self.world:player()
    local mx, my = love.mouse.getPosition()
    if Hud.over(self.buttons or {}, Hud.screenToGui(mx, my)) then
        self.uiConsumed = true
    end
    self.inputAcc = self.inputAcc + dt
    if self.inputAcc >= config.inputInterval then
        self.inputAcc = 0
        if self:connected() then
            local camX, camY, fov = Render.view(self.world)
            local _, visW, visH = Render.viewMetrics(fov)
            if player then
                local flags = 0
                local locked = Console.isOpen(self) or self.treeOpen or self.optionsOpen or self.paused
                if not locked then
                    flags = Input.flags(self.uiConsumed, self:canCheat())
                    if self.autoFire then
                        flags = bit.bor(flags, Enums.InputFlags.leftclick)
                    end
                end
                local wx, wy
                if self.autoSpin and not locked then
                    local px, py = self.world:ensureWorld(player)
                    local ang = self.autoSpinAngle or 0
                    wx = px + math.cos(ang) * 1400
                    wy = py + math.sin(ang) * 1400
                else
                    wx, wy = Input.screenToWorld(mx, my, camX, camY, fov)
                end
                self:send(Encode.input(flags, wx, wy, visW, visH))
            else
                self:send(Encode.input(0, camX, camY, visW, visH))
            end
        end
        Input.clear()
    end
    self.uiConsumed = false
end

function Game:draw()
    local ok, err = pcall(Render.draw, self.world)
    if not ok then
        print("[LoveDiepClient] render: " .. tostring(err))
    end
    while love.graphics.getStackDepth() > 0 do
        love.graphics.pop()
    end
    love.graphics.origin()
    ok, err = pcall(function()
        self.buttons = Hud.draw(self)
    end)
    if not ok then
        print("[LoveDiepClient] hud: " .. tostring(err))
        self.buttons = {}
    end
    local mx, my = love.mouse.getPosition()
    Hud.syncCursor(self.buttons or {}, Hud.screenToGui(mx, my))
end

return Game
