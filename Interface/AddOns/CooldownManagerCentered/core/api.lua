local _, ns = ...

local API = {}
ns.API = API

local LSM = LibStub("LibSharedMedia-3.0", true)

local SliceFrameMixin = {}

function SliceFrameMixin:CreatePieces(n)
    if self.pieces then
        return
    end
    self.pieces = {}
    self.numSlices = n

    for i = 1, n do
        self.pieces[i] = self:CreateTexture(nil, "BORDER")
        self.pieces[i]:ClearAllPoints()
    end

    self:SetCornerSize(16)

    if n == 3 then
        self.pieces[1]:SetPoint("CENTER", self, "LEFT", 0, 0)
        self.pieces[3]:SetPoint("CENTER", self, "RIGHT", 0, 0)
        self.pieces[2]:SetPoint("TOPLEFT", self.pieces[1], "TOPRIGHT", 0, 0)
        self.pieces[2]:SetPoint("BOTTOMRIGHT", self.pieces[3], "BOTTOMLEFT", 0, 0)

        self.pieces[1]:SetTexCoord(0, 0.25, 0, 1)
        self.pieces[2]:SetTexCoord(0.25, 0.75, 0, 1)
        self.pieces[3]:SetTexCoord(0.75, 1, 0, 1)
    elseif n == 9 then
        self.pieces[1]:SetPoint("CENTER", self, "TOPLEFT", 0, 0)
        self.pieces[3]:SetPoint("CENTER", self, "TOPRIGHT", 0, 0)
        self.pieces[7]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, 0)
        self.pieces[9]:SetPoint("CENTER", self, "BOTTOMRIGHT", 0, 0)
        self.pieces[2]:SetPoint("TOPLEFT", self.pieces[1], "TOPRIGHT", 0, 0)
        self.pieces[2]:SetPoint("BOTTOMRIGHT", self.pieces[3], "BOTTOMLEFT", 0, 0)
        self.pieces[4]:SetPoint("TOPLEFT", self.pieces[1], "BOTTOMLEFT", 0, 0)
        self.pieces[4]:SetPoint("BOTTOMRIGHT", self.pieces[7], "TOPRIGHT", 0, 0)
        self.pieces[5]:SetPoint("TOPLEFT", self.pieces[1], "BOTTOMRIGHT", 0, 0)
        self.pieces[5]:SetPoint("BOTTOMRIGHT", self.pieces[9], "TOPLEFT", 0, 0)
        self.pieces[6]:SetPoint("TOPLEFT", self.pieces[3], "BOTTOMLEFT", 0, 0)
        self.pieces[6]:SetPoint("BOTTOMRIGHT", self.pieces[9], "TOPRIGHT", 0, 0)
        self.pieces[8]:SetPoint("TOPLEFT", self.pieces[7], "TOPRIGHT", 0, 0)
        self.pieces[8]:SetPoint("BOTTOMRIGHT", self.pieces[9], "BOTTOMLEFT", 0, 0)

        self.pieces[1]:SetTexCoord(0, 0.25, 0, 0.25)
        self.pieces[2]:SetTexCoord(0.25, 0.75, 0, 0.25)
        self.pieces[3]:SetTexCoord(0.75, 1, 0, 0.25)
        self.pieces[4]:SetTexCoord(0, 0.25, 0.25, 0.75)
        self.pieces[5]:SetTexCoord(0.25, 0.75, 0.25, 0.75)
        self.pieces[6]:SetTexCoord(0.75, 1, 0.25, 0.75)
        self.pieces[7]:SetTexCoord(0, 0.25, 0.75, 1)
        self.pieces[8]:SetTexCoord(0.25, 0.75, 0.75, 1)
        self.pieces[9]:SetTexCoord(0.75, 1, 0.75, 1)
    end
end

function SliceFrameMixin:SetCornerSize(a)
    if self.numSlices == 3 then
        self.pieces[1]:SetSize(a, 2 * a)
        self.pieces[3]:SetSize(a, 2 * a)
    elseif self.numSlices == 9 then
        self.pieces[1]:SetSize(a, a)
        self.pieces[3]:SetSize(a, a)
        self.pieces[7]:SetSize(a, a)
        self.pieces[9]:SetSize(a, a)
    end
end

function SliceFrameMixin:SetCornerSizeByScale(scale)
    self:SetCornerSize(16 * scale)
end

function SliceFrameMixin:SetTexture(tex)
    for i = 1, #self.pieces do
        self.pieces[i]:SetTexture(tex)
    end
end

function SliceFrameMixin:SetDisableSharpening(state)
    for i = 1, #self.pieces do
        self.pieces[i]:SetSnapToPixelGrid(not state)
    end
end

function SliceFrameMixin:SetColor(r, g, b)
    for i = 1, #self.pieces do
        self.pieces[i]:SetVertexColor(r, g, b)
    end
end

function SliceFrameMixin:CoverParent(padding)
    padding = padding or 0
    local parent = self:GetParent()
    if parent then
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "TOPLEFT", -padding, padding)
        self:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", padding, -padding)
    end
end

function SliceFrameMixin:ShowBackground(state)
    for _, piece in ipairs(self.pieces) do
        piece:SetShown(state)
    end
end

---Available nine-slice layout styles
local NineSliceLayouts = {
    Dark = true,
}

---Create a nine-slice frame with custom border texture
---@param parent Frame Parent frame to attach the nine-slice to
---@param layoutName? string Layout name from NineSliceLayouts
---@return Frame nineSliceFrame Frame with SliceFrameMixin methods (SetCornerSize, CoverParent, etc.)
function API:CreateNineSliceFrame(parent, layoutName)
    if not (layoutName and NineSliceLayouts[layoutName]) then
        layoutName = "Dark"
    end
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, SliceFrameMixin)
    f:CreatePieces(9)
    f:SetTexture("Interface/AddOns/CooldownManagerCentered/Media/Art/" .. layoutName)
    f:ClearAllPoints()
    return f
end

-- Per-frame "affected" markers. CMC tracks which features it has applied to a
-- frame (icon, viewer, etc.) under a shared `frame._cmc_affected` table so it
-- knows what to restore/refresh later. These helpers are the single way to
-- read/write those markers.
function API:GetIsAffected(frame, key)
    return (frame and frame._cmc_affected and frame._cmc_affected[key]) or false
end

function API:SetAffected(frame, key, value)
    if not frame then
        return
    end
    if value == nil then
        value = true
    end
    frame._cmc_affected = frame._cmc_affected or {}
    frame._cmc_affected[key] = value
end

function API:UnsetAffected(frame, key)
    if frame and frame._cmc_affected then
        frame._cmc_affected[key] = nil
    end
end

-- Returns the frame's `_cmc_affected` state table, creating it on first use.
-- All per-frame CMC state -- both the boolean "affected" markers above and the
-- object references CMC stashes on a frame (border, cooldown, masks, glow, the
-- tracker entry fields, etc.) -- lives in this single table, so a managed frame
-- carries one CMC field instead of dozens. Nil-safe: returns a throwaway table
-- when frame is nil so callers never index nil.
function API.Affected(frame)
    if not frame then
        return {}
    end
    local state = frame._cmc_affected
    if not state then
        state = {}
        frame._cmc_affected = state
    end
    return state
end

-- Returns frame:GetSize(), or nil when either dimension is unusable: zero (not laid
-- out yet) or a protected "secret" value. WoW 11.x can hand back tainted sizes for
-- reparented frames and arithmetic on those errors; issecretvalue itself may be
-- absent on older clients, so guard its existence. Callers should skip geometry math
-- and keep their last good size when this returns nil.
function API:GetSafeSize(frame)
    if not frame then
        return nil
    end
    local w, h = frame:GetSize()
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then
        return nil
    end
    if not w or not h or w <= 0 or h <= 0 then
        return nil
    end
    return w, h
end

function API:RefreshCooldownManager()
    C_Timer.After(0.01, function()
        ns.StyledIcons:RefreshAll()
        ns.CooldownManager.Initialize()
        if ns.CooldownStyle then
            ns.CooldownStyle:RefreshHooks()
        end
    end)
end

function API:IsSomeAddOnRestrictionActive()
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        for i = 0, 4 do
            if C_RestrictedActions.IsAddOnRestrictionActive(i) then
                return true
            end
        end
    end
    return false
end

StaticPopupDialogs["CMC_RELOAD_UI_ASK"] = {
    text = "Some settings won't take effect until you reload the UI. Reload now?",
    button1 = "Reload",
    button2 = "Not now",
    OnAccept = function(self, profileName)
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function API:ShowReloadUIConfirmation()
    StaticPopup_Show("CMC_RELOAD_UI_ASK")
end

function API:ToggleEditMode()
    if InCombatLockdown and InCombatLockdown() then
        ns.Addon:Print("Cannot toggle Edit Mode while in combat.")
        return
    end
    local frame = _G.EditModeManagerFrame
    if not frame then
        local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.UIParentLoadAddOn
        if loader then
            loader("Blizzard_EditMode")
            frame = _G.EditModeManagerFrame
        end
    end
    if not frame then
        return
    end
    if frame.CanEnterEditMode and not frame:CanEnterEditMode() then
        ns.Addon:Print("Cannot enter Edit Mode right now.")
        return
    end
    if frame:IsShown() then
        if HideUIPanel then
            HideUIPanel(frame)
        else
            frame:Hide()
        end
    else
        if ShowUIPanel then
            ShowUIPanel(frame)
        else
            frame:Show()
        end
    end
end

StaticPopupDialogs["CMC_ELVUI_SKINNING_ASK"] = {
    text = "ElvUI Cooldown Manager skinning is enabled. It will conflict with Cooldown Manager Centered styling. Disable ElvUI skinning?",
    button1 = "Yes, I will use CMC styling",
    button2 = "No\nI want to keep using ElvUI skinning",
    OnAccept = function(self, profileName)
        API:DisableElvUICDMSkinning()
        ReloadUI()
    end,
    OnCancel = function(self)
        StaticPopup_Show("CMC_CMC_SKINNING_ASK")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["CMC_CMC_SKINNING_ASK"] = {
    text = "Disable CMC skinning then?",
    button1 = "Yes, disable CMC styling",
    button2 = "No, I want to keep both",
    OnAccept = function(self, profileName)
        ns.db.profile.cooldownManager_normalizeUtilitySize = false
        ns.db.profile.cooldownManager_squareIcons_Essential = false
        ns.db.profile.cooldownManager_squareIcons_Utility = false
        ns.db.profile.cooldownManager_squareIcons_BuffIcons = false
        ns.db.profile.cooldownManager_stackAnchorEssential_enabled = false
        ns.db.profile.cooldownManager_stackAnchorUtility_enabled = false
        ns.db.profile.cooldownManager_stackAnchorBuffIcons_enabled = false

        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
function API:IsElvUICDMSkinningEnabled()
    if C_AddOns and not C_AddOns.IsAddOnLoaded("ElvUI") then
        return false
    end

    local E = ElvUI and ElvUI[1]
    if not E or not E.private then
        return false
    end

    local skins = E.private.skins
    if not skins or not skins.blizzard then
        return false
    end

    return skins.blizzard.enable and skins.blizzard.cooldownManager
end

function API:DisableElvUICDMSkinning()
    if C_AddOns and not C_AddOns.IsAddOnLoaded("ElvUI") then
        return false
    end

    local E = ElvUI and ElvUI[1]
    if not E or not E.private then
        return false
    end

    local skins = E.private.skins
    if not skins or not skins.blizzard then
        return false
    end

    skins.blizzard.cooldownManager = false
    return true
end

function API:GetTableLength(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function AddSpellToTracking(spellID, state)
    if InCombatLockdown() then
        return nil, "Cannot add spell to tracking while in combat."
    end

    -- local overrideSpell = C_Spell.GetOverrideSpell(spellID)
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    local isUsable = C_Spell.DoesSpellExist(baseSpellID)
    if not isUsable then
        return nil, "Spell does not exist."
    end

    local target = state or ns.TrackerItemsData.ITEM_STATE_TRACKER1
    ns.TrackerItemsData:SetEntryState("spell", baseSpellID, target)

    if ns.TrackerItemViewer and ns.TrackerItemViewer.ReconcileTrackerCount then
        ns.TrackerItemViewer:ReconcileTrackerCount()
    end
    if ns.TrackerAssignmentPanel and ns.TrackerAssignmentPanel.RefreshMiscPanel then
        ns.TrackerAssignmentPanel:RefreshMiscPanel()
    end
    if ns.TrackerItemViewer and ns.TrackerItemViewer.RefreshItemViewerFrames then
        ns.TrackerItemViewer:RefreshItemViewerFrames()
    end

    return true
end

local function AddItemToTracking(itemID, state)
    if InCombatLockdown() then
        return nil, "Cannot add item to tracking while in combat."
    end

    local _spellName, spellId = C_Item.GetItemSpell(itemID)
    if not spellId then
        return nil, "Item is not usable."
    end

    local target = state or ns.TrackerItemsData.ITEM_STATE_TRACKER1
    ns.TrackerItemsData:SetEntryState("item", itemID, target)

    if ns.TrackerItemViewer and ns.TrackerItemViewer.ReconcileTrackerCount then
        ns.TrackerItemViewer:ReconcileTrackerCount()
    end
    if ns.TrackerAssignmentPanel and ns.TrackerAssignmentPanel.RefreshMiscPanel then
        ns.TrackerAssignmentPanel:RefreshMiscPanel()
    end
    if ns.TrackerItemViewer and ns.TrackerItemViewer.RefreshItemViewerFrames then
        ns.TrackerItemViewer:RefreshItemViewerFrames()
    end

    return true
end

function API:AddSpellToTracking(spellID)
    return AddSpellToTracking(spellID)
end

function API:AddItemToTracking(itemID)
    return AddItemToTracking(itemID)
end
function API:AddToTracking(kind, id, state)
    if kind == "spell" then
        return AddSpellToTracking(id, state)
    elseif kind == "item" then
        return AddItemToTracking(id, state)
    else
        return nil, "Invalid kind. Must be 'spell' or 'item'."
    end
end

function API:GetFontPath(fontName)
    if not fontName or fontName == "" or fontName == "NIL" then
        return nil
    end
    if LSM then
        local fontPath = LSM:Fetch("font", fontName)
        if fontPath then
            return fontPath
        end
    end
    return nil
end

function API:GetFontFlags(flagsTable)
    if not flagsTable then
        return ""
    end
    local parts = {}
    if flagsTable["MONOCHROME"] then
        table.insert(parts, "MONOCHROME")
    end
    if flagsTable["OUTLINE"] then
        table.insert(parts, "OUTLINE")
    end
    if flagsTable["THICKOUTLINE"] then
        table.insert(parts, "THICKOUTLINE")
    end
    if flagsTable["SLUG"] then
        table.insert(parts, "SLUG")
    end
    return table.concat(parts, ",")
end
