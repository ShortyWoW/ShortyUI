-- Options.lua
-- Options panel for ShortyTalents
-- - Per-spec configuration
-- - Multi-select dropdown (checklist) per activity
-- - Stores rules by saved configID (robust)

local ADDON_NAME = ...
local ST = _G.ShortyTalents
if not ST then return end

-- -----------------------------
-- DB helpers (mirror core expectations)
-- -----------------------------
local function EnsureDB()
  ShortyTalentsDB = ShortyTalentsDB or {}
  ShortyTalentsDB.spec = ShortyTalentsDB.spec or {}
end

local function GetCurrentSpecID()
  local specIndex = GetSpecialization()
  if not specIndex then return nil end
  return select(1, GetSpecializationInfo(specIndex))
end

local function EnsureSpecDB(specID)
  EnsureDB()
  if not specID then return nil end

  local specDB = ShortyTalentsDB.spec[specID]
  if not specDB then
    specDB = { allowed = {}, raid = { bossAllowedByNPCID = {} } }
    for _, activity in ipairs(ST.ACTIVITIES) do
      specDB.allowed[activity] = {} -- set of configIDs
    end
    ShortyTalentsDB.spec[specID] = specDB
  else
    specDB.allowed = specDB.allowed or {}
    for _, activity in ipairs(ST.ACTIVITIES) do
      specDB.allowed[activity] = specDB.allowed[activity] or {}
    end
    specDB.raid = specDB.raid or { bossAllowedByNPCID = {} }
    specDB.raid.bossAllowedByNPCID = specDB.raid.bossAllowedByNPCID or {}
  end

  return specDB
end

-- -----------------------------
-- Saved loadout list for current spec
-- -----------------------------
local function GetSavedLoadoutsForSpec(specID)
  -- Returns array of { configID=number, name=string }
  local out = {}
  if not specID then return out end
  if not C_ClassTalents.GetConfigIDsBySpecID then return out end

  local ids = C_ClassTalents.GetConfigIDsBySpecID(specID)
  if type(ids) ~= "table" then return out end

  for _, configID in ipairs(ids) do
    local info = C_Traits.GetConfigInfo(configID)
    if info and info.name then
      table.insert(out, { configID = configID, name = info.name })
    end
  end

  table.sort(out, function(a, b)
    if a.name == b.name then
      return a.configID < b.configID
    end
    return a.name < b.name
  end)

  return out
end

-- -----------------------------
-- Small UI helpers
-- -----------------------------
local function CreateHeader(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetText(text)
  return fs
end

local function CreateButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetSize(width or 220, height or 22)
  return b
end

local function CreateMultiSelectDropdown(parent, width)
  -- This is a button that opens a checklist menu.
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 200, 22)
  b:SetText("Select…")

  -- Left-align text + add padding WITHOUT SetTextInsets (not available on all templates/builds)
  local fs = b:GetFontString()
  if fs then
    fs:SetJustifyH("LEFT")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", 10, 0)
    fs:SetPoint("RIGHT", b, "RIGHT", -10, 0)
  end

  b:SetScript("OnClick", function(self)
    if self.OpenMenu then
      self:OpenMenu()
    end
  end)

  return b
end


local function BuildSummaryText(selectedSet, loadouts)
  -- show up to 2 names then "+N more"
  if not selectedSet or not next(selectedSet) then
    return "Select…"
  end

  local names = {}
  for _, item in ipairs(loadouts) do
    if selectedSet[item.configID] then
      table.insert(names, item.name)
    end
  end

  if #names == 0 then return "Select…" end
  if #names == 1 then return names[1] end
  if #names == 2 then return names[1] .. ", " .. names[2] end
  return names[1] .. ", " .. names[2] .. string.format(" (+%d more)", #names - 2)
end

-- -----------------------------
-- Panel (modern Settings API)
-- -----------------------------
local panel = CreateFrame("Frame", "ShortyTalentsOptionsPanel", UIParent)
panel.name = "ShortyTalents"

-- IMPORTANT: Settings canvas does not always clip children like old InterfaceOptions did.
-- We'll put everything in a clipped content container to prevent bleed.
local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
content:SetClipsChildren(true)

local ui = {
  rows = {}, -- activity -> { label, dropdown, UpdateWidth }
  specText = nil,
  hintText = nil,
  categoryID = nil,
}

-- -----------------------------
-- Dropdown checklist menu
-- -----------------------------
local menuFrame = CreateFrame("Frame", "ShortyTalentsDropDownMenuFrame", UIParent, "UIDropDownMenuTemplate")

local function ToggleAllowed(specDB, activity, configID, enabled)
  if not (specDB and activity and configID) then return end
  specDB.allowed[activity] = specDB.allowed[activity] or {}
  if enabled then
    specDB.allowed[activity][configID] = true
  else
    specDB.allowed[activity][configID] = nil
  end
end

local function OpenChecklistMenu(dropdownButton, activity, specID)
  local specDB = EnsureSpecDB(specID)
  local loadouts = GetSavedLoadoutsForSpec(specID)

  local function InitializeMenu(_, level)
    if level ~= 1 then return end

    local titleInfo = UIDropDownMenu_CreateInfo()
    titleInfo.isTitle = true
    titleInfo.notCheckable = true
    titleInfo.text = activity .. " allowed loadouts"
    UIDropDownMenu_AddButton(titleInfo, level)

    if #loadouts == 0 then
      local noneInfo = UIDropDownMenu_CreateInfo()
      noneInfo.notCheckable = true
      noneInfo.disabled = true
      noneInfo.text = "(No saved loadouts found for this spec)"
      UIDropDownMenu_AddButton(noneInfo, level)
      return
    end

    for _, item in ipairs(loadouts) do
      local info = UIDropDownMenu_CreateInfo()
      info.keepShownOnClick = true
      info.isNotRadio = true
      info.checked = function()
        return specDB.allowed[activity] and specDB.allowed[activity][item.configID] == true
      end
      info.text = string.format("%s  (ID: %d)", item.name, item.configID)
      info.func = function(_, _, _, checked)
        ToggleAllowed(specDB, activity, item.configID, checked)
        dropdownButton:SetText(BuildSummaryText(specDB.allowed[activity], loadouts))
      end
      UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_AddSeparator(level)

    local clearInfo = UIDropDownMenu_CreateInfo()
    clearInfo.notCheckable = true
    clearInfo.text = "Clear all"
    clearInfo.func = function()
      wipe(specDB.allowed[activity])
      dropdownButton:SetText("Select…")
      CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(clearInfo, level)
  end

  UIDropDownMenu_Initialize(menuFrame, InitializeMenu, "MENU")
  ToggleDropDownMenu(1, nil, menuFrame, dropdownButton, 0, 0)
end

-- -----------------------------
-- UI refresh
-- -----------------------------
local function RefreshUI()
  local specID = GetCurrentSpecID()
  local specName = "Unknown"
  if specID then
    local _, name = GetSpecializationInfoByID(specID)
    specName = name or tostring(specID)
  end

  ui.specText:SetText(string.format("Current Spec: %s (SpecID: %s)", tostring(specName), tostring(specID or "nil")))

  if not specID then
    ui.hintText:SetText("No specialization detected. Please choose a spec.")
    for _, row in pairs(ui.rows) do
      row.dropdown:SetText("Select…")
      row.dropdown:Disable()
    end
    return
  end

  ui.hintText:SetText("Select allowed saved loadouts per activity. If an activity has no selections, ShortyTalents will not warn for that activity.")

  local specDB = EnsureSpecDB(specID)
  local loadouts = GetSavedLoadoutsForSpec(specID)

  for activity, row in pairs(ui.rows) do
    row.dropdown:Enable()
    row.dropdown:SetText(BuildSummaryText(specDB.allowed[activity], loadouts))
    row.dropdown.OpenMenu = function(btn)
      OpenChecklistMenu(btn, activity, specID)
    end
  end
end

panel:SetScript("OnShow", RefreshUI)

-- -----------------------------
-- Layout (clean 2-column grid + dynamic widths)
-- -----------------------------
local title = CreateHeader(content, "ShortyTalents")
title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

ui.specText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
ui.specText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
ui.specText:SetText("Current Spec: ...")

ui.hintText = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
ui.hintText:SetPoint("TOPLEFT", ui.specText, "BOTTOMLEFT", 0, -8)
ui.hintText:SetWidth(720)
ui.hintText:SetJustifyH("LEFT")
ui.hintText:SetText("...")

-- Grid container (stretches with panel; no hard-coded width)
local grid = CreateFrame("Frame", nil, content)
grid:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -68)
grid:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -68)
grid:SetHeight(280)

-- Column sizing
local LABEL_W = 110
local ROW_H = 26
local ROW_GAP = 12
local DROPDOWN_MIN_W = 220
local LABEL_TO_DROPDOWN_GAP = 14

for i, activity in ipairs(ST.ACTIVITIES) do
  local row = CreateFrame("Frame", nil, grid)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -((i - 1) * (ROW_H + ROW_GAP)))
  row:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -((i - 1) * (ROW_H + ROW_GAP)))

  row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.label:SetWidth(LABEL_W)
  row.label:SetJustifyH("LEFT")
  row.label:SetText(activity .. ":")

  row.dropdown = CreateMultiSelectDropdown(row, 200) -- width will be set dynamically
  row.dropdown:SetPoint("RIGHT", row, "RIGHT", 0, 0)

  -- Dynamic width so we never bleed outside the visible panel
  local function UpdateRowWidths()
    local w = row:GetWidth() or 0
    local dropdownW = math.max(DROPDOWN_MIN_W, w - LABEL_W - LABEL_TO_DROPDOWN_GAP)
    row.dropdown:SetWidth(dropdownW)
  end
  row:SetScript("OnSizeChanged", UpdateRowWidths)
  UpdateRowWidths()

  ui.rows[activity] = row
end

-- Buttons row (stretches; centered group)
local btnRow = CreateFrame("Frame", nil, content)
btnRow:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -18)
btnRow:SetPoint("TOPRIGHT", grid, "BOTTOMRIGHT", 0, -18)
btnRow:SetHeight(26)

btnRow.checkBtn = CreateButton(btnRow, "Run Check Now", 140, 22)
btnRow.reloadBtn = CreateButton(btnRow, "Reload UI", 120, 22)
btnRow.debugBtn = CreateButton(btnRow, "Print Selected Loadout", 180, 22)

-- Center the group based on total width
local totalW = 140 + 14 + 120 + 14 + 180
btnRow.checkBtn:SetPoint("TOPLEFT", btnRow, "TOP", -(totalW / 2), 0)
btnRow.reloadBtn:SetPoint("LEFT", btnRow.checkBtn, "RIGHT", 14, 0)
btnRow.debugBtn:SetPoint("LEFT", btnRow.reloadBtn, "RIGHT", 14, 0)

btnRow.checkBtn:SetScript("OnClick", function()
  if ST.CheckTalentsNow then
    ST.CheckTalentsNow("options_button")
  end
end)

btnRow.reloadBtn:SetScript("OnClick", function()
  ReloadUI()
end)

btnRow.debugBtn:SetScript("OnClick", function()
  local specID = GetCurrentSpecID()
  if not specID then
    print("|cff66ccffShortyTalents|r: No spec detected.")
    return
  end

  local selectedID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
  local name = (selectedID and selectedID > 0) and (C_Traits.GetConfigInfo(selectedID) or {}).name or nil
  print(string.format("|cff66ccffShortyTalents|r: Selected Saved Loadout: %s (ID: %s)",
    tostring(name or "None"),
    tostring(selectedID or "nil")
  ))
end)

-- -----------------------------
-- Register with modern Settings API + hook /stalent
-- -----------------------------
local category = Settings.RegisterCanvasLayoutCategory(panel, "ShortyTalents")
Settings.RegisterAddOnCategory(category)
ui.categoryID = category:GetID()
ST.OPTIONS_CATEGORY_ID = ui.categoryID

function ST:OpenOptions()
  if ST.OPTIONS_CATEGORY_ID then
    Settings.OpenToCategory(ST.OPTIONS_CATEGORY_ID)
  else
    Settings.OpenToCategory("ShortyTalents")
  end
end
ST.OpenOptions = ST.OpenOptions