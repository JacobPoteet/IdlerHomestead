-- Minimal test harness: T.test(name, fn) plus a few assertions.

local T = {}

local results = { passed = 0, failed = 0, failures = {} }
local currentFile = "?"

local function describe(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

function T.beginFile(file)
  currentFile = file
end

function T.fileError(file, err)
  results.failed = results.failed + 1
  results.failures[#results.failures + 1] = file .. " (load): " .. tostring(err)
end

function T.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    results.passed = results.passed + 1
  else
    results.failed = results.failed + 1
    results.failures[#results.failures + 1] = currentFile .. " > " .. name .. "\n    " .. tostring(err)
  end
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", describe(expected), describe(actual)), 2)
  end
end

function T.near(actual, expected, eps, msg)
  if math.abs(actual - expected) > (eps or 1e-9) then
    error(string.format("%sexpected ~%s, got %s", msg and (msg .. ": ") or "", describe(expected), describe(actual)), 2)
  end
end

function T.truthy(v, msg)
  if not v then
    error(msg or ("expected truthy, got " .. describe(v)), 2)
  end
end

function T.falsy(v, msg)
  if v then
    error(msg or ("expected falsy, got " .. describe(v)), 2)
  end
end

--- Assert fn errors; if `pattern` is given, the message must contain it (plain match).
function T.errors(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    error("expected an error, but none was raised", 2)
  end
  if pattern and not tostring(err):find(pattern, 1, true) then
    error(string.format("error %s does not contain %s", describe(tostring(err)), describe(pattern)), 2)
  end
end

--- Deep equality for plain tables.
function T.same(actual, expected, msg)
  local function deep(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
      return a == b
    end
    for k, v in pairs(a) do
      if not deep(v, b[k]) then
        return false
      end
    end
    for k in pairs(b) do
      if a[k] == nil then
        return false
      end
    end
    return true
  end
  if not deep(actual, expected) then
    error((msg or "tables differ"), 2)
  end
end

function T.summary()
  for _, f in ipairs(results.failures) do
    print("FAIL " .. f)
  end
  print(string.format("\n%d passed, %d failed", results.passed, results.failed))
  return results.failed
end

return T
