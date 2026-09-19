--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local config = require("../config")

local Enums = {}

Enums.Color = {
    Border = 0,
    Barrel = 1,
    Tank = 2,
    TeamBlue = 3,
    TeamRed = 4,
    TeamPurple = 5,
    TeamGreen = 6,
    Shiny = 7,
    EnemySquare = 8,
    EnemyTriangle = 9,
    EnemyPentagon = 10,
    EnemyCrasher = 11,
    Neutral = 12,
    ScoreboardBar = 13,
    Box = 14,
    EnemyTank = 15,
    NecromancerSquare = 16,
    Fallen = 17,
    kMaxColors = 18
}

Enums.ColorsHexCode = {
    [0] = 0x555555,
    [1] = 0x999999,
    [2] = 0x00B2E1,
    [3] = 0x00B2E1,
    [4] = 0xF14E54,
    [5] = 0xBF7FF5,
    [6] = 0x00E16E,
    [7] = 0x8AFF69,
    [8] = 0xFFE869,
    [9] = 0xFC7677,
    [10] = 0x768DFC,
    [11] = 0xF177DD,
    [12] = 0xFFE869,
    [13] = 0x43FF91,
    [14] = 0xBBBBBB,
    [15] = 0xF14E54,
    [16] = 0xFCC376,
    [17] = 0xC0C0C0,
    [18] = 0x000000
}

Enums.Tank = {
    Basic = 0,
    Twin = 1,
    Triplet = 2,
    TripleShot = 3,
    QuadTank = 4,
    OctoTank = 5,
    Sniper = 6,
    MachineGun = 7,
    FlankGuard = 8,
    TriAngle = 9,
    Destroyer = 10,
    Overseer = 11,
    Overlord = 12,
    TwinFlank = 13,
    PentaShot = 14,
    Assassin = 15,
    ArenaCloser = 16,
    Necromancer = 17,
    TripleTwin = 18,
    Hunter = 19,
    Gunner = 20,
    Stalker = 21,
    Ranger = 22,
    Booster = 23,
    Fighter = 24,
    Hybrid = 25,
    Manager = 26,
    Mothership = 27,
    Predator = 28,
    Sprayer = 29,
    Trapper = 31,
    GunnerTrapper = 32,
    Overtrapper = 33,
    MegaTrapper = 34,
    TriTrapper = 35,
    Smasher = 36,
    Landmine = 37,
    AutoGunner = 39,
    Auto5 = 40,
    Auto3 = 41,
    SpreadShot = 42,
    Streamliner = 43,
    AutoTrapper = 44,
    DominatorD = 45,
    DominatorG = 46,
    DominatorT = 47,
    Battleship = 48,
    Annihilator = 49,
    AutoSmasher = 50,
    Spike = 51,
    Factory = 52,
    Skimmer = 54,
    Rocketeer = 55
}

Enums.Stat = {
    MovementSpeed = 0,
    Reload = 1,
    BulletDamage = 2,
    BulletPenetration = 3,
    BulletSpeed = 4,
    BodyDamage = 5,
    MaxHealth = 6,
    HealthRegen = 7
}

Enums.StatCount = 8

Enums.ServerBound = {
    Init = 0x0,
    Input = 0x1,
    Spawn = 0x2,
    StatUpgrade = 0x3,
    TankUpgrade = 0x4,
    Ping = 0x5,
    TCPInit = 0x6,
    ExtensionFound = 0x7,
    ToRespawn = 0x8,
    TakeTank = 0x9
}

Enums.ClientBound = {
    Update = 0x0,
    OutdatedClient = 0x1,
    Compressed = 0x2,
    Notification = 0x3,
    ServerInfo = 0x4,
    Ping = 0x5,
    PartyCode = 0x6,
    Accept = 0x7,
    Achievement = 0x8,
    InvalidParty = 0x9,
    PlayerCount = 0xA,
    ProofOfWork = 0xB
}

Enums.InputFlags = {
    leftclick = bit.lshift(1, 0),
    up = bit.lshift(1, 1),
    left = bit.lshift(1, 2),
    down = bit.lshift(1, 3),
    right = bit.lshift(1, 4),
    godmode = bit.lshift(1, 5),
    suicide = bit.lshift(1, 6),
    rightclick = bit.lshift(1, 7),
    levelup = bit.lshift(1, 8),
    gamepad = bit.lshift(1, 9),
    switchtank = bit.lshift(1, 10),
    adblock = bit.lshift(1, 11)
}

Enums.ArenaFlags = {
    noJoining = bit.lshift(1, 0),
    showsLeaderArrow = bit.lshift(1, 1),
    hiddenScores = bit.lshift(1, 2),
    gameReadyStart = bit.lshift(1, 3),
    canUseCheats = bit.lshift(1, 4)
}

Enums.TeamFlags = {
    hasMothership = bit.lshift(1, 0)
}

Enums.CameraFlags = {
    usesCameraCoords = bit.lshift(1, 0),
    showingDeathStats = bit.lshift(1, 1),
    gameWaitingStart = bit.lshift(1, 2)
}

Enums.StyleFlags = {
    isVisible = bit.lshift(1, 0),
    hasBeenDamaged = bit.lshift(1, 1),
    isFlashing = bit.lshift(1, 2),
    renderFirst = bit.lshift(1, 3),
    isStar = bit.lshift(1, 4),
    isCachable = bit.lshift(1, 5),
    showsAboveParent = bit.lshift(1, 6),
    hasNoDmgIndicator = bit.lshift(1, 7)
}

Enums.PositionFlags = {
    absoluteRotation = bit.lshift(1, 0),
    canMoveThroughWalls = bit.lshift(1, 1)
}

Enums.PhysicsFlags = {
    isTrapezoid = bit.lshift(1, 0),
    showsOnMap = bit.lshift(1, 1),
    doChildrenCollision = bit.lshift(1, 2),
    noOwnTeamCollision = bit.lshift(1, 3),
    isSolidWall = bit.lshift(1, 4),
    onlySameOwnerCollision = bit.lshift(1, 5),
    isBase = bit.lshift(1, 6),
    _unknown1 = bit.lshift(1, 7),
    canEscapeArena = bit.lshift(1, 8)
}

Enums.BarrelFlags = {
    hasShot = bit.lshift(1, 0)
}

Enums.HealthFlags = {
    hiddenHealthbar = bit.lshift(1, 0)
}

Enums.NameFlags = {
    hiddenName = bit.lshift(1, 0),
    highlightedName = bit.lshift(1, 1)
}

Enums.EntityTags = {
    isShape = bit.lshift(1, 0),
    isTank = bit.lshift(1, 1),
    isDominator = bit.lshift(1, 2),
    isBoss = bit.lshift(1, 3),
    isShiny = bit.lshift(1, 4)
}

Enums.EntityStateFlags = {
    needsUpdate = bit.lshift(1, 0),
    needsCreate = bit.lshift(1, 1),
    needsDelete = bit.lshift(1, 2)
}

local maxPlayerLevel = config.maxPlayerLevel
Enums.levelToScoreTable = {}
for i = 0, maxPlayerLevel - 1 do
    Enums.levelToScoreTable[i] = 0
end

for i = 1, maxPlayerLevel - 1 do
    Enums.levelToScoreTable[i] = Enums.levelToScoreTable[i - 1]
        + (40 / 9 * (1.06 ^ (i - 1)) * math.min(31, i))
end

function Enums.levelToScore(level)
    if level >= maxPlayerLevel then
        return Enums.levelToScoreTable[maxPlayerLevel - 1]
    end
    if level <= 0 then
        return 0
    end
    return Enums.levelToScoreTable[level - 1]
end

return Enums
