-- Test runner. From the repo root:  lovec tests   (or: love tests)
-- Runs every tests/test_*.lua file and exits with status 1 if anything failed.
-- Optional filter: lovec tests rng   -> only files whose name contains "rng".
-- Optional jobs=N: how many files run at once, each in its own child process (default
-- min(8, CPUs); jobs=1 runs everything in this process, which is what a debugger wants).

-- Resolve game modules (src.*, data.*) from the game/ folder relative to the repo root.
package.path = "game/?.lua;game/?/init.lua;" .. package.path

local T = require("harness")

-- Files that take far longer than the rest start first, so the pool does not end waiting on one.
local SLOW_FIRST = { "test_balance_smoke.lua" }

local function parseArgs(args)
  local opts = {}
  for _, a in ipairs(args or {}) do
    local k, v = a:match("^(%w+)=(.*)$")
    if k then
      opts[k] = v
    else
      opts.filter = a
    end
  end
  return opts
end

local function listFiles(filter)
  local files = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:match("^test_.*%.lua$") and (not filter or name:find(filter, 1, true)) then
      files[#files + 1] = name
    end
  end
  table.sort(files)
  for i = #SLOW_FIRST, 1, -1 do
    for n, name in ipairs(files) do
      if name == SLOW_FIRST[i] then
        table.remove(files, n)
        table.insert(files, 1, name)
        break
      end
    end
  end
  return files
end

--- Run each file in its own `lovec tests <file> jobs=1` child, `jobs` at a time, echo the
--- children's output in order and add up their "N passed, M failed" lines. A child that printed no
--- such line (it crashed) counts as one failure. Returns the number of failures.
local function runParallel(files, jobs)
  local source = love.filesystem.getSource()
  local running, nextFile, passed, failed = {}, 1, 0, 0
  local function launch()
    while #running < jobs and nextFile <= #files do
      local name = files[nextFile]
      nextFile = nextFile + 1
      local cmd = string.format('"%s" "%s" %s jobs=1 2>&1"', arg[-2], source, name)
      running[#running + 1] = { name = name, pipe = assert(io.popen('"' .. cmd, "r"), "cannot start " .. name) }
    end
  end
  launch()
  while #running > 0 do
    local job = table.remove(running, 1)
    local out = job.pipe:read("*a")
    job.pipe:close()
    local p, f = out:match("(%d+) passed, (%d+) failed")
    if p then
      passed, failed = passed + tonumber(p), failed + tonumber(f)
      -- A passing file adds nothing but its summary; only failures and stray prints are worth showing.
      out = out:gsub("\n?%d+ passed, %d+ failed\n?", "")
      if out:find("%S") then
        io.write(out, "\n")
      end
    else
      failed = failed + 1
      io.write("FAIL ", job.name, " (child process died)\n", out, "\n")
    end
    launch()
  end
  print(string.format("\n%d passed, %d failed", passed, failed))
  return failed
end

function love.load(args)
  local opts = parseArgs(args)
  local files = listFiles(opts.filter)
  local jobs = tonumber(opts.jobs) or math.min(8, love.system.getProcessorCount())
  if jobs > 1 and #files > 1 then
    love.event.quit(runParallel(files, jobs) > 0 and 1 or 0)
    return
  end
  for _, file in ipairs(files) do
    T.beginFile(file)
    local chunk = assert(love.filesystem.load(file))
    local ok, err = pcall(chunk)
    if not ok then
      T.fileError(file, err)
    end
  end
  local failed = T.summary()
  love.event.quit(failed > 0 and 1 or 0)
end
