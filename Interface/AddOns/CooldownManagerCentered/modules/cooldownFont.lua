local _, ns = ...

local CooldownFont = {}
ns.CooldownFont = CooldownFont

local Stacks = {}
ns.Stacks = Stacks

local LSM = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"

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

-- Cooldown number font

local function GetViewerCooldownSettings(viewerName)
    local map = {
        EssentialCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeEssential,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeEssential_enabled,
            default = 20,
        },
        UtilityCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeUtility,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeUtility_enabled,
            default = 12,
        },
        BuffIconCooldownViewer = {
            size = ns.db.profile.cooldownManager_cooldownFontSizeBuffIcons,
            enabled = ns.db.profile.cooldownManager_cooldownFontSizeBuffIcons_enabled,
            default = 16,
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
        local size, enabled, _size = GetViewerCooldownSettings(viewerName)
        if not enabled then
            return
        end
        if not size or size == 0 then
            fontString:SetFontHeight(0)
            return
        end
        fontString:SetTextColor(1, 1, 1, 1)

        if size == "NIL" then
            size = _size
        end

        local fontName = ns.db.profile.cooldownManager_cooldownFontName or "Friz Quadrata TT"
        local fontPath = GetFontPath(fontName)
        local fontFlags = ns.db.profile.cooldownManager_cooldownFontFlags or {}
        local fontFlag = ""
        for n, v in pairs(fontFlags) do
            if v == true then
                fontFlag = fontFlag .. n .. ","
            end
        end
        fontString:SetFont(fontPath, size, fontFlag or "")
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
        },
        UtilityCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeUtility,
            enabled = ns.db.profile.cooldownManager_stackAnchorUtility_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorUtility_point,
            x = ns.db.profile.cooldownManager_stackAnchorUtility_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorUtility_offsetY,
        },
        BuffIconCooldownViewer = {
            size = ns.db.profile.cooldownManager_stackFontSizeBuffIcons,
            enabled = ns.db.profile.cooldownManager_stackAnchorBuffIcons_enabled,
            point = ns.db.profile.cooldownManager_stackAnchorBuffIcons_point,
            x = ns.db.profile.cooldownManager_stackAnchorBuffIcons_offsetX,
            y = ns.db.profile.cooldownManager_stackAnchorBuffIcons_offsetY,
        },
    }
    local cfg = map[viewerName]
    if not cfg then
        return nil, false, "BOTTOMRIGHT", 0, 0
    end
    return cfg.size, cfg.enabled, (cfg.point or "BOTTOMRIGHT"), (cfg.x or 0), (cfg.y or 0)
end

local function ApplyStackFont(fontString, size)
    local fontName = (ns.db and ns.db.profile and ns.db.profile.cooldownManager_stackFontName) or "Friz Quadrata TT"
    local fontPath = GetFontPath(fontName)
    local fontFlags = ns.db.profile.cooldownManager_stackFontFlags or {}
    local fontFlag = ""
    for n, v in pairs(fontFlags) do
        if v == true then
            fontFlag = fontFlag .. n .. ","
        end
    end
    fontString:SetFont(fontPath, size, fontFlag or "")
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
            ApplyStackFont(fs, fontSize)
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

