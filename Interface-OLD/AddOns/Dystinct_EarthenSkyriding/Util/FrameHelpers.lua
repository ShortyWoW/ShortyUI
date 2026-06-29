local addonName, addon = ...

function addon:BuildFrame(frame, options)
    local childFrame = CreateFrame("Frame", nil, frame)
    childFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    childFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    childFrame.title = childFrame:CreateFontString(nil, "OVERLAY")
    childFrame.title:SetFontObject("GameFontHighlight")
    childFrame.title:SetPoint("TOP", frame, "TOP", 0, -15)

    if options then
        if options.title then
            childFrame.title:SetText(options.title or "")
        end

        if options.scroll then
            childFrame.scroll = CreateFrame("ScrollFrame", nil, childFrame, "UIPanelScrollFrameTemplate")
            childFrame.scroll:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 8, -46.5)
            childFrame.scroll:SetPoint("BOTTOMRIGHT", childFrame, "BOTTOMRIGHT", -30, 27)

            childFrame.content = CreateFrame("Frame", nil, childFrame.scroll)
            childFrame.scroll:SetScrollChild(childFrame.content)
            
            childFrame.rows = {}
        end

        if options.up then
            addon:AddUpButton(childFrame, options.up)
        end

        if options.buttons then
            addon:AddButtons(childFrame, options.buttons)
        end

        if options.fields then
            addon:AddFields(childFrame, options.fields)
        end
    end

    return childFrame
end

function addon:AddButtons(frame, buttons, default_width, default_height)
    local default_width = 100
    local default_height = 20
    for _, button in ipairs(buttons) do
        
        local parent
        if button.anchor[2] then
            parent = frame[button.anchor[2]]
        else
            parent = frame
        end
        local control = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        control.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        control:SetPoint(button.anchor[1], parent, button.anchor[3], button.anchor[4], button.anchor[5])
        control:SetWidth(button.width or default_width)
        control:SetHeight(button.height or default_height)
        control:SetText(button.label)
        control:SetEnabled(not button.disable)
        control:SetScript("OnClick", button.script)
        frame[button.name] = control
    end
end

function addon:AddUpButton(frame, buttonFunction)
    frame.up = CreateFrame("Button", nil, frame)
    frame.up:SetSize(30, 30)
    frame.up:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -6)
    frame.up:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    frame.up:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    frame.up:SetDisabledTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Disabled")
    frame.up:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    frame.up:SetScript("OnClick", buttonFunction)
end

function addon:BuildLabel(frame, options)
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetPoint(options.anchor[1], options.anchor[2], options.anchor[3], options.anchor[4], options.anchor[5])
    label:SetFontObject("GameFontNormal")
    label:SetFont("Fonts\\FRIZQT__.TTF", options.size or 10)
    label:SetText(options.label or "")
    if options.color then
        label:SetTextColor(options.color[1], options.color[2], options.color[3])
    end
    return label
end

function addon:BuildField(frame, options)
    local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    input:SetPoint(options.anchor[1], options.anchor[2] and frame[options.anchor[2]].input or frame, options.anchor[3], options.anchor[4], options.anchor[5])
    input:SetSize(options.width, 20)
    input:SetAutoFocus(false)
    local label = addon:BuildLabel(frame, { label = options.label, anchor = { "BOTTOMLEFT", input, "TOPLEFT", 0, 4 } })

    return label, input
end

function addon:AddFields(frame, field_options)
    for _, options in ipairs(field_options) do
        frame[options.name] = {}
        frame[options.name].label, frame[options.name].input = addon:BuildField(frame, options)
        frame[options.name].input:SetScript("OnTextChanged", options.script)
    end
end