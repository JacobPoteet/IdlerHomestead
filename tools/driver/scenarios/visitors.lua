-- The visitors and luck events (B9, D194): the card for the peddler (a price worked out from the market, in money or in
-- eggs), the hiker (a supper and a fire) and the stray dog (a dog that stays). Offered through the Events debug path; the card
-- and the taps are the real ones.
local Events = require("src.sim.systems.events")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")

local function quiet(d)
  local scene = d:scene()
  scene.toast, scene.toastQueue = nil, {}
end

local function block(scene, prefix)
  for _, b in ipairs(scene.eventCard.blocks.list) do
    if b.label:sub(1, #prefix) == prefix then
      return b
    end
  end
  return nil
end

local function tap(d, b)
  d:click(b.x + b.w / 2, b.y + b.h / 2)
  d:frames(3)
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local view = scene.app.view
  d:frames(30)
  quiet(d)

  -- 1. The peddler: both prices are on the card; a tap on Buy pays the money and gives the canes.
  Ledger.add(world, "money", 60)
  Ledger.add(world, "egg", 30)
  assert(Events.force(world, "peddler"))
  d:frames(10)
  quiet(d)
  local r = scene.eventRect
  assert(r.x >= 0 and r.x + r.w <= view.w and r.y >= 0 and r.y + r.h <= view.h, "inside the view")
  local buy, barter = block(scene, "Buy"), block(scene, "Barter")
  assert(buy and barter and buy.enabled and barter.enabled, "both trades can be chosen")
  d:shot("peddler")
  tap(d, buy)
  assert(Ledger.get(world, "seed_berries") == 2, "the canes are in the seed bag")
  d:frames(10)
  quiet(d)

  -- 2. The hiker at the door: the supper is named from what the pantry holds.
  assert(Events.force(world, "lost_hiker"))
  d:frames(10)
  quiet(d)
  assert(block(scene, "Share") and block(scene, "Point"), "two options")
  d:shot("hiker")
  Events.ignore(world)
  d:frames(10)
  quiet(d)

  -- 3. The stray dog: feeding it keeps it.
  assert(Events.force(world, "stray_dog"))
  d:frames(10)
  quiet(d)
  local keep = block(scene, "Feed")
  assert(keep and keep.enabled, "a supper is in the pantry")
  d:shot("stray_dog")
  tap(d, keep)
  assert(Inventory.hasEquipment(world, "farm_dog"), "the dog stays")
  d:frames(10)
  d:shot("dog_kept")
end
