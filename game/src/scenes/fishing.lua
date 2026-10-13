-- Fishing mini-game (GDD §7.10): the tension meter.
-- One input: hold (mouse/touch press, or Space) to reel; let go to ease off.
-- The game logic is src/sim/minigames/fishing_model.lua; this scene only feeds input and draws.
-- Time keeps passing on the homestead while you fish.

local Fishing = require("src.sim.systems.fishing")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")
local Model = require("src.sim.minigames.fishing_model")
local Assets = require("src.render.assets")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local FishingScene = { name = "fishing" }
FishingScene.__index = FishingScene

local RESULT_TEXT = {
  missed = "It got away before you set the hook.",
  slipped = "Too much tension. It slipped the hook.",
  escaped = "It ran off with the slack.",
  full = "No room to keep a catch. Make space first.",
  lostfull = "The store filled up. It got away.",
}

function FishingScene.new(world, onCatch)
  return setmetatable({ world = world, onCatch = onCatch, time = 0 }, FishingScene)
end

function FishingScene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self:cast()
end

function FishingScene:cast()
  local world = self.world
  local why
  self.fish, why = Fishing.rollFish(world, "active")
  self.result, self.size, self.first = nil, nil, nil
  self.pointerHeld = false
  if not self.fish then
    self.result = why == "full" and "full" or "nothing"
    self.model = nil
  else
    local bait = Ledger.remove(world, "bait", 1, "fishing")
    self.model = Model.new({
      fish = self.fish,
      tuning = world.tuning.fishing,
      rng = world:rng("fishing_game"),
      maxTension = 1 + Stats.modifier(world, "maxTension"),
      reelSpeed = 1 + Stats.modifier(world, "reelSpeed"),
      bait = bait,
      activity = Fishing.activity(world),
    })
    self.usedBait = bait
    self.app.ctx.audio:play("fish_hooked")
  end
  if self.box then
    self:layout()
  end
end

function FishingScene:resize(view)
  self.box = Panel.box(view, 320, 220)
  self:layout()
end

function FishingScene:layout()
  local b = self.box
  self.buttons:clear()
  if self.result then
    self.buttons:add({ x = b.x + 12, y = b.y + b.h - 34, w = 140, h = 26, label = "Cast again", style = "accent", onPress = function()
      self:cast()
    end })
    self.buttons:add({ x = b.x + b.w - 152, y = b.y + b.h - 34, w = 140, h = 26, label = "Done", onPress = function()
      self.app:pop()
    end })
  else
    Panel.closeButton(self.buttons, b, function()
      self.app:pop()
    end)
  end
end

function FishingScene:holding()
  return self.pointerHeld or love.keyboard.isDown("space")
end

function FishingScene:update(dt)
  self.time = self.time + dt
  if self.model and not self.result then
    local result = self.model:update(dt, self:holding())
    if result then
      self.result = result
      if result == "caught" then
        self.size = Fishing.rollSize(self.world, self.fish)
        self.first = (self.world.meta.fishGuide or {})[self.fish.id] == nil
        if Fishing.land(self.world, self.fish.id, self.size, "active") then
          if self.onCatch then
            self.onCatch(self.fish, self.size, self.first)
          end
        else
          self.result = "lostfull" -- its store filled while it was on the line: never claim the catch
        end
      elseif result == "slipped" or result == "escaped" then
        Fishing.lose(self.world, self.fish.id, result)
      end
      self:layout()
    end
  end
end

function FishingScene:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "press" then
    self.pointerHeld = true
  elseif name == "release" then
    self.pointerHeld = false
  elseif name == "cancel" then
    self.app:pop()
  end
  return true -- modal
end

local function bar(x, y, w, h, frac, color)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", x, y, w, h, 2, 2)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", x + 1, y + 1, math.max(0, (w - 2) * math.min(1, frac)), h - 2, 2, 2)
end

function FishingScene:drawWater(x, y, w, h)
  -- Simple banded water with drifting highlights (the full cutaway shader is future work).
  for row = 0, h - 1, 4 do
    local t = row / h
    love.graphics.setColor(0.20 - t * 0.08, 0.45 - t * 0.15, 0.55 - t * 0.12, 1)
    love.graphics.rectangle("fill", x, y + row, w, 4)
  end
  love.graphics.setColor(0.75, 0.9, 0.95, 0.35)
  for n = 0, 5 do
    local hx = x + ((n * 53 + self.time * 12) % w)
    love.graphics.rectangle("fill", math.floor(hx), y + 6 + n * 9, 6, 1)
  end
end

function FishingScene:draw()
  local b, m = self.box, self.model
  Panel.frame(self.app.view, b, "Fishing", self.usedBait and "Baited hook" or "No bait")
  local wx, wy, ww, wh = b.x + 12, b.y + 40, b.w - 24, 90
  self:drawWater(wx, wy, ww, wh)

  if self.result == "nothing" then
    Text.draw("Nothing's biting right now.", b.x, wy + 38, { size = "body", width = b.w, align = "center" })
  elseif self.result == "caught" then
    Panel.icon("icon_" .. self.fish.id, b.x + b.w / 2 - 6, wy + 22)
    Text.draw(string.format("%s, %d cm%s", self.fish.name, self.size, self.first and "  · New!" or ""), b.x, wy + 42, {
      size = "body",
      width = b.w,
      align = "center",
      color = self.first and theme.colors.accent or theme.colors.text,
    })
  elseif self.result then
    Text.draw(RESULT_TEXT[self.result], b.x + 16, wy + 38, { size = "small", width = b.w - 32, align = "center" })
  elseif m then
    local bobber = Assets.sprite("bobber")
    local bx = wx + ww / 2 - 4
    local by = wy + 26 + math.sin(self.time * 3) * 1.5
    if m.phase == "bite" then
      by = by + 4 -- the dip
    elseif m.phase == "fight" then
      bx = wx + 20 + (ww - 48) * (1 - m.line) + math.sin(self.time * 9) * (2 + m:pull() * 4)
      by = wy + 30 + (m.surge > 0 and math.sin(self.time * 30) * 2 or 0)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bobber.image, bobber.quad, math.floor(bx), math.floor(by))
    local status
    if m.phase == "wait" then
      status = "Waiting for a bite..."
    elseif m.phase == "bite" then
      status = "Bite! Press now!"
    else
      status = m.surge > 0 and "It's surging! Ease off!" or "Hold to reel, let go to ease off"
    end
    Text.draw(status, b.x, wy + wh - 16, {
      size = "small",
      width = b.w,
      align = "center",
      color = m.phase == "bite" and theme.colors.accent or theme.colors.text,
    })
    if m.phase == "fight" then
      local t = m.tension
      local color = { 0.45 + t * 0.5, 0.8 - t * 0.55, 0.42 - t * 0.2, 1 }
      Text.draw("Tension", b.x + 12, b.y + 138, { size = "small", color = theme.colors.textDim })
      bar(b.x + 70, b.y + 138, b.w - 82, 10, t, color)
      Text.draw("Line", b.x + 12, b.y + 156, { size = "small", color = theme.colors.textDim })
      bar(b.x + 70, b.y + 156, b.w - 82, 10, m.line, { 0.55, 0.75, 0.92, 1 })
    else
      Text.draw("Hold the mouse, a finger, or Space to reel.", b.x, b.y + 146, {
        size = "small",
        width = b.w,
        align = "center",
        color = theme.colors.textDim,
      })
    end
  end
  self.buttons:draw()
end

return FishingScene
