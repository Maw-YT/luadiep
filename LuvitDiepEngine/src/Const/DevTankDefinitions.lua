--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local DevTank = {
    Developer = -1,
    UsainBolt = -2,
    BigBoi = -3,
    Bouncy = -4,
    Master = -5,
    Musketeer = -6,
    Squirrel = -7,
    Shotgun = -8,
    Flamethrower = -9,
    Builder = -10,
    Goodbye = -11,
    Spectator = -12,
    TheCroc = -13,
    Railgun = -14,
    Commander = -15,
    DeathRay = -16
}

local defaultStats = {
    { name = "Movement Speed", max = 9 },
    { name = "Reload", max = 9 },
    { name = "Bullet Damage", max = 9 },
    { name = "Bullet Penetration", max = 9 },
    { name = "Bullet Speed", max = 9 },
    { name = "Body Damage", max = 9 },
    { name = "Max Health", max = 9 },
    { name = "Health Regen", max = 9 }
}

local spectatorStats = {}
for i = 1, 8 do
    spectatorStats[i] = { name = defaultStats[i].name, max = 0 }
end

local function tank(partial)
    partial.upgradeMessage = partial.upgradeMessage or ""
    partial.upgrades = partial.upgrades or {}
    partial.levelRequirement = partial.levelRequirement or 45
    partial.fieldFactor = partial.fieldFactor or 1
    partial.speed = partial.speed or 1
    partial.absorbtionFactor = partial.absorbtionFactor or 1
    partial.maxHealth = partial.maxHealth or 50
    partial.borderWidth = partial.borderWidth or 15
    partial.sides = partial.sides or 1
    partial.preAddon = partial.preAddon
    partial.postAddon = partial.postAddon
    partial.visibilityRateShooting = partial.visibilityRateShooting or 0.23
    partial.visibilityRateMoving = partial.visibilityRateMoving or 0.08
    partial.invisibilityRate = partial.invisibilityRate or 0.03
    partial.flags = partial.flags or { invisibility = false, zoomAbility = false, devOnly = false }
    partial.barrels = partial.barrels or {}
    partial.stats = partial.stats or defaultStats
    return partial
end

-- Indexed so getTankById(-id) works: Developer is -1 -> [1]
local DevTankDefinitions = {
    tank({
        id = DevTank.Developer,
        name = "Developer",
        upgradeMessage = "Use your right mouse button to teleport to where your mouse is",
        barrels = {{
            angle = 0, delay = 0, size = 85, offset = 0, recoil = 2, addon = nil,
            bullet = { type = "bullet", speed = 0.5, damage = 0.5, health = 0.45, scatterRate = 0.01, lifeLength = 0.3, absorbtionFactor = 1, sizeRatio = 1 },
            reload = 0.6, width = 50, isTrapezoid = true, trapezoidDirection = math.pi
        }},
        fieldFactor = 0.75,
        speed = 1.5,
        preAddon = "spike",
        flags = { invisibility = false, zoomAbility = false, devOnly = false }
    }),
    tank({
        id = DevTank.UsainBolt,
        name = "Usain Bolt",
        upgradeMessage = "Use your right mouse button to look further in the direction you're facing",
        barrels = {
            {
                angle = math.pi, delay = 0, size = 65, offset = 0, recoil = 9, addon = nil,
                bullet = { type = "bullet", speed = 0.1, damage = 1, health = 1, scatterRate = 0.1, lifeLength = 0.5, absorbtionFactor = 1, sizeRatio = 1 },
                reload = 0.2, width = 50, isTrapezoid = true, trapezoidDirection = math.pi
            },
            {
                angle = 0, delay = 0, size = 110, offset = 0, recoil = 0.2, addon = nil,
                bullet = { type = "bullet", speed = 1.5, damage = 1.5, health = 1, scatterRate = 3, lifeLength = 1, absorbtionFactor = 1, sizeRatio = 1 },
                reload = 1.5, width = 42, isTrapezoid = false, trapezoidDirection = 0
            }
        },
        fieldFactor = 0.9,
        speed = 1.2,
        flags = { invisibility = false, zoomAbility = true, devOnly = false }
    }),
    tank({ id = DevTank.BigBoi, name = "Big Boi", barrels = {{
        angle = 0, delay = 0, size = 95, offset = 0, recoil = 2, addon = nil,
        bullet = { type = "bullet", speed = 0.7, damage = 1.5, health = 1.5, scatterRate = 1, lifeLength = 1, absorbtionFactor = 1, sizeRatio = 1 },
        reload = 1, width = 70, isTrapezoid = false, trapezoidDirection = 0
    }}, speed = 0.8 }),
    tank({ id = DevTank.Bouncy, name = "Bouncy", barrels = {{
        angle = 0, delay = 0, size = 60, offset = 0, recoil = 0, addon = "trapLauncher",
        bullet = { type = "trap", speed = 2, damage = 1, health = 2, scatterRate = 1, lifeLength = 8, absorbtionFactor = 1, sizeRatio = 0.8 },
        reload = 0.6, width = 42, isTrapezoid = false, trapezoidDirection = 0
    }} }),
    tank({ id = DevTank.Master, name = "Master", barrels = {{
        angle = 0, delay = 0, size = 70, offset = 0, recoil = 1, addon = nil, droneCount = 8, canControlDrones = true,
        bullet = { type = "drone", speed = 0.8, damage = 0.7, health = 2, scatterRate = 1, lifeLength = -1, absorbtionFactor = 1, sizeRatio = 0.8 },
        reload = 0.25, width = 42, isTrapezoid = true, trapezoidDirection = 0
    }} }),
    tank({ id = DevTank.Musketeer, name = "Musketeer", barrels = {{
        angle = 0, delay = 0, size = 95, offset = 0, recoil = 0.2, addon = nil,
        bullet = { type = "bullet", speed = 1.5, damage = 0.6, health = 0.6, scatterRate = 0.3, lifeLength = 1, absorbtionFactor = 1, sizeRatio = 0.7 },
        reload = 0.5, width = 32, isTrapezoid = false, trapezoidDirection = 0
    }} }),
    tank({ id = DevTank.Squirrel, name = "Squirrel", barrels = {{
        angle = 0, delay = 0, size = 95, offset = 0, recoil = 1, addon = nil,
        bullet = { type = "bullet", speed = 1, damage = 1, health = 1, scatterRate = 1, lifeLength = 1, absorbtionFactor = 1, sizeRatio = 1 },
        reload = 1, width = 42, isTrapezoid = false, trapezoidDirection = 0
    }}, flags = { invisibility = false, zoomAbility = false, devOnly = false } }),
    tank({ id = DevTank.Shotgun, name = "Shotgun", barrels = {{
        angle = 0, delay = 0, size = 90, offset = 0, recoil = 3, addon = nil,
        bullet = { type = "bullet", speed = 1, damage = 0.4, health = 0.4, scatterRate = 3, lifeLength = 0.6, absorbtionFactor = 1, sizeRatio = 0.7 },
        reload = 2, width = 55, isTrapezoid = true, trapezoidDirection = 0
    }} }),
    tank({ id = DevTank.Flamethrower, name = "Flamethrower", barrels = {{
        angle = 0, delay = 0, size = 85, offset = 0, recoil = 0.2, addon = nil,
        bullet = { type = "flame", speed = 1, damage = 0.3, health = 1, scatterRate = 2, lifeLength = 1, absorbtionFactor = 0, sizeRatio = 1 },
        reload = 0.15, width = 42, isTrapezoid = true, trapezoidDirection = 0
    }} }),
    tank({ id = DevTank.Builder, name = "Builder", barrels = {{
        angle = 0, delay = 0, size = 80, offset = 0, recoil = 0, addon = nil,
        bullet = { type = "wall", speed = 0, damage = 0, health = 1, scatterRate = 0, lifeLength = 1, absorbtionFactor = 0, sizeRatio = 1 },
        reload = 2, width = 42, isTrapezoid = false, trapezoidDirection = 0
    }} }),
    tank({ id = DevTank.Goodbye, name = "Goodbye", barrels = {{
        angle = 0, delay = 0, size = 80, offset = 0, recoil = 20, addon = nil,
        bullet = { type = "bullet", speed = 0.2, damage = 10, health = 10, scatterRate = 0.1, lifeLength = 0.5, absorbtionFactor = 0, sizeRatio = 2 },
        reload = 4, width = 71, isTrapezoid = false, trapezoidDirection = 0
    }} }),
    tank({
        id = DevTank.Spectator,
        name = "Spectator",
        levelRequirement = 0,
        flags = { invisibility = true, zoomAbility = false, devOnly = true },
        visibilityRateShooting = 0,
        visibilityRateMoving = 0,
        invisibilityRate = 1,
        fieldFactor = 0.3,
        absorbtionFactor = 0,
        speed = 3,
        sides = 0,
        barrels = {},
        stats = spectatorStats
    }),
    tank({ id = DevTank.TheCroc, name = "The Croc", barrels = {{
        angle = 0, delay = 0, size = 95, offset = 0, recoil = 1, addon = nil,
        bullet = { type = "croc", speed = 0.5, damage = 1, health = 2, scatterRate = 0.1, lifeLength = 1.5, absorbtionFactor = 0.1, sizeRatio = 1 },
        reload = 3, width = 42, isTrapezoid = false, trapezoidDirection = 0
    }}, preAddon = "pronounced" }),
    tank({ id = DevTank.Railgun, name = "Railgun", barrels = {{
        angle = 0, delay = 0, size = 130, offset = 0, recoil = 3, addon = nil,
        bullet = { type = "bullet", speed = 2.5, damage = 3, health = 0.5, scatterRate = 0.01, lifeLength = 1, absorbtionFactor = 0, sizeRatio = 0.8 },
        reload = 4, width = 25, isTrapezoid = false, trapezoidDirection = 0
    }}, fieldFactor = 0.75 }),
    tank({ id = DevTank.Commander, name = "Commander", barrels = {{
        angle = 0, delay = 0, size = 70, offset = 0, recoil = 0.5, addon = nil, droneCount = 12, canControlDrones = true,
        bullet = { type = "minion", speed = 0.8, damage = 0.5, health = 2, scatterRate = 1, lifeLength = -1, absorbtionFactor = 1, sizeRatio = 1 },
        reload = 0.5, width = 42, isTrapezoid = true, trapezoidDirection = 0
    }} }),
    tank({
        id = DevTank.DeathRay,
        name = "Death Ray",
        upgradeMessage = "Hold fire to melt anything in a straight line",
        barrels = {{
            angle = 0, delay = 0, size = 145, offset = 0, recoil = 5, addon = nil,
            bullet = { type = "deathray", speed = 1, damage = 6, health = 8, scatterRate = 0, lifeLength = 0.22, absorbtionFactor = 0, sizeRatio = 0.85 },
            reload = 1.8, width = 34, isTrapezoid = true, trapezoidDirection = math.pi
        }},
        fieldFactor = 0.8,
        speed = 0.95,
        preAddon = "pronounced"
    })
}

DevTankDefinitions.DevTank = DevTank

return DevTankDefinitions
