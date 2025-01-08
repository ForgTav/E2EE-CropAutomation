local config = require('sysConfig')
local storage = {}
local reverseStorage = {}
local farm = {}
local reverseFarm = {}
local parentSlots = {}
local logs = {}
local logsLimit = 30

-- ======================== PARENT AND CHILD SLOTS ========================

local function getParentSlots()
  return parentSlots
end

local function updateParentSlots(slot)
  parentSlots[slot] = slot
end

local function deleteParentSlots(slot)
  parentSlots[slot] = nil
end

local function getPossibleParentSlots()
  for slot = 1, config.workingFarmArea, 1 do
    if slot % 2 > 0 then
      updateParentSlots(slot)
    end
  end
end

-- ======================== LOGS LIST ========================

local function getLogs()
  return logs
end

local function setLogs(log)
  for key, value in pairs(log) do
    table.insert(logs, value)
  end
  if #logs > logsLimit then
    table.remove(logs, 1)
  end
end

-- ======================== WORKING FARM ========================

local function getFarm()
  return farm
end

local function getFarmSlot(slot)
  return farm[slot]
end


local function updateFarm(slot, crop)
  farm[slot] = crop
  reverseFarm[crop.name] = slot
end

local function existInFarm(crop)
  if crop and crop.name and reverseFarm[crop.name] then
    return reverseFarm[crop.name]
  else
    return false
  end
end

local function existInFarmSlot(slot, crop)
  if reverseFarm[crop.name] == slot then
    return true
  else
    return false
  end
end

-- ======================== STORAGE FARM ========================

local function getStorage()
  return storage
end

local function getStorageSlot(slot)
  return storage[slot]
end


--local function resetStorage()
--  storage = {}
--end

local function updateStorage(slot, crop)
  storage[slot] = crop
  reverseStorage[crop.name] = slot
end

--[[
local function addToStorage(slot, crop)
  storage[slot] = crop
  reverseStorage[crop.name] = #storage
end
]] --

local function existInStorage(crop)
  if reverseStorage[crop.name] then
    return true
  else
    return false
  end
end

local function getSlotInReverse(crop)
  return reverseStorage[crop.name]
end

--local function nextStorageSlot()
--  return #storage + 1
--end

local function initDataBase()
  storage = {}
  reverseStorage = {}
  farm = {}
  reverseFarm = {}
  parentSlots = {}
  logs = {}
  getPossibleParentSlots()
end


return {
  initDataBase = initDataBase,
  getFarm = getFarm,
  getFarmSlot = getFarmSlot,
  updateFarm = updateFarm,
  getStorage = getStorage,
  getStorageSlot = getStorageSlot,
  updateStorage = updateStorage,
  existInStorage = existInStorage,
  getParentSlots = getParentSlots,
  existInFarm = existInFarm,
  existInFarmSlot = existInFarmSlot,
  deleteParentSlots = deleteParentSlots,
  getLogs = getLogs,
  setLogs = setLogs
}


--resetStorage = resetStorage,
--getOrder = getOrder,
--updateOrder = updateOrder,
--nextStorageSlot = nextStorageSlot,
