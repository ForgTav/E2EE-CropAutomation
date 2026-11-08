local Station = {}

function Station.start(runtime)
  local computer, component = runtime.computer, runtime.component
  local app, screen, renderer, scheduler, closePort
  local succeeded, failure = xpcall(function()
    screen = require("shared_oc_screen").open(component, "station", runtime.unicode)
    runtime.loadOnce("station_startup").show(screen)
    renderer = require("station_renderer").new(screen, runtime.unicode)
    local modemApi = require("shared_oc_modem")
    local modem = modemApi.select(component, false)
    closePort = modemApi.openPort(modem)
    local storage = { __index = runtime.files }
    local network = {
      transport = modemApi.transport(modem),
      boot = runtime.bootId(),
      store = require("shared_link_store").open("station", modem.address, setmetatable({
        path = "/cropautomation/data/station_link.cfg", directory = "/cropautomation/data"
      }, storage))
    }
    local inventoryOpened, inventory = pcall(require("station_oc_transposer").open, component)
    scheduler = require("station_native_scheduler").new(computer, inventoryOpened and inventory.changed or nil)
    local dependencies = {
      now = computer.uptime,
      startTask = scheduler.startTask,
      taskStatus = scheduler.taskStatus,
      waitInput = scheduler.waitInput,
      waitModem = scheduler.waitModem,
      pause = scheduler.pause,
      renderer = renderer,
      unicode = runtime.unicode,
      network = network,
      storage = setmetatable({ path = "/cropautomation/data/state.dat", directory = "/cropautomation/data" }, storage),
      observation = { scan = require("station_oc_sensor").open(component, computer.uptime) }
    }
    if inventoryOpened then
      dependencies.inventory = inventory
    else
      dependencies.networkError = "INVENTORY_HARDWARE_MISMATCH"
    end
    app = require("station_app").boot(dependencies)
    while app.running do
      local continuing, reason = scheduler.step()
      app.supervise()
      if app.tasks.UI.status == "failed" then error("UI: " .. app.tasks.UI.error, 0) end
      if not continuing then
        assert(reason == "interrupted", "NATIVE_TASKS_EXITED")
        app.shutdown()
      end
    end
  end, function(reason) return tostring(reason):sub(1, 160) end)
  local cleanupFailure
  local function cleanup(operation)
    local called, reason = pcall(operation)
    if not called and not cleanupFailure then cleanupFailure = tostring(reason):sub(1, 160) end
  end
  if app then
    cleanup(app.shutdown)
    -- A latched scheduler fault cannot resume production to fake a clean exit.
    if succeeded then
      cleanup(function()
        local deadline = computer.uptime() + 2
        while not app.finished() and computer.uptime() < deadline do scheduler.step(0.1) end
        assert(app.finished(), "NATIVE_TASK_SHUTDOWN_TIMEOUT")
      end)
    end
  end
  if closePort then cleanup(closePort) end
  if renderer then cleanup(renderer.close) end
  if screen then
    if not succeeded or cleanupFailure then
      pcall(function()
        screen.clear(); screen.line(1, "CropAutomation Station stopped")
        screen.line(3, failure or cleanupFailure)
      end)
    end
    cleanup(screen.close)
  end
  if not succeeded then error(failure, 0) end
  if cleanupFailure then error(cleanupFailure, 0) end
  return app
end

return Station
