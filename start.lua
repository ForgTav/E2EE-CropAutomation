local component = require('component')
local os = require('os')
local event = require("event")
local gps = require('robotGPS')
local actions = require('robotActions')
local serialization = require("serialization")
local config = require('robotConfig')
local tunnel = component.tunnel
local robot = require("robot")
local robotStatus = true

local function sendMessage(msg)
    local messageToSend = serialization.serialize(msg)
    tunnel.send(messageToSend)
end

local function checkLinkedCard()
    if component.isAvailable("tunnel") then
        return true
    end
    return false
end

local function checkRedstoneCard()
    if component.isAvailable("redstone") then
        return true
    end
    return false
end

local function checkInventoryUpgrade()
    local success, size = pcall(robot.inventorySize)
    return success and type(size) == "number" and size / 16 >= 1
end

local function checkInventoryController()
    if component.isAvailable("inventory_controller") then
        return true
    end
    return false
end

local function checkTools(returnTable)
    local invSize = robot.inventorySize()
    if not invSize then
        return false
    end
    local ic = component.inventory_controller
    local itemTargets = {
        ['ic2:weeding_trowel'] = config.trowelSlot,
        ['thaumictinkerer:connector'] = config.binderSlot,
    }
    local foundItems = {}

    for itemName, itemSlot in pairs(itemTargets) do
        for slot = 1, invSize do
            local item = ic.getStackInInternalSlot(slot)
            if item and item.name == itemName then
                foundItems[item.name] = true
                local targetSlot = invSize + itemSlot
                if slot ~= targetSlot then
                    robot.select(slot)
                    robot.transferTo(targetSlot)
                end
                break
            end
        end
    end
    robot.select(1)

    for itemName, _ in pairs(itemTargets) do
        if not foundItems[itemName] and not returnTable then
            return false
        end
    end

    if returnTable then
        return foundItems
    end

    return true
end

local function checkMemory()
    local computer = require("computer")
    local totalMemory = computer.totalMemory()

    if totalMemory >= 393216 then
        return true
    else
        return false
    end
end

local function scanSystemRobot()
    local tools = checkTools(true)
    return {
        linkedCard = checkLinkedCard(),
        redstoneCard = checkRedstoneCard(),
        inventoryUpgrade = checkInventoryUpgrade(),
        inventoryController = checkInventoryController(),
        weedingTrowel = tools and tools['ic2:weeding_trowel'] or false,
        transvectorBinder = tools and tools['thaumictinkerer:connector'] or false,
    }
end

local function transporter(msgType, msgData)
    if msgType == "scanSystemRobot" then
        robotStatus = false
        local results = scanSystemRobot()
        sendMessage({
            type = "scanSystemRobot",
            data = results
        })
    elseif msgType == "getStatus" then
        local chargedStatus = actions.fullyCharged() or false
        if not chargedStatus then
            print('Robot – Now charging. System is on standby.')
        end

        sendMessage({
            type = "getStatus",
            robotStatus = robotStatus,
            charged = chargedStatus
        })
    elseif msgType == 'order' then
        robotStatus = false
        for _, order in pairs(msgData) do
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
    elseif msgType == 'cleanUp' then
        robotStatus = false
        for _, order in pairs(msgData) do
            if order.farm == 'working' then
                gps.go(gps.workingSlotToPos(order.slot))
                actions.clearSlot()
            elseif order.farm == 'storage' then
                gps.go(gps.storageSlotToPos(order.slot))
                actions.clearSlot()
            elseif order.farm == 'blankFarm' then
                gps.go({ 1, 1 })
                actions.clearSlot()
            end
        end
        actions.restockAll()
    elseif msgType == 'manualTransplant' then
        robotStatus = false
        actions.manualTransplant(msgData)
        actions.restockAll()
    else
        sendMessage({
            type = "error",
            message = "Unknown request type: " .. tostring(msgType)
        })
    end
    robotStatus = true
end

local function initRobot()
    local firstRun = true
    while true do
        local _, _, _, _, _, rawMessage = event.pull("modem_message")
        if rawMessage then
            local success, parsed = pcall(serialization.unserialize, rawMessage)
            if success and parsed then
                if type(parsed) ~= "table" then
                    return
                end

                local msgType = parsed.type

                if not msgType then
                    return
                end
                print("Received message: " .. msgType)
                local msgData = parsed.data or {}
                if firstRun and (msgType == 'order' or msgType == 'manualTransplant') then
                    actions.initWork()
                    firstRun = false
                end
                transporter(msgType, msgData)
            else
                print("Failed to parse message: " .. tostring(rawMessage))
            end
        end
    end
end

local function checkComponents()
    if not checkLinkedCard() then
        print("Requires a Linked Card to communicate with robot.")
        os.exit()
    end

    if not checkMemory() then
        print("Insufficient memory: requires additional or higher-tier RAM/Memory modules.")
        os.exit()
    end

    if not checkInventoryController() or not checkInventoryUpgrade() then
        print("Missing required upgrades: Inventory Upgrade and Inventory Controller Upgrade.")
        os.exit()
    end

    if not checkRedstoneCard() then
        print("Missing required upgrades: Inventory Upgrade and Inventory Controller Upgrade.")
        os.exit()
    end

    if not checkTools() then
        print("Required tools not found: Weeding Trowel and Transvector Binder.")
        os.exit()
    end

    print("Robot has been initialized. All systems are functioning correctly.")

    initRobot()
end

checkComponents()
