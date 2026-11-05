local LinkProtocol = require("shared_link")
local LinkStore = {}

function LinkStore.open(role, localModemAddress, deps)
  local path, directory = deps.path, deps.directory
  local writeUncertain, loadedConfigText, configLoaded = false, nil, false
  local function read()
    local callSucceeded, configText, overflow = pcall(function()
      local exists, reason = deps.exists(path)
      assert(exists ~= nil, reason or "EXISTS_FAILED")
      if not exists then return nil end
      local encodedConfig, tooLarge = deps.readBytes(path, 1024)
      assert(encodedConfig ~= nil, tooLarge or "READ_FAILED")
      return encodedConfig, tooLarge
    end)
    if not callSucceeded then return nil, "LINK_READ_FAILED" end
    if overflow then return nil, "LINK_CORRUPT" end
    return configText
  end
  local api = {}
  function api.remove()
    if writeUncertain then return nil, "LINK_WRITE_FAILED" end
    local previousConfig, readError = read()
    if readError then return nil, readError end
    if not configLoaded or previousConfig ~= loadedConfigText then return nil, "LINK_CHANGED" end
    writeUncertain = true
    local removed = pcall(function()
      if previousConfig ~= nil then
        local removed, reason = deps.remove(path)
        assert(removed == true, reason or "REMOVE_FAILED")
      end
      local remainingConfig, verifyError = read()
      assert(remainingConfig == nil and verifyError == nil, "REMOVE_READBACK_FAILED")
    end)
    if not removed then return nil, "LINK_WRITE_FAILED" end
    writeUncertain, loadedConfigText = false, nil
    return true
  end

  function api.load()
    local encodedConfig, readError = read()
    if readError then return nil, readError end
    loadedConfigText, configLoaded = encodedConfig, true
    if encodedConfig == nil then return nil, "LINK_MISSING" end
    local linkConfig = LinkProtocol.decode(encodedConfig, role, localModemAddress)
    if not linkConfig then return nil, "LINK_CORRUPT" end
    return linkConfig
  end

  function api.save(linkConfig, replace)
    if writeUncertain or not LinkProtocol.validConfig(linkConfig, role, localModemAddress) then
      return nil,
          "LINK_WRITE_FAILED"
    end
    local previousConfig, readError = read()
    if readError then return nil, readError end
    if not configLoaded or previousConfig ~= loadedConfigText then return nil, "LINK_CHANGED" end
    if previousConfig ~= nil and not replace then return nil, "LINK_REPLACE_REQUIRED" end
    local encodedConfig
    writeUncertain = true
    local callSucceeded = pcall(function()
      local made, directoryError = deps.makeDirectory(directory)
      assert(made == true, directoryError or "DIRECTORY_FAILED")
      encodedConfig = LinkProtocol.encode(linkConfig)
      local written, writeError = deps.writeBytes(path, encodedConfig)
      assert(written == true, writeError or "WRITE_FAILED")
      local readback = read()
      assert(readback == encodedConfig, "READBACK_FAILED")
    end)
    if not callSucceeded then return nil, "LINK_WRITE_FAILED" end
    writeUncertain = false
    loadedConfigText = encodedConfig
    return true
  end

  return api
end

return LinkStore
