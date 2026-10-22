-- Night raiders (C2 + C3, D188, #356): a summer dusk with a young field, the deer drawn for the night (the dusk sign on
-- the Tonight card), the raid landing (a toast, and the browsed crops' tile card), then an autumn dusk with the bear and
-- the Journal's three new answers (Lidded bins, Scarecrow, Bear box) once their notes are written. The clock, stocks and
-- crops are set through the sim (a scenario cannot wait for a season); the card, the toasts, the tile card and the
-- journal are the real ones. At desktop and phone sizes.
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local NightThreats = require("src.sim.systems.nightthreats")

local function jumpTo(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- A random find can pop up after a long jump of the clock: take it so the homestead is on top again.
local function dismissFinds(d)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1]
      d:click(first.x + first.w / 2, first.y + first.h / 2)
      d:press("Take it")
      d:frames(3)
    end
  end
end

local function hasLine(lines, text)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then
      return true
    end
  end
  return false
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local DPS = world.tuning.time.daysPerSeason
  -- Only the one raider has a chance, and it is certain.
  for _, id in ipairs({ "raccoon", "deer", "bear" }) do
    world.tuning.raiders[id].chancePerDay = 0
  end
  world.tuning.cat.mice.chancePerDay = 0
  world.tuning.raiders.deer.chancePerDay = 8

  -- A block of young tomatoes at the start.
  local tiles = {}
  for dy = 2, 4 do
    for dx = 2, 5 do
      local x, y = d:freeTileNear(dx * 2, dy * 2)
      local i = Grid.index(world.state.grid, x, y)
      if not world.state.crops[i] then
        world.state.fields.tilled[i] = true
        world.state.fields.plan[i] = "tomato"
        world.state.crops[i] = { id = "tomato", growth = 0.4, moisture = 1, thirst = 0 }
        tiles[#tiles + 1] = i
      end
    end
  end
  assert(#tiles >= 4, "a field to browse")
  d:frames(6)

  -- 1. After sunset in summer the deer are drawn: the dusk sign is on the Tonight card.
  local day = DPS + 3
  local sunset = world.tuning.time.daylight.summer[2]
  jumpTo(world, day, sunset + 0.3)
  d:frames(30)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  local sign = NightThreats.sign(world)
  assert(sign and sign.id == "deer", "the deer are drawn at sunset")
  if not scene.tonight.open then
    d:key("t")
  end
  d:frames(10)
  assert(scene.tonight.open, "the Tonight card is up")
  d:shot("dusk_sign")
  d:key("t")

  -- 2. The raid lands at its hour: a few edge crops are browsed, none die, and the tile card says so.
  jumpTo(world, day, world.tuning.raiders.deer.hour + 0.2)
  d:frames(30)
  dismissFinds(d)
  local history = NightThreats.history(world)
  assert(history[#history] and history[#history].outcome == "landed", "the raid landed")
  local browsed
  for _, i in ipairs(tiles) do
    assert(world.state.crops[i], "no crop died")
    if Crops.isBrowsed(world, i) then
      browsed = browsed or i
    end
  end
  assert(browsed, "a crop was browsed")
  assert(hasLine(scene:tileInfo(browsed), "Browsed by deer"), "the tile card says it")
  scene.selected = browsed
  d:frames(12)
  d:shot("browsed_card")
  scene.selected = nil

  -- 3. The notes are written by the raids; the answers are then ideas in the Journal.
  assert(Journal.hasNote(world, "deer_browse"), "the raid wrote its note")
  for _, id in ipairs({ "raccoon_raid", "bear_raid" }) do
    Journal.write(world, id)
  end
  Ledger.add(world, "money", 200)
  d:frames(6)
  d:pick("Journal")
  d:frames(8)
  d:shot("journal")
  d:key("escape")
  d:frames(3)

  -- 4. An autumn dusk with smoked fish in store: the bear, and its sign.
  world.tuning.raiders.deer.chancePerDay = 0
  world.tuning.raiders.bear.chancePerDay = 8
  world.tuning.raiders.bear.yearScale = { 1 }
  Ledger.add(world, "smoked_fish", 8)
  local autumn = 2 * DPS + 3
  jumpTo(world, autumn, world.tuning.time.daylight.autumn[2] + 0.3)
  d:frames(30)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  sign = NightThreats.sign(world)
  assert(sign and sign.id == "bear", "the bear is drawn on an autumn night")
  if not scene.tonight.open then
    d:key("t")
  end
  d:frames(10)
  d:shot("bear_sign")
end
