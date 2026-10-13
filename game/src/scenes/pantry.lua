-- Pantry: keep targets (GDD §6.2, D75). Every good that can be eaten, burned or sold has one keep
-- number; stock above it is spare, which the roadside stand and the truck load sell. Targets start
-- automatic (Food.keeps); - and + set your own, Auto goes back. A Stand/Truck toggle keeps a good's
-- spare away from the stand (D62).
-- Perishables show how long they keep and when their oldest batch spoils, with a warning when
-- something will rot tonight (D68, D73); a footer says what slows it.

local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Spoilage = require("src.sim.systems.spoilage")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local SpoilText = require("src.ui.spoil_text")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Pantry = { name = "pantry" }
Pantry.__index = Pantry

local ROW_H = 26 -- a row clears the smallest touch target (tuning.input.minTouchTarget) with a gap
local NOTE_H = 10 -- extra height under a perishable's row for its spoilage line
-- Columns, measured from the panel's right edge.
local COL = {
  stand = 66, -- Stand/Truck toggle (54 wide)
  plus = 96,
  minus = 122,
  auto = 160, -- Auto button (34 wide)
  keep = 196, -- keep number
  spare = 228, -- spare number
}

-- What Auto keeps, in words, from the same tuning Food.keeps reads.
local function helpText(world)
  local cfg = world.tuning.food
  return string.format(
    "Auto keeps %d days of fresh food, %d days for winter and fuel to the end of winter. "
      .. "Set your own with - and +; Auto goes back. Spare goods sell at the stand or on the truck.",
    cfg.defaultPantryDays,
    cfg.defaultWinterDays
  )
end

function Pantry.new(world)
  return setmetatable({ world = world, list = ScrollList.new() }, Pantry)
end

function Pantry:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

-- Goods worth showing: in stock and edible, burnable or sellable. Perishables come first so their
-- spoilage lines are never the ones cut off when the panel is short.
function Pantry:goods()
  local fresh, rest = {}, {}
  for _, res in ipairs(self.world.registry:all("resources")) do
    if Ledger.get(self.world, res.id) > 0 and (res.calories or res.value or res.heat) then
      local list = Spoilage.perishable(self.world, res.id) and fresh or rest
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
      text = string.format(
        "Warning: %s of food will rot tonight (at the end of its shelf life). Eat, sell or preserve it.",
        tonight.units == 1 and "1 unit" or (tonight.units .. " units")
      ),
      color = theme.colors.danger,
    }
  end
  if #tonight.list > 0 then
    lines[#lines + 1] = { text = SpoilText.slowing(world), color = theme.colors.textDim }
  end
  local h = 0
  for _, line in ipairs(lines) do
    line.h = Text.wrappedHeight(line.text, "small", b.w - 24)
    h = h + line.h + 2
  end
  return lines, h
end

-- Help text under the title, wrapped; the column headings sit under it.
function Pantry:helpHeight()
  return Text.wrappedHeight(helpText(self.world), "small", self.box.w - 24)
end

function Pantry:layout()
  local b, world = self.box, self.world
  local right = b.x + b.w
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.headY = b.y + 40 + self:helpHeight() + 4
  -- The goods list scrolls (D70, #170): rows are laid out from the top of the list minus the scroll
  -- offset, only the ones in view get buttons, and the footer and hint line keep their places.
  self.rows = {}
  self.rowButtons = self.rowButtons or Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons:clear()
  self.footerLines, self.footerH = self:footer()
  local ui = self.app.ctx.tuning.ui
  local goods = self:goods()
  local keeps, autos = Food.keeps(world)
  local contentH = 0
  for _, res in ipairs(goods) do
    contentH = contentH + ROW_H + (Spoilage.info(world, res.id) and NOTE_H or 0)
  end
  local top = self.headY + 14
  local viewH = math.max(ROW_H, b.y + b.h - 6 - self.footerH - top)
  local view = self.list:fit({ x = b.x, y = top, w = b.w, h = viewH }, contentH, ui.scrollHintHeight, ROW_H)
  self.view, viewH = view, view.h
  local y = self.list:origin()
  for _, res in ipairs(goods) do
    local info = Spoilage.info(world, res.id)
    local h = ROW_H + (info and NOTE_H or 0)
    if y + h > top and y < top + viewH then
      local keep, auto = keeps[res.id] or 0, autos[res.id] == true
      local stock = Ledger.get(world, res.id)
      local spare = res.value and math.max(0, stock - keep) or nil
      self.rows[#self.rows + 1] = { res = res, y = y, info = info, keep = keep, auto = auto, spare = spare }
      local by = y + 1
      self.rowButtons:add({
        x = right - COL.auto,
        y = by,
        w = 34,
        h = ROW_H - 4,
        label = "Auto",
        size = "small",
        selected = auto,
        onPress = function()
          Food.setKeep(world, res.id, nil)
          self:layout()
        end,
      })
      self.rowButtons:add({ x = right - COL.minus, y = by, w = 24, h = ROW_H - 4, label = "-", onPress = function()
        Food.setKeep(world, res.id, keep - 1)
        self:layout()
      end })
      self.rowButtons:add({ x = right - COL.plus, y = by, w = 24, h = ROW_H - 4, label = "+", onPress = function()
        Food.setKeep(world, res.id, keep + 1)
        self:layout()
      end })
      if res.value then
        -- "Not at the stand" pin (D62): a good marked Truck keeps its spare for the truck load.
        local truckOnly = Food.truckOnly(world, res.id)
        self.rowButtons:add({
          x = right - COL.stand,
          y = by,
          w = 54,
          h = ROW_H - 4,
          label = truckOnly and "Truck" or "Stand",
          size = "small",
          selected = truckOnly,
          onPress = function()
            Food.setTruckOnly(world, res.id, not truckOnly)
            self:layout()
          end,
        })
      end
    end
    y = y + h
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
  if self.buttons:action(name, data) then
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    -- Row buttons only answer inside the list's window: a half-scrolled row must not reach out of it.
    if self.list:contains(data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui.scrollWheelStep) then
    self:layout() -- the list follows the finger
  end
  return true
end

function Pantry:draw()
  local b, world = self.box, self.world
  local right = b.x + b.w
  local dim = theme.colors.textDim
  Panel.frame(self.app.view, b, "Pantry", "Keep what you need; the rest is spare to sell.")
  Text.draw(helpText(world), b.x + 12, b.y + 40, { size = "small", width = b.w - 24, color = dim })
  local hy = self.headY
  Text.draw("Stock", b.x + 12, hy, { size = "small", color = dim })
  Text.draw("Spare", right - COL.spare - 4, hy, { size = "small", color = dim })
  Text.draw("Keep", right - COL.keep - 2, hy, { size = "small", color = dim })
  Text.draw("Sell at", right - COL.stand + 8, hy, { size = "small", color = dim })
  -- The goods list is clipped to its window (scissor works in screen pixels, not virtual ones).
  local scale = self.app.view.scale
  self.list:begin(scale)
  for _, row in ipairs(self.rows) do
    local res, info = row.res, row.info
    local warn = info and info.warn
    local ty = row.y + 7
    Panel.icon(Panel.resourceIcon(res.id), b.x + 12, row.y + 6)
    Text.draw(string.format("%s  x%d", res.name, Ledger.get(world, res.id)), b.x + 28, ty, { size = "small" })
    if row.spare then
      Text.draw(tostring(row.spare), right - COL.spare, ty, {
        size = "small",
        width = 26,
        align = "center",
        color = row.spare > 0 and theme.colors.accent or dim,
      })
    end
    Text.draw(tostring(row.keep), right - COL.keep, ty, {
      size = "small",
      width = 30,
      align = "center",
      color = row.auto and theme.colors.text or theme.colors.accent,
    })
    if info then
      -- The "!" keeps the warning readable without relying on colour.
      Text.draw(
        (warn and "! " or "") .. SpoilText.ageLine(info),
        b.x + 28,
        row.y + ROW_H - 4,
        { size = "small", color = warn and theme.colors.danger or dim }
      )
    end
  end
  self.rowButtons:draw()
  self.list:finish()
  if #self.rows == 0 then
    Text.draw("Nothing in stock yet.", b.x + 12, self.view.y + 4, { size = "small", color = dim })
  end
  self.list:drawCue(self.app.ctx.tuning.ui)
  local y = b.y + b.h - 6 - self.footerH
  for _, line in ipairs(self.footerLines) do
    Text.draw(line.text, b.x + 12, y, { size = "small", width = b.w - 24, color = line.color })
    y = y + line.h + 2
  end
  self.buttons:draw()
end

return Pantry
