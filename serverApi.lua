local component = require('component')
local event = require('event')
local config = require('config')
local serialization = require("serialization")
local gps = require('gps')
local tunnel = component.tunnel

local function sendToLinkedCards(ready_message)
  local loop = true;
  local sended_message = false;
  while loop do
    if not sended_message then
      local message_to_send = serialization.serialize(ready_message)
      tunnel.send(message_to_send)
      sended_message = true
    end

    local _, _, _, _, _, message = event.pull("modem_message")
    local unserilized = serialization.unserialize(message)
    local response_type = unserilized.type
    local response_data = unserilized.response

    if response_type == 'getCrop' then
      local block = response_data['block']
      if block['name'] == 'minecraft:air' or block['name'] == 'GalacticraftCore:tile.brightAir' then
        return { isCrop = true, name = 'air' }
      elseif block['name'] == 'ic2:te' then
        if block['label'] == 'Crop' then
          return { isCrop = true, name = 'emptyCrop' }
        else
          local crop = response_data['data']['Crop']
          return {
            isCrop = true,
            name = crop['cropId'],
            gr = crop['statGrowth'],
            ga = crop['statGain'],
            re = crop['statResistance'],
            tier = config.seedTiers[crop['cropId']]
          }
        end
      else
        return { isCrop = false, name = 'block' }
      end
    end
  end
end

local function initGetCrop()
  local cur_grs = gps.getPos()
  local send_table = {
    type = 'getCrop',
    x = cur_grs[1],
    y = cur_grs[2]
  }
  return send_table
end

return {
  initGetCrop = initGetCrop,
  sendToLinkedCards = sendToLinkedCards
}
