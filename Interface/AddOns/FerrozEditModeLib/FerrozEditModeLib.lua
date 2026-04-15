local addonName = ... 
local versionString = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"
local major, minor, patch = string.match(versionString, "(%d+)%.(%d+)%.(%d+)") or "1", "0", "0"
local LIB_VERSION = (tonumber(major) * 10000) + (tonumber(minor) * 100) + tonumber(patch)
local LIB_NAME = "FerrozEditModeLib-1.0"
local lib = LibStub:NewLibrary(LIB_NAME, LIB_VERSION)
if not lib then return end --Guard, already loaded
local LSM = LibStub("LibSharedMedia-3.0")

--library variables
lib.registeredFrames = {}
lib.selectionOverlay = nil
lib.DEBUG_MODE = false

--library constants
lib.STRATA_TABLE = {
    ["BACKGROUND"] = "LOW",
    ["LOW"] = "MEDIUM",
    ["MEDIUM"] = "HIGH",
    ["HIGH"] = "DIALOG",
    ["DIALOG"] = "FULLSCREEN",
}
lib.FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")
lib.CONTAINER_PADDING = 2
lib.MIN_HEIGHT = 10
lib.MIN_WIDTH = 10
lib.MAX_WIDTH = 1200
lib.MAX_HEIGHT = 600
lib.MIN_SCALE = 0.4
lib.MAX_SCALE = 2.5
lib.MIN_OPACITY = 0
lib.MAX_OPACITY = 1
lib.SIZE_STEP = 1
lib.SCALE_STEP = 0.05
lib.OPACITY_STEP = 0.05
--debug log function
function lib:Log(...)
    if not self.DEBUG_MODE then return end

    local n = select("#", ...)
    if n == 0 then return end

    local first = select(1, ...)
    local msg
    
    -- If the first arg is a string and there are more args, assume string.format
    if type(first) == "string" and n > 1 then
        local success, formatted = pcall(string.format, ...)
        if success then
            msg = formatted
        else
            msg = table.concat({tostringall(...)}, " ")
        end
    else
        msg = table.concat({tostringall(...)}, " ")
    end

    print("|cff00ff00[FerrozLib]|r " .. msg)
end

function lib:AnnounceInit()
    --todo
end

function lib:ResolveFrame(frameOrName)
    local frame = (type(frameOrName) == "string" and _G[frameOrName]) or frameOrName or UIParent
    local name = (type(frame) == "table" and frame.GetName) and frame:GetName() or tostring(frameOrName or "UIParent")
    
    return frame, name
end

function lib:SetDirty(frame)
    frame.isDirty = true
    if not EditModeManagerFrame or EditModeManagerFrame.layoutApplyInProgress then return end

    -- The brute force flag
    EditModeManagerFrame.hasActiveChanges = true
    EditModeManagerFrame.SaveChangesButton:SetEnabled(true)
    EditModeManagerFrame.RevertAllChangesButton:SetEnabled(true)
    lib:RefreshConfigUI(frame)
end

function lib:GetCurrentLayoutName()
    if not C_EditMode or type(C_EditMode.GetLayouts) ~= "function" then 
        return "Default" 
    end

    local layoutData = C_EditMode.GetLayouts()
    if not layoutData or not layoutData.layouts then 
        return "Default" 
    end

    local activeIdx = layoutData.activeLayout
    -- presets, hard coded as 1 and 2
    if activeIdx == 1 then
        return HUD_EDIT_MODE_PRESET_MODERN or "Modern"
    elseif activeIdx ==  2 then
        return HUD_EDIT_MODE_PRESET_CLASSIC or "Classic"
    end
    --user layouts, these are offset by 2, the number of presets.  Unfortunately we can't get that dynamically
    if activeIdx then
        local directMatch = layoutData.layouts[activeIdx-2]
        if directMatch and directMatch.layoutName then
            return directMatch.layoutName
        end
    end
    return "Default"
end 

function lib:ApplyLayout(frame)
    frame.isDirty = false
    local layoutName = self:GetCurrentLayoutName()
    lib:Log("lib:ApplyLayout: " .. (frame:GetName() or "Unknown") .. " - " .. layoutName)
    local settingsTable = frame.settingsTable
    local s = settingsTable.layouts and settingsTable.layouts[layoutName]

    if s then
        local relativeTo, _unused_relativeToName = lib:ResolveFrame(s.relativeFrame)
        frame:ClearAllPoints()
        frame:SetPoint(s.point, relativeTo, s.relativePoint, s.xOfs, s.yOfs)
        frame:SetScale(s.scale or 1.0)
        frame:SetAlpha(s.opacity or 1.0)
        frame:SetAttribute("alpha-full", frame:GetAlpha() or 1.0)
        if s.height then frame:SetHeight(s.height) end
        if s.width then frame:SetWidth(s.width) end
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER")
        frame:SetScale(1.0)
        --frame:SetDefaultHeightAndWidth()
    end
end

function lib:CreateObservableState(initialData, onChange)
    local proxy = { _values = initialData or {} }
    setmetatable(proxy, {
        __index = function(t, k) return t._values[k] end,
        __newindex = function(t, k, v)
            if t._values[k] ~= v then
                t._values[k] = v
                if onChange then onChange(k, v) end
            end
        end,
        __pairs = function(t) return pairs(t._values) end
    })
    return proxy
end

function lib:ApplyState(frame, state)
    if not frame or not state then return false end
    local changed = false
    local newScale = tonumber(state.scale)
    if newScale then
        newScale = math.max(lib.MIN_SCALE, math.min(lib.MAX_SCALE, newScale))
        if math.abs(frame:GetScale() - newScale) > 0.001 then
            frame:SetScale(state.scale)
            changed = true
        end
    end
    local newOpacity = tonumber(state.opacity)
    if newOpacity then
        newOpacity = math.max(lib.MIN_OPACITY, math.min(lib.MAX_OPACITY, newOpacity))
        if math.abs(frame:GetAlpha() - newOpacity) > 0.001 then
            frame:SetAlpha(state.opacity)
            changed = true
        end
    end
    if state.point then
        local xOfs = tonumber(state.xOfs) or 0
        local yOfs = tonumber(state.yOfs) or 0
        local relFrame, _unused_relFrameName = lib:ResolveFrame(state.relativeFrame)
        local relPoint = state.relativePoint or state.point
        local curPoint, curRel, curRelPoint, curX, curY = frame:GetPoint()
        local hasMoved = (curPoint ~= state.point) or 
                        (curRel ~= relFrame) or 
                        (curRelPoint ~= relPoint) or 
                        (math.abs((curX or 0) - xOfs) > 0.1) or 
                        (math.abs((curY or 0) - yOfs) > 0.1)
        if hasMoved then
            frame:ClearAllPoints()
            frame:SetPoint(state.point, relFrame, relPoint, xOfs, yOfs)
            changed = true
        end
    end
    local targetW = tonumber(state.width)
    local targetH = tonumber(state.height)

    if targetW and math.abs(frame:GetWidth() - targetW) > 0.1 then
        frame:SetWidth(targetW)
        changed = true
    end

    if targetH and math.abs(frame:GetHeight() - targetH) > 0.1 then
        frame:SetHeight(targetH)
        changed = true
    end
    if frame.UpdateFromState then
        changed = frame:UpdateFromState(state) or changed
    end
    return changed
end

function lib:ResetPosition(frame) -- fallbackmethod until refactor is available 
    lib:ResetState(frame)
end

function lib:ResetState(frame)
    if not frame then return end
    --clear DB
    local layoutName = self:GetCurrentLayoutName()
    if frame and frame.settingsTable and frame.settingsTable.layouts and layoutName then
        frame.settingsTable.layouts[layoutName] = nil
    end

    lib:ApplyState(frame, frame.defaultState)

    lib:SnapshotWorkingState(frame)
end

--Selection
function lib:GetSelectionOverlay()
    if not self.selectionOverlay then
        local f = CreateFrame("Frame", "FerrozSelectionOverlay", UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        f:SetBackdropBorderColor(0.973, 0.851, 0.263, .8)
        f:SetBackdropColor(0.5, 0.4, 0, 0.3)
        f:SetMouseClickEnabled(false)
        f:SetPropagateMouseClicks(true)
        self.selectionOverlay = f
    end
    return self.selectionOverlay
end

function lib:AttachOverlay(targetFrame)
    EditModeManagerFrame:SelectSystem(nil)
    if EditModeSystemSettingsDialog then
        EditModeSystemSettingsDialog:Hide()
    end
    local overlay = self:GetSelectionOverlay()
    overlay:SetParent(targetFrame)
    local currentStrata = targetFrame:GetFrameStrata()
    overlay:SetFrameStrata(lib.STRATA_TABLE[currentStrata] or "TOOLTIP")
    overlay:SetFrameLevel(100)
    overlay:ClearAllPoints()
    
    overlay:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -lib.CONTAINER_PADDING, lib.CONTAINER_PADDING)
    overlay:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", lib.CONTAINER_PADDING, -lib.CONTAINER_PADDING)
    overlay:Show()
    lib:SnapshotWorkingState(targetFrame)
    self:ShowConfigForFrame(targetFrame)
end

function lib:ClearAttachOverlay()
    local overlay = self:GetSelectionOverlay()
    overlay:Hide()
    overlay:SetParent(UIParent)
    overlay:SetFrameStrata("DIALOG")
    self:ClearConfigMenu()
end

function lib:SnapshotBaseState(frame)
    local point, relFrame, rel, x, y = frame:GetPoint()
    lib:Log("Snapshotting revert position " .. (frame:GetName() or "Unknown") .. " - " .. lib:GetCurrentLayoutName())
    frame.baseState = {
        point = point,
        relativeFrame = relFrame,
        relativePoint = rel,
        xOfs = x,
        yOfs = y,
        scale = frame:GetScale(),
        height = frame:GetHeight(),
        width = frame:GetWidth(),
    }

    if frame.GetFrameSpecificSnapshot then
        local extra = frame:GetFrameSpecificSnapshot()
        for k, v in pairs(extra) do
            frame.baseState[k] = v
        end
    end
end

function lib:SnapshotWorkingState(frame)
    local point, relFrame, rel, x, y = frame:GetPoint()
    local lName = lib:GetCurrentLayoutName()
    local h = frame:GetHeight()
    local w = frame:GetWidth()
    local currentState = {
        layoutName = lName,
        point = point,
        relativeFrame = relFrame,
        relativePoint = rel,
        xOfs = x,
        yOfs = y,
        scale = frame:GetScale(),
        height = (h and h > lib.MIN_HEIGHT) and h or nil,
        width = (w and w > lib.MIN_WIDTH) and w or nil,
    }

    if frame.GetFrameSpecificSnapshot then
        local extra = frame:GetFrameSpecificSnapshot()
        for k, v in pairs(extra) do
            currentState[k] = v
        end
    end

    if not frame.workingState then
        frame.workingState = lib:CreateObservableState(currentState, function(key, value)
            if frame._isInternalSynchronize then return end
            local isDirty = lib:ApplyState(frame, frame.workingState)
            if isDirty then
                lib:SetDirty(frame)
            end
            lib:RefreshConfigUI(frame)
        end)
    else
        frame._isInternalSynchronize = true
        for k, v in pairs(currentState) do
            -- We update the proxy directly so it stays in sync
            frame.workingState[k] = v
        end
        frame._isInternalSynchronize = false
    end
    lib:RefreshConfigUI(frame)
end

-- Internal function to save current state to the active layout
function lib:CommitWorkingState(frame)
    if frame and not frame.isDirty then return end
    local cp = frame.workingState
    if not cp then return end -- Nothing new to save
    
    local layoutName = (cp and cp.layoutName) or lib:GetCurrentLayoutName()
    local _unused_relFrame,relativeFrameName = lib:ResolveFrame(cp.relativeFrame)
    lib:Log(string.format("Saving %s - %s: X=%.2f, Y=%.2f", layoutName, (frame:GetName() or "Unknown"), cp.xOfs, cp.yOfs))
    
    frame.settingsTable.layouts[layoutName] = {
        point = cp.point,
        relativePoint = cp.relativePoint,
        relativeFrame = relativeFrameName,
        xOfs = cp.xOfs,
        yOfs = cp.yOfs,
        scale = cp.scale,
        opacity = cp.opacity,
        height = cp.height,
        width = cp.width,
    }
    if frame.CommitFrameSpecificFields then
        frame:CommitFrameSpecificFields()
    end
    frame.isDirty = false
    lib:SnapshotBaseState(frame)
    lib:RefreshConfigUI(frame)
end

function lib:RevertState(frame)
    if not frame or not frame.baseState or not frame.isDirty then return end
    frame._isInternalSynchronize = true
    lib:ApplyState(frame,frame.baseState)
    lib:SnapshotWorkingState(frame)
    frame._isInternalSynchronize = false
    frame.isDirty = false
    lib:RefreshConfigUI(frame)
end

local function GetAnchorXY(frame, anchor)
    local left, bottom, width, height = frame:GetRect()
    if not left then return 0, 0 end
    
    local x, y
    -- Handle Horizontal
    if anchor:find("LEFT") then x = left
    elseif anchor:find("RIGHT") then x = left + width
    else x = left + (width / 2) end -- CENTER
    
    -- Handle Vertical
    if anchor:find("TOP") then y = bottom + height
    elseif anchor:find("BOTTOM") then y = bottom
    else y = bottom + (height / 2) end -- CENTER
    
    return x, y
end

function lib:ReanchorFrame(frame)
    local state = frame.workingState
    if not state or not state.point then return end
    
    local relFrame, _unused_relFrameName = lib:ResolveFrame(state.relativeFrame)

    -- 1. Where on the SCREEN is the point we are attaching TO?
    local targetX, targetY = GetAnchorXY(relFrame, state.relativePoint or state.point)
    
    -- 2. Where on the SCREEN is the point on our frame we are attaching FROM?
    local sourceX, sourceY = GetAnchorXY(frame, state.point)
    
    -- 3. The difference is our offset
    local xOfs = sourceX - targetX
    local yOfs = sourceY - targetY
    
    -- 4. Scale Correction
    -- WoW's SetPoint offsets are relative to the frame's own scale.
    local frameScale = frame:GetScale() or 1

    frame:ClearAllPoints()
    frame:SetPoint(
        state.point, 
        relFrame, 
        state.relativePoint or state.point, 
        xOfs , 
        yOfs
    )
end

-- The Registration Core
function lib:Register(frame, settingsTable, defaultState)
    frame.settingsTable = settingsTable
    frame.isEditing = false
    frame.isDirty = false
    --create default state
    local ds = {
        point = "CENTER",
        relativeFrame = UIParent,
        relativePoint = "CENTER",
        xOfs = 0,
        yOfs = 0,
        scale = frame:GetScale() or 1.0,
        opacity = frame:GetAlpha() or 1.0,
        height = frame:GetHeight() or lib.MIN_HEIGHT,
        width = frame:GetWidth() or lib.MIN_WIDTH,
    }
    if type(defaultState) == "table" then
        for k, v in pairs(defaultState) do
            ds[k] = v
        end
    end
    --reinforce minimums
    ds.height = math.max(lib.MIN_HEIGHT, ds.height)
    ds.width = math.max(lib.MIN_WIDTH, ds.width)
    ds.scale = math.max(lib.MIN_SCALE, ds.scale) -- Don't let scale go to 0!    
    ds.opacity = math.max(lib.MIN_OPACITY, ds.opacity)
    frame.defaultState = ds
    settingsTable.layouts = settingsTable.layouts or {}
    Mixin(frame, EditModeSystemMixin)
    frame.systemIndex = Enum.EditModeSystem.UnitFrame 
    if(frame.systemName == nil) then
        frame.systemName = frame:GetName() or frame:GetDebugName()
    end
    lib:Log(frame.systemName)

    RunNextFrame(function()
        lib:ApplyLayout(frame)
    end)

    -- 1. Scaling Logic
    frame:SetScript("OnMouseWheel", function(self, delta)
        if self.isEditing then
            local centerX, centerY = self:GetCenter()
            local oldScale = self:GetScale()
            local newScale = math.max(0.4, math.min(2.5, oldScale + (delta * 0.05)))
            self:SetScale(newScale)
            if centerX and centerY then
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (centerX * oldScale) / newScale, (centerY * oldScale) / newScale)
            end
            lib:SetDirty(self)
            lib:SnapshotWorkingState(self)
        end
    end)

    -- 2. Drag Logic
    frame:SetScript("OnDragStart", function(self)
        if self.isEditing then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        lib:ReanchorFrame(frame)
        lib:SetDirty(self)
        lib:SnapshotWorkingState(self)
    end)
    frame:HookScript("OnMouseDown", function(self, button)
        if self.isEditing and button == "LeftButton" then
            lib:AttachOverlay(self)
        end
    end)

    -- Add to the library's internal tracker
    table.insert(lib.registeredFrames, frame)

end

if not lib.HooksInitialized then
    -- Blizzard Handshake (EventRegistry)
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if InCombatLockdown() then return end
        for _, f in ipairs(lib.registeredFrames) do
            lib:ApplyLayout(f)
            f.isEditing = true
            f:EnableMouse(true)
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            lib:SnapshotBaseState(f)
            if f.EditModeStartMock then f:EditModeStartMock() end
        end
    end)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        for _, f in ipairs(lib.registeredFrames) do
            if f.isEditing then
                f:StopMovingOrSizing()
            end
            f.isEditing = false
            f:EnableMouse(false)
            f:SetMovable(false)
            if f.EditModeStopMock then f:EditModeStopMock() end
        end 
        lib:ClearAttachOverlay()
    end)

    hooksecurefunc(EditModeManagerFrame, "SelectLayout", function(self, layoutInfo)
        RunNextFrame(function()
            lib:Log("hooksecurefunc(EditModeManagerFrame, OnLayoutSelected")
            for _, f in ipairs(lib.registeredFrames or {}) do
                -- 1. Move frame to its position in the NEW layout
                if f.settingsTable then
                    lib:ApplyLayout(f)
                end
            end
        end)
    end)

    hooksecurefunc(EditModeManagerFrame, "SaveLayouts", function()
        lib:Log("Manager SaveLayouts detected!")
        for _, f in ipairs(lib.registeredFrames) do
            lib:CommitWorkingState(f)      -- Save to its specific table
        end
    end)

    -- This catches Golden Button AND the "Discard" button on the Popup
    hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", function()
        lib:Log("Revert All changes")
        if EditModeManagerFrame.isSaving then return end 
    
        for _, f in ipairs(lib.registeredFrames or {}) do
            if f.baseState then
                lib:RevertState(f)
            end
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(self, frame)
        lib:ClearAttachOverlay()
    end)

    if EditModeManagerFrame.RevertAllChangesButton then
        EditModeManagerFrame.RevertAllChangesButton:HookScript("OnClick", function()
            lib:Log("Physical Revert Button Clicked")
            for _, f in ipairs(lib.registeredFrames or {}) do
                if f.baseState then
                    lib:RevertState(f)
                end
            end
        end)
    end

    lib.HooksInitialized = true
end