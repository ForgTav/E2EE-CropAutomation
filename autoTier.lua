local config = require('sysConfig')
local database = require('sysDB')
local sys = require('sysFunction')

local function handleChild(slot, crop)
    local order = {}
    local availableParentSlot, availableParent
    local parentSlots = database.getParentSlots()

    -- Найти пустой родительский слот
    for _, parentSlot in ipairs(parentSlots) do
        local parentCrop = database.getFarmSlot(parentSlot)
        if parentCrop and (parentCrop.name == 'emptyCrop' or parentCrop.name == 'air') then
            availableParentSlot = parentSlot
            availableParent = parentCrop
            break
        end
    end

    if crop.isCrop and crop.name ~= 'emptyCrop' then
        if not sys.isWeed(crop) and config.tierSchema[crop.name] then
            for _, schemaSlot in pairs(config.tierSchema[crop.name]) do
                if not database.existInFarmSlot(schemaSlot, crop) then
                    table.insert(order, {
                        action = 'transplantParent',
                        slot = slot,
                        farm = 'working',
                        to = schemaSlot,
                        priority = config.priorities['transplantParent'],
                        slotName = database.getFarmSlot(schemaSlot)
                    })
                    database.updateFarm(slot, { isCrop = true, name = 'air' })
                    database.updateFarm(schemaSlot, crop)
                    break
                end
            end
        elseif crop.name == 'air' then
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
            table.insert(order, {
                action = 'transplant',
                slot = slot,
                to = sys.scanEmptySlotStorage(crop),
                farm = 'storage',
                slotName = 'air',
                priority = config.priorities['transplant']
            })
            database.updateFarm(slot, { isCrop = true, name = 'air' })
            database.updateStorage(slot, crop)
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
            database.updateFarm(slot, { isCrop = true, name = 'air' })
            database.updateFarm(availableParentSlot, crop)
        else
            table.insert(order, {
                action = 'removePlant',
                slot = slot,
                priority = config.priorities['removePlant']
            })
        end
    end

    return order
end

local function handleParent(slot, crop)
    local order = {}
    if crop.name == 'air' then
        return order
    elseif sys.isWeed(crop) then
        table.insert(order, {
            action = 'deweed',
            slot = slot,
            priority = config.priorities['deweed']
        })
    elseif crop.name == "emptyCrop" then
        return order
    elseif config.tierSchema[crop.name] and not database.existInFarmSlot(slot, crop.name) then
        for _, schemaSlot in pairs(config.tierSchema[crop.name]) do
            print(name)
            if schemaSlot ~= slot then
                table.insert(order, {
                    action = 'transplantParent',
                    slot = slot,
                    farm = 'working',
                    to = schemaSlot,
                    priority = config.priorities['transplantParent'],
                    slotName = database.getFarmSlot(schemaSlot)
                })
                database.updateFarm(slot, { isCrop = true, name = 'air' })
                database.updateFarm(schemaSlot, crop)
                break
            end
        end
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

return {
    handleParent = handleParent,
    handleChild = handleChild,
    init = init
}
