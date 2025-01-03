local component = require('component')
local config = require('sysConfig')
local database = require('sysDB')
local sys = require('sysFunction')
local breadingRound = 0;
local sensor = component.sensor

local modeConfig = {
    -- 1 = schema, 2 = targetCrop
    tierMode = 1,
    targetCrop = ''
}

local function handleChild(slot, crop)
    local order = {}
    local availableParentSlot, availableParent
    local parentSlots = database.getParentSlots()

    for _, parentSlot in pairs(parentSlots) do
        local parentCrop = database.getFarmSlot(parentSlot)
        if parentCrop and (parentCrop.name == 'emptyCrop' or parentCrop.name == 'air') then
            availableParentSlot = parentSlot
            availableParent = parentCrop
            break
        end
    end

    if crop.isCrop and crop.name ~= 'emptyCrop' then
        if modeConfig.tierMode == 1 and not sys.isWeed(crop) and config.tierSchema[crop.name] then
            local foundedSchemaSlot = false;
            for _, schemaSlot in pairs(config.tierSchema[crop.name]) do
                local schemaCrop = database.getFarmSlot(schemaSlot)
                if schemaCrop.name ~= crop.name then
                    table.insert(order, {
                        action = 'transplantParent',
                        slot = slot,
                        farm = 'working',
                        to = schemaSlot,
                        priority = config.priorities['transplantParent'],
                        slotName = schemaCrop.name,
                        isSchema = true,
                        targetCrop = false,
                    })
                    database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
                    database.updateFarm(schemaSlot, crop)
                    foundedSchemaSlot = true;
                    break
                end
            end
            if foundedSchemaSlot then
                return order;
            end
        elseif modeConfig.tierMode == 2 and crop.name == modeConfig.targetCrop then
            local foundedTargetSlot = false
            for _, parentSlot in pairs(parentSlots) do
                local parentCrop = database.getFarm()[parentSlot]
                if parentCrop and parentCrop.isCrop and parentCrop.name ~= crop.name then
                    table.insert(order, {
                        action = 'transplantParent',
                        slot = slot,
                        farm = 'working',
                        to = parentSlot,
                        priority = config.priorities['transplantParent'],
                        slotName = parentCrop.name,
                        targetCrop = true,
                        isSchema = false,
                    })
                    database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
                    database.updateFarm(parentSlot, crop)
                    foundedTargetSlot = true
                    break
                end
            end
            if foundedTargetSlot then
                return order;
            end
        end



        if crop.name == 'air' then
            table.insert(order, {
                action = 'placeCropStick',
                slot = slot,
                priority = config.priorities['placeCropStick'],
                count = 2
            })
        elseif sys.isWeed(crop) then
            table.insert(order, {
                action = 'deweed',
                slot = slot,
                priority = config.priorities['deweed']
            })
        elseif not database.existInStorage(crop) then
            local emptySlot = sys.getEmptySlotStorage()
            if not emptySlot then
                return order
            end

            table.insert(order, {
                action = 'transplant',
                slot = slot,
                to = emptySlot,
                farm = 'storage',
                slotName = 'air',
                priority = config.priorities['transplant']
            })
            database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
            database.updateStorage(emptySlot, crop)
            table.insert(order, {
                action = 'placeCropStick',
                slot = slot,
                priority = config.priorities['placeCropStick'],
                count = 2
            })
        elseif sys.isComMax(crop, 'working') and not availableParentSlot then
            table.insert(order, {
                action = 'removePlant',
                slot = slot,
                priority = config.priorities['removePlant']
            })
        elseif availableParentSlot then
            table.insert(order, {
                action = 'transplantParent',
                slot = slot,
                farm = 'working',
                to = availableParentSlot,
                priority = config.priorities['transplantParent'],
                slotName = availableParent.name,
                isSchema = false,
                targetCrop = false,
            })
            database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
            database.updateFarm(availableParentSlot, crop)
        else
            table.insert(order, {
                action = 'removePlant',
                slot = slot,
                priority = config.priorities['removePlant']
            })
        end
    elseif crop.isCrop and crop.name == 'emptyCrop' and crop.crossingbase == 0 then
        table.insert(order, {
            action = 'placeCropStick',
            slot = slot,
            priority = config.priorities['placeCropStick'],
            count = 1
        })
    end
    return order
end

local function handleParent(slot, crop)
    local order = {}
    if crop.name == 'air' or crop.name == "emptyCrop" then
        return order
    elseif sys.isWeed(crop) then
        table.insert(order, {
            action = 'deweed',
            slot = slot,
            priority = config.priorities['deweed']
        })
    elseif sys.isComMax(crop) then
        table.insert(order, {
            action = 'removePlant',
            slot = slot,
            priority = config.priorities['removePlant']
        })
    elseif not crop.isCrop then
        database.deleteParentSlots(slot)
    end
    return order
end

local function init()
    modeConfig.tierMode = 2

    local cord = sys.cordtoScan(0, 1)
    local scan = sys.fetchScan(sensor.scan(cord[1], 0, cord[2]))
    modeConfig.targetCrop = scan.name
end

local function checkCondition()
    breadingRound = breadingRound + 1
    local storageSlot = database.getStorageSlot(config.storageFarmArea)
    if not storageSlot then
        return false
    end

    if storageSlot.isCrop and storageSlot.name ~= 'air' and storageSlot.name ~= 'emptyCrop' and not sys.isWeed(storageSlot) then
        sys.printCenteredText('Missing slots in storage')
        return true
    end

    if breadingRound >= config.maxBreedRound then
        sys.printCenteredText('maxBreedRound')
        return true
    end

    return false
end

local function setConfig(key, value)
    modeConfig[key] = value
end

local function getConfig(key)
    return modeConfig[key]
end

return {
    handleParent = handleParent,
    handleChild = handleChild,
    checkCondition = checkCondition,
    init = init,
    setConfig = setConfig,
    getConfig = getConfig
}
