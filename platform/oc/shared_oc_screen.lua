local Screen = {}

local function selectAddress(component, kind)
  local selected
  for address in component.list(kind, true) do
    if selected then error("SCREEN_MULTIPLE_" .. kind:upper(), 0) end
    selected = address
  end
  if not selected then error("SCREEN_MISSING_" .. kind:upper(), 0) end
  return selected
end

function Screen.open(component, role, unicode)
  local gpuAddress = selectAddress(component, "gpu")
  local screenAddress = selectAddress(component, "screen")
  local gpu = assert(component.proxy(gpuAddress), "SCREEN_GPU_REQUIRED")
  local function call(operation, ...)
    local result, reason = gpu[operation](...)
    if result == nil or result == false then error("SCREEN_" .. operation .. ": " .. tostring(reason), 0) end
    return result
  end
  call("bind", screenAddress, false)
  local function checkBinding()
    assert(gpu.getScreen() == screenAddress, "SCREEN_BINDING_CHANGED")
  end
  local function dimensions(operation)
    local width, height = gpu[operation]()
    if not (type(width) == "number" and width > 0 and width % 1 == 0 and
          type(height) == "number" and height > 0 and height % 1 == 0) then
      error("SCREEN_" .. operation .. "_INVALID", 0)
    end
    return width, height
  end
  checkBinding()
  local width, height = role == "station" and 80 or 50, role == "station" and 25 or 16
  local function capacity()
    local maxWidth, maxHeight = dimensions("maxResolution")
    assert(maxWidth >= width and maxHeight >= height and
      (role ~= "station" or gpu.maxDepth() >= 4), "SCREEN_ROLE_CAPACITY_REQUIRED")
  end
  capacity()
  local savedWidth, savedHeight = dimensions("getResolution")
  local savedViewportWidth, savedViewportHeight = dimensions("getViewport")
  local savedInk, savedInkIndexed = gpu.getForeground()
  local savedPaper, savedPaperIndexed = gpu.getBackground()
  assert(type(savedInk) == "number" and type(savedInkIndexed) == "boolean" and
    type(savedPaper) == "number" and type(savedPaperIndexed) == "boolean", "SCREEN_COLORS_INVALID")
  local closed = false
  local function resolution(targetWidth, targetHeight)
    -- false without an error is valid when the size did not change.
    local result, reason = gpu.setResolution(targetWidth, targetHeight)
    if type(result) ~= "boolean" or reason ~= nil then error("SCREEN_RESOLUTION: " .. tostring(reason), 0) end
    local actualWidth, actualHeight = dimensions("getResolution")
    assert(actualWidth == targetWidth and actualHeight == targetHeight, "SCREEN_RESOLUTION_MISMATCH")
  end
  local function viewport(targetWidth, targetHeight)
    local result, reason = gpu.setViewport(targetWidth, targetHeight)
    if type(result) ~= "boolean" or reason ~= nil then error("SCREEN_VIEWPORT: " .. tostring(reason), 0) end
    local actualWidth, actualHeight = dimensions("getViewport")
    assert(actualWidth == targetWidth and actualHeight == targetHeight, "SCREEN_VIEWPORT_MISMATCH")
  end
  local function restore()
    checkBinding()
    local firstFailure
    local function attempt(body)
      local called, reason = pcall(body)
      if not called and not firstFailure then firstFailure = reason end
    end
    attempt(function() resolution(savedWidth, savedHeight) end)
    attempt(function() viewport(savedViewportWidth, savedViewportHeight) end)
    attempt(function() call("setForeground", savedInk, savedInkIndexed) end)
    attempt(function() call("setBackground", savedPaper, savedPaperIndexed) end)
    if firstFailure then error(firstFailure, 0) end
  end
  local function geometry()
    local actualWidth, actualHeight = dimensions("getResolution")
    if actualWidth ~= width or actualHeight ~= height then resolution(width, height) end
    local viewportWidth, viewportHeight = dimensions("getViewport")
    if viewportWidth ~= width or viewportHeight ~= height then viewport(width, height) end
  end
  local opened, reason = pcall(function()
    geometry()
    call("setForeground", 0xFFFFFF, false); call("setBackground", 0, false)
  end)
  if not opened then
    local restored, restoreReason = pcall(restore)
    if not restored then reason = tostring(reason) .. "; SCREEN_RESTORE: " .. tostring(restoreReason) end
    error(reason, 0)
  end
  local api = { gpu = gpu, address = screenAddress }
  local function active()
    assert(not closed, "SCREEN_CLOSED")
    checkBinding()
  end
  if role == "station" then
    function api.resize()
      active(); capacity(); geometry()
    end
  end
  function api.size()
    active(); return dimensions("getViewport")
  end

  function api.clear()
    active()
    call("setForeground", 0xFFFFFF, false); call("setBackground", 0, false)
    local currentWidth, currentHeight = dimensions("getViewport")
    call("fill", 1, 1, currentWidth, currentHeight, " ")
  end

  function api.text(x, y, text)
    active()
    local currentWidth, currentHeight = dimensions("getViewport")
    if y < 1 or y > currentHeight or x > currentWidth then return end
    text = tostring(text or ""):gsub("[%z\1-\31\127]", " ")
    local clippedX, visible = math.max(1, x), ""
    if not text:find("[\128-\255]") then
      visible = text:sub(clippedX - x + 1, currentWidth - x + 1)
    else
      local position = x
      for index = 1, unicode.len(text) do
        local character = unicode.sub(text, index, index)
        local characterWidth = unicode.charWidth(character)
        if position + characterWidth - 1 > currentWidth then break end
        if characterWidth > 0 and position >= clippedX then
          if visible == "" and position > clippedX then visible = string.rep(" ", position - clippedX) end
          visible = visible .. character
        end
        position = position + characterWidth
      end
    end
    if visible ~= "" then call("set", clippedX, y, visible) end
  end

  function api.line(row, text) return api.text(1, row, text) end

  function api.close()
    if closed then return false end
    closed = true
    restore()
    return true
  end

  return api
end

return Screen
