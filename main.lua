local component = require('component')
local os = require('os')
local term = require("term")
local thread = require("thread")
local db = require('sysDB')
local ui = require("sysUI")
local logic = require("sysLogic")

local function checkGPU()
    if component.isAvailable("gpu") then
        local gpu = component.gpu
        local w, h = gpu.maxResolution()
        if w < 80 or h < 25 then
            print("Requires at least a Tier 2 Graphics Card and compatible Screen.")
            return false
        else
            return true
        end
    end

    return false
end

local function checkLinkedCard()
    if component.isAvailable("tunnel") then
        return true
    end
    print("Requires a Linked Card to communicate with robot.")
    return false
end

local function checkMemory()
    local computer = require("computer")
    local totalMemory = computer.totalMemory()

    if totalMemory >= 786432 then
        return true
    else
        print("Insufficient memory: requires additional or higher-tier RAM/Memory modules.")
        return false
    end
end

local function initServer()
    local uiThread = thread.create(function()
        local _success, _error = pcall(function()
            ui.initUI()
        end)
        if not _success and _error and _error.reason ~= 'terminated' then
            term.clear()
            error("uiThread error: " .. tostring(error), 2)
        end
    end)
    local runThread = thread.create(function()
        local _success, _error = pcall(function()
            logic.initLogic()
        end)
        if not _success and _error and _error.reason ~= 'terminated' then
            term.clear()
            print("System thread error: " .. tostring(_error))
        end
    end)
end

local function checkComponents()
    db.initDataBase()
    if not checkGPU() then
        os.exit()
    end

    if not checkLinkedCard() then
        os.exit()
    end

    if not checkMemory() then
        os.exit()
    end

    initServer()
end
checkComponents()
