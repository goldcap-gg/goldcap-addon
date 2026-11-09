local _, GC = ...

-- WoW: Forever only: GoldCap_Camelot.toc loads this file and GoldCap.toc does not, so nothing here
-- runs on retail. SELL posts about as many units as sell within the auction's duration, and puts a
-- slow seller up for 24 h. The pace of an item is the auction house's sale tape
-- (GC.Data.ForeverSales), which GC.SellPositions.Build keeps on `position.tape`: units sold a day
-- (`perDay`) over the `hours` the tape covers.
--
-- Pure: Decorate is handed a position Build made and a context, and reads no SavedVariables and no
-- client. The context (Services/Sell/Compose.lua builds it):
--   hoursOf(index)    the hours a duration index (1 to 3) lasts (GC.GroupRules.HoursOf)
--   settingIndex      the Settings duration (1 to 3)
--   slowOn            the "Post slow sellers for 24 h" setting
--   streakFor(itemID) -> rounds, short, shortIndex: the rounds the item came back unsold since its
--                     last sale, how many of them at a duration under 24 h, and the duration index
--                     of the last short one
--   recent            this visit's posts, { [positionKey] = { { auctionID, quantity, unitPrice } } }
--
-- What Decorate writes on a position. A variant (`variantKind`: a suffix or a caged pet shares its
-- itemID with every other variant, so the tape is not its own) and a repair row get none of it:
--   pacePerDay, paceHours  the tape's units a day and its hours; nil with no tape
--   paceTargets            { units within 2 h, within 8 h, within 24 h } (Target); nil with no tape
--                          or no hours, and a duration whose hours are unknown has none.
--                          Core/SellPositions.lua's PostQuantity reads it at the duration the post
--                          goes up at, less the units already up at or under the post's price.
--   returnRounds, returnShort, returnShortIndex  streakFor's answer
--   slowDurationIndex, slowWhy  3 and "pace" (under half a sale expected at the Settings duration)
--                          or "history" (came back unsold SLOW_SHORT_ROUNDS times under 24 h), when
--                          the slow sellers rule picks 24 h; GC.Sell.PostDurationFor reads it after
--                          a duration the player picked and a followed group's
--   paceRecent             the entries of `recent` the owned list does not hold yet, which
--                          GC.SellPositions.ListedAtOrBelow counts as already up
GC.ForeverPace = GC.ForeverPace or {}
local P = GC.ForeverPace

-- Unsold rounds in a row after which SELL stops offering an item.
P.RETURN_HOLD = 3
-- Under this many sales expected within the duration, a post goes up for 24 h.
P.SLOW_EXPECTED = 0.5
-- Returns at a duration under 24 h after which a post goes up for 24 h.
P.SLOW_SHORT_ROUNDS = 2

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function validIndex(v)
  return (v == 1 or v == 2 or v == 3) and v or nil
end

--- The units that sell within `hours` at `perDay` units a day, rounded up and at least 1: an item
--- nobody bought here still posts one, to test the price. nil, no pace, when the hours or the rate
--- are unknown: 1 is the answer for "nobody buys it", not for "no idea".
function P.Target(perDay, hours)
  if not (finite(perDay) and finite(hours)) or hours <= 0 then return nil end
  if perDay <= 0 then return 1 end
  return math.max(1, math.ceil(perDay * hours / 24 - 1e-9))
end

-- The posts of this visit the owned list has not caught up with: an entry drops the moment a lot
-- with its auctionID is on the list, so a lot is never counted twice.
local function notYetOwned(entries, ownedLots)
  if type(entries) ~= "table" then return nil end
  local owned = {}
  for _, lot in ipairs(type(ownedLots) == "table" and ownedLots or {}) do
    if type(lot) == "table" and lot.auctionID ~= nil then owned[lot.auctionID] = true end
  end
  local left = {}
  for _, entry in ipairs(entries) do
    if type(entry) == "table" and not owned[entry.auctionID] then left[#left + 1] = entry end
  end
  return #left > 0 and left or nil
end

--- Writes the pace fields above on `position`, from its tape and `ctx`.
function P.Decorate(position, ctx)
  if type(position) ~= "table" or position.variantKind or position.unresolved then return end
  ctx = type(ctx) == "table" and ctx or {}
  local hoursOf = type(ctx.hoursOf) == "function" and ctx.hoursOf or function() return nil end
  local tape = position.tape
  if type(tape) == "table" and finite(tape.perDay) then
    position.pacePerDay, position.paceHours = tape.perDay, tape.hours
    local targets = { P.Target(tape.perDay, hoursOf(1)), P.Target(tape.perDay, hoursOf(2)),
      P.Target(tape.perDay, hoursOf(3)) }
    position.paceTargets = next(targets) ~= nil and targets or nil
  end
  local rounds, short, shortIndex = 0, 0, nil
  if type(ctx.streakFor) == "function" then rounds, short, shortIndex = ctx.streakFor(position.itemID) end
  position.returnRounds = finite(rounds) and rounds or 0
  position.returnShort = finite(short) and short or 0
  position.returnShortIndex = validIndex(shortIndex)

  local setting = validIndex(ctx.settingIndex)
  if ctx.slowOn and not validIndex(position.ruleDurationIndex) and setting and setting < 3
      and finite(position.bagQty) and position.bagQty > 0 then
    local hours = hoursOf(setting)
    local why
    if position.pacePerDay ~= nil and finite(hours) and position.pacePerDay * hours / 24 < P.SLOW_EXPECTED then
      why = "pace"
    elseif position.returnShort >= P.SLOW_SHORT_ROUNDS then
      why = "history"
    end
    if why then position.slowDurationIndex, position.slowWhy = 3, why end
  end

  local recent = type(ctx.recent) == "table" and type(position.positionKey) == "string"
    and ctx.recent[position.positionKey] or nil
  position.paceRecent = notYetOwned(recent, position.ownedLots)
end
