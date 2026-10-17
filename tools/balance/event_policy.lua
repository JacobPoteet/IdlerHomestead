-- Event-choice policies for the balance harness (D169, #347, docs/PLAN_DEPTH.md §6.2, §6.4): how the simulated player
-- answers a misfortune event card, on top of whatever the play policy does. Player behaviour only: the options come
-- from the event content (its `careful` and `bold` flags), the numbers from the sim.
--
--   ignore   never answers: every card runs out its window and the ignore outcome applies
--   careful  takes the option flagged `careful` when it can pay for it, else ignores
--   bold     takes the option flagged `bold` when it can pay for it, else ignores
--   random   a seeded coin over option 1, option 2 and ignore (an unaffordable option ignores)
--
-- Off (no policy) the harness plays with events disabled, so its default output is what it was before events.

local Rng = require("src.core.rng")

local EventPolicy = {}

EventPolicy.list = { "ignore", "careful", "bold", "random" }

--- Is `mode` a policy name?
function EventPolicy.valid(mode)
  for _, name in ipairs(EventPolicy.list) do
    if name == mode then
      return true
    end
  end
  return false
end

--- Turn the engine on or off in the raw tuning (before Balance.context): on only when a policy is chosen.
function EventPolicy.configure(mode)
  assert(
    mode == nil or mode == "off" or EventPolicy.valid(mode),
    "events= must be off or one of " .. table.concat(EventPolicy.list, "|")
  )
  require("data.tuning.events").enabled = mode ~= nil and mode ~= "off"
end

function EventPolicy.new(mode, seed)
  if mode == nil or mode == "off" then
    return nil
  end
  return { mode = mode, rng = Rng.new(Rng.deriveSeed(seed, "eventpolicy")) }
end

local function flagged(view, flag)
  for _, o in ipairs(view.options) do
    if o[flag] and o.affordable then
      return o.index
    end
  end
  return nil
end

--- The answer to an open card (an Events.pending view): 1 or 2 to choose that option, "ignore" to ignore it now, nil to
--- leave it until its window runs out. Always takes one roll, so the stream never depends on the cards.
function EventPolicy.answer(self, view)
  local roll = self.rng:int(1, 3)
  if self.mode == "careful" then
    return flagged(view, "careful") or "ignore"
  elseif self.mode == "bold" then
    return flagged(view, "bold") or "ignore"
  elseif self.mode == "random" then
    if roll == 3 then
      return nil
    end
    return view.options[roll].affordable and roll or "ignore"
  end
  return nil
end

return EventPolicy
