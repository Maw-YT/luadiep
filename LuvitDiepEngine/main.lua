--[[
    LuvitDiepEngine - Luvit diepcustom server
    Copyright (C) 2022 ABCxFF (github.com/ABCxFF)
    Ported to Luvit/LuaJIT.

    Licensed under the GNU Affero General Public License v3.0.
]]

bit = require("bit")
io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

local net = require("net")
local fs = require("fs")
local uv = require("uv")
local pathJoin = require("pathjoin").pathJoin
local url = require("url")
local json = require("json")

local config = require("./src/config")
local util = require("./src/util")
local GameServer = require("./src/Game")
local Client = require("./src/Client")
local WebSocket = require("./src/Net/WebSocket")
local TankDefs = require("./src/Const/TankDefinitions")
local Commands = require("./src/Const/Commands")
local Enums = require("./src/Const/Enums")
local FFAArena = require("./src/Gamemodes/FFA")
local TeamsArena = require("./src/Gamemodes/Teams")
local FourTeamsArena = require("./src/Gamemodes/FourTeams")
local MazeArena = require("./src/Gamemodes/Maze")
local SurvivalArena = require("./src/Gamemodes/Survival")
local DominationArena = require("./src/Gamemodes/Domination")
local MothershipArena = require("./src/Gamemodes/Mothership")
local SandboxArena = require("./src/Gamemodes/Sandbox")
local Pack = require("./src/Web/Pack")

math.randomseed(os.time())

local ROOT = process.cwd()
local connections = {}

local function thisDir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return src:match("^(.*)[/\\][^/\\]+$") or ROOT
end

local ENGINE_DIR = thisDir()
local WEB_ROOT = pathJoin(ENGINE_DIR, "web")
local CLIENT_ROOT = pathJoin(ENGINE_DIR, "..", "LoveDiepClient")

local MIME = {
    [".json"] = "application/json; charset=utf-8",
    [".html"] = "text/html; charset=utf-8",
    [".js"] = "text/javascript; charset=utf-8",
    [".css"] = "text/css; charset=utf-8",
    [".wasm"] = "application/wasm",
    [".lua"] = "text/plain; charset=utf-8",
    [".txt"] = "text/plain; charset=utf-8",
    [".love"] = "application/octet-stream"
}

local function getExt(p)
    return p:match("(%.[^./\\]+)$") or ""
end

local function writeHttp(socket, status, headers, body)
    body = body or ""
    headers = headers or {}
    headers["Content-Length"] = tostring(#body)
    if not headers["Connection"] then
        headers["Connection"] = "close"
    end
    local lines = { "HTTP/1.1 " .. tostring(status) }
    for k, v in pairs(headers) do
        lines[#lines + 1] = k .. ": " .. tostring(v)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    socket:write(table.concat(lines, "\r\n") .. body, function()
        pcall(function() socket:destroy() end)
    end)
end

local function sendFile(socket, filePath, status, headers)
    status = status or "200 OK"
    fs.readFile(filePath, function(err, data)
        if err or not data then
            writeHttp(socket, "404 Not Found", { ["Content-Type"] = "text/plain" }, "Not Found")
            return
        end
        headers = headers or {}
        if not headers["Content-Type"] then
            headers["Content-Type"] = MIME[getExt(filePath)] or "application/octet-stream"
        end
        writeHttp(socket, status, headers, data)
    end)
end

local function webHeaders(contentType)
    return {
        ["Content-Type"] = contentType,
        ["Cross-Origin-Opener-Policy"] = "same-origin",
        ["Cross-Origin-Embedder-Policy"] = "require-corp",
        ["Cross-Origin-Resource-Policy"] = "same-origin"
    }
end

local function webFile(rel)
    local parts = { WEB_ROOT }
    for seg in tostring(rel or ""):gmatch("[^/\\]+") do
        if seg == ".." or seg == "." then
            return nil
        end
        parts[#parts + 1] = seg
    end
    if #parts < 2 then
        return nil
    end
    return pathJoin(unpack(parts))
end

local function serveClient(socket, pathname)
    if pathname == "/" or pathname == "/index.html" then
        return sendFile(socket, pathJoin(WEB_ROOT, "index.html"), "200 OK", webHeaders("text/html; charset=utf-8"))
    end
    if pathname == "/client.love" then
        local data, err = Pack.zip(CLIENT_ROOT)
        if not data then
            util.log("Web client pack failed: " .. tostring(err))
            return writeHttp(socket, "500 Internal Server Error", {
                ["Content-Type"] = "text/plain"
            }, "Could not pack the LÖVE client")
        end
        local headers = webHeaders("application/octet-stream")
        headers["Cache-Control"] = "no-store"
        return writeHttp(socket, "200 OK", headers, data)
    end
    local rel = (pathname or "/"):gsub("^/+", "")
    if rel == "" or rel:find("%.%.", 1, true) then
        return writeHttp(socket, "404 Not Found", { ["Content-Type"] = "text/plain" }, "Not Found")
    end
    local filePath = webFile(rel)
    local stat = filePath and uv.fs_stat(filePath)
    if not filePath or not stat or stat.type ~= "file" then
        return writeHttp(socket, "404 Not Found", { ["Content-Type"] = "text/plain" }, "Not Found")
    end
    return sendFile(socket, filePath, "200 OK", webHeaders(MIME[getExt(filePath)] or "application/octet-stream"))
end

local function jsonReply(socket, obj)
    writeHttp(socket, "200 OK", { ["Content-Type"] = "application/json; charset=utf-8" }, json.stringify(obj))
end

local function handleApi(pathname, socket)
    local rest = pathname:sub(#config.apiLocation + 2)
    if rest == "" or rest == "/" then
        writeHttp(socket, "200 OK", { ["Content-Type"] = "text/plain" }, "")
        return
    end
    if rest == "/tanks" then
        -- JSON array of vanilla defs (null holes keep ids stable) plus appended dev tanks.
        return writeHttp(socket, "200 OK", {
            ["Content-Type"] = "application/json; charset=utf-8"
        }, TankDefs.exportClientJson())
    end
    if rest == "/servers" then
        local servers = {}
        for i = 1, #GameServer.games do
            servers[#servers + 1] = { gamemode = GameServer.games[i].gamemode, name = GameServer.games[i].name }
        end
        return jsonReply(socket, servers)
    end
    if rest == "/commands" then
        local cmds = {}
        if config.enableCommands then
            for _, def in pairs(Commands.commandDefinitions) do
                cmds[#cmds + 1] = def
            end
        end
        return jsonReply(socket, cmds)
    end
    if rest == "/colors" then
        return jsonReply(socket, Enums.ColorsHexCode)
    end
    if rest == "/achievements" then
        local achPath = pathJoin(ROOT, "src", "Const", "Achievements.json")
        return sendFile(socket, achPath)
    end
    if rest == "/changelog" then
        return sendFile(socket, pathJoin(ROOT, "src", "Const", "Changelog.json"))
    end
    writeHttp(socket, "404 Not Found", { ["Content-Type"] = "text/plain" }, "Not Found")
end

local function handleHttp(req, socket)
    local pathname = url.parse(req.url).pathname or "/"
    util.saveToVLog("Incoming request to " .. pathname)

    if config.enableApi and pathname:sub(1, #config.apiLocation + 1) == "/" .. config.apiLocation then
        return handleApi(pathname, socket)
    end

    return serveClient(socket, pathname)
end

local function peerIp(socket)
    local ok, addr = pcall(function()
        if socket.getpeername then return socket:getpeername() end
        if socket.address then return socket:address() end
    end)
    if ok and type(addr) == "table" then
        return addr.ip or addr.address or "unknown"
    end
    if ok and type(addr) == "string" then
        return addr
    end
    return "unknown"
end

local function normalizeGamemode(pathname)
    local g = pathname or "/"
    g = g:gsub("^https?://[^/]+", "")
    g = g:gsub("%?.*$", "")
    g = g:gsub("#.*$", "")
    g = g:gsub("^/+", ""):gsub("/+$", "")
    return g:lower()
end

local function findGame(pathname)
    local g = normalizeGamemode(pathname)
    if g == "" then return nil end
    local reversed = g:reverse()
    for i = 1, #GameServer.games do
        local id = GameServer.games[i].gamemode
        if id == g or id == reversed then
            return GameServer.games[i]
        end
    end
    for i = 1, #GameServer.games do
        local id = GameServer.games[i].gamemode
        if g:find(id, 1, true) or g:find(id:reverse(), 1, true) then
            return GameServer.games[i]
        end
    end
    return nil
end

local function handleUpgrade(req, socket, leftover)
    local pathname = url.parse(req.url).pathname or "/"
    local ip = peerIp(socket)
    util.log("WebSocket upgrade " .. pathname .. " from " .. ip)

    if GameServer.bannedClients[ip] then
        socket:destroy()
        return
    end
    local conns = connections[ip] or 0
    if conns >= config.connectionsPerIp then
        socket:destroy()
        return
    end

    local game = findGame(pathname)
    if not game then
        util.log("No gamemode for path " .. pathname)
        socket:destroy()
        return
    end

    local ws = WebSocket.handshake(req, socket, leftover)
    if not ws then
        util.log("WebSocket handshake failed for " .. pathname)
        socket:destroy()
        return
    end

    connections[ip] = conns + 1
    local client = Client:new(ws, game, ip)
    util.log("Client connected to " .. game.gamemode .. " (" .. tostring(game.clients.size) .. " in game)")
    ws.onMessage = function(payload, isBinary)
        if not isBinary then
            client:terminate()
            return
        end
        client:onMessage(payload)
    end
    ws.onClose = function()
        connections[ip] = math.max((connections[ip] or 1) - 1, 0)
        client:onClose()
    end
end

local function isWebSocketRequest(req)
    local upgrade = req.headers.upgrade or ""
    local connection = req.headers.connection or ""
    return upgrade:lower() == "websocket" and connection:lower():find("upgrade", 1, true) ~= nil
end

local function parseHttpHeaders(block)
    local lines = {}
    for line in (block .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    if #lines == 0 then return nil end
    local method, path = lines[1]:match("^(%S+)%s+(%S+)")
    if not method or not path then return nil end
    local headers = {}
    for i = 2, #lines do
        local name, value = lines[i]:match("^([^:]+):%s*(.*)$")
        if name then
            headers[name:lower()] = value
        end
    end
    return { method = method, url = path, headers = headers }
end

local function onConnection(socket)
    local buffer = ""
    local done = false

    local function onData(chunk)
        if done then return end
        buffer = buffer .. chunk
        if #buffer > 65536 then
            socket:destroy()
            return
        end
        local headerEnd = buffer:find("\r\n\r\n", 1, true)
        local sepLen = 4
        if not headerEnd then
            headerEnd = buffer:find("\n\n", 1, true)
            sepLen = 2
        end
        if not headerEnd then return end

        done = true
        local headerBlock = buffer:sub(1, headerEnd - 1)
        local leftover = buffer:sub(headerEnd + sepLen)
        socket:removeListener("data", onData)

        local req = parseHttpHeaders(headerBlock)
        if not req then
            writeHttp(socket, "400 Bad Request", { ["Content-Type"] = "text/plain" }, "Bad Request")
            return
        end

        if isWebSocketRequest(req) then
            handleUpgrade(req, socket, leftover)
            return
        end

        handleHttp(req, socket)
    end

    socket:on("data", onData)
    socket:on("error", function()
        pcall(function() socket:destroy() end)
    end)
end

local server = net.createServer(onConnection)

server:listen(config.serverPort, "0.0.0.0", function()
    util.log("Listening on port " .. tostring(config.serverPort))
    util.log("Web client http://localhost:" .. tostring(config.serverPort) .. "/")
    if not uv.fs_stat(CLIENT_ROOT) then
        util.log("LoveDiepClient not found at " .. CLIENT_ROOT)
    end
    GameServer:new(FFAArena, "FFA")
    GameServer:new(TeamsArena, "2TDM")
    GameServer:new(FourTeamsArena, "4TDM")
    GameServer:new(MazeArena, "Maze")
    GameServer:new(SurvivalArena, "Survival")
    GameServer:new(DominationArena, "Domination")
    GameServer:new(MothershipArena, "Mothership")
    GameServer:new(SandboxArena, "Sandbox")
    util.saveToLog("Servers up", "All servers booted up.", 0x37F554)
    util.log("Dumping endpoint -> gamemode routing table")
    for i = 1, #GameServer.games do
        local game = GameServer.games[i]
        local endpoint = ("localhost:%d/%s"):format(config.serverPort, game.gamemode)
        print("> " .. endpoint .. " -> " .. game.name)
    end
end)

process:on("error", function(err)
    util.log("Process error: " .. tostring(err))
end)
