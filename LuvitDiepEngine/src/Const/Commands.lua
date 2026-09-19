--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local config = require("../config")
local util = require("../util")
local Entity = require("../Native/Entity")
local Enums = require("./Enums")
local TankDefs = require("./TankDefinitions")

local AccessLevel = config.AccessLevel
local ClientBound = Enums.ClientBound
local StatCount = Enums.StatCount
local EntityStateFlags = Enums.EntityStateFlags

local commandDefinitions = {
    game_set_tank = { id = "game_set_tank", usage = "[tank]", description = "Changes your tank to the given class", permissionLevel = AccessLevel.BetaAccess, isCheat = true },
    game_set_level = { id = "game_set_level", usage = "[level]", description = "Changes your level to the given integer", permissionLevel = AccessLevel.BetaAccess, isCheat = true },
    game_set_score = { id = "game_set_score", usage = "[score]", description = "Changes your score to the given integer", permissionLevel = AccessLevel.BetaAccess, isCheat = true },
    game_set_stat = { id = "game_set_stat", usage = "[stat num] [points]", description = "Set the value of the given attribute", permissionLevel = AccessLevel.FullAccess, isCheat = true },
    game_add_upgrade_points = { id = "game_add_upgrade_points", usage = "[points]", description = "Adds upgrade points", permissionLevel = AccessLevel.FullAccess, isCheat = true },
    game_teleport = { id = "game_teleport", usage = "[x] [y]", description = "Teleports you to the given position", permissionLevel = AccessLevel.FullAccess, isCheat = true },
    game_godmode = { id = "game_godmode", usage = "[?value]", description = "Toggles godmode.", permissionLevel = AccessLevel.FullAccess, isCheat = true },
    game_announce = { id = "game_announce", usage = "[message]", description = "Announce a message", permissionLevel = AccessLevel.FullAccess, isCheat = false },
    admin_summon = { id = "admin_summon", usage = "[entityName] [?count] [?x] [?y]", description = "Spawns entities at the given coordinates", permissionLevel = AccessLevel.FullAccess, isCheat = false },
    admin_kill_all = { id = "admin_kill_all", description = "Kills all living entities in the arena", permissionLevel = AccessLevel.FullAccess, isCheat = false },
    admin_kill_entity = { id = "admin_kill_entity", usage = "[entityName]", description = "Kills all entities of the given type", permissionLevel = AccessLevel.FullAccess, isCheat = false },
    admin_close_arena = { id = "admin_close_arena", description = "Closes the current arena", permissionLevel = AccessLevel.FullAccess, isCheat = false },
    game_achievement = { id = "game_achievement", usage = "[achievementName]", description = "Unlocks the given achievement", permissionLevel = AccessLevel.FullAccess, isCheat = false }
}

local commandCallbacks = {}

function commandCallbacks.game_set_tank(client, tankNameArg)
    local TankBody = require("../Entity/Tank/TankBody")
    local tankDef = TankDefs.getTankByName(tankNameArg)
    local player = client.camera and client.camera.cameraData.player
    if not Entity.exists(player) or not TankBody.isTank(player) then return "Spawn first" end
    if not tankDef then return "Unknown tank: " .. tostring(tankNameArg or "") end
    if tankDef.flags and tankDef.flags.devOnly and client.accessLevel ~= AccessLevel.FullAccess then
        return "That tank needs full access"
    end
    player:setTank(tankDef.id)
    return "Tank set to " .. tostring(tankDef.name)
end

function commandCallbacks.game_set_level(client, levelArg)
    local TankBody = require("../Entity/Tank/TankBody")
    local level = tonumber(levelArg)
    local player = client.camera and client.camera.cameraData.player
    if not Entity.exists(player) or not TankBody.isTank(player) then return "Spawn first" end
    if not level then return "Usage: game_set_level [level]" end
    if client.accessLevel ~= AccessLevel.FullAccess then
        level = math.min(config.maxPlayerLevel, level)
    end
    client.camera:setLevel(level)
    return "Level set to " .. tostring(level)
end

function commandCallbacks.game_set_score(client, scoreArg)
    local TankBody = require("../Entity/Tank/TankBody")
    local score = tonumber(scoreArg)
    local player = client.camera and client.camera.cameraData.player
    if not Entity.exists(player) or not TankBody.isTank(player) then return "Spawn first" end
    if not score then return "Usage: game_set_score [score]" end
    client.camera:setScore(score)
    return "Score set to " .. tostring(score)
end

function commandCallbacks.game_set_stat(client, statIdArg, statPointsArg)
    local TankBody = require("../Entity/Tank/TankBody")
    local statId = StatCount - tonumber(statIdArg)
    local statPoints = tonumber(statPointsArg)
    local player = client.camera and client.camera.cameraData.player
    if not statId or not statPoints or statId < 0 or statId >= StatCount then return end
    if not Entity.exists(player) or not TankBody.isTank(player) then return end
    client.camera:setStat(statId, statPoints)
end

function commandCallbacks.game_add_upgrade_points(client, pointsArg)
    local points = tonumber(pointsArg)
    if not points or not client.camera then return end
    client.camera.cameraData.statsAvailable = client.camera.cameraData.values.statsAvailable + points
end

function commandCallbacks.game_teleport(client, xArg, yArg)
    local ObjectEntity = require("../Entity/Object")
    local player = client.camera and client.camera.cameraData.player
    if not Entity.exists(player) or not ObjectEntity.isObject(player) then return end
    local x = tonumber(xArg)
    local y = tonumber(yArg)
    if not x or not y then return end
    player.positionData.x = x
    player.positionData.y = y
    player:setVelocity(0, 0)
    player.entityState = bit.bor(player.entityState, EntityStateFlags.needsCreate, EntityStateFlags.needsDelete)
end

function commandCallbacks.game_godmode(client, activeArg)
    local TankBody = require("../Entity/Tank/TankBody")
    local player = client.camera and client.camera.cameraData.player
    if not Entity.exists(player) or not TankBody.isTank(player) then return end
    if activeArg == "on" then
        player:setInvulnerability(true)
    elseif activeArg == "off" then
        player:setInvulnerability(false)
    else
        player:setInvulnerability(not player.isInvulnerable)
    end
    return "God mode: " .. (player.isInvulnerable and "ON" or "OFF")
end

function commandCallbacks.game_announce(client, message, color, time, id)
    if not client.game then return end
    client.game:broadcast()
        :u8(ClientBound.Notification)
        :stringNT(message or "")
        :u32(tonumber(color) or 0)
        :float(tonumber(time) or 15000)
        :stringNT(id or "")
        :send()
end

local function parseSummonCoord(arg, origin)
    if not arg or arg == "" then return origin or 0, true end
    if type(arg) == "string" and arg:sub(1, 1) == "~" then
        return (origin or 0) + (tonumber(arg:sub(2)) or 0), true
    end
    local n = tonumber(arg)
    if not n then return origin or 0, false end
    return n, true
end

function commandCallbacks.admin_summon(client, entityArg, countArg, xArg, yArg)
    local ObjectEntity = require("../Entity/Object")
    local count = tonumber(countArg) or 1
    local player = client.camera and client.camera.cameraData.player
    local originX, originY = 0, 0
    if Entity.exists(player) and ObjectEntity.isObject(player) then
        originX = player.positionData.values.x
        originY = player.positionData.values.y
    end
    local x, xOk = parseSummonCoord(xArg, (xArg and xArg:sub(1, 1) == "~") and originX or 0)
    local y, yOk = parseSummonCoord(yArg, (yArg and yArg:sub(1, 1) == "~") and originY or 0)
    local game = client.camera and client.camera.game
    local entities = {
        Defender = require("../Entity/Boss/Defender"),
        Summoner = require("../Entity/Boss/Summoner"),
        Guardian = require("../Entity/Boss/Guardian"),
        FallenOverlord = require("../Entity/Boss/FallenOverlord"),
        FallenBooster = require("../Entity/Boss/FallenBooster"),
        FallenAC = require("../Entity/Misc/Boss/FallenAC"),
        FallenSpike = require("../Entity/Misc/Boss/FallenSpike"),
        FallenMegaTrapper = require("../Entity/Misc/Boss/FallenMegaTrapper"),
        ArenaCloser = require("../Entity/Misc/ArenaCloser"),
        Crasher = require("../Entity/Shape/Crasher"),
        Pentagon = require("../Entity/Shape/Pentagon"),
        Square = require("../Entity/Shape/Square"),
        Triangle = require("../Entity/Shape/Triangle")
    }
    local TEntity = entities[entityArg]
    if not xOk or not yOk or not count or count < 0 or not game or not TEntity then
        return "Unknown entity or invalid args"
    end
    for _ = 1, count do
        local spawned = TEntity:new(game)
        spawned.positionData.values.x = x
        spawned.positionData.values.y = y
    end
    return "Spawned " .. tostring(count) .. " " .. tostring(entityArg)
end

function commandCallbacks.admin_kill_all(client)
    local LivingEntity = require("../Entity/Live")
    local PhysicsFlags = Enums.PhysicsFlags
    local game = client.camera and client.camera.game
    if not game then return end
    for id = 0, game.entities.lastId do
        local entity = game.entities.inner[id]
        if Entity.exists(entity) and LivingEntity.isLive(entity)
            and entity ~= (client.camera and client.camera.cameraData.player)
            and bit.band(entity.physicsData.values.flags, PhysicsFlags.showsOnMap) == 0 then
            entity:destroy()
        end
    end
end

function commandCallbacks.admin_kill_entity(client, entityArg)
    local game = client.camera and client.camera.game
    if not game then return end
    local LivingEntity = require("../Entity/Live")
    local TankBody = require("../Entity/Tank/TankBody")
    local AbstractBoss = require("../Entity/Boss/AbstractBoss")
    local AbstractShape = require("../Entity/Shape/AbstractShape")
    local ArenaCloser = require("../Entity/Misc/ArenaCloser")
    local match = ({
        ArenaCloser = ArenaCloser.isCloser,
        Tank = TankBody.isTank,
        Boss = AbstractBoss.isBoss,
        Shape = AbstractShape.isShape,
        Bullet = function(entity)
            return entity and entity.barrelEntity ~= nil and LivingEntity.isLive(entity)
        end
    })[entityArg]
    if not match then return "Unknown entity: " .. tostring(entityArg or "") end
    for id = 0, game.entities.lastId do
        local entity = game.entities.inner[id]
        if Entity.exists(entity) and match(entity) then
            entity:destroy()
        end
    end
end

function commandCallbacks.admin_close_arena(client)
    if client.camera then
        client.camera.game.arena:close()
    end
end

function commandCallbacks.game_achievement(client, nameArg)
    local Achievements = require("./Achievements")
    local achievement = Achievements.getByName(nameArg)
    if not achievement then return "Unknown achievement" end
    Achievements.sendAchievements(client, { achievement.hash })
    return "Unlocked " .. achievement.name
end

local function executeCommand(client, cmd, args)
    cmd = tostring(cmd or ""):lower()
    if not commandDefinitions[cmd] or not commandCallbacks[cmd] then
        util.saveToVLog(tostring(client) .. " tried to run the invalid command " .. tostring(cmd))
        return client:notify("Unknown command: " .. tostring(cmd), 0xFF0000, 4000, "cmd-err")
    end
    if client.accessLevel < commandDefinitions[cmd].permissionLevel then
        util.saveToVLog("command permission too low: " .. tostring(cmd))
        return client:notify("No permission for " .. tostring(cmd), 0xFF0000, 4000, "cmd-err")
    end
    if commandDefinitions[cmd].isCheat then client:setHasCheated(true) end
    local ok, response = pcall(commandCallbacks[cmd], client, unpack(args or {}))
    if not ok then
        return client:notify("Command error: " .. tostring(response), 0xFF0000, 5000, "cmd-err")
    end
    client:notify(response or ("OK: " .. cmd), 0x00FFA0, 4000, "cmd-callback" .. commandDefinitions[cmd].id)
end

return {
    commandDefinitions = commandDefinitions,
    executeCommand = executeCommand
}
