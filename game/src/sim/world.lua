-- The simulation world: owns one run's state and ticks the systems in order.
--
-- Pure game logic. Nothing in src/sim may call love.graphics/love.audio, so the sim can be
-- tested headless and fast-forwarded (GDD §12.1).
--
-- `world.state` is plain, serializable data and is exactly what goes into the save's `run`.
-- Systems are modules listed in src/sim/systems/init.lua. Each may define:
--   init(world)              set up its slice of world.state (also called on loaded saves)
--   tick(world, dt)          advance one fixed step
--   summarize(world, out)    add fields to the save-slot header (year, season, ...)

local Events = require("src.core.events")
local Rng = require("src.core.rng")

local World = {}
World.__index = World

--- Fresh state for a new run.
function World.newState(seed)
  return { seed = seed, tick = 0, rng = {} }
end

--- ctx: { registry, tuning, events?, meta? }. state: from World.newState or a loaded save.
--- `meta` is the save slot's persistent career data (survives failed runs); systems may record
--- into it (e.g. the fish guide). Tests can omit it.
function World.new(ctx, state)
  assert(ctx.registry and ctx.tuning, "World.new requires ctx.registry and ctx.tuning")
  assert(type(state) == "table" and state.seed, "World.new requires a state with a seed")
  local self = setmetatable({
    state = state,
    registry = ctx.registry,
    tuning = ctx.tuning,
    events = ctx.events or Events.new(),
    meta = ctx.meta or {},
    systems = {},
    rngStreams = {},
  }, World)
  for _, name in ipairs(require("src.sim.systems.init")) do
    local system = require("src.sim.systems." .. name)
    self.systems[#self.systems + 1] = system
    if system.init then
      system.init(self)
    end
  end
  return self
end

--- A named random stream ("land", "weather", ...), persisted in the run state.
function World:rng(name)
  local stream = self.rngStreams[name]
  if not stream then
    local store = self.state.rng[name]
    if not store then
      store = { s = Rng.deriveSeed(self.state.seed, name) }
      self.state.rng[name] = store
    end
    stream = Rng.attach(store)
    self.rngStreams[name] = stream
  end
  return stream
end

--- Advance the simulation by one fixed step of `dt` seconds.
function World:tick(dt)
  self.state.tick = self.state.tick + 1
  local systems = self.systems
  for i = 1, #systems do
    local tick = systems[i].tick
    if tick then
      tick(self, dt)
    end
  end
end

--- Summary for the save-slot header, contributed by systems.
function World:summarize()
  local out = {}
  for _, system in ipairs(self.systems) do
    if system.summarize then
      system.summarize(self, out)
    end
  end
  return out
end

return World
