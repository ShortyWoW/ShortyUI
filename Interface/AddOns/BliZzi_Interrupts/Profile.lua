-- Copyright (c) 2026 BliZzi1337. All rights reserved.
-- Unauthorized copying, modification, distribution or use of this
-- software, in whole or in part, without prior written permission
-- from the copyright holder is strictly prohibited.
-- BliZzi Interrupts — Profile (Import / Export)
-- Serializes BIT.db settings and/or charDb position to a shareable string.

local BIT = BIT
local FORMAT_VERSION = "161"  -- 161: delta export (non-default values only)
local ENCODE_PREFIX  = "!BIT!"

-- Safe locale accessor (metatable returns key itself for missing keys, so rawget is needed)
local function LL(key, fallback)
    return rawget(BIT.L, key) or fallback or key
end

------------------------------------------------------------
-- Base64 encode / decode  (pure Lua, no library needed)
------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, #B64 do B64R[B64:sub(i,i)] = i - 1 end

local function Base64Encode(s)
    local out, len = {}, #s
    for i = 1, len, 3 do
        local b1 = s:byte(i)
        local b2 = i+1 <= len and s:byte(i+1) or 0
        local b3 = i+2 <= len and s:byte(i+2) or 0
        local n  = b1 * 65536 + b2 * 256 + b3
        out[#out+1] = B64:sub(math.floor(n/262144)%64+1, math.floor(n/262144)%64+1)
        out[#out+1] = B64:sub(math.floor(n/4096)%64+1,   math.floor(n/4096)%64+1)
        out[#out+1] = i+1 <= len and B64:sub(math.floor(n/64)%64+1, math.floor(n/64)%64+1) or "="
        out[#out+1] = i+2 <= len and B64:sub(n%64+1, n%64+1) or "="
    end
    return table.concat(out)
end

local function Base64Decode(s)
    s = s:gsub("[^A-Za-z0-9+/=]", "")
    local out = {}
    for i = 1, #s, 4 do
        local c1 = B64R[s:sub(i,   i  )] or 0
        local c2 = B64R[s:sub(i+1, i+1)] or 0
        local c3 = B64R[s:sub(i+2, i+2)] or 0
        local c4 = B64R[s:sub(i+3, i+3)] or 0
        local n  = c1*262144 + c2*4096 + c3*64 + c4
        out[#out+1] = string.char(math.floor(n/65536)%256)
        if s:sub(i+2,i+2) ~= "=" then out[#out+1] = string.char(math.floor(n/256)%256) end
        if s:sub(i+3,i+3) ~= "=" then out[#out+1] = string.char(n%256) end
    end
    return table.concat(out)
end

------------------------------------------------------------
-- Version helpers
------------------------------------------------------------
local function GetAddonVersion()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata("BliZzi_Interrupts", "Version")
    return v or "0.0.0"
end

-- Returns major, minor, patch as numbers (e.g. "3.1.0" → 3, 1, 0)
local function ParseVersion(vStr)
    local a, b, c = vStr:match("^(%d+)%.(%d+)%.(%d+)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

-- true if vA > vB
local function VersionGT(vA, vB)
    local a1,a2,a3 = ParseVersion(vA)
    local b1,b2,b3 = ParseVersion(vB)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

------------------------------------------------------------
-- Serialization helpers
------------------------------------------------------------

-- Keys in BIT.db that are tables and need special handling
local TABLE_KEYS = { disabledSpells = true, rotationOrder = true }
-- Keys that are purely internal / should never be exported
local SKIP_KEYS  = { rotationIndex = true, fontPath = true, borderTexturePath = true, barTexturePath = true,
                     charProfiles = true }

local function SerializeValue(v)
    local t = type(v)
    if t == "boolean" then return v and "b1" or "b0"
    elseif t == "number" then return "n" .. tostring(v)
    elseif t == "string" then
        -- escape ; and = so they don't collide with our delimiters
        return "s" .. v:gsub("\\", "\\\\"):gsub(";", "\\;"):gsub("=", "\\=")
    end
    return nil
end

local function DeserializeValue(raw)
    local prefix = raw:sub(1, 1)
    local body   = raw:sub(2)
    if prefix == "b" then return body == "1"
    elseif prefix == "n" then return tonumber(body)
    elseif prefix == "s" then
        return body:gsub("\\=", "="):gsub("\\;", ";"):gsub("\\\\", "\\")
    end
    return nil
end

-- Serialize disabledSpells: "123,456,789"
local function SerializeDisabledSpells(tbl)
    if not tbl then return "" end
    local ids = {}
    for id in pairs(tbl) do ids[#ids+1] = tostring(id) end
    return table.concat(ids, ",")
end

local function DeserializeDisabledSpells(str)
    local t = {}
    if str == "" then return t end
    for id in str:gmatch("[^,]+") do
        local n = tonumber(id)
        if n then t[n] = true end
    end
    return t
end

------------------------------------------------------------
-- Export
------------------------------------------------------------
function BIT.ExportProfile(includeSettings, includePos)
    local parts = { "BIT" .. FORMAT_VERSION }

    -- embed the current addon version so importers can check compatibility
    parts[#parts+1] = "v" .. GetAddonVersion()

    -- section flags: S=settings, P=position
    local flags = (includeSettings and "S" or "") .. (includePos and "P" or "")
    parts[#parts+1] = flags

    if includeSettings then
        parts[#parts+1] = "SETTINGS"
        -- Export ALL known settings (not just non-defaults) so the import is a
        -- complete, unambiguous snapshot of the source character's configuration.
        for k in pairs(BIT.DEFAULTS) do
            if not SKIP_KEYS[k] and not TABLE_KEYS[k] then
                local v  = BIT.db[k]
                local sv = SerializeValue(v)
                if sv then parts[#parts+1] = k .. "=" .. sv end
            end
        end
        -- disabledSpells: only include when non-empty
        local ds = SerializeDisabledSpells(BIT.db.disabledSpells)
        if ds ~= "" then
            parts[#parts+1] = "disabledSpells=" .. ds
        end
    end

    if includePos then
        parts[#parts+1] = "POSITION"
        local function addPos(key, val)
            if val then parts[#parts+1] = key .. "=n" .. tostring(val) end
        end
        addPos("posX",   BIT.charDb.posX)
        addPos("posY",   BIT.charDb.posY)
        addPos("posXUp", BIT.charDb.posXUp)
        addPos("posYUp", BIT.charDb.posYUp)
    end

    local plain = table.concat(parts, ";")
    return ENCODE_PREFIX .. Base64Encode(plain)
end

------------------------------------------------------------
-- Import
------------------------------------------------------------
function BIT.ImportProfile(str)
    if not str or str == "" then return false, "Empty string." end

    -- Decode !BIT! encoded strings
    if str:sub(1, #ENCODE_PREFIX) == ENCODE_PREFIX then
        local ok, decoded = pcall(Base64Decode, str:sub(#ENCODE_PREFIX + 1))
        if not ok or not decoded or decoded == "" then
            return false, "Failed to decode string."
        end
        str = decoded
    end

    local parts = {}
    -- split on ; but respect escaped \;
    local current = ""
    local i = 1
    while i <= #str do
        local c = str:sub(i, i)
        if c == "\\" and str:sub(i+1, i+1) == ";" then
            current = current .. ";"
            i = i + 2
        else
            if c == ";" then
                parts[#parts+1] = current
                current = ""
            else
                current = current .. c
            end
            i = i + 1
        end
    end
    if current ~= "" then parts[#parts+1] = current end

    if #parts < 2 then return false, "Invalid format." end

    local header = parts[1]
    -- Accept current version and the previous full-export version (160)
    local ACCEPTED = { ["BIT161"] = true, ["BIT160"] = true }
    if not ACCEPTED[header] then
        return false, "Incompatible version: " .. header
    end

    -- Version check: parts[2] is either "vX.Y.Z" (new) or the flags (old BIT160)
    local flagIdx = 2
    if parts[2] and parts[2]:sub(1,1) == "v" then
        local importVer = parts[2]:sub(2)  -- strip leading "v"
        local curVer    = GetAddonVersion()
        if VersionGT(importVer, curVer) then
            return false, string.format(
                "This profile was created with v%s but you have v%s. Please update the addon first.",
                importVer, curVer)
        end
        flagIdx = 3
    end

    local flags   = parts[flagIdx]
    local section = nil

    for idx = flagIdx + 1, #parts do
        local p = parts[idx]
        if p == "SETTINGS" then
            section = "SETTINGS"
            -- Reset to defaults first so any setting NOT in the string
            -- behaves exactly as it did on the source character (= default value).
            -- Without this, a delta-export could leave stale non-default values
            -- from the importing character intact.
            for k, v in pairs(BIT.DEFAULTS) do
                if not SKIP_KEYS[k] then BIT.db[k] = v end
            end
            BIT.db.disabledSpells = {}  -- clear disabled spells; import may re-add them
        elseif p == "POSITION" then
            section = "POSITION"
        else
            local key, raw = p:match("^([^=]+)=(.*)$")
            if key and raw then
                if section == "SETTINGS" then
                    if key == "disabledSpells" then
                        BIT.db.disabledSpells = DeserializeDisabledSpells(raw)
                    elseif not SKIP_KEYS[key] then
                        local v = DeserializeValue(raw)
                        if v ~= nil and BIT.DEFAULTS[key] ~= nil then
                            BIT.db[key] = v
                        end
                    end
                elseif section == "POSITION" then
                    local v = DeserializeValue(raw)
                    if v then BIT.charDb[key] = v end
                end
            end
        end
    end

    -- Re-apply locale if language changed
    BIT:ApplyLocale()
    -- Rebuild UI
    BIT.UI:RebuildBars()
    if BIT.UI.ApplyFramePosition then BIT.UI.ApplyFramePosition() end
    return true, "Import successful."
end

------------------------------------------------------------
-- Character Profile helpers
------------------------------------------------------------

-- Saves the current settings + position as a snapshot for this character
function BIT.SaveCharProfile()
    BIT.db.charProfiles = BIT.db.charProfiles or {}
    local snap = {}
    for k in pairs(BIT.DEFAULTS) do
        if BIT.db[k] ~= nil then snap[k] = BIT.db[k] end
    end
    -- fontPath/fontName use nil as DEFAULTS value so pairs() skips them; save explicitly
    if BIT.db.fontPath then snap.fontPath = BIT.db.fontPath end
    if BIT.db.fontName then snap.fontName = BIT.db.fontName end
    -- also snapshot per-character frame positions
    snap._posX   = BIT.charDb.posX
    snap._posY   = BIT.charDb.posY
    snap._posXUp = BIT.charDb.posXUp
    snap._posYUp = BIT.charDb.posYUp
    snap._syncX  = BIT.charDb.syncCdBarsPosX
    snap._syncY  = BIT.charDb.syncCdBarsPosY
    BIT.db.charProfiles[BIT.charKey or "Unknown"] = snap
end

-- Copies settings + position from another character's saved profile
function BIT.CopyCharProfile(sourceKey)
    local profiles = BIT.db.charProfiles
    if not profiles or not profiles[sourceKey] then return false end
    local snap = profiles[sourceKey]
    for k in pairs(BIT.DEFAULTS) do
        if snap[k] ~= nil then BIT.db[k] = snap[k] end
    end
    -- fontPath/fontName saved explicitly since their DEFAULTS are nil
    if snap.fontPath then BIT.db.fontPath = snap.fontPath end
    if snap.fontName then BIT.db.fontName = snap.fontName end
    -- restore positions if saved
    if snap._posX   then BIT.charDb.posX            = snap._posX   end
    if snap._posY   then BIT.charDb.posY            = snap._posY   end
    if snap._posXUp then BIT.charDb.posXUp          = snap._posXUp end
    if snap._posYUp then BIT.charDb.posYUp          = snap._posYUp end
    if snap._syncX  then BIT.charDb.syncCdBarsPosX  = snap._syncX  end
    if snap._syncY  then BIT.charDb.syncCdBarsPosY  = snap._syncY  end
    BIT:ApplyLocale()
    BIT.UI:RebuildBars()
    if BIT.UI.ApplyFramePosition then BIT.UI.ApplyFramePosition() end
    if BIT.SyncCD and BIT.SyncCD.ApplyBarsFrameSettings then
        BIT.SyncCD:ApplyBarsFrameSettings()
    end
    -- Save immediately so the new settings persist for this char
    BIT.SaveCharProfile()
    return true
end

-- Returns a sorted list of charKeys that have saved profiles (excluding current char)
function BIT.GetOtherCharProfiles()
    local list = {}
    local profiles = BIT.db.charProfiles or {}
    for key in pairs(profiles) do
        if key ~= (BIT.charKey or "") then
            list[#list+1] = key
        end
    end
    table.sort(list)
    return list
end

------------------------------------------------------------
-- Confirmation dialog (StaticPopup)
------------------------------------------------------------
StaticPopupDialogs["BIT_CONFIRM_COPY_PROFILE"] = {
    text          = "|cFF00DDDDBliZzi Interrupts|r\n\nCopy profile from |cFFFFD700%s|r?\n|cFFAAAAAA(Settings and position will be overwritten.)|r",
    button1       = "Copy",
    button2       = "Cancel",
    OnAccept      = function(self, data)
        if data and data.key and data.onSuccess then
            local ok = BIT.CopyCharProfile(data.key)
            if ok then data.onSuccess() end
        end
    end,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    preferredIndex = 3,
}

------------------------------------------------------------
-- Panel UI
------------------------------------------------------------
local profilePanel = nil

function BIT.UI:ShowProfilePanel()
    if profilePanel then
        if profilePanel:IsShown() then profilePanel:Hide() else profilePanel:Show() end
        return
    end

    local PW, PH = 400, 500
    profilePanel = CreateFrame("Frame", "BITProfilePanel", UIParent, "BackdropTemplate")
    profilePanel:SetSize(PW, PH)
    profilePanel:SetPoint("CENTER")
    profilePanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    profilePanel:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    profilePanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    profilePanel:SetMovable(true)
    profilePanel:EnableMouse(true)
    profilePanel:RegisterForDrag("LeftButton")
    profilePanel:SetScript("OnDragStart", profilePanel.StartMoving)
    profilePanel:SetScript("OnDragStop",  profilePanel.StopMovingOrSizing)
    profilePanel:SetClampedToScreen(true)
    profilePanel:SetFrameStrata("DIALOG")
    profilePanel:SetFrameLevel(200)

    -- Header bg
    local hdrBg = profilePanel:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBg:SetColorTexture(0.04, 0.04, 0.04, 1)
    hdrBg:SetPoint("TOPLEFT",  profilePanel, "TOPLEFT",  1, -1)
    hdrBg:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -1, -1)
    hdrBg:SetHeight(44)

    local hdrLine = profilePanel:CreateTexture(nil, "BORDER")
    hdrLine:SetColorTexture(0, 0.87, 0.87, 0.8)
    hdrLine:SetHeight(1)
    hdrLine:SetPoint("TOPLEFT",  profilePanel, "TOPLEFT",  1, -44)
    hdrLine:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -1, -44)

    local title = profilePanel:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    title:SetText("|cFF00DDDD" .. (LL("PROFILE_TITLE", "Profile — Import / Export")) .. "|r")
    title:SetPoint("TOP", profilePanel, "TOP", 0, -16)

    local closeBtn = CreateFrame("Button", nil, profilePanel)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -4, -4)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
    closeLbl:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    closeLbl:SetText("|cFFFF4444x|r")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeBtn:SetScript("OnClick", function() profilePanel:Hide() end)

    -- Helper: styled section label
    local function SectionLabel(text, yOff)
        local lbl = profilePanel:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        lbl:SetText("|cFFAAAAAA" .. text .. "|r")
        lbl:SetPoint("TOPLEFT", profilePanel, "TOPLEFT", 12, yOff)
        return lbl
    end

    -- Helper: styled checkbox
    local function MakeCheck(label, yOff, defaultVal)
        local f = CreateFrame("CheckButton", nil, profilePanel, "UICheckButtonTemplate")
        f:SetSize(20, 20)
        f:SetPoint("TOPLEFT", profilePanel, "TOPLEFT", 12, yOff)
        f:SetChecked(defaultVal)
        local lbl = profilePanel:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        lbl:SetText(label)
        lbl:SetPoint("LEFT", f, "RIGHT", 4, 0)
        return f
    end

    -- Helper: styled button (reuse rotation panel style)
    local function MakeBtn(label, w, h, parent)
        local btn = CreateFrame("Button", nil, parent or profilePanel)
        btn:SetSize(w, h)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.10, 0.06, 0.06, 1)
        btn.bg = bg
        local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(0, 0.87, 0.87, 0.8)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        lbl:SetText("|cFF00DDDD" .. label .. "|r")
        lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
        btn:SetScript("OnEnter",    function() bg:SetColorTexture(0.05,0.18,0.18,1); border:SetBackdropBorderColor(0,1,1,1) end)
        btn:SetScript("OnLeave",    function() bg:SetColorTexture(0.10,0.06,0.06,1); border:SetBackdropBorderColor(0,0.87,0.87,0.8) end)
        btn:SetScript("OnMouseDown",function() bg:SetColorTexture(0.02,0.10,0.10,1) end)
        btn:SetScript("OnMouseUp",  function() bg:SetColorTexture(0.05,0.18,0.18,1) end)
        return btn
    end

    -- Helper: styled EditBox
    local function MakeEditBox(yOff, h, readOnly)
        local eb = CreateFrame("EditBox", nil, profilePanel, "BackdropTemplate")
        eb:SetPoint("TOPLEFT",  profilePanel, "TOPLEFT",  12, yOff)
        eb:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -12, yOff)
        eb:SetHeight(h)
        eb:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
        eb:SetBackdropColor(0.05, 0.05, 0.05, 1)
        eb:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        eb:SetFontObject(GameFontNormal)
        eb:SetTextColor(0.9, 0.9, 0.9)
        eb:SetTextInsets(6, 6, 4, 4)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(false)
        eb:SetMaxLetters(4096)
        if readOnly then
            eb:SetScript("OnChar", function(self) self:SetText(self._val or "") end)
        end
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return eb
    end

    -- ── CHARACTER PROFILES SECTION ──────────────────────────────────
    SectionLabel(LL("PROFILE_CHARS", "Character Profiles"), -56)

    -- Current character label
    local curLbl = profilePanel:CreateFontString(nil, "OVERLAY")
    curLbl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    curLbl:SetText("|cFFAAAAAACurrent: |r|cFFFFD700" .. (BIT.charKey or "?") .. "|r")
    curLbl:SetPoint("TOPLEFT", profilePanel, "TOPLEFT", 12, -75)

    -- Save Now button
    local saveNowBtn = MakeBtn(LL("PROFILE_BTN_SAVE", "Save Now"), 90, 22)
    saveNowBtn:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -12, -71)
    saveNowBtn:SetScript("OnClick", function()
        BIT.SaveCharProfile()
        curLbl:SetText("|cFFAAAAAACurrent: |r|cFF00FF00" .. (BIT.charKey or "?") .. " ✓|r")
        C_Timer.After(2, function()
            curLbl:SetText("|cFFAAAAAACurrent: |r|cFFFFD700" .. (BIT.charKey or "?") .. "|r")
        end)
    end)

    -- Scroll frame for other character profiles
    local ROW_H    = 24
    local LIST_H   = 120
    local scrollBg = CreateFrame("Frame", nil, profilePanel, "BackdropTemplate")
    scrollBg:SetPoint("TOPLEFT",  profilePanel, "TOPLEFT",  12,  -100)
    scrollBg:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -12, -100)
    scrollBg:SetHeight(LIST_H)
    scrollBg:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8",
                           edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    scrollBg:SetBackdropColor(0.05, 0.05, 0.05, 1)
    scrollBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local sf = CreateFrame("ScrollFrame", nil, scrollBg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",  scrollBg, "TOPLEFT",  4, -4)
    sf:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -24, 4)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth())
    sc:SetHeight(LIST_H)
    sf:SetScrollChild(sc)

    local emptyLbl = sc:CreateFontString(nil, "OVERLAY")
    emptyLbl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    emptyLbl:SetText("|cFF666666No other character profiles saved yet.|r")
    emptyLbl:SetPoint("TOPLEFT", sc, "TOPLEFT", 4, -6)

    local charRows = {}

    local function RebuildCharList()
        -- hide old rows
        for _, r in ipairs(charRows) do r:Hide() end
        charRows = {}

        local others = BIT.GetOtherCharProfiles()
        emptyLbl:SetShown(#others == 0)

        local rowY = 0
        for _, key in ipairs(others) do
            local row = CreateFrame("Frame", nil, sc, "BackdropTemplate")
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -rowY)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -rowY)
            row:SetHeight(ROW_H)
            row:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8" })
            row:SetBackdropColor(rowY % 2 == 0 and 0.10 or 0.13, 0.10, rowY % 2 == 0 and 0.10 or 0.13, 1)

            local nameLbl = row:CreateFontString(nil, "OVERLAY")
            nameLbl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
            nameLbl:SetText("|cFFFFFFFF" .. key .. "|r")
            nameLbl:SetPoint("LEFT",  row, "LEFT", 6, 0)
            nameLbl:SetPoint("RIGHT", row, "RIGHT", -70, 0)
            nameLbl:SetWordWrap(false)

            local copyBtn = MakeBtn(LL("PROFILE_BTN_COPY_CHAR", "Copy"), 58, 18, row)
            copyBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local capturedKey = key
            copyBtn:SetScript("OnClick", function()
                StaticPopup_Show("BIT_CONFIRM_COPY_PROFILE", capturedKey, nil, {
                    key       = capturedKey,
                    onSuccess = function()
                        curLbl:SetText("|cFFAAAAAACurrent: |r|cFF00FF00Copied from " .. capturedKey .. " ✓|r")
                        C_Timer.After(3, function()
                            curLbl:SetText("|cFFAAAAAACurrent: |r|cFFFFD700" .. (BIT.charKey or "?") .. "|r")
                        end)
                    end,
                })
            end)

            row:Show()
            charRows[#charRows+1] = row
            rowY = rowY + ROW_H
        end
        sc:SetHeight(math.max(LIST_H, rowY))
    end

    RebuildCharList()

    -- divider between profiles and export
    local div1 = profilePanel:CreateTexture(nil, "BORDER")
    div1:SetColorTexture(0.25, 0.25, 0.25, 1)
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  profilePanel, "TOPLEFT",  12, -228)
    div1:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -12, -228)

    -- ── EXPORT SECTION ──────────────────────────────────────────────
    SectionLabel(LL("PROFILE_EXPORT", "Export"), -240)

    local chkSettings = MakeCheck(LL("PROFILE_OPT_SETTINGS", "Settings"), -260,  true)
    local chkPosition = MakeCheck(LL("PROFILE_OPT_POSITION", "Position"), -260, false)
    chkPosition:SetPoint("TOPLEFT", profilePanel, "TOPLEFT", 140, -260)

    local exportBox = MakeEditBox(-286, 28, true)
    exportBox._val = ""

    local exportBtn = MakeBtn(LL("PROFILE_BTN_EXPORT", "Export"), 100, 26)
    exportBtn:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -12, -320)
    exportBtn:SetScript("OnClick", function()
        local s = chkSettings:GetChecked()
        local p = chkPosition:GetChecked()
        if not s and not p then
            print("|cFF00DDDD[BliZzi]|r " .. (LL("PROFILE_ERR_NOTHING", "Select at least one option.")))
            return
        end
        local str = BIT.ExportProfile(s, p)
        exportBox._val = str
        exportBox:SetText(str)
        exportBox:HighlightText()
        exportBox:SetFocus()
    end)

    -- divider
    local div = profilePanel:CreateTexture(nil, "BORDER")
    div:SetColorTexture(0.25, 0.25, 0.25, 1)
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  profilePanel, "TOPLEFT",  12, -356)
    div:SetPoint("TOPRIGHT", profilePanel, "TOPRIGHT", -12, -356)

    -- ── IMPORT SECTION ──────────────────────────────────────────────
    SectionLabel(LL("PROFILE_IMPORT", "Import"), -368)

    local importBox = MakeEditBox(-388, 28, false)

    local statusLbl = profilePanel:CreateFontString(nil, "OVERLAY")
    statusLbl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    statusLbl:SetPoint("BOTTOMLEFT", profilePanel, "BOTTOMLEFT", 12, 44)
    statusLbl:SetText("")

    local importBtn = MakeBtn(LL("PROFILE_BTN_IMPORT", "Import"), 100, 26)
    importBtn:SetPoint("BOTTOMRIGHT", profilePanel, "BOTTOMRIGHT", -12, 10)
    importBtn:SetScript("OnClick", function()
        local str = importBox:GetText()
        local ok, msg = BIT.ImportProfile(str)
        if ok then
            statusLbl:SetText("|cFF00FF00" .. msg .. "|r")
            importBox:SetText("")
        else
            statusLbl:SetText("|cFFFF4444" .. msg .. "|r")
        end
    end)

    local clearBtn = MakeBtn(LL("PROFILE_BTN_CLEAR", "Clear"), 80, 26)
    clearBtn:SetPoint("BOTTOMRIGHT", importBtn, "BOTTOMLEFT", -6, 0)
    clearBtn:SetScript("OnClick", function()
        importBox:SetText("")
        exportBox:SetText("")
        exportBox._val = ""
        statusLbl:SetText("")
    end)

    profilePanel:Show()
end
