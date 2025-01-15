local component = require('component')
local event = require("event")
local os = require('os')
local database = require('sysDB')
local sys = require('sysFunction')
local term = require("term")
local thread = require("thread")
local ui = require("sysUI")
local config = require("sysConfig")
local currentMode

local robotSide
local exec
local uiThread

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
    if uiThread and uiThread:status() ~= 'dead' then
        uiThread:kill()
    end
    sys.printCenteredText('Force exit')
    if ui.needCleanup() then
        sys.scanStorage(true)
        sys.scanFarm(true)
        local order = sys.cleanUp()
        if next(order) ~= nil then
            sys.printCenteredText('Send cleanup order')
            while not sys.getRobotStatus(1, currentMode) do
                os.sleep(0.1)
            end
            os.sleep(0.1)
            sys.SendToLinkedCards({ type = 'cleanUp', data = order })
        else
            sys.printCenteredText('Empty cleanup order')
        end
    end
    while not sys.getRobotStatus(1, currentMode) do
        os.sleep(0.1)
    end
    os.sleep(0.1)
    term.clear()
    os.exit()
end

local function sysExit()
    if uiThread and uiThread:status() ~= 'dead' then
        uiThread:kill()
    end

    sys.scanStorage(true)

    local order = sys.cleanUp()
    if next(order) ~= nil then
        sys.printCenteredText('Send cleanup order')
        while not sys.getRobotStatus(1, currentMode) do
            os.sleep(0.1)
        end
        os.sleep(0.1)
        sys.SendToLinkedCards({ type = 'cleanUp', data = order })
    end
    while not sys.getRobotStatus(1, currentMode) do
        os.sleep(0.1)
    end
    os.sleep(0.1)
    term.clear()
    os.exit()
end

local function run(firstRun)
    local systemExit = false;

    while true do
        sys.setLastComputerStatus('Awaiting')
        while not sys.getRobotStatus(3, currentMode) do
            sys.setLastComputerStatus('Sleep 3 seconds..')
            os.sleep(3)
        end
        os.sleep(0.1)

        if ui.needExit() then
            forceExit()
            break
        end

        if not firstRun then
            ui.UIloading(true)
            sys.scanFarm()
        end
        firstRun = false

        if exec.checkCondition() then
            systemExit = true
            break
        end

        if sys.getEmptyCropSticks() then
            systemExit = true
            break
        end

        local order = sys.createOrderList(exec.handleChild, exec.handleParent)
        if next(order) ~= nil then
            sys.SendToLinkedCards({ type = 'order', data = order })
        end

        ui.UIloading(false)
        sys.setLastComputerStatus('Sleep 5 seconds..')
        os.sleep(5)
    end

    if systemExit then
        sysExit()
    end
    os.sleep(0.2)
end

local function initServer()
    currentMode = ui.drawMainMenu()

    if not currentMode then
        os.exit()
    else
        if currentMode == "autoStat" then
            config.workingFarmSize = config.workingFarmStatSize
        elseif currentMode == "autoSpread" then
            config.workingFarmSize = config.workingFarmSpreadSize
        elseif currentMode == "autoTier" then
            config.workingFarmSize = config.workingFarmTierSize
        end
        config.workingFarmArea = config.workingFarmSize ^ 2
    end

    sys.printCenteredText("initDataBase")
    database.initDataBase()

    sys.printCenteredText("getChargerSide")
    robotSide = sys.getChargerSide()

    if not robotSide then
        sys.printCenteredText('Charger not found')
        os.exit()
    end
    sys.setRobotSide(robotSide)

    exec = require(currentMode)

    exec.init()

    sys.printCenteredText("Awaiting robot")

    while not sys.getRobotStatus(3, currentMode) do
        os.sleep(0)
    end
    os.sleep(0.1)

    while not sys.sendRobotConfig() do
        os.sleep(3)
    end

    sys.scanStorage(true)

    sys.printCenteredText("scanFarm")
    sys.scanFarm(true)

    uiThread = thread.create(function() ui.initUI() end)
    local runThread = thread.create(function()
        local success, error = pcall(function()
            while not ui.getStartSystem() do
                os.sleep(1)
            end
            run(true)
        end)
        if not success then
            term.clear()
            if error ~= nil and error.reason ~= 'terminated' then
                print("RunThread error: " .. tostring(error))
            end
        end
    end)
end

initServer()
