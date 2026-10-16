-- The Notebook and the Ledger (GDD §9.4, D140, D143): one tabbed paper book scene for both. Each tab hosts
-- one of the former panels (Journal, Fish guide, Diary; Pantry, Routine, Catalog, Truck & town) unchanged:
-- a page is the panel scene itself, laid out in the book's page body and drawn over its paper. The book owns
-- the tab strip and the one Close tab, remembers the page it was left on (src/ui/books.lua), and hands every
-- input and update to the page showing. The page talks to the book through a stand-in `app` whose view
-- carries the page body (Panel.box returns it) and whose pop closes the book.

local Books = require("src.ui.books")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Motion = require("src.ui.motion")
local Paper = require("src.ui.paper")
local Plate = require("src.ui.plate")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Book = { name = "book", dissolve = "book" } -- it dissolves in and out (D142)
Book.__index = Book

--- Make the page scene for tab `id`. Each is the former panel's scene, built as it was.
local function makePage(self, id)
  local world, toast = self.world, self.onToast
  if id == "journal" then
    return require("src.scenes.journal").new(world, toast)
  elseif id == "fish" then
    return require("src.scenes.guide").new(world)
  elseif id == "diary" then
    return require("src.scenes.message_log").new(self.log)
  elseif id == "pantry" then
    return require("src.scenes.pantry").new(world)
  elseif id == "routine" then
    return require("src.scenes.routine").new(world)
  elseif id == "catalog" then
    return require("src.scenes.catalog").new(world, toast, self.catalogOpts)
  elseif id == "truck" then
    return require("src.scenes.truck").new(world, toast)
  end
  error("no page " .. tostring(id))
end

--- spec: { book = "notebook"|"ledger", page = tab id or nil (the remembered one), onToast = fn(text),
--- log = the message log (the Diary reads it), catalogOpts = { buildings = bool } }.
function Book.new(world, spec)
  return setmetatable({
    world = world,
    book = spec.book,
    request = spec.page,
    onToast = spec.onToast or function() end,
    log = spec.log,
    catalogOpts = spec.catalogOpts,
    pages = {},
  }, Book)
end

--- Open a book on the page a shortcut name names ("pantry", "truck", "journal"...; tuning.ui.book.shortcuts), or
--- on the book's remembered page when `name` is a book id ("notebook", "ledger"). The homestead on the stack
--- lends its toaster and its message log.
function Book.open(app, name, opts)
  local cfg = app.ctx.tuning.ui.book
  local book, page
  if rawget(cfg.tabs, name) then
    book = name
  else
    book, page = Books.shortcut(cfg, name)
  end
  local home
  for _, scene in ipairs(app.stack) do
    if scene.toaster and scene.log then
      home = scene
    end
  end
  app:push(Book.new(app.ctx.session.world, {
    book = book,
    page = page,
    onToast = home and home:toaster() or nil,
    log = home and home.log or nil,
    catalogOpts = opts,
  }))
end

function Book:enter()
  local ctx = self.app.ctx
  self.cfg = ctx.tuning.ui.book
  self.minTouch = ctx.tuning.input.minTouchTarget
  self.buttons = Buttons.new(self.minTouch)
  local book = self
  -- What a page sees as its `app`: the real one, but its view holds the page body and its pop closes the book.
  self.host = setmetatable({
    view = self.app.view,
    pop = function()
      book.app:pop()
    end,
    push = function(_, scene, ...)
      return book.app:push(scene, ...)
    end,
  }, { __index = self.app })
  self:show(Books.page(self.cfg, self.book, self:locked() and "truck" or self.request))
end

function Book:exit()
  Books.remember(self.cfg, self.book, self.current)
  local page = self.pages[self.current]
  if page and page.exit then
    page:exit()
  end
end

--- In town the truck's page is the only way home, so the other pages and Close wait (the town menu is modal).
function Book:locked()
  return self.world.state.market.inTown == true
end

--- Show page `id`, making its scene the first time.
function Book:show(id)
  local previous = self.pages[self.current]
  if previous and self.current ~= id and previous.exit then
    previous:exit()
  end
  self.current = id
  Books.remember(self.cfg, self.book, id)
  local page = self.pages[id]
  if not page then
    page = makePage(self, id)
    page.app = self.host
    if page.enter then
      page:enter()
    end
    self.pages[id] = page
  end
  self.page = page
  if self.rects then -- not yet on the first show: the app lays the book out right after enter
    page:resize(self.host.view)
    self:layoutTabs()
  end
end

function Book:resize(view)
  local rects = Books.rects(self.cfg, view, self.book, self.minTouch)
  self.rects = rects
  self.host.view = Books.hostView(view, rects.body)
  self.page:resize(self.host.view)
  self:layoutTabs()
end

--- The tab strip's buttons: one per page, then Close (not while locked in town).
function Book:layoutTabs()
  local cfg, locked = self.cfg, self:locked()
  self.buttons:clear()
  self.lockedShown = locked
  local pages = Books.pages(cfg, self.book)
  local lay = Books.layoutTabs(cfg, pages, self.current, self.rects.strip, self.minTouch, function(label)
    return Text.measure(label, "body")
  end, cfg.iconSize)
  for n, tab in ipairs(lay.tabs) do
    local def = pages[n]
    self.buttons:add({
      x = tab.x,
      y = tab.y,
      w = tab.w,
      h = tab.h,
      id = def.id,
      label = def.label,
      enabled = not locked or def.id == "truck",
      selected = def.id == self.current,
      showLabel = tab.label,
      icon = def.icon,
      onPress = function()
        if def.id ~= self.current then
          self:show(def.id)
        end
      end,
      draw = function(b)
        self:drawTab(b)
      end,
    })
  end
  if not locked then
    self.buttons:add({
      x = lay.close.x,
      y = lay.close.y,
      w = lay.close.w,
      h = lay.close.h,
      label = "Close",
      onPress = function()
        self.app:pop()
      end,
    })
  end
end

--- A tab: paper like the page when it is the open one, a darker slip when not; its ink stamp, and the label
--- when there is room (or for the open page).
function Book:drawTab(b)
  local cfg, colors = self.cfg, theme.colors
  local open = b.selected
  local pressed = self.buttons.pressed == b
  Plate.draw(b.x, b.y, b.w, b.h, {
    base = open and cfg.paper or cfg.tabIdle,
    kind = "button",
    see = 0,
    alpha = 1,
    ink = open and colors.accent or nil,
    lit = (pressed and 0) or (open and 0.3) or nil,
    weather = false,
  })
  local alpha = b.enabled and 1 or 0.4
  local ink = open and cfg.stampInk or cfg.stampIdle
  local iconW = cfg.iconSize
  local tw, th = Text.measure(b.label, "body")
  local total = iconW + (b.showLabel and (cfg.iconGap + tw) or 0)
  local ix = math.floor(b.x + (b.w - total) / 2)
  Paper.stamp(cfg, b.icon, ix, math.floor(b.y + (b.h - cfg.iconSize) / 2), ink, alpha)
  if b.showLabel then
    Text.draw(b.label, ix + iconW + cfg.iconGap, b.y + (b.h - th) / 2, {
      size = "body",
      color = open and colors.text or colors.textDim,
    })
  end
end

--- The page's modal item card (Catalog, Truck) covers the book, so the tabs wait for it.
function Book:modal()
  local card = self.page.card
  return card and card.isOpen and card:isOpen()
end

function Book:update(dt)
  if self:locked() ~= self.lockedShown then
    if self:locked() and self.current ~= "truck" then
      self:show("truck")
    end
    self:layoutTabs()
  end
  if self.page.update then
    self.page:update(dt)
  end
end

function Book:action(name, data)
  if not self:modal() and self.buttons:action(name, data) then
    return true
  end
  self.page:action(name, data)
  return true -- a book is modal
end

function Book:textinput(text)
  if self.page.textinput then
    self.page:textinput(text)
  end
end

function Book:keypressed(key)
  if self.page.keypressed then
    self.page:keypressed(key)
  end
end

function Book:draw()
  local paper, strip = self.rects.paper, self.rects.strip
  Draw.overlay(self.app.view)
  Paper.drawPool(self.cfg, paper.x, paper.y, paper.w, paper.h, Motion.night()) -- lamp light round the page at night
  Paper.draw(self.cfg, paper.x, paper.y, paper.w, paper.h)
  Paper.drawLamp(self.cfg, paper.x, paper.y, paper.w, paper.h, Motion.night())
  love.graphics.setColor(theme.colors.panelBorder)
  love.graphics.rectangle("fill", paper.x + 2, strip.y + strip.h, paper.w - 4, 1)
  self.buttons:draw()
  self.page:draw()
end

return Book
