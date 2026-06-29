local addonName, addon = ...

local frame = addon.ui.SettingsFrame

function frame:Initialize()
    frame.confirm = frame:InitializeConfirm()
    frame.options = frame:InitializeOptions()
    frame.import = frame:InitializeImport()
    frame.export = frame:InitializeExport()
end

function frame:Refresh()
    frame.options.clear_runs:SetEnabled(addon.active == nil)
    frame.options.reset_routes:SetEnabled(addon.active == nil)

    frame.options.import_routes:SetEnabled(addon.importExportEnabled)
    frame.options.export_routes:SetEnabled(addon.importExportEnabled)

    frame.options.toggle_minimap:SetText(addon.data.minimap.hidden and "Show Minimap Button" or "Hide Minimap Button")
    frame.options.move_announcement:SetText(addon.ui.AnnouncementFrame:IsVisible() and "Lock Announcements" or "Move Announcements")

    local tt = addon.data.waypoints.tomtom
    frame.options.toggle_tomtom:SetText("TomTom: " .. (tt == "enable" and "Enabled" or tt == "disable" and "Disabled" or "Auto"))
    local pp = addon.data.waypoints.pins
    frame.options.toggle_pins:SetText("Pins: " .. (pp == "enable" and "Enabled" or pp == "disable" and "Disabled" or "Auto"))

    frame.options.toggle_mapOverlay:SetText(addon.data.waypoints.mapOverlay and "Disable Map Overlay" or "Enable Map Overlay")

    if addon.active ~= nil then
        frame:ShowContainer("options")
    end
end

function frame:ShowContainer(container)
    for _, name in ipairs({ "options", "confirm", "import", "export" }) do
        frame[name]:SetShown(container == name)
    end
end

function frame:InitializeOptions()
    local function move_announcementOnClick()
        addon.ui.AnnouncementFrame.label:SetText("Announcement")
        addon.ui.AnnouncementFrame.heading:SetText("Click and Drag")
        addon.ui.AnnouncementFrame:SetShown(not addon.ui.AnnouncementFrame:IsVisible())
        frame.options.move_announcement:SetText(addon.ui.AnnouncementFrame:IsVisible() and "Lock Announcements" or "Move Announcements")
    end

    local function reset_announcementOnClick()
        addon.data.announcement = { anchor = "TOP", relative = "TOP", x = 0, y = -25 }
        addon.ui.AnnouncementFrame:ClearAllPoints()
        addon.ui.AnnouncementFrame:SetPoint(addon.data.announcement.anchor, UIParent, addon.data.announcement.relative, addon.data.announcement.x, addon.data.announcement.y)
    end

    local toggle_noteOnClick = function()
        addon.data.note.visible = not addon.data.note.visible
        addon.ui.NoteFrame:SetShown(addon.data.note.visible and addon.note_active and addon.active)
        frame.options.toggle_note:SetText(addon.data.note.visible and "Disable Notes" or "Enable Notes")
     end

    local function reset_noteOnClick()
        addon.data.note = { visible = true, anchor = "CENTER", relative = "TOP", x = 0, y = -300 }
        addon.ui.NoteFrame:ClearAllPoints()
        addon.ui.NoteFrame:SetPoint(addon.data.note.anchor, UIParent, addon.data.note.relative, addon.data.note.x, addon.data.note.y)
    end

    local function toggle_minimapOnClick()
        addon.data.minimap.hidden = not addon.data.minimap.hidden
        addon.minimapButton:SetShown(not addon.data.minimap.hidden)
        frame.options.toggle_minimap:SetText(addon.data.minimap.hidden and "Show Minimap Button" or "Hide Minimap Button")
    end

    local function cycleWaypointSetting(current)
        if current == "auto" then return "enable"
        elseif current == "enable" then return "disable"
        else return "auto" end
    end

    local function waypointSettingLabel(name, value)
        if value == "enable" then return name .. ": Enabled"
        elseif value == "disable" then return name .. ": Disabled"
        else return name .. ": Auto" end
    end

    local function toggle_tomtomOnClick()
        addon.data.waypoints.tomtom = cycleWaypointSetting(addon.data.waypoints.tomtom)
        frame.options.toggle_tomtom:SetText(waypointSettingLabel("TomTom", addon.data.waypoints.tomtom))
        addon:UpdateWaypointArrow()
    end

    local function toggle_pinsOnClick()
        addon.data.waypoints.pins = cycleWaypointSetting(addon.data.waypoints.pins)
        frame.options.toggle_pins:SetText(waypointSettingLabel("Pins", addon.data.waypoints.pins))
        addon:UpdateWaypointArrow()
    end

    local function toggle_mapOverlayOnClick()
        addon.data.waypoints.mapOverlay = not addon.data.waypoints.mapOverlay
        frame.options.toggle_mapOverlay:SetText(addon.data.waypoints.mapOverlay and "Disable Map Overlays" or "Enable Map Overlays")
        addon:RefreshWorldMapOverlay()
        addon:RefreshMinimapOverlay()
    end

    local function import_routesOnClick()
        frame.import.editbox:SetText("")
        frame.import.scroll:Hide()
        frame.import.editscroll:Show()
        frame.import.confirm:Hide()
        frame.import.import:Show()
        frame:ShowContainer("import")
    end

    local function export_routesOnClick()
        frame.export.editbox:SetText(addon:ExportTableToString(addon.data.routes))
        frame.export.editbox:HighlightText(0)
        frame:ShowContainer("export")
    end

    local function reset_routesOnClick()
        frame.confirm.title:SetText("Reset Route Data Confirmation")
        frame.confirm.warning:SetText("Are you sure you want to clear all custom routes and restore default routes?")

        frame:ShowContainer("confirm")

        frame.confirm.confirm:SetScript("OnClick", function()
            addon.data.routes = addon:DefaultRoutes()
            addon.menu = addon.processRoutes(addon.data.routes)

            addon.ui.SegmentFrame:Refresh()
            addon.ui.RoutesFrame:Refresh()

            frame:ShowContainer("options")
        end)
    end

    local function clear_runsOnClick()
        frame.confirm.title:SetText("Clear Run Data Confirmation")
        frame.confirm.warning:SetText("Are you sure you want to clear all run data?")
        frame:ShowContainer("confirm")

        frame.confirm.confirm:SetScript("OnClick", function(self)
            addon.data.runs = {}
            addon.ui.LogFrame:Refresh()

            frame:ShowContainer("options")
        end)
    end

    local childFrame = addon:BuildFrame(frame, {
        title = "Settings",
        buttons = {
            { name = "toggle_mapOverlay", label = addon.data.waypoints.mapOverlay and "Disable Map Overlays" or "Enable Map Overlays", anchor = { "RIGHT", nil, "CENTER", -5, 70 }, width = 150, script = toggle_mapOverlayOnClick },
            { name = "toggle_minimap", label = addon.data.minimap.hidden and "Show Minimap Button" or "Hide Minimap Button", anchor = { "LEFT", nil, "CENTER", 5, 70 }, width = 150, script = toggle_minimapOnClick },
            { name = "move_announcement", label = "Move Announcements", anchor = { "RIGHT", nil, "CENTER", -5, 40 }, width = 150, script = move_announcementOnClick },
            { name = "reset_announcement", label = "Reset Announcements", anchor = { "LEFT", nil, "CENTER", 5, 40 }, width = 150, script = reset_announcementOnClick },
            { name = "toggle_note", label = addon.data.note.visible and "Disable Notes" or "Enable Notes", anchor = { "RIGHT", nil, "CENTER", -5, 10 }, width = 150, script = toggle_noteOnClick },
            { name = "reset_note", label = "Reset Notes", anchor = { "LEFT", nil, "CENTER", 5, 10 }, width = 150, script = reset_noteOnClick },
            { name = "toggle_tomtom", label = waypointSettingLabel("TomTom", addon.data.waypoints.tomtom), anchor = { "RIGHT", nil, "CENTER", -5, -20 }, width = 150, script = toggle_tomtomOnClick },
            { name = "toggle_pins", label = waypointSettingLabel("Pins", addon.data.waypoints.pins), anchor = { "LEFT", nil, "CENTER", 5, -20 }, width = 150, script = toggle_pinsOnClick },
            { name = "import_routes", label = "Import Route Data", anchor = { "RIGHT", nil, "CENTER", -5, -50 }, width = 150, script = import_routesOnClick },
            { name = "export_routes", label = "Export Route Data", anchor = { "LEFT", nil, "CENTER", 5, -50 }, width = 150, script = export_routesOnClick },
            { name = "reset_routes", label = "Reset Route Data", anchor = { "RIGHT", nil, "CENTER", -5, -80 }, width = 150, script = reset_routesOnClick },
            { name = "clear_runs", label = "Clear Run Data", anchor = { "LEFT", nil, "CENTER", 5, -80 }, width = 150, script = clear_runsOnClick },
        }
    })
    return childFrame
end

function frame:InitializeConfirm()
    local childFrame = addon:BuildFrame(frame, {
        buttons = {
            { name = "confirm", label = "Confirm", anchor = { "RIGHT", nil, "CENTER", -5, -10 } },
            { name = "cancel", label = "Cancel", anchor = { "LEFT", nil, "CENTER", 5, -10 }, script = function() frame:ShowContainer("options") end },
        },
        up = function() frame:ShowContainer("options") end
    })
    
    childFrame.warning = addon:BuildLabel(childFrame, { anchor = { "CENTER", childFrame, "CENTER", 0, 15 } })
    childFrame:Hide()

    return childFrame
end

function frame:InitializeExport()
    local function closeOnClick()
        frame.export:Hide()
        frame.options:Show()
    end
    
    local childFrame = addon:BuildFrame(frame, {
        title = "Exporting Route Data",
        scroll = true,
        buttons = {
            { name = "close", label = "Close", anchor = { "BOTTOM", nil, "BOTTOM", 0, 0 }, width = 70, script = closeOnClick }
        },
        up = closeOnClick
    })
    
    childFrame.editbox = CreateFrame("EditBox", nil, childFrame.scroll)
    childFrame.editbox:SetMultiLine(true)
    childFrame.editbox:SetFontObject("ChatFontNormal")
    childFrame.editbox:SetWidth(childFrame.scroll:GetWidth())
    childFrame.editbox:SetAutoFocus(false)
    childFrame.scroll:SetScrollChild(childFrame.editbox)

    childFrame.editbox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, fontHeight = self:GetFont()
        local _, lineCount = text:gsub("\n", "\n")
        lineCount = lineCount + 1
        local requiredHeight = lineCount * (fontHeight + 2)
        local scrollHeight = childFrame.scroll:GetHeight()
        self:SetHeight(math.max(scrollHeight, requiredHeight))
    end)
    childFrame.editbox:SetHeight(childFrame.scroll:GetHeight())

    childFrame:Hide()

    return childFrame
end

function frame:InitializeImport()
    local function closeOnClick()
        frame.import:Hide()
        frame.options:Show()
    end

    local function mergeRoutes(importTable)
        for name, row in pairs(importTable) do
            addon.data.routes[name] = row
        end
        addon.ui:Refresh()
    end

    local function importOnClick()
        local importString = frame.import.editbox:GetText()
        local importTable = addon:ImportStringToTable(importString)
        local overwritten = {}
        if importTable then
            frame.import.scroll:Show()
            frame.import.editscroll:Hide()

            for name, _ in pairs(importTable) do
                if addon.data.routes[name] then
                    overwritten[#overwritten + 1] = name
                end
            end

            if #overwritten > 0 then
                frame.import.content.list:SetText(table.concat(overwritten, "\n"))

                local requiredHeight = frame.import.content.list:GetHeight()
                frame.import.content:SetSize(574, requiredHeight + 70)

                frame.import.scroll:Show()
                frame.import.editscroll:Hide()
                frame.import.import:Hide()
                frame.import.confirm:Show()

                frame.import.confirm:SetScript("OnClick", function()
                    mergeRoutes(importTable)
                    closeOnClick()
                end)
            else
                mergeRoutes(importTable)
                closeOnClick()
            end
        else
            print("Dystinct Earthen Skyriding was unable to import any routes from the supplied string.")
        end
    end

    local childFrame = addon:BuildFrame(frame, {
        title = "Importing Route Data",
        scroll = true,
        buttons = {
            { name = "cancel", label = "Cancel", anchor = { "BOTTOM", nil, "BOTTOM", -38, 0 }, width = 70, script = closeOnClick },
            { name = "import", label = "Import", anchor = { "BOTTOM", nil, "BOTTOM", 38, 0 }, width = 70, script = importOnClick },
            { name = "confirm", label = "Confirm", anchor = { "BOTTOM", nil, "BOTTOM", 38, 0 }, width = 70 }
        },
        up = closeOnClick
    })

    childFrame.content.warning = addon:BuildLabel(childFrame.content, {
        label = "The following routes will be overwritten if you continue.",
        anchor = { "TOP", childFrame.content, "TOP", 0, -20 }
    })
    childFrame.content.list = addon:BuildLabel(childFrame.content, {
        anchor = { "TOP", childFrame.content.warning, "BOTTOM", 0, -15 }
    })
    childFrame.scroll:Hide()

    childFrame.editscroll = CreateFrame("ScrollFrame", nil, childFrame, "UIPanelScrollFrameTemplate")
    childFrame.editscroll:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 8, -46.5)
    childFrame.editscroll:SetPoint("BOTTOMRIGHT", childFrame, "BOTTOMRIGHT", -30, 27)
    
    childFrame.editbox = CreateFrame("EditBox", "MyCustomEditBox", childFrame.editscroll)
    childFrame.editbox:SetMultiLine(true)
    childFrame.editbox:SetFontObject("ChatFontNormal")
    childFrame.editbox:SetWidth(childFrame.editscroll:GetWidth())
    childFrame.editbox:SetAutoFocus(false)
    childFrame.editbox:SetMaxLetters(0)
    childFrame.editscroll:SetScrollChild(childFrame.editbox)

    childFrame.editbox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, fontHeight = self:GetFont()
        local _, lineCount = text:gsub("\n", "\n")
        lineCount = lineCount + 1
        local requiredHeight = lineCount * (fontHeight + 2)
        local scrollHeight = childFrame.editscroll:GetHeight()
        self:SetHeight(math.max(scrollHeight, requiredHeight))
    end)
    childFrame.editbox:SetHeight(childFrame.editscroll:GetHeight())

    childFrame.content.list:SetSpacing(8)
    childFrame.content.list:SetTextColor(1, 1, 1)

    childFrame:Hide()

    return childFrame
end