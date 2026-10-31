-- Master loot handoff. Forever may expose either the classic loot calls or C_PartyInfo.
local _, TGC = ...

TGC.Loot = TGC.Loot or {}
local Loot = TGC.Loot

Loot.open = false
Loot.slots = {}

local function MasterValue()
  local enum = Enum and Enum.LootMethod
  return enum and (enum.Masterlooter or enum.MasterLooter)
end

function Loot.Method()
  local method, partyID, raidID
  if C_PartyInfo and C_PartyInfo.GetLootMethod then
    local ok, a, b, c = pcall(C_PartyInfo.GetLootMethod)
    if ok then method, partyID, raidID = a, b, c end
  end
  if method == nil and GetLootMethod then
    local ok, a, b, c = pcall(GetLootMethod)
    if ok then method, partyID, raidID = a, b, c end
  end
  if TGC.Secret(method) then return false end
  local master = MasterValue()
  return method == "master" or (master ~= nil and method == master), partyID, raidID
end

function Loot.IsMasterLooter()
  local isMaster, partyID, raidID = Loot.Method()
  if not isMaster then return false end
  if IsMasterLooter then
    local ok, mine = pcall(IsMasterLooter)
    if ok and not TGC.Secret(mine) and mine ~= nil then return mine == true end
  end
  if IsInRaid and IsInRaid() then
    if type(raidID) ~= "number" or TGC.Secret(raidID) then return false end
    local ok, same = pcall(UnitIsUnit, "raid" .. raidID, "player")
    return ok and not TGC.Secret(same) and same == true
  end
  return partyID == 0
end

function Loot.SetMasterLoot()
  local function try(name)
    if type(name) ~= "string" or name == "" then return end
    local master = MasterValue()
    if C_PartyInfo and C_PartyInfo.SetLootMethod and master then
      pcall(C_PartyInfo.SetLootMethod, master, name)
    end
    if SetLootMethod then pcall(SetLootMethod, "master", name) end
  end
  try(UnitName and UnitName("player"))
  local full = TGC.PlayerName()
  if C_Timer then
    C_Timer.After(1, function()
      if Loot.IsMasterLooter() then
        TGC.Print("Master loot is on, with you as the master looter.")
        if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
        return
      end
      try(full)
    end)
  end
end

local function ItemKey(link)
  local body = type(link) == "string" and link:match("|Hitem:([^|]+)")
  if not body then return nil end
  local fields = {}
  for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
  local id = tonumber(fields[1])
  if not id then return nil end
  return id .. ":" .. (tonumber(fields[7]) or 0)
end

function Loot.Scan()
  Loot.slots = {}
  if not Loot.open or not GetNumLootItems or not GetLootSlotLink then return end
  local ok, count = pcall(GetNumLootItems)
  if not ok or type(count) ~= "number" or TGC.Secret(count) then return end
  for slot = 1, count do
    local fine, link = pcall(GetLootSlotLink, slot)
    if fine and type(link) == "string" and not TGC.Secret(link) and link:find("|Hitem:", 1, true) then
      local quality = 0
      if GetLootSlotInfo then
        local infoOk, _, _, _, _, slotQuality = pcall(GetLootSlotInfo, slot)
        if infoOk and type(slotQuality) == "number" and not TGC.Secret(slotQuality) then quality = slotQuality end
      end
      Loot.slots[#Loot.slots + 1] = { slot = slot, link = link, quality = quality, name = TGC.ItemNameFromLink(link) }
    end
  end
end

function Loot.FindSlot(link)
  if not link then return nil end
  local wanted = ItemKey(link)
  local sameId
  for _, slot in ipairs(Loot.slots) do
    if slot.link == link then return slot.slot end
    if not sameId and wanted and ItemKey(slot.link) == wanted then sameId = slot.slot end
  end
  return sameId
end

function Loot.Candidate(slot, name)
  if not GetMasterLootCandidate then return nil, "master loot candidates are unavailable" end
  local loose = {}
  for index = 1, 40 do
    local ok, candidate = pcall(GetMasterLootCandidate, slot, index)
    if ok and type(candidate) == "string" and not TGC.Secret(candidate) then
      if TGC.Key(candidate) == TGC.Key(name) then return index end
      local left, right = TGC.Key(candidate), TGC.Key(name)
      if left and right and left:match("^(%S+)") == right:match("^(%S+)") then
        loose[#loose + 1] = index
      end
    end
  end
  if #loose == 1 then return loose[1] end
  if #loose > 1 and IsInRaid and IsInRaid() then
    local hit
    for _, index in ipairs(loose) do
      local named = TGC.FullUnitName("raid" .. index)
      if named and TGC.Key(named) == TGC.Key(name) then
        if hit then return nil, "more than one raider has that first name" end
        hit = index
      end
    end
    if hit then return hit end
  end
  if #loose > 1 then return nil, "more than one raider has that first name" end
  return nil, "not eligible for this item"
end

function Loot.Give()
  local give = TGC.give
  if not give or give.given then
    TGC.Print("Award an item first.")
    return
  end
  if not GiveMasterLoot or not GetMasterLootCandidate then
    TGC.Print("This client can't hand off master loot. Trade " .. give.name .. " the item.")
    return
  end
  if not Loot.IsMasterLooter() then
    TGC.Print("You need to be the master looter. Trade " .. give.name .. " the item, or turn master loot on.")
    return
  end
  Loot.Scan()
  local slot = Loot.FindSlot(give.link) or give.slot
  if not slot then
    TGC.Print("Open the corpse that still has " .. (give.link or "the item") .. ", then click Give item.")
    return
  end
  local index, why = Loot.Candidate(slot, give.name)
  if not index then
    TGC.Print("Can't hand it to " .. give.name .. " (" .. (why or "not eligible") .. ").")
    return
  end
  local ok, err = pcall(GiveMasterLoot, slot, index)
  if not ok then
    TGC.Print("The game refused to give the item: " .. tostring(err))
    return
  end
  give.slot = slot
  give.pending = true
  if C_Timer then
    C_Timer.After(1.5, function()
      if give.pending and not give.given then
        give.pending = false
        TGC.Print("The item is still in the loot window. Check range and bag space, then try Give item again.")
        if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
      end
    end)
  end
end

function Loot.SlotCleared(slot)
  local give = TGC.give
  if give and give.pending and give.slot == slot then
    give.given = true
    give.pending = false
    TGC.Print(give.link .. " went to " .. give.name .. ".")
    if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
  end
end
