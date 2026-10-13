-- Compact on-disk form of the grid's per-tile arrays (#21, D103). In memory `state.grid.terrain`,
-- `soil` and `waterTable` stay plain arrays; only the saved file holds them as short strings:
--
--   terrain     "ids:grass,water,dirt;a12b3c4"   palette of ids, then runs of (palette letter, count)
--   soil,       "hundredths:45*3,46,47*12"       tile values as whole hundredths, runs as value*count
--   waterTable
--
-- Exact by construction: a numeric array is packed only when every value is a whole number of
-- hundredths that divides back to the very same double (`n / 100 == v`, which is how landgen made them),
-- and a terrain array only when it is a dense array of palette-sized strings. Anything else is left as
-- the plain array, and unpack accepts either form, so no input can fail to round-trip.
-- Pure data; no love, no sim.

local Gridpack = {}

local LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local NUMERIC = { "soil", "waterTable" }

local function packTerrain(list)
  local n = #list
  if n == 0 then
    return nil
  end
  local palette, index, runs = {}, {}, {}
  local current, count = nil, 0
  for i = 1, n do
    local id = list[i]
    if type(id) ~= "string" or id:find("[,;]") then
      return nil
    end
    if not index[id] then
      if #palette >= #LETTERS then
        return nil
      end
      palette[#palette + 1] = id
      index[id] = #palette
    end
    if id == current then
      count = count + 1
    else
      if current then
        runs[#runs + 1] = LETTERS:sub(index[current], index[current]) .. count
      end
      current, count = id, 1
    end
  end
  runs[#runs + 1] = LETTERS:sub(index[current], index[current]) .. count
  return "ids:" .. table.concat(palette, ",") .. ";" .. table.concat(runs)
end

local function unpackTerrain(text)
  local palette, runs = text:match("^ids:([^;]*);(.*)$")
  if not palette then
    error("gridpack: malformed terrain", 0)
  end
  local ids = {}
  for id in palette:gmatch("[^,]+") do
    ids[#ids + 1] = id
  end
  local list, n = {}, 0
  for letter, count in runs:gmatch("(%a)(%d+)") do
    local id = ids[LETTERS:find(letter, 1, true)]
    if not id then
      error("gridpack: terrain run uses an unknown id", 0)
    end
    for _ = 1, tonumber(count) do
      n = n + 1
      list[n] = id
    end
  end
  return list
end

local function packNumbers(list)
  local n = #list
  if n == 0 then
    return nil
  end
  local tokens = {}
  local current, count = nil, 0
  local function flush()
    tokens[#tokens + 1] = count > 1 and (current .. "*" .. count) or tostring(current)
  end
  for i = 1, n do
    local v = list[i]
    if type(v) ~= "number" or v ~= v or v < 0 or v > 1 or (v == 0 and 1 / v < 0) then
      return nil
    end
    local hundredths = math.floor(v * 100 + 0.5)
    if hundredths / 100 ~= v then
      return nil
    end
    if hundredths == current then
      count = count + 1
    else
      if current then
        flush()
      end
      current, count = hundredths, 1
    end
  end
  flush()
  return "hundredths:" .. table.concat(tokens, ",")
end

local function unpackNumbers(text)
  local body = text:match("^hundredths:(.*)$")
  if not body then
    error("gridpack: malformed numbers", 0)
  end
  local list, n = {}, 0
  for value, count in body:gmatch("(%d+)%*?(%d*),?") do
    local v = tonumber(value) / 100
    for _ = 1, count == "" and 1 or tonumber(count) do
      n = n + 1
      list[n] = v
    end
  end
  return list
end

--- A copy of `grid` for the file: the per-tile arrays that can be packed exactly are strings. The
--- grid itself is untouched.
function Gridpack.pack(grid)
  local out = {}
  for k, v in pairs(grid) do
    out[k] = v
  end
  if type(grid.terrain) == "table" then
    out.terrain = packTerrain(grid.terrain) or grid.terrain
  end
  for _, key in ipairs(NUMERIC) do
    if type(grid[key]) == "table" then
      out[key] = packNumbers(grid[key]) or grid[key]
    end
  end
  return out
end

--- Restore the plain arrays in a grid just read from a file (in place). Plain arrays pass through.
--- Raises on a damaged string, so the caller can treat the slot as unreadable.
function Gridpack.unpack(grid)
  if type(grid.terrain) == "string" then
    grid.terrain = unpackTerrain(grid.terrain)
  end
  for _, key in ipairs(NUMERIC) do
    if type(grid[key]) == "string" then
      grid[key] = unpackNumbers(grid[key])
    end
  end
  return grid
end

return Gridpack
