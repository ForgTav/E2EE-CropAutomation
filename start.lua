local component = require('component')
local os = require('os')
local event = require("event")
local gps = require('robotGPS')
local actions = require('robotActions')
local serialization = require("serialization")
local config = require('robotConfig')
local tunnel = component.tunnel
local lastMode
local robotStatus = true

local function sendMessage(msg)
    local messageToSend = serialization.serialize(msg)
    tunnel.send(messageToSend)
end

local function transporter(table)
    if table.type == 'order' then
        robotStatus = false
        for _, order in pairs(table.data) do
            if order.action == 'deweed' then
                gps.go(gps.workingSlotToPos(order.slot))
                actions.deweed()
            elseif order.action == 'transplantParent' or order.action == 'transplant' then
                actions.transplant(order)
            elseif order.action == 'removePlant' then
                gps.go(gps.workingSlotToPos(order.slot))
                actions.removePlant(true)
            elseif order.action == 'placeCropStick' then
                gps.go(gps.workingSlotToPos(order.slot))
                actions.placeCropStick(order.count)
            end
        end
        actions.restockAll()
    elseif table.type == 'getStatus' then
        local needConfig = false
        if config.workingFarmSize == nil then
            needConfig = true
        elseif config.storageFarmSize == nil then
            needConfig = true
        elseif config.storageOffset == nil then
            needConfig = true
        end

        if lastMode == nil and table.currentMode ~= nil then
            lastMode = table.currentMode
        elseif lastMode ~= nil and table.currentMode ~= lastMode then
            needConfig = true
            lastMode = table.currentMode
        end

        if needConfig then
            sendMessage({ action = 'getStatus', robotStatus = false, needConfig = needConfig, emptyCropSticks = actions.getEmptyCropSticksFlag() })
        else
            sendMessage({ action = 'getStatus', robotStatus = robotStatus, emptyCropSticks = actions.getEmptyCropSticksFlag() })
        end
        
    elseif table.type == 'robotConfig' then
        local robotConfig = table.data
        if robotConfig.workingFarmSize then
            config.workingFarmSize = robotConfig.workingFarmSize
        end

        if robotConfig.storageFarmSize then
            config.storageFarmSize = robotConfig.storageFarmSize
        end

        if robotConfig.storageOffset then
            config.storageOffset = robotConfig.storageOffset
        end

        actions.setEmptyCropSticksFlag(false)

        sendMessage({ action = 'robotConfig', answer = true })
    elseif table.type == 'cleanUp' then
        robotStatus = false
        for _, order in pairs(table.data) do
            if order.farm == 'working' then
                gps.go(gps.workingSlotToPos(order.slot))
                actions.removePlant()
            elseif order.farm == 'storage' then
                gps.go(gps.storageSlotToPos(order.slot))
                actions.removePlant()
            elseif order.farm == 'blankFarm' then
                gps.go({1,1})
                print('blankFarm')
                actions.removePlant()
            end
        end
        actions.restockAll()
    end
    robotStatus = true
end

local function main()
    actions.initWork()
    while true do
        local _, _, _, _, _, message = event.pull("modem_message")
        local unserilized = serialization.unserialize(message)
        transporter(unserilized)
        os.sleep(0.1)
    end
end


main()
