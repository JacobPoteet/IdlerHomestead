-- Performance probe (#19). From the repo root:
--   lovec tools/perf [key=value ...]
-- Plays a balance-harness policy to a mid-game state, then measures the sim over a window of ticks:
-- wall ms per tick (total and per system), allocation per tick (GC stopped), the object counts of the
-- state, and the save file size and encode/decode time. Timing is wall-clock, so only compare numbers
-- from the same machine; the allocation and size figures are deterministic. The regression test
-- (tests/test_perf_budget.lua) counts operations instead of time.
--   policy=active|scripted|idle   who plays the warm-up       (default active)
--   seed=N                        run seed                    (default 1)
--   warm=DAYS                     in-game days to play first  (default 84: three years, the active policy
--                                 has coop, pump, drip lines, solar, wind, battery and freezer by then;
--                                 42 is mid year 2 with only a coop)
--   ticks=N                       ticks in each measured window (default 2000)
--   set=domain.key=value          tuning override (repeatable), e.g. set=world.mapWidth=192
--   saves=N                       save/load repetitions       (default 5)

package.path = "game/?.lua;game/?/init.lua;tools/balance/?.lua;" .. package.path

local function parseArgs(args)
  local opts = { sets = {} }
  for _, arg in ipairs(args or {}) do
    local key, value = arg:gsub("^%-+", ""):match("^([%w_]+)=(.*)$")
    if key == "set" then
      opts.sets[#opts.sets + 1] = value
    elseif key then
      opts[key] = value
    end
  end
  return opts
end

local function now()
  return love.timer.getTime()
end

local function percentile(sorted, p)
  return sorted[math.max(1, math.min(#sorted, math.ceil(#sorted * p)))]
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

function love.load(args)
  local ok, err = xpcall(function()
    local opts = parseArgs(args)
    local Balance = require("balance")
    local Features = require("features")
    local Finds = require("src.sim.systems.finds")
    local Policies = require("policies")
    local Save = require("src.core.save")
    local Session = require("src.session")
    local serialize = require("src.core.serialize")

    Balance.applyOverrides(opts.sets)
    local ctx = Balance.context()
    local tuning = ctx.tuning
    local policyName = opts.policy or "active"
    local seed = tonumber(opts.seed) or 1
    local warmDays = tonumber(opts.warm) or 84
    local window = tonumber(opts.ticks) or 2000
    local saveReps = tonumber(opts.saves) or 5

    local data = Save.newSlotData("perf")
    local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
    local session =
      Session.new({ store = store, slot = 1, data = data, registry = ctx.registry, tuning = tuning, seed = seed })
    local world = session.world
    local step = 1 / tuning.time.tickRate
    local policy = Policies.new(policyName, world, seed, Features.parse(nil))
    local decisionTicks = math.max(1, math.floor(tuning.idle.recheckInterval * tuning.time.tickRate + 0.5))
    world.events:on("calendar.newDay", function()
      policy:daily(world)
    end)

    local tickNo = 0
    local function play(runTick)
      local offer = Finds.pending(world)
      if offer then
        Finds.choose(world, policy:chooseFind(world, offer))
      end
      if tickNo % decisionTicks == 0 then
        policy:step(world)
      end
      runTick()
      tickNo = tickNo + 1
    end

    local plain = function()
      world:tick(step)
    end
    local warmTicks = math.floor(warmDays * tuning.time.dayLength * tuning.time.tickRate)
    local started = now()
    for _ = 1, warmTicks do
      play(plain)
    end
    io.write(
      string.format(
        "warm-up: %s seed %d, %d days (%d ticks) in %.1fs\n",
        policyName,
        seed,
        warmDays,
        warmTicks,
        now() - started
      )
    )

    -- State size.
    local grid = world.state.grid
    local owned = {}
    for _, obj in pairs(grid.objects) do
      owned[obj.id] = (owned[obj.id] or 0) + 1
    end
    local ids = {}
    for id in pairs(owned) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
      parts[#parts + 1] = id .. "=" .. owned[id]
    end
    io.write(
      string.format(
        "state: map %dx%d, %d objects: %s\n",
        grid.w,
        grid.h,
        countKeys(grid.objects),
        table.concat(parts, " ")
      )
    )

    -- Window A: wall time per tick, total and per system (GC running as in play).
    local systems = world.systems
    local names = require("src.sim.systems.init")
    local perSystem, perMax, totals = {}, {}, {}
    for i = 1, #systems do
      perSystem[i], perMax[i] = 0, 0
    end
    local function timed()
      local t0 = now()
      world.state.tick = world.state.tick + 1
      for i = 1, #systems do
        local tick = systems[i].tick
        if tick then
          local s0 = now()
          tick(world, step)
          local spent = now() - s0
          perSystem[i] = perSystem[i] + spent
          if spent > perMax[i] then
            perMax[i] = spent
          end
        end
      end
      totals[#totals + 1] = now() - t0
    end
    for _ = 1, window do
      play(timed)
    end
    table.sort(totals)
    local sum = 0
    for _, t in ipairs(totals) do
      sum = sum + t
    end
    io.write(
      string.format(
        "sim ms/tick over %d ticks: mean %.3f  p50 %.3f  p95 %.3f  p99 %.3f  max %.3f\n",
        #totals,
        sum / #totals * 1000,
        percentile(totals, 0.5) * 1000,
        percentile(totals, 0.95) * 1000,
        percentile(totals, 0.99) * 1000,
        totals[#totals] * 1000
      )
    )
    local over1, over4 = 0, 0
    for _, t in ipairs(totals) do
      over1 = over1 + (t > 0.001 and 1 or 0)
      over4 = over4 + (t > 0.004 and 1 or 0)
    end
    io.write(string.format("  ticks over 1 ms: %d, over 4 ms: %d\n", over1, over4))
    local order = {}
    for i = 1, #systems do
      order[#order + 1] = i
    end
    table.sort(order, function(a, b)
      return perSystem[a] > perSystem[b]
    end)
    local top = {}
    for k = 1, math.min(8, #order) do
      local i = order[k]
      top[#top + 1] = string.format("%s %.3f", names[i], perSystem[i] / window * 1000)
    end
    io.write("  top systems (mean ms/tick): " .. table.concat(top, ", ") .. "\n")
    table.sort(order, function(a, b)
      return perMax[a] > perMax[b]
    end)
    top = {}
    for k = 1, math.min(5, #order) do
      top[#top + 1] = string.format("%s %.3f", names[order[k]], perMax[order[k]] * 1000)
    end
    io.write("  worst single tick by system (ms): " .. table.concat(top, ", ") .. "\n")

    -- Window B: allocation per tick with the collector stopped.
    collectgarbage("collect")
    collectgarbage("stop")
    local perTick, allocMax = {}, {}
    for i = 1, #systems do
      allocMax[i] = 0
    end
    local tickAlloc = 0
    local function counted()
      world.state.tick = world.state.tick + 1
      tickAlloc = 0
      for i = 1, #systems do
        local tick = systems[i].tick
        if tick then
          local before = collectgarbage("count")
          tick(world, step)
          local grew = collectgarbage("count") - before
          tickAlloc = tickAlloc + grew
          allocMax[i] = math.max(allocMax[i], grew)
        end
      end
    end
    for _ = 1, window do
      play(counted)
      perTick[#perTick + 1] = tickAlloc
    end
    collectgarbage("restart")
    table.sort(perTick)
    local allocSum = 0
    for _, kb in ipairs(perTick) do
      allocSum = allocSum + kb
    end
    io.write(
      string.format(
        "alloc KB/tick over %d ticks (sim only, policy excluded): mean %.2f  p50 %.2f  p95 %.2f  max %.2f\n",
        #perTick,
        allocSum / #perTick,
        percentile(perTick, 0.5),
        percentile(perTick, 0.95),
        perTick[#perTick]
      )
    )

    table.sort(order, function(a, b)
      return allocMax[a] > allocMax[b]
    end)
    top = {}
    for k = 1, math.min(4, #order) do
      top[#top + 1] = string.format("%s %.1f", names[order[k]], allocMax[order[k]])
    end
    io.write("  worst single tick by system (KB): " .. table.concat(top, ", ") .. "\n")

    -- Save size and time.
    local wr, rd, size = 0, 0, 0
    for _ = 1, saveReps do
      local t0 = now()
      assert(store:write(1, data))
      wr = wr + (now() - t0)
      size = store.backend.size("slot1.sav")
      t0 = now()
      assert(store:read(1))
      rd = rd + (now() - t0)
    end
    local plainSize = #serialize.encode(data)
    io.write(
      string.format(
        "save: %d bytes on disk (%d via serialize alone), write %.1f ms, read %.1f ms (mean of %d)\n",
        size,
        plainSize,
        wr / saveReps * 1000,
        rd / saveReps * 1000,
        saveReps
      )
    )
    local run = data.run
    local sections = {}
    for key, value in pairs(run) do
      sections[#sections + 1] = { key, #serialize.encode(value) }
    end
    table.sort(sections, function(a, b)
      return a[2] > b[2]
    end)
    local big = {}
    for k = 1, math.min(6, #sections) do
      big[#big + 1] = string.format("%s %d", sections[k][1], sections[k][2])
    end
    io.write("  largest run sections (bytes, plain encode): " .. table.concat(big, ", ") .. "\n")
    for _, key in ipairs({ "terrain", "soil", "waterTable", "objects" }) do
      if type(grid[key]) == "table" then
        io.write(string.format("  grid.%s: %d bytes\n", key, #serialize.encode(grid[key])))
      end
    end
  end, debug.traceback)
  if not ok then
    io.stderr:write(tostring(err), "\n")
    print(tostring(err))
    love.event.quit(1)
    return
  end
  love.event.quit(0)
end
