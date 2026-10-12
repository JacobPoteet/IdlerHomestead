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
    rod = 30,
    placeMin = 80,
    plan = 46,
    routine = 54,
    journal = 56,
    fish = 42,
    catalog = 56,
    pantry = 52,
  },
}
