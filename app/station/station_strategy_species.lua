local Facts = require("station_planner_facts")
local Species = require("station_species_math")
local Strategy = {}
function Strategy.isCrossCell(cell)
  return (math.floor((cell - 1) / 6) + (cell - 1) % 6) % 2 == 0
end

function Strategy.isParentCell(cell) return not Strategy.isCrossCell(cell) end

local function same(facts, key) return Facts.plant(facts) and Facts.key(facts) == key end
local function replaceable(facts, key)
  return Facts.known(facts) and (Facts.empty(facts) or facts.tile) and not same(facts, key)
end
local function routeReadiness(planning, key)
  local field, projection = planning.view.field, planning.projection
  local working, preparation = 0, math.huge
  for cell = 1, 36 do
    local site = field[cell]
    if Strategy.isCrossCell(cell) and Facts.known(site) and (Facts.empty(site) or site.tile) then
      local ready, count, foreign, unknown = projection.group(cell, key, false)
      if count >= 2 and not unknown then
        if site.kind == "DOUBLE" and foreign == 0 then
          preparation = 0
          if ready >= 2 then working = working + 1 end
        elseif site.kind ~= "DOUBLE" then
          preparation = math.min(preparation, 1 + foreign)
        end
      end
    end
  end
  if preparation == math.huge then
    for _, cell in ipairs(planning.liveSources) do
      if same(field[cell], key) then
        preparation = 3; break
      end
    end
    if preparation == math.huge then
      preparation = planning.view.material and Facts.key(planning.view.material) == key and 4 or 5
    end
  end
  return working, preparation
end
function Strategy.summarize(planning)
  local view, memo = planning.view, planning.routeMemo
  local keys = Facts.candidates()
  local sourcesKey, candidatesKey = table.concat(planning.sourceKeys, "|"), table.concat(keys, "|")
  local route, tied, reason
  if memo and memo.sources == sourcesKey and memo.target == view.order.key and memo.candidates == candidatesKey then
    route, tied = memo.route, memo.tiedSources
  else
    route, reason, tied = Species.plan(planning.sourceKeys, view.order.key, keys, planning.yieldComputation, true)
  end
  if not route then return { blocked = reason or "UNREACHABLE", cancelled = reason == "PLANNING_CHANGED" } end
  local desired, bestWorking, bestPreparation
  for _, key in ipairs(tied) do
    local working, preparation = routeReadiness(planning, key)
    if not desired or working > bestWorking or working == bestWorking and
        (preparation < bestPreparation or preparation == bestPreparation and key < desired) then
      desired, bestWorking, bestPreparation = key, working, preparation
    end
    if not planning.check() then return { cancelled = true } end
  end
  if desired ~= route.path[1] then
    route, reason = Species.plan({ desired }, view.order.key, keys, planning.yieldComputation)
    if not route then return { blocked = reason, cancelled = reason == "PLANNING_CHANGED" } end
  end
  local summary = { key = desired, nextKey = route.path[2], parents = 0, working = 0, assured = {}, active = {}, canCopy = {}, pending = false, mixedMask = 0, copyDonors = 0, needsParentMask = 0 }
  summary.memo = {
    sources = sourcesKey,
    target = view.order.key,
    candidates = candidatesKey,
    route = route,
    tiedSources =
        tied
  }
  summary.stopWhen = { key = summary.nextKey }
  summary.specimens = 0
  for _, cell in ipairs(planning.liveSources) do
    if same(view.field[cell], desired) then summary.specimens = summary.specimens + 1 end
  end
  for sourceIndex = 1, #planning.bankSources, 2 do
    local slot, item = planning.bankSources[sourceIndex], planning.bankSources[sourceIndex + 1]
    if Facts.key(item) == desired then summary.specimens = summary.specimens + (item.size or 1) end
    if Facts.key(item) == desired and not summary.bankSlot then summary.bankSlot = slot end
  end
  summary.held = planning.view.material and Facts.key(planning.view.material) == desired and
      Facts.plantingGenes(planning.view.material) ~= nil
  if summary.held then summary.specimens = summary.specimens + 1 end
  for cell = 1, 36 do
    if same(view.field[cell], desired) then
      summary.canCopy[cell] = Strategy.isParentCell(cell) and
          planning.projection.copySite(cell, nil, Strategy.isCrossCell, function(facts)
            return facts.kind == "SINGLE" or facts.kind == "DOUBLE" or
                Facts.crop(facts) and not same(facts, desired) and not same(facts, summary.nextKey)
          end) ~= nil
    end
    if Strategy.isParentCell(cell) and same(view.field[cell], desired) then summary.parents = summary.parents + 1 end
    if Strategy.isCrossCell(cell) then
      local ready, count, foreign, unknown = planning.projection.group(cell, desired, false)
      if count == 1 then summary.needsParentMask = summary.needsParentMask | (1 << (cell - 1)) end
      local site = view.field[cell]
      if Facts.known(site) and (Facts.empty(site) or site.tile) and count >= 2 and foreign == 0 and not unknown then
        summary.assured[cell] = count
      end
      if view.field[cell] and view.field[cell].kind == "DOUBLE" and ready >= 2 and foreign == 0 and not unknown then
        summary.active[cell] = ready; summary.working = summary.working + 1
      end
      if view.field[cell] and view.field[cell].kind == "DOUBLE" and ready >= 2 and foreign > 0 and not unknown then
        summary.mixedMask = summary.mixedMask | (1 << (cell - 1))
        for direction = 1, 4 do
          local neighbor = Facts.adjacent(cell, direction)
          if neighbor then summary.mixedMask = summary.mixedMask | (1 << (neighbor - 1)) end
        end
      end
    end
  end
  return summary
end

local function receiver(planning, summary, vacated)
  local projection = planning.projection
  local missing = false
  local strengthening, existingParents
  for target = 1, 36 do
    local site = projection.at(target)
    if Strategy.isParentCell(target) and not Facts.known(site) then missing = true end
    if Strategy.isParentCell(target) and replaceable(site, summary.key) then
      for direction = 1, 4 do
        local center = Facts.adjacent(target, direction)
        local centerFacts = center and projection.at(center)
        if center and Strategy.isCrossCell(center) and not Facts.known(centerFacts) then missing = true end
        if center and Strategy.isCrossCell(center) and Facts.known(centerFacts) and
            (Facts.empty(centerFacts) or centerFacts.tile) then
          local count, foreign, unknown = 0, 0, false
          for neighborDirection = 1, 4 do
            local neighbor = Facts.adjacent(center, neighborDirection)
            if neighbor and neighbor ~= vacated and neighbor ~= target then
              local facts = projection.at(neighbor)
              if not Facts.known(facts) then
                unknown = true
              elseif facts.kind == "PLANT" then
                if same(facts, summary.key) then count = count + 1 else foreign = foreign + 1 end
              end
            end
          end
          if foreign == 0 and not unknown then
            if count == 1 then return target, false, count end
            if count >= 2 and count < 4 and summary.assured[center] and not strengthening then
              strengthening, existingParents = target, count
            end
          end
          if unknown and foreign == 0 and count <= 1 then missing = true end
        end
      end
    end
  end
  if strengthening then return strengthening, false, existingParents end
  return nil, missing
end
local function firstPairRoom(planning, summary, destination)
  local field = planning.view.field
  if summary.parents ~= 0 or not Strategy.isParentCell(destination) then return false end
  local missing = false
  for direction = 1, 4 do
    local center = Facts.adjacent(destination, direction)
    if center and Strategy.isCrossCell(center) and Facts.known(field[center]) and
        (Facts.empty(field[center]) or field[center].tile) then
      local readable, target = true, nil
      for neighborDirection = 1, 4 do
        local cell = Facts.adjacent(center, neighborDirection)
        if cell then
          if not Facts.known(field[cell]) then
            readable = false; missing = true
          end
          if same(field[cell], summary.nextKey) then readable = false end
          if cell ~= destination and Strategy.isParentCell(cell) and replaceable(field[cell], summary.key) then
            target =
                cell
          end
        end
      end
      if readable and target then return true end
    elseif center and Strategy.isCrossCell(center) and not Facts.known(field[center]) then
      missing = true
    end
  end
  return false, missing
end
local function copyPurpose(planning, summary, source, destination)
  local target, missing, existingParents = receiver(planning, summary, destination)
  if target then return true, existingParents end
  if summary.parents == 0 and not Strategy.isParentCell(source) and Strategy.isParentCell(destination) then
    local room, unknown = firstPairRoom(planning, summary, destination)
    if room then return true end
    missing = missing or unknown
  end
  if missing then return nil end
  return false
end
local function crossWaiting(planning, summary, cell)
  if not Strategy.isCrossCell(cell) then return false end
  local _, count, foreign, unknown = planning.projection.group(cell, summary.key, true)
  if unknown then return nil end
  if count >= 2 and foreign == 0 then return "PARENT_MATURING" end
  if planning.view.field[cell].kind == "DOUBLE" and count > 0 then
    local ready = 0
    for direction = 1, 4 do
      local neighbor = Facts.adjacent(cell, direction)
      if neighbor and Facts.mature(planning.view.field[neighbor]) then ready = ready + 1 end
    end
    if ready >= 2 then return "WAIT_CROSSING" end
  end
  return false
end
function Strategy.usesSite(planning, summary, cell)
  if not summary.key then return nil end
  if (summary.mixedMask & (1 << (cell - 1))) ~= 0 then return true end
  local crossing = crossWaiting(planning, summary, cell)
  if crossing ~= false then return crossing and true or nil end
  local parent = planning.projection.copyParent(cell, function(facts) return same(facts, summary.key) end)
  if parent and (Strategy.isCrossCell(cell) or summary.parents == 0 and not Strategy.isParentCell(parent)) then
    return copyPurpose(planning, summary, parent, cell)
  end
  return false
end

function Strategy.enumerate(planning, summary)
  if not summary.key then return end
  local field = planning.view.field
  if summary.parents == 0 then
    for _, source in ipairs(planning.liveSources) do
      if same(field[source], summary.key) and not Strategy.isParentCell(source) then
        for direction = 1, 4 do
          local target = Facts.adjacent(source, direction)
          if target and firstPairRoom(planning, summary, target) and Facts.copyObstacles(field, source, target) then
            summary.canCopy[source] = true
          end
        end
      end
    end
  end
  for cell = 1, 36 do
    local parent = planning.projection.copyParent(cell, function(facts) return same(facts, summary.key) end)
    if parent and field[cell].kind == "DOUBLE" and copyPurpose(planning, summary, parent, cell) then
      summary.pending = true; summary.copyDonors = summary.copyDonors | (1 << (parent - 1))
    end
    if Strategy.isCrossCell(cell) then
      if same(field[cell], summary.key) and receiver(planning, summary, cell) then
        summary.pending = true
        if not field[cell].size or field[cell].size < 2 then summary.growing = true end
      end
      planning.offer("ENABLE_CROSS", 0, cell, nil, 2, "ACTIVATE_CROSS")
    end
  end
  for target = 1, 36 do
    if Strategy.isParentCell(target) and not same(field[target], summary.key) then
      planning.install(target, function(facts, source, slot)
        return Facts.key(facts) == summary.key and
            (source > 0 or not slot or not summary.held and slot == summary.bankSlot)
      end, 3, "INSTALL_PARENT")
    end
  end
  if not summary.pending then
    for _, source in ipairs(planning.liveSources) do
      if same(field[source], summary.key) then
        for direction = 1, 4 do
          local target = Facts.adjacent(source, direction)
          if target and (Strategy.isCrossCell(target) or summary.parents == 0 and not Strategy.isParentCell(source)) then
            planning.offer("ENABLE_COPY", source, target, nil, 4, "EXPAND_LINE")
          end
        end
      end
    end
  end
end

function Strategy.evaluate(candidate, planning, summary)
  local field, projection = planning.view.field, planning.projection
  if candidate.reason == "ARCHIVE_SAMPLE" and same(field[candidate.destination], summary.key) then return false end
  if (candidate.changed & summary.mixedMask) ~= 0 then return false end
  for cell = 1, 36 do
    if (candidate.removed & (1 << (cell - 1))) ~= 0 then
      if same(field[cell], summary.nextKey) then return false end
      if same(field[cell], summary.key) then
        if Strategy.isParentCell(cell) or summary.pending and receiver(planning, summary, cell) or
            summary.parents == 0 and summary.specimens >= 2 then
          return false
        end
      end
    end
    if summary.assured[cell] then
      local ready, count, foreign, unknown = projection.group(cell, summary.key, false)
      local site = projection.at(cell)
      if not Facts.known(site) or not (Facts.empty(site) or site.tile) or
          count < summary.assured[cell] or foreign > 0 or unknown then
        return false
      end
      if summary.active[cell] and (site.kind ~= "DOUBLE" or ready < summary.active[cell]) then return false end
    end
  end
  if candidate.operation == "INSTALL" then
    if candidate.source > 0 and (summary.copyDonors & (1 << (candidate.source - 1))) ~= 0 then return false end
    if not same(candidate.installed, summary.key) then return false end
    local gained, strengthened, usesParent = 0, 0, false
    for center = 1, 36 do
      if Strategy.isCrossCell(center) then
        local _, count, foreign, unknown = projection.group(center, summary.key, true)
        local site = projection.at(center)
        local after = Facts.known(site) and (Facts.empty(site) or site.tile) and count >= 2 and foreign == 0 and
            not unknown
        gained = gained + (after and 1 or 0) - (summary.assured[center] and 1 or 0)
        if after and summary.assured[center] then
          strengthened = strengthened + count - summary.assured[center]
        end
        if after and not usesParent and (summary.needsParentMask & (1 << (center - 1))) ~= 0 then usesParent = true end
      end
    end
    candidate.gained = gained
    candidate.strengthened = strengthened
    if gained > 0 and usesParent then return true end
    if strengthened > 0 then
      candidate.rank = 5; return true
    end
    local bootstrap = summary.parents <= 1 and summary.working == 0 and
        (not summary.canCopy[candidate.source] or summary.parents == 0 and summary.specimens >= 2) and
        projection.copySite(candidate.destination, candidate.source, Strategy.isCrossCell,
          function(facts)
            return facts.kind == "SINGLE" or facts.kind == "DOUBLE" or
                Facts.crop(facts) and not same(facts, summary.key) and not same(facts, summary.nextKey)
          end) and
        receiver(planning, summary, candidate.source)
    if bootstrap and candidate.source > 0 and not (summary.parents == 0 and summary.specimens >= 2) then candidate.rank = 5 end
    return bootstrap
  elseif candidate.operation == "ENABLE_COPY" then
    if summary.pending then return false end
    local useful, existingParents = copyPurpose(planning, summary, candidate.source, candidate.destination)
    if useful and existingParents and existingParents >= 2 then candidate.rank = 6 end
    return useful
  elseif candidate.operation == "ENABLE_CROSS" then
    if field[candidate.destination].kind == "DOUBLE" then
      for direction = 1, 4 do
        local cell = Facts.adjacent(candidate.destination, direction)
        if cell and Facts.plant(field[cell]) and not same(field[cell], summary.key) then return false end
      end
    end
    if same(field[candidate.destination], summary.key) then
      if receiver(planning, summary, candidate.destination) then return false end
    end
    local ready = projection.group(candidate.destination, summary.key, false)
    candidate.ready = ready
    return true
  end
  return candidate.operation == "RELEASE_SITE"
end

function Strategy.compareCandidates(first, second)
  if first.rank ~= second.rank then return second.rank - first.rank end
  if first.gained ~= second.gained then return (first.gained or 0) - (second.gained or 0) end
  if first.strengthened ~= second.strengthened then return (first.strengthened or 0) - (second.strengthened or 0) end
  local firstReady, secondReady = (first.ready or 0) >= 2, (second.ready or 0) >= 2
  if firstReady ~= secondReady then return firstReady and 1 or -1 end
  return 0
end

function Strategy.waiting(planning, summary)
  if summary.blocked then return end
  if summary.pending then return summary.growing and "PARENT_MATURING" or "WAIT_SPREADING" end
  if summary.working > 0 then return "WAIT_CROSSING" end
  for cell = 1, 36 do
    if summary.assured[cell] then return "PARENT_MATURING" end
    if planning.view.field[cell] and planning.view.field[cell].kind == "DOUBLE" then
      local waiting = crossWaiting(planning, summary, cell)
      if waiting then return waiting end
    end
  end
end

return Strategy
