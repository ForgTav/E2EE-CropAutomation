local MAX_NBT = 2048

local function newTree()
  return { count = {}, first = {}, index = {}, next = {}, symbol = {}, max = 0 }
end
local fixedLiteralTree, fixedDistanceTree = newTree(), newTree()
local dynamicLiteralTree, dynamicDistanceTree, codeTree = newTree(), newTree(), newTree()
local literalCodeLengths, distanceCodeLengths, codeLengthLengths, combinedCodeLengths, uncompressedBytes = {}, {}, {}, {},
    {}

local function build(tree, lengths, offset, symbolCount, allowEmpty)
  local count, first, index, nextIndex, symbols =
      tree.count, tree.first, tree.index, tree.next, tree.symbol
  for codeLength = 1, 15 do count[codeLength] = 0 end
  local max = 0
  for i = offset, offset + symbolCount - 1 do
    local codeLength = lengths[i]
    assert(codeLength and codeLength >= 0 and codeLength <= 15, "Bad Huffman length")
    if codeLength > 0 then
      count[codeLength] = count[codeLength] + 1
      if codeLength > max then max = codeLength end
    end
  end
  if max == 0 then
    assert(allowEmpty, "Empty Huffman alphabet")
    tree.max = 0
    return
  end
  local code, symbolOffset = 0, 0
  for codeLength = 1, 15 do
    code = (code + (count[codeLength - 1] or 0)) * 2
    assert(code + count[codeLength] <= 2 ^ codeLength, "Oversubscribed Huffman tree")
    first[codeLength], index[codeLength], nextIndex[codeLength] = code, symbolOffset, symbolOffset
    symbolOffset = symbolOffset + count[codeLength]
  end
  for i = offset, offset + symbolCount - 1 do
    local codeLength = lengths[i]
    if codeLength ~= 0 then
      local slot = nextIndex[codeLength] + 1
      symbols[slot] = i - offset
      nextIndex[codeLength] = slot
    end
  end
  tree.max = max
end

for symbol = 0, 287 do
  literalCodeLengths[symbol + 1] = symbol <= 143 and 8 or symbol <= 255 and 9
      or symbol <= 279 and 7 or 8
end
for i = 1, 32 do distanceCodeLengths[i] = 5 end
build(fixedLiteralTree, literalCodeLengths, 1, 288)
build(fixedDistanceTree, distanceCodeLengths, 1, 32)

local lengthBases = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local lengthExtraBits = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local distanceBases = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
  193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local distanceExtraBits = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local lengthOrder = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function gunzip(gzipBytes)
  assert(type(gzipBytes) == "string" and #gzipBytes >= 18, "No GZIP tag")
  assert(gzipBytes:byte(1) == 31 and gzipBytes:byte(2) == 139
    and gzipBytes:byte(3) == 8, "Not GZIP/DEFLATE")
  local flags, gzipLength, deflateStart = gzipBytes:byte(4), #gzipBytes, 11
  assert(flags < 32, "Unsupported GZIP flags")
  if flags % 8 >= 4 then
    local extraLengthLow, extraLengthHigh = gzipBytes:byte(deflateStart, deflateStart + 1)
    assert(extraLengthHigh, "Bad GZIP extra data")
    deflateStart = deflateStart + 2 + extraLengthLow + extraLengthHigh * 256
  end
  if flags % 16 >= 8 then
    while deflateStart < gzipLength - 7 and gzipBytes:byte(deflateStart) ~= 0 do deflateStart = deflateStart + 1 end
    deflateStart = deflateStart + 1
  end
  if flags % 32 >= 16 then
    while deflateStart < gzipLength - 7 and gzipBytes:byte(deflateStart) ~= 0 do deflateStart = deflateStart + 1 end
    deflateStart = deflateStart + 1
  end
  if flags % 4 >= 2 then deflateStart = deflateStart + 2 end
  assert(deflateStart <= gzipLength - 8, "Invalid GZIP header")

  local expectedOutputSize = gzipBytes:byte(gzipLength - 3) + 256 * gzipBytes:byte(gzipLength - 2)
      + 65536 * gzipBytes:byte(gzipLength - 1) + 16777216 * gzipBytes:byte(gzipLength)
  assert(expectedOutputSize <= MAX_NBT, "NBT larger than limit")
  local readPosition, deflateEnd = deflateStart, gzipLength - 8
  local bitBuffer, availableBits = 0, 0
  local outputSize = 0
  local function read(bitCount)
    while availableBits < bitCount do
      assert(readPosition <= deflateEnd, "Truncated DEFLATE")
      bitBuffer = bitBuffer + gzipBytes:byte(readPosition) * 2 ^ availableBits
      readPosition = readPosition + 1
      availableBits = availableBits + 8
    end
    local decodedValue = bitBuffer % 2 ^ bitCount
    bitBuffer = math.floor(bitBuffer / 2 ^ bitCount)
    availableBits = availableBits - bitCount
    return decodedValue
  end
  local function decode(tree)
    local code = 0
    for codeLength = 1, tree.max do
      code = code * 2 + read(1)
      local relativeCode = code - tree.first[codeLength]
      if relativeCode >= 0 and relativeCode < tree.count[codeLength] then
        return tree.symbol[tree.index[codeLength] + relativeCode + 1]
      end
    end
    error("Invalid Huffman symbol")
  end

  local finalBlock = false
  while not finalBlock do
    finalBlock = read(1) == 1
    local blockType = read(2)
    if blockType == 0 then
      read(availableBits % 8)
      local size, invertedSize = read(16), read(16)
      assert((size + invertedSize) % 65536 == 65535, "Bad DEFLATE stored block")
      assert(outputSize + size <= MAX_NBT, "NBT too large")
      for _ = 1, size do
        outputSize = outputSize + 1
        uncompressedBytes[outputSize] = read(8)
      end
    else
      assert(blockType == 1 or blockType == 2, "Bad DEFLATE block type")
      local literalTree, distanceTree = fixedLiteralTree, fixedDistanceTree
      if blockType == 2 then
        local literalCount, distanceCount, codeLengthCount = read(5) + 257, read(5) + 1, read(4) + 4
        for i = 1, 19 do codeLengthLengths[i] = 0 end
        for i = 1, codeLengthCount do codeLengthLengths[lengthOrder[i] + 1] = read(3) end
        build(codeTree, codeLengthLengths, 1, 19)
        local decodedLengthCount, countNeeded = 0, literalCount + distanceCount
        while decodedLengthCount < countNeeded do
          local symbol = decode(codeTree)
          if symbol <= 15 then
            decodedLengthCount = decodedLengthCount + 1
            combinedCodeLengths[decodedLengthCount] = symbol
          else
            local repeatCount, repeatedLength
            if symbol == 16 then
              assert(decodedLengthCount > 0, "Bad Huffman repeat")
              repeatCount, repeatedLength = read(2) + 3, combinedCodeLengths[decodedLengthCount]
            elseif symbol == 17 then
              repeatCount, repeatedLength = read(3) + 3, 0
            elseif symbol == 18 then
              repeatCount, repeatedLength = read(7) + 11, 0
            else
              error("Bad Huffman repeat symbol")
            end
            assert(decodedLengthCount + repeatCount <= countNeeded, "Bad Huffman repeats")
            for _ = 1, repeatCount do
              decodedLengthCount = decodedLengthCount + 1
              combinedCodeLengths[decodedLengthCount] = repeatedLength
            end
          end
        end
        build(dynamicLiteralTree, combinedCodeLengths, 1, literalCount)
        build(dynamicDistanceTree, combinedCodeLengths, literalCount + 1, distanceCount, true)
        literalTree, distanceTree = dynamicLiteralTree, dynamicDistanceTree
      end
      while true do
        local literalSymbol = decode(literalTree)
        if literalSymbol < 256 then
          assert(outputSize < MAX_NBT, "NBT too large")
          outputSize = outputSize + 1
          uncompressedBytes[outputSize] = literalSymbol
        elseif literalSymbol == 256 then
          break
        else
          local lengthIndex = literalSymbol - 256
          local base, extra = lengthBases[lengthIndex], lengthExtraBits[lengthIndex]
          assert(base, "Bad DEFLATE length")
          local amount = base + read(extra)
          local distanceIndex = decode(distanceTree) + 1
          local distanceBase, distanceBits = distanceBases[distanceIndex], distanceExtraBits[distanceIndex]
          assert(distanceBase, "Bad DEFLATE distance")
          local backreferenceDistance = distanceBase + read(distanceBits)
          assert(backreferenceDistance <= outputSize and outputSize + amount <= MAX_NBT,
            "Invalid DEFLATE backreference")
          for _ = 1, amount do
            outputSize = outputSize + 1
            uncompressedBytes[outputSize] = uncompressedBytes[outputSize - backreferenceDistance]
          end
        end
      end
    end
  end
  assert(outputSize == expectedOutputSize, "GZIP size mismatch")
  return outputSize
end

local expectedType = { owner = 8, id = 8, growth = 1, gain = 1, resistance = 1 }
local function parseNBT(byteCount)
  local byteOffset = 1
  local owner, id, growth, gain, resistance
  local function number(bytes)
    assert(byteOffset + bytes - 1 <= byteCount, "Truncated NBT number")
    local decodedValue = 0
    for _ = 1, bytes do
      decodedValue = decodedValue * 256 + uncompressedBytes[byteOffset]
      byteOffset = byteOffset + 1
    end
    return decodedValue
  end
  local function skip(bytes)
    assert(bytes >= 0 and byteOffset + bytes - 1 <= byteCount, "Truncated NBT value")
    byteOffset = byteOffset + bytes
  end
  local function stringValue()
    local stringLength = number(2)
    assert(byteOffset + stringLength - 1 <= byteCount, "Truncated NBT string")
    local stringResult = ""
    if stringLength > 0 then
      stringResult = string.char(table.unpack(uncompressedBytes, byteOffset, byteOffset + stringLength - 1))
    end
    byteOffset = byteOffset + stringLength
    return stringResult
  end
  local parse
  parse = function(tag, name, depth)
    assert(depth <= 8, "NBT too deeply nested")
    local value
    if tag >= 1 and tag <= 3 then
      local bytes = tag == 1 and 1 or tag == 2 and 2 or 4
      value = number(bytes)
      if value >= 2 ^ (8 * bytes - 1) then
        value = value - 2 ^ (8 * bytes)
      end
    elseif tag == 8 then
      value = stringValue()
    elseif tag == 10 then
      while true do
        local tagType = number(1)
        if tagType == 0 then break end
        parse(tagType, stringValue(), depth + 1)
      end
    elseif tag == 9 then
      local elementType, count = number(1), number(4)
      assert(count <= 4096, "NBT list too large")
      for _ = 1, count do parse(elementType, nil, depth + 1) end
    elseif tag == 7 or tag == 11 or tag == 12 then
      local count = number(4)
      skip(count * (tag == 7 and 1 or tag == 11 and 4 or 8))
    elseif tag == 4 or tag == 5 or tag == 6 then
      skip(tag == 5 and 4 or 8)
    else
      error("Unsupported NBT tag " .. tostring(tag))
    end
    if depth == 1 and expectedType[name] then
      assert(tag == expectedType[name], "NBT_TYPE_" .. name)
      if name == "owner" then
        assert(owner == nil, "NBT_DUPLICATE_owner"); owner = value
      elseif name == "id" then
        assert(id == nil, "NBT_DUPLICATE_id"); id = value
      elseif name == "growth" then
        assert(growth == nil, "NBT_DUPLICATE_growth"); growth = value
      elseif name == "gain" then
        assert(gain == nil, "NBT_DUPLICATE_gain"); gain = value
      elseif name == "resistance" then
        assert(resistance == nil, "NBT_DUPLICATE_resistance"); resistance = value
      end
    end
  end
  assert(number(1) == 10, "NBT root is not compound")
  stringValue()
  parse(10, nil, 0)
  assert(type(owner) == "string" and owner ~= ""
    and type(id) == "string" and id ~= ""
    and growth ~= nil and gain ~= nil and resistance ~= nil,
    "NBT_MISSING_SEED_FIELDS")
  return owner, id, growth, gain, resistance
end

local function decode(tag)
  local uncompressedSize = gunzip(tag)
  return parseNBT(uncompressedSize)
end

local function readNBT(item)
  if type(item) ~= "table" then
    return nil, "item_missing"
  end
  if item.hasTag == false then
    return nil, "no_nbt"
  end
  if type(item.tag) ~= "string" then
    return nil, "nbt_unavailable"
  end

  local decodeSucceeded, owner, id, growth, gain, resistance = pcall(decode, item.tag)
  if not decodeSucceeded then
    return nil, tostring(owner)
  end

  return {
    owner = owner,
    id = id,
    growth = growth,
    gain = gain,
    resistance = resistance
  }
end

return { readNBT = readNBT }
