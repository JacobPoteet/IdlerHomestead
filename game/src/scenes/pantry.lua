-- Pantry & food rules (GDD §6.2): how many days to keep, how much to preserve for winter, and
-- per-item pins. Everything else goes in the sell crate for the next truck trip.
-- Perishables show their nightly spoilage rate, tonight's expected loss and a warning when a
-- meaningful amount will rot (D68, #151); a footer says what slows it.

local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Spoilage = require("src.sim.systems.spoilage")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Scroll = require("src.ui.scroll")
local SpoilText = require("src.ui.spoil_text")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Pantry = { name = "pantry" }
Pantry.__index = Pantry

local LIST_TOP = 108 -- virtual pixels from the panel top to the first row of goods
local ROW_H = 22
local NOTE_H = 10 -- extra height under a perishable's row for its spoilage line
local PIN_LABELS = { [false] = "Auto", keep = "Keep", preserve = "Preserve", sell = "Sell" }
local PIN_CYCLE = { [false] = "keep", keep = "preserve", preserve = "sell", sell = false }

function Pantry.new(world)
  return setmetatable({ world = world }, Pantry)
end

function Pantry:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

-- Goods worth showing: in stock and edible or sellable. Perishables come first so their spoilage
-- lines are never the ones cut off when the panel is short.
function Pantry:goods()
  local fresh, rest = {}, {}
  for _, res in ipairs(self.world.registry:all("resources")) do
    if Ledger.get(self.world, res.id) > 0 and (res.calories or res.value) then
      local list = res.spoilDays and fresh or rest
      list[#list + 1] = res
    end
  end
  for _, res in ipairs(rest) do
    fresh[#fresh + 1] = res
  end
  return fresh
end

function Pantry:resize(view)
  self.box = Panel.box(view, 400, view.h - 16)
  self:layout()
end

-- The footer: last night's loss, tonight's warning, what slows spoilage. Returns lines and height.
function Pantry:footer()
  local world, b = self.world, self.box
  local lines = {}
  local loss = Food.lastLoss(world)
  if loss then
    lines[#lines + 1] = { text = "Last night: " .. SpoilText.items(world, loss.lost) .. " spoiled.", color = theme.colors.textDim }
  end
  local tonight = Spoilage.tonight(world)
  if tonight.warn then
    lines[#lines + 1] = {
      text = string.format("Warning: about %d units will rot tonight. Eat, sell or preserve them.", math.floor(tonight.expected + 0.5)),
      color = theme.colors.danger,
    }
  end
  if #tonight.list > 0 then
    lines[#lines + 1] = { text = SpoilText.slowing(world), color = theme.colors.textDim }
  end
  if Food.pantryAuto(world) then
    lines[#lines + 1] = { text = "Auto pantry: fresh food stays only as long as it keeps. The rest is for sale.", color = theme.colors.textDim }
  end
  local h = 0
  for _, line in ipairs(lines) do
    line.h = Text.wrappedHeight(line.text, "small", b.w - 24)
    h = h + line.h + 2
  end
  return lines, h
end

function Pantry:layout()
  local b, world = self.box, self.world
  local food = world.state.food
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  local function stepper(y, get, set)
    self.buttons:add({ x = b.x + b.w - 70, y = y, w = 26, h = 22, label = "-", onPress = function()
      set(get() - 1)
      self:layout()
    end })
    self.buttons:add({ x = b.x + b.w - 38, y = y, w = 26, h = 22, label = "+", onPress = function()
      set(get() + 1)
      self:layout()
    end })
  end
  self.pantryY, self.winterY = b.y + 40, b.y + 66
  stepper(self.pantryY, function()
    return food.pantryDays
  end, function(v)
    Food.setDays(world, v, food.winterDays)
  end)
  stepper(self.winterY, function()
    return food.winterDays
  end, function(v)
    Food.setDays(world, food.pantryDays, v)
  end)
  -- Automatic pantry (D68): perishables kept only as long as they keep. A stepper press turns it off.
  self.buttons:add({
    x = b.x + b.w - 70 - 58,
    y = self.pantryY,
    w = 54,
    h = 22,
    label = "Auto",
    selected = Food.pantryAuto(world),
    onPress = function()
      Food.setPantryAuto(world, not Food.pantryAuto(world))
      self:layout()
    end,
  })
  -- The goods list scrolls (D70, #170): rows are laid out from the top of the list minus the scroll
  -- offset, only the ones in view get buttons, and the footer and hint line keep their places.
  self.rows = {}
  self.rowButtons = self.rowButtons or Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons:clear()
  self.footerLines, self.footerH = self:footer()
  local ui = self.app.ctx.tuning.ui
  local goods = self:goods()
  local contentH = 0
  for _, res in ipairs(goods) do
    contentH = contentH + ROW_H + (Spoilage.info(world, res.id) and NOTE_H or 0)
  end
  local top = b.y + LIST_TOP
  local viewH = math.max(ROW_H, b.y + b.h - 6 - self.footerH - top)
  self.overflow = Scroll.overflows(contentH, viewH)
  if self.overflow then
    viewH = math.max(ROW_H, viewH - ui.scrollHintHeight)
  end
  self.contentH = contentH
  self.view = { x = b.x, y = top, w = b.w, h = viewH }
  self.scroll = Scroll.clamp(self.scroll or 0, contentH, viewH)
  local y = top - self.scroll
  for _, res in ipairs(goods) do
    local info = Spoilage.info(world, res.id)
    local h = ROW_H + (info and NOTE_H or 0)
    if y + h > top and y < top + viewH then
      self.rows[#self.rows + 1] = { res = res, y = y, info = info }
      local pin = food.pins[res.id] or false
      if res.value then
        -- "Not at the stand" pin (D62): a sellable good marked Truck stays in the crate for the truck.
        local truckOnly = Food.truckOnly(world, res.id)
        self.rowButtons:add({
          x = b.x + b.w - 84 - 62,
          y = y,
          w = 58,
          h = ROW_H - 2,
          label = truckOnly and "Truck" or "Stand",
          selected = truckOnly,
          onPress = function()
            Food.setTruckOnly(world, res.id, not truckOnly)
            self:layout()
          end,
        })
      end
      self.rowButtons:add({
        x = b.x + b.w - 84,
        y = y,
        w = 72,
        h = ROW_H - 2,
        label = PIN_LABELS[pin],
        selected = pin ~= false,
        onPress = function()
          Food.setPin(world, res.id, PIN_CYCLE[pin] or nil)
          self:layout()
        end,
      })
    end
    y = y + h
  end
end

--- Scroll the goods list by dragging `dy` or turning the wheel `steps` notches, then rebuild.
function Pantry:scrollBy(offset)
  self.scroll = offset
  self:layout()
end

local function inside(r, x, y)
  return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Pantry:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function Pantry:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  local view = self.view
  if name == "press" or name == "select" or name == "hover" then
    -- Row buttons only answer inside the list's window: a half-scrolled row must not reach out of it.
    if inside(view, data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif name == "pan" and self.overflow then
    self:scrollBy(Scroll.byDrag(self.scroll, data.dy, self.contentH, view.h)) -- the list follows the finger
  elseif name == "zoom" and self.overflow then
    local step = self.app.ctx.tuning.ui.scrollWheelStep
    self:scrollBy(Scroll.byWheel(self.scroll, data.steps, step, self.contentH, view.h))
  end
  return true
end

function Pantry:draw()
  local b, world = self.box, self.world
  local food = world.state.food
  Panel.frame(self.app.view, b, "Pantry", "Keep food to eat, preserve for winter, sell the rest.")
  local keepText = Food.pantryAuto(world) and "Keep up to %d days of food to eat" or "Keep %d days of food to eat"
  Text.draw(string.format(keepText, food.pantryDays), b.x + 12, self.pantryY + 6, { size = "small" })
  Text.draw(string.format("Preserve %d days for winter", food.winterDays), b.x + 12, self.winterY + 6, { size = "small" })
  Text.draw("Stock", b.x + 12, b.y + 94, { size = "small", color = theme.colors.textDim })
  Text.draw("For sale", b.x + 150, b.y + 94, { size = "small", color = theme.colors.textDim })
  Text.draw("Sell at", b.x + b.w - 146, b.y + 94, { size = "small", color = theme.colors.textDim })
  Text.draw("Rule", b.x + b.w - 84, b.y + 94, { size = "small", color = theme.colors.textDim })
  -- The goods list is clipped to its window (scissor works in screen pixels, not virtual ones).
  local v, scale = self.view, self.app.view.scale
  love.graphics.setScissor(math.floor(v.x * scale), math.floor(v.y * scale), math.ceil(v.w * scale), math.ceil(v.h * scale))
  for _, row in ipairs(self.rows) do
    local res, info = row.res, row.info
    local warn = info and info.warn
    Panel.icon(Panel.resourceIcon(res.id), b.x + 12, row.y + 4)
    Text.draw(string.format("%s  x%d", res.name, Ledger.get(world, res.id)), b.x + 30, row.y + 5, { size = "small" })
    local crate = food.crate[res.id]
    if crate then
      Text.draw(tostring(crate), b.x + 150, row.y + 5, { size = "small", color = theme.colors.accent })
    end
    if info then
      -- The "!" keeps the warning readable without relying on colour.
      Text.draw(
        (warn and "! " or "") .. SpoilText.rateLine(info),
        b.x + 30,
        row.y + ROW_H - 2,
        { size = "small", color = warn and theme.colors.danger or theme.colors.textDim }
      )
    end
  end
  self.rowButtons:draw()
  love.graphics.setScissor()
  if #self.rows == 0 then
    Text.draw("Nothing in stock yet.", b.x + 12, b.y + LIST_TOP + 4, { size = "small", color = theme.colors.textDim })
  end
  if self.overflow then
    self:drawScrollCue()
  end
  local y = b.y + b.h - 6 - self.footerH
  for _, line in ipairs(self.footerLines) do
    Text.draw(line.text, b.x + 12, y, { size = "small", width = b.w - 24, color = line.color })
    y = y + line.h + 2
  end
  self.buttons:draw()
end

--- The scroll cues: a thumb down the right edge of the list and a hint line under it that says how
--- much is out of sight, above and below.
function Pantry:drawScrollCue()
  local v, ui = self.view, self.app.ctx.tuning.ui
  local at, h = Scroll.thumb(self.scroll, self.contentH, v.h, v.h, ui.scrollHintHeight)
  local barW = ui.scrollBarWidth
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", v.x + v.w - barW - 2, v.y, barW, v.h, 1, 1)
  love.graphics.setColor(theme.colors.accent)
  love.graphics.rectangle("fill", v.x + v.w - barW - 2, v.y + at, barW, h, 1, 1)
  local above, below = Scroll.hidden(self.scroll, self.contentH, v.h)
  local parts = {}
  if above > 0 then
    parts[#parts + 1] = "^ more above"
  end
  if below > 0 then
    parts[#parts + 1] = "v more below"
  end
  Text.draw(
    "Drag or scroll: " .. table.concat(parts, ", "),
    v.x + 12,
    v.y + v.h + 2,
    { size = "small", color = theme.colors.textDim }
  )
end

return Pantry
