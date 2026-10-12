-- Pantry & food rules (GDD §6.2): how many days to keep, how much to preserve for winter, and
-- per-item pins. Everything else goes in the sell crate for the next truck trip.

local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Pantry = { name = "pantry" }
Pantry.__index = Pantry

local ROW_H = 22
local PIN_LABELS = { [false] = "Auto", keep = "Keep", preserve = "Preserve", sell = "Sell" }
local PIN_CYCLE = { [false] = "keep", keep = "preserve", preserve = "sell", sell = false }

function Pantry.new(world)
  return setmetatable({ world = world }, Pantry)
end

function Pantry:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

-- Goods worth showing: in stock and edible or sellable.
function Pantry:goods()
  local list = {}
  for _, res in ipairs(self.world.registry:all("resources")) do
    if Ledger.get(self.world, res.id) > 0 and (res.calories or res.value) then
      list[#list + 1] = res
    end
  end
  return list
end

function Pantry:resize(view)
  self.box = Panel.box(view, 400, view.h - 16)
  self:layout()
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
  self.rows = {}
  local maxRows = math.floor((b.h - 116) / ROW_H)
  for n, res in ipairs(self:goods()) do
    if n > maxRows then
      break
    end
    local y = b.y + 108 + (n - 1) * ROW_H
    self.rows[#self.rows + 1] = { res = res, y = y }
    local pin = food.pins[res.id] or false
    self.buttons:add({
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
end

function Pantry:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function Pantry:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

function Pantry:draw()
  local b, world = self.box, self.world
  local food = world.state.food
  Panel.frame(self.app.view, b, "Pantry", "Keep food to eat, preserve for winter, sell the rest.")
  Text.draw(string.format("Keep %d days of food to eat", food.pantryDays), b.x + 12, self.pantryY + 6, { size = "small" })
  Text.draw(string.format("Preserve %d days for winter", food.winterDays), b.x + 12, self.winterY + 6, { size = "small" })
  Text.draw("Stock", b.x + 12, b.y + 94, { size = "small", color = theme.colors.textDim })
  Text.draw("For sale", b.x + 200, b.y + 94, { size = "small", color = theme.colors.textDim })
  for _, row in ipairs(self.rows) do
    local res = row.res
    Panel.icon(Panel.resourceIcon(res.id), b.x + 12, row.y + 4)
    Text.draw(string.format("%s  x%d", res.name, Ledger.get(world, res.id)), b.x + 30, row.y + 5, { size = "small" })
    local crate = food.crate[res.id]
    if crate then
      Text.draw(tostring(crate), b.x + 200, row.y + 5, { size = "small", color = theme.colors.accent })
    end
  end
  if #self.rows == 0 then
    Text.draw("Nothing in stock yet.", b.x + 12, b.y + 112, { size = "small", color = theme.colors.textDim })
  end
  self.buttons:draw()
end

return Pantry
