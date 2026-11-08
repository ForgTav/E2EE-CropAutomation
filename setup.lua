-- Runs only on the separate OpenOS installation computer.
local Installer = {}
local repository = "ForgTav/E2EE-CropAutomation"
local files = {
  shared = {
    "app/shared/shared_link.lua",
    "app/shared/shared_link_store.lua",
    "platform/native/shared_native_runtime.lua",
    "platform/oc/shared_oc_modem.lua",
    "platform/oc/shared_oc_screen.lua",
  },
  station = {
    "app/station/station_app.lua",
    "app/station/station_catalog.lua",
    "app/station/station_control.lua",
    "app/station/station_genetics_math.lua",
    "app/station/station_inventory.lua",
    "app/station/station_link.lua",
    "app/station/station_observation.lua",
    "app/station/station_planner.lua",
    "app/station/station_planner_facts.lua",
    "app/station/station_planner_projection.lua",
    "app/station/station_production_rules.lua",
    "app/station/station_renderer.lua",
    "app/station/station_seed_nbt.lua",
    "app/station/station_species_math.lua",
    "app/station/station_startup.lua",
    "app/station/station_state.lua",
    "app/station/station_strategy_genetics.lua",
    "app/station/station_strategy_quantity.lua",
    "app/station/station_strategy_species.lua",
    "app/station/station_ui.lua",
    "platform/native/station_native_scheduler.lua",
    "platform/oc/station_oc_sensor.lua",
    "platform/oc/station_oc_transposer.lua",
    "station.lua",
  },
  robot = {
    "app/robot/robot_app.lua",
    "app/robot/robot_execute.lua",
    "app/robot/robot_io.lua",
    "app/robot/robot_hand.lua",
    "app/robot/robot_nav.lua",
    "app/robot/robot_ui.lua",
    "platform/oc/robot_oc_hardware.lua",
    "robot.lua",
  },
}

function Installer.install(volume, role, fetch, systemAddresses, checkTarget)
  local function guard()
    assert(not systemAddresses[volume.address], "SYSTEM_DISK_FORBIDDEN")
    checkTarget(volume.address)
  end
  guard()
  assert(files[role] and role ~= "shared", "INSTALL_ROLE_INVALID")
  assert(volume.isReadOnly() == false, "TARGET_READ_ONLY")
  local otherEntry = "/cropautomation/" .. (role == "station" and "robot" or "station") .. ".lua"
  local otherPresent, accessError = volume.exists(otherEntry)
  assert(otherPresent ~= nil and accessError == nil, accessError or "TARGET_ACCESS_FAILED")
  assert(not otherPresent, "HDD belongs to the other role; select its role or use another HDD")

  local function directory(path)
    guard()
    local present, reason = volume.exists(path)
    assert(present ~= nil and reason == nil, reason or "TARGET_ACCESS_FAILED")
    if present then
      local isDirectory, directoryError = volume.isDirectory(path)
      assert(isDirectory == true and directoryError == nil, directoryError or "TARGET_DIRECTORY_REQUIRED")
    else
      local parent = path:match("^(.+)/[^/]+$")
      if parent then directory(parent) end
      guard()
      local made, makeError = volume.makeDirectory(path)
      assert(made == true and makeError == nil, makeError or "TARGET_MKDIR_FAILED")
    end
  end
  local function copy(source, destination)
    local handle
    local function writeChunk(chunk)
      if not handle then
        directory(destination:match("^(.+)/[^/]+$") or "/")
        guard()
        local openError
        handle, openError = volume.open(destination, "w")
        assert(handle and openError == nil, openError or "TARGET_OPEN_FAILED")
      end
      local written, writeError = volume.write(handle, chunk)
      assert(written == true and writeError == nil, writeError or "TARGET_WRITE_FAILED")
    end
    local fetched, fetchError = pcall(fetch, source, writeChunk)
    local closed, closeResult, closeError
    if handle then closed, closeResult, closeError = pcall(volume.close, handle) end

    local reason
    if not fetched then
      reason = fetchError
    elseif not handle then
      reason = "DOWNLOAD_EMPTY"
    elseif not closed or closeResult == false or closeError ~= nil then
      reason = closeError or closeResult or "TARGET_CLOSE_FAILED"
    else
      return
    end
    error("INSTALL_FAILED: " .. destination .. ": " .. tostring(reason), 0)
  end
  for _, group in ipairs({ "shared", role }) do
    for _, source in ipairs(files[group]) do copy(source, "/cropautomation/" .. source) end
  end
  copy("platform/native/shared_native_boot.lua", "/init.lua")
  return true
end

function Installer.main(branch)
  local component, computer = require("component"), require("computer")
  local filesystem = require("filesystem")
  local internet = assert(component.internet, "Internet Card required on installation computer")
  local function fetchUrl(url, writeChunk)
    local headers = { ["User-Agent"] = "CropAutomation-Installer" }
    local request = assert(internet.request(url, nil, headers))
    local called, fetchError = pcall(function()
      local deadline = computer.uptime() + 30
      while true do
        local connected, reason = request.finishConnect()
        assert(reason == nil, reason)
        if connected then break end
        assert(computer.uptime() < deadline, "HTTP_CONNECT_TIMEOUT"); os.sleep(0.05)
      end
      local status = request.response()
      assert(status == 200, "HTTP_STATUS: " .. tostring(status))
      deadline = computer.uptime() + 30
      while true do
        local chunk, reason = request.read(2048)
        assert(reason == nil, reason)
        if chunk == nil then break end
        if #chunk > 0 then
          writeChunk(chunk)
          deadline = computer.uptime() + 30
        else
          assert(computer.uptime() < deadline, "HTTP_READ_TIMEOUT"); os.sleep(0.05)
        end
      end
    end)
    local closed, closeResult, closeError = pcall(request.close)
    if not called then error(fetchError, 0) end
    assert(closed and closeResult ~= false and closeError == nil, "HTTP_CLOSE_FAILED")
  end
  print("CropAutomation")
  print("1 - Station\n2 - Robot"); io.write("> ")
  local choice = io.read()
  local role = choice == "1" and "station" or choice == "2" and "robot"
  if not role then return false end
  local rootVolume = assert(filesystem.get("/"), "SYSTEM_FILESYSTEM_REQUIRED")
  local systemAddresses = { [assert(rootVolume.address)] = true }
  local bootAddress = computer.getBootAddress()
  if bootAddress then systemAddresses[bootAddress] = true end
  local temporaryAddress = computer.tmpAddress()
  if temporaryAddress then systemAddresses[temporaryAddress] = true end
  local targets = {}
  for address in component.list("filesystem", true) do
    if not systemAddresses[address] then
      local volume = assert(component.proxy(address))
      if volume.isReadOnly() == false then
        targets[#targets + 1] = volume
        print(#targets .. " - " .. address .. " / " .. tostring(volume.getLabel() or "unlabelled"))
      end
    end
  end
  if #targets == 0 then
    print("No writable target HDD found."); return false
  end
  io.write("Target HDD number: ")
  local target = targets[tonumber(io.read())]
  if not target then return false end
  print("Install " .. role .. " on " .. target.address)
  io.write("Program files on the selected disk will be overwritten. Continue? [y/N] ")
  if (io.read() or ""):lower() ~= "y" then return false end
  local baseUrl = "https://raw.githubusercontent.com/" .. repository .. "/" .. (branch or "main") .. "/"
  Installer.install(target, role, function(source, writeChunk)
    print("Download " .. source)
    fetchUrl(baseUrl .. source, writeChunk)
  end, systemAddresses, function(address)
    assert(address == target.address and component.type(address) == "filesystem" and
      filesystem.get("/").address == rootVolume.address, "TARGET_OR_SYSTEM_CHANGED")
  end)
  print("Installed. Move the HDD to " .. role)
  return true
end

if ... == "setup" then return Installer end
return Installer.main(...)
