--local robot = require('robot')
local config = require('sysConfig')

-- ======================== WORKING FARM ========================
--  _________________   5x5 Slot Map
-- |25 16 15 06 05|
-- |24 17 14 07 04|  One down from 01 is (0,0)
-- |23 18 WW 08 03|
-- |22 19 12 09 02|
-- |21 20 11 10 01|
--  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

local function workingSlotToPos(slot)
    local x = (slot - 1) // config.workingFarmSize
    local row = (slot - 1) % config.workingFarmSize
    local y

    if x % 2 == 0 then
        y = row + 1
    else
        y = -row + config.workingFarmSize
    end

    return { -x, y }
end

-- ======================== STORAGE FARM ========================
--  __________________________
-- |09 10 27 28 45 46 63 64 81|  9x9 Slot Map
-- |08 11 26 29 44 47 62 65 80|
-- |07 12 25 30 43 48 61 66 79|  Two left from 03 is (0,0)
-- |06 13 24 31 42 49 60 67 78|
-- |05 14 23 32 41 50 59 68 77|
-- |04 15 22 33 40 51 58 69 76|
-- |03 16 21 34 39 52 57 70 75|
-- |02 17 20 35 38 53 56 71 74|
-- |01 18 19 36 37 54 55 72 73|
--  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

local function storageSlotToPos(slot)
    local x = (slot - 1) // config.storageFarmSize + 2
    local row = (slot - 1) % config.storageFarmSize
    local y

    if x % 2 == 0 then
        y = row - config.storageFarmSize + config.workingFarmSize + 1
    else
        y = -row + config.workingFarmSize
    end

    return { x, y }
end




return {
    workingSlotToPos = workingSlotToPos,
    storageSlotToPos = storageSlotToPos
}
