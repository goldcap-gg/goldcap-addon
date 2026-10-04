local _, GC = ...

-- A record of the BUY tab's waits, for the one question "what is this row waiting for": each wait
-- (a quote, a hover's look, the search's browse request, a keys batch) says when it was armed and
-- what ended it -- the event that answered, a write-off, or its own timeout. Off by default; the
-- player turns it on with `/gc buywait on`, searches, clicks a result, and reads the lines back
-- from SavedVariables (GoldCapDB.buyWaitLog) or with `/gc buywait show`. Nothing is printed while it
-- runs. Plain untranslated text, like the other diagnostics.
GC.BuyWaitDiag = {}
local D = GC.BuyWaitDiag

D.CAP = 300

function D.On()
  return GC.db ~= nil and GC.db.buyWaitDiagOn == true
end

--- One line: seconds since the game started, the wait, what happened to it, and the detail.
function D.Note(wait, what, detail)
  if not D.On() then return end
  local log = GC.db.buyWaitLog
  if type(log) ~= "table" then
    log = {}
    GC.db.buyWaitLog = log
  end
  log[#log + 1] = ("%.2f %s %s%s"):format((GetTime or os.time)(), wait, what,
    detail and detail ~= "" and (" " .. tostring(detail)) or "")
  while #log > D.CAP do table.remove(log, 1) end
end

local function show()
  local log = GC.db and GC.db.buyWaitLog or {}
  GC.Print(("buywait: %s, %d lines"):format(D.On() and "on" or "off", #log))
  for i = math.max(1, #log - 29), #log do GC.Print(log[i]) end
end

--- `/gc buywait on|off|show|clear`.
function D.Slash(rest)
  if not GC.db then return end
  local arg = (rest or ""):lower():match("^%s*(%S*)")
  if arg == "on" then
    GC.db.buyWaitDiagOn = true
    GC.db.buyWaitLog = {}
    GC.Print("buywait: on, the log is empty. Search in BUY, click a result, then /gc buywait show")
  elseif arg == "off" then
    GC.db.buyWaitDiagOn = false
    GC.Print("buywait: off (the log is kept)")
  elseif arg == "clear" then
    GC.db.buyWaitLog = {}
  else
    show()
  end
end
