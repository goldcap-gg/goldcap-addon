-- What a row of the Sell list says on hover: the item's own tooltip with GoldCap's lines under
-- it, the selling mark's, and the help of the row's action button. Row.CreateRow wires each once
-- on the pooled frame and calls in here at hover time, so the text is always about what the row
-- holds then. Moved from UI/Sell/Row.lua as it was.
local _, GC = ...

local Theme = GC.Theme
local UI = GC.SellUI
local Row, ROW = UI.Row, UI.ROW

-- The selling mark's tooltip (Row.CreateRow): what the mark means for this row, why it is marked
-- when the player never chose (Deals bought it), and that a click changes it.
function ROW.markTooltip(owner, row)
  if not GameTooltip then return end
  local selling, position = row.markSelling == true, row.position
  GameTooltip:SetOwner(owner, Theme.TooltipAnchor(owner))
  if row.markDone then
    GameTooltip:AddLine(GC.Util.ClientText(GC.L["Done for this visit"]), 1, 0.82, 0)
    GameTooltip:AddLine(GC.Util.ClientText(GC.L["POST passes it by until you close the auction house. Click to have POST list it again."]),
      0.85, 0.85, 0.85, true)
    GameTooltip:Show()
    return
  end
  GameTooltip:AddLine(GC.Util.ClientText(selling and GC.L["Selling"] or GC.L["Not selling"]), 1, 0.82, 0)
  GameTooltip:AddLine(GC.Util.ClientText(selling and GC.L["POST lists it, and so does the key for posting the next item."]
    or GC.L["POST passes it by. Click the item to post it from the bar below."]), 0.85, 0.85, 0.85, true)
  local marks = GC.Sell._QueueOpts().marks
  if selling and position and type(marks) == "table" and marks[position.positionKey] == nil then
    -- Deals bought it, else a followed flip or gather group holds it (GC.PostQueue.Selling).
    local bought = type(position.sources) == "table" and (tonumber(position.sources.goldcap) or 0) > 0
    GameTooltip:AddLine(GC.Util.ClientText(bought and GC.L["Marked for you: you bought it on DEALS."]
      or GC.L["Marked for you: it is in a group you follow."]), 0.85, 0.85, 0.85, true)
  end
  GameTooltip:AddLine(GC.Util.ClientText(GC.L["Click to change."]), 0.6, 0.6, 0.6)
  GameTooltip:Show()
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
  ["Post"] = { "Post", { "Lists this item at the price on its row: the whole bag for a commodity, one stack for a regular item, or the number under HOW MANY.", "The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price." } },
  ["Cancel lot"] = { "Cancel lot", { "Cancels this live auction. It does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive.", "Asks for a second click to confirm." } },
  ["Cancel lot?"] = { "Confirm the cancel", { "Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags.", "The button waits a moment before it can be pressed, so this is never an accidental double-click." } },
  ["Remove"] = { "Remove this cost", { "Deletes a hand-entered cost you typed into Set cost, never a purchase GoldCap itself captured or matched to your mail.", "There is no undo. Clicking asks for a second click to confirm." } },
  ["Remove?"] = { "Confirm the removal", { "Clicking again deletes this hand-entered cost for good.", "A run of several purchases collapsed onto one line removes every one of them." } },
}
Row.ACTION_HELP = ACTION_HELP

-- The row's own tooltip (Row.CreateRow's OnEnter): a position's item, or a heading's facts.
function ROW.itemTooltip(row)
  -- Rows are pooled and rebound every render, so the item tooltip is wired once (Row.CreateRow)
  -- and reads whatever position the row currently holds. Hooking it per render would stack.
  if GameTooltip and row.kind == "position" and row.position and row.position.itemID then
    -- Outside the window, never over it -- a row's own item tooltip used to cover the deck
    -- it is describing (Theme.ItemTooltipOutside; see UI/Theme.lua's own comment on it).
    Theme.ItemTooltipOutside(row, UI.window)
    -- A variant is the stack itself -- its item level, its bonuses, its pet -- not the base item
    -- (for every caged pet, "Pet Cage"): the bag slot, else the lot's own link (review M9).
    -- GoldCap's own block under this tooltip (UI/Tooltip.lua) reads the site's figure for the
    -- item -- every item level at once, every pet at once. Under a variant row it says there is
    -- none for this one instead (review N7), reading which variant off the tooltip's owner --
    -- this row -- so it can never outlive the row onto some other item's tooltip (NI-B).
    row.goldcapVariant = row.position.variantKind
    if row.goldcapVariant == "level" and not GC.SellViewModel.LevelVariant(row.position) then
      row.goldcapVariant = nil
    end
    local stack = row.position.quoteKey and row.position.bagStacks and row.position.bagStacks[1]
    local lot = row.position.quoteKey and row.position.ownedLots and row.position.ownedLots[1]
    if stack and GameTooltip.SetBagItem then GameTooltip:SetBagItem(stack.bag, stack.slot)
    elseif lot and lot.itemLink and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(lot.itemLink)
    elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(row.position.itemID) end
    -- Flags painted onto the row at the same time as the cells they describe (MARKET/UNIT's
    -- fallback, the item cell's "· not on hand" suffix) -- read here rather than re-derived,
    -- so the tooltip can never disagree with what the row is actually showing.
    if row.marketFallback then
      GameTooltip:AddLine(GC.Util.ClientText(GC.L["~ goldcap.gg market value, no live quote yet"]), 0.85, 0.85, 0.85, true)
    end
    if row.notOnHand then
      GameTooltip:AddLine(GC.Util.ClientText(GC.L["Not on hand: the stock is in the mail, the bank, or on another character"]),
        0.85, 0.85, 0.85, true)
    end
    UI.fmt.ruleTooltip(row.position)
    GameTooltip:Show()
  elseif GameTooltip and (row.kind == "group" or row.kind == "batch" or row.kind == "section")
      and row.groupHint and row.groupHint ~= "" then
    GameTooltip:SetOwner(row, Theme.TooltipAnchor(row))
    -- A fact a line. The sentence is a run of facts joined by one separator, and wrapped as
    -- a paragraph it broke mid-fact ("bought 29 / Aug"), which is harder to read than the row.
    local first = true
    for fact in (row.groupHint .. " · "):gmatch("(.-) · ") do
      local factLine = GC.Util.ClientText(fact)
      if first then GameTooltip:AddLine(factLine, 1, 1, 1) else GameTooltip:AddLine(factLine, 0.85, 0.85, 0.85) end
      first = false
    end
    GameTooltip:Show()
  end
end

-- The action button's help (Row.CreateRow), chosen at hover time from the label the button
-- currently carries, so it always describes the action actually on offer.
function ROW.actionTooltip(button)
  if not GameTooltip then return end
  -- helpKey is the English action name the row set; button.label is display text and may be
  -- in any language. Fall back to the label for buttons that predate the key.
  local help = ACTION_HELP[button.helpKey or ""]
    or ACTION_HELP[button.label]
    or ACTION_HELP[(button.label or ""):gsub("%s*%(.*", "")]
  if not help then return end
  -- Not ANCHOR_RIGHT: this button sits in the far-right column of a window that can fill
  -- the screen, and a tooltip told to grow rightward from there gets clamped back over the
  -- list, the header and the button itself. Theme reads where the button is and opens the
  -- tooltip on the side that has room.
  GameTooltip:SetOwner(button, Theme.TooltipAnchor(button))
  -- Translated at READ time -- see ACTION_HELP's own comment for why the table itself
  -- cannot hold GC.L lookups.
  GameTooltip:AddLine(GC.Util.ClientText(GC.L[help[1]]), 1, 0.82, 0)
  for _, line in ipairs(help[2]) do
    GameTooltip:AddLine(GC.Util.ClientText(GC.L[line]), 0.85, 0.85, 0.85, true)
  end
  GameTooltip:Show()
end
