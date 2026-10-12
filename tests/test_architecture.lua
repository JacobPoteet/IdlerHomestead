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
    "game/src/sim/minigames/fishing_model.lua",
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
