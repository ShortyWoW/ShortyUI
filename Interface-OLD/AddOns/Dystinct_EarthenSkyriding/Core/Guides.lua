local addonName, addon = ...

local frame = addon.ui.GuidesFrame

local frameHeight = 38
local guides = addon.guides

function frame:Initialize()
    frame.selection = frame:InitializeSelection()
    frame.viewer = frame:InitializeViewer()
    frame:RefreshSelection()
end

function frame:Refresh()
    -- Guides are static content, no dynamic refresh needed
end

function frame:ShowContainer(container)
    for _, name in ipairs({ "selection", "viewer" }) do
        frame[name]:SetShown(container == name)
    end
end

function frame:InitializeSelection()
    local childFrame = addon:BuildFrame(frame, {
        title = "Guides",
        scroll = true,
    })

    return childFrame
end

function frame:RefreshSelection()
    for i, guide in ipairs(guides) do
        frame:UpdateSelectionRow(i, guide)
        frame.selection.rows[i]:Show()
    end

    local separatorGap = 12
    local separatorY = -1 * (#guides * (frameHeight + 2)) - (separatorGap / 2)

    if not frame.selection.separator then
        frame.selection.separator = frame.selection.content:CreateTexture(nil, "ARTWORK")
        frame.selection.separator:SetHeight(1)
        frame.selection.separator:SetPoint("LEFT", frame.selection.content, "LEFT", 10, 0)
        frame.selection.separator:SetPoint("RIGHT", frame.selection.content, "RIGHT", -10, 0)
        frame.selection.separator:SetColorTexture(1, 1, 1, 0.1)
    end
    frame.selection.separator:SetPoint("TOP", frame.selection.content, "TOP", 0, separatorY)

    if not frame.selection.changelogRow then
        local row = CreateFrame("Frame", nil, frame.selection.content)
        row:SetSize(560, frameHeight)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.number:SetFont("Fonts\\FRIZQT__.TTF", 16)
        row.number:SetPoint("CENTER", row, "LEFT", 21, 0)
        row.number:SetTextColor(1, 0.82, 0)
        row.number:SetText("?")

        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.title:SetFont("Fonts\\FRIZQT__.TTF", 11)
        row.title:SetPoint("LEFT", row, "LEFT", 42, 8)
        row.title:SetTextColor(1.0, 1.0, 1.0)
        row.title:SetText("Version History")

        row.description = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.description:SetFont("Fonts\\FRIZQT__.TTF", 9)
        row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.description:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.description:SetTextColor(0.6, 0.6, 0.6)
        row.description:SetJustifyH("LEFT")
        row.description:SetWordWrap(true)
        row.description:SetText("View changes across all versions.")

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        row:SetScript("OnMouseDown", function()
            frame:LoadChangelog()
        end)

        frame.selection.changelogRow = row
    end

    if not frame.selection.readmeRow then
        local row = CreateFrame("Frame", nil, frame.selection.content)
        row:SetSize(560, frameHeight)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.number:SetFont("Fonts\\FRIZQT__.TTF", 16)
        row.number:SetPoint("CENTER", row, "LEFT", 21, 0)
        row.number:SetTextColor(1, 0.82, 0)
        row.number:SetText("!")

        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.title:SetFont("Fonts\\FRIZQT__.TTF", 11)
        row.title:SetPoint("LEFT", row, "LEFT", 42, 8)
        row.title:SetTextColor(1.0, 1.0, 1.0)
        row.title:SetText("Addon Information")

        row.description = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.description:SetFont("Fonts\\FRIZQT__.TTF", 9)
        row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.description:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.description:SetTextColor(0.6, 0.6, 0.6)
        row.description:SetJustifyH("LEFT")
        row.description:SetWordWrap(true)
        row.description:SetText("Features, commands, and addon information.")

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        row:SetScript("OnMouseDown", function()
            frame:LoadReadme()
        end)

        frame.selection.readmeRow = row
    end

    local extraRowY = -1 * (#guides * (frameHeight + 2)) - separatorGap
    frame.selection.readmeRow:ClearAllPoints()
    frame.selection.readmeRow:SetPoint("TOPLEFT", frame.selection.content, "TOPLEFT", 0, extraRowY)
    frame.selection.readmeRow:Show()

    local changelogY = extraRowY - (frameHeight + 2)
    frame.selection.changelogRow:ClearAllPoints()
    frame.selection.changelogRow:SetPoint("TOPLEFT", frame.selection.content, "TOPLEFT", 0, changelogY)
    frame.selection.changelogRow:Show()

    local contentHeight = #guides * (frameHeight + 2) + separatorGap + (frameHeight + 2) * 2
    frame.selection.content:SetSize(560, contentHeight)
    frame.viewer:Hide()
    frame.selection:Show()
end

function frame:UpdateSelectionRow(index, guide)
    local rows = frame.selection.rows
    if #rows < index then
        local row = CreateFrame("Frame", nil, frame.selection.content)
        row:SetSize(560, frameHeight)
        row:SetPoint("TOPLEFT", frame.selection.content, "TOPLEFT", 0, -1 * (frameHeight + 2) * #rows)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

        row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.number:SetFont("Fonts\\FRIZQT__.TTF", 16)
        row.number:SetPoint("CENTER", row, "LEFT", 21, 0)
        row.number:SetTextColor(1, 0.82, 0)

        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.title:SetFont("Fonts\\FRIZQT__.TTF", 11)
        row.title:SetPoint("LEFT", row, "LEFT", 42, 8)
        row.title:SetTextColor(1.0, 1.0, 1.0)

        row.description = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.description:SetFont("Fonts\\FRIZQT__.TTF", 9)
        row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.description:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.description:SetTextColor(0.6, 0.6, 0.6)
        row.description:SetJustifyH("LEFT")
        row.description:SetWordWrap(true)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.05)

        frame.selection.rows[#rows + 1] = row
    end

    rows[index].number:SetText(string.format("%02d", index))
    rows[index].title:SetText(guide.title)
    rows[index].description:SetText(guide.description)

    rows[index]:SetScript("OnMouseDown", function()
        frame:LoadGuide(index)
    end)
end

function frame:InitializeViewer()
    local childFrame = addon:BuildFrame(frame, {
        title = "",
        scroll = true,
        up = function() frame:ShowContainer("selection") end
    })

    childFrame.elements = {}
    childFrame:Hide()

    return childFrame
end

function frame:LoadGuide(index, guideOverride)
    local guide = guideOverride or guides[index]
    if not guide then return end

    frame.viewer.title:SetText(guide.title)

    -- Hide all existing elements
    for _, element in ipairs(frame.viewer.elements) do
        element:Hide()
    end

    local yOffset = -5
    local contentWidth = frame.viewer.scroll:GetWidth() - 20
    local elementIndex = 0

    for _, block in ipairs(guide.content) do
        elementIndex = elementIndex + 1

        if block.type == "header" then
            local header
            if elementIndex <= #frame.viewer.elements and frame.viewer.elements[elementIndex].elementType == "header" then
                header = frame.viewer.elements[elementIndex]
            else
                header = frame.viewer.content:CreateFontString(nil, "OVERLAY")
                header:SetFontObject("GameFontHighlight")
                header:SetFont("Fonts\\FRIZQT__.TTF", 12)
                header:SetJustifyH("LEFT")
                header:SetTextColor(1, 1, 1)
                header.elementType = "header"
                if elementIndex > #frame.viewer.elements then
                    frame.viewer.elements[elementIndex] = header
                else
                    table.insert(frame.viewer.elements, elementIndex, header)
                end
            end

            yOffset = yOffset - 10
            -- if elementIndex > 1 then
            -- end

            header:ClearAllPoints()
            header:SetWidth(contentWidth)
            header:SetPoint("TOPLEFT", frame.viewer.content, "TOPLEFT", 10, yOffset)
            header:SetText(block.value)
            header:Show()

            yOffset = yOffset - header:GetStringHeight() - 8

        elseif block.type == "text" then
            local label
            if elementIndex <= #frame.viewer.elements and frame.viewer.elements[elementIndex].elementType == "text" then
                label = frame.viewer.elements[elementIndex]
            else
                label = frame.viewer.content:CreateFontString(nil, "OVERLAY")
                label:SetFontObject("GameFontNormal")
                label:SetFont("Fonts\\FRIZQT__.TTF", 10)
                label:SetTextColor(1, 0.82, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(true)
                label:SetSpacing(4)
                label.elementType = "text"
                if elementIndex > #frame.viewer.elements then
                    frame.viewer.elements[elementIndex] = label
                else
                    table.insert(frame.viewer.elements, elementIndex, label)
                end
            end

            label:ClearAllPoints()
            label:SetWidth(contentWidth)
            label:SetPoint("TOPLEFT", frame.viewer.content, "TOPLEFT", 10, yOffset)
            label:SetText(block.value)
            label:Show()

            yOffset = yOffset - label:GetStringHeight() - 12

        elseif block.type == "image" then
            local texture
            if elementIndex <= #frame.viewer.elements and frame.viewer.elements[elementIndex].elementType == "image" then
                texture = frame.viewer.elements[elementIndex]
            else
                texture = frame.viewer.content:CreateTexture(nil, "ARTWORK")
                texture.elementType = "image"
                if elementIndex > #frame.viewer.elements then
                    frame.viewer.elements[elementIndex] = texture
                else
                    table.insert(frame.viewer.elements, elementIndex, texture)
                end
            end

            local imgWidth = math.min(block.width or 400, contentWidth)
            local imgHeight = block.height or 200

            texture:ClearAllPoints()
            texture:SetSize(imgWidth, imgHeight)
            texture:SetPoint("TOP", frame.viewer.content, "TOP", 5, yOffset)
            texture:SetTexture(block.texture)
            texture:Show()

            yOffset = yOffset - imgHeight - 12
        end
    end

    local totalHeight = math.abs(yOffset) + 10
    frame.viewer.content:SetSize(contentWidth, totalHeight)

    frame:ShowContainer("viewer")
end

function frame:LoadChangelog()
    local versions = {}
    for version in pairs(addon.changelogs) do
        versions[#versions + 1] = version
    end
    table.sort(versions, function(a, b)
        local a1, a2, a3 = a:match("(%d+)%.(%d+)%.(%d+)")
        local b1, b2, b3 = b:match("(%d+)%.(%d+)%.(%d+)")
        a1, a2, a3 = tonumber(a1), tonumber(a2), tonumber(a3)
        b1, b2, b3 = tonumber(b1), tonumber(b2), tonumber(b3)
        if a1 ~= b1 then return a1 > b1 end
        if a2 ~= b2 then return a2 > b2 end
        return a3 > b3
    end)

    local content = {}
    for _, version in ipairs(versions) do
        content[#content + 1] = { type = "header", value = "Version " .. version }
        for _, entry in ipairs(addon.changelogs[version]) do
            content[#content + 1] = { type = "text", value = entry }
        end
    end

    frame:LoadGuide(nil, { title = "Version History", content = content })
end

function frame:LoadReadme()
    frame:LoadGuide(nil, { title = "Addon Information", content = addon.readme })
end
