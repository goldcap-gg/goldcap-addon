local _, GC = ...

-- The marks on Blizzard's bag slots for what the Disenchant window will disenchant (retail only,
-- like UI/DisenchantFrame.lua, which calls Paint and Clear with the plan it read for its own paint:
-- one read of the bags a paint). A queued slot carries a purple ring round the slot, at full strength
-- on the first (the one the window names, the button points at) and dimmed (RING_DIM) on the rest,
-- and the Disenchant spell's icon on a dark round badge with a purple ring in its top left corner; a
-- slot the auction house pays more for carries the coin on the same badge in its top right (the
-- owner, 2026-10-27 00:30: the bare icon was almost invisible on the item's art). The badges are
-- true circles: a purple disc and a smaller dark one on it, each, and the spell's icon, cut round by
-- the client's own round mask (CIRCLE, the one Blizzard's round portraits use: live
-- Blizzard_PVPUI/Mainline/Blizzard_PVPUI.xml:346, a MaskTexture clamped to black additive).
--
-- Everything is drawn on one frame of ours per item button, made once and reused: a child of the
-- button, level with it plus a little, taking no mouse. Blizzard's button gets no script, no hook and
-- no anchor from here, and none of its own regions is shown or hidden. Nothing here is protected (the
-- item button is not a protected frame: ContainerFrame.xml:77, ItemButtonTemplate.xml:4), so it runs in
-- combat too, making an overlay included.
--
-- The buttons are those of the container frames that show, which the window hands in (it already lists
-- them for placing itself beside the bags: ContainerFrameCombinedBags and ContainerFrame1 to
-- NUM_CONTAINER_FRAMES, a bag opened alone too). Each is listed as Blizzard lists them,
-- EnumerateValidItems (Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:522-526: index, button),
-- with its bag (ContainerFrameItemButtonMixin:GetBagID, :1648) and slot (GetID). A mark is drawn only
-- while the slot still holds the item the plan read there (the window's `holds`: its link, and its
-- GUID where it has one), and every overlay a pass did not visit is
-- hidden: Blizzard reuses a bag frame and its buttons for another bag (ContainerFrame_GetOpenFrame,
-- :383-397), so a mark never outlives the slot it was drawn for.
GC.DisenchantMarks = {}
local M = GC.DisenchantMarks

-- In UI units: the badge (its purple disc), its dark disc (RING less on every side, the ring being
-- what shows between them), the spell's icon and the coin on it, and how far out of its corner a
-- badge stands; how far the overlay stands above its button. RING_DIM: the slot ring's alpha on a
-- queued slot other than the first.
local BADGE, RING, ICON, COIN, OUT, LIFT = 18, 1.5, 12, 11, 2, 4
local RING_DIM = 0.55
local PURPLE = { 176 / 255, 100 / 255, 240 / 255, 1 }
local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local overlays = setmetatable({}, { __mode = "k" })

-- One guarded client call (Core/Util.lua's Ask).
local ask = GC.Util.Ask

-- What the plan marks: "bag:slot" -> { row, first = true | nil, coin = true | nil }.
local function wanted(plan)
  local want = {}
  if type(plan) ~= "table" then return want end
  for i, row in ipairs(plan.queue or {}) do want[row.slotKey] = { row = row, first = i == 1 } end
  for _, row in ipairs(plan.left or {}) do want[row.slotKey] = { row = row, coin = true } end
  return want
end

-- Cuts `texture` round: a mask of the overlay's, on exactly the texture's own rectangle.
local function round(o, texture)
  local mask = o:CreateMaskTexture()
  mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(texture)
  texture:AddMaskTexture(mask)
end

-- A dark round badge with a purple ring at a corner of the overlay ("TOPLEFT" or "TOPRIGHT"),
-- standing OUT units out of it: the purple disc, the dark disc on it, what sits on them above both.
local function badge(o, corner)
  local dark = GC.Kit.Tokens.color.windowBottom
  local x = corner == "TOPLEFT" and -OUT or OUT
  local ring = o:CreateTexture(nil, "OVERLAY", nil, 1)
  ring:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 1)
  ring:SetSize(BADGE, BADGE)
  ring:SetPoint(corner, o, corner, x, OUT)
  round(o, ring)
  local back = o:CreateTexture(nil, "OVERLAY", nil, 2)
  back:SetColorTexture(dark[1], dark[2], dark[3], 1)
  back:SetSize(BADGE - 2 * RING, BADGE - 2 * RING)
  back:SetPoint("CENTER", ring, "CENTER", 0, 0)
  round(o, back)
  return back, ring
end

local function build(button, spellTexture)
  local T = GC.Theme
  local o = CreateFrame("Frame", nil, button)
  o:SetAllPoints(button)
  o:SetFrameLevel(button:GetFrameLevel() + LIFT)
  o:EnableMouse(false)
  o.glow = T.SlicedTexture(o, "OVERLAY", T.MEDIA .. "plaque_ring.png", PURPLE, T.SLICE.plaque)
  o.glow:SetAllPoints(o)
  o.iconBadge, o.iconRing = badge(o, "TOPLEFT")
  o.icon = o:CreateTexture(nil, "OVERLAY", nil, 3)
  o.icon:SetSize(ICON, ICON)
  o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  o.icon:SetTexture(spellTexture)
  o.icon:SetPoint("CENTER", o.iconBadge, "CENTER", 0, 0)
  round(o, o.icon)
  o.coinBadge, o.coinRing = badge(o, "TOPRIGHT")
  o.coin = o:CreateTexture(nil, "OVERLAY", nil, 3)
  o.coin:SetSize(COIN, COIN)
  o.coin:SetTexture(COIN_TEXTURE)
  o.coin:SetPoint("CENTER", o.coinBadge, "CENTER", 0, 0)
  return o
end

local function hide(button)
  local o = overlays[button]
  if o then o:Hide() end
end

local function paintOne(button, mark, spellTexture)
  local o = overlays[button]
  if not o then
    o = build(button, spellTexture)
    overlays[button] = o
  end
  local queued, coin = not mark.coin, mark.coin == true
  o.glow:SetShown(queued)
  o.glow:SetAlpha(mark.first and 1 or RING_DIM)
  o.icon:SetShown(queued)
  o.iconBadge:SetShown(queued)
  o.iconRing:SetShown(queued)
  o.coin:SetShown(coin)
  o.coinBadge:SetShown(coin)
  o.coinRing:SetShown(coin)
  o:Show()
end

--- Draws the marks for `plan` (the queue and the left-out rows of Core/Disenchant.lua's Plan) on the
--- slots of `frames` (the container frames that show), and takes them off every other overlay.
--- `spellTexture`: the spell's icon. `holds(stack)`: whether its slot still holds that stack (the
--- window's rule). A plan with an empty queue still marks its left-out rows.
function M.Paint(plan, spellTexture, frames, holds)
  local want = wanted(plan)
  local visited = {}
  for _, container in ipairs(frames or {}) do
    local ok = pcall(function()
      for _, button in container:EnumerateValidItems() do
        local bag, slot = ask(button.GetBagID, button), ask(button.GetID, button)
        local mark = type(bag) == "number" and type(slot) == "number" and want[bag .. ":" .. slot] or nil
        if mark and holds(mark.row.stack) then
          visited[button] = true
          paintOne(button, mark, spellTexture)
        end
      end
    end)
    if not ok then return M.Clear() end
  end
  for button in pairs(overlays) do
    if not visited[button] then hide(button) end
  end
end

--- Takes every mark off.
function M.Clear()
  for button in pairs(overlays) do hide(button) end
end
