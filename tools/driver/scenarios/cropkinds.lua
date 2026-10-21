-- The eleven crops (D177, #363): every crop at its three growth stages in one field (placeholder art), the seed
-- tray with a packet per crop, a garlic plan in spring (it waits for autumn: the tile card says so), and the
-- Water & Soil chapter of the Field Journal with the nine new seeds as ideas on the Seeds page.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)
  d:setSpeed(0)
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  local tx, ty = Grid.coords(grid, world.state.land.truck)

  -- noon, clear
  local now = Calendar.now(world)
  world.state.calendar.elapsed = world.state.calendar.elapsed + ((12 - now.hour) % 24) / 24 * dayLength
  for n = 1, 4 do
    world.state.weather.sky.days[n] = "clear"
  end

  for anchor in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if math.abs(x - tx) <= 10 and math.abs(y - ty) <= 8 then
      Grid.removeObject(world, anchor)
    end
  end

  -- one row per crop: sprout, growing, ready, and a thirsty one
  local fields = world.state.fields
  local crops = world.registry:all("crops")
  for row, crop in ipairs(crops) do
    for col, growth in ipairs({ 0.1, 0.6, 1, 0.6 }) do
      local i = Grid.index(grid, tx - 3 + col, ty + 1 + row)
      fields.tilled[i] = true
      world.state.crops[i] = { id = crop.id, growth = growth, moisture = col == 4 and 0 or 1 }
    end
  end
  cam.zoomIndex = 1
  cam:centerOn((tx - 1) * tile, (ty + 1 + #crops / 2) * tile, view)
  d:frames(4, 0.05)
  d:shot("field")

  -- a garlic plan in spring: tapped, the card says it waits for autumn
  local plan = Grid.index(grid, tx + 3, ty + 3)
  fields.tilled[plan] = nil
  fields.plan[plan] = "garlic"
  Ledger.add(world, "seed_garlic", 3, "test")
  scene.selected = plan
  scene:layout()
  d:frames(3, 0.05)
  d:shot("garlic_waits")
  scene.selected = nil

  -- the Hoe's ring: a packet for every crop (the extra ones end in More)
  d:pressHud("tools")
  d:frames(10, 0.05)
  d:shot("wheel_open")
  local wedge = scene.wheelLayout.wedges.hoe
  local s = scene.app.view.scale
  d.game.input:mousemoved((wedge.x + wedge.w / 2) * s, (wedge.y + wedge.h / 2) * s, 0, 0, false)
  d:frames(2)
  assert(scene.wheel and scene.wheel.highlight == "hoe", "hovering the Hoe shows its ring")
  d:shot("hoe_ring")
  d:key("escape")
  d:frames(2)

  -- the Journal's Water & Soil chapter lists the seeds
  d:pick("Journal")
  d:frames(8)
  local jscene = d:scene()
  for i, chapter in ipairs(jscene.chapters) do
    if chapter.name == "Water & Soil" then
      jscene.nav.offset = 0
      jscene:layoutButtons()
      local t = jscene.nav.grid.tileOf[i]
      d:click(jscene.nav.body.x + t.x + t.w / 2, jscene.nav.body.y + t.y - jscene.nav.offset + t.h / 2)
    end
  end
  d:frames(3)
  d:shot("journal_seeds")
  d:key("escape")
  d:key("escape")
  d:frames(2)
end
