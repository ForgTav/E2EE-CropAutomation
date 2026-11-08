local LinkProtocol = require("shared_link")
local RobotApp = {}
function RobotApp.new(deps, pairingRequested)
  local transport, now, linkStore = deps.transport, deps.now, deps.store
  local robotAddress, robotBootId = transport.address, deps.boot
  local pairingCode = deps.code
  assert(LinkProtocol.address(robotAddress))
  local linkConfig, linkConfigError = linkStore.load()
  local pairingAnnouncementsEnabled = pairingRequested or linkConfigError == "LINK_MISSING"
  local pairingAttempt, stationBootId, handshakeOffer, lastAction, highestActionId = nil, nil, nil, nil, 0
  local lastRejectionReason
  local connectionConfirmed, lastHandshakeAt, lastAnnouncementAt, announcementSequence = false, 0, -math.huge, 0
  local lastWakeAt = -math.huge
  local wakeRetryDelay = 3
  local api = {}
  local executor, navigation = deps.executor, deps.nav
  local positionSequence, positionRequest = 0, nil
  local localizationFailed = false
  local lastPublishedStatus
  local statusReplies = {}
  local robotInventory, stationEnabled
  local highestPingSequence, challengeSequence = 0, 0
  local confirmedChallenge
  local energyAllowsWork, energyReturnRequired, energyError = false, false, "ENERGY_UNREADABLE"
  local cachedEnergyRatio, cachedEnergyError, lastEnergyReadAt = nil, "ENERGY_UNREADABLE", -math.huge
  local function checkEnergy(forceRefresh)
    local checkedAt = now()
    if forceRefresh or checkedAt - lastEnergyReadAt >= 5 then
      cachedEnergyRatio, cachedEnergyError = navigation.energy()
      lastEnergyReadAt = checkedAt
    end
    local atHome = navigation.snapshot().atHome
    energyAllowsWork = cachedEnergyRatio ~= nil and
        (atHome and cachedEnergyRatio >= 0.80 or not atHome and cachedEnergyRatio > 0.40)
    energyReturnRequired = cachedEnergyRatio ~= nil and cachedEnergyRatio <= 0.40
    energyError = cachedEnergyError or (not energyAllowsWork and "ENERGY_CHARGING" or nil)
  end
  if deps.robotHardware and deps.inventory and navigation then
    robotInventory = require("robot_io").new({
      robot = deps.robotHardware,
      inventory = deps.inventory,
      nav = navigation,
      now = now,
      requiredSticks = function() return 4 end,
      send = function(kind, exchangeId, exchangeStatus, exchangeDetail)
        if not linkConfig or not connectionConfirmed or now() - lastHandshakeAt > 9 or (kind == "IO_REQUEST" and not stationEnabled) then return false end
        return transport.send(linkConfig.peer_modem, LinkProtocol.dataPort, linkConfig.link_id,
          LinkProtocol.route(robotBootId, stationBootId), kind, exchangeId, exchangeStatus, exchangeDetail, robotBootId)
      end
    })
    executor.attachInventory(robotInventory)
  end
  function api.inventoryChanged(slot) if robotInventory then robotInventory.changed(slot) end end

  function api.resetPairing()
    local navigationState = navigation and navigation.snapshot()
    if lastAction and not lastAction.done or executor and executor.busy() or
        navigationState and (navigationState.moving or navigationState.localizing) then
      return nil, "ROBOT_BUSY"
    end
    if robotInventory then
      local ownership, receiptId = robotInventory.ownership()
      if ownership ~= "FREE" or receiptId ~= "*" or robotInventory.reserved() then return nil, "IO_BUSY" end
    end
    local removed, removeError = linkStore.remove()
    if not removed then
      linkConfigError = removeError; return nil, removeError
    end
    linkConfig, linkConfigError = nil, "LINK_MISSING"
    pairingCode = string.format("%04d", (tonumber(pairingCode) + 1) % 10000)
    pairingRequested, pairingAnnouncementsEnabled = false, true
    pairingAttempt, handshakeOffer, confirmedChallenge = nil, nil, nil
    connectionConfirmed, stationEnabled = false, false
    lastAnnouncementAt = -math.huge
    return true
  end

  local function send(incomingFrame, kind, id, payloadA, payloadB, payloadC)
    return transport.send(incomingFrame.senderAddress, incomingFrame.port, incomingFrame.link,
      LinkProtocol.route(robotBootId, incomingFrame.senderBoot), kind, id, payloadA, payloadB, payloadC)
  end
  local function replay(incomingFrame)
    send(incomingFrame, "RESULT", lastAction.id, lastAction.result, lastAction.reason, robotBootId)
  end
  local function workReady(emergency)
    if not executor or not navigation then return nil, "HARDWARE_UNAVAILABLE" end
    if (lastAction and not lastAction.done) or executor.busy() then return nil, "ACTION_BUSY" end
    local navigationReady, navigationError = navigation.workReady()
    if not navigationReady then return nil, navigationError end
    if robotInventory and robotInventory.reserved() and not
        (emergency ~= false and robotInventory.isNormalized() and robotInventory.awaitingGrant()) then
      return nil, "IO_BUSY"
    end
    checkEnergy(false)
    if not energyAllowsWork then return nil, energyError end
    return true
  end
  local function navigationAvailable()
    return not robotInventory or not robotInventory.reserved() or robotInventory.recoveringStartup()
  end
  local lastIoStatusSignature
  local function ioStatus(incomingFrame, ownershipStatus, exchangeId)
    if not ownershipStatus then
      ownershipStatus, exchangeId = "FREE", "*"
      if robotInventory then ownershipStatus, exchangeId = robotInventory.ownership() end
    end
    local ownershipSignature = tostring(stationBootId) .. "|" .. ownershipStatus .. "|" .. exchangeId
    if not incomingFrame then
      return ownershipSignature ~= lastIoStatusSignature,
          ownershipStatus == "BUSY" or exchangeId ~= "*"
    end
    send(incomingFrame, "IO_STATUS", exchangeId, ownershipStatus, confirmedChallenge, robotBootId)
    lastIoStatusSignature = ownershipSignature
  end
  local function status(incomingFrame)
    local taskNumber = LinkProtocol.task(incomingFrame.id)
    local reportedStatus, rejectionReason
    if not taskNumber then
      reportedStatus = lastAction and not lastAction.done and "RUNNING" or (workReady() and "READY" or "UNSYNCED")
    elseif lastAction and lastAction.stationBootId == incomingFrame.senderBoot and incomingFrame.id == lastAction.id then
      reportedStatus = lastAction.done and "DONE" or "RUNNING"
    else
      if incomingFrame.a == "FENCE" and taskNumber > highestActionId then
        highestActionId, lastRejectionReason = taskNumber, "NOT_ACCEPTED"
      end
      if taskNumber == highestActionId and lastRejectionReason then
        reportedStatus, rejectionReason = "REJECT", lastRejectionReason
      else
        reportedStatus = taskNumber > highestActionId and "UNSEEN" or "NOT_FOUND"
      end
    end
    local ownershipStatus, exchangeId = "FREE", "*"
    if robotInventory then ownershipStatus, exchangeId = robotInventory.ownership() end
    local reportedActionId = lastAction and lastAction.stationBootId == incomingFrame.senderBoot and lastAction.id or ""
    local actionDone = lastAction and lastAction.done or false
    local resultStatus = actionDone and lastAction.result or nil
    local resultReason = actionDone and lastAction.reason or nil
    local replyRole = taskNumber and reportedStatus or (incomingFrame.id == "*" and "GENERAL" or "HANDSHAKE")
    local previousReply = statusReplies[replyRole]
    local replyAt = now()
    if previousReply and replyAt - previousReply.at < 1 and previousReply.boot == incomingFrame.senderBoot and
        previousReply.challenge == incomingFrame.c and previousReply.status == (not taskNumber and reportedStatus or nil) and
        previousReply.actionId == reportedActionId and previousReply.result == resultStatus and
        previousReply.actionDone == actionDone and previousReply.highestActionId == highestActionId and
        previousReply.rejectionReason == lastRejectionReason and
        previousReply.reason == resultReason and previousReply.ownership == ownershipStatus and
        previousReply.exchangeId == exchangeId then
      return
    end
    statusReplies[replyRole] = {
      at = replyAt,
      boot = incomingFrame.senderBoot,
      challenge = incomingFrame.c,
      status = not taskNumber and reportedStatus or nil,
      actionId = reportedActionId,
      actionDone = actionDone,
      highestActionId = highestActionId,
      rejectionReason = lastRejectionReason,
      result = resultStatus,
      reason = resultReason,
      ownership = ownershipStatus,
      exchangeId = exchangeId
    }
    if rejectionReason then
      send(incomingFrame, "ACK", incomingFrame.id, "REJECT", rejectionReason, robotBootId)
      ioStatus(incomingFrame, ownershipStatus, exchangeId)
      return
    end
    if not taskNumber then lastPublishedStatus = reportedStatus end
    send(incomingFrame, "STATUS", incomingFrame.id, reportedStatus, reportedActionId, robotBootId)
    ioStatus(incomingFrame, ownershipStatus, exchangeId)
    if lastAction and lastAction.done and lastAction.stationBootId == incomingFrame.senderBoot and incomingFrame.id == lastAction.id then
      replay(incomingFrame)
    end
  end
  function api.receive(localAddress, stationAddress, port, _, ...)
    local incomingFrame = LinkProtocol.frame(robotAddress, localAddress, stationAddress, port, ...)
    if not incomingFrame then return end
    if LinkProtocol.isPairKind(incomingFrame.kind) then
      if pairingAttempt and pairingAttempt.saved and now() < pairingAttempt.deadline and incomingFrame.senderAddress == pairingAttempt.stationAddress and incomingFrame.link == pairingAttempt.link and
          incomingFrame.targetBoot == robotBootId and incomingFrame.senderBoot == pairingAttempt.boot and incomingFrame.id == pairingAttempt.id and incomingFrame.kind == "PAIR_CONFIRM" and
          incomingFrame.a == "COMMIT" and incomingFrame.b == robotBootId and incomingFrame.c == pairingCode then
        send(incomingFrame, "PAIR_DONE", incomingFrame.id, "SAVED", robotBootId, pairingCode); return
      end
      if incomingFrame.targetBoot ~= robotBootId or not pairingAnnouncementsEnabled then return end
      if incomingFrame.kind == "PAIR_SELECT" then
        if incomingFrame.link ~= incomingFrame.senderAddress .. "|" .. robotAddress or incomingFrame.a ~= pairingCode or incomingFrame.b ~= robotBootId or incomingFrame.c ~= robotAddress then return end
        if pairingAttempt then
          if pairingAttempt.stationAddress == incomingFrame.senderAddress and pairingAttempt.id == incomingFrame.id then
            if now() >= pairingAttempt.deadline then return end
          elseif now() < pairingAttempt.deadline then
            return
          else
            pairingAttempt = nil
          end
        end
        if not pairingAttempt then
          pairingAttempt = {
            stationAddress = incomingFrame.senderAddress,
            id = incomingFrame
                .id,
            link = incomingFrame.link,
            boot = incomingFrame.senderBoot,
            deadline = now() + LinkProtocol.pairTimeout
          }
        end
        connectionConfirmed = false
        send(incomingFrame, "PAIR_CONFIRM", incomingFrame.id, "OFFER", robotBootId, pairingCode)
      elseif incomingFrame.kind == "PAIR_CONFIRM" and pairingAttempt and now() < pairingAttempt.deadline and
          incomingFrame.senderAddress == pairingAttempt.stationAddress and incomingFrame.senderBoot == pairingAttempt.boot and incomingFrame.id == pairingAttempt.id and incomingFrame.link == pairingAttempt.link and
          incomingFrame.a == "COMMIT" and incomingFrame.b == robotBootId and incomingFrame.c == pairingCode then
        local pairingConfig = LinkProtocol.config("robot", robotAddress, incomingFrame.senderAddress, incomingFrame.link)
        local success, operationError = linkStore.save(pairingConfig, pairingRequested == true)
        if not success then
          linkConfigError = operationError; pairingAnnouncementsEnabled = false; connectionConfirmed = false; pairingAttempt = nil; return
        end
        linkConfig, linkConfigError, pairingRequested = pairingConfig, nil, false
        pairingAttempt.saved = true; pairingAnnouncementsEnabled = false; connectionConfirmed = false; handshakeOffer = nil
        send(incomingFrame, "PAIR_DONE", incomingFrame.id, "SAVED", robotBootId, pairingCode)
      end
      return
    end
    if not linkConfig or pairingRequested or incomingFrame.senderAddress ~= linkConfig.peer_modem or incomingFrame.link ~= linkConfig.link_id then return end
    if incomingFrame.kind == "PING" then
      if not LinkProtocol.token(incomingFrame.a) or type(incomingFrame.b) ~= "string" or incomingFrame.c ~= "HELLO" then return end
      if incomingFrame.senderBoot ~= incomingFrame.a or (incomingFrame.targetBoot ~= "*" and incomingFrame.targetBoot ~= robotBootId) then return end
      local pingSequenceText = incomingFrame.id:sub(#incomingFrame.senderBoot + 2)
      local pingSequence = LinkProtocol.task(pingSequenceText)
      if incomingFrame.id:sub(1, #incomingFrame.senderBoot + 1) ~= incomingFrame.senderBoot .. ":" or not pingSequence then return end
      if handshakeOffer and handshakeOffer.station == incomingFrame.senderBoot and pingSequence <= highestPingSequence then return end
      highestPingSequence = pingSequence
      wakeRetryDelay = 3
      if challengeSequence >= LinkProtocol.maxInt then return end
      challengeSequence = challengeSequence + 1
      local challenge = robotBootId .. ":c" .. challengeSequence
      handshakeOffer = {
        station = incomingFrame.a,
        stationTag = incomingFrame.id,
        enabled = incomingFrame.b ~= "STOPPED",
        tag =
            challenge,
        at = now()
      }
      send(incomingFrame, "PONG", incomingFrame.id, robotBootId, incomingFrame.a, challenge)
      return
    end
    if incomingFrame.kind == "STATUS_QUERY" then
      local taskQuery = LinkProtocol.task(incomingFrame.id) and
          (incomingFrame.a == "QUERY" or incomingFrame.a == "FENCE")
      if LinkProtocol.task(incomingFrame.id) and not taskQuery then return end
      if incomingFrame.targetBoot ~= robotBootId or (not taskQuery and incomingFrame.a ~= incomingFrame.senderBoot) or incomingFrame.b ~= robotBootId then return end
      local exactHandshakeTag = handshakeOffer and now() - handshakeOffer.at <= 6 and
          incomingFrame.senderBoot == handshakeOffer.station and
          incomingFrame.id == handshakeOffer.stationTag and incomingFrame.c == handshakeOffer.tag
      local confirmedStatusQuery = connectionConfirmed and now() - lastHandshakeAt <= 9 and
          incomingFrame.senderBoot == stationBootId and
          confirmedChallenge == incomingFrame.c and (incomingFrame.id == "*" or LinkProtocol.task(incomingFrame.id)) and
          (not handshakeOffer or handshakeOffer.tag == confirmedChallenge)
      if not exactHandshakeTag and not confirmedStatusQuery then return end
      if exactHandshakeTag and (not connectionConfirmed or confirmedChallenge ~= handshakeOffer.tag or stationBootId ~= handshakeOffer.station) then
        if stationBootId and stationBootId ~= handshakeOffer.station and robotInventory then
          robotInventory
              .onConfirmedStationRestart()
        end
        confirmedChallenge = handshakeOffer.tag
        if stationBootId ~= handshakeOffer.station then
          highestActionId, lastRejectionReason = 0, nil
        end
        stationBootId, stationEnabled, connectionConfirmed, lastHandshakeAt = handshakeOffer.station,
            handshakeOffer.enabled, true, now()
      end
      status(incomingFrame)
      return
    end
    if not connectionConfirmed or incomingFrame.senderBoot ~= stationBootId or incomingFrame.targetBoot ~= robotBootId then return end
    if incomingFrame.kind == "IO_GRANT" or incomingFrame.kind == "IO_ACK" or incomingFrame.kind == "IO_CALL" then
      if not robotInventory or incomingFrame.c ~= robotBootId or incomingFrame.b ~= 0 or now() - lastHandshakeAt > 9 then return end
      if incomingFrame.kind == "IO_GRANT" and (incomingFrame.a == "EXCHANGE" or LinkProtocol.call(incomingFrame.a)) then
        robotInventory.acceptGrant(incomingFrame.id, incomingFrame.a)
      elseif incomingFrame.kind == "IO_ACK" and (incomingFrame.a == "SUCCESS" or incomingFrame.a == "FAILED") then
        robotInventory.acknowledgeReceipt(incomingFrame.id, incomingFrame.a)
      elseif incomingFrame.kind == "IO_CALL" and incomingFrame.a == "READY" and stationEnabled then
        robotInventory.requestService(incomingFrame.id)
      end
      return
    end
    if incomingFrame.kind == "SYNC_FIX" then
      if not navigation or (lastAction and not lastAction.done) or now() - lastHandshakeAt > 9 or incomingFrame.c ~= robotBootId or
          not positionRequest or incomingFrame.id ~= positionRequest.id or not navigation.positionNeeded() then
        return
      end
      local x, y, z = LinkProtocol.decodePosition(incomingFrame.a)
      if incomingFrame.b == "POSITION" then
        if x == nil then return end
      elseif incomingFrame.a ~= "" or not LinkProtocol.token(incomingFrame.b, 48) then
        return
      end
      positionRequest = nil
      if not navigation.position(x, y, z, incomingFrame.b ~= "POSITION" and incomingFrame.b or nil) then localizationFailed = true end
      return
    end
    if incomingFrame.kind == "ACTION" then
      local taskNumber = LinkProtocol.task(incomingFrame.id)
      local sourceCell, placementVariant, emergency = LinkProtocol.decodeAction(incomingFrame.a, incomingFrame.b,
        incomingFrame.c)
      if not taskNumber or sourceCell == nil or now() - lastHandshakeAt > 9 or not stationEnabled then return end
      if lastAction and lastAction.stationBootId == incomingFrame.senderBoot and lastAction.id == incomingFrame.id then
        if lastAction.name ~= incomingFrame.a or lastAction.from ~= sourceCell or lastAction.to ~= incomingFrame.c or
            lastAction.variant ~= placementVariant or lastAction.emergency ~= emergency then
          send(incomingFrame, "ACK", incomingFrame.id, "REJECT", "PAYLOAD_CONFLICT", robotBootId)
          return
        end
        send(incomingFrame, "ACK", incomingFrame.id, "DUP", "ACTION", robotBootId)
        if lastAction.done then replay(incomingFrame) end
        return
      end
      if taskNumber <= highestActionId then
        send(incomingFrame, "ACK", incomingFrame.id, "REJECT",
          taskNumber == highestActionId and lastRejectionReason or "OLD_TASK", robotBootId)
        return
      end
      highestActionId, lastRejectionReason = taskNumber, nil
      local operationError
      if lastAction and not lastAction.done then
        operationError = "ACTION_BUSY"
      else
        local success; success, operationError = workReady(emergency); if success then operationError = nil end
      end
      if not operationError and robotInventory then
        local prepared, preparationError = robotInventory.prepareAction(emergency)
        if not prepared then operationError = preparationError or "IO_BUSY" end
      end
      if not operationError then
        local actionAccepted, actionError = executor.accept(incomingFrame.a, sourceCell, incomingFrame.c,
          placementVariant, emergency)
        if not actionAccepted then operationError = actionError or "ROBOT_BUSY" end
      end
      if operationError then
        lastRejectionReason = operationError
        send(incomingFrame, "ACK", incomingFrame.id, "REJECT", operationError, robotBootId)
        return
      end
      lastAction = {
        id = incomingFrame.id,
        stationBootId = incomingFrame.senderBoot,
        done = false,
        name = incomingFrame
            .a,
        from = sourceCell,
        to = incomingFrame.c,
        variant = placementVariant,
        emergency = emergency
      }
      send(incomingFrame, "ACK", incomingFrame.id, "NEW", "ACTION", robotBootId)
    end
  end

  function api.tick()
    local localizationActive = navigation and navigation.snapshot().localizing
    local actionActive = lastAction and not lastAction.done
    if robotInventory then robotInventory.retryReceipt(connectionConfirmed and now() - lastHandshakeAt <= 9) end
    if lastAction and not lastAction.done then
      local actionResult
      actionResult = executor.step()
      if actionResult then
        lastAction.done, lastAction.result, lastAction.reason = true, actionResult.status, actionResult.reason
        lastAction.finishedAt = now()
        checkEnergy(true)
        transport.send(linkConfig.peer_modem, LinkProtocol.dataPort, linkConfig.link_id,
          LinkProtocol.route(robotBootId, lastAction.stationBootId),
          "RESULT", lastAction.id, lastAction.result, lastAction.reason, robotBootId)
      end
    end
    if navigation and not executor.busy() and navigationAvailable() then
      local navigationSnapshot = navigation.snapshot()
      if navigationSnapshot.trusted and not navigationSnapshot.moving then checkEnergy(false) end
    end
    if robotInventory and not localizationActive and not actionActive and not executor.busy() then
      local navigationSnapshot = navigation.snapshot()
      robotInventory.step(connectionConfirmed and now() - lastHandshakeAt <= 9 and stationEnabled,
        stationEnabled and not (lastAction and not lastAction.done) and
        navigationSnapshot.trusted and not navigationSnapshot.moving and not navigationSnapshot.stopped and
        energyAllowsWork, energyReturnRequired)
    end
    if navigation then
      if not localizationActive and not (lastAction and not lastAction.done) and navigationAvailable() and navigation.snapshot().trusted then
        if energyReturnRequired and not navigation.snapshot().moving and not navigation.snapshot().stopped and not navigation.snapshot().atHome then
          navigation.begin(0)
        end
        if navigation.snapshot().moving then navigation.step() end
      end
    end
    if navigation and navigation.snapshot().returningFromProbe then
      local movementComplete = navigation.step()
      if movementComplete == nil then localizationFailed = true end
    elseif navigation and connectionConfirmed and stationEnabled and now() - lastHandshakeAt <= 9 and
        not (lastAction and not lastAction.done) and navigationAvailable() and not localizationFailed then
      local navigationSnapshot = navigation.snapshot()
      if not navigationSnapshot.trusted and not navigationSnapshot.moving then
        local success = navigation.localize()
        if not success then localizationFailed = true end
      end
      if navigation.snapshot().localizing then
        if navigation.positionNeeded() then
          if not positionRequest then
            if positionSequence >= LinkProtocol.maxInt then
              navigation.invalidate("SYNC_ID_EXHAUSTED"); localizationFailed = true
            else
              positionSequence = positionSequence + 1
              positionRequest = { id = tostring(positionSequence), sent = -math.huge }
            end
          end
          if positionRequest then
            if now() - positionRequest.sent >= 3 then
              positionRequest.sent = now(); api.requestPosition(positionSequence)
            end
          end
        else
          local movementComplete = navigation.step()
          if movementComplete == nil then localizationFailed = true end
        end
      end
    end
    if connectionConfirmed and now() - lastHandshakeAt <= 9 then
      local reportedState = lastAction and not lastAction.done and "RUNNING" or (workReady() and "READY" or "UNSYNCED")
      if reportedState ~= lastPublishedStatus then
        lastPublishedStatus = reportedState
        transport.send(linkConfig.peer_modem, LinkProtocol.dataPort, linkConfig.link_id,
          LinkProtocol.route(robotBootId, stationBootId),
          "STATUS", "*", reportedState, lastAction and lastAction.stationBootId == stationBootId and lastAction.id or "",
          robotBootId)
      end
    end
    local bindingFresh = connectionConfirmed and now() - lastHandshakeAt <= 9
    local ownershipChanged, ioObligation = false, false
    if robotInventory then ownershipChanged, ioObligation = ioStatus() end
    local serviceBindingNeeded = robotInventory and robotInventory.connectionNeeded(stationEnabled ~= false)
    local needsBinding = not stationBootId or ownershipChanged
    if not bindingFresh and stationEnabled ~= false then
      needsBinding = needsBinding or
          (navigation and not localizationFailed and not navigation.snapshot().trusted and not actionActive)
    end
    if not bindingFresh and serviceBindingNeeded then needsBinding = true end
    if not needsBinding then wakeRetryDelay = 3 end
    local criticalWake = positionRequest or ioObligation
    if needsBinding and linkConfig and not pairingRequested and not pairingAnnouncementsEnabled and
        now() - lastWakeAt >= (criticalWake and 3 or wakeRetryDelay) then
      if not criticalWake and lastWakeAt ~= -math.huge then wakeRetryDelay = math.min(60, wakeRetryDelay * 2) end
      lastWakeAt = now()
      transport.send(linkConfig.peer_modem, LinkProtocol.dataPort, linkConfig.link_id,
        LinkProtocol.route(robotBootId, "*"),
        "PING", robotBootId, robotBootId, stationBootId or "", "HELLO")
    end
    if pairingAnnouncementsEnabled and now() - lastAnnouncementAt >= 3 then
      lastAnnouncementAt = now(); announcementSequence = announcementSequence + 1
      transport.broadcast(LinkProtocol.dataPort, LinkProtocol.marker, "", LinkProtocol.route(robotBootId, "*"),
        "PAIR_ANNOUNCE", robotBootId, pairingCode, robotAddress, announcementSequence)
    end
  end

  function api.hasReadyWork()
    local bindingFresh = connectionConfirmed and now() - lastHandshakeAt <= 9
    local navigationSnapshot = navigation and navigation.snapshot()
    if lastAction and not lastAction.done then
      local _, waitingForInventory = executor.busy()
      return not waitingForInventory and not (navigationSnapshot and navigationSnapshot.waitingForObstacle)
    end
    if navigationSnapshot and navigationSnapshot.returningFromProbe then return true end
    if navigationSnapshot and navigationSnapshot.localizing then
      return bindingFresh and stationEnabled and not localizationFailed and not navigation.positionNeeded() or false
    end
    if robotInventory and robotInventory.hasReadyWork(bindingFresh and stationEnabled) and
        not (navigationSnapshot and navigationSnapshot.waitingForObstacle) then
      return true
    end
    if not navigationSnapshot or not navigationAvailable() then return false end
    return navigationSnapshot.trusted and navigationSnapshot.moving and not navigationSnapshot.waitingForObstacle or
        false
  end

  function api.loopFlags()
    local navigationSnapshot = navigation and navigation.snapshot()
    local inventoryBusy, inventoryFault = false, false
    if robotInventory then inventoryBusy, inventoryFault = robotInventory.activity() end
    return lastAction ~= nil and not lastAction.done, inventoryBusy, inventoryFault,
        navigationSnapshot and navigationSnapshot.moving or false
  end

  function api.screenStatus()
    local bindingFresh = connectionConfirmed and now() - lastHandshakeAt <= 9
    return {
      hardwareAvailable = executor ~= nil and navigation ~= nil,
      code = pairingCode,
      advertising = pairingAnnouncementsEnabled,
      linkError = linkConfigError,
      waitingForStation = not bindingFresh and (not stationBootId or positionRequest ~= nil or
        (robotInventory and robotInventory.connectionNeeded(stationEnabled ~= false))) or false,
      enabled = stationEnabled,
      localizationFailed = localizationFailed,
      energyIssue = energyError,
      actionRunning = lastAction ~= nil and not lastAction.done,
      actionName = lastAction and lastAction.name,
      actionFrom = lastAction and lastAction.from,
      actionTo = lastAction and lastAction.to,
      actionResult = lastAction and (lastAction.result == "UNKNOWN" or
        (lastAction.finishedAt and now() - lastAction.finishedAt < 5)) and lastAction.result or nil,
      navigation = navigation and navigation.snapshot(),
      io = robotInventory and robotInventory.snapshot()
    }
  end

  function api.snapshot()
    local canAcceptAction = workReady()
    return {
      code = pairingCode,
      boot = robotBootId,
      stationBootId = stationBootId,
      address = robotAddress,
      paired = linkConfig ~= nil,
      error = linkConfigError,
      advertising = pairingAnnouncementsEnabled,
      networkReady = connectionConfirmed and now() - lastHandshakeAt <= 9,
      lastId = lastAction and lastAction.id,
      status = lastAction and (lastAction.done and "DONE" or "RUNNING") or
          (canAcceptAction and "READY" or "UNSYNCED"),
      result = lastAction and lastAction.result,
      reason = lastAction and lastAction.reason,
      physicalReady = connectionConfirmed and now() - lastHandshakeAt <= 9 and canAcceptAction == true,
      io = robotInventory and robotInventory.snapshot(),
      navigation = navigation and navigation.snapshot()
    }
  end

  function api.requestPosition(querySequence)
    if not connectionConfirmed or now() - lastHandshakeAt > 9 or not LinkProtocol.integer(querySequence, 1, LinkProtocol.maxInt) then
      return
          nil, "NOT_CONNECTED"
    end
    return transport.send(linkConfig.peer_modem, LinkProtocol.dataPort, linkConfig.link_id,
      LinkProtocol.route(robotBootId, stationBootId),
      "SYNC_REQUEST", tostring(querySequence), 0, "UNKNOWN", robotBootId)
  end

  return api
end

function RobotApp.run(api, now, pullEvent, screen)
  screen.draw(api.screenStatus())
  local resetConfirmation = false
  local notice, noticeUntil
  local lastScreenAt = now()
  while true do
    local actionRunning, ioBusy, ioFault, navigationMoving = api.loopFlags()
    local incomingEvent = table.pack(pullEvent(api.hasReadyWork() and 0 or 0.25))
    local quitPressed = incomingEvent[1] == "key_down" and (incomingEvent[3] == 113 or incomingEvent[3] == 81)
    if ((quitPressed and not resetConfirmation) or incomingEvent[1] == "interrupted") and not actionRunning and not navigationMoving and
        not (ioBusy and not ioFault) then
      break
    end
    if incomingEvent[1] == "modem_message" then
      api.receive(table.unpack(incomingEvent, 2, incomingEvent.n))
    elseif incomingEvent[1] == "key_down" then
      local character = incomingEvent[3]
      if resetConfirmation then
        resetConfirmation = false
        if character == 121 or character == 89 then
          local removed, removeError = api.resetPairing()
          if removed then
            notice = "Saved connection removed."
          elseif removeError == "ROBOT_BUSY" or removeError == "IO_BUSY" then
            notice = "Still working. Try pairing again when idle."
          else
            notice = "Pairing failed. Check the robot's disk."
          end
          noticeUntil = now() + 5
        end
      elseif character == 112 or character == 80 then
        resetConfirmation = true; notice = nil
      elseif quitPressed then
        notice = "Still working. Press Q again when idle."
        noticeUntil = now() + 5
      end
      lastScreenAt = -math.huge
    elseif incomingEvent[1] == "inventory_changed" then
      api.inventoryChanged(incomingEvent[2])
    end
    api.tick()
    if now() - lastScreenAt >= 0.25 then
      lastScreenAt = now()
      if noticeUntil and lastScreenAt >= noticeUntil then
        notice = nil; noticeUntil = nil
      end
      screen.draw(api.screenStatus(), resetConfirmation, notice)
    end
  end
end

return RobotApp
