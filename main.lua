local component = require('component')
local event = require("event")
local os = require('os')
local database = require('sysDB')
local sys = require('sysFunction')
local ev = require('sysEvents')
local term = require("term")
local gpu = component.gpu

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
        local order = sys.Cleanup()
        if next(order) ~= nil then
            print("sendCleanup")
            sys.SendToLinkedCards({ type = 'Cleanup', data = order })
            return true
        end
    end
end

local function initServer()
    print("getChargerSide")
    robotSide = sys.getChargerSide()
    if not robotSide then
        error('Charger not found')
    end
    ev.initEvents()
    ev.hookEvents()
    sys.setRobotSide(robotSide)
    exec.init()
    print("initDataBase")
    database.initDataBase()
    sys.scanStorage()
    sys.scanFarm()
    while true do
        if exec.checkCondition() then
            break
        end
        print("awaitRobotStatus")
        while not sys.getRobotStatus() do
            os.sleep(1)
        end

        print("getOrder")
        if ev.needExit() then
            extraExit()
            break
        end

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
        print("sleep5S")
        os.sleep(5)
        sys.scanFarm()
    end
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
