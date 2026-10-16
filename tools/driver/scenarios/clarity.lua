-- The clarity batch (D72): tap-to-explain HUD chips (#158), the Journal's unlock hints (#160), the truck
-- panel at home with its trip numbers and the "ready" state (#162), the renamed toolbar with the tool
-- caption and routine badge (#168), and the toolbar palette on narrow views (#17). The truck's charge is
-- set through the sim (a scenario cannot wait for the sun); the taps are the real ones.
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")

--- Tap the middle of a chip's tap target. Also checks the target is finger-sized.
local function tapChip(d, id)
  local scene = d:scene()
  local minSize = scene.app.ctx.tuning.input.minTouchTarget
  for _, r in ipairs(scene:chipRects()) do
    assert(r.w >= minSize and r.h >= minSize, "chip " .. tostring(r.id) .. " is smaller than the touch size")
    if r.id == id then
      d:click(r.x + r.w / 2, r.y + r.h / 2)
      return
    end
  end
  error("no chip " .. id)
end

return function(d)
  d:newGame()
  local world = d:world()
  local truck = Land.truck(world)
  d:frames(10)
  d:shot("toolbar")

  -- Chips: the explanation card for food (with its Pantry shortcut) and the truck charge (Power).
  tapChip(d, "food")
  d:frames(3)
  assert(d:scene().name == "notice", "a chip tap opens its card")
  d:shot("chip_food")
  d:key("escape")
  tapChip(d, "battery")
  d:frames(3)
  d:shot("chip_battery")
  d:press("Open Power")
  d:frames(3)
  assert(d:scene().name == "power", "the shortcut opens the Power panel")
  d:key("escape")
  d:frames(3)

  -- The tools tray and a book's tray (D137), then the tool caption.
  d:press("Tools")
  d:frames(3)
  d:shot("palette_tools")
  d:key("escape")
  d:press("Notebook")
  d:frames(3)
  d:shot("palette_more")
  d:key("escape")
  d:pick("Rod")
  d:frames(3)
  d:shot("rod_caption")
  d:pick("Plan field")
  d:frames(3)
  d:shot("plan_caption")
  d:pick("Hand")
  d:frames(3)

  -- Journal: a ??? idea says what to do, and so does a blank stamp.
  d:pick("Journal")
  d:frames(5)
  local journal = d:scene()
  journal:select("smoker")
  d:frames(3)
  d:shot("journal_hint")
  journal:select("axe")
  d:frames(3)
  d:shot("journal_hint_axe")
  journal:selectNote("felled_tree")
  d:frames(3)
  d:shot("journal_note_hint")
  for _ = 1, 4 do -- each escape steps back one level (note, chapter, overview, close)
    if d:scene().name == "homestead" then
      break
    end
    d:key("escape")
  end
  d:frames(3)
  assert(d:scene().name == "homestead", "the journal closed, scene is " .. tostring(d:scene().name))

  -- Truck at home: charging, then ready.
  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  Power.drain(world, truck, Power.charge(world, truck))
  d:frames(30)
  d:clickTile(tx, ty)
  d:frames(5)
  d:shot("truck_charging")
  d:key("escape")
  Power.add(world, truck, world.tuning.economy.tripCost + 2)
  d:frames(30)
  d:shot("trip_ready_hud")
  d:clickTile(tx, ty)
  d:frames(5)
  d:shot("truck_ready")
  d:key("escape")
end
