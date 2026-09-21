local Enums = require("src.protocol.enums")
local Render = require("src.render")
local State = require("src.ui.state")
local Layout = require("src.ui.layout")

local W = {}
W.PhysicsFlags = Enums.PhysicsFlags
W.NameFlags = Enums.NameFlags
W.State = State
W.anim = State.anim

local STAT_COLORS = {
    [0] = { 0.18, 0.72, 0.92, 0.95 },
    [1] = { 0.98, 0.82, 0.22, 0.95 },
    [2] = { 0.94, 0.32, 0.33, 0.95 },
    [3] = { 1.00, 0.55, 0.20, 0.95 },
    [4] = { 0.22, 0.52, 0.95, 0.95 },
    [5] = { 0.75, 0.48, 0.96, 0.95 },
    [6] = { 0.18, 0.86, 0.42, 0.95 },
    [7] = { 0.98, 0.42, 0.70, 0.95 }
}

local function statFill(i, can)
    local c = STAT_COLORS[i] or { 0.18, 0.52, 0.82, 0.95 }
    if can then
        local pulse = 0.5 + 0.5 * math.sin(State.anim.pulse * 5.2)
        return {
            math.min(1, c[1] + 0.10 * pulse),
            math.min(1, c[2] + 0.08 * pulse),
            math.min(1, c[3] + 0.06 * pulse),
            0.95
        }
    end
    return {
        c[1] * 0.38 + 0.10,
        c[2] * 0.38 + 0.10,
        c[3] * 0.38 + 0.10,
        0.9
    }
end

local function box(list, x, y, w, h, click, key, cursor)
    local c = cursor or "hand"
    list[#list + 1] = {
        x = x, y = y, w = w, h = h,
        click = click or function() end,
        key = key or (#list + 1),
        cursor = c,
        press = c == "hand" and key ~= "death"
    }
end

local function inRect(b, x, y, pad)
    pad = pad or 0
    return x >= b.x - pad and y >= b.y - pad and x <= b.x + b.w + pad and y <= b.y + b.h + pad
end

local function roundrect(x, y, w, h, r, mode)
    love.graphics.rectangle(mode or "fill", x, y, w, h, r or 6, r or 6)
end

local function pressDown(key)
    local p = State.presses[key]
    return (p and p.down) or 0
end

local function buttonShadow(x, y, w, h, r, alpha, key)
    alpha = alpha or 1
    local lip = h * 0.2 * (1 - pressDown(key))
    if lip < 0.4 then return end
    love.graphics.stencil(function()
        roundrect(x, y, w, h, r)
    end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(0, 0, 0, 0.32 * alpha)
    love.graphics.rectangle("fill", x, y + h - lip, w, lip)
    love.graphics.setStencilTest()
end

local function darkenRgb(r, g, b, f)
    f = f or 0.62
    return r * f, g * f, b * f
end

local function buttonOutline(x, y, w, h, r, alpha, fr, fg, fb)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2.4)
    local dr, dg, db = darkenRgb(fr or 0.2, fg or 0.2, fb or 0.2, 0.62)
    love.graphics.setColor(dr, dg, db, alpha or 1)
    roundrect(x, y, w, h, r, "line")
end

local function buttonFlash(x, y, w, h, r, key, alpha)
    local p = State.presses[key]
    if not p or p.flash <= 0.02 then return end
    love.graphics.setColor(1, 1, 1, 0.58 * p.flash * (alpha or 1))
    roundrect(x, y, w, h, r)
end

local function txt(s)
    return Render.safeText(s)
end

local function drawCogIcon(cx, cy, r)
    local teeth = 8
    love.graphics.push()
    love.graphics.translate(cx, cy)
    for i = 0, teeth - 1 do
        love.graphics.push()
        love.graphics.rotate(i * math.pi * 2 / teeth)
        love.graphics.rectangle("fill", -r * 0.22, -r * 1.02, r * 0.44, r * 0.55, 2, 2)
        love.graphics.pop()
    end
    love.graphics.circle("fill", 0, 0, r * 0.68)
    love.graphics.setColor(0.10, 0.12, 0.16, 1)
    love.graphics.circle("fill", 0, 0, r * 0.28)
    love.graphics.pop()
end

local function outlinedBar(x, y, w, h, ratio, fill, radius, alpha)
    radius = radius or 6
    alpha = alpha or 1
    ratio = math.max(0, math.min(1, ratio or 0))
    love.graphics.setColor(0.08, 0.08, 0.08, 0.72 * alpha)
    roundrect(x, y, w, h, radius)
    if w * ratio > 0.5 then
        love.graphics.stencil(function()
            roundrect(x, y, w, h, radius)
        end, "replace", 1)
        love.graphics.setStencilTest("equal", 1)
        love.graphics.setColor(fill[1], fill[2], fill[3], (fill[4] or 1) * alpha)
        Render.drawWaveFill(x, y, w, h, ratio)
        love.graphics.setStencilTest()
    end
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.05, 0.05, 0.05, alpha)
    roundrect(x, y, w, h, radius, "line")
end

local function scissorGui(x, y, w, h)
    local scale, ox, oy = Layout.metrics()
    love.graphics.setScissor(
        math.floor(ox + x * scale + 0.5),
        math.floor(oy + y * scale + 0.5),
        math.max(0, math.floor(w * scale + 0.5)),
        math.max(0, math.floor(h * scale + 0.5))
    )
end

local function easeOut(t)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return 1 - (1 - t) * (1 - t)
end

local function followShow(current, want, speed)
    local dt = math.min(love.timer.getDelta() or 0.016, 0.05)
    local a = 1 - math.exp(-dt * (speed or 14))
    local next = current + ((want and 1 or 0) - current) * a
    if next < 0.002 then return 0 end
    if want and next > 0.998 then return 1 end
    return next
end

local function hoverScale(key, x, y, w, h)
    local s = 1
    if State.anim.hoverKey == key then
        s = 1 + 0.055 * State.anim.hover
    end
    local nx = x - (w * (s - 1)) * 0.5
    local ny = y - (h * (s - 1)) * 0.5
    local nw, nh = w * s, h * s
    local down = pressDown(key)
    if down > 0 then
        ny = ny + math.min(7, nh * 0.14) * down
    end
    return nx, ny, nw, nh, s
end

local function formatScore(n)
    n = tonumber(n) or 0
    if n ~= n or n < 0 then n = 0 end
    n = math.floor(n + 0.5)
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fk", n / 1000)
    elseif n >= 1000 then
        local s = tostring(n)
        return s:sub(1, #s - 3) .. "," .. s:sub(#s - 2)
    end
    return tostring(n)
end

local function mapRect(sw, sh)
    local size = 176
    local pad = 18
    return sw - pad - size, sh - pad - size, size
end

local function caption(text, x, y, align, w)
    w = w or 80
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(0.64, 0.64)
    if align == "right" then
        Render.printf(text, -w, 0, w, "right")
    elseif align == "center" then
        Render.printf(text, -w * 0.5, 0, w, "center")
    else
        Render.print(text, 0, 0)
    end
    love.graphics.pop()
end

local function modeTitle(game)
    local id = tostring(game.gamemode or "ffa")
    local modes = game.modes
    if modes then
        for i = 1, #modes do
            if modes[i].id == id then
                return tostring(modes[i].label or id)
            end
        end
    end
    return string.upper(id)
end

local function currentTankName(game, cam)
    local tankId = math.floor(tonumber(cam and cam.tank) or 0)
    if tankId == 53 then tankId = 0 end
    local def = game.tanksById and game.tanksById[tankId]
    if def and type(def.name) == "string" and def.name ~= "" then
        return txt(def.name)
    end
    return "Unknown"
end

W.STAT_COLORS = STAT_COLORS
W.statFill = statFill
W.box = box
W.inRect = inRect
W.roundrect = roundrect
W.pressDown = pressDown
W.buttonShadow = buttonShadow
W.darkenRgb = darkenRgb
W.buttonOutline = buttonOutline
W.buttonFlash = buttonFlash
W.txt = txt
W.drawCogIcon = drawCogIcon
W.outlinedBar = outlinedBar
W.scissorGui = scissorGui
W.easeOut = easeOut
W.followShow = followShow
W.hoverScale = hoverScale
W.formatScore = formatScore
W.mapRect = mapRect
W.caption = caption
W.modeTitle = modeTitle
W.currentTankName = currentTankName
return W
