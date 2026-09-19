--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")

local FFAArena = class(ArenaEntity)
FFAArena.GAMEMODE_ID = "ffa"

return FFAArena
