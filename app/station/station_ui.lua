local Catalog = require("station_catalog")
local Ui = {}
local fields = { "K", "g", "ga", "r" }
local taskNames = { "UI", "Robot Link", "Observation", "Control" }
local function value(actual) return actual == nil and "unknown" or tostring(actual) end
local function geneDifference(required, observed)
  if required == nil then return "-" end
  local difference = required - observed
  return (difference > 0 and "+" or "") .. difference
end
local function terrainRange(minimum, maximum)
  if minimum == nil or maximum == nil then return "?" end
  if minimum == maximum then return tostring(minimum) end
  return minimum .. "–" .. maximum
end
local function cropKey(order) return order and order.owner .. ":" .. order.cropId or "none" end
local function cropName(order)
  local crop = order and Catalog.get(cropKey(order))
  return crop and crop.name or cropKey(order)
end
local actionLabels = {
  PLANT_SEED = "Planting a crop.",
  PLACE_DOUBLE_STICKS = "Placing double crop sticks.",
  EXTRACT_AND_PLANT = "Moving a plant.",
  COLLECT_AND_CLEAR_CELL = "Collecting and clearing a cell.",
  COLLECT_AND_RESTORE_DOUBLE = "Collecting and restoring double sticks.",
  REMOVE_WEED = "Removing weeds."
}
local workWaitingLabels = {
  PARENT_MATURING = "Waiting for plants to mature.",
  WAIT_CROSSING = "Waiting for a crossing result.",
  WAIT_SPREADING = "Waiting for plants to spread.",
  LOCAL_FACTS_UNREADABLE = "Waiting for a field reading.",
  OBSERVATION_PENDING = "Checking the field.",
  IO_PREPARING = "Preparing supplies.",
  ROBOT_OR_IO_WAIT = "Waiting for the robot or storage access."
}
local orderMessages = {
  ORDER_LIMIT = "Order records are full.",
  ORDER_INVALID_ORDER = "Check quantity and genes.",
  ORDER_NOT_EDITABLE = "Order is closed or missing.",
  ORDER_PROGRESS_CHOICE_REQUIRED = "Choose whether to reset output.",
  ORDER_QUANTITY_BELOW_PRODUCED = "Quantity is below delivered.",
  ORDER_NOT_FOUND = "The selected order no longer exists.",
  STATE_MISSING = "Order storage is unavailable.",
  ORDER_ID_EXHAUSTED = "No further order IDs can be issued."
}
local waitingLabels = {
  PARENT_MATURING = "Waiting for plants to mature.",
  WAIT_CROSSING = "Waiting for a crossing result.",
  WAIT_SPREADING = "Waiting for plants to spread.",
  LOCAL_FACTS_UNREADABLE = "Waiting for readable field observations.",
  OBSERVATION_PENDING = "Observing the field before work.",
  ROBOT_OR_IO_WAIT = "Waiting for the robot or shared inventory.",
  PLANNING_CHANGED = "Reconsidering the latest field observations."
}
local recoveryMessage = "Restoring inventory stocks."
local issueLabels = {
  PAIR_SELECTION_STALE = { "The selected robot identity has changed.", "Review a fresh announcement before confirming." },
  PAIR_LIST_FULL = { "The robot announcement list is full.", "Close and reopen robot linking." },
  PAIR_TIMEOUT = { "Robot linking timed out.", "Check the robot and review a fresh announcement." },
  STATE_MISSING = { "Order storage is unavailable.", "Check the Station HDD." },
  STATE_READ_FAILED = { "Order storage could not be read.", "Check the Station HDD and file access." },
  STATE_SCHEMA_UNSUPPORTED = { "The saved State format is unsupported.", "Stop both programs; back up old State." },
  WRITE_FAILED = { "An order storage write failed.", "Keep a backup; inspect the HDD before restarting." },
  OUTPUT_FULL = { "Output cannot accept more items.", "Make room in the Output inventory." },
  TRASH_BLOCKED = { "Trash cannot accept more items.", "Check the Trash inventory." },
  GENEBANK_FULL = { "The seed archive needs space.", "Inspect the Genebank inventory." },
  GENEBANK_UNAVAILABLE = { "Genebank is unavailable.", "Retrying automatically; check its connection if this persists." },
  IO_UNAVAILABLE = { "The exchange inventory is unavailable.", "Retrying automatically; check its connection and size." },
  TRASH_UNAVAILABLE = { "Trash is unavailable.", "Retrying automatically; items are kept in their source." },
  IO_UNREADABLE = { "Some exchange slots are unreadable.", "Retrying automatically; readable slots remain in use." },
  DRAWER_UNREADABLE = { "Some Drawer slots are unreadable.", "Retrying automatically; readable slots remain in use." },
  GENEBANK_TRANSFER_BLOCKED = { "The seed archive cannot accept the item.", "Retrying automatically; check available archive space." },
  CLASSIFICATION_FAILED = { "An inventory item could not be identified.", "The item is kept; retrying automatically." },
  SEED_SOURCE_UNREADABLE = { "The seed source is unreadable.", "Checking actual archive contents automatically." },
  SEED_SOURCE_MISSING = { "The requested seed source is missing.", "Checking actual archive contents automatically." },
  SEED_SOURCE_CHANGED = { "The requested seed source has changed.", "Checking actual archive contents automatically." },
  SEED_TRANSFER_BLOCKED = { "The seed could not be staged for exchange.", "A fresh preparation will use the current inventory." },
  TRANSFER_UNCONFIRMED = { "Inventory preparation is being rebuilt.", "The old transfer is not repeated." },
  CROP_STICKS = { "Production is waiting for crop sticks.", "Check the Crop Sticks Drawer." },
  SENSOR_UNAVAILABLE = { "The field sensor is unavailable.", "Check the sensor and its cable." },
  SENSOR_AMBIGUOUS = { "More than one field sensor was found.", "Check the stationary sensor setup." },
  TRANSPOSER = { "Inventory access is unavailable.", "Check the Transposer connection." },
  TRANSFER_UNKNOWN = { "An inventory transfer has an uncertain result.", "Inspect inventories; do not repeat the transfer." },
  TASK_NOT_FOUND = { "The current operation has an uncertain result.", "Inspect the field and robot; do not repeat work." },
  NO_SOURCE_MATERIAL = { "No usable source material was found.", "Check available source plants and seeds." },
  NO_FEASIBLE_SITE = { "No suitable planting site is currently available.", "Inspect the actual field layout in game." }
}
local fatalReasons = {
  STATE_MISSING = true,
  STATE_READ_FAILED = true,
  STATE_SCHEMA_UNSUPPORTED = true,
  WRITE_FAILED = true,
  LINK_QUEUE_FULL = true,
  OBSERVATION_QUEUE_FULL = true,
  INVENTORY_HARDWARE_MISMATCH = true
}
local function knownFatal(snapshot)
  local reason = snapshot.diagnostic
  return reason and (fatalReasons[reason] or reason:match("^TASK_FAILED_") or reason:match("^LINK_HARDWARE:")) or false
end
local function issue(snapshot)
  local stock, observed, action = snapshot.inventory, snapshot.observation, snapshot.action
  local reason = snapshot.diagnostic or snapshot.link and snapshot.link.error
  local severe = knownFatal(snapshot)
  if not severe then
    if action and action.task and action.outcome == "UNKNOWN" then
      if action.reason == "EXPECTED_EFFECT_ABSENT" then
        return action.reason, "The operation's effect is not yet confirmed.", "Waiting for changed field observations.",
            2
      end
      return action.reason, "The current operation has an uncertain result.",
          "Inspect the field and robot; do not repeat work.", 6
    elseif snapshot.ioAccessFault or stock and stock.fault then
      reason = snapshot.ioAccessFault or stock.fault; severe = true
    elseif observed and observed.dockError then
      reason = observed.dockError; severe = true
    elseif observed and (observed.dataInvalid or 0) > 0 then
      return observed.lastErrorCategory,
          observed.lastErrorCell and "Field reading error at cell " .. observed.lastErrorCell .. "." or
          "Some field readings are unreadable.", nil, 7
    elseif observed and (observed.dangers or 0) > 0 then
      return nil, "Threats have been reported in the field.", nil, 6
    elseif stock and stock.phase == "RECOVERING" then
      return "INVENTORY_RECOVERING", snapshot.enabled and recoveryMessage or "Inventory recovery is paused.",
          snapshot.enabled and "Continuing automatically." or "Use START to continue.", 2
    else
      reason = stock and (stock.waiting or stock.problem) or snapshot.blocker or reason
    end
  end
  if reason then
    local explanation = issueLabels[reason]
    return reason, explanation and explanation[1] or waitingLabels[reason] or "A reported condition is limiting work.",
        explanation and explanation[2], severe and 6 or waitingLabels[reason] and 2 or 7
  end
  local planner = snapshot.planner
  if planner and waitingLabels[planner.reason] then return nil, waitingLabels[planner.reason], nil, 2 end
  return nil, snapshot.enabled and "No issue is currently reported." or "Automation is stopped.", nil, 2
end
local function currentWork(snapshot, planner)
  local action, stock = snapshot.action, snapshot.inventory
  if action and action.task then
    if action.outcome == "UNKNOWN" then
      if action.reason == "EXPECTED_EFFECT_ABSENT" then
        return "Waiting for the operation's result.", 2
      end
      return nil
    end
    if action.reported then return "Checking the result.", 1 end
    return actionLabels[action.name], 1
  end
  if stock and (stock.uncertain or stock.fault) or snapshot.ioAccessFault or not snapshot.enabled then return nil end
  if stock and stock.phase == "RECOVERING" then return recoveryMessage, 2 end
  if stock and stock.waiting then return nil end
  if stock and stock.busy and (stock.kind == "STARTUP" or stock.kind == "PREPARE_EXCHANGE" or stock.kind == "SORT_CARGO") then
    return stock.phase == "SORTING" and "Sorting collected items." or "Preparing supplies.", 1
  end
  if snapshot.ioCallPending or snapshot.ioRequestPending or snapshot.ioExchangeGranted then
    return "Waiting for an item exchange.", 2
  end
  if planner and planner.kind == "MATERIAL" then return "Waiting for planting material.", 2 end
  if snapshot.blocker then return workWaitingLabels[snapshot.blocker], 2 end
  if planner and planner.kind == "WAIT" then return workWaitingLabels[planner.reason], 2 end
end
local function inside(x, y, left, top, width, height)
  return x >= left and x < left + width and y >= top and y < top + height
end
local function nextCrop(currentKey, direction)
  local chosen, wrapped
  for key in Catalog.each() do
    if Catalog.canProceed(key) then
      if not wrapped or (direction > 0 and key < wrapped) or (direction < 0 and key > wrapped) then wrapped = key end
      if (not currentKey or (direction > 0 and key > currentKey) or (direction < 0 and key < currentKey)) and
          (not chosen or (direction > 0 and key < chosen) or (direction < 0 and key > chosen)) then
        chosen = key
      end
    end
  end
  return chosen or wrapped
end
function Ui.new(renderer, unicode)
  local page, form = "System", nil
  local selectedOrderId, orderIndex, orderOffset = nil, 1, 0
  local candidateIndex, candidateOffset, pairingSelection = 1, 0, nil
  local cancelOrderId, cancelConfirm, linkPanel = nil, false, false
  local unlinkSelection
  local notice, commandError, previousView, pairingWasOpen, screenDirty
  local splashVisible, splashDeadline = false, nil
  local stateWarning = false
  local goalOrderId, goalPhase, goalFrom, goalTo
  local goalOwner, goalCropId, goalRequiredG, goalRequiredGa, goalRequiredR
  local goalGeneticsMode, goalBestCell, goalBestG, goalBestGa, goalBestR
  local actionIndex, cropCount = 1, 0
  for key in Catalog.each() do if Catalog.canProceed(key) then cropCount = cropCount + 1 end end
  local remembered = {}
  local api = {}
  function api.terrainCrop() return page == "Form" and form and form.crop or nil end

  function api.snapshotQueuedLimit()
    if page == "Production" then return 3 end
    if page == "System" then return 0 end
  end

  local function changed(key, ...)
    local count = select("#", ...)
    local previous = remembered[key]
    if not previous then
      previous = {}; remembered[key] = previous
    end
    local different = previous.count ~= count
    for index = 1, count do
      local actual = select(index, ...); if previous[index] ~= actual then
        different = true; previous[index] = actual
      end
    end
    previous.count = count; return different
  end
  local function text(x, y, width, label, ink, paper) renderer.text(x, y, width, label, ink or 1, paper or 0) end
  local function button(x, y, width, label, enabled, selected)
    local padding = math.max(0, width - 2 - unicode.wlen(label)); local left = math.floor(padding / 2)
    text(x, y, width, "|" .. string.rep(" ", left) .. label .. string.rep(" ", padding - left) .. "|", enabled and 1 or 2,
      enabled and selected and 4 or 3)
  end
  local function panel(x, y, width, height, title)
    renderer.fill(x, y, width, 1, 0, "─", 11); renderer.fill(x, y + height - 1, width, 1, 0, "─", 11)
    renderer.fill(x, y + 1, 1, height - 2, 0, "│", 11); renderer.fill(x + width - 1, y + 1, 1, height - 2, 0, "│", 11)
    text(x, y, 1, "┌", 11); text(x + width - 1, y, 1, "┐", 11); text(x, y + height - 1, 1, "└", 11); text(x + width - 1,
      y + height - 1, 1, "┘", 11)
    if title then text(x + 3, y, math.min(width - 5, unicode.wlen(title) + 2), " " .. title .. " ", 8) end
  end
  local function paragraph(x, y, width, lines, label, ink)
    local remaining = tostring(label or ""):gsub("^ +", "")
    local isAscii = width >= 0 and width % 1 == 0
    if isAscii then
      for index = 1, #remaining do
        local code = remaining:byte(index)
        if code < 32 or code > 126 then
          isAscii = false; break
        end
      end
    end
    for row = 0, lines - 1 do
      local count, lastSpace, cells = 0, nil, 0
      local length = isAscii and #remaining or unicode.len(remaining)
      if isAscii then
        count = math.min(length, width)
        for index = 1, count do if remaining:byte(index) == 32 then lastSpace = index end end
      else
        for index = 1, length do
          local character = unicode.sub(remaining, index, index); local characterWidth = unicode.charWidth(character)
          if cells + characterWidth > width then break end
          count = index; cells = cells + characterWidth; if character == " " then lastSpace = index end
        end
      end
      local finish, nextIndex = count, count + 1
      if count < length and lastSpace then finish, nextIndex = lastSpace - 1, lastSpace + 1 end
      text(x, y + row, width, isAscii and remaining:sub(1, finish) or unicode.sub(remaining, 1, finish), ink)
      remaining = (isAscii and remaining:sub(nextIndex, length) or unicode.sub(remaining, nextIndex, length)):gsub("^ +",
        "")
    end
  end
  local function activeOrder(snapshot)
    for _, order in ipairs(snapshot.orders) do if order.status == "ACTIVE" then return order end end
  end
  local function available(kind, snapshot, selected)
    local network = snapshot.link
    if kind == "STOP" then return true end
    if (snapshot.queued or 0) >= 32 then return false end
    if kind == "START" then return not knownFatal(snapshot) and not (network and network.pairing) end
    if kind == "PAIR_CLOSE" then return network and network.pairing end
    if kind == "PAIR_OPEN" or kind == "PAIR_RESET" then
      if kind == "PAIR_RESET" and (not network or network.pairing or
            not network.paired and (not network.error or network.error == "LINK_MISSING")) then
        return false
      end
      return network ~= nil and not snapshot.enabled and not (snapshot.action and snapshot.action.task) and
          not snapshot.ioCallPending and not snapshot.ioRequestPending and not snapshot.ioExchangeGranted and
          not snapshot.ioReceiptPending and not snapshot.sortingReceiptPending and snapshot.ioAccessState ~= "ROBOT" and
          snapshot.ioAccessState ~= "UNCERTAIN" and
          not (kind ~= "PAIR_RESET" and snapshot.ioAccessState == "UNKNOWN" and network.paired)
    end
    if knownFatal(snapshot) then return false end
    if kind == "ORDER_CREATE" then
      if snapshot.canCreateOrder ~= nil then return snapshot.canCreateOrder end
      if #snapshot.orders < 20 then return true end
      for _, order in ipairs(snapshot.orders) do if order.status == "CLOSED" then return true end end
      return false
    end
    if kind == "ORDER_EDIT" then return selected and (selected.status == "QUEUED" or selected.status == "ACTIVE") end
    if kind == "ORDER_CANCEL" then return selected and selected.status ~= "CLOSED" end
    return false
  end
  local function submit(request, kind, details)
    local accepted, reason = request(kind, details)
    commandError = not accepted and reason or nil
    if accepted then
      notice = nil
    else
      notice = "Request rejected. " .. (orderMessages[reason] or tostring(reason or "See System."))
    end
    if form and (kind == "ORDER_CREATE" or kind == "ORDER_EDIT") then form.error = not accepted and reason or nil end
    return accepted
  end
  local function navigate(target)
    page = target; form = nil; cancelOrderId = nil; cancelConfirm = false; unlinkSelection = nil; notice = nil; commandError = nil
    if target == "Orders" then
      selectedOrderId = nil; orderIndex, orderOffset = 1, 0
    end
  end
  local function selectOrder(orders)
    local found
    for index, order in ipairs(orders) do
      if order.id == selectedOrderId then
        found = index; break
      end
    end
    orderIndex = math.max(1, math.min(#orders, found or orderIndex))
    local selected = orders[orderIndex]; selectedOrderId = selected and selected.id; orderOffset = math.floor((orderIndex - 1) /
      16) * 16
    return selected
  end
  local function orderPage(snapshot, direction)
    local orders = snapshot.orders; selectOrder(orders); local nextOffset = orderOffset + direction * 16
    if nextOffset >= 0 and nextOffset < #orders then
      orderIndex = nextOffset + 1; selectedOrderId = orders[orderIndex].id; orderOffset = nextOffset
    end
  end
  local function beginForm(selected)
    page = "Form"; cancelOrderId = nil; notice = nil; commandError = nil
    form = { crop = nextCrop(nil, 1), cropIndex = 1, cropOffset = 0, focus = 1, replaceInput = true, inputs = { K = "1", g = "", ga = "", r = "" }, submitted = false }
    if selected then
      form.orderId = selected.id
      while form.crop ~= cropKey(selected) do
        form.crop = nextCrop(form.crop, 1); form.cropIndex = form.cropIndex + 1
      end
      form.cropOffset = math.floor((form.cropIndex - 1) / 16) * 16
      for _, field in ipairs(fields) do form.inputs[field] = selected[field] ~= nil and tostring(selected[field]) or "" end
    end
  end
  local function editedOrder(snapshot)
    for _, order in ipairs(snapshot.orders) do if order.id == form.orderId then return order end end
  end
  local function formEditable(snapshot)
    if knownFatal(snapshot) then return false end
    local order = form.orderId and editedOrder(snapshot)
    return not form.orderId or order and (order.status == "QUEUED" or order.status == "ACTIVE") or false
  end
  local function leaveForm()
    local orderId = form.orderId
    navigate(orderId and "Orders" or "Production")
    if orderId then selectedOrderId = orderId end
  end
  local function chooseCrop(direction)
    local wanted = math.max(1, math.min(cropCount, form.cropIndex + direction))
    if wanted ~= form.cropIndex then form.submitted = false end
    while form.cropIndex ~= wanted do
      local step = wanted > form.cropIndex and 1 or -1; form.crop = nextCrop(form.crop, step); form.cropIndex = form
          .cropIndex + step
    end
    form.cropOffset = math.floor((form.cropIndex - 1) / 16) * 16
  end
  local function cropPage(direction)
    local offset = form.cropOffset + direction * 16; if offset >= 0 and offset < cropCount then form.cropOffset = offset end
  end
  local function terrainWarning(snapshot)
    local _, needMaximum = Catalog.terrainNeed(form.crop, tonumber(form.inputs.g), tonumber(form.inputs.ga),
      tonumber(form.inputs.r))
    if not needMaximum then return end
    local terrain = snapshot.observation and snapshot.observation.terrain
    if not terrain or terrain.crop ~= form.crop or (terrain.known or 0) == 0 or
        terrain.qualityMin == nil or terrain.qualityMax == nil then
      return "UNKNOWN"
    end
    if terrain.qualityMin < needMaximum then return "LOW" end
  end
  local function saveOrder(snapshot, request, resetProduced, terrainConfirmed)
    local kind = form.orderId and "ORDER_EDIT" or "ORDER_CREATE"
    local order = form.orderId and editedOrder(snapshot)
    if form.submitted or not available(kind, snapshot, order) then return end
    if not form.orderId then
      local warning = terrainWarning(snapshot)
      if warning and (not terrainConfirmed or form.terrainPrompt ~= warning) then
        form.terrainPrompt = warning; form.terrainConfirm = false; return
      end
      form.terrainPrompt = nil
    end
    if order and order.status == "ACTIVE" and resetProduced == nil then
      form.resetPrompt = true; form.resetSelected = false; return
    end
    form.resetPrompt = nil
    local newestOrderId = 0
    if not form.orderId then
      for _, savedOrder in ipairs(snapshot.orders) do newestOrderId = math.max(newestOrderId, savedOrder.id) end
    end
    local owner, cropId = form.crop:match("^([^:]+):(.+)$")
    if submit(request, kind, { id = form.orderId, resetProduced = resetProduced, owner = owner, cropId = cropId, K = tonumber(form.inputs.K) or 1,
          g = tonumber(form.inputs.g), ga = tonumber(form.inputs.ga), r = tonumber(form.inputs.r) }) then
      form.submitted = true
      if not form.orderId then form.createAfterId = newestOrderId end
    end
  end
  local function cancel(snapshot, request, confirm)
    local selected
    for _, order in ipairs(snapshot.orders) do
      if order.id == (confirm and cancelOrderId or selectedOrderId) then
        selected = order; break
      end
    end
    if not available("ORDER_CANCEL", snapshot, selected) then
      cancelOrderId = nil; return
    end
    if confirm then
      submit(request, "ORDER_CANCEL", { id = selected.id }); cancelOrderId = nil
    else
      cancelOrderId = selected.id; cancelConfirm = false
    end
  end
  local function selectCandidate(candidates)
    candidateIndex = math.max(1, math.min(#candidates, candidateIndex))
    if candidateIndex <= candidateOffset then candidateOffset = candidateIndex - 1 end
    if candidateIndex > candidateOffset + 8 then candidateOffset = candidateIndex - 8 end
    candidateOffset = math.max(0, math.min(candidateOffset, math.max(0, #candidates - 8)))
  end
  local function review(candidates)
    local candidate = candidates[candidateIndex]
    if candidate then pairingSelection = { address = candidate.address, boot = candidate.boot, code = candidate.code } end
  end
  local function toggle(snapshot, request)
    local kind = snapshot.enabled and "STOP" or "START"; if available(kind, snapshot) then submit(request, kind) end
  end
  local function openLink(snapshot, request)
    page = "System"; form = nil; linkPanel = true
    if available("PAIR_OPEN", snapshot) and submit(request, "PAIR_OPEN") then
      candidateIndex, candidateOffset, pairingSelection =
          1, 0, nil
    end
  end
  local function closeLink(snapshot, request)
    if available("PAIR_CLOSE", snapshot) then submit(request, "PAIR_CLOSE") end
    linkPanel = false; pairingSelection = nil
  end
  local function unlinkRobot(snapshot, request)
    if not available("PAIR_RESET", snapshot) then
      unlinkSelection = nil; return
    end
    if unlinkSelection and unlinkSelection.address == snapshot.link.robotAddress then
      submit(request, "PAIR_RESET"); unlinkSelection = nil
    else
      unlinkSelection = { address = snapshot.link.robotAddress }
    end
  end
  local function inputNumber(character, keyCode, snapshot)
    if stateWarning or page ~= "Form" or form.terrainPrompt or form.resetPrompt or not formEditable(snapshot) then return end
    local field = fields[form.focus]
    local before = form.inputs[field]
    if character and character >= 48 and character <= 57 then
      if form.replaceInput then form.inputs[field] = "" end
      if #form.inputs[field] < 10 then form.inputs[field] = form.inputs[field] .. string.char(character) end
    elseif keyCode == 14 or character == 8 then
      form.inputs[field] = form.replaceInput and "" or form.inputs[field]:sub(1, -2)
    else
      return
    end
    form.replaceInput = false
    if form.inputs[field] ~= before then form.submitted = false end
  end
  function api.handle(eventName, address, first, second, third, snapshot, request)
    if splashVisible then return end
    if eventName == "key_down" then return inputNumber(first, second, snapshot) end
    if address ~= renderer.screen() then return end
    if eventName == "screen_resized" then
      if first ~= 80 or second ~= 25 then
        renderer.resize(); api.invalidate()
      end; return
    end
    if eventName ~= "touch" then return end
    local x, y = first, second
    if type(x) ~= "number" or type(y) ~= "number" or x ~= math.floor(x) or y ~= math.floor(y) or x < 1 or x > 80 or y < 1 or y > 25 then return end
    local network = snapshot.link
    if third ~= 0 then return end
    if stateWarning then
      if inside(x, y, 35, 18, 12, 1) then
        stateWarning = false; api.invalidate()
      end
      return
    end
    if inside(x, y, 60, 2, 10, 1) then
      toggle(snapshot, request); return
    end
    if inside(x, y, 15, 2, 14, 1) then
      navigate("Production"); return
    end
    if inside(x, y, 3, 2, 10, 1) then
      navigate("System"); return
    end
    if page == "Form" and form.terrainPrompt then
      if inside(x, y, 12, 20, 18, 1) then
        form.terrainPrompt = nil
      elseif inside(x, y, 42, 20, 28, 1) then
        saveOrder(snapshot, request, nil, true)
      end
      return
    end
    if page == "Form" and form.resetPrompt then
      if inside(x, y, 18, 16, 14, 1) then
        saveOrder(snapshot, request, false)
      elseif inside(x, y, 34, 16, 14, 1) then
        saveOrder(snapshot, request, true)
      elseif inside(x, y, 50, 16, 14, 1) then
        form.resetPrompt = nil
      end
      return
    end
    if page == "Form" then
      if inside(x, y, 48, 23, 14, 1) then
        leaveForm()
      elseif formEditable(snapshot) then
        if inside(x, y, 3, 6, 41, 16) and form.cropOffset + y - 5 <= cropCount then
          chooseCrop(form.cropOffset + y - 5 - form.cropIndex)
        elseif inside(x, y, 3, 23, 8, 1) then
          cropPage(-1)
        elseif inside(x, y, 36, 23, 8, 1) then
          cropPage(1)
        elseif inside(x, y, 64, 23, 14, 1) then
          saveOrder(snapshot, request)
        elseif inside(x, y, 48, 10, 30, 1) then
          form.focus = 1; form.replaceInput = true
        elseif y == 13 then
          if x >= 48 and x <= 55 then
            form.focus = 2; form.replaceInput = true
          elseif x >= 58 and x <= 65 then
            form.focus = 3; form.replaceInput = true
          elseif x >= 68 and x <= 77 then
            form.focus = 4; form.replaceInput = true
          end
        end
      end
    elseif page == "Orders" then
      if cancelOrderId then
        if inside(x, y, 21, 16, 16, 1) then
          cancelOrderId = nil
        elseif inside(x, y, 40, 16, 20, 1) then
          cancel(snapshot, request, true)
        end
      elseif inside(x, y, 2, 6, 78, 16) then
        local selected = snapshot.orders[orderOffset + y - 5]
        if selected then
          selectedOrderId = selected.id; selectOrder(snapshot.orders)
          if x >= 77 then
            cancel(snapshot, request, false)
          end
        end
      elseif y == 23 then
        if x >= 3 and x <= 13 then
          if available("ORDER_CREATE", snapshot) then beginForm() end
        elseif x >= 16 and x <= 23 then
          local selected = selectOrder(snapshot.orders)
          if available("ORDER_EDIT", snapshot, selected) then beginForm(selected) end
        elseif x >= 28 and x <= 33 then
          orderPage(snapshot, -1)
        elseif x >= 48 and x <= 53 then
          orderPage(snapshot, 1)
        elseif x >= 73 and x <= 78 then
          navigate("Production")
        end
      end
    elseif page == "Production" and inside(x, y, 55, 20, 22, 2) then
      actionIndex = y - 19
      if y == 20 then
        if available("ORDER_CREATE", snapshot) then beginForm() end
      elseif y == 21 then
        navigate("Orders")
      end
    elseif page == "System" then
      if inside(x, y, 62, 12, 14, 1) then
        if network and network.paired then unlinkRobot(snapshot, request) else openLink(snapshot, request) end
      elseif linkPanel and inside(x, y, 70, 9, 9, 1) then
        closeLink(snapshot, request)
      elseif linkPanel and inside(x, y, 3, 9, 11, 1) then
        if snapshot.enabled then
          submit(request, "STOP")
        elseif available("PAIR_OPEN", snapshot) then
          openLink(snapshot,
            request)
        end
      elseif network and network.pairing then
        if inside(x, y, 2, 13, 78, 8) and network.candidates[candidateOffset + y - 12] then
          candidateIndex = candidateOffset + y - 12; pairingSelection = nil
        elseif inside(x, y, 32, 23, 8, 1) or inside(x, y, 42, 23, 8, 1) then
          local offset = candidateOffset + (x < 42 and -8 or 8)
          if offset >= 0 and offset < #network.candidates then
            candidateOffset, candidateIndex = offset, offset + 1; pairingSelection = nil
          end
        elseif inside(x, y, 3, 23, 11, 1) then
          review(network.candidates)
        elseif inside(x, y, 17, 23, 12, 1) and pairingSelection then
          submit(request, "PAIR_SELECT", pairingSelection); pairingSelection = nil
        end
      end
    end
  end

  function api.invalidate()
    remembered = {}; previousView = nil; screenDirty = true
  end

  function api.close() renderer.close() end

  function api.waitForStartup(stateRecreated)
    splashVisible, splashDeadline = true, nil; stateWarning = stateRecreated == true; api.invalidate()
  end

  function api.finishStartup(now) splashDeadline = now + 2 end

  local function row(key, y, label, status, ink)
    if changed("c:row:" .. key, status, ink) then
      text(3, y, 28, label); text(32, y, 1, "●", ink); text(34, y, 45, status, ink)
    end
  end
  function api.update(snapshot, tasks, now)
    if splashVisible then
      local failed = knownFatal(snapshot)
      for _, name in ipairs(taskNames) do if tasks and tasks[name] and tasks[name].status == "failed" then failed = true end end
      if failed or splashDeadline and now and now >= splashDeadline then
        splashVisible = false; api.invalidate()
      else
        return
      end
    end
    if renderer.open() then api.invalidate() end
    if stateWarning then
      if changed("stateWarning", true) then
        renderer.fill(1, 1, 80, 25, 0)
        panel(7, 7, 68, 14, "ORDER STORAGE WARNING")
        text(10, 9, 62, "Damage was detected in state.dat.")
        text(10, 11, 62, "The file was automatically recreated.")
        text(10, 13, 62, "Saved orders and production counters were reset.")
        text(10, 15, 62, "Station is stopped. Enter your orders again.", 2)
        button(35, 18, 12, "OK", true, true)
        text(10, 23, 62, "Click OK to close this notice.", 2)
      end
      return
    end
    local network, stock, observed = snapshot.link, snapshot.inventory, snapshot.observation
    local pairing = network and network.pairing or false
    if page ~= "System" or not available("PAIR_RESET", snapshot) or unlinkSelection and network.robotAddress ~= unlinkSelection.address then unlinkSelection = nil end
    if pairing and not pairingWasOpen then
      page = "System"; form = nil; cancelOrderId = nil; linkPanel = true
    end
    pairingWasOpen = pairing
    if not pairing then pairingSelection = nil end
    if page == "Form" and not form then page = "Production" end
    if page == "Form" and form.createAfterId then
      for _, savedOrder in ipairs(snapshot.orders) do
        if savedOrder.id > form.createAfterId then
          navigate("Orders"); selectedOrderId = savedOrder.id; break
        end
      end
    end
    if page == "Form" and form.resetPrompt and not formEditable(snapshot) then form.resetPrompt = nil end
    if page == "Form" and form.terrainPrompt then
      local warning = formEditable(snapshot) and terrainWarning(snapshot)
      if warning ~= form.terrainPrompt then
        form.terrainPrompt = warning; form.terrainConfirm = false
      end
    end
    local view = page ..
        (page == "Form" and (form.resetPrompt and ":reset" or form.terrainPrompt and ":terrain:" .. form.terrainPrompt or "") or page == "Orders" and (cancelOrderId and ":cancel" or "") or page == "System" and (pairing and ":pair" or linkPanel and ":link" or "") or "")
    if previousView ~= view then
      if screenDirty then
        renderer.fill(1, 1, 80, 25, 0); screenDirty = false
      else
        renderer.fill(1, 4, 80, 21, 0)
      end
      for cacheKey in pairs(remembered) do if cacheKey:sub(1, 2) == "c:" then remembered[cacheKey] = nil end end
      previousView = view
    end
    if changed("header", true) then panel(1, 1, 80, 3) end
    if changed("navigation", page == "System") then
      button(3, 2, 10, "System", true, page == "System"); button(15, 2, 14, "Production", true, page ~= "System")
    end
    local canStart = available("START", snapshot)
    if changed("toggle", snapshot.enabled, canStart) then
      button(60, 2, 10, snapshot.enabled and "STOP" or "START",
        snapshot.enabled or canStart, false)
    end
    if changed("status", snapshot.label, snapshot.enabled) then
      local label = not snapshot.enabled and "Stopped" or snapshot.label == "AWAIT" and "Waiting" or
          snapshot.label == "READY" and "Ready" or snapshot.label == "RUNNING" and "Running" or "Enabled"
      local statusInk = not snapshot.enabled and 6 or snapshot.label == "AWAIT" and 7 or 5
      text(71, 2, 8, label, statusInk)
    end
    if changed("footer", true) then text(30, 25, 21, "CropAutomation v3.0.0", 2) end
    local orders = snapshot.orders
    local active = activeOrder(snapshot)
    local planner = snapshot.planner
    local current = snapshot.enabled and planner and not planner.calculating and
        (active and planner.orderId == active.id or not active and planner.phase == "SAFETY")
    if not snapshot.enabled or goalOrderId ~= (active and active.id) or
        goalPhase == "GENETICS" and active and (goalOwner ~= active.owner or goalCropId ~= active.cropId or
          goalRequiredG ~= active.g or goalRequiredGa ~= active.ga or goalRequiredR ~= active.r) or
        planner and not planner.orderId and planner.phase == "IDLE" or
        planner and not planner.calculating and
        (planner.orderId and planner.orderId ~= (active and active.id) or not active and planner.phase ~= "SAFETY") then
      goalOrderId, goalPhase, goalFrom, goalTo = nil, nil, nil, nil
      goalOwner, goalCropId, goalRequiredG, goalRequiredGa, goalRequiredR = nil, nil, nil, nil, nil
      goalGeneticsMode, goalBestCell, goalBestG, goalBestGa, goalBestR = nil, nil, nil, nil, nil
    end
    if current then
      goalOrderId, goalPhase, goalFrom, goalTo = active and active.id, planner.phase, planner.routeFrom, planner.routeTo
      goalOwner, goalCropId = active and active.owner, active and active.cropId
      goalRequiredG, goalRequiredGa, goalRequiredR = active and active.g, active and active.ga, active and active.r
      local genetics = planner.phase == "GENETICS" and planner.genetics
      goalGeneticsMode, goalBestCell = genetics and genetics.mode, genetics and genetics.bestCell
      goalBestG, goalBestGa, goalBestR = genetics and genetics.g, genetics and genetics.ga, genetics and genetics.r
    end
    if page == "Production" then
      if changed("c:order", active and active.id, active and active.owner, active and active.cropId, active and active.g, active and active.ga, active and active.r, active and active.K) then
        panel(1, 4, 80, 4, active and "ORDER #" .. active.id or "NO ACTIVE ORDER")
        text(3, 5, 32, "CROP", 2); text(39, 5, 6, "GROWTH", 2); text(48, 5, 4, "GAIN", 2); text(55, 5, 10, "RESISTANCE",
          2); text(68, 5, 11, "QUANTITY", 2)
        text(3, 6, 32, active and cropName(active) or "Create an order to begin.")
        text(39, 6, 6, active and (active.g == nil and "Any" or active.g) or "")
        text(48, 6, 4, active and (active.ga == nil and "Any" or active.ga) or "")
        text(55, 6, 10, active and (active.r == nil and "Any" or active.r) or "")
        text(68, 6, 11, active and value(active.K) or "")
      end
      if changed("c:goalFrame", true) then
        panel(1, 8, 80, 11, "CURRENT GOAL")
        renderer.fill(1, 14, 80, 1, 0, "─", 11); text(1, 14, 1, "├", 11); text(80, 14, 1, "┤", 11); text(4, 14, 5,
          " NOW ", 8)
      end
      local phase = goalPhase
      local retained = phase and not current
      if changed("c:goal", phase, active and active.id, active and active.owner, active and active.cropId,
            active and active.g, active and active.ga, active and active.r, phase == "QUANTITY" and active and active.K,
            phase == "QUANTITY" and active and active.produced, goalFrom, goalTo, snapshot.enabled,
            goalGeneticsMode, goalBestCell, goalBestG, goalBestGa, goalBestR) then
        renderer.fill(2, 9, 78, 4, 0)
        local phaseName = phase == "SPECIES" and "Obtaining the crop" or
            phase == "GENETICS" and "Breeding for requested genes" or
            phase == "QUANTITY" and "Producing requested quantity" or
            phase == "SAFETY" and "Protecting the field"
        text(3, 9, 13, "STAGE:", 2); text(17, 9, 62, phaseName or (not snapshot.enabled and "Stopped" or "Not yet known"),
          7)
        if phase == "SPECIES" then
          if goalFrom and goalTo then
            local fromCrop, toCrop = Catalog.get(goalFrom), Catalog.get(goalTo)
            text(3, 10, 15, "CURRENT CROSS:", 2); text(19, 10, 60,
              (fromCrop and fromCrop.name or goalFrom) .. " → " .. (toCrop and toCrop.name or goalTo), 7)
          end
        elseif phase == "GENETICS" and active then
          text(21, 10, 14, "Growth", 2); text(39, 10, 14, "Gain", 2); text(57, 10, 14, "Resistance", 2)
          text(3, 11, 17, "BEST ON FIELD:", 2); text(3, 12, 17, "TARGET − CURRENT:", 2)
          if goalBestCell then
            text(21, 11, 14, goalBestG); text(39, 11, 14, goalBestGa); text(57, 11, 14, goalBestR)
            text(21, 12, 14, geneDifference(active.g, goalBestG), (active.g == nil or active.g == goalBestG) and 2 or 1)
            text(39, 12, 14, geneDifference(active.ga, goalBestGa),
              (active.ga == nil or active.ga == goalBestGa) and 2 or
              1)
            text(57, 12, 14, geneDifference(active.r, goalBestR), (active.r == nil or active.r == goalBestR) and 2 or 1)
          else
            text(21, 11, 58, "Not yet known", 2); text(21, 12, 58, "Not yet known", 2)
          end
        elseif phase == "QUANTITY" and active then
          text(3, 11, 13, "DELIVERED:", 2)
          text(17, 11, 62, active.produced .. " / " .. active.K .. "    Remaining: " .. (active.K - active.produced))
          local percent = math.floor(100 * active.produced / active.K); local filled = math.floor(30 * active.produced /
            active.K)
          text(3, 12, 13, "PROGRESS:", 2); text(17, 12, 1, "[", 5); renderer.fill(18, 12, 30, 1, 3)
          if filled > 0 then renderer.fill(18, 12, filled, 1, 5) end
          text(48, 12, 1, "]", 5); text(52, 12, 8, percent .. "%", 5)
        elseif phase == "SAFETY" then
          text(3, 10, 13, "GOAL:", 2); text(17, 10, 62, "Remove reported field threats")
        elseif not active then
          text(3, 10, 13, "GOAL:", 2); text(17, 10, 62, "No active order")
        end
      end
      if changed("c:goalSnapshot", retained) then
        text(3, 13, 75,
          retained and "Updating goal; previous goal shown." or "", 2)
      end
      local work, ink = currentWork(snapshot, current and planner or nil)
      local _, explanation, recommendation, severity = issue(snapshot)
      local attention = severity ~= 2 and not (snapshot.blocker == "IO_PREPARING" and severity == 7)
      if not work then
        if attention then
          work, ink = explanation, severity
        elseif not snapshot.enabled then
          work, ink = "Work is stopped.", 2
        elseif planner and planner.calculating then
          work, ink = "Choosing the next step.", 2
        elseif not active then
          work, ink = "No active order.", 2
        else
          work, ink = "Current action is not yet known.", 2
        end
      end
      local physical = snapshot.action
      local detail = physical and physical.task and physical.cell and
          (physical.from and physical.from > 0 and "Cell " .. physical.from .. " → cell " .. physical.cell or "Cell " .. physical.cell) or
          ""
      local warning = attention and explanation ~= work and explanation or ""
      local advice = attention and recommendation or ""
      if changed("c:now", work, ink, detail, warning, advice, severity) then
        if attention then
          text(3, 15, 75, work, ink); text(3, 16, 75, warning, severity); text(3, 17, 75, advice, severity)
        else
          paragraph(3, 15, 75, 2, work, ink); text(3, 17, 75, detail, 2)
        end
      end
      local quantityWidth, queuedCount = 3, 0
      for _, order in ipairs(orders) do
        if order.status == "QUEUED" then
          quantityWidth = math.max(quantityWidth, #tostring(order.K)); queuedCount = queuedCount + 1
          if queuedCount == 3 then break end
        end
      end
      local quantityX = 36 - quantityWidth
      if changed("c:queueFrame", true) then
        panel(1, 19, 49, 6, "ORDER QUEUE"); panel(51, 19, 30, 6, "ACTIONS")
      end
      if changed("c:queueColumns", quantityWidth) then
        renderer.fill(2, 20, 47, 1, 0)
        text(3, 20, 6, "ID", 2); text(10, 20, quantityX - 11, "CROP", 2); text(quantityX, 20, quantityWidth, "QTY", 2); text(
          38, 20, 3, "G", 2); text(42, 20, 3, "Ga", 2); text(46, 20, 3, "R", 2)
      end
      local queueRank = 0
      for _, order in ipairs(orders) do
        if order.status == "QUEUED" then
          queueRank = queueRank + 1
          if queueRank <= 3 and changed("c:queue" .. queueRank, order.id, order.owner, order.cropId, order.K, order.g, order.ga, order.r, quantityWidth) then
            local y = 20 + queueRank; renderer.fill(2, y, 47, 1, 0)
            text(3, y, 6, "#" .. order.id); text(10, y, quantityX - 11, cropName(order)); text(quantityX, y,
              quantityWidth, order.K)
            text(38, y, 3, order.g == nil and "Any" or order.g); text(42, y, 3, order.ga == nil and "Any" or order.ga); text(
              46, y, 3, order.r == nil and "Any" or order.r)
          end
        end
      end
      for rank = math.min(queueRank, 3) + 1, 3 do if changed("c:queue" .. rank, nil) then text(2, 20 + rank, 47, "") end end
      if changed("c:actions", available("ORDER_CREATE", snapshot), actionIndex) then
        button(55, 20, 22, "New Order", available("ORDER_CREATE", snapshot), actionIndex == 1)
        button(55, 21, 22, "All Orders", true, actionIndex == 2)
      end
    elseif page == "Form" and form.terrainPrompt then
      local terrain = snapshot.observation and snapshot.observation.terrain
      if terrain and terrain.crop ~= form.crop then terrain = nil end
      if changed("c:terrainWarningFrame", form.terrainPrompt) then
        panel(7, 5, 68, 19, "TERRAIN WARNING")
        text(10, 7, 62, Catalog.get(form.crop).name, 1)
        if form.terrainPrompt == "UNKNOWN" then
          text(10, 9, 62, "Terrain measurements are unknown.", 7)
          paragraph(10, 12, 62, 3,
            "Plant one crop manually, then start the system to obtain terrain measurements before creating this order.",
            1)
        else
          text(10, 9, 62, "Terrain quality is below Need quality.", 7)
          paragraph(10, 13, 62, 2, "Plants may die, and this order may never complete.", 1)
          text(10, 16, 62, "Some cells or allowed gene values may be affected.", 2)
        end
        text(10, 17, 62, "Create the order anyway?", 1)
      end
      if changed("c:terrainWarningValues", terrain and terrain.qualityMin, terrain and terrain.qualityMax) and form.terrainPrompt == "LOW" then
        local minimum, maximum = Catalog.terrainNeed(form.crop, tonumber(form.inputs.g), tonumber(form.inputs.ga),
          tonumber(form.inputs.r))
        text(10, 11, 62,
          "Terrain quality: " ..
          terrainRange(terrain.qualityMin, terrain.qualityMax) .. "   Need quality: ≥" .. terrainRange(minimum, maximum),
          2)
      end
      local known = terrain and terrain.known or 0
      if changed("c:terrainWarningCoverage", known, snapshot.enabled) then
        text(10, 18, 62, "Measured cells: " .. known .. "/36" ..
          (not snapshot.enabled and known > 0 and " (retained)" or ""), 2)
      end
      local canCreate = available("ORDER_CREATE", snapshot) and not form.submitted
      if changed("c:terrainWarningButtons", form.terrainConfirm, canCreate) then
        button(12, 20, 18, "BACK", true, not form.terrainConfirm)
        button(42, 20, 28, "CREATE ANYWAY", canCreate, form.terrainConfirm)
      end
    elseif page == "Form" and form.resetPrompt then
      local order = editedOrder(snapshot)
      if changed("c:resetFrame", form.orderId) then
        panel(15, 8, 52, 11, "SAVE ORDER #" .. form.orderId .. "?")
        text(18, 10, 46, "Reset delivered quantity to zero?", 1)
        text(18, 14, 46, "YES resets; NO keeps the current count.", 2)
      end
      if changed("c:resetCount", order.produced) then text(18, 12, 46, "Delivered so far: " .. value(order.produced), 2) end
      local canSave = available("ORDER_EDIT", snapshot, order)
      if changed("c:resetButtons", form.resetSelected, canSave) then
        button(18, 16, 14, "NO", canSave, not form.resetSelected)
        button(34, 16, 14, "YES", canSave, form.resetSelected)
        button(50, 16, 14, "BACK", true, false)
      end
    elseif page == "Form" then
      local editable = formEditable(snapshot)
      if changed("c:formFrame", form.orderId) then
        panel(1, 4, 80, 21, "CROPS"); renderer.fill(45, 5, 1, 19, 0, "│", 11); text(45, 4, 1, "┬", 11); text(45, 24, 1,
          "┴", 11)
        text(48, 4, 30, form.orderId and " EDIT ORDER #" .. form.orderId .. " " or " ORDER DETAILS ", 8); text(48, 6, 31,
          "SELECTED CROP", 2)
        text(48, 9, 30, "QUANTITY", 2); text(48, 12, 8, "GROWTH", 2); text(58, 12, 8, "GAIN", 2); text(68, 12, 10,
          "RESISTANCE", 2)
        text(48, 16, 21, "Humidity", 2); text(48, 17, 21, "Nutrients", 2); text(48, 18, 21, "Air quality", 2)
        text(48, 19, 21, "Terrain quality", 2); text(48, 20, 21, "Need quality", 2)
      end
      if changed("c:crops", form.crop, form.cropOffset, editable) then
        local key = nextCrop(nil, 1)
        for _ = 1, form.cropOffset do key = nextCrop(key, 1) end
        for index = 1, 16 do
          local shown = form.cropOffset + index <= cropCount
          text(3, 5 + index, 41, shown and Catalog.get(key).name or "", editable and 1 or 2,
            shown and key == form.crop and 4 or 0); key = nextCrop(key, 1)
        end
        text(48, 7, 30, Catalog.get(form.crop).name, 7); button(3, 23, 8, "PREV", editable and form.cropOffset > 0, false)
        local pageLabel = (math.floor(form.cropOffset / 16) + 1) .. " / " .. math.ceil(cropCount / 16)
        text(11, 23, 25, string.rep(" ", math.floor((25 - #pageLabel) / 2)) .. pageLabel, 2)
        button(36, 23, 8, "NEXT", editable and form.cropOffset + 16 < cropCount, false)
      end
      for index, field in ipairs(fields) do
        if changed("c:input" .. index, form.inputs[field], form.focus == index, editable) then
          local x, y, width = 48, 10, 30
          if index > 1 then x, y, width = index == 2 and 48 or index == 3 and 58 or 68, 13, index == 4 and 10 or 8 end
          text(x, y, width,
            (form.inputs[field] == "" and (index == 1 and "1 (default)" or "Any") or form.inputs[field]) ..
            (form.focus == index and "_" or ""), editable and 1 or 2, form.focus == index and 12 or 3)
        end
      end
      local terrain = snapshot.observation and snapshot.observation.terrain
      if terrain and terrain.crop ~= form.crop then terrain = nil end
      local known = terrain and terrain.known or 0
      local retained = not snapshot.enabled and terrain and
          (terrain.humidityMin ~= nil or terrain.nutrientsMin ~= nil or terrain.airMin ~= nil) or false
      if changed("c:terrainCoverage", known, retained) then
        text(48, 15, 21, retained and "TERRAIN retained" or "TERRAIN", 8)
        text(70, 15, 10, known .. "/36", 2)
      end
      if changed("c:terrainHumidity", terrain and terrain.humidityMin, terrain and terrain.humidityMax) then
        text(70, 16, 10, terrainRange(terrain and terrain.humidityMin, terrain and terrain.humidityMax), 1)
      end
      if changed("c:terrainNutrients", terrain and terrain.nutrientsMin, terrain and terrain.nutrientsMax) then
        text(70, 17, 10, terrainRange(terrain and terrain.nutrientsMin, terrain and terrain.nutrientsMax), 1)
      end
      if changed("c:terrainAir", terrain and terrain.airMin, terrain and terrain.airMax) then
        text(70, 18, 10, terrainRange(terrain and terrain.airMin, terrain and terrain.airMax), 1)
      end
      if changed("c:terrainQuality", terrain and terrain.qualityMin, terrain and terrain.qualityMax) then
        text(70, 19, 10, terrainRange(terrain and terrain.qualityMin, terrain and terrain.qualityMax), 1)
      end
      if changed("c:terrainNeed", form.crop, form.inputs.g, form.inputs.ga, form.inputs.r) then
        local minimum, maximum = Catalog.terrainNeed(form.crop, tonumber(form.inputs.g), tonumber(form.inputs.ga),
          tonumber(form.inputs.r))
        text(70, 20, 10, minimum and "≥" .. terrainRange(minimum, maximum) or "?", 1)
      end
      local canSave = available(form.orderId and "ORDER_EDIT" or "ORDER_CREATE", snapshot,
        form.orderId and editedOrder(snapshot)) and not form.submitted
      if changed("c:formButtons", canSave, form.submitted, form.orderId) then
        button(48, 23, 14, "BACK", true, false); button(64, 23, 14,
          form.submitted and "SENT" or form.orderId and "SAVE" or "CREATE", canSave, false)
      end
      local errorCode = form.orderId and not editable and not knownFatal(snapshot) and "ORDER_NOT_EDITABLE" or form
          .error or snapshot.uiDiagnostic or commandError
      if changed("c:formError", errorCode, notice) then
        if errorCode then
          text(48, 21, 30, "[" .. errorCode .. "]", 6)
          text(48, 22, 30, orderMessages[errorCode] or "Order request needs attention.", 6)
        else
          paragraph(48, 21, 30, 2, notice or "", 2)
        end
      end
    elseif page == "Orders" then
      local selected = selectOrder(orders)
      if cancelOrderId then
        local found = false; for _, order in ipairs(orders) do if order.id == cancelOrderId and order.status ~= "CLOSED" then found = true end end
        if not found then
          cancelOrderId = nil; api.invalidate(); return
        end
      end
      local quantityWidth = 3
      for index = 1, 16 do
        local order = orders[orderOffset + index]; if order then
          quantityWidth = math.max(quantityWidth,
            #tostring(order.K))
        end
      end
      local quantityX = 49 - quantityWidth
      if changed("c:ordersFrame", true) then
        panel(1, 4, 80, 21, "ALL ORDERS")
      end
      if changed("c:orderColumns", quantityWidth) then
        renderer.fill(2, 5, 78, 1, 0)
        text(3, 5, 7, "ID", 2); text(11, 5, quantityX - 12, "CROP", 2); text(
          quantityX, 5, quantityWidth, "QTY", 2)
        text(51, 5, 3, "G", 2); text(55, 5, 3, "Ga", 2); text(59, 5, 3, "R", 2); text(64, 5, 10, "STATE", 2); text(74, 5,
          6, "CANCEL", 2)
      end
      local rowsChanged = false
      for index = 1, 16 do
        local order = orders[orderOffset + index]; local selectedRow = order and order.id == selectedOrderId
        local canCancel = available("ORDER_CANCEL", snapshot, order) or false
        if changed("c:order" .. index, order and order.id, order and order.owner, order and order.cropId, order and order.status,
              order and order.K, order and order.g, order and order.ga, order and order.r, selectedRow, canCancel, quantityWidth) then
          rowsChanged = true
          local y, paper = 5 + index, selectedRow and 4 or 0; renderer.fill(2, y, 78, 1, paper)
          if order then
            text(3, y, 7, "#" .. order.id, 1, paper); text(11, y, quantityX - 12, cropName(order), 1, paper); text(
              quantityX, y, quantityWidth, order.K, 1, paper)
            text(51, y, 3, order.g == nil and "Any" or order.g, 1, paper); text(55, y, 3,
              order.ga == nil and "Any" or order.ga, 1, paper); text(59, y, 3, order.r == nil and "Any" or order.r, 1,
              paper)
            text(64, y, 10, order.status, order.status == "ACTIVE" and 5 or 2, paper); text(77, y, 3,
              canCancel and "|×|" or "", canCancel and 1 or 2, paper)
          end
        end
      end
      local canEdit = available("ORDER_EDIT", snapshot, selected) or false
      if changed("c:orderButtons", orderOffset, #orders, available("ORDER_CREATE", snapshot), canEdit) then
        button(3, 23, 11, "NEW ORDER", available("ORDER_CREATE", snapshot), false); button(28, 23, 6, "PREV",
          orderOffset > 0, false)
        button(16, 23, 8, "EDIT", canEdit, false)
        local pageLabel = (math.floor(orderOffset / 16) + 1) .. "/" .. math.max(1, math.ceil(#orders / 16))
        text(34, 23, 14, string.rep(" ", math.floor((14 - #pageLabel) / 2)) .. pageLabel)
        button(48, 23, 6, "NEXT", orderOffset + 16 < #orders, false); button(73, 23, 6, "BACK", true, false)
      end
      if cancelOrderId then
        local redraw = changed("c:cancelFrame", cancelOrderId) or rowsChanged
        if redraw then
          renderer.fill(18, 8, 46, 11, 0); panel(18, 8, 46, 11, "CANCEL ORDER #" .. cancelOrderId .. "?")
          paragraph(21, 10, 40, 3,
            "Cancel this order? Delivered items are kept. Accepted robot work still needs verification.", 1)
        end
        local buttonsChanged = changed("c:cancelButtons", cancelConfirm)
        if redraw or buttonsChanged then
          button(21, 16, 16, "KEEP ORDER", true, not cancelConfirm); button(40, 16, 20, "CONFIRM CANCEL", true,
            cancelConfirm)
        end
      end
    else
      local reason, explanation, recommendation, severity = issue(snapshot)
      local routine = severity == 2 or reason == "IO_PREPARING" and severity == 7
      local taskFault, allTasksRunning = nil, tasks ~= nil
      for _, name in ipairs(taskNames) do
        local task = tasks and tasks[name]
        if not task or task.status ~= "running" then allTasksRunning = false end
        if task and (task.status == "failed" or task.error) and not taskFault then taskFault = name end
      end
      if taskFault then
        explanation, recommendation, severity = "Station process stopped: " .. taskFault,
            "Inspect the reported fault before restarting.", 6
        routine = false
      end
      if routine then
        local recoveryAdvice = recommendation
        explanation, recommendation, severity = nil, nil, 2
        if taskFault then
          explanation, recommendation, severity = "Station process stopped: " .. taskFault,
              "Inspect the reported fault before restarting.", 6
        elseif stock and stock.uncertain then
          explanation, recommendation, severity = issueLabels.TRANSFER_UNKNOWN[1], issueLabels.TRANSFER_UNKNOWN[2], 6
        elseif reason == "INVENTORY_RECOVERING" then
          explanation, recommendation = snapshot.enabled and recoveryMessage or "Inventory recovery is paused.",
              recoveryAdvice
        elseif stock and stock.stickReady == false and stock.stickCount ~= nil then
          explanation, recommendation, severity = issueLabels.CROP_STICKS[1], issueLabels.CROP_STICKS[2], 7
        elseif observed and ((observed.sensorInvalid or 0) > 0 or (observed.unreadable or 0) > 0) then
          explanation, recommendation, severity = "Some field readings are unavailable.",
              "Check the sensor and its connection.", 7
        end
      end
      local confirmed = network and network.paired == true and network.networkReady == true and
          (snapshot.physicalReady == true or snapshot.robotStatus == "RUNNING" or snapshot.action and snapshot.action.task) and
          observed and observed.ready == true and observed.covered == 36 and stock and stock.prepared == true and
          stock.stickReady == true and stock.stickCount ~= nil and allTasksRunning
      local title, impact, advice, ink
      if explanation then
        title, impact, advice, ink = severity == 2 and "Inventory recovery" or "Attention required", explanation,
            recommendation or "Open the reported component for inspection.", severity
      elseif not snapshot.enabled then
        title, impact, ink = "Automation is stopped", "Use START when you want to continue.", 2
      elseif confirmed then
        title, impact, ink = "All clear", "No problems detected.", 5
      else
        title, impact, ink = "Checking system status", "Some information is not yet confirmed.", 2
      end
      if changed("c:systemFrames", true) then
        panel(1, 4, 80, 7, "MESSAGE"); panel(1, 11, 80, 14, "STATUS")
      end
      if changed("c:message", title, impact, advice, ink, linkPanel, pairing, network and network.phase, pairingSelection and pairingSelection.boot, snapshot.enabled, available("PAIR_OPEN", snapshot)) then
        renderer.fill(2, 5, 78, 5, 0)
        if linkPanel or pairing then
          text(3, 5, 75, "ROBOT LINKING", 7)
          text(3, 6, 75,
            snapshot.enabled and "Stop automation before linking a robot." or
            pairing and "Waiting for fresh Robot announcements." or "Ready to request robot linking.")
          text(3, 7, 75,
            pairingSelection and "Review captured identity before confirming." or "Select a robot, Review, then Confirm.",
            2)
          if explanation then text(3, 8, 75, explanation, severity) end
          button(3, 9, 11, snapshot.enabled and "STOP" or pairing and "WAITING" or "LINK",
            snapshot.enabled or available("PAIR_OPEN", snapshot), false)
          button(70, 9, 9, "CLOSE", true, false)
        else
          text(3, 5, 75, title, ink); paragraph(3, 7, 75, 2, impact, 1)
          if advice then
            text(3, 9, 6, "TO DO", 2); text(10, 9, 68, advice, 1)
          end
        end
      end
      if pairing then
        local candidates = network.candidates or {}; selectCandidate(candidates)
        if pairing and changed("c:pairPages", candidateOffset, #candidates) then
          button(32, 23, 8, "PREV", candidateOffset > 0, false)
          button(42, 23, 8, "NEXT", candidateOffset + 8 < #candidates, false)
        end
        for index = 1, 8 do
          local candidate = candidates[candidateOffset + index]; local selectedRow = candidate and
              candidateOffset + index == candidateIndex
          if changed("c:candidate" .. index, candidate and candidate.address, candidate and candidate.code, candidate and candidate.boot, selectedRow) then
            text(3, 12 + index, 75,
              candidate and (selectedRow and "> " or "  ") .. candidate.code .. "  " .. candidate.address or
              index == 1 and #candidates == 0 and "Waiting for robot announcements..." or "", 1, selectedRow and 4 or 0)
          end
        end
        if changed("c:review", pairingSelection and pairingSelection.address, pairingSelection and pairingSelection.code, pairingSelection and pairingSelection.boot) then
          text(3, 21, 75,
            pairingSelection and pairingSelection.code .. "  " .. pairingSelection.address or
            "Review captures the selected robot identity.", 7)
          text(3, 22, 75, pairingSelection and "Boot: " .. pairingSelection.boot or "", 2); button(17, 23, 12, "CONFIRM",
            pairingSelection ~= nil, false)
        end
        if changed("c:pairButtons", #candidates, network.overflow) then
          button(3, 23, 11, "REVIEW", #candidates > 0, false)
        end
      else
        local connection = not network and "Not yet known" or network.paired == false and "Robot not linked" or
            network.networkReady == true and "Connected" or "Connection not confirmed"
        local linked = network and network.paired
        local linkButton = linked and (unlinkSelection and "CONFIRM" or "UNLINK ROBOT") or "LINK ROBOT"
        local linkButtonEnabled = linked and available("PAIR_RESET", snapshot) or not linked and network ~= nil
        if changed("c:connection", connection, linkButton, linkButtonEnabled, available("PAIR_OPEN", snapshot), snapshot.enabled) then
          text(3, 12, 28, "Robot link"); text(32, 12, 1, "●", connection == "Connected" and 5 or 2); text(34, 12, 27,
            connection, connection == "Connected" and 5 or 2)
          button(62, 12, 14, linkButton, linkButtonEnabled, false)
        end
        local uncertain = snapshot.action and snapshot.action.task and snapshot.action.outcome == "UNKNOWN" and
            snapshot.action.reason ~= "EXPECTED_EFFECT_ABSENT"
        local readiness = uncertain and "Physical result uncertain" or
            snapshot.action and snapshot.action.task and "Working" or snapshot.physicalReady == true and "Ready" or
            snapshot.robotStatus == "RUNNING" and "Working" or "Not confirmed"
        row("robot", 13, "Robot readiness", readiness, uncertain and 6 or readiness == "Ready" and 5 or 2)
        local sensor = observed and observed.sensorAvailable == true and "Available" or
            observed and observed.sensorAvailable == false and "Unavailable" or "Not yet known"
        row("sensor", 14, "Sensor", sensor, sensor == "Available" and 5 or sensor == "Unavailable" and 6 or 2)
        local sticks = not stock and "Not yet known" or stock.stickCount == nil and "Not yet known" or
            stock.stickReady and ("Sufficient (" .. stock.stickCount .. ")") or "Insufficient"
        row("sticks", 15, "Crop sticks", sticks,
          stock and stock.stickReady == true and 5 or stock and stock.stickReady == false and 7 or 2)
        local output = stock and stock.outputAvailable == true and "Available" or
            stock and stock.outputAvailable == false and "Unavailable" or "Not yet known"
        local bank = stock and stock.genebankAvailable == true and "Available" or
            stock and stock.genebankAvailable == false and "Unavailable" or "Not yet known"
        local trash = stock and stock.trashAvailable == true and "Available" or
            stock and stock.trashAvailable == false and "Unavailable" or "Not yet known"
        row("output", 16, "Output", output, output == "Available" and 5 or output == "Unavailable" and 6 or 2)
        row("bank", 17, "Genebank", bank, bank == "Available" and 5 or bank == "Unavailable" and 6 or 2)
        row("trash", 18, "Trash", trash, trash == "Available" and 5 or trash == "Unavailable" and 6 or 2)
        local exchanging = snapshot.ioCallPending or snapshot.ioRequestPending or snapshot.ioExchangeGranted
        row("items", 19, "Item processing",
          stock and stock.uncertain and "Transfer result uncertain" or
          stock and stock.phase == "RECOVERING" and "Restoring stocks" or
          stock and (stock.waiting or stock.problem) and "Waiting for storage" or
          stock and stock.busy and (stock.phase == "SORTING" and "Sorting" or "Preparing supplies") or
          exchanging and "Waiting for exchange" or stock and "Idle" or "Not yet known", stock and stock.fault and 6 or 2)
        local storageFault = snapshot.diagnostic and
            (snapshot.diagnostic:match("^STATE_") or snapshot.diagnostic == "WRITE_FAILED")
        row("orders", 20, "Order storage",
          storageFault and "Requires attention" or "Data available", storageFault and 6 or 5)
        row("program", 21, "Station program",
          taskFault and "Process stopped: " .. taskFault or allTasksRunning and "Running" or "Not confirmed",
          taskFault and 6 or allTasksRunning and 5 or 2)
        local requestError = commandError or snapshot.uiDiagnostic
        if changed("c:lastRequest", requestError) then
          text(3, 22, 75,
            requestError and "Last request: " .. (orderMessages[requestError] or tostring(requestError)) or "", 7)
        end
      end
    end
  end

  return api
end

return Ui
