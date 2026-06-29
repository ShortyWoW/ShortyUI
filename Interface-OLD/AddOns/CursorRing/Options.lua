local addonName, ns = ...
local L = ns.L or {}

local function T(key)
  local value = L[key]
  if value == nil or value == "" then
    return key
  end
  return value
end

local Controls = ns.Controls or {}
local CopyTable = CopyTable
local Settings = Settings
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns

local createCheck = Controls.createCheck
local createSlider = Controls.createSlider
local createDropdown = Controls.createDropdown
local createMainActionButton = Controls.createMainActionButton
local initLegacyScrollFrame = Controls.initLegacyScrollFrame
local shared_settings_registered = false

local function Clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local SIZE_RADIUS_MIN = 10
local SIZE_RADIUS_MAX = 100
local SIZE_PERCENT_MIN = 1
local SIZE_PERCENT_MAX = 100
local SIZE_PERCENT_DEFAULT = 50
local SIZE_RADIUS_AT_50 = 35

local COLOR_MODE_CHOICES = {
  { value = "class", text = T("Player Class Color") },
  { value = "highvis", text = T("High-Visibility Green") },
  { value = "custom", text = T("Custom Color") },
  { value = "gradient", text = T("Gradient") },
}

local FORCE_CLASS_CHOICES = {
  { value = "NONE", text = T("None") },
  { value = "warrior", text = T("Warrior") },
  { value = "paladin", text = T("Paladin") },
  { value = "hunter", text = T("Hunter") },
  { value = "rogue", text = T("Rogue") },
  { value = "priest", text = T("Priest") },
  { value = "deathknight", text = T("Death Knight") },
  { value = "shaman", text = T("Shaman") },
  { value = "mage", text = T("Mage") },
  { value = "warlock", text = T("Warlock") },
  { value = "monk", text = T("Monk") },
  { value = "druid", text = T("Druid") },
  { value = "demonhunter", text = T("Demon Hunter") },
  { value = "evoker", text = T("Evoker") },
}

local GCD_STYLE_CHOICES = {
  { value = "simple", text = T("Simple (No Edge)") },
  { value = "blizzard", text = T("Blizzard-Style Edge") },
}

local TRAIL_ASSET_CHOICES = ns.TrailAssetChoices or {
  {
    text = T("Basic"),
    items = {
      { value = "solid", text = T("Solid White") },
      { value = "cooldown", text = T("Cooldown Swipe") },
    },
  },
  {
    text = T("Cursor"),
    items = {
      { value = "openhand", text = T("Open Hand Glow") },
      { value = "openhand2x", text = T("Open Hand Glow 2x") },
    },
  },
  {
    text = T("Glows"),
    items = {
      { value = "talent", text = T("Talent Glow") },
    },
  },
}

local TRAIL_COLOR_MODE_CHOICES = ns.TrailColorModeChoices or {
  { value = "ring", text = T("Match ring") },
  { value = "custom", text = T("Custom color") },
}

local TRAIL_BLEND_MODE_CHOICES = ns.TrailBlendModeChoices or {
  { value = "ADD", text = T("Additive") },
  { value = "BLEND", text = T("Blend") },
}

local function PercentToRadius(percent)
  local pct = Clamp(math.floor(tonumber(percent) or SIZE_PERCENT_DEFAULT), SIZE_PERCENT_MIN, SIZE_PERCENT_MAX)
  if pct <= 50 then
    local t = (pct - SIZE_PERCENT_MIN) / (50 - SIZE_PERCENT_MIN)
    return math.floor(SIZE_RADIUS_MIN + (t * (SIZE_RADIUS_AT_50 - SIZE_RADIUS_MIN)) + 0.5)
  end
  local t = (pct - 50) / (SIZE_PERCENT_MAX - 50)
  return math.floor(SIZE_RADIUS_AT_50 + (t * (SIZE_RADIUS_MAX - SIZE_RADIUS_AT_50)) + 0.5)
end

local function RadiusToPercent(radius)
  local value = Clamp(math.floor(tonumber(radius) or SIZE_RADIUS_AT_50), SIZE_RADIUS_MIN, SIZE_RADIUS_MAX)
  if value <= SIZE_RADIUS_AT_50 then
    local t = (value - SIZE_RADIUS_MIN) / (SIZE_RADIUS_AT_50 - SIZE_RADIUS_MIN)
    return Clamp(math.floor(SIZE_PERCENT_MIN + (t * (50 - SIZE_PERCENT_MIN)) + 0.5), SIZE_PERCENT_MIN, SIZE_PERCENT_MAX)
  end
  local t = (value - SIZE_RADIUS_AT_50) / (SIZE_RADIUS_MAX - SIZE_RADIUS_AT_50)
  return Clamp(math.floor(50 + (t * (SIZE_PERCENT_MAX - 50)) + 0.5), SIZE_PERCENT_MIN, SIZE_PERCENT_MAX)
end

local function GetDB()
  CursorRingDB = CursorRingDB or CopyTable(ns.defaults)
  CursorRingCharDB = CursorRingCharDB or CopyTable(ns.charDefaults)
  return CursorRingDB, CursorRingCharDB
end

local function Refresh()
  if ns and ns.Refresh then
    ns.Refresh()
  end
end

local function IsLauncherButtonShown()
  local launcher = ns.GetSharedLauncher and ns.GetSharedLauncher()
  if type(launcher) == "table" and type(launcher.IsAddonHidden) == "function" then
    return not launcher:IsAddonHidden(addonName)
  end
  return true
end

local function SetLauncherButtonShown(value)
  local launcher = ns.GetSharedLauncher and ns.GetSharedLauncher()
  if type(launcher) == "table" and type(launcher.SetAddonHidden) == "function" then
    launcher:SetAddonHidden(addonName, not value)
    return
  end
  if type(ns.RefreshSharedLauncher) == "function" then
    ns.RefreshSharedLauncher()
  end
end

local function getColorMode()
  local db = GetDB()
  if db.colorMode == "gradient" then
    return "gradient"
  end
  if db.useHighVis or db.colorMode == "highvis" then
    return "highvis"
  end
  if db.useClassColor or db.colorMode == "class" then
    return "class"
  end
  return "custom"
end

local function setColorMode(mode)
  local db = GetDB()
  if mode == "gradient" then
    db.colorMode = "gradient"
    db.useClassColor = false
    db.useHighVis = false
  elseif mode == "class" then
    db.colorMode = "class"
    db.useClassColor = true
    db.useHighVis = false
  elseif mode == "highvis" then
    db.colorMode = "highvis"
    db.useClassColor = false
    db.useHighVis = true
  else
    db.colorMode = "custom"
    db.useClassColor = false
    db.useHighVis = false
  end
  Refresh()
end

local function getForcedClass()
  local db = GetDB()
  local mode = db.colorMode
  if not mode or mode == "class" or mode == "custom" or mode == "highvis" or mode == "gradient" then
    return "NONE"
  end
  return mode
end

local function setForcedClass(value)
  local db = GetDB()
  if value == "NONE" then
    if db.useHighVis then
      db.colorMode = "highvis"
    elseif db.useClassColor then
      db.colorMode = "class"
    else
      db.colorMode = "custom"
    end
  else
    db.colorMode = value
  end
  Refresh()
end

local function setRingRadiusPercent(value)
  local db = GetDB()
  db.ringRadius = PercentToRadius(value)
  Refresh()
end

local function getRingRadiusPercent()
  local db = GetDB()
  return RadiusToPercent(db.ringRadius or SIZE_RADIUS_AT_50)
end

local function setRingThickness(value)
  local db = GetDB()
  db.ringThickness = Clamp(math.floor(tonumber(value) or 50), 1, 100)
  Refresh()
end

local function getRingThickness()
  local db = GetDB()
  return Clamp(math.floor(tonumber(db.ringThickness) or 50), 1, 100)
end

local function setRingMargin(value)
  local db = GetDB()
  db.ringMargin = Clamp(math.floor(tonumber(value) or 2), 0, 80)
  Refresh()
end

local function getRingMargin()
  local db = GetDB()
  return Clamp(math.floor(tonumber(db.ringMargin) or 2), 0, 80)
end

local function setOffsetX(value)
  local db = GetDB()
  db.offsetX = Clamp(math.floor(tonumber(value) or 0), -100, 100)
  Refresh()
end

local function getOffsetX()
  local db = GetDB()
  return Clamp(db.offsetX or 0, -100, 100)
end

local function setOffsetY(value)
  local db = GetDB()
  db.offsetY = Clamp(math.floor(tonumber(value) or 0), -100, 100)
  Refresh()
end

local function getOffsetY()
  local db = GetDB()
  return Clamp(db.offsetY or 0, -100, 100)
end

local function setCustomColor(r, g, b)
  local db = GetDB()
  db.customColor = db.customColor or { r = 1, g = 1, b = 1 }
  db.customColor.r, db.customColor.g, db.customColor.b = r, g, b
  db.useClassColor = false
  db.useHighVis = false
  db.colorMode = "custom"
  Refresh()
end

local function getCustomColor()
  local db = GetDB()
  local color = db.customColor or { r = 1, g = 1, b = 1 }
  return color.r or 1, color.g or 1, color.b or 1
end

local function setGradientColor1(r, g, b)
  local db = GetDB()
  db.gradientColor1 = db.gradientColor1 or { r = 1, g = 1, b = 1 }
  db.gradientColor1.r, db.gradientColor1.g, db.gradientColor1.b = r, g, b
  Refresh()
end

local function getGradientColor1()
  local db = GetDB()
  local color = db.gradientColor1 or { r = 1, g = 1, b = 1 }
  return color.r or 1, color.g or 1, color.b or 1
end

local function setGradientColor2(r, g, b)
  local db = GetDB()
  db.gradientColor2 = db.gradientColor2 or { r = 1, g = 1, b = 1 }
  db.gradientColor2.r, db.gradientColor2.g, db.gradientColor2.b = r, g, b
  Refresh()
end

local function getGradientColor2()
  local db = GetDB()
  local color = db.gradientColor2 or { r = 1, g = 1, b = 1 }
  return color.r or 1, color.g or 1, color.b or 1
end

local function setGradientAngle(value)
  local db = GetDB()
  db.gradientAngle = (tonumber(value) or 0) % 360
  Refresh()
end

local function getGradientAngle()
  local db = GetDB()
  return db.gradientAngle or 0
end

local function setInCombatAlphaPercent(value)
  local db = GetDB()
  db.inCombatAlpha = Clamp(tonumber(value) or 70, 0, 100) / 100
  Refresh()
end

local function getInCombatAlphaPercent()
  local db = GetDB()
  return Clamp(math.floor(((db.inCombatAlpha or 0.70) * 100) + 0.5), 0, 100)
end

local function setOutCombatAlphaPercent(value)
  local db = GetDB()
  db.outCombatAlpha = Clamp(tonumber(value) or 30, 0, 100) / 100
  Refresh()
end

local function getOutCombatAlphaPercent()
  local db = GetDB()
  return Clamp(math.floor(((db.outCombatAlpha or 0.30) * 100) + 0.5), 0, 100)
end

local function setGCDDimPercent(value)
  local _, cdb = GetDB()
  cdb.gcdDimMultiplier = Clamp(tonumber(value) or 35, 0, 100) / 100
  Refresh()
end

local function getGCDDimPercent()
  local _, cdb = GetDB()
  return Clamp(math.floor(((cdb.gcdDimMultiplier or 0.35) * 100) + 0.5), 0, 100)
end

local function setCastRingColor(r, g, b)
  local _, cdb = GetDB()
  cdb.castRingColor = cdb.castRingColor or { r = 0.20, g = 0.80, b = 1.00 }
  cdb.castRingColor.r, cdb.castRingColor.g, cdb.castRingColor.b = r, g, b
  Refresh()
end

local function getCastRingColor()
  local _, cdb = GetDB()
  local color = cdb.castRingColor or { r = 0.20, g = 0.80, b = 1.00 }
  return color.r or 0.20, color.g or 0.80, color.b or 1.00
end

local function setCastRingThickness(value)
  local _, cdb = GetDB()
  cdb.castRingThickness = Clamp(math.floor(tonumber(value) or 25), 1, 99)
  Refresh()
end

local function getCastRingThickness()
  local _, cdb = GetDB()
  return Clamp(math.floor(tonumber(cdb.castRingThickness) or 25), 1, 99)
end

local function setResourceRingThickness(value)
  local _, cdb = GetDB()
  cdb.resourceRingThickness = Clamp(math.floor(tonumber(value) or 15), 1, 99)
  Refresh()
end

local function getResourceRingThickness()
  local _, cdb = GetDB()
  return Clamp(math.floor(tonumber(cdb.resourceRingThickness) or 15), 1, 99)
end

local function setTrailCustomColor(r, g, b)
  local _, cdb = GetDB()
  cdb.trailCustomColor = cdb.trailCustomColor or { r = 1, g = 1, b = 1 }
  cdb.trailCustomColor.r, cdb.trailCustomColor.g, cdb.trailCustomColor.b = r, g, b
  Refresh()
end

local function getTrailCustomColor()
  local _, cdb = GetDB()
  local color = cdb.trailCustomColor or { r = 1, g = 1, b = 1 }
  return color.r or 1, color.g or 1, color.b or 1
end

local function setTrailLayerCustomColor(key, r, g, b)
  local _, cdb = GetDB()
  cdb[key] = cdb[key] or { r = 1, g = 1, b = 1 }
  cdb[key].r, cdb[key].g, cdb[key].b = r, g, b
  Refresh()
end

local function getTrailLayerCustomColor(key)
  local _, cdb = GetDB()
  local color = cdb[key] or cdb.trailCustomColor or { r = 1, g = 1, b = 1 }
  return color.r or 1, color.g or 1, color.b or 1
end

local function setTrailNumber(key, value, min_value, max_value, fallback)
  local _, cdb = GetDB()
  cdb[key] = Clamp(math.floor(tonumber(value) or fallback), min_value, max_value)
  Refresh()
end

local function getTrailNumber(key, min_value, max_value, fallback)
  local _, cdb = GetDB()
  return Clamp(math.floor(tonumber(cdb[key]) or fallback), min_value, max_value)
end

local function setBehaviorToggle(key, value)
  local db = GetDB()
  db[key] = value
  Refresh()
end

local function getBehaviorToggle(key, fallback)
  local db = GetDB()
  if db[key] == nil then
    return fallback
  end
  return db[key]
end

local function setCharToggle(key, value)
  local _, cdb = GetDB()
  cdb[key] = value
  Refresh()
end

local function getCharToggle(key, fallback)
  local _, cdb = GetDB()
  if cdb[key] == nil then
    return fallback
  end
  return cdb[key]
end

local function setCharString(key, value)
  local _, cdb = GetDB()
  cdb[key] = value
  Refresh()
end

local function getCharString(key, fallback)
  local _, cdb = GetDB()
  return cdb[key] or fallback
end

local function set_widget_enabled(widget, enabled)
  if not widget then return end
  if widget.SetEnabled then
    widget:SetEnabled(enabled)
  elseif widget.Enable and widget.Disable then
    if enabled then widget:Enable() else widget:Disable() end
    if type(widget.SetAlpha) == "function" then
      widget:SetAlpha(enabled and 1 or 0.4)
    end
  end
  if widget.EnableMouse then
    widget:EnableMouse(enabled)
  end
  if widget.Label and type(widget.Label.SetAlpha) == "function" then
    widget.Label:SetAlpha(enabled and 1 or 0.4)
  end
end

local function openColorPicker(current_color, on_changed)
  local c = current_color or { 1, 1, 1, 1 }
  local function push_color(r, g, b, a)
    if on_changed then
      on_changed({ r or 1, g or 1, b or 1, a or 1 })
    end
  end

  if Settings and Settings.OpenColorPicker then
    Settings.OpenColorPicker({
      r = c[1] or 1,
      g = c[2] or 1,
      b = c[3] or 1,
      opacity = 1 - (c[4] or 1),
      swatchFunc = function()
        if ColorPickerFrame and ColorPickerFrame.GetColorRGB then
          local r, g, b = ColorPickerFrame:GetColorRGB()
          local a = 1 - (ColorPickerFrame.opacity or 0)
          push_color(r, g, b, a)
        else
          push_color(c[1], c[2], c[3], c[4])
        end
      end,
      opacityFunc = function()
        if ColorPickerFrame and ColorPickerFrame.GetColorRGB then
          local r, g, b = ColorPickerFrame:GetColorRGB()
          local a = 1 - (ColorPickerFrame.opacity or 0)
          push_color(r, g, b, a)
        end
      end,
      cancelFunc = function()
        push_color(c[1], c[2], c[3], c[4])
      end,
    })
    return
  end

  if not ColorPickerFrame and LoadAddOn then
    LoadAddOn("Blizzard_ColorPicker")
  end
  local picker = ColorPickerFrame
  if not picker then
    return
  end

  if picker.SetupColorPickerAndShow then
    picker:SetupColorPickerAndShow({
      r = c[1] or 1,
      g = c[2] or 1,
      b = c[3] or 1,
      opacity = 1 - (c[4] or 1),
      swatchFunc = function()
        local r, g, b = picker:GetColorRGB()
        local a = 1 - (picker.opacity or 0)
        push_color(r, g, b, a)
      end,
      opacityFunc = function()
        local r, g, b = picker:GetColorRGB()
        local a = 1 - (picker.opacity or 0)
        push_color(r, g, b, a)
      end,
      cancelFunc = function()
        push_color(c[1], c[2], c[3], c[4])
      end,
      hasOpacity = true,
    })
    return
  end

  if not picker.SetColorRGB then
    return
  end
  picker.hasOpacity = true
  picker.opacity = 1 - (c[4] or 1)
  picker.func = function()
    local r, g, b = picker:GetColorRGB()
    local a = 1 - (picker.opacity or 0)
    push_color(r, g, b, a)
  end
  picker.opacityFunc = picker.func
  picker.cancelFunc = function()
    push_color(c[1], c[2], c[3], c[4])
  end
  picker:SetColorRGB(c[1] or 1, c[2] or 1, c[3] or 1)
  picker:Hide()
  picker:Show()
end

local function createColorSwatch(parent, label_text, getter, setter)
  local swatch = CreateFrame("Button", nil, parent)
  swatch:SetSize(26, 18)
  swatch:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
  swatch:RegisterForClicks("LeftButtonUp")
  swatch:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
  swatch:GetHighlightTexture():SetBlendMode("ADD")

  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
  label:SetText(label_text)

  local function refresh_color()
    local r, g, b = getter()
    local texture = swatch:GetNormalTexture()
    if texture then
      texture:SetVertexColor(r or 1, g or 1, b or 1)
    end
  end

  swatch:SetScript("OnClick", function()
    local r, g, b = getter()
    openColorPicker({ r, g, b, 1 }, function(color)
      setter(color[1], color[2], color[3])
      refresh_color()
    end)
  end)

  swatch.SetEnabled = function(self, enabled)
    self:EnableMouse(enabled)
    self:SetAlpha(enabled and 1 or 0.4)
    label:SetAlpha(enabled and 1 or 0.4)
  end
  swatch.Refresh = refresh_color
  swatch.Label = label
  refresh_color()
  return swatch
end

local function createChoiceDropdown(parent, width, choices, current_value, on_select)
  local function find_choice_text(entries, value)
    for _, entry in ipairs(entries or {}) do
      if entry.items then
        local match = find_choice_text(entry.items, value)
        if match then
          return match
        end
      elseif entry.value == value then
        return entry.text
      end
    end
    return nil
  end

  local function get_text(value)
    return find_choice_text(choices, value) or tostring(value or "")
  end

  local selected = current_value
  local frame = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(frame, width)
  UIDropDownMenu_SetText(frame, get_text(selected))
  UIDropDownMenu_Initialize(frame, function(_, level)
    local function add_legacy_choice(choice)
      local info = UIDropDownMenu_CreateInfo()
      info.text = choice.text
      info.checked = (choice.value == selected)
      info.func = function()
        selected = choice.value
        UIDropDownMenu_SetText(frame, choice.text)
        if on_select then
          on_select(choice.value)
        end
      end
      UIDropDownMenu_AddButton(info, level)
    end

    for _, entry in ipairs(choices or {}) do
      if entry.items then
        local title_info = UIDropDownMenu_CreateInfo()
        title_info.text = entry.text
        title_info.isTitle = true
        title_info.notCheckable = true
        UIDropDownMenu_AddButton(title_info, level)
        for _, item in ipairs(entry.items or {}) do
          add_legacy_choice(item)
        end
      else
        add_legacy_choice(entry)
      end
    end
  end)
  frame.SetValue = function(self, value)
    selected = value
    UIDropDownMenu_SetText(self, get_text(value))
  end
  frame.SetEnabled = function(self, enabled)
    if enabled then
      UIDropDownMenu_EnableDropDown(self)
    else
      UIDropDownMenu_DisableDropDown(self)
    end
    self:SetAlpha(enabled and 1 or 0.4)
  end
  return frame
end

local function createSection(parent, label, x, y, width)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  frame:SetWidth(width)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.05, 0.05, 0.07, 0.90)
  frame:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.90)

  frame.header = frame:CreateTexture(nil, "ARTWORK")
  frame.header:SetColorTexture(1, 1, 1, 0.04)
  frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
  frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.header:SetHeight(24)

  frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  frame.title:SetText(label)

  frame.pad = 12
  frame.innerY = -36
  return frame
end

local function finishSection(frame, extra_bottom)
  local padding = extra_bottom or 12
  frame:SetHeight(math.abs(frame.innerY) + padding)
  return frame:GetHeight()
end

local function addSectionNote(frame, text, x, y, width)
  local note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", frame, "TOPLEFT", x or frame.pad, y or frame.innerY)
  note:SetJustifyH("LEFT")
  note:SetSpacing(2)
  note:SetText(text)
  if width then
    note:SetWidth(width)
  end
  return note
end

local function registerPanel(panel)
  local launcher = ns.GetSharedLauncher and ns.GetSharedLauncher()
  if not shared_settings_registered and type(launcher) == "table" and type(launcher.RegisterSettingsPage) == "function" then
    local ok = pcall(launcher.RegisterSettingsPage, launcher, {
      id = addonName,
      addon_name = addonName,
      name = panel.name,
      get_panel = function()
        return ns.optionsPanel or panel
      end,
      on_registered = function(category)
        ns.optionsCategory = category
        ns.optionsCategoryID = (type(category) == "table" and ((type(category.GetID) == "function" and category:GetID()) or category.ID)) or panel.name
        ns.optionsCategoryName = panel.name
      end,
    })
    if ok then
      shared_settings_registered = true
      ns.optionsCategoryName = panel.name
      return ns.optionsCategory or panel
    end
  end

  if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.optionsCategory = category
    ns.optionsCategoryID = category.ID
    ns.optionsCategoryName = panel.name
    return category
  end
  InterfaceOptions_AddCategory(panel)
  ns.optionsCategory = panel
  ns.optionsCategoryID = panel.name
  ns.optionsCategoryName = panel.name
  return panel
end

local function buildBehaviorLayoutSections(content, cursor_y, left_x, right_x, left_width, right_width, section_gap, panel, state)
  local behaviorSection = createSection(content, T("Behavior"), left_x, cursor_y, left_width)
  local layoutSection = createSection(content, T("Ring Layout"), right_x, cursor_y, right_width)

  local showRing = createCheck(behaviorSection, T("Show ring"), true, function(value)
    if state.updating then return end
    setBehaviorToggle("visible", value)
    panel:RefreshControls()
  end)
  showRing:SetPoint("TOPLEFT", behaviorSection, "TOPLEFT", behaviorSection.pad, behaviorSection.innerY)
  behaviorSection.innerY = behaviorSection.innerY - 28

  local rightClickHide = createCheck(behaviorSection, T("Hide on right-click hold"), true, function(value)
    if state.updating then return end
    setBehaviorToggle("hideOnRightClick", value)
    panel:RefreshControls()
  end)
  rightClickHide:SetPoint("TOPLEFT", behaviorSection, "TOPLEFT", behaviorSection.pad, behaviorSection.innerY)
  behaviorSection.innerY = behaviorSection.innerY - 28

  local helpOnLogin = createCheck(behaviorSection, T("Show help message on login"), false, function(value)
    if state.updating then return end
    setBehaviorToggle("showHelpOnLogin", value)
    panel:RefreshControls()
  end)
  helpOnLogin:SetPoint("TOPLEFT", behaviorSection, "TOPLEFT", behaviorSection.pad, behaviorSection.innerY)
  behaviorSection.innerY = behaviorSection.innerY - 36

  local showMinimapButton = createCheck(behaviorSection, T("Show Minimap button"), true, function(value)
    if state.updating then return end
    SetLauncherButtonShown(value)
    panel:RefreshControls()
  end)
  showMinimapButton:SetPoint("TOPLEFT", behaviorSection, "TOPLEFT", behaviorSection.pad, behaviorSection.innerY)
  behaviorSection.innerY = behaviorSection.innerY - 36

  local behaviorNote = addSectionNote(
    behaviorSection,
    T("These settings control when the ring is shown, how it reacts to right-click hold behavior, and whether Cursor Ring appears in the shared minimap launcher stack."),
    behaviorSection.pad,
    behaviorSection.innerY,
    left_width - (behaviorSection.pad * 2)
  )
  behaviorSection.innerY = behaviorSection.innerY - ((behaviorNote:GetStringHeight() or 18) + 10)

  local sizeSlider = createSlider(layoutSection, T("Size"), 1, 100, 1, getRingRadiusPercent(), function(value)
    if state.updating then return end
    setRingRadiusPercent(value)
    panel:RefreshControls()
  end, "1", "100")
  sizeSlider:SetPoint("TOPLEFT", layoutSection, "TOPLEFT", layoutSection.pad - 8, layoutSection.innerY - 4)
  layoutSection.innerY = layoutSection.innerY - 68

  local thicknessSlider = createSlider(layoutSection, T("Main ring thickness"), 1, 100, 1, getRingThickness(), function(value)
    if state.updating then return end
    setRingThickness(value)
    panel:RefreshControls()
  end, T("Thin"), T("Solid"))
  thicknessSlider:SetPoint("TOPLEFT", layoutSection, "TOPLEFT", layoutSection.pad - 8, layoutSection.innerY - 4)
  layoutSection.innerY = layoutSection.innerY - 68

  local ringMarginSlider = createSlider(layoutSection, T("Ring margin"), 0, 80, 1, getRingMargin(), function(value)
    if state.updating then return end
    setRingMargin(value)
    panel:RefreshControls()
  end, "0", "80")
  ringMarginSlider:SetPoint("TOPLEFT", layoutSection, "TOPLEFT", layoutSection.pad - 8, layoutSection.innerY - 4)
  layoutSection.innerY = layoutSection.innerY - 68

  local offsetXSlider = createSlider(layoutSection, T("Horizontal offset"), -100, 100, 1, getOffsetX(), function(value)
    if state.updating then return end
    setOffsetX(value)
    panel:RefreshControls()
  end, "-100", "100")
  offsetXSlider:SetPoint("TOPLEFT", layoutSection, "TOPLEFT", layoutSection.pad - 8, layoutSection.innerY - 4)
  layoutSection.innerY = layoutSection.innerY - 68

  local offsetYSlider = createSlider(layoutSection, T("Vertical offset"), -100, 100, 1, getOffsetY(), function(value)
    if state.updating then return end
    setOffsetY(value)
    panel:RefreshControls()
  end, "-100", "100")
  offsetYSlider:SetPoint("TOPLEFT", layoutSection, "TOPLEFT", layoutSection.pad - 8, layoutSection.innerY - 4)
  layoutSection.innerY = layoutSection.innerY - 68

  local row_height = math.max(finishSection(behaviorSection), finishSection(layoutSection))
  behaviorSection:SetHeight(row_height)
  layoutSection:SetHeight(row_height)

  local controls = {
    showRing = showRing,
    rightClickHide = rightClickHide,
    helpOnLogin = helpOnLogin,
    showMinimapButton = showMinimapButton,
    sizeSlider = sizeSlider,
    thicknessSlider = thicknessSlider,
    ringMarginSlider = ringMarginSlider,
    offsetXSlider = offsetXSlider,
    offsetYSlider = offsetYSlider,
  }

  function controls:Refresh(db)
    self.showRing:SetChecked(db.visible ~= false)
    self.rightClickHide:SetChecked(db.hideOnRightClick ~= false)
    self.helpOnLogin:SetChecked(db.showHelpOnLogin == true)
    self.showMinimapButton:SetChecked(IsLauncherButtonShown())
    self.sizeSlider:SetValue(getRingRadiusPercent())
    self.thicknessSlider:SetValue(getRingThickness())
    self.ringMarginSlider:SetValue(getRingMargin())
    self.offsetXSlider:SetValue(getOffsetX())
    self.offsetYSlider:SetValue(getOffsetY())
  end

  return row_height, controls
end

local function buildColorSection(content, cursor_y, full_width, left_x, wide_column_x, wide_dropdown_width, panel, state)
  local colorSection = createSection(content, T("Color & Transparency"), left_x, cursor_y, full_width)

  local colorModeLabel = colorSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  colorModeLabel:SetPoint("TOPLEFT", colorSection, "TOPLEFT", colorSection.pad, colorSection.innerY)
  colorModeLabel:SetText(T("Color mode"))
  local colorModeDropdown = createChoiceDropdown(colorSection, wide_dropdown_width, COLOR_MODE_CHOICES, getColorMode(), function(value)
    if state.updating then return end
    setColorMode(value)
    panel:RefreshControls()
  end)
  colorModeDropdown:SetPoint("TOPLEFT", colorModeLabel, "BOTTOMLEFT", 0, -4)
  colorModeDropdown.Label = colorModeLabel

  local forceClassLabel = colorSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  forceClassLabel:SetPoint("TOPLEFT", colorSection, "TOPLEFT", wide_column_x, colorSection.innerY)
  forceClassLabel:SetText(T("Force class color"))
  local forceClassDropdown = createChoiceDropdown(colorSection, wide_dropdown_width, FORCE_CLASS_CHOICES, getForcedClass(), function(value)
    if state.updating then return end
    setForcedClass(value)
    panel:RefreshControls()
  end)
  forceClassDropdown:SetPoint("TOPLEFT", forceClassLabel, "BOTTOMLEFT", 0, -4)
  forceClassDropdown.Label = forceClassLabel
  colorSection.innerY = colorSection.innerY - 64

  local gradient1Swatch = createColorSwatch(colorSection, T("Gradient color 1"), getGradientColor1, setGradientColor1)
  gradient1Swatch:SetPoint("TOPLEFT", colorSection, "TOPLEFT", colorSection.pad, colorSection.innerY)

  local customSwatch = createColorSwatch(colorSection, T("Custom color"), getCustomColor, setCustomColor)
  customSwatch:SetPoint("TOPLEFT", colorSection, "TOPLEFT", wide_column_x, colorSection.innerY)
  colorSection.innerY = colorSection.innerY - 34

  local gradient2Swatch = createColorSwatch(colorSection, T("Gradient color 2"), getGradientColor2, setGradientColor2)
  gradient2Swatch:SetPoint("TOPLEFT", colorSection, "TOPLEFT", colorSection.pad, colorSection.innerY)
  colorSection.innerY = colorSection.innerY - 34

  local gradientNote = addSectionNote(
    colorSection,
    T("Force class color overrides the mode until it is set back to None. Gradient controls only apply while Gradient mode is active."),
    colorSection.pad,
    colorSection.innerY,
    full_width - (colorSection.pad * 2)
  )
  colorSection.innerY = colorSection.innerY - ((gradientNote:GetStringHeight() or 18) + 10)

  local gradientAngleSlider = createSlider(colorSection, T("Gradient angle"), 0, 359, 1, getGradientAngle(), function(value)
    if state.updating then return end
    setGradientAngle(value)
    panel:RefreshControls()
  end, "0", "359")
  gradientAngleSlider:SetPoint("TOPLEFT", colorSection, "TOPLEFT", colorSection.pad - 8, colorSection.innerY - 4)

  local inCombatAlphaSlider = createSlider(colorSection, T("In-combat alpha"), 0, 100, 1, getInCombatAlphaPercent(), function(value)
    if state.updating then return end
    setInCombatAlphaPercent(value)
    panel:RefreshControls()
  end, "0", "100")
  inCombatAlphaSlider:SetPoint("TOPLEFT", colorSection, "TOPLEFT", wide_column_x - 8, colorSection.innerY - 4)
  colorSection.innerY = colorSection.innerY - 68

  local outCombatAlphaSlider = createSlider(colorSection, T("Out-of-combat alpha"), 0, 100, 1, getOutCombatAlphaPercent(), function(value)
    if state.updating then return end
    setOutCombatAlphaPercent(value)
    panel:RefreshControls()
  end, "0", "100")
  outCombatAlphaSlider:SetPoint("TOPLEFT", colorSection, "TOPLEFT", wide_column_x - 8, colorSection.innerY - 4)
  colorSection.innerY = colorSection.innerY - 78

  local controls = {
    colorModeDropdown = colorModeDropdown,
    forceClassDropdown = forceClassDropdown,
    customSwatch = customSwatch,
    gradient1Swatch = gradient1Swatch,
    gradient2Swatch = gradient2Swatch,
    gradientAngleSlider = gradientAngleSlider,
    inCombatAlphaSlider = inCombatAlphaSlider,
    outCombatAlphaSlider = outCombatAlphaSlider,
  }

  function controls:Refresh(db)
    self.colorModeDropdown:SetValue(getColorMode())
    self.forceClassDropdown:SetValue(getForcedClass())
    self.customSwatch:Refresh()
    self.gradient1Swatch:Refresh()
    self.gradient2Swatch:Refresh()
    self.gradientAngleSlider:SetValue(getGradientAngle())
    self.inCombatAlphaSlider:SetValue(getInCombatAlphaPercent())
    self.outCombatAlphaSlider:SetValue(getOutCombatAlphaPercent())

    local gradient_enabled = db.colorMode == "gradient"
    set_widget_enabled(self.gradient1Swatch, gradient_enabled)
    set_widget_enabled(self.gradient2Swatch, gradient_enabled)
    set_widget_enabled(self.gradientAngleSlider, gradient_enabled)
  end

  return finishSection(colorSection), controls
end

local function buildRingsSection(content, cursor_y, full_width, left_x, wide_column_x, wide_dropdown_width, panel, state)
  local ringsSection = createSection(content, T("GCD, Cast & Resource Rings"), left_x, cursor_y, full_width)

  local gcdEnabled = createCheck(ringsSection, T("Enable GCD swipe"), true, function(value)
    if state.updating then return end
    setCharToggle("gcdEnabled", value)
    panel:RefreshControls()
  end)
  gcdEnabled:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", ringsSection.pad, ringsSection.innerY)

  local castRingEnabled = createCheck(ringsSection, T("Enable cast ring"), false, function(value)
    if state.updating then return end
    setCharToggle("castRingEnabled", value)
    panel:RefreshControls()
  end)
  castRingEnabled:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", wide_column_x, ringsSection.innerY)
  ringsSection.innerY = ringsSection.innerY - 30

  local gcdStyleLabel = ringsSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  gcdStyleLabel:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", ringsSection.pad, ringsSection.innerY)
  gcdStyleLabel:SetText(T("GCD swipe style"))
  local gcdStyleDropdown = createChoiceDropdown(ringsSection, wide_dropdown_width, GCD_STYLE_CHOICES, getCharString("gcdStyle", "simple"), function(value)
    if state.updating then return end
    setCharString("gcdStyle", value)
    panel:RefreshControls()
  end)
  gcdStyleDropdown:SetPoint("TOPLEFT", gcdStyleLabel, "BOTTOMLEFT", 0, -4)
  gcdStyleDropdown.Label = gcdStyleLabel

  local castColorSwatch = createColorSwatch(ringsSection, T("Cast ring color"), getCastRingColor, setCastRingColor)
  castColorSwatch:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", wide_column_x, ringsSection.innerY - 24)
  ringsSection.innerY = ringsSection.innerY - 64

  local castThicknessSlider = createSlider(ringsSection, T("Cast ring thickness"), 1, 99, 1, getCastRingThickness(), function(value)
    if state.updating then return end
    setCastRingThickness(value)
    panel:RefreshControls()
  end, T("Thin"), T("Solid"))
  castThicknessSlider:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", wide_column_x - 8, ringsSection.innerY - 4)

  local gcdDimSlider = createSlider(ringsSection, T("Background ring hide during GCD"), 0, 100, 1, getGCDDimPercent(), function(value)
    if state.updating then return end
    setGCDDimPercent(value)
    panel:RefreshControls()
  end, "0", "100")
  gcdDimSlider:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", ringsSection.pad - 8, ringsSection.innerY - 4)
  ringsSection.innerY = ringsSection.innerY - 68

  local resourceRingEnabled = createCheck(ringsSection, T("Enable secondary resource ring"), false, function(value)
    if state.updating then return end
    setCharToggle("resourceRingEnabled", value)
    panel:RefreshControls()
  end)
  resourceRingEnabled:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", wide_column_x, ringsSection.innerY)

  local resourceThicknessSlider = createSlider(ringsSection, T("Secondary resource ring thickness"), 1, 99, 1, getResourceRingThickness(), function(value)
    if state.updating then return end
    setResourceRingThickness(value)
    panel:RefreshControls()
  end, T("Thin"), T("Solid"))
  resourceThicknessSlider:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", wide_column_x - 8, ringsSection.innerY - 30)
  ringsSection.innerY = ringsSection.innerY - 98

  local gcdReverse = createCheck(ringsSection, T("Reverse GCD swipe (fill ring)"), false, function(value)
    if state.updating then return end
    setCharToggle("gcdReverse", value)
    panel:RefreshControls()
  end)
  gcdReverse:SetPoint("TOPLEFT", ringsSection, "TOPLEFT", ringsSection.pad, ringsSection.innerY)
  ringsSection.innerY = ringsSection.innerY - 34

  local ringsNote = addSectionNote(
    ringsSection,
    T("The GCD swipe uses Blizzard cooldown timing. Cast and resource rings sit outside the main ring and respect the nested ring priority layout."),
    ringsSection.pad,
    ringsSection.innerY,
    full_width - (ringsSection.pad * 2)
  )
  ringsSection.innerY = ringsSection.innerY - ((ringsNote:GetStringHeight() or 18) + 10)

  local controls = {
    gcdEnabled = gcdEnabled,
    gcdStyleDropdown = gcdStyleDropdown,
    gcdDimSlider = gcdDimSlider,
    gcdReverse = gcdReverse,
    castRingEnabled = castRingEnabled,
    castThicknessSlider = castThicknessSlider,
    castColorSwatch = castColorSwatch,
    resourceRingEnabled = resourceRingEnabled,
    resourceThicknessSlider = resourceThicknessSlider,
  }

  function controls:Refresh(cdb)
    self.gcdEnabled:SetChecked(cdb.gcdEnabled ~= false)
    self.gcdStyleDropdown:SetValue(getCharString("gcdStyle", "simple"))
    self.gcdDimSlider:SetValue(getGCDDimPercent())
    self.gcdReverse:SetChecked(cdb.gcdReverse == true)
    self.castRingEnabled:SetChecked(cdb.castRingEnabled == true)
    self.castThicknessSlider:SetValue(getCastRingThickness())
    self.castColorSwatch:Refresh()
    self.resourceRingEnabled:SetChecked(cdb.resourceRingEnabled == true)
    self.resourceThicknessSlider:SetValue(getResourceRingThickness())

    local gcd_enabled = cdb.gcdEnabled ~= false
    set_widget_enabled(self.gcdStyleDropdown, gcd_enabled)
    set_widget_enabled(self.gcdDimSlider, gcd_enabled)
    set_widget_enabled(self.gcdReverse, gcd_enabled)

    local cast_enabled = cdb.castRingEnabled == true
    local resource_enabled = cdb.resourceRingEnabled == true
    set_widget_enabled(self.castColorSwatch, cast_enabled)
    set_widget_enabled(self.castThicknessSlider, cast_enabled)
    set_widget_enabled(self.resourceThicknessSlider, resource_enabled)
  end

  return finishSection(ringsSection), controls
end

local function buildTrailLayerControls(parent, anchor_x, anchor_y, dropdown_width, panel, state, spec)
  local enabledCheck = createCheck(parent, T(spec.enabled_label), false, function(value)
    if state.updating then return end
    setCharToggle(spec.enabled_key, value)
    panel:RefreshControls()
  end)
  enabledCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", anchor_x, anchor_y)
  anchor_y = anchor_y - 30

  local colorModeLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  colorModeLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", anchor_x, anchor_y)
  colorModeLabel:SetText(T(spec.color_mode_label))
  local colorModeDropdown = createChoiceDropdown(parent, dropdown_width, TRAIL_COLOR_MODE_CHOICES, getCharString(spec.color_mode_key, "ring"), function(value)
    if state.updating then return end
    setCharString(spec.color_mode_key, value)
    panel:RefreshControls()
  end)
  colorModeDropdown:SetPoint("TOPLEFT", colorModeLabel, "BOTTOMLEFT", 0, -4)
  colorModeDropdown.Label = colorModeLabel
  anchor_y = anchor_y - 64

  local customSwatch = createColorSwatch(parent, T(spec.custom_color_label), function()
    return getTrailLayerCustomColor(spec.custom_color_key)
  end, function(r, g, b)
    setTrailLayerCustomColor(spec.custom_color_key, r, g, b)
  end)
  customSwatch:SetPoint("TOPLEFT", parent, "TOPLEFT", anchor_x, anchor_y + 2)
  anchor_y = anchor_y - 42

  return anchor_y, {
    enabledCheck = enabledCheck,
    colorModeDropdown = colorModeDropdown,
    customSwatch = customSwatch,
    enabled_key = spec.enabled_key,
    color_mode_key = spec.color_mode_key,
  }
end

local function makeTrailToggleCallback(state, panel, key)
  return function(value)
    if state.updating then return end
    setCharToggle(key, value)
    panel:RefreshControls()
  end
end

local function makeTrailStringCallback(state, panel, key)
  return function(value)
    if state.updating then return end
    setCharString(key, value)
    panel:RefreshControls()
  end
end

local function makeTrailNumberCallback(state, panel, key, min_value, max_value, fallback)
  return function(value)
    if state.updating then return end
    setTrailNumber(key, value, min_value, max_value, fallback)
    panel:RefreshControls()
  end
end

local function buildTrailSection(content, cursor_y, full_width, left_x, wide_column_x, wide_dropdown_width, panel, state)
  local trailSection = createSection(content, T("Cursor Trails"), left_x, cursor_y, full_width)
  local trail_left_y = trailSection.innerY
  local trail_right_y = trailSection.innerY

  local trailEnabled = createCheck(trailSection, T("Enable cursor trails"), false, makeTrailToggleCallback(state, panel, "trailEnabled"))
  trailEnabled:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad, trail_left_y)
  trail_left_y = trail_left_y - 36

  local trailPresetLabel = trailSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  trailPresetLabel:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x, trail_right_y)
  trailPresetLabel:SetText(T("Trail preset"))
  local trailPresetDropdown = createChoiceDropdown(trailSection, wide_dropdown_width, TRAIL_ASSET_CHOICES, getCharString("trailAsset", "metalglow"), makeTrailStringCallback(state, panel, "trailAsset"))
  trailPresetDropdown:SetPoint("TOPLEFT", trailPresetLabel, "BOTTOMLEFT", 0, -4)
  trailPresetDropdown.Label = trailPresetLabel
  trail_right_y = trail_right_y - 64

  local trailBlendModeLabel = trailSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  trailBlendModeLabel:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x, trail_right_y)
  trailBlendModeLabel:SetText(T("Trail blend mode"))
  local trailBlendModeDropdown = createChoiceDropdown(trailSection, wide_dropdown_width, TRAIL_BLEND_MODE_CHOICES, getCharString("trailBlendMode", "ADD"), makeTrailStringCallback(state, panel, "trailBlendMode"))
  trailBlendModeDropdown:SetPoint("TOPLEFT", trailBlendModeLabel, "BOTTOMLEFT", 0, -4)
  trailBlendModeDropdown.Label = trailBlendModeLabel
  trail_right_y = trail_right_y - 64

  local glowControls
  trail_left_y, glowControls = buildTrailLayerControls(trailSection, trailSection.pad, trail_left_y, wide_dropdown_width, panel, state, {
    enabled_label = "Enable glow layer",
    enabled_key = "trailGlowEnabled",
    color_mode_label = "Glow color mode",
    color_mode_key = "trailGlowColorMode",
    custom_color_label = "Glow custom color",
    custom_color_key = "trailGlowCustomColor",
  })

  local ribbonControls
  trail_left_y, ribbonControls = buildTrailLayerControls(trailSection, trailSection.pad, trail_left_y, wide_dropdown_width, panel, state, {
    enabled_label = "Enable ribbon layer",
    enabled_key = "trailRibbonEnabled",
    color_mode_label = "Ribbon color mode",
    color_mode_key = "trailRibbonColorMode",
    custom_color_label = "Ribbon custom color",
    custom_color_key = "trailRibbonCustomColor",
  })

  local particleControls
  trail_right_y, particleControls = buildTrailLayerControls(trailSection, wide_column_x, trail_right_y, wide_dropdown_width, panel, state, {
    enabled_label = "Enable particle layer",
    enabled_key = "trailParticleEnabled",
    color_mode_label = "Particle color mode",
    color_mode_key = "trailParticleColorMode",
    custom_color_label = "Particle custom color",
    custom_color_key = "trailParticleCustomColor",
  })

  trailSection.innerY = math.min(trail_left_y, trail_right_y)
  local trailLayerNote = addSectionNote(
    trailSection,
    T("Glow, ribbon, and particle layers can be enabled together. Each layer can either match the ring color or use its own custom color."),
    trailSection.pad,
    trailSection.innerY,
    full_width - (trailSection.pad * 2)
  )
  trailSection.innerY = trailSection.innerY - ((trailLayerNote:GetStringHeight() or 18) + 10)
  trail_left_y = trailSection.innerY
  trail_right_y = trailSection.innerY

  local trailAlphaSlider = createSlider(trailSection, T("Trail alpha"), 0, 100, 1, getTrailNumber("trailAlpha", 0, 100, 60), makeTrailNumberCallback(state, panel, "trailAlpha", 0, 100, 60), "0", "100")
  trailAlphaSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  local trailSizeSlider = createSlider(trailSection, T("Trail size"), 4, 96, 1, getTrailNumber("trailSize", 4, 96, 24), makeTrailNumberCallback(state, panel, "trailSize", 4, 96, 24), "4", "96")
  trailSizeSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x - 8, trail_right_y - 4)
  trail_right_y = trail_right_y - 68

  local trailLengthSlider = createSlider(trailSection, T("Trail length"), 60, 1400, 20, getTrailNumber("trailLength", 60, 1400, 320), makeTrailNumberCallback(state, panel, "trailLength", 60, 1400, 320), "60", "1400")
  trailLengthSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  local trailSegmentsSlider = createSlider(trailSection, T("Trail segments"), 2, 24, 1, getTrailNumber("trailSegments", 2, 24, 8), makeTrailNumberCallback(state, panel, "trailSegments", 2, 24, 8), "2", "24")
  trailSegmentsSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x - 8, trail_right_y - 4)
  trail_right_y = trail_right_y - 68

  local trailSampleRateSlider = createSlider(trailSection, T("Trail sample rate"), 10, 90, 1, getTrailNumber("trailSampleRate", 10, 90, 36), makeTrailNumberCallback(state, panel, "trailSampleRate", 10, 90, 36), "10", "90")
  trailSampleRateSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  local trailMinDistanceSlider = createSlider(trailSection, T("Trail movement threshold"), 0, 40, 1, getTrailNumber("trailMinDistance", 0, 40, 6), makeTrailNumberCallback(state, panel, "trailMinDistance", 0, 40, 6), "0", "40")
  trailMinDistanceSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x - 8, trail_right_y - 4)
  trail_right_y = trail_right_y - 68

  local trailRibbonWidthSlider = createSlider(trailSection, T("Ribbon width"), 2, 72, 1, getTrailNumber("trailRibbonWidth", 2, 72, 18), makeTrailNumberCallback(state, panel, "trailRibbonWidth", 2, 72, 18), "2", "72")
  trailRibbonWidthSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  local trailHeadScaleSlider = createSlider(trailSection, T("Trail head scale"), 50, 220, 1, getTrailNumber("trailHeadScale", 50, 220, 120), makeTrailNumberCallback(state, panel, "trailHeadScale", 50, 220, 120), "50", "220")
  trailHeadScaleSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x - 8, trail_right_y - 4)
  trail_right_y = trail_right_y - 68

  local trailParticleCountSlider = createSlider(trailSection, T("Particle pool"), 4, 64, 1, getTrailNumber("trailParticleCount", 4, 64, 20), makeTrailNumberCallback(state, panel, "trailParticleCount", 4, 64, 20), "4", "64")
  trailParticleCountSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  local trailParticleBurstSlider = createSlider(trailSection, T("Particle burst"), 1, 6, 1, getTrailNumber("trailParticleBurst", 1, 6, 2), makeTrailNumberCallback(state, panel, "trailParticleBurst", 1, 6, 2), "1", "6")
  trailParticleBurstSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x - 8, trail_right_y - 4)
  trail_right_y = trail_right_y - 68

  local trailParticleSpreadSlider = createSlider(trailSection, T("Particle spread"), 0, 80, 1, getTrailNumber("trailParticleSpread", 0, 80, 18), makeTrailNumberCallback(state, panel, "trailParticleSpread", 0, 80, 18), "0", "80")
  trailParticleSpreadSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  local trailParticleSpeedSlider = createSlider(trailSection, T("Particle speed"), 0, 260, 1, getTrailNumber("trailParticleSpeed", 0, 260, 80), makeTrailNumberCallback(state, panel, "trailParticleSpeed", 0, 260, 80), "0", "260")
  trailParticleSpeedSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", wide_column_x - 8, trail_right_y - 4)
  trail_right_y = trail_right_y - 68

  local trailParticleSizeSlider = createSlider(trailSection, T("Particle size"), 2, 48, 1, getTrailNumber("trailParticleSize", 2, 48, 12), makeTrailNumberCallback(state, panel, "trailParticleSize", 2, 48, 12), "2", "48")
  trailParticleSizeSlider:SetPoint("TOPLEFT", trailSection, "TOPLEFT", trailSection.pad - 8, trail_left_y - 4)
  trail_left_y = trail_left_y - 68

  trailSection.innerY = math.min(trail_left_y, trail_right_y)

  local controls = {
    trailEnabled = trailEnabled,
    trailPresetDropdown = trailPresetDropdown,
    trailBlendModeDropdown = trailBlendModeDropdown,
    glowControls = glowControls,
    ribbonControls = ribbonControls,
    particleControls = particleControls,
    trailAlphaSlider = trailAlphaSlider,
    trailSizeSlider = trailSizeSlider,
    trailLengthSlider = trailLengthSlider,
    trailSegmentsSlider = trailSegmentsSlider,
    trailSampleRateSlider = trailSampleRateSlider,
    trailMinDistanceSlider = trailMinDistanceSlider,
    trailRibbonWidthSlider = trailRibbonWidthSlider,
    trailHeadScaleSlider = trailHeadScaleSlider,
    trailParticleCountSlider = trailParticleCountSlider,
    trailParticleBurstSlider = trailParticleBurstSlider,
    trailParticleSpreadSlider = trailParticleSpreadSlider,
    trailParticleSpeedSlider = trailParticleSpeedSlider,
    trailParticleSizeSlider = trailParticleSizeSlider,
  }

  function controls:Refresh(cdb)
    self.trailEnabled:SetChecked(cdb.trailEnabled == true)
    self.trailPresetDropdown:SetValue(getCharString("trailAsset", "metalglow"))
    self.trailBlendModeDropdown:SetValue(getCharString("trailBlendMode", "ADD"))

    self.glowControls.enabledCheck:SetChecked(cdb.trailGlowEnabled == true)
    self.glowControls.colorModeDropdown:SetValue(getCharString("trailGlowColorMode", "ring"))
    self.glowControls.customSwatch:Refresh()

    self.ribbonControls.enabledCheck:SetChecked(cdb.trailRibbonEnabled == true)
    self.ribbonControls.colorModeDropdown:SetValue(getCharString("trailRibbonColorMode", "ring"))
    self.ribbonControls.customSwatch:Refresh()

    self.particleControls.enabledCheck:SetChecked(cdb.trailParticleEnabled == true)
    self.particleControls.colorModeDropdown:SetValue(getCharString("trailParticleColorMode", "ring"))
    self.particleControls.customSwatch:Refresh()

    self.trailAlphaSlider:SetValue(getTrailNumber("trailAlpha", 0, 100, 60))
    self.trailSizeSlider:SetValue(getTrailNumber("trailSize", 4, 96, 24))
    self.trailLengthSlider:SetValue(getTrailNumber("trailLength", 60, 1400, 320))
    self.trailSegmentsSlider:SetValue(getTrailNumber("trailSegments", 2, 24, 8))
    self.trailSampleRateSlider:SetValue(getTrailNumber("trailSampleRate", 10, 90, 36))
    self.trailMinDistanceSlider:SetValue(getTrailNumber("trailMinDistance", 0, 40, 6))
    self.trailRibbonWidthSlider:SetValue(getTrailNumber("trailRibbonWidth", 2, 72, 18))
    self.trailHeadScaleSlider:SetValue(getTrailNumber("trailHeadScale", 50, 220, 120))
    self.trailParticleCountSlider:SetValue(getTrailNumber("trailParticleCount", 4, 64, 20))
    self.trailParticleBurstSlider:SetValue(getTrailNumber("trailParticleBurst", 1, 6, 2))
    self.trailParticleSpreadSlider:SetValue(getTrailNumber("trailParticleSpread", 0, 80, 18))
    self.trailParticleSpeedSlider:SetValue(getTrailNumber("trailParticleSpeed", 0, 260, 80))
    self.trailParticleSizeSlider:SetValue(getTrailNumber("trailParticleSize", 2, 48, 12))

    local trail_enabled = cdb.trailEnabled == true
    local glow_enabled = cdb.trailGlowEnabled == true
    local ribbon_enabled = cdb.trailRibbonEnabled == true
    local particle_enabled = cdb.trailParticleEnabled == true
    local history_enabled = glow_enabled or ribbon_enabled

    set_widget_enabled(self.trailPresetDropdown, trail_enabled)
    set_widget_enabled(self.trailBlendModeDropdown, trail_enabled)

    local function refreshLayerControls(layer, enabled)
      local custom_color = getCharString(layer.color_mode_key, "ring") == "custom"
      set_widget_enabled(layer.enabledCheck, trail_enabled)
      set_widget_enabled(layer.colorModeDropdown, trail_enabled and enabled)
      set_widget_enabled(layer.customSwatch, trail_enabled and enabled and custom_color)
    end

    refreshLayerControls(self.glowControls, glow_enabled)
    refreshLayerControls(self.ribbonControls, ribbon_enabled)
    refreshLayerControls(self.particleControls, particle_enabled)

    set_widget_enabled(self.trailAlphaSlider, trail_enabled)
    set_widget_enabled(self.trailLengthSlider, trail_enabled)
    set_widget_enabled(self.trailSampleRateSlider, trail_enabled)
    set_widget_enabled(self.trailMinDistanceSlider, trail_enabled)
    set_widget_enabled(self.trailSizeSlider, trail_enabled and glow_enabled)
    set_widget_enabled(self.trailSegmentsSlider, trail_enabled and history_enabled)
    set_widget_enabled(self.trailRibbonWidthSlider, trail_enabled and ribbon_enabled)
    set_widget_enabled(self.trailHeadScaleSlider, trail_enabled and glow_enabled)
    set_widget_enabled(self.trailParticleCountSlider, trail_enabled and particle_enabled)
    set_widget_enabled(self.trailParticleBurstSlider, trail_enabled and particle_enabled)
    set_widget_enabled(self.trailParticleSpreadSlider, trail_enabled and particle_enabled)
    set_widget_enabled(self.trailParticleSpeedSlider, trail_enabled and particle_enabled)
    set_widget_enabled(self.trailParticleSizeSlider, trail_enabled and particle_enabled)
  end

  return finishSection(trailSection), controls
end

local function buildOptionsPanelContents(panel)
  if panel._contentBuilt then
    return panel
  end
  panel._contentBuilt = true

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText(T("Cursor Ring"))

  local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  desc:SetText(T("Configure the cursor ring, GCD swipe, cast ring, secondary resource ring, and optional cursor trails."))

  local resetButton = createMainActionButton(panel, T("Reset all"), function()
    CursorRingDB = CopyTable(ns.defaults)
    CursorRingCharDB = CopyTable(ns.charDefaults)
    SetLauncherButtonShown(true)
    if panel.RefreshControls then
      panel:RefreshControls()
    end
    Refresh()
  end)
  resetButton:SetSize(92, 24)
  resetButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -14)

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -8)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 16)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetSize(820, 520)
  scroll:SetScrollChild(content)
  scroll:HookScript("OnSizeChanged", function(self, width)
    if content and width and width > 0 then
      content:SetWidth(width - 2)
    end
  end)
  if initLegacyScrollFrame then
    initLegacyScrollFrame(scroll, 28)
  end

  local layout_padding = 12
  local section_gap = 3
  local content_width = 820
  local inner_width = content_width - (layout_padding * 2)
  local left_width = math.floor((inner_width - section_gap) * 0.42) - 35
  local right_width = left_width
  local left_x = layout_padding
  local right_x = left_x + left_width + section_gap
  local full_width = left_width + right_width + section_gap
  local wide_column_x = left_width + section_gap + 12
  local wide_dropdown_width = 180
  local cursor_y = -6

  local state = { updating = false }

  local behaviorLayoutHeight, behaviorLayoutControls = buildBehaviorLayoutSections(content, cursor_y, left_x, right_x, left_width, right_width, section_gap, panel, state)
  cursor_y = cursor_y - behaviorLayoutHeight - section_gap

  local colorSectionHeight, colorControls = buildColorSection(content, cursor_y, full_width, left_x, wide_column_x, wide_dropdown_width, panel, state)
  cursor_y = cursor_y - colorSectionHeight - section_gap

  local ringsSectionHeight, ringControls = buildRingsSection(content, cursor_y, full_width, left_x, wide_column_x, wide_dropdown_width, panel, state)
  cursor_y = cursor_y - ringsSectionHeight - section_gap

  local trailSectionHeight, trailControls = buildTrailSection(content, cursor_y, full_width, left_x, wide_column_x, wide_dropdown_width, panel, state)
  cursor_y = cursor_y - trailSectionHeight - section_gap

  local helpSection = createSection(content, T("Help"), left_x, cursor_y, full_width)
  local helpText = helpSection:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  helpText:SetPoint("TOPLEFT", helpSection, "TOPLEFT", helpSection.pad, helpSection.innerY)
  helpText:SetJustifyH("LEFT")
  helpText:SetSpacing(2)
  helpText:SetWidth(full_width - (helpSection.pad * 2))
  helpText:SetText(
    T("Slash commands:\n" ..
    "  /cr show        - Show the ring\n" ..
    "  /cr hide        - Hide the ring\n" ..
    "  /cr toggle      - Toggle visibility\n" ..
    "  /cr reset       - Reset to defaults\n\n" ..
    "  /cr gcd         - Toggle the GCD swipe\n" ..
    "  /cr gcdstyle    - Set GCD style (simple / blizzard)\n" ..
    "  /cr color       - Set color mode (class, highvis, custom, gradient, or class token)\n" ..
    "  /cr alpha       - Set in/out-of-combat alpha\n" ..
    "  /cr size        - Change ring size\n" ..
    "  /cr right-click - Configure hide-on-right-click behavior")
  )
  helpSection.innerY = helpSection.innerY - ((helpText:GetStringHeight() or 120) + 8)
  cursor_y = cursor_y - finishSection(helpSection) - section_gap
  content:SetHeight(math.abs(cursor_y) + 24)

  function panel:RefreshControls()
    local db, cdb = GetDB()
    state.updating = true

    if behaviorLayoutControls and behaviorLayoutControls.Refresh then
      behaviorLayoutControls:Refresh(db)
    end
    if colorControls and colorControls.Refresh then
      colorControls:Refresh(db)
    end
    if ringControls and ringControls.Refresh then
      ringControls:Refresh(cdb)
    end
    if trailControls and trailControls.Refresh then
      trailControls:Refresh(cdb)
    end

    state.updating = false
  end

  if type(ns.EnsureDevInfoModule) == "function" then
    local module = ns.EnsureDevInfoModule()
    if module and type(module.AttachButton) == "function" then
      module:AttachButton(panel, {
        point = "RIGHT",
        relative_to = resetButton,
        relative_point = "LEFT",
        x = -6,
        y = 0,
        width = 72,
        height = 24,
        text = T("Dev Info"),
        frame_level_offset = 12,
      })
    end
  end

  return panel
end

local function buildOptionsPanel()
  if ns.optionsPanel then
    return ns.optionsPanel
  end

  local panel = CreateFrame("Frame", "CursorRingOptionsPanel")
  panel.name = T("Cursor Ring")
  ns.optionsPanel = panel

  function panel:EnsureBuilt()
    return buildOptionsPanelContents(self)
  end

  panel:EnsureBuilt()

  panel:SetScript("OnShow", function(self)
    self:EnsureBuilt()
    if self.RefreshControls then
      self:RefreshControls()
    end
  end)

  ns.optionsCategory = registerPanel(panel)
  return panel
end

function ns.OpenOptions()
  local panel = buildOptionsPanel()
  local launcher = ns.GetSharedLauncher and ns.GetSharedLauncher()
  local category = ns.optionsCategory
  local category_name = ns.optionsCategoryName or (panel and panel.name) or T("Cursor Ring")

  if type(launcher) == "table" and type(launcher.OpenSettings) == "function" then
    if launcher:OpenSettings(addonName) then
      return true
    end
  end

  if Settings and Settings.OpenToCategory then
    if category and category.ID then
      Settings.OpenToCategory(category.ID)
      return true
    end
    if type(Settings.GetCategory) == "function" then
      local resolved = Settings.GetCategory(category_name)
      if resolved and resolved.ID then
        Settings.OpenToCategory(resolved.ID)
        return true
      end
    end
    Settings.OpenToCategory(category_name)
    return true
  end

  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel or category_name)
    InterfaceOptionsFrame_OpenToCategory(panel or category_name)
    return true
  end

  return false
end

buildOptionsPanel()
