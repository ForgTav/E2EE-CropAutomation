local Facts = require("station_planner_facts")
local Strategy = { parents = {}, children = {}, cells = {} }
local parentSet, childSet = {}, {}
local traits = { "g", "ga", "r" }
for row = 1, 5 do
  for column = 1, 5 do
    local cell = (row - 1) * 6 + column
    Strategy.cells[#Strategy.cells + 1] = cell
    local roles = (row + column) % 2 == 0 and Strategy.children or Strategy.parents
    roles[#roles + 1] = cell
    if (row + column) % 2 == 0 then childSet[cell] = true else parentSet[cell] = true end
  end
end
function Strategy.isCrossCell(cell) return childSet[cell] == true end

function Strategy.isParentCell(cell) return parentSet[cell] == true end

local function crop(f, goal) return Facts.plant(f) and Facts.key(f) == goal.key end
local function free(f)
  return Facts.known(f) and (f.kind == "AIR" or f.kind == "SINGLE" or f.kind == "DOUBLE")
end
function Strategy.score(f, goal)
  local sum, squares = 0, 0
  for _, trait in ipairs(traits) do
    if goal[trait] ~= nil then
      local error = math.abs(f[trait] - goal[trait])
      sum, squares = sum + error, squares + error * error
    end
  end
  return sum, squares
end

function Strategy.compare(first, second, goal, mode)
  local firstSum, firstSquares = Strategy.score(first, goal)
  local secondSum, secondSquares = Strategy.score(second, goal)
  if mode == "FAR" and firstSquares ~= secondSquares then return firstSquares < secondSquares end
  return firstSum < secondSum
end

local function distance(first, second)
  if type(first) ~= "number" or first < 1 or first > 36 then return 0 end
  return math.abs(math.floor((first - 1) / 6) - math.floor((second - 1) / 6)) +
      math.abs((first - 1) % 6 - (second - 1) % 6)
end
Strategy.distance = distance
function Strategy.goal(view)
  for cell = 1, 36 do
    if crop(view.field[cell], view.order) and Strategy.score(view.field[cell], view.order) == 0 then return true end
  end
  return false
end

function Strategy.inspect(view, mode)
  local field, goal = view.field, view.order
  local result = { parents = {}, free = {}, worst = nil, bestSum = math.huge, parentUnknown = false, near = true }
  for _, cell in ipairs(Strategy.cells) do
    if crop(field[cell], goal) then
      local sum = Strategy.score(field[cell], goal)
      if sum < result.bestSum then result.bestSum, result.bestNearCell = sum, cell end
      if not result.bestFarCell or Strategy.compare(field[cell], field[result.bestFarCell], goal, "FAR") then
        result.bestFarCell = cell
      end
    end
  end
  for _, cell in ipairs(Strategy.parents) do
    local f = field[cell]
    if crop(f, goal) then
      result.parents[#result.parents + 1] = cell
      if not result.worst or Strategy.compare(field[result.worst], f, goal, mode) then result.worst = cell end
      for _, trait in ipairs(traits) do
        if goal[trait] ~= nil and math.abs(f[trait] - goal[trait]) > 4 then result.near = false end
      end
    elseif free(f) then
      result.free[#result.free + 1] = cell
    elseif not Facts.known(f) or f.kind == "PLANT" and not Facts.plant(f) then
      result.parentUnknown = true; result.near = false
    end
  end
  if #result.parents == 0 then result.near = false end
  return result
end

function Strategy.useful(f, view, mode, summary)
  if not crop(f, view.order) then return false end
  if #summary.parents == 0 then return true end
  return summary.worst and Strategy.compare(f, view.field[summary.worst], view.order, mode) or
      #summary.free > 0 and Strategy.score(f, view.order) <= summary.bestSum + 6
end

function Strategy.connectivity(view, cell)
  local score = 0
  Facts.neighbors(cell, function(center)
    if childSet[center] then
      local count = 0
      Facts.neighbors(center, function(neighbor)
        if parentSet[neighbor] and crop(view.field[neighbor], view.order) then count = count + 1 end
      end)
      score = score + (count == 1 and 3 or count >= 2 and 1 or 0)
    end
  end)
  return score
end

function Strategy.destination(view, summary, source)
  if #summary.free == 0 then return summary.worst end
  local selected, best
  for _, cell in ipairs(summary.free) do
    local score = Strategy.connectivity(view, cell)
    if not selected or score > best or score == best and
        (distance(source, cell) < distance(source, selected) or
          distance(source, cell) == distance(source, selected) and cell < selected) then
      selected, best = cell, score
    end
  end
  return selected
end

local function same(facts, key) return Facts.plant(facts) and Facts.key(facts) == key end
local function copyPurpose(planning, summary)
  local goal = planning.view.order
  local missing = false
  for _, target in ipairs(Strategy.parents) do
    local available = planning.projection.at(target)
    if not Facts.known(available) then
      missing = true
    elseif (Facts.empty(available) or available.tile) and not crop(available, goal) then
      for direction = 1, 4 do
        local center = Facts.adjacent(target, direction)
        if center and childSet[center] then
          local _, count, foreign, unknown = planning.projection.group(center, summary.key, true)
          if count >= 1 and foreign == 0 and not unknown then return true end
          if unknown and foreign == 0 then missing = true end
        end
      end
    end
  end
  if missing then return nil end
  return false
end
local function crossPurpose(planning, summary, cell)
  if not childSet[cell] then return false end
  local _, count, foreign, unknown = planning.projection.group(cell, summary.key, true)
  if unknown then return nil end
  return count >= 2 and foreign == 0
end
function Strategy.usesSite(planning, summary, cell)
  local crossing = crossPurpose(planning, summary, cell)
  if crossing ~= false then return crossing end
  if not childSet[cell] then return false end
  local parent = planning.projection.copyParent(cell, function(facts) return same(facts, summary.key) end)
  if parent and parentSet[parent] then return copyPurpose(planning, summary) end
  return false
end

function Strategy.summarize(planning)
  local view = planning.view
  local summary = Strategy.inspect(view, "FAR")
  summary.key = view.order.key
  summary.mode = summary.near and "NEAR" or "FAR"
  local bestCell = summary.near and summary.bestNearCell or summary.bestFarCell
  local bestPlant = bestCell and view.field[bestCell]
  summary.genetics = {
    mode = summary.mode,
    bestCell = bestCell,
    g = bestPlant and bestPlant.g,
    ga = bestPlant and bestPlant.ga,
    r = bestPlant and bestPlant.r
  }
  if summary.near then
    summary.worst = nil
    for _, cell in ipairs(summary.parents) do
      if not summary.worst or Strategy.compare(view.field[summary.worst], view.field[cell], view.order, "NEAR") then
        summary.worst = cell
      end
    end
  end
  summary.stopWhen = { key = view.order.key, g = view.order.g, ga = view.order.ga, r = view.order.r }
  summary.useful = {}
  for _, cell in ipairs(Strategy.children) do
    if view.field[cell] and view.field[cell].kind == "DOUBLE" then
      local ready, _, foreign, unknown = planning.projection.group(cell, summary.key, false)
      if ready >= 2 and foreign == 0 and not unknown then summary.active = true end
    end
    if same(view.field[cell], summary.key) then
      summary.useful[cell] = Strategy.useful(view.field[cell], view, summary.mode, summary)
      if summary.useful[cell] and view.field[cell].size and view.field[cell].size < 2 then summary.growing = true end
    end
    if not planning.check() then
      summary.cancelled = true; return summary
    end
  end
  return summary
end

function Strategy.enumerate(planning, summary)
  local field = planning.view.field
  for _, cell in ipairs(Strategy.children) do
    local facts = field[cell]
    if same(facts, summary.key) and summary.useful[cell] then
      local target = Strategy.destination(planning.view, summary, cell)
      if target then planning.offer("INSTALL", cell, target, nil, 1, "INSTALL_PARENT") end
    elseif Facts.plant(facts) then
      if not summary.parentUnknown then
        local operation = crossPurpose(planning, summary, cell) and "ENABLE_CROSS" or "RELEASE_SITE"
        planning.offer(operation, 0, cell, nil, 2, "REJECT_OFFSPRING")
      end
    else
      planning.offer("ENABLE_CROSS", 0, cell, nil, 3, "ACTIVATE_CROSS")
    end
  end
  local materialTarget = Strategy.destination(planning.view, summary, 0)
  if materialTarget then
    planning.install(materialTarget, function(facts, source)
      if source ~= 0 or Facts.key(facts) ~= summary.key then return false end
      local installed = Facts.installation(facts)
      return installed and Strategy.useful(installed, planning.view, summary.mode, summary)
    end, 1, "INSTALL_MATERIAL_PARENT")
  end
  if #summary.parents < 2 then
    for _, target in ipairs(Strategy.parents) do
      if not same(field[target], summary.key) then
        planning.install(target, function(facts, source)
          return Facts.key(facts) == summary.key and (source == 0 or not parentSet[source])
        end, 3, "ESTABLISH_LINE")
      end
    end
  end
  if #summary.parents < 2 or not summary.active then
    for _, source in ipairs(summary.parents) do
      for direction = 1, 4 do
        local center = Facts.adjacent(source, direction)
        if center and childSet[center] then planning.offer("ENABLE_COPY", source, center, nil, 4, "ESTABLISH_COPY") end
      end
      if not planning.projection.copySite(source, nil, Strategy.isCrossCell) then
        for _, target in ipairs(summary.free) do
          planning.offer("INSTALL", source, target, nil, 5, "RELOCATE_SOURCE")
        end
      end
    end
  end
end

function Strategy.evaluate(candidate, planning, summary)
  local field, goal = planning.view.field, planning.view.order
  if candidate.operation == "INSTALL" then
    local installed = candidate.installed
    if not installed or Facts.key(installed) ~= summary.key then return false end
    if candidate.source > 0 and not Facts.geneticsMatch(installed, field[candidate.source]) then return false end
    if candidate.rank == 1 then
      if candidate.source > 0 and not summary.useful[candidate.source] or
          candidate.source == 0 and not Strategy.useful(installed, planning.view, summary.mode, summary) then
        return false
      end
      if candidate.destination ~= Strategy.destination(planning.view, summary, candidate.source) then return false end
      candidate.quality1, candidate.quality2 = Strategy.score(installed, goal)
    else
      if same(field[candidate.destination], summary.key) then return false end
      if not planning.projection.copySite(candidate.destination, candidate.source, Strategy.isCrossCell,
            function(facts) return not crop(facts, goal) end) and
          #summary.parents == 0 then
        return false
      end
      candidate.connectivity = Strategy.connectivity(planning.view, candidate.destination)
      candidate.distance = Strategy.distance(candidate.source, candidate.destination)
    end
    return true
  end
  for cell = 1, 36 do
    if (candidate.removed & (1 << (cell - 1))) ~= 0 and same(field[cell], summary.key) then
      if parentSet[cell] or summary.useful[cell] then return false end
    end
  end
  if candidate.operation == "ENABLE_COPY" then
    if summary.useful[candidate.destination] then return false end
    return copyPurpose(planning, summary)
  elseif candidate.operation == "ENABLE_CROSS" then
    local ready = planning.projection.group(candidate.destination, summary.key, false)
    candidate.ready = ready
    return true
  end
  return candidate.operation == "RELEASE_SITE"
end

function Strategy.compareCandidates(first, second, _, summary)
  if first.rank ~= second.rank then return second.rank - first.rank end
  if first.rank == 2 then return 0 end
  if first.rank == 1 then
    if summary.mode == "FAR" and first.quality2 ~= second.quality2 then return second.quality2 - first.quality2 end
    if first.quality1 ~= second.quality1 then return second.quality1 - first.quality1 end
    if (first.source > 0) ~= (second.source > 0) then return first.source > 0 and 1 or -1 end
    return second.source - first.source
  end
  if first.ready ~= second.ready then return (first.ready or 0) - (second.ready or 0) end
  if first.connectivity ~= second.connectivity then return (first.connectivity or 0) - (second.connectivity or 0) end
  if first.distance ~= second.distance then return (second.distance or 0) - (first.distance or 0) end
  return 0
end

function Strategy.waiting(planning, summary)
  if summary.growing then return "PARENT_MATURING" end
  for _, center in ipairs(Strategy.children) do
    if planning.view.field[center] and planning.view.field[center].kind == "DOUBLE" then
      if crossPurpose(planning, summary, center) then return "FIELD_PROCESS" end
      local parent = planning.projection.copyParent(center, function(facts) return same(facts, summary.key) end)
      if parent then return "WAIT_SPREADING" end
    end
  end
  if summary.parentUnknown then return "LOCAL_FACTS_UNREADABLE" end
end

return Strategy
