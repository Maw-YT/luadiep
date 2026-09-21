local Encode = require("src.protocol.encode")
local Input = require("src.input")
local Render = require("src.render")
local Hud = require("src.ui")
local Console = require("src.ui.console")
local Settings = require("src.ui.settings")
local TankTree = require("src.ui.tanktree")
local Changelog = require("src.data.changelog")

local FIELD_MAX = {
    spawnName = 16,
    url = 256,
    password = 48
}

local FOCUS_ORDER = { "spawnName", "url", "password" }

return function(Game)
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
    if Changelog.wheel(dx, dy, gx, gy) then
        return
    end
    if not self.treeOpen then return end
    TankTree.wheel(self, dx, dy)
end
end
