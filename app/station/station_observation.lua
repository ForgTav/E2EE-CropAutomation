local StationObservation = {}
local function rotate(x, z, rotation)
  for _ = 1, rotation do x, z = -z, x end; return x, z
end
function StationObservation.dock(scan)
  local function readBlockName(x, y, z, candidateRotation)
    x, z = rotate(x, z, candidateRotation)
    local sensorResult, scanError = scan(x, y, z)
    if scanError ~= nil or type(sensorResult) ~= "table" or type(sensorResult.block) ~= "table" or type(sensorResult.block.name) ~= "string" then
      error(scanError or "DOCK_SCAN_UNREADABLE", 0)
    end
    return sensorResult.block.name
  end
  local function isOpenComputersBlock(block, kind) return block == "oc:" .. kind or block == "opencomputers:" .. kind end
  local rotation
  for candidateRotation = 0, 3 do
    if isOpenComputersBlock(readBlockName(-1, 0, 0, candidateRotation), "charger") then
      if rotation then return nil, "DOCK_AMBIGUOUS" end
      rotation = candidateRotation
    end
  end
  if rotation == nil then return nil, "CHARGER_NOT_FOUND" end
  return rotation
end

function StationObservation.findRobot(scan, rotation, firstPosition)
  local function check(x, y, z)
    local sensorX, sensorZ = rotate(x - 1, z, rotation)
    local sensorResult, scanError = scan(sensorX, y, sensorZ)
    if scanError ~= nil or type(sensorResult) ~= "table" or type(sensorResult.block) ~= "table" or
        type(sensorResult.block.name) ~= "string" or sensorResult.block.name == "" then
      error("ROBOT_SCAN_UNREADABLE", 0)
    end
    local name = sensorResult.block.name
    if name == "oc:robot" or name == "opencomputers:robot" then
      return { x = x, y = y, z = z }
    end
  end
  local observedPosition
  if firstPosition then
    for _, delta in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      observedPosition = check(firstPosition.x + delta[1], 1, firstPosition.z + delta[2])
      if observedPosition then return observedPosition end
    end
  else
    observedPosition = check(0, 0, -1); if observedPosition then return observedPosition end
    observedPosition = check(0, 1, -1); if observedPosition then return observedPosition end
    for z = -3, 2 do
      for x = -1, -6, -1 do
        observedPosition = check(x, 1, z); if observedPosition then return observedPosition end
      end
    end
    for z = -3, 2 do
      observedPosition = check(-7, 1, z); if observedPosition then return observedPosition end
      if z ~= -1 then
        observedPosition = check(0, 1, z); if observedPosition then return observedPosition end
      end
    end
    for x = -1, -6, -1 do
      observedPosition = check(x, 1, -4); if observedPosition then return observedPosition end
      observedPosition = check(x, 1, 3); if observedPosition then return observedPosition end
    end
    observedPosition = check(1, 1, -1); if observedPosition then return observedPosition end
  end
  error("ROBOT_NOT_FOUND", 0)
end

local function integer(value, minimum, maximum)
  return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
end
local function ident(value, limit)
  return type(value) == "string" and #value > 0 and #value <= limit and value:match("^[a-z0-9_.%-]+$") ~= nil
end
function StationObservation.coordinates(cell)
  if not integer(cell, 1, 36) then return nil, "INVALID_CELL" end
  local row = math.floor((cell - 1) / 6) + 1
  local column = (cell - 1) % 6 + 1
  return -column - 1, 0, row - 4, (row + column) % 2 == 0 and "X" or "R"
end

local function copy(sourceRecord)
  local recordCopy = {}; for fieldName, fieldValue in pairs(sourceRecord) do recordCopy[fieldName] = fieldValue end; return
      recordCopy
end
function StationObservation.dangerous(cellFacts)
  if cellFacts.kind ~= "PLANT" then return end
  local cropKey = tostring(cellFacts.owner) .. ":" .. tostring(cellFacts.id)
  if not require("station_catalog").isDangerous(cropKey, cellFacts.g or 0) then return end
  if cellFacts.owner == "ic2" and cellFacts.id == "weed" then return "WEED" end
  if cellFacts.g and cellFacts.g >= 24 then return "HIGH_GROWTH" end
  return "VENOMILIA"
end

function StationObservation.normalize(sensorResult)
  local cellFacts = { kind = "UNREADABLE", scanOk = false }
  if type(sensorResult) ~= "table" or type(sensorResult.block) ~= "table" or
      type(sensorResult.block.name) ~= "string" or #sensorResult.block.name > 96 or
      not sensorResult.block.name:match("^[a-z0-9_.%-]+:[a-z0-9_./%-]+$") then
    return cellFacts, "INVALID_BLOCK"
  end
  cellFacts.block = sensorResult.block.name
  if sensorResult.block.meta ~= nil then
    if not integer(sensorResult.block.meta, 0, 65535) then return cellFacts, "INVALID_BLOCK_META" end
    cellFacts.meta = sensorResult.block.meta
  end
  if sensorResult.data ~= nil and type(sensorResult.data) ~= "table" then return cellFacts, "INVALID_DATA" end
  local cropFields = sensorResult.data and sensorResult.data.Crop
  local isCropBlock = cellFacts.block == "ic2:te" and cellFacts.meta == 11
  if cropFields == nil then
    if isCropBlock then return cellFacts, "MISSING_CROP" end
    if cellFacts.block == "ic2:te" and cellFacts.meta == nil then return cellFacts, "MISSING_IC2_META" end
    cellFacts.kind = cellFacts.block == "minecraft:air" and "AIR" or "OBSTRUCTED"
    cellFacts.scanOk = true; return cellFacts
  end
  if not isCropBlock then return cellFacts, "INVALID_CROP_BLOCK" end
  if type(cropFields) ~= "table" then return cellFacts, "INVALID_CROP" end
  cellFacts.tile = true
  local invalidCropField
  local function number(key, target, maximum, minimum)
    local fieldValue = cropFields[key]
    if fieldValue ~= nil then
      if integer(fieldValue, minimum or 0, maximum) then
        cellFacts[target] = fieldValue
      else
        invalidCropField =
            "INVALID_" .. key
      end
    end
  end
  number("statGrowth", "g", 31); number("statGain", "ga", 31); number("statResistance", "r", 31)
  number("currentSize", "size", 255); number("growthPoints", "growthPoints", 2147483647)
  number("crossingBase", "crossingBase", 1)
  number("terrainHumidity", "terrainH", 127, -128); number("terrainNutrients", "terrainN", 127, -128)
  number("terrainAirQuality", "terrainA", 127, -128)
  local owner, id = cropFields.cropOwner, cropFields.cropId
  if ident(owner, 32) and ident(id, 48) then
    cellFacts.owner, cellFacts.id = owner, id; cellFacts.kind = "PLANT"
  elseif (owner == nil or owner == "") and (id == nil or id == "") then
    if cellFacts.crossingBase == 0 then
      cellFacts.kind = "SINGLE"
    elseif cellFacts.crossingBase == 1 then
      cellFacts.kind = "DOUBLE"
    else
      invalidCropField = "MISSING_CROSSING_BASE"
    end
  else
    invalidCropField = "INVALID_IDENTITY"
  end
  cellFacts.danger = StationObservation.dangerous(cellFacts)
  if invalidCropField then
    cellFacts.kind = "UNREADABLE"; return cellFacts, invalidCropField
  end
  cellFacts.scanOk = true
  return cellFacts
end

function StationObservation.change(previousCellFacts, observedCellFacts)
  if observedCellFacts.danger and (observedCellFacts.danger ~= previousCellFacts.danger or previousCellFacts.owner ~= observedCellFacts.owner or previousCellFacts.id ~= observedCellFacts.id) then
    return
    "DANGEROUS"
  end
  if observedCellFacts.kind == "PLANT" and previousCellFacts.kind ~= "PLANT" then return "NEW_PLANT" end
  if observedCellFacts.kind == "PLANT" and (previousCellFacts.owner ~= observedCellFacts.owner or previousCellFacts.id ~= observedCellFacts.id) then
    return
    "SPECIES_CHANGED"
  end
  if previousCellFacts.tile and not observedCellFacts.tile then return "TILE_DISAPPEARED" end
  if previousCellFacts.kind == "PLANT" and observedCellFacts.kind ~= "PLANT" then return "PLANT_DISAPPEARED" end
  if previousCellFacts.kind ~= observedCellFacts.kind or previousCellFacts.block ~= observedCellFacts.block or previousCellFacts.meta ~= observedCellFacts.meta or previousCellFacts.crossingBase ~= observedCellFacts.crossingBase or
      previousCellFacts.g ~= observedCellFacts.g or previousCellFacts.ga ~= observedCellFacts.ga or previousCellFacts.r ~= observedCellFacts.r then
    return "FIELD_CHANGED"
  end
  if observedCellFacts.kind == "PLANT" and observedCellFacts.size ~= nil and observedCellFacts.size >= 2 and (previousCellFacts.size == nil or previousCellFacts.size < 2) then
    return "MATURE_FOR_DECISION"
  end
  if observedCellFacts.kind == "PLANT" and observedCellFacts.size and previousCellFacts.size then
    local crossFrom = require("station_catalog").crossFrom(observedCellFacts.owner .. ":" .. observedCellFacts.id)
    if crossFrom and previousCellFacts.size < crossFrom and observedCellFacts.size >= crossFrom then
      return
      "MATURE_FOR_DECISION"
    end
  end
  if previousCellFacts.size ~= observedCellFacts.size and (observedCellFacts.size == nil or previousCellFacts.size == nil or observedCellFacts.size < previousCellFacts.size) then
    return
    "FIELD_CHANGED"
  end
end

function StationObservation.new(deps)
  local cells, requests, events = {}, {}, {}
  local eventHead, eventCount = 1, 0
  local generation, scanCancellationRevision, covered = 0, 0, 0
  local planningRevision = 0
  local sensorAvailable
  local startupCheck = deps.startupCheck == true
  local function scanSensor(x, y, z)
    local startedCancellationRevision = scanCancellationRevision
    local callSucceeded, sensorResult, scanError = pcall(deps.scan, x, y, z)
    if (deps.enabled() or startupCheck) and scanCancellationRevision == startedCancellationRevision then
      sensorAvailable = callSucceeded and scanError == nil and sensorResult ~= nil and sensorResult ~= false
    end
    return callSucceeded, sensorResult, scanError
  end
  local urgentMask, urgentVisited = 0, 0
  local activeScan, queueFault, lastError, lastErrorCategory, lastErrorCell
  local scanCount, retryCount, failureCount = 0, 0, 0
  local api = {}
  function api.planningRevision() return planningRevision end

  local rotation, orientationSurvey, orientationRetryAt = nil, nil, -math.huge
  function api.rotation() return rotation end

  local robotRequest, robotSearchWorker, firstRobotPosition
  function api.resetRobot()
    firstRobotPosition = nil; robotRequest = nil; robotSearchWorker = nil
  end

  local dockError
  function api.requestRobot(id, boot)
    if not deps.enabled() then return nil, "STOPPED" end
    if robotRequest then return nil, "ROBOT_SEARCH_BUSY" end
    if firstRobotPosition and firstRobotPosition.boot ~= boot then firstRobotPosition = nil end
    robotRequest = { id = id, boot = boot }; return true
  end

  for cell = 1, 36 do
    cells[cell] = { cell = cell, kind = "UNREADABLE", scanOk = false, version = 0 }
  end
  local function emit(observationEvent)
    if eventCount == 32 then
      queueFault = true; return
    end
    events[(eventHead + eventCount - 1) % 32 + 1] = observationEvent; eventCount = eventCount + 1
  end
  function api.poll()
    if eventCount == 0 then return end
    local observationEvent = events[eventHead]; events[eventHead] = nil; eventHead = eventHead % 32 + 1; eventCount =
        eventCount - 1; return observationEvent
  end

  local function result(scanJob, callSucceeded, scanError, category)
    if scanJob.request then
      emit({
        kind = "SCAN_RESULT",
        cell = scanJob.cell,
        version = cells[scanJob.cell].version,
        token = scanJob.request.token,
        reason = scanJob.request.reason,
        ok = callSucceeded,
        error = scanError,
        errorCategory = category
      })
    end
  end
  function api.pause()
    startupCheck = false
    urgentMask, urgentVisited = 0, 0
    scanCancellationRevision = scanCancellationRevision + 1
    if activeScan then result(activeScan, false, "CANCELLED_STOPPED") end
    for _, scanRequest in ipairs(requests) do
      result({ cell = scanRequest.cell, request = scanRequest }, false,
        "CANCELLED_STOPPED")
    end
    activeScan = nil; requests = {}; orientationSurvey = nil; api.resetRobot()
  end

  function api.start()
    planningRevision = planningRevision + 1
    api.pause(); generation = generation + 1; covered = 0
    rotation = nil; orientationRetryAt = -math.huge; dockError = nil
  end

  function api.snapshot(cell)
    if not cells[cell] then return nil, "INVALID_CELL" end
    return copy(cells[cell])
  end

  function api.forceScan(cell, reason, token)
    if not cells[cell] then return nil, "INVALID_CELL" end
    if not deps.enabled() then return nil, "STOPPED" end
    if queueFault then return nil, "QUEUE_FAULT" end
    if type(reason) ~= "string" or #reason > 48 or
        not (integer(token, 0, 2147483647) or (type(token) == "string" and #token > 0 and #token <= 64)) then
      return nil, "INVALID_REQUEST"
    end
    if activeScan and activeScan.cell == cell and activeScan.request then return nil, "CELL_BUSY" end
    for _, scanRequest in ipairs(requests) do if scanRequest.cell == cell then return nil, "CELL_BUSY" end end
    if #requests + (activeScan and activeScan.request and 1 or 0) >= 8 then return nil, "QUEUE_FULL" end
    requests[#requests + 1] = { cell = cell, reason = reason, token = token }; return true
  end

  local function priority(cellFacts)
    if cellFacts.danger or cellFacts.kind == "DOUBLE" or cellFacts.kind == "SINGLE" then return 1, 5 end
    local _, _, _, role = StationObservation.coordinates(cellFacts.cell)
    if role == "X" and cellFacts.kind == "PLANT" then return 2, 8 end
    if role == "R" and cellFacts.kind == "PLANT" then return 3, 20 end
    return 4, 60
  end
  local function choose(now)
    if urgentMask ~= 0 then
      for cell = 1, 36 do if (urgentMask & (1 << (cell - 1))) ~= 0 then return cell end end
    end
    urgentVisited = 0
    local selected, bestPriority, earliestDueAt, highestRelativeAge
    for cell = 1, 36 do
      local cellFacts = cells[cell]
      if cellFacts then
        local scanPriority, interval = priority(cellFacts)
        local lastSeenAt = cellFacts.generation == generation and cellFacts.seenAt or -math.huge
        if cellFacts.failureGeneration == generation and cellFacts.failedAt and cellFacts.failedAt >= (cellFacts.seenAt or -math.huge) then
          lastSeenAt, interval = cellFacts.failedAt, 60
        end
        local nextScanAt, relativeAge = lastSeenAt + interval, (now - lastSeenAt) / interval
        if now >= nextScanAt and (not highestRelativeAge or relativeAge > highestRelativeAge or
              (relativeAge == highestRelativeAge and (scanPriority < bestPriority or (scanPriority == bestPriority and nextScanAt < earliestDueAt)))) then
          selected, bestPriority, earliestDueAt, highestRelativeAge = cell, scanPriority, nextScanAt, relativeAge
        end
      end
    end
    return selected
  end
  function api.step()
    if not (deps.enabled() or startupCheck) or queueFault then return false end
    if rotation == nil and not orientationSurvey and deps.now() >= orientationRetryAt then
      activeScan = nil
      orientationSurvey = coroutine.create(function()
        return StationObservation.dock(function(x, y, z)
          local callSucceeded, sensorResult, scanError = scanSensor(x, y, z)
          local name = callSucceeded and scanError == nil and type(sensorResult) == "table" and
              type(sensorResult.block) == "table" and sensorResult.block.name
          sensorResult = nil
          coroutine.yield()
          if type(name) ~= "string" then error(scanError or "DOCK_SCAN_FAILED", 0) end
          return { block = { name = name } }
        end)
      end)
    end
    if orientationSurvey then
      local surveyWorker = orientationSurvey
      local callSucceeded, surveyedRotation, scanError = coroutine.resume(surveyWorker)
      if orientationSurvey ~= surveyWorker or not (deps.enabled() or startupCheck) then return true end
      if coroutine.status(surveyWorker) == "dead" then
        startupCheck = false
        orientationSurvey = nil
        if callSucceeded and surveyedRotation ~= nil then
          if rotation ~= surveyedRotation then
            generation = generation + 1; covered = 0; firstRobotPosition = nil; urgentMask, urgentVisited = 0, 0
          end
          rotation = surveyedRotation
        end
        dockError = not callSucceeded and tostring(surveyedRotation):sub(1, 96) or scanError
        if rotation == nil then orientationRetryAt = deps.now() + 3 end
      end
      return true
    end
    if rotation == nil then return false end
    if robotRequest then
      local request = robotRequest
      if not robotSearchWorker then
        robotSearchWorker = coroutine.create(function()
          return StationObservation.findRobot(function(x, y, z)
            local callSucceeded, sensorResult, scanError = scanSensor(x, y, z)
            local name = callSucceeded and scanError == nil and type(sensorResult) == "table" and
                type(sensorResult.block) == "table" and sensorResult.block.name
            sensorResult = nil
            coroutine.yield()
            if type(name) ~= "string" then error("ROBOT_SCAN_UNREADABLE", 0) end
            return { block = { name = name } }
          end, rotation, firstRobotPosition)
        end)
      end
      local surveyWorker = robotSearchWorker
      local callSucceeded, workerResult = coroutine.resume(surveyWorker)
      if robotSearchWorker ~= surveyWorker or not deps.enabled() then return true end
      if coroutine.status(surveyWorker) == "dead" then
        robotRequest = nil; robotSearchWorker = nil
        if callSucceeded and not firstRobotPosition then
          firstRobotPosition = { x = workerResult.x, z = workerResult.z, boot = request.boot }
        else
          firstRobotPosition = nil
        end
        emit({
          kind = "ROBOT_POSITION",
          id = request.id,
          boot = request.boot,
          x = callSucceeded and workerResult.x or nil,
          y = callSucceeded and workerResult.y or nil,
          z = callSucceeded and workerResult.z or nil,
          error = not callSucceeded and tostring(workerResult):sub(1, 48) or nil
        })
      end
      return true
    end
    if #requests > 0 and (not activeScan or (not activeScan.request and not activeScan.retry)) then
      local scanRequest = table.remove(requests, 1); activeScan = { cell = scanRequest.cell, request = scanRequest, y = 0 }
    end
    if not activeScan then
      local cell = choose(deps.now()); if not cell then return false end
      activeScan = { cell = cell, y = 0 }
    end
    local scanJob, startedCancellationRevision = activeScan, scanCancellationRevision
    local x, _, z = StationObservation.coordinates(scanJob.cell)
    x, z = rotate(x, z, rotation)
    local callSucceeded, sensorResult, scanError = scanSensor(x, scanJob.y, z)
    scanCount = scanCount + 1
    if scanCancellationRevision ~= startedCancellationRevision or not deps.enabled() then return true end
    local observedCell, category
    if callSucceeded and scanError == nil and sensorResult ~= nil and sensorResult ~= false then
      observedCell, scanError = StationObservation.normalize(sensorResult)
      if not observedCell.scanOk then category = "OBS_DATA_INVALID" end
    else
      category = "SENSOR_UNAVAILABLE"
      if not callSucceeded then scanError = tostring(sensorResult):sub(1, 96) end
    end
    sensorResult = nil
    if scanJob.y == -1 and observedCell and observedCell.scanOk then
      scanJob.surface.soil = observedCell.block; observedCell = scanJob.surface
    end
    if not observedCell or not observedCell.scanOk then
      lastError = tostring(scanError or "SCAN_UNREADABLE"):sub(1, 96)
      lastErrorCategory, lastErrorCell = category, scanJob.cell
      if not scanJob.retry then
        scanJob.retry = true; scanJob.retryCategory = category; scanJob.retryError = lastError
        retryCount = retryCount + 1; return true
      end
      if category ~= scanJob.retryCategory then
        category = "OBS_DATA_INVALID"
        lastError = ("MIXED_FAILURE: " .. scanJob.retryError .. " -> " .. lastError):sub(1, 96)
        lastErrorCategory = category
      end
      local cellFacts = cells[scanJob.cell]
      if urgentMask == 0 then urgentVisited = 0 end
      urgentMask = urgentMask & ~(1 << (scanJob.cell - 1))
      urgentVisited = urgentVisited | (1 << (scanJob.cell - 1))
      local wasCovered = cellFacts.generation == generation and
          (cellFacts.scanOk or cellFacts.errorCategory == "OBS_DATA_INVALID")
      if cellFacts.scanOk or not wasCovered then
        cellFacts.lastGoodKind = cellFacts.scanOk and cellFacts.kind or nil
        cellFacts.kind = "UNREADABLE"; cellFacts.version = cellFacts.version + 1
        planningRevision = planningRevision + 1
      end
      cellFacts.scanOk = false
      cellFacts.failedAt = deps.now(); cellFacts.error = lastError
      cellFacts.errorCategory = category; cellFacts.failureGeneration = generation
      if category == "OBS_DATA_INVALID" then
        if not wasCovered then covered = covered + 1 end
        cellFacts.generation = generation; cellFacts.seenAt = deps.now()
      end
      failureCount = failureCount + 1
      if category == "SENSOR_UNAVAILABLE" then
        generation = generation + 1; covered = 0; urgentMask, urgentVisited = 0, 0
        if rotation ~= nil then
          rotation = nil; orientationRetryAt = deps.now() + 3; dockError = "SENSOR_UNAVAILABLE"
          api.resetRobot()
        end
      end
      result(scanJob, false, lastError, category); activeScan = nil; return true
    end
    scanJob.retry = nil
    local cellFacts = cells[scanJob.cell]
    if scanJob.y == 0 and (observedCell.kind == "AIR" or
          scanJob.request and scanJob.request.reason == "ADMISSION_SOIL") and
        not (scanJob.request and scanJob.request.reason == "ACTION_VERIFY") and
        (scanJob.request or cellFacts.generation ~= generation) then
      scanJob.surface = observedCell; scanJob.y = -1; return true
    end
    observedCell.soilChecked = scanJob.y == -1
    if scanJob.y == 0 then
      observedCell.soil = cellFacts.soil
    end
    if observedCell.kind == "AIR" and observedCell.soil and observedCell.soil ~= "minecraft:farmland" then
      observedCell.kind = "OBSTRUCTED"
    end
    local code = StationObservation.change(cellFacts, observedCell)
    if urgentMask == 0 then urgentVisited = 0 end
    urgentMask = urgentMask & ~(1 << (scanJob.cell - 1))
    urgentVisited = urgentVisited | (1 << (scanJob.cell - 1))
    if code == "DANGEROUS" then
      local row, column = math.floor((scanJob.cell - 1) / 6), (scanJob.cell - 1) % 6
      if row > 0 then urgentMask = urgentMask | (1 << (scanJob.cell - 7)) end
      if row < 5 then urgentMask = urgentMask | (1 << (scanJob.cell + 5)) end
      if column > 0 then urgentMask = urgentMask | (1 << (scanJob.cell - 2)) end
      if column < 5 then urgentMask = urgentMask | (1 << scanJob.cell) end
      urgentMask = urgentMask & ~urgentVisited
    end
    local previouslyCovered = cellFacts.generation == generation and
        (cellFacts.scanOk or cellFacts.errorCategory == "OBS_DATA_INVALID")
    observedCell.cell, observedCell.version = scanJob.cell, cellFacts.version + (code and 1 or 0)
    local surveyCovered = previouslyCovered or
        not (scanJob.y == 0 and observedCell.block == "minecraft:air" and scanJob.request and scanJob.request.reason == "ACTION_VERIFY")
    observedCell.seenAt, observedCell.generation = deps.now(), surveyCovered and generation or nil
    cells[scanJob.cell] = observedCell
    if code or (not previouslyCovered and surveyCovered) then
      planningRevision = planningRevision + 1
    end
    if not previouslyCovered and surveyCovered then covered = covered + 1 end
    result(scanJob, true); activeScan = nil; return true
  end

  function api.status(terrainCrop)
    local dangers, dataInvalid, sensorInvalid, emptySticks = 0, 0, 0, 0
    local sampledAt = deps.now()
    local oldestAge, oldestCell
    local overdue, maxLateness, unseen, unreadable = 0, 0, 0, 0
    local humidityWeight, nutrientWeight, airWeight
    local terrain
    if terrainCrop then
      humidityWeight, nutrientWeight, airWeight = require("station_catalog").terrainWeights(terrainCrop)
      if humidityWeight then terrain = { crop = terrainCrop, known = 0 } end
    end
    for _, cellFacts in pairs(cells) do
      if cellFacts.danger then dangers = dangers + 1 end
      if cellFacts.scanOk and cellFacts.tile and (cellFacts.kind == "SINGLE" or cellFacts.kind == "DOUBLE") then
        emptySticks = emptySticks + 1
      end
      if cellFacts.errorCategory == "OBS_DATA_INVALID" then dataInvalid = dataInvalid + 1 end
      if cellFacts.errorCategory == "SENSOR_UNAVAILABLE" then sensorInvalid = sensorInvalid + 1 end
      if not cellFacts.scanOk then unreadable = unreadable + 1 end
      if cellFacts.generation ~= generation then
        unseen = unseen + 1
      elseif cellFacts.scanOk and cellFacts.seenAt then
        if terrain then
          local humidity, nutrients, airQuality = cellFacts.terrainH, cellFacts.terrainN, cellFacts.terrainA
          if not (humidity == -1 and nutrients == -1 and airQuality == -1) then
            if humidity ~= nil then
              terrain.humidityMin = math.min(terrain.humidityMin or humidity, humidity)
              terrain.humidityMax = math.max(terrain.humidityMax or humidity, humidity)
            end
            if nutrients ~= nil then
              terrain.nutrientsMin = math.min(terrain.nutrientsMin or nutrients, nutrients)
              terrain.nutrientsMax = math.max(terrain.nutrientsMax or nutrients, nutrients)
            end
            if airQuality ~= nil then
              terrain.airMin = math.min(terrain.airMin or airQuality, airQuality)
              terrain.airMax = math.max(terrain.airMax or airQuality, airQuality)
            end
            if humidity ~= nil and nutrients ~= nil and airQuality ~= nil then
              local quality = require("station_catalog").terrainQuality(humidity, nutrients, airQuality,
                humidityWeight, nutrientWeight, airWeight)
              terrain.known = terrain.known + 1
              terrain.qualityMin = math.min(terrain.qualityMin or quality, quality)
              terrain.qualityMax = math.max(terrain.qualityMax or quality, quality)
            end
          end
        end
        local age = math.max(0, sampledAt - cellFacts.seenAt)
        local _, interval = priority(cellFacts)
        if not oldestAge or age > oldestAge or age == oldestAge and cellFacts.cell < oldestCell then
          oldestAge, oldestCell = age, cellFacts.cell
        end
        if age > interval then
          overdue = overdue + 1; maxLateness = math.max(maxLateness, age - interval)
        end
      end
    end
    return {
      ready = covered == 36,
      covered = covered,
      terrain = terrain,
      sensorAvailable = sensorAvailable,
      queueFault = queueFault,
      rotation = rotation,
      dockError = dockError,
      requests = #requests + (activeScan and activeScan.request and 1 or 0),
      events = eventCount,
      dangers = dangers,
      emptySticks = emptySticks,
      scans = scanCount,
      retries = retryCount,
      failures = failureCount,
      lastError = lastError,
      lastErrorCategory = lastErrorCategory,
      lastErrorCell = lastErrorCell,
      dataInvalid = dataInvalid,
      sensorInvalid = sensorInvalid,
      revision = planningRevision,
      sampledAt = sampledAt,
      oldestAge = oldestAge,
      oldestCell = oldestCell,
      overdue = overdue,
      maxLateness = maxLateness,
      unseen = unseen,
      unreadable = unreadable
    }
  end

  return api
end

return StationObservation
