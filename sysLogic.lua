local db = require('sysDB')
local sys = require('sysFunction')
local ui = require('sysUI')
local config = require('sysConfig')
local priorities = {
  deweed = 1,
  forceRemovePlant = 2,
  transplantParent = 3,
  transplant = 4,
  removePlant = 8,
  placeCropStick = 9,
  removeCrop = 10
}

local function isInLogicalGrid(slot, logicalGridSize, realGridSize)
  local col = math.floor((slot - 1) / realGridSize) + 1
  local indexInCol = (slot - 1) % realGridSize
  local row

  if col % 2 == 1 then
    row = indexInCol + 1
  else
    row = realGridSize - indexInCol
  end

  return row <= logicalGridSize and col <= logicalGridSize
end

local function transplantToParent(slot, toSlot, crop, toCrop, logStr)
  db.updateFarm(slot, { isCrop = true, name = "air", fromScan = false })
  crop.fromScan = false
  local oldCrop = db.getFarmSlot(toSlot)
  if oldCrop and oldCrop.warningCounter then
    crop.warningCounter = oldCrop.warningCounter
  end

  db.updateFarm(toSlot, crop)
  return {
    action = "transplantParent",
    slot = slot,
    to = toSlot,
    farm = "working",
    priority = priorities.transplantParent,
    slotName = toCrop.name,
    logLevel = 2,
    log = logStr
  }
end

local function transplantToStorage(slot, crop, logStr)
  local emptySlot = sys.getEmptySlotStorage()
  if not emptySlot then
    return nil
  end

  if not logStr then
    logStr = ''
  end

  db.updateFarm(slot, { isCrop = true, name = "air", fromScan = false })
  crop.fromScan = false
  db.updateStorage(emptySlot, crop)
  logStr = logStr .. string.format('transplant to storage: slot %s', emptySlot)
  return {
    action = "transplant",
    slot = slot,
    to = emptySlot,
    farm = "storage",
    slotName = "air",
    priority = priorities.transplant,
    logLevel = 1,
    log = logStr,
    color = 'green'
  }, {
    action = "placeCropStick",
    slot = slot,
    priority = priorities.placeCropStick,
    count = 2,
    logLevel = 3,
    log = string.format("Order - Place crop stick on slot %d", slot)
  }
end

local function getParentSlots(logicalGridSize, realGridSize)
  local slots = {}
  for slot = 1, realGridSize ^ 2, 1 do
    if slot % 2 > 0 and isInLogicalGrid(slot, logicalGridSize, realGridSize) then
      table.insert(slots, slot)
    end
  end
  return slots
end

local function isSuitableParent(crop, currentMode, targetCrop)
  if not crop or not crop.isCrop then
    return false
  end

  if currentMode == 1 then
    return crop.name == "emptyCrop" or crop.name == "air"
  elseif currentMode == 2 or currentMode == 3 then
    return crop.name ~= targetCrop
  else
    return false
  end
end

local function handleChild(args)
  local order = {}
  local slot = args.slot
  local crop = args.crop
  local currentMode = args.currentMode
  local currentSubMode = args.currentSubMode
  local targetCrop = args.targetCrop
  local parentSlots = args.parentSlots
  local availableParentSlot, availableParent


  if crop.name == "air" then
    return { { action = "placeCropStick", slot = slot, priority = priorities.placeCropStick, count = 2, logLevel = 3, log = string.format("Order - Place crop stick on slot: %d", slot) } }
  elseif crop.isCrop and crop.name == "emptyCrop" then
    if crop.crossingbase == 0 then
      return { { action = "placeCropStick", slot = slot, priority = priorities.placeCropStick, count = 1, logLevel = 3, log = string.format("Order - Place crop stick on slot: %d", slot) } }
    else
      return order
    end
  elseif sys.isWeed(crop) then
    return { { action = "deweed", slot = slot, priority = priorities.deweed, logLevel = 3, log = string.format("Order - Weed remove on slot: %d", slot) } }
  elseif currentMode ~= 2 and sys.isMaxStat(crop) then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities.forceRemovePlant,
      needCropStick = false,
      logLevel = 3,
      log = string.format("Order - Too high stats on slot: %d, Name - %s; Growth - %d, Gain - %d, Resistance - %d",
        slot, crop.name, crop.gr, crop.ga, crop.re)
    })
    return order
  end

  if (currentMode == 1 and currentSubMode ~= 2) or currentMode == 2 or currentMode == 3 then
    for _, parentSlot in ipairs(parentSlots) do
      local parentCrop = db.getFarmSlot(parentSlot)
      if parentCrop and parentCrop.fromScan and isSuitableParent(parentCrop, currentMode, targetCrop) then
        availableParentSlot = parentSlot
        availableParent = parentCrop
      end
    end
  end

  -- === AutoTier ===
  if currentMode == 1 then
    if crop.isCrop and crop.name ~= "emptyCrop" then
      if currentSubMode == 1 and config.tierSchema[crop.name] then
        for _, schemaSlot in pairs(config.tierSchema[crop.name]) do
          local schemaCrop = db.getFarmSlot(schemaSlot)
          if schemaCrop and schemaCrop.fromScan and schemaCrop.name ~= crop.name then
            table.insert(order,
              transplantToParent(slot, schemaSlot, crop, schemaCrop,
                string.format('AutoTier - Schema crop: %s; from slot: %d, to slot: %d', crop.name, slot, schemaSlot)
              ))
            return order
          end
        end
      elseif currentSubMode ~= 2 and availableParentSlot then
        table.insert(order,
          transplantToParent(slot, availableParentSlot, crop, availableParent,
            string.format('AutoTier - Available parent slot: %d; Transplant crop: %s; from slot: %d',
              availableParentSlot, crop.name, slot)
          ))
        return order
      end

      if not db.existInStorage(crop) then
        local transplant, placeStick = transplantToStorage(slot, crop,
          string.format('AutoTier - New crop: %s;', crop.name)
        )
        if transplant and placeStick then
          table.insert(order, transplant)
          table.insert(order, placeStick)
        end
        return order
      end
    end

    table.insert(order, {
      action = "removePlant",
      slot = slot,
      priority = priorities.removePlant,
      logLevel = 3,
      log = string.format("Order - Remove plant: %s; on slot: %d", crop.name, slot)
    })
    return order
  end

  -- === AutoStat ===
  if currentMode == 2 then
    if crop.name == targetCrop then
      local stat = crop.gr + crop.ga - crop.re
      local systemGrowth = db.getSystemData("systemGrowth") or 21
      local systemGain = db.getSystemData("systemGain") or 31
      local systemResistance = db.getSystemData("systemResistance") or 0
      local statsSettings = systemGrowth + systemGain - systemResistance

      if crop.gr == systemGrowth and crop.ga == systemGain and crop.re == systemResistance then
        local transplant, placeStick = transplantToStorage(slot, crop,
          string.format('AutoStat - Target stats; Growth - %d; Gain - %d; Resistance - %d;', crop.gr, crop.ga, crop.re)
        )
        if transplant and placeStick then
          table.insert(order, transplant)
          table.insert(order, placeStick)
        end
        return order
      elseif sys.isMaxStat(crop) then
        table.insert(order, {
          action = 'removePlant',
          slot = slot,
          priority = priorities.forceRemovePlant,
          needCropStick = false,
          logLevel = 3,
          log = string.format("Order - Too high stats on slot: %d, Name - %s; Growth - %d, Gain - %d, Resistance - %d",
            slot, crop.name, crop.gr, crop.ga, crop.re)
        })
      elseif stat > statsSettings then
        table.insert(order, {
          action = "removePlant",
          slot = slot,
          priority = priorities.removePlant,
          logLevel = 3,
          log = string.format(
            "AutoStat - remove plant, too high stats by settings on slot: %d, Name - %s; Growth - %d, Gain - %d, Resistance - %d",
            slot, crop.name, crop.gr, crop.ga, crop.re)
        })
        return order
      elseif availableParentSlot then
        table.insert(order,
          transplantToParent(slot, availableParentSlot, crop, availableParent,
            string.format('AutoStat - Available parent slot: %d; Transplant crop: %s, from slot: %d',
              availableParentSlot, crop.name, slot)
          ))
        return order
      else
        for _, pSlot in ipairs(parentSlots) do
          local pCrop = db.getFarmSlot(pSlot)
          if pCrop and pCrop.isCrop and pCrop.fromScan and pCrop.name ~= "emptyCrop" and pCrop.name ~= "air" then
            local parentStat = pCrop.gr + pCrop.ga - pCrop.re
            if stat > parentStat then
              table.insert(order,
                transplantToParent(slot, pSlot, crop, pCrop,
                  string.format(
                    'AutoStat - Replacing weaker parent; Strong slot %d: Growth - %d, Gain - %d, Resistance - %d; ↓; Weaker slot: %d, Growth - %d, Gain - %d, Resistance - %d',
                    slot, crop.gr, crop.ga, crop.re, pSlot, pCrop.gr, pCrop.ga, pCrop.re)
                ))
              return order
            end
          end
        end
      end
    end

    table.insert(order, {
      action = "removePlant",
      slot = slot,
      priority = priorities.removePlant,
      logLevel = 3,
      log = string.format("Order - Remove plant, nothing to do: %s on slot: %d", crop.name, slot)
    })
    return order
  end

  -- === AutoSpread ===
  if currentMode == 3 then
    if crop.name == targetCrop then
      if availableParentSlot then
        table.insert(order,
          transplantToParent(slot, availableParentSlot, crop, availableParent,
            string.format('AutoSpread - Available parent slot: %d; Transplant crop: %s, from slot: %d',
              availableParentSlot, crop.name, slot)
          ))
        return order
      else
        local transplant, placeStick = transplantToStorage(slot, crop,
          string.format('AutoSpread - Target crop: %s;', crop.name))
        if transplant then
          table.insert(order, transplant)
          table.insert(order, placeStick)
        end
        return order
      end
    else
      table.insert(order, {
        action = "removePlant",
        slot = slot,
        priority = priorities.removePlant,
        logLevel = 3,
        log = string.format("Order - Remove plant: %s; on slot: %d", crop.name, slot)
      })
      return order
    end
  end

  return order
end

local function handleParent(args)
  local order = {}

  local crop = args.crop
  local slot = args.slot

  if crop.name == 'air' or crop.name == "emptyCrop" then
    return order
  end

  if sys.isWeed(crop) then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = priorities.deweed,
      logLevel = 3,
      log = string.format("Order - Weed remove on slot: %d", slot)
    })
    return order
  end

  if slot ~= 1 and sys.isMaxStat(crop) then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities.forceRemovePlant,
      needCropStick = false,
      logLevel = 3,
      log = string.format("Order - Too high stats on slot: %d, Name - %s; Growth - %d, Gain - %d, Resistance - %d",
        slot, crop.name, crop.gr, crop.ga, crop.re)
    })
    return order
  end

  return order
end

local function handleNotLogical(args)
  local order = {}
  local slot = args.slot
  local crop = args.crop

  if crop.name == "air" then
    return {}
  elseif crop.name == "emptyCrop" then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      needCropStick = false,
      priority = priorities.removePlant,
      logLevel = 3,
      log = string.format("Order - Remove plant on slot: %d", slot)
    })
  elseif slot % 2 == 0 then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      needCropStick = false,
      priority = priorities.removePlant,
      logLevel = 3,
      log = string.format("Order - Remove plant on slot: %d", slot)
    })
  elseif slot % 2 == 1 and (sys.isWeed(crop) or sys.isMaxStat(crop)) then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities.forceRemovePlant,
      needCropStick = false,
      logLevel = 3,
      log = string.format("Order - Remove plant on slot: %d", slot)
    })
  end
  return order
end

local function limitedOrderList(list)
  local result = {}
  local count = 0
    for i = 1, #list do
        local order = list[i]
        if order.action == "deweed" then
          table.insert(result, order)
          count = count + 1
        elseif count < config.maxOrderList then
          table.insert(result, order)
          count = count + 1
        else
          break
        end
    end
  return result
end

local function createOrderList()
  local orderList = {}
  local currentMode = db.getSystemData('currentMode')
  local currentSubMode = db.getSystemData('currentSubMode') or nil
  local currentLevel = db.getSystemData('currentLogsLevel')
  local realGridSize = config.workingFarmSize or 6
  local logicalGridSize = config.modesGrid[currentMode] or realGridSize
  local targetCrop = db.getSystemData("systemTargetCrop")
  local parentSlots = getParentSlots(logicalGridSize, realGridSize)

  for slot, _ in pairs(db.getFarm()) do
    local crop = db.getFarmSlot(slot) or {}

    if crop and crop.isCrop then
      if not isInLogicalGrid(slot, logicalGridSize, realGridSize) then
        local tasks = handleNotLogical({
          crop = crop,
          slot = slot,
        })
        for _, task in pairs(tasks) do
          table.insert(orderList, task)
        end
      elseif crop.fromScan then
        local tasks = {}
        local args = {
          slot = slot,
          crop = crop,
          currentMode = currentMode,
          currentSubMode = currentSubMode,
          targetCrop = targetCrop,
          parentSlots = parentSlots
        }

        if slot % 2 == 0 then
          tasks = handleChild(args)
        else
          tasks = handleParent(args)
        end

        for _, task in pairs(tasks) do
          table.insert(orderList, task)
        end
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

  for _, task in ipairs(orderList) do
    local logLevel = task.logLevel or 1
    if logLevel <= currentLevel then
      local message = task.log or string.format("Order - %s on slot %d", task.action, task.slot)
      local color = task.color or nil
      db.setLogs(message, color)
    end
  end

  return orderList
end

local function executeCycle(cycle)
  db.setSystemData('systemCreateOrder', true)
  ui.UIloading(true)

  if not sys.scanFarm() then
    db.setSystemData('systemCreateOrder', false)
    ui.UIloading(false)
    return
  end

  if cycle == 0 then
    sys.scanStorage()
  end

  local order = createOrderList()
  if next(order) ~= nil then
    sys.sendTunnelRequestNoReply({ type = 'order', data = order })
    os.sleep(1.0)
  end

  if cycle == 1 then
    sys.scanStorage()
  end

  ui.UIloading(false)
  db.setSystemData('systemCreateOrder', false)
  os.sleep(5)
end

local function checkCondition()
  sys.scanCropStickChest()
  local countCropSticks = db.getSystemData('cropSticksCount')
  if countCropSticks and countCropSticks <= 64 then
    db.setSystemData('flagNeedCleanUp', true)
    db.setLogs(string.format('Exit - Only %d Crop Sticks available (min. 64 required)', countCropSticks), 'red')
    return true
  end

  sys.scanTrashOrChest()

  local storageEmptySlots = db.getSystemData('systemStorageEmptySlots')
  if storageEmptySlots == 0 then
    db.setSystemData('flagNeedCleanUp', true)
    db.setLogs(string.format('Exit - Storage farm has no available space'), 'red')
    return true
  end

  return false
end

local function sysExit()
  while not sys.getRobotStatus() do
    os.sleep(1)
  end
  db.setSystemData('systemCreateOrder', true)

  ui.UIloading(true)
  sys.scanFarm()
  sys.scanStorage()

  local order = sys.cleanUp()

  if next(order) ~= nil then
    while not sys.getRobotStatus() do
      os.sleep(1)
    end
    os.sleep(0.1)
    sys.sendTunnelRequestNoReply({ type = 'cleanUp', data = order })

    while not sys.getRobotStatus() do
      os.sleep(1)
    end
    os.sleep(0.1)

    sys.scanFarm()
    sys.scanStorage()
  else
    db.setLogs(string.format('CleanUp - No cleanup required. Empty order issued.'))
  end

  db.setSystemData("systemEnabled", false)
  db.setSystemData("flagNeedCleanUp", false)
  db.setSystemData('systemCreateOrder', false)
  ui.UIloading(false)
end

local function checkForcedFlags()
  return db.getSystemData("flagNeedCleanUp")
end

local function shouldExit()
  return checkForcedFlags() or checkCondition()
end

local function waitUntilSystemEnabledOrForced()
  while not db.getSystemData("systemEnabled") and not checkForcedFlags() do
    os.sleep(1)
  end
end

local function initLogic()
  local cycle = 0

  while true do
    waitUntilSystemEnabledOrForced()

    while not sys.getRobotStatus() do
      os.sleep(3)
    end

    if shouldExit() then
      sysExit()
    elseif db.getSystemData("systemEnabled") then
      executeCycle(cycle)
      cycle = (cycle % 3) + 1
    end
  end
end

return {
  initLogic = initLogic,
}
