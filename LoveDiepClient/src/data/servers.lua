local json = require("src.lib.json")
local HttpGet = require("src.net.http")
local Url = require("src.net.url")
local config = require("src.config")

local Servers = {}

local FALLBACK = {
    { id = "ffa", label = "FFA" },
    { id = "teams", label = "2TDM" },
    { id = "4teams", label = "4TDM" },
    { id = "maze", label = "Maze" },
    { id = "survival", label = "Survival" },
    { id = "dom", label = "Domination" },
    { id = "mot", label = "Mothership" },
    { id = "sandbox", label = "Sandbox" }
}

local fetch = nil

local function parseServers(body)
    local ok, parsed = pcall(json.decode, body or "")
    if not ok or type(parsed) ~= "table" then
        return nil
    end
    if #parsed == 0 then
        for _, def in pairs(parsed) do
            if type(def) == "table" then
                parsed[#parsed + 1] = def
            end
        end
    end
    local list = {}
    local seen = {}
    for i = 1, #parsed do
        local def = parsed[i]
        if type(def) == "table" and def ~= json.null then
            local id = def.gamemode or def.id
            if type(id) == "string" and id ~= "" then
                id = id:lower()
                if not seen[id] then
                    seen[id] = true
                    list[#list + 1] = {
                        id = id,
                        label = tostring(def.name or def.label or id)
                    }
                end
            end
        end
    end
    if #list < 1 then
        return nil
    end
    return list
end

function Servers.fallback()
    return FALLBACK
end

function Servers.fetch(game)
    if not game then return end
    local raw = game.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    local modes = game.apiModes and game:apiModes() or game.modes or FALLBACK
    local target = Url.resolveApi(raw, (config.apiPath or "/api") .. "/servers", modes)
    if not target then return end
    if fetch and not fetch.done then
        fetch.callback = nil
        fetch:finish(false, "replaced")
    end
    fetch = HttpGet:new()
    fetch:get(target, function(ok, body)
        if not ok then
            return
        end
        local list = parseServers(body)
        if not list then
            return
        end
        game.modes = list
    end)
end

function Servers.update()
    if fetch and not fetch.done then
        fetch:update()
    end
end

return Servers
