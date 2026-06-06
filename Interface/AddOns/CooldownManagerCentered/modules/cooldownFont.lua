local _, ns = ...

local CooldownFont = {}
ns.CooldownFont = CooldownFont

local Stacks = {}
ns.Stacks = Stacks

local LSM = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"
local DEFAULT_STACK_FONT_PATH = "Fonts\\ARIALN.TTF"
local BUFF_ICON_DEFAULT_COOLDOWN_FONT_PATH = DEFAULT_FONT_PATH
local BUFF_ICON_DEFAULT_COOLDOWN_FONT_SIZE = 16
local BUFF_ICON_DEFAULT_STACK_FONT_PATH = DEFAULT_STACK_FONT_PATH
local BUFF_ICON_DEFAULT_STACK_FONT_SIZE = 14
local BUFF_ICON_DEFAULT_STACK_POINT = "BOTTOMRIGHT"
local BUFF_ICON_DEFAULT_STACK_OFFSET_X = -2
local BUFF_ICON_DEFAULT_STACK_OFFSET_Y = 2

local ESSENTIAL_ICON_DEFAULT_COOLDOWN_FONT_PATH = DEFAULT_FONT_PATH
local ESSENTIAL_ICON_DEFAULT_COOLDOWN_FONT_SIZE = 20
local ESSENTIAL_ICON_DEFAULT_STACK_FONT_PATH = DEFAULT_STACK_FONT_PATH
local ESSENTIAL_ICON_DEFAULT_STACK_FONT_SIZE = 14
local ESSENTIAL_ICON_DEFAULT_STACK_POINT = "BOTTOMRIGHT"
local ESSENTIAL_ICON_DEFAULT_STACK_OFFSET_X = -2
local ESSENTIAL_ICON_DEFAULT_STACK_OFFSET_Y = 2

local UTILITY_ICON_DEFAULT_COOLDOWN_FONT_PATH = DEFAULT_FONT_PATH
local UTILITY_ICON_DEFAULT_COOLDOWN_FONT_SIZE = 12
local UTILITY_ICON_DEFAULT_STACK_FONT_PATH = DEFAULT_STACK_FONT_PATH
local UTILITY_ICON_DEFAULT_STACK_FONT_SIZE = 12
local UTILITY_ICON_DEFAULT_STACK_POINT = "BOTTOMRIGHT"
local UTILITY_ICON_DEFAULT_STACK_OFFSET_X = -2
local UTILITY_ICON_DEFAULT_STACK_OFFSET_Y = 2

local viewersSettingKey = {
    EssentialCooldownViewer = "Essential",
    UtilityCooldownViewer = "Utility",
    BuffIconCooldownViewer = "BuffIcons",
}

local function GetFontPath(fontName)
    if not fontName or fontName == "" then
        return DEFAULT_FONT_PATH
    end
    if LSM then
        local fontPath = LSM:Fetch("font", fontName)
        if fontPath then
            return fontPath
        end
    end
    return DEFAULT_FONT_PATH
end

local function GetDefaultFontPathForViewer(viewerName)
    if viewerName == "BuffIconCooldownViewer" then
        return BUFF_ICON_DEFAULT_COOLDOWN_FONT_PATH
    elseif viewerName == "EssentialCooldownViewer" then
        return ESSENTIAL_ICON_DEFAULT_COOLDOWN_FONT_PATH
    elseif viewerName == "UtilityCooldownViewer" then
        return UTILITY_ICON_DEFAULT_COOLDOWN_FONT_PATH
    end
    return DEFAULT_FONT_PATH
end

local function GetConfiguredFontPath(fontName, viewerName)
    if fontName and fontName ~= "" then
        return GetFontPath(fontName)
    end
    return GetDefaultFontPathForViewer(viewerName)
end

-- Cooldown number font

local function GetViewerCooldownSettings(viewerName)
    local map = {
        EssentialCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeEssential,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeEssential_enabled,
            default = ESSENTIAL_ICON_DEFAULT_COOLDOWN_FONT_SIZE,
        },
        UtilityCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeUtility,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeUtility_enabled,
            default = UTILITY_ICON_DEFAULT_COOLDOWN_FONT_SIZE,
        },
        BuffIconCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeBuffIcons,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeBuffIcons_enabled,
            default = BUFF_ICON_DEFAULT_COOLDOWN_FONT_SIZE,
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
        local size, enabled, _size = GetViewerCooldownSettings(viewerName)
        if not enabled then
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

        -- fontString:SetTextColor(1, 1, 1, 1)

        local fontName = ns.db.profile.cooldownManager_cooldownFontName
        local fontPath = GetConfiguredFontPath(fontName, viewerName)
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

local function GetViewerStackSettings(viewerName)
    local map = {
        EssentialCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeEssential,
            enabled = ns.db.profile.cooldownManager_stackAnchorEssential_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorEssential_point,
            x = ns.db.profile.cooldownManager_stackAnchorEssential_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorEssential_offsetY,
            default = ESSENTIAL_ICON_DEFAULT_STACK_FONT_SIZE,
            defaultPoint = ESSENTIAL_ICON_DEFAULT_STACK_POINT,
            defaultX = ESSENTIAL_ICON_DEFAULT_STACK_OFFSET_X,
            defaultY = ESSENTIAL_ICON_DEFAULT_STACK_OFFSET_Y,
        },
        UtilityCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeUtility,
            enabled = ns.db.profile.cooldownManager_stackAnchorUtility_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorUtility_point,
            x = ns.db.profile.cooldownManager_stackAnchorUtility_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorUtility_offsetY,
            default = UTILITY_ICON_DEFAULT_STACK_FONT_SIZE,
            defaultPoint = UTILITY_ICON_DEFAULT_STACK_POINT,
            defaultX = UTILITY_ICON_DEFAULT_STACK_OFFSET_X,
            defaultY = UTILITY_ICON_DEFAULT_STACK_OFFSET_Y,
        },
        BuffIconCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeBuffIcons,
            enabled = ns.db.profile.cooldownManager_stackAnchorBuffIcons_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorBuffIcons_point,
            x = ns.db.profile.cooldownManager_stackAnchorBuffIcons_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorBuffIcons_offsetY,
            default = BUFF_ICON_DEFAULT_STACK_FONT_SIZE,
            defaultPoint = BUFF_ICON_DEFAULT_STACK_POINT,
            defaultX = BUFF_ICON_DEFAULT_STACK_OFFSET_X,
            defaultY = BUFF_ICON_DEFAULT_STACK_OFFSET_Y,
        },
    }
    local cfg = map[viewerName]
    if not cfg then
        return nil, false, "BOTTOMRIGHT", 0, 0
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
    local fontName = ns.db and ns.db.profile and ns.db.profile.cooldownManager_stackFontName
    local fontPath = GetConfiguredFontPath(fontName, viewerName)
    if viewerName == "BuffIconCooldownViewer" and (not fontName or fontName == "") then
        fontPath = BUFF_ICON_DEFAULT_STACK_FONT_PATH
    elseif viewerName == "EssentialCooldownViewer" and (not fontName or fontName == "") then
        fontPath = ESSENTIAL_ICON_DEFAULT_STACK_FONT_PATH
    elseif viewerName == "UtilityCooldownViewer" and (not fontName or fontName == "") then
        fontPath = UTILITY_ICON_DEFAULT_STACK_FONT_PATH
    end
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
        if viewerName == "BuffIconCooldownViewer" then
            size = select(2, fontString:GetFont()) or BUFF_ICON_DEFAULT_STACK_FONT_SIZE
        elseif viewerName == "EssentialCooldownViewer" then
            size = select(2, fontString:GetFont()) or ESSENTIAL_ICON_DEFAULT_STACK_FONT_SIZE
        elseif viewerName == "UtilityCooldownViewer" then
            size = select(2, fontString:GetFont()) or UTILITY_ICON_DEFAULT_STACK_FONT_SIZE
        else
            size = select(2, fontString:GetFont()) or BUFF_ICON_DEFAULT_STACK_FONT_SIZE
        end
    end
    fontString:SetFont(fontPath, size, table.concat(fontFlag, ","))
end

function Stacks:ApplyStackFonts(viewerName)
    local viewer = _G[viewerName]
    if not viewer then
        return
    end
    local fontSize, stackEnabled, stackPoint, stackX, stackY = GetViewerStackSettings(viewerName)
    if not stackEnabled then
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
    self:ApplyAllStackFonts()
end

EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
    if ns.Stacks then
        ns.Stacks:OnSettingChanged()
    end
end)
