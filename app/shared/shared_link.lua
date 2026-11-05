local LinkProtocol = {
  dataPort = 39392,
  marker = "CA27",
  candidateLimit = 16,
  candidateTTL = 9,
  pairTimeout = 12,
  maxInt = 2147483647
}
function LinkProtocol.ioRequest(mode, callSequence)
  return mode == "EXCHANGE" and LinkProtocol.integer(callSequence, 0, LinkProtocol.maxInt)
end

function LinkProtocol.plantingItem(name)
  return name == "ic2:crop_seed_bag" or name == "minecraft:wheat_seeds" or
      name == "minecraft:carrot" or name == "minecraft:potato" or name == "minecraft:melon_seeds" or
      name == "minecraft:beetroot_seeds" or name == "minecraft:pumpkin_seeds" or name == "minecraft:reeds"
end

function LinkProtocol.integer(numericValue, low, high)
  return type(numericValue) == "number" and numericValue == math.floor(numericValue) and numericValue >= low and
      numericValue <= high
end

function LinkProtocol.encodePosition(x, y, z)
  if LinkProtocol.integer(x, -7, 1) and LinkProtocol.integer(y, 0, 1) and LinkProtocol.integer(z, -4, 3) then
    return
        string.format("%d:%d:%d", x, y, z)
  end
end

function LinkProtocol.decodePosition(value)
  if type(value) ~= "string" or #value > 16 then return end
  local x, y, z = value:match("^(%-?%d+):(%d+):(%-?%d+)$")
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if LinkProtocol.encodePosition(x, y, z) == value then return x, y, z end
end

function LinkProtocol.token(textValue, maxLength)
  return type(textValue) == "string" and #textValue > 0 and #textValue <= (maxLength or 96) and
      textValue:match("^[%w_|:%-%.]+$") ~= nil
end

function LinkProtocol.address(textValue)
  return type(textValue) == "string" and #textValue == 36
end

function LinkProtocol.code(textValue) return type(textValue) == "string" and textValue:match("^%d%d%d%d$") ~= nil end

function LinkProtocol.task(id)
  if type(id) ~= "string" or #id > 10 then return end
  local numericValue = tonumber(id)
  if LinkProtocol.integer(numericValue, 1, LinkProtocol.maxInt) and id == tostring(numericValue) then return numericValue end
end

function LinkProtocol.call(id)
  if type(id) == "string" and id:sub(1, 5) == "call:" then return LinkProtocol.task(id:sub(6)) end
end

function LinkProtocol.route(senderBootId, targetBootId)
  assert(LinkProtocol.token(senderBootId) and not senderBootId:find("|", 1, true))
  assert(targetBootId == "*" or (LinkProtocol.token(targetBootId) and not targetBootId:find("|", 1, true)))
  return senderBootId .. "|" .. targetBootId
end

local actions = {
  PLANT_SEED = "TO",
  EXTRACT_AND_PLANT = "BOTH",
  PLACE_DOUBLE_STICKS = "TO",
  COLLECT_AND_CLEAR_CELL = "TO",
  COLLECT_AND_RESTORE_DOUBLE = "TO",
  REMOVE_WEED = "TO"
}
function LinkProtocol.action(name, from, to)
  local shape = actions[name]
  local function cell(primitiveValue) return LinkProtocol.integer(primitiveValue, 1, 36) end
  return shape ~= nil and ((shape == "TO" and from == 0 and cell(to)) or
    (shape == "BOTH" and cell(from) and cell(to) and from ~= to))
end

function LinkProtocol.parameters(name, from, to, variant)
  return LinkProtocol.action(name, from, to) and ((name == "PLACE_DOUBLE_STICKS" and
      (variant == "BARE_FARMLAND" or variant == "SINGLE")) or
    (name == "EXTRACT_AND_PLANT" and (variant == nil or variant == "REPLACE_TILE")) or
    (name ~= "PLACE_DOUBLE_STICKS" and name ~= "EXTRACT_AND_PLANT" and variant == nil))
end

function LinkProtocol.priority(name, emergency)
  return type(emergency) == "boolean" and
      (not emergency or name == "REMOVE_WEED" or name == "COLLECT_AND_CLEAR_CELL") and
      (name ~= "REMOVE_WEED" or emergency)
end

function LinkProtocol.encodeAction(name, from, variant, emergency)
  if not LinkProtocol.priority(name, emergency) then return end
  local prefix = emergency and "EMERGENCY:" or "NORMAL:"
  if name == "PLACE_DOUBLE_STICKS" then return prefix .. variant end
  if name == "EXTRACT_AND_PLANT" and variant == "REPLACE_TILE" then
    return prefix ..
        string.format("%d:REPLACE_TILE", from)
  end
  return prefix .. tostring(from)
end

function LinkProtocol.sticks(name, variant)
  if name == "PLACE_DOUBLE_STICKS" then
    return variant == "SINGLE" and 1 or 2
  end
  if name == "COLLECT_AND_RESTORE_DOUBLE" then return 2 end
  return (name == "PLANT_SEED" or name == "EXTRACT_AND_PLANT") and 1 or 0
end

function LinkProtocol.validChallenge(boot, challenge)
  if not LinkProtocol.token(boot) or not LinkProtocol.token(challenge) then return false end
  local prefix = boot .. ":c"
  return challenge:sub(1, #prefix) == prefix and LinkProtocol.task(challenge:sub(#prefix + 1)) ~= nil
end

function LinkProtocol.decodeAction(name, sourceOrVariant, to)
  if type(sourceOrVariant) ~= "string" then return end
  local priority, encoded = sourceOrVariant:match("^(%u+):(.+)$")
  if priority ~= "NORMAL" and priority ~= "EMERGENCY" then return end
  local emergency = priority == "EMERGENCY"
  if not LinkProtocol.priority(name, emergency) then return end
  local from, variant = tonumber(encoded), nil
  if name == "PLACE_DOUBLE_STICKS" then from, variant = 0, encoded end
  if name == "EXTRACT_AND_PLANT" and encoded:find(":", 1, true) then
    local source = encoded:match("^([1-9]%d?):REPLACE_TILE$")
    from, variant = tonumber(source), "REPLACE_TILE"
  end
  if LinkProtocol.parameters(name, from, to, variant) and
      LinkProtocol.encodeAction(name, from, variant, emergency) == sourceOrVariant then
    return from, variant, emergency
  end
end

function LinkProtocol.config(role, localModemAddress, remoteModemAddress, linkId)
  return {
    version = 2,
    role = role,
    local_modem = localModemAddress,
    peer_modem = remoteModemAddress,
    data_port = LinkProtocol.dataPort,
    link_id = linkId or
        (role == "station" and localModemAddress .. "|" .. remoteModemAddress or remoteModemAddress .. "|" .. localModemAddress)
  }
end

local configFields = { version = true, role = true, local_modem = true, peer_modem = true, data_port = true, link_id = true }
function LinkProtocol.validConfig(linkConfig, role, localModemAddress)
  if type(linkConfig) ~= "table" then return false end
  local fieldCount = 0
  for fieldName in pairs(linkConfig) do
    if not configFields[fieldName] then return false end; fieldCount = fieldCount + 1
  end
  return fieldCount == 6 and linkConfig.version == 2 and linkConfig.role == role and
      linkConfig.local_modem == localModemAddress and
      LinkProtocol.address(localModemAddress) and LinkProtocol.address(linkConfig.peer_modem) and
      localModemAddress ~= linkConfig.peer_modem and
      linkConfig.data_port == LinkProtocol.dataPort and LinkProtocol.token(linkConfig.link_id)
end

function LinkProtocol.encode(linkConfig)
  return '{version=2,role="' .. linkConfig.role .. '",local_modem="' .. linkConfig.local_modem ..
      '",peer_modem="' .. linkConfig.peer_modem .. '",data_port=39392,link_id="' .. linkConfig.link_id .. '"}\n'
end

function LinkProtocol.decode(encodedConfig, role, localModemAddress)
  if type(encodedConfig) ~= "string" or #encodedConfig > 1024 then return end
  local storedRole, localAddress, remoteModemAddress, linkId = encodedConfig:match(
    '^{version=2,role="([^"\\]*)",local_modem="([^"\\]*)",peer_modem="([^"\\]*)",data_port=39392,link_id="([^"\\]*)"}\n$')
  if not storedRole then return end
  local linkConfig = {
    version = 2,
    role = storedRole,
    local_modem = localAddress,
    peer_modem = remoteModemAddress,
    data_port = LinkProtocol.dataPort,
    link_id = linkId
  }
  if LinkProtocol.validConfig(linkConfig, role, localModemAddress) then return linkConfig end
end

function LinkProtocol.frame(localModemAddress, localAddress, remoteModemAddress, port, marker, linkId, route, kind, id,
                            payloadA, payloadB, payloadC, ...)
  local senderBootId, targetBootId
  if type(route) == "string" and #route <= 193 then senderBootId, targetBootId = route:match("^([^|]+)|([^|]+)$") end
  if localAddress ~= localModemAddress or not LinkProtocol.address(remoteModemAddress) or remoteModemAddress == localModemAddress or
      marker ~= LinkProtocol.marker or select("#", ...) ~= 0 or not LinkProtocol.token(senderBootId) or
      (targetBootId ~= "*" and not LinkProtocol.token(targetBootId)) or
      not LinkProtocol.token(kind, 24) or (id ~= "*" and not LinkProtocol.token(id, 96)) or type(linkId) ~= "string" or #linkId > 96 then
    return
  end
  if id == "*" and kind ~= "STATUS_QUERY" and kind ~= "STATUS" and kind ~= "IO_STATUS" then return end
  for _, primitiveValue in ipairs({ payloadA, payloadB, payloadC }) do
    if type(primitiveValue) ~= "string" and type(primitiveValue) ~= "number" then return end
    if type(primitiveValue) == "string" and #primitiveValue > 96 then return end
    if type(primitiveValue) == "number" and not LinkProtocol.integer(primitiveValue, 0, LinkProtocol.maxInt) then return end
  end
  if payloadA == nil or payloadB == nil or payloadC == nil then return end
  if port ~= LinkProtocol.dataPort then return end
  return {
    senderAddress = remoteModemAddress,
    port = port,
    link = linkId,
    senderBoot = senderBootId,
    targetBoot =
        targetBootId,
    kind = kind,
    id = id,
    a = payloadA,
    b = payloadB,
    c = payloadC
  }
end

function LinkProtocol.isPairKind(kind)
  return kind == "PAIR_ANNOUNCE" or kind == "PAIR_SELECT" or kind == "PAIR_CONFIRM" or kind == "PAIR_DONE"
end

return LinkProtocol
