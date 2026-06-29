-- PullPrep Addon Exporter
-- Exports action bars and keybindings as a copyable Base64 string.

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- Helper: Base64 encoder
local function base64_encode(data)
    return ((data:gsub('.', function(x) 
        local r, b_val = '', x:byte()
        for i = 8, 1, -1 do 
            r = r .. (b_val % 2^i - b_val % 2^(i-1) > 0 and '1' or '0') 
        end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do 
            c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) 
        end
        return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- Helper: JSON escape string
local function escape(str)
    if not str then return "" end
    return str:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r")
end

-- Scan Action Bars and format as JSON
local function ExportActionBars()
    local classDisplayName, classFile = UnitClass("player")
    local specIndex = GetSpecialization()
    local specName = "Unknown"
    if specIndex then
        local _, name = GetSpecializationInfo(specIndex)
        specName = name or "Unknown"
    end

    local json = '{"class":"' .. (classFile or "UNKNOWN") .. '","spec":"' .. (specName or "UNKNOWN") .. '","actionBars":['
    
    -- Action Bar mappings inside the WoW client
    local barMappings = {
        { name = "ActionBar1", slots = {1, 12}, cmd = "ACTIONBUTTON" },
        { name = "ActionBar2", slots = {61, 72}, cmd = "MULTIBARBOTTOMLEFTBUTTON" },
        { name = "ActionBar3", slots = {49, 60}, cmd = "MULTIBARBOTTOMRIGHTBUTTON" },
        { name = "ActionBar4", slots = {37, 48}, cmd = "MULTIBARRIGHTBUTTON" },
        { name = "ActionBar5", slots = {25, 36}, cmd = "MULTIBARLEFTBUTTON" },
        { name = "ActionBar6", slots = {13, 24}, cmd = "MULTIBAR5BUTTON" },
        { name = "ActionBar7", slots = {73, 84}, cmd = "MULTIBAR6BUTTON" },
        { name = "ActionBar8", slots = {85, 96}, cmd = "MULTIBAR7BUTTON" },
    }

    local firstBar = true
    for _, bar in ipairs(barMappings) do
        local buttonsJson = ""
        local firstButton = true
        local barHasContent = false

        for slot = bar.slots[1], bar.slots[2] do
            local btnIndex = slot - bar.slots[1] + 1
            local cmdName = bar.cmd .. btnIndex
            local key = GetBindingKey(cmdName)

            local actionType, id = GetActionInfo(slot)
            if actionType then
                local name, icon
                if actionType == "spell" then
                    if C_Spell and C_Spell.GetSpellInfo then
                        local info = C_Spell.GetSpellInfo(id)
                        if info then
                            name = info.name
                            icon = info.iconID
                        end
                    else
                        name, _, icon = GetSpellInfo(id)
                    end
                elseif actionType == "macro" then
                    name = GetMacroSpell(id)
                    if not name then
                        name = GetMacroInfo(id)
                    end
                    local _, mIcon = GetMacroInfo(id)
                    icon = mIcon
                elseif actionType == "item" then
                    name = GetItemInfo(id)
                    local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(id)
                    icon = itemIcon
                end

                if name then
                    barHasContent = true
                    if not firstButton then
                        buttonsJson = buttonsJson .. ","
                    end
                    firstButton = false
                    
                    local keyStr = key or ""
                    buttonsJson = buttonsJson .. '{"slot":' .. btnIndex .. ',"type":"' .. actionType .. '","id":' .. id .. ',"name":"' .. escape(name) .. '","key":"' .. escape(keyStr) .. '","icon":' .. (icon or 0) .. '}'
                end
            elseif key then
                -- Include button if it has a keybind even if empty (so we render empty slot with keybind in UI)
                barHasContent = true
                if not firstButton then
                    buttonsJson = buttonsJson .. ","
                end
                firstButton = false
                buttonsJson = buttonsJson .. '{"slot":' .. btnIndex .. ',"type":"empty","id":0,"name":"","key":"' .. escape(key) .. '","icon":0}'
            end
        end

        if barHasContent then
            if not firstBar then
                json = json .. ","
            end
            firstBar = false
            json = json .. '{"barName":"' .. bar.name .. '","buttons":[' .. buttonsJson .. ']}'
        end
    end

    json = json .. ']}'
    return json
end

-- Setup Exporter GUI Frame (Modern flat design)
local frame = CreateFrame("Frame", "PullPrepExporterFrame", UIParent, "BackdropTemplate")
frame:SetSize(450, 320)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:Hide()
tinsert(UISpecialFrames, "PullPrepExporterFrame") -- Close with Escape key

-- Make the frame draggable
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

-- Flat dark background with violet border
frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
frame:SetBackdropColor(0.05, 0.05, 0.07, 0.96) -- #0d0d11 deep dark carbon
frame:SetBackdropBorderColor(0.55, 0.36, 0.96, 0.8) -- #8b5cf6 PullPrep violet

-- Header Title
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
title:SetText("|cFF8B5CF6P|r PULLPREP.COM EXPORTER")

-- Header Subtitle
local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetText("Copy the configuration string below to import into PullPrep.")
subtitle:SetTextColor(0.6, 0.6, 0.6)

-- Status Indicator Message
local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 54)
statusText:SetText("")

-- Custom Header Close Button (X)
local xButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
xButton:SetSize(20, 20)
xButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
xButton.text = xButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
xButton.text:SetPoint("CENTER")
xButton.text:SetText("X")
xButton.text:SetTextColor(0.6, 0.6, 0.6)
xButton:SetScript("OnEnter", function(self) self.text:SetTextColor(0.9, 0.2, 0.2) end)
xButton:SetScript("OnLeave", function(self) self.text:SetTextColor(0.6, 0.6, 0.6) end)
xButton:SetScript("OnClick", function() frame:Hide() end)

-- Inner ScrollFrame Inset Container
local container = CreateFrame("Frame", nil, frame, "BackdropTemplate")
container:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -62)
container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 74)
container:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1
})
container:SetBackdropColor(0.02, 0.02, 0.03, 0.9) -- #050507 ultra dark
container:SetBackdropBorderColor(0.12, 0.12, 0.15, 1.0) -- #1e1e24 dark gray border

-- Scroll Frame for EditBox
local scrollFrame = CreateFrame("ScrollFrame", "PullPrepScrollFrame", container, "InputScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)

local editBox = scrollFrame.EditBox
editBox:SetWidth(scrollFrame:GetWidth() - 20)
editBox:SetMaxLetters(0) -- Unlimited
if scrollFrame.CharCount then
    scrollFrame.CharCount:Hide()
end
editBox:SetFontObject("GameFontHighlightSmall")
editBox:SetText("")

-- Hide legacy InputScrollFrameTemplate textures
if _G[scrollFrame:GetName().."Middle"] then _G[scrollFrame:GetName().."Middle"]:Hide() end
if _G[scrollFrame:GetName().."Top"] then _G[scrollFrame:GetName().."Top"]:Hide() end
if _G[scrollFrame:GetName().."Bottom"] then _G[scrollFrame:GetName().."Bottom"]:Hide() end

-- Select all text when clicking inside the edit box
editBox:SetScript("OnMouseUp", function(self)
    self:HighlightText()
end)

-- Premium Custom Button Factory
local function CreatePremiumButton(parent, text, width, height, isPrimary)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 1
    })
    
    local normalColor, hoverColor, borderNorm, borderHover
    if isPrimary then
        -- Violet primary styling
        normalColor = {0.45, 0.25, 0.85, 1.0} -- #7c3aed
        hoverColor = {0.55, 0.35, 0.95, 1.0}  -- #8b5cf6
        borderNorm = {0.55, 0.35, 0.95, 1.0}
        borderHover = {0.65, 0.45, 1.0, 1.0}
    else
        -- Slate secondary styling
        normalColor = {0.15, 0.15, 0.18, 1.0} -- #27272a
        hoverColor = {0.20, 0.20, 0.25, 1.0}  -- #3f3f46
        borderNorm = {0.25, 0.25, 0.28, 1.0}
        borderHover = {0.35, 0.35, 0.40, 1.0}
    end
    
    btn:SetBackdropColor(unpack(normalColor))
    btn:SetBackdropBorderColor(unpack(borderNorm))
    
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(hoverColor))
        self:SetBackdropBorderColor(unpack(borderHover))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(normalColor))
        self:SetBackdropBorderColor(unpack(borderNorm))
    end)
    
    return btn
end

-- Copy Button
local copyButton = CreatePremiumButton(frame, "Highlight Text", 160, 30, true)
copyButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
copyButton:SetScript("OnClick", function()
    editBox:SetFocus()
    editBox:HighlightText()
    statusText:SetText("|cFFFFB000Text highlighted! Press Ctrl+C to copy.|r")
end)

-- Close Button
local closeButton = CreatePremiumButton(frame, "Close", 100, 30, false)
closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
closeButton:SetScript("OnClick", function()
    frame:Hide()
end)

-- Register Slash Commands
SLASH_PULLPREP1 = "/pullprep"
SLASH_PULLPREP2 = "/pp"
SlashCmdList["PULLPREP"] = function()
    local data = ExportActionBars()
    local b64 = base64_encode(data)
    editBox:SetText(b64)
    statusText:SetText("|cFFFFB000Press Ctrl+C to copy configuration!|r")
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end

print("|cFF8B5CF6[PullPrep]|r Addon loaded. Type |cFF00FF00/pullprep|r or |cFF00FF00/pp|r to export your action bars.")

