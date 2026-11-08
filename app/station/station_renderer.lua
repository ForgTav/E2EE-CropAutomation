local Renderer = {}
local palette = { 0x03090C, 0xE9ECF5, 0xA0AFC5, 0x192B43, 0x332DA5, 0x10BD22, 0xFA484E, 0xF3CE48,
  0x6390EF, 0xCC66CC, 0xFFFF33, 0x91B2EE, 0x333399, 0x663300, 0x669933, 0xFF6699 }
function Renderer.new(display, unicode)
  local gpu, expectedScreen = display.gpu, display.address
  local saved, screenAddress, foreground, background
  local api = {}
  local function checkScreen()
    assert(gpu.getScreen() == expectedScreen, "UI_GPU_SCREEN_CHANGED")
  end
  local function checked(operation, ...)
    local result, reason = gpu[operation](...)
    if result == nil or result == false then error("UI_GPU_" .. operation .. ": " .. tostring(reason), 0) end
    return result
  end
  local function colors(ink, paper)
    if foreground ~= ink then
      checked("setForeground", ink, true); foreground = ink
    end
    if background ~= paper then
      checked("setBackground", paper, true); background = paper
    end
  end
  function api.open()
    -- Ui.update opens once before each redraw; display.resize checks the first open.
    if saved then
      checkScreen(); return false
    end
    display.resize()
    screenAddress = expectedScreen
    local original = {
      depth = gpu.getDepth(),
      palette = {}
    }
    for index = 0, 15 do original.palette[index] = assert(gpu.getPaletteColor(index)) end
    saved = original
    checked("setDepth", 4)
    for index = 0, 15 do checked("setPaletteColor", index, palette[index + 1]) end
    return true
  end

  function api.screen() return screenAddress end

  function api.resize()
    display.resize()
    foreground, background = nil, nil
  end

  function api.fill(x, y, width, height, paper, character, ink)
    local right, bottom = math.min(80, x + width - 1), math.min(25, y + height - 1)
    x, y = math.max(1, x), math.max(1, y)
    if right < x or bottom < y then return end
    colors(ink or 1, paper or 0); checked("fill", x, y, right - x + 1, bottom - y + 1, character or " ")
  end

  function api.text(x, y, width, text, ink, paper)
    if y < 1 or y > 25 or width <= 0 or x > 80 or x + width <= 1 then return end
    local right = math.min(80, x + width - 1)
    local clippedX = math.max(1, x)
    text = tostring(text or ""):gsub("[%z\1-\31\127]", " ")
    local visible, position = "", x
    local isAscii = x % 1 == 0 and width % 1 == 0
    if isAscii then
      for index = 1, #text do
        if text:byte(index) >= 128 then
          isAscii = false; break
        end
      end
    end
    if isAscii then
      visible = text:sub(clippedX - x + 1, right - x + 1)
    else
      for index = 1, unicode.len(text) do
        local character = unicode.sub(text, index, index)
        local characterWidth = unicode.charWidth(character)
        if position + characterWidth - 1 > right then break end
        if characterWidth > 0 and position >= clippedX then
          if visible == "" and position > clippedX then visible = string.rep(" ", position - clippedX) end
          visible = visible .. character
        end
        position = position + characterWidth
      end
    end
    colors(ink or 1, paper or 0)
    checked("fill", clippedX, y, right - clippedX + 1, 1, " ")
    if visible ~= "" then checked("set", clippedX, y, visible) end
  end

  function api.close()
    if not saved then return end
    local original = saved; saved = nil
    checkScreen()
    local firstFailure
    local function restore(body)
      local called, reason = pcall(body)
      if not called and not firstFailure then firstFailure = reason end
    end
    restore(function() checked("setDepth", original.depth) end)
    for index = 0, 15 do
      restore(function() checked("setPaletteColor", index, original.palette[index]) end)
    end
    foreground, background = nil, nil
    if firstFailure then error(firstFailure, 0) end
  end

  return api
end

return Renderer
