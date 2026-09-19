--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Copyright (C) 2022 ABCxFF (github.com/ABCxFF)
    Ported to Luvit/LuaJIT.

    Licensed under the GNU Affero General Public License v3.0.
]]

local function class(base)
    local cls = {}
    cls.__index = cls
    cls.__base = base
    if base then
        setmetatable(cls, { __index = base })
    end

    function cls:new(...)
        local inst = setmetatable({}, cls)
        if inst.init then
            inst:init(...)
        end
        return inst
    end

    return cls
end

return class
