--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")
local ShapeManager = require("../Misc/ShapeManager")
local Enums = require("../Const/Enums")

local SandboxShapeManager = class(ShapeManager)
function SandboxShapeManager:wantedShapes()
    local i = 0
    for client in pairs(self.game.clients) do
        if client.camera then i = i + 1 end
    end
    return math.floor(i * 12.5)
end

local SandboxArena = class(ArenaEntity)
SandboxArena.GAMEMODE_ID = "sandbox"

function SandboxArena:init(game)
    ArenaEntity.init(self, game)
    self.shapes = SandboxShapeManager:new(self)
    self.arenaData.values.flags = bit.bor(self.arenaData.values.flags, Enums.ArenaFlags.canUseCheats)
    self.state = ArenaEntity.ArenaState.OPEN
    self.game.enableAchievements = false
    self:setSandboxArenaSize(0)
end

function SandboxArena:setSandboxArenaSize(playerCount)
    local arenaSize = math.floor(25 * math.sqrt(math.max(playerCount, 1))) * 100
    self:updateBounds(arenaSize, arenaSize)
end

function SandboxArena:tick(tick)
    self:setSandboxArenaSize(self.game.clients.size)
    ArenaEntity.tick(self, tick)
end

return SandboxArena
