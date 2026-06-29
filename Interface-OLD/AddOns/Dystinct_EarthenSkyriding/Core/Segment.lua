local addonName, addon = ...

local frame = addon.ui.SegmentFrame

local visibleRows = 9
local frameHeight = 22
local largerFrameHeight = 34

local function sortRouteItems(items)
    table.sort(items, function(a, b)
        local aIsLeaf = not a.children or #a.children == 0
        local bIsLeaf = not b.children or #b.children == 0
        if aIsLeaf ~= bIsLeaf then
            return not aIsLeaf
        end
        return (a.display or a.name):lower() < (b.display or b.name):lower()
    end)
end

local function startRunFromNode(node)
    frame.browsingStack = {}
    addon:UpdateActive(node)
    if addon.active ~= nil then
        addon:StartNewRun()
    end
    addon.ui.RoutesFrame.viewer.editing = {}
    addon.ui.RoutesFrame.selection:Show()
    addon.ui.RoutesFrame.viewer:Hide()
    addon.ui.RoutesFrame.delete:Hide()
    addon.ui.RoutesFrame.segment:Hide()
    addon.ui.RoutesFrame.waypoint:Hide()
    local routeName = addon.data.routes[node.path[1]].display or node.path[1]
    addon:Announce("Route Started", addon:LocalizedString(routeName))
end

function frame:Initialize()
    frame.browsingStack = {}

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -15)

    frame.back = CreateFrame("Button", nil, frame)
    frame.back:SetSize(30, 30)
    frame.back:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -6)
    frame.back:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.back:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    frame.back:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    frame.back:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    frame.back:SetScript("OnClick", function()
        table.remove(frame.browsingStack)
        frame:Refresh()
    end)
    frame.back:Hide()

    frame.routesscroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.routesscroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -46.5)
    frame.routesscroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 27)

    frame.routescontent = CreateFrame("Frame", nil, frame.routesscroll)
    frame.routesscroll:SetScrollChild(frame.routescontent)
    frame.routes = {}

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -46.5)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 27)

    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows = {}

    frame.scroll:Hide()

    frame.abandon = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.abandon.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
	frame.abandon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -3, 0)
	frame.abandon:SetWidth(100)
	frame.abandon:SetHeight(20)
	frame.abandon:SetText("Abandon Run")
    frame.abandon:Disable()
    frame.abandon:SetScript("OnClick", function(self, button)
        addon:ClearActive()
    end)

    frame.prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.prev.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
	frame.prev:SetPoint("LEFT", frame.abandon, "RIGHT", 3, 0)
	frame.prev:SetWidth(120)
	frame.prev:SetHeight(20)
	frame.prev:SetText("Previous Segment")
    frame.prev:Disable()
    frame.prev:SetScript("OnClick", function(self, button)
        addon:JumpToPreviousSegment()
    end)

    frame.skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.skip.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
	frame.skip:SetPoint("LEFT", frame.prev, "RIGHT", 3, 0)
	frame.skip:SetWidth(100)
	frame.skip:SetHeight(20)
	frame.skip:SetText("Next Segment")
    frame.skip:Disable()
    frame.skip:SetScript("OnClick", function(self, button)
        addon.waypoint.index = #addon.segment.route
        addon.segment.route[addon.waypoint.index].discovered = true
        addon:DetermineNextWaypoint()
        frame:Refresh()
    end)

    frame.selectMenu = CreateFrame("Frame", "DysES_SegmentSelectMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(frame.selectMenu, function(dropdown, level)
        if not addon.active then return end
        local root = addon.menu[addon.active.path[1]]
        local leaves = addon:GetAllLeaves(root)
        for i, leaf in ipairs(leaves) do
            local info = UIDropDownMenu_CreateInfo()
            local section = leaf.path[#leaf.path]
            info.text = addon:LocalizedString(addon.data.routes[section].display or section)
            info.checked = (addon.active.name == leaf.name)
            info.func = function()
                addon:JumpToSegment(leaf)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    frame.select = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.select.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
	frame.select:SetPoint("LEFT", frame.skip, "RIGHT", 3, 0)
	frame.select:SetWidth(60)
	frame.select:SetHeight(20)
	frame.select:SetText("Select")
    frame.select:Disable()
    frame.select:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, frame.selectMenu, self, 0, 0)
    end)

    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
	frame.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.next:SetWidth(70)
	frame.next:SetHeight(20)
	frame.next:SetText("Next")
    frame.next:Disable()
    frame.next:SetScript("OnClick", function(self, button)
        addon.segment.route[addon.waypoint.index].discovered = true
        addon:DetermineNextWaypoint()
        frame:Refresh()
    end)

    frame:Refresh()

    return frame
end

function frame:Refresh()
    if addon.waypoint.index then
        frame.routesscroll:Hide()
        frame.back:Hide()
        frame:ShowActiveSegment()
    else
        frame.scroll:Hide()
        frame:ShowBrowseView()
    end

    local hasActive = addon.active ~= nil
    frame.abandon:SetEnabled(hasActive)
    frame.next:SetEnabled(hasActive)

    if hasActive then
        local root = addon.menu[addon.active.path[1]]
        local hasPrev = addon:FindPreviousLeaf(root, addon.active.path) ~= nil
        local hasNextLeaf = addon:FindNextLeaf(root, addon.active.path) ~= nil
        local leafCount = #addon:GetAllLeaves(root)

        frame.prev:SetEnabled(hasPrev)
        frame.skip:SetEnabled(hasNextLeaf)
        frame.select:SetEnabled(leafCount > 1)
    else
        frame.prev:SetEnabled(false)
        frame.skip:SetEnabled(false)
        frame.select:SetEnabled(false)
    end
end

function frame:ShowBrowseView()
    local items = {}

    if #frame.browsingStack == 0 then
        for _, node in pairs(addon.menu) do
            items[#items + 1] = node
        end
        frame.title:SetText("Select a Route")
        frame.back:Hide()
    else
        local current = frame.browsingStack[#frame.browsingStack]
        for _, child in ipairs(current.children) do
            items[#items + 1] = child
        end

        local parts = {}
        for _, node in ipairs(frame.browsingStack) do
            parts[#parts + 1] = addon:LocalizedString(node.display or node.name)
        end
        frame.title:SetText(table.concat(parts, "  >  "))
        frame.back:Show()
    end

    sortRouteItems(items)

    for i, node in ipairs(items) do
        frame:UpdateRoutesRow(i, node)
    end

    if #items < #frame.routes then
        for index = #items + 1, #frame.routes do
            frame.routes[index]:Hide()
        end
    end

    local contentHeight = #items * (largerFrameHeight + 2) - 2
    frame.routescontent:SetSize(280, contentHeight)
    frame.routesscroll:Show()
end

function frame:ShowActiveSegment()
    local display_title = {}

    if #addon.active.path > 3 then
        display_title[1] = addon.data.routes[addon.active.path[1]].display or addon.active.path[1]
        display_title[2] = "..."
        display_title[3] = addon.data.routes[addon.active.path[#addon.active.path - 1]].display or addon.active.path[#addon.active.path - 1]
        display_title[4] = addon.data.routes[addon.active.path[#addon.active.path]].display or addon.active.path[#addon.active.path]
    else
        for index, name in ipairs(addon.active.path) do
            display_title[#display_title + 1] = addon:LocalizedString(addon.data.routes[name].display or name)
        end
    end
    frame.title:SetText(table.concat(display_title, "  >  "))

    local halfVisible = math.floor(visibleRows / 2)

    for index, waypoint in ipairs(addon.segment.route) do
        frame:UpdateRow(index, waypoint)
    end

    if #addon.segment.route < #frame.rows then
        for index=#addon.segment.route + 1,#frame.rows do
            frame.rows[index]:Hide()
        end
    end

    local contentHeight = #addon.segment.route * (frameHeight + 2) - 2
    frame.content:SetSize(280, contentHeight)

    local maxScroll = contentHeight - (visibleRows * (frameHeight + 2)) + 2
    local targetIndex = addon.waypoint.index

    local scrollPosition
    if targetIndex <= halfVisible then
        scrollPosition = 0
    elseif targetIndex > #addon.segment.route - halfVisible then
        scrollPosition = maxScroll
    else
        scrollPosition = (targetIndex - halfVisible - 1) * (frameHeight + 2)
    end

    scrollPosition = math.max(0, math.min(scrollPosition, maxScroll))
    frame.scroll:Show()
    C_Timer.After(0, function()
        frame.scroll:SetVerticalScroll(scrollPosition)
    end)
end

local function RowLeftClicked(index)
    addon.segment.route[index].discovered = false
    addon.waypoint.index = index
    addon:UpdateWaypointArrow()
    frame:Refresh()
    addon:SaveProgress()
end

local function RowRightClicked(index)
    addon.segment.route[index].discovered = not addon.segment.route[index].discovered
    if index == addon.waypoint.index then
        addon:DetermineNextWaypoint()
        addon:UpdateWaypointArrow()
    else
        addon:SaveProgress()
    end
    frame:Refresh()
end

function frame:UpdateRow(index, waypoint)
    local rows = frame.rows
    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(560, frameHeight)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * #rows)
        row:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                RowRightClicked(index)
            elseif button == "LeftButton" then
                RowLeftClicked(index)
            end
        end)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        local columnX = { 20, 65, 95 }
        for index, label in ipairs({ "x", "y", "name" }) do
            row[label] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row[label]:SetPoint(index < 3 and "CENTER" or "LEFT", row, "LEFT", columnX[index], 0)
            row[label]:SetFont("Fonts\\FRIZQT__.TTF", 10)
        end

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        frame.rows[#rows + 1] = row
    end

    for i, label in ipairs({ "x", "y", "name" }) do
        if i < 3 then
            local val = tonumber(waypoint.data[label])
            frame.rows[index][label]:SetText(val and string.format("%.1f", val) or "")
        else
            frame.rows[index][label]:SetText(addon:LocalizedString(waypoint.data[label]))
        end

        if index == addon.waypoint.index then
            frame.rows[index][label]:SetTextColor(1.0, 1.0, 1.0)
        elseif waypoint.discovered then
            frame.rows[index][label]:SetTextColor(0.3, 0.3, 0.3)
        else
            frame.rows[index][label]:SetTextColor(0.6, 0.66, 0.6)
        end
    end

    frame.rows[index]:Show()
end

function frame:UpdateRoutesRow(index, node)
    local rows = frame.routes
    local name = node.name
    local route = addon.data.routes[name]
    local isSegment = node.children and #node.children > 0

    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.routescontent)
        row:SetSize(560, largerFrameHeight)
        row:SetPoint("TOPLEFT", frame.routescontent, "TOPLEFT", 0, -1 * (largerFrameHeight + 2) * #rows)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        for _, label in ipairs({ "display", "name", "routes" }) do
            row[label] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row[label]:SetFont("Fonts\\FRIZQT__.TTF", 10)
        end

        row.display:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
        row.name:SetPoint("LEFT", row.display, "RIGHT", 8, 0)
        row.name:SetTextColor(0.6, 0.6, 0.6)
        row.routes:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 7)
        row.routes:SetFont("Fonts\\FRIZQT__.TTF", 9)

        row.start = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.start.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        row.start:SetWidth(60)
        row.start:SetHeight(20)
        row.start:SetPoint("RIGHT", row, "RIGHT", -15, 0)
        row.start:SetText("Start")

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        frame.routes[#rows + 1] = row
    end

    rows[index]:SetScript("OnMouseDown", function(self, button)
        startRunFromNode(node)
    end)

    if isSegment then
        rows[index].start:SetText("Examine")
        rows[index].start:SetScript("OnClick", function()
            frame.browsingStack[#frame.browsingStack + 1] = node
            frame:Refresh()
        end)
        rows[index].start:Show()
    else
        rows[index].start:Hide()
    end

    rows[index].display:SetTextColor(1.0, 1.0, 1.0)

    rows[index].display:SetText(addon:LocalizedString(route.display or name))
    rows[index].name:SetText(name)

    if route.class == "segment" then
        local resolved = addon:ResolveRouteList(route.route)
        local routeNames = {}
        for i = 1, math.min(3, #resolved) do
            if addon.data.routes[resolved[i]] then
                routeNames[#routeNames + 1] = addon:LocalizedString(addon.data.routes[resolved[i]].display or resolved[i])
            end
        end
        if #resolved > 3 then
            routeNames[#routeNames + 1] = "and " .. (#resolved - 3) .. " more"
        end
        rows[index].routes:SetText(table.concat(routeNames, ", "))
    else
        local waypoints = {}
        for i = 1, math.min(3, #route.route) do
            waypoints[i] = addon:LocalizedString(route.route[i].name)
        end
        if #route.route > 3 then
            waypoints[4] = "and " .. (#route.route - 3) .. " more"
        end
        rows[index].routes:SetText(table.concat(waypoints, ", "))
    end

    frame.routes[index]:Show()
end
