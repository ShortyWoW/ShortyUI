local addon_name, ns = ...
local L = ns.L or {}
local MODULE_VERSION = 4

local function T(key)
  local value = L[key]
  if value == nil or value == "" then
    return key
  end
  return value
end

local shared = _G.KagrokSharedLauncher
if type(shared) == "table" and type(shared.__module_version) == "number" and shared.__module_version >= MODULE_VERSION then
  ns.KagrokSharedLauncher = shared
  return
end

if type(shared) ~= "table" then
  shared = {}
  _G.KagrokSharedLauncher = shared
end
ns.KagrokSharedLauncher = shared

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetCursorPosition = GetCursorPosition
local Minimap = Minimap
local UIParent = UIParent
local Settings = Settings
local C_Timer = C_Timer
local IsMouseButtonDown = IsMouseButtonDown
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local math = math
local pcall = pcall
local type = type
local table_insert = table.insert
local table_sort = table.sort

local DEFAULT_SHARED_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_BUTTON_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_MINIMAP_POSITION = 225
local MINIMAP_LDB_NAME = "KagrokSharedLauncher"
local MENU_WIDTH = 236
local MENU_MAX_HEIGHT = 420
local MENU_ROW_HEIGHT = 24
local MENU_COLUMN_WIDTH = MENU_WIDTH - 22
local MENU_SCROLL_COLUMN_WIDTH = MENU_WIDTH - 42
local MENU_COLUMN_GAP = 12
local MENU_MAX_COLUMNS = 3
local MENU_MAX_CONTENT_HEIGHT = MENU_MAX_HEIGHT - 60
local MENU_CONTENT_PADDING = 16
local SETTINGS_ROW_HEIGHT = 62
local SETTINGS_ROW_PITCH = 66
local SETTINGS_ROW_X = 12
local SETTINGS_GRAB_X = 12
local SETTINGS_GRAB_WIDTH = 12
local SETTINGS_ICON_X = 34

local function trim_text(value)
  local text = tostring(value or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function get_libstub()
  local libstub = _G.LibStub
  if type(libstub) == "table" or type(libstub) == "function" then
    return libstub
  end
  return nil
end

local function get_embedded_library(major)
  local libstub = get_libstub()
  if not libstub or type(libstub.GetLibrary) ~= "function" then
    return nil
  end
  return libstub:GetLibrary(major, true)
end

local function ensure_db()
  if type(_G.KagrokLauncherDB) ~= "table" then
    _G.KagrokLauncherDB = {}
  end
  local db = _G.KagrokLauncherDB
  db.settings = db.settings or {}
  db.settings.priority_overrides = db.settings.priority_overrides or {}
  db.settings.hidden_addons = db.settings.hidden_addons or {}
  db.settings.launcher_override_addon = trim_text(db.settings.launcher_override_addon)
  db.settings.left_click_addon = trim_text(db.settings.left_click_addon)
  db.settings.tooltip_addon = trim_text(db.settings.tooltip_addon)
  if db.settings.launcher_override_addon == "" then
    if db.settings.left_click_addon ~= "" then
      db.settings.launcher_override_addon = db.settings.left_click_addon
    elseif db.settings.tooltip_addon ~= "" then
      db.settings.launcher_override_addon = db.settings.tooltip_addon
    end
  end
  if db.settings.launcher_override_addon ~= "" then
    db.settings.left_click_addon = db.settings.launcher_override_addon
    db.settings.tooltip_addon = db.settings.launcher_override_addon
  end
  db.minimap = db.minimap or {}
  if db.minimap.minimapPos == nil then
    db.minimap.minimapPos = tonumber(db.angle) or DEFAULT_MINIMAP_POSITION
  end
  db.minimap.minimapPos = tonumber(db.minimap.minimapPos) or DEFAULT_MINIMAP_POSITION
  if db.minimap.hide == nil then
    db.minimap.hide = db.settings.hide_stack == true
  else
    db.minimap.hide = db.minimap.hide == true
  end
  db.angle = db.minimap.minimapPos
  db.settings.hide_stack = db.minimap.hide == true
  return db
end

local function get_addon_metadata(addon_key, field)
  local value = ""
  if type(GetAddOnMetadata) == "function" then
    value = tostring(GetAddOnMetadata(addon_key, field) or "")
  end
  if value == "" and C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
    value = tostring(C_AddOns.GetAddOnMetadata(addon_key, field) or "")
  end
  return trim_text(value)
end

local function safe_call(callback, ...)
  if type(callback) ~= "function" then
    return nil
  end
  local ok, result = pcall(callback, ...)
  if ok then
    return result
  end
  return nil
end

local function get_polar_angle_degrees(dy, dx)
  if type(math.atan2) == "function" then
    return math.deg(math.atan2(dy, dx))
  end
  if dx == 0 then
    if dy > 0 then
      return 90
    elseif dy < 0 then
      return 270
    end
    return 0
  end
  local angle = math.deg(math.atan(dy / dx))
  if dx < 0 then
    angle = angle + 180
  elseif dy < 0 then
    angle = angle + 360
  end
  return angle
end

local function create_backdrop(frame, bg, border)
  if not frame or not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function create_frame_with_optional_template(frame_type, name, parent, template)
  if template and template ~= "" then
    local ok, frame = pcall(CreateFrame, frame_type, name, parent, template)
    if ok and frame then
      return frame
    end
  end
  return CreateFrame(frame_type, name, parent)
end

local function get_effective_priority(entry)
  local db = ensure_db()
  local overrides = db.settings and db.settings.priority_overrides
  local override = overrides and tonumber(overrides[entry.id])
  if override then
    return override
  end
  return tonumber(entry.priority) or 0
end

local function get_launcher_override_id()
  local db = ensure_db()
  local settings = db.settings or {}
  local override_id = trim_text(settings.launcher_override_addon)
  if override_id ~= "" then
    return override_id
  end
  override_id = trim_text(settings.left_click_addon)
  if override_id ~= "" then
    return override_id
  end
  return trim_text(settings.tooltip_addon)
end

local function sort_entries(a, b)
  local ap = get_effective_priority(a)
  local bp = get_effective_priority(b)
  if ap ~= bp then
    return ap > bp
  end
  return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
end

local function normalize_entry(definition)
  local addon_key = trim_text(definition.addon_name or definition.id or addon_name)
  local id = trim_text(definition.id or addon_key)
  local name = trim_text(definition.name)
  if name == "" then
    name = get_addon_metadata(addon_key, "Title")
  end
  if name == "" then
    name = id
  end

  local priority = tonumber(definition.priority)
  if not priority then
    priority = tonumber(get_addon_metadata(addon_key, "X-KagrokLauncherPriority")) or 0
  end

  local icon = trim_text(definition.icon)
  if icon == "" then
    icon = get_addon_metadata(addon_key, "IconTexture")
  end
  if icon == "" then
    icon = DEFAULT_BUTTON_ICON
  end

  local shared_icon = trim_text(definition.shared_icon or definition.family_icon)
  if shared_icon == "" then
    shared_icon = DEFAULT_SHARED_ICON
  end

  return {
    id = id,
    addon_name = addon_key,
    name = name,
    priority = priority,
    icon = icon,
    shared_icon = shared_icon,
    is_enabled = definition.is_enabled,
    left_click = definition.left_click,
    tooltip = definition.tooltip,
    menu_items = definition.menu_items,
    shared_items = definition.shared_items,
  }
end

local function normalize_settings_entry(definition)
  local addon_key = trim_text(definition.addon_name or definition.id or addon_name)
  local id = trim_text(definition.id or addon_key)
  local name = trim_text(definition.name)
  if name == "" then
    name = get_addon_metadata(addon_key, "Title")
  end
  if name == "" then
    name = id
  end

  local priority = tonumber(definition.priority)
  if not priority then
    priority = tonumber(get_addon_metadata(addon_key, "X-KagrokLauncherPriority")) or 0
  end

  local icon = trim_text(definition.icon)
  if icon == "" then
    icon = get_addon_metadata(addon_key, "IconTexture")
  end
  if icon == "" then
    icon = DEFAULT_BUTTON_ICON
  end

  local get_panel = definition.get_panel
  if type(get_panel) ~= "function" and definition.panel then
    get_panel = function()
      return definition.panel
    end
  end

  return {
    id = id,
    addon_name = addon_key,
    name = name,
    priority = priority,
    icon = icon,
    get_panel = get_panel,
    is_enabled = definition.is_enabled,
    on_registered = definition.on_registered,
  }
end

function shared:RegisterAddon(definition)
  if type(definition) ~= "table" then
    return nil
  end
  self.registry = self.registry or {}
  local entry = normalize_entry(definition)
  self.registry[entry.id] = entry
  self:Refresh()
  return entry
end

function shared:UnregisterAddon(addon_id)
  self.registry = self.registry or {}
  self.registry[tostring(addon_id or "")] = nil
  self:Refresh()
end

function shared:RegisterSettingsPage(definition)
  if type(definition) ~= "table" then
    return nil
  end
  self.settings_registry = self.settings_registry or {}
  local entry = normalize_settings_entry(definition)
  if type(entry.get_panel) ~= "function" then
    return nil
  end
  self.settings_registry[entry.id] = entry
  self:EnsureSettingsBootstrap()
  if type(IsLoggedIn) == "function" and IsLoggedIn() then
    self:ScheduleSettingsFinalize()
  end
  return entry
end

function shared:UnregisterSettingsPage(addon_id)
  self.settings_registry = self.settings_registry or {}
  self.settings_registry[tostring(addon_id or "")] = nil
end

function shared:GetEntries(include_disabled)
  self.registry = self.registry or {}
  local db = ensure_db()
  local hidden_addons = db.settings and db.settings.hidden_addons or {}
  local entries = {}
  for _, entry in pairs(self.registry) do
    local enabled = true
    if type(entry.is_enabled) == "function" then
      enabled = safe_call(entry.is_enabled) ~= false
    end
    if hidden_addons[entry.id] == true then
      enabled = false
    end
    if include_disabled or enabled then
      table_insert(entries, entry)
    end
  end
  table_sort(entries, sort_entries)
  return entries
end

function shared:GetSettingsEntries(include_disabled)
  self.settings_registry = self.settings_registry or {}
  local entries = {}
  for _, entry in pairs(self.settings_registry) do
    local enabled = true
    if type(entry.is_enabled) == "function" then
      enabled = safe_call(entry.is_enabled) ~= false
    end
    if include_disabled or enabled then
      table_insert(entries, entry)
    end
  end
  table_sort(entries, sort_entries)
  return entries
end

function shared:GetSettingsEntry(addon_id)
  local key = trim_text(addon_id)
  if key == "" then
    return nil
  end
  self.settings_registry = self.settings_registry or {}
  return self.settings_registry[key]
end

local function sequence_equals(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
    return false
  end
  for index = 1, #a do
    if a[index] ~= b[index] then
      return false
    end
  end
  return true
end

local function copy_sequence(values)
  local copy = {}
  for index, value in ipairs(values or {}) do
    copy[index] = value
  end
  return copy
end

function shared:UpdateSettingsCategoryOrder()
  if not self.settings_finalized then
    return
  end

  local entries = self:GetSettingsEntries(false)
  for index, entry in ipairs(entries) do
    if type(entry.category) == "table" and type(entry.category.SetOrder) == "function" then
      entry.category:SetOrder(index)
    end
  end
end

function shared:ApplyLauncherOrder(ordered_ids)
  local active_entries = self:GetEntries(true)
  local valid_ids = {}
  local final_ids = {}
  local seen = {}

  for _, entry in ipairs(active_entries) do
    valid_ids[entry.id] = true
  end

  for _, addon_id in ipairs(ordered_ids or {}) do
    local key = trim_text(addon_id)
    if key ~= "" and valid_ids[key] and not seen[key] then
      seen[key] = true
      table_insert(final_ids, key)
    end
  end

  for _, entry in ipairs(active_entries) do
    if not seen[entry.id] then
      table_insert(final_ids, entry.id)
    end
  end

  local db = ensure_db()
  local overrides = db.settings.priority_overrides or {}
  db.settings.priority_overrides = overrides
  for key in pairs(overrides) do
    overrides[key] = nil
  end

  local total = #final_ids
  for index, addon_id in ipairs(final_ids) do
    overrides[addon_id] = total - index + 1
  end

  self:UpdateSettingsCategoryOrder()
  self:Refresh()
  if self.settings_hub_panel and self.settings_hub_panel.RefreshContents then
    self.settings_hub_panel:RefreshContents(self:GetSettingsEntries(false))
  end
end

function shared:GetPrimaryEntry()
  local entries = self:GetEntries(false)
  return entries[1], entries
end

function shared:GetLauncherOverrideAddonId()
  return get_launcher_override_id()
end

function shared:IsLauncherOverride(addon_id)
  local key = trim_text(addon_id)
  return key ~= "" and self:GetLauncherOverrideAddonId() == key
end

function shared:SetLauncherOverride(addon_id)
  local key = trim_text(addon_id)
  local db = ensure_db()
  db.settings.launcher_override_addon = key
  db.settings.left_click_addon = key
  db.settings.tooltip_addon = key
  self:Refresh()
  if self.settings_hub_panel and self.settings_hub_panel.RefreshContents then
    self.settings_hub_panel:RefreshContents()
  end
end

function shared:GetLauncherOverrideEntry(entries)
  local override_id = self:GetLauncherOverrideAddonId()
  if override_id == "" then
    return nil
  end
  local active_entries = entries or self:GetEntries(false)
  for _, entry in ipairs(active_entries) do
    if entry.id == override_id then
      return entry
    end
  end
  return nil
end

function shared:GetLauncherTargetEntry(entries)
  local override_entry = self:GetLauncherOverrideEntry(entries)
  if override_entry then
    return override_entry, entries or self:GetEntries(false)
  end
  local primary, active_entries = self:GetPrimaryEntry()
  return primary, active_entries
end

function shared:GetSharedIcon(entries)
  local active_entries = entries or self:GetEntries(false)
  for _, entry in ipairs(active_entries) do
    local icon = trim_text(entry.shared_icon)
    if icon ~= "" then
      return icon
    end
  end
  return DEFAULT_SHARED_ICON
end

function shared:GetBrokerName()
  return MINIMAP_LDB_NAME
end

function shared:GetLibDataBroker()
  return get_embedded_library("LibDataBroker-1.1")
end

function shared:GetLibDBIcon()
  return get_embedded_library("LibDBIcon-1.0")
end

function shared:EnsureDataObject()
  local data_object = self.data_object
  local ldb = self:GetLibDataBroker()
  local created = false
  if not data_object and not ldb then
    return nil
  end

  local name = self:GetBrokerName()
  if not data_object and type(ldb.GetDataObjectByName) == "function" then
    data_object = ldb:GetDataObjectByName(name)
  end
  if not data_object and type(ldb.NewDataObject) == "function" then
    data_object = ldb:NewDataObject(name, {
      type = "launcher",
      text = T("Kagrok Launcher"),
      icon = DEFAULT_BUTTON_ICON,
    })
    created = data_object ~= nil
  end
  if not data_object then
    return nil
  end

  data_object.type = "launcher"
  if created or trim_text(data_object.text) == "" then
    data_object.text = T("Kagrok Launcher")
  end
  if created or trim_text(data_object.icon) == "" then
    data_object.icon = DEFAULT_BUTTON_ICON
  end
  data_object.OnClick = function(frame, mouse_button)
    if mouse_button == "RightButton" then
      self:ShowContextMenu(frame or self.button or UIParent)
      return
    end
    if mouse_button == "LeftButton" then
      self:OpenPrimaryAddon()
    end
  end
  data_object.OnTooltipShow = function(tooltip)
    self:PopulateTooltip(tooltip, nil)
  end

  self.data_object = data_object
  return data_object
end

function shared:EnsureLibDBIconButton()
  local data_object = self:EnsureDataObject()
  local icon = self:GetLibDBIcon()
  if not data_object or not icon then
    return nil
  end

  local db = ensure_db()
  local name = self:GetBrokerName()
  local ok = true
  if type(icon.IsRegistered) == "function" and not icon:IsRegistered(name) then
    ok = pcall(icon.Register, icon, name, data_object, db.minimap)
  elseif type(icon.Refresh) == "function" then
    pcall(icon.Refresh, icon, name, db.minimap)
  end
  if not ok then
    return nil
  end

  if self.fallback_button then
    self.fallback_button:Hide()
  end

  self.button_provider = "libdbicon"
  if type(icon.GetMinimapButton) == "function" then
    self.button = icon:GetMinimapButton(name)
  end
  return self.button
end

function shared:EnsureFallbackButton()
  if self.fallback_button then
    self.button_provider = "fallback"
    self.button = self.fallback_button
    return self.fallback_button
  end
  if type(CreateFrame) ~= "function" or not Minimap then
    return nil
  end

  local button = CreateFrame("Button", "KagrokSharedLauncherMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetPoint("CENTER")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetVertexColor(0, 0, 0, 0.55)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  icon:SetTexture(DEFAULT_BUTTON_ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local pushed = button:CreateTexture(nil, "ARTWORK")
  pushed:SetSize(20, 20)
  pushed:SetPoint("CENTER", 1, -1)
  pushed:SetTexture(DEFAULT_BUTTON_ICON)
  pushed:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button:SetPushedTexture(pushed)

  button.Icon = icon
  button.PushedIcon = pushed
  button.Border = border
  button.Background = background

  button:SetScript("OnClick", function(_, mouse_button)
    if mouse_button == "RightButton" then
      self:ShowContextMenu(button)
      return
    end
    if mouse_button == "LeftButton" then
      self:OpenPrimaryAddon()
    end
  end)
  button:SetScript("OnDragStart", function(btn)
    btn:SetScript("OnUpdate", function()
      self:UpdateButtonDrag()
    end)
  end)
  button:SetScript("OnDragStop", function(btn)
    btn:SetScript("OnUpdate", nil)
    self:UpdateButtonDrag()
  end)
  button:SetScript("OnHide", function(btn)
    btn:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(btn)
    self:ShowTooltip(btn)
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  self.fallback_button = button
  self.button_provider = "fallback"
  self.button = button
  self:UpdateButtonAppearance()
  self:UpdateButtonPosition()
  return button
end

function shared:EnsureButton()
  local button = self:EnsureLibDBIconButton()
  if button then
    return button
  end
  return self:EnsureFallbackButton()
end

function shared:UpdateButtonAppearance()
  local primary, entries = self:GetPrimaryEntry()
  local override_entry = self:GetLauncherOverrideEntry(entries)
  local icon_path = DEFAULT_BUTTON_ICON
  local label = T("Kagrok Launcher")
  if override_entry then
    icon_path = trim_text(override_entry.icon)
    if icon_path == "" then
      icon_path = DEFAULT_BUTTON_ICON
    end
    label = override_entry.name or T("Kagrok Launcher")
  elseif primary then
    if #entries > 1 then
      icon_path = self:GetSharedIcon(entries)
      label = T("Kagrok Addons")
    else
      icon_path = trim_text(primary.icon)
      if icon_path == "" then
        icon_path = DEFAULT_BUTTON_ICON
      end
      label = primary.name or T("Kagrok Launcher")
    end
  end

  local data_object = self:EnsureDataObject()
  if data_object then
    data_object.icon = icon_path
    data_object.text = label
  end

  local button = self:EnsureButton()
  if not button then
    return
  end
  if button.Icon and button.PushedIcon then
    button.Icon:SetTexture(icon_path)
    button.PushedIcon:SetTexture(icon_path)
  end
end

function shared:UpdateButtonPosition()
  local button = self:EnsureButton()
  if not button then
    return
  end
  local db = ensure_db()
  db.angle = tonumber(db.minimap.minimapPos) or DEFAULT_MINIMAP_POSITION

  if self.button_provider == "libdbicon" then
    local icon = self:GetLibDBIcon()
    if icon and type(icon.Refresh) == "function" then
      pcall(icon.Refresh, icon, self:GetBrokerName(), db.minimap)
    end
    return
  end

  if not Minimap or not Minimap.GetCenter then
    return
  end

  local angle = tonumber(db.minimap.minimapPos) or DEFAULT_MINIMAP_POSITION
  local radius = (math.min(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) * 0.5) + 5
  local radians = math.rad(angle)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

function shared:UpdateButtonDrag()
  if self.button_provider == "libdbicon" then
    return
  end
  if not Minimap or not Minimap.GetCenter or not GetCursorPosition then
    return
  end
  local scale = Minimap:GetEffectiveScale() or 1
  local cursor_x, cursor_y = GetCursorPosition()
  local center_x, center_y = Minimap:GetCenter()
  if not cursor_x or not cursor_y or not center_x or not center_y then
    return
  end
  local dx = (cursor_x / scale) - center_x
  local dy = (cursor_y / scale) - center_y
  local db = ensure_db()
  db.minimap.minimapPos = get_polar_angle_degrees(dy, dx)
  db.angle = db.minimap.minimapPos
  self:UpdateButtonPosition()
end

function shared:OpenPrimaryAddon()
  local target = self:GetLauncherTargetEntry()
  if target and type(target.left_click) == "function" then
    safe_call(target.left_click)
  end
end

function shared:ResetButtonPosition()
  local db = ensure_db()
  db.minimap.minimapPos = DEFAULT_MINIMAP_POSITION
  db.angle = db.minimap.minimapPos
  self:UpdateButtonPosition()
end

function shared:IsStackHidden()
  local db = ensure_db()
  return db.minimap.hide == true
end

function shared:SetStackHidden(hidden)
  local db = ensure_db()
  db.minimap.hide = hidden == true
  db.settings.hide_stack = db.minimap.hide
  self:Refresh()
  if self.settings_hub_panel and self.settings_hub_panel.RefreshContents then
    self.settings_hub_panel:RefreshContents(self:GetSettingsEntries(false))
  end
end

function shared:IsAddonHidden(addon_id)
  local db = ensure_db()
  local hidden_addons = db.settings.hidden_addons or {}
  return hidden_addons[tostring(addon_id or "")] == true
end

function shared:SetAddonHidden(addon_id, hidden)
  local key = tostring(addon_id or "")
  if key == "" then
    return
  end
  local db = ensure_db()
  db.settings.hidden_addons[key] = hidden == true
  if hidden == true and self:IsLauncherOverride(key) then
    db.settings.launcher_override_addon = ""
    db.settings.left_click_addon = ""
    db.settings.tooltip_addon = ""
  end
  self:Refresh()
  if self.settings_hub_panel and self.settings_hub_panel.RefreshContents then
    self.settings_hub_panel:RefreshContents()
  end
end

function shared:PopulateTooltip(tooltip, owner)
  if not tooltip then
    return
  end
  local primary, entries = self:GetLauncherTargetEntry()
  if type(tooltip.ClearLines) == "function" then
    tooltip:ClearLines()
  end

  if primary and type(primary.tooltip) == "function" then
    safe_call(primary.tooltip, owner, tooltip, self, primary)
    if type(tooltip.Show) == "function" then
      tooltip:Show()
    end
    return
  end

  tooltip:SetText((#entries > 1) and T("Kagrok Addons") or (primary and primary.name or T("Kagrok Launcher")))
  if primary then
    tooltip:AddLine(string.format(T("Left Click: Open %s"), primary.name), 1, 1, 1)
  else
    tooltip:AddLine(T("Left Click: Open primary addon"), 1, 1, 1)
  end
  tooltip:AddLine(T("Right Click: Launcher menu"), 1, 1, 1)
  tooltip:AddLine(T("Drag: Move along minimap"), 0.65, 0.85, 1.0)
  if #entries > 1 then
    tooltip:AddLine(" ")
    for _, entry in ipairs(entries) do
      tooltip:AddLine(entry.name, 1.0, 0.82, 0.1)
    end
  end
  if type(tooltip.Show) == "function" then
    tooltip:Show()
  end
end

function shared:ShowTooltip(owner)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  self:PopulateTooltip(GameTooltip, owner)
end

function shared:HideContextMenu()
  if self.menu_frame then
    self.menu_frame:Hide()
  end
  if self.dismiss_frame then
    self.dismiss_frame:Hide()
  end
end

function shared:EnsureDismissFrame()
  if self.dismiss_frame then
    return self.dismiss_frame
  end
  local dismiss = CreateFrame("Button", nil, UIParent)
  dismiss:SetAllPoints(UIParent)
  dismiss:SetFrameStrata("DIALOG")
  dismiss:SetFrameLevel(1)
  dismiss:EnableMouse(true)
  dismiss:RegisterForClicks("LeftButtonUp")
  dismiss:SetScript("OnClick", function(_, mouse_button)
    if mouse_button == "LeftButton" then
      self:HideContextMenu()
    end
  end)
  dismiss:Hide()
  self.dismiss_frame = dismiss
  return dismiss
end

function shared:AcquireSectionTitle(index)
  local frame = self.menu_frame
  frame.section_titles = frame.section_titles or {}
  if frame.section_titles[index] then
    return frame.section_titles[index]
  end
  local title = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetJustifyH("LEFT")
  title:SetTextColor(1.0, 0.82, 0.1)
  frame.section_titles[index] = title
  return title
end

function shared:AcquireDivider(index)
  local frame = self.menu_frame
  frame.dividers = frame.dividers or {}
  if frame.dividers[index] then
    return frame.dividers[index]
  end
  local divider = frame.content:CreateTexture(nil, "ARTWORK")
  divider:SetHeight(1)
  divider:SetColorTexture(0.24, 0.61, 0.78, 0.55)
  frame.dividers[index] = divider
  return divider
end

function shared:AcquireMenuButton(index)
  local frame = self.menu_frame
  frame.buttons = frame.buttons or {}
  if frame.buttons[index] then
    return frame.buttons[index]
  end
  local button = CreateFrame("Button", nil, frame.content)
  button:SetHeight(MENU_ROW_HEIGHT)

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.07, 0.09, 0.12, 0.82)

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.08)

  local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", button, "LEFT", 10, 0)
  text:SetPoint("RIGHT", button, "RIGHT", -10, 0)
  text:SetJustifyH("LEFT")
  text:SetTextColor(0.93, 0.91, 0.82)
  button.Text = text

  frame.buttons[index] = button
  return button
end

function shared:BuildSections(entries)
  local sections = {}
  for _, entry in ipairs(entries or self:GetEntries(false)) do
    local items = entry.menu_items
    if type(items) == "function" then
      items = safe_call(items, entry, self)
    end
    if type(items) == "table" and #items > 0 then
      table_insert(sections, {
        title = entry.name,
        items = items,
      })
    end
  end

  local seen = {}
  local shared_items = {}
  local settings_entries = self:GetSettingsEntries(false)
  if #settings_entries > 0 then
    seen["launcher_settings"] = true
    table_insert(shared_items, {
      key = "launcher_settings",
      text = T("Open settings"),
      order = 10,
      func = function()
        self:OpenSettings()
      end,
    })
  end
  seen["hide_minimap_button"] = true
  table_insert(shared_items, {
    key = "hide_minimap_button",
    text = self:IsStackHidden() and T("Show minimap button") or T("Hide minimap button"),
    order = 999,
    func = function()
      self:SetStackHidden(not self:IsStackHidden())
    end,
  })
  for _, entry in ipairs(entries or self:GetEntries(false)) do
    local items = entry.shared_items
    if type(items) == "function" then
      items = safe_call(items, entry, self)
    end
    if type(items) == "table" then
      for _, item in ipairs(items) do
        local key = trim_text(item.key)
        if key ~= "" and not seen[key] then
          seen[key] = true
          table_insert(shared_items, item)
        end
      end
    end
  end
  table_sort(shared_items, function(a, b)
    local ao = tonumber(a.order) or 0
    local bo = tonumber(b.order) or 0
    if ao ~= bo then
      return ao < bo
    end
    return tostring(a.text or "") < tostring(b.text or "")
  end)
  if #shared_items > 0 then
    table_insert(sections, {
      title = T("Shared"),
      items = shared_items,
    })
  end
  return sections
end

local function get_menu_section_height(section)
  return 30 + (#(section.items or {}) * (MENU_ROW_HEIGHT + 2))
end

local function build_menu_column_layout(sections)
  if type(sections) ~= "table" or #sections == 0 then
    return {
      columns = { { sections = {} } },
      column_width = MENU_COLUMN_WIDTH,
      content_width = MENU_COLUMN_WIDTH,
      content_height = MENU_CONTENT_PADDING,
      frame_width = MENU_COLUMN_WIDTH + 22,
      frame_height = MENU_CONTENT_PADDING + 44,
    }
  end

  local columns = {}
  local current_column = { sections = {}, height = 0 }

  for _, section in ipairs(sections) do
    local section_height = get_menu_section_height(section)
    if #current_column.sections > 0 and (current_column.height + section_height) > MENU_MAX_CONTENT_HEIGHT then
      table_insert(columns, current_column)
      current_column = { sections = {}, height = 0 }
    end
    table_insert(current_column.sections, section)
    current_column.height = current_column.height + section_height
  end

  if #current_column.sections > 0 then
    table_insert(columns, current_column)
  end

  if #columns > MENU_MAX_COLUMNS then
    return nil
  end

  local tallest_column = 0
  for _, column in ipairs(columns) do
    if column.height > MENU_MAX_CONTENT_HEIGHT then
      return nil
    end
    tallest_column = math.max(tallest_column, column.height)
  end

  local content_width = (#columns * MENU_COLUMN_WIDTH) + (math.max(0, #columns - 1) * MENU_COLUMN_GAP)
  local content_height = math.max(1, MENU_CONTENT_PADDING + tallest_column)

  return {
    columns = columns,
    column_width = MENU_COLUMN_WIDTH,
    content_width = content_width,
    content_height = content_height,
    frame_width = content_width + 22,
    frame_height = content_height + 44,
  }
end

function shared:RefreshMenuLayout(entries)
  local frame = self.menu_frame
  if not frame then
    return
  end

  local sections = self:BuildSections(entries)
  local layout = build_menu_column_layout(sections)
  local use_scrollbar = layout == nil
  local title_count = 0
  local divider_count = 0
  local button_count = 0
  local function layout_section(section, x_offset, start_y, width)
    local y = start_y
    title_count = title_count + 1
    local title = self:AcquireSectionTitle(title_count)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", frame.content, "TOPLEFT", x_offset + 4, y)
    title:SetWidth(width - 8)
    title:SetText(section.title)
    title:Show()
    y = y - 16

    divider_count = divider_count + 1
    local divider = self:AcquireDivider(divider_count)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", frame.content, "TOPLEFT", x_offset + 4, y)
    divider:SetPoint("TOPRIGHT", frame.content, "TOPLEFT", x_offset + width, y)
    divider:Show()
    y = y - 8

    for _, item in ipairs(section.items) do
      button_count = button_count + 1
      local button = self:AcquireMenuButton(button_count)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", frame.content, "TOPLEFT", x_offset + 4, y)
      button:SetPoint("TOPRIGHT", frame.content, "TOPLEFT", x_offset + width, y)
      button.Text:SetText(tostring(item.text or T("Option")))
      button:SetEnabled(item.disabled ~= true)
      button:SetAlpha((item.disabled == true) and 0.5 or 1)
      button:SetScript("OnClick", function()
        self:HideContextMenu()
        if type(item.func) == "function" then
          safe_call(item.func)
        end
      end)
      button:Show()
      y = y - (MENU_ROW_HEIGHT + 2)
    end
    y = y - 6
    return y
  end

  if use_scrollbar then
    local y = -8
    for _, section in ipairs(sections) do
      y = layout_section(section, 0, y, MENU_SCROLL_COLUMN_WIDTH)
    end

    local content_height = math.max(1, -y + 8)
    frame.content:SetSize(MENU_SCROLL_COLUMN_WIDTH, content_height)
    frame.scroll:SetVerticalScroll(0)
    if frame.scroll.ScrollBar then
      frame.scroll.ScrollBar:SetShown(true)
    end
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)
    frame:SetWidth(MENU_WIDTH)
    frame:SetHeight(MENU_MAX_HEIGHT)
  else
    for column_index, column in ipairs(layout.columns) do
      local x_offset = (column_index - 1) * (layout.column_width + MENU_COLUMN_GAP)
      local y = -8
      for _, section in ipairs(column.sections) do
        y = layout_section(section, x_offset, y, layout.column_width)
      end
    end

    frame.content:SetSize(layout.content_width, layout.content_height)
    frame.scroll:SetVerticalScroll(0)
    if frame.scroll.ScrollBar then
      frame.scroll.ScrollBar:SetShown(false)
    end
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    frame:SetWidth(layout.frame_width)
    frame:SetHeight(layout.frame_height)
  end

  for index = title_count + 1, #(frame.section_titles or {}) do
    frame.section_titles[index]:Hide()
  end
  for index = divider_count + 1, #(frame.dividers or {}) do
    frame.dividers[index]:Hide()
  end
  for index = button_count + 1, #(frame.buttons or {}) do
    frame.buttons[index]:Hide()
  end
end

function shared:EnsureContextMenu()
  if self.menu_frame then
    return self.menu_frame
  end

  local frame = create_frame_with_optional_template("Frame", "KagrokSharedLauncherContextMenu", UIParent, "BackdropTemplate")
  frame:SetSize(MENU_WIDTH, 140)
  frame:SetFrameStrata("DIALOG")
  frame:SetFrameLevel(10)
  frame:SetClampedToScreen(true)
  create_backdrop(frame, { 0.03, 0.04, 0.06, 0.96 }, { 0.85, 0.7, 0.18, 1 })

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  title:SetTextColor(1.0, 0.82, 0.1)
  frame.TitleText = title

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self_frame, delta)
    local current = self_frame:GetVerticalScroll() or 0
    local step = 18
    local next_value = current - (delta * step)
    if next_value < 0 then
      next_value = 0
    end
    local max_scroll = math.max(0, (frame.content:GetHeight() or 0) - (scroll:GetHeight() or 0))
    if next_value > max_scroll then
      next_value = max_scroll
    end
    self_frame:SetVerticalScroll(next_value)
  end)
  frame.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(MENU_WIDTH - 42, 1)
  scroll:SetScrollChild(content)
  frame.content = content

  frame:Hide()
  self.menu_frame = frame
  return frame
end

function shared:ShowContextMenu(owner)
  local primary, entries = self:GetPrimaryEntry()
  if not primary then
    self:HideContextMenu()
    return
  end

  local dismiss = self:EnsureDismissFrame()
  local frame = self:EnsureContextMenu()
  frame.TitleText:SetText((#entries > 1) and T("Kagrok Addons") or primary.name)
  self:RefreshMenuLayout(entries)

  if frame:IsShown() then
    self:HideContextMenu()
    return
  end

  frame:ClearAllPoints()
  if owner and owner.GetRight and owner.GetBottom then
    frame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 10, -4)
  else
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local cursor_x, cursor_y = GetCursorPosition()
    local x = (cursor_x or 0) / scale
    local y = (cursor_y or 0) / scale
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 8, y - 8)
  end

  dismiss:Show()
  frame:Show()
end

function shared:Refresh()
  local button = self:EnsureButton()
  if not button then
    return nil
  end
  local primary = self:GetPrimaryEntry()
  local visible = (primary ~= nil) and not self:IsStackHidden()

  if visible then
    self:UpdateButtonAppearance()
  end

  if self.button_provider == "libdbicon" then
    local icon = self:GetLibDBIcon()
    if icon then
      if visible then
        if type(icon.Refresh) == "function" then
          pcall(icon.Refresh, icon, self:GetBrokerName(), ensure_db().minimap)
        end
        if type(icon.Show) == "function" then
          pcall(icon.Show, icon, self:GetBrokerName())
        end
      elseif type(icon.Hide) == "function" then
        pcall(icon.Hide, icon, self:GetBrokerName())
      end
    end
  else
    button:SetShown(visible)
    if visible then
      self:UpdateButtonPosition()
    end
  end

  if visible then
    if self.menu_frame and self.menu_frame:IsShown() then
      self:RefreshMenuLayout(self:GetEntries(false))
    end
  else
    self:HideContextMenu()
  end

  return button
end

function shared:EnsureSettingsBootstrap()
  if self.settings_bootstrap then
    return self.settings_bootstrap
  end
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
      self.settings_ready = true
    elseif event == "PLAYER_ENTERING_WORLD" then
      self.settings_ready = true
      self:ScheduleSettingsFinalize()
    end
  end)
  self.settings_bootstrap = frame
  return frame
end

function shared:ScheduleSettingsFinalize()
  if self.settings_finalized or self.settings_finalize_pending then
    return
  end

  self.settings_finalize_pending = true
  local function finalize()
    self.settings_finalize_pending = false
    if not self.settings_finalized then
      self:FinalizeSettingsPages()
    end
  end

  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, finalize)
  else
    finalize()
  end
end

local function set_row_grab_handle_state(row, active)
  if type(row) ~= "table" or type(row.grabDots) ~= "table" then
    return
  end

  local r, g, b, a
  if active then
    r, g, b, a = 1.0, 0.82, 0.18, 1.0
  else
    r, g, b, a = 0.66, 0.68, 0.72, 0.95
  end

  for _, dot in ipairs(row.grabDots) do
    dot:SetColorTexture(r, g, b, a)
  end
end

function shared:AcquireSettingsHubRow(panel, index)
  panel.list_rows = panel.list_rows or {}
  if panel.list_rows[index] then
    return panel.list_rows[index]
  end

  local row = create_frame_with_optional_template("Frame", nil, panel, "BackdropTemplate")
  row:SetHeight(62)
  if row.SetBackdrop then
    row:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = false,
      edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    row:SetBackdropColor(0.05, 0.05, 0.07, 0.90)
    row:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.90)
  end

  row.header = row:CreateTexture(nil, "ARTWORK")
  row.header:SetColorTexture(1, 1, 1, 0.04)
  row.header:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  row.header:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
  row.header:SetHeight(20)

  row.grabHandle = CreateFrame("Button", nil, row)
  row.grabHandle:SetPoint("LEFT", row, "LEFT", SETTINGS_GRAB_X, 0)
  row.grabHandle:SetSize(SETTINGS_GRAB_WIDTH, 26)
  row.grabHandle:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  row.grabHandle:SetScript("OnEnter", function()
    set_row_grab_handle_state(row, true)
  end)
  row.grabHandle:SetScript("OnLeave", function()
    if row.is_dragging then
      return
    end
    set_row_grab_handle_state(row, false)
  end)
  row.grabHandle:SetScript("OnMouseDown", function(_, mouse_button)
    if mouse_button == "LeftButton" and row.entry_id then
      shared:StartSettingsHubDrag(shared.settings_hub_panel, row)
    end
  end)
  row.grabHandle:SetScript("OnMouseUp", function(_, mouse_button)
    if mouse_button == "LeftButton" then
      shared:StopSettingsHubDrag(shared.settings_hub_panel, true)
    end
  end)

  row.grabDots = {}
  for dot_index = 1, 6 do
    local dot = row.grabHandle:CreateTexture(nil, "ARTWORK")
    local col = (dot_index - 1) % 2
    local dot_row = math.floor((dot_index - 1) / 2)
    dot:SetSize(3, 3)
    dot:SetPoint("TOPLEFT", row.grabHandle, "TOPLEFT", col * 6, -(4 + (dot_row * 7)))
    row.grabDots[dot_index] = dot
  end
  set_row_grab_handle_state(row, false)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(26, 26)
  row.icon:SetPoint("LEFT", row, "LEFT", SETTINGS_ICON_X, 0)

  row.order = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.order:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
  row.order:SetWidth(20)
  row.order:SetJustifyH("LEFT")
  row.order:SetTextColor(0.95, 0.82, 0.18)

  row.titleButton = CreateFrame("Button", nil, row)
  row.titleButton:SetPoint("TOPLEFT", row.order, "TOPRIGHT", 6, -4)
  row.titleButton:SetHeight(18)
  row.titleButton:RegisterForClicks("LeftButtonUp")
  row.titleButton:SetScript("OnEnter", function(button)
    if button.can_open then
      row.title:SetTextColor(1.0, 0.82, 0.18)
    end
  end)
  row.titleButton:SetScript("OnLeave", function(button)
    if button.can_open then
      row.title:SetTextColor(1, 1, 1)
    else
      row.title:SetTextColor(0.72, 0.72, 0.72)
    end
  end)

  row.title = row.titleButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.title:SetPoint("LEFT", row.titleButton, "LEFT", 0, 0)
  row.title:SetPoint("RIGHT", row.titleButton, "RIGHT", 0, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetTextColor(1, 1, 1)

  row.meta = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.meta:SetPoint("TOPLEFT", row.titleButton, "BOTTOMLEFT", 0, -4)
  row.meta:SetJustifyH("LEFT")
  row.meta:SetSpacing(1)

  row.priority = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.priority:SetPoint("RIGHT", row, "RIGHT", -140, 0)
  row.priority:SetJustifyH("RIGHT")
  row.priority:SetTextColor(0.82, 0.82, 0.82)

  row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.action:SetSize(118, 22)
  row.action:SetPoint("RIGHT", row, "RIGHT", -14, 0)

  panel.list_rows[index] = row
  return row
end

local function create_settings_section(parent, label, x, y, width)
  local frame = create_frame_with_optional_template("Frame", nil, parent, "BackdropTemplate")
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  frame:SetWidth(width)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = false,
      edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.90)
    frame:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.90)
  end

  frame.header = frame:CreateTexture(nil, "ARTWORK")
  frame.header:SetColorTexture(1, 1, 1, 0.04)
  frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
  frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.header:SetHeight(24)

  frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  frame.title:SetText(label or "")

  frame.pad = 12
  frame.innerY = -36
  return frame
end

local function add_section_note(frame, text, width)
  local note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.pad, frame.innerY)
  note:SetWidth(width or (frame:GetWidth() - (frame.pad * 2)))
  note:SetJustifyH("LEFT")
  note:SetSpacing(2)
  note:SetText(text or "")
  frame.innerY = frame.innerY - ((note:GetStringHeight() or 18) + 10)
  return note
end

local function finish_settings_section(frame, extra_bottom)
  local padding = extra_bottom or 12
  local height = math.abs(frame.innerY) + padding
  frame:SetHeight(height)
  return height
end

local function create_settings_check(parent, label, initial, on_click)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb.Text:SetText(label or "")
  cb:SetChecked(initial == true)
  cb:SetScript("OnClick", function(self)
    if type(on_click) == "function" then
      on_click(self:GetChecked() == true)
    end
  end)
  return cb
end

function shared:LayoutSettingsHubRows(frame, ordered_ids, immediate)
  if type(frame) ~= "table" or type(frame.listSection) ~= "table" then
    return
  end

  local list_section = frame.listSection
  list_section.order_ids = copy_sequence(ordered_ids or list_section.order_ids or {})

  local y = list_section.rows_start_y or -48
  for index, addon_id in ipairs(list_section.order_ids) do
    local row = list_section.rows_by_id and list_section.rows_by_id[addon_id]
    if row then
      row.order:SetText(string.format("%d.", index))
      row.target_y = y
      if immediate or row.current_y == nil then
        row.current_y = y
      end
      if not (frame.drag_state and frame.drag_state.row == row) then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list_section, "TOPLEFT", SETTINGS_ROW_X, row.current_y or y)
      end
      y = y - SETTINGS_ROW_PITCH
    end
  end

  list_section:SetHeight(math.max(120, math.abs(y) + 20))
end

function shared:RefreshSettingsHubAnimator(frame)
  if type(frame) ~= "table" then
    return
  end

  local needs_update = frame.drag_state ~= nil
  local list_section = frame.listSection
  if not needs_update and type(list_section) == "table" and type(list_section.rows_by_id) == "table" then
    for _, row in pairs(list_section.rows_by_id) do
      if row:IsShown() and row.target_y and row.current_y and math.abs(row.target_y - row.current_y) > 0.5 then
        needs_update = true
        break
      end
    end
  end

  if needs_update then
    if not frame:GetScript("OnUpdate") then
      frame:SetScript("OnUpdate", function(panel, elapsed)
        shared:UpdateSettingsHubDrag(panel, elapsed)
      end)
    end
  else
    frame:SetScript("OnUpdate", nil)
  end
end

function shared:GetDraggedSettingsHubOrder(frame, drag_state)
  local list_section = frame and frame.listSection
  if type(list_section) ~= "table" then
    return copy_sequence(drag_state and drag_state.order_ids or {})
  end

  local top = list_section:GetTop()
  local scale = list_section:GetEffectiveScale()
  if not top or not scale or scale == 0 then
    return copy_sequence(drag_state and drag_state.order_ids or {})
  end

  local _, cursor_y = GetCursorPosition()
  cursor_y = (cursor_y or 0) / scale

  local compact_ids = {}
  for _, addon_id in ipairs(drag_state.order_ids or {}) do
    if addon_id ~= drag_state.entry_id then
      table_insert(compact_ids, addon_id)
    end
  end

  local rows_start = math.abs(list_section.rows_start_y or 0)
  local relative_y = (top - cursor_y) - rows_start
  local insert_index = #compact_ids + 1

  for index = 1, #compact_ids do
    local slot_center = ((index - 1) * SETTINGS_ROW_PITCH) + (SETTINGS_ROW_HEIGHT / 2)
    if relative_y < slot_center then
      insert_index = index
      break
    end
  end

  local ordered_ids = {}
  local inserted = false
  for index = 1, #compact_ids do
    if not inserted and index == insert_index then
      table_insert(ordered_ids, drag_state.entry_id)
      inserted = true
    end
    table_insert(ordered_ids, compact_ids[index])
  end
  if not inserted then
    table_insert(ordered_ids, drag_state.entry_id)
  end

  return ordered_ids
end

function shared:GetDraggedSettingsHubRowY(frame, drag_state)
  local list_section = frame and frame.listSection
  local row = drag_state and drag_state.row
  if type(list_section) ~= "table" or type(row) ~= "table" then
    return nil
  end

  local top = list_section:GetTop()
  local scale = row:GetEffectiveScale()
  if not top or not scale or scale == 0 then
    return row.current_y or row.target_y or list_section.rows_start_y or 0
  end

  local _, cursor_y = GetCursorPosition()
  cursor_y = (cursor_y or 0) / scale

  local desired_center_y = cursor_y - (drag_state.cursor_offset_y or 0)
  local drag_y = (desired_center_y + (SETTINGS_ROW_HEIGHT / 2)) - top

  local max_y = list_section.rows_start_y or 0
  local min_y = max_y - (math.max(0, (#(drag_state.order_ids or {}) - 1)) * SETTINGS_ROW_PITCH)
  if drag_y > max_y then
    drag_y = max_y
  elseif drag_y < min_y then
    drag_y = min_y
  end

  return drag_y
end

function shared:UpdateSettingsHubDrag(frame, elapsed)
  if type(frame) ~= "table" or type(frame.listSection) ~= "table" then
    return
  end

  local list_section = frame.listSection
  local drag_state = frame.drag_state
  if drag_state and type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
    self:StopSettingsHubDrag(frame, true)
    return
  end

  if drag_state then
    local ordered_ids = self:GetDraggedSettingsHubOrder(frame, drag_state)
    if not sequence_equals(ordered_ids, drag_state.order_ids) then
      drag_state.order_ids = ordered_ids
      self:LayoutSettingsHubRows(frame, ordered_ids, false)
    end
  end

  for _, row in pairs(list_section.rows_by_id or {}) do
    if row:IsShown() then
      local target_y = row.target_y or row.current_y or (list_section.rows_start_y or 0)
      if drag_state and drag_state.row == row then
        target_y = self:GetDraggedSettingsHubRowY(frame, drag_state) or target_y
      elseif row.current_y and math.abs(target_y - row.current_y) > 0.5 then
        target_y = row.current_y + ((target_y - row.current_y) * math.min(1, (elapsed or 0) * 18))
      end

      row.current_y = target_y
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list_section, "TOPLEFT", SETTINGS_ROW_X, target_y)
    end
  end

  self:RefreshSettingsHubAnimator(frame)
end

function shared:StartSettingsHubDrag(frame, row)
  if type(frame) ~= "table" or type(row) ~= "table" or not row.entry_id then
    return
  end

  self:StopSettingsHubDrag(frame, false)

  local scale = row:GetEffectiveScale()
  local _, cursor_y = GetCursorPosition()
  cursor_y = (cursor_y or 0) / (scale and scale ~= 0 and scale or 1)

  local _, row_center_y = row:GetCenter()
  row_center_y = row_center_y or cursor_y

  frame.drag_state = {
    row = row,
    entry_id = row.entry_id,
    original_ids = copy_sequence(frame.listSection.order_ids or {}),
    order_ids = copy_sequence(frame.listSection.order_ids or {}),
    cursor_offset_y = cursor_y - row_center_y,
    restore_strata = row:GetFrameStrata(),
    restore_level = row:GetFrameLevel(),
    restore_alpha = row:GetAlpha(),
  }

  row.is_dragging = true
  row:SetFrameStrata("DIALOG")
  row:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
  row:SetAlpha(0.96)
  set_row_grab_handle_state(row, true)

  self:LayoutSettingsHubRows(frame, frame.drag_state.order_ids, false)
  self:RefreshSettingsHubAnimator(frame)
end

function shared:StopSettingsHubDrag(frame, apply_order)
  local drag_state = frame and frame.drag_state
  if type(frame) ~= "table" or type(drag_state) ~= "table" then
    return
  end

  local row = drag_state.row
  frame.drag_state = nil

  if type(row) == "table" then
    row.is_dragging = false
    row:SetFrameStrata(drag_state.restore_strata or "MEDIUM")
    row:SetFrameLevel(drag_state.restore_level or 1)
    row:SetAlpha(drag_state.restore_alpha or 1)
    set_row_grab_handle_state(row, false)
  end

  local final_ids = copy_sequence(drag_state.order_ids or {})
  if apply_order and not sequence_equals(final_ids, drag_state.original_ids or {}) then
    self:ApplyLauncherOrder(final_ids)
    return
  end

  self:LayoutSettingsHubRows(frame, drag_state.original_ids or final_ids, true)
  self:RefreshSettingsHubAnimator(frame)
end

function shared:EnsureSettingsHubPanel()
  if self.settings_hub_panel then
    return self.settings_hub_panel
  end

  local panel = CreateFrame("Frame", "KagrokSharedLauncherSettingsPanel")
  panel.name = T("Kagrok's Addons")

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText(T("Kagrok's Addons"))

  local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  desc:SetWidth(760)
  desc:SetJustifyH("LEFT")
  desc:SetSpacing(2)
  desc:SetText(T("Shared launcher settings for Kagrok addons. Subcategories below are listed in launcher priority order."))

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -8)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 16)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self_frame, delta)
    local range = self_frame:GetVerticalScrollRange() or 0
    local current = self_frame:GetVerticalScroll() or 0
    local next_value = math.max(0, math.min(range, current - ((delta or 0) * 28)))
    self_frame:SetVerticalScroll(next_value)
  end)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetSize(820, 420)
  scroll:SetScrollChild(content)
  scroll:HookScript("OnSizeChanged", function(_, width)
    if content and width and width > 0 then
      content:SetWidth(width - 2)
    end
  end)

  local layout_padding = 12
  local section_gap = 3
  local content_width = 820
  local inner_width = content_width - (layout_padding * 2)
  local left_width = math.floor((inner_width - section_gap) * 0.42) - 35
  local right_width = left_width
  local left_x = layout_padding
  local right_x = left_x + left_width + section_gap
  local full_width = left_width + right_width + section_gap
  local cursor_y = -6

  local launcher_section = create_settings_section(content, T("Launcher"), left_x, cursor_y, left_width)
  local summary_section = create_settings_section(content, T("Settings"), right_x, cursor_y, right_width)

  local show_stack = create_settings_check(launcher_section, T("Show shared minimap button stack"), not self:IsStackHidden(), function(value)
    self:SetStackHidden(not value)
  end)
  show_stack:SetPoint("TOPLEFT", launcher_section, "TOPLEFT", launcher_section.pad, launcher_section.innerY)
  launcher_section.innerY = launcher_section.innerY - 28

  local reset = CreateFrame("Button", nil, launcher_section, "UIPanelButtonTemplate")
  reset:SetSize(154, 24)
  reset:SetPoint("TOPLEFT", launcher_section, "TOPLEFT", launcher_section.pad, launcher_section.innerY - 2)
  reset:SetText(T("Reset minimap button"))
  reset:SetScript("OnClick", function()
    self:ResetButtonPosition()
  end)
  launcher_section.innerY = launcher_section.innerY - 38
  add_section_note(launcher_section, T("Reset the shared minimap button position for every registered Kagrok addon."), left_width - (launcher_section.pad * 2))
  add_section_note(launcher_section, T("Use the addon rows below to override the launcher icon, tooltip, and primary action."), left_width - (launcher_section.pad * 2))

  local summary_text = summary_section:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  summary_text:SetPoint("TOPLEFT", summary_section, "TOPLEFT", summary_section.pad, summary_section.innerY)
  summary_text:SetWidth(right_width - (summary_section.pad * 2))
  summary_text:SetJustifyH("LEFT")
  summary_text:SetSpacing(2)
  summary_text:SetText("")
  summary_section.innerY = summary_section.innerY - 68
  add_section_note(summary_section, T("Use the shared settings entry from the minimap launcher to open this hub or the only available addon page."), right_width - (summary_section.pad * 2))

  local row_height = math.max(finish_settings_section(launcher_section), finish_settings_section(summary_section))
  launcher_section:SetHeight(row_height)
  summary_section:SetHeight(row_height)
  cursor_y = cursor_y - row_height - section_gap

  local list_section = create_settings_section(content, T("Registered Addons"), left_x, cursor_y, full_width)
  local list_note = list_section:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  list_note:SetPoint("TOPLEFT", list_section, "TOPLEFT", list_section.pad, list_section.innerY)
  list_note:SetWidth(full_width - (list_section.pad * 2))
  list_note:SetJustifyH("LEFT")
  list_note:SetSpacing(2)
  list_note:SetText(T("Each addon keeps its own settings page below this parent. This list shows the shared launcher order."))
  list_section.rows_start_y = list_section.innerY - ((list_note:GetStringHeight() or 18) + 12)
  list_section.innerY = list_section.rows_start_y

  panel.RefreshContents = function(frame, entries)
    local settings_rows = entries or self:GetSettingsEntries(false)
    local launcher_rows = self:GetEntries(false)
    local override_entry = self:GetLauncherOverrideEntry(launcher_rows)
    local settings_target = (#settings_rows > 1) and T("Kagrok's Addons") or ((settings_rows[1] and settings_rows[1].name) or T("this addon"))
    local override_name = override_entry and (override_entry.name or override_entry.id) or T("Shared icon")
    if frame.ShowStackCheck then
      frame.ShowStackCheck:SetChecked(not self:IsStackHidden())
    end
    summary_text:SetText(string.format(T("Registered settings pages: %d\nOpen settings destination: %s\nMinimap stack: %s\nLauncher override: %s"), #settings_rows, settings_target, self:IsStackHidden() and T("Hidden") or T("Shown"), override_name))

    local row_width = full_width - 24
    frame.listSection.row_width = row_width
    frame.listSection.entry_map = {}
    frame.listSection.rows_by_id = {}
    frame.listSection.order_ids = {}
    for index, entry in ipairs(launcher_rows) do
      local row = self:AcquireSettingsHubRow(frame.listSection, index)
      row:SetWidth(row_width)
      local text_width = math.max(180, row_width - 280)
      row.titleButton:SetWidth(text_width)
      row.meta:SetWidth(text_width)
      row.entry_id = entry.id
      row.icon:SetTexture(trim_text(entry.icon) ~= "" and entry.icon or DEFAULT_BUTTON_ICON)
      row.title:SetText(entry.name or entry.id or T("Unknown Addon"))
      row.meta:SetText(string.format(T("Settings page: %s\nMinimap entry: %s"), entry.name or entry.id or T("Unknown Addon"), self:IsAddonHidden(entry.id) and T("Hidden") or T("Shown")))
      row.titleButton.can_open = self:GetSettingsEntry(entry.id) ~= nil
      row.titleButton:EnableMouse(row.titleButton.can_open)
      row.titleButton:SetScript("OnClick", function()
        if row.titleButton.can_open then
          self:OpenSettings(entry.id)
        end
      end)
      row.title:SetTextColor(row.titleButton.can_open and 1 or 0.72, row.titleButton.can_open and 1 or 0.72, row.titleButton.can_open and 1 or 0.72)
      if self:IsLauncherOverride(entry.id) then
        row.priority:SetText(T("Launcher override"))
        row.action:SetText(T("Clear override"))
      else
        row.priority:SetText(string.format(T("Priority %d"), get_effective_priority(entry)))
        row.action:SetText(T("Use as launcher"))
      end
      row.action:SetScript("OnClick", function()
        if self:IsLauncherOverride(entry.id) then
          self:SetLauncherOverride(nil)
        else
          self:SetLauncherOverride(entry.id)
        end
      end)
      row.action:Show()
      row:Show()
      frame.listSection.entry_map[entry.id] = entry
      frame.listSection.rows_by_id[entry.id] = row
      frame.listSection.order_ids[index] = entry.id
    end
    for index = #launcher_rows + 1, #(frame.listSection.list_rows or {}) do
      frame.listSection.list_rows[index]:Hide()
    end
    self:LayoutSettingsHubRows(frame, frame.listSection.order_ids, true)
    content:SetHeight(math.abs(cursor_y) + frame.listSection:GetHeight() + 24)
  end

  panel.ScrollFrame = scroll
  panel.ScrollContent = content
  panel.LauncherSection = launcher_section
  panel.ShowStackCheck = show_stack
  panel.SummarySection = summary_section
  panel.listSection = list_section

  self.settings_hub_panel = panel
  return panel
end

function shared:FinalizeSettingsPages()
  if self.settings_finalized then
    return true
  end

  local entries = self:GetSettingsEntries(false)
  if #entries == 0 then
    return false
  end

  local supports_canvas_categories = Settings
    and type(Settings.RegisterCanvasLayoutCategory) == "function"
    and type(Settings.RegisterAddOnCategory) == "function"
  local supports_subcategories = supports_canvas_categories and type(Settings.RegisterCanvasLayoutSubcategory) == "function"

  if supports_canvas_categories then
    if #entries == 1 or not supports_subcategories then
      for _, entry in ipairs(entries) do
        local panel = safe_call(entry.get_panel, entry, self)
        if panel then
          local category = Settings.RegisterCanvasLayoutCategory(panel, entry.name)
          Settings.RegisterAddOnCategory(category)
          entry.category = category
          entry.category_name = entry.name
          if type(entry.on_registered) == "function" then
            safe_call(entry.on_registered, category, nil)
          end
        end
      end
    else
      local hub_panel = self:EnsureSettingsHubPanel()
      local hub_category = Settings.RegisterCanvasLayoutCategory(hub_panel, hub_panel.name)
      Settings.RegisterAddOnCategory(hub_category)
      self.settings_hub_category = hub_category
      hub_panel:RefreshContents(entries)

      for index, entry in ipairs(entries) do
        local panel = safe_call(entry.get_panel, entry, self)
        if panel then
          local subcategory = Settings.RegisterCanvasLayoutSubcategory(hub_category, panel, entry.name)
          if subcategory and subcategory.SetOrder then
            subcategory:SetOrder(index)
          end
          entry.category = subcategory
          entry.category_name = entry.name
          if type(entry.on_registered) == "function" then
            safe_call(entry.on_registered, subcategory, hub_category)
          end
        end
      end
    end
  else
    for _, entry in ipairs(entries) do
      local panel = safe_call(entry.get_panel, entry, self)
      if panel and type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
        entry.category = panel
        entry.category_name = panel.name or entry.name
        if type(entry.on_registered) == "function" then
          safe_call(entry.on_registered, panel, nil)
        end
      end
    end
  end

  self.settings_finalized = true
  return true
end

function shared:OpenSettings(addon_id)
  if not self.settings_finalized then
    self:FinalizeSettingsPages()
  end

  local entries = self:GetSettingsEntries(false)
  local entry = nil
  if addon_id then
    entry = self:GetSettingsEntry(addon_id)
  else
    if #entries > 1 and self.settings_hub_category then
      entry = nil
    else
      entry = entries[1]
    end
  end

  local target = nil
  local fallback_name = nil
  if entry and entry.category then
    target = entry.category
    fallback_name = entry.category_name or entry.name
  elseif self.settings_hub_category then
    target = self.settings_hub_category
    fallback_name = T("Kagrok's Addons")
  elseif entry then
    fallback_name = entry.category_name or entry.name
  end

  if Settings and Settings.OpenToCategory then
    if type(target) == "table" and type(target.GetID) == "function" then
      Settings.OpenToCategory(target:GetID())
      return true
    end
    if type(target) == "table" and target.ID then
      Settings.OpenToCategory(target.ID)
      return true
    end
    if fallback_name and fallback_name ~= "" then
      Settings.OpenToCategory(fallback_name)
      return true
    end
  end

  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(target or fallback_name)
    InterfaceOptionsFrame_OpenToCategory(target or fallback_name)
    return true
  end
  return false
end

shared.registry = shared.registry or {}
shared.settings_registry = shared.settings_registry or {}
shared.__module_version = MODULE_VERSION
