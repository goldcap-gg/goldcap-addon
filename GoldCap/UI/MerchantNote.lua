local _, GC = ...

-- At a vendor: a short GoldCap note beside the vendor window when items in the bags fetch more on
-- the auction house than the vendor pays. Which items count, and by how much, is
-- Core/ForeverValue.lua's BagTotals (`gain`, `gainItems`) -- the same rule Road to 40, `/gc bags`
-- and the Sold tab already use: a stack the vendor pays something for, not bound, whose auction
-- house price after the 5% cut is higher. The price per item is the one its tooltip prints
-- (GC.Tooltip.Headline). Retail and WoW: Forever alike; with no GoldCap price for anything in the
-- bags there is nothing to say and no note. Read-only: it sells nothing.
GC.MerchantNote = GC.MerchantNote or {}
local N = GC.MerchantNote

local LAYOUT = { WIDTH = 220, PAD = 10, GAP = 4, X = 4, TITLE = 12, BODY = 11 }

-- The note's sentence for a BagTotals answer, or nil when nothing in the bags fetches more on the
-- auction house.
function N.Text(totals)
  local items = type(totals) == "table" and totals.gainItems or 0
  local gain = type(totals) == "table" and totals.gain or 0
  if type(items) ~= "number" or type(gain) ~= "number" or items < 1 or gain <= 0 then return nil end
  local coins = GC.Util.CoinText(gain)
  if items == 1 then
    return GC.L["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."]:format(coins)
  end
  return GC.L["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."]
    :format(items, coins)
end

-- An item's value as BagTotals reads it (`mv`), at the figure its tooltip prints.
function N.ValueFor(itemID)
  local unit = GC.Tooltip.Headline(GC.Data.GetItemValue(itemID))
  return unit and { mv = unit } or nil
end

local function build(host)
  local T = GC.Theme
  local f = T.Card(host, T.color.panel, T.color.border, true)
  f:SetWidth(LAYOUT.WIDTH)
  f:SetPoint("TOPLEFT", host, "TOPRIGHT", LAYOUT.X, 0)
  f.title = T.Label(f, LAYOUT.TITLE)
  f.title:SetPoint("TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  f.title:SetTextColor(T.color.gold[1], T.color.gold[2], T.color.gold[3])
  f.title:SetText("GoldCap")
  f.body = T.Label(f, LAYOUT.BODY)
  f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  f.body:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  f.body:SetWordWrap(true)
  f.body:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3])
  return f
end

-- Counts the bags again and shows the note, or hides it.
function N.Refresh()
  if not N._open then return end
  local host = _G.MerchantFrame
  if type(host) ~= "table" then return end
  local text = N.Text(GC.ForeverValue.RealBagTotals(N.ValueFor))
  if not text then
    if N._frame then N._frame:Hide() end
    return
  end
  local f = N._frame
  if not f then
    f = build(host)
    N._frame = f
  end
  f.body:SetText(text)
  -- The box grows with the sentence: every language's whole sentence shows, wrapped.
  f:SetHeight(LAYOUT.PAD + f.title:GetHeight() + LAYOUT.GAP + f.body:GetHeight() + LAYOUT.PAD)
  f:Show()
end

function N.OnMerchantShow()
  N._open = true
  N.Refresh()
end

function N.OnMerchantClosed()
  N._open = false
  if N._frame then N._frame:Hide() end
end

-- BAG_UPDATE_DELAYED: a sale or a buyback moved something.
function N.OnBagsChanged()
  if N._open then N.Refresh() end
end
