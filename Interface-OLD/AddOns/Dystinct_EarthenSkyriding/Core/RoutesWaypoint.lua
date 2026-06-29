local addonName, addon = ...

local frame = addon.ui.RoutesFrame

local triggerTypes = {
    { value = "none", label = "None" },
    { value = "proximity", label = "Proximity" },
    { value = "zone", label = "Zone" },
    { value = "buff", label = "Buff" },
    { value = "cast", label = "Cast" },
    { value = "vehicle", label = "Vehicle" },
}

local triggerLabelLookup = {}
for _, t in ipairs(triggerTypes) do
    triggerLabelLookup[t.value] = t.label
end

function frame:InitializeWaypoint()
    local function saveOnClick()
        frame:SaveWaypoint()
        frame.viewer:Show()
    end

    local function discardOnClick()
        frame.waypoint:Hide()
        frame.viewer:Show()
    end

    local function validateFields()
        local wp = frame.waypoint
        local nameOk = wp.name.input:GetText() ~= ""
        if not nameOk then
            wp.save:Disable()
            return
        end

        local triggerType = wp.triggerType or "none"

        if triggerType == "none" then
            if wp.x.input:GetText() == "" or wp.y.input:GetText() == "" then
                wp.save:Disable()
                return
            end
        elseif triggerType == "buff" or triggerType == "cast" then
            if wp.spellId.input:GetText() == "" then
                wp.save:Disable()
                return
            end
        end

        wp.save:Enable()
    end

    local function fieldOnChange(self, user)
        if user then
            validateFields()
        end
    end

    local childFrame = addon:BuildFrame(frame, {
        title = "Editing Waypoint",
        buttons = {
            { name = "save", label = "Save", anchor = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 }, width = 70, disable = true, script = saveOnClick },
            { name = "discard", label = "Cancel", anchor = { "RIGHT", "save", "LEFT", -3, 0 }, width = 70, script = discardOnClick },
        },
        fields = {
            { name = "note", label = "Note", anchor = { "CENTER", nil, "CENTER", 0, 0 }, width = 470, script = fieldOnChange },
            { name = "name", label = "Name", anchor = { "BOTTOMLEFT", "note", "TOPLEFT", 0, 25 }, width = 200, script = fieldOnChange },
            { name = "map", label = "Map ID", anchor = { "LEFT", "name", "RIGHT", 15, 0 }, width = 75, script = fieldOnChange },
            { name = "x", label = "X Coordinate", anchor = { "LEFT", "map", "RIGHT", 15, 0 }, width = 75, script = fieldOnChange },
            { name = "y", label = "Y Coordinate", anchor = { "LEFT", "x", "RIGHT", 15, 0 }, width = 75, script = fieldOnChange },
        },
        up = function()
            frame.waypoint:Hide()
            frame.viewer:Show()
        end
    })

    childFrame.triggerType = "none"
    childFrame.validateFields = validateFields

    ---------------------------------------------------------------------------
    -- Trigger type selector
    ---------------------------------------------------------------------------
    local triggerBtn = CreateFrame("Button", nil, childFrame, "UIPanelButtonTemplate")
    triggerBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    triggerBtn:SetSize(90, 20)
    triggerBtn:SetPoint("TOPLEFT", childFrame.note.input, "BOTTOMLEFT", 0, -20)
    triggerBtn:SetText("None")
    childFrame.triggerBtn = triggerBtn

    addon:BuildLabel(childFrame, { label = "Trigger", anchor = { "BOTTOMLEFT", triggerBtn, "TOPLEFT", 0, 4 } })

    local triggerDropdown = CreateFrame("Frame", "DysES_TriggerDropDown", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(triggerDropdown, function(self, level)
        for _, tt in ipairs(triggerTypes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = tt.label
            info.notCheckable = true
            info.func = function()
                childFrame.triggerType = tt.value
                triggerBtn:SetText(tt.label)
                frame:UpdateTriggerFields()
                validateFields()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    triggerBtn:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, triggerDropdown, self, 0, 0)
    end)

    ---------------------------------------------------------------------------
    -- Trigger-specific fields (all created upfront, shown/hidden dynamically)
    ---------------------------------------------------------------------------

    -- Proximity: radius
    childFrame.radius = {}
    childFrame.radius.input = CreateFrame("EditBox", nil, childFrame, "InputBoxTemplate")
    childFrame.radius.input:SetSize(50, 20)
    childFrame.radius.input:SetPoint("LEFT", triggerBtn, "RIGHT", 15, 0)
    childFrame.radius.input:SetAutoFocus(false)
    childFrame.radius.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.radius.label = addon:BuildLabel(childFrame, { label = "Radius", anchor = { "BOTTOMLEFT", childFrame.radius.input, "TOPLEFT", 0, 4 } })

    -- Zone: target map override
    childFrame.triggerMap = {}
    childFrame.triggerMap.input = CreateFrame("EditBox", nil, childFrame, "InputBoxTemplate")
    childFrame.triggerMap.input:SetSize(75, 20)
    childFrame.triggerMap.input:SetPoint("LEFT", triggerBtn, "RIGHT", 15, 0)
    childFrame.triggerMap.input:SetAutoFocus(false)
    childFrame.triggerMap.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.triggerMap.label = addon:BuildLabel(childFrame, { label = "Target Map", anchor = { "BOTTOMLEFT", childFrame.triggerMap.input, "TOPLEFT", 0, 4 } })

    -- Buff / Cast: spell ID
    childFrame.spellId = {}
    childFrame.spellId.input = CreateFrame("EditBox", nil, childFrame, "InputBoxTemplate")
    childFrame.spellId.input:SetSize(75, 20)
    childFrame.spellId.input:SetPoint("LEFT", triggerBtn, "RIGHT", 15, 0)
    childFrame.spellId.input:SetAutoFocus(false)
    childFrame.spellId.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.spellId.label = addon:BuildLabel(childFrame, { label = "Spell ID", anchor = { "BOTTOMLEFT", childFrame.spellId.input, "TOPLEFT", 0, 4 } })

    -- Buff / Cast: spell display name
    childFrame.spellName = {}
    childFrame.spellName.input = CreateFrame("EditBox", nil, childFrame, "InputBoxTemplate")
    childFrame.spellName.input:SetSize(120, 20)
    childFrame.spellName.input:SetPoint("LEFT", childFrame.spellId.input, "RIGHT", 15, 0)
    childFrame.spellName.input:SetAutoFocus(false)
    childFrame.spellName.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.spellName.label = addon:BuildLabel(childFrame, { label = "Spell Name", anchor = { "BOTTOMLEFT", childFrame.spellName.input, "TOPLEFT", 0, 4 } })

    -- Buff: gained / lost toggle
    childFrame.gained = true
    childFrame.gainedBtn = CreateFrame("Button", nil, childFrame, "UIPanelButtonTemplate")
    childFrame.gainedBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    childFrame.gainedBtn:SetSize(70, 20)
    childFrame.gainedBtn:SetPoint("LEFT", childFrame.spellName.input, "RIGHT", 15, 0)
    childFrame.gainedBtn:SetText("Gained")
    childFrame.gainedLabel = addon:BuildLabel(childFrame, { label = "On Aura", anchor = { "BOTTOMLEFT", childFrame.gainedBtn, "TOPLEFT", 0, 4 } })
    childFrame.gainedBtn:SetScript("OnClick", function()
        childFrame.gained = not childFrame.gained
        childFrame.gainedBtn:SetText(childFrame.gained and "Gained" or "Lost")
    end)

    -- Vehicle: enter / exit toggle
    childFrame.entered = true
    childFrame.enteredBtn = CreateFrame("Button", nil, childFrame, "UIPanelButtonTemplate")
    childFrame.enteredBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    childFrame.enteredBtn:SetSize(70, 20)
    childFrame.enteredBtn:SetPoint("LEFT", triggerBtn, "RIGHT", 15, 0)
    childFrame.enteredBtn:SetText("Enter")
    childFrame.enteredLabel = addon:BuildLabel(childFrame, { label = "On Vehicle", anchor = { "BOTTOMLEFT", childFrame.enteredBtn, "TOPLEFT", 0, 4 } })
    childFrame.enteredBtn:SetScript("OnClick", function()
        childFrame.entered = not childFrame.entered
        childFrame.enteredBtn:SetText(childFrame.entered and "Enter" or "Exit")
    end)

    ---------------------------------------------------------------------------
    -- Action fields
    ---------------------------------------------------------------------------
    childFrame.actionLabel = {}
    childFrame.actionLabel.input = CreateFrame("EditBox", nil, childFrame, "InputBoxTemplate")
    childFrame.actionLabel.input:SetSize(120, 20)
    childFrame.actionLabel.input:SetPoint("TOPLEFT", triggerBtn, "BOTTOMLEFT", 0, -20)
    childFrame.actionLabel.input:SetAutoFocus(false)
    childFrame.actionLabel.label = addon:BuildLabel(childFrame, { label = "Action Label", anchor = { "BOTTOMLEFT", childFrame.actionLabel.input, "TOPLEFT", 0, 4 } })

    childFrame.actionMacro = {}
    childFrame.actionMacro.input = CreateFrame("EditBox", nil, childFrame, "InputBoxTemplate")
    childFrame.actionMacro.input:SetSize(310, 20)
    childFrame.actionMacro.input:SetPoint("LEFT", childFrame.actionLabel.input, "RIGHT", 15, 0)
    childFrame.actionMacro.input:SetAutoFocus(false)
    childFrame.actionMacro.label = addon:BuildLabel(childFrame, { label = "Action Macro", anchor = { "BOTTOMLEFT", childFrame.actionMacro.input, "TOPLEFT", 0, 4 } })

    childFrame:Hide()

    return childFrame
end

---------------------------------------------------------------------------
-- Show / hide trigger-specific fields based on selected type
---------------------------------------------------------------------------

function frame:UpdateTriggerFields()
    local wp = frame.waypoint
    local t = wp.triggerType or "none"

    -- Hide all trigger-specific elements
    wp.radius.label:Hide();      wp.radius.input:Hide()
    wp.triggerMap.label:Hide();   wp.triggerMap.input:Hide()
    wp.spellId.label:Hide();     wp.spellId.input:Hide()
    wp.spellName.label:Hide();   wp.spellName.input:Hide()
    wp.gainedBtn:Hide();         wp.gainedLabel:Hide()
    wp.enteredBtn:Hide();        wp.enteredLabel:Hide()

    if t == "proximity" then
        wp.radius.label:Show();  wp.radius.input:Show()
    elseif t == "zone" then
        wp.triggerMap.label:Show();  wp.triggerMap.input:Show()
    elseif t == "buff" then
        wp.spellId.label:Show();    wp.spellId.input:Show()
        wp.spellName.label:Show();  wp.spellName.input:Show()
        wp.gainedBtn:Show();        wp.gainedLabel:Show()
    elseif t == "cast" then
        wp.spellId.label:Show();    wp.spellId.input:Show()
        wp.spellName.label:Show();  wp.spellName.input:Show()
    elseif t == "vehicle" then
        wp.enteredBtn:Show();       wp.enteredLabel:Show()
    end
end

---------------------------------------------------------------------------
-- Clear all trigger / action fields to defaults
---------------------------------------------------------------------------

local function resetTriggerActionFields(wp)
    wp.triggerType = "none"
    wp.triggerBtn:SetText("None")
    wp.radius.input:SetText("")
    wp.triggerMap.input:SetText("")
    wp.spellId.input:SetText("")
    wp.spellName.input:SetText("")
    wp.gained = true
    wp.gainedBtn:SetText("Gained")
    wp.entered = true
    wp.enteredBtn:SetText("Enter")
    wp.actionLabel.input:SetText("")
    wp.actionMacro.input:SetText("")
end

---------------------------------------------------------------------------
-- New / Load / Save
---------------------------------------------------------------------------

function frame:NewWaypoint()
    local wp = frame.waypoint
    wp.name.input:SetText("")
    wp.map.input:SetText(tonumber(addon.data.routes[frame.viewer.editing[#frame.viewer.editing]].map) or "")
    wp.x.input:SetText("")
    wp.y.input:SetText("")
    wp.note.input:SetText("")
    resetTriggerActionFields(wp)
    frame:UpdateTriggerFields()
    frame:ShowWaypointEditor()
end

function frame:LoadWaypoint(data)
    local wp = frame.waypoint
    wp.name.input:SetText(data.name or "")
    wp.map.input:SetText(data.map and tostring(data.map) or (tonumber(addon.data.routes[frame.viewer.editing[#frame.viewer.editing]].map) or ""))
    wp.x.input:SetText(data.x and tostring(data.x) or "")
    wp.y.input:SetText(data.y and tostring(data.y) or "")
    wp.note.input:SetText(data.note or "")

    -- Load trigger
    if data.trigger and data.trigger.type then
        local t = data.trigger
        wp.triggerType = t.type
        wp.triggerBtn:SetText(triggerLabelLookup[t.type] or t.type)

        if t.type == "proximity" then
            wp.radius.input:SetText(t.radius or 25)
        elseif t.type == "zone" then
            wp.triggerMap.input:SetText(t.map and tostring(t.map) or "")
        elseif t.type == "buff" then
            wp.spellId.input:SetText(t.spellId and tostring(t.spellId) or "")
            wp.spellName.input:SetText(t.spell or "")
            wp.gained = t.gained ~= false
            wp.gainedBtn:SetText(wp.gained and "Gained" or "Lost")
        elseif t.type == "cast" then
            wp.spellId.input:SetText(t.spellId and tostring(t.spellId) or "")
            wp.spellName.input:SetText(t.spell or "")
        elseif t.type == "vehicle" then
            wp.entered = t.entered ~= false
            wp.enteredBtn:SetText(wp.entered and "Enter" or "Exit")
        end
    else
        wp.triggerType = "none"
        wp.triggerBtn:SetText("None")
        wp.radius.input:SetText("")
        wp.triggerMap.input:SetText("")
        wp.spellId.input:SetText("")
        wp.spellName.input:SetText("")
        wp.gained = true
        wp.gainedBtn:SetText("Gained")
        wp.entered = true
        wp.enteredBtn:SetText("Enter")
    end

    -- Load action
    if data.action then
        wp.actionLabel.input:SetText(data.action.label or "")
        wp.actionMacro.input:SetText(data.action.macro or "")
    else
        wp.actionLabel.input:SetText("")
        wp.actionMacro.input:SetText("")
    end

    frame:UpdateTriggerFields()
    frame:ShowWaypointEditor()
end

function frame:SaveWaypoint()
    local route = addon.data.routes[frame.viewer.editing[#frame.viewer.editing]]
    local index = frame.waypoint.editing
    local wp = frame.waypoint

    local name = wp.name.input:GetText()
    local map = wp.map.input:GetText()
    local note = wp.note.input:GetText()
    local x = wp.x.input:GetText()
    local y = wp.y.input:GetText()

    -- Normalize empty strings to nil
    if map == "" then map = nil end
    if note == "" then note = nil end
    if x == "" then x = nil end
    if y == "" then y = nil end

    -- Build trigger table
    local trigger = nil
    local triggerType = wp.triggerType or "none"
    if triggerType ~= "none" then
        trigger = { type = triggerType }
        if triggerType == "proximity" then
            local radius = tonumber(wp.radius.input:GetText())
            if radius then trigger.radius = radius end
        elseif triggerType == "zone" then
            local targetMap = wp.triggerMap.input:GetText()
            if targetMap ~= "" then trigger.map = tonumber(targetMap) end
        elseif triggerType == "buff" then
            trigger.spellId = tonumber(wp.spellId.input:GetText())
            local spell = wp.spellName.input:GetText()
            if spell ~= "" then trigger.spell = spell end
            trigger.gained = wp.gained
        elseif triggerType == "cast" then
            trigger.spellId = tonumber(wp.spellId.input:GetText())
            local spell = wp.spellName.input:GetText()
            if spell ~= "" then trigger.spell = spell end
        elseif triggerType == "vehicle" then
            trigger.entered = wp.entered
        end
    end

    -- Build action table
    local action = nil
    local actionMacro = wp.actionMacro.input:GetText()
    if actionMacro ~= "" then
        local actionLbl = wp.actionLabel.input:GetText()
        action = {
            macro = actionMacro,
            label = actionLbl ~= "" and actionLbl or nil,
        }
    end

    if index ~= nil then
        local waypoint = route.route[index]
        waypoint.name = name
        waypoint.map = map
        waypoint.x = x
        waypoint.y = y
        waypoint.note = note
        waypoint.trigger = trigger
        waypoint.action = action
    else
        route.route[#route.route + 1] = {
            name = name,
            map = map,
            note = note,
            x = x,
            y = y,
            trigger = trigger,
            action = action,
        }
    end

    addon.menu = addon.processRoutes(addon.data.routes)
    addon.ui.SegmentFrame:Refresh()
    frame:LoadViewerRows()

    frame.waypoint:Hide()
    frame.viewer:Show()
end
