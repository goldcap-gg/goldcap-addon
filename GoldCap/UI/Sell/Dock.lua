-- The dock along the bottom of the Sell tab, and every click that posts or cancels. POST and the
-- item it posts (UI/Sell/PostPanel.lua paints the rest of that tier), CANCEL n and its line, the
-- totals and the status line; and the click handlers. onPostClick and onRepostClick are the only places the tab makes a protected
-- auction-house call, one per click, before anything else the click does (docs/addon/AGENTS.md
-- "Protected actions"). A row's buttons, the inspector's Cancel lot, the dock and the key binding
-- all reach them through UI.Dock. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local Post = GC.SellPost
local UI = GC.SellUI
local Dock = UI.Dock
local ROW, DOCK = UI.ROW, UI.DOCK
local setColor, formatCell = UI.fmt.setColor, UI.fmt.cell
local effectivePostUnit, postQuantity = GC.SellUtil.effectivePostUnit, GC.SellUtil.postQuantity

-- Forward-declared for the same reason renderRows was (in UI/SellFrame.lua, before the split):
-- setStatus (below) needs to call this on every state change, and the row handlers need it
-- on every data change -- see this function's real body, below,
-- for why it cannot be defined this early itself. renderRows DEFERS for the
-- whole time a post is armed (Post.DisarmPost/Post.DisarmRepost's own flushDeferredRender in
-- Services/Sell/Post.lua), so a render is
-- not a reliable place to keep the queue control's own label in sync with the confirm/posting
-- dance -- this is driven the same way paintRefreshButton already is, from setStatus.
local function paintQueueButton() end
-- Forward-declared for the same reason paintQueueButton is: setStatus, ROW.armLot and the row
-- handlers call it before its real body, and Services/Sell/Post.lua reaches it as
-- GC.SellView.paintCancel to keep the cancel control's label in sync with the arm/confirm dance,
-- because renderRows defers for the whole time a repost is armed.
local function paintCancelButton() end

local function setStatus(text)
  if UI.window and UI.window.status then UI.window.status:SetText(text) end
  GC.Sell._lastStatus = text
  -- Said, and not yet said beside a button: a refused press reads this (onPostClick).
  Dock.unanswered = text
  -- And in the dock, under the bulk action: the toolbar line above is a window's width from
  -- every control on this tab, which is why REFRESH, POST and each row button had to grow a
  -- copy of the state. Said here, it is said beside the button that was just pressed -- unless
  -- the player's own post has something to say there (GC.Sell._NotePost below), in its colour.
  GC.Sell._PaintDock(text)
  UI.Toolbar.PaintRefreshButton()
  paintQueueButton()
  -- The cancel control is driven from here for the same reason the queue control is: renderRows
  -- DEFERS for the whole time a repost is armed, so a render cannot be relied on to keep it in
  -- step with the arm/confirm dance. It was missing, and the one transition that mattered most
  -- went unpainted -- the footer still read "CANCEL LOT?", still enabled, while the cancel it
  -- named was already on the wire.
  paintCancelButton()
end
Dock.SetStatus = setStatus

-- The dock's line belongs to the player's own post while it has something to say about it.
-- The owner pressed Post and could not tell whether anything was happening: the pricing walk
-- writes this line every few seconds and wrote over "Posting…" within the second, the refresh
-- after a refusal replaced "Posting failed" before it was ever drawn, and a post that went up
-- said nothing at all. So a note holds the dock -- a post on its way until the post ends
-- (Post.DisarmPost lets it go), an outcome for its few seconds -- whatever the walk says meanwhile.
-- The toolbar line keeps the walk's words; when the note ends the dock goes back to them.
-- `tone` is a Theme.color key. Fields rather than locals: written when this code lived in
-- UI/SellFrame.lua, whose chunk was at Lua 5.1's limit.

-- The dock's line: the post's note while there is one, else `text`, the tab's ordinary line.
function GC.Sell._PaintDock(text)
  local dock = UI.container and UI.container.dockStatus
  if not dock then return end
  local note = GC.Sell._postNote
  dock:SetText(note and note.text or text or "")
  local c = Theme and Theme.color and Theme.color[note and note.tone or "fgMuted"]
  if c then dock:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

function GC.Sell._NotePost(text, tone, seconds)
  local note = { text = text, tone = tone or "fg", timed = seconds ~= nil }
  GC.Sell._postNote = note
  if UI.container and UI.container.IsShown and UI.container:IsShown() then
    local ordinary = GC.Sell._lastStatus
    setStatus(text)
    -- The toolbar says it too, but it is not the tab's ordinary line: the dock returns to that.
    GC.Sell._lastStatus = ordinary
    Dock.unanswered = nil -- said beside the button already: it is the note
  else
    -- The toolbar line is the whole window's, and another tab has it now: a late answer a minute
    -- on wrote "Posted" over Deals' own line (review M1). Only the dock, which is ours.
    GC.Sell._PaintDock(GC.Sell._lastStatus)
    paintQueueButton()
  end
  if seconds and C_Timer and C_Timer.After then
    C_Timer.After(seconds, function()
      if GC.Sell._postNote == note then GC.Sell._EndPostNote() end
    end)
  end
end

-- `heldOnly`: end a note that lasts as long as its post, never an outcome still on its clock.
function GC.Sell._EndPostNote(heldOnly)
  local note = GC.Sell._postNote
  if not note or (heldOnly and note.timed) then return end
  GC.Sell._postNote = nil
  -- An outcome that runs out while another post of ours is still out (a late answer said
  -- Posted over it) gives the dock back to that post, not to the walk.
  local stage = not heldOnly and S.postingRow and S.postingRow.postStage
  local again = (stage == "posting" or stage == "confirming")
    and (S.postingPin and S.postingPin.queued and GC.L["Waiting for the Auction House…"] or GC.L["Posting…"])
    or stage == "confirm" and GC.L["Click Confirm to post"] or nil
  -- The toolbar line is the whole window's. With another tab on screen it is that tab's, and a
  -- clock running out here wrote over it -- a Deals line erased ten seconds after a refusal
  -- (review M1). Off the tab, only the dock, which is ours, is repainted.
  if not (UI.container and UI.container.IsShown and UI.container:IsShown()) then
    if again then GC.Sell._postNote = { text = again, tone = "fg", timed = false } end
    GC.Sell._PaintDock(GC.Sell._lastStatus)
    paintQueueButton()
    return
  end
  if again then
    GC.Sell._NotePost(again)
    return
  end
  setStatus(GC.Sell._lastStatus or "")
end

-- What a refused press of POST, of a row's Post or of the price box is told, said beside the
-- button for ANSWER_SECONDS the way a post's own note is: on the posting deck the dock is one row
-- with no line for the walk's words, only news under the item's name (owner, 2026-10-10). The
-- status line says it too, as it always did. Not over a post still out: the dock keeps saying
-- what that post is doing, and the answer is the status line's alone (review M3).
local ANSWER_SECONDS = 6
function Dock.Answer(text)
  local note = GC.Sell._postNote
  if note and not note.timed then setStatus(text) return end
  GC.Sell._NotePost(text, "fg", ANSWER_SECONDS)
end

-- Skip reasons in words a seller would actually read, never GC.PostQueue's own internal token
-- -- see that module's own `evaluate` comment for what each one means structurally. A silently
-- short queue is the same lie as a silently short deals list; naming the reason in plain words
-- is what keeps it from being a DIFFERENT lie instead.
-- @localised-keys: literals in this table ARE GC.L keys, looked up where the table is
-- READ, not here. This is file scope, and GC.L only resolves once ApplyLocale has run
-- at ADDON_LOADED -- a lookup here captures the English fallback and keeps it in every
-- language. The table has to close with a `}` on its own line: that is where the
-- contract spec's scanner stops.
local QUEUE_SKIP_TEXT = {
  no_fresh_price = "needs a fresh price -- press Refresh",
  below_breakeven = "would sell at a loss",
  unresolved_identity = "GoldCap can't pin down which bag stack this is",
  -- WoW: Forever only (Core/PostQueue.lua's below_vendor): a vendor pays at least as much for
  -- it after the AH's cut.
  below_vendor = "a vendor pays more -- sell it there",
  -- The cancel queue's own reasons (GC.CancelQueue.Build): a cancel burns a deposit, so a
  -- held-back listing needs its why stated even more than a held-back post does.
  advised_hold = "relisting now would lock in a loss or a stall -- hold",
  -- Held by this tab, not by the queue module: the item's last post may still go up
  -- (GC.Sell._lateAnswers).
  awaiting_answer = "Last post may still go up -- wait a minute",
  no_advice = "cost basis incomplete -- set costs to get repost advice",
}

-- Why the queue held a position back, in the words above; nil when it did not.
function Dock.HeldBackText(positionKey)
  for _, skip in ipairs(S.queueSkipped or {}) do
    if skip.positionKey == positionKey then
      return QUEUE_SKIP_TEXT[skip.reason] and GC.L[QUEUE_SKIP_TEXT[skip.reason]] or nil
    end
  end
end

-- The real body, promised by the forward declaration above. Reads UI.container and
-- GC.SellState's queue fields.
paintQueueButton = function()
  local button = UI.container and UI.container.queueButton
  if not button then return end
  -- POST belongs to the posting deck and shares the dock with the cancel queue's controls.
  -- Hidden, not disabled, on the other deck: a disabled control invites a click that can never
  -- work, and this one belongs to a screen the player is not on.
  if S.filterMode == "listed" or S.filterMode == "cancelqueue" then
    button:Hide()
    UI.PostPanel.Hide()
    Dock.LayoutLedger()
    return
  end
  button:Show()
  -- The dock's item: what a press of POST posts, painted from the same answer the press reads.
  local row, nextRow = Dock.Current()
  -- The spinner turns for as long as a post of ours is on the wire: POST is disabled meanwhile,
  -- and disabled alone reads as dead.
  local sending = S.postingRow ~= nil and (S.postingRow.postStage == "posting" or S.postingRow.postStage == "confirming")
  if button.SetBusy then button:SetBusy(sending) end
  local hint
  if S.postingRow then
    -- CONFIRM only while the post waiting for it is the dock's item's: a press must never land
    -- on another item than the one the dock names.
    local same = row and S.postingRow.position and S.postingRow.position.positionKey == row.position.positionKey
    if same and S.postingRow.postStage == "confirm" then
      button:SetLabel(GC.L["CONFIRM"]); button:Enable()
    else
      button:SetLabel(GC.L["POSTING…"]); button:Disable()
    end
  elseif not row then
    button:SetLabel(GC.L["POST"])
    button:Disable()
    -- Items in the bags, none of them on the selling list: say how to put one on it. Not once
    -- the walk has been down a list there was, nor while an item waits for its last post.
    local unmarkedOnly = #S.queueSkipped == 0 and #(S.queueDone or {}) == 0 and #(S.notSelling or {}) > 0
    hint = unmarkedOnly and GC.L["Mark what to sell with the circle"] or GC.L["Nothing queued to post"]
  else
    button:SetLabel(GC.L["POST"])
    button:Enable()
  end
  UI.PostPanel.Paint(row, nextRow, hint)
  Dock.LayoutLedger()
end
Dock.PaintQueueButton = paintQueueButton

-- The cancel control's mirror of paintQueueButton, over the repost arm instead of the post
-- pin. States, in the order a click sequence produces them: "CANCEL N" -> "CANCEL LOT?" (the
-- head lot is armed; enabled only once the REPOST_ARM_SECONDS delay has passed, exactly like
-- the row's own button) -> "CANCELLING…". While some OTHER lot's repost is in flight the
-- control keeps its count but disables -- it must never offer a click that would land on the
-- wrong lot, the same rule paintQueueButton applies to a non-head post.
paintCancelButton = function()
  -- The cancel queue's half of the same footer slot -- see paintQueueButton's own comment.
  if UI.container and UI.container.cancelButton
      and S.filterMode ~= "listed" and S.filterMode ~= "cancelqueue" then
    UI.container.cancelButton:Hide()
    if UI.container.cancelHeldBack then UI.container.cancelHeldBack:Hide() end
    if UI.container.cancelHeldBackHit then UI.container.cancelHeldBackHit:Hide() end
    return
  end
  if UI.container and UI.container.cancelButton then UI.container.cancelButton:Show() end
  local button = UI.container and UI.container.cancelButton
  if not button then return end
  local heldBack, heldBackHit = UI.container.cancelHeldBack, UI.container.cancelHeldBackHit
  local head = S.cancelEntries[1]
  -- SetVariant runs BEFORE Enable/Disable in every branch: Theme.Button's OnDisable dims the
  -- text to fgDim, and SetVariant restores full-brightness text -- calling SetVariant after
  -- Disable() silently wiped the dimmed look this button needs while it has nothing to do.
  if S.repostingRow then
    local sameHead = head and S.repostPin and S.repostPin.auctionID == head.auctionID
    button:SetVariant("danger")
    if sameHead and S.repostingRow.repostStage == "cancelling" then
      button:SetLabel(GC.L["CANCELLING…"]); button:Disable()
    elseif sameHead and S.repostingRow.repostStage == "armed" then
      button:SetLabel(GC.L["CANCEL LOT?"])
      if S.repostingRow.repostReady then button:Enable() else button:Disable() end
    else
      button:SetLabel((GC.L["CANCEL %d"]):format(#S.cancelEntries)); button:Disable()
    end
  elseif not head then
    button:SetVariant("ghost")
    -- Empty only because every lot is waiting on a live price: that is not "nothing to cancel",
    -- and beside My Lots' own list it read as a contradiction (WoW: Forever, 2026-09-26).
    local waiting = #S.cancelSkipped > 0
    for _, skip in ipairs(S.cancelSkipped) do
      if skip.reason ~= "no_fresh_price" then waiting = false; break end
    end
    button:SetLabel(waiting and GC.L["NO LIVE PRICE YET"] or GC.L["NOTHING TO CANCEL"])
    button:Disable()
  else
    button:SetVariant("danger")
    button:SetLabel((GC.L["CANCEL %d"]):format(#S.cancelEntries))
    button:Enable()
  end
  if heldBack then
    -- The line beside the control names what the next click is about -- "Mycobloom ×80 @
    -- 8g10s" -- the way the posting deck's does, ahead of the held-back count. One line rather
    -- than the posting deck's two: this deck's lower line is the status.
    local parts = {}
    if head then
      parts[1] = GC.Sell._InlineColor(Theme.color.fg, ("%s ×%d @ %s"):format(
        head.itemName or GC.L["Item"], head.quantity or 0, formatCell(head.listedUnit)))
    end
    if #S.cancelSkipped > 0 then parts[#parts + 1] = (GC.L["%d held back"]):format(#S.cancelSkipped) end
    heldBack:SetText(table.concat(parts, "  ·  "))
    if GC.Sell.PaintCancelMirror then GC.Sell.PaintCancelMirror() end
    if #parts > 0 then heldBack:Show() else heldBack:Hide() end
    -- The hover explains the held-back lots, so it is only there when there are any.
    if heldBackHit then
      if #S.cancelSkipped > 0 then heldBackHit:Show() else heldBackHit:Hide() end
    end
  end
  Dock.LayoutLedger()
end
Dock.PaintCancelButton = paintCancelButton

-- The Post click: the row's button, the inspector's, the dock's POST and the key binding all end
-- here. Post.PreparePost decides; this makes the protected call, the first thing the click does
-- with the client, and only then gives the button its busy look and the dock its note.
local function onPostClick(row)
  -- A plain field write, the only thing ahead of Post.PreparePost: whatever it says from here on
  -- is this press's answer.
  Dock.unanswered = nil
  local step = Post.PreparePost(row)
  if not step then
    -- Refused, so no protected call follows: what it said goes beside the button (Dock.Answer).
    if Dock.unanswered then Dock.Answer(Dock.unanswered) end
    return
  end
  local pin = step.pin
  if step.confirm then
    if pin.isCommodity then
      C_AuctionHouse.ConfirmPostCommodity(pin.location, pin.duration, pin.quantity, pin.unitPrice)
    else
      C_AuctionHouse.ConfirmPostItem(pin.location, pin.duration, pin.quantity, nil, pin.buyout)
    end
    -- Sent once the call returns, as on the first click: an error the client raises inside the
    -- call is this post's own refusal (OnAuctionHouseError reads an unsent post's error as its
    -- own), not an older late post's answer -- which left this one "confirming", then held it a
    -- minute for a post refused on the spot (review NM-B). The same guard now also protects the
    -- "Posting…" note below: an error raised inside the call already ran OnAuctionHouseError's
    -- own Post.DisarmPost + _NotePost with the real refusal, which postingPin == pin (now false)
    -- catches -- overwriting that message with "Posting…" would hide the refusal from the player.
    if S.postingPin == pin then
      -- The busy look, now that the protected call is behind it: disabled, saying so, the
      -- spinner turning. Moved here with the note below (final review C3): both run Blizzard or
      -- GoldCap Lua that WoW: Forever's taint engine blocks ahead of a protected call.
      row.action:Disable(); row.action:SetLabel(GC.L["Posting…"])
      if row.action.SetBusy then row.action:SetBusy(true) end
      -- Moved here, after the call: WoW: Forever's taint engine blocks a protected AH call once
      -- the same hardware click has read certain GoldCap runtime state, and _NotePost ->
      -- setStatus (this file, above) -> paintRefreshButton (UI/Sell/Toolbar.lua) ->
      -- refresh.deckProgress() is one of the reads it flags. Said the instant the call returns
      -- rather than the instant it was about to be made -- the player sees the same "Posting…" note
      -- either way, just a beat later in the same tick, unless the call queued the confirm itself
      -- (OnThrottleQueued, same guard the first click's own note now reads).
      GC.Sell._NotePost(pin.queued and GC.L["Waiting for the Auction House…"] or GC.L["Posting…"])
      Post.Sent(pin)
    end
    return
  end
  local needsConfirmation
  if pin.isCommodity then
    needsConfirmation = C_AuctionHouse.PostCommodity(pin.location, pin.duration, pin.quantity, pin.unitPrice)
  else
    needsConfirmation = C_AuctionHouse.PostItem(pin.location, pin.duration, pin.quantity, nil, pin.buyout)
  end
  -- The client can answer inside the call itself (an error it raises on the spot). That answer
  -- has already given the row back (OnAuctionHouseError's own Post.DisarmPost) and noted its own
  -- message -- so nothing below must run over it; this guard, already needed to stop the call
  -- from being turned into a Confirm or a watchdog it never asked for, is what protects the busy
  -- look and the note too now that both run after the call instead of before.
  if S.postingRow ~= row then return end
  -- The busy look, now that the protected call is behind it: disabled, saying "Posting…", the
  -- client's spinner turning beside the words.
  row.action:Disable(); row.action:SetLabel(GC.L["Posting…"])
  if row.action.SetBusy then row.action:SetBusy(true) end
  -- Moved here, after the call: WoW: Forever's taint engine blocks a protected AH call once the
  -- same hardware click has read certain GoldCap runtime state, and _NotePost -> setStatus ->
  -- paintRefreshButton (UI/Sell/Toolbar.lua) -> refresh.deckProgress() is one of the reads it
  -- flags. Said the instant the call returns rather than the instant it was about to be made --
  -- the dock says "Posting…" either way, just a beat later in the same tick, and only when
  -- nothing inside the call already answered it (the guard just above). The client can also
  -- QUEUE the post inside the call itself (GC.Sell.OnThrottleQueued, fired synchronously from
  -- AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED): that already noted "Waiting for the Auction
  -- House…" and set postingPin.queued, so re-noting "Posting…" unconditionally here would talk
  -- over it the instant it was said -- read the same flag _EndPostNote already reads to pick
  -- the right words instead of assuming nothing answered.
  GC.Sell._NotePost(S.postingPin.queued and GC.L["Waiting for the Auction House…"] or GC.L["Posting…"])
  if needsConfirmation then
    row.postStage = "confirm"; row.action:Enable(); row.action:SetLabel(GC.L["Confirm"])
    if row.action.SetBusy then row.action:SetBusy(false) end
    GC.Sell._NotePost(GC.L["Click Confirm to post"])
  else
    Post.Sent(S.postingPin)
  end
end
Dock.OnPostClick = onPostClick

-- The Cancel lot click: a lot's own button, a position's, the dock's CANCEL. Post.PrepareCancel
-- decides; this makes the protected call first, and only then disables the button and recomposes.
local function onRepostClick(row, auctionID)
  local pin, scope = Post.PrepareCancel(row, auctionID)
  if not pin then return end
  C_AuctionHouse.CancelAuction(pin.auctionID)
  row.action:Disable()
  Post.Cancelling(row, pin, scope)
end
Dock.OnRepostClick = onRepostClick

-- The footer ledger's two totals, right to left (owner, 2026-10-10). Its three figures before
-- them were COST, ASKING and AT MARKET over every row on the deck, and read "0", "0" and
-- "Unknown" on a deck whose every price was known: the tab had moved on to a selling list and a
-- price per row, and the totals had not. PROCEEDS is what the deck brings in at the prices on
-- it, after the 5% cut; PROFIT is what that leaves once the stock is paid for, and is not shown
-- at all while the cost of any of it is unknown -- a figure with a hole in it is worse than
-- none. Same label/id split as PRICE_CHIP_LABELS/PRICE_CHIP_IDS in UI/Sell/Inspector.lua.
-- @localised-keys
local SUMMARY_STAT_LABELS = {
  "PROCEEDS", "PROFIT",
}
local SUMMARY_STAT_IDS = { "total", "profit" }
-- What each total's tooltip says under its name; PROCEEDS's, by deck.
-- @localised-keys
local SUMMARY_STAT_TIPS = {
  total = {
    post = "What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut.",
    listed = "What your lots bring in if they all sell, after the auction house's 5% cut.",
  },
  profit = "PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it.",
}

-- The button that was pressed is the one that has to answer. The row's Cancel lot arms the
-- lot's own button over in the panel; left as it was, it read as a dead control ("I press it
-- and nothing happens") with the confirm waiting a column away. Painted from
-- paintCancelButton, which every step of an arm already repaints through -- renders are
-- held while an arm lives, so a render cannot be what keeps this in step.
-- (On GC.Sell, the name paintCancelButton calls it by.)
function GC.Sell.PaintCancelMirror()
  local button = ROW.mirror
  if not button then return end
  if S.repostingRow and S.repostingRow.repostStage == "armed" then
    button.helpKey = "Cancel lot?"; button:SetLabel(GC.L["Cancel lot?"])
    if S.repostingRow.repostReady then button:Enable() else button:Disable() end
  else
    button.helpKey = "Cancel lot"; button:SetLabel(GC.L["Cancel lot"]); button:Enable()
    ROW.mirror = nil
  end
end

-- The destructive-action rule, for the row's button and the dock's alike: nothing here
-- cancels. It opens the lot's position -- onRepostClick pins to a RENDERED lot row, and a
-- shut position renders none -- finds that row and hands it the click, so the two-click arm,
-- the delay before a confirm counts, the timeout and every pin check apply unchanged. While
-- an arm is in flight the render defers, deliberately, and the row found is the armed one.
--
-- A CONFIRMING press -- the target row already "armed" from an earlier click -- hands this
-- same click straight to onRepostClick's cancel branch, which calls CancelAuction. renderRows()
-- -> pushPosition -> cacheBagLocation runs Blizzard's ItemLocation:CreateFromBagAndSlot for
-- every position with bag stock, so it must not run in that click (final review C2, same shape
-- as C1). The row is already on screen from the click that armed it, so this skips the render
-- entirely rather than only reordering it.
function ROW.armLot(entry)
  if not entry then return end
  local alreadyArmed
  for _, row in ipairs(UI.rows) do
    if row.IsShown and row:IsShown() and row.kind == "lot" and row.lot
        and row.lot.auctionID == entry.auctionID and row.repostStage == "armed" then
      alreadyArmed = true
      break
    end
  end
  if not alreadyArmed then
    for other in pairs(UI.expanded) do UI.expanded[other] = nil end
    UI.expanded[entry.positionKey] = true
    UI.List.RenderRows()
  end
  for _, row in ipairs(UI.rows) do
    -- `row:IsShown()`, never `row.shown` -- see onQueueClick's own comment on the
    -- widget-double field that shipped a dead button.
    if row.IsShown and row:IsShown() and row.kind == "lot" and row.lot
        and row.lot.auctionID == entry.auctionID then
      onRepostClick(row, entry.auctionID)
      Post.CancelSent()
      paintCancelButton()
      return
    end
  end
  setStatus(GC.L["Could not find the queue's next lot to cancel — try again"])
end

-- What the totals add up, by deck. On the posting deck, what POST lists -- the queue, whatever
-- the rows on screen are narrowed to -- at the price and the quantity each entry will post, read
-- live as the row reads them: a price or a number being typed moves PROCEEDS with the row's YOU
-- GET, not a compose later (review). On MY LOTS, every lot the player has, at its own price,
-- whatever the chips, the search or the cancel queue's focus narrow the rows to.
local function proceedsLines(deck)
  local lines = {}
  if deck == "listed" then
    for _, position in ipairs(S.positions) do
      for _, lot in ipairs(position.ownedLots or {}) do
        lines[#lines + 1] = { qty = lot.quantity, unit = lot.unitPrice, position = position }
      end
    end
    return lines
  end
  local byKey = {}
  for _, position in ipairs(S.positions) do
    if position.positionKey then byKey[position.positionKey] = position end
  end
  for _, entry in ipairs(S.queueEntries or {}) do
    local position = byKey[entry.positionKey]
    lines[#lines + 1] = { position = position,
      qty = position and postQuantity(position) or entry.postableQty,
      unit = position and effectivePostUnit(position) or entry.unitPrice }
  end
  return lines
end

local function updateSummary(deck)
  local container = UI.container
  local proceeds, profit = GC.SellPositions.Proceeds(proceedsLines(deck))
  container.summaryDeck = deck
  container.summaryShown = { total = proceeds ~= nil, profit = profit ~= nil }
  container.summary.total:SetText(proceeds and GC.Sell._FormatAmount(proceeds) or "")
  container.summary.profit:SetText(profit and GC.Sell._FormatAmount(profit) or "")
  container.summaryTone = { total = Theme.color.gold,
    profit = profit and profit < 0 and Theme.color.red or Theme.color.green }
  setColor(container.summary.profit, container.summaryTone.profit)
  -- What shows changes what the lines beside the bulk action run up to.
  Dock.LayoutLedger()
end
Dock.UpdateSummary = updateSummary

-- The posting deck's totals and how many marked items the queue held back, for the SELLING
-- heading (ROW.sectionText, UI/Sell/List.lua): on that deck the dock is one row and keeps no
-- ledger (owner, 2026-10-10). What updateSummary last added up, which the list runs before it
-- paints a heading.
function Dock.SellingAside()
  local container = UI.container
  if not (container and container.summary) then return "" end
  local shown, tone, parts = container.summaryShown or {}, container.summaryTone or {}, {}
  for i, id in ipairs(SUMMARY_STAT_IDS) do
    if shown[id] then
      parts[#parts + 1] = GC.L[SUMMARY_STAT_LABELS[i]] .. " "
        .. GC.Sell._InlineColor(tone[id] or Theme.color.fg, container.summary[id]:GetText() or "")
    end
  end
  if #S.queueSkipped > 0 then parts[#parts + 1] = (GC.L["%d held back"]):format(#S.queueSkipped) end
  return table.concat(parts, "  ·  ")
end

-- The SELLING heading's hover: each item the queue held back, and why, in the words above. The
-- rows say it too, each on its own stock line; this is all of them in one place.
function Dock.HeldBackHint()
  if #S.queueSkipped == 0 then return nil end
  local facts = { GC.L["Held back from the queue"] }
  for _, skip in ipairs(S.queueSkipped) do
    facts[#facts + 1] = ("%s: %s"):format(skip.itemName or GC.L["Item"],
      QUEUE_SKIP_TEXT[skip.reason] and GC.L[QUEUE_SKIP_TEXT[skip.reason]] or GC.L["not ready to post"])
  end
  return table.concat(facts, " · ")
end

-- The item the dock posts: the one a post of ours is out for while it is (its CONFIRM must stay
-- reachable however the queue moves meanwhile -- review), else the one the player put there by
-- clicking its row (S.dockKey), else the first item of the queue in the list's own order, top to
-- bottom -- not the queue's value order: by value a part-posted water stood in front of the linen
-- marked beside it (owner, 2026-10-10).
-- Returns that item's rendered position row, which is what the Post machinery pins (Services/
-- Sell/Post.lua), and the row of the item after it. Every position on the deck has a row of its
-- own -- the list is not windowed -- so the dock never renders to find one: a render in the
-- click that posts is what WoW: Forever's taint engine refuses (final review C1). `row:IsShown()`,
-- never `row.shown`: a real Frame has no such field (spec/ui_widget_field_spec.lua).
function Dock.Current()
  if S.filterMode == "listed" or S.filterMode == "cancelqueue" then return nil, nil end
  local queued = {}
  for _, entry in ipairs(S.queueEntries) do queued[entry.positionKey] = true end
  -- ...and what the queue held back but the player marked: the walk stops at it too, and the dock
  -- says in red why GoldCap would not list it (owner, 2026-10-10: two items held back below what
  -- they cost, and SKIP on the first left the second unoffered). Not one whose last post may
  -- still go up: that one waits.
  for _, skip in ipairs(S.queueSkipped) do
    if skip.reason ~= "awaiting_answer" then queued[skip.positionKey] = true end
  end
  local chosen
  local walk = {}
  for _, row in ipairs(UI.rows or {}) do
    if row.IsShown and row:IsShown() and row.kind == "position" and row.position
        and type(row.position.positionKey) == "string" and (row.position.bagQty or 0) > 0 then
      local key = row.position.positionKey
      if key == S.dockKey then chosen = row end
      if queued[key] then walk[#walk + 1] = row end
    end
  end
  local out = S.postingRow
  if not (out and out.kind == "position" and out.IsShown and out:IsShown()) then out = nil end
  local current = out or chosen or walk[1]
  for _, row in ipairs(walk) do
    if row ~= current then return current, row end
  end
  return current, nil
end

-- The dock's POST and the post-next key: the dock's item, through onPostClick EXACTLY -- its own
-- pin validation, its confirmation, its timeout. There is no second posting implementation here,
-- and nothing here calls a protected API directly (spec/sell_post_wiring_spec.lua). A post
-- waiting for its Confirm is that item's, so a press while it waits confirms it.
local function onQueueClick()
  -- The key works from every tab of the window, and from a closed one: a post the player cannot
  -- see is not one they chose (review). Shown flags only, which the press may read.
  if not GC.SellWalk.Shown() then return end
  local row = Dock.Current()
  if not row then
    Dock.Answer(GC.L["Nothing queued to post"])
    return
  end
  local armed = S.postingRow
  -- The dock stays on a post of ours while it is out (Dock.Current): its answer is the one to
  -- wait for, and the key press says so rather than nothing.
  if armed == row and (armed.postStage == "posting" or armed.postStage == "confirming") then
    Dock.Answer(GC.L["Finish the pending post first"])
    return
  end
  if armed and armed.postStage == "confirm" and armed.position
      and armed.position.positionKey == row.position.positionKey then
    onPostClick(armed)
    return
  end
  onPostClick(row)
end

-- The cancel control's click. Same discipline as onQueueClick, plus the destructive-action
-- rule: this function never cancels anything itself -- it finds the head's rendered LOT row
-- and hands the click to onRepostClick, whose two-click arm (the deposit warning, the
-- REPOST_ARM_SECONDS delay before a confirm counts, the timeout) and pin validation apply
-- unchanged. A first click therefore arms at most; nothing here calls a protected API --
-- see spec/sell_post_wiring_spec.lua's static guard on exactly that.
local function onCancelQueueClick()
  if #S.cancelEntries == 0 then
    setStatus(GC.L["Nothing queued to cancel"])
    return
  end
  -- The queue's own order, head first (renderRows' "cancelqueue" branch); the rest is the same
  -- hand-over the row's own Cancel lot makes -- see ROW.armLot.
  S.filterMode = "cancelqueue"
  ROW.armLot(S.cancelEntries[1])
end

-- The dock's surface, built before the toolbar as it always was.
function Dock.BuildFill()
  local container = UI.container
  -- The dock: one raised surface along the bottom carrying the deck's bulk action, what it
  -- will do next, what is happening, and the session's totals. It used to be a bare strip
  -- of widgets on the window's own background, which read as leftovers under the list rather
  -- than as the place the tab is driven from.
  local phc = Theme.color.panelHi
  local dockFill = Theme.SlicedTexture(container, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { phc[1], phc[2], phc[3], 1 }, 12)
  dockFill:SetPoint("BOTTOMLEFT"); dockFill:SetPoint("BOTTOMRIGHT")
  dockFill:SetHeight(Dock.Height())
  container.dockFill = dockFill
end

-- How tall the dock stands: one row, taller while the posting deck's item has a name or news that
-- wraps (UI/Sell/PostPanel.lua sets it). The list and the item panel stop at its top edge, so they
-- follow it here.
function Dock.Height()
  return Dock.height or DOCK.H
end

function Dock.SetHeight(height)
  local container = UI.container
  if not container or Dock.Height() == height then return end
  Dock.height = height
  if container.dockFill then container.dockFill:SetHeight(height) end
  if container.inspector then
    container.inspector:ClearAllPoints()
    container.inspector:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -34)
    container.inspector:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, height + 6)
  end
  if container.scroll and container.header then UI.List.ApplyListGeometry() end
end

-- The totals and the status line, by deck. On MY LOTS: the totals at the right end, and the
-- status line beside CANCEL, under the line naming the lot it cancels next, stopping short of
-- the totals so the two never overlap however long either grows. Under DOCK.NARROW the ledger
-- keeps PROCEEDS alone, and a total with nothing to show is not drawn. On the posting deck the
-- totals are in the SELLING heading (Dock.SellingAside) and the status line is the item's news,
-- under its name (UI/Sell/PostPanel.lua places it). Re-run on every resize and every paint.
function Dock.LayoutLedger()
  local container = UI.container
  -- Painted once before the totals are built (Dock.Build's first paintQueueButton).
  if not (container and container.summary) then return end
  local lots = S.filterMode == "listed" or S.filterMode == "cancelqueue"
  local narrow = (UI.rowWidth or 0) < DOCK.NARROW
  local shown = container.summaryShown or {}
  local left
  for _, id in ipairs(SUMMARY_STAT_IDS) do
    local value, label = container.summary[id], container.summaryLabels[id]
    -- The hover frame goes with its figure: left up over a hidden one it took the mouse from
    -- the line that runs under it (review).
    local hit = container.summaryHits and container.summaryHits[id]
    if lots and shown[id] and (id == "total" or not narrow) then
      value:Show(); label:Show()
      if hit then hit:Show() end
      left = label
    else
      value:Hide(); label:Hide()
      if hit then hit:Hide() end
    end
  end
  -- Nothing shown: the lines run to where PROCEEDS would stand.
  left = left or container.summaryLabels.total
  container.ledgerLeft = left
  if lots then
    local dockStatus, cancel, head = container.dockStatus, container.cancelButton, container.cancelHeldBack
    -- Two lines beside CANCEL when it has a lot to name, one on the dock's middle when not.
    local lift = (head and head:IsShown()) and 7 or 0
    if head then
      head:ClearAllPoints()
      head:SetPoint("LEFT", cancel, "RIGHT", 10, (dockStatus:GetText() or "") ~= "" and lift or 0)
    end
    dockStatus:ClearAllPoints()
    dockStatus:SetPoint("LEFT", cancel, "RIGHT", 10, -lift)
    dockStatus:SetPoint("RIGHT", left, "LEFT", -12, -lift)
  end
  UI.PostPanel.Layout()
end

function Dock.Build(f)
  local container = UI.container
  -- POST, beside the item it posts and everything about that post (UI/Sell/PostPanel.lua): a
  -- blind click is not one a seller should be asked to make. What GC.PostQueue.Build held back is
  -- counted in the SELLING heading (Dock.SellingAside). See paintQueueButton for how POST is
  -- painted, and onQueueClick for what a click does.
  local queueButton = Theme.Button(container, "primary", "plaque")
  -- The row's right end; the posting panel (UI/Sell/PostPanel.lua) lines up to its left. As wide
  -- as the widest of its words in the player's language, so the item's name keeps the rest.
  queueButton:SetSize(DOCK.POST_W, DOCK.BUTTON_H)
  -- Measured again at every scale (several of this suite's theme doubles have no OnRescale).
  local function fitPost()
    queueButton:FitLabels({ GC.L["POST"], GC.L["POSTING…"], GC.L["CONFIRM"] }, DOCK.POST_W, GC.L["POSTING…"])
  end
  if queueButton.FitLabels and Theme.OnRescale then fitPost(); Theme.OnRescale(fitPost) end
  -- The one glow on the tab (owner, 2026-10-09): POST in gold, CANCEL n in red when it turns to it.
  if queueButton.SetGlow then queueButton:SetGlow(true) end
  queueButton:SetPoint("RIGHT", container, "BOTTOMRIGHT", -DOCK.PAD, DOCK.CTRL_Y)
  queueButton:SetScript("OnClick", function() onQueueClick() end)
  container.queueButton = queueButton

  -- What is happening: on MY LOTS beside CANCEL, on the posting deck the item's news under its
  -- name (Dock.LayoutLedger, UI/Sell/PostPanel.lua). It wraps rather than ending in "…".
  local dockStatus = Theme.Num(container, 9)
  dockStatus:SetJustifyH("LEFT")
  dockStatus:SetWordWrap(true)
  setColor(dockStatus, Theme.color.fgMuted)
  container.dockStatus = dockStatus
  UI.PostPanel.Build()

  paintQueueButton() -- honest empty/disabled state before the very first compose ever runs

  -- The cancel queue control: row 1's right end, the far side of the row from Post -- the two
  -- queue actions are siblings, but a destructive control does not belong ADJACENT to a
  -- non-destructive one. Danger when it can burn a deposit, ghost when idle -- still the
  -- quieter look next to POST. See paintCancelButton for the states and onCancelQueueClick
  -- for what a click does (and, more importantly, does not) do.
  local cancelButton = Theme.Button(container, "ghost", "plaque")
  -- 136: "NOTHING TO CANCEL" (132.6px at mono-10 and Theme.Scale() 1.3) must fit inside.
  cancelButton:SetSize(136, DOCK.BUTTON_H)
  -- The row's left end: only one deck is ever on screen, so only POST's panel or this cluster is
  -- ever shown there.
  cancelButton:SetPoint("LEFT", container, "BOTTOMLEFT", DOCK.PAD, DOCK.MID_Y)
  cancelButton:SetScript("OnClick", function() onCancelQueueClick() end)
  container.cancelButton = cancelButton

  local cancelHeldBack = Theme.Num(container, 9)
  cancelHeldBack:SetJustifyH("LEFT")
  setColor(cancelHeldBack, Theme.color.fgDim)
  cancelHeldBack:SetPoint("LEFT", cancelButton, "RIGHT", 10, 0) -- and up a line over the status
  cancelHeldBack:Hide()
  container.cancelHeldBack = cancelHeldBack

  -- Same FontString-cannot-take-mouse-scripts fix as the posting queue's held-back label.
  local cancelHeldBackHit = CreateFrame("Frame", nil, container)
  cancelHeldBackHit:SetAllPoints(cancelHeldBack)
  cancelHeldBackHit:EnableMouse(true)
  cancelHeldBackHit:Hide()
  cancelHeldBackHit:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GC.Util.ClientText(GC.L["Held back from cancelling"]), 1, 0.82, 0)
    if #S.cancelSkipped == 0 then
      GameTooltip:AddLine(GC.Util.ClientText(GC.L["Nothing is being held back."]), 0.85, 0.85, 0.85, true)
    else
      for _, skip in ipairs(S.cancelSkipped) do
        GameTooltip:AddLine(GC.Util.ClientText(("%s — %s"):format(skip.itemName or GC.L["Item"],
          (QUEUE_SKIP_TEXT[skip.reason] and GC.L[QUEUE_SKIP_TEXT[skip.reason]]
            or GC.L["not ready to cancel"]))), 0.85, 0.85, 0.85, true)
      end
    end
    GameTooltip:Show()
  end)
  cancelHeldBackHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  container.cancelHeldBackHit = cancelHeldBackHit

  paintCancelButton()

  -- The real keybinding (Bindings.xml, auto-loaded by the client, not listed in the .toc -- see
  -- that file) reaches into this exact field on the Sniper window frame, because Bindings.xml
  -- executes as its own isolated Lua chunk with no upvalues into this file. It calls the SAME
  -- Lua function the button's own OnClick calls above -- never Button:Click(), which both
  -- inherits the caller's taint and skips RegisterForClicks/the mouse-down handling (see the
  -- design document's own reasoning). A keybinding handler already runs synchronously inside a
  -- real hardware input event, which is what a protected post actually requires.
  f.GoldCapPostNext = onQueueClick

  -- The totals: MY LOTS's right end, what the session adds up to -- a thing to glance at
  -- on the way out, not a thing to read before starting. See SUMMARY_STAT_LABELS above for what
  -- each one is and why. Inline, label then figure, each as wide as its text.
  container.summary, container.summaryLabels = {}, {}
  local ledgerPrevious
  for i, id in ipairs(SUMMARY_STAT_IDS) do
    local value = Theme.Num(container, 10, true)
    value:SetJustifyH("RIGHT"); value:SetWordWrap(false)
    if ledgerPrevious then value:SetPoint("RIGHT", ledgerPrevious, "LEFT", -16, 0)
    else value:SetPoint("RIGHT", container, "BOTTOMRIGHT", -DOCK.PAD, DOCK.MID_Y) end
    local label = Theme.Num(container, 9)
    label:SetJustifyH("RIGHT"); label:SetWordWrap(false)
    label:SetPoint("RIGHT", value, "LEFT", -6, 0)
    label:SetText(GC.L[SUMMARY_STAT_LABELS[i]]); setColor(label, Theme.color.fgDim)
    if id == "total" then setColor(value, Theme.color.gold) end
    container.summary[id], container.summaryLabels[id] = value, label
    -- What the figure is, on hover: a FontString cannot take mouse scripts, so an invisible
    -- frame over the label and the figure, which read as one control. The deck is read at
    -- hover time, so the words cannot go stale between renders.
    local hit = CreateFrame("Frame", nil, container)
    hit:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 4)
    hit:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", 0, -4)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
      if not GameTooltip or not value:IsShown() then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(GC.Util.ClientText(GC.L[SUMMARY_STAT_LABELS[i]]), 1, 0.82, 0)
      local tip = SUMMARY_STAT_TIPS[id]
      if type(tip) == "table" then tip = tip[container.summaryDeck or "post"] end
      GameTooltip:AddLine(GC.Util.ClientText(GC.L[tip]), 0.85, 0.85, 0.85, true)
      GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    container.summaryHits = container.summaryHits or {}
    container.summaryHits[id] = hit
    ledgerPrevious = label
  end
  Dock.LayoutLedger()
end

GC.SellView.status = function(...) return UI.Dock.SetStatus(...) end
GC.SellView.paintQueue = function(...) return UI.Dock.PaintQueueButton(...) end
GC.SellView.paintCancel = function(...) return UI.Dock.PaintCancelButton(...) end
GC.SellView.notePost = function(...) return GC.Sell._NotePost(...) end
GC.SellView.endPostNote = function(...) return GC.Sell._EndPostNote(...) end
