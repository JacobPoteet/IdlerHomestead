-- Smoke test for the balance harness (tools/balance, issue #31): one seed, a short span, every
-- policy. Keeps the harness from rotting; real runs are done with `lovec tools/balance`.
local T = require("harness")

package.path = "tools/balance/?.lua;" .. package.path
local Balance = require("balance")
local Policies = require("policies")

local ctx = Balance.context()
local WEEK = 0.25 -- years: one season (7 days)

T.test("balance harness: every policy plays one seed for a season, deterministically", function()
  for _, name in ipairs(Policies.list) do
    local a = Balance.playSeed(ctx, name, 1, WEEK, 1)
    local b = Balance.playSeed(ctx, name, 1, WEEK, 1)
    T.eq(#a, 1)
    T.eq(a[1].alive, b[1].alive, name .. " alive")
    T.eq(a[1].final.money, b[1].final.money, name .. " money repeats")
    T.eq(a[1].final.warmth, b[1].final.warmth, name .. " warmth repeats")
    T.truthy(a[1].snaps[2], name .. " recorded the first morning")
  end
end)

T.test("balance harness: summaries, careers after failure, and tuning overrides", function()
  local results = Balance.playSeed(ctx, "idle", 1, WEEK, 2)
  T.eq(results[1].alive, false, "an idle player with no plan starves in the first spring")
  T.eq(results[1].cause, "hunger")
  T.eq(results[2] and results[2].run, 2, "a failed run is followed by a second run")
  local summary = Balance.summarize(ctx, { results[1] }, 1)
  T.eq(summary.n, 1)
  T.eq(summary.failed, 1)
  T.eq(#summary.points, #ctx.tuning.time.seasons)
  T.truthy(Balance.jsonEncode(summary):find("daysSurvived", 1, true))
  T.errors(function()
    Balance.applyOverrides({ "needs.noSuchKnob=1" })
  end, "no such number")
end)
