-- Saved-record codec for TGC Loot. No game API calls: the logic tests load this file directly.
local _, TGC = ...

TGC.CODEC = 1

function TGC.Split(text, sep)
  local out, start = {}, 1
  if type(text) ~= "string" or text == "" then
    if text == "" then out[1] = "" end
    return out
  end
  local seplen = #sep
  while true do
    local found = text:find(sep, start, true)
    if not found then
      out[#out + 1] = text:sub(start)
      return out
    end
    out[#out + 1] = text:sub(start, found - 1)
    start = found + seplen
  end
end

function TGC.Clean(text, max)
  text = tostring(text or "")
  text = text:gsub("[|%c]", " ")
  text = text:gsub("%s+", " ")
  text = text:match("^%s*(.-)%s*$") or ""
  if max and max > 0 and #text > max then text = text:sub(1, max) end
  return text
end

-- Packed fields use these characters as separators, so they cannot appear inside a field.
function TGC.CleanTight(text, max)
  text = TGC.Clean(text, max)
  text = text:gsub("[|^,;~]", "")
  return text
end

function TGC.Key(name)
  if type(name) ~= "string" then return nil end
  local trimmed = name:gsub("%-.*$", "")
  trimmed = trimmed:lower():gsub("%s+", " ")
  trimmed = trimmed:match("^%s*(.-)%s*$")
  if not trimmed or trimmed == "" then return nil end
  return trimmed
end

function TGC.Num(value, fallback)
  local number = tonumber(value)
  if not number then return fallback or 0 end
  return number
end

function TGC.Checksum(text)
  local sum = 0
  text = text or ""
  for i = 1, #text do
    sum = (sum * 33 + text:byte(i)) % 1000000007
  end
  return sum
end

function TGC.NewDB(guild)
  return {
    rev = 0,
    updated = 0,
    writer = "",
    guild = guild or "",
    nextWin = 0,
    settings = { seconds = 30, resetDay = 2, resetHour = 15, officerMax = 1 },
    lockout = { id = "", label = "", week = 0, started = 0 },
    tierItems = {},
    players = {},
    reservations = {},
    log = {},
  }
end

local function Clamp(number, low, high, fallback)
  number = tonumber(number)
  if not number then return fallback end
  if number < low then return low end
  if number > high then return high end
  return number
end

local function SortedKeys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function EncodeWin(win)
  return table.concat({
    tostring(win.w or 0),
    win.tier and "1" or "0",
    tostring(win.item or 0),
    tostring(win.t or 0),
    TGC.CleanTight(win.lockout, 24),
    TGC.CleanTight(win.spec, 8),
    win.plus and "1" or "0",
    tostring(win.n or 0),
    TGC.CleanTight(win.reason, 80),
    TGC.CleanTight(win.itemName, 48),
  }, "^")
end

local function DecodeWin(text)
  local fields = TGC.Split(text, "^")
  if not fields[1] or fields[1] == "" then return nil end
  return {
    w = TGC.Num(fields[1]),
    tier = fields[2] == "1",
    item = TGC.Num(fields[3]),
    t = TGC.Num(fields[4]),
    lockout = fields[5] or "",
    spec = fields[6] or "",
    plus = fields[7] == "1",
    n = TGC.Num(fields[8]),
    reason = fields[9] or "",
    itemName = fields[10] or "",
  }
end

local function EncodePlayer(player)
  local weeks, seen = {}, {}
  for _, week in ipairs(player.weeks or {}) do
    week = tonumber(week)
    if week and not seen[week] then
      seen[week] = true
      weeks[#weeks + 1] = tostring(week)
    end
  end
  table.sort(weeks, function(a, b) return tonumber(a) < tonumber(b) end)

  local raids = {}
  for _, raid in ipairs(player.raids or {}) do
    if raid.id and raid.id ~= "" then
      raids[#raids + 1] = tostring(raid.w or 0) .. "^" .. TGC.CleanTight(raid.id, 24)
    end
  end
  table.sort(raids)

  local wins = {}
  for _, win in ipairs(player.wins or {}) do wins[#wins + 1] = win end
  table.sort(wins, function(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
    return (a.n or 0) < (b.n or 0)
  end)
  local packedWins = {}
  for _, win in ipairs(wins) do packedWins[#packedWins + 1] = EncodeWin(win) end

  local current = player.current or {}
  return table.concat({
    TGC.Clean(player.name, 48),
    TGC.CleanTight(player.class, 16),
    TGC.CleanTight(player.spec, 24),
    player.guild == nil and "u" or (player.guild and "g" or "p"),
    tostring(player.joined or 0),
    table.concat(weeks, ","),
    table.concat(raids, ","),
    table.concat(packedWins, ","),
    TGC.CleanTight(current.lockout, 24),
    tostring(current.tier or 0),
    tostring(current.other or 0),
  }, "|")
end

local function UniqueNumbers(text, cap)
  local list, seen = {}, {}
  for _, part in ipairs(TGC.Split(text or "", ",")) do
    local number = tonumber(part)
    if number and not seen[number] then
      seen[number] = true
      list[#list + 1] = number
    end
  end
  table.sort(list)
  while #list > cap do table.remove(list, 1) end
  return list
end

local function DecodePlayer(rest)
  local fields = TGC.Split(rest, "|")
  local name = TGC.Clean(fields[1], 48)
  if name == "" then return nil end
  local weeks = UniqueNumbers(fields[6], 40)
  local raids = {}
  local raidSeen = {}
  for _, part in ipairs(TGC.Split(fields[7] or "", ",")) do
    if part ~= "" then
      local raidFields = TGC.Split(part, "^")
      local id = TGC.CleanTight(raidFields[2], 24)
      if id ~= "" and not raidSeen[id] then
        raidSeen[id] = true
        raids[#raids + 1] = { w = TGC.Num(raidFields[1]), id = id }
      end
    end
  end
  while #raids > 40 do table.remove(raids, 1) end

  local wins = {}
  for _, part in ipairs(TGC.Split(fields[8] or "", ",")) do
    local win = part ~= "" and DecodeWin(part) or nil
    if win then wins[#wins + 1] = win end
  end
  while #wins > 80 do table.remove(wins, 1) end

  local guildFlag = false
  if fields[4] == "g" then guildFlag = true
  elseif fields[4] == "u" then guildFlag = nil end

  return {
    name = name,
    class = TGC.CleanTight(fields[2], 16),
    spec = TGC.CleanTight(fields[3], 24),
    guild = guildFlag,
    joined = TGC.Num(fields[5]),
    weeks = weeks,
    raids = raids,
    wins = wins,
    current = {
      lockout = TGC.CleanTight(fields[9], 24),
      tier = TGC.Num(fields[10]),
      other = TGC.Num(fields[11]),
    },
  }
end

function TGC.Encode(db, forSum)
  db = db or TGC.NewDB()
  local settings = db.settings or {}
  local lockout = db.lockout or {}
  local lines = {
    "1",
    table.concat({
      tostring(db.rev or 0),
      forSum and "0" or tostring(db.updated or 0),
      forSum and "" or TGC.Clean(db.writer, 48),
      TGC.Clean(db.guild, 64),
      tostring(db.nextWin or 0),
    }, "|"),
    table.concat({
      tostring(settings.seconds or 30),
      tostring(settings.resetDay or 2),
      tostring(settings.resetHour or 15),
      tostring(settings.officerMax or 1),
    }, "|"),
    table.concat({
      TGC.CleanTight(lockout.id, 24),
      TGC.CleanTight(lockout.label, 40),
      tostring(lockout.week or 0),
      tostring(lockout.started or 0),
    }, "|"),
  }

  local tierIds = {}
  for id, on in pairs(db.tierItems or {}) do
    local number = tonumber(id)
    if on and number then tierIds[#tierIds + 1] = tostring(number) end
  end
  table.sort(tierIds, function(a, b) return tonumber(a) < tonumber(b) end)
  lines[#lines + 1] = "T|" .. table.concat(tierIds, ",")

  for _, key in ipairs(SortedKeys(db.players)) do
    local player = db.players[key]
    if type(player) == "table" and player.name and player.name ~= "" then
      lines[#lines + 1] = "P|" .. EncodePlayer(player)
    end
  end

  local reservations = {}
  for _, reservation in ipairs(db.reservations or {}) do reservations[#reservations + 1] = reservation end
  table.sort(reservations, function(a, b)
    if (a.item or 0) ~= (b.item or 0) then return (a.item or 0) < (b.item or 0) end
    return (a.player or "") < (b.player or "")
  end)
  for _, reservation in ipairs(reservations) do
    lines[#lines + 1] = "R|" .. table.concat({
      tostring(reservation.item or 0),
      TGC.Clean(reservation.player, 48),
      TGC.Clean(reservation.by, 48),
      tostring(reservation.t or 0),
      TGC.Clean(reservation.note, 80),
      TGC.Clean(reservation.itemName, 48),
    }, "|")
  end

  local log = {}
  for _, entry in ipairs(db.log or {}) do log[#log + 1] = entry end
  table.sort(log, function(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
    return (a.text or "") < (b.text or "")
  end)
  for _, entry in ipairs(log) do
    lines[#lines + 1] = "N|" .. table.concat({
      tostring(entry.t or 0),
      TGC.Clean(entry.by, 48),
      TGC.Clean(entry.text, 160),
    }, "|")
  end
  return table.concat(lines, "\n")
end

function TGC.ContentSum(db)
  return TGC.Checksum(TGC.Encode(db, true))
end

function TGC.Decode(text)
  if type(text) ~= "string" or text == "" then return nil, "empty" end
  if #text > 200000 then return nil, "too large" end
  local lines = TGC.Split(text, "\n")
  if lines[1] ~= "1" or #lines < 5 then return nil, "version" end

  local db = TGC.NewDB()
  local header = TGC.Split(lines[2] or "", "|")
  db.rev = math.floor(TGC.Num(header[1]))
  db.updated = TGC.Num(header[2])
  db.writer = TGC.Clean(header[3], 48)
  db.guild = TGC.Clean(header[4], 64)
  db.nextWin = math.floor(TGC.Num(header[5]))

  local settings = TGC.Split(lines[3] or "", "|")
  db.settings = {
    seconds = math.floor(Clamp(settings[1], 5, 180, 30)),
    resetDay = math.floor(Clamp(settings[2], 1, 7, 2)),
    resetHour = math.floor(Clamp(settings[3], 0, 23, 15)),
    officerMax = math.floor(Clamp(settings[4], 0, 10, 1)),
  }

  local lockout = TGC.Split(lines[4] or "", "|")
  db.lockout = {
    id = TGC.CleanTight(lockout[1], 24),
    label = TGC.CleanTight(lockout[2], 40),
    week = math.floor(TGC.Num(lockout[3])),
    started = TGC.Num(lockout[4]),
  }

  local highest = db.nextWin
  for index = 5, #lines do
    local line = lines[index]
    if line and line ~= "" then
      local op, rest = line:match("^(%a)|(.*)$")
      if op == "T" then
        for _, id in ipairs(TGC.Split(rest or "", ",")) do
          local number = tonumber(id)
          if number then db.tierItems[number] = true end
        end
      elseif op == "P" then
        local player = DecodePlayer(rest or "")
        local key = player and TGC.Key(player.name)
        if key then
          db.players[key] = player
          for _, win in ipairs(player.wins) do
            if win.n > highest then highest = win.n end
          end
        end
      elseif op == "R" then
        local fields = TGC.Split(rest or "", "|")
        local player = TGC.Clean(fields[2], 48)
        local item = tonumber(fields[1])
        if item and player ~= "" and #db.reservations < 80 then
          db.reservations[#db.reservations + 1] = {
            item = item,
            player = player,
            by = TGC.Clean(fields[3], 48),
            t = TGC.Num(fields[4]),
            note = TGC.Clean(fields[5], 80),
            itemName = TGC.Clean(fields[6], 48),
          }
        end
      elseif op == "N" then
        local fields = TGC.Split(rest or "", "|")
        local entryText = TGC.Clean(fields[3], 160)
        if entryText ~= "" and #db.log < 60 then
          db.log[#db.log + 1] = {
            t = TGC.Num(fields[1]),
            by = TGC.Clean(fields[2], 48),
            text = entryText,
          }
        end
      end
    end
  end
  db.nextWin = highest
  return db
end

function TGC.CodecTest()
  local db = TGC.NewDB("Test Guild")
  db.rev = 4
  db.updated = 50
  db.writer = "Ada Wren"
  db.nextWin = 2
  db.settings = { seconds = 25, resetDay = 3, resetHour = 11, officerMax = 2 }
  db.lockout = { id = "abc", label = "MC", week = 100, started = 40 }
  db.tierItems = { [19019] = true, [123] = true }
  db.players[TGC.Key("Ada Wren")] = {
    name = "Ada Wren", class = "WARRIOR", spec = "Fury", guild = true, joined = 10,
    weeks = { 100, 99 }, raids = { { w = 100, id = "abc" } },
    wins = {
      { w = 100, tier = true, item = 19019, t = 40, lockout = "abc", spec = "MS", plus = true, n = 2, reason = "", itemName = "Thunderfury" },
    },
    current = { lockout = "abc", tier = 1, other = 0 },
  }
  db.players[TGC.Key("Bea Quinn")] = {
    name = "Bea Quinn", class = "PRIEST", spec = "", guild = nil, joined = 0,
    weeks = {}, raids = {}, wins = {}, current = { lockout = "", tier = 0, other = 0 },
  }
  db.reservations[1] = { item = 19019, player = "Ada Wren", by = "Officer", t = 12, note = "discussed", itemName = "Thunderfury" }
  db.log[1] = { t = 12, by = "Officer", text = "Told the raid before pull." }

  local again = TGC.Decode(TGC.Encode(db))
  if not again then return false, "decode failed" end
  if again.rev ~= 4 or again.guild ~= "Test Guild" or again.nextWin ~= 2 then return false, "header" end
  if again.settings.seconds ~= 25 or again.settings.resetDay ~= 3 or again.settings.officerMax ~= 2 then return false, "settings" end
  if again.lockout.id ~= "abc" or again.lockout.label ~= "MC" or again.lockout.week ~= 100 then return false, "lockout" end
  if not again.tierItems[19019] or not again.tierItems[123] then return false, "tier items" end
  local player = again.players[TGC.Key("Ada Wren")]
  if not player or player.spec ~= "Fury" or not player.guild then return false, "player" end
  local bea = again.players[TGC.Key("Bea Quinn")]
  if not bea or bea.guild ~= nil then return false, "unknown guild flag" end
  if #player.weeks ~= 2 or #player.wins ~= 1 or not player.wins[1].plus or player.wins[1].item ~= 19019 then return false, "wins" end
  if player.current.tier ~= 1 or player.current.lockout ~= "abc" then return false, "current" end
  if #again.reservations ~= 1 or again.reservations[1].note ~= "discussed" then return false, "reservation" end
  if #again.log ~= 1 then return false, "log" end
  if TGC.ContentSum(db) ~= TGC.ContentSum(again) then return false, "checksum drifted" end
  if TGC.Encode(again, true) ~= TGC.Encode(db, true) then return false, "encode drifted" end
  return true
end
