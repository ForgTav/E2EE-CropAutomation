local component = require('component')
local os = require('os')
local event = require("event")
local gps = require('robotGPS')
local actions = require('robotActions')
local serialization = require("serialization")
local tunnel = component.tunnel
local robotStatus = false

local function sendMessage(msg)
    local messageToSend = serialization.serialize(msg)
    tunnel.send(messageToSend)
end


local function transporter(table)
    if table.type == 'order' then
        robotStatus = false
        for index, order in ipairs(table.data) do
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
        sendMessage({ action = 'getStatus', robotStatus = robotStatus })
    end
end





local function main()
    actions.initWork()
    robotStatus = true

    while true do
        local _, _, _, _, _, message = event.pull("modem_message")
        local unserilized = serialization.unserialize(message)
        transporter(unserilized)
        robotStatus = true
        os.sleep(0.1)
    end
end


main()

--while main() do
--
--end
