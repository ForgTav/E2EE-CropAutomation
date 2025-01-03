local config = {
    -- NOTE: EACH CONFIG SHOULD END WITH A COMMA

    -- Side Length of Working Farm
    workingFarmSize = nil,
    -- Side Length of Storage Farm
    storageFarmSize = nil,
    
    storageOffset = nil,

    -- Pickup any and all drops (don't change)
    keepDrops = true,

    -- Minimum Charge Level
    needChargeLevel = 0.2,

    -- =========== DO NOT CHANGE ===========

    -- The coordinate for charger
    chargerPos = { 0, 0 },
    -- The coordinate for the container contains crop sticks
    stickContainerPos = { -1, 0 },
    -- The coordinate for the container to store seeds, products, etc
    storagePos = { -2, 0 },
    -- The coordinate for the farmland that the dislocator is facing
    relayFarmlandPos = { 1, 1 },
    -- The coordinate for the transvector dislocator
    dislocatorPos = { 1, 2 },

    -- The slot for spade
    spadeSlot = 0,
    -- The slot for the transvector binder
    binderSlot = -1,
    -- The slot for crop sticks
    stickSlot = -2,
    -- The slot which the robot will stop storing items
    storageStopSlot = -3
}

return config
