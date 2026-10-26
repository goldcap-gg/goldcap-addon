local _, GC = ...

-- The marks on Blizzard's bag slots for what the Disenchant window will disenchant (retail only,
-- like UI/DisenchantFrame.lua, which calls Paint and Clear with the plan it read for its own paint:
-- one read of the bags a paint). A queued slot carries the Disenchant spell's icon in its top left
-- corner, the first (the one the window names, the button points at) also a purple ring around the
-- slot, and a slot the auction house pays more for a coin in its top right.
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
-- while the slot still holds the item the plan read there, and every overlay a pass did not visit is
-- hidden: Blizzard reuses a bag frame and its buttons for another bag (ContainerFrame_GetOpenFrame,
-- :383-397), so a mark never outlives the slot it was drawn for.
GC.DisenchantMarks = {}
local M = GC.DisenchantMarks

-- In UI units: the spell's icon and the coin, and how far each sits in from its corner; how far the
-- overlay stands above its button.
local ICON, COIN, INSET, LIFT = 14, 12, 2, 4
local PURPLE = { 176 / 255, 100 / 255, 240 / 255, 1 }
local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"

local overlays = setmetatable({}, { __mode = "k" })

local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- What the plan marks: "bag:slot" -> { row, first = true | nil, coin = true | nil }.
local function wanted(plan)
  local want = {}
  if type(plan) ~= "table" then return want end
  for i, row in ipairs(plan.queue or {}) do want[row.slotKey] = { row = row, first = i == 1 } end
  for _, row in ipairs(plan.left or {}) do want[row.slotKey] = { row = row, coin = true } end
  return want
end

local function holds(row)
  local info = _G.C_Container and ask(C_Container.GetContainerItemInfo, row.stack.bag, row.stack.slot)
  return type(info) == "table" and info.hyperlink == row.stack.link
end

local function build(button, spellTexture)
  local T = GC.Theme
  local o = CreateFrame("Frame", nil, button)
  o:SetAllPoints(button)
  o:SetFrameLevel(button:GetFrameLevel() + LIFT)
  o:EnableMouse(false)
  o.glow = T.SlicedTexture(o, "OVERLAY", T.MEDIA .. "plaque_ring.png", PURPLE, T.SLICE.plaque)
  o.glow:SetAllPoints(o)
  o.icon = o:CreateTexture(nil, "OVERLAY", nil, 2)
  o.icon:SetSize(ICON, ICON)
  o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  o.icon:SetTexture(spellTexture)
  o.icon:SetPoint("TOPLEFT", o, "TOPLEFT", INSET, -INSET)
  o.coin = o:CreateTexture(nil, "OVERLAY", nil, 2)
  o.coin:SetSize(COIN, COIN)
  o.coin:SetTexture(COIN_TEXTURE)
  o.coin:SetPoint("TOPRIGHT", o, "TOPRIGHT", -INSET, -INSET)
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
  o.icon:SetShown(not mark.coin)
  o.glow:SetShown(mark.first == true)
  o.coin:SetShown(mark.coin == true)
  o:Show()
end

--- Draws the marks for `plan` (the queue and the left-out rows of Core/Disenchant.lua's Plan) on the
--- slots of `frames` (the container frames that show), and takes them off every other overlay.
--- `spellTexture`: the spell's icon. A plan with an empty queue still marks its left-out rows.
function M.Paint(plan, spellTexture, frames)
  local want = wanted(plan)
  local visited = {}
  for _, container in ipairs(frames or {}) do
    local ok = pcall(function()
      for _, button in container:EnumerateValidItems() do
        local bag, slot = ask(button.GetBagID, button), ask(button.GetID, button)
        local mark = type(bag) == "number" and type(slot) == "number" and want[bag .. ":" .. slot] or nil
        if mark and holds(mark.row) then
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
