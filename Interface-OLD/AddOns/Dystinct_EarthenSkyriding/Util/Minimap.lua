local addonName, addon = ...

local DEFAULT_ANGLE = 225
local RADIUS = 104

local function UpdatePosition(angle)
    local rads = math.rad(angle)
    addon.minimapButton:ClearAllPoints()
    addon.minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(rads) * RADIUS,
        math.sin(rads) * RADIUS)
end

local function OnDragStart(self)
    self.isDragging = true
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        addon.data.minimap.angle = angle
        UpdatePosition(angle)
    end)
end

local function OnDragStop(self)
    self.isDragging = false
    self:SetScript("OnUpdate", nil)
end

local function InitializeContextMenu(frame, level)
    local info

    info = UIDropDownMenu_CreateInfo()
    info.text = "Dystinct Earthen Skyriding"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Toggle Window"
    info.notCheckable = true
    info.func = function()
        addon.ui:SetShown(not addon.ui:IsShown())
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Map Overlay"
    info.isNotRadio = true
    info.checked = addon.data.waypoints.mapOverlay
    info.keepShownOnClick = true
    info.func = function()
        addon.data.waypoints.mapOverlay = not addon.data.waypoints.mapOverlay
        addon:RefreshWorldMapOverlay()
        addon:RefreshMinimapOverlay()
        addon.ui.SettingsFrame:Refresh()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Previous Node"
    info.notCheckable = true
    info.disabled = not addon.active or not addon.waypoint.index
    info.func = function()
        DysES_GoToPreviousNode()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Advance Node"
    info.notCheckable = true
    info.disabled = not addon.active or not addon.waypoint.index
    info.func = function()
        DysES_MarkCurrentDiscovered()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Previous Segment"
    info.notCheckable = true
    info.disabled = not addon.active or not addon:FindPreviousLeaf(addon.menu[addon.active.path[1]], addon.active.path)
    info.func = function()
        addon:JumpToPreviousSegment()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Advance Segment"
    info.notCheckable = true
    info.disabled = not addon.active or not addon:FindNextLeaf(addon.menu[addon.active.path[1]], addon.active.path)
    info.func = function()
        addon:JumpToNextSegment()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Abandon Run"
    info.notCheckable = true
    info.disabled = addon.active == nil
    info.func = function()
        addon:ClearActive()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Reset Position"
    info.notCheckable = true
    info.func = function()
        addon.ui:SetUserPlaced(false)
        addon.ui:ClearAllPoints()
        addon.ui:SetPoint("CENTER", UIParent, "CENTER")
    end
    UIDropDownMenu_AddButton(info, level)
end

function addon:InitializeMinimap()
    local button = CreateFrame("Button", "DysES_MinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface/Icons/ability_dragonriding_upwardflap01")
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(48, 48)
    border:SetPoint("TOPLEFT", 0, -1)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    local contextMenu = CreateFrame("Frame", "DysES_MinimapContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(contextMenu, InitializeContextMenu, "MENU")

    button:SetScript("OnClick", function(self, clickButton)
        if clickButton == "LeftButton" then
            addon.ui:SetShown(not addon.ui:IsShown())
        elseif clickButton == "RightButton" then
            ToggleDropDownMenu(1, nil, contextMenu, self, 0, 0)
        end
    end)

    button:SetScript("OnDragStart", OnDragStart)
    button:SetScript("OnDragStop", OnDragStop)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Dystinct Earthen Skyriding")
        GameTooltip:AddLine("Left-click to toggle window", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:AddLine("Drag to reposition", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    addon.minimapButton = button
    UpdatePosition(addon.data.minimap.angle or DEFAULT_ANGLE)
    button:SetShown(not addon.data.minimap.hidden)
end
