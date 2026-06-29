local _, ns = ...
CooldownManagerCentered = LibStub("AceAddon-3.0"):NewAddon("CooldownManagerCentered", "AceConsole-3.0")
ns.Addon = CooldownManagerCentered
CooldownManagerCentered.ns = ns
local L = LibStub("AceLocale-3.0"):GetLocale("CooldownManagerCentered")
ns.L = L

ns.CONSTANTS = ns.CONSTANTS or {}
-- Upper bound on the number of custom trackers a profile may have (contiguous 1..N).
ns.CONSTANTS.MAX_TRACKERS = 10
ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR = {
    r = CooldownViewerConstants.ITEM_AURA_COLOR.r,
    g = CooldownViewerConstants.ITEM_AURA_COLOR.g,
    b = CooldownViewerConstants.ITEM_AURA_COLOR.b,
    a = CooldownViewerConstants.ITEM_AURA_COLOR.a,
}
ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR = {
    r = CooldownViewerConstants.ITEM_COOLDOWN_COLOR.r,
    g = CooldownViewerConstants.ITEM_COOLDOWN_COLOR.g,
    b = CooldownViewerConstants.ITEM_COOLDOWN_COLOR.b,
    a = CooldownViewerConstants.ITEM_COOLDOWN_COLOR.a,
}

ns.CONSTANTS.DEFAULT_FONT = { SystemFont_Outline:GetFont() }
ns.CONSTANTS.DEFAULT_NUMBER_FONT = { NumberFontNormal:GetFont() }

ns.CONSTANTS.FONT = {
    DEFAULT_STACK_POINT = "BOTTOMRIGHT",
    DEFAULT_STACK_OFFSET_X = -2,
    DEFAULT_STACK_OFFSET_Y = 2,
}

local GLOBAL_SETTINGS_JUST_DEFAULTS = {
    autoSwitchProfiles = false,
    masque_enabled = false,
    -- ["autoSwitchProfile" .. playerClassId .. "Spec" .. i] = "ProfileName", -- ex. autoSwitchProfile1SPec1 = "ProfileName",
}

-- Default Settings
ns.DEFAULT_SETTINGS = {
    profile = {
        cooldownManager_alignBuffIcons_growFromDirection = "CENTER",
        cooldownManager_alignBuffBars_growFromDirection = "BOTTOM",
        cooldownManager_centerEssential_growFromDirection = "TOP",
        cooldownManager_centerUtility_growFromDirection = "TOP",

        cooldownManager_utility_dimWhenNotOnCD = false,
        cooldownManager_utility_dimOpacity = 0.3,

        cooldownManager_cooldownFontName = "NIL",
        cooldownManager_cooldownFontFlags = { OUTLINE = true },
        cooldownManager_cooldownFontSizeEssential_enabled = false,
        cooldownManager_cooldownFontSizeEssential = "NIL",
        cooldownManager_cooldownFontSizeUtility_enabled = false,
        cooldownManager_cooldownFontSizeUtility = "NIL",
        cooldownManager_cooldownFontSizeBuffIcons_enabled = false,
        cooldownManager_cooldownFontSizeBuffIcons = "NIL",
        cooldownManager_cooldownFontSizeTracker_enabled = false,
        cooldownManager_cooldownFontSizeTracker = "NIL",

        -- Cooldown (countdown) text position offsets. Separate per viewer,
        -- shared single pair for all custom trackers.
        cooldownManager_cooldownTextEssential_offsetX = 0,
        cooldownManager_cooldownTextEssential_offsetY = 0,
        cooldownManager_cooldownTextUtility_offsetX = 0,
        cooldownManager_cooldownTextUtility_offsetY = 0,
        cooldownManager_cooldownTextBuffIcons_offsetX = 0,
        cooldownManager_cooldownTextBuffIcons_offsetY = 0,
        cooldownManager_cooldownTextTracker_offsetX = 0,
        cooldownManager_cooldownTextTracker_offsetY = 0,

        cooldownManager_stackFontName = "NIL",
        cooldownManager_stackFontFlags = { OUTLINE = true },

        cooldownManager_stackFontSizeEssential = nil,
        cooldownManager_stackFontSizeUtility = nil,
        cooldownManager_stackFontSizeBuffIcons = nil,

        cooldownManager_stackAnchorEssential_enabled = false,
        cooldownManager_stackAnchorEssential_point = "BOTTOMRIGHT",
        cooldownManager_stackAnchorEssential_offsetX = -2,
        cooldownManager_stackAnchorEssential_offsetY = 2,

        cooldownManager_stackAnchorUtility_enabled = false,
        cooldownManager_stackAnchorUtility_point = "BOTTOMRIGHT",
        cooldownManager_stackAnchorUtility_offsetX = -2,
        cooldownManager_stackAnchorUtility_offsetY = 2,

        cooldownManager_stackAnchorBuffIcons_enabled = false,
        cooldownManager_stackAnchorBuffIcons_point = "BOTTOMRIGHT",
        cooldownManager_stackAnchorBuffIcons_offsetX = -2,
        cooldownManager_stackAnchorBuffIcons_offsetY = 2,

        -- Square Icons Styling
        cooldownManager_squareIcons_Essential = false,
        cooldownManager_squareIconsBorder_Essential = 1,
        cooldownManager_squareIconsBorder_Essential_Overlap = false,
        cooldownManager_squareIconsZoom_Essential = 0.3,

        cooldownManager_squareIcons_Utility = false,
        cooldownManager_squareIconsBorder_Utility = 1,
        cooldownManager_squareIconsBorder_Utility_Overlap = false,
        cooldownManager_squareIconsZoom_Utility = 0.3,

        cooldownManager_squareIcons_BuffIcons = false,
        cooldownManager_squareIconsBorder_BuffIcons = 1,
        cooldownManager_squareIconsBorder_BuffIcons_Overlap = false,
        cooldownManager_squareIconsZoom_BuffIcons = 0.3,

        -- Keybinds Display
        cooldownManager_keybindFontName = "NIL",
        cooldownManager_keybindFontFlags = { OUTLINE = true },

        cooldownManager_showKeybinds_Essential = false,
        cooldownManager_keybindAnchor_Essential = "TOPRIGHT",
        cooldownManager_keybindFontSize_Essential = 14,
        cooldownManager_keybindOffsetX_Essential = -3,
        cooldownManager_keybindOffsetY_Essential = -3,

        cooldownManager_showKeybinds_Utility = false,
        cooldownManager_keybindAnchor_Utility = "TOPRIGHT",
        cooldownManager_keybindFontSize_Utility = 10,
        cooldownManager_keybindOffsetX_Utility = -3,
        cooldownManager_keybindOffsetY_Utility = -3,

        cooldownManager_showKeybinds_CMCTracker = false,
        cooldownManager_keybindAnchor_CMCTracker = "TOPRIGHT",
        cooldownManager_keybindFontSize_CMCTracker = 10,
        cooldownManager_keybindOffsetX_CMCTracker = -3,
        cooldownManager_keybindOffsetY_CMCTracker = -3,

        cooldownManager_limitUtilitySizeToEssential = false,

        -- Rotation Highlight (Assisted Combat)
        cooldownManager_showHighlight_Essential = false,
        cooldownManager_showHighlight_Utility = false,

        cooldownManager_buttonPress = false,
        cooldownManager_buttonPress_texture = "Blizzard",

        -- Disable Blizzard's out-of-range dimming on Essential/Utility icons.
        cooldownManager_hideRangeCheck = false,

        -- Icon Size Normalization
        cooldownManager_normalizeUtilitySize = false,

        -- Per-viewer visibility rules (populated by CMCVisibility:MigrateSettings on first load).
        -- Intentionally absent from defaults so migration can detect first-run and copy old settings.
        -- cooldownManager_visibility_perViewer = {},

        cooldownManager_hideCooldownFlash = false,

        cooldownManager_customSwipeColor_enabled = false,
        cooldownManager_customActiveColor_r = ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.r,
        cooldownManager_customActiveColor_g = ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.g,
        cooldownManager_customActiveColor_b = ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.b,
        cooldownManager_customActiveColor_a = ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.a,
        cooldownManager_customCDSwipeColor_r = ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.r,
        cooldownManager_customCDSwipeColor_g = ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.g,
        cooldownManager_customCDSwipeColor_b = ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.b,
        cooldownManager_customCDSwipeColor_a = ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.a,

        cooldownManager_desaturate_under_aura = false,
        cooldownManager_hide_gcd = false,

        cooldownManager_experimental_glow_style = "DEFAULT",
        cooldownManager_experimental_glow_custom_color = false,
        cooldownManager_experimental_glow_color_r = 0.95,
        cooldownManager_experimental_glow_color_g = 0.95,
        cooldownManager_experimental_glow_color_b = 0.32,
        cooldownManager_experimental_glow_color_a = 1,

        cooldownManager_hide_glow_on_active_aura = false,

        cooldownManager_experimental_enableRectangularIcons_essential = false,
        cooldownManager_experimental_enableRectangularIcons_essential_percent = 0.8,
        cooldownManager_experimental_enableRectangularIcons_utility = false,
        cooldownManager_experimental_enableRectangularIcons_utility_percent = 0.8,
        cooldownManager_experimental_enableRectangularIcons_buffIcons = false,
        cooldownManager_experimental_enableRectangularIcons_buffIcons_percent = 0.8,

        -- used for new tracker as well - legacy name
        trinketRacialTracker_squareIcons = false,
        trinketRacialTracker_borderThickness = 1,
        trinketRacialTracker_iconZoom = 0.3,
        trinketRacialTracker_rectangularIcons = false,
        trinketRacialTracker_rectangularIcons_percent = 0.8,
        trinketRacialTracker_stackAnchor = "BOTTOMRIGHT",
        trinketRacialTracker_stackFontSize = 14,
        trinketRacialTracker_stackOffsetX = -1,
        trinketRacialTracker_stackOffsetY = 1,

        tracker_enabled = false,
        tracker = {},
        -- Number of active custom trackers (contiguous 1..N, max MAX_TRACKERS).
        -- Auto-reconciled to keep one empty trailing tracker; defaults to 2.
        tracker_count = 2,
        cooldownStyleSettings = {
            spellSettings = {},
        },
        editMode = {
            tracker1 = {},
            tracker2 = {},
        },
    },
}
