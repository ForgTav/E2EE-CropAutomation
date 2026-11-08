local StationScheduler = {}
local inputSlot, linkSlot = 1, 2
local inboxLimit = 32

function StationScheduler.new(computer, onComponent)
  local now, pullSignal = computer.uptime, computer.pullSignal
  local tasks, inputInbox, modemInbox = {}, {}, {}
  local currentTask, started, interrupted, fault = nil, false, false, nil
  local scheduler = {}

  local function fail(reason)
    fault = fault or tostring(reason):sub(1, 160)
    error(fault, 0)
  end

  local function timeoutDeadline(timeout)
    assert(type(timeout) == "number" and timeout >= 0 and timeout < math.huge, "NATIVE_TIMEOUT_INVALID")
    return now() + timeout
  end

  local function push(inbox, eventName, ...)
    if #inbox >= inboxLimit then fail("NATIVE_SIGNAL_QUEUE_FULL: " .. eventName) end
    inbox[#inbox + 1] = table.pack(eventName, ...)
  end

  local function route(eventName, ...)
    if eventName == "key_down" or eventName == "touch" or eventName == "screen_resized" then
      push(inputInbox, eventName, ...)
    elseif eventName == "modem_message" then
      push(modemInbox, eventName, ...)
    elseif eventName == "component_added" or eventName == "component_removed" then
      if onComponent then
        local called, reason = pcall(onComponent, eventName, ...)
        if not called then fail("NATIVE_COMPONENT_CALLBACK_FAILED: " .. tostring(reason)) end
      end
    elseif eventName == "interrupted" then
      interrupted = true
    end
  end

  local function pulled(called, eventName, ...)
    if not called then fail("NATIVE_PULL_FAILED: " .. tostring(eventName)) end
    if eventName ~= nil then route(eventName, ...) end
  end

  function scheduler.startTask(body)
    assert(not started and #tasks < 4, "NATIVE_REQUIRES_FOUR_TASKS")
    local handle = { coroutine = coroutine.create(body), deadline = 0 }
    tasks[#tasks + 1] = handle
    return handle
  end

  function scheduler.taskStatus(handle)
    return coroutine.status(handle.coroutine) == "dead" and "dead" or "running"
  end

  function scheduler.waitInput(timeout)
    assert(currentTask == tasks[inputSlot] and currentTask and
      coroutine.running() == currentTask.coroutine, "NATIVE_INPUT_OWNER_REQUIRED")
    local deadline = timeoutDeadline(timeout)
    if #inputInbox > 0 then
      local packet = table.remove(inputInbox, 1)
      return table.unpack(packet, 1, packet.n)
    end
    return coroutine.yield("input", deadline)
  end

  function scheduler.waitModem(timeout)
    assert(currentTask == tasks[linkSlot] and currentTask and
      coroutine.running() == currentTask.coroutine, "NATIVE_LINK_OWNER_REQUIRED")
    local deadline = timeoutDeadline(timeout)
    if #modemInbox > 0 then
      local packet = table.remove(modemInbox, 1)
      return table.unpack(packet, 1, packet.n)
    end
    return coroutine.yield("modem", deadline)
  end

  function scheduler.pause(timeout)
    assert(currentTask and coroutine.running() == currentTask.coroutine, "NATIVE_TASK_REQUIRED")
    return coroutine.yield("pause", timeoutDeadline(timeout))
  end

  local function waitingPacket(handle)
    if handle.wait == "input" and #inputInbox > 0 then
      return table.remove(inputInbox, 1)
    elseif handle.wait == "modem" and #modemInbox > 0 then
      return table.remove(modemInbox, 1)
    end
  end

  local function hasPacket(handle)
    return handle.wait == "input" and #inputInbox > 0 or
        handle.wait == "modem" and #modemInbox > 0
  end

  local function resumeTask(slot)
    local handle = tasks[slot]
    if scheduler.taskStatus(handle) == "dead" then return end
    local packet = waitingPacket(handle)
    if not packet and now() < handle.deadline then return end
    currentTask = handle
    local called, wait, deadline
    if packet then
      called, wait, deadline = coroutine.resume(handle.coroutine, table.unpack(packet, 1, packet.n))
    else
      called, wait, deadline = coroutine.resume(handle.coroutine)
    end
    currentTask = nil
    if fault then error(fault, 0) end
    if not called then fail("NATIVE_TASK_FAILED: " .. slot .. ": " .. tostring(wait)) end
    if scheduler.taskStatus(handle) == "dead" then return end
    if type(deadline) ~= "number" or deadline < 0 or deadline >= math.huge or deadline ~= deadline then
      fail("NATIVE_TASK_WAIT_INVALID: " .. slot)
    end
    if wait == "input" then
      if slot ~= inputSlot then fail("NATIVE_INPUT_OWNER_REQUIRED") end
    elseif wait == "modem" then
      if slot ~= linkSlot then fail("NATIVE_LINK_OWNER_REQUIRED") end
    elseif wait ~= "pause" then
      fail("NATIVE_TASK_YIELD_INVALID: " .. slot)
    end
    handle.wait, handle.deadline = wait, deadline
  end

  function scheduler.step(maximumWait)
    if fault then error(fault, 0) end
    if not started then assert(#tasks == 4, "NATIVE_REQUIRES_FOUR_TASKS") end
    local deadline = timeoutDeadline(maximumWait == nil and 0.25 or maximumWait)
    started = true
    local active = false
    for slot = 1, 4 do
      local handle = tasks[slot]
      if scheduler.taskStatus(handle) ~= "dead" then
        active = true
        deadline = math.min(deadline, hasPacket(handle) and now() or handle.deadline)
      end
    end
    if not active then return false, "finished" end
    -- One host signal pull per turn; pullSignal(0) can itself yield in OC.
    pulled(pcall(pullSignal, math.max(0, deadline - now())))
    if interrupted then
      interrupted = false; return false, "interrupted"
    end
    resumeTask(inputSlot)
    resumeTask(linkSlot)
    resumeTask(3)
    resumeTask(4)
    return true
  end

  return scheduler
end

return StationScheduler
