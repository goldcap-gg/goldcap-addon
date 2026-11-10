local _, GC = ...

GC.Theme = GC.Theme or {}
local T = GC.Theme

-- The names every window reads, drawn from UI/Kit/Tokens.lua. Each keeps its meaning: `red` and
-- `green` are what TEXT wears (a loss, a profit), `redFill` is what a BUTTON is filled with,
-- `cost` is a price paid, `hover` is the gold wash a row wears under the cursor, `watch` is a
-- state that persists while you look elsewhere (the player's own lots) and so has its own colour.
local Tokens = GC.Kit.Tokens
local K = Tokens.color
local rgb = Tokens.rgb
T.color = {
  bg      = rgb("windowBottom"),
  panel   = rgb("windowTop"),
  panelHi = rgb("raised"),
  border  = K.glassBorder,
  gold    = rgb("gold"),
  goldHi  = rgb("goldText"),
  fg      = rgb("text1"),
  fgMuted = rgb("text2"),
  fgDim   = rgb("text3"),
  red     = rgb("loss"),
  redFill = rgb("lossFill"),
  green   = rgb("profit"),
  cost    = rgb("cost"),
  zebra   = Tokens.alpha("ink", 0.035),
  hover   = Tokens.alpha("gold", 0.16),
  watch   = rgb("yours"),
}

T.tier = {
  HOT     = rgb("tierHot"),
  GOOD    = rgb("tierGood"),
  WATCH   = rgb("tierWatch"),
  SUSPECT = rgb("tierSuspect"),
}

T.pad = { xs = 4, s = 8, m = 12, l = 16 }
T.ROW_H = 32

T.MEDIA = GC.Kit.MEDIA
T.RAIL_W = 76

-- Drawn additively in the HIGHLIGHT layer by the engine while the cursor is over a button, so
-- it must stay subtle: it lands on top of a gold fill as readily as on bare panel.
local HOVER_WASH = Tokens.alpha("gold", 0.18)

-- QuietScrollBar: UIPanelScrollFrameTemplate's scrollbar without Blizzard's chrome -- the two
-- arrow buttons and the knurled thumb floated beside panels drawn in none of that style (seen
-- in game beside the Sell list AND its detail panel at once). The bar itself stays: the wheel
-- and a drag of the thumb still scroll. The arrows are made invisible and unclickable rather
-- than hidden, because the template's own scripts Enable/Disable them and anchor the track
-- between them. Every part is optional -- which keys a scrollbar carries has changed between
-- client versions, and a missing one is simply skipped.
function T.QuietScrollBar(scroll)
  local bar = scroll and scroll.ScrollBar
  if not bar then return end
  for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    local button = bar[key]
    if button then
      if button.SetAlpha then button:SetAlpha(0) end
      if button.EnableMouse then button:EnableMouse(false) end
    end
  end
  for _, key in ipairs({ "Top", "Middle", "Bottom", "Background", "trackBG" }) do
    if bar[key] and bar[key].Hide then bar[key]:Hide() end
  end
  local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
  if thumb and thumb.SetTexture then
    -- bar.png at its own slice (2), the same pill the Sell book's depth bars are drawn with.
    thumb:SetTexture(T.MEDIA .. "bar.png")
    if thumb.SetTexCoord then thumb:SetTexCoord(0, 1, 0, 1) end
    if thumb.SetTextureSliceMargins then thumb:SetTextureSliceMargins(2, 2, 2, 2) end
    if thumb.SetVertexColor then thumb:SetVertexColor(K.ink[1], K.ink[2], K.ink[3], 0.22) end
    if thumb.SetSize then thumb:SetSize(4, 36) end
  end
end

-- Rail: the window's primary navigation. Big targets on purpose -- the old
-- 50x18 ghost tabs were the main menu and read as decoration. Active state
-- reuses setTabActive's functional contract: the current view's button is
-- Disable()d (not clickable), visuals ride on top of that.
local RAIL_BTN_W, RAIL_BTN_H = 60, 54
local RAIL_FILL = Tokens.alpha("gold", 0.12)
local RAIL_RING = Tokens.alpha("gold", 0.38)
local RAIL_GLOW = Tokens.alpha("gold", 0.12)
local BADGE_TEXT = K.onGold

function T.RailButton(parent, iconName, labelText)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(RAIL_BTN_W, RAIL_BTN_H)
  b:RegisterForClicks("LeftButtonUp")
  -- Required for the HIGHLIGHT layer, exactly as in T.Button.
  b:EnableMouse(true)

  -- Art is chosen here, as the button is built; the skin is applied before any window exists.
  local skin = GC.Kit.Skins.Current()
  local plate = T.Plate()
  -- A skin without a glow (Pixel, Parchment, Classic) draws no halo at all.
  if skin.glow then b.glow = T.Glow(b, RAIL_GLOW, 10) end
  local washFile, washSlice
  local client = plate and plate.client
  if client then
    -- Classic: the client's quickslot frame round the icon, its hilight when selected (below).
    b.plate = plate
  elseif plate then
    -- A framed plate: the baked ring (untinted, it carries its own colours) over a vertical
    -- gradient, drawn all the time and lit when the button is the selected one.
    b.plate = plate
    b.plateFill = T.GradientFill(b, K.plateTop, K.plateBottom, plate.fill, plate.fillSlice, 32)
    b.ring = T.SlicedTexture(b, "BORDER", plate.ring, { 1, 1, 1, 1 }, plate.ringSlice) -- untinted
    b.ring:SetAllPoints()
    washFile, washSlice = plate.fill, plate.fillSlice
  elseif skin.railCard then
    -- Parchment: the selected button is a slip of the paper (skin.railCard), shown only when selected.
    local card, radius = skin.railCard, skin.railRadius or skin.radius[3]
    washFile, washSlice = T.Art("card", radius), T.ArtSlice("card", radius)
    b.card = T.GradientFill(b, card.top, card.bottom, washFile, washSlice, 64)
    b.ring = T.SlicedTexture(b, "BORDER", T.Art("ring", radius), card.ring, washSlice)
    b.ring:SetAllPoints()
    b.edge = T.SlicedTexture(b, "BORDER", T.Art("ring", radius), card.edge, washSlice)
    b.edge:SetPoint("TOPLEFT", -1, 1)
    b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  else
    local radius = skin.railRadius or skin.radius[3]
    washFile, washSlice = T.Art("card", radius), T.ArtSlice("card", radius)
    b.bg = T.SlicedTexture(b, "BACKGROUND", washFile, RAIL_FILL, washSlice)
    b.bg:SetAllPoints()
    b.ring = T.SlicedTexture(b, "BORDER", T.Art("ring", radius), RAIL_RING, washSlice)
    b.ring:SetAllPoints()
  end
  if skin.railBar then
    -- Pixel: the selected button is marked by a bar on its left edge, not a halo.
    b.bar = T.Solid(b, "BORDER", K.gold)
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
  end

  b.icon = b:CreateTexture(nil, "ARTWORK")
  if client then
    -- The client's item icon in its quickslot frame, 40px, trimmed of the icon's own border.
    b.icon:SetTexture(T.CLASSIC.icons[iconName])
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetSize(40, 40)
    b.icon:SetPoint("TOP", 0, -1)
    b.iconFrame = T.ClientSliced(b, "OVERLAY", T.CLASSIC.quickslot)
    b.iconFrame:SetAllPoints(b.icon)
  else
    T.SetIcon(b.icon, iconName)
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("TOP", 0, -8)
  end

  b.text = T.Heading(b, client and 11 or 9.5)
  if client then
    -- Classic: 2px under the icon, as on the board, so a larger font scale grows the label down
    -- into the gap between buttons, never up into the icon and its glow.
    b.text:SetPoint("TOP", b.icon, "BOTTOM", 0, -2)
  else
    b.text:SetPoint("BOTTOM", 0, 7)
  end
  b.text:SetText(labelText)

  -- The same rounded card as the active fill, not a flat colour: a SetColorTexture wash filled
  -- the button's whole square, so hovering a rail button drew a square around the rounded
  -- plate the active one wears (owner, Forever beta 2026-10-01).
  if client then
    -- The client's hilight over the 40px icon, at its size as on the client's own action buttons:
    -- under the cursor, and kept on the selected one. At 46px it glowed onto the label below.
    local function hilight(layer)
      local tx = b:CreateTexture(nil, layer)
      tx:SetTexture(T.CLASSIC.hilight)
      tx:SetBlendMode("ADD")
      tx:SetSize(40, 40)
      tx:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
      return tx
    end
    b.highlightTexture = hilight("HIGHLIGHT")
    b.selected = hilight("OVERLAY")
  else
    b.highlightTexture = T.SlicedTexture(b, "HIGHLIGHT", washFile, HOVER_WASH, washSlice)
    b.highlightTexture:SetAllPoints()
    b.highlightTexture:SetBlendMode("ADD")
  end

  -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
  -- can still raise a tooltip), so the wash is hidden here instead of guarded in a script.
  -- Hide/Show, never SetAlpha: on a texture, SetAlpha writes the same alpha SetVertexColor set,
  -- so SetAlpha(1) on the way back turned the 18% wash into solid gold -- a tab the player had
  -- visited and left lit up bright yellow under the cursor (owner, Forever beta 2026-10-01).
  b:SetScript("OnDisable", function() b.highlightTexture:Hide() end)
  b:SetScript("OnEnable", function() b.highlightTexture:Show() end)

  b.badge = CreateFrame("Frame", nil, b)
  b.badge:SetPoint("TOPRIGHT", -4, -4)
  -- badge.png/T.SLICE.badge, not card.png/T.SLICE.card or plaque.png/T.SLICE.plaque: the badge is
  -- 14px tall and both of those margins exceed half that (see T.SLICE.badge's own comment).
  b.badge.bg = T.ShapeTexture(b.badge, "BACKGROUND", "chip", T.color.gold)
  b.badge.bg:SetAllPoints()
  b.badge.text = T.Heading(b.badge, 9.5)
  b.badge.text:SetPoint("CENTER")
  b.badge.text:SetTextColor(BADGE_TEXT[1], BADGE_TEXT[2], BADGE_TEXT[3])
  b.badge:Hide()

  function b:SetBadge(count)
    if count then
      b.badge.text:SetText(tostring(count))
      b.badge:SetWidth((14 + 6 * #tostring(count)) * T.Scale())
      -- Item 7 (addon polish batch): height scales the same way -- it used to stay a fixed 14,
      -- distorting the pill's aspect ratio at the font-scale slider's extremes.
      b.badge:SetHeight(14 * T.Scale())
      b.badge:Show()
    else
      b.badge:Hide()
    end
  end

  function b:SetActive(active)
    local c = active and K.railActive or K.railIdle
    if client then
      -- The client's icon keeps its own colours.
      b.icon:SetVertexColor(1, 1, 1, 1) -- untinted
    else
      b.icon:SetVertexColor(c[1], c[2], c[3], 1)
    end
    b.text:SetTextColor(c[1], c[2], c[3], 1)
    if client then
      b.selected:SetShown(active)
    elseif b.plateFill then
      -- The plate stays; only its fill lights.
      if active then
        T.PaintGradientFill(b.plateFill, K.plateOnTop, K.plateOnBottom)
      else
        T.PaintGradientFill(b.plateFill, K.plateTop, K.plateBottom)
      end
    elseif b.card then
      for _, piece in ipairs(b.card) do piece:SetShown(active) end
      b.ring:SetShown(active)
      b.edge:SetShown(active)
    else
      if active then b.bg:Show(); b.ring:Show() else b.bg:Hide(); b.ring:Hide() end
    end
    if b.glow then
      if active then b.glow:Show() else b.glow:Hide() end
    end
    if b.bar then
      if active then b.bar:Show() else b.bar:Hide() end
    end
    if active then b:Disable() else b:Enable() end
  end
  b:SetActive(false)

  return b
end

function T.Rail(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(T.RAIL_W)
  -- card_left.png: left corners rounded to match the window card's own radius 12, right edge
  -- square (it borders content, not window chrome) -- a flat rectangle here would poke square
  -- corners past the window's rounded top-left/bottom-left arcs. Cut at the applied skin's window
  -- radius (card_left_r<N>.png), so the corners stay the window's in every skin.
  -- The skin's rail fill (K.railTop to K.railBottom): flat, as it always was, where the two are the
  -- same; else a vertical gradient cut from the same art (T.GradientFill).
  local skin = GC.Kit.Skins.Current()
  local radius = skin.radius[1]
  local top, bottom = K.railTop, K.railBottom
  local flat = top[1] == bottom[1] and top[2] == bottom[2] and top[3] == bottom[3] and top[4] == bottom[4]
  if flat then
    frame.fill = T.SlicedTexture(frame, "BACKGROUND", T.Art("cardLeft", radius), top, T.ArtSlice("cardLeft", radius))
    frame.fill:SetAllPoints()
  else
    frame.fill = T.GradientFill(frame, top, bottom, T.Art("cardLeft", radius), 16, 64)
  end
  -- Docked, a skin's window has square corners (UI/Kit/Card.lua's SetDocked), and so has its rail;
  -- goldcap's keeps its rounded ones, as it always has.
  local function setDocked(docked)
    if skin.frame == "hairline" then return end
    if flat then
      local r = docked and 0 or radius
      local margin = T.ArtSlice("cardLeft", r)
      frame.fill:SetTexture(T.Art("cardLeft", r))
      frame.fill:SetTextureSliceMargins(margin, margin, margin, margin)
    else
      T.SquareCorners(frame.fill, docked, 16, 64)
    end
  end
  local edge = frame:CreateTexture(nil, "BORDER")
  edge:SetColorTexture(K.hairline[1], K.hairline[2], K.hairline[3], K.hairline[4])
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  edge:SetWidth(1)

  -- The GoldCap mark itself -- the coin in the crosshair the site, the store pages and the
  -- AddOns list show -- rather than a gold plate with a "G" on it (owner, 2026-10-01). Same
  -- file as the .toc's IconTexture, full colour on transparent, so it is drawn as it is and
  -- never tinted. 40px, where the plate was 32: the crosshair's arms take the outer ring, and
  -- at 32 the coin inside was smaller than a rail icon. The gap under it shrinks by the same
  -- 8px (LOGO_GAP) so the buttons below stay where they were.
  local logo = CreateFrame("Frame", nil, frame)
  logo:SetSize(40, 40)
  logo:SetPoint("TOP", 0, -16)
  logo.mark = logo:CreateTexture(nil, "ARTWORK")
  logo.mark:SetTexture(T.MEDIA .. "GoldCap")
  logo.mark:SetAllPoints()
  -- A soft gold glow behind the mark, the window's one warm light; none in a skin without a glow.
  if skin.glow then logo.glow = T.Glow(logo, { K.gold[1], K.gold[2], K.gold[3], 0.22 }, 10) end
  local LOGO_GAP = 14

  local buttons = {}
  local order = {
    { key = "deals", icon = "deals", label = "DEALS" },
    { key = "sell", icon = "sell", label = "SELL" },
    { key = "sold", icon = "sold", label = "SOLD" },
    { key = "buy", icon = "buy", label = "BUY" },
  }
  local prev = logo
  for i, item in ipairs(order) do
    local b = T.RailButton(frame, item.icon, item.label)
    b:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -LOGO_GAP or -T.pad.s)
    buttons[item.key] = b
    prev = b
  end

  -- "badge" rounded (margin 6, no ring -- see ROUNDED_BUTTON's own comment): 28px is the same
  -- size class as T.RailButton's own badge, and SetVariant("active") below (SettingsFrame.lua)
  -- needs a rounded fill to switch, not the square T.EdgeBorder look a bare "ghost" button has.
  local gear = T.Button(frame, "ghost", "badge")
  gear:SetSize(28, 28)
  gear:SetPoint("BOTTOM", 0, 14)
  gear.icon = gear:CreateTexture(nil, "ARTWORK")
  local framed = T.Plate()
  if framed and framed.client then
    gear.icon:SetTexture(T.CLASSIC.icons.gear) -- the client's own icon, in its own colours
    gear.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    gear.clientIcon = true -- SettingsFrame's tint of the icon leaves it alone
  else
    T.SetIcon(gear.icon, "gear", T.color.fgDim)
  end
  gear.icon:SetSize(17, 17)
  gear.icon:SetPoint("CENTER")

  -- Docked into the Auction House the host's portrait overhangs the rail's top-left corner;
  -- SetDocked pushes the logo (and the nav chain anchored to it) below it. The gear is
  -- bottom-anchored and unaffected.
  local function setTopInset(px)
    logo:ClearAllPoints()
    logo:SetPoint("TOP", 0, -(16 + (px or 0)))
  end

  return { frame = frame, buttons = buttons, gear = gear, logo = logo, SetTopInset = setTopInset,
    SetDocked = setDocked }
end

-- TitleBar: 32px drag region at top of `frame`, title Label 13; close sits at the outer
-- top-right corner, gear sits immediately inboard (left) of close.
function T.TitleBar(frame, titleText)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(32)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function()
    -- A docked window (GC.Sniper.SetDocked flips SetMovable off) must not be draggable, and
    -- StartMoving on an immovable frame is a Lua error, not a no-op.
    if frame:IsMovable() then frame:StartMoving() end
  end)
  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  bar.title = T.Heading(bar, 14)
  bar.title:SetPoint("LEFT", bar, "LEFT", T.pad.m, 0)
  bar.title:SetText(titleText or "")
  bar.title:SetTextColor(K.text1[1], K.text1[2], K.text1[3], 1)

  local close = T.Button(bar, "ghost")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -T.pad.s, -T.pad.xs)
  close.icon = close:CreateTexture(nil, "ARTWORK")
  close.icon:SetSize(12, 12)
  close.icon:SetPoint("CENTER")
  T.SetIcon(close.icon, "close", K.text3)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  local gear = T.Button(bar, "ghost")
  gear:SetSize(20, 20)
  gear:SetPoint("RIGHT", close, "LEFT", -T.pad.xs, 0)
  gear:SetLabel("*")

  -- `title` is part of the return on purpose: docked mode (GC.Sniper.SetDocked) blanks and
  -- restores it. It shipped without this field once, and the caller's nil-guard turned the
  -- missing key into a silently-still-visible duplicate title.
  -- `bar` (the title bar FRAME) is returned too because a caller may need to re-anchor the
  -- title relative to it (e.g. to make room for a rail on the left) -- the RETURN TABLE
  -- itself is a plain Lua table, not a region, and must never be passed to SetPoint.
  return { gear = gear, close = close, title = bar.title, bar = bar }
end

-- Reagent quality, as the game itself draws it.
--
-- The first attempt hardcoded `Professions-ChatIcon-Quality-Tier1..5`, which are
-- the Dragonflight diamonds. The client draws something else now, so the list
-- showed two diamonds beside an item whose own tooltip showed a different mark
-- entirely -- the addon disagreeing with the game about the same item.
--
-- The lesson is not "use the newer atlas names". It is that an atlas name is art
-- and art is versioned, so hardcoding one means being wrong again at the next
-- expansion. The tooltip already renders the correct icon for whatever build is
-- running, and C_TooltipInfo hands us that tooltip as data with its escape
-- sequences intact -- so the icon is lifted from there and rescaled, and this
-- file never needs to know what the art is called.
--
-- Matching is on the atlas NAME, never on the label beside it: atlas names are
-- not localised and the label is. "quality" or "tier" covers every naming the
-- art has used so far; a client that matches neither shows no pip at all, which
-- is honest -- an absent mark costs nothing, a wrong one contradicts the game.
--
-- There is deliberately no hardcoded fallback atlas here. There used to be
-- one, kept for a client that supposedly still carried the old art -- but
-- Blizzard does not delete atlas entries it stops using, so the fallback's own
-- existence check (C_Texture.GetAtlasInfo) kept succeeding long after the game
-- moved on to different art, and whenever it won a race against a tooltip that
-- simply had not warmed up yet, the wrong icon got cached for the rest of the
-- session -- the exact contradiction this file exists to avoid. A guess that
-- is sometimes wrong is worse than the pip being briefly absent while the
-- tooltip catches up, so an unresolved lookup is left unresolved instead of
-- being answered from memory.
local QUALITY_CACHE = {}

-- `read` is C_TooltipInfo's GetItemByID (an item id) or GetHyperlink (an item's link).
local function atlasFromTooltip(read, arg)
  local fn = C_TooltipInfo and C_TooltipInfo[read]
  if not fn then return nil end
  local ok, data = pcall(fn, arg)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  for _, line in ipairs(data.lines) do
    for _, text in ipairs({ line.leftText, line.rightText }) do
      if type(text) == "string" then
        for atlas in text:gmatch("|A:([^:|]+):") do
          local name = atlas:lower()
          if name:find("quality", 1, true) or name:find("tier", 1, true) then return atlas end
        end
      end
    end
  end
  return nil
end

-- Cached by what was read: an item id, or a link (a crafted copy's quality is its own).
local function atlasForQuality(read, arg)
  local cached = QUALITY_CACHE[arg]
  if cached ~= nil then return cached end
  local atlas = atlasFromTooltip(read, arg)
  if atlas then
    QUALITY_CACHE[arg] = atlas
  end
  -- Nothing is remembered when the tooltip has no answer yet -- that is
  -- temporary, so the next call is free to try again once it warms up.
  return atlas
end

-- Whether the client's `name` call gives `arg` a crafting quality: one that is missing or throws
-- answers nothing.
local function hasQuality(name, arg)
  local api = C_TradeSkillUI
  local call = type(api) == "table" and api[name] or nil
  if not call then return false end
  local ok, quality = pcall(call, arg)
  return ok and type(quality) == "number"
end

--- The atlas the client draws for `itemID`'s crafting quality, or nil when the item has no quality
-- tier (most items do not) or the client will not say what to draw. A reagent's quality is asked
-- by the item id, as the auction house's commodity rows ask it (GetItemReagentQualityByItemInfo,
-- Blizzard_AuctionHouseSharedTemplates.lua). Crafted gear carries its quality on each copy, in the
-- link, and every copy shares the id: it is asked only with the copy's `link` in hand, as
-- Blizzard's crafting order forms ask it (GetItemCraftedQualityByItemInfo(link),
-- Blizzard_ProfessionsCustomerOrdersForm.lua, Blizzard_ProfessionsCrafterOrderView.lua), and its pip
-- read from that link's tooltip. A bare id never asks it.
function T.QualityAtlas(itemID, link)
  if type(itemID) ~= "number" then return nil end
  if hasQuality("GetItemReagentQualityByItemInfo", itemID) then return atlasForQuality("GetItemByID", itemID) end
  if type(link) == "string" and link ~= "" and hasQuality("GetItemCraftedQualityByItemInfo", link) then
    return atlasForQuality("GetHyperlink", link)
  end
  return nil
end

--- The quality of `itemID` as an inline atlas escape, or "" when the item has no
-- quality tier (most items do not) or the client will not say what to draw.
function T.QualityMarkup(itemID, size)
  local atlas = T.QualityAtlas(itemID)
  if not atlas then return "" end
  size = size or 14
  return ("|A:%s:%d:%d|a"):format(atlas, size, size)
end

local skinQualities = {}

--- The applied skin's colour for item quality `quality` ({ r, g, b, hex = "|cff......", color }), or
-- nil when the skin sets none (only the skins whose window is light, or whose blue the game's does
-- not read on, do: Skins.lua `quality`). Made once per skin and quality.
function T.SkinQuality(quality)
  local skin = GC.Kit.Skins.Current()
  local value = skin.quality and skin.quality[quality]
  if not value then return nil end
  local made = skinQualities[skin.id]
  if not made then made = {}; skinQualities[skin.id] = made end
  if not made[quality] then
    local c = GC.Kit.Tokens.hex(value)
    made[quality] = { r = c[1], g = c[2], b = c[3], hex = "|cff" .. value:lower(),
      color = _G.CreateColor and _G.CreateColor(c[1], c[2], c[3], 1) or nil }
  end
  return made[quality]
end

--- The colour for an item's quality ({ r, g, b, hex, color }): the applied skin's own where it sets
-- one, else the game's (ITEM_QUALITY_COLORS), for text on one of GoldCap's windows.
--
-- By item (an id, link or name the client takes): uncommon and better only; nil for common and poor,
-- whose colours are no brighter than the interface's own text, and when the client will not say.
--
-- With `isQuality`, `quality` is the quality number itself (Enum.ItemQuality; an id can be as small
-- as one) and every quality has a colour, nil only when the game has none for it.
--
-- `onBlizzard`: the text is on a Blizzard surface (a tooltip, a menu), which keeps the game's
-- colour in every skin.
function T.QualityColor(quality, isQuality, onBlizzard)
  if not quality then return nil end
  if not isQuality then
    local api = _G.C_Item and _G.C_Item.GetItemQualityByID
    if not api then return nil end
    local ok, found = pcall(api, quality)
    if not ok or type(found) ~= "number" or found < 2 then return nil end
    quality = found
  end
  local skinned = not onBlizzard and T.SkinQuality(quality)
  if skinned then return skinned end
  return _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] or nil
end

--- `name` as a list shows an item: in its item quality's colour (uncommon and better -- the
-- game's colour for common is pure white, brighter than anything else on these panels, so a
-- common name stays in the interface's own foreground) with its reagent-tier pip AFTER it, so
-- names start on one edge down a list. `name` unchanged when the client knows neither.
function T.WithQuality(name, itemID, size, onBlizzard)
  local label = tostring(name)
  local colour = T.QualityColor(itemID, false, onBlizzard)
  if colour and type(colour.hex) == "string" then label = colour.hex .. label .. "|r" end
  local markup = T.QualityMarkup(itemID, size)
  if markup == "" then return label end
  return label .. " " .. markup
end

--- The GameTooltip anchor that opens a tooltip from `owner` into the part of the screen
-- that has room for it.
--
-- SetOwner's ANCHOR_RIGHT pins the tooltip's bottom-left corner to the owner's top-right,
-- so it grows up and to the right. That is empty space for a control on the left of the
-- screen and no space at all for one in the right-hand column of a window that fills it:
-- the client clamps the tooltip back inside the screen, which drags it left across the
-- list it describes and over the very button under the cursor, and a long body runs into
-- the top edge the same way. So the side is chosen from where the owner sits -- leftward
-- in the right half of the screen, downward in the top half -- and the tooltip lands
-- beside the control every time.
--
-- GetCenter answers in the owner's own scaled space, and the Sniper window carries its own
-- scale, so both centres are brought to screen pixels before they are compared. Falls back
-- to ANCHOR_RIGHT wherever a position cannot be read: a frame with no anchors yet, or the
-- headless test bed with no UIParent.
function T.TooltipAnchor(owner)
  local screen = UIParent
  if not (owner and owner.GetCenter and screen and screen.GetCenter) then return "ANCHOR_RIGHT" end
  local x, y = owner:GetCenter()
  local midX, midY = screen:GetCenter()
  if not (x and y and midX and midY) then return "ANCHOR_RIGHT" end
  local ownerScale, screenScale = owner:GetEffectiveScale(), screen:GetEffectiveScale()
  local right = x * ownerScale > midX * screenScale
  local top = y * ownerScale > midY * screenScale
  if right then return top and "ANCHOR_BOTTOMLEFT" or "ANCHOR_LEFT" end
  return top and "ANCHOR_BOTTOMRIGHT" or "ANCHOR_RIGHT"
end

-- How much horizontal room an item tooltip needs beside the window before T.ItemTooltipOutside
-- decides the right edge has space for it. Not measured off the real tooltip (its width
-- depends on the item's own name/quality/flavor text, none of which is known before
-- SetItemByID runs) -- 330 is a deliberately generous upper estimate so the check fails
-- toward the side that is SURE to have room rather than clipping against the screen edge.
local ITEM_TOOLTIP_WIDTH = 330

--- Opens GameTooltip beside `windowFrame` -- its right edge, or its left edge when the right
-- has no room -- never inside it. For an ITEM tooltip (SetItemByID), whose body can run long
-- enough to cover the very row that opened it if it were anchored to the row the ordinary way.
--
-- `rowFrame` is the hovered row; the tooltip's TOP lands level with the row's own top (read
-- off GetTop(), not GetCenter() -- a multi-line item tooltip grows DOWN from its anchor, so
-- top-aligning is what keeps it beside the row that triggered it instead of drifting below).
-- Whether the right edge has room is windowFrame's own right edge, converted to screen pixels
-- via GetEffectiveScale() (the window carries its own scale, see T.SetScale) and compared
-- against the screen's, the same coordinate-space conversion T.TooltipAnchor above uses.
--
-- Falls back to ANCHOR_RIGHT off `rowFrame` when either frame lacks real geometry -- a frame
-- with no anchors yet, or the headless test bed with no UIParent.
function T.ItemTooltipOutside(rowFrame, windowFrame)
  local screen = UIParent
  local ready = rowFrame and rowFrame.GetTop and windowFrame and windowFrame.GetTop
    and windowFrame.GetRight and windowFrame.GetEffectiveScale
    and screen and screen.GetRight and screen.GetEffectiveScale
  local rowTop = ready and rowFrame:GetTop()
  local windowTop = ready and windowFrame:GetTop()
  local windowRight = ready and windowFrame:GetRight()
  local screenRight = ready and screen:GetRight()

  if not (rowTop and windowTop and windowRight and screenRight) then
    GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
    return
  end

  GameTooltip:SetOwner(rowFrame, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()

  local windowScale, screenScale = windowFrame:GetEffectiveScale(), screen:GetEffectiveScale()
  local fitsRight = (windowRight * windowScale + ITEM_TOOLTIP_WIDTH) <= (screenRight * screenScale)
  local yOffset = rowTop - windowTop

  if fitsRight then
    GameTooltip:SetPoint("TOPLEFT", windowFrame, "TOPRIGHT", 8, yOffset)
  else
    GameTooltip:SetPoint("TOPRIGHT", windowFrame, "TOPLEFT", -8, yOffset)
  end
end
