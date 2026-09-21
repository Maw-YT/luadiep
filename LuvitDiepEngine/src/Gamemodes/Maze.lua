--[[
    LuvitDiepEngine - Luvit port of diepcustom
    Licensed under AGPL-3.0.
]]

local class = require("../class")
local ArenaEntity = require("../Native/Arena")
local ShapeManager = require("../Misc/ShapeManager")
local MazeGenerator = require("../Misc/MazeGenerator")

local MazeShapeManager = class(ShapeManager)
function MazeShapeManager:wantedShapes()
    return 1300
end

local GRID_SIZE = 40
local CELL_SIZE = 635
local ARENA_SIZE = GRID_SIZE * CELL_SIZE

local MazeArena = class(ArenaEntity)
MazeArena.GAMEMODE_ID = "maze"

function MazeArena:init(game)
    ArenaEntity.init(self, game)
    self.shapes = MazeShapeManager:new(self)
    self:updateBounds(ARENA_SIZE, ARENA_SIZE)
    self.mazeGenerator = MazeGenerator:new({
        size = GRID_SIZE,
        baseSeedCount = 45,
        seedCountVariation = 30,
        turnChance = 0.2,
        branchChance = 0.2,
        terminationChance = 0.2
    })
    self.mazeGenerator:generate()
    self.mazeGenerator:placeWalls(self)
    self.bossManager = nil
end

function MazeArena:isValidSpawnLocation(x, y)
    local cell = self.mazeGenerator:getGridCell(self, x, y)
    if cell.gridX < 0 or cell.gridY < 0 or cell.gridX >= GRID_SIZE or cell.gridY >= GRID_SIZE then
        return false
    end
    return self.mazeGenerator:isCellOccupied(cell.gridX, cell.gridY) == false
end

return MazeArena
