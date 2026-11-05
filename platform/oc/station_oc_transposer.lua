local StationTransposer = {}

function StationTransposer.open(component)
  local transposerProxy, transposerAddress
  local generation, revision, discoveryRevision = 0, 0
  local function discover()
    local transposerAddress
    for uuid in component.list("transposer") do
      if transposerAddress then return end
      transposerAddress = uuid
    end
    if not transposerAddress then return end
    local success, transposerProxy = pcall(component.proxy, transposerAddress)
    if success and transposerProxy then return transposerProxy, transposerAddress end
  end
  local function resolve()
    if not transposerProxy and discoveryRevision ~= revision then
      discoveryRevision = revision
      transposerProxy, transposerAddress = discover()
    end
    return transposerProxy
  end
  local hardware = {}
  resolve()
  local facade = { generation = function() return generation end }
  for _, method in ipairs({ "getInventorySize", "getStackInSlot", "transferItem" }) do
    facade[method] = function(...)
      local currentProxy = resolve()
      if not currentProxy then
        return nil, method == "transferItem" and "TRANSFER_NOT_ATTEMPTED" or "TRANSPOSER"
      end
      local success, apiResult, apiError = pcall(currentProxy[method], ...)
      if success and apiError == nil and (method ~= "transferItem" or type(apiResult) == "number") then return apiResult end
      local typeReadSucceeded, componentKind = pcall(component.type, transposerAddress)
      if transposerProxy == currentProxy and (not typeReadSucceeded or componentKind ~= "transposer") then
        transposerProxy = nil; generation = generation + 1; discoveryRevision = nil
      end
      return nil, "INVENTORY_API_ERROR"
    end
  end
  hardware.transposer = facade
  function hardware.changed(event, changedAddress, componentKind)
    if componentKind ~= "transposer" then return end
    revision = revision + 1
    if event == "component_added" and not transposerProxy then
      generation = generation + 1
    elseif event == "component_removed" and transposerAddress == changedAddress then
      transposerProxy = nil; generation = generation + 1
    end
  end

  return hardware
end

return StationTransposer
