local addonName, addon = ...

local frame = addon.ui.RoutesFrame

local visibleRows = 9
local frameHeight = 34

function frame:InitializeSelection()
    local childFrame = addon:BuildFrame(frame, {
        title = "Select a Path or Segment",
        scroll = true,
        buttons = {
            { name = "create", label = "Create New", anchor = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 }, script = function() ToggleDropDownMenu(1, nil, addon.dropdown, frame.selection.create, 0, 0) end }
        }
    })

    return childFrame
end

function frame:RefreshSelection()
    frame.selection.title:SetText("Select a Path or Segment")

    local sorted = {}
    for name, route in pairs(addon.data.routes) do
        if route ~= nil then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted, function(a, b)
        local ra, rb = addon.data.routes[a], addon.data.routes[b]
        if ra.class ~= rb.class then
            return ra.class == "segment"
        end
        return (ra.display or a):lower() < (rb.display or b):lower()
    end)

    for i, name in ipairs(sorted) do
        frame:UpdateSelectionRow(i, name)
        frame.selection.rows[i]:Show()
    end

    if #sorted < #frame.selection.rows then
        for index = #sorted + 1, #frame.selection.rows do
            frame.selection.rows[index]:Hide()
        end
    end

    local contentHeight = #sorted * (frameHeight + 2) - 2
    frame.selection.content:SetSize(280, contentHeight)
    frame.viewer:Hide()
    frame.selection:Show()
end

function frame:UpdateSelectionRow(index, name)
    local rows = frame.selection.rows
    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.selection.content)
        row:SetSize(560, frameHeight)
        row:SetPoint("TOPLEFT", frame.selection.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * #rows)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        row.icon = row:CreateTexture(nil, "BORDER")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

        for index, label in ipairs({ "display", "name", "routes" }) do
            row[label] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row[label]:SetFont("Fonts\\FRIZQT__.TTF", 10)
        end
        
        row.display:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -5)
        row.display:SetTextColor(1.0, 1.0, 1.0)

        row.name:SetPoint("LEFT", row.display, "RIGHT", 8, 0)
        row.name:SetTextColor(0.6, 0.6, 0.6)

        row.routes:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 42, 7)
        row.routes:SetFont("Fonts\\FRIZQT__.TTF", 9)

        row.start = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.start.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        row.start:SetWidth(50)
        row.start:SetHeight(20)
        row.start:SetPoint("RIGHT", row, "RIGHT", -15, 0)
        row.start:SetText("Start")

        frame.selection.rows[#rows + 1] = row
    end
    rows[index]:SetScript("OnMouseDown", function(self, button)
        table.insert(frame.viewer.editing, name)
        frame:LoadViewerRows(name)
    end)
    rows[index].start:SetScript("OnClick", function()
        local node = addon:FindMenuNode(name)
        if node then
            addon.ui.SegmentFrame.browsingStack = {}
            addon:UpdateActive(node)
            if addon.active ~= nil then
                addon:StartNewRun()
            end
            local routeName = addon.data.routes[node.path[1]].display or node.path[1]
            addon:Announce("Route Started", addon:LocalizedString(routeName))
        end
    end)
    rows[index].start:SetEnabled(addon.active == nil)
    local route = addon.data.routes[name]
    rows[index].display:SetText(addon:LocalizedString(route.display or name))
    rows[index].name:SetText(name)

    if route.class == "segment" then
        rows[index].icon:SetTexture(237383)
        local resolved = addon:ResolveRouteList(route.route)
        local routes = {}
        for i=1,math.min(3, #resolved) do
            if addon.data.routes[resolved[i]] then
                routes[#routes + 1] = addon:LocalizedString(addon.data.routes[resolved[i]].display or resolved[i])
            end
        end
        if #resolved > 3 then
            routes[#routes + 1] = "and " .. (#resolved - 3) .. " more"
        end
        rows[index].routes:SetText(table.concat(routes, ", "))
    else
        rows[index].icon:SetTexture(1519350)
        local waypoints = {}
        for i=1,math.min(3, #route.route) do
            waypoints[i] = addon:LocalizedString(route.route[i].name)
        end
        if #route.route > 3 then
            waypoints[4] = "and " .. (#route.route - 3) .. " more"
        end
        rows[index].routes:SetText(table.concat(waypoints, ", "))
    end
end