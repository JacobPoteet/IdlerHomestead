-- Lenses (GDD §9.4, D141, D145): which lens is on, why, and where its side card goes. Pure (no drawing), so
-- the switch-on routes are tested headless. One lens at a time, no lens buttons: a lens comes on with the tool in
-- hand (the Pail shows Water), with a placement (a panel shows Power, a pump shows Water), from its vital, or
-- when a device is tapped. A lens that came with a trigger goes off when the trigger ends; a lens the player
-- switched on (vital, tap) stays until the card's Close or the vital is tapped again.

local Water = require("src.sim.systems.water")

local Lens = {}
Lens.__index = Lens

--- The lens an object definition belongs to ("water" | "power"), or nil. Water wins: a pump draws power but is
--- a water thing.
function Lens.forObject(def)
  if def.placeOn == "waterTable" or Water.irrigationKind(def) or def.waterSource then
    return "water"
  end
  if def.source or def.sink or def.battery then
    return "power"
  end
  return nil
end

--- The lens a tool in hand shows, from `tuning.ui.lens.tools` (tool id -> lens id).
function Lens.forTool(cfg, tool)
  return tool and rawget(cfg.tools, tool) or nil
end

--- The lens a chip (vital) opens, from `tuning.ui.lens.vitals` (chip id -> lens id).
function Lens.forVital(cfg, chip)
  return rawget(cfg.vitals, chip)
end

--- A lens state. `cfg` = tuning.ui.lens.
function Lens.new(cfg)
  return setmetatable({ cfg = cfg, id = nil, source = nil, trigger = nil, dismissed = nil }, Lens)
end

--- The lens showing now ("power" | "water") or nil.
function Lens:active()
  return Lens.forced or self.id
end

--- A lens the F8 editor holds on to look at it (module state, a session, never saved); nil lets go.
Lens.forced = nil

--- Switch a lens on by the player's hand ("vital" or "select"): it stays until dismissed.
function Lens:show(id, source)
  self.id, self.source = id, source or "vital"
  self.dismissed = nil
end

--- A vital was tapped: on when off or showing another lens, off when it is already this lens. Returns true when
--- the lens is now on.
function Lens:toggle(id)
  if self.id == id then
    self:dismiss()
    return false
  end
  self:show(id, "vital")
  return true
end

--- The player closed the lens. A lens held by a trigger (a tool, a placement) stays closed until that trigger
--- changes, so the Pail does not reopen it a frame later.
function Lens:dismiss()
  if self.trigger and self.id == self.trigger then
    self.dismissed = self.trigger
  end
  self.id, self.source = nil, nil
end

--- Call every frame with the lens the current tool or placement wants (nil for none). A new trigger switches its
--- lens on; when the trigger ends a lens that came with it goes off.
function Lens:sync(trigger)
  if trigger ~= self.trigger then
    local before = self.trigger
    self.trigger = trigger
    self.dismissed = nil
    if trigger then
      self.id, self.source = trigger, "trigger"
    elseif before and self.source == "trigger" then
      self.id, self.source = nil, nil
    end
  elseif trigger and self.id == nil and self.dismissed ~= trigger then
    self.id, self.source = trigger, "trigger"
  end
end

--- Where the card goes. `view` = { w, h }, `bounds` = { top, bottom } (the free band between the HUD's plates),
--- `collapsed` = show only the strip. Returns { rect = { x, y, w, h }, layout = "side" | "sheet", strip = h }.
function Lens.cardRect(cfg, view, bounds, collapsed, touch)
  local margin = cfg.margin
  local strip = math.max(cfg.stripH, touch)
  local top, bottom = bounds.top + margin, bounds.bottom - margin
  local avail = bottom - top
  local layout, x, y, w, h
  if view.w > view.h then
    layout = "side"
    w = math.min(view.h < cfg.tallMin and cfg.sideWidthShort or cfg.sideWidth, view.w - 2 * margin)
    x = view.w - margin - w
    y, h = top, avail
  else
    layout = "sheet"
    w = math.min(view.w - 2 * margin, cfg.sheetMaxWidth)
    x = math.floor((view.w - w) / 2)
    h = math.floor(avail * cfg.sheetShare)
    y = bottom - h
  end
  if collapsed then
    h = strip
    if layout == "sheet" then
      y = bottom - h
    end
  end
  return { rect = { x = x, y = y, w = w, h = h }, layout = layout, strip = strip }
end

return Lens
