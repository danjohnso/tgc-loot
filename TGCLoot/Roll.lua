-- Timed main-spec / off-spec roll. Scores are decided by the raid leader and shown to the raid.
local _, TGC = ...

TGC.Roll = TGC.Roll or {}
local Roll = TGC.Roll

TGC.session = {
  responses = {},
  tier = false,
  active = false,
  awarded = false,
}
TGC.watch = {
  rows = {},
  banner = "Alt+click an item to roll it.",
  tieNames = {},
  active = false,
}
TGC.give = nil

local function Clock()
  return GetTime and GetTime() or 0
end

function Roll.Pattern()
  if Roll.pattern then return Roll.pattern end
  local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  fmt = fmt:gsub("%%%d+%$", "%%")
  local pattern = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  Roll.pattern = "^" .. pattern .. "$"
  return Roll.pattern
end

function Roll.SenderIsLeader(sender)
  local leader = TGC.LeaderName()
  return leader ~= nil and TGC.SamePlayer(leader, sender)
end

function Roll.Seconds()
  local seconds = TGC.db and TGC.db.settings and TGC.db.settings.seconds or 30
  if TGC.UI and TGC.UI.Seconds then seconds = TGC.UI.Seconds() or seconds end
  seconds = math.floor(tonumber(seconds) or 30)
  if seconds < 5 then seconds = 5 end
  if seconds > 180 then seconds = 180 end
  return seconds
end

function Roll.SetItem(link, slot)
  if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return end
  if TGC.session.active then
    TGC.Print("A roll is still open.")
    return
  end
  TGC.session.link = link
  TGC.session.itemId = TGC.ItemID(link)
  TGC.session.lootSlot = slot
  TGC.session.tier = TGC.db and TGC.db.tierItems[TGC.session.itemId] and true or false
  TGC.session.responses = {}
  TGC.session.awarded = false
  TGC.session.active = false
  TGC.session.acceptRolls = false
  TGC.watch.id = nil
  TGC.watch.link = link
  TGC.watch.itemId = TGC.session.itemId
  TGC.watch.tier = TGC.session.tier
  TGC.watch.rows = {}
  TGC.watch.result = nil
  TGC.watch.active = false
  TGC.watch.closed = false
  TGC.watch.tie = false
  TGC.watch.tieNames = {}
  TGC.watch.mine = nil
  TGC.watch.banner = "Set Tier if this is tier gear, then start the roll."
  if TGC.UI and TGC.UI.Show then TGC.UI.Show() end
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

function Roll.SetTier(on)
  if TGC.session.awarded then return end
  TGC.session.tier = on and true or false
  TGC.watch.tier = TGC.session.tier
  if TGC.session.active or TGC.watch.closed then Roll.Publish() else
    if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  end
end

local function ReservationNote(itemId)
  local names = {}
  for _, reservation in ipairs(TGC.db and TGC.db.reservations or {}) do
    if reservation.item == itemId then
      local note = reservation.note ~= "" and (" (" .. reservation.note .. ")") or ""
      names[#names + 1] = reservation.player .. note
    end
  end
  if #names == 0 then return "" end
  return "Reserved: " .. table.concat(names, ", ") .. ". "
end

function Roll.ResponseList()
  local list = {}
  for _, response in pairs(TGC.session.responses) do list[#list + 1] = response end
  return list
end

function Roll.Compute()
  local isGuild = function(key, player) return TGC.PlayerIsGuild(key, player) end
  local result = TGC.Evaluate(
    Roll.ResponseList(),
    TGC.db.players,
    TGC.CurrentWeek(),
    TGC.session.tier,
    TGC.db.lockout and TGC.db.lockout.id or "",
    isGuild
  )
  result.banner = ReservationNote(TGC.session.itemId) .. (result.banner or "")
  return result
end

local function PackRows(rows)
  local pieces = {}
  for _, row in ipairs(rows or {}) do
    pieces[#pieces + 1] = table.concat({
      TGC.CleanTight(row.name, 40),
      row.choice or "",
      tostring(TGC.Score100(row.score)),
      row.statusLetter or TGC.StatusLetter(row.status),
      tostring(row.current or 0),
      tostring(TGC.Score100(row.rate)),
      row.roll and tostring(row.roll) or "",
      TGC.CleanTight(row.class, 16),
      TGC.CleanTight(row.spec, 16),
      row.competing and "1" or "0",
      row.unclear and "1" or "0",
    }, "^")
  end
  return table.concat(pieces, ";")
end

function Roll.ParseRows(payload)
  local rows = {}
  if not payload or payload == "" then return rows end
  for _, piece in ipairs(TGC.Split(payload, ";")) do
    if piece ~= "" then
      local fields = TGC.Split(piece, "^")
      if fields[1] and fields[1] ~= "" then
        local roll = fields[7]
        rows[#rows + 1] = {
          name = fields[1],
          key = TGC.Key(fields[1]),
          choice = fields[2] or "",
          score = TGC.Num(fields[3]) / 100,
          statusLetter = fields[4] or "P",
          current = TGC.Num(fields[5]),
          rate = TGC.Num(fields[6]) / 100,
          roll = roll ~= "" and TGC.Num(roll) or nil,
          class = fields[8] or "",
          spec = fields[9] or "",
          competing = fields[10] == "1",
          unclear = fields[11] == "1",
        }
      end
    end
  end
  return rows
end

function Roll.Broadcast()
  if not TGC.Comm or not TGC.session.id then return end
  local rows = TGC.watch.rows or {}
  local payload = PackRows(rows)
  local size = 170
  local count = math.max(1, math.ceil(math.max(#payload, 1) / size))
  for index = 1, count do
    local part = payload:sub((index - 1) * size + 1, index * size)
    TGC.Comm.Queue(string.format("U~%d~%d~%d~%s", TGC.session.id, index, count, part), "roll")
  end
  local remain = 0
  if TGC.watch.endsAt then remain = math.max(0, math.floor(TGC.watch.endsAt - Clock() + 0.5)) end
  local info = string.format("I~%d~%d~%d~%d~%s", TGC.session.id, remain, TGC.session.tier and 1 or 0,
    TGC.session.itemId or 0, TGC.Clean(TGC.watch.banner, 160))
  if #info <= 255 then TGC.Comm.Queue(info, "roll") end
  if TGC.watch.tie then
    local names = {}
    for _, row in ipairs(TGC.watch.result and TGC.watch.result.tied or {}) do
      names[#names + 1] = TGC.CleanTight(row.name, 40)
    end
    TGC.Comm.Queue(string.format("B~%d~%s", TGC.session.id, table.concat(names, ";")), "roll")
  end
end

function Roll.Publish()
  local result = Roll.Compute()
  TGC.watch.result = result
  TGC.watch.rows = result.rows
  TGC.watch.banner = result.banner
  TGC.watch.tier = TGC.session.tier
  TGC.watch.link = TGC.session.link
  TGC.watch.itemId = TGC.session.itemId
  Roll.Broadcast()
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
end

function Roll.Remember(key, name, class, choice, unclear)
  local player = TGC.db.players[key]
  TGC.session.responses[key] = {
    key = key,
    name = name,
    class = class or (player and player.class),
    spec = player and player.spec or "",
    choice = choice,
    roll = TGC.session.responses[key] and TGC.session.responses[key].roll,
    unclear = unclear and true or false,
  }
end

function Roll.SetChoice(key, choice)
  if not TGC.session.active then
    TGC.Print("Start the roll first.")
    return
  end
  if not TGC.IsRaidLeader() then
    if TGC.SamePlayer(key, TGC.PlayerName()) then Roll.Respond(choice) end
    return
  end
  local member, unclear = TGC.ResolveMember(key)
  if unclear then
    TGC.Print("More than one raider matches that name. Use the full name.")
    return
  end
  local name = member and member.name or key
  local realKey = member and member.key or TGC.Key(name)
  if not realKey then return end
  Roll.Remember(realKey, name, member and member.class, choice, false)
  Roll.Publish()
end

function Roll.Respond(choice)
  if choice ~= "MS" and choice ~= "OS" and choice ~= "PASS" then return end
  if not TGC.watch.active or not TGC.watch.id then
    TGC.Print("There is no roll open.")
    return
  end
  TGC.watch.mine = choice
  if TGC.IsRaidLeader() and TGC.session.id == TGC.watch.id then
    local name = TGC.PlayerName()
    local key = TGC.Key(name)
    if key then
      Roll.Remember(key, name, nil, choice, false)
      Roll.Publish()
    end
    return
  end
  if TGC.Comm then TGC.Comm.Queue(string.format("R~%d~%s", TGC.watch.id, choice), "roll") end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
end

function Roll.Start()
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return
  end
  if not TGC.session.link then
    TGC.Print("Alt+click an item in the loot window, your bags, or chat.")
    return
  end
  if TGC.session.active then return end
  if TGC.session.awarded then
    TGC.Print("That item was already awarded. Alt+click the next one.")
    return
  end
  if TGC.ChatLocked() then
    TGC.Print("Can't open rolls during a boss fight. Addon chat is blocked until it ends.")
    return
  end
  if not TGC.db.lockout or TGC.db.lockout.id == "" then
    local started = TGC.StartLockout("Raid")
    if not started then return end
  else
    local lines = TGC.BuildAttendanceLines()
    for _, line in ipairs(lines) do TGC.Mutate(line) end
  end
  local seconds = Roll.Seconds()
  TGC.session.id = math.random(100000, 999999)
  TGC.session.responses = {}
  TGC.session.active = true
  TGC.session.acceptRolls = false
  TGC.session.awarded = false
  TGC.watch.id = TGC.session.id
  TGC.watch.active = true
  TGC.watch.closed = false
  TGC.watch.tie = false
  TGC.watch.tieNames = {}
  TGC.watch.mine = nil
  TGC.watch.duration = seconds
  TGC.watch.endsAt = Clock() + seconds
  TGC.watch.rows = {}
  TGC.watch.result = nil
  TGC.watch.banner = ReservationNote(TGC.session.itemId) .. "Roll is open. Main spec beats off spec."
  local kind = TGC.session.tier and "tier" or "non-tier"
  TGC.Announce(string.format("Rolling %s (%s, %d sec). Main spec beats off spec. Lowest score wins.",
    TGC.session.link, kind, seconds), true)
  local message = string.format("O~%d~%d~%d~%d~%s", TGC.session.id, seconds, TGC.session.tier and 1 or 0,
    TGC.session.itemId or 0, TGC.session.link)
  if TGC.Comm and #message <= 255 then TGC.Comm.Queue(message, "roll")
  elseif #message > 255 then TGC.Print("The item link is too long to open a popup for the raid.") end
  if TGC.UI and TGC.UI.ShowPopup then TGC.UI.ShowPopup() end
  Roll.Publish()
  local id = TGC.session.id
  if C_Timer then
    C_Timer.After(seconds, function()
      if TGC.session.active and TGC.session.id == id then Roll.Close() end
    end)
  end
end

function Roll.Close()
  if not TGC.session.active then return end
  if not TGC.IsRaidLeader() then return end
  TGC.session.active = false
  TGC.watch.active = false
  TGC.watch.closed = true
  local result = Roll.Compute()
  TGC.watch.result = result
  TGC.watch.rows = result.rows
  TGC.watch.banner = result.banner
  TGC.watch.tie = result.tied and #result.tied > 1 or false
  TGC.session.acceptRolls = TGC.watch.tie
  TGC.watch.tieNames = {}
  if TGC.watch.tie then
    for _, row in ipairs(result.tied) do TGC.watch.tieNames[#TGC.watch.tieNames + 1] = row.name end
  end
  if TGC.Comm then TGC.Comm.Queue(string.format("E~%d", TGC.session.id), "roll") end
  Roll.Broadcast()
  TGC.Announce("Rolls closed for " .. TGC.session.link .. ". " .. result.banner, true)
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
end

function Roll.Reset()
  if TGC.session.active then
    TGC.Print("Close the roll before resetting it.")
    return
  end
  TGC.session.responses = {}
  TGC.session.awarded = false
  TGC.session.acceptRolls = false
  TGC.session.link = nil
  TGC.session.itemId = nil
  TGC.watch.id = nil
  TGC.watch.link = nil
  TGC.watch.rows = {}
  TGC.watch.result = nil
  TGC.watch.active = false
  TGC.watch.closed = false
  TGC.watch.tie = false
  TGC.watch.banner = "Alt+click an item to roll it."
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

function Roll.ResolvedWinner()
  local result = TGC.watch.result
  if not result or result.empty then return nil end
  if result.winner then return result.winner end
  if not result.tied then return nil end
  local winner = TGC.PickRolls(result.tied, function(row)
    local response = TGC.session.responses[row.key]
    return response and response.roll
  end)
  return winner
end

function Roll.FindRow(key)
  local wanted = TGC.Key(key) or key
  for _, row in ipairs(TGC.watch.rows or {}) do
    if row.key == wanted then return row end
  end
  for _, member in ipairs(TGC.GroupRoster()) do
    if member.key == wanted then
      return { key = member.key, name = member.name, class = member.class, choice = "" }
    end
  end
end

function Roll.Award(overrideKey, reason, overridden)
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return
  end
  if TGC.session.active then
    TGC.Print("Close the roll first.")
    return
  end
  if TGC.session.awarded then
    TGC.Print("That item was already awarded. Loot decisions are final.")
    return
  end
  local result = TGC.watch.result
  if not result or result.empty then
    TGC.Print("Nobody rolled main spec or off spec.")
    return
  end
  local winner
  if overridden then
    reason = TGC.Clean(reason or "", 60)
    if reason == "" then
      TGC.Print("Type a reason. Officer overrides are recorded.")
      return
    end
    winner = Roll.FindRow(overrideKey)
    if not winner then
      TGC.Print("Select a raider in the list first.")
      return
    end
  else
    winner = Roll.ResolvedWinner()
    if not winner then
      TGC.Print("It's a tie. The tied players roll 100, or select a raider and override with a reason.")
      return
    end
  end
  if winner.unclear then
    TGC.Print("That name matches more than one raider. Enter the roll on the full name.")
    return
  end
  local plus = TGC.AwardPlus(result, overridden)
  local spec = winner.choice
  if overridden then spec = result.priority or spec end
  if spec ~= "MS" and spec ~= "OS" then spec = result.priority or "MS" end
  local reasonText = overridden and ("Officer award to " .. (winner.name or "") .. ": " .. reason) or ""
  local line = TGC.AwardLine(winner.name, winner.class, TGC.session.itemId, TGC.session.tier, spec, plus,
    TGC.db.lockout.id, reasonText, TGC.ItemNameFromLink(TGC.session.link))
  if #("D~" .. tostring((TGC.db.rev or 0) + 1) .. "~" .. line) > 255 then
    TGC.Print("The award record is too long. Shorten the reason.")
    return
  end
  if not TGC.Mutate(line) then return end
  TGC.session.awarded = true
  TGC.session.acceptRolls = false
  TGC.watch.tie = false
  TGC.give = {
    link = TGC.session.link, name = winner.name, key = winner.key,
    slot = TGC.session.lootSlot, itemId = TGC.session.itemId,
  }
  local plusText = plus and (TGC.session.tier and "+1 tier" or "+1") or "free"
  local how = overridden and ("Officer decision: " .. reason) or (result.contested and "contested" or "uncontested")
  local specText = spec == "MS" and "Main spec" or "Off spec"
  TGC.Announce(string.format("%s -> %s. %s, %s, %s.", TGC.session.link, winner.name, specText, how, plusText), true)
  TGC.watch.banner = winner.name .. " awarded. " .. plusText .. "."
  TGC.watch.active = false
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
end

function Roll.Skip(reason)
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return
  end
  if TGC.session.active then Roll.Close() end
  if not TGC.session.link then return end
  local text = "Skipped " .. (TGC.ItemNameFromLink(TGC.session.link) ~= "" and TGC.ItemNameFromLink(TGC.session.link) or "item") .. "."
  if reason and TGC.Clean(reason, 80) ~= "" then text = text .. " " .. TGC.Clean(reason, 80) end
  local link = TGC.session.link
  if not TGC.Mutate(string.format("N|%d|%s|%s", TGC.Now(), TGC.Clean(TGC.PlayerName(), 48), TGC.Clean(text, 140))) then return end
  TGC.Announce(link .. " skipped.", true)
  Roll.Reset()
end

function Roll.Roll()
  if not TGC.watch.tie then
    TGC.Print("There is no tie to roll.")
    return
  end
  local allowed = false
  for _, name in ipairs(TGC.watch.tieNames or {}) do
    if TGC.SamePlayer(name, TGC.PlayerName()) then allowed = true end
  end
  if not allowed then
    TGC.Print("You are not in the tie.")
    return
  end
  if not pcall(RandomRoll, 1, 100) then TGC.Print("Couldn't roll. Type /roll 100.") end
end

function Roll.OnOpen(text, sender)
  if not Roll.SenderIsLeader(sender) then return end
  local id, seconds, tier, itemId, link = text:match("^O~(%d+)~(%d+)~([01])~(%d+)~(.+)$")
  id, seconds, itemId = tonumber(id), tonumber(seconds), tonumber(itemId)
  if not id or not seconds or seconds < 1 or seconds > 180 then return end
  if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return end
  TGC.watch.id = id
  TGC.watch.link = link
  TGC.watch.itemId = itemId
  TGC.watch.tier = tier == "1"
  TGC.watch.duration = seconds
  TGC.watch.endsAt = Clock() + seconds
  TGC.watch.active = true
  TGC.watch.closed = false
  TGC.watch.rows = {}
  TGC.watch.result = nil
  TGC.watch.tie = false
  TGC.watch.tieNames = {}
  TGC.watch.mine = nil
  TGC.watch.banner = "Roll opened by " .. TGC.ShortName(sender) .. ". Main spec beats off spec."
  if not (TGC.saved and TGC.saved.ui and TGC.saved.ui.popup == false) and TGC.UI and TGC.UI.ShowPopup then
    TGC.UI.ShowPopup()
  elseif TGC.UI and TGC.UI.Show then
    TGC.UI.Show()
  end
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

function Roll.OnResponse(text, sender)
  if not TGC.IsRaidLeader() or not TGC.session.active then return end
  local id, choice = text:match("^R~(%d+)~([A-Z]+)$")
  id = tonumber(id)
  if id ~= TGC.session.id then return end
  if choice ~= "MS" and choice ~= "OS" and choice ~= "PASS" then return end
  local member, unclear = TGC.ResolveMember(sender)
  if unclear or not member then
    TGC.Print("A response came in as \"" .. TGC.ShortName(sender) .. "\", and it doesn't match one raider. Add it by full name.")
    return
  end
  Roll.Remember(member.key, member.name, member.class, choice, false)
  Roll.Publish()
end

function Roll.OnInfo(text, sender)
  if not Roll.SenderIsLeader(sender) then return end
  local id, remain, tier, itemId, banner = text:match("^I~(%d+)~(%d+)~([01])~(%d+)~(.*)$")
  id = tonumber(id)
  if not id or id ~= TGC.watch.id then return end
  TGC.watch.tier = tier == "1"
  TGC.watch.itemId = tonumber(itemId) or TGC.watch.itemId
  if banner and banner ~= "" then TGC.watch.banner = banner end
  if TGC.watch.active and remain then TGC.watch.endsAt = Clock() + tonumber(remain) end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

function Roll.OnState(text, sender)
  if not Roll.SenderIsLeader(sender) then return end
  local id, index, count, data = text:match("^U~(%d+)~(%d+)~(%d+)~(.*)$")
  id, index, count = tonumber(id), tonumber(index), tonumber(count)
  if not id or id ~= TGC.watch.id or not index or not count or count < 1 or count > 40 or index < 1 or index > count then return end
  Roll.parts = Roll.parts or {}
  local box = Roll.parts[id]
  if not box or box.countExpected ~= count then
    box = { countExpected = count, got = {}, count = 0 }
    Roll.parts[id] = box
  end
  if not box.got[index] then
    box.got[index] = data
    box.count = box.count + 1
  end
  if box.count < count then return end
  local pieces = {}
  for piece = 1, count do pieces[piece] = box.got[piece] or "" end
  Roll.parts[id] = nil
  TGC.watch.rows = Roll.ParseRows(table.concat(pieces, ""))
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

function Roll.OnTie(text, sender)
  if not Roll.SenderIsLeader(sender) then return end
  local id, names = text:match("^B~(%d+)~(.*)$")
  id = tonumber(id)
  if not id or id ~= TGC.watch.id then return end
  TGC.watch.tie = true
  TGC.watch.tieNames = {}
  for _, name in ipairs(TGC.Split(names or "", ";")) do
    if name ~= "" then TGC.watch.tieNames[#TGC.watch.tieNames + 1] = name end
  end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
end

function Roll.OnEnd(text, sender)
  if not Roll.SenderIsLeader(sender) then return end
  local id = tonumber(text:match("^E~(%d+)$"))
  if not id or id ~= TGC.watch.id then return end
  TGC.watch.active = false
  TGC.watch.closed = true
  if TGC.watch.endsAt and TGC.watch.endsAt > Clock() then TGC.watch.endsAt = Clock() end
  if TGC.UI and TGC.UI.UpdatePopup then TGC.UI.UpdatePopup() end
end

function Roll.OnSystem(text)
  if not TGC.IsRaidLeader() or not TGC.session.acceptRolls then return end
  if TGC.Secret(text) or type(text) ~= "string" then return end
  local roller, amount, low, high = text:match(Roll.Pattern())
  amount, low, high = tonumber(amount), tonumber(low), tonumber(high)
  if not roller or low ~= 1 or high ~= 100 then return end
  local member, unclear = TGC.ResolveMember(roller)
  if unclear or not member then return end
  local response = TGC.session.responses[member.key]
  if not response or response.roll then return end
  local inTie = false
  for _, name in ipairs(TGC.watch.tieNames or {}) do
    if TGC.SamePlayer(name, member.name) then inTie = true end
  end
  if not inTie then return end
  response.roll = amount
  Roll.Publish()
  local winner, still, pending = TGC.PickRolls(TGC.watch.result and TGC.watch.result.tied or {}, function(row)
    local saved = TGC.session.responses[row.key]
    return saved and saved.roll
  end)
  if winner then
    TGC.watch.tie = false
    TGC.session.acceptRolls = false
    TGC.Announce(winner.name .. " wins the tie with a " .. winner.roll .. ".", false)
  elseif still and not pending then
    for _, row in ipairs(still) do
      local saved = TGC.session.responses[row.key]
      if saved then saved.roll = nil end
    end
    TGC.Announce("The tie roll is still tied. Those players roll 100 again.", false)
    Roll.Publish()
  end
end
