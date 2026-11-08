local Species = require("station_species_math")
local Catalog = require("station_catalog")
local Genetics = {}
function Genetics.rangeMass(parentCount, average, low, high)
  if low > high then return 0 end
  local first = low == 0 and -parentCount or math.max(-parentCount, low - average)
  local last = high == 31 and parentCount or math.min(parentCount, high - average)
  return math.max(0, last - first + 1) / (2 * parentCount + 1)
end

function Genetics.mass(parentCount, average, target)
  return Genetics.rangeMass(parentCount, average, target, target)
end

local function gap(parentCount, average, low, high)
  if low > high then return math.huge end
  return math.max(0, low - math.min(31, average + parentCount), math.max(0, average - parentCount) - high)
end
function Genetics.calculate(parents, criteria, candidateKeys, weightScratch)
  for index = 1, #parents do
    local parent = parents[index]
    if type(parent.ga) ~= "number" or parent.ga % 1 ~= 0 or parent.ga < 0 or parent.ga > 31 then
      return nil,
          "GENES_UNREADABLE"
    end
  end
  local speciesProbability, crossProbability, firstAcceptance, secondAcceptance, thirdAcceptance, fourthAcceptance =
      Species.evaluate(parents, criteria.key, candidateKeys, weightScratch)
  if speciesProbability == nil then return nil, crossProbability end
  if #parents < 2 or speciesProbability == 0 then return 0, math.huge, 0 end
  local growthCap = criteria.key == "ic2:venomilia" and 7 or 23
  local growthLow, growthHigh = criteria.g or 0, math.min(criteria.g or growthCap, growthCap)
  local gainLow, gainHigh = criteria.ga or 0, criteria.ga or 31
  local resistanceLow, resistanceHigh = criteria.r or 0, criteria.r or 31
  local excludeVanilla = Catalog.get(criteria.key).vanillaSeeds and
      (criteria.g ~= nil or criteria.ga ~= nil or criteria.r ~= nil)
  if growthLow > growthHigh or (excludeVanilla and growthHigh < 2 and gainHigh < 2 and resistanceHigh < 2) then
    return 0,
        math.huge, 0
  end
  local probability, distance, safeProbability = 0, math.huge, 0
  local speciesRatio = speciesProbability / crossProbability
  for mask = 1, (1 << #parents) - 1 do
    local count, subsetProbability, sumGrowth, sumGain, sumResistance = 0, 1, 0, 0, 0
    for index = 1, #parents do
      local accepted = (mask & (1 << (index - 1))) ~= 0
      local acceptance = index == 1 and firstAcceptance or index == 2 and secondAcceptance or
          index == 3 and thirdAcceptance or fourthAcceptance
      subsetProbability = subsetProbability * (accepted and acceptance or 1 - acceptance)
      if accepted then
        local parent = parents[index]
        count = count + 1; sumGrowth = sumGrowth + parent.g; sumGain = sumGain + parent.ga; sumResistance = sumResistance +
            parent.r
      end
    end
    if count >= 2 then
      local averageGrowth, averageGain, averageResistance = math.floor(sumGrowth / count), math.floor(sumGain / count),
          math.floor(sumResistance / count)
      local genotypeProbability = Genetics.rangeMass(count, averageGrowth, growthLow, growthHigh) *
          Genetics.rangeMass(count, averageGain, gainLow, gainHigh) *
          Genetics.rangeMass(count, averageResistance, resistanceLow, resistanceHigh)
      local subsetDistance = gap(count, averageGrowth, growthLow, growthHigh) +
          gap(count, averageGain, gainLow, gainHigh) +
          gap(count, averageResistance, resistanceLow, resistanceHigh)
      if excludeVanilla then
        genotypeProbability = genotypeProbability -
            Genetics.rangeMass(count, averageGrowth, growthLow, math.min(1, growthHigh)) *
            Genetics.rangeMass(count, averageGain, gainLow, math.min(1, gainHigh)) *
            Genetics.rangeMass(count, averageResistance, resistanceLow, math.min(1, resistanceHigh))
        subsetDistance = math.min(
          gap(count, averageGrowth, math.max(2, growthLow), growthHigh) + gap(count, averageGain, gainLow, gainHigh) +
          gap(count, averageResistance, resistanceLow, resistanceHigh),
          gap(count, averageGrowth, growthLow, growthHigh) + gap(count, averageGain, math.max(2, gainLow), gainHigh) +
          gap(count, averageResistance, resistanceLow, resistanceHigh),
          gap(count, averageGrowth, growthLow, growthHigh) + gap(count, averageGain, gainLow, gainHigh) +
          gap(count, averageResistance, math.max(2, resistanceLow), resistanceHigh))
      end
      local factor = subsetProbability * speciesRatio / 3
      probability = probability + factor * genotypeProbability
      safeProbability = safeProbability + factor * Genetics.rangeMass(count, averageGrowth, 0, growthCap)
      distance = math.min(distance, subsetDistance)
    end
  end
  return probability, distance, safeProbability
end

return Genetics
