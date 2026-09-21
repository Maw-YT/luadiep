--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local json = require("json")
local fs = require("fs")
local pathJoin = require("pathjoin").pathJoin

local info = debug.getinfo(1, "S")
local dir = (info.source:match("^@(.*)[/\\]") or ".")
local raw = fs.readFileSync(pathJoin(dir, "TankDefinitions.json"))
local parsed = json.parse(raw)

local function isNull(v)
    return v == nil or v == json.null
end

local function sanitize(value)
    if isNull(value) then return nil end
    if type(value) ~= "table" then return value end
    local out = {}
    local isArray = true
    for k, _ in pairs(value) do
        if type(k) ~= "number" then isArray = false break end
    end
    if isArray then
        for i, v in ipairs(value) do
            out[i] = sanitize(v)
        end
    else
        for k, v in pairs(value) do
            out[k] = sanitize(v)
        end
    end
    return out
end

local TankDefinitions = {}
local TankCount = 0
local maxn = 0
for i, _ in pairs(parsed) do
    if type(i) == "number" and i > maxn then maxn = i end
end
for i = 1, maxn do
    local def = parsed[i]
    if def and not isNull(def) then
        TankDefinitions[i - 1] = sanitize(def)
        TankCount = TankCount + 1
    end
end

local visibilityRateDamage = 0.2

local function getTankById(id)
    if not id then return nil end
    if id < 0 then
        local DevTankDefinitions = require("./DevTankDefinitions")
        return DevTankDefinitions[-id]
    end
    return TankDefinitions[id]
end

local function getTankByName(tankName)
    if type(tankName) ~= "string" or tankName == "" then return nil end
    local want = tankName:lower()
    for _, tank in pairs(TankDefinitions) do
        if tank and type(tank.name) == "string" and tank.name:lower() == want then return tank end
    end
    local DevTankDefinitions = require("./DevTankDefinitions")
    for _, tank in ipairs(DevTankDefinitions) do
        if tank and type(tank.name) == "string" and tank.name:lower() == want then return tank end
    end
    return nil
end

-- Cached JSON array for /api/tanks: vanilla defs (with null holes) plus dev tanks.
local clientJson = nil

local function exportClientJson()
    if clientJson then return clientJson end
    local list = {}
    for i = 1, maxn do
        list[i] = parsed[i]
    end
    local DevTankDefinitions = require("./DevTankDefinitions")
    for i = 1, #DevTankDefinitions do
        list[#list + 1] = DevTankDefinitions[i]
    end
    local ok, encoded = pcall(json.stringify, list)
    if ok and type(encoded) == "string" and encoded:sub(1, 1) == "[" then
        clientJson = encoded
        return clientJson
    end
    clientJson = raw
    return clientJson
end

return {
    TankDefinitions = TankDefinitions,
    TankCount = TankCount,
    visibilityRateDamage = visibilityRateDamage,
    getTankById = getTankById,
    getTankByName = getTankByName,
    exportClientJson = exportClientJson
}
