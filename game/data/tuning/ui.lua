-- HUD layout metrics for the homestead (GDD §9.4): the resting HUD's plates, trays and panels.
-- All sizes are virtual pixels (the view is at least 640x360 on desktop, narrower on phones).
return {
  statIconGap = 3, -- space between a stat's icon and its value
  buttonHeight = 24, -- tray and panel button height on wide views
  compactButtonHeight = 30, -- the same on narrow views (phone), where fingers need more room
  compactWidth = 480, -- views narrower than this use the compact button height
  buttonGap = 4, -- space between neighbouring buttons
  controlTextPadding = 14, -- horizontal padding around a control button's label
  reportSeconds = 16, -- real seconds the morning report card waits before folding itself away (Got it closes it sooner; a tip card pauses the count)
  storageNoteRefresh = 0.5, -- game seconds between re-scans for which full stores are holding something back (the "Full:" pill, D93)
  planLatchWindow = 0.5, -- real seconds in which a second tap on Plan latches the tool on (touch counterpart of holding Shift, D94); a slower tap turns it off
  planLatchToast = "Plan kept on after each plan. Tap Plan to stop.", -- toast when the Plan latch turns on
  scrollWheelStep = 22, -- virtual pixels a list scrolls per mouse-wheel notch (about one pantry row)
  scrollPageOverlap = 22, -- virtual pixels of the old view kept when Page Up/Down scrolls, so the eye keeps its place (about one pantry row)
  flingMinSpeed = 120, -- virtual pixels per second a drag must be moving at release to coast on (below it the list stops where the finger left it)
  flingMaxSpeed = 2400, -- virtual pixels per second the coast is capped at, so a flick cannot throw a short list past its end unseen
  flingBlend = 0.5, -- 0..1 weight of the newest frame's drag speed against the average so far (higher follows the last motion more closely)
  flingStaleTime = 0.1, -- real seconds a held finger may rest before release; after that the list does not coast
  flingFriction = 4, -- per second; a coast slows by this rate (the speed falls to a third in about a quarter second)
  flingStopSpeed = 12, -- virtual pixels per second under which a coast ends cleanly, so the list never creeps
  scrollBarWidth = 3, -- virtual pixels wide the scroll thumb drawn at the edge of a scrolling list
  catalogCheat = { -- the Catalog's debug cheat mode (D126): only offered while the F1 debug overlay is on, or while cheating
    button = "Debug", -- label of the toggle beside Close
    buttonWidth = 48, -- view px
    tag = "CHEAT", -- the on-screen mark while cheat mode is on
    subtitle = "Every item listed - free, handed over at once", -- replaces the money line while cheating
    row = "Get", -- the row button's label in cheat mode
    granted = "Cheat: got %s", -- toast after a grant
  },
  sandbox = { -- the Sandbox save mode's words (D134)
    tag = "SANDBOX", -- the mark in the slot list, the Catalog and on the homestead screen
    modeTitle = "Game mode", -- title of the choice shown when a new homestead is started
    modeMessage = "Normal: the full survival game.\nSandbox: everything is free and the homesteader cannot die. A sandbox earns no progress.", -- body of that choice
    normal = "Normal", -- the button that starts a normal homestead
    sandbox = "Sandbox", -- the button that starts a sandbox homestead
    subtitle = "Sandbox: every item listed - free, handed over at once", -- replaces the Catalog's money line
    granted = "Got %s", -- toast after a grant
    priceFree = "Free in a sandbox", -- the item card's price line
    nowFree = "Sandbox: free, and it goes straight to your inventory", -- the "Right now" line of a grantable item
  },
  scrollHintHeight = 12, -- virtual pixels reserved under a scrolling list for its "drag or scroll" hint
  buttonWidths = { -- tray button widths (the tools tray, the books' trays)
    hand = 40,
    seed = 40,
    rod = 44,
    untill = 54,
    placeMin = 80,
    plan = 66,
  },
  paletteMaxRows = 4, -- rows of buttons a tray shows at once; more seeds or tools scroll (drag, wheel, keys) with a thumb beside them (D87, #184)
  pillHeight = 14, -- height of the small pills: the tool caption over the tool badge, the forecast lines
  chipHitPad = 2, -- virtual pixels a chip's tap target grows beyond its icon and number on each side
  labels = { -- HUD and tray button texts (D72, #168, D137); a name that says what tapping does
    hand = "Hand",
    rod = "Rod",
    untill = "Untill",
    plan = "Plan field",
    routineList = "Routine list",
    startRoutine = "Start routine",
    routineOn = "Routine on",
    resting = "Resting",
    speed = "Speed %gx", -- speed button; %g is the sim speed multiplier
    pantry = "Pantry",
    catalog = "Catalog",
    fishGuide = "Fish guide",
    journal = "Journal",
    tools = "Tools",
    place = "Place",
    moving = "Moving",
    tripReady = "ready", -- added to the truck charge chip while a trip to town is possible
    log = "Log", -- the message log, on the Notebook's tray (D90)
    pause = "Pause", -- speed plate: stop time
    play = "Play", -- speed plate: normal speed
    fast = "Fast", -- speed plate: the fast speeds, 2x then 4x on each tap
    menu = "Menu",
    notebook = "Notebook", -- book plate: what you know (Journal, Fish guide, Diary) (D140)
    ledger = "Ledger", -- book plate: what you run (Pantry, Routine, Catalog, Truck & town) (D140)
    hoe = "Hoe", -- the tool wheel's tools (D138); Hand and Rod are above
    pail = "Pail",
    axe = "Axe",
    hammer = "Hammer",
    more = "More", -- the last item of a ring too long to show: opens the full tray
    hammerMove = "Move", -- the Hammer's ring and modes (D139): tap a building to move it
    hammerPickUp = "Pick up", -- tap a building to put it back in the crate
    hammerDemolish = "Demolish", -- tap a building or a crop to destroy it (asks first)
    orderMore = "Order more", -- the Hammer's ring: opens the Catalog on its buildings
    journalStamp = "Pick an idea", -- decision stamp: the Journal has an idea to choose and nothing is queued
    deliveryStamp = "Delivered: %s", -- decision stamp: an item waits in the crate to be placed; %s is its name
    crateStamp = "%d in the crate", -- the same stamp when more than one thing waits (D139); %d is the count
  },
  captions = { -- one line saying what the tool in hand does on the next tap (D72, #168); %s is the seed or object name
    rod = "Rod: tap the water to fish",
    pail = "Pail: tap a thirsty crop to water it", -- D138
    axe = "Axe: tap a tree, rock, log or brush to clear it", -- D138
    untill = "Untill: tap a crop to pull it, tap bare tilled soil to turn it back to grass",
    seed = "%s in hand: tap open ground to till and plant",
    plan = "Plan field: tap two corners",
    planSeed = "Plan %s: tap two corners (take Plan again quickly to keep it on)",
    planClear = "Plan field: tap two corners to clear a plan (take Plan again quickly to keep it on)",
    planKept = "Plan kept on: tap two corners; take Plan again to stop", -- the Plan latch is on (D94, #205); the caption is the same for a seed or a clear
    place = "Placing %s: tap where it goes",
    moving = "Moving %s: tap where it goes (Esc or another tool cancels)", -- D98, #15
    move = "Move: tap a building to choose its new spot", -- the Hammer's modes (D139)
    pickup = "Pick up: tap a building to put it back in the crate",
    demolish = "Demolish: tap a building or crop to destroy it (asks first)",
  },
  failure = { -- rescue and recovery words for what ended a run (D99, #216, #173); %s is a shelter or object name, lower case
    bothRatio = 2, -- ratio: cold and hunger both count when neither damage is at least this many times the other
    cold = "The cold got you.",
    coldIn = "The cold got you in the %s.",
    both = "Cold and hunger got you.",
    bothIn = "Cold and hunger got you in the %s.",
    coldNext = "The Shelter page of the Journal has a warmer bed: the %s.",
    coldTop = "More wood or a heater keeps the shack warm. The Shelter page of the Journal has more.",
    hunger = "You ran out of food.",
    hungerHint = "Plant early and watch the food chip; it counts the days left.",
    unknown = "Your strength gave out.",
    unknownHint = "The Journal keeps what you learned.",
    firstChange = "First change for next time:", -- label above the suggestion on the first recovery (once per slot, D99)
    firstColdNext = "Learn the %s early, from the Shelter page of the Journal.",
    firstColdTop = "Stock wood before the first freeze.",
    firstHunger = "Plant a field in the first days and keep a few days of food.",
    firstUnknown = "Spend the free study below, then plan the first week.",
  },
  greatWinter = { -- the Great Winter and the Established card (D117, #277); %s is a severity word (mild, hard, brutal)
    summaryHead = "the Great Winter (%s)", -- forecast pill: replaces "<severity> winter"
    news = "Warning: the Great Winter is coming, the hardest yet. Stock wood and food now.", -- toast when the full forecast is revealed, at the start of autumn
    cardTitle = "Established", -- celebration card title
    cardHeadline = "The Great Winter is behind you.", -- card headline
    cardMessage = "You came through the hardest winter this land has thrown at you, and the homestead is yours now. The seasons go on, and so does the work.", -- card body: what happened, in plain words
    cardOk = "Carry on", -- card button
    logLine = "Established: the Great Winter is behind you", -- message log line when the card is shown
    surviveLabel = "Great Winter", -- recovery table row label
    surviveYes = "Survived", -- recovery table cell: the run lived through the Great Winter
    surviveNo = "-", -- recovery table cell: it did not
  },
  progress = { -- progress metrics on the recovery and slot screens (D117, #275); %d is a whole number
    colThis = "This run", -- column heading
    colPrevious = "Previous run", -- column heading; left out on a slot's first run
    colBest = "Slot best", -- column heading; left out on a slot's first run
    yearsLabel = "Years survived", -- row label: full game years completed before the run ended
    yearsFormat = "%d", -- a years cell
    incomeLabel = "Best year's income", -- row label: the most sales income in one game year
    incomeFormat = "$%d", -- an income cell
    none = "-", -- a cell with no value (no previous run)
    newBest = "New best!", -- marker beside this run's cell when it beat the slot's earlier best
    firstRun = "Your first run on this slot. These numbers are the ones to beat.", -- shown instead of the extra columns on the first run
    journalLine = "Journal %d%% known", -- slot screen line; the percentage is known nodes over all, rounded down
  },
  itemCard = { -- the store's item card on a tap or long-press of a Catalog or town shop row (D107, #266); %s / %d are filled in by src/ui/item_text.lua
    width = 300, -- view px; the card's width (narrower views shrink it to fit)
    labelWidth = 52, -- view px; the left column of labels ("Gets", "Needs", ...)
    priceDelivery = "$%d + $%d delivery, arrives tomorrow",
    priceTown = "$%d, handed over on the spot",
    sale = "(on sale)",
    gets = "Gets",
    object = "A %s to place on your land",
    equipment = "Gear kept for the whole run",
    needs = "Needs",
    needsNothing = "Nothing",
    needsItem = "the %s",
    needsHome = "a %s to live in",
    needsTown = "Bought on a truck trip",
    replaces = "Replaces",
    replacesItem = "the %s",
    limit = "Limit",
    limitOne = "One per run",
    limitStore = "Your %s store holds %d (you have %d)",
    now = "Right now",
    reasons = { -- why it can't be bought at this moment, by Market.cannotBuy's answer
      owned = "You already own it",
      replaced = "You already own the better one",
      ordered = "Already on its way",
      ["pickup only"] = "Only sold in town",
      ["too big for storage"] = "More than your storage can ever hold",
      ["not enough money"] = "Not enough money",
      ["no room"] = "No room in storage for it",
    },
    priceCheat = "Free in cheat mode (debug)", -- the price line while Market cheat mode is on (D126)
    nowCheat = "Cheat mode: free, and it goes straight to your inventory", -- the "Right now" line of a grantable item in cheat mode
    cheatGet = "Get (free)", -- the card's buy button in cheat mode
    order = "Order $%d", -- the card's buy button for a delivery
    buy = "Buy $%d", -- the same in town
    owned = "Owned", -- the buy button of an item you already have (or that a better one covers), disabled
    close = "Close",
  },
  placement = { -- placement preview, confirmation and order card (D79, #197); %s / %d are filled in by src/ui/place_text.lua
    cardGap = 10, -- view px kept clear between the placement card and the target footprint (D86); the camera pans to keep it
    panSeconds = 0.25, -- real seconds the camera glides to bring the target clear of the card (eased; unaffected by sim speed or pause, D120)
    refitDelay = 0.6, -- real seconds after the player last dragged, scrolled or zoomed the map (and let go) before the card re-fits the view (D120)
    title = "Build %s here?",
    clears = "Clears first: %s",
    removes = "Removed just before it goes up: %s. Nothing is refunded. Cancelling keeps them.",
    cropsPart = "%d crop%s",
    ripePart = "%d ripe, its harvest is lost",
    plansPart = "%d planned tile%s",
    steps = "The homesteader clears the way, then the %s goes up.",
    upgradeTitle = "Replace the %s with the %s?", -- upgrade placed over the old building (D115): old name, new name, lower case
    upgradeLine = "The %s is removed when the %s goes up. Nothing is refunded. Cancelling keeps it.",
    upgradeTag = "replaces %s", -- label on the ghost of an upgrade over the old building
    full = "Warning: %s storage is full, so clearing waits for room.",
    confirm = "Go ahead",
    cancel = "Cancel",
    ordered = "Ordered: the homesteader clears the way first",
    orderTitle = "Waiting to build: %s",
    orderClearing = "Still to clear: %s",
    orderNothing = "Ready to go up",
    orderFull = "Held: %s storage is full",
    orderUnreachable = "Held: the homesteader can't reach it",
    orderBlocked = "Held: no room to step aside",
    orderClose = "Close",
    orderCancel = "Cancel order",
    cancelled = "Cancelled the %s order",
    done = "Built the %s",
    lostItem = "The %s order was dropped",
    noUntill = "Only tilled soil can be untilled",
    noWater = "Nothing to water there", -- the Pail tapped where no crop is thirsty (D138)
    noClear = "Nothing to clear there", -- the Axe tapped where nothing can be cleared (D138)
    noMove = "No building to move there", -- the Hammer's Move tapped off a building (D139)
    noPickUp = "No building to pick up there", -- the Hammer's Pick up tapped off a building
    noDemolish = "Nothing to demolish there", -- the Hammer's Demolish tapped off a building or crop
    hammerHint = "Move, pick up or demolish it with the Hammer", -- object card line (D139: the card only informs)
    pullCrop = "Pulling the %s. Nothing is refunded", -- toast when Untill is aimed at a planted crop (%s: crop name, lower case, #254)
    pulledCrop = "Pulled the %s", -- toast when the homesteader finishes pulling it (#254)
    destroyTitle = "Destroy the %s?", -- %s: object or crop name, lower case
    destroyNoRefund = "It is gone for good and nothing is refunded. Pick up instead to keep it.", -- objects
    destroyCrop = "The %s is lost: %s Nothing is refunded.", -- %s: crop name; %s: growth state
    destroyCropGrowing = "it is %d%% grown.", -- %d: percent
    destroyCropRipe = "it is ripe and its harvest is lost.",
    destroyBatch = "The %d %s in it are lost.", -- a station's running or waiting batch (%d count, %s output name)
    destroyCharge = "Its %.1f kWh of stored charge is lost.",
    destroyGoods = "Storage drops: %s no longer fit and are lost.", -- %s: "12 stone, 3 hens"
    destroyConfirmLabel = "Destroy",
    destroyedObject = "Destroyed the %s",
    destroyedCrop = "Destroyed the %s",
    destroyedLost = "Lost %s with it", -- toast part after destroying a store that held goods
    replaceTitle = "Replace with %s?", -- plan over a different crop (D110, #257); %s: new crop name
    replaceText = "%s are pulled and planted with %s. Nothing is refunded.", -- %s: "4 tiles of potato, 2 of carrot"; %s: new crop name
    replaceRipe = "%d of them are ripe and their harvest is lost.",
    replaceLabel = "Replace",
    replacedToast = "Replaced %d tiles with %s. Tilling and planting start now",
    moveTitle = "Move %s here?", -- move preview/confirmation card (D98, #15)
    moveOrderTitle = "Waiting to move: %s",
    moveSteps = "The homesteader clears the way, then the %s moves. It stays where it is until then.",
    moveStart = "Tap where the %s should go. It stays put until then",
    moveOrdered = "Ordered: the homesteader clears the way, then the %s moves",
    moved = "Moved the %s",
    pickedUp = "Picked up the %s: it waits in the crate (the Hammer)", -- D139
    pickConfirmTitle = "Pick up the %s?",
    pickConfirmCharge = "Its %.1f kWh of stored charge is lost.",
    pickConfirmOutput = "The %d %s waiting in it are thrown away.",
    pickConfirmLabel = "Pick up",
    pickReasons = { -- why a pick up or move is refused, by Placement.pickUpCheck reason
      fixed = "That can't be picked up",
      asleep = "The homesteader is sleeping there: wait for morning",
      batch = "Its batch is still running: wait for it to finish",
      storage = "It holds %s that would not fit without it: use some first",
      animals = "The %s live there and no other building has room for them",
    },
    reasons = { -- why a spot is refused, by Inventory.check reason (or rule)
      here = "It is already there",
      bounds = "Can't place it there",
      terrain = "Roads and water are off limits",
      object = "Something that can't be cleared is in the way",
      claimed = "Another order already covers that spot",
      none = "No more of those to place",
      waterTable = "Needs a high water table (blue tiles)",
      road = "Needs a free spot beside the road",
      water = "Needs to touch the creek",
      replace = "An upgrade goes over the building it replaces: place it on that one",
      replaceAsleep = "The homesteader is sleeping in the old building: wait for morning",
    },
  },
  book = { -- the Notebook and the Ledger, tabbed paper books (GDD §9.4, D140, D143; src/ui/books.lua, src/scenes/book.lua)
    width = { notebook = 720, ledger = 600 }, -- UI pixels: widest each book gets (the Journal map and the town lists need the room)
    margin = 8, -- UI pixels left clear round the book on every side
    tabHeight = 26, -- UI pixels: the tab strip (raised to input.minTouchTarget if that is larger)
    tabGap = 2, -- UI pixels between tabs
    tabPad = 6, -- UI pixels either side of a tab's icon and label
    iconSize = 12, -- UI pixels: the tab stamps' edge (the 12x12 icon grid of docs/ASSETS.md)
    iconGap = 3, -- UI pixels between a tab's icon and its label
    closeWidth = 52, -- UI pixels: the Close tab at the strip's right end
    bodyGap = 2, -- UI pixels between the tab strip and the page below it
    paper = { 0.20, 0.16, 0.12 }, -- the page's base colour (a dark kraft paper, so the pages' light ink keeps reading)
    tabIdle = { 0.14, 0.11, 0.08 }, -- an unselected tab's paper, a shade darker than the page
    fibreDensity = 0.07, -- 0..1 share of the art-pixel cells carrying a paper fibre fleck
    fibreLight = 0.05, -- 0..1 how much lighter a light fleck is than the page
    fibreDark = 0.06, -- 0..1 how much darker a dark fleck is than the page
    fibreLength = 3, -- art pixels a fleck runs (horizontal or vertical)
    stampShift = 1, -- UI pixels the ink stamp's second pass sits right and down (a printing misregistration)
    stampInk = { 0.95, 0.86, 0.62 }, -- the stamped icon's ink on a selected tab
    stampIdle = { 0.62, 0.55, 0.43 }, -- the stamped icon's ink on an unselected tab
    stampShade = { 0.06, 0.04, 0.03, 0.8 }, -- the misregistered second pass under the stamp
    tabs = { -- each book's pages in order: id, label, stamp icon
      notebook = {
        { id = "journal", label = "Journal", icon = "icon_tab_journal" },
        { id = "fish", label = "Fish guide", icon = "icon_tab_fish" },
        { id = "diary", label = "Diary", icon = "icon_tab_diary" },
      },
      ledger = {
        { id = "pantry", label = "Pantry", icon = "icon_tab_pantry" },
        { id = "routine", label = "Routine", icon = "icon_tab_routine" },
        { id = "catalog", label = "Catalog", icon = "icon_tab_catalog" },
        { id = "truck", label = "Truck & town", icon = "icon_tab_truck" },
      },
    },
    shortcuts = { -- a name a shortcut uses -> the book and page it opens (the old panel names and the world's taps)
      journal = { "notebook", "journal" },
      fish = { "notebook", "fish" },
      diary = { "notebook", "diary" },
      log = { "notebook", "diary" },
      pantry = { "ledger", "pantry" },
      routine = { "ledger", "routine" },
      catalog = { "ledger", "catalog" },
      buildings = { "ledger", "catalog" },
      truck = { "ledger", "truck" },
    },
  },
  log = { -- message log (D90, #167)
    maxLines = 40, -- lines kept, newest first; older ones drop off the end (a night of news is about a dozen)
    coalesceSeconds = 60, -- game seconds within which the pieces of one multi-part event (storage full for several goods) merge into one line
    panelWidth = 400, -- virtual pixels wide the log panel (shrinks to fit a narrow view)
  },
  journal = { -- Field Journal navigation (D81, #194); all virtual pixels unless noted
    defaultArea = "Other", -- area heading for a chapter whose content has no `area`
    pad = 4, -- space inside the map rect and between the map rect and the node card
    gap = 4, -- space between chips and between tiles
    chipHeight = 28, -- chip height (raised to input.minTouchTarget if that is larger)
    chipMinWidth = 58, -- narrowest chip; chips wrap into rows when they do not fit one
    tileMinWidth = 104, -- narrowest chapter tile; the grid fits as many columns as that allows
    tileHeight = 62, -- chapter tile height: name, known count, ideas and locked, to-study
    tilePad = 5, -- text inset inside a tile
    headingHeight = 20, -- area heading strip height
    groupGap = 6, -- space under an area's last row of tiles
    radius = 3, -- corner radius of chips and tiles
    wheelStep = 24, -- pixels the overview scrolls per mouse-wheel notch
    thumbWidth = 3, -- scroll thumb width
    thumbMin = 14, -- shortest scroll thumb
    thumbAlpha = 0.3, -- scroll thumb opacity (0..1)
    fitMaxScale = 2, -- largest zoom of a fitted chapter (art pixels are drawn at most this big)
    fitMaxColumns = 5, -- most side-by-side columns a chapter is split into to fit a short, wide view
    fitTolerance = 0.02, -- zoom a split must beat the previous one by to be preferred (ties keep fewer columns)
    scrollNodes = 24, -- nodes: a chapter with more than this scrolls at readScale instead of shrinking to fit (D120, #208)
    readScale = 1, -- zoom: a scrolling chapter is drawn at this size (art pixels 1:1), so it stays readable however many nodes it has
    search = { -- the Journal's search by node name (D120, #208); sizes are virtual pixels
      height = 28, -- search field height (raised to input.minTouchTarget if that is larger)
      maxLength = 24, -- characters a query may hold
      rowHeight = 30, -- result row height (raised to input.minTouchTarget if that is larger)
      clearWidth = 36, -- clear button width (raised to input.minTouchTarget if that is larger)
      textPad = 6, -- text inset inside the field and in a result row
      caretBlink = 1, -- seconds for one on/off cycle of the typing caret
      statusWidth = 70, -- width reserved at a result row's right for its status word
      labels = {
        placeholder = "Search what you know", -- shown in the empty field; only known names are searched
        clear = "Clear", -- the clear button; tapping it empties the field and shows the chapters again
        none = "Nothing found among the things you know.", -- shown for a query with no match; the same words whether or not locked nodes would match
        status = { known = "Known", idea = "Idea", queued = "Queued", studying = "Studying" },
      },
    },
    sideCardWidth = 230, -- node card width when it sits beside the chapter
    sideCardMinViewWidth = 500, -- the card moves beside the chapter on views wider than this ...
    sideCardMaxViewHeight = 300, -- ... and shorter than this
    colors = {
      tile = { 0.14, 0.17, 0.15, 1 }, -- chapter tile fill
      chipOn = { 0.22, 0.29, 0.20, 1 }, -- the active filter chip's fill
      dim = { 0.09, 0.11, 0.10, 0.75 }, -- veil over nodes the filter hides
    },
    labels = {
      back = "< Chapters", -- focus view: back to the overview
      queue = "Queue", -- jump to the head of the study queue
      search = "Search", -- chip that opens the search field (D120)
      study = "To study (%d)", -- jump to the next idea; %d is how many ideas are waiting
      filters = { all = "All", known = "Known", ideas = "Ideas", locked = "Locked" },
      known = "%d/%d known", -- tile line: known of total
      ideas = "Ideas: %d", -- tile line part: ideas (including queued and studying)
      locked = "Locked: %d", -- tile line part: still ???
      separator = ", ",
      toStudy = "%d to study", -- tile line: ideas nobody has queued
      empty = "No chapters match.", -- overview with a filter that hides everything
      continued = " ...", -- suffix on the continuation columns of a split chapter
    },
  },
  version = { -- the build label (tag and commit hash, D91) on the title screen and the out-of-date save prompt
    size = "small", -- theme text size key for the title screen label
    color = "textDim", -- theme colour key: quiet, it is for playtesters and bug reports
    margin = 6, -- virtual pixels between the label and the left/bottom screen edges
    promptPrefix = "This build: ", -- line added under the out-of-date save message
  },
  topChips = { -- what the top-bar chips show besides their number (D112, #267): a state bar, a level mark and a trend arrow
    barHeight = 2, -- virtual pixels: the fill bar under a chip's icon and number
    barGap = 1, -- virtual pixels between the icon and the bar under it
    barTrack = { 0, 0, 0, 0.45 }, -- rgba: the empty part of a chip's bar
    barOk = { 0.86, 0.80, 0.66, 1 }, -- rgba: a bar whose vital is fine, a quiet cream (amber and red use the theme accent and danger colours; no UI green, D142)
    marks = { [0] = "", "!", "!!" }, -- text after the number by alert level (0 fine, 1 amber, 2 red): the state is never colour alone
    markGap = 2, -- virtual pixels between a chip's number and its level mark or trend arrow
    trendSize = 5, -- virtual pixels: width and height of the trend triangle after a number
    trendMinKw = 0.05, -- kW: a battery charging or draining slower than this shows no trend arrow (flat)
    foodFullDays = 7, -- days of food that fill the food bar (a week in the larder reads as full)
    woodFullNights = 10, -- nights of wood that fill the wood bar once a fire is needed (before that the bar is the share of the store)
    waterAmber = 0.25, -- cistern fill (0..1) under which the water chip turns amber
    waterRed = 0.10, -- cistern fill (0..1) under which the water chip turns red
    stormThreat = 2, -- weather kinds whose threat multiplier (tuning.weather.kinds) is at least this show the weather chip amber (storms)
    weatherDays = 3, -- days of weather the weather chip shows as icons, today first (capped by what the forecast reveals)
    iconGap = 1, -- virtual pixels between the weather chip's day icons
  },
  holdRepeat = { -- hold-to-repeat on the Pantry keep and truck load steppers (D119, #201); real (UI clock) seconds, so it ignores sim speed and pause
    delay = 0.45, -- seconds a press is held before the first repeat (a quick tap is still exactly one step)
    rate = 10, -- repeats per second once repeating
    stageTicks = 6, -- repeats at each step size before the step grows to the next one in stageUnits
    stageUnits = { 1, 5, 10 }, -- units moved per repeat, stage by stage; the last stage holds until release
  },
  modal = { -- the short chip modals (D112, #267)
    width = 260, -- virtual pixels: widest a chip modal gets (narrower on small views)
    rowGap = 2, -- virtual pixels between rows
    todayLabel = "Today", -- weather modal: the first day
    tomorrowLabel = "Tomorrow", -- weather modal: the second day
    inDaysLabel = "In %d days", -- weather modal: later days
  },
  controls = { -- Settings > Controls screen (D121)
    bandHeight = 54, -- virtual pixels: the message strip under the title (hint, "Press a key...", conflict question)
    rowGap = 6, -- virtual pixels between binding rows
    keyWidth = 76, -- virtual pixels: the key button of a row (shows the current key, or "Press a key...")
    resetWidth = 48, -- virtual pixels: the per-row Reset button
    buttonGap = 4, -- virtual pixels between a row's buttons
  },
  hud = { -- the resting HUD (src/ui/hud.lua, GDD §9.4, D137); UI pixels unless noted
    pad = 4, -- margin between the plates and the view's edges
    gap = 4, -- space between neighbouring plates
    textPad = 6, -- space between a plate's edge and its words
    clockH = 26, -- the clock plate: two lines (date, then time and the forecast glyphs)
    speedSegment = 24, -- width of each speed button on the speed plate (at least the touch size)
    vitalH = 24, -- height of a vitals plate (icon, value and the thin gauge under them)
    vitalGap = 9, -- space between two vitals on a plate
    vitalPad = 6, -- space between a vitals plate's edge and its first and last vital
    stampSize = 24, -- a decision stamp's height, and its width when only the icon shows
    badgeH = 30, -- the homesteader, tool and book plates
    iconPad = 9, -- space round an icon on an icon-only plate
    countdownSteps = 76, -- pixels round the homesteader portrait for the idle countdown ring (about 2 pi x the radius, so it reads as a line)
    countdownRadius = 12, -- UI pixels from the portrait's centre to the ring
    jobs = { -- the badge's second line for the job in hand, by task category (anything else reads "Working")
      harvest = "Harvesting",
      water = "Watering",
      animals = "With the animals",
      plant = "Planting",
      process = "Preserving",
      clear = "Clearing",
      trees = "Felling",
      fish = "Fishing",
    },
    states = { -- the badge's first line
      routine = "Routine",
      handsOn = "Hands-on",
      asleep = "Asleep",
      resting = "Resting",
      paused = "Paused",
    },
    idleLine = "Nothing to do", -- the routine is on with no work (it opens the routine list)
    countdownLine = "Routine in %ds", -- hands-on: when the routine takes over; %d is seconds
    walking = "Walking", -- on the way to a job
  },
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
  plate = { -- frosted HUD and panel plates lit like the world (shaders/ui_plate.glsl, src/ui/plate.lua; GDD §9.4, D142)
    see = 0.36, -- 0..1 how much of the blurred world shows through a panel plate (higher = more glass, less contrast for text)
    panelSee = 0.2, -- 0..1 the same for modal panels (Draw.panel), whose text sits over a wide area of world
    buttonSee = 0.16, -- 0..1 the same for buttons, which stay more solid so their label reads at a glance
    blurDivisor = 6, -- the world is copied at 1/this of the screen size before blurring (bigger = softer and cheaper)
    blurPasses = 2, -- horizontal plus vertical blur passes over that copy
    gradeShare = 0.45, -- 0..1 share of the world's time-of-day and season tint the plates take (text and icons take none)
    nightDim = 0.35, -- 0..1 how much darker a plate's own colour gets at full night (on top of the grade share)
    alpha = 0.92, -- 0..1 opacity of a plate's body
    litAmount = 0.16, -- 0..1 strength of the warm lit edge on the top and left (the world's sun side)
    shadeAmount = 0.35, -- 0..1 strength of the cool shade edge on the bottom and right
    cornerCut = 2, -- UI pixels cut from each corner in steps (0 = square corners)
    frostReach = 7, -- UI pixels frost creeps in from each corner at full frost (winter, D142)
    snowMinSize = 24, -- UI pixels: plates narrower or shorter than this get no snow along their top, so it never covers their icon
  },
  startRoutineHint = "Starts the routine now. It waters, plants, harvests and chops for you; any tap ends it.", -- toast when the routine starts
}
