--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../../class")
local ObjectEntity = require("../Object")
local FieldGroups = require("../../Native/FieldGroups")
local Enums = require("../../Const/Enums")
local util = require("../../util")

local Color = Enums.Color
local PhysicsFlags = Enums.PhysicsFlags
local BarrelFlags = Enums.BarrelFlags
local Stat = Enums.Stat
local Tank = Enums.Tank
local PositionFlags = Enums.PositionFlags

local ShootCycle = class()
function ShootCycle:init(barrel)
    self.barrelEntity = barrel
    self.barrelEntity.barrelData.reloadTime = self.barrelEntity.tank.reloadTime * self.barrelEntity.definition.reload
    self.reloadTime = barrel.barrelData.values.reloadTime
    self.pos = self.reloadTime
end
function ShootCycle:tick()
    local reloadTime = self.barrelEntity.tank.reloadTime * self.barrelEntity.definition.reload
    local btype = self.barrelEntity.definition.bullet and self.barrelEntity.definition.bullet.type
    local alwaysShoot = self.barrelEntity.definition.forceFire or btype == "drone" or btype == "minion"
    if self.pos >= reloadTime then
        if not self.barrelEntity.attemptingShot and not alwaysShoot then
            self.pos = reloadTime
            return
        end
        if type(self.barrelEntity.definition.droneCount) == "number"
            and self.barrelEntity.droneCount >= self.barrelEntity.definition.droneCount then
            self.pos = reloadTime
            return
        end
    end
    if self.pos >= reloadTime * (1 + (self.barrelEntity.definition.delay or 0)) then
        self.barrelEntity.barrelData.reloadTime = reloadTime
        self.barrelEntity:shoot()
        self.pos = reloadTime * (self.barrelEntity.definition.delay or 0)
    end
    self.pos = self.pos + 1
end

local Barrel = class(ObjectEntity)

function Barrel:init(owner, barrelDefinition)
    ObjectEntity.init(self, owner.game)
    self.tank = owner
    self.definition = barrelDefinition
    self.attemptingShot = false
    self.bulletAccel = 20
    self.droneCount = 0
    self.addons = {}
    self.barrelData = FieldGroups.BarrelGroup:new(self)
    self.styleData.values.color = barrelDefinition.color or Color.Barrel
    self.physicsData.values.sides = 2
    if barrelDefinition.isTrapezoid then
        self.physicsData.values.flags = bit.bor(self.physicsData.values.flags, PhysicsFlags.isTrapezoid)
    end
    self:setParent(owner)
    self.relationsData.values.owner = owner
    self.relationsData.values.team = owner.relationsData.values.team
    local scaleFactor = self.tank.scaleFactor or 1
    if type(self.tank.getSizeFactor) == "function" then
        scaleFactor = self.tank:getSizeFactor()
    end
    local size = barrelDefinition.size * scaleFactor
    self.physicsData.values.size = size
    self.physicsData.values.width = barrelDefinition.width * scaleFactor
    self.positionData.values.angle = barrelDefinition.angle + (barrelDefinition.trapezoidDirection or 0)
    self.positionData.values.x = math.cos(barrelDefinition.angle) * (size / 2 + ((barrelDefinition.distance or 0) * scaleFactor)) - math.sin(barrelDefinition.angle) * barrelDefinition.offset * scaleFactor
    self.positionData.values.y = math.sin(barrelDefinition.angle) * (size / 2 + ((barrelDefinition.distance or 0) * scaleFactor)) + math.cos(barrelDefinition.angle) * barrelDefinition.offset * scaleFactor
    if barrelDefinition.addon then
        local BarrelAddonById = require("./BarrelAddons").BarrelAddonById
        local AddonConstructor = BarrelAddonById[barrelDefinition.addon]
        if AddonConstructor then self.addons[#self.addons + 1] = AddonConstructor:new(self) end
    end
    self.barrelData.values.trapezoidDirection = barrelDefinition.trapezoidDirection or 0
    self.shootCycle = ShootCycle:new(self)
    self:calculateStatData()
end

function Barrel:shoot()
    self.barrelData.flags = bit.bxor(self.barrelData.values.flags, BarrelFlags.hasShot)
    local scatterAngle = (math.pi / 180) * (self.definition.bullet.scatterRate or 1) * (math.random() - 0.5) * 10
    local angle = self.definition.angle + scatterAngle + self.tank.positionData.values.angle
    self.rootParent:addVelocity(angle + math.pi, self.definition.recoil * 2)
    local tankDefinition = nil
    local TankBody = require("./TankBody")
    if TankBody.isTank(self.rootParent) then tankDefinition = self.rootParent.definition end
    local projectile = nil
    local btype = self.definition.bullet.type
    if btype == "skimmer" then
        local Skimmer = require("./Projectile/Skimmer")
        local dir = self.tank.inputs:attemptingRepel() and -Skimmer.BASE_ROTATION or Skimmer.BASE_ROTATION
        projectile = Skimmer:new(self, self.tank, tankDefinition, angle, dir)
    elseif btype == "rocket" then
        local Rocket = require("./Projectile/Rocket")
        Rocket:new(self, self.tank, tankDefinition, angle)
    elseif btype == "bullet" then
        local Bullet = require("./Projectile/Bullet")
        projectile = Bullet:new(self, self.tank, tankDefinition, angle)
        local DevTank = require("../../Const/DevTankDefinitions").DevTank
        if tankDefinition and (tankDefinition.id == Tank.ArenaCloser or tankDefinition.id == DevTank.Squirrel) then
            projectile.positionData.flags = bit.bor(projectile.positionData.values.flags, PositionFlags.canMoveThroughWalls)
        end
    elseif btype == "trap" then
        projectile = require("./Projectile/Trap"):new(self, self.tank, tankDefinition, angle)
    elseif btype == "drone" then
        projectile = require("./Projectile/Drone"):new(self, self.tank, tankDefinition, angle)
    elseif btype == "necrodrone" then
        projectile = require("./Projectile/NecromancerSquare"):new(self, self.tank, tankDefinition, angle)
    elseif btype == "swarm" then
        projectile = require("./Projectile/Swarm"):new(self, self.tank, tankDefinition, angle)
    elseif btype == "minion" then
        projectile = require("./Projectile/Minion"):new(self, self.tank, tankDefinition, angle)
    elseif btype == "flame" then
        projectile = require("./Projectile/Flame"):new(self, self.tank, tankDefinition, angle)
    elseif btype == "wall" then
        local MazeWall = require("../Misc/MazeWall")
        local mx = math.floor(self.tank.inputs.mouse.x / 50 + 0.5) * 50
        local my = math.floor(self.tank.inputs.mouse.y / 50 + 0.5) * 50
        local w = MazeWall:new(self.game.arena, mx, my, 250, 250)
        projectile = w
        local timer = require("timer")
        timer.setTimeout(60 * 1000, function()
            if w.hash ~= 0 then w:delete() end
        end)
    elseif btype == "croc" then
        projectile = require("./Projectile/CrocSkimmer"):new(self, self.tank, tankDefinition, angle)
    else
        util.log("Ignoring attempt to spawn projectile of type " .. tostring(btype))
    end
    if projectile then
        if self.definition.bullet.sides then
            projectile.physicsData.values.sides = self.definition.bullet.sides
        end
        if self.definition.bullet.color then
            projectile.styleData.values.color = self.definition.bullet.color
        end
    end
end

function Barrel:calculateStatData()
    local reloadTime = self.tank.reloadTime * self.definition.reload
    if reloadTime ~= self.shootCycle.reloadTime then
        self.shootCycle.pos = self.shootCycle.pos * reloadTime / self.shootCycle.reloadTime
        self.shootCycle.reloadTime = reloadTime
        self.barrelData.reloadTime = reloadTime
    end
    local statLevels = self.tank.cameraEntity.cameraData and self.tank.cameraEntity.cameraData.values.statLevels
    local bulletSpeed = statLevels and statLevels:get(Stat.BulletSpeed) or 0
    self.bulletAccel = (20 + bulletSpeed * 3) * self.definition.bullet.speed
end

function Barrel:tick(tick)
    self.relationsData.values.team = self.tank.relationsData.values.team
    if not self.tank.rootParent.deletionAnimation then
        self.attemptingShot = self.tank.inputs:attemptingShot()
        self.shootCycle:tick()
    end
    ObjectEntity.tick(self, tick)
end

Barrel.ShootCycle = ShootCycle

return Barrel
