local Catalog = require("station_catalog")
local Planner = {}

local function ratio(candidate, parent)
  if candidate == parent then return 500 end
  local weight = 10
      - math.abs(candidate.chemistry - parent.chemistry)
      - math.abs(candidate.consumable - parent.consumable)
      - math.abs(candidate.defensive - parent.defensive)
      - math.abs(candidate.colorful - parent.colorful)
      - math.abs(candidate.weed - parent.weed)
  for _, candidateAttribute in ipairs(candidate.attributes) do
    for _, parentAttribute in ipairs(parent.attributes) do
      if candidateAttribute:lower() == parentAttribute:lower() then weight = weight + 5 end
    end
  end
  local tierDifference = candidate.tier - parent.tier
  if tierDifference > 1 then weight = weight - 2 * tierDifference end
  if tierDifference < -3 then weight = weight + tierDifference end
  return math.max(0, weight)
end

function Planner.calculateRatioFor(candidateKey, parentKey)
  local candidate, parent = Catalog.get(candidateKey), Catalog.get(parentKey)
  if not candidate then return nil, "INVALID_CANDIDATE" end
  if not parent then return nil, "INVALID_PARENT" end
  return ratio(candidate, parent)
end

function Planner.acceptance(parent)
  if type(parent.g) ~= "number" or type(parent.r) ~= "number" or
      parent.g % 1 ~= 0 or parent.r % 1 ~= 0 or parent.g < 0 or parent.g > 31 or parent.r < 0 or parent.r > 31 then
    return nil, "GENES_UNREADABLE"
  end
  return (5 + (parent.g >= 16 and 1 or 0) + (parent.g >= 30 and 1 or 0) - math.max(0, parent.r - 27)) / 16
end

function Planner.crossProbability(parents)
  if #parents > 4 then return nil, "INVALID_PARENTS" end
  local none, one = 1, 0
  local firstAcceptance, secondAcceptance, thirdAcceptance, fourthAcceptance
  for index = 1, #parents do
    local acceptance, reason = Planner.acceptance(parents[index])
    if not acceptance then return nil, reason end
    if index == 1 then
      firstAcceptance = acceptance
    elseif index == 2 then
      secondAcceptance = acceptance
    elseif index == 3 then
      thirdAcceptance = acceptance
    else
      fourthAcceptance = acceptance
    end
    local previousNone = none
    none = previousNone * (1 - acceptance)
    one = one * (1 - acceptance) + previousNone * acceptance
  end
  return (1 - none - one) / 3, firstAcceptance, secondAcceptance, thirdAcceptance, fourthAcceptance
end

function Planner.evaluate(parents, targetKey, candidateKeys, weightScratch)
  if not Catalog.get(targetKey) then return nil, "UNKNOWN_CROP" end
  local crossProbability, firstAcceptance, secondAcceptance, thirdAcceptance, fourthAcceptance = Planner
      .crossProbability(parents)
  if not crossProbability then return nil, firstAcceptance end
  local parentKey = parents[1] and parents[1].key
  for index = 1, #parents do
    if not Catalog.get(parents[index].key) then return nil, "UNKNOWN_CROP" end
    if parents[index].key ~= parentKey then return nil, "MIXED_SPECIES" end
  end
  local denominator, targetWeight
  if weightScratch and weightScratch.weightParent == parentKey and weightScratch.weightTarget == targetKey and
      weightScratch.weightCandidates == candidateKeys then
    denominator, targetWeight = weightScratch.weightTotal, weightScratch.weightResult
  else
    if type(candidateKeys) ~= "table" then return nil, "INVALID_CANDIDATES" end
    local candidateCount = 0
    for index in pairs(candidateKeys) do
      if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 52 then return nil, "INVALID_CANDIDATES" end
      candidateCount = candidateCount + 1
    end
    local targetPresent, orderedCandidates = false, true
    denominator = 0
    for index = 1, candidateCount do
      local candidateKey = candidateKeys[index]
      if not Catalog.get(candidateKey) then return nil, "INVALID_CANDIDATES" end
      if index > 1 and candidateKey <= candidateKeys[index - 1] then orderedCandidates = false end
      if not orderedCandidates then
        for previous = 1, index - 1 do if candidateKeys[previous] == candidateKey then return nil, "INVALID_CANDIDATES" end end
      end
      targetPresent = targetPresent or candidateKey == targetKey
      if parentKey then denominator = denominator + ratio(Catalog.get(candidateKey), Catalog.get(parentKey)) end
    end
    targetWeight = targetPresent and parentKey and ratio(Catalog.get(targetKey), Catalog.get(parentKey)) or 0
    if weightScratch then
      weightScratch.weightParent, weightScratch.weightTarget, weightScratch.weightCandidates = parentKey, targetKey,
          candidateKeys
      weightScratch.weightTotal, weightScratch.weightResult = denominator, targetWeight
    end
  end
  local probability = 0
  if #parents >= 2 and denominator > 0 then probability = crossProbability * targetWeight / denominator end
  return probability, crossProbability, firstAcceptance, secondAcceptance, thirdAcceptance, fourthAcceptance
end

local function sortedKeys(inputKeys, requireAllowed, requireNonempty)
  if type(inputKeys) ~= "table" then return nil end
  local sorted, seen = {}, {}
  local count = 0
  for index, cropKey in pairs(inputKeys) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0
        or type(cropKey) ~= "string" or not Catalog.get(cropKey)
        or (requireAllowed and not Catalog.canProceed(cropKey)) or seen[cropKey] then
      return nil
    end
    count = count + 1
    seen[cropKey] = true
  end
  if requireNonempty and count == 0 then return nil end
  for index = 1, count do
    if inputKeys[index] == nil then return nil end
    sorted[index] = inputKeys[index]
  end
  table.sort(sorted)
  return sorted, seen
end

function Planner.plan(sourceKeys, targetKey, candidateKeys, yieldComputation, includeSourceTies)
  local sources = sortedKeys(sourceKeys, true, true)
  if not sources then return nil, "INVALID_SOURCES" end
  if type(targetKey) ~= "string" or not Catalog.canProceed(targetKey) then return nil, "INVALID_TARGET" end
  local candidates, candidateSet = sortedKeys(candidateKeys, false, false)
  if not candidates then return nil, "INVALID_CANDIDATES" end
  local distances, predecessors, visited = {}, {}, {}
  local sourceMasks = includeSourceTies and #sources > 1 and {}
  for index, sourceKey in ipairs(sources) do
    distances[sourceKey] = 0
    if sourceMasks then sourceMasks[sourceKey] = 1 << (index - 1) end
  end
  if distances[targetKey] == 0 then
    return { path = { targetKey }, cost = 0 }, nil, includeSourceTies and { targetKey } or nil
  end
  if not candidateSet[targetKey] then return nil, "UNREACHABLE" end

  local vertices = {}
  for cropKey in Catalog.each() do
    if Catalog.canProceed(cropKey) then vertices[#vertices + 1] = cropKey end
  end
  table.sort(vertices)
  local candidateWeights = {}
  while true do
    local parentKey, nearestDistance
    for _, cropKey in ipairs(vertices) do
      local distance = distances[cropKey]
      if not visited[cropKey] and distance ~= nil
          and (nearestDistance == nil or distance < nearestDistance) then
        parentKey, nearestDistance = cropKey, distance
      end
    end
    if not parentKey then return nil, "UNREACHABLE" end
    if parentKey == targetKey then
      local reversed, path = {}, {}
      local cropKey = targetKey
      while cropKey do
        reversed[#reversed + 1] = cropKey
        cropKey = predecessors[cropKey]
      end
      for index = #reversed, 1, -1 do path[#path + 1] = reversed[index] end
      local tiedSources
      if includeSourceTies then
        tiedSources = {}
        if sourceMasks then
          for index, sourceKey in ipairs(sources) do
            if (sourceMasks[targetKey] & (1 << (index - 1))) ~= 0 then tiedSources[#tiedSources + 1] = sourceKey end
          end
        else
          tiedSources[1] = sources[1]
        end
      end
      return { path = path, cost = nearestDistance }, nil, tiedSources
    end
    visited[parentKey] = true
    if yieldComputation and yieldComputation() == false then return nil, "PLANNING_CHANGED" end
    local parent = Catalog.get(parentKey)
    local totalWeight = 0
    for index, candidateKey in ipairs(candidates) do
      local weight = ratio(Catalog.get(candidateKey), parent)
      candidateWeights[index] = weight
      totalWeight = totalWeight + weight
    end
    if totalWeight > 0 then
      for index, candidateKey in ipairs(candidates) do
        if not visited[candidateKey] and Catalog.canProceed(candidateKey) then
          local weight = candidateWeights[index]
          if weight > 0 then
            local distance = nearestDistance + totalWeight / weight
            if distances[candidateKey] == nil or distance < distances[candidateKey] then
              distances[candidateKey], predecessors[candidateKey] = distance, parentKey
              if sourceMasks then sourceMasks[candidateKey] = sourceMasks[parentKey] end
            elseif sourceMasks and distance == distances[candidateKey] then
              sourceMasks[candidateKey] = sourceMasks[candidateKey]| sourceMasks[parentKey]
            end
          end
        end
      end
    end
  end
end

return Planner
