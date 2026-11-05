local RobotHand = {}

function RobotHand.new(deps)
  local access, inventory, inventoryMap, wait = deps.inventoryAccess, deps.inventory, deps.inventoryMap, deps.wait
  local api = {}
  local workingSlot, workingStack, minimumRemaining, mayBeConsumed
  local function same(first, second)
    return (not first and not second) or (first and second and first.name == second.name and first.size == second.size)
  end
  local function matchesHeld(stack, expected, mayBeConsumed, minimumSize)
    return same(stack, expected) or (mayBeConsumed and not stack) or
        (minimumSize and stack and stack.name == expected.name and
          stack.size >= minimumSize and stack.size <= expected.size)
  end
  local function read(slot, optional)
    while true do
      local version = inventoryMap.version(slot)
      local readable, stack = access.readStack(slot)
      if readable then inventoryMap.observed(slot, stack, version) end
      coroutine.yield()
      if readable and version == inventoryMap.version(slot) then return stack, version, true end
      if optional then return nil, nil, false end
      wait("HAND_UNREADABLE")
    end
  end
  local function select(slot, version)
    local success, selectedSlot = access.selectSlot(slot)
    return success and selectedSlot == slot and version == inventoryMap.version(slot)
  end
  -- Store an unknown/possibly consumed held item into an empty slot.
  -- A nonempty result proves the swap; an empty result needs a successful reply.
  function api.store(slot)
    local before, version, readable = read(slot, true)
    if not readable or before or not select(slot, version) then return false end
    local success, swapped, reason = pcall(inventory.equip)
    coroutine.yield()
    local after = read(slot)
    return after ~= nil or (success and reason == nil and swapped == true), after
  end

  -- Return known held equipment, retaining anything displaced from the slot.
  -- Resolve the physical result before retrying; a lost reply must never
  -- swap the items back.
  -- A used tool may have broken, leaving the hand empty before this call.
  -- minimumHeldSize bounds a consumable remainder after an attempted use.
  function api.swap(slot, expectedHeld, expectedStored, mayBeConsumed, minimumHeldSize)
    local before, version = read(slot)
    if (expectedStored and not same(before, expectedStored)) or not select(slot, version) then
      return false
    end
    local success, swapped, reason = pcall(inventory.equip)
    coroutine.yield()
    while true do
      local after = read(slot)
      local heldMatches = matchesHeld(after, expectedHeld, mayBeConsumed, minimumHeldSize)
      local confirmed = success and reason == nil and swapped == true
      if heldMatches and (not same(after, before) or confirmed) then return true, before end
      if same(after, before) and (not before or not matchesHeld(before, expectedHeld, mayBeConsumed, minimumHeldSize)) and
          not confirmed then
        return false
      end
      wait("HAND_SWAP_UNVERIFIED")
    end
  end

  -- The caller has established an empty hand via store. Only a confirmed
  -- unchanged source permits retry; after invoking equip, retry reads first.
  function api.take(slot, expected)
    while true do
      local before, version = read(slot)
      if before and same(before, expected) and select(slot, version) then
        pcall(inventory.equip); coroutine.yield()
        while true do
          local after = read(slot)
          if not after then return before end
          if same(after, before) then break end
          wait("HAND_SWAP_UNVERIFIED")
        end
      end
      wait("HAND_SWAP_PENDING")
    end
  end

  function api.park()
    return api.store(14)
  end

  -- One working item in the caller's physical coroutine. The actual source
  -- descriptor is retained until the common finish path has restored it.
  function api.equip(slot, expected)
    local taken = api.take(slot, expected)
    workingSlot, workingStack = slot, taken
    minimumRemaining, mayBeConsumed = nil, nil
  end

  function api.allowConsumption(maximumConsumed)
    minimumRemaining = math.max(0, workingStack.size - maximumConsumed)
    mayBeConsumed = minimumRemaining == 0
  end

  -- Return the working remainder, retain any displaced cargo, then restore
  -- the original hand. A full cargo area uses 14 until the caller's service.
  function api.finish(originalHand)
    local restoredSlot, displacedHand = workingSlot
    if workingSlot then
      while true do
        local restored
        restored, displacedHand = api.swap(workingSlot, workingStack, nil, mayBeConsumed, minimumRemaining)
        if restored then break end
        wait("HAND_RETURN_PENDING")
      end
      workingSlot, workingStack, minimumRemaining, mayBeConsumed = nil, nil, nil, nil
    end
    if displacedHand then
      local stored
      for slot = 1, 13 do
        if api.store(slot) then
          stored = true; break
        end
      end
      if not stored then
        if originalHand then
          while not api.swap(14, displacedHand, originalHand) do wait("HAND_RESTORE_PENDING") end
        else
          while not api.store(14) do wait("HAND_STORAGE_PENDING") end
        end
        return true, restoredSlot
      end
    end
    if originalHand then api.take(14, originalHand) end
    return false, restoredSlot
  end

  return api
end

return RobotHand
