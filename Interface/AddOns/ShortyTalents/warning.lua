-- warning.lua
-- Modern warning overlay for ShortyTalents (ElvUI/Discord inspired)

local ADDON_NAME = ...
local ST = _G.ShortyTalents
if not ST then return end

local WarnFrame
local hideTimerHandle

-- Visual constants (tweak as desired)
local PANEL_W, PANEL_H = 620, 120
local SHOW_Y_OFFSET = 240
local HIDE_SECONDS = 8

-- Discord-ish accents
local ACCENT_R, ACCENT_G, ACCENT_B = 0.35, 0.40, 0.95  -- blurple-ish
local BG_R, BG_G, BG_B, BG_A       = 0.07, 0.08, 0.10, 0.88
local BORDER_R, BORDER_G, BORDER_B, BORDER_A = 0.20, 0.22, 0.26, 1.0

local WHITE8X8 = "Interface\\Buttons\\WHITE8x8"

local function CancelHideTimer()
  if hideTimerHandle then
    hideTimerHandle:Cancel()
    hideTimerHandle = nil
  end
end

local function CreateBorderLine(parent, point, rel, x, y, w, h)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetTexture(WHITE8X8)
  t:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, BORDER_A)
  t:SetPoint(point, rel, point, x, y)
  t:SetSize(w, h)
  return t
end

local function EnsureWarnFrame()
  if WarnFrame then return end

  WarnFrame = CreateFrame("Frame", "ShortyTalentsWarnFrame", UIParent)
  WarnFrame:SetSize(PANEL_W, PANEL_H)
  WarnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, SHOW_Y_OFFSET)
  WarnFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  WarnFrame:SetFrameLevel(1000)
  WarnFrame:SetClampedToScreen(true)

  -- Close button (top-right)
  WarnFrame.close = CreateFrame("Button", nil, WarnFrame, "UIPanelCloseButton")
  WarnFrame.close:SetPoint("TOPRIGHT", WarnFrame, "TOPRIGHT", -4, -4)
  WarnFrame.close:SetFrameStrata("FULLSCREEN_DIALOG")
  WarnFrame.close:SetFrameLevel(WarnFrame:GetFrameLevel() + 10)
  WarnFrame.close:SetScript("OnClick", function()
    WarnFrame:Hide()
  end)

  WarnFrame:EnableMouse(true)

  -- Background panel
  WarnFrame.bg = WarnFrame:CreateTexture(nil, "BACKGROUND")
  WarnFrame.bg:SetAllPoints(WarnFrame)
  WarnFrame.bg:SetTexture(WHITE8X8)
  WarnFrame.bg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

  -- Border (4 thin lines)
  WarnFrame.borderTop    = CreateBorderLine(WarnFrame, "TOPLEFT",     WarnFrame, 0, 0, PANEL_W, 1)
  WarnFrame.borderBottom = CreateBorderLine(WarnFrame, "BOTTOMLEFT",  WarnFrame, 0, 0, PANEL_W, 1)
  WarnFrame.borderLeft   = CreateBorderLine(WarnFrame, "TOPLEFT",     WarnFrame, 0, 0, 1, PANEL_H)
  WarnFrame.borderRight  = CreateBorderLine(WarnFrame, "TOPRIGHT",    WarnFrame, 0, 0, 1, PANEL_H)

  -- Accent bar (top)
  WarnFrame.accent = WarnFrame:CreateTexture(nil, "ARTWORK")
  WarnFrame.accent:SetTexture(WHITE8X8)
  WarnFrame.accent:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1.0)
  WarnFrame.accent:SetPoint("TOPLEFT", WarnFrame, "TOPLEFT", 0, 0)
  WarnFrame.accent:SetPoint("TOPRIGHT", WarnFrame, "TOPRIGHT", 0, 0)
  WarnFrame.accent:SetHeight(4)

  -- Icon (simple exclamation)
  WarnFrame.icon = WarnFrame:CreateTexture(nil, "ARTWORK")
  WarnFrame.icon:SetSize(28, 28)
  WarnFrame.icon:SetPoint("LEFT", WarnFrame, "LEFT", 18, 0)
  WarnFrame.icon:SetAtlas("ui-hud-unitframes-combatindicator") -- compact warning-like icon
  WarnFrame.icon:SetDesaturated(true)
  WarnFrame.icon:SetVertexColor(1.0, 0.35, 0.35, 1.0)

  -- Title
  WarnFrame.title = WarnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  WarnFrame.title:SetPoint("TOPLEFT", WarnFrame, "TOPLEFT", 60, -14)
  WarnFrame.title:SetText("|cffff5a5aWARNING|r")

  -- Activity + loadout lines
  WarnFrame.line1 = WarnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  WarnFrame.line1:SetPoint("TOPLEFT", WarnFrame.title, "BOTTOMLEFT", 0, -10)
  WarnFrame.line1:SetJustifyH("LEFT")

  WarnFrame.line2 = WarnFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  WarnFrame.line2:SetPoint("TOPLEFT", WarnFrame.line1, "BOTTOMLEFT", 0, -6)
  WarnFrame.line2:SetJustifyH("LEFT")

  -- Detail (only really useful in debug mode)
  WarnFrame.detail = WarnFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  WarnFrame.detail:SetPoint("BOTTOMLEFT", WarnFrame, "BOTTOMLEFT", 60, 10)
  WarnFrame.detail:SetJustifyH("LEFT")
  WarnFrame.detail:SetText("")

  -- Countdown bar
  WarnFrame.timerBar = CreateFrame("StatusBar", nil, WarnFrame)
  WarnFrame.timerBar:SetStatusBarTexture(WHITE8X8)
  WarnFrame.timerBar:SetPoint("BOTTOMLEFT", WarnFrame, "BOTTOMLEFT", 0, 0)
  WarnFrame.timerBar:SetPoint("BOTTOMRIGHT", WarnFrame, "BOTTOMRIGHT", 0, 0)
  WarnFrame.timerBar:SetHeight(3)
  WarnFrame.timerBar:SetMinMaxValues(0, HIDE_SECONDS)
  WarnFrame.timerBar:SetValue(HIDE_SECONDS)
  WarnFrame.timerBar:SetStatusBarColor(ACCENT_R, ACCENT_G, ACCENT_B, 1.0)

  -- Animation (fade + slight slide)
  WarnFrame.anim = WarnFrame:CreateAnimationGroup()

  WarnFrame.fadeIn = WarnFrame.anim:CreateAnimation("Alpha")
  WarnFrame.fadeIn:SetFromAlpha(0)
  WarnFrame.fadeIn:SetToAlpha(1)
  WarnFrame.fadeIn:SetDuration(1)
  WarnFrame.fadeIn:SetSmoothing("OUT")

  WarnFrame.slideIn = WarnFrame.anim:CreateAnimation("Translation")
  WarnFrame.slideIn:SetOffset(0, -16)
  WarnFrame.slideIn:SetDuration(25)
  WarnFrame.slideIn:SetSmoothing("OUT")

  WarnFrame:SetAlpha(0)

  -- Click to dismiss
  WarnFrame:SetScript("OnMouseDown", function()
    WarnFrame:Hide()
  end)

  -- OnUpdate for countdown bar
  WarnFrame._endAt = nil
  WarnFrame:SetScript("OnUpdate", function(self)
    if not self._endAt then return end
    local remaining = self._endAt - GetTime()
    if remaining < 0 then remaining = 0 end
    self.timerBar:SetValue(remaining)
  end)

  WarnFrame:Hide()
end

function ST.HideWarning()
  if not WarnFrame then return end
  CancelHideTimer()
  WarnFrame._endAt = nil
  WarnFrame:Hide()
end

-- Public API: ST.ShowWarning(activity, loadoutName, detail)
function ST.ShowWarning(activity, loadoutName, detail)
  EnsureWarnFrame()
  CancelHideTimer()

  local a = activity or "Unknown Activity"
  local l = loadoutName or "Unknown Loadout"

  WarnFrame.line1:SetText(("Activity: |cffffffaa%s|r"):format(a))
  WarnFrame.line2:SetText(("Current Loadout: |cffffffff%s|r"):format(l))

  -- Only show reason details when debug is enabled
  if ST.debug and detail and detail ~= "" then
    WarnFrame.detail:SetText(("(%s)"):format(detail))
    WarnFrame.detail:Show()
  else
    WarnFrame.detail:SetText("")
    WarnFrame.detail:Hide()
  end

  WarnFrame.timerBar:SetMinMaxValues(0, HIDE_SECONDS)
  WarnFrame.timerBar:SetValue(HIDE_SECONDS)
  WarnFrame._endAt = GetTime() + HIDE_SECONDS

  WarnFrame:Show()
  WarnFrame.anim:Stop()
  WarnFrame:SetAlpha(0)
  WarnFrame.anim:Play()

  WarnFrame:Show()
  WarnFrame.anim:Stop()
  WarnFrame:SetAlpha(0)
  WarnFrame.anim:Play()

  -- Alert sound (default WoW sound)
  PlaySound(SOUNDKIT.RAID_WARNING, "Master")


  hideTimerHandle = C_Timer.NewTimer(HIDE_SECONDS, function()
    if WarnFrame then
      WarnFrame._endAt = nil
      ST.HideWarning()
    end
    hideTimerHandle = nil
  end)
end

-- Optional quick test:
-- /run ShortyTalents.ShowWarning("Dungeons","Raid ST","zone_changed")