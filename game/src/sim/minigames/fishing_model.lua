-- Tension-meter fishing mini-game model (GDD §7.10). Pure logic, no rendering, so it can be
-- tested by simulating a player. The scene feeds it one input: is the button held?
--
-- Phases:
--   wait   bobber in the water until a bite (faster with bait)
--   bite   the bobber dips: press within biteWindow to set the hook, or it's "missed"
--   fight  hold to reel (line up, tension up), release to ease off (tension down, the fish takes
--          line). The fish pulls harder when fresh and during surges, and tires over time.
--          Tension maxed for slipTime -> "slipped" (gentle: no gear lost).
--          Line at zero while released for escapeTime -> "escaped". Line full -> "caught".
--
-- params: { fish = def, tuning = tuning.fishing, rng = Rng, maxTension = n, reelSpeed = n, bait = bool, activity = n }
-- maxTension / reelSpeed are gear multipliers (1 = basic rod).

local Model = {}
Model.__index = Model

function Model.new(params)
  local cfg = params.tuning
  -- activity: how active the fish are (weather, 1 = normal); livelier fish bite sooner.
  local delay = params.rng:range(cfg.biteDelayMin, cfg.biteDelayMax) * (params.bait and cfg.baitBiteSpeed or 1) / (params.activity or 1)
  return setmetatable({
    fish = params.fish,
    cfg = cfg,
    rng = params.rng,
    maxTension = params.maxTension or 1,
    reelSpeed = params.reelSpeed or 1,
    phase = "wait",
    timer = delay,
    tension = 0,
    line = 0,
    stamina = 1,
    surge = 0,
    slip = 0,
    slack = 0,
    holding = false,
    result = nil,
  }, Model)
end

--- Current pull of the fish, 0..~2 (strength scaled by stamina, boosted during surges).
function Model:pull()
  local cfg = self.cfg
  local pull = self.fish.strength * (cfg.minPull + (1 - cfg.minPull) * self.stamina)
  if self.surge > 0 then
    pull = pull * (1 + cfg.surgeBoost)
  end
  return pull
end

function Model:update(dt, holding)
  if self.result then
    return self.result
  end
  local pressed = holding and not self.holding
  self.holding = holding
  local cfg = self.cfg

  if self.phase == "wait" then
    self.timer = self.timer - dt
    if self.timer <= 0 then
      self.phase = "bite"
      self.timer = cfg.biteWindow
    end
  elseif self.phase == "bite" then
    if pressed then
      self.phase = "fight"
      self.line = cfg.startLine
    else
      self.timer = self.timer - dt
      if self.timer <= 0 then
        self.result = "missed"
      end
    end
  elseif self.phase == "fight" then
    if self.surge > 0 then
      self.surge = math.max(0, self.surge - dt)
    elseif self.rng:chance(self.fish.surgeChance * dt) then
      self.surge = cfg.surgeDuration
    end
    local pull = self:pull()
    if holding then
      self.tension = self.tension + (cfg.tensionRise + pull * cfg.pullTension) * dt / self.maxTension
      self.line = self.line + cfg.reelSpeed * self.reelSpeed * (1 - pull * cfg.pullSlowdown) * dt
      self.stamina = math.max(0, self.stamina - dt / self.fish.stamina)
    else
      self.tension = self.tension - cfg.tensionFall * dt
      self.line = self.line - pull * cfg.runSpeed * dt
      self.stamina = math.max(0, self.stamina - dt * cfg.restingDrain / self.fish.stamina)
    end
    self.tension = math.max(0, math.min(1, self.tension))
    self.line = math.max(0, math.min(1, self.line))

    if self.tension >= 1 then
      self.slip = self.slip + dt
      if self.slip >= cfg.slipTime then
        self.result = "slipped"
      end
    else
      self.slip = math.max(0, self.slip - dt)
    end
    if self.line <= 0 and not holding then
      self.slack = self.slack + dt
      if self.slack >= cfg.escapeTime then
        self.result = "escaped"
      end
    else
      self.slack = 0
    end
    if self.line >= 1 then
      self.result = "caught"
    end
  end
  return self.result
end

return Model
