local State = {}

State.anim = {
    hover = 0,
    hoverKey = "",
    pulse = 0,
    notify = 0,
    mapX = 0,
    mapY = 0,
    mapA = 0,
    up = 0,
    overlay = 0,
    tankShow = 0,
    statShow = 0
}

State.presses = {}
State.holdKey = nil
State.lastHoverKey = ""
State.wantTank = false
State.wantStat = false

function State.resetMap()
    local anim = State.anim
    anim.mapX, anim.mapY, anim.mapA = 0, 0, 0
end

return State
