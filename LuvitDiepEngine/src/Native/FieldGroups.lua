--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local Enums = require("../Const/Enums")

local function fill(n, v)
    local t = {}
    for i = 0, n - 1 do t[i] = v end
    return t
end

local function makeGroup(fieldNames, defaults)
    local Group = class()

    function Group:init(entity)
        self.entity = entity
        self.state = fill(#fieldNames, 0)
        self.values = {}
        for i, name in ipairs(fieldNames) do
            local def = defaults[name]
            if type(def) == "function" then
                self.values[name] = def(self)
            else
                self.values[name] = def
            end
        end
    end

    function Group:wipe()
        for i = 0, #fieldNames - 1 do
            self.state[i] = 0
        end
    end

    for i, name in ipairs(fieldNames) do
        local idx = i - 1
        Group["get_" .. name] = function(self)
            return self.values[name]
        end
        Group["set_" .. name] = function(self, value)
            if value == self.values[name] then return end
            self.state[idx] = 1
            self.entity.entityState = bit.bor(self.entity.entityState, 1)
            self.values[name] = value
        end
    end

    -- metamethods so group.flags = x works
    function Group:__index(k)
        local v = rawget(Group, k)
        if v ~= nil then return v end
        local values = rawget(self, "values")
        if values and values[k] ~= nil then
            return values[k]
        end
        return values and values[k]
    end

    function Group:__newindex(k, v)
        if k == "entity" or k == "state" or k == "values" then
            rawset(self, k, v)
            return
        end
        local setter = Group["set_" .. k]
        if setter then
            setter(self, v)
        else
            rawset(self, k, v)
        end
    end

    return Group
end

-- Scoreboard / camera tables (0-indexed)
local DirtyTable = class()

function DirtyTable:init(defaultValue, fieldId, owner, count)
    self.state = fill(count, 0)
    self.values = fill(count, defaultValue)
    self.fieldId = fieldId
    self.owner = owner
    self.count = count
end

function DirtyTable:wipe()
    for i = 0, self.count - 1 do
        self.state[i] = 0
    end
end

function DirtyTable:get(i)
    return self.values[i]
end

function DirtyTable:set(i, value)
    if value == self.values[i] then return end
    self.state[i] = 1
    self.values[i] = value
    self.owner.state[self.fieldId] = 1
    self.owner.entity.entityState = bit.bor(self.owner.entity.entityState, 1)
end

DirtyTable.__index = function(self, k)
    local v = rawget(DirtyTable, k)
    if v ~= nil then return v end
    if type(k) == "number" then
        return self.values[k]
    end
    return rawget(self, k)
end

DirtyTable.__newindex = function(self, k, v)
    if type(k) == "number" then
        DirtyTable.set(self, k, v)
    else
        rawset(self, k, v)
    end
end

local RelationsGroup = makeGroup(
    { "parent", "owner", "team" },
    { parent = false, owner = false, team = false }
)
-- false used as placeholder; we want nil. Fix defaults:
function RelationsGroup:init(entity)
    self.entity = entity
    self.state = fill(3, 0)
    self.values = { parent = nil, owner = nil, team = nil }
end

local BarrelGroup = makeGroup(
    { "flags", "reloadTime", "trapezoidDirection" },
    { flags = 0, reloadTime = 15, trapezoidDirection = 0 }
)

local PhysicsGroup = makeGroup(
    { "flags", "sides", "size", "width", "absorbtionFactor", "pushFactor" },
    { flags = 0, sides = 0, size = 0, width = 0, absorbtionFactor = 1, pushFactor = 8 }
)

local HealthGroup = makeGroup(
    { "flags", "health", "maxHealth" },
    { flags = 0, health = 1, maxHealth = 1 }
)

local ArenaGroup = class()
function ArenaGroup:init(entity)
    self.entity = entity
    self.state = fill(15, 0)
    self.values = {
        flags = 2,
        leftX = 0,
        topY = 0,
        rightX = 0,
        bottomY = 0,
        scoreboardAmount = 0,
        scoreboardNames = DirtyTable:new("", 6, self, 10),
        scoreboardScores = DirtyTable:new(0, 7, self, 10),
        scoreboardColors = DirtyTable:new(13, 8, self, 10),
        scoreboardSuffixes = DirtyTable:new("", 9, self, 10),
        scoreboardTanks = DirtyTable:new(Enums.Tank.Basic, 10, self, 10),
        leaderX = 0,
        leaderY = 0,
        playersNeeded = 1,
        ticksUntilStart = 250
    }
end
function ArenaGroup:wipe()
    for i = 0, 14 do self.state[i] = 0 end
    self.values.scoreboardNames:wipe()
    self.values.scoreboardScores:wipe()
    self.values.scoreboardColors:wipe()
    self.values.scoreboardSuffixes:wipe()
    self.values.scoreboardTanks:wipe()
end
ArenaGroup.__index = function(self, k)
    local v = rawget(ArenaGroup, k)
    if v ~= nil then return v end
    local values = rawget(self, "values")
    if values then return values[k] end
end
ArenaGroup.__newindex = function(self, k, v)
    if k == "entity" or k == "state" or k == "values" then
        rawset(self, k, v)
        return
    end
    local map = {
        flags = 0, leftX = 1, topY = 2, rightX = 3, bottomY = 4,
        scoreboardAmount = 5, leaderX = 11, leaderY = 12,
        playersNeeded = 13, ticksUntilStart = 14
    }
    local idx = map[k]
    if idx then
        if v == self.values[k] then return end
        self.state[idx] = 1
        self.entity.entityState = bit.bor(self.entity.entityState, 1)
        self.values[k] = v
    else
        rawset(self, k, v)
    end
end

local NameGroup = makeGroup(
    { "flags", "name" },
    { flags = 0, name = "" }
)

local CameraGroup = class()
function CameraGroup:init(entity)
    self.entity = entity
    self.state = fill(21, 0)
    self.values = {
        unusedClientId = 0,
        flags = 1,
        player = nil,
        FOV = 0.35,
        level = 1,
        tank = 53,
        levelbarProgress = 0,
        levelbarMax = 0,
        statsAvailable = 0,
        statNames = DirtyTable:new("", 9, self, 8),
        statLevels = DirtyTable:new(0, 10, self, 8),
        statLimits = DirtyTable:new(0, 11, self, 8),
        cameraX = 0,
        cameraY = 0,
        score = 0,
        respawnLevel = 0,
        killedBy = "",
        spawnTick = 0,
        deathTick = -1,
        tankOverride = "",
        movementSpeed = 0
    }
end
function CameraGroup:wipe()
    for i = 0, 20 do self.state[i] = 0 end
    self.values.statNames:wipe()
    self.values.statLevels:wipe()
    self.values.statLimits:wipe()
end
CameraGroup.__index = function(self, k)
    local v = rawget(CameraGroup, k)
    if v ~= nil then return v end
    local values = rawget(self, "values")
    if values then return values[k] end
end
CameraGroup.__newindex = function(self, k, v)
    if k == "entity" or k == "state" or k == "values" then
        rawset(self, k, v)
        return
    end
    local map = {
        unusedClientId = 0, flags = 1, player = 2, FOV = 3, level = 4, tank = 5,
        levelbarProgress = 6, levelbarMax = 7, statsAvailable = 8,
        cameraX = 12, cameraY = 13, score = 14, respawnLevel = 15,
        killedBy = 16, spawnTick = 17, deathTick = 18, tankOverride = 19,
        movementSpeed = 20
    }
    local idx = map[k]
    if idx then
        if v == self.values[k] then return end
        self.state[idx] = 1
        self.entity.entityState = bit.bor(self.entity.entityState, 1)
        self.values[k] = v
    else
        rawset(self, k, v)
    end
end

local PositionGroup = makeGroup(
    { "x", "y", "angle", "flags" },
    { x = 0, y = 0, angle = 0, flags = 0 }
)

local StyleGroup = makeGroup(
    { "flags", "color", "borderWidth", "opacity", "zIndex" },
    { flags = 1, color = Enums.Color.Border, borderWidth = 7.5, opacity = 1, zIndex = 0 }
)

local ScoreGroup = makeGroup(
    { "score" },
    { score = 0 }
)

local TeamGroup = makeGroup(
    { "teamColor", "mothershipX", "mothershipY", "flags" },
    { teamColor = Enums.Color.Border, mothershipX = 0, mothershipY = 0, flags = 0 }
)

return {
    DirtyTable = DirtyTable,
    RelationsGroup = RelationsGroup,
    BarrelGroup = BarrelGroup,
    PhysicsGroup = PhysicsGroup,
    HealthGroup = HealthGroup,
    ArenaGroup = ArenaGroup,
    NameGroup = NameGroup,
    CameraGroup = CameraGroup,
    PositionGroup = PositionGroup,
    StyleGroup = StyleGroup,
    ScoreGroup = ScoreGroup,
    TeamGroup = TeamGroup
}
