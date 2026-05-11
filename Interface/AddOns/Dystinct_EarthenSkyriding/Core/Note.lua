local addonName, addon = ...

addon.ui.NoteFrame = {}
local frame = addon.ui.NoteFrame

function addon:InitializeNoteFrame()
    frame = CreateFrame("Frame", nil, UIParent, "InsetFrameTemplate3")
    frame:SetSize(200, 30)
    frame:SetMovable(true)
    frame:ClearAllPoints()
    frame:SetPoint(addon.data.note.anchor, UIParent, addon.data.note.relative, addon.data.note.x, addon.data.note.y)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        frame:StopMovingOrSizing()
        addon.data.note.anchor, _, addon.data.note.relative, addon.data.note.x, addon.data.note.y = self:GetPoint()
    end)
    local regions = {frame:GetRegions()}
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            region:SetAlpha(0.7)
        end
    end

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.label:SetPoint("CENTER", frame, "CENTER")
    frame.label:SetFont("Fonts\\FRIZQT__.TTF", 10)
    frame.label:SetSpacing(8)

    frame:Hide()

    return frame
end

function addon:RefreshNote()
    addon.ui.NoteFrame:SetShown(addon.active and addon.data.note.visible and addon.note_active)
end

function addon:UpdateNote(note)
    addon.ui.NoteFrame.label:SetText(note and note:gsub("\\n", "\n") or "")
    addon.ui.NoteFrame:SetWidth(addon.ui.NoteFrame.label:GetStringWidth() + 30)
    addon.ui.NoteFrame:SetHeight(addon.ui.NoteFrame.label:GetStringHeight() + 20)

    addon.ui.NoteFrame:SetShown(addon.data.note.visible and addon.note_active)
end

function addon:UpdateNoteAction(action)
    local noteFrame = addon.ui.NoteFrame
    if not action or not action.macro then
        if noteFrame.actionButton then
            noteFrame.actionButton:Hide()
        end
        return
    end

    if not noteFrame.actionButton then
        local btn = CreateFrame("Button", "DysES_NoteActionButton", noteFrame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
        btn:SetSize(120, 24)
        btn:SetPoint("BOTTOM", noteFrame, "TOP", 0, 4)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        noteFrame.actionButton = btn
    end

    local btn = noteFrame.actionButton
    btn:SetText(action.label or "Action")
    btn:SetWidth(btn:GetTextWidth() + 30)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", action.macro)
    btn:Show()
end