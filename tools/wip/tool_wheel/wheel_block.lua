  wheel = { -- the tool wheel (src/ui/tool_wheel.lua, GDD §9.4, D138); UI pixels and degrees unless noted
    wedges = { -- the six tools and their fixed directions (0 = right, 90 = down): never reorder after release
      { id = "hand", angle = -60 },
      { id = "hoe", angle = 0 },
      { id = "pail", angle = 60 },
      { id = "axe", angle = 120 },
      { id = "rod", angle = 180 },
      { id = "hammer", angle = 240 },
    },
    holdTime = 0.18, -- real seconds a still right-press is held before the wheel opens (a quicker click inspects)
    showDelay = 0.12, -- real seconds after opening before the wheel is drawn: a flick released sooner equips without it
    spread = 24, -- degrees between the items of a tool's ring
    maxFan = 150, -- degrees the widest ring may fan; more items sit closer together
    maxRing = 9, -- ring items shown at most; a longer list ends in a More item that opens the full tray
    smallWidth = 300, -- views narrower than this use the small sizes
    normal = { radius = 58, wedge = 32, selected = 36, ring = 106, ringItem = 28, subRadius = 84, deadZone = 14 },
    small = { radius = 48, wedge = 28, selected = 30, ring = 84, ringItem = 26, subRadius = 68, deadZone = 12 },
    dim = { 0.03, 0.03, 0.05, 0.22 }, -- rgba: the world behind the wheel, darkened in a stepped ring round it
  },
