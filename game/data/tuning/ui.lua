-- HUD layout metrics for the homestead (GDD §9): top bar, toolbar, speed/routine column.
-- All sizes are virtual pixels (the view is at least 640x360 on desktop, narrower on phones).
return {
  topBarHeight = 24, -- height of the top bar's first row (date, clock, Menu)
  compactTopBarHeight = 32, -- first-row height on narrow views, so the Menu button is a finger-sized target
  statRowHeight = 20, -- extra top-bar row used when the stats don't fit beside the date
  statGap = 9, -- space between two stats in the strip
  statMinGap = 4, -- tightest gap the strip squeezes down to; narrower than that the stats wrap to their own row
  statIconGap = 3, -- space between a stat's icon and its value
  barPadding = 6, -- left/right padding inside the top and bottom bars
  buttonHeight = 24, -- toolbar and control button height on wide views
  compactButtonHeight = 30, -- the same on narrow views (phone), where fingers need more room
  compactWidth = 480, -- views narrower than this use the compact button height
  buttonGap = 4, -- space between neighbouring buttons
  groupGap = 4, -- extra space between the tool group and the Place/Plan group
  barMargin = 5, -- vertical padding above the first toolbar row and below the last
  menuWidth = 50, -- Menu button width
  controlMinWidth = 54, -- narrowest speed/routine/power button
  controlTextPadding = 14, -- horizontal padding around a control button's label
  statsAfterDate = 162, -- left edge of the stat strip when it sits beside the date
  reportSeconds = 16, -- real seconds the morning report card waits before folding itself away (Got it closes it sooner; a tip card pauses the count)
  scrollWheelStep = 22, -- virtual pixels a list scrolls per mouse-wheel notch (about one pantry row)
  scrollBarWidth = 3, -- virtual pixels wide the scroll thumb drawn at the edge of a scrolling list
  scrollHintHeight = 12, -- virtual pixels reserved under a scrolling list for its "drag or scroll" hint
  buttonWidths = { -- toolbar button widths
    hand = 40,
    seed = 40,
    rod = 44,
    placeMin = 80,
    plan = 66,
    routine = 78,
    journal = 56,
    fish = 78,
    catalog = 56,
    pantry = 52,
    tools = 54, -- the palette button on narrow views
    more = 46, -- the books palette button on narrow views
    activeMin = 44, -- narrowest "tool in hand" shortcut beside the palette button
  },
  paletteGap = 4, -- virtual pixels between the toolbar and the palette that opens above it
  pillHeight = 14, -- height of the small status pills above the toolbar (routine badge, tool caption)
  pillGap = 4, -- space between those pills and the bar, and between two stacked pills
  chipHitPad = 2, -- virtual pixels a chip's tap target grows beyond its icon and number on each side
  labels = { -- toolbar and control button texts (D72, #168); a name that says what tapping does
    hand = "Hand",
    rod = "Rod",
    plan = "Plan field",
    routineList = "Routine list",
    startRoutine = "Start routine",
    routineOn = "Routine on",
    resting = "Resting",
    speed = "Speed %gx", -- speed button; %g is the sim speed multiplier
    skipNight = "Skip night",
    skipping = "Skipping...",
    pantry = "Pantry",
    catalog = "Catalog",
    fishGuide = "Fish guide",
    journal = "Journal",
    power = "Power",
    tools = "Tools",
    more = "More",
    place = "Place",
    tripReady = "ready", -- added to the truck charge chip while a trip to town is possible
  },
  captions = { -- one line saying what the tool in hand does on the next tap (D72, #168); %s is the seed or object name
    rod = "Rod: tap the water to fish",
    seed = "%s in hand: tap open ground to till and plant",
    plan = "Plan field: tap two corners",
    planSeed = "Plan %s: tap two corners",
    planClear = "Plan field: tap two corners to clear a plan",
    place = "Placing %s: tap where it goes",
  },
  badges = { -- the routine badge above the toolbar (D72, #168); %d is seconds
    asleep = "Sleeping",
    paused = "Paused",
    running = "Routine running: tap to take over",
    resting = "Resting hours: the routine sleeps too",
    countdown = "Routine starts in %ds if you stop tapping",
  },
  startRoutineHint = "Starts the routine now. It waters, plants, harvests and chops for you; any tap ends it.", -- toast when the routine starts
}
