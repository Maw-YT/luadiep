local bit = require("bit")

local config = {}

config.buildHash = "6f59094d60f98fafc14371671d3ff31ef4d75d9e"
config.defaultUrl = "127.0.0.1:8080"
config.defaultGamemode = "ffa"
config.apiPath = "/api"
config.pingInterval = 0.25
config.inputInterval = 0.04
config.statCount = 8

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
