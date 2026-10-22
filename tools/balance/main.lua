-- Balance harness CLI. From the repo root:
--   lovec tools/balance [key=value ...]
-- See tools/balance/README via docs/BALANCE.md for the options. Plain key=value arguments are used
-- because LÖVE reserves some --flags for itself.

package.path = "game/?.lua;game/?/init.lua;tools/balance/?.lua;" .. package.path

local USAGE = [[
Idler Homestead balance harness. Usage:  lovec tools/balance [key=value ...]
  policy=all|idle|scripted|active|human|a,b  policies to play       (default all; human is active made fallible, #410)
  seeds=N                               seeds per policy            (default 20)
  seed0=N                               first seed                  (default 1)
  years=N                               years to simulate per run   (default 1)
  runs=N                                runs per career: a failed run is followed by recovery (free
                                        study) and a new run with the knowledge kept     (default 1)
  features=all|none|a,b                 optional policy behaviours (default all): cat, stand, chickens, goats,
                                        water, power, machines, finds, weather; `none` plays the harness as it was
                                        before them. `rotate` is opt-in (not in `all`): replant a tile with a family other than
                                        its last, from the seeds in hand (D179). Policies: see docs/BALANCE.md
  outfit=light|mid|heavy                dress the homesteader in a whole outfit of one weight class
                                        (the wardrobe's grant and wear; default: the starter outfit, all mid)
  loadout=<id>                          every run of the career starts with that starting loadout (angler,
                                        gardener, herder, lumberjack, tinkerer; D201). The Journal unlock is skipped:
                                        this measures the loadout, not the unlock. Default: the standard start
  jobs=N                                worker threads that play seeds in parallel (default: the
                                        CPU count, at most 16); jobs=1 plays them one after another
                                        in this thread. The report and out= files are identical.
  profile=1|N                           sample the sim with LuaJIT's profiler (forces jobs=1) and
                                        print the top 25 (or N) lines and functions
  trace=1                               also print the first seed of each policy day by day
  out=path.csv|path.json                write per-day rows (csv) or summaries + runs (json)
                                        both carry Footing (#344): csv columns footing (0 no, 1 held, 2 slipped),
                                        footingDay, footingSlips; json summary.footing and per-run footing.
                                        The report prints day of Footing (median/p10/p90), the share reaching it
                                        before the first winter and slips per run. Reporting only, no target.
  events=off|ignore|careful|bold|random  the event-choice policy (D169): how the player answers misfortune
                                        event cards; off (default) plays with events disabled, so the output
                                        is what it was without them. Pair a run with the default for events on/off
  pair=1                                paired seeds (#410): play every seed twice, with events disabled and with them on
                                        under the events= policy (required), and report the runs that fail only with
                                        events on (event-caused failure) beside the usual report, which is the events-on leg
  gates=report|strict                   the pass/fail gates (idle reaches Footing and does not starve in year 1, no death
                                        spiral, no event-caused failure) always print; strict also exits 1 when one fails
                                        (default report). Limits: tools/balance/gates.lua (first guesses)
  set=domain.key=value                  override a tuning number for what-if runs (repeatable),
                                        e.g. set=needs.coldDamage=15 set=needs.warmthPeak=3
  quiet=1                               no progress lines
  help=1                                this text]]

local function parseArgs(args)
  local opts = { sets = {} }
  for _, arg in ipairs(args or {}) do
    local key, value = arg:gsub("^%-+", ""):match("^([%w_]+)=(.*)$")
    if not key then
      key, value = arg:gsub("^%-+", ""), "1"
    end
    if key == "set" then
      opts.sets[#opts.sets + 1] = value
    else
      opts[key] = value
    end
  end
  return opts
end

function love.load(args)
  local ok, err = xpcall(function()
    local opts = parseArgs(args)
    if opts.help or opts.h then
      print(USAGE)
      return
    end
    local Balance = require("balance")
    local Policies = require("policies")
    Balance.applyOverrides(opts.sets)
    require("event_policy").configure(opts.events)
    local ctx = Balance.context()

    local names = Policies.list
    if opts.policy and opts.policy ~= "all" then
      names = {}
      for name in opts.policy:gmatch("[^,]+") do
        names[#names + 1] = name
      end
    end
    local pair = opts.pair ~= nil and opts.pair ~= "0"
    assert(
      not pair or (opts.events and opts.events ~= "off"),
      "pair=1 needs an event policy: events=ignore|careful|bold|random"
    )
    assert(opts.gates == nil or opts.gates == "report" or opts.gates == "strict", "gates= must be report or strict")
    local seeds = tonumber(opts.seeds) or 20
    local seed0 = tonumber(opts.seed0) or 1
    local years = tonumber(opts.years) or 1
    local runs = tonumber(opts.runs) or 1
    local quiet = opts.quiet ~= nil
    local Features = require("features")
    local features = Features.parse(opts.features)
    local outfit = opts.outfit
    assert(
      outfit == nil or outfit == "light" or outfit == "mid" or outfit == "heavy",
      "outfit= must be light, mid or heavy"
    )

    local loadout = opts.loadout
    assert(loadout == nil or ctx.registry:has("loadouts", loadout), "loadout= must be a loadout id")

    io.write(
      string.format(
        "balance: policies=%s seeds=%d (from %d) years=%d runs=%d features=%s%s%s%s\n",
        table.concat(names, ","),
        seeds,
        seed0,
        years,
        runs,
        Features.label(features),
        outfit and (" outfit=" .. outfit) or "",
        loadout and (" loadout=" .. loadout) or "",
        pair and (" paired events off/" .. opts.events) or "",
        #opts.sets > 0 and (" overrides: " .. table.concat(opts.sets, " ")) or ""
      )
    )

    local function clock()
      return love.timer and love.timer.getTime() or os.clock()
    end
    local started = clock()

    -- jobs > 1: play every (policy, seed) on worker threads first, then report from the stored
    -- results in the same order as the plain loop below (identical output, see parallel.lua).
    local Parallel = require("parallel")
    local jobs = math.min(tonumber(opts.jobs) or Parallel.defaultJobs(), #names * seeds)
    local Profile
    if opts.profile then
      jobs = 1 -- the profiler samples this thread only
      Profile = require("profile")
      Profile.start()
    end
    local played
    if jobs > 1 then
      if not quiet then
        io.write(string.format("parallel: %d worker threads\n", jobs))
      end
      local nextReport = 10
      played = Parallel.play({
        names = names,
        seeds = seeds,
        seed0 = seed0,
        years = years,
        runs = runs,
        features = opts.features,
        outfit = outfit,
        loadout = loadout,
        events = opts.events,
        pair = pair,
        sets = opts.sets,
        jobs = jobs,
        onProgress = function(done, total)
          if not quiet and (done >= nextReport or done == total) then
            nextReport = done + 10
            io.write(string.format("  %d/%d seeds played (%.0fs)\n", done, total, clock() - started))
            io.flush()
          end
        end,
      })
      quiet = true -- the per-policy progress lines below would only repeat the above
    end
    local function playSeed(name, seed)
      if played then
        return played[name][seed]
      end
      return Balance.playSeed(ctx, name, seed, years, runs, features, outfit, opts.events, pair, loadout)
    end

    local all, report =
      {}, {
        config = { seeds = seeds, seed0 = seed0, years = years, runs = runs, overrides = opts.sets, features = Features.label(features), outfit = outfit, loadout = loadout, events = opts.events, pair = pair },
        policies = {},
      }
    for _, name in ipairs(names) do
      local byRun = {}
      for s = 0, seeds - 1 do
        for _, result in ipairs(playSeed(name, seed0 + s)) do
          byRun[result.run] = byRun[result.run] or {}
          table.insert(byRun[result.run], result)
          if opts.trace and s == 0 then
            Balance.printTrace(result)
          end
          all[#all + 1] = result
        end
        if not quiet and ((s + 1) % 10 == 0 or s + 1 == seeds) then
          io.write(string.format("  %s: %d/%d seeds (%.0fs)\n", name, s + 1, seeds, clock() - started))
          io.flush()
        end
      end
      local entry = { runs = {} }
      for r = 1, runs do
        if byRun[r] then
          local summary = Balance.summarize(ctx, byRun[r], years, name)
          Balance.printSummary(ctx, name, r, summary, years)
          Balance.printFeatures(summary, years)
          entry.runs[#entry.runs + 1] = { run = r, summary = summary }
        end
      end
      report.policies[name] = entry
    end
    local failedGates = 0
    for _, entry in pairs(report.policies) do
      for _, run in ipairs(entry.runs) do
        for _, g in ipairs(run.summary.gates) do
          failedGates = failedGates + (g.pass == false and 1 or 0)
        end
      end
    end
    if Profile then
      io.write(
        "\n",
        Profile.stop(tonumber(opts.profile) and tonumber(opts.profile) > 1 and tonumber(opts.profile) or 25)
      )
    end
    io.write(
      string.format(
        "\nTotal: %.1fs%s\n",
        clock() - started,
        played and string.format(" (%d worker threads)", jobs) or ""
      )
    )

    io.write(string.format("Gates failed: %d\n", failedGates))
    if opts.out then
      if opts.out:lower():match("%.json$") then
        report.results = {}
        for _, r in ipairs(all) do
          report.results[#report.results + 1] = Balance.runRecord(r)
          report.results[#report.results].policy = r.policy
        end
        Balance.writeJson(opts.out, report)
      else
        Balance.writeCsv(opts.out, all)
      end
      io.write("wrote " .. opts.out .. "\n")
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
