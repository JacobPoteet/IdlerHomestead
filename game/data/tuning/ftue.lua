-- First-time user experience: contextual tip cards (GDD D69, #152). What each tip says and when it
-- fires lives with the step in data/content/ftue.lua; this file holds the global knobs.
return {
  minGap = 20, -- game seconds between one card being dismissed and the next one showing (stops a burst of cards)
  defaultDelay = 2, -- game seconds from a step's trigger to its card being due, when the step sets no delay of its own
  cardMaxWidth = 340, -- widest tip card, in virtual pixels (narrower views use the view width less the margin)
  cardMargin = 8, -- virtual pixels kept free at the left and right of the card
  cardPadding = 8, -- virtual pixels between the card edge and its text and buttons
  cardBottomGap = 44, -- virtual pixels between the bottom bar and the card: room for the toast and the routine badge
  highlightPad = 3, -- virtual pixels the pulsing outline sits outside the target a tip card points at (D89)
  highlightThickness = 2, -- virtual pixels, line width of the pulsing outline
  highlightPulseSeconds = 1.2, -- seconds for one pulse of the outline (a ring grows outward and fades)
  highlightGrow = 4, -- virtual pixels the fading ring grows outward at the end of a pulse
  highlightArrow = 7, -- virtual pixels, half-width of the arrow head that points at the target
  tipsColumns = 2,-- columns of step buttons in the Menu's Tips list
}
