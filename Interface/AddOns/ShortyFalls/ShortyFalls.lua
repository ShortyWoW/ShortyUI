local ADDON_NAME = ...
local SF = {}
_G.ShortyFalls = SF

print("|cff66ccffShortyFalls|r loaded. Raid sync media-symbol build.")

-- -------------------------------------------------------
-- UI state
-- -------------------------------------------------------
local frame
local cells = {}
local callStep = 0
local listenerStep = 0
local checkActive = false
local checkResponders = {}

-- -------------------------------------------------------
-- Config
-- -------------------------------------------------------
local ADDON_VERSION = ((C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "dev")
local ADDON_PREFIX = "SFALLS"

local TARGET_INSTANCE_MAP_ID = 2913

local CELL_SIZE = 44
local CELL_GAP  = 6
local PAD_X     = 12
local PAD_Y     = 12

local ICON_ORDER = { 5, 3, 7, 4, nil }

local SYMBOL_NAMES = {
  [1] = "Circle",
  [2] = "Diamond",
  [3] = "Cross",
  [4] = "Triangle",
  [5] = "T",
}

local TEX_PATH = "Interface\\AddOns\\ShortyFalls\\media\\"

local TEXTURE_MAP = {
  [1] = TEX_PATH .. "sym_circle.tga",
  [2] = TEX_PATH .. "sym_diamond.tga",
  [3] = TEX_PATH .. "sym_cross.tga",
  [4] = TEX_PATH .. "sym_triangle.tga",
  [5] = TEX_PATH .. "sym_t.tga",
}

-- -------------------------------------------------------
-- Raid visibility gate
-- -------------------------------------------------------
local function IsDebugForced()
  return ShortyFallsDB and ShortyFallsDB.debugMode == true
end

local function ShouldBeActive()
  if IsDebugForced() then
    return true
  end

  local _, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
  return instanceType == "raid" and mapID == TARGET_INSTANCE_MAP_ID
end

local function IsMythicRaid()
  local _, instanceType, difficultyID = GetInstanceInfo()
  return instanceType == "raid" and difficultyID == 16
end

local function UpdateVisibility()
  if not frame then return end

  if ShouldBeActive() then
    frame:Show()
  else
    frame:Hide()
  end
end

-- -------------------------------------------------------
-- SavedVariables
-- -------------------------------------------------------
local function DB()
  if not ShortyFallsDB then ShortyFallsDB = {} end
  if ShortyFallsDB.locked == nil then ShortyFallsDB.locked = true end
  if ShortyFallsDB.debugMode == nil then ShortyFallsDB.debugMode = false end
  -- Legacy tables retained for compatibility with older saved variables.
  if not ShortyFallsDB.assign then ShortyFallsDB.assign = {} end
  if not ShortyFallsDB.used then ShortyFallsDB.used = {} end

  -- Mythic-compatible caller sequence.
  -- sequence[1..5] = symbolIndex. Duplicates are allowed.
  if not ShortyFallsDB.sequence then ShortyFallsDB.sequence = {} end
  return ShortyFallsDB
end

-- -------------------------------------------------------
-- Group / authority helpers
-- -------------------------------------------------------
local function NormalizeName(name)
  if not name or name == "" then return nil end
  name = name:gsub("%s+", "")
  if not name:find("%-") then
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and realm ~= "" then
      name = name .. "-" .. realm
    end
  end
  return name
end

local function UnitFullName(unit)
  local name = GetUnitName and GetUnitName(unit, true)
  return NormalizeName(name)
end

local function IsUnitLeadOrAssist(unit)
  return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
end

local function IsPlayerLeadOrAssist()
  if not IsInGroup() then return true end
  if IsInRaid() then
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
  end
  return UnitIsGroupLeader("player")
end

local function IsTrustedSender(sender)
  local normalizedSender = NormalizeName(sender)
  if not normalizedSender then return false end

  if UnitFullName("player") == normalizedSender then
    return IsPlayerLeadOrAssist()
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) and UnitFullName(unit) == normalizedSender then
        return IsUnitLeadOrAssist(unit)
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) and UnitFullName(unit) == normalizedSender then
        return UnitIsGroupLeader(unit)
      end
    end
  else
    return true
  end

  return false
end

local function GetGroupChannel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

local function ForEachGroupMember(callback)
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) then callback(unit) end
    end
  elseif IsInGroup() then
    callback("player")
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) then callback(unit) end
    end
  else
    callback("player")
  end
end

-- -------------------------------------------------------
-- Raid icons fallback
-- -------------------------------------------------------
local RAID_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RAID_TEXCOORDS = {
  [1] = {0.00, 0.25, 0.00, 0.25},
  [2] = {0.25, 0.50, 0.00, 0.25},
  [3] = {0.50, 0.75, 0.00, 0.25},
  [4] = {0.75, 1.00, 0.00, 0.25},
  [5] = {0.00, 0.25, 0.25, 0.50},
  [6] = {0.25, 0.50, 0.25, 0.50},
  [7] = {0.50, 0.75, 0.25, 0.50},
  [8] = {0.75, 1.00, 0.25, 0.50},
}

local function ApplyRaidIcon(tex, iconIndex)
  local tc = RAID_TEXCOORDS[iconIndex]
  tex:SetTexture(RAID_TEX)
  tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
end

local function GetCellPosition(index)
  local x = PAD_X + (index - 1) * (CELL_SIZE + CELL_GAP)
  local y = -PAD_Y - 22
  return x, y
end

local function PlaceCell(cell, positionIndex)
  local x, y = GetCellPosition(positionIndex)
  cell:ClearAllPoints()
  cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
end

local function RestoreOriginalCellOrder()
  for i = 1, #cells do
    PlaceCell(cells[i], i)
  end
end

local function ReorderByAssignedNumber()
  local db = DB()
  local ordered = {}

  for i = 1, #cells do
    local assignedNumber = db.assign[i]
    if assignedNumber then
      ordered[assignedNumber] = cells[i]
    end
  end

  for n = 1, 5 do
    if ordered[n] then
      PlaceCell(ordered[n], n)
    end
  end
end

local function SavePosition()
  local db = DB()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePosition()
  local db = DB()
  frame:ClearAllPoints()

  if db.pos then
    frame:SetPoint(db.pos.point, UIParent, db.pos.relPoint, db.pos.x, db.pos.y)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
end

local function ApplyLockState()
  local db = DB()

  if db.locked then
    frame:RegisterForDrag()
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
  else
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
      self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      SavePosition()
    end)
  end
end

-- -------------------------------------------------------
-- Macro keybind lookup
-- -------------------------------------------------------
local SYMBOL_MACRO_NAMES = {
  [1] = "sfalls:circle",
  [2] = "sfalls:diamond",
  [3] = "sfalls:cross",
  [4] = "sfalls:triangle",
  [5] = "sfalls:t",
}

local CHAT_SYMBOL_MAP = {
  ["sfalls:circle"] = 1,
  ["sfalls:diamond"] = 2,
  ["sfalls:cross"] = 3,
  ["sfalls:triangle"] = 4,
  ["sfalls:t"] = 5,
}

local SHORTYFALLS_MACROS = {
  { name = "sfalls:circle",   body = "/raid sfalls:circle" },
  { name = "sfalls:diamond",  body = "/raid sfalls:diamond" },
  { name = "sfalls:cross",    body = "/raid sfalls:cross" },
  { name = "sfalls:triangle", body = "/raid sfalls:triangle" },
  { name = "sfalls:t",        body = "/raid sfalls:t" },
  { name = "sfalls:clear",    body = "/raid sfalls:clear" },
}

local function CreateShortyFallsMacros()
  if InCombatLockdown and InCombatLockdown() then
    print("|cff66ccffShortyFalls|r Cannot create macros while in combat. Try again after combat.")
    return
  end

  if not GetMacroIndexByName or not CreateMacro then
    print("|cff66ccffShortyFalls|r Macro API not available right now.")
    return
  end

  local created = 0
  local skipped = 0
  local failed = 0
  local icon = "INV_Misc_QuestionMark"

  print("|cff66ccffShortyFalls|r Checking ShortyFalls macros...")

  for _, macroInfo in ipairs(SHORTYFALLS_MACROS) do
    local existingIndex = GetMacroIndexByName(macroInfo.name)

    if existingIndex and existingIndex ~= 0 then
      skipped = skipped + 1
      print("|cff66ccffShortyFalls|r Skipped existing macro: |cffffff00" .. macroInfo.name .. "|r")
    else
      local ok, result = pcall(CreateMacro, macroInfo.name, icon, macroInfo.body, false)

      if ok and result then
        created = created + 1
        print("|cff66ccffShortyFalls|r Created macro: |cff00ff00" .. macroInfo.name .. "|r")
      else
        failed = failed + 1
        print("|cff66ccffShortyFalls|r Failed to create macro: |cffff3333" .. macroInfo.name .. "|r")
      end
    end
  end

  print("|cff66ccffShortyFalls|r Macro setup done. Created: " .. created .. "  Skipped: " .. skipped .. "  Failed: " .. failed)
  print("|cff66ccffShortyFalls|r Open your Macro panel and drag the sfalls macros to keybinds/action bars.")
end

local ACTION_BINDINGS = {
  [1]="ACTIONBUTTON1", [2]="ACTIONBUTTON2", [3]="ACTIONBUTTON3", [4]="ACTIONBUTTON4", [5]="ACTIONBUTTON5", [6]="ACTIONBUTTON6", [7]="ACTIONBUTTON7", [8]="ACTIONBUTTON8", [9]="ACTIONBUTTON9", [10]="ACTIONBUTTON10", [11]="ACTIONBUTTON11", [12]="ACTIONBUTTON12",
  [61]="MULTIACTIONBAR1BUTTON1", [62]="MULTIACTIONBAR1BUTTON2", [63]="MULTIACTIONBAR1BUTTON3", [64]="MULTIACTIONBAR1BUTTON4", [65]="MULTIACTIONBAR1BUTTON5", [66]="MULTIACTIONBAR1BUTTON6", [67]="MULTIACTIONBAR1BUTTON7", [68]="MULTIACTIONBAR1BUTTON8", [69]="MULTIACTIONBAR1BUTTON9", [70]="MULTIACTIONBAR1BUTTON10", [71]="MULTIACTIONBAR1BUTTON11", [72]="MULTIACTIONBAR1BUTTON12",
  [49]="MULTIACTIONBAR2BUTTON1", [50]="MULTIACTIONBAR2BUTTON2", [51]="MULTIACTIONBAR2BUTTON3", [52]="MULTIACTIONBAR2BUTTON4", [53]="MULTIACTIONBAR2BUTTON5", [54]="MULTIACTIONBAR2BUTTON6", [55]="MULTIACTIONBAR2BUTTON7", [56]="MULTIACTIONBAR2BUTTON8", [57]="MULTIACTIONBAR2BUTTON9", [58]="MULTIACTIONBAR2BUTTON10", [59]="MULTIACTIONBAR2BUTTON11", [60]="MULTIACTIONBAR2BUTTON12",
  [25]="MULTIACTIONBAR3BUTTON1", [26]="MULTIACTIONBAR3BUTTON2", [27]="MULTIACTIONBAR3BUTTON3", [28]="MULTIACTIONBAR3BUTTON4", [29]="MULTIACTIONBAR3BUTTON5", [30]="MULTIACTIONBAR3BUTTON6", [31]="MULTIACTIONBAR3BUTTON7", [32]="MULTIACTIONBAR3BUTTON8", [33]="MULTIACTIONBAR3BUTTON9", [34]="MULTIACTIONBAR3BUTTON10", [35]="MULTIACTIONBAR3BUTTON11", [36]="MULTIACTIONBAR3BUTTON12",
  [37]="MULTIACTIONBAR4BUTTON1", [38]="MULTIACTIONBAR4BUTTON2", [39]="MULTIACTIONBAR4BUTTON3", [40]="MULTIACTIONBAR4BUTTON4", [41]="MULTIACTIONBAR4BUTTON5", [42]="MULTIACTIONBAR4BUTTON6", [43]="MULTIACTIONBAR4BUTTON7", [44]="MULTIACTIONBAR4BUTTON8", [45]="MULTIACTIONBAR4BUTTON9", [46]="MULTIACTIONBAR4BUTTON10", [47]="MULTIACTIONBAR4BUTTON11", [48]="MULTIACTIONBAR4BUTTON12",
}

local function CleanKeybindText(key)
  if not key then return nil end
  key = key:gsub("CTRL%-", "C-"):gsub("SHIFT%-", "S-"):gsub("ALT%-", "A-")
  key = key:gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD")
  key = key:gsub("BUTTON", "B"):gsub("NUMPAD", "N"):gsub("SPACE", "Spc")
  return key
end

local function GetMacroKeybind(macroName)
  if not macroName or not GetMacroIndexByName then return nil end
  local macroIndex = GetMacroIndexByName(macroName)
  if not macroIndex or macroIndex == 0 then return nil end

  for slot = 1, 120 do
    local actionType, id = GetActionInfo(slot)
    if actionType == "macro" and id == macroIndex then
      local binding = ACTION_BINDINGS[slot]
      if binding then
        local key1, key2 = GetBindingKey(binding)
        return CleanKeybindText(key1 or key2)
      end
    end
  end

  return nil
end

local function SetCompleteVisual(complete)
  if not frame then return end
  if complete then
    frame:SetBackdropBorderColor(0.2, 1, 0.35, 0.95)
    frame:SetBackdropColor(0, 0.18, 0.06, 0.42)
  else
    frame:SetBackdropBorderColor(1, 1, 1, 0.25)
    frame:SetBackdropColor(0, 0, 0, 0.35)
  end
end

local function SetCellGlow(cell, active, wrong)
  if not cell then return end

  if wrong then
    cell:SetBackdropBorderColor(1, 0.15, 0.15, 1)
    cell.bg:SetColorTexture(1, 0, 0, 0.22)
  elseif active then
    cell:SetBackdropBorderColor(1, 0.85, 0.1, 1)
    cell.bg:SetColorTexture(1, 0.85, 0.1, 0.24)
  else
    cell:SetBackdropBorderColor(1, 1, 1, 0.25)
    cell.bg:SetColorTexture(1, 1, 1, 0.10)
  end
end

local function ClearStepGlow()
  for i = 1, #cells do
    SetCellGlow(cells[i], false, false)
  end
end

local function HideAssignmentIcon(cell)
  if cell and cell.icon then cell.icon:SetAlpha(0) end
end

local function ShowAssignmentIcon(cell)
  if cell and cell.icon then cell.icon:SetAlpha(1) end
  if cell and cell.listenTex then cell.listenTex:Hide() end
end

local function ClearListenerSlot(cell)
  if not cell then return end
  HideAssignmentIcon(cell)
  if cell.listenTex then cell.listenTex:Hide() end
  if cell.num then cell.num:SetText("") end
  if cell.key then cell.key:SetText("") end
  SetCellGlow(cell, false, false)
end

local function SetListenerSlotSymbol(cell, symbolIndex)
  if not cell then return end
  HideAssignmentIcon(cell)
  if cell.num then cell.num:SetText("") end
  if cell.key then cell.key:SetText("") end

  -- Listener side should always use the media textures, including T.
  -- The old listener path used font text for T, which looked different from the caller UI.

  if cell.listenTex then
    local ok = cell.listenTex:SetTexture(TEXTURE_MAP[symbolIndex])
    if ok then
      cell.listenTex:SetTexCoord(0, 1, 0, 1)
    else
      local fallback = ({ [1] = 5, [2] = 3, [3] = 7, [4] = 4 })[symbolIndex]
      if fallback then ApplyRaidIcon(cell.listenTex, fallback) end
    end
    cell.listenTex:Show()
  end
end
local function UseAssignmentVisuals()
  for i = 1, #cells do
    ShowAssignmentIcon(cells[i])
  end
end

local function UseListenerBlankVisuals()
  listenerStep = 0
  RestoreOriginalCellOrder()
  for i = 1, #cells do
    ClearListenerSlot(cells[i])
  end
  SetCompleteVisual(false)
end

local function ShouldUseAssignmentMode()
  return IsDebugForced() or IsPlayerLeadOrAssist()
end

local function ApplyIdleVisualMode()
  if ShouldUseAssignmentMode() then
    RestoreOriginalCellOrder()
    UseAssignmentVisuals()
  else
    UseListenerBlankVisuals()
  end
end

local function AddListenerSymbol(symbolIndex)
  if not frame or not symbolIndex then return end

  listenerStep = listenerStep + 1
  if listenerStep > 5 then listenerStep = 5 end

  local slot = cells[listenerStep]

  SetListenerSlotSymbol(slot, symbolIndex)

  if slot.num then
    slot.num:SetText(tostring(listenerStep))
  end

  SetCellGlow(slot, true, false)

  if listenerStep > 1 then
    SetCellGlow(cells[listenerStep - 1], false, false)
  end

  if listenerStep == 5 then
    SetCompleteVisual(true)
  else
    SetCompleteVisual(false)
  end
end

local function GetSequenceCount()
  local db = DB()
  local count = 0
  for step = 1, 5 do
    if db.sequence[step] then
      count = step
    end
  end
  return count
end

local function IsSequenceComplete()
  return GetSequenceCount() == 5
end

local function ClearCellOverlayVisuals(cell)
  if not cell then return end
  if cell.listenTex then cell.listenTex:Hide() end
  if cell.num then cell.num:SetText("") end
  if cell.key then cell.key:SetText("") end
  SetCellGlow(cell, false, false)
end

local function RenderCallerEntryVisuals()
  if not ShouldUseAssignmentMode() then return end

  RestoreOriginalCellOrder()
  UseAssignmentVisuals()

  for i = 1, #cells do
    ClearCellOverlayVisuals(cells[i])
  end

  local db = DB()
  local perSymbol = {}
  for step = 1, 5 do
    local symbolIndex = db.sequence[step]
    if symbolIndex then
      perSymbol[symbolIndex] = perSymbol[symbolIndex] and (perSymbol[symbolIndex] .. "," .. step) or tostring(step)
    end
  end

  for symbolIndex = 1, #cells do
    if cells[symbolIndex] and cells[symbolIndex].num then
      cells[symbolIndex].num:SetText(perSymbol[symbolIndex] or "")
    end
  end
end

local function RenderCallerSequenceVisuals()
  if not ShouldUseAssignmentMode() then return end

  RestoreOriginalCellOrder()

  local db = DB()
  for slot = 1, #cells do
    local cell = cells[slot]
    local symbolIndex = db.sequence[slot]

    HideAssignmentIcon(cell)
    ClearCellOverlayVisuals(cell)

    if symbolIndex then
      SetListenerSlotSymbol(cell, symbolIndex)
      if cell.num then cell.num:SetText(tostring(slot)) end
      if cell.key then cell.key:SetText(GetMacroKeybind(SYMBOL_MACRO_NAMES[symbolIndex]) or "?") end
    end
  end
end

local function GetCellForOrderStep(step)
  local db = DB()

  if IsMythicRaid() then
    local symbolIndex = db.sequence and db.sequence[step]
    if symbolIndex then
      return cells[step], symbolIndex
    end
    return nil, nil
  end

  for i = 1, #cells do
    if db.assign[i] == step then
      return cells[i], i
    end
  end
end

local function HighlightCallStep()
  ClearStepGlow()

  if callStep < 1 or callStep > 5 then
    return
  end

  local cell = GetCellForOrderStep(callStep)
  if cell then
    SetCellGlow(cell, true, false)
  end
end

local function StartCallTracking()
  callStep = 1
  HighlightCallStep()
end

local function StopCallTracking()
  callStep = 0
  ClearStepGlow()
end

local function UpdateKeybindTexts(complete)
  local db = DB()

  for i = 1, #cells do
    if cells[i].key then
      if complete then
        if IsMythicRaid() then
          local symbolIndex = db.sequence and db.sequence[i]
          cells[i].key:SetText((symbolIndex and GetMacroKeybind(SYMBOL_MACRO_NAMES[symbolIndex])) or "?")
        else
          cells[i].key:SetText(GetMacroKeybind(SYMBOL_MACRO_NAMES[i]) or "?")
        end
      else
        cells[i].key:SetText("")
      end
    end
  end
end

-- -------------------------------------------------------
-- Logic
-- -------------------------------------------------------
local function ResetAll(forceListenerBlank)
  local db = DB()

  wipe(db.assign)
  wipe(db.used)
  wipe(db.sequence)

  for i = 1, #cells do
    cells[i].num:SetText("")
    if cells[i].key then cells[i].key:SetText("") end
    if cells[i].listenTex then cells[i].listenTex:Hide() end
  end

  listenerStep = 0
  StopCallTracking()
  SetCompleteVisual(false)
  UpdateKeybindTexts(false)

  -- Local right-click/slash reset preserves caller/debug assignment mode.
  -- Raid chat clear forces listener-style blanking for non-authority clients, even if debug was used for testing.
  if forceListenerBlank and not IsPlayerLeadOrAssist() then
    UseListenerBlankVisuals()
  else
    ApplyIdleVisualMode()
  end
end
local function GetNextNumber()
  local db = DB()

  for n = 1, 5 do
    if not db.used[n] then
      return n
    end
  end
end

local function Assign(i)
  if not ShouldUseAssignmentMode() then return end

  local db = DB()

  if IsMythicRaid() then
    local step = GetSequenceCount() + 1
    if step > 5 then return end

    -- Mythic-compatible: record the clicked symbol for this step.
    -- This allows duplicates like Circle > Circle or T > T.
    db.sequence[step] = i

    if step == 5 then
      RenderCallerSequenceVisuals()
      SetCompleteVisual(true)
      UpdateKeybindTexts(true)
      StartCallTracking()
    else
      RenderCallerEntryVisuals()
      SetCompleteVisual(false)
      StopCallTracking()
    end

    return
  end

  -- Non-Mythic keeps the original one-number-per-symbol behavior.
  if db.assign[i] then return end

  local n = GetNextNumber()
  if not n then return end

  db.assign[i] = n
  db.used[n] = true

  cells[i].num:SetText(tostring(n))

  if n == 5 then
    ReorderByAssignedNumber()
    SetCompleteVisual(true)
    UpdateKeybindTexts(true)
    StartCallTracking()
  end
end

local function ApplyFromDB()
  if not ShouldUseAssignmentMode() then
    UseListenerBlankVisuals()
    return
  end

  if IsMythicRaid() then
    if IsSequenceComplete() then
      RenderCallerSequenceVisuals()
      SetCompleteVisual(true)
      UpdateKeybindTexts(true)
      StartCallTracking()
    else
      RenderCallerEntryVisuals()
      SetCompleteVisual(false)
      UpdateKeybindTexts(false)
      StopCallTracking()
    end
    return
  end

  local db = DB()
  local complete = true

  UseAssignmentVisuals()

  for i = 1, #cells do
    local n = db.assign[i]
    cells[i].num:SetText(n and tostring(n) or "")

    if not n then
      complete = false
    end
  end

  if complete then
    ReorderByAssignedNumber()
    SetCompleteVisual(true)
    UpdateKeybindTexts(true)
    StartCallTracking()
  else
    RestoreOriginalCellOrder()
    SetCompleteVisual(false)
    UpdateKeybindTexts(false)
    StopCallTracking()
  end
end

-- -------------------------------------------------------
-- Build UI
-- -------------------------------------------------------
local function BuildUI()
  if frame then return end
  DB()

  local totalW = PAD_X * 2 + CELL_SIZE * 5 + CELL_GAP * 4
  local totalH = PAD_Y * 2 + CELL_SIZE + 38

  frame = CreateFrame("Frame", "ShortyFallsFrame", UIParent, "BackdropTemplate")
  frame:SetSize(totalW, totalH)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0, 0, 0, 0.35)
  frame:SetBackdropBorderColor(1, 1, 1, 0.25)
  frame:SetClampedToScreen(true)

  frame:EnableMouse(true)
  frame:SetMovable(true)

  local fontPath = (GameFontNormal and select(1, GameFontNormal:GetFont()))
    or STANDARD_TEXT_FONT
    or "Fonts\\FRIZQT__.TTF"

  for i = 1, 5 do
    local cell = CreateFrame("Button", nil, frame, "BackdropTemplate")
    cell:SetSize(CELL_SIZE, CELL_SIZE)

    PlaceCell(cell, i)

    cell:SetBackdrop({
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    cell:SetBackdropBorderColor(1, 1, 1, 0.25)

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(cell)
    cell.bg:SetColorTexture(1, 1, 1, 0.10)

    local iconSpec = ICON_ORDER[i]

    cell.icon = cell:CreateTexture(nil, "OVERLAY")
    cell.icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
    cell.icon:SetSize(CELL_SIZE - 10, CELL_SIZE - 10)
    cell.icon:SetAlpha(1)

    local ok = cell.icon:SetTexture(TEXTURE_MAP[i])

    if ok then
      cell.icon:SetTexCoord(0, 1, 0, 1)
    else
      if type(iconSpec) == "number" then
        ApplyRaidIcon(cell.icon, iconSpec)
      else
        cell.icon:Hide()
        print("|cff66ccffShortyFalls|r Missing media texture: " .. tostring(TEXTURE_MAP[i]))
      end
    end

    cell.num = cell:CreateFontString(nil, "OVERLAY")
    cell.num:SetPoint("BOTTOM", cell, "TOP", 0, 6)
    cell.num:SetFont(fontPath, 28, "OUTLINE")
    cell.num:SetTextColor(1, 1, 1, 1)
    cell.num:SetShadowColor(0, 0, 0, 1)
    cell.num:SetShadowOffset(0, 0)
    cell.num:SetText("")

    cell.key = cell:CreateFontString(nil, "OVERLAY")
    cell.key:SetPoint("TOP", cell, "BOTTOM", 0, -3)
    cell.key:SetFont(fontPath, 13, "OUTLINE")
    cell.key:SetTextColor(0.2, 1, 0.35, 1)
    cell.key:SetShadowColor(0, 0, 0, 1)
    cell.key:SetShadowOffset(0, 0)
    cell.key:SetText("")

    cell.listenTex = cell:CreateTexture(nil, "OVERLAY")
    cell.listenTex:SetPoint("CENTER", cell, "CENTER", 0, 0)
    cell.listenTex:SetSize(CELL_SIZE - 10, CELL_SIZE - 10)
    cell.listenTex:Hide()


    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetScript("OnClick", function(_, btn)
      if btn == "RightButton" then
        ResetAll()
      else
        Assign(i)
      end
    end)

    cells[i] = cell
  end

  RestorePosition()
  ApplyLockState()
  ApplyFromDB()
  UpdateVisibility()
end

BuildUI()

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
end

-- -------------------------------------------------------
-- Addon version check comms
-- -------------------------------------------------------
local function SendAddonMessageSafe(message)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  local channel = GetGroupChannel()
  if not channel then return false end
  return C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel)
end

local function RunAddonCheck()
  if InCombatLockdown and InCombatLockdown() then
    print("|cff66ccffShortyFalls|r Cannot run addon check in combat.")
    return
  end

  local channel = GetGroupChannel()
  if not channel then
    print("|cff66ccffShortyFalls|r You are not in a group.")
    return
  end

  wipe(checkResponders)
  checkActive = true
  checkResponders[UnitFullName("player") or UnitName("player") or "player"] = ADDON_VERSION

  print("|cff66ccffShortyFalls|r Running addon check... version " .. tostring(ADDON_VERSION))
  SendAddonMessageSafe("CHECK:" .. tostring(ADDON_VERSION))

  C_Timer.After(3, function()
    checkActive = false

    local missing = {}
    local outdated = {}
    local total = 0
    local found = 0

    ForEachGroupMember(function(unit)
      local fullName = UnitFullName(unit)
      if fullName then
        total = total + 1
        local ver = checkResponders[fullName]
        if ver then
          found = found + 1
          if tostring(ver) ~= tostring(ADDON_VERSION) then
            table.insert(outdated, fullName .. " (" .. tostring(ver) .. ")")
          end
        else
          table.insert(missing, fullName)
        end
      end
    end)

    print("|cff66ccffShortyFalls|r Addon check: " .. found .. "/" .. total .. " installed. Version: " .. tostring(ADDON_VERSION))

    if #missing > 0 then
      print("|cffff3333MISSING:|r " .. table.concat(missing, ", "))
    else
      print("|cff66ccffShortyFalls|r MISSING: none")
    end

    if #outdated > 0 then
      print("|cffffff00OUTDATED:|r " .. table.concat(outdated, ", "))
    else
      print("|cff66ccffShortyFalls|r OUTDATED: none")
    end
  end)
end

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
  if prefix ~= ADDON_PREFIX or not message then return end

  local command, version = message:match("^(%u+):?(.*)$")

  if command == "CHECK" then
    SendAddonMessageSafe("ACK:" .. tostring(ADDON_VERSION))
    return
  end

  if command == "ACK" and checkActive then
    local fullName = NormalizeName(sender)
    if fullName then
      checkResponders[fullName] = (version and version ~= "") and version or "unknown"
    end
  end
end)

-- -------------------------------------------------------
-- Eventless polling visibility
-- -------------------------------------------------------
C_Timer.NewTicker(1.0, function()
  UpdateVisibility()
end)

-- -------------------------------------------------------
-- Chat detection progress tracking
-- -------------------------------------------------------
local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_RAID")
chatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
chatFrame:RegisterEvent("CHAT_MSG_PARTY")
chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
chatFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
chatFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")

chatFrame:SetScript("OnEvent", function(_, _, msg, sender)
  if not msg then return end

  local token = msg:lower():match("sfalls:%a+")
  if not token then return end

  if not IsTrustedSender(sender) then
    return
  end

  if token == "sfalls:clear" then
    ResetAll(true)
    return
  end

  local symbolIndex = CHAT_SYMBOL_MAP[token]
  if not symbolIndex then return end

  if callStep >= 1 and callStep <= 5 then
    local _, expectedSymbolIndex = GetCellForOrderStep(callStep)
    if symbolIndex == expectedSymbolIndex then
      callStep = callStep + 1

      if callStep > 5 then
        ClearStepGlow()
        SetCompleteVisual(true)
      else
        HighlightCallStep()
      end
    else
      local expectedCell = GetCellForOrderStep(callStep)
      SetCellGlow(expectedCell, false, true)
      C_Timer.After(0.18, HighlightCallStep)
    end
    return
  end

  AddListenerSymbol(symbolIndex)
end)

-- -------------------------------------------------------
-- Slash commands
-- -------------------------------------------------------
SLASH_SHORTYFALLS1 = "/sfalls"
SlashCmdList["SHORTYFALLS"] = function(msg)
  msg = (msg or ""):lower()

  if msg == "macro" or msg == "macros" then
    CreateShortyFallsMacros()
    return
  end

  if msg == "check" then
    RunAddonCheck()
    return
  end

  if msg == "debug" then
    local db = DB()
    db.debugMode = not db.debugMode

    if db.debugMode then
      frame:Show()
      print("|cff66ccffShortyFalls|r debug mode |cff00ff00ON|r - frame forced visible.")
    else
      UpdateVisibility()
      print("|cff66ccffShortyFalls|r debug mode |cffff0000OFF|r - raid mapID 2913 gate restored.")
    end
    return
  end

  if msg == "show" then
    if ShouldBeActive() then
      frame:Show()
    else
      frame:Hide()
      print("|cff66ccffShortyFalls|r only shows inside raid mapID 2913.")
    end
    return
  end

  if msg == "hide" then
    frame:Hide()
    return
  end

  if msg == "lock" then
    DB().locked = true
    ApplyLockState()
    print("|cff66ccffShortyFalls|r locked.")
    return
  end

  if msg == "unlock" then
    DB().locked = false
    ApplyLockState()
    print("|cff66ccffShortyFalls|r unlocked.")
    return
  end

  if msg == "clear" or msg == "reset" then
    ResetAll()
    return
  end

  if msg == "track" then
    StartCallTracking()
    print("|cff66ccffShortyFalls|r call tracking restarted.")
    return
  end

  if msg == "where" then
    local name, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
    print("|cff66ccffShortyFalls|r Instance:", name or "nil", "Type:", instanceType or "nil", "MapID:", tostring(mapID))
    print("|cff66ccffShortyFalls|r Active:", ShouldBeActive() and "YES" or "NO")
    print("|cff66ccffShortyFalls|r Debug Mode:", DB().debugMode and "ON" or "OFF")
    print("|cff66ccffShortyFalls|r Assignment Mode:", IsMythicRaid() and "MYTHIC SEQUENCE" or "STANDARD UNIQUE")
    return
  end

  print("|cff66ccffShortyFalls commands|r:")
  print("/sfalls macro")
  print("/sfalls check")
  print("/sfalls debug")
  print("/sfalls show")
  print("/sfalls hide")
  print("/sfalls lock")
  print("/sfalls unlock")
  print("/sfalls clear")
  print("/sfalls track")
  print("/sfalls where")
end