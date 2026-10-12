-- Sampling profiler for the balance harness (`profile=1`, issue #123), on LuaJIT's jit.profile.
-- Samples every millisecond of the main thread and reports the hottest lines (self time) and the
-- functions most often on the stack (inclusive time). Tool code only; never used by the game.

local Profile = {}

local selfCounts, inclusive, total = {}, {}, 0
local profiler

--- Start sampling. Errors when the runtime is not LuaJIT 2.1 (no jit.profile).
function Profile.start()
  local ok, lib = pcall(require, "jit.profile")
  assert(ok, "profile=1 needs LuaJIT's jit.profile")
  profiler = lib
  selfCounts, inclusive, total = {}, {}, 0
  profiler.start("li1", function(thread, samples)
    total = total + samples
    local top = profiler.dumpstack(thread, "pl", 1)
    selfCounts[top] = (selfCounts[top] or 0) + samples
    -- Each function counts once per sample, however deep it recurses.
    local seen = {}
    for frame in profiler.dumpstack(thread, "pF;", 40):gmatch("[^;]+") do
      if not seen[frame] then
        seen[frame] = true
        inclusive[frame] = (inclusive[frame] or 0) + samples
      end
    end
  end)
end

local function top(counts, n)
  local list = {}
  for key, count in pairs(counts) do
    list[#list + 1] = { key, count }
  end
  table.sort(list, function(a, b)
    if a[2] ~= b[2] then
      return a[2] > b[2]
    end
    return a[1] < b[1]
  end)
  local lines = {}
  for i = 1, math.min(n, #list) do
    lines[#lines + 1] = string.format("  %5.1f%%  %s", 100 * list[i][2] / math.max(1, total), list[i][1])
  end
  return table.concat(lines, "\n")
end

--- Stop sampling and return the report text (top `n` rows per view).
function Profile.stop(n)
  profiler.stop()
  n = n or 25
  return string.format(
    "Profile: %d samples (1 ms)\nHottest lines (self):\n%s\nFunctions on the stack (inclusive):\n%s\n",
    total,
    top(selfCounts, n),
    top(inclusive, n)
  )
end

return Profile
