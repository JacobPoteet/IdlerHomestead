-- The lantern (C7, #361, D191, docs/PLAN_DEPTH.md §5.3, §6.1): a one-time buy that hangs by the door at night. It burns no fuel
-- and needs no chore. Every number is a first guess for the M9 balance pass.
return {
  guards = { -- threat id -> chance (0..1) added to that threat's own guard roll while the lantern is owned; a threat not listed is not covered (the mice are the cat's, weather nights are not guarded)
    fox = 0.25, -- hens and goats: light by the coop makes a fox think twice
    raccoon = 0.3, -- the stores: a raccoon keeps to the dark
    bear = 0.15, -- partly: a bear is not afraid of a lantern, so the bear box stays the answer
  },
}
