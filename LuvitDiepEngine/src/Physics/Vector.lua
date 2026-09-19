--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")

local Vector = class()

function Vector:init(x, y)
    self.x = x or 0
    self.y = y or 0
end

function Vector.isFinite(vector)
    local x, y = vector.x, vector.y
    return x == x and y == y and x ~= math.huge and x ~= -math.huge and y ~= math.huge and y ~= -math.huge
end

function Vector.fromPolar(theta, distance)
    return Vector:new(distance * math.cos(theta), distance * math.sin(theta))
end

function Vector:set(vector)
    self.x = vector.x
    self.y = vector.y
end

function Vector:add(vector)
    self.x = self.x + vector.x
    self.y = self.y + vector.y
end

function Vector:subtract(vector)
    self.x = self.x - vector.x
    self.y = self.y - vector.y
end

function Vector:distanceToSQ(vector)
    local dx = vector.x - self.x
    local dy = vector.y - self.y
    return dx * dx + dy * dy
end

function Vector:get_magnitude()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

function Vector:set_magnitude(magnitude)
    local currentDir = self:get_angle()
    self.x = math.cos(currentDir) * magnitude
    self.y = math.sin(currentDir) * magnitude
end

function Vector:get_angle()
    return math.atan2(self.y, self.x)
end

function Vector:set_angle(angle)
    local currentMag = self:get_magnitude()
    self.x = math.cos(angle) * currentMag
    self.y = math.sin(angle) * currentMag
end

Vector.__index = function(self, k)
    if k == "magnitude" then
        return Vector.get_magnitude(self)
    elseif k == "angle" then
        return Vector.get_angle(self)
    end
    return rawget(Vector, k) or rawget(self, k)
end

Vector.__newindex = function(self, k, v)
    if k == "magnitude" then
        Vector.set_magnitude(self, v)
    elseif k == "angle" then
        Vector.set_angle(self, v)
    else
        rawset(self, k, v)
    end
end

return Vector
