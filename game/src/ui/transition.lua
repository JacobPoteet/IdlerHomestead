-- A dissolve's state (GDD §9.4, D142): how far something that opens and closes (the tool wheel, a book, a
-- card, a lens) has come in, on real time. Pure, so the timing is tested headless. `coverage` is the amount
-- the dither lets through (src/render/dissolve.lua), moved in a few steps so it reads as a pixel-art
-- dissolve and not a fade. With Reduce motion (or the driver) the change is a two-step one: the thing is
-- either away (0) or there (1), never between, and nothing animates.

local Transition = {}
Transition.__index = Transition

--- `cfg` = one of tuning.ui.motion.kinds: { open = seconds, close = seconds, steps = levels }.
function Transition.new(cfg)
  return setmetatable({ cfg = cfg, amount = 0, target = 0 }, Transition)
end

--- Say whether the thing should be there (`open`). `instant` jumps straight to it. Safe to call every frame.
function Transition:set(open, instant)
  self.target = open and 1 or 0
  if instant then
    self.amount = self.target
  end
end

--- Advance by real seconds `dt`. Only ever moves toward the target, at the open or close rate.
function Transition:update(dt, instant)
  if instant then
    self.amount = self.target
  elseif self.amount < self.target then
    self.amount = math.min(self.target, self.amount + dt / math.max(self.cfg.open, 1e-6))
  elseif self.amount > self.target then
    self.amount = math.max(self.target, self.amount - dt / math.max(self.cfg.close, 1e-6))
  end
end

--- 0..1 the dither lets through: the amount rounded to `steps` levels (0 and 1 are always exact).
function Transition:coverage()
  local steps = self.cfg.steps
  if steps <= 0 then
    return self.amount
  end
  return math.floor(self.amount * steps + 0.5) / steps
end

--- Is it still moving?
function Transition:busy()
  return self.amount ~= self.target
end

--- Does any of it show (or is it about to)? False once it has closed all the way.
function Transition:shown()
  return self.amount > 0 or self.target > 0
end

return Transition
