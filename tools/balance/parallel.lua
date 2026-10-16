-- Parallel seeds for the balance harness (issue #123): plays (policy, seed) units on a pool of
-- love.thread workers, each a separate Lua state with its own registry and tuning, and hands the
-- results back in the order a single-process run produces them.
--
-- Each unit is independent (a fresh Session per seed), so a unit's results do not depend on which
-- worker played it or what it played before; tests/test_balance_smoke.lua checks that the
-- results come back identical to an in-process run. Results cross the thread boundary as Lua
-- source with every number written with 17 significant digits, which round-trips exactly.

local Parallel = {}

-- Serialization ---------------------------------------------------------------------------------

local function encodeNumber(v)
  if v ~= v then
    return "(0/0)"
  elseif v == math.huge then
    return "(1/0)"
  elseif v == -math.huge then
    return "(-1/0)"
  elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    if v == 0 and 1 / v < 0 then
      return "(-0)"
    end
    return string.format("%d", v)
  end
  return string.format("%.17g", v)
end

local function encode(v, out)
  local t = type(v)
  if t == "number" then
    out[#out + 1] = encodeNumber(v)
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, item in pairs(v) do
      out[#out + 1] = "["
      encode(k, out)
      out[#out + 1] = "]="
      encode(item, out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  else
    error("parallel: cannot serialize a " .. t, 0)
  end
end

--- Lossless plain-data serializer (tables, finite and non-finite numbers, strings, booleans).
function Parallel.encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

function Parallel.decode(s)
  local chunk = assert(loadstring("return " .. s, "=parallel result"))
  setfenv(chunk, {})
  return chunk()
end

-- Pool ------------------------------------------------------------------------------------------

--- Default worker count: the CPU count, capped (more threads than this mostly costs memory).
Parallel.MAX_DEFAULT_JOBS = 16

function Parallel.defaultJobs()
  local ok, system = pcall(require, "love.system")
  local cpus = ok and system and system.getProcessorCount() or 1
  return math.max(1, math.min(cpus, Parallel.MAX_DEFAULT_JOBS))
end

local WORKER_PATH = "tools/balance/worker.lua"

--- Play every (policy, seed) unit on `jobs` worker threads.
--- spec: { names = {...}, seeds = N, seed0 = N, years = N, runs = N, features = string|nil, outfit = string|nil,
---         sets = { "domain.key=value", ... }, jobs = N, onProgress = function(done, total) }
--- Returns results[policy][seed] = the list Balance.playSeed returns for that seed.
function Parallel.play(spec)
  require("love.thread")
  require("love.filesystem")
  local fh = assert(io.open(WORKER_PATH, "rb"), "parallel: cannot read " .. WORKER_PATH .. " (run from the repo root)")
  local code = fh:read("*a")
  fh:close()

  local units = {}
  for _, name in ipairs(spec.names) do
    for s = 0, spec.seeds - 1 do
      units[#units + 1] = { name, spec.seed0 + s }
    end
  end
  local jobs = math.max(1, math.min(spec.jobs, #units))
  local work, done = love.thread.newChannel(), love.thread.newChannel()
  for _, unit in ipairs(units) do
    work:push(unit[1] .. "\t" .. unit[2])
  end
  for _ = 1, jobs do
    work:push("") -- one stop marker per worker
  end
  local config = Parallel.encode({
    years = spec.years,
    runs = spec.runs,
    features = spec.features or false,
    outfit = spec.outfit or false,
    sets = spec.sets or {},
  })
  local threads = {}
  for n = 1, jobs do
    local thread = love.thread.newThread(love.filesystem.newFileData(code, "worker.lua"))
    thread:start(config, work, done)
    threads[n] = thread
  end

  local results = {}
  for _, name in ipairs(spec.names) do
    results[name] = {}
  end
  local received = 0
  local function stop(message)
    work:clear()
    for _ = 1, jobs do
      work:push("")
    end
    for _, thread in ipairs(threads) do
      thread:wait()
    end
    error(message, 0)
  end
  while received < #units do
    local msg = done:demand(1)
    if msg then
      local kind, name, seed, payload = msg:match("^(%a+)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if kind == "error" then
        stop(string.format("worker failed on %s seed %s:\n%s", name, seed, payload))
      end
      results[name][tonumber(seed)] = Parallel.decode(payload)
      received = received + 1
      if spec.onProgress then
        spec.onProgress(received, #units)
      end
    else
      for _, thread in ipairs(threads) do
        local err = thread:getError()
        if err then
          stop("worker thread died:\n" .. err)
        end
      end
    end
  end
  for _, thread in ipairs(threads) do
    thread:wait()
    local err = thread:getError()
    if err then
      error("worker thread died:\n" .. err, 0)
    end
  end
  return results
end

return Parallel
