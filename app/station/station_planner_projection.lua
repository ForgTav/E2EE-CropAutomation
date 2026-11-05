local Facts = require("station_planner_facts")
local Quantity = require("station_production_rules")
local Projection = {}
local air = { kind = "AIR", scanOk = true, tile = false }
local double = { kind = "DOUBLE", scanOk = true, tile = true, crossingBase = 1 }
local function bit(cell) return 1 << (cell - 1) end
function Projection.transfer(source, allowGrowth)
  if not Facts.plant(source) or not allowGrowth and (not source.size or source.size < 2) then return end
  local itemKind = Quantity.outputKind(source, Facts.key(source))
  if itemKind then return Facts.installation(source, itemKind) end
end

function Projection.new(view)
  local field, overlay = view.field, {}
  local projection = {}
  function projection.at(cell) return overlay[cell] or field[cell] end

  function projection.reset() for cell in pairs(overlay) do overlay[cell] = nil end end

  function projection.group(center, cropKey, future)
    local count, ready, foreign, unknown = 0, 0, 0, false
    for direction = 1, 4 do
      local cell = Facts.adjacent(center, direction)
      if cell then
        local facts = projection.at(cell)
        if not Facts.known(facts) then
          unknown = true
        elseif facts.kind == "PLANT" then
          if not Facts.crop(facts) then
            unknown = true
          elseif Facts.key(facts) ~= cropKey then
            foreign = foreign + 1
          else
            count = count + 1; if Facts.mature(facts) then ready = ready + 1 end
          end
        end
      end
    end
    return future and count or ready, count, foreign, unknown
  end

  function projection.copyParent(center, usable)
    local site = projection.at(center)
    if not Facts.known(site) or not (Facts.doubleSite(site) or site.kind == "DOUBLE") then return end
    local count, parent = 0, nil
    for direction = 1, 4 do
      local cell = Facts.adjacent(center, direction)
      if cell then
        local facts = projection.at(cell)
        if not Facts.known(facts) then return end
        if facts.tile then
          count = count + 1; if usable(facts) then parent = cell end
        end
      end
    end
    if count == 1 then return parent end
  end

  function projection.copySite(source, vacated, isCrossCell, allowRemoval)
    for direction = 1, 4 do
      local center = Facts.adjacent(source, direction)
      if center and (not isCrossCell or isCrossCell(center)) then
        local site = projection.at(center)
        if Facts.known(site) and (Facts.doubleSite(site) or site.kind == "DOUBLE") then
          local clear = true
          for neighborDirection = 1, 4 do
            local cell = Facts.adjacent(center, neighborDirection)
            if cell and cell ~= source and cell ~= vacated then
              local facts = projection.at(cell)
              if not Facts.known(facts) or facts.tile and not (allowRemoval and allowRemoval(facts, cell)) then
                clear = false; break
              end
            end
          end
          if clear then return center end
        end
      end
    end
  end

  local function remove(candidate, cell)
    candidate.removed = candidate.removed | bit(cell); overlay[cell] = air
  end
  function projection.prepare(candidate)
    projection.reset()
    local destination, source = candidate.destination, candidate.source or 0
    local site = field[destination]
    candidate.removed, candidate.changed = 0, bit(destination)
    candidate.cost, candidate.spent = 1, 0
    candidate.firstName, candidate.firstFrom, candidate.firstTo = nil, 0, destination
    if not Facts.known(site) then return nil, "LOCAL_FACTS_UNREADABLE" end
    local operation = candidate.operation
    if operation == "INSTALL" then
      if not (Facts.empty(site) or site.tile) then return end
      local installed
      if source > 0 then
        if source == destination then return end
        if not Facts.known(field[source]) then return nil, "LOCAL_FACTS_UNREADABLE" end
        installed = Projection.transfer(field[source], true)
        if not installed then return end
        if not field[source].size or field[source].size < 2 then candidate.waiting = "PARENT_MATURING" end
        overlay[source] = air; candidate.changed = candidate.changed | bit(source)
        candidate.firstName, candidate.firstFrom = "EXTRACT_AND_PLANT", source
      else
        installed = Facts.installation(candidate.material)
        if not installed then return end
        candidate.spent = 1
        if candidate.slot and not Facts.sameMaterial(candidate.material, view.material) then
          candidate.cost = candidate.cost + 1; candidate.firstName = "MATERIAL"
        elseif Facts.sameMaterial(candidate.material, view.material) then
          candidate.firstName = "PLANT_SEED"
        else
          return
        end
      end
      candidate.installed = installed; overlay[destination] = installed
      if site.tile then
        candidate.removed = bit(destination); candidate.cost = candidate.cost + 1
        if source == 0 then
          if candidate.firstName ~= "MATERIAL" then
            candidate.firstName, candidate.firstFrom = "COLLECT_AND_CLEAR_CELL",
                0
          end
        end
      end
    elseif operation == "ENABLE_COPY" or operation == "ENABLE_CROSS" then
      if not (Facts.empty(site) or site.tile) then return end
      local parentsReady
      if operation == "ENABLE_COPY" then
        local adjacent = false
        for direction = 1, 4 do if Facts.adjacent(destination, direction) == source then adjacent = true end end
        if not adjacent then return end
        if not Facts.known(field[source]) then return nil, "LOCAL_FACTS_UNREADABLE" end
        if not Facts.plant(field[source]) then return end
        parentsReady = Facts.mature(field[source])
        local obstacles, missing = Facts.copyObstacles(field, source, destination)
        if not obstacles then return nil, missing and "LOCAL_FACTS_UNREADABLE" or nil end
        for cell = 1, 36 do
          if (obstacles & bit(cell)) ~= 0 then remove(candidate, cell) end
        end
      end
      if site.kind == "PLANT" then remove(candidate, destination) end
      for direction = 1, 4 do
        local cell = Facts.adjacent(destination, direction)
        if cell then
          local facts = field[cell]
          if not Facts.known(facts) then return nil, "LOCAL_FACTS_UNREADABLE" end
          if operation == "ENABLE_CROSS" and facts.kind == "PLANT" then
            if not Facts.crop(facts) then return nil, "LOCAL_FACTS_UNREADABLE" end
            if Facts.key(facts) ~= candidate.key then remove(candidate, cell) end
          end
        end
      end
      if operation == "ENABLE_CROSS" then
        local ready, count, foreign, unknown = projection.group(destination, candidate.key, false)
        if unknown then return nil, "LOCAL_FACTS_UNREADABLE" end
        if count < 2 or foreign > 0 then return end
        parentsReady = ready >= 2
      end
      overlay[destination] = double
      candidate.firstName = site.kind == "PLANT" and
          (parentsReady and "COLLECT_AND_RESTORE_DOUBLE" or "COLLECT_AND_CLEAR_CELL") or "PLACE_DOUBLE_STICKS"
      if not parentsReady and site.kind == "PLANT" then candidate.cost = candidate.cost + 1 end
      for cell = 1, 36 do
        if cell ~= destination and (candidate.removed & bit(cell)) ~= 0 then
          candidate.cost = candidate.cost + 1
          if candidate.firstName == "PLACE_DOUBLE_STICKS" or candidate.firstName == "COLLECT_AND_RESTORE_DOUBLE" then
            candidate.firstName, candidate.firstTo = "COLLECT_AND_CLEAR_CELL", cell
          end
        end
      end
      candidate.changed = candidate.changed | candidate.removed
      if candidate.removed == 0 and site.kind == "DOUBLE" then return end
      -- Evaluate the useful final site, but dispatch only clearing until its
      -- real parents are ready. No continuation reserves this destination.
      if not parentsReady and candidate.firstName == "PLACE_DOUBLE_STICKS" then
        candidate.waiting = "PARENT_MATURING"
      end
    elseif operation == "EXTRACT" then
      if not Facts.plant(site) then return end
      if not site.size or site.size < 2 then candidate.waiting = "COPY_MATURING" end
      candidate.firstName = "COLLECT_AND_CLEAR_CELL"; remove(candidate, destination)
      if candidate.resultKind == "DOUBLE" then
        local parent = projection.copyParent(destination, Facts.plant)
        if not parent then return end
        if Facts.mature(projection.at(parent)) then
          overlay[destination] = double; candidate.firstName = "COLLECT_AND_RESTORE_DOUBLE"
        else
          candidate.resultKind = nil
        end
      end
    elseif operation == "RELEASE_SITE" then
      if not site.tile then return end
      candidate.firstName = "COLLECT_AND_CLEAR_CELL"; remove(candidate, destination)
    else
      error("Unknown planner operation: " .. tostring(operation))
    end
    candidate.changed = candidate.changed | candidate.removed; candidate.footprint = candidate.changed
    return true
  end

  return projection
end

return Projection
