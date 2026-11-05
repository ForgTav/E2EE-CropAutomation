local LinkProtocol = require("shared_link")
local Modem = {}

function Modem.transport(modem)
  local transport = { address = modem.address, broadcast = modem.broadcast }
  function transport.send(remoteModemAddress, port, linkId, route, kind, id, payloadA, payloadB, payloadC)
    if port ~= LinkProtocol.dataPort then return false end
    local callSucceeded, result = pcall(modem.send, remoteModemAddress, port, LinkProtocol.marker, linkId, route, kind,
      id,
      payloadA or "", payloadB or "", payloadC or "")
    return callSucceeded and result == true
  end

  return transport
end

function Modem.openPort(modem)
  local portOpenedHere = false
  if not modem.isOpen(LinkProtocol.dataPort) then portOpenedHere = assert(modem.open(LinkProtocol.dataPort)) end
  return function()
    if portOpenedHere then
      portOpenedHere = false
      local called, closed, reason = pcall(modem.close, LinkProtocol.dataPort)
      assert(called and closed == true and reason == nil, reason or "MODEM_CLOSE_FAILED")
    end
  end
end

function Modem.select(component, wireless)
  local matchingModem
  for address in component.list("modem", true) do
    local modem = component.proxy(address)
    if modem.isWireless() == wireless then
      assert(not matchingModem, "Multiple matching modems; select hardware explicitly")
      matchingModem = modem
    end
  end
  return assert(matchingModem, "Required modem missing")
end

return Modem
