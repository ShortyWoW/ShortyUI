local _, ns = ...

local CooldownFont = {}
ns.CooldownFont = CooldownFont

local Stacks = {}
ns.Stacks = Stacks

local unpack = unpack or table.unpack

local LSM = LibStub("LibSharedMedia-3.0", true)

local viewersSettingKey = {
    EssentialCooldownViewer = "Essential",
    UtilityCooldownViewer = "Utility",
    BuffIconCooldownViewer = "BuffIcons",
}

local function GetFontPath(fontName)
    if not fontName or fontName == "" then
        return nil
    end
    if LSM then
        local fontPath = LSM:Fetch("font", fontName)
        if fontPath then
            return fontPath
        end
    end
    return nil
end

local function GetConfiguredFontPath(fontName, viewerName, defaults)
    local fontPath = GetFontPath(fontName)
    if fontPath then
        return fontPath
    end
    if defaults and defaults[1] then
        return defaults[1]
    end
    return ns.CONSTANTS.DEFAULT_FONT_PATH
end

-- Cooldown number font

local function GetViewerCooldownSettings(viewerName)
    local map = {
        EssentialCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeEssential,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeEssential_enabled,
            default = ns.CONSTANTS.FONT.ESSENTIAL_ICON_DEFAULT_COOLDOWN_FONT_SIZE,
        },
        UtilityCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeUtility,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeUtility_enabled,
            default = ns.CONSTANTS.FONT.UTILITY_ICON_DEFAULT_COOLDOWN_FONT_SIZE,
        },
        BuffIconCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeBuffIcons,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeBuffIcons_enabled,
            default = ns.CONSTANTS.FONT.BUFF_ICON_DEFAULT_COOLDOWN_FONT_SIZE,
        },
    }
    local cfg = map[viewerName]
    if not cfg then
        return nil, false, nil
    end
    return cfg.size, cfg.enabled, cfg.default
end

local function SetIconCooldownFont(icon, viewerName)
    if icon.Cooldown.GetCountdownFontString then
        local fontString = icon.Cooldown:GetCountdownFontString()
        if not fontString then
            return
        end
        -- Capture original font before first modification
        if not icon._cmcCooldownFontBackup then
            local fp, fsz, ffl = fontString:GetFont()
            if fp and fsz and fsz > 0 then
                icon._cmcCooldownFontBackup = { fp, fsz, ffl or "" }
            end
        end
        local size, enabled, _size = GetViewerCooldownSettings(viewerName)
        if not enabled then
            if fontString.defaults then
                fontString:SetFont(unpack(fontString.defaults))
            else
                fontString:SetFont(ns.CONSTANTS.DEFAULT_FONT_PATH, _size, "OUTLINE")
            end
            return
        end
        if size == "NIL" then
            size = _size
        end
        if size == 0 then
            fontString:SetFontHeight(0)
            return
        end
        if not size then
            size = select(2, fontString:GetFont()) or _size
        end

        local fontName = ns.db.profile.cooldownManager_cooldownFontName
        if not fontString.defaults then
            local fp, fsz, ffl = fontString:GetFont()
            fontString.defaults = { fp, fsz, ffl or "" }
        end
        local fontPath = GetConfiguredFontPath(fontName, viewerName, fontString.defaults)
        local fontFlags = ns.db.profile.cooldownManager_cooldownFontFlags or {}
        local fontFlag = {}
        for n, v in pairs(fontFlags) do
            if v == true then
                table.insert(fontFlag, n)
            end
        end
        fontString:SetFont(fontPath, size, table.concat(fontFlag, ","))
    end
end

local function ProcessCooldownFontViewer(viewerName)
    local viewer = _G[viewerName]
    if not viewer or not ns.Runtime:IsReady(viewerName) then
        return
    end
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        if child.Icon and child.Cooldown then
            SetIconCooldownFont(child, viewerName)
        end
    end
end

function CooldownFont:RefreshViewer(viewerName)
    ProcessCooldownFontViewer(viewerName)
end

function CooldownFont:RefreshAll()
    for viewerName in pairs(viewersSettingKey) do
        ProcessCooldownFontViewer(viewerName)
    end
end

function CooldownFont:Initialize()
    self:RefreshAll()
end

-- Stack count font

local function GetViewerStackSettings(viewerName, forceDefaults)
    local map = {
        EssentialCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeEssential,
            enabled = ns.db.profile.cooldownManager_stackAnchorEssential_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorEssential_point,
            x = ns.db.profile.cooldownManager_stackAnchorEssential_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorEssential_offsetY,
            default = ns.CONSTANTS.FONT.ESSENTIAL_ICON_DEFAULT_STACK_FONT_SIZE,
            defaultPoint = ns.CONSTANTS.FONT.ESSENTIAL_ICON_DEFAULT_STACK_POINT,
            defaultX = ns.CONSTANTS.FONT.ESSENTIAL_ICON_DEFAULT_STACK_OFFSET_X,
            defaultY = ns.CONSTANTS.FONT.ESSENTIAL_ICON_DEFAULT_STACK_OFFSET_Y,
        },
        UtilityCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeUtility,
            enabled = ns.db.profile.cooldownManager_stackAnchorUtility_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorUtility_point,
            x = ns.db.profile.cooldownManager_stackAnchorUtility_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorUtility_offsetY,
            default = ns.CONSTANTS.FONT.UTILITY_ICON_DEFAULT_STACK_FONT_SIZE,
            defaultPoint = ns.CONSTANTS.FONT.UTILITY_ICON_DEFAULT_STACK_POINT,
            defaultX = ns.CONSTANTS.FONT.UTILITY_ICON_DEFAULT_STACK_OFFSET_X,
            defaultY = ns.CONSTANTS.FONT.UTILITY_ICON_DEFAULT_STACK_OFFSET_Y,
        },
        BuffIconCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeBuffIcons,
            enabled = ns.db.profile.cooldownManager_stackAnchorBuffIcons_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorBuffIcons_point,
            x = ns.db.profile.cooldownManager_stackAnchorBuffIcons_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorBuffIcons_offsetY,
            default = ns.CONSTANTS.FONT.BUFF_ICON_DEFAULT_STACK_FONT_SIZE,
            defaultPoint = ns.CONSTANTS.FONT.BUFF_ICON_DEFAULT_STACK_POINT,
            defaultX = ns.CONSTANTS.FONT.BUFF_ICON_DEFAULT_STACK_OFFSET_X,
            defaultY = ns.CONSTANTS.FONT.BUFF_ICON_DEFAULT_STACK_OFFSET_Y,
        },
    }
    local cfg = map[viewerName]
    if not cfg then
        return nil, false, "BOTTOMRIGHT", 0, 0
    end
    if forceDefaults then
        return cfg.default, cfg.enabled, cfg.defaultPoint, cfg.defaultX, cfg.defaultY
    end
    return cfg.size or cfg.default,
        cfg.enabled,
        (cfg.point or cfg.defaultPoint or "BOTTOMRIGHT"),
        (cfg.x ~= nil and cfg.x or cfg.defaultX or 0),
        (cfg.y ~= nil and cfg.y or cfg.defaultY or 0)
end

local function ApplyStackFont(fontString, size, viewerName)
    if not fontString then
        return
    end
    if not fontString.defaults then
        local fp, fsz, ffl = fontString:GetFont()
        fontString.defaults = { fp, fsz, ffl or "" }
    end

    local fontName = ns.db and ns.db.profile and ns.db.profile.cooldownManager_stackFontName
    local fontPath = GetConfiguredFontPath(fontName, viewerName, fontString.defaults)

    local fontFlags = ns.db.profile.cooldownManager_stackFontFlags or {}
    local fontFlag = {}
    for n, v in pairs(fontFlags) do
        if v == true then
            table.insert(fontFlag, n)
        end
    end
    if size == 0 then
        fontString:SetFontHeight(0)
        return
    end
    if not size or size == "NIL" then
        size = fontString.defaults[2] or 14
    end

    fontString:SetFont(fontPath, size, table.concat(fontFlag, ","))
end

function Stacks:RestoreStackPositions(viewerName)
    local viewer = _G[viewerName]
    if not viewer then
        return
    end
    local children = { viewer:GetChildren() }
    local fontSize, _, stackPoint, stackX, stackY = GetViewerStackSettings(viewerName, true)
    for _, child in ipairs(children) do
        local fs = child and child.Applications and child.Applications.Applications
            or child.ChargeCount and child.ChargeCount.Current
        if fs and child._cmc_affected and child._cmc_affected.stack then
            fs:ClearAllPoints()
            fs:SetPoint(stackPoint, child, stackPoint, stackX, stackY)
            if fs.defaults then
                fs:SetFont(unpack(fs.defaults))
            else
                fs:SetFont(ns.CONSTANTS.DEFAULT_STACK_FONT_PATH, fontSize, "OUTLINE")
            end
        end
    end
end

function Stacks:ApplyStackFonts(viewerName)
    local viewer = _G[viewerName]
    if not viewer then
        return
    end
    local fontSize, stackEnabled, stackPoint, stackX, stackY = GetViewerStackSettings(viewerName)
    -- Track per-viewer state so Initialize can compare desired vs current
    viewer._cmc_stack_enabled = stackEnabled or false
    if not stackEnabled then
        self:RestoreStackPositions(viewerName)
        return
    end
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        -- BuffIconCooldownViewer has Applications.Applications and other views have ChargeCount.Current
        local fs = child and child.Applications and child.Applications.Applications
            or child.ChargeCount and child.ChargeCount.Current

        if child.Applications and child.Applications.SetFrameLevel then
            child.Applications:SetFrameLevel(20)
        end
        if child.ChargeCount and child.ChargeCount.SetFrameLevel then
            child.ChargeCount:SetFrameLevel(20)
        end
        if fs then
            child._cmc_affected = child._cmc_affected or {}
            child._cmc_affected.stack = true
            ApplyStackFont(fs, fontSize, viewerName)
            fs:ClearAllPoints()
            fs:SetPoint(stackPoint, child, stackPoint, stackX, stackY)
        end
    end
end

function Stacks:IsAnyStacksFeatureEnabled()
    return ns.db.profile.cooldownManager_stackAnchorEssential_enabled
        or ns.db.profile.cooldownManager_stackAnchorUtility_enabled
        or ns.db.profile.cooldownManager_stackAnchorBuffIcons_enabled
end

function Stacks:ApplyAllStackFonts()
    for viewerName in pairs(viewersSettingKey) do
        self:ApplyStackFonts(viewerName)
    end
end

function Stacks:OnSettingChanged()
    self:ApplyAllStackFonts()
end

function Stacks:Initialize()
    self:OnSettingChanged()
end

EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
    if ns.Stacks then
        ns.Stacks:OnSettingChanged()
    end
end)
