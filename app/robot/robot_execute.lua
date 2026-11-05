local RobotExecute = {}
function RobotExecute.new(deps)
  local navigation, robotHardware, inventoryController = deps.nav, deps.robot, deps.inventory
  local inventoryAccess = robotHardware.inventoryAccess
  local actionWorker, actionResult
  local handParked, waitingForInventory = false, false
  local robotInventory, hand
  local api = {}
  local function waitInventory()
    waitingForInventory = true; coroutine.yield()
  end
  function api.attachInventory(executionResult)
    robotInventory = executionResult
    hand = require("robot_hand").new({
      inventoryAccess = inventoryAccess,
      inventory = inventoryController,
      inventoryMap = robotInventory,
      wait = waitInventory
    })
  end

  local function call(componentMethod, ...)
    local callResults = table.pack(pcall(componentMethod, ...))
    coroutine.yield()
    if not callResults[1] then error("API_EXCEPTION", 0) end
    return table.unpack(callResults, 2, callResults.n)
  end
  local function trySelect(slot)
    local success, selectedSlot = inventoryAccess.selectSlot(slot)
    if not success then return nil end
    return selectedSlot
  end
  local function select(slot)
    while true do
      local selectedSlot = trySelect(slot)
      if selectedSlot == slot or not handParked then return selectedSlot end
      waitingForInventory = true; coroutine.yield()
    end
  end
  local function empty(slot)
    local observedVersion = robotInventory.version(slot)
    local success, itemCount, operationError = pcall(robotHardware.count, slot)
    if not success or operationError ~= nil or type(itemCount) ~= "number" or itemCount % 1 ~= 0 or itemCount < 0 or itemCount > 64 then
      return nil, "INVENTORY_UNREADABLE"
    end
    if observedVersion ~= robotInventory.version(slot) then return nil, "INVENTORY_CHANGED" end
    if itemCount == 0 then robotInventory.observed(slot, nil, observedVersion) end
    return itemCount == 0
  end
  local function read(slot)
    while true do
      local observedVersion = robotInventory.version(slot)
      local valid, inventoryStack = inventoryAccess.readStack(slot)
      if valid then
        robotInventory.observed(slot, inventoryStack, observedVersion); return inventoryStack
      end
      if not handParked then return nil, "INVENTORY_UNREADABLE" end
      waitingForInventory = true; coroutine.yield()
    end
  end
  local function finish(status, reason) return { status = status, reason = reason } end
  local function interactionFailure(result, reason)
    if result == true then return end
    if result == false or result == nil then return finish("BLOCKED", reason) end
    return finish("UNKNOWN", "FIELD_RESPONSE_INVALID")
  end
  function api.accept(name, sourceCell, targetCell, placementVariant, emergency)
    if actionWorker then return nil, "BUSY" end
    local LinkProtocol = require("shared_link")
    if not LinkProtocol.parameters(name, sourceCell, targetCell, placementVariant) or
        not LinkProtocol.priority(name, emergency) then
      return nil, "INVALID_ACTION"
    end
    actionResult = nil
    handParked, waitingForInventory = false, false
    actionWorker = coroutine.create(function()
      if not robotInventory or not robotInventory.isNormalized() then return finish("BLOCKED", "INVENTORY_NOT_READY") end
      local replant = name == "EXTRACT_AND_PLANT"
      local restoreAfterCollection = name == "COLLECT_AND_RESTORE_DOUBLE"
      local weedWork = name == "REMOVE_WEED"
      local requiredStickCount = LinkProtocol.sticks(name, placementVariant)
      if not emergency and robotInventory.freeSlots() < 4 then return finish("BLOCKED", "INVENTORY_SPACE") end
      if requiredStickCount > 0 then
        local stack, operationError = read(15)
        if operationError then return finish("BLOCKED", "INVENTORY_UNREADABLE") end
        if not stack or stack.name ~= "ic2:crop_stick" or stack.size < requiredStickCount then
          return finish("BLOCKED", "MISSING_CROP_STICKS")
        end
      end
      local handStorageSlot, parkedHand = 14
      while true do
        local stored, heldStack = hand.park()
        if stored then
          parkedHand = heldStack; break
        end
        local occupiedStack, operationError = read(handStorageSlot)
        if operationError then return finish("BLOCKED", operationError) end
        if occupiedStack then
          robotInventory.requestCargoService()
          return finish("BLOCKED", "INVENTORY_SPACE")
        end
        waitInventory()
      end
      handParked = true
      local plantingSlot
      local seedBagUsed = false
      local extractionAttempted = false
      local function fieldFailure(reason) return finish(replant and "BLOCKED" or "UNKNOWN", reason) end
      local function useWorkingItem(slot, expected, maximumConsumed, failureReason)
        hand.equip(slot, expected)
        local workReady, workReason = navigation.workReady()
        if not workReady then return fieldFailure(workReason) end
        hand.allowConsumption(maximumConsumed)
        return interactionFailure(call(robotHardware.useDown), failureReason)
      end
      local function cargoSlot()
        local lastError
        for slot = 1, 13 do
          if not robotInventory.peek(slot) then
            local slotEmpty, operationError = empty(slot)
            if operationError then lastError = operationError end
            if slotEmpty then
              if trySelect(slot) == slot then return slot end
              lastError = "SELECT_FAILED"
            end
            coroutine.yield()
          end
        end
        return nil, lastError or "INVENTORY_SPACE"
      end
      local function navigate(cell)
        local accepted, reason = navigation.begin(cell)
        if not accepted then return finish("BLOCKED", reason) end
        while true do
          local done, outcome, movementReason = navigation.step()
          if done then break end
          if done == nil then return finish(outcome, movementReason) end
          coroutine.yield()
        end
        if not navigation.snapshot().trusted then return finish("UNKNOWN", "POSITION_UNCERTAIN") end
        local workReady, reason = navigation.workReady()
        if not workReady then return finish("BLOCKED", reason) end
      end
      local function collectCell(selectPlantingMaterial)
        local emptySlots = 0
        if selectPlantingMaterial then
          for slot = 1, 13 do
            local slotEmpty = empty(slot)
            if slotEmpty then emptySlots = emptySlots | (1 << slot) end
          end
        end
        local slot, reason = cargoSlot()
        if not slot then return finish("BLOCKED", reason) end
        local workReady, workReason = navigation.workReady()
        if not workReady then return finish("BLOCKED", workReason) end
        extractionAttempted = true
        local interactionError = interactionFailure(call(robotHardware.swingDown), "SWING_REFUSED")
        if interactionError then return interactionError end
        local _, readError = read(slot)
        if readError then return fieldFailure(readError) end
        for _ = 1, 13 do
          slot, reason = cargoSlot()
          if not slot then
            if reason == "INVENTORY_SPACE" then break end
            return fieldFailure(reason)
          end
          workReady, workReason = navigation.workReady()
          if not workReady then return finish("UNKNOWN", workReason) end
          local pickupResult = call(robotHardware.suckDown, 1)
          local receivedStack, readError = read(slot)
          if readError then return fieldFailure(readError) end
          if pickupResult == false and not receivedStack then break end
          if (pickupResult ~= true and not (type(pickupResult) == "number" and pickupResult > 0)) or not receivedStack then
            return fieldFailure("PICKUP_UNCERTAIN")
          end
        end
        if selectPlantingMaterial then
          local plantingItems = 0
          for slot = 1, 13 do
            if (emptySlots & (1 << slot)) ~= 0 then
              local slotEmpty, reason = empty(slot)
              if reason then return fieldFailure(reason) end
              if not slotEmpty then
                local stack, readError = read(slot)
                if readError then return fieldFailure(readError) end
                if stack and LinkProtocol.plantingItem(stack.name) then
                  plantingItems = plantingItems + 1; plantingSlot = slot
                end
              end
            end
          end
          if plantingItems ~= 1 then
            plantingSlot = nil
            return finish("BLOCKED",
              plantingItems == 0 and "EXTRACT_AND_PLANT_NO_SEED" or "EXTRACT_AND_PLANT_AMBIGUOUS_SEED")
          end
        end
      end
      local function preparePlanting()
        local material, reason = read(plantingSlot)
        if reason then return finish("BLOCKED", reason) end
        if not material or not LinkProtocol.plantingItem(material.name) then
          return finish("BLOCKED",
            "MISSING_PLANTING_ITEM")
        end
        if material.name == "ic2:crop_seed_bag" and material.size > 1 then
          local remainderSlot, remainderError = cargoSlot()
          if not remainderSlot then return finish("BLOCKED", remainderError) end
          if select(plantingSlot) ~= plantingSlot then return finish("BLOCKED", "SELECT_FAILED") end
          local transferred = call(robotHardware.transferTo, remainderSlot, material.size - 1)
          local sourceAfter, sourceError = read(plantingSlot)
          local unusedBags, unusedError = read(remainderSlot)
          if transferred ~= true or sourceError or unusedError or not sourceAfter or sourceAfter.name ~= material.name or
              sourceAfter.size ~= 1 or not unusedBags or unusedBags.name ~= material.name or unusedBags.size ~= material.size - 1 then
            return finish("UNKNOWN", "PLANT_MATERIAL_TRANSFER_UNCERTAIN")
          end
        end
        local sticks, readError = read(15)
        if readError then return finish("BLOCKED", readError) end
        if not sticks or sticks.name ~= "ic2:crop_stick" or sticks.size < 1 then
          return finish("BLOCKED",
            "MISSING_CROP_STICKS")
        end
        return nil, sticks
      end
      local function plant(materialPrepared)
        local sticks
        if not materialPrepared then
          local preparation
          preparation, sticks = preparePlanting()
          if preparation then return preparation end
        else
          local readError
          sticks, readError = read(15)
          if readError then return finish("BLOCKED", readError) end
          if not sticks or sticks.name ~= "ic2:crop_stick" or sticks.size < 1 then
            return finish("BLOCKED",
              "MISSING_CROP_STICKS")
          end
        end
        if select(15) ~= 15 then return finish("BLOCKED", "SELECT_FAILED") end
        local workReady, workReason = navigation.workReady()
        if not workReady then return finish("BLOCKED", workReason) end
        local interactionError = interactionFailure(call(robotHardware.placeDown), "PLACE_REFUSED")
        if interactionError then return interactionError end
        local remainingSticks, readError = read(15)
        if readError or (remainingSticks and (remainingSticks.name ~= "ic2:crop_stick" or remainingSticks.size ~= sticks.size - 1)) or
            (not remainingSticks and sticks.size ~= 1) then
          return fieldFailure("STICKS_CHANGED")
        end
        if select(plantingSlot) ~= plantingSlot then return finish("BLOCKED", "PLANT_PARTIAL_SELECT_FAILED") end
        local material, reason = read(plantingSlot)
        if reason then return fieldFailure(reason) end
        if not material or not LinkProtocol.plantingItem(material.name) then
          return finish("BLOCKED",
            "PLANT_PARTIAL_MISSING_ITEM")
        end
        workReady, workReason = navigation.workReady()
        if not workReady then return finish("BLOCKED", "PLANT_PARTIAL_" .. workReason) end
        if material.name == "ic2:crop_seed_bag" then
          local placed = call(robotHardware.placeDown)
          seedBagUsed = placed == true or replant
          local interactionError = interactionFailure(placed, "PLANT_REFUSED")
          if interactionError then return interactionError end
        else
          local useResult = useWorkingItem(plantingSlot, material, 1, "PLANT_REFUSED")
          if useResult then return useResult end
        end
        return finish("SUCCESS", "REPORTED_PLANT")
      end
      local function removeWeed()
        local tool, operationError = read(16)
        if operationError then return finish("BLOCKED", operationError) end
        if not tool or tool.name ~= "ic2:weeding_trowel" then return collectCell(false) end
        return useWorkingItem(16, tool, tool.size, "USE_REFUSED")
      end
      local function checkSticks(required)
        if required == 0 then return end
        local currentSticks, actualError = read(15)
        if actualError then return finish("BLOCKED", actualError) end
        if not currentSticks or currentSticks.name ~= "ic2:crop_stick" or currentSticks.size < required then
          return finish("BLOCKED", "MISSING_CROP_STICKS")
        end
      end
      local function restoreDouble(variant)
        local shortage = checkSticks(variant == "SINGLE" and 1 or 2)
        if shortage then return shortage end
        if select(15) ~= 15 then return finish("BLOCKED", "SELECT_FAILED") end
        local remainingSticks, readError
        if variant == "BARE_FARMLAND" then
          local interactionError = interactionFailure(call(robotHardware.placeDown), "PLACE_REFUSED")
          if interactionError then return interactionError end
        end
        remainingSticks, readError = read(15)
        if readError or not remainingSticks or remainingSticks.name ~= "ic2:crop_stick" or remainingSticks.size < 1 then
          return finish("UNKNOWN", "STICKS_CHANGED")
        end
        return useWorkingItem(15, remainingSticks, 1, "USE_REFUSED")
      end
      local succeeded, executionResult = pcall(function()
        if name == "PLANT_SEED" then
          local received = robotInventory.received()
          if not received then return finish("BLOCKED", "MISSING_PLANTING_ITEM") end
          plantingSlot = received.slot
        end
        local navigationResult = navigate(replant and sourceCell or targetCell)
        if navigationResult then return navigationResult end
        local workReady, workReason = navigation.workReady()
        if not workReady then return finish("BLOCKED", workReason) end
        local shortage = checkSticks(requiredStickCount)
        if shortage then return shortage end
        if weedWork then
          local weedResult = removeWeed()
          if weedResult then return weedResult end
          return finish("SUCCESS", "REPORTED_WEED_REMOVAL")
        end
        if name == "COLLECT_AND_CLEAR_CELL" or restoreAfterCollection or replant then
          local extractionResult = collectCell(replant)
          if extractionResult then return extractionResult end
          if name == "COLLECT_AND_CLEAR_CELL" then return finish("SUCCESS", "REPORTED_TILE_REMOVAL") end
          if restoreAfterCollection then
            local restored = restoreDouble("BARE_FARMLAND")
            if restored then return restored end
            return finish("SUCCESS", "REPORTED_DOUBLE")
          end
          navigationResult = navigate(targetCell)
          if navigationResult then return navigationResult end
          if placementVariant == "REPLACE_TILE" then
            local preparation = preparePlanting()
            if preparation then return preparation end
            local cleared = collectCell(false)
            if cleared then return cleared end
          end
          return plant(placementVariant == "REPLACE_TILE")
        end
        if name == "PLANT_SEED" then return plant() end
        local restored = restoreDouble(placementVariant == "SINGLE" and "SINGLE" or "BARE_FARMLAND")
        if restored then return restored end
        return finish("SUCCESS", "REPORTED_DOUBLE")
      end)
      local needsService, finalEquippedSlot = hand.finish(parkedHand)
      if needsService then robotInventory.requestCargoService() end
      local _, operationError = read(handStorageSlot); if operationError then return finish("UNKNOWN", operationError) end
      if not succeeded then
        return finish("UNKNOWN", executionResult == "API_EXCEPTION" and "API_EXCEPTION" or "EXECUTION_ERROR")
      end
      if plantingSlot and plantingSlot ~= finalEquippedSlot and plantingSlot ~= handStorageSlot then
        local _, readError = read(plantingSlot)
        if readError then executionResult = fieldFailure(readError) end
      end
      if seedBagUsed then
        local remainingBag = robotInventory.peek(plantingSlot)
        if remainingBag then
          if remainingBag.name ~= "ic2:crop_seed_bag" or remainingBag.size ~= 1 then
            return finish("UNKNOWN",
              "PLANT_REMAINDER_CHANGED")
          end
          robotInventory.markUsedPlantingRemainder(plantingSlot)
        end
      end
      if executionResult.status ~= "UNKNOWN" and (extractionAttempted or
            (name == "PLANT_SEED" and executionResult.status == "SUCCESS")) then
        robotInventory.releasePlanting(plantingSlot)
        if executionResult.status ~= "SUCCESS" then
          robotInventory.requestCargoService()
        end
      end
      return executionResult
    end)
    return true
  end

  function api.step()
    if not actionWorker then return actionResult end
    waitingForInventory = false
    local callSucceeded, executionResult = coroutine.resume(actionWorker)
    if not callSucceeded then
      navigation.invalidate("EXECUTION_ERROR"); actionResult = finish("UNKNOWN", "EXECUTION_ERROR"); actionWorker = nil
    elseif coroutine.status(actionWorker) == "dead" then
      actionResult = executionResult; actionWorker = nil
    end
    return actionResult
  end

  function api.busy() return actionWorker ~= nil, actionWorker ~= nil and waitingForInventory end

  return api
end

return RobotExecute
