local LinkProtocol = require("shared_link")
local StationLink = {}
function StationLink.new(deps)
  local networkTransport, now, linkStore = deps.transport, deps.now, deps.store
  local stationAddress, stationBootId = networkTransport.address, deps.boot
  assert(LinkProtocol.address(stationAddress))
  local linkConfig, linkConfigError = linkStore.load()
  local pairingCandidates, expiredCandidates, pairingOpen, pairingAttempt, candidateOverflow = {}, {}, false, nil, false
  local pairingCommands, transportEvents = {}, {}
  local robotBootId, pingTag, confirmedChallenge, pendingHandshake = nil, nil, nil, nil
  local lastHandshakeAttemptAt, pingSequence = -math.huge, 0
  local lastRobotWakeBoot, lastRobotWakeAt = nil, -math.huge
  local handshakeRetryDelay = 3
  local connectionConfirmed = false
  local confirmedAt
  local outstandingAction, highestActionId = nil, 0
  local positionResponse, positionRequestId = nil, nil
  local highestPositionSequence, queueFault, lastStatusSignature = 0, false, nil
  local queueFaultSource, queueFaultKind
  local api = {}
  local ioOutbox = {}
  local confirmedOnce = false
  local function tag()
    pingSequence = pingSequence + 1
    assert(pingSequence <= LinkProtocol.maxInt, "LINK_SEQUENCE_EXHAUSTED")
    return stationBootId .. ":" .. pingSequence
  end
  local function emit(kind, id, eventStatus, detail)
    local previousEvent = transportEvents[#transportEvents]
    if kind == "IO_STATUS" and previousEvent and previousEvent.kind == kind and
        previousEvent.boot == robotBootId and previousEvent.id == id and
        previousEvent.ownership == eventStatus and previousEvent.challenge == detail then
      return
    end
    local incomingEvent = { kind = kind, id = id, boot = robotBootId }
    if kind == "STATUS" then
      incomingEvent.status = eventStatus; incomingEvent.lastActionId = detail
    elseif kind == "IO_STATUS" then
      incomingEvent.ownership = eventStatus; incomingEvent.challenge = detail
    elseif kind == "IO_REQUEST" then
      incomingEvent.mode = eventStatus; incomingEvent.callSequence = detail
    elseif kind == "IO_UNLOADED" then
      incomingEvent.status = eventStatus
    elseif kind == "ACK" or kind == "RESULT" then
      incomingEvent.status = eventStatus; incomingEvent.reason = detail
    else
      incomingEvent.reason = eventStatus
    end
    if kind == "IO_REQUEST" or kind == "IO_UNLOADED" then
      for _, queuedEvent in ipairs(transportEvents) do
        if queuedEvent.kind == kind and queuedEvent.boot == incomingEvent.boot and queuedEvent.id == id then
          if queuedEvent.status ~= incomingEvent.status or queuedEvent.mode ~= incomingEvent.mode or
              queuedEvent.callSequence ~= incomingEvent.callSequence then
            queuedEvent.kind = "IO_PROTOCOL_FAULT"
            queuedEvent.reason = kind == "IO_UNLOADED" and "IO_RECEIPT_CONFLICT" or "IO_PAYLOAD_CONFLICT"
          end
          return
        end
      end
    end
    if #transportEvents >= 32 then
      queueFaultSource, queueFaultKind = queueFaultSource or "EVENTS", queueFaultKind or kind
      queueFault = true; connectionConfirmed = false; return
    end
    transportEvents[#transportEvents + 1] = incomingEvent
  end
  local function transport(reason)
    emit("TRANSPORT_WAIT", outstandingAction and outstandingAction.id, reason)
  end
  local function send(kind, id, payloadA, payloadB, payloadC, targetBoot)
    if not linkConfig then return false end
    return networkTransport.send(linkConfig.peer_modem, LinkProtocol.dataPort, linkConfig.link_id,
      LinkProtocol.route(stationBootId, targetBoot or (kind == "PING" and "*" or (robotBootId or "*"))), kind, id,
      payloadA, payloadB, payloadC)
  end
  local function freshConnection()
    return connectionConfirmed and confirmedAt ~= nil and now() - confirmedAt <= 9 and not queueFault
  end
  function api.requestConnection(modeChanged, urgent)
    if not linkConfig or pairingOpen or queueFault then return false end
    if modeChanged then
      pingTag, pendingHandshake = nil, nil
    elseif pingTag or pendingHandshake then
      if urgent then
        lastHandshakeAttemptAt = -math.huge; handshakeRetryDelay = 3
      end
      return false
    elseif freshConnection() then
      return true
    end
    pingTag = tag(); lastHandshakeAttemptAt = -math.huge; handshakeRetryDelay = 3
    return false
  end

  local function query(id)
    if not freshConnection() or pingTag or pendingHandshake or not confirmedChallenge or not robotBootId then return false end
    return send("STATUS_QUERY", id or "*",
      id and (outstandingAction.phase == "FENCE" and "FENCE" or "QUERY") or stationBootId, robotBootId,
      confirmedChallenge)
  end
  local function confirmHandshake()
    if not pendingHandshake or not pendingHandshake.status or not pendingHandshake.ownership then return end
    local robotRestarted = confirmedOnce and robotBootId ~= pendingHandshake.robotBootId
    robotBootId, confirmedChallenge = pendingHandshake.robotBootId, pendingHandshake.challenge
    connectionConfirmed = true
    handshakeRetryDelay = 3
    if pendingHandshake.stationTag ~= "*" then confirmedAt = pendingHandshake.at end
    if robotRestarted then
      positionResponse, positionRequestId = nil, nil; highestPositionSequence = 0; lastStatusSignature = nil
    end
    emit("ROBOT_CONFIRMED", pendingHandshake.exchangeId, robotRestarted and "RESTART" or
      (confirmedOnce and "RECONNECT" or "FIRST"))
    emit("IO_STATUS", pendingHandshake.exchangeId, pendingHandshake.ownership, confirmedChallenge)
    emit("STATUS", "*", pendingHandshake.status, pendingHandshake.lastActionId)
    lastStatusSignature = "*|" .. pendingHandshake.status .. "|" .. pendingHandshake.lastActionId
    confirmedOnce = true; pendingHandshake = nil
  end
  local function expire()
    for i = #pairingCandidates, 1, -1 do
      if now() - pairingCandidates[i].seen >= LinkProtocol.candidateTTL then
        local pairingCandidate = table.remove(pairingCandidates, i)
        if #expiredCandidates == LinkProtocol.candidateLimit then table.remove(expiredCandidates, 1) end
        expiredCandidates[#expiredCandidates + 1] = {
          address = pairingCandidate.address,
          boot = pairingCandidate.boot,
          seq =
              pairingCandidate.seq
        }
      end
    end
  end
  local function cancelPair()
    pairingOpen, pairingAttempt, candidateOverflow = false, nil, false
    pairingCandidates, expiredCandidates = {}, {}
  end
  local function selectCandidate(selection)
    expire()
    if not pairingOpen or not deps.stopped() or pairingAttempt or candidateOverflow or type(selection) ~= "table" then return end
    for _, pairingCandidate in ipairs(pairingCandidates) do
      if pairingCandidate.address == selection.address and pairingCandidate.boot == selection.boot and pairingCandidate.code == selection.code then
        pairingAttempt = {
          address = pairingCandidate.address,
          boot = pairingCandidate.boot,
          code = pairingCandidate.code,
          id = tag(),
          link = stationAddress .. "|" .. pairingCandidate.address,
          deadline = now() + LinkProtocol.pairTimeout,
          phase = "SELECT",
          sent = -math.huge
        }
        connectionConfirmed = false
        return
      end
    end
    linkConfigError = "PAIR_SELECTION_STALE"
  end
  function api.command(kind, selection)
    if kind ~= "PAIR_OPEN" and kind ~= "PAIR_CLOSE" and kind ~= "PAIR_SELECT" and kind ~= "PAIR_RESET" then
      return nil,
          "REJECTED"
    end
    if #pairingCommands >= 8 then return nil, "LINK_COMMAND_QUEUE_FULL" end
    if selection then selection = { address = selection.address, boot = selection.boot, code = selection.code } end
    pairingCommands[#pairingCommands + 1] = { kind = kind, selection = selection }
    return true
  end

  function api.positionReply(positionResult)
    if not positionRequestId or positionResult.id ~= positionRequestId or positionResult.boot ~= robotBootId or
        deps.stopped() then
      return nil, "POSITION_NOT_REQUESTED"
    end
    local encodedPosition = LinkProtocol.encodePosition(positionResult.x, positionResult.y, positionResult.z)
    if not encodedPosition and not LinkProtocol.token(positionResult.error, 48) then return nil, "POSITION_INVALID" end
    positionResponse = {
      id = positionResult.id,
      coordinates = encodedPosition or "",
      result = encodedPosition and
          "POSITION" or positionResult.error,
      boot = robotBootId
    }
    return true
  end

  function api.sendAction(id, name, from, to, variant, emergency)
    if not LinkProtocol.parameters(name, from, to, variant) or not LinkProtocol.priority(name, emergency) then
      return nil,
          "INVALID_ACTION"
    end
    local taskNumber = LinkProtocol.task(id)
    if not taskNumber or taskNumber <= highestActionId then return nil, "TASK_INVALID" end
    if outstandingAction then return nil, "BUSY" end
    if not api.snapshot().networkReady or deps.stopped() then return nil, "NOT_READY" end
    outstandingAction = {
      id = id,
      phase = "SENT",
      name = name,
      from = from,
      to = to,
      variant = variant,
      emergency = emergency,
      boot = robotBootId,
      nextQuery = now() + 3
    }
    highestActionId = taskNumber
    if not send("ACTION", id, name, LinkProtocol.encodeAction(name, from, variant, emergency), to) then
      transport(
        "SEND_FAILED")
    end
    return true
  end

  function api.releaseAction(id)
    if outstandingAction and outstandingAction.id == id then
      outstandingAction = nil; return true
    end
    return nil, "TASK_INVALID"
  end

  function api.stopAction()
    if not outstandingAction or outstandingAction.phase == "DONE" or outstandingAction.phase == "ACCEPTED" then return end
    if outstandingAction.phase ~= "FENCE" then
      outstandingAction.phase = "FENCE"; outstandingAction.nextQuery = -math.huge
    end
  end

  function api.poll() return table.remove(transportEvents, 1) end

  function api.pendingEvents() return #transportEvents end

  function api.sendIo(outgoingMessage)
    if not linkConfig or outgoingMessage.boot ~= robotBootId then return nil, "NOT_CONNECTED" end
    local kind, id = outgoingMessage.kind, outgoingMessage.id
    if kind ~= "IO_CALL" and kind ~= "IO_GRANT" and kind ~= "IO_ACK" then return nil, "IO_INVALID" end
    if (kind == "IO_CALL" and not LinkProtocol.call(id)) or (kind ~= "IO_CALL" and not LinkProtocol.task(id)) then
      return
          nil, "IO_INVALID"
    end
    for _, queuedMessage in ipairs(ioOutbox) do
      if queuedMessage.kind == kind and queuedMessage.id == id and queuedMessage.boot == outgoingMessage.boot then return true end
    end
    if #ioOutbox >= 8 then return nil, "IO_SEND_QUEUE_FULL" end
    ioOutbox[#ioOutbox + 1] = {
      kind = kind,
      id = id,
      boot = outgoingMessage.boot,
      value = outgoingMessage.status or outgoingMessage.callId or (kind == "IO_CALL" and "READY" or "EXCHANGE")
    }
    api.requestConnection()
    return true
  end

  function api.receive(localAddress, robotAddress, port, _, ...)
    local incomingFrame = LinkProtocol.frame(stationAddress, localAddress, robotAddress, port, ...)
    if not incomingFrame then return end
    if LinkProtocol.isPairKind(incomingFrame.kind) then
      if not pairingOpen or not deps.stopped() or (incomingFrame.targetBoot ~= stationBootId and incomingFrame.kind ~= "PAIR_ANNOUNCE") then return end
      if incomingFrame.kind == "PAIR_ANNOUNCE" then
        if incomingFrame.targetBoot ~= "*" or incomingFrame.senderBoot ~= incomingFrame.id or incomingFrame.link ~= "" or not LinkProtocol.code(incomingFrame.a) or incomingFrame.b ~= incomingFrame.senderAddress or not LinkProtocol.integer(incomingFrame.c, 1, LinkProtocol.maxInt) then return end
        expire()
        for _, pairingCandidate in ipairs(expiredCandidates) do
          if pairingCandidate.address == incomingFrame.senderAddress and pairingCandidate.boot == incomingFrame.id and incomingFrame.c <= pairingCandidate.seq then return end
        end
        for _, pairingCandidate in ipairs(pairingCandidates) do
          if pairingCandidate.address == incomingFrame.senderAddress then
            if pairingCandidate.boot == incomingFrame.id then
              if incomingFrame.a == pairingCandidate.code and incomingFrame.c > pairingCandidate.seq then
                pairingCandidate.seq = incomingFrame.c; pairingCandidate.seen = now()
              end
            elseif incomingFrame.id ~= pairingCandidate.previous then
              pairingCandidate.previous, pairingCandidate.boot, pairingCandidate.code, pairingCandidate.seq, pairingCandidate.seen =
                  pairingCandidate.boot, incomingFrame.id, incomingFrame.a, incomingFrame.c, now()
            end
            return
          end
        end
        if #pairingCandidates == LinkProtocol.candidateLimit then
          candidateOverflow = true; linkConfigError = "PAIR_LIST_FULL"; return
        end
        pairingCandidates[#pairingCandidates + 1] = {
          address = incomingFrame.senderAddress,
          boot = incomingFrame.id,
          code =
              incomingFrame.a,
          seq = incomingFrame.c,
          seen = now()
        }
      elseif pairingAttempt and now() < pairingAttempt.deadline and incomingFrame.senderAddress == pairingAttempt.address and incomingFrame.id == pairingAttempt.id and
          incomingFrame.link == pairingAttempt.link and incomingFrame.senderBoot == pairingAttempt.boot and incomingFrame.b == pairingAttempt.boot and incomingFrame.c == pairingAttempt.code then
        if incomingFrame.kind == "PAIR_CONFIRM" and incomingFrame.a == "OFFER" and pairingAttempt.phase == "SELECT" then
          pairingAttempt.phase = "WRITING"
          local pairingConfig = LinkProtocol.config("station", stationAddress, incomingFrame.senderAddress,
            incomingFrame.link)
          local success, transportError = linkStore.save(pairingConfig, true)
          if not success then
            linkConfig = nil; linkConfigError = transportError; pairingAttempt = nil; connectionConfirmed = false; return
          end
          linkConfig, linkConfigError = pairingConfig, nil
          if not deps.stopped() or not pairingOpen or not pairingAttempt then
            connectionConfirmed = false; return
          end
          pairingAttempt.phase = "COMMIT"; pairingAttempt.sent = -math.huge
        elseif incomingFrame.kind == "PAIR_DONE" and incomingFrame.a == "SAVED" and pairingAttempt.phase == "COMMIT" then
          linkConfigError = nil; cancelPair(); connectionConfirmed = false
          robotBootId = nil; pingTag = nil; api.requestConnection(true)
          emit("PAIR_DONE", nil, "SAVED")
        end
      end
      return
    end
    if not linkConfig or pairingOpen or incomingFrame.senderAddress ~= linkConfig.peer_modem or incomingFrame.link ~= linkConfig.link_id then return end
    if incomingFrame.kind == "PING" and (incomingFrame.targetBoot == "*" or incomingFrame.targetBoot == stationBootId) then
      if incomingFrame.id ~= incomingFrame.senderBoot or incomingFrame.a ~= incomingFrame.senderBoot or
          type(incomingFrame.b) ~= "string" or incomingFrame.c ~= "HELLO" then
        return
      end
      if incomingFrame.senderBoot == lastRobotWakeBoot and now() - lastRobotWakeAt < 3 then return end
      lastRobotWakeBoot, lastRobotWakeAt = incomingFrame.senderBoot, now()
      if pingTag or pendingHandshake then
        handshakeRetryDelay = 3; return
      end
      if incomingFrame.senderBoot == robotBootId and freshConnection() then
        pendingHandshake = { robotBootId = robotBootId, stationTag = "*", challenge = confirmedChallenge, at = now() }
        lastHandshakeAttemptAt = -math.huge
      else
        api.requestConnection(true)
      end
      return
    end
    if incomingFrame.targetBoot ~= stationBootId then return end
    if incomingFrame.kind == "PONG" then
      if incomingFrame.senderBoot ~= incomingFrame.a or not pingTag or incomingFrame.id ~= pingTag or incomingFrame.b ~= stationBootId or not LinkProtocol.token(incomingFrame.c) or
          not LinkProtocol.validChallenge(incomingFrame.a, incomingFrame.c) then
        return
      end
      handshakeRetryDelay = 3
      pendingHandshake = { robotBootId = incomingFrame.a, stationTag = pingTag, challenge = incomingFrame.c, at = now() }
      pingTag = nil
      lastHandshakeAttemptAt = now()
      send("STATUS_QUERY", pendingHandshake.stationTag, stationBootId, incomingFrame.a, incomingFrame.c, incomingFrame.a)
      return
    end
    if pendingHandshake and incomingFrame.senderBoot == pendingHandshake.robotBootId and incomingFrame.c == pendingHandshake.robotBootId and now() - pendingHandshake.at <= 6 then
      if incomingFrame.kind == "IO_STATUS" and incomingFrame.b == pendingHandshake.challenge and
          (incomingFrame.id == "*" or LinkProtocol.task(incomingFrame.id)) and (incomingFrame.a == "FREE" or incomingFrame.a == "BUSY" or incomingFrame.a == "FAULT") then
        pendingHandshake.ownership, pendingHandshake.exchangeId = incomingFrame.a, incomingFrame.id
        confirmHandshake(); return
      elseif incomingFrame.kind == "STATUS" and incomingFrame.id == pendingHandshake.stationTag and
          (incomingFrame.a == "READY" or incomingFrame.a == "RUNNING" or incomingFrame.a == "UNSYNCED") and (incomingFrame.b == "" or LinkProtocol.task(incomingFrame.b)) then
        pendingHandshake.status, pendingHandshake.lastActionId = incomingFrame.a, incomingFrame.b
        confirmHandshake(); return
      end
    end
    if incomingFrame.senderBoot ~= robotBootId or incomingFrame.c ~= robotBootId then return end
    if not connectionConfirmed and incomingFrame.kind ~= "RESULT" and incomingFrame.kind ~= "ACK" then return end
    if incomingFrame.kind == "IO_STATUS" then
      if not connectionConfirmed or incomingFrame.b ~= confirmedChallenge or (incomingFrame.id ~= "*" and not LinkProtocol.task(incomingFrame.id)) or
          (incomingFrame.a ~= "FREE" and incomingFrame.a ~= "BUSY" and incomingFrame.a ~= "FAULT") then
        return
      end
      emit(incomingFrame.kind, incomingFrame.id, incomingFrame.a, incomingFrame.b)
    elseif incomingFrame.kind == "IO_REQUEST" then
      if not connectionConfirmed or not LinkProtocol.task(incomingFrame.id) or not LinkProtocol.ioRequest(incomingFrame.a, incomingFrame.b) then return end
      emit(incomingFrame.kind, incomingFrame.id, incomingFrame.a, incomingFrame.b)
    elseif incomingFrame.kind == "IO_UNLOADED" then
      if not connectionConfirmed or (incomingFrame.a ~= "SUCCESS" and incomingFrame.a ~= "FAILED") or incomingFrame.b ~= 0 or not LinkProtocol.task(incomingFrame.id) then return end
      emit(incomingFrame.kind, incomingFrame.id, incomingFrame.a, 0)
    elseif incomingFrame.kind == "STATUS" then
      if not connectionConfirmed or (incomingFrame.a ~= "READY" and incomingFrame.a ~= "RUNNING" and incomingFrame.a ~= "DONE" and incomingFrame.a ~= "NOT_FOUND" and incomingFrame.a ~= "UNSEEN" and incomingFrame.a ~= "UNSYNCED") then return end
      if incomingFrame.b ~= "" and not LinkProtocol.task(incomingFrame.b) then return end
      if incomingFrame.id ~= "*" then
        if not outstandingAction or incomingFrame.id ~= outstandingAction.id or (outstandingAction.phase == "DONE") then return end
        if (incomingFrame.a == "RUNNING" or incomingFrame.a == "DONE") and incomingFrame.b ~= incomingFrame.id then return end
        if incomingFrame.a == "NOT_FOUND" or incomingFrame.a == "UNSYNCED" then
          outstandingAction.phase = "UNKNOWN"; transport("TASK_NOT_FOUND")
        elseif incomingFrame.a == "UNSEEN" and outstandingAction.phase == "SENT" and not deps.stopped() and
            outstandingAction.boot == robotBootId and freshConnection() and not pingTag and not pendingHandshake then
          outstandingAction.nextQuery = now() + 3
          send("ACTION", outstandingAction.id, outstandingAction.name,
            LinkProtocol.encodeAction(outstandingAction.name, outstandingAction.from, outstandingAction.variant,
              outstandingAction.emergency),
            outstandingAction.to)
        elseif incomingFrame.a == "RUNNING" or incomingFrame.a == "DONE" then
          outstandingAction.phase = "ACCEPTED"; outstandingAction.nextQuery = now() + 6
        end
      end
      local statusSignature = incomingFrame.id .. "|" .. incomingFrame.a .. "|" .. incomingFrame.b
      if statusSignature ~= lastStatusSignature then
        emit("STATUS", incomingFrame.id, incomingFrame.a, incomingFrame.b); lastStatusSignature = statusSignature
      end
    elseif incomingFrame.kind == "ACK" and outstandingAction and incomingFrame.id == outstandingAction.id and outstandingAction.phase ~= "DONE" then
      if incomingFrame.a ~= "NEW" and incomingFrame.a ~= "DUP" and incomingFrame.a ~= "REJECT" then return end
      if not LinkProtocol.token(incomingFrame.b, 48) then return end
      if outstandingAction.boot ~= robotBootId then return end
      if outstandingAction.phase ~= "ACCEPTED" or incomingFrame.a == "REJECT" then
        emit("ACK", incomingFrame.id,
          incomingFrame.a, incomingFrame.b)
      end
      outstandingAction.phase = incomingFrame.a == "REJECT" and (incomingFrame.b == "OLD_TASK" and "UNKNOWN" or "DONE") or
          "ACCEPTED"
    elseif incomingFrame.kind == "RESULT" and outstandingAction and incomingFrame.id == outstandingAction.id and outstandingAction.phase ~= "DONE" then
      if outstandingAction.boot ~= robotBootId or
          (incomingFrame.a ~= "SUCCESS" and incomingFrame.a ~= "NO_CHANGE" and incomingFrame.a ~= "BLOCKED" and incomingFrame.a ~= "UNKNOWN") or not LinkProtocol.token(incomingFrame.b, 48) then
        return
      end
      outstandingAction.phase = "DONE"
      emit("RESULT", incomingFrame.id, incomingFrame.a, incomingFrame.b)
    elseif incomingFrame.kind == "SYNC_REQUEST" then
      local querySequence = tonumber(incomingFrame.id)
      if not LinkProtocol.integer(querySequence, 1, LinkProtocol.maxInt) or tostring(querySequence) ~= incomingFrame.id or querySequence < highestPositionSequence or
          incomingFrame.a ~= 0 or incomingFrame.b ~= "UNKNOWN" or deps.stopped() then
        return
      end
      if querySequence == highestPositionSequence then
        if positionResponse and positionResponse.id == incomingFrame.id then positionResponse.sent = nil end
        return
      end
      positionRequestId = incomingFrame.id; positionResponse = nil
      highestPositionSequence = querySequence; emit(incomingFrame.kind, incomingFrame.id, incomingFrame.a,
        incomingFrame.b)
    end
  end

  function api.tick()
    if #pairingCommands > 0 then
      local command = table.remove(pairingCommands, 1)
      if command.kind == "PAIR_RESET" then
        if not deps.stopped() or outstandingAction or #ioOutbox > 0 then
          linkConfigError = "PAIR_REQUIRES_STOPPED"
        else
          local removed, removeError = linkStore.remove()
          if not removed then
            linkConfigError = removeError
          else
            linkConfig, linkConfigError = nil, nil
            robotBootId, pingTag, confirmedChallenge, pendingHandshake = nil, nil, nil, nil
            connectionConfirmed, confirmedOnce = false, false
            positionResponse, positionRequestId, lastStatusSignature = nil, nil, nil
            highestPositionSequence = 0
            cancelPair()
            emit("PAIR_RESET", nil, "REMOVED")
          end
        end
      elseif command.kind == "PAIR_OPEN" and deps.stopped() and not outstandingAction then
        pairingOpen = true; pairingCandidates = {}; expiredCandidates = {}; candidateOverflow = false; pairingAttempt = nil; linkConfigError = nil
        connectionConfirmed = false
      elseif command.kind == "PAIR_CLOSE" then
        cancelPair()
      elseif command.kind == "PAIR_SELECT" then
        selectCandidate(command.selection)
      end
    end
    expire()
    if pairingOpen and not deps.stopped() then cancelPair() end
    if pairingAttempt then
      if now() >= pairingAttempt.deadline then
        linkConfigError = "PAIR_TIMEOUT"; pairingAttempt = nil; connectionConfirmed = false
      elseif pairingAttempt.phase ~= "WRITING" and now() - pairingAttempt.sent >= 2 then
        pairingAttempt.sent = now()
        if pairingAttempt.phase == "SELECT" then
          networkTransport.send(pairingAttempt.address, LinkProtocol.dataPort, pairingAttempt.link,
            LinkProtocol.route(stationBootId, pairingAttempt.boot), "PAIR_SELECT", pairingAttempt.id, pairingAttempt
            .code, pairingAttempt.boot, pairingAttempt.address)
        else
          networkTransport.send(pairingAttempt.address, LinkProtocol.dataPort, pairingAttempt.link,
            LinkProtocol.route(stationBootId, pairingAttempt.boot), "PAIR_CONFIRM", pairingAttempt.id, "COMMIT",
            pairingAttempt.boot, pairingAttempt.code)
        end
      end
    end
    if not linkConfig or pairingOpen then return end
    if not deps.stopped() and not queueFault and not freshConnection() and not pingTag and
        not pendingHandshake and deps.connectionNeeded and deps.connectionNeeded() then
      api.requestConnection()
    end
    if #ioOutbox > 0 then
      local outgoingMessage = ioOutbox[1]
      if outgoingMessage.boot ~= robotBootId or (outgoingMessage.kind == "IO_CALL" and deps.stopped()) then
        table.remove(ioOutbox, 1)
      elseif freshConnection() and not pingTag and not pendingHandshake then
        if not outgoingMessage.retryAt or now() >= outgoingMessage.retryAt then
          if send(outgoingMessage.kind, outgoingMessage.id, outgoingMessage.value, 0, outgoingMessage.boot) then
            table.remove(ioOutbox, 1)
          else
            outgoingMessage.retryAt = now() + 3
          end
        end
      else
        api.requestConnection()
      end
    end
    if positionResponse and not positionResponse.sent then
      if not deps.stopped() and robotBootId == positionResponse.boot then
        if freshConnection() and not pingTag and not pendingHandshake then
          positionResponse.sent = true
          send("SYNC_FIX", positionResponse.id, positionResponse.coordinates, positionResponse.result, robotBootId)
        else
          api.requestConnection()
        end
      else
        positionResponse = nil
      end
    end
    if deps.stopped() then api.stopAction() end
    if outstandingAction and outstandingAction.phase ~= "DONE" and outstandingAction.nextQuery and now() >= outstandingAction.nextQuery and
        outstandingAction.boot == robotBootId then
      if freshConnection() and not pingTag and not pendingHandshake then
        outstandingAction.nextQuery = now() + (outstandingAction.phase == "ACCEPTED" and 6 or 3)
        query(outstandingAction.id)
      else
        api.requestConnection()
      end
    end
    local criticalBinding = (outstandingAction and outstandingAction.phase ~= "DONE") or
        (positionResponse and not positionResponse.sent) or pendingHandshake
    for _, outgoingMessage in ipairs(ioOutbox) do
      if outgoingMessage.kind ~= "IO_CALL" then
        criticalBinding = true; break
      end
    end
    if (pingTag or pendingHandshake) and now() - lastHandshakeAttemptAt >= (criticalBinding and 3 or handshakeRetryDelay) then
      if not criticalBinding and lastHandshakeAttemptAt ~= -math.huge then
        handshakeRetryDelay = math.min(60,
          handshakeRetryDelay * 2)
      end
      lastHandshakeAttemptAt = now()
      if pendingHandshake and now() - pendingHandshake.at < 6 and
          (pendingHandshake.stationTag ~= "*" or freshConnection()) then
        send("STATUS_QUERY", pendingHandshake.stationTag, stationBootId,
          pendingHandshake.robotBootId, pendingHandshake.challenge, pendingHandshake.robotBootId)
      else
        pingTag = tag(); pendingHandshake = nil
        send("PING", pingTag, stationBootId, deps.stopped() and "STOPPED" or (robotBootId or ""), "HELLO")
      end
    end
  end

  function api.connectionStatus()
    expire()
    return freshConnection() and not pingTag and not pendingHandshake, robotBootId, queueFault
  end

  function api.snapshot()
    local networkReady = api.connectionStatus()
    local candidateSnapshots = {}
    for i, pairingCandidate in ipairs(pairingCandidates) do
      candidateSnapshots[i] = {
        address = pairingCandidate.address,
        code =
            pairingCandidate.code,
        boot = pairingCandidate.boot
      }
    end
    return {
      stationBootId = stationBootId,
      pairing = pairingOpen,
      candidates = candidateSnapshots,
      overflow = candidateOverflow,
      phase = pairingAttempt and pairingAttempt.phase,
      error = linkConfigError,
      paired = linkConfig ~= nil,
      robotAddress = linkConfig and linkConfig.peer_modem,
      boot = robotBootId,
      challenge = confirmedChallenge,
      outstanding = outstandingAction and outstandingAction.id,
      queueFault = queueFault,
      queueFaultSource = queueFaultSource,
      queueFaultKind = queueFaultKind,
      eventCount = #transportEvents,
      commandCount = #pairingCommands,
      networkReady = networkReady,
      ioSendCount = #ioOutbox
    }
  end

  return api
end

return StationLink
