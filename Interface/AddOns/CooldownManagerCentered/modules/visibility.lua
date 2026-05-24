local _, ns = ...

local CMCVisibility = {}
ns.CMCVisibility = CMCVisibility

-- Per-viewer data: driver frames, cached attribute-driver state, and instance override flag
local inInstance = false
local miniGameSceneActive = false
local driverFrames = {}  -- [viewerName] = Frame with RegisterAttributeDriver
local driverState  = {}  -- [viewerName] = "show" | "hide"  (last value from attribute driver)

local viewers = {
    { viewerName = "BuffIconCooldownViewer" },
    { viewerName = "BuffBarCooldownViewer" },
    { viewerName = "EssentialCooldownViewer" },
    { viewerName = "UtilityCooldownViewer" },
    { viewerName = "CMCTracker1", settingsKey = "tracker1" },
    { viewerName = "CMCTracker2", settingsKey = "tracker2" },
}

-- Rules that map directly to macro conditionals supported by RegisterAttributeDriver.
-- SHOW_IN_INSTANCE has no macro conditional equivalent and is handled via events.
local RULE_CONDITIONALS = {
    SHOW_IN_COMBAT         = "[combat] show",
    HIDE_IN_VEHICLES       = "[unithasvehicleui] hide;[overridebar] hide;[possessbar] hide",
    HIDE_WHEN_FLYING       = "[flying] hide",
    HIDE_WHEN_MOUNTED      = "[mounted] hide",
    HIDE_WHEN_RESTING      = "[resting] hide",
    HIDE_OUT_OF_COMBAT     = "[nocombat] hide",
}

-- Priority order: SHOW overrides are evaluated first, HIDE rules after.
local RULE_ORDER = {
    "SHOW_IN_COMBAT",
    "HIDE_IN_VEHICLES",
    "HIDE_WHEN_FLYING",
    "HIDE_WHEN_MOUNTED",
    "HIDE_WHEN_RESTING",
    "HIDE_OUT_OF_COMBAT",
}

local function GetViewerRules(viewerName)
    local perViewer = ns.db and ns.db.profile.cooldownManager_visibility_perViewer
    return (perViewer and perViewer[viewerName]) or {}
end

local function HasAnyRule(rules)
    for _, v in pairs(rules) do
        if v then return true end
    end
    return false
end

local function BuildConditionalString(rules)
    local parts = {}
    for _, ruleName in ipairs(RULE_ORDER) do
        if rules[ruleName] and RULE_CONDITIONALS[ruleName] then
            table.insert(parts, RULE_CONDITIONALS[ruleName])
        end
    end
    table.insert(parts, "show")
    return table.concat(parts, "; ")
end

local function GetViewerAlpha(viewerData)
    local viewer = viewerData.viewer
    local settingsKey = viewerData.settingsKey
    if settingsKey then
        local editMode = ns.db and ns.db.profile.editMode
        return (editMode and editMode[settingsKey] and editMode[settingsKey].alpha) or 1
    elseif viewer and viewer.settingMap and viewer.settingMap[Enum.EditModeCooldownViewerSetting.Opacity] then
        return (viewer.settingMap[Enum.EditModeCooldownViewerSetting.Opacity].value + 50) / 100
    end
    return 1
end

local function ApplyViewerAlpha(viewerData)
    local viewerName = viewerData.viewerName
    local viewer = viewerData.viewer
    if not viewer then return end

    local rules = GetViewerRules(viewerName)
    local alpha = GetViewerAlpha(viewerData)

    if not HasAnyRule(rules) then
        viewer:SetAlpha(alpha)
        return
    end

    if rules.SHOW_IN_INSTANCE and inInstance then
        viewer:SetAlpha(alpha)
        return
    end
    if rules.HIDE_IN_VEHICLES and miniGameSceneActive then
        viewer:SetAlpha(0)
        return
    end
    local hasTarget = UnitExists("target")
    local targetIsEnemy = UnitCanAttack("player", "target")
    if rules.SHOW_WITH_TARGET and hasTarget then
        viewer:SetAlpha(alpha)
        return
    end
    if rules.SHOW_WITH_ENEMY_TARGET and hasTarget and targetIsEnemy then
        viewer:SetAlpha(alpha)
        return
    end

    local state = driverState[viewerName] or "show"
    viewer:SetAlpha(state == "show" and alpha or 0)
end

local function SetupViewerDriver(viewerData)
    local viewerName = viewerData.viewerName

    -- Lazily resolve the viewer frame reference
    if not viewerData.viewer and _G[viewerName] then
        viewerData.viewer = _G[viewerName]
    end

    local rules = GetViewerRules(viewerName)

    if not HasAnyRule(rules) then
        -- Unregister any existing driver but keep the frame for reuse later
        if driverFrames[viewerName] then
            UnregisterAttributeDriver(driverFrames[viewerName], "state-vis")
        end
        driverState[viewerName] = "show"
        ApplyViewerAlpha(viewerData)
        return
    end

    -- Reuse the frame when rules change; create it once per viewer
    local frame = driverFrames[viewerName]
    if not frame then
        frame = CreateFrame("Frame")
        driverFrames[viewerName] = frame
        -- viewerData / viewerName captured by closure — stable for the lifetime of the addon
        frame:SetScript("OnAttributeChanged", function(self, name, value)
            if name == "state-vis" then
                driverState[viewerName] = value
                ApplyViewerAlpha(viewerData)
            end
        end)
    else
        UnregisterAttributeDriver(frame, "state-vis")
    end

    local conditionalStr = BuildConditionalString(rules)
    RegisterAttributeDriver(frame, "state-vis", conditionalStr)

    -- Ensure alpha is applied even if OnAttributeChanged has not yet fired
    ApplyViewerAlpha(viewerData)
end

-- Pending-initialize flag: set when Initialize() is called during combat lockdown.
-- SetupViewerDriver calls RegisterAttributeDriver which is combat-restricted.
local pendingInitialize = false

-- Event frame: handles SHOW_IN_INSTANCE (event-based) and deferred post-combat init.
local EventFrame = CreateFrame("Frame")
EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        inInstance = IsInInstance()
    elseif event == "CLIENT_SCENE_OPENED" then
        local sceneType = ...
        miniGameSceneActive = (sceneType == 1)
    elseif event == "CLIENT_SCENE_CLOSED" then
        miniGameSceneActive = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingInitialize then
            pendingInitialize = false
            CMCVisibility:Initialize()
            return  -- Initialize calls UpdateAll internally via SetupViewerDriver
        end
    end
    CMCVisibility:UpdateAll()
end)

function CMCVisibility:UpdateAll()
    for _, viewerData in ipairs(viewers) do
        if not viewerData.viewer and _G[viewerData.viewerName] then
            viewerData.viewer = _G[viewerData.viewerName]
        end
        ApplyViewerAlpha(viewerData)
    end
end

function CMCVisibility:Initialize()
    self:MigrateSettings()

    -- RegisterAttributeDriver (called by SetupViewerDriver) is combat-restricted.
    -- Defer the full driver setup until after combat; UpdateAll still runs so
    -- the current alpha stays correct based on already-registered drivers.
    if InCombatLockdown() then
        pendingInitialize = true
        EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    pendingInitialize = false

    for _, viewerData in ipairs(viewers) do
        SetupViewerDriver(viewerData)
    end

    -- Always keep PLAYER_REGEN_ENABLED registered so a queued init is never lost.
    -- Also register PLAYER_ENTERING_WORLD when at least one viewer uses SHOW_IN_INSTANCE.
    EventFrame:UnregisterAllEvents()
    EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    inInstance = IsInInstance()
    EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    EventFrame:RegisterEvent("CLIENT_SCENE_OPENED")
    EventFrame:RegisterEvent("CLIENT_SCENE_CLOSED")
    EventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
end

function CMCVisibility:DeInitialize()
    EventFrame:UnregisterAllEvents()

    for _, viewerData in ipairs(viewers) do
        local viewerName = viewerData.viewerName
        if driverFrames[viewerName] then
            UnregisterAttributeDriver(driverFrames[viewerName], "state-vis")
            -- Keep the frame in driverFrames so it can be reused on re-Initialize
        end
        driverState[viewerName] = "show"
        if viewerData.viewer then
            viewerData.viewer:SetAlpha(GetViewerAlpha(viewerData))
        end
    end
end

-- Migrate from the legacy "Smart Visibility" global rules + affected viewers into
-- the new per-viewer rule tables.  Runs once (skipped if perViewer already exists).
function CMCVisibility:MigrateSettings()
    local profile = ns.db.profile
    if profile.cooldownManager_visibility_perViewer then
        return
    end

    profile.cooldownManager_visibility_perViewer = {}

    local globalRules    = profile.cooldownManager_visibility_enabled_rules    or {}
    local affectedViewers = profile.cooldownManager_visibility_enabled_viewers or {}

    local viewerNames = {
        "BuffIconCooldownViewer",
        "BuffBarCooldownViewer",
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "CMCTracker1",
        "CMCTracker2",
    }

    for _, viewerName in ipairs(viewerNames) do
        local viewerRules = {}
        if affectedViewers[viewerName] then
            for rule, enabled in pairs(globalRules) do
                if enabled then
                    viewerRules[rule] = true
                end
            end
        end
        profile.cooldownManager_visibility_perViewer[viewerName] = viewerRules
    end
end
