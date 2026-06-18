local _, ns = ...
local Affected = ns.API.Affected

local TrackerAssignmentPanel = {}
ns.TrackerAssignmentPanel = TrackerAssignmentPanel

local DB = ns.TrackerDB
local ItemsData = ns.TrackerItemsData
local ItemVisuals = ns.TrackerItemVisuals
local ItemViewer = ns.TrackerItemViewer

local ITEM_STATE_HIDDEN = ItemsData.ITEM_STATE_HIDDEN
local ENTRY_KIND_WILDCARD_SLOTS = ItemsData.ENTRY_KIND_WILDCARD_SLOTS or "wildcardSlots"

local reorderSourceItem = nil
local reorderTarget = nil
local reorderTargetItem = nil
local reorderOffset = 0
local reorderEatNextGlobalMouseUp = nil
local reorderMarker = nil
local reorderCursor = nil
local reorderCursorFollow = false

-- Asked before enabling the custom tracker from the Cooldown Settings tab. Enables
-- live (no reload); the `data` argument is a continuation run on confirm so the
-- tracker tab only opens once the user actually says yes.
StaticPopupDialogs["CMC_ENABLE_TRACKER"] = {
    text = "Custom Trackers are disabled. Enable them now?",
    button1 = _G.YES,
    button2 = _G.NO,
    OnAccept = function(_, data)
        if not ns.db or not ns.db.profile then
            return
        end
        ns.db.profile.tracker_enabled = true
        if ns.TrackerItemViewer then
            ns.TrackerItemViewer:Initialize()
            ns.TrackerItemViewer:ShowAll()
        end
        if type(data) == "function" then
            data()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function IsCustomActiveConfigKind(kind)
    return kind == "spell" or kind == "item"
end

local function IsCustomActiveMenuSupportedKind(kind)
    return IsCustomActiveConfigKind(kind) or kind == ENTRY_KIND_WILDCARD_SLOTS
end

local function ResolveCustomActiveTarget(kind, id)
    if kind == ENTRY_KIND_WILDCARD_SLOTS then
        local wildcardItemID = ItemsData.GetWildcardSlotItemID and ItemsData:GetWildcardSlotItemID(id) or nil
        if wildcardItemID then
            return "item", wildcardItemID
        end
        return nil, nil
    end

    if IsCustomActiveConfigKind(kind) and id then
        return kind, id
    end

    return nil, nil
end

local function FormatCustomActiveValue(value)
    local numeric = tonumber(value) or 0
    if math.abs(numeric - math.floor(numeric)) < 0.000001 then
        return tostring(math.floor(numeric))
    end
    return string.format("%g", numeric)
end

local function ParseCustomActiveInput(text)
    local trimmed = strtrim(text or "")
    if trimmed == "" then
        return nil
    end

    local value = tonumber(trimmed)
    if not value then
        return nil
    end
    if value < 0 then
        return nil
    end

    return value
end

local function SetCustomActiveAcceptEnabled(dialog, enabled)
    if not dialog or not dialog.GetName then
        return
    end
    local acceptButton = _G[dialog:GetName() .. "Button1"]
    if acceptButton and acceptButton.SetEnabled then
        acceptButton:SetEnabled(enabled == true)
    end
end

local function ValidateCustomActivePopup(dialog)
    if not dialog then
        return nil
    end
    local editBox = dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
    if not editBox then
        return nil
    end
    local value = ParseCustomActiveInput(editBox:GetText())
    SetCustomActiveAcceptEnabled(dialog, value ~= nil)
    return value
end

-- Manual custom-active-time popup. Only surfaced for entries we have no auto
-- duration data for (see the context menu gate below).
StaticPopupDialogs["CMC_SET_CUSTOM_ACTIVE"] = {
    text = "Set custom active time (seconds).\nCurrent value: 0",
    button1 = _G.ACCEPT,
    button2 = _G.CANCEL,
    hasEditBox = true,
    maxLetters = 32,
    autoCompleteParams = nil,
    OnShow = function(self)
        local data = self.data
        if not data or not IsCustomActiveConfigKind(data.kind) or not data.id then
            self:Hide()
            return
        end

        local currentValue = DB.GetCustomActiveDuration(data.kind, data.id) or 0
        local textWidget = self.text or _G[self:GetName() .. "Text"]
        if textWidget then
            textWidget:SetText(
                "Set custom active time (seconds).\nCurrent value: " .. FormatCustomActiveValue(currentValue)
            )
        end

        local editBox = self.editBox or (self.GetEditBox and self:GetEditBox())
        if editBox then
            editBox:SetText(FormatCustomActiveValue(currentValue))
            editBox:HighlightText()
            editBox:SetFocus()
        end

        ValidateCustomActivePopup(self)
    end,
    OnAccept = function(self)
        local data = self.data
        if not data or not IsCustomActiveConfigKind(data.kind) or not data.id then
            return
        end

        local value = ValidateCustomActivePopup(self)
        if value == nil then
            ns.Addon:Print("Custom active value must be a non-negative number.")
            return
        end

        DB.SetCustomActiveDuration(data.kind, data.id, value)
        TrackerAssignmentPanel:RefreshMiscPanel()
        ItemViewer:RefreshItemViewerFrames()
    end,
    EditBoxOnTextChanged = function(self)
        ValidateCustomActivePopup(self:GetParent())
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        if ValidateCustomActivePopup(popup) ~= nil then
            StaticPopup_OnClick(popup, 1)
        else
            ns.Addon:Print("Custom active value must be a non-negative number.")
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function IsTabButton(child)
    if not child then
        return false
    end
    if Affected(child).trackerIsTabButton then
        return true
    end
    local name = child:GetName()
    return name and name:find("Tab") ~= nil
end

function TrackerAssignmentPanel:HideMiscPanel(settingsFrame)
    if Affected(settingsFrame).trackerMiscPanel then
        Affected(settingsFrame).trackerMiscPanel:Hide()
    end

    local hidden = Affected(settingsFrame).trackerHiddenChildren
    if hidden then
        for _, child in ipairs(hidden) do
            if child and not child:IsShown() then
                child:Show()
            end
        end
        Affected(settingsFrame).trackerHiddenChildren = nil
    end
end

-- Called when the custom tracker is turned off. If the Cooldown Settings window is
-- currently sitting on the (now-disabled) tracker tab, drop the panel and switch
-- back to the first tab so the user isn't stranded on an empty/disabled tab.
function TrackerAssignmentPanel:OnTrackerDisabled()
    local settingsFrame = _G["CooldownViewerSettings"]
    if not settingsFrame then
        return
    end
    local miscPanel = Affected(settingsFrame).trackerMiscPanel
    if not miscPanel or not miscPanel:IsShown() then
        return
    end
    -- SetDisplayMode("spells") restores the first tab; the hook on it also clears
    -- the tab checked states and hides the tracker panel.
    if settingsFrame.SetDisplayMode then
        settingsFrame:SetDisplayMode("spells")
    else
        self:HideMiscPanel(settingsFrame)
    end
end

local function GetMiscPanelFrame()
    local settings = _G["CooldownViewerSettings"]
    return settings and Affected(settings).trackerMiscPanel or nil
end

local function GetEntryKindAndID(button)
    if not button then
        return nil, nil
    end
    return Affected(button).trackerEntryKind, Affected(button).trackerEntryId
end

local function SetButtonEntry(button, kind, id)
    if not button then
        return
    end
    Affected(button).trackerEntryKind = kind
    Affected(button).trackerEntryId = id
    if kind == "item" then
        button.itemID = id
        button.spellID = nil
    elseif kind == "spell" then
        button.itemID = nil
        button.spellID = id
    else
        button.itemID = nil
        button.spellID = nil
    end
end

local function SetWildcardGlow(button, kind)
    if not button then
        return
    end

    if kind == ENTRY_KIND_WILDCARD_SLOTS then
        if not Affected(button).trackerWildcardGlow then
            Affected(button).trackerWildcardGlowFrame = CreateFrame("Frame", nil, button)
            Affected(button).trackerWildcardGlowFrame:SetAllPoints(button.Icon or button)
            Affected(button).trackerWildcardGlowFrame:SetFrameStrata("MEDIUM")
            Affected(button).trackerWildcardGlowFrame:SetFrameLevel(20)
            local glow = Affected(button).trackerWildcardGlowFrame:CreateTexture(nil, "ARTWORK")

            glow:SetAtlas("UI-CooldownManager-ActiveGlow", false)
            glow:ClearAllPoints()
            glow:SetPoint("CENTER", button.Icon or button, "CENTER", 0, 0)
            glow:SetSize(58, 58)
            Affected(button).trackerWildcardGlow = glow
        end
        if not Affected(button).trackerWildcardName then
            local name =
                Affected(button).trackerWildcardGlowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
            name:SetFontHeight(11)
            name:SetPoint("BOTTOM", button.Icon or button, "BOTTOM", 0, -4)
            name:SetText("Trinket\nSlot")
            name:SetTextColor(1, 0.8, 0.2, 1)
            Affected(button).trackerWildcardName = name
        end
        Affected(button).trackerWildcardGlow:Show()
        Affected(button).trackerWildcardName:Show()
    else
        if Affected(button).trackerWildcardGlow then
            Affected(button).trackerWildcardGlow:Hide()
        end
        if Affected(button).trackerWildcardName then
            Affected(button).trackerWildcardName:Hide()
        end
    end
end

local function BuildEntry(kind, id)
    if not kind or not id then
        return nil
    end
    return {
        kind = kind,
        id = id,
    }
end

local function SetIconFromEntry(target, kind, id)
    if not target or not target.Icon then
        return
    end
    local qualityItemID = nil
    if kind == "item" then
        qualityItemID = id
    end
    local quality = qualityItemID and C_TradeSkillUI.GetItemReagentQualityByItemInfo(qualityItemID) or nil
    local itemInfo = { C_Item.GetItemInfo(id) }
    local expansionNumber = itemInfo and itemInfo[15] or nil
    if quality then
        if not target.Icon._quality then
            target.Icon._quality_frame = CreateFrame("Frame", nil, target)
            target.Icon._quality_frame:SetAllPoints(target.Icon)
            target.Icon._quality_frame:SetFrameStrata("MEDIUM")
            target.Icon._quality_frame:SetFrameLevel(20)
            target.Icon._quality = target.Icon._quality_frame:CreateTexture(nil, "ARTWORK")
            target.Icon._quality:SetSize(33, 28)
        end
        if expansionNumber and expansionNumber >= 11 then -- game version - 1 (1 is vanilla)
            target.Icon._quality:SetAtlas("Professions-Icon-Quality-12-Tier" .. quality .. "-Inv", false)
        else
            target.Icon._quality:SetAtlas("Professions-Icon-Quality-Tier" .. quality .. "-Inv", false)
        end

        target.Icon._quality:Show()
        target.Icon._quality:ClearAllPoints()
        target.Icon._quality:SetPoint("TOPLEFT", target.Icon, "TOPLEFT", -4, 4)
    else
        if target.Icon._quality then
            target.Icon._quality:Hide()
        end
    end

    if ItemVisuals.GetEntryIcon then
        target.Icon:SetTexture(ItemVisuals:GetEntryIcon(kind, id))
        return
    end
    local icon = nil
    if kind == "spell" then
        icon = C_Spell.GetSpellTexture(id)
    else
        icon = C_Item.GetItemIconByID(id)
    end
    target.Icon:SetTexture(icon or 134400)
end

local function IsEntryUsable(owned, kind, id)
    if not owned and kind ~= "spell" then
        return false
    end
    if kind == "spell" then
        return C_SpellBook and C_SpellBook.IsSpellInSpellBook(id) or owned.spells[id]
    end
    if kind == ENTRY_KIND_WILDCARD_SLOTS then
        return owned.wildcardSlots and owned.wildcardSlots[id]
    end
    return owned.items[id]
end

local function HandleCursorDrop(state)
    if InCombatLockdown() then
        return false
    end
    local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
    if not cursorType then
        return false
    end

    local kind, id
    if cursorType == "spell" then
        local spellID = cursorSpellID or cursorID
        if not spellID then
            return false
        end
        id = C_Spell.GetBaseSpell(spellID) or spellID
        kind = "spell"
    elseif cursorType == "item" then
        if not cursorID then
            return false
        end
        id = cursorID
        kind = "item"
    end

    if not kind or not id then
        return false
    end
    local ok, error = ns.API:AddToTracking(kind, id, state)
    if not ok then
        ns.Addon:Print(error)
    end

    ClearCursor()
    return true
end

local function IsCursorDroppable()
    local cursorType = GetCursorInfo()
    return cursorType == "spell" or cursorType == "item" or cursorType == "action"
end

local function EnsureDropPlaceholder(category)
    if Affected(category).trackerDropPlaceholder then
        return Affected(category).trackerDropPlaceholder
    end

    local dropZone = CreateFrame("Frame", nil, category)
    dropZone:SetAllPoints(category)
    dropZone:EnableMouse(true)
    local baseLevel = (category.Container and category.Container:GetFrameLevel()) or category:GetFrameLevel()
    dropZone:SetFrameLevel(baseLevel + 100)
    dropZone:Hide()

    local overlay = dropZone:CreateTexture(nil, "OVERLAY")
    overlay:SetAtlas("UI-Dream-Highlight-Top", false)
    overlay:SetAlpha(0.65)
    overlay:SetPoint("TOPLEFT", category, "TOPLEFT", 8, -24)
    overlay:SetPoint("BOTTOMRIGHT", category, "BOTTOMRIGHT", -8, 24)
    dropZone.Texture = overlay

    local function drop()
        dropZone:Hide()
        HandleCursorDrop(category.state)
    end
    dropZone:SetScript("OnReceiveDrag", drop)
    dropZone:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" and IsCursorDroppable() then
            drop()
        end
    end)

    dropZone:SetScript("OnLeave", function()
        dropZone:Hide()
    end)

    Affected(category).trackerDropPlaceholder = dropZone
    return dropZone
end

local function ShowDropPlaceholder(category, show)
    local dropZone = EnsureDropPlaceholder(category)
    if not dropZone then
        return
    end
    dropZone:SetShown(show == true)
end

local function EnsureReorderMarker()
    if reorderMarker then
        return reorderMarker
    end

    local miscPanel = GetMiscPanelFrame()
    if not miscPanel then
        return nil
    end

    local marker = nil
    if _G["CooldownViewerSettingsReorderMarkerTemplate"] then
        local ok, created = pcall(CreateFrame, "Frame", nil, miscPanel, "CooldownViewerSettingsReorderMarkerTemplate")
        if ok then
            marker = created
        end
    end

    if not marker or not marker.Texture then
        marker = CreateFrame("Frame", nil, miscPanel)
        marker:SetSize(12, 12)
        marker.Texture = marker:CreateTexture(nil, "OVERLAY")
        marker.Texture:SetAllPoints()
    end

    if not marker.SetHorizontal then
        function marker:SetHorizontal()
            if self.Texture and self.Texture.SetAtlas then
                self.Texture:SetAtlas("cdm-vertical", true)
            elseif self.Texture then
                self.Texture:SetColorTexture(1, 1, 1, 1)
            end
        end
    end

    marker:Hide()
    local spacing = Affected(miscPanel).trackerItemSpacing or 8
    local itemSize = Affected(miscPanel).trackerItemSize or 38
    marker:SetSize(spacing, itemSize)
    reorderMarker = marker
    return reorderMarker
end

local function EnsureReorderCursor()
    if reorderCursor then
        return reorderCursor
    end

    local frame = CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")
    frame:Hide()
    reorderCursor = frame
    return reorderCursor
end

local function PickupItemCursor(itemButton)
    local cursor = EnsureReorderCursor()
    if not cursor then
        return
    end

    if cursor.SetToCursor then
        cursor:SetToCursor(itemButton)
        reorderCursorFollow = false
    else
        if cursor.Icon and itemButton and itemButton.Icon then
            cursor.Icon:SetTexture(itemButton.Icon:GetTexture())
        end
        cursor:Show()
        reorderCursorFollow = true
    end
end

local function ClearItemCursor()
    if reorderCursor then
        if reorderCursor.StopMovingOrSizing then
            reorderCursor:StopMovingOrSizing()
        end
        reorderCursor:Hide()
    end
    reorderCursorFollow = false
end

local function IsReordering()
    return reorderSourceItem ~= nil
end

local function SetReorderTarget(target)
    if IsReordering() then
        reorderTarget = target
    end
end

local function UpdateReorderMarker()
    local marker = EnsureReorderMarker()
    if not marker then
        return
    end

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        local spacing = Affected(miscPanel).trackerItemSpacing or 8
        local itemSize = Affected(miscPanel).trackerItemSize or 38
        marker:SetSize(spacing, itemSize)
    end

    local target = reorderTarget
    marker:SetShown(target ~= nil)
    if not target then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = GetAppropriateTopLevelParent():GetScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local targetItem = target.GetBestCooldownItemTarget and target:GetBestCooldownItemTarget(cursorX, cursorY) or nil
    reorderTargetItem = targetItem
    if targetItem and targetItem.UpdateReorderMarkerPosition then
        marker:ClearAllPoints()
        local isMarkerAfterTarget = targetItem:UpdateReorderMarkerPosition(marker, cursorX, cursorY)
        reorderOffset = isMarkerAfterTarget and 1 or 0
    end

    if reorderCursorFollow and reorderCursor then
        reorderCursor:ClearAllPoints()
        reorderCursor:SetPoint("TOPLEFT", GetAppropriateTopLevelParent(), "BOTTOMLEFT", cursorX, cursorY)
    end
end

local function CancelOrderChange()
    if reorderSourceItem and reorderSourceItem.SetReorderLocked then
        reorderSourceItem:SetReorderLocked(false)
    end
    if reorderMarker then
        reorderMarker:Hide()
    end
    reorderSourceItem = nil
    reorderTarget = nil
    reorderTargetItem = nil
    reorderOffset = 0
    reorderEatNextGlobalMouseUp = nil
    ClearItemCursor()

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        miscPanel:SetScript("OnUpdate", nil)
        miscPanel:UnregisterEvent("GLOBAL_MOUSE_UP")
    end
end

local function EndOrderChange()
    local sourceItem = reorderSourceItem
    local targetItem = reorderTargetItem

    if sourceItem and targetItem and sourceItem ~= targetItem then
        local targetState = targetItem.categoryState or sourceItem.categoryState
        local sourceKind, sourceID = GetEntryKindAndID(sourceItem)
        if sourceKind and sourceID then
            if Affected(targetItem).trackerEmpty then
                if sourceItem.categoryState ~= targetState then
                    ItemsData:SetEntryState(sourceKind, sourceID, targetState)
                end
                ItemsData:InsertItemAt(targetState, BuildEntry(sourceKind, sourceID), nil, false)
            else
                local targetKind, targetID = GetEntryKindAndID(targetItem)
                if targetKind and targetID then
                    if sourceItem.categoryState ~= targetState then
                        ItemsData:SetEntryState(sourceKind, sourceID, targetState)
                    end
                    ItemsData:InsertItemAt(
                        targetState,
                        BuildEntry(sourceKind, sourceID),
                        BuildEntry(targetKind, targetID),
                        reorderOffset == 0
                    )
                end
            end
        end
    end

    CancelOrderChange()
    TrackerAssignmentPanel:RefreshMiscPanel()
    ItemViewer:RefreshItemViewerFrames()
end

local function BeginOrderChange(itemButton, eatNextGlobalMouseUp)
    if IsReordering() or not itemButton or Affected(itemButton).trackerEmpty then
        return
    end

    reorderSourceItem = itemButton
    reorderTarget = itemButton
    reorderTargetItem = itemButton
    reorderOffset = 0
    reorderEatNextGlobalMouseUp = eatNextGlobalMouseUp

    if itemButton.SetReorderLocked then
        itemButton:SetReorderLocked(true)
    end

    PickupItemCursor(itemButton)
    EnsureReorderMarker()

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        miscPanel:SetScript("OnUpdate", function()
            UpdateReorderMarker()
        end)
        miscPanel:SetScript("OnEvent", function(_self, event, ...)
            if event == "GLOBAL_MOUSE_UP" then
                local button = ...
                if reorderEatNextGlobalMouseUp == button then
                    reorderEatNextGlobalMouseUp = nil
                    return
                end
                if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_DROP_OBJECT then
                    PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
                end
                if button == "LeftButton" then
                    EndOrderChange()
                elseif button == "RightButton" then
                    CancelOrderChange()
                end
            end
        end)
        miscPanel:RegisterEvent("GLOBAL_MOUSE_UP")
    end
end

local function ShowItemContextMenu(button)
    if not button then
        return
    end
    local kind, id = GetEntryKindAndID(button)
    if not kind or not id then
        return
    end
    local currentState = button.categoryState

    local function RefreshTrackerPanels()
        TrackerAssignmentPanel:RefreshMiscPanel()
        ItemViewer:RefreshItemViewerFrames()
    end

    local function Generator(owner, rootDescription)
        -- Entries with curated/proc data show a disabled info button stating the
        -- source. Only entries we have NO data for get the manual "Set Custom
        -- Active" option (the manual duration logic stays on for those).
        if currentState ~= ITEM_STATE_HIDDEN and IsCustomActiveMenuSupportedKind(kind) then
            local targetKind, targetID = ResolveCustomActiveTarget(kind, id)
            local AuraDurations = ns.TrackerAuraDurations

            local isProc = false
            local knownDuration = 0
            if targetKind and targetID and AuraDurations then
                isProc = AuraDurations.HasProc and AuraDurations:HasProc(targetKind, targetID) or false
                knownDuration = (
                    AuraDurations.GetKnownDuration and AuraDurations:GetKnownDuration(targetKind, targetID)
                ) or 0
            end

            if isProc then
                local info = rootDescription:CreateButton("Duration from procs", function() end)
                if info and info.SetEnabled then
                    info:SetEnabled(false)
                end
            elseif knownDuration > 0 then
                local info = rootDescription:CreateButton(
                    "Auto duration: " .. FormatCustomActiveValue(knownDuration) .. "s",
                    function() end
                )
                if info and info.SetEnabled then
                    info:SetEnabled(false)
                end
            else
                local currentValue = 0
                if targetKind and targetID then
                    currentValue = DB.GetCustomActiveDuration(targetKind, targetID) or 0
                end

                local label = "Set Custom Active (" .. FormatCustomActiveValue(currentValue) .. "s)"
                if not targetKind or not targetID then
                    label = "Set Custom Active (equip trinket first)"
                end

                rootDescription:CreateButton(label, function()
                    local popupKind, popupID = ResolveCustomActiveTarget(kind, id)
                    if not popupKind or not popupID then
                        local wildcardName = ItemsData:GetEntryName(kind, id) or tostring(id)
                        ns.Addon:Print(wildcardName .. ": no equipped trinket to set custom active.")
                        return
                    end
                    StaticPopup_Show("CMC_SET_CUSTOM_ACTIVE", nil, nil, { kind = popupKind, id = popupID })
                end)
            end
        end
        if ItemsData:IsTrackerState(currentState) then
            rootDescription:CreateCheckbox("Always Show", function()
                return DB.GetAlwaysShow(kind, id)
            end, function()
                DB.SetAlwaysShow(kind, id, not DB.GetAlwaysShow(kind, id))
                RefreshTrackerPanels()
            end)
        end
        rootDescription:CreateButton("Untrack", function()
            ItemsData:SetEntryState(kind, id, nil)
            RefreshTrackerPanels()
        end)
    end

    MenuUtil.CreateContextMenu(button, Generator)
end

local function InitializeItemButton(button)
    if Affected(button).trackerInitialized then
        return
    end

    if button.Cooldown then
        if ItemVisuals then
            ItemVisuals:ClearCooldown(button, nil)
        else
            CooldownFrame_Clear(button.Cooldown)
            button.Cooldown:SetDrawSwipe(false)
        end
        button.Cooldown:SetDrawEdge(false)
    end

    if button.OutOfRange then
        button.OutOfRange:Hide()
    end

    button:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowItemContextMenu(self)
        elseif mouseButton == "LeftButton" and not Affected(self).trackerEmpty then
            if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
                PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
            end
            BeginOrderChange(self, mouseButton)
        end
    end)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if Affected(self).trackerEmpty then
            return
        end
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
            PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
        end
        BeginOrderChange(self)
    end)
    button:SetScript("OnEnter", function(self)
        SetReorderTarget(self)
        if Affected(self).trackerEmpty then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip_SetTitle then
                GameTooltip_SetTitle(GameTooltip, "Empty Slot")
            else
                GameTooltip:SetText("Empty Slot")
            end
            GameTooltip:Show()
        else
            local kind, id = GetEntryKindAndID(self)
            if kind and id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if kind == ENTRY_KIND_WILDCARD_SLOTS then
                    local wildcardName = ItemsData:GetEntryName(kind, id) or tostring(id)
                    local equippedItemID = ItemsData.GetWildcardSlotItemID and ItemsData:GetWildcardSlotItemID(id)
                        or nil
                    if equippedItemID and GameTooltip.SetItemByID then
                        GameTooltip:SetItemByID(equippedItemID)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(wildcardName, 0.85, 0.85, 0.85)
                    else
                        if GameTooltip_SetTitle then
                            GameTooltip_SetTitle(GameTooltip, wildcardName)
                        else
                            GameTooltip:SetText(wildcardName)
                        end
                    end
                elseif kind == "spell" then
                    if GameTooltip.SetSpellByID then
                        GameTooltip:SetSpellByID(id)
                    else
                        local name = ItemsData:GetEntryName(kind, id)
                        if name then
                            GameTooltip:SetText(name)
                        end
                    end
                else
                    GameTooltip:SetItemByID(id)
                end
                GameTooltip:Show()
            end
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    function button:SetReorderLocked(locked)
        Affected(self).trackerReorderLocked = locked and true or false
        if self.Icon then
            self.Icon:SetDesaturated(Affected(self).trackerReorderLocked)
        end
    end

    function button:IsReorderLocked()
        return Affected(self).trackerReorderLocked == true
    end

    function button:IsEmptyCategory()
        return Affected(self).trackerEmpty == true
    end

    function button:GetBestCooldownItemTarget(_cursorX, _cursorY)
        return self
    end

    function button:UpdateReorderMarkerPosition(marker, cursorX, _cursorY)
        if marker and marker.SetHorizontal then
            marker:SetHorizontal()
        end
        local centerX = self:GetCenter()
        if centerX and cursorX < centerX then
            marker:SetPoint("CENTER", self, "LEFT", -4, 0)
            return false
        else
            marker:SetPoint("CENTER", self, "RIGHT", 4, 0)
            return true
        end
    end

    button:HookScript("OnShow", function(self)
        if not self.Icon then
            return
        end
        if Affected(self).trackerEmpty then
            if ItemVisuals then
                ItemVisuals:SetEmptySlot(self)
            else
                self.Icon:SetTexture(nil)
                self.Icon:SetAtlas("cdm-empty", true)
            end
        else
            local kind, id = GetEntryKindAndID(self)
            if kind and id then
                SetIconFromEntry(self, kind, id)
            end
        end
    end)

    Affected(button).trackerInitialized = true
end

local function AcquireItemButton(category)
    local button = category.itemPool:Acquire()
    InitializeItemButton(button)
    button:Show()
    return button
end

local function ResetCategoryButtons(category)
    category.itemPool:ReleaseAll()

    if Affected(category).trackerDropPlaceholder then
        Affected(category).trackerDropPlaceholder:Hide()
    end

    local container = category.Container
    if container then
        for _, child in ipairs({ container:GetChildren() }) do
            if child.layoutIndex ~= nil then
                child.layoutIndex = nil
            end
        end
    end
end

function TrackerAssignmentPanel:LayoutCategory(category, entries, owned)
    ResetCategoryButtons(category)

    local container = category.Container or category.Content
    local headerHeight = category.Header:GetHeight()
    local isCollapsed = category.IsCollapsed and category:IsCollapsed() or category.Collapsed
    if isCollapsed then
        if category.SetCollapsed then
            category:SetCollapsed(true)
        elseif container then
            container:Hide()
        end
        category:SetHeight(headerHeight)
        return
    end

    if category.SetCollapsed then
        category:SetCollapsed(false)
    elseif container then
        container:Show()
    end

    local size = 38
    local spacing = 8

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        Affected(miscPanel).trackerItemSpacing = spacing
        Affected(miscPanel).trackerItemSize = size
    end

    if #entries == 0 then
        local emptyButton = AcquireItemButton(category)
        SetButtonEntry(emptyButton, nil, nil)
        -- Clear overlays left over from whatever entry this pooled button held
        -- before, so an empty slot never shows a stale quality / "Trinket Slot" badge.
        SetWildcardGlow(emptyButton, nil)
        if emptyButton.Icon and emptyButton.Icon._quality then
            emptyButton.Icon._quality:Hide()
        end
        Affected(emptyButton).trackerEmpty = true
        emptyButton.categoryState = category.state
        emptyButton.layoutIndex = 1
        emptyButton:ClearAllPoints()
        emptyButton:SetSize(size, size)
        if ItemVisuals then
            ItemVisuals:SetEmptySlot(emptyButton)
        else
            if emptyButton.Icon then
                emptyButton.Icon:SetTexture(nil)
                emptyButton.Icon:SetAtlas("cdm-empty", true)
                emptyButton.Icon:SetDesaturated(false)
            end
            if emptyButton.Cooldown then
                CooldownFrame_Clear(emptyButton.Cooldown)
            end
        end
    else
        for index, entry in ipairs(entries) do
            local button = AcquireItemButton(category)
            SetButtonEntry(button, entry.kind, entry.id)
            SetWildcardGlow(button, entry.kind)
            Affected(button).trackerEmpty = false
            button.categoryState = category.state
            button.layoutIndex = index
            button:ClearAllPoints()
            button:SetSize(size, size)

            SetIconFromEntry(button, entry.kind, entry.id)
            if button.Icon then
                button.Icon:SetDesaturated(not IsEntryUsable(owned, entry.kind, entry.id))
            end

            if button.Cooldown then
                CooldownFrame_Clear(button.Cooldown)
            end
        end
    end

    if container and container.Layout then
        container.childXPadding = spacing
        container.childYPadding = spacing
        container.isHorizontal = true
        container.stride = 7
        container.layoutFramesGoingRight = true
        container.layoutFramesGoingUp = false
        container.alwaysUpdateLayout = true
        container:Layout()
    end

    local contentHeight = container and container:GetHeight() or 0
    local totalHeight = nil
    if category.Header and container then
        local headerTop = category.Header:GetTop()
        local containerBottom = container:GetBottom()
        if headerTop and containerBottom then
            totalHeight = headerTop - containerBottom
        end
    end
    category:SetHeight(totalHeight or (headerHeight + 6 + contentHeight))
end

function TrackerAssignmentPanel:CreateItemCategory(parent, title, state)
    local categoryDisplay = CreateFrame("Frame", nil, parent, "CooldownViewerSettingsCategoryTemplate")
    categoryDisplay.state = state
    categoryDisplay.Collapsed = false
    categoryDisplay.Header:SetHeaderText(title)

    categoryDisplay:Layout()

    function categoryDisplay:SetCollapsed(collapsed)
        self.Collapsed = collapsed and true or false
        if self.Header and self.Header.UpdateCollapsedState then
            self.Header:UpdateCollapsedState(self.Collapsed)
        end
        if self.Container then
            self.Container:SetShown(not self.Collapsed)
            if self.Container.Layout then
                self.Container:Layout()
            end
        end
    end

    function categoryDisplay:IsCollapsed()
        return self.Collapsed == true
    end

    function categoryDisplay:ToggleCollapsed()
        self:SetCollapsed(not self:IsCollapsed())
        TrackerAssignmentPanel:RefreshMiscPanel()
    end

    if categoryDisplay.Header then
        if categoryDisplay.Header.CollapseButton then
            categoryDisplay.Header.CollapseButton:Hide()
            categoryDisplay.Header.CollapseButton:Disable()
        end
        if categoryDisplay.Header.Toggle then
            categoryDisplay.Header.Toggle:Hide()
            categoryDisplay.Header.Toggle:Disable()
        end
    end

    if not categoryDisplay.Container then
        categoryDisplay.Container = CreateFrame("Frame", nil, categoryDisplay)
        categoryDisplay.Container:SetPoint("TOPLEFT", categoryDisplay, "TOPLEFT", 0, 0)
        categoryDisplay.Container:SetPoint("TOPRIGHT", categoryDisplay, "TOPRIGHT", 0, 0)
    end

    categoryDisplay:SetScript("OnEnter", function(self)
        SetReorderTarget(self)
        if IsCursorDroppable() and not self:IsCollapsed() then
            ShowDropPlaceholder(self, true)
        end
    end)
    categoryDisplay:SetScript("OnReceiveDrag", function(self)
        ShowDropPlaceholder(self, false)
        if HandleCursorDrop(self.state) then
            return
        end
    end)
    categoryDisplay:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" and IsCursorDroppable() then
            ShowDropPlaceholder(self, false)
            HandleCursorDrop(self.state)
        end
    end)
    if categoryDisplay.Container then
        categoryDisplay.Container:SetScript("OnEnter", function()
            SetReorderTarget(categoryDisplay)
            if IsCursorDroppable() and not categoryDisplay:IsCollapsed() then
                ShowDropPlaceholder(categoryDisplay, true)
            end
        end)
        categoryDisplay.Container:SetScript("OnReceiveDrag", function()
            ShowDropPlaceholder(categoryDisplay, false)
            if HandleCursorDrop(categoryDisplay.state) then
                return
            end
        end)
        categoryDisplay.Container:SetScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" and IsCursorDroppable() then
                ShowDropPlaceholder(categoryDisplay, false)
                HandleCursorDrop(categoryDisplay.state)
            end
        end)
    end

    categoryDisplay.itemPool = CreateFramePool(
        "Frame",
        categoryDisplay.Container,
        "CooldownViewerSettingsItemTemplate",
        function(_, frame)
            frame:Hide()
            frame.layoutIndex = nil
            frame.itemID = nil
            frame.spellID = nil
            Affected(frame).trackerEntryKind = nil
            Affected(frame).trackerEntryId = nil
            Affected(frame).trackerEmpty = nil
            -- Hide every custom overlay so a recycled button never carries a stale
            -- quality badge or "Trinket Slot" glow/label onto its next entry.
            if Affected(frame).trackerWildcardGlow then
                Affected(frame).trackerWildcardGlow:Hide()
            end
            if Affected(frame).trackerWildcardName then
                Affected(frame).trackerWildcardName:Hide()
            end
            if frame.Icon and frame.Icon._quality then
                frame.Icon._quality:Hide()
            end
            if frame.Icon then
                frame.Icon:SetTexture(nil)
            end
        end
    )

    function categoryDisplay:GetNearestItemToCursorWeighted(cursorX, cursorY)
        local nearestItem = nil
        local nearestVertical = math.huge
        local nearestHorizontal = math.huge

        for item in self.itemPool:EnumerateActive() do
            local left, right, bottom, top = item:GetLeft(), item:GetRight(), item:GetBottom(), item:GetTop()
            if left and right and bottom and top then
                local centerX = (left + right) / 2
                local centerY = (bottom + top) / 2
                local horizontalDistance = math.abs(centerX - cursorX)
                local verticalDistance = math.abs(centerY - cursorY)
                if cursorY > bottom and cursorY < top then
                    verticalDistance = 0
                end
                if
                    verticalDistance < nearestVertical
                    or (verticalDistance == nearestVertical and horizontalDistance < nearestHorizontal)
                then
                    nearestItem = item
                    nearestVertical = verticalDistance
                    nearestHorizontal = horizontalDistance
                end
            end
        end

        return nearestItem
    end

    function categoryDisplay:GetBestCooldownItemTarget(cursorX, cursorY)
        return self:GetNearestItemToCursorWeighted(cursorX, cursorY)
    end

    if categoryDisplay.Header and categoryDisplay.Header.SetClickHandler then
        categoryDisplay.Header:SetClickHandler(function(_, button)
            if button == "LeftButton" then
                categoryDisplay:ToggleCollapsed()
            end
        end)
    elseif categoryDisplay.Header then
        categoryDisplay.Header:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                categoryDisplay:ToggleCollapsed()
            end
        end)
    end

    categoryDisplay:SetCollapsed(false)

    return categoryDisplay
end

function TrackerAssignmentPanel:RefreshMiscPanel(settingsFrame)
    if not ns.db.profile.tracker_enabled then
        return
    end
    local owned = ItemsData:ScanOwnedItemsForMiscPanel()
    ItemsData:EnsureTrackedItems(owned)

    -- Auto-grow/shrink so there's always exactly one empty trailing tracker.
    if ItemViewer.ReconcileTrackerCount then
        ItemViewer:ReconcileTrackerCount()
    end

    local frame = settingsFrame or _G["CooldownViewerSettings"]
    local miscPanel = Affected(frame).trackerMiscPanel
    if not miscPanel then
        return
    end

    if miscPanel.SetPortraitToSpecIcon then
        miscPanel:SetPortraitToSpecIcon()
    end

    local showUnusable = DB.GetShowingUnusable()
    local searchTerm = Affected(miscPanel).trackerSearchTerm or ""
    local searchLower = searchTerm ~= "" and searchTerm:lower() or nil

    local function matchesSearch(entry)
        if not searchLower then
            return true
        end
        local name = ItemsData:GetEntryName(entry.kind, entry.id)
        return name and name:lower():find(searchLower, 1, true) ~= nil
    end

    -- Collect the displayable entries for one bucket. Tracker buckets keep
    -- alwaysShow entries even when unowned; the hidden bucket never does.
    local function collectEntries(state, isHidden)
        local result = {}
        for _, entry in ipairs(ItemsData:GetEntriesByState(state)) do
            local usable = showUnusable
                or IsEntryUsable(owned, entry.kind, entry.id)
                or (not isHidden and DB.GetAlwaysShow(entry.kind, entry.id))
            if usable and matchesSearch(entry) then
                table.insert(result, entry)
            end
        end
        return result
    end

    local trackerCategories = Affected(miscPanel).trackerCategories
    local hiddenCategory = Affected(miscPanel).hiddenCategory
    if not trackerCategories or not hiddenCategory then
        return
    end

    -- Lay out one category per active tracker, hide the surplus, and append the
    -- hidden bucket. `categories` holds only the visible frames for positioning.
    local count = ItemViewer:GetTrackerCount()
    local categories = {}
    local revealedNewCategory = false
    for i = 1, #trackerCategories do
        local category = trackerCategories[i]
        if i <= count then
            -- A category being shown for the first time lays out at the wrong height
            -- on this pass (its content frames size up a frame later), so it overlaps
            -- the next section until a follow-up redraw corrects it.
            if not category:IsShown() then
                revealedNewCategory = true
            end
            category:Show()
            self:LayoutCategory(category, collectEntries(ItemsData:GetTrackerStateName(i), false), owned)
            table.insert(categories, category)
        else
            category:Hide()
        end
    end
    self:LayoutCategory(hiddenCategory, collectEntries(ITEM_STATE_HIDDEN, true), owned)
    table.insert(categories, hiddenCategory)

    local scrollChild = Affected(miscPanel).trackerScrollChild
    if scrollChild then
        local yOffset = 0
        local previousCategory = nil
        for _, category in ipairs(categories) do
            category:ClearAllPoints()
            if previousCategory then
                category:SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT", 0, -18)
            else
                category:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
            end
            yOffset = yOffset + category:GetHeight() + (previousCategory and 18 or 0)
            previousCategory = category
        end
        local scrollFrame = Affected(miscPanel).trackerScrollFrame
        if scrollFrame then
            local paddingHeight = 18
            local frameHeight = scrollFrame:GetHeight() or 0
            local needsScrollPadding = previousCategory and (frameHeight > 0 and yOffset > frameHeight)
            if needsScrollPadding then
                if not Affected(miscPanel).trackerScrollPadding then
                    Affected(miscPanel).trackerScrollPadding = CreateFrame("Frame", nil, scrollChild)
                    Affected(miscPanel).trackerScrollPadding:SetHeight(paddingHeight)
                end
                Affected(miscPanel).trackerScrollPadding:ClearAllPoints()
                Affected(miscPanel).trackerScrollPadding:SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT")
                Affected(miscPanel).trackerScrollPadding:SetPoint("TOPRIGHT", previousCategory, "BOTTOMRIGHT")
                Affected(miscPanel).trackerScrollPadding:Show()
                scrollChild:SetHeight(math.max(1, yOffset + paddingHeight))
            elseif Affected(miscPanel).trackerScrollPadding then
                Affected(miscPanel).trackerScrollPadding:Hide()
                scrollChild:SetHeight(math.max(1, yOffset))
            end

            scrollFrame:UpdateScrollChildRect()
        else
            scrollChild:SetHeight(math.max(1, yOffset))
        end
    end

    -- A newly revealed category needs one corrective relayout once its content
    -- frames have sized. Guarded by revealedNewCategory so this never loops (the
    -- follow-up pass sees the category already shown).
    if revealedNewCategory then
        C_Timer.After(0.1, function()
            TrackerAssignmentPanel:RefreshMiscPanel(settingsFrame)
        end)
    end
end

local function ShowMiscPanel(settingsFrame)
    local miscPanel = Affected(settingsFrame).trackerMiscPanel
    if not miscPanel then
        return
    end

    local hidden = {}
    for _, child in ipairs({ settingsFrame:GetChildren() }) do
        if child:IsShown() and child ~= miscPanel and not IsTabButton(child) then
            child:Hide()
            table.insert(hidden, child)
        end
    end

    Affected(settingsFrame).trackerHiddenChildren = hidden
    TrackerAssignmentPanel:RefreshMiscPanel(settingsFrame)
    miscPanel:Show()
end

function TrackerAssignmentPanel:EnsureMiscSettingsTab(settingsFrame)
    if Affected(settingsFrame).trackerMiscPanel then
        return
    end

    local miscPanel = CreateFrame("Frame", "_cmc_tracker_misc_panel", settingsFrame, "ButtonFrameTemplate")
    miscPanel:SetAllPoints(settingsFrame)
    miscPanel:Hide()
    miscPanel.Inset.Bg:SetAtlas("character-panel-background", true)
    miscPanel.Inset.Bg:SetHorizTile(false)
    miscPanel.Inset.Bg:SetVertTile(false)
    miscPanel.TitleContainer.TitleText:SetText("Cooldown Settings")

    if miscPanel.CloseButton then
        miscPanel.CloseButton:SetScript("OnClick", function()
            HideUIPanel(settingsFrame)
        end)
    end

    Affected(settingsFrame).trackerMiscPanel = miscPanel

    local scrollFrame = CreateFrame("ScrollFrame", "$parent.CooldownScroll", miscPanel, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 17, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 29)

    local scrollChild = CreateFrame("Frame", "$parent.Content", scrollFrame)
    scrollChild:SetSize(300, 1)
    scrollChild:SetPoint("TOPLEFT", 0, 0)
    scrollChild:SetPoint("TOPRIGHT", 0, 0)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0)
    scrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 0)

    scrollFrame:SetScript("OnSizeChanged", function(self)
        scrollChild:SetWidth(self:GetWidth())
        TrackerAssignmentPanel:RefreshMiscPanel(settingsFrame)
    end)

    miscPanel:HookScript("OnShow", function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
        TrackerAssignmentPanel:RefreshMiscPanel(settingsFrame)
    end)

    -- Pre-create the full pool of tracker categories (LibEQOL/template frames can't
    -- be destroyed); RefreshMiscPanel shows only the active ones. The hidden bucket
    -- is always last.
    local maxTrackers = ns.CONSTANTS.MAX_TRACKERS or 10
    local trackerCategories = {}
    for i = 1, maxTrackers do
        trackerCategories[i] = self:CreateItemCategory(scrollChild, "Tracker " .. i, ItemsData:GetTrackerStateName(i))
        trackerCategories[i]:Hide()
    end
    local hiddenCategory = self:CreateItemCategory(scrollChild, "Not Displayed", ITEM_STATE_HIDDEN)

    Affected(miscPanel).trackerCategories = trackerCategories
    Affected(miscPanel).hiddenCategory = hiddenCategory
    Affected(miscPanel).trackerScrollChild = scrollChild
    Affected(miscPanel).trackerScrollFrame = scrollFrame
    local spellsTab = settingsFrame.SpellsTab
    local aurasTab = settingsFrame.AurasTab

    Affected(spellsTab).trackerIsTabButton = true
    Affected(aurasTab).trackerIsTabButton = true

    -- Create a dedicated search box for the TrackerAssignmentPanel, matching Blizzard's CooldownViewerSettings XML
    if not Affected(miscPanel).trackerSearchBox then
        local searchBox = CreateFrame("EditBox", nil, miscPanel, "SearchBoxTemplate")
        searchBox:SetSize(195, 30)
        searchBox:SetPoint("TOPLEFT", miscPanel, "TOPLEFT", 72, -30)
        searchBox.Instructions:SetText("Enter search text")
        searchBox:SetScript("OnTextChanged", function(self)
            self.Instructions:SetShown(self:GetText() == "")
            Affected(miscPanel).trackerSearchTerm = self:GetText()
            TrackerAssignmentPanel:RefreshMiscPanel(settingsFrame)
        end)
        searchBox:Hide()
        Affected(miscPanel).trackerSearchBox = searchBox
    end

    if not Affected(miscPanel).trackerShowUnusableCheckbox then
        local cb = CreateFrame("CheckButton", nil, miscPanel, "UICheckButtonTemplate")
        cb:SetPoint("LEFT", Affected(miscPanel).trackerSearchBox, "RIGHT", 8, 0)
        cb:SetChecked(DB.GetShowingUnusable())
        cb:SetScript("OnClick", function(self)
            DB.ToggleShowUnusable()
            self:SetChecked(DB.GetShowingUnusable())
        end)
        if cb.text then
            cb.text:SetText("Show Unusable")
        end
        cb:Hide()
        Affected(miscPanel).trackerShowUnusableCheckbox = cb
    end

    if not Affected(miscPanel).trackerTrackTip then
        local trackTip = miscPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        trackTip:SetPoint("BOTTOMLEFT", miscPanel, "BOTTOMLEFT", 10, 10)
        -- |cff008945Cool|r|cff1e9a4e|r|cff3faa4fdown Ma|r|cff5fb64anag|r|cff7ac243er Ce|r|cff8ccd00ntered|r
        trackTip:SetText("|cfffff100Drag&Drop|r an item or spell")
        Affected(miscPanel).trackerTrackTip = trackTip
    end

    miscPanel:HookScript("OnShow", function(self)
        if Affected(self).trackerSearchBox then
            Affected(self).trackerSearchBox:Show()
        end
        if Affected(self).trackerShowUnusableCheckbox then
            Affected(self).trackerShowUnusableCheckbox:SetChecked(DB.GetShowingUnusable())
            Affected(self).trackerShowUnusableCheckbox:Show()
        end
    end)
    miscPanel:HookScript("OnHide", function(self)
        if Affected(self).trackerSearchBox then
            Affected(self).trackerSearchBox:Hide()
        end
        if Affected(self).trackerShowUnusableCheckbox then
            Affected(self).trackerShowUnusableCheckbox:Hide()
        end
    end)

    -- Do not parent the miscTab to settingsFrame! Doing so will add it to its .TabButtons list and will taint everything inside CooldownViewer as a result.
    local miscTab = CreateFrame("Button", "$parent.MiscTab", UIParent, "CooldownViewerSettingsTabTemplate")

    Affected(miscTab).trackerIsTabButton = true
    miscTab.tooltipText =
        "|cff008945Cool|r|cff1e9a4e|r|cff3faa4fdownMa|r|cff5fb64anag|r|cff7ac243erCe|r|cff8ccd00ntered|r Trackers"
    miscTab.displayMode = "tracker"
    miscTab.activeAtlas = "GreenCross"
    miscTab.inactiveAtlas = "GreenCross"
    miscTab:SetChecked(false)
    miscTab:SetPoint("TOP", aurasTab, "BOTTOM", 0, -3)

    -- Hide the tab when the settings window is closed
    settingsFrame:HookScript("OnHide", function()
        miscTab:Hide()
    end)
    settingsFrame:HookScript("OnShow", function()
        miscTab:Show()
    end)

    local function ShowTrackerTab()
        if Affected(settingsFrame).trackerMiscPanel:IsShown() then
            return
        end
        spellsTab:SetChecked(false)
        aurasTab:SetChecked(false)
        miscTab:SetChecked(true)
        ShowMiscPanel(settingsFrame)
    end

    miscTab:SetScript("OnClick", function()
        -- Never silently turn the feature on: ask first, then enable live (no
        -- reload) and open the tab only if the user confirms.
        if not ns.db.profile.tracker_enabled then
            StaticPopup_Show("CMC_ENABLE_TRACKER", nil, nil, ShowTrackerTab)
            return
        end
        ShowTrackerTab()
    end)

    hooksecurefunc(settingsFrame, "SetDisplayMode", function(self, mode)
        spellsTab:SetChecked(mode == "spells")
        aurasTab:SetChecked(mode == "auras")
        miscTab:SetChecked(mode == "tracker")
        TrackerAssignmentPanel:HideMiscPanel(self)
    end)

    miscTab:Show()
end
