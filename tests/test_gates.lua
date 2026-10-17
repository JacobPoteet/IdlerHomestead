-- The gate framework (D164, #343): the content flag `requiresFooting`, the one accessor Footing.isOpen, the gate the
-- Market enforces ("needs Footing"), the locked words on the item card, and the Progress panel's gate list. No shipped
-- item carries the flag; the tests flag one by hand.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Footing = require("src.sim.systems.footing")
local Goal = require("src.sim.systems.goal")
local ItemText = require("src.ui.item_text")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local schemas = require("data.schemas")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

--- A starter catalog item the player could buy right now, found by asking the market.
local function buyable(world)
  Ledger.add(world, "money", 100000)
  for _, def in ipairs(reg:all("catalog")) do
    if def.starter and Market.cannotBuy(world, def.id, false) == nil then
      return def
    end
  end
  error("no buyable starter item")
end

--- Run `fn` with `def` flagged as gated, then take the flag off again (definitions are shared across tests).
local function flagged(def, fn)
  rawset(def, "requiresFooting", true)
  local ok, err = pcall(fn)
  rawset(def, "requiresFooting", nil)
  if not ok then
    error(err, 0)
  end
end

T.test("gates: the flag is a catalog schema field and no shipped item carries it", function()
  T.eq(schemas.catalog.requiresFooting, "boolean?")
  for _, def in ipairs(reg:all("catalog")) do
    T.eq(Footing.gated(def), false, def.id .. " must not be gated yet")
  end
end)

T.test(
  "gates: Footing.isOpen reads the flag from a definition, a bare gate or true, and nothing is gated by default",
  function()
    local world = newWorld()
    T.truthy(Footing.isOpen(world, nil))
    T.truthy(Footing.isOpen(world, false))
    T.truthy(Footing.isOpen(world, {}), "a definition without the flag is open")
    T.truthy(not Footing.isOpen(world, true))
    T.truthy(not Footing.isOpen(world, { footing = true }))
    T.truthy(not Footing.isOpen(world, { requiresFooting = true }))
    world.state.footing.held = true
    T.truthy(Footing.isOpen(world, true))
    T.truthy(Footing.isOpen(world, { footing = true }))
    T.truthy(Footing.isOpen(world, { requiresFooting = true }))
  end
)

T.test("gates: a slip does not close what Footing opened", function()
  local world = newWorld()
  world.state.footing.held, world.state.footing.slipped = true, true
  T.truthy(Footing.isOpen(world, { requiresFooting = true }))
end)

T.test("gates: a gated item is listed but cannot be bought until Footing is held", function()
  local world = newWorld()
  local def = buyable(world)
  flagged(def, function()
    T.eq(Market.cannotBuy(world, def.id, false), "needs Footing")
    T.eq(Market.cannotBuy(world, def.id, true), "needs Footing", "in town too")
    local money = Ledger.get(world, "money")
    local ok, reason = Market.order(world, def.id)
    T.truthy(not ok)
    T.eq(reason, "needs Footing")
    T.eq(Ledger.get(world, "money"), money, "a refused order costs nothing")
    T.truthy(not Market.buyInTown(world, def.id))
    world.state.footing.held = true
    T.eq(Market.cannotBuy(world, def.id, false), nil)
    T.truthy(Market.order(world, def.id))
  end)
end)

T.test("gates: cheat mode ignores the gate, and an ungated item is untouched", function()
  local world = newWorld()
  local def = buyable(world)
  flagged(def, function()
    Market.setCheat(world, true)
    T.eq(Market.cannotBuy(world, def.id, false), nil)
    Market.setCheat(world, false)
  end)
  T.eq(Market.cannotBuy(world, def.id, false), nil, "no flag, no gate")
end)

T.test("gates: the item card says it is locked and why, and never hides the item", function()
  local world = newWorld()
  local def = buyable(world)
  flagged(def, function()
    local info = ItemText.build(world, def.id, false)
    T.truthy(info.locked)
    T.eq(info.title, def.name)
    local found
    for _, line in ipairs(info.lines) do
      if line.text == tun.progress.gate.reason then
        found = line
      end
    end
    T.truthy(found, "a 'Right now' line carries the reason")
    T.eq(found.tone, "warn")
    T.eq(tun.progress.gate.reason, "Opens at Footing")
    world.state.footing.held = true
    info = ItemText.build(world, def.id, false)
    T.truthy(not info.locked)
  end)
  T.truthy(not ItemText.build(world, def.id, false).locked)
end)

T.test(
  "gates: the Progress panel lists flagged catalog items, then the named surfaces, and opens with Footing",
  function()
    local world = newWorld()
    local before = Goal.gates(world)
    T.eq(#before.items, #tun.progress.surfaces)
    T.truthy(not before.open)
    local def = reg:all("catalog")[1]
    flagged(def, function()
      local gates = Goal.gates(world)
      T.eq(#gates.items, #tun.progress.surfaces + 1)
      T.eq(gates.items[1].id, def.id)
      T.eq(gates.items[1].name, def.name)
      world.state.footing.held = true
      T.truthy(Goal.gates(world).open)
    end)
  end
)
