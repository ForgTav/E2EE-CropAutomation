local component = require("component")
local term = require("term")
local event = require("event")
local db = require('sysDB')
local sys = require('sysFunction')
local config = require('sysConfig')

local gpu = component.gpu
local screenWidth, screenHeight = gpu.getResolution()

local screenPadding = 1
local menuPX = 15

local tabButtons = {}
local modeTable = {
  { id = 1, name = 'autoTier' },
  { id = 2, name = 'autoStat' },
  { id = 3, name = 'autoSpread' }
}

local modeDescriptions = {
  autoSpread = "Copies a specific plant to storage.",
  autoStat   = "Improves stats. Stored once desired values reached.",
  autoTier   = "Transfers only new, previously unseen plants to storage."
}

local subModeTable = {
  { id = 1, name = 'schemaMode' },
  { id = 2, name = 'manualMode' }
}

local subModeDescriptions = {
  schemaMode = "Arranges plants in a pattern to breed the most new varieties.",
  manualMode = {
    "Robot will not interact with parent plants.",
    "You can manually set the grid for crossbreeding."
  }
}

local actionsTranplate = {
  { id = 1, name = 'Working' },
  { id = 2, name = 'Storage' }
}

local logLevels = {
  { id = 1, name = 'Minimal' },
  { id = 2, name = 'Medium' },
  { id = 3, name = 'Detailed' }
}

local logLevelsDescriptions = {
  Minimal = {
    "Only successful main actions for selected mode.",
    "No auxiliary operations are shown."
  },
  Medium = {
    "Includes all Minimal logs.",
    "Also logs parent crop modifications and transplant."
  },
  Detailed = {
    "Includes all Medium logs.",
    "Also logs weeding, stick placement, and removal of plants."
  }
}

local menuButtons = {
  { text = " Farm ",     tab = "farm" },
  { text = " System ",   tab = "system" },
  { text = " Actions ",  tab = "actions" },
  { text = " Settings ", tab = "settings" },
  { text = " Logs ",     tab = "logs" }
}

local uiColors = {
  background = 0x000000,
  foreground = 0x55FFFF,
  grid       = 0x3b3b3b,

  lightgray  = 0x3b3b3b,
  green      = 0x00FF00,
  black      = 0x000000,
  yellow     = 0xFFFF00,
  white      = 0xFFFFFF,
  red        = 0xFF5000,
  pink       = 0xFF5555,
  lightblue  = 0x5555FF,
  purple     = 0xFF00FF,
  blue       = 0x3399FF,
  orange     = 0xFFA500
}

local installationSteps = {
  {
    id = 1,
    stepLabel = "Welcome, and thank you for using the E2EE Crop Automation System!",
    stepDescription = {
      "If you encounter any issues or bugs,",
      "please report them in the E2EE Discord channel",
      "Your feedback helps us improve and grow.",
      "Happy farming!",
      "",
      "Press NEXT to begin the guided installation process."
    },
    checkBtn = false,
    checkDB = nil,
    needMap = false,
    needContent = false
  },
  {
    id = 2,
    stepLabel = "Step 1: Install Open Sensor",
    stepDescription = {
      "See the map below to guide placement. The blocks must be close together.",
      "After setup, connect the sensor to the computer via cable from OpenComputers.",
      "The cable must run underneath the blocks. Press Check button to verify",
      "the step installation. If verification failed, you have made a mistake."
    },
    checkBtn = true,
    checkDB = "IWSensor",
    needMap = true,
    needContent = true
  },
  {
    id = 3,
    stepLabel = "Step 2: Install Charger",
    stepDescription = {
      "It's positioning center and future Robot charger.",
      "Requires RF energy and redstone activation (e.g. a lever).",
      "Charger from OpenComputers."
    },
    checkBtn = true,
    checkDB = "IWCharger",
    needMap = true,
    needContent = true
  },
  {
    id = 4,
    stepLabel = "Step 3: Install Crop chest",
    stepDescription = {
      "You can use a chest or drawer to store crop sticks for the Robot.",
      "Make sure to refill it regularly, or the system will stop."
    },
    checkBtn = true,
    checkDB = "IWCropChest",
    needMap = true,
    needContent = true
  },
  {
    id = 5,
    stepLabel = "Step 4: Install Trash or Chest",
    stepDescription = {
      "If seeds are needed during Robot operation, place a chest.",
      "Otherwise, use a trash bin."
    },
    checkBtn = true,
    checkDB = "IWTrashOrChest",
    needMap = true,
    needContent = true
  },
  {
    id = 6,
    stepLabel = "Step 5: Collect Robot details and assemble the Robot",
    stepDescription = {
      "For this step, we will need the Electronics Assembler from OpenComputers.",
      "This machine is used to assemble a robot from its individual parts.",
      "It's not used by the system and should be placed outside the farm.",
      "When crafting the Linked card, you should have one card left for the robot.",
      "Install the Computer Case Tier 3 in the Electronics Assembler first.",
      "Then add all other parts. Complexity should be 16 and press Assemble."
    },
    checkBtn = false,
    checkDB = "IWRobotConnection",
    needMap = false,
    needContent = true
  },
  {
    id = 7,
    stepLabel = "Step 6: Install OpenOS",
    stepDescription = {
      "Rename Robot in an anvil. Put the Robot on top of the OC Charger.",
      "The robot must be positioned with its back facing the sensor. There is a",
      "small chest on its back. You should still have the OpenOS floppy left from",
      "setting up the computer. The robot has a slot in its inventory",
      "for a floppy disk. Put a floppy disk, Power on and install OpenOS",
      "from floppy disk. install --> Y --> Y",
      "After setting up OpenOS, remove the floppy.",
    },
    checkBtn = false,
    checkDB = "IWRobotConnection",
    needMap = true,
    needContent = false
  },
  {
    id = 8,
    stepLabel = "Step 7: Install the script on the Robot",
    stepDescription = {
      "Get the link from",
      "https://github.com/ForgTav/E2EE-CropAutomation.",
      "",
      "Or",
      "",
      "Discord channel of Enigmatica 2: Expert - Extended",
      "",
      "Or",
      "",
      "Or enter it manually — the link must be without spaces.",
      "",
      "",
      "wget https://raw.githubusercontent.com/ForgTav/",
      "E2EE-CropAutomation/main/robotSetup.lua && robotSetup"
    },
    checkBtn = false,
    checkDB = "IWRobotConnection",
    needMap = false,
    needContent = true
  },
  {
    id = 9,
    stepLabel = "Step 8: Install the tools in the Robot and start the Robot",
    stepDescription = {
      "Equip the Robot with a Transvector Binder and Weeding Trowel",
      "In its inventory (not in the wrench slot).",
      "Put axe or mattock in the wrench slot. (optional)",
      "Type 'start' and make sure no warnings messages appear on the screen."
    },
    checkBtn = true,
    checkDB = "IWRobotTools",
    needMap = false,
    needContent = false
  },
  {
    id = 10,
    stepLabel = "Step 9: Build the Working Farm",
    stepDescription = {
      "Now we need to build a Working Farm. Grab a hoe and build a Working Farm.",
      "There should be a trapdoor on top of the water source. Grid Working Farm 6x6",
    },
    checkBtn = true,
    checkDB = "IWWorkingFarm",
    needMap = true,
    needContent = true
  },
  {
    id = 11,
    stepLabel = "Step 10: Plant Target crop",
    stepDescription = {
      "An IC2 starter plant is required for operation. If none are available,",
      "sugarcane(from vanilla) in a Crop Stick instead. All plants must be placed",
      "on Crop Sticks. Plant a crop in the slot highlighted in red.",
    },
    checkBtn = true,
    checkDB = "IWTargetCrop",
    needMap = true,
    needContent = false
  },
  {
    id = 12,
    stepLabel = "Step 11: Install Transvector Dislocator and Blank Farmland",
    stepDescription = {
      "Transvector Dislocator goes above and faces the Blank Farmland.",
      "You can identify Facing side by the number of dots on it's surface.",
    },
    checkBtn = true,
    checkDB = "IWDislocatorAndBlank",
    needMap = true,
    needContent = true
  },
  {
    id = 13,
    stepLabel = "Step 12: Build the Storage Farm",
    stepDescription = {
      "Now we need to build a Storage Farm. Grab a hoe and build a Storage Farm.",
      "There should be a trapdoor on top of the water source. Grid Storage Farm 9x9",
    },
    checkBtn = true,
    checkDB = "IWStorageFarm",
    needMap = true,
    needContent = true
  },
  {
    id = 14,
    stepLabel = "Finally",
    stepDescription = {
      "You all set! 🚀",
      "The System tab will open next, showing the latest scan result.",
      "Before launching, make sure to adjust the settings as needed.",
      "The final scan will run after clicking Next. It could take a while.",
    },
    checkBtn = false,
    checkDB = "",
    needMap = false,
    needContent = false
  }
}

local function drawLogo()
  gpu.setForeground(uiColors.foreground)
  local title1 = "E2EE"
  local padding1 = math.floor((menuPX - 1 - #title1) / 2)
  gpu.set(2, 2, string.rep(" ", padding1) .. title1)

  local title2 = "CropAutomation"
  local padding2 = math.floor((menuPX - 1 - #title2 - 6) / 2)
  gpu.set(2, 3, string.rep(" ", padding2) .. title2)

  gpu.setForeground(uiColors.foreground)
end

local function registeterButton(btn)
  table.insert(tabButtons, btn)
end

local function drawButton(x, y, width, btnColor, label, action)
  local padding = math.floor((width - 2 - #label) / 2)
  local labelLine = "│" .. string.rep(" ", padding) .. label .. string.rep(" ", width - 2 - padding - #label) .. "│"

  gpu.setBackground(uiColors.background)
  gpu.setForeground(btnColor)

  gpu.set(x, y, "┌" .. string.rep("─", width - 2) .. "┐")
  gpu.set(x, y + 1, labelLine)
  gpu.set(x, y + 2, "└" .. string.rep("─", width - 2) .. "┘")

  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)
  if action ~= nil and action then
    registeterButton({
      x1 = x,
      x2 = x + width - 1,
      y1 = y,
      y2 = y + 2,
      action = action
    })
  end
end

local function drawClickedText(x, y, label, value, action)
  local labelLine = "⯈ " .. label
  if value ~= nil then
    labelLine = labelLine .. ": " .. value
  end

  gpu.set(x, y, labelLine)
  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)

  registeterButton({
    x1 = x,
    x2 = x + #labelLine,
    y1 = y,
    y2 = y,
    action = action
  })
end

local function drawStatControl(label, value, x, y)
  gpu.set(x, y, label .. ": ")
  local cursor = x + #label + 2

  gpu.set(cursor, y, "<<")

  registeterButton({
    x1 = cursor,
    x2 = cursor + 1,
    y1 = y,
    y2 = y,
    action = 'minusStat',
    subAction = label,
  })

  cursor = cursor + #tostring(value) + 1

  local valStr = string.format("%2d", value)
  gpu.set(cursor, y, valStr)
  cursor = cursor + 3

  gpu.set(cursor, y, ">>")

  registeterButton({
    x1 = cursor,
    x2 = cursor + 1,
    y1 = y,
    y2 = y,
    action = 'plusStat',
    subAction = label,
  })
end

local function drawSlotControl(value, x, y, transplateFor, slotFarm)
  local cursor = x + 2
  -- <<
  gpu.set(cursor, y, "<<")
  registeterButton({
    x1 = cursor,
    x2 = cursor + 1,
    y1 = y,
    y2 = y,
    action = 'minusSlot',
    transplateFor = transplateFor,
    slotFarm = slotFarm,
    count = 10,
  })
  cursor = cursor + 3

  -- <
  gpu.set(cursor, y, "<")
  registeterButton({
    x1 = cursor,
    x2 = cursor,
    y1 = y,
    y2 = y,
    action = 'minusSlot',
    transplateFor = transplateFor,
    slotFarm = slotFarm,
    count = 1,
  })
  cursor = cursor + 2

  -- value
  local valStr = string.format("%2d", value)
  gpu.set(cursor, y, valStr)
  cursor = cursor + #valStr + 1

  -- >
  gpu.set(cursor, y, ">")
  registeterButton({
    x1 = cursor,
    x2 = cursor,
    y1 = y,
    y2 = y,
    action = 'plusSlot',
    transplateFor = transplateFor,
    slotFarm = slotFarm,
    count = 1,
  })
  cursor = cursor + 2

  -- >>
  gpu.set(cursor, y, ">>")
  registeterButton({
    x1 = cursor,
    x2 = cursor + 1,
    y1 = y,
    y2 = y,
    action = 'plusSlot',
    transplateFor = transplateFor,
    slotFarm = slotFarm,
    count = 10,
  })
end

local function drawMenuButton(y, width, label, selected)
  local fg = selected and uiColors.lightblue or uiColors.foreground
  local padding = math.floor((width - 2 - #label) / 2)
  local labelLine = "│" .. string.rep(" ", padding) .. label .. string.rep(" ", width - 2 - padding - #label) .. "│"
  local buttonStart = screenPadding + 1

  gpu.setBackground(uiColors.background)
  gpu.setForeground(fg)

  gpu.set(buttonStart, y, "┌" .. string.rep("─", width - 2) .. "┐")
  gpu.set(buttonStart, y + 1, labelLine)
  gpu.set(buttonStart, y + 2, "└" .. string.rep("─", width - 2) .. "┘")

  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)
end

local function drawFrame(x, y, width, height, title)
  local top = "╔" .. string.rep("═", width - 2) .. "╗"

  if title and #title > 0 and #title < width - 4 then
    local padding = math.floor((width - 2 - #title) / 2)
    top = "╔" .. string.rep("═", padding) .. title .. string.rep("═", width - 2 - padding - #title) .. "╗"
  end

  gpu.set(x, y, top)

  for i = 1, height - 2 do
    gpu.set(x, y + i, "║")
    gpu.set(x + width - 1, y + i, "║")
  end

  gpu.set(x, y + height - 1, "╚" .. string.rep("═", width - 2) .. "╝")
end

local function fillBackground()
  gpu.setBackground(uiColors.background)
  for y = 1, screenHeight do
    gpu.set(1, y, string.rep(" ", screenWidth))
  end
  gpu.setBackground(uiColors.background)
end

local function fillGrid()
  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.grid)

  gpu.set(1, 1,
    "╔" .. string.rep("═", menuPX - 1)
    .. "╦" .. string.rep("═", screenWidth - menuPX - 2) .. "╗")

  gpu.set(1, 2, "║")
  gpu.set(menuPX + 1, 2, "║")
  gpu.set(screenWidth, 2, "║")

  gpu.set(1, 3, "║")
  gpu.set(menuPX + 1, 3, "║")
  gpu.set(screenWidth, 3, "║")

  gpu.set(1, 4, "╠" .. string.rep("═", menuPX - 1) .. "╣")
  gpu.set(screenWidth, 4, "║")

  for y = 5, screenHeight - 1 do
    gpu.set(1, y, "║")
    gpu.set(menuPX + 1, y, "║")
    gpu.set(screenWidth, y, "║")
  end

  local rightWidth = screenWidth - menuPX - 2
  gpu.set(1, screenHeight,
    "╚" .. string.rep("═", menuPX - 1)
    .. "╩" .. string.rep("═", rightWidth) .. "╝")

  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)
end

local function fillMenu()
  local selectedMenuItem = db.getSystemData('selectedMenuItem')

  drawLogo()
  for i = 1, #menuButtons do
    local btn = menuButtons[i]
    local selected = selectedMenuItem == btn.tab or false
    local menuSpace = menuPX - 1

    local y = 5 + (i - 1) * 3
    drawMenuButton(y, menuSpace, btn.text, selected)
    menuButtons[i].startY = y
    menuButtons[i].endY = y + 2
  end
end

local function fillScreen()
  fillBackground()
  fillGrid()
  fillMenu()
end

local function clearContentArea()
  tabButtons = {}
  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)
  gpu.fill(menuPX + 2, 2, screenWidth - menuPX - 2, screenHeight - 2, " ")
end

local function clearFullArea()
  tabButtons = {}
  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)
  term.clear()
end

local function drawIWHeader(step)
  local cursor = 2

  local stepLabel = step.stepLabel
  local stepDescriptions = step.stepDescription

  local labelX = math.ceil((screenWidth - #stepLabel) / 2)
  gpu.set(labelX, cursor, stepLabel)
  cursor = cursor + 2

  for _, text in ipairs(stepDescriptions) do
    local descX = math.ceil((screenWidth - #text) / 2)
    gpu.set(descX, cursor, text)
    cursor = cursor + 1
  end
end

local function drawIWFooter(step)
  local y = screenHeight - 1
  local nextIndex = step.id + 1
  local prevIndex = step.id - 1
  local activeNextBtn = false

  if prevIndex >= 1 then
    local backText = '< Back'
    gpu.set(2, y, backText)

    registeterButton({
      x1 = 2,
      x2 = 2 + #backText,
      y1 = y,
      y2 = y,
      action = 'prevIWStep'
    })
  end

  if step.checkBtn and step.checkDB then
    local currentStatus = db.getSystemData(step.checkDB) or false
    local checkText = '⯈ Check'

    local checkColor, checkSign

    if currentStatus then
      checkColor = uiColors.green
      checkSign = '✔'
      activeNextBtn = true
    else
      checkColor = uiColors.red
      checkSign = '✗'
    end

    local checkX = math.ceil((screenWidth - #checkText + 1) / 2)
    local checkY = screenHeight - 1

    gpu.set(checkX, checkY, checkText)
    gpu.setForeground(checkColor)
    gpu.set(checkX + #checkText, checkY, checkSign)
    gpu.setForeground(uiColors.foreground)
    registeterButton({
      x1 = checkX,
      x2 = checkX + #checkText,
      y1 = checkY,
      y2 = checkY,
      action = 'scanIWSystem'
    })
  else
    activeNextBtn = true
  end

  if nextIndex <= #installationSteps or step.id == 14 then
    local nextText = 'Next >'
    local x = screenWidth - #nextText - 1
    gpu.setForeground(uiColors.lightgray)
    if activeNextBtn then
      registeterButton({
        x1 = x,
        x2 = x + #nextText,
        y1 = y,
        y2 = y,
        action = step.id == 14 and 'exitIWStep' or 'nextIWStep'
      })
      gpu.setForeground(uiColors.foreground)
    end
    gpu.set(x, y, nextText)
  end
end

local function drawIWMap(step)
  if not step.needMap then return end

  local y = 7
  local maxY = 17
  local center = math.ceil(screenWidth / 2)

  --Working farm
  if step.id >= 10 then
    local cellW = 3
    local workingFarmSize = config.workingFarmSize
    local startX = center - math.floor((workingFarmSize * cellW) / 2) - 4
    local startY = y + 1

    if step.id >= 11 then
      gpu.setForeground(uiColors.lightgray)
    end

    for slot = 1, workingFarmSize * workingFarmSize do
      local col = (slot - 1) // workingFarmSize
      local row = (slot - 1) % workingFarmSize
      local gridY = (col % 2 == 0) and row + 1 or (workingFarmSize - row)
      local gridX = col + 1
      local mirroredX = workingFarmSize - gridX + 1

      local posX = startX + (mirroredX - 1) * cellW
      local posY = startY + (workingFarmSize - gridY)

      local label = (slot == 21) and 'WS' or '[]'
      gpu.set(posX, posY, label)
    end
    gpu.setForeground(uiColors.foreground)
  end

  --Storage farm
  if step.id >= 13 then
    local cellW = 3
    local storageSize = 9
    local startX = center + math.floor((storageSize * cellW) / 2) - 5
    local startY = y + 1

    for slot = 1, storageSize * storageSize do
      local col = (slot - 1) // storageSize
      local row = (slot - 1) % storageSize
      local gridY = (col % 2 == 0) and row + 1 or (storageSize - row)
      local gridX = col + 1
      local mirroredX = storageSize - gridX + 1

      local posX = startX + (mirroredX - 1) * cellW
      local posY = startY + (storageSize - gridY)

      local label = (slot == 21 or slot == 25 or slot == 57 or slot == 61) and 'WS' or '[]'
      gpu.set(posX, posY, label)
    end
  end

  --Dislocator and Blank Farmland
  if step.id >= 12 then
    if step.id == 12 then
      gpu.setForeground(uiColors.red)
      gpu.set(center + 5, maxY - 5, 'TD')
      gpu.setForeground(uiColors.foreground)
      --gpu.set(center + 4, maxY - 5, ' ← Transvector Dislocator')

      gpu.setForeground(uiColors.red)
      gpu.set(center + 5, maxY - 4, '[]')
      gpu.setForeground(uiColors.foreground)
      --gpu.set(center + 4, maxY - 4, ' ← Blank Farmland')
    else
      gpu.setForeground(uiColors.lightgray)
      gpu.set(center + 5, maxY - 5, 'TD')
      gpu.set(center + 5, maxY - 4, '[]')
      gpu.setForeground(uiColors.foreground)
    end
  end

  if step.id == 11 then
    gpu.setForeground(uiColors.red)
    gpu.set(center + 2, maxY - 4, '[] ')
    gpu.setForeground(uiColors.foreground)
  end

  --Trash or Chest
  if step.id == 5 then
    gpu.setForeground(uiColors.red)
    gpu.set(center - 4, maxY - 3, 'TC')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 10 then
    gpu.setForeground(uiColors.lightgray)
    gpu.set(center - 4, maxY - 3, 'TC')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 6 then
    gpu.set(center - 4, maxY - 3, 'TC')
  end

  --Crop chest
  if step.id == 4 then
    gpu.setForeground(uiColors.red)
    gpu.set(center - 1, maxY - 3, 'CH')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 10 then
    gpu.setForeground(uiColors.lightgray)
    gpu.set(center - 1, maxY - 3, 'CH')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 5 then
    gpu.set(center - 1, maxY - 3, 'CH')
  end

  --OC CHARGER
  if step.id == 3 or step.id == 7 then
    gpu.setForeground(uiColors.red)
    gpu.set(center + 2, maxY - 3, 'CG')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 10 then
    gpu.setForeground(uiColors.lightgray)
    gpu.set(center + 2, maxY - 3, 'CG')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 4 then
    gpu.set(center + 2, maxY - 3, 'CG')
  end

  --OPEN SENSOR
  if step.id == 2 then
    gpu.setForeground(uiColors.red)
    gpu.set(center + 2, maxY - 2, 'OS')
    gpu.setForeground(uiColors.foreground)
  elseif step.id >= 10 then
    gpu.setForeground(uiColors.lightgray)
    gpu.set(center + 2, maxY - 2, 'OS')
    gpu.setForeground(uiColors.foreground)
  else
    gpu.set(center + 2, maxY - 2, 'OS')
  end

  --COMPUTER CASE
  if step.id >= 10 then
    gpu.setForeground(uiColors.lightgray)
    gpu.set(center - 4, maxY - 2, 'CC')
    gpu.setForeground(uiColors.foreground)
  else
    gpu.set(center - 4, maxY - 2, 'CC')
  end

  --COMPUTER SCREEN
  if step.id >= 10 then
    gpu.setForeground(uiColors.lightgray)
    gpu.set(center - 1, maxY - 2, 'SC')
    gpu.setForeground(uiColors.foreground)
  else
    gpu.set(center - 1, maxY - 2, 'SC')
  end

  --PLAYER MARK
  gpu.setForeground(uiColors.yellow)
  gpu.set(center - 1, maxY, '⇑⇑')
  gpu.setForeground(uiColors.foreground)
end

local function drawIWContent(step)
  if not step.needContent then return end


  if step.id == 2 then
    local legend = {
      'CC - Computer Case',
      'SC - Screen',
      'OS - Open sensor',
      '⇑⇑ - You are looking at screen'
    }

    local cursor = 17
    for index, value in ipairs(legend) do
      gpu.set(4, cursor, value);
      cursor = cursor + 1
    end
  elseif step.id == 3 then
    local legend = {
      'CG - Charger',
    }

    local cursor = 17
    for index, value in ipairs(legend) do
      gpu.set(4, cursor, value);
      cursor = cursor + 1
    end
  elseif step.id == 4 then
    local legend = {
      'CH - Crop chest',
    }

    local cursor = 17
    for index, value in ipairs(legend) do
      gpu.set(4, cursor, value);
      cursor = cursor + 1
    end
  elseif step.id == 5 then
    local legend = {
      'TC - Trash/Chest',
    }

    local cursor = 17
    for index, value in ipairs(legend) do
      gpu.set(4, cursor, value);
      cursor = cursor + 1
    end
  elseif step.id == 6 then
    local cursorCol1 = 13
    local cursorCol2 = 13
    local robotDelailsCol1 = {
      '1. Memory Tier 2',
      '2. Hard Disk Drive Tier 1',
      '3. EEPROM (Lua BIOS)',
      '4. Linked card',
      '5. Internet Card',
      '6. Accelerated Processing Unit (APU) Tier 2',
    }

    local robotDelailsCol2 = {
      '7. Redstone Card Tier 1',
      '8. Inventory Upgrade',
      '9. Inventory Controller Upgrade',
      '10. Keyboard',
      '11. Screen Tier 1',
      '12. Disk drive (as block)',
    }


    gpu.set(2, 11, 'Also the list of parts needed for the Robot:');

    for index, value in ipairs(robotDelailsCol1) do
      gpu.set(2, cursorCol1, value);
      cursorCol1 = cursorCol1 + 1
    end

    for index, value in ipairs(robotDelailsCol2) do
      gpu.set(48, cursorCol2, value);
      cursorCol2 = cursorCol2 + 1
    end

    gpu.set(2, 20, 'P.S. If you used a Linked Card from Creative or a different one, sync it with');
    gpu.set(2, 21, 'the computer Linked Card by merging it in the crafting table.');
  elseif step.id == 10 or step.id == 13 then
    local legend = {
      '[] - Farmland',
      'WS - Water source'
    }

    local cursor = 17
    for index, value in ipairs(legend) do
      gpu.set(4, cursor, value);
      cursor = cursor + 1
    end
  elseif step.id == 12 then
    local legend = {
      'TD - Transvector Dislocator',
      '[] - Blank farm'
    }

    local cursor = 15
    for index, value in ipairs(legend) do
      gpu.set(4, cursor, value);
      cursor = cursor + 1
    end

    gpu.setForeground(uiColors.green)
    gpu.set(60, 7, 'Facing side');
    gpu.setForeground(uiColors.foreground)
    gpu.set(60, 8, '┌─ ▪  ▪ ─┐');
    gpu.set(60, 9, '▪ ┌────┐ ▪');
    gpu.set(60, 10, '  │    │  ');
    gpu.set(60, 11, '▪ └────┘ ▪');
    gpu.set(60, 12, '└─ ▪  ▪ ─┘');

    gpu.setForeground(uiColors.red)
    gpu.set(60, 14, 'Wrong side');
    gpu.setForeground(uiColors.foreground)
    gpu.set(60, 15, ' ──    ── ');
    gpu.set(60, 16, '│ ┌────┐ │');
    gpu.set(60, 17, '  │    │  ');
    gpu.set(60, 18, '│ └────┘ │');
    gpu.set(60, 19, ' ──    ── ');

    gpu.setForeground(uiColors.yellow)
    gpu.set(2, 19, '⚠ WARNING');
    gpu.setForeground(uiColors.foreground)
    gpu.set(2, 20, 'Incorrect placement of the Transvector Dislocator may cause world crashes.');
    gpu.set(2, 21, 'Make sure to position it carefully and exactly as instructed.');
  end
end

local function drawLegend(x, y)
  local legend = {
    { color = uiColors.white,  label = "Block" },
    { color = uiColors.blue,   label = "Air" },
    { color = uiColors.orange, label = "Crop" },
    { color = uiColors.red,    label = "Weed" },
    { color = uiColors.green,  label = "Seed" },
    { color = uiColors.purple, label = "Scheduled" }
  }

  local columns = 2
  local cellWidth = 12
  local frameWidth = cellWidth * columns + 3
  local frameHeight = math.ceil(#legend / columns) + 2

  drawFrame(x, y, frameWidth, frameHeight, " Legend ")

  for i = 1, #legend do
    local item = legend[i]
    local col = ((i - 1) % columns)
    local row = math.floor((i - 1) / columns)

    local posX = x + 1 + col * cellWidth
    local posY = y + 1 + row

    gpu.setBackground(item.color)
    gpu.set(posX, posY, "  ")
    gpu.setBackground(uiColors.background)
    gpu.setForeground(uiColors.foreground)
    gpu.set(posX + 3, posY, item.label)
  end
end

local function getCropColor(crop)
  if not crop then return uiColors.foreground end

  if not crop.isCrop and crop.name == 'block' then
    return uiColors.white
  elseif crop.isCrop and not crop.fromScan then
    return uiColors.purple
  elseif crop.isCrop and crop.name == 'air' then
    return uiColors.blue
  elseif crop.isCrop and crop.name == 'emptyCrop' then
    return uiColors.orange
  elseif crop.isCrop and sys.isWeed(crop) then
    return uiColors.red
  elseif crop.isCrop then
    return uiColors.green
  end
  return uiColors.foreground
end

local function drawFarmGrid()
  local cellW = 3
  local spacingX = 3
  local workingSize = config.workingFarmSize
  local storageSize = config.storageFarmSize
  local workingGridW = workingSize * cellW
  local storageGridW = storageSize * cellW

  local startX = menuPX + math.floor((screenWidth - menuPX - (workingGridW + spacingX + storageGridW)) / 2)
  local startY = 2
  local workingArea = workingSize ^ 2
  local storageArea = storageSize ^ 2
  local innerX = startX + 2
  local innerY = startY + 1

  local workingX = innerX
  local storageX = innerX + workingGridW + spacingX

  local titleWorking = "WORKING"
  local titleStorage = "STORAGE"
  local workingTitleX = workingX + math.floor((workingGridW - #titleWorking) / 2)
  local storageTitleX = storageX + math.floor((storageGridW - #titleStorage) / 2)

  gpu.set(workingTitleX, innerY, titleWorking)
  gpu.set(storageTitleX, innerY, titleStorage)

  for slot = 1, workingArea do
    local col = (slot - 1) // workingSize
    local row = (slot - 1) % workingSize
    local y = (col % 2 == 0) and row + 1 or (workingSize - row)
    local x = col + 1
    local mirroredX = workingSize - x + 1

    local posX = workingX + (mirroredX - 1) * cellW
    local posY = innerY + 1 + (workingSize - y)
    local crop = db.getFarmSlot(slot)

    gpu.setForeground(getCropColor(crop))
    gpu.set(posX, posY, string.format("%02d", slot))
    gpu.setForeground(uiColors.foreground)

    tabButtons[posY] = tabButtons[posY] or {}
    tabButtons[posY][posX] = {
      slot = slot,
      type = "working",
    }
  end

  local xxX = workingX + workingGridW
  local xxY = innerY + 1 + (workingSize - 1)
  gpu.set(xxX, xxY, "XX")

  for slot = 1, storageArea do
    local col = (slot - 1) // storageSize
    local row = (slot - 1) % storageSize
    local y = (col % 2 == 0) and row + 1 or (storageSize - row)
    local x = col + 1

    local posX = storageX + (x - 1) * cellW
    local posY = innerY + 1 + (storageSize - y)

    local crop = db.getStorageSlot(slot)
    gpu.setForeground(getCropColor(crop))
    gpu.set(posX, posY, string.format("%02d", slot))
    gpu.setForeground(uiColors.foreground)

    tabButtons[posY] = tabButtons[posY] or {}
    tabButtons[posY][posX] = {
      slot = slot,
      type = "storage",
    }
  end
end

local function drawFarmSlotInfo(cell)
  if not cell or not cell.slot or not cell.type then return end

  db.setSystemData('farmSelectedSlot', cell)
  local crop
  if cell.type == 'working' then
    crop = db.getFarmSlot(cell.slot)
  elseif cell.type == 'storage' then
    crop = db.getStorageSlot(cell.slot)
  end

  local workingSize = config.workingFarmSize
  local storageSize = config.storageFarmSize
  local gridH = math.max(workingSize, storageSize)

  local frameInfoX = menuPX + 4
  local frameInfoY = gridH + 6
  local col1X = frameInfoX + 1
  local col2X = frameInfoX + 20
  local col3X = frameInfoX + 38

  gpu.fill(frameInfoX, frameInfoY, screenWidth - menuPX - 6, 4, " ")

  if not crop then
    gpu.setForeground(uiColors.red)
    gpu.set(frameInfoX, frameInfoY, "Slot uninitialized. Execute system process and retry.")
    gpu.setForeground(uiColors.foreground)
    return
  end

  gpu.setForeground(uiColors.foreground)

  if crop.isCrop then
    if crop.name == 'emptyCrop' then
      gpu.set(col1X, frameInfoY, "Name: emptyCrop")
      gpu.set(col1X, frameInfoY + 1, "Farm: " .. cell.type)
      gpu.set(col1X, frameInfoY + 2, "Slot: " .. tostring(cell.slot))
      gpu.set(col1X, frameInfoY + 3, "Crossing base: " .. tostring(crop.crossingbase == 1))
    elseif crop.name == 'air' then
      gpu.set(col1X, frameInfoY, "Name: air")
      gpu.set(col1X, frameInfoY + 1, "Farm: " .. cell.type)
      gpu.set(col1X, frameInfoY + 2, "Slot: " .. tostring(cell.slot))
    elseif crop.name == 'weed' or crop.name == 'Grass' then
      gpu.set(col1X, frameInfoY, "Weed detected: " .. crop.name)
    else
      gpu.set(col1X, frameInfoY, "Name: " .. crop.name)
      gpu.set(col1X, frameInfoY + 1, "Farm: " .. cell.type)
      gpu.set(col1X, frameInfoY + 2, "Slot: " .. tostring(cell.slot))
      gpu.set(col1X, frameInfoY + 3, "Tier: " .. tostring(crop.tier))

      gpu.set(col2X, frameInfoY + 1, "Gain: " .. tostring(crop.ga))
      gpu.set(col2X, frameInfoY + 2, "Growth: " .. tostring(crop.gr))
      gpu.set(col2X, frameInfoY + 3, "Resistance: " .. tostring(crop.re))

      gpu.set(col3X, frameInfoY + 1, "Nutrients: " .. tostring(crop.nutrients))
      gpu.set(col3X, frameInfoY + 2, "Water: " .. tostring(crop.water))
      gpu.set(col3X, frameInfoY + 3, "WeedEx: " .. tostring(crop.weedex))
    end
  else
    gpu.set(col1X, frameInfoY, "Name: " .. (crop.name or "Unknown"))
    gpu.set(col1X, frameInfoY + 1, "Farm: " .. cell.type)
    gpu.set(col1X, frameInfoY + 2, "Slot: " .. tostring(cell.slot))
  end
end

local function drawAdditional(x, y)
  local stickCount = db.getSystemData('cropSticksCount') or 0

  if stickCount == 0 then
    gpu.setForeground(uiColors.foreground)
  elseif stickCount <= 64 * 10 then
    gpu.setForeground(uiColors.red)
  elseif stickCount <= 64 * 30 then
    gpu.setForeground(uiColors.yellow)
  else
    gpu.setForeground(uiColors.foreground)
  end

  gpu.set(x, y, string.format("Crop Sticks: %d", stickCount))
  gpu.setForeground(uiColors.foreground)


  local trashOrChestCount = db.getSystemData('trashOrChestCount') or 0

  if trashOrChestCount >= 90 then
    gpu.setForeground(uiColors.red)
  elseif trashOrChestCount >= 60 then
    gpu.setForeground(uiColors.yellow)
  else
    gpu.setForeground(uiColors.foreground)
  end

  gpu.set(x, y + 1, string.format("Trash/Chest: %d%%", trashOrChestCount))
  gpu.setForeground(uiColors.foreground)
end

local function drawFarm(refresh)
  local workingSize = config.workingFarmSize
  local storageSize = config.storageFarmSize
  local gridHeight = math.max(workingSize, storageSize)
  local paddingY = 2

  local frameX = menuPX + 3
  local frameY = 2
  local frameW = screenWidth - menuPX - 4
  local frameH = gridHeight + paddingY + 1

  local infoFrameY = frameY + frameH
  local infoFrameH = 6

  local legendX = frameX
  local legendY = infoFrameY + infoFrameH

  local additionalX = legendX + 27
  local additionalY = legendY
  local additionalW = (screenWidth - menuPX - 4) - 27
  local additionalH = 5

  if refresh then
    drawFarmGrid()

    local selectedSlot = db.getSystemData('farmSelectedSlot')
    if selectedSlot then
      drawFarmSlotInfo(selectedSlot)
    end
    gpu.fill(additionalX + 1, additionalY + 1, additionalW - 2, additionalH - 2, " ")
    drawAdditional(additionalX + 1, additionalY + 1)
    return
  end

  clearContentArea()
  gpu.setBackground(uiColors.background)
  gpu.setForeground(uiColors.foreground)

  drawFrame(frameX, frameY, frameW, frameH, " Farm Slots ")
  drawFrame(frameX, infoFrameY, frameW, infoFrameH, " Slot Overview ")
  gpu.set(frameX + 1, infoFrameY + 1, "Click a slot to view details.")

  drawFrame(additionalX, additionalY, additionalW, additionalH, " Additional ")

  drawFarmGrid()
  drawLegend(legendX, legendY)
  drawAdditional(additionalX + 1, additionalY + 1)
end

local function drawComponentStatus(label, key, x, y)
  local status = db.getSystemData(key)
  local color, sign

  if status == nil then
    color, sign = uiColors.yellow, '⋯'
  elseif status then
    color, sign = uiColors.green, '✔'
  else
    color, sign = uiColors.red, '✗'
  end

  gpu.set(x, y, label .. ": ")
  gpu.setForeground(color)
  gpu.set(x + #label + 2, y, sign)
  gpu.setForeground(uiColors.foreground)
end

local function drawSystem(refresh)
  local systemPaddingTop = 2
  local systemWidth = screenWidth - menuPX - 4
  local systemX = menuPX + 3


  local systemReady = db.getSystemData('systemReady')
  local systemEnabled = db.getSystemData('systemEnabled')
  local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')

  local btnOnOffColor = uiColors.lightgray
  local btnOnOffLabel = "  Start  "
  local btnOnOffAction = 'startSystem'

  local btnScanLabel = "   Scan   "
  local btnScanAction = "doSystemScan"
  local btnScanColor = uiColors.lightblue

  local btnScanWidth = 2 + #btnScanLabel
  local btnStartSystemWidth = 4 + #btnOnOffLabel

  local btnSpacing = 5
  local btnBaseY = 19

  if systemReady then
    btnOnOffColor = uiColors.green
    if systemEnabled then
      btnOnOffColor = uiColors.red
      btnOnOffLabel = "  Stop  "
      btnOnOffAction = 'stopSystem'

      btnScanColor = uiColors.lightgray
    end

    if flagNeedCleanUp then
      btnOnOffColor = uiColors.lightgray
      btnScanColor = uiColors.lightgray
    end
  end

  if refresh then
    drawButton(systemX, btnBaseY, btnScanWidth, btnScanColor, btnScanLabel, btnScanAction)

    drawButton(systemX + btnScanWidth, btnBaseY, btnStartSystemWidth, btnOnOffColor,
      btnOnOffLabel, btnOnOffAction)

    return
  end

  clearContentArea()

  local function drawComponents(title, components, height)
    drawFrame(systemX, systemPaddingTop, systemWidth, height, " " .. title .. " ")

    for i, comp in ipairs(components) do
      local column = (i % 2 == 0) and 2 or 1
      local row = math.ceil(i / 2)
      local colX = (column == 1) and (systemX + 1) or math.floor((screenWidth + menuPX) / 2)
      local y = systemPaddingTop + row
      drawComponentStatus(comp.label, comp.key, colX, y)
    end

    systemPaddingTop = systemPaddingTop + height
  end

  drawComponents("Robot", {
    { label = "Linked card",          key = "linkedCard" },
    { label = "Redstone card",        key = "redstoneCard" },
    { label = "Inventory upgrade",    key = "inventoryUpgrade" },
    { label = "Inventory controller", key = "inventoryController" },
    { label = "Weeding Trowel",       key = "weedingTrowel" },
    { label = "Transvector Binder",   key = "transvectorBinder" },
  }, 5)

  drawComponents("Farm", {
    { label = "Farmland",       key = "farmLand" },
    { label = "Grid 6x6",       key = "farmGrid" },
    { label = "Water source",   key = "farmWater" },
    { label = "Blank Farmland", key = "blankFarmland" },
  }, 4)

  drawComponents("Storage", {
    { label = "Farmland",     key = "storageLand" },
    { label = "Grid 9x9",     key = "storageGrid" },
    { label = "Water source", key = "storageWater" },
  }, 4)

  drawComponents("Blocks", {
    { label = "Cropstick chest",        key = "IWCropChest" },
    { label = "Charger",                key = "IWCharger" },
    { label = "Trash/Chest",            key = "IWTrashOrChest" },
    { label = "Transvector Dislocator", key = "transvectorDislocator" },
  }, 4)

  drawButton(systemX, btnBaseY, btnScanWidth, btnScanColor,
    btnScanLabel, btnScanAction)

  drawButton(systemX + btnScanWidth, btnBaseY, btnStartSystemWidth, btnOnOffColor,
    btnOnOffLabel, btnOnOffAction)

  local buttonsTotalWidth = btnScanWidth + btnStartSystemWidth + btnSpacing
  local modeFrameX = systemX + buttonsTotalWidth
  local modeFrameWidth = systemWidth - buttonsTotalWidth

  local currentMode = db.getSystemData('currentMode')
  local currentModeName
  local curentSubMode
  local curentSubModeName
  if currentMode == 1 then
    curentSubMode = db.getSystemData('currentSubMode')
    for i, subMode in ipairs(subModeTable) do
      if subMode.id == curentSubMode then
        curentSubModeName = subMode.name
      end
    end
  end

  for i, mode in ipairs(modeTable) do
    if mode.id == currentMode then
      currentModeName = mode.name
    end
  end

  drawFrame(modeFrameX, systemPaddingTop, modeFrameWidth, 4, " Mode ")

  if not currentMode then
    drawComponentStatus("Mode", 'currentMode', modeFrameX + 1, systemPaddingTop + 1)
    return
  end

  gpu.set(modeFrameX + 1, systemPaddingTop + 1, "Mode : " .. currentModeName)
  if curentSubMode then
    gpu.set(modeFrameX + 1, systemPaddingTop + 2, "SubMode : " .. curentSubModeName)
  end
end

local function drawSettings(refresh)
  if refresh then
    return
  end

  clearContentArea()

  local systemX = menuPX + 4
  local cursor = 3

  if db.getSystemData('systemEnabled') then
    gpu.setForeground(uiColors.yellow)
    gpu.set(systemX, cursor, 'Stop the system before making changes.')
    gpu.setForeground(uiColors.foreground)
    cursor = cursor + 2
  end

  local currentMode = db.getSystemData('currentMode')
  local currentModeName;
  for i, mode in ipairs(modeTable) do
    if mode.id == currentMode then
      currentModeName = mode.name
    end
  end

  drawClickedText(systemX, cursor, 'Mode', currentModeName, 'changeMode')
  cursor = cursor + 1
  gpu.set(systemX, cursor, modeDescriptions[currentModeName])
  cursor = cursor + 2

  if currentModeName == 'autoTier' then
    local currentSubMode = db.getSystemData('currentSubMode')
    local currentSubName;
    for i, subMode in ipairs(subModeTable) do
      if subMode.id == currentSubMode then
        currentSubName = subMode.name
      end
    end

    drawClickedText(systemX, cursor, 'subMode', currentSubName, 'changeSubMode')
    cursor = cursor + 1

    local subModeDes = subModeDescriptions[currentSubName]
    if type(subModeDes) == "string" then
      gpu.set(systemX, cursor, subModeDescriptions[currentSubName])
      cursor = cursor + 2
    elseif type(subModeDes) == "table" then
      for i, line in ipairs(subModeDes) do
        gpu.set(systemX, cursor, line)
        cursor = cursor + 1
      end
      cursor = cursor + 1
    end
  elseif currentModeName == 'autoStat' then
    local currentGrowth = db.getSystemData('systemGrowth')
    local currentGain = db.getSystemData('systemGain')
    local currentResistance = db.getSystemData('systemResistance')
    drawStatControl("Growth", currentGrowth, systemX, cursor)
    cursor = cursor + 1
    drawStatControl("Gain", currentGain, systemX, cursor)
    cursor = cursor + 1
    drawStatControl("Resistance", currentResistance, systemX, cursor)
    cursor = cursor + 2
  end

  if currentModeName ~= 'autoTier' then
    local targetCrop = db.getSystemData('systemTargetCrop') or 'click to scan target crop'

    drawClickedText(systemX, cursor, 'targetCrop', targetCrop, 'scanTargetCrop')
    cursor = cursor + 1

    local descriptions = {
      autoSpread = "Clones selected crop into storage.",
      autoStat   = "Improves and stores selected crop once target stats are met."
    }

    local desc = descriptions[currentModeName] or "Target crop to process in this mode."
    gpu.set(systemX, cursor, desc)
    cursor = cursor + 1
    gpu.set(systemX, cursor, "Taken from slot 01 on the work farm.")
    cursor = cursor + 2
  end

  local currentLogsLevel = db.getSystemData('currentLogsLevel') or 1
  local currentLogsName;
  for i, log in ipairs(logLevels) do
    if log.id == currentLogsLevel then
      currentLogsName = log.name
    end
  end

  drawClickedText(systemX, cursor, 'Logs level', currentLogsName, 'changeLogsLevel')
  cursor = cursor + 1

  for i, line in ipairs(logLevelsDescriptions[currentLogsName]) do
    gpu.set(systemX, cursor, line)
    cursor = cursor + 1
  end
  cursor = cursor + 2
end

local function drawLogs(refresh)
  if refresh and db.getSystemData('logsOffset') ~= 0 then return end

  clearContentArea()

  local logsX = menuPX + 4
  local logsY = 2
  local logs = db.getLogs()
  --local logsOffset = db.getSystemData('logsOffset') or 0
  local maxLineLen = screenWidth - logsX - 7

  local visibleLines = screenHeight - logsY - 2
  db.setSystemData("visibleLines", visibleLines)

  drawFrame(logsX - 1, logsY, screenWidth - logsX, screenHeight - logsY, " Logs ")

  gpu.set(screenWidth - 3, 3, '⇧')
  gpu.set(screenWidth - 3, screenHeight - 2, '⇩')

  registeterButton({
    x1 = screenWidth - 3,
    x2 = screenWidth - 3,
    y1 = 3,
    y2 = 3,
    action = 'logsUp'
  })
  registeterButton({
    x1 = screenWidth - 3,
    x2 = screenWidth - 3,
    y1 = screenHeight - 2,
    y2 = screenHeight - 2,
    action = 'logsDown'
  })

  local y = logsY + 1
  local logOffset = db.getSystemData('logsOffset') or 0

  for logIndex = #logs - logOffset, 1, -1 do
    local entry = logs[logIndex]
    if entry then
      local rawLog = string.format("[%s] %s", entry.date, entry.log)

      local segments = {}
      for part in rawLog:gmatch("([^;]+)") do
        part = part:gsub("^%s+", "")
        while #part > maxLineLen do
          table.insert(segments, string.sub(part, 1, maxLineLen))
          part = string.sub(part, maxLineLen + 1)
        end
        if #part > 0 then table.insert(segments, part) end
      end

      for i = 1, #segments do
        local prefix = i > 1 and '  ' or ''
        gpu.set(logsX, y, prefix .. segments[i])
        y = y + 1
        if y > screenHeight - 2 then return end
      end
    end
  end
end

local function logsUp()
  local offset = db.getSystemData('logsOffset') or 0
  if offset > 0 then
    offset = offset - 2
    if offset < 0 then
      offset = 0
    end
    db.setSystemData('logsOffset', offset)
    drawLogs()
  end
end

local function logsDown()
  local logs = db.getCountLogs()
  local offset = db.getSystemData('logsOffset') or 0
  if offset < logs then
    offset = offset + 2
    if offset > logs then
      offset = logs
    end
    db.setSystemData('logsOffset', offset)
    drawLogs()
  end
end

local function drawTransplant()
  local menuX = menuPX + 4
  local halfScreen = math.floor((screenWidth - menuX) / 2)
  local rightX = halfScreen + menuX

  local fromX = menuX + 1
  local toX = rightX + 2
  local fromFrame = menuX - 1
  local toFrame = rightX

  local btnTransplanteLabel = " Transplant "
  local btnTransplanteAction = "doTransplante"
  local btnTransplanteColor = uiColors.lightblue
  local btnTransplanteWidth = 2 + #btnTransplanteLabel

  local currentInAction = db.getSystemData('currentInAction')
  if currentInAction then
    btnTransplanteColor = uiColors.lightgray
  end

  local cursor = 3

  local transplateFromFarm = db.getSystemData('transplateFromFarm')
  if not transplateFromFarm then
    transplateFromFarm = 2
    db.setSystemData('transplateFromFarm', 2)
  end

  local transplateToFarm = db.getSystemData('transplateToFarm')
  if not transplateToFarm then
    transplateToFarm = 1
    db.setSystemData('transplateToFarm', 1)
  end

  local transplateFromFarmName, transplateToFarmName

  local transplateFromSlot = db.getSystemData('transplateFromSlot')
  if not transplateFromSlot then
    transplateFromSlot = 1
    db.setSystemData('transplateFromSlot', 1)
  end

  local transplateToSlot = db.getSystemData('transplateToSlot') or 1
  if not transplateToSlot then
    transplateToSlot = 1
    db.setSystemData('transplateToSlot', 1)
  end

  for i, farm in ipairs(actionsTranplate) do
    if farm.id == transplateFromFarm then
      transplateFromFarmName = farm.name
    end
    if farm.id == transplateToFarm then
      transplateToFarmName = farm.name
    end
  end

  drawClickedText(menuX, cursor, 'Back', nil, 'closeTransplant')

  drawButton(screenWidth - btnTransplanteWidth - 1, cursor - 1, btnTransplanteWidth, btnTransplanteColor,
    btnTransplanteLabel, btnTransplanteAction)

  cursor = cursor + 3


  drawFrame(fromFrame, cursor, halfScreen - 1, screenHeight - 6, " From ")
  drawFrame(toFrame, cursor, halfScreen, screenHeight - 6, " To ")

  cursor = cursor + 2

  local centerFromX = fromFrame + math.floor((halfScreen - 1 - #transplateFromFarmName - 3) / 2)
  local centerToX = toFrame + math.floor((halfScreen - #transplateToFarmName - 2) / 2)

  drawClickedText(centerFromX, cursor, transplateFromFarmName, nil, 'transplateFromFarm')
  drawClickedText(centerToX, cursor, transplateToFarmName, nil, 'transplateToFarm')

  cursor = cursor + 2

  local centerFromSlotX = fromFrame + math.floor((halfScreen - 1 - #"Slot:") / 2)
  local centerToSlotX = toFrame + math.floor((halfScreen - #"Slot:" + 1) / 2)

  gpu.set(centerFromSlotX, cursor, "Slot:")
  gpu.set(centerToSlotX, cursor, "Slot:")

  cursor = cursor + 2

  local centerFromSlotControlX = fromFrame + math.floor((halfScreen - 18) / 2)
  local centerToSlotControX = toFrame + math.floor((halfScreen - 16) / 2)
  drawSlotControl(transplateFromSlot, centerFromSlotControlX, cursor, 'from', transplateFromFarm)
  drawSlotControl(transplateToSlot, centerToSlotControX, cursor, 'to', transplateToFarm)

  cursor = cursor + 4

  local cropFrom
  if transplateFromFarm == 1 then
    cropFrom = db.getFarmSlot(transplateFromSlot)
  elseif transplateFromFarm == 2 then
    cropFrom = db.getStorageSlot(transplateFromSlot)
  end

  local cropTo
  if transplateToFarm == 1 then
    cropTo = db.getFarmSlot(transplateToSlot)
  elseif transplateToFarm == 2 then
    cropTo = db.getStorageSlot(transplateToSlot)
  end

  if not cropFrom then
    gpu.setForeground(uiColors.red)
    gpu.set(fromX, cursor, "Slot uninitialized.")
    gpu.set(fromX, cursor + 1, "Scan farm.")
    gpu.setForeground(uiColors.foreground)
  else
    local cropName = cropFrom.name or "Unknown"
    if cropFrom.isCrop then
      if #cropName > 20 then
        cropName = string.sub(cropName, 1, 17) .. "..."
      end
      gpu.set(fromX, cursor, "Name: " .. cropName)
      if cropFrom.name == "emptyCrop" then
        gpu.set(fromX, cursor + 1, "Crossing base: " .. tostring(cropFrom.crossingbase == 1))
      elseif cropFrom.name == "air" or cropFrom.name == "weed" or cropFrom.name == "Grass" then
      else
        gpu.set(fromX, cursor + 1, "Tier: " .. tostring(cropFrom.tier))
        gpu.set(fromX, cursor + 3, "Gain: " .. tostring(cropFrom.ga))
        gpu.set(fromX, cursor + 4, "Growth: " .. tostring(cropFrom.gr))
        gpu.set(fromX, cursor + 5, "Resistance: " .. tostring(cropFrom.re))
      end
    else
      gpu.set(fromX, cursor, "Name: " .. cropName)
    end
  end


  if not cropTo then
    gpu.setForeground(uiColors.red)
    gpu.set(toX, cursor, "Slot uninitialized.")
    gpu.set(toX, cursor + 1, "Scan farm.")
    gpu.setForeground(uiColors.foreground)
  else
    local cropName = cropTo.name or "Unknown"
    if cropTo.isCrop then
      if #cropName > 20 then
        cropName = string.sub(cropName, 1, 17) .. "..."
      end
      gpu.set(toX, cursor, "Name: " .. cropName)
      if cropTo.name == "emptyCrop" then
        gpu.set(toX, cursor + 1, "Crossing base: " .. tostring(cropTo.crossingbase == 1))
      elseif cropTo.name == "air" or cropTo.name == "weed" or cropTo.name == "Grass" then
      else
        gpu.set(toX, cursor + 1, "Tier: " .. tostring(cropTo.tier))
        gpu.set(toX, cursor + 3, "Gain: " .. tostring(cropTo.ga))
        gpu.set(toX, cursor + 4, "Growth: " .. tostring(cropTo.gr))
        gpu.set(toX, cursor + 5, "Resistance: " .. tostring(cropTo.re))
      end
    else
      gpu.set(toX, cursor, "Name: " .. cropName)
    end
  end
end

local function drawActions()
  clearContentArea()
  local currentInTransplant = db.getSystemData('currentInTransplant') or false
  if currentInTransplant then
    drawTransplant()
    return
  end

  local systemX = menuPX + 4
  local cursor = 3
  local systemEnabled = db.getSystemData('systemEnabled')
  local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
  local currentInAction = db.getSystemData('currentInAction') or false

  if systemEnabled then
    gpu.setForeground(uiColors.yellow)
    gpu.set(systemX, cursor, 'Stop the system before performing any actions.')
    gpu.setForeground(uiColors.foreground)
    cursor = cursor + 3
  end

  if flagNeedCleanUp or currentInAction then
    gpu.setForeground(uiColors.lightgray)
  end
  drawClickedText(systemX, cursor, 'Transplant', nil, 'openTransplant')
  cursor = cursor + 1
  gpu.set(systemX, cursor, 'Move a crop from one slot to another')
  cursor = cursor + 3

  if flagNeedCleanUp or currentInAction then
    gpu.setForeground(uiColors.lightgray)
  end
  drawClickedText(systemX, cursor, 'CleanUp', nil, 'cleanUpSystem')
  cursor = cursor + 1

  gpu.set(systemX, cursor, 'Remove child crops and all cropsticks (farm and storage)')
  cursor = cursor + 3

  if flagNeedCleanUp or currentInAction then
    gpu.setForeground(uiColors.lightgray)
  end
  drawClickedText(systemX, cursor, 'Scan farm', nil, 'doScanWorking')
  cursor = cursor + 1
  gpu.set(systemX, cursor, 'Manually rescan the working farm')
  cursor = cursor + 3

  if flagNeedCleanUp or currentInAction then
    gpu.setForeground(uiColors.lightgray)
  end
  drawClickedText(systemX, cursor, 'Scan storage', nil, 'doScanStorage')
  cursor = cursor + 1
  gpu.set(systemX, cursor, 'Manually rescan the storage farm')
  cursor = cursor + 3
end

local function renderContent(refresh)
  local selectedMenuItem = db.getSystemData('selectedMenuItem')
  if refresh == nil then
    refresh = false
  end

  if selectedMenuItem == "farm" then
    drawFarm(refresh)
  elseif selectedMenuItem == "system" then
    drawSystem(refresh)
  elseif selectedMenuItem == "actions" then
    drawActions()
  elseif selectedMenuItem == "settings" and not refresh then
    drawSettings()
  elseif selectedMenuItem == "logs" then
    drawLogs(refresh)
  end
end

local function drawIWStep()
  clearFullArea()
  local stepId = db.getSystemData('IWStep') or 1
  local step = installationSteps[stepId]
  drawIWHeader(step)
  drawIWMap(step)
  drawIWContent(step)
  drawIWFooter(step)
end

local function nextIWStep()
  local currentStep = db.getSystemData('IWStep')
  local nextIndex = currentStep + 1
  if nextIndex <= #installationSteps then
    db.setSystemData('IWStep', nextIndex)
    drawIWStep()
  end
end

local function prevIWStep()
  local currentStep = db.getSystemData('IWStep')
  local prevIndex = currentStep - 1
  if prevIndex >= 1 then
    db.setSystemData('IWStep', prevIndex)
    drawIWStep()
  end
end

local function exitIWStep()
  sys.doSystemScan()
  db.setSystemData('selectedMenuItem', 'system')
  fillScreen()
  renderContent()
end

local function isPointInBounds(x, y, btn)
  return x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2
end

local function handleBodyMouseClick(btn)
  if btn.action == 'doSystemScan' then
    local systemEnabled = db.getSystemData('systemEnabled')
    local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
    if not systemEnabled and not flagNeedCleanUp then
      drawButton(btn.x1, btn.y1, 2 + #' Scanning ', uiColors.lightgray, ' Scanning ')
      sys.doSystemScan()
      drawSystem()
    end
  elseif btn.action == 'startSystem' then
    local systemReady = db.getSystemData('systemReady')
    local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
    if systemReady and not flagNeedCleanUp then
      db.setSystemData('systemEnabled', true)
      sys.scanTargetCrop()
    end

    drawSystem()
  elseif btn.action == 'stopSystem' then
    db.setSystemData('systemEnabled', false)
    drawSystem()
  elseif btn.action == 'cleanUpSystem' then
    local systemReady = db.getSystemData('systemReady')
    local systemEnabled = db.getSystemData('systemEnabled')
    local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
    local currentInTransplant = db.getSystemData('currentInTransplant') or false

    if systemReady and not systemEnabled and not flagNeedCleanUp and not currentInTransplant then
      db.setSystemData('flagNeedCleanUp', true)
      db.setLogs('Actions - Do system cleanUp')
      drawActions()
    end
  elseif btn.action == 'doScanStorage' or btn.action == 'doScanWorking' then
    local systemReady = db.getSystemData('systemReady')
    local systemEnabled = db.getSystemData('systemEnabled')
    local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
    local currentInAction = db.getSystemData('currentInAction') or false
    local currentInTransplant = db.getSystemData('currentInTransplant') or false

    if not systemReady or systemEnabled or flagNeedCleanUp or currentInAction or currentInTransplant then
      return
    end
    db.setSystemData('currentInAction', true)
    drawActions()
    os.sleep(0.5)

    if btn.action == 'doScanWorking' then
      sys.scanFarm()
      db.setLogs('Actions - Do scan farm "Working"')
    elseif btn.action == 'doScanStorage' then
      sys.scanStorage()
      db.setLogs('Actions - Do scan farm "Storage"')
    end

    db.setSystemData('currentInAction', false)
    drawActions()
  elseif btn.action == 'openTransplant' then
    local systemReady = db.getSystemData('systemReady')
    local systemEnabled = db.getSystemData('systemEnabled')
    local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
    local currentInAction = db.getSystemData('currentInAction') or false
    local currentInTransplant = db.getSystemData('currentInTransplant') or false
    if not systemReady or systemEnabled or flagNeedCleanUp or currentInAction or currentInTransplant then
      return
    end

    db.setSystemData('currentInTransplant', true)
    drawActions()
  elseif btn.action == 'closeTransplant' then
    db.setSystemData('currentInTransplant', false)
    drawActions()
  elseif btn.action == 'doTransplante' then
    local systemReady = db.getSystemData('systemReady')
    local systemEnabled = db.getSystemData('systemEnabled')
    local flagNeedCleanUp = db.getSystemData('flagNeedCleanUp')
    local currentInAction = db.getSystemData('currentInAction') or false
    if not systemReady or systemEnabled or flagNeedCleanUp or currentInAction then
      return
    end

    db.setSystemData('currentInAction', true)
    sys.doTransplante()
    db.setSystemData('currentInAction', false)

    db.setSystemData('logsOffset', 0)
    db.setSystemData('selectedMenuItem', 'logs')
    fillScreen()
    drawLogs()
  elseif btn.action == 'changeMode' then
    if db.getSystemData('systemEnabled') then
      return
    end
    local currentMode = db.getSystemData('currentMode')
    for i, mode in ipairs(modeTable) do
      if mode.id == currentMode then
        local nextIndex = (i % #modeTable) + 1
        local nextMode = modeTable[nextIndex].id
        db.setSystemData('currentMode', nextMode)
        drawSettings()
        break
      end
    end
  elseif btn.action == 'changeLogsLevel' then
    if db.getSystemData('systemEnabled') then
      return
    end
    local currentLogsLevel = db.getSystemData('currentLogsLevel')

    for i, log in ipairs(logLevels) do
      if log.id == currentLogsLevel then
        local nextIndex = (i % #logLevels) + 1
        local nextLog = logLevels[nextIndex].id
        db.setSystemData('currentLogsLevel', nextLog)
        drawSettings()
        break
      end
    end
  elseif btn.action == 'changeSubMode' then
    if db.getSystemData('systemEnabled') then
      return
    end
    local currentSubMode = db.getSystemData('currentSubMode')
    for i, mode in ipairs(subModeTable) do
      if mode.id == currentSubMode then
        local nextSubIndex = (i % #subModeTable) + 1
        local nextSubMode = subModeTable[nextSubIndex].id
        db.setSystemData('currentSubMode', nextSubMode)
        drawSettings()
        break
      end
    end
  elseif btn.action == 'minusStat' or btn.action == 'plusStat' then
    if db.getSystemData('systemEnabled') then
      return
    end
    local statKey = 'system' .. btn.subAction
    local currentStatValue = db.getSystemData(statKey)
    local change = (btn.action == 'plusStat') and 1 or -1
    local nextStatValue = currentStatValue + change

    local statLimits = {
      Growth = { min = 0, max = 23 },
      Gain = { min = 0, max = 31 },
      Resistance = { min = 0, max = 2 },
    }

    local limit = statLimits[btn.subAction]
    if limit and nextStatValue >= limit.min and nextStatValue <= limit.max then
      db.setSystemData(statKey, nextStatValue)
    end

    drawSettings()
  elseif btn.action == 'minusSlot' or btn.action == 'plusSlot' then
    local transplateFor = btn.transplateFor or 'from'
    local key = transplateFor == 'from' and 'transplateFromSlot' or 'transplateToSlot'
    local current = db.getSystemData(key) or 1
    local slotFarm = btn.slotFarm or 1
    local workingSize = config.workingFarmSize
    local storageSize = config.storageFarmSize
    local maxSlot = 36
    if slotFarm == 1 then
      maxSlot = workingSize * workingSize
    elseif slotFarm == 2 then
      maxSlot = storageSize * storageSize
    end

    if btn.action == 'minusSlot' then
      local count = btn.count or 1
      current = math.max(1, current - count)
      db.setSystemData(key, current)
      drawActions()
    elseif btn.action == 'plusSlot' then
      local count = btn.count or 1
      current = math.min(maxSlot, current + count)
      db.setSystemData(key, current)
      drawActions()
    end
  elseif btn.action == 'transplateFromFarm' or btn.action == 'transplateToFarm' then
    local transplateFarm = db.getSystemData(btn.action)
    if btn.action == 'transplateFromFarm' then
      db.setSystemData('transplateFromSlot', 1)
    elseif btn.action == 'transplateToFarm' then
      db.setSystemData('transplateToSlot', 1)
    end

    for i, farm in ipairs(actionsTranplate) do
      if farm.id == transplateFarm then
        local nextIndex = (i % #actionsTranplate) + 1
        local nextFarm = actionsTranplate[nextIndex].id
        db.setSystemData(btn.action, nextFarm)
        break
      end
    end
    drawActions()
  elseif btn.action == 'scanTargetCrop' then
    if db.getSystemData('systemEnabled') then
      return
    end
    sys.scanTargetCrop()
    drawSettings()
  elseif btn.action == 'logsUp' then
    logsUp()
  elseif btn.action == 'logsDown' then
    logsDown()
  end
end

local function handleMouseClick(_, _, x, y)
  if x == 1 or x == screenWidth or y == 1 or y == screenHeight then return end

  local systemCreateOrder = db.getSystemData('systemCreateOrder') or false
  if systemCreateOrder then return end

  local selectedMenuItem = db.getSystemData('selectedMenuItem')

  if selectedMenuItem == 'IW' then
    for index, btn in ipairs(tabButtons) do
      if isPointInBounds(x, y, btn) and not btn.disabled then
        tabButtons[index].disabled = true
        if btn.action == 'scanIWSystem' then
          local checkText = ' Checking '
          local checkX = math.ceil((screenWidth - #checkText + 1) / 2)
          local checkY = screenHeight - 1

          gpu.setForeground(uiColors.lightgray)
          gpu.set(checkX, checkY, checkText)
          gpu.setForeground(uiColors.foreground)

          sys.doSystemScan()
          drawIWStep()
        elseif btn.action == 'nextIWStep' then
          nextIWStep()
        elseif btn.action == 'prevIWStep' then
          prevIWStep()
        elseif btn.action == 'exitIWStep' then
          exitIWStep()
        end
        break
      end
    end
  elseif x > 1 and x <= menuPX then
    for _, btn in ipairs(menuButtons) do
      if y >= btn.startY and y <= btn.endY then
        os.sleep(0.1)
        if selectedMenuItem ~= btn.tab then
          if btn.tab == 'logs' then
            db.setSystemData('logsOffset', 0)
          end
          db.setSystemData('selectedMenuItem', btn.tab)
          fillMenu()
          renderContent()
        end
        break
      end
    end
  elseif x > menuPX + 1 then
    if selectedMenuItem == "farm" and tabButtons[y] then
      local cell = tabButtons[y][x] or tabButtons[y][x - 1]
      if cell then
        drawFarmSlotInfo(cell)
      end
    elseif tabButtons then
      for index, btn in ipairs(tabButtons) do
        if isPointInBounds(x, y, btn) and not btn.disabled then
          tabButtons[index].disabled = true
          if btn.action then
            handleBodyMouseClick(btn)
          end
          break
        end
      end
    end
  end
end

local function UIloading(set)
  local text = "Loading.."
  local x = 2
  local y = screenHeight - 1

  if set then
    local padding = math.floor((menuPX - 1 - #text) / 2)
    gpu.set(x, y, string.rep(" ", padding) .. text)
  else
    gpu.set(x, y, string.rep(" ", menuPX - 1))
    renderContent(true)
  end
end

local function initUI()
  term.clear()
  gpu.setResolution(80, 25)
  gpu.setDepth(4)

  if not sys.doSystemScan(true) then
    db.setSystemData('selectedMenuItem', 'IW')
    drawIWStep()
  else
    db.setSystemData('selectedMenuItem', 'system')
    fillScreen()
    renderContent()
  end

  event.listen("touch", handleMouseClick)

  while true do
    os.sleep(0.1)
  end
end

return {
  initUI = initUI,
  UIloading = UIloading,
}
