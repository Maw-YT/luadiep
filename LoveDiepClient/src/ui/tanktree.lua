local Render = require("src.render")
local Layout = require("src.ui.layout")

local TankTree = {}

local function metrics()
    return Layout.metrics()
end

local function screenToGui(x, y)
    return Layout.screenToGui(x, y)
end

local NODE_W = 92
local NODE_H = 108
local COL_GAP = 36
local ROW_GAP = 10
local MIN_ZOOM = 0.12
local MAX_ZOOM = 2.8
local PAD_TOP = 64
local PANEL_H = 90

local cache = { key = nil, nodes = nil, contentW = 0, contentH = 0, parents = nil }

local function txt(s)
    return Render.safeText(s)
end

local function upgradeIds(def)
    local list = {}
    if type(def) ~= "table" or type(def.upgrades) ~= "table" then
        return list
    end
    for i = 1, #def.upgrades do
        local id = tonumber(def.upgrades[i])
        if id then
            list[#list + 1] = id
        end
    end
    if #list == 0 then
        for _, uid in pairs(def.upgrades) do
            local id = tonumber(uid)
            if id then
                list[#list + 1] = id
            end
        end
    end
    return list
end

local function usable(def)
    if type(def) ~= "table" then return false end
    if type(def.name) ~= "string" or def.name == "" then return false end
    if def.flags and def.flags.devOnly then return false end
    return true
end

local function build(tanksById)
    local children, parents = {}, {}
    local seen = { [0] = true }
    local queue = { 0 }
    while #queue > 0 do
        local id = table.remove(queue, 1)
        local def = tanksById[id]
        local kids = {}
        children[id] = kids
        if def then
            local ups = upgradeIds(def)
            for i = 1, #ups do
                local uid = ups[i]
                local ud = tanksById[uid]
                if usable(ud) then
                    kids[#kids + 1] = uid
                    if not parents[uid] then
                        parents[uid] = id
                    end
                    if not seen[uid] then
                        seen[uid] = true
                        queue[#queue + 1] = uid
                    end
                end
            end
        end
    end
    return children, parents
end

local function layout(tanksById)
    local children, parents = build(tanksById)
    local nodes = {}
    local leafY = 0

    local function walk(id, depth)
        local kids = children[id] or {}
        local x = depth * (NODE_W + COL_GAP)
        if #kids == 0 then
            nodes[id] = { x = x, y = leafY, kids = kids }
            leafY = leafY + NODE_H + ROW_GAP
            return nodes[id].y, nodes[id].y + NODE_H
        end
        local minY, maxY = math.huge, -math.huge
        for i = 1, #kids do
            local a, b = walk(kids[i], depth + 1)
            if a < minY then minY = a end
            if b > maxY then maxY = b end
        end
        local y = (minY + maxY) * 0.5 - NODE_H * 0.5
        nodes[id] = { x = x, y = y, kids = kids }
        if y < minY then minY = y end
        if y + NODE_H > maxY then maxY = y + NODE_H end
        return minY, maxY
    end

    local _, bottom = walk(0, 0)
    local maxX = 0
    for _, n in pairs(nodes) do
        if n.x > maxX then maxX = n.x end
    end
    return nodes, maxX + NODE_W, math.max(bottom, leafY), parents
end

local function ensure(game)
    local key = tostring(game.tanksById)
    if cache.key == key and cache.nodes then
        return cache.nodes, cache.contentW, cache.contentH, cache.parents
    end
    local nodes, w, h, parents = layout(game.tanksById or {})
    cache.key, cache.nodes, cache.contentW, cache.contentH, cache.parents = key, nodes, w, h, parents
    return nodes, w, h, parents
end

local function viewSize()
    local _, _, _, sw, sh = metrics()
    return sw, sh
end

local function origin(game, sw, sh)
    local z = game.treeZoom or 1
    local ox = sw * 0.5 - (game.treeCamX or 0) * z
    local oy = (PAD_TOP + sh) * 0.5 - (game.treeCamY or 0) * z
    return ox, oy, z
end

function TankTree.fit(game, sw, sh)
    local _, cw, ch = ensure(game)
    sw = sw or select(1, viewSize())
    sh = sh or select(2, viewSize())
    local vw, vh = sw - 40, sh - PAD_TOP - 72
    local z = math.min(vw / math.max(cw, 1), vh / math.max(ch, 1)) * 0.92
    if z > 1 then z = 1 end
    if z < MIN_ZOOM then z = MIN_ZOOM end
    game.treeZoom = z
    game.treeCamX = cw * 0.5
    game.treeCamY = ch * 0.5
end

function TankTree.toggle(game)
    game.treeOpen = not game.treeOpen
    if game.treeOpen then
        game.optionsOpen = false
        game.styleMenuOpen = false
        game.treeDragging = false
        game.treeNeedFit = true
        game.treeSelected = game.treeSelected or 0
    end
end

function TankTree.setZoom(game, zoom, gx, gy, sw, sh)
    sw, sh = sw or select(1, viewSize()), sh or select(2, viewSize())
    local z0 = game.treeZoom or 1
    local z1 = math.max(MIN_ZOOM, math.min(MAX_ZOOM, zoom))
    if z1 == z0 then return end
    if gx and gy then
        local ox, oy = origin(game, sw, sh)
        local wx = (gx - ox) / z0
        local wy = (gy - oy) / z0
        game.treeZoom = z1
        game.treeCamX = wx - (gx - sw * 0.5) / z1
        game.treeCamY = wy - (gy - (PAD_TOP + sh) * 0.5) / z1
    else
        game.treeZoom = z1
    end
end

function TankTree.wheel(game, dx, dy, x, y)
    if not game.treeOpen then return end
    local gx, gy = screenToGui(x or love.mouse.getX(), y or love.mouse.getY())
    local sw, sh = viewSize()
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        local z = game.treeZoom or 1
        game.treeCamX = (game.treeCamX or 0) - (dy or 0) * 48 / z
        game.treeCamY = (game.treeCamY or 0) - (dx or 0) * 48 / z
    else
        local factor = ((dy or 0) > 0) and 1.12 or (((dy or 0) < 0) and (1 / 1.12) or 1)
        if factor ~= 1 then
            TankTree.setZoom(game, (game.treeZoom or 1) * factor, gx, gy, sw, sh)
        end
        if dx and dx ~= 0 then
            game.treeCamX = (game.treeCamX or 0) - dx * 48 / (game.treeZoom or 1)
        end
    end
end

local function inChrome(gx, gy, sw, sh)
    if gy < PAD_TOP then return true end
    if gy > sh - PANEL_H - 18 then return true end
    return false
end

local function hitNode(game, gx, gy, sw, sh)
    if inChrome(gx, gy, sw, sh) then return nil end
    local nodes = ensure(game)
    local ox, oy, z = origin(game, sw, sh)
    local hit, best = nil, -1
    for id, n in pairs(nodes) do
        local x, y = ox + n.x * z, oy + n.y * z
        local w, h = NODE_W * z, NODE_H * z
        if gx >= x and gy >= y and gx <= x + w and gy <= y + h then
            if z > best then
                hit, best = id, z
            end
        end
    end
    return hit
end

function TankTree.mousepressed(game, gx, gy, button)
    if not game.treeOpen then return false end
    local sw, sh = viewSize()
    if inChrome(gx, gy, sw, sh) then
        return false
    end
    if button ~= 1 and button ~= 2 and button ~= 3 then
        return true
    end
    game.treeDragX, game.treeDragY = gx, gy
    game.treeDragging = false
    game.treeDragButton = button
    game.treePressNode = hitNode(game, gx, gy, sw, sh)
    return true
end

function TankTree.mousemoved(game, gx, gy)
    if not game.treeOpen then return end
    if not game.treeDragButton then
        game.treeHover = hitNode(game, gx, gy, viewSize())
        return
    end
    local dx = gx - (game.treeDragX or gx)
    local dy = gy - (game.treeDragY or gy)
    if not game.treeDragging and (dx * dx + dy * dy) > 16 then
        game.treeDragging = true
    end
    if game.treeDragging then
        local z = game.treeZoom or 1
        game.treeCamX = (game.treeCamX or 0) - dx / z
        game.treeCamY = (game.treeCamY or 0) - dy / z
        game.treeDragX, game.treeDragY = gx, gy
    else
        game.treeHover = hitNode(game, gx, gy, viewSize())
    end
end

local function focusNode(game, id)
    local nodes = ensure(game)
    local n = nodes[id]
    if not n then return end
    game.treeCamX = n.x + NODE_W * 0.5
    game.treeCamY = n.y + NODE_H * 0.5
    game.treeZoom = math.min(1.25, MAX_ZOOM)
end

function TankTree.mousereleased(game, gx, gy, button)
    if not game.treeOpen then return end
    if button ~= game.treeDragButton then return end
    if not game.treeDragging and button == 1 then
        local id = hitNode(game, gx, gy, viewSize())
        if id then
            local now = love.timer.getTime()
            if game.treeSelected == id and now - (game.treeClickAt or 0) < 0.35 then
                focusNode(game, id)
            end
            game.treeSelected = id
            game.treeClickAt = now
        end
    end
    game.treeDragging = false
    game.treeDragButton = nil
end

function TankTree.update(game, dt)
    if not game.treeOpen then return end
    if game.treeDragButton and not love.mouse.isDown(game.treeDragButton) then
        game.treeDragging = false
        game.treeDragButton = nil
    end
    local z = game.treeZoom or 1
    local pan = 420 * dt / z
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        pan = pan * 2.2
    end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        game.treeCamX = (game.treeCamX or 0) - pan
    end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        game.treeCamX = (game.treeCamX or 0) + pan
    end
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        game.treeCamY = (game.treeCamY or 0) - pan
    end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        game.treeCamY = (game.treeCamY or 0) + pan
    end
end

function TankTree.keypressed(game, key)
    if not game.treeOpen then return false end
    local sw, sh = viewSize()
    local gx, gy = screenToGui(love.mouse.getPosition())
    if key == "=" or key == "+" or key == "kp+" then
        TankTree.setZoom(game, (game.treeZoom or 1) * 1.18, gx, gy, sw, sh)
        return true
    elseif key == "-" or key == "kp-" then
        TankTree.setZoom(game, (game.treeZoom or 1) / 1.18, gx, gy, sw, sh)
        return true
    elseif key == "0" or key == "kp0" then
        TankTree.setZoom(game, 1, nil, nil, sw, sh)
        return true
    elseif key == "f" then
        TankTree.fit(game, sw, sh)
        return true
    elseif key == "r" then
        game.treeSelected = 0
        TankTree.fit(game, sw, sh)
        return true
    end
    return false
end

function TankTree.draw(game, buttons, sw, sh, box)
    if not game.treeOpen then return end
    if game.treeNeedFit or not game.treeZoom then
        TankTree.fit(game, sw, sh)
        game.treeNeedFit = false
    end

    local nodes, _, _, parents = ensure(game)
    local ox, oy, z = origin(game, sw, sh)
    local tanksById = game.tanksById or {}
    local mx, my = screenToGui(love.mouse.getPosition())
    if not game.treeDragButton then
        game.treeHover = hitNode(game, mx, my, sw, sh)
    end

    box(buttons, 0, 0, sw, sh, function() end, "treeback", "arrow")

    love.graphics.setColor(0.05, 0.06, 0.08, 0.62)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local pad = 40
    local vx0 = (-ox - pad) / z
    local vy0 = (PAD_TOP - 6 - oy - pad) / z
    local vx1 = (sw - ox + pad) / z
    local vy1 = (sh - oy + pad) / z
    local function nodeVisible(n)
        return n.x + NODE_W >= vx0 and n.x <= vx1 and n.y + NODE_H >= vy0 and n.y <= vy1
    end

    local function tool(x, y, w, h, label, fn, key)
        love.graphics.setColor(0.12, 0.16, 0.22, 0.96)
        love.graphics.rectangle("fill", x, y, w, h, 8, 8)
        love.graphics.setColor(1, 1, 1, 0.16)
        love.graphics.rectangle("line", x, y, w, h, 8, 8)
        love.graphics.setColor(1, 1, 1, 0.95)
        Render.printf(label, x, y + 6, w, "center")
        return { x = x, y = y, w = w, h = h, fn = fn, key = key }
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.translate(24, 12)
    love.graphics.scale(1.15, 1.15)
    Render.print("Tank Tree", 0, 0)
    love.graphics.pop()

    local gx, gy = screenToGui(love.mouse.getPosition())
    local tools = {
        tool(24, 36, 56, 24, "Fit", function()
            TankTree.fit(game, sw, sh)
        end, "treefit"),
        tool(86, 36, 70, 24, "100%", function()
            TankTree.setZoom(game, 1)
        end, "tree100"),
        tool(162, 36, 28, 24, "+", function()
            TankTree.setZoom(game, (game.treeZoom or 1) * 1.18, gx, gy, sw, sh)
        end, "treein"),
        tool(196, 36, 28, 24, "-", function()
            TankTree.setZoom(game, (game.treeZoom or 1) / 1.18, gx, gy, sw, sh)
        end, "treeout"),
        tool(sw - 88, 12, 64, 28, "Close", function()
            game.treeOpen = false
        end, "treeclose")
    }

    love.graphics.setColor(0.62, 0.70, 0.78, 0.92)
    Render.printf("wheel zoom   drag pan   WASD  +/-   F fit   0 100%   R reset   dbl-click focus   Y/Esc", 230, 16, sw - 330, "right")
    love.graphics.setColor(0.78, 0.84, 0.90, 0.85)
    Render.printf(string.format("%.0f%%", (game.treeZoom or 1) * 100), 230, 36, sw - 330, "right")

    local scale, sox, soy = metrics()
    love.graphics.setScissor(sox, soy + (PAD_TOP - 6) * scale, sw * scale, (sh - (PAD_TOP - 6)) * scale)
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(z, z)

    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2 / z)
    love.graphics.setColor(1, 1, 1, 0.18)
    for _, n in pairs(nodes) do
        local x1 = n.x + NODE_W
        local y1 = n.y + 40
        for i = 1, #(n.kids or {}) do
            local kid = nodes[n.kids[i]]
            if kid and (nodeVisible(n) or nodeVisible(kid)) then
                local x2 = kid.x
                local y2 = kid.y + 40
                local mxid = (x1 + x2) * 0.5
                love.graphics.line(x1, y1, mxid, y1, mxid, y2, x2, y2)
            end
        end
    end

    local selected = game.treeSelected
    local hover = game.treeHover
    for id, n in pairs(nodes) do
        local def = tanksById[id]
        if def and nodeVisible(n) then
            local hi = (selected == id) or (hover == id)
            if selected == id then
                love.graphics.setColor(0.16, 0.55, 0.85, 0.95)
                love.graphics.rectangle("fill", n.x - 3, n.y - 3, NODE_W + 6, NODE_H + 6, 12, 12)
            elseif hover == id then
                love.graphics.setColor(1, 1, 1, 0.14)
                love.graphics.rectangle("fill", n.x - 2, n.y - 2, NODE_W + 4, NODE_H + 4, 12, 12)
            end
            love.graphics.setColor(0.08, 0.10, 0.13, hi and 0.98 or 0.92)
            love.graphics.rectangle("fill", n.x, n.y, NODE_W, NODE_H, 10, 10)
            love.graphics.setColor(1, 1, 1, hi and 0.22 or 0.10)
            love.graphics.rectangle("line", n.x, n.y, NODE_W, NODE_H, 10, 10)
            Render.drawTankIcon(def, n.x + NODE_W * 0.5, n.y + 40, 70, 1)
            if z >= 0.38 then
                love.graphics.setColor(1, 1, 1, 0.95)
                Render.outlinedPrintf(txt(def.name), n.x + 4, n.y + NODE_H - 22, NODE_W - 8, "center", 1)
            end
        end
    end
    love.graphics.pop()
    love.graphics.setScissor()

    local canvasTop, canvasBot = PAD_TOP, sh - PANEL_H - 18
    for id, n in pairs(nodes) do
        if tanksById[id] then
            local x, y = ox + n.x * z, oy + n.y * z
            local w, h = NODE_W * z, NODE_H * z
            local y1 = math.max(y, canvasTop)
            local y2 = math.min(y + h, canvasBot)
            if y2 > y1 and x < sw and x + w > 0 then
                box(buttons, x, y1, w, y2 - y1, function() end, "treenode" .. id, "hand")
            end
        end
    end

    local sel = tanksById[selected]
    if sel then
        local panelH = PANEL_H
        local py = sh - panelH - 12
        love.graphics.setColor(0.07, 0.08, 0.10, 0.94)
        love.graphics.rectangle("fill", 16, py, sw - 32, panelH, 12, 12)
        love.graphics.setColor(1, 1, 1, 0.10)
        love.graphics.rectangle("line", 16, py, sw - 32, panelH, 12, 12)

        Render.drawTankIcon(sel, 64, py + panelH * 0.5, 78, 1)
        love.graphics.setColor(1, 1, 1, 1)
        local title = txt(sel.name)
        local lvl = tonumber(sel.levelRequirement) or 0
        if lvl > 0 then
            title = title .. "   Lv " .. tostring(lvl)
        end
        Render.outlinedPrint(title, 110, py + 14, 2)

        local bits = {}
        local pid = parents and parents[selected]
        if pid and tanksById[pid] then
            bits[#bits + 1] = "From " .. txt(tanksById[pid].name)
        end
        local ups = {}
        for i = 1, #(nodes[selected] and nodes[selected].kids or {}) do
            local kid = tanksById[nodes[selected].kids[i]]
            if kid then ups[#ups + 1] = txt(kid.name) end
        end
        if #ups > 0 then
            bits[#bits + 1] = "Into " .. table.concat(ups, ", ")
        else
            bits[#bits + 1] = "No further upgrades"
        end
        love.graphics.setColor(0.75, 0.82, 0.90, 0.9)
        Render.print(table.concat(bits, "    ·    "), 110, py + 40)
        local msg = sel.upgradeMessage
        if type(msg) == "string" and msg ~= "" then
            love.graphics.setColor(0.95, 0.85, 0.45, 0.95)
            Render.print(txt(msg), 110, py + 58)
        end
        box(buttons, 16, py, sw - 32, panelH, function() end, "treedetail", "arrow")
    end

    for i = 1, #tools do
        local t = tools[i]
        box(buttons, t.x, t.y, t.w, t.h, t.fn, t.key, "hand")
    end
end

return TankTree
