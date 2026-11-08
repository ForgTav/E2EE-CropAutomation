local StationApp = {}

function StationApp.boot(deps)
  local now = deps.now
  local StationState = require("station_state")
  local StationControl = require("station_control")
  local stateStore = StationState.open(deps.storage)
  local savedState, loadError, loadDetail, stateRecreated = stateStore.load()
  local control = StationControl.new(stateStore, savedState, loadError)
  local ui = require("station_ui").new(deps.renderer, deps.unicode)
  ui.waitForStartup(stateRecreated)
  local link
  if deps.network then
    local networkDependencies = deps.network
    link = require("station_link").new({
      transport = networkDependencies.transport,
      now = now,
      store = networkDependencies.store,
      boot = networkDependencies.boot,
      connectionNeeded = control.connectionNeeded,
      stopped = control.isStopped
    })
    control.attachLink(link)
  end
  local observation
  if deps.observation then
    local observationDependencies = deps.observation
    observation = require("station_observation").new({
      scan = observationDependencies.scan,
      now = now,
      enabled = function() return not control.isStopped() end,
      startupCheck = true
    })
    control.attachObservation(observation, now)
  end
  if deps.inventory and link and observation then
    deps.inventory.now = now
    deps.inventory.rotation = observation.rotation
    deps.inventory.startupCheck = true
    deps.inventory.yieldComputation = function() deps.pause(0) end
    control.attachInventory(deps.inventory)
  end
  local app = {
    control = control,
    tasks = {},
    running = true,
    loadDetail = loadDetail,
    link = link,
    observation = observation,
    ui = ui
  }
  if deps.networkError then control.fail(deps.networkError) end
  local taskNames = { "UI", "Robot Link", "Observation", "Control" }
  for _, taskName in ipairs(taskNames) do
    app.tasks[taskName] = { handle = false, status = "starting", error = nil }
  end
  local function fault(taskName, failureReason)
    local taskStatus = app.tasks[taskName]
    taskStatus.status, taskStatus.error = "failed", tostring(failureReason):sub(1, 160)
    control.fail("TASK_FAILED_" .. taskName:gsub(" ", "_"))
    if deps.reportFault then pcall(deps.reportFault, taskName, taskStatus.error) end
  end
  local taskBodies = {}
  taskBodies.UI = function()
    while app.running do
      ui.update(control.statusSnapshot(ui.terrainCrop(), ui.snapshotQueuedLimit(), ui.wantsActiveTerrain()),
        app.tasks, now())
      local eventName, address, first, second, third = deps.waitInput(0.25)
      if app.running and eventName then
        ui.handle(eventName, address, first, second, third, control.statusSnapshot(ui.terrainCrop()),
          control.request)
      end
    end
  end
  taskBodies["Robot Link"] = function()
    local function receiveEvent(eventName, ...)
      if app.running and link and eventName then link.receive(...) end
    end
    while app.running do
      receiveEvent(deps.waitModem(0.25))
      if app.running and link then link.tick() end
    end
  end
  taskBodies.Observation = function()
    while app.running do
      local sensorCallPerformed = observation and observation.step()
      deps.pause(sensorCallPerformed and 0.01 or 0.25)
    end
  end
  taskBodies.Control = function()
    while app.running do
      control.step()
      deps.pause(control.ioActive() and 0.01 or 0.1)
    end
  end
  for _, taskName in ipairs(taskNames) do
    local taskBody = taskBodies[taskName]
    local callSucceeded, threadHandle = pcall(deps.startTask, function()
      app.tasks[taskName].status = "running"
      local taskSucceeded, failureReason = xpcall(taskBody,
        function(taskError) return tostring(taskError):sub(1, 160) end)
      if not taskSucceeded then
        fault(taskName, failureReason)
      elseif app.running then
        fault(taskName, "Unexpected task exit")
      else
        app.tasks[taskName].status = "stopped"
      end
    end)
    if not callSucceeded or not threadHandle then
      fault(taskName, threadHandle or "Task start failed")
    else
      app.tasks[taskName].handle = threadHandle
    end
  end
  ui.finishStartup(now())
  function app.supervise()
    for _, taskName in ipairs(taskNames) do
      local threadHandle = app.tasks[taskName].handle
      if threadHandle and app.tasks[taskName].status ~= "failed" then
        local threadStatus = deps.taskStatus(threadHandle)
        if app.running and threadStatus ~= "running" then
          fault(taskName, "Unexpected task status: " .. tostring(threadStatus))
        end
      end
    end
  end

  function app.shutdown()
    control.request("STOP")
    app.running = false
  end

  function app.finished()
    for _, taskName in ipairs(taskNames) do
      local threadHandle = app.tasks[taskName].handle
      if threadHandle and deps.taskStatus(threadHandle) ~= "dead" then return false end
    end
    return true
  end

  return app
end

return StationApp
