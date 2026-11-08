local RobotHardware = {}

function RobotHardware.inventoryAccess(robotHardware, inventoryController)
  local inventoryAccess = {}
  function inventoryAccess.readStack(slot)
    local called, inventoryStack, reason = pcall(inventoryController.getStackInInternalSlot, slot)
    local readable = called and reason == nil and (inventoryStack == nil or
      type(inventoryStack) == "table" and type(inventoryStack.name) == "string" and type(inventoryStack.size) == "number" and
      inventoryStack.size >= 1 and inventoryStack.size <= 64 and inventoryStack.size % 1 == 0)
    return readable, inventoryStack
  end

  function inventoryAccess.selectSlot(slot)
    local called, selectedSlot, reason = pcall(robotHardware.select)
    if not called or reason ~= nil or type(selectedSlot) ~= "number" or selectedSlot % 1 ~= 0 or
        selectedSlot < 1 or selectedSlot > 16 then
      return false
    end
    if selectedSlot ~= slot then called, selectedSlot, reason = pcall(robotHardware.select, slot) end
    return called and reason == nil, selectedSlot
  end

  return inventoryAccess
end

function RobotHardware.open(component)
  local function unique(kind)
    local address
    for componentAddress in component.list(kind, true) do
      assert(not address, "Multiple " .. kind); address = componentAddress
    end
    return component.proxy(assert(address, "Missing " .. kind))
  end
  local robotHardware, inventoryController = unique("robot"), unique("inventory_controller")
  return {
    forward = function() return robotHardware.move(3) end,
    back = function() return robotHardware.move(2) end,
    up = function() return robotHardware.move(1) end,
    down = function() return robotHardware.move(0) end,
    turnLeft = function() return robotHardware.turn(false) end,
    turnRight = function() return robotHardware.turn(true) end,
    placeDown = function() return robotHardware.place(0, nil, false) end,
    suckDown = function(requestedCount) return robotHardware.suck(0, requestedCount) end,
    useDown = function() return robotHardware.use(0, nil, false) end,
    swingDown = function() return robotHardware.swing(0, nil, false) end,
    count = robotHardware.count,
    inventorySize = robotHardware.inventorySize,
    transferTo = robotHardware.transferTo,
    inventoryAccess = RobotHardware.inventoryAccess(robotHardware, inventoryController)
  }, inventoryController
end

return RobotHardware
