local addonName, ns = ...
---Libraries
local lib = LibStub("FerrozEditModeLib-1.0")
--Constants
local log = lib.Log --log function, handles only printing in debug mode
local UPDATE_THROTTLE = 0.05 -- Roughly 20 updates per second (super smooth)
--general ui
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")
local BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_FONT_FACE = "Fonts\\FRIZQT__.TTF"
local DEFAULT_WIDTH = 200
local DEFAULT_HEIGHT = 55
local POWER_BAR_HEIGHT = 5
local HEALTH_BAR_INTENSITY = 0.7
--private auras
local PRIVATE_AURA_CONTAINER_SIZE = 30
--debuffs
local DEBUFF_ICON_SIZE = 26
local DEBUFF_SPACING = 4
local DEBUFF_DEFAULT_COUNT = 5
local DEBUFF_MIN_COUNT = 0
local DEBUFF_MAX_COUNT = 10
local DEBUFF_AURA_FILTER = "HARMFUL"
--defensives
local BIG_DEFENSIVES_DEFAULT_COUNT =1
local BIG_DEFENSIVES_MIN_COUNT = 0
local BIG_DEFENSIVES_MAX_COUNT = 3
local BIG_DEFENSIVE_AURA_FILTER = "HELPFUL|BIG_DEFENSIVE"

local PRIVATE_AURAS_BACKGROUND_ALPHA = 0.5
local PRIVATE_AURAS_DEFAULT_COUNT = 4
local PRIVATE_AURAS_MIN_COUNT = 0
local PRIVATE_AURAS_MAX_COUNT = 10
local PRIVATE_AURAS_DEFAULT_SCALE_FACTOR = 1.5
local PRIVATE_AURAS_MIN_SCALE_FACTOR = 0.5
local PRIVATE_AURAS_MAX_SCALE_FACTOR = 3

--filter mode lists
local FILTER_MODES = {
    AURAS = "Private Auras",
    DEBUFFS = "All Debuffs",
    BOTH = "Both Debuffs and Private Auras"
}
local NEXT_FILTER_MODE = {
    [FILTER_MODES.AURAS] = FILTER_MODES.DEBUFFS,
    [FILTER_MODES.DEBUFFS] = FILTER_MODES.BOTH,
    [FILTER_MODES.BOTH] = FILTER_MODES.AURAS
}
local MOCK_PREVIEW_DEBUFF_ICONS = {
    132290, -- Sunder Armor (Warrior)
    132090, -- Weakened Armor (Generic)
    135904, -- Demoralizing Roar (Druid)
    136125, -- Thrash (Bleed)
    132155, -- Thunder Clap (Attack Speed Slow)
    136207, -- Faerie Fire (Armor Reduction)
    132104, -- Mortal Strike (Healing Reduction)
    136147, -- Rake (Bleed)
    135974, -- Blood Plague (DK Disease)
    136015, -- Frost Fever (DK Attack Speed Slow)
    132114, -- Rend (Warrior Bleed)
    136116, -- Infected Wounds (Movement Slow)
    135978, -- Scarlet Fever (Damage Reduction)
}
local MOCK_NAMES = {"Lord Doljonijiarnimorinar", "Lorem Ipsum Dolor", "M1 Abrams", "Iblameheals","TheArtistFormerlyKnownAsTank","LineOfSighted"}

--local values
local isTestMode = false

---------------------------------------------------------
-- HELPERS
---------------------------------------------------------
local function IsInEditMode()
    if C_EditMode and type(C_EditMode.IsEditModeActive) == "function" then
        return C_EditMode.IsEditModeActive()
    end
    return false
end

local function SettingNumber(key, default)
    local val = Co_Tank_Frame_Settings and Co_Tank_Frame_Settings[key]
    return tonumber(val) or default
end

---------------------------------------------------------
-- MIXINS 
---------------------------------------------------------
local Co_Tank_Frame_Mixin = {}
function Co_Tank_Frame_Mixin:FindCoTank()
    if isTestMode then return "player" end
    local groupType = IsInRaid() and "raid" or (IsInGroup() and "party")
    if not groupType then return nil end

    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = groupType..i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            if UnitGroupRolesAssigned(unit) == "TANK" then return unit end
        end
    end
    return nil
end

--values from current, settings or default
function Co_Tank_Frame_Mixin:RaidInstancesOnly()
    return self.raidInstancesOnly or SettingNumber("raidInstancesOnly", 0)
end
function Co_Tank_Frame_Mixin:AuraBackgroundAlpha()
    return self.auraBackgroundAlpha or SettingNumber("auraBackgroundAlpha", PRIVATE_AURAS_BACKGROUND_ALPHA)
end
function Co_Tank_Frame_Mixin:MaxShownPrivateAuras()
    return self.maxPrivateAuras or SettingNumber("maxPrivateAuras", PRIVATE_AURAS_DEFAULT_COUNT)
end
function Co_Tank_Frame_Mixin:MaxShownDebuffs()
    return self.maxDebuffs or SettingNumber("maxDebuffs", DEBUFF_DEFAULT_COUNT)
end
function Co_Tank_Frame_Mixin:MaxShownDefensives()
    return self.maxDefensives or SettingNumber("maxDefensives",BIG_DEFENSIVES_DEFAULT_COUNT)
end
function Co_Tank_Frame_Mixin:ScaleFactorPrivateAuras()
    return self.scaleFactorPrivateAuras or SettingNumber("scaleFactorPrivateAuras",PRIVATE_AURAS_DEFAULT_SCALE_FACTOR)
end
--boolean show if > 0
function Co_Tank_Frame_Mixin:ShowPrivateAuras()
    return self:MaxShownPrivateAuras() > 0
end
function Co_Tank_Frame_Mixin:ShowDebuffs()
    return self:MaxShownDebuffs() > 0
end
function Co_Tank_Frame_Mixin:ShowDefensives()
    return self:MaxShownDefensives() > 0
end

function Co_Tank_Frame_Mixin:ClearDebuffs()
    if self.debuffs then
        for i = 1, #self.debuffs do 
            self.debuffs[i]:SetAlpha(0)
            self.debuffs[i].icon:SetTexture(nil)
            self.debuffs[i].count:SetText("");
            self.debuffs[i].cd:SetCooldown(0,0)
        end
    end
end
function Co_Tank_Frame_Mixin:ClearBigDefensives()
    if self.bigDefensives then 
        for i = 1, #self.bigDefensives do
            self.bigDefensives[i]:SetAlpha(0)
            self.bigDefensives[i].icon:SetTexture(nil)
            self.bigDefensives[i].count:SetText("");
            self.bigDefensives[i].cd:SetCooldown(0,0)
        end
    end 
end

function Co_Tank_Frame_Mixin:UpdateBigDefensives()
    local unit = self:GetAttribute("unit")
    local isEditMode = IsInEditMode() or self.isEditing

    if not self:ShowDefensives() or not unit or not UnitExists(unit) or isEditMode then
        return
    end
    self:ClearBigDefensives()

    for auraIdx = 1, self:MaxShownDefensives() do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, auraIdx, BIG_DEFENSIVE_AURA_FILTER)
        
        if not aura then break end
        local iconFrame = self.bigDefensives[auraIdx]
        iconFrame.auraInstanceID = aura.auraInstanceID
        iconFrame.icon:SetTexture(aura.icon)
        iconFrame.count:SetFormattedText("%s", aura.applications)
        if(aura.applications) then
            iconFrame.count:SetAlpha(aura.applications)
        else
            iconFrame.count:SetAlpha(0)
        end
        if( iconFrame.cd.SetCooldownFromExpirationTime and type(iconFrame.cd.SetCooldownFromExpirationTime) == "function") then
            --iconFrame.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration)
        else
            iconFrame.cd:SetCooldown(0, 0) -- can't show it, shouldn't happen
        end
        iconFrame:SetAlpha(1)
    end

end

function Co_Tank_Frame_Mixin:UpdateDebuffs()
    local unit = self:GetAttribute("unit")
    local isEditMode = IsInEditMode() or self.isEditing

    if not self:ShowDebuffs() or not unit or not UnitExists(unit) or isEditMode then
        return
    end

    self:ClearDebuffs()--hide all

    for auraIdx = 1, self:MaxShownDebuffs() do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, auraIdx, DEBUFF_AURA_FILTER)
        if not aura then break end
        local iconFrame = self.debuffs[auraIdx]
        iconFrame.auraInstanceID = aura.auraInstanceID
        iconFrame.icon:SetTexture(aura.icon)
        iconFrame.count:SetFormattedText("%s", aura.applications)
        if(aura.applications) then
            iconFrame.count:SetAlpha(aura.applications)
        else
            iconFrame.count:SetAlpha(0)
        end
        if( iconFrame.cd.SetCooldownFromExpirationTime and type(iconFrame.cd.SetCooldownFromExpirationTime) == "function") then
            --iconFrame.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration)
        else
            iconFrame.cd:SetCooldown(0, 0) -- can't show it, shouldn't happen
        end
        iconFrame:SetAlpha(1)
    end

end

function Co_Tank_Frame_Mixin:UpdateHealthBarColor()
    local unit = self:GetAttribute("unit")
    local color
    if unit then
        local _, class = UnitClass(unit)

        if class then
            color = RAID_CLASS_COLORS[class]
        end
    end
    if color then
        self.health:SetStatusBarColor(color.r * HEALTH_BAR_INTENSITY, color.g * HEALTH_BAR_INTENSITY, color.b * HEALTH_BAR_INTENSITY)
    else
        self.health:SetStatusBarColor(0.5, 0.5, 0.5)
    end
end

function Co_Tank_Frame_Mixin:UpdateHealthText()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then 
        self.hpText:SetText("")
        return 
    end
    if(not self.isEditing ) then
        self:SetNameText(UnitName(unit))
    end
    --clears taint?
    if self.hpText.HasSecretValues and type(self.hpText.HasSecretValues) == "function" and self.hpText:HasSecretValues() then 
        self.hpText:SetToDefaults() 
    end

    -- Direct assignment only. Concatenation (..) is blocked in 12.0.
    local unitHealth
    if(AbbreviateLargeNumbers and type(AbbreviateLargeNumbers) == "function") then
        unitHealth = AbbreviateLargeNumbers(UnitHealth(unit))
    else 
        unitHealth = UnitHealth(unit)
    end
    local ok, unitHealthAsPercent
    if CurveConstants and CurveConstants.ScaleTo100 then
        ok, unitHealthAsPercent  = pcall(UnitHealthPercent, unit,false, CurveConstants.ScaleTo100)
    else
        ok, unitHealthAsPercent  = pcall(UnitHealthPercent, unit,false, true)
    end
    if(ok and unitHealthAsPercent ~= nil and unitHealth ~= nil) then 
        self.hpText:SetFormattedText("%s | %.0f%%", unitHealth, unitHealthAsPercent)
    elseif unitHealth then
        self.hpText:SetText(unitHealth)
    else
        self.hpText:SetText("??")
    end
end

function Co_Tank_Frame_Mixin:UpdateHealthBar()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    self.health:SetMinMaxValues(0, UnitHealthMax(unit))
    self.health:SetValue(UnitHealth(unit))
    self:UpdateHealthText()
end

function Co_Tank_Frame_Mixin:UpdatePower()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    local powerType, powerToken = UnitPowerType(unit)
    local p, maxP = UnitPower(unit), UnitPowerMax(unit)
    
    self.power:SetMinMaxValues(0, maxP)
    self.power:SetValue(p)

    -- Color the bar based on power type (Mana/Rage/Energy/etc)
    local color = PowerBarColor[powerToken] or PowerBarColor["MANA"]
    self.power:SetStatusBarColor(color.r, color.g, color.b)
end

function Co_Tank_Frame_Mixin:UpdateIconList(frameList, maxCount)
    if InCombatLockdown() or not frameList then return end
    for i, iconFrame in ipairs(frameList) do
        iconFrame:SetShown(i <= maxCount)
    end
end

function Co_Tank_Frame_Mixin:UpdateAndRefreshAuraAlpha(newVal)
    local diff = math.abs(self:AuraBackgroundAlpha() - newVal)
    local changed = diff > 0.0001
    self.auraBackgroundAlpha = newVal
    for i=1, #self.anchorFrames do
        local iconFrame = self.anchorFrames[i]
        iconFrame:SetBackdropColor(0, 0, 0, self:AuraBackgroundAlpha())
    end
    return changed
end

function Co_Tank_Frame_Mixin:UpdateAndRefreshAuraLayout(newVal)
    local changed = self:MaxShownPrivateAuras() ~= newVal
    self.maxPrivateAuras = newVal
    self:RefreshAuraLayout()
    return changed
end
function Co_Tank_Frame_Mixin:UpdateAndRefreshDebuffLayout(newVal)
    local changed = self:MaxShownDebuffs() ~= newVal
    self.maxDebuffs = newVal
    self:RefreshDebuffLayout()
    return changed
end
function Co_Tank_Frame_Mixin:UpdateAndRefreshDefensiveLayout(newVal)
    local changed = self:MaxShownDefensives() ~= newVal
    self.maxDefensives = newVal
    self:RefreshDefensiveLayout()
    return changed
end

function Co_Tank_Frame_Mixin:RefreshAuraLayout()
    self:UpdateIconList(self.anchorFrames, self:MaxShownPrivateAuras())
end
function Co_Tank_Frame_Mixin:RefreshDebuffLayout()
    self:UpdateIconList(self.debuffs, self:MaxShownDebuffs())
end
function Co_Tank_Frame_Mixin:RefreshDefensiveLayout()
    self:UpdateIconList(self.bigDefensives, self:MaxShownDefensives())
end

local function CreateIconFrame(iconList, iconSize, point, parent, relativePoint, ofsx, ofsy)
    local iconFrame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    iconFrame:SetFrameStrata("MEDIUM")
    iconFrame:SetMouseClickEnabled(true)
    iconFrame:SetSize(iconSize, iconSize)

    --BORDER (Using Backdrop for a perfect 1px line)
    iconFrame:SetBackdrop({
        edgeFile = BACKDROP_TEXTURE,
        edgeSize = 1,
    })
    iconFrame.border = iconFrame
    iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

    -- ICON
    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    --iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Zoom in slightly to remove default icon edges

    -- COOLDOWN
    iconFrame.cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.cd:SetAllPoints(iconFrame)
    iconFrame.cd:SetReverse(true) -- Darken the spent time, keep remaining time bright
    iconFrame.cd:SetHideCountdownNumbers(false)

    -- STACK COUNT
    iconFrame.count = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    iconFrame.count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 2, 0)

    -- Tooltip and Positioning logic remains the same...
    iconFrame:EnableMouse(true)
    iconFrame:SetScript("OnLeave", function() 
        GameTooltip:Hide()
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
    end)
    iconFrame:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local theFrame = parent:GetParent()
        local unit = theFrame:GetAttribute("unit")
        if unit and self.auraInstanceID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnitAura(unit, self.auraInstanceID)
            GameTooltip:Show()
        end
    end)

    local auraIdx = #iconList + 1
    if auraIdx == 1 then
        iconFrame:SetPoint(point, parent, relativePoint, ofsx, ofsy )
    else
        iconFrame:SetPoint("RIGHT", iconList[auraIdx-1], "LEFT", -1 * DEBUFF_SPACING, 0)
    end
    iconFrame:SetAlpha(0)
    iconList[auraIdx] = iconFrame
end

function Co_Tank_Frame_Mixin:CreateDebuffContainer()
    self.debuffs = {}
    for i = 1, DEBUFF_MAX_COUNT do
        local iconFrame = CreateIconFrame(self.debuffs,DEBUFF_ICON_SIZE, "TOPRIGHT", self,"BOTTOMRIGHT", 0, 0)
    end
    self:RefreshDebuffLayout()
end
function Co_Tank_Frame_Mixin:CreateDefensiveontainer()
    if InCombatLockdown() or self.bigDefensives then return end
    self.bigDefensives = {}
    for i = 1, BIG_DEFENSIVES_MAX_COUNT do
        local bigDefensiveIconSize = DEFAULT_HEIGHT - POWER_BAR_HEIGHT - 16
        local iconFrame = CreateIconFrame(self.bigDefensives,bigDefensiveIconSize,"RIGHT", self.health, "RIGHT", -1 * DEBUFF_SPACING, -2 )
    end
    self:RefreshDefensiveLayout()
end

function Co_Tank_Frame_Mixin:CreatePrivateAnchorContainers()
    if InCombatLockdown() or self.anchorFrames then return end
    self.anchorFrames = {}
    local scaleFactor = self:ScaleFactorPrivateAuras()
    for i = 1, PRIVATE_AURAS_MAX_COUNT do
        -- Visible container for the border
        local container = CreateFrame("Frame", nil, self, "BackdropTemplate")
        container:SetSize(PRIVATE_AURA_CONTAINER_SIZE,PRIVATE_AURA_CONTAINER_SIZE)
        container:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground", -- Standard solid textur
        })
        container:SetBackdropColor(0, 0, 0, self:AuraBackgroundAlpha()) -- Semi-transparent black

        local auraAnchor = CreateFrame("Frame", nil, container)
        auraAnchor:SetAllPoints(container)
        if i == 1 then
            container:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 0)
        else
            container:SetPoint("RIGHT", self.anchorFrames[i-1], "LEFT", -DEBUFF_SPACING, 0)
        end
        self.anchorFrames[i] = container
        self.anchorFrames[i]:SetAlpha(1)
        self.anchorFrames[i]:SetScale(scaleFactor)
    end
    self:RefreshAuraLayout()--sets show/hide based on the user's configuration
end

function Co_Tank_Frame_Mixin:AttachPrivateAnchors()
    local unit = self:GetAttribute("unit")
    self:CleanupPrivateAnchors()
    self:RefreshAuraLayout()
    if not unit or not self:IsVisible() or not self:ShowPrivateAuras() then return end

    self.privateAnchorIDs = self.privateAnchorIDs or {}
    self.anchorFrames = self.anchorFrames or {}

    for i = 1, #self.anchorFrames do
        local anchorData = {
            unitToken = unit,
            auraIndex = i,
            parent = self.anchorFrames[i],
            showCountdownFrame = false, -- sweep + default centered text
            showCountdownNumbers = false,--default centered text
            isContainer = false,
            durationAnchor = { -- custom text without sweep, shifted up
                point = "BOTTOM",
                relativeTo = self.anchorFrames[i],
                relativePoint = "TOP",
                offsetX = 0,
                offsetY = 2,
            },
            iconInfo = {
                iconWidth = PRIVATE_AURA_CONTAINER_SIZE - 2,
                iconHeight = PRIVATE_AURA_CONTAINER_SIZE - 2,
                iconAnchor = {
                    point = "BOTTOM",
                    relativeTo = self.anchorFrames[i],
                    relativePoint = "BOTTOM",
                    offsetX = 0,
                    offsetY = 0,
                },
            }
        }

        local anchorID = C_UnitAuras.AddPrivateAuraAnchor(anchorData)
        if anchorID then
            table.insert(self.privateAnchorIDs, anchorID)
        end
    end
end

function Co_Tank_Frame_Mixin:CleanupPrivateAnchors()
    if self.privateAnchorIDs then
        for _, anchorID in ipairs(self.privateAnchorIDs) do
            C_UnitAuras.RemovePrivateAuraAnchor(anchorID)
        end
        self.privateAnchorIDs = {}
    end
end

-- Called when the unit attribute changes (Binding Logic)
function Co_Tank_Frame_Mixin:OnAttributeChanged(name, value)
    if name == "unit" then
        self:UnregisterAllEvents() -- Clear old unit tracking
        local watchUnit = isTestMode and "player" or value
        if watchUnit then
            self:RegisterUnitEvent("UNIT_HEALTH", watchUnit)
            self:RegisterUnitEvent("UNIT_MAXHEALTH", watchUnit)
            self:RegisterUnitEvent("UNIT_POWER_UPDATE", watchUnit)
            self:RegisterUnitEvent("UNIT_MAXPOWER", watchUnit)
            self:RegisterUnitEvent("UNIT_DISPLAYPOWER", watchUnit)
            self:RegisterUnitEvent("UNIT_AURA", watchUnit)
            self:AttachPrivateAnchors()
            self:UpdateVisuals()
        else
            if not isTestMode then
                self:SetNameText("NO CO-TANK")
            end
            self.health:SetValue(0)
            self.power:SetValue(0)
            for i = 1, #self.debuffs do self.debuffs[i]:SetAlpha(0) end
            self:CleanupPrivateAnchors()
        end
    end
end

function Co_Tank_Frame_Mixin:OnSizeChangedHandler(width, height)
    self:FitNameToWidth()
end

function Co_Tank_Frame_Mixin:SetNameText(nameText)
    self.nameText.rawText = nameText
    self.nameText:SetText(nameText)
    self:FitNameToWidth()
end   
function Co_Tank_Frame_Mixin:FitNameToWidth()
    local maxWidth = self:GetWidth() - 8 -- 4px padding on each side
    self.nameText:SetText(self.nameText.rawText)
    if self.nameText:GetStringWidth() > maxWidth then
        -- We loop backwards from the end of the string to find the sweet spot
        local textLen = string.len(self.nameText.rawText)
        for i = textLen, 1, -1 do
            local substring = string.sub(self.nameText.rawText, 1, i) .. "..."
            self.nameText:SetText(substring)
            if self.nameText:GetStringWidth() <= maxWidth then
                break
            end
        end
    end
end

function Co_Tank_Frame_Mixin:UpdateVisuals(event, unused_unit, info)
    if event == "UNIT_AURA" and info then
        if not info.isFullUpdate and not info.addedAuras and not info.updatedAuras and not info.removedAuraInstanceIDs then
            return
        end
    end
    if not self.isEditing then
        local now = GetTime()
        if (self.nextUpdate or 0) > now then
            return
        end
        self.nextUpdate = now + UPDATE_THROTTLE
    end

    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    self:UpdateHealthBar()
    self:UpdatePower()
    self:UpdateDebuffs()
    self:UpdateBigDefensives()

    if self.isEditing then return end
    local name = UnitName(unit)
    if name then
        self:SetNameText(name)
    end
end

function Co_Tank_Frame_Mixin:UpdateMedia(mediaType, state)
    if mediaType == "statusbar" then return self:UpdateTextures(state) end
    if mediaType == "font" then return self:UpdateFonts(state) end
    --ignore any others
end

function Co_Tank_Frame_Mixin:UpdateTextures(state)
    state = state or self.workingState
    if not state or not state.barTexture then return false end

    -- Apply Texture to Health and Power bars
    local changed = self.health.statusBarTextureString ~= state.barTexture
        or self.power.statusBarTextureString ~= state.barTexture

    self.health.statusBarTextureString =state.barTexture
    self.health:SetStatusBarTexture(self.health.statusBarTextureString)
    self.power.statusBarTextureString = state.barTexture
    self.power:SetStatusBarTexture(self.power.statusBarTextureString)
    --visual refresh
    self:UpdateHealthBar()
    self:UpdatePower()
    return changed
end

function Co_Tank_Frame_Mixin:UpdateFonts(state)
    state = state or self.workingState
    if not state or not state.fontFace then return false end
    -- Apply Font to Name and health Text
    local changed = false
    if self.nameText then
        local currentFontPath, size, flags = self.nameText:GetFont()
        changed = (currentFontPath ~= state.fontFace) or changed
        self.nameText:SetFont(state.fontFace, size, flags)
    end
    if self.hpText then
        local currentFontPath, size, flags = self.hpText:GetFont()
        changed = (currentFontPath ~= state.fontFace) or changed
        self.hpText:SetFont(state.fontFace, size, flags)
    end
    return changed
end

function Co_Tank_Frame_Mixin:EditModeStartMock()
    if InCombatLockdown() then return end
    -- Stop listening to the real tank while editing
    self:UnregisterAllEvents()
    UnregisterUnitWatch(self)
    self:SetAttribute("unit", "player") 
    self:SetNameText(MOCK_NAMES[math.random(#MOCK_NAMES)])
    self:ClearDebuffs()
    --mock debuffs
    for i = 1, math.min(#self.debuffs,#MOCK_PREVIEW_DEBUFF_ICONS) do
        local iconFrame = self.debuffs[i]
        local borderFrame = iconFrame.border or iconFrame
        iconFrame.icon:SetTexture(MOCK_PREVIEW_DEBUFF_ICONS[i])
        iconFrame.count:SetText(i == 1 and "3" or "")
        iconFrame.cd:SetCooldown(GetTime(), math.random(10, 60))
        iconFrame:SetAlpha(1)
    end
    for i=1, #self.bigDefensives do
        local iconFrame = self.bigDefensives[i]
        iconFrame:Hide()--hide on edit so they don't intercept mouse clicks
    end
    --Private auras can't be mocked.  
    self:UpdateHealthBar()
    self:UpdatePower()
    self:Show()
end

function Co_Tank_Frame_Mixin:EditModeStopMock()
    -- Put back the default background color
    self:UpdateHealthBarColor()
    self:ClearDebuffs()
    for i=1, #self.bigDefensives do
        local iconFrame = self.bigDefensives[i]
        iconFrame:Show()
    end
    RegisterUnitWatch(self)
    if not InCombatLockdown() then
        local realTank = self:FindCoTank()
        self:SetAttribute("unit", realTank)
        --Give the 12.0 engine a moment to 'unlock' the tank data
        C_Timer.After(0.1, function()
            self:UpdateVisuals()
        end)
    end
end

function Co_Tank_Frame_Mixin:GetOrCreateFrameSpecificControls(socket)
    if not self.frameSpecificPlugin then
        local state = Co_Tank_Frame_Settings or {}
        local p = CreateFrame("Frame", nil, self, "VerticalLayoutFrame")
        p.fixedWidth = lib.CONFIG_FRAME_WIDTH
        p.spacing = lib.CONFIG_ROW_SPACING 
        self.frameSpecificPlugin = p
        self.extraControls = {}
        lib:AddHR(p)
        self.extraControls.barTexture = lib:CreateMediaSelector(p, "Bar Texture", "barTexture","statusbar", lib.CONFIG_ROW_LABEL_WIDTH *2)
        if state.barTexture then
            local name = lib:GetMediaNameFromPath("statusbar", state.barTexture)
            self.extraControls.barTexture:SetText(name)
        end
        self.extraControls.fontFace = lib:CreateMediaSelector(p, "Font", "fontFace","font",lib.CONFIG_ROW_LABEL_WIDTH * 2)
        if state.fontFace then
            local name = lib:GetMediaNameFromPath("font", state.fontFace)
            self.extraControls.fontFace:SetText(name)
        end
        
        --display in instances only 
        self.raidInstancesOnly = SettingNumber("raidInstancesOnly", 0)
        self.extraControls.raidInstancesOnly = lib:CreateSliderRow(p, "TBD", "raidInstancesOnly", 0, 1, 1, lib.CONFIG_ROW_LABEL_WIDTH * 2)
        self.extraControls.raidInstancesOnly.slider:SetValue(self.raidInstancesOnly)
        --auras
        self.auraBackgroundAlpha = SettingNumber("auraBackgroundAlpha", PRIVATE_AURAS_BACKGROUND_ALPHA)
        self.extraControls.auraBackgroundAlpha = lib:CreateSliderRow(p, "Aura BG", "auraBackgroundAlpha", 0.0, 1.0, 0.05, lib.CONFIG_ROW_LABEL_WIDTH * 2)
        self.extraControls.auraBackgroundAlpha.slider:SetValue(self.auraBackgroundAlpha)
        self.maxPrivateAuras = SettingNumber("maxPrivateAuras", PRIVATE_AURAS_DEFAULT_COUNT)
        self.extraControls.maxPrivateAuras = lib:CreateSliderRow(p, "# Auras", "maxPrivateAuras", PRIVATE_AURAS_MIN_COUNT, PRIVATE_AURAS_MAX_COUNT, 1, lib.CONFIG_ROW_LABEL_WIDTH * 2)
        self.extraControls.maxPrivateAuras.slider:SetValue(self.maxPrivateAuras)
        --debuffs
        self.maxDebuffs = SettingNumber("maxDebuffs", DEBUFF_DEFAULT_COUNT)
        self.extraControls.maxDebuffs = lib:CreateSliderRow(p, "# Debuffs", "maxDebuffs", DEBUFF_MIN_COUNT, DEBUFF_MAX_COUNT, 1,lib.CONFIG_ROW_LABEL_WIDTH * 2)
        self.extraControls.maxDebuffs.slider:SetValue(self.maxDebuffs)
        --defensives
        self.maxDefensives = SettingNumber("maxDefensives",BIG_DEFENSIVES_DEFAULT_COUNT)
        self.extraControls.maxDefensives = lib:CreateSliderRow(p, "# Defensives", "maxDefensives", BIG_DEFENSIVES_MIN_COUNT, BIG_DEFENSIVES_MAX_COUNT, 1, lib.CONFIG_ROW_LABEL_WIDTH * 2)
        self.extraControls.maxDefensives.slider:SetValue(self.maxDefensives)
        p:Layout()
    end
    return self.extraControls, self.frameSpecificPlugin
end

function Co_Tank_Frame_Mixin:CommitFrameSpecificFields()
    if not self.workingState then return end
    Co_Tank_Frame_Settings.barTexture = self.workingState.barTexture
    Co_Tank_Frame_Settings.fontFace = self.workingState.fontFace
    Co_Tank_Frame_Settings.raidInstancesOnly = self.raidInstancesOnly
    Co_Tank_Frame_Settings.auraBackgroundAlpha = self.workingState.auraBackgroundAlpha
    Co_Tank_Frame_Settings.maxPrivateAuras = self.workingState.maxPrivateAuras
    Co_Tank_Frame_Settings.maxDebuffs = self.workingState.maxDebuffs
    Co_Tank_Frame_Settings.maxDefensives = self.workingState.maxDefensives
    lib:Log("Committed frame specific settings for Tank Frame")
end

function Co_Tank_Frame_Mixin:UpdateFromState(state)
    local changed = false
    if state.barTexture then
        changed = self:UpdateMedia("statusbar",state) or changed
    end
    if state.fontFace then
        changed =  self:UpdateMedia("font",state) or changed
    end
    if state.raidInstancesOnly then
        changed = (self:RaidInstancesOnly() ~= state.raidInstancesOnly ) or changed
        self.raidInstancesOnly = state.raidInstancesOnly
    end
    if state.auraBackgroundAlpha then
        changed = self:UpdateAndRefreshAuraAlpha(state.auraBackgroundAlpha) or changed
    end
    if state.maxPrivateAuras then
        changed = self:UpdateAndRefreshAuraLayout(state.maxPrivateAuras) or changed
    end
    if state.maxDebuffs then
        changed = self:UpdateAndRefreshDebuffLayout(state.maxDebuffs) or changed
    end
    if state.maxDefensives then
        changed = self:UpdateAndRefreshDefensiveLayout(state.maxDefensives) or changed
    end
    self:FitNameToWidth()
    return changed
end

function Co_Tank_Frame_Mixin:GetFrameSpecificSnapshot()
    local currentTexture = self.health:GetStatusBarTexture():GetTexture()
    local currentTextureString = self.health.statusBarTextureString or [[Interface\Buttons\WHITE8X8]]
    local fontPath, fontSize, fontFlags = self.nameText:GetFont()
    local state = Co_Tank_Frame_Settings or {}

    return {
        barTexture = currentTextureString,
        fontFace = fontPath,
        raidInstancesOnly = self:RaidInstancesOnly(),
        auraBackgroundAlpha = self:AuraBackgroundAlpha(),
        maxPrivateAuras = self:MaxShownPrivateAuras(),
        maxDebuffs = self:MaxShownDebuffs(),
        maxDefensives = self:MaxShownDefensives(),
    }
end

function Co_Tank_Frame_Mixin:OnConfigRefresh(configFrame, state)
    local controls = configFrame.frameSpecificControls
    if controls then
        if controls.barTexture and state.barTexture then
            local name = lib:GetMediaNameFromPath("statusbar", state.barTexture)
            controls.barTexture:SetText(name)
        end
        if controls.fontFace and state.fontFace then
            local name = lib:GetMediaNameFromPath("font", state.fontFace)
            controls.fontFace:SetText(name)
        end
        if controls.raidInstancesOnly and state.raidInstancesOnly then
            controls.raidInstancesOnly.slider:SetValue(state.raidInstancesOnly)
        end
        if controls.auraBackgroundAlpha and state.auraBackgroundAlpha then
            controls.auraBackgroundAlpha.slider:SetValue(state.auraBackgroundAlpha)
        end
        if controls.maxPrivateAuras and state.maxPrivateAuras then
            controls.maxPrivateAuras.slider:SetValue(state.maxPrivateAuras)
        end
        if controls.maxDebuffs and state.maxDebuffs then
            controls.maxDebuffs.slider:SetValue(state.maxDebuffs)
        end
        if controls.maxDefensives and state.maxDefensives then
            controls.maxDefensives.slider:SetValue(state.maxDefensives)
        end
    end
end

---------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------
local function InitializeCotankFrame()
    -- Initialize settings if they don't exist
    Co_Tank_Frame_Settings = Co_Tank_Frame_Settings or {}
    Co_Tank_Frame_Settings.layouts = Co_Tank_Frame_Settings.layouts or {}
    Co_Tank_Frame_Settings.filterMode = nil -- drop this 

    if InCombatLockdown() then return end -- can't initialize during combat
    local frame = CreateFrame("Button", "Co_Tank_Frame", UIParent, "SecureUnitButtonTemplate, BackdropTemplate, EditModeSystemTemplate")
    frame:SetAttribute("type1", "target") -- Left click = Target
    frame:SetAttribute("type2", "togglemenu") -- Right click = Menu 

    Mixin(frame, Co_Tank_Frame_Mixin)
    
    -- Visual Setup
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    --backgroundTexture
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    frame:SetBackdrop({edgeFile = BACKDROP_TEXTURE, edgeSize = 1})
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    -- Health bar
    frame.health = CreateFrame("StatusBar", nil, frame)
    frame.health:SetPoint("TOPLEFT", 1, -1)
    frame.health:SetPoint("BOTTOMRIGHT", -1, POWER_BAR_HEIGHT + 2) -- Raised by height + 2px gap
    frame.health.statusBarTextureString = Co_Tank_Frame_Settings.barTexture or BACKDROP_TEXTURE
    frame.health:SetStatusBarTexture(frame.health.statusBarTextureString)
    -- Power Bar
    frame.power = CreateFrame("StatusBar", nil, frame)
    frame.power:SetHeight(POWER_BAR_HEIGHT) -- Thin, modern look
    frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -1)
    frame.power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.power.statusBarTextureString = Co_Tank_Frame_Settings.barTexture or BACKDROP_TEXTURE
    frame.power:SetStatusBarTexture(frame.power.statusBarTextureString)
    -- Power Background
    frame.powerBG = frame.power:CreateTexture(nil, "BACKGROUND")
    frame.powerBG:SetAllPoints()
    frame.powerBG:SetColorTexture(0, 0, 0, 0.5)

    -- Name Text (row 1)
    frame.nameText = frame.health:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    frame.nameText:SetFont(Co_Tank_Frame_Settings.fontFace or DEFAULT_FONT_FACE, 14, "OUTLINE")
    frame.nameText:SetPoint("BOTTOMLEFT", frame.health, "LEFT", 6, 4) -- Nudged up
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetIgnoreParentAlpha(false)

    -- HP Text (row 2 2)
    frame.hpText = frame.health:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    frame.hpText:SetFont(Co_Tank_Frame_Settings.fontFace or DEFAULT_FONT_FACE, 12, "OUTLINE")
    frame.hpText:SetPoint("TOPLEFT", frame.health, "LEFT", 6, -4) -- Nudged down
    frame.hpText:SetJustifyH("LEFT")
    frame.hpText:SetTextColor(0.9, 0.9, 0.9)
    frame.hpText:SetIgnoreParentAlpha(false)

    --initialize/create debuffs, defensives and private aura anchorpoints
    frame:CreateDebuffContainer()
    frame:CreateDefensiveontainer()
    frame:CreatePrivateAnchorContainers()
    --Scripts
    frame:SetScript("OnAttributeChanged", frame.OnAttributeChanged)
    frame:SetScript("OnSizeChanged", function(s, w, h) s:OnSizeChangedHandler(w, h) end)
    frame:SetScript("OnEvent", frame.UpdateVisuals)
    frame:SetScript("OnShow", function(self)
        self:UpdateHealthBarColor()
        self:AttachPrivateAnchors()
    end)
    frame:SetScript("OnHide", function(self)
        self:CleanupPrivateAnchors()
    end)

    --Register with FerrozEditModeLib
    if lib then
        lib:Register(frame, Co_Tank_Frame_Settings,{height=DEFAULT_HEIGHT,width=DEFAULT_WIDTH})
    end

    

    -- External State Controller (Manager)
    local manager = CreateFrame("Frame")
    manager:RegisterEvent("GROUP_ROSTER_UPDATE")
    manager:RegisterEvent("PLAYER_REGEN_ENABLED")
    manager:RegisterEvent("PLAYER_ENTERING_WORLD")
    manager:SetScript("OnEvent", function(self, event)
        if not InCombatLockdown() then
            --todo maybe handle gracefully initializing if you happen to log in and are already in combat lockdown.  TBD march/april
            if not frame.anchorFrames then
                frame:CreatePrivateAnchorContainers()
            end
            local myRole = UnitGroupRolesAssigned("player")
            local currentTank = frame:FindCoTank()
            if myRole == "TANK" and currentTank then
                frame:SetAttribute("unit", currentTank)
                RegisterUnitWatch(frame) -- Engine handles showing it
            else
                UnregisterUnitWatch(frame)
                frame:Hide()
                frame:SetAttribute("unit", nil)
                --force always test mode
                --frame:SetAttribute("unit", "player")
                --frame:Show()
                --RegisterUnitWatch(frame)
            end
            if lib then
                lib:ApplyLayout(frame)
            end
            frame:UpdateHealthBarColor()
            frame:UpdateVisuals()
            frame:RefreshAuraLayout()
            frame:RefreshDebuffLayout()
            frame:RefreshDefensiveLayout()
        end
    end)

    -- Support for Clique and other click-casting addons
    _G["ClickCastFrames"] = _G["ClickCastFrames"] or {}
    _G["ClickCastFrames"][frame] = true

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"
    print(FERROZ_COLOR:WrapTextInColorCode("[CoTank] v" .. version) .. " loaded (/cotank)")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        InitializeCotankFrame()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

---------------------------------------------------------
-- MAIN SLASH COMMAND
---------------------------------------------------------
SLASH_COTANK1 = "/cotank"
SlashCmdList["COTANK"] = function(msg)
    local cmd, arg = string.split(" ", msg)
    cmd = cmd and cmd:lower() or ""
    if cmd == "reset" then
        Co_Tank_Frame:UpdateVisuals()
        if lib and lib.ResetPosition then
            lib:ResetPosition(Co_Tank_Frame)
        end
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Settings and position have been reset.")
    elseif cmd == "test" then
        isTestMode = not isTestMode
        local status = isTestMode and GREEN_FONT_COLOR:WrapTextInColorCode("ON") or RED_FONT_COLOR:WrapTextInColorCode("OFF")
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Test Mode is " .. status)

        if Co_Tank_Frame then
            if isTestMode then
                UnregisterUnitWatch(Co_Tank_Frame)
                Co_Tank_Frame:SetAttribute("unit", "player")
                Co_Tank_Frame:Show()
            else
                local tankUnit = Co_Tank_Frame:FindCoTank()
                Co_Tank_Frame:SetAttribute("unit", tankUnit)
                RegisterUnitWatch(Co_Tank_Frame)
            end
            Co_Tank_Frame:UpdateVisuals()
        end
        if Co_Tank_Frame.UpdateDebuffs then Co_Tank_Frame:UpdateDebuffs() end
    else
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank Commands"))
        print("  /cotank reset - Resets frame position")
    end
end