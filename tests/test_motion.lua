-- Dither dissolves and calm signals (GDD §9.4, D142, #298): the dissolve's timing and its Reduce motion
-- two-step, the amber glint and red beat schedules, and the flash limit on both (nothing changes its look
-- more than tuning.ui.motion.maxChangesPerSecond times a second, and never by a big step).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Signals = require("src.ui.signals")
local Transition = require("src.ui.transition")

local tun = tuningLoader.load()
local M = tun.ui.motion
local FPS = 60

T.test("transition: opens and closes at the tuned rates, only ever toward its target", function()
  local cfg = M.kinds.book
  local t = Transition.new(cfg)
  T.eq(t:coverage(), 0)
  T.falsy(t:shown(), "starts away")
  t:set(true)
  T.truthy(t:busy() and t:shown())
  t:update(cfg.open / 2)
  T.near(t.amount, 0.5, 1e-9, "half the open time is half way")
  local before = t.amount
  t:update(cfg.open * 3)
  T.eq(t.amount, 1, "settles at 1 and no further")
  T.falsy(t:busy())
  t:set(false)
  t:update(cfg.close / 4)
  T.near(t.amount, 0.75, 1e-9, "closes at the close rate")
  T.truthy(t.amount < 1 and t.amount > before - 1)
  t:update(cfg.close * 3)
  T.eq(t.amount, 0)
  T.falsy(t:shown(), "gone once closed")
end)

T.test("transition: coverage moves in whole steps and is exact at both ends", function()
  for kind, cfg in pairs({ wheel = M.kinds.wheel, book = M.kinds.book, card = M.kinds.card, lens = M.kinds.lens }) do
    local t = Transition.new(cfg)
    t:set(true)
    local seen, last = {}, -1
    for _ = 1, 400 do
      t:update(1 / FPS)
      local c = t:coverage()
      T.truthy(c >= last, kind .. " coverage never goes back while opening")
      last = c
      seen[string.format("%.4f", c)] = true
    end
    local count = 0
    for _ in pairs(seen) do
      count = count + 1
    end
    T.truthy(count <= cfg.steps + 1, kind .. " coverage takes at most steps + 1 values")
    T.eq(t:coverage(), 1)
  end
end)

T.test("transition: Reduce motion is a two-step change, away or there, never between", function()
  local t = Transition.new(M.kinds.book)
  t:set(true, true)
  T.eq(t.amount, 1, "opening jumps straight to there")
  T.eq(t:coverage(), 1)
  t:update(0.01, true)
  T.eq(t:coverage(), 1)
  t:set(false, true)
  T.eq(t:coverage(), 0, "closing jumps straight to away")
  T.falsy(t:busy())
  -- The same through update alone (a transition already set, then Reduce motion turned on).
  local u = Transition.new(M.kinds.wheel)
  u:set(true)
  u:update(0.01)
  T.truthy(u:busy())
  u:update(0.01, true)
  T.eq(u:coverage(), 1)
end)

T.test("transition: a reversal part way turns round from where it is", function()
  local cfg = M.kinds.card
  local t = Transition.new(cfg)
  t:set(true)
  t:update(cfg.open / 2)
  t:set(false)
  t:update(cfg.close / 4)
  T.near(t.amount, 0.25, 1e-9)
end)

-- Sample a schedule at 60 fps over `seconds` and return the most changes in any one second, the biggest
-- single step, and the total number of changes. `sample(t)` returns a number (a level) or a boolean.
local function audit(sample, seconds)
  local stamps, maxStep, total, prev = {}, 0, 0, nil
  local worst = 0
  for i = 0, seconds * FPS do
    local t = i / FPS
    local v = sample(t)
    if type(v) == "boolean" then
      v = v and 1 or 0
    end
    if prev and v ~= prev then
      total = total + 1
      maxStep = math.max(maxStep, math.abs(v - prev))
      stamps[#stamps + 1] = t
    end
    prev = v
    local inWindow = 0
    for k = #stamps, 1, -1 do
      if t - stamps[k] < 1 then
        inWindow = inWindow + 1
      else
        break
      end
    end
    worst = math.max(worst, inWindow)
  end
  return worst, maxStep, total
end

T.test("amber: one glint of `hold` seconds every `every` seconds, on a pixel of the outline", function()
  local cfg = M.amber
  local on = 0
  local last
  for i = 0, 60 * FPS do
    local t = i / FPS
    local x, y = Signals.glint(t, cfg, 40, 30, 7, 3)
    if x then
      on = on + 1
      local edge = x == 0 or y == 0 or x == 39 or y == 29
      T.truthy(edge, "the glint sits on the outline ring")
      T.truthy(x >= 0 and x < 40 and y >= 0 and y < 30)
      T.eq(Signals.glinting(t, cfg, 7), true)
      last = x .. "," .. y
    else
      T.eq(Signals.glinting(t, cfg, 7), false)
    end
  end
  T.near(on / FPS, 60 / cfg.every * cfg.hold, 0.2, "lit for hold seconds in every cycle")
  T.truthy(last, "it glinted")
end)

T.test("amber: the glint moves between cycles and never lands on a cut corner", function()
  local cfg = M.amber
  local places, margin = {}, 3
  for step = 0, 40 * cfg.every / 0.05 do
    local x, y = Signals.glint(step * 0.05, cfg, 24, 24, 3, margin)
    if x then
      places[x .. "," .. y] = true
      T.truthy((x >= margin and x < 24 - margin) or (y >= margin and y < 24 - margin), "clear of the corners")
    end
  end
  local count = 0
  for _ in pairs(places) do
    count = count + 1
  end
  T.truthy(count > 5, "it does not sit in one place")
  T.eq(Signals.glint(0, cfg, 4, 4, 1, 3), nil, "a plate too small for a ring has no glint")
end)

T.test("amber: the glint is within the flash limit", function()
  local worst, _, total = audit(function(t)
    return Signals.glinting(t, M.amber, 11)
  end, 60)
  T.truthy(worst <= M.maxChangesPerSecond, "changes in one second: " .. worst)
  T.truthy(total > 0)
  T.truthy(M.amber.every / 2 >= 1 / M.maxChangesPerSecond, "glints are spaced far apart")
end)

T.test("red: a three-frame beat, slow, in small steps", function()
  local cfg = M.red
  local frames = {}
  for i = 0, 5 * cfg.every * FPS do
    frames[Signals.beatFrame(i / FPS, cfg)] = true
  end
  T.truthy(frames[1] and frames[2] and frames[3], "all three frames show")
  T.eq(Signals.beatFrame(0, cfg), 1, "the beat starts at rest")
  T.eq(Signals.beatLevel(0, cfg), cfg.levels[1])
  local worst, maxStep = audit(function(t)
    return Signals.beatLevel(t, cfg)
  end, 60)
  T.truthy(worst <= M.maxChangesPerSecond, "changes in one second: " .. worst)
  T.truthy(maxStep <= 0.5, "no step bigger than half the contrast: " .. maxStep)
  T.truthy(cfg.every >= 2, "a slow beat")
end)

T.test("red: the rest frame holds most of the beat, frames 2 and 3 are short", function()
  local cfg = M.red
  local count = { 0, 0, 0 }
  local n = 20 * cfg.every * FPS
  for i = 0, n - 1 do
    local f = Signals.beatFrame(i / FPS, cfg)
    count[f] = count[f] + 1
  end
  T.near(count[1] / n, cfg.rest, 0.02)
  T.near(count[3] / n, (1 - cfg.rest) / 3, 0.02)
  T.near(count[2] / n, 2 * (1 - cfg.rest) / 3, 0.02)
end)

T.test("reduce motion: red holds one level and amber has no glint pixel to move", function()
  local cfg = M.red
  for i = 0, 10 * FPS do
    T.eq(Signals.beatLevel(i / FPS, cfg, true), cfg.levels[3], "red holds still")
  end
  T.truthy(M.amber.reducedSteady >= M.amber.steady, "the steady amber carries the cue by itself")
end)

T.test("no flash: every signal and dissolve knob keeps within the limit", function()
  local limit = M.maxChangesPerSecond
  T.truthy(limit <= 3, "the flash limit is at most 3 changes a second")
  -- Two changes per glint, one glint per `every`; four changes per beat.
  T.truthy(2 / M.amber.every <= limit)
  T.truthy(4 / M.red.every <= limit)
  for i = 2, #M.red.levels do
    T.truthy(M.red.levels[i] >= M.red.levels[i - 1], "the beat's levels climb")
    T.truthy(M.red.levels[i] - M.red.levels[i - 1] <= 0.5, "in small steps")
  end
  T.truthy(M.red.levels[1] > 0, "the rest outline never switches fully off")
  T.truthy(M.amber.hold < M.amber.every, "a glint ends before the next one starts")
end)
