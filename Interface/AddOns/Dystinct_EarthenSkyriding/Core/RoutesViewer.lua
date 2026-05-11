local addonName, addon = ...

local frame = addon.ui.RoutesFrame

local visibleRows = 9
local frameHeight = 34

function frame:InitializeViewer()
    
    local deleteOnClick = function()
        frame.viewer:Hide()
        frame.delete.warning:SetText("Are you sure you want to delete " .. frame.viewer.editing[#frame.viewer.editing] .. "?")
        frame.delete:Show()
    end

    local discardOnClick = function()
        frame.viewer.modified = false
        frame:LoadViewerRows(frame.viewer.editing[#frame.viewer.editing])
        frame:Refresh()
    end

    local function exportOnClick()
        local routeList = addon:GetRouteTree(addon.data.routes, frame.viewer.editing[#frame.viewer.editing])
        local exportTable = {}
        for _, name in ipairs(routeList) do
            exportTable[name] = addon.data.routes[name]
        end
        frame.export.editbox:SetText(addon:ExportTableToString(exportTable))
        frame.export.editbox:HighlightText(0)
        frame.viewer:Hide()
        frame.export:Show()
    end

    local childFrame = addon:BuildFrame(frame, {
        scroll = true,
        buttons = {
            { name = "add", label = "Add Segment", anchor = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 } },
            { name = "rename", label = "Rename", anchor = { "RIGHT", "add", "LEFT", -3, 0 }, width = 70 },
            { name = "save", label = "Save", anchor = { "RIGHT", "rename", "LEFT", -3, 0 }, width = 70, disable = true, script = function() frame:SaveViewer() end },
            { name = "discard", label = "Cancel", anchor = { "RIGHT", "save", "LEFT", -3, 0 }, width = 70, disable = true, script = discardOnClick },
            { name = "delete", label = "Delete", anchor = { "BOTTOMLEFT", nil, "BOTTOMLEFT", -3, 0 }, width = 70, script = deleteOnClick },
            { name = "export", label = "Export", anchor = { "LEFT", "delete", "RIGHT", 3, 0 }, width = 70, script = exportOnClick },
        },
        up = function()
            table.remove(frame.viewer.editing)
            if #frame.viewer.editing ~= 0 then
                frame:LoadViewerRows(frame.viewer.editing[#frame.viewer.editing])
            end
            frame:Refresh()
        end
    })

    childFrame.editing = {}
    
    return childFrame
end

function frame:ResolveCaseRef(ref)
    local route = addon.data.routes[ref.root]
    local routeArray = route.route
    for i, step in ipairs(ref.chain) do
        local switchEntry = routeArray[step.entry]
        local caseData = switchEntry.switch[step.case]
        if i == #ref.chain then
            return caseData
        end
        routeArray = caseData.routes or (caseData.route and { caseData.route }) or {}
    end
end

function frame:GetViewerRoute()
    if #frame.viewer.editing == 0 then return nil, nil, false end
    local entry = frame.viewer.editing[#frame.viewer.editing]
    if type(entry) == "table" and entry.caseRef then
        local caseData = frame:ResolveCaseRef(entry)
        local routeList = caseData.routes or (caseData.route and { caseData.route }) or {}
        return entry.label, { class = "segment", route = routeList, display = entry.label }, true
    end
    return entry, addon.data.routes[entry], false
end

function frame:RefreshViewer()
    local count = 0
    for index, row in ipairs(frame.viewer.rows) do
        if frame.viewer.rows[index].enabled then
            frame:UpdateViewerRow(index)
            count = count + 1
        else
            frame.viewer.rows[index]:Hide()
        end
    end
    local contentHeight = count * (frameHeight + 2) - 2
    frame.viewer.content:SetSize(280, contentHeight)

    local name, route, isCaseRef = frame:GetViewerRoute()
    if not route then
        frame.viewer.title:SetText("")
    else
        frame.viewer.title:SetText(addon:LocalizedString(route.display or name))
    end

    if addon.active then
        frame.viewer.discard:Disable()
        frame.viewer.save:Disable()
        frame.viewer.delete:Disable()
        frame.viewer.rename:Disable()
        frame.viewer.add:Disable()
        frame.viewer.export:Enable()
    else
        if frame.viewer.modified then
            frame.viewer.discard:Enable()
            frame.viewer.save:Enable()
            frame.viewer.rename:Disable()
            frame.viewer.add:Disable()
            frame.viewer.export:Disable()
        else
            frame.viewer.discard:Disable()
            frame.viewer.save:Disable()
            frame.viewer.rename:Enable()
            frame.viewer.add:Enable()
            frame.viewer.export:Enable()
        end
        frame.viewer.delete:Enable()

        if isCaseRef then
            frame.viewer.rename:Disable()
            frame.viewer.delete:Disable()
            frame.viewer.export:Disable()
        end
    end

    frame.selection:Hide()
    frame.export:Hide()
    frame.viewer:Show()
end

function frame:LoadViewerRows()
    local name, route, isCaseRef = frame:GetViewerRoute()
    frame.viewer.title:SetText(addon:LocalizedString(route.display or name))

    if route.class == "segment" then
        frame.viewer.add.Text:SetText("Add Segment")
        frame.viewer.add:SetScript("OnClick", function()
            ToggleDropDownMenu(1, nil, addon.dropdown, frame.viewer.add, 0, 0)
        end)
    else
        frame.viewer.add.Text:SetText("New Waypoint")
        frame.viewer.add:SetScript("OnClick", function()
            frame.waypoint.editing = nil
            frame:NewWaypoint()
        end)
    end

    if not isCaseRef then
        local data = { ["name"] = name, ["route"] = route }
        frame.viewer.rename:Enable()
        frame.viewer.rename:SetScript("OnClick", function()
            frame:LoadSegment(data)
        end)
    end

    local maxIndex = 0
    for index, data in ipairs(route.route) do
        frame:UpdateViewerRow(index, data, index)
        frame.viewer.rows[index].enabled = true
        maxIndex = index
    end
    if maxIndex < #frame.viewer.rows then
        for index = maxIndex + 1, #frame.viewer.rows do
            frame.viewer.rows[index].enabled = false
            frame.viewer.rows[index]:Hide()
        end
    end

    frame.viewer.modified = false

    frame:RefreshViewer()
end

function frame:UpdateViewerOrder(index, direction)
    if direction == 0 then
        local entry = table.remove(frame.viewer.rows, index)
        entry.enabled = false
        table.insert(frame.viewer.rows, entry)
    else
        local oldPosition = index
        local newPosition = index + direction
        frame.viewer.rows[oldPosition], frame.viewer.rows[newPosition] = frame.viewer.rows[newPosition], frame.viewer.rows[oldPosition]
    end

    frame.viewer.modified = true

    frame:RefreshViewer()
end

function frame:UpdateViewerRow(index, data)
    local rows = frame.viewer.rows
    
    -- new row
    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.viewer.content)
        row:SetSize(560, frameHeight)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        for index, label in ipairs({ "display", "name", "routes", "map" }) do
            row[label] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row[label]:SetFont("Fonts\\FRIZQT__.TTF", 10)
        end
        
        row.display:SetTextColor(1.0, 1.0, 1.0)

        row.name:SetPoint("LEFT", row.display, "RIGHT", 8, 0)
        row.name:SetTextColor(0.6, 0.6, 0.6)

        row.map:SetTextColor(0.6, 0.6, 0.6)
        row.map:SetPoint("BOTTOMLEFT", row.name, "BOTTOMRIGHT", 8, 0)

        row.routes:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 30, 7)
        row.routes:SetFont("Fonts\\FRIZQT__.TTF", 9)

        row.up = CreateFrame("Button", nil, row)
        row.up:SetSize(21, 21)
        row.up:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
        row.up:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        row.up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled")
        row.up:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down")
        row.up:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled")

        row.down = CreateFrame("Button", nil, row)
        row.down:SetSize(21, 21)
        row.down:SetPoint("TOP", row.up, "BOTTOM", 0, 5)
        row.down:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        row.down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
        row.down:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
        row.down:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")

        row.delete = CreateFrame("Button", nil, row)
        row.delete:SetSize(32, 32)
        row.delete:SetPoint("RIGHT", row, "RIGHT", -7, -1)
        row.delete:SetNormalTexture("Interface\\Buttons\\CancelButton-Up")
        row.delete:SetPushedTexture("Interface\\Buttons\\CancelButton-Down")
        row.delete:SetHighlightTexture("Interface\\Buttons\\CancelButton-Highlight")

        row.edit = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.edit.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        row.edit:SetWidth(45)
        row.edit:SetHeight(18)
        row.edit:SetPoint("RIGHT", row.delete, "LEFT", 5, 1)
        row.edit:SetText("Edit")

        row.start = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.start.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        row.start:SetWidth(45)
        row.start:SetHeight(18)
        row.start:SetPoint("RIGHT", row.edit, "LEFT", -2, 0)
        row.start:SetText("Start")

        frame.viewer.rows[#rows + 1] = row
    end

    local row = rows[index]
    if not row.enabled then
        row:Hide()
        row:SetPoint("TOPLEFT", frame.viewer.content, "TOPLEFT", 0, 0)
    else
        row:Show()
        row:SetPoint("TOPLEFT", frame.viewer.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * (index - 1))
    end

    if addon.active then
        row.up:Disable()
        row.down:Disable()
        row.delete:Disable()
    else
        row.up:Enable()
        row.down:Enable()
        row.delete:Enable()

        if index == 1 then
            row.up:Disable()
        end
        if index == #rows then
            row.down:Disable()
        elseif rows[index + 1].enabled then
            row.down:Enable()
        else
            row.down:Disable()
        end

        row.up:SetScript("OnClick", function()
            frame:UpdateViewerOrder(index, -1)
        end)
        row.down:SetScript("OnClick", function()
            frame:UpdateViewerOrder(index, 1)
        end)
        row.delete:SetScript("OnClick", function()
            frame:UpdateViewerOrder(index, 0)
        end)
    end

    if frame.viewer.modified == true or addon.active then
        row.edit:Disable()
    else
        row.edit:Enable()
    end

    if data then
        row.rawEntry = data

        if type(data) == "string" then
            -- Segment subroute reference
            local name = data
            local routeData = addon.data.routes[name]
            row.name:SetText(name)
            row.display:SetText(addon:LocalizedString(routeData and (routeData.display or name) or name))
            local concat = {}
            if routeData then
                local resolved = addon:ResolveRouteList(routeData.route)
                for i = 1, math.min(3, #resolved) do
                    if addon.data.routes[resolved[i]] then
                        concat[#concat + 1] = addon:LocalizedString(addon.data.routes[resolved[i]].display or resolved[i])
                    else
                        concat[#concat + 1] = addon:LocalizedString(resolved[i])
                    end
                end
                if #resolved > 3 then
                    concat[#concat + 1] = "and " .. (#resolved - 3) .. " more"
                end
            end
            row.routes:SetText(table.concat(concat, ", "))
            row.display:SetPoint("TOPLEFT", rows[index], "TOPLEFT", 30, -5)
            row.map:Hide()

            if frame.viewer.modified == true then
                row.edit:Disable()
            else
                row.edit:Enable()
                row.edit:SetScript("OnClick", function()
                    table.insert(frame.viewer.editing, name)
                    frame:LoadViewerRows()
                    frame:RefreshViewer()
                end)
            end

            row.start:Show()
            if addon.active or frame.viewer.modified then
                row.start:Disable()
            else
                row.start:Enable()
                row.start:SetScript("OnClick", function()
                    local node = addon:FindMenuNode(name)
                    if node then
                        addon.ui.SegmentFrame.browsingStack = {}
                        addon:UpdateActive(node)
                        if addon.active ~= nil then
                            addon:StartNewRun()
                        end
                        local routeName = addon.data.routes[node.path[1]].display or node.path[1]
                        addon:Announce("Route Started", addon:LocalizedString(routeName))
                        frame:RefreshViewer()
                    end
                end)
            end

        elseif type(data) == "table" and (data.condition or data.switch) then
            -- Conditional or switch entry (read-only)
            local resolved = addon:ResolveRouteList({ data })
            local resolvedText = #resolved > 0 and table.concat(resolved, ", ") or "(no match)"
            row.display:SetText("|cFFFFCC00Conditional|r")
            row.display:ClearAllPoints()
            row.display:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -5)
            row.name:SetText("")
            row.routes:SetText(resolvedText)
            row.map:Hide()
            row.start:Hide()

            if addon.active or frame.viewer.modified == true then
                row.edit:Disable()
            else
                row.edit:Enable()
                row.edit:SetScript("OnClick", function()
                    frame.conditional.editing = index
                    frame:LoadConditional(data)
                end)
            end

        else
            -- Waypoint data
            row.display:SetText(addon:LocalizedString(data.name))
            local xVal = tonumber(data.x)
            local yVal = tonumber(data.y)
            row.name:SetText(xVal and yVal and (string.format("%.1f", xVal) .. ", " .. string.format("%.1f", yVal)) or "")

            -- Build second-line info: note + trigger/action tags
            local info = data.note or ""
            if data.trigger and data.trigger.type then
                info = (info ~= "" and (info .. "  ") or "") .. "|cFF87e6e8[" .. data.trigger.type .. "]|r"
            end
            if data.action then
                info = (info ~= "" and (info .. "  ") or "") .. "|cFFFFCC00[action]|r"
            end
            row.routes:SetText(info)

            row.map:Show()
            local editEntry = frame.viewer.editing[#frame.viewer.editing]
            local parentRoute = type(editEntry) == "string" and addon.data.routes[editEntry]
            local mapID = tonumber(data.map) or (parentRoute and tonumber(parentRoute.map)) or nil
            if mapID ~= nil then
                local map = C_Map.GetMapInfo(mapID)
                local continent = map and map.name or ""
                row.map:SetText(continent)
            else
                row.map:SetText("")
            end
            local hasSecondLine = info ~= ""
            if hasSecondLine then
                row.display:ClearAllPoints()
                row.display:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -5)
            else
                row.display:ClearAllPoints()
                row.display:SetPoint("LEFT", row, "LEFT", 30, 0)
            end

            if addon.active or frame.viewer.modified == true then
                row.edit:Disable()
            else
                row.edit:Enable()
                row.edit:SetScript("OnClick", function()
                    frame.waypoint.editing = index
                    frame:LoadWaypoint(data)
                    frame:ShowWaypointEditor()
                end)
            end

            row.start:Hide()
        end
        row.data = data
    end
end

function frame:SaveViewer()
    local entry = frame.viewer.editing[#frame.viewer.editing]
    local isCaseRef = type(entry) == "table" and entry.caseRef

    if isCaseRef then
        local updatedRoute = {}
        for index, row in ipairs(frame.viewer.rows) do
            if row.enabled == false then break end
            table.insert(updatedRoute, row.rawEntry or row.name:GetText())
        end
        local caseData = frame:ResolveCaseRef(entry)
        if #updatedRoute == 1 and type(updatedRoute[1]) == "string" then
            caseData.route = updatedRoute[1]
            caseData.routes = nil
        else
            caseData.routes = updatedRoute
            caseData.route = nil
        end
        addon.menu = addon.processRoutes(addon.data.routes)
        addon.ui.SegmentFrame:Refresh()
    else
        local name = entry
        local route = addon.data.routes[name]

        if route.class == "segment" then
            local updatedRoute = {}
            for index, row in ipairs(frame.viewer.rows) do
                if row.enabled == false then break end
                table.insert(updatedRoute, row.rawEntry or row.name:GetText())
            end
            route.route = updatedRoute
            addon.menu = addon.processRoutes(addon.data.routes)
            addon.ui.SegmentFrame:Refresh()
        else
            local updatedRoute = {}
            for index, row in ipairs(frame.viewer.rows) do
                if row.enabled == false then break end
                table.insert(updatedRoute, row.data)
            end
            route.route = updatedRoute
            addon.ui.SegmentFrame:Refresh()
        end
    end

    frame.viewer.modified = false

    frame:RefreshViewer()
end