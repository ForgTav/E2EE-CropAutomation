local component = require('component')
local event = require("event")
local config = require('sysConfig')
local gps = require('sysGPS')
local database = require('sysDB')
local serialization = require("serialization")
local term = require("term")
local db = require("sysDB")

local gpu = component.gpu
local screenWidth, screenHeight = gpu.getResolution()

local tunnel = component.tunnel
local sensor = component.sensor
local robotSide
local lastRobotStatus = false
local emptyCropSticks = false
local lastComputerStatus = ''


local function SendToLinkedCards(msg)
    tunnel.send(serialization.serialize(msg))
end

local function printCenteredText(text)
    term.clear()

    local startX = math.floor((screenWidth - #text) / 2)
    local startY = math.floor(screenHeight / 2)

    term.setCursor(startX, startY)
    term.write(text)
end



local function setRobotSide(side)
    robotSide = side
end

local function cordtoScan(x, y)
    if robotSide == 1 then
        return { x, (-y - 1) }
    elseif robotSide == 2 then
        return { y + 1, x }
    elseif robotSide == 3 then
        return { x * -1, y + 1 }
    elseif robotSide == 4 then
        return { -y - 1, x * -1 }
    else
        error("Invalid robot side")
    end
end

local function getChargerSide()
    for i = 1, #config.sidesCharger do
        local cur_scan = sensor.scan(config.sidesCharger[i][1], 0, config.sidesCharger[i][2])
        if cur_scan ~= nil and cur_scan.block and cur_scan.block.name == 'opencomputers:charger' then
            return i
        end
    end
    return nil
end

local function fetchScan(rawScan)
    local block = rawScan['block']
    if block['name'] == 'minecraft:air' or block['name'] == 'GalacticraftCore:tile.brightAir' then
        return { isCrop = true, name = 'air', fromScan = true }
    elseif block['name'] == 'ic2:te' then
        local crop = rawScan['data']['Crop']
        if block['label'] == 'Crop' then
            return { isCrop = true, name = 'emptyCrop', crossingbase = crop.crossingBase, fromScan = true }
        else
            return {
                isCrop = true,
                name = crop['cropId'],
                gr = crop['statGrowth'],
                ga = crop['statGain'],
                re = crop['statResistance'],
                tier = config.seedTiers[crop['cropId']],
                weedex = crop['storageWeedEX'],
                water = crop['storageWater'],
                nutrients = crop['storageNutrients'],
                fromScan = true
            }
        end
    else
        return { isCrop = false, name = 'block', fromScan = true }
    end
end

local function scanStorage(firstRun)
    for slot = 1, config.storageFarmArea, 1 do
        local raw = gps.storageSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        if crop then
            database.updateStorage(slot, crop)
        end

        if firstRun then
            local scanPercent = (slot / config.storageFarmArea) * 100
            printCenteredText(string.format("Scan Storage: %.2f%%", scanPercent))
        end
    end
end

local function scanFarm(firstRun)
    for slot = 1, config.workingFarmArea do
        local raw = gps.workingSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        if crop then
            database.updateFarm(slot, crop)
        end
        if firstRun then
            local scanPercent = (slot / config.workingFarmArea) * 100
            printCenteredText(string.format("Scan Farm: %.2f%%", scanPercent))
        end
    end

    return true
end

local function getEmptySlotStorage()
    for slot, crop in pairs(database.getStorage()) do
        if crop.isCrop and (crop.name == 'emptyCrop' or crop.name == 'air') then
            return slot
        end
    end
end

local function isComMax(crop, farm)
    if farm == 'working' then
        return crop.gr > config.workingMaxGrowth or
            crop.re > config.workingMaxResistance or
            (crop.name == 'venomilia' and crop.gr > 7)
    elseif farm == 'storage' then
        return crop.gr > config.storageMaxGrowth or
            crop.re > config.storageMaxResistance or
            (crop.name == 'venomilia' and crop.gr > 7)
    end
end

local function isWeed(crop)
    return crop.name == 'weed' or crop.name == 'Grass'
end

local function limitedOrderList(list)
    local result = {}
    for i = 1, config.maxOrderList do
        table.insert(result, list[i])
    end
    return result
end

local function createOrderList(handleChild, handleParent)
    local orderList = {}
    for slot, crop in pairs(database.getFarm()) do
        if crop.isCrop and crop.fromScan then
            local tasks = {}
            if slot % 2 == 0 then
                tasks = handleChild(slot, crop)
            else
                tasks = handleParent(slot, crop)
            end
            for _, task in pairs(tasks) do
                table.insert(orderList, task)
            end
        end
    end

    table.sort(orderList, function(a, b)
        if a.priority == b.priority then
            return a.slot < b.slot
        end
        return a.priority < b.priority
    end)

    if #orderList > config.maxOrderList then
        orderList = limitedOrderList(orderList)
    end

    db.setLogs(orderList)
    return orderList
end


local function cleanUp()
    local order = {}

    for slot, crop in pairs(database.getFarm()) do
        if crop.isCrop and (crop.name == 'emptyCrop' or isWeed(crop)) then
            table.insert(order, {
                farm = 'working',
                slot = slot,
            })
        elseif slot % 2 == 0 then
            table.insert(order, {
                farm = 'working',
                slot = slot,
            })
        end
    end

    for slot, crop in pairs(database.getStorage()) do
        if crop.isCrop and (crop.name == 'emptyCrop' or isWeed(crop)) then
            table.insert(order, {
                farm = 'storage',
                slot = slot,
            })
        end
    end

    --table.sort(order, function(a, b)
    --    return a.slot < b.slot
    --end)

    return order
end

local function sendRobotConfig()
    local robotConfig = {
        workingFarmSize = config.workingFarmSize,
        storageFarmSize = config.storageFarmSize,
        storageOffset = config.workingFarmDefaultSize - config.workingFarmSize
    }

    tunnel.send(serialization.serialize({ type = "robotConfig", data = robotConfig }))
    local _, _, _, _, _, message = event.pull(2, "modem_message")
    if message == nil then
        return false
    end

    local unserilized = serialization.unserialize(message)
    if unserilized.answer then
        return unserilized.answer
    end
    return false
end

local function getRobotStatus(timeout, mode)
    tunnel.send(serialization.serialize({ type = "getStatus", currentMode = mode }))
    local _, _, _, _, _, message = event.pull(timeout, "modem_message")
    if message == nil then
        lastRobotStatus = false
        return false
    end

    local unserilized = serialization.unserialize(message)

    if unserilized.needConfig ~= nil and unserilized.needConfig == true then
        while not sendRobotConfig() do
            os.sleep(1)
        end
    end

    if unserilized.emptyCropSticks ~= nil and unserilized.emptyCropSticks == true then
        emptyCropSticks = unserilized.emptyCropSticks
    end

    if unserilized.robotStatus then
        lastRobotStatus = unserilized.robotStatus
        return unserilized.robotStatus
    end
    lastRobotStatus = false
    return false
end





local function getLastRobotStatus()
    return lastRobotStatus
end

local function setLastComputerStatus(status)
    lastComputerStatus = status
end

local function getEmptyCropSticks()
    return emptyCropSticks
end

local function getLastComputerStatus()
    return lastComputerStatus
end


return {
    SendToLinkedCards = SendToLinkedCards,
    getRobotStatus = getRobotStatus,
    getLastRobotStatus = getLastRobotStatus,
    getEmptyCropSticks = getEmptyCropSticks,
    getLastComputerStatus = getLastComputerStatus,
    setLastComputerStatus = setLastComputerStatus,
    scanFarm = scanFarm,
    createOrderList = createOrderList,
    isWeed = isWeed,
    isComMax = isComMax,
    scanStorage = scanStorage,
    fetchScan = fetchScan,
    getChargerSide = getChargerSide,
    cordtoScan = cordtoScan,
    setRobotSide = setRobotSide,
    cleanUp = cleanUp,
    getEmptySlotStorage = getEmptySlotStorage,
    printCenteredText = printCenteredText,
    sendRobotConfig = sendRobotConfig
}
