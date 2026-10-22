-- The contracts board (D197, #372, docs/PLAN_DEPTH.md §9.2): the town's open contracts, opened from the truck panel at home
-- and in town. Each row says who asks, what, the pay, and the days left; Fill hands the goods over (in town only, from the
-- surplus above the keep target). The trip's Sell the load also fills what it can, so the board needs no visit. Never forced,
-- never punishing: a contract that is missed just lapses. Reputation is the count of contracts finished.

local Contracts = require("src.sim.systems.contracts")
local Footing = require("src.sim.systems.footing")
local Market = require("src.sim.systems.market")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Board = { name = "contracts" }
Board.__index = Board

local ROW_H = 40 -- name line plus the days and stock line; clears the touch target with a gap
local TOP = 62 -- virtual pixels from the panel top to the list
local FOOT_H = 44 -- the reputation and explanation lines under the list

--- "today", "tomorrow", "5 days" for the days left on a contract.
function Board.daysText(left)
  if left <= 0 then
    return "last day"
  elseif left == 1 then
    return "1 day left"
  end
  return string.format("%d days left", left)
end

--- The empty board's words: why nothing is posted.
function Board.emptyText(world)
  if not Contracts.isOpen(world) then
    return "The board opens at Footing."
  elseif Footing.paused(world) then
    return "No new offers while the homestead is short of reserves. They return when it is steady."
  end
  return "No offers right now. New ones are posted each week, for goods you have held."
end

function Board.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast or function() end }, Board)
end

function Board:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.list = ScrollList.new(function()
    self:layout()
  end)
end

function Board:resize(view)
  self.box = Panel.box(view, 420, view.h - 16)
  self:layout()
end

function Board:inTown()
  return self.world.state.market.inTown
end

function Board:fill(contract)
  local filled = Market.fillContracts(self.world, contract.id)
  if filled[1] then
    self.onToast(string.format("Contract filled: +$%d", filled[1].reward))
  end
  self:layout()
end

function Board:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  self.rowButtons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.rows = {}
  local list = Contracts.list(world)
  local ui = self.app.ctx.tuning.ui
  local top = b.y + TOP
  local viewH = math.max(ROW_H, b.h - TOP - FOOT_H - 6)
  self.view = self.list:fit({ x = b.x, y = top, w = b.w, h = viewH }, #list * ROW_H, ui.scrollHintHeight, ROW_H)
  local town = self:inTown()
  local y = self.list:origin()
  for _, c in ipairs(list) do
    if self.list:visible(y, ROW_H) then
      local reason, missing = Contracts.cannotFill(world, c)
      self.rows[#self.rows + 1] = { contract = c, y = y, missing = missing }
      self.rowButtons:add({
        x = b.x + b.w - 12 - 70 - (self.list.overflow and ui.scrollBarWidth + 2 or 0),
        y = y + 6,
        w = 70,
        h = 26,
        label = not town and "In town" or reason and "Short" or "Fill",
        style = town and not reason and "accent" or nil,
        enabled = town and not reason,
        onPress = function()
          self:fill(c)
        end,
      })
    end
    y = y + ROW_H
  end
end

function Board:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function Board:action(name, data)
  if name == "press" or name == "release" then
    self.list:action(name, data)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    if self.list:contains(data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout()
  end
  return true
end

function Board:draw()
  local b, world = self.box, self.world
  local dim = theme.colors.textDim
  local done = Contracts.reputation(world)
  Panel.frame(
    self.app.view,
    b,
    "Contracts",
    string.format("Reputation: %d %s finished", done, done == 1 and "contract" or "contracts")
  )
  Text.draw(
    self:inTown() and "Fill a contract from your spare goods."
      or "Contracts are filled in town. Selling the load fills them too.",
    b.x + 12,
    b.y + 38,
    { size = "small", width = b.w - 24, color = dim }
  )
  self.list:begin(self.app.view.scale)
  for _, row in ipairs(self.rows) do
    local c = row.contract
    local res = world.registry:get("resources", c.item)
    local def = world.registry:get("contracts", c.def)
    Panel.icon(Panel.resourceIcon(c.item), b.x + 12, row.y + 6)
    Text.draw(string.format("%s: %d %s for $%d", def.name, c.amount, res.name, c.reward), b.x + 28, row.y + 5, {
      size = "small",
      width = b.w - 28 - 94,
    })
    local have = Contracts.available(world, c)
    local line = string.format("%s · %d spare", Board.daysText(Contracts.daysLeft(world, c)), have)
    if row.missing then
      line = line .. string.format(" · %d short", row.missing)
    end
    Text.draw(line, b.x + 28, row.y + 20, { size = "small", color = row.missing and dim or theme.colors.accent })
  end
  self.rowButtons:draw()
  self.list:finish()
  if #self.rows == 0 then
    Text.draw(Board.emptyText(world), b.x + 12, self.view.y + 4, { size = "small", width = b.w - 24, color = dim })
  end
  self.list:drawCue(self.app.ctx.tuning.ui)
  Text.draw(
    "A contract that is missed just lapses: nothing is lost. Each one finished raises the pay and opens richer orders. Standing orders come back every week.",
    b.x + 12,
    b.y + b.h - FOOT_H,
    { size = "small", width = b.w - 24, color = dim }
  )
  self.buttons:draw()
end

return Board
