local component = require('component')
local event = require("event")
local os = require('os')
local config = require('sysConfig')
local gps = require('sysGPS')
local database = require('sysDB')
local serialization = require("serialization")
local tunnel = component.tunnel
local sensor = component.sensor
local targetCrop
local robotStatus = false
local robotSide
local sidesCharger = {
  { 0,  -1 },
  { 1,  0 },
  { 0,  1 },
  { -1, 0 },
}

local priorities = {
  deweed = 1,
  transplantParent = 2,
  transplant = 4,
  removePlant = 8,
  placeCropStick = 9
}

local function tprint(tbl, indent)
  indent = indent or 0
  for k, v in pairs(tbl) do
    local formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent + 1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))
    else
      print(formatting .. v)
    end
  end
end

local function savetxt(table)
  local file = io.open("test2.txt", "a")
  for key, value in pairs(table) do
    file:write(serialization.serialize(value) .. ",\n")
  end
  file:close()
end

local function getChargerSide()
  for i = 1, #sidesCharger do
    local cur_scan = sensor.scan(sidesCharger[i][1], 0, sidesCharger[i][2])
    if cur_scan.block and cur_scan.block.name == 'opencomputers:charger' then
      return i
    end
  end
  return nil
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
    if crop and crop.isCrop and crop.name ~= 'air' and crop.name ~= 'emptyCrop' and not database.existInStorage(crop) then
      database.updateStorage(slot, crop)
    end
  end
end

local function scanFarm()
  for slot = 1, config.workingFarmArea, 1 do
    local raw = gps.workingSlotToPos(slot)
    local cord = cordtoScan(raw[1], raw[2])
    local rawScan = sensor.scan(cord[1], 0, cord[2])
    local crop = fetchScan(rawScan)
    if crop and crop.isCrop then
      database.updateFarm(slot, crop)
    end
  end
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

local function isWeed(crop, farm)
  return (farm == 'working' or farm == 'storage') and (crop.name == 'weed' or crop.name == 'Grass')
end



local function scanFarmAndAddToDB(slot)
  local raw = gps.workingSlotToPos(slot)
  local cord = cordtoScan(raw[1], raw[2])
  local rawScan = sensor.scan(cord[1], 0, cord[2])
  local crop = fetchScan(rawScan)
  if crop then
    crop.slot = slot
    database.updateFarm(slot, crop)
  end
end

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
      priority = priorities['placeCropStick'],
      count = 2
    })
  elseif crop.isCrop and crop.name == "emptyCrop" then
    return order
  elseif isWeed(crop, 'working') then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = priorities['deweed']
    })
  elseif isComMax(crop, 'working') and not availableParentSlot then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities['removePlant']
    })
  elseif crop.name == targetCrop then
    local stat = crop.gr + crop.ga - crop.re
    if availableParentSlot then
      table.insert(order, {
        action = 'transplantParent',
        slot = slot,
        to = availableParentSlot,
        farm = 'working',
        priority = priorities['transplantParent'],
        slotName = availableParent.name
      })
      database.updateFarm(slot, { isCrop = true, name = 'air' })
      database.updateFarm(availableParentSlot, crop)
    elseif stat >= config.autoStatThreshold then
      table.insert(order, {
        action = 'transplant',
        slot = slot,
        to = scanEmptySlotStorage(crop),
        farm = 'storage',
        slotName = 'air',
        priority = priorities['transplant']
      })
      database.updateFarm(slot, { isCrop = true, name = 'air' })
      database.updateStorage(slot, crop)
      table.insert(order, {
        action = 'placeCropStick',
        slot = slot,
        priority = priorities['placeCropStick'],
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
              priority = priorities['transplant']
            })
            database.updateFarm(slot, { isCrop = true, name = 'air' })
            database.updateFarm(parentSlot, crop)
            table.insert(order, {
              action = 'placeCropStick',
              slot = slot,
              priority = priorities['placeCropStick'],
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
          priority = priorities['removePlant']
        })
      end
    end
  elseif config.keepMutations and not database.existInStorage(crop) then
    table.insert(order, {
      action = 'transplant',
      slot = slot,
      to = database.nextStorageSlot(),
      farm = 'storage',
      priority = priorities['transplant']
    })
    database.updateFarm(slot, { isCrop = true, name = 'air' })
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
  if crop.name == 'air' then
    return order
  end
  if isWeed(crop, 'working') then
    table.insert(order, {
      action = 'deweed',
      slot = slot,
      priority = priorities['deweed']
    })
  elseif crop.isCrop and crop.name == "emptyCrop" then
    return order
  elseif isComMax(crop, 'working') then
    table.insert(order, {
      action = 'removePlant',
      slot = slot,
      priority = priorities['removePlant']
    })
  else
    database.deleteParentSlots(slot)
  end
  return order
end

local function createOrderList()
  local orderList = {}
  for slot, crop in ipairs(database.getFarm()) do
    if crop.isCrop then
      local tasks = {}
      if slot % 2 == 0 then
        tasks = handleChild(slot, crop)
      else
        tasks = handleParent(slot, crop)
      end
      for _, task in ipairs(tasks) do
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

local function scanFarmAndAddToQueue()
  for slot = 1, config.workingFarmArea do
    scanFarmAndAddToDB(slot)
  end
  return createOrderList()
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

local function SendToLinkedCards(msg)
  local messageToSend = serialization.serialize(msg)
  tunnel.send(messageToSend)
end

local function main()
  print("getChargerSide")
  robotSide = getChargerSide()
  if not robotSide then
    print('Charger not found')
    os.exit()
  end

  local cord = cordtoScan(0, 1)
  local scan = fetchScan(sensor.scan(cord[1], 0, cord[2]))
  if not scan.isCrop or (scan.name == 'air' or scan.name == 'emptyCrop') then
    print('Not found targetCrop')
    os.exit()
  end
  targetCrop = scan.name
  print("targetCrop:" .. scan.name)

  print("initDataBase")
  database.initDataBase()
  scanStorage()
  scanFarm()


  while true do
    local loopForStatus = true
    print("awaitRobotStatus")
    while loopForStatus do
      robotStatus = getRobotStatus()
      if robotStatus then
        loopForStatus = false
      end
      os.sleep(1)
    end

    print("getOrder")
    local order = scanFarmAndAddToQueue()
    if next(order) == nil then
      print("emptyOrder")
    else
      print("sendOrder")
      SendToLinkedCards({ type = 'order', data = order })
    end
    print("sleep5S")
    os.sleep(5)
  end
end

main()
