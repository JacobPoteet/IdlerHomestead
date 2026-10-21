-- Harness gates (#410, D184, docs/PLAN_DEPTH.md §15): pass/fail checks read off a policy summary. A gate is a report line,
-- not a rule of the sim; it never changes a run. `gates=strict` makes the harness exit 1 when one fails, so a script can
-- hold a build to them; by default they are only printed. Every limit below is a first guess (the M9 pass sets them).
--
--   idle reaches Footing     the idle policy (the routine alone, every upkeep task on) earns Footing in at least
--                            `idleFootingShare` of its runs: "an idle player must do fine" (D184)
--   idle does not starve     no more than `idleStarveShare` of the idle runs die of hunger in year 1
--   no death spiral          of the runs that slipped, at most `spiralDeathShare` died while still slipped
--   no event-caused failure  (paired runs only) at most `eventFailShare` of the paired runs fail with events on and
--                            survive the same seed with them off

local Gates = {}

Gates.LIMITS = {
  idleFootingShare = 0.9, -- share of idle runs that must earn Footing
  idleStarveShare = 0, -- share of idle runs allowed to starve in year 1
  spiralDeathShare = 0.25, -- share of slipped runs allowed to die still slipped
  eventFailShare = { -- share of paired runs allowed to fail only with events on, by policy (default for the rest)
    active = 0.05,
    human = 0.15,
    default = 0.10,
  },
}

local function gate(id, text, value, limit, atLeast, note)
  local pass = nil
  if value ~= nil then
    pass = atLeast and value >= limit - 1e-9 or (not atLeast and value <= limit + 1e-9)
  end
  return { id = id, text = text, value = value, limit = limit, atLeast = atLeast, pass = pass, note = note }
end

--- The gates that apply to `policyName`'s summary, as a list of { id, text, value, limit, atLeast, pass, note }. `pass` is
--- nil when the gate has nothing to measure (no run slipped, no paired run); the value is a share 0..1.
function Gates.evaluate(policyName, summary)
  local limits = Gates.LIMITS
  local list = {}
  if policyName == "idle" then
    list[#list + 1] =
      gate("idleFooting", "idle reaches Footing", summary.footing.reachedFraction, limits.idleFootingShare, true)
    list[#list + 1] = gate(
      "idleStarve",
      "idle does not starve in year 1",
      summary.spiral.yearOneStarved / math.max(1, summary.n),
      limits.idleStarveShare,
      false
    )
  end
  local sp = summary.spiral
  list[#list + 1] = gate(
    "spiral",
    "no death spiral (slipped runs that die slipped)",
    sp.slippedRuns > 0 and sp.slipToDeath or nil,
    limits.spiralDeathShare,
    false,
    sp.slippedRuns == 0 and "no run slipped" or nil
  )
  if summary.paired then
    local cap = limits.eventFailShare[policyName] or limits.eventFailShare.default
    list[#list + 1] = gate(
      "eventFailure",
      "no event-caused failure (fail with events on, live with them off)",
      summary.paired.n > 0 and summary.paired.eventCausedShare or nil,
      cap,
      false
    )
  end
  return list
end

return Gates
