--local robot = require('robot')
local config = require('sysConfig')

-- ======================== WORKING FARM ========================
--  _________________   6x6 Slot Map
-- |31 30 19 18 07 06|
-- |32 29 20 17 08 05|
-- |33 28 21 16 09 04|  One down from 01 is (0,0)
-- |34 27 22 15 10 03|
-- |35 26 23 14 11 02|
-- |36 25 24 13 12 01|
--  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

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
        y = row - config.storageFarmSize + config.workingFarmSize + 1 + config.workingFarmDefaultSize - config.workingFarmSize
    else
        y = -row + config.workingFarmSize
    end

    return { x, y }
end




return {
    workingSlotToPos = workingSlotToPos,
    storageSlotToPos = storageSlotToPos
}
