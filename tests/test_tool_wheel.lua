-- The tool wheel's geometry (GDD §9.4, D138, #294): every direction picks its wedge, the dead zone
-- cancels, a ring is chosen by angle past the wedges (and stays on its tool while it fans wide), and the
-- wheel opens moved in from the edges so it fits on every view.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Wheel = require("src.ui.tool_wheel")

local tun = tuningLoader.load()
local W = tun.ui.wheel
local wedges = W.wedges
local S = W.normal

local function at(angle, dist)
  local a = math.rad(angle)
  return 100 + math.cos(a) * dist, 100 + math.sin(a) * dist
end

T.test("wheel: six fixed wedges, every direction picks the nearest one", function()
  T.eq(#wedges, 6)
  for _, w in ipairs(wedges) do
    for _, off in ipairs({ -25, 0, 25 }) do
      local x, y = at(w.angle + off, S.radius)
      local id, sub = Wheel.pick(100, 100, x, y, wedges, S, {}, W.spread)
      T.eq(id, w.id, w.id .. " at " .. off .. " degrees off")
      T.eq(sub, nil)
    end
  end
end)

T.test("wheel: the dead zone in the middle chooses nothing", function()
  local x, y = at(0, S.deadZone - 1)
  T.eq(Wheel.pick(100, 100, x, y, wedges, S, {}, W.spread), nil)
end)

T.test("wheel: past the wedges a ring item is chosen by angle, clamped to its ends", function()
  local counts = { hoe = 3 }
  local spread = Wheel.spread(W, 3)
  local hoe = Wheel.angleOf(wedges, "hoe")
  for k = 1, 3 do
    local x, y = at(hoe + (k - 2) * spread, S.ring)
    local id, sub = Wheel.pick(100, 100, x, y, wedges, S, counts, spread)
    T.eq(id, "hoe")
    T.eq(sub, k, "item " .. k)
  end
  local x, y = at(hoe, S.radius) -- on the wedge, not out on the ring
  T.eq(select(2, Wheel.pick(100, 100, x, y, wedges, S, counts, spread)), nil)
end)

T.test("wheel: a wide ring stays on its tool past the neighbouring wedges' directions", function()
  local count = W.maxRing
  local spread = Wheel.spread(W, count)
  T.truthy(spread * (count - 1) <= W.maxFan + 0.001, "the fan is capped")
  local hoe = Wheel.angleOf(wedges, "hoe")
  local x, y = at(hoe + (count - 1) / 2 * spread, S.ring) -- the last item, past halfway to the pail
  local id, sub = Wheel.pick(100, 100, x, y, wedges, S, { hoe = count }, spread, "hoe")
  T.eq(id, "hoe")
  T.eq(sub, count)
end)

T.test("wheel: it opens moved in from the edges so the ring stays on screen", function()
  for _, view in ipairs({ { w = 640, h = 360 }, { w = 390, h = 844 }, { w = 844, h = 390 }, { w = 260, h = 500 } }) do
    local sizes = Wheel.sizes(W, view)
    for _, p in ipairs({ { 0, 0 }, { view.w, view.h }, { view.w / 2, 2 }, { 3, view.h / 2 } }) do
      local cx, cy = Wheel.centre(p[1], p[2], view, sizes, tun.ui.hud.pad)
      local spread = Wheel.spread(W, W.maxRing)
      for _, w in ipairs(wedges) do
        local out = Wheel.layout(cx, cy, wedges, sizes, w.id, W.maxRing, spread, w.id)
        for _, r in pairs(out.wedges) do
          T.truthy(r.x >= 0 and r.y >= 0 and r.x + r.w <= view.w and r.y + r.h <= view.h, "a wedge is off screen")
        end
        for _, r in ipairs(out.ring) do
          T.truthy(r.x >= 0 and r.y >= 0 and r.x + r.w <= view.w and r.y + r.h <= view.h, "a ring item is off screen")
        end
      end
    end
  end
end)

T.test("wheel: wedges never overlap each other, and touch-sized", function()
  for _, sizes in ipairs({ W.normal, W.small }) do
    local out = Wheel.layout(200, 200, wedges, sizes, nil, 0, W.spread, "hoe")
    local list = {}
    for _, r in pairs(out.wedges) do
      list[#list + 1] = r
      T.truthy(r.w >= tun.input.minTouchTarget, "a wedge is under the touch size")
    end
    for i = 1, #list do
      for j = i + 1, #list do
        local a, b = list[i], list[j]
        T.falsy(a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h, "two wedges overlap")
      end
    end
  end
end)
