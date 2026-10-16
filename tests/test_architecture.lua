-- Guards for the architecture rules in CLAUDE.md / GDD §12.1.
local T = require("harness")

local function readFile(path)
  local fh = assert(io.open(path, "r"), "cannot open " .. path)
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = line:gsub("%-%-.*$", "") -- code only; comments may mention forbidden APIs
  end
  fh:close()
  return table.concat(lines, "\n")
end

local function simFiles()
  local files = {
    "game/src/sim/world.lua",
    "game/src/sim/grid.lua",
    "game/src/sim/pathfind.lua",
    "game/src/sim/landgen.lua",
    "game/src/sim/noise.lua",
    "game/src/sim/stats.lua",
    "game/src/sim/routine_rules.lua",
    "game/src/sim/minigames/fishing_model.lua",
    "game/src/meta/run.lua",
  }
  for _, name in ipairs(require("src.sim.systems.init")) do
    files[#files + 1] = "game/src/sim/systems/" .. name .. ".lua"
  end
  return files
end

T.test("sim modules never touch rendering or audio", function()
  for _, path in ipairs(simFiles()) do
    local text = readFile(path)
    T.falsy(text:find("love%.graphics"), path .. " uses love.graphics")
    T.falsy(text:find("love%.audio"), path .. " uses love.audio")
    T.falsy(text:find("love%.math%.random"), path .. " uses love.math.random (use world:rng)")
    T.falsy(text:find("math%.random"), path .. " uses math.random (use world:rng)")
  end
end)

-- Systems must not reach into each other's state (CLAUDE.md: "They never reach into another
-- system's internals"). Each top-level key of `world.state` is owned by one system file; anything
-- else goes through that system's accessor functions (Food.surplus, Crops.tileInUse, Land.truck ...).
-- The grid is the one genuinely shared structure (every system reads terrain and objects through
-- it), as are world.lua's own bookkeeping keys, so those are allow-listed. A key not listed here
-- (such as a nested field read through a local alias, `local state = world.state.food`) is ignored,
-- so add every new top-level state key to this table.
local STATE_OWNERS = {
  actors = "actors",
  alerts = "alerts",
  animals = "animals",
  nightly = "nightly",
  calendar = "calendar",
  cat = "cat",
  condition = "needs",
  crops = "crops",
  fields = "crops",
  finds = "finds",
  food = "food",
  income = "income",
  inventory = "inventory",
  land = "land",
  machines = "machines",
  ledger = "ledger",
  market = "market",
  marks = "marks",
  needs = "needs",
  perks = "perks",
  perksApplied = "perks",
  placement = "placement",
  power = "power",
  priorities = "tasks",
  routine = "routine",
  processing = "processing",
  spoilage = "spoilage",
  stand = "stand",
  startingKitGiven = "land",
  threats = "threats",
  water = "water",
  weather = "weather",
}
local SHARED_STATE = { grid = true, rng = true, seed = true, tick = true }

T.test("systems only touch the world.state keys they own", function()
  local files = { "game/src/sim/stats.lua" }
  for _, name in ipairs(require("src.sim.systems.init")) do
    files[#files + 1] = "game/src/sim/systems/" .. name .. ".lua"
  end
  for _, path in ipairs(files) do
    local owner = path:match("([%w_]+)%.lua$")
    local text = readFile(path)
    for key in text:gmatch("state%.([%a_][%w_]*)") do
      local keyOwner = STATE_OWNERS[key]
      T.truthy(
        SHARED_STATE[key] or keyOwner == nil or keyOwner == owner,
        path .. " reads world.state." .. key .. " (owned by " .. tostring(keyOwner) .. "); use its accessor"
      )
    end
  end
end)

-- The first-time tip state (D69) lives in the slot meta as meta.ftue and is owned by the ftue system;
-- everything else goes through its accessors (Ftue.begin, Ftue.current, Ftue.dismiss ...).
T.test("only the ftue system touches meta.ftue", function()
  local files = {
    "game/src/scenes/homestead.lua",
    "game/src/scenes/tips.lua",
    "game/src/scenes/menu.lua",
    "game/src/scenes/slots.lua",
  }
  for _, name in ipairs(require("src.sim.systems.init")) do
    if name ~= "ftue" then
      files[#files + 1] = "game/src/sim/systems/" .. name .. ".lua"
    end
  end
  for _, path in ipairs(files) do
    T.falsy(readFile(path):find("meta%.ftue"), path .. " reaches into meta.ftue; use the Ftue accessors")
  end
end)
