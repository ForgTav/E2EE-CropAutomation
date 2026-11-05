local Catalog = require("station_catalog")
local Quantity = require("station_production_rules")
local Facts = require("station_planner_facts")
local Projection = require("station_planner_projection")
local strategies = {
  SPECIES = require("station_strategy_species"),
  GENETICS = require("station_strategy_genetics"),
  QUANTITY = require("station_strategy_quantity"),
}
local Planner = {}
local function bit(cell) return 1 << (cell - 1) end
local function localityDistance(localityRow, localityColumn, from, to)
  local cell = from and from > 0 and from or to
  return math.abs(localityColumn - (cell - 1) % 6) + math.abs(localityRow - (cell - 1) // 6)
end
local function copy(values, result)
  result = result or {}
  for name in pairs(result) do result[name] = nil end
  for name, value in pairs(values) do result[name] = value end; return result
end
local function matches(facts, criteria, material)
  return material and Quantity.matchesDescriptor(facts, criteria) or
      not material and Facts.plant(facts) and Quantity.sourceMatches(facts, criteria, Facts.key(facts))
end
local function stickSites(field, excluded, visit, check)
  for cell = 1, 36 do
    if check and not check() then return false end
    if Facts.sticks(field[cell]) and (excluded & bit(cell)) == 0 then
      local known = true
      for direction = 1, 4 do
        local neighbor = Facts.adjacent(cell, direction)
        local facts = neighbor and field[neighbor]
        if neighbor and (not Facts.known(facts) or facts.kind == "PLANT" and not Facts.crop(facts)) then known = false end
      end
      if known and visit(cell) == false then break end
    end
  end
  return true
end
function Planner.next(view, step, routeMemo, yieldComputation)
  local field, order, bank = view.field, view.order, view.bank or {}
  local localityCell = view.localityCell
  local localityRow, localityColumn
  if localityCell then localityRow, localityColumn = (localityCell - 1) // 6, (localityCell - 1) % 6 end
  local discardStep = false
  local strategySummary
  local function finish(result)
    result.discardStep = discardStep or nil
    if strategySummary and result.reason ~= "PLANNING_CHANGED" then
      if result.need == "SPECIES" and result.kind ~= "BLOCKED" then
        result.routeFrom, result.routeTo = strategySummary.key, strategySummary.nextKey
      elseif result.need == "GENETICS" then
        result.genetics = strategySummary.genetics
      end
    end
    return result
  end
  for cell = 1, 36 do
    local facts = field[cell]
    if facts and facts.kind == "PLANT" and (facts.danger or Facts.key(facts) and
          type(facts.g) == "number" and Catalog.isDangerous(Facts.key(facts), facts.g)) then
      local result = Facts.action(Facts.key(facts) == "ic2:weed" and "REMOVE_WEED" or "COLLECT_AND_CLEAR_CELL", 0, cell,
        "THREAT", step)
      result.need = "SAFETY"
      return finish(result)
    end
  end
  local archiveGrowing, archiveUnreadable = 0, 0
  if view.archiveDisposition then
    local sample = {}
    for cell = 1, 36 do
      local facts = field[cell]
      if Facts.crop(facts) then
        sample.key, sample.g, sample.ga, sample.r = Facts.key(facts), facts.g, facts.ga, facts.r
        sample.itemKind = nil
        sample.itemKind = Quantity.outputKind(sample)
        if sample.itemKind then
          local disposition = view.archiveDisposition(sample)
          if disposition == "KEEP" or disposition == "REPLACE" or disposition == "FULL" then
            if type(facts.size) ~= "number" then
              archiveUnreadable = archiveUnreadable | bit(cell)
            elseif facts.size < 2 then
              archiveGrowing = archiveGrowing | bit(cell)
            end
          end
        end
      end
    end
  end
  local function archiveWaiting(removed)
    if (removed & archiveUnreadable) ~= 0 then return "LOCAL_FACTS_UNREADABLE" end
    if (removed & archiveGrowing) ~= 0 then return "PARENT_MATURING" end
  end
  local function releaseUnusedSticks(need)
    local selected, selectedDistance
    stickSites(field, 0, function(cell)
      local distance = localityCell and localityDistance(localityRow, localityColumn, 0, cell) or 0
      if not selected or distance < selectedDistance then selected, selectedDistance = cell, distance end
      if distance == 0 then return false end
    end)
    if selected then
      local result = Facts.action("COLLECT_AND_CLEAR_CELL", 0, selected, "UNUSED_STICKS")
      result.need = need; return result
    end
  end
  if not order or Quantity.remaining(order) == 0 then
    discardStep = step ~= nil
    local cleanup = releaseUnusedSticks("EMPTY")
    if cleanup then return finish(cleanup) end
    return finish(Facts.decision("IDLE", "NO_ACTIVE_ORDER", "EMPTY"))
  end
  if not Catalog.canProceed(order.key) then return finish(Facts.decision("BLOCKED", "INVALID_SPECIES", "EMPTY")) end
  local planning = {
    view = view,
    routeMemo = routeMemo,
    projection = Projection.new(view),
    liveSources = {},
    bankSources = {},
    sourceKeys = {},
    exactLive = {},
    yieldComputation = yieldComputation
  }
  local seen = {}
  local function addSource(facts)
    local cropKey = Facts.key(facts)
    if cropKey and Catalog.canProceed(cropKey) and Facts.plantingGenes(facts) ~= nil then
      if not seen[cropKey] then
        seen[cropKey] = true; planning.sourceKeys[#planning.sourceKeys + 1] = cropKey
      end
      if cropKey == order.key then planning.targetPresent = true end
      return true
    end
  end
  for cell = 1, 36 do
    if Facts.plant(field[cell]) and addSource(field[cell]) then
      planning.liveSources[#planning.liveSources + 1] = cell
      if matches(field[cell], order, false) then planning.exactLive[#planning.exactLive + 1] = cell end
    end
  end
  for slot = 1, 54 do
    local item = bank[slot]
    if type(item) == "table" and item.itemKind and addSource(item) then
      local sourceIndex = #planning.bankSources + 1
      planning.bankSources[sourceIndex], planning.bankSources[sourceIndex + 1] = slot, item
      if matches(item, order, true) and not planning.exactBank then planning.exactBank = true end
    end
  end
  if view.material and view.material.itemKind and addSource(view.material) then
    planning.exactMaterial = matches(view.material, order, true)
  end
  table.sort(planning.sourceKeys)
  local need = (#planning.exactLive > 0 or planning.exactMaterial or planning.exactBank) and "QUANTITY" or
      planning.targetPresent and "GENETICS" or "SPECIES"
  planning.need = need
  local work, cancelled = 0, false
  function planning.check()
    if cancelled then return false end
    work = work + 1
    if work % 12 == 0 and yieldComputation and yieldComputation() == false then cancelled = true end
    return not cancelled
  end

  local waitReason
  function planning.wait(reason)
    if reason == "LOCAL_FACTS_UNREADABLE" or not waitReason then waitReason = reason end
  end

  local function reached(criteria)
    if not criteria then return false end
    for _, cell in ipairs(planning.liveSources) do if matches(field[cell], criteria, false) then return true end end
    if view.material and matches(view.material, criteria, true) then return true end
    for sourceIndex = 1, #planning.bankSources, 2 do
      if matches(planning.bankSources[sourceIndex + 1], criteria, true) then return true end
    end
    return false
  end
  local retainedStep
  if step then
    local selected = step.action
    local changed = step.orderId ~= order.id or step.orderKey ~= order.key or
        step.g ~= order.g or step.ga ~= order.ga or step.r ~= order.r or step.K ~= order.K
    if changed or reached(step.stopWhen) or not selected or step.kind ~= "INSTALL" or
        selected.name ~= "PLANT_SEED" or selected.from ~= 0 then
      discardStep = true
    else
      local source = view.material
      local target = field[selected.to]
      local sourceInvalid = not Facts.sameMaterial(step.expected, source)
      local targetInvalid = Facts.known(target) and not Facts.empty(target)
      if sourceInvalid or targetInvalid then
        discardStep = true
      elseif not Facts.known(target) then
        retainedStep = step; planning.wait("LOCAL_FACTS_UNREADABLE")
      else
        retainedStep = step
        local result = Facts.action(selected.name, selected.from, selected.to, "COMPLETE_INSTALLATION")
        result.need = need
        return finish(result)
      end
    end
  end
  if #planning.sourceKeys == 0 and not retainedStep then
    local cleanup = releaseUnusedSticks(need)
    if cleanup then return finish(cleanup) end
    return finish(Facts.decision("BLOCKED", "NO_SOURCE_MATERIAL", need))
  end
  local strategy = strategies[need]
  local summary = strategy.summarize(planning)
  strategySummary = summary
  if cancelled or summary.cancelled then return finish(Facts.decision("WAIT", "PLANNING_CHANGED", need)) end
  local candidate, best = {}, nil
  local bestDistance
  local retainedSites = 0
  local function decisionFor(selected)
    if selected.firstName == "MATERIAL" then
      return {
        kind = "MATERIAL",
        slot = selected.slot,
        expected = Facts.descriptor(selected.material),
        reason = selected
            .reason
      }
    end
    local nextStep
    if selected.operation == "INSTALL" and selected.firstName == "COLLECT_AND_CLEAR_CELL" then
      nextStep = {
        kind = "INSTALL",
        orderId = order.id,
        orderKey = order.key,
        g = order.g,
        ga = order.ga,
        r = order.r,
        K = order.K,
        destination = selected.destination,
        action = { name = "PLANT_SEED", from = 0, to = selected.destination },
        expected = Facts.descriptor(selected.material),
        stopWhen = summary.stopWhen
      }
    end
    return Facts.action(selected.firstName, selected.firstFrom, selected.firstTo, selected.reason, nextStep,
      selected.purpose)
  end
  function planning.offer(operation, source, destination, material, rank, reason, slot, resultKind)
    if not planning.check() then return end
    if operation == "RELEASE_SITE" and Facts.sticks(field[destination]) and
        strategy.usesSite(planning, summary, destination) ~= false then
      return
    end
    for name in pairs(candidate) do candidate[name] = nil end
    candidate.operation, candidate.source, candidate.destination = operation, source or 0, destination
    candidate.material, candidate.slot, candidate.rank, candidate.reason = material, slot, rank, reason
    candidate.resultKind = resultKind
    candidate.key = summary.key
    local valid, obstacle = planning.projection.prepare(candidate)
    local useful = valid and strategy.evaluate(candidate, planning, summary)
    if valid then
      if useful then
        candidate.waiting = archiveWaiting(candidate.removed) or candidate.waiting
        retainedSites = retainedSites | candidate.footprint
        if candidate.waiting then
          planning.wait(candidate.waiting)
        else
          local independent = true
          if retainedStep then
            local occupied = bit(retainedStep.action.to)
            independent = (candidate.footprint & occupied) == 0 and
                not (candidate.operation == "INSTALL" and candidate.firstName == "COLLECT_AND_CLEAR_CELL")
            if candidate.spent > 0 or candidate.firstName == "MATERIAL" or
                candidate.operation == "EXTRACT" then
              independent = false
            end
          end
          if independent then
            local comparison = best and strategy.compareCandidates(candidate, best, planning, summary) or 1
            local candidateDistance
            if comparison == 0 then
              comparison = best.cost - candidate.cost
              if comparison == 0 and localityCell then
                candidateDistance = localityDistance(localityRow, localityColumn, candidate.firstFrom,
                  candidate.firstTo)
                if bestDistance == nil then
                  bestDistance = localityDistance(localityRow, localityColumn, best.firstFrom, best.firstTo)
                end
                comparison = bestDistance - candidateDistance
              end
            end
            if comparison > 0 or comparison == 0 and
                (candidate.destination < best.destination or candidate.destination == best.destination and
                  (candidate.source < best.source or candidate.source == best.source and (candidate.slot or 0) < (best.slot or 0))) then
              best = copy(candidate, best)
              bestDistance = candidateDistance
            end
          end
        end
      end
    elseif obstacle then
      planning.wait(obstacle)
    end
    planning.projection.reset()
    return useful
  end

  function planning.install(destination, predicate, rank, reason)
    for _, cell in ipairs(planning.liveSources) do
      if predicate(field[cell], cell) then planning.offer("INSTALL", cell, destination, nil, rank, reason) end
    end
    if view.material and predicate(view.material, 0) then
      planning.offer("INSTALL", 0, destination, view.material, rank, reason)
    end
    for sourceIndex = 1, #planning.bankSources, 2 do
      local slot, item = planning.bankSources[sourceIndex], planning.bankSources[sourceIndex + 1]
      if predicate(item, 0, slot) and not Facts.sameMaterial(item, view.material) then
        planning.offer("INSTALL", 0, destination, item, rank, reason, slot)
      end
    end
  end

  strategy.enumerate(planning, summary)
  planning.projection.reset()
  if not best and not cancelled then
    local excluded = retainedSites
    if retainedStep then excluded = excluded | bit(retainedStep.action.to) end
    stickSites(field, excluded, function(cell)
      planning.offer("RELEASE_SITE", 0, cell, nil, 0, "UNUSED_STICKS")
    end, planning.check)
  end
  if cancelled then return finish(Facts.decision("WAIT", "PLANNING_CHANGED", need)) end
  if routeMemo and summary.memo then
    for name in pairs(routeMemo) do routeMemo[name] = nil end
    for name, value in pairs(summary.memo) do routeMemo[name] = value end
  end
  if best then
    local result = decisionFor(best)
    result.need = need
    if need == "SPECIES" then result.routeFrom, result.routeTo = summary.key, summary.nextKey end
    if retainedStep and result.kind == "ACTION" then result.step = retainedStep end
    return finish(result)
  end
  local waiting = strategy.waiting(planning, summary)
  if waitReason or waiting then
    return finish(Facts.decision("WAIT", waitReason or waiting, need))
  end
  return finish(Facts.decision("BLOCKED", summary.blocked or "NO_FEASIBLE_SITE", need))
end

return Planner
