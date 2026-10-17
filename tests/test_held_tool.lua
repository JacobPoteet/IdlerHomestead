-- The tool in the homesteader's hand (src/render/held_tool.lua, data/tuning/visuals.lua heldTool, #335): which
-- tool a job holds, which way the figure faces, and where the sprite goes.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Tasks = require("src.sim.systems.tasks")
local HeldTool = require("src.render.held_tool")
local manifest = require("assets.manifest")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.visuals.heldTool

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed))
end

T.test("held tool: every task that holds a tool is a real task, and the tool is one the hand can carry", function()
  local world = newWorld(8)
  for task, tool in pairs(cfg.tasks) do
    Tasks.get(world, task) -- errors on an unknown id
    T.truthy(tool == "hoe" or tool == "pail" or tool == "axe", task .. " holds " .. tostring(tool))
  end
end)

T.test(
  "held tool: till, plant, water, fetch and clear hold the hoe, pail and axe; harvest and walking hold nothing",
  function()
    local function held(task)
      return HeldTool.forJob(cfg, { task = task, path = {} })
    end
    T.eq(held("till"), "hoe")
    T.eq(held("plant"), "hoe")
    T.eq(held("water_crop"), "pail")
    T.eq(held("water_marked"), "pail")
    T.eq(held("fetch_water"), "pail")
    T.eq(held("fell"), "axe")
    T.eq(held("clear_marked"), "axe")
    T.eq(held("harvest"), nil)
    T.eq(held("move"), nil)
    T.eq(HeldTool.forJob(cfg, nil), nil, "no job, nothing in hand")
  end
)

T.test("held tool: every tool sprite the Icons can pick has a grip and a sprite in the manifest", function()
  for _, id in ipairs({ "icon_tool_hoe", "icon_tool_hatchet", "icon_tool_axe", "icon_tool_pail", "icon_tool_pail_big" }) do
    local entry = manifest.sprites[id]
    T.truthy(entry, id .. " is in the manifest")
    local grip = cfg.grips[id]
    T.truthy(grip, id .. " has a grip")
    T.truthy(grip[1] >= 0 and grip[1] < entry.w and grip[2] >= 0 and grip[2] < entry.h, id .. " grip is inside it")
  end
end)

T.test("held tool: the figure turns to its target while working and to its step while walking", function()
  local world = newWorld(8)
  local grid = world.state.grid
  local ax, ay = Grid.coords(grid, world.state.land.spawn)
  local actor = { x = ax, y = ay, prevX = ax, prevY = ay }
  local east = Grid.index(grid, ax + 1, ay)
  local west = Grid.index(grid, ax - 1, ay)
  T.eq(HeldTool.facing(cfg, grid, actor, nil, nil), 1, "defaults to right")
  T.eq(HeldTool.facing(cfg, grid, actor, nil, -1), -1, "standing still keeps the last way")
  T.eq(
    HeldTool.facing(cfg, grid, actor, { task = "till", path = {}, target = west }, 1),
    -1,
    "working turns to the target"
  )
  T.eq(HeldTool.facing(cfg, grid, actor, { task = "till", path = {}, target = east }, -1), 1)
  actor.prevX = ax + 0.5
  T.eq(
    HeldTool.facing(cfg, grid, actor, { task = "till", path = { east }, target = east }, 1),
    -1,
    "walking west faces west"
  )
end)

T.test("held tool: facing left mirrors the grip about the figure and flips the sprite", function()
  local x, y, sx = HeldTool.placement(cfg, "icon_tool_axe", 20, 100, 50, 1)
  T.eq(sx, 1)
  T.eq(x, 100 + cfg.hand[1] - cfg.grips.icon_tool_axe[1])
  T.eq(y, 50 + cfg.hand[2] - cfg.grips.icon_tool_axe[2])
  local lx, ly, lsx = HeldTool.placement(cfg, "icon_tool_axe", 20, 100, 50, -1)
  T.eq(lsx, -1)
  T.eq(ly, y, "same height")
  -- the grip column of the flipped sprite lands on the mirrored hand column: lx - gripX - 1 == 100 + 19 - handX
  T.eq(lx - cfg.grips.icon_tool_axe[1] - 1, 100 + 19 - cfg.hand[1])
end)
