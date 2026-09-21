local json = require("src.json")
local HttpGet = require("src.net.http")
local Url = require("src.net.url")
local config = require("src.config")
local Render = require("src.render")

local Tanks = {}

local fetch = nil
local watchKey = ""
local wait = nil

local function hostKey(game)
    local raw = game and game.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    local parsed = Url.parse(raw)
    if not parsed then return "" end
    return parsed.host .. ":" .. tostring(parsed.port)
end

local function addDef(byId, def, fallbackId)
    if type(def) ~= "table" or def == json.null then
        return 0
    end
    local id = def.id
    if id == nil then
        id = fallbackId
    end
    id = tonumber(id)
    if id == nil then
        return 0
    end
    byId[id] = def
    if id >= 0 then
        return 1
    end
    return 0
end

local function parseTanks(body)
    local ok, parsed = pcall(json.decode, body or "")
    if not ok or type(parsed) ~= "table" then
        return nil
    end
    local countHint = nil
    local list = parsed
    if type(parsed.tanks) == "table" then
        list = parsed.tanks
        countHint = tonumber(parsed.count)
    end
    local byId = {}
    local count = 0
    if #list > 0 then
        for i = 1, #list do
            count = count + addDef(byId, list[i], i - 1)
        end
    else
        for k, def in pairs(list) do
            count = count + addDef(byId, def, tonumber(k))
        end
    end
    if count < 1 then
        return nil
    end
    if countHint and countHint > 0 then
        count = countHint
    end
    return byId, count
end

local function apply(game, byId, count)
    if not game or not byId then return end
    game.tanksById = byId
    game.tankCount = count
    if Render.invalidateIconCache then
        Render.invalidateIconCache()
    end
end

function Tanks.parse(body)
    return parseTanks(body)
end

function Tanks.fetch(game)
    if not game then return end
    local raw = game.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    local modes = game.apiModes and game:apiModes() or game.modes
    local target = Url.resolveApi(raw, (config.apiPath or "/api") .. "/tanks", modes)
    if not target then return end
    watchKey = hostKey(game)
    if fetch and not fetch.done then
        fetch.callback = nil
        fetch:finish(false, "replaced")
    end
    fetch = HttpGet:new()
    fetch:get(target, function(ok, body)
        if not ok then
            return
        end
        local byId, count = parseTanks(body)
        if byId then
            apply(game, byId, count)
        end
    end)
end

function Tanks.update(game, dt)
    if fetch and not fetch.done then
        fetch:update()
    end
    if not game then return end
    local key = hostKey(game)
    if key ~= watchKey then
        watchKey = key
        wait = 0.45
    end
    if wait then
        wait = wait - (dt or 0)
        if wait <= 0 then
            wait = nil
            Tanks.fetch(game)
        end
    end
end

return Tanks
