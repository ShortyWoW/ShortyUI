local addonName, ns = ...
local lib = LibStub:GetLibrary("FerrozEditModeLib-1.0")
local LSM = LibStub("LibSharedMedia-3.0")

lib.CONFIG_FRAME_WIDTH = 400
lib.CONFIG_FRAME_HALF_WIDTH = lib.CONFIG_FRAME_WIDTH / 2
lib.CONFIG_FRAME_HEIGHT = 400
lib.CONFIG_FRAME_PADDING = 10
lib.CONFIG_EDIT_BOX_WIDTH = 145 --I think technically this gets ignored
lib.CONFIG_EDIT_BOX_HEIGHT = 26
lib.CONFIG_BUTTON_HEIGHT = lib.CONFIG_EDIT_BOX_HEIGHT
lib.CONFIG_ROW_HEIGHT = 30
lib.CONFIG_ROW_LABEL_WIDTH = 45
lib.CONFIG_ROW_SPACING = 5
lib.ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
}
lib.DEFAULT_MEDIA ={
    statusbar = {
        { name = " Default", path = [[Interface\Buttons\WHITE8X8]] },
        { name = "Blizzard", path = [[Interface\TargetingFrame\UI-StatusBar]] },
        { name = "Raid", path = [[Interface\RaidFrame\Raid-Bar-Hp-Fill]] },
        { name = "Glow", path = [[Interface\TargetingFrame\UI-StatusBar-Glow]] },
        { name = "Classic", path = [[Interface\TargetingFrame\UI-TargetingFrame-BarFill]] },
    },
    font= {
        {name = " Default", path = [[Fonts\FRIZQT__.TTF]] },
        { name = "Arial", path = [[Fonts\ARIALN.TTF]] },
        { name = "Skurri", path = [[Fonts\skurri.ttf]] },
        { name = "Morpheus", path = [[Fonts\MORPHEUS.ttf]] }
    }
}
-- rounds toward zero regardless of positive or negative
function lib:RoundCoordinates(num)
    local val = (num > 0) and math.floor(num) or math.ceil(num)
    return tostring(val)
end

function lib:NormalizePath(p)
    local path = tostring(p or "") 
    path = path:lower():gsub("\\\\", "\\")
    path = path:gsub("%.blp$", ""):gsub("%.tga$", ""):gsub("%.ttf$", "")
    return path
end

function lib:GetMediaNameFromPath(mediaType, path)
    if not path then return "Unknown" end
    local defaults = lib.DEFAULT_MEDIA[mediaType]
    local normalizedInput = lib:NormalizePath(path)

    -- 1. Check Defaults
    for _, item in ipairs(defaults) do
        -- Check against the normalized string path
        if lib:NormalizePath(item.path) == normalizedInput then 
            return item.name 
        end
        -- ALSO check if the input is a number that matches a known FileID
        -- (This handles 130871 matching your " Default" bar)
        if type(path) == "number" and item.fileID == path then
            return item.name
        end
    end

    -- 2. Check LibSharedMedia
    if LSM then
        local keys = LSM:List(mediaType)
        for _, name in ipairs(keys) do
            local lsmPath = LSM:Fetch(mediaType, name)
            if lib:NormalizePath(lsmPath) == normalizedInput then
                return name
            end
        end
    end

    return "Custom"
end

function lib:AddElementRow(container, content)
    container.nextIndex = (container.nextIndex or 0) + 1
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(lib.CONFIG_FRAME_WIDTH, lib.CONFIG_ROW_HEIGHT)
    row.layoutIndex = container.nextIndex

    if content then
        content:SetParent(row)
        content:SetAllPoints(row)
    end
    return row
end

function lib:CreateLabelElementPair(container, labelText, element, totalWidth, labelWidth)
    totalWidth = totalWidth or lib.CONFIG_FRAME_WIDTH
    labelWidth = labelWidth or lib.CONFIG_ROW_LABEL_WIDTH
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(totalWidth, lib.CONFIG_ROW_HEIGHT)
    row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Label:SetSize(labelWidth, lib.CONFIG_ROW_HEIGHT)
    row.Label:SetPoint("LEFT", row, "LEFT", lib.CONFIG_FRAME_PADDING, 0)
    row.Label:SetText(labelText)
    row.Label:SetJustifyH("LEFT")
    if element then
        element:SetParent(row)
        element:ClearAllPoints()
        element:SetPoint("LEFT", row.Label, "RIGHT", lib.CONFIG_FRAME_PADDING, 0)
        element:SetPoint("RIGHT", row, "RIGHT", -lib.CONFIG_FRAME_PADDING, 0)
    end
    return row
end

function lib:AddLabelElementRow(container, labelText, element, totalWidth, labelWidth)
    totalWidth = totalWidth or lib.CONFIG_FRAME_WIDTH
    labelWidth = labelWidth or lib.CONFIG_ROW_LABEL_WIDTH
    local row = lib:CreateLabelElementPair(container, labelText, element, totalWidth, labelWidth)
    return lib:AddElementRow(container, row)
end
function lib:AddHR(container)
    local element = CreateFrame("Frame")
    element:SetSize(lib.CONFIG_FRAME_WIDTH, 1) 
    local texture = element:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    local r, g, b = lib.FERROZ_COLOR:GetRGB()
    texture:SetColorTexture(r, g, b, 0.4)
    local row = lib:AddElementRow(container, element)
    row:SetHeight(4) -- Give the HR row a smaller vertical footprint
    return row
end

function lib:GetOrCreateConfigFrame()
    if not self.configFrame then
        local f = CreateFrame("Frame", "FerrozEditConfigFrame", UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetFrameLevel(100)
        f:SetClampedToScreen(true)
        f:SetSize(lib.CONFIG_FRAME_WIDTH, lib.CONFIG_FRAME_HEIGHT)
        f:SetPoint("RIGHT", UIParent, "RIGHT", -100, 0)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8", -- A solid 1px-capable line
            tile = true, tileSize = 16, edgeSize = 1,    -- 1px edge for a modern look
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        f:SetBackdropBorderColor(0, 0, 0, 1) -- Pure black thin border
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.9) -- Dark grey satin feel
        --title
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -lib.CONFIG_FRAME_PADDING)
        f.title:SetText("Frame Settings")
        --close button
        f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        f.close:HookScript("OnClick", function()
            f.previousTarget = nil 
        end)
        --flex container, vertical layout
        f.flexContainer = CreateFrame("Frame", nil, f, "VerticalLayoutFrame")
        f.flexContainer.fixedWidth = lib.CONFIG_FRAME_WIDTH
        f.flexContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -f.title:GetHeight() - 2*lib.CONFIG_FRAME_PADDING)
        f.flexContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -f.title:GetHeight() - 2*lib.CONFIG_FRAME_PADDING)
        f.flexContainer.spacing = lib.CONFIG_ROW_SPACING

        --add standard elements
        f.standardControls = {}
        f.standardControls.widthControl = lib:CreateSliderRow(f.flexContainer, "Width", "width", lib.MIN_WIDTH, lib.MAX_WIDTH, lib.SIZE_STEP)
        f.standardControls.heightControl = lib:CreateSliderRow(f.flexContainer, "Height", "height", lib.MIN_HEIGHT, lib.MAX_HEIGHT, lib.SIZE_STEP)
        f.standardControls.scaleControl = lib:CreateSliderRow(f.flexContainer, "Scale", "scale", lib.MIN_SCALE, lib.MAX_SCALE, lib.SCALE_STEP)
        f.standardControls.opacityControl = lib:CreateSliderRow(f.flexContainer, "Alpha", "opacity", lib.MIN_OPACITY, lib.MAX_OPACITY, lib.OPACITY_STEP)
        f.standardControls.xControl,f.standardControls.yControl = lib:CreateXYControls(f.flexContainer)
        f.standardControls.sourceFrame, f.standardControls.sourcePoint = lib:CreateFrameAnchorControls(f.flexContainer)
        f.standardControls.relativeFrame, f.standardControls.relativePoint = lib:CreateRelativeFrameAnchorControls(f.flexContainer)
        
        f.frameSpecificControls = {}
        f.frameSpecificSocket = CreateFrame("Frame", nil, f.flexContainer)
        f.flexContainer.nextIndex = (f.flexContainer.nextIndex or 0) + 1
        f.frameSpecificSocket.layoutIndex = f.flexContainer.nextIndex
        f.frameSpecificSocket:SetPoint("LEFT")
        f.frameSpecificSocket:SetPoint("RIGHT")
        f.frameSpecificSocket.fixedWidth = lib.CONFIG_FRAME_WIDTH
        f.frameSpecificSocket:SetSize(lib.CONFIG_FRAME_WIDTH, 1)
        lib:AddHR(f.flexContainer)

        local btnWidth = (lib.CONFIG_FRAME_WIDTH-4*lib.CONFIG_FRAME_PADDING) / 3
        f.revertBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.revertBtn:SetHeight(lib.CONFIG_BUTTON_HEIGHT)
        f.revertBtn:SetText("Revert Changes")
        f.revertBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", lib.CONFIG_FRAME_PADDING , lib.CONFIG_FRAME_PADDING)
        f.revertBtn:SetScript("OnClick", function() lib:RevertState(f.target) end)
        f.revertBtn:SetWidth(btnWidth)

        f.saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.saveBtn:SetHeight(lib.CONFIG_BUTTON_HEIGHT)
        f.saveBtn:SetText("Save")
        f.saveBtn:SetPoint("BOTTOMLEFT", f.revertBtn, "BOTTOMRIGHT", lib.CONFIG_FRAME_PADDING , 0)
        f.saveBtn:SetScript("OnClick", function() lib:CommitWorkingState(f.target) end)
        f.saveBtn:SetWidth(btnWidth)

        f.resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.resetBtn:SetHeight(lib.CONFIG_BUTTON_HEIGHT)
        f.resetBtn:SetText("Reset to Default")
        f.resetBtn:SetPoint("BOTTOMLEFT", f.saveBtn, "BOTTOMRIGHT", lib.CONFIG_FRAME_PADDING , 0)
        f.resetBtn:SetScript("OnClick", function() lib:ResetState(f.target) end)
        f.resetBtn:SetWidth(btnWidth)
        f:Hide()
        self.configFrame = f
    end
    return self.configFrame
end
function lib:ClearFrameSpecificControls()
    local cfg = self:GetOrCreateConfigFrame()
    local socket = cfg.frameSpecificSocket

    if socket.attachedPlugin then
        socket.attachedPlugin:SetParent(cfg.target)
        socket.attachedPlugin:Hide()
        socket.attachedPlugin = nil
    end

    cfg.frameSpecificControls = {}
    socket:SetHeight(1) -- Collapse the space
end
function lib:AttachFrameSpecificControls(targetFrame)
    local cfg = self:GetOrCreateConfigFrame()
    local socket = cfg.frameSpecificSocket
    cfg.frameSpecificControls = {}

    if targetFrame.GetOrCreateFrameSpecificControls and type(targetFrame.GetOrCreateFrameSpecificControls) == "function" then
        -- 1. Get the controls table and the single Plugin Frame Container
        local controls, pluginFrame = targetFrame:GetOrCreateFrameSpecificControls(socket)
        cfg.frameSpecificControls = controls or {}

        if pluginFrame then
            pluginFrame:SetParent(socket)
            pluginFrame:ClearAllPoints()
            pluginFrame:SetPoint("TOPLEFT", socket, "TOPLEFT")
            pluginFrame:SetPoint("TOPRIGHT", socket, "TOPRIGHT")
            if pluginFrame.Layout then pluginFrame:Layout() end
            pluginFrame:Show()
            socket.attachedPlugin = pluginFrame
            socket:SetHeight(pluginFrame:GetHeight() or 1)
        end
    end
    cfg.flexContainer:MarkDirty()
    cfg.flexContainer:Layout()

    local totalHeight = cfg.flexContainer:GetHeight() + cfg.title:GetHeight() + 4*lib.CONFIG_FRAME_PADDING +  lib.CONFIG_EDIT_BOX_HEIGHT
    cfg:SetHeight(totalHeight)
end
function lib:ShowConfigForFrame(targetFrame)
    --if not lib.DEBUG_MODE then return end
    local cfg = self:GetOrCreateConfigFrame()
    cfg.target = targetFrame
    cfg.title:SetText(targetFrame.systemName or "Frame Settings")
    --standard elements
    if targetFrame.workingState then
        local ws = targetFrame.workingState
        if cfg.standardControls.widthControl then cfg.standardControls.widthControl.slider:SetValue(ws.width or targetFrame:GetWidth()) end
        if cfg.standardControls.heightControl then cfg.standardControls.heightControl.slider:SetValue(ws.height or targetFrame:GetHeight()) end
        if cfg.standardControls.scaleControl then cfg.standardControls.scaleControl.slider:SetValue(ws.scale or targetFrame:GetScale() or 1) end
        if cfg.standardControls.opacityControl then cfg.standardControls.opacityControl.slider:SetValue(ws.opacity or targetFrame:GetAlpha() or 1) end
        if cfg.standardControls.xControl then cfg.standardControls.xControl:SetText(lib:RoundCoordinates(ws.xOfs)) end
        if cfg.standardControls.yControl then cfg.standardControls.yControl:SetText(lib:RoundCoordinates(ws.yOfs)) end
        if cfg.standardControls.sourceFrame then cfg.standardControls.sourceFrame:SetText(targetFrame:GetName() or "Unnamed") end
        if cfg.standardControls.sourcePoint then cfg.standardControls.sourcePoint:SetText(ws.point or "CENTER") end
        local _unused_relFrame, relFrameName = lib:ResolveFrame(ws.relativeFrame)
        if cfg.standardControls.relativeFrame then cfg.standardControls.relativeFrame:SetText(relFrameName) end
        if cfg.standardControls.relativePoint then cfg.standardControls.relativePoint:SetText(ws.relativePoint or "CENTER") end
    end

    lib:AttachFrameSpecificControls(targetFrame)

    if targetFrame.isDirty then
        cfg.revertBtn:Enable()
        cfg.saveBtn:Enable()
     else 
        cfg.revertBtn:Disable()
        cfg.saveBtn:Disable()
    end

    if(cfg.target ~= cfg.previousTarget ) then
        -- INTELLIGENT POSITIONING 
        local screenWidth = UIParent:GetWidth()
        local screenHeight = UIParent:GetHeight()
        local centerX, centerY = targetFrame:GetCenter()

        if centerX and centerY then
            cfg:ClearAllPoints()
            -- Determine Horizontal side (if on left, show on right)
            local point = (centerX > screenWidth / 2) and "RIGHT" or "LEFT"
            local relPoint = (point == "LEFT") and "RIGHT" or "LEFT"
            -- Determine Vertical side (if on top, show on bottom)
            local vPoint = (centerY > screenHeight / 2) and "TOP" or "BOTTOM"
            -- Combine them (e.g., "TOPLEFT")
            local finalPoint = vPoint .. point
            local finalRelPoint = vPoint .. relPoint
            -- Offset slightly (e.g., 10px away) so it doesn't touch the frame
            local xOfs = (point == "LEFT") and 10 or -10
            cfg:SetPoint(finalPoint, targetFrame, finalRelPoint, xOfs, 0)
            local left, top = cfg:GetLeft(), cfg:GetTop()    
            if left and top then
                cfg:ClearAllPoints()
                cfg:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        else
            -- Fallback if frame isn't rendered
            cfg:ClearAllPoints()
            cfg:SetPoint("CENTER", UIParent, "CENTER")
        end
    end
    cfg.previousTarget = nil

    --TODO calculate height and reset config height to accomodate?

    cfg:SetAlpha(0)
    cfg:Show()
    cfg.flexContainer:Layout()
    cfg:SetAlpha(1)
end
function lib:ClearConfigMenu()
    local cfg = self:GetOrCreateConfigFrame()
    cfg:Hide()
    lib:ClearFrameSpecificControls()
    cfg.previousTarget = cfg.target
    cfg.target = nil
    cfg:SetParent(UIParent)
    cfg:SetFrameStrata("DIALOG")
end

function lib:CreateSliderRow(container, label, key, minValue, maxValue, step, labelWidth)
    local wrapper = CreateFrame("Frame")
    totalWidth = totalWidth or lib.CONFIG_FRAME_WIDTH
    labelWidth = labelWidth or lib.CONFIG_ROW_LABEL_WIDTH
    wrapper:SetSize(totalWidth-lib.CONFIG_FRAME_PADDING - labelWidth, lib.CONFIG_ROW_HEIGHT)
    --Edit Box
    local eb = CreateFrame("EditBox", nil, wrapper, "InputBoxTemplate")
    eb:SetSize(40, lib.CONFIG_ROW_HEIGHT)
    eb:SetPoint("RIGHT", wrapper, "RIGHT", 0, 0)
    eb:SetAutoFocus(false)
    --Slider
    local slider = CreateFrame("Slider", nil, wrapper, "MinimalSliderTemplate")
    slider:SetPoint("LEFT", wrapper, "LEFT", 0, 0)
    slider:SetPoint("RIGHT", eb, "LEFT", -lib.CONFIG_FRAME_PADDING, 0)
    --slider:SetWidth(140)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    --attach to wrapper so we can programatically access them later intelligently
    wrapper.slider = slider
    wrapper.editBox = eb
    
    -- Sync: Slider -> Proxy
    slider:SetScript("OnValueChanged", function(self, value)
        local formatStr = (step < 1) and "%.2f" or "%d"
        eb:SetText(string.format(formatStr, value))
        local cfg = lib:GetOrCreateConfigFrame()
        if cfg.target and cfg.target.workingState then
            cfg.target.workingState[key] = value
        end
    end)
    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.min(maxValue, math.max(minValue, val))
            slider:SetValue(val)
        end
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        local value = slider:GetValue()
        local formatStr = (step < 1) and "%.2f" or "%d"
        self:SetText(string.format(formatStr, value))
    end)

    lib:AddLabelElementRow(container, label, wrapper, totalWidth, labelWidth)
    return wrapper
end

function lib:RefreshConfigUI(frame)
    local f = self.configFrame
    -- Check if we are actually looking at this frame right now
    if f and f:IsShown() and f.target == frame then
        local ws = frame.workingState
        -- Update Scale
        if f.standardControls.scaleControl and ws.scale then
            f.standardControls.scaleControl.slider:SetValue(ws.scale)
        end
        if f.standardControls.opacityControl and ws.opacity then
            f.standardControls.opacityControl.slider:SetValue(ws.opacity)
        end
        -- Update Width/Height if you have them
        if f.standardControls.widthControl and ws.width then
            f.standardControls.widthControl.slider:SetValue(ws.width)
        end
        if f.standardControls.heightControl and ws.height then
            f.standardControls.heightControl.slider:SetValue(ws.height)
        end
        if f.standardControls.xControl and not f.standardControls.xControl:HasFocus() then
            f.standardControls.xControl:SetText(lib:RoundCoordinates(ws.xOfs or 0))
        end
        if f.standardControls.yControl and not f.standardControls.yControl:HasFocus() then
            f.standardControls.yControl:SetText(lib:RoundCoordinates(ws.yOfs or 0))
        end
        f.standardControls.sourceFrame:SetText(frame:GetName() or "Unnamed Frame")
        if f.standardControls.sourcePoint then
            f.standardControls.sourcePoint:SetText(ws.point or "CENTER")
        end

        local _, relName = lib:ResolveFrame(ws.relativeFrame)
        f.standardControls.relativeFrame:SetText(relName)
        if f.standardControls.relativePoint then
            f.standardControls.relativePoint:SetText(ws.relativePoint or "CENTER")
        end

        if frame.OnConfigRefresh then
            frame:OnConfigRefresh(f, frame.workingState)
        end

        if frame.isDirty then
            f.revertBtn:Enable()
            f.saveBtn:Enable()
        else
            f.revertBtn:Disable()
            f.saveBtn:Disable()
        end
    end
end

function lib:CreateXYControls(container)
    local wrapper = CreateFrame("Frame", nil, container)
    wrapper:SetSize(lib.CONFIG_FRAME_WIDTH, lib.CONFIG_ROW_HEIGHT)
    --X
    local xBox = CreateFrame("EditBox", nil, wrapper, "InputBoxTemplate")
    xBox:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_ROW_HEIGHT)
    xBox:SetAutoFocus(false)
    local xPair = lib:CreateLabelElementPair(wrapper,"X",xBox,lib.CONFIG_FRAME_HALF_WIDTH)
    xPair:SetPoint("LEFT", wrapper, "LEFT", 0, 0)
    --Y
    local yBox = CreateFrame("EditBox", nil, wrapper, "InputBoxTemplate")
    yBox:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_ROW_HEIGHT)
    yBox:SetAutoFocus(false)
    local yPair = lib:CreateLabelElementPair(wrapper,"Y",yBox,lib.CONFIG_FRAME_HALF_WIDTH)
    yPair:SetPoint("LEFT", xPair, "RIGHT", 0, 0)
    --local scripts
    local function UpdateCoords()
        local cfg = lib:GetOrCreateConfigFrame()
        if cfg.target and cfg.target.workingState then
            cfg.target.workingState.xOfs = tonumber(xBox:GetText()) or 0
            cfg.target.workingState.yOfs = tonumber(yBox:GetText()) or 0
        end
    end
    local function OnCancel()
        local cfg = lib:GetOrCreateConfigFrame()
        if cfg.target then lib:RefreshConfigUI(cfg.target) end
    end
    --set Scripts
    xBox:SetScript("OnEnterPressed", function(self) UpdateCoords(); self:ClearFocus() end)
    yBox:SetScript("OnEnterPressed", function(self) UpdateCoords(); self:ClearFocus() end)
    xBox:SetScript("OnEditFocusLost", OnCancel)
    yBox:SetScript("OnEditFocusLost", OnCancel)

    lib:AddElementRow(container, wrapper)
    return xBox, yBox
end

function lib:CreateFrameAnchorControls(container)
    local wrapper = CreateFrame("Frame", nil, container)
    wrapper:SetSize(lib.CONFIG_FRAME_WIDTH, lib.CONFIG_ROW_HEIGHT)

    -- Control 1: Read-only Frame Name
    local nameBox = CreateFrame("EditBox", nil, wrapper, "InputBoxTemplate")
    nameBox:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_EDIT_BOX_HEIGHT)
    nameBox:SetAutoFocus(false)
    nameBox:SetEnabled(false)
    nameBox:SetFontObject("GameFontDisable")
    nameBox:SetScript("OnEditFocusGained", function(self) self:ClearFocus() end)

    -- Control 2: Anchor Point Dropdown
    local pointDrop = lib:CreateAnchorDropdown(wrapper, "point")

    local namePair = lib:CreateLabelElementPair(wrapper, "Self", nameBox, lib.CONFIG_FRAME_HALF_WIDTH)
    local pointPair = lib:CreateLabelElementPair(wrapper, "Point", pointDrop, lib.CONFIG_FRAME_HALF_WIDTH)

    namePair:SetPoint("LEFT", wrapper, "LEFT", 0, 0)
    pointPair:SetPoint("LEFT", namePair, "RIGHT", 0, 0)

    lib:AddElementRow(container, wrapper)
    return nameBox, pointDrop
end

function lib:CreateRelativeFrameAnchorControls(container)
    local wrapper = CreateFrame("Frame", nil, container)
    wrapper:SetSize(lib.CONFIG_FRAME_WIDTH, lib.CONFIG_ROW_HEIGHT)

    -- Control 1: Relative To (The target frame name)
    local relToBox = CreateFrame("EditBox", nil, wrapper, "InputBoxTemplate")
    relToBox:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_EDIT_BOX_HEIGHT)
    relToBox:SetAutoFocus(false)
    
    -- Control 2: Relative Point Dropdown
    local relPointDrop = lib:CreateAnchorDropdown(wrapper, "relativePoint")

    local toPair = lib:CreateLabelElementPair(wrapper, "To", relToBox, lib.CONFIG_FRAME_HALF_WIDTH)
    local relPointPair = lib:CreateLabelElementPair(wrapper, "At", relPointDrop, lib.CONFIG_FRAME_HALF_WIDTH)

    toPair:SetPoint("LEFT", wrapper, "LEFT", 0, 0)
    relPointPair:SetPoint("LEFT", toPair, "RIGHT", 0, 0)

    -- Input Logic for the "To" Box
    relToBox:SetScript("OnEnterPressed", function(self)
        local cfg = lib:GetOrCreateConfigFrame()
        if cfg.target and cfg.target.workingState then
            relFrame,_unused_relFrameName = lib:ResolveFrame(self:GetText())
            cfg.target.workingState.relativeFrame = relFrame
        end
        self:ClearFocus()
    end)

    lib:AddElementRow(container, wrapper)
    return relToBox, relPointDrop
end

function lib:CreateAnchorDropdown(container, key)
    -- Creating a sleek, modern button instead of the old-style dropdown
    local dropdown = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    dropdown:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_EDIT_BOX_HEIGHT)
    dropdown:SetAutoFocus(false)
    dropdown:EnableMouse(false)
    dropdown:SetAutoFocus(false)
    
    local clicker = CreateFrame("Button", nil, dropdown)
    clicker:SetAllPoints(dropdown)
    clicker:EnableMouse(true)
    clicker:RegisterForClicks("LeftButtonUp")
    clicker:SetScript("OnClick", function()
        local library = lib
        MenuUtil.CreateContextMenu(dropdown, function(owner, rootDescription)
            rootDescription:CreateTitle("Select Anchor Point")
            for _, point in ipairs(library.ANCHOR_POINTS) do
                rootDescription:CreateButton(point, function()
                    dropdown:SetText(point) -- Uses EditBox:SetText
                    
                    local cfg = library:GetOrCreateConfigFrame()
                    if cfg and cfg.target and cfg.target.workingState then
                        cfg.target.workingState[key] = point
                    end
                end)
            end
        end)
    end)

    if dropdown.Left then dropdown.Left:SetAlpha(0.5) end

    return dropdown
end

function lib:CreateMediaSelector(container, label, key, mediaType, labelWidth)
    local dropdown = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    dropdown:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_EDIT_BOX_HEIGHT)
    dropdown:SetAutoFocus(false)
    dropdown:EnableMouse(false)

    local clicker = CreateFrame("Button", nil, dropdown)
    clicker:SetAllPoints(dropdown)
    clicker:SetScript("OnClick", function()
        local sortedList = {}
        local seenPaths = {}

        for _, entry in ipairs(lib.DEFAULT_MEDIA[mediaType]) do
            local cleanPath = lib:NormalizePath(entry.path)
            if not seenPaths[cleanPath] then
                table.insert(sortedList, { name = entry.name, path = entry.path })
                seenPaths[cleanPath] = true
            end
        end

        if LSM then
            for name, path in pairs(LSM:HashTable(mediaType)) do
                local cleanPath = lib:NormalizePath(path)
                if not seenPaths[cleanPath] then
                    table.insert(sortedList, { name = name, path = path })
                    seenPaths[cleanPath] = true
                end
            end
        end
        table.sort(sortedList, function(a, b)
            return a.name:lower() < b.name:lower() -- Compare the name field
        end)

        MenuUtil.CreateContextMenu(dropdown, function(owner, rootDescription)
            rootDescription:CreateTitle("Select "..label)
            for _, mm in ipairs(sortedList) do
                rootDescription:CreateButton(mm.name, function()
                    dropdown:SetText(mm.name)
                    local cfg = lib:GetOrCreateConfigFrame()
                    if cfg.target and cfg.target.workingState then
                        cfg.target.workingState[key] = mm.path
                        if cfg.target.UpdateMedia then cfg.target:UpdateMedia(mediaType) end
                    end
                end)
            end
        end)
    end)

    local pair = lib:CreateLabelElementPair(container, label, dropdown, lib.CONFIG_FRAME_WIDTH, labelWidth)
    lib:AddElementRow(container, pair)
    return dropdown
end
function lib:CreateSpellIconSelector(container, label, key, iconList, labelWidth)
    -- Create the EditBox display (matching your sleek button style)
    local dropdown = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    dropdown:SetSize(lib.CONFIG_EDIT_BOX_WIDTH, lib.CONFIG_EDIT_BOX_HEIGHT)
    dropdown:SetAutoFocus(false)
    dropdown:EnableMouse(false)

    local clicker = CreateFrame("Button", nil, dropdown)
    clicker:SetAllPoints(dropdown)
    clicker:SetScript("OnClick", function()
        MenuUtil.CreateContextMenu(dropdown, function(owner, rootDescription)
            rootDescription:CreateTitle("Select " .. label)
            
            -- 1. Get the keys so we can sort them
            local sortedIDs = {}
            for spellId in pairs(iconList) do
                table.insert(sortedIDs, spellId)
            end
            
            -- 2. Sort keys based on your .order field
            table.sort(sortedIDs, function(a, b)
                return iconList[a].order < iconList[b].order
            end)
            
            -- 3. Iterate through the sorted IDs
            for _, spellId in ipairs(sortedIDs) do
                local data = iconList[spellId]
                local displayName = data.label -- Use the label field
                
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local texture = spellInfo and spellInfo.iconID
                
                local button = rootDescription:CreateButton(displayName, function()
                    dropdown:SetText(displayName)
                    
                    local cfg = lib:GetOrCreateConfigFrame()
                    if cfg and cfg.target and cfg.target.workingState then
                        cfg.target.workingState[key] = spellId
                        if cfg.target.UpdateFromState then
                            cfg.target:UpdateFromState(cfg.target.workingState)
                        end
                    end
                end)
                
                -- Add the icon preview
                if texture then
                    button:AddInitializer(function(btn)
                        local icon = btn:AttachTexture()
                        icon:SetSize(16, 16)
                        icon:SetPoint("LEFT", 5, 0)
                        icon:SetTexture(texture)
                        btn.fontString:SetPoint("LEFT", icon, "RIGHT", 5, 0)
                    end)
                end
            end
        end)
    end)

    -- Visually consistent with your Anchor dropdown
    if dropdown.Left then dropdown.Left:SetAlpha(0.5) end

    -- Glue it to the container with your label pair system
    local pair = lib:CreateLabelElementPair(container, label, dropdown, lib.CONFIG_FRAME_WIDTH, labelWidth)
    lib:AddElementRow(container, pair)
    
    return dropdown
end