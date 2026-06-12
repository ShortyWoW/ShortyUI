local _, ns = ...

local BuffBarIconMode = {}
ns.BuffBarIconMode = BuffBarIconMode

local unpack = unpack or table.unpack

local LSM_font = LibStub and LibStub("LibSharedMedia-3.0", true)
local BASE_SQUARE_MASK = "Interface\\AddOns\\CooldownManagerCentered\\Media\\Art\\Square"
local DEFAULT_MASK_TEXTURE = "Interface\\AddOns\\CooldownManagerCentered\\Media\\Art\\CooldownManager"

function BuffBarIconMode.GetMode()
    local profile = ns.db and ns.db.profile
    if not profile then
        return "OFF"
    end
    local setting = profile.cooldownManager_alignBuffBars_growFromDirection
    if setting == "ICONS_VERTICAL" then
        return "VERTICAL"
    elseif setting == "ICONS_HORIZONTAL" then
        return "HORIZONTAL"
    end
    return "OFF"
end

function BuffBarIconMode.IsEnabled()
    return BuffBarIconMode.GetMode() ~= "OFF"
end

function BuffBarIconMode.IsHorizontal()
    return BuffBarIconMode.GetMode() == "HORIZONTAL"
end

local function IsSquare()
    return ns.db.profile.cooldownManager_squareIcons_BuffIcons == true
end

local function GetBorderThickness(frame)
    if not IsSquare() then
        return 1
    end
    local raw = ns.db.profile.cooldownManager_squareIconsBorder_BuffIcons or 4
    if raw > 0 and ns.Scaling then
        return ns.Scaling:GetPixelSize(frame) * raw
    end
    return raw > 0 and raw or 0
end

local function GetZoom()
    return ns.db.profile.cooldownManager_squareIconsZoom_BuffIcons or 0
end

local BUFF_ICON_DEFAULT_SIZE = 35
local BUFF_ICON_DEFAULT_SQUARE_SIZE = 40
local function GetTargetIconSize()
    local square = IsSquare()
    local size = BUFF_ICON_DEFAULT_SIZE
    if square then
        size = BUFF_ICON_DEFAULT_SQUARE_SIZE
    end
    local width = size
    local height = size
    if ns.db.profile.cooldownManager_experimental_enableRectangularIcons_buffIcons then
        local pct = ns.db.profile.cooldownManager_experimental_enableRectangularIcons_buffIcons_percent or 0.8
        height = math.floor(height * pct)
    end
    return width, height
end

local function GetBuffBarParts(frame)
    local iconHost = frame and (frame.Icon or frame.icon)
    local bar = frame and (frame.Bar or frame.bar)
    local iconTexture

    if iconHost then
        iconHost:Show()
        iconTexture = iconHost.Icon or iconHost.icon
        if not iconTexture and iconHost.IsObjectType and iconHost:IsObjectType("Texture") then
            iconTexture = iconHost
        end
    end

    return iconHost, iconTexture, bar
end

local function GetIconTexTarget(iconHost, iconTexture)
    if iconTexture and iconTexture ~= iconHost then
        return iconTexture
    end
    if iconHost and iconHost.IsObjectType and iconHost:IsObjectType("Texture") then
        return iconHost
    end
    return nil
end

local function GetBuffIconDefaultFontPath(fontName)
    return ns.API:GetFontPath(fontName) or ns.CONSTANTS.DEFAULT_FONT[1]
end

local function ApplyFontStyling(frame)
    if not BuffBarIconMode.IsEnabled() or not ns.db or not ns.db.profile then
        return
    end
    local p = ns.db.profile
    local iconHost = GetBuffBarParts(frame)
    local borderLevel = (frame.cmcBorder and frame.cmcBorder:GetFrameLevel())
        or ((iconHost and iconHost:GetFrameLevel() or frame:GetFrameLevel()) + 4)

    -- local cooldownFS = frame.Bar.Duration
    local stackFS = frame.Icon.Applications

    -- if frame.Bar then
    --     frame.Bar:SetFrameLevel(borderLevel + 1)
    -- end
    -- if frame.Bar.Name then
    --     frame.Bar.Name:Hide()
    -- end

    -- if cooldownFS then
    --     cooldownFS:Hide()
    -- end

    -- Apply cooldown font to _CMC_Cooldown's countdown FontString
    if frame._CMC_Cooldown and frame._CMC_Cooldown.GetCountdownFontString then
        local cdFS = frame._CMC_Cooldown:GetCountdownFontString()
        if cdFS and p.cooldownManager_cooldownFontSizeBuffIcons_enabled then
            local size = p.cooldownManager_cooldownFontSizeBuffIcons
            if size == "NIL" then
                size = 16
            end
            if size == 0 then
                cdFS:SetFontHeight(0)
            else
                if not size then
                    size = select(2, cdFS:GetFont()) or 16
                end
                local fontName = p.cooldownManager_cooldownFontName
                local fontFlags = p.cooldownManager_cooldownFontFlags
                cdFS:SetFont(GetBuffIconDefaultFontPath(fontName), size, ns.API:GetFontFlags(fontFlags))
            end
        end
    end

    if stackFS and p.cooldownManager_stackAnchorBuffIcons_enabled then
        local fp, fsz, ffl = unpack(ns.Stacks.defaultUtilityAndBuffStackFont)
        local size = p.cooldownManager_stackFontSizeBuffIcons
        if size == "NIL" or not size then
            size = fsz
        end
        local point = p.cooldownManager_stackAnchorBuffIcons_point or ns.CONSTANTS.FONT.DEFAULT_STACK_POINT
        local offsetX = p.cooldownManager_stackAnchorBuffIcons_offsetX
        if offsetX == nil then
            offsetX = ns.CONSTANTS.FONT.DEFAULT_STACK_OFFSET_X
        end
        local offsetY = p.cooldownManager_stackAnchorBuffIcons_offsetY
        if offsetY == nil then
            offsetY = ns.CONSTANTS.FONT.DEFAULT_STACK_OFFSET_Y
        end
        stackFS:SetFontObject("NumberFontNormal")
        local fontName = p.cooldownManager_stackFontName
        local fontFlags = p.cooldownManager_stackFontFlags or {}
        local flags = ns.API:GetFontFlags(fontFlags)
        if size == 0 then
            stackFS:SetFontHeight(0)
        else
            local stackFontPath = ns.API:GetFontPath(fontName) or fp
            stackFS:SetFont(stackFontPath, size, flags)
        end
        if not frame._cmcStackAnchor then
            frame._cmcStackAnchor = CreateFrame("Frame", nil, frame)
        end
        frame._cmcStackAnchor:SetAllPoints(frame)
        frame._cmcStackAnchor:SetFrameLevel(borderLevel + 5)

        stackFS:SetParent(frame._cmcStackAnchor)

        stackFS:SetJustifyV("MIDDLE")
        stackFS:ClearAllPoints()
        stackFS:SetPoint(point, frame._cmcStackAnchor, point, offsetX, offsetY)
        stackFS:SetDrawLayer("OVERLAY", 7)
        stackFS:SetSize(30, size)
        stackFS:SetJustifyH("CENTER")
        if point:find("RIGHT") then
            stackFS:SetJustifyH("RIGHT")
        elseif point:find("LEFT") then
            stackFS:SetJustifyH("LEFT")
        end
    elseif stackFS then
        stackFS:SetFontObject("NumberFontNormalSmall")
        if not frame._cmcStackAnchor then
            frame._cmcStackAnchor = CreateFrame("Frame", nil, frame)
        end
        frame._cmcStackAnchor:SetAllPoints(frame)
        frame._cmcStackAnchor:SetFrameLevel(borderLevel + 5)

        stackFS:SetParent(frame._cmcStackAnchor)
        stackFS:SetJustifyH("RIGHT")
        stackFS:SetJustifyV("MIDDLE")
        stackFS:ClearAllPoints()
        stackFS:SetPoint(
            ns.CONSTANTS.FONT.DEFAULT_STACK_POINT,
            frame._cmcStackAnchor,
            ns.CONSTANTS.FONT.DEFAULT_STACK_POINT,
            ns.CONSTANTS.FONT.DEFAULT_STACK_OFFSET_X,
            ns.CONSTANTS.FONT.DEFAULT_STACK_OFFSET_Y
        )

        stackFS:SetDrawLayer("OVERLAY", 7)
        stackFS:SetSize(30, fsz)
    end
end

local function ApplyIconStyling(frame, iconHost, iconTexture)
    if not iconHost then
        return
    end

    local square = IsSquare()
    local zoom = GetZoom()
    local crop = zoom * 0.5
    local texTarget = GetIconTexTarget(iconHost, iconTexture)

    if texTarget and texTarget.SetTexCoord then
        if square then
            texTarget:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        else
            texTarget:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    local bt = square and GetBorderThickness(frame) or 0
    if not frame.cmcBorder then
        frame.cmcBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.cmcBorder:SetFrameLevel(iconHost:GetFrameLevel() + 10)
    end
    frame.cmcBorder:ClearAllPoints()
    frame.cmcBorder:SetAllPoints(iconHost)
    if square and bt > 0 then
        frame.cmcBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = bt })
        frame.cmcBorder:SetBackdropBorderColor(0, 0, 0, 1)
        frame.cmcBorder:Show()
    else
        frame.cmcBorder:Hide()
    end

    if iconHost and iconHost.GetRegions then
        frame._cmcHiddenIconHostRegions = frame._cmcHiddenIconHostRegions or {}
        frame._cmcReplacedMaskRegions = frame._cmcReplacedMaskRegions or {}
        for _, region in ipairs({ iconHost:GetRegions() }) do
            if region:IsObjectType("Texture") then
                local tex = region.GetTexture and region:GetTexture()
                local atlas = region.GetAtlas and region:GetAtlas()
                local isMask = (not issecretvalue or not issecretvalue(tex)) and tex == 6707800
                    or atlas == "UI-HUD-CoolDownManager-Mask"
                local isOverlay = (not issecretvalue or not issecretvalue(tex)) and tex == 6739577
                    or atlas == "UI-HUD-CoolDownManager-IconOverlay"
                if isMask then
                    if square then
                        if not frame._cmcReplacedMaskRegions[region] then
                            frame._cmcReplacedMaskRegions[region] = tex
                        end
                        region:SetTexture(BASE_SQUARE_MASK)
                    else
                        region:SetTexture(DEFAULT_MASK_TEXTURE)
                    end
                elseif isOverlay then
                    if square then
                        if not frame._cmcHiddenIconHostRegions[region] then
                            frame._cmcHiddenIconHostRegions[region] = region:GetAlpha()
                        end
                        region:SetAlpha(0)
                    else
                        if frame._cmcHiddenIconHostRegions[region] then
                            region:SetAlpha(frame._cmcHiddenIconHostRegions[region])
                            frame._cmcHiddenIconHostRegions[region] = nil
                        end
                        local _w, _h = frame:GetSize()
                        local _ratio = (_w and _h and _w > 0) and (_h / _w) or 1.0
                        region:ClearAllPoints()
                        region:SetPoint("TOPLEFT", iconHost, "TOPLEFT", -9, 8 * _ratio)
                        region:SetPoint("BOTTOMRIGHT", iconHost, "BOTTOMRIGHT", 9, -8 * _ratio)
                    end
                end
            end
        end
    end
end

local function EnsureBackup(frame)
    if not frame or frame._cmcBuffBarIconBackup then
        return
    end

    local iconHost, iconTexture = GetBuffBarParts(frame)
    local hiddenState = {}

    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= iconHost and child ~= iconTexture then
            hiddenState[child] = child:IsShown()
        end
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region ~= iconHost and region ~= iconTexture then
            hiddenState[region] = region:IsShown()
        end
    end

    frame._cmcBuffBarIconBackup = {
        hiddenState = hiddenState,
    }
end

local function UpdateCMCCooldown(frame)
    if not frame._CMC_Cooldown then
        return
    end

    if frame.auraInstanceID then
        local cdframe = frame._CMC_Cooldown
        if cdframe then
            local durationObj = C_UnitAuras.GetAuraDuration("player", frame.auraInstanceID)
            if durationObj ~= nil then
                cdframe:SetCooldownFromDurationObject(durationObj)
            end
        end
    end
end

local function EnsureCMCCooldown(frame)
    local iconHost = frame.Icon or frame.icon
    local isSquare = IsSquare()

    if frame._CMC_Cooldown then
        frame._CMC_Cooldown:ClearAllPoints()
        frame._CMC_Cooldown:SetAllPoints(iconHost)
        if isSquare then
            frame._CMC_Cooldown:SetSwipeTexture(BASE_SQUARE_MASK)
        else
            frame._CMC_Cooldown:SetSwipeTexture(DEFAULT_MASK_TEXTURE)
        end
        return
    end
    local parent = iconHost or frame
    local baseLevel = parent:GetFrameLevel()

    local cdframe = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cdframe:SetDrawEdge(false)
    cdframe:SetDrawBling(false)
    cdframe:SetReverse(true)
    if isSquare then
        cdframe:SetSwipeTexture(BASE_SQUARE_MASK)
    else
        cdframe:SetSwipeTexture(DEFAULT_MASK_TEXTURE)
    end
    cdframe:SetHideCountdownNumbers(false)
    cdframe:SetFrameLevel(baseLevel + 5)
    cdframe:ClearAllPoints()
    cdframe:SetAllPoints(iconHost)

    frame._CMC_Cooldown = cdframe
    local function onCooldownUpdate(self)
        UpdateCMCCooldown(self)
    end

    for _, hookName in ipairs({
        "OnUnitAuraAddedEvent",
        "OnUnitAuraRemovedEvent",
        "OnUnitAuraUpdatedEvent",
        "OnActiveStateChanged",
        "OnAuraInstanceInfoSet",
        "RefreshData",
    }) do
        if type(frame[hookName]) == "function" then
            hooksecurefunc(frame, hookName, onCooldownUpdate)
        end
    end
end

function BuffBarIconMode.Apply(frame)
    if not frame then
        return
    end

    local iconHost, iconTexture, bar = GetBuffBarParts(frame)
    if not iconHost then
        return
    end

    EnsureBackup(frame)
    EnsureCMCCooldown(frame)

    local targetWidth, targetHeight = GetTargetIconSize()

    local backup = frame._cmcBuffBarIconBackup
    if backup and backup.hiddenState then
        for region in pairs(backup.hiddenState) do
            if region and region.Hide then
                region:Hide()
            end
        end
    end

    if bar then
        bar:SetAlpha(0)
        if bar.Show then
            bar:Show()
        end
    end

    frame:SetSize(targetWidth, targetHeight)
    iconHost:SetSize(targetWidth, targetHeight)
    iconHost:ClearAllPoints()
    iconHost:SetPoint("CENTER", frame, "CENTER", 0, 0)

    ApplyIconStyling(frame, iconHost, iconTexture)
    ApplyFontStyling(frame)
end

function BuffBarIconMode.Restore(frame)
    local backup = frame and frame._cmcBuffBarIconBackup
    if not backup then
        return
    end

    local settings = BuffBarCooldownViewer.settingMap
    local opacity = settings[Enum.EditModeCooldownViewerSetting.Opacity]
    local barWidthScale = (50 + settings[Enum.EditModeCooldownViewerSetting.BarWidthScale].value) / 100
    local iconHost, iconTexture, bar = GetBuffBarParts(frame)

    local isIconHidden = settings[Enum.EditModeCooldownViewerSetting.BarContent].value == 2
    frame:SetSize(220 * barWidthScale, 30)
    iconHost:SetSize(30, 30)
    iconHost:ClearAllPoints()
    iconHost:SetPoint("LEFT", frame, "LEFT", 0, 0)
    if isIconHidden and iconHost.Hide then
        iconHost:Hide()
    end

    bar:SetAlpha(1)

    if backup.hiddenState then
        for region, wasShown in pairs(backup.hiddenState) do
            if region and region.Show and region.Hide then
                if wasShown then
                    region:Show()
                else
                    region:Hide()
                end
            end
        end
    end

    local texTarget = GetIconTexTarget(iconHost, iconTexture)
    if texTarget and texTarget.SetTexCoord then
        texTarget:SetTexCoord(0, 1, 0, 1)
    end

    if frame._cmcBarIconMask and frame._cmcBarIconMaskTarget then
        if frame._cmcBarIconMaskTarget.RemoveMaskTexture then
            frame._cmcBarIconMaskTarget:RemoveMaskTexture(frame._cmcBarIconMask)
        end
        frame._cmcBarIconMask = nil
        frame._cmcBarIconMaskTarget = nil
    end

    if frame.cmcBorder then
        frame.cmcBorder:Hide()
    end

    if frame._cmcReplacedMaskRegions then
        for region, originalTex in pairs(frame._cmcReplacedMaskRegions) do
            region:SetTexture(originalTex)
        end
        frame._cmcReplacedMaskRegions = nil
    end

    if frame._cmcHiddenIconHostRegions then
        for region, alpha in pairs(frame._cmcHiddenIconHostRegions) do
            region:SetAlpha(alpha)
        end
        frame._cmcHiddenIconHostRegions = nil
    end
end

function BuffBarIconMode.RefreshAll(barFrames)
    if not barFrames then
        return
    end
    local enabled = BuffBarIconMode.IsEnabled()
    for _, frame in ipairs(barFrames) do
        if enabled then
            if frame:IsShown() and frame:IsVisible() then
                BuffBarIconMode.Apply(frame)
            end
        elseif frame._cmcBuffBarIconBackup then
            BuffBarIconMode.Restore(frame)
        end
    end
end
