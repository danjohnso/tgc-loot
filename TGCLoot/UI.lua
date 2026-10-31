-- Guild loot window. Frames are created on first use, not when the file loads.
local _, TGC = ...

TGC.UI = TGC.UI or {}
local UI = TGC.UI

local COLORS = {
  bg = { 0.06, 0.07, 0.09 },
  bar = { 0.11, 0.13, 0.16 },
  inset = { 0.08, 0.09, 0.11 },
  edge = { 0.22, 0.24, 0.28 },
  text = { 0.93, 0.91, 0.86 },
  dim = { 0.62, 0.64, 0.68 },
  gold = { 0.86, 0.68, 0.34 },
  green = { 0.45, 0.82, 0.50 },
  blue = { 0.45, 0.68, 0.95 },
  red = { 0.90, 0.40, 0.36 },
}
local FORMULA = "Lowest score wins. Score = current lockout + 2 x 6-week rate. Main spec beats off spec. Uncontested is free."

local main, popup

local function Face()
  return UI.font or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
end

local function Backdrop()
  return { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
end

local function Paint(frame, fill, border, alpha)
  frame:SetBackdropColor(fill[1], fill[2], fill[3], alpha or 1)
  if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], 1) end
end

local function Label(parent, size)
  local text = parent:CreateFontString(nil, "OVERLAY")
  text:SetFont(Face(), size or 12, "")
  text:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
  text:SetJustifyH("LEFT")
  text:SetJustifyV("MIDDLE")
  return text
end

local function Arm(button, on, chosen)
  if not button then return end
  button:SetEnabled(on and true or false)
  if on then
    Paint(button, COLORS.bar, chosen and COLORS.gold or COLORS.edge, 1)
    button.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
  else
    Paint(button, COLORS.inset, COLORS.edge, 0.85)
    button.label:SetTextColor(0.45, 0.46, 0.48)
  end
end

local function Button(parent, text, width, height)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  button:SetSize(width or 80, height or 20)
  button:SetBackdrop(Backdrop())
  Paint(button, COLORS.bar, COLORS.edge, 1)
  button.label = Label(button, 12)
  button.label:SetPoint("CENTER")
  button.label:SetJustifyH("CENTER")
  button.label:SetText(text or "")
  button:SetScript("OnEnter", function(self)
    if self:IsEnabled() then self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1) end
  end)
  button:SetScript("OnLeave", function(self)
    if self.chosen then self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
    else self:SetBackdropBorderColor(COLORS.edge[1], COLORS.edge[2], COLORS.edge[3], 1) end
  end)
  button:SetScript("OnMouseDown", function(self)
    if self:IsEnabled() then self.label:SetPoint("CENTER", 1, -1) end
  end)
  button:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER") end)
  return button
end

local function Edit(parent, width, height, multiline)
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  box:SetSize(width, height or 20)
  box:SetAutoFocus(false)
  box:SetFont(Face(), 12, "")
  box:SetTextInsets(6, 6, multiline and 6 or 2, 2)
  box:SetBackdrop(Backdrop())
  Paint(box, COLORS.inset, COLORS.edge, 1)
  box:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
  if multiline then
    box:SetMultiLine(true)
    box:SetMaxLetters(200000)
  else
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  end
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusGained", function(self)
    self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  end)
  box:SetScript("OnEditFocusLost", function(self)
    self:SetBackdropBorderColor(COLORS.edge[1], COLORS.edge[2], COLORS.edge[3], 1)
  end)
  return box
end

local function SetIdle(box, text)
  if not box or (box.HasFocus and box:HasFocus()) then return end
  text = tostring(text or "")
  if box:GetText() ~= text then box:SetText(text) end
end

local function Check(parent, text, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width or 90, 18)
  button.edge = button:CreateTexture(nil, "BACKGROUND")
  button.edge:SetSize(14, 14)
  button.edge:SetPoint("LEFT", 0, 0)
  button.edge:SetColorTexture(COLORS.edge[1], COLORS.edge[2], COLORS.edge[3], 1)
  button.box = button:CreateTexture(nil, "ARTWORK")
  button.box:SetSize(12, 12)
  button.box:SetPoint("CENTER", button.edge, "CENTER")
  button.box:SetColorTexture(COLORS.inset[1], COLORS.inset[2], COLORS.inset[3], 1)
  button.mark = button:CreateTexture(nil, "OVERLAY")
  button.mark:SetSize(8, 8)
  button.mark:SetPoint("CENTER", button.edge, "CENTER")
  button.mark:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  button.mark:Hide()
  button.text = Label(button, 12)
  button.text:SetPoint("LEFT", button.edge, "RIGHT", 6, 0)
  button.text:SetText(text or "")
  button.checked = false
  function button:SetChecked(on)
    self.checked = on and true or false
    if self.checked then self.mark:Show() else self.mark:Hide() end
  end
  function button:GetChecked()
    return self.checked
  end
  return button
end

local function ClassRGB(class)
  local color = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  if color then return color.r, color.g, color.b end
  return COLORS.text[1], COLORS.text[2], COLORS.text[3]
end

local function Special(name)
  if not UISpecialFrames then return end
  for _, have in ipairs(UISpecialFrames) do
    if have == name then return end
  end
  UISpecialFrames[#UISpecialFrames + 1] = name
end

local function SavePoint(frame, key)
  if not frame or not TGC.saved or not TGC.saved.ui then return end
  local point, _, relative, x, y = frame:GetPoint(1)
  if not point then return end
  TGC.saved.ui.points = TGC.saved.ui.points or {}
  TGC.saved.ui.points[key] = { point, relative or "CENTER", x or 0, y or 0 }
end

local function RestorePoint(frame, key, x, y)
  local saved = TGC.saved and TGC.saved.ui and TGC.saved.ui.points and TGC.saved.ui.points[key]
  frame:ClearAllPoints()
  if saved then frame:SetPoint(saved[1], UIParent, saved[2] or "CENTER", saved[3] or 0, saved[4] or 0)
  else frame:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0) end
end

function UI.Wheel(key, delta)
  local visible = UI.visible[key] or 1
  local count = UI.counts[key] or 0
  local offset = UI.scroll[key] or 0
  local nextOffset = offset - delta
  if nextOffset < 0 then nextOffset = 0 end
  local maxOffset = count - visible
  if maxOffset < 0 then maxOffset = 0 end
  if nextOffset > maxOffset then nextOffset = maxOffset end
  if nextOffset == offset then return end
  UI.scroll[key] = nextOffset
  if key == "popup" then UI.UpdatePopup() else UI.Refresh() end
end

local function ClampScroll(key, count)
  UI.counts[key] = count
  local visible = UI.visible[key] or 1
  local offset = UI.scroll[key] or 0
  local maxOffset = count - visible
  if maxOffset < 0 then maxOffset = 0 end
  if offset < 0 then offset = 0 end
  if offset > maxOffset then offset = maxOffset end
  UI.scroll[key] = offset
  return offset
end

function UI.ItemLabel(id, fallback)
  id = tonumber(id)
  if not id then return fallback or "" end
  UI.names = UI.names or {}
  if UI.names[id] then return UI.names[id] end
  if C_Item and C_Item.GetItemInfo then
    local ok, name = pcall(C_Item.GetItemInfo, id)
    if ok and type(name) == "string" and name ~= "" and not TGC.Secret(name) then
      UI.names[id] = name
      return name
    end
  end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  if type(fallback) == "string" and fallback ~= "" then return fallback end
  return "item " .. tostring(id)
end

function UI.NoteItem(id)
  if not id then return end
  UI.names = UI.names or {}
  if C_Item and C_Item.GetItemInfo then
    local ok, name = pcall(C_Item.GetItemInfo, id)
    if ok and type(name) == "string" and name ~= "" and not TGC.Secret(name) then UI.names[id] = name end
  end
  if UI.noteQueued or not C_Timer then return end
  UI.noteQueued = true
  C_Timer.After(0.25, function()
    UI.noteQueued = false
    if main and main:IsShown() then UI.Refresh() end
  end)
end

local function ItemTexture(link)
  local id = TGC.ItemID(link)
  if id and C_Item then
    if C_Item.GetItemIconByID then
      local ok, icon = pcall(C_Item.GetItemIconByID, id)
      if ok and icon and icon ~= "" and not TGC.Secret(icon) then return icon end
    end
    if C_Item.GetItemInfoInstant then
      local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, id)
      if ok and icon and not TGC.Secret(icon) then return icon end
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function MakeList(parent, count, columns, top, scrollKey, onClick)
  local x = 0
  for _, column in ipairs(columns) do
    local text = Label(parent, 11)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, top)
    text:SetWidth(column.width - 8)
    text:SetText(column.title)
    text:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
    x = x + column.width
  end
  local rows = {}
  for index = 1, count do
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local y = top - 16 - (index - 1) * 18
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    row:SetBackdrop(Backdrop())
    Paint(row, COLORS.inset, COLORS.bg, 1)
    row.labels = {}
    local left = 4
    for _, column in ipairs(columns) do
      local text = Label(row, 12)
      text:SetPoint("LEFT", row, "LEFT", left, 0)
      text:SetWidth(column.width - 8)
      text:SetWordWrap(false)
      if column.align then text:SetJustifyH(column.align) end
      row.labels[column.key] = text
      left = left + column.width
    end
    row:SetScript("OnClick", function(self) if self.data and onClick then onClick(self.data) end end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) UI.Wheel(scrollKey, delta) end)
    row:SetScript("OnEnter", function(self)
      if self.tip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip, COLORS.text[1], COLORS.text[2], COLORS.text[3], 1, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rows[index] = row
  end
  return rows
end

local function Fill(rows, data, offset, chosen, paint)
  for index, row in ipairs(rows) do
    local item = data[offset + index]
    row.data = item
    if not item then
      row:Hide()
    else
      row:Show()
      local selected = chosen and chosen(item)
      if selected then Paint(row, { 0.24, 0.19, 0.10 }, COLORS.gold, 1)
      elseif index % 2 == 0 then Paint(row, { 0.09, 0.10, 0.13 }, COLORS.bg, 1)
      else Paint(row, COLORS.inset, COLORS.bg, 1) end
      paint(row, item)
    end
  end
end

local function RollSource()
  local rows, seen = {}, {}
  for _, row in ipairs(TGC.watch and TGC.watch.rows or {}) do
    rows[#rows + 1] = row
    if row.key then seen[row.key] = true end
  end
  if TGC.IsRaidLeader and TGC.IsRaidLeader() and TGC.GroupRoster then
    for _, member in ipairs(TGC.GroupRoster()) do
      if member.key and not seen[member.key] then
        local player = TGC.db and TGC.db.players[member.key]
        rows[#rows + 1] = {
          key = member.key, name = member.name, class = member.class,
          spec = player and player.spec or "", choice = "", waiting = true,
        }
        seen[member.key] = true
      end
    end
  end
  return rows
end

local function MineInTie()
  if not TGC.watch or not TGC.watch.tie then return false end
  local mine = TGC.PlayerName()
  local listed = false
  for _, name in ipairs(TGC.watch.tieNames or {}) do
    if TGC.SamePlayer(name, mine) then listed = true end
  end
  if not listed then return false end
  for _, row in ipairs(TGC.watch.rows or {}) do
    if TGC.SamePlayer(row.name, mine) and row.roll then return false end
  end
  return true
end

local function ChoiceText(choice)
  if choice == "MS" then return "MS", COLORS.green end
  if choice == "OS" then return "OS", COLORS.blue end
  if choice == "PASS" then return "Pass", COLORS.dim end
  return "-", COLORS.dim
end

function UI.Seconds()
  if not UI.seconds or not UI.seconds.GetText then return nil end
  local text = UI.seconds:GetText()
  if text == nil or text == "" then return nil end
  return tonumber(text)
end

local function Can()
  return TGC.CanMutate() and true or false
end

function UI.RefreshButtons()
  if not UI.ready then return end
  local can = Can()
  local leader = TGC.IsRaidLeader and TGC.IsRaidLeader()
  local active = TGC.session and TGC.session.active
  local awarded = TGC.session and TGC.session.awarded
  local link = TGC.session and TGC.session.link
  local open = TGC.watch and TGC.watch.active
  local reason = UI.reason and UI.reason:GetText() or ""
  local manual = UI.manual and UI.manual:GetText() or ""
  local winner = TGC.Roll and TGC.Roll.ResolvedWinner and TGC.Roll.ResolvedWinner()
  Arm(UI.start, can and link and not active and not awarded)
  Arm(UI.closeBtn, leader and active)
  Arm(UI.ms, open, TGC.watch and TGC.watch.mine == "MS")
  Arm(UI.os, open, TGC.watch and TGC.watch.mine == "OS")
  Arm(UI.pass, open, TGC.watch and TGC.watch.mine == "PASS")
  if UI.ms then UI.ms.chosen = TGC.watch and TGC.watch.mine == "MS" end
  if UI.os then UI.os.chosen = TGC.watch and TGC.watch.mine == "OS" end
  if UI.pass then UI.pass.chosen = TGC.watch and TGC.watch.mine == "PASS" end
  Arm(UI.rollBtn, MineInTie())
  Arm(UI.confirm, can and not active and not awarded and winner ~= nil)
  Arm(UI.override, can and not active and not awarded and UI.rollPick and reason ~= "")
  Arm(UI.give, can and TGC.give and not TGC.give.given)
  Arm(UI.skip, can and link)
  local mark = leader and active and (manual ~= "" or UI.rollPick)
  Arm(UI.markMs, mark)
  Arm(UI.markOs, mark)
  Arm(UI.markPass, mark)
  Arm(UI.lockoutBtn, can)
  Arm(UI.attendBtn, can)
  Arm(UI.masterBtn, can)
  Arm(UI.specBtn, true)
  Arm(UI.guildBtn, can and UI.rosterPick)
  Arm(UI.guestBtn, can and UI.rosterPick)
  local voidReason = UI.voidReason and UI.voidReason:GetText() or ""
  Arm(UI.voidBtn, can and UI.historyPick and voidReason ~= "")
  Arm(UI.addNote, can)
  Arm(UI.removeNote, can and UI.notePick)
  Arm(UI.saveSettings, can)
  Arm(UI.showRecord, TGC.db ~= nil)
  Arm(UI.replace, can)
  if popup then
    Arm(UI.popupMs, open, TGC.watch and TGC.watch.mine == "MS")
    Arm(UI.popupOs, open, TGC.watch and TGC.watch.mine == "OS")
    Arm(UI.popupPass, open, TGC.watch and TGC.watch.mine == "PASS")
    Arm(UI.popupRoll, MineInTie())
    if UI.popupMs then UI.popupMs.chosen = TGC.watch and TGC.watch.mine == "MS" end
    if UI.popupOs then UI.popupOs.chosen = TGC.watch and TGC.watch.mine == "OS" end
    if UI.popupPass then UI.popupPass.chosen = TGC.watch and TGC.watch.mine == "PASS" end
  end
end

local function PaintRoll()
  local link = (TGC.session and TGC.session.link) or (TGC.watch and TGC.watch.link)
  if link then
    UI.itemIcon:SetTexture(ItemTexture(link))
    UI.itemText:SetText(link)
    UI.itemText:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    local id = TGC.ItemID(link)
    if id then UI.ItemLabel(id) end
  else
    UI.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    UI.itemText:SetText("Alt+click an item in loot, bags, or chat.")
    UI.itemText:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  end
  local tier = (TGC.session and TGC.session.tier) or (TGC.watch and TGC.watch.tier)
  UI.tier:SetChecked(tier and true or false)
  if UI.seconds:GetText() == "" and not UI.seconds:HasFocus() then
    local seconds = TGC.db and TGC.db.settings and TGC.db.settings.seconds or 30
    UI.seconds:SetText(tostring(seconds))
  end
  UI.banner:SetText(TGC.watch and TGC.watch.banner or FORMULA)
  local rows = RollSource()
  local offset = ClampScroll("roll", #rows)
  Fill(UI.rollRows, rows, offset, function(item)
    return UI.rollPick and item.key and UI.rollPick.key == item.key
  end, function(row, item)
    local r, g, b = ClassRGB(item.class)
    row.labels.name:SetText(item.name or "")
    row.labels.name:SetTextColor(r, g, b)
    local choice, color = ChoiceText(item.choice)
    row.labels.choice:SetText(choice)
    row.labels.choice:SetTextColor(color[1], color[2], color[3])
    row.labels.score:SetText(item.waiting and "-" or TGC.FormatScore(item.score))
    row.labels.now:SetText(item.waiting and "-" or tostring(item.current or 0))
    row.labels.rate:SetText(item.waiting and "-" or TGC.FormatScore(item.rate))
    row.labels.spec:SetText(item.spec or "")
    local status = item.waiting and "Waiting" or TGC.StatusName(item.status or item.statusLetter)
    row.labels.status:SetText(status)
    row.labels.status:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
    if item.roll then row.labels.choice:SetText(choice .. " " .. tostring(item.roll)) end
    if item.waiting then row.tip = "No response yet."
    else row.tip = TGC.Detail(item) end
  end)
  local lock = TGC.db and TGC.db.lockout
  if lock and lock.id ~= "" then
    local label = lock.label ~= "" and lock.label or lock.id
    UI.lockLabel:SetText(string.format("Lockout %s, week %d.", label, lock.week or 0))
  else
    UI.lockLabel:SetText("No lockout yet. Starting a roll will open one.")
  end
  local shown = 0
  if TGC.IsRaidLeader and TGC.IsRaidLeader() and TGC.Loot and TGC.Loot.open then
    for _, slot in ipairs(TGC.Loot.slots or {}) do
      local id = TGC.ItemID(slot.link)
      local remembered = id and TGC.db and TGC.db.tierItems[id]
      if (slot.quality or 0) >= 3 or remembered then
        shown = shown + 1
        local button = UI.lootButtons[shown]
        if not button then break end
        button.link = slot.link
        button.slot = slot.slot
        button.icon:SetTexture(ItemTexture(slot.link))
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[slot.quality or 0]
        if color then button:SetBackdropBorderColor(color.r, color.g, color.b, 1)
        else button:SetBackdropBorderColor(COLORS.edge[1], COLORS.edge[2], COLORS.edge[3], 1) end
        button:Show()
      end
    end
  end
  for index = shown + 1, #UI.lootButtons do UI.lootButtons[index]:Hide() end
end

local function PaintRoster()
  SetIdle(UI.spec, (function()
    local name = TGC.PlayerName and TGC.PlayerName()
    local key = name and TGC.Key(name)
    local saved = key and TGC.saved and TGC.saved.specs and TGC.saved.specs[key]
    local player = key and TGC.db and TGC.db.players[key]
    return saved or (player and player.spec) or ""
  end)())
  local rows = {}
  if TGC.db and TGC.RosterRows then rows = TGC.RosterRows() end
  local filter = UI.filter and UI.filter:GetText():lower() or ""
  if filter ~= "" then
    local kept = {}
    for _, row in ipairs(rows) do
      local name = (row.name or ""):lower()
      local spec = (row.spec or ""):lower()
      if name:find(filter, 1, true) or spec:find(filter, 1, true) then kept[#kept + 1] = row end
    end
    rows = kept
  end
  local offset = ClampScroll("roster", #rows)
  Fill(UI.rosterRows, rows, offset, function(item)
    return UI.rosterPick and item.key == UI.rosterPick.key
  end, function(row, item)
    local r, g, b = ClassRGB(item.class)
    row.labels.name:SetText(item.name or "")
    row.labels.name:SetTextColor(r, g, b)
    row.labels.spec:SetText(item.spec ~= "" and item.spec or "-")
    row.labels.status:SetText(TGC.StatusName(item.status))
    row.labels.weeks:SetText(tostring(item.weeks or 0))
    row.labels.tier:SetText(TGC.FormatScore(item.tierScore))
    row.labels.other:SetText(TGC.FormatScore(item.otherScore))
    row.tip = string.format("%s. Tier score %s (now %d, rate %s, %d wins). Non-tier score %s (now %d, rate %s, %d wins). %d weeks in the window.",
      TGC.StatusName(item.status), TGC.FormatScore(item.tierScore), item.tierCurrent or 0, TGC.FormatScore(item.tierRate), item.tierWins or 0,
      TGC.FormatScore(item.otherScore), item.otherCurrent or 0, TGC.FormatScore(item.otherRate), item.otherWins or 0, item.weeks or 0)
  end)
  if UI.rosterPick then
    local item = UI.rosterPick
    UI.detail:SetText(string.format("%s is %s. Tier %s, non-tier %s. %s.",
      item.name or "", TGC.StatusName(item.status), TGC.FormatScore(item.tierScore), TGC.FormatScore(item.otherScore),
      item.guild and "Guild" or "Guest"))
  else
    UI.detail:SetText("Select a raider to see both scores. Mark guild or guest if the roster did not.")
  end
end

local function PaintHistory()
  local rows = TGC.db and TGC.History and TGC.History() or {}
  local offset = ClampScroll("history", #rows)
  Fill(UI.historyRows, rows, offset, function(item)
    return UI.historyPick and item.key == UI.historyPick.key and item.n == UI.historyPick.n
  end, function(row, item)
    local r, g, b = ClassRGB(item.class)
    row.labels.week:SetText(tostring(item.week or ""))
    row.labels.name:SetText(item.name or "")
    row.labels.name:SetTextColor(r, g, b)
    row.labels.item:SetText(UI.ItemLabel(item.item, item.itemName))
    row.labels.spec:SetText(item.spec or "")
    row.labels.plus:SetText(item.plus and (item.tier and "Tier" or "+1") or "Free")
    row.labels.plus:SetTextColor(item.plus and COLORS.gold[1] or COLORS.dim[1], item.plus and COLORS.gold[2] or COLORS.dim[2], item.plus and COLORS.gold[3] or COLORS.dim[3])
    local reason = item.reason or ""
    row.tip = reason ~= "" and reason or "Awarded."
  end)
  local lines = {}
  local log = TGC.db and TGC.db.log or {}
  local startAt = #log - 3
  if startAt < 1 then startAt = 1 end
  for index = startAt, #log do
    if log[index] and log[index].text then lines[#lines + 1] = log[index].text end
  end
  UI.logText:SetText(#lines > 0 and table.concat(lines, "\n") or "Voids and officer notes show up here.")
end

local function PaintNotes()
  if TGC.db and TGC.db.settings then
    local settings = TGC.db.settings
    SetIdle(UI.setSeconds, settings.seconds or 30)
    SetIdle(UI.setDay, settings.resetDay or 2)
    SetIdle(UI.setHour, settings.resetHour or 15)
    SetIdle(UI.setOfficer, settings.officerMax or 1)
  end
  if UI.popupCheck and TGC.saved and TGC.saved.ui then
    UI.popupCheck:SetChecked(TGC.saved.ui.popup ~= false)
  end
  local rows = TGC.db and TGC.db.reservations or {}
  local offset = ClampScroll("notes", #rows)
  Fill(UI.noteRows, rows, offset, function(item)
    return UI.notePick and item.item == UI.notePick.item and TGC.Key(item.player) == TGC.Key(UI.notePick.player)
  end, function(row, item)
    row.labels.item:SetText(UI.ItemLabel(item.item, item.itemName))
    row.labels.player:SetText(item.player or "")
    row.labels.note:SetText(item.note or "")
    row.tip = (item.player or "") .. (item.note and item.note ~= "" and (" — " .. item.note) or "")
  end)
end

local function PaintTabs()
  for _, tab in ipairs(UI.tabs) do
    local on = UI.tab == tab.key
    tab.button.label:SetTextColor(on and COLORS.gold[1] or COLORS.dim[1], on and COLORS.gold[2] or COLORS.dim[2], on and COLORS.gold[3] or COLORS.dim[3])
    Paint(tab.button, on and COLORS.bar or COLORS.inset, on and COLORS.gold or COLORS.edge, 1)
  end
  for name, page in pairs(UI.pages) do
    if name == UI.tab then page:Show() else page:Hide() end
  end
end

function UI.Refresh()
  if not UI.ready or not main then return end
  local rev = TGC.db and TGC.db.rev or 0
  local pending = TGC.pendingSnapshot and " A newer record is waiting: /tgcloot pull." or ""
  UI.role:SetText(string.format("Revision %d. %s%s", rev, TGC.RoleText and TGC.RoleText() or "", pending))
  PaintTabs()
  if UI.tab == "roll" then PaintRoll()
  elseif UI.tab == "roster" then PaintRoster()
  elseif UI.tab == "history" then PaintHistory()
  elseif UI.tab == "notes" then PaintNotes() end
  UI.RefreshButtons()
  if popup and popup:IsShown() then UI.UpdatePopup() end
end

local function SelectTab(key)
  UI.tab = key
  UI.Refresh()
end

local function MarkChoice(choice)
  local name = UI.manual and UI.manual:GetText() or ""
  if name == "" and UI.rollPick then name = UI.rollPick.name or UI.rollPick.key or "" end
  if name == "" then
    TGC.Print("Select a raider, or type a full name.")
    return
  end
  TGC.Roll.SetChoice(name, choice)
end

local function BuildRoll(page)
  UI.itemIcon = page:CreateTexture(nil, "ARTWORK")
  UI.itemIcon:SetSize(32, 32)
  UI.itemIcon:SetPoint("TOPLEFT", 0, 0)
  UI.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.itemText = Label(page, 13)
  UI.itemText:SetPoint("LEFT", UI.itemIcon, "RIGHT", 8, 0)
  UI.itemText:SetWidth(230)
  UI.itemText:SetWordWrap(false)
  UI.tier = Check(page, "Tier", 58)
  UI.tier:SetPoint("TOPLEFT", 292, -8)
  UI.tier:SetScript("OnClick", function(self)
    if not Can() or (TGC.session and TGC.session.awarded) then
      self:SetChecked(TGC.session and TGC.session.tier)
      return
    end
    self:SetChecked(not self.checked)
    if TGC.Roll then TGC.Roll.SetTier(self.checked) end
  end)
  local sec = Label(page, 11)
  sec:SetPoint("TOPLEFT", 358, -8)
  sec:SetText("Sec")
  sec:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  UI.seconds = Edit(page, 36, 20)
  UI.seconds:SetPoint("TOPLEFT", 384, -6)
  UI.start = Button(page, "Start", 64)
  UI.start:SetPoint("TOPLEFT", 426, -6)
  UI.start:SetScript("OnClick", function() TGC.Roll.Start() end)
  UI.closeBtn = Button(page, "Close", 64)
  UI.closeBtn:SetPoint("TOPLEFT", 494, -6)
  UI.closeBtn:SetScript("OnClick", function() TGC.Roll.Close() end)
  UI.banner = Label(page, 12)
  UI.banner:SetPoint("TOPLEFT", 0, -38)
  UI.banner:SetPoint("TOPRIGHT", 0, -38)
  UI.banner:SetHeight(32)
  UI.banner:SetWordWrap(true)
  UI.banner:SetJustifyV("TOP")
  UI.rollRows = MakeList(page, 10, {
    { key = "name", title = "Name", width = 168 },
    { key = "choice", title = "Roll", width = 70 },
    { key = "score", title = "Score", width = 58 },
    { key = "now", title = "Now", width = 40 },
    { key = "rate", title = "Rate", width = 52 },
    { key = "spec", title = "Spec", width = 80 },
    { key = "status", title = "Status", width = 88 },
  }, -72, "roll", function(data) UI.rollPick = data UI.Refresh() end)
  UI.ms = Button(page, "MS", 52)
  UI.ms:SetPoint("TOPLEFT", 0, -276)
  UI.ms:SetScript("OnClick", function() TGC.Roll.Respond("MS") end)
  UI.os = Button(page, "OS", 52)
  UI.os:SetPoint("LEFT", UI.ms, "RIGHT", 4, 0)
  UI.os:SetScript("OnClick", function() TGC.Roll.Respond("OS") end)
  UI.pass = Button(page, "Pass", 56)
  UI.pass:SetPoint("LEFT", UI.os, "RIGHT", 4, 0)
  UI.pass:SetScript("OnClick", function() TGC.Roll.Respond("PASS") end)
  UI.rollBtn = Button(page, "Roll 100", 76)
  UI.rollBtn:SetPoint("LEFT", UI.pass, "RIGHT", 8, 0)
  UI.rollBtn:SetScript("OnClick", function() TGC.Roll.Roll() end)
  UI.markMs = Button(page, "Mark MS", 68)
  UI.markMs:SetPoint("TOPLEFT", 280, -276)
  UI.markMs:SetScript("OnClick", function() MarkChoice("MS") end)
  UI.markOs = Button(page, "Mark OS", 68)
  UI.markOs:SetPoint("LEFT", UI.markMs, "RIGHT", 4, 0)
  UI.markOs:SetScript("OnClick", function() MarkChoice("OS") end)
  UI.markPass = Button(page, "Mark Pass", 76)
  UI.markPass:SetPoint("LEFT", UI.markOs, "RIGHT", 4, 0)
  UI.markPass:SetScript("OnClick", function() MarkChoice("PASS") end)
  UI.manual = Edit(page, 160, 20)
  UI.manual:SetPoint("TOPLEFT", 0, -302)
  UI.manual:SetScript("OnTextChanged", function() UI.RefreshButtons() end)
  local manualLabel = Label(page, 11)
  manualLabel:SetPoint("LEFT", UI.manual, "RIGHT", 6, 0)
  manualLabel:SetText("Full name, if the click did not match one raider")
  manualLabel:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  UI.reason = Edit(page, 250, 20)
  UI.reason:SetPoint("TOPLEFT", 0, -328)
  UI.reason:SetScript("OnTextChanged", function() UI.RefreshButtons() end)
  UI.confirm = Button(page, "Confirm", 76)
  UI.confirm:SetPoint("LEFT", UI.reason, "RIGHT", 6, 0)
  UI.confirm:SetScript("OnClick", function() TGC.Roll.Award(nil, nil, false) end)
  UI.override = Button(page, "Override", 76)
  UI.override:SetPoint("LEFT", UI.confirm, "RIGHT", 4, 0)
  UI.override:SetScript("OnClick", function()
    local pick = UI.rollPick
    TGC.Roll.Award(pick and (pick.name or pick.key), UI.reason:GetText(), true)
  end)
  UI.give = Button(page, "Give", 56)
  UI.give:SetPoint("TOPLEFT", 416, -328)
  UI.give:SetScript("OnClick", function() if TGC.Loot then TGC.Loot.Give() end end)
  UI.skip = Button(page, "Skip", 56)
  UI.skip:SetPoint("LEFT", UI.give, "RIGHT", 4, 0)
  UI.skip:SetScript("OnClick", function() TGC.Roll.Skip(UI.reason:GetText()) end)
  UI.lockLabel = Label(page, 12)
  UI.lockLabel:SetPoint("TOPLEFT", 0, -354)
  UI.lockLabel:SetWidth(560)
  UI.lockoutBox = Edit(page, 120, 20)
  UI.lockoutBox:SetPoint("TOPLEFT", 0, -376)
  UI.lockoutBtn = Button(page, "Start lockout", 110)
  UI.lockoutBtn:SetPoint("LEFT", UI.lockoutBox, "RIGHT", 6, 0)
  UI.lockoutBtn:SetScript("OnClick", function() TGC.StartLockout(UI.lockoutBox:GetText()) end)
  UI.attendBtn = Button(page, "Attendance", 96)
  UI.attendBtn:SetPoint("LEFT", UI.lockoutBtn, "RIGHT", 4, 0)
  UI.attendBtn:SetScript("OnClick", function() TGC.RecordAttendance() end)
  UI.masterBtn = Button(page, "Master loot", 100)
  UI.masterBtn:SetPoint("LEFT", UI.attendBtn, "RIGHT", 4, 0)
  UI.masterBtn:SetScript("OnClick", function() if TGC.Loot then TGC.Loot.SetMasterLoot() end end)
  UI.lootButtons = {}
  for index = 1, 12 do
    local button = CreateFrame("Button", nil, page, "BackdropTemplate")
    button:SetSize(26, 26)
    button:SetPoint("TOPLEFT", (index - 1) * 28, -404)
    button:SetBackdrop(Backdrop())
    Paint(button, COLORS.inset, COLORS.edge, 1)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetScript("OnClick", function(self)
      if self.link and TGC.Roll then TGC.Roll.SetItem(self.link, self.slot) end
    end)
    button:SetScript("OnEnter", function(self)
      if self.link and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
      end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:Hide()
    UI.lootButtons[index] = button
  end
  local formula = Label(page, 11)
  formula:SetPoint("BOTTOMLEFT", 0, 0)
  formula:SetPoint("BOTTOMRIGHT", 0, 0)
  formula:SetHeight(28)
  formula:SetWordWrap(true)
  formula:SetText(FORMULA)
  formula:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
end

local function BuildRoster(page)
  UI.filter = Edit(page, 180, 20)
  UI.filter:SetPoint("TOPLEFT", 0, 0)
  UI.filter:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    if text == UI.filterText then return end
    UI.filterText = text
    UI.scroll.roster = 0
    UI.Refresh()
  end)
  local filterLabel = Label(page, 11)
  filterLabel:SetPoint("LEFT", UI.filter, "RIGHT", 6, 0)
  filterLabel:SetText("Filter")
  filterLabel:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  UI.spec = Edit(page, 140, 20)
  UI.spec:SetPoint("TOPLEFT", 280, 0)
  UI.specBtn = Button(page, "Save my spec", 100)
  UI.specBtn:SetPoint("LEFT", UI.spec, "RIGHT", 6, 0)
  UI.specBtn:SetScript("OnClick", function() TGC.DeclareSpec(UI.spec:GetText()) end)
  UI.rosterRows = MakeList(page, 12, {
    { key = "name", title = "Name", width = 160 },
    { key = "spec", title = "Spec", width = 100 },
    { key = "status", title = "Status", width = 110 },
    { key = "weeks", title = "Weeks", width = 50 },
    { key = "tier", title = "Tier", width = 70 },
    { key = "other", title = "Non-tier", width = 86 },
  }, -28, "roster", function(data) UI.rosterPick = data UI.Refresh() end)
  UI.detail = Label(page, 12)
  UI.detail:SetPoint("TOPLEFT", 0, -268)
  UI.detail:SetPoint("TOPRIGHT", 0, -268)
  UI.detail:SetHeight(36)
  UI.detail:SetWordWrap(true)
  UI.detail:SetJustifyV("TOP")
  UI.guildBtn = Button(page, "Mark guild", 100)
  UI.guildBtn:SetPoint("TOPLEFT", 0, -310)
  UI.guildBtn:SetScript("OnClick", function()
    if UI.rosterPick then TGC.SetGuildFlag(UI.rosterPick.name, true) end
  end)
  UI.guestBtn = Button(page, "Mark guest", 100)
  UI.guestBtn:SetPoint("LEFT", UI.guildBtn, "RIGHT", 6, 0)
  UI.guestBtn:SetScript("OnClick", function()
    if UI.rosterPick then TGC.SetGuildFlag(UI.rosterPick.name, false) end
  end)
end

local function BuildHistory(page)
  UI.historyRows = MakeList(page, 12, {
    { key = "week", title = "Week", width = 50 },
    { key = "name", title = "Name", width = 140 },
    { key = "item", title = "Item", width = 200 },
    { key = "spec", title = "Spec", width = 50 },
    { key = "plus", title = "Count", width = 56 },
  }, 0, "history", function(data) UI.historyPick = data UI.Refresh() end)
  UI.voidReason = Edit(page, 360, 20)
  UI.voidReason:SetPoint("TOPLEFT", 0, -248)
  UI.voidReason:SetScript("OnTextChanged", function() UI.RefreshButtons() end)
  UI.voidBtn = Button(page, "Void selected", 110)
  UI.voidBtn:SetPoint("LEFT", UI.voidReason, "RIGHT", 6, 0)
  UI.voidBtn:SetScript("OnClick", function()
    local pick = UI.historyPick
    if not pick then
      TGC.Print("Select an award first.")
      return
    end
    TGC.VoidWin(pick.name, pick.n, UI.voidReason:GetText())
  end)
  local hint = Label(page, 11)
  hint:SetPoint("TOPLEFT", 0, -276)
  hint:SetWidth(560)
  hint:SetWordWrap(true)
  hint:SetText("A void is an exceptional correction. It is recorded. Awards stay final in the normal buttons.")
  hint:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  UI.logText = Label(page, 12)
  UI.logText:SetPoint("TOPLEFT", 0, -310)
  UI.logText:SetPoint("TOPRIGHT", 0, -310)
  UI.logText:SetHeight(64)
  UI.logText:SetWordWrap(true)
  UI.logText:SetJustifyV("TOP")
end

local function BuildNotes(page)
  local hint = Label(page, 11)
  hint:SetPoint("TOPLEFT", 0, 0)
  hint:SetWidth(560)
  hint:SetText("Item link or id, player, then note. Reservations are announced when a lockout starts.")
  hint:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  UI.itemBox = Edit(page, 170, 20)
  UI.itemBox:SetPoint("TOPLEFT", 0, -18)
  UI.playerBox = Edit(page, 140, 20)
  UI.playerBox:SetPoint("LEFT", UI.itemBox, "RIGHT", 4, 0)
  UI.noteBox = Edit(page, 160, 20)
  UI.noteBox:SetPoint("LEFT", UI.playerBox, "RIGHT", 4, 0)
  UI.addNote = Button(page, "Reserve", 72)
  UI.addNote:SetPoint("LEFT", UI.noteBox, "RIGHT", 4, 0)
  UI.addNote:SetScript("OnClick", function()
    TGC.AddReservation(UI.itemBox:GetText(), UI.playerBox:GetText(), UI.noteBox:GetText())
  end)
  UI.noteRows = MakeList(page, 5, {
    { key = "item", title = "Item", width = 230 },
    { key = "player", title = "Player", width = 160 },
    { key = "note", title = "Note", width = 186 },
  }, -46, "notes", function(data) UI.notePick = data UI.Refresh() end)
  UI.removeNote = Button(page, "Remove", 80)
  UI.removeNote:SetPoint("TOPLEFT", 0, -160)
  UI.removeNote:SetScript("OnClick", function()
    if UI.notePick then TGC.RemoveReservation(UI.notePick.item, UI.notePick.player) end
  end)
  local settings = Label(page, 11)
  settings:SetPoint("TOPLEFT", 0, -190)
  settings:SetWidth(560)
  settings:SetHeight(32)
  settings:SetWordWrap(true)
  settings:SetJustifyV("TOP")
  settings:SetText("Day 1 is Monday and 7 is Sunday. Hour is UTC. Officer max is the highest guild rank index that can change loot, besides the guild master. Rank 2 officers need this raised, or the raid leader is rejected.")
  settings:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  local labels = { "Seconds", "Day", "Hour", "Officer max" }
  for index, title in ipairs(labels) do
    local text = Label(page, 11)
    text:SetPoint("TOPLEFT", (index - 1) * 90, -226)
    text:SetText(title)
    text:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  end
  UI.setSeconds = Edit(page, 70, 20)
  UI.setSeconds:SetPoint("TOPLEFT", 0, -242)
  UI.setDay = Edit(page, 70, 20)
  UI.setDay:SetPoint("LEFT", UI.setSeconds, "RIGHT", 20, 0)
  UI.setHour = Edit(page, 70, 20)
  UI.setHour:SetPoint("LEFT", UI.setDay, "RIGHT", 20, 0)
  UI.setOfficer = Edit(page, 70, 20)
  UI.setOfficer:SetPoint("LEFT", UI.setHour, "RIGHT", 20, 0)
  UI.saveSettings = Button(page, "Save settings", 110)
  UI.saveSettings:SetPoint("TOPLEFT", 0, -268)
  UI.saveSettings:SetScript("OnClick", function()
    TGC.SaveSettings(UI.setSeconds:GetText(), UI.setDay:GetText(), UI.setHour:GetText(), UI.setOfficer:GetText())
  end)
  UI.popupCheck = Check(page, "Roll popup", 110)
  UI.popupCheck:SetPoint("LEFT", UI.saveSettings, "RIGHT", 12, 0)
  UI.popupCheck:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if TGC.saved and TGC.saved.ui then TGC.saved.ui.popup = self.checked end
  end)
  local record = Label(page, 11)
  record:SetPoint("TOPLEFT", 0, -296)
  record:SetText("Loot record. Show it, copy it, or replace this guild's copy.")
  record:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  UI.export = Edit(page, 560, 96, true)
  UI.export:SetPoint("TOPLEFT", 0, -314)
  UI.showRecord = Button(page, "Show record", 110)
  UI.showRecord:SetPoint("TOPLEFT", 0, -416)
  UI.showRecord:SetScript("OnClick", function()
    if TGC.db then
      UI.export:SetText(TGC.Encode(TGC.db, false))
      UI.export:SetCursorPosition(0)
    end
  end)
  UI.replace = Button(page, "Replace record", 120)
  UI.replace:SetPoint("LEFT", UI.showRecord, "RIGHT", 6, 0)
  UI.replace:SetScript("OnClick", function()
    local decoded = TGC.Decode(UI.export:GetText() or "")
    if not decoded then
      TGC.Print("That text is not a TGC Loot record.")
      return
    end
    TGC.ReplaceDB(decoded)
  end)
end

local function BuildMain()
  main = CreateFrame("Frame", "TGCLootFrame", UIParent, "BackdropTemplate")
  main:SetSize(600, 572)
  main:SetFrameStrata("DIALOG")
  main:SetMovable(true)
  main:SetClampedToScreen(true)
  main:SetBackdrop(Backdrop())
  Paint(main, COLORS.bg, COLORS.edge, 0.98)
  RestorePoint(main, "main", 0, 40)
  Special("TGCLootFrame")
  local drag = CreateFrame("Frame", nil, main)
  drag:SetPoint("TOPLEFT", 0, 0)
  drag:SetPoint("TOPRIGHT", -28, 0)
  drag:SetHeight(26)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() main:StartMoving() end)
  drag:SetScript("OnDragStop", function()
    main:StopMovingOrSizing()
    SavePoint(main, "main")
  end)
  local title = Label(main, 15)
  title:SetPoint("TOPLEFT", 12, -6)
  title:SetText("TGC Loot")
  title:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
  local version = Label(main, 11)
  version:SetPoint("LEFT", title, "RIGHT", 8, 0)
  version:SetText(TGC.VERSION or "")
  version:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
  local close = Button(main, "X", 20, 18)
  close:SetPoint("TOPRIGHT", -6, -4)
  close:SetScript("OnClick", function() main:Hide() end)
  UI.role = Label(main, 12)
  UI.role:SetPoint("TOPLEFT", 12, -28)
  UI.role:SetPoint("TOPRIGHT", -12, -28)
  UI.role:SetHeight(28)
  UI.role:SetWordWrap(true)
  UI.role:SetJustifyV("TOP")
  UI.tabs = {}
  UI.pages = {}
  local keys = {
    { key = "roll", label = "Roll" },
    { key = "roster", label = "Roster" },
    { key = "history", label = "History" },
    { key = "notes", label = "Notes" },
  }
  for index, info in ipairs(keys) do
    local button = Button(main, info.label, 88, 22)
    button:SetPoint("TOPLEFT", 12 + (index - 1) * 94, -58)
    button:SetScript("OnClick", function() SelectTab(info.key) end)
    UI.tabs[index] = { key = info.key, button = button }
    local page = CreateFrame("Frame", nil, main)
    page:SetPoint("TOPLEFT", 12, -86)
    page:SetPoint("BOTTOMRIGHT", -12, 10)
    page:Hide()
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta) UI.Wheel(info.key, delta) end)
    UI.pages[info.key] = page
  end
  BuildRoll(UI.pages.roll)
  BuildRoster(UI.pages.roster)
  BuildHistory(UI.pages.history)
  BuildNotes(UI.pages.notes)
  UI.tab = "roll"
  main:Hide()
end

local function PlaceMinimap()
  if not UI.minimap or not Minimap then return end
  local angle = 220
  if TGC.saved and TGC.saved.ui and TGC.saved.ui.minimap then angle = TGC.saved.ui.minimap end
  local rad = math.rad(angle)
  local radius = (Minimap:GetWidth() / 2) + 8
  UI.minimap:ClearAllPoints()
  UI.minimap:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function BuildMinimap()
  if not Minimap then return end
  local button = CreateFrame("Button", "TGCLootMinimapButton", Minimap)
  button:SetSize(28, 28)
  button:SetFrameStrata("MEDIUM")
  button:SetMovable(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(52, 52)
  border:SetPoint("TOPLEFT", -1, 1)
  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button:SetScript("OnClick", function(self, which)
    if self.dragged then
      self.dragged = false
      return
    end
    if which == "RightButton" then
      if TGC.saved and TGC.saved.ui then
        TGC.saved.ui.popup = not TGC.saved.ui.popup
        TGC.Print(TGC.saved.ui.popup and "Roll popups on." or "Roll popups off.")
      end
      return
    end
    UI.Toggle()
  end)
  button:SetScript("OnDragStart", function(self)
    self.dragged = true
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      if TGC.saved and TGC.saved.ui then
        TGC.saved.ui.minimap = math.deg(math.atan2(cy - my, cx - mx))
      end
      PlaceMinimap()
    end)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("TGC Loot", COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
      GameTooltip:AddLine("Left-click opens the window. Right-click toggles the roll popup. Drag to move.", COLORS.dim[1], COLORS.dim[2], COLORS.dim[3], true)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  UI.minimap = button
  PlaceMinimap()
end

local function ReservedLines(id)
  if not id or not TGC.db then return nil end
  local lines = {}
  for _, reservation in ipairs(TGC.db.reservations or {}) do
    if reservation.item == id then
      local note = reservation.note and reservation.note ~= "" and (" — " .. reservation.note) or ""
      lines[#lines + 1] = "Reserved: " .. (reservation.player or "") .. note
    end
  end
  if #lines == 0 then return nil end
  return lines
end

local function AddReservationLines(tip, id)
  local lines = ReservedLines(id)
  if not lines or not tip then return end
  for _, line in ipairs(lines) do
    tip:AddLine(line, COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], true)
  end
end

local function HookTooltip()
  if UI.tooltipHooked then return end
  UI.tooltipHooked = true
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      if data and data.id then AddReservationLines(tip, data.id) end
    end)
    return
  end
  if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tip)
      local _, link = tip:GetItem()
      AddReservationLines(tip, TGC.ItemID(link))
    end)
  end
end

local function HookClicks()
  if UI.clicksHooked or not hooksecurefunc or not HandleModifiedItemClick then return end
  UI.clicksHooked = true
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if GetMouseButtonClicked and GetMouseButtonClicked() ~= "LeftButton" then return end
    if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return end
    if TGC.Roll and TGC.Roll.SetItem then TGC.Roll.SetItem(link) end
  end)
end

local function BuildPopup()
  popup = CreateFrame("Frame", "TGCLootPopup", UIParent, "BackdropTemplate")
  popup:SetSize(460, 340)
  popup:SetFrameStrata("DIALOG")
  popup:SetFrameLevel((main and main:GetFrameLevel() or 0) + 20)
  popup:SetMovable(true)
  popup:SetClampedToScreen(true)
  popup:SetBackdrop(Backdrop())
  Paint(popup, COLORS.bg, COLORS.edge, 0.98)
  RestorePoint(popup, "popup", 220, 20)
  Special("TGCLootPopup")
  local drag = CreateFrame("Frame", nil, popup)
  drag:SetPoint("TOPLEFT")
  drag:SetPoint("TOPRIGHT", -24, 0)
  drag:SetHeight(24)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() popup:StartMoving() end)
  drag:SetScript("OnDragStop", function()
    popup:StopMovingOrSizing()
    SavePoint(popup, "popup")
  end)
  local title = Label(popup, 13)
  title:SetPoint("TOPLEFT", 10, -5)
  title:SetText("TGC Loot")
  title:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
  local close = Button(popup, "X", 18, 16)
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() popup:Hide() end)
  UI.popupIcon = popup:CreateTexture(nil, "ARTWORK")
  UI.popupIcon:SetSize(28, 28)
  UI.popupIcon:SetPoint("TOPLEFT", 10, -28)
  UI.popupIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  UI.popupItem = Label(popup, 13)
  UI.popupItem:SetPoint("LEFT", UI.popupIcon, "RIGHT", 8, 0)
  UI.popupItem:SetWidth(390)
  UI.popupItem:SetWordWrap(false)
  local barBack = popup:CreateTexture(nil, "ARTWORK")
  barBack:SetPoint("TOPLEFT", 10, -62)
  barBack:SetSize(440, 8)
  barBack:SetColorTexture(COLORS.inset[1], COLORS.inset[2], COLORS.inset[3], 1)
  UI.popupBar = popup:CreateTexture(nil, "OVERLAY")
  UI.popupBar:SetPoint("LEFT", barBack, "LEFT", 0, 0)
  UI.popupBar:SetHeight(8)
  UI.popupBar:SetWidth(1)
  UI.popupBar:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  UI.popupTime = Label(popup, 11)
  UI.popupTime:SetPoint("TOPRIGHT", -12, -46)
  UI.popupBanner = Label(popup, 12)
  UI.popupBanner:SetPoint("TOPLEFT", 10, -76)
  UI.popupBanner:SetWidth(440)
  UI.popupBanner:SetHeight(32)
  UI.popupBanner:SetWordWrap(true)
  UI.popupBanner:SetJustifyV("TOP")
  UI.popupRows = MakeList(popup, 8, {
    { key = "name", title = "Name", width = 180 },
    { key = "choice", title = "Roll", width = 70 },
    { key = "score", title = "Score", width = 70 },
    { key = "now", title = "Now", width = 50 },
    { key = "status", title = "Status", width = 80 },
  }, -110, "popup", nil)
  UI.popupMs = Button(popup, "MS", 64)
  UI.popupMs:SetPoint("BOTTOMLEFT", 10, 12)
  UI.popupMs:SetScript("OnClick", function() TGC.Roll.Respond("MS") end)
  UI.popupOs = Button(popup, "OS", 64)
  UI.popupOs:SetPoint("LEFT", UI.popupMs, "RIGHT", 4, 0)
  UI.popupOs:SetScript("OnClick", function() TGC.Roll.Respond("OS") end)
  UI.popupPass = Button(popup, "Pass", 64)
  UI.popupPass:SetPoint("LEFT", UI.popupOs, "RIGHT", 4, 0)
  UI.popupPass:SetScript("OnClick", function() TGC.Roll.Respond("PASS") end)
  UI.popupRoll = Button(popup, "Roll 100", 80)
  UI.popupRoll:SetPoint("LEFT", UI.popupPass, "RIGHT", 8, 0)
  UI.popupRoll:SetScript("OnClick", function() TGC.Roll.Roll() end)
  popup:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.1 then return end
    self.acc = 0
    UI.UpdatePopup(true)
  end)
  popup:Hide()
end

function UI.UpdatePopup(timerOnly)
  if not popup then return end
  local link = TGC.watch and TGC.watch.link
  if not timerOnly then
    if link then
      UI.popupIcon:SetTexture(ItemTexture(link))
      UI.popupItem:SetText(link)
    else
      UI.popupIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      UI.popupItem:SetText("Roll")
    end
    UI.popupBanner:SetText(TGC.watch and TGC.watch.banner or "")
    local rows = TGC.watch and TGC.watch.rows or {}
    local offset = ClampScroll("popup", #rows)
    Fill(UI.popupRows, rows, offset, nil, function(row, item)
      local r, g, b = ClassRGB(item.class)
      row.labels.name:SetText(item.name or "")
      row.labels.name:SetTextColor(r, g, b)
      local choice, color = ChoiceText(item.choice)
      if item.roll then choice = choice .. " " .. tostring(item.roll) end
      row.labels.choice:SetText(choice)
      row.labels.choice:SetTextColor(color[1], color[2], color[3])
      row.labels.score:SetText(TGC.FormatScore(item.score))
      row.labels.now:SetText(tostring(item.current or 0))
      row.labels.status:SetText(TGC.StatusName(item.status or item.statusLetter))
      row.tip = TGC.Detail(item)
    end)
    UI.RefreshButtons()
  end
  local duration = TGC.watch and TGC.watch.duration or 0
  local remain, fraction = 0, 0
  if TGC.watch and TGC.watch.active and TGC.watch.endsAt and GetTime then
    remain = TGC.watch.endsAt - GetTime()
    if remain < 0 then remain = 0 end
    if duration > 0 then fraction = remain / duration end
    if fraction > 1 then fraction = 1 end
  end
  UI.popupBar:SetWidth(math.max(1, 440 * fraction))
  if TGC.watch and TGC.watch.active then UI.popupTime:SetText(string.format("%ds", math.ceil(remain)))
  elseif TGC.watch and TGC.watch.closed then UI.popupTime:SetText("Closed")
  else UI.popupTime:SetText("") end
end

function UI.ShowPopup()
  UI.Init()
  if not UI.ready then return end
  if not popup then BuildPopup() end
  popup:Show()
  UI.UpdatePopup()
end

function UI.Init()
  if UI.ready or not CreateFrame or not UIParent then return end
  UI.font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  UI.scroll = { roll = 0, roster = 0, history = 0, notes = 0, popup = 0 }
  UI.visible = { roll = 10, roster = 12, history = 12, notes = 5, popup = 8 }
  UI.counts = {}
  UI.names = {}
  UI.tab = "roll"
  BuildMain()
  BuildMinimap()
  HookTooltip()
  HookClicks()
  UI.ready = true
end

function UI.Show()
  UI.Init()
  if not main then return end
  main:Show()
  UI.Refresh()
end

function UI.Hide()
  if main then main:Hide() end
end

function UI.Toggle()
  UI.Init()
  if main and main:IsShown() then main:Hide() else UI.Show() end
end
