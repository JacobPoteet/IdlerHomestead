-- The pixel font (GDD §9.4, D142, #291): every glyph is well formed, and every character in the game's
-- content and tuning text has a glyph, so no word ever prints with a hole in it.
local T = require("harness")
local utf8 = require("utf8")
local PixelFont = require("src.ui.pixel_font")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")

T.test("every glyph has rows of one width, at most 9 rows, of '.' and '#' only", function()
  for code = 32, 126 do
    local ch = string.char(code)
    local rows = PixelFont.glyph(ch)
    T.truthy(rows, "no glyph for " .. string.format("%q", ch))
    T.truthy(#rows >= 1 and #rows <= PixelFont.HEIGHT, "row count of " .. ch)
    for _, row in ipairs(rows) do
      T.eq(#row, #rows[1], "row width of " .. ch)
      T.truthy(not row:find("[^.#]"), "stray character in " .. ch)
    end
  end
end)

-- Every string reachable from a table, visited once.
local function eachString(value, fn, seen)
  seen = seen or {}
  if type(value) == "string" then
    fn(value)
  elseif type(value) == "table" and not seen[value] then
    seen[value] = true
    for k, v in pairs(value) do
      eachString(k, fn, seen)
      eachString(v, fn, seen)
    end
  end
end

T.test("every character in content and tuning text has a glyph", function()
  local missing = {}
  local function check(str)
    if not utf8.len(str) then
      return -- not text (binary data never reaches the font)
    end
    for _, code in utf8.codes(str) do
      local ch = utf8.char(code)
      if code >= 32 and not PixelFont.glyph(ch) then
        missing[ch] = str
      end
    end
  end
  local reg = Registry.new():loadAll()
  for _, kind in ipairs(require("data.content.init")) do
    for _, def in ipairs(reg:all(kind)) do
      eachString(def, check)
    end
  end
  eachString(tuningLoader.load(), check)
  for ch, str in pairs(missing) do
    T.truthy(false, string.format("no glyph for %q (in %q)", ch, str:sub(1, 60)))
  end
end)
