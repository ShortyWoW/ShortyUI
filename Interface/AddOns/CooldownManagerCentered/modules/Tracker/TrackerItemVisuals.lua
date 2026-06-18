local _, ns = ...

local DB = ns.TrackerDB
local ItemsData = ns.TrackerItemsData

local ItemVisuals = ns.TrackerItemVisuals or {}
ns.TrackerItemVisuals = ItemVisuals

local FALLBACK_ICON = 134400
local ITEM_COOLDOWN_TRIGGER_THRESHOLD = 0.1
local WILDCARD_SLOT_TRINKET1 = ItemsData.WILDCARD_SLOT_TRINKET1 or "trinket1"
local WILDCARD_SLOT_TRINKET2 = ItemsData.WILDCARD_SLOT_TRINKET2 or "trinket2"

local activeStartByEntry = {}
local activeUntilByEntry = {}
local lastItemCooldownRemainingByEntry = {}

local desaturationCurve = C_CurveUtil.CreateCurve()
desaturationCurve:AddPoint(0, 0)
desaturationCurve:AddPoint(0.001, 1)

local function BuildEntryKey(kind, id)
    if not kind or id == nil then
        return nil
    end
    return kind .. ":" .. tostring(id)
end

local itemStaticInfo = {}
local function GetItemStaticInfo(itemID)
    local info = itemStaticInfo[itemID]
    if info then
        return info
    end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    local _, spellID = C_Item.GetItemSpell(itemID)
    info = {
        isConsumable = (classID == Enum.ItemClass.Consumable),
        spellID = spellID,
    }
    itemStaticInfo[itemID] = info
    return info
end

local function GetCooldownSwipeColor()
    if not (ns.db and ns.db.profile and ns.db.profile.cooldownManager_customSwipeColor_enabled) then
        return {
            ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.r,
            ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.g,
            ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.b,
            ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.a,
        }
    end
    return {
        (ns.db and ns.db.profile and ns.db.profile.cooldownManager_customCDSwipeColor_r)
            or ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.r,
        (ns.db and ns.db.profile and ns.db.profile.cooldownManager_customCDSwipeColor_g)
            or ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.g,
        (ns.db and ns.db.profile and ns.db.profile.cooldownManager_customCDSwipeColor_b)
            or ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.b,
        (ns.db and ns.db.profile and ns.db.profile.cooldownManager_customCDSwipeColor_a)
            or ns.CONSTANTS.DEFAULT_COOLDOWN_SWIPE_COLOR.a,
    }
end

local function ApplyCustomActiveOverlay(frame, startTime, duration)
    if not frame or not frame.Cooldown or duration <= 0 or not startTime then
        return
    end

    local now = GetTime()
    if startTime < (now - duration) then
        return
    end

    frame.Cooldown:SetCooldown(startTime, duration)
    frame.Cooldown:SetDrawSwipe(true)

    if ns.db.profile.cooldownManager_customSwipeColor_enabled then
        frame.Cooldown:SetSwipeColor(
            ns.db.profile.cooldownManager_customActiveColor_r or ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.r,
            ns.db.profile.cooldownManager_customActiveColor_g or ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.g,
            ns.db.profile.cooldownManager_customActiveColor_b or ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.b,
            ns.db.profile.cooldownManager_customActiveColor_a or ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.a
        )
    else
        frame.Cooldown:SetSwipeColor(
            ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.r,
            ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.g,
            ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.b,
            ns.CONSTANTS.DEFAULT_ACTIVE_SWIPE_COLOR.a
        )
    end
end

function ItemVisuals:GetEntryIcon(kind, id)
    if kind == "wildcardSlots" and ItemsData and ItemsData.GetWildcardSlotItemID then
        local itemID = ItemsData:GetWildcardSlotItemID(id)
        if itemID then
            return C_Item.GetItemIconByID(itemID) or FALLBACK_ICON
        end
        return FALLBACK_ICON
    end
    if kind == "spell" then
        return C_Spell.GetSpellTexture(id) or FALLBACK_ICON
    end

    return C_Item.GetItemIconByID(id) or FALLBACK_ICON
end

function ItemVisuals:ApplyItemIcon(frame, itemID)
    if not frame or not frame.Icon then
        return
    end
    frame.Icon:SetTexture(C_Item.GetItemIconByID(itemID) or FALLBACK_ICON)
end

function ItemVisuals:ApplyEntryIcon(frame, kind, id)
    if not frame or not frame.Icon then
        return
    end
    frame.Icon:SetTexture(self:GetEntryIcon(kind, id))
end

function ItemVisuals:SetEmptySlot(frame)
    if not frame then
        return
    end
    if frame.Icon then
        frame.Icon:SetTexture(nil)
        frame.Icon:SetAtlas("cdm-empty", true)
        frame.Icon:SetDesaturated(false)
    end
    if frame.Cooldown then
        CooldownFrame_Clear(frame.Cooldown)
    end
end

function ItemVisuals:ClearCooldown(frame, desaturation)
    if not frame then
        return
    end
    if frame.Cooldown then
        CooldownFrame_Clear(frame.Cooldown)
        frame.Cooldown:SetDrawSwipe(false)
    end
    if desaturation ~= nil and frame.Icon then
        frame.Icon:SetDesaturation(desaturation)
    end
end

function ItemVisuals:GetCustomActiveDuration(kind, id)
    return DB.GetCustomActiveDuration(kind, id) or 0
end

-- Active-overlay duration to use when no live aura is readable. Prefers the
-- user's manual custom time; if the entry opted into real-aura timing and has no
-- manual value, falls back to the curated on-use buff duration data.
function ItemVisuals:GetEffectiveActiveDuration(kind, id)
    -- Auto durations are the default. For entries we have curated data on, use it
    -- and ignore any old manual customActiveDuration. For entries with no data,
    -- fall back to the user's manual custom time (still offered in the menu).
    local AuraDurations = ns.TrackerAuraDurations
    if AuraDurations and AuraDurations.GetKnownDuration then
        local known = AuraDurations:GetKnownDuration(kind, id)
        if known and known > 0 then
            return known
        end
    end
    return self:GetCustomActiveDuration(kind, id)
end

function ItemVisuals:IsEntryActive(kind, id)
    local key = BuildEntryKey(kind, id)
    if not key then
        return false
    end

    local activeUntil = activeUntilByEntry[key] or 0
    if activeUntil <= GetTime() then
        activeUntilByEntry[key] = nil
        activeStartByEntry[key] = nil
        return false
    end

    return true
end

function ItemVisuals:SetEntryActiveNow(kind, id)
    local duration = self:GetEffectiveActiveDuration(kind, id)
    if duration <= 0 then
        return false
    end

    local key = BuildEntryKey(kind, id)
    if not key then
        return false
    end

    local now = GetTime()
    activeStartByEntry[key] = now
    activeUntilByEntry[key] = now + duration
    C_Timer.After(duration + 0.05, function()
        if ns.TrackerItemViewer and ns.TrackerItemViewer.RefreshItemViewerFrames then
            ns.TrackerItemViewer:RefreshItemViewerFrames()
        end
    end)

    return true
end

function ItemVisuals:MarkSpellCastActive(spellID)
    local matched = false
    if self:SetEntryActiveNow("spell", spellID) then
        matched = true
    end

    local baseSpellID = C_Spell.GetBaseSpell(spellID) or spellID
    if baseSpellID ~= spellID and self:SetEntryActiveNow("spell", baseSpellID) then
        matched = true
    end

    return matched
end

function ItemVisuals:MarkItemCastActive(spellID)
    if not spellID then
        return false
    end

    local matched = false
    local db = DB.GetDB and DB.GetDB() or nil
    local itemCandidates = {}

    if db and db.itemSettings then
        for itemID, settings in pairs(db.itemSettings) do
            if settings and settings.state then
                itemCandidates[itemID] = true
            end
        end
    end

    if ItemsData and ItemsData.GetWildcardSlotItemID and DB.GetWildcardSlotState then
        for _, slotID in ipairs({ WILDCARD_SLOT_TRINKET1, WILDCARD_SLOT_TRINKET2 }) do
            if DB.GetWildcardSlotState(slotID) ~= nil then
                local itemID = ItemsData:GetWildcardSlotItemID(slotID)
                if itemID then
                    itemCandidates[itemID] = true
                end
            end
        end
    end

    for itemID in pairs(itemCandidates) do
        if self:GetEffectiveActiveDuration("item", itemID) > 0 then
            local _, itemSpellID = C_Item.GetItemSpell(itemID)
            if itemSpellID then
                local matches = itemSpellID == spellID
                if not matches then
                    local baseItem = C_Spell.GetBaseSpell(itemSpellID) or itemSpellID
                    local baseCast = C_Spell.GetBaseSpell(spellID) or spellID
                    matches = baseItem == baseCast
                end
                if matches and self:SetEntryActiveNow("item", itemID) then
                    matched = true
                end
            end
        end
    end

    return matched
end

-- Drive the active overlay from the live aura's actual remaining duration. This
-- is the default now (no per-entry opt-in). Returns true when an aura was found
-- and applied.
function ItemVisuals:TryApplyLiveAura(frame, kind, id)
    if not frame or not frame.Cooldown then
        return false
    end
    -- Auto aura durations are always on now; the per-entry opt-in is deprecated.
    -- if not (DB.GetUseRealAura and DB.GetUseRealAura(kind, id)) then
    --     return false
    -- end
    local AuraDurations = ns.TrackerAuraDurations
    if not AuraDurations then
        return false
    end

    local startTime, duration, stacks = AuraDurations:GetLiveActive(kind, id)
    if not startTime then
        return false
    end

    if frame.count then
        frame.count:SetText((stacks and stacks > 1) and stacks or "")
    end
    if frame.Icon then
        frame.Icon:SetDesaturation(0)
    end
    ApplyCustomActiveOverlay(frame, startTime, duration)
    return true
end

function ItemVisuals:UpdateSpellCooldown(frame, spellID)
    if not frame or not frame.Cooldown then
        return false
    end

    if self:TryApplyLiveAura(frame, "spell", spellID) then
        return true
    end

    local overrideSpellID = C_Spell.GetOverrideSpell(spellID) or spellID

    if self:IsEntryActive("spell", spellID) then
        local entryKey = BuildEntryKey("spell", spellID)
        local duration = self:GetEffectiveActiveDuration("spell", spellID)
        local startTime = entryKey and activeStartByEntry[entryKey] or nil
        frame.count:SetText("")
        frame.Icon:SetDesaturation(0)
        ApplyCustomActiveOverlay(frame, startTime, duration)
        return true
    end

    frame.Cooldown:SetSwipeColor(unpack(GetCooldownSwipeColor(), 1, 4))

    local spellCharges = C_Spell.GetSpellCharges(overrideSpellID)
    local hasCharges = spellCharges and spellCharges.maxCharges > 1
    if hasCharges then
        frame.count:SetText(spellCharges.currentCharges)
    else
        frame.count:SetText("")
    end

    local desaturation = 0
    local spellCooldownInfo = C_Spell.GetSpellCooldown(overrideSpellID)
    local isOnGCD = spellCooldownInfo and spellCooldownInfo.isOnGCD

    local cooldownDuration = C_Spell.GetSpellCooldownDuration(overrideSpellID)
    if hasCharges then
        local chargeDuration = C_Spell.GetSpellChargeDuration(overrideSpellID)
        frame.Cooldown:SetCooldownFromDurationObject(chargeDuration)
    else
        if frame.showGCD or not isOnGCD then
            frame.Cooldown:SetCooldownFromDurationObject(cooldownDuration)
            frame.Cooldown:SetDrawSwipe(true)
        end
    end
    if not isOnGCD then
        desaturation = cooldownDuration:EvaluateRemainingDuration(desaturationCurve)
    end

    frame.Icon:SetDesaturation(desaturation)

    return true
end

function ItemVisuals:UpdateItemCooldown(frame, itemID)
    if not frame or not frame.Cooldown then
        return false
    end

    if self:TryApplyLiveAura(frame, "item", itemID) then
        return true
    end

    local staticInfo = GetItemStaticInfo(itemID)
    local isConsumable = staticInfo.isConsumable

    local count = 0
    if isConsumable then
        count = C_Item.GetItemCount(itemID, false, true)
    end
    -- Consumable with no charges: always show as unusable regardless of cooldown
    local forceDesaturated = isConsumable and count == 0

    if count > 1 then
        frame.count:SetText(count)
    else
        frame.count:SetText("")
    end

    local startTime, duration, isCDEnabled = C_Item.GetItemCooldown(itemID)

    local spellID = staticInfo.spellID
    local customDuration = self:GetEffectiveActiveDuration("item", itemID)
    local hasCustomActive = customDuration > 0

    local cooldownRemaining = startTime + duration - GetTime()

    local entryKey = BuildEntryKey("item", itemID)
    local previousRemaining = entryKey and lastItemCooldownRemainingByEntry[entryKey] or nil
    if entryKey then
        lastItemCooldownRemainingByEntry[entryKey] = cooldownRemaining
    end

    if
        hasCustomActive
        and not spellID
        and previousRemaining ~= nil
        and cooldownRemaining > ITEM_COOLDOWN_TRIGGER_THRESHOLD
        and previousRemaining <= ITEM_COOLDOWN_TRIGGER_THRESHOLD
    then
        self:SetEntryActiveNow("item", itemID)
    end

    if hasCustomActive and self:IsEntryActive("item", itemID) then
        local entryKey = BuildEntryKey("item", itemID)
        local startTime = entryKey and activeStartByEntry[entryKey] or nil
        frame.Icon:SetDesaturation(forceDesaturated and 1 or 0)
        ApplyCustomActiveOverlay(frame, startTime, customDuration)
        return true
    end

    frame.Cooldown:SetSwipeColor(unpack(GetCooldownSwipeColor(), 1, 4))

    local isOnGCD = spellID and C_Spell.GetSpellCooldown(spellID).isOnGCD
    if isCDEnabled and (not isOnGCD or frame.showGCD or cooldownRemaining > 2) then
        frame.Cooldown:SetCooldown(startTime, duration)
        frame.Cooldown:SetDrawSwipe(true)
        -- Desaturate only while the long cooldown is clearly active; clear when ≤2s or expired
        if cooldownRemaining <= 0 then
            frame.Icon:SetDesaturation(forceDesaturated and 1 or 0)
        elseif forceDesaturated or cooldownRemaining > 2 then
            frame.Icon:SetDesaturation(1)
        end

        return true
    end
    if not isCDEnabled and cooldownRemaining > 0 and cooldownRemaining <= 0.1 then
        -- healthstone?
        frame.Cooldown:Clear()
        frame.Icon:SetDesaturation(1)
    elseif not isCDEnabled then
        frame.Cooldown:Clear()
        frame.Icon:SetDesaturation(forceDesaturated and 1 or 0)
    end

    return true
end

function ItemVisuals:UpdateEntryCooldown(frame, kind, id)
    if kind == "wildcardSlots" and ItemsData and ItemsData.GetWildcardSlotItemID then
        local itemID = ItemsData:GetWildcardSlotItemID(id)
        if not itemID then
            if frame.count then
                frame.count:SetText("")
            end
            if frame.Cooldown then
                CooldownFrame_Clear(frame.Cooldown)
                frame.Cooldown:SetDrawSwipe(false)
            end
            if frame.Icon then
                frame.Icon:SetDesaturation(0)
            end
            return true
        end
        return self:UpdateItemCooldown(frame, itemID)
    end
    if kind == "spell" then
        return self:UpdateSpellCooldown(frame, id)
    end

    local entryKey = BuildEntryKey(kind, id)
    if entryKey and kind ~= "item" then
        lastItemCooldownRemainingByEntry[entryKey] = nil
    end

    return self:UpdateItemCooldown(frame, id)
end
