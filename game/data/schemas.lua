-- Field schemas for each content kind (see src/core/registry.lua for the spec format).
-- Unknown fields in content files are rejected, so add new fields here first.
return {
  resources = {
    name = "string", -- display name
    category = "string", -- grouping for UI: currency | material | supply | food | ...
    capacity = "number?", -- default storage cap; absent means unlimited until storage buildings set one
  },
}
