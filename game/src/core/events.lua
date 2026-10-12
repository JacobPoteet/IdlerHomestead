-- Publish/subscribe event bus.
-- Systems communicate through events instead of calling each other directly.
-- Handler lists are copy-on-write, so subscribing/unsubscribing during an emit is safe.

local Events = {}
Events.__index = Events

function Events.new()
  return setmetatable({ handlers = {}, anyHandlers = {} }, Events)
end

local function without(list, fn)
  local copy = {}
  for i = 1, #list do
    if list[i] ~= fn then
      copy[#copy + 1] = list[i]
    end
  end
  return copy
end

local function with(list, fn)
  local copy = { unpack(list or {}) }
  copy[#copy + 1] = fn
  return copy
end

--- Subscribe to an event. Returns a function that unsubscribes.
function Events:on(name, fn)
  self.handlers[name] = with(self.handlers[name], fn)
  return function()
    self:off(name, fn)
  end
end

function Events:off(name, fn)
  local list = self.handlers[name]
  if list then
    self.handlers[name] = without(list, fn)
  end
end

--- Subscribe to every event; the handler receives (name, ...). Intended for debugging/logging.
function Events:onAny(fn)
  self.anyHandlers = with(self.anyHandlers, fn)
  return function()
    self.anyHandlers = without(self.anyHandlers, fn)
  end
end

function Events:emit(name, ...)
  local list = self.handlers[name]
  if list then
    for i = 1, #list do
      list[i](...)
    end
  end
  local any = self.anyHandlers
  for i = 1, #any do
    any[i](name, ...)
  end
end

return Events
