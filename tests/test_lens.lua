-- The lenses (GDD §9.4, D141, D145, #297): which lens a tool, a placement, a vital or a tapped device switches
-- on, when it goes off, where its card sits at every view size, and what the data layer holds.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Fields = require("src.render.lens_fields")
local LensState = require("src.ui.lens")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.ui.lens

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(1))
end

local function place(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

local function def(id)
  return reg:get("objects", id)
end

-- Routing ----------------------------------------------------------------------------------------

T.test("lens: objects route to their lens, water things before power things", function()
  T.eq(LensState.forObject(def("folding_panel")), "power")
  T.eq(LensState.forObject(def("battery_bank")), "power")
  T.eq(LensState.forObject(def("chest_freezer")), "power")
  T.eq(LensState.forObject(def("dc_pump")), "water", "a pump draws power but is a water thing")
  T.eq(LensState.forObject(def("well")), "water")
  T.eq(LensState.forObject(def("drip_line")), "water")
  T.eq(LensState.forObject(def("sprinkler")), "water")
  T.eq(LensState.forObject(def("cistern")), "water")
  T.eq(LensState.forObject(def("smoker")), nil, "a smoker has no lens")
end)

T.test("lens: the pail shows Water, other tools show nothing, a vital opens its lens", function()
  T.eq(LensState.forTool(cfg, "pail"), "water")
  T.eq(LensState.forTool(cfg, "axe"), nil)
  T.eq(LensState.forTool(cfg, nil), nil)
  T.eq(LensState.forVital(cfg, "battery"), "power")
  T.eq(LensState.forVital(cfg, "water"), "water")
  T.eq(LensState.forVital(cfg, "food"), nil)
end)

T.test("lens: a trigger switches its lens on and off again when it ends", function()
  local lens = LensState.new(cfg)
  T.eq(lens:active(), nil)
  lens:sync("water") -- the pail comes out
  T.eq(lens:active(), "water")
  lens:sync("water")
  T.eq(lens:active(), "water", "still on while the trigger holds")
  lens:sync(nil)
  T.eq(lens:active(), nil, "off when the pail goes away")
  lens:sync("power") -- a panel is being placed
  T.eq(lens:active(), "power")
  lens:sync("water") -- then a pump: the lens follows
  T.eq(lens:active(), "water")
end)

T.test("lens: closing a triggered lens keeps it closed until the trigger changes", function()
  local lens = LensState.new(cfg)
  lens:sync("water")
  lens:dismiss()
  T.eq(lens:active(), nil)
  lens:sync("water")
  T.eq(lens:active(), nil, "the pail does not reopen it a frame later")
  lens:sync(nil)
  lens:sync("water")
  T.eq(lens:active(), "water", "a new trigger switches it on again")
end)

T.test("lens: the vital toggles, and a lens the player opened outlives a trigger", function()
  local lens = LensState.new(cfg)
  T.truthy(lens:toggle("power"))
  T.eq(lens:active(), "power")
  lens:sync("water")
  lens:sync(nil)
  T.eq(lens:active(), nil, "a trigger took over, and its end put the lens away")
  lens:show("power", "vital")
  lens:sync(nil)
  T.eq(lens:active(), "power", "a vital's lens stays with no trigger")
  T.falsy(lens:toggle("power"), "the vital again puts it away")
  T.eq(lens:active(), nil)
  LensState.forced = "water"
  T.eq(lens:active(), "water", "the editor can hold a lens on")
  LensState.forced = nil
end)

-- Card geometry ----------------------------------------------------------------------------------

T.test("lens card: inside the free band, touch tall when folded, at every view size", function()
  local touch = tun.input.minTouchTarget
  for _, v in ipairs({ { 1280, 720 }, { 390, 844 }, { 844, 390 } }) do
    local view = { w = v[1], h = v[2] }
    local bounds = { top = 40, bottom = v[2] - 60 }
    for _, folded in ipairs({ false, true }) do
      local spec = LensState.cardRect(cfg, view, bounds, folded, touch)
      local r = spec.rect
      local label = v[1] .. "x" .. v[2] .. (folded and " folded" or "")
      T.truthy(r.x >= 0 and r.x + r.w <= view.w, label .. ": inside the view horizontally")
      T.truthy(r.y >= bounds.top and r.y + r.h <= bounds.bottom, label .. ": inside the free band")
      T.truthy(spec.strip >= touch, label .. ": the strip is a touch target")
      if folded then
        T.eq(r.h, spec.strip, label .. ": a folded card is its strip")
      end
    end
  end
  T.eq(LensState.cardRect(cfg, { w = 1280, h = 720 }, { top = 0, bottom = 700 }, false, 44).layout, "side")
  T.eq(LensState.cardRect(cfg, { w = 390, h = 844 }, { top = 0, bottom = 800 }, false, 44).layout, "sheet")
end)

-- Data layer -------------------------------------------------------------------------------------

local function maxOf(t)
  local m = 0
  for _, v in ipairs(t) do
    m = math.max(m, v)
  end
  return m
end

T.test("lens fields: a source makes a warm pool and a sink a band, joined by a connection", function()
  local world = newWorld()
  local empty = Fields.power(world, tun.visuals.lens.power)
  place(world, "solar_array")
  place(world, "chest_freezer")
  world:tick(1 / tun.time.tickRate)
  local f = Fields.power(world, tun.visuals.lens.power)
  T.truthy(maxOf(f.r) > maxOf(empty.r), "the array makes a pool")
  T.truthy(maxOf(f.g) > 0, "the freezer makes a band")
  T.truthy(maxOf(f.r) <= 1 and maxOf(f.g) <= 1, "fields stay in 0..1")
  T.truthy(#f.markers.connections >= 2, "each end is connected")
end)

T.test("lens fields: a bigger draw makes a wider, stronger band", function()
  local world = newWorld()
  place(world, "chest_freezer")
  local small = Fields.power(world, tun.visuals.lens.power)
  place(world, "electric_heater")
  local both = Fields.power(world, tun.visuals.lens.power)
  local function covered(t)
    local n = 0
    for _, v in ipairs(t) do
      if v > 0 then
        n = n + 1
      end
    end
    return n
  end
  T.truthy(covered(both.g) > covered(small.g), "the heater adds a band")
end)

T.test("lens fields: the water table, irrigation coverage and ground a well can go on", function()
  local world = newWorld()
  local plain = Fields.water(world, tun.visuals.lens.water, nil)
  T.truthy(maxOf(plain.r) > 0, "the water table is painted")
  T.eq(maxOf(plain.g), 0, "no coverage before a line is placed")
  T.eq(maxOf(plain.b), 0, "no spots unless a well is being placed")
  local spots = Fields.water(world, tun.visuals.lens.water, { id = "well" })
  T.eq(maxOf(spots.b), 1, "placing a well marks the ground it can go on")
  local line = place(world, "drip_line")
  local f = Fields.water(world, tun.visuals.lens.water, nil)
  T.truthy(f.g[line] > 0, "the line covers its own tile")
  local both = Fields.water(world, tun.visuals.lens.water, { id = "drip_line", tile = line })
  T.truthy(both.g[line] > f.g[line], "the line being placed adds its coverage")
end)

T.test("lens fields: a cistern gets a gauge that follows the stock", function()
  local world = newWorld()
  place(world, "cistern")
  local f = Fields.water(world, tun.visuals.lens.water, nil)
  T.eq(#f.markers.gauges, 1)
  T.eq(f.markers.gauges[1].kind, "cistern")
end)
