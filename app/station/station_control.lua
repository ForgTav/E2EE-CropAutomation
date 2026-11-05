local Protocol = require("shared_link")
local State = require("station_state")
local Catalog = require("station_catalog")
local Quantity = require("station_production_rules")
local Planner = require("station_planner")

local Control = {}
function Control.label(enabled, workPending, blocker)
  if not enabled then return "STOPPED" end
  if blocker then return "AWAIT" end
  return workPending and "RUNNING" or "READY"
end

function Control.new(store, initialState, loadError)
  local state = initialState
  local enabled, fatal = false, loadError ~= nil
  local diagnostic, blocker, uiDiagnostic = loadError, loadError, nil
  local observation, inventory, link, now, plannerYield
  local action, actionOutcome, actionReason, lastAction
  local localityCell
  local step, planKey, planStatus = nil, nil, { kind = "IDLE", phase = "IDLE" }
  local function clearPlanDisplay()
    planStatus.orderId, planStatus.routeFrom, planStatus.routeTo, planStatus.genetics = nil, nil, nil, nil
  end
  local routeMemo = {}
  local nextActionId, verificationSequence, stopRevision = 1, 0, 0
  local readySequence, stamp = 0, nil
  local admission
  local robotBootId, robotStatus
  local startupStatusPending, startupWorkerRunning = false, false
  local ioState, ioFault, reportedExchangeId = "UNKNOWN", nil, nil
  local ioRequest, ioExchange, ioCall, ioReceipt, sortingReceipt
  local highestRequest, highestReceipt, callSequence = 0, 0, 0
  local sortingRequired, heldMaterial = false, nil
  local batchExtractions, batchOrderId = 0, nil
  local inbox = {}
  local api = {}

  local function activeOrder(from)
    for _, order in ipairs((from or state).orders) do
      if order.status == "ACTIVE" then return order end
    end
  end
  local function batchDue()
    if batchExtractions == 0 then return false end
    local order = activeOrder()
    return not order or order.id ~= batchOrderId or Quantity.remaining(order) == 0 or
        batchExtractions >= math.min(8, Quantity.remaining(order))
  end
  local function orderCriteria()
    if not enabled or fatal then return end
    local order = activeOrder()
    if not order then return end
    return {
      id = order.id,
      key = order.owner .. ":" .. order.cropId,
      g = order.g,
      ga = order.ga,
      r = order.r,
      remaining = order.K - order.produced
    }
  end
  local function copyState()
    local copied = { schema = 8, revision = state.revision, nextOrderId = state.nextOrderId, orders = {} }
    for i, original in ipairs(state.orders) do
      local row = {}
      for field, value in pairs(original) do row[field] = value end
      copied.orders[i] = row
    end
    return copied
  end
  local function findOrder(orders, id)
    for index, order in ipairs(orders) do if order.id == id then return order, index end end
  end
  local function nextQueued(candidate)
    for _, order in ipairs(candidate.orders) do
      if order.status == "QUEUED" then
        order.status = "ACTIVE"; return true
      end
    end
  end
  local function closeOrder(candidate, id)
    local order = findOrder(candidate.orders, id)
    if not order then return nil, "ORDER_NOT_FOUND" end
    if order.status == "CLOSED" then return false end
    local wasActive = order.status == "ACTIVE"
    order.status = "CLOSED"
    if wasActive then nextQueued(candidate) end
    return true
  end
  local function save(candidate, editedActive)
    local previous = activeOrder()
    local success, reason = store.commit(candidate)
    if not success then
      api.fail(reason or "WRITE_FAILED"); return nil
    end
    state = candidate
    local current = activeOrder()
    if editedActive or (previous and previous.id) ~= (current and current.id) then
      clearPlanDisplay()
      step, admission = nil, nil
      if action then action.step = nil end
    end
    if editedActive then
      if inventory then inventory.invalidateOrder(previous.id) end
      planStatus = { kind = "IDLE", phase = "IDLE" }
      for index = #inbox, 1, -1 do
        if inbox[index].kind == "IO_CALL" and inbox[index].material then table.remove(inbox, index) end
      end
    end
    planKey = nil
    return true
  end
  local function credit(orderId, amount)
    if fatal or not Protocol.integer(orderId, 1, state.nextOrderId - 1) then
      api.fail("OUTPUT_PROGRESS_INVALID"); return nil
    end
    local order = findOrder(state.orders, orderId)
    if not order then
      if #state.orders == State.maxOrders and state.nextOrderId > State.maxOrders + 1 and
          Protocol.integer(amount, 1, 64) then
        return true
      end
      api.fail("OUTPUT_PROGRESS_INVALID"); return nil
    end
    if not (order.status == "ACTIVE" or order.status == "CLOSED") or
        not Protocol.integer(amount, 1, order.K - order.produced) then
      api.fail("OUTPUT_PROGRESS_INVALID"); return nil
    end
    local candidate = copyState()
    local credited = findOrder(candidate.orders, orderId)
    credited.produced = credited.produced + amount
    if credited.status == "ACTIVE" and credited.produced == credited.K then closeOrder(candidate, orderId) end
    return save(candidate)
  end
  function api.attachLink(attached)
    link = attached
  end

  function api.attachObservation(attached, clock)
    observation, now = attached, clock
  end

  function api.attachInventory(dependencies)
    if fatal or not state then return end
    plannerYield = dependencies.yieldComputation
    inventory = require("station_inventory").new({
      transposer = dependencies.transposer,
      rotation = dependencies.rotation,
      now = dependencies.now,
      startupCheck = dependencies.startupCheck,
      enabled = function() return enabled and not fatal end,
      order = orderCriteria,
      credit = credit
    })
  end

  function api.isStopped() return not enabled end

  local function ready(linkState, safetyDuringLocalWork)
    local networkReady, connectedBoot, queueFault
    if linkState then
      networkReady, connectedBoot, queueFault = linkState.networkReady, linkState.boot, linkState.queueFault
    elseif link then
      networkReady, connectedBoot, queueFault = link.connectionStatus()
    end
    return networkReady and not queueFault and
        robotBootId == connectedBoot and robotStatus == "READY" and ioState == "STATION" and
        (safetyDuringLocalWork or reportedExchangeId == nil or reportedExchangeId == "*") and
        not ioRequest and not ioExchange and (not ioCall or safetyDuringLocalWork and ioCall.phase == "PREPARING") and
        (safetyDuringLocalWork or (not sortingRequired and not sortingReceipt)) and
        not (inventory and inventory.fault())
  end
  local function outstanding()
    return action or ioExchange or ioRequest or ioCall or ioState == "ROBOT" or
        ioState == "UNCERTAIN" or ioState == "UNKNOWN" and link and link.snapshot().paired
  end
  local function resetBlocked()
    return action or ioExchange or ioRequest or ioCall or ioState == "ROBOT" or ioState == "UNCERTAIN" or
        sortingReceipt or reportedExchangeId and reportedExchangeId ~= "*"
  end
  local function resetPending()
    for _, command in ipairs(inbox) do if command.kind == "PAIR_RESET" then return true end end
    return false
  end
  local function queue(command)
    if #inbox >= 32 then
      uiDiagnostic = "CONTROL_QUEUE_FULL"; return nil, "QUEUE_FULL"
    end
    inbox[#inbox + 1] = command
    if command.kind == "IO_CALL" and enabled and link then link.requestConnection(false, true) end
    return true
  end
  function api.fail(reason)
    clearPlanDisplay()
    enabled, fatal, blocker, diagnostic = false, true, reason, reason
    stopRevision = stopRevision + 1
    if link then link.stopAction() end
    if observation then observation.pause() end
    inbox = {}
  end

  function api.request(kind, details)
    if kind == "STOP" then
      clearPlanDisplay()
      local wasEnabled = enabled
      enabled = false; stopRevision = stopRevision + 1
      if not (step and step.action) then step = nil end
      planKey = nil; admission = nil
      if link then
        link.stopAction(); if wasEnabled then link.requestConnection(true) end
      end
      if observation then observation.pause() end
      inbox = {}
      return true
    end
    if kind == "ORDER_CREATE" or kind == "ORDER_EDIT" or kind == "ORDER_CANCEL" then
      if fatal or not state then return nil, "STATE_MISSING" end
      if type(details) ~= "table" then return nil, "ORDER_INVALID" end
      local copy = {}
      for _, field in ipairs({ "owner", "cropId", "g", "ga", "r", "K", "id", "resetProduced" }) do
        copy[field] =
            details[field]
      end
      return queue({ kind = kind, details = copy })
    end
    if kind == "IO_CALL" then
      if fatal or not enabled or not inventory or
          (details ~= nil and not Protocol.integer(details, 1, 54)) then
        return nil, "IO_NOT_READY"
      end
      return queue({ kind = "IO_CALL", slot = details })
    end
    if kind == "PAIR_RESET" then
      local network = link and link.snapshot()
      if enabled or resetBlocked() or not network or network.pairing or resetPending() or
          (network.commandCount or 0) > 0 then
        return nil, "PAIR_REQUIRES_STOPPED"
      end
      for _, command in ipairs(inbox) do
        if command.kind:match("^PAIR_") then return nil, "PAIR_REQUIRES_STOPPED" end
      end
      return queue({ kind = kind, details = { address = network.robotAddress } })
    end
    if kind == "PAIR_OPEN" or kind == "PAIR_CLOSE" or kind == "PAIR_SELECT" then
      if resetPending() then return nil, "PAIR_RESET_PENDING" end
      if enabled or not link or (kind ~= "PAIR_CLOSE" and outstanding()) then return nil, "PAIR_REQUIRES_STOPPED" end
      return queue({ kind = kind, details = details })
    end
    if kind ~= "START" then return nil, "REJECTED" end
    if fatal or not state then return nil, diagnostic or "STATE_MISSING" end
    if resetPending() or link and link.snapshot().pairing then return nil, "CLOSE_PAIRING_FIRST" end
    if enabled then return true end
    return queue({ kind = "START" })
  end

  local function validatedCell(name, cell, harvest)
    local facts = observation.snapshot(cell)
    if not facts or not facts.scanOk or not facts.seenAt then return nil, "OBSERVATION_UNREADABLE" end
    local variant
    if name == "PLACE_DOUBLE_STICKS" then
      if facts.kind == "AIR" then
        variant = "BARE_FARMLAND"
      elseif facts.kind == "SINGLE" then
        variant = "SINGLE"
      end
      if not variant then return nil, "UNSAFE_TARGET" end
    elseif name == "COLLECT_AND_RESTORE_DOUBLE" then
      if facts.kind ~= "PLANT" or not facts.owner or not facts.id or
          facts.g == nil or facts.ga == nil or facts.r == nil or
          facts.owner == "ic2" and facts.id == "weed" then
        return nil, "UNSAFE_TARGET"
      end
    end
    if name == "EXTRACT_AND_PLANT" and facts.tile then
      if facts.kind ~= "SINGLE" and facts.kind ~= "DOUBLE" and
          not (facts.kind == "PLANT" and facts.owner and facts.id and
            facts.g ~= nil and facts.ga ~= nil and facts.r ~= nil) then
        return nil, "UNSAFE_TARGET"
      end
      variant = "REPLACE_TILE"
    end
    if name == "PLANT_SEED" or name == "EXTRACT_AND_PLANT" or variant == "BARE_FARMLAND" then
      if facts.kind ~= "AIR" and not (name == "EXTRACT_AND_PLANT" and variant == "REPLACE_TILE") then
        return nil,
            "UNSAFE_TARGET"
      end
      if not facts.soilChecked then return nil, "SOIL_OBSERVATION_STALE" end
      if facts.soil ~= "minecraft:farmland" then return nil, "UNSAFE_TARGET" end
    elseif not facts.tile then
      return nil, "NO_CROP_TILE"
    elseif name == "REMOVE_WEED" and
        (facts.kind ~= "PLANT" or facts.owner ~= "ic2" or facts.id ~= "weed") then
      return nil, "UNSAFE_TARGET"
    end
    if harvest and (facts.kind ~= "PLANT" or not facts.size or facts.size < 2 or
          facts.owner == "ic2" and facts.id == "weed") then
      return nil, "UNSAFE_TARGET"
    end
    return facts, nil, variant
  end
  local function donor(cell)
    local facts, reason = validatedCell("COLLECT_AND_CLEAR_CELL", cell, true)
    if not facts then return nil, nil, reason end
    if facts.danger or not facts.owner or not facts.id or
        facts.g == nil or facts.ga == nil or facts.r == nil then
      return nil, nil, "UNSAFE_SOURCE"
    end
    local key = facts.owner .. ":" .. facts.id
    if not Catalog.canProceed(key) then return nil, nil, "UNSAFE_SOURCE" end
    local result = { key = key, g = facts.g, ga = facts.ga, r = facts.r }
    if Quantity.outputKind(result) == "vanilla" then result.g, result.ga, result.r = 1, 1, 1 end
    return facts, result
  end
  local function sameEffect(before, after)
    if before.kind == "AIR" and not after.tile and
        after.kind == "AIR" then
      return true
    end
    for _, field in ipairs({ "kind", "tile", "owner", "id", "g", "ga", "r", "crossingBase", "block" }) do
      if before[field] ~= after[field] then return false end
    end
    if before.size ~= after.size and
        (not before.size or not after.size or after.size < before.size) then
      return false
    end
    return true
  end
  local function absent(facts)
    return facts and not facts.tile and (facts.kind == "AIR" or facts.block == "minecraft:air")
  end
  local function planted(facts, expected)
    return facts and expected and facts.kind == "PLANT" and facts.owner and facts.id and
        facts.owner .. ":" .. facts.id == expected.key and facts.g == expected.g and
        facts.ga == expected.ga and facts.r == expected.r and not facts.danger
  end
  local function conclude(outcome, reason)
    local current = assert(action)
    assert(link.releaseAction(current.id))
    lastAction = {
      id = current.id,
      stationBootId = current.stationBootId,
      robotBootId = current.robotBootId,
      name = current.name,
      cell = current.to,
      from = current.from,
      variant = current.variant,
      emergency = current.emergency,
      outcome = outcome,
      reported = current.reported,
      reason = reason,
      robotReason = current.robotReason
    }
    if outcome == "PASS" then localityCell = current.to end
    if current.quantityOrderId and outcome == "PASS" then
      batchExtractions = math.min(8, batchExtractions + 1)
      batchOrderId = batchOrderId or current.quantityOrderId
    end
    if current.name == "PLANT_SEED" and
        (outcome == "PASS" or current.reported == "SUCCESS" or
          outcome == "PARTIAL" and current.targetFacts and current.targetFacts.kind == "PLANT" or
          current.robotReason == "MISSING_PLANTING_ITEM" or
          current.robotReason == "PLANT_PARTIAL_MISSING_ITEM") then
      heldMaterial = nil
    end
    action = nil
    actionOutcome, actionReason = outcome, reason
    local continuation = step and step.action and step
    step = outcome == "PASS" and current.step or
        ((outcome == "BLOCKED" or outcome == "NO_CHANGE") and continuation or nil)
    if outcome == "BLOCKED" or outcome == "NO_CHANGE" then
      lastAction.readySequence = readySequence
      lastAction.unprocessed = true
      planKey = stamp()
      blocker, diagnostic = current.robotReason or reason, current.robotReason or reason
    else
      planKey = nil
      blocker, diagnostic = nil, nil
    end
  end
  local function verify()
    local current = action
    if not current or not (current.reported or current.recoveryBoot) or not current.targetFacts or
        (current.name == "EXTRACT_AND_PLANT" and not current.sourceFacts) then
      return
    end
    if not current.recoveryBoot and (current.unknown or current.reported == "UNKNOWN" or
          link.snapshot().boot ~= current.robotBootId or
          observation.rotation() ~= current.rotation) then
      actionOutcome, actionReason = "UNKNOWN", "EXPLICIT_RESOLUTION_REQUIRED"; return
    end
    local target = current.targetFacts
    local source = current.sourceFacts
    current.verificationRevision = observation.planningRevision()
    if current.name == "EXTRACT_AND_PLANT" then
      if source.kind == "UNREADABLE" or target.kind == "UNREADABLE" then return end
      if current.recoveryBoot then
        conclude("PARTIAL", "EXTRACT_AND_PLANT_REBOOT_OBSERVED")
      elseif current.reported == "SUCCESS" and absent(source) and planted(target, current.expected) then
        conclude("PASS", "SENSOR_VERIFIED")
      elseif sameEffect(current.sourceBefore, source) and sameEffect(current.before, target) then
        conclude(current.reported == "BLOCKED" and "BLOCKED" or "NO_CHANGE", "SENSOR_VERIFIED_NO_EFFECT")
      else
        conclude("PARTIAL", "SENSOR_VERIFIED_PARTIAL")
      end
      return
    end
    local effect
    if current.name == "PLACE_DOUBLE_STICKS" or current.name == "COLLECT_AND_RESTORE_DOUBLE" then
      local newCrop = target.kind == "PLANT" and target.owner and target.id and
          target.g ~= nil and target.ga ~= nil and target.r ~= nil
      effect = (target.kind == "DOUBLE" and target.crossingBase == 1) or
          (newCrop and (current.before.kind == "SINGLE" or current.before.kind == "AIR" or
            current.name == "COLLECT_AND_RESTORE_DOUBLE" and not sameEffect(current.before, target)))
      if current.name == "COLLECT_AND_RESTORE_DOUBLE" and current.reported == "SUCCESS" and
          sameEffect(current.before, target) then
        conclude("NO_CHANGE", "SENSOR_VERIFIED_NO_PROGRESS"); return
      end
    elseif current.name == "COLLECT_AND_CLEAR_CELL" then
      effect = absent(target)
    elseif current.name == "REMOVE_WEED" then
      effect = target.scanOk and target.kind ~= "UNREADABLE" and
          not (target.owner == "ic2" and target.id == "weed")
    elseif current.name == "PLANT_SEED" then
      effect = planted(target, current.expected)
    end
    if current.reported == "SUCCESS" and effect then
      conclude("PASS", "SENSOR_VERIFIED")
    elseif (current.reported == "SUCCESS" or current.reported == "BLOCKED") and
        current.name == "PLANT_SEED" and
        current.before.kind == "AIR" and not current.before.tile and
        target.kind == "PLANT" and target.tile and target.owner and target.id and
        target.g ~= nil and target.ga ~= nil and target.r ~= nil then
      conclude("PARTIAL", "SENSOR_VERIFIED_PARTIAL")
    elseif current.reported == "BLOCKED" and effect then
      conclude("PARTIAL", "SENSOR_VERIFIED_PARTIAL")
    elseif current.name == "PLANT_SEED" and current.reported == "BLOCKED" and
        current.before.kind == "AIR" and not current.before.tile and
        target.kind == "SINGLE" and target.tile and not target.owner and not target.id then
      conclude("PARTIAL", "SENSOR_VERIFIED_PARTIAL")
    elseif (current.reported == "BLOCKED" or current.reported == "NO_CHANGE") and
        sameEffect(current.before, target) and
        (not source or sameEffect(current.sourceBefore, source)) then
      conclude(current.reported, "SENSOR_VERIFIED_NO_EFFECT")
    elseif current.reported == "SUCCESS" or current.reported == "BLOCKED" then
      actionOutcome, actionReason = "UNKNOWN", "EXPECTED_EFFECT_ABSENT"
    else
      actionOutcome, actionReason = "UNKNOWN", "EXPLICIT_RESOLUTION_REQUIRED"
    end
  end
  local function actionEvent(event)
    local current = action
    if not current then return end
    if event.kind == "ROBOT_CONFIRMED" and event.boot ~= current.robotBootId then
      if current.name == "EXTRACT_AND_PLANT" then
        current.recoveryBoot = event.boot
        current.verifyToken, current.targetFacts, current.sourceFacts = nil, nil, nil
        actionOutcome, actionReason = "PENDING", "EXTRACT_AND_PLANT_REBOOT_OBSERVATION"
      else
        current.unknown = true; actionOutcome, actionReason = "UNKNOWN", "ROBOT_REBOOT"
      end
      return
    end
    if event.kind == "SCAN_RESULT" and event.token == current.verifyToken then
      current.verifyToken = nil
      if not event.ok then
        if event.error == "CANCELLED_STOPPED" then return end
        if current.name == "EXTRACT_AND_PLANT" and event.errorCategory == "OBS_DATA_INVALID" and
            (current.recoveryBoot or current.reported and current.reported ~= "UNKNOWN" and not current.unknown) then
          conclude("PARTIAL", "EXTRACT_AND_PLANT_LOCAL_FACTS_UNREADABLE"); return
        end
        current.verifyAfter = now() + 3
        actionOutcome, actionReason = "PENDING", "VERIFICATION_UNAVAILABLE"; return
      end
      local facts = observation.snapshot(event.cell)
      if not facts or not facts.scanOk or facts.version ~= event.version then
        current.verifyAfter = now() + 3; actionOutcome, actionReason = "UNKNOWN", "VERIFICATION_UNREADABLE"; return
      end
      if event.cell == current.to then
        current.targetFacts = facts
      elseif event.cell == current.from then
        current.sourceFacts = facts
      end
      if current.targetFacts and (current.name ~= "EXTRACT_AND_PLANT" or current.sourceFacts) then
        if observation.snapshot(current.to).version ~= current.targetFacts.version or
            current.name == "EXTRACT_AND_PLANT" and observation.snapshot(current.from).version ~= current.sourceFacts.version then
          current.targetFacts, current.sourceFacts = nil, nil
        else
          verify()
        end
      end
      return
    end
    if event.id ~= current.id then return end
    if event.kind == "ACK" then
      if event.status == "REJECT" and current.accepted then
        current.unknown = true; actionOutcome, actionReason = "UNKNOWN", "CONTRADICTORY_ACK"
      elseif event.status == "REJECT" and event.reason ~= "OLD_TASK" and event.boot == current.robotBootId then
        conclude("BLOCKED", event.reason)
      elseif event.status == "NEW" or event.status == "DUP" then
        current.accepted = true; actionReason = "AWAITING_RESULT"
      else
        current.unknown = true; actionOutcome, actionReason = "UNKNOWN", "TASK_HISTORY_UNCERTAIN"
      end
    elseif event.kind == "STATUS" and event.boot == current.robotBootId and
        (event.status == "RUNNING" or event.status == "DONE") then
      current.accepted = true
    elseif event.kind == "RESULT" and event.boot == current.robotBootId then
      if current.reported and
          (current.reported ~= event.status or current.robotReason ~= event.reason) then
        current.unknown = true
      end
      current.reported, current.robotReason = event.status, event.reason
      current.targetFacts, current.sourceFacts = nil, nil
      current.accepted = true
      actionOutcome, actionReason = "PENDING", "INDEPENDENT_VERIFICATION_REQUIRED"
    elseif event.kind == "TRANSPORT_WAIT" then
      current.transportReason = event.reason
      if event.reason == "TASK_NOT_FOUND" then actionOutcome, actionReason = "UNKNOWN", "TASK_HISTORY_UNCERTAIN" end
    end
  end

  local function ioProblem(reason)
    ioState, ioFault = "UNCERTAIN", reason
    if reason == "IO_PAYLOAD_CONFLICT" then link.requestConnection(true) end
  end
  local function sendIo(kind, id, status, callId)
    return link.sendIo({ kind = kind, id = id, status = status, callId = callId, boot = robotBootId })
  end
  local function receiveIo(event)
    if not link or event.boot ~= link.snapshot().boot then return end
    if event.kind == "ROBOT_CONFIRMED" then
      if robotBootId ~= event.boot then
        if ioExchange and ioExchange.granted and not ioFault then sortingRequired = true end
        if ioFault == "IO_RECEIPT_CONFLICT" and ioReceipt and not ioExchange and
            not sortingRequired and not sortingReceipt and
            not inventory.fault() then
          ioState, ioFault = "UNKNOWN", nil
        end
        robotBootId, robotStatus = event.boot, nil
        localityCell = nil
        ioRequest, ioExchange, ioCall, ioReceipt, sortingReceipt = nil, nil, nil, nil, nil
        heldMaterial = nil; planKey = nil
        highestRequest, highestReceipt = 0, 0
        if ioState ~= "UNCERTAIN" then ioState = "UNKNOWN" end
      end
      return
    end
    if event.boot ~= robotBootId then return end
    if event.kind == "STATUS" and event.id == "*" then
      if startupStatusPending and event.status == "RUNNING" then startupWorkerRunning = true end
      if event.status == "READY" and robotStatus ~= "READY" then
        readySequence = readySequence + 1
        if enabled and startupStatusPending and startupWorkerRunning and not action and observation then
          observation.start()
          planKey = nil
        end
        if not action and lastAction and lastAction.outcome == "BLOCKED" and
            lastAction.readySequence ~= readySequence then
          if not lastAction.unprocessed then planKey = nil end
        end
      end
      if event.status == "READY" then startupStatusPending = false end
      robotStatus = event.status
    elseif event.kind == "IO_PROTOCOL_FAULT" then
      ioProblem(event.reason or "IO_PROTOCOL_FAULT")
    elseif event.kind == "IO_STATUS" then
      if event.ownership == "FAULT" then
        ioProblem("ROBOT_IO_FAULT"); return
      end
      if ioState == "UNCERTAIN" then
        local ungranted = ioRequest or (ioExchange and not ioExchange.granted and ioExchange)
        if ioFault == "IO_PAYLOAD_CONFLICT" and ungranted and
            event.ownership == "FREE" and event.id == "*" then
          ioState, ioFault = "STATION", nil
        else
          return
        end
      end
      local reportedNumber = Protocol.task(event.id)
      if event.ownership == "BUSY" and reportedNumber and reportedNumber <= highestReceipt then return end
      if ioExchange and ioExchange.granted then return end
      if ioState == "ROBOT" and event.ownership == "FREE" and
          not ioReceipt then
        return
      end
      if event.ownership == "FREE" and event.id == "*" then
        ioState = "STATION"
      elseif event.ownership == "BUSY" then
        ioState = "ROBOT"
      elseif event.ownership == "FREE" and event.id ~= "*" then
        if ioReceipt and event.id ~= ioReceipt.id then return end
        ioState = "STATION"
      end
      reportedExchangeId = event.id
    elseif event.kind == "IO_REQUEST" then
      if not enabled or fatal or ioState == "UNCERTAIN" then return end
      local number = Protocol.task(event.id)
      if not number then return end
      local tracked = (ioRequest and ioRequest.id == event.id and ioRequest) or
          (ioExchange and ioExchange.id == event.id and ioExchange)
      if tracked then
        if tracked.callSequence ~= event.callSequence then
          if not tracked.granted then tracked.reconfirm = true end
          ioProblem("IO_PAYLOAD_CONFLICT")
        elseif tracked.granted then
          sendIo("IO_GRANT", tracked.id, nil, tracked.callId)
        else
          tracked.reconfirm = nil
        end
        return
      end
      if number <= highestRequest or ioRequest or ioExchange then return end
      highestRequest = number
      ioRequest = { id = event.id, boot = event.boot, callSequence = event.callSequence }
    elseif event.kind == "IO_UNLOADED" then
      if ioReceipt and ioReceipt.id == event.id then
        if ioReceipt.status ~= event.status then
          ioProblem("IO_RECEIPT_CONFLICT")
        else
          sendIo("IO_ACK", event.id, event.status)
        end
        return
      end
      local number = Protocol.task(event.id)
      if not number or number <= highestReceipt then return end
      if not (ioExchange and ioExchange.granted and ioExchange.id == event.id) and
          not (not ioExchange and reportedExchangeId == event.id and ioState ~= "UNKNOWN") then
        return
      end
      highestReceipt = number
      localityCell = nil
      ioReceipt = {
        id = event.id,
        status = event.status,
        material = ioExchange and ioExchange.material
      }
      reportedExchangeId = event.id
      ioExchange = nil
      if ioState ~= "UNCERTAIN" then ioState = "STATION" end
      sortingRequired = true
      sendIo("IO_ACK", event.id, event.status)
    end
  end

  local function advanceInventory()
    if not inventory or fatal then return end
    inventory.step(enabled and ioState == "STATION",
      enabled and ioState ~= "ROBOT" and ioState ~= "UNCERTAIN" and
      (not reportedExchangeId or reportedExchangeId == "*") and
      not ioRequest and not ioExchange and not ioCall and not sortingRequired)
    if not enabled then return end
    local current = inventory.snapshot()
    if current.fault then
      ioProblem(current.fault); return
    end
    if current.phase == "DONE" then
      local kind = current.kind
      local failure = current.failure
      local resultMaterial = current.material
      local taken = current.plantingItemTaken
      inventory.release()
      if kind == "PREPARE_EXCHANGE" then
        if failure then
          if ioCall then ioCall = nil end
          if ioExchange and not ioExchange.granted then
            ioRequest = ioExchange; ioExchange = nil
          end
        elseif ioExchange and ioExchange.phase == "PREPARING" and ioExchange.boot == robotBootId then
          ioExchange.phase = "PREPARED"
          ioExchange.material = resultMaterial
        elseif ioCall and ioCall.phase == "PREPARING" then
          ioCall.material = resultMaterial
          ioCall.phase = "CALLING"; ioCall.sent = -math.huge
        end
      elseif kind == "SORT_CARGO" then
        if not failure and sortingReceipt and sortingReceipt.status == "SUCCESS" then
          batchExtractions, batchOrderId = 0, nil
        end
        if sortingReceipt and sortingReceipt.status == "SUCCESS" and taken and sortingReceipt.material then
          local material = sortingReceipt.material
          heldMaterial = {
            key = material.key,
            itemKind = material.itemKind,
            g = material.g,
            ga = material.ga,
            r =
                material.r
          }
        end
        sortingReceipt = nil
        planKey = nil
      end
      current = inventory.snapshot()
    end
    if ioCall and ioCall.phase == "CALLING" and now() - ioCall.sent >= 3 then
      ioCall.sent = now(); sendIo("IO_CALL", ioCall.id)
    end
    if not current.prepared or current.busy or ioState ~= "STATION" then return end
    if ioExchange and ioExchange.phase == "PREPARED" and not ioExchange.reconfirm and
        ioExchange.boot == robotBootId and link.snapshot().networkReady then
      if ioExchange.material then heldMaterial = nil end
      ioExchange.granted = true
      ioExchange.callId = ioCall and ioCall.id
      ioCall = nil; ioState = "ROBOT"
      sendIo("IO_GRANT", ioExchange.id, nil, ioExchange.callId)
      return
    end
    if sortingRequired then
      if inventory.sortCargo() then
        sortingRequired = false
        sortingReceipt = ioReceipt and { id = ioReceipt.id, status = ioReceipt.status, material = ioReceipt.material }
        if ioReceipt then ioReceipt.material = nil end
      end
      return
    end
    if ioRequest and not ioRequest.reconfirm and not ioExchange and not action and link.snapshot().networkReady and
        (not ioCall or ioCall.phase == "CALLING") then
      ioExchange = ioRequest; ioRequest = nil
      ioExchange.phase = "PREPARING"
      if ioCall and ioCall.phase == "CALLING" then
        ioExchange.granted = true
        ioExchange.callId = ioCall.id; ioExchange.material = ioCall.material
        if ioExchange.material then heldMaterial = nil end
        ioCall = nil; ioState = "ROBOT"
        sendIo("IO_GRANT", ioExchange.id, nil, ioExchange.callId)
      elseif not inventory.prepareExchange() then
        ioRequest = ioExchange; ioExchange = nil
      end
    end
  end
  local function receiveLinkEvent(event)
    if event.kind == "PAIR_RESET" then
      robotBootId, robotStatus, heldMaterial, reportedExchangeId = nil, nil, nil, nil
      localityCell = nil
      ioState = "UNKNOWN"; planKey = nil
      if observation then observation.resetRobot() end
      return
    end
    if event.boot and event.boot ~= link.snapshot().boot then
      if event.kind == "ROBOT_CONFIRMED" then actionEvent(event) end
      return
    end
    if action then actionEvent(event) end
    if event.kind == "ROBOT_CONFIRMED" and robotBootId and event.boot ~= robotBootId and observation then
      observation.resetRobot()
    end
    receiveIo(event)
    if event.kind == "SYNC_REQUEST" and enabled and not fatal and
        not (action and action.robotBootId == event.boot) and
        not (ioExchange and ioExchange.granted) then
      local success, reason = observation.requestRobot(event.id, event.boot)
      if not success then link.positionReply({ id = event.id, boot = event.boot, error = reason }) end
    end
  end
  local function receiveLink()
    if not link then return end
    if link.snapshot().queueFault then
      api.fail("LINK_QUEUE_FULL"); return
    end
    for _ = 1, 32 do
      local event = link.poll()
      if not event then return end
      receiveLinkEvent(event)
    end
  end

  local function orderCommand(request)
    local candidate = copyState()
    local editedActive = false
    if request.kind == "ORDER_CREATE" then
      if candidate.nextOrderId >= State.maxInteger then return nil, "ORDER_ID_EXHAUSTED" end
      if #candidate.orders >= State.maxOrders then
        local oldest
        for index, order in ipairs(candidate.orders) do
          if order.status == "CLOSED" and (not oldest or order.id < candidate.orders[oldest].id) then oldest = index end
        end
        if not oldest then return nil, "ORDER_LIMIT" end
        table.remove(candidate.orders, oldest)
      end
      local details = request.details
      candidate.orders[#candidate.orders + 1] = {
        id = candidate.nextOrderId,
        owner = details.owner,
        cropId = details.cropId,
        g = details.g,
        ga = details.ga,
        r = details.r,
        K = details.K or 1,
        status = "QUEUED",
        produced = 0
      }
      candidate.nextOrderId = candidate.nextOrderId + 1
    elseif request.kind == "ORDER_EDIT" then
      local details = request.details
      local order = findOrder(candidate.orders, details.id)
      if not order or order.status == "CLOSED" then return nil, "ORDER_NOT_EDITABLE" end
      editedActive = order.status == "ACTIVE"
      if (editedActive or details.resetProduced ~= nil) and type(details.resetProduced) ~= "boolean" then
        return nil, "ORDER_PROGRESS_CHOICE_REQUIRED"
      end
      local changed = false
      for _, field in ipairs({ "owner", "cropId", "K", "g", "ga", "r" }) do
        if order[field] ~= details[field] then changed = true end
        order[field] = details[field]
      end
      if editedActive and details.resetProduced and order.produced ~= 0 then
        order.produced = 0; changed = true
      end
      if editedActive and Protocol.integer(order.K, 1, State.maxInteger) then
        if order.K < order.produced then return nil, "ORDER_QUANTITY_BELOW_PRODUCED" end
        if order.K == order.produced then closeOrder(candidate, order.id) end
      end
      if not changed then return true end
    elseif request.kind == "ORDER_CANCEL" then
      local changed, reason = closeOrder(candidate, request.details.id)
      if changed == false and not reason then return true end
      if not changed then return nil, reason end
    end
    local valid, reason = State.validate(candidate)
    if not valid then return nil, "ORDER_INVALID_" .. tostring(reason) end
    return save(candidate, editedActive)
  end
  local function processCommand(request)
    if request.kind == "ORDER_CREATE" or request.kind == "ORDER_EDIT" or request.kind == "ORDER_CANCEL" then
      local success, reason = orderCommand(request)
      if not success then
        uiDiagnostic = reason
      else
        uiDiagnostic = nil
        if link and enabled then link.requestConnection(false, true) end
      end
      return
    end
    if request.kind == "PAIR_RESET" then
      local network = link.snapshot()
      if not enabled and not resetBlocked() and network.robotAddress == request.details.address then
        local success, reason = link.command("PAIR_RESET")
        if not success then uiDiagnostic = reason end
      else
        uiDiagnostic = "PAIR_REQUIRES_STOPPED"
      end
      return
    end
    if request.kind == "PAIR_OPEN" or request.kind == "PAIR_CLOSE" or request.kind == "PAIR_SELECT" then
      if not enabled and (request.kind == "PAIR_CLOSE" or not outstanding()) then
        local success, reason = link.command(request.kind, request.details)
        if not success then uiDiagnostic = reason end
      else
        uiDiagnostic = "PAIR_REQUIRES_STOPPED"
      end
      return
    end
    if request.kind == "START" then
      if fatal or enabled or (link and link.snapshot().pairing) then return end
      clearPlanDisplay()
      enabled = true; planKey = nil; admission = nil
      if not (step and step.action) then step = nil end
      startupStatusPending = robotStatus ~= "READY"
      startupWorkerRunning = robotStatus == "RUNNING"
      blocker, diagnostic = "OBSERVATION_PENDING", "OBSERVATION_PENDING"
      if link then link.requestConnection(true) end
      if observation then observation.start() end
      return
    end
    if request.kind == "IO_CALL" then
      if not enabled or not inventory or action or ioCall or ioRequest or ioExchange or
          not ready() or inventory.snapshot().busy or not inventory.snapshot().prepared then
        uiDiagnostic = "IO_NOT_READY"; return
      end
      if callSequence >= Protocol.maxInt then
        api.fail("IO_CALL_SEQUENCE_EXHAUSTED"); return
      end
      callSequence = callSequence + 1
      local id = "call:" .. callSequence
      local success, reason = inventory.prepareExchange(request.slot, request.material)
      if success then
        ioCall = { id = id, phase = "PREPARING", sent = -math.huge, material = request.material }
      else
        uiDiagnostic = reason
      end
    end
  end

  stamp = function(observationRevision)
    local order = activeOrder()
    local held = heldMaterial
    return table.concat({ observationRevision or observation.planningRevision(), inventory.planningRevision(),
      state.revision, order and order.id or "*", robotBootId or "*",
      held and (held.key .. ":" .. held.itemKind .. ":" .. tostring(held.g) .. ":" ..
        tostring(held.ga) .. ":" .. tostring(held.r)) or "*",
      step and step.kind or "*" }, "|")
  end
  function api.connectionNeeded()
    if not enabled or fatal then return false end
    if action or admission or ioRequest or ioExchange or ioCall or sortingRequired or
        sortingReceipt or planStatus.calculating then
      return true
    end
    return state ~= nil and observation ~= nil and inventory ~= nil and activeOrder() ~= nil and
        planKey ~= stamp()
  end

  local function doAction(nextDecision, observed)
    local selected = nextDecision.action
    local name, from, to = selected.name, selected.from or 0, selected.to
    local safety = nextDecision.need == "SAFETY"
    if not safety and batchDue() then return nil, "IO_PREPARING" end
    if not ready(nil, safety) then return nil, "ROBOT_OR_IO_WAIT" end
    local harvest = nextDecision.need == "QUANTITY" and nextDecision.purpose == "QUANTITY_RESULT" and
        (name == "COLLECT_AND_CLEAR_CELL" or name == "COLLECT_AND_RESTORE_DOUBLE")
    local target, reason, variant = validatedCell(name, to, harvest)
    if not target then return nil, reason end
    if not Protocol.parameters(name, from, to, variant) then return nil, "INVALID_ACTION" end
    local source, expected
    if name == "EXTRACT_AND_PLANT" then
      source, expected, reason = donor(from)
      if not source then return nil, reason end
    elseif name == "PLANT_SEED" then
      if not heldMaterial then return nil, "PLANTING_MATERIAL_REQUIRED" end
      local g, ga, r = Quantity.plantGenes(heldMaterial)
      expected = { key = heldMaterial.key, g = g, ga = ga, r = r }
    end
    if nextActionId > Protocol.maxInt then return nil, "ACTION_ID_EXHAUSTED" end
    local boot = link.snapshot().boot
    local id = tostring(nextActionId); nextActionId = nextActionId + 1
    action = {
      id = id,
      stationBootId = link.snapshot().stationBootId,
      robotBootId = boot,
      name = name,
      from = from,
      to = to,
      variant = variant,
      emergency = safety,
      before = target,
      sourceBefore = source,
      expected = expected,
      rotation = observed.rotation,
      step = nextDecision.step
    }
    if harvest then
      action.quantityOrderId = activeOrder().id
    end
    local success, sendError = link.sendAction(id, name, from, to, variant, safety)
    if not success then
      action = nil; return nil, sendError
    end
    blocker, diagnostic = nil, nil
    actionOutcome, actionReason = "PENDING", "AWAITING_ROBOT"
    return true
  end
  local function requestAdmission(cell, selected, selectionKey, revision, version, rotation)
    admission = {
      cell = cell,
      selected = selected,
      key = selectionKey,
      revision = revision or observation.planningRevision(),
      version = version,
      rotation = rotation
    }
    verificationSequence = verificationSequence + 1
    local token = "admission:" .. verificationSequence
    local accepted, reason = observation.forceScan(cell, "ADMISSION_SOIL", token)
    if accepted then
      admission.token = token
    elseif reason ~= "CELL_BUSY" and reason ~= "QUEUE_FULL" then
      admission = nil; blocker, diagnostic = reason or "ADMISSION_SCAN_UNAVAILABLE",
          reason or "ADMISSION_SCAN_UNAVAILABLE"
    end
  end
  local function plan()
    if not enabled or fatal or not observation or not inventory or not link or action then return end
    local observed, stock, linkState = observation.status(), inventory.snapshot(), link.snapshot()
    if not observed.ready or observed.queueFault or observed.rotation == nil then
      blocker, diagnostic = "OBSERVATION_PENDING", "OBSERVATION_PENDING"; return
    end
    if observed.sensorInvalid > 0 or observed.dockError then
      blocker, diagnostic = observed.dockError or "SENSOR_UNAVAILABLE", observed.dockError or "SENSOR_UNAVAILABLE"
      return
    end
    if stock.fault or ioState == "UNCERTAIN" then
      blocker, diagnostic = stock.fault or ioFault or "IO_ACCESS_UNCERTAIN",
          stock.fault or ioFault or "IO_ACCESS_UNCERTAIN"
      return
    end
    if batchDue() and (observed.dangers or 0) == 0 then
      if not stock.prepared or stock.busy or not ready(linkState) then
        if not linkState.networkReady then link.requestConnection() end
        blocker, diagnostic = stock.waiting or "IO_PREPARING", stock.waiting or "IO_PREPARING"
      else
        local batchKey = "BATCH|" .. stamp()
        if planKey ~= batchKey then
          planKey = batchKey
          processCommand({ kind = "IO_CALL" })
        end
      end
      return
    end
    if not activeOrder() and observed.dangers == 0 and
        stock.stickReady == true and planKey == stamp() and
        planStatus.kind == "IDLE" and planStatus.reason == "NO_ACTIVE_ORDER" then
      planStatus = { kind = "IDLE", phase = "EMPTY", reason = "NO_ACTIVE_ORDER" }
      blocker, diagnostic = nil, nil
      return
    end
    local inventoryBlocking = stock.busy and not stock.backgroundRead
    local safetyDuringLocalWork = observed.dangers > 0 and ioState == "STATION" and
        (not ioCall or ioCall.phase == "PREPARING") and not ioRequest and not ioExchange and
        (inventoryBlocking or sortingRequired or sortingReceipt)
    if (not stock.prepared and not safetyDuringLocalWork) or (inventoryBlocking and not safetyDuringLocalWork) or
        (ioCall and not safetyDuringLocalWork) or ioRequest or ioExchange or
        (sortingRequired and not safetyDuringLocalWork) then
      blocker, diagnostic = stock.waiting or "IO_PREPARING", stock.waiting or "IO_PREPARING"
      return
    end
    if admission then return end
    if not ready(linkState, safetyDuringLocalWork) then
      if not linkState.networkReady then link.requestConnection() end
      blocker, diagnostic = "ROBOT_OR_IO_WAIT", "ROBOT_OR_IO_WAIT"
      return
    end
    local stockAwait = stock.stickReady ~= true
    local currentStamp = stamp()
    if planKey == currentStamp and not (lastAction and lastAction.unprocessed) then
      if stockAwait then
        blocker, diagnostic = "CROP_STICKS", "CROP_STICKS"
      elseif blocker == "IO_PREPARING" or blocker == "ROBOT_OR_IO_WAIT" or
          blocker == "OBSERVATION_PENDING" or blocker == "CROP_STICKS" then
        local reason = planStatus.kind == "BLOCKED" and planStatus.reason or nil
        blocker, diagnostic = reason, reason
      end
      return
    end
    if stockAwait and observed.dangers == 0 then
      planKey = currentStamp
      blocker, diagnostic = "CROP_STICKS", "CROP_STICKS"
      return
    end
    local field = {}
    for cell = 1, 36 do
      local facts = observation.snapshot(cell); field[cell] = facts
    end
    local order = activeOrder()
    local orderView = order and {
      id = order.id,
      key = order.owner .. ":" .. order.cropId,
      g = order.g,
      ga = order.ga,
      r = order.r,
      K = order.K,
      produced = order.produced
    }
    local fieldRevision, bankRevision, stateRevision = observation.planningRevision(),
        inventory.planningRevision(), state.revision
    local selectedBoot, stopAt = robotBootId, stopRevision
    local function current()
      return enabled and not fatal and stopRevision == stopAt and
          observation.planningRevision() == fieldRevision and
          inventory.planningRevision() == bankRevision and state.revision == stateRevision and
          robotBootId == selectedBoot and ready(nil, safetyDuringLocalWork)
    end
    local sameRefusal = lastAction and lastAction.unprocessed and planKey == currentStamp
    local refusal
    if sameRefusal then
      refusal = {
        name = lastAction.name,
        from = lastAction.from,
        to = lastAction.cell,
        reason = lastAction.robotReason or lastAction.reason,
        scope = lastAction.outcome == "NO_CHANGE" and "exact" or "kind"
      }
    end
    clearPlanDisplay()
    planStatus.calculating = true
    local selected = Planner.next({
      order = orderView,
      field = field,
      bank = inventory.catalogue(),
      material = heldMaterial,
      archiveDisposition = inventory.archiveDisposition,
      refusal = refusal,
      localityCell = localityCell
    }, step, routeMemo, function()
      if plannerYield then plannerYield() end
      if link.pendingEvents() > 0 then receiveLink() end
      return current()
    end)
    planStatus.calculating = false
    if not current() then return end
    if selected.discardStep then step = nil end
    if lastAction then lastAction.unprocessed = nil end
    planKey = currentStamp
    planStatus = {
      kind = selected.kind,
      phase = selected.need or "IDLE",
      reason = selected.reason,
      orderId = order and order.id,
      routeFrom = selected.routeFrom,
      routeTo = selected.routeTo,
      genetics = selected.genetics
    }
    if safetyDuringLocalWork and selected.need ~= "SAFETY" then
      blocker, diagnostic = stock.waiting or "IO_PREPARING", stock.waiting or "IO_PREPARING"
      return
    end
    if selected.kind == "ACTION" then
      if stockAwait and selected.need ~= "SAFETY" then
        blocker, diagnostic = "CROP_STICKS", "CROP_STICKS"
        return
      end
      local success, reason = doAction(selected, observed)
      if not success and reason == "SOIL_OBSERVATION_STALE" then
        local target = field[selected.action.to]
        requestAdmission(selected.action.to, selected, currentStamp,
          fieldRevision, target.version, observed.rotation)
      elseif not success then
        blocker, diagnostic = reason, reason
      end
    elseif selected.kind == "MATERIAL" then
      if selected.slot and selected.expected then
        queue({ kind = "IO_CALL", slot = selected.slot, material = selected.expected })
      end
    elseif stockAwait then
      blocker, diagnostic = "CROP_STICKS", "CROP_STICKS"
    elseif selected.kind == "BLOCKED" then
      blocker, diagnostic = selected.reason, selected.reason
    else
      blocker, diagnostic = nil, nil
    end
  end

  function api.step()
    if observation then
      local observed = observation.status()
      if observed.queueFault then
        api.fail("OBSERVATION_QUEUE_FULL"); return
      end
      local event = observation.poll()
      if event then
        if event.kind == "ROBOT_POSITION" and link then link.positionReply(event) end
        if action then actionEvent(event) end
        if event.kind == "SCAN_RESULT" and admission and event.token == admission.token then
          local pending = admission
          admission = nil
          if not event.ok then
            blocker, diagnostic = event.error or "ADMISSION_SCAN_FAILED", event.error or "ADMISSION_SCAN_FAILED"
            if observation.planningRevision() == pending.revision then planKey = stamp() else planKey = nil end
          else
            local facts = observation.snapshot(pending.cell)
            local observed = observation.status()
            if facts and facts.version == pending.version and
                facts.soilChecked and facts.soil == "minecraft:farmland" and observed.rotation == pending.rotation and
                observation.planningRevision() == pending.revision and
                stamp(pending.revision) == pending.key then
              local success, reason = doAction(pending.selected, observed)
              if not success then
                blocker, diagnostic = reason, reason
                if reason == "ROBOT_OR_IO_WAIT" then planKey = nil end
              end
            else
              planKey = nil
            end
          end
        end
      end
    end
    receiveLink()
    if admission and (observation.planningRevision() ~= admission.revision or
          observation.rotation() ~= admission.rotation or
          stamp(admission.revision) ~= admission.key or not ready()) then
      admission = nil; planKey = nil
    end
    if action and (action.reported or action.recoveryBoot and
          action.recoveryBoot == robotBootId and ioState == "STATION") and not action.verifyToken and enabled and
        (not action.verifyAfter or now() >= action.verifyAfter) then
      if action.targetFacts and not action.unknown and action.reported ~= "UNKNOWN" and
          action.verificationRevision ~= observation.planningRevision() then
        action.verificationRevision = observation.planningRevision()
        local targetFacts = observation.snapshot(action.to)
        local sourceFacts = action.sourceFacts and observation.snapshot(action.from)
        if targetFacts.version ~= action.targetFacts.version or
            sourceFacts and sourceFacts.version ~= action.sourceFacts.version then
          action.targetFacts, action.sourceFacts = nil, nil
        end
      end
      local target = not action.targetFacts and action.to or
          action.name == "EXTRACT_AND_PLANT" and not action.sourceFacts and action.from
      if target then
        verificationSequence = verificationSequence + 1
        local token = "verify:" .. action.id .. ":" .. verificationSequence
        if observation.forceScan(target, "ACTION_VERIFY", token) then
          action.verifyToken = token
        end
      end
    end
    if inventory then advanceInventory() end
    if admission and not admission.token and enabled then
      verificationSequence = verificationSequence + 1
      local token = "admission:" .. verificationSequence
      local accepted, reason = observation.forceScan(admission.cell, "ADMISSION_SOIL", token)
      if accepted then
        admission.token = token
      elseif reason ~= "CELL_BUSY" and reason ~= "QUEUE_FULL" then
        admission = nil; planKey = stamp(); blocker, diagnostic = reason, reason
      end
    end
    if enabled and action then
      blocker = actionOutcome == "UNKNOWN" and actionReason or nil
    end
    if #inbox > 0 then
      local stock = inventory and inventory.snapshot()
      local callReady = not action and ready() and stock and stock.prepared and not stock.busy
      local selected
      for index, command in ipairs(inbox) do
        if command.kind ~= "IO_CALL" or not enabled or callReady then
          selected = index; break
        end
      end
      if selected then
        processCommand(table.remove(inbox, selected)); return
      end
    end
    local order = state and activeOrder()
    if enabled and order == nil and state then
      for _, entry in ipairs(state.orders) do
        if entry.status == "QUEUED" then
          local candidate = copyState()
          nextQueued(candidate); save(candidate)
          return
        end
      end
    end
    plan()
  end

  function api.statusSnapshot(terrainCrop, queuedOrderLimit)
    local observed = observation and observation.status(terrainCrop)
    local network = link and link.snapshot()
    local orders = {}
    local canCreateOrder = not state or #state.orders < 20
    local queuedOrders = 0
    if state then
      for _, order in ipairs(state.orders) do
        if order.status == "CLOSED" then canCreateOrder = true end
        if order.status == "QUEUED" then queuedOrders = queuedOrders + 1 end
        if queuedOrderLimit == nil or order.status == "ACTIVE" or
            order.status == "QUEUED" and queuedOrders <= queuedOrderLimit then
          local row = {}; for field, value in pairs(order) do row[field] = value end; orders[#orders + 1] = row
        end
      end
    end
    local workPending = (state and activeOrder()) ~= nil or action ~= nil or
        ioRequest ~= nil or ioExchange ~= nil or ioCall ~= nil
    return {
      enabled = enabled,
      work_pending = workPending,
      blocker = blocker,
      label = Control.label(enabled, workPending, blocker),
      diagnostic = diagnostic,
      queued = #inbox,
      physicalReady = ready(network) == true,
      action = {
        task = action and action.id,
        name = action and action.name,
        cell = action and action.to,
        from = action and action.from,
        emergency = action and action.emergency,
        boot = action and action.robotBootId,
        reported = action and action.reported,
        outcome = actionOutcome,
        reason = actionReason,
        transportReason = action and action.transportReason,
        lastAction = lastAction
      },
      observationReady = enabled and observed and observed.ready or false,
      inventory = inventory and inventory.snapshot(),
      planner = planStatus,
      ioAccessState = ioState,
      ioAccessFault = ioFault,
      ioCallPending = ioCall ~= nil,
      ioRequestPending = ioRequest ~= nil,
      ioExchangeGranted = ioExchange and ioExchange.granted or false,
      ioReceiptPending = ioReceipt ~= nil,
      sortingReceiptPending = sortingReceipt ~= nil,
      robotBootId = robotBootId,
      robotStatus = robotStatus,
      orders = orders,
      canCreateOrder = canCreateOrder,
      uiDiagnostic = uiDiagnostic,
      observation = observed,
      link = network
    }
  end

  function api.ioActive()
    return enabled and not fatal and inventory and inventory.busy() or false
  end

  return api
end

return Control
