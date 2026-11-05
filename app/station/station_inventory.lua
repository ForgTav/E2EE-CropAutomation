local LinkProtocol = require("shared_link")
local Catalog = require("station_catalog")
local Quantity = require("station_production_rules")
local StationInventory = {}
local function validInventorySize(slotCount, minimumSlots)
  return type(slotCount) == "number" and slotCount >= minimumSlots and
      slotCount < math.huge and slotCount == math.floor(slotCount)
end
local function rotate(x, z, rotation)
  for _ = 1, rotation do x, z = -z, x end
  return x, z
end
function StationInventory.sides(rotation)
  assert(LinkProtocol.integer(rotation, 0, 3), "ORIENTATION_UNKNOWN")
  local function side(x, z)
    x, z = rotate(x, z, rotation)
    return x == -1 and 4 or (x == 1 and 5 or (z == -1 and 2 or 3))
  end
  return {
    output = side(1, 0),
    genebank = side(0, 1),
    io = side(-1, 0),
    trash = side(0, -1),
    drawer = 1
  }
end

function StationInventory.classify(sourceStack)
  if sourceStack.name == "ic2:crop_seed_bag" then
    local seed, err = require("station_seed_nbt").readNBT(sourceStack)
    if not seed then return nil, err end
    local function ident(identifier, maxLength) return #identifier <= maxLength and identifier:match("^[a-z0-9_.%-]+$") end
    if not ident(seed.owner, 32) or not ident(seed.id, 48) or
        not LinkProtocol.integer(seed.growth, 0, 31) or not LinkProtocol.integer(seed.gain, 0, 31) or
        not LinkProtocol.integer(seed.resistance, 0, 31) then
      return nil, "INVALID_SEED"
    end
    local key = seed.owner .. ":" .. seed.id
    if not Catalog.get(key) or Catalog.isDangerous(key, seed.growth) then return false end
    return {
      key = key,
      itemKind = "ic2",
      g = seed.growth,
      ga = seed.gain,
      r = seed.resistance
    }
  end
  local key = Catalog.vanilla(sourceStack.name)
  if key then return { key = key, itemKind = "vanilla" } end
end

local function better(candidate, archived)
  if candidate.itemKind ~= archived.itemKind then return candidate.itemKind == "ic2" end
  if candidate.itemKind == "vanilla" then return false end
  return math.abs(candidate.g - 12) + math.abs(candidate.ga - 15) + candidate.r <
      math.abs(archived.g - 12) + math.abs(archived.ga - 15) + archived.r
end
local function sameSeedDescriptor(first, second)
  return type(first) == "table" and type(second) == "table" and first.key == second.key and
      first.itemKind == second.itemKind and first.g == second.g and first.ga == second.ga and
      first.r == second.r and first.size == second.size
end
function StationInventory.new(deps)
  local transposer = deps.transposer
  local enabled, orderCriteria, credit = deps.enabled, deps.order, deps.credit
  local inventoryOperation, inventoryWorker, physicalFault, waitingReason
  local sortingOrder
  local transferUncertain = false
  local verifyingAddressed = false
  local orientationResetPending = false
  local drawerNotice
  local prepared = false
  local startupCheck = deps.startupCheck == true
  local inventorySides, drawerSlots, lockedRotation
  local genebankUsable, ioUsable, trashUsable
  local outputAvailable, genebankAvailable, trashAvailable
  local function recordAccess(side, available)
    if not inventorySides then return end
    if side == inventorySides.output then
      outputAvailable = available
    elseif side == inventorySides.genebank then
      genebankAvailable = available
    elseif side == inventorySides.trash then
      trashAvailable = available
    end
  end
  local stationHasIoAccess
  local genebankCatalogue, nextGenebankSlot, genebankLoaded = {}, 1, false
  local planningRevision = 0
  local bankRefreshPending = false
  local retrySortingAt, cargoFailure
  local passiveBankSlot, passiveBankAt = 1, deps.now() + 2
  local stickCount, stickKnown, stickNextCheck = 0, false, 0
  local transposerGeneration = transposer.generation()
  local api = {}
  local waitBeforeRetry
  local function same(first, second)
    return first and second and first.name == second.name and first.damage == second.damage and first.tag == second.tag
  end
  local function checkGeneration()
    assert(transposer.generation() == transposerGeneration, "INVENTORY_REPLACED")
  end
  local function waitForAccess(requiresIoAccess)
    while true do
      checkGeneration()
      if enabled() and (not requiresIoAccess or stationHasIoAccess) then return end
      coroutine.yield()
    end
  end
  local function size(side, minimum)
    waitForAccess(side == inventorySides.io)
    local success, slotCount, reason = pcall(transposer.getInventorySize, side)
    recordAccess(side, success and reason == nil and validInventorySize(slotCount, 1))
    coroutine.yield(); checkGeneration()
    if success and reason == nil and validInventorySize(slotCount, minimum) then return slotCount end
  end
  -- A failed read is an unavailable slot, never an empty slot.
  local function probe(side, slot)
    assert(verifyingAddressed or deps.rotation() == lockedRotation, "ORIENTATION_CHANGED")
    if side == inventorySides.genebank and not genebankUsable or side == inventorySides.io and ioUsable == false then
      return false
    end
    waitForAccess(side == inventorySides.io)
    local success, stack, reason = pcall(transposer.getStackInSlot, side, slot)
    coroutine.yield(); checkGeneration()
    local readable = success and reason == nil and (stack == nil or type(stack) == "table" and
      LinkProtocol.token(stack.name, 128) and LinkProtocol.integer(stack.size, 1, side == inventorySides.io and 64 or 2147483647))
    recordAccess(side, readable)
    return readable, readable and stack or nil
  end
  local function checkDrawerLayout()
    local slotCount = size(inventorySides.drawer, 1)
    drawerSlots = slotCount and math.min(slotCount, 54) or 0
    if drawerSlots == 0 then drawerNotice = "DRAWER_UNAVAILABLE" end
  end
  local function countSticks()
    drawerNotice = nil
    if drawerSlots == 0 then checkDrawerLayout() end
    local total = 0
    for slot = 1, drawerSlots do
      local readable, stack = probe(inventorySides.drawer, slot)
      if not readable then drawerNotice = drawerNotice or "DRAWER_UNREADABLE" end
      if readable and stack and stack.name == "ic2:crop_stick" then total = total + stack.size end
    end
    local changed = not stickKnown or total ~= stickCount
    stickCount, stickKnown, stickNextCheck = total, true, deps.now() + 2
    if changed then planningRevision = planningRevision + 1 end
  end
  local function layout()
    local rotation = deps.rotation()
    assert(LinkProtocol.integer(rotation, 0, 3), "ORIENTATION_UNKNOWN")
    lockedRotation = lockedRotation or rotation
    assert(lockedRotation == rotation, "ORIENTATION_CHANGED")
    inventorySides = StationInventory.sides(lockedRotation)
    size(inventorySides.output, 1)
    genebankUsable = size(inventorySides.genebank, 54) ~= nil
    trashUsable = size(inventorySides.trash, 1) ~= nil
    if not genebankUsable then passiveBankAt = deps.now() + 3 end
    checkDrawerLayout()
  end
  local function checkIoLayout()
    ioUsable = size(inventorySides.io, 27) ~= nil
    if not ioUsable then error("IO_UNAVAILABLE", 0) end
  end
  local function descriptor(sourceStack, slot)
    local success, seedDescriptor, operationError = pcall(StationInventory.classify, sourceStack)
    if not success or operationError then
      return nil, "CLASSIFICATION_FAILED", success and sourceStack.name == "ic2:crop_seed_bag"
    end
    if seedDescriptor then
      seedDescriptor.slot = slot; seedDescriptor.size = sourceStack.size
    end
    return seedDescriptor
  end
  local function selected(key, except)
    local lastSlot = genebankLoaded and 54 or nextGenebankSlot - 1
    for slot = 1, lastSlot do
      local seedDescriptor = genebankCatalogue[slot]
      if slot ~= except and type(seedDescriptor) == "table" and seedDescriptor.key == key then return seedDescriptor end
    end
  end
  local function recoverStocks()
    inventoryOperation.phase = "RECOVERING"
    inventoryOperation.material, inventoryOperation.plantingItemTaken = nil, nil
    prepared, genebankLoaded, bankRefreshPending = false, false, false
    genebankCatalogue, nextGenebankSlot = {}, 1
    planningRevision = planningRevision + 1
    for slot = 1, 54 do
      local readable, stack = probe(inventorySides.genebank, slot)
      local entry = true
      if readable and not stack then
        entry = false
      elseif readable then
        local seed = descriptor(stack, slot)
        if type(seed) == "table" and Catalog.canStore(seed.key) then
          local archived = selected(seed.key)
          if not archived then
            entry = seed
          elseif better(seed, archived) then
            genebankCatalogue[archived.slot] = true; entry = seed
          end
        end
      end
      genebankCatalogue[slot], nextGenebankSlot = entry, slot + 1
    end
    -- Inspect the actual exchange chest without crediting or replaying the old transfer.
    -- The following ordinary STARTUP will sort readable cargo by the existing rules.
    if stationHasIoAccess then
      for slot = 1, 27 do probe(inventorySides.io, slot) end
    end
    countSticks()
    genebankLoaded = true
    bankRefreshPending = not genebankUsable
    transferUncertain, verifyingAddressed = false, false
    assert(not orientationResetPending and deps.rotation() == lockedRotation, "ORIENTATION_CHANGED")
    passiveBankAt = deps.now() + 2
    inventoryOperation.failure = "TRANSFER_UNCONFIRMED"
    inventoryOperation.phase = "DONE"
  end
  local function move(from, to, slot, target, requestedCount, sourceStack, verifyTarget, append, outputOrder)
    local addressed = from == inventorySides.genebank and to == inventorySides.io or
        from == inventorySides.io and to == inventorySides.genebank or
        from == inventorySides.drawer or to == inventorySides.drawer
    local requiresIoAccess = from == inventorySides.io or to == inventorySides.io
    waitForAccess(requiresIoAccess)
    local destinationStack
    if verifyTarget then
      local readable
      readable, destinationStack = probe(to, target)
      if not readable then return 0, sourceStack, true end
    end
    if destinationStack and not (append and same(sourceStack, destinationStack) and
          (to == inventorySides.drawer or destinationStack.size + requestedCount <= 64)) then
      return 0, sourceStack, true
    end
    waitForAccess(requiresIoAccess)
    if outputOrder and outputOrder.invalidated then return 0, sourceStack, false, true end
    assert(deps.rotation() == lockedRotation, "ORIENTATION_CHANGED")
    local success, moved, operationError
    transferUncertain = true
    if to == inventorySides.output or to == inventorySides.trash then
      success, moved, operationError = pcall(transposer.transferItem, from, to, requestedCount, slot)
    else
      success, moved, operationError = pcall(transposer.transferItem, from, to, requestedCount, slot, target)
    end
    if success and operationError == nil and LinkProtocol.integer(moved, 1, requestedCount) then
      recordAccess(to, true)
    elseif not success or operationError ~= nil or not LinkProtocol.integer(moved, 0, requestedCount) then
      recordAccess(to, false)
    end
    if success and operationError == "TRANSFER_NOT_ATTEMPTED" then
      moved = 0; operationError = nil
    end
    transferUncertain = not (success and operationError == nil and LinkProtocol.integer(moved, 0, requestedCount))
    verifyingAddressed = addressed and transferUncertain
    if not outputOrder then coroutine.yield() end
    if transferUncertain then
      if not addressed then error("TRANSFER_RECOVERY", 0) end
      local attempts = 0
      while true do
        local sourceReadable, remainingStack, targetReadable, receivedStack
        sourceReadable, remainingStack = probe(from, slot)
        targetReadable, receivedStack = probe(to, target)
        local sourceCount = remainingStack and remainingStack.size or 0
        local receivedCount = receivedStack and receivedStack.size or 0
        local inferredCount = sourceStack.size - sourceCount
        local verified = sourceReadable and targetReadable and (not remainingStack or same(sourceStack, remainingStack)) and
            (not receivedStack or same(sourceStack, receivedStack)) and
            LinkProtocol.integer(inferredCount, 0, requestedCount) and
            receivedCount - (destinationStack and destinationStack.size or 0) == inferredCount
        if verified then
          moved = inferredCount; break
        end
        attempts = attempts + 1
        if attempts == 3 then error("TRANSFER_RECOVERY", 0) end
        waitBeforeRetry("TRANSFER_UNVERIFIED")
      end
      transferUncertain, verifyingAddressed = false, false
      assert(not orientationResetPending and deps.rotation() == lockedRotation, "ORIENTATION_CHANGED")
    end
    if outputOrder and moved > 0 then assert(credit(outputOrder.id, moved), "OUTPUT_SAVE_FAILED") end
    if outputOrder then coroutine.yield() end
    local after
    if moved < sourceStack.size then
      after = {}; for fieldName, fieldValue in pairs(sourceStack) do after[fieldName] = fieldValue end
      after.size = sourceStack.size - moved
    end
    return moved, after
  end
  waitBeforeRetry = function(reason, delay)
    waitingReason = reason
    local untilAt = deps.now() + (delay or 3)
    repeat
      checkGeneration(); coroutine.yield()
    until deps.now() >= untilAt and enabled()
    waitingReason = nil
  end
  local function canDiscard(to)
    if to ~= inventorySides.trash or trashUsable then return true end
    trashUsable = size(inventorySides.trash, 1) ~= nil
    if trashUsable then return true end
    inventoryOperation.failure = "TRASH_UNAVAILABLE"
    return false
  end
  local function deliver(sourceSide, slot, sourceStack, to)
    if not canDiscard(to) then return sourceStack end
    while sourceStack do
      local moved, after = move(sourceSide, to, slot, 1, sourceStack.size, sourceStack, false)
      sourceStack = after
      if sourceStack and moved == 0 then waitBeforeRetry(to == inventorySides.output and "OUTPUT_FULL" or "TRASH_BLOCKED") end
    end
  end
  local function discardArchive(slot, sourceStack, to)
    to = to or inventorySides.trash
    if not canDiscard(to) then return sourceStack end
    while sourceStack do
      local moved, after = move(inventorySides.genebank, to, slot, 1, sourceStack.size, sourceStack, false)
      local catalogueEntry = genebankCatalogue[slot]
      if after and type(catalogueEntry) == "table" then catalogueEntry.size = after.size end
      sourceStack = after
      if sourceStack and moved == 0 then waitBeforeRetry(to == inventorySides.output and "OUTPUT_FULL" or "TRASH_BLOCKED") end
    end
    genebankCatalogue[slot] = false
  end
  local function storeSticks(sourceSide, sourceSlot, sourceStack)
    drawerNotice = nil
    local unavailable = drawerSlots == 0
    for destinationSlot = 1, drawerSlots do
      local readable, storedStack = probe(inventorySides.drawer, destinationSlot)
      if not readable then
        unavailable = true
      elseif storedStack and storedStack.name ~= "ic2:crop_stick" then
        drawerNotice = drawerNotice or "DRAWER_ITEM_MISMATCH:" .. destinationSlot
      else
        local _, remaining, destinationUnavailable = move(sourceSide, inventorySides.drawer, sourceSlot,
          destinationSlot, sourceStack.size, sourceStack, true, true)
        unavailable = unavailable or destinationUnavailable
        sourceStack = remaining
        if not sourceStack then return end
      end
    end
    if unavailable then
      drawerNotice = drawerNotice or "DRAWER_UNREADABLE"
      inventoryOperation.failure = "DRAWER_UNREADABLE"; return sourceStack
    end
    return deliver(sourceSide, sourceSlot, sourceStack, inventorySides.trash)
  end
  local function registerSlot(slot, sourceStack)
    local previousEntry = genebankCatalogue[slot]
    if not sourceStack then
      genebankCatalogue[slot] = false; return previousEntry ~= false
    end
    genebankCatalogue[slot] = true
    if sourceStack.name == "ic2:crop_stick" then
      local remaining = storeSticks(inventorySides.genebank, slot, sourceStack)
      genebankCatalogue[slot] = remaining ~= nil
      return previousEntry ~= genebankCatalogue[slot]
    end
    local seedDescriptor, operationError, invalidNBT = descriptor(sourceStack, slot)
    if invalidNBT then
      discardArchive(slot, sourceStack); return previousEntry ~= genebankCatalogue[slot]
    end
    if operationError then return previousEntry ~= true end
    if seedDescriptor == false then
      discardArchive(slot, sourceStack); return previousEntry ~= genebankCatalogue[slot]
    end
    if not seedDescriptor then
      discardArchive(slot, sourceStack, inventorySides.output); return previousEntry ~= false
    end
    if not Catalog.canStore(seedDescriptor.key) then
      discardArchive(slot, sourceStack, inventorySides.output); return previousEntry ~= false
    end
    local archiveEntry = selected(seedDescriptor.key, slot)
    if archiveEntry and genebankLoaded then
      while true do
        local readable, archiveStack = probe(inventorySides.genebank, archiveEntry.slot)
        if not readable then
          genebankCatalogue[archiveEntry.slot] = true; bankRefreshPending = true; return true
        end
        local archiveFacts, classError, invalidSeed
        if archiveStack then archiveFacts, classError, invalidSeed = descriptor(archiveStack, archiveEntry.slot) end
        if classError and not invalidSeed then
          genebankCatalogue[archiveEntry.slot] = true; bankRefreshPending = true; return true
        else
          if not sameSeedDescriptor(archiveEntry, archiveFacts) then
            bankRefreshPending = true; return false
          end
          break
        end
      end
    end
    local changed = false
    if archiveEntry then
      if not better(seedDescriptor, archiveEntry) then
        discardArchive(slot, sourceStack); return previousEntry ~= genebankCatalogue[slot]
      end
      if discardArchive(archiveEntry.slot, archiveEntry) then return previousEntry ~= true end
      changed = true
    end
    genebankCatalogue[slot] = seedDescriptor
    return changed or not sameSeedDescriptor(previousEntry, seedDescriptor)
  end
  local function reconcileBank(rebuild)
    if rebuild then
      nextGenebankSlot, genebankLoaded = 1, false
      inventoryOperation.phase = "SCANNING"
    end
    if genebankLoaded then return false end
    if not genebankUsable and deps.now() >= passiveBankAt then
      genebankUsable = size(inventorySides.genebank, 54) ~= nil
    end
    if not genebankUsable then
      local changed = false
      for slot = 1, 54 do
        if genebankCatalogue[slot] ~= true then changed = true end
        genebankCatalogue[slot] = true
      end
      genebankLoaded, bankRefreshPending, passiveBankAt = true, true, deps.now() + 3
      inventoryOperation.failure = "GENEBANK_UNAVAILABLE"
      return changed
    end
    local changed = false
    while nextGenebankSlot <= 54 do
      local slot = nextGenebankSlot
      local readable, sourceStack = probe(inventorySides.genebank, slot)
      if readable then
        if registerSlot(slot, sourceStack) then changed = true end
      else
        if genebankCatalogue[slot] ~= true then changed = true end
        genebankCatalogue[slot] = true
      end
      nextGenebankSlot = slot + 1
    end
    genebankLoaded, bankRefreshPending = true, false
    return changed
  end
  local function sort(slot, sourceStack)
    sortingOrder = nil
    waitForAccess(false)
    if slot >= 23 and slot <= 26 and sourceStack.name == "ic2:crop_seed_bag" then
      deliver(inventorySides.io, slot, sourceStack, inventorySides.trash); return
    end
    local order = orderCriteria()
    sortingOrder = order
    local seedDescriptor, operationError, invalidNBT
    while sourceStack.name ~= "ic2:crop_stick" do
      seedDescriptor, operationError, invalidNBT = descriptor(sourceStack)
      if not operationError then break end
      if invalidNBT then
        deliver(inventorySides.io, slot, sourceStack, inventorySides.trash); return
      end
      inventoryOperation.failure = operationError; return
    end
    if sourceStack.name == "ic2:crop_stick" then
      storeSticks(inventorySides.io, slot, sourceStack); return
    end
    if seedDescriptor == false then
      deliver(inventorySides.io, slot, sourceStack, inventorySides.trash); return
    end
    if seedDescriptor and Catalog.canStore(seedDescriptor.key) then
      if not genebankUsable then
        inventoryOperation.failure = "GENEBANK_UNAVAILABLE"; return
      end
      local archiveEntry = selected(seedDescriptor.key)
      if not archiveEntry or better(seedDescriptor, archiveEntry) then
        local target
        if archiveEntry then
          target = archiveEntry.slot
          if discardArchive(target, archiveEntry) then return end
          planningRevision = planningRevision + 1
        else
          for i = 1, 54 do
            if genebankCatalogue[i] == false then
              target = i; break
            end
          end
        end
        local moved, after
        repeat
          local searched = 0
          while not target and searched < 54 do
            searched = searched + 1
            local bankSlot = passiveBankSlot
            passiveBankSlot = bankSlot % 54 + 1
            local readable, stack = probe(inventorySides.genebank, bankSlot)
            if readable and not stack then
              if genebankCatalogue[bankSlot] ~= false then
                genebankCatalogue[bankSlot] = false; planningRevision = planningRevision + 1
              end
              target = bankSlot
            end
          end
          if not target then
            inventoryOperation.failure = "GENEBANK_FULL"; return
          end
          local destinationOccupied
          moved, after, destinationOccupied = move(inventorySides.io, inventorySides.genebank, slot, target, 1,
            sourceStack, true, false)
          if destinationOccupied then
            genebankCatalogue[target] = true; bankRefreshPending = true
            planningRevision = planningRevision + 1
            passiveBankSlot = target % 54 + 1; target = nil
          elseif moved == 0 then
            local previousTarget = target
            for offset = 1, 53 do
              local candidate = (previousTarget + offset - 1) % 54 + 1
              if genebankCatalogue[candidate] == false then
                target = candidate; break
              end
            end
            if target <= previousTarget then
              inventoryOperation.failure = "GENEBANK_TRANSFER_BLOCKED"; return
            end
          end
        until moved == 1
        seedDescriptor.slot = target; seedDescriptor.size = moved; genebankCatalogue[target] = seedDescriptor; sourceStack =
            after
        planningRevision = planningRevision + 1
      end
    end
    if sourceStack and seedDescriptor and order and Quantity.matchesDescriptor(seedDescriptor, order) then
      local remaining = order.remaining
      while sourceStack and remaining > 0 do
        local moved, after, _, orderChanged = move(inventorySides.io, inventorySides.output, slot, nil,
          math.min(remaining, sourceStack.size), sourceStack, false, false, order)
        sourceStack = after; remaining = remaining - moved
        if orderChanged or order.invalidated then break end
        if moved == 0 then
          waitBeforeRetry("OUTPUT_FULL")
          local currentOrder = orderCriteria()
          if order.invalidated or not currentOrder or currentOrder.id ~= order.id then break end
        end
      end
    end
    if sourceStack then
      deliver(inventorySides.io, slot, sourceStack,
        seedDescriptor and inventorySides.trash or inventorySides.output)
    end
    sortingOrder = nil
  end
  local function replenish()
    local readable, storedStack = probe(inventorySides.io, 1)
    if not readable then
      inventoryOperation.failure = "IO_UNREADABLE"; return
    end
    while storedStack and storedStack.name ~= "ic2:crop_stick" do
      sort(1, storedStack)
      local after
      readable, after = probe(inventorySides.io, 1)
      if not readable then
        inventoryOperation.failure = "IO_UNREADABLE"; return
      end
      if after and same(storedStack, after) and storedStack.size == after.size then return end
      storedStack = after
    end
    local needed = 64 - (storedStack and storedStack.size or 0)
    if needed > 0 then drawerNotice = nil end
    for source = 1, drawerSlots do
      if needed == 0 then break end
      local readable, sourceStack = probe(inventorySides.drawer, source)
      if not readable then
        drawerNotice = drawerNotice or "DRAWER_UNREADABLE"
      elseif sourceStack and sourceStack.name ~= "ic2:crop_stick" then
        drawerNotice = drawerNotice or "DRAWER_ITEM_MISMATCH:" .. source
      elseif sourceStack then
        local requestedCount = move(inventorySides.drawer, inventorySides.io, source, 1,
          math.min(needed, sourceStack.size), sourceStack, true, true)
        needed = needed - requestedCount
      end
    end
  end
  local function complete()
    checkGeneration()
    inventoryOperation.phase = "DONE"
    if inventoryOperation.kind == "STARTUP" then prepared = true end
    if inventoryOperation.kind == "STARTUP" or inventoryOperation.kind == "SORT_CARGO" then
      cargoFailure = inventoryOperation.failure
      retrySortingAt = inventoryOperation.failure and deps.now() + 3 or nil
    end
  end
  local function sorting()
    inventoryOperation.phase = "SORTING"
    for slot = 2, 27 do
      inventoryOperation.cargoSlot = slot
      local readable, sourceStack = probe(inventorySides.io, slot)
      if not readable then
        inventoryOperation.failure = "IO_UNREADABLE"
      else
        if slot == 27 then inventoryOperation.plantingItemTaken = sourceStack == nil end
        if sourceStack then sort(slot, sourceStack) end
      end
    end
    replenish(); complete()
  end
  local function begin(operationKind, sourceSlot, expectedSeed)
    inventoryOperation = { kind = operationKind, phase = "PRECHECK" }
    inventoryWorker = coroutine.create(function()
      local rebuildingBank = operationKind ~= "PREPARE_EXCHANGE" and bankRefreshPending
      if reconcileBank(rebuildingBank) then planningRevision = planningRevision + 1 end
      if operationKind == "STARTUP" then checkIoLayout() end
      if operationKind == "PREPARE_EXCHANGE" then
        replenish()
        if inventoryOperation.failure then
          complete(); return
        end
        if sourceSlot then
          local attempts = 0
          repeat
            local readable, sourceStack = probe(inventorySides.genebank, sourceSlot)
            local catalogueEntry, classError, invalidSeed
            if sourceStack then catalogueEntry, classError, invalidSeed = descriptor(sourceStack, sourceSlot) end
            local matchesExpected = true
            if expectedSeed and type(catalogueEntry) == "table" then
              matchesExpected = expectedSeed.key == catalogueEntry.key and expectedSeed.itemKind ==
                  catalogueEntry.itemKind and
                  expectedSeed.g == catalogueEntry.g and expectedSeed.ga == catalogueEntry.ga and
                  expectedSeed.r == catalogueEntry.r
            end
            if not readable or classError and not invalidSeed then
              genebankCatalogue[sourceSlot] = true; planningRevision = planningRevision + 1
              inventoryOperation.failure = "SEED_SOURCE_UNREADABLE"
            elseif not sourceStack then
              inventoryOperation.failure = "SEED_SOURCE_MISSING"
            elseif type(catalogueEntry) ~= "table" or not Catalog.canStore(catalogueEntry.key) or not matchesExpected then
              inventoryOperation.failure = "SEED_SOURCE_CHANGED"
            else
              local moved, remaining = move(inventorySides.genebank, inventorySides.io, sourceSlot, 27, 1, sourceStack,
                true, false)
              if moved == 0 then
                attempts = attempts + 1
                if attempts == 3 then
                  inventoryOperation.failure = "SEED_TRANSFER_BLOCKED"
                else
                  waitBeforeRetry("SEED_TRANSFER_BLOCKED")
                end
              elseif remaining then
                catalogueEntry.size = remaining.size; genebankCatalogue[sourceSlot] = catalogueEntry
              else
                genebankCatalogue[sourceSlot] = false
              end
              if moved > 0 then
                inventoryOperation.material = catalogueEntry
                planningRevision = planningRevision + 1
                break
              end
            end
          until inventoryOperation.failure
          if inventoryOperation.failure == "SEED_SOURCE_MISSING" or inventoryOperation.failure == "SEED_SOURCE_CHANGED" then
            bankRefreshPending = true
          end
        end
        complete()
      else
        sorting()
      end
    end)
  end
  local function beginStickCheck()
    inventoryOperation = { kind = "CHECK_STICKS", phase = "READING" }
    inventoryWorker = coroutine.create(function()
      countSticks()
      complete()
    end)
  end
  local function beginBankCheck(fullPass, slot)
    inventoryOperation = { kind = fullPass and "RECONCILE_BANK" or "PASSIVE_BANK", phase = "PRECHECK" }
    inventoryWorker = coroutine.create(function()
      local initialLoad = not drawerSlots
      if initialLoad then layout() end
      if not initialLoad and not trashUsable then trashUsable = size(inventorySides.trash, 1) ~= nil end
      local changed
      if fullPass then
        changed = reconcileBank(true)
      else
        local readable, sourceStack = probe(inventorySides.genebank, slot)
        if readable then
          inventoryOperation.phase = "REGISTERING"
          changed = registerSlot(slot, sourceStack)
        else
          changed = genebankCatalogue[slot] ~= true; genebankCatalogue[slot] = true
        end
        passiveBankSlot = slot % 54 + 1
      end
      if changed then planningRevision = planningRevision + 1 end
      if not initialLoad then passiveBankAt = deps.now() + 2 end
      complete()
    end)
  end
  function api.prepareExchange(sourceSlot, expectedSeed)
    if not prepared or inventoryOperation or (bankRefreshPending and sourceSlot ~= nil) or physicalFault or (sourceSlot ~= nil and not LinkProtocol.integer(sourceSlot, 1, 54)) then
      return nil, "INVENTORY_BUSY"
    end
    begin("PREPARE_EXCHANGE", sourceSlot, expectedSeed); return true
  end

  function api.sortCargo()
    if not prepared or inventoryOperation or physicalFault then return nil, "INVENTORY_BUSY" end
    begin("SORT_CARGO"); return true
  end

  function api.invalidateOrder(orderId)
    if sortingOrder and sortingOrder.id == orderId then sortingOrder.invalidated = true end
  end

  local function block(reason) physicalFault = physicalFault or reason end
  local function resetHardware(failure)
    failure = failure or (transferUncertain and "TRANSFER_UNCONFIRMED" or "INVENTORY_REPLACED")
    transferUncertain, verifyingAddressed = false, false
    transposerGeneration = transposer.generation(); prepared = false
    startupCheck = not enabled()
    outputAvailable, genebankAvailable, trashAvailable = nil, nil, nil
    genebankCatalogue, nextGenebankSlot, genebankLoaded = {}, 1, false
    bankRefreshPending, drawerSlots, waitingReason, drawerNotice = false, nil, nil, nil
    genebankUsable, ioUsable, trashUsable = nil, nil, nil
    retrySortingAt, cargoFailure = nil, nil
    stickKnown, stickNextCheck = false, 0
    planningRevision = planningRevision + 1
    if inventoryOperation then
      inventoryOperation.phase = "DONE"; inventoryOperation.failure = failure
      inventoryOperation.material, inventoryOperation.plantingItemTaken = nil, nil
    end
  end
  local function resetOrientation()
    inventoryWorker = nil
    resetHardware("ORIENTATION_CHANGED")
    lockedRotation, inventorySides, sortingOrder = nil, nil, nil
    orientationResetPending = false
    if inventoryOperation and (inventoryOperation.kind == "STARTUP_CHECK" or inventoryOperation.kind == "PASSIVE_BANK" or
          inventoryOperation.kind == "RECONCILE_BANK" or inventoryOperation.kind == "CHECK_STICKS") then
      inventoryOperation = nil
    end
  end
  function api.step(hasIoAccess, allowBankCheck)
    stationHasIoAccess = hasIoAccess == true
    if physicalFault then return end
    local rotation = deps.rotation()
    if lockedRotation ~= nil and rotation ~= nil and lockedRotation ~= rotation then
      orientationResetPending, prepared = true, false
    end
    if rotation == nil and not verifyingAddressed then return end
    if orientationResetPending and not verifyingAddressed then
      prepared = false
      if transferUncertain then resetHardware("TRANSFER_UNCONFIRMED") end
      if not stationHasIoAccess then
        waitingReason = "ORIENTATION_CHANGED"; return
      end
      resetOrientation()
    end
    if inventoryOperation and inventoryOperation.kind == "PASSIVE_BANK" and
        inventoryOperation.phase == "PRECHECK" and not allowBankCheck then
      inventoryWorker, inventoryOperation, waitingReason = nil, nil, nil
    end
    if not inventoryWorker and transposer.generation() ~= transposerGeneration then resetHardware() end
    if enabled() then startupCheck = false end
    if startupCheck and not inventoryWorker and (not inventoryOperation or inventoryOperation.phase == "DONE") then
      startupCheck = false
      inventorySides = StationInventory.sides(rotation)
      inventoryOperation = inventoryOperation or { kind = "STARTUP_CHECK", phase = "READING" }
      inventoryWorker = coroutine.create(function()
        for _, side in ipairs({ inventorySides.output, inventorySides.genebank, inventorySides.trash }) do
          local success, slotCount, apiError = pcall(transposer.getInventorySize, side)
          recordAccess(side, success and apiError == nil and validInventorySize(slotCount, 1))
          coroutine.yield()
          checkGeneration()
        end
      end)
    end
    if not inventoryWorker and not inventoryOperation then
      if not enabled() then return end
      if not genebankLoaded then
        beginBankCheck(true)
      elseif not prepared and stationHasIoAccess and (not retrySortingAt or deps.now() >= retrySortingAt) then
        begin("STARTUP")
      elseif bankRefreshPending and allowBankCheck and (genebankUsable or deps.now() >= passiveBankAt) then
        beginBankCheck(true)
      elseif prepared and stationHasIoAccess and allowBankCheck and retrySortingAt and deps.now() >= retrySortingAt then
        retrySortingAt = nil; begin("SORT_CARGO")
      elseif allowBankCheck and not bankRefreshPending and deps.now() >= passiveBankAt then
        passiveBankAt = deps.now() + 2
        beginBankCheck(false, passiveBankSlot)
      elseif prepared and deps.now() >= stickNextCheck then
        beginStickCheck()
      end
    end
    if not inventoryWorker then return end
    local success, operationError = coroutine.resume(inventoryWorker)
    if not success then
      local reason = tostring(operationError):match("([A-Z][A-Z_]+)$") or "INVENTORY_ERROR"
      inventoryWorker = nil
      if reason == "INVENTORY_REPLACED" then
        resetHardware()
        if inventoryOperation.kind == "STARTUP_CHECK" or inventoryOperation.kind == "PASSIVE_BANK" or inventoryOperation.kind == "RECONCILE_BANK" or inventoryOperation.kind == "CHECK_STICKS" then inventoryOperation = nil end
      elseif reason == "TRANSFER_RECOVERY" then
        inventoryWorker = coroutine.create(recoverStocks)
      elseif reason == "IO_UNAVAILABLE" then
        inventoryOperation.phase, inventoryOperation.failure = "DONE", reason
        inventoryOperation.material, inventoryOperation.plantingItemTaken = nil, nil
        prepared, retrySortingAt = false, deps.now() + 3
      elseif reason == "ORIENTATION_CHANGED" and not transferUncertain then
        orientationResetPending, prepared = true, false
        if stationHasIoAccess then resetOrientation() else waitingReason = "ORIENTATION_CHANGED" end
      else
        block(reason)
      end
    elseif coroutine.status(inventoryWorker) == "dead" then
      inventoryWorker = nil
      if inventoryOperation.kind == "STARTUP_CHECK" or inventoryOperation.kind == "PASSIVE_BANK" or inventoryOperation.kind == "RECONCILE_BANK" or inventoryOperation.kind == "CHECK_STICKS" then inventoryOperation = nil end
    end
  end

  function api.release()
    if inventoryOperation and inventoryOperation.phase == "DONE" and not physicalFault then
      inventoryOperation = nil; sortingOrder = nil; return true
    end
    return nil, "INVENTORY_BUSY"
  end

  function api.snapshot()
    local outputAccess, genebankAccess, trashAccess = outputAvailable, genebankAvailable, trashAvailable
    if transposer.generation() ~= transposerGeneration then outputAccess, genebankAccess, trashAccess = nil, nil, nil end
    return {
      phase = inventoryOperation and inventoryOperation.phase,
      kind = inventoryOperation and inventoryOperation.kind,
      outputAvailable = outputAccess,
      genebankAvailable = genebankAccess,
      trashAvailable = trashAccess,
      fault = physicalFault,
      waiting = waitingReason,
      failure = inventoryOperation and inventoryOperation.failure,
      problem = inventoryOperation and inventoryOperation.failure or
          (ioUsable == false and "IO_UNAVAILABLE" or genebankUsable == false and "GENEBANK_UNAVAILABLE" or
            trashUsable == false and "TRASH_UNAVAILABLE") or cargoFailure,
      notice = drawerNotice,
      stickCount = stickKnown and stickCount or nil,
      stickReady = stickKnown and stickCount >= 64,
      uncertain = physicalFault ~= nil,
      busy = not prepared or inventoryOperation ~= nil,
      bankRefreshPending = bankRefreshPending,
      backgroundRead = prepared and inventoryOperation ~= nil and
          (inventoryOperation.kind == "CHECK_STICKS" or
            inventoryOperation.kind == "PASSIVE_BANK" and inventoryOperation.phase == "PRECHECK"),
      prepared = prepared,
      plantingItemTaken = inventoryOperation and inventoryOperation.plantingItemTaken,
      material = inventoryOperation and inventoryOperation.material,
      bankLoaded = genebankLoaded,
      cargoSlot = inventoryOperation and inventoryOperation.cargoSlot
    }
  end

  function api.catalogue() return genebankCatalogue end

  function api.archiveDisposition(seedDescriptor)
    if not genebankLoaded or not Catalog.canStore(seedDescriptor.key) then return "SKIP" end
    local archiveEntry = selected(seedDescriptor.key)
    if archiveEntry then return better(seedDescriptor, archiveEntry) and "REPLACE" or "SKIP" end
    for slot = 1, 54 do if genebankCatalogue[slot] == false then return "KEEP" end end
    return "FULL"
  end

  function api.planningRevision() return planningRevision end

  function api.fault() return physicalFault end

  function api.busy() return inventoryWorker ~= nil end

  return api
end

return StationInventory
