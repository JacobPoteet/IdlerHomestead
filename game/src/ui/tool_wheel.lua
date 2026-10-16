-- The tool wheel as pure geometry (GDD §9.4, D138, #294): where the wheel sits, where its wedges and the
-- ring of the highlighted tool go, and what a pointer at (x, y) is choosing. No drawing, no input, so it is
-- tested headless. Wedge directions are fixed by tuning (ui.wheel.wedges) and never move: a tool that is not
-- owned yet is greyed by the scene, never removed, so the directions stay learnable.

local Wheel = {}

local function wrap(deg)
  return (deg + 180) % 360 - 180
end

--- The radii and sizes for a view: small views (phones) get a tighter wheel.
function Wheel.sizes(cfg, view)
  if view.w < cfg.smallWidth then
    return cfg.small
  end
  return cfg.normal
end

--- Where the wheel opens for a press at (x, y): moved in from the view's edges so the wedges and the outer
--- ring stay on screen (it still chooses by direction from where it opened).
function Wheel.centre(x, y, view, sizes, pad)
  local reach = sizes.ring + sizes.ringItem / 2 + pad
  local cx = math.max(reach, math.min(view.w - reach, x))
  local cy = math.max(reach, math.min(view.h - reach, y))
  if view.w < 2 * reach then
    cx = view.w / 2
  end
  if view.h < 2 * reach then
    cy = view.h / 2
  end
  return cx, cy
end

--- Rectangles of the wedges and of `ringCount` ring items round the wedge `ringOf` (an id or nil), for a
--- wheel centred at (cx, cy). Returns { wedges = { id = rect }, ring = { rect } }.
function Wheel.layout(cx, cy, wedges, sizes, ringOf, ringCount, spread, highlight)
  local out = { wedges = {}, ring = {} }
  for _, w in ipairs(wedges) do
    local a = math.rad(w.angle)
    local size = w.id == highlight and sizes.selected or sizes.wedge
    out.wedges[w.id] = {
      x = math.floor(cx + math.cos(a) * sizes.radius - size / 2),
      y = math.floor(cy + math.sin(a) * sizes.radius - size / 2),
      w = size,
      h = size,
      angle = w.angle,
    }
  end
  if ringOf and ringCount > 0 then
    local base = Wheel.angleOf(wedges, ringOf)
    for k = 1, ringCount do
      local deg = base + (k - (ringCount + 1) / 2) * spread
      local a = math.rad(deg)
      out.ring[k] = {
        x = math.floor(cx + math.cos(a) * sizes.ring - sizes.ringItem / 2),
        y = math.floor(cy + math.sin(a) * sizes.ring - sizes.ringItem / 2),
        w = sizes.ringItem,
        h = sizes.ringItem,
        angle = deg,
      }
    end
  end
  return out
end

function Wheel.angleOf(wedges, id)
  for _, w in ipairs(wedges) do
    if w.id == id then
      return w.angle
    end
  end
  error("unknown wedge " .. tostring(id))
end

--- The angle between ring items for `count` items: `cfg.spread`, closer together when that would fan the
--- ring wider than `cfg.maxFan` degrees.
function Wheel.spread(cfg, count)
  if count <= 1 then
    return cfg.spread
  end
  return math.min(cfg.spread, cfg.maxFan / (count - 1))
end

--- What a pointer at (x, y) chooses on a wheel centred at (cx, cy): returns the wedge id (or nil inside the
--- dead zone, which cancels) and, past `sizes.subRadius`, the ring item index of that wedge's ring (or nil).
--- `ringCounts` maps a wedge id to how many ring items it has (nil or 0: no ring). `sticky` is the wedge
--- highlighted before the pointer went out past the wedges: while it has a ring the pointer stays on it, so
--- a wide ring can fan past the neighbouring wedges' directions.
function Wheel.pick(cx, cy, x, y, wedges, sizes, ringCounts, spread, sticky)
  local dx, dy = x - cx, y - cy
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < sizes.deadZone then
    return nil, nil
  end
  local deg = math.deg(math.atan2(dy, dx))
  local best, bestOff
  for _, w in ipairs(wedges) do
    local off = math.abs(wrap(deg - w.angle))
    if not bestOff or off < bestOff then
      best, bestOff = w, off
    end
  end
  if sticky and dist >= sizes.subRadius and ringCounts and (ringCounts[sticky] or 0) > 0 then
    for _, w in ipairs(wedges) do
      if w.id == sticky then
        best = w
      end
    end
  end
  local count = ringCounts and ringCounts[best.id] or 0
  if count > 0 and dist >= sizes.subRadius then
    -- The ring fans out round the wedge's direction; the nearest item by angle, clamped to the ends.
    local k = math.floor(wrap(deg - best.angle) / spread + (count + 1) / 2 + 0.5)
    return best.id, math.max(1, math.min(count, k))
  end
  return best.id, nil
end

return Wheel
