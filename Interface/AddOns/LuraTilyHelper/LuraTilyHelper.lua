-- ============================================================
-- Lura Tily Helper  –  Boss pattern tracker
-- Inspired by LuraHelper's approach for combat sync
-- ============================================================

local ADDON_NAME = "LuraTilyHelper"
local PREFIX     = "LuraTilyHelpr"

local TEX = "Interface\\AddOns\\LuraTilyHelper\\Textures\\"

local SYMS = {
    { k="1", tex=TEX.."sym_diamond.tga",  label="Diamond",  r=0.7, g=0.0, b=1.0 },
    { k="2", tex=TEX.."sym_triangle.tga", label="Triangle", r=0.0, g=1.0, b=0.2 },
    { k="3", tex=TEX.."sym_circle.tga",   label="Circle",   r=1.0, g=0.5, b=0.0 },
    { k="4", tex=TEX.."sym_cross.tga",    label="Cross",    r=1.0, g=0.1, b=0.1 },
    { k="5", tex=TEX.."sym_t.tga",        label="T",        r=1.0, g=0.9, b=0.0 },
}

local MAX      = 5
local state    = {}
local arcIcons = {}

-- Arc geometry (smile shape, right to left)
local R = 80
local slots = {}
for i = 1, MAX do
    local angle = math.rad((i - 1) / (MAX - 1) * 180)
    slots[i] = { x = R * math.cos(angle), y = -R * math.sin(angle) }
end

local function redraw()
    for i = 1, MAX do arcIcons[i]:Hide() end
    for i, s in ipairs(state) do
        arcIcons[i]:SetTexture(s.tex)
        arcIcons[i]:Show()
    end
end

local function serialize()
    local t = {}
    for _, s in ipairs(state) do t[#t+1] = s.k end
    return table.concat(t, ",")
end

local function deserialize(str)
    local decoded = {}
    if not str or str == "" then return decoded end
    for k in str:gmatch("[^,]+") do
        for _, sym in ipairs(SYMS) do
            if sym.k == k then
                decoded[#decoded+1] = { k=sym.k, tex=sym.tex }
                break
            end
        end
    end
    return decoded
end

-- Send current state to raid (only called explicitly via Send button)
local function sendState()
    local msg = serialize()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, "S:"..msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, "S:"..msg, "PARTY")
    end
end

-- Send clear to raid
local function sendClear()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, "CLEAR", "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, "CLEAR", "PARTY")
    end
end

-- Fake Raid Warning
local fakeRWFrame = nil
local function showFakeRW(text)
    if not fakeRWFrame then
        fakeRWFrame = CreateFrame("Frame", "LuraTilyFakeRW", UIParent)
        fakeRWFrame:SetSize(700, 80)
        fakeRWFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
        fakeRWFrame:SetFrameStrata("DIALOG")
        fakeRWFrame:SetMovable(true)
        fakeRWFrame:EnableMouse(true)
        fakeRWFrame:RegisterForDrag("LeftButton")
        fakeRWFrame:SetScript("OnDragStart", fakeRWFrame.StartMoving)
        fakeRWFrame:SetScript("OnDragStop",  fakeRWFrame.StopMovingOrSizing)

        local hdr = fakeRWFrame:CreateFontString(nil, "OVERLAY")
        hdr:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        hdr:SetPoint("TOP", fakeRWFrame, "TOP", 0, 0)
        hdr:SetText("|cffff4400-- Raid Warning --|r")
        fakeRWFrame.hdr = hdr

        local lbl = fakeRWFrame:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        lbl:SetPoint("TOP", hdr, "BOTTOM", 0, -4)
        lbl:SetTextColor(1, 0.8, 0)
        fakeRWFrame.lbl = lbl
    end
    fakeRWFrame.lbl:SetText(text)
    fakeRWFrame:Show()
    PlaySound(8959, "Master")
    C_Timer.After(5, function() if fakeRWFrame then fakeRWFrame:Hide() end end)
end

local function buildPatternText()
    local parts = {}
    for _, s in ipairs(state) do
        for _, sym in ipairs(SYMS) do
            if sym.k == s.k then parts[#parts+1] = sym.label; break end
        end
    end
    return #parts > 0 and table.concat(parts, " > ") or "(empty)"
end

local function sendRW()
    local text = buildPatternText()
    showFakeRW(text)
    local msg = "RW:" .. serialize()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    end
end

-- Build main window
local win

local function build()
    if win then return end

    local W, H = 290, 330

    win = CreateFrame("Frame", "LuraTilyHelperWin", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER", UIParent, "CENTER", 200, 80)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop",  win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    win:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left=4, right=4, top=4, bottom=4 },
    })
    win:SetBackdropColor(0.04, 0.0, 0.13, 0.55)
    win:SetBackdropBorderColor(0.5, 0.0, 0.9, 1.0)

    -- Close button
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() win:Hide() end)

    -- Resize grip
    local winScale = 1.0
    local grip = CreateFrame("Frame", nil, win)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -4, 4)
    grip:EnableMouse(true)
    grip:SetFrameStrata("TOOLTIP")
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnEnter", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        GameTooltip:SetOwner(grip, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        GameTooltip:Hide()
    end)
    local resizing, startX, startY, startScale = false
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            resizing = true
            startX, startY = GetCursorPosition()
            startScale = winScale
        end
    end)
    grip:SetScript("OnMouseUp", function() resizing = false end)
    grip:SetScript("OnUpdate", function()
        if not resizing then return end
        local cx, cy = GetCursorPosition()
        local delta = (cx - startX) + (startY - cy)
        winScale = math.max(0.4, math.min(2.5, startScale + delta / 250))
        win:SetScale(winScale)
    end)

    -- Title
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", win, "TOP", 0, -14)
    title:SetText("Lura Tily Helper")
    title:SetTextColor(0.85, 0.4, 1.0)

    -- Top separator
    local sep1 = win:CreateTexture(nil, "ARTWORK")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT",  win, "TOPLEFT",  10, -58)
    sep1:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -58)
    sep1:SetColorTexture(0.4, 0.0, 0.8, 0.5)

    -- Arc icons
    local ARC_Y, iconSz = -100, 44
    for i = 1, MAX do
        local tex = win:CreateTexture(nil, "OVERLAY")
        tex:SetSize(iconSz, iconSz)
        tex:SetPoint("CENTER", win, "TOP", slots[i].x, ARC_Y + slots[i].y)
        tex:Hide()
        arcIcons[i] = tex
    end

    -- Arrow separators
    for i = 1, MAX - 1 do
        local mx = (slots[i].x + slots[i+1].x) / 2
        local my = (slots[i].y + slots[i+1].y) / 2
        local arr = win:CreateFontString(nil, "OVERLAY")
        arr:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        arr:SetPoint("CENTER", win, "TOP", mx, ARC_Y + my)
        arr:SetText(">")
        arr:SetTextColor(0.5, 0.3, 0.8, 0.7)
    end

    -- BOSS label
    local bossLabel = win:CreateFontString(nil, "OVERLAY")
    bossLabel:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    bossLabel:SetPoint("CENTER", win, "TOP", 0, ARC_Y)
    bossLabel:SetText("|cffff2222BOSS|r")

    -- Sep above buttons
    local sep2 = win:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 98)
    sep2:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 98)
    sep2:SetColorTexture(0.4, 0.0, 0.8, 0.5)

    -- Ligne HAUT : Clear (gauche) + Send (droite)
    local clr = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    clr:SetSize(80, 24)
    clr:SetPoint("BOTTOM", win, "BOTTOM", -45, 100)
    clr:SetText("Clear")
    clr:SetScript("OnClick", function()
        state = {}
        redraw()
        sendClear()
    end)

    local snd = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    snd:SetSize(80, 24)
    snd:SetPoint("BOTTOM", win, "BOTTOM", 45, 100)
    snd:SetText("|cff00ff00Send|r")
    snd:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Send pattern to all addon users\n(works in combat)", 1, 1, 1)
        GameTooltip:Show()
    end)
    snd:SetScript("OnLeave", function() GameTooltip:Hide() end)
    snd:SetScript("OnClick", function()
        if #state == 0 then return end
        sendState()
    end)

    -- Sep entre les deux lignes
    local sep3 = win:CreateTexture(nil, "ARTWORK")
    sep3:SetHeight(1)
    sep3:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 94)
    sep3:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 94)
    sep3:SetColorTexture(0.3, 0.0, 0.6, 0.4)

    -- Ligne BAS : SAY (gauche) + RW (droite)
    local say = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    say:SetSize(80, 24)
    say:SetPoint("BOTTOM", win, "BOTTOM", -45, 65)
    say:SetText("|cffffff00SAY|r")
    say:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Send the pattern in /say\n(visible to everyone nearby)", 1, 1, 1)
        GameTooltip:Show()
    end)
    say:SetScript("OnLeave", function() GameTooltip:Hide() end)
    say:SetScript("OnClick", function()
        DEFAULT_CHAT_FRAME:AddMessage("|cffffffff[" .. UnitName("player") .. "] says: " .. buildPatternText() .. "|r")
    end)

    local rw = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    rw:SetSize(80, 24)
    rw:SetPoint("BOTTOM", win, "BOTTOM", 45, 65)
    rw:SetText("|cffff4444RW|r")
    rw:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Raid Warning\nDisplayed on screen for all addon users", 1, 1, 1)
        GameTooltip:Show()
    end)
    rw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rw:SetScript("OnClick", function() sendRW() end)

    -- Sep above icon row
    local sep4 = win:CreateTexture(nil, "ARTWORK")
    sep4:SetHeight(1)
    sep4:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 57)
    sep4:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 57)
    sep4:SetColorTexture(0.3, 0.0, 0.6, 0.3)

    -- Symbol buttons
    local bSz, bGap = 44, 5
    local rowW = #SYMS * bSz + (#SYMS - 1) * bGap
    local bX0  = -(rowW / 2) + bSz / 2

    for i, sym in ipairs(SYMS) do
        local btn = CreateFrame("Button", nil, win, "BackdropTemplate")
        btn:SetSize(bSz, bSz)
        btn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT",
            (W / 2 + bX0 + (i - 1) * (bSz + bGap)) - bSz / 2, 8)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 3,
            insets   = { left=3, right=3, top=3, bottom=3 },
        })
        btn:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
        btn:SetBackdropBorderColor(sym.r, sym.g, sym.b, 1.0)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT",     btn, "TOPLEFT",     3,  -3)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3,  3)
        tex:SetTexture(sym.tex)

        btn:SetScript("OnEnter", function(s)
            s:SetBackdropBorderColor(1, 1, 1, 1)
            s:SetBackdropColor(sym.r*0.2, sym.g*0.2, sym.b*0.2, 1)
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:SetText(sym.label, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(s)
            s:SetBackdropBorderColor(sym.r, sym.g, sym.b, 1.0)
            s:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if #state >= MAX then return end
            state[#state+1] = { k=sym.k, tex=sym.tex }
            redraw()
            -- Pas d'envoi auto - utiliser le bouton Send
        end)
    end
end

-- Events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("CHAT_MSG_ADDON")

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and (...) == ADDON_NAME then
        build()
        print("|cffaa44ffLura Tily Helper|r loaded! Type |cffffd700/lura|r to open.")

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= PREFIX then return end

        if msg == "CLEAR" then
            state = {}
            if win then redraw() end
            return
        end

        local stateStr = msg:match("^S:(.*)$")
        if stateStr then
            state = deserialize(stateStr)
            if not win then build() end
            win:Show()
            redraw()
            return
        end

        local rwStr = msg:match("^RW:(.*)$")
        if rwStr then
            local decoded = deserialize(rwStr)
            local parts = {}
            for _, s in ipairs(decoded) do
                for _, sym in ipairs(SYMS) do
                    if sym.k == s.k then parts[#parts+1] = sym.label; break end
                end
            end
            showFakeRW(table.concat(parts, " > "))
        end
    end
end)

-- Slash commands
SLASH_LURATILYHELPER1 = "/lura"
SLASH_LURATILYHELPER2 = "/luratily"

SlashCmdList["LURATILYHELPER"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "clear" then
        state = {}
        if win then redraw() end
        sendClear()
    elseif msg == "rw" then
        sendRW()
    else
        if win then
            if win:IsShown() then win:Hide() else win:Show() end
        end
    end
end
