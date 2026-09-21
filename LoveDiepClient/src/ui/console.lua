local Encode = require("src.protocol.encode")
local Render = require("src.render")
local json = require("src.lib.json")
local HttpGet = require("src.net.http")
local Url = require("src.net.url")
local config = require("src.config")

local Console = {}

local ALIASES = {
    tank = "game_set_tank",
    level = "game_set_level",
    score = "game_set_score",
    stat = "game_set_stat",
    points = "game_add_upgrade_points",
    tp = "game_teleport",
    teleport = "game_teleport",
    god = "game_godmode",
    godmode = "game_godmode",
    announce = "game_announce",
    summon = "admin_summon",
    killall = "admin_kill_all",
    kill = "admin_kill_entity",
    close = "admin_close_arena",
    achievement = "game_achievement"
}

local LOCAL_COMMANDS = {
    { name = "help", usage = "", desc = "List commands" },
    { name = "clear", usage = "", desc = "Clear console output" }
}

local FALLBACK_COMMANDS = {
    { name = "game_set_tank", usage = "[tank]", desc = "Set your class (alias: tank)" },
    { name = "game_set_level", usage = "[level]", desc = "Set level (alias: level)" },
    { name = "game_set_score", usage = "[score]", desc = "Set score (alias: score)" },
    { name = "game_set_stat", usage = "[stat] [points]", desc = "Set a stat (alias: stat)" },
    { name = "game_add_upgrade_points", usage = "[points]", desc = "Add upgrade points (alias: points)" },
    { name = "game_teleport", usage = "[x] [y]", desc = "Teleport (alias: tp)" },
    { name = "game_godmode", usage = "[on|off]", desc = "Toggle godmode (alias: god)" },
    { name = "game_announce", usage = "[message]", desc = "Broadcast a message" },
    { name = "admin_kill_all", usage = "", desc = "Kill all entities" },
    { name = "admin_close_arena", usage = "", desc = "Close the arena" }
}

local remoteCommands = nil
local remoteKey = ""
local fetch = nil

local MAX_LOG = 80
local MAX_HISTORY = 32
local MAX_INPUT = 200

local function rgb(hex)
    hex = tonumber(hex) or 0xFFFFFF
    local r = math.floor(hex / 65536) % 256
    local g = math.floor(hex / 256) % 256
    local b = hex % 256
    return r / 255, g / 255, b / 255
end

local function txt(s)
    return Render.safeText(s)
end

function Console.ensure(game)
    if game.console then return game.console end
    game.console = {
        open = false,
        anim = 0,
        text = "",
        log = {},
        history = {},
        histIndex = 0,
        scroll = 0,
        panelY = 0,
        panelH = 0,
        panelW = 0,
        visible = 1
    }
    Console.push(game, "Console — Home to close. Type help for commands.", 0x8EC8FF)
    return game.console
end

function Console.isOpen(game)
    local c = game and game.console
    return c and c.open
end

function Console.push(game, text, color)
    local c = Console.ensure(game)
    if (c.scroll or 0) > 0 then
        c.scroll = c.scroll + 1
    end
    c.log[#c.log + 1] = {
        text = txt(tostring(text or "")),
        color = color or 0xEEEEEE
    }
    while #c.log > MAX_LOG do
        table.remove(c.log, 1)
    end
end

function Console.toggle(game)
    local c = Console.ensure(game)
    c.open = not c.open
    if c.open then
        c.histIndex = 0
        c.scroll = 0
        game.focus = "console"
        local access = tonumber(game.accessLevel) or 0
        local accessName = (access >= 3 and "full") or (access >= 2 and "beta") or "public"
        Console.push(game, "Access: " .. accessName .. ". Spawn, then run commands like: tank Overlord", 0x8EC8FF)
        if game.needsAuth and game:needsAuth() then
            Console.push(game, "Password is typed but not applied. Press Play to reconnect with it.", 0xFFAA00)
        end
    elseif game.focus == "console" then
        game.focus = "spawnName"
    end
end

local function commandList()
    local list = {}
    for i = 1, #LOCAL_COMMANDS do
        list[#list + 1] = LOCAL_COMMANDS[i]
    end
    local src = remoteCommands or FALLBACK_COMMANDS
    for i = 1, #src do
        list[#list + 1] = src[i]
    end
    return list
end

local function parseRemote(body)
    local ok, parsed = pcall(json.decode, body or "")
    if not ok or type(parsed) ~= "table" then
        return nil
    end
    local list = {}
    local n = #parsed
    if n == 0 then
        for _, def in pairs(parsed) do
            if type(def) == "table" then
                n = n + 1
                parsed[n] = def
            end
        end
    end
    for i = 1, #parsed do
        local def = parsed[i]
        if type(def) == "table" and def ~= json.null then
            local name = def.id or def.name
            if type(name) == "string" and name ~= "" then
                list[#list + 1] = {
                    name = name,
                    usage = tostring(def.usage or ""),
                    desc = tostring(def.description or def.desc or ""),
                    permissionLevel = tonumber(def.permissionLevel)
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Console.fetch(game)
    if not game then return end
    local raw = game.url
    if type(raw) ~= "string" or raw:match("^%s*$") then
        raw = config.defaultUrl
    end
    local modes = game.apiModes and game:apiModes() or game.modes
    local target = Url.resolveApi(raw, (config.apiPath or "/api") .. "/commands", modes)
    if not target then return end
    local key = target.host .. ":" .. tostring(target.port) .. Url.requestPath(target)
    if fetch and not fetch.done then
        fetch.callback = nil
        fetch:finish(false, "replaced")
    end
    fetch = HttpGet:new()
    fetch:get(target, function(ok, body)
        if not ok then
            if body ~= "replaced" and not remoteCommands then
                Console.push(game, "Couldn't load server commands; using local list.", 0xFFAA00)
            end
            return
        end
        local list = parseRemote(body)
        if not list then
            Console.push(game, "Server command list was invalid.", 0xFFAA00)
            return
        end
        local first = remoteCommands == nil or remoteKey ~= key
        remoteCommands = list
        remoteKey = key
        if first then
            Console.push(game, "Loaded " .. tostring(#list) .. " commands from the server.", 0x8EC8FF)
        end
    end)
end

function Console.update(game, dt)
    if fetch and not fetch.done then
        fetch:update()
    end
    local c = Console.ensure(game)
    local target = c.open and 1 or 0
    local a = 1 - math.exp(-(dt or 0.016) * 14)
    c.anim = c.anim + (target - c.anim) * a
    if math.abs(c.anim - target) < 0.002 then
        c.anim = target
    end
end

local function splitArgs(line)
    local args = {}
    local buf = ""
    local quote = nil
    for i = 1, #line do
        local ch = line:sub(i, i)
        if quote then
            if ch == quote then
                quote = nil
            else
                buf = buf .. ch
            end
        elseif ch == '"' or ch == "'" then
            quote = ch
        elseif ch:match("%s") then
            if buf ~= "" then
                args[#args + 1] = buf
                buf = ""
            end
        else
            buf = buf .. ch
        end
    end
    if buf ~= "" then
        args[#args + 1] = buf
    end
    return args
end

local function commandNames()
    local names = {}
    local cmds = commandList()
    for i = 1, #cmds do
        names[#names + 1] = cmds[i].name
    end
    for alias in pairs(ALIASES) do
        names[#names + 1] = alias
    end
    table.sort(names)
    return names
end

local function complete(text)
    local prefix = (text or ""):match("^(%S*)$") or ""
    if prefix == "" then return text end
    local names = commandNames()
    local hit = nil
    for i = 1, #names do
        if names[i]:sub(1, #prefix) == prefix then
            if hit and hit ~= names[i] then
                return text
            end
            hit = names[i]
        end
    end
    return hit or text
end

local function helpText()
    local lines = { remoteCommands and "Commands (from server):" or "Commands:" }
    local cmds = commandList()
    for i = 1, #cmds do
        local cmd = cmds[i]
        local usage = cmd.usage ~= "" and (" " .. cmd.usage) or ""
        lines[#lines + 1] = "  " .. cmd.name .. usage .. "  —  " .. cmd.desc
    end
    lines[#lines + 1] = "Dev password on the menu is required for full-access commands."
    return lines
end

function Console.submit(game)
    local c = Console.ensure(game)
    local line = (c.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    c.text = ""
    c.histIndex = 0
    if line == "" then return end
    if line:sub(1, 1) == "/" then
        line = line:sub(2)
    end
    c.history[#c.history + 1] = line
    while #c.history > MAX_HISTORY do
        table.remove(c.history, 1)
    end
    Console.push(game, "> " .. line, 0x9AD1FF)

    local parts = splitArgs(line)
    local raw = parts[1]
    if not raw then return end
    raw = raw:lower()
    if raw == "help" or raw == "?" then
        local lines = helpText()
        for i = 1, #lines do
            Console.push(game, lines[i], 0xD7E6F5)
        end
        return
    end
    if raw == "clear" then
        c.log = {}
        c.scroll = 0
        Console.push(game, "Cleared.", 0x8EC8FF)
        return
    end
    local cmd = ALIASES[raw] or raw
    local args = {}
    for i = 2, #parts do
        args[#args + 1] = parts[i]
    end
    if (cmd == "game_announce" or cmd == "game_set_tank") and #args > 0 then
        args = { table.concat(args, " ") }
    end
    if not game:connected() then
        Console.push(game, "Not connected.", 0xFF6B6B)
        return
    end
    if game.needsAuth and game:needsAuth() then
        Console.push(game, "Password wasn't sent yet. Reconnecting with it — run the command again after Play.", 0xFFAA00)
        game:connect()
        return
    end
    if not game.world:isSpawned() and cmd:sub(1, 5) == "game_" then
        Console.push(game, "Spawn first, then run " .. cmd, 0xFFAA00)
    end
    game:send(Encode.command(cmd, args))
    local access = tonumber(game.accessLevel) or 0
    local accessName = (access >= 3 and "full") or (access >= 2 and "beta") or "public"
    Console.push(game, "sent " .. cmd .. "  (" .. accessName .. " access)", 0x7DDA9A)
end

function Console.textinput(game, text)
    if not Console.isOpen(game) then return false end
    if type(text) ~= "string" or text == "" then return true end
    if text:match("%c") then return true end
    local c = game.console
    c.text = ((c.text or "") .. text):sub(1, MAX_INPUT)
    return true
end

function Console.keypressed(game, key, isrepeat)
    if key == "home" then
        if not isrepeat then
            Console.toggle(game)
        end
        return true
    end
    if not Console.isOpen(game) then
        return false
    end
    local c = game.console
    if key == "escape" then
        Console.toggle(game)
        return true
    elseif key == "return" or key == "kpenter" or key == "enter" then
        if not isrepeat then
            Console.submit(game)
        end
        return true
    elseif key == "backspace" then
        local v = c.text or ""
        if #v > 0 then
            c.text = v:sub(1, -2)
        end
        return true
    elseif key == "up" then
        if #c.history == 0 then return true end
        if c.histIndex < #c.history then
            c.histIndex = c.histIndex + 1
        end
        c.text = c.history[#c.history - c.histIndex + 1] or ""
        return true
    elseif key == "down" then
        if c.histIndex <= 1 then
            c.histIndex = 0
            c.text = ""
        else
            c.histIndex = c.histIndex - 1
            c.text = c.history[#c.history - c.histIndex + 1] or ""
        end
        return true
    elseif key == "tab" then
        c.text = complete(c.text or "")
        return true
    end
    return true
end

function Console.wheel(game, dx, dy, gx, gy)
    if not Console.isOpen(game) then return false end
    local c = game.console
    local y = c.panelY or 0
    local h = c.panelH or 0
    local w = c.panelW or 0
    if h <= 0 then return false end
    gx = gx or 0
    gy = gy or 0
    if gx < 0 or gx > w or gy < y or gy > y + h then
        return false
    end
    local visible = math.max(1, c.visible or 1)
    local maxScroll = math.max(0, #c.log - visible)
    local step = 3
    if (dy or 0) > 0 then
        c.scroll = math.min(maxScroll, (c.scroll or 0) + step)
    elseif (dy or 0) < 0 then
        c.scroll = math.max(0, (c.scroll or 0) - step)
    end
    return true
end

function Console.draw(game, buttons, sw, sh, box)
    local c = Console.ensure(game)
    if c.anim <= 0.01 then return end
    local h = math.min(320, sh * 0.42)
    local y = -h * (1 - c.anim)
    local a = c.anim

    love.graphics.setColor(0.05, 0.07, 0.10, 0.88 * a)
    love.graphics.rectangle("fill", 0, y, sw, h)
    love.graphics.setColor(0.16, 0.55, 0.85, 0.95 * a)
    love.graphics.rectangle("fill", 0, y + h - 3, sw, 3)

    love.graphics.setColor(0.75, 0.85, 0.95, a)
    Render.print("Console", 16, y + 10)
    love.graphics.setColor(0.55, 0.62, 0.70, 0.85 * a)
    Render.printf("Home close   Enter send   Tab complete   Wheel scroll   Up/Down history", 16, y + 10, sw - 32, "right")

    local logBottom = y + h - 46
    local lineH = 18
    local visible = math.max(1, math.floor((h - 62) / lineH))
    local maxScroll = math.max(0, #c.log - visible)
    local scroll = math.max(0, math.min(maxScroll, c.scroll or 0))
    c.scroll = scroll
    c.visible = visible
    c.panelY = y
    c.panelH = h
    c.panelW = sw
    local start = math.max(1, #c.log - visible + 1 - scroll)
    local ly = y + 34
    for i = start, #c.log do
        local entry = c.log[i]
        local r, g, b = rgb(entry.color)
        love.graphics.setColor(r, g, b, a)
        Render.print(entry.text, 16, ly)
        ly = ly + lineH
        if ly > logBottom - 2 then break end
    end
    if maxScroll > 0 then
        local barH = math.max(18, (visible / #c.log) * (h - 72))
        local barY = y + 34 + (1 - (scroll / maxScroll)) * ((h - 72) - barH)
        love.graphics.setColor(1, 1, 1, 0.18 * a)
        love.graphics.rectangle("fill", sw - 10, y + 34, 4, h - 72, 2, 2)
        love.graphics.setColor(0.70, 0.84, 1, 0.7 * a)
        love.graphics.rectangle("fill", sw - 10, barY, 4, barH, 2, 2)
    end

    love.graphics.setColor(0.08, 0.10, 0.13, 0.95 * a)
    love.graphics.rectangle("fill", 10, y + h - 38, sw - 20, 28, 6, 6)
    love.graphics.setColor(0.55, 0.78, 1, a)
    local caret = (love.timer.getTime() % 1 < 0.5) and "_" or " "
    Render.print("> " .. txt(c.text or "") .. caret, 18, y + h - 32)

    if box then
        box(buttons, 0, y, sw, h, function()
            game.focus = "console"
        end, "console", "arrow")
        box(buttons, 10, y + h - 38, sw - 20, 28, function()
            game.focus = "console"
        end, "console-input", "ibeam")
    end
end

return Console
