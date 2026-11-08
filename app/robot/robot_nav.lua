local RobotNavigation = {}
local function integer(value, minimum, maximum)
  return type(value) == "number" and value % 1 == 0 and value >= minimum and
      value <= maximum
end
function RobotNavigation.coordinates(cell)
  if cell == 0 then return 0, 0, -1 end
  if not integer(cell, 1, 36) then return nil, "INVALID_CELL" end
  return -((cell - 1) % 6 + 1), 1, math.floor((cell - 1) / 6) - 3
end

function RobotNavigation.route(sourceCell, targetCell, heading)
  local x, _, z = RobotNavigation.coordinates(sourceCell); local targetX, _, targetZ = RobotNavigation.coordinates(
    targetCell)
  if not x or not targetX then return nil, "INVALID_CELL" end
  local routeCells = {}
  if sourceCell == targetCell then return routeCells end
  local function move(nextX, nextZ)
    x, z = nextX, nextZ; routeCells[#routeCells + 1] = x == 0 and 0 or (z + 3) * 6 - x
  end
  if sourceCell == 0 and targetCell ~= 0 then move(-1, -1) end
  local goalX = targetCell == 0 and -1 or targetX
  local function alongX()
    while x ~= goalX do move(x + (goalX > x and 1 or -1), z) end
  end
  local function alongZ()
    while z ~= targetZ do move(x, z + (targetZ > z and 1 or -1)) end
  end
  local xFirst = false
  if sourceCell ~= 0 and targetCell ~= 0 and heading ~= nil and x ~= goalX and z ~= targetZ then
    local function turns(targetHeading)
      local difference = (targetHeading - heading) % 4
      return math.min(difference, 4 - difference)
    end
    xFirst = turns(goalX < x and 0 or 2) < turns(targetZ < z and 1 or 3)
  end
  if xFirst then
    alongX(); alongZ()
  else
    alongZ(); alongX()
  end
  if targetCell == 0 and x ~= 0 then move(0, -1) end
  return routeCells
end

local headingDeltaX, headingDeltaZ = { -1, 0, 1, 0 }, { 0, -1, 0, 1 }
function RobotNavigation.new(deps)
  local robotHardware = deps.robot
  local cell, heading, routeCells, routeIndex, localizationProgress = nil, nil, nil, 1, nil
  local homeElevated = false
  local destination
  local retryAt
  local now = deps.now
  local api = {}
  local stopReason
  function api.invalidate(reason)
    cell, heading, routeCells, localizationProgress = nil, nil, nil, nil
    homeElevated = false; retryAt = nil
    stopReason = reason
    return nil, "UNKNOWN", reason or "POSITION_UNCERTAIN"
  end

  function api.energy()
    local callSucceeded, currentEnergy, maximumEnergy = pcall(function() return deps.energy(), deps.maxEnergy() end)
    if not callSucceeded or type(currentEnergy) ~= "number" or type(maximumEnergy) ~= "number" or not (maximumEnergy > 0 and maximumEnergy < math.huge) or
        not (currentEnergy >= 0 and currentEnergy <= maximumEnergy) then
      return nil, "ENERGY_UNREADABLE"
    end
    local energyRatio = currentEnergy / maximumEnergy
    return energyRatio, energyRatio <= 0.40 and "ENERGY_RETURN" or nil
  end

  function api.workReady()
    if cell == nil or heading == nil or routeCells or localizationProgress or stopReason then
      return nil,
          "POSITION_UNCERTAIN"
    end
    return true
  end

  function api.localize()
    if cell or routeCells or localizationProgress then return nil, "BUSY" end
    localizationProgress = { phase = "START", attempts = 0 }; stopReason = nil
    return true
  end

  function api.positionNeeded()
    return localizationProgress ~= nil and
        (localizationProgress.phase == "START" or localizationProgress.phase == "OBSERVE")
  end

  function api.position(x, y, z, operationError)
    if not api.positionNeeded() then return nil, "POSITION_NOT_REQUESTED" end
    if operationError then return api.invalidate(operationError) end
    if not integer(x, -7, 1) or not integer(y, 0, 1) or not integer(z, -4, 3) then
      return api.invalidate("POSITION_INVALID")
    end
    local probeProgress = localizationProgress
    if probeProgress.phase == "START" then
      local observedCell
      if x == 0 and z == -1 then
        observedCell = 0
      elseif y == 1 and x >= -6 and x <= -1 and z >= -3 and z <= 2 then
        observedCell = (z + 3) * 6 - x
      end
      if observedCell == nil then return api.invalidate("POSITION_UNSUPPORTED") end
      probeProgress.x, probeProgress.y, probeProgress.z, probeProgress.cell = x, y, z, observedCell
      probeProgress.phase = y == 0 and "UP" or "FORWARD"
    else
      if y ~= 1 then return api.invalidate("PROBE_DISPLACEMENT_INVALID") end
      for headingIndex = 1, 4 do
        if x - probeProgress.x == headingDeltaX[headingIndex] and z - probeProgress.z == headingDeltaZ[headingIndex] then
          probeProgress.heading =
              headingIndex - 1
        end
      end
      if probeProgress.heading == nil then return api.invalidate("PROBE_DISPLACEMENT_INVALID") end
      probeProgress.phase = "BACK"
    end
    return true
  end

  function api.snapshot()
    local trusted = cell ~= nil and heading ~= nil and localizationProgress == nil
    return {
      cell = cell,
      heading = heading,
      trusted = trusted,
      moving = routeCells ~= nil or localizationProgress ~= nil,
      localizing = localizationProgress ~= nil,
      returningFromProbe = localizationProgress ~= nil and
          (localizationProgress.phase == "BACK" or localizationProgress.phase == "DOWN"),
      atHome = trusted and cell == 0 and not homeElevated,
      aboveHome = trusted and cell == 0 and homeElevated,
      returning = routeCells ~= nil and destination == 0,
      stopped = stopReason,
      waitingForObstacle = retryAt ~= nil and now() < retryAt
    }
  end

  function api.begin(target)
    if not RobotNavigation.coordinates(target) then return nil, "INVALID_CELL" end
    if not cell or (homeElevated and stopReason and target ~= 0) then return nil, "POSITION_UNCERTAIN" end
    if routeCells or localizationProgress then return nil, "BUSY" end
    routeCells, routeIndex, stopReason = RobotNavigation.route(cell, target, heading), 1, nil
    retryAt = nil
    destination = target
    return true
  end

  function api.face(targetHeading)
    if not cell or routeCells or localizationProgress or homeElevated or not integer(targetHeading, 0, 3) then
      return nil,
          "POSITION_UNCERTAIN"
    end
    if heading == targetHeading then return true end
    local turnRight = (targetHeading - heading) % 4 ~= 3
    local callSucceeded, turned = pcall(turnRight and robotHardware.turnRight or robotHardware.turnLeft)
    if not callSucceeded or turned ~= true then return api.invalidate("TURN_UNCERTAIN") end
    heading = (heading + (turnRight and 1 or -1)) % 4
    return heading == targetHeading
  end

  local function move(movementMethod, unknownEffectReason)
    local callSucceeded, moved, operationError = pcall(movementMethod)
    if callSucceeded and moved == true and operationError == nil then return true end
    if callSucceeded and moved == nil then
      if operationError == "solid" or operationError == "entity" or operationError == "passable" then
        return false,
            "ROUTE_OBSTRUCTED"
      end
      if operationError == "impossible move" then return false, "MOVE_IMPOSSIBLE" end
      if operationError == "not enough energy" then return false, "ENERGY_CRITICAL" end
    end
    return nil, unknownEffectReason
  end
  local function blocked(reason)
    routeCells = nil; stopReason = reason
    return nil, "BLOCKED", reason
  end
  function api.step()
    if localizationProgress then
      local probeProgress = localizationProgress
      if api.positionNeeded() then return false, "WAIT_POSITION" end
      if probeProgress.phase == "TURN" then
        local callSucceeded, turned, turnError = pcall(robotHardware.turnRight)
        if not callSucceeded or turned ~= true or turnError ~= nil then return api.invalidate("TURN_UNCERTAIN") end
        probeProgress.phase = "FORWARD"
        return false, "RUNNING"
      end
      local operation = ({ UP = robotHardware.up, FORWARD = robotHardware.forward, BACK = robotHardware.back, DOWN = robotHardware.down })
          [probeProgress.phase]
      local moved, reason = move(operation, "LOCALIZATION_MOVE_UNCERTAIN")
      if moved == nil then return api.invalidate(reason) end
      if not moved then
        if probeProgress.phase == "FORWARD" and reason == "ROUTE_OBSTRUCTED" then
          probeProgress.attempts = probeProgress.attempts + 1
          if probeProgress.attempts == 4 then return api.invalidate("LOCALIZATION_BLOCKED") end
          probeProgress.phase = "TURN"; return false, "RUNNING"
        end
        return api.invalidate(reason)
      end
      if probeProgress.phase == "UP" then
        probeProgress.phase = "FORWARD"
      elseif probeProgress.phase == "FORWARD" then
        probeProgress.phase = "OBSERVE"
      elseif probeProgress.phase == "BACK" and probeProgress.y == 0 then
        probeProgress.phase = "DOWN"
      else
        cell, heading, homeElevated = probeProgress.cell, probeProgress.heading,
            probeProgress.cell == 0 and probeProgress.y == 1
        localizationProgress = nil; stopReason = nil
        return true, "DONE"
      end
      return false, "RUNNING"
    end
    if not routeCells then return nil, "BLOCKED", "NO_ROUTE" end
    if retryAt then
      if now() < retryAt then return false, "WAIT_OBSTACLE" end
      retryAt = nil
    end
    local function retryObstacle(reason)
      if reason ~= "ROUTE_OBSTRUCTED" then return false end
      retryAt = now() + 1
      return true
    end
    local target = routeCells[routeIndex]
    if not target then
      if cell == 0 and homeElevated then
        local moved, reason = move(robotHardware.down, "HOME_DOWN_UNCERTAIN")
        if moved == nil then return api.invalidate(reason) end
        if not moved then
          if retryObstacle(reason) then return false, "WAIT_OBSTACLE" end
          return blocked(reason)
        end
        homeElevated = false
      end
      routeCells = nil
      return true, "DONE"
    end
    if cell == 0 and not homeElevated then
      local moved, reason = move(robotHardware.up, "HOME_UP_UNCERTAIN")
      if moved == nil then return api.invalidate(reason) end
      if not moved then
        if retryObstacle(reason) then return false, "WAIT_OBSTACLE" end
        return blocked(reason)
      end
      homeElevated = true
      return false, "RUNNING"
    end
    local x, _, z = RobotNavigation.coordinates(cell); local targetX, _, targetZ = RobotNavigation.coordinates(target)
    local targetHeading
    for headingIndex = 1, 4 do
      if targetX - x == headingDeltaX[headingIndex] and targetZ - z == headingDeltaZ[headingIndex] then
        targetHeading =
            headingIndex - 1
      end
    end
    if targetHeading == nil then return api.invalidate("INVALID_ROUTE") end
    if targetHeading ~= heading then
      local turnRight = (targetHeading - heading) % 4 ~= 3
      local callSucceeded, turned = pcall(turnRight and robotHardware.turnRight or robotHardware.turnLeft)
      if not callSucceeded or turned ~= true then return api.invalidate("TURN_UNCERTAIN") end
      heading = (heading + (turnRight and 1 or -1)) % 4
      return false, "RUNNING"
    end
    local moved, reason = move(robotHardware.forward, "MOVE_UNCERTAIN")
    if moved == nil then return api.invalidate(reason) end
    if not moved then
      if retryObstacle(reason) then return false, "WAIT_OBSTACLE" end
      return blocked(reason)
    end
    cell = target; routeIndex = routeIndex + 1
    homeElevated = cell == 0
    if not routeCells[routeIndex] and not homeElevated then
      routeCells = nil
      return true, "DONE"
    end
    return false, "RUNNING"
  end

  return api
end

return RobotNavigation
