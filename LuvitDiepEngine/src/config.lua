--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local env = (process and process.env) or {}

local config = {}

config.buildHash = "6f59094d60f98fafc14371671d3ff31ef4d75d9e"
config.serverPort = tonumber(env.PORT or os.getenv("PORT") or "8080")
config.mspt = 40
config.tps = 1000 / config.mspt
config.connectionsPerIp = math.huge
config.wssMaxMessageSize = 4096
config.writtenBufferChunkSize = 2048
config.host = env.SERVER_INFO or os.getenv("SERVER_INFO") or "unknown"
config.mode = env.NODE_ENV or os.getenv("NODE_ENV") or "production"
config.countdownDuration = 10 * config.tps
config.shinyChance = 1 / 1000000
config.factorySpawnChance = 0.05
config.enableAchievements = true
config.enableApi = true
config.apiLocation = "api"
config.enableCommands = true
config.hashGridCellSize = 7
config.bossSpawningInterval = 45 * 60 * config.tps
config.scoreboardUpdateInterval = 1 * config.tps
config.devPasswordHash = env.DEV_PASSWORD_HASH or os.getenv("DEV_PASSWORD_HASH")
config.doVerboseLogs = false

config.AccessLevel = {
    FullAccess = 3,
    BetaAccess = 2,
    kReserved = 1,
    PublicAccess = 0,
    NoAccess = -1
}

config.unbannableLevelMinimum = config.AccessLevel.FullAccess
config.defaultAccessLevel = config.AccessLevel.BetaAccess
config.maxPlayerLevel = 45

local function magicNum(build)
    local seed, res, timer = 1, 0, 0
    for i = 1, 40 do
        local char = tonumber(build:sub(i, i), 16) or 0
        local shift = bit.lshift(bit.band(seed, 1), 2)
        res = bit.bxor(res, bit.lshift(bit.lshift(char, shift), bit.lshift(timer, 3)))
        timer = bit.band(timer + 1, 3)
        if timer == 0 then
            seed = bit.bxor(seed, 1)
        end
    end
    return bit.tobit(res)
end

config.magicNum = magicNum(config.buildHash)

return config
