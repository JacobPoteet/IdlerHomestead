-- Journal search by node name (GDD D120, #208). Pure logic, no drawing and no world: the scene passes
-- the chapters and a status lookup, so the rules are unit-tested headless (tests/test_journal_search.lua).
--
-- THE RULE: a node whose name the player does not know yet (status "unknown", still ???) never matches,
-- and nothing about the result may tell how many such nodes there are. So the search never looks at an
-- unknown node's name at all, and the result list holds only nodes the player may already read.

local Search = {}

--- The query as it is matched: trimmed and lower case. "" means no search is active.
function Search.normalize(query)
  return ((query or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower())
end

--- The nodes whose known name contains the query (case-insensitive, plain substring), in journal order:
--- { { id, name, chapter = index, chapterName, status } }. Nil for an empty query (no search), an empty
--- list for a query nothing known matches.
function Search.find(chapters, statusOf, query)
  local needle = Search.normalize(query)
  if needle == "" then
    return nil
  end
  local out = {}
  for index, chapter in ipairs(chapters) do
    for _, def in ipairs(chapter.nodes) do
      local status = statusOf(def.id)
      if status ~= "unknown" and def.name:lower():find(needle, 1, true) then
        out[#out + 1] = { id = def.id, name = def.name, chapter = index, chapterName = chapter.name, status = status }
      end
    end
  end
  return out
end

--- The chapter index to reopen on: the one with id `chapterId`, or nil when there is none (not remembered,
--- or no longer in the journal), so the caller falls back to its default.
function Search.rememberedIndex(chapters, chapterId)
  if not chapterId then
    return nil
  end
  for i, chapter in ipairs(chapters) do
    if chapter.id == chapterId then
      return i
    end
  end
  return nil
end

return Search
