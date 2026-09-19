local bit = require("bit")
local class = require("src.class")
local Decode = require("src.protocol.decode")
local Enums = require("src.protocol.enums")

local World = class()

function World:init()
    self.entities = {}
    self.tick = 0
    self.camera = nil
    self.arena = nil
    self.inGame = false
    self._lastPlayer = nil
    self._lastPlayerHash = nil
    self._missingSince = nil
    self._playerKey = nil
    self._respawned = false
end

function World:clear()
    self.entities = {}
    self.camera = nil
    self.arena = nil
    self.tick = 0
    self._lastPlayer = nil
    self._lastPlayerHash = nil
    self.inGame = false
    self._missingSince = nil
    self._playerKey = nil
    self._respawned = false
end

function World:delete(id)
    local e = self.entities[id]
    if e then
        self.entities[id] = nil
        if self.camera == e then self.camera = nil end
        if self.arena == e then self.arena = nil end
        if self._lastPlayer == e then self._lastPlayer = nil end
    end
end

function World:applyUpdate(reader)
    local prevCamId = self.camera and self.camera.id
    local prevCamHash = self.camera and self.camera.hash
    local touched = {}
    local ok, err = pcall(function()
        self.tick = reader:vu()
        local nDel = reader:vu()
        if type(nDel) ~= "number" or nDel ~= nDel or nDel < 0 or nDel > 4096 then nDel = 0 end
        local saved = {}
        for _ = 1, nDel do
            if reader:remaining() <= 0 then break end
            local ident = reader:entid()
            if ident then
                local e = self.entities[ident.id]
                if e then
                    saved[ident.id] = e
                    self.entities[ident.id] = nil
                end
            end
        end
        local nCU = reader:vu()
        if type(nCU) ~= "number" or nCU ~= nCU or nCU < 0 or nCU > 4096 then nCU = 0 end
        for _ = 1, nCU do
            if reader:remaining() <= 0 then break end
            local at = reader.at
            local ident = reader:entid()
            reader.at = at
            if not ident then
                reader:entid()
                break
            end
            local existing = self.entities[ident.id] or saved[ident.id]
            if existing and ident.hash and existing.hash ~= ident.hash then
                existing = nil
            end
            local existed = existing ~= nil
            local ent, decoded = Decode.entity(reader, existing)
            if not decoded then
                if existing then
                    self.entities[existing.id] = existing
                    saved[existing.id] = nil
                    touched[existing.id] = true
                    if existing.camera then self.camera = existing end
                    if existing.arena then self.arena = existing end
                end
                break
            end
            if ent then
                self.entities[ent.id] = ent
                saved[ent.id] = nil
                touched[ent.id] = true
                if ent.camera then self.camera = ent end
                if ent.arena then self.arena = ent end
                self:noteEffects(ent, not existed)
            end
        end
        for id, e in pairs(saved) do
            if self.entities[id] == nil then
                if self.camera == e then self.camera = nil end
                if self.arena == e then self.arena = nil end
                if self._lastPlayer == e then self._lastPlayer = nil end
            end
        end
    end)
    if not ok then
        print("[LoveDiepClient] update decode error: " .. tostring(err))
    end
    if self.camera and (self.camera.id ~= prevCamId or self.camera.hash ~= prevCamHash) then
        for id, e in pairs(self.entities) do
            if not touched[id] then
                self.entities[id] = nil
                if self.camera == e then self.camera = nil end
                if self.arena == e then self.arena = nil end
                if self._lastPlayer == e then self._lastPlayer = nil end
            end
        end
        self:snapWorld()
        self._respawned = true
    end
    self:rebuildChildren()
    local prevKey = self._playerKey
    self:refreshAlive()
    local _, player = self:playerRef()
    local key = nil
    if player then
        key = tostring(player.id) .. ":" .. tostring(player.hash or "")
    end
    if key and key ~= prevKey then
        self:snapWorld()
        self._respawned = true
    end
    self._playerKey = key
end

function World:rebuildChildren()
    for _, e in pairs(self.entities) do
        e.children = {}
    end
    for _, e in pairs(self.entities) do
        local pref = e.relations and e.relations.parent
        local parent = pref and self.entities[pref.id]
        if parent and (not pref.hash or parent.hash == pref.hash) then
            parent.children[#parent.children + 1] = e
            e.parentEntity = parent
        else
            e.parentEntity = nil
        end
    end
end

local absRot = Enums.PositionFlags.absoluteRotation

function World:ensureWorld(e, visiting)
    if not e then return 0, 0, 0 end
    if e._wf == self.tick and e.worldX then
        return e.worldX, e.worldY, e.worldAngle
    end
    visiting = visiting or {}
    if visiting[e.id] then
        return e.ix or 0, e.iy or 0, e.ia or 0
    end
    visiting[e.id] = true
    local pos = e.position
    local lx = e.ix or (pos and pos.x) or 0
    local ly = e.iy or (pos and pos.y) or 0
    local la = e.ia or (pos and pos.angle) or 0
    local parent = e.parentEntity
    if not parent or not parent.position then
        e.worldX, e.worldY, e.worldAngle = lx, ly, la
        e._wf = self.tick
        return lx, ly, la
    end
    local px, py, pa = self:ensureWorld(parent, visiting)
    local flags = (pos and pos.flags) or 0
    local wx = px + lx * math.cos(pa) - ly * math.sin(pa)
    local wy = py + lx * math.sin(pa) + ly * math.cos(pa)
    local wa = (bit.band(flags, absRot) ~= 0) and la or (pa + la)
    e.worldX, e.worldY, e.worldAngle = wx, wy, wa
    e._wf = self.tick
    return wx, wy, wa
end

local function lerp(cur, target, a)
    if cur == nil or target == nil then return target end
    return cur + (target - cur) * a
end

function World:interpolate(dt)
    local a = 1 - math.exp(-dt * 22)
    local ba = 1 - math.exp(-dt * 14)
    self.tick = (self.tick or 0)
    for _, e in pairs(self.entities) do
        e._wf = nil
        local pos = e.position
        if pos then
            if e.ix == nil then
                e.ix, e.iy, e.ia = pos.x, pos.y, pos.angle
            else
                e.ix = e.ix + (pos.x - e.ix) * a
                e.iy = e.iy + (pos.y - e.iy) * a
                local d = pos.angle - e.ia
                while d > math.pi do d = d - math.pi * 2 end
                while d < -math.pi do d = d + math.pi * 2 end
                e.ia = e.ia + d * a
            end
        end
        if e.health then
            e.ih = lerp(e.ih, e.health.health, ba)
            e.imh = lerp(e.imh, e.health.maxHealth, ba)
            local maxH = e.imh or 1
            if maxH < 1e-6 then maxH = 1 end
            local ratio = (e.ih or 0) / maxH
            if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
            local lag = e._hpLag
            if lag == nil then lag = ratio end
            local prev = e._hpPrev
            if prev == nil then prev = ratio end
            if ratio > lag then
                lag = ratio
                e._hpLagWait = 0
            elseif ratio < prev - 0.0005 then
                e._hpLagWait = 0.18
            else
                local wait = e._hpLagWait or 0
                if wait > 0 then
                    e._hpLagWait = wait - dt
                else
                    lag = lag + (ratio - lag) * (1 - math.exp(-dt * 12))
                    if lag - ratio < 0.003 then lag = ratio end
                end
            end
            e._hpLag = lag
            e._hpPrev = ratio
        end
        if e.camera then
            e.ibar = lerp(e.ibar, e.camera.levelbarProgress or 0, ba)
            e.ibarMax = lerp(e.ibarMax, e.camera.levelbarMax or 1, ba)
            e.istat = e.istat or {}
            for i = 0, 7 do
                e.istat[i] = lerp(e.istat[i], e.camera.statLevels and e.camera.statLevels[i] or 0, ba)
            end
        end
        if e.score then
            e.iscore = lerp(e.iscore, e.score.score, ba)
        end
        if (e._shootAnim or 1) < 1 then
            local reload = (e.barrel and e.barrel.reloadTime) or 15
            local duration = math.max(0.06, reload / 25)
            e._shootAnim = math.min(1, e._shootAnim + dt / duration)
        end
        if (e._hitFlash or 0) > 0 then
            e._hitFlash = math.max(0, e._hitFlash - dt / 0.18)
        end
    end
end

function World:noteEffects(ent, isNew)
    if ent.barrel then
        local f = ent.barrel.flags or 0
        if not isNew and ent._shotFlags ~= nil and f ~= ent._shotFlags then
            ent._shootAnim = 0
        end
        ent._shotFlags = f
    end
    if ent.style then
        local flags = ent.style.flags or 0
        local d = bit.band(flags, Enums.StyleFlags.hasBeenDamaged)
        local noDmg = bit.band(flags, Enums.StyleFlags.hasNoDmgIndicator) ~= 0
        if not isNew and not noDmg and ent._dmgFlag ~= nil and d ~= ent._dmgFlag then
            ent._hitFlash = 1
        end
        ent._dmgFlag = d
    end
end

function World:snapEntity(e)
    if not e then return end
    local pos = e.position
    if pos then
        e.ix, e.iy, e.ia = pos.x, pos.y, pos.angle
        e.worldX, e.worldY, e.worldAngle = nil, nil, nil
        e._wf = nil
    end
end

function World:snapWorld()
    for _, e in pairs(self.entities) do
        self:snapEntity(e)
    end
end

function World:cameraValues()
    return self.camera and self.camera.camera or nil
end

function World:arenaValues()
    return self.arena and self.arena.arena or nil
end

local function refsMatch(ref, e)
    if type(ref) ~= "table" or not e or ref.id == nil then return false end
    if e.id ~= ref.id then return false end
    if ref.hash and e.hash and ref.hash ~= e.hash then return false end
    return true
end

function World:playerRef()
    local cam = self:cameraValues()
    local ref = cam and cam.player
    if type(ref) ~= "table" or ref.id == nil then return nil end
    local e = self.entities[ref.id]
    if not e then return nil end
    if e.camera or e.arena then return nil end
    if not refsMatch(ref, e) then return nil end
    return ref, e
end

local function tankAlive(e)
    if not e or e.camera or e.arena or e.barrel then return false end
    if not e.physics or not e.position then return false end
    local hp = (e.health and e.health.health) or e.ih
    if type(hp) == "number" and hp <= 0.0001 then return false end
    return true
end

function World:player()
    local _, e = self:playerRef()
    if tankAlive(e) then
        return e
    end
    return nil
end

function World:refreshAlive()
    local p = self:player()
    if p then
        self.inGame = true
        self._lastPlayer = p
        self._lastPlayerHash = p.hash
        self._missingSince = nil
        return
    end
    self.inGame = false
    self._lastPlayer = nil
    self._lastPlayerHash = nil
    self._missingSince = nil
end

function World:isSpawned()
    return self:player() ~= nil
end

function World:isWaitingStart()
    local cam = self:cameraValues()
    if not cam then return false end
    return bit.band(cam.flags or 0, Enums.CameraFlags.gameWaitingStart) ~= 0
end

function World:isDead()
    if self:isSpawned() then return false end
    local cam = self:cameraValues()
    if not cam then return false end
    if bit.band(cam.flags or 0, Enums.CameraFlags.showingDeathStats) == 0 then
        return false
    end
    local ref = cam.player
    if type(ref) ~= "table" or ref.id == nil then
        return true
    end
    local e = self.entities[ref.id]
    if not e or not refsMatch(ref, e) then
        return true
    end
    if not tankAlive(e) then
        return true
    end
    local fov = tonumber(cam.FOV) or 0
    return fov > 0.36 and fov < 0.42
end

function World:tickAlive()
    if self:player() then
        self.inGame = true
        self._missingSince = nil
        return
    end
    self.inGame = false
    self._lastPlayer = nil
    self._lastPlayerHash = nil
    self._missingSince = nil
end

return World
