local _, ns = ...
local Affected = ns.API.Affected

local BuffBarIconMode = {}
ns.BuffBarIconMode = BuffBarIconMode

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
    local borderLevel = (Affected(frame).border and Affected(frame).border:GetFrameLevel())
        or ((iconHost and iconHost:GetFrameLevel() or frame:GetFrameLevel()) + 4)

    local stackFS = frame.Icon.Applications

    if frame.Cooldown and frame.Cooldown.GetCountdownFontString then
        local cdFS = frame.Cooldown:GetCountdownFontString()
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
        -- Buff bars in icon mode share the Buff Icons countdown text offset, and
        -- the same Buff Icons "Override Font" gate. Off (or 0/0) restores the
        -- default centered position.
        if cdFS then
            local enabled = p.cooldownManager_cooldownFontSizeBuffIcons_enabled
            local ox = enabled and (p.cooldownManager_cooldownTextBuffIcons_offsetX or 0) or 0
            local oy = enabled and (p.cooldownManager_cooldownTextBuffIcons_offsetY or 0) or 0
            if ox ~= 0 or oy ~= 0 then
                cdFS:ClearAllPoints()
                cdFS:SetPoint("CENTER", frame.Cooldown, "CENTER", ox, oy)
                ns.API:SetAffected(frame, "cooldowntextpos")
            elseif ns.API:GetIsAffected(frame, "cooldowntextpos") then
                cdFS:ClearAllPoints()
                cdFS:SetPoint("CENTER", frame.Cooldown, "CENTER", 0, 0)
                ns.API:UnsetAffected(frame, "cooldowntextpos")
            end
        end
    end

    local fp, fsz = unpack(ns.Stacks.defaultUtilityAndBuffStackFont, 1, 2)
    if stackFS and p.cooldownManager_stackAnchorBuffIcons_enabled then
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
        if not frame.Applications then
            frame.Applications = {}
        end
        if not frame.Applications.Applications then
            frame.Applications.Applications = CreateFrame("Frame", nil, frame)
        end
        frame.Applications.Applications:SetAllPoints(frame)
        frame.Applications.Applications:SetFrameLevel(borderLevel + 5)

        stackFS:SetParent(frame.Applications.Applications)

        stackFS:SetJustifyV("MIDDLE")
        stackFS:ClearAllPoints()
        stackFS:SetPoint(point, frame.Applications.Applications, point, offsetX, offsetY)
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
        if not frame.Applications then
            frame.Applications = {}
        end
        if not frame.Applications.Applications then
            frame.Applications.Applications = CreateFrame("Frame", nil, frame)
        end
        frame.Applications.Applications:SetAllPoints(frame)
        frame.Applications.Applications:SetFrameLevel(borderLevel + 5)

        stackFS:SetParent(frame.Applications.Applications)
        stackFS:SetJustifyH("RIGHT")
        stackFS:SetJustifyV("MIDDLE")
        stackFS:ClearAllPoints()
        stackFS:SetPoint(
            ns.CONSTANTS.FONT.DEFAULT_STACK_POINT,
            frame.Applications.Applications,
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
    if not Affected(frame).border then
        Affected(frame).border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        Affected(frame).border:SetFrameLevel(iconHost:GetFrameLevel() + 10)
    end
    Affected(frame).border:ClearAllPoints()
    Affected(frame).border:SetAllPoints(iconHost)
    if square and bt > 0 then
        Affected(frame).border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = bt })
        Affected(frame).border:SetBackdropBorderColor(0, 0, 0, 1)
        Affected(frame).border:Show()
    else
        Affected(frame).border:Hide()
    end

    if iconHost and iconHost.GetRegions then
        Affected(frame).hiddenIconHostRegions = Affected(frame).hiddenIconHostRegions or {}
        Affected(frame).replacedMaskRegions = Affected(frame).replacedMaskRegions or {}
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
                        if not Affected(frame).replacedMaskRegions[region] then
                            Affected(frame).replacedMaskRegions[region] = tex
                        end
                        region:SetTexture(BASE_SQUARE_MASK)
                    else
                        region:SetTexture(DEFAULT_MASK_TEXTURE)
                    end
                elseif isOverlay then
                    if square then
                        if not Affected(frame).hiddenIconHostRegions[region] then
                            Affected(frame).hiddenIconHostRegions[region] = region:GetAlpha()
                        end
                        region:SetAlpha(0)
                    else
                        if Affected(frame).hiddenIconHostRegions[region] then
                            region:SetAlpha(Affected(frame).hiddenIconHostRegions[region])
                            Affected(frame).hiddenIconHostRegions[region] = nil
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
    if not frame or Affected(frame).buffBarIconBackup then
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

    Affected(frame).buffBarIconBackup = {
        hiddenState = hiddenState,
    }
end

local function UpdateCMCCooldown(frame)
    if not frame.Cooldown then
        return
    end

    if frame.auraInstanceID then
        local cdframe = frame.Cooldown
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

    if frame.Cooldown then
        frame.Cooldown:Show()
        frame.Cooldown:ClearAllPoints()
        frame.Cooldown:SetAllPoints(iconHost)
        if isSquare then
            frame.Cooldown:SetSwipeTexture(BASE_SQUARE_MASK)
        else
            frame.Cooldown:SetSwipeTexture(DEFAULT_MASK_TEXTURE)
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
        cdframe:SetSwipeTexture(BASE_SQUARE_MASK) ---@diagnostic disable-line: missing-parameter
    else
        cdframe:SetSwipeTexture(DEFAULT_MASK_TEXTURE) ---@diagnostic disable-line: missing-parameter
    end
    cdframe:SetHideCountdownNumbers(false)
    cdframe:SetFrameLevel(baseLevel + 5)
    cdframe:ClearAllPoints()
    cdframe:SetAllPoints(iconHost)

    frame.Cooldown = cdframe
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

    local backup = Affected(frame).buffBarIconBackup
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
    local backup = frame and Affected(frame).buffBarIconBackup

    if frame.Cooldown then
        frame.Cooldown:Hide()
    end

    if not backup then
        return
    end

    local settings = BuffBarCooldownViewer.settingMap
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

    if Affected(frame).barIconMask and Affected(frame).barIconMaskTarget then
        if Affected(frame).barIconMaskTarget.RemoveMaskTexture then
            Affected(frame).barIconMaskTarget:RemoveMaskTexture(Affected(frame).barIconMask)
        end
        Affected(frame).barIconMask = nil
        Affected(frame).barIconMaskTarget = nil
    end

    if Affected(frame).border then
        Affected(frame).border:Hide()
    end

    if Affected(frame).replacedMaskRegions then
        for region, originalTex in pairs(Affected(frame).replacedMaskRegions) do
            region:SetTexture(originalTex)
        end
        Affected(frame).replacedMaskRegions = nil
    end

    if Affected(frame).hiddenIconHostRegions then
        for region, alpha in pairs(Affected(frame).hiddenIconHostRegions) do
            region:SetAlpha(alpha)
        end
        Affected(frame).hiddenIconHostRegions = nil
    end

    if frame.Applications and frame.Applications.Applications and frame.Icon and frame.Icon.Applications then
        local stackFS = frame.Icon.Applications

        stackFS:SetFontObject("NumberFontNormalSmall")
        stackFS:SetParent(frame.Icon)
        stackFS:SetJustifyH("RIGHT")
        stackFS:SetJustifyV("MIDDLE")
        stackFS:ClearAllPoints()
        stackFS:SetSize(30, 10)
        stackFS:SetPoint(
            ns.CONSTANTS.FONT.DEFAULT_STACK_POINT,
            frame.Icon,
            ns.CONSTANTS.FONT.DEFAULT_STACK_POINT,
            -5,
            5
        )
        frame.Applications = nil
    end
end

function BuffBarIconMode.RefreshAll(barFrames)
    if not barFrames then
        return
    end
    local enabled = BuffBarIconMode.IsEnabled()
    for _, frame in ipairs(barFrames) do
        if enabled then
            BuffBarIconMode.Apply(frame)
        elseif Affected(frame).buffBarIconBackup then
            BuffBarIconMode.Restore(frame)
        end
    end
end
