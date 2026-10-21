-- The crop schema and the eleven crops (PLAN_DEPTH 8.1, D177, issue #363): data shape, plant windows, frost,
-- water appetite, the seed gate on the Seeds page, and the art every crop needs.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Spoilage = require("src.sim.systems.spoilage")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local manifest = require("assets.manifest")
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SPRING, SUMMER, AUTUMN, WINTER = 1, DPS + 1, 2 * DPS + 1, 3 * DPS + 1

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

--- A free tillable tile near the spawn.
local function freeTile(world)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if i and Grid.terrain(world, i).tillable and not world.occupancy[i] and i ~= world.state.land.spawn then
          return i
        end
      end
    end
  end
end

-- Each crop's planting window, written out so a change to the data is a change to the test (first guesses, M9).
local WINDOWS = {
  radish = { "spring", "summer", "autumn" },
  potato = { "spring", "summer", "autumn" },
  lettuce = { "spring", "autumn" },
  beans = { "spring", "summer" },
  carrot = { "spring", "summer", "autumn" },
  onion = { "spring", "summer" },
  garlic = { "autumn" },
  squash = { "spring", "summer" },
  tomato = { "spring", "summer" },
  corn = { "spring", "summer" },
  herbs = { "spring", "summer", "autumn" },
  berries = { "spring" }, -- the perennials (D183)
  apple = { "spring", "summer" },
}
local HARDY = { lettuce = true, garlic = true, berries = true, apple = true }

local function has(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

T.test("crops: thirteen crops, the starter pair first, and the data is the table above", function()
  local all = reg:all("crops")
  T.eq(#all, 13)
  T.eq(all[1].id, "radish", "the policies and the starter field rely on the order")
  T.eq(all[2].id, "potato")
  for _, crop in ipairs(all) do
    T.truthy(WINDOWS[crop.id], crop.id .. " is in the test's table")
    T.eq(table.concat(crop.plantSeasons, ","), table.concat(WINDOWS[crop.id], ","), crop.id .. " window")
    T.eq(crop.frost, HARDY[crop.id] and "hardy" or "tender", crop.id .. " frost")
  end
end)

T.test("crops: every crop has the schema fields in range and its five data files", function()
  local seasons, families = tun.time.seasons, tun.farming.families
  for _, crop in ipairs(reg:all("crops")) do
    local id = crop.id
    T.truthy(crop.growDays > 0 and crop.yield > 0, id .. " grows and yields")
    if crop.perennial then
      T.eq(crop.seedReturn[2], 0, id .. " gives no seed back (it is planted once)")
    else
      T.truthy(crop.seedReturn[1] >= 1 and crop.seedReturn[2] >= crop.seedReturn[1], id .. " seed return")
    end
    T.truthy(#crop.plantSeasons > 0, id .. " has a window")
    for _, s in ipairs(crop.plantSeasons) do
      T.truthy(has(seasons, s), id .. " window season " .. s)
    end
    T.truthy(crop.frost == "tender" or crop.frost == "hardy", id .. " frost")
    T.truthy(crop.waterAppetite > 0, id .. " water appetite")
    T.truthy(crop.qualitySensitivity >= 0 and crop.qualitySensitivity <= 1, id .. " quality sensitivity")
    T.truthy(has(families, crop.family), id .. " family " .. crop.family)
    T.truthy(crop.fertilityDraw > -1 and crop.fertilityDraw < 1, id .. " fertility draw")
    -- the resources, the catalog entry, the art
    T.eq(reg:get("resources", crop.seed).category, "seed", id .. " seed")
    T.truthy(reg:get("resources", crop.produce).value, id .. " produce sells")
    local entry = reg:get("catalog", id .. "_seeds")
    T.eq(entry.page, "seeds")
    T.truthy(entry.gives[crop.seed] and entry.gives[crop.seed] > 0, id .. " seeds give the seed")
    for _, sprite in ipairs({ id, "icon_seed_" .. id, "icon_" .. id, "icon_packet_" .. id }) do
      T.truthy(manifest.sprites[sprite], sprite .. " is in the manifest")
    end
    -- perishable foods have a shelf life; herbs, with no calories, are dried and keep
    local res = reg:get("resources", crop.produce)
    T.eq(Spoilage.perishable(newWorld(), crop.produce), res.calories ~= nil, id .. " perishable if edible")
  end
  -- the legume gives back, the heavy feeders take most
  T.truthy(reg:get("crops", "beans").fertilityDraw < 0, "beans add fertility")
  T.truthy(reg:get("crops", "corn").fertilityDraw > reg:get("crops", "potato").fertilityDraw)
end)

T.test("crops: season windows, crop by crop and season by season", function()
  local world = newWorld()
  for id, window in pairs(WINDOWS) do
    for _, season in ipairs(tun.time.seasons) do
      T.eq(Crops.inWindow(world, id, season), has(window, season), id .. " in " .. season)
    end
  end
  -- canPlantNow follows the calendar and never opens on frozen ground
  setTime(world, SPRING)
  T.truthy(Crops.canPlantNow(world, "lettuce"))
  T.falsy(Crops.canPlantNow(world, "garlic"), "garlic waits for autumn")
  setTime(world, SUMMER)
  T.falsy(Crops.canPlantNow(world, "lettuce"), "lettuce bolts in summer")
  T.truthy(Crops.canPlantNow(world, "tomato"))
  setTime(world, AUTUMN)
  T.truthy(Crops.canPlantNow(world, "garlic"))
  T.falsy(Crops.canPlantNow(world, "tomato"))
  setTime(world, WINTER)
  for id in pairs(WINDOWS) do
    T.falsy(Crops.canPlantNow(world, id), id .. " is not planted in the frozen season")
  end
end)

T.test("crops: a planned tile outside the window is tilled and waits for its season", function()
  local world = newWorld()
  setTime(world, SPRING, 9)
  local i = freeTile(world)
  Ledger.add(world, "seed_garlic", 2, "test")
  T.truthy(Crops.setPlan(world, i, "garlic"))
  run(world, 60)
  T.truthy(world.state.fields.tilled[i], "tilled all the same")
  T.eq(world.state.crops[i], nil, "garlic is not sown in spring")
  T.eq(Ledger.get(world, "seed_garlic"), 2, "the seed stays in the store")
  setTime(world, AUTUMN, 9)
  run(world, 60)
  T.truthy(world.state.crops[i], "sown once autumn comes")
  T.eq(world.state.crops[i].id, "garlic")
  T.eq(Ledger.get(world, "seed_garlic"), 1)
end)

T.test("crops: the routine's starter field still plants radish and potato in spring", function()
  local world = newWorld(1)
  local planned = Crops.planStarter(world)
  T.truthy(#planned > 0)
  local kinds = {}
  for _, id in pairs(world.state.fields.plan) do
    kinds[id] = true
  end
  T.truthy(kinds.radish and kinds.potato)
  for _, entry in ipairs(tun.farming.starterField) do
    T.truthy(Crops.inWindow(world, entry.crop, "spring"), entry.crop .. " is sown in spring")
  end
end)

T.test("crops: tender crops die at the freeze, hardy ones sit the winter out", function()
  for id in pairs(WINDOWS) do
    local world = newWorld()
    local i = freeTile(world)
    world.state.crops[i] = { id = id, growth = 0.5, moisture = 1 }
    local frosted = {}
    world.events:on("crop.frosted", function(e)
      frosted[#frosted + 1] = e.crop
    end)
    world.events:emit("weather.froze", {})
    if HARDY[id] then
      T.truthy(world.state.crops[i], id .. " survives the freeze")
      T.eq(#frosted, 0)
    else
      T.eq(world.state.crops[i], nil, id .. " is killed by the freeze")
      T.eq(frosted[1], id)
    end
  end
end)

T.test("crops: a ripe tender crop is lost to the freeze too, and a ripe hardy one stays", function()
  local world = newWorld()
  local a = freeTile(world)
  local b = a + 1
  world.state.crops[a] = { id = "carrot", growth = 1, moisture = 0 }
  world.state.crops[b] = { id = "lettuce", growth = 1, moisture = 0 }
  world.events:emit("weather.froze", {})
  T.eq(world.state.crops[a], nil)
  T.truthy(world.state.crops[b])
end)

T.test("crops: hardy crops are no frost risk; tender ones still are late in autumn", function()
  local world = newWorld()
  setTime(world, 3 * DPS, 9) -- the last day before winter
  T.eq(Crops.frostRisk(world, "radish").level, "late")
  T.eq(Crops.frostRisk(world, "squash").level, "late")
  T.eq(Crops.frostRisk(world, "lettuce"), nil)
  T.eq(Crops.frostRisk(world, "garlic"), nil)
end)

T.test("crops: a hardy crop is dormant while frozen and grows again after the thaw", function()
  local world = newWorld()
  local i = freeTile(world)
  world.state.crops[i] = { id = "garlic", growth = 0.5, moisture = 1 }
  setTime(world, WINTER, 9)
  for _ = 1, 200 do
    Crops.tick(world, 1)
  end
  T.eq(world.state.crops[i].growth, 0.5, "nothing grows on frozen ground")
  T.eq(world.state.crops[i].moisture, 1, "and nothing dries")
  setTime(world, 1, 9) -- spring
  Crops.tick(world, tun.time.dayLength)
  T.truthy(world.state.crops[i].growth > 0.5, "growing again in spring")
end)

T.test("crops: water appetite dries a watering faster or slower than the base rate", function()
  local world = newWorld()
  setTime(world, SPRING, 9)
  local tiles, ids = {}, { "radish", "lettuce", "garlic" }
  local i = freeTile(world)
  for n, id in ipairs(ids) do
    tiles[n] = i + n - 1
    world.state.crops[tiles[n]] = { id = id, growth = 0, moisture = 1 }
  end
  Crops.tick(world, tun.time.dayLength * 0.5) -- half a day awake and growing
  local m = {}
  for n, tile in ipairs(tiles) do
    m[ids[n]] = world.state.crops[tile].moisture
  end
  local base = 1 - 0.5 / tun.farming.moistureDays
  T.near(m.radish, base, 1e-6, "appetite 1 is the base rate")
  T.truthy(m.lettuce < m.radish, "thirsty lettuce dries faster")
  T.truthy(m.garlic > m.radish, "garlic dries slower")
end)

T.test("crops: the nine new seeds are ideas on the Seeds page, gated by notes, none known at the start", function()
  local world = newWorld()
  for _, crop in ipairs(reg:all("crops")) do
    local entry = reg:get("catalog", crop.id .. "_seeds")
    if crop.id == "radish" or crop.id == "potato" then
      T.truthy(entry.starter, crop.id .. " is a starter seed")
    else
      T.falsy(entry.starter, crop.id .. " is not")
      T.truthy(entry.needs and #entry.needs > 0 and entry.studyNights >= 1, crop.id .. " is gated")
      for _, note in ipairs(entry.needs) do
        T.truthy(reg:has("notes", note), crop.id .. " needs a real note: " .. note)
      end
      T.falsy(Journal.isKnown(world, entry.id))
      T.eq(Market.cannotBuy(world, entry.id, false), "unknown", crop.id .. " cannot be bought before it is learned")
    end
  end
  -- write the notes, learn it, buy it
  for _, note in ipairs(reg:get("catalog", "garlic_seeds").needs) do
    world.meta.journal.notes[note] = { day = 1, season = "autumn", year = 1, run = 1 }
  end
  T.truthy(Journal.isIdea(world, "garlic_seeds"))
  T.truthy(Journal.learnNow(world, "garlic_seeds"))
  T.eq(Market.cannotBuy(world, "garlic_seeds", false), "not enough money", "known: only the money is missing")
  Ledger.add(world, "money", 100, "test")
  T.eq(Market.cannotBuy(world, "garlic_seeds", false), nil)
end)
