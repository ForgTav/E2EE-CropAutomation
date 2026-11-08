local Facts = require("station_planner_facts")
local Quantity = require("station_production_rules")
local Strategy = {}
local comparisonOrder = { "priority", "section", "capacity" }
local function bit(cell) return 1 << (cell - 1) end
local function parity(cell) return (math.floor((cell - 1) / 6) + (cell - 1) % 6) % 2 end
local layouts = {}
for transform = 0, 7 do
  local layout = { parents = {}, mask = 0 }
  for index, cell in ipairs({ 3, 12, 13, 22, 32, 36 }) do
    local row, column = math.floor((cell - 1) / 6), (cell - 1) % 6
    if transform >= 4 then column = 5 - column end
    for _ = 1, transform % 4 do row, column = column, 5 - row end
    local destination = row * 6 + column + 1
    layout.parents[index] = destination; layout.mask = layout.mask | bit(destination)
  end
  layout.parity = parity(layout.parents[1]); layouts[#layouts + 1] = layout
end
local function usable(facts, order)
  return Facts.plant(facts) and Quantity.sourceMatches(facts, order, Facts.key(facts))
end
local function capacityParent(planning, summary, cell, parentParity, retained)
  local field = summary.projectedField
  if retained and (retained & bit(cell)) ~= 0 then return end
  for direction = 1, 4 do
    local parent = Facts.adjacent(cell, direction)
    if parent and parity(parent) == parentParity and summary.usable(field[parent]) and
        (not retained or (retained & bit(parent)) ~= 0) then
      local obstacles = Facts.copyObstacles(field, parent, cell)
      if obstacles then
        local allowed = true
        for direction = 0, 4 do
          local obstacle = direction == 0 and cell or Facts.adjacent(cell, direction)
          if obstacle and (obstacles & bit(obstacle)) ~= 0 then
            local facts = field[obstacle]
            if obstacle ~= cell and summary.usable(facts) and
                (not retained or (retained & bit(obstacle)) ~= 0) or
                obstacle ~= cell and facts.kind == "DOUBLE" and planning.projection.copyParent(obstacle, summary.usable) or
                facts.kind == "PLANT" and not Facts.crop(facts) then
              allowed = false; break
            end
          end
        end
        if allowed then return parent end
      end
    end
  end
end
local function measure(planning, summary, parentParity, result)
  result.capacity, result.harvest, result.copies = 0, 0, 0
  result.parents, result.sites, result.working = 0, 0, 0
  for _, cell in ipairs(summary.layout.parents) do
    if summary.usable(planning.projection.at(cell)) then result.parents = result.parents | bit(cell) end
  end
  for cell = 1, 36 do
    local facts = planning.projection.at(cell)
    if facts and facts.kind == "DOUBLE" then
      local parent = planning.projection.copyParent(cell, summary.usable)
      if parent then
        result.parents = result.parents | bit(parent)
        result.working = result.working | bit(cell)
        result.copies = result.copies + 1
      end
    end
  end
  for cell = 1, 36 do
    if parity(cell) ~= parentParity then
      if not planning.check() then return false end
      local parent = capacityParent(planning, summary, cell, parentParity)
      if parent then
        result.parents = result.parents | bit(parent)
        result.sites = result.sites | bit(cell)
      end
    end
  end
  for cell = 1, 36 do
    if parity(cell) ~= parentParity then
      if (result.parents & bit(cell)) ~= 0 then
        result.sites = result.sites & ~bit(cell)
      elseif (result.sites & bit(cell)) == 0 then
        -- A first-pass parent is retained; only previously rejected sites
        -- need the relaxed obstacle check against the final parent mask.
        if not planning.check() then return false end
        if capacityParent(planning, summary, cell, parentParity, result.parents) then
          result.sites = result.sites | bit(cell)
        end
      end
    end
  end
  result.sites = result.sites | result.working
  for cell = 1, 36 do
    local facts = planning.projection.at(cell)
    if summary.usable(facts) and (result.parents & bit(cell)) == 0 then result.harvest = result.harvest + 1 end
    if (result.sites & bit(cell)) ~= 0 then result.capacity = result.capacity + 1 end
  end
  return true
end
local function archiveNeeded(planning)
  local disposition = planning.view.archiveDisposition
  if not disposition then return false end
  local function needs(item, live)
    local descriptor = Facts.descriptor(item)
    if live then descriptor.itemKind = Quantity.outputKind(descriptor) end
    if not descriptor.itemKind then return false end
    local result = disposition(descriptor)
    return result == "KEEP" or result == "REPLACE" or result == "FULL"
  end
  for _, cell in ipairs(planning.exactLive) do if needs(planning.view.field[cell], true) then return true end end
  if planning.exactMaterial and needs(planning.view.material) then return true end
  for sourceIndex = 1, #planning.bankSources, 2 do
    local item = planning.bankSources[sourceIndex + 1]
    if Quantity.matchesDescriptor(item, planning.view.order) and needs(item) then return true end
  end
  return false
end
local function layoutCapacity(planning, layout)
  local field = planning.view.field
  local capacity = 0
  for _, parent in ipairs(layout.parents) do
    local facts = field[parent]
    if not Facts.known(facts) or Facts.empty(facts) or facts.tile then
      for direction = 1, 4 do
        local cell = Facts.adjacent(parent, direction)
        if cell then
          local site = field[cell]
          if not Facts.known(site) or Facts.empty(site) or site.tile then capacity = capacity + 1 end
        end
      end
    end
    if not planning.check() then return end
  end
  return capacity
end
function Strategy.summarize(planning)
  local summary = { key = planning.view.order.key, blocked = "NO_FEASIBLE_COPY_SITE" }
  summary.usable = function(facts) return usable(facts, planning.view.order) end
  summary.projectedField = setmetatable({}, { __index = function(_, cell) return planning.projection.at(cell) end })
  local bestCapacity = -1
  for _, layout in ipairs(layouts) do
    local capacity = layoutCapacity(planning, layout)
    if not capacity then
      summary.cancelled = true; return summary
    end
    if capacity > bestCapacity then
      summary.layout = layout; bestCapacity = capacity
    end
  end
  summary.baseline = {}
  summary.layoutCapacity = bestCapacity
  if not measure(planning, summary, summary.layout.parity, summary.baseline) then
    summary.cancelled = true; return summary
  end
  summary.archiveNeeded = archiveNeeded(planning)
  summary.demand = Quantity.remaining(planning.view.order) + (summary.archiveNeeded and 1 or 0)
  summary.copyBudget = Quantity.budget(planning.view.order, summary.archiveNeeded,
    summary.baseline.harvest, summary.baseline.copies)
  summary.expand = summary.baseline.capacity == 0 or
      summary.demand > 2 * summary.baseline.capacity and
      summary.baseline.harvest + summary.baseline.copies < summary.demand
  return summary
end

function Strategy.enumerate(planning, summary)
  if summary.expand then
    local function install(target)
      local site = planning.view.field[target]
      if Facts.known(site) and not (Facts.empty(site) or site.tile) then return end
      if not Facts.known(site) then
        local possible = false
        for direction = 1, 4 do
          local neighbor = Facts.adjacent(target, direction)
          local facts = neighbor and planning.view.field[neighbor]
          if neighbor and (not Facts.known(facts) or Facts.empty(facts) or facts.tile) then
            possible = true; break
          end
        end
        if not possible then return end
      end
      planning.install(target, function(item, source)
        if source > 0 then
          if not summary.usable(item) then return false end
          if summary.baseline.capacity > 0 and (summary.baseline.parents & bit(source)) ~= 0 then return false end
          return not summary.usable(site) or (summary.baseline.parents & bit(source)) ~= 0
        end
        if #planning.exactLive > 0 or summary.usable(site) then return false end
        return Quantity.matchesDescriptor(item, planning.view.order)
      end, 0, "QUANTITY_EXPAND")
    end
    for _, target in ipairs(summary.layout.parents) do install(target) end
    if summary.baseline.capacity < summary.layoutCapacity or summary.layoutCapacity == 0 then
      for target = 1, 36 do
        if parity(target) == summary.layout.parity and (summary.layout.mask & bit(target)) == 0 then install(target) end
      end
    end
  end
  for _, source in ipairs(planning.exactLive) do
    if (summary.baseline.parents & bit(source)) == 0 and summary.baseline.capacity > 0 then
      local parent = Strategy.usesSite(planning, summary, source) == true and
          capacityParent(planning, summary, source, summary.layout.parity, summary.baseline.parents)
      local obstacles = parent and Facts.copyObstacles(planning.view.field, parent, source)
      local resultKind = obstacles == bit(source) and "DOUBLE" or nil
      planning.offer("EXTRACT", 0, source, nil, 0, "QUANTITY_RESULT", nil, resultKind)
    elseif summary.copyBudget > 0 then
      for direction = 1, 4 do
        local target = Facts.adjacent(source, direction)
        if target and parity(target) ~= summary.layout.parity then
          planning.offer("ENABLE_COPY", source, target, nil, 0, "QUANTITY_COPY")
        end
      end
    end
    if not planning.check() then return end
  end
end

local function preservesWork(candidate, planning, summary)
  local before = summary.baseline
  for cell = 1, 36 do
    if (candidate.removed & bit(cell)) ~= 0 then
      local removed = planning.view.field[cell]
      if removed.kind == "PLANT" and not Facts.crop(removed) then
        planning.wait("LOCAL_FACTS_UNREADABLE")
        return false
      end
    end
    if (before.parents & bit(cell)) ~= 0 and cell ~= candidate.source and
        not summary.usable(planning.projection.at(cell)) then
      return false
    end
    if (before.working & bit(cell)) ~= 0 then
      local parent = planning.projection.copyParent(cell, summary.usable)
      local oldParent
      for direction = 1, 4 do
        local adjacent = Facts.adjacent(cell, direction)
        if adjacent and summary.usable(planning.view.field[adjacent]) then
          oldParent = adjacent; break
        end
      end
      if not parent or Facts.mature(planning.view.field[oldParent]) and
          not Facts.mature(planning.projection.at(parent)) then
        return false
      end
    end
    if (candidate.removed & bit(cell)) ~= 0 and summary.usable(planning.view.field[cell]) and
        candidate.operation ~= "EXTRACT" and not (candidate.operation == "INSTALL" and candidate.source > 0 and
          (before.parents & bit(cell)) ~= 0 and (before.parents & bit(candidate.source)) ~= 0) then
      return false
    end
  end
  return true
end
function Strategy.evaluate(candidate, planning, summary)
  if not preservesWork(candidate, planning, summary) then return false end
  if not measure(planning, summary, summary.layout.parity, candidate) then return false end
  local before = summary.baseline
  candidate.priority, candidate.section = 0, 0
  if candidate.operation == "INSTALL" then
    if not summary.expand or not summary.usable(planning.projection.at(candidate.destination)) or
        candidate.capacity <= before.capacity then
      return false
    end
    if candidate.source == 0 and #planning.exactLive > 0 then return false end
    if candidate.source > 0 and before.capacity > 0 and
        (before.parents & bit(candidate.source)) ~= 0 then
      return false
    end
    candidate.priority = 3
    for index, cell in ipairs(summary.layout.parents) do
      if cell == candidate.destination then
        candidate.section = 7 - index; break
      end
    end
    return true
  elseif candidate.operation == "EXTRACT" then
    if before.capacity == 0 or (before.parents & bit(candidate.destination)) ~= 0 or
        not summary.usable(planning.view.field[candidate.destination]) or candidate.capacity < before.capacity then
      return false
    end
    candidate.priority = 2; candidate.purpose = "QUANTITY_RESULT"
    return true
  elseif candidate.operation == "ENABLE_COPY" then
    if summary.copyBudget <= 0 or (before.parents & bit(candidate.source)) == 0 or
        candidate.capacity < before.capacity or candidate.copies <= before.copies then
      return false
    end
    candidate.priority = 1
    return true
  end
  return candidate.operation == "RELEASE_SITE"
end

function Strategy.compareCandidates(first, second)
  for _, name in ipairs(comparisonOrder) do
    if first[name] ~= second[name] then return first[name] - second[name] end
  end
  return 0
end

function Strategy.usesSite(planning, summary, cell)
  for direction = 1, 4 do
    local neighbor = Facts.adjacent(cell, direction)
    local facts = neighbor and planning.view.field[neighbor]
    if neighbor and (not Facts.known(facts) or facts.kind == "PLANT" and not Facts.crop(facts)) then return nil end
  end
  local existing = (summary.baseline.working & bit(cell)) ~= 0
  if existing then
    return Quantity.budget(planning.view.order, summary.archiveNeeded, summary.baseline.harvest,
      summary.baseline.copies - 1) > 0
  end
  if parity(cell) == summary.layout.parity then return false end
  local parent = capacityParent(planning, summary, cell, summary.layout.parity, summary.baseline.parents)
  if not parent or (summary.baseline.parents & bit(parent)) == 0 then return false end
  return Quantity.budget(planning.view.order, summary.archiveNeeded, summary.baseline.harvest,
    summary.baseline.copies) > 0
end

function Strategy.waiting(planning, summary)
  for cell = 1, 36 do
    if (summary.baseline.working & bit(cell)) ~= 0 then
      local parent = planning.projection.copyParent(cell, summary.usable)
      if parent and not Facts.mature(planning.projection.at(parent)) then return "PARENT_MATURING" end
    end
  end
  if summary.baseline.copies > 0 then return "WAIT_SPREADING" end
end

return Strategy
