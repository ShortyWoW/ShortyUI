-- Cursor Ring - Core (Retail 11.2.x + Midnight 12.0-safe)
-- Anchors a ring to the mouse cursor and (optionally) shows a GCD swipe using Blizzard's Cooldown widget.

local addonName, ns = ...
local L = ns.L or {}

local function T(key)
    local value = L[key]
    if value == nil or value == "" then
        return key
    end
    return value
end

-- Locals
local UIParent = UIParent
local CreateFrame = CreateFrame
local GetScaledCursorPosition = GetScaledCursorPosition
local GetCursorPosition = GetCursorPosition
local GetAddOnMetadata = GetAddOnMetadata
local UnitClass = UnitClass
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerDisplayMod = UnitPowerDisplayMod
local CopyTable = CopyTable
local C_AddOns = C_AddOns
local C_Spell = C_Spell
local strlower = string.lower
local strupper = string.upper
local tostring = tostring
local type = type
local GetSpellCooldown = GetSpellCooldown
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local C_ClassColor = C_ClassColor
local C_Timer = C_Timer
local math = math
local cos = math.cos
local sin = math.sin
local pi2 = math.rad(360)
local halfpi = math.rad(90)
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local KAGROK_LAUNCHER_CORE_NAME = "KagrokLauncherCore"
local EMPOWER_TIER_COLORS = {
    { 0.31, 0.84, 1.00 }, -- approximate ui-castingbar-tier1-empower
    { 0.82, 0.93, 0.31 }, -- approximate ui-castingbar-tier2-empower
    { 1.00, 0.62, 0.20 }, -- approximate ui-castingbar-tier3-empower
}

-- Debug flag (chat spam only when true)
ns.DEBUG_GCD = false

-- Fixed ring/swipe texture + inverse mask punchout.
ns.texturePath = "Interface\\AddOns\\CursorRing\\Media\\Solid.blp"
ns.inverseMaskPath = "Interface\\AddOns\\CursorRing\\Media\\SolidInverseMask.blp"
ns.baseTextureSize = 512
ns.maskArtSizePx = 1024      -- Full mask canvas size
ns.maskHoleSizePx = 256      -- Transparent center hole diameter in the mask art

-- Account-wide defaults
ns.defaults = {
    ringRadius          = 35,
    ringThickness       = 50,         -- 1..100 (100 = no mask)
    ringMargin          = 2,          -- spacing between concentric rings (in px)
    inCombatAlpha       = 0.70,
    outCombatAlpha      = 0.30,

    -- Color selection
    -- colorMode:
    --   "class"    = player class
    --   "highvis"  = bright green
    --   "custom"   = customColor
    --   "gradient" = gradientColor1/2 + gradientAngle
    --   <class id> = forced specific class color (for swipe / solid ring)
    useClassColor       = true,       -- legacy, migrated on login
    useHighVis          = false,      -- legacy, migrated on login
    colorMode           = "class",
    customColor         = { r = 1, g = 1, b = 1 },

    visible             = true,
    hideOnRightClick    = true,

    -- Help message behavior
    helpMessageShownOnce = false,
    showHelpOnLogin      = false,

    -- Offsets relative to cursor
    offsetX             = 0,
    offsetY             = 0,

    -- Gradient config (used when colorMode == "gradient")
    -- gradientEnabled is legacy and ignored now
    gradientAngle       = 315,         -- degrees, 0..360
    gradientColor1      = { r = 1, g = 1, b = 1 },
    gradientColor2      = { r = 0, g = 0, b = 0 },
}

-- Per-character defaults
ns.charDefaults = {
    gcdEnabled        = true,          -- GCD swipe ON by default
    gcdStyle          = "simple",      -- "simple" or "blizzard"
    gcdDimMultiplier  = 0.35,          -- Emphasis for hiding the ring under the GCD swipe
    gcdReverse        = false,         -- when true, swipe fills the ring instead of emptying
    castRingEnabled   = false,         -- optional cast progress ring
    castRingThickness = 25,            -- 1..99 (100 would always overlap inner rings)
    castRingColor     = { r = 0.20, g = 0.80, b = 1.00 },
    resourceRingEnabled = false,       -- optional secondary resource ring
    resourceRingThickness = 15,        -- 1..99 (100 would always overlap inner rings)
    trailEnabled      = false,         -- optional cursor trail renderer
    trailStyle        = "sprites",     -- legacy migration source for layered trails
    trailGlowEnabled  = true,
    trailRibbonEnabled = false,
    trailParticleEnabled = false,
    trailAsset        = "metalglow",   -- selected Blizzard-art trail preset asset
    trailColorMode    = "ring",        -- legacy migration source for layered trails
    trailGlowColorMode = "ring",
    trailRibbonColorMode = "ring",
    trailParticleColorMode = "ring",
    trailBlendMode    = "ADD",         -- "ADD" or "BLEND"
    trailCustomColor  = { r = 1.00, g = 1.00, b = 1.00 }, -- legacy migration source
    trailGlowCustomColor = { r = 1.00, g = 1.00, b = 1.00 },
    trailRibbonCustomColor = { r = 1.00, g = 1.00, b = 1.00 },
    trailParticleCustomColor = { r = 1.00, g = 1.00, b = 1.00 },
    trailAlpha        = 60,            -- 0..100
    trailSize         = 24,            -- base sprite size
    trailLength       = 320,           -- milliseconds
    trailSegments     = 8,             -- 2..24
    trailSampleRate   = 36,            -- Hz
    trailMinDistance  = 6,             -- px
    trailRibbonWidth  = 18,            -- px
    trailHeadScale    = 120,           -- percent
    trailParticleCount = 20,           -- pooled particle regions
    trailParticleBurst = 2,            -- particles per sample
    trailParticleSpread = 18,          -- px
    trailParticleSpeed = 80,           -- px/sec
    trailParticleSize = 12,            -- px
}
ns.KagrokLauncherSharedIcon = "Interface\\AddOns\\" .. KAGROK_LAUNCHER_CORE_NAME .. "\\Media\\Launcher\\kagrok_full.png"
ns.KagrokLauncherSocialMediaRoot = "Interface\\AddOns\\" .. KAGROK_LAUNCHER_CORE_NAME .. "\\Media\\Social\\"

function ns.GetSharedLauncher()
    local launcher = ns.KagrokSharedLauncher
    if type(launcher) == "table" and type(launcher.RegisterAddon) == "function" then
        return launcher
    end

    launcher = _G.KagrokSharedLauncher
    if type(launcher) == "table" and type(launcher.RegisterAddon) == "function" then
        ns.KagrokSharedLauncher = launcher
        return launcher
    end

    return nil
end

function ns.GetSharedDevInfoModule()
    local module = ns.DevInfoModule
    if type(module) == "table" and type(module.Create) == "function" then
        return module
    end

    module = _G.KagrokDevInfoModule
    if type(module) == "table" and type(module.Create) == "function" then
        ns.DevInfoModule = module
        return module
    end

    return nil
end

local function StripColorCodes(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local function GetAddonMetadataValue(field)
    local value = ""
    if type(GetAddOnMetadata) == "function" then
        value = tostring(GetAddOnMetadata(addonName, field) or "")
        if value == "" then
            value = tostring(GetAddOnMetadata("CursorRing", field) or "")
        end
    end
    if value == "" and C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        value = tostring(C_AddOns.GetAddOnMetadata(addonName, field) or "")
        if value == "" then
            value = tostring(C_AddOns.GetAddOnMetadata("CursorRing", field) or "")
        end
    end
    return value
end

local function GetLauncherDisplayName()
    local title = StripColorCodes(GetAddonMetadataValue("Title"))
    if title == "" then
        return T("Cursor Ring +")
    end
    return title
end

local function GetLauncherPriority()
    local priority = tonumber(GetAddonMetadataValue("X-KagrokLauncherPriority"))
    if not priority then
        return 100
    end
    return priority
end

local function PrintAddonMessage(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00CursorRing:|r " .. tostring(text))
    end
end

function ns.EnsureDevInfoModule()
    if ns.devInfoModule then
        return ns.devInfoModule
    end

    local module = ns.GetSharedDevInfoModule and ns.GetSharedDevInfoModule()
    if type(module) ~= "table" or type(module.Create) ~= "function" then
        return nil
    end

    ns.devInfoModule = module:Create(ns, {
        addon_name = addonName,
        frame_prefix = addonName,
        media_root = ns.KagrokLauncherSocialMediaRoot,
        panel_title = T("Developer Info"),
        profile_body = T("Cursor Ring + and other World of Warcraft projects.\n\nClick any platform on the right to open a copyable link."),
        print = PrintAddonMessage,
    })
    return ns.devInfoModule
end

function ns.ShowDeveloperInfoPanel()
    local module = ns.EnsureDevInfoModule and ns.EnsureDevInfoModule()
    if module and type(module.ShowPanel) == "function" then
        return module:ShowPanel()
    end
    return false
end

local function EnsureLauncherDB()
    CursorRingDB = CursorRingDB or CopyTable(ns.defaults)
    CursorRingCharDB = CursorRingCharDB or CopyTable(ns.charDefaults)
    return CursorRingDB, CursorRingCharDB
end

function ns.BuildSharedLauncherMenuItems()
    local db, cdb = EnsureLauncherDB()
    local function ToggleMenuItem(label, enabled, apply)
        return {
            text = string.format("%s: %s", label, enabled and T("On") or T("Off")),
            func = function()
                apply(not enabled)
                if ns.Refresh then
                    ns.Refresh()
                end
            end,
        }
    end

    return {
        ToggleMenuItem(T("Main Ring"), db.visible ~= false, function(value)
            db.visible = value
        end),
        ToggleMenuItem(T("Cast Bar"), cdb.castRingEnabled == true, function(value)
            cdb.castRingEnabled = value
        end),
        ToggleMenuItem(T("2nd Resource"), cdb.resourceRingEnabled == true, function(value)
            cdb.resourceRingEnabled = value
        end),
    }
end

function ns.BuildSharedLauncherSharedItems()
    return {
        {
            key = "developer_info",
            text = T("Developer Info"),
            order = 100,
            func = function()
                ns.ShowDeveloperInfoPanel()
            end,
        },
    }
end

function ns.EnsureSharedLauncher()
    if ns.sharedLauncher and ns._sharedLauncherRegistered then
        return ns.sharedLauncher
    end
    if ns.sharedLauncher and ns._sharedLauncherRegistrationFailed then
        return ns.sharedLauncher
    end

    local launcher = ns.GetSharedLauncher and ns.GetSharedLauncher()
    if type(launcher) ~= "table" or type(launcher.RegisterAddon) ~= "function" then
        return nil
    end

    ns.sharedLauncher = launcher
    local ok = pcall(launcher.RegisterAddon, launcher, {
        id = addonName,
        addon_name = addonName,
        name = GetLauncherDisplayName(),
        priority = GetLauncherPriority(),
        icon = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon.tga",
        shared_icon = ns.KagrokLauncherSharedIcon,
        is_enabled = function()
            return true
        end,
        left_click = function()
            if type(ns.OpenOptions) == "function" then
                ns.OpenOptions()
            end
        end,
        tooltip = function(_, tooltip)
            local db = CursorRingDB or ns.defaults
            tooltip:SetText(GetLauncherDisplayName())
            tooltip:AddLine(T("Left Click: Open settings"), 1, 1, 1)
            tooltip:AddLine(T("Right Click: Launcher menu"), 1, 1, 1)
            tooltip:AddLine(T("Drag: Move along minimap"), 0.65, 0.85, 1.0)
            tooltip:AddLine(" ")
            tooltip:AddDoubleLine(T("Ring"), (db.visible ~= false) and T("Shown") or T("Hidden"), 1, 1, 1, 0.4, 0.9, 0.4)
        end,
        menu_items = function()
            return ns.BuildSharedLauncherMenuItems()
        end,
        shared_items = function()
            return ns.BuildSharedLauncherSharedItems()
        end,
    })
    if not ok then
        ns._sharedLauncherRegistrationFailed = true
        return launcher
    end
    ns._sharedLauncherRegistered = true
    ns._sharedLauncherRegistrationFailed = nil
    return launcher
end

function ns.EnsureMinimapButton()
    local launcher = ns.EnsureSharedLauncher and ns.EnsureSharedLauncher()
    if launcher and launcher.EnsureButton then
        local ok, button = pcall(launcher.EnsureButton, launcher)
        if ok then
            return button
        end
    end
    return nil
end

function ns.RefreshSharedLauncher()
    local launcher = ns.EnsureSharedLauncher and ns.EnsureSharedLauncher()
    if launcher and launcher.Refresh then
        pcall(launcher.Refresh, launcher)
    end
end

local function applyTextureSampling(texture)
    if not texture then return end
    if texture.SetTexelSnappingBias then
        texture:SetTexelSnappingBias(0)
    end
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
    end
end

local function SetTextureCompat(texture, path)
    if not (texture and path) then return end
    local ok = pcall(texture.SetTexture, texture, path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
    if not ok then
        texture:SetTexture(path)
    end
end

local function setTextureSmooth(texture, path)
    if not (texture and path) then return end
    SetTextureCompat(texture, path)
    applyTextureSampling(texture)
end

local function setMaskTextureSmooth(maskTexture, path)
    if not (maskTexture and path) then return end
    SetTextureCompat(maskTexture, path)
    applyTextureSampling(maskTexture)
end

local function GetScaledCursorPositionCompat()
    if type(GetScaledCursorPosition) == "function" then
        return GetScaledCursorPosition()
    end
    local x, y = GetCursorPosition()
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if scale == 0 then
        scale = 1
    end
    return (x or 0) / scale, (y or 0) / scale
end

local function GetClassColorRGB(classFile)
    if type(classFile) ~= "string" or classFile == "" then
        return nil
    end

    if C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
        local c = C_ClassColor.GetClassColor(classFile)
        if not c then
            c = C_ClassColor.GetClassColor(strupper(classFile))
        end
        if c and c.r and c.g and c.b then
            return c.r, c.g, c.b
        end
    end

    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    if colors then
        local c = colors[strupper(classFile)]
        if c and c.r and c.g and c.b then
            return c.r, c.g, c.b
        end
    end

    return nil
end

-- Addon-owned radial spinner used by simple GCD style.
local function CreateSpinner(parent)
    local function Transform(tx, x, y, angle, aspect)
        local c, s = cos(angle), sin(angle)
        local ay, oy = y / aspect, 0.5 / aspect
        local ULx, ULy = 0.5 + (x - 0.5) * c - (ay - oy) * s, (oy + (ay - oy) * c + (x - 0.5) * s) * aspect
        local LLx, LLy = 0.5 + (x - 0.5) * c - (ay + oy) * s, (oy + (ay + oy) * c + (x - 0.5) * s) * aspect
        local URx, URy = 0.5 + (x + 0.5) * c - (ay - oy) * s, (oy + (ay - oy) * c + (x + 0.5) * s) * aspect
        local LRx, LRy = 0.5 + (x + 0.5) * c - (ay + oy) * s, (oy + (ay + oy) * c + (x + 0.5) * s) * aspect
        tx:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
    end

    local function OnPlayUpdate(self)
        self:SetScript("OnUpdate", nil)
        self:Pause()
    end

    local function OnPlay(self)
        self:SetScript("OnUpdate", OnPlayUpdate)
    end

    local function SetValue(self, value)
        if value > 1 then value = 1 end
        if value < 0 then value = 0 end
        if self._reverse then value = 1 - value end

        local q, quadrant = self._clockwise and (1 - value) or value, 4
        if q >= 0.75 then
            quadrant = 1
        elseif q >= 0.5 then
            quadrant = 2
        elseif q >= 0.25 then
            quadrant = 3
        else
            quadrant = 4
        end

        if self._quadrant ~= quadrant then
            self._quadrant = quadrant
            if self._clockwise then
                for i = 1, 4 do self._textures[i]:SetShown(i < quadrant) end
            else
                for i = 1, 4 do self._textures[i]:SetShown(i > quadrant) end
            end
            self._scrollframe:SetAllPoints(self._textures[quadrant])
        end

        local rads = value * pi2
        if not self._clockwise then rads = -rads + halfpi end
        Transform(self._wedge, -0.5, -0.5, rads, self._aspect)
        self._rotation:SetRadians(-rads)
    end

    local function SetClockwise(self, clockwise) self._clockwise = not not clockwise end
    local function SetReverse(self, reverse) self._reverse = not not reverse end

    local function OnSizeChanged(self, width, height)
        self._wedge:SetSize(width, height)
        self._aspect = width / height
    end

    local function CreateTextureFunction(func)
        return function(self, ...)
            for i = 1, 4 do
                local tx = self._textures[i]
                tx[func](tx, ...)
            end
            self._wedge[func](self._wedge, ...)
        end
    end

    local spinner = CreateFrame("Frame", nil, parent)
    spinner:SetAllPoints()

    local scrollframe = CreateFrame("ScrollFrame", nil, spinner)
    scrollframe:SetPoint("BOTTOMLEFT", spinner, "CENTER")
    scrollframe:SetPoint("TOPRIGHT")
    spinner._scrollframe = scrollframe

    local scrollchild = CreateFrame("Frame", nil, scrollframe)
    scrollframe:SetScrollChild(scrollchild)
    scrollchild:SetAllPoints(scrollframe)

    local wedge = scrollchild:CreateTexture(nil, "OVERLAY")
    wedge:SetPoint("BOTTOMRIGHT", spinner, "CENTER")
    applyTextureSampling(wedge)
    spinner._wedge = wedge

    local trTexture = spinner:CreateTexture(nil, "OVERLAY")
    trTexture:SetPoint("BOTTOMLEFT", spinner, "CENTER")
    trTexture:SetPoint("TOPRIGHT")
    trTexture:SetTexCoord(0.5, 1, 0, 0.5)
    applyTextureSampling(trTexture)

    local brTexture = spinner:CreateTexture(nil, "OVERLAY")
    brTexture:SetPoint("TOPLEFT", spinner, "CENTER")
    brTexture:SetPoint("BOTTOMRIGHT")
    brTexture:SetTexCoord(0.5, 1, 0.5, 1)
    applyTextureSampling(brTexture)

    local blTexture = spinner:CreateTexture(nil, "OVERLAY")
    blTexture:SetPoint("TOPRIGHT", spinner, "CENTER")
    blTexture:SetPoint("BOTTOMLEFT")
    blTexture:SetTexCoord(0, 0.5, 0.5, 1)
    applyTextureSampling(blTexture)

    local tlTexture = spinner:CreateTexture(nil, "OVERLAY")
    tlTexture:SetPoint("BOTTOMRIGHT", spinner, "CENTER")
    tlTexture:SetPoint("TOPLEFT")
    tlTexture:SetTexCoord(0, 0.5, 0, 0.5)
    applyTextureSampling(tlTexture)

    spinner._textures = { trTexture, brTexture, blTexture, tlTexture }
    spinner._quadrant = nil
    spinner._clockwise = true
    spinner._reverse = false
    spinner._aspect = 1
    spinner:HookScript("OnSizeChanged", OnSizeChanged)

    spinner.SetTexture = CreateTextureFunction("SetTexture")
    spinner.SetBlendMode = CreateTextureFunction("SetBlendMode")
    spinner.SetVertexColor = CreateTextureFunction("SetVertexColor")
    spinner.SetClockwise = SetClockwise
    spinner.SetReverse = SetReverse
    spinner.SetValue = SetValue

    local group = wedge:CreateAnimationGroup()
    local rotation = group:CreateAnimation("Rotation")
    spinner._rotation = rotation
    rotation:SetDuration(0)
    rotation:SetEndDelay(1)
    rotation:SetOrigin("BOTTOMRIGHT", 0, 0)
    group:SetScript("OnPlay", OnPlay)
    group:Play()

    spinner._maskBindings = {}
    if spinner.CreateMaskTexture then
        for i = 1, 4 do
            local tx = spinner._textures[i]
            if tx.AddMaskTexture then
                local m = spinner:CreateMaskTexture(nil, "ARTWORK")
                -- Use spinner-wide mask space so all segments share one centered punchout.
                m:SetAllPoints(spinner)
                setMaskTextureSmooth(m, ns.inverseMaskPath)
                tx:AddMaskTexture(m)
                table.insert(spinner._maskBindings, { texture = tx, mask = m, attached = true })
            end
        end
        if wedge.AddMaskTexture then
            local wm = spinner:CreateMaskTexture(nil, "ARTWORK")
            wm:SetAllPoints(spinner)
            setMaskTextureSmooth(wm, ns.inverseMaskPath)
            wedge:AddMaskTexture(wm)
            table.insert(spinner._maskBindings, { texture = wedge, mask = wm, attached = true })
        end
    end

    spinner:Hide()
    return spinner
end

-- Primary frames
local ring = CreateFrame("Frame", nil, UIParent)
ring:SetFrameStrata("TOOLTIP")

local tex = ring:CreateTexture(nil, "ARTWORK")
tex:SetAllPoints()
applyTextureSampling(tex)

local ringMask = nil
local ringMaskAttached = false
if ring.CreateMaskTexture and tex.AddMaskTexture then
    ringMask = ring:CreateMaskTexture(nil, "ARTWORK")
    ringMask:SetAllPoints(tex)
    setMaskTextureSmooth(ringMask, ns.inverseMaskPath)
    tex:AddMaskTexture(ringMask)
    ringMaskAttached = true
end

-- GCD Cooldown overlay (Blizzard template animates; we do not compute times)
local gcd = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
gcd:ClearAllPoints()
gcd:SetPoint("CENTER", ring, "CENTER")
gcd:SetSize(ns.baseTextureSize, ns.baseTextureSize)
gcd:SetScale(1)
gcd:EnableMouse(false)
if gcd.SetDrawSwipe then gcd:SetDrawSwipe(true) end
if gcd.SetDrawEdge then gcd:SetDrawEdge(true) end
if gcd.SetHideCountdownNumbers then gcd:SetHideCountdownNumbers(true) end
if gcd.SetUseCircularEdge then gcd:SetUseCircularEdge(true) end
gcd:SetFrameStrata("TOOLTIP")
gcd:SetFrameLevel(ring:GetFrameLevel() + 3)

local gcdSimple = CreateSpinner(ring)

local resourceRingFrame = CreateFrame("Frame", nil, ring)
resourceRingFrame:SetPoint("CENTER", ring, "CENTER")
resourceRingFrame:SetSize(ns.baseTextureSize, ns.baseTextureSize)
resourceRingFrame:SetFrameStrata("TOOLTIP")
resourceRingFrame:SetFrameLevel(ring:GetFrameLevel() + 1)
local resourceRingTrack = CreateSpinner(resourceRingFrame)
resourceRingTrack:SetClockwise(true)
resourceRingTrack:SetReverse(false)
resourceRingTrack:Hide()
local resourceRing = CreateSpinner(resourceRingFrame)
resourceRing:SetClockwise(true)
resourceRing:SetReverse(false)
resourceRing:Hide()
local resourceSegments = {}
local resourceRingCenterRadius = 0

local castRingFrame = CreateFrame("Frame", nil, ring)
castRingFrame:SetPoint("CENTER", ring, "CENTER")
castRingFrame:SetSize(ns.baseTextureSize, ns.baseTextureSize)
castRingFrame:SetFrameStrata("TOOLTIP")
castRingFrame:SetFrameLevel(ring:GetFrameLevel() + 2)
local castRing = CreateSpinner(castRingFrame)
castRing:SetClockwise(true)
castRing:SetReverse(false)
castRing:Hide()
local castStageMarkers = {}

-- State
local gcdRegionMasks = setmetatable({}, { __mode = "k" })
local gcdMaskTargets = {}
local gcdMaskDirty = true
local castActive = false
local castStart = 0
local castDuration = 0
local castReverse = false
local castHoldAtMax = false
local castSpellID = nil
local castStagePoints = {}
local gcdVisualActive = false
local resourceHasValue = false
local resourceNeedsContinuousUpdate = false
local resourceStartupRetryToken = 0
local activeResourceModule = nil
local activeResourceModuleClass = nil
local lastCursorX, lastCursorY = nil, nil
local lastOffsetX, lastOffsetY = nil, nil
local trailSystem = nil

local function clearArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function MarkGCDMaskDirty()
    gcdMaskDirty = true
end

local function SetGCDVisualActive(active, refreshAppearance)
    active = not not active
    if gcdVisualActive == active then
        return
    end
    gcdVisualActive = active
    if refreshAppearance and ns and type(ns.UpdateAppearance) == "function" then
        ns.UpdateAppearance()
    end
end

local Clamp01
local GetRingThickness
local GetCastRingThickness
local GetResourceRingThickness
local GetRingMargin
local GetMaskScaleForThickness
local GetRingBaseAlpha
local IsCastRingEnabled

local function ClearCastStagePoints()
    clearArray(castStagePoints)
end

local function HideCastStageMarkers()
    for i = 1, #castStageMarkers do
        castStageMarkers[i]:Hide()
    end
end

local function EnsureCastStageMarkers(count)
    if #castStageMarkers >= count then
        return
    end

    for i = #castStageMarkers + 1, count do
        local marker = castRingFrame:CreateTexture(nil, "OVERLAY")
        marker:SetTexture(WHITE8X8)
        applyTextureSampling(marker)
        marker:Hide()
        castStageMarkers[i] = marker
    end
end

local function ResetCastStageIndicators()
    ClearCastStagePoints()
    HideCastStageMarkers()
end

local function CaptureEmpowerStagePoints()
    ResetCastStageIndicators()
    if type(UnitEmpoweredStagePercentages) ~= "function" then
        return
    end

    local percentages = UnitEmpoweredStagePercentages("player", true)
    if type(percentages) ~= "table" or #percentages < 2 then
        return
    end

    local cumulative = 0
    for i = 1, (#percentages - 1) do
        cumulative = Clamp01(cumulative + Clamp01(tonumber(percentages[i]) or 0))
        if cumulative > 0 and cumulative < 1 then
            castStagePoints[#castStagePoints + 1] = cumulative
        end
    end
end

local function GetRingInnerRadiusForThickness(outerRadius, thickness, size)
    local effectiveOuter = tonumber(outerRadius) or 0
    if effectiveOuter <= 0 then
        return 0
    end

    local effectiveThickness = tonumber(thickness) or 50
    if effectiveThickness >= 100 then
        return 0
    end

    local holeFrac = (ns.maskHoleSizePx or 256) / (ns.maskArtSizePx or 1024)
    if holeFrac <= 0 then
        holeFrac = 0.25
    end

    local frameSize = tonumber(size) or (effectiveOuter * 2)
    local innerRadius = effectiveOuter * holeFrac * GetMaskScaleForThickness(effectiveThickness, frameSize)
    if innerRadius < 0 then
        return 0
    end
    if innerRadius > effectiveOuter then
        return effectiveOuter
    end
    return innerRadius
end

local function GetRingBandMetrics(frame, thickness)
    local size = (frame and frame.GetWidth and frame:GetWidth()) or ns.baseTextureSize or 512
    local outerRadius = size * 0.5
    local innerRadius = GetRingInnerRadiusForThickness(outerRadius, thickness or GetRingThickness(), size)
    local bandWidth = outerRadius - innerRadius
    return innerRadius + (bandWidth * 0.5), bandWidth, innerRadius, outerRadius
end

local function GetEmpowerTierColor(stageIndex, disabled)
    local paletteIndex = math.floor(tonumber(stageIndex) or 1)
    if paletteIndex < 1 then
        paletteIndex = 1
    elseif paletteIndex > #EMPOWER_TIER_COLORS then
        paletteIndex = #EMPOWER_TIER_COLORS
    end

    local color = EMPOWER_TIER_COLORS[paletteIndex]
    local r, g, b = color[1], color[2], color[3]
    if disabled then
        r = (r * 0.30) + 0.18
        g = (g * 0.30) + 0.18
        b = (b * 0.30) + 0.18
    end
    return Clamp01(r), Clamp01(g), Clamp01(b)
end

local function GetEmpowerStageState(progress)
    local clampedProgress = Clamp01(tonumber(progress) or 0)
    local stageCount = #castStagePoints
    if stageCount == 0 then
        return 1, false
    end

    local activeStage = stageCount
    for i = 1, stageCount do
        local point = castStagePoints[i]
        if point and clampedProgress < point then
            activeStage = i
            break
        end
    end

    local inHoldAtMax = castStagePoints[stageCount] and clampedProgress >= castStagePoints[stageCount] or false
    return activeStage, inHoldAtMax
end

local function UpdateCastStageMarkers(progress)
    if not castHoldAtMax or #castStagePoints == 0 or not IsCastRingEnabled() then
        HideCastStageMarkers()
        return
    end

    EnsureCastStageMarkers(#castStagePoints)

    local currentStage, inHoldAtMax = GetEmpowerStageState(progress)
    local centerRadius, bandWidth = GetRingBandMetrics(castRingFrame, GetCastRingThickness())
    local markerLength = math.max(8, bandWidth + 4)
    local markerWidth = math.max(2, math.floor((bandWidth * 0.14) + 0.5))
    local baseAlpha = Clamp01(GetRingBaseAlpha())
    local pendingAlpha = Clamp01(baseAlpha * 0.75 + 0.10)
    local reachedAlpha = Clamp01(baseAlpha + 0.35)

    for i = 1, #castStageMarkers do
        local marker = castStageMarkers[i]
        local point = castStagePoints[i]
        if point then
            local angle = -halfpi + (point * pi2)
            local x = cos(angle) * centerRadius
            local y = sin(angle) * centerRadius
            local reached = progress and progress >= point

            marker:ClearAllPoints()
            marker:SetPoint("CENTER", castRingFrame, "CENTER", x, y)
            marker:SetSize(markerWidth, markerLength)
            if marker.SetRotation then
                marker:SetRotation(angle + halfpi)
            end

            if reached then
                local stageR, stageG, stageB = GetEmpowerTierColor(i, false)
                marker:SetBlendMode("ADD")
                marker:SetVertexColor(
                    stageR + ((1 - stageR) * 0.24),
                    stageG + ((1 - stageG) * 0.24),
                    stageB + ((1 - stageB) * 0.24),
                    Clamp01(reachedAlpha + ((inHoldAtMax and i == #castStagePoints) and 0.10 or 0))
                )
            else
                local nextStage = i + 1
                if nextStage > #castStagePoints then
                    nextStage = #castStagePoints
                end
                local stageR, stageG, stageB = GetEmpowerTierColor(nextStage, true)
                marker:SetBlendMode("BLEND")
                if currentStage == nextStage then
                    marker:SetVertexColor(stageR, stageG, stageB, Clamp01(pendingAlpha + 0.08))
                else
                    marker:SetVertexColor(stageR, stageG, stageB, pendingAlpha)
                end
            end
            marker:Show()
        else
            marker:Hide()
        end
    end
end

local function DiscoverGCDSwipeRegions()
    clearArray(gcdMaskTargets)
    if not (gcd and gcd.GetRegions and gcd.GetChildren) then
        return
    end

    local stack = { gcd }
    local seen = {}
    while #stack > 0 do
        local frame = stack[#stack]
        stack[#stack] = nil

        if frame and not seen[frame] then
            seen[frame] = true

            local regions = { frame:GetRegions() }
            for i = 1, #regions do
                local region = regions[i]
                if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.AddMaskTexture then
                    applyTextureSampling(region)
                    gcdMaskTargets[#gcdMaskTargets + 1] = region
                end
            end

            local children = { frame:GetChildren() }
            for i = 1, #children do
                stack[#stack + 1] = children[i]
            end
        end
    end
end

local function HasCombatAlphaVariance()
    local db = CursorRingDB or ns.defaults
    if not db then
        return false, 1, 1
    end

    local inAlpha = db.inCombatAlpha or 0.70
    local outAlpha = db.outCombatAlpha or 0.30
    return inAlpha ~= outAlpha, inAlpha, outAlpha
end

GetRingBaseAlpha = function()
    local hasVariance, inAlpha, outAlpha = HasCombatAlphaVariance()
    if not hasVariance then
        return outAlpha
    end
    if InCombatLockdown() then
        return inAlpha
    end
    return outAlpha
end

Clamp01 = function(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

GetRingThickness = function()
    local db = CursorRingDB or ns.defaults
    local v = tonumber(db.ringThickness)
    if not v then return 50 end
    if v < 1 then return 1 end
    if v > 100 then return 100 end
    return v
end

GetCastRingThickness = function()
    local cdb = CursorRingCharDB or ns.charDefaults
    local v = tonumber(cdb.castRingThickness)
    if not v then return 25 end
    if v < 1 then return 1 end
    if v > 99 then return 99 end
    return v
end

GetResourceRingThickness = function()
    local cdb = CursorRingCharDB or ns.charDefaults
    local v = tonumber(cdb.resourceRingThickness)
    if not v then return 15 end
    if v < 1 then return 1 end
    if v > 99 then return 99 end
    return v
end

GetRingMargin = function()
    local db = CursorRingDB or ns.defaults
    local v = tonumber(db.ringMargin)
    if not v then return 2 end
    if v < 0 then return 0 end
    if v > 80 then return 80 end
    return v
end

local function GetGCDSwipeTexturePath()
    local thickness = GetRingThickness()
    if thickness >= 99 then
        return ns.texturePath
    end

    local bucket = math.floor((thickness - 1) / 5) + 1
    if bucket < 1 then
        bucket = 1
    elseif bucket > 20 then
        bucket = 20
    end

    return string.format("Interface\\AddOns\\CursorRing\\Media\\GCDSwipe\\GCDSwipeRing-%02d.tga", bucket)
end

local function ApplySpinnerThicknessMasks(spinner, thickness)
    if not (spinner and spinner._maskBindings) then return end
    local useMask = thickness < 100
    local simpleScale = GetMaskScaleForThickness(thickness, spinner:GetWidth())
    for i = 1, #spinner._maskBindings do
        local b = spinner._maskBindings[i]
        if useMask then
            b.mask:ClearAllPoints()
            b.mask:SetPoint("CENTER", spinner, "CENTER")
            b.mask:SetSize(spinner:GetWidth() * simpleScale, spinner:GetHeight() * simpleScale)
            if (not b.attached) and b.texture.AddMaskTexture then
                b.texture:AddMaskTexture(b.mask)
                b.attached = true
            end
        elseif b.attached and b.texture.RemoveMaskTexture then
            b.texture:RemoveMaskTexture(b.mask)
            b.attached = false
        end
    end
end

local function GetMaxMaskScaleForOnePixel(sizePx)
    -- holeFrac = holeDiameter / maskCanvasDiameter in source art.
    local holeFrac = (ns.maskHoleSizePx or 256) / (ns.maskArtSizePx or 1024)
    if holeFrac <= 0 then holeFrac = 0.25 end

    -- Scale where the hole fully reaches ring bounds.
    local hideScale = 1 / holeFrac

    -- Scale where ~1px ring remains visible.
    local thinScale = hideScale
    if sizePx and sizePx > 2 then
        thinScale = ((sizePx - 2) / sizePx) / holeFrac
    end

    if thinScale < 1 then thinScale = 1 end
    if thinScale > hideScale then thinScale = hideScale end
    return thinScale
end

GetMaskScaleForThickness = function(thickness, sizePx)
    -- 99% = authored mask size (scale 1.0, as-is asset look).
    -- 1%  = ~1px visible ring (size-aware).
    -- 1%  = thinnest visible masked ring.
    -- 100% = mask disabled (handled by detach).
    if thickness >= 99 then
        return 1
    end
    local maxScale = GetMaxMaskScaleForOnePixel(sizePx)
    if thickness <= 1 then
        return maxScale
    end
    local t = (99 - thickness) / 98
    local eased = t
    return 1 + (maxScale - 1) * eased
end

local ApplyResourceSegmentMasks

local function ApplyRingThicknessMasks()
    local mainThickness = GetRingThickness()
    local castThickness = GetCastRingThickness()
    local resourceThickness = GetResourceRingThickness()
    local useMask = mainThickness < 100
    local scale = GetMaskScaleForThickness(mainThickness, tex:GetWidth())

    if ringMask then
        if useMask then
            ringMask:ClearAllPoints()
            ringMask:SetPoint("CENTER", tex, "CENTER")
            ringMask:SetSize(tex:GetWidth() * scale, tex:GetHeight() * scale)
            if not ringMaskAttached and tex.AddMaskTexture then
                tex:AddMaskTexture(ringMask)
                ringMaskAttached = true
            end
        elseif ringMaskAttached and tex.RemoveMaskTexture then
            tex:RemoveMaskTexture(ringMask)
            ringMaskAttached = false
        end
    end

    ApplySpinnerThicknessMasks(resourceRingTrack, resourceThickness)
    ApplySpinnerThicknessMasks(resourceRing, resourceThickness)
    ApplySpinnerThicknessMasks(castRing, castThickness)
    ApplyResourceSegmentMasks()
end

-- Color aliases for slash convenience
ns.colorAlias = {
    red         = "deathknight",
    magenta     = "demonhunter",
    orange      = "druid",
    darkgreen   = "evoker",
    green       = "hunter",
    lightgreen  = "monk",
    blue        = "shaman",
    lightblue   = "mage",
    pink        = "paladin",
    white       = "priest",
    yellow      = "rogue",
    purple      = "warlock",
    tan         = "warrior",
}

-- This is used for the GCD swipe color (overlay) and for solid ring mode.
-- It does NOT color the ring when colorMode == "gradient"; the ring is handled in UpdateAppearance.
local function GetColor()
    local db = CursorRingDB
    if not db then
        return 1, 1, 1
    end

    local mode = db.colorMode or "class"

    -- Gradient mode: solid color for the swipe is the average of the two gradient colors.
    if mode == "gradient" then
        local c1 = db.gradientColor1 or {}
        local c2 = db.gradientColor2 or {}

        local r1 = c1.r or 1
        local g1 = c1.g or 1
        local b1 = c1.b or 1

        local r2 = c2.r or r1
        local g2 = c2.g or g1
        local b2 = c2.b or b1

        return (r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2
    end

    if mode == "highvis" then
        return 0, 1, 0
    end

    if mode == "custom" then
        local c = db.customColor or { r = 1, g = 1, b = 1 }
        return c.r or 1, c.g or 1, c.b or 1
    end

    -- "class" mode: player class color
    if mode == "class" then
        local _, classFile = UnitClass("player")
        local r, g, b = GetClassColorRGB(classFile)
        if r then
            return r, g, b
        end
        return 1, 1, 1
    end

    -- Specific class token
    local classFile = ns.colorAlias[mode] or mode
    local r2, g2, b2 = GetClassColorRGB(classFile)
    if r2 then
        return r2, g2, b2
    end

    return 1, 1, 1
end

local function EnsureTrailSystem()
    local cdb = CursorRingCharDB or ns.charDefaults or {}
    if cdb.trailEnabled ~= true then
        return nil
    end
    if trailSystem then
        return trailSystem
    end
    if type(ns.CreateTrailSystem) ~= "function" then
        return nil
    end

    trailSystem = ns.CreateTrailSystem(ring, {
        get_color = function()
            return GetColor()
        end,
        get_alpha = function()
            return GetRingBaseAlpha()
        end,
    })
    return trailSystem
end

local function RefreshTrailSystem(force_reset)
    local trail = EnsureTrailSystem()
    if trail and type(trail.RefreshConfig) == "function" then
        trail:RefreshConfig(force_reset)
        return trail
    end
    if trailSystem and type(trailSystem.ResetTrail) == "function" then
        trailSystem:ResetTrail()
    end
    return nil
end

-----------------------------------------------------------------------
-- Right-click hide: hide/show the entire ring frame
-----------------------------------------------------------------------
WorldFrame:HookScript("OnMouseDown", function(_, button)
    if button == "RightButton" and CursorRingDB and CursorRingDB.hideOnRightClick then
        ring:Hide()
        local trail = trailSystem
        if trail and type(trail.ResetTrail) == "function" then
            trail:ResetTrail()
        end
    end
end)

WorldFrame:HookScript("OnMouseUp", function(_, button)
    if button == "RightButton" and CursorRingDB and CursorRingDB.hideOnRightClick then
        ring:Show()
    end
end)

-----------------------------------------------------------------------
-- GCD swipe alpha helper (separate from ring emphasis)
-----------------------------------------------------------------------
local function GetSwipeAlpha()
    -- Swipe follows the base in/out-of-combat alpha, but is clamped to 0..1
    if GetRingThickness() <= 0 then
        return 0
    end
    return Clamp01(GetRingBaseAlpha())
end

local function GetGCDStyle()
    if CursorRingCharDB and CursorRingCharDB.gcdStyle then
        return CursorRingCharDB.gcdStyle
    end
    return "simple"
end

IsCastRingEnabled = function()
    return CursorRingCharDB and CursorRingCharDB.castRingEnabled
end

local function IsResourceRingEnabled()
    return CursorRingCharDB and CursorRingCharDB.resourceRingEnabled
end

local function SolveOuterRingRadius(minInnerEdge, thickness, startOuterRadius)
    local outer = tonumber(startOuterRadius) or (tonumber(minInnerEdge) or 0) + 1
    local targetInner = tonumber(minInnerEdge) or 0
    if outer <= 0 then
        outer = targetInner + 1
    end

    for _ = 1, 96 do
        local inner = GetRingInnerRadiusForThickness(outer, thickness, outer * 2)
        if inner >= targetInner then
            return outer
        end

        local deficit = targetInner - inner
        if deficit < 0.25 then
            deficit = 0.25
        end
        outer = outer + deficit + 0.5
    end

    return outer
end

local function UpdateRingLayout()
    local mainOuterRadius = (CursorRingDB and CursorRingDB.ringRadius) or (ns.defaults and ns.defaults.ringRadius) or 35
    local ringMargin = GetRingMargin()
    if ringMargin < 0 then
        ringMargin = 0
    end

    local castOuterRadius = mainOuterRadius
    local resourceOuterRadius = mainOuterRadius
    local nextMinInnerEdge = mainOuterRadius + ringMargin

    if IsCastRingEnabled() then
        castOuterRadius = SolveOuterRingRadius(nextMinInnerEdge, GetCastRingThickness(), mainOuterRadius + ringMargin + 1)
        nextMinInnerEdge = castOuterRadius + ringMargin
    end

    if IsResourceRingEnabled() then
        local previousOuter = IsCastRingEnabled() and castOuterRadius or mainOuterRadius
        resourceOuterRadius = SolveOuterRingRadius(nextMinInnerEdge, GetResourceRingThickness(), previousOuter + ringMargin + 1)
    else
        resourceOuterRadius = IsCastRingEnabled() and castOuterRadius or mainOuterRadius
    end

    castRingFrame:SetSize(castOuterRadius * 2, castOuterRadius * 2)
    resourceRingFrame:SetSize(resourceOuterRadius * 2, resourceOuterRadius * 2)

    local resourceInnerRadius = GetRingInnerRadiusForThickness(resourceOuterRadius, GetResourceRingThickness(), resourceOuterRadius * 2)
    resourceRingCenterRadius = resourceInnerRadius + ((resourceOuterRadius - resourceInnerRadius) * 0.5)
end

local function GetCastColor()
    local c = CursorRingCharDB and CursorRingCharDB.castRingColor
    if not c then return 0.2, 0.8, 1.0 end
    return c.r or 0.2, c.g or 0.8, c.b or 1.0
end

local function GetResourceColor(token, powerType)
    if PowerBarColor then
        local c = token and PowerBarColor[token] or nil
        if not c and powerType ~= nil then
            c = PowerBarColor[powerType]
        end
        if c and c.r and c.g and c.b then
            return c.r, c.g, c.b
        end
    end
    return 1, 1, 1
end

local function GetResourceSegmentTexturePath(count)
    local normalizedCount = math.floor(tonumber(count) or 1)
    if normalizedCount < 1 then
        normalizedCount = 1
    elseif normalizedCount > 8 then
        normalizedCount = 8
    end
    return "Interface\\AddOns\\CursorRing\\Media\\Segments\\ResourceSegmentArc-" .. normalizedCount .. ".tga"
end

local function EnsureResourceSegments(count)
    if #resourceSegments >= count then return end
    for i = #resourceSegments + 1, count do
        local seg = resourceRingFrame:CreateTexture(nil, "ARTWORK")
        seg._segmentTexturePath = nil
        seg._maskAttached = false
        if resourceRingFrame.CreateMaskTexture and seg.AddMaskTexture then
            local mask = resourceRingFrame:CreateMaskTexture(nil, "ARTWORK")
            setMaskTextureSmooth(mask, ns.inverseMaskPath)
            seg._mask = mask
        end
        seg:Hide()
        resourceSegments[i] = seg
    end
end

ApplyResourceSegmentMasks = function()
    local thickness = GetResourceRingThickness()
    local useMask = thickness < 100
    local scale = GetMaskScaleForThickness(thickness, resourceRingFrame:GetWidth())

    for i = 1, #resourceSegments do
        local seg = resourceSegments[i]
        local mask = seg and seg._mask or nil
        if mask then
            if useMask then
                mask:ClearAllPoints()
                mask:SetPoint("CENTER", resourceRingFrame, "CENTER")
                mask:SetSize(resourceRingFrame:GetWidth() * scale, resourceRingFrame:GetHeight() * scale)
                if (not seg._maskAttached) and seg.AddMaskTexture then
                    seg:AddMaskTexture(mask)
                    seg._maskAttached = true
                end
            elseif seg._maskAttached and seg.RemoveMaskTexture then
                seg:RemoveMaskTexture(mask)
                seg._maskAttached = false
            end
        end
    end
end

local function HideResourceSegments()
    for i = 1, #resourceSegments do
        resourceSegments[i]:Hide()
    end
end

local function LayoutResourceSegments(count)
    local segCount = count or 6
    local templateAngle = -halfpi
    local texturePath = GetResourceSegmentTexturePath(segCount)
    for i = 1, #resourceSegments do
        local seg = resourceSegments[i]
        if i <= segCount then
            local angle = -halfpi + (((i - 1) / segCount) * pi2)
            seg:ClearAllPoints()
            seg:SetAllPoints(resourceRingFrame)
            if seg._segmentTexturePath ~= texturePath then
                setTextureSmooth(seg, texturePath)
                seg._segmentTexturePath = texturePath
            end
            if seg.SetRotation then
                seg:SetRotation(angle - templateAngle)
            end
        else
            seg:Hide()
        end
    end
end

local function SelectResourceModule()
    local _, classFile = UnitClass("player")
    if activeResourceModuleClass ~= classFile then
        activeResourceModuleClass = classFile
        activeResourceModule = ns.GetResourceModule and ns.GetResourceModule(classFile) or nil
    end
    return activeResourceModule
end

local function ResetResourceRingDisplay()
    HideResourceSegments()
    resourceRingTrack:Hide()
    resourceRing:Hide()
    resourceHasValue = false
    resourceNeedsContinuousUpdate = false
end

local function CancelResourceRingStartupRetry()
    resourceStartupRetryToken = resourceStartupRetryToken + 1
end

local function UpdateSegmentedResourceDisplay(states, count, token, powerType, color, options)
    local r, g, b
    if color then
        r, g, b = color[1], color[2], color[3]
    else
        r, g, b = GetResourceColor(token, powerType)
    end
    local allow_full_charge_highlight = not (options and options.suppressFullChargeHighlight)
    local recharge_visual = options and options.rechargeVisual or nil
    local activeAlpha = Clamp01(GetRingBaseAlpha())
    local inactiveAlpha = Clamp01(activeAlpha * 0.45)
    local inactiveR, inactiveG, inactiveB = 0.35, 0.35, 0.35
    local isFullyCharged = true

    EnsureResourceSegments(count)
    ApplyResourceSegmentMasks()
    LayoutResourceSegments(count)

    for i = 1, count do
        local progress = states[i]
        if type(progress) == "boolean" then
            progress = progress and 1 or 0
        else
            progress = Clamp01(tonumber(progress) or 0)
        end

        if progress < 0.999 then
            isFullyCharged = false
            break
        end
    end

    for i = 1, #resourceSegments do
        local seg = resourceSegments[i]
        if i <= count then
            local progress = states[i]
            if type(progress) == "boolean" then
                progress = progress and 1 or 0
            else
                progress = Clamp01(tonumber(progress) or 0)
            end

            local segR, segG, segB, segA
            if recharge_visual == "alpha_pop" and progress < 0.999 then
                segR, segG, segB = r, g, b
                segA = Clamp01(activeAlpha * 0.5 * progress)
            else
                segR = inactiveR + ((r - inactiveR) * progress)
                segG = inactiveG + ((g - inactiveG) * progress)
                segB = inactiveB + ((b - inactiveB) * progress)
                segA = inactiveAlpha + ((activeAlpha - inactiveAlpha) * progress)
            end

            if allow_full_charge_highlight and isFullyCharged and progress > 0 then
                segR = segR + ((1 - segR) * 0.18)
                segG = segG + ((1 - segG) * 0.18)
                segB = segB + ((1 - segB) * 0.18)
                segA = Clamp01(segA + 0.12)
                seg:SetBlendMode("ADD")
            else
                seg:SetBlendMode("BLEND")
            end
            seg:SetVertexColor(segR, segG, segB, segA)
            seg:Show()
        else
            seg:SetBlendMode("BLEND")
            seg:Hide()
        end
    end

    resourceRingTrack:Hide()
    resourceRing:Hide()
end

local function UpdateResourceRing()
    if not IsResourceRingEnabled() then
        CancelResourceRingStartupRetry()
        ResetResourceRingDisplay()
        return false
    end

    local module = SelectResourceModule()
    if not (module and module.BuildState) then
        ResetResourceRingDisplay()
        return false
    end

    local state = module:BuildState()
    if not state then
        ResetResourceRingDisplay()
        return false
    end

    if state.kind == "segments" and state.count and state.count > 0 then
        CancelResourceRingStartupRetry()
        UpdateSegmentedResourceDisplay(state.values or {}, state.count, state.token, state.powerType, state.color, state.options)
        resourceHasValue = not not state.hasValue
        resourceNeedsContinuousUpdate = not not state.needsContinuousUpdate
        return true
    end

    ResetResourceRingDisplay()
    return false
end

local function ScheduleResourceRingStartupRetry()
    if not (IsResourceRingEnabled() and C_Timer and C_Timer.After) then
        return
    end

    resourceStartupRetryToken = resourceStartupRetryToken + 1
    local token = resourceStartupRetryToken
    local attempts_remaining = 20

    local function Retry()
        if token ~= resourceStartupRetryToken or not IsResourceRingEnabled() then
            return
        end

        if UpdateResourceRing() then
            return
        end

        attempts_remaining = attempts_remaining - 1
        if attempts_remaining > 0 then
            C_Timer.After(0.25, Retry)
        end
    end

    C_Timer.After(0.25, Retry)
end

local function UpdateCastRingFromUnit()
    if not IsCastRingEnabled() then
        castRing:Hide()
        castActive = false
        castReverse = false
        castHoldAtMax = false
        castSpellID = nil
        ResetCastStageIndicators()
        return
    end
    local _, _, _, startMS, endMS, _, _, _, spellID = UnitCastingInfo("player")
    if startMS and endMS and endMS > startMS then
        castStart = startMS / 1000
        castDuration = (endMS - startMS) / 1000
        castReverse = false
        castHoldAtMax = false
        castSpellID = spellID
        castActive = true
        ResetCastStageIndicators()
        return
    end
    local _, _, _, startMS2, endMS2, _, _, _, spellID2, _, numStages = UnitChannelInfo("player")
    if startMS2 and endMS2 and endMS2 > startMS2 then
        castStart = startMS2 / 1000
        castDuration = (endMS2 - startMS2) / 1000
        castReverse = not (numStages and numStages > 0)
        castHoldAtMax = numStages and numStages > 0 or false
        castSpellID = spellID2
        castActive = true
        if castHoldAtMax then
            CaptureEmpowerStagePoints()
        else
            ResetCastStageIndicators()
        end
        return
    end
    castActive = false
    castReverse = false
    castHoldAtMax = false
    castSpellID = nil
    ResetCastStageIndicators()
    castRing:Hide()
end

local function UpdateCastRingVisual(now)
    if not castActive or not IsCastRingEnabled() or castDuration <= 0 then
        castRing:Hide()
        HideCastStageMarkers()
        return
    end
    local elapsed = (now or GetTime()) - castStart
    local progress = Clamp01(elapsed / castDuration)
    if progress >= 1 then
        if not castHoldAtMax then
            castActive = false
            castRing:Hide()
            HideCastStageMarkers()
            return
        end
        progress = 1
    end

    local r, g, b
    local ringAlpha = GetRingBaseAlpha()
    local blendMode = "BLEND"
    if castHoldAtMax and #castStagePoints > 0 then
        local activeStage, inHoldAtMax = GetEmpowerStageState(progress)
        r, g, b = GetEmpowerTierColor(activeStage, false)
        if inHoldAtMax then
            r = r + ((1 - r) * 0.18)
            g = g + ((1 - g) * 0.18)
            b = b + ((1 - b) * 0.18)
            ringAlpha = Clamp01(ringAlpha + 0.14)
            blendMode = "ADD"
        end
    else
        r, g, b = GetCastColor()
    end

    setTextureSmooth(castRing, ns.texturePath)
    castRing:SetVertexColor(r, g, b)
    castRing:SetBlendMode(blendMode)
    castRing:SetReverse(castReverse)
    castRing:SetAlpha(ringAlpha)
    castRing:SetValue(progress)
    UpdateCastStageMarkers(progress)
    castRing:Show()
end

local function ApplyGCDSwipeMask()
    if not (gcd and gcd.GetRegions and gcd.CreateMaskTexture and gcd.GetChildren) then
        return
    end

    local thickness = GetRingThickness()
    local useMask = thickness < 100
    if gcdMaskDirty or #gcdMaskTargets == 0 then
        DiscoverGCDSwipeRegions()
        gcdMaskDirty = false
    end

    for i = 1, #gcdMaskTargets do
        local region = gcdMaskTargets[i]
        local mask = gcdRegionMasks[region]
        if useMask then
            local scale = GetMaskScaleForThickness(thickness, gcd:GetWidth())
            if not mask then
                mask = gcd:CreateMaskTexture(nil, "ARTWORK")
                setMaskTextureSmooth(mask, ns.inverseMaskPath)
                gcdRegionMasks[region] = mask
                region:AddMaskTexture(mask)
            end
            mask:ClearAllPoints()
            mask:SetPoint("CENTER", gcd, "CENTER")
            mask:SetSize(gcd:GetWidth() * scale, gcd:GetHeight() * scale)
        elseif mask and region.RemoveMaskTexture then
            region:RemoveMaskTexture(mask)
            gcdRegionMasks[region] = nil
        end
    end
end

local function HideLegacyGCDSpinner()
    gcdSimple:Hide()
    gcdSimple:SetValue(0)
end

gcd:HookScript("OnHide", function()
    SetGCDVisualActive(false, true)
end)

-----------------------------------------------------------------------
-- GCD style / swipe
-- Native Cooldown timing only. "simple" and "blizzard" differ only by edge styling.
-----------------------------------------------------------------------
local function UpdateGCDStyle()
    if not (CursorRingCharDB and CursorRingCharDB.gcdEnabled) then
        gcd:Hide()
        HideLegacyGCDSpinner()
        return
    end

    local r, g, b = GetColor()
    local style = GetGCDStyle()
    local swipeA = GetSwipeAlpha()
    local reverse = CursorRingCharDB and CursorRingCharDB.gcdReverse

    HideLegacyGCDSpinner()
    if gcd.SetSwipeTexture then
        gcd:SetSwipeTexture(GetGCDSwipeTexturePath())
    end
    if gcd.SetDrawSwipe then gcd:SetDrawSwipe(true) end
    if gcd.SetDrawEdge then gcd:SetDrawEdge(style ~= "simple") end
    if gcd.SetDrawBling then gcd:SetDrawBling(false) end
    if gcd.SetSwipeColor then gcd:SetSwipeColor(r, g, b, swipeA) end
    if gcd.SetReverse then
        gcd:SetReverse(not not reverse)
    end
end

-----------------------------------------------------------------------
-- Ring appearance (color + alpha) – single source of truth
-----------------------------------------------------------------------
local function UpdateAppearance()
    local db = CursorRingDB or ns.defaults
    local radius  = db.ringRadius or 28
    local mode    = db.colorMode or "class"
    local thickness = GetRingThickness()

    setTextureSmooth(tex, ns.texturePath)

    -- Base alpha from in-combat / out-of-combat
    local baseAlpha = GetRingBaseAlpha()

    -- Decide ring alpha:
    --   - If no GCD swipe is actually visible/active, use baseAlpha.
    --   - If GCD swipe is visible and enabled, fade between baseAlpha and 0
    --     based on gcdDimMultiplier:
    --         E = 0 -> ringAlpha = baseAlpha
    --         E = 1 -> ringAlpha = 0
    local ringAlpha
    if gcdVisualActive and CursorRingCharDB and CursorRingCharDB.gcdEnabled then
        local e = CursorRingCharDB.gcdDimMultiplier or 0
        e = Clamp01(e)
        ringAlpha = baseAlpha * (1 - e)
    else
        ringAlpha = baseAlpha
    end
    local gradientAlpha = Clamp01(ringAlpha)

    -- Reset rotation & clear any previous gradient
    if tex.SetRotation then
        tex:SetRotation(0)
    end
    if tex.SetGradient then
        if CreateColor then
            tex:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
        else
            tex:SetGradient("HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 1)
        end
    end

    if mode == "gradient" and tex.SetGradient then
        -- Gradient ring path: this is the ONLY place that colors the ring when in gradient mode.
        local c1 = db.gradientColor1 or {}
        local c2 = db.gradientColor2 or {}

        local r1 = c1.r or 1
        local g1 = c1.g or 1
        local b1 = c1.b or 1

        local r2 = c2.r or r1
        local g2 = c2.g or g1
        local b2 = c2.b or b1

        tex:SetVertexColor(1, 1, 1) -- neutral base

        -- RGB gradient only; alpha is applied to the gradient stops so slider/combat updates still affect the ring.
        if CreateColor then
            tex:SetGradient("HORIZONTAL",
                CreateColor(r1, g1, b1, gradientAlpha),
                CreateColor(r2, g2, b2, gradientAlpha)
            )
        else
            tex:SetGradient("HORIZONTAL",
                r1, g1, b1, gradientAlpha,
                r2, g2, b2, gradientAlpha
            )
        end

        local angle = db.gradientAngle or 0
        angle = angle % 360
        if tex.SetRotation then
            tex:SetRotation(angle * math.pi / 180)
        end

        tex:SetAlpha(1)
    else
        -- Solid color path (class/highvis/custom/forced class)
        local cr, cg, cb = GetColor()
        tex:SetVertexColor(cr, cg, cb)
        tex:SetAlpha(ringAlpha)
    end

    ring:SetSize(radius * 2, radius * 2)
    gcd:SetScale((radius * 2) / ns.baseTextureSize)
    UpdateRingLayout()
    ApplyRingThicknessMasks()
    UpdateResourceRing()
    UpdateCastRingVisual(GetTime())
    UpdateGCDStyle()
    RefreshTrailSystem(false)
end
ns.UpdateAppearance = UpdateAppearance

-----------------------------------------------------------------------
-- Cooldown handling (no secret fields)
-----------------------------------------------------------------------
local function ReadSpellCooldownInfo(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local a, b, c, d = C_Spell.GetSpellCooldown(spellID)
        if type(a) == "table" then
            return a
        else
            -- 11.x tuple: start, duration, enable, modRate
            local start2, duration2, enable2, modRate2 = a, b, c, d
            return {
                startTime = start2,
                duration = duration2,
                isEnabled = (enable2 == nil) or (enable2 ~= 0),
                modRate = modRate2,
            }
        end
    end
    if GetSpellCooldown then
        local s, d, e, m = GetSpellCooldown(spellID)
        return {
            startTime = s,
            duration = d,
            isEnabled = (e == nil) or (e ~= 0),
            modRate = m,
        }
    end
    return nil
end

local function ReadSpellCooldownDurationObject(spellID)
    if not (C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function") then
        return nil
    end

    local ok, durationObject = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    if ok then
        return durationObject
    end
    return nil
end

local GCD_SPELL_ID = 61304

-- SAFE against 12.0 "secret" cooldown values.
local function IsCooldownActive(start, duration)
    -- If either value is nil, there's clearly no cooldown.
    if not start or not duration then return false end

    -- We cannot safely do *any* arithmetic or comparisons on secret cooldown values,
    -- because the client throws if you touch them. So we wrap the checks in pcall:
    --   - If the comparison works, we use the result.
    --   - If it errors (secret values), we treat that as "cooldown is active".
    local ok, result = pcall(function()
        -- Normal numeric path (works for pre-12.0 and non-secret values):
        -- idle GCD:  start == 0, duration == 0  -> inactive
        -- active GCD: duration > 0              -> active
        if duration == 0 or start == 0 then
            return false
        else
            return true
        end
    end)

    if not ok then
        -- Comparison exploded, so we hit a secret value.
        -- That only happens when a cooldown is actually running, so treat it as active.
        return true
    end

    return result and true or false
end

local function IsCooldownInfoActive(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return false
    end

    if type(cooldownInfo.isActive) == "boolean" then
        return cooldownInfo.isActive
    end

    return IsCooldownActive(cooldownInfo.startTime or cooldownInfo.start, cooldownInfo.duration)
end

local function ApplyCooldownFrameFromSpell(frame, spellID, cooldownInfo)
    if not frame then
        return false
    end

    if type(frame.SetCooldownFromDurationObject) == "function" and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function" then
        local durationObject = ReadSpellCooldownDurationObject(spellID)
        if durationObject then
            local ok = pcall(frame.SetCooldownFromDurationObject, frame, durationObject, true)
            if ok then
                return true
            end

            PrintDebug("SetCooldownFromDurationObject failed for spellID " .. tostring(spellID))
            return false
        end

        PrintDebug("Cooldown duration object unavailable for spellID " .. tostring(spellID))
        return false
    end

    local start = cooldownInfo and (cooldownInfo.startTime or cooldownInfo.start)
    local duration = cooldownInfo and cooldownInfo.duration
    local modRate = cooldownInfo and cooldownInfo.modRate
    if not IsCooldownActive(start, duration) then
        return false
    end

    if modRate then
        local ok = pcall(frame.SetCooldown, frame, start, duration, modRate)
        if ok then
            return true
        end
    end

    local ok = pcall(frame.SetCooldown, frame, start, duration)
    return ok and true or false
end

local function UpdateGCDCooldown()
    if not (CursorRingCharDB and CursorRingCharDB.gcdEnabled) then
        SetGCDVisualActive(false)
        gcd:Hide()
        HideLegacyGCDSpinner()
        ns.UpdateAppearance()
        return
    end

    local cooldownInfo = ReadSpellCooldownInfo(GCD_SPELL_ID)
    if IsCooldownInfoActive(cooldownInfo) then
        gcd:Show()
        MarkGCDMaskDirty()
        if ApplyCooldownFrameFromSpell(gcd, GCD_SPELL_ID, cooldownInfo) then
            SetGCDVisualActive(true)
        else
            SetGCDVisualActive(false)
            gcd:Hide()
        end
        HideLegacyGCDSpinner()
        ns.UpdateAppearance()
    else
        SetGCDVisualActive(false)
        gcd:Hide()
        HideLegacyGCDSpinner()
        ns.UpdateAppearance()
    end
end

-----------------------------------------------------------------------
-- Debug helpers
-----------------------------------------------------------------------
local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00CursorRing:|r " .. tostring(msg))
end

local function PrintDebug(msg)
    if ns.DEBUG_GCD then
        Say(msg)
    end
end

local function DumpGCDState(header)
    if not ns.DEBUG_GCD then return end
    PrintDebug("=== " .. tostring(header) .. " ===")
    local cooldownInfo = ReadSpellCooldownInfo(GCD_SPELL_ID) or {}
    PrintDebug("Cooldown info -> start=" .. tostring(type(cooldownInfo.startTime)) .. ", duration=" .. tostring(type(cooldownInfo.duration)) .. ", modRate=" .. tostring(type(cooldownInfo.modRate)) .. ", isActive=" .. tostring(cooldownInfo.isActive))
end

-----------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------
local function SafeRegisterEvent(frame, event, unit)
    if not frame or type(event) ~= "string" or event == "" then
        return false
    end
    if unit and frame.RegisterUnitEvent then
        local ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
        if ok then
            return true
        end
    end
    if frame.RegisterEvent then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if ok then
            return true
        end
    end
    return false
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
f:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
SafeRegisterEvent(f, "UNIT_POWER_POINT_CHARGE", "player")
f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
f:RegisterEvent("RUNE_POWER_UPDATE")
f:RegisterEvent("RUNE_TYPE_UPDATE")
f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
SafeRegisterEvent(f, "UNIT_SPELLCAST_EMPOWER_START", "player")
SafeRegisterEvent(f, "UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
SafeRegisterEvent(f, "UNIT_SPELLCAST_EMPOWER_STOP", "player")

f:SetScript("OnEvent", function(self, event, unit, arg3, spellID)
    if event == "PLAYER_LOGIN" then
        CursorRingDB     = CursorRingDB     or CopyTable(ns.defaults)
        CursorRingCharDB = CursorRingCharDB or CopyTable(ns.charDefaults)

        if CursorRingCharDB.castRingEnabled == nil then
            CursorRingCharDB.castRingEnabled = false
        end
        if CursorRingCharDB.castRingThickness == nil then
            CursorRingCharDB.castRingThickness = 25
        elseif CursorRingCharDB.castRingThickness < 1 then
            CursorRingCharDB.castRingThickness = 1
        elseif CursorRingCharDB.castRingThickness > 99 then
            CursorRingCharDB.castRingThickness = 99
        end
        if not CursorRingCharDB.castRingColor then
            CursorRingCharDB.castRingColor = { r = 0.20, g = 0.80, b = 1.00 }
        end
        if CursorRingCharDB.resourceRingEnabled == nil then
            CursorRingCharDB.resourceRingEnabled = false
        end
        if CursorRingCharDB.resourceRingThickness == nil then
            CursorRingCharDB.resourceRingThickness = 15
        elseif CursorRingCharDB.resourceRingThickness < 1 then
            CursorRingCharDB.resourceRingThickness = 1
        elseif CursorRingCharDB.resourceRingThickness > 99 then
            CursorRingCharDB.resourceRingThickness = 99
        end
        if CursorRingCharDB.trailEnabled == nil then
            CursorRingCharDB.trailEnabled = false
        end
        if CursorRingCharDB.trailStyle == nil then
            CursorRingCharDB.trailStyle = "sprites"
        end
        local legacy_trail_style = CursorRingCharDB.trailStyle or "sprites"
        if type(ns.NormalizeTrailAssetKey) == "function" then
            CursorRingCharDB.trailAsset = ns.NormalizeTrailAssetKey(CursorRingCharDB.trailAsset)
        elseif type(CursorRingCharDB.trailAsset) ~= "string" or CursorRingCharDB.trailAsset == "" then
            CursorRingCharDB.trailAsset = "metalglow"
        end
        if CursorRingCharDB.trailColorMode == nil then
            CursorRingCharDB.trailColorMode = "ring"
        end
        local legacy_trail_color_mode = CursorRingCharDB.trailColorMode or "ring"
        if CursorRingCharDB.trailBlendMode == nil then
            CursorRingCharDB.trailBlendMode = "ADD"
        end
        if not CursorRingCharDB.trailCustomColor then
            CursorRingCharDB.trailCustomColor = { r = 1.00, g = 1.00, b = 1.00 }
        end
        local legacy_trail_custom = CursorRingCharDB.trailCustomColor
        if CursorRingCharDB.trailGlowEnabled == nil then
            CursorRingCharDB.trailGlowEnabled = (legacy_trail_style == "sprites" or legacy_trail_style == "hybrid")
        end
        if CursorRingCharDB.trailRibbonEnabled == nil then
            CursorRingCharDB.trailRibbonEnabled = (legacy_trail_style == "ribbon" or legacy_trail_style == "hybrid")
        end
        if CursorRingCharDB.trailParticleEnabled == nil then
            CursorRingCharDB.trailParticleEnabled = (legacy_trail_style == "particles")
        end
        if CursorRingCharDB.trailGlowColorMode == nil then
            CursorRingCharDB.trailGlowColorMode = legacy_trail_color_mode
        end
        if CursorRingCharDB.trailRibbonColorMode == nil then
            CursorRingCharDB.trailRibbonColorMode = legacy_trail_color_mode
        end
        if CursorRingCharDB.trailParticleColorMode == nil then
            CursorRingCharDB.trailParticleColorMode = legacy_trail_color_mode
        end
        if not CursorRingCharDB.trailGlowCustomColor then
            CursorRingCharDB.trailGlowCustomColor = { r = legacy_trail_custom.r or 1.00, g = legacy_trail_custom.g or 1.00, b = legacy_trail_custom.b or 1.00 }
        end
        if not CursorRingCharDB.trailRibbonCustomColor then
            CursorRingCharDB.trailRibbonCustomColor = { r = legacy_trail_custom.r or 1.00, g = legacy_trail_custom.g or 1.00, b = legacy_trail_custom.b or 1.00 }
        end
        if not CursorRingCharDB.trailParticleCustomColor then
            CursorRingCharDB.trailParticleCustomColor = { r = legacy_trail_custom.r or 1.00, g = legacy_trail_custom.g or 1.00, b = legacy_trail_custom.b or 1.00 }
        end
        if CursorRingCharDB.trailAlpha == nil then
            CursorRingCharDB.trailAlpha = 60
        elseif CursorRingCharDB.trailAlpha < 0 then
            CursorRingCharDB.trailAlpha = 0
        elseif CursorRingCharDB.trailAlpha > 100 then
            CursorRingCharDB.trailAlpha = 100
        end
        if CursorRingCharDB.trailSize == nil then
            CursorRingCharDB.trailSize = 24
        elseif CursorRingCharDB.trailSize < 4 then
            CursorRingCharDB.trailSize = 4
        elseif CursorRingCharDB.trailSize > 96 then
            CursorRingCharDB.trailSize = 96
        end
        if CursorRingCharDB.trailLength == nil then
            CursorRingCharDB.trailLength = 320
        elseif CursorRingCharDB.trailLength < 60 then
            CursorRingCharDB.trailLength = 60
        elseif CursorRingCharDB.trailLength > 1400 then
            CursorRingCharDB.trailLength = 1400
        end
        if CursorRingCharDB.trailSegments == nil then
            CursorRingCharDB.trailSegments = 8
        elseif CursorRingCharDB.trailSegments < 2 then
            CursorRingCharDB.trailSegments = 2
        elseif CursorRingCharDB.trailSegments > 24 then
            CursorRingCharDB.trailSegments = 24
        end
        if CursorRingCharDB.trailSampleRate == nil then
            CursorRingCharDB.trailSampleRate = 36
        elseif CursorRingCharDB.trailSampleRate < 10 then
            CursorRingCharDB.trailSampleRate = 10
        elseif CursorRingCharDB.trailSampleRate > 90 then
            CursorRingCharDB.trailSampleRate = 90
        end
        if CursorRingCharDB.trailMinDistance == nil then
            CursorRingCharDB.trailMinDistance = 6
        elseif CursorRingCharDB.trailMinDistance < 0 then
            CursorRingCharDB.trailMinDistance = 0
        elseif CursorRingCharDB.trailMinDistance > 40 then
            CursorRingCharDB.trailMinDistance = 40
        end
        if CursorRingCharDB.trailRibbonWidth == nil then
            CursorRingCharDB.trailRibbonWidth = 18
        elseif CursorRingCharDB.trailRibbonWidth < 2 then
            CursorRingCharDB.trailRibbonWidth = 2
        elseif CursorRingCharDB.trailRibbonWidth > 72 then
            CursorRingCharDB.trailRibbonWidth = 72
        end
        if CursorRingCharDB.trailHeadScale == nil then
            CursorRingCharDB.trailHeadScale = 120
        elseif CursorRingCharDB.trailHeadScale < 50 then
            CursorRingCharDB.trailHeadScale = 50
        elseif CursorRingCharDB.trailHeadScale > 220 then
            CursorRingCharDB.trailHeadScale = 220
        end
        if CursorRingCharDB.trailParticleCount == nil then
            CursorRingCharDB.trailParticleCount = 20
        elseif CursorRingCharDB.trailParticleCount < 4 then
            CursorRingCharDB.trailParticleCount = 4
        elseif CursorRingCharDB.trailParticleCount > 64 then
            CursorRingCharDB.trailParticleCount = 64
        end
        if CursorRingCharDB.trailParticleBurst == nil then
            CursorRingCharDB.trailParticleBurst = 2
        elseif CursorRingCharDB.trailParticleBurst < 1 then
            CursorRingCharDB.trailParticleBurst = 1
        elseif CursorRingCharDB.trailParticleBurst > 6 then
            CursorRingCharDB.trailParticleBurst = 6
        end
        if CursorRingCharDB.trailParticleSpread == nil then
            CursorRingCharDB.trailParticleSpread = 18
        elseif CursorRingCharDB.trailParticleSpread < 0 then
            CursorRingCharDB.trailParticleSpread = 0
        elseif CursorRingCharDB.trailParticleSpread > 80 then
            CursorRingCharDB.trailParticleSpread = 80
        end
        if CursorRingCharDB.trailParticleSpeed == nil then
            CursorRingCharDB.trailParticleSpeed = 80
        elseif CursorRingCharDB.trailParticleSpeed < 0 then
            CursorRingCharDB.trailParticleSpeed = 0
        elseif CursorRingCharDB.trailParticleSpeed > 260 then
            CursorRingCharDB.trailParticleSpeed = 260
        end
        if CursorRingCharDB.trailParticleSize == nil then
            CursorRingCharDB.trailParticleSize = 12
        elseif CursorRingCharDB.trailParticleSize < 2 then
            CursorRingCharDB.trailParticleSize = 2
        elseif CursorRingCharDB.trailParticleSize > 48 then
            CursorRingCharDB.trailParticleSize = 48
        end

        local db = CursorRingDB

        -- Help flags
        if db.helpMessageShownOnce == nil then
            db.helpMessageShownOnce = false
        end
        if db.showHelpOnLogin == nil then
            db.showHelpOnLogin = false
        end

        -- Offsets
        if db.offsetX == nil then db.offsetX = 0 end
        if db.offsetY == nil then db.offsetY = 0 end

        -- Gradient fields (legacy gradientEnabled is ignored)
        db.gradientEnabled = nil
        db.textureKey = nil
        if db.ringThickness == nil then
            db.ringThickness = 50
        elseif db.ringThickness < 1 then
            db.ringThickness = 1
        end
        if db.ringMargin == nil then
            db.ringMargin = 2
        elseif db.ringMargin < 0 then
            db.ringMargin = 0
        elseif db.ringMargin > 80 then
            db.ringMargin = 80
        end
        if db.gradientAngle == nil then
            db.gradientAngle = 315
        end
        if not db.gradientColor1 then
            db.gradientColor1 = { r = 1, g = 1, b = 1 }
        end
        if not db.gradientColor2 then
            db.gradientColor2 = { r = 0, g = 0, b = 0 }
        end

        -- Color mode migration (one-time from old useClassColor/useHighVis)
        if db.colorMode == nil then
            if db.useHighVis then
                db.colorMode = "highvis"
            elseif db.useClassColor == false then
                db.colorMode = "custom"
            else
                db.colorMode = "class"
            end
        end

        ring:SetShown(db.visible)
        RefreshTrailSystem(true)
        ns.UpdateAppearance()
        UpdateGCDCooldown()
        UpdateCastRingFromUnit()
        if not UpdateResourceRing() then
            ScheduleResourceRingStartupRetry()
        end
        ns.EnsureMinimapButton()
        ns.RefreshSharedLauncher()
        if C_Timer and ns.optionsPanel and type(ns.optionsPanel.RefreshControls) == "function" then
            C_Timer.After(0, function()
                if ns.optionsPanel and type(ns.optionsPanel.RefreshControls) == "function" then
                    ns.optionsPanel:RefreshControls()
                end
            end)
        end

        -- Cursor follow
        ring:SetScript("OnUpdate", function(_, elapsed)
            local x, y = GetScaledCursorPositionCompat()
            local db2 = CursorRingDB or ns.defaults
            local ox = db2.offsetX or 0
            local oy = db2.offsetY or 0

            if (x ~= lastCursorX) or (y ~= lastCursorY) or (ox ~= lastOffsetX) or (oy ~= lastOffsetY) then
                ring:ClearAllPoints()
                ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + ox, y + oy)
                lastCursorX, lastCursorY = x, y
                lastOffsetX, lastOffsetY = ox, oy
            end

            if resourceNeedsContinuousUpdate then
                UpdateResourceRing()
            end

            if castActive then
                UpdateCastRingVisual(GetTime())
            end

            if trailSystem and CursorRingCharDB and CursorRingCharDB.trailEnabled == true and type(trailSystem.Update) == "function" then
                trailSystem:Update(elapsed, x + ox, y + oy, db2.visible ~= false)
            end

        end)

        -- One-time / optional help message
        local shouldShowHelp = false
        if not db.helpMessageShownOnce then
            shouldShowHelp = true
            db.helpMessageShownOnce = true
        else
            shouldShowHelp = (db.showHelpOnLogin == true)
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if shouldShowHelp then
                    Say(T("Type /cr or open Esc -> Options -> AddOns -> Cursor Ring."))
                end
            end)
        elseif shouldShowHelp then
            Say(T("Type /cr or open Esc -> Options -> AddOns -> Cursor Ring."))
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateGCDStyle()
        UpdateGCDCooldown()
        UpdateCastRingFromUnit()
        if not UpdateResourceRing() then
            ScheduleResourceRingStartupRetry()
        end
        ns.RefreshSharedLauncher()

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if not HasCombatAlphaVariance() then
            return
        end
        ns.UpdateAppearance()

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        UpdateGCDCooldown()

    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_POWER_POINT_CHARGE" or event == "UNIT_DISPLAYPOWER" or event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        if not UpdateResourceRing() and (event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM") then
            ScheduleResourceRingStartupRetry()
        end

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        UpdateCastRingFromUnit()
        UpdateCastRingVisual(GetTime())

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        castActive = false
        castReverse = false
        castHoldAtMax = false
        castSpellID = nil
        ResetCastStageIndicators()
        castRing:Hide()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and spellID then
        if not (CursorRingCharDB and CursorRingCharDB.gcdEnabled) then
            SetGCDVisualActive(false)
            gcd:Hide()
            HideLegacyGCDSpinner()
            ns.UpdateAppearance()
            return
        end

        -- Check the cooldown of the spell we just cast; only show swipe if it has a real cooldown.
        local cooldownInfo = ReadSpellCooldownInfo(spellID)
        if IsCooldownInfoActive(cooldownInfo) then
            gcd:Show()
            MarkGCDMaskDirty()
            if ApplyCooldownFrameFromSpell(gcd, spellID, cooldownInfo) then
                SetGCDVisualActive(true)
            else
                SetGCDVisualActive(false)
                gcd:Hide()
            end
            HideLegacyGCDSpinner()
            ns.UpdateAppearance()
        else
            -- Fall back to the general GCD spell for safety.
            UpdateGCDCooldown()
        end
    end
end)

-----------------------------------------------------------------------
-- Public refresh
-----------------------------------------------------------------------
function ns.Refresh()
    ring:SetShown(CursorRingDB.visible)
    local trail = RefreshTrailSystem(false)
    ns.UpdateAppearance()
    UpdateGCDCooldown()
    UpdateCastRingFromUnit()
    if not UpdateResourceRing() then
        ScheduleResourceRingStartupRetry()
    end
    if not CursorRingDB.visible then
        gcd:Hide()
        HideLegacyGCDSpinner()
        castRing:Hide()
        ResetCastStageIndicators()
        resourceRingTrack:Hide()
        resourceRing:Hide()
        castActive = false
        if trail and type(trail.ResetTrail) == "function" then
            trail:ResetTrail()
        end
    end
    ns.RefreshSharedLauncher()
end

-----------------------------------------------------------------------
-- Slash commands
-----------------------------------------------------------------------
do
    SLASH_CURSORRING1 = "/cr"
    SlashCmdList.CURSORRING = function(msg)
        local args = {}
        for token in string.gmatch(msg or "", "%S+") do
            table.insert(args, strlower(token))
        end

        local cmd  = args[1]
        local arg1 = args[2]
        local arg2 = args[3]
        local db   = CursorRingDB or ns.defaults

        if cmd == "show" then
            db.visible = true
            ns.Refresh()
            Say(T("Shown"))

        elseif cmd == "hide" then
            db.visible = false
            ns.Refresh()
            Say(T("Hidden"))

        elseif cmd == "toggle" then
            db.visible = not db.visible
            ns.Refresh()
            Say(string.format(T("Toggled to %s"), db.visible and T("shown") or T("hidden")))

        elseif cmd == "reset" then
            CursorRingDB = CopyTable(ns.defaults)
            ns.Refresh()
            Say(T("Reset to defaults"))

        elseif cmd == "gcd" then
            CursorRingCharDB.gcdEnabled = not CursorRingCharDB.gcdEnabled
            if CursorRingCharDB.gcdEnabled then
                UpdateGCDStyle()
                UpdateGCDCooldown()
                Say(T("GCD swipe: enabled"))
            else
                gcd:Hide()
                HideLegacyGCDSpinner()
                ns.UpdateAppearance()
                Say(T("GCD swipe: disabled"))
            end

        elseif cmd == "gcdstyle" and arg1 then
            local v = strlower(arg1)
            if v == "blizzard" or v == "simple" then
                CursorRingCharDB.gcdStyle = v
                ns.Refresh()
                Say(string.format(T("GCD style set to %s"), v))
            else
                Say(T("Usage: /cr gcdstyle blizzard|simple"))
            end

        elseif cmd == "gcdtest" and ns.DEBUG_GCD then
            CursorRingCharDB.gcdEnabled = true
            UpdateGCDStyle()
            local now = GetTime()
            gcd:Show()
            gcd:SetCooldown(now, 1.5)
            Say(T("Test 1.5s GCD swipe"))
            DumpGCDState("GCDTEST")

        elseif cmd == "color" and arg1 then
            if arg1 == "rouge" then
                Say(T("It's spelled R-O-G-U-E."))
                return
            end

            if arg1 == "gradient" then
                db.colorMode = "gradient"
                ns.Refresh()
                Say(T("Color mode: gradient"))
                return
            elseif arg1 == "default" then
                db.colorMode = "class"
                ns.Refresh()
                Say(T("Color mode: class"))
                return
            elseif arg1 == "highvis" then
                db.colorMode = "highvis"
                ns.Refresh()
                Say(T("Color mode: high visibility"))
                return
            elseif arg1 == "custom" then
                db.colorMode = "custom"
                ns.Refresh()
                Say(T("Color mode: custom"))
                return
            end

            local classFile = ns.colorAlias[arg1] or arg1
            local r, g, b = GetClassColorRGB(classFile)
            if r and g and b then
                db.colorMode = classFile
                ns.Refresh()
                Say(string.format(T("Color set to %s"), classFile))
            else
                Say(string.format(T("Unknown color profile: %s"), arg1))
            end

        elseif cmd == "alpha" and arg1 and arg2 then
            local val = tonumber(arg2)
            if not val or val < 0 or val > 100 then
                Say(T("Alpha must be 0–100."))
                return
            end
            local normalized = val / 100

            if arg1 == "in" then
                db.inCombatAlpha = normalized
            elseif arg1 == "out" then
                db.outCombatAlpha = normalized
            else
                Say(T("Usage: /cr alpha in|out <0–100>"))
                return
            end
            ns.Refresh()
            Say(string.format(T("Alpha (%s) = %d%%"), arg1, math.floor(val + 0.5)))

        elseif cmd == "size" and arg1 then
            local v = tonumber(arg1)
            if not v then
                Say(T("Size must be numeric."))
                return
            end
            if v < 10 or v > 100 then
                Say(T("Size must be between 10–100."))
                return
            end
            db.ringRadius = math.floor(v)
            ns.Refresh()
            Say(string.format(T("Ring size set to %d"), db.ringRadius))

        elseif cmd == "right-click" and arg1 then
            if arg1 == "enable" then
                db.hideOnRightClick = true
            elseif arg1 == "disable" then
                db.hideOnRightClick = false
            elseif arg1 == "toggle" then
                db.hideOnRightClick = not db.hideOnRightClick
            else
                Say(T("Usage: /cr right-click enable|disable|toggle"))
                return
            end
            ns.Refresh()
            Say(string.format(T("Right-click hide: %s"), db.hideOnRightClick and T("enabled") or T("disabled")))

        else
            Say(T("Commands:"))
            Say(T("/cr show/hide/toggle/reset"))
            Say(T("/cr gcd       – toggle GCD swipe"))
            Say(T("/cr gcdstyle   – simple | blizzard"))
            Say(T("/cr color      – default, highvis, custom, gradient, <class>"))
            Say(T("/cr alpha      – in|out <0–100>"))
            Say(T("/cr size <n>   – 10–100"))
            Say(T("/cr right-click enable|disable/toggle"))
        end
    end
end

-- Initial size
local initialRadius = (ns.defaults and ns.defaults.ringRadius) or 28
ring:SetSize(initialRadius * 2, initialRadius * 2)
