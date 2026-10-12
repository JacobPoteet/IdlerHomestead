-- A play session on one save slot: owns the slot data, the running World, the sim clock,
-- playtime, and autosaving. Sits between the app/scenes and the sim; no rendering here.

local Clock = require("src.core.clock")
local Rng = require("src.core.rng")
local World = require("src.sim.world")

local Session = {}
Session.__index = Session

--- opts: { store, slot, data, registry, tuning, events? }
--- `data` is the slot data (from Save:read or Save.newSlotData). Starts a new run if it has none.
function Session.new(opts)
  local tuning = opts.tuning
  local data = opts.data
  if not data.run then
    data.run = World.newState(opts.seed or Rng.freshSeed())
  end
  local self = setmetatable({
    store = opts.store,
    slot = opts.slot,
    data = data,
    tuning = tuning,
    world = World.new({ registry = opts.registry, tuning = tuning, events = opts.events }, data.run),
    clock = Clock.new({ tickRate = tuning.time.tickRate, maxTicksPerFrame = tuning.time.maxTicksPerFrame }),
    sinceSave = 0,
  }, Session)
  self.tick = function(dt)
    self.world:tick(dt)
  end
  return self
end

--- "active" (the player is directing) or "idle" (the routine takes over). See GDD §5.2.
function Session:setControl(mode)
  self.world.control = mode
end

--- Advance real time: runs due sim ticks, accrues playtime, autosaves on the interval.
function Session:update(dt)
  self.clock:advance(dt, self.tick)
  local header = self.data.header
  header.playtime = (header.playtime or 0) + dt
  self.sinceSave = self.sinceSave + dt
  if self.sinceSave >= self.tuning.save.autosaveInterval then
    self:save()
  end
end

--- Write the slot now. Returns true on success, or false + error.
function Session:save()
  self.sinceSave = 0
  local header = self.data.header
  for k, v in pairs(self.world:summarize()) do
    header[k] = v
  end
  return self.store:write(self.slot, self.data)
end

return Session
