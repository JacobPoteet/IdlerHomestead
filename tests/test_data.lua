local T = require("harness")
local tuning = require("src.core.tuning")
local Registry = require("src.core.registry")

-- Tuning ---------------------------------------------------------------------

T.test("tuning: all domains load and are strict", function()
  local tun = tuning.load()
  T.eq(type(tun.time.tickRate), "number")
  T.errors(function()
    return tun.time.tickRat
  end, "tuning.time")
  T.errors(function()
    return tun.nonexistentDomain
  end, "tuning")
end)

T.test("tuning: every value has a comment (unit/intent)", function()
  for _, domain in ipairs(require("data.tuning.init")) do
    local path = "game/data/tuning/" .. domain .. ".lua"
    local fh = assert(io.open(path, "r"), "cannot open " .. path)
    for line in fh:lines() do
      local key = line:match("^%s*([%a_][%w_]*)%s*=")
      if key then
        T.truthy(line:find("%-%-"), path .. ": '" .. key .. "' needs a comment with unit and intent")
      end
    end
    fh:close()
  end
end)

-- Registry -------------------------------------------------------------------

local schema = { name = "string", weight = "number?" }

T.test("registry: loads the game's content", function()
  local reg = Registry.new():loadAll()
  T.eq(reg:get("resources", "wood").name, "Wood")
  T.truthy(#reg:all("resources") > 0)
end)

T.test("registry: get/has/all", function()
  local reg = Registry.new()
  reg:addKind("things", { { id = "a", name = "A" }, { id = "b", name = "B", weight = 2 } }, schema)
  T.eq(reg:get("things", "b").weight, 2)
  T.eq(reg:get("things", "a").weight, nil) -- optional & absent reads as nil
  T.truthy(reg:has("things", "a"))
  T.falsy(reg:has("things", "zzz"))
  T.eq(reg:all("things")[2].id, "b")
  T.errors(function()
    reg:get("things", "zzz")
  end, "Unknown things id 'zzz'")
end)

T.test("registry: rejects bad definitions", function()
  T.errors(function()
    Registry.new():addKind("t", { { id = "a" } }, schema)
  end, "missing required field 'name'")
  T.errors(function()
    Registry.new():addKind("t", { { id = "a", name = 3 } }, schema)
  end, "should be string")
  T.errors(function()
    Registry.new():addKind("t", { { id = "a", name = "A", wieght = 1 } }, schema)
  end, "unknown field 'wieght'")
  T.errors(function()
    Registry.new():addKind("t", { { id = "a", name = "A" }, { id = "a", name = "B" } }, schema)
  end, "duplicate id")
end)

T.test("registry: definitions reject new fields and typo reads", function()
  local reg = Registry.new()
  reg:addKind("t", { { id = "a", name = "A" } }, schema)
  local def = reg:get("t", "a")
  T.errors(function()
    def.colour = "red"
  end, "Cannot add field")
  T.errors(function()
    return def.nmae
  end, "not a field")
end)
