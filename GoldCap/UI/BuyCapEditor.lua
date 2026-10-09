local _, GC = ...

-- BUY 2.0's price box: the player types the most one unit of a line may cost. A popup the addon's
-- own way (UI/Sell/Toolbar.lua's search well is the model for the box): a background, a strata above
-- the list it covers, and its own mouse, so a click aimed at it never falls through to a row.
-- Parsing is GC.Util.ParseMoney's -- a bare number is gold, as in every other GoldCap box -- and the
-- preview shows the amount in coins before Set, because "90" meaning 90 gold is exactly the
-- surprise a preview exists for. Every line of it wraps rather than being cut, and the popup
-- grows to what it says (layout).
--
-- The same popup asks the BUY tab's two other questions (UI/BuyLists.lua): a list's name (`text`,
-- the box as wide as the popup, whatever is typed accepted) and "delete this list?" (`box = false`,
-- a title and two buttons). One popup in the kit, never a Blizzard StaticPopup.
GC.BuyCapEditor = {}

local W = { WIDTH = 280, PAD = 10, BOX_W = 130, BOX_H = 22, BUTTON_H = 24, BUTTON_MIN = 72 }

-- The cap as a player would type it back: "12g 50s", "1s 40c", "91c". Plain letters, never coin
-- icons -- this is what goes INTO the box, and an icon escape is not something anybody can edit.
local function plain(copper)
  copper = math.max(0, math.floor(tonumber(copper) or 0))
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = GC.Util.IntText(g) .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

local frame

local function measuredHeight(fs)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return type(h) == "number" and math.ceil(h) or 12
end

-- A button as wide as its label in the player's language, never under W.BUTTON_MIN.
local function fitButton(btn)
  local fs = btn.text
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(width) ~= "number" then return end
  btn:SetWidth(math.max(W.BUTTON_MIN, math.ceil(width) + 2 * GC.Theme.pad.m))
end

-- Title, box, preview and buttons top to bottom, the popup as tall as their wrapped text.
local function layout()
  local pad = W.PAD
  local inner = W.WIDTH - 2 * pad
  frame.title:SetWidth(inner)
  frame.preview:SetWidth(inner)
  local titleH = measuredHeight(frame.title)
  frame.box:ClearAllPoints()
  frame.box:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + 8, -(pad + titleH + 8))
  local previewH = (frame.preview:GetText() or "") ~= "" and measuredHeight(frame.preview) or 0
  frame.preview:ClearAllPoints()
  frame.preview:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(pad + titleH + 6 + W.BOX_H + 6))
  fitButton(frame.set)
  fitButton(frame.cancel)
  local boxH = frame.asks and (W.BOX_H + 6 + previewH) or 0
  frame:SetHeight(pad + titleH + 6 + boxH + 8 + W.BUTTON_H + pad)
end

local function build()
  local T = GC.Theme
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetWidth(W.WIDTH)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  local bg = T.color.panel
  T.SlicedTexture(frame, "BACKGROUND", T.MEDIA .. "plaque.png", { bg[1], bg[2], bg[3], 0.97 }, 12):SetAllPoints(frame)
  T.SlicedTexture(frame, "BORDER", T.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, 12):SetAllPoints(frame)
  frame.title = T.Label(frame, 11)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(true)
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", W.PAD, -W.PAD)
  -- The well the box sits in, and the bare EditBox inside it (UI/Sell/Toolbar.lua's search).
  local well = CreateFrame("Frame", nil, frame)
  well:SetSize(W.BOX_W, W.BOX_H)
  local wc = T.color.bg or T.color.panel
  T.SlicedTexture(well, "BACKGROUND", T.MEDIA .. "plaque.png", { wc[1], wc[2], wc[3], 1 }, 12):SetAllPoints(well)
  T.SlicedTexture(well, "BORDER", T.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, 12):SetAllPoints(well)
  frame.box = CreateFrame("EditBox", nil, frame)
  frame.box:SetAutoFocus(false)
  frame.box:SetSize(W.BOX_W - 16, W.BOX_H - 4)
  well:SetPoint("CENTER", frame.box, "CENTER", 0, 0)
  frame.well = well
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if frame.box.SetFont then
    frame.box:SetFont(T.FONT_UI, 11 * T.Scale(), "")
    frame.box:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3], 1)
  end
  frame.preview = T.Num(frame, 10)
  frame.preview:SetJustifyH("LEFT")
  frame.preview:SetWordWrap(true)
  frame.set = T.Button(frame, "primary", "plaque")
  frame.set:SetSize(W.BUTTON_MIN, W.BUTTON_H)
  frame.set:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -W.PAD, W.PAD)
  frame.set:SetLabel(GC.L["Set cap"])
  frame.cancel = T.Button(frame, "ghost", "plaque")
  frame.cancel:SetSize(W.BUTTON_MIN, W.BUTTON_H)
  frame.cancel:SetPoint("RIGHT", frame.set, "LEFT", -T.pad.s, 0)
  frame.cancel:SetLabel(GC.L["Cancel"])

  local function preview()
    if frame.read then return nil end -- a name has nothing to preview
    local copper = GC.Util.ParseMoney(frame.box:GetText() or "")
    frame.preview:SetText(copper and GC.Util.CoinText(copper) or "")
    local c = T.color.fgDim
    frame.preview:SetTextColor(c[1], c[2], c[3], 1)
    layout()
    return copper
  end
  local function commit()
    local copper
    if not frame.asks then
      copper = true
    elseif frame.read then
      copper = frame.read(frame.box:GetText() or "")
    else
      copper = GC.Util.ParseMoney(frame.box:GetText() or "")
    end
    if not copper then
      frame.preview:SetText(frame.invalid or GC.L["Could not read that amount. Type it like 12g 50s."])
      local r = T.color.red
      frame.preview:SetTextColor(r[1], r[2], r[3], 1)
      layout()
      return
    end
    local done = frame.onCommit
    GC.BuyCapEditor.Close()
    if done then done(copper) end
  end
  frame.box:SetScript("OnTextChanged", function() preview() end)
  frame.box:SetScript("OnEnterPressed", commit)
  frame.box:SetScript("OnEscapePressed", function() GC.BuyCapEditor.Close() end)
  frame.set:SetScript("OnClick", commit)
  frame.cancel:SetScript("OnClick", function() GC.BuyCapEditor.Close() end)
  GC.BuyCapEditor._frame = frame -- spec seam
end

-- Opens the box under `anchor` on `opts.current` (copper), titled `opts.title`; `opts.onCommit`
-- gets the copper the player set. One box at a time: a second Open takes the first one over.
-- For the BUY tab's lists: `opts.text` asks for a name instead (the box opens on that text, selected,
-- and onCommit gets whatever was typed), `opts.box = false` asks only yes or no (onCommit(true)),
-- `opts.setLabel` names the button that commits, `opts.danger` paints it red, and `opts.over` lays
-- the popup over the anchor rather than under it. With `opts.text`, `opts.read(text)` may answer
-- what onCommit gets -- nil keeps the popup open on `opts.invalid` (the BUY search's "how many").
function GC.BuyCapEditor.Open(anchor, opts)
  if not frame then build() end
  frame.onCommit = opts.onCommit
  frame.asks = opts.box ~= false
  frame.read = opts.text and (opts.read or function(text) return text end) or nil
  frame.invalid = opts.invalid
  frame.title:SetText(opts.title or "")
  frame.set:SetLabel(opts.setLabel or GC.L["Set cap"])
  if frame.set.SetVariant then frame.set:SetVariant(opts.danger and "danger" or "primary") end
  local boxW = opts.text and (W.WIDTH - 2 * W.PAD) or W.BOX_W
  frame.well:SetWidth(boxW)
  frame.box:SetWidth(boxW - 16)
  if frame.box.SetMaxLetters then frame.box:SetMaxLetters(opts.text and 60 or 0) end
  frame.box:SetText(opts.text or (opts.current and plain(opts.current)) or "")
  frame.preview:SetText("")
  if frame.asks then
    frame.well:Show()
    frame.box:Show()
  else
    frame.well:Hide()
    frame.box:Hide()
  end
  frame:ClearAllPoints()
  if opts.over then
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  else
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  end
  layout()
  frame:Show()
  if frame.asks and frame.box.SetFocus then
    frame.box:SetFocus()
    if opts.text and frame.box.HighlightText then frame.box:HighlightText() end
  end
end

function GC.BuyCapEditor.Close()
  if not frame then return end
  frame.onCommit = nil
  if frame.box.ClearFocus then frame.box:ClearFocus() end
  frame:Hide()
end
