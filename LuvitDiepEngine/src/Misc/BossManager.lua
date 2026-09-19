--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local config = require("../config")
local util = require("../util")

local Guardian = require("../Entity/Boss/Guardian")
local Summoner = require("../Entity/Boss/Summoner")
local FallenOverlord = require("../Entity/Boss/FallenOverlord")
local FallenBooster = require("../Entity/Boss/FallenBooster")
local Defender = require("../Entity/Boss/Defender")

local BossManager = class()

function BossManager:init(arena)
    self.arena = arena
    self.boss = nil
    self.bossClasses = { Guardian, Summoner, FallenOverlord, FallenBooster, Defender }
end

function BossManager:findBossSpawnLocation()
    return self.arena:findSpawnLocation(self.arena.width / 2, self.arena.height / 2)
end

function BossManager:spawnBoss()
    if #self.bossClasses == 0 then return end
    local TBoss = util.randomFrom(self.bossClasses)
    local boss = TBoss:new(self.arena.game)
    self.boss = boss

    local pos = self:findBossSpawnLocation()
    boss.positionData.values.x = pos.x
    boss.positionData.values.y = pos.y

    local manager = self
    local originalDelete = boss.delete
    function boss:delete()
        originalDelete(self)
        if manager.boss == self then
            manager.boss = nil
        end
    end
end

function BossManager:tick(tick)
    if tick >= 1 and (tick % config.bossSpawningInterval) == 0 and not self.boss then
        self:spawnBoss()
    end
end

return BossManager
