-- The status detail card (D167, #346; docs/PLAN_DEPTH.md §7): what one status does to the homesteader, how long it
-- lasts, what clears it and what happens if it is hurt again. Opened by a tap on a status chip under the Condition meter
-- or by the H key (the first status); Close, Esc or H puts it away. A browse card: it reads the sim (Status) and changes
-- nothing. It closes itself when the status ends while it is open. Tap and keyboard, nothing hover-only.

local Assets = require("src.render.assets")
local Buttons = require("src.ui.buttons")
local Icons = require("src.ui.icons")
local Panel = require("src.ui.panel")
local Status = require("src.sim.systems.status")
local StatusText = require("src.ui.status_text")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Scene = { name = "status" }
Scene.__index = Scene

function Scene.new(world, id)
  return setmetatable({ world = world, id = id, age = 0 }, Scene)
end

function Scene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Scene:resize(view)
  self.view = view
  self:layout()
end

-- The card's words for the status now, and the status, or nil when it is gone.
function Scene:look()
  local status = Status.get(self.world, self.id)
  if not status then
    return nil
  end
  local cfg = self.app.ctx.tuning.ui.status
  local model =
    StatusText.detail(cfg, self.world.registry, status, Status.count(self.world), Status.maxActive(self.world))
  return model, status
end

-- A string that changes when any word of the card does.
local function signature(model)
  return table.concat({
    model.title,
    model.line,
    table.concat(model.effects, "|"),
    model.time,
    model.how,
    model.worse,
    model.footer,
  }, "#")
end

function Scene:layout()
  local model, status = self:look()
  if not model then
    return
  end
  local cfg = self.app.ctx.tuning.ui.status
  self.model, self.status, self.sig = model, status, signature(model)
  local width = math.min(cfg.panelWidth, self.view.w - 16)
  local textW = width - 2 * cfg.pad
  local items, y = {}, 0
  local function add(text, opts)
    opts = opts or {}
    local indent = opts.indent or 0
    local h = Text.wrappedHeight(text, "small", textW - indent)
    items[#items + 1] = { text = text, top = y, h = h, indent = indent, color = opts.color, bullet = opts.bullet }
    y = y + h + cfg.rowGap
  end
  for _, e in ipairs(model.effects) do
    add(e, { bullet = true, indent = 10 })
  end
  y = y + cfg.sectionGap - cfg.rowGap
  add(model.time, { color = theme.colors.accent })
  add(model.how)
  add(model.worse, { color = theme.colors.textDim })
  y = y + cfg.sectionGap - cfg.rowGap
  add(model.footer, { color = theme.colors.textDim })
  self.items, self.textW = items, textW
  local height = cfg.headH + y + cfg.pad - cfg.rowGap
  self.box = Panel.box(self.view, width, math.min(height, self.view.h - 16))
  self.buttons:clear()
  Panel.closeButton(self.buttons, self.box, function()
    self.app:pop()
  end)
end

function Scene:update(dt)
  self.age = self.age + dt
  if self.age < self.app.ctx.tuning.ui.status.refresh then
    return
  end
  self.age = 0
  local model = self:look()
  if not model then
    self.app:pop() -- the status ended while the card was open
  elseif signature(model) ~= self.sig then
    self:layout()
  end
end

function Scene:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" or name == "status" then
    self.app:pop() -- Esc or H again
  end
  return true -- modal
end

function Scene:draw()
  if not self.model then
    return
  end
  local b, cfg = self.box, self.app.ctx.tuning.ui.status
  local colors = theme.colors
  Panel.frame(self.app.view, b, self.model.title, cfg.subtitle)
  -- The family's icon sits left of Close, in the title strip.
  local icon = StatusText.icon(Assets.has, self.status)
  local sp = Assets.sprite(icon)
  Icons.draw(icon, b.x + b.w - 58 - cfg.rowGap - sp.w, b.y + 6 + math.floor((22 - sp.h) / 2))
  local x, y0 = b.x + cfg.pad, b.y + cfg.headH
  for _, item in ipairs(self.items) do
    local y = y0 + item.top
    if item.bullet then
      love.graphics.setColor(colors.text)
      love.graphics.rectangle("fill", x + 2, y + 4, 3, 3)
      love.graphics.setColor(1, 1, 1, 1)
    end
    Text.draw(item.text, x + item.indent, y, {
      size = "small",
      width = self.textW - item.indent,
      color = item.color or colors.text,
    })
  end
  self.buttons:draw()
end

return Scene
