-- The message log (D90, #167): the last N things the toasts said, newest first, so a toast that came and
-- went (or was replaced) while the player slept, read a panel or looked away can still be read. Pure
-- UI state: the scene feeds it the same events its toasts come from; it is not part of the sim or a save.
--
-- A line is { text, count, day, hour }. The same text twice in a row is one line with a count, and the
-- pieces of one multi-part event (storage overflowing for several resources in the same moment) merge
-- into a single line ("Storage full: lost 3 wood, 2 stone") when they arrive within `window` game seconds.

local MessageLog = {}
MessageLog.__index = MessageLog

--- `cap` is the number of lines kept (tuning.ui.log.maxLines), `window` the game seconds within which
--- pieces of one event merge (tuning.ui.log.coalesceSeconds).
function MessageLog.new(cap, window)
  return setmetatable({ cap = cap, window = window, entries = {} }, MessageLog)
end

local function trim(self)
  while #self.entries > self.cap do
    table.remove(self.entries, 1)
  end
end

--- Add a line. `stamp` = { day, hour, at = game seconds }.
function MessageLog:add(text, stamp)
  local last = self.entries[#self.entries]
  if last and not last.tag and last.text == text then
    last.count, last.day, last.hour, last.at = last.count + 1, stamp.day, stamp.hour, stamp.at
    return
  end
  self.entries[#self.entries + 1] = { text = text, count = 1, day = stamp.day, hour = stamp.hour, at = stamp.at }
  trim(self)
end

--- Add one piece of a multi-part event: `format` has one %s for the pieces joined by commas. A piece
--- joins the last line when that is the same `tag` and recent enough; otherwise it starts a new line.
function MessageLog:addPart(tag, part, format, stamp)
  local last = self.entries[#self.entries]
  if last and last.tag == tag and stamp.at - last.at <= self.window then
    last.parts[#last.parts + 1] = part
    last.text = string.format(format, table.concat(last.parts, ", "))
    last.day, last.hour, last.at = stamp.day, stamp.hour, stamp.at
    return
  end
  self.entries[#self.entries + 1] = {
    text = string.format(format, part),
    count = 1,
    tag = tag,
    parts = { part },
    day = stamp.day,
    hour = stamp.hour,
    at = stamp.at,
  }
  trim(self)
end

--- The lines, newest first: { { text, count, day, hour } }.
function MessageLog:lines()
  local out = {}
  for i = #self.entries, 1, -1 do
    out[#out + 1] = self.entries[i]
  end
  return out
end

function MessageLog:size()
  return #self.entries
end

--- "Day 3 06:12" for a line.
function MessageLog.when(line)
  return string.format("Day %d %02d:%02d", line.day, math.floor(line.hour), math.floor(line.hour % 1 * 60))
end

--- The line's text with its repeat count: "Caught a perch (x3)".
function MessageLog.label(line)
  return line.count > 1 and string.format("%s (x%d)", line.text, line.count) or line.text
end

return MessageLog
