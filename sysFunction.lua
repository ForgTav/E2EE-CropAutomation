local component = require('component')
local event = require("event")
local os = require('os')
local config = require('sysConfig')
local gps = require('sysGPS')
local database = require('sysDB')

local serialization = require("serialization")

local tunnel = component.tunnel
local sensor = component.sensor
local robotSide


local function SendToLinkedCards(msg)
    local messageToSend = serialization.serialize(msg)
    tunnel.send(messageToSend)
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
        if cur_scan.block and cur_scan.block.name == 'opencomputers:charger' then
            return i
        end
    end
    return nil
end

local function fetchScan(rawScan)
    local block = rawScan['block']
    if block['name'] == 'minecraft:air' or block['name'] == 'GalacticraftCore:tile.brightAir' then
        return { isCrop = true, name = 'air' }
    elseif block['name'] == 'ic2:te' then
        if block['label'] == 'Crop' then
            return { isCrop = true, name = 'emptyCrop' }
        else
            local crop = rawScan['data']['Crop']
            return {
                isCrop = true,
                name = crop['cropId'],
                gr = crop['statGrowth'],
                ga = crop['statGain'],
                re = crop['statResistance'],
                tier = config.seedTiers[crop['cropId']]
            }
        end
    else
        return { isCrop = false, name = 'block' }
    end
end

local function scanStorage()
    for slot = 1, config.storageFarmArea, 1 do
        local raw = gps.storageSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        if crop then
            database.updateStorage(slot, crop)
        end
    end
end

local function scanAndProcess(slot)
    local raw = gps.workingSlotToPos(slot)
    local cord = cordtoScan(raw[1], raw[2])
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local crop = fetchScan(rawScan)
    if crop then
        database.updateFarm(slot, crop)
    end
end

local function scanFarm()
    for slot = 1, config.workingFarmArea do
        local raw = gps.workingSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        if crop then
            database.updateFarm(slot, crop)
        end
    end

    return true
end

local function scanEmptySlotStorage(newCrop)
    for slot = 1, config.storageFarmArea, 1 do
        local raw = gps.storageSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        if crop and crop.isCrop and (crop.name == 'air' or crop.name == 'emptyCrop') then
            database.updateStorage(slot, newCrop)
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

local function createOrderList(handleChild, handleParent)
    local orderList = {}
    for slot, crop in pairs(database.getFarm()) do
        if crop.isCrop then
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

    table.sort(order, function(a, b)
        return a.slot < b.slot
    end)

    return order
end


local function getRobotStatus()
    local messageToSend = serialization.serialize({ type = "getStatus" })
    tunnel.send(messageToSend)
    local _, _, _, _, _, message = event.pull(1, "modem_message")

    if message == nil then
        return false
    end

    local unserilized = serialization.unserialize(message)

    if unserilized.robotStatus then
        return unserilized.robotStatus
    end
    return false
end






return {
    SendToLinkedCards = SendToLinkedCards,
    getRobotStatus = getRobotStatus,
    scanFarm = scanFarm,
    createOrderList = createOrderList,
    isWeed = isWeed,
    isComMax = isComMax,
    scanEmptySlotStorage = scanEmptySlotStorage,
    scanStorage = scanStorage,
    fetchScan = fetchScan,
    getChargerSide = getChargerSide,
    cordtoScan = cordtoScan,
    setRobotSide = setRobotSide,
    cleanUp = cleanUp
}
