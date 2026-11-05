local RobotUI = {}
local activities = {
  REMOVE_WEED = "Removing a weed",
  COLLECT_AND_CLEAR_CELL = "Collecting and clearing a cell",
  COLLECT_AND_RESTORE_DOUBLE = "Collecting and preparing a cell",
  EXTRACT_AND_PLANT = "Extracting seeds and planting",
  PLANT_SEED = "Planting seeds",
  PLACE_DOUBLE_STICKS = "Preparing a planting site",
}

function RobotUI.message(view)
  local navigation, inventory = view.navigation or {}, view.io or {}
  if not view.hardwareAvailable then
    return "Robot equipment is unavailable", "Check the robot's equipment.", "Restart the program after checking."
  end
  if inventory.fault then
    return "Inventory needs checking", "Stop Station and inspect the robot", "and exchange chest before restarting."
  end
  if view.localizationFailed then
    return "Cannot determine my position", "Check the robot's position.", "Restart the program after checking."
  end
  if navigation.stopped then
    if navigation.stopped == "ENERGY_CRITICAL" then
      return "Not enough power to move", "Stop Station and charge the robot.", "Check its position before restarting."
    end
    return "Movement needs checking", "Stop Station and check my position.", "Restart the program after checking."
  end
  if navigation.waitingForObstacle then
    return "The path is blocked", "Remove the obstacle.", "I will continue automatically."
  end
  if view.actionRunning then
    local cells
    if view.actionFrom and view.actionFrom > 0 then
      cells = string.format("From cell %02d to cell %02d", view.actionFrom, view.actionTo)
    elseif view.actionTo then
      cells = string.format("Cell %02d", view.actionTo)
    end
    return activities[view.actionName] or "Working", cells or "", ""
  end
  if navigation.returningFromProbe then return "Returning after locating myself", "", "" end
  if inventory.phase == "EXCHANGING" then return "Exchanging supplies and collected items", "", "" end
  if navigation.returning then return "Returning home", "", "" end
  if inventory.phase == "ROUTING" then return "Moving to exchange supplies", "", "" end
  if view.actionResult == "UNKNOWN" then
    return "Could not confirm the operation result", "Check the current status on Station.", ""
  end
  if view.advertising then
    return "Select this robot on Station", "Pairing code: " .. view.code, ""
  end
  if view.linkError then
    return "The saved connection needs checking", "Check the robot's disk and restart.", "Use P to pair again if needed."
  end
  if view.waitingForStation then return "Waiting for Station", "Check Station and the wireless connection.", "" end
  if inventory.awaitingAck then return "Waiting for Station to confirm the exchange", "", "" end
  if not view.enabled then return "Work is stopped", "Press START on Station to continue.", "" end
  if navigation.localizing then return "Determining my position", "", "" end
  if inventory.phase == "REQUESTED" then return "Waiting for Station to allow the exchange", "", "" end
  if inventory.inventoryWaiting then
    if inventory.inventoryWaiting == "NORMALIZE_INVENTORY_SPACE" then
      return "Waiting for inventory space", "Free a slot in the robot's inventory.", "I will continue automatically."
    end
    return "Checking my inventory", "Waiting to complete the inventory check.", "I will try again automatically."
  end
  if not inventory.normalized and view.io then return "Checking my inventory", "", "" end
  if inventory.busy then return "Checking my inventory", "", "" end
  if inventory.serviceRetrySuppressed and inventory.failure then
    return "Could not finish exchanging items", "Check chest space and supplies on Station.",
        "I will try again automatically."
  end
  if view.energyIssue == "ENERGY_UNREADABLE" then
    return "Cannot read the power level", "Check the robot's equipment if this persists.", ""
  end
  if view.energyIssue then return "Waiting for enough power", "", "" end
  if inventory.waitingForSticks then return "Waiting for supplies", "Check the supply stock on Station.", "" end
  if view.actionResult == "BLOCKED" then
    return "Could not finish the operation", "Check the field and robot.", "See Station for the current work status."
  end
  return "Ready for work", "Waiting for a task from Station.", ""
end

function RobotUI.new(display)
  local previousLines = {}
  local previousWidth, previousHeight
  local api = {}
  function api.draw(view, confirmation, notice)
    local width, height = display.size()
    width, height = math.min(width, 50), math.min(height, 16)
    if width ~= previousWidth or height ~= previousHeight then
      display.clear(); previousLines = {}; previousWidth, previousHeight = width, height
    end
    local activity, explanation, instruction = RobotUI.message(view)
    if confirmation then
      activity, explanation, instruction = "Change robot pairing?", "Remove this robot's saved connection.", ""
    end
    local lines = { "CropAutomation Robot", "", activity, explanation, instruction, "", notice or "", "",
      confirmation and "Y confirm   Any other key cancel" or "P - pairing   Q - exit" }
    for row = 1, math.min(#lines, height - 1) do
      local line = lines[row]:sub(1, width - 1)
      if previousLines[row] ~= line then
        display.line(row, line .. string.rep(" ", width - 1 - #line))
        previousLines[row] = line
      end
    end
  end

  return api
end

return RobotUI
