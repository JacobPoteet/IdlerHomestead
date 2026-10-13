-- Load the truck (GDD §6.4, D75, #196): choose what goes to town on the next trip. Every sellable good
-- in stock is listed with its spare (stock above its keep target), its keep and its price; - and +
-- change the load one unit at a time, +5 five, All takes all the spare. Auto-load fills the free cargo
-- (best price per unit first, then what spoils soonest, never below a keep target) and Clear empties
-- the truck. Loading into a keep target asks first (the reserve guard): the warning reads the winter
-- readiness and needs accessors, so it says what the homestead would be short of.
-- Loaded goods stay at home until the trip, still counted in stock; anything not loaded stays home.

local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Scroll = require("src.ui.scroll")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Load = { name = "load" }
Load.__index = Load

local ROW_H = 36 -- name line plus the spare / keep / price line; clears the touch target with a gap
local HELP_Y = 64 -- virtual pixels from the panel top to the help line; the list starts under it
local HELP = "Spare = stock above what you keep (set in the Pantry). Auto-load takes the best price first."
-- Row controls, measured from the panel's right edge.
local COL = { all = 44, five = 78, plus = 106, count = 132, minus = 156 }

--- The reserve-guard message for a Market.loadWarning: what loading would take from what is kept.
--- Returns title, message. Numbers come from Readiness and Needs, never from here.
function Load.warningText(world, warning)
  local res = world.registry:get("resources", warning.id)
  local what = string.format("This loads %d %s from the %d you keep.", warning.below, res.name, warning.keep)
  local ready = Readiness.winter(world)
  if warning.kind == "fuel" then
    local text
    if ready then
      text = string.format("Your fuel covers %d of the %d nights to the end of winter.", ready.fuel.covered, ready.fuel.nights)
    else
      local nights = Needs.fuelNights(world)
      text = nights == math.huge and "No fire is needed tonight, but winter will need fuel."
        or string.format("Your fuel lasts about %.1f nights at tonight's need.", nights)
    end
    return "Sell fuel you keep?", what .. " " .. text .. " Load it anyway?"
  elseif warning.kind == "food" then
    local text
    if ready then
      text = string.format("You have %.1f days of food; winter still needs %d.", ready.food.days, ready.food.need)
    else
      text = string.format("You have %.1f days of food in stock.", Needs.foodDays(world))
    end
    return "Sell food you keep?", what .. " " .. text .. " Load it anyway?"
  end
  return "Sell what you keep?", what .. " Load it anyway?"
end

function Load.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast or function() end }, Load)
end

function Load:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Load:inTown()
  return self.world.state.market.inTown
end

-- Sellable goods in stock: those with spare first, then the ones only kept, each part in content
-- order (loading never moves a row).
function Load:goods()
  local world = self.world
  local surplus = Food.surpluses(world)
  local first, rest = {}, {}
  for _, res in ipairs(world.registry:all("resources")) do
    if res.value and Ledger.get(world, res.id) > 0 then
      local list = (surplus[res.id] or 0) > 0 and first or rest
      list[#list + 1] = res
    end
  end
  for _, res in ipairs(rest) do
    first[#first + 1] = res
  end
  return first
end

function Load:resize(view)
  self.box = Panel.box(view, 420, view.h - 16)
  self:layout()
end

-- Ask for `units` of `id` on the truck; a load into the keep target asks first.
function Load:request(id, units)
  local world = self.world
  local _, reason = Market.setLoad(world, id, units)
  if reason == "reserve" then
    local title, message = Load.warningText(world, Market.loadWarning(world, id, units))
    self.app:push(require("src.scenes.confirm").new({
      title = title,
      message = message,
      confirmLabel = "Load anyway",
      danger = true,
      onConfirm = function()
        local _, why = Market.setLoad(world, id, units, true)
        if why == "cargo full" then
          self.onToast(string.format("The truck is full (%d units)", Market.cargoCapacity(world)))
        end
        self:layout()
      end,
    }))
  elseif reason == "cargo full" then
    self.onToast(string.format("The truck is full (%d units)", Market.cargoCapacity(world)))
  end
  self:layout()
end

function Load:layout()
  local b, world = self.box, self.world
  local right = b.x + b.w
  local town = self:inTown()
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.buttons:add({
    x = right - 12 - 56 - 6 - 76,
    y = b.y + 36,
    w = 76,
    h = 24,
    label = "Auto-load",
    style = "accent",
    enabled = not town and Market.cargoLeft(world) > 0 and Market.spareUnits(world) > 0,
    onPress = function()
      local n = Market.autoLoad(world)
      self.onToast(n > 0 and string.format("Loaded %d spare units", n) or "Nothing spare to load")
      self:layout()
    end,
  })
  self.buttons:add({
    x = right - 12 - 56,
    y = b.y + 36,
    w = 56,
    h = 24,
    label = "Clear",
    enabled = not town and Market.loadUnits(world) > 0,
    onPress = function()
      Market.clearLoad(world)
      self:layout()
    end,
  })

  self.rows = {}
  self.rowButtons:clear()
  local goods = self:goods()
  local ui = self.app.ctx.tuning.ui
  local top = b.y + HELP_Y + Text.wrappedHeight(HELP, "small", b.w - 24) + 16
  local footH = Text.wrappedHeight(self:footerText(), "small", b.w - 24) + 4
  local contentH = #goods * ROW_H
  local viewH = math.max(ROW_H, b.y + b.h - 6 - footH - top)
  self.overflow = Scroll.overflows(contentH, viewH)
  if self.overflow then
    viewH = math.max(ROW_H, viewH - ui.scrollHintHeight)
  end
  self.contentH, self.footH = contentH, footH
  self.view = { x = b.x, y = top, w = b.w, h = viewH }
  self.scroll = Scroll.clamp(self.scroll or 0, contentH, viewH)
  local keeps = Food.keeps(world)
  local y = top - self.scroll
  for _, res in ipairs(goods) do
    if y + ROW_H > top and y < top + viewH then
      local id = res.id
      local stock = Ledger.get(world, id)
      local keep = keeps[id] or 0
      local loaded = Market.loaded(world, id)
      local spare = math.max(0, stock - keep)
      self.rows[#self.rows + 1] = { res = res, y = y, stock = stock, keep = keep, loaded = loaded, spare = spare }
      local by = y + 6
      local function add(x, w, label, enabled, onPress)
        self.rowButtons:add({ x = right - x, y = by, w = w, h = 24, label = label, size = "small", enabled = enabled and not town, onPress = onPress })
      end
      add(COL.minus, 24, "-", loaded > 0, function()
        self:request(id, loaded - 1)
      end)
      add(COL.plus, 24, "+", loaded < stock, function()
        self:request(id, loaded + 1)
      end)
      add(COL.five, 30, "+5", loaded < stock, function()
        self:request(id, loaded + 5)
      end)
      add(COL.all, 32, "All", loaded < spare, function()
        self:request(id, spare)
      end)
    end
    y = y + ROW_H
  end
end

function Load:footerText()
  if self:inTown() then
    return "The goods are at home: load the truck before the next trip."
  end
  return "Anything not loaded stays home. Loaded goods stay in stock (eaten in a pinch, aging oldest first) until they sell in town, and the roadside stand leaves them alone."
end

local function inside(r, x, y)
  return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Load:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function Load:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  local view = self.view
  if name == "press" or name == "select" or name == "hover" then
    if inside(view, data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif name == "pan" and self.overflow then
    self.scroll = Scroll.byDrag(self.scroll, data.dy, self.contentH, view.h)
    self:layout()
  elseif name == "zoom" and self.overflow then
    self.scroll = Scroll.byWheel(self.scroll, data.steps, self.app.ctx.tuning.ui.scrollWheelStep, self.contentH, view.h)
    self:layout()
  end
  return true
end

function Load:draw()
  local b, world = self.box, self.world
  local right = b.x + b.w
  local dim = theme.colors.textDim
  local _, value, units = Market.loadQuote(world)
  local cargo = Market.cargoCapacity(world)
  Panel.frame(self.app.view, b, "Load the truck", string.format("Cargo %d / %d units, worth $%d in town", units, cargo, value))
  -- Cargo bar.
  local barW = b.w - 24 - 56 - 6 - 76 - 8
  love.graphics.setColor(theme.colors.background)
  love.graphics.rectangle("fill", b.x + 12, b.y + 42, barW, 12, 2, 2)
  if units > 0 then
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", b.x + 13, b.y + 43, math.max(1, (barW - 2) * math.min(1, units / cargo)), 10, 2, 2)
  end
  Text.draw(HELP, b.x + 12, b.y + HELP_Y, { size = "small", width = b.w - 24, color = dim })
  Text.draw("Loaded", right - COL.count - 6, self.view.y - 12, { size = "small", color = dim })
  local v, scale = self.view, self.app.view.scale
  love.graphics.setScissor(math.floor(v.x * scale), math.floor(v.y * scale), math.ceil(v.w * scale), math.ceil(v.h * scale))
  for _, row in ipairs(self.rows) do
    local res = row.res
    Panel.icon(Panel.resourceIcon(res.id), b.x + 12, row.y + 5)
    Text.draw(string.format("%s  x%d", res.name, row.stock), b.x + 28, row.y + 6, { size = "small" })
    Text.draw(
      string.format("%d spare · keep %d · $%d each", row.spare, row.keep, Market.sellPrice(world, res.id)),
      b.x + 28,
      row.y + 18,
      { size = "small", color = row.spare > 0 and dim or theme.colors.textDim }
    )
    Text.draw(tostring(row.loaded), right - COL.count, row.y + 12, {
      size = "small",
      width = 26,
      align = "center",
      color = row.loaded > row.spare and theme.colors.danger or (row.loaded > 0 and theme.colors.accent or dim),
    })
  end
  self.rowButtons:draw()
  love.graphics.setScissor()
  if #self.rows == 0 then
    Text.draw("Nothing to sell in stock yet.", b.x + 12, self.view.y + 4, { size = "small", color = dim })
  end
  if self.overflow then
    local above, below = Scroll.hidden(self.scroll, self.contentH, v.h)
    local parts = {}
    if above > 0 then
      parts[#parts + 1] = "^ more above"
    end
    if below > 0 then
      parts[#parts + 1] = "v more below"
    end
    Text.draw("Drag or scroll: " .. table.concat(parts, ", "), v.x + 12, v.y + v.h + 2, { size = "small", color = dim })
  end
  Text.draw(self:footerText(), b.x + 12, b.y + b.h - 6 - self.footH + 4, { size = "small", width = b.w - 24, color = dim })
  self.buttons:draw()
end

return Load
