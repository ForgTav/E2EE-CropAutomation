local Catalog = {
  ["ic2:weed"] = { name = "Weed", tier = 0, chemistry = 0, consumable = 0, defensive = 1, colorful = 0, weed = 5, attributes = { "Weed", "Bad" }, maxSize = 5, canStore = false, canProceed = false },
  ["ic2:wheat"] = { name = "Wheat", tier = 1, chemistry = 0, consumable = 4, defensive = 0, colorful = 0, weed = 2, attributes = { "Yellow", "Food", "Wheat" }, maxSize = 7, vanillaItem = "minecraft:wheat_seeds", vanillaSeeds = true },
  ["ic2:pumpkin"] = { name = "Pumpkin", tier = 1, chemistry = 0, consumable = 1, defensive = 0, colorful = 3, weed = 1, attributes = { "Orange", "Decoration", "Stem" }, maxSize = 4, vanillaItem = "minecraft:pumpkin_seeds", vanillaSeeds = true },
  ["ic2:melon"] = { name = "Melon", tier = 2, chemistry = 0, consumable = 4, defensive = 0, colorful = 2, weed = 0, attributes = { "Green", "Food", "Stem" }, maxSize = 4, vanillaItem = "minecraft:melon_seeds", vanillaSeeds = true },
  ["ic2:dandelion"] = { name = "Dandelion", tier = 2, chemistry = 1, consumable = 1, defensive = 0, colorful = 5, weed = 1, attributes = { "Yellow", "Flower" }, maxSize = 4 },
  ["ic2:rose"] = { name = "Rose", tier = 2, chemistry = 1, consumable = 1, defensive = 0, colorful = 5, weed = 1, attributes = { "Red", "Flower", "Rose" }, maxSize = 4 },
  ["ic2:blackthorn"] = { name = "Blackthorn", tier = 2, chemistry = 1, consumable = 1, defensive = 0, colorful = 5, weed = 1, attributes = { "Black", "Flower", "Rose" }, maxSize = 4 },
  ["ic2:tulip"] = { name = "Tulip", tier = 2, chemistry = 1, consumable = 1, defensive = 0, colorful = 5, weed = 1, attributes = { "Purple", "Flower", "Tulip" }, maxSize = 4 },
  ["ic2:cyazint"] = { name = "Cyazint", tier = 2, chemistry = 1, consumable = 1, defensive = 0, colorful = 5, weed = 1, attributes = { "Blue", "Flower" }, maxSize = 4 },
  ["ic2:venomilia"] = { name = "Venomilia", tier = 3, chemistry = 3, consumable = 1, defensive = 3, colorful = 3, weed = 3, attributes = { "Purple", "Flower", "Tulip", "Poison" }, maxSize = 6 },
  ["ic2:reed"] = { name = "Reed", tier = 2, chemistry = 0, consumable = 0, defensive = 1, colorful = 0, weed = 2, attributes = { "Reed" }, maxSize = 3, vanillaItem = "minecraft:reeds" },
  ["ic2:stickreed"] = { name = "Stickreed", tier = 4, chemistry = 2, consumable = 0, defensive = 1, colorful = 0, weed = 1, attributes = { "Reed", "Resin" }, maxSize = 4 },
  ["ic2:cocoa"] = { name = "Cocoa", tier = 3, chemistry = 1, consumable = 3, defensive = 0, colorful = 4, weed = 0, attributes = { "Brown", "Food", "Stem" }, maxSize = 4, canProceed = false },
  ["ic2:flax"] = { name = "Flax", tier = 2, chemistry = 1, consumable = 1, defensive = 2, colorful = 0, weed = 1, attributes = { "Silk", "Vine", "Addictive" }, maxSize = 4 },
  ["ic2:ferru"] = { name = "Ferru", tier = 6, chemistry = 2, consumable = 0, defensive = 0, colorful = 1, weed = 0, attributes = { "Gray", "Leaves", "Metal" }, maxSize = 4 },
  ["ic2:aurelia"] = { name = "Aurelia", tier = 6, chemistry = 2, consumable = 0, defensive = 0, colorful = 2, weed = 0, attributes = { "Gold", "Leaves", "Metal" }, maxSize = 5 },
  ["ic2:redwheat"] = { name = "Redwheat", tier = 6, chemistry = 3, consumable = 0, defensive = 0, colorful = 2, weed = 0, attributes = { "Red", "Redstone", "Wheat" }, maxSize = 7, canProceed = false },
  ["ic2:nether_wart"] = { name = "Nether Wart", tier = 5, chemistry = 4, consumable = 2, defensive = 0, colorful = 2, weed = 1, attributes = { "Red", "Nether", "Ingredient", "Soulsand" }, maxSize = 3 },
  ["ic2:terra_wart"] = { name = "Terra Wart", tier = 5, chemistry = 2, consumable = 4, defensive = 0, colorful = 3, weed = 0, attributes = { "Blue", "Aether", "Consumable", "Snow" }, maxSize = 3 },
  ["ic2:coffee"] = { name = "Coffee", tier = 7, chemistry = 1, consumable = 4, defensive = 1, colorful = 2, weed = 0, attributes = { "Leaves", "Ingredient", "Beans" }, maxSize = 5 },
  ["ic2:hops"] = { name = "Hops", tier = 5, chemistry = 2, consumable = 2, defensive = 0, colorful = 1, weed = 1, attributes = { "Green", "Ingredient", "Wheat" }, maxSize = 7 },
  ["ic2:carrots"] = { name = "Carrots", tier = 2, chemistry = 0, consumable = 4, defensive = 0, colorful = 0, weed = 2, attributes = { "Orange", "Food", "Carrots" }, maxSize = 3, vanillaItem = "minecraft:carrot", vanillaSeeds = true },
  ["ic2:potato"] = { name = "Potato", tier = 2, chemistry = 0, consumable = 4, defensive = 0, colorful = 0, weed = 2, attributes = { "Yellow", "Food", "Potato" }, maxSize = 4, vanillaItem = "minecraft:potato" },
  ["ic2:red_mushroom"] = { name = "Red Mushroom", tier = 2, chemistry = 0, consumable = 4, defensive = 0, colorful = 0, weed = 4, attributes = { "Red", "Food", "Mushroom" }, maxSize = 3, canProceed = false },
  ["ic2:brown_mushroom"] = { name = "Brown Mushroom", tier = 2, chemistry = 0, consumable = 4, defensive = 0, colorful = 0, weed = 4, attributes = { "Brown", "Food", "Mushroom" }, maxSize = 3, canProceed = false },
  ["ic2:eatingplant"] = { name = "Eating Plant", tier = 6, chemistry = 1, consumable = 1, defensive = 3, colorful = 1, weed = 4, attributes = { "Bad", "Food" }, maxSize = 6 },
  ["ic2:cyprium"] = { name = "Cyprium", tier = 6, chemistry = 2, consumable = 0, defensive = 0, colorful = 1, weed = 0, attributes = { "Orange", "Leaves", "Metal" }, maxSize = 4 },
  ["ic2:stagnium"] = { name = "Stagnium", tier = 6, chemistry = 2, consumable = 0, defensive = 0, colorful = 1, weed = 0, attributes = { "Shiny", "Leaves", "Metal" }, maxSize = 4 },
  ["ic2:plumbiscus"] = { name = "Plumbiscus", tier = 6, chemistry = 2, consumable = 0, defensive = 0, colorful = 1, weed = 0, attributes = { "Dense", "Leaves", "Metal" }, maxSize = 4 },
  ["ic2:shining"] = { name = "Shining", tier = 6, chemistry = 2, consumable = 0, defensive = 0, colorful = 2, weed = 0, attributes = { "Silver", "Leaves", "Metal" }, maxSize = 5 },
  ["ic2:beetroots"] = { name = "Beetroots", tier = 1, chemistry = 0, consumable = 4, defensive = 0, colorful = 1, weed = 2, attributes = { "Red", "Food", "Beetroot" }, maxSize = 3, vanillaItem = "minecraft:beetroot_seeds", vanillaSeeds = true },
  ["ic2:oak_sapling"] = { name = "Oak Sapling", tier = 3, chemistry = 1, consumable = 0, defensive = 4, colorful = 4, weed = 0, attributes = { "Leaves", "Sapling", "Green" }, maxSize = 5 },
  ["ic2:spruce_sapling"] = { name = "Spruce Sapling", tier = 3, chemistry = 1, consumable = 0, defensive = 4, colorful = 4, weed = 0, attributes = { "Leaves", "Sapling", "Green" }, maxSize = 5 },
  ["ic2:birch_sapling"] = { name = "Birch Sapling", tier = 3, chemistry = 1, consumable = 0, defensive = 4, colorful = 4, weed = 0, attributes = { "Leaves", "Sapling", "Green" }, maxSize = 5 },
  ["ic2:jungle_sapling"] = { name = "Jungle Sapling", tier = 3, chemistry = 1, consumable = 0, defensive = 4, colorful = 4, weed = 0, attributes = { "Leaves", "Sapling", "Green" }, maxSize = 5 },
  ["ic2:acacia_sapling"] = { name = "Acacia Sapling", tier = 3, chemistry = 1, consumable = 0, defensive = 4, colorful = 4, weed = 0, attributes = { "Leaves", "Sapling", "Green" }, maxSize = 5 },
  ["ic2:dark_oak_sapling"] = { name = "Dark Oak Sapling", tier = 3, chemistry = 1, consumable = 0, defensive = 4, colorful = 4, weed = 0, attributes = { "Leaves", "Sapling", "Green" }, maxSize = 5 },
  ["ic2:blazereed"] = { name = "Blazereed", tier = 6, chemistry = 0, consumable = 4, defensive = 1, colorful = 0, weed = 0, attributes = { "Fire", "Blaze", "Reed", "Sulfur" }, maxSize = 4 },
  ["ic2:bobs_yer_uncle_ranks_berries"] = { name = "Bobs Yer Uncle Ranks Berries", tier = 11, chemistry = 4, consumable = 0, defensive = 8, colorful = 2, weed = 9, attributes = { "Shiny", "Vine", "Emerald", "Berylium", "Crystal" }, maxSize = 4 },
  ["ic2:corium"] = { name = "Corium", tier = 6, chemistry = 0, consumable = 2, defensive = 3, colorful = 1, weed = 0, attributes = { "Cow", "Silk", "Vine" }, maxSize = 4 },
  ["ic2:corpse_plant"] = { name = "Corpse Plant", tier = 5, chemistry = 0, consumable = 2, defensive = 1, colorful = 0, weed = 3, attributes = { "Toxic", "Undead", "Vine", "Edible", "Rotten" }, maxSize = 4 },
  ["ic2:creeper_weed"] = { name = "Creeper Weed", tier = 7, chemistry = 3, consumable = 0, defensive = 5, colorful = 1, weed = 3, attributes = { "Creeper", "Vine", "Explosive", "Fire", "Sulfur", "Saltpeter", "Coal" }, maxSize = 4 },
  ["ic2:diareed"] = { name = "Diareed", tier = 12, chemistry = 5, consumable = 0, defensive = 10, colorful = 2, weed = 10, attributes = { "Fire", "Shiny", "Reed", "Coal", "Diamond", "Crystal" }, maxSize = 4 },
  ["ic2:egg_plant"] = { name = "Egg Plant", tier = 6, chemistry = 0, consumable = 4, defensive = 1, colorful = 0, weed = 0, attributes = { "Chicken", "Egg", "Edible", "Feather", "Flower", "Addictive" }, maxSize = 3, crossFrom = 2 },
  ["ic2:ender_blossom"] = { name = "Ender Blossom", tier = 10, chemistry = 5, consumable = 0, defensive = 2, colorful = 1, weed = 6, attributes = { "Ender", "Flower", "Shiny" }, maxSize = 4 },
  ["ic2:meat_rose"] = { name = "Meat Rose", tier = 7, chemistry = 0, consumable = 4, defensive = 1, colorful = 3, weed = 0, attributes = { "Edible", "Flower", "Cow", "Chicken", "Pig", "Sheep" }, maxSize = 4 },
  ["ic2:milk_wart"] = { name = "Milk Wart", tier = 6, chemistry = 0, consumable = 3, defensive = 0, colorful = 1, weed = 0, attributes = { "Edible", "Milk", "Cow" }, maxSize = 3, crossFrom = 2 },
  ["ic2:oil_berries"] = { name = "Oil Berries", tier = 9, chemistry = 6, consumable = 1, defensive = 2, colorful = 1, weed = 12, attributes = { "Fire", "Dark", "Reed", "Rotten", "Coal", "Oil" }, maxSize = 3, crossFrom = 2 },
  ["ic2:slime_plant"] = { name = "Slime Plant", tier = 6, chemistry = 3, consumable = 0, defensive = 0, colorful = 0, weed = 2, attributes = { "Slime", "Bouncy", "Sticky", "Bush" }, maxSize = 4 },
  ["ic2:spidernip"] = { name = "Spidernip", tier = 4, chemistry = 2, consumable = 1, defensive = 4, colorful = 1, weed = 3, attributes = { "Toxic", "Silk", "Spider", "Flower", "Ingredient", "Addictive" }, maxSize = 4 },
  ["ic2:tearstalks"] = { name = "Tearstalks", tier = 8, chemistry = 1, consumable = 2, defensive = 0, colorful = 0, weed = 0, attributes = { "Healing", "Nether", "Ingredient", "Reed", "Ghast" }, maxSize = 4 },
  ["ic2:withereed"] = { name = "Withereed", tier = 8, chemistry = 2, consumable = 0, defensive = 4, colorful = 1, weed = 3, attributes = { "Fire", "Undead", "Reed", "Coal", "Rotten", "Wither" }, maxSize = 4 },
}
function Catalog.get(cropKey)
  local crop = Catalog[cropKey]
  if type(crop) == "table" then return crop end
end

function Catalog.canStore(cropKey)
  local crop = Catalog.get(cropKey)
  return crop ~= nil and crop.canStore ~= false
end

function Catalog.canProceed(cropKey)
  local crop = Catalog.get(cropKey)
  return crop ~= nil and crop.canProceed ~= false
end

function Catalog.crossFrom(cropKey)
  local crop = Catalog.get(cropKey)
  if crop then return crop.crossFrom or 3 end
end

local function nextCrop(catalog, cropKey)
  local crop
  repeat cropKey, crop = next(catalog, cropKey) until cropKey == nil or type(crop) == "table"
  return cropKey, crop
end
function Catalog.each() return nextCrop, Catalog, nil end

function Catalog.vanilla(itemName)
  for key, crop in Catalog.each() do if crop.vanillaItem == itemName then return key, crop end end
end

function Catalog.isDangerous(cropKey, growth)
  return cropKey == "ic2:weed"
      or growth >= 24
      or (cropKey == "ic2:venomilia" and growth >= 8)
end

function Catalog.terrainWeights(cropKey)
  if not Catalog.get(cropKey) then return end
  if cropKey == "ic2:pumpkin" or cropKey == "ic2:melon" then return 1.1, 0.9, 1 end
  if cropKey == "ic2:reed" or cropKey == "ic2:stickreed" then return 1.2, 1, 0.8 end
  if cropKey == "ic2:cocoa" then return 0.8, 1.3, 0.9 end
  if cropKey == "ic2:coffee" then return 0.4, 1.4, 1.2 end
  return 1, 1, 1
end

function Catalog.terrainQuality(humidity, nutrients, airQuality, humidityWeight, nutrientWeight, airWeight)
  local influence = humidityWeight * humidity + nutrientWeight * nutrients + airWeight * airQuality
  return 5 * (influence < 0 and math.ceil(influence) or math.floor(influence))
end

function Catalog.terrainNeed(cropKey, g, ga, r)
  local crop = Catalog.get(cropKey)
  if not crop then return end
  local minimum, maximum = 4 * (crop.tier - 1), 4 * (crop.tier - 1)
  for index = 1, 3 do
    local gene
    if index == 1 then gene = g elseif index == 2 then gene = ga else gene = r end
    if gene == nil then
      maximum = maximum + (index == 1 and (cropKey == "ic2:venomilia" and 7 or 23) or 31)
    elseif type(gene) ~= "number" or gene ~= math.floor(gene) or gene < 0 or gene > 31 then
      return
    else
      minimum, maximum = minimum + gene, maximum + gene
    end
  end
  return math.max(0, minimum), math.max(0, maximum)
end

return Catalog
