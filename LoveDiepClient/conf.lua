function love.conf(t)
    t.identity = "LoveDiepClient"
    t.version = "11.5"
    t.console = false
    t.window.title = "LoveDiepClient"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 800
    t.window.minheight = 450
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.depth = 24
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
