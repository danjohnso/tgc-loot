-- Guild members can view the record. Officers keep the authoritative copy.
-- New loot changes are sent only by the raid leader, who has to be an officer or the guild master.
local _, TGC = ...

TGC.Comm = TGC.Comm or {}
local Comm = TGC.Comm

Comm.queue = {}
Comm.parts = {}
Comm.sawSnapshotRev = nil

local function DataChannel()
  if IsInGuild and IsInGuild() then return "GUILD" end
  return nil
end

local function RollChannel()
  local home = LE_PARTY_CATEGORY_HOME or 1
  local instance = LE_PARTY_CATEGORY_INSTANCE or 2
  if IsInGroup and IsInGroup(instance) and not IsInGroup(home) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

function Comm.Queue(message, kind)
  if type(message) ~= "string" or message == "" then return end
  if #message > 255 then
    TGC.Debug("Dropped an oversized addon message (" .. #message .. ")")
    return
  end
  Comm.queue[#Comm.queue + 1] = { message = message, kind = kind or "data" }
  Comm.Pump()
end

function Comm.Pump()
  if Comm.pumping then return end
  Comm.pumping = true
  Comm.Step()
end

function Comm.Step()
  Comm.pumping = false
  if #Comm.queue == 0 then return end
  if TGC.ChatLocked() then
    if C_Timer then C_Timer.After(2, Comm.Pump) end
    return
  end
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  local item = table.remove(Comm.queue, 1)
  local channel = item.kind == "roll" and RollChannel() or DataChannel()
  if not channel then
    if #Comm.queue > 0 and C_Timer then C_Timer.After(0.05, Comm.Pump) end
    return
  end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, TGC.PREFIX, item.message, channel)
  local throttled = result == 3 or result == 8 or result == 11
  if not ok or throttled then
    table.insert(Comm.queue, 1, item)
    if C_Timer then C_Timer.After(0.6, Comm.Pump) end
    return
  end
  if type(result) == "number" and result ~= 0 then
    TGC.Debug("Addon message refused (" .. tostring(result) .. ")")
  end
  if #Comm.queue > 0 and C_Timer then C_Timer.After(0.12, Comm.Pump) end
end

function Comm.SendDelta(rev, line)
  local message = "D~" .. tostring(rev) .. "~" .. line
  if #message > 255 then
    TGC.Print("That loot change is too long to sync.")
    return
  end
  Comm.Queue(message, "data")
end

function Comm.SendSnapshot()
  if not TGC.db then return end
  local payload = TGC.Encode(TGC.db, false)
  local sum = TGC.ContentSum(TGC.db)
  local rev = TGC.db.rev or 0
  local size = 180
  local count = math.max(1, math.ceil(#payload / size))
  if count > 400 then
    TGC.Print("The loot record is too large to sync.")
    return
  end
  Comm.lastServeRev = rev
  Comm.lastServeAt = GetTime and GetTime() or 0
  for index = 1, count do
    local part = payload:sub((index - 1) * size + 1, index * size)
    Comm.Queue(string.format("K~%d~%d~%d~%d~%s", rev, sum, index, count, part), "data")
  end
end

function Comm.Hello()
  if not TGC.db then return end
  local rank = 2
  if IsGuildLeader and IsGuildLeader() then rank = 0
  elseif TGC.IsOfficer() then rank = 1 end
  Comm.Queue(string.format("H~%d~%d~%d", TGC.db.rev or 0, TGC.ContentSum(TGC.db), rank), "data")
end

function Comm.ConsiderRequest()
  local now = GetTime and GetTime() or 0
  if Comm.asked and now - Comm.asked < 10 then return end
  Comm.asked = now
  Comm.Queue(string.format("N~%d", TGC.db and TGC.db.rev or 0), "data")
end

function Comm.ConsiderServe()
  if not TGC.IsOfficer() or Comm.serveTimer then return end
  Comm.serveTimer = true
  local delay = (IsGuildLeader and IsGuildLeader()) and 0.4 or 1.3
  local function fire()
    Comm.serveTimer = false
    if not TGC.IsOfficer() or not TGC.db then return end
    if Comm.sawSnapshotRev == TGC.db.rev then return end
    local now = GetTime and GetTime() or 0
    if Comm.lastServeRev == TGC.db.rev and now - (Comm.lastServeAt or 0) < 15 then return end
    Comm.SendSnapshot()
  end
  if C_Timer then C_Timer.After(delay, fire) else fire() end
end

local function NoteSnapshot(rev)
  Comm.sawSnapshotRev = rev
end

function Comm.OnHello(text, sender)
  local rev, sum, rank = text:match("^H~(%d+)~(%d+)~(%d+)$")
  rev, sum, rank = tonumber(rev), tonumber(sum), tonumber(rank)
  if not rev or not TGC.db then return end
  local officer = TGC.SenderIsOfficer(sender)
  if officer and rev > TGC.db.rev then
    Comm.ConsiderRequest()
  elseif officer and rev == TGC.db.rev and sum ~= TGC.ContentSum(TGC.db) then
    TGC.Print(TGC.ShortName(sender) .. " has revision " .. rev .. " as well, but the contents differ.")
  elseif rev < TGC.db.rev and TGC.IsOfficer() then
    Comm.ConsiderServe()
  end
  TGC.Debug("Hello " .. sender .. " rev " .. rev .. " rank " .. tostring(rank))
end

function Comm.OnNeed(text, sender)
  local rev = tonumber(text:match("^N~(%d+)$"))
  if not rev or not TGC.db then return end
  if rev < TGC.db.rev and TGC.IsOfficer() then Comm.ConsiderServe() end
  TGC.Debug("Need from " .. sender)
end

function Comm.OnChunk(text, sender)
  local rev, sum, index, count, data = text:match("^K~(%d+)~(%d+)~(%d+)~(%d+)~(.*)$")
  rev, sum, index, count = tonumber(rev), tonumber(sum), tonumber(index), tonumber(count)
  if not rev or not index or not count or count < 1 or count > 400 or index < 1 or index > count then return end
  if not TGC.SenderIsOfficer(sender) then return end
  NoteSnapshot(rev)
  local key = (TGC.Key(sender) or sender) .. "|" .. rev
  local box = Comm.parts[key]
  if not box or box.countExpected ~= count then
    box = { countExpected = count, sum = sum, got = {}, count = 0 }
    Comm.parts[key] = box
  end
  if not box.got[index] then
    box.got[index] = data
    box.count = box.count + 1
  end
  if box.count < count then return end
  local pieces = {}
  for piece = 1, count do pieces[piece] = box.got[piece] or "" end
  Comm.parts[key] = nil
  local payload = table.concat(pieces, "")
  local db, err = TGC.Decode(payload)
  if not db then
    TGC.Debug("Bad snapshot from " .. sender .. ": " .. tostring(err))
    return
  end
  if TGC.ContentSum(db) ~= sum or db.rev ~= rev then
    TGC.Print("Rejected a loot snapshot from " .. TGC.ShortName(sender) .. " because it failed its check.")
    return
  end
  TGC.AcceptSnapshot(db, sender)
end

function Comm.OnDelta(text, sender)
  local rev, line = text:match("^D~(%d+)~(.*)$")
  rev = tonumber(rev)
  if not rev or not line or line == "" or not TGC.db then return end
  local function apply()
    if not TGC.SenderIsOfficer(sender) then
      TGC.Debug("Ignored a loot change from " .. sender)
      return
    end
    if TGC.InGroup() then
      local leader = TGC.LeaderName()
      if not leader or not TGC.SamePlayer(leader, sender) then
        TGC.Debug("Ignored a loot change from " .. sender .. " because they are not the raid leader.")
        return
      end
    end
    if rev <= (TGC.db.rev or 0) then return end
    if rev > (TGC.db.rev or 0) + 1 then
      Comm.ConsiderRequest()
      return
    end
    TGC.db.writer = TGC.ShortName(sender)
    if not TGC.ApplyLine(line) then return end
    TGC.db.rev = rev
    TGC.db.updated = TGC.Now()
    if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  end
  if not TGC.rosterLoaded then TGC.DeferUntilRoster(apply) else apply() end
end

function Comm.OnSpec(text, sender)
  if not TGC.CanMutate() then return end
  local spec = TGC.CleanTight(text:match("^P~(.*)$") or "", 24)
  local member, unclear = TGC.ResolveMember(sender)
  if unclear then
    TGC.Print("A main spec came in as \"" .. TGC.ShortName(sender) .. "\", and it matches more than one raider.")
    return
  end
  local name = member and member.name or TGC.ShortName(sender)
  local key = TGC.Key(name)
  local player = key and TGC.db.players[key]
  if player and player.spec == spec then return end
  TGC.Mutate("S|" .. TGC.Clean(name, 48) .. "|" .. spec)
end

function Comm.OnMessage(prefix, text, _, sender)
  if TGC.Secret(prefix) or prefix ~= TGC.PREFIX then return end
  if TGC.Secret(text) or TGC.Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  if TGC.SamePlayer(sender, TGC.PlayerName()) then return end
  local kind = text:sub(1, 1)
  if kind == "H" then Comm.OnHello(text, sender)
  elseif kind == "N" then Comm.OnNeed(text, sender)
  elseif kind == "K" then Comm.OnChunk(text, sender)
  elseif kind == "D" then Comm.OnDelta(text, sender)
  elseif kind == "P" then Comm.OnSpec(text, sender)
  elseif kind == "O" and TGC.Roll then TGC.Roll.OnOpen(text, sender)
  elseif kind == "R" and TGC.Roll then TGC.Roll.OnResponse(text, sender)
  elseif kind == "U" and TGC.Roll then TGC.Roll.OnState(text, sender)
  elseif kind == "I" and TGC.Roll then TGC.Roll.OnInfo(text, sender)
  elseif kind == "B" and TGC.Roll then TGC.Roll.OnTie(text, sender)
  elseif kind == "E" and TGC.Roll then TGC.Roll.OnEnd(text, sender)
  end
end
