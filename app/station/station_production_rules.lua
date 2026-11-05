local Catalog = require("station_catalog")
local Quantity = {}
function Quantity.plantGenes(material, itemKind)
  if (itemKind or material.itemKind) == "vanilla" then return 1, 1, 1 end
  return material.g, material.ga, material.r
end

function Quantity.matchesDescriptor(seed, criteria)
  return seed.key == criteria.key and
      (seed.itemKind ~= "vanilla" or (criteria.g == nil and criteria.ga == nil and criteria.r == nil)) and
      (seed.g == nil or not Catalog.isDangerous(seed.key, seed.g)) and
      (criteria.g == nil or seed.g == criteria.g) and
      (criteria.ga == nil or seed.ga == criteria.ga) and
      (criteria.r == nil or seed.r == criteria.r)
end

function Quantity.outputKind(plant, cropKey)
  local crop = Catalog.get(cropKey or plant.key)
  if not crop then return nil, "UNKNOWN_CROP" end
  local growth, gain, resistance = Quantity.plantGenes(plant)
  if type(growth) ~= "number" or type(gain) ~= "number" or type(resistance) ~= "number" or
      growth % 1 ~= 0 or gain % 1 ~= 0 or resistance % 1 ~= 0 or growth < 0 or growth > 31 or
      gain < 0 or gain > 31 or resistance < 0 or resistance > 31 then
    return nil, "GENES_UNREADABLE"
  end
  return crop.vanillaSeeds and growth <= 1 and gain <= 1 and resistance <= 1 and "vanilla" or "ic2"
end

function Quantity.sourceMatches(plant, criteria, cropKey)
  cropKey = cropKey or plant.key
  local itemKind = Quantity.outputKind(plant, cropKey)
  local growth, gain, resistance = Quantity.plantGenes(plant)
  if not itemKind or not Catalog.canProceed(cropKey) or Catalog.isDangerous(cropKey, growth) then return false end
  if itemKind == "vanilla" then
    return cropKey == criteria.key and criteria.g == nil and criteria.ga == nil and criteria.r == nil
  end
  return cropKey == criteria.key and (criteria.g == nil or growth == criteria.g) and
      (criteria.ga == nil or gain == criteria.ga) and (criteria.r == nil or resistance == criteria.r)
end

function Quantity.remaining(order) return math.max(0, order.K - order.produced) end

function Quantity.budget(order, archiveNeeded, sparePlants, waitingCopies)
  local remaining = Quantity.remaining(order)
  return remaining == 0 and 0 or math.max(0, remaining + (archiveNeeded and 1 or 0) - sparePlants - waitingCopies)
end

return Quantity
