--[[
    LibEditMode - Minimal implementation for BliZzi_Interrupts
    Registers addon frames with WoW's Edit Mode system (introduced in Dragonflight).
    Allows moving/positioning frames via the Edit Mode UI (Game Menu → Edit Mode).
]]

local LibStub = LibStub
local MAJOR, MINOR = "LibEditMode", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.frames      = lib.frames or {}
lib.initialized = lib.initialized or false

------------------------------------------------------------
-- Internal: Check if Edit Mode system is available
------------------------------------------------------------
local function EditModeAvailable()
    return EditModeManagerFrame ~= nil
        and C_EditMode ~= nil
        and C_EditMode.GetActiveLayoutInfo ~= nil
end

------------------------------------------------------------
-- Internal: Snap a frame back to a saved position
------------------------------------------------------------
local function RestorePosition(frameInfo)
    local f   = frameInfo.frame
    local db  = frameInfo.db
    if db.x and db.y then
        f:ClearAllPoints()
        f:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x, db.y)
    end
end

------------------------------------------------------------
-- Internal: Save current frame position
------------------------------------------------------------
local function SavePosition(frameInfo)
    local f  = frameInfo.frame
    local db = frameInfo.db
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point then
        db.point    = point
        db.relPoint = relPoint or "CENTER"
        db.x        = x
        db.y        = y
    end
end

------------------------------------------------------------
-- Internal: Hook into Edit Mode enter/exit
------------------------------------------------------------
local function SetupEditModeHooks(frameInfo)
    if not EditModeAvailable() then return end

    -- When Edit Mode opens: make frame movable and show glow
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        local f  = frameInfo.frame
        local db = frameInfo.db
        if not db.locked then return end  -- already unlocked, skip

        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self)
            self:StopMovingOrSizing()
            SavePosition(frameInfo)
        end)

        -- Show a label so user knows this frame is editable
        if not f._editModeLabel then
            local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOP", f, "BOTTOM", 0, -4)
            lbl:SetText("|cFF00DDDD" .. (frameInfo.name or "BliZzi Interrupts") .. "|r")
            f._editModeLabel = lbl
        end
        f._editModeLabel:Show()

        -- Highlight border
        if not f._editModeBorder then
            local border = f:CreateTexture(nil, "OVERLAY", nil, 8)
            border:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            border:SetVertexColor(0.0, 0.85, 1.0, 0.8)
            border:SetPoint("TOPLEFT",     -2,  2)
            border:SetPoint("BOTTOMRIGHT",  2, -2)
            border:SetAlpha(0)
            f._editModeBorder = border
        end
        f._editModeBorder:SetAlpha(0.6)
    end)

    -- When Edit Mode closes: restore lock state and hide glow
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        local f  = frameInfo.frame
        local db = frameInfo.db

        SavePosition(frameInfo)

        -- Restore original mouse behaviour (respect lock setting)
        if db.locked then
            f:SetMovable(false)
        end

        if f._editModeLabel  then f._editModeLabel:Hide()  end
        if f._editModeBorder then f._editModeBorder:SetAlpha(0) end
    end)
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--- Register a frame with the Edit Mode system.
-- @param frame    The WoW Frame to register
-- @param name     Display name shown in Edit Mode
-- @param db       SavedVariables sub-table for position {x, y, point, relPoint}
function lib:RegisterFrame(frame, name, db)
    local frameInfo = {
        frame = frame,
        name  = name,
        db    = db,
    }
    table.insert(self.frames, frameInfo)

    -- Restore saved position immediately
    RestorePosition(frameInfo)

    -- Hook into Edit Mode if already available, else wait for it
    if EditModeAvailable() then
        SetupEditModeHooks(frameInfo)
    else
        -- EditModeManagerFrame may not exist yet at load time — retry on first use
        local watchFrame = CreateFrame("Frame")
        watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        watchFrame:SetScript("OnEvent", function(self)
            if EditModeAvailable() then
                SetupEditModeHooks(frameInfo)
                self:UnregisterAllEvents()
            end
        end)
    end
end

--- Utility: save position of all registered frames (call on logout/reload)
function lib:SaveAll()
    for _, frameInfo in ipairs(self.frames) do
        SavePosition(frameInfo)
    end
end
