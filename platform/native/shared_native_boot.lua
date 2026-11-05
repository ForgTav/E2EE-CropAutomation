-- CropAutomation Native bootstrap protocol 1; installed as /init.lua.
local bootAddress = assert(computer.getBootAddress(), "NATIVE_BOOT_ADDRESS_REQUIRED")
assert(component.type(bootAddress) == "filesystem", "NATIVE_BOOT_FILESYSTEM_REQUIRED")
local volume = assert(component.proxy(bootAddress), "NATIVE_BOOT_FILESYSTEM_REQUIRED")
assert(volume.address == bootAddress, "NATIVE_BOOT_FILESYSTEM_MISMATCH")

local function exists(path)
  local result, reason = volume.exists(path)
  assert(type(result) == "boolean" and reason == nil, reason or "NATIVE_BOOT_READ_FAILED")
  return result
end

local stationPresent = exists("/cropautomation/station.lua")
local robotPresent = exists("/cropautomation/robot.lua")
assert(stationPresent ~= robotPresent, "NATIVE_BOOT_REQUIRES_ONE_ROLE")
local role = stationPresent and "station" or "robot"
local runtimePath = "/cropautomation/platform/native/shared_native_runtime.lua"
local handle, openError = volume.open(runtimePath, "r")
if handle == nil or handle == false or openError ~= nil then
  if handle ~= nil and handle ~= false then pcall(volume.close, handle) end
  error(openError or "NATIVE_RUNTIME_OPEN_FAILED", 0)
end
local loaded, chunks = pcall(function()
  local pieces, pending, length = {}, "", 0
  while true do
    local bytes, reason = volume.read(handle, 2048)
    assert(reason == nil, reason)
    if bytes == nil then break end
    assert(type(bytes) == "string" and #bytes > 0 and #bytes <= 2048, "NATIVE_RUNTIME_READ_INVALID")
    length = length + #bytes
    assert(length <= 32768, "NATIVE_RUNTIME_TOO_LARGE")
    pending = pending .. bytes
    if #pending >= 2048 then
      pieces[#pieces + 1] = pending; pending = ""
    end
  end
  if pending ~= "" then pieces[#pieces + 1] = pending end
  return pieces
end)
local closed, closeResult, closeError = pcall(volume.close, handle)
assert(closed and closeResult ~= false and closeError == nil, closeError or "NATIVE_RUNTIME_CLOSE_FAILED")
assert(loaded, chunks)
local position = 0
local chunk, loadError = load(function()
  position = position + 1
  local bytes = chunks[position]
  chunks[position] = nil
  return bytes
end, "@" .. runtimePath, "t", _ENV)
chunks = nil
assert(chunk, loadError)
local runtimeModule = chunk()
assert(type(runtimeModule) == "table" and type(runtimeModule.open) == "function", "NATIVE_RUNTIME_INVALID")
local runtime = runtimeModule.open(volume, role, _ENV)
return runtime.start()
