local _, ns = ...

-- EditModeViewerSettings -----------------------------------------------------------
-- Builds viewer-scoped settings lists for the in-edit-mode anchored panel
-- (see modules/editModeViewerSettings.lua). These are separate, hand-authored
-- LibEQOLEditMode setting tables that reuse the SAME db keys and refresh calls as
-- settings/AddonSettings.lua, so changing a value here behaves exactly like the
-- matching control in the full /cmc panel.
local EMVS = {}
ns.EditModeViewerSettings = EMVS

local LEM = LibStub("WildForkLibEQOLEditMode-1.0")
local LSM = LibStub("LibSharedMedia-3.0", true)
local ST = LEM.SettingType

local db = function()
    return ns.db.profile
end

-- Refresh helpers (mirror AddonSettings.lua) ---------------------------------------
local function refreshIcons()
    if ns.StyledIcons then
        ns.StyledIcons:OnSettingChanged()
    end
end
local function refreshCDM()
    if ns.API then
        ns.API:RefreshCooldownManager()
    end
end
local function refreshFont()
    if ns.CooldownFont then
        ns.CooldownFont:RefreshAll()
    end
    if ns.TrackerItemViewer then
        ns.TrackerItemViewer:RefreshStyling()
    end
end
local function refreshStyle()
    if ns.CooldownStyle and ns.CooldownStyle.RefreshHooks then
        ns.CooldownStyle:RefreshHooks()
    end
end
local function refreshStacks(viewerFrame)
    if ns.Stacks then
        ns.Stacks:ApplyStackFonts(viewerFrame)
    end
end
local function refreshKeybinds(viewerFrame)
    if ns.Keybinds then
        ns.Keybinds:ApplyKeybindSettings(viewerFrame)
    end
end

-- Widget constructors --------------------------------------------------------------
-- Each returns a LibEQOLEditMode setting table; callers attach parentId/isShown.

local function makeArray(valuesMap, order)
    local out = {}
    for _, key in ipairs(order) do
        out[#out + 1] = { value = key, text = valuesMap[key], label = valuesMap[key] }
    end
    return out
end

local function section(list, id, name, expanded)
    list[#list + 1] = { kind = ST.Collapsible, id = id, name = name, defaultCollapsed = not expanded }
    return id
end

local function add(list, data, parentId)
    data.parentId = parentId
    list[#list + 1] = data
    return data
end

-- Checkbox bound to a single boolean profile key.
local function checkbox(o)
    return {
        kind = ST.Checkbox,
        name = o.name,
        tooltip = o.desc,
        default = o.default or false,
        isShown = o.isShown,
        get = o.get or function()
            return db()[o.key]
        end,
        set = o.set or function(_, value)
            db()[o.key] = value
            if o.apply then
                o.apply(value)
            end
        end,
    }
end

-- Numeric slider bound to a single profile key (with a default fallback).
local function slider(o)
    return {
        kind = ST.Slider,
        name = o.name,
        tooltip = o.desc,
        default = o.default,
        minValue = o.min,
        maxValue = o.max,
        valueStep = o.step,
        formatter = o.formatter,
        isShown = o.isShown,
        get = o.get or function()
            local v = db()[o.key]
            if v == nil then
                return o.default
            end
            return v
        end,
        set = o.set or function(_, value)
            if o.round then
                value = math.floor((value or 0) + 0.5)
            end
            db()[o.key] = value
            if o.apply then
                o.apply(value)
            end
        end,
    }
end

-- Radio dropdown bound to a single profile key.
local function dropdown(o)
    return {
        kind = ST.Dropdown,
        name = o.name,
        tooltip = o.desc,
        default = o.default,
        values = o.values,
        height = o.height,
        isShown = o.isShown,
        get = o.get or function()
            return db()[o.key] or o.default
        end,
        set = o.set or function(_, value)
            db()[o.key] = value
            if o.apply then
                o.apply(value)
            end
        end,
    }
end

-- Multi-select dropdown bound to a profile key holding a selection map.
local function multidropdown(o)
    return {
        kind = ST.MultiDropdown,
        name = o.name,
        tooltip = o.desc,
        customText = o.customText,
        values = o.values,
        height = o.height,
        isShown = o.isShown,
        get = o.get,
        set = o.set,
    }
end

local function color(o)
    return {
        kind = ST.Color,
        name = o.name,
        hasOpacity = true,
        isShown = o.isShown,
        get = o.get,
        set = o.set,
        default = o.default,
    }
end

-- Shared value tables (mirror AddonSettings.lua) -----------------------------------
local ANCHOR_VALUES = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}
local ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local ANCHOR_ARRAY = makeArray(ANCHOR_VALUES, ANCHOR_ORDER)

local KEYBIND_ANCHOR_VALUES = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}
local KEYBIND_ANCHOR_ORDER =
    { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local KEYBIND_ANCHOR_ARRAY = makeArray(KEYBIND_ANCHOR_VALUES, KEYBIND_ANCHOR_ORDER)

local FONT_FLAG_VALUES =
    { OUTLINE = "Outline", THICKOUTLINE = "Thick Outline", MONOCHROME = "Monochrome", SLUG = "Slug" }
local FONT_FLAG_ORDER = { "MONOCHROME", "OUTLINE", "THICKOUTLINE", "SLUG" }
local FONT_FLAG_ARRAY = makeArray(FONT_FLAG_VALUES, FONT_FLAG_ORDER)

local VISIBILITY_RULE_VALUES = {
    SHOW_IN_COMBAT = "Always show in Combat",
    SHOW_IN_INSTANCE = "Always show in Instances",
    HIDE_IN_VEHICLES = "Hide in Vehicles & Mini-games",
    ALWAYS_HIDE_WHEN_FLYING = "Always hide when Flying",
    SHOW_WITH_ENEMY_TARGET = "Show with Enemy Target",
    SHOW_WITH_TARGET = "Show with any Target",
    HIDE_WHEN_FLYING = "Hide when Flying",
    HIDE_WHEN_NOT_FLYING = "Hide when not Flying",
    HIDE_WHEN_MOUNTED = "Hide when Mounted & Travel Form",
    HIDE_WHEN_RESTING = "Hide when Resting",
    HIDE_OUT_OF_COMBAT = "Hide out of Combat",
}
local VISIBILITY_RULE_ORDER = {
    "SHOW_IN_COMBAT",
    "SHOW_IN_INSTANCE",
    "HIDE_IN_VEHICLES",
    "ALWAYS_HIDE_WHEN_FLYING",
    "SHOW_WITH_ENEMY_TARGET",
    "SHOW_WITH_TARGET",
    "HIDE_WHEN_FLYING",
    "HIDE_WHEN_NOT_FLYING",
    "HIDE_WHEN_MOUNTED",
    "HIDE_WHEN_RESTING",
    "HIDE_OUT_OF_COMBAT",
}
local VISIBILITY_RULE_ARRAY = makeArray(VISIBILITY_RULE_VALUES, VISIBILITY_RULE_ORDER)

-- Cooldown font size options (with Default / Hide entries).
local COOLDOWN_SIZE_ARRAY = {
    { value = "NIL", text = "Default", label = "Default" },
    { value = "0", text = "Hide", label = "Hide" },
}
for size = 10, 38, 2 do
    COOLDOWN_SIZE_ARRAY[#COOLDOWN_SIZE_ARRAY + 1] =
        { value = tostring(size), text = tostring(size), label = tostring(size) }
end

-- Stack font size options ("Don't change" + sizes).
local STACK_SIZE_ARRAY = { { value = "NIL", text = "Don't change", label = "Don't change" } }
for size = 10, 38, 2 do
    STACK_SIZE_ARRAY[#STACK_SIZE_ARRAY + 1] = { value = tostring(size), text = tostring(size), label = tostring(size) }
end

-- Keybind font size options (no "Don't change").
local KEYBIND_SIZE_ARRAY = {}
for size = 6, 32, 2 do
    KEYBIND_SIZE_ARRAY[#KEYBIND_SIZE_ARRAY + 1] =
        { value = tostring(size), text = tostring(size), label = tostring(size) }
end

local function fontNameArray()
    local arr = { { value = "NIL", text = "Default font", label = "Default font" } }
    if not LSM then
        return arr
    end
    local fonts = LSM:HashTable(LSM.MediaType.FONT)
    local sorted = {}
    for name in pairs(fonts) do
        if name ~= "" then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)
    for _, name in ipairs(sorted) do
        arr[#arr + 1] = { value = name, text = name, label = name }
    end
    return arr
end

local function pct(value)
    return string.format("%.0f%%", (value or 0) * 100)
end
local function px(value)
    return string.format("%.0fpx", value or 0)
end
local function whole(value)
    return string.format("%.0f", value or 0)
end

-- Section builders -----------------------------------------------------------------

-- "Grow / Alignment" direction dropdown for the viewer (per-viewer key).
local function buildGrowDirection(list, cfg)
    if not cfg.growKey then
        return
    end
    local values
    if cfg.scope == "BuffBar" then
        values = {
            { value = "TOP", text = "Bars grow from |cff8ccd00Top|r" },
            { value = "BOTTOM", text = "Bars grow from |cff8ccd00Bottom|r" },
            { value = "ICONS_VERTICAL", text = "Only |cfffff100Icons|r |cff8ccd00Vertical|r" },
            { value = "ICONS_HORIZONTAL", text = "Only |cfffff100Icons|r |cff8ccd00Horizontal|r" },
            { value = "Disable", text = "|cffff2020Disable|r centering" },
        }
    else
        local frame = _G[cfg.frame]
        local horizontal = frame and frame.isHorizontal
        if cfg.scope == "BuffIcons" then
            values = {
                { value = "START", text = "Grow from the |cff8ccd00Start|r" },
                { value = "CENTER", text = "Grow from |cff8ccd00Center|r" },
                { value = "END", text = "Grow from the |cff8ccd00End|r" },
                { value = "Disable", text = "|cffff2020Disable|r centering" },
            }
        else
            values = {
                {
                    value = "TOP",
                    text = horizontal and "New Rows |cff8ccd00Below|r" or "New Columns to the |cff8ccd00Right|r",
                },
                {
                    value = "BOTTOM",
                    text = horizontal and "New Rows on |cff8ccd00Top|r" or "New Columns to the |cff8ccd00Left|r",
                },
                { value = "Disable", text = "|cffff2020Disable|r centering" },
            }
        end
    end
    list[#list + 1] = dropdown({
        name = "Alignment",
        key = cfg.growKey,
        default = cfg.growDefault,
        values = values,
        apply = refreshCDM,
        desc = "Dynamic alignment direction inside the viewer container.",
    })
end

-- Icon styling: square / border / zoom / rectangular (+ normalize for Utility).
local function buildIconStyling(list, cfg)
    if not cfg.icon then
        return
    end
    if ns.MasqueModule and ns.MasqueModule:IsActive() then
        return
    end
    local id = section(list, "icons", "Icons Styling")
    local squareKey = "cooldownManager_squareIcons_" .. cfg.scope
    add(
        list,
        checkbox({
            name = "Square Icons",
            key = squareKey,
            desc = "Apply square icon styling to this viewer.",
            apply = refreshIcons,
        }),
        id
    )
    add(
        list,
        slider({
            name = "Border Thickness",
            key = "cooldownManager_squareIconsBorder_" .. cfg.scope,
            default = 4,
            min = 0,
            max = 6,
            step = 1,
            formatter = px,
            apply = refreshIcons,
        }),
        id
    )
    add(
        list,
        slider({
            name = "Icon Zoom",
            key = "cooldownManager_squareIconsZoom_" .. cfg.scope,
            default = 0,
            min = 0,
            max = 0.5,
            step = 0.01,
            formatter = function(v)
                return string.format("%.2f", v or 0)
            end,
            apply = refreshIcons,
        }),
        id
    )

    local rectKey = "cooldownManager_experimental_enableRectangularIcons_" .. cfg.lower
    add(
        list,
        checkbox({
            name = "Rectangular Ratio",
            key = rectKey,
            desc = "Enable rectangular icons. |cffff0000Experimental feature, may cause issues!|r",
            apply = refreshIcons,
        }),
        id
    )
    add(
        list,
        slider({
            name = "Height to Width Ratio",
            key = rectKey .. "_percent",
            default = 0.8,
            min = 0.6,
            max = 0.9,
            step = 0.01,
            formatter = pct,
            round = false,
            isShown = function()
                return db()[rectKey] and true or false
            end,
            set = function(_, value)
                db()[rectKey .. "_percent"] = math.floor((value or 0) * 100 + 0.5) / 100
                refreshIcons()
            end,
        }),
        id
    )

    if cfg.normalize then
        add(
            list,
            checkbox({
                name = "Normalize Utility Icons Scaling",
                key = "cooldownManager_normalizeUtilitySize",
                desc = "Use Essential Cooldowns base icon size for Utility icons for a uniform look.",
                apply = refreshIcons,
            }),
            id
        )
    end
end

-- Cooldown number font (shared name/flags + per-viewer size).
local function buildCooldownFont(list, cfg)
    if not cfg.icon then
        return
    end
    local id = section(list, "cdfont", "Cooldown Number")

    local enabledKey = "cooldownManager_cooldownFontSize" .. cfg.scope .. "_enabled"
    local sizeKey = "cooldownManager_cooldownFontSize" .. cfg.scope
    local offXKey = "cooldownManager_cooldownText" .. cfg.scope .. "_offsetX"
    local offYKey = "cooldownManager_cooldownText" .. cfg.scope .. "_offsetY"

    -- Master gate: when off, the font / flags / size / offset widgets are hidden
    -- and nothing is overridden (the code restores defaults).
    local function whenEnabled()
        return db()[enabledKey] and true or false
    end

    add(
        list,
        checkbox({
            name = "Override Font",
            key = enabledKey,
            apply = refreshFont,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Font",
            height = 220,
            isShown = whenEnabled,
            values = fontNameArray(),
            get = function()
                local v = db().cooldownManager_cooldownFontName
                if not v or v == "NIL" then
                    return "NIL"
                end
                return v
            end,
            set = function(_, value)
                db().cooldownManager_cooldownFontName = value
                refreshFont()
            end,
            desc = "Font for ability cooldown numbers (shared across viewers).",
        }),
        id
    )
    add(
        list,
        multidropdown({
            name = "Font Flags",
            customText = "No Flags",
            isShown = whenEnabled,
            values = FONT_FLAG_ARRAY,
            get = function()
                return db().cooldownManager_cooldownFontFlags or {}
            end,
            set = function(_, value)
                if value.OUTLINE or value.THICKOUTLINE or value.MONOCHROME or value.SLUG then
                    db().cooldownManager_cooldownFontFlags = value
                else
                    db().cooldownManager_cooldownFontFlags = { OUTLINE = false }
                end
                refreshFont()
            end,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Font Size",
            values = COOLDOWN_SIZE_ARRAY,
            isShown = whenEnabled,
            get = function()
                local v = db()[sizeKey]
                return v ~= nil and tostring(v) or "NIL"
            end,
            set = function(_, value)
                if value == "NIL" then
                    db()[sizeKey] = "NIL"
                else
                    db()[sizeKey] = tonumber(value)
                end
                refreshFont()
            end,
        }),
        id
    )

    -- Countdown text position offset (separate per viewer).
    add(
        list,
        slider({
            name = "Text X Offset",
            key = offXKey,
            isShown = whenEnabled,
            default = 0,
            min = -40,
            max = 40,
            step = 1,
            round = true,
            formatter = whole,
            apply = refreshFont,
        }),
        id
    )
    add(
        list,
        slider({
            name = "Text Y Offset",
            key = offYKey,
            isShown = whenEnabled,
            default = 0,
            min = -40,
            max = 40,
            step = 1,
            round = true,
            formatter = whole,
            apply = refreshFont,
        }),
        id
    )
end

-- Cooldown swipe overlay colors (shared) -- icon viewers only.
local function buildSwipeColors(list, cfg)
    if not cfg.icon then
        return
    end
    local C = ns.CONSTANTS
    if not C then
        return
    end
    local id = section(list, "swipe", "Overlay Colors")
    add(
        list,
        checkbox({
            name = "Custom Overlay Colors",
            key = "cooldownManager_customSwipeColor_enabled",
            desc = "Enable custom coloring for the cooldown swipe overlay.",
        }),
        id
    )
    add(
        list,
        color({
            name = "Active Aura Color",
            get = function()
                local p = db()
                local d = C.DEFAULT_ACTIVE_SWIPE_COLOR
                return {
                    r = p.cooldownManager_customActiveColor_r or d.r,
                    g = p.cooldownManager_customActiveColor_g or d.g,
                    b = p.cooldownManager_customActiveColor_b or d.b,
                    a = p.cooldownManager_customActiveColor_a or d.a,
                }
            end,
            set = function(_, c)
                local p = db()
                p.cooldownManager_customActiveColor_r = c.r
                p.cooldownManager_customActiveColor_g = c.g
                p.cooldownManager_customActiveColor_b = c.b
                p.cooldownManager_customActiveColor_a = c.a
            end,
        }),
        id
    )
    add(
        list,
        color({
            name = "Cooldown Swipe Color",
            get = function()
                local p = db()
                local d = C.DEFAULT_COOLDOWN_SWIPE_COLOR
                return {
                    r = p.cooldownManager_customCDSwipeColor_r or d.r,
                    g = p.cooldownManager_customCDSwipeColor_g or d.g,
                    b = p.cooldownManager_customCDSwipeColor_b or d.b,
                    a = p.cooldownManager_customCDSwipeColor_a or d.a,
                }
            end,
            set = function(_, c)
                local p = db()
                p.cooldownManager_customCDSwipeColor_r = c.r
                p.cooldownManager_customCDSwipeColor_g = c.g
                p.cooldownManager_customCDSwipeColor_b = c.b
                p.cooldownManager_customCDSwipeColor_a = c.a
            end,
        }),
        id
    )
end

-- Stack number anchor / size / offsets (per viewer).
local function buildStacks(list, cfg)
    if not cfg.stacks then
        return
    end
    local id = section(list, "stacks", "Stack Numbers")
    local enabledKey = "cooldownManager_stackAnchor" .. cfg.scope .. "_enabled"
    local pointKey = "cooldownManager_stackAnchor" .. cfg.scope .. "_point"
    local sizeKey = "cooldownManager_stackFontSize" .. cfg.scope
    local offXKey = "cooldownManager_stackAnchor" .. cfg.scope .. "_offsetX"
    local offYKey = "cooldownManager_stackAnchor" .. cfg.scope .. "_offsetY"

    -- Master gate: the enable checkbox is always shown; the rest of the options
    -- appear only while it's enabled.
    local function whenEnabled()
        return db()[enabledKey] and true or false
    end

    -- Stack font name / flags are shared across all viewers, so changing them
    -- refreshes every stack viewer (and trackers) rather than just this one.
    local function refreshStackFont()
        if ns.Stacks then
            ns.Stacks:RefreshAll()
        end
        if ns.TrackerItemViewer then
            ns.TrackerItemViewer:RefreshStyling()
        end
    end

    add(
        list,
        checkbox({
            name = "Override Stack Numbers",
            key = enabledKey,
            apply = function()
                refreshStacks(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Font",
            height = 220,
            isShown = whenEnabled,
            values = fontNameArray(),
            get = function()
                local v = db().cooldownManager_stackFontName
                if not v or v == "NIL" then
                    return "NIL"
                end
                return v
            end,
            set = function(_, value)
                db().cooldownManager_stackFontName = value
                refreshStackFont()
            end,
            desc = "Font for ability stack numbers (shared across viewers).",
        }),
        id
    )
    add(
        list,
        multidropdown({
            name = "Font Flags",
            customText = "No Flags",
            isShown = whenEnabled,
            values = FONT_FLAG_ARRAY,
            get = function()
                return db().cooldownManager_stackFontFlags or {}
            end,
            set = function(_, value)
                if value.OUTLINE or value.THICKOUTLINE or value.MONOCHROME or value.SLUG then
                    db().cooldownManager_stackFontFlags = value
                else
                    db().cooldownManager_stackFontFlags = { OUTLINE = false }
                end
                refreshStackFont()
            end,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Anchor",
            key = pointKey,
            default = "BOTTOMRIGHT",
            isShown = whenEnabled,
            values = ANCHOR_ARRAY,
            apply = function()
                refreshStacks(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Font Size",
            values = STACK_SIZE_ARRAY,
            isShown = whenEnabled,
            get = function()
                local v = db()[sizeKey]
                return v ~= nil and tostring(v) or "NIL"
            end,
            set = function(_, value)
                if value == "NIL" then
                    db()[sizeKey] = nil
                else
                    local n = tonumber(value)
                    db()[sizeKey] = n and math.floor(n + 0.5) or nil
                end
                refreshStacks(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        slider({
            name = "X Offset",
            key = offXKey,
            isShown = whenEnabled,
            default = 0,
            min = -40,
            max = 40,
            step = 1,
            round = true,
            formatter = whole,
            apply = function()
                refreshStacks(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        slider({
            name = "Y Offset",
            key = offYKey,
            isShown = whenEnabled,
            default = 0,
            min = -40,
            max = 40,
            step = 1,
            round = true,
            formatter = whole,
            apply = function()
                refreshStacks(cfg.frame)
            end,
        }),
        id
    )
end

-- Keybind text (Essential / Utility).
local function buildKeybinds(list, cfg)
    if not cfg.keybind then
        return
    end
    local id = section(list, "keybinds", "Keybind Text")
    local showKey = "cooldownManager_showKeybinds_" .. cfg.scope
    local anchorKey = "cooldownManager_keybindAnchor_" .. cfg.scope
    local sizeKey = "cooldownManager_keybindFontSize_" .. cfg.scope
    local offXKey = "cooldownManager_keybindOffsetX_" .. cfg.scope
    local offYKey = "cooldownManager_keybindOffsetY_" .. cfg.scope

    -- Master gate: the show checkbox is always visible; the rest of the options
    -- appear only while it's enabled.
    local function whenEnabled()
        return db()[showKey] and true or false
    end

    add(
        list,
        checkbox({
            name = "Show Keybind Text",
            key = showKey,
            apply = function()
                if ns.Keybinds then
                    ns.Keybinds:OnSettingChanged(cfg.scope)
                end
            end,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Anchor",
            key = anchorKey,
            default = "TOPRIGHT",
            isShown = whenEnabled,
            values = KEYBIND_ANCHOR_ARRAY,
            apply = function()
                refreshKeybinds(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        dropdown({
            name = "Font Size",
            values = KEYBIND_SIZE_ARRAY,
            isShown = whenEnabled,
            get = function()
                return tostring(db()[sizeKey] or 14)
            end,
            set = function(_, value)
                local n = tonumber(value)
                db()[sizeKey] = n and math.floor(n + 0.5) or 14
                refreshKeybinds(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        slider({
            name = "X Offset",
            key = offXKey,
            isShown = whenEnabled,
            default = -3,
            min = -40,
            max = 40,
            step = 1,
            round = true,
            formatter = whole,
            apply = function()
                refreshKeybinds(cfg.frame)
            end,
        }),
        id
    )
    add(
        list,
        slider({
            name = "Y Offset",
            key = offYKey,
            isShown = whenEnabled,
            default = -3,
            min = -40,
            max = 40,
            step = 1,
            round = true,
            formatter = whole,
            apply = function()
                refreshKeybinds(cfg.frame)
            end,
        }),
        id
    )
end

-- Tweaks that affect cooldown icon viewers (Essential / Utility).
local function buildTweaks(list, cfg)
    if not cfg.tweaks then
        return
    end
    local id = section(list, "tweaks", "Tweaks")
    add(
        list,
        checkbox({
            name = "Hide cooldown flash",
            key = "cooldownManager_hideCooldownFlash",
            desc = "Hide the bright flash when an ability comes off cooldown.",
            apply = refreshStyle,
        }),
        id
    )
    add(
        list,
        checkbox({
            name = "Rotation Highlight on CDM",
            desc = "Show a border when an ability is suggested by the rotation helper.",
            get = function()
                return db().cooldownManager_showHighlight_Essential and db().cooldownManager_showHighlight_Utility
            end,
            set = function(_, value)
                db().cooldownManager_showHighlight_Essential = value
                db().cooldownManager_showHighlight_Utility = value
                if value then
                    C_CVar.SetCVar("assistedCombatHighlight", "1")
                end
                if ns.Assistant then
                    ns.Assistant:OnSettingChanged("Essential")
                    ns.Assistant:OnSettingChanged("Utility")
                end
            end,
        }),
        id
    )
    add(
        list,
        checkbox({
            name = "Hide Range Check",
            key = "cooldownManager_hideRangeCheck",
            desc = "Stop icons from dimming when the target is out of range.",
            apply = function()
                if ns.RangeCheck then
                    ns.RangeCheck:RefreshAll()
                end
            end,
        }),
        id
    )
    add(
        list,
        checkbox({
            name = "Desaturate Icon Under Aura",
            key = "cooldownManager_desaturate_under_aura",
            desc = "Desaturate cooldown icons when there is an active Aura for that ability.",
            apply = refreshStyle,
        }),
        id
    )
    add(
        list,
        checkbox({
            name = "Hide GCD",
            key = "cooldownManager_hide_gcd",
            desc = "Hide the GCD cooldown spiral on cooldown icons.",
            apply = refreshStyle,
        }),
        id
    )

    if cfg.scope == "Utility" then
        add(
            list,
            checkbox({
                name = "Sync Utility width to Essential",
                key = "cooldownManager_limitUtilitySizeToEssential",
                desc = "Limit Utility width to the width of Essential.",
                apply = function()
                    ns.CooldownManager.ForceRefreshAll()
                end,
            }),
            id
        )
        add(
            list,
            checkbox({
                name = "Dim Utility when not on CD",
                key = "cooldownManager_utility_dimWhenNotOnCD",
                desc = "Dim Utility icons when they are not on cooldown. |cffff0000Higher CPU usage|r",
                apply = function(value)
                    ns.CooldownManager.ForceRefresh({ utility = true })
                    if not value then
                        ns.CooldownManager.RestoreUtilityAlpha()
                    end
                end,
            }),
            id
        )
        add(
            list,
            slider({
                name = "Dim Opacity",
                key = "cooldownManager_utility_dimOpacity",
                default = 0.3,
                min = 0,
                max = 0.9,
                step = 0.05,
                formatter = pct,
                isShown = function()
                    return db().cooldownManager_utility_dimWhenNotOnCD and true or false
                end,
                apply = function()
                    ns.CooldownManager.ForceRefresh({ utility = true })
                end,
            }),
            id
        )
    end
end

-- Shared cooldown-number font controls (the font name & flags are global, so
-- these edit the same keys as the viewers). Exposed so custom trackers can embed
-- identical controls. opts = { parentId, isShown }.
function EMVS:BuildCooldownFontNameSetting(opts)
    opts = opts or {}
    return {
        kind = ST.Dropdown,
        name = "Font",
        height = 220,
        parentId = opts.parentId,
        isShown = opts.isShown,
        values = fontNameArray(),
        get = function()
            local v = db().cooldownManager_cooldownFontName
            if not v or v == "NIL" then
                return "NIL"
            end
            return v
        end,
        set = function(_, value)
            db().cooldownManager_cooldownFontName = value
            refreshFont()
        end,
        desc = "Font for ability cooldown numbers (shared across viewers & trackers).",
    }
end

function EMVS:BuildCooldownFontFlagsSetting(opts)
    opts = opts or {}
    return {
        kind = ST.MultiDropdown,
        name = "Font Flags",
        customText = "No Flags",
        parentId = opts.parentId,
        isShown = opts.isShown,
        values = FONT_FLAG_ARRAY,
        get = function()
            return db().cooldownManager_cooldownFontFlags or {}
        end,
        set = function(_, value)
            if value.OUTLINE or value.THICKOUTLINE or value.MONOCHROME or value.SLUG then
                db().cooldownManager_cooldownFontFlags = value
            else
                db().cooldownManager_cooldownFontFlags = { OUTLINE = false }
            end
            refreshFont()
        end,
    }
end

-- Build the Show/Hide visibility-rules control for a frame. Exposed on EMVS so
-- custom trackers can embed the same control in their own Edit Mode settings.
function EMVS:BuildVisibilitySetting(frameName)
    return multidropdown({
        name = "Visibility",
        customText = "No rules (always visible)",
        height = 340,
        values = VISIBILITY_RULE_ARRAY,
        get = function()
            local perViewer = db().cooldownManager_visibility_perViewer
            return (perViewer and perViewer[frameName]) or {}
        end,
        set = function(_, value)
            if not db().cooldownManager_visibility_perViewer then
                db().cooldownManager_visibility_perViewer = {}
            end
            db().cooldownManager_visibility_perViewer[frameName] = value
            if ns.CMCVisibility then
                ns.CMCVisibility:Initialize({ [frameName] = true })
            end
        end,
    })
end

-- Visibility rules (all viewers). Added as a single trailing row (no section
-- header) at the very end of the viewer's settings.
local function buildVisibility(list, cfg)
    add(list, EMVS:BuildVisibilitySetting(cfg.frame))
end

-- Per-viewer configuration ---------------------------------------------------------
local CONFIG = {
    EssentialCooldownViewer = {
        frame = "EssentialCooldownViewer",
        scope = "Essential",
        lower = "essential",
        title = "Essential Cooldowns",
        growKey = "cooldownManager_centerEssential_growFromDirection",
        growDefault = "TOP",
        icon = true,
        stacks = true,
        keybind = true,
        tweaks = true,
    },
    UtilityCooldownViewer = {
        frame = "UtilityCooldownViewer",
        scope = "Utility",
        lower = "utility",
        title = "Utility Cooldowns",
        growKey = "cooldownManager_centerUtility_growFromDirection",
        growDefault = "TOP",
        icon = true,
        stacks = true,
        keybind = true,
        tweaks = true,
        normalize = true,
    },
    BuffIconCooldownViewer = {
        frame = "BuffIconCooldownViewer",
        scope = "BuffIcons",
        lower = "buffIcons",
        title = "Tracked Buff Icons",
        growKey = "cooldownManager_alignBuffIcons_growFromDirection",
        growDefault = "CENTER",
        icon = true,
        stacks = true,
        keybind = false,
        tweaks = false,
    },
    BuffBarCooldownViewer = {
        frame = "BuffBarCooldownViewer",
        scope = "BuffBar",
        title = "Tracked Buff Bars",
        growKey = "cooldownManager_alignBuffBars_growFromDirection",
        growDefault = "BOTTOM",
        icon = false,
        stacks = false,
        keybind = false,
        tweaks = false,
    },
}

function EMVS:IsViewer(frameName)
    return CONFIG[frameName] ~= nil
end

function EMVS:GetTitle(frameName)
    local cfg = CONFIG[frameName]
    return cfg and cfg.title or frameName
end

-- Build the ordered LibEQOLEditMode setting list for a viewer frame name.
function EMVS:BuildForViewer(frameName)
    local cfg = CONFIG[frameName]
    if not cfg then
        return nil
    end
    local list = {}
    buildGrowDirection(list, cfg)
    buildIconStyling(list, cfg)
    buildCooldownFont(list, cfg)
    buildSwipeColors(list, cfg)
    buildStacks(list, cfg)
    buildKeybinds(list, cfg)
    buildTweaks(list, cfg)
    buildVisibility(list, cfg)
    return list
end
