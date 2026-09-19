--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local Enums = require("../Const/Enums")
local Color = Enums.Color

local function resolveColor(camera, entity)
    local color = entity.styleData.values.color
    if color == Color.Tank then
        local player = camera.cameraData.values.player
        local sameTeam = entity.relationsData
            and player
            and player.relationsData
            and entity.relationsData.values.team == player.relationsData.values.team
        if not sameTeam then
            return Color.EnemyTank
        end
    end
    return color
end

local function compileCreation(camera, w, entity)
    w:entid(entity):u8(1)

    local hasRelations = entity.relationsData ~= nil
    local hasBarrel = entity.barrelData ~= nil
    local hasPhysics = entity.physicsData ~= nil
    local hasHealth = entity.healthData ~= nil
    local hasArena = entity.arenaData ~= nil
    local hasName = entity.nameData ~= nil
    local hasCamera = entity.cameraData ~= nil
    local hasPosition = entity.positionData ~= nil
    local hasStyle = entity.styleData ~= nil
    local hasScore = entity.scoreData ~= nil
    local hasTeam = entity.teamData ~= nil

    local at = -1
    if hasRelations then w:u8(bit.bxor(0 - at, 1)); at = 0 end
    if hasBarrel then w:u8(bit.bxor(2 - at, 1)); at = 2 end
    if hasPhysics then w:u8(bit.bxor(3 - at, 1)); at = 3 end
    if hasHealth then w:u8(bit.bxor(4 - at, 1)); at = 4 end
    if hasArena then w:u8(bit.bxor(7 - at, 1)); at = 7 end
    if hasName then w:u8(bit.bxor(8 - at, 1)); at = 8 end
    if hasCamera then w:u8(bit.bxor(9 - at, 1)); at = 9 end
    if hasPosition then w:u8(bit.bxor(10 - at, 1)); at = 10 end
    if hasStyle then w:u8(bit.bxor(11 - at, 1)); at = 11 end
    if hasScore then w:u8(bit.bxor(13 - at, 1)); at = 13 end
    if hasTeam then w:u8(bit.bxor(14 - at, 1)); at = 14 end
    w:u8(1)

    if hasPosition then w:vi(entity.positionData.values.y) end
    if hasPosition then w:vi(entity.positionData.values.x) end
    if hasPosition then w:float64Precision(entity.positionData.values.angle) end
    if hasPhysics then w:float(entity.physicsData.values.size) end
    if hasCamera then w:entid(entity.cameraData.values.player) end
    if hasArena then w:vu(entity.arenaData.values.flags) end
    if hasStyle then w:vu(resolveColor(camera, entity)) end
    if hasArena then
        for i = 0, 9 do w:vu(entity.arenaData.values.scoreboardColors:get(i)) end
    end
    if hasCamera then w:stringNT(entity.cameraData.values.killedBy) end
    if hasArena then w:vi(entity.arenaData.values.playersNeeded) end
    if hasPhysics then w:vu(entity.physicsData.values.sides) end
    if hasTeam then w:vu(entity.teamData.values.flags) end
    if hasHealth then w:vu(entity.healthData.values.flags) end
    if hasArena then
        for i = 0, 9 do w:vi(entity.arenaData.values.scoreboardTanks:get(i)) end
    end
    if hasCamera then w:vi(entity.cameraData.values.respawnLevel) end
    if hasCamera then w:float(entity.cameraData.values.levelbarProgress) end
    if hasCamera then w:vi(entity.cameraData.values.spawnTick) end
    if hasPhysics then w:float(entity.physicsData.values.absorbtionFactor) end
    if hasArena then w:float(entity.arenaData.values.leaderX) end
    if hasHealth then w:float(entity.healthData.values.maxHealth) end
    if hasStyle then w:vu(entity.styleData.values.flags) end
    if hasBarrel then w:float(entity.barrelData.values.trapezoidDirection) end
    if hasPosition then w:vu(entity.positionData.values.flags) end
    if hasArena then
        for i = 0, 9 do w:stringNT(entity.arenaData.values.scoreboardNames:get(i)) end
    end
    if hasCamera then w:float(entity.cameraData.values.score) end
    if hasTeam then w:float(entity.teamData.values.mothershipY) end
    if hasArena then
        for i = 0, 9 do w:stringNT(entity.arenaData.values.scoreboardSuffixes:get(i)) end
    end
    if hasName then w:vu(entity.nameData.values.flags) end
    if hasCamera then w:float(entity.cameraData.values.movementSpeed) end
    if hasArena then w:float(entity.arenaData.values.leaderY) end
    if hasArena then w:float(entity.arenaData.values.bottomY) end
    if hasRelations then w:entid(entity.relationsData.values.team) end
    if hasCamera then w:vi(entity.cameraData.values.level) end
    if hasTeam then w:vu(entity.teamData.values.teamColor) end
    if hasCamera then w:float(entity.cameraData.values.FOV) end
    if hasCamera then
        for i = 0, 7 do w:vi(entity.cameraData.values.statLimits:get(i)) end
    end
    if hasArena then w:float(entity.arenaData.values.leftX) end
    if hasArena then
        for i = 0, 9 do w:float(entity.arenaData.values.scoreboardScores:get(i)) end
    end
    if hasCamera then
        for i = 0, 7 do w:vi(entity.cameraData.values.statLevels:get(i)) end
    end
    if hasCamera then w:stringNT(entity.cameraData.values.tankOverride) end
    if hasCamera then w:vi(entity.cameraData.values.tank) end
    if hasStyle then w:float64Precision(entity.styleData.values.borderWidth) end
    if hasCamera then w:vi(entity.cameraData.values.deathTick) end
    if hasPhysics then w:float(entity.physicsData.values.width) end
    if hasCamera then w:vi(entity.cameraData.values.statsAvailable) end
    if hasBarrel then w:vu(entity.barrelData.values.flags) end
    if hasCamera then w:float(entity.cameraData.values.levelbarMax) end
    if hasName then w:stringNT(entity.nameData.values.name) end
    if hasRelations then w:entid(entity.relationsData.values.owner) end
    if hasHealth then w:float(entity.healthData.values.health) end
    if hasCamera then w:float(entity.cameraData.values.cameraY) end
    if hasStyle then w:float(entity.styleData.values.opacity) end
    if hasBarrel then w:float(entity.barrelData.values.reloadTime) end
    if hasCamera then
        for i = 0, 7 do w:stringNT(entity.cameraData.values.statNames:get(i)) end
    end
    if hasCamera then w:float(entity.cameraData.values.cameraX) end
    if hasTeam then w:float(entity.teamData.values.mothershipX) end
    if hasCamera then w:vu(entity.cameraData.values.unusedClientId) end
    if hasRelations then w:entid(entity.relationsData.values.parent) end
    if hasStyle then w:vu(entity.styleData.values.zIndex) end
    if hasCamera then w:vu(entity.cameraData.values.flags) end
    if hasArena then w:float(entity.arenaData.values.rightX) end
    if hasPhysics then w:float(entity.physicsData.values.pushFactor) end
    if hasPhysics then w:vu(entity.physicsData.values.flags) end
    if hasArena then w:vu(entity.arenaData.values.scoreboardAmount) end
    if hasArena then w:float(entity.arenaData.values.ticksUntilStart) end
    if hasArena then w:float(entity.arenaData.values.topY) end
    if hasScore then w:float(entity.scoreData.values.score) end
end

local function writeTable(w, tbl, count, writeFn)
    local at = -1
    for i = 0, count - 1 do
        if tbl.state[i] == 1 then
            w:u8(bit.bxor(i - at, 1))
            writeFn(i)
            at = i
        end
    end
    w:u8(1)
    return at
end

local function compileUpdate(camera, w, entity)
    w:entid(entity):raw(0, 1)

    local hasRelations = entity.relationsData ~= nil
    local hasBarrel = entity.barrelData ~= nil
    local hasPhysics = entity.physicsData ~= nil
    local hasHealth = entity.healthData ~= nil
    local hasArena = entity.arenaData ~= nil
    local hasName = entity.nameData ~= nil
    local hasCamera = entity.cameraData ~= nil
    local hasPosition = entity.positionData ~= nil
    local hasStyle = entity.styleData ~= nil
    local hasScore = entity.scoreData ~= nil
    local hasTeam = entity.teamData ~= nil

    local at = -1
    local function field(id, cond, write)
        if cond then
            w:u8(bit.bxor(id - at, 1))
            at = id
            write()
        end
    end

    if hasPosition and entity.positionData.state[1] == 1 then field(0, true, function() w:vi(entity.positionData.values.y) end) end
    if hasPosition and entity.positionData.state[0] == 1 then field(1, true, function() w:vi(entity.positionData.values.x) end) end
    if hasPosition and entity.positionData.state[2] == 1 then field(2, true, function() w:float64Precision(entity.positionData.values.angle) end) end
    if hasPhysics and entity.physicsData.state[2] == 1 then field(3, true, function() w:float(entity.physicsData.values.size) end) end
    if hasCamera and entity.cameraData.state[2] == 1 then field(4, true, function() w:entid(entity.cameraData.values.player) end) end
    if hasArena and entity.arenaData.state[0] == 1 then field(5, true, function() w:vu(entity.arenaData.values.flags) end) end
    if hasStyle and entity.styleData.state[1] == 1 then field(6, true, function() w:vu(resolveColor(camera, entity)) end) end
    if hasArena and entity.arenaData.state[8] == 1 then
        w:u8(bit.bxor(7 - at, 1)); at = -1
        local colors = entity.arenaData.values.scoreboardColors
        for i = 0, 9 do
            if colors.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:vu(colors:get(i)); at = i
            end
        end
        w:u8(1); at = 7
    end
    if hasCamera and entity.cameraData.state[16] == 1 then field(8, true, function() w:stringNT(entity.cameraData.values.killedBy) end) end
    if hasArena and entity.arenaData.state[13] == 1 then field(9, true, function() w:vi(entity.arenaData.values.playersNeeded) end) end
    if hasPhysics and entity.physicsData.state[1] == 1 then field(10, true, function() w:vu(entity.physicsData.values.sides) end) end
    if hasTeam and entity.teamData.state[3] == 1 then field(11, true, function() w:vu(entity.teamData.values.flags) end) end
    if hasHealth and entity.healthData.state[0] == 1 then field(12, true, function() w:vu(entity.healthData.values.flags) end) end
    if hasArena and entity.arenaData.state[10] == 1 then
        w:u8(bit.bxor(13 - at, 1)); at = -1
        local tanks = entity.arenaData.values.scoreboardTanks
        for i = 0, 9 do
            if tanks.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:vi(tanks:get(i)); at = i
            end
        end
        w:u8(1); at = 13
    end
    if hasCamera and entity.cameraData.state[15] == 1 then field(14, true, function() w:vi(entity.cameraData.values.respawnLevel) end) end
    if hasCamera and entity.cameraData.state[6] == 1 then field(15, true, function() w:float(entity.cameraData.values.levelbarProgress) end) end
    if hasCamera and entity.cameraData.state[17] == 1 then field(16, true, function() w:vi(entity.cameraData.values.spawnTick) end) end
    if hasPhysics and entity.physicsData.state[4] == 1 then field(17, true, function() w:float(entity.physicsData.values.absorbtionFactor) end) end
    if hasArena and entity.arenaData.state[11] == 1 then field(18, true, function() w:float(entity.arenaData.values.leaderX) end) end
    if hasHealth and entity.healthData.state[2] == 1 then field(19, true, function() w:float(entity.healthData.values.maxHealth) end) end
    if hasStyle and entity.styleData.state[0] == 1 then field(20, true, function() w:vu(entity.styleData.values.flags) end) end
    if hasBarrel and entity.barrelData.state[2] == 1 then field(22, true, function() w:float(entity.barrelData.values.trapezoidDirection) end) end
    if hasPosition and entity.positionData.state[3] == 1 then field(23, true, function() w:vu(entity.positionData.values.flags) end) end
    if hasArena and entity.arenaData.state[6] == 1 then
        w:u8(bit.bxor(24 - at, 1)); at = -1
        local names = entity.arenaData.values.scoreboardNames
        for i = 0, 9 do
            if names.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:stringNT(names:get(i)); at = i
            end
        end
        w:u8(1); at = 24
    end
    if hasCamera and entity.cameraData.state[14] == 1 then field(25, true, function() w:float(entity.cameraData.values.score) end) end
    if hasTeam and entity.teamData.state[2] == 1 then field(26, true, function() w:float(entity.teamData.values.mothershipY) end) end
    if hasArena and entity.arenaData.state[9] == 1 then
        w:u8(bit.bxor(27 - at, 1)); at = -1
        local suffixes = entity.arenaData.values.scoreboardSuffixes
        for i = 0, 9 do
            if suffixes.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:stringNT(suffixes:get(i)); at = i
            end
        end
        w:u8(1); at = 27
    end
    if hasName and entity.nameData.state[0] == 1 then field(28, true, function() w:vu(entity.nameData.values.flags) end) end
    if hasCamera and entity.cameraData.state[20] == 1 then field(29, true, function() w:float(entity.cameraData.values.movementSpeed) end) end
    if hasArena and entity.arenaData.state[12] == 1 then field(30, true, function() w:float(entity.arenaData.values.leaderY) end) end
    if hasArena and entity.arenaData.state[4] == 1 then field(31, true, function() w:float(entity.arenaData.values.bottomY) end) end
    if hasRelations and entity.relationsData.state[2] == 1 then field(32, true, function() w:entid(entity.relationsData.values.team) end) end
    if hasCamera and entity.cameraData.state[4] == 1 then field(33, true, function() w:vi(entity.cameraData.values.level) end) end
    if hasTeam and entity.teamData.state[0] == 1 then field(34, true, function() w:vu(entity.teamData.values.teamColor) end) end
    if hasCamera and entity.cameraData.state[3] == 1 then field(35, true, function() w:float(entity.cameraData.values.FOV) end) end
    if hasCamera and entity.cameraData.state[11] == 1 then
        w:u8(bit.bxor(36 - at, 1)); at = -1
        local limits = entity.cameraData.values.statLimits
        for i = 0, 7 do
            if limits.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:vi(limits:get(i)); at = i
            end
        end
        w:u8(1); at = 36
    end
    if hasArena and entity.arenaData.state[1] == 1 then field(37, true, function() w:float(entity.arenaData.values.leftX) end) end
    if hasArena and entity.arenaData.state[7] == 1 then
        w:u8(bit.bxor(38 - at, 1)); at = -1
        local scores = entity.arenaData.values.scoreboardScores
        for i = 0, 9 do
            if scores.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:vi(scores:get(i)); at = i
            end
        end
        w:u8(1); at = 38
    end
    if hasCamera and entity.cameraData.state[10] == 1 then
        w:u8(bit.bxor(39 - at, 1)); at = -1
        local levels = entity.cameraData.values.statLevels
        for i = 0, 7 do
            if levels.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:vi(levels:get(i)); at = i
            end
        end
        w:u8(1); at = 39
    end
    if hasCamera and entity.cameraData.state[19] == 1 then field(40, true, function() w:stringNT(entity.cameraData.values.tankOverride) end) end
    if hasCamera and entity.cameraData.state[5] == 1 then field(41, true, function() w:vi(entity.cameraData.values.tank) end) end
    if hasStyle and entity.styleData.state[2] == 1 then field(42, true, function() w:float64Precision(entity.styleData.values.borderWidth) end) end
    if hasCamera and entity.cameraData.state[18] == 1 then field(43, true, function() w:vi(entity.cameraData.values.deathTick) end) end
    if hasPhysics and entity.physicsData.state[3] == 1 then field(44, true, function() w:float(entity.physicsData.values.width) end) end
    if hasCamera and entity.cameraData.state[8] == 1 then field(45, true, function() w:vi(entity.cameraData.values.statsAvailable) end) end
    if hasBarrel and entity.barrelData.state[0] == 1 then field(46, true, function() w:vu(entity.barrelData.values.flags) end) end
    if hasCamera and entity.cameraData.state[7] == 1 then field(47, true, function() w:float(entity.cameraData.values.levelbarMax) end) end
    if hasName and entity.nameData.state[1] == 1 then field(48, true, function() w:stringNT(entity.nameData.values.name) end) end
    if hasRelations and entity.relationsData.state[1] == 1 then field(49, true, function() w:entid(entity.relationsData.values.owner) end) end
    if hasHealth and entity.healthData.state[1] == 1 then field(50, true, function() w:float(entity.healthData.values.health) end) end
    if hasCamera and entity.cameraData.state[13] == 1 then field(51, true, function() w:float(entity.cameraData.values.cameraY) end) end
    if hasStyle and entity.styleData.state[3] == 1 then field(52, true, function() w:float(entity.styleData.values.opacity) end) end
    if hasBarrel and entity.barrelData.state[1] == 1 then field(53, true, function() w:float(entity.barrelData.values.reloadTime) end) end
    if hasCamera and entity.cameraData.state[9] == 1 then
        w:u8(bit.bxor(54 - at, 1)); at = -1
        local names = entity.cameraData.values.statNames
        for i = 0, 7 do
            if names.state[i] == 1 then
                w:u8(bit.bxor(i - at, 1)); w:stringNT(names:get(i)); at = i
            end
        end
        w:u8(1); at = 54
    end
    if hasCamera and entity.cameraData.state[12] == 1 then field(55, true, function() w:float(entity.cameraData.values.cameraX) end) end
    if hasTeam and entity.teamData.state[1] == 1 then field(56, true, function() w:float(entity.teamData.values.mothershipX) end) end
    if hasCamera and entity.cameraData.state[0] == 1 then field(57, true, function() w:vu(entity.cameraData.values.unusedClientId) end) end
    if hasRelations and entity.relationsData.state[0] == 1 then field(58, true, function() w:entid(entity.relationsData.values.parent) end) end
    if hasStyle and entity.styleData.state[4] == 1 then field(59, true, function() w:vu(entity.styleData.values.zIndex) end) end
    if hasCamera and entity.cameraData.state[1] == 1 then field(60, true, function() w:vu(entity.cameraData.values.flags) end) end
    if hasArena and entity.arenaData.state[3] == 1 then field(61, true, function() w:float(entity.arenaData.values.rightX) end) end
    if hasPhysics and entity.physicsData.state[5] == 1 then field(62, true, function() w:float(entity.physicsData.values.pushFactor) end) end
    if hasPhysics and entity.physicsData.state[0] == 1 then field(63, true, function() w:vu(entity.physicsData.values.flags) end) end
    if hasArena and entity.arenaData.state[5] == 1 then field(64, true, function() w:vu(entity.arenaData.values.scoreboardAmount) end) end
    if hasArena and entity.arenaData.state[14] == 1 then field(65, true, function() w:float(entity.arenaData.values.ticksUntilStart) end) end
    if hasArena and entity.arenaData.state[2] == 1 then field(66, true, function() w:float(entity.arenaData.values.topY) end) end
    if hasScore and entity.scoreData.state[0] == 1 then field(67, true, function() w:float(entity.scoreData.values.score) end) end

    w:u8(1)
end

return {
    compileCreation = compileCreation,
    compileUpdate = compileUpdate
}
