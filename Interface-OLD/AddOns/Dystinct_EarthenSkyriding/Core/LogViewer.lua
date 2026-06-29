local addonName, addon = ...

local frame = addon.ui.LogFrame

local visibleRows = 9
local frameHeight = 22

function frame:LoadRun(index)
    frame.viewer.run = index
    local run = addon.data.runs[index]
    frame.viewer.title:SetText(run.route)

    for index, event in ipairs(run.discoveries) do
        frame:UpdateRow(index, event)
    end

    if #run.discoveries < #frame.viewer.rows then
        for index=#run.discoveries + 1,#frame.viewer.rows do
            frame.viewer.rows[index]:Hide()
        end
    end

    local contentHeight = #run.discoveries * (frameHeight + 2) - 2
    frame.viewer.content:SetSize(280, contentHeight)
    frame.viewer.scroll:Show()
    frame.selection:Hide()
    frame.viewer:Show()
    frame:RefreshViewer()
end

function frame:ShowActiveRun()
    if #addon.data.runs ~= 0 then
        frame.viewer.run = #addon.data.runs
        local run = addon.data.runs[#addon.data.runs]
        frame.viewer.title:SetText(run.route)

        for index, event in ipairs(run.discoveries) do
            frame:UpdateRow(index, event)
        end

        if #run.discoveries < #frame.viewer.rows then
            for index=#run.discoveries + 1,#frame.viewer.rows do
                frame.viewer.rows[index]:Hide()
            end
        end

        local contentHeight = #run.discoveries * (frameHeight + 2) - 2
        frame.viewer.content:SetSize(280, contentHeight)
        frame.viewer.scroll:Show()
        frame.selection:Hide()
        frame.viewer:Show()
        frame:RefreshViewer()
    end
end

local function formatTimeDelta(currentTime, referenceTime, compact)
    local diff = currentTime - referenceTime
    
    local hours = math.floor(diff / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local seconds = math.floor(diff % 60)

    if compact then
        if minutes == 0 then
            return string.format("+%02d", seconds)
        else
            return string.format("+%02d:%02d", minutes, seconds)
        end
    else
        return string.format("+%d:%02d:%02d", hours, minutes, seconds)
    end
end

function frame:UpdateRow(index, event)
    local run = addon.data.runs[frame.viewer.run]
    local rows = frame.viewer.rows
    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.viewer.content)
        row:SetSize(560, frameHeight)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        local columnX = { 6, 250, 153, 84, 123, 470, 530 }
        for index, label in ipairs({ "timestamp", "name", "zoneName", "x", "y", "level", "delta"}) do
            row[label] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local center = index == 4 or index == 5 or index == 7
            row[label]:SetPoint(center and "CENTER" or "LEFT", row, "LEFT", columnX[index], 1)
            row[label]:SetFont("Fonts\\FRIZQT__.TTF", 10)
        end
        row.name:ClearAllPoints()
        row.delta:ClearAllPoints()
        row.level:ClearAllPoints()
        row.delta:SetPoint("RIGHT", row, "RIGHT", -16, 1)
        row.level:SetPoint("RIGHT", row.delta, "LEFT", -14, 0)

        row.x:SetTextColor(0.6, 0.6, 0.6)
        row.y:SetTextColor(0.6, 0.6, 0.6)
        row.name:SetTextColor(1, 1, 1)
        row.delta:SetTextColor(1, 1, 1)

        frame.viewer.rows[#rows + 1] = row
    end

    frame.viewer.rows[index]:SetPoint("TOPLEFT", frame.viewer.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * (#run.discoveries - index))

    for i, label in ipairs({ "name", "zoneName"}) do
        frame.viewer.rows[index][label]:SetText(addon:LocalizedString(event[label]))
    end
    for i, label in ipairs({ "x", "y" }) do
        frame.viewer.rows[index][label]:SetText(string.format("%.1f", tonumber(event[label])))
    end
    frame.viewer.rows[index].name:SetPoint("LEFT", frame.viewer.rows[index].zoneName, "RIGHT", 14, 0)

    local run = addon.data.runs[frame.viewer.run]

    frame.viewer.rows[index].timestamp:SetText(formatTimeDelta(run.discoveries[index].timestamp, run.discoveries[1].timestamp))
    
    if index == 1 or run.discoveries[index].level ~= run.discoveries[index - 1].level then
        frame.viewer.rows[index].level:SetText("Lv. " .. event.level)
    else
        frame.viewer.rows[index].level:SetText("")
    end

    frame.viewer.rows[index].delta:SetText(formatTimeDelta(run.discoveries[index].timestamp, run.discoveries[math.max(1, index - 1)].timestamp, "compact"))

    frame.viewer.rows[index]:Show()
end