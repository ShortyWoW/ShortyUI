local addonName, addon = ...

local frame = addon.ui.RoutesFrame

local MAX_SWITCH_CASES = 6

local conditionTypes = {
    { value = "achievement", label = "Achievement" },
    { value = "faction", label = "Faction" },
    { value = "level", label = "Level" },
    { value = "class", label = "Class" },
    { value = "quest", label = "Quest" },
}

local switchCondTypes = {
    { value = "achievement", label = "Achievement" },
    { value = "faction", label = "Faction" },
    { value = "level", label = "Level" },
    { value = "class", label = "Class" },
    { value = "quest", label = "Quest" },
    { value = "default", label = "Default" },
}

local conditionLabelLookup = {}
for _, c in ipairs(conditionTypes) do conditionLabelLookup[c.value] = c.label end
for _, c in ipairs(switchCondTypes) do conditionLabelLookup[c.value] = c.label end

local function parseRouteField(text)
    if not text or text == "" then return nil end
    if text:find(",") then
        local routes = {}
        for name in text:gmatch("[^,]+") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed ~= "" then routes[#routes + 1] = trimmed end
        end
        return #routes > 0 and routes or nil
    end
    return text
end

local function formatRouteField(value)
    if type(value) == "table" then
        local parts = {}
        for _, v in ipairs(value) do
            if type(v) == "string" then
                parts[#parts + 1] = v
            elseif type(v) == "table" then
                parts[#parts + 1] = "(conditional)"
            end
        end
        return table.concat(parts, ", ")
    elseif type(value) == "string" then
        return value
    end
    return ""
end

local function extractConditionValue(cond)
    if not cond then return "" end
    if cond.type == "achievement" or cond.type == "quest" then
        return cond.id and tostring(cond.id) or ""
    elseif cond.type == "faction" then
        return cond.faction or "Horde"
    elseif cond.type == "level" then
        return cond.level and tostring(cond.level) or ""
    elseif cond.type == "class" then
        return cond.class or ""
    end
    return ""
end

local function buildCondition(condType, value)
    local condition = { type = condType }
    if condType == "achievement" or condType == "quest" then
        condition.id = tonumber(value)
    elseif condType == "faction" then
        condition.faction = value
    elseif condType == "level" then
        condition.level = tonumber(value)
    elseif condType == "class" then
        condition.class = value
    end
    return condition
end

function frame:InitializeConditional()
    local function saveOnClick()
        frame:SaveConditional()
    end

    local function discardOnClick()
        frame.conditional:Hide()
        frame.viewer:Show()
    end

    local function validateFields()
        local cf = frame.conditional
        if cf.isReadOnly then return end

        if cf.mode == "condition" then
            local condType = cf.condType or "achievement"
            if condType == "achievement" or condType == "quest" then
                if cf.condId.input:GetText() == "" then cf.save:Disable(); return end
            elseif condType == "level" then
                if cf.condLevel.input:GetText() == "" then cf.save:Disable(); return end
            elseif condType == "class" then
                if cf.condClass.input:GetText() == "" then cf.save:Disable(); return end
            end
            if cf.passRoute.input:GetText() == "" then cf.save:Disable(); return end
        else
            -- Switch mode: require at least one case with routes
            local hasRoute = false
            for i = 1, #cf.switchCases do
                if cf.switchCases[i].routeData and #cf.switchCases[i].routeData > 0 then
                    hasRoute = true
                    break
                end
            end
            if not hasRoute then cf.save:Disable(); return end
        end

        cf.save:Enable()
    end

    local function fieldOnChange(self, user)
        if user then validateFields() end
    end

    local childFrame = addon:BuildFrame(frame, {
        title = "Conditional Editor",
        buttons = {
            { name = "save", label = "Save", anchor = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 }, width = 70, disable = true, script = saveOnClick },
            { name = "discard", label = "Cancel", anchor = { "RIGHT", "save", "LEFT", -3, 0 }, width = 70, script = discardOnClick },
        },
        up = function()
            frame.conditional:Hide()
            frame.viewer:Show()
        end
    })

    childFrame.mode = "condition"
    childFrame.condType = "achievement"
    childFrame.isReadOnly = false
    childFrame.validateFields = validateFields

    ---------------------------------------------------------------------------
    -- Mode selector (Condition / Switch) — shared, always visible
    ---------------------------------------------------------------------------
    local modeBtn = CreateFrame("Button", nil, childFrame, "UIPanelButtonTemplate")
    modeBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    modeBtn:SetSize(90, 20)
    modeBtn:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 15, -45)
    modeBtn:SetText("Condition")
    childFrame.modeBtn = modeBtn

    addon:BuildLabel(childFrame, { label = "Style", anchor = { "BOTTOMLEFT", modeBtn, "TOPLEFT", 0, 4 } })

    local modeDropdown = CreateFrame("Frame", "DysES_CondModeDropDown", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(modeDropdown, function(self, level)
        for _, m in ipairs({ { value = "condition", label = "Condition" }, { value = "switch", label = "Switch" } }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = m.label
            info.notCheckable = true
            info.func = function()
                childFrame.mode = m.value
                modeBtn:SetText(m.label)
                frame:UpdateConditionalMode()
                validateFields()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    modeBtn:SetScript("OnClick", function(self)
        if not childFrame.isReadOnly then
            ToggleDropDownMenu(1, nil, modeDropdown, self, 0, 0)
        end
    end)

    ---------------------------------------------------------------------------
    -- CONDITION MODE UI (children of conditionUI — hidden together)
    ---------------------------------------------------------------------------
    local condUI = CreateFrame("Frame", nil, childFrame)
    condUI:SetAllPoints(childFrame)
    childFrame.conditionUI = condUI

    local condBtn = CreateFrame("Button", nil, condUI, "UIPanelButtonTemplate")
    condBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    condBtn:SetSize(100, 20)
    condBtn:SetPoint("TOPLEFT", modeBtn, "TOPRIGHT", 30, 0)
    condBtn:SetText("Achievement")
    childFrame.condBtn = condBtn

    addon:BuildLabel(condUI, { label = "Condition Type", anchor = { "BOTTOMLEFT", condBtn, "TOPLEFT", 0, 4 } })

    local condDropdown = CreateFrame("Frame", "DysES_CondDropDown", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(condDropdown, function(self, level)
        for _, ct in ipairs(conditionTypes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ct.label
            info.notCheckable = true
            info.func = function()
                childFrame.condType = ct.value
                condBtn:SetText(ct.label)
                frame:UpdateConditionFields()
                validateFields()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    condBtn:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, condDropdown, self, 0, 0)
    end)

    -- Achievement / Quest: ID
    childFrame.condId = {}
    childFrame.condId.input = CreateFrame("EditBox", nil, condUI, "InputBoxTemplate")
    childFrame.condId.input:SetSize(100, 20)
    childFrame.condId.input:SetPoint("LEFT", condBtn, "RIGHT", 15, 0)
    childFrame.condId.input:SetAutoFocus(false)
    childFrame.condId.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.condId.label = addon:BuildLabel(condUI, { label = "ID", anchor = { "BOTTOMLEFT", childFrame.condId.input, "TOPLEFT", 0, 4 } })

    -- Faction: toggle
    childFrame.factionValue = "Horde"
    childFrame.factionBtn = CreateFrame("Button", nil, condUI, "UIPanelButtonTemplate")
    childFrame.factionBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    childFrame.factionBtn:SetSize(80, 20)
    childFrame.factionBtn:SetPoint("LEFT", condBtn, "RIGHT", 15, 0)
    childFrame.factionBtn:SetText("Horde")
    childFrame.factionLabel = addon:BuildLabel(condUI, { label = "Faction", anchor = { "BOTTOMLEFT", childFrame.factionBtn, "TOPLEFT", 0, 4 } })
    childFrame.factionBtn:SetScript("OnClick", function()
        childFrame.factionValue = (childFrame.factionValue == "Horde") and "Alliance" or "Horde"
        childFrame.factionBtn:SetText(childFrame.factionValue)
        validateFields()
    end)

    -- Level
    childFrame.condLevel = {}
    childFrame.condLevel.input = CreateFrame("EditBox", nil, condUI, "InputBoxTemplate")
    childFrame.condLevel.input:SetSize(50, 20)
    childFrame.condLevel.input:SetPoint("LEFT", condBtn, "RIGHT", 15, 0)
    childFrame.condLevel.input:SetAutoFocus(false)
    childFrame.condLevel.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.condLevel.label = addon:BuildLabel(condUI, { label = "Min Level", anchor = { "BOTTOMLEFT", childFrame.condLevel.input, "TOPLEFT", 0, 4 } })

    -- Class
    childFrame.condClass = {}
    childFrame.condClass.input = CreateFrame("EditBox", nil, condUI, "InputBoxTemplate")
    childFrame.condClass.input:SetSize(120, 20)
    childFrame.condClass.input:SetPoint("LEFT", condBtn, "RIGHT", 15, 0)
    childFrame.condClass.input:SetAutoFocus(false)
    childFrame.condClass.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.condClass.label = addon:BuildLabel(condUI, { label = "Class Token", anchor = { "BOTTOMLEFT", childFrame.condClass.input, "TOPLEFT", 0, 4 } })

    -- Pass / Fail
    childFrame.passRoute = {}
    childFrame.passRoute.input = CreateFrame("EditBox", nil, condUI, "InputBoxTemplate")
    childFrame.passRoute.input:SetSize(220, 20)
    childFrame.passRoute.input:SetPoint("TOPLEFT", condBtn, "BOTTOMLEFT", 0, -20)
    childFrame.passRoute.input:SetAutoFocus(false)
    childFrame.passRoute.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.passRoute.label = addon:BuildLabel(condUI, { label = "Pass Route(s)", anchor = { "BOTTOMLEFT", childFrame.passRoute.input, "TOPLEFT", 0, 4 } })

    childFrame.failRoute = {}
    childFrame.failRoute.input = CreateFrame("EditBox", nil, condUI, "InputBoxTemplate")
    childFrame.failRoute.input:SetSize(220, 20)
    childFrame.failRoute.input:SetPoint("LEFT", childFrame.passRoute.input, "RIGHT", 15, 0)
    childFrame.failRoute.input:SetAutoFocus(false)
    childFrame.failRoute.input:SetScript("OnTextChanged", fieldOnChange)
    childFrame.failRoute.label = addon:BuildLabel(condUI, { label = "Fail Route(s)", anchor = { "BOTTOMLEFT", childFrame.failRoute.input, "TOPLEFT", 0, 4 } })

    -- Read-only notice (compound conditions only)
    childFrame.readOnlyText = condUI:CreateFontString(nil, "OVERLAY")
    childFrame.readOnlyText:SetFontObject("GameFontNormal")
    childFrame.readOnlyText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    childFrame.readOnlyText:SetPoint("TOPLEFT", childFrame.passRoute.input, "BOTTOMLEFT", 0, -15)
    childFrame.readOnlyText:SetTextColor(1, 0.5, 0)
    childFrame.readOnlyText:Hide()

    ---------------------------------------------------------------------------
    -- SWITCH MODE UI (children of switchUI — hidden together)
    ---------------------------------------------------------------------------
    local switchUI = CreateFrame("Frame", nil, childFrame)
    switchUI:SetAllPoints(childFrame)
    childFrame.switchUI = switchUI

    childFrame.switchCases = {} -- { { condType, value, routeData (array), originalCondition? }, ... }
    childFrame.switchRows = {}

    -- Column headers (anchored to childFrame to avoid cross-parent anchor issues)
    local typeHeader = addon:BuildLabel(switchUI, { label = "Type", anchor = { "TOPLEFT", childFrame, "TOPLEFT", 17, -80 } })
    addon:BuildLabel(switchUI, { label = "Value", anchor = { "LEFT", typeHeader, "LEFT", 93, 0 } })
    addon:BuildLabel(switchUI, { label = "Routes", anchor = { "LEFT", typeHeader, "LEFT", 198, 0 } })

    -- Shared dropdown for switch case condition types
    local switchCondDropdown = CreateFrame("Frame", "DysES_SwitchCondDropDown", UIParent, "UIDropDownMenuTemplate")
    local switchDropdownRow = nil

    UIDropDownMenu_Initialize(switchCondDropdown, function(self, level)
        for _, ct in ipairs(switchCondTypes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ct.label
            info.notCheckable = true
            info.func = function()
                if switchDropdownRow then
                    switchDropdownRow.condType = ct.value
                    switchDropdownRow.originalCondition = nil
                    switchDropdownRow.condBtn:SetText(ct.label)
                    if ct.value == "default" then
                        switchDropdownRow.valueInput:SetText("")
                        switchDropdownRow.valueInput:Disable()
                    else
                        switchDropdownRow.valueInput:Enable()
                    end
                end
                validateFields()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    -- Create row frames
    for i = 1, MAX_SWITCH_CASES do
        local row = CreateFrame("Frame", nil, switchUI)
        row:SetSize(500, 22)
        if i == 1 then
            row:SetPoint("TOPLEFT", typeHeader, "BOTTOMLEFT", -2, -5)
        else
            row:SetPoint("TOPLEFT", childFrame.switchRows[i - 1], "BOTTOMLEFT", 0, -3)
        end

        row.condType = "achievement"
        row.originalCondition = nil

        row.condBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.condBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 9)
        row.condBtn:SetSize(90, 20)
        row.condBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.condBtn:SetText("Achievement")
        row.condBtn:SetScript("OnClick", function(self)
            switchDropdownRow = row
            ToggleDropDownMenu(1, nil, switchCondDropdown, self, 0, 0)
        end)

        row.valueInput = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.valueInput:SetSize(100, 20)
        row.valueInput:SetPoint("LEFT", row.condBtn, "RIGHT", 5, 0)
        row.valueInput:SetAutoFocus(false)
        row.valueInput:SetScript("OnTextChanged", fieldOnChange)

        row.routeCount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.routeCount:SetFont("Fonts\\FRIZQT__.TTF", 10)
        row.routeCount:SetPoint("LEFT", row.valueInput, "RIGHT", 10, 0)
        row.routeCount:SetTextColor(0.8, 0.8, 0.8)
        row.routeCount:SetText("0 routes")

        row.editRoutesBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.editRoutesBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 9)
        row.editRoutesBtn:SetSize(50, 18)
        row.editRoutesBtn:SetPoint("LEFT", row.routeCount, "RIGHT", 8, 0)
        row.editRoutesBtn:SetText("Edit")

        row.deleteBtn = CreateFrame("Button", nil, row)
        row.deleteBtn:SetSize(24, 24)
        row.deleteBtn:SetPoint("LEFT", row.editRoutesBtn, "RIGHT", 5, 0)
        row.deleteBtn:SetNormalTexture("Interface\\Buttons\\CancelButton-Up")
        row.deleteBtn:SetPushedTexture("Interface\\Buttons\\CancelButton-Down")
        row.deleteBtn:SetHighlightTexture("Interface\\Buttons\\CancelButton-Highlight")

        local rowIndex = i
        row.deleteBtn:SetScript("OnClick", function()
            frame:CollectSwitchState()
            table.remove(childFrame.switchCases, rowIndex)
            frame:RefreshSwitchRows()
            validateFields()
        end)

        row:Hide()
        childFrame.switchRows[i] = row
    end

    -- Add case button
    childFrame.addCaseBtn = CreateFrame("Button", nil, switchUI, "UIPanelButtonTemplate")
    childFrame.addCaseBtn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    childFrame.addCaseBtn:SetSize(90, 18)
    childFrame.addCaseBtn:SetText("+ Add Case")
    childFrame.addCaseBtn:SetPoint("TOPLEFT", childFrame.switchRows[1], "BOTTOMLEFT", 0, -5)
    childFrame.addCaseBtn:SetScript("OnClick", function()
        if #childFrame.switchCases < MAX_SWITCH_CASES then
            frame:CollectSwitchState()
            childFrame.switchCases[#childFrame.switchCases + 1] = { condType = "default", value = "", routeData = {} }
            frame:RefreshSwitchRows()
            validateFields()
        end
    end)

    switchUI:Hide()
    childFrame:Hide()

    return childFrame
end

---------------------------------------------------------------------------
-- Mode toggle — show condition or switch UI
---------------------------------------------------------------------------

function frame:UpdateConditionalMode()
    local cf = frame.conditional
    if cf.mode == "condition" then
        cf.conditionUI:Show()
        cf.switchUI:Hide()
        frame:UpdateConditionFields()
    else
        cf.conditionUI:Hide()
        cf.switchUI:Show()
        frame:RefreshSwitchRows()
    end
end

---------------------------------------------------------------------------
-- Condition mode: show / hide type-specific fields
---------------------------------------------------------------------------

function frame:UpdateConditionFields()
    local cf = frame.conditional
    local t = cf.condType or "achievement"

    cf.condId.label:Hide();      cf.condId.input:Hide()
    cf.factionBtn:Hide();        cf.factionLabel:Hide()
    cf.condLevel.label:Hide();   cf.condLevel.input:Hide()
    cf.condClass.label:Hide();   cf.condClass.input:Hide()

    if t == "achievement" or t == "quest" then
        cf.condId.label:SetText(t == "achievement" and "Achievement ID" or "Quest ID")
        cf.condId.label:Show();  cf.condId.input:Show()
    elseif t == "faction" then
        cf.factionBtn:Show();    cf.factionLabel:Show()
    elseif t == "level" then
        cf.condLevel.label:Show(); cf.condLevel.input:Show()
    elseif t == "class" then
        cf.condClass.label:Show(); cf.condClass.input:Show()
    end
end

---------------------------------------------------------------------------
-- Switch mode: refresh rows from switchCases data
---------------------------------------------------------------------------

function frame:RefreshSwitchRows()
    local cf = frame.conditional
    for i = 1, MAX_SWITCH_CASES do
        local row = cf.switchRows[i]
        if i <= #cf.switchCases then
            local case = cf.switchCases[i]
            row.condType = case.condType
            row.originalCondition = case.originalCondition
            row.condBtn:SetText(conditionLabelLookup[case.condType] or case.condType)
            row.valueInput:SetText(case.value or "")

            -- Route count display
            local routeCount = case.routeData and #case.routeData or 0
            row.routeCount:SetText(routeCount .. " route" .. (routeCount ~= 1 and "s" or ""))

            -- Edit Routes button handler
            local rowIndex = i
            row.editRoutesBtn:SetScript("OnClick", function()
                frame:CollectSwitchState()

                -- Build and save the switch entry to the parent's route array
                local switchEntry = frame:BuildSwitchEntry()
                local parentEntry = frame.viewer.editing[#frame.viewer.editing]
                local parentIsCaseRef = type(parentEntry) == "table" and parentEntry.caseRef
                local parentRouteArray

                if parentIsCaseRef then
                    local caseData = frame:ResolveCaseRef(parentEntry)
                    if not caseData.routes then
                        caseData.routes = caseData.route and { caseData.route } or {}
                        caseData.route = nil
                    end
                    parentRouteArray = caseData.routes
                else
                    parentRouteArray = addon.data.routes[parentEntry].route
                end

                local editIndex = cf.editing
                if editIndex then
                    parentRouteArray[editIndex] = switchEntry
                else
                    parentRouteArray[#parentRouteArray + 1] = switchEntry
                    cf.editing = #parentRouteArray
                    editIndex = cf.editing
                end

                addon.menu = addon.processRoutes(addon.data.routes)
                addon.ui.SegmentFrame:Refresh()

                -- Build case ref with root/chain format
                local root, chain
                if parentIsCaseRef then
                    root = parentEntry.root
                    chain = {}
                    for _, step in ipairs(parentEntry.chain) do
                        chain[#chain + 1] = { entry = step.entry, case = step.case }
                    end
                    chain[#chain + 1] = { entry = editIndex, case = rowIndex }
                else
                    root = parentEntry
                    chain = { { entry = editIndex, case = rowIndex } }
                end

                local caseLabel = conditionLabelLookup[case.condType] or case.condType
                if case.value and case.value ~= "" and case.value ~= "(compound)" then
                    caseLabel = caseLabel .. ": " .. case.value
                end

                table.insert(frame.viewer.editing, {
                    caseRef = true,
                    root = root,
                    chain = chain,
                    label = caseLabel,
                })

                cf:Hide()
                frame:LoadViewerRows()
            end)

            if case.originalCondition then
                -- Compound condition — keep type visible but locked
                row.condBtn:Disable()
                row.valueInput:Disable()
            elseif case.condType == "default" then
                row.condBtn:Enable()
                row.valueInput:SetText("")
                row.valueInput:Disable()
            else
                row.condBtn:Enable()
                row.valueInput:Enable()
            end

            row:Show()
        else
            row:Hide()
        end
    end

    -- Reposition add button below last visible row
    cf.addCaseBtn:ClearAllPoints()
    local lastIdx = math.min(#cf.switchCases, MAX_SWITCH_CASES)
    if lastIdx > 0 then
        cf.addCaseBtn:SetPoint("TOPLEFT", cf.switchRows[lastIdx], "BOTTOMLEFT", 0, -5)
    else
        cf.addCaseBtn:SetPoint("TOPLEFT", cf.switchRows[1], "TOPLEFT", 0, 0)
    end

    if #cf.switchCases >= MAX_SWITCH_CASES then
        cf.addCaseBtn:Disable()
    else
        cf.addCaseBtn:Enable()
    end
end

---------------------------------------------------------------------------
-- Switch mode: sync current UI state back into switchCases data
---------------------------------------------------------------------------

function frame:CollectSwitchState()
    local cf = frame.conditional
    for i = 1, #cf.switchCases do
        local row = cf.switchRows[i]
        cf.switchCases[i].condType = row.condType
        cf.switchCases[i].value = row.valueInput:GetText()
        cf.switchCases[i].originalCondition = row.originalCondition
        -- routeData is stored directly in switchCases, not in a UI element
    end
end

---------------------------------------------------------------------------
-- Build switch entry table from current switchCases data
---------------------------------------------------------------------------

function frame:BuildSwitchEntry()
    local cf = frame.conditional
    local switchData = {}
    for _, case in ipairs(cf.switchCases) do
        local caseEntry = {}
        if case.originalCondition then
            caseEntry.condition = case.originalCondition
        elseif case.condType ~= "default" then
            caseEntry.condition = buildCondition(case.condType, case.value)
        end
        if case.routeData and #case.routeData > 0 then
            if #case.routeData == 1 and type(case.routeData[1]) == "string" then
                caseEntry.route = case.routeData[1]
            else
                caseEntry.routes = case.routeData
            end
        end
        switchData[#switchData + 1] = caseEntry
    end
    return { switch = switchData }
end

---------------------------------------------------------------------------
-- New / Load / Save
---------------------------------------------------------------------------

function frame:NewConditional()
    local cf = frame.conditional
    cf.mode = "condition"
    cf.modeBtn:SetText("Condition")
    cf.isReadOnly = false
    cf.readOnlyText:Hide()

    cf.condType = "achievement"
    cf.condBtn:SetText("Achievement")
    cf.condBtn:Enable()
    cf.condId.input:SetText("")
    cf.factionValue = "Horde"
    cf.factionBtn:SetText("Horde")
    cf.condLevel.input:SetText("")
    cf.condClass.input:SetText("")
    cf.passRoute.input:SetText("")
    cf.failRoute.input:SetText("")

    cf.switchCases = {}
    cf.save:Disable()

    frame:UpdateConditionalMode()
    frame.viewer:Hide()
    cf:Show()
end

function frame:LoadConditional(data)
    local cf = frame.conditional
    cf.isReadOnly = false
    cf.readOnlyText:Hide()

    if data.switch then
        -- Switch mode
        cf.mode = "switch"
        cf.modeBtn:SetText("Switch")

        cf.switchCases = {}
        for _, case in ipairs(data.switch) do
            local caseData = {}
            if case.condition then
                local cType = case.condition.type
                if cType == "all" or cType == "any" then
                    -- Compound condition — preserve original, show as locked
                    caseData.condType = cType
                    caseData.value = "(compound)"
                    caseData.originalCondition = case.condition
                else
                    caseData.condType = cType
                    caseData.value = extractConditionValue(case.condition)
                    caseData.originalCondition = nil
                end
            else
                caseData.condType = "default"
                caseData.value = ""
                caseData.originalCondition = nil
            end
            -- Store route data as an array
            caseData.routeData = case.routes or (case.route and { case.route }) or {}
            cf.switchCases[#cf.switchCases + 1] = caseData
        end

        frame:UpdateConditionalMode()
        cf.save:Disable()
        frame.viewer:Hide()
        cf:Show()
        return
    end

    -- Condition mode
    local cond = data.condition
    if not cond then return end

    cf.mode = "condition"
    cf.modeBtn:SetText("Condition")

    if cond.type == "all" or cond.type == "any" then
        cf.isReadOnly = true
        cf.readOnlyText:SetText("Compound condition (" .. cond.type .. ") — edit via data file")
        cf.readOnlyText:Show()
        cf.condBtn:Disable()
        cf.passRoute.input:Disable()
        cf.failRoute.input:Disable()
        cf.save:Disable()
        cf.condType = "achievement"
        cf.condBtn:SetText(cond.type)
        cf.passRoute.input:SetText(formatRouteField(data.pass))
        cf.failRoute.input:SetText(formatRouteField(data.fail))
    else
        cf.condType = cond.type or "achievement"
        cf.condBtn:SetText(conditionLabelLookup[cf.condType] or cf.condType)
        cf.condBtn:Enable()
        cf.passRoute.input:Enable()
        cf.failRoute.input:Enable()

        cf.condId.input:SetText("")
        cf.factionValue = "Horde"
        cf.factionBtn:SetText("Horde")
        cf.condLevel.input:SetText("")
        cf.condClass.input:SetText("")

        if cond.type == "achievement" or cond.type == "quest" then
            cf.condId.input:SetText(cond.id and tostring(cond.id) or "")
        elseif cond.type == "faction" then
            cf.factionValue = cond.faction or "Horde"
            cf.factionBtn:SetText(cf.factionValue)
        elseif cond.type == "level" then
            cf.condLevel.input:SetText(cond.level and tostring(cond.level) or "")
        elseif cond.type == "class" then
            cf.condClass.input:SetText(cond.class or "")
        end

        cf.passRoute.input:SetText(formatRouteField(data.pass))
        cf.failRoute.input:SetText(formatRouteField(data.fail))
    end

    cf.switchCases = {}

    frame:UpdateConditionalMode()
    cf.save:Disable()
    frame.viewer:Hide()
    cf:Show()
end

function frame:SaveConditional()
    local cf = frame.conditional
    if cf.isReadOnly then return end

    local entry

    if cf.mode == "condition" then
        local condition = buildCondition(cf.condType, "")
        if cf.condType == "achievement" or cf.condType == "quest" then
            condition.id = tonumber(cf.condId.input:GetText())
        elseif cf.condType == "faction" then
            condition.faction = cf.factionValue
        elseif cf.condType == "level" then
            condition.level = tonumber(cf.condLevel.input:GetText())
        elseif cf.condType == "class" then
            condition.class = cf.condClass.input:GetText()
        end

        entry = {
            condition = condition,
            pass = parseRouteField(cf.passRoute.input:GetText()),
            fail = parseRouteField(cf.failRoute.input:GetText()),
        }
    else
        -- Switch mode
        frame:CollectSwitchState()
        entry = frame:BuildSwitchEntry()
    end

    local parentEntry = frame.viewer.editing[#frame.viewer.editing]
    local parentRouteArray
    if type(parentEntry) == "table" and parentEntry.caseRef then
        local caseData = frame:ResolveCaseRef(parentEntry)
        if not caseData.routes then
            caseData.routes = caseData.route and { caseData.route } or {}
            caseData.route = nil
        end
        parentRouteArray = caseData.routes
    else
        parentRouteArray = addon.data.routes[parentEntry].route
    end

    local editIndex = cf.editing
    if editIndex ~= nil then
        parentRouteArray[editIndex] = entry
    else
        parentRouteArray[#parentRouteArray + 1] = entry
    end

    addon.menu = addon.processRoutes(addon.data.routes)
    addon.ui.SegmentFrame:Refresh()
    frame:LoadViewerRows()

    cf:Hide()
    frame.viewer:Show()
end
