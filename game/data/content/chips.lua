-- Top-bar chips (GDD D72, D112): the short modal a tap on a chip opens. The chip itself carries the state
-- (number, bar, level mark, trend arrow); the modal is one headline, a few labelled numbers, at most one
-- action and an optional one-line "why". src/ui/chip_text.lua picks the state and fills the numbers from
-- the same accessors the chip reads; this file only holds the words.
--   name: modal title.
--   status: headline by state key (the states each chip can be in are listed per entry); never longer than a phrase.
--   rows: { key, label, fmt }; the value is string.format(fmt, ...) of what chip_text computes for `key`
--         (a row with no value in the current state is skipped).
--   why: optional one short line by state key, shown only for that state (say what to do about it).
--   panel / panelLabel: the one action, the panel it opens ("pantry" | "power" | "catalog" | "load"); absent = no action.
return {
  {
    id = "weather",
    name = "Weather",
    -- States: the kind of today's weather ("clear" ... "storm"), or "cold" during a cold snap.
    status = {
      clear = "Clear today",
      cloudy = "Cloudy today",
      rain = "Rain today",
      windy = "Windy today",
      storm = "Storm today",
      cold = "Cold snap",
    },
    rows = {}, -- one row per visible day is added by chip_text (day name, kind)
    why = {
      clear = "Full sun for solar. Water the crops by hand.",
      cloudy = "Solar makes less. Fish bite better.",
      rain = "Rain waters the crops and fills the cistern.",
      windy = "Turbines make more. Fish bite less.",
      storm = "Turbines make the most. Storms raise raid and hail odds.",
      cold = "Nights burn extra wood.",
    },
    panel = "power",
    panelLabel = "Open Power",
  },
  {
    id = "money",
    name = "Money",
    status = { have = "Cash in hand" },
    rows = {
      { key = "cash", label = "Money", fmt = "$%d" },
      { key = "load", label = "Truck load worth", fmt = "$%d" },
    },
    panel = "catalog",
    panelLabel = "Open Catalog",
  },
  {
    id = "food",
    name = "Food",
    status = { ok = "Food is fine", low = "Food is low", bad = "Almost out of food" }, -- by alert level
    rows = {
      { key = "days", label = "Lasts", fmt = "%.1f days" },
      { key = "perDay", label = "Eaten each day", fmt = "%d cal" },
    },
    why = { low = "Harvest, fish or buy canned food.", bad = "Harvest, fish or buy canned food." },
    panel = "pantry",
    panelLabel = "Open Pantry",
  },
  {
    id = "condition",
    name = "Health",
    status = { ok = "Healthy", low = "Health is falling", bad = "Health is dangerously low" },
    rows = {
      { key = "hp", label = "Health", fmt = "%d of %d" },
    },
    why = { low = "Eat and keep warm.", bad = "Eat and keep warm." },
    panel = "pantry",
    panelLabel = "Open Pantry",
  },
  {
    id = "battery",
    name = "Truck charge",
    -- States: ready (a trip is possible), charging, draining, idle.
    status = { ready = "Ready for a trip", charging = "Charging", draining = "Draining", idle = "Not charging" },
    rows = {
      { key = "charge", label = "Charge", fmt = "%.1f of %d kWh" },
      { key = "cost", label = "A trip needs", fmt = "%d kWh" },
      { key = "rate", label = "Right now", fmt = "%+.1f kW" },
    },
    why = { idle = "Spare solar, wind or hydro charges it." },
    panel = "power",
    panelLabel = "Open Power",
  },
  {
    id = "surplus",
    name = "Spare goods",
    status = { spare = "Goods to sell", none = "Nothing spare" },
    rows = {
      { key = "spare", label = "Above keep", fmt = "%d units" },
      { key = "loaded", label = "On the truck", fmt = "%d units" },
      { key = "worth", label = "Worth in town", fmt = "$%d" },
    },
    panel = "load",
    panelLabel = "Load the truck",
  },
  {
    id = "wood",
    name = "Wood",
    -- States: ok, low, bad (alert levels), none (no fire needed tonight), nofire (a fire is needed, none placed).
    status = {
      ok = "Enough wood",
      low = "Wood is low",
      bad = "Not enough for tonight",
      none = "No fire needed tonight",
      nofire = "No fire to burn it in",
      full = "Store is full",
    },
    rows = {
      { key = "stock", label = "Logs", fmt = "%d of %d" },
      { key = "perNight", label = "Tonight's fire", fmt = "%d logs" },
      { key = "nights", label = "Lasts", fmt = "%.1f nights" },
    },
    why = {
      low = "Fell trees or buy wood.",
      bad = "Fell trees or buy wood.",
      nofire = "Place a campfire or stove.",
      full = "A woodshed holds more.",
    },
    panel = "pantry",
    panelLabel = "Open Pantry",
  },
  {
    id = "spoiled",
    name = "Spoiling tonight",
    status = { rot = "Food will rot tonight" },
    rows = {
      { key = "units", label = "Units lost", fmt = "%d" },
    },
    why = { rot = "Eat, sell or smoke it first." },
    panel = "pantry",
    panelLabel = "Open Pantry",
  },
  {
    id = "water",
    name = "Cistern",
    status = { ok = "Water in store", low = "Water is low", bad = "Almost dry" },
    rows = {
      { key = "stored", label = "Stored", fmt = "%d of %d" },
    },
    why = { low = "Rain or a pump refills it.", bad = "Rain or a pump refills it." },
    panel = "power",
    panelLabel = "Open Power",
  },
  {
    id = "hens",
    name = "Hens",
    status = { ok = "Flock is fed", short = "Short of feed or water", none = "No hens yet" },
    rows = {
      { key = "count", label = "Hens", fmt = "%d of %d" },
      { key = "feedDays", label = "Feed lasts", fmt = "%.1f days" },
    },
    why = { short = "Top up the feed and water." },
    panel = "catalog",
    panelLabel = "Open Catalog",
  },
  {
    id = "eggs",
    name = "Eggs",
    status = { some = "Eggs waiting", none = "No eggs yet" },
    rows = {
      { key = "nest", label = "In the nest box", fmt = "%d" },
    },
    why = { some = "Tap the coop to collect them." },
  },
  {
    id = "goats",
    name = "Goats",
    status = { ok = "Herd is fed", low = "Hay is running low", short = "Short of hay or water", none = "No goats yet" },
    rows = {
      { key = "count", label = "Goats", fmt = "%d of %d" },
      { key = "feedDays", label = "Hay lasts", fmt = "%.1f days" },
    },
    why = { low = "Buy hay.", short = "Top up the hay and water." },
    panel = "catalog",
    panelLabel = "Open Catalog",
  },
  {
    id = "milk",
    name = "Milk",
    status = { some = "Milk waiting", none = "No milk yet" },
    rows = {
      { key = "pail", label = "In the pail", fmt = "%d" },
    },
    why = { some = "It does not keep: use it or make cheese." },
  },
}
