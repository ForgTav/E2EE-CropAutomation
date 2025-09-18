local component = require('component')
local event = require("event")
local config = require('sysConfig')
local gps = require('sysGPS')
local serialization = require("serialization")
local db = require("sysDB")
local computer = require('computer')

local function getSensor()
    if component.isAvailable("sensor") then
        return component.sensor
    end
    return nil
end

local function getTunnel()
    if component.isAvailable("tunnel") then
        return component.tunnel
    end
    return nil
end

local function getChargerSide()
    local sidesCharger = {
        { 0,  -1 },
        { 1,  0 },
        { 0,  1 },
        { -1, 0 },
    }

    local sensor = getSensor()
    if not sensor then return nil end

    for i = 1, #sidesCharger do
        local cur_scan = sensor.scan(sidesCharger[i][1], 0, sidesCharger[i][2])
        if cur_scan ~= nil and cur_scan.block and cur_scan.block.name == 'opencomputers:charger' then
            return i
        end
    end
    return nil
end

local function sendTunnelRequest(request, expectedType, timeout)
    timeout = timeout or 3
    local tunnel = getTunnel()
    if not tunnel then return nil end
    tunnel.send(serialization.serialize(request))

    local startTime = computer.uptime()
    repeat
        local remaining = timeout - (computer.uptime() - startTime)
        if remaining <= 0 then break end
        local _, _, _, _, _, message = event.pull(remaining, "modem_message")
        if message then
            local decoded = serialization.unserialize(message)
            if decoded and decoded.type == expectedType then
                return decoded
            end
        end
    until false

    return nil
end

local function sendTunnelRequestNoReply(request)
    local tunnel = getTunnel()
    if not tunnel then return nil end
    tunnel.send(serialization.serialize(request))
end

local function getRobotStatus()
    local response = sendTunnelRequest({ type = "getStatus" }, "getStatus", 3)

    if not response then
        return false
    end

    if not response.charged then
        db.setLogs('Robot – Entered charging state. Awaiting full charge.', 'yellow')
        return false
    end

    return response.robotStatus or false
end

local function cordtoScan(x, y)
    local robotSide = db.getSystemData('robotSide')
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

local function fetchScan(rawScan)
    local block = rawScan.block
    local data = rawScan.data or {}
    local crop = data.Crop or {}

    local blockName = block.name
    local blockLabel = block.label or ""

    if blockName == "minecraft:air" or blockName == "GalacticraftCore:tile.brightAir" then
        return { isCrop = true, name = "air", fromScan = true, warningCounter = 0 }
    elseif blockName == "ic2:te" then
        if blockLabel == "Crop" then
            return {
                isCrop = true,
                name = "emptyCrop",
                crossingbase = crop.crossingBase or 0,
                fromScan = true, 
                warningCounter = 0
            }
        else
            local cropId = crop.cropId or "unknown"
            return {
                isCrop = true,
                name = cropId,
                gr = crop.statGrowth or 0,
                ga = crop.statGain or 0,
                re = crop.statResistance or 0,
                tier = config.seedTiers[cropId] or 0,
                weedex = crop.storageWeedEX or 0,
                water = crop.storageWater or 0,
                nutrients = crop.storageNutrients or 0,
                fromScan = true, 
                warningCounter = 0
            }
        end
    else
        return { isCrop = false, name = "block", fromScan = true, warningCounter = 0 }
    end
end

local function isMaxStat(crop, currentMode)
    local maxGrowth = config.maxGrowth or 21
    local maxGain = config.maxGain or 31
    local maxResistance = config.maxResistance or 2

    return crop.gr > maxGrowth or
        crop.ga > maxGain or
        crop.re > maxResistance or
        (crop.name == 'venomilia' and crop.gr > 7)
end

local function isWeed(crop)
    return crop.name == 'weed' or crop.name == 'Grass'
end

local function scanStorage()
    db.deleteStorage()
    os.sleep(0.1)

    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local emptyCounter = 0

    local storageFarmArea = 9 ^ 2
    for slot = 1, storageFarmArea, 1 do
        local raw = gps.storageSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        local oldCrop = db.getStorageSlot(slot) or nil

        if crop then
            db.updateStorage(slot, crop)
        end
    
        if crop.name == 'air' then
            emptyCounter = emptyCounter + 1
        end
    end

    db.setSystemData('systemStorageEmptySlots', emptyCounter)
end

local function scanFarm()
    --db.deleteFarm()
    os.sleep(0.1)

    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end
    local workingFarmSize = config.workingFarmSize
    local workingFarmArea = workingFarmSize ^ 2
    local foundedCrop = false

    for slot = 1, workingFarmArea do
        local raw = gps.workingSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], 0, cord[2])
        local crop = fetchScan(rawScan)
        local oldCrop = db.getFarmSlot(slot) or nil

        if crop then
            if not foundedCrop and crop.isCrop and crop.name ~= "air" and crop.name ~= "emptyCrop" and not isWeed(crop) then
                foundedCrop = true
            end
            
            if crop.name == "air" then
                local warningIncremental = 1
                if oldCrop and not oldCrop.fromScan then
                    warningIncremental = 5
                end
                local warningCounter = ((oldCrop and oldCrop.warningCounter) or 0) + warningIncremental
                if warningCounter > 10 then
                    --Force scan farmland
                    local rawScan = sensor.scan(cord[1], -1, cord[2])
                    if rawScan and rawScan.block then
                        local scanBlock = rawScan.block
                        if scanBlock.name ~= 'minecraft:farmland' then
                            crop.isCrop = false
                            crop.name = "block"
                            crop.fromScan = true
                            crop.warningCounter = warningCounter
                        else
                            crop.warningCounter = 0
                        end
                    end
                else
                    crop.warningCounter = warningCounter
                end
            end

            db.updateFarm(slot, crop)
        end
    end

    if not foundedCrop then
        db.setLogs('Order - Looks like there’s nothing planted in the working farm.', 'yellow')
        db.setSystemData('systemEnabled', false)

        return false;
    end

    return true
end

local function cleanUp()
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end
    local order = {}

    for slot, crop in pairs(db.getFarm()) do
        if crop.isCrop and (crop.name == 'emptyCrop' or isWeed(crop)) then
            table.insert(order, {
                farm = 'working',
                slot = slot,
            })
        elseif slot % 2 == 0 and crop.isCrop and crop.name ~= 'air' then
            table.insert(order, {
                farm = 'working',
                slot = slot,
            })
        end
    end

    local cord = cordtoScan(1, 1)
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local blankCrop = fetchScan(rawScan)

    if blankCrop.isCrop and (blankCrop.name == 'emptyCrop' or isWeed(blankCrop)) then
        table.insert(order, {
            farm = 'blankFarm'
        })
    end

    for slot, crop in pairs(db.getStorage()) do
        if crop.isCrop and (crop.name == 'emptyCrop' or isWeed(crop)) then
            table.insert(order, {
                farm = 'storage',
                slot = slot,
            })
        end
    end

    return order
end

local function getEmptySlotStorage()
    for slot, crop in pairs(db.getStorage()) do
        if crop.isCrop and (crop.name == 'emptyCrop' or crop.name == 'air') then
            return slot
        end
    end
end

local function forceScan(farm, slot)
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return false
    end

    local rawCord

    if farm == 1 then
        rawCord = gps.workingSlotToPos(slot)
    elseif farm == 2 then
        rawCord = gps.storageSlotToPos(slot)
    else
        return false;
    end

    local cord = cordtoScan(rawCord[1], rawCord[2])
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local crop = fetchScan(rawScan)
    if crop and farm == 1 then
        db.updateFarm(slot, crop)
        return true;
    elseif crop and farm == 2 then
        db.updateStorage(slot, crop)
        return true;
    end

    return false;
end

local function doTransplante()
    local transplateFromFarm = db.getSystemData('transplateFromFarm')
    local transplateToFarm = db.getSystemData('transplateToFarm')
    local transplateFromSlot = db.getSystemData('transplateFromSlot')
    local transplateToSlot = db.getSystemData('transplateToSlot')

    if not transplateFromFarm or not transplateToFarm or not transplateFromSlot or not transplateToSlot then
        db.setLogs('Actions - Missing transplant parameters', 'red')
        return false
    end

    while not getRobotStatus() do
        os.sleep(1)
    end

    if not forceScan(transplateFromFarm, transplateFromSlot) then
        db.setLogs('Actions - Unable to scan crop in "From" slot', 'yellow')
        return false
    elseif not forceScan(transplateToFarm, transplateToSlot) then
        db.setLogs('Actions - Unable to scan crop in "To" slot', 'yellow')
        return false
    end

    local fromCrop, toCrop, fromFarm, toFarm

    if transplateFromFarm == 1 then
        fromCrop = db.getFarmSlot(transplateFromSlot)
        fromFarm = 'working'
    elseif transplateFromFarm == 2 then
        fromCrop = db.getStorageSlot(transplateFromSlot)
        fromFarm = 'storage'
    end


    if not fromCrop then
        db.setLogs('Actions - No crop found in "From" slot', 'yellow')
        return false
    end

    if not fromCrop.isCrop then
        db.setLogs('Actions - "From" is not a valid crop', 'yellow')
        return false
    end

    if fromCrop.name == "air" then
        db.setLogs('Actions - "From" crop is air', 'yellow')
        return false
    elseif fromCrop.name == "emptyCrop" then
        db.setLogs('Actions - "From" crop is an empty crop', 'yellow')
        return false
    elseif isWeed(fromCrop) then
        db.setLogs('Actions - "From" crop is a weed', 'red')
        return false
    end

    if transplateToFarm == 1 then
        toCrop = db.getFarmSlot(transplateToSlot)
        toFarm = 'working'
    elseif transplateToFarm == 2 then
        toCrop = db.getStorageSlot(transplateToSlot)
        toFarm = 'storage'
    end

    if not toCrop then
        db.setLogs('Actions - No crop found in "To" slot', 'yellow')
        return false
    end

    if not toCrop.isCrop then
        db.setLogs('Actions - "To" is not a valid crop', 'yellow')
        return false
    end

    local toSlotName = toCrop.name
    local destroyTo = false;

    if toCrop.name == "air" then
        destroyTo = true
    elseif toCrop.name == "emptyCrop" then
        destroyTo = true
    elseif isWeed(toCrop) then
        destroyTo = true
    end

    if transplateFromFarm == transplateToFarm and transplateFromSlot == transplateToSlot then
        db.setLogs('Actions - Same crop in both From and To – lets hope its intentional', 'yellow')
        toSlotName = 'air'
        destroyTo = true
    end

    local order = {
        fromSlot = transplateFromSlot,
        toSlot = transplateToSlot,
        fromFarm = fromFarm,
        toFarm = toFarm,
        toSlotName = toSlotName,
        destroyTo = destroyTo
    }
    db.setLogs(string.format('Manual transplant from %s[%d] to %s[%d]', fromFarm, transplateFromSlot, toFarm,
        transplateToSlot), 'green')

    while not getRobotStatus() do
        os.sleep(1)
    end
    os.sleep(0.1)

    sendTunnelRequestNoReply({ type = 'manualTransplant', data = order })
    os.sleep(1)

    while not getRobotStatus() do
        os.sleep(1)
    end
    os.sleep(0.1)

    if not forceScan(transplateFromFarm, transplateFromSlot) then
        db.setLogs('Actions - Unable to scan crop in "From" slot', 'yellow')
        return false
    elseif not forceScan(transplateToFarm, transplateToSlot) then
        db.setLogs('Actions - Unable to scan crop in "To" slot', 'yellow')
        return false
    end

    return true;
end

local function scanCropStickChest()
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local cord = cordtoScan(-1, 0)
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local cropsticks = 0

    if rawScan and rawScan.data and rawScan.data.items then
        for _, item in ipairs(rawScan.data.items) do
            if item.name == 'ic2:crop_stick' then
                cropsticks = cropsticks + (item.size or 0)
            end
        end
    end
    db.setSystemData('cropSticksCount', cropsticks)
end

local function scanTrashOrChest()
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local cord = cordtoScan(-2, 0)
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local total = 0
    local occupied = 0
    local result = 0

    if rawScan and rawScan.data and rawScan.data.items then
        for _, item in pairs(rawScan.data.items) do
            total = total + 1
            if item.id and item.id ~= 0 then
                occupied = occupied + 1
            end
        end
    end

    if total ~= 0 then
        result = math.floor((occupied / total) * 100)
    end

    db.setSystemData('trashOrChestCount', result)
end

local function drawMessage(message, color)
    local gpu = component.gpu
    gpu.setForeground(color or 0xFFFFFF)
    print(message)
end

local function scanTargetCrop()
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local slot = 1
    local raw = gps.workingSlotToPos(slot)
    local cord = cordtoScan(raw[1], raw[2])
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local crop = fetchScan(rawScan)
    if crop and crop.isCrop then
        db.setSystemData('systemTargetCrop', crop.name)
        db.setSystemData('IWTargetCrop', true)
        return true
    end
    db.setSystemData('IWTargetCrop', false)
    return false;
end

local function scanSystemRobot(firstRun)
    db.setSystemData('IWRobotTools', false)
    local connectionSuccess = false
    local connectionData = {}
    local allPassed = true

    local linkedCardError = false
    local redstoneCardError = false
    local inventoryUpgradeError = false
    local inventoryControllerError = false
    local weedingTrowelError = false
    local transvectorBinderError = false

    if firstRun then
        drawMessage("Scanning robot", 0xFFFFFF)
    end

    for attempt = 1, 3 do
        local robotStatus = getRobotStatus()
        if robotStatus then
            os.sleep(0.1)
            local robotData = sendTunnelRequest({ type = 'scanSystemRobot' }, 'scanSystemRobot', 3)
            if robotData and robotData.data then
                connectionSuccess = true
                connectionData = robotData.data
                break
            end
        end
        os.sleep(0.5)
    end

    if connectionSuccess then
        linkedCardError = connectionData.linkedCard or false
        redstoneCardError = connectionData.redstoneCard or false
        inventoryUpgradeError = connectionData.inventoryUpgrade or false
        inventoryControllerError = connectionData.inventoryController or false
        weedingTrowelError = connectionData.weedingTrowel or false
        transvectorBinderError = connectionData.transvectorBinder or false
    end

    if not linkedCardError then
        if firstRun then
            drawMessage("Error: Linked Card error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Linked Card check passed.", 0x00FF00)
    end

    if not redstoneCardError then
        if firstRun then
            drawMessage("Error: Redstone Card error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Redstone Card check passed.", 0x00FF00)
    end

    if not inventoryUpgradeError then
        if firstRun then
            drawMessage("Error: Inventory Upgrade error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Inventory Upgrade check passed.", 0x00FF00)
    end

    if not inventoryControllerError then
        if firstRun then
            drawMessage("Error: Inventory Controller error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Inventory Controller check passed.", 0x00FF00)
    end


    if not weedingTrowelError then
        if firstRun then
            drawMessage("Error: Weeding Trowel detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Weeding Trowel passed.", 0x00FF00)
    end


    if not transvectorBinderError then
        if firstRun then
            drawMessage("Error: Transvector Binder error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Transvector Binder check passed.", 0x00FF00)
    end

    db.setSystemData('IWRobotTools', allPassed)
    db.setSystemData('linkedCard', linkedCardError)
    db.setSystemData('redstoneCard', redstoneCardError)
    db.setSystemData('inventoryUpgrade', inventoryUpgradeError)
    db.setSystemData('inventoryController', inventoryControllerError)
    db.setSystemData('weedingTrowel', weedingTrowelError)
    db.setSystemData('transvectorBinder', transvectorBinderError)

    return allPassed
end

local function checkSensor(firstRun)
    if component.isAvailable("sensor") then
        if firstRun then
            drawMessage("Success: Sensor check passed.", 0x00FF00)
        end
        db.setSystemData('IWSensor', true)
        return true
    end
    if firstRun then
        drawMessage("Error: Sensor error detected!", 0xFF0000)
    end
    db.setSystemData('IWSensor', false)
    return false
end

local function checkCharger(firstRun)
    local robotSide = getChargerSide()
    if not robotSide then
        if firstRun then
            drawMessage("Error: Charger error detected!", 0xFF0000)
        end
        db.setSystemData('IWCharger', false)
        return false
    end

    if firstRun then
        drawMessage("Success: Charger check passed.", 0x00FF00)
    end

    db.setSystemData('IWCharger', true)
    db.setSystemData('robotSide', robotSide)
    return true;
end

local function checkCropChest(firstRun)
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return false
    end
    local cord = cordtoScan(-1, 0)
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    if rawScan and rawScan.data then
        local scanBlock = rawScan.data
        if scanBlock and scanBlock.items then
            if firstRun then
                drawMessage("Success: Cropstick Chest check passed.", 0x00FF00)
            end
            db.setSystemData('IWCropChest', true)
            return true
        end
    end

    if firstRun then
        drawMessage("Error: Cropstick Chest error detected!", 0xFF0000)
    end
    db.setSystemData('IWCropChest', false)
    return false
end

local function checkTrashOrChest(firstRun)
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return false
    end

    local cord = cordtoScan(-2, 0)
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    if rawScan and rawScan.data then
        local scanBlock = rawScan.data
        if scanBlock and scanBlock.items then
            if firstRun then
                drawMessage("Success: Trash or chest check passed.", 0x00FF00)
            end
            db.setSystemData('IWTrashOrChest', true)
            return true
        end
    end
    if firstRun then
        drawMessage("Error: Trash or chest error detected!", 0xFF0000)
    end
    db.setSystemData('IWTrashOrChest', false)
    return false
end

local function checkRobot(firstRun)
    if firstRun then
        drawMessage("Scanning robot", 0xFFFFFF)
    end

    for i = 1, 3 do
        if firstRun then
            print('Attempt ' .. i)
        end
        local robotStatus = getRobotStatus()
        if robotStatus then
            if firstRun then
                drawMessage("Success: Robot check passed.", 0x00FF00)
            end
            db.setSystemData('IWRobotConnection', true)
            scanSystemRobot()
            return true
        end
        os.sleep(0.5)
    end

    if firstRun then
        drawMessage("Error: Robot error detected!", 0xFF0000)
    end
    db.setSystemData('IWRobotConnection', false)
    return false
end

local function checkFarm(firstRun)
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local workingFarmSize = config.workingFarmSize
    local farmWaterSucces = false
    local farmWaterBlockSuccess = false
    local farmFarmlandError = true
    local farmGridError = true
    local allPassed = true
    if firstRun then
        drawMessage("Analyze Farm Grid", 0xFFFFFF)
    end

    for slot = 1, workingFarmSize ^ 2 do
        local raw = gps.workingSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], -1, cord[2])

        if rawScan and rawScan.block then
            local scanBlock = rawScan.block

            if scanBlock.name ~= 'minecraft:farmland' and scanBlock.name ~= 'minecraft:water' then
                farmGridError = false
                farmFarmlandError = false
                break
            end

            if scanBlock.name == 'minecraft:water' then
                local rawScanWater = sensor.scan(cord[1], 0, cord[2])
                if rawScanWater and rawScanWater.block then
                    local rawScanWaterBlock = rawScanWater.block
                    if rawScanWaterBlock and rawScanWaterBlock.name ~= 'minecraft:air' then
                        farmWaterBlockSuccess = true
                    end
                end

                farmWaterSucces = true
            end
        end
    end

    if not farmGridError then
        if firstRun then
            drawMessage("Error: Farm grid error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Farm grid check passed.", 0x00FF00)
    end

    if not farmFarmlandError then
        if firstRun then
            drawMessage("Error: Farmland error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Farmland check passed.", 0x00FF00)
    end

    if not farmWaterSucces then
        if firstRun then
            drawMessage("Warning: Water source not found!", 0xFFFF00)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Water source check passed.", 0x00FF00)
    end

    if not farmWaterBlockSuccess then
        if firstRun then
            drawMessage("Error: The water source is not covered by the block!", 0xFFFF00)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Water source block check passed.", 0x00FF00)
    end

    db.setSystemData('IWWorkingFarm', allPassed)
    db.setSystemData('farmLand', farmFarmlandError)
    db.setSystemData('farmWater', farmWaterSucces)
    db.setSystemData('farmGrid', farmGridError)

    return allPassed
end

local function checkStorage(firstRun)
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local storageWaterSuccess = false
    local storageWaterBlockSuccess = false
    local storageGridError = true
    local storageFarmlandError = true
    local allPassed = true

    if firstRun then
        drawMessage("Analyze Storage Grid", 0xFFFFFF)
    end

    for slot = 1, 9 ^ 2 do
        local raw = gps.storageSlotToPos(slot)
        local cord = cordtoScan(raw[1], raw[2])
        local rawScan = sensor.scan(cord[1], -1, cord[2])

        if rawScan and rawScan.block then
            local scanBlock = rawScan.block

            if scanBlock.name ~= 'minecraft:farmland' and scanBlock.name ~= 'minecraft:water' then
                storageGridError = false
                storageFarmlandError = false
                break
            end

            if scanBlock.name == 'minecraft:water' then
                local rawScanWater = sensor.scan(cord[1], 0, cord[2])
                if rawScanWater and rawScanWater.block then
                    local rawScanWaterBlock = rawScanWater.block
                    if rawScanWaterBlock and rawScanWaterBlock.name ~= 'minecraft:air' then
                        storageWaterBlockSuccess = true
                    end
                end

                storageWaterSuccess = true
            end
        end
    end

    if not storageGridError then
        if firstRun then
            drawMessage("Error: Storage grid error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Storage grid check passed.", 0x00FF00)
    end

    if not storageFarmlandError then
        if firstRun then
            drawMessage("Error: Farmland error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Farmland check passed.", 0x00FF00)
    end

    if not storageWaterSuccess then
        if firstRun then
            drawMessage("Warning: Water source not found!", 0xFFFF00)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Water source check passed.", 0x00FF00)
    end

    if not storageWaterBlockSuccess then
        if firstRun then
            drawMessage("Error: The water source is not covered by the block!", 0xFFFF00)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Water source block check passed.", 0x00FF00)
    end

    db.setSystemData('IWStorageFarm', allPassed)
    db.setSystemData('storageLand', storageFarmlandError)
    db.setSystemData('storageGrid', storageGridError)
    db.setSystemData('storageWater', storageWaterSuccess)

    return allPassed
end

local function checkDislocatorAndBlank(firstRun)
    local sensor = getSensor()
    if not sensor then
        db.setLogs('ERROR – OC Sensor not found', 'red')
        return nil
    end

    local cord, rawScan
    local blankFarmError = true
    local transvectorDislocatorError = true
    local allPassed = true

    if firstRun then
        drawMessage("Analyze Blank Farmland", 0xFFFFFF)
    end

    cord = cordtoScan(1, 2)
    rawScan = sensor.scan(cord[1], 0, cord[2])
    if rawScan and rawScan.block then
        local scanBlock = rawScan.block
        if scanBlock.name ~= 'thaumictinkerer:transvector_dislocator' then
            transvectorDislocatorError = false
        end
    else
        transvectorDislocatorError = false
    end

    cord = cordtoScan(1, 1)
    rawScan = sensor.scan(cord[1], -1, cord[2])
    if rawScan and rawScan.block then
        local scanBlock = rawScan.block

        if scanBlock.name ~= 'minecraft:farmland' then
            blankFarmError = false
        end
    end

    if not blankFarmError then
        if firstRun then
            drawMessage("Error: Invalid or missing Blank Farmland.", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Blank Farmland check passed.", 0x00FF00)
    end

    if not transvectorDislocatorError then
        if firstRun then
            drawMessage("Error: Transvector Dislocator error detected!", 0xFF0000)
        end
        allPassed = false
    elseif firstRun then
        drawMessage("Success: Transvector Dislocator check passed.", 0x00FF00)
    end

    db.setSystemData('IWDislocatorAndBlank', allPassed)
    db.setSystemData('blankFarmland', blankFarmError)
    db.setSystemData('transvectorDislocator', blankFarmError)

    return allPassed
end

local function doSystemScan(firstRun)
    db.setSystemData('systemReady', false)

    if firstRun then
        drawMessage("Scan system", 0xFFFFFF)
    end

    if not checkSensor(firstRun) then
        return false
    end

    if not checkCharger(firstRun) then
        return false
    end

    if not checkCropChest(firstRun) then
        return false
    end

    if not checkTrashOrChest(firstRun) then
        return false
    end

    if not checkRobot(firstRun) then
        return false
    end

    if not checkFarm(firstRun) then
        return false
    end

    if not scanTargetCrop() then
        return false
    end

    if not checkDislocatorAndBlank(firstRun) then
        return false
    end

    if not checkStorage(firstRun) then
        return false
    end

    db.setSystemData('systemReady', true)
    return true
end

local function doIWSystemScan(target)
    if not target then return end

    if target == 'IWSensor' then
        return checkSensor()
    elseif target == 'IWCharger' then
        return checkCharger()
    elseif target == 'IWCropChest' then
        return checkCropChest()
    elseif target == 'IWTrashOrChest' then
        return checkTrashOrChest()
    elseif target == 'IWRobotConnection' then
        return checkRobot()
    elseif target == 'IWRobotTools' then
        return scanSystemRobot()
    elseif target == 'IWWorkingFarm' then
        return checkFarm()
    elseif target == 'IWTargetCrop' then
        return scanTargetCrop()
    elseif target == 'IWDislocatorAndBlank' then
        return checkDislocatorAndBlank()
    elseif target == 'IWStorageFarm' then
        return checkStorage()
    end
    return false
end

local function beforeStartSystem()
    scanCropStickChest()
    local countCropSticks = db.getSystemData('cropSticksCount')
    if countCropSticks and countCropSticks <= 64 then
        db.setLogs(
            string.format(
                'Exit - Only %d Crop Sticks available (min. 64 required); If you\'ve added more cropsticks, manually rescan the Cropstick Chest from the Actions menu.',
                countCropSticks), 'red')
        return false
    end

    local storageEmptySlots = db.getSystemData('systemStorageEmptySlots')
    if storageEmptySlots == 0 then
        db.setLogs(
            string.format(
                'Exit – Storage farm has no available space; If you have cleared the storage farm, run "scan storage" from the Actions menu.'),
            'red')
        return false
    end

    return true
end

return {
    getRobotStatus = getRobotStatus,
    sendTunnelRequestNoReply = sendTunnelRequestNoReply,
    scanFarm = scanFarm,
    isWeed = isWeed,
    isMaxStat = isMaxStat,
    scanStorage = scanStorage,
    doTransplante = doTransplante,
    fetchScan = fetchScan,
    cordtoScan = cordtoScan,
    cleanUp = cleanUp,
    getEmptySlotStorage = getEmptySlotStorage,
    doSystemScan = doSystemScan,
    doIWSystemScan = doIWSystemScan,
    scanTargetCrop = scanTargetCrop,
    scanCropStickChest = scanCropStickChest,
    scanTrashOrChest = scanTrashOrChest,
    beforeStartSystem = beforeStartSystem
}
