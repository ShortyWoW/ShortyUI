local _, ns = ...

ns.db = ns.db or {}
ns.db.profile = ns.db.profile or {}
local CooldownManager = {}
ns.CooldownManager = CooldownManager

local CMC_DEBUG = false

local CMC_DEBUG_VAR = {}

local PrintDebug = function(...)
    if CMC_DEBUG then
        print("[CMC]", ...)
    end
end

-- Architecture:
-- LayoutEngine: pure layout computations (no frame access)
-- ViewerAdapters: WoW Frame interaction per viewer type

local LayoutEngine = {}
local ViewerAdapters = {}

local viewers = {
    BuffIconCooldownViewer = _G["BuffIconCooldownViewer"],
    BuffBarCooldownViewer = _G["BuffBarCooldownViewer"],
    EssentialCooldownViewer = _G["EssentialCooldownViewer"],
    UtilityCooldownViewer = _G["UtilityCooldownViewer"],
}

local castrate
castrate = function(value, level)
    level = level or 0
    if level > 4 then
        return "Too deep"
    end
    if type(value) == "table" then
        local copy = {}
        for k, v in pairs(value) do
            copy[k] = castrate(v, level + 1)
        end
        return copy
    elseif type(value) ~= "function" then
        return value
    end
end

function _G.debugCMCdata()
    for k, v in pairs(viewers) do
        print("Debugging viewer:", k, "->", v)
        if v then
            local children = v:GetItemFrames()
            local castrated = castrate(children)
            CMC_DEBUG_VAR[k] = {
                frame = castrate(v),
                childCount = #children,
                children = castrated,
                firstChild = castrated[1],
                secondChild = castrated[2],
            }
        end
    end
end

function LayoutEngine.CenteredRowXOffsets(count, itemWidth, padding, directionModifier, iconLimit)
    if not count or count <= 0 then
        return {}
    end
    local dir = directionModifier or 1
    local iconsMissing = iconLimit - count
    local startX = ((itemWidth + padding) * iconsMissing / 2) * dir
    local offsets = {}
    for i = 1, count do
        offsets[i] = startX + (i - 1) * (itemWidth + padding) * dir
    end

    return offsets
end

function LayoutEngine.CenteredColYOffsets(count, itemHeight, padding, directionModifier, iconLimit)
    if not count or count <= 0 then
        return {}
    end
    local dir = directionModifier or 1
    local iconsMissing = iconLimit - count
    local startY = -((itemHeight + padding) * iconsMissing / 2) * dir
    local offsets = {}
    for i = 1, count do
        offsets[i] = startY - (i - 1) * (itemHeight + padding) * dir
    end
    return offsets
end

function LayoutEngine.StartRowXOffsets(count, itemWidth, padding, directionModifier)
    if not count or count <= 0 then
        return {}
    end
    local dir = directionModifier or 1
    local offsets = {}
    for i = 1, count do
        offsets[i] = ((i - 1) * (itemWidth + padding) * dir)
    end
    return offsets
end

function LayoutEngine.EndRowXOffsets(count, itemWidth, padding, directionModifier)
    if not count or count <= 0 then
        return {}
    end
    local dir = directionModifier or 1
    local offsets = {}
    for i = 1, count do
        offsets[i] = (-((i - 1) * (itemWidth + padding)) * dir)
    end
    return offsets
end

function LayoutEngine.StartColYOffsets(count, itemHeight, padding, directionModifier)
    if not count or count <= 0 then
        return {}
    end
    local dir = directionModifier or 1
    local offsets = {}
    for i = 1, count do
        offsets[i] = (-((i - 1) * (itemHeight + padding)) * dir)
    end
    return offsets
end

function LayoutEngine.EndColYOffsets(count, itemHeight, padding, directionModifier)
    if not count or count <= 0 then
        return {}
    end
    local dir = directionModifier or 1
    local offsets = {}
    for i = 1, count do
        offsets[i] = ((i - 1) * (itemHeight + padding) * dir)
    end
    return offsets
end

function LayoutEngine.BuildRows(iconLimit, children)
    local rows = {}
    local limit = iconLimit or 0
    if limit <= 0 then
        return rows
    end
    for i = 1, #children do
        local rowIndex = math.floor((i - 1) / limit) + 1
        rows[rowIndex] = rows[rowIndex] or {}
        rows[rowIndex][#rows[rowIndex] + 1] = children[i]
    end
    return rows
end

-- ViewerAdapters: BuffIcon/BuffBar collection + hooks
function ViewerAdapters.GetBuffIconFrames()
    if not BuffIconCooldownViewer then
        return {}
    end
    local visible = {}
    local children = BuffIconCooldownViewer:GetItemFrames()
    local total = 0
    for _, child in ipairs(children) do
        if child and (child.icon or child.Icon) and child.layoutIndex ~= nil then
            total = total + 1
            if child:IsShown() then
                visible[#visible + 1] = child
            end
            if not ns.API:GetIsAffected(child, "cooldownManagerHooked") then
                ns.API:SetAffected(child, "cooldownManagerHooked")
                hooksecurefunc(child, "OnActiveStateChanged", ViewerAdapters.UpdateBuffIcons)
                hooksecurefunc(child, "OnUnitAuraAddedEvent", ViewerAdapters.UpdateBuffIcons)
                hooksecurefunc(child, "OnUnitAuraRemovedEvent", ViewerAdapters.UpdateBuffIcons)
            end
        end
    end

    table.sort(visible, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)
    return visible, total
end

function ViewerAdapters.GetBuffBarFrames(includeInactive)
    if not BuffBarCooldownViewer then
        return {}
    end
    local frames = {}
    if BuffBarCooldownViewer.GetItemFrames then
        local ok, items = pcall(BuffBarCooldownViewer.GetItemFrames, BuffBarCooldownViewer)
        if ok and items then
            frames = items
        end
    end
    if #frames == 0 then
        local okc, children = pcall(BuffBarCooldownViewer.GetChildren, BuffBarCooldownViewer)
        if okc and children then
            for _, child in ipairs({ children }) do
                if child and child:IsObjectType("Frame") then
                    frames[#frames + 1] = child
                end
            end
        end
    end

    local active = {}
    for _, frame in ipairs(frames) do
        if includeInactive or (frame:IsShown() and frame:IsVisible()) then
            active[#active + 1] = frame
        end
        if
            not ns.API:GetIsAffected(frame, "cooldownManagerHooked")
            and (frame.icon or frame.Icon or frame.bar or frame.Bar)
        then
            ns.API:SetAffected(frame, "cooldownManagerHooked")
            hooksecurefunc(frame, "OnActiveStateChanged", ViewerAdapters.UpdateBuffBars)
            hooksecurefunc(frame, "OnUnitAuraAddedEvent", ViewerAdapters.UpdateBuffBars)
            hooksecurefunc(frame, "OnUnitAuraRemovedEvent", ViewerAdapters.UpdateBuffBars)
        end
    end
    table.sort(active, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)
    return active
end

function ViewerAdapters.UpdateBuffIcons()
    if
        not ns.Runtime:IsReady(BuffIconCooldownViewer)
        or ns.db.profile.cooldownManager_alignBuffIcons_growFromDirection == "Disable"
    then
        return
    end

    local icons, total = ViewerAdapters.GetBuffIconFrames()
    local count = #icons
    if count == 0 then
        return
    end

    local refIcon = icons[1]
    local iconWidth = refIcon:GetWidth()
    local iconHeight = refIcon:GetHeight()
    if not iconWidth or iconWidth == 0 or not iconHeight or iconHeight == 0 then
        return
    end

    local isHorizontal = BuffIconCooldownViewer.isHorizontal ~= false
    local iconDirection = BuffIconCooldownViewer.iconDirection == 1 and "NORMAL" or "REVERSED"

    local alignment = ns.db.profile.cooldownManager_alignBuffIcons_growFromDirection or "CENTER"
    local padding = isHorizontal and BuffIconCooldownViewer.childXPadding or BuffIconCooldownViewer.childYPadding

    if isHorizontal then
        local offsets
        local anchor, relativePoint
        local iconDirectionModifier = iconDirection == "NORMAL" and 1 or -1
        if alignment == "START" then
            offsets = LayoutEngine.StartRowXOffsets(count, iconWidth, padding, iconDirectionModifier)
            anchor = iconDirection == "NORMAL" and "TOPLEFT" or "TOPRIGHT"
            relativePoint = iconDirection == "NORMAL" and "TOPLEFT" or "TOPRIGHT"
        elseif alignment == "END" then
            offsets = LayoutEngine.EndRowXOffsets(count, iconWidth, padding, iconDirectionModifier)
            anchor = iconDirection == "NORMAL" and "TOPRIGHT" or "TOPLEFT"
            relativePoint = iconDirection == "NORMAL" and "TOPRIGHT" or "TOPLEFT"
        else -- CENTER
            offsets = LayoutEngine.CenteredRowXOffsets(count, iconWidth, padding, iconDirectionModifier, total)
            anchor = iconDirection == "NORMAL" and "TOPLEFT" or "TOPRIGHT"
            relativePoint = iconDirection == "NORMAL" and "TOPLEFT" or "TOPRIGHT"
        end

        for i, icon in ipairs(icons) do
            local x = offsets[i] or 0
            icon:ClearAllPoints()
            icon:SetPoint(anchor, BuffIconCooldownViewer, relativePoint, x, 0)
        end
    else
        -- Vertical layout
        local offsets
        local anchor, relativePoint
        local iconDirectionModifier = iconDirection == "NORMAL" and -1 or 1
        if alignment == "START" then
            offsets = LayoutEngine.StartColYOffsets(count, iconHeight, padding, iconDirectionModifier)
            anchor = iconDirection == "NORMAL" and "BOTTOMLEFT" or "TOPLEFT"
            relativePoint = iconDirection == "NORMAL" and "BOTTOMLEFT" or "TOPLEFT"
        elseif alignment == "END" then
            offsets = LayoutEngine.EndColYOffsets(count, iconHeight, padding, iconDirectionModifier)
            anchor = iconDirection == "NORMAL" and "TOPLEFT" or "BOTTOMLEFT"
            relativePoint = iconDirection == "NORMAL" and "TOPLEFT" or "BOTTOMLEFT"
        else -- CENTER
            offsets = LayoutEngine.CenteredColYOffsets(count, iconHeight, padding, iconDirectionModifier, total)
            anchor = iconDirection == "NORMAL" and "BOTTOMLEFT" or "TOPLEFT"
            relativePoint = iconDirection == "NORMAL" and "BOTTOMLEFT" or "TOPLEFT"
        end

        for i, icon in ipairs(icons) do
            local y = offsets[i] or 0
            icon:ClearAllPoints()
            icon:SetPoint(anchor, BuffIconCooldownViewer, relativePoint, 0, y)
        end
    end
end

function ViewerAdapters.UpdateBuffBars()
    if not ns.Runtime:IsReady(BuffBarCooldownViewer) then
        return
    end
    local iconMode = ns.BuffBarIconMode.IsEnabled()

    ns.BuffBarIconMode.RefreshAll(ViewerAdapters.GetBuffBarFrames(true))

    local bars = ViewerAdapters.GetBuffBarFrames()
    local count = #bars
    if count == 0 then
        return
    end

    local growSetting = ns.db.profile.cooldownManager_alignBuffBars_growFromDirection

    if iconMode then
        local scale = BuffBarCooldownViewer.iconScale
        if not InCombatLockdown() then
            BuffBarCooldownViewer:SetSize(35 * scale, 35 * scale)
        end
    else
        if growSetting == "Disable" then
            return
        end

        -- Layout() internally calls SetSize on the protected EditMode viewer,
        -- which is blocked during combat lockdown. Guard like an explicit resize.
        if not InCombatLockdown() then
            BuffBarCooldownViewer:Layout()
        end
    end
    local horizontalIcons = iconMode and ns.BuffBarIconMode.IsHorizontal()

    if horizontalIcons then
        local refBar = bars[1]
        local barWidth = refBar and refBar:GetWidth()
        local spacing = BuffBarCooldownViewer.childXPadding or BuffBarCooldownViewer.childYPadding or 0
        if not barWidth or barWidth == 0 then
            return
        end

        local totalWidth = (count * barWidth) + (math.max(count - 1, 0) * spacing)
        local startX = -(totalWidth / 2) + (barWidth / 2)
        local anchor = "BOTTOM"

        for index, bar in ipairs(bars) do
            local x = startX + ((index - 1) * (barWidth + spacing))
            bar:ClearAllPoints()
            bar:SetPoint(anchor, BuffBarCooldownViewer, anchor, x, 0)
        end

        return
    end

    if growSetting == "Disable" then
        return
    end

    local refBar = bars[1]
    local barHeight = refBar and refBar:GetHeight()
    local spacing = BuffBarCooldownViewer.childYPadding or 0
    if not barHeight or barHeight == 0 then
        return
    end

    local growFromBottom = (growSetting == "BOTTOM") or (growSetting == "ICONS_VERTICAL")

    for index, bar in ipairs(bars) do
        local offsetIndex = index - 1
        local y = growFromBottom and offsetIndex * (barHeight + spacing) or -offsetIndex * (barHeight + spacing)

        bar:ClearAllPoints()
        if growFromBottom then
            bar:SetPoint("BOTTOM", BuffBarCooldownViewer, "BOTTOM", 0, y)
        else
            bar:SetPoint("TOP", BuffBarCooldownViewer, "TOP", 0, y)
        end
    end
end

local _dimCurve = nil
local _dimCurveOpacity = nil

local weirdSpellsWithoutGCD = {
    -- info.spellID == 198793 or info.spellID == 195072 or info.spellID == 232893
    [198793] = true, -- Vengeful Retreat
    [195072] = true, -- Fel Rush
    [232893] = true, -- Felblade
    [102401] = true, -- Wild Charge
    [106839] = true, -- Skull Bash
}
local function GetDimCurveWeirdSpells(toDimOpacity)
    if _dimCurve and _dimCurveOpacity == toDimOpacity then
        return _dimCurve
    end
    _dimCurve = C_CurveUtil.CreateCurve()
    _dimCurve:AddPoint(0.0, toDimOpacity)
    _dimCurve:AddPoint(1.0000, toDimOpacity)
    _dimCurve:AddPoint(1.001, 1)
    _dimCurveOpacity = toDimOpacity
    return _dimCurve
end

function ViewerAdapters.UpdateUtilityDimming()
    local viewer = UtilityCooldownViewer
    if not viewer then
        return
    end
    local toDim = ns.db.profile.cooldownManager_utility_dimWhenNotOnCD
    if not toDim then
        if ns.API:GetIsAffected(viewer, "dimmed") then
            ns.API:UnsetAffected(viewer, "dimmed")
            local children = viewer:GetItemFrames()
            for _, child in ipairs(children) do
                if child and child.Icon then
                    child:SetAlpha(1)
                end
            end
        end
        return
    end
    local shouldForceShow = ns.Runtime and (ns.Runtime.isInEditMode or ns.Runtime.hasSettingsOpened)

    local toDimOpacity = ns.db.profile.cooldownManager_utility_dimOpacity or 0.3

    local children = viewer:GetItemFrames()
    for _, child in ipairs(children) do
        if child and child:IsShown() and child.Icon then
            if shouldForceShow then
                child:SetAlpha(1)
            else
                if child.cooldownID then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(child.cooldownID)
                    local spellID = info.overrideSpellID or info.spellID
                    local spellCD = C_Spell.GetSpellCooldown(spellID)
                    if not spellCD.isOnGCD then
                        local spellCharges = C_Spell.GetSpellCharges(spellID)
                        local hasCharges = spellCharges and spellCharges.maxCharges > 1
                        if hasCharges and spellCharges.isActive then
                            child:SetAlpha(1)
                        elseif spellCD.isActive then
                            if weirdSpellsWithoutGCD[info.spellID] then
                                local cd = C_Spell.GetSpellCooldownDuration(spellID)

                                local curve = GetDimCurveWeirdSpells(toDimOpacity)

                                local EvaluateDuration = cd:EvaluateRemainingDuration(curve)
                                child:SetAlpha(EvaluateDuration)
                            else
                                child:SetAlpha(1)
                            end
                        else
                            child:SetAlpha(toDimOpacity)
                        end
                    else
                        child:SetAlpha(toDimOpacity)
                    end
                end
            end
        end
    end
    ns.API:SetAffected(viewer, "dimmed")
end

-- SPELL_UPDATE_COOLDOWN can fire many times per frame (every cooldown/charge
-- change), and each UpdateUtilityDimming pass walks every utility child and
-- allocates Blizzard cooldown/charge tables per child. Coalesce bursts into a
-- single pass on the next frame so the work runs at most once per frame.
local utilityDimmingPending = false
local function RunUtilityDimming()
    utilityDimmingPending = false
    ViewerAdapters.UpdateUtilityDimming()
end
function ViewerAdapters.RequestUtilityDimming()
    if utilityDimmingPending then
        return
    end
    utilityDimmingPending = true
    C_Timer.After(0, RunUtilityDimming)
end

function ViewerAdapters.CollectViewerChildren(viewer)
    local viewerName = viewer:GetName()

    -- Direct insert by layoutIndex to avoid sorting
    local indexed = {}
    local children = viewer:GetItemFrames()
    for _x, child in ipairs(children) do
        local li = child.layoutIndex
        if child and child:IsShown() and child.Icon and li then
            if indexed[li] then
                PrintDebug(
                    "|cffff0000[CooldownManager]|r Warning: Duplicate layoutIndex " .. li .. " in " .. viewerName
                )
            end
            indexed[li] = child
        end
    end

    return indexed
end

local function PositionRowHorizontal(viewer, row, yOffset, w, padding, iconDirectionModifier, rowAnchor, iconLimit)
    local count = #row
    local xOffsets = LayoutEngine.CenteredRowXOffsets(count, w, padding, iconDirectionModifier, iconLimit)

    for i, icon in ipairs(row) do
        local x = xOffsets[i] or 0
        local stillNeedToSet = true

        if icon.GetPoint then
            local point, _, relativePoint, offsetX, offsetY = icon:GetPoint()
            if offsetX ~= nil and offsetY ~= nil then
                local xDiff = math.abs(x - offsetX)
                local yDiff = math.abs(yOffset - offsetY)
                if point == rowAnchor and relativePoint == rowAnchor and xDiff < 1 and yDiff < 1 then
                    stillNeedToSet = false
                    -- No need to reposition
                else
                    if xDiff <= 1 then
                        x = offsetX
                    end
                end
            end
        end
        if stillNeedToSet then
            icon:ClearAllPoints()
            icon:SetPoint(rowAnchor, viewer, rowAnchor, x, yOffset)
        end
    end
end

local function PositionRowVertical(viewer, row, xOffset, h, padding, iconDirectionModifier, colAnchor, iconLimit)
    local count = #row
    local yOffsets = LayoutEngine.CenteredColYOffsets(count, h, padding, iconDirectionModifier, iconLimit)

    for i, icon in ipairs(row) do
        local y = yOffsets[i] or 0
        local stillNeedToSet = true

        if icon.GetPoint then
            local point, _, relativePoint, offsetX, offsetY = icon:GetPoint()
            if offsetX ~= nil and offsetY ~= nil then
                local xDiff = math.abs(xOffset - offsetX)
                local yDiff = math.abs(y - offsetY)
                if point == colAnchor and relativePoint == colAnchor and xDiff < 1 and yDiff < 1 then
                    stillNeedToSet = false
                    -- No need to reposition
                else
                    if yDiff <= 1 then
                        y = offsetY
                    end
                end
            end
        end
        if stillNeedToSet then
            icon:ClearAllPoints()
            icon:SetPoint(colAnchor, viewer, colAnchor, xOffset, y)
        end
    end
end

function ViewerAdapters.UpdateViewerSizeIfChanged(viewer)
    local currentWidth = viewer:GetWidth()
    local currentHeight = viewer:GetHeight()

    local children = ViewerAdapters.CollectViewerChildren(viewer)
    local top, right, bottom, left = 0, 0, 999999, 999999
    for _, child in ipairs(children) do
        local scale = child:GetEffectiveScale() / viewer:GetEffectiveScale()
        local cTop = child:GetTop() or 0
        local cRight = child:GetRight() or 0
        local cBottom = child:GetBottom() or 0
        local cLeft = child:GetLeft() or 0
        cTop = cTop * scale
        cRight = cRight * scale
        cBottom = cBottom * scale
        cLeft = cLeft * scale
        if cTop > top then
            top = cTop
        end
        if cRight > right then
            right = cRight
        end
        if cBottom < bottom then
            bottom = cBottom
        end
        if cLeft < left then
            left = cLeft
        end
    end

    local targetWidth = (right - left)
    local targetHeight = (top - bottom)

    if math.abs(currentWidth - targetWidth) >= 1 or math.abs(currentHeight - targetHeight) >= 1 then
        viewer:SetWidth(targetWidth)
        viewer:SetHeight(targetHeight)
        viewer:SetSize(targetWidth, targetHeight)
    end
end

function ViewerAdapters.UpdateEssential()
    ViewerAdapters.UpdateCDViewer(
        EssentialCooldownViewer,
        ns.db.profile.cooldownManager_centerEssential_growFromDirection
    )
end

function ViewerAdapters.UpdateUtility()
    ViewerAdapters.UpdateCDViewer(UtilityCooldownViewer, ns.db.profile.cooldownManager_centerUtility_growFromDirection)
    ViewerAdapters.RequestUtilityDimming()
end

function ViewerAdapters.UpdateCDViewer(viewer, fromDirection)
    if not ns.Runtime:IsReady(viewer) then
        return
    end

    local viewerName = viewer:GetName()

    local isHorizontal = viewer.isHorizontal ~= false
    local iconDirection = viewer.iconDirection == 1 and "NORMAL" or "REVERSED"
    local iconLimit = viewer.iconLimit or 0
    if iconLimit <= 0 then
        return
    end

    local children = ViewerAdapters.CollectViewerChildren(viewer)
    if fromDirection == "Disable" then
        if ns.API:GetIsAffected(viewer, "aligned") and viewer.Layout then
            ns.API:UnsetAffected(viewer, "aligned")
            -- Layout() internally calls SetSize on the protected EditMode viewer,
            -- which is blocked during combat lockdown. Guard like an explicit resize.
            if not InCombatLockdown() then
                viewer:Layout()
            end
        end
        ViewerAdapters.UpdateViewerSizeIfChanged(viewer)
        return
    end
    if #children == 0 then
        return
    end

    local first = children[1]
    if not first then
        return
    end
    local w, h = first:GetWidth(), first:GetHeight()
    if not w or w == 0 or not h or h == 0 then
        return
    end

    local padding = isHorizontal and viewer.childXPadding or viewer.childYPadding
    if
        viewerName == "UtilityCooldownViewer"
        and ns.db.profile.cooldownManager_limitUtilitySizeToEssential
        and isHorizontal
    then
        local essentialViewer = viewers["EssentialCooldownViewer"]
        if essentialViewer then
            local eWidth = essentialViewer:GetWidth()
            if eWidth and eWidth > 0 then
                local iconActualWidth = (w + padding) * viewer.iconScale
                local maxIcons = math.floor((eWidth + (padding * viewer.iconScale)) / iconActualWidth)
                if maxIcons > 0 then
                    iconLimit = math.max(math.min(iconLimit, maxIcons), math.min(iconLimit, 6))
                end
            end
        end
    end

    local rows = LayoutEngine.BuildRows(iconLimit, children)
    if #rows == 0 then
        return
    end
    local maxIcons = math.min(iconLimit, #children)

    if isHorizontal then
        local rowOffsetModifier = fromDirection == "BOTTOM" and 1 or -1
        local iconDirectionModifier = iconDirection == "NORMAL" and 1 or -1
        local fromAnchor1 = fromDirection == "BOTTOM" and "BOTTOM" or "TOP"
        local fromAnchor2 = iconDirection == "NORMAL" and "LEFT" or "RIGHT"
        local rowAnchor = fromAnchor1 .. fromAnchor2

        local cumulativeOffset = 0
        for iRow, row in ipairs(rows) do
            local currentRowHeight = h

            local yOffset = cumulativeOffset * rowOffsetModifier
            PositionRowHorizontal(viewer, row, yOffset, w, padding, iconDirectionModifier, rowAnchor, maxIcons)

            cumulativeOffset = cumulativeOffset + currentRowHeight + padding
        end
    else
        local rowOffsetModifier = fromDirection == "BOTTOM" and -1 or 1
        local iconDirectionModifier = iconDirection == "NORMAL" and -1 or 1
        local fromAnchor1 = fromDirection == "BOTTOM" and "RIGHT" or "LEFT"
        local fromAnchor2 = iconDirection == "NORMAL" and "BOTTOM" or "TOP"
        local colAnchor = fromAnchor2 .. fromAnchor1
        local cumulativeOffset = 0
        for iRow, row in ipairs(rows) do
            local currentColWidth = w

            local xOffset = cumulativeOffset * rowOffsetModifier
            PositionRowVertical(viewer, row, xOffset, h, padding, iconDirectionModifier, colAnchor, maxIcons)

            cumulativeOffset = cumulativeOffset + currentColWidth + padding
        end
    end
    ns.API:SetAffected(viewer, "aligned")
    ViewerAdapters.UpdateViewerSizeIfChanged(viewer)
end

function CooldownManager.ForceRefresh(parts)
    parts = parts or { icons = true, bars = true, essential = true, utility = true }
    if parts.icons then
        ViewerAdapters.UpdateBuffIcons()
    end
    if parts.bars then
        ViewerAdapters.UpdateBuffBars()
    end
    if parts.essential then
        ViewerAdapters.UpdateEssential()
    end
    if parts.utility then
        ViewerAdapters.UpdateUtility()
    end

    -- debugCMCdata()
end

function CooldownManager.ForceRefreshAll()
    CooldownManager.ForceRefresh({ icons = true, bars = true, essential = true, utility = true })
end

function CooldownManager.UpdateUtilityDimming()
    ViewerAdapters.RequestUtilityDimming()
end

function CooldownManager.RestoreUtilityAlpha()
    local viewer = UtilityCooldownViewer
    if not viewer then
        return
    end
    local children = viewer:GetItemFrames()
    for _, child in ipairs(children) do
        if child and child.Icon then
            child:SetAlpha(1)
        end
    end
end

function CooldownManager.Initialize()
    CooldownManager.ForceRefreshAll()
end
