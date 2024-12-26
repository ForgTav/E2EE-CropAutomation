local config = require('config')

local function isWeed(crop, farm)
    if farm == 'working' then
        return crop.name == 'weed' or
            crop.name == 'Grass'
    elseif farm == 'storage' then
        return crop.name == 'weed' or
            crop.name == 'Grass'
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


return {
    isWeed = isWeed,
    isComMax = isComMax
}
