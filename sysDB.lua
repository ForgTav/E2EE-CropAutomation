local config = require('sysConfig')
local storage = {}
local reverseStorage = {}
local farm = {}
local order = {}
local ParentSlots = {}

function tprint(tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
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

-- ======================== PARENT AND CHILD SLOTS ========================

local function getParentSlots()
  return ParentSlots
end

local function updateParentSlots(slot)
  ParentSlots[slot] = slot
end

local function deleteParentSlots(slot)
  ParentSlots[slot] = nil
end

local function getPossibleParentSlots()
  for slot = 1, config.workingFarmArea, 1 do
    if slot % 2 > 0 then
      updateParentSlots(slot)
    end
  end
end

-- ======================== ORDER LIST ========================

local function getOrder()
  return order
end

local function updateOrder(newOrder)
  order = newOrder
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

-- ======================== STORAGE FARM ========================

local function getStorage()
  return storage
end


local function resetStorage()
  storage = {}
end

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


local function nextStorageSlot()
  return #storage + 1
end

local function initDataBase()
  getPossibleParentSlots()
end


return {
  initDataBase = initDataBase,
  getFarm = getFarm,
  getFarmSlot = getFarmSlot,
  updateFarm = updateFarm,
  getStorage = getStorage,
  resetStorage = resetStorage,
  updateStorage = updateStorage,
  existInStorage = existInStorage,
  nextStorageSlot = nextStorageSlot,
  getOrder = getOrder,
  updateOrder = updateOrder,
  getParentSlots = getParentSlots,
  updateParentSlots = updateParentSlots,
  deleteParentSlots = deleteParentSlots
}