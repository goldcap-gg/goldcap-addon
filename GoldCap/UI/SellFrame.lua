local _, GC = ...

GC.Sell = GC.Sell or {}

-- Labels for the posting-queue keybinding (Bindings.xml, auto-loaded by the client -- see that
-- file for the binding itself and GC.Sell.Attach below for the handler it calls). Purely
-- cosmetic: the Key Bindings UI falls back to the raw action name if these are missing, so the
-- feature works without them, but a human label is worth the two lines. `_G.` explicit, not a
-- bare assignment, so this is a plain field write on the standard `_G` table rather than a new
-- global luacheck would need to be told about.
_G.BINDING_HEADER_GOLDCAP = "GoldCap"
-- Assigned through GC.SellUI.RefreshBindingName, called from Init once the locale is
-- active. Resolving GC.L here would capture the English fallback: this file loads long
-- before ApplyLocale picks a language, so the binding would read English forever.
function GC.SellUI_RefreshBindingName()
  _G.BINDING_NAME_GOLDCAP_POST_NEXT = GC.L["Post the next queued item"]
end

local Theme = GC.Theme
-- The checks and constants this file shares with the Sell services (Services/Sell/State.lua).
local S = GC.SellState
local Bags, Walk, Post = GC.SellBags, GC.SellWalk, GC.SellPost
local exact, safeAdd, safeMultiply, effectivePostUnit = GC.SellUtil.exact, GC.SellUtil.safeAdd,
  GC.SellUtil.safeMultiply, GC.SellUtil.effectivePostUnit
local itemName = GC.SellUtil.itemName
local EMPTY_ANSWER_AGE = GC.Sell.EMPTY_ANSWER_AGE

-- The view's shared pieces (UI/Sell/Frame.lua): the geometry more than one part lays out by, and
-- the pure text helpers.
local UI = GC.SellUI
local COLUMNS, ROW, DR, INSP, DOCK = UI.COLUMNS, UI.ROW, UI.DR, UI.INSP, UI.DOCK
local setColor, formatCell, DIM_HEX, MONEY_HEX = UI.fmt.setColor, UI.fmt.cell, UI.fmt.DIM_HEX, UI.fmt.MONEY_HEX

-- The positions module owns all accounting and action-plan decisions.  This file only joins
-- live AH observations, a cached quote stream, and widgets around that single model.

-- Labels for the deck switch and the two chips. Parallel tables, exactly like
-- PRICE_CHIP_LABELS/PRICE_CHIP_IDS in UI/Sell/Inspector.lua and for both of the same reasons: the contract
-- scanner reads EVERY literal inside an @localised-keys table as a key, so an id sitting in the
-- same table would be collected as a translatable string nobody ever shows; and the id is what
-- the code switches on, never the label, which a translation changes out from under it.
-- @localised-keys
local DECK_LABELS = {
  "TO POST %d", "MY LOTS %d",
}
local DECK_IDS = { "post", "listed" }
-- @localised-keys
local CHIP_LABELS = {
  "READY", "NO COST",
}
local CHIP_IDS = { "ready", "nocost" }
-- "READY" is 5 chars and "NO COST" 7, but both carry the rounded badge's own inset: 92/76 match
-- what the five chips they replaced used for labels of the same length.
local CHIP_WIDTHS = { 92, 76 }
local renderGeneration = 0

-- Forward-declared here rather than further down: the callers above its real body in this
-- file (setStatus, ROW.armLot, the row handlers) need it. Services/Sell/Post.lua reaches it as
-- GC.SellView.render, filled at the bottom of this file.
local function renderRows() end
-- Forward-declared for the same reason renderRows is: setStatus (defined further down, but
-- above formatCell) needs to call this on every state change, and the row handlers need it
-- on every data change -- see this function's real body, well
-- below formatCell, for why it cannot be defined this early itself. renderRows DEFERS for the
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

-- The status line lives in the Sniper's toolbar, at the far left of a different
-- row from the Refresh button -- a window's width away from what was just
-- pressed. That is the same distance that made Scan look dead. So the button
-- carries the state too, and the progress with it: "PRICING 3/24" answers "is it
-- running" without the player having to hunt for a line of text.
local function paintRefreshButton()
  local button = UI.container and UI.container.refreshButton
  if not button then return end
  local phase = S.refresh.phase
  local busy = phase ~= "idle" and phase ~= "done" and phase ~= "error"
  local label = "REFRESH"
  if busy then
    -- "PRICING 10/24", not a bare "10/24". This button sits at the end of a row of filter
    -- chips, so a naked ratio reads as one more filter -- and the owner reasonably asked why
    -- the tab only had 24 items in it. It is not a count of anything the player owns: it is
    -- how far this pass has got through the pricing queue, which is capped at QUOTE_WALK_CAP
    -- because every entry is a round trip on the same throttled slot the Sniper's scans use.
    -- Once the bulk fill has priced the tab, what the walk is still fetching is each row's
    -- book -- and a button that went on saying PRICING for twelve seconds over a list whose
    -- prices were all there read as the refresh itself being that slow.
    -- Of the deck on screen, not of the queue: the walk prices both decks, and "BOOKS 4/27"
    -- over ten rows was the same puzzle again. While it is on the other deck's rows the count
    -- stands at this deck's full figure and the button stays lit.
    local counting = S.refresh.bulkLanded and GC.L["BOOKS %d/%d"] or GC.L["PRICING %d/%d"]
    local done, total = S.refresh.deckProgress()
    label = done > 0 and counting:format(done, total) or GC.L["PRICING…"]
  end
  if button.lastLabel ~= label then
    button.lastLabel = label
    button:SetLabel(label)
  end
  if button.lastBusy ~= busy then
    button.lastBusy = busy
    if button.SetVariant then button:SetVariant(busy and "active" or "ghost") end
  end
end
UI.Toolbar.PaintRefreshButton = paintRefreshButton

local function setStatus(text)
  if UI.window and UI.window.status then UI.window.status:SetText(text) end
  GC.Sell._lastStatus = text
  -- And in the dock, under the bulk action: the toolbar line above is a window's width from
  -- every control on this tab, which is why REFRESH, POST and each row button had to grow a
  -- copy of the state. Said here, it is said beside the button that was just pressed -- unless
  -- the player's own post has something to say there (GC.Sell._NotePost below), in its colour.
  GC.Sell._PaintDock(text)
  paintRefreshButton()
  paintQueueButton()
  -- The cancel control is driven from here for the same reason the queue control is: renderRows
  -- DEFERS for the whole time a repost is armed, so a render cannot be relied on to keep it in
  -- step with the arm/confirm dance. It was missing, and the one transition that mattered most
  -- went unpainted -- the footer still read "CANCEL LOT?", still enabled, while the cancel it
  -- named was already on the wire.
  paintCancelButton()
end
UI.Dock.SetStatus = setStatus

-- The dock's line belongs to the player's own post while it has something to say about it.
-- The owner pressed Post and could not tell whether anything was happening: the pricing walk
-- writes this line every few seconds and wrote over "Posting…" within the second, the refresh
-- after a refusal replaced "Posting failed" before it was ever drawn, and a post that went up
-- said nothing at all. So a note holds the dock -- a post on its way until the post ends
-- (Post.DisarmPost lets it go), an outcome for its few seconds -- whatever the walk says meanwhile.
-- The toolbar line keeps the walk's words; when the note ends the dock goes back to them.
-- `tone` is a Theme.color key. Fields rather than locals: this chunk is at Lua 5.1's limit.

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

-- The one-word state a row wears at the end of its stock line, and only when something is off:
-- a row that is ready says nothing. It replaces the WHAT TO DO column, which no deck had room
-- for at any width, so the reason a row was left out of the queue was one hover away on a
-- counter in the footer and nowhere on the row it was about. Keyed by GC.PostQueue's and
-- GC.CancelQueue's own reason tokens; `alarm` paints red, `wait` the watch blue, the rest dim.
-- @localised-keys
local ROW_TAG_TEXT = {
  no_fresh_price = "no live price",
  unresolved_identity = "stack not identified",
  advised_hold = "hold",
  below_vendor = "vendor pays more",
}

local rowTag
do
-- No tag for below_breakeven: the red margin under YOU GET is that fact, on the same row, and
-- the words were the first thing a narrow list cut to "be...".
local ROW_TAG_TONE = { no_fresh_price = "wait" }

-- The tag itself, already coloured, or "" for a row with nothing to say. `reason` is the skip
-- token the deck's queue gave this position, if it skipped it. Money leaving silently outranks
-- everything: a lot standing far below market is the one thing on the row that has to be read
-- first, and it used to be written into a column no deck shows.
--
-- A function of its own rather than lines inside renderRows for a reason the client enforces
-- and busted does not: WoW runs Lua 5.1, which caps a function at 60 upvalues, and renderRows
-- sits close enough to that cap that three more tables put the whole file out of action.
rowTag = function(position, reason, notOnHand)
  local tag, tone
  if position.facts and position.facts.underpriced then
    tag, tone = GC.L["far below market"], "alarm"
  elseif reason then
    tag, tone = ROW_TAG_TEXT[reason] and GC.L[ROW_TAG_TEXT[reason]] or nil, ROW_TAG_TONE[reason]
  end
  local uncosted = math.max(0, (position.exposureQty or 0) - (position.knownQty or 0))
  if not tag and position.coverage ~= "COMPLETE" and not notOnHand and uncosted > 0 then
    tag = (GC.L["no cost for %d"]):format(uncosted)
  end
  if not tag then return "" end
  local color = tone == "alarm" and Theme.color.red or tone == "wait" and Theme.color.watch
    or Theme.color.fgDim
  return "  " .. GC.Sell._InlineColor(color, tag)
end
end -- do: keeps the helpers above out of the file's own local count (Lua 5.1 allows 200)

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

-- Three different emptinesses needing three different next moves, where the old copy had one
-- sentence ("No items match this filter") that answered none of them: a deck that is genuinely
-- empty, a chip that emptied it, or the OTHER deck holding everything. Read live from the deck
-- and chip state rather than passed in, so it can never disagree with what the switch is
-- painting.
-- A GC.Sell field, not a top-level local: paint-only, same reason as _FormatAmount above
-- (final review "Headroom").
function GC.Sell._EmptyDeckText()
  if UI.chips.search then return GC.L["Nothing on this deck matches that search"] end
  if S.filterMode == "listed" or S.filterMode == "cancelqueue" then
    return GC.L["No live auctions on this character"]
  end
  if UI.chips.ready then return GC.L["Nothing is priced yet - the Auction House is still answering"] end
  if UI.chips.nocost then return GC.L["Every position in your bags already has a cost on record"] end
  return GC.L["Nothing in your bags to list"]
end

-- The real body, promised by the forward declaration above. Needs formatCell (just above) and
-- container/queueEntries/queueSkipped/postingRow (all declared well above this point), so it
-- could not be written any earlier than here.
paintQueueButton = function()
  local button, label = UI.container and UI.container.queueButton, UI.container and UI.container.queueLabel
  if not button then return end
  local heldBack, heldBackHit = UI.container.queueHeldBack, UI.container.queueHeldBackHit
  -- The post queue is the POST deck's bulk action and shares the footer slot with the cancel
  -- queue's. Hidden, not disabled, on the other deck: a disabled control invites a click that
  -- can never work, and this one belongs to a screen the player is not on.
  if S.filterMode == "listed" or S.filterMode == "cancelqueue" then
    button:Hide()
    if label then label:SetText(""); label:Hide() end
    if heldBack then heldBack:Hide() end
    if heldBackHit then heldBackHit:Hide() end
    return
  end
  button:Show()
  if label then label:Show() end
  -- Row 1 of the QUEUE's own order, not of whatever filter chip happens to be on screen right
  -- now: this control acts on GC.PostQueue's own head regardless of what the player is currently
  -- looking at, and paints itself from that same head so what it says is never a guess about
  -- what a render would show if one ran right now.
  local head = S.queueEntries[1]
  -- The spinner turns for as long as a post of ours is on the wire, whichever button sent it:
  -- the dock's POST is disabled either way, and disabled alone reads as dead.
  local sending = S.postingRow ~= nil and (S.postingRow.postStage == "posting" or S.postingRow.postStage == "confirming")
  if button.SetBusy then button:SetBusy(sending) end
  if S.postingRow then
    -- Mirror the row postingRow itself pins to -- see onQueueClick/onPostClick -- only when
    -- that row genuinely IS the queue's own head. If some OTHER row's post is in flight (the
    -- player clicked a row's own Post button directly, on a position that is not the head),
    -- this control simply disables rather than offering a second, conflicting click; it must
    -- never claim "CONFIRM" for a click that would land on the wrong row.
    local sameHead = head and S.postingRow.position and S.postingRow.position.positionKey == head.positionKey
    if sameHead and S.postingRow.postStage == "confirm" then
      button:SetLabel(GC.L["CONFIRM"]); button:Enable()
    else
      button:SetLabel(GC.L["POSTING…"]); button:Disable()
    end
    -- The item going up, not the head: a row's own Post can be any row on the list.
    local going = S.postingRow.position and S.postingRow.position.itemName or head and head.itemName
    if label then label:SetText(going or "") end
  elseif not head then
    button:SetLabel(GC.L["NOTHING TO POST"])
    button:Disable()
    if label then label:SetText("") end
  else
    button:SetLabel((GC.L["POST %d"]):format(#S.queueEntries))
    button:Enable()
    if label then label:SetText(("%s @ %s"):format(head.itemName or GC.L["Item"], formatCell(head.unitPrice))) end
  end
  if heldBack then
    if #S.queueSkipped > 0 then
      -- "from posting", because the cancel queue paints an identical counter near its own
      -- button (paintCancelButton below) and two bare "N held back" strings on one screen
      -- would leave the reader guessing which queue each one describes.
      heldBack:SetText((GC.L["%d held back from posting"]):format(#S.queueSkipped))
      heldBack:Show()
      if heldBackHit then heldBackHit:Show() end
    else
      heldBack:SetText("")
      heldBack:Hide()
      if heldBackHit then heldBackHit:Hide() end
    end
  end
end
UI.Dock.PaintQueueButton = paintQueueButton

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
end
UI.Dock.PaintCancelButton = paintCancelButton

local function currentPosition(positionKey)
  for _, position in ipairs(S.positions) do
    if position.positionKey == positionKey then return position end
  end
  return nil
end

-- The Post click: the row's button, the inspector's, the dock's POST and the key binding all end
-- here. Post.PreparePost decides; this makes the protected call, the first thing the click does
-- with the client, and only then gives the button its busy look and the dock its note.
local function onPostClick(row)
  local step = Post.PreparePost(row)
  if not step then return end
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
      -- setStatus -> paintRefreshButton -> refresh.deckProgress() (this file, above) is one of
      -- the reads it flags. Said the instant the call returns rather than the instant it was
      -- about to be made -- the player sees the same "Posting…" note either way, just a beat
      -- later in the same tick, unless the call queued the confirm itself (OnThrottleQueued,
      -- same guard the first click's own note now reads).
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
  -- paintRefreshButton -> refresh.deckProgress() (this file, above) is one of the reads it
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
UI.Dock.OnPostClick = onPostClick

-- The Cancel lot click: a lot's own button, a position's, the dock's CANCEL. Post.PrepareCancel
-- decides; this makes the protected call first, and only then disables the button and recomposes.
local function onRepostClick(row, auctionID)
  local pin, scope = Post.PrepareCancel(row, auctionID)
  if not pin then return end
  C_AuctionHouse.CancelAuction(pin.auctionID)
  row.action:Disable()
  Post.Cancelling(row, pin, scope)
end
UI.Dock.OnRepostClick = onRepostClick




-- The item name is the one column that must stay readable: every other cell is a number that
-- also lives in the tooltip or the expansion, but a row whose name is "Aze..." is useless.
-- `min` on the flex column was declared and never honoured, so the name silently collapsed to
-- nothing as soon as the fixed columns outgrew the window. Shed load-bearing weight in order
-- instead: the listed total (already in the summary), then squeeze the advice text, then drop
-- it entirely (the action button carries the same guidance on its tooltip), and only then the
-- cost per unit (which the expansion spells out per purchase).
-- 160, was 200. The name has its own truncation and a tooltip carrying it in full; COST/UNIT
-- has neither, and at 200 the name's floor was what pushed it off the screen.
local ITEM_MIN = 160
local STATUS_MIN = 110
local columnWidth = {}

-- Which columns each deck lays out. Not cosmetics: one column set had to serve both jobs at
-- once, which is what made it eight columns wide, which is what made the shedding order reach
-- load-bearing numbers at the DEFAULT window. At 720x600 the old set dropped LISTED and then
-- COST / UNIT by arithmetic, not by bad luck -- the column this whole tab exists to answer was
-- off screen for every player who never resized. Splitting by deck is what buys the room back.
local DECK_COLUMNS = {
  post = { item = true, price = true, gross = true, action = true },
  -- No cost/profit on a live lot: what a listed row is asked is "what did I list at, and who
  -- is under me". Its cost basis has not changed since it was posted and is one click away in
  -- the expansion. "Who is under me" is the line under YOUR PRICE now, in units, which is the
  -- half of that question the old UNDER YOU column (a bare price) never answered.
  listed = { item = true, price = true, listed = true, action = true },
}
-- What a deck gives up once squeezing every minimum still does not fit, in order.
--
-- Nothing, on either deck, since each is down to two figures and the button: at the narrowest
-- window the item name still clears ITEM_MIN with both at their minimum. The table stays so
-- that the next column anybody adds has to say where it goes when the room runs out.
local DECK_SHED = {
  post = {},
  listed = {},
}

-- Content-sized figure columns. FIT.need (defined below ROW, which it reads) answers how wide a
-- column must be to print its longest heading and second line in full in the active language
-- and font scale; shownColumns never makes a column narrower than that.
local FIT = {}

local function shownColumns()
  local width = INSP.listWidth()
  local deck = (S.filterMode == "listed" or S.filterMode == "cancelqueue") and "listed" or "post"
  local inDeck = DECK_COLUMNS[deck]
  local dropped = {}
  columnWidth = {}
  -- A column this deck does not carry is DROPPED, not merely absent from `shown`: layoutCells
  -- hides exactly what `dropped` names, and a pooled row that drew the column on the other deck
  -- last render would otherwise keep painting it here forever.
  for _, column in ipairs(COLUMNS) do
    if not inDeck[column.key] then dropped[column.key] = true end
  end

  -- A translation longer than the column's design width widens the column rather than being cut:
  -- the flexible ITEM column gives up the difference.
  for _, column in ipairs(COLUMNS) do
    if not column.flex and not dropped[column.key] then
      local need = FIT.need(column.key, deck)
      if need > column.w then columnWidth[column.key] = need end
    end
  end

  local function remaining()
    local total = 0
    for _, column in ipairs(COLUMNS) do
      if not column.flex and not dropped[column.key] then
        total = total + (columnWidth[column.key] or column.w) + 2
      end
    end
    return width - total
  end

  if width > 0 then
    -- Squeeze everything that has a floor before giving anything up. Every minimum here was
    -- measured against a real string at Theme.Scale() 1.3, not guessed.
    if remaining() < ITEM_MIN then columnWidth.status = STATUS_MIN end
    if remaining() < ITEM_MIN then
      for _, column in ipairs(COLUMNS) do
        if column.min then
          columnWidth[column.key] = math.max(column.min, FIT.need(column.key, deck))
        end
      end
    end
    for _, key in ipairs(DECK_SHED[deck]) do
      if remaining() >= ITEM_MIN then break end
      dropped[key] = true
      columnWidth[key] = nil
    end
  end

  local shown = {}
  for _, column in ipairs(COLUMNS) do
    if not dropped[column.key] then shown[#shown + 1] = column end
  end
  return shown, dropped
end

-- The footer ledger's three labels, same split as PRICE_CHIP_LABELS/PRICE_CHIP_IDS in
-- UI/Sell/Inspector.lua and for the same reason. "AT MARKET" and "ASKING", not "PROFIT" and "LISTED" (2026-09-11): a
-- player reads three figures left to right as ASKING minus COST equalling the rightmost one,
-- and that arithmetic is false -- ASKING is the sum of the player's own typed prices, AT
-- MARKET is what GoldCap projects these lots clear after the 5% cut, at a price nobody typed.
-- Distinct labels don't fix the misreading by themselves; the AT MARKET tooltip carries the
-- actual sentence.
-- @localised-keys
local SUMMARY_STAT_LABELS = {
  "AT MARKET", "ASKING", "COST",
}
local SUMMARY_STAT_IDS = { "profit", "listed", "cost" }

-- One hidden probe per font size, the same face and size as the text it stands in for: the
-- header cells (9), the stand line (10) and the margin line (11).
function FIT.width(size, text)
  if not UI.container or not Theme or type(text) ~= "string" or text == "" then return 0 end
  FIT.probes = FIT.probes or {}
  local probe = FIT.probes[size]
  if not probe then
    probe = Theme.Num(UI.container, size)
    probe:Hide()
    FIT.probes[size] = probe
  end
  probe:SetText(text)
  return probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth() or 0
end

-- MY LOTS, as the redesign drew it. Functions on ROW rather than file locals: this chunk sits
-- at Lua 5.1's limit of 200, and renderRows at its limit of 60 upvalues.
-- (The two key tables stand at file scope, closing brace in column 0: that is how the locale
-- contract's scanner finds where an @localised-keys table ends.)
-- @localised-keys
ROW.SECTION_TITLES = {
  undercut = "UNDERCUT %d", low = "PRICED TOO LOW %d", hold = "HOLDING %d",
}
-- @localised-keys
ROW.SECTION_HINTS = {
  undercut = "worth cancelling", hold = "leave these alone",
}
do
  -- The deck in section order, and which section each position fell into.
  function ROW.bySection(filtered)
    local ordered, sectionOf = {}, {}
    for _, section in ipairs(GC.SellViewModel.LotSections(filtered, S.cancelEntries)) do
      for _, position in ipairs(section.positions) do
        ordered[#ordered + 1] = position
        sectionOf[position] = section
      end
    end
    return ordered, sectionOf
  end

  function ROW.sectionText(section)
    local hint = ROW.SECTION_HINTS[section.id]
    return (GC.L[ROW.SECTION_TITLES[section.id]]):format(#section.positions)
      .. (hint and ("  " .. DIM_HEX .. GC.L[hint] .. "|r") or "")
  end

  -- "400 in 2 lots" on MY LOTS, where how the stock is listed is what the row is about; the
  -- posting deck keeps its plain count beside the bags'.
  function ROW.listedText(position, listedQty, onListed)
    local lots = #(position.ownedLots or {})
    if not onListed or lots == 0 then return (GC.L["×%d listed"]):format(listedQty) end
    if lots == 1 then return (GC.L["%d in 1 lot"]):format(listedQty) end
    return (GC.L["%d in %d lots"]):format(listedQty, lots)
  end

  -- The TO POST deck's last section: stock in the bags the tab cannot key yet (the client has
  -- not said whether it is a commodity, or cannot give its ItemKey -- GC.Sell._waitingStock).
  -- It used to be left out without a word. A heading and a line per item; nothing to post from
  -- until the client answers, and then the rescan files it (GC.Sell.OnItemKeyInfo). The search
  -- narrows it like every other row.
  function ROW.pushWaiting(entries)
    local shown = {}
    for _, waiting in ipairs(GC.Sell._waitingStock or {}) do
      local name = type(waiting.itemName) == "string" and waiting.itemName ~= "" and waiting.itemName
        or itemName(waiting.itemID)
      if not UI.chips.search or name:lower():find(UI.chips.search, 1, true) then
        shown[#shown + 1] = { kind = "waitItem", name = name, quantity = waiting.quantity,
          position = { itemID = waiting.itemID, itemName = name } }
      end
    end
    if #shown == 0 then return end
    entries[#entries + 1] = { kind = "waitHead", count = #shown, position = { itemID = 0 } }
    for _, entry in ipairs(shown) do entries[#entries + 1] = entry end
  end

  -- Two copies of one piece at two item levels were two identical rows (review M9): a variant's
  -- row names its level -- a pet's, its pet level -- from its own key.
  function ROW.variantSuffix(position)
    local level = type(position.quoteKey) == "string" and tonumber(position.quoteKey:match("^item:%d+:(%d+):"))
    if position.variantKind == "pet" then
      -- A pet's level is the one its battle-pet link states. What the client's ItemKey carries in
      -- its level field for a caged pet is not confirmed off the client (final review M5).
      local stack = position.bagStacks and position.bagStacks[1]
      local lot = position.ownedLots and position.ownedLots[1]
      local link = stack and stack.link or lot and lot.itemLink
      level = type(link) == "string" and tonumber(link:match("battlepet:%d+:(%d+)")) or nil
    end
    if not level or level <= 0 then return "" end
    local words = position.variantKind == "pet" and (GC.L["level %d"]):format(level) or (GC.L["ilvl %d"]):format(level)
    return "  " .. DIM_HEX .. words .. "|r"
  end

  -- The heading's title, and its aside for the heading's own hint cell (renderRows): run on in
  -- the label, the aside went past the list's edge and was cut mid-word (final review M1).
  function ROW.waitText(entry)
    if entry.kind == "waitHead" then
      local open = GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()
      return (GC.L["WAITING FOR THE AUCTION HOUSE %d"]):format(entry.count),
        open and GC.L["the auction house has not sent details for these yet"]
          or GC.L["open the auction house once so GoldCap can tell how these sell"]
    end
    return ("%s ×%d"):format(entry.name, entry.quantity or 0)
  end

  -- The first of this position's lots the cancel queue holds, or nil: the queue is the one
  -- judge of what is worth cancelling, for the row's button as for the dock's.
  function ROW.queuedLot(position)
    for _, entry in ipairs(S.cancelEntries) do
      if entry.positionKey == position.positionKey then return entry end
    end
    return nil
  end

  -- The button that was pressed is the one that has to answer. The row's Cancel lot arms the
  -- lot's own button over in the panel; left as it was, it read as a dead control ("I press it
  -- and nothing happens") with the confirm waiting a column away. Painted from
  -- paintCancelButton, which every step of an arm already repaints through -- renders are
  -- held while an arm lives, so a render cannot be what keeps this in step.
  -- (On GC.Sell, not ROW: paintCancelButton is written above where ROW is declared.)
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
      renderRows()
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
end

-- One column can mean two things depending on the deck, and a heading that lies is worse than
-- no heading: MARKET / UNIT is "the cheapest ask that is not mine" while you are choosing a
-- price to post at, and "who is standing under my lot" once it is posted. Same number, two
-- questions, two words for it.
-- @localised-keys
local HEADINGS_POST = {
  item = "ITEM", gross = "YOU GET", price = "PRICE / UNIT",
  cost = "COST / UNIT", listed = "LISTED", market = "MARKET / UNIT",
  profit = "PROFIT / UNIT", status = "WHAT TO DO",
}
-- @localised-keys
local HEADINGS_LISTED = {
  item = "LISTED AS", gross = "IN THE LOT", price = "YOUR PRICE",
  cost = "COST / UNIT", listed = "LOT VALUE", market = "UNDER YOU",
  profit = "PROFIT / UNIT", status = "WHAT TO DO",
}

-- The widest thing a column prints besides its figure: its heading on either deck and, for the
-- two figures that carry one, the second line. The count in the stand line is FormatCount's
-- widest shape ("99.9k" -- five characters). Cached per language and font scale, the only two
-- things that change the answer.
function FIT.need(key, deck)
  local scale = Theme and Theme.Scale and Theme.Scale() or 1
  local stamp = tostring(GC.L["YOU GET"]) .. "|" .. tostring(scale) .. "|" .. tostring(deck)
  if FIT.stamp ~= stamp then
    FIT.stamp, FIT.cache = stamp, {}
    local words = deck == "listed" and HEADINGS_LISTED or HEADINGS_POST
    for columnKey, word in pairs(words) do
      FIT.cache[columnKey] = FIT.width(9, GC.L[word])
    end
    local count = "99.9k"
    local stand = math.max(FIT.width(10, GC.L["first in line"]),
      FIT.width(10, (GC.L["%s ahead"]):format(count)),
      FIT.width(10, (GC.L["%s+ ahead"]):format(count)),
      FIT.width(10, (GC.L["%s under you"]):format(count)))
    if stand > 0 then FIT.cache.price = math.max(FIT.cache.price or 0, stand + ROW.MARKS_W) end
    local margin = math.max(FIT.width(11, GC.L["no cost"]), FIT.width(11, "+9999%"))
    if margin > 0 then FIT.cache.gross = math.max(FIT.cache.gross or 0, margin) end
    -- A few pixels of air: an exactly-fitting string sits flush against its neighbour.
    for columnKey, width in pairs(FIT.cache) do
      FIT.cache[columnKey] = width > 0 and math.ceil(width + 6) or 0
    end
  end
  return FIT.cache[key] or 0
end

local function paintHeaderText(header, deck)
  local words = deck == "listed" and HEADINGS_LISTED or HEADINGS_POST
  for key, cell in pairs(header.cells) do
    local word = words[key]
    cell:SetText(word and GC.L[word] or "")
  end
end

-- Which figure carries a second line, and the row field that line lives in.
ROW.SECOND_LINE = { price = "priceStand", gross = "grossNote", listed = "grossNote" }

local function layoutCells(row)
  local right = row
  -- How far `right` itself sits above the row's centre. Every cell anchors to its neighbour,
  -- so a lifted neighbour lifts whatever hangs off it: offsets are written relative to this,
  -- or the second lifted cell in a chain lands a full row-half too high (seen in game -- the
  -- price rode up into the row above it).
  local rightLift = 0
  local cols, dropped = shownColumns()
  for i = #cols, 1, -1 do
    local column, cell = cols[i], row.cells[cols[i].key]
    cell:ClearAllPoints()
    if column.flex then
      -- row.itemInset leaves room for the icon on a position row, and indents a child row so
      -- the hierarchy is carried by layout instead of by leading spaces in the string. The box
      -- this defines is shared by three mutually exclusive widgets -- this cell (a position),
      -- row.subItem (a detail/batch/lot/listing sub-row) and row.sectionLabel (a group heading)
      -- -- exactly one of which is shown per row (the kind branch in renderRows), so all three
      -- get the same anchors rather than fighting over layout.
      -- The name sits in the upper half of the row and its stock line in the lower half; the
      -- header row and every sub-row keep the whole box, centred, because they carry one line.
      -- 8, not 7: at Theme.Scale 1.3 a 12px name is ~15.6 tall and a 10px stock line ~13, so
      -- the two boxes touch at ±7 and clear each other at ±8 inside the 32px row.
      local nameY = row.itemStock and ROW.LIFT or 0
      cell:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, nameY)
      cell:SetPoint("RIGHT", right, "LEFT", -4, nameY - rightLift)
      if row.itemStock then
        row.itemStock:ClearAllPoints()
        row.itemStock:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, -ROW.LIFT)
        row.itemStock:SetPoint("RIGHT", right, "LEFT", -4, -ROW.LIFT - rightLift)
      end
      -- The column header row (below) shares this function but carries neither widget -- it is
      -- a single fixed heading, never a position/sub-row/group in the pooled row sense.
      if row.subItem then
        row.subItem:ClearAllPoints()
        -- Clears the fixed width layoutBookRow gives it. Rows are pooled: a row that drew a
        -- book level last render would otherwise keep an 84px price column forever, fighting
        -- the LEFT/RIGHT pair below for the rest of its life.
        row.subItem:SetWidth(0)
        row.subItem:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
        row.subItem:SetPoint("RIGHT", right, "LEFT", -4, -rightLift)
      end
      if row.sectionLabel then
        row.sectionLabel:ClearAllPoints()
        row.sectionLabel:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
      end
      -- Deliberately no cell:Show() here: which of item/subItem/sectionLabel is visible is the
      -- kind branch's call (renderRows), not this function's -- forcing the flex column shown
      -- unconditionally would undo a "position" row's own cells.item:Hide() on every layout.
      -- The header row (below) sets its own item cell's text once and never hides it.
    else
      cell:SetWidth(columnWidth[column.key] or column.w)
      -- A position's figures share the row with a second line, exactly as its name does with the
      -- stock line (same +-8 split, same reason). Every other kind keeps the cell centred.
      local second = row.kind == "position" and ROW.SECOND_LINE[column.key] and row[ROW.SECOND_LINE[column.key]] or nil
      local lift = second and ROW.LIFT or 0
      -- The figure beside the button stands clear of it: at the usual 2px the row's total ran
      -- into the button's own edge.
      local gap = right == row and 0 or right == row.cells.action and -ROW.BUTTON_GAP or -2
      cell:SetPoint("RIGHT", right, right == row and "RIGHT" or "LEFT", gap, lift - rightLift)
      if second then
        second:ClearAllPoints()
        second:SetPoint("RIGHT", cell, "RIGHT", 0, -2 * ROW.LIFT)
        -- Held inside its own column: "нет себестоимости" under YOU GET grew leftwards straight
        -- across "24 впереди" under the price (owner, ruRU, Forever beta 2026-10-01). The column
        -- itself is sized to fit its longest second line (FIT.need), so nothing here is ever cut
        -- short -- the owner's rule is that text is read in full, never ended with "…". The stand
        -- line keeps its own width because its marks hang off its left edge; FIT.need leaves room
        -- for them.
        if second ~= row.priceStand then
          second:SetPoint("LEFT", cell, "LEFT", 0, -2 * ROW.LIFT)
        end
      end
      right, rightLift = cell, lift
      cell:Show()
    end
  end
  if row.standMarks then
    -- Chained leftwards from the words they belong to, so the pair stays together however long
    -- the count beside them grows.
    local anchor = row.priceStand
    for i = #row.standMarks, 1, -1 do
      local mark = row.standMarks[i]
      mark:ClearAllPoints()
      mark:SetPoint("RIGHT", anchor, "LEFT", anchor == row.priceStand and -5 or -2, 0)
      anchor = mark
    end
  end
  for _, column in ipairs(COLUMNS) do
    if dropped[column.key] then row.cells[column.key]:Hide() end
  end
end

-- Keyed by the label the button currently carries. Every one of these either spends gold or
-- destroys a deposit, so none of them should be a word a player has to guess at.
--
-- English here on purpose, and translated where it is READ (actionHelp below). This table
-- is built at file scope, and GC.L only resolves once ApplyLocale has run at ADDON_LOADED
-- -- so GC.L[...] in these entries would capture the English fallback once and stay English
-- in every language. The outer KEYS stay English for a different reason: they are the
-- stable helpKey the buttons carry, which is the defect helpKey was introduced to fix.
-- @localised-keys: literals in this table ARE GC.L keys; see the comment above for why
-- the lookup happens where the table is read rather than where it is built.
local ACTION_HELP = {
  ["Set cost"] = { "Set cost", { "Tell GoldCap what you actually paid for these units.", "It will not invent a cost from the market price, so profit stays unknown until you enter one." } },
  -- Two short paragraphs each, never more (sell_action_help_spec locks the length): the
  -- tooltip opens beside a button inside the list, so every extra line is a row it covers.
  ["Post"] = { "Post", { "Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item.", "The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price." } },
  ["Cancel lot"] = { "Cancel lot", { "Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive.", "Asks for a second click to confirm." } },
  ["Cancel lot?"] = { "Confirm the cancel", { "Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags.", "The button waits a moment before it can be pressed, so this is never an accidental double-click." } },
  ["Remove"] = { "Remove this cost", { "Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail.", "There is no undo. Clicking asks for a second click to confirm." } },
  ["Remove?"] = { "Confirm the removal", { "Clicking again deletes this hand-entered cost for good.", "A run of several purchases collapsed onto one line removes every one of them." } },
}
UI.Row.ACTION_HELP = ACTION_HELP

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(UI.rowHeight)

  -- Sell rows carried no banding, no hover feedback and no rule between them, so a screenful
  -- of positions read as one undifferentiated block -- and an expanded position's children were
  -- distinguishable only by two leading spaces in their text. Same treatment as the Deals list:
  -- BACKGROUND zebra, a highlight above it, a hairline at the bottom edge, and an item icon so
  -- rows are scannable by shape rather than by reading every name.
  -- Sliced rounded fills (batch-2 pattern). Insets: 1px top/bottom so margin 12 <= 15 = half of
  -- the 30px effective fill (Theme.ROW_H 32 minus 2px); right inset is 2, NOT Deals' 26 -- this
  -- container is already inset by CONTENT_RIGHT_GUTTER (see Attach) and the scrollbar hangs
  -- outside in that gutter.
  local zc = Theme.color.zebra
  row.zebra = row:CreateTexture(nil, "BACKGROUND")
  row.zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  row.zebra:SetTextureSliceMargins(12, 12, 12, 12)
  row.zebra:SetPoint("TOPLEFT", 2, -1); row.zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], 0)
  -- The open position's outline, over the same rect as its fill: gold at the design's 38%.
  -- Built through the kit's own sliced texture so a spec's Theme double serves it too.
  row.selectRing = Theme.SlicedTexture(row, "BORDER", Theme.MEDIA .. "plaque_ring.png",
    { Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.38 }, 12)
  row.selectRing:SetPoint("TOPLEFT", 2, -1); row.selectRing:SetPoint("BOTTOMRIGHT", -2, 1)
  row.selectRing:Hide()
  -- The "well": a sunken fill an expanded position's children sit in instead of the list's
  -- alternating zebra, so a sub-row reads as nested inside its position rather than as one more
  -- row in the same flat list (row.spine, below, is the other half of that cue). Same sliced
  -- plaque and insets as the zebra it replaces -- only shown for sub-rows (the kind branch in
  -- renderRows), never alongside it.
  row.well = row:CreateTexture(nil, "BACKGROUND")
  row.well:SetTexture(Theme.MEDIA .. "plaque.png")
  row.well:SetTextureSliceMargins(12, 12, 12, 12)
  row.well:SetPoint("TOPLEFT", 2, -1); row.well:SetPoint("BOTTOMRIGHT", -2, 1)
  local phc = Theme.color.panelHi
  row.well:SetVertexColor(phc[1], phc[2], phc[3], 0.5)
  row.well:Hide()
  row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  row.highlight:SetTextureSliceMargins(12, 12, 12, 12)
  row.highlight:SetPoint("TOPLEFT", 2, -1); row.highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  local hc = Theme.color.hover
  row.highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight:Hide()
  row.divider = row:CreateTexture(nil, "ARTWORK")
  row.divider:SetHeight(1)
  row.divider:SetPoint("BOTTOMLEFT", 0, 0)
  row.divider:SetPoint("BOTTOMRIGHT", 0, 0)
  local bc = Theme.color.border
  row.divider:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.06)
  -- Child rows (batch/detail/lot) get a gold spine at the left edge instead of a bottom rule,
  -- so an expanded group reads as one bracketed unit rather than as more top-level rows.
  row.spine = row:CreateTexture(nil, "ARTWORK")
  row.spine:SetWidth(2)
  row.spine:SetPoint("TOPLEFT", 0, 0)
  row.spine:SetPoint("BOTTOMLEFT", 0, 0)
  local gc = Theme.color.gold
  row.spine:SetColorTexture(gc[1], gc[2], gc[3], 0.45)
  row.spine:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW.ICON, ROW.ICON)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the stock icon border
  row.icon:Hide()
  row:SetScript("OnEnter", function(self)
    self.goldcapVariant = nil
    -- The list's rows are what a hover picks between; a wash over the panel's twelve-slot
    -- head, or over a heading inside it, points at nothing.
    if not self.inPanel then self.highlight:Show() end
    -- Rows are pooled and rebound every render, so the item tooltip is wired once here and
    -- reads whatever position the row currently holds. Hooking it per render would stack.
    if GameTooltip and self.kind == "position" and self.position and self.position.itemID then
      -- Outside the window, never over it -- a row's own item tooltip used to cover the deck
      -- it is describing (Theme.ItemTooltipOutside; see UI/Theme.lua's own comment on it).
      Theme.ItemTooltipOutside(self, UI.window)
      -- A variant is the stack itself -- its item level, its bonuses, its pet -- not the base item
      -- (for every caged pet, "Pet Cage"): the bag slot, else the lot's own link (review M9).
      -- GoldCap's own block under this tooltip (UI/Tooltip.lua) reads the site's figure for the
      -- item -- every item level at once, every pet at once. Under a variant row it says there is
      -- none for this one instead (review N7), reading which variant off the tooltip's owner --
      -- this row -- so it can never outlive the row onto some other item's tooltip (NI-B).
      self.goldcapVariant = self.position.variantKind
      local stack = self.position.quoteKey and self.position.bagStacks and self.position.bagStacks[1]
      local lot = self.position.quoteKey and self.position.ownedLots and self.position.ownedLots[1]
      if stack and GameTooltip.SetBagItem then GameTooltip:SetBagItem(stack.bag, stack.slot)
      elseif lot and lot.itemLink and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(lot.itemLink)
      elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.position.itemID) end
      -- Flags painted onto the row at the same time as the cells they describe (MARKET/UNIT's
      -- fallback, the item cell's "· not on hand" suffix) -- read here rather than re-derived,
      -- so the tooltip can never disagree with what the row is actually showing.
      if self.marketFallback then
        GameTooltip:AddLine(GC.Util.ClientText(GC.L["~ goldcap.gg market value — no live quote yet"]), 0.85, 0.85, 0.85, true)
      end
      if self.notOnHand then
        GameTooltip:AddLine(GC.Util.ClientText(GC.L["Not on hand — the stock is in the mail, the bank, or on another character"]),
          0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    elseif GameTooltip and (self.kind == "group" or self.kind == "batch")
        and self.groupHint and self.groupHint ~= "" then
      GameTooltip:SetOwner(self, Theme.TooltipAnchor(self))
      -- A fact a line. The sentence is a run of facts joined by one separator, and wrapped as
      -- a paragraph it broke mid-fact ("bought 29 / Aug"), which is harder to read than the row.
      local first = true
      for fact in (self.groupHint .. " · "):gmatch("(.-) · ") do
        local factLine = GC.Util.ClientText(fact)
        if first then GameTooltip:AddLine(factLine, 1, 1, 1) else GameTooltip:AddLine(factLine, 0.85, 0.85, 0.85) end
        first = false
      end
      GameTooltip:Show()
    end
  end)
  -- Belt and braces: a row hidden under a stationary cursor (Escape, the auction house closing,
  -- a re-render) never gets its OnLeave.
  row:SetScript("OnHide", function(self) self.goldcapVariant = nil end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    self.goldcapVariant = nil
    -- GameTooltip_Hide closes Blizzard's battle-pet card too, which a caged pet's bag slot or
    -- link may open beside GameTooltip (review N5).
    if _G.GameTooltip_Hide then _G.GameTooltip_Hide()
    elseif GameTooltip then GameTooltip:Hide() end
  end)

  row.cells = {}
  for _, column in ipairs(COLUMNS) do
    -- Figures in the mono face, names and prose in the client's own -- the kit's rule (see
    -- Theme.Label). Every cell here used to be a Label, so the two columns a seller compares
    -- down the list were set in a face whose digits do not line up.
    local cell = column.num and Theme.Num(row, 11, column.bold) or Theme.Label(row, column.key == "item" and 12 or 11)
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    cell:SetWordWrap(false)
    row.cells[column.key] = cell
  end
  row.cells.item:SetJustifyH("LEFT")
  -- The stock line ("×246 in bags · ×11 listed") used to ride in cells.item as a second line
  -- behind a "\n". cells.item is SetWordWrap(false) like every other cell, which renders ONE
  -- line and marks the rest with an ellipsis -- so the second line was never drawn at all and
  -- every item on the screen appeared truncated, whatever its name. Its own FontString, its
  -- own anchor (layoutCells splits the flex box in half vertically for the pair).
  row.itemStock = Theme.Num(row, 10)
  -- Said out loud rather than inherited from the font template: this line is deliberately one
  -- step back from the item name above it, so that the money coloured into it (MONEY_HEX) is
  -- the thing that steps forward. Leaving it on the template's own colour made the whole line
  -- compete with the name and the cost compete with nothing.
  row.itemStock:SetTextColor(Theme.color.fgMuted[1], Theme.color.fgMuted[2], Theme.color.fgMuted[3])
  row.itemStock:SetJustifyH("LEFT")
  row.itemStock:SetWordWrap(false)
  row.itemStock:Hide()

  -- The second line of the two figures, the same split the name and its stock line already
  -- make. Under the price: where that price stands in the live book -- five marks, one per
  -- price level from the cheapest, the one this price lands on lit -- and the stock queued
  -- under it in words. Under YOU GET: the margin, which used to be a column of its own a row's
  -- width away from the figure it qualifies. Both answer before anything is opened.
  row.priceStand = Theme.Num(row, 10)
  row.priceStand:SetJustifyH("RIGHT")
  row.priceStand:SetWordWrap(false)
  row.priceStand:Hide()
  row.standMarks = {}
  for i = 1, ROW.MARKS do
    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetSize(3, 8)
    mark:Hide()
    row.standMarks[i] = mark
  end
  -- 11, the size of the figure above it: at 9 the one number that says whether the row makes
  -- or loses money was the smallest thing on it.
  row.grossNote = Theme.Num(row, 11)
  row.grossNote:SetJustifyH("RIGHT")
  row.grossNote:SetWordWrap(false)
  row.grossNote:Hide()

  UI.Book.Decorate(row)

  UI.Inspector.Decorate(row)
  -- Sub-rows (detail/batch/lot/listing) write into their own widget, one size down from a
  -- position's name (11, not 12) -- the flex column's box is shared by three mutually
  -- exclusive widgets (this, row.cells.item, row.sectionLabel below), and layoutCells anchors
  -- all three to the same LEFT/RIGHT points every render since exactly one is shown per row
  -- (the kind branch in renderRows).
  row.subItem = Theme.Num(row, 10)
  row.subItem:SetJustifyH("LEFT")
  row.subItem:SetWordWrap(false)
  row.subItem:Hide()
  -- Group headings (Sold's own pattern, UI/SoldFrame.lua's row.sectionLabel/row.sectionRule):
  -- a mono micro-label plus a hairline rule running to the row's right edge, instead of a
  -- gold line sharing the item cell's own font -- gold and uppercase are the group's whole
  -- visual language, so nothing about the flex column's shared styling has to bend for it.
  row.sectionLabel = Theme.Num(row, 9, true)
  row.sectionLabel:SetJustifyH("LEFT")
  setColor(row.sectionLabel, Theme.color.gold)
  row.sectionLabel:Hide()
  -- A heading's aside, at the right end of its row ("oldest units sell first").
  row.sectionHint = Theme.Num(row, 9)
  row.sectionHint:SetJustifyH("RIGHT")
  row.sectionHint:SetWordWrap(false)
  setColor(row.sectionHint, Theme.color.fgDim)
  row.sectionHint:Hide()
  local gc2 = Theme.color.gold
  row.sectionRule = row:CreateTexture(nil, "ARTWORK")
  row.sectionRule:SetColorTexture(gc2[1], gc2[2], gc2[3], 0.25)
  row.sectionRule:SetHeight(1)
  row.sectionRule:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.s, 0)
  row.sectionRule:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
  row.sectionRule:Hide()
  row.action = Theme.Button(row, "ghost", "badge")
  -- 86, not 84: "Cancel lot?" is 85.8px at mono-10 and Theme.Scale() 1.3 (JetBrains Mono
  -- ~0.6em/char -> 7.8px/char); 86 is the largest width that still leaves >=2px clearance
  -- from the neighbouring cells inside the 88px `action` column (layoutCells packs cells with
  -- an explicit 2px gap between them, so an inset button never touches the gap).
  row.action:SetSize(86, 18)
  -- Its own column. Anchored over `status` it covered the recommendation text, which is where
  -- the price and the breakeven are written.
  row.action:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  row.action:Hide()
  -- Wired once on the pooled button; the text is chosen at hover time from the label it
  -- currently carries, so it always describes the action actually on offer.
  if row.action.HookScript then
    row.action:HookScript("OnEnter", function(self)
      if not GameTooltip then return end
      -- helpKey is the English action name the row set; self.label is display text and may be
      -- in any language. Fall back to the label for buttons that predate the key.
      local help = ACTION_HELP[self.helpKey or ""]
        or ACTION_HELP[self.label]
        or ACTION_HELP[(self.label or ""):gsub("%s*%(.*", "")]
      if not help then return end
      -- Not ANCHOR_RIGHT: this button sits in the far-right column of a window that can fill
      -- the screen, and a tooltip told to grow rightward from there gets clamped back over the
      -- list, the header and the button itself. Theme reads where the button is and opens the
      -- tooltip on the side that has room.
      GameTooltip:SetOwner(self, Theme.TooltipAnchor(self))
      -- Translated at READ time -- see ACTION_HELP's own comment for why the table itself
      -- cannot hold GC.L lookups.
      GameTooltip:AddLine(GC.Util.ClientText(GC.L[help[1]]), 1, 0.82, 0)
      for _, line in ipairs(help[2]) do
        GameTooltip:AddLine(GC.Util.ClientText(GC.L[line]), 0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    end)
    row.action:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  row:SetScript("OnClick", function(self)
    if self.kind == "fold" then
      UI.showNotOnHand = not UI.showNotOnHand
      renderRows()
    elseif self.kind == "position" and type(self.position.positionKey) == "string" then
      Post.WalkAway() -- an armed post or cancel is a question; this click answers it "no"
      -- One open position at a time. Two open panels are two hundred pixels of detail each,
      -- and the second one pushed the first -- the one being compared against -- off screen.
      local key = self.position.positionKey
      local wasOpen = UI.expanded[key]
      for other in pairs(UI.expanded) do UI.expanded[other] = nil end
      UI.expanded[key] = not wasOpen or nil
      renderRows()
    end
  end)
  return row
end

-- Explanatory tooltip on any frame. Guarded for busted, where no WoW globals exist.
local function explain(frame, title, body)
  if not frame or not frame.SetScript then return end
  -- HookScript, never SetScript: Theme.Button owns OnEnter/OnLeave for its hover fill, and
  -- replacing those would leave buttons stuck in whichever state they were painted in.
  local hook = frame.HookScript and "HookScript" or "SetScript"
  frame[hook](frame, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GC.Util.ClientText(title), 1, 0.82, 0)
    for _, line in ipairs(body) do GameTooltip:AddLine(GC.Util.ClientText(line), 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  frame[hook](frame, "OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
end

-- @localised-keys: literals in this table ARE GC.L keys, looked up where the table is
-- READ, not here. This is file scope, and GC.L only resolves once ApplyLocale has run
-- at ADDON_LOADED -- a lookup here captures the English fallback and keeps it in every
-- language. The table has to close with a `}` on its own line: that is where the
-- contract spec's scanner stops.
local HEADER_HELP = {
  cost = { "Cost per unit", { "What one of these actually cost you, averaged over the purchases still on hand.", "A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price." } },
  listed = { "Listed value", { "What your live auctions for this item add up to at their current asking price." } },
  market = { "Market per unit", {
    "The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards.",
    "It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at.",
    "Greyed out means the quote has aged; Post and Repost refresh it before they act." } },
  profit = { "Profit per unit", { "What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost.", "Unknown means the cost side is incomplete -- fill it in with Set cost." } },
  status = { "What to do", { "GoldCap's suggestion for this item, and the price it would use.", "Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money." } },
}
UI.List.HEADER_HELP = HEADER_HELP

-- `key` is the ENGLISH action name, not display text. ACTION_HELP is keyed by it, so once the
-- interface is translated a lookup by the visible label would miss every time and silently
-- drop the help from exactly the buttons that spend gold. The key is remembered on the button;
-- the label is only what the player reads.
local function showRowAction(row, key, onClick)
  -- Deliberately does NOT clear `status` any more: that cell holds the recommendation -- what
  -- to do, at what unit price, and the breakeven under it -- and blanking it was the reason a
  -- player could never tell what a Post or Repost was about to charge.
  row.action.helpKey = key
  row.action:SetLabel(GC.L[key])
  if onClick then row.action:SetScript("OnClick", onClick) end
  row.action:Show()
end
UI.Row.ShowRowAction = showRowAction

local function summaryFor(filtered)
  local partial, unknown, knownCost, listedValue = 0, 0, 0, 0
  for _, position in ipairs(filtered) do
    if position.coverage == "PARTIAL" then partial = partial + 1 end
    if position.coverage == "UNKNOWN" then unknown = unknown + 1 end
    if not exact(position.knownCost) then knownCost = nil
    elseif knownCost ~= nil then knownCost = safeAdd(knownCost, position.knownCost) end
    if not exact(position.listedValue) then listedValue = nil
    elseif listedValue ~= nil then listedValue = safeAdd(listedValue, position.listedValue) end
  end
  local raw = GC.SellPositions.Summary(filtered)
  return GC.SellViewModel.SummaryText({ knownCost = raw.invested or knownCost,
    listedValue = raw.listedValue or listedValue,
    profit = raw.profit, partialCount = partial, unknownCount = unknown,
    countedCount = raw.countedCount, excludedNoCost = raw.excludedNoCost, excludedNoPrice = raw.excludedNoPrice })
end

local function updateSummary(filtered)
  local text = summaryFor(filtered)
  UI.container.summary.cost:SetText(formatCell(text.knownCost))
  UI.container.summary.listed:SetText(formatCell(text.listedValue))
  if type(text.profit) == "number" then
    -- Item 2 (addon polish batch): the number is a sum over only the positions that
    -- individually cleared both gates, so it can still be a partial total -- the card's own
    -- hit frame (below) shows the detail on hover, but a player who never hovers must not read
    -- a partial sum as the whole picture. profitMarker carries that onto the number itself.
    UI.container.summary.profit:SetText(GC.Sell._FormatAmount(text.profit) .. (text.profitMarker or ""))
    UI.container.summaryProfitDetail = text.profitDetail
  else
    -- SellViewModel.SummaryText's non-number reads "Unknown" or "Unknown · 12 partial · 37
    -- missing" -- at Theme.Scale() 1.3 the longer form doesn't fit the mono value line, so the
    -- card itself stays a plain "Unknown" and everything after the first " · " moves to
    -- summaryProfitHit's own tooltip (see the stat-card loop below), read live at hover time.
    UI.container.summary.profit:SetText(GC.L["Unknown"])
    local sepStart, sepEnd = text.profit:find(" · ", 1, true)
    UI.container.summaryProfitDetail = sepStart and text.profit:sub(sepEnd + 1) or nil
  end
  -- A non-number here is an absence, not a result: painting "Unknown" in the same confident
  -- green as a real profit read as a figure the addon stood behind.
  setColor(UI.container.summary.profit, type(text.profit) == "number"
    and (text.profit < 0 and Theme.color.red or Theme.color.green) or Theme.color.fgDim)
end

renderRows = function()
  if not UI.container then return end
  -- The Sell CONTENT may be attached but not the tab currently on screen -- Compose.Positions()
  -- and GC.Sell.Refresh() run regardless of which tab is active (bag counts and the tab badge
  -- must stay current either way), and that used to rebuild every visible row along with them:
  -- dragging the window's resize grip alone re-ran this at up to 60fps, and every quote landing
  -- during a background pricing walk re-ran it again, whether or not anyone could see the
  -- result. Defer instead, the same way an armed post/repost already defers below --
  -- GC.Sell.Show() reveals the container and then unconditionally calls Refresh(), which is
  -- what actually flushes this: the very next render it triggers runs for real once
  -- Walk.Shown() is true again, so nothing needs a second explicit flush call here.
  if not Walk.Shown() then
    S.deferredRender = true
    return
  end
  -- A post or repost that is armed is waiting on the player's confirming click,
  -- and the pin proving that click belongs to it is bound to a pooled row. A
  -- render rebinds those rows, so this used to answer by CANCELLING the
  -- confirmation the player was one click away from giving. That was already
  -- wrong; the tab now re-prices itself every few seconds, which made it certain.
  -- Hold the render instead. Every arm is timeout-bounded, so it cannot be held
  -- indefinitely, and Post.DisarmPost/Post.DisarmRepost/Post.DisarmRemove flush whatever was
  -- deferred.
  if S.postingRow or S.repostingRow or S.removingRow then
    S.deferredRender = true
    return
  end
  S.deferredRender = false
  renderGeneration = renderGeneration + 1
  -- One read of the bags for this whole pass (see GC.Sell._BagSnapshot); a local, so it dies with it.
  local bagSnapshot = GC.Sell._BagSnapshot()
  -- The two decks carry DIFFERENT column sets, so the heading row has to be re-laid out when
  -- the deck changes -- rows are laid out on every render (below) but the header is built once.
  -- Done here rather than in the deck buttons' own handler because filterMode also moves
  -- underneath us: onCancelQueueClick sets "cancelqueue", which is the listed deck, and
  -- onQueueClick sets "queue", which is the post one. Every path that can change the deck ends
  -- up here, so this is the one place that cannot be forgotten.
  local headerDeck = (S.filterMode == "listed" or S.filterMode == "cancelqueue") and "listed" or "post"
  if UI.container and UI.container.header and UI.container.headerDeck ~= headerDeck then
    UI.container.headerDeck = headerDeck
    paintHeaderText(UI.container.header, headerDeck)
    layoutCells(UI.container.header)
  end
  local filtered
  if S.filterMode == "queue" then
    -- The queue's own order, head first -- deliberately NOT SellViewModel.Order, which ranks
    -- by a different question ("what could I act on, roughly") than GC.PostQueue.Build's "what
    -- is most valuable to post right now, in a stable order." See PostQueue.lua's own
    -- entryLess. Every entry maps back to its live position object -- the queue itself carries
    -- only display figures, never a second copy of the position -- so the row this produces is
    -- the exact same row a normal filter chip would have rendered for that position.
    filtered = {}
    for _, entry in ipairs(S.queueEntries) do
      local position = currentPosition(entry.positionKey)
      if position then filtered[#filtered + 1] = position end
    end
  elseif S.filterMode == "cancelqueue" then
    -- The cancel queue's own order, head first -- one row per position however many of its
    -- lots are queued; the queued lots themselves render through the position's expansion,
    -- which is where the Repost/Cancel action a click needs actually lives.
    filtered = {}
    local seen = {}
    for _, entry in ipairs(S.cancelEntries) do
      if not seen[entry.positionKey] then
        seen[entry.positionKey] = true
        local position = currentPosition(entry.positionKey)
        if position then filtered[#filtered + 1] = position end
      end
    end
  else
    -- Deck ends in SellViewModel.Order itself, so there is no second ordering pass here the
    -- way the old single-filter path needed one.
    filtered = GC.SellViewModel.Deck(S.positions, S.filterMode,
      { ready = UI.chips.ready, noCost = UI.chips.nocost })
    -- Deck ends in Order, which is the right answer for a list being BUILT and the wrong one
    -- for a list already on screen: the pricing walk answers one item at a time, and every
    -- answer re-ranked a row out from under the cursor.
    filtered = GC.SellViewModel.Settle(filtered, S.rowPlaces)
  end
  -- MY LOTS reads in three sections (SellViewModel.LotSections); the queue's own focus state
  -- keeps the queue's order, which is the point of it.
  local sectionOf
  if S.filterMode == "listed" then filtered, sectionOf = ROW.bySection(filtered) end
  updateSummary(filtered)
  -- Why a row is not in the bulk action, by position, for the tag on its stock line. Read off
  -- the same two skip lists the footer's held-back counter reads, so the row and the counter
  -- can never disagree about what was left out.
  local heldBackReason = {}
  local onListed = S.filterMode == "listed" or S.filterMode == "cancelqueue"
  for _, skip in ipairs(onListed and S.cancelSkipped or S.queueSkipped) do
    if type(skip.positionKey) == "string" then heldBackReason[skip.positionKey] = skip.reason end
  end
  local entries = {}
  -- Stock that is neither in the bags nor listed is cost history, not work: it sits at the
  -- bottom of the posting deck folded under one heading, so the rows a seller acts on are not
  -- followed by a tail of rows they cannot. NO COST opens it by itself -- those positions are
  -- most of what that chip exists to find, and Set cost lives on their rows.
  local folded = {}
  -- The position whose detail panel is open, if it is on this deck at all: a deck change or a
  -- chip can take the row away, and a panel describing a row that is not there shuts.
  local openPosition
  local function pushPosition(position)
    entries[#entries + 1] = { kind = "position", position = position }
    -- Cached here for every position this render pushes, not only an expanded one: the row's own
    -- Post button (below, "bagQty > 0 and not onListed") is live whether or not the drawer is
    -- open, and onPostClick never builds an ItemLocation itself -- see cacheBagLocation's own
    -- comment above Bags.LiveState.
    if (position.bagQty or 0) > 0 then
      GC.Sell._CacheBagLocation(position, Bags.LiveState(position, nil, bagSnapshot))
    end
    if UI.expanded[position.positionKey] and not openPosition then
      openPosition = position
      local first = #entries + 1
      local detail = GC.SellViewModel.Expansion(position)
      -- ONE panel where this used to spend eleven separate 32px rows: the facts line, the
      -- price control, the book heading and eight levels. Opening a position buried the list
      -- it was opened from -- 25 rows of expansion inside a 430px scroll area -- which is the
      -- single complaint this redesign started from.
      entries[#entries + 1] = { kind = "drawer", position = position, detail = detail,
        -- Without a book the eight levels are not drawn, and neither is the room for them: the
        -- head used to keep 160px of nothing between its heading and "has not answered yet".
        slots = ((position.bagQty or 0) > 0 and DR.SLOTS or DR.SLOTS_BARE) - (detail.book and 0 or DR.NO_BOOK_SLOTS)
          - (((position.bagQty or 0) > 0 and not detail.factsText) and DR.NO_REASON_SLOTS or 0) }
      local head = table.remove(entries)
      -- What you are selling comes before what you paid: the listings are the thing a player
      -- acts on, the purchase history is only there to justify the cost number.
      local inBags = position.bagQty or 0
      -- The bag line earns its row when it says something the panel's heading ("x37 in bags")
      -- does not: that one click lists only part of the stock, that no stack can be pinned
      -- down, or that some of it has no cost and can be given one here.
      local bagState = inBags > 0 and Bags.LiveState(position, nil, bagSnapshot) or nil
      GC.Sell._CacheBagLocation(position, bagState)
      local postableNow = bagState and bagState.bag and exact(bagState.exactQty) and bagState.exactQty or 0
      local bagLine = inBags > 0 and (postableNow ~= inBags or UI.CostDialog.CanSetCost(position))
      -- On MY LOTS the lots ARE the subject, so they open the panel -- each with its own
      -- Cancel lot -- and the book follows as the evidence. On the posting deck the price
      -- control is the subject and the lots come after it, as before.
      if not onListed then entries[#entries + 1] = head end
      if #detail.ownedLots > 0 or bagLine then
        entries[#entries + 1] = { kind = "group", position = position,
          title = onListed and GC.L["YOUR LOTS"] or GC.L["ON THE AUCTION HOUSE"],
          aside = onListed and ROW.lotsAside(position) or nil }
      end
      for _, lot in ipairs(detail.ownedLots) do entries[#entries + 1] = { kind = "lot", position = position, lot = lot } end
      if bagLine then
        entries[#entries + 1] = { kind = "listing", position = position }
      end
      if onListed then entries[#entries + 1] = head end
      if #detail.batches > 0 then
        entries[#entries + 1] = { kind = "group", position = position, title = GC.L["WHAT YOU PAID"],
          hint = GC.L["Sales are costed from your oldest units first"],
          aside = GC.L["oldest units sell first"] }
      end
      for _, batch in ipairs(detail.batches) do entries[#entries + 1] = { kind = "batch", position = position, batch = batch } end
      -- Everything a position opens into is drawn in the side panel, not under the row. The
      -- entries keep their place in this one list -- and so their pooled rows and every pin a
      -- post or a cancel holds on one -- and only say where they are to be laid out.
      for index = first, #entries do entries[index].panel = true end
    end
  end
  for _, position in ipairs(filtered) do
    local notOnHand = S.filterMode == "post" and not position.unresolved
      and (position.bagQty or 0) == 0 and (position.listedQty or 0) == 0
    -- The search narrows what is DRAWN, after the ledger has been summed: the dock's totals
    -- are the deck's, and would otherwise jump about under every keystroke. Plain substring,
    -- lower-cased -- which folds ASCII only, so a Cyrillic name matches in the case it is
    -- written in; the client's Lua has no way to fold the rest.
    local name = type(position.itemName) == "string" and position.itemName:lower() or ""
    local matches = not UI.chips.search or name:find(UI.chips.search, 1, true) ~= nil
    if matches and notOnHand then folded[#folded + 1] = position
    elseif matches then
      -- A heading goes in ahead of the first of its positions that is actually drawn, so a
      -- search that empties a section takes its heading with it.
      local section = sectionOf and sectionOf[position]
      if section and not section.headed then
        section.headed = true
        entries[#entries + 1] = { kind = "section", position = position, section = section }
      end
      pushPosition(position)
    end
  end
  -- Only a TAIL is folded. When nothing on the deck is on hand there is no work for the fold to
  -- keep clear, and hiding the only rows there are would leave a heading over an empty list.
  if #folded > 0 and #entries == 0 then
    for _, position in ipairs(folded) do pushPosition(position) end
  elseif #folded > 0 then
    local open = UI.showNotOnHand or UI.chips.nocost
    entries[#entries + 1] = { kind = "fold", position = folded[1], count = #folded, open = open }
    if open then
      for _, position in ipairs(folded) do pushPosition(position) end
    end
  end
  if S.filterMode == "post" then ROW.pushWaiting(entries) end
  if #entries == 0 then
    -- M7: sentence case, not shouted -- this is a native-font (Theme.Label) empty state, like
    -- Deals', and reads like the rest of that font's copy rather than a toolbar label.
    -- Say which of the three reasons it is, because they need different next moves: a deck
    -- that is genuinely empty, versus a chip that emptied it, versus the other deck holding
    -- everything. "No items match this filter" answered none of them.
    UI.container.emptyText:SetText(GC.Sell._EmptyDeckText())
    UI.container.emptyText:Show()
  else
    UI.container.emptyText:Hide()
  end
  for i = #UI.rows + 1, #entries do UI.rows[i] = createRow(UI.content) end
  -- Known before any row is laid out: a docked panel takes its width out of the list's, and
  -- shownColumns reads that. The heading row and the scroll area follow whenever it changes.
  INSP.sync(openPosition ~= nil)
  -- Running Y for the loop below, one per surface. Rows are pooled and re-anchored on every
  -- render, so both are rebuilt from scratch each time rather than remembered.
  local placedHeight, detailHeight, listIndex = 0, 0, 0
  for i, row in ipairs(UI.rows) do
    local entry = entries[i]
    if not entry then row.renderEntryID = nil; row:Hide()
    else
      -- One pool, two surfaces. A row is re-parented only when its entry moves between them,
      -- which a position being opened or shut does and a re-price never does -- so the price
      -- box a seller is typing into is not touched by the renders their typing causes.
      local surface = entry.panel and UI.detailContent or UI.content
      row.inPanel = entry.panel == true
      if surface and row.surface ~= surface then
        row.surface = surface
        if row.SetParent then row:SetParent(surface) end
      end
      -- Slot-based placement, not a fixed pitch off the index: an entry may claim several
      -- ROW_HEIGHT slots (entry.slots) so that one row can be a PANEL instead of a line. Every
      -- entry that does not ask for slots claims exactly one, which is the old arithmetic
      -- (offset == (i - 1) * ROW_HEIGHT) reproduced exactly -- so nothing but the drawer moves.
      local slots = entry.slots or 1
      local offset = entry.panel and detailHeight or placedHeight
      row:Show(); row:ClearAllPoints()
      row:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, -offset); row:SetPoint("TOPRIGHT", surface, "TOPRIGHT", 0, -offset)
      -- A position in the list is ROW.H tall; everything else keeps the slot pitch.
      local height = (entry.kind == "position" and not entry.panel) and ROW.H or slots * UI.rowHeight
      row:SetHeight(height)
      if entry.panel then detailHeight = detailHeight + height
      else placedHeight = placedHeight + height; listIndex = listIndex + 1 end
      row.kind, row.position, row.batch, row.lot = entry.kind, entry.position, entry.batch, entry.lot
      -- Read by this row's own OnEnter (below) to decide whether to add a tooltip line about the
      -- number this row is showing. Reset for every kind, not just "position": rows are pooled
      -- and rebound, so a flag left set from an earlier position would otherwise ride along onto
      -- an unrelated expansion sub-row.
      row.marketFallback, row.notOnHand, row.groupHint = false, false, nil
      local p = entry.position
      local lotID = entry.lot and entry.lot.auctionID or 0
      row.renderEntryID = table.concat({ renderGeneration, i, entry.kind, p.scopeKey or "", p.positionKey or "", lotID }, ":")
      -- Every cell starts empty, whatever kind takes this pooled row next, so a branch only
      -- has to write what it actually shows. Enumerating the clears per branch is what leaked
      -- YOU GET / PRICE / MARGIN onto lot and batch sub-rows: those lists were written before
      -- the columns existed, and nothing made anybody update them.
      for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
      if entry.kind == "position" then
        -- Second line answers "how many of these do I have, and where are they" -- the question
        -- a seller actually asks. Where each unit came from stays available on the tooltip.
        -- The bag count is now measured, not inferred. It used to be tracked
        -- minus listed -- an accounting leftover that announced stock as "in
        -- your bags" whenever GoldCap had not seen one of the player's own
        -- auctions, and that showed nothing at all for anything GoldCap never
        -- bought, which was most of what a seller actually has to sell.
        local listedQty, bagQty = p.listedQty or 0, p.bagQty or 0
        local stockParts = {}
        if bagQty > 0 then stockParts[#stockParts + 1] = (GC.L["×%d in bags"]):format(bagQty) end
        if listedQty > 0 then stockParts[#stockParts + 1] = ROW.listedText(p, listedQty, onListed) end
        -- What one of these cost, on the line under the name. COST / UNIT was its own column
        -- until this deck's column set replaced it; the fact is too load-bearing to lose with
        -- the column, and it reads better beside the quantity it applies to anyway.
        local paidUnit = nil
        if p.coverage == "COMPLETE" and exact(p.knownCost) and exact(p.knownQty) and p.knownQty > 0 then
          paidUnit = math.floor(p.knownCost / p.knownQty)
          -- Escaped around the AMOUNT, not around the whole phrase: a translation is free to
          -- put the money anywhere in its own sentence, and only the money should light up.
          stockParts[#stockParts + 1] =
            (GC.L["paid %s each"]):format(MONEY_HEX .. formatCell(paidUnit) .. "|r")
        end
        -- The quality pip goes in the label rather than beside it: this row and
        -- the Sniper's deal row anchor their cells completely differently, and an
        -- inline atlas escape needs no layout in either. Empty for the vast
        -- majority of items, which have no quality tier at all.
        local named = Theme.WithQuality and Theme.WithQuality(p.itemName or "Item", p.itemID)
          or (p.itemName or "Item")
        -- Nothing in the bags and nothing listed means the stock this row tracks is real cost
        -- history sitting somewhere else -- the mail, the bank, another character -- not a
        -- position that vanished. The dim "· not on hand" suffix goes AFTER the qty suffix (or
        -- its SourceText fallback, when there is no qty to show), same idiom as SniperFrame's
        -- "· watching" suffix in setRowDeal, and its own color code so it never inherits
        -- whatever color the line before it painted.
        --
        -- Deliberately not queued into the pricing walk: Walk.Queue (above) only picks
        -- up a position with `inBags or listed`, so this row keeps whatever quote it already
        -- has (or none) and stays ranked last -- there is nothing actionable to price a quote
        -- for, and spending one of the walk's throttled requests on it would starve a row a
        -- player can actually act on right now.
        -- I2 (fix wave, sell honesty): an unresolved position (unassigned_acquisition/
        -- pending_purchase/paid_sale/ambiguous_sale, see Core/SellPositions.lua ~:579-616) has
        -- no batch or lot backing it at all -- there is no stock to be "elsewhere", so the
        -- mail/bank/alt claim below would be a fabrication about a position that is really
        -- "GoldCap doesn't know what this is yet". Mirrors the STATUS branch's own
        -- `not p.unresolved` guard further down.
        local notOnHand = not p.unresolved and (p.bagQty or 0) == 0 and (p.listedQty or 0) == 0
        row.notOnHand = notOnHand
        row.cells.item:SetText(named .. ROW.variantSuffix(p))
        -- What is off about this row, if anything -- see rowTag.
        row.itemStock:SetText((#stockParts > 0 and table.concat(stockParts, " · ")
          or GC.SellViewModel.SourceText(p))
          .. (notOnHand and (DIM_HEX .. " · not on hand|r") or "")
          .. rowTag(p, heldBackReason[p.positionKey], notOnHand))
        -- Cost per unit, not the position total: it is the number that compares against the
        -- market price in the very next column. An incomplete basis says so in words below.
        local unitCost = nil
        if p.coverage == "COMPLETE" and exact(p.knownCost) and exact(p.knownQty) and p.knownQty > 0 then
          unitCost = math.floor(p.knownCost / p.knownQty)
        end
        row.cells.cost:SetText(unitCost and formatCell(unitCost) or "—")
        row.cells.listed:SetText(formatCell(p.listedValue))
        -- "none" ~= "—": the first is an answer ("the AH has zero listings right now",
        -- remembered in emptyAnswers), the second is the absence of one. Conflating them made
        -- honestly-unlisted items read as the pricing walk being slow or stuck.
        --
        -- Below both of those sits a third case: no live quote yet AT ALL (not even a stale
        -- one), but the item was imported from goldcap.gg with a market value -- the same
        -- number Deals shows. That value is not live, so it never overrides an actual AH
        -- answer (an empty one included -- the AH answered "none", which outranks a guess from
        -- the last import), but showing it beats a "—" that reads as "the addon hasn't checked
        -- yet" for as long as the pricing walk takes to reach this row.
        -- Item 5 (addon polish batch): a bare `emptyAnswers[p.itemID]` presence check made a
        -- ONE-OFF empty AH answer hide the fallback forever -- only a manual Refresh (which
        -- wipes emptyAnswers outright) brought it back. Age-gate it the same way
        -- Walk.Queue already does for re-query eligibility, so a stale empty answer
        -- lets the fallback show again instead of only a fresh one suppressing it. While the
        -- walk is actively re-querying THIS exact item (refresh.pending, the walk's one
        -- in-flight slot), keep "none" rather than flicker the fallback in for the few seconds
        -- until the real (still probably empty) answer lands.
        --
        -- Fix wave: a request that never came back was recorded in emptyAnswers exactly like a
        -- reply that carried no listings, so an item the auction house had said nothing about
        -- at all rendered as "none" here and "Nothing listed on the AH right now" in STATUS.
        -- Only an ANSWER may drive that text now (emptyAnswers' own comment); silence falls
        -- back to the dash and "Waiting for a live price", which is what it is. The re-query
        -- guard keeps its job -- holding the last KNOWN-EMPTY answer on screen while the walk
        -- re-asks -- but it cannot invent one for an item that has never answered.
        -- By quote id: an item-level variant's answers are its own (GC.Sell._QuoteItemKey).
        local quoteID = p.quoteKey or p.itemID
        local answeredEmpty = Walk.RestedEmptyFresh(quoteID, time())
        local requeryingThis = S.refresh.pending and S.refresh.pending.itemID == quoteID
        local rest = S.emptyAnswers[quoteID]
        local emptyKnown = answeredEmpty
          or (requeryingThis and type(rest) == "table" and rest.answered == true) or false
        local marketFallback = p.displayMarketUnit == nil and type(p.marketValue) == "number"
          and p.marketValue > 0 and not emptyKnown
        row.marketFallback = marketFallback
        local marketText
        if p.displayMarketUnit then
          marketText = formatCell(p.displayMarketUnit)
        elseif marketFallback then
          -- "~", not "≈": on Korean this cell draws in the client's 2002.TTF, which has no U+2248.
          marketText = "~" .. formatCell(p.marketValue)
        else
          marketText = emptyKnown and "none" or "—"
        end
        if p.displayMarketUnit and not p.freshMarketUnit and type(p.quoteAge) == "number" then
          marketText = marketText .. (GC.L[" · stale %ds"]):format(p.quoteAge)
        end
        row.cells.market:SetText(marketText)
        setColor(row.cells.market, (marketFallback or (p.displayMarketUnit and not p.freshMarketUnit))
          and Theme.color.fgDim or Theme.color.fg)
        -- Per unit, to match the two columns it is compared against. The view model reports the
        -- position total; showing that under a "/ UNIT" heading turned a loss of under a gold
        -- per unit into a headline "-128g".
        local profit = GC.SellViewModel.ProfitText(p)
        if type(profit) == "number" and exact(p.knownQty) and p.knownQty > 0 then
          local perUnit = profit / p.knownQty
          profit = perUnit >= 0 and math.floor(perUnit) or -math.floor(-perUnit)
        end
        -- position.profitAtHold names the case where this number was computed at
        -- postRecommendation.unit and that unit sat ABOVE the fresh live quote (PostFloor, or
        -- the queue-at-exit rule, holding the recommendation above what a seller could actually
        -- get selling into today's book right now). The number itself stays the recommendation
        -- -- it IS the price GoldCap would post at -- but green would claim it as ordinary
        -- market profit when it is really a bet on the hold, so it renders in the same gold the
        -- MARKET/UNIT column already uses for a computed forward price (see the "→ <price>"
        -- cells below), with the price it assumes named in the cell rather than left implicit.
        -- A hold that is STILL a loss is not softened by the gold tone -- red outranks it.
        --
        -- setColor runs in BOTH branches, never just the hold one: rows are pooled and rebound
        -- to a new position on every render (renderRows reuses `rows[i]` rather than creating a
        -- fresh cell each time -- see createRow's own call site), so a row painted gold or red
        -- here on one render and left uncolored on the next would carry that tint into whatever
        -- unrelated number lands in the same slot afterward. Same failure class the addon's engineering notes
        -- already documents for hover fills painted in OnEnter and never cleared in OnLeave.
        if type(profit) == "number" and exact(p.profitAtHold) then
          -- Whole gold only: "@ 18g15s" was precisely the tail the column cut
          -- off in game. The exact figure is the Post price, one column over.
          -- GC.Util.IntText, not %d: WoW's own string.format raises "integer overflow
          -- attempting to store N" past +-2^31 copper (about 214,748g).
          local hold = p.profitAtHold >= 10000
            and GC.Util.IntText(math.floor(p.profitAtHold / 10000)) .. "g"
            or formatCell(p.profitAtHold)
          row.cells.profit:SetText(("%s %s@%s|r"):format(
            formatCell(profit), DIM_HEX, hold))
          setColor(row.cells.profit, profit < 0 and Theme.color.red or Theme.color.gold)
        else
          row.cells.profit:SetText(formatCell(profit))
          -- Minor (fix wave, sell honesty): "Unknown" beside a dim "~" market used to render in
          -- the row's ordinary fg -- a confident-looking pair next to an admittedly approximate
          -- number. Dim whenever there is no real number here; the gold/red hold-price branch
          -- above (a real number either way) is untouched.
          setColor(row.cells.profit, type(profit) == "number" and Theme.color.fg or Theme.color.fgDim)
        end
        -- "Unknown" (profit) sitting beside "UNLISTED" (status) read as one meaningless phrase.
        -- This column now says what to do about it, in a sentence, or names what is missing.
        local knownQty, exposureQty = p.knownQty or 0, p.exposureQty or 0
        if p.facts and p.facts.underpriced then
          -- Money leaving, silently. A listing posted against a thin cheap lot
          -- looks ordinary until that lot clears and the book springs back --
          -- which is how five Arcane Crystals bought at 70g ended up on sale at
          -- 18g against a 92g market. This is the one thing on the row that has
          -- to be read before anything else, so it takes the column and the
          -- alarm colour, and the advice moves aside for it.
          row.cells.status:SetText((GC.L["Listed at %s — far below market. Repost."]):format(
            formatCell(p.underpricedUnit)))
          setColor(row.cells.status, Theme.color.red)
        elseif p.recommendation then
          row.cells.status:SetText(GC.Sell._RecommendationText(p.recommendation))
          setColor(row.cells.status, Theme.color.fg)
        elseif bagQty > 0 then
          -- The advice column is not the place to report bookkeeping when the
          -- player is holding sellable stock: say what is missing to price it.
          -- "Waiting" when the answer already arrived and was "nothing on sale"
          -- is a lie that reads as the addon being slow -- name the real state.
          -- MINOR-1 (fix round 1): reuses the same age-gated `emptyKnown` the MARKET column
          -- decides its fallback from, above -- a bare `emptyAnswers[p.itemID]` here disagreed
          -- with MARKET once the answer went stale (MARKET said "~…", STATUS still said
          -- "Nothing listed").
          if p.displayMarketUnit == nil and emptyKnown then
            row.cells.status:SetText(GC.L["Nothing listed on the AH right now"])
          else
            row.cells.status:SetText(GC.L["Waiting for a live price"])
          end
          setColor(row.cells.status, Theme.color.fgDim)
        elseif not p.unresolved and (p.listedQty or 0) == 0 then
          -- Nothing in the bags AND nothing listed: the stock this row tracks is in the
          -- mail, the bank, or on another character. Cost coverage is a real question too,
          -- but "where is my ore?" is the one the player is actually asking here.
          row.cells.status:SetText(GC.L["Not in your bags or listed — mail or bank?"])
          setColor(row.cells.status, Theme.color.fgDim)
        elseif p.coverage ~= "COMPLETE" then
          row.cells.status:SetText((GC.L["Cost unknown for %d of %d"]):format(
            math.max(0, exposureQty - knownQty), exposureQty))
          setColor(row.cells.status, Theme.color.fgDim)
        else
          row.cells.status:SetText("")
          setColor(row.cells.status, Theme.color.fg)
        end
        -- The deck's own three figures. Written for BOTH decks and shown per DECK_COLUMNS, so
        -- a cell never carries a number belonging to the deck the player is not looking at.
        local onListedDeck = S.filterMode == "listed" or S.filterMode == "cancelqueue"
        local rowUnit
        if onListedDeck and listedQty > 0 and exact(p.listedValue) then
          -- The average a live lot is actually standing at, which is what "your price" means
          -- once it is posted -- not what Post would choose for the stock still in the bags.
          rowUnit = math.floor(p.listedValue / listedQty)
        else
          rowUnit = effectivePostUnit(p)
        end
        -- YOU GET answers "what does this row fetch if I click Post", so on the post deck it is
        -- counted over what one click LISTS -- the largest stack for a normal item, the whole
        -- pool for a commodity (position.postableQty, see Core/SellPositions). Counting the bag
        -- sum quoted a figure four fifths of which stayed in the bags.
        local postableQty = exact(p.postableQty) and p.postableQty > 0 and p.postableQty or bagQty
        local grossQty = onListedDeck and listedQty or postableQty
        local gross = rowUnit and safeMultiply(rowUnit, grossQty) or nil
        row.cells.gross:SetText(gross and formatCell(gross) or "—")
        setColor(row.cells.gross, gross and Theme.color.fg or Theme.color.fgDim)
        row.cells.price:SetText(rowUnit and formatCell(rowUnit) or "—")
        -- A lot the cancel queue calls urgent is priced far under the market: that figure is
        -- the problem, and it is the one on this row that goes red.
        local queuedLot = onListed and ROW.queuedLot(p) or nil
        setColor(row.cells.price, (queuedLot and queuedLot.urgent and Theme.color.red)
          or (rowUnit and Theme.color.fg) or Theme.color.fgDim)
        if rowUnit and paidUnit and paidUnit > 0 then
          local pct = math.floor(((rowUnit - paidUnit) / paidUnit) * 100 + 0.5)
          row.grossNote:SetText((pct >= 0 and "+" or "") .. pct .. "%")
          setColor(row.grossNote, pct >= 0 and Theme.color.green or Theme.color.red)
        else
          -- Nothing is "no price yet"; the words are "no receipt, so the margin is not a number
          -- anybody can know". Conflating them is what made Unknown read as broken.
          row.grossNote:SetText(rowUnit and not paidUnit and GC.L["no cost"] or "")
          setColor(row.grossNote, Theme.color.fgDim)
        end
        -- Where rowUnit stands in the live book. The marks count price levels from the
        -- cheapest; the lit one is where this price lands -- gold for a price about to be
        -- posted, the watch blue for a lot already standing there, the same two colours the
        -- book itself uses for the same two facts.
        -- On TO POST the price is about to be posted and joins any level at the same price, so
        -- that level counts as ahead -- what THE BOOK's marker says (SellViewModel.UnitsAhead).
        local standing = rowUnit and GC.SellViewModel.Standing
          and GC.SellViewModel.Standing(p, rowUnit, not onListedDeck) or nil
        local lit = onListedDeck and Theme.color.watch or Theme.color.gold
        for slot, mark in ipairs(row.standMarks) do
          if not standing then
            -- No book, no marks: five grey ticks beside nothing read as a broken widget.
            mark:SetColorTexture(1, 1, 1, 0)
          elseif slot == standing.slot then
            mark:SetColorTexture(lit[1], lit[2], lit[3], 1)
          else
            mark:SetColorTexture(1, 1, 1, slot < standing.slot and 0.32 or 0.10)
          end
        end
        if not standing then
          row.priceStand:SetText("")
        elseif standing.ahead == 0 then
          row.priceStand:SetText(GC.L["first in line"])
          setColor(row.priceStand, Theme.color.green)
        else
          row.priceStand:SetText((onListedDeck and GC.L["%s under you"] or GC.L["%s ahead"]):format(
            GC.Util.FormatCount(standing.ahead) or tostring(standing.ahead)))
          -- Gold where those units are why the lot is worth cancelling; quiet on one being held.
          setColor(row.priceStand, (queuedLot and not queuedLot.urgent)
            and (Theme.color.goldHi or Theme.color.gold) or Theme.color.fgDim)
        end
        -- Post is the point of this screen, so it lives on the row itself. It
        -- used to be reachable only by expanding the position and finding a
        -- sub-row, and only for stock GoldCap had a receipt for -- which is why
        -- the honest answer to "what can I list" was "go use the Blizzard tab".
        -- Set cost is bookkeeping and stays available whenever there is no
        -- stock to act on; the expansion carries it in either case.
        if onListed and ROW.queuedLot(p) then
          -- MY LOTS' own control, on the rows worth cancelling and no others. It cancels nothing
          -- itself: ROW.armLot opens the position and hands the click to the lot's own button.
          showRowAction(row, "Cancel lot", function()
            ROW.mirror = row.action
            ROW.armLot(ROW.queuedLot(row.position))
          end)
        elseif bagQty > 0 and not onListed then
          showRowAction(row, "Post", function() onPostClick(row) end)
        elseif UI.CostDialog.CanSetCost(p) then
          showRowAction(row, GC.L["Set cost"], function() UI.CostDialog.OpenCostDialog(p) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "drawer" then
        INSP.paintHead(row, p, entry.detail)
      elseif entry.kind == "fold" then
        -- "+" and "-" rather than an arrow: only in-game-proven punctuation goes on screen (the
        -- bundled face drew tofu for the arrows the design used).
        row.sectionLabel:SetText((entry.open and "- " or "+ ")
          .. (GC.L["NOT ON HAND %d"]):format(entry.count)
          .. "  " .. DIM_HEX .. GC.L["in the mail, the bank or on another character"] .. "|r")
        row.action:Hide()
      elseif entry.kind == "section" then
        row.sectionLabel:SetText(ROW.sectionText(entry.section))
        row.action:Hide()
      elseif entry.kind == "waitHead" or entry.kind == "waitItem" then
        local title, aside = ROW.waitText(entry)
        row.sectionLabel:SetText(title)
        row.sectionHint:SetText(aside or "")
        row.action:Hide()
      elseif entry.kind == "batch" then
          UI.CostDialog.PaintBatch(row, entry)
      else
        UI.Inspector.PaintPanelRow(row, entry, bagSnapshot)
      end
      -- Banding, hierarchy and the icon are decided here, after the cells are filled, because
      -- only `entry.kind` distinguishes a position from one of its expanded children. Exactly
      -- one of row.cells.item / row.subItem / row.sectionLabel is shown per row -- the other
      -- two are hidden here rather than merely left un-set, since rows are pooled and rebound
      -- to a different kind on every render (a "batch" this pass can be a "position" the next).
      local zc2 = Theme.color.zebra
      -- An OPEN position and the panel under it are one block, so the row wears the same gold
      -- the panel's left rail does instead of its turn in the white zebra. Without it the pair
      -- read as two unrelated rows that happened to land next to each other.
      if entry.kind == "position" and UI.expanded[p.positionKey] then
        local gc3 = Theme.color.gold
        row.zebra:SetVertexColor(gc3[1], gc3[2], gc3[3], 0.10)
        row.selectRing:Show()
      else
        row.zebra:SetVertexColor(zc2[1], zc2[2], zc2[3], (listIndex % 2 == 1) and (zc2[4] or 0.04) or 0)
        row.selectRing:Hide()
      end
      -- The drawer is a SURFACE, not a shaded row: at the well's usual half alpha the window
      -- behind it (and, docked, the auction house's own art at the edges) mixed straight
      -- through and left the panel looking washed out rather than the flat panel colour the
      -- design is drawn in. Every other sub-row keeps the translucent well, so this is set on
      -- both branches -- rows are pooled and one would otherwise inherit the other's fill.
      local pnc = Theme.color.panel
      local phc2 = Theme.color.panelHi
      if entry.kind == "drawer" then
        row.well:SetVertexColor(pnc[1], pnc[2], pnc[3], 1)
      else
        row.well:SetVertexColor(phc2[1], phc2[2], phc2[3], 0.5)
      end
      -- Pooled rows are rebound to a different kind on every render, so a book row's own
      -- widgets have to be put away by whatever kind takes the row next.
      if entry.kind ~= "price" and entry.kind ~= "drawer" then
        UI.Inspector.PutAway(row)
        -- The head dresses the pooled action button as the panel's own Post; every other kind
        -- gets the row button back.
        -- ...at the row's own height for a position, where it is the control the row exists for.
        row.action:SetSize(86, entry.kind == "position" and ROW.BUTTON_H or 18)
        if row.action.SetVariant then row.action:SetVariant("ghost") end
        -- Gold lettering on the row's Post, the way the design drew it: the fill stays the
        -- quiet ghost, so a list of ten does not become ten gold bars.
        -- Red for the one that cancels, on the row and on the panel's lots alike.
        local cancels = row.action.helpKey == "Cancel lot"
        if (entry.kind == "position" or cancels) and row.action.text and row.action.text.SetTextColor then
          local lettering = cancels and Theme.color.red or Theme.color.goldHi or Theme.color.gold
          row.action.text:SetTextColor(lettering[1], lettering[2], lettering[3], 1)
        end
        -- ...and a thin outline with it, on a position or a cancel alone: the pooled button is
        -- every other kind's too, and theirs stay bare.
        if row.action.SetRing then
          local ring = cancels and Theme.color.red or Theme.color.gold
          row.action:SetRing((entry.kind == "position" or cancels) and { ring[1], ring[2], ring[3], cancels and 0.5 or 0.45 } or nil)
        end
      end
      if entry.kind ~= "group" and entry.kind ~= "batch" then row.sectionHint:Hide() end
      -- Same rule, and the drawer has the most to put away: five book lines and four headings.
      -- A pooled row that painted a panel last render would otherwise keep every one of them
      -- on top of whatever line it becomes next.
      if entry.kind ~= "drawer" then
        UI.Book.PutAway(row)
      end
      -- The second lines belong to a position alone; a pooled row that was one last render
      -- must not keep its queue marks under a lot or a batch.
      local twoLine = entry.kind == "position"
      if twoLine then row.priceStand:Show(); row.grossNote:Show()
      else row.priceStand:Hide(); row.grossNote:Hide() end
      for _, mark in ipairs(row.standMarks) do
        if twoLine then mark:Show() else mark:Hide() end
      end
      if entry.kind == "position" then
        row.spine:Hide()
        row.divider:Show()
        row.zebra:Show()
        row.well:Hide()
        row.cells.item:Show()
        row.itemStock:Show()
        row.subItem:Hide()
        row.sectionLabel:Hide()
        row.sectionRule:Hide()
        local icon = nil
        if p.itemID and C_Item and C_Item.GetItemIconByID then
          local ok, texture = pcall(C_Item.GetItemIconByID, p.itemID)
          icon = ok and texture or nil
        end
        -- Item 4 (addon polish batch): no icon means nothing to indent past -- the old
        -- unconditional 26 left the name floating in a blank gap for a row with no
        -- resolvable icon.
        row.itemInset = icon and (ROW.ICON + 10) or 0
        if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
      elseif entry.kind == "fold" or entry.kind == "section" or entry.kind == "waitHead"
          or entry.kind == "waitItem" then
        -- A heading in the list's own column, not a child of the row above it: no spine, no
        -- well, and the label starts where the item names do.
        row.itemInset = 2
        row.icon:Hide(); row.spine:Hide(); row.divider:Hide()
        row.zebra:Hide(); row.well:Hide()
        row.cells.item:Hide(); row.itemStock:Hide(); row.subItem:Hide()
        row.sectionLabel:Show(); row.sectionRule:Show()
        row.sectionRule:ClearAllPoints()
        row.sectionRule:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.s, 0)
        row.sectionRule:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
        -- The fold is a control and wears gold; a section is a caption and stays quiet.
        local fgc = entry.kind == "fold" and Theme.color.gold or Theme.color.fgMuted
        row.sectionRule:SetColorTexture(fgc[1], fgc[2], fgc[3], entry.kind == "fold" and 0.25 or 0.12)
        setColor(row.sectionLabel, fgc)
        -- An item waiting for its key is a line under that heading, not a heading of its own.
        if entry.kind == "waitItem" then row.sectionRule:Hide() end
        -- The waiting heading's aside, one line from its title to the list's edge, where the
        -- rule would run.
        if entry.kind == "waitHead" then
          row.sectionRule:Hide()
          row.sectionHint:ClearAllPoints()
          row.sectionHint:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.m, 0)
          row.sectionHint:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
          row.sectionHint:SetWordWrap(false)
          row.sectionHint:SetMaxLines(1)
          row.sectionHint:Show()
        end
      else
        row.itemInset = 34
        row.icon:Hide()
        row.spine:Show()
        row.divider:Hide() -- a group's children are bracketed by the spine, not sliced by rules
        -- The well, not the zebra: a sub-row sits on a nested fill instead of the list's own
        -- banding, so an expanded group reads as one bracketed unit (the spine is the other
        -- half of that cue) rather than as more top-level rows in the same alternating list.
        row.zebra:Hide()
        row.well:Show()
        row.cells.item:Hide()
        row.itemStock:Hide()
        if entry.kind == "group" then
          row.subItem:Hide()
          row.sectionLabel:Show()
          row.sectionRule:Show()
        else
          row.subItem:Show()
          row.sectionLabel:Hide()
          row.sectionRule:Hide()
        end
      end
      if entry.panel then
        -- The panel is the surface these sit on: no well, no spine bracketing them to a row
        -- that is a column away.
        row.spine:Hide(); row.well:Hide(); row.zebra:Hide()
        UI.Inspector.LayoutDetailRow(row)
      else
        layoutCells(row)
      end
    end
  end
  UI.Inspector.PaintInspector(openPosition)
  -- Measured from what was actually placed, not from #entries: a multi-slot entry occupies
  -- more than one row's worth, and a scroll child sized by entry COUNT would clip the drawer.
  UI.content:SetHeight(math.max(UI.rowHeight, placedHeight))
  if UI.detailContent then UI.detailContent:SetHeight(math.max(UI.rowHeight, detailHeight)) end
  Walk.ScheduleExpiry()
  if GC.Sniper and GC.Sniper.UpdateSellTabLabel then GC.Sniper.UpdateSellTabLabel() end
end
UI.List.RenderRows = renderRows

-- The toolbar queue control's own click. Arms queue mode (so row 1 is guaranteed to be the
-- head -- see renderRows' own "queue" branch above and the design document's own reasoning for
-- why this, rather than teaching onPostClick a second way to find a row) and then posts row 1
-- through onPostClick EXACTLY -- its own pin validation, its needsConfirmation branch, its
-- timeout. There is no second posting implementation here, and nothing here calls a protected
-- API directly; see spec/sell_post_wiring_spec.lua for the static guard on both.
--
-- Retail posts on the first press, exactly as addon-v0.15.3 did: switch into queue mode, render,
-- post row 1, all in the same click. If row 1 does not come back as a rendered "position" row
-- after that render -- the container hidden, a render some other in-flight arm is still
-- deferring -- no protected call is attempted on a guess; the status line says so and the player
-- can press again.
--
-- WoW: Forever only: renderRows() -> pushPosition -> cacheBagLocation runs Blizzard's
-- ItemLocation:CreateFromBagAndSlot for every position with bag stock, plus GC.Sell._SlotKey for
-- every non-commodity one, and paints besides -- all of it Blizzard or GoldCap Lua a click that
-- ends in PostCommodity/PostItem must not run ahead of that call there (final review C1). So in
-- Forever a click that would have to render first -- switching into queue mode, or the queue's
-- own head having moved since the last render -- renders ONLY, and asks for one more press once
-- row 1 is actually the rendered head; it never falls through into onPostClick in the same click
-- that just rendered. Only a click that finds row 1 already the queue's rendered, shown head
-- posts -- and then through onPostClick EXACTLY, with no render of its own. The split is gated on
-- Forever (read fresh, like every other GC.Game.IsForever gate, and inline: this file's top-level
-- local headroom is not spent on it) because retail has always rendered inside this click and a
-- retail player never had to press twice (retail drift audit F1).
local function onQueueClick()
  if #S.queueEntries == 0 then
    setStatus(GC.L["Nothing queued to post"])
    return
  end
  local head = S.queueEntries[1]
  -- `row:IsShown()`, never `row.shown`. A real Frame has no `shown` FIELD -- only the method --
  -- but every widget double in this suite implements Show/Hide by writing `self.shown`, so
  -- reading the field is true in every test and nil in the client, and this button would have
  -- shipped refusing to post anything at all while seven tests proved it worked. That is the
  -- third time today a field only the fakes define reached production; see
  -- spec/ui_widget_field_spec.lua, which now fails the build for it.
  --
  -- Shared by both branches below: row 1 only counts as the queue's own head when it is actually
  -- showing that exact position. A Cancel lot or a Remove armed anywhere holds renderRows() to a
  -- no-op (its own guard, above it in this file) rather than rebinding rows out from under a pin
  -- the player is mid-confirming, so without this identity check row 1 can still be whatever
  -- OTHER deck was on screen before the click -- and the retail branch used to post that instead
  -- of the position the button, or its keybinding, actually named as next.
  local function isQueueHead(row)
    return row and row.IsShown and row:IsShown() and row.kind == "position"
      and row.position and row.position.positionKey == head.positionKey
  end
  if not (GC.Game and GC.Game.IsForever(GC.Game.Passport())) then
    S.filterMode = "queue"
    renderRows()
    local row = UI.rows[1]
    if isQueueHead(row) then
      onPostClick(row)
    else
      setStatus(GC.L["Could not find the queue's next item to post — try again"])
    end
    return
  end
  local row = UI.rows[1]
  if S.filterMode == "queue" and isQueueHead(row) then
    onPostClick(row)
    return
  end
  S.filterMode = "queue"
  renderRows()
  setStatus(GC.L["Queue ready — press POST again to post it"])
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

function GC.Sell.Show()
  if UI.container then UI.container:Show() end
  -- The headings are otherwise only ever stamped when the DECK changes (renderRows), and this
  -- tab spends most of its life hidden behind Deals or Sold: a one-line FontString that was on
  -- screen when its parent hid can come back with its text simply not drawn, and SetText is
  -- what the client needs to draw it again (UI/SniperFrame.lua's updateHeaderSortIndicators
  -- carries the full story). Unconditional, from the deck the header is currently showing.
  if UI.container and UI.container.header then
    paintHeaderText(UI.container.header, UI.container.headerDeck)
  end
  -- This is what flushes a render renderRows() deferred while the container was hidden: Show()
  -- has always called Refresh() unconditionally, and Refresh()'s own Compose.Positions()+
  -- renderRows() pass now runs for real the instant Walk.Shown() is true. An explicit
  -- flushDeferredRender() call here would render this same pass a second time.
  GC.Sell.Refresh()
  -- Mid-post the render is held, so coming back to the tab re-sets the dock's line and the
  -- busy labels with the text they already hold -- a no-op the client does not redraw on a
  -- one-line FontString that was hidden and shown (the engineering notes' "Text"): the row and
  -- the dock could sit on a bare spinner until the answer (review M4). Clear, set, hide, show,
  -- the cure UI/BuyFrame.lua's restampHeadings uses.
  if UI.container and (S.postingRow or GC.Sell._postNote) then
    local function restamp(fs)
      if not (fs and fs.IsShown and fs:IsShown()) then return end
      local text = fs:GetText() or ""
      fs:SetText(""); fs:SetText(text); fs:Hide(); fs:Show()
    end
    restamp(UI.container.dockStatus)
    restamp(UI.container.queueLabel)
    for _, button in ipairs({ UI.container.queueButton or false, S.postingRow and S.postingRow.action or false }) do
      if button and button.label and button.SetLabel then
        local label = button.label
        button:SetLabel(""); button:SetLabel(label)
        if type(button.text) == "table" then restamp(button.text) end
      end
    end
  end
end
function GC.Sell.Hide() if UI.container then UI.container:Hide() end end

function GC.Sell.Attach(f, geometry)
  UI.rowWidth, UI.rowHeight, UI.window = geometry.rowWidth, geometry.rowHeight, f
  UI.container = CreateFrame("Frame", nil, f)
  local container = UI.container
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top); container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom); container:Hide()
  -- Two rows of chrome and a footer, down from three rows of chrome. The three stat cards that
  -- used to own row 3 were 40px of ACCOUNTING sitting above the work; they are one quiet line
  -- in the footer now, beside the bulk action, where the eye ends rather than where it starts.
  --   row 1 (y   0): [TO POST N][MY LOTS N] ·········· [NO COST][READY][REFRESH]
  --   row 2 (y -34): column headings for the deck below
  --   list  (y -52) ......................................................... (to footer)
  --   footer (bottom, h32): [POST N] head label ··· held-back · cost / listed / profit
  -- Each row still owns its whole width: the layout this replaced let two anchor chains grow
  -- toward each other on one shared row and collide at ordinary window widths (the queue's head
  -- label ran under the filter chips; the cancel cluster ran under EST. PROFIT).
  -- The dock: one raised surface along the bottom carrying the deck's bulk action, what it
  -- will do next, what is happening, and the session's three totals. It used to be a bare strip
  -- of widgets on the window's own background, which read as leftovers under the list rather
  -- than as the place the tab is driven from.
  local phc = Theme.color.panelHi
  local dockFill = Theme.SlicedTexture(container, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { phc[1], phc[2], phc[3], 1 }, 12)
  dockFill:SetPoint("BOTTOMLEFT"); dockFill:SetPoint("BOTTOMRIGHT")
  dockFill:SetHeight(DOCK.H)
  container.dockFill = dockFill
  local refreshButton = Theme.Button(container, "ghost", "plaque")
  -- 104, not 72: the busy label is "PRICING 10/24" (see paintRefreshButton), which is 101.4px
  -- at mono-10 and Theme.Scale() 1.3 (JetBrains Mono ~0.6em/char -> 7.8px/char) -- a button
  -- sized for "REFRESH" alone would have let that overflow its own edges into the filter chip
  -- beside it.
  refreshButton:SetSize(104, 26); refreshButton:SetPoint("TOPRIGHT", 0, 0); refreshButton:SetLabel(GC.L["REFRESH"])
  container.refreshButton = refreshButton
  -- Wrapped, not passed directly: OnClick hands the handler (self, button, down),
  -- so GC.Sell.Refresh would receive the button as its `automatic` flag -- truthy
  -- -- and every press would take the stand-aside path that exists for the timer.
  -- The button would have gone on doing nothing, which is the bug this argument
  -- was added to fix.
  refreshButton:SetScript("OnClick", function() GC.Sell.Refresh() end)
  -- Two chips, where there were five. Not a cut: three of the old five became the DECK switch
  -- below ("in bags" and "listed" are the decks themselves) and "GC" was a provenance cut
  -- sitting where a player expected "my auctions" -- provenance stays on the tooltip. What is
  -- left are the two questions that NARROW a deck instead of replacing it, which is why they
  -- are booleans and can both be on at once. The old five could not express that at all.
  container.filterButtons = {}
  local previous = refreshButton
  -- State on the chip itself: SetVariant, never a second overlaid button (one control, two
  -- variants -- see the addon's engineering notes on buttons).
  local function paintFilterChips()
    for _, id in ipairs(CHIP_IDS) do
      local chip = container.filterButtons[id]
      if chip then
        -- Both chips ask POST-deck questions, so on LISTED they are disabled rather than
        -- hidden: a control that vanishes reads as a bug, one that dims reads as "not here".
        local onPostDeck = S.filterMode ~= "listed" and S.filterMode ~= "cancelqueue"
        chip:SetVariant(UI.chips[id] and onPostDeck and "active" or "ghost")
        if onPostDeck then chip:Enable() else chip:Disable() end
      end
    end
  end
  container.paintFilterChips = paintFilterChips
  for slot, id in ipairs(CHIP_IDS) do
    local button = Theme.Button(container, "ghost", "badge")
    button:SetSize(CHIP_WIDTHS[slot], 20)
    button:SetPoint("RIGHT", previous, "LEFT", -2, 0)
    button:SetLabel(GC.L[CHIP_LABELS[slot]])
    button:SetScript("OnClick", function()
      UI.chips[id] = not UI.chips[id]
      -- "queue" and "cancelqueue" are transient FOCUS states, not decks, and nothing ever
      -- cleared them: press the POST control once and the tab rendered the queue's own order
      -- for the rest of the session, with these chips lighting up over a list they could not
      -- narrow. Pressing a chip is a request to filter a deck, so give the chip its deck back.
      if S.filterMode == "queue" then S.filterMode = "post"
      elseif S.filterMode == "cancelqueue" then S.filterMode = "listed" end
      -- A chip changes which rows are on screen, so the order is the player's to have again.
      S.rowPlaces = {}
      -- Through the container, not the local: paintDeckSwitch is declared below this loop.
      if container.paintDeckSwitch then container.paintDeckSwitch() end
      paintFilterChips()
      renderRows()
    end)
    container.filterButtons[id] = button
    previous = button
  end

  -- The deck switch: the one control this redesign turns on. "What can I list" and "what is
  -- already listed" are two jobs, and serving both from one table is what forced the action
  -- column to change its verb from row to row -- Post here, Repost there, Set cost on the next
  -- -- so no player could ever read ahead. One deck, one verb.
  container.deckButtons = {}
  local function deckCounts()
    local post, listed = 0, 0
    for _, position in ipairs(S.positions) do
      local bags = type(position.bagQty) == "number" and position.bagQty or 0
      local live = type(position.listedQty) == "number" and position.listedQty or 0
      -- What can be POSTED, not everything the deck holds. The deck also lists stock that is
      -- neither in the bags nor listed -- folded away under NOT ON HAND, or a purchase not yet
      -- identified -- and counting those read "TO POST 17" over three rows with a Post button
      -- (seen in game). The rows stay where they were; only the number says what it names.
      if bags > 0 then post = post + 1 end
      if live > 0 then listed = listed + 1 end
    end
    return post, listed
  end
  -- Deliberately reads the deck the QUEUE focus states belong to: "queue" is a focus inside the
  -- post deck and "cancelqueue" one inside listed, so pressing a queue control must not leave
  -- the switch painting neither half as active.
  local function activeDeck()
    return (S.filterMode == "listed" or S.filterMode == "cancelqueue") and "listed" or "post"
  end
  local function paintDeckSwitch()
    local post, listed = deckCounts()
    local counts = { post = post, listed = listed }
    for slot, id in ipairs(DECK_IDS) do
      local button = container.deckButtons[id]
      if button then
        button:SetLabel((GC.L[DECK_LABELS[slot]]):format(counts[id] or 0))
        button:SetVariant(activeDeck() == id and "active" or "ghost")
      end
    end
  end
  container.paintDeckSwitch = paintDeckSwitch
  local deckPrevious
  for _, id in ipairs(DECK_IDS) do
    local button = Theme.Button(container, "ghost", "plaque")
    -- 128, sized for "TO POST 88" at mono-10 and Theme.Scale() 1.3 (~7.8px/char = 78px) with
    -- room for the rounded plaque's own inset, the same way REFRESH is sized for "PRICING 10/24".
    button:SetSize(128, 26)
    if deckPrevious then button:SetPoint("LEFT", deckPrevious, "RIGHT", 4, 0)
    else button:SetPoint("TOPLEFT") end
    button:SetScript("OnClick", function()
      S.filterMode = id
      S.rowPlaces = {} -- a different deck is a different list; settle it fresh
      -- A deck change invalidates whatever the other deck's chips were narrowing to, and an
      -- expansion opened on a row that is not on this deck would render against nothing.
      paintDeckSwitch(); paintFilterChips(); renderRows()
    end)
    container.deckButtons[id] = button
    deckPrevious = button
  end
  paintDeckSwitch()
  paintFilterChips()

  -- Search, between the deck switch and the chips. Forty positions is an ordinary posting deck
  -- and finding one of them was a matter of reading down the list. It lives in whatever room
  -- row 1 has left, so under SEARCH_MIN of it the box is not drawn at all -- and takes its
  -- filter with it, because a list narrowed by a box nobody can see is a list that looks broken.
  -- The kit's own well at the height of the deck buttons it sits beside (InputBoxTemplate is a
  -- fixed 20px strip of Blizzard's stone border, a third shorter than everything on the row).
  local searchWell = CreateFrame("Frame", nil, container)
  searchWell:SetHeight(26)
  searchWell:SetPoint("LEFT", deckPrevious, "RIGHT", 12, 0)
  local swc = Theme.color.bg or Theme.color.panel
  Theme.SlicedTexture(searchWell, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { swc[1], swc[2], swc[3], 1 }, 12):SetAllPoints(searchWell)
  Theme.SlicedTexture(searchWell, "BORDER", Theme.MEDIA .. "plaque_ring.png",
    { 1, 1, 1, 0.12 }, 12):SetAllPoints(searchWell)
  local search = CreateFrame("EditBox", nil, searchWell)
  search:SetAutoFocus(false)
  search:SetPoint("TOPLEFT", 10, -2)
  search:SetPoint("BOTTOMRIGHT", -8, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if search.SetFont then
    search:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    search:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    Theme.OnRescale(function(scale) search:SetFont(Theme.FONT_UI, 11 * scale, "") end)
  end
  container.search = search
  local searchHint = Theme.Num(searchWell, 10)
  searchHint:SetJustifyH("LEFT")
  searchHint:SetPoint("LEFT", searchWell, "LEFT", 10, 0)
  searchHint:SetText(GC.L["Search"])
  setColor(searchHint, Theme.color.fgDim)
  container.searchHint = searchHint
  local function applySearch()
    local text = (search:GetText() or ""):lower():match("^%s*(.-)%s*$")
    UI.chips.search = search:IsShown() and text ~= "" and text or nil
    if text ~= "" or (search.HasFocus and search:HasFocus()) then searchHint:Hide() else searchHint:Show() end
  end
  search:SetScript("OnTextChanged", function(_, byUser)
    applySearch()
    if byUser then renderRows() end
  end)
  search:SetScript("OnEditFocusGained", applySearch)
  search:SetScript("OnEditFocusLost", applySearch)
  search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(box)
    box:SetText(""); box:ClearFocus()
    applySearch(); renderRows()
  end)
  -- Row 1's fixed occupants: two deck buttons and their gap, REFRESH, the two chips and theirs.
  local SEARCH_MIN, SEARCH_MAX, ROW1_FIXED = 120, 220, 2 * 128 + 4 + 104 + 92 + 76 + 4
  container.layoutSearch = function()
    local room = (UI.rowWidth or 0) - ROW1_FIXED - 36
    if room >= SEARCH_MIN then
      searchWell:SetWidth(math.min(SEARCH_MAX, room)); searchWell:Show(); search:Show()
    else
      searchWell:Hide(); search:Hide()
    end
    applySearch()
    if not search:IsShown() then searchHint:Hide() end
  end
  container.layoutSearch()
  -- The posting queue control: the toolbar's own left end, opposite Refresh/the filter chips.
  -- "POST N" (its own count, so the number is on the button a click actually is), a label
  -- beside it naming the item and unit price that click will post -- a blind click is not one a
  -- seller should be asked to make -- and a held-back indicator with a tooltip that explains,
  -- in words, everything GC.PostQueue.Build held back. See paintQueueButton for how all three
  -- are painted, and onQueueClick for what a click does.
  local queueButton = Theme.Button(container, "primary", "plaque")
  -- 136, not 110: matches cancelButton below, sized for its own widest label ("NOTHING TO
  -- CANCEL", 132.6px at mono-10 and Theme.Scale() 1.3 -- JetBrains Mono ~0.6em/char ->
  -- 7.8px/char) -- a narrower button let "NOTHING TO POST" spill past its own borders.
  queueButton:SetSize(136, 26)
  queueButton:SetPoint("BOTTOMLEFT", DOCK.PAD, (DOCK.H - 26) / 2)
  queueButton:SetScript("OnClick", function() onQueueClick() end)
  container.queueButton = queueButton

  -- Two lines beside the button: what the next press does, and under it what is happening.
  local queueLabel = Theme.Num(container, 10)
  queueLabel:SetPoint("LEFT", queueButton, "RIGHT", 10, 7)
  queueLabel:SetJustifyH("LEFT")
  queueLabel:SetWordWrap(false)
  container.queueLabel = queueLabel

  local dockStatus = Theme.Num(container, 9)
  dockStatus:SetPoint("LEFT", queueButton, "RIGHT", 10, -7)
  dockStatus:SetJustifyH("LEFT")
  dockStatus:SetWordWrap(false)
  setColor(dockStatus, Theme.color.fgMuted)
  container.dockStatus = dockStatus

  local queueHeldBack = Theme.Num(container, 9)
  queueHeldBack:SetJustifyH("LEFT")
  setColor(queueHeldBack, Theme.color.fgDim)
  -- Both anchors set below, once its row-2 position and the ALL chip it abuts exist -- see the
  -- row-1 bounding block after the cancel cluster (M5: RIGHT-bound against the ALL chip, or a
  -- long held-back count ran under the filter chips at narrow widths).
  queueHeldBack:Hide()
  container.queueHeldBack = queueHeldBack

  -- A FontString cannot take mouse scripts (see the header-cell hit frames a little further
  -- down for the same fix) -- this invisible frame over the label is what actually raises the
  -- tooltip. Content is read from queueSkipped live, at hover time, rather than baked in when
  -- the label's text was last set, so it can never go stale between two renders.
  local queueHeldBackHit = CreateFrame("Frame", nil, container)
  queueHeldBackHit:SetAllPoints(queueHeldBack)
  queueHeldBackHit:EnableMouse(true)
  queueHeldBackHit:Hide()
  queueHeldBackHit:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GC.Util.ClientText(GC.L["Held back from the queue"]), 1, 0.82, 0)
    if #S.queueSkipped == 0 then
      GameTooltip:AddLine(GC.Util.ClientText(GC.L["Nothing is being held back."]), 0.85, 0.85, 0.85, true)
    else
      for _, skip in ipairs(S.queueSkipped) do
        GameTooltip:AddLine(GC.Util.ClientText(("%s — %s"):format(skip.itemName or GC.L["Item"],
          (QUEUE_SKIP_TEXT[skip.reason] and GC.L[QUEUE_SKIP_TEXT[skip.reason]]
            or GC.L["not ready to post"]))), 0.85, 0.85, 0.85, true)
      end
    end
    GameTooltip:Show()
  end)
  queueHeldBackHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  container.queueHeldBackHit = queueHeldBackHit

  paintQueueButton() -- honest empty/disabled state before the very first compose ever runs

  -- The cancel queue control: row 1's right end, the far side of the row from Post -- the two
  -- queue actions are siblings, but a destructive control does not belong ADJACENT to a
  -- non-destructive one. Danger when it can burn a deposit, ghost when idle -- still the
  -- quieter look next to POST. See paintCancelButton for the states and onCancelQueueClick
  -- for what a click does (and, more importantly, does not) do.
  local cancelButton = Theme.Button(container, "ghost", "plaque")
  -- 136 for the same reason as the Post button: "NOTHING TO CANCEL" (132.6px at mono-10 and
  -- Theme.Scale() 1.3) must fit inside.
  cancelButton:SetSize(136, 26)
  -- The SAME footer slot as the post queue's control, not the far end of a row: only one deck
  -- is ever on screen, so only one of these is ever shown, and putting them in one place means
  -- the bulk action never moves under the cursor when the deck changes.
  cancelButton:SetPoint("BOTTOMLEFT", DOCK.PAD, (DOCK.H - 26) / 2)
  cancelButton:SetScript("OnClick", function() onCancelQueueClick() end)
  container.cancelButton = cancelButton

  local cancelHeldBack = Theme.Num(container, 9)
  cancelHeldBack:SetJustifyH("LEFT")
  setColor(cancelHeldBack, Theme.color.fgDim)
  cancelHeldBack:SetPoint("LEFT", cancelButton, "RIGHT", 10, 7)
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

  -- Row-1 bounding, settable only now that the cancel cluster exists: the head label
  -- stretches between the Post button and the cancel cluster, so a long item name TRUNCATES
  -- instead of running under the controls to its right -- exactly the collision the old
  -- one-row toolbar shipped. The post queue's own held-back count does NOT sit here: two
  -- identical "N held back" strings side by side (one the post queue's, one the cancel
  -- queue's) read as one meaningless phrase, so the post one moves to row 2's empty left
  -- end, under the cluster it belongs to, and says which queue it is about in words.
  queueLabel:SetPoint("RIGHT", queueHeldBack, "LEFT", -10, 0)
  -- RIGHT edge deliberately NOT set here: the ledger line built further down owns the
  -- footer's right corner, and anchoring both to it painted the held-back count straight
  -- through the profit figure. Bound against the ledger's leftmost label once that exists.
  queueHeldBack:SetWordWrap(false)

  paintCancelButton()

  -- The real keybinding (Bindings.xml, auto-loaded by the client, not listed in the .toc -- see
  -- that file) reaches into this exact field on the Sniper window frame, because Bindings.xml
  -- executes as its own isolated Lua chunk with no upvalues into this file. It calls the SAME
  -- Lua function the button's own OnClick calls above -- never Button:Click(), which both
  -- inherits the caller's taint and skips RegisterForClicks/the mouse-down handling (see the
  -- design document's own reasoning). A keybinding handler already runs synchronously inside a
  -- real hardware input event, which is what a protected post actually requires.
  f.GoldCapPostNext = onQueueClick

  -- The same three figures updateSummary has always written, moved out of 40px of stat cards
  -- sitting ABOVE the work into one right-aligned line in the footer. They are what the session
  -- adds up to -- a thing to glance at on the way out, not a thing to read before starting. The
  -- labels shortened with the move: at Theme.Scale() 1.3 three full phrases plus their figures
  -- would have run into the bulk action sharing this row. See SUMMARY_STAT_LABELS/
  -- SUMMARY_STAT_IDS above for what each one is and why.
  container.summary = {}
  local ledgerPrevious
  for i, id in ipairs(SUMMARY_STAT_IDS) do
    local stat = { id, SUMMARY_STAT_LABELS[i] }
    -- Label over figure in a fixed-width column, where they used to run inline as "LABEL
    -- figure LABEL figure": stacked, three totals take half the width, and that width is what
    -- the line beside the bulk action needs at the default window.
    local value = Theme.Num(container, 10, true)
    value:SetJustifyH("RIGHT"); value:SetWordWrap(false)
    value:SetWidth(DOCK.STAT_W)
    if ledgerPrevious then value:SetPoint("RIGHT", ledgerPrevious, "LEFT", -8, 0)
    else value:SetPoint("RIGHT", container, "BOTTOMRIGHT", -DOCK.PAD, DOCK.H / 2 - 7) end
    local label = Theme.Num(container, 9)
    label:SetJustifyH("RIGHT"); label:SetWordWrap(false)
    label:SetWidth(DOCK.STAT_W)
    label:SetPoint("BOTTOMRIGHT", value, "TOPRIGHT", 0, 3)
    label:SetText(GC.L[stat[2]]); setColor(label, Theme.color.fgDim)
    container.summary[stat[1]] = value
    container.summaryLabels = container.summaryLabels or {}
    container.summaryLabels[stat[1]] = label
    if stat[1] == "profit" then
      -- Same invisible-hit-frame trick the stat card used, for the same reason: a FontString
      -- cannot take mouse scripts, and the partial/missing detail is read from
      -- container.summaryProfitDetail LIVE at hover time so it can never go stale between
      -- renders. Covers the label as well as the figure -- the two read as one control.
      local hit = CreateFrame("Frame", nil, container)
      hit:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 2)
      hit:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", 0, -2)
      hit:EnableMouse(true)
      hit:SetScript("OnEnter", function(self)
        if not GameTooltip or not container.summaryProfitDetail then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(GC.Util.ClientText(GC.L["Est. profit"]), 1, 0.82, 0)
        GameTooltip:AddLine(
          GC.Util.ClientText(GC.L["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"]),
          0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(GC.Util.ClientText(container.summaryProfitDetail), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(GC.Util.ClientText(GC.L["Positions without a cost or a live price are excluded."]),
          0.85, 0.85, 0.85, true)
        GameTooltip:Show()
      end)
      hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      container.summaryProfitHit = hit
    end
    ledgerPrevious = value
  end
  -- The leftmost thing in the ledger line, whatever it turned out to be: the held-back counter
  -- and the queue's head label chain LEFT from here, so the footer's two halves can never
  -- overlap however long either grows.
  -- Re-run on every resize: under DOCK.NARROW the ledger keeps AT MARKET alone, and whatever
  -- is leftmost afterwards is what the two lines beside the bulk action stop short of. The
  -- held-back counter rides the upper line (14 above a figure's own centre), the status the
  -- lower one, level with the figures.
  local function layoutLedger()
    local narrow = (UI.rowWidth or 0) < DOCK.NARROW
    local left
    for _, id in ipairs(SUMMARY_STAT_IDS) do
      local value, label = container.summary[id], container.summaryLabels[id]
      if id == "profit" or not narrow then
        value:Show(); label:Show()
        left = value
      else
        value:Hide(); label:Hide()
      end
    end
    container.ledgerLeft = left
    queueHeldBack:ClearAllPoints()
    queueHeldBack:SetPoint("RIGHT", left, "LEFT", -12, 14)
    dockStatus:ClearAllPoints()
    dockStatus:SetPoint("LEFT", queueButton, "RIGHT", 10, -7)
    dockStatus:SetPoint("RIGHT", left, "LEFT", -12, 0)
  end
  container.layoutLedger = layoutLedger
  layoutLedger()
  local header = CreateFrame("Frame", nil, container)
  -- Kept on the container so renderRows can re-lay it out when the deck changes; see its own
  -- comment for why that cannot live in the deck buttons' click handler.
  container.header = header
  container.headerDeck = "post"
  header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", 0, -34); header:SetHeight(16); header.cells = {}
  header.itemInset = ROW.ICON + 10 -- line the ITEM heading up with the names, not with the icons
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Num(header, 9); cell:SetWordWrap(false); cell:SetText(""); header.cells[column.key] = cell
    -- One line, hard capped -- the pair every other single-line cell in the kit carries
    -- (UI/SniperFrame.lua's buildHeaderCell): this row is 16px tall, and a line that does
    -- not fit the height it is given is not drawn at all.
    cell:SetMaxLines(1)
    setColor(cell, Theme.color.fgDim)
    -- Headings must sit over their own numbers. createRow right-aligns every numeric cell, but
    -- these were left at the default left alignment, so each heading floated to the left edge
    -- of a right-aligned column and every value looked like it belonged to the column after it.
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    -- A FontString cannot take mouse scripts, so each heading gets an invisible hit frame over
    -- it. Every column here is a number a seller has to trust, so each one explains itself
    -- instead of expecting a one-word heading to carry the meaning.
    local help = HEADER_HELP[column.key]
    if help then
      local hit = CreateFrame("Frame", nil, header)
      hit:SetAllPoints(cell)
      hit:EnableMouse(true)
      -- Translated at READ time -- see HEADER_HELP's own comment for why the table
      -- itself cannot hold GC.L lookups.
      local body = {}
      for i = 1, #help[2] do body[i] = GC.L[help[2][i]] end
      explain(hit, GC.L[help[1]], body)
    end
  end
  -- Separates the column headings from the first row now that both read in the same mono
  -- font -- without it the header row visually fused with row 1.
  local rule = header:CreateTexture(nil, "ARTWORK")
  local bc = Theme.color.border
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  paintHeaderText(header, "post")
  layoutCells(header)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -52)
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
  -- Stops above the footer instead of running to the container's own bottom edge: the bulk
  -- action and the ledger line live there now, and a list that scrolled under them would put
  -- rows behind a control that can spend gold.
  scroll:SetPoint("BOTTOMRIGHT", 0, DOCK.H + 6)
  -- Empty-state panel, mirroring the Deals board's own (SniperFrame.lua) exactly: parented to
  -- `scroll` (not `content`), living where the rows would be, never scrolling.
  local emptyText = Theme.Label(scroll, 12)
  emptyText:SetPoint("TOP", scroll, "TOP", 0, -UI.rowHeight * 2)
  emptyText:SetPoint("LEFT", scroll, "LEFT", Theme.pad.m * 3, 0)
  emptyText:SetPoint("RIGHT", scroll, "RIGHT", -Theme.pad.m * 3, 0)
  emptyText:SetJustifyH("CENTER")
  emptyText:SetWordWrap(true)
  emptyText:SetSpacing(4)
  emptyText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  emptyText:Hide()
  container.emptyText = emptyText
  UI.content = CreateFrame("Frame", nil, scroll); UI.content:SetSize(UI.rowWidth, UI.rowHeight); scroll:SetScrollChild(UI.content)

  UI.Inspector.Build()

  -- The list's own width follows the panel: docked, it ends where the panel's column begins
  -- (the gap is where the list's scroll bar hangs); as a sheet, it keeps the whole width and
  -- the panel covers its right side. Called by renderRows when that changes and by the resize
  -- hook, never per render.
  container.applyListGeometry = function()
    local inset = INSP.docked() and (INSP.W + INSP.GAP) or 0
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", -inset, -34)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 0, -52); scroll:SetPoint("BOTTOMRIGHT", -inset, DOCK.H + 6)
    UI.content:SetWidth(INSP.listWidth())
    layoutCells(header)
  end

  UI.CostDialog.Build()
  -- OnSizeChanged fires once per pixel while the resize grip is being dragged -- as often as
  -- every frame -- and renderRows is not free: it walks the filtered position list and
  -- rebuilds every visible row. Layout (the width-driven column drop) is cheap and stays
  -- immediate; the row rebuild is coalesced to a single pass once the size has settled,
  -- rather than rebuilding the model up to 60 times a second while the grip is dragged.
  local resizeRenderToken = 0
  f:HookScript("OnSizeChanged", function(_, width)
    UI.rowWidth = math.max(1, width - geometry.panelLeft - geometry.panelRightInset)
    -- Through the same function a panel opening uses: the width a resize leaves decides
    -- whether the panel still has a column of its own.
    container.listDocked = INSP.docked()
    container.applyListGeometry()
    layoutLedger()
    container.layoutSearch()
    resizeRenderToken = resizeRenderToken + 1
    local token = resizeRenderToken
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if token == resizeRenderToken then renderRows() end
      end)
    else
      renderRows()
    end
  end)
end

-- Live diagnosis for a wedged pricing walk, straight from the client: /goldcap sellstate
-- prints the machine's actual state instead of leaving "PRICING…" to be guessed about.
-- Registered here (not Core/Init.lua) because every field it reads is this file's own.
GC.slashHandlers = GC.slashHandlers or {}
-- The throttle flag as the CLIENT reports it, with no side effect.
--
-- Quotes.driver.isReady() is GC.Util.ThrottleReady(), which past its stuck window answers true on a
-- flag the client is still reporting false. That is the right answer for a sender and the
-- wrong one for a readout of what the CLIENT says, which is what these two printers want.
local function throttleReadyForDisplay()
  return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
    and C_AuctionHouse.IsThrottledMessageSystemReady() == true or false
end

GC.slashHandlers.sellstate = function()
  local pending = S.refresh.pending
  GC.Print((GC.L["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"]):format(
    tostring(S.refresh.phase), #S.refresh.queue, S.refresh.index or 0, S.refresh.skipped or 0,
    time() - (S.refresh.progressAt or 0),
    pending and (" · pending item %s for %ds"):format(tostring(pending.itemID), time() - pending.at) or ""))
  local blocking = GC.Sniper and (GC.Sniper.IsSearchCritical or GC.Sniper.IsBusy)
  local rested = 0
  for _, rest in pairs(S.emptyAnswers) do
    if type(rest) == "table" and type(rest.at) == "number"
        and time() - rest.at <= EMPTY_ANSWER_AGE then rested = rested + 1 end
  end
  GC.Print((GC.L["throttle ready=%s · sniper busy=%s · empty answers resting=%d"]):format(
    tostring(throttleReadyForDisplay()),
    tostring(blocking and blocking() or false), rested))
  -- Every row without a market price, and the EXACT reason the walk is not asking about it --
  -- mirrors Walk.Queue's own membership rules, so a "—" can always be explained.
  local shown = 0
  for _, position in ipairs(S.positions) do
    if position.displayMarketUnit == nil and position.itemID and shown < 12 then
      local inBags = type(position.bagQty) == "number" and position.bagQty > 0
      local listed = type(position.listedQty) == "number" and position.listedQty > 0
      local commodity = type(position.positionKey) == "string"
        and position.positionKey:find("commodity:", 1, true) == 1
      local restingAt = Walk.RestedAt(position.quoteKey or position.itemID)
      local resting = restingAt ~= nil and (time() - restingAt) <= EMPTY_ANSWER_AGE
      local why
      if position.unresolved and not commodity then
        why = GC.L["identity unresolved (variant item -- not priced by design)"]
      elseif not (inBags or listed) then
        why = GC.L["no stock in bags or listed -- nothing to price for"]
      elseif resting and Walk.RestedEmptyFresh(position.quoteKey or position.itemID, time()) then
        why = (GC.L["AH answered empty %ds ago"]):format(time() - restingAt)
      elseif resting then
        -- Rested but never ANSWERED. Printing the line above here is what made a wedged walk
        -- read as a quiet auction house.
        why = (GC.L["no answer %ds ago -- resting"]):format(time() - restingAt)
      else
        why = GC.L["due -- will be asked next pass"]
      end
      shown = shown + 1
      -- A variant by its exact key: two item levels of one piece read as one line by item ID.
      GC.Print(("  %s (%s): %s"):format(tostring(position.itemName or "?"),
        tostring(position.quoteKey or position.itemID), why))
    end
  end
end

-- `/gc sell`: the pricing walk's state and who holds the shared search slot, printed to
-- chat. For a live client that sits at "PRICING…" -- the walk yields to whatever owns the
-- slot and there is otherwise nothing on screen that says which gate it is waiting on.
function GC.Sell.DebugPrint()
  local sniper = GC.Sniper or {}
  -- What C_AuctionHouse.GetAuctionInfoByID said about the last auction created (GC.Sell.
  -- OnAuctionCreated): whether the client names a just-created auction at all.
  GC.Print(GC.Sell._createdSeen or "sell: created -- none this session")
  local function call(fn, ...) if type(fn) == "function" then return tostring(fn(...)) end return "n/a" end
  -- Why an item will not post, or a post was not booked (final review M7): the items a late
  -- answer holds and for how long, how long an answer a guess ended may still be owed, whether a
  -- post now would be certain, the stock waiting for the auction house, and the requests out.
  local held, now = {}, time()
  for _, late in ipairs(GC.Sell._LiveLate()) do
    held[#held + 1] = ("%s %ds"):format(itemName(late.pin.itemID) or tostring(late.pin.itemID),
      GC.Sell.LATE_ANSWER_SECONDS - (now - late.at))
  end
  GC.Print(("post: late=%d [%s] owed=%ds certain=%s waiting=%d requestOut=%s confirmOwed=%s"):format(
    #held, table.concat(held, ", "), math.max(0, (GC.Sell._owedUntil or 0) - now), tostring(GC.Sell._Certain()),
    #(GC.Sell._waitingStock or {}), call(sniper.RequestOut),
    GC.PurchaseSlot and call(GC.PurchaseSlot.ConfirmOwed) or "n/a"))
  GC.Print(("sell walk: phase=%s index=%d/%d pending=%s awaiting=%s gen=%d progress=%ds ago waitingNoted=%s"):format(
    tostring(S.refresh.phase), S.refresh.index or 0, #(S.refresh.queue or {}),
    tostring(S.refresh.pending and S.refresh.pending.itemID), tostring(S.refresh.awaiting),
    S.refresh.generation or 0, time() - (S.refresh.progressAt or time()), tostring(S.refresh.waitingNoted)))
  -- `apiReady` is the CLIENT's own flag, read with no side effect -- see throttleReadyForDisplay.
  GC.Print(("slot: ahOpen=%s apiReady=%s searchCritical=%s busy=%s paging=%s quietZone=%s quietSince=%s"):format(
    call(sniper.IsAHOpen),
    tostring(throttleReadyForDisplay()),
    call(sniper.IsSearchCritical), call(sniper.IsBusy),
    sniper._bookPass and call(function() return sniper._bookPass:IsPaging() end) or "n/a",
    call(sniper._QuietZoneOpen), tostring(sniper._quietSince)))
  -- The bulk fill's own state: whether a press is still owed one, whether it went, whether it
  -- landed, and every gate the arbiter would hold it at -- so "the prices did not come at once"
  -- can be answered from a paste instead of guessed at.
  GC.Print(("bulk: wanted=%s sent=%s landed=%s outstanding=%s targets=%d view=%s keysOwner=%s keysOut=%s pendingStart=%s playerBusy=%s"):format(
    tostring(S.refresh.bulkWanted), tostring(S.refresh.bulkSent), tostring(S.refresh.bulkLanded),
    tostring(GC.Sell.BulkOutstanding()), #GC.Sell.BulkTargets(), call(sniper.CurrentView),
    tostring(sniper._keysOwner), call(sniper._KeysOutstanding),
    sniper._bookPass and call(function() return sniper._bookPass:PendingStart() end) or "n/a",
    GC.AuctionHouseTab and call(GC.AuctionHouseTab.PlayerIsBusy) or "n/a"))
  -- A cancel's own state, so "I pressed Cancel lot and the tab went dead" can be answered from a
  -- paste: what is armed and how far it got, whether a render is being held behind it, and
  -- which lots were sent for cancelling and whether the server ever confirmed them.
  local sent, confirmed = 0, 0
  for _, lot in pairs(GC.Sell.cancelledLots or {}) do
    if lot.confirmed then confirmed = confirmed + 1 else sent = sent + 1 end
  end
  GC.Print(("cancel: armed=%s stage=%s ready=%s lot=%s renderHeld=%s posting=%s removing=%s sentUnconfirmed=%d confirmed=%d requery=%s"):format(
    tostring(S.repostingRow ~= nil), tostring(S.repostingRow and S.repostingRow.repostStage),
    tostring(S.repostingRow and S.repostingRow.repostReady), tostring(S.repostPin and S.repostPin.auctionID),
    tostring(S.deferredRender), tostring(S.postingRow ~= nil), tostring(S.removingRow ~= nil),
    sent, confirmed, tostring(S.refresh.ownedWanted)))
  local status = UI.window and UI.window.status and UI.window.status.GetText and UI.window.status:GetText()
  GC.Print("status: " .. tostring(status))
  local t = GC.Util.throttleStats
  GC.Print(("throttle events: queued=%d dropped=%d ready=%d forcedSends=%d"):format(t.queued, t.dropped, t.ready, t.forced))
end

-- What the Sell services (GoldCap/Services/Sell) ask of this screen: GC.SellView's slots, filled
-- here once every function they name exists. The services call these and never reach a frame.
GC.SellView.render = function(...) return UI.List.RenderRows(...) end
GC.SellView.status = function(...) return UI.Dock.SetStatus(...) end
GC.SellView.paintQueue = function(...) return UI.Dock.PaintQueueButton(...) end
GC.SellView.paintCancel = function(...) return UI.Dock.PaintCancelButton(...) end
GC.SellView.paintDeck = function()
  if UI.container and UI.container.paintDeckSwitch then UI.container.paintDeckSwitch() end
end
GC.SellView.notePost = function(...) return GC.Sell._NotePost(...) end
GC.SellView.endPostNote = function(...) return GC.Sell._EndPostNote(...) end
GC.SellView.attached = function() return UI.container ~= nil end
-- nil until the tab is built, then its own shown flag: the two questions the services ask of it
-- ("is it built", "is it up") stay as distinct as `container ~= nil` and `container:IsShown()` were.
GC.SellView.isShown = function()
  if UI.container and UI.container.IsShown then return UI.container:IsShown() end
end
