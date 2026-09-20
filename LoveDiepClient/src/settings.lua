local json = require("src.json")

local Settings = {
    style = "new",
    hudScale = 1,
    innerShadow = 0.15,
    showFps = false
}

local HUD_MIN, HUD_MAX, HUD_STEP = 0.70, 1.50, 0.05
local SHADOW_MIN, SHADOW_MAX, SHADOW_STEP = 0, 1, 0.01
local SHADOW_NUDGE = 0.05

function Settings.clampHudScale(v)
    v = tonumber(v) or 1
    if v ~= v then v = 1 end
    v = math.floor(v / HUD_STEP + 0.5) * HUD_STEP
    if v < HUD_MIN then v = HUD_MIN end
    if v > HUD_MAX then v = HUD_MAX end
    return v
end

function Settings.clampInnerShadow(v)
    v = tonumber(v) or 0.15
    if v ~= v then v = 0.15 end
    v = math.floor(v / SHADOW_STEP + 0.5) * SHADOW_STEP
    if v < SHADOW_MIN then v = SHADOW_MIN end
    if v > SHADOW_MAX then v = SHADOW_MAX end
    return v
end

function Settings.load()
    local raw = love.filesystem.read("settings.json")
    if raw then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == "table" then
            if data.style == "old" then
                Settings.style = "old"
            elseif data.style == "shaded" then
                Settings.style = "shaded"
            else
                Settings.style = "new"
            end
            if data.hudScale ~= nil then
                Settings.hudScale = Settings.clampHudScale(data.hudScale)
            end
            if data.innerShadow ~= nil then
                Settings.innerShadow = Settings.clampInnerShadow(data.innerShadow)
            end
            if data.showFps ~= nil then
                Settings.showFps = data.showFps == true
            end
        end
    end
    return Settings
end

function Settings.save()
    local style = "new"
    if Settings.style == "old" then
        style = "old"
    elseif Settings.style == "shaded" then
        style = "shaded"
    end
    local scale = Settings.clampHudScale(Settings.hudScale)
    local shadow = Settings.clampInnerShadow(Settings.innerShadow)
    local fps = Settings.showFps and "true" or "false"
    love.filesystem.write(
        "settings.json",
        string.format(
            '{"style":"%s","hudScale":%.2f,"innerShadow":%.2f,"showFps":%s}',
            style, scale, shadow, fps
        )
    )
end

function Settings.setStyle(style)
    if style == "old" then
        Settings.style = "old"
    elseif style == "shaded" then
        Settings.style = "shaded"
    else
        Settings.style = "new"
    end
    Settings.save()
end

function Settings.setHudScale(scale, skipSave)
    Settings.hudScale = Settings.clampHudScale(scale)
    if not skipSave then
        Settings.save()
    end
end

function Settings.nudgeHudScale(dir)
    Settings.setHudScale((Settings.hudScale or 1) + HUD_STEP * (dir or 1))
end

function Settings.setHudScaleFromBar(gx, bar, skipSave)
    if not bar then return end
    local t = (gx - bar.x) / math.max(1, bar.w)
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    Settings.setHudScale(HUD_MIN + t * (HUD_MAX - HUD_MIN), skipSave)
end

function Settings.hudScaleT()
    local s = Settings.clampHudScale(Settings.hudScale)
    return (s - HUD_MIN) / (HUD_MAX - HUD_MIN), s
end

function Settings.setInnerShadow(coverage, skipSave)
    Settings.innerShadow = Settings.clampInnerShadow(coverage)
    if not skipSave then
        Settings.save()
    end
end

function Settings.nudgeInnerShadow(dir)
    Settings.setInnerShadow((Settings.innerShadow or 0.15) + SHADOW_NUDGE * (dir or 1))
end

function Settings.setInnerShadowFromBar(gx, bar, skipSave)
    if not bar then return end
    local t = (gx - bar.x) / math.max(1, bar.w)
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    Settings.setInnerShadow(SHADOW_MIN + t * (SHADOW_MAX - SHADOW_MIN), skipSave)
end

function Settings.innerShadowT()
    local s = Settings.clampInnerShadow(Settings.innerShadow)
    return (s - SHADOW_MIN) / (SHADOW_MAX - SHADOW_MIN), s
end

function Settings.setShowFps(on)
    Settings.showFps = on == true
    Settings.save()
end

function Settings.isOld()
    return Settings.style == "old"
end

return Settings
