local LinkProtocol = require("shared_link")
local RobotIO = {}
function RobotIO.new(deps)
  local robotHardware, inventoryController, navigation = deps.robot, deps.inventory, deps.nav
  local inventoryAccess = robotHardware.inventoryAccess
  local inventorySlots, dirtySlots, slotVersions = {}, {}, {}
  local slotRetryAt, reevaluateService = {}, true
  local waitingForSticks = false
  local exchangeWorker, inventoryReader, activeIoExchange, physicalFault, exchangeSequence = nil, nil, nil, nil, 0
  local inventoryNormalized, lastExchangeFailure = false, nil
  local startupSpaceBlocked = false
  local inventoryWaiting, inventoryRetryAt
  local releaseReservationsPending, ordinaryCargoNeedsService = false, false
  local retryServiceAt, failedAttempts = nil, 0
  local cancelUngrantedRequest = false
  local pendingReceipt, callId
  local highestCallSequence = 0
  local api = {}
  function api.version(slot) return slotVersions[slot] or 0 end

  function api.changed(slot)
    if not LinkProtocol.integer(slot, 1, 16) then return end
    slotVersions[slot] = api.version(slot) + 1; dirtySlots[slot] = true
    slotRetryAt[slot] = nil
  end

  function api.observed(slot, inventoryStack, observedVersion)
    local previousStack = inventorySlots[slot]
    local usedPlantingRemainder = previousStack and previousStack.usedPlantingRemainder and inventoryStack and
        previousStack.name == inventoryStack.name and previousStack.size == inventoryStack.size or nil
    local plantingReserved = previousStack and previousStack.reserved and inventoryStack and
        previousStack.name == inventoryStack.name or nil
    local stackChanged = (previousStack == nil) or (previousStack == false and inventoryStack ~= nil) or
        (previousStack and (not inventoryStack or previousStack.name ~= inventoryStack.name or previousStack.size ~= inventoryStack.size))
    inventorySlots[slot] = inventoryStack and
        {
          name = inventoryStack.name,
          size = inventoryStack.size,
          reserved = plantingReserved,
          usedPlantingRemainder =
              usedPlantingRemainder
        } or false
    if stackChanged then
      reevaluateService = true
      if not activeIoExchange and not pendingReceipt then
        failedAttempts = 0; retryServiceAt = nil
      end
      if slot == 15 then
        waitingForSticks = false
      end
    end
    if observedVersion ~= nil and observedVersion == api.version(slot) then
      dirtySlots[slot], slotRetryAt[slot] = nil, nil
    end
  end

  function api.peek(slot) return inventorySlots[slot] or nil end

  local function usable(slot)
    return inventorySlots[slot] ~= nil and not dirtySlots[slot] and not slotRetryAt[slot]
  end

  function api.freeSlots()
    local count = 0
    for slot = 1, 13 do if inventorySlots[slot] == false and usable(slot) then count = count + 1 end end
    return count
  end

  function api.spare()
    for slot = 1, 13 do if inventorySlots[slot] == false and usable(slot) then return slot end end
  end

  function api.isNormalized() return inventoryNormalized end

  local function pending()
    for slot = 1, 16 do
      if dirtySlots[slot] and (not slotRetryAt[slot] or deps.now() >= slotRetryAt[slot]) then return slot end
    end
  end
  local function waitInventory(reason)
    inventoryWaiting, inventoryRetryAt = reason, deps.now() + 3
    coroutine.yield()
    inventoryWaiting, inventoryRetryAt = nil, nil
  end
  local function defer(slot)
    dirtySlots[slot], slotRetryAt[slot] = true, deps.now() + 3
  end
  local function tryRead(slot)
    if slotRetryAt[slot] and deps.now() < slotRetryAt[slot] then return false end
    local observedVersion = api.version(slot)
    local readable, inventoryStack = inventoryAccess.readStack(slot)
    readable = readable and (inventoryStack == nil or LinkProtocol.token(inventoryStack.name, 128))
    if readable then api.observed(slot, inventoryStack, observedVersion) end
    coroutine.yield()
    if readable and observedVersion == api.version(slot) then return true, inventoryStack end
    defer(slot); return false
  end
  local function read(slot)
    while true do
      local readable, inventoryStack = tryRead(slot)
      if readable then return inventoryStack end
      waitInventory("ROBOT_STACK_UNREADABLE")
    end
  end
  local function trySelect(slot)
    if slotRetryAt[slot] and deps.now() < slotRetryAt[slot] then return false end
    local success, selectedSlot = inventoryAccess.selectSlot(slot)
    if success and selectedSlot == slot then return true end
    defer(slot); return false
  end
  local function select(slot)
    while not trySelect(slot) do waitInventory("SELECT_FAILED") end
  end
  local function emptySlot(firstSlot, lastSlot)
    for slot = firstSlot, lastSlot do
      if usable(slot) and inventorySlots[slot] == false then
        local readable, stack = tryRead(slot)
        if readable and not stack and trySelect(slot) and not dirtySlots[slot] then return slot end
      end
    end
  end
  local function readExchange(slot)
    local success, stack, reason = pcall(inventoryController.getStackInSlot, 3, slot); coroutine.yield()
    if success and reason == nil and (stack == nil or type(stack) == "table" and
          LinkProtocol.token(stack.name, 128) and LinkProtocol.integer(stack.size, 1, 64)) then
      return true, stack
    end
    return false
  end
  local function sameStack(first, second)
    return (not first and not second) or (first and second and first.name == second.name and first.size == second.size)
  end
  local function transfer(internalSlot, externalSlot, requestedCount, pickup, expectedSource)
    local readable, internalBefore = tryRead(internalSlot)
    if not readable then
      lastExchangeFailure = "ROBOT_STACK_UNREADABLE"; return
    end
    local externalReadable, externalBefore = readExchange(externalSlot)
    if not externalReadable then
      lastExchangeFailure = "IO_UNREADABLE"; return
    end
    local sourceBefore, destinationBefore = internalBefore, externalBefore
    if pickup then sourceBefore, destinationBefore = externalBefore, internalBefore end
    if not sourceBefore or not sameStack(sourceBefore, expectedSource) or dirtySlots[internalSlot] then
      lastExchangeFailure = "INVENTORY_CHANGED"; return
    end
    if pickup and externalSlot == 27 and internalBefore then
      lastExchangeFailure = "INVENTORY_CHANGED"; return
    end
    if not trySelect(internalSlot) then
      lastExchangeFailure = "SELECT_FAILED"; return
    end
    if dirtySlots[internalSlot] then
      lastExchangeFailure = "INVENTORY_CHANGED"; return
    end
    requestedCount = math.min(requestedCount, sourceBefore.size)
    local operation = pickup and inventoryController.suckFromSlot or inventoryController.dropIntoSlot
    pcall(operation, 3, externalSlot, requestedCount); coroutine.yield()
    while true do
      local internalAfter = read(internalSlot)
      local externalReadable, externalAfter = readExchange(externalSlot)
      if externalReadable and not dirtySlots[internalSlot] then
        local sourceAfter, destinationAfter = internalAfter, externalAfter
        if pickup then sourceAfter, destinationAfter = externalAfter, internalAfter end
        if sameStack(sourceBefore, sourceAfter) and sameStack(destinationBefore, destinationAfter) then
          return 0, internalAfter
        end
        local removed = (not sourceAfter or sourceAfter.name == sourceBefore.name) and
            sourceBefore.size - (sourceAfter and sourceAfter.size or 0)
        local added = destinationAfter and destinationAfter.name == sourceBefore.name and
            (not destinationBefore or destinationBefore.name == sourceBefore.name) and
            destinationAfter.size - (destinationBefore and destinationBefore.size or 0)
        if removed and added and removed > 0 and removed <= requestedCount and removed == added then
          return removed, internalAfter
        end
      end
      waitInventory(externalReadable and "TRANSFER_UNVERIFIED" or "IO_UNREADABLE")
    end
  end
  local hand = require("robot_hand").new({
    inventoryAccess = inventoryAccess,
    inventory = inventoryController,
    inventoryMap = api,
    wait = waitInventory
  })
  local function normalizeTransfer(sourceSlot, destinationSlot, requestedCount)
    local expectedSource, expectedDestination = api.peek(sourceSlot), api.peek(destinationSlot)
    local sourceReadable, sourceBefore = tryRead(sourceSlot)
    local destinationReadable, destinationBefore = tryRead(destinationSlot)
    if not sourceReadable or not destinationReadable then return false end
    if not (sourceBefore and sameStack(sourceBefore, expectedSource) and sameStack(destinationBefore, expectedDestination) and
          not dirtySlots[sourceSlot] and not dirtySlots[destinationSlot] and requestedCount <= sourceBefore.size and
          (not destinationBefore or destinationBefore.name == sourceBefore.name)) then
      return false
    end
    if not trySelect(sourceSlot) then return false end
    if dirtySlots[sourceSlot] or dirtySlots[destinationSlot] then return false end
    pcall(robotHardware.transferTo, destinationSlot, requestedCount); coroutine.yield()
    local sourceAfter, destinationAfter = read(sourceSlot), read(destinationSlot)
    local removed = sourceBefore.size - (sourceAfter and sourceAfter.size or 0)
    return removed > 0 and removed <= requestedCount and (not sourceAfter or sourceAfter.name == sourceBefore.name) and
        destinationAfter and destinationAfter.name == sourceBefore.name and
        destinationAfter.size == (destinationBefore and destinationBefore.size or 0) + removed
  end
  local function collect(sourceSlot)
    while usable(sourceSlot) do
      local sourceStack = api.peek(sourceSlot)
      local destinationSlot = sourceStack and (sourceStack.name == "ic2:crop_stick" and 15 or
        (sourceStack.name == "ic2:weeding_trowel" and 16 or nil))
      if not destinationSlot or sourceSlot == destinationSlot then break end
      if not usable(destinationSlot) then
        defer(sourceSlot); return false
      end
      local destinationStack = api.peek(destinationSlot)
      local capacity = destinationSlot == 15 and 64 or 1
      local available = capacity - (destinationStack and destinationStack.size or 0)
      if available <= 0 then break end
      if not normalizeTransfer(sourceSlot, destinationSlot, math.min(sourceStack.size, available)) then
        defer(sourceSlot); return false
      end
    end
    return true
  end
  local function clearHandStorage()
    if not collect(14) then return false end
    for storageSlot = 1, 13 do
      local sourceStack = api.peek(14)
      if not sourceStack then return usable(14) end
      local stored = api.peek(storageSlot)
      if usable(storageSlot) and (not stored or stored.name == sourceStack.name and stored.size < 64) then
        normalizeTransfer(14, storageSlot, math.min(sourceStack.size, 64 - (stored and stored.size or 0)))
      end
    end
    return usable(14) and not api.peek(14)
  end
  local startupInventoryWorker = coroutine.create(function()
    while true do
      local success, size, reason = pcall(robotHardware.inventorySize); coroutine.yield()
      if success and reason == nil and size == 16 then break end
      waitInventory("ROBOT_INVENTORY_MISMATCH")
    end
    local function arrange()
      for slot = 1, 16 do tryRead(slot) end
      if not usable(15) or not usable(16) then return false, "ROBOT_STACK_UNREADABLE" end
      for destinationSlot = 15, 16 do
        local destinationStack = api.peek(destinationSlot)
        local expectedName = destinationSlot == 15 and "ic2:crop_stick" or "ic2:weeding_trowel"
        if destinationStack and destinationStack.name ~= expectedName then
          local otherServiceSlot = destinationSlot == 15 and 16 or 15
          local otherExpectedName = otherServiceSlot == 15 and "ic2:crop_stick" or "ic2:weeding_trowel"
          if destinationStack.name == otherExpectedName and usable(otherServiceSlot) and not api.peek(otherServiceSlot) then
            normalizeTransfer(destinationSlot, otherServiceSlot, destinationStack.size)
          end
          for storageSlot = 1, 13 do
            destinationStack = api.peek(destinationSlot)
            if not destinationStack then break end
            local stored = api.peek(storageSlot)
            if usable(storageSlot) and (not stored or stored.name == destinationStack.name and stored.size < 64) then
              normalizeTransfer(destinationSlot, storageSlot,
                math.min(destinationStack.size, 64 - (stored and stored.size or 0)))
            end
          end
          if api.peek(destinationSlot) then return false, "NORMALIZE_INVENTORY_SPACE" end
        end
      end
      return true
    end
    local function compact()
      for sourceSlot = 1, 13 do
        local source = api.peek(sourceSlot)
        if usable(sourceSlot) and source then
          for destinationSlot = sourceSlot + 1, 13 do
            local destination = api.peek(destinationSlot)
            if usable(destinationSlot) and destination and destination.name == source.name and destination.size < 64 and
                normalizeTransfer(sourceSlot, destinationSlot, math.min(source.size, 64 - destination.size)) then
              return true
            end
          end
        end
      end
      return false
    end
    local handStorageSlot
    while true do
      handStorageSlot = nil
      local arranged, reason = arrange()
      if arranged then
        for slot = 1, 16 do collect(slot) end
      end
      if arranged then
        if clearHandStorage() then handStorageSlot = emptySlot(14, 14) end
      end
      if handStorageSlot and hand.park() then break end
      if not compact() then
        startupSpaceBlocked = (arranged or reason == "NORMALIZE_INVENTORY_SPACE") and
            not handStorageSlot and usable(14) and api.peek(14) ~= nil
        for slot = 1, 13 do
          if not usable(slot) or not api.peek(slot) then
            startupSpaceBlocked = false; break
          end
        end
        waitInventory(reason or (handStorageSlot and "EQUIP_UNKNOWN" or "NORMALIZE_INVENTORY_SPACE"))
        startupSpaceBlocked = false
      end
    end
    while not collect(handStorageSlot) do
      waitInventory("NORMALIZE_NOT_MOVED")
      read(handStorageSlot)
      read(15); read(16)
    end
    local remainingHand = api.peek(handStorageSlot)
    if remainingHand then
      hand.finish(remainingHand)
    end
    for slot = 1, 13 do
      local cargoStack = inventorySlots[slot]
      if cargoStack and cargoStack.name ~= "ic2:weeding_trowel" then ordinaryCargoNeedsService = true end
    end
    inventoryNormalized = true
  end)
  local function face(heading)
    while true do
      local movementComplete, operationError = navigation.face(heading)
      assert(movementComplete ~= nil, operationError or "IO_TURN_FAILED"); if movementComplete then return end
      coroutine.yield()
    end
  end
  local function route()
    local navigationSnapshot = navigation.snapshot()
    assert(navigationSnapshot.trusted and not navigationSnapshot.moving and not navigationSnapshot.stopped,
      "POSITION_UNCERTAIN")
    if not navigationSnapshot.atHome then
      local begun, operationError = navigation.begin(0)
      assert(begun, operationError or "IO_ROUTE_START_FAILED")
      while true do
        local movementComplete, _, operationError = navigation.step()
        assert(movementComplete ~= nil, operationError or "IO_ROUTE_FAILED"); if movementComplete then break end
        coroutine.yield()
      end
    end
    face(1)
  end
  local function drop(slot, destinationSlot, lastDestinationSlot)
    local previousFailure = lastExchangeFailure
    local readable, inventoryStack = tryRead(slot)
    if not readable then
      lastExchangeFailure = "ROBOT_STACK_UNREADABLE"; return destinationSlot
    end
    if not inventoryStack then
      lastExchangeFailure = "ITEM_MISSING"; return destinationSlot
    end
    if inventoryStack.name == "ic2:weeding_trowel" then
      lastExchangeFailure = "TOOL_IN_CARGO"; return destinationSlot
    end
    while destinationSlot <= (lastDestinationSlot or 22) do
      if dirtySlots[slot] then
        lastExchangeFailure = "INVENTORY_CHANGED"; return destinationSlot
      end
      local moved, sourceAfter = transfer(slot, destinationSlot, inventoryStack.size, false, inventoryStack)
      if moved == nil and (not usable(slot) or not sameStack(api.peek(slot), inventoryStack)) then return destinationSlot end
      destinationSlot = destinationSlot + 1
      if moved ~= nil then
        if not sourceAfter then
          lastExchangeFailure = previousFailure; return destinationSlot
        end
        inventoryStack = sourceAfter
      end
    end
    lastExchangeFailure = "ITEM_NOT_MOVED"; return destinationSlot
  end
  local function block(reason)
    physicalFault = physicalFault or reason; exchangeWorker = nil; startupInventoryWorker = nil; inventoryReader = nil
  end
  function api.onConfirmedStationRestart()
    highestCallSequence = 0; callId = nil; releaseReservationsPending = true
    failedAttempts = 0; retryServiceAt = nil; waitingForSticks = false
    if activeIoExchange and not activeIoExchange.granted then cancelUngrantedRequest = true end
  end

  local function resetReservations()
    if not releaseReservationsPending then return end
    for slot = 1, 13 do
      local cargoStack = inventorySlots[slot]
      if cargoStack then
        cargoStack.reserved = nil
        if cargoStack.name ~= "ic2:weeding_trowel" then ordinaryCargoNeedsService = true end
      end
    end
    releaseReservationsPending = false; reevaluateService = true
  end
  function api.needsDrain()
    return releaseReservationsPending or ordinaryCargoNeedsService or
        api.usedPlantingRemainders() >= 4
  end

  function api.ownership()
    if physicalFault then
      return "FAULT",
          activeIoExchange and activeIoExchange.id or (pendingReceipt and pendingReceipt.id) or "*"
    end
    if activeIoExchange and activeIoExchange.granted then return "BUSY", activeIoExchange.id end
    return "FREE", pendingReceipt and pendingReceipt.id or "*"
  end

  function api.awaitingGrant()
    return activeIoExchange ~= nil and activeIoExchange.phase == "REQUESTED" and not activeIoExchange.granted
  end

  function api.recoveringStartup()
    return startupSpaceBlocked and not activeIoExchange and not physicalFault
  end

  function api.prepareAction(emergency)
    if physicalFault or not inventoryNormalized or
        activeIoExchange and not (emergency and api.awaitingGrant()) then
      return false
    end
    inventoryReader = nil; reevaluateService = true
    if not emergency and api.freeSlots() < 4 then return false, "INVENTORY_SPACE" end
    if not emergency and api.needsDrain() then return false, "IO_BUSY" end
    return true
  end

  function api.requestService(callIdFromStation)
    local callNumber = LinkProtocol.call(callIdFromStation)
    if not callNumber or callNumber <= highestCallSequence then return end
    highestCallSequence = callNumber
    if not activeIoExchange or activeIoExchange.phase == "ROUTING" or activeIoExchange.phase == "REQUESTED" then
      callId =
          callIdFromStation
    end
    reevaluateService = true
  end

  function api.acknowledgeReceipt(exchangeId, reportedStatus)
    if not pendingReceipt or exchangeId ~= pendingReceipt.id or reportedStatus ~= pendingReceipt.status then return end
    if pendingReceipt.status == "FAILED" then
      failedAttempts = math.min(failedAttempts + 1, 5)
      retryServiceAt = deps.now() + math.min(60, 3 * 2 ^ (failedAttempts - 1))
    else
      failedAttempts = 0; retryServiceAt = nil
    end
    pendingReceipt = nil; reevaluateService = true
  end

  function api.acceptGrant(exchangeId, grantMode)
    if not activeIoExchange or exchangeId ~= activeIoExchange.id or activeIoExchange.phase ~= "REQUESTED" or activeIoExchange.granted then return end
    local grantedCallNumber = LinkProtocol.call(grantMode)
    if grantMode ~= "EXCHANGE" and not grantedCallNumber then return end
    if grantedCallNumber then highestCallSequence = math.max(highestCallSequence, grantedCallNumber) end
    callId = nil; activeIoExchange.granted = true
  end

  local function start(id)
    lastExchangeFailure = nil
    activeIoExchange = { id = id, phase = "ROUTING" }
    exchangeWorker = coroutine.create(function()
      local requestCallSequence
      repeat
        if activeIoExchange.phase == "ROUTING" then
          route()
          if cancelUngrantedRequest then
            cancelUngrantedRequest = false; activeIoExchange = nil; reevaluateService = true
            return
          end
          activeIoExchange.phase = "REQUESTED"
          requestCallSequence = requestCallSequence or LinkProtocol.call(callId) or 0
        end
        local requestSentAt = deps.now()
        activeIoExchange.requestSentAt = requestSentAt
        deps.send("IO_REQUEST", id, "EXCHANGE", requestCallSequence)
        repeat
          local energyReturnRequired = coroutine.yield()
          if not activeIoExchange.granted and energyReturnRequired and
              navigation.workReady() and not navigation.snapshot().atHome then
            activeIoExchange.phase = "ROUTING"
            break
          end
        until activeIoExchange.granted or deps.now() - requestSentAt >= 3
      until activeIoExchange.granted
      -- An emergency ACTION may have moved us away from the dock while
      -- this request was waiting. Reestablish the transfer pose first.
      route()
      activeIoExchange.phase = "EXCHANGING"
      local destinationSlot, remainderDestinationSlot = 2, 23
      for slot = 1, 14 do
        if inventorySlots[slot] or dirtySlots[slot] then
          if inventorySlots[slot] and inventorySlots[slot].usedPlantingRemainder then
            remainderDestinationSlot = drop(slot, remainderDestinationSlot, 26)
          elseif inventorySlots[slot] and (inventorySlots[slot].reserved or inventorySlots[slot].name == "ic2:weeding_trowel") then
            local readable, inventoryStack = tryRead(slot)
            if not readable then
              lastExchangeFailure = "ROBOT_STACK_UNREADABLE"
            elseif not inventoryStack or (not inventorySlots[slot].reserved and inventoryStack.name ~= "ic2:weeding_trowel") then
              lastExchangeFailure =
              "RESERVED_ITEM_CHANGED"
            end
          else
            destinationSlot = drop(slot, destinationSlot)
          end
        end
      end
      while true do
        local handStorageSlot = clearHandStorage() and emptySlot(14, 14)
        if not handStorageSlot then
          lastExchangeFailure = "INVENTORY_SPACE"; break
        end
        local parked, heldStack = hand.park()
        if parked then
          if heldStack and heldStack.name ~= "ic2:crop_stick" and
              not (heldStack.name == "ic2:crop_res" and heldStack.damage == 5) then
            hand.finish(heldStack)
          elseif heldStack then
            drop(handStorageSlot, destinationSlot)
          end
          break
        end
        waitInventory("EQUIP_UNKNOWN")
      end
      local stickFailure
      local sticksReadable, sticksBefore = tryRead(15)
      if not sticksReadable then
        stickFailure = "ROBOT_STACK_UNREADABLE"
      elseif sticksBefore and sticksBefore.name ~= "ic2:crop_stick" then
        stickFailure = "STICKS_SLOT_OCCUPIED"
      else
        local stickCount = sticksBefore and sticksBefore.size or 0
        if stickCount < 64 then
          local readable, availableSticks = readExchange(1)
          if not readable then
            stickFailure = "IO_UNREADABLE"
          elseif availableSticks then
            if availableSticks.name ~= "ic2:crop_stick" then
              stickFailure = "STICKS_SLOT_MISMATCH"
            elseif dirtySlots[15] then
              stickFailure = "INVENTORY_CHANGED"
            else
              local requestedCount = math.min(64 - (sticksBefore and sticksBefore.size or 0), availableSticks.size)
              while requestedCount > 0 do
                local receivedCount, sticksAfter = transfer(15, 1, requestedCount, true, availableSticks)
                if receivedCount == nil then
                  stickFailure = lastExchangeFailure; break
                end
                if receivedCount == 0 then
                  if not sticksAfter or sticksAfter.name ~= "ic2:crop_stick" or sticksAfter.size < 64 then
                    stickFailure = "STICKS_NOT_RECEIVED"
                  end
                  break
                end
                requestedCount = math.min(requestedCount - receivedCount, 64 - sticksAfter.size)
                if requestedCount > 0 then
                  local readable
                  readable, availableSticks = readExchange(1)
                  if not readable then
                    stickFailure = "IO_UNREADABLE"; break
                  end
                  if not availableSticks then break end
                end
              end
            end
          end
        end
      end
      lastExchangeFailure = stickFailure or lastExchangeFailure
      local seedReadable, inventoryStack = readExchange(27)
      if not seedReadable then lastExchangeFailure = "IO_UNREADABLE" end
      local previousReservation = api.received()
      if inventoryStack and previousReservation then
        local readable, previousStack = tryRead(previousReservation.slot)
        if not readable then
          lastExchangeFailure = "ROBOT_STACK_UNREADABLE"
        elseif not previousStack or previousStack.name ~= previousReservation.name or previousStack.size ~= 1 then
          lastExchangeFailure = "RESERVED_ITEM_CHANGED"
        else
          destinationSlot = drop(previousReservation.slot, destinationSlot)
        end
      end
      if inventoryStack and api.received() then
        lastExchangeFailure = lastExchangeFailure or "RESERVED_ITEM_NOT_RELEASED"
      elseif inventoryStack then
        if not LinkProtocol.plantingItem(inventoryStack.name) or inventoryStack.size ~= 1 then
          lastExchangeFailure = "SEED_UNSUPPORTED"
        else
          local previousFailure = lastExchangeFailure
          for destinationSlot = 1, 13 do
            if usable(destinationSlot) and inventorySlots[destinationSlot] == false then
              local receivedCount = transfer(destinationSlot, 27, 1, true, inventoryStack)
              if receivedCount == 1 then
                inventorySlots[destinationSlot].reserved = true; lastExchangeFailure = previousFailure; break
              end
              lastExchangeFailure = lastExchangeFailure or "SEED_NOT_RECEIVED"
            end
          end
          if not api.received() then lastExchangeFailure = lastExchangeFailure or "INVENTORY_SPACE" end
        end
      end
      local stationRestarted = releaseReservationsPending
      resetReservations()
      if ordinaryCargoNeedsService or lastExchangeFailure then
        local ordinaryCargoRemains = false
        for slot = 1, 14 do
          local cargoStack = inventorySlots[slot]
          if cargoStack and (slot == 14 or not cargoStack.reserved and cargoStack.name ~= "ic2:weeding_trowel") then
            ordinaryCargoRemains = true
          end
        end
        ordinaryCargoNeedsService = ordinaryCargoRemains
      end
      local exchangeFailure = lastExchangeFailure
      local stickStack = api.peek(15)
      waitingForSticks = not stationRestarted and not stickFailure and
          (not stickStack or (stickStack.name == "ic2:crop_stick" and
            stickStack.size < math.max(2, deps.requiredSticks and deps.requiredSticks() or 2)))
      pendingReceipt = { id = id, status = exchangeFailure and "FAILED" or "SUCCESS", sent = deps.now() }
      activeIoExchange = nil; reevaluateService = true
      deps.send("IO_UNLOADED", id, pendingReceipt.status, 0)
    end)
  end
  function api.received()
    for slot = 1, 13 do
      if inventorySlots[slot] and inventorySlots[slot].reserved and not inventorySlots[slot].usedPlantingRemainder then
        return {
          slot =
              slot,
          name = inventorySlots[slot].name
        }
      end
    end
  end

  function api.usedPlantingRemainders()
    local count = 0
    for slot = 1, 13 do
      if inventorySlots[slot] and inventorySlots[slot].usedPlantingRemainder then count = count + 1 end
    end
    return count
  end

  function api.markUsedPlantingRemainder(slot)
    local material = inventorySlots[slot]
    material.reserved = nil; material.usedPlantingRemainder = true; reevaluateService = true
  end

  function api.releasePlanting(slot)
    if slot and inventorySlots[slot] then inventorySlots[slot].reserved = nil end
  end

  function api.requestCargoService()
    ordinaryCargoNeedsService = true; reevaluateService = true
  end

  function api.retryReceipt(connectionConfirmed)
    if pendingReceipt and connectionConfirmed and deps.now() - pendingReceipt.sent >= 3 then
      pendingReceipt.sent = deps.now()
      deps.send("IO_UNLOADED", pendingReceipt.id, pendingReceipt.status, 0)
    end
  end

  local function advance(workerCoroutine, ...)
    local success, operationError = coroutine.resume(workerCoroutine, ...)
    if not success then
      block(tostring(operationError):match("([A-Z][A-Z_]+)$") or "ROBOT_IO_ERROR"); return true
    end
    return coroutine.status(workerCoroutine) == "dead"
  end
  local function serviceNeeded()
    local inventoryStack = api.peek(15)
    return ordinaryCargoNeedsService or api.usedPlantingRemainders() >= 4 or callId or api.freeSlots() < 4 or
        (not inventoryStack or (inventoryStack.name == "ic2:crop_stick" and
          inventoryStack.size < math.max(2, deps.requiredSticks and deps.requiredSticks() or 2))) and
        not waitingForSticks
  end
  local function startService()
    exchangeSequence = exchangeSequence + 1; assert(exchangeSequence <= LinkProtocol.maxInt, "IO_SEQUENCE_EXHAUSTED")
    start(tostring(exchangeSequence))
  end
  function api.connectionNeeded(stationAllowsService)
    if physicalFault then return false end
    if pendingReceipt then return true end
    if not stationAllowsService then return false end
    if activeIoExchange then return activeIoExchange.phase == "REQUESTED" and not activeIoExchange.granted end
    if api.recoveringStartup() then return true end
    return inventoryNormalized and not inventoryReader and not pending() and
        reevaluateService and
        (not retryServiceAt or deps.now() >= retryServiceAt) and serviceNeeded() or false
  end

  function api.step(connectionConfirmed, serviceAllowed, energyReturnRequired)
    if physicalFault then return end
    if inventoryRetryAt and deps.now() < inventoryRetryAt then return end
    if startupInventoryWorker and not activeIoExchange then
      if api.recoveringStartup() and connectionConfirmed and serviceAllowed and not pendingReceipt and
          (not retryServiceAt or deps.now() >= retryServiceAt) then
        startupSpaceBlocked = false
        startService()
      else
        if advance(startupInventoryWorker) then startupInventoryWorker = nil end
        return
      end
    end
    if not activeIoExchange or not activeIoExchange.granted then resetReservations() end
    if cancelUngrantedRequest and activeIoExchange and not activeIoExchange.granted and activeIoExchange.phase == "REQUESTED" then
      activeIoExchange, exchangeWorker = nil, nil; cancelUngrantedRequest = false; reevaluateService = true
    end
    if activeIoExchange then
      if not connectionConfirmed and api.awaitingGrant() and not energyReturnRequired then return end
      if advance(exchangeWorker, energyReturnRequired) then exchangeWorker = nil end
      return
    end
    if inventoryReader then
      if advance(inventoryReader) then inventoryReader = nil end; return
    end
    if pending() then
      inventoryReader = coroutine.create(function()
        local slot = pending()
        if slot then
          local readable = tryRead(slot)
          if readable then collect(slot) end
        end
      end)
      if advance(inventoryReader) then inventoryReader = nil end
      return
    end
    if ordinaryCargoNeedsService and reevaluateService then
      ordinaryCargoNeedsService = false
      for slot = 1, 14 do
        local stack = inventorySlots[slot]
        if stack and (slot == 14 or not stack.reserved and not stack.usedPlantingRemainder and stack.name ~= "ic2:weeding_trowel") then
          ordinaryCargoNeedsService = true; break
        end
      end
    end
    if pendingReceipt or not reevaluateService or not connectionConfirmed or not serviceAllowed or
        (retryServiceAt and deps.now() < retryServiceAt) then
      return
    end
    reevaluateService = false
    local inventoryStack = api.peek(15)
    if serviceNeeded() then
      startService()
    elseif inventoryStack and inventoryStack.name ~= "ic2:crop_stick" then
      lastExchangeFailure = "STICKS_SLOT_OCCUPIED"
    end
    if exchangeWorker and advance(exchangeWorker) then exchangeWorker = nil end
  end

  function api.activity()
    return startupInventoryWorker ~= nil or inventoryReader ~= nil or activeIoExchange ~= nil or pending() ~= nil,
        physicalFault ~= nil
  end

  function api.hasReadyWork(connectionConfirmed)
    if physicalFault then return false end
    if inventoryRetryAt and deps.now() < inventoryRetryAt then return false end
    if activeIoExchange then
      if activeIoExchange.phase ~= "REQUESTED" or activeIoExchange.granted then return true end
      return cancelUngrantedRequest or (connectionConfirmed and deps.now() - activeIoExchange.requestSentAt >= 3) or
          false
    end
    return startupInventoryWorker ~= nil or inventoryReader ~= nil or pending() ~= nil
  end

  function api.snapshot()
    local inventoryStack = api.peek(15)
    local reservedPlantingItem = api.received()
    return {
      id = activeIoExchange and activeIoExchange.id,
      phase = activeIoExchange and activeIoExchange.phase,
      mode = activeIoExchange and "EXCHANGE",
      fault = physicalFault,
      failure = lastExchangeFailure,
      normalized = inventoryNormalized,
      inventoryWaiting = inventoryWaiting,
      free = api.freeSlots(),
      sticks15 = inventoryStack and inventoryStack.name == "ic2:crop_stick" and inventoryStack.size or 0,
      waitingForSticks = waitingForSticks,
      failedAttempts = failedAttempts,
      serviceRetrySuppressed = retryServiceAt ~= nil and deps.now() < retryServiceAt,
      seedSlot = reservedPlantingItem and reservedPlantingItem.slot,
      seedName = reservedPlantingItem and reservedPlantingItem.name,
      usedPlantingRemainders = api.usedPlantingRemainders(),
      needsDrain = api.needsDrain(),
      awaitingAck = pendingReceipt and pendingReceipt.id,
      receiptStatus = pendingReceipt and pendingReceipt.status,
      callId = callId,
      busy = startupInventoryWorker ~= nil or inventoryReader ~= nil or activeIoExchange ~= nil or pending() ~= nil
    }
  end

  function api.reserved()
    return startupInventoryWorker ~= nil or inventoryReader ~= nil or activeIoExchange ~= nil or
        physicalFault ~= nil or pending() ~= nil
  end

  return api
end

return RobotIO
