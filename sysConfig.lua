local config = {
    -- NOTE: EACH CONFIG SHOULD END WITH A COMMA

    -- Side Length of Working Farm
    workingFarmSize = 5,
    -- Side Length of Storage Farm
    storageFarmSize = 9,

    -- Once complete, remove all extra crop sticks to prevent the working farm from weeding
    cleanUp = true,
    -- Pickup any and all drops (don't change)
    keepDrops = true,
    -- Stat-up crops during autoTier (Very Slow)
    statWhileTiering = false,

    -- Minimum tier for the working farm during autoTier
    autoTierThreshold = 13,
    -- Minimum Gr + Ga - Re for the working farm during autoStat (21 + 31 - 0 = 52)
    autoStatThreshold = 52,
    -- Minimum Gr + Ga - Re for the storage farm during autoSpread (23 + 31 - 0 = 54)
    autoSpreadThreshold = 50,

    -- Maximum Growth for crops on the working farm
    workingMaxGrowth = 21,
    -- Maximum Resistance for crops on the working farm
    workingMaxResistance = 2,
    -- Maximum Growth for crops on the storage farm
    storageMaxGrowth = 23,
    -- Maximum Resistance for crops on the storage farm
    storageMaxResistance = 2,

    -- Minimum Charge Level
    needChargeLevel = 0.2,
    -- Max breed round before termination of autoTier.
    maxBreedRound = 1000,

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

config.workingFarmArea = config.workingFarmSize ^ 2
config.storageFarmArea = config.storageFarmSize ^ 2

config.seedTiers = {
    weed = 0,
    accacia_sapling = 1,
    jungle_sapling = 1,
    wheat = 1,
    beetroots = 1,
    pumpkin = 1,
    brown_mushroom = 2,
    blackthorn = 2,
    carrots = 2,
    cyazint = 2,
    dandelion = 2,
    flax = 2,
    melon = 2,
    potato = 2,
    red_mushroom = 2,
    reed = 2,
    rose = 2,
    tulip = 2,
    cocoa = 3,
    venomilia = 3,
    stickreed = 4,
    corpse_plant = 5,
    hops = 5,
    nether_wart = 5,
    terra_wart = 5,
    aurelia = 6,
    blazereed = 6,
    corium = 6,
    stagnium = 6,
    cyprium = 6,
    eatingplant = 6,
    egg_plant = 6,
    ferru = 6,
    milk_wart = 6,
    plumbiscus = 6,
    redwheat = 6,
    shining = 6,
    slime_plant = 6,
    spidernip = 7,
    coffee = 7,
    creeper_weed = 7,
    meat_rose = 7,
    tearstalks = 8,
    withereed = 8,
    oil_berries = 9,
    ender_blossom = 10,
    bobs_yer_uncle_ranks_berries = 11,
    diareed = 12,
}

config.tierSchema = {
    ["nether_wart"] = { 1, 9, 11 },
    ["stickreed"] = { 3, 5 },
    ["blazereed"] = { 7, 15 },
    ["diareed"] = { 17, 25 },
    ["withereed"] = { 19, 21, 23 }
}

config.sidesCharger = {
    { 0,  -1 },
    { 1,  0 },
    { 0,  1 },
    { -1, 0 },
}


config.priorities = {
    deweed = 1,
    transplantParent = 2,
    transplant = 4,
    removePlant = 8,
    placeCropStick = 9,
    removeCrop = 10
}

return config
