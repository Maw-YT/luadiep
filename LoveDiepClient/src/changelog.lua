local json = require("src.json")
local HttpGet = require("src.net.http")
local Url = require("src.net.url")
local config = require("src.config")

local Changelog = {}

local FALLBACK = {
    {
        date = "Sep 21, 2026",
        items = {
            "Server now hosts 2TDM, 4TDM, Maze, Survival, Domination, and Mothership.",
            "Client FPS now follows the monitor refresh rate.",
            "Tank tree icons are cached so zooming stays smooth.",
            "The match still plays behind the tank tree.",
            "Gamemode buttons now load from the server.",
            "Home screen changelog panel.",
            "Fixed 3D trap outlines.",
            "Smashers and top turrets read as stacked 3D parts."
        }
    },
    {
        date = "Sep 20, 2026",
        items = {
            "Added a depth-tested 3D shaded look.",
            "Dev password now persists between sessions."
        }
    },
    {
        date = "Sep 19, 2026",
        items = {
            "Join public TLS URLs without freezing.",
            "Recover from dropped connections instead of hanging."
        }
    },
    {
        date = "Sep 18, 2026",
        items = {
            "Lua diep server and LÖVE client.",
            "HUD, pause menu, and health-bar effects."
        }
    }
}

local entries = nil
local fetch = nil
local watchKey = ""
local wait = nil
local scroll = 0
local maxScroll = 0
local panel = { x = 0, y = 0, w = 0, h = 0 }
local visible = false

local function hostKey(game)
    local raw = game and game.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    local parsed = Url.parse(raw)
    if not parsed then return "" end
    return parsed.host .. ":" .. tostring(parsed.port)
end

local function asItems(src)
    local items = {}
    if type(src) == "string" and src ~= "" then
        items[1] = src
        return items
    end
    if type(src) ~= "table" then
        return items
    end
    for i = 1, #src do
        if type(src[i]) == "string" and src[i] ~= "" then
            items[#items + 1] = src[i]
        end
    end
    return items
end

local function parseChangelog(body)
    local ok, parsed = pcall(json.decode, body or "")
    if not ok or type(parsed) ~= "table" then
        return nil
    end
    local list = {}
    if type(parsed[1]) == "string" then
        local current = { date = "", items = {} }
        for i = 1, #parsed do
            local line = parsed[i]
            if type(line) == "string" then
                if line == "" then
                    if current.date ~= "" or #current.items > 0 then
                        list[#list + 1] = current
                        current = { date = "", items = {} }
                    end
                else
                    current.items[#current.items + 1] = line
                end
            end
        end
        if current.date ~= "" or #current.items > 0 then
            list[#list + 1] = current
        end
        return #list > 0 and list or nil
    end
    if #parsed == 0 then
        for _, def in pairs(parsed) do
            if type(def) == "table" then
                parsed[#parsed + 1] = def
            end
        end
    end
    for i = 1, #parsed do
        local e = parsed[i]
        if type(e) == "table" and e ~= json.null then
            local date = e.date or e.title or ""
            if type(date) ~= "string" then
                date = tostring(date)
            end
            local items = asItems(e.items or e.lines or e.changes or e.text)
            if date ~= "" or #items > 0 then
                list[#list + 1] = { date = date, items = items }
            end
        end
    end
    return #list > 0 and list or nil
end

local function loadLocal()
    local raw = love.filesystem.read("assets/changelog.json")
    if not raw then
        return FALLBACK
    end
    return parseChangelog(raw) or FALLBACK
end

function Changelog.load()
    if not entries then
        entries = loadLocal()
    end
    return Changelog
end

function Changelog.entries()
    Changelog.load()
    return entries or FALLBACK
end

function Changelog.fetch(game)
    if not game then return end
    Changelog.load()
    local raw = game.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    local modes = game.apiModes and game:apiModes() or game.modes
    local target = Url.resolveApi(raw, (config.apiPath or "/api") .. "/changelog", modes)
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
        local list = parseChangelog(body)
        if list then
            entries = list
            scroll = 0
        end
    end)
end

function Changelog.update(game, dt)
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
            Changelog.fetch(game)
        end
    end
end

function Changelog.hide()
    visible = false
end

function Changelog.show(x, y, w, h)
    visible = true
    panel.x, panel.y, panel.w, panel.h = x, y, w, h
end

function Changelog.setMaxScroll(value)
    maxScroll = math.max(0, value or 0)
    if scroll > maxScroll then
        scroll = maxScroll
    elseif scroll < 0 then
        scroll = 0
    end
end

function Changelog.scrollOffset()
    return scroll
end

function Changelog.wheel(dx, dy, gx, gy)
    if not visible then return false end
    gx = gx or 0
    gy = gy or 0
    if gx < panel.x or gx > panel.x + panel.w or gy < panel.y or gy > panel.y + panel.h then
        return false
    end
    local step = 36
    if (dy or 0) > 0 then
        scroll = math.max(0, scroll - step)
    elseif (dy or 0) < 0 then
        scroll = math.min(maxScroll, scroll + step)
    end
    return true
end

return Changelog
