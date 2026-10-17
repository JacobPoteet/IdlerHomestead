-- Statuses (D166, #345, docs/PLAN_DEPTH.md §7): the caps and floors that keep an injury slow and never stuck. The
-- statuses themselves are content (data/content/statuses.lua); the system is src/sim/systems/status.lua.
return {
  minWorkSpeed = 0.35, -- multiplier (0..1): the statuses together never slow work under this share of normal speed, so the game is slow, not stuck (PLAN_DEPTH §7)
  maxActiveStatuses = 3, -- statuses at once: families escalate, not stack, and different families coexist up to this many; a new one past it only replaces the shortest-lived (PLAN_DEPTH §6.5)
  drainFloor = 1, -- Condition points: a status's daily drain never takes Condition under this, so an injury makes survival harder and cannot kill (PLAN_DEPTH §6.5)
}
