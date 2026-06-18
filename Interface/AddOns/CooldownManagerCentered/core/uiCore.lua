local _, ns = ...

--- WilduUI Core Module
local WilduUICore = {}
ns.WilduUICore = WilduUICore

local LEM = LibStub("WildForkLibEQOLEditMode-1.0")

local HIDDEN_POSITION = { point = "TOP", x = 0, y = 500 }
local DEFAULT_SCALE = 1
local DEFAULT_ALPHA = 1
local DEFAULT_STRATA = "MEDIUM"

local VALID_STRATA = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

local FRAME_DEFAULT_CONFIG = {
    point = "CENTER",
    x = 0,
    y = 0,
    scale = DEFAULT_SCALE,
    alpha = DEFAULT_ALPHA,
    strata = DEFAULT_STRATA,
}

local visibilityDriverPostCombatFrame = CreateFrame("Frame", nil, UIParent)
visibilityDriverPostCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visibilityDriverPostCombatFrame.delayedApplications = {}
visibilityDriverPostCombatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not InCombatLockdown() then
        for i, application in ipairs(visibilityDriverPostCombatFrame.delayedApplications) do
            WilduUICore.ApplyVisibilityDriverToFrame(application.frame, application.expression)
        end
        visibilityDriverPostCombatFrame.delayedApplications = {}
    end
end)

---Apply or remove a visibility state driver for a frame
---@param frame Frame The WoW UI frame to manage visibility for
---@param expression? string State driver expression (nil to remove driver) - https://warcraft.wiki.gg/wiki/Macro_conditionals
---@param shouldHideInCombat? boolean If true, hides frame immediately when in combat
function WilduUICore.ApplyVisibilityDriverToFrame(frame, expression, shouldHideInCombat)
    if not frame then
        return
    end
    if InCombatLockdown() then
        if shouldHideInCombat then
            frame:Hide()
        end
        table.insert(visibilityDriverPostCombatFrame.delayedApplications, {
            frame = frame,
            expression = expression,
        })
        return
    end
    if not expression then
        if frame._wt_VisibilityDriver then
            if UnregisterStateDriver then
                pcall(UnregisterStateDriver, frame, "visibility")
            end
            frame._wt_VisibilityDriver = nil
        end
        return
    end
    if frame._wt_VisibilityDriver == expression then
        return
    end
    if RegisterStateDriver then
        local ok = pcall(RegisterStateDriver, frame, "visibility", expression)
        if ok then
            frame._wt_VisibilityDriver = expression
        end
    end
end

---Ensure and load frame configuration with comprehensive fallback chain
---@param configKey string The database key in editMode (e.g., "rangeCheck", "mountIcon")
---@param defaultConfig? table Default position/settings table (applied to profile first)
---@return table config The configuration table with all properties resolved
function WilduUICore.LoadFrameConfig(configKey, defaultConfig)
    -- Ensure editMode database structure exists
    defaultConfig = defaultConfig or {}
    if not ns.Addon.db.profile.editMode then
        ns.Addon.db.profile.editMode = {}
    end

    -- Initialize config entry if missing
    if not ns.Addon.db.profile.editMode[configKey] then
        ns.Addon.db.profile.editMode[configKey] = {}
    end

    local storedConfig = ns.Addon.db.profile.editMode[configKey]

    -- Build result with three-tier fallback: stored → defaultConfig → DEFAULT_CONFIG
    local result = {}

    -- Get all unique keys from all sources
    local allKeys = {}
    for key in pairs(FRAME_DEFAULT_CONFIG) do
        allKeys[key] = true
    end
    for key in pairs(defaultConfig) do
        allKeys[key] = true
    end
    for key in pairs(storedConfig) do
        allKeys[key] = true
    end

    -- Apply fallback chain for each property
    for key in pairs(allKeys) do
        result[key] = ns.Addon.db.profile.editMode[configKey][key] or defaultConfig[key] or FRAME_DEFAULT_CONFIG[key]
    end

    -- Update stored config to ensure missing properties are persisted
    for key, value in pairs(result) do
        if ns.Addon.db.profile.editMode[configKey][key] == nil then
            ns.Addon.db.profile.editMode[configKey][key] = value
        end
    end

    return result
end

---Apply position and scale to a frame from config
---@param frame Frame The frame to position
---@param configKey string The database key
---@param shouldHide boolean Whether to hide (move off-screen) the frame
function WilduUICore.ApplyFramePosition(frame, configKey, shouldHide)
    local config = ns.Addon.db.profile.editMode[configKey]
    if shouldHide then
        frame:SetClampedToScreen(false)
    else
        frame:SetClampedToScreen(true)
    end

    frame:ClearAllPoints()

    if shouldHide then
        frame:SetPoint(HIDDEN_POSITION.point, UIParent, HIDDEN_POSITION.point, HIDDEN_POSITION.x, HIDDEN_POSITION.y)
    else
        frame:SetPoint(config.point or "CENTER", UIParent, config.point or "CENTER", config.x or 0, config.y or 0)
    end

    if config.scale ~= nil then
        frame:SetScale(config.scale)
    end
    if frame.SetAlpha and config.alpha ~= nil then
        frame:SetAlpha(config.alpha)
    end
    if frame.SetFrameStrata then
        frame:SetFrameStrata(config.strata or DEFAULT_STRATA)
    end
end

---Create standard position-changed callback for LEM
---@param configKey string The database key
---@return function callback Callback function for LEM
function WilduUICore.CreateOnPositionChanged(configKey)
    return function(frame, layoutName, point, x, y)
        ns.Addon.db.profile.editMode[configKey].point = point
        ns.Addon.db.profile.editMode[configKey].y = y

        if ns.Addon.db.profile.editMode[configKey].lockHorizontal then
            ns.Addon.db.profile.editMode[configKey].x = 0
        else
            ns.Addon.db.profile.editMode[configKey].x = x
        end

        WilduUICore.ApplyFramePosition(frame, configKey, false)
    end
end

---Register standard EditMode callbacks (enter/layout)
---@param frame Frame The frame to register callbacks for
---@param configKey string The database key
---@param enabledCheckFn function Function that returns whether frame should be visible
---@param shouldRepositionFn function Function that returns whether frame should be repositioned
function WilduUICore.RegisterEditModeCallbacks(frame, configKey, enabledCheckFn, shouldRepositionFn)
    LEM:RegisterCallback("enter", function()
        local shouldHide = not enabledCheckFn()
        if frame._wt_VisibilityDriver and not InCombatLockdown() then
            if UnregisterStateDriver then
                pcall(UnregisterStateDriver, frame, "visibility")
            end
            frame._wt_VisibilityDriver_BACKUP = frame._wt_VisibilityDriver
            frame._wt_VisibilityDriver = nil
        elseif not frame._wt_VisibilityDriver and not frame:IsShown() then
            frame._wt_hideOnEditModeExit = true
        end
        if not frame:IsShown() then
            frame:Show()
        end
        if not shouldHide and (not shouldRepositionFn or shouldRepositionFn()) then
            WilduUICore.ApplyFramePosition(frame, configKey, false)
        elseif shouldHide then
            WilduUICore.ApplyFramePosition(frame, configKey, true)
        end
    end)

    LEM:RegisterCallback("exit", function()
        if frame._wt_VisibilityDriver_BACKUP then
            WilduUICore.ApplyVisibilityDriverToFrame(frame, frame._wt_VisibilityDriver_BACKUP)
            frame._wt_VisibilityDriver_BACKUP = nil
        end
        if frame._wt_hideOnEditModeExit then
            frame._wt_hideOnEditModeExit = nil
            frame:Hide()
        end
    end)

    LEM:RegisterCallback("layout", function(layoutName)
        WilduUICore.LoadFrameConfig(configKey)
        local shouldHide = not enabledCheckFn()
        if not shouldHide and (not shouldRepositionFn or shouldRepositionFn()) then
            WilduUICore.ApplyFramePosition(frame, configKey, false)
        elseif shouldHide then
            WilduUICore.ApplyFramePosition(frame, configKey, true)
        end
    end)
end

---Create a Scale slider setting for LEM
---@param configKey string The database key
---@param defaultValue number Default scale value
---@param frame Frame The frame to apply the scale toggle
---@param onPositionChangedCallback? function Optional custom position callback used after scaling
---@return table setting LEM setting configuration
function WilduUICore.CreateScaleSetting(configKey, defaultValue, frame, onPositionChangedCallback)
    defaultValue = defaultValue or DEFAULT_SCALE
    return {
        name = "Scale",
        kind = LEM.SettingType.Slider,
        default = defaultValue,
        get = function()
            return ns.Addon.db.profile.editMode[configKey].scale or defaultValue
        end,
        set = function(layoutName, value)
            local config = ns.Addon.db.profile.editMode[configKey]
            local previousScale = config.scale or defaultValue
            config.scale = value
            local scaleDiff = previousScale / value
            config.x = (config.x or 0) * scaleDiff
            config.y = (config.y or 0) * scaleDiff

            if onPositionChangedCallback then
                onPositionChangedCallback(frame, layoutName, config.point or "CENTER", config.x or 0, config.y or 0)
                return
            end
            WilduUICore.ApplyFramePosition(frame, configKey, false)
        end,
        minValue = 0.1,
        maxValue = 5,
        valueStep = 0.1,
        formatter = function(value)
            return FormatPercentage(value, true)
        end,
    }
end

---Create a Strata dropdown setting for LEM
---@param configKey string The database key
---@param defaultValue string Default strata value
---@param frame Frame The frame to apply the strata toggle
---@return table setting LEM setting configuration
function WilduUICore.CreateStrataSetting(configKey, defaultValue, frame)
    defaultValue = defaultValue or DEFAULT_STRATA
    local strataValues = {}
    for _, strata in ipairs(VALID_STRATA) do
        table.insert(strataValues, { text = strata, isRadio = true })
    end
    return {
        name = "Strata",
        kind = LEM.SettingType.Dropdown,
        default = defaultValue,
        get = function()
            return ns.Addon.db.profile.editMode[configKey].strata or defaultValue
        end,
        set = function(layoutName, value)
            ns.Addon.db.profile.editMode[configKey].strata = value
            if frame.SetFrameStrata then
                frame:SetFrameStrata(value)
            end
        end,
        values = strataValues,
    }
end

---Register a frame with LEM and apply settings
---@param frame Frame The frame to register
---@param configKey string The database key
---@param additionalSettings? table[] Additional LEM settings appended after Scale and Strata
---@param onPositionChangedCallback? function Custom callback for position changes (overrides default)
function WilduUICore.RegisterFrameWithLEM(frame, configKey, additionalSettings, onPositionChangedCallback)
    additionalSettings = additionalSettings or {}
    local config = WilduUICore.LoadFrameConfig(configKey)

    local defaultTable = ns.DEFAULT_SETTINGS.profile.editMode[configKey] or {}
    defaultTable.enableOverlayToggle = true
    -- Custom trackers don't expose "Reset to Default" / "Reset Position" buttons.
    defaultTable.showReset = false
    defaultTable.showSettingsReset = false
    LEM:AddFrame(frame, onPositionChangedCallback or WilduUICore.CreateOnPositionChanged(configKey), defaultTable)

    -- Frame-level Scale/Strata live in a collapsible "General" section so the
    -- panel groups the same way the cooldown viewers' Edit Mode settings do.
    local scaleSetting =
        WilduUICore.CreateScaleSetting(configKey, FRAME_DEFAULT_CONFIG.scale, frame, onPositionChangedCallback)
    local strataSetting = WilduUICore.CreateStrataSetting(configKey, FRAME_DEFAULT_CONFIG.strata, frame)
    scaleSetting.parentId = "general"
    strataSetting.parentId = "general"

    local settings = {
        { kind = LEM.SettingType.Collapsible, id = "general", name = "General", defaultCollapsed = true },
        scaleSetting,
        strataSetting,
    }

    for _, setting in ipairs(additionalSettings) do
        table.insert(settings, setting)
    end

    LEM:AddFrameSettings(frame, settings)
end

---Wrap update logic with a repeating C_Timer.NewTicker
---@param frame Frame The frame to associate the ticker with
---@param interval number Seconds between updates
---@param updateFn function Function to call for update logic
---@param checkForIsShown? boolean Check for frame visibility, if hidden won't call callback
function WilduUICore.CreateTickerUpdate(frame, interval, updateFn, checkForIsShown)
    if not frame or not interval or not updateFn then
        return
    end

    -- Cancel previous ticker if it exists
    if frame._wt_ticker and frame._wt_ticker.Cancel then
        frame._wt_ticker:Cancel()
        frame._wt_ticker = nil
    end

    -- Create new repeating ticker
    frame._wt_ticker = C_Timer.NewTicker(interval, function()
        if not checkForIsShown or frame:IsShown() then
            updateFn(frame)
        end
    end)
end
