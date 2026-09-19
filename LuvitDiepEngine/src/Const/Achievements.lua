--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local json = require("json")
local fs = require("fs")
local pathJoin = require("pathjoin").pathJoin
local bit = require("bit")
local Enums = require("./Enums")
local config = require("../config")

local ClientBound = Enums.ClientBound
local NAME_SEED = 170
local DESC_SEED = 221
local OP_EQUALS, OP_GTE, OP_LTE = 0, 1, 2

local function u32mul(k, m)
    return bit.tobit(bit.band(k, 0xffff) * m + bit.lshift(bit.band(bit.rshift(k, 16) * m, 0xffff), 16))
end

local function murmurhash2(str, seed)
    str = str or ""
    local m = 0x5bd1e995
    local data = { str:byte(1, #str) }
    local len = #data
    local h = bit.bxor(seed, len)
    local i = 1
    while len >= 4 do
        local k = bit.bor(data[i], bit.lshift(data[i + 1], 8), bit.lshift(data[i + 2], 16), bit.lshift(data[i + 3], 24))
        k = u32mul(k, m)
        k = bit.bxor(k, bit.rshift(k, 24))
        k = u32mul(k, m)
        h = bit.bxor(u32mul(h, m), k)
        len = len - 4
        i = i + 4
    end
    if len == 3 then
        h = bit.bxor(h, bit.lshift(data[i + 2], 16))
    end
    if len >= 2 then
        h = bit.bxor(h, bit.lshift(data[i + 1], 8))
    end
    if len >= 1 then
        h = bit.bxor(h, data[i])
        h = u32mul(h, m)
    end
    h = bit.bxor(h, bit.rshift(h, 13))
    h = u32mul(h, m)
    h = bit.bxor(h, bit.rshift(h, 15))
    local hex = bit.tohex(h, 8):gsub("^0+", "")
    if hex == "" then hex = "0" end
    return hex
end

local function createHash(a)
    return murmurhash2(a.name or "", NAME_SEED) .. murmurhash2(a.desc or "", DESC_SEED) .. "_1"
end

local function compileConds(conds)
    if type(conds) ~= "table" then return {} end
    for i = 1, #conds do
        local c = conds[i]
        local tags = c.tags
        if type(tags) == "table" then
            for key, value in pairs(tags) do
                if key == "total" or key == "value" or key == "delta" then
                    value = tostring(value)
                    tags[key] = tonumber(value:sub(3))
                    local op = value:sub(1, 2)
                    if op == "==" then
                        c.op = OP_EQUALS
                    elseif op == ">=" then
                        c.op = OP_GTE
                    elseif op == "<=" then
                        c.op = OP_LTE
                    end
                end
            end
        else
            c.tags = {}
        end
    end
    return conds
end

local info = debug.getinfo(1, "S")
local dir = (info.source:match("^@(.*)[/\\]") or ".")
local raw = fs.readFileSync(pathJoin(dir, "Achievements.json"))
local parsed = json.parse(raw) or {}

local Achievements = {}
local byName = {}
local eventMap = {}

for i = 1, #parsed do
    local a = parsed[i]
    if type(a) == "table" then
        a.hash = createHash(a)
        a.conds = compileConds(a.conds)
        Achievements[#Achievements + 1] = a
        byName[a.name] = a
        for c = 1, #a.conds do
            local event = a.conds[c].event
            if event then
                if not eventMap[event] then eventMap[event] = {} end
                local list = eventMap[event]
                list[#list + 1] = a
            end
        end
    end
end

local function parseCondition(cond, data)
    if not cond then return true end
    local tags = cond.tags or {}
    for key, value in pairs(tags) do
        local given = data[key]
        if given == nil then
            return false
        end
        if key == "total" or key == "value" or key == "delta" then
            local op = cond.op
            if op == OP_EQUALS then
                if given ~= value then return false end
            elseif op == OP_GTE then
                if given < value then return false end
            elseif op == OP_LTE then
                if given > value then return false end
            end
        elseif given ~= value then
            return false
        end
    end
    return true
end

local function checkCondition(achievement, data)
    local conds = achievement.conds or {}
    for i = 1, #conds do
        if not parseCondition(conds[i], data) then
            return false
        end
    end
    return true
end

local function sendAchievements(client, hashes)
    if not client or client.terminated or not hashes or #hashes == 0 then return end
    local w = client:write()
    w:u8(ClientBound.Achievement)
    w:vu(#hashes)
    for i = 1, #hashes do
        w:stringNT(hashes[i])
    end
    w:send()
end

local function sendEvent(client, event, data)
    if not config.enableAchievements then return end
    if not client then return end
    local list = eventMap[event]
    if not list then return end
    local completed = {}
    for i = 1, #list do
        if checkCondition(list[i], data or {}) then
            completed[#completed + 1] = list[i].hash
        end
    end
    if #completed > 0 then
        client:giveAchievements(completed)
    end
end

local function getByName(name)
    return byName[name]
end

return {
    list = Achievements,
    sendEvent = sendEvent,
    sendAchievements = sendAchievements,
    getByName = getByName
}
