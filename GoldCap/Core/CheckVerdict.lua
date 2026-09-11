local _, GC = ...

-- What the check panel SAYS, decided away from the panel that draws it.
--
-- UI/SniperFrame.lua owns the layout; this owns the content. The split exists because
-- every content decision made inside that 6,400-line file is one nothing can test
-- directly -- several specs already have to reach into it through debug.getupvalue chains
-- -- and these are exactly the decisions the owner's in-game session found wrong: a panel
-- that reserved 94px for a figure a refusal never has, printed the same sentence three
-- times, and offered a quantity box on a verdict where nothing could be bought.
--
-- Nothing here formats. Money stays copper, rates stay basis points, and the panel decides
-- how to draw them -- GetCoinTextureString is a client global this file must never need.
-- Prose stays as GC.L keys resolved by the caller, for the same reason.
GC.CheckVerdict = {}

-- The engine's own gates, so a meter's tick is where the refusal actually happens rather
-- than a number picked to look right. Keep these equal to SniperDecision's thresholds --
-- spec/check_verdict_spec.lua pins the behaviour, not the constants.
local MIN_LISTINGS = 3
local MIN_SOLD_PER_DAY = 3
local MIN_SELL_THROUGH_BPS = 7000
local MIN_CONFIDENCE = 70

-- A meter needs a ceiling to be honest, and these two have none of their own -- a seller
-- count and a daily sales rate are unbounded. Both are drawn against a multiple of their
-- own gate, so the bar reads "how far past the line", which is the only question either
-- one answers. Far enough past and it simply fills.
local SELLERS_CEILING = MIN_LISTINGS * 6
local VELOCITY_CEILING = MIN_SOLD_PER_DAY * 20

-- Refusals about the VALUE itself. On any of these the panel must not print a profit or a
-- loss: the figure would be derived from the very number the engine has just said it
-- cannot stand behind, and dressing that up as "-1,240g" is a more confident lie than the
-- dash it replaces.
local UNPRICEABLE_REASONS = {
  live_verification_required = true, realm_item_unverified = true,
  -- Sniper phase 2: no region reference means no price to measure against at all, so there is
  -- nothing to put in the headline slot. It is a refusal in tone (there is no candidate, so
  -- the "Your call" branch below never applies) and unpriceable in figures.
  realm_no_reference = true,
  bundled_data_unverified = true, source_stale = true, market_value_estimated = true,
  price_history_sparse = true, listings_too_low = true, invalid_input = true,
  book_missing = true, competing_ask_missing = true, stress_exit_missing = true,
  deposit_missing = true, shadow_validation = true,
}

-- Refusals where the price may be perfectly fine and the trap is TIME. Gold is the wrong
-- unit for these: what the player needs is how long their capital would be stuck.
local TIME_REASONS = {
  velocity_missing = true, velocity_too_low = true,
  sell_through_too_low = true, liquidity_confidence_low = true,
}

-- The prose, as GC.L KEYS -- looked up by the panel that draws them, never here. A GC.L
-- lookup evaluated while this file loads resolves before GC.ApplyLocale has chosen a
-- language and freezes to English in every locale (spec/locale_load_time_spec.lua is the
-- guard); the @localised-keys marker is what tells spec/locale_contract_spec.lua that these
-- literals still have to exist in all twelve locale files.
-- @localised-keys
GC.CheckVerdict.TONE_WORD = {
  refuse = "Won't buy",
  adjust = "Buy less",
  clear = "Clear to buy",
  -- Sniper phase 2. A fourth answer, for the one case that is neither: a realm lot whose
  -- PRICE has been checked against the region reference and found far under it, while its
  -- sale speed is not measured anywhere and never will be from an import. "Won't buy" would
  -- be a lie over an enabled buy button, and "Clear to buy" would be a bigger one.
  unverified = "Your call",
}

-- What the headline figure is OF. Keyed by the hero's unit rather than by the reason, because
-- that is what actually changes the sentence: gold up and gold down are the same number read
-- from opposite ends, and neither is a hold time.
-- @localised-keys
GC.CheckVerdict.HERO_CAPTION = {
  gold_up = "worst case, selling all %d back into the price standing there now",
  gold_down = "if you buy all %d and sell them back at the price standing there now",
  days = "to clear %d units at %s sold a day, with %s tied up the whole time",
  units = "is what this market absorbs — past that you are buying stock you will sit on",
  unpriceable = "any figure here would be invented out of the very number being refused",
  reference = "against the region's own price for this item, after the 5% cut — if it sells",
}

-- The sentence under the hero on the two verdicts that are not a refusal. A refusal already
-- has one: the reason SniperDecision filed.
-- @localised-keys
GC.CheckVerdict.TONE_SENTENCE = {
  adjust = "Capped by how fast this actually sells, not by your wallet.",
  clear = "Checked against the live order book a moment ago.",
  unverified = "The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge.",
}

-- Said beside the board's own tier chip, and only when the two disagree.
-- @localised-keys
GC.CheckVerdict.RECONCILE_TEXT = {
  line = "The board tiered this off the imported snapshot. The live book does not back it.",
}

-- One label per fact id. The ids are stable; the wording is not.
-- @localised-keys
GC.CheckVerdict.FACT_LABEL = {
  sellers = "Sellers",
  soldPerDay = "Sold per day",
  sellThrough = "Sell-through",
  confidence = "Confidence",
  liveAsk = "Live ask",
  snapshotValue = "Snapshot value",
  youPay = "You would pay",
  youGet = "You would get",
  goldTiedUp = "Gold tied up",
  ifItClears = "If it clears",
  youPayFlat = "You pay",
  worstCaseBack = "Worst case back",
  yourMinimum = "Your minimum",
}

-- A confidence score is 0-100 with no unit, so a bare "90" says nothing a player can act on.
-- The meter beside it carries the precision; this carries the reading. MIN_CONFIDENCE is the
-- engine's own line, so "low" is exactly the band that refuses.
-- @localised-keys
GC.CheckVerdict.CONFIDENCE_WORD = {
  low = "low",
  fair = "fair",
  high = "high",
}

--- Which of CONFIDENCE_WORD's keys a score reads as. Here rather than in the panel because it
-- is a judgement about the number, not about how to draw it.
function GC.CheckVerdict.ConfidenceBand(value)
  if type(value) ~= "number" then return nil end
  if value < MIN_CONFIDENCE then return "low" end
  if value < 85 then return "fair" end
  return "high"
end

local function positive(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value > 0
end

local function number(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function clamp01(value)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

--- The reason a headline should show: the first that actually refused. SniperDecision
-- files some reasons at severity 0 as NOTES (`informational`) and orders them ahead of
-- the gate that really bit, so `reasons[1]` can be a note while the true reason hides
-- further down -- a headline reading it blind explains the wrong thing.
local function headlineReason(decision)
  local reasons = type(decision.reasons) == "table" and decision.reasons or {}
  local informational = type(decision.informational) == "table" and decision.informational or {}
  for i = 1, #reasons do
    if not informational[reasons[i]] then return reasons[i] end
  end
  return reasons[1]
end

local function meter(at, gate)
  return { at = clamp01(at), gate = clamp01(gate) }
end

local function sellersFact(market)
  if not number(market.listings) then return nil end
  return {
    id = "sellers", count = market.listings,
    tone = market.listings < MIN_LISTINGS and "bad" or "plain",
    meter = meter(market.listings / SELLERS_CEILING, MIN_LISTINGS / SELLERS_CEILING),
  }
end

local function velocityFact(market)
  if not number(market.soldPerDay) then return nil end
  return {
    id = "soldPerDay", count = market.soldPerDay,
    tone = market.soldPerDay < MIN_SOLD_PER_DAY and "bad" or "plain",
    meter = meter(market.soldPerDay / VELOCITY_CEILING, MIN_SOLD_PER_DAY / VELOCITY_CEILING),
  }
end

local function sellThroughFact(market)
  if not number(market.sellThroughBps) then return nil end
  return {
    id = "sellThrough", bps = market.sellThroughBps,
    tone = market.sellThroughBps < MIN_SELL_THROUGH_BPS and "bad" or "plain",
    meter = meter(market.sellThroughBps / 10000, MIN_SELL_THROUGH_BPS / 10000),
  }
end

local function confidenceFact(market)
  if not number(market.liquidityConfidence) then return nil end
  return {
    id = "confidence", count = market.liquidityConfidence,
    tone = market.liquidityConfidence < MIN_CONFIDENCE and "bad" or "plain",
    meter = meter(market.liquidityConfidence / 100, MIN_CONFIDENCE / 100),
  }
end

local function flat(id, field, value, tone)
  if not number(value) then return nil end
  return { id = id, [field] = value, tone = tone or "plain" }
end

-- What you pay against what you get back, sharing one ceiling. The comparison IS the
-- point on a profit refusal, so both are drawn on the larger of the two and the shortfall
-- is visible before either number is read.
local function moneyPair(decision)
  if not positive(decision.entryTotal) or not number(decision.stressProfit) then return nil, nil end
  local proceeds = decision.entryTotal + decision.stressProfit
  if proceeds < 0 then proceeds = 0 end
  local ceiling = math.max(decision.entryTotal, proceeds)
  if ceiling <= 0 then return nil, nil end
  return {
    id = "youPay", copper = decision.entryTotal, tone = "plain",
    meter = meter(decision.entryTotal / ceiling, 1),
  }, {
    id = "youGet", copper = proceeds,
    tone = proceeds < decision.entryTotal and "bad" or "good",
    meter = meter(proceeds / ceiling, 1),
  }
end

-- Indexed by count, not ipairs: a fact helper returns nil when its figure is absent, and
-- ipairs stops at the first nil -- so a missing third candidate silently dropped every
-- candidate after it, and the panel showed two facts where four were on offer.
local function take(facts, ...)
  for i = 1, select("#", ...) do
    local fact = select(i, ...)
    if fact and #facts < 4 then facts[#facts + 1] = fact end
  end
  return facts
end

--- Builds the panel's content from a decision and the market snapshot behind it.
-- `context.tier` is the tier the DEALS BOARD showed, which comes from the imported
-- snapshot rather than the live book -- the two can disagree, and when they do the player
-- is owed the reconciliation rather than two contradictory badges 320 pixels apart.
function GC.CheckVerdict.Build(decision, market, context)
  decision = type(decision) == "table" and decision or {}
  market = type(market) == "table" and market or {}
  context = type(context) == "table" and context or {}

  local buyable = decision.buyable == true
  local informational = type(decision.informational) == "table" and decision.informational or {}
  local reason = headlineReason(decision)

  local tone = "refuse"
  if buyable then
    tone = informational.demand_limit and "adjust" or "clear"
  elseif type(decision.candidate) == "table" then
    -- Sniper phase 2: a realm decision that named a specific lot. Not an approval -- it is not
    -- buyable and cannot become so -- but not a refusal either: the panel has a real price
    -- comparison to show and a button that will act on it.
    tone = "unverified"
  end

  local hero
  if tone == "unverified" then
    -- Its own kind, not "gold": the caption for a gold hero is about selling a commodity back
    -- into a live book, and this figure is measured against a region reference instead.
    hero = number(decision.estProfit) and { kind = "reference", copper = decision.estProfit }
      or { kind = "unpriceable" }
  elseif tone == "clear" then
    hero = number(decision.stressProfit) and { kind = "gold", copper = decision.stressProfit }
      or { kind = "unpriceable" }
  elseif tone == "adjust" then
    hero = positive(decision.quantity) and { kind = "units", quantity = decision.quantity }
      or { kind = "unpriceable" }
  elseif reason and UNPRICEABLE_REASONS[reason] then
    hero = { kind = "unpriceable" }
  elseif reason and TIME_REASONS[reason] and positive(market.soldPerDay)
      and positive(decision.quantity)
      and decision.quantity / market.soldPerDay >= 1 then
    -- Whole days, floored, and only when there IS at least one: 200 units at 412 a day
    -- floors to "0 days", which reads as instant rather than as fast. Under a day the
    -- time framing says nothing, so the gold branch below answers instead.
    hero = { kind = "days", days = math.floor(decision.quantity / market.soldPerDay) }
  elseif number(decision.stressProfit) then
    hero = { kind = "gold", copper = decision.stressProfit }
  else
    hero = { kind = "unpriceable" }
  end

  -- Four facts, chosen to explain THIS verdict rather than to fill a fixed grid. The old
  -- panel showed the same ten rows every time, five of them dashes on any refusal.
  local facts = {}
  local pay, get = moneyPair(decision)
  if tone == "refuse" and reason and UNPRICEABLE_REASONS[reason] then
    take(facts, sellersFact(market), confidenceFact(market),
      flat("liveAsk", "copper", decision.entryUnitDisplay),
      flat("snapshotValue", "copper", market.marketValue, "muted"),
      velocityFact(market))
  elseif tone == "refuse" and reason and TIME_REASONS[reason] then
    take(facts, velocityFact(market), sellThroughFact(market),
      flat("goldTiedUp", "copper", decision.entryTotal),
      flat("ifItClears", "copper", decision.stressProfit,
        number(decision.stressProfit) and decision.stressProfit >= 0 and "good" or "bad"))
  elseif tone == "adjust" then
    take(facts, velocityFact(market), sellThroughFact(market),
      flat("youPayFlat", "copper", decision.entryTotal),
      flat("worstCaseBack", "copper", decision.stressProfit, "good"))
  elseif tone == "unverified" then
    -- Two facts, because two are all a realm item honestly has: what this lot costs, and the
    -- reference it is being compared with. No sellers, no sell-through, no velocity -- an
    -- import carries none of them for a realm item, and a dash in a row is not a fact.
    take(facts, flat("youPayFlat", "copper", decision.entryTotal),
      flat("snapshotValue", "copper", decision.reference, "muted"))
  elseif tone == "refuse" and reason == "stress_profit_below_buffer" then
    -- The refusal is a comparison -- what came back against what the player asked for -- so
    -- the floor it fell short of is the third fact, ahead of anything about the market.
    take(facts, pay, get, flat("yourMinimum", "copper", decision.requiredProfit),
      sellThroughFact(market), sellersFact(market))
  else
    take(facts, pay, get, sellThroughFact(market), sellersFact(market),
      flat("snapshotValue", "copper", market.marketValue, "muted"))
  end

  return {
    tone = tone,
    reason = reason,
    hero = hero,
    facts = facts,
    actionable = tone ~= "refuse",
    -- Only worth saying when the two actually disagree. A refusal under a WATCH tier is
    -- the board and the panel agreeing, and saying so would be noise.
    reconcile = tone == "refuse" and type(context.tier) == "string"
      and (context.tier == "HOT" or context.tier == "GOOD") or false,
  }
end
