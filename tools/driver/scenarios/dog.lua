-- The farm dog (C4, D189, #358): the dog moves in (a toast, the dog by the spawn tile), eats from the food ledger at its
-- mealtime with nothing for the player to do, and the Tonight card names it among what lowers the night's exposure while a
-- raccoon is drawn for the night. The clock and stocks are set through the sim (a scenario cannot wait for a season); the
-- card, the toast and the sprite are the real ones. At desktop and phone sizes.
local Dog = require("src.sim.systems.dog")
local Inventory = require("src.sim.systems.inventory")
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

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local view = d.game.app.view
  local DPS = world.tuning.time.daysPerSeason
  for _, id in ipairs({ "deer", "bear" }) do
    world.tuning.raiders[id].chancePerDay = 0
  end
  world.tuning.cat.mice.chancePerDay = 0
  world.tuning.raiders.raccoon.chancePerDay = 8
  Ledger.add(world, "radish", 10)
  Ledger.add(world, "potato", 20)
  d:advance(1)

  -- 1. Owning the dog brings it to the homestead.
  Inventory.addEquipment(world, Dog.ITEM)
  d:advance(1)
  assert(Dog.present(world), "the dog never arrived")
  local x, y = Dog.position(world)
  local cx, cy = scene.camera:tileToWorld(x, y)
  scene.camera:centerOn(cx + scene.camera.tileSize / 2, cy + scene.camera.tileSize / 2, view)
  d:frames(3)
  d:shot("arrived")

  -- 2. At mealtime it eats a unit of food from the ledger by itself.
  local day = DPS + 3
  jumpTo(world, day, world.tuning.dog.feedHour - 0.2)
  world.state.finds.rollDay = day
  d:frames(3)
  local before = Ledger.get(world, "radish")
  d:advance(0.5)
  assert(Ledger.get(world, "radish") == before - world.tuning.dog.mealUnits, "the dog ate from the ledger")
  assert(Dog.fed(world), "and is fed")

  -- 3. After sunset a raccoon is drawn; the Tonight card names the dog on watch.
  jumpTo(world, day, world.tuning.time.daylight.summer[2] + 0.3)
  d:frames(30)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  local sign = NightThreats.sign(world)
  assert(sign and sign.id == "raccoon", "the raccoon is drawn at sunset")
  if not scene.tonight.open then
    d:key("t")
  end
  d:frames(10)
  assert(scene.tonight.open, "the Tonight card is up")
  d:shot("tonight_dog")
  d:key("t")

  -- 4. The dog sleeps through the night.
  jumpTo(world, day, 23.5)
  d:frames(10)
  d:shot("asleep")
end
