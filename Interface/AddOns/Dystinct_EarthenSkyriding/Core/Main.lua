local addonName, addon = ...

addon.ui = DysES_Frame

function addon.ui:Initialize()
    addon.dropdown = addon.CreateDropDown()

    addon.ui:SetSize(600, 314)
    addon.ui:SetTitle("Dystinct Earthen Skyriding")
    addon.ui:SetTitleOffsets(0,0)
    addon.ui:SetMovable(true)
    addon.ui:EnableMouse(true)
    addon.ui:RegisterForDrag("LeftButton")
    addon.ui:SetScript("OnDragStart", self.StartMoving)
    addon.ui:SetScript("OnDragStop", self.StopMovingOrSizing)

    for _, value in ipairs({"Settings", "Segment", "Routes", "Log", "Guides" }) do
        addon.ui[value .. "Frame"]:Initialize()
        addon.ui[value .. "Tab"].Highlight:SetAlpha(0)
        addon.ui[value .. "Tab"]:SetScript("OnMouseDown", function(self, button)
            addon.ui:SelectTab(value)
        end)
    end

    addon.ui.NoteFrame = addon:InitializeNoteFrame()
    addon.ui.AnnouncementFrame = addon:InitializeAnnouncement()

    addon.ui:SelectTab("Segment")

    addon.ui:HookScript("OnShow", function()
        if addon.pendingChangelog then
            addon.ui:SelectTab("Guides")
            addon.ui.GuidesFrame:LoadChangelog()
            addon.pendingChangelog = nil
        end
    end)
end

function addon.ui:SelectTab(value)
    addon.ui[value .. "Tab"].Highlight:SetAlpha(0.6)
    addon.ui[value .. "Tab"].Icon:SetDesaturation(0)
    addon.ui[value .. "Frame"]:Show()
    for _, disable in ipairs({"Settings", "Segment", "Routes", "Log", "Guides" }) do
        if value ~= disable then
            addon.ui[disable .. "Tab"].Highlight:SetAlpha(0)
            addon.ui[disable .. "Tab"].Icon:SetDesaturation(1)
            addon.ui[disable .. "Frame"]:Hide()
        end
    end
end

function addon.ui:Refresh()
    addon.menu = addon.processRoutes(addon.data.routes)
    addon.ui.SegmentFrame:Refresh()
    addon.ui.RoutesFrame:Refresh()
    addon.ui.LogFrame:Refresh()
    addon.ui.SettingsFrame:Refresh()
    addon.ui.GuidesFrame:Refresh()
    addon:RefreshNote()
end