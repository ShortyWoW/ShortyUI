local addonName, addon = ...

local frame = addon.ui.LogFrame

local frameHeight = 34
local visibleRows = 9

function frame:Initialize()
    frame.selection = frame:InitializeSelection()
    frame.viewer = frame:InitializeViewer()
    frame.export = frame:InitializeExport()

    frame.selection:Show()
    frame.export:Hide()
    frame.viewer:Hide()
    frame:Refresh()
end

function frame:InitializeSelection()
    local childFrame = addon:BuildFrame(frame, {
        title = "Select a Run",
        scroll = true,
        buttons = { {
            name = "view_active",
            label = "View Active", 
            anchor = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 },
            disabled = true,
            script = function()
                frame:Refresh()
                frame:ShowActiveRun()
            end
        } }
    })

    return childFrame
end

function frame:InitializeViewer()
    local childFrame = addon:BuildFrame(frame, {
        scroll = true,
        up = function()
            frame:Refresh()
            frame.viewer:Hide()
            frame.export:Hide()
            frame.selection:Show()
        end
    })
    childFrame.editing = {}

    return childFrame
end

function frame:Refresh()
    frame:RefreshViewer()
    frame:RefreshSelection()
end

function frame:RefreshViewer()
    frame.selection.view_active:SetEnabled(addon.active ~= nil)
end

function frame:RefreshSelection()
    frame.selection.title:SetText("Select a Log")
    local count = 0
    for index, run in ipairs(addon.data.runs) do
        if run ~= nil then
            count = count + 1
            frame:UpdateSelectionRow(count, run)
            frame.selection.rows[count]:Show()
        end
    end

    if count < #frame.selection.rows then
        for index = count + 1, #frame.selection.rows do
            frame.selection.rows[index]:Hide()
        end
    end

    local contentHeight = count * (frameHeight + 2) - 2
    frame.selection.content:SetSize(280, contentHeight)
    frame.export:Hide()
end