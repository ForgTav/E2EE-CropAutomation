local Robot = {}

function Robot.start(runtime)
  local computer, component = runtime.computer, runtime.component
  local api, display, screen, closePort
  local succeeded, failure = xpcall(function()
    display = require("shared_oc_screen").open(component, "robot", runtime.unicode)
    local modemApi = require("shared_oc_modem")
    local modem = modemApi.select(component, true)
    closePort = modemApi.openPort(modem)
    local robotBootId, pairingCode = runtime.bootId()
    local available, robotHardware, inventory = pcall(require("robot_oc_hardware").open, component)
    local navigation, executor
    if available then
      navigation = require("robot_nav").new({
        robot = robotHardware,
        now = computer.uptime,
        energy = computer.energy,
        maxEnergy = computer.maxEnergy
      })
      executor = require("robot_execute").new({ nav = navigation, robot = robotHardware, inventory = inventory })
    end
    api = require("robot_app").new({
      transport = modemApi.transport(modem),
      now = computer.uptime,
      store = require("shared_link_store").open("robot", modem.address, setmetatable({
        path = "/cropautomation/data/robot_link.cfg", directory = "/cropautomation/data"
      }, { __index = runtime.files })),
      boot = robotBootId,
      code = pairingCode,
      nav = navigation,
      executor = executor,
      robotHardware = available and robotHardware,
      inventory = available and inventory
    }, false)
    screen = require("robot_ui").new(display)
    require("robot_app").run(api, computer.uptime, computer.pullSignal, screen)
  end, function(reason) return tostring(reason):sub(1, 160) end)
  local cleanupFailure
  local function cleanup(operation)
    local called, reason = pcall(operation)
    if not called and not cleanupFailure then cleanupFailure = tostring(reason):sub(1, 160) end
  end
  if closePort then cleanup(closePort) end
  if display then
    if not succeeded then
      pcall(function()
        display.clear(); display.line(1, "CropAutomation Robot stopped"); display.line(3, failure)
      end)
    end
    cleanup(display.close)
  end
  if not succeeded then error(failure, 0) end
  if cleanupFailure then error(cleanupFailure, 0) end
  return api
end

return Robot
