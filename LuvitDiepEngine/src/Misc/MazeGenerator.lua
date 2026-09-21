--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local MazeWall = require("../Entity/Misc/MazeWall")

local MAZE_CELL_EMPTY = 0
local MAZE_CELL_WALL = 1
local MAZE_CELL_ACCESSIBLE = 2
local MAZE_CELL_PLACED_WALL = 3

local DIRECTION = {
    { -1, 0 }, { 1, 0 },
    { 0, -1 }, { 0, 1 }
}

local MazeGenerator = class()

local function perpendicular(dir)
    local out = {}
    for i = 1, #DIRECTION do
        local a = DIRECTION[i]
        if a[1] ~= dir[1] and a[2] ~= dir[2] then
            out[#out + 1] = a
        end
    end
    return out
end

function MazeGenerator:init(config)
    self.config = config
    self.maze = {}
    local n = config.size * config.size
    for i = 0, n - 1 do
        self.maze[i] = MAZE_CELL_EMPTY
    end
end

function MazeGenerator:get(x, y)
    if x < 0 or y < 0 or x >= self.config.size or y >= self.config.size then
        return nil
    end
    return self.maze[y * self.config.size + x] or MAZE_CELL_EMPTY
end

function MazeGenerator:set(x, y, value)
    if x < 0 or y < 0 or x >= self.config.size or y >= self.config.size then
        return value
    end
    self.maze[y * self.config.size + x] = value
    return value
end

function MazeGenerator:isCellOccupied(x, y)
    return self:get(x, y) == MAZE_CELL_PLACED_WALL
end

function MazeGenerator:mapValues()
    local values = {}
    local size = self.config.size
    for i = 0, size * size - 1 do
        values[#values + 1] = { i % size, math.floor(i / size), self.maze[i] or 0 }
    end
    return values
end

function MazeGenerator:generate()
    local seeds = {}
    local seedCount = self.config.baseSeedCount + math.floor((math.random() - 0.5) * self.config.seedCountVariation)
    local maxSeedCount = self.config.baseSeedCount + self.config.seedCountVariation
    local size = self.config.size

    for _ = 1, 10000 do
        if #seeds >= seedCount then break end
        local seed = {
            x = math.floor((math.random() * size) - 1),
            y = math.floor((math.random() * size) - 1)
        }
        local tooClose = false
        for i = 1, #seeds do
            local a = seeds[i]
            if math.abs(seed.x - a.x) <= 3 and math.abs(seed.y - a.y) <= 3 then
                tooClose = true
                break
            end
        end
        if not tooClose and not (seed.x <= 0 or seed.y <= 0 or seed.x >= size - 1 or seed.y >= size - 1) then
            seeds[#seeds + 1] = seed
            self:set(seed.x, seed.y, MAZE_CELL_WALL)
        end
    end

    for si = 1, #seeds do
        local seed = seeds[si]
        local dir = DIRECTION[math.random(4)]
        local termination = 1
        while termination >= self.config.terminationChance do
            termination = math.random()
            seed.x = seed.x + dir[1]
            seed.y = seed.y + dir[2]
            if seed.x <= 0 or seed.y <= 0 or seed.x >= size - 1 or seed.y >= size - 1 then
                break
            end
            self:set(seed.x, seed.y, MAZE_CELL_WALL)
            if math.random() <= self.config.branchChance then
                if #seeds <= maxSeedCount then
                    local sides = perpendicular(dir)
                    local side = sides[math.random(#sides)]
                    local newSeed = {
                        x = seed.x + side[1],
                        y = seed.y + side[2]
                    }
                    seeds[#seeds + 1] = newSeed
                    self:set(seed.x, seed.y, MAZE_CELL_WALL)
                end
            elseif math.random() <= self.config.turnChance then
                local sides = perpendicular(dir)
                dir = sides[math.random(#sides)]
            end
        end
    end

    for _ = 1, 10 do
        local seed = {
            x = math.floor((math.random() * size) - 1),
            y = math.floor((math.random() * size) - 1)
        }
        local tooClose = false
        local cells = self:mapValues()
        for i = 1, #cells do
            local x, y, value = cells[i][1], cells[i][2], cells[i][3]
            if value == MAZE_CELL_WALL and math.abs(seed.x - x) <= 3 and math.abs(seed.y - y) <= 3 then
                tooClose = true
                break
            end
        end
        if not tooClose and not (seed.x <= 0 or seed.y <= 0 or seed.x >= size - 1 or seed.y >= size - 1) then
            self:set(seed.x, seed.y, MAZE_CELL_WALL)
        end
    end

    local queue = { { 0, 0 } }
    local qi = 1
    self:set(0, 0, MAZE_CELL_ACCESSIBLE)
    local checked = { [0] = true }
    local steps = 0
    while qi <= #queue and steps < 3000 do
        steps = steps + 1
        local cell = queue[qi]
        qi = qi + 1
        local x, y = cell[1], cell[2]
        local neighbors = {
            { x - 1, y },
            { x + 1, y },
            { x, y - 1 },
            { x, y + 1 }
        }
        for n = 1, 4 do
            local nx, ny = neighbors[n][1], neighbors[n][2]
            if nx >= 0 and ny >= 0 and nx < size and ny < size then
                if self:get(nx, ny) == MAZE_CELL_EMPTY then
                    local idx = ny * size + nx
                    if not checked[idx] then
                        checked[idx] = true
                        queue[#queue + 1] = { nx, ny }
                        self:set(nx, ny, MAZE_CELL_ACCESSIBLE)
                    end
                end
            end
        end
    end

    local cells = self:mapValues()
    for i = 1, #cells do
        local x, y, value = cells[i][1], cells[i][2], cells[i][3]
        if value ~= MAZE_CELL_WALL and value ~= MAZE_CELL_ACCESSIBLE then
            self:set(x, y, MAZE_CELL_WALL)
        end
    end
end

function MazeGenerator:convertToWalls()
    local cells = self:mapValues()
    for i = 1, #cells do
        if cells[i][3] == MAZE_CELL_PLACED_WALL then
            self:set(cells[i][1], cells[i][2], MAZE_CELL_WALL)
        end
    end

    local walls = {}
    local size = self.config.size
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            if self:get(x, y) == MAZE_CELL_WALL then
                local chunk = { x = x, y = y, width = 0, height = 1 }
                while self:get(x + chunk.width, y) == MAZE_CELL_WALL do
                    self:set(x + chunk.width, y, MAZE_CELL_PLACED_WALL)
                    chunk.width = chunk.width + 1
                end
                while true do
                    local canGrow = true
                    for i = 0, chunk.width - 1 do
                        if self:get(x + i, y + chunk.height) ~= MAZE_CELL_WALL then
                            canGrow = false
                            break
                        end
                    end
                    if not canGrow then break end
                    for i = 0, chunk.width - 1 do
                        self:set(x + i, y + chunk.height, MAZE_CELL_PLACED_WALL)
                    end
                    chunk.height = chunk.height + 1
                end
                walls[#walls + 1] = chunk
            end
        end
    end
    return walls
end

function MazeGenerator:scaleGridToArenaPosition(arena, gridX, gridY)
    local gridCellWidth = arena.width / self.config.size
    local gridCellHeight = arena.height / self.config.size
    return {
        x = gridX * gridCellWidth + arena.arenaData.values.leftX,
        y = gridY * gridCellHeight + arena.arenaData.values.topY
    }
end

function MazeGenerator:scaleArenaToGridPosition(arena, x, y)
    local gridCellWidth = arena.width / self.config.size
    local gridCellHeight = arena.height / self.config.size
    return {
        gridX = (x + arena.width / 2) / gridCellWidth,
        gridY = (y + arena.height / 2) / gridCellHeight
    }
end

function MazeGenerator:getGridCell(arena, x, y)
    local scaled = self:scaleArenaToGridPosition(arena, x, y)
    return {
        gridX = math.floor(scaled.gridX),
        gridY = math.floor(scaled.gridY)
    }
end

function MazeGenerator:buildWallFromGridCoord(arena, gridX, gridY, gridW, gridH)
    local minPos = self:scaleGridToArenaPosition(arena, gridX, gridY)
    local maxPos = self:scaleGridToArenaPosition(arena, gridX + gridW, gridY + gridH)
    return MazeWall.newFromBounds(arena, minPos.x, minPos.y, maxPos.x, maxPos.y)
end

function MazeGenerator:placeWalls(arena)
    local walls = self:convertToWalls()
    for i = 1, #walls do
        local wall = walls[i]
        self:buildWallFromGridCoord(arena, wall.x, wall.y, wall.width, wall.height)
    end
end

return MazeGenerator
