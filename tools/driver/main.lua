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
  out=dir                   where PNGs go           (default docs/screens, must exist)
Scenarios: ]]

local function run(opts)
  if #opts.scenarios == 0 or opts.help then
    print(USAGE .. table.concat(scenarioNames(), ", "))
    return true
  end
  local Driver = require("driver")
  local outDir = opts.out or (root .. "/docs/screens")
  local sizes = { "desktop", "phone", "landscape" }
  if opts.size and opts.size ~= "both" then
    sizes = { opts.size }
  end
  local names = opts.scenarios
  if names[1] == "all" then
    names = scenarioNames()
  end
  for _, name in ipairs(names) do
    local chunk = assert(love.filesystem.load("scenarios/" .. name .. ".lua"))
    local scenario = chunk()
    for _, size in ipairs(sizes) do
      print(string.format("== %s (%s)", name, size))
      local d = Driver.new({ size = size, outDir = outDir, prefix = name .. "_" .. size })
      scenario(d)
    end
  end
  return true
end

function love.load(args)
  local ok, err = xpcall(function()
    return run(parseArgs(args))
  end, debug.traceback)
  if not ok then
    io.stderr:write("driver failed: " .. tostring(err) .. "\n")
  end
  love.event.quit(ok and 0 or 1)
end
