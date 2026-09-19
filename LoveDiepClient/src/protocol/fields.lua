local Fields = {}

Fields.GROUP = {
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

-- Creation writes every present-group field in this order (no ids).
-- Updates write dirty fields by id. Nested arrays use an inner index table.
-- scoreboardScores is float on create and vi on update (matches the server compiler).
Fields.list = {
    { id = 0,  group = "position", key = "y", type = "vi" },
    { id = 1,  group = "position", key = "x", type = "vi" },
    { id = 2,  group = "position", key = "angle", type = "float64Precision" },
    { id = 3,  group = "physics", key = "size", type = "float" },
    { id = 4,  group = "camera", key = "player", type = "entid" },
    { id = 5,  group = "arena", key = "flags", type = "vu" },
    { id = 6,  group = "style", key = "color", type = "vu" },
    { id = 7,  group = "arena", key = "scoreboardColors", type = "vu", count = 10 },
    { id = 8,  group = "camera", key = "killedBy", type = "stringNT" },
    { id = 9,  group = "arena", key = "playersNeeded", type = "vi" },
    { id = 10, group = "physics", key = "sides", type = "vu" },
    { id = 11, group = "team", key = "flags", type = "vu" },
    { id = 12, group = "health", key = "flags", type = "vu" },
    { id = 13, group = "arena", key = "scoreboardTanks", type = "vi", count = 10 },
    { id = 14, group = "camera", key = "respawnLevel", type = "vi" },
    { id = 15, group = "camera", key = "levelbarProgress", type = "float" },
    { id = 16, group = "camera", key = "spawnTick", type = "vi" },
    { id = 17, group = "physics", key = "absorbtionFactor", type = "float" },
    { id = 18, group = "arena", key = "leaderX", type = "float" },
    { id = 19, group = "health", key = "maxHealth", type = "float" },
    { id = 20, group = "style", key = "flags", type = "vu" },
    { id = 22, group = "barrel", key = "trapezoidDirection", type = "float" },
    { id = 23, group = "position", key = "flags", type = "vu" },
    { id = 24, group = "arena", key = "scoreboardNames", type = "stringNT", count = 10 },
    { id = 25, group = "camera", key = "score", type = "float" },
    { id = 26, group = "team", key = "mothershipY", type = "float" },
    { id = 27, group = "arena", key = "scoreboardSuffixes", type = "stringNT", count = 10 },
    { id = 28, group = "name", key = "flags", type = "vu" },
    { id = 29, group = "camera", key = "movementSpeed", type = "float" },
    { id = 30, group = "arena", key = "leaderY", type = "float" },
    { id = 31, group = "arena", key = "bottomY", type = "float" },
    { id = 32, group = "relations", key = "team", type = "entid" },
    { id = 33, group = "camera", key = "level", type = "vi" },
    { id = 34, group = "team", key = "teamColor", type = "vu" },
    { id = 35, group = "camera", key = "FOV", type = "float" },
    { id = 36, group = "camera", key = "statLimits", type = "vi", count = 8 },
    { id = 37, group = "arena", key = "leftX", type = "float" },
    { id = 38, group = "arena", key = "scoreboardScores", type = "float", updateType = "vi", count = 10 },
    { id = 39, group = "camera", key = "statLevels", type = "vi", count = 8 },
    { id = 40, group = "camera", key = "tankOverride", type = "stringNT" },
    { id = 41, group = "camera", key = "tank", type = "vi" },
    { id = 42, group = "style", key = "borderWidth", type = "float64Precision" },
    { id = 43, group = "camera", key = "deathTick", type = "vi" },
    { id = 44, group = "physics", key = "width", type = "float" },
    { id = 45, group = "camera", key = "statsAvailable", type = "vi" },
    { id = 46, group = "barrel", key = "flags", type = "vu" },
    { id = 47, group = "camera", key = "levelbarMax", type = "float" },
    { id = 48, group = "name", key = "name", type = "stringNT" },
    { id = 49, group = "relations", key = "owner", type = "entid" },
    { id = 50, group = "health", key = "health", type = "float" },
    { id = 51, group = "camera", key = "cameraY", type = "float" },
    { id = 52, group = "style", key = "opacity", type = "float" },
    { id = 53, group = "barrel", key = "reloadTime", type = "float" },
    { id = 54, group = "camera", key = "statNames", type = "stringNT", count = 8 },
    { id = 55, group = "camera", key = "cameraX", type = "float" },
    { id = 56, group = "team", key = "mothershipX", type = "float" },
    { id = 57, group = "camera", key = "unusedClientId", type = "vu" },
    { id = 58, group = "relations", key = "parent", type = "entid" },
    { id = 59, group = "style", key = "zIndex", type = "vu" },
    { id = 60, group = "camera", key = "flags", type = "vu" },
    { id = 61, group = "arena", key = "rightX", type = "float" },
    { id = 62, group = "physics", key = "pushFactor", type = "float" },
    { id = 63, group = "physics", key = "flags", type = "vu" },
    { id = 64, group = "arena", key = "scoreboardAmount", type = "vu" },
    { id = 65, group = "arena", key = "ticksUntilStart", type = "float" },
    { id = 66, group = "arena", key = "topY", type = "float" },
    { id = 67, group = "score", key = "score", type = "float" }
}

Fields.byId = {}
for i = 1, #Fields.list do
    Fields.byId[Fields.list[i].id] = Fields.list[i]
end

function Fields.defaults(group)
    if group == "relations" then
        return { parent = nil, owner = nil, team = nil }
    elseif group == "barrel" then
        return { flags = 0, reloadTime = 15, trapezoidDirection = 0 }
    elseif group == "physics" then
        return { flags = 0, sides = 0, size = 0, width = 0, absorbtionFactor = 1, pushFactor = 8 }
    elseif group == "health" then
        return { flags = 0, health = 1, maxHealth = 1 }
    elseif group == "arena" then
        local a = {
            flags = 2, leftX = 0, topY = 0, rightX = 0, bottomY = 0,
            scoreboardAmount = 0, leaderX = 0, leaderY = 0,
            playersNeeded = 1, ticksUntilStart = 250,
            scoreboardNames = {}, scoreboardScores = {}, scoreboardColors = {},
            scoreboardSuffixes = {}, scoreboardTanks = {}
        }
        for i = 0, 9 do
            a.scoreboardNames[i] = ""
            a.scoreboardScores[i] = 0
            a.scoreboardColors[i] = 13
            a.scoreboardSuffixes[i] = ""
            a.scoreboardTanks[i] = 0
        end
        return a
    elseif group == "name" then
        return { flags = 0, name = "" }
    elseif group == "camera" then
        local c = {
            unusedClientId = 0, flags = 1, player = nil, FOV = 0.35,
            level = 1, tank = 53, levelbarProgress = 0, levelbarMax = 0,
            statsAvailable = 0, cameraX = 0, cameraY = 0, score = 0,
            respawnLevel = 0, killedBy = "", spawnTick = 0, deathTick = -1,
            tankOverride = "", movementSpeed = 0,
            statNames = {}, statLevels = {}, statLimits = {}
        }
        for i = 0, 7 do
            c.statNames[i] = ""
            c.statLevels[i] = 0
            c.statLimits[i] = 0
        end
        return c
    elseif group == "position" then
        return { x = 0, y = 0, angle = 0, flags = 0 }
    elseif group == "style" then
        return { flags = 1, color = 0, borderWidth = 7.5, opacity = 1, zIndex = 0 }
    elseif group == "score" then
        return { score = 0 }
    elseif group == "team" then
        return { teamColor = 0, mothershipX = 0, mothershipY = 0, flags = 0 }
    end
    return {}
end

return Fields
