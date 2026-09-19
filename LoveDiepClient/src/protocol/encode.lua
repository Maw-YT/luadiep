local bit = require("bit")
local config = require("src.config")
local Writer = require("src.coder.writer")
local Enums = require("src.protocol.enums")

local Encode = {}

local function packet()
    return Writer:new()
end

function Encode.init(password)
    return packet():u8(Enums.ServerBound.Init):stringNT(config.buildHash):stringNT(password or ""):write()
end

function Encode.input(flags, mouseX, mouseY)
    return packet():u8(Enums.ServerBound.Input):vu(flags):vf(mouseX):vf(mouseY):write()
end

function Encode.spawn(name)
    return packet():u8(Enums.ServerBound.Spawn):stringNT(name or ""):write()
end

function Encode.ping()
    return packet():u8(Enums.ServerBound.Ping):write()
end

function Encode.statUpgrade(statId, tankCount)
    local xor = config.magicNum % 8
    return packet():u8(Enums.ServerBound.StatUpgrade):vi(bit.bxor(statId, xor)):write()
end

function Encode.tankUpgrade(tankId, tankCount)
    tankCount = tankCount or 1
    local xor = config.magicNum % tankCount
    return packet():u8(Enums.ServerBound.TankUpgrade):vi(bit.bxor(tankId, xor)):write()
end

function Encode.toRespawn()
    return packet():u8(Enums.ServerBound.ToRespawn):write()
end

function Encode.command(cmd, args)
    args = args or {}
    local n = #args
    if n > 255 then n = 255 end
    local w = packet():u8(Enums.ServerBound.TCPInit):stringNT(cmd or ""):u8(n)
    for i = 1, n do
        w:stringNT(tostring(args[i] or ""))
    end
    return w:write()
end

return Encode
