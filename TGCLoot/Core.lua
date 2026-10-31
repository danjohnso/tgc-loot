-- Names, saved record, and the mutations the raid leader is allowed to make.
local _, TGC = ...

TGC.VERSION = "1.0.0"
TGC.PREFIX = "TGCLoot"
TGC.roster = {}
TGC.rosterLoaded = false
TGC.sessionDirty = false

function TGC.Secret(value)
  return issecretvalue ~= nil and issecretvalue(value) == true
end

function TGC.Print(message)
  print("|cffe0b060TGC Loot:|r " .. tostring(message))
end

function TGC.Debug(message)
  if TGC.saved and TGC.saved.ui and TGC.saved.ui.debug then
    print("|cff8a8478TGC:|r " .. tostring(message))
  end
end

function TGC.Now()
  if TGC._now then return TGC._now end
  if GetServerTime then
    local ok, stamp = pcall(GetServerTime)
    if ok and type(stamp) == "number" and not TGC.Secret(stamp) then return stamp end
  end
  return time()
end

function TGC.CurrentWeek()
  local settings = TGC.db and TGC.db.settings or {}
  return TGC.WeekId(TGC.Now(), settings.resetDay, settings.resetHour)
end

function TGC.ChatLocked()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() == true
end

function TGC.InGroup()
  if TGC._group ~= nil then return TGC._group end
  return IsInGroup and IsInGroup() and true or false
end

function TGC.GuildName()
  if not GetGuildInfo then return nil end
  local ok, name = pcall(GetGuildInfo, "player")
  if ok and type(name) == "string" and name ~= "" and not TGC.Secret(name) then return name end
end

function TGC.ShortName(name)
  if type(name) ~= "string" then return "" end
  return (name:gsub("%-.*$", ""))
end

function TGC.ItemID(link)
  if type(link) == "number" then return link end
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)")) or tonumber(link)
end

function TGC.ItemNameFromLink(link)
  if type(link) ~= "string" then return "" end
  return link:match("%[(.-)%]") or ""
end

function TGC.FullUnitName(unit, listed)
  local best
  local function consider(name)
    if type(name) ~= "string" or TGC.Secret(name) or name == "" then return end
    if UNKNOWNOBJECT and name == UNKNOWNOBJECT then return end
    name = name:gsub("%-.*$", "")
    if name == "" then return end
    local function spaced(value) return value:find(" ", 1, true) ~= nil end
    if not best or (spaced(name) and not spaced(best)) then best = name end
  end
  if unit and GetUnitName then
    local ok, name = pcall(GetUnitName, unit, true)
    if ok then consider(name) end
  end
  if unit and UnitName then
    local ok, name = pcall(UnitName, unit)
    if ok then consider(name) end
  end
  consider(listed)
  return best
end

function TGC.PlayerName()
  return TGC.FullUnitName("player") or (UnitName and UnitName("player")) or nil
end

function TGC.GroupRoster()
  local list = {}
  local function add(unit, listed, rank)
    local name = TGC.FullUnitName(unit, listed)
    if not name then return end
    local classFile
    if UnitClass then
      local ok, _, file = pcall(UnitClass, unit)
      if ok and type(file) == "string" and not TGC.Secret(file) then classFile = file end
    end
    list[#list + 1] = { name = name, key = TGC.Key(name), class = classFile, unit = unit, rank = rank or 0 }
  end
  if IsInRaid and IsInRaid() then
    for index = 1, GetNumGroupMembers() do
      local ok, name, rank = pcall(GetRaidRosterInfo, index)
      if not ok or TGC.Secret(name) then name, rank = nil, 0 end
      add("raid" .. index, type(name) == "string" and name or nil, tonumber(rank) or 0)
    end
  elseif TGC.InGroup() then
    add("player", nil, UnitIsGroupLeader and UnitIsGroupLeader("player") and 2 or 0)
    for index = 1, GetNumSubgroupMembers() do
      local unit = "party" .. index
      add(unit, nil, UnitIsGroupLeader and UnitIsGroupLeader(unit) and 2 or 0)
    end
  else
    add("player", nil, 0)
  end
  return list
end

-- member, unclear, candidates. Unclear means a shared first name and no surname to separate them.
function TGC.ResolveMember(name, roster)
  roster = roster or (TGC.GroupRoster and TGC.GroupRoster() or {})
  local key = TGC.Key(name)
  if not key then return nil, false end
  for _, member in ipairs(roster) do
    if member.key == key then return member, false end
  end
  local first = key:match("^(%S+)")
  local hits = {}
  for _, member in ipairs(roster) do
    if member.key and member.key:match("^(%S+)") == first then hits[#hits + 1] = member end
  end
  if #hits == 1 and not key:find(" ", 1, true) then return hits[1], false end
  if #hits > 1 and not key:find(" ", 1, true) then return nil, true, hits end
  return nil, false
end

function TGC.SamePlayer(a, b)
  local left, right = TGC.Key(a), TGC.Key(b)
  if not left or not right then return false end
  if left == right then return true end
  local roster = TGC.GroupRoster()
  local memberA = TGC.ResolveMember(a, roster)
  local memberB = TGC.ResolveMember(b, roster)
  return memberA ~= nil and memberB ~= nil and memberA.key == memberB.key
end

function TGC.LeaderName()
  for _, member in ipairs(TGC.GroupRoster()) do
    if member.rank == 2 then return member.name end
    if member.unit and UnitIsGroupLeader and UnitIsGroupLeader(member.unit) then return member.name end
  end
end

function TGC.IsRaidLeader()
  if TGC._leader ~= nil then return TGC._leader end
  if not TGC.InGroup() then return false end
  return UnitIsGroupLeader and UnitIsGroupLeader("player") and true or false
end

function TGC.IsOfficer()
  if TGC._officer ~= nil then return TGC._officer end
  if IsGuildLeader and IsGuildLeader() then return true end
  if C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() then return true end
  if not GetGuildInfo then return false end
  local ok, _, _, rankIndex = pcall(GetGuildInfo, "player")
  if not ok or type(rankIndex) ~= "number" or TGC.Secret(rankIndex) then return false end
  if rankIndex == 0 then return true end
  local maxRank = TGC.db and TGC.db.settings and TGC.db.settings.officerMax or 1
  return rankIndex <= maxRank
end

function TGC.CanMutate()
  if not TGC.db then return false, "Loot data is still loading." end
  if TGC.InGroup() then
    if not TGC.IsRaidLeader() then
      return false, "Only the raid leader can change loot during a raid."
    end
    if TGC.GuildName() and not TGC.IsOfficer() then
      return false, "The raid leader has to be the guild master or an officer."
    end
    return true
  end
  if TGC.GuildName() and not TGC.IsOfficer() then
    return false, "Only officers can prepare the loot record. Everyone else can view it."
  end
  return true
end

function TGC.RoleText()
  local ok, why = TGC.CanMutate()
  if ok and TGC.InGroup() then
    return "Raid leader. Awards you confirm are the guild record."
  end
  if ok and TGC.GuildName() then
    return "Officer prep. During a raid, only the raid leader can change loot."
  end
  if ok then return "Not in a guild. This copy stays on this account until you join one." end
  return why or "View only."
end

function TGC.RefreshRoster()
  if not IsInGuild or not IsInGuild() then
    TGC.roster = {}
    TGC.rosterLoaded = true
    return
  end
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then pcall(GuildRoster) end
end

function TGC.ReadRoster()
  TGC.roster = {}
  if not IsInGuild or not IsInGuild() then
    TGC.rosterLoaded = true
    return
  end
  if not GetNumGuildMembers or not GetGuildRosterInfo then return end
  local ok, count = pcall(GetNumGuildMembers)
  if not ok or type(count) ~= "number" or TGC.Secret(count) then return end
  for index = 1, count do
    local fine, name, _, rankIndex, _, _, _, _, _, _, _, classFile = pcall(GetGuildRosterInfo, index)
    if fine and type(name) == "string" and not TGC.Secret(name) then
      local key = TGC.Key(name)
      if key then
        TGC.roster[key] = {
          name = (name:gsub("%-.*$", "")),
          rankIndex = tonumber(rankIndex) or 99,
          class = type(classFile) == "string" and not TGC.Secret(classFile) and classFile or nil,
        }
      end
    end
  end
  TGC.rosterLoaded = true
  if TGC.deferred then
    local waiting = TGC.deferred
    TGC.deferred = nil
    for _, callback in ipairs(waiting) do callback() end
  end
end

function TGC.DeferUntilRoster(callback)
  if TGC.rosterLoaded then
    callback()
    return
  end
  TGC.deferred = TGC.deferred or {}
  if #TGC.deferred < 30 then TGC.deferred[#TGC.deferred + 1] = callback end
  TGC.RefreshRoster()
end

function TGC.LookupRoster(nameOrKey)
  if not nameOrKey or not TGC.roster then return nil end
  if TGC.roster[nameOrKey] then return TGC.roster[nameOrKey], nameOrKey end
  local key = TGC.Key(nameOrKey)
  if key and TGC.roster[key] then return TGC.roster[key], key end
  if not key then return nil end
  local first = key:match("^(%S+)")
  local found, foundKey, hits = nil, nil, 0
  for rosterKey, info in pairs(TGC.roster) do
    if rosterKey:match("^(%S+)") == first then
      hits = hits + 1
      found, foundKey = info, rosterKey
    end
  end
  if hits == 1 then return found, foundKey end
end

function TGC.SenderIsOfficer(sender)
  if TGC.SamePlayer(sender, TGC.PlayerName()) then return TGC.IsOfficer() end
  local info = TGC.LookupRoster(sender)
  if not info then return false end
  if info.rankIndex == 0 then return true end
  local maxRank = TGC.db and TGC.db.settings and TGC.db.settings.officerMax or 1
  return info.rankIndex <= maxRank
end

function TGC.PlayerIsGuild(key, player)
  -- A stored true or false is an attendance or officer decision and wins over the live roster.
  if player and player.guild ~= nil then return player.guild and true or false end
  if TGC.rosterLoaded then return TGC.LookupRoster(key or (player and player.name)) ~= nil end
  return false
end

function TGC.Sanitize(db, guild)
  if type(db) ~= "table" then db = TGC.NewDB(guild) end
  db.guild = guild or db.guild or ""
  db.rev = tonumber(db.rev) or 0
  db.updated = tonumber(db.updated) or 0
  db.writer = type(db.writer) == "string" and db.writer or ""
  db.nextWin = tonumber(db.nextWin) or 0
  db.settings = type(db.settings) == "table" and db.settings or {}
  db.settings.seconds = tonumber(db.settings.seconds) or 30
  db.settings.resetDay = tonumber(db.settings.resetDay) or 2
  db.settings.resetHour = tonumber(db.settings.resetHour) or 15
  db.settings.officerMax = tonumber(db.settings.officerMax) or 1
  db.lockout = type(db.lockout) == "table" and db.lockout or { id = "", label = "", week = 0, started = 0 }
  db.tierItems = type(db.tierItems) == "table" and db.tierItems or {}
  db.players = type(db.players) == "table" and db.players or {}
  db.reservations = type(db.reservations) == "table" and db.reservations or {}
  db.log = type(db.log) == "table" and db.log or {}
  local highest = db.nextWin
  for _, player in pairs(db.players) do
    if type(player) == "table" then
      player.weeks = type(player.weeks) == "table" and player.weeks or {}
      player.raids = type(player.raids) == "table" and player.raids or {}
      player.wins = type(player.wins) == "table" and player.wins or {}
      player.current = type(player.current) == "table" and player.current or { lockout = "", tier = 0, other = 0 }
      for _, win in ipairs(player.wins) do
        if type(win) == "table" and (win.n or 0) > highest then highest = win.n end
      end
    end
  end
  db.nextWin = highest
  return db
end

function TGC.InitDB()
  if type(TGCLootDB) ~= "table" then TGCLootDB = {} end
  TGC.saved = TGCLootDB
  TGC.saved.ui = TGC.saved.ui or { minimap = 220, popup = true }
  if TGC.saved.ui.popup == nil then TGC.saved.ui.popup = true end
  TGC.saved.guilds = TGC.saved.guilds or {}
  TGC.saved.specs = TGC.saved.specs or {}
  TGC.BindGuild()
end

function TGC.BindGuild()
  if not TGC.saved then return false end
  local guild = TGC.GuildName()
  if not guild then
    if IsInGuild and IsInGuild() then return false end
    guild = "*"
  end
  TGC.saved.guilds[guild] = TGC.Sanitize(TGC.saved.guilds[guild], guild == "*" and "" or guild)
  TGC.db = TGC.saved.guilds[guild]
  return true
end

function TGC.InstallDB(db)
  db = TGC.Sanitize(db, db.guild)
  local guild = TGC.db and TGC.db.guild or ""
  if guild == "" then guild = db.guild end
  if guild == "" then guild = "*" end
  db.guild = guild == "*" and db.guild or guild
  if TGC.saved then
    local storeKey = guild == "" and "*" or guild
    if storeKey == "" then storeKey = "*" end
    TGC.saved.guilds[storeKey] = db
  end
  TGC.db = db
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

function TGC.Ensure(name, class)
  local key = TGC.Key(name)
  if not key or not TGC.db then return nil end
  local display = TGC.ShortName(TGC.Clean(name, 48))
  local player = TGC.db.players[key]
  if not player then
    player = {
      name = display, class = TGC.CleanTight(class, 16), spec = "", guild = nil, joined = 0,
      weeks = {}, raids = {}, wins = {}, current = { lockout = "", tier = 0, other = 0 },
    }
    TGC.db.players[key] = player
  else
    if class and class ~= "" then player.class = TGC.CleanTight(class, 16) end
    if display:find(" ", 1, true) and not tostring(player.name):find(" ", 1, true) then player.name = display end
  end
  return player, key
end

function TGC.AddLog(stamp, by, text)
  text = TGC.Clean(text, 160)
  if text == "" or not TGC.db then return end
  TGC.db.log[#TGC.db.log + 1] = { t = stamp or TGC.Now(), by = TGC.Clean(by, 48), text = text }
  while #TGC.db.log > 60 do table.remove(TGC.db.log, 1) end
end

function TGC.RecomputeCurrent(player, lockoutId)
  local tier, other = 0, 0
  if lockoutId and lockoutId ~= "" then
    for _, win in ipairs(player.wins) do
      if win.plus and win.lockout == lockoutId then
        if win.tier then tier = tier + 1 else other = other + 1 end
      end
    end
  end
  player.current = { lockout = lockoutId or "", tier = tier, other = other }
end

function TGC.Prune(db, weekNow)
  if not db or not weekNow or weekNow <= 0 then return end
  local keep = weekNow - 8
  for _, player in pairs(db.players) do
    if type(player) == "table" then
      local weeks = {}
      for _, week in ipairs(player.weeks or {}) do
        if week > keep then weeks[#weeks + 1] = week end
      end
      player.weeks = weeks
      local wins = {}
      for _, win in ipairs(player.wins or {}) do
        if (win.w or 0) > keep then wins[#wins + 1] = win end
      end
      player.wins = wins
      local raids = {}
      for _, raid in ipairs(player.raids or {}) do
        if (raid.w or 0) > keep then raids[#raids + 1] = raid end
      end
      player.raids = raids
    end
  end
  while #db.log > 60 do table.remove(db.log, 1) end
end

local function PushWeek(player, week)
  for _, have in ipairs(player.weeks) do
    if have == week then return false end
  end
  player.weeks[#player.weeks + 1] = week
  table.sort(player.weeks)
  while #player.weeks > 40 do table.remove(player.weeks, 1) end
  return true
end

local function PushRaid(player, week, raidId)
  if raidId == "" then return false end
  for _, raid in ipairs(player.raids) do
    if raid.id == raidId then return false end
  end
  player.raids[#player.raids + 1] = { w = week, id = raidId }
  while #player.raids > 40 do table.remove(player.raids, 1) end
  return true
end

function TGC.ApplyLine(line)
  local db = TGC.db
  if not db or type(line) ~= "string" then return false end
  local op, rest = line:match("^(%a)|(.*)$")
  if not op or not rest then return false end

  if op == "L" then
    local fields = TGC.Split(rest, "|")
    local id = TGC.CleanTight(fields[1], 24)
    if id == "" then return false end
    db.lockout = {
      id = id,
      label = TGC.CleanTight(fields[2], 40),
      week = math.floor(TGC.Num(fields[3])),
      started = TGC.Num(fields[4]),
    }
    TGC.Prune(db, db.lockout.week)
    return true
  end

  if op == "A" then
    local fields = TGC.Split(rest, "|")
    local week = math.floor(TGC.Num(fields[1]))
    local lockout = TGC.CleanTight(fields[2], 24)
    local stamp = TGC.Num(fields[3])
    local changed = false
    for _, packed in ipairs(TGC.Split(fields[4] or "", ";")) do
      if packed ~= "" then
        local bits = TGC.Split(packed, "^")
        local player = TGC.Ensure(bits[2], bits[3])
        if player then
          local guilded = bits[1] == "g"
          if player.guild ~= guilded then
            player.guild = guilded
            changed = true
          end
          if (player.joined or 0) == 0 then
            player.joined = stamp
            changed = true
          end
          if PushWeek(player, week) then changed = true end
          if PushRaid(player, week, lockout) then changed = true end
        end
      end
    end
    return changed
  end

  if op == "W" then
    local fields = TGC.Split(rest, "|")
    local player = TGC.Ensure(fields[1], fields[2])
    if not player then return false end
    local n = math.floor(TGC.Num(fields[10]))
    if n <= 0 then n = (db.nextWin or 0) + 1 end
    if n > (db.nextWin or 0) then db.nextWin = n end
    local item = math.floor(TGC.Num(fields[3]))
    local tier = fields[4] == "1"
    player.wins[#player.wins + 1] = {
      w = math.floor(TGC.Num(fields[7])),
      tier = tier,
      item = item,
      t = TGC.Num(fields[8]),
      lockout = TGC.CleanTight(fields[9], 24),
      spec = TGC.CleanTight(fields[5], 8),
      plus = fields[6] == "1",
      n = n,
      reason = TGC.Clean(fields[11], 80),
      itemName = TGC.Clean(fields[12], 48),
    }
    while #player.wins > 80 do table.remove(player.wins, 1) end
    TGC.RecomputeCurrent(player, TGC.CleanTight(fields[9], 24))
    if item > 0 then db.tierItems[item] = tier or nil end
    if fields[11] and TGC.Clean(fields[11], 80) ~= "" then
      TGC.AddLog(TGC.Num(fields[8]), db.writer, TGC.Clean(fields[11], 80))
    end
    return true
  end

  if op == "V" then
    local fields = TGC.Split(rest, "|")
    local key = TGC.Key(fields[1])
    local player = key and db.players[key]
    if not player then return false end
    local n = math.floor(TGC.Num(fields[2]))
    local removed, index
    if n > 0 then
      for i, win in ipairs(player.wins) do
        if win.n == n then removed, index = win, i break end
      end
    else
      for i = #player.wins, 1, -1 do
        if player.wins[i].plus then removed, index = player.wins[i], i break end
      end
    end
    if not removed then return false end
    table.remove(player.wins, index)
    TGC.RecomputeCurrent(player, removed.lockout)
    TGC.AddLog(TGC.Now(), db.writer, "Voided " .. player.name .. " item " .. tostring(removed.item) .. ". " .. TGC.Clean(fields[3], 120))
    return true
  end

  if op == "S" then
    local fields = TGC.Split(rest, "|")
    local player = TGC.Ensure(fields[1], nil)
    if not player then return false end
    local spec = TGC.CleanTight(fields[2], 24)
    if player.spec == spec then return false end
    player.spec = spec
    return true
  end

  if op == "F" then
    local fields = TGC.Split(rest, "|")
    local player = TGC.Ensure(fields[1], nil)
    if not player then return false end
    local guilded = fields[2] == "1"
    if player.guild == guilded then return false end
    player.guild = guilded
    return true
  end

  if op == "R" then
    local fields = TGC.Split(rest, "|")
    local item = tonumber(fields[1])
    local player = TGC.Clean(fields[2], 48)
    if not item or player == "" then return false end
    local note = TGC.Clean(fields[5], 80)
    local itemName = TGC.Clean(fields[6], 48)
    for _, reservation in ipairs(db.reservations) do
      if reservation.item == item and TGC.Key(reservation.player) == TGC.Key(player) then
        reservation.note, reservation.itemName, reservation.by, reservation.t = note, itemName, TGC.Clean(fields[3], 48), TGC.Num(fields[4])
        return true
      end
    end
    if #db.reservations >= 80 then table.remove(db.reservations, 1) end
    db.reservations[#db.reservations + 1] = {
      item = item, player = player, by = TGC.Clean(fields[3], 48), t = TGC.Num(fields[4]), note = note, itemName = itemName,
    }
    return true
  end

  if op == "X" then
    local fields = TGC.Split(rest, "|")
    local item = tonumber(fields[1])
    local key = TGC.Key(fields[2])
    for index, reservation in ipairs(db.reservations) do
      if reservation.item == item and TGC.Key(reservation.player) == key then
        table.remove(db.reservations, index)
        return true
      end
    end
    return false
  end

  if op == "G" then
    local fields = TGC.Split(rest, "|")
    db.settings.seconds = math.floor(math.max(5, math.min(180, TGC.Num(fields[1], 30))))
    db.settings.resetDay = math.floor(math.max(1, math.min(7, TGC.Num(fields[2], 2))))
    db.settings.resetHour = math.floor(math.max(0, math.min(23, TGC.Num(fields[3], 15))))
    db.settings.officerMax = math.floor(math.max(0, math.min(10, TGC.Num(fields[4], 1))))
    return true
  end

  if op == "T" then
    local fields = TGC.Split(rest, "|")
    local item = tonumber(fields[1])
    if not item then return false end
    local tier = fields[2] == "1"
    local have = db.tierItems[item] and true or false
    if have == tier then return false end
    db.tierItems[item] = tier or nil
    return true
  end

  if op == "N" then
    local fields = TGC.Split(rest, "|")
    local text = TGC.Clean(fields[3], 160)
    if text == "" then return false end
    TGC.AddLog(TGC.Num(fields[1]), fields[2], text)
    return true
  end

  return false
end

function TGC.Mutate(line)
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return false, why
  end
  TGC.db.writer = TGC.PlayerName() or TGC.db.writer or ""
  if not TGC.ApplyLine(line) then return false, "Nothing changed." end
  TGC.db.rev = (TGC.db.rev or 0) + 1
  TGC.db.updated = TGC.Now()
  if TGC.InGroup() then TGC.sessionDirty = true end
  if TGC.Comm and TGC.Comm.SendDelta then TGC.Comm.SendDelta(TGC.db.rev, line) end
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  return true
end

function TGC.BuildAttendanceLines()
  local lock = TGC.db and TGC.db.lockout
  if not lock or lock.id == "" then return {} end
  local week = lock.week ~= 0 and lock.week or TGC.CurrentWeek()
  local pending = {}
  for _, member in ipairs(TGC.GroupRoster()) do
    local player = TGC.db.players[member.key]
    local have = false
    if player then
      for _, raid in ipairs(player.raids) do
        if raid.id == lock.id then have = true break end
      end
    end
    if not have then
      local guilded = TGC.PlayerIsGuild(member.key, player) and "g" or "p"
      pending[#pending + 1] = guilded .. "^" .. TGC.CleanTight(member.name, 40) .. "^" .. TGC.CleanTight(member.class, 16)
    end
  end
  local lines, batch = {}, nil
  local function flush()
    if batch then
      lines[#lines + 1] = string.format("A|%d|%s|%d|%s", week, lock.id, TGC.Now(), batch)
      batch = nil
    end
  end
  for _, person in ipairs(pending) do
    local combined = batch and (batch .. ";" .. person) or person
    if #string.format("A|%d|%s|%d|%s", week, lock.id, TGC.Now(), combined) > 230 and batch then
      flush()
      batch = person
    else
      batch = combined
    end
  end
  flush()
  return lines
end

function TGC.Say(lines, warning)
  local index = 1
  local function step()
    local line = lines[index]
    if not line then return end
    index = index + 1
    TGC.Announce(line, warning)
    if C_Timer and lines[index] then C_Timer.After(0.35, step) end
  end
  step()
end

function TGC.Announce(message, warning)
  message = tostring(message or "")
  if #message > 250 then message = message:sub(1, 250) end
  local channel
  local home = LE_PARTY_CATEGORY_HOME or 1
  local instance = LE_PARTY_CATEGORY_INSTANCE or 2
  if IsInGroup and IsInGroup(instance) and not IsInGroup(home) then channel = "INSTANCE_CHAT"
  elseif IsInRaid and IsInRaid() then
    if warning and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then channel = "RAID_WARNING"
    else channel = "RAID" end
  elseif TGC.InGroup() then channel = "PARTY" end
  if not channel then
    TGC.Print(message)
    return
  end
  if TGC.ChatLocked() then
    TGC.Print("Chat is locked until the fight ends. Not sent: " .. message)
    return
  end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if not send or not pcall(send, message, channel) then
    TGC.Print("Couldn't send: " .. message)
  end
end

function TGC.AnnounceReservations()
  local lines = {}
  for _, reservation in ipairs(TGC.db.reservations or {}) do
    local name = reservation.itemName ~= "" and reservation.itemName or ("item " .. tostring(reservation.item))
    local note = reservation.note ~= "" and (" (" .. reservation.note .. ")") or ""
    lines[#lines + 1] = "Reserved: " .. name .. " — " .. reservation.player .. note
  end
  if #lines == 0 then return end
  TGC.Say(lines, false)
end

function TGC.StartLockout(label)
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return false, why
  end
  label = TGC.CleanTight(label, 40)
  if label == "" then label = "Raid" end
  local id = string.format("%x%04x", TGC.Now() % 1048576, math.random(0, 65535))
  local worked, err = TGC.Mutate(string.format("L|%s|%s|%d|%d", id, label, TGC.CurrentWeek(), TGC.Now()))
  if not worked then return false, err end
  local lines = TGC.BuildAttendanceLines()
  for _, line in ipairs(lines) do TGC.Mutate(line) end
  TGC.AnnounceReservations()
  TGC.Print("Lockout \"" .. label .. "\" started. Current raid items reset. Attendance recorded for " .. #TGC.GroupRoster() .. ".")
  return true
end

function TGC.RecordAttendance()
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return false, why
  end
  if not TGC.db.lockout or TGC.db.lockout.id == "" then return TGC.StartLockout("Raid") end
  local lines = TGC.BuildAttendanceLines()
  if #lines == 0 then
    TGC.Print("Attendance is already recorded for this lockout.")
    return true
  end
  for _, line in ipairs(lines) do TGC.Mutate(line) end
  TGC.Print("Attendance updated.")
  return true
end

function TGC.DeclareSpec(text)
  text = TGC.CleanTight(text, 24)
  local name = TGC.PlayerName()
  if not name then return false, "Your character name isn't available yet." end
  if TGC.saved then TGC.saved.specs[TGC.Key(name)] = text end
  if TGC.CanMutate() then return TGC.Mutate("S|" .. TGC.Clean(name, 48) .. "|" .. text) end
  if TGC.Comm and TGC.Comm.Queue then
    TGC.Comm.Queue("P~" .. text, "roll")
    TGC.Comm.Queue("P~" .. text, "data")
  end
  TGC.Print("Main spec saved on this character. The raid leader's addon records it for the guild.")
  return true
end

function TGC.SaveSettings(seconds, day, hour, officerMax)
  return TGC.Mutate(string.format("G|%d|%d|%d|%d",
    math.floor(tonumber(seconds) or 30),
    math.floor(tonumber(day) or 2),
    math.floor(tonumber(hour) or 15),
    math.floor(tonumber(officerMax) or 1)))
end

function TGC.SetGuildFlag(name, isGuild)
  return TGC.Mutate("F|" .. TGC.Clean(name, 48) .. "|" .. (isGuild and "1" or "0"))
end

function TGC.AddReservation(link, player, note)
  local item = TGC.ItemID(link)
  if not item then return false, TGC.Print("Paste an item link or item id.") end
  player = TGC.Clean(player, 48)
  if player == "" then return false, TGC.Print("Name the player the item is reserved for.") end
  local itemName = TGC.ItemNameFromLink(link)
  return TGC.Mutate(table.concat({
    "R", tostring(item), player, TGC.Clean(TGC.PlayerName(), 48), tostring(TGC.Now()),
    TGC.Clean(note, 80), TGC.Clean(itemName, 48),
  }, "|"))
end

function TGC.RemoveReservation(item, player)
  return TGC.Mutate("X|" .. tostring(item) .. "|" .. TGC.Clean(player, 48))
end

function TGC.VoidWin(name, n, reason)
  reason = TGC.Clean(reason, 120)
  if reason == "" then
    TGC.Print("A void needs a reason. It is recorded and is not a normal undo.")
    return false
  end
  return TGC.Mutate("V|" .. TGC.Clean(name, 48) .. "|" .. tostring(n or 0) .. "|" .. reason)
end

function TGC.AwardLine(name, class, item, tier, spec, plus, lockout, reason, itemName)
  local n = (TGC.db.nextWin or 0) + 1
  return "W|" .. table.concat({
    TGC.Clean(name, 40),
    TGC.CleanTight(class, 16),
    tostring(item or 0),
    tier and "1" or "0",
    TGC.CleanTight(spec, 8),
    plus and "1" or "0",
    tostring(TGC.CurrentWeek()),
    tostring(TGC.Now()),
    TGC.CleanTight(lockout, 24),
    tostring(n),
    TGC.Clean(reason, 60),
    TGC.Clean(itemName, 32),
  }, "|")
end

function TGC.History()
  local list = {}
  for _, player in pairs(TGC.db and TGC.db.players or {}) do
    for _, win in ipairs(player.wins or {}) do
      list[#list + 1] = {
        name = player.name, key = TGC.Key(player.name), class = player.class,
        item = win.item, itemName = win.itemName, tier = win.tier, plus = win.plus,
        spec = win.spec, t = win.t, n = win.n, reason = win.reason, week = win.w,
      }
    end
  end
  table.sort(list, function(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
    return (a.n or 0) > (b.n or 0)
  end)
  return list
end

function TGC.Detail(row)
  if not row then return "" end
  local status = TGC.StatusName(row.status or row.statusLetter)
  local how = ""
  if row.currentOnly then
    how = " History is off because a guest is in this contest."
  elseif row.status == "new" or row.statusLetter == "N" then
    how = string.format(" New member uses average %s or personal %s, whichever is higher.",
      TGC.FormatScore(row.guildAvg), TGC.FormatScore(row.personal))
  end
  return string.format("%s. Current %d. Rate %s (%d contested wins / %d weeks). Score %s.%s",
    status, row.current or 0, TGC.FormatScore(row.rate), row.wins or 0, row.weeks or 0,
    TGC.FormatScore(row.score), how)
end

function TGC.RosterRows()
  if not TGC.db then return {} end
  local weekNow = TGC.CurrentWeek()
  local lock = TGC.db.lockout and TGC.db.lockout.id or ""
  local isGuild = function(key, player) return TGC.PlayerIsGuild(key, player) end
  local tierAvg = TGC.GuildAverage(TGC.db.players, weekNow, true, isGuild)
  local otherAvg = TGC.GuildAverage(TGC.db.players, weekNow, false, isGuild)
  local rows, seen = {}, {}
  local function add(key, player, name, class)
    if not key or seen[key] then return end
    seen[key] = true
    player = player or { name = name, class = class, spec = "", weeks = {}, wins = {}, raids = {}, current = {} }
    local weeks, tierWins, tierPersonal, raids = TGC.TrackStats(player, weekNow, true)
    local _, otherWins, otherPersonal = TGC.TrackStats(player, weekNow, false)
    local status = TGC.MemberStatus(weeks, isGuild(key, player), raids)
    local tierRate = TGC.EffectiveRate(status, tierPersonal, tierAvg)
    local otherRate = TGC.EffectiveRate(status, otherPersonal, otherAvg)
    rows[#rows + 1] = {
      key = key, name = player.name or name, class = player.class or class, spec = player.spec or "",
      status = status, weeks = weeks, raids = raids, guild = isGuild(key, player),
      tierWins = tierWins, otherWins = otherWins,
      tierRate = tierRate, otherRate = otherRate,
      tierCurrent = TGC.PlayerCurrent(player, lock, true),
      otherCurrent = TGC.PlayerCurrent(player, lock, false),
      tierScore = TGC.ScoreOf(TGC.PlayerCurrent(player, lock, true), tierRate, false),
      otherScore = TGC.ScoreOf(TGC.PlayerCurrent(player, lock, false), otherRate, false),
      guildAvg = otherAvg, personal = otherPersonal, wins = otherWins,
    }
  end
  for key, player in pairs(TGC.db.players) do add(key, player) end
  for _, member in ipairs(TGC.GroupRoster()) do
    add(member.key, TGC.db.players[member.key], member.name, member.class)
  end
  table.sort(rows, function(a, b) return (a.name or "") < (b.name or "") end)
  return rows
end

function TGC.ReplaceDB(incoming)
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return false, why
  end
  if type(incoming) ~= "table" or type(incoming.players) ~= "table" then
    TGC.Print("That text is not a TGC Loot record.")
    return false
  end
  incoming.rev = math.max((TGC.db.rev or 0) + 1, incoming.rev or 0)
  incoming.updated = TGC.Now()
  incoming.writer = TGC.PlayerName() or ""
  if TGC.db.guild and TGC.db.guild ~= "" then incoming.guild = TGC.db.guild end
  if TGC.InGroup() then TGC.sessionDirty = true end
  TGC.InstallDB(incoming)
  if TGC.Comm and TGC.Comm.SendSnapshot then TGC.Comm.SendSnapshot() end
  TGC.Print("Replaced the loot record and sent revision " .. incoming.rev .. ".")
  return true
end

function TGC.AcceptSnapshot(db, sender)
  if not db or not TGC.db then return end
  if TGC.db.guild ~= "" and db.guild ~= "" and db.guild ~= TGC.db.guild then
    TGC.Debug("Rejected a snapshot for " .. tostring(db.guild))
    return
  end
  if not TGC.SenderIsOfficer(sender) then
    TGC.Debug("Rejected a snapshot from " .. tostring(sender))
    return
  end
  if db.rev < (TGC.db.rev or 0) then return end
  if db.rev == (TGC.db.rev or 0) then
    if TGC.ContentSum(db) ~= TGC.ContentSum(TGC.db) then
      TGC.Print(TGC.ShortName(sender) .. " also has revision " .. db.rev .. ", but the contents differ.")
    end
    return
  end
  if TGC.sessionDirty and TGC.IsRaidLeader() then
    TGC.pendingSnapshot = db
    TGC.Print(TGC.ShortName(sender) .. " has a newer loot record (revision " .. db.rev .. "). /tgcloot pull takes it. Your changes this session were left in place.")
    return
  end
  if TGC.db.guild ~= "" then db.guild = TGC.db.guild end
  TGC.InstallDB(db)
  TGC.Print("Loot record updated from " .. TGC.ShortName(sender) .. " (revision " .. db.rev .. ").")
end

function TGC.PullSnapshot()
  if not TGC.pendingSnapshot then
    TGC.Print("There is no newer record waiting.")
    return
  end
  local ok, why = TGC.CanMutate()
  if not ok then
    TGC.Print(why)
    return
  end
  local db = TGC.pendingSnapshot
  TGC.pendingSnapshot = nil
  TGC.sessionDirty = false
  if TGC.db.guild ~= "" then db.guild = TGC.db.guild end
  TGC.InstallDB(db)
  TGC.Print("Took the newer loot record, revision " .. db.rev .. ".")
end

function TGC.LogicTest()
  local savedDb, savedNow = TGC.db, TGC._now
  local function run()
  TGC.db = TGC.NewDB("Test Guild")
  TGC._now = 1700000000
  TGC.db.writer = "Officer"
  local function apply(text) return TGC.ApplyLine(text) end
  if not apply("L|lock1|MC|100|1700000000") then return false, "lockout" end
  if TGC.db.lockout.id ~= "lock1" or TGC.db.lockout.week ~= 100 then return false, "lockout fields" end
  if not apply("A|97|old1|10|g^Ada^WARRIOR") then return false, "attend 97" end
  if not apply("A|98|old2|10|g^Ada^WARRIOR") then return false, "attend 98" end
  if not apply("A|99|old3|10|g^Ada^WARRIOR") then return false, "attend 99" end
  if not apply("A|100|lock1|10|g^Ada^WARRIOR;g^Bea^PRIEST;p^Gus^MAGE") then return false, "attend raid" end
  local ada = TGC.db.players[TGC.Key("Ada")]
  local bea = TGC.db.players[TGC.Key("Bea")]
  local gus = TGC.db.players[TGC.Key("Gus")]
  if not ada or not ada.guild or #ada.weeks ~= 4 then return false, "ada weeks " .. tostring(ada and #ada.weeks) end
  if not bea or not bea.guild or not gus or gus.guild then return false, "guild flags" end
  if not apply("W|Ada|WARRIOR|123|0|MS|1|97|11|old1|1||Bone") then return false, "win" end
  if not apply("W|Ada|WARRIOR|456|1|MS|1|100|12|lock1|2||Tier") then return false, "tier win" end
  if ada.current.tier ~= 1 or ada.current.other ~= 0 or ada.current.lockout ~= "lock1" then
    return false, "current counts"
  end
  if not apply("W|Bea|PRIEST|789|0|MS|0|100|13|lock1|3||Free") then return false, "free" end
  if bea.current.other ~= 0 or bea.current.tier ~= 0 then return false, "free counted" end
  if not TGC.db.tierItems[456] or TGC.db.tierItems[123] then return false, "tier memory" end
  if not apply("V|Ada|2|misclick") then return false, "void" end
  if ada.current.tier ~= 0 then return false, "void cleared current" end
  for _, win in ipairs(ada.wins) do
    if win.n == 2 then return false, "void removed win" end
  end
  local again = TGC.Decode(TGC.Encode(TGC.db))
  if not again or TGC.ContentSum(again) ~= TGC.ContentSum(TGC.db) then return false, "applied record did not round-trip" end
  if not apply("R|19019|Ada|Officer|14|held|Thunderfury") then return false, "reserve" end
  if not apply("S|Bea|Holy") then return false, "spec" end
  if bea.spec ~= "Holy" then return false, "spec saved" end
  if apply("S|Bea|Holy") then return false, "spec no-op should not count as a change" end
  if not apply("G|40|2|15|1") then return false, "settings" end
  if TGC.db.settings.seconds ~= 40 then return false, "seconds" end
  local line = TGC.AwardLine("Ada", "WARRIOR", 99, false, "MS", true, "lock1", "", "Claw")
  if #("D~1~" .. line) > 255 then return false, "award line is too long" end
  if not apply(line) then return false, "award helper" end
  if ada.current.other ~= 1 then return false, "helper did not count" end
  local wasLoaded = TGC.rosterLoaded
  TGC.rosterLoaded = false
  local unknown = { guild = nil }
  if TGC.PlayerIsGuild("x", unknown) then
    TGC.rosterLoaded = wasLoaded
    return false, "unknown guild flag"
  end
  unknown.guild = true
  if not TGC.PlayerIsGuild("x", unknown) then
    TGC.rosterLoaded = wasLoaded
    return false, "member flag"
  end
  unknown.guild = false
  if TGC.PlayerIsGuild("x", unknown) then
    TGC.rosterLoaded = wasLoaded
    return false, "guest flag"
  end
  TGC.rosterLoaded = wasLoaded
  return true
  end
  local ok, a, b = pcall(run)
  TGC.db = savedDb
  TGC._now = savedNow
  if not ok then return false, tostring(a) end
  return a, b
end
