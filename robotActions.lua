local component = require('component')
local os = require('os')
local robot = require('robot')
local sides = require('sides')
local computer = require('computer')
local config = require('robotConfig')
local gps = require('robotGPS')
local inventory_controller = component.inventory_controller
local redstone = component.redstone
local emptyCropSticks = false;


local function needCharge()
    return computer.energy() / computer.maxEnergy() < config.needChargeLevel
end


local function fullyCharged()
    return computer.energy() / computer.maxEnergy() > 0.99
end


local function fullInventory()
    for i = 1, robot.inventorySize() do
        if robot.count(i) == 0 then
            return false
        end
    end
    return true
end

local function restockStick()
    local selectedSlot = robot.select()
    gps.go(config.stickContainerPos)
    robot.select(robot.inventorySize() + config.stickSlot)

    for i = 1, inventory_controller.getInventorySize(sides.down) do
        os.sleep(0)
        inventory_controller.suckFromSlot(sides.down, i, 64 - robot.count())
        if robot.count() == 64 then
            break
        end
    end

    robot.select(selectedSlot)

    if robot.count(robot.inventorySize() + config.stickSlot) < 32 then
        emptyCropSticks = true;
        return false;
    end
end

local function dumpInventory()
    local selectedSlot = robot.select()
    gps.go(config.storagePos)

    local chestSize = inventory_controller.getInventorySize(sides.down) or 0
    local invSize = robot.inventorySize() + config.storageStopSlot
    local chestFull = false

    for i = 1, invSize do
        os.sleep(0)
        if robot.count(i) > 0 then
            robot.select(i)
            if chestFull then
                robot.dropUp()
            else
                local placed = false
                for slot = 1, chestSize do
                    if inventory_controller.getStackInSlot(sides.down, slot) == nil then
                        if inventory_controller.dropIntoSlot(sides.down, slot) then
                            placed = true
                            break
                        end
                    end
                end

                if not placed then
                    robot.dropUp()
                    chestFull = true
                end
            end
        end
    end

    robot.select(selectedSlot)
end





local function placeCropStick(count)
    local selectedSlot = robot.select()

    if count == nil then
        count = 1
    end

    if robot.count(robot.inventorySize() + config.stickSlot) < (count + 1) * 3 then
        if emptyCropSticks then
            return;
        end

        gps.save()
        if not restockStick() then
            return;
        end
        gps.resume()
    end

    robot.select(robot.inventorySize() + config.stickSlot)
    inventory_controller.equip()

    for _ = 1, count do
        robot.useDown()
    end

    inventory_controller.equip()
    robot.select(selectedSlot)
end


local function deweed()
    local selectedSlot = robot.select()

    if config.keepDrops and fullInventory() then
        gps.save()
        dumpInventory()
        gps.resume()
    end

    robot.select(robot.inventorySize() + config.trowelSlot)
    inventory_controller.equip()
    robot.useDown()

    if config.keepDrops then
        robot.suckDown()
    end

    inventory_controller.equip()
    robot.select(selectedSlot)
end

local function removePlant(needCropStick)
    if needCropStick == nil then
        needCropStick = false
    end

    if config.keepDrops and fullInventory() then
        gps.save()
        dumpInventory()
        gps.resume()
    end

    local selectedSlot = robot.select()


    robot.swingDown()
    if config.KeepDrops then
        robot.suckDown()
    end
    if needCropStick then
        placeCropStick(2)
    end

    --inventory_controller.equip()
    robot.select(selectedSlot)
end

local function clearSlot()
    robot.swingDown()
end


local function pulseDown()
    redstone.setOutput(sides.down, 15)
    os.sleep(0.1)
    redstone.setOutput(sides.down, 0)
end


local function manualTransplant(order)
    local fromSlot, toSlot = order.fromSlot, order.toSlot
    local fromFarm, toFarm = order.fromFarm, order.toFarm
    local toSlotName = order.toSlotName or nil
    local destroyTo = order.destroyTo
    if destroyTo == nil then
        destroyTo = true
    end

    if not fromSlot or not toSlot or not fromFarm or not toFarm or not toSlotName then
        return
    end

    local fromPos = (fromFarm == 'working' and gps.workingSlotToPos(fromSlot)) or
        (fromFarm == 'storage' and gps.storageSlotToPos(fromSlot))
    local toPos = (toFarm == 'working' and gps.workingSlotToPos(toSlot)) or
        (toFarm == 'storage' and gps.storageSlotToPos(toSlot))

    if not (fromPos and toPos) then
        return
    end

    local selectedSlot = robot.select()
    robot.select(robot.inventorySize() + config.binderSlot)
    inventory_controller.equip()

    gps.go(fromPos)
    robot.useDown(sides.down, true)

    gps.go(config.dislocatorPos)
    pulseDown()
    robot.useDown(sides.down, true)

    gps.go(toPos)
    if toSlotName == 'air' then
        placeCropStick()
    end
    robot.useDown(sides.down, true)

    gps.go(config.dislocatorPos)
    pulseDown()
    robot.useDown(sides.down, true)


    -- TODO DESTROY FROM CROP
    if not destroyTo then
        gps.go(fromPos)
        placeCropStick()
        robot.useDown(sides.down, true)

        gps.go(config.dislocatorPos)
        pulseDown()
        robot.useDown(sides.down, true)
    end

    -- Destroy original crop
    inventory_controller.equip()
    gps.go(config.relayFarmlandPos)
    robot.swingDown()
    if config.KeepDrops then
        robot.suckDown()
    end

    robot.select(selectedSlot)
end

local function transplant(order)
    local dest = nil
    local src = gps.workingSlotToPos(order.slot)
    if order.farm == 'storage' then
        dest = gps.storageSlotToPos(order.to)
    elseif order.farm == 'working' then
        dest = gps.workingSlotToPos(order.to)
    else
        return
    end

    local selectedSlot = robot.select()

    --gps.save()
    robot.select(robot.inventorySize() + config.binderSlot)
    inventory_controller.equip()

    -- Transfer to relay location
    gps.go(src)
    robot.useDown(sides.down, true)
    gps.go(config.dislocatorPos)
    pulseDown()

    -- Transfer crop to destination
    robot.useDown(sides.down, true)
    gps.go(dest)

    --print(order.slotName)
    if order.slotName == 'air' then
        placeCropStick()
    end

    robot.useDown(sides.down, true)
    gps.go(config.dislocatorPos)
    pulseDown()

    -- Reprime binder
    robot.useDown(sides.down, true)

    -- Destroy original crop
    inventory_controller.equip()
    gps.go(config.relayFarmlandPos)
    robot.swingDown()
    if config.KeepDrops then
        robot.suckDown()
    end

    --gps.resume()
    robot.select(selectedSlot)
end

local function charge()
    gps.go(config.chargerPos)
    gps.turnTo(1)
    repeat
        os.sleep(0.5)
    until fullyCharged()
end

local function primeBinder()
    local selectedSlot = robot.select()
    robot.select(robot.inventorySize() + config.binderSlot)
    inventory_controller.equip()

    -- Use binder at start to reset it, if already primed
    robot.useDown(sides.down, true)

    gps.go(config.dislocatorPos)
    robot.useDown(sides.down)

    inventory_controller.equip()
    robot.select(selectedSlot)
end


local function restockAll()
    dumpInventory()
    restockStick()
    charge()
end

local function initWork()
    charge()
    primeBinder()
    restockAll()
end

local function getEmptyCropSticksFlag()
    return emptyCropSticks;
end

local function setEmptyCropSticksFlag(flag)
    emptyCropSticks = flag;
end

--local function checkBase()
--
--end



return {
    needCharge = needCharge,
    charge = charge,
    restockStick = restockStick,
    dumpInventory = dumpInventory,
    restockAll = restockAll,
    clearSlot = clearSlot,
    placeCropStick = placeCropStick,
    deweed = deweed,
    removePlant = removePlant,
    pulseDown = pulseDown,
    transplant = transplant,
    manualTransplant = manualTransplant,
    initWork = initWork,
    getEmptyCropSticksFlag = getEmptyCropSticksFlag,
    setEmptyCropSticksFlag = setEmptyCropSticksFlag
}
