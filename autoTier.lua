local action = require('action')
local os = require('os')
local database = require('database')
local gps = require('gps')
local scanner = require('scanner')
local config = require('config')
local events = require('events')
local serverApi = require('serverApi')
local breedRound = 0
local lowestTier
local lowestTierSlot
local lowestStat
local lowestStatSlot

local computer = require('computer')

-- =================== MINOR FUNCTIONS ======================
local function updateLowest()
    local farm = database.getFarm()
    lowestTier = 99
    lowestTierSlot = 0
    lowestStat = 99
    lowestStatSlot = 0

    -- Find lowest tier slot
    for slot = 1, config.workingFarmArea, 2 do
        local crop = farm[slot]
        if crop.isCrop then
            if crop.name == 'air' or crop.name == 'emptyCrop' then
                lowestTier = 0
                lowestTierSlot = slot
                break
            elseif crop.tier < lowestTier then
                lowestTier = crop.tier
                lowestTierSlot = slot
            end
        end
    end

    -- Find lowest stat slot amongst the lowest tier
    if config.statWhileTiering then
        for slot = 1, config.workingFarmArea, 2 do
            local crop = farm[slot]
            if crop.isCrop then
                if crop.name == 'air' or crop.name == 'emptyCrop' then
                    lowestStat = 0
                    lowestStatSlot = slot
                    break
                elseif crop.tier == lowestTier then
                    local stat = crop.gr + crop.ga - crop.re
                    if stat < lowestStat then
                        lowestStat = stat
                        lowestStatSlot = slot
                    end
                end
            end
        end
    end
end


local function checkChild(slot, crop, firstRun)
    if crop.isCrop and crop.name ~= 'emptyCrop' then
        if crop.name == 'air' then
            action.placeCropStick(2)
        elseif scanner.isWeed(crop, 'working') then
            action.deweed()
            action.placeCropStick()
        elseif scanner.isComMax(crop, 'working') then
            action.removePlant()
            action.placeCropStick(2)
        elseif firstRun then
            return

            -- Seen before, tier up working farm
        elseif database.existInStorage(crop) then
            local stat = crop.gr + crop.ga - crop.re
            if crop.tier > lowestTier then
                action.transplant(gps.workingSlotToPos(slot), gps.workingSlotToPos(lowestTierSlot))
                action.placeCropStick(2)
                database.updateFarm(lowestTierSlot, crop)
                updateLowest()

                -- Not higher tier, stat up working farm
            elseif (config.statWhileTiering and crop.tier == lowestTier and stat > lowestStat) then
                action.transplant(gps.workingSlotToPos(slot), gps.workingSlotToPos(lowestStatSlot))
                action.placeCropStick(2)
                database.updateFarm(lowestStatSlot, crop)
                updateLowest()
            else
                action.removePlant()
                action.placeCropStick(2)
            end

            -- Not seen before, move to storage
        else
            action.transplant(gps.workingSlotToPos(slot), gps.storageSlotToPos(database.nextStorageSlot()))
            action.placeCropStick(2)
            database.addToStorage(crop)
        end
    end
end


local function checkParent(slot, crop, firstRun)
    if crop.isCrop and crop.name ~= 'air' and crop.name ~= 'emptyCrop' then
        if scanner.isWeed(crop, 'working') then
            action.deweed()
        elseif scanner.isComMax(crop, 'working') then
            action.removePlant()
        end

        database.updateFarm(slot, { isCrop = true, name = 'emptyCrop' })
        if not firstRun then
            updateLowest()
        end
    end
end

-- ====================== THE LOOP ======================

local function tierOnce(firstRun)
    for slot = 1, config.workingFarmArea, 1 do
        -- Terminal Condition
        if breedRound > config.maxBreedRound then
            print('autoTier: Max Breeding Round Reached!')
            return false
        end

        -- Terminal Condition
        if #database.getStorage() >= config.storageFarmArea then
            print('autoTier: Storage Full!')
            return false
        end

        -- Terminal Condition
        if not firstRun then
            if lowestTier >= config.autoTierThreshold then
                print('autoTier: Minimum Tier Threshold Reached!')
                return false
            end
        end

        -- Terminal Condition
        if events.needExit() then
            print('autoTier: Received Exit Command!')
            return false
        end

        os.sleep(0)

        -- Scan
        gps.go(gps.workingSlotToPos(slot))
        local crop = serverApi.sendToLinkedCards(serverApi.initGetCrop())

        if firstRun then
            database.updateFarm(slot, crop)
        end

        if slot % 2 == 0 then
            checkChild(slot, crop, firstRun)
        else
            checkParent(slot, crop, firstRun)
        end

        if action.needCharge() then
            action.charge()
        end
    end
    return true
end

-- ======================== MAIN ========================

local function main()
    action.initWork()
    print('autoTier: Scanning Farm')
    print(string.format('autoTier: Target Tier %s', config.autoTierThreshold))

    -- First Run
    tierOnce(true)
    action.restockAll()
    updateLowest()

    -- Loop
    while tierOnce(false) do
        breedRound = breedRound + 1
        action.restockAll()
    end

    -- Terminated Early
    if events.needExit() then
        action.restockAll()
    end

    -- Finish
    if config.cleanUp then
        action.cleanUp()
    end

    events.unhookEvents()
    print('autoTier: Complete!')
end

main()
