--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local config = require("./config")

local util = {}

util.PI2 = math.pi * 2
util.SQRT1_2 = math.sqrt(0.5)
util.SQRT2 = math.sqrt(2)

local function timestamp()
    return os.date("%H:%M:%S")
end

function util.log(...)
    io.write("[" .. timestamp() .. "] ")
    local args = { ... }
    for i = 1, #args do
        if i > 1 then io.write(" ") end
        io.write(tostring(args[i]))
    end
    io.write("\n")
end

function util.warn(...)
    io.write("[" .. timestamp() .. "] WARNING: ")
    local args = { ... }
    for i = 1, #args do
        if i > 1 then io.write(" ") end
        io.write(tostring(args[i]))
    end
    io.write("\n")
end

function util.removeFast(array, index)
    if index < 1 or index > #array then
        error("Index out of range. In `removeFast`")
    end
    if index == #array then
        array[#array] = nil
    else
        array[index] = array[#array]
        array[#array] = nil
    end
end

function util.indexOf(array, value)
    for i = 1, #array do
        if array[i] == value then
            return i
        end
    end
    return -1
end

function util.includes(array, value)
    if not array then return false end
    local n = tonumber(value)
    for i = 1, #array do
        if array[i] == value or (n ~= nil and tonumber(array[i]) == n) then
            return true
        end
    end
    return false
end

function util.randomFrom(array)
    if not array or #array == 0 then return nil end
    return array[math.random(#array)]
end

function util.constrain(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function util.normalizeAngle(angle)
    return ((angle % util.PI2) + util.PI2) % util.PI2
end

function util.isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function util.saveToLog(title, description, color)
    print("[!] " .. title .. "\n :: " .. description)
end

function util.saveToVLog(text)
    if config.doVerboseLogs then
        print("[v] " .. text)
    end
end

function util.hasFlag(flags, flag)
    return bit.band(flags or 0, flag) ~= 0
end

function util.getRandomPosition(entity)
    local pos = entity:getWorldPosition()
    local physics = entity.physicsData.values
    local isRect = physics.sides == 2

    if isRect then
        pos.x = pos.x + (math.random() - 0.5) * physics.size
        pos.y = pos.y + (math.random() - 0.5) * physics.width
    else
        local radius = math.sqrt(math.random()) * physics.size
        local angle = math.random() * util.PI2
        pos.x = pos.x + math.cos(angle) * radius
        pos.y = pos.y + math.sin(angle) * radius
    end

    return pos
end

return util
