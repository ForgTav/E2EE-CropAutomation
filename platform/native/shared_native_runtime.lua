local NativeRuntime = {}
local root = "/cropautomation/"
local readSize, maxFileBytes = 2048, 131072

local function failure(operation, reason)
  return operation .. ": " .. tostring(reason or "INVALID_RESULT"):sub(1, 160)
end

local function validPath(path)
  return type(path) == "string" and #path <= 256 and path:sub(1, 1) == "/" and
      not path:find("[%z\\]") and not path:find("//", 1, true) and
      not (path .. "/"):find("/%.%.?/")
end

function NativeRuntime.open(volume, role, machineEnvironment)
  local files = {}

  local function booleanCall(operation, path)
    if not validPath(path) then return nil, "NATIVE_PATH_INVALID" end
    local called, result, reason = pcall(volume[operation], path)
    if not called then return nil, failure(operation, result) end
    if type(result) ~= "boolean" or reason ~= nil then return nil, failure(operation, reason) end
    return result
  end

  function files.exists(path) return booleanCall("exists", path) end

  function files.isDirectory(path) return booleanCall("isDirectory", path) end

  function files.makeDirectory(path)
    local exists, reason = files.exists(path)
    if exists == nil then return nil, reason end
    if exists then
      local directory, directoryError = files.isDirectory(path)
      if directory == true then return true end
      return nil, directoryError or "NATIVE_NOT_DIRECTORY"
    end
    local made, makeError = booleanCall("makeDirectory", path)
    if made == true then return true end
    return nil, makeError or "NATIVE_MKDIR_FAILED"
  end

  function files.remove(path)
    local directory, reason = files.isDirectory(path)
    if directory == nil then return nil, reason end
    if directory then return nil, "NATIVE_FILE_REQUIRED" end
    local removed, removeError = booleanCall("remove", path)
    if removed == true then return true end
    return nil, removeError or "NATIVE_REMOVE_FAILED"
  end

  local function withHandle(path, mode, operation)
    if not validPath(path) then return nil, "NATIVE_PATH_INVALID" end
    local opened, handle, openError = pcall(volume.open, path, mode)
    if not opened then return nil, failure("open", handle) end
    if handle == nil or handle == false or openError ~= nil then
      -- Handles are opaque OC values, not necessarily Lua numbers.
      if handle ~= nil and handle ~= false then pcall(volume.close, handle) end
      return nil, failure("open", openError)
    end
    local called, result, detail = pcall(operation, handle)
    local closed, closeResult, closeError = pcall(volume.close, handle)
    if not called then return nil, failure(mode, result) end
    if not closed then return nil, failure("close", closeResult) end
    if closeResult == false or closeError ~= nil then return nil, failure("close", closeError) end
    return result, detail
  end

  local function readChunks(handle, limit)
    local chunks, length, pending = {}, 0, ""
    while true do
      local requested = math.min(readSize, limit + 1 - length)
      local chunk, reason = volume.read(handle, requested)
      assert(reason == nil, reason)
      if chunk == nil then
        if pending ~= "" then chunks[#chunks + 1] = pending end
        return chunks, false
      end
      assert(type(chunk) == "string" and #chunk > 0 and #chunk <= requested, "NATIVE_READ_INVALID")
      length = length + #chunk
      local overflow = length > limit
      if overflow then chunk = chunk:sub(1, #chunk - 1) end
      pending = pending .. chunk
      if #pending >= readSize or overflow then
        if pending ~= "" then chunks[#chunks + 1] = pending end
        pending = ""
      end
      if overflow then return chunks, true end
    end
  end

  function files.readBytes(path, limit)
    if type(limit) ~= "number" or limit % 1 ~= 0 or limit < 0 or limit > maxFileBytes then
      return nil, "NATIVE_READ_LIMIT_INVALID"
    end
    local chunks, overflow = withHandle(path, "r", function(handle) return readChunks(handle, limit) end)
    if not chunks then return nil, overflow end
    return table.concat(chunks), overflow
  end

  function files.writeBytes(path, bytes)
    if type(bytes) ~= "string" or #bytes > maxFileBytes then return nil, "NATIVE_WRITE_LIMIT_INVALID" end
    return withHandle(path, "w", function(handle)
      local written, reason = volume.write(handle, bytes)
      assert(written == true and reason == nil, reason or "NATIVE_WRITE_FAILED")
      return true
    end)
  end

  local loading, modules = {}, {}
  local environment = setmetatable({}, { __index = machineEnvironment })
  local runtime = {
    files = files,
    role = role,
    computer = machineEnvironment.computer,
    component = machineEnvironment.component,
    unicode = machineEnvironment.unicode
  }
  function runtime.bootId()
    local wallClockTime = math.floor(machineEnvironment.os.time())
    local bootId = string.format("%x-%x-%x-%x", wallClockTime, math.floor(runtime.computer.uptime() * 1000),
      machineEnvironment.math.random(0, 0x7fffffff), machineEnvironment.math.random(0, 0x7fffffff))
    if role == "robot" then
      return bootId, string.format("%04d", (wallClockTime + machineEnvironment.math.random(0, 9999)) % 10000)
    end
    return bootId
  end

  local function modulePath(name)
    if name == role then return root .. name .. ".lua" end
    local area = name:match("^(station)_") or name:match("^(robot)_") or name:match("^(shared)_")
    assert(area == "shared" or area == role, "NATIVE_MODULE_ROLE_INVALID")
    if name == "station_native_scheduler" then return root .. "platform/native/" .. name .. ".lua" end
    assert(not name:match("^shared_native_"), "NATIVE_MODULE_RESERVED")
    if name:match("^[a-z]+_oc_") then return root .. "platform/oc/" .. name .. ".lua" end
    return root .. "app/" .. area .. "/" .. name .. ".lua"
  end

  local function compile(name)
    local path = modulePath(name)
    local chunks, overflow = withHandle(path, "r", function(handle) return readChunks(handle, maxFileBytes) end)
    assert(chunks, overflow)
    assert(not overflow, "NATIVE_MODULE_TOO_LARGE")
    local position = 0
    -- OC I/O can yield. The reader inside Lua load must only touch memory.
    return load(function()
      position = position + 1
      local bytes = chunks[position]
      chunks[position] = nil
      return bytes
    end, "@" .. path, "t", environment)
  end

  local function evaluate(name, cacheResult)
    local previous = modules[name]
    if previous == loading then error("NATIVE_MODULE_CYCLE: " .. name, 0) end
    if previous ~= nil then
      if cacheResult then return previous end
      error("NATIVE_ONCE_ALREADY_CACHED: " .. name, 0)
    end
    assert(type(name) == "string" and #name <= 64 and name:match("^[a-z][a-z0-9_]*$"),
      "NATIVE_MODULE_NAME_INVALID")
    modules[name] = loading
    local called, result = pcall(function()
      local chunk, reason = compile(name)
      assert(chunk, reason)
      return chunk(name)
    end)
    modules[name] = nil
    if not called then error(result, 0) end
    if result == nil then result = true end
    if cacheResult then modules[name] = result end
    return result
  end

  function runtime.require(name)
    return evaluate(name, true)
  end

  function runtime.loadOnce(name)
    return evaluate(name, false)
  end

  function runtime.start()
    local entry = runtime.require(role)
    assert(type(entry) == "table" and type(entry.start) == "function", "NATIVE_ENTRY_REQUIRED")
    entry.start(runtime)
    return runtime.computer.shutdown()
  end

  environment.require = runtime.require
  return runtime
end

return NativeRuntime
