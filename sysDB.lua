local storage = {}
local reverseStorage = {}
local farm = {}
local logs = {}
local system = {}
local logsLimit = 100


-- ======================== LOGS LIST ========================
local function getLogs()
  return logs
end

local function getCountLogs()
  return #logs
end

local function setLogs(str, color)
  if not color then
    color = 'white'
  end

  local log = {
    date = os.date("%H:%M"),
    log = str,
    color = color
  }

  table.insert(logs, log)

  if #logs > logsLimit then
    table.remove(logs, 1)
  end
end

-- ======================== SYSTEM DATA ========================
local function getSystemData(key)
  return system[key]
end

local function setSystemData(key, value)
  system[key] = value
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
end

local function deleteFarm()
  farm = {}
end

-- ======================== STORAGE FARM ========================
local function getStorage()
  return storage
end

local function getStorageSlot(slot)
  return storage[slot]
end

local function updateStorage(slot, crop)
  storage[slot] = crop
  reverseStorage[crop.name] = slot
end

local function deleteStorage()
  storage = {}
  reverseStorage = {}
end

local function existInStorage(crop)
  if reverseStorage[crop.name] then
    return true
  else
    return false
  end
end


local function initDataBase()
  storage = {}
  reverseStorage = {}
  farm = {}
  logs = {}
  system = {}

  setSystemData("currentMode", 1)
  setSystemData("currentSubMode", 1)

  setSystemData("systemGrowth", 21)
  setSystemData("systemGain", 31)
  setSystemData("systemResistance", 0)
  setSystemData("systemEnabled", false)

  setSystemData("currentLogsLevel", 3)

  setSystemData('selectedMenuItem', 'IW')

  setSystemData("IWStep", 1)
end

return {
  initDataBase = initDataBase,
  getFarm = getFarm,
  getFarmSlot = getFarmSlot,
  updateFarm = updateFarm,
  deleteFarm = deleteFarm,
  getStorage = getStorage,
  getStorageSlot = getStorageSlot,
  updateStorage = updateStorage,
  deleteStorage = deleteStorage,
  existInStorage = existInStorage,
  getLogs = getLogs,
  getCountLogs = getCountLogs,
  setLogs = setLogs,
  setSystemData = setSystemData,
  getSystemData = getSystemData
}
