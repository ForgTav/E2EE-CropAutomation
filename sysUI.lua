local component = require("component")
local computer = require("computer")
local term = require("term")
local event = require("event")
local config = require('sysConfig')
local db = require('sysDB')
local sys = require('sysFunction')

local gpu = component.gpu
local screenWidth, screenHeight = gpu.getResolution()
local menuStartX = math.floor(screenWidth * 0.3)
local InfoStartX = menuStartX + 2
local startY = 2
local endY = screenHeight - 4

local startSystem
local needExitFlag
local needCleanupFlag
local selectedMenuItem
local currentMode
local modeExec

local farmCords = {}
local btnExitTable = {
  { text = "[ CleanUp and exit ]", y = 5,  startX = 0 },
  { text = "[ Force exit ]",       y = 10, startX = 0 },
}

local function clearRightSide()
  for y = 1, screenHeight do
    gpu.set(menuStartX + 1, y, string.rep(" ", screenWidth - menuStartX))
  end
end

local function clearRightExtraSide()
  for y = endY + 1, screenHeight do
    gpu.set(menuStartX + 1, y, string.rep(" ", screenWidth - menuStartX))
  end
end

local function drawSeparator()
  for y = 1, screenHeight do
    gpu.set(menuStartX, y, "║")
  end
end

local function drawSysInfo()
  while selectedMenuItem == 2 do
    clearRightSide()
    local robotStatus = sys.getLastRobotStatus()
    local computerStatus = sys.getLastComputerStatus()

    local totalMemory = computer.totalMemory()
    local freeMemory = computer.freeMemory()
    local usedMemory = totalMemory - freeMemory
    local usedPercent = (usedMemory / totalMemory) * 100
    local upTime = computer.uptime()


    gpu.set(InfoStartX, startY, "System info:")
    if not robotStatus then
      gpu.set(InfoStartX, startY + 1, "Robot: Busy")
    else
      gpu.set(InfoStartX, startY + 1, "Robot: Awaiting")
    end
    gpu.set(InfoStartX, startY + 2, "Computer: " .. computerStatus)

    gpu.set(InfoStartX, startY + 4, "Computers info:")
    gpu.set(InfoStartX, startY + 5, string.format("RAM: %.2f%% (%d/%d)", usedPercent, usedMemory, totalMemory))
    gpu.set(InfoStartX, startY + 6, string.format("Uptime: %d sec", math.floor(upTime)))
    os.sleep(1)
  end
end

--local lastScrollPoss = 1
--local scrollPos = 1
local visibleLines = screenHeight

local function logs2Text()
  local logs = db.getLogs()
  local readyLogs = {}

  for _, log in ipairs(logs) do
    if log.action == "transplantParent" then
      if log.isSchema ~= nil and log.isSchema then
        table.insert(readyLogs, string.format("%s: schema", log.action))
        table.insert(readyLogs, string.format("from: slot %02d", log.slot))
        table.insert(readyLogs, string.format("to: slot %02d", log.slot))
      elseif log.targetCrop ~= nil and log.targetCrop then
        table.insert(readyLogs, string.format("%s: targetCrop", log.action))
        table.insert(readyLogs, string.format("from: slot %02d", log.slot))
        table.insert(readyLogs, string.format("to: slot %02d", log.slot))
      elseif log.slotName == 'air' or log.slotName == 'emptyCrop' then
        table.insert(readyLogs, string.format("%s: empty slot", log.action))
        table.insert(readyLogs, string.format("from: slot %02d", log.slot))
        table.insert(readyLogs, string.format("to: slot %02d", log.slot))
      else
        table.insert(readyLogs, string.format("%s: stats", log.action))
        table.insert(readyLogs, string.format("from: slot %02d, stat %s", log.slot, log.slotStat))
        table.insert(readyLogs, string.format("to: slot %02d, stat %s", log.to, log.toStat))
      end
    elseif log.action == "transplant" then
      if log.farm == 'storage' then
        table.insert(readyLogs, string.format("%s: %s", log.action, log.farm))
        table.insert(readyLogs, string.format("from: working farm slot %02d", log.slot))
        table.insert(readyLogs, string.format("to: storage farm slot %02d", log.to))
      end
    else
      table.insert(readyLogs, string.format("%s: slot %02d", log.action, log.slot))
    end
  end

  return readyLogs
end

local function drawLogsText()
  if selectedMenuItem ~= 5 then
    return
  end

  local logs = logs2Text()
  local maxScrollPos = #logs - visibleLines + 1
  --if #logs <= visibleLines then
  --  scrollPos = 1
  --else
  --  scrollPos = maxScrollPos
  --end

  clearRightSide()
  for i = 0, visibleLines - 1 do
    local lineIndex = maxScrollPos + i
    if lineIndex <= #logs then
      gpu.set(InfoStartX, 0 + i + 1, logs[lineIndex])
    end
  end
end

--[[
local function initScroll(_, _, _, code)
  local delta = 0
  if code == 200 then
    delta = -1
  elseif code == 208 then
    delta = 1
  else
    return;
  end

  scrollPos = scrollPos + delta
  if scrollPos < 1 then
    scrollPos = 1
  end
  drawLogsText()
end


local function drawLogs()
  if selectedMenuItem ~= 5 then
    return
  end
  --event.listen("key_down", initScroll)
  drawLogsText()
end
]] --


local function drawAutoTierSettings()
  clearRightSide()
  local tiermode = modeExec.getConfig('tierMode')
  if tiermode == 1 then
    gpu.set(InfoStartX, startY, string.format("[ Mode: %s ]", 'schema {BETA}'))
  elseif tiermode == 2 then
    gpu.set(InfoStartX, startY, string.format("[ Mode: %s ]", modeExec.getConfig('targetCrop')))
  end

  gpu.set(InfoStartX, startY + 2, string.format("[ AutoStat while tiering: %s ]", modeExec.getConfig('statWhileTier')))
end

local function setAutoTierSettings(clickX, clickY)
  local targetKey
  if clickY == startY then
    targetKey = 'tierMode'
  elseif clickY == startY + 2 then
    targetKey = 'statWhileTier'
  end

  if not targetKey then
    return
  end

  local targetValue
  local targetText
  if targetKey == 'tierMode' then
    targetValue = modeExec.getConfig('tierMode')
    if targetValue == 1 then
      targetText = string.format("[ Mode: %s ]", 'schema {BETA}')
    elseif targetValue == 2 then
      targetText = string.format("[ Mode: %s ]", modeExec.getConfig('targetCrop'))
    end
  elseif targetKey == 'statWhileTier' then
    targetValue = modeExec.getConfig('statWhileTier')
    targetText = string.format("[ AutoStat while tiering: %s ]", modeExec.getConfig('statWhileTier'))
  end

  if (clickX >= InfoStartX and clickX <= InfoStartX + #targetText) then
    local newValue
    if targetKey == 'tierMode' then
      if targetValue == 1 then
        newValue = 2
      elseif targetValue == 2 then
        newValue = 1
      end
    elseif targetKey == 'statWhileTier' then
      if targetValue then
        newValue = false
      else
        newValue = true
      end
    end
    modeExec.setConfig(targetKey, newValue)
  end
  drawAutoTierSettings()
end

local function drawSlotInfo(clickX, clickY)
  clearRightExtraSide()
  local foundedSlot
  for i = 1, #farmCords, 1 do
    if (clickX >= farmCords[i].x and clickX <= farmCords[i].x + 1) and farmCords[i].y == clickY then
      foundedSlot = i
      break
    end
  end

  if not foundedSlot then
    return
  end

  local crop = db.getFarmSlot(foundedSlot)
  if crop.isCrop then
    if crop.name == 'emptyCrop' then
      gpu.set(menuStartX + 1, endY + 1, crop.name)
      if crop.crossingbase == 1 then
        gpu.set(menuStartX + 1, endY + 2, 'Crossing base: true')
      else
        gpu.set(menuStartX + 1, endY + 2, 'Crossing base: false')
      end
    elseif crop.name == 'air' then
      gpu.set(menuStartX + 1, endY + 1, crop.name)
    elseif crop.name ~= 'weed' or crop.name ~= 'Grass' then
      gpu.set(menuStartX + 1, endY + 1, string.format("%s Tier: %s", crop.name, crop.tier))

      gpu.set(menuStartX + 1, endY + 2, string.format("Growth: %d", crop.gr))
      gpu.set(menuStartX + 1, endY + 3, string.format("Gain: %d", crop.ga))
      gpu.set(menuStartX + 1, endY + 4, string.format("Resistance: %d", crop.re))

      gpu.set(menuStartX + 20, endY + 2, string.format("Nutrients: %d", crop.nutrients))
      gpu.set(menuStartX + 20, endY + 3, string.format("Water: %d", crop.water))
      gpu.set(menuStartX + 20, endY + 4, string.format("WeedEx: %d", crop.weedex))
    end
  else
    gpu.set(menuStartX + 1, endY + 1, crop.name)
  end
end

local function drawFarmGrid()
  local gridSize = config.workingFarmSize

  gpu.set(InfoStartX, startY, "WORKING FARM")
  gpu.set(InfoStartX, startY + 1, string.rep("-", (gridSize * 3) - 1))

  for slot = 1, config.workingFarmArea do
    local x = (slot - 1) // gridSize
    local row = (slot - 1) % gridSize
    local y
    if x % 2 == 0 then
      y = row + 1
    else
      y = -row + gridSize
    end

    local posX = (InfoStartX + (gridSize - x) * 3) - 3
    local posY = startY + 2 + (gridSize - y)

    gpu.set(posX, posY, string.format("%02d", slot))
    farmCords[slot] = { x = posX, y = posY }
  end

  gpu.set(InfoStartX, startY + gridSize + 2, string.rep("-", (gridSize * 3) - 1))

  gpu.set(menuStartX + 1, endY, string.rep("═", screenWidth - menuStartX))
  gpu.set(menuStartX + 1, endY + 1, 'Click on slot to get info')
end

local function exitBtnAction(clickX, clickY)
  if not startSystem then
    return
  end
  for i, btn in ipairs(btnExitTable) do
    if (clickX >= btn.startX and clickX <= btn.startX + #btn.text) and btn.y == clickY then
      needExitFlag = true
      if i == 1 then
        needCleanupFlag = true
      end
      --printCenteredText('Awaiting robot operation..')
      break
    end
  end
end

local function btnExit()
  if not startSystem then
    local startX = InfoStartX + math.floor((screenWidth - InfoStartX - #"System not running") / 2)
    gpu.set(startX, math.floor(screenHeight / 2), "System not running")
    return
  end

  local blockWidth = screenWidth - menuStartX
  gpu.set(menuStartX + math.floor((blockWidth - #"Exit:") / 2), 2, "Exit:")
  for i, btn in ipairs(btnExitTable) do
    local startX = menuStartX + math.floor((blockWidth - #btn.text) / 2)
    gpu.set(startX, btn.y, btn.text)
    btnExitTable[i].startX = startX
  end
end

local function btnStart()
  if not startSystem then
    startSystem = true
    gpu.set(2, screenHeight - 4, "[ Active ]")
  end
end

local menuButtons = {
  { text = "Farm",     y = 2,                menuBtn = drawFarmGrid,         actionBtns = drawSlotInfo },
  { text = "System",   y = 4,                menuBtn = drawSysInfo },
  { text = "Start",    y = screenHeight - 4, menuBtn = btnStart },
  { text = "Exit",     y = screenHeight - 2, menuBtn = btnExit,              actionBtns = exitBtnAction },
  { text = "Logs",     y = 6,                menuBtn = drawLogsText },
  { text = "AutoTier", y = 8,                menuBtn = drawAutoTierSettings, actionBtns = setAutoTierSettings }
}



local function drawMenu()
  if currentMode ~= 2 then
    table.remove(menuButtons, 6)
  end


  for i = 1, #menuButtons do
    local btn = menuButtons[i]
    term.setCursor(1, btn.y)
    gpu.fill(1, btn.y, menuStartX - 1, 1, " ")
    if i == selectedMenuItem then
      gpu.set(2, btn.y, "[ " .. btn.text .. " ]")
    else
      if i == 3 and startSystem then
        gpu.set(2, btn.y, "[ Active ]")
        gpu.set(menuStartX, btn.y, "║")
      else
        gpu.set(2, btn.y, "  " .. btn.text .. "  ")
        gpu.set(menuStartX, btn.y, "║")
      end
    end
  end
end

local function handleMouseClick(_, _, x, y, button)
  if x <= menuStartX then
    for i, btn in pairs(menuButtons) do
      if y == btn.y then
        if i == selectedMenuItem then
          break
        end
        if i ~= 3 then
          selectedMenuItem = i
          clearRightSide()
        end
        drawMenu()
        if btn.menuBtn then
          btn.menuBtn()
        end
        break
      end
    end
  else
    for i, btn in pairs(menuButtons) do
      if i == selectedMenuItem and btn.actionBtns then
        btn.actionBtns(x, y)
        break
      end
    end
  end
end

local function drawMainMenu()
  term.clear()

  term.setCursor(math.floor((screenWidth - #'Welcome to the IC2 Farm Automation System!') / 2), 1)
  term.write('Welcome to the IC2 Farm Automation System!')
  term.setCursor(math.floor((screenWidth - #'Please select an operation mode:') / 2), 2)
  term.write('Please select an operation mode:')

  local modeButtons = {
    { text = "autoStat",   startX = 0, startY = 0, needExec = false },
    { text = "autoTier",   startX = 0, startY = 0, needExec = true },
    { text = "autoSpread", startX = 0, startY = 0, needExec = false }
  }

  for i, mode in ipairs(modeButtons) do
    local startX = math.floor((screenWidth - #mode.text) / 2)
    modeButtons[i].startX = startX
    modeButtons[i].startY = (startY + 1) + (i * 2)
    term.setCursor(startX, (startY + 1) + (i * 2))
    term.write(mode.text)
  end

  while true do
    local _, _, clickX, clickY = event.pull("touch")
    for i, btn in ipairs(modeButtons) do
      if (clickX >= btn.startX and clickX <= btn.startX + #btn.text) and btn.startY == clickY then
        term.clear()
        currentMode = i
        if btn.needExec then
          modeExec = require(btn.text)
        end
        return btn.text
      end
    end
  end
end

local function getStartSystem()
  return startSystem
end

local function needExit()
  return needExitFlag
end

local function needCleanup()
  return needCleanupFlag
end
local function UIloading(set)
  if not set then
    gpu.set(screenWidth - 9, 1, string.rep(" ", 9))
    drawLogsText()
  else
    gpu.set(screenWidth - 9, 1, "Loading..")
  end
end

local function initUI()
  event.listen("touch", handleMouseClick)
  startSystem = false
  needExitFlag = false
  needCleanupFlag = false
  selectedMenuItem = 1

  term.clear()
  drawSeparator()
  drawMenu()
  drawFarmGrid()
  while not needExitFlag do
    os.sleep(0.1)
  end
  event.ignore("touch", handleMouseClick)
end

return {
  initUI = initUI,
  drawMainMenu = drawMainMenu,
  getStartSystem = getStartSystem,
  needExit = needExit,
  needCleanup = needCleanup,
  handleMouseClick = handleMouseClick,
  UIloading = UIloading
}
