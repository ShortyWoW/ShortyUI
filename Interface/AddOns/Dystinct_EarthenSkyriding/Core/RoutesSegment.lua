local addonName, addon = ...

local frame = addon.ui.RoutesFrame

function frame:InitializeSegment()
    local discardOnClick = function()
        frame.segment:Hide()
        if #frame.viewer.editing == 0 then
            frame.selection:Show()
        else
            frame.viewer:Show()
        end
    end

    local function fieldOnChange(self, user)
        if user then
            if addon.data.routes[frame.segment.name.input:GetText()] ~= nil and frame.segment.name.input:GetText() ~= frame.viewer.editing[#frame.viewer.editing] then
                frame.segment.unique:Show()
                frame.segment.save:Disable()
            else
                frame.segment.unique:Hide()
                if frame.segment.name.input:GetText() ~= "" and frame.segment.display.input:GetText() ~= "" then
                    frame.segment.save:Enable()
                else
                    frame.segment.save:Disable()
                end
            end
        end
    end

    local childFrame = addon:BuildFrame(frame, {
        title = "Segment Editor",
        buttons = {
            { name = "save", label = "Save", anchor = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 }, width = 70, ["disable"] = true, script = function() frame:SaveSegment() end },
            { name = "discard", label = "Cancel", anchor = { "RIGHT", "save", "LEFT", -3, 0 }, width = 70 },
        },
        fields = {
            { name = "note", label = "Note", anchor = { "CENTER", nil, "CENTER", 0, -30 }, width = 470, script = fieldOnChange },
            { name = "name", label = "Unique Name", anchor = { "BOTTOMLEFT", "note", "TOPLEFT", 0, 25 }, width = 185, script = fieldOnChange },
            { name = "display", label = "Display Name", anchor = { "LEFT", "name", "RIGHT", 15, 0 }, width = 185, script = fieldOnChange },
            { name = "map", label = "Map ID", anchor = { "LEFT", "display", "RIGHT", 15, 0 }, width = 70, script = fieldOnChange },
        },
        up =  function()
            frame.segment:Hide()
            if #frame.viewer.editing == 0 then
                frame.selection:Show()
            else
                frame.viewer:Show()
            end
        end
    })

    childFrame.unique = addon:BuildLabel(childFrame, { label = "Conflict", color = { 1, 0, 0 }, anchor = { "BOTTOMRIGHT", childFrame.name.input, "TOPRIGHT", 0, 6 } })
    childFrame.unique:Hide()

    childFrame:Hide()

    return childFrame
end

function frame:NewSegment(class)
    frame.segment.class = class
    frame.segment.name.input:SetText("")
    frame.segment.display.input:SetText("")
    frame.segment.map.input:SetText("")
    frame.segment.note.input:SetText("")
    frame:ShowSegmentEditor()
end

function frame:LoadSegment(data)
    frame.segment.name.input:SetText(data.name)
    frame.segment.display.input:SetText(data.route.display)
    frame.segment.map.input:SetText(tonumber(data.route.map) or 10)
    frame.segment.note.input:SetText(data.route.note or "")
    frame:ShowSegmentEditor()
end

function frame:SaveSegment()
    frame.segment:Hide()

    local name = frame.segment.name.input:GetText()
    local display = frame.segment.display.input:GetText()
    local map = frame.segment.map.input:GetText()
    local note = frame.segment.note.input:GetText()

    if #frame.viewer.editing == 0 then
        addon.data.routes[name] = {
            ['display'] = display,
            ['map'] = map,
            ['note'] = note,
            ['route'] = {},
            ['class'] = frame.segment.class
        }

        frame.selection:Show()
    else
        local oldName = frame.viewer.editing[#frame.viewer.editing]
        local route = addon.data.routes[oldName]
        route.display = display
        route.map = map
        route.note = note
        
        local newRoute = {
            display = display,
            map = map,
            note = note,
            route = route.route,
            class = route.class
        }

        addon.data.routes[oldName] = nil
        addon.data.routes[name] = newRoute

        frame.viewer.editing[#frame.viewer.editing] = name

        local function renameInEntries(entries)
            for i, entry in ipairs(entries) do
                if type(entry) == "string" then
                    if entry == oldName then
                        entries[i] = name
                    end
                elseif type(entry) == "table" then
                    if entry.switch then
                        for _, case in ipairs(entry.switch) do
                            if case.route == oldName then case.route = name end
                            if case.routes then renameInEntries(case.routes) end
                        end
                    elseif entry.condition then
                        if type(entry.pass) == "string" and entry.pass == oldName then entry.pass = name end
                        if type(entry.fail) == "string" and entry.fail == oldName then entry.fail = name end
                        if type(entry.pass) == "table" then renameInEntries(entry.pass) end
                        if type(entry.fail) == "table" then renameInEntries(entry.fail) end
                    end
                end
            end
        end
        for _, listRoute in pairs(addon.data.routes) do
            renameInEntries(listRoute.route)
        end

        frame.viewer:Show()
    end

    addon.menu = addon.processRoutes(addon.data.routes)
    addon.ui.SegmentFrame:Refresh()
    frame:Refresh()
end