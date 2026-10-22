-- Contracts (D197, #372, docs/PLAN_DEPTH.md §9.2): the town's board. Opens at Footing (A4, Footing.isOpen with a bare gate).
--
-- Each market week (tuning.economy.daysPerWeek, the week the prices turn on) the board offers `offersPerWeek` contracts picked
-- from data/content/contracts.lua: a good the run has held, a number of units, a deadline of `deadlineMin` to `deadlineMax`
-- days and a reward of the good's base value x units x a multiplier. Standing orders (`standing = true` in the content) are the
-- repeating weekly orders: one of each is open at a time and a new one is posted every `standingDays` days once the last is
-- filled or has lapsed (the idle-friendly income). Nothing
-- is forced and nothing is punished: a contract that passes its deadline just lapses (Contracts.expire), no reputation is lost,
-- nothing is owed. Reputation is a plain count of contracts finished (`done`): it adds `rewardPerDone` to the reward multiplier
-- (to `doneCap`) and opens richer goods (`minDone` in the content). No quality tiers, no levels.
--
-- Filling takes the goods from the surplus (stock above the keep target, Food.surplus), so it can never dig into a kept reserve
-- and cannot cause a slip of Footing. A contract is filled all at once, at the town: by the player (the board, in town) or
-- automatically when the truck load is sold (Market.sellLoad, so the default Auto-load trip fills what it can with no input).
-- A contract's reward is fixed when it is posted and it adds nothing to the market's saturation (D196): it is a named buyer.
-- While Footing is slipped no new offers are rolled (D168); deadlines keep running, and an open contract can still be filled.
--
-- State: world.state.contracts = { done (contracts finished), week (the week last rolled), serial, seen = { [resourceId] = true }
--   (goods the run has held: only those are asked for), nextStanding = { [defId] = first day the next standing order may be posted }, open = { { id, def, item, amount, reward, due (last day to fill),
--   posted (day), standing } } }.
-- Emits "contract.offered" { id, def, standing }, "contract.done" { id, item, amount, reward, standing, done },
--       "contract.expired" { id, item, standing }.

local Calendar = require("src.sim.systems.calendar")
local Food = require("src.sim.systems.food")
local Footing = require("src.sim.systems.footing")
local Ledger = require("src.sim.systems.ledger")
local Quality = require("src.sim.systems.quality")

local Contracts = {}

local OPEN = { footing = true } -- the bare gate of the board (D164)

local function state(world)
  return world.state.contracts
end

local function weekOf(world, day)
  return math.floor((day - 1) / world.tuning.economy.daysPerWeek) + 1
end

--- Is the board open (Footing held, slipped or not)?
function Contracts.isOpen(world)
  return Footing.isOpen(world, OPEN)
end

--- Contracts finished: the town's reputation of the run.
function Contracts.reputation(world)
  return state(world).done
end

--- The reward multiplier now: the base for the kind, plus a step per contract finished up to the cap.
function Contracts.rewardMult(world, standing)
  local cfg = world.tuning.contracts
  local base = standing and cfg.standingMult or cfg.rewardMult
  return base + cfg.rewardPerDone * math.min(state(world).done, cfg.doneCap)
end

local function rewardFor(world, def, amount)
  local value = world.registry:get("resources", def.item).value
  return math.max(1, math.floor(value * amount * Contracts.rewardMult(world, def.standing) + 0.5))
end

--- The open contracts, soonest deadline first (a live list: do not change it).
function Contracts.list(world)
  local open = state(world).open
  table.sort(open, function(a, b)
    if a.due ~= b.due then
      return a.due < b.due
    end
    return a.id < b.id
  end)
  return open
end

--- Days left to fill a contract (0 on its last day).
function Contracts.daysLeft(world, contract)
  return contract.due - Calendar.now(world).day
end

--- Units of the contract's good that may go to it: the surplus above the keep target.
function Contracts.available(world, contract)
  return Food.surplus(world, contract.item)
end

local function post(world, def, rng)
  local st = state(world)
  local cfg = world.tuning.contracts
  local day = Calendar.now(world).day
  local amount = rng:int(def.min, def.max)
  local cap = Ledger.capacity(world, def.item)
  if amount > cap then
    amount = math.max(1, math.floor(cap))
  end
  local days = def.standing and cfg.standingDays or rng:int(cfg.deadlineMin, cfg.deadlineMax)
  local contract = {
    id = st.serial,
    def = def.id,
    item = def.item,
    amount = amount,
    reward = rewardFor(world, def, amount),
    posted = day,
    due = day + days,
    standing = def.standing or false,
  }
  st.serial = st.serial + 1
  st.open[#st.open + 1] = contract
  world.events:emit("contract.offered", { id = contract.id, def = def.id, standing = contract.standing })
end

--- Post the standing orders that are due: one per standing definition, when none is open and `standingDays` have passed
--- since the last was posted (filling early does not bring the next one sooner). Nothing while the board is closed or
--- Footing is slipped.
function Contracts.rollStanding(world)
  local st = state(world)
  if not Contracts.isOpen(world) or Footing.paused(world) then
    return
  end
  local day = Calendar.now(world).day
  local rng = world:rng("market")
  for _, def in ipairs(world.registry:all("contracts")) do
    if def.standing and st.seen[def.item] and (def.minDone or 0) <= st.done then
      local open = false
      for _, c in ipairs(st.open) do
        open = open or c.def == def.id
      end
      if not open and day >= (st.nextStanding[def.id] or 0) then
        st.nextStanding[def.id] = day + world.tuning.contracts.standingDays
        post(world, def, rng)
      end
    end
  end
end

--- Roll this week's offers now: `offersPerWeek` board contracts. Does nothing when the board is closed, Footing is slipped
--- or the week was already rolled. Returns true when it rolled. The standing orders come with it (Contracts.rollStanding).
function Contracts.roll(world)
  local st = state(world)
  local week = weekOf(world, Calendar.now(world).day)
  if not Contracts.isOpen(world) or Footing.paused(world) then
    return false
  end
  Contracts.rollStanding(world)
  if st.week == week then
    return false
  end
  st.week = week
  local rng = world:rng("market")
  local pool = {}
  for _, def in ipairs(world.registry:all("contracts")) do
    if not def.standing and st.seen[def.item] and (def.minDone or 0) <= st.done then
      pool[#pool + 1] = def
    end
  end
  rng:shuffle(pool)
  for n = 1, math.min(world.tuning.contracts.offersPerWeek, #pool) do
    post(world, pool[n], rng)
  end
  return true
end

--- Drop the contracts whose deadline has passed. No penalty, no reputation lost; they just lapse.
function Contracts.expire(world)
  local st = state(world)
  local day = Calendar.now(world).day
  local i = 1
  while i <= #st.open do
    local c = st.open[i]
    if c.due < day then
      table.remove(st.open, i)
      world.events:emit("contract.expired", { id = c.id, item = c.item, standing = c.standing })
    else
      i = i + 1
    end
  end
end

--- Why a contract cannot be filled now (nil if it can): "short" with the units missing as the second result.
function Contracts.cannotFill(world, contract, available)
  local have = available or Contracts.available(world, contract)
  if have < contract.amount then
    return "short", contract.amount - have
  end
  return nil
end

--- Fill a contract from the surplus (or `available`, units the caller lets it take). All or nothing. Returns the
--- reward, or nil plus the reason.
function Contracts.fill(world, id, available)
  local st = state(world)
  for i, c in ipairs(st.open) do
    if c.id == id then
      local reason, missing = Contracts.cannotFill(world, c, available)
      if reason then
        return nil, reason, missing
      end
      table.remove(st.open, i)
      Quality.take(world, c.item, c.amount, "worst") -- the plainest units go; the best stay for sale
      Ledger.remove(world, c.item, c.amount, "contract")
      Ledger.add(world, "money", c.reward, "contract")
      st.done = st.done + 1
      world.events:emit("contract.done", {
        id = c.id,
        item = c.item,
        amount = c.amount,
        reward = c.reward,
        standing = c.standing,
        done = st.done,
      })
      return c.reward
    end
  end
  return nil, "gone"
end

--- Fill every open contract the surplus covers, soonest deadline first (what the truck sale does). Returns the list of
--- { item, amount, reward } filled.
function Contracts.fillAll(world)
  local filled = {}
  if not Contracts.isOpen(world) then
    return filled
  end
  local ids = {}
  for _, c in ipairs(Contracts.list(world)) do
    ids[#ids + 1] = c.id
  end
  for _, id in ipairs(ids) do
    local c = Contracts.find(world, id)
    local reward = c and Contracts.fill(world, id)
    if reward then
      filled[#filled + 1] = { item = c.item, amount = c.amount, reward = reward }
    end
  end
  return filled
end

--- The open contract with this id, or nil.
function Contracts.find(world, id)
  for _, c in ipairs(state(world).open) do
    if c.id == id then
      return c
    end
  end
  return nil
end

--- Units a good has promised to open contracts (for the board's own text).
function Contracts.promised(world, item)
  local n = 0
  for _, c in ipairs(state(world).open) do
    if c.item == item then
      n = n + c.amount
    end
  end
  return n
end

function Contracts.init(world)
  if not world.state.contracts then
    local seen = {}
    for _, res in ipairs(world.registry:all("resources")) do
      if res.value and Ledger.get(world, res.id) > 0 then
        seen[res.id] = true
      end
    end
    world.state.contracts = { done = 0, week = 0, serial = 1, seen = seen, open = {}, nextStanding = {} }
  end
  world.events:on("ledger.changed", function(e)
    local seen = state(world).seen
    if e.delta > 0 and not seen[e.id] then
      seen[e.id] = true
    end
  end)
  world.events:on("calendar.newDay", function()
    Contracts.expire(world)
    Contracts.roll(world)
  end)
  world.events:on("footing.gained", function()
    Contracts.roll(world)
  end)
  world.events:on("footing.regained", function()
    Contracts.roll(world)
  end)
end

return Contracts
