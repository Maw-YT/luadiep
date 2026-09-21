local bit = require("bit")

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
    Fallen = 17
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
    isBeam = bit.lshift(1, 7),
    canEscapeArena = bit.lshift(1, 8)
}

Enums.HealthFlags = {
    hiddenHealthbar = bit.lshift(1, 0)
}

Enums.BarrelFlags = {
    hasShot = bit.lshift(1, 0)
}

Enums.NameFlags = {
    hiddenName = bit.lshift(1, 0),
    highlightedName = bit.lshift(1, 1)
}

Enums.CameraFlags = {
    usesCameraCoords = bit.lshift(1, 0),
    showingDeathStats = bit.lshift(1, 1),
    gameWaitingStart = bit.lshift(1, 2)
}

Enums.ArenaFlags = {
    noJoining = bit.lshift(1, 0),
    showsLeaderArrow = bit.lshift(1, 1),
    hiddenScores = bit.lshift(1, 2),
    gameReadyStart = bit.lshift(1, 3),
    canUseCheats = bit.lshift(1, 4)
}

Enums.GroupId = {
    [0] = "relations",
    [2] = "barrel",
    [3] = "physics",
    [4] = "health",
    [7] = "arena",
    [8] = "name",
    [9] = "camera",
    [10] = "position",
    [11] = "style",
    [13] = "score",
    [14] = "team"
}

return Enums
