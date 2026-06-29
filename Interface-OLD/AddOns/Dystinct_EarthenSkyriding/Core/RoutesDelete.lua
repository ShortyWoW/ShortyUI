local addonName, addon = ...

local frame = addon.ui.RoutesFrame

function frame:InitializeDelete()
    local childFrame = addon:BuildFrame(frame, {
        buttons = {
            { name = "confirm", ["label"] = "Confirm", ["anchor"] = { "RIGHT", nil, "CENTER", -5, -10 } },
            { name = "cancel", ["label"] = "Cancel", ["anchor"] = { "LEFT", nil, "CENTER", 5, -10 } },
        }
    })

    childFrame.cancel:SetScript("OnClick", function()
        childFrame:Hide()
        frame.viewer:Show()
    end)

    childFrame.confirm:SetScript("OnClick", function()
        childFrame:Hide()
        local name = frame.viewer.editing[#frame.viewer.editing]
        addon.data.routes[name] = nil
        for _, route in pairs(addon.data.routes) do
            for index = #route.route, 1, -1 do
                local entry = route.route[index]
                if type(entry) == "string" and entry == name then
                    table.remove(route.route, index)
                elseif type(entry) == "table" and entry.switch then
                    for j = #entry.switch, 1, -1 do
                        local case = entry.switch[j]
                        if case.route == name then
                            table.remove(entry.switch, j)
                        elseif case.routes then
                            for k = #case.routes, 1, -1 do
                                local r = case.routes[k]
                                if type(r) == "string" and r == name then
                                    table.remove(case.routes, k)
                                elseif type(r) == "table" and r.condition then
                                    if r.pass == name then r.pass = nil end
                                    if r.fail == name then r.fail = nil end
                                    if not r.pass and not r.fail then
                                        table.remove(case.routes, k)
                                    end
                                end
                            end
                            if #case.routes == 0 then
                                table.remove(entry.switch, j)
                            end
                        end
                    end
                    if #entry.switch == 0 then
                        table.remove(route.route, index)
                    end
                elseif type(entry) == "table" and entry.condition then
                    if entry.pass == name then entry.pass = nil end
                    if entry.fail == name then entry.fail = nil end
                    if not entry.pass and not entry.fail then
                        table.remove(route.route, index)
                    end
                end
            end
        end
        frame.viewer.editing = {}
        addon.menu = addon.processRoutes(addon.data.routes)
        frame:RefreshSelection()
        addon.ui.SegmentFrame:Refresh()
        frame.selection:Show()
    end)

    childFrame.warning = childFrame:CreateFontString(nil, "OVERLAY")
    childFrame.warning:SetPoint("CENTER", childFrame, "CENTER", 0, 15)
    childFrame.warning:SetFontObject("GameFontNormal")
    childFrame.warning:SetText("Are you sure you want to delete this?")
    
    childFrame.up = CreateFrame("Button", nil, childFrame)
    childFrame.up:SetSize(30, 30)
    childFrame.up:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, -6)
    childFrame.up:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    childFrame.up:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    childFrame.up:SetDisabledTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Disabled")
    childFrame.up:SetScript("OnClick", function()
        childFrame:Hide()
        if #frame.viewer.editing == 0 then
            frame.selection:Show()
        else
            frame.viewer:Show()
        end
    end)

    childFrame:Hide()

    return childFrame
end