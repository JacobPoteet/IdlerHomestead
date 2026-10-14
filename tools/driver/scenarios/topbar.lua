-- The top bar says it in the icon (D112, #267): every chip carries its state (a bar, a state glyph, a
-- trend arrow) and its modal is a short summary. This stages a homestead with a cistern, coop and
-- goat pen, a cold autumn and stock in a few different states, shoots the bar, then taps every chip and
-- shoots its modal. Stock and the clock are set through the sim; the taps are the real ones.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Spoilage = require("src.sim.systems.spoilage")

local function spotNear(world, id, sx, sy, dx, dy)
  local grid = world.state.grid
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx - dx) ^ 2 + (y - sy - dy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot for " .. id)
  return best
end

local function jumpTo(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- Tap the middle of a chip's tap target, if the chip is on the bar.
local function tapChip(d, id)
  local scene = d:scene()
  for _, r in ipairs(scene:chipRects()) do
    if r.id == id then
      d:click(r.x + r.w / 2, r.y + r.h / 2)
      return true
    end
  end
  return false
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(1)
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  for n, id in ipairs({ "cistern", "chicken_coop", "goat_pen" }) do
    local at = spotNear(world, id, sx, sy, 3 * n, n % 2 == 0 and 3 or -3)
    Inventory.addObject(world, id)
    assert(Inventory.place(world, id, at))
  end
  jumpTo(world, world.tuning.time.daysPerSeason * 2 + 4, 10) -- late autumn
  d:frames(2)
  Ledger.add(world, "radish", 8)
  Ledger.add(world, "potato", 3)
  Ledger.add(world, "creek_chub", 4)
  Spoilage.ageStock(world, "creek_chub", Spoilage.shelfLife(world, "creek_chub"))
  Ledger.add(world, "wood", 9)
  Ledger.add(world, "water", 40)
  Ledger.add(world, "hen", 4, "driver")
  Ledger.add(world, "goat", 2, "driver")
  Ledger.add(world, "chicken_feed", 6, "driver")
  Ledger.add(world, "hay", 1, "driver")
  local a = world.state.animals
  a.nest = 3
  a.goats.pail = 2
  a.goats.feed = 1
  d:frames(6)
  assert(d:scene().name == "homestead", "expected the homestead, got " .. d:scene().name)
  d:shot("bar_mixed")

  local ids = { "weather", "money", "food", "condition", "battery", "surplus", "wood", "spoiled", "water", "hens", "eggs", "goats", "milk" }
  for _, id in ipairs(ids) do
    if tapChip(d, id) then
      d:frames(3)
      if d:scene().name == "notice" then
        d:shot("modal_" .. id)
        d:key("escape")
        d:frames(2)
      end
    end
  end

  -- The bar when things are fine and when everything is short.
  Ledger.add(world, "radish", 40)
  Ledger.add(world, "wood", 200)
  d:frames(4)
  d:shot("bar_fine")
  Ledger.remove(world, "radish", Ledger.get(world, "radish"))
  Ledger.remove(world, "potato", Ledger.get(world, "potato"))
  Ledger.remove(world, "creek_chub", Ledger.get(world, "creek_chub"))
  Ledger.remove(world, "canned_food", Ledger.get(world, "canned_food"))
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  d:frames(2)
  tapChip(d, "food")
  d:frames(3)
  d:shot("modal_food_bad")
  d:key("escape")
  tapChip(d, "wood")
  d:frames(3)
  d:shot("modal_wood_bad")
  d:key("escape")
  d:frames(4)
  d:shot("bar_short")
end
