local words = {
  {
    width = 23,
    height = 6,
    text = [=[
  ____
 / ___|_ __ ___  _ __
| |   | '__/ _ \| '_ \
| |___| | | (_) | |_) |
 \____|_|  \___/| .__/
                |_|
]=]
  },
  {
    width = 57,
    height = 5,
    text = [=[
    _         _                        _   _
   / \  _   _| |_ ___  _ __ ___   __ _| |_(_) ___  _ __
  / _ \| | | | __/ _ \| '_ ` _ \ / _` | __| |/ _ \| '_ \
 / ___ \ |_| | || (_) | | | | | | (_| | |_| | (_) | | | |
/_/   \_\__,_|\__\___/|_| |_| |_|\__,_|\__|_|\___/|_| |_|
]=]
  },
}
local Startup = {}
function Startup.show(display)
  display.clear()
  local width, height = display.size()
  local logoHeight = #words - 1
  for _, word in ipairs(words) do logoHeight = logoHeight + word.height end
  local y = math.max(1, math.floor((height - logoHeight) / 2) + 1 - 5)
  for _, word in ipairs(words) do
    local x = math.max(1, math.floor((width - word.width) / 2) + 1)
    local row = 0
    for line in word.text:gmatch("[^\r\n]+") do
      if y + row > height then break end
      display.text(x, y + row, line:sub(1, math.max(0, width - x + 1)))
      row = row + 1
    end
    y = y + word.height + 1
  end
end

return Startup
