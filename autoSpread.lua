local component = require('component')
local config = require('sysConfig')
local database = require('sysDB')
local os = require('os')
local sys = require('sysFunction')
local sensor = component.sensor
local targetCrop
local ui = require("sysUI")

local function handleChild(slot, crop)
  local order = {}
  local availableParentSlot = nil
  local availableParent = nil
  local parentSlots = database.getParentSlots()
  for _, parentSlot in pairs(parentSlots) do
    local parentCrop = database.getFarmSlot(parentSlot)
    if parentCrop and (parentCrop.name == 'emptyCrop' or parentCrop.name == 'air') then
      availableParentSlot = parentSlot
      availableParent = parentCrop
      break
    end
  end

  local priorities = config.priorities

  if crop.name == 'air' then
    table.insert(order, {
      action = 'placeCropStick',
      slot = slot,
      priority = priorities['placeCropStick'],
      count = 2
    })
  elseif crop.isCrop and crop.name == "emptyCrop" then
    if crop.crossingbase == 0 then
      table.insert(order, {
        action = 'placeCropStick',
        slot = slot,
        priority = priorities['placeCropStick'],
        count = 1
      })
    else
      return order
    end
  elseif sys.isWeed(crop) then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = priorities['deweed']
    })
  elseif sys.isComMax(crop, 'working') and not availableParentSlot then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities['removePlant']
    })
  elseif crop.name == targetCrop then
    if availableParentSlot then
      table.insert(order, {
        action = 'transplantParent',
        slot = slot,
        to = availableParentSlot,
        farm = 'working',
        priority = priorities['transplantParent'],
        slotName = availableParent.name,
        isSchema = false,
        targetCrop = false,
      })
      database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
      database.updateFarm(availableParentSlot, crop)
    else
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
        priority = priorities['transplant']
      })
      database.updateFarm(slot, { isCrop = true, name = 'air', fromScan = false })
      database.updateStorage(emptySlot, crop)
      table.insert(order, {
        action = 'placeCropStick',
        slot = slot,
        priority = priorities['placeCropStick'],
        count = 2
      })
    end
  else
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities['removePlant']
    })
  end
  return order
end

local function handleParent(slot, crop)
  local order = {}
  if crop.name == 'air' or (crop.isCrop and crop.name == "emptyCrop") then
    return order
  elseif sys.isWeed(crop) then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = config.priorities['deweed']
    })
  elseif sys.isComMax(crop, 'working') then
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
  local cord = sys.cordtoScan(0, 1)
  local scan = sys.fetchScan(sensor.scan(cord[1], 0, cord[2]))
  if not scan.isCrop or (scan.name == 'air' or scan.name == 'emptyCrop') then
    sys.printCenteredText('Not found targetCrop')
    os.exit()
  end
  --print("targetCrop:" .. scan.name)
  --ui.printCenteredText("autoSpread inited")
  targetCrop = scan.name
end

local function checkCondition()
  local storageSlot = database.getStorageSlot(config.storageFarmArea)
  if not storageSlot then
    return false
  end

  if storageSlot.isCrop and storageSlot.name ~= 'air' and storageSlot.name ~= 'emptyCrop' and not sys.isWeed(storageSlot) then
    --TODO THROW ERROR
    --print('Missing slots in storage')
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
