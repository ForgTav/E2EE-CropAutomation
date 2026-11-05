local Catalog = require("station_catalog")
local Quantity = require("station_production_rules")

local function key(facts)
  if not facts then return nil end
  return facts.key or (facts.owner and facts.id and facts.owner .. ":" .. facts.id)
end

local function adjacent(cell, direction)
  if direction == 1 and cell > 6 then return cell - 6 end
  if direction == 2 and (cell - 1) % 6 > 0 then return cell - 1 end
  if direction == 3 and (cell - 1) % 6 < 5 then return cell + 1 end
  if direction == 4 and cell <= 30 then return cell + 6 end
end
local function neighbors(cell, visit)
  for direction = 1, 4 do
    local neighbor = adjacent(cell, direction)
    if neighbor then visit(neighbor) end
  end
end

local function known(facts)
  return facts ~= nil and facts.scanOk == true and facts.kind ~= "UNREADABLE"
end

local function empty(facts)
  return known(facts) and facts.kind == "AIR"
end

local function sticks(facts)
  return known(facts) and facts.tile == true and
      (facts.kind == "SINGLE" or facts.kind == "DOUBLE")
end

local function doubleSite(facts)
  return known(facts) and (facts.kind == "SINGLE" or empty(facts))
end

local function crop(facts)
  local cropKey = key(facts)
  return known(facts) and facts.kind == "PLANT" and cropKey and Catalog.get(cropKey)
      and type(facts.g) == "number" and type(facts.ga) == "number"
      and type(facts.r) == "number" and not Catalog.isDangerous(cropKey, facts.g)
end
local function plant(facts) return crop(facts) and Catalog.canProceed(key(facts)) end

local function mature(facts)
  local cropKey = key(facts)
  return plant(facts) and type(facts.size) == "number"
      and facts.size >= Catalog.crossFrom(cropKey)
end

local function descriptor(facts)
  local cropKey = key(facts)
  if not cropKey then return nil end
  return {
    key = cropKey,
    itemKind = facts.itemKind,
    g = facts.g,
    ga = facts.ga,
    r = facts.r,
    slot = facts.slot,
    size = facts.size
  }
end

local function geneticsMatch(first, second)
  return first and second and key(first) == key(second)
      and first.g == second.g and first.ga == second.ga and first.r == second.r
end

local function plantingGenes(facts, itemKind)
  local cropKey = key(facts)
  if not cropKey then return nil end
  itemKind = itemKind or facts.itemKind
  local g, ga, r = Quantity.plantGenes(facts, itemKind)
  if type(g) ~= "number" or type(ga) ~= "number" or type(r) ~= "number" then return nil end
  if g % 1 ~= 0 or ga % 1 ~= 0 or r % 1 ~= 0 or g < 0 or g > 31 or ga < 0 or ga > 31 or r < 0 or r > 31 then return nil end
  if itemKind and itemKind ~= "vanilla" and itemKind ~= "ic2" then return nil end
  if Catalog.isDangerous(cropKey, g) then return nil end
  return g, ga, r, cropKey
end

local function installation(facts, itemKind)
  local g, ga, r, cropKey = plantingGenes(facts, itemKind)
  if g == nil then return nil end
  local owner, id = cropKey:match("^([^:]+):(.+)$")
  return {
    kind = "PLANT",
    scanOk = true,
    tile = true,
    owner = owner,
    id = id,
    key = cropKey,
    g = g,
    ga = ga,
    r = r,
    size = 1,
    crossingBase = 0
  }
end

local function action(name, from, to, reason, step, purpose)
  return {
    kind = "ACTION",
    action = { name = name, from = from, to = to },
    reason = reason,
    step = step,
    purpose = purpose
  }
end

local function decision(kind, reason, need)
  return { kind = kind, reason = reason, need = need }
end

local function sameMaterial(expected, held)
  if not expected or not held or key(expected) ~= key(held) then return false end
  if expected.itemKind ~= held.itemKind then return false end
  if expected.itemKind == "vanilla" then return true end
  return geneticsMatch(expected, held)
end

local function candidates()
  local keys = {}
  for cropKey in Catalog.each() do keys[#keys + 1] = cropKey end
  table.sort(keys)
  return keys
end

local function copyObstacles(field, sourceCell, targetCell)
  local site = field[targetCell]
  if not known(site) then return nil, targetCell end
  if not (site.tile or empty(site)) then return nil end
  local obstacles = site.kind == "PLANT" and (1 << (targetCell - 1)) or 0
  for direction = 1, 4 do
    local neighbor = adjacent(targetCell, direction)
    if neighbor and neighbor ~= sourceCell then
      if not known(field[neighbor]) then
        return nil, neighbor
      elseif field[neighbor].tile then
        obstacles = obstacles | (1 << (neighbor - 1))
      end
    end
  end
  return obstacles
end

return {
  key = key,
  adjacent = adjacent,
  neighbors = neighbors,
  known = known,
  empty = empty,
  sticks = sticks,
  doubleSite = doubleSite,
  plant = plant,
  crop = crop,
  mature = mature,
  descriptor = descriptor,
  geneticsMatch = geneticsMatch,
  installation = installation,
  plantingGenes = plantingGenes,
  action = action,
  decision = decision,
  sameMaterial = sameMaterial,
  candidates = candidates,
  copyObstacles = copyObstacles,
}
