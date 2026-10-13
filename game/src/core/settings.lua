-- Player settings store (GDD D96, #50). Pure logic: defaults, validation, (de)serialisation and change
-- notification. Options are declared as data in src/core/settings_options.lua; this module knows
-- nothing about any particular option. Storage goes through a backend ({ read, write }, the same
-- shape as the save backends) so tests and the screenshot driver use memory and never touch the
-- player's real settings file.
--
-- File: { version = 1, values = { id = value }, window = { w, h, x, y } | nil }. A missing, corrupt or
-- partly bad file never errors: bad entries fall back to the default.

local serialize = require("src.core.serialize")
local Options = require("src.core.settings_options")

local Settings = {}
Settings.__index = Settings

Settings.FORMAT_VERSION = 1

local current -- the live instance, for the render layer (it reads settings and never changes them)

--- backend: { read(path), write(path, contents) }; tuning: the loaded tuning root.
function Settings.new(backend, tuning)
  local self = setmetatable({
    backend = backend,
    tuning = tuning,
    cfg = tuning.settings,
    options = Options.build(tuning),
    values = {},
    window = nil,
    listeners = {},
  }, Settings)
  self.byId = {}
  for _, opt in ipairs(self.options) do
    assert(not self.byId[opt.id], "duplicate setting " .. opt.id)
    self.byId[opt.id] = opt
    self.values[opt.id] = self:default(opt.id)
  end
  return self
end

--- Make this the instance `Settings.read` answers from.
function Settings:activate()
  current = self
  return self
end

--- Value of a setting from the active instance, or `fallback` when none is active (headless tools).
function Settings.read(id, fallback)
  if current then
    local v = current.values[id]
    if v ~= nil then
      return v
    end
  end
  return fallback
end

function Settings:default(id)
  local v = self.cfg.defaults[id]
  assert(v ~= nil, "no default for setting " .. tostring(id))
  return v
end

--- Coerce `value` into a valid value for the option, or nil if it is not valid.
function Settings:validate(opt, value)
  if opt.kind == "toggle" then
    if type(value) == "boolean" then
      return value
    end
  elseif opt.kind == "choice" then
    for _, v in ipairs(opt.values) do
      if v == value then
        return value
      end
    end
  elseif opt.kind == "slider" then
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
      local steps = math.floor((value - opt.min) / opt.step + 0.5)
      -- Tidied to 9 significant digits so 7 x 0.1 is 0.7, not 0.7000000000000001.
      local snapped = tonumber(string.format("%.9g", opt.min + steps * opt.step))
      return math.min(opt.max, math.max(opt.min, snapped))
    end
  end
  return nil
end

function Settings:get(id)
  local v = self.values[id]
  assert(v ~= nil, "unknown setting " .. tostring(id))
  return v
end

--- Set a setting. Invalid values are ignored (returns false). Calls the change listeners.
function Settings:set(id, value, silent)
  local opt = self.byId[id]
  assert(opt, "unknown setting " .. tostring(id))
  local v = self:validate(opt, value)
  if v == nil then
    return false
  end
  if self.values[id] ~= v then
    self.values[id] = v
    if not silent then
      for _, fn in ipairs(self.listeners) do
        fn(id, v)
      end
    end
  end
  return true
end

--- fn(id, value) is called after every change.
function Settings:onChange(fn)
  self.listeners[#self.listeners + 1] = fn
end

--- Back to the defaults (every option, or one).
function Settings:reset(id)
  for _, opt in ipairs(self.options) do
    if id == nil or id == opt.id then
      self:set(opt.id, self:default(opt.id))
    end
  end
end

--- Options this platform offers (those whose `requires` capability is present), in display order.
function Settings:visible(platform)
  local out = {}
  for _, opt in ipairs(self.options) do
    if not opt.requires or platform.has(opt.requires) then
      out[#out + 1] = opt
    end
  end
  return out
end

--- Run an option's apply hook with the current value (env: see settings_options.lua).
function Settings:apply(id, env)
  local opt = self.byId[id]
  if opt and opt.apply then
    opt.apply(self.values[id], env)
  end
end

--- Run every visible option's hook (at boot, after load).
function Settings:applyAll(platform, env)
  for _, opt in ipairs(self:visible(platform)) do
    self:apply(opt.id, env)
  end
end

--- Remembered window rectangle, if any: { w, h, x, y } with sane sizes.
function Settings:setWindow(w, h, x, y)
  local min = self.cfg.minWindow
  if type(w) == "number" and type(h) == "number" and w >= min[1] and h >= min[2] then
    self.window = { w = math.floor(w), h = math.floor(h), x = math.floor(x or 0), y = math.floor(y or 0) }
  end
end

function Settings:encode()
  local values = {}
  for id, v in pairs(self.values) do
    values[id] = v
  end
  return serialize.encode({ version = Settings.FORMAT_VERSION, values = values, window = self.window })
end

--- Apply file contents (a string) over the defaults. Returns true if it was usable.
function Settings:decode(text)
  local data = serialize.decode(text)
  if type(data) ~= "table" or type(data.values) ~= "table" then
    return false
  end
  for id, raw in pairs(data.values) do
    local opt = self.byId[id]
    if opt then
      local v = self:validate(opt, raw)
      if v ~= nil then
        self.values[id] = v
      end
    end
  end
  local w = data.window
  if type(w) == "table" then
    self:setWindow(w.w, w.h, w.x, w.y)
  end
  return true
end

--- Load from the backend; defaults stay for anything missing or bad. Never raises.
function Settings:load()
  local ok, text = pcall(self.backend.read, self.cfg.file)
  if ok and type(text) == "string" then
    local ok2, usable = pcall(self.decode, self, text)
    return ok2 and usable
  end
  return false
end

--- Write to the backend. Returns true on success; never raises.
function Settings:save()
  local ok, result = pcall(function()
    return self.backend.write(self.cfg.file, self:encode())
  end)
  return ok and result ~= false
end

return Settings
