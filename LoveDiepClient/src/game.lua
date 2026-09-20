local bit = require("bit")
local class = require("src.class")
local config = require("src.config")
local json = require("src.json")
local WebSocket = require("src.net.websocket")
local Url = require("src.net.url")
local Reader = require("src.coder.reader")
local Encode = require("src.protocol.encode")
local Enums = require("src.protocol.enums")
local World = require("src.world")
local Input = require("src.input")
local Render = require("src.render")
local Hud = require("src.hud")
local Console = require("src.console")
local Settings = require("src.settings")
local TankTree = require("src.tanktree")
local Achievements = require("src.achievements")

local GAMEMODES = {
    { id = "ffa", label = "FFA" },
    { id = "sandbox", label = "Sandbox" }
}

local FIELD_MAX = {
    spawnName = 16,
    url = 256,
    password = 48
}

local FOCUS_ORDER = { "spawnName", "url", "password" }

local Game = class()

local function loadTanks()
    local byId = {}
    local count = 0
    local raw = love.filesystem.read("assets/tanks.json")
    if not raw then return byId, 1 end
    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= "table" then return byId, 1 end
    for i = 1, #parsed do
        local def = parsed[i]
        if type(def) == "table" and def ~= json.null then
            local id = def.id
            if id == nil then id = i - 1 end
            byId[id] = def
            count = count + 1
        end
    end
    if count < 1 then count = 1 end
    return byId, count
end

function Game:init()
    self.tanksById, self.tankCount = loadTanks()
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
    self.modes = GAMEMODES
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
    Render.setStyle(Settings.style)
    Render.setInnerShadow(Settings.innerShadow)
    self.password = Settings.devPassword or ""
    Console.ensure(self)
end

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
    local modes = self.modes or GAMEMODES
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
    local idx = 1
    for i = 1, #GAMEMODES do
        if GAMEMODES[i].id == self.gamemode then
            idx = i
            break
        end
    end
    idx = ((idx - 1 + dir) % #GAMEMODES) + 1
    self:selectGamemode(GAMEMODES[idx].id)
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
                self:send(Encode.input(flags, wx, wy))
            else
                self:send(Encode.input(0, camX, camY))
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

function Game:focusField(key)
    self.focus = key
    local v = self[key]
    if type(v) == "string" then
        self.caret = #v
        self._caretFocus = key
    end
end

function Game:fieldCaret()
    local focus = self.focus or "spawnName"
    local v = (type(self[focus]) == "string") and self[focus] or ""
    if self._caretFocus ~= focus then
        self.caret = #v
        self._caretFocus = focus
    end
    local caret = self.caret or #v
    if caret < 0 then caret = 0 end
    if caret > #v then caret = #v end
    self.caret = caret
    return focus, v, caret
end

function Game:textinput(text)
    if self.treeOpen or self.optionsOpen or self.paused then
        return
    end
    if Console.textinput(self, text) then
        return
    end
    if self.world:isSpawned() or self:showingDeath() or self.world:isWaitingStart() then
        return
    end
    local focus, v, caret = self:fieldCaret()
    if not FIELD_MAX[focus] then
        return
    end
    local maxn = FIELD_MAX[focus] or 48
    local room = maxn - #v
    if room <= 0 then return end
    if #text > room then
        text = text:sub(1, room)
    end
    self[focus] = v:sub(1, caret) .. text .. v:sub(caret + 1)
    self.caret = caret + #text
    if focus == "password" then
        self:persistPassword()
    end
end

function Game:toggleAutoFire()
    self.autoFire = not self.autoFire
    if self.autoFire then
        self:notify("Auto Fire ON", 0x43FF91, 1800)
    else
        self:notify("Auto Fire OFF", 0xBBBBBB, 1800)
    end
end

function Game:toggleAutoSpin()
    self.autoSpin = not self.autoSpin
    if self.autoSpin then
        local player = self.world:player()
        if player then
            local camX, camY, fov = Render.view(self.world)
            local mx, my = love.mouse.getPosition()
            local wx, wy = Input.screenToWorld(mx, my, camX, camY, fov)
            local px, py = self.world:ensureWorld(player)
            self.autoSpinAngle = math.atan2(wy - py, wx - px)
        end
        self:notify("Auto Spin ON", 0x43FF91, 1800)
    else
        self:notify("Auto Spin OFF", 0xBBBBBB, 1800)
    end
end

function Game:toggleFullscreen()
    local fs = love.window.getFullscreen()
    if fs then
        love.window.setFullscreen(false)
    else
        love.window.setFullscreen(true, "desktop")
    end
end

function Game:keypressed(key, isrepeat)
    if key == "f11" then
        if not isrepeat then
            self:toggleFullscreen()
        end
        return
    end
    if (key == "return" or key == "kpenter" or key == "enter")
        and (love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")) then
        if not isrepeat then
            self:toggleFullscreen()
        end
        return
    end
    if isrepeat and (key == "return" or key == "kpenter" or key == "enter") then
        return
    end
    if not isrepeat and key == "escape" then
        if self.styleMenuOpen then
            self.styleMenuOpen = false
            return
        end
        if self.optionsOpen then
            self.optionsOpen = false
            return
        end
        if self.treeOpen then
            self.treeOpen = false
            return
        end
        if Console.isOpen(self) then
            Console.toggle(self)
            return
        end
        if self.paused then
            self:resume()
            return
        end
        if self:inMatch() then
            self:pause()
            return
        end
        love.event.quit()
        return
    end
    if Console.keypressed(self, key, isrepeat) then
        return
    end
    if not isrepeat and key == "y" and not self.paused then
        local typing = false
        if not self.world:isSpawned() and not self:showingDeath() and not self.world:isWaitingStart() then
            local focus = self.focus or "spawnName"
            typing = FIELD_MAX[focus] ~= nil
        end
        if not typing then
            TankTree.toggle(self)
            return
        end
    end
    if self.treeOpen then
        TankTree.keypressed(self, key)
        return
    end
    if self.paused then
        return
    end
    if not isrepeat and self.world:isSpawned() and not self.optionsOpen then
        if key == "e" then
            self:toggleAutoFire()
            return
        elseif key == "c" then
            self:toggleAutoSpin()
            return
        end
    end
    Input.keypressed(key)
    if self.world:isSpawned() or self.world:isWaitingStart() then
        return
    end
    if self:showingDeath() then
        if key == "return" or key == "kpenter" or key == "enter" then
            self:send(Encode.toRespawn())
        end
        return
    end
    if key == "tab" then
        local cur = 1
        for i = 1, #FOCUS_ORDER do
            if FOCUS_ORDER[i] == self.focus then
                cur = i
                break
            end
        end
        self.focus = FOCUS_ORDER[(cur % #FOCUS_ORDER) + 1]
        self:fieldCaret()
    elseif key == "left" or key == "right" then
        local focus, v, caret = self:fieldCaret()
        if FIELD_MAX[focus] then
            if key == "left" then
                self.caret = math.max(0, caret - 1)
            else
                self.caret = math.min(#v, caret + 1)
            end
        elseif focus == "gamemode" then
            self:cycleGamemode(key == "left" and -1 or 1)
        end
    elseif key == "backspace" then
        local focus, v, caret = self:fieldCaret()
        if FIELD_MAX[focus] and caret > 0 then
            self[focus] = v:sub(1, caret - 1) .. v:sub(caret + 1)
            self.caret = caret - 1
            if focus == "password" then
                self:persistPassword()
            end
        end
    elseif key == "delete" then
        local focus, v, caret = self:fieldCaret()
        if FIELD_MAX[focus] and caret < #v then
            self[focus] = v:sub(1, caret) .. v:sub(caret + 2)
            if focus == "password" then
                self:persistPassword()
            end
        end
    elseif key == "return" or key == "kpenter" or key == "enter" then
        Hud.press("spawnbtn")
        self:play()
    end
end

function Game:mousepressed(x, y, button)
    local gx, gy = Hud.screenToGui(x, y)
    if TankTree.mousepressed(self, gx, gy, button) then
        self.uiConsumed = true
        return
    end
    if button ~= 1 then return end
    if Hud.hit(self.buttons or {}, gx, gy) then
        self.uiConsumed = true
    end
end

function Game:mousemoved(x, y)
    local gx, gy = Hud.screenToGui(x, y)
    TankTree.mousemoved(self, gx, gy)
    if self.hudScaleDrag then
        if love.mouse.isDown(1) then
            Settings.setHudScaleFromBar(gx, self._hudScaleBar, true)
        else
            self.hudScaleDrag = false
            Settings.save()
        end
    end
    if self.innerShadowDrag then
        if love.mouse.isDown(1) then
            Settings.setInnerShadowFromBar(gx, self._innerShadowBar, true)
            Render.setInnerShadow(Settings.innerShadow)
        else
            self.innerShadowDrag = false
            Settings.save()
        end
    end
end

function Game:mousereleased(x, y, button)
    local gx, gy = Hud.screenToGui(x, y)
    TankTree.mousereleased(self, gx, gy, button)
    if button == 1 and self.hudScaleDrag then
        Settings.setHudScaleFromBar(gx, self._hudScaleBar)
        self.hudScaleDrag = false
    end
    if button == 1 and self.innerShadowDrag then
        Settings.setInnerShadowFromBar(gx, self._innerShadowBar)
        Render.setInnerShadow(Settings.innerShadow)
        self.innerShadowDrag = false
    end
end

function Game:wheelmoved(dx, dy)
    local gx, gy = Hud.screenToGui(love.mouse.getPosition())
    if Console.wheel(self, dx, dy, gx, gy) then
        return
    end
    if not self.treeOpen then return end
    TankTree.wheel(self, dx, dy)
end

return Game
