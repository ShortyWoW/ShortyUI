local addonName, addon = ...

local frame = addon.ui.RoutesFrame

function frame:Initialize()
    frame.selection = frame:InitializeSelection()
    frame.viewer = frame:InitializeViewer()
    frame.waypoint = frame:InitializeWaypoint()
    frame.segment = frame:InitializeSegment()
    frame.conditional = frame:InitializeConditional()
    frame.delete = frame:InitializeDelete()
    frame.export = frame:InitializeExport()

    frame:Refresh()
end

function frame:Refresh()
    if #frame.viewer.editing ~= 0 then
        frame:RefreshViewer()
    else
        frame:RefreshSelection()
    end
end

function frame:ShowSegmentEditor(class)
    frame.selection:Hide()
    frame.viewer:Hide()
    frame.segment:Show()
end

function frame:ShowWaypointEditor()
    frame.waypoint.save:Disable()
    frame.viewer:Hide()
    frame.waypoint:Show()
end