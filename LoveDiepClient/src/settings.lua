local json = require("src.json")

local Settings = {
    style = "new",
    hudScale = 1,
    showFps = false
}

local HUD_MIN, HUD_MAX, HUD_STEP = 0.70, 1.50, 0.05

function Settings.clampHudScale(v)
    v = tonumber(v) or 1
    if v ~= v then v = 1 end
    v = math.floor(v / HUD_STEP + 0.5) * HUD_STEP
    if v < HUD_MIN then v = HUD_MIN end
    if v > HUD_MAX then v = HUD_MAX end
    return v
end

function Settings.load()
    local raw = love.filesystem.read("settings.json")
    if raw then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == "table" then
            if data.style == "old" then
                Settings.style = "old"
            else
                Settings.style = "new"
            end
            if data.hudScale ~= nil then
                Settings.hudScale = Settings.clampHudScale(data.hudScale)
            end
            if data.showFps ~= nil then
                Settings.showFps = data.showFps == true
            end
        end
    end
    return Settings
end

function Settings.save()
    local style = Settings.style == "old" and "old" or "new"
    local scale = Settings.clampHudScale(Settings.hudScale)
    local fps = Settings.showFps and "true" or "false"
    love.filesystem.write(
        "settings.json",
        string.format('{"style":"%s","hudScale":%.2f,"showFps":%s}', style, scale, fps)
    )
end

function Settings.setStyle(style)
    Settings.style = (style == "old") and "old" or "new"
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

function Settings.setShowFps(on)
    Settings.showFps = on == true
    Settings.save()
end

function Settings.isOld()
    return Settings.style == "old"
end

return Settings
