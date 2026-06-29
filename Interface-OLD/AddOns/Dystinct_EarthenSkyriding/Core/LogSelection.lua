local addonName, addon = ...

local frame = addon.ui.LogFrame

local visibleRows = 9
local frameHeight = 34

local icons = {
    ["warrior"] = 626008,
    ["paladin"] = 626003,
    ["hunter"] = 626000,
    ["rogue"] = 626005,
    ["priest"] = 626004,
    ["shaman"] = 626006,
    ["warlock"] = 626007,
    ["mage"] = 626001,
    ["monk"] = 626002,
    ["druid"] = 625999,
    ["demon Hunter"] = 1260827,
    ["death knight"] = 135771,
    ["evoker"] = 4574311
}

local function getEnglishClassName(localizedClassName)
    -- Loop through the global LOCALIZED_CLASS_NAMES_MALE table
    for englishClass, localizedClass in pairs(LOCALIZED_CLASS_NAMES_MALE) do
        if localizedClass == localizedClassName then
            return string.lower(englishClass)
        end
    end
    
    -- Check female variants if not found in male table
    for englishClass, localizedClass in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
        if localizedClass == localizedClassName then
            return string.lower(englishClass)
        end
    end
    
    -- Return original if not found
    return  string.lower(localizedClassName)
end

local function exportOnClick(index)
    local exportData = { "name,mapID,zoneName,timestamp,experience,level,segment,x,y,status" }
    for i, discovery in ipairs(addon.data.runs[index].discoveries) do
        exportData[#exportData + 1] = table.concat({ discovery.name, discovery.mapID, discovery.zoneName, discovery.timestamp, discovery.experience, discovery.level, discovery.segment, discovery.x, discovery.y, discovery.status }, ",")
    end
    frame.export.editbox:SetText(table.concat(exportData, "\n"))
    frame.export.editbox:HighlightText(0)
    frame.selection:Hide()
    frame.export:Show()
end

function frame:UpdateSelectionRow(index, run)
    local rows = frame.selection.rows
    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.selection.content)
        row:SetSize(560, frameHeight)
        row:SetPoint("TOPLEFT", frame.selection.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * #rows)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        row.icon = row:CreateTexture(nil, "BORDER")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

        row.export = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.export.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        row.export:SetWidth(65)
        row.export:SetHeight(18)
        row.export:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.export:SetText("Export")
        row.export:SetScript("OnClick", function() exportOnClick(index) end)
        
        for index, label in ipairs({ "character", "date", "level", "duration", "route" }) do
            row[label] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row[label]:SetFont("Fonts\\FRIZQT__.TTF", 10)
        end
        
        row.character:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -5)
        row.character:SetTextColor(1.0, 1.0, 1.0)

        row.date:SetPoint("LEFT", row.character, "RIGHT", 8, 0)
        row.date:SetTextColor(0.6, 0.6, 0.6)

        row.level:SetPoint("LEFT", row.date, "RIGHT", 8, 0)
        row.level:SetTextColor(0.6, 0.6, 0.6)

        row.duration:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 42, 7)
        row.duration:SetFont("Fonts\\FRIZQT__.TTF", 9)

        row.route:SetPoint("LEFT", row.duration, "RIGHT", 8, 0)
        row.route:SetFont("Fonts\\FRIZQT__.TTF", 9)
        
        frame.selection.rows[#rows + 1] = row
    end
    frame.selection.rows[index]:ClearAllPoints()
    frame.selection.rows[index]:SetPoint("TOPLEFT", frame.selection.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * (#addon.data.runs - index))

    rows[index]:SetScript("OnMouseDown", function(self, button)
        frame:LoadRun(index)
    end)

    rows[index].icon:SetTexture(icons[getEnglishClassName(run.class)])
    rows[index].character:SetText(run.character)
    rows[index].date:SetText(run.date)
    rows[index].route:SetText(run.route or "None Selected")
    if #run.discoveries > 1 then
        rows[index].level:SetText(run.discoveries[1].level .. "-" .. run.discoveries[#run.discoveries].level)
        
        local diff = run.discoveries[#run.discoveries].timestamp - run.discoveries[1].timestamp
        local hours = math.floor(diff / 3600)
        local minutes = math.floor((diff % 3600) / 60)
        local seconds = math.floor(diff % 60)
        rows[index].duration:SetText(string.format("%d:%02d:%02d", hours, minutes, seconds))
    else
        rows[index].level:SetText("")
        rows[index].duration:SetText("0:00:00")
    end 
end