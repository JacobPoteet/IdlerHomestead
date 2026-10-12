-- Balance harness CLI. From the repo root:
--   lovec tools/balance [key=value ...]
-- See tools/balance/README via docs/BALANCE.md for the options. Plain key=value arguments are used
-- because LÖVE reserves some --flags for itself.

package.path = "game/?.lua;game/?/init.lua;tools/balance/?.lua;" .. package.path

local USAGE = [[
Idler Homestead balance harness. Usage:  lovec tools/balance [key=value ...]
  policy=all|idle|scripted|active|a,b   policies to play            (default all)
  seeds=N                               seeds per policy            (default 20)
  seed0=N                               first seed                  (default 1)
  years=N                               years to simulate per run   (default 1)
  runs=N                                runs per career: a failed run is followed by recovery (free
                                        study) and a new run with the knowledge kept     (default 1)
  trace=1                               also print the first seed of each policy day by day
  out=path.csv|path.json                write per-day rows (csv) or summaries + runs (json)
  set=domain.key=value                  override a tuning number for what-if runs (repeatable),
                                        e.g. set=needs.coldDamage=15 set=needs.dailyWarmth.winter=3
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
    local ctx = Balance.context()

    local names = Policies.list
    if opts.policy and opts.policy ~= "all" then
      names = {}
      for name in opts.policy:gmatch("[^,]+") do
        names[#names + 1] = name
      end
    end
    local seeds = tonumber(opts.seeds) or 20
    local seed0 = tonumber(opts.seed0) or 1
    local years = tonumber(opts.years) or 1
    local runs = tonumber(opts.runs) or 1
    local quiet = opts.quiet ~= nil

    io.write(
      string.format(
        "balance: policies=%s seeds=%d (from %d) years=%d runs=%d%s\n",
        table.concat(names, ","),
        seeds,
        seed0,
        years,
        runs,
        #opts.sets > 0 and (" overrides: " .. table.concat(opts.sets, " ")) or ""
      )
    )

    local started = os.clock()
    local all, report = {}, { config = { seeds = seeds, seed0 = seed0, years = years, runs = runs, overrides = opts.sets }, policies = {} }
    for _, name in ipairs(names) do
      local byRun = {}
      for s = 0, seeds - 1 do
        for _, result in ipairs(Balance.playSeed(ctx, name, seed0 + s, years, runs)) do
          byRun[result.run] = byRun[result.run] or {}
          table.insert(byRun[result.run], result)
          if opts.trace and s == 0 then
            Balance.printTrace(result)
          end
          all[#all + 1] = result
        end
        if not quiet and ((s + 1) % 10 == 0 or s + 1 == seeds) then
          io.write(string.format("  %s: %d/%d seeds (%.0fs)\n", name, s + 1, seeds, os.clock() - started))
          io.flush()
        end
      end
      local entry = { runs = {} }
      for r = 1, runs do
        if byRun[r] then
          local summary = Balance.summarize(ctx, byRun[r], years)
          Balance.printSummary(ctx, name, r, summary, years)
          entry.runs[#entry.runs + 1] = { run = r, summary = summary }
        end
      end
      report.policies[name] = entry
    end
    io.write(string.format("\nTotal: %.1fs\n", os.clock() - started))

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
