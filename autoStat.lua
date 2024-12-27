local config = require('sysConfig')
local database = require('sysDB')
local sys = require('sysFunction')
local targetCrop

local function handleChild(slot, crop)
  local order = {}
  local availableParentSlot = nil
  local availableParent = nil
  for _, parentSlot in pairs(database.getParentSlots()) do
    local parentCrop = database.getFarmSlot(parentSlot)

    if parentCrop and (parentCrop.name == 'emptyCrop' or parentCrop.name == 'air') then
      availableParentSlot = parentSlot
      availableParent = parentCrop
      break
    end
  end

  if crop.name == 'air' then
    table.insert(order, {
      action = 'placeCropStick',
      slot = slot,
      priority = config.priorities['placeCropStick'],
      count = 2
    })
  elseif crop.isCrop and crop.name == "emptyCrop" then
    return order
  elseif sys.isWeed(crop) then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = config.priorities['deweed']
    })
  elseif sys.isComMax(crop, 'working') and not availableParentSlot then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = config.priorities['removePlant']
    })
  elseif crop.name == targetCrop then
    local stat = crop.gr + crop.ga - crop.re
    if availableParentSlot then
      table.insert(order, {
        action = 'transplantParent',
        slot = slot,
        to = availableParentSlot,
        farm = 'working',
        priority = config.priorities['transplantParent'],
        slotName = availableParent.name
      })
      database.updateFarm(slot, { isCrop = true, name = 'air' })
      database.updateFarm(availableParentSlot, crop)
    elseif stat >= config.autoStatThreshold then
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
    else
      local foundedSlot = false
      for _, parentSlot in ipairs(database.getParentSlots()) do
        local parentCrop = database.getFarm()[parentSlot]
        if parentCrop and parentCrop.isCrop and (parentCrop.name ~= 'emptyCrop' and parentCrop.name ~= 'air') then
          local parentStat = parentCrop.gr + parentCrop.ga - parentCrop.re
          if parentStat < stat then
            table.insert(order, {
              action = 'transplant',
              slot = slot,
              to = parentSlot,
              farm = 'working',
              slotName = parentCrop.name,
              priority = config.priorities['transplant']
            })
            database.updateFarm(slot, { isCrop = true, name = 'air' })
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
  elseif config.keepMutations and not database.existInStorage(crop) then
    table.insert(order, {
      action = 'transplant',
      slot = slot,
      to = database.nextStorageSlot(),
      farm = 'storage',
      priority = config.priorities['transplant']
    })
    database.updateFarm(slot, { isCrop = true, name = 'air' })
  else
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = config.priorities['removePlant']
    })
  end
  return order
end

local function handleParent(slot, crop)
  local order = {}
  if crop.name == 'air' then
    return order
  end
  if sys.isWeed(crop) then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = config.priorities['deweed']
    })
  elseif crop.isCrop and crop.name == "emptyCrop" then
    return order
  elseif sys.isComMax(crop, 'working') then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = config.priorities['removePlant']
    })
  else
    database.deleteParentSlots(slot)
  end
  return order
end

local function init()
  local cord = sys.cordtoScan(0, 1)
  local scan = sys.fetchScan(sensor.scan(cord[1], 0, cord[2]))
  if not scan.isCrop or (scan.name == 'air' or scan.name == 'emptyCrop') then
    print('Not found targetCrop')
    os.exit()
  end
  print("targetCrop:" .. scan.name)
  print("autoStat inited")
  targetCrop = crop
end


return {
  handleParent = handleParent,
  handleChild = handleChild,
  init = init
}
