local config = require('sysConfig')
local database = require('sysDB')
local sys = require('sysFunction')
local breadingRound = 0;

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
        local foundedSchemaSlot = false;
        if not sys.isWeed(crop) and config.tierSchema[crop.name] then
            --local isInCorrectSlot = false
            for _, schemaSlot in pairs(config.tierSchema[crop.name]) do
                local schemaCrop = database.getFarmSlot(schemaSlot)
                if schemaCrop.name ~= crop.name then
                    table.insert(order, {
                        action = 'transplantParent',
                        slot = slot,
                        farm = 'working',
                        to = schemaSlot,
                        priority = config.priorities['transplantParent'],
                        slotName = schemaCrop.name
                    })
                    database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
                    database.updateFarm(schemaSlot, crop)
                    foundedSchemaSlot = true;
                    break
                end
            end
        end

        if foundedSchemaSlot then
            return order;
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
        elseif sys.isComMax(crop, 'working') then
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
                slotName = availableParent.name
            })
            database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
            database.updateFarm(availableParentSlot, crop)
        else
            local stat = crop.gr + crop.ga - crop.re
            local foundedSlot = false
            for _, parentSlot in pairs(parentSlots) do
                local parentCrop = database.getFarm()[parentSlot]
                if parentCrop and parentCrop.isCrop and crop.name == parentCrop.name then
                    local parentStat = parentCrop.gr + parentCrop.ga - parentCrop.re
                    if stat > parentStat then
                        print('child slot:' .. slot .. ' stat: gr=' .. crop.gr .. ' ga=' .. crop.ga .. ' re=' .. crop.re)
                        print('parent slot:' ..
                            parentSlot ..
                            ' stat: gr=' .. parentCrop.gr .. ' ga=' .. parentCrop.ga .. ' re=' .. parentCrop.re)
                        print('-----------------')
                        table.insert(order, {
                            action = 'transplantParent',
                            slot = slot,
                            to = parentSlot,
                            farm = 'working',
                            slotName = parentCrop.name,
                            priority = config.priorities['transplantParent']
                        })
                        database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
                        database.updateFarm(parentSlot, crop)
                        table.insert(order, {
                            action = 'placeCropStick',
                            slot = slot,
                            priority = config.priorities['placeCropStick'],
                            count = 2
                        })
                        foundedSlot = true
                        break
                    end
                end
            end
            if not foundedSlot then
                table.insert(order, {
                    action = 'removePlant',
                    slot = slot,
                    priority = config.priorities['removePlant']
                })
            end
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
    end
    return order
end

local function init()
    print("autoTier inited")
end

local function checkCondition()
    breadingRound = breadingRound + 1
    local storageSlot = database.getStorageSlot(config.storageFarmArea)
    if not storageSlot then
        return false
    end

    if storageSlot.isCrop and storageSlot.name ~= 'air' and storageSlot.name ~= 'emptyCrop' and not sys.isWeed(storageSlot) then
        print('Missing slots in storage')
        return true
    end

    if breadingRound >= config.maxBreedRound then
        print('maxBreedRound')
        return true
    end

    return false
end

return {
    handleParent = handleParent,
    handleChild = handleChild,
    checkCondition = checkCondition,
    init = init
}
