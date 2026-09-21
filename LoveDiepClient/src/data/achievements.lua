local json = require("src.lib.json")
local bit = require("bit")

local Achievements = {}

local NAME_SEED = 170
local DESC_SEED = 221

local defs = {}
local byHash = {}
local unlocked = {}
local unlockedSet = {}
local scroll = 0
local loaded = false

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
    return bit.tohex(h, 8):gsub("^0+", "")
end

function Achievements.hashOf(name, desc)
    local nh = murmurhash2(name, NAME_SEED)
    local dh = murmurhash2(desc, DESC_SEED)
    if nh == "" then nh = "0" end
    if dh == "" then dh = "0" end
    return nh .. dh .. "_1"
end

local function save()
    local parts = { '{"unlocked":[' }
    for i = 1, #unlocked do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = '"' .. tostring(unlocked[i].hash) .. '"'
    end
    parts[#parts + 1] = "]}"
    love.filesystem.write("achievements.json", table.concat(parts))
end

local function loadDefs()
    local raw = love.filesystem.read("assets/achievements.json")
    if not raw then return end
    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= "table" then return end
    for i = 1, #parsed do
        local a = parsed[i]
        if type(a) == "table" and type(a.name) == "string" then
            local hash = Achievements.hashOf(a.name, a.desc or "")
            local def = { name = a.name, desc = a.desc or "", hash = hash }
            defs[#defs + 1] = def
            byHash[hash] = def
        end
    end
end

local function loadSave()
    local raw = love.filesystem.read("achievements.json")
    if not raw then return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= "table" then return end
    local list = data.unlocked
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local hash = list[i]
        if type(hash) == "string" and hash ~= "" and not unlockedSet[hash] then
            unlockedSet[hash] = true
            unlocked[#unlocked + 1] = byHash[hash] or {
                name = "Achievement",
                desc = "",
                hash = hash
            }
        end
    end
end

function Achievements.load()
    if loaded then return Achievements end
    loaded = true
    loadDefs()
    loadSave()
    return Achievements
end

function Achievements.unlock(hash)
    Achievements.load()
    if type(hash) ~= "string" or hash == "" or unlockedSet[hash] then
        return nil
    end
    unlockedSet[hash] = true
    local def = byHash[hash] or { name = "Achievement", desc = "", hash = hash }
    unlocked[#unlocked + 1] = def
    save()
    return def
end

function Achievements.list()
    Achievements.load()
    return unlocked
end

function Achievements.update(dt)
    if #unlocked < 1 then return end
    scroll = scroll + dt * 22
end

function Achievements.scrollOffset()
    return scroll
end

return Achievements
