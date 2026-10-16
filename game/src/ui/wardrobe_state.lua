-- The Wardrobe's draft (docs/PLAN_WARDROBE_MENU.md §3): the outfit the player is trying on, apart from the one
-- chosen. A tap or a focus previews a garment into the draft; Reset puts the draft back; only Wear (a call into
-- the wardrobe system) changes what is chosen. Pure (no love.*). The draft and the slot shown are remembered for
-- the session, so a stray Esc never loses a careful outfit; they are never saved.

local WardrobeState = {}
local State = {} -- the draft's methods (the module's own reset forgets the session, so they are kept apart)
State.__index = State

local memory -- { draft = { slot = id }, slot = slot id } from the last time the Wardrobe closed, or nil

--- Forget the remembered draft and slot (a new session, and tests).
function WardrobeState.reset()
  memory = nil
end

--- What was remembered when the Wardrobe last closed: { draft, slot }, or nil.
function WardrobeState.last()
  return memory
end

local function copy(outfit)
  local out = {}
  for slot, id in pairs(outfit) do
    out[slot] = id
  end
  return out
end

--- A draft that starts as `committed` (`{ slot = garmentId }`, the outfit chosen). `owned(id)` says whether the
--- player has a garment; a garment that is not owned never enters the draft (every id is owned when omitted).
function WardrobeState.new(committed, owned)
  return setmetatable({ committedOutfit = copy(committed), outfit = copy(committed), owned = owned }, State)
end

--- Try a garment on in a slot. Returns false (and changes nothing) for a garment that is not owned.
function State:preview(slot, id)
  if self.owned and not self.owned(id) then
    return false
  end
  self.outfit[slot] = id
  return true
end

--- Put the draft back to the chosen outfit.
function State:reset()
  self.outfit = copy(self.committedOutfit)
end

--- Take a whole outfit into the draft, skipping the garments that are not owned (a preset saved before one was
--- lost cannot happen today, but a preset never overrides the rule). `name` is kept for the scene to show.
function State:loadPreset(outfit, name)
  for slot, id in pairs(outfit) do
    if not self.owned or self.owned(id) then
      self.outfit[slot] = id
    end
  end
  self.presetName = name
end

--- The chosen outfit changed (a Wear, or a dawn that moved it): the draft is measured against this from now on.
function State:setCommitted(outfit)
  self.committedOutfit = copy(outfit)
end

--- Does the draft differ from the chosen outfit?
function State:changed()
  for slot, id in pairs(self.outfit) do
    if self.committedOutfit[slot] ~= id then
      return true
    end
  end
  return false
end

--- The draft, `{ slot = id }` (the live table: read it, do not write it).
function State:draft()
  return self.outfit
end

--- The outfit chosen, `{ slot = id }` (the live table).
function State:committed()
  return self.committedOutfit
end

--- Remember this draft and the slot shown for the session. A draft equal to the chosen outfit leaves nothing to
--- remember, and clears what was. `slot` is the tab showing.
function WardrobeState.remember(state, slot)
  if state:changed() then
    memory = { draft = copy(state.outfit), slot = slot }
  else
    memory = { slot = slot }
  end
end

--- Put a remembered draft back into this state, keeping only the garments that are still owned and fit the slot
--- they were saved in. Returns true when a draft was restored.
function State:restore()
  local last = memory
  if not (last and last.draft) then
    return false
  end
  local any = false
  for slot, id in pairs(last.draft) do
    if self.committedOutfit[slot] ~= id and (not self.owned or self.owned(id)) then
      self.outfit[slot] = id
      any = true
    end
  end
  return any
end

return WardrobeState
