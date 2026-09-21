local Game = require("src.app.game")

local game

function love.load()
    love.keyboard.setKeyRepeat(true)
    love.graphics.setBackgroundColor(0.8, 0.8, 0.8)
    local font = love.graphics.newFont(16)
    love.graphics.setFont(font)
    game = Game:new()
end

function love.update(dt)
    game:update(dt)
end

function love.draw()
    game:draw()
end

function love.textinput(text)
    game:textinput(text)
end

function love.keypressed(key, scancode, isrepeat)
    game:keypressed(key, isrepeat)
end

function love.mousepressed(x, y, button)
    game:mousepressed(x, y, button)
end

function love.mousemoved(x, y)
    if game then game:mousemoved(x, y) end
end

function love.mousereleased(x, y, button)
    if game then game:mousereleased(x, y, button) end
end

function love.wheelmoved(dx, dy)
    if game then game:wheelmoved(dx, dy) end
end

function love.quit()
    if game then game:disconnect() end
end

function love.focus(focused)
    if focused and game then
        game:update(0)
    end
end

-- Pump simulation even when the window is unfocused. Vsync present() can
-- stall for a long time on Windows when another window is in front, so we
-- turn vsync off while unfocused and cap that background pump to 60 Hz.
function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end
    local vsyncOn = true
    local function setVsync(on)
        if on == vsyncOn then return end
        vsyncOn = on
        if love.window.setVSync then
            love.window.setVSync(on and 1 or 0)
        end
    end
    return function()
        if love.event then
            love.event.pump()
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" then
                    if not love.quit or not love.quit() then
                        return a or 0
                    end
                else
                    love.handlers[name](a, b, c, d, e, f)
                end
            end
        end
        local focused = true
        if love.window and love.window.hasFocus then
            focused = love.window.hasFocus()
        end
        setVsync(focused)
        local dt = 0
        if love.timer then dt = love.timer.step() end
        if love.update then love.update(dt) end
        if love.graphics and love.graphics.isActive() then
            love.graphics.origin()
            love.graphics.clear(love.graphics.getBackgroundColor())
            if love.draw then love.draw() end
            love.graphics.present()
        end
        if not focused and love.timer then
            local leftover = (1 / 60) - dt
            if leftover > 0 then
                love.timer.sleep(leftover)
            end
        end
    end
end
