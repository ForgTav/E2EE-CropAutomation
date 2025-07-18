local config = {
    workingFarmSize = 6,
    storageFarmSize = 9,

    maxOrderList = 4,

    maxGrowth = 23,
    maxGain = 31,
    maxResistance = 2,

    seedTiers = {
        weed = 0,
        dark_oak_sapling = 1,
        acacia_sapling = 1,
        jungle_sapling = 1,
        birch_sapling = 1,
        spruce_sapling = 1,
        oak_sapling = 1,
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
    },

    tierSchema = {
        ["nether_wart"] = { 1, 3, 11, 13 },
        ["stickreed"] = { 5, 7, 9 },
        ["blazereed"] = { 25, 35 },
        ["diareed"] = { 17, 19, 31 },
        ["oil_berries"] = { 15, 23 },
        ["withereed"] = { 33, 29, 27 }
    },

    modesGrid = {
        [1] = 6, -- AutoTier
        [2] = 5, -- AutoStat
        [3] = 5  -- AutoSpread
    }

}
return config
