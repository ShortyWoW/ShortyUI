local _, ns = ...
local Affected = ns.API.Affected

local ItemsData = ns.TrackerItemsData
local ItemVisuals = ns.TrackerItemVisuals
local WilduUICore = ns.WilduUICore
local LEM = LibStub("WildForkLibEQOLEditMode-1.0")

local ItemViewer = ns.TrackerItemViewer or {}
ns.TrackerItemViewer = ItemViewer

local UPDATE_THROTTLE_DELAY = 0.02
local DEFAULT_ICON_SIZE = 50
local DEFAULT_ICON_PADDING = 2
local BASE_SQUARE_MASK = "Interface\\AddOns\\CooldownManagerCentered\\Media\\Art\\Square"
local DEFAULT_MASK_TEXTURE = "Interface\\AddOns\\CooldownManagerCentered\\Media\\Art\\CooldownManager"

-- Events that drive a tracker's refreshes. Registered on the anchor while the
-- tracker is active and fully unregistered when it (or the whole custom tracker
-- system) is turned off, so a disabled tracker never reacts to game events or
-- re-shows itself — letting us toggle the feature live without a reload.
local TRACKER_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "ITEM_LOCKED",
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE_COOLDOWN",
    "PLAYER_ENTERING_WORLD",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED",
}

local ORIENTATION_ANCHORS = {
    ["Horizontal Right"] = { primary = "LEFT", offsetX = 1, offsetY = 0 },
    ["Horizontal Center"] = { primary = "CENTER", offsetX = 1, offsetY = 0 },
    ["Horizontal Left"] = { primary = "RIGHT", offsetX = -1, offsetY = 0 },
    ["Vertical Down"] = { primary = "TOP", offsetX = 0, offsetY = -1 },
    ["Vertical Up"] = { primary = "BOTTOM", offsetX = 0, offsetY = 1 },
}

local OPPOSITE_ANCHOR = {
    LEFT = "RIGHT",
    RIGHT = "LEFT",
    TOP = "BOTTOM",
    BOTTOM = "TOP",
    CENTER = "BOTTOM",
}

-- Colored "Cooldown Manager Centered" gradient used as the edit-mode label prefix.
local TRACKER_NAME_PREFIX =
    "|cff008945Cool|r|cff1e9a4e|r|cff3faa4fdown Ma|r|cff5fb64anag|r|cff7ac243er Ce|r|cff8ccd00ntered|r"

-- Edit-mode display name for a tracker config key ("tracker1" -> "...Centered 1").
local function GetTrackerDisplayName(configKey)
    local index = tonumber(tostring(configKey):match("tracker(%d+)$"))
    if index then
        return TRACKER_NAME_PREFIX .. " " .. index
    end
    return configKey
end

-- Active number of trackers (contiguous 1..N), clamped to [1, MAX_TRACKERS].
local function GetTrackerCount()
    local count = (ns.db and ns.db.profile and ns.db.profile.tracker_count) or 2
    local maxTrackers = ns.CONSTANTS.MAX_TRACKERS or 10
    if count < 1 then
        count = 1
    elseif count > maxTrackers then
        count = maxTrackers
    end
    return count
end

-- Runs callback(frameName) for every active tracker frame (for shared settings).
local function ForEachActiveTrackerFrameName(callback)
    for i = 1, GetTrackerCount() do
        callback("CMCTracker" .. i)
    end
end

local function GetIconHeight(iconSize)
    -- Masque skins square (1:1) icons; ignore the rectangular ratio entirely.
    if ns.MasqueModule and ns.MasqueModule:IsActive() then
        return iconSize
    end
    if ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_rectangularIcons then
        local percent = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_rectangularIcons_percent) or 0.8
        return math.floor(iconSize * percent)
    end
    return iconSize
end

local function ApplyCooldownFontToFrame(frame)
    if not frame or not frame.Cooldown or not frame.Cooldown.GetCountdownFontString then
        return
    end
    local fontString = frame.Cooldown:GetCountdownFontString()
    if not fontString then
        return
    end

    if not fontString.defaults then
        local fp, fsz, ffl = fontString:GetFont()
        fontString.defaults = { fp, fsz, ffl or "" }
    end

    local enabled = ns.db.profile.cooldownManager_cooldownFontSizeTracker_enabled

    -- Override off: restore the default font + centered position and stop
    -- overriding anything.
    if not enabled then
        if ns.API:GetIsAffected(frame, "cooldownfont") then
            fontString:SetFont(fontString.defaults[1], fontString.defaults[2], fontString.defaults[3])
            ns.API:UnsetAffected(frame, "cooldownfont")
        end
        if ns.API:GetIsAffected(frame, "cooldowntextpos") then
            fontString:ClearAllPoints()
            fontString:SetPoint("CENTER", frame.Cooldown, "CENTER", 0, 0)
            ns.API:UnsetAffected(frame, "cooldowntextpos")
        end
        return
    end

    fontString:SetAlpha(1)
    ns.API:SetAffected(frame, "cooldownfont")

    local size = ns.db.profile.cooldownManager_cooldownFontSizeTracker
    local numericSize = tonumber(size)
    if numericSize == 0 then
        fontString:SetFontHeight(0)
    else
        if size == "NIL" or size == nil then
            numericSize = fontString.defaults[2] or select(2, fontString:GetFont()) or 16
        else
            numericSize = numericSize or 16
        end
        local fontName = ns.db.profile.cooldownManager_cooldownFontName
        local fontPath = ns.API:GetFontPath(fontName) or fontString.defaults[1] or ns.CONSTANTS.DEFAULT_FONT[1]
        local fontFlagTable = ns.db.profile.cooldownManager_cooldownFontFlags
        fontString:SetFont(fontPath, numericSize, ns.API:GetFontFlags(fontFlagTable))
    end

    -- Shared countdown text position offset for all custom trackers. 0/0 keeps
    -- the default centered position.
    local ox = ns.db.profile.cooldownManager_cooldownTextTracker_offsetX or 0
    local oy = ns.db.profile.cooldownManager_cooldownTextTracker_offsetY or 0
    if ox ~= 0 or oy ~= 0 then
        fontString:ClearAllPoints()
        fontString:SetPoint("CENTER", frame.Cooldown, "CENTER", ox, oy)
        ns.API:SetAffected(frame, "cooldowntextpos")
    elseif ns.API:GetIsAffected(frame, "cooldowntextpos") then
        fontString:ClearAllPoints()
        fontString:SetPoint("CENTER", frame.Cooldown, "CENTER", 0, 0)
        ns.API:UnsetAffected(frame, "cooldowntextpos")
    end
end

local function ApplySquareStyle(frame)
    local borderThickness = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_borderThickness) or 1
    local zoom = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_iconZoom) or 0.3
    local crop = zoom * 0.5

    if frame.Icon and frame.Icon.SetTexCoord then
        local width, height = frame:GetSize()
        if width > 0 and height > 0 and width > height + 0.5 then
            -- Wider than tall: crop top/bottom proportionally to maintain zoom feel
            local horizontalSpan = 1 - (2 * crop)
            local verticalSpan = horizontalSpan * (height / width)
            local clampedSpan = math.max(0, math.min(1, verticalSpan))
            local verticalCrop = (1 - clampedSpan) * 0.5
            frame.Icon:SetTexCoord(crop, 1 - crop, verticalCrop, 1 - verticalCrop)
        elseif width > 0 and height > 0 and height > width + 0.5 then
            -- Taller than wide: crop left/right proportionally
            local verticalSpan = 1 - (2 * crop)
            local horizontalSpan = verticalSpan * (width / height)
            local clampedSpan = math.max(0, math.min(1, horizontalSpan))
            local horizontalCrop = (1 - clampedSpan) * 0.5
            frame.Icon:SetTexCoord(horizontalCrop, 1 - horizontalCrop, crop, 1 - crop)
        else
            frame.Icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        end
    end

    if frame.Cooldown then
        frame.Cooldown:SetSwipeTexture(BASE_SQUARE_MASK)
        frame.Cooldown:ClearAllPoints()
        frame.Cooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", borderThickness, -borderThickness)
        frame.Cooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderThickness, borderThickness)
    end

    if frame.mask then
        frame.mask:SetTexture(BASE_SQUARE_MASK)
        frame.mask:Show()
    else
        local mask = frame:CreateMaskTexture()
        mask:SetAllPoints(frame.Icon)
        mask:SetTexture(BASE_SQUARE_MASK)
        frame.Icon:AddMaskTexture(mask)
        frame.mask = mask
    end

    if not Affected(frame).border then
        Affected(frame).border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        Affected(frame).border:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
    Affected(frame).border:ClearAllPoints()
    Affected(frame).border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    Affected(frame).border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    if borderThickness <= 0 then
        Affected(frame).border:Hide()
    else
        Affected(frame).border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = borderThickness,
        })
        Affected(frame).border:SetBackdropBorderColor(0, 0, 0, 1)
        Affected(frame).border:Show()
    end
    ns.API:SetAffected(frame, "squareStyle")
end

local function RestoreDefaultStyle(frame)
    if not ns.API:GetIsAffected(frame, "squareStyle") then
        return
    end
    if frame.Icon and frame.Icon.SetTexCoord then
        frame.Icon:SetTexCoord(0, 1, 0, 1)
    end

    if frame.Cooldown then
        frame.Cooldown:SetSwipeTexture(DEFAULT_MASK_TEXTURE)
        frame.Cooldown:ClearAllPoints()
        frame.Cooldown:SetAllPoints(frame)
    end

    if frame.mask then
        frame.mask:SetTexture(DEFAULT_MASK_TEXTURE)
        frame.mask:Show()
    end
    if Affected(frame).border then
        Affected(frame).border:Hide()
    end
    ns.API:UnsetAffected(frame, "squareStyle")
end

local function ApplyStyleToFrame(frame)
    -- When Masque integration is active it owns the icon styling; let it skin
    -- this frame and skip CMC's own square-icon / border styling.
    if ns.MasqueModule and ns.MasqueModule:IsActive() then
        ns.MasqueModule:SkinTrackerIcon(frame)
        return
    end

    local isSquare = ns.db.profile.trinketRacialTracker_squareIcons or false

    if isSquare then
        ApplySquareStyle(frame)
    else
        RestoreDefaultStyle(frame)
    end

    if frame.IconOverlay then
        if isSquare then
            frame.IconOverlay:Hide()
        else
            frame.IconOverlay:Show()
        end
    end
end

local function ApplyStackFontToFrame(frame)
    -- Masque positions the Count region itself; don't fight it.
    if ns.MasqueModule and ns.MasqueModule:IsActive() then
        return
    end
    local fontName = ns.db.profile.cooldownManager_stackFontName
    local fontPath = ns.API:GetFontPath(fontName) or ns.CONSTANTS.DEFAULT_NUMBER_FONT[1]
    local fontFlagTable = ns.db.profile.cooldownManager_stackFontFlags or {}
    local fontFlagStr = ns.API:GetFontFlags(fontFlagTable)
    local fontSize = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_stackFontSize) or 14
    local anchor = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_stackAnchor) or "BOTTOMRIGHT"
    local offsetX = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_stackOffsetX) or -1
    local offsetY = (ns.db and ns.db.profile and ns.db.profile.trinketRacialTracker_stackOffsetY) or 1

    if frame.count then
        frame.count:SetFont(fontPath, fontSize, fontFlagStr)
        frame.count:ClearAllPoints()
        frame.count:SetPoint(anchor, frame, anchor, offsetX, offsetY)
    end
end

local ItemViewerFrame = {}
ItemViewerFrame.__index = ItemViewerFrame

function ItemViewerFrame:New(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local obj = setmetatable({ frame = frame }, ItemViewerFrame)
    obj:Initialize()
    return obj
end

function ItemViewerFrame:Initialize()
    local frame = self.frame
    frame.showGCD = false
    if not frame.Icon then
        frame.Icon = frame:CreateTexture(nil, "ARTWORK")
        frame.Icon:SetAllPoints()
        frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local width, height = frame:GetSize()
    if not frame.IconOverlay and frame.Icon then
        frame.IconOverlay = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        frame.IconOverlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
        frame.IconOverlay:SetSize(width * 1.5, height * 1.5)
        frame.IconOverlay:SetPoint("Center", frame.Icon, "CENTER")
        frame.IconOverlay:Hide()
    end
    if not frame.Cooldown then
        frame.Cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        frame.Cooldown:SetAllPoints()
        frame.Cooldown:SetDrawEdge(false)
        frame.Cooldown:SetDrawBling(false)
        frame.Cooldown:SetSwipeTexture(DEFAULT_MASK_TEXTURE)
        frame.Cooldown:SetHideCountdownNumbers(false)
        frame.Cooldown:HookScript("OnCooldownDone", function()
            ItemVisuals:UpdateEntryCooldown(frame, Affected(frame).trackerEntryKind, Affected(frame).trackerEntryId)
        end)
    end
    if not frame.mask then
        local mask = frame:CreateMaskTexture()
        mask:SetAllPoints(frame.Icon)
        mask:SetTexture(DEFAULT_MASK_TEXTURE)
        frame.Icon:AddMaskTexture(mask)
        frame.mask = mask
    end

    if not frame.count then
        local overlay = CreateFrame("Frame", nil, frame)
        overlay:SetAllPoints(frame)
        overlay:SetFrameLevel(frame.Cooldown:GetFrameLevel() + 5)

        local count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        count:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        count:SetShadowOffset(1, -1)
        count:SetShadowColor(0, 0, 0, 1)
        frame.count = count
    end
    ApplyStyleToFrame(frame)
    ApplyStackFontToFrame(frame)
    ApplyCooldownFontToFrame(frame)
    frame:Hide()
end

function ItemViewerFrame:Show()
    self.frame:Show()
end

function ItemViewerFrame:Hide()
    self.frame:Hide()
end

function ItemViewerFrame:UpdateEntry(entry)
    local frame = self.frame
    -- Reset identity first: these frames are pooled/reused, and the spellID/itemID
    -- below are only set when the new entry actually has them. Without clearing,
    -- a frame reused for an entry with no on-use spell keeps the previous entry's
    -- spellID, leaving its (now wrong) keybind text showing. Keybinds refresh off
    -- frame.spellID, so a nil here correctly clears the keybind for spell-less items.
    frame.spellID = nil
    frame.itemID = nil
    if not entry then
        Affected(frame).trackerEntryKind = nil
        Affected(frame).trackerEntryId = nil
        frame:Hide()
        return
    end

    Affected(frame).trackerEntryKind = entry.kind
    Affected(frame).trackerEntryId = entry.id

    if entry.kind == "item" then
        local _spellName, spellID = C_Item.GetItemSpell(entry.id)
        frame.itemID = entry.id
        if spellID then
            frame.spellID = spellID
        end
    elseif entry.kind == "wildcardSlots" then
        local itemID = ItemsData:GetWildcardSlotItemID(entry.id)
        if itemID then
            frame.itemID = itemID
            local _spellName, spellID = C_Item.GetItemSpell(itemID)
            if spellID then
                frame.spellID = spellID
            end
        end
    elseif entry.kind == "spell" then
        frame.spellID = entry.id
    end
    ItemVisuals:ApplyEntryIcon(frame, entry.kind, entry.id)
    ItemVisuals:UpdateEntryCooldown(frame, entry.kind, entry.id)
    ApplyStyleToFrame(frame)
    ApplyStackFontToFrame(frame)
    ApplyCooldownFontToFrame(frame)

    frame:Show()
end

function ItemViewerFrame:UpdateCooldown()
    if not ns.db.profile.tracker_enabled then
        return
    end
    local frame = self.frame
    if not frame:IsShown() or not Affected(frame).trackerEntryKind or not Affected(frame).trackerEntryId then
        return
    end
    ItemVisuals:ApplyEntryIcon(frame, Affected(frame).trackerEntryKind, Affected(frame).trackerEntryId)
    ItemVisuals:UpdateEntryCooldown(frame, Affected(frame).trackerEntryKind, Affected(frame).trackerEntryId)
end

local function GetConfigValue(configKey, key, default)
    if ns.db and ns.db.profile and ns.db.profile.editMode and ns.db.profile.editMode[configKey] then
        return ns.db.profile.editMode[configKey][key] or default
    end
    return default
end

local TrackerInstance = {}
TrackerInstance.__index = TrackerInstance

function TrackerInstance:New(configKey, frameName, getEntriesFn)
    local instance = setmetatable({
        configKey = configKey,
        frameName = frameName,
        index = tonumber(tostring(configKey):match("tracker(%d+)$")),
        editModeName = GetTrackerDisplayName(configKey),
        getEntriesFn = getEntriesFn,
        active = false,
        anchor = nil,
        iconFrames = {},
        lastUpdateTimes = {},
        pendingHide = {},
        shownKeys = {},
        shownOrder = {},
    }, TrackerInstance)
    return instance
end

function TrackerInstance:GetIconSize()
    return GetConfigValue(self.configKey, "iconSize", DEFAULT_ICON_SIZE)
end

function TrackerInstance:GetIconPadding()
    return GetConfigValue(self.configKey, "iconPadding", DEFAULT_ICON_PADDING)
end

function TrackerInstance:GetOrientation()
    return GetConfigValue(self.configKey, "orientation", "Horizontal Right")
end

function TrackerInstance:GetShowGCD()
    return GetConfigValue(self.configKey, "showGCD", false)
end

function TrackerInstance:GetShowStacks()
    -- Stacks/charge numbers are shown by default; only an explicit false hides them.
    if ns.db and ns.db.profile and ns.db.profile.editMode and ns.db.profile.editMode[self.configKey] then
        local v = ns.db.profile.editMode[self.configKey].showStacks
        if v ~= nil then
            return v and true or false
        end
    end
    return true
end

function TrackerInstance:UpdateIconPosition(frame, visibleIndex)
    local iconSize = self:GetIconSize()
    local iconHeight = GetIconHeight(iconSize)
    local padding = self:GetIconPadding()
    local orientation = self:GetOrientation()
    local anchorData = ORIENTATION_ANCHORS[orientation] or ORIENTATION_ANCHORS["Horizontal Right"]

    local anchorPoint = anchorData.primary
    if anchorPoint == "CENTER" then
        anchorPoint = "LEFT"
    end
    frame:ClearAllPoints()
    -- Use iconHeight for vertical layouts so icons don't overlap when height < width
    local isVertical = anchorData.offsetY ~= 0
    local stepSize = isVertical and (iconHeight + padding) or (iconSize + padding)
    local offset = (visibleIndex - 1) * stepSize
    frame:SetPoint(anchorPoint, self.anchor, anchorPoint, anchorData.offsetX * offset, anchorData.offsetY * offset)
end

function TrackerInstance:UpdateCooldowns()
    if not ns.db.profile.tracker_enabled then
        return
    end
    if
        self.lastUpdateTimes.UpdateCooldownsThrottle
        and (GetTime() - self.lastUpdateTimes.UpdateCooldownsThrottle) < UPDATE_THROTTLE_DELAY
    then
        return
    end

    self.lastUpdateTimes.UpdateCooldownsThrottle = GetTime()
    for _, ivf in ipairs(self.iconFrames) do
        ivf:UpdateCooldown()
    end
end

function TrackerInstance:ApplyStabilityGuard(newEntries)
    local prevPos = {}
    for i, key in ipairs(self.shownOrder) do
        prevPos[key] = i
    end

    local function entryKey(e)
        return e.kind .. ":" .. tostring(e.id)
    end

    table.sort(newEntries, function(a, b)
        local aOrder, bOrder = ItemsData:GetEntryOrder(a), ItemsData:GetEntryOrder(b)
        if aOrder ~= bOrder then
            if aOrder == nil then
                return false
            end
            if bOrder == nil then
                return true
            end
            return aOrder < bOrder
        end
        local aPrev, bPrev = prevPos[entryKey(a)], prevPos[entryKey(b)]
        if aPrev ~= bPrev then
            if aPrev == nil then
                return false
            end
            if bPrev == nil then
                return true
            end
            return aPrev < bPrev
        end
        local aName = ItemsData:GetEntryName(a.kind, a.id) or tostring(a.id)
        aName = aName == "" and tostring(a.id) or aName:lower()
        local bName = ItemsData:GetEntryName(b.kind, b.id) or tostring(b.id)
        bName = bName == "" and tostring(b.id) or bName:lower()
        if aName ~= bName then
            return aName < bName
        end
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        return tostring(a.id) < tostring(b.id)
    end)

    self.shownOrder = {}
    for _, entry in ipairs(newEntries) do
        table.insert(self.shownOrder, entryKey(entry))
    end

    return newEntries
end

function TrackerInstance:RefreshEntries()
    if not self.anchor then
        return
    end
    if
        self.lastUpdateTimes.RefreshEntriesThrottle
        and (GetTime() - self.lastUpdateTimes.RefreshEntriesThrottle) < UPDATE_THROTTLE_DELAY
    then
        return
    end

    self:DoRefreshEntries()
end

function TrackerInstance:DoRefreshEntries()
    if not self.anchor then
        return
    end

    self.lastUpdateTimes.RefreshEntriesThrottle = GetTime()

    local owned = ItemsData:ScanOwnedItems()
    ItemsData:EnsureTrackedItems(owned)
    local rawEntries = self.getEntriesFn(owned)
    local entries = self:ApplyStabilityGuard(rawEntries)

    local iconSize = self:GetIconSize()
    local iconHeight = GetIconHeight(iconSize)
    local padding = self:GetIconPadding()
    local orientation = self:GetOrientation()
    local showGCD = self:GetShowGCD()
    local showStacks = self:GetShowStacks()
    local count = #entries

    for i = 1, count do
        if not self.iconFrames[i] then
            self.iconFrames[i] = ItemViewerFrame:New(self.anchor)
        end
        local ivf = self.iconFrames[i]
        ivf.frame:SetSize(iconSize, iconHeight)
        ivf.frame.IconOverlay:SetSize(iconSize * 1.5, iconHeight * 1.5)
        ivf.frame.showGCD = showGCD
        ivf.frame.showStacks = showStacks
        -- Hiding the count fontstring persists across SetText, so the stack/charge
        -- number stays hidden even as cooldown updates re-write its text.
        if ivf.frame.count then
            ivf.frame.count:SetShown(showStacks)
        end

        ivf:UpdateEntry(entries[i])
        self:UpdateIconPosition(ivf.frame, i)
    end

    for i = count + 1, #self.iconFrames do
        self.iconFrames[i]:UpdateEntry(nil)
    end

    local isHorizontal = orientation == "Horizontal Right"
        or orientation == "Horizontal Left"
        or orientation == "Horizontal Center"
    local totalWidthSize = count > 0 and (count * iconSize + (count - 1) * padding) or iconSize
    local totalHeightSize = count > 0 and (count * iconHeight + (count - 1) * padding) or iconHeight
    if isHorizontal then
        self.anchor:SetSize(totalWidthSize, iconHeight)
    else
        self.anchor:SetSize(iconSize, totalHeightSize)
    end

    -- A deactivated (trimmed) tracker must never re-show, even if stale item state
    -- somehow still maps to it; only active trackers with content (or forced in edit
    -- mode) are shown.
    self.anchor:SetShown(self.active and (count > 0 or Affected(self.anchor).trackerForceShow))
    ns.Keybinds:UpdateAllKeybinds()
end

function TrackerInstance:RefreshStyling()
    for _, ivf in ipairs(self.iconFrames) do
        if ivf.frame:IsShown() then
            ApplyStyleToFrame(ivf.frame)
            ApplyStackFontToFrame(ivf.frame)
            ApplyCooldownFontToFrame(ivf.frame)
        end
    end
end

function TrackerInstance:UpdateIconLayout()
    local iconSize = self:GetIconSize()
    local iconHeight = GetIconHeight(iconSize)
    for _, ivf in ipairs(self.iconFrames) do
        ivf.frame:SetSize(iconSize, iconHeight)
        ivf.frame.IconOverlay:SetSize(iconSize * 1.5, iconHeight * 1.5)
    end
    self:RefreshEntries()
end

-- (Re)registers the refresh-driving events on the anchor. Idempotent, so it's
-- safe to call on every activation.
function TrackerInstance:RegisterTrackerEvents()
    if not self.anchor then
        return
    end
    for _, event in ipairs(TRACKER_EVENTS) do
        self.anchor:RegisterEvent(event)
    end
end

-- Drops all event registrations on the anchor so a deactivated tracker stays
-- inert (and hidden). The OnEvent handler script is left intact for cheap reuse.
function TrackerInstance:UnregisterTrackerEvents()
    if self.anchor then
        self.anchor:UnregisterAllEvents()
    end
end

function TrackerInstance:Create()
    if self.anchor then
        return
    end

    local DEFAULT_CONFIG = {
        alpha = 1,
        point = "CENTER",
        x = 0,
        y = 200,
        scale = 1,
        strata = "MEDIUM",
        iconSize = DEFAULT_ICON_SIZE,
        iconPadding = DEFAULT_ICON_PADDING,
        orientation = "Horizontal Right",
        anchoredToTracker1 = false,
        anchoredToTracker1Spacing = DEFAULT_ICON_PADDING,
    }

    WilduUICore.LoadFrameConfig(self.configKey, DEFAULT_CONFIG)
    local iconSize = self:GetIconSize()

    self.anchor = CreateFrame("Frame", self.frameName, UIParent, "BackdropTemplate")

    self.anchor.editModeName = self.editModeName

    self.anchor:SetSize(iconSize, iconSize)
    self.anchor:SetClampedToScreen(true)

    self:RegisterTrackerEvents()

    self.anchor:SetScript("OnEvent", function(_, event, arg1)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
            self:UpdateCooldowns()
            C_Timer.After(UPDATE_THROTTLE_DELAY + 0.01, function()
                self:UpdateCooldowns()
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:RefreshEntries()
            C_Timer.After(5, function()
                self:RefreshEntries()
            end)
        elseif event == "ITEM_LOCKED" then
            self:RefreshEntries()
            C_Timer.After(0.5, function()
                self:RefreshEntries()
            end)
        elseif event == "BAG_UPDATE_DELAYED" then
            C_Timer.After(0.05, function()
                self:RefreshEntries()
            end)
        elseif
            event == "TRAIT_CONFIG_UPDATED"
            or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "PLAYER_TALENT_UPDATE"
            or event == "ACTIVE_TALENT_GROUP_CHANGED"
        then
            if ItemsData and ItemsData.InvalidateSpellBookCache then
                ItemsData:InvalidateSpellBookCache()
            end
            self:RefreshEntries()
            C_Timer.After(0.1, function()
                self:RefreshEntries()
            end)
        else
            self:RefreshEntries()
        end
    end)

    WilduUICore.ApplyFramePosition(self.anchor, self.configKey, false)

    WilduUICore.RegisterEditModeCallbacks(self.anchor, self.configKey, function()
        return self.active
    end, function()
        return not ns.db.profile.editMode[self.configKey].anchoredToTracker1
    end)

    local configKey = self.configKey
    local anchor = self.anchor
    local instance = self

    local RELATIVE_FACTORS = {
        LEFT = { x = 0, y = -0.5 },
        RIGHT = { x = -1, y = -0.5 },
        TOP = { x = -0.5, y = -1 },
        BOTTOM = { x = -0.5, y = 0 },
    }

    local function OnPositionChanged(frame, layoutName, _point, _x, _y)
        local orientation = instance:GetOrientation()
        local anchorData = ORIENTATION_ANCHORS[orientation] or ORIENTATION_ANCHORS["Horizontal Right"]
        local anchorPrimary = (anchorData and anchorData.primary) or "RIGHT"

        if ns.db.profile.editMode[configKey].anchoredToTracker1 then
            local x, y
            local config = ns.db.profile.editMode[configKey]
            local spacing = config.anchoredToTracker1Spacing or DEFAULT_ICON_PADDING
            if anchorPrimary == "LEFT" then
                x = spacing
                y = 0
            elseif anchorPrimary == "RIGHT" then
                x = -spacing
                y = 0
            elseif anchorPrimary == "TOP" then
                x = 0
                y = -spacing
            else
                x = 0
                y = spacing
            end
            frame:SetClampedToScreen(true)
            if config.scale ~= nil then
                frame:SetScale(config.scale)
            end
            frame:ClearAllPoints()
            -- Anchor to the previous tracker in the chain (tracker N anchors to N-1).
            local prevFrame = _G["CMCTracker" .. ((instance.index or 2) - 1)]
            if prevFrame then
                frame:SetPoint(anchorPrimary, prevFrame, OPPOSITE_ANCHOR[anchorPrimary], x, y)
            end
            return
        end
        local screenWidth, screenHeight = UIParent:GetSize()
        local frameWidth, frameHeight = frame:GetSize()
        local centerX, centerY = frame:GetCenter()

        if not centerX or not centerY or not frameWidth or not frameHeight then
            return
        end

        local frameScale = frame:GetEffectiveScale()
        local uiParentScale = UIParent:GetEffectiveScale()
        local scale = frameScale / uiParentScale

        screenWidth, screenHeight = screenWidth / scale, screenHeight / scale

        local newX, newY
        local factor = RELATIVE_FACTORS[anchorPrimary]

        if anchorPrimary == "LEFT" then
            newX = centerX - frameWidth / 2
            newY = centerY + (screenHeight * factor.y)
        elseif anchorPrimary == "RIGHT" then
            newX = centerX + frameWidth / 2 - screenWidth
            newY = centerY + (screenHeight * factor.y)
        elseif anchorPrimary == "TOP" then
            newX = centerX + (screenWidth * factor.x)
            newY = centerY + frameHeight / 2 - screenHeight
        elseif anchorPrimary == "BOTTOM" then
            newX = centerX + (screenWidth * factor.x)
            newY = centerY - frameHeight / 2
        elseif anchorPrimary == "CENTER" then
            newX = centerX - screenWidth / 2
            newY = centerY - screenHeight / 2
        end

        ns.db.profile.editMode[configKey].point = anchorPrimary
        ns.db.profile.editMode[configKey].x = newX
        ns.db.profile.editMode[configKey].y = newY

        WilduUICore.ApplyFramePosition(frame, configKey, false)
    end

    local additionalSettings = {
        {
            kind = LEM.SettingType.Collapsible,
            id = "layout",
            name = "Layout",
            defaultCollapsed = false,
        },
        {
            name = "Icon Size",
            parentId = "layout",
            kind = LEM.SettingType.Slider,
            default = DEFAULT_ICON_SIZE,
            get = function()
                return ns.db.profile.editMode[configKey].iconSize or DEFAULT_ICON_SIZE
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].iconSize = value
                instance:UpdateIconLayout()
            end,
            minValue = 16,
            maxValue = 80,
            valueStep = 2,
            formatter = function(value)
                return string.format("%d px", value)
            end,
        },
        {
            name = "Icon Padding",
            parentId = "layout",
            kind = LEM.SettingType.Slider,
            default = DEFAULT_ICON_PADDING,
            get = function()
                return ns.db.profile.editMode[configKey].iconPadding or DEFAULT_ICON_PADDING
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].iconPadding = value
                instance:RefreshEntries()
            end,
            minValue = 0,
            maxValue = 20,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d px", value)
            end,
        },
        {
            name = "Orientation",
            parentId = "layout",
            kind = LEM.SettingType.Dropdown,
            default = DEFAULT_CONFIG.orientation,
            get = function()
                return ns.db.profile.editMode[configKey].orientation or DEFAULT_CONFIG.orientation
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].orientation = value
                OnPositionChanged(anchor, configKey)
                instance:RefreshEntries()
            end,
            values = {
                { text = "Horizontal Right" },
                { text = "Horizontal Center" },
                { text = "Horizontal Left" },
                { text = "Vertical Down" },
                { text = "Vertical Up" },
            },
        },
        {
            name = "Alpha",
            parentId = "layout",
            kind = LEM.SettingType.Slider,
            default = DEFAULT_CONFIG.alpha,
            get = function()
                return ns.db.profile.editMode[configKey].alpha or DEFAULT_CONFIG.alpha
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].alpha = value
                anchor:SetAlpha(value)
            end,
            minValue = 0.1,
            maxValue = 1,
            valueStep = 0.01,
            formatter = function(value)
                return string.format("%.2f", value)
            end,
        },
        {
            name = "Show GCD",
            parentId = "layout",
            kind = LEM.SettingType.Checkbox,
            default = false,
            get = function()
                return ns.db.profile.editMode[configKey].showGCD or false
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].showGCD = value
                instance:RefreshEntries()
            end,
        },
    }

    -- Anchor-to-previous-tracker chaining belongs to the Layout section. Added
    -- here (right after the base layout settings) so it nests correctly.
    if (self.index or 1) > 1 then
        tinsert(additionalSettings, {
            name = "Anchor to Tracker " .. ((self.index or 2) - 1),
            parentId = "layout",
            kind = LEM.SettingType.Checkbox,
            default = false,
            get = function()
                return ns.db.profile.editMode[configKey].anchoredToTracker1 or false
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].anchoredToTracker1 = value
                OnPositionChanged(anchor, configKey)
                instance:RefreshEntries()
            end,
        })
        tinsert(additionalSettings, {
            name = "Spacing",
            parentId = "layout",
            kind = LEM.SettingType.Slider,
            default = DEFAULT_ICON_PADDING,
            get = function()
                return ns.db.profile.editMode[configKey].anchoredToTracker1Spacing or DEFAULT_ICON_PADDING
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].anchoredToTracker1Spacing = value
                OnPositionChanged(anchor, configKey)
                instance:RefreshEntries()
            end,
            minValue = 0,
            maxValue = 96,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        })
    end

    -- Icon styling & stack-number settings are owned by Masque when active, so
    -- they're only added to the panel when Masque skinning is off.
    if not (ns.MasqueModule and ns.MasqueModule:IsActive()) then
        local stylingSettings = {
            {
                kind = LEM.SettingType.Collapsible,
                id = "styling",
                name = "Styling",
                defaultCollapsed = true,
            },
            {
                name = "Square Icons",
                parentId = "styling",
                kind = LEM.SettingType.Checkbox,
                default = false,
                get = function()
                    return ns.db.profile.trinketRacialTracker_squareIcons or false
                end,
                set = function(layoutName, value)
                    ns.db.profile.trinketRacialTracker_squareIcons = value
                    if ns.TrackerItemViewer then
                        ns.TrackerItemViewer:RefreshStyling()
                    end
                end,
            },
            {
                name = "Border Thickness",
                parentId = "styling",
                kind = LEM.SettingType.Slider,
                default = 1,
                get = function()
                    return ns.db.profile.trinketRacialTracker_borderThickness or 1
                end,
                set = function(layoutName, value)
                    ns.db.profile.trinketRacialTracker_borderThickness = value
                    if ns.TrackerItemViewer then
                        ns.TrackerItemViewer:RefreshStyling()
                    end
                end,
                minValue = 0,
                maxValue = 6,
                valueStep = 1,
                formatter = function(value)
                    return string.format("%dpx", value)
                end,
            },
            {
                name = "Icon Zoom",
                parentId = "styling",
                kind = LEM.SettingType.Slider,
                default = 0.3,
                get = function()
                    return ns.db.profile.trinketRacialTracker_iconZoom or 0.3
                end,
                set = function(layoutName, value)
                    ns.db.profile.trinketRacialTracker_iconZoom = value
                    if ns.TrackerItemViewer then
                        ns.TrackerItemViewer:RefreshStyling()
                    end
                end,
                minValue = 0,
                maxValue = 0.5,
                valueStep = 0.01,
                formatter = function(value)
                    return string.format("%.2f", value)
                end,
            },
            {
                name = "Rectangular Icons",
                parentId = "styling",
                kind = LEM.SettingType.Checkbox,
                default = false,
                get = function()
                    return ns.db.profile.trinketRacialTracker_rectangularIcons or false
                end,
                set = function(layoutName, value)
                    ns.db.profile.trinketRacialTracker_rectangularIcons = value
                    if ns.TrackerItemViewer then
                        ns.TrackerItemViewer:RefreshItemViewerFrames()
                    end
                end,
            },
            {
                name = "Aspect Ratio (Height %)",
                parentId = "styling",
                kind = LEM.SettingType.Slider,
                default = 0.8,
                get = function()
                    return ns.db.profile.trinketRacialTracker_rectangularIcons_percent or 0.8
                end,
                set = function(layoutName, value)
                    ns.db.profile.trinketRacialTracker_rectangularIcons_percent = math.floor(value * 100 + 0.5) / 100
                    if ns.TrackerItemViewer then
                        ns.TrackerItemViewer:RefreshItemViewerFrames()
                    end
                end,
                minValue = 0.3,
                maxValue = 1,
                valueStep = 0.01,
                formatter = function(value)
                    return string.format("%.0f%%", value * 100)
                end,
            },
        }
        for _, s in ipairs(stylingSettings) do
            tinsert(additionalSettings, s)
        end
    end

    -- Cooldown-number controls are all gated by the override checkbox (the font,
    -- flags, size and text offset only apply while it's on — see
    -- ApplyCooldownFontToFrame, which restores defaults when off).
    local function cooldownNumberEnabled()
        return ns.db.profile.cooldownManager_cooldownFontSizeTracker_enabled and true or false
    end

    -- Stack numbers are shown by default (per tracker); the remaining stack
    -- controls are hidden while the master checkbox is off.
    local function stacksEnabled()
        local cfg = ns.db.profile.editMode[configKey]
        if cfg and cfg.showStacks ~= nil then
            return cfg.showStacks and true or false
        end
        return true
    end

    local stacksCooldownAndKeybindSettings = {
        {
            kind = LEM.SettingType.Collapsible,
            id = "stacks",
            name = "Charges/Count",
            defaultCollapsed = true,
        },
        {
            name = "Show Charges/Count",
            parentId = "stacks",
            kind = LEM.SettingType.Checkbox,
            default = true,
            get = function()
                local cfg = ns.db.profile.editMode[configKey]
                if cfg and cfg.showStacks ~= nil then
                    return cfg.showStacks and true or false
                end
                return true
            end,
            set = function(layoutName, value)
                ns.db.profile.editMode[configKey].showStacks = value and true or false
                instance:RefreshEntries()
            end,
        },
        {
            name = "Anchor",
            parentId = "stacks",
            kind = LEM.SettingType.Dropdown,
            default = "BOTTOMRIGHT",
            isShown = stacksEnabled,
            get = function()
                return ns.db.profile.trinketRacialTracker_stackAnchor or "BOTTOMRIGHT"
            end,
            set = function(layoutName, value)
                ns.db.profile.trinketRacialTracker_stackAnchor = value
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            values = {
                { text = "Top Left", value = "TOPLEFT" },
                { text = "Top", value = "TOP" },
                { text = "Top Right", value = "TOPRIGHT" },
                { text = "Left", value = "LEFT" },
                { text = "Center", value = "CENTER" },
                { text = "Right", value = "RIGHT" },
                { text = "Bottom Left", value = "BOTTOMLEFT" },
                { text = "Bottom", value = "BOTTOM" },
                { text = "Bottom Right", value = "BOTTOMRIGHT" },
            },
        },
        {
            name = "Font Size",
            parentId = "stacks",
            kind = LEM.SettingType.Slider,
            default = 14,
            isShown = stacksEnabled,
            get = function()
                return ns.db.profile.trinketRacialTracker_stackFontSize or 14
            end,
            set = function(layoutName, value)
                ns.db.profile.trinketRacialTracker_stackFontSize = value
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            minValue = 8,
            maxValue = 32,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
        {
            name = "X Offset",
            parentId = "stacks",
            kind = LEM.SettingType.Slider,
            default = -1,
            isShown = stacksEnabled,
            get = function()
                return ns.db.profile.trinketRacialTracker_stackOffsetX or -1
            end,
            set = function(layoutName, value)
                ns.db.profile.trinketRacialTracker_stackOffsetX = value
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            minValue = -40,
            maxValue = 40,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
        {
            name = "Y Offset",
            parentId = "stacks",
            kind = LEM.SettingType.Slider,
            default = 1,
            isShown = stacksEnabled,
            get = function()
                return ns.db.profile.trinketRacialTracker_stackOffsetY or 1
            end,
            set = function(layoutName, value)
                ns.db.profile.trinketRacialTracker_stackOffsetY = value
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            minValue = -40,
            maxValue = 40,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
        {
            kind = LEM.SettingType.Collapsible,
            id = "cdfont",
            name = "Cooldown Numbers",
            defaultCollapsed = true,
        },
        {
            name = "Override Font",
            parentId = "cdfont",
            kind = LEM.SettingType.Checkbox,
            default = false,
            get = function()
                return ns.db.profile.cooldownManager_cooldownFontSizeTracker_enabled
            end,
            set = function(layoutName, value)
                ns.db.profile.cooldownManager_cooldownFontSizeTracker_enabled = value
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
        },
        ns.EditModeViewerSettings:BuildCooldownFontNameSetting({
            parentId = "cdfont",
            isShown = cooldownNumberEnabled,
        }),
        ns.EditModeViewerSettings:BuildCooldownFontFlagsSetting({
            parentId = "cdfont",
            isShown = cooldownNumberEnabled,
        }),
        {
            name = "Number Size",
            parentId = "cdfont",
            kind = LEM.SettingType.Dropdown,
            default = "NIL",
            isShown = cooldownNumberEnabled,
            get = function()
                return ns.db.profile.cooldownManager_cooldownFontSizeTracker ~= nil
                        and tostring(ns.db.profile.cooldownManager_cooldownFontSizeTracker)
                    or "NIL"
            end,
            set = function(layoutName, value)
                if value == "NIL" then
                    ns.db.profile.cooldownManager_cooldownFontSizeTracker = "NIL"
                else
                    local n = tonumber(value)
                    ns.db.profile.cooldownManager_cooldownFontSizeTracker = n
                end
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            values = {
                { text = "Default", value = "NIL" },
                { text = "Hide", value = "0" },
                { text = "10", value = "10" },
                { text = "12", value = "12" },
                { text = "14", value = "14" },
                { text = "16", value = "16" },
                { text = "18", value = "18" },
                { text = "20", value = "20" },
                { text = "22", value = "22" },
                { text = "24", value = "24" },
                { text = "26", value = "26" },
                { text = "28", value = "28" },
                { text = "30", value = "30" },
                { text = "32", value = "32" },
                { text = "34", value = "34" },
                { text = "36", value = "36" },
                { text = "38", value = "38" },
            },
        },
        {
            name = "Number X Offset",
            parentId = "cdfont",
            kind = LEM.SettingType.Slider,
            default = 0,
            isShown = cooldownNumberEnabled,
            get = function()
                return ns.db.profile.cooldownManager_cooldownTextTracker_offsetX or 0
            end,
            set = function(layoutName, value)
                ns.db.profile.cooldownManager_cooldownTextTracker_offsetX = math.floor((value or 0) + 0.5)
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            minValue = -40,
            maxValue = 40,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
        {
            name = "Number Y Offset",
            parentId = "cdfont",
            kind = LEM.SettingType.Slider,
            default = 0,
            isShown = cooldownNumberEnabled,
            get = function()
                return ns.db.profile.cooldownManager_cooldownTextTracker_offsetY or 0
            end,
            set = function(layoutName, value)
                ns.db.profile.cooldownManager_cooldownTextTracker_offsetY = math.floor((value or 0) + 0.5)
                if ns.TrackerItemViewer then
                    ns.TrackerItemViewer:RefreshStyling()
                end
            end,
            minValue = -40,
            maxValue = 40,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
        {
            kind = LEM.SettingType.Collapsible,
            id = "keybinds",
            name = "Keybinds",
            defaultCollapsed = true,
        },
        {
            name = "Show Keybinds",
            parentId = "keybinds",
            kind = LEM.SettingType.Checkbox,
            default = false,
            get = function()
                return ns.db.profile.cooldownManager_showKeybinds_CMCTracker
            end,
            set = function(layoutName, value)
                ns.db.profile.cooldownManager_showKeybinds_CMCTracker = value
                if ns.Keybinds then
                    ForEachActiveTrackerFrameName(function(name)
                        ns.Keybinds:OnSettingChanged(name)
                    end)
                end
            end,
        },
        {
            name = "Keybind Anchor",
            parentId = "keybinds",
            kind = LEM.SettingType.Dropdown,
            default = "TOPRIGHT",
            isShown = function()
                return ns.db.profile.cooldownManager_showKeybinds_CMCTracker and true or false
            end,
            get = function()
                return ns.db.profile.cooldownManager_keybindAnchor_CMCTracker or "TOPRIGHT"
            end,
            set = function(layoutName, value)
                ns.db.profile.cooldownManager_keybindAnchor_CMCTracker = value
                if ns.Keybinds then
                    ForEachActiveTrackerFrameName(function(name)
                        ns.Keybinds:ApplyKeybindSettings(name)
                    end)
                end
            end,
            values = {
                { text = "Top Left", value = "TOPLEFT" },
                { text = "Top", value = "TOP" },
                { text = "Top Right", value = "TOPRIGHT" },
                { text = "Left", value = "LEFT" },
                { text = "Center", value = "CENTER" },
                { text = "Right", value = "RIGHT" },
                { text = "Bottom Left", value = "BOTTOMLEFT" },
                { text = "Bottom", value = "BOTTOM" },
                { text = "Bottom Right", value = "BOTTOMRIGHT" },
            },
        },
        {
            name = "Keybind Font Size",
            parentId = "keybinds",
            kind = LEM.SettingType.Dropdown,
            default = "10",
            isShown = function()
                return ns.db.profile.cooldownManager_showKeybinds_CMCTracker and true or false
            end,
            get = function()
                return tostring(ns.db.profile.cooldownManager_keybindFontSize_CMCTracker or 10)
            end,
            set = function(layoutName, value)
                local n = tonumber(value)
                ns.db.profile.cooldownManager_keybindFontSize_CMCTracker = n and math.floor(n + 0.5) or 14
                if ns.Keybinds then
                    ForEachActiveTrackerFrameName(function(name)
                        ns.Keybinds:ApplyKeybindSettings(name)
                    end)
                end
            end,
            values = {
                { text = "6", value = "6" },
                { text = "8", value = "8" },
                { text = "10", value = "10" },
                { text = "12", value = "12" },
                { text = "14", value = "14" },
                { text = "16", value = "16" },
                { text = "18", value = "18" },
                { text = "20", value = "20" },
                { text = "22", value = "22" },
                { text = "24", value = "24" },
                { text = "26", value = "26" },
                { text = "28", value = "28" },
                { text = "30", value = "30" },
                { text = "32", value = "32" },
            },
        },
        {
            name = "Keybind X Offset",
            parentId = "keybinds",
            kind = LEM.SettingType.Slider,
            default = -3,
            isShown = function()
                return ns.db.profile.cooldownManager_showKeybinds_CMCTracker and true or false
            end,
            get = function()
                return ns.db.profile.cooldownManager_keybindOffsetX_CMCTracker or -3
            end,
            set = function(layoutName, value)
                local v = math.floor((value or 0) + 0.5)
                ns.db.profile.cooldownManager_keybindOffsetX_CMCTracker = v
                if ns.Keybinds then
                    ForEachActiveTrackerFrameName(function(name)
                        ns.Keybinds:ApplyKeybindSettings(name)
                    end)
                end
            end,
            minValue = -40,
            maxValue = 40,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
        {
            name = "Keybind Y Offset",
            parentId = "keybinds",
            kind = LEM.SettingType.Slider,
            default = -3,
            isShown = function()
                return ns.db.profile.cooldownManager_showKeybinds_CMCTracker and true or false
            end,
            get = function()
                return ns.db.profile.cooldownManager_keybindOffsetY_CMCTracker or -3
            end,
            set = function(layoutName, value)
                local v = math.floor((value or 0) + 0.5)
                ns.db.profile.cooldownManager_keybindOffsetY_CMCTracker = v
                if ns.Keybinds then
                    ForEachActiveTrackerFrameName(function(name)
                        ns.Keybinds:ApplyKeybindSettings(name)
                    end)
                end
            end,
            minValue = -40,
            maxValue = 40,
            valueStep = 1,
            formatter = function(value)
                return string.format("%d", value)
            end,
        },
    }
    for _, s in ipairs(stacksCooldownAndKeybindSettings) do
        tinsert(additionalSettings, s)
    end

    -- Visibility rules row (same control the cooldown viewers use), added last.
    if ns.EditModeViewerSettings and ns.EditModeViewerSettings.BuildVisibilitySetting then
        tinsert(additionalSettings, ns.EditModeViewerSettings:BuildVisibilitySetting(self.frameName))
    end

    WilduUICore.RegisterFrameWithLEM(self.anchor, self.configKey, additionalSettings, OnPositionChanged)

    if ns.db.profile.editMode[configKey].anchoredToTracker1 then
        OnPositionChanged(self.anchor, self.configKey)
    end
    self:RefreshEntries()
end

-- Activates or deactivates a tracker. Deactivated trackers are hidden and removed
-- from Edit Mode's overlay list (LibEQOL has no RemoveFrame, so we toggle the
-- overlay and visibility instead of destroying the frame, allowing cheap re-add).
function TrackerInstance:SetActive(active)
    self.active = active
    if not self.anchor then
        return
    end
    if LEM.SetFrameOverlayToggleEnabled then
        LEM:SetFrameOverlayToggleEnabled(self.anchor, active)
    end
    if active then
        self:RegisterTrackerEvents()
        self.anchor:Show()
        self:RefreshEntries()
    else
        self:UnregisterTrackerEvents()
        self.anchor:Hide()
    end
end

-- Pool of tracker instances, indexed 1..N. Instances are created lazily as the
-- active count grows and reused (deactivated, not destroyed) when it shrinks.
local trackers = {}
local spellCastEventFrame = nil

local function GetOrCreateTrackerInstance(index)
    if not trackers[index] then
        trackers[index] = TrackerInstance:New("tracker" .. index, "CMCTracker" .. index, function(owned)
            return ItemsData:GetTrackerEntries(index, owned)
        end)
    end
    return trackers[index]
end

-- Creates/activates frames for trackers 1..count and deactivates any beyond it.
-- Safe to call repeatedly; TrackerInstance:Create() is idempotent.
function ItemViewer:EnsureTrackers()
    if not ns.db.profile.tracker_enabled then
        return
    end
    local count = GetTrackerCount()
    for i = 1, count do
        local tracker = GetOrCreateTrackerInstance(i)
        tracker:Create()
        tracker:SetActive(true)
    end
    -- Deactivate any previously-created instances above the active count.
    for i = count + 1, #trackers do
        if trackers[i] then
            trackers[i]:SetActive(false)
        end
    end
end

-- Wires up visibility drivers and keybind text for the current tracker set after
-- the count changes at runtime, so a freshly added tracker works without a reload.
local function RefreshTrackerIntegrations()
    if ns.CMCVisibility and ns.CMCVisibility.Initialize then
        ns.CMCVisibility:Initialize()
    end
    if ns.Keybinds and ns.Keybinds.UpdateAllKeybinds then
        ns.Keybinds:UpdateAllKeybinds()
    end
end

-- Keeps the tracker count "magical": there is always exactly one empty trailing
-- tracker to drop new items into. Grows the count the moment the last tracker gains
-- an item, and trims any surplus trailing empties back down to a single spare.
-- Clamped to [1, MAX_TRACKERS]. Returns true if the count changed.
function ItemViewer:ReconcileTrackerCount()
    if not ns.db or not ns.db.profile then
        return false
    end
    local maxTrackers = ns.CONSTANTS.MAX_TRACKERS or 10

    local maxUsed = 0
    for i = 1, maxTrackers do
        if not ItemsData:IsTrackerEmpty(i) then
            maxUsed = i
        end
    end

    -- One spare empty tracker past the last used one, capped at the maximum.
    local desired = math.min(math.max(maxUsed + 1, 1), maxTrackers)
    if desired == GetTrackerCount() then
        return false
    end

    ns.db.profile.tracker_count = desired
    self:EnsureTrackers()
    RefreshTrackerIntegrations()
    return true
end

function ItemViewer:GetTrackerCount()
    return GetTrackerCount()
end

function ItemViewer:RefreshItemViewerFrames()
    for _, tracker in ipairs(trackers) do
        tracker:RefreshEntries()
    end
end

function ItemViewer:RefreshStyling()
    for _, tracker in ipairs(trackers) do
        tracker:RefreshStyling()
    end
end

function ItemViewer:Initialize()
    if not ns.db.profile.tracker_enabled then
        return
    end

    ns.TrackerDB.InitializeDB()

    if not spellCastEventFrame then
        spellCastEventFrame = CreateFrame("Frame")
        spellCastEventFrame:SetScript("OnEvent", function(_, _event, unitTarget, _castGUID, spellID)
            if unitTarget ~= "player" or not spellID then
                return
            end

            local matched = false
            if ItemVisuals and ItemVisuals.MarkSpellCastActive and ItemVisuals:MarkSpellCastActive(spellID) then
                matched = true
            end
            if ItemVisuals and ItemVisuals.MarkItemCastActive and ItemVisuals:MarkItemCastActive(spellID) then
                matched = true
            end

            if matched then
                ItemViewer:RefreshItemViewerFrames()
            end
        end)
    end
    -- Registered every Initialize (not just on first creation) so re-enabling the
    -- feature after a HideAll() — which unregisters it — wires the watcher back up.
    spellCastEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

    self:EnsureTrackers()
    self:ReconcileTrackerCount()
end

-- Turns the whole custom tracker system off without a reload: stops the spell-cast
-- watcher, then deactivates every tracker — which hides its frame, unregisters its
-- refresh events (so nothing re-shows it), and disables its Edit Mode overlay so it
-- can't be selected or forced visible while disabled. LibEQOL has no
-- RemoveFrame/destroy, so the frames are kept (hidden) for cheap reuse on re-enable.
function ItemViewer:HideAll()
    if spellCastEventFrame then
        spellCastEventFrame:UnregisterAllEvents()
    end
    for _, tracker in ipairs(trackers) do
        tracker:SetActive(false)
    end
end

function ItemViewer:ShowAll()
    for _, tracker in ipairs(trackers) do
        if tracker.anchor and tracker.active then
            tracker:RefreshEntries()
        end
    end
end
