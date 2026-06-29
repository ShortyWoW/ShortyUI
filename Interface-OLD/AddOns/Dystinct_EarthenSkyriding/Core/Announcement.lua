local addonName, addon = ...

function addon:InitializeAnnouncement()
    local frame = CreateFrame("Frame", "AnnouncementFrame", UIParent)
    frame:SetSize(500, 150)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:ClearAllPoints()
    frame:SetPoint(addon.data.announcement.anchor, UIParent, addon.data.announcement.relative, addon.data.announcement.x, addon.data.announcement.y)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        frame:StopMovingOrSizing()
        addon.data.announcement.anchor, _, addon.data.announcement.relative, addon.data.announcement.x, addon.data.announcement.y = self:GetPoint()
    end)

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.label:SetPoint("CENTER")
    frame.label:SetFont("Fonts\\FRIZQT__.TTF", 28)
    
    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.heading:SetPoint("CENTER", frame.label, "CENTER", 0, 36)

    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("CENTER", frame, "CENTER", 0, 19)
    texture:SetSize(500, 150)
    texture:SetTexCoord(0, .8, 0.45, 0.9)
    texture:SetTexture("Interface\\LevelUp\\MinorTalents")
    texture:SetAlpha(0.3)

    frame:Hide()

    return frame
end

function addon:Announce(heading, label)
    local frame = addon.ui.AnnouncementFrame
    frame.label:SetText(addon:LocalizedString(label))
    frame.heading:SetText(heading)

    if addon.announceTimer then
        addon.announceTimer:Cancel()
        addon.announceTimer = nil
    end
    if addon.announceFadeGroup then
        addon.announceFadeGroup:Stop()
    end

    frame:SetAlpha(1)
    frame:Show()
    local fadeGroup = frame:CreateAnimationGroup()
    addon.announceFadeGroup = fadeGroup
    local fade = fadeGroup:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.2)
    fadeGroup:Play()

    addon.announceTimer = C_Timer.NewTimer(3, function()
        local fadeOutGroup = frame:CreateAnimationGroup()
        addon.announceFadeGroup = fadeOutGroup
        local fadeOut = fadeOutGroup:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(1)

        fadeOutGroup:SetScript("OnFinished", function()
            addon.announceFadeGroup = nil
            addon.announceTimer = nil
            frame:Hide()
        end)
        fadeOutGroup:Play()
    end)
end

function addon:RunCompleted(label)
    addon:Announce("Route Complete", label)
end