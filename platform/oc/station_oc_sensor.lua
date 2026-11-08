local StationSensor = {}

function StationSensor.open(component, now)
  local address, reason, retryAt = nil, nil, -math.huge
  local function discover()
    local sensorAddress, discoveryError
    local callSucceeded = pcall(function()
      for candidate in component.list("sensor", true) do
        if sensorAddress then
          sensorAddress = nil; discoveryError = "SENSOR_AMBIGUOUS"; return
        end
        sensorAddress = candidate
      end
    end)
    if not callSucceeded then return nil, "SENSOR_UNAVAILABLE" end
    return sensorAddress, discoveryError or (not sensorAddress and "SENSOR_UNAVAILABLE")
  end
  return function(x, y, z)
    if not address then
      if now() < retryAt then return nil, reason or "SENSOR_UNAVAILABLE" end
      address, reason = discover()
      if not address then
        retryAt = now() + 3; return nil, reason
      end
      reason = nil
    end
    local present, kind = pcall(component.type, address)
    if not present or kind ~= "sensor" then
      address = nil; reason = "SENSOR_UNAVAILABLE"; retryAt = now() + 3
      return nil, reason
    end
    local callSucceeded, sensorResult, scanError = pcall(function() return component.proxy(address).scan(x, y, z) end)
    if not callSucceeded or sensorResult == nil or sensorResult == false or scanError ~= nil then
      address = nil; reason = scanError or "SENSOR_UNAVAILABLE"; retryAt = now() + 3
      return nil, reason
    end
    return sensorResult, scanError
  end
end

return StationSensor
