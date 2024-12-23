local component = require('component')
local event = require("event")
local os = require('os')
local serialization = require("serialization")
local tunnel = component.tunnel
local sensor = component.sensor
local robotSide


-- 1 = North  2 = East 3 = South 4 = West
local sidesCharger = {
  { 0,  -1 },
  { 1,  0 },
  { 0,  1 },
  { -1, 0 },
}

local function getChargerSide()
  for i = 1, #sidesCharger do
    local cur_scan = sensor.scan(sidesCharger[i][1], 0, sidesCharger[i][2])
    if cur_scan.block.name == 'opencomputers:charger' then
      robotSide = i
      return true
    end
  end
  return false;
end


local function cordtoScan(x, y)
  if robotSide == 1 then
    return { x, (-y - 1) }
  elseif robotSide == 2 then
    return { y + 1, x }
  elseif robotSide == 3 then
    return { x * -1, y + 1 }
  elseif robotSide == 4 then
    return { -y - 1, x * -1 }
  else
    os.stop()
  end
end




local function transporter(messagetype, data)
  if messagetype == 'getCrop' then
    local cord = cordtoScan(data['x'], data['y'])
    local cur_scan = sensor.scan(cord[1], 0, cord[2])
    SendToLinkedCards({
      type = 'getCrop',
      response = cur_scan
    })
    local block = cur_scan['block']
    if block['name'] == 'minecraft:air' or block['name'] == 'GalacticraftCore:tile.brightAir' then
      print('air')
    elseif block['name'] == 'ic2:te' then
      if block['label'] == 'Crop' then
        print('emptyCrop')
      else
        local crop = cur_scan['data']['Crop']
        print('name:' .. crop['cropId'] .. ', gr:' .. crop['statGrowth'] .. ', ga:' .. crop['statGain'] .. ',re' .. crop ['statResistance'])
      end
    else
      print('block')
    end
  end
end


SendToLinkedCards = function(ready_message)
  local message_to_send = serialization.serialize(ready_message)
  tunnel.send(message_to_send)
end

if not getChargerSide() then
  error('Charger not found')
end

print("LinkedRelay Started")

while true do
  local _, _, _, _, _, message = event.pull("modem_message")
  local unserilized = serialization.unserialize(message)
  print('Receive message:' .. unserilized['type'])
  transporter(unserilized['type'], unserilized)
end
