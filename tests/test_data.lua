local T = require("harness")
local tuning = require("src.core.tuning")
local Registry = require("src.core.registry")

-- Tuning ---------------------------------------------------------------------

T.test("tuning: all domains load and are strict", function()
  local tun = tuning.load()
  T.eq(type(tun.time.tickRate), "number")
  T.errors(function()
    return tun.time.tickRat
  end, "tuning.time")
  T.errors(function()
    return tun.nonexistentDomain
  end, "tuning")
end)

T.test("tuning: every value has a comment (unit/intent)", function()
  for _, domain in ipairs(require("data.tuning.init")) do
    local path = "game/data/tuning/" .. domain .. ".lua"
    local fh = assert(io.open(path, "r"), "cannot open " .. path)
    for line in fh:lines() do
      -- Top-level knobs only; entries inside a table are covered by the table's own comment.
      local key = line:match("^  ([%a_][%w_]*)%s*=")
      if key then
        T.truthy(line:find("%-%-"), path .. ": '" .. key .. "' needs a comment with unit and intent")
      end
    end
    fh:close()
  end
end)

-- Registry -------------------------------------------------------------------

local schema = { name = "string", weight = "number?" }

T.test("registry: loads the game's content", function()
  local reg = Registry.new():loadAll()
  T.eq(reg:get("resources", "wood").name, "Wood")
  T.truthy(#reg:all("resources") > 0)
end)

T.test("registry: content cross-references point at real ids", function()
  local r = Registry.new():loadAll()
  for _, crop in ipairs(r:all("crops")) do
    T.truthy(r:has("resources", crop.seed), crop.id .. ".seed")
    T.truthy(r:has("resources", crop.produce), crop.id .. ".produce")
  end
  for _, obj in ipairs(r:all("objects")) do
    for res in pairs(obj.yields or {}) do
      T.truthy(r:has("resources", res), obj.id .. ".yields." .. res)
    end
  end
  local tun = tuning.load()
  for res in pairs(tun.run.startingResources) do
    T.truthy(r:has("resources", res), "run.startingResources." .. res)
  end
  for res in pairs(tun.landgen.clutterWeights) do
    T.truthy(r:has("objects", res), "landgen.clutterWeights." .. res)
  end
end)

T.test("registry: get/has/all", function()
  local reg = Registry.new()
  reg:addKind("things", { { id = "a", name = "A" }, { id = "b", name = "B", weight = 2 } }, schema)
  T.eq(reg:get("things", "b").weight, 2)
  T.eq(reg:get("things", "a").weight, nil) -- optional & absent reads as nil
  T.truthy(reg:has("things", "a"))
  T.falsy(reg:has("things", "zzz"))
  T.eq(reg:all("things")[2].id, "b")
  T.errors(function()
    reg:get("things", "zzz")
  end, "Unknown things id 'zzz'")
end)

T.test("registry: rejects bad definitions", function()
  T.errors(function()
    Registry.new():addKind("t", { { id = "a" } }, schema)
  end, "missing required field 'name'")
  T.errors(function()
    Registry.new():addKind("t", { { id = "a", name = 3 } }, schema)
  end, "should be string")
  T.errors(function()
    Registry.new():addKind("t", { { id = "a", name = "A", wieght = 1 } }, schema)
  end, "unknown field 'wieght'")
  T.errors(function()
    Registry.new():addKind("t", { { id = "a", name = "A" }, { id = "a", name = "B" } }, schema)
  end, "duplicate id")
end)

T.test("registry: definitions reject new fields and typo reads", function()
  local reg = Registry.new()
  reg:addKind("t", { { id = "a", name = "A" } }, schema)
  local def = reg:get("t", "a")
  T.errors(function()
    def.colour = "red"
  end, "Cannot add field")
  T.errors(function()
    return def.nmae
  end, "not a field")
end)

-- Storage fit (D60) --------------------------------------------------------------
-- Everything the game hands over must fit its store when that store is empty, using the base
-- capacity (the least a player can ever have: storage buildings only add to it). Otherwise a paid
-- order, a clearing job or a harvest could wait forever.

local function baseCapacity(reg, id)
  return reg:get("resources", id).capacity or math.huge
end

T.test("storage fit: every catalog item's gives fits its resource capacity", function()
  local reg = Registry.new():loadAll()
  for _, item in ipairs(reg:all("catalog")) do
    for res, amount in pairs(item.gives or {}) do
      T.truthy(
        amount <= baseCapacity(reg, res),
        string.format("catalog '%s' gives %d %s but its capacity is %s", item.id, amount, res, tostring(baseCapacity(reg, res)))
      )
    end
  end
end)

T.test("storage fit: clearing yields and crop harvests fit their capacities", function()
  local reg = Registry.new():loadAll()
  local farming = tuning.load().farming
  for _, obj in ipairs(reg:all("objects")) do
    for res, amount in pairs(obj.yields or {}) do
      local most = type(amount) == "table" and amount[2] or amount
      T.truthy(most <= baseCapacity(reg, res), string.format("object '%s' can yield %d %s, over its capacity", obj.id, most, res))
    end
  end
  for _, crop in ipairs(reg:all("crops")) do
    local mostProduce = math.floor(crop.yield * farming.soilYieldMax) + 1
    T.truthy(mostProduce <= baseCapacity(reg, crop.produce), "crop '" .. crop.id .. "' harvest is over its produce capacity")
    T.truthy(crop.seedReturn[2] <= baseCapacity(reg, crop.seed), "crop '" .. crop.id .. "' seed return is over its capacity")
  end
end)

T.test("storage fit: every recipe's output has a store, so a smoker batch can always be delivered", function()
  local reg = Registry.new():loadAll()
  for _, recipe in ipairs(reg:all("recipes")) do
    -- A batch bigger than the store is delivered in parts, which is fine; a zero store is not.
    T.truthy(baseCapacity(reg, recipe.output) >= 1, "recipe '" .. recipe.id .. "' output '" .. recipe.output .. "' has no room at all")
    T.truthy(recipe.batch >= 1)
  end
end)

T.test("storage fit: the guard rejects content that would never fit", function()
  -- The check above must be able to fail: a made-up item over a capacity is flagged by Market.neverFits.
  local World = require("src.sim.world")
  local reg = Registry.new():loadAll()
  local world = World.new({ registry = reg, tuning = tuning.load() }, World.newState(1))
  local Ledger = require("src.sim.systems.ledger")
  local Market = require("src.sim.systems.market")
  T.falsy(Market.neverFits(world, "fuel_can"))
  Ledger.setCapacity(world, "fuel", 4)
  T.truthy(Market.neverFits(world, "fuel_can"))
end)
