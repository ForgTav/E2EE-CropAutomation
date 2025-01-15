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

    if robot.count(robot.inventorySize() + config.stickSlot) < 3 * 3 then
        emptyCropSticks = true;
        return false;
    end
end



local function dumpInventory()
    local selectedSlot = robot.select()
    gps.go(config.storagePos)

    for i = 1, (robot.inventorySize() + config.storageStopSlot) do
        os.sleep(0)
        if robot.count(i) > 0 then
            robot.select(i)
            for e = 1, inventory_controller.getInventorySize(sides.down) do
                if inventory_controller.getStackInSlot(sides.down, e) == nil then
                    inventory_controller.dropIntoSlot(sides.down, e)
                    break
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

    robot.select(robot.inventorySize() + config.spadeSlot)
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


local function pulseDown()
    redstone.setOutput(sides.down, 15)
    os.sleep(0.1)
    redstone.setOutput(sides.down, 0)
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




return {
    needCharge = needCharge,
    charge = charge,
    restockStick = restockStick,
    dumpInventory = dumpInventory,
    restockAll = restockAll,
    placeCropStick = placeCropStick,
    deweed = deweed,
    removePlant = removePlant,
    pulseDown = pulseDown,
    transplant = transplant,
    initWork = initWork,
    getEmptyCropSticksFlag = getEmptyCropSticksFlag
}
