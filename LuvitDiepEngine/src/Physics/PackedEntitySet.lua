--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")

local MAX_ENTITY_COUNT = 16384
local SET_WORD_COUNT = math.ceil(MAX_ENTITY_COUNT / 32)

local PackedEntitySet = class()

function PackedEntitySet:init()
    self.data = {}
    for i = 0, SET_WORD_COUNT - 1 do
        self.data[i] = 0
    end
end

function PackedEntitySet:add(entityId)
    local wordIndex = bit.rshift(entityId, 5)
    local bitIndex = bit.band(entityId, 31)
    self.data[wordIndex] = bit.bor(self.data[wordIndex], bit.lshift(1, bitIndex))
end

function PackedEntitySet:remove(entityId)
    local wordIndex = bit.rshift(entityId, 5)
    local bitIndex = bit.band(entityId, 31)
    self.data[wordIndex] = bit.band(self.data[wordIndex], bit.bnot(bit.lshift(1, bitIndex)))
end

function PackedEntitySet:has(entityId)
    local wordIndex = bit.rshift(entityId, 5)
    local bitIndex = bit.band(entityId, 31)
    return bit.band(self.data[wordIndex], bit.lshift(1, bitIndex)) ~= 0
end

function PackedEntitySet:clear()
    for i = 0, SET_WORD_COUNT - 1 do
        self.data[i] = 0
    end
end

function PackedEntitySet:forEach(fn)
    for i = 0, SET_WORD_COUNT - 1 do
        local chunk = self.data[i]
        while chunk ~= 0 do
            local bitValue = bit.band(chunk, -chunk)
            local bitIdx = 0
            local v = bit.tobit(bitValue)
            if v ~= 0 then
                while bit.band(v, 1) == 0 do
                    v = bit.rshift(v, 1)
                    bitIdx = bitIdx + 1
                end
            end
            chunk = bit.bxor(chunk, bitValue)
            fn(32 * i + bitIdx)
        end
    end
end

PackedEntitySet.SET_WORD_COUNT = SET_WORD_COUNT
PackedEntitySet.MAX_ENTITY_COUNT = MAX_ENTITY_COUNT

return PackedEntitySet
