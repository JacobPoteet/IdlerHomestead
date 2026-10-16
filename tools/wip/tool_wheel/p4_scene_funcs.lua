
-- The tool wheel (GDD §9.4, D138, #294) ---------------------------------------------------

-- Tools that only take part of what a tap can do: the Pail only waters, the Axe only clears and fells.
local TOOL_CATEGORIES = {
  pail = { water = true },
  axe = { clear = true, trees = true },
}

--- The wheel's wedge for the tool in hand.
function Homestead:currentTool()
  if self.mode == "place" then
    return "hammer"
  elseif self.mode == "plan" or self.seed or self.tool == "untill" then
    return "hoe"
  elseif self.tool == "rod" or self.tool == "pail" or self.tool == "axe" then
    return self.tool
  end
  return "hand"
end

--- The seed the Hoe takes when no packet is chosen: the last one used while it lasts, else the first crop
--- with seed to sow, else the first crop.
function Homestead:defaultSeed()
  local world = self.world
  local crops = world.registry:all("crops")
  local function has(id)
    return Ledger.get(world, world.registry:get("crops", id).seed) > 0
  end
  if self.lastSeed and has(self.lastSeed) then
    return self.lastSeed
  end
  for _, crop in ipairs(crops) do
    if has(crop.id) then
      return crop.id
    end
  end
  return crops[1] and crops[1].id
end

--- The ring a wedge fans out past the wheel: the Hoe's seed packets, then Untill and Plan field. More than
--- fit end in More, which opens the full tray. { { kind, crop?, icon, label } }.
function Homestead:ringItems(id)
  if id ~= "hoe" then
    return {}
  end
  local world, ui = self.world, self.app.ctx.tuning.ui
  local L = ui.labels
  local seeds = {}
  for _, crop in ipairs(world.registry:all("crops")) do
    seeds[#seeds + 1] = {
      kind = "seed",
      crop = crop.id,
      icon = Icons.packet(crop.id),
      label = crop.name .. " " .. Ledger.get(world, crop.seed),
      count = Ledger.get(world, crop.seed),
    }
  end
  local tail = {
    { kind = "untill", icon = "icon_verb_untill", label = L.untill },
    { kind = "plan", icon = "icon_verb_plan", label = L.plan },
  }
  local room = ui.wheel.maxRing - #tail
  local items = {}
  for i, s in ipairs(seeds) do
    if #seeds > room and i >= room then
      items[#items + 1] = { kind = "more", icon = "icon_tool_hoe", label = L.more }
      break
    end
    items[#items + 1] = s
  end
  for _, t in ipairs(tail) do
    items[#items + 1] = t
  end
  return items
end

--- Take a tool from the wheel or a key (D138): `id` is a wedge, `item` a ring item or nil.
function Homestead:equip(id, item)
  local world = self.world
  local L = self.app.ctx.tuning.ui.labels
  self.palette = nil
  if id == "hand" then
    self:setHand(nil, nil)
  elseif id == "hoe" then
    local kind = item and item.kind
    if kind == "untill" then
      self:setHand(nil, "untill")
    elseif kind == "more" then
      self.palette = "tools"
      self:layout()
    elseif kind == "plan" then
      if self.mode ~= "plan" then
        self:setHand(self.seed or self:defaultSeed(), nil)
      end
      self:pressPlan(love.timer.getTime())
    else
      local crop = item and item.crop or self.seed or self:defaultSeed()
      self.lastSeed = crop
      self:setHand(crop, nil)
    end
  elseif id == "pail" or id == "axe" or id == "rod" then
    self:setHand(nil, id)
  elseif id == "hammer" then
    local placeable = self:nextPlaceable()
    if placeable then
      local def = world.registry:get("objects", placeable)
      self.seed, self.tool = nil, nil
      self.mode, self.placing, self.moving, self.planStart = "place", placeable, nil, nil
      self:showToast("Tap where the " .. def.name:lower() .. " should go")
      self:layout()
    else
      self:setHand(nil, nil)
      self:showToast(L.hammerEmpty)
    end
  end
end

--- Equip by a label the old toolbar used ("Hand", "Rod", "Untill", "Plan field", "Place campfire"), for the
--- screenshot driver and keyboard-free scripts. Returns whether a label matched.
function Homestead:equipByLabel(label)
  local L = self.app.ctx.tuning.ui.labels
  local want = label:lower()
  if want == L.hand:lower() then
    self:equip("hand")
  elseif want == L.rod:lower() then
    self:equip("rod")
  elseif want == L.untill:lower() then
    self:equip("hoe", { kind = "untill" })
  elseif want == L.plan:lower() then
    self:equip("hoe", { kind = "plan" })
  elseif want == L.pail:lower() or want == L.axe:lower() then
    self:equip(want)
  elseif want:find("^" .. L.place:lower() .. " ") then
    self:equip("hammer")
  else
    return false
  end
  return true
end

--- Does a right press or a long-press at (x, y) open the wheel here (Input asks, D138)? Over the world only,
--- with no panel, card or tray in the way.
function Homestead:wantsWheel(x, y)
  return self.app:top() == self
    and not self.palette
    and not (self.card and self:overCard(x, y))
    and self:inWorldArea(x, y)
    and self:chipAt(x, y) == nil
end

--- Open the wheel at (x, y): held (the pointer chooses on release) or sticky (a tap chooses, D138).
function Homestead:openWheel(x, y, held)
  local view = self.app.view
  local cfg = self.app.ctx.tuning.ui.wheel
  local sizes = ToolWheel.sizes(cfg, view)
  local cx, cy = ToolWheel.centre(x, y, view, sizes, self.app.ctx.tuning.ui.hud.pad)
  self.palette = nil
  self.wheel = {
    cx = cx,
    cy = cy,
    px = x,
    py = y,
    at = love.timer.getTime(),
    held = held,
    highlight = held and nil or self:currentTool(),
  }
  self:layout()
end

--- Point the wheel at (x, y): which wedge and ring item would be taken.
function Homestead:aimWheel(x, y)
  local w = self.wheel
  local cfg = self.app.ctx.tuning.ui.wheel
  local sizes = ToolWheel.sizes(cfg, self.app.view)
  local counts = { hoe = #self:ringItems("hoe") }
  local sticky = w.highlight
  local spread = ToolWheel.spread(cfg, counts[sticky] or 0)
  w.px, w.py = x, y
  w.highlight, w.sub = ToolWheel.pick(w.cx, w.cy, x, y, cfg.wedges, sizes, counts, spread, sticky)
  if not w.highlight then
    w.highlight, w.sub = sticky, nil -- the middle keeps the last choice in sight; letting go there cancels
    w.cancel = true
  else
    w.cancel = false
  end
end

--- Take what the wheel points at and close it (or just close it from the middle).
function Homestead:releaseWheel()
  local w = self.wheel
  self.wheel = nil
  if w and w.highlight and not w.cancel then
    local items = self:ringItems(w.highlight)
    self:equip(w.highlight, w.sub and items[w.sub] or nil)
  else
    self:layout()
  end
end

--- A tap on a sticky wheel (opened by the tool badge or a key): a wedge or ring item takes it, elsewhere
--- closes the wheel.
function Homestead:tapWheel(x, y)
  local lay = self.wheelLayout
  local w = self.wheel
  if lay then
    for id, r in pairs(lay.wedges) do
      if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
        if self:ringItems(id)[1] and w.highlight ~= id then
          w.highlight, w.sub = id, nil -- a tool with a ring: the first tap shows its ring
          return
        end
        self.wheel = nil
        self:equip(id)
        return
      end
    end
    for k, r in ipairs(lay.ring) do
      if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
        self.wheel = nil
        self:equip(w.highlight, self:ringItems(w.highlight)[k])
        return
      end
    end
  end
  self.wheel = nil
  self:layout()
end

--- Input while the wheel is open; returns true when it took the action.
function Homestead:wheelAction(name, data)
  local w = self.wheel
  if name == "wheelMove" and w then
    self:aimWheel(data.x, data.y)
    return true
  elseif name == "wheelRelease" and w then
    self:aimWheel(data.x, data.y)
    self:releaseWheel()
    return true
  end
  if not w or w.held then
    return false
  end
  if name == "hover" then
    local lay = self.wheelLayout
    local function over(r)
      return data.x >= r.x and data.x < r.x + r.w and data.y >= r.y and data.y < r.y + r.h
    end
    for id, r in pairs(lay and lay.wedges or {}) do
      if over(r) and id ~= w.highlight then
        w.highlight, w.sub = id, nil
      end
    end
    for k, r in ipairs(lay and lay.ring or {}) do
      if over(r) then
        w.sub = k
      end
    end
    return true
  elseif name == "select" then
    self:tapWheel(data.x, data.y)
    return true
  elseif name == "press" or name == "release" or name == "pan" or name == "context" then
    return true -- the open wheel is solid
  elseif name == "cancel" or name == "toolWheel" then
    self.wheel = nil
    self:layout()
    return true
  end
  return false
end

--- The wheel over everything: the world dims round it, the six tools on plates (2x icons), the ring of the
--- highlighted tool, and its name under the ring. A held wheel waits `showDelay` before it shows, so a quick
--- flick equips without it.
function Homestead:drawWheel()
  local w = self.wheel
  self.wheelLayout = nil
  if not w then
    return
  end
  local ui = self.app.ctx.tuning.ui
  local cfg = ui.wheel
  if w.held and love.timer.getTime() - w.at < cfg.showDelay then
    return
  end
  local colors = theme.colors
  local world, view = self.world, self.app.view
  local sizes = ToolWheel.sizes(cfg, view)
  local items = self:ringItems(w.highlight)
  local spread = ToolWheel.spread(cfg, #items)
  local lay = ToolWheel.layout(w.cx, w.cy, cfg.wedges, sizes, w.highlight, #items, spread, w.highlight)
  self.wheelLayout = lay
  -- The world behind dims in two stepped bands round the wheel.
  love.graphics.setColor(cfg.dim)
  love.graphics.circle("fill", w.cx, w.cy, sizes.ring + sizes.ringItem / 2 + 6, 40)
  love.graphics.circle("fill", w.cx, w.cy, sizes.radius + sizes.selected / 2 + 6, 32)
  for _, wedge in ipairs(cfg.wedges) do
    local r = lay.wedges[wedge.id]
    local on = wedge.id == w.highlight
    Plate.draw(r.x, r.y, r.w, r.h, {
      ink = on and colors.accent or nil,
      lit = on and 0.35 or nil,
      base = on and colors.buttonHover or nil,
      weather = false,
    })
    local icon = Icons.tool(world, wedge.id)
    local sp = Assets.sprite(icon)
    Icons.draw(icon, r.x + math.floor((r.w - 2 * sp.w) / 2), r.y + math.floor((r.h - 2 * sp.h) / 2), 2)
  end
  for k, r in ipairs(lay.ring) do
    local item = items[k]
    local on = k == w.sub
    Plate.draw(r.x, r.y, r.w, r.h, { ink = on and colors.accent or nil, lit = on and 0.35 or nil, weather = false })
    local sp = Assets.sprite(item.icon)
    local scale = r.w >= 2 * sp.w + 4 and 2 or 1
    local ix, iy = r.x + math.floor((r.w - scale * sp.w) / 2), r.y + math.floor((r.h - scale * sp.h) / 2)
    Icons.draw(item.icon, ix, iy, scale)
    if item.count then
      local text = tostring(item.count)
      local tw = Text.measure(text, "small")
      Text.draw(text, r.x + r.w - tw - 2, r.y + r.h - 10, {
        size = "small",
        color = item.count > 0 and colors.text or colors.danger,
      })
    end
  end
  -- The name of what would be taken, under the wheel.
  local name = w.highlight and ui.labels[w.highlight] or ""
  if w.sub and items[w.sub] then
    name = name .. " · " .. items[w.sub].label
  end
  if name ~= "" then
    local tw, th = Text.measure(name, "body")
    local lx = math.floor(w.cx - tw / 2 - ui.hud.textPad)
    local ly = math.floor(w.cy + sizes.radius + sizes.selected / 2 + 6)
    if lay.ring[1] and w.sub then
      ly = math.floor(w.cy + sizes.ring + sizes.ringItem / 2 + 4)
    end
    ly = math.min(ly, view.h - th - 12)
    Plate.draw(lx, ly, tw + 2 * ui.hud.textPad, th + 6, { weather = false })
    Text.draw(name, lx + ui.hud.textPad, ly + 4, { color = colors.accent })
  end
  -- Where the pointer is, while the wheel is held.
  if w.held then
    love.graphics.setColor(colors.accent)
    love.graphics.rectangle("fill", math.floor(w.px) - 1, math.floor(w.py) - 1, 3, 3)
  end
end
