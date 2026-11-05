local StationState = {
  maxPayload = 16384,
  maxInteger = 2147483647,
  maxOrders = 20
}

local function integer(value, minimum, maximum)
  return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
end
local function shape(recordFields, allowedFields)
  if type(recordFields) ~= "table" or getmetatable(recordFields) ~= nil then return false end
  for fieldName in pairs(recordFields) do
    if not allowedFields[fieldName] then return false end
  end
  return true
end
local function array(recordFields, limit)
  if type(recordFields) ~= "table" or getmetatable(recordFields) ~= nil then return nil end
  local entryCount = 0
  for fieldName in pairs(recordFields) do
    entryCount = entryCount + 1
    if entryCount > limit or not integer(fieldName, 1, limit) then return nil end
  end
  for i = 1, entryCount do if recordFields[i] == nil then return nil end end
  return entryCount
end
local function ident(textValue, limit)
  return type(textValue) == "string" and #textValue > 0 and #textValue <= limit
      and textValue:match("^[a-z0-9_.%-]+$") ~= nil
end
local function genes(recordFields)
  return (recordFields.g == nil or integer(recordFields.g, 0, 31))
      and (recordFields.ga == nil or integer(recordFields.ga, 0, 31))
      and (recordFields.r == nil or integer(recordFields.r, 0, 31))
end
local rootKeys = {
  schema = true,
  revision = true,
  nextOrderId = true,
  orders = true
}
local orderKeys = {
  id = true,
  owner = true,
  cropId = true,
  g = true,
  ga = true,
  r = true,
  K = true,
  status = true,
  produced = true
}
local Catalog = require("station_catalog")
function StationState.empty()
  return { schema = 8, revision = 0, nextOrderId = 1, orders = {} }
end

function StationState.validate(savedState)
  if not shape(savedState, rootKeys) or savedState.schema ~= 8
      or not integer(savedState.revision, 0, StationState.maxInteger)
      or not integer(savedState.nextOrderId, 1, StationState.maxInteger) then
    return nil, "ROOT"
  end
  local orderCount = array(savedState.orders, StationState.maxOrders)
  if not orderCount then return nil, "COLLECTION_BOUNDS" end
  local orderIds, activeOrderId = {}, nil
  for i = 1, orderCount do
    local savedOrder = savedState.orders[i]
    if not shape(savedOrder, orderKeys) then return nil, "ORDER" end
    local cropKey = tostring(savedOrder.owner) .. ":" .. tostring(savedOrder.cropId)
    if not integer(savedOrder.id, 1, savedState.nextOrderId - 1)
        or orderIds[savedOrder.id] or not ident(savedOrder.owner, 32) or not ident(savedOrder.cropId, 48)
        or not Catalog.canProceed(cropKey)
        or not genes(savedOrder)
        or Catalog.isDangerous(cropKey, savedOrder.g or 0)
        or not integer(savedOrder.K, 1, StationState.maxInteger) or not integer(savedOrder.produced, 0, savedOrder.K)
        or (savedOrder.status ~= "QUEUED" and savedOrder.status ~= "ACTIVE" and savedOrder.status ~= "CLOSED")
        or (savedOrder.status == "QUEUED" and savedOrder.produced ~= 0) then
      return nil, "ORDER"
    end
    orderIds[savedOrder.id] = true
    if savedOrder.status == "ACTIVE" then
      if activeOrderId or savedOrder.produced == savedOrder.K then return nil, "ACTIVE" end
      activeOrderId = savedOrder.id
    end
  end
  return true
end

local function checksum(payload)
  local checksumValue = 2166136261
  for i = 1, #payload do checksumValue = ((checksumValue ~ payload:byte(i)) * 16777619) & 0xffffffff end
  return string.format("%08x", checksumValue)
end
local function optional(fieldValue)
  if fieldValue == nil then return "~" end
  if type(fieldValue) == "number" then return string.format("%d", fieldValue) end
  return fieldValue
end
local function line(recordFields)
  for i, fieldValue in ipairs(recordFields) do
    if type(fieldValue) == "number" then
      recordFields[i] = string.format("%d",
        fieldValue)
    end
  end
  return table.concat(recordFields, "\t") .. "\n"
end

function StationState.encode(savedState)
  local callSucceeded, validationError = StationState.validate(savedState)
  if not callSucceeded then return nil, validationError end
  local rows = { line({ "S", savedState.revision, savedState.nextOrderId }), line({ "V", 8 }) }
  for _, savedOrder in ipairs(savedState.orders) do
    rows[#rows + 1] = line({ "O", savedOrder.id, savedOrder.owner, savedOrder.cropId, optional(savedOrder.g), optional(
      savedOrder.ga),
      optional(savedOrder.r), savedOrder.K, savedOrder.status, savedOrder.produced })
  end
  local payload = table.concat(rows)
  if #payload > StationState.maxPayload then return nil, "SIZE" end
  return "CA20\t8\t" .. #payload .. "\t" .. checksum(payload) .. "\n" .. payload
end

function StationState.decode(encodedState)
  if type(encodedState) ~= "string" or #encodedState > StationState.maxPayload + 64 then return nil, "SIZE" end
  local version, payloadLength, expectedChecksum, payloadOffset = encodedState:match(
    "^CA20\t(%d+)\t(%d+)\t([0-9a-f]+)\n()")
  if version and version ~= "8" then return nil, "UNSUPPORTED_SCHEMA" end
  if version ~= "8" or #payloadLength > 5 or #expectedChecksum ~= 8 then return nil, "HEADER" end
  local payload = encodedState:sub(payloadOffset)
  if tonumber(payloadLength) ~= #payload or #payload > StationState.maxPayload or checksum(payload) ~= expectedChecksum then
    return nil, "INTEGRITY"
  end
  local function number(fieldValue)
    if not fieldValue or #fieldValue > 10 or not fieldValue:match("^%d+$") then error("NUMBER", 0) end
    return tonumber(fieldValue)
  end
  local function opt(fieldValue) if fieldValue ~= "~" then return number(fieldValue) end end
  local callSucceeded, operationResult = pcall(function()
    if payload:sub(-1) ~= "\n" then error("LINES", 0) end
    local decodedState, rowIndex = StationState.empty(), 0
    for row in payload:gmatch("([^\n]*)\n") do
      rowIndex = rowIndex + 1
      if rowIndex > StationState.maxOrders + 2 or row == "" or row:find("\t\t") or row:sub(-1) == "\t" then
        error("ROWS", 0)
      end
      local fields = {}
      for fieldValue in row:gmatch("[^\t]+") do
        if #fields >= 12 then error("FIELDS", 0) end
        fields[#fields + 1] = fieldValue
      end
      if rowIndex == 1 and fields[1] == "S" and #fields == 3 then
        decodedState.revision, decodedState.nextOrderId = number(fields[2]), number(fields[3])
      elseif rowIndex == 2 and row == "V\t8" then
      elseif rowIndex > 2 and fields[1] == "O" and #fields == 10 and #decodedState.orders < StationState.maxOrders then
        decodedState.orders[#decodedState.orders + 1] = {
          id = number(fields[2]),
          owner = fields[3],
          cropId = fields[4],
          g = opt(fields[5]),
          ga = opt(fields[6]),
          r = opt(fields[7]),
          K = number(fields[8]),
          status = fields[9],
          produced = number(fields[10])
        }
      else
        error("GRAMMAR", 0)
      end
    end
    if rowIndex < 2 then error("ROWS", 0) end
    local valid, validationError = StationState.validate(decodedState)
    if not valid then error(validationError, 0) end
    return decodedState
  end)
  if not callSucceeded then return nil, tostring(operationResult) end
  return operationResult
end

function StationState.open(deps)
  local path, directory = deps.path, deps.directory
  local store = {}
  local writesAllowed, writeUncertain, revision, nextOrderId = false, false, nil, nil
  local function read()
    local encodedState, overflow = deps.readBytes(path, StationState.maxPayload + 64)
    if encodedState == nil then return nil, overflow or "READ_FAILED" end
    return encodedState, nil, overflow
  end
  local function createEmpty()
    if writeUncertain then return nil, "WRITE_FAILED", "LOCKED" end
    local directoryChecked, made = pcall(deps.makeDirectory, directory)
    if not directoryChecked or made ~= true then return nil, "WRITE_FAILED", "DIRECTORY" end
    local savedState = StationState.empty()
    revision, nextOrderId, writesAllowed = 0, 1, true
    local stateSaved, validationError, failureDetail = store.commit(savedState)
    if not stateSaved then return nil, validationError, failureDetail end
    return savedState
  end
  function store.load()
    writesAllowed = false
    local existsChecked, exists, existsError = pcall(deps.exists, path)
    if not existsChecked or exists == nil then
      return nil, "STATE_READ_FAILED", tostring(existsError or exists):sub(1, 160)
    end
    if not exists then return createEmpty() end
    local callSucceeded, encodedState, readError, overflow = pcall(read)
    if not callSucceeded or encodedState == nil then
      return nil, "STATE_READ_FAILED", tostring(callSucceeded and readError or encodedState):sub(1, 160)
    end
    local savedState, validationError = StationState.decode(encodedState)
    if overflow and validationError ~= "UNSUPPORTED_SCHEMA" then savedState, validationError = nil, "SIZE" end
    if validationError == "UNSUPPORTED_SCHEMA" then return nil, "STATE_SCHEMA_UNSUPPORTED", validationError end
    if not savedState then
      local recreatedState, createError, createDetail = createEmpty()
      return recreatedState, createError, createDetail, recreatedState ~= nil
    end
    revision, nextOrderId, writesAllowed = savedState.revision, savedState.nextOrderId, not writeUncertain
    return savedState
  end

  function store.commit(savedState)
    if not writesAllowed or writeUncertain then return nil, "WRITE_FAILED", "LOCKED" end
    if type(savedState) ~= "table" or savedState.revision ~= revision or revision >= StationState.maxInteger then
      return nil, "WRITE_FAILED", "REVISION"
    end
    if not integer(savedState.nextOrderId, nextOrderId, StationState.maxInteger) then
      return nil, "WRITE_FAILED",
          "ORDER_ID"
    end
    local previousRevision = savedState.revision
    savedState.revision = previousRevision + 1
    local encodedState, validationError = StationState.encode(savedState)
    savedState.revision = previousRevision
    if not encodedState then return nil, "WRITE_FAILED", validationError end
    writeUncertain, writesAllowed = true, false
    local callSucceeded, writeError = pcall(function()
      local written, reason = deps.writeBytes(path, encodedState)
      assert(written == true, reason or "WRITE_FAILED")
      local readbackState, readError, overflow = read()
      assert(not overflow and readbackState == encodedState, readError or "READBACK")
    end)
    if not callSucceeded then return nil, "WRITE_FAILED", tostring(writeError):sub(1, 160) end
    savedState.revision, revision, writeUncertain, writesAllowed = previousRevision + 1, previousRevision + 1, false,
        true
    nextOrderId = savedState.nextOrderId
    return true
  end

  return store
end

return StationState
