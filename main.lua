local component = require('component')
local event = require("event")
local os = require('os')
local database = require('sysDB')
local sys = require('sysFunction')
local ev = require('sysEvents')
local term = require("term")
local gpu = component.gpu
local serialization = require("serialization")

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

local function extraExit()
    if ev.needCleanup() then
        local order = sys.cleanUp()
        if next(order) ~= nil then
            print("sendCleanUp")
            while not sys.getRobotStatus() do
                os.sleep(1)
            end
            sys.SendToLinkedCards({ type = 'cleanUp', data = order })
        end
    end
end

local function sysExit()
    print("scanStorage")
    sys.scanStorage()

    print("scanFarm")
    sys.scanFarm()

    local order = sys.cleanUp()
    if next(order) ~= nil then
        print("sendCleanUp")
        while not sys.getRobotStatus() do
            os.sleep(1)
        end
        sys.SendToLinkedCards({ type = 'cleanUp', data = order })
    end
end

local function run()
    local system_exit = false;
    local first_run = true;

    while true do
        if exec.checkCondition() then
            system_exit = true
            break
        end

        if ev.needExit() then
            extraExit()
            break
        end

        print("awaitRobotStatus")
        while not sys.getRobotStatus() do
            os.sleep(1)
        end

        print("scanFarm")
        if not first_run then
            sys.scanFarm()
        end

        print("getOrder")
        local order = sys.createOrderList(exec.handleChild, exec.handleParent)
        if next(order) == nil then
            print("emptyOrder")
        else
            print("sendOrder")
            sys.SendToLinkedCards({ type = 'order', data = order })
        end

        if ev.needExit() then
            break
        end
        first_run = false
        print("sleep5S")
        os.sleep(5)
    end

    if system_exit then
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
    while not sys.getRobotStatus() do
        os.sleep(1)
    end

    print("initDataBase")
    database.initDataBase()

    print("scanStorage")
    sys.scanStorage()

    print("scanFarm")
    sys.scanFarm()

    run()
end

local function main()
    gpu.setResolution(50, 16)
    term.clear()
    drawButton(1, "autoStat")
    drawButton(5, "autoTier WIP")
    drawButton(10, "autoSpread WIP")
    while true do
        local _, _, x, y = event.pull("touch")
        if x >= 20 and x <= 40 and y == 1 then
            exec = require("autoStat")
            break
        end
    end
    term.clear()
    initServer()
end

main()
