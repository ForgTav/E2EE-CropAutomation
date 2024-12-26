local robot = require('robot')
local config = require('config')
local nowFacing = 1
local nowPos = {0, 0}
local savedPos = {}

-- ======================== WORKING FARM ========================
--  _________________
-- |31 30 19 18 07 06|  6x6 Slot Map
-- |32 29 20 17 08 05|
-- |33 28 21 16 09 04|  One down from 01 is (0,0)
-- |34 27 22 15 10 03|
-- |35 26 23 14 11 02|
-- |36 25 24 13 12 01|
--  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

local function workingSlotToPos(slot)
    local x = (slot - 1) // config.workingFarmSize
    local row = (slot - 1) % config.workingFarmSize
    local y

    if x % 2 == 0 then
        y = row + 1
    else
        y = -row + config.workingFarmSize
    end

    return {-x, y}
end

-- ======================== STORAGE FARM ========================
--  __________________________
-- |09 10 27 28 45 46 63 64 81|  9x9 Slot Map
-- |08 11 26 29 44 47 62 65 80|
-- |07 12 25 30 43 48 61 66 79|  Two left from 03 is (0,0)
-- |06 13 24 31 42 49 60 67 78|
-- |05 14 23 32 41 50 59 68 77|
-- |04 15 22 33 40 51 58 69 76|
-- |03 16 21 34 39 52 57 70 75|
-- |02 17 20 35 38 53 56 71 74|
-- |01 18 19 36 37 54 55 72 73|
--  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

local function storageSlotToPos(slot)
    local x = (slot - 1) // config.storageFarmSize + 2
    local row = (slot - 1) % config.storageFarmSize
    local y

    if x % 2 == 0 then
        y = row - config.storageFarmSize + config.workingFarmSize + 1
    else
        y = -row + config.workingFarmSize
    end

    return {x, y}
end


local function getFacing()
    return nowFacing
end


local function getPos()
    return nowPos
end


local function safeForward()
    local forwardSuccess
    repeat
        forwardSuccess = robot.forward()
    until forwardSuccess
end


local function turnTo(facing)
    local delta = (facing - nowFacing) % 4
    nowFacing = facing
    if delta <= 2 then
        for _=1, delta do
            robot.turnRight()
        end
    else
        for _= 1, 4 - delta do
            robot.turnLeft()
        end
    end
end


local function turningDelta(facing)
    local delta = (facing - nowFacing) % 4
    if delta <= 2 then
        return delta
    else
        return 4-delta
    end
end


local function go(pos)
    if nowPos[1] == pos[1] and nowPos[2] == pos[2] then
        return
    end

    -- Find path
    local posDelta = {pos[1]-nowPos[1], pos[2]-nowPos[2]}
    local path = {}

    if posDelta[1] > 0 then
        path[#path+1] = {2, posDelta[1]}
    elseif posDelta[1] < 0 then
        path[#path+1] = {4, -posDelta[1]}
    end

    if posDelta[2] > 0 then
        path[#path+1] = {1, posDelta[2]}
    elseif posDelta[2] < 0 then
        path[#path+1] = {3, -posDelta[2]}
    end

    -- Optimal first turn
    if #path == 2 and turningDelta(path[2][1]) < turningDelta(path[1][1]) then
        path[1], path[2] = path[2], path[1]
    end

    for i=1, #path do
        turnTo(path[i][1])
        for _=1, path[i][2] do
            safeForward()
        end
    end

    nowPos = pos
end


local function down(distance)
    if distance == nil then
        distance = 1
    end
    for _=1, distance do
        robot.down()
    end
end


local function up(distance)
    if distance == nil then
        distance = 1
    end
    for _=1, distance do
        robot.up()
    end
end


local function save()
    savedPos[#savedPos+1] = nowPos
end


local function resume()
    if #savedPos == 0 then
        return
    end
    go(savedPos[#savedPos])
    savedPos[#savedPos] = nil
end


return {
    workingSlotToPos = workingSlotToPos,
    storageSlotToPos = storageSlotToPos,
    getFacing = getFacing,
    getPos = getPos,
    turnTo = turnTo,
    go = go,
    save = save,
    resume = resume,
    down = down,
    up = up
}
