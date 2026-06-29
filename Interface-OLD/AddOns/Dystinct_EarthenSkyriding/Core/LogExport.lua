local addonName, addon = ...

local frame = addon.ui.LogFrame

function frame:InitializeExport()
    local function closeOnClick()
        frame.export:Hide()
        frame.selection:Show()
    end
    
    local childFrame = addon:BuildFrame(frame, {
        title = "Exporting Log",
        scroll = true,
        buttons = {
            { name = "close", label = "Close", anchor = { "BOTTOM", nil, "BOTTOM", 0, 0 }, width = 70, script = closeOnClick }
        },
        up = closeOnClick
    })
    
    childFrame.editbox = CreateFrame("EditBox", nil, childFrame.scroll)
    childFrame.editbox:SetMultiLine(true)
    childFrame.editbox:SetFontObject("ChatFontNormal")
    childFrame.editbox:SetWidth(childFrame.scroll:GetWidth())
    childFrame.editbox:SetAutoFocus(false)
    childFrame.scroll:SetScrollChild(childFrame.editbox)

    childFrame.editbox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, fontHeight = self:GetFont()
        local _, lineCount = text:gsub("\n", "\n")
        lineCount = lineCount + 1
        local requiredHeight = lineCount * (fontHeight + 2)
        local scrollHeight = childFrame.scroll:GetHeight()
        self:SetHeight(math.max(scrollHeight, requiredHeight))
    end)
    childFrame.editbox:SetHeight(childFrame.scroll:GetHeight())

    childFrame:Hide()

    return childFrame
end