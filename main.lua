local component = require('component')
local event = require("event")
local os = require('os')
local database = require('sysDB')
local sys = require('sysFunction')

local term = require("term")
local gpu = component.gpu
local screenWidth, screenHeight = gpu.getResolution()

local sensor = component.sensor
local robotSide
local robotStatus = false

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

local function initServer()
    print("getChargerSide")
    robotSide = sys.getChargerSide()
    if not robotSide then
        error('Charger not found')
    end

    sys.setRobotSide(robotSide)

    exec.init()

    print("initDataBase")
    database.initDataBase()
    sys.scanStorage()
    sys.scanFarm()

    -- sysFunction.initServer()
    while true do
        local loopForStatus = true
        print("awaitRobotStatus")
        while loopForStatus do
            if sys.getRobotStatus() then
                loopForStatus = false
            end
            os.sleep(1)
        end

        print("getOrder")
        local order = nil
        if sys.scanFarm() then
            order = sys.createOrderList(exec.handleChild, exec.handleParent)
        end

        if next(order) == nil then
            print("emptyOrder")
        else
            print("sendOrder")
            sys.SendToLinkedCards({ type = 'order', data = order })
        end
        print("sleep5S")
        os.sleep(5)
    end
end
local function drawButton(y, text)
    gpu.set(math.floor((50 - #text) / 2), y, "[ " .. text .. " ]")
end


local function main()
    gpu.setResolution(50, 16)

    term.clear()

    drawButton(1, "autoStat")
    drawButton(5, "autoTier")
    drawButton(10, "autoSpread")

    -- Ожидание событий
    while true do
        local _, _, x, y = event.pull("touch")

        if x >= 20 and x <= 40 and y == 1 then
            exec = require("autoStat")
            break
        elseif x >= 20 and x <= 40 and y == 5 then
            exec = require("autoTier")
            break
        elseif x >= 20 and x <= 40 and y == 10 then
            exec = require("autoSpread")
            break
        end
    end

    gpu.setResolution(screenWidth, screenHeight)
    term.clear()
    initServer()
end

main()
