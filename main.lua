local component = require('component')
local event = require("event")
local os = require('os')
local database = require('sysDB')
local sys = require('sysFunction')
local ev = require('sysEvents')
local term = require("term")
local gpu = component.gpu
local currentMode

local robotSide
local exec

local function drawButton(y, text)
    gpu.set(math.floor((50 - #text) / 2), y, "[ " .. text .. " ]")
end

local function tprint(tbl, indent)
    indent = indent or 0
    for k, v in pairs(tbl) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if type(v) == "table" then
            print(formatting)
            tprint(v, indent + 1)
        elseif type(v) == 'boolean' then
            print(formatting .. tostring(v))
        else
            print(formatting .. v)
        end
    end
end

local function forceExit()
    print('forceExit')
    if ev.needCleanup() then
        print("scanStorage")
        sys.scanStorage()

        print("scanFarm")
        sys.scanFarm()

        print('needCleanUp')
        local order = sys.cleanUp()
        if next(order) ~= nil then
            print("sendCleanUp")
            sys.SendToLinkedCards({ type = 'cleanUp', data = order })
        else
            print("emptyCleanUp")
        end
    end
end

local function sysExit()
    print("scanStorage")
    sys.scanStorage()

    local order = sys.cleanUp()
    if next(order) ~= nil then
        print("sendCleanUp")
        sys.SendToLinkedCards({ type = 'cleanUp', data = order })
        --sys.sendOrder('cleanUp', order)
    end
end

local function run(firstRun)
    local systemExit = false;

    while true do
        print("awaitRobotStatus")

        while not sys.getRobotStatus(3) do
            os.sleep(0.1)
        end
        os.sleep(0.1)

        if ev.needExit() then
            forceExit()
            break
        end

        if not firstRun then
            print("scanFarm")
            sys.scanFarm()
        end

        if exec.checkCondition() then
            systemExit = true
            break
        end

        print("getOrder")
        local order = sys.createOrderList(exec.handleChild, exec.handleParent)
        if next(order) == nil then
            print("emptyOrder")
        else
            print("sendOrder")
            sys.SendToLinkedCards({ type = 'order', data = order })
            --sys.sendOrder('order', order)
        end

        firstRun = false
        print("sleep5S")
        os.sleep(5)
    end

    if systemExit then
        sysExit()
    end
end

local function initServer()
    print("getChargerSide")
    robotSide = sys.getChargerSide()
    if not robotSide then
        error('Charger not found')
    end
    sys.setRobotSide(robotSide)

    ev.initEvents()
    ev.hookEvents()
    exec.init()

    print("awaitRobotStatus")

    while not sys.getRobotStatus(3) do
        os.sleep(0)
    end
    os.sleep(0.1)

    print("initDataBase")
    database.initDataBase()

    print("scanStorage")
    sys.scanStorage()

    print("scanFarm")
    sys.scanFarm()

    run(true)
end
local function main()
    gpu.setResolution(50, 16)
    term.clear()
    drawButton(1, "autoStat")
    drawButton(5, "autoTier WIP")
    drawButton(10, "autoSpread")
    while true do
        local _, _, x, y = event.pull("touch")
        if x >= 20 and x <= 40 and y == 1 then
            exec = require("autoStat")
            currentMode = 'autoStat'
            break
        elseif x >= 20 and x <= 40 and y == 5 then
            exec = require("autoTier")
            currentMode = 'autoTier'
            break
        elseif x >= 20 and x <= 40 and y == 10 then
            exec = require("autoSpread")
            currentMode = 'autoSpread'
            break
        end
    end
    term.clear()
    initServer()
end

main()
