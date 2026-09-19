--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local ObjectEntity = require("../Object")
local Enums = require("../../Const/Enums")

local Color = Enums.Color
local PhysicsFlags = Enums.PhysicsFlags

local BarrelAddon = class()
function BarrelAddon:init(owner)
    self.owner = owner
    self.game = owner.game
end

local TrapLauncher = class(ObjectEntity)
function TrapLauncher:init(barrel)
    ObjectEntity.init(self, barrel.game)
    self.barrelEntity = barrel
    self:setParent(barrel)
    self.relationsData.values.team = barrel
    self.physicsData.values.flags = bit.bor(PhysicsFlags.isTrapezoid, PhysicsFlags.doChildrenCollision)
    self.styleData.values.color = Color.Barrel
    self.physicsData.values.sides = 2
    self.physicsData.values.width = barrel.physicsData.values.width
    self.physicsData.values.size = barrel.physicsData.values.width * (20 / 42)
    self.positionData.values.x = (barrel.physicsData.values.size + self.physicsData.values.size) / 2
end
function TrapLauncher:resize()
    self.physicsData.sides = 2
    self.physicsData.width = self.barrelEntity.physicsData.values.width
    self.physicsData.size = self.barrelEntity.physicsData.values.width * (20 / 42)
    self.positionData.x = (self.barrelEntity.physicsData.values.size + self.physicsData.values.size) / 2
end
function TrapLauncher:tick(tick)
    ObjectEntity.tick(self, tick)
    self:resize()
end

local TrapLauncherAddon = class(BarrelAddon)
function TrapLauncherAddon:init(owner)
    BarrelAddon.init(self, owner)
    self.launcherEntity = TrapLauncher:new(owner)
end

local PurpleBarrelAddon = class(BarrelAddon)
function PurpleBarrelAddon:init(owner)
    BarrelAddon.init(self, owner)
    owner.styleData.color = Enums.Color.TeamPurple
end

return {
    BarrelAddon = BarrelAddon,
    TrapLauncher = TrapLauncher,
    TrapLauncherAddon = TrapLauncherAddon,
    BarrelAddonById = {
        trapLauncher = TrapLauncherAddon,
        purplebarrel = PurpleBarrelAddon
    }
}
