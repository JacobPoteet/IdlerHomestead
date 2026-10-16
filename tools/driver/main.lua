-- Screenshot driver CLI. From the repo root:
--   lovec tools/driver <scenario|all> [size=desktop|phone|landscape|both] [out=dir]
-- See tools/driver/README.md. Plays the real game through scripted input with an in-memory save
-- store (never your real saves) and writes PNG screenshots.

local source = love.filesystem.getSource() -- <repo>/tools/driver
local root = source .. "/../.."
local gameDir = root .. "/game"

-- The game's code, shaders and sprites are resolved from game/ without copying. LÖVE only lets
-- love.filesystem see the driver's own folder (mounting an outside folder is refused), so
-- require() gets a package.path entry (plain Lua io) and the few love.filesystem/newImage calls
-- the game makes on its own files fall back to reading game/ with io.
package.path = gameDir .. "/?.lua;" .. gameDir .. "/?/init.lua;" .. package.path

local function readGameFile(path)
  local f = io.open(gameDir .. "/" .. path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

local fsRead, fsGetInfo = love.filesystem.read, love.filesystem.getInfo
function love.filesystem.read(path, ...)
  if type(path) == "string" and not fsGetInfo(path) then
    local data = readGameFile(path)
    if data then
      return data, #data
    end
  end
  return fsRead(path, ...)
end
function love.filesystem.getInfo(path, ...)
  local info = fsGetInfo(path, ...)
  if info == nil and type(path) == "string" then
    local data = readGameFile(path)
    if data then
      return { type = "file", size = #data }
    end
  end
  return info
end
local newImage = love.graphics.newImage
function love.graphics.newImage(arg, ...)
  if type(arg) == "string" and not fsGetInfo(arg) then
    local data = readGameFile(arg)
    if data then
      return newImage(love.filesystem.newFileData(data, arg), ...)
    end
  end
  return newImage(arg, ...)
end

-- Audio files (#87, D100): love.audio.newSource and love.sound.newSoundData given a path inside game/
-- read it with io the same way. (The driver is silent by default, so this only matters for audio=1.)
if love.audio and love.audio.newSource then
  local newSource = love.audio.newSource
  function love.audio.newSource(arg, ...)
    if type(arg) == "string" and not fsGetInfo(arg) then
      local data = readGameFile(arg)
      if data then
        return newSource(love.filesystem.newFileData(data, arg), ...)
      end
    end
    return newSource(arg, ...)
  end
end
if love.sound and love.sound.newSoundData then
  local newSoundData = love.sound.newSoundData
  function love.sound.newSoundData(arg, ...)
    if type(arg) == "string" and not fsGetInfo(arg) then
      local data = readGameFile(arg)
      if data then
        return newSoundData(love.filesystem.newFileData(data, arg), ...)
      end
    end
    return newSoundData(arg, ...)
  end
end

local function parseArgs(args)
  local opts = { scenarios = {} }
  for _, a in ipairs(args or {}) do
    local k, v = a:match("^([%w_]+)=(.*)$")
    if k then
      opts[k] = v
    else
      opts.scenarios[#opts.scenarios + 1] = a
    end
  end
  return opts
end

local function scenarioNames()
  local names = {}
  for _, item in ipairs(love.filesystem.getDirectoryItems("scenarios")) do
    local name = item:match("^(.+)%.lua$")
    if name then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local USAGE = [[
Idler Homestead screenshot driver. Usage:  lovec tools/driver <scenario|all> [key=value ...]
  size=desktop|phone|landscape|both   window size to run at   (default both = all three;desktop 1280x720, phone 390x844, landscape 844x390)
  seed=N                    run seed for every scenario (default: a fixed seed per scenario, so runs repeat)
  audio=1                   play sound for real (default: silent; plays are recorded in d.audioLog)
  out=dir                  where PNGs go           (default docs/screens, must exist)
  jobs=N                   child processes at once (default min(4, CPUs); jobs=1 runs in this process)
`all` skips the frame-cost benchmarks (perf, wall); name them to run them.
Scenarios: ]]

-- Frame-cost benchmarks: they take no screenshots, so `all` leaves them out (run them by name).
local BENCHMARKS = { perf = true, wall = true }

--- Run each (scenario, size) job in its own child process, `jobs` at a time, and print each job's
--- output in order. A child is a fresh `lovec tools/driver <scenario> size=<size> jobs=1`; it prints
--- DRIVER_OK as its last line when it finished, so no exit code is needed. Returns true if all did.
local function runParallel(opts, names, sizes, jobs)
  local exe = arg[-2]
  local queue = {}
  for _, name in ipairs(names) do
    for _, size in ipairs(sizes) do
      local parts = { '"' .. exe .. '"', '"' .. love.filesystem.getSource() .. '"', name, "size=" .. size, "jobs=1" }
      for _, key in ipairs({ "seed", "audio", "out" }) do
        if opts[key] then
          parts[#parts + 1] = key .. '="' .. opts[key] .. '"'
        end
      end
      queue[#queue + 1] = { name = name, size = size, cmd = '"' .. table.concat(parts, " ") .. ' 2>&1"' }
    end
  end
  local running, nextJob, allOk = {}, 1, true
  local function launch()
    while #running < jobs and nextJob <= #queue do
      local job = queue[nextJob]
      nextJob = nextJob + 1
      job.pipe = assert(io.popen(job.cmd, "r"), "cannot start " .. job.name)
      running[#running + 1] = job
    end
  end
  launch()
  while #running > 0 do
    local job = table.remove(running, 1) -- oldest first, so output stays in scenario order
    local out = job.pipe:read("*a")
    job.pipe:close()
    io.write(out)
    if not out:find("DRIVER_OK", 1, true) then
      allOk = false
      print(string.format("FAILED: %s (%s)", job.name, job.size))
    end
    launch()
  end
  return allOk
end

local function run(opts)
  if #opts.scenarios == 0 or opts.help then
    print(USAGE .. table.concat(scenarioNames(), ", "))
    return true
  end
  local Rng = require("src.core.rng")
  local outDir = opts.out or (root .. "/docs/screens")
  local sizes = { "desktop", "phone", "landscape" }
  if opts.size and opts.size ~= "both" then
    sizes = { opts.size }
  end
  local names = opts.scenarios
  if names[1] == "all" then
    names = {}
    for _, name in ipairs(scenarioNames()) do
      if not BENCHMARKS[name] then
        names[#names + 1] = name
      end
    end
  end
  local jobs = tonumber(opts.jobs) or math.min(4, love.system.getProcessorCount())
  for _, name in ipairs(names) do
    if BENCHMARKS[name] then
      jobs = 1 -- a timing run beside other processes measures the neighbours too
    end
  end
  if jobs > 1 and #names * #sizes > 1 then
    return runParallel(opts, names, sizes, jobs)
  end
  local Driver = require("driver")
  for _, name in ipairs(names) do
    local chunk = assert(love.filesystem.load("scenarios/" .. name .. ".lua"))
    local scenario = chunk()
    for _, size in ipairs(sizes) do
      print(string.format("== %s (%s)", name, size))
      -- Fixed seed per scenario (#188); seed=N overrides it for every scenario.
      local seed = tonumber(opts.seed) or Rng.hash(name)
      local d = Driver.new({
        size = size,
        outDir = outDir,
        prefix = name .. "_" .. size,
        seed = seed,
        audio = opts.audio == "1",
      })
      scenario(d)
    end
  end
  print("DRIVER_OK")
  return true
end

function love.load(args)
  local ok, result = xpcall(function()
    return run(parseArgs(args))
  end, debug.traceback)
  if not ok then
    io.stderr:write("driver failed: " .. tostring(result) .. "\n")
  end
  love.event.quit((ok and result) and 0 or 1)
end
