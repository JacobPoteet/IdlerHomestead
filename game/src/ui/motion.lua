-- Motion (GDD §9.4, D142): the UI's own clock and the helpers the screens use for dissolves and calm signals.
-- Presentation only; it never touches the sim. The clock is an effect clock (D97): `real` time, which runs
-- while the game is paused, so a signal keeps its rhythm in a menu. Reduce motion makes every change a
-- two-step one (src/ui/transition.lua) and holds signals still. Knobs: tuning.ui.motion.

local EffectClock = require("src.render.effect_clock")
local Plate = require("src.ui.plate")
local Settings = require("src.core.settings")
local Signals = require("src.ui.signals")
local Transition = require("src.ui.transition")
local theme = require("src.ui.theme")

local Motion = {}

local tuning
local clock
local scratch = { 0, 0, 0 } -- the ink handed back by `signal`, reused so a frame allocates nothing

--- Set when the screenshot driver wants every change settled at once (it is not a player setting).
Motion.settled = false

--- Hand over the live tuning tables once at start-up.
function Motion.setup(t)
  tuning = t
  clock = EffectClock.new(t.visuals.effectClock)
end

--- Advance the UI clock by real seconds.
function Motion.tick(dt)
  if clock then
    clock.cfg = tuning.visuals.effectClock -- F6 swaps the tuning tables
    clock:advance(dt, 1)
  end
end

--- UI time in seconds (real time).
function Motion.ready()
  return tuning ~= nil
end

function Motion.time()
  return clock and clock.real or 0
end

function Motion.reduce()
  return Settings.read("reduceMotion", false)
end

--- Do changes jump straight to their end (Reduce motion, or the driver settling shots)?
function Motion.instant()
  return Motion.settled or Settings.read("reduceMotion", false)
end

--- A new dissolve of `kind` ("wheel" | "book" | "card" | "lens").
function Motion.transition(kind)
  return Transition.new(tuning.ui.motion.kinds[kind])
end

--- Move a dissolve toward `open` this frame. Returns its coverage (0..1) for Dissolve.begin.
function Motion.step(transition, open, dt)
  local instant = Motion.instant()
  transition:set(open, instant)
  transition:update(dt, instant)
  return transition:coverage()
end

--- 0..1 how much the night light pool shows behind a paper book now: nothing by day, full at deep night, and
--- nothing with Settings > Ambient effects off.
function Motion.night()
  if not tuning or not Settings.read("ambientFx", true) then
    return 0
  end
  local n = tuning.ui.motion.night
  local k = (n.startLevel - Plate.level()) / (n.startLevel - n.fullLevel)
  return math.max(0, math.min(1, k))
end

local function mix(out, a, b, k)
  out[1], out[2], out[3] = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

--- The outline and glint of a plate that carries a signal. `kind`: "amber" (attention) or "red" (danger);
--- w, h: the plate in UI pixels; `salt` any number that tells plates apart. Returns ink (a table that is reused,
--- read it at once), and the glint pixel x, y on the plate (nil when none shows). Nothing here flashes: the
--- outline only ever moves a small step, a few times in a few seconds (tests/test_motion.lua).
function Motion.signal(kind, w, h, salt)
  if not tuning then
    return theme.colors.panelBorder -- no tuning yet (a test): a plain outline
  end
  local cfg = tuning.ui.motion
  local colors = theme.colors
  local reduce = Motion.reduce()
  local t = Motion.time()
  if kind == "red" then
    mix(scratch, colors.panelBorder, colors.danger, Signals.beatLevel(t, cfg.red, reduce))
    return scratch
  end
  local amber = cfg.amber
  mix(scratch, colors.panelBorder, colors.accent, reduce and amber.reducedSteady or amber.steady)
  if reduce then
    return scratch
  end
  local gx, gy = Signals.glint(t, amber, w, h, salt, tuning.ui.plate.cornerCut + 1)
  return scratch, gx, gy
end

return Motion
