-- Events, slash commands, and the addon compartment button.
local _, TGC = ...

local function HelloLoop()
  if TGC.db and TGC.rosterLoaded and TGC.Comm and TGC.Comm.Hello then TGC.Comm.Hello() end
  if C_Timer then C_Timer.After(20, HelloLoop) end
end

local function Refresh()
  if TGC.UI and TGC.UI.Refresh then TGC.UI.Refresh() end
end

local function OnEvent(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= "TGCLoot" then return end
    TGC.InitDB()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      pcall(C_ChatInfo.RegisterAddonMessagePrefix, TGC.PREFIX)
    end
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if not TGC.saved then TGC.InitDB() end
    TGC.BindGuild()
    TGC.RefreshRoster()
    if event == "PLAYER_LOGIN" then
      if TGC.UI and TGC.UI.Init then TGC.UI.Init() end
      if C_Timer then C_Timer.After(3, HelloLoop) end
    end
    Refresh()
  elseif event == "PLAYER_GUILD_UPDATE" then
    TGC.BindGuild()
    TGC.RefreshRoster()
    Refresh()
  elseif event == "GUILD_ROSTER_UPDATE" then
    TGC.ReadRoster()
    TGC.BindGuild()
    Refresh()
  elseif event == "GROUP_ROSTER_UPDATE" then
    Refresh()
  elseif event == "CHAT_MSG_ADDON" then
    if TGC.Comm and TGC.Comm.OnMessage then TGC.Comm.OnMessage(...) end
  elseif event == "CHAT_MSG_SYSTEM" then
    if TGC.Roll and TGC.Roll.OnSystem then TGC.Roll.OnSystem(...) end
  elseif event == "LOOT_OPENED" then
    if TGC.Loot then
      TGC.Loot.open = true
      TGC.Loot.Scan()
    end
    Refresh()
  elseif event == "LOOT_CLOSED" then
    if TGC.Loot then
      TGC.Loot.open = false
      TGC.Loot.slots = {}
    end
    Refresh()
  elseif event == "LOOT_SLOT_CLEARED" then
    if TGC.Loot then
      TGC.Loot.SlotCleared(...)
      TGC.Loot.Scan()
    end
    Refresh()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if TGC.UI and TGC.UI.NoteItem then TGC.UI.NoteItem(...) end
  end
end

local function Help()
  TGC.Print("Open the window with /tgcloot or /tgc.")
  TGC.Print("/tgcloot spec Fury — declare your main spec.")
  TGC.Print("/tgcloot lockout MC — start a lockout and take attendance.")
  TGC.Print("/tgcloot attendance — record raiders who joined after the start.")
  TGC.Print("/tgcloot push — send the full record. /tgcloot pull — take a newer one.")
  TGC.Print("/tgcloot scores — print scores. /tgcloot void Name 12 reason — exceptional correction.")
  TGC.Print("/tgcloot test — run the rules self-test. /tgcloot debug — show who can edit.")
end

local function VoidCommand(rest)
  local name, n, reason = (rest or ""):match("^(.-)%s+(%d+)%s+(.+)$")
  if not name or name == "" or not reason then
    TGC.Print("Usage: /tgcloot void Name 12 reason")
    return
  end
  TGC.VoidWin(name, tonumber(n), reason)
end

local function Scores()
  local rows = TGC.RosterRows and TGC.RosterRows() or {}
  if #rows == 0 then
    TGC.Print("No raiders in the record yet.")
    return
  end
  local limit = #rows
  if limit > 40 then limit = 40 end
  for index = 1, limit do
    local row = rows[index]
    TGC.Print(string.format("%s - %s - tier %s, non-tier %s",
      row.name or "", TGC.StatusName(row.status), TGC.FormatScore(row.tierScore), TGC.FormatScore(row.otherScore)))
  end
  if #rows > limit then TGC.Print("Showing 40 of " .. #rows .. ".") end
end

local function Debug(rest)
  TGC.saved = TGC.saved or {}
  TGC.saved.ui = TGC.saved.ui or {}
  TGC.saved.ui.debug = not TGC.saved.ui.debug
  local ok, why = TGC.CanMutate()
  local count = 0
  for _ in pairs(TGC.roster or {}) do count = count + 1 end
  TGC.Print("Debug " .. (TGC.saved.ui.debug and "on." or "off."))
  TGC.Print(string.format("You: %s. Guild: %s. Raid leader: %s. Officer: %s.",
    tostring(TGC.PlayerName()), tostring(TGC.GuildName()), tostring(TGC.LeaderName()), tostring(TGC.IsOfficer())))
  TGC.Print(ok and "This character can change the loot record." or (why or "View only."))
  TGC.Print(string.format("Revision %s. Guild roster names loaded: %d. Session changed: %s.",
    tostring(TGC.db and TGC.db.rev), count, tostring(TGC.sessionDirty)))
  if rest and rest ~= "" then
    local member, unclear = TGC.ResolveMember(rest)
    local found = member and member.name or "nobody"
    if unclear then found = found .. " (more than one raider has that first name)" end
    TGC.Print("Resolve " .. rest .. " -> " .. found)
  end
end

local function Slash(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = text:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "show" or cmd == "toggle" then
    if TGC.UI and TGC.UI.Toggle then TGC.UI.Toggle() end
  elseif cmd == "spec" then
    TGC.DeclareSpec(rest)
  elseif cmd == "lockout" then
    TGC.StartLockout(rest)
  elseif cmd == "attendance" then
    TGC.RecordAttendance()
  elseif cmd == "push" then
    local ok, why = TGC.CanMutate()
    if not ok then
      TGC.Print(why)
    elseif TGC.Comm and TGC.Comm.SendSnapshot then
      TGC.Comm.SendSnapshot()
      TGC.Print("Sent the loot record.")
    end
  elseif cmd == "pull" then
    TGC.PullSnapshot()
  elseif cmd == "scores" then
    Scores()
  elseif cmd == "void" then
    VoidCommand(rest)
  elseif cmd == "test" then
    local passed, err = TGC.SelfTest()
    if passed then TGC.Print("Self-test passed.")
    else TGC.Print("Self-test failed: " .. tostring(err)) end
  elseif cmd == "debug" then
    Debug(rest)
  elseif cmd == "help" then
    Help()
  else
    TGC.Print("Unknown command. /tgcloot help")
  end
end

function TGCLoot_Compartment()
  if TGC.UI and TGC.UI.Toggle then TGC.UI.Toggle() end
end

if SlashCmdList then
  SLASH_TGCLOOT1 = "/tgcloot"
  SLASH_TGCLOOT2 = "/tgc"
  SlashCmdList.TGCLOOT = Slash
end

if CreateFrame then
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("ADDON_LOADED")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_GUILD_UPDATE")
  frame:RegisterEvent("GUILD_ROSTER_UPDATE")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:RegisterEvent("CHAT_MSG_SYSTEM")
  frame:RegisterEvent("LOOT_OPENED")
  frame:RegisterEvent("LOOT_CLOSED")
  frame:RegisterEvent("LOOT_SLOT_CLEARED")
  frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  frame:SetScript("OnEvent", OnEvent)
end
