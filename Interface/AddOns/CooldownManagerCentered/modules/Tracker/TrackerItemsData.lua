local _, ns = ...

local DB = ns.TrackerDB
local ItemsData = ns.TrackerItemsData or {}
ns.TrackerItemsData = ItemsData

local ITEM_EQUIP_FIRST = INVSLOT_FIRST_EQUIPPED or 1
local ITEM_EQUIP_LAST = INVSLOT_LAST_EQUIPPED or 19

local ITEM_STATE_HIDDEN = "hidden"

local ITEM_STATE_TRACKER1 = "tracker1"

local ENTRY_KIND_WILDCARD_SLOTS = "wildcardSlots"
local WILDCARD_SLOT_TRINKET1 = "trinket1"
local WILDCARD_SLOT_TRINKET2 = "trinket2"

local IGNORED_WILDCARD_TRINKETS = {
    [248583] = true, -- Drum of Renewed Bonds
    [249806] = true, -- Radiant Plume
    [260235] = true, -- Umbral Plume
}
local AUTO_ATTACK_SPELL_ID = 6603

--[[
To get all flyouts:
for i = 1, 1000 do local ok, name, description, numSlots, isKnown = pcall(GetFlyoutInfo,i)  if ok and name then print("[",i,"]= true, --", name) end end
]]
--
local IGNORED_FLYOUT_IDS = {
    [1] = true, -- Teleport
    [8] = true, -- Teleport
    [9] = true, -- Call Pet
    [10] = true, -- Summon Demon
    [11] = true, -- Portal
    [12] = true, -- Portal
    [66] = true, -- Poisons
    [67] = true, -- Grimoire of Service
    [84] = true, -- Hero's Path: Mists of Pandaria
    [92] = true, -- Polymorph Variants
    [93] = true, -- Exotic Munitions
    [96] = true, -- Hero's Path: Warlords of Draenor
    [103] = true, -- Pet Utility
    [106] = true, -- Hex Variants
    [217] = true, -- Kyrian Instruments
    [219] = true, -- Adaptation
    [220] = true, -- Hero's Path: Shadowlands
    [222] = true, -- Hero's Path: Shadowlands Raids
    [223] = true, -- Hero's Path: Battle for Azeroth
    [224] = true, -- Hero's Path: Legion
    [225] = true, -- Hunter Tracking
    [226] = true, -- Track Gathering Profession Reagents
    [227] = true, -- Hero's Path: Dragonflight
    [229] = false, -- Skyriding
    [230] = true, -- Hero's Path: Cataclysm
    [231] = true, -- Hero's Path: Dragonflight Raids
    [232] = true, -- Hero's Path: The War Within
    [235] = true, -- Warbands
    [236] = true, -- Number Sequences
    [237] = true, -- Perennius's Sky Arsenal
    [238] = true, -- Sharpen Your Knife
    [239] = false, -- Overload Herbs
    [240] = false, -- Overload Ore
    [241] = true, -- Green Thumb
    [242] = true, -- Hero's Path: War Within Raids
    [243] = true, -- Skyriding Flight Style
    [244] = true, -- Hero's Path: Midnight Season 1
    [245] = true, -- Carve Meat
    [246] = true, -- Hero's Path: Midnight
}

local WILDCARD_SLOT_DISPLAY_NAMES = {
    [WILDCARD_SLOT_TRINKET1] = "Trinket in first slot",
    [WILDCARD_SLOT_TRINKET2] = "Trinket in second slot",
}

local WILDCARD_SLOT_INVENTORY_SLOTS = {
    [WILDCARD_SLOT_TRINKET1] = INVSLOT_TRINKET1,
    [WILDCARD_SLOT_TRINKET2] = INVSLOT_TRINKET2,
}

local generalSpellBookCache = nil

-- Whether an itemID is trackable (has an on-use spell or proc data) is static for
-- a given item, so memoize it instead of calling C_Item.GetItemSpell on every scan.
local trackableItemCache = {}

-- ScanOwnedItems walks every bag + equipment slot and is called once per tracker
-- per refresh. Ownership only changes on bag/equipment/spellbook changes, so cache
-- the scan result and invalidate it from those events (see the event frame below).
local ownedItemsCache = nil

local function MakeEntry(kind, id)
    return {
        kind = kind,
        id = id,
    }
end

local function IsSpellEntry(entry)
    return entry and entry.kind == "spell"
end

local function IsWildcardSlotEntry(entry)
    return entry and entry.kind == ENTRY_KIND_WILDCARD_SLOTS
end

local function IsWildcardSlotID(slotID)
    return slotID == WILDCARD_SLOT_TRINKET1 or slotID == WILDCARD_SLOT_TRINKET2
end

local function GetWildcardSlotItemID(slotID)
    local inventorySlot = WILDCARD_SLOT_INVENTORY_SLOTS[slotID]
    if not inventorySlot then
        return nil
    end
    local location = ItemLocation:CreateFromEquipmentSlot(inventorySlot)
    if location:IsValid() then
        return C_Item.GetItemID(location)
    end
    return nil
end

local function EntriesEqual(a, b)
    return a and b and a.kind == b.kind and a.id == b.id
end

local function AddSpellIDFromSpellBook(ids, spellID)
    if not spellID or spellID == AUTO_ATTACK_SPELL_ID then
        return
    end
    local isPassive = (C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID))
        or (IsPassiveSpell and IsPassiveSpell(spellID))
        or false
    if not isPassive then
        ids[spellID] = true
    end
end

local function GetSpellIDsFromGeneralSpellBook()
    if generalSpellBookCache then
        return generalSpellBookCache
    end

    local ids = {}
    if not C_SpellBook or not C_SpellBook.GetSpellBookSkillLineInfo or not C_SpellBook.GetSpellBookItemInfo then
        return ids
    end

    local spellBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or nil
    local spellItemType = Enum and Enum.SpellBookItemType or nil
    if not spellBank or not spellItemType then
        return ids
    end

    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(1)
    if not skillLineInfo then
        return ids
    end

    local offset = skillLineInfo.itemIndexOffset or 0
    local numSlots = skillLineInfo.numSpellBookItems or 0
    for spellBookIndex = offset + 1, offset + numSlots do
        local itemInfo = C_SpellBook.GetSpellBookItemInfo(spellBookIndex, spellBank)
        if itemInfo then
            local spellID = itemInfo.spellID or itemInfo.actionID
            local itemType = itemInfo.itemType

            if itemType == spellItemType.Spell or itemType == spellItemType.FutureSpell then
                AddSpellIDFromSpellBook(ids, spellID)
            elseif
                itemType == spellItemType.Flyout
                and spellID
                and not IGNORED_FLYOUT_IDS[spellID]
                and GetFlyoutInfo
                and GetFlyoutSlotInfo
            then
                local _, _, flyoutNumSlots = GetFlyoutInfo(spellID)
                for flyoutSlot = 1, flyoutNumSlots or 0 do
                    local flyoutSpellID, _, isKnown = GetFlyoutSlotInfo(spellID, flyoutSlot)
                    if isKnown then
                        AddSpellIDFromSpellBook(ids, flyoutSpellID)
                    end
                end
            end
        end
    end

    generalSpellBookCache = ids
    return ids
end

function ItemsData:InvalidateSpellBookCache()
    generalSpellBookCache = nil
end

function ItemsData:GetItemNameByID(itemID)
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(itemID)
    end
    local name = C_Item.GetItemInfo(itemID)
    return name
end

function ItemsData:GetEntryName(kind, id)
    if kind == ENTRY_KIND_WILDCARD_SLOTS then
        return WILDCARD_SLOT_DISPLAY_NAMES[id] or tostring(id)
    end
    if kind == "spell" then
        if C_Spell and C_Spell.GetSpellName then
            return C_Spell.GetSpellName(id)
        end
        if GetSpellInfo then
            local name = GetSpellInfo(id)
            return name
        end
        return nil
    end
    return self:GetItemNameByID(id)
end

local function GetEntrySettings(entry)
    if entry.wildcardSlotID then
        return DB.GetWildcardSlotSettings(entry.wildcardSlotID)
    end
    if IsWildcardSlotEntry(entry) then
        return DB.GetWildcardSlotSettings(entry.id)
    end
    if IsSpellEntry(entry) then
        return DB.GetSpellItemSettings(entry.id)
    end
    return DB.GetItemSettings(entry.id)
end

local function SortEntries(entries)
    table.sort(entries, function(a, b)
        local aSettings = GetEntrySettings(a)
        local bSettings = GetEntrySettings(b)
        local aOrder = aSettings and aSettings.order or nil
        local bOrder = bSettings and bSettings.order or nil
        if aOrder ~= nil and bOrder ~= nil and aOrder ~= bOrder then
            return aOrder < bOrder
        elseif aOrder ~= nil and bOrder == nil then
            return true
        elseif aOrder == nil and bOrder ~= nil then
            return false
        end
        local aName = ItemsData:GetEntryName(a.kind, a.id)
        aName = (not aName or aName == "") and tostring(a.id) or aName:lower()
        local bName = ItemsData:GetEntryName(b.kind, b.id)
        bName = (not bName or bName == "") and tostring(b.id) or bName:lower()
        if aName ~= bName then
            return aName < bName
        end
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        return a.id < b.id
    end)
end

local function GetEntryOrder(entry)
    local settings = GetEntrySettings(entry)
    return settings and settings.order or nil
end

local function SetEntryOrder(entry, order)
    local settings
    if entry.wildcardSlotID then
        settings = DB.EnsureWildcardSlotSettings(entry.wildcardSlotID)
    elseif IsWildcardSlotEntry(entry) then
        settings = DB.EnsureWildcardSlotSettings(entry.id)
    elseif IsSpellEntry(entry) then
        settings = DB.EnsureSpellItemSettings(entry.id)
    else
        settings = DB.EnsureItemSettings(entry.id)
    end
    settings.order = order
end

local function EnsureOrderForEntries(entries)
    local maxOrder = 0
    for _, entry in ipairs(entries) do
        local order = GetEntryOrder(entry)
        if order and order > maxOrder then
            maxOrder = order
        end
    end

    for _, entry in ipairs(entries) do
        if GetEntryOrder(entry) == nil then
            maxOrder = maxOrder + 1
            SetEntryOrder(entry, maxOrder)
        end
    end
end

function ItemsData:InsertItemAt(state, entry, targetEntry, insertBefore)
    if not entry then
        return
    end

    local entries = self:GetEntriesByState(state)
    local existingIndex = nil
    for index, candidate in ipairs(entries) do
        if EntriesEqual(candidate, entry) then
            existingIndex = index
            break
        end
    end

    if existingIndex then
        table.remove(entries, existingIndex)
    end

    local insertIndex = #entries + 1
    if targetEntry then
        for index, candidate in ipairs(entries) do
            if EntriesEqual(candidate, targetEntry) then
                insertIndex = insertBefore and index or (index + 1)
                break
            end
        end
    end

    table.insert(entries, insertIndex, MakeEntry(entry.kind, entry.id))
    for index, e in ipairs(entries) do
        SetEntryOrder(e, index)
    end
end

function ItemsData:GetEntryState(kind, id)
    if kind == ENTRY_KIND_WILDCARD_SLOTS then
        return DB.GetWildcardSlotState(id)
    end
    if kind == "spell" then
        return DB.GetSpellItemState(id)
    end
    return DB.GetItemState(id)
end

function ItemsData:SetEntryState(kind, id, state)
    if kind == ENTRY_KIND_WILDCARD_SLOTS then
        DB.SetWildcardSlotState(id, state)
        return
    end
    if kind == "spell" then
        DB.SetSpellItemState(id, state)
    else
        DB.SetItemState(id, state)
    end
end

-- Proc trinkets often have no on-use spell (their effect is an equip proc), so
-- GetItemSpell can't see them. Treat anything with proc data as trackable too.
local function IsProcDataItem(itemID)
    local data = ns.TrackerAuraData
    return itemID ~= nil and data ~= nil and data.procByItemID ~= nil and data.procByItemID[itemID] ~= nil
end

local function IsTrackableItem(itemID)
    if not itemID then
        return false
    end
    local cached = trackableItemCache[itemID]
    if cached ~= nil then
        return cached
    end
    local result = (C_Item.GetItemSpell(itemID) ~= nil) or IsProcDataItem(itemID)
    trackableItemCache[itemID] = result
    return result
end

local function IsTrackableWildcardSlot(slotID)
    local itemID = GetWildcardSlotItemID(slotID)
    return itemID ~= nil and IsTrackableItem(itemID) and not IGNORED_WILDCARD_TRINKETS[itemID]
end

local function DoScanOwnedItems()
    local owned = {
        items = {},
        spells = {},
        wildcardSlots = {},
    }

    if C_Container and NUM_BAG_SLOTS then
        for bag = 0, NUM_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID then
                    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
                    if classID == Enum.ItemClass.Consumable then
                        owned.items[itemID] = true
                    end
                end
            end
        end
    end

    for slot = ITEM_EQUIP_FIRST, ITEM_EQUIP_LAST do
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location and C_Item.DoesItemExist(location) then
            local itemID = C_Item.GetItemID(location)
            if itemID and IsTrackableItem(itemID) then
                owned.items[itemID] = true
            end
        end
    end

    do
        local db = DB.GetDB()
        for spellID in pairs(db.spellItemSettings or {}) do
            local override = C_Spell.GetOverrideSpell(spellID)
            if not C_Spell.IsSpellPassive(override) and C_SpellBook.IsSpellInSpellBook(spellID) then
                owned.spells[spellID] = true
            end
        end
    end

    owned.wildcardSlots[WILDCARD_SLOT_TRINKET1] = true
    owned.wildcardSlots[WILDCARD_SLOT_TRINKET2] = true

    return owned
end

-- Cached entry point. Consumers (EnsureTrackedItems, GetTrackerEntries,
-- CleanupHiddenEntries) treat the result as read-only, so a shared table is safe.
function ItemsData:ScanOwnedItems()
    if ownedItemsCache then
        return ownedItemsCache
    end
    ownedItemsCache = DoScanOwnedItems()
    return ownedItemsCache
end

-- Drops the cached ownership scan; rebuilt lazily on the next ScanOwnedItems call.
function ItemsData:InvalidateOwnedItemsCache()
    ownedItemsCache = nil
end

function ItemsData:ScanOwnedItemsForMiscPanel()
    -- Build fresh: this path overwrites owned.spells, which would corrupt the
    -- shared cached table returned by ScanOwnedItems.
    local owned = DoScanOwnedItems()
    owned.spells = {}
    for spellID in pairs(GetSpellIDsFromGeneralSpellBook()) do
        owned.spells[spellID] = true
    end
    return owned
end

local ownedItemsEventFrame = CreateFrame("Frame")
for _, event in ipairs({
    "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED",
    "ITEM_LOCKED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_TALENT_UPDATE",
    "SPELLS_CHANGED",
}) do
    ownedItemsEventFrame:RegisterEvent(event)
end
ownedItemsEventFrame:SetScript("OnEvent", function(_, event)
    ownedItemsCache = nil
    if event == "PLAYER_ENTERING_WORLD" then
        wipe(trackableItemCache)
    end
end)

function ItemsData:EnsureTrackedItems(owned)
    local ownedItems = owned and owned.items or {}
    local ownedSpells = owned and owned.spells or {}
    local ownedWildcardSlots = owned and owned.wildcardSlots or {}

    for itemID in pairs(ownedItems) do
        local state = DB.GetItemState(itemID)
        if state == nil then
            DB.SetItemState(itemID, ITEM_STATE_HIDDEN)
        end
    end

    for spellID in pairs(ownedSpells) do
        local state = DB.GetSpellItemState(spellID)
        if state == nil then
            DB.SetSpellItemState(spellID, ITEM_STATE_HIDDEN)
        end
    end

    for slotID in pairs(ownedWildcardSlots) do
        if IsWildcardSlotID(slotID) then
            local state = DB.GetWildcardSlotState(slotID)
            if state == nil then
                DB.SetWildcardSlotState(slotID, ITEM_STATE_HIDDEN)
            end
        end
    end
end

function ItemsData:GetEntriesByState(state)
    local entries = {}
    local db = DB.GetDB()

    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == state then
            table.insert(entries, MakeEntry("item", itemID))
        end
    end

    for spellID, settings in pairs(db.spellItemSettings or {}) do
        if settings.state == state then
            table.insert(entries, MakeEntry("spell", spellID))
        end
    end

    for slotID, settings in pairs(db.wildcardSlotSettings or {}) do
        if settings.state == state and IsWildcardSlotID(slotID) then
            table.insert(entries, MakeEntry(ENTRY_KIND_WILDCARD_SLOTS, slotID))
        end
    end

    EnsureOrderForEntries(entries)
    SortEntries(entries)
    return entries
end

function ItemsData:CleanupHiddenEntries(owned)
    local ownedItems = owned and owned.items or {}
    local ownedSpells = owned and owned.spells or {}

    local db = DB.GetDB()
    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == ITEM_STATE_HIDDEN and not ownedItems[itemID] then
            DB.SetItemState(itemID, nil)
        end
    end

    for spellID, settings in pairs(db.spellItemSettings or {}) do
        if settings.state == ITEM_STATE_HIDDEN and not ownedSpells[spellID] then
            DB.SetSpellItemState(spellID, nil)
        end
    end
end

function ItemsData:GetItemIDsByState(state)
    local entries = self:GetEntriesByState(state)
    local ids = {}
    for _, entry in ipairs(entries) do
        if entry.kind == "item" then
            table.insert(ids, entry.id)
        end
    end
    return ids
end

-- Returns the item-state string for tracker `index` (1-based): "tracker1", "tracker2", ...
function ItemsData:GetTrackerStateName(index)
    return "tracker" .. index
end

-- Returns the numeric tracker index for a state string, or nil if it isn't a tracker state.
function ItemsData:GetTrackerIndexFromState(state)
    if type(state) ~= "string" then
        return nil
    end
    local n = state:match("^tracker(%d+)$")
    return n and tonumber(n) or nil
end

-- True when `state` names a tracker bucket (as opposed to "hidden" / nil).
function ItemsData:IsTrackerState(state)
    return self:GetTrackerIndexFromState(state) ~= nil
end

-- Returns the displayable entries assigned to tracker `index`, honouring `owned`
-- filtering (unowned entries are skipped unless alwaysShow) and resolving wildcard
-- slots to plain item entries so downstream handling is uniform.
function ItemsData:GetTrackerEntries(index, owned)
    local state = self:GetTrackerStateName(index)
    local entries = {}
    local db = DB.GetDB()
    local ownedItems = owned and owned.items or {}
    local ownedSpells = owned and owned.spells or {}
    local ownedWildcardSlots = owned and owned.wildcardSlots or {}
    local addedItemIDs = {} -- prevent duplicate entries when a wildcard item is also explicitly tracked

    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == state and (ownedItems[itemID] or settings.alwaysShow) then
            local e = MakeEntry("item", itemID)
            addedItemIDs[itemID] = true
            table.insert(entries, e)
        end
    end

    for spellID, settings in pairs(db.spellItemSettings or {}) do
        if settings.state == state and (ownedSpells[spellID] or settings.alwaysShow) then
            local e = MakeEntry("spell", spellID)
            table.insert(entries, e)
        end
    end

    -- Wildcard slots are resolved to plain item entries so the tracker handles them
    -- identically to explicitly-tracked items (no special-casing needed downstream).
    for slotID, settings in pairs(db.wildcardSlotSettings or {}) do
        if
            settings.state == state
            and (ownedWildcardSlots[slotID] or settings.alwaysShow)
            and IsTrackableWildcardSlot(slotID)
        then
            local itemID = GetWildcardSlotItemID(slotID)
            if itemID and not addedItemIDs[itemID] then
                local e = MakeEntry("item", itemID)
                e.wildcardSlotID = slotID -- retains slot identity for ordering and instant-remove
                table.insert(entries, e)
            end
        end
    end

    EnsureOrderForEntries(entries)
    SortEntries(entries)
    return entries
end

-- True when no item / spell / wildcard slot is assigned to tracker `index`,
-- regardless of ownership. Used to gate removal of the trailing tracker.
function ItemsData:IsTrackerEmpty(index)
    local state = self:GetTrackerStateName(index)
    local db = DB.GetDB()
    for _, settings in pairs(db.itemSettings or {}) do
        if settings.state == state then
            return false
        end
    end
    for _, settings in pairs(db.spellItemSettings or {}) do
        if settings.state == state then
            return false
        end
    end
    for _, settings in pairs(db.wildcardSlotSettings or {}) do
        if settings.state == state then
            return false
        end
    end
    return true
end

ItemsData.ITEM_STATE_HIDDEN = ITEM_STATE_HIDDEN
ItemsData.ITEM_STATE_TRACKER1 = ITEM_STATE_TRACKER1
ItemsData.ENTRY_KIND_WILDCARD_SLOTS = ENTRY_KIND_WILDCARD_SLOTS
ItemsData.WILDCARD_SLOT_TRINKET1 = WILDCARD_SLOT_TRINKET1
ItemsData.WILDCARD_SLOT_TRINKET2 = WILDCARD_SLOT_TRINKET2

function ItemsData:GetWildcardSlotItemID(slotID)
    return GetWildcardSlotItemID(slotID)
end

function ItemsData:GetEntryOrder(entry)
    return GetEntryOrder(entry)
end

function ItemsData:IsTrackableItem(itemID)
    return IsTrackableItem(itemID)
end
