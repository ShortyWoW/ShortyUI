local addon_name, ns = ...
local L = ns.L or {}

local function T(key)
  local value = L[key]
  if value == nil or value == "" then
    return key
  end
  return value
end

local DevInfoModule = {}
ns.DevInfoModule = DevInfoModule
_G.KagrokDevInfoModule = DevInfoModule

-- Copy-friendly module usage:
-- 1. Add this file to your addon's TOC before the files that use it.
-- 2. Create a controller once:
--      local dev_info = ns.DevInfoModule:Create(self, { addon_name = addon_name })
-- 3. Attach the opener button where you want it:
--      dev_info:AttachButton(parent_frame, {
--          point = "BOTTOMLEFT",
--          relative_to = parent_frame,
--          relative_point = "BOTTOMLEFT",
--          x = 12,
--          y = 1,
--      })
-- 4. Reuse dev_info:ShowPanel() from slash commands, menus, or other buttons.

local ACCENT_LEFT = { 0.97, 0.03, 0.57 }
local ACCENT_RIGHT = { 0.08, 0.39, 0.98 }
local BORDER_COLOR = { 0.19, 0.22, 0.28, 1 }
local PANEL_BG_COLOR = { 0.035, 0.04, 0.055, 0.98 }
local HEADER_BG_COLOR = { 0.055, 0.065, 0.09, 1 }
local SURFACE_BG_COLOR = { 0.07, 0.08, 0.11, 1 }
local CLOSE_BG_COLOR = { 0.12, 0.14, 0.18, 1 }

local function copy_table(source)
  local target = {}
  if type(source) ~= "table" then
    return target
  end
  for key, value in pairs(source) do
    target[key] = value
  end
  return target
end

local function copy_entries(entries)
  local copied = {}
  if type(entries) ~= "table" then
    return copied
  end
  for index, entry in ipairs(entries) do
    copied[index] = copy_table(entry)
  end
  return copied
end

local function get_default_media_root(config)
  local configured_root = tostring(config and config.media_root or "")
  if configured_root ~= "" then
    return configured_root
  end
  return "Interface\\AddOns\\" .. tostring(addon_name or "Addon") .. "\\Media\\Social\\"
end

local function build_default_links(media_root)
  return {
    {
      key = "curseforge",
      label = "CurseForge",
      url = "https://www.curseforge.com/members/kagrok/projects",
      tooltip = T("Check out my other projects"),
      icon = media_root .. "curseforge.png",
      accent = { 0.95, 0.42, 0.12 },
    },
    {
      key = "bluesky",
      label = "Bluesky",
      url = "https://bsky.app/profile/kagrok.bsky.social",
      tooltip = T("Join me on BlueSky"),
      icon = media_root .. "bluesky.jpeg",
      accent = { 0.09, 0.62, 0.97 },
    },
    {
      key = "discord",
      label = "Discord",
      url = "http://discord.gg/U2TeUF9y3K",
      tooltip = T("Join my community"),
      badge = "D",
      accent = { 0.35, 0.42, 0.95 },
    },
    {
      key = "twitch",
      label = "Twitch",
      url = "https://www.twitch.tv/kagrok",
      tooltip = T("Follow me on Twitch"),
      icon = media_root .. "twitch.png",
      accent = { 0.57, 0.36, 0.93 },
    },
    {
      key = "youtube",
      label = "YouTube",
      url = "https://www.youtube.com/@Kagrok",
      tooltip = T("Follow me on YouTube"),
      icon = media_root .. "youtube.png",
      accent = { 0.92, 0.16, 0.14 },
    },
    {
      key = "patreon",
      label = "Patreon",
      url = "https://www.patreon.com/cw/Kagrok",
      tooltip = T("Support me!"),
      icon = media_root .. "patreon.png",
      accent = { 0.96, 0.39, 0.29 },
    },
    {
      key = "buymeacoffee",
      label = "Buy Me A Coffee",
      url = "https://buymeacoffee.com/kagrok",
      tooltip = T("Support me!"),
      icon = media_root .. "bmac.png",
      accent = { 1.0, 0.86, 0.22 },
    },
  }
end

local function merge_config(config)
  local resolved = copy_table(config)
  resolved.addon_name = tostring(resolved.addon_name or addon_name or "Addon")
  resolved.frame_prefix = tostring(resolved.frame_prefix or resolved.addon_name)
  resolved.media_root = tostring(resolved.media_root or get_default_media_root(resolved))
  resolved.panel_title = tostring(resolved.panel_title or T("Developer Info"))
  resolved.button_text = tostring(resolved.button_text or T("Dev Info"))
  resolved.profile_name = tostring(resolved.profile_name or "Kagrok")
  resolved.profile_title = tostring(resolved.profile_title or T("WoW Addon Developer"))
  resolved.profile_body = tostring(resolved.profile_body or T("Murloc Minder and other World of Warcraft projects.\n\nClick any platform on the right to open a copyable link."))
  resolved.profile_texture = tostring(resolved.profile_texture or (resolved.media_root .. "kagrok_full.png"))
  resolved.links = (#copy_entries(resolved.links) > 0) and copy_entries(resolved.links) or build_default_links(resolved.media_root)
  return resolved
end

local function sanitize_prefix(raw)
  local text = tostring(raw or "")
  text = text:gsub("[^%w]", "")
  if text == "" then
    return "Addon"
  end
  return text
end

local function register_special_frame(frame)
  if type(UISpecialFrames) ~= "table" or not frame or not frame.GetName then
    return
  end
  local name = frame:GetName()
  if not name or name == "" then
    return
  end
  for _, existing in ipairs(UISpecialFrames) do
    if existing == name then
      return
    end
  end
  UISpecialFrames[#UISpecialFrames + 1] = name
end

local function set_backdrop(frame, bg, border)
  if not frame or not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function set_horizontal_gradient(texture, left_color, right_color)
  if not texture then
    return
  end
  texture:SetTexture("Interface\\Buttons\\WHITE8x8")
  if texture.SetGradient and CreateColor then
    texture:SetGradient("HORIZONTAL", CreateColor(left_color[1], left_color[2], left_color[3], left_color[4] or 1), CreateColor(right_color[1], right_color[2], right_color[3], right_color[4] or 1))
  else
    texture:SetColorTexture(left_color[1], left_color[2], left_color[3], left_color[4] or 1)
  end
end

local function play_ui_sound(self, sound_key)
  local callback = self and self.config and self.config.sound_player
  if type(callback) == "function" then
    callback(sound_key)
  end
end

local function host_print(self, text)
  local callback = self and self.config and self.config.print
  if type(callback) == "function" then
    callback(text)
  end
end

local function resolve_link_entry(self, entry)
  if type(entry) == "table" then
    return entry
  end
  if type(entry) ~= "string" then
    return nil
  end
  for _, candidate in ipairs(self.config.links or {}) do
    if candidate.key == entry then
      return candidate
    end
  end
  return nil
end

local function create_close_button(parent, on_click)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(26, 26)

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(CLOSE_BG_COLOR[1], CLOSE_BG_COLOR[2], CLOSE_BG_COLOR[3], CLOSE_BG_COLOR[4])

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.08)

  local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetPoint("CENTER")
  text:SetTextColor(0.95, 0.95, 0.95)
  text:SetText("x")

  button:SetScript("OnClick", on_click)
  return button
end

function DevInfoModule:Create(host, config)
  local instance = setmetatable({}, { __index = DevInfoModule })
  instance.host = host
  instance.config = merge_config(config or {})
  return instance
end

function DevInfoModule:GetFramePrefix()
  return sanitize_prefix(self.config.frame_prefix)
end

function DevInfoModule:GetHost()
  return self.host
end

function DevInfoModule:GetLinks()
  return self.config.links
end

function DevInfoModule:EnsureButton(parent, anchor)
  if type(CreateFrame) ~= "function" or not parent then
    return nil
  end

  if self.button and self.button:GetParent() ~= parent then
    self.button:Hide()
    self.button = nil
  end

  if not self.button then
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    set_backdrop(button, { 0.055, 0.065, 0.09, 0.98 }, BORDER_COLOR)

    local accent = button:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    set_horizontal_gradient(accent, ACCENT_LEFT, ACCENT_RIGHT)
    button.Accent = accent

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(1, 1, 1, 0.06)

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(0.95, 0.95, 0.95)
    button.Text = text

    button:SetScript("OnMouseDown", function()
      text:SetPoint("CENTER", 1, -1)
    end)
    button:SetScript("OnMouseUp", function()
      text:SetPoint("CENTER")
    end)
    button:SetScript("OnClick", function()
      self:ShowPanel()
    end)

    self.button = button
  end

  local button = self.button
  local options = type(anchor) == "table" and anchor or {}
  local width = tonumber(options.width) or 56
  local height = tonumber(options.height) or 21
  local point = tostring(options.point or "BOTTOMLEFT")
  local relative_to = options.relative_to or parent
  local relative_point = tostring(options.relative_point or point)
  local x = tonumber(options.x) or 12
  local y = tonumber(options.y) or 1
  local frame_level_offset = tonumber(options.frame_level_offset)
  local frame_strata = options.frame_strata or (parent.GetFrameStrata and parent:GetFrameStrata()) or "MEDIUM"
  local button_text = tostring(options.text or self.config.button_text)

  button:ClearAllPoints()
  button:SetPoint(point, relative_to, relative_point, x, y)
  button:SetSize(width, height)
  button:SetFrameStrata(frame_strata)
  if parent.GetFrameLevel then
    button:SetFrameLevel(parent:GetFrameLevel() + (frame_level_offset or 8))
  end
  button.Text:SetText(button_text)
  button:Show()
  return button
end

function DevInfoModule:AttachButton(parent, anchor)
  return self:EnsureButton(parent, anchor)
end

function DevInfoModule:EnsureSocialCopyFrame()
  if self.social_copy_frame and self.social_copy_frame.EditBox and self.social_copy_frame.TitleText then
    return self.social_copy_frame
  end
  if type(CreateFrame) ~= "function" or not UIParent then
    return nil
  end

  local frame_name = self:GetFramePrefix() .. "SocialCopyFrame"
  local frame = CreateFrame("Frame", frame_name, UIParent, "BackdropTemplate")
  frame:SetSize(560, 118)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  set_backdrop(frame, PANEL_BG_COLOR, BORDER_COLOR)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(panel)
    panel:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(panel)
    panel:StopMovingOrSizing()
  end)

  local shadow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 8)
  shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -8)
  set_backdrop(shadow, { 0, 0, 0, 0 }, { 0, 0, 0, 0.35 })
  shadow:SetFrameLevel(math.max(1, frame:GetFrameLevel() - 1))

  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(40)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  local header_bg = header:CreateTexture(nil, "BACKGROUND")
  header_bg:SetAllPoints()
  header_bg:SetColorTexture(HEADER_BG_COLOR[1], HEADER_BG_COLOR[2], HEADER_BG_COLOR[3], HEADER_BG_COLOR[4])

  local header_accent = header:CreateTexture(nil, "ARTWORK")
  header_accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  header_accent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header_accent:SetHeight(2)
  set_horizontal_gradient(header_accent, ACCENT_LEFT, ACCENT_RIGHT)

  local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", header, "LEFT", 14, 0)
  title:SetTextColor(1, 1, 1)
  title:SetText(T("Link"))
  frame.TitleText = title

  local close_button = create_close_button(header, function()
    frame:Hide()
    play_ui_sound(self, "popup_close")
  end)
  close_button:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  frame.CloseButton = close_button

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -54)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)

  local icon_frame = CreateFrame("Frame", nil, content, "BackdropTemplate")
  icon_frame:SetSize(52, 52)
  icon_frame:SetPoint("LEFT", content, "LEFT", 0, 0)
  set_backdrop(icon_frame, SURFACE_BG_COLOR, BORDER_COLOR)
  frame.IconFrame = icon_frame

  local icon_accent = icon_frame:CreateTexture(nil, "ARTWORK")
  icon_accent:SetPoint("TOPLEFT", icon_frame, "TOPLEFT", 1, -1)
  icon_accent:SetPoint("TOPRIGHT", icon_frame, "TOPRIGHT", -1, -1)
  icon_accent:SetHeight(2)
  frame.IconAccent = icon_accent

  local icon_texture = icon_frame:CreateTexture(nil, "ARTWORK")
  icon_texture:SetSize(28, 28)
  icon_texture:SetPoint("CENTER")
  frame.IconTexture = icon_texture

  local icon_badge = icon_frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  icon_badge:SetPoint("CENTER")
  icon_badge:SetTextColor(1, 1, 1)
  frame.IconBadge = icon_badge

  local field = CreateFrame("Frame", nil, content, "BackdropTemplate")
  field:SetPoint("LEFT", icon_frame, "RIGHT", 12, 0)
  field:SetPoint("RIGHT", content, "RIGHT", 0, 0)
  field:SetHeight(40)
  set_backdrop(field, SURFACE_BG_COLOR, BORDER_COLOR)

  local edit = CreateFrame("EditBox", nil, field)
  edit:SetMultiLine(false)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetPoint("TOPLEFT", field, "TOPLEFT", 10, -11)
  edit:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -10, 11)
  edit:SetJustifyH("LEFT")
  edit:SetJustifyV("MIDDLE")
  edit:SetTextInsets(0, 0, 0, 0)
  edit:SetScript("OnEscapePressed", function()
    frame:Hide()
    play_ui_sound(self, "popup_close")
  end)
  edit:SetScript("OnMouseDown", function(box)
    box:SetFocus()
    box:HighlightText()
  end)
  frame.EditBox = edit

  register_special_frame(frame)

  frame:Hide()
  self.social_copy_frame = frame
  return frame
end

function DevInfoModule:ShowCopyableSocialLink(entry)
  local resolved = resolve_link_entry(self, entry)
  if type(resolved) ~= "table" then
    host_print(self, T("Nothing to copy."))
    return false
  end

  local url = tostring(resolved.url or "")
  if url == "" then
    host_print(self, T("Nothing to copy."))
    return false
  end

  local frame = self:EnsureSocialCopyFrame()
  if not frame then
    host_print(self, url)
    return false
  end

  frame.TitleText:SetText(tostring(resolved.label or T("Link")))
  frame.EditBox:SetText(url)
  frame.EditBox:SetCursorPosition(0)

  local accent = resolved.accent or BORDER_COLOR
  set_horizontal_gradient(frame.IconAccent, accent, ACCENT_RIGHT)
  if resolved.icon then
    frame.IconTexture:SetTexture(resolved.icon)
    frame.IconTexture:Show()
    frame.IconBadge:Hide()
  else
    frame.IconTexture:Hide()
    frame.IconBadge:SetText(tostring(resolved.badge or "?"))
    frame.IconBadge:Show()
  end

  frame:Show()
  frame:Raise()
  frame.EditBox:SetFocus()
  frame.EditBox:HighlightText()
  play_ui_sound(self, "popup_open")
  return true
end

function DevInfoModule:EnsurePanel()
  if self.panel_frame then
    return self.panel_frame
  end
  if type(CreateFrame) ~= "function" or not UIParent then
    return nil
  end

  local frame_name = self:GetFramePrefix() .. "DeveloperInfoFrame"
  local frame = CreateFrame("Frame", frame_name, UIParent, "BackdropTemplate")
  frame:SetSize(720, 472)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  set_backdrop(frame, PANEL_BG_COLOR, BORDER_COLOR)

  local shadow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 8)
  shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -8)
  set_backdrop(shadow, { 0, 0, 0, 0 }, { 0, 0, 0, 0.35 })
  shadow:SetFrameLevel(math.max(1, frame:GetFrameLevel() - 1))
  frame.Shadow = shadow

  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(44)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  local header_bg = header:CreateTexture(nil, "BACKGROUND")
  header_bg:SetAllPoints()
  header_bg:SetColorTexture(HEADER_BG_COLOR[1], HEADER_BG_COLOR[2], HEADER_BG_COLOR[3], HEADER_BG_COLOR[4])

  local header_accent = header:CreateTexture(nil, "ARTWORK")
  header_accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  header_accent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header_accent:SetHeight(2)
  set_horizontal_gradient(header_accent, ACCENT_LEFT, ACCENT_RIGHT)

  local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", header, "LEFT", 16, 0)
  title:SetTextColor(1, 1, 1)
  title:SetText(self.config.panel_title)
  frame.TitleText = title

  local close_button = create_close_button(header, function()
    frame:Hide()
    play_ui_sound(self, "popup_close")
  end)
  close_button:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  frame.CloseButton = close_button

  register_special_frame(frame)

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -56)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
  frame.Content = content

  local hero_panel = CreateFrame("Frame", nil, content)
  hero_panel:SetSize(224, 390)
  hero_panel:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -4)

  local hero_bg = hero_panel:CreateTexture(nil, "BACKGROUND")
  hero_bg:SetAllPoints()
  hero_bg:SetColorTexture(0.06, 0.07, 0.09, 0.95)

  local hero_accent = hero_panel:CreateTexture(nil, "BORDER")
  hero_accent:SetPoint("TOPLEFT", hero_panel, "TOPLEFT", 0, 0)
  hero_accent:SetPoint("TOPRIGHT", hero_panel, "TOPRIGHT", 0, 0)
  hero_accent:SetHeight(3)
  set_horizontal_gradient(hero_accent, ACCENT_LEFT, ACCENT_RIGHT)

  local portrait = hero_panel:CreateTexture(nil, "ARTWORK")
  portrait:SetSize(176, 176)
  portrait:SetPoint("TOP", hero_panel, "TOP", 0, -18)
  portrait:SetTexture(self.config.profile_texture)
  portrait:SetTexCoord(0.04, 0.96, 0.04, 0.96)

  local name_text = hero_panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  name_text:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -14)
  name_text:SetPoint("TOPRIGHT", portrait, "BOTTOMRIGHT", 0, -14)
  name_text:SetJustifyH("CENTER")
  name_text:SetTextColor(1, 1, 1)
  name_text:SetText(self.config.profile_name)

  local role_text = hero_panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  role_text:SetPoint("TOPLEFT", name_text, "BOTTOMLEFT", 0, -6)
  role_text:SetPoint("TOPRIGHT", name_text, "BOTTOMRIGHT", 0, -6)
  role_text:SetJustifyH("CENTER")
  role_text:SetTextColor(0.78, 0.83, 0.9)
  role_text:SetText(self.config.profile_title)

  local body_text = hero_panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  body_text:SetPoint("TOPLEFT", role_text, "BOTTOMLEFT", 4, -20)
  body_text:SetPoint("TOPRIGHT", role_text, "BOTTOMRIGHT", -4, -20)
  body_text:SetJustifyH("LEFT")
  body_text:SetJustifyV("TOP")
  body_text:SetTextColor(0.86, 0.88, 0.92)
  body_text:SetText(self.config.profile_body)

  local links_panel = CreateFrame("Frame", nil, content)
  links_panel:SetPoint("TOPLEFT", hero_panel, "TOPRIGHT", 22, -10)
  links_panel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -16, 14)

  frame.LinkButtons = {}
  for index, entry in ipairs(self.config.links) do
    local row = CreateFrame("Button", nil, links_panel)
    row:SetPoint("TOPLEFT", links_panel, "TOPLEFT", 0, -((index - 1) * 52))
    row:SetPoint("TOPRIGHT", links_panel, "TOPRIGHT", 0, -((index - 1) * 52))
    row:SetHeight(44)

    local accent = row:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(4)
    accent:SetColorTexture(entry.accent[1], entry.accent[2], entry.accent[3], 1)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", row, "TOPLEFT", 4, 0)
    bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0.07, 0.08, 0.11, 0.96)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", row, "TOPLEFT", 4, 0)
    highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    highlight:SetColorTexture(1, 1, 1, 0.05)

    local icon_frame = CreateFrame("Frame", nil, row)
    icon_frame:SetSize(28, 28)
    icon_frame:SetPoint("LEFT", row, "LEFT", 16, 0)
    local icon_bg = icon_frame:CreateTexture(nil, "BACKGROUND")
    icon_bg:SetAllPoints()
    icon_bg:SetColorTexture(0.12, 0.14, 0.18, 1)

    if entry.icon then
      local icon = icon_frame:CreateTexture(nil, "ARTWORK")
      icon:SetAllPoints()
      icon:SetTexture(entry.icon)
    else
      local badge = icon_frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      badge:SetPoint("CENTER")
      badge:SetTextColor(1, 1, 1)
      badge:SetText(entry.badge or "?")
    end

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", icon_frame, "TOPRIGHT", 14, -7)
    label:SetTextColor(1, 1, 1)
    label:SetText(entry.label)

    local info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    info:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    info:SetJustifyH("LEFT")
    info:SetTextColor(0.74, 0.79, 0.86)
    info:SetText(entry.tooltip)

    row:SetScript("OnClick", function()
      self:ShowCopyableSocialLink(entry)
    end)
    row:SetScript("OnEnter", function(button)
      GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
      GameTooltip:SetText(entry.label, 1, 1, 1)
      GameTooltip:AddLine(entry.tooltip, 0.84, 0.88, 0.94, true)
      GameTooltip:AddLine(T("Click to copy link"), 1.0, 0.82, 0.1)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    frame.LinkButtons[#frame.LinkButtons + 1] = row
  end

  frame:Hide()
  self.panel_frame = frame
  return frame
end

function DevInfoModule:ShowPanel()
  local frame = self:EnsurePanel()
  if not frame then
    return false
  end
  frame:Show()
  frame:Raise()
  play_ui_sound(self, "popup_open")
  return true
end

return DevInfoModule
