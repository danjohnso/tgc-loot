-- 6-week weighted +1. No game API calls: the logic tests load this file directly.
--
-- Score = current lockout contested main-spec items + (2 x historical rate)
-- Historical rate = contested main-spec wins / raid weeks attended, last 6 weeks.
-- Tier and non-tier keep separate wins, rates, and current counts.
-- Lowest score wins. A tie rolls 1-100.
local _, TGC = ...

TGC.WINDOW = 6
TGC.MEMBER_WEEKS = 4
TGC.GUEST_RAIDS = 4

function TGC.WeekId(serverTime, resetDay, resetHour)
  if type(serverTime) ~= "number" then return 0 end
  resetDay = tonumber(resetDay) or 2
  resetHour = tonumber(resetHour) or 15
  if resetDay < 1 or resetDay > 7 then resetDay = 2 end
  if resetHour < 0 or resetHour > 23 then resetHour = 15 end
  -- 1970-01-01 was a Thursday. resetDay uses 1 = Monday ... 7 = Sunday, so Thursday is 4.
  local offset = (resetDay - 4) * 86400 + resetHour * 3600
  return math.floor((serverTime - offset) / 604800)
end

function TGC.InWindow(week, now)
  return type(week) == "number" and type(now) == "number" and week > now - TGC.WINDOW and week <= now
end

function TGC.TrackStats(player, weekNow, tier)
  local seen, weeks = {}, 0
  for _, week in ipairs(player and player.weeks or {}) do
    if TGC.InWindow(week, weekNow) and not seen[week] then
      seen[week] = true
      weeks = weeks + 1
    end
  end
  local wins = 0
  for _, win in ipairs(player and player.wins or {}) do
    if win.plus and win.tier == tier and TGC.InWindow(win.w, weekNow) then
      wins = wins + 1
    end
  end
  local raidSeen, raids = {}, 0
  for _, raid in ipairs(player and player.raids or {}) do
    if raid.id and raid.id ~= "" and TGC.InWindow(raid.w, weekNow) and not raidSeen[raid.id] then
      raidSeen[raid.id] = true
      raids = raids + 1
    end
  end
  local personal = 0
  if weeks > 0 then personal = wins / weeks end
  return weeks, wins, personal, raids
end

function TGC.MemberStatus(weeks, inGuild, raids)
  if inGuild then
    if weeks >= TGC.MEMBER_WEEKS then return "established" end
    return "new"
  end
  if (raids or 0) >= TGC.GUEST_RAIDS then return "regular" end
  return "pug"
end

function TGC.EffectiveRate(status, personal, guildAvg)
  if status == "established" or status == "regular" then return personal end
  if status == "new" then
    local average = guildAvg or 0
    if personal > average then return personal end
    return average
  end
  return 0
end

function TGC.GuildAverage(players, weekNow, tier, isGuild)
  local function collect(establishedOnly)
    local wins, weeks = 0, 0
    for key, player in pairs(players or {}) do
      if isGuild(key, player) then
        local attended, taken = TGC.TrackStats(player, weekNow, tier)
        local include = establishedOnly and attended >= TGC.MEMBER_WEEKS or (not establishedOnly and attended > 0)
        if include then
          wins = wins + taken
          weeks = weeks + attended
        end
      end
    end
    if weeks > 0 then return wins / weeks end
  end
  return collect(true) or collect(false) or 0
end

function TGC.PlayerCurrent(player, lockoutId, tier)
  local current = player and player.current
  if not current or lockoutId == nil or lockoutId == "" or current.lockout ~= lockoutId then return 0 end
  if tier then return current.tier or 0 end
  return current.other or 0
end

function TGC.ScoreOf(current, rate, currentOnly)
  if currentOnly then return current or 0 end
  return (current or 0) + 2 * (rate or 0)
end

-- Contested main spec always counts, including an officer picking the winner.
-- An officer redirect of an otherwise free main-spec item also counts.
-- Off spec never counts.
function TGC.AwardPlus(result, overridden)
  if not result or result.priority ~= "MS" then return false end
  if result.contested then return true end
  return overridden and true or false
end

function TGC.StatusLetter(status)
  if status == "established" then return "E" end
  if status == "new" then return "N" end
  if status == "regular" then return "R" end
  return "P"
end

function TGC.StatusName(status)
  if status == "E" or status == "established" then return "Member" end
  if status == "N" or status == "new" then return "New member" end
  if status == "R" or status == "regular" then return "Regular guest" end
  return "Guest"
end

function TGC.FormatScore(number)
  return string.format("%.2f", number or 0)
end

function TGC.Score100(number)
  return math.floor((number or 0) * 100 + 0.5)
end

function TGC.Describe(result)
  if not result or result.empty then return "No main spec or off spec rolls yet." end
  local parts = {}
  if result.currentOnly then
    parts[#parts + 1] = "A guest is competing, so scores are current lockout items only."
  end
  if not result.contested then
    if result.priority == "MS" then
      parts[#parts + 1] = "Uncontested main spec. Free, no +1."
    else
      parts[#parts + 1] = "Uncontested off spec. Free, no +1."
    end
  elseif result.plus then
    parts[#parts + 1] = "Contested main spec. Lowest score wins and takes a +1."
  else
    parts[#parts + 1] = "Contested off spec. Lowest score wins. Off spec is free."
  end
  if result.winner then
    parts[#parts + 1] = "Leading: " .. (result.winner.name or result.winner.key) .. " (" .. TGC.FormatScore(result.winner.score) .. ")."
  elseif result.tied and #result.tied > 1 then
    local names = {}
    for index, row in ipairs(result.tied) do
      if index <= 6 then names[#names + 1] = row.name or row.key end
    end
    parts[#parts + 1] = "Tie: " .. table.concat(names, ", ") .. ". Roll 100."
  end
  return table.concat(parts, " ")
end

local function SameRow(pool, row)
  for _, member in ipairs(pool) do
    if member == row then return true end
  end
  return false
end

function TGC.SortRows(rows)
  local copy = {}
  for index, row in ipairs(rows or {}) do copy[index] = row end
  local function rank(row)
    if row.competing then return 1 end
    if row.choice == "MS" or row.choice == "OS" then return 2 end
    if row.choice == "PASS" then return 3 end
    return 4
  end
  table.sort(copy, function(a, b)
    local left, right = rank(a), rank(b)
    if left ~= right then return left < right end
    if left == 1 and math.abs((a.score or 0) - (b.score or 0)) > 1e-9 then
      return (a.score or 0) < (b.score or 0)
    end
    return (a.name or "") < (b.name or "")
  end)
  return copy
end

-- responses: { key, name, class, spec, choice, roll, unclear }
-- players: map keyed by TGC.Key. isGuild(key, player) -> boolean.
function TGC.Evaluate(responses, players, weekNow, tier, lockoutId, isGuild)
  players = players or {}
  isGuild = isGuild or function() return false end
  local guildAvg = TGC.GuildAverage(players, weekNow, tier, isGuild)
  local ms, os, rows = {}, {}, {}

  local function fill(response)
    local player = players[response.key] or {}
    local weeks, wins, personal, raids = TGC.TrackStats(player, weekNow, tier)
    local status = TGC.MemberStatus(weeks, isGuild(response.key, player) and true or false, raids)
    local rate = TGC.EffectiveRate(status, personal, guildAvg)
    local current = TGC.PlayerCurrent(player, lockoutId, tier)
    return {
      key = response.key,
      name = response.name or player.name or response.key,
      class = response.class or player.class,
      spec = response.spec or player.spec or "",
      choice = response.choice,
      roll = response.roll,
      unclear = response.unclear and true or false,
      weeks = weeks,
      wins = wins,
      personal = personal,
      raids = raids,
      rate = rate,
      current = current,
      status = status,
      statusLetter = TGC.StatusLetter(status),
      guildAvg = guildAvg,
    }
  end

  for _, response in ipairs(responses or {}) do
    if response.choice == "MS" or response.choice == "OS" or response.choice == "PASS" then
      local row = fill(response)
      rows[#rows + 1] = row
      if response.choice == "MS" then ms[#ms + 1] = row
      elseif response.choice == "OS" then os[#os + 1] = row end
    end
  end

  local pool = #ms > 0 and ms or os
  local priority = #ms > 0 and "MS" or (#os > 0 and "OS" or nil)
  local currentOnly = false
  if pool and #pool > 0 then
    for _, row in ipairs(pool) do
      if row.status == "pug" then
        currentOnly = true
        break
      end
    end
  end
  for _, row in ipairs(rows) do
    row.competing = pool and SameRow(pool, row) or false
    row.currentOnly = row.competing and currentOnly or false
    row.score = TGC.ScoreOf(row.current, row.rate, row.currentOnly)
  end

  local result
  if not pool or #pool == 0 then
    result = {
      empty = true, rows = TGC.SortRows(rows), guildAvg = guildAvg,
      currentOnly = false, contested = false, plus = false,
    }
  else
    local best
    for _, row in ipairs(pool) do
      if not best or row.score < best - 1e-9 then best = row.score end
    end
    local tied = {}
    for _, row in ipairs(pool) do
      if math.abs(row.score - best) <= 1e-9 then tied[#tied + 1] = row end
    end
    table.sort(tied, function(a, b) return (a.name or "") < (b.name or "") end)
    result = {
      empty = false,
      rows = TGC.SortRows(rows),
      pool = pool,
      priority = priority,
      tied = tied,
      winner = #tied == 1 and tied[1] or nil,
      best = best,
      contested = #pool >= 2,
      currentOnly = currentOnly,
      guildAvg = guildAvg,
    }
    result.plus = TGC.AwardPlus(result, false)
  end
  result.banner = TGC.Describe(result)
  return result
end

-- Highest roll wins. Missing rolls keep the tie open. A remaining tie is returned for another roll.
function TGC.PickRolls(tied, rollOf)
  local pending, best, winners = {}, nil, nil
  for _, row in ipairs(tied or {}) do
    local roll = rollOf(row)
    if not roll then
      pending[#pending + 1] = row
    elseif not best or roll > best then
      best = roll
      winners = { row }
    elseif roll == best then
      winners[#winners + 1] = row
    end
  end
  if #pending > 0 then return nil, tied, pending end
  if winners and #winners == 1 then return winners[1], nil, nil end
  return nil, winners, nil
end

function TGC.SelfTest()
  local fails = {}
  local function check(condition, message)
    if not condition then fails[#fails + 1] = message end
  end

  local boundary = -118800 -- Tuesday 15:00 UTC, the default week start
  check(TGC.WeekId(boundary, 2, 15) == 0, "week starts on Tuesday 15:00 UTC")
  check(TGC.WeekId(boundary - 1, 2, 15) == -1, "week rolls back before the reset")
  check(TGC.WeekId(boundary + 604800, 2, 15) == 1, "week advances seven days later")
  check(TGC.InWindow(95, 100) and TGC.InWindow(100, 100) and not TGC.InWindow(94, 100), "window is six weeks")

  local function guild(key, player) return player and player.guild end
  local function blank(name, isGuild)
    return {
      name = name, class = "WARRIOR", spec = "", guild = isGuild, joined = 1,
      weeks = {}, raids = {}, wins = {}, current = { lockout = "", tier = 0, other = 0 },
    }
  end
  local function attend(player, week, raidId)
    player.weeks[#player.weeks + 1] = week
    player.raids[#player.raids + 1] = { w = week, id = raidId }
  end
  local function win(player, week, tier, lockout)
    player.wins[#player.wins + 1] = {
      w = week, tier = tier, item = 1, t = week, lockout = lockout, spec = "MS", plus = true, n = #player.wins + 1,
    }
    if player.current.lockout ~= lockout then player.current = { lockout = lockout, tier = 0, other = 0 } end
    if tier then player.current.tier = player.current.tier + 1 else player.current.other = player.current.other + 1 end
  end

  local ada = blank("Ada", true)
  for week = 97, 100 do attend(ada, week, "r" .. week) end
  win(ada, 97, false, "r97")
  local bea = blank("Bea", true)
  attend(bea, 100, "r100")
  local players = { ada = ada, bea = bea }
  check(math.abs(TGC.GuildAverage(players, 100, false, guild) - 0.25) < 1e-9, "average uses established members")
  local newbie = TGC.Evaluate({ { key = "bea", name = "Bea", choice = "MS" } }, players, 100, false, "r100", guild)
  check(newbie.rows[1].status == "new", "under four weeks is new")
  check(math.abs(newbie.rows[1].rate - 0.25) < 1e-9, "new member uses the guild average")
  check(math.abs(newbie.rows[1].score - 0.5) < 1e-9, "score is current plus twice the rate")

  win(bea, 100, false, "r100")
  local lucky = TGC.Evaluate({ { key = "bea", name = "Bea", choice = "MS" } }, players, 100, false, "r100", guild)
  check(math.abs(lucky.rows[1].personal - 1) < 1e-9, "personal rate is wins over weeks")
  check(math.abs(lucky.rows[1].rate - 1) < 1e-9, "a higher personal rate replaces the average")
  bea.wins = {}
  bea.current = { lockout = "", tier = 0, other = 0 }

  local vet = blank("Vet", true)
  for week = 95, 100 do attend(vet, week, "v" .. week) end
  win(vet, 95, false, "v95")
  win(vet, 96, false, "v96")
  -- Both are 2 contested wins over 6 weeks, so the rates match.
  attend(ada, 95, "a95")
  attend(ada, 96, "a96")
  win(ada, 95, false, "a95")
  players.vet = vet
  local even = TGC.Evaluate({
    { key = "ada", name = "Ada", choice = "MS" },
    { key = "vet", name = "Vet", choice = "MS" },
  }, players, 100, false, "none", guild)
  check(even.winner == nil and #even.tied == 2, "equal rates tie")
  check(even.contested and even.plus, "two main spec rolls are a contested +1")

  local one = TGC.Evaluate({
    { key = "ada", name = "Ada", choice = "MS" },
    { key = "bea", name = "Bea", choice = "OS" },
    { key = "vet", name = "Vet", choice = "OS" },
  }, players, 100, false, "none", guild)
  check(one.winner and one.winner.key == "ada" and not one.plus, "one main spec beats off spec and is free")

  local offspec = TGC.Evaluate({
    { key = "ada", name = "Ada", choice = "OS" },
    { key = "vet", name = "Vet", choice = "OS" },
  }, players, 100, false, "none", guild)
  check(offspec.contested and not offspec.plus and offspec.priority == "OS", "contested off spec is free")

  local guest = blank("Gus", false)
  attend(guest, 100, "r100")
  guest.current = { lockout = "r100", tier = 0, other = 0 }
  ada.current = { lockout = "r100", tier = 1, other = 1 }
  players.gus = guest
  local mixed = TGC.Evaluate({
    { key = "ada", name = "Ada", choice = "MS" },
    { key = "gus", name = "Gus", choice = "MS" },
  }, players, 100, false, "r100", guild)
  check(mixed.currentOnly, "an occasional guest makes the whole contest current-only")
  check(mixed.winner and mixed.winner.key == "gus", "the guest with fewer current items wins that contest")
  check(mixed.plus, "that main spec contest still awards a +1")

  local side = TGC.Evaluate({
    { key = "ada", name = "Ada", choice = "MS" },
    { key = "gus", name = "Gus", choice = "OS" },
  }, players, 100, false, "r100", guild)
  check(not side.currentOnly and side.winner.key == "ada", "a guest who is not competing leaves history on")

  for i = 2, 4 do attend(guest, 100, "g" .. i) end
  local regular = TGC.Evaluate({
    { key = "gus", name = "Gus", choice = "MS" },
    { key = "bea", name = "Bea", choice = "MS" },
  }, players, 100, true, "r100", guild)
  local gusRow
  for _, row in ipairs(regular.rows) do
    if row.key == "gus" then gusRow = row end
  end
  check(gusRow and gusRow.status == "regular" and not regular.currentOnly, "four raids in the window makes a regular guest")

  local winner, still, pending = TGC.PickRolls(even.tied, function(row)
    if row.key == "ada" then return 40 end
    if row.key == "vet" then return 80 end
  end)
  check(winner and winner.key == "vet" and not still and not pending, "highest tie roll wins")
  local _, again, waiting = TGC.PickRolls(even.tied, function(row)
    if row.key == "ada" then return 10 end
  end)
  check(again and waiting and waiting[1].key == "vet", "a missing tie roll stays open")

  check(TGC.AwardPlus({ priority = "MS", contested = true }, false), "contested main spec counts")
  check(TGC.AwardPlus({ priority = "MS", contested = false }, true), "an officer redirect of a free main spec counts")
  check(not TGC.AwardPlus({ priority = "OS", contested = true }, true), "off spec never counts")

  if TGC.CodecTest then
    local ok, err = TGC.CodecTest()
    check(ok, err or "codec")
  end
  if TGC.LogicTest then
    local ok, err = TGC.LogicTest()
    check(ok, err or "records")
  end

  if #fails == 0 then return true end
  return false, table.concat(fails, "\n")
end
