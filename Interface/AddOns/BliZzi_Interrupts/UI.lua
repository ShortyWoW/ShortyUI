-- Copyright (c) 2026 BliZzi1337. All rights reserved.
-- Unauthorized copying, modification, distribution or use of this
-- software, in whole or in part, without prior written permission
-- from the copyright holder is strictly prohibited.
--[[
    UI.lua - BliZzi Interrupts
    Main frame, bars, resize handle and display update loop.
]]

BIT    = BIT or {}
BIT.UI = BIT.UI or {}

local bars         = {}
local mainFrame    = nil
local titleText    = nil
local resizeHandle = nil
local _posEditor        = nil
local _posEditorRefresh = nil
local _lockBtn          = nil
local isResizing   = false
local shouldShowByZone = true

------------------------------------------------------------
-- Fade helper
-- FadeFrame(frame, targetAlpha, duration)
-- Smoothly transitions a frame to targetAlpha over duration seconds.
-- Automatically calls Show() at start and Hide() when fading to 0.
------------------------------------------------------------
local _fadeTickers = {}   -- frame → ticker, so we can cancel mid-fade

local function FadeFrame(frame, targetAlpha, duration)
    if not frame then return end
    duration = duration or 0.3

    -- Cancel any in-progress fade on this frame
    if _fadeTickers[frame] then
        _fadeTickers[frame]:Cancel()
        _fadeTickers[frame] = nil
    end

    local startAlpha = frame:GetAlpha()

    -- Already at target — just make sure visibility is correct
    if math.abs(startAlpha - targetAlpha) < 0.01 then
        if targetAlpha <= 0 then frame:Hide() else frame:Show() end
        -- Sync child bar alphas too (SetAlpha doesn't propagate to child frames)
        for _, bar in ipairs(bars) do bar:SetAlpha(targetAlpha) end
        return
    end

    if targetAlpha > 0 then
        frame:SetAlpha(startAlpha)
        frame:Show()
    end

    local elapsed  = 0
    local interval = 0.02   -- ~50fps
    _fadeTickers[frame] = C_Timer.NewTicker(interval, function(t)
        elapsed = elapsed + interval
        local pct   = math.min(elapsed / duration, 1)
        local alpha = startAlpha + (targetAlpha - startAlpha) * pct
        frame:SetAlpha(alpha)
        -- Child frames need explicit alpha (WoW doesn't propagate parent alpha to child frames)
        for _, bar in ipairs(bars) do bar:SetAlpha(alpha) end
        if pct >= 1 then
            t:Cancel()
            _fadeTickers[frame] = nil
            if targetAlpha <= 0 then frame:Hide() end
        end
    end)
end

------------------------------------------------------------
-- Layout helper
------------------------------------------------------------
local function GetBarLayout()
    local db    = BIT.db
    local fw    = db.frameWidth
    local titleH = db.showTitle and 20 or 0

    -- Snap barH to a value that is an exact integer number of screen pixels.
    -- mainFrame may have its own scale (ApplyAutoScale), so use GetEffectiveScale()
    -- on the mainFrame itself if it exists, otherwise fall back to UIParent.
    local uiScale = (mainFrame and mainFrame:GetEffectiveScale()) or UIParent:GetEffectiveScale()
    local rawH    = math.max(12, db.barHeight)
    local barH    = math.floor(rawH * uiScale + 0.5) / uiScale

    local iconS = barH
    local barW  = math.max(60, fw - iconS)
    local autoNameSize = math.max(9,  math.floor(barH * 0.45))
    local autoCdSize   = math.max(10, math.floor(barH * 0.55))
    local fontSize   = (db.nameFontSize  and db.nameFontSize  > 0) and db.nameFontSize  or autoNameSize
    local cdFontSize = (db.readyFontSize and db.readyFontSize > 0) and db.readyFontSize or autoCdSize
    return barW, barH, iconS, fontSize, cdFontSize, titleH
end

-- Icon Only mode: returns true when the tracker should use compact icon grid
-- Icon Only Mode was removed in 3.3.8 — the feature conflicted with the new
-- Attached-to-Unit-Frames display and caused overlap confusion. The stub
-- always returns false so the remaining code paths that branch on
-- iconOnly stay dormant without needing line-by-line deletion.
local function IsIconOnlyMode()
    return false
end

------------------------------------------------------------
-- Zone visibility
------------------------------------------------------------
function BIT.UI:CheckZoneVisibility(force)
    local db = BIT.db
    if force then
        shouldShowByZone = true
    else
        local _, instanceType = IsInInstance()
        if     instanceType == "party" then shouldShowByZone = db.showInDungeon
        elseif instanceType == "raid"  then shouldShowByZone = db.showInRaid
        elseif instanceType == "arena" then shouldShowByZone = db.showInArena
        elseif instanceType == "pvp"   then shouldShowByZone = db.showInBG
        else                                shouldShowByZone = db.showInOpenWorld
        end
    end
    if mainFrame then
        -- Keep tracker visible while settings are open so the user can preview changes
        local settingsOpen = BIT_SettingsFrame and BIT_SettingsFrame:IsShown()
        local shouldShow = settingsOpen
            or (shouldShowByZone and (not db.hideOutOfCombat or BIT.inCombat))

        -- Attached-display mode: hide the classic bars window entirely and
        -- drive per-member icons instead.  Settings panel still previews the
        -- bars if the user opens it with mode=ATTACHED (so they can switch
        -- back and see the result).
        if db.interruptDisplayMode == "ATTACHED" and not settingsOpen then
            FadeFrame(mainFrame, 0, 0.2)
        else
            local targetAlpha = shouldShow and (db.alpha or 1.0) or 0
            FadeFrame(mainFrame, targetAlpha, 0.4)
        end
    end

    -- Rebuild attached icons on zone transitions — party frames can change
    -- (e.g. entering/leaving an instance), so the anchor may have moved.
    if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
        BIT.UI.AttachedInterrupts:Rebuild()
    end
end

------------------------------------------------------------
-- Rebuild bars
------------------------------------------------------------
function BIT.UI:RebuildBars()
    local db  = BIT.db
    local m   = BIT.Media

    for i = 1, 7 do
        if bars[i] then
            bars[i]:Hide()
            bars[i]:SetParent(nil)
            bars[i] = nil
        end
    end

    local barW, barH, iconS, fontSize, cdFontSize, titleH = GetBarLayout()
    local iconOnly = IsIconOnlyMode()
    if iconOnly then titleH = 0 end

    if not mainFrame then return end
    mainFrame:SetSize(db.frameWidth, mainFrame:GetHeight() or 200)
    -- Alpha is managed by CheckZoneVisibility / FadeFrame — don't override here
    if titleText then
        if db.showTitle and not iconOnly then titleText:Show() else titleText:Hide() end
        local titleSize = (db.titleFontSize and db.titleFontSize > 0) and db.titleFontSize or 12
        m:SetFont(titleText, titleSize)
        local align   = db.titleAlign or "CENTER"
        local titleY  = -titleH + (db.titleOffsetY or 0)
        titleText:ClearAllPoints()
        if align == "LEFT" then
            titleText:SetPoint("BOTTOMLEFT",  mainFrame, "TOPLEFT",  0, titleY)
        elseif align == "RIGHT" then
            titleText:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", 0, titleY)
        else
            titleText:SetPoint("BOTTOM",      mainFrame, "TOP",      0, titleY)
        end
        titleText:SetTextColor(db.titleColorR or 0, db.titleColorG or 0.867, db.titleColorB or 0.867)
        -- Force re-render so alignment takes effect immediately
        titleText:SetText(titleText:GetText())
    end
    -- Re-anchor frame so bar[1] stays fixed when title is toggled
    if BIT.UI.ApplyFramePosition then BIT.UI.ApplyFramePosition() end


    local prevFrame = nil
    local barGap = db.barGap or 0
    local growUp = db.growUpward
    local iconOnly = IsIconOnlyMode()

    for i = 1, 7 do
        local f = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")

        if iconOnly then
            -- ── Icon Only mode: square icon cells in a horizontal row ──
            local icoSize = db.iconOnlySize or 36
            local icoGap  = db.iconOnlySpacing or 4
            local perRow  = db.iconOnlyPerRow or 7
            local goRight = (db.iconOnlyGrowth or "RIGHT") == "RIGHT"
            f:SetSize(icoSize, icoSize)

            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            local xOff = col * (icoSize + icoGap)
            local yOff = row * (icoSize + icoGap)
            if goRight then
                if growUp then
                    f:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", xOff, yOff)
                else
                    f:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, -yOff - titleH)
                end
            else
                if growUp then
                    f:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -xOff, yOff)
                else
                    f:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -xOff, -yOff - titleH)
                end
            end
        else
            -- ── Normal bar mode ──
            f:SetSize(db.frameWidth, barH)
            if i == 1 then
                if growUp then
                    f:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
                else
                    f:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -titleH)
                end
            else
                if growUp then
                    f:SetPoint("BOTTOMLEFT", prevFrame, "TOPLEFT", 0, barGap)
                else
                    f:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -barGap)
                end
            end
        end
        prevFrame = f
        f:EnableMouse(false)

        local iconRight = db.iconSide == "RIGHT"

        -- Icon
        local ico = f:CreateTexture(nil, "ARTWORK")
        if iconOnly then
            ico:SetAllPoints(f)
        elseif iconRight then
            ico:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iconS, 0)
            ico:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,     0)
        else
            ico:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,     0)
            ico:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iconS, 0)
        end
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icon = ico

        -- Icon background
        local iconBg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
        if iconOnly then
            iconBg:SetAllPoints(f)
        elseif iconRight then
            iconBg:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iconS, 0)
            iconBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,     0)
        else
            iconBg:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,     0)
            iconBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iconS, 0)
        end
        iconBg:SetTexture(m.flatTexture)
        iconBg:SetVertexColor(0.1, 0.1, 0.1, 1)
        f.iconBg = iconBg

        -- Icon border frame
        local iconBorderFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        if iconOnly then
            iconBorderFrame:SetAllPoints(f)
        elseif iconRight then
            iconBorderFrame:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iconS, 0)
            iconBorderFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,     0)
        else
            iconBorderFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,     0)
            iconBorderFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iconS, 0)
        end
        iconBorderFrame:SetFrameLevel(f:GetFrameLevel() + 5)
        f.iconBorderFrame = iconBorderFrame

        -- Clickable frame over icon for announce
        local iconBtn = CreateFrame("Button", nil, f)
        if iconOnly then
            iconBtn:SetAllPoints(f)
        elseif iconRight then
            iconBtn:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iconS, 0)
            iconBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,     0)
        else
            iconBtn:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,     0)
            iconBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iconS, 0)
        end
        iconBtn:SetFrameLevel(f:GetFrameLevel() + 10)
        iconBtn:EnableMouse(true)
        -- SetPropagateMouseClicks is protected in 11.x/12.x; defer if currently in combat
        if not InCombatLockdown() then
            iconBtn:SetPropagateMouseClicks(true)
        else
            BIT._pendingPropagate = BIT._pendingPropagate or {}
            BIT._pendingPropagate[#BIT._pendingPropagate+1] = iconBtn
        end
        f.iconBtn = iconBtn
        iconBtn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" and false then -- Under Construction
                -- Detaint GetTime() immediately — tainted numbers in control flow
                -- (if conditions) corrupt the entire execution frame.
                local okNow, sNow = pcall(string.format, "%.3f", GetTime())
                local now = okNow and tonumber(sNow) or 0

                -- Anti-spam: detaint stored lock time before comparison
                if db.antiSpam and f.announceLockedUntil then
                    local okL, sL = pcall(string.format, "%.3f", f.announceLockedUntil)
                    local lockUntil = okL and tonumber(sL) or 0
                    if now < lockUntil then return end
                end

                -- Name: strip color codes; fall back to "?" on any taint
                local rawLastName = f._lastName
                local name
                if rawLastName and not issecretvalue(rawLastName) then
                    local okG, stripped = pcall(function()
                        return rawLastName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    end)
                    if okG and stripped and not issecretvalue(stripped) then
                        name = stripped
                    end
                end
                name = name or "?"

                -- spellName comes from our own table — always untainted
                local spellName = f.spellID and BIT.ALL_INTERRUPTS[f.spellID] and BIT.ALL_INTERRUPTS[f.spellID].name or "?"

                -- Detaint f.cdEnd before arithmetic
                local cdEndClean = 0
                if f.cdEnd then
                    local okC, sC = pcall(string.format, "%.3f", f.cdEnd)
                    cdEndClean = okC and tonumber(sC) or 0
                end
                local rem = cdEndClean - now

                local msg
                if rem > 0.5 then
                    msg = string.format(BIT.L["MSG_ANNOUNCE_CD"], name, spellName, rem)
                else
                    msg = string.format(BIT.L["MSG_ANNOUNCE_READY"], name, spellName)
                end
                if issecretvalue(msg) then return end

                if IsInGroup() then
                    C_ChatInfo.SendChatMessage(msg, "INSTANCE_CHAT")
                else
                    print("|cff0091edBliZzi|r|cffffa300Interrupts|r " .. msg)
                end

                -- Store clean lock time (tainted GetTime would corrupt next click's frame)
                if db.antiSpam then
                    local lockDur = rem > 0.5 and rem or 5
                    f.announceLockedUntil = now + lockDur
                end
            end
        end)

        -- Bar background solid (fills bar area) — hidden in Icon Only mode
        local barBgSolid = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        if iconOnly then
            barBgSolid:Hide()
        elseif iconRight then
            barBgSolid:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,      0)
            barBgSolid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",-iconS, 0)
        else
            barBgSolid:SetPoint("TOPLEFT",     f, "TOPLEFT",    iconS, 0)
            barBgSolid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
        end
        barBgSolid:SetTexture(m.flatTexture)
        barBgSolid:SetVertexColor(0, 0, 0, 1)
        f.barBgSolid = barBgSolid

        -- Textured bar background — hidden in Icon Only mode
        local barBg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
        if iconOnly then
            barBg:Hide()
        elseif iconRight then
            barBg:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,      0)
            barBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",-iconS, 0)
        else
            barBg:SetPoint("TOPLEFT",     f, "TOPLEFT",    iconS, 0)
            barBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
        end
        m:SetBarTexture(barBg)
        barBg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
        f.barBg = barBg

        -- StatusBar (CD progress) — hidden in Icon Only mode
        local sb = CreateFrame("StatusBar", nil, f)
        if iconOnly then
            sb:Hide()
        elseif iconRight then
            sb:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,      0)
            sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",-iconS, 0)
        else
            sb:SetPoint("TOPLEFT",     f, "TOPLEFT",    iconS, 0)
            sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
        end
        m:SetBarTexture(sb)
        sb:SetStatusBarColor(1, 1, 1, 0.85)
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(0)
        sb:SetFrameLevel(f:GetFrameLevel() + 1)
        -- Remove the default NineSlice border WoW adds to StatusBar frames
        if sb.NineSlice then sb.NineSlice:SetAtlas("") sb.NineSlice:Hide() end
        if sb.BorderFrame then sb.BorderFrame:Hide() end
        -- Bar value is driven by UpdateDisplay (10x/s) — no OnUpdate needed
        sb._cdEnd  = 0
        sb._baseCd = 1
        f.cdBar = sb

        -- Content layer (text) — must be above border overlays
        local content = CreateFrame("Frame", nil, f)
        if iconOnly then
            content:SetAllPoints(f)
        elseif iconRight then
            content:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,      0)
            content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",-iconS, 0)
        else
            content:SetPoint("TOPLEFT",     f, "TOPLEFT",    iconS, 0)
            content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
        end
        content:SetFrameLevel(sb:GetFrameLevel() + 20)
        f.contentFrame = content

        -- Name text — hidden in Icon Only mode
        local nm = content:CreateFontString(nil, "OVERLAY")
        m:SetFont(nm, fontSize)
        nm:SetPoint("LEFT", 6 + (db.nameOffsetX or 0), (db.nameOffsetY or 0))
        nm:SetJustifyH("LEFT")
        nm:SetWidth(db.showReady and (barW - 50) or (barW - 10))
        nm:SetWordWrap(false)
        nm:SetShadowOffset(db.shadowOffsetX or 0, db.shadowOffsetY or 0)
        if iconOnly then nm:Hide() end
        f.nameText      = nm
        f.nameShortW    = barW - 50   -- width when CD/READY text is shown
        f.nameFullW     = barW - 10   -- width when no CD/READY text

        -- Party CD text — hidden in Icon Only mode
        local pcd = content:CreateFontString(nil, "OVERLAY")
        m:SetFont(pcd, cdFontSize)
        pcd:SetPoint("RIGHT", -6 + (db.cdOffsetX or 0), (db.cdOffsetY or 0))
        pcd:SetShadowOffset(db.shadowOffsetX or 0, db.shadowOffsetY or 0)
        if iconOnly then pcd:Hide() end
        f.partyCdText = pcd

        -- Player CD wrapper (taint-safe) — also handles click-to-announce
        local wrap = CreateFrame("Frame", nil, content)
        wrap:SetAllPoints()
        wrap:SetFrameLevel(content:GetFrameLevel() + 1)
        wrap:EnableMouse(true)
        -- SetPropagateMouseClicks is protected in 11.x/12.x; defer if currently in combat
        if not InCombatLockdown() then
            wrap:SetPropagateMouseClicks(true)  -- pass unhandled clicks down to mainFrame for drag
        else
            BIT._pendingPropagate = BIT._pendingPropagate or {}
            BIT._pendingPropagate[#BIT._pendingPropagate+1] = wrap
        end
        -- no click handler on bar — announce is on icon instead
        f.barWrap = wrap
        local mycd = wrap:CreateFontString(nil, "OVERLAY")
        m:SetFont(mycd, cdFontSize)
        mycd:SetPoint("RIGHT", -6 + (db.cdOffsetX or 0), (db.cdOffsetY or 0))
        mycd:SetShadowOffset(db.shadowOffsetX or 0, db.shadowOffsetY or 0)
        if iconOnly then mycd:Hide() end
        f.playerCdWrapper = wrap
        f.playerCdText    = mycd

        -- Icon Only: CD countdown overlay centered on the icon
        if iconOnly then
            local icoCounterSize = db.iconOnlyCounterSize or 14
            -- Create on a high-level overlay frame so text draws above icon + border
            local cdOverlay = CreateFrame("Frame", nil, f)
            cdOverlay:SetAllPoints(f)
            cdOverlay:SetFrameLevel(f:GetFrameLevel() + 30)
            local icoCd = cdOverlay:CreateFontString(nil, "OVERLAY")
            m:SetFont(icoCd, icoCounterSize)
            icoCd:SetPoint("CENTER", f, "CENTER", 0, 0)
            icoCd:SetJustifyH("CENTER")
            icoCd:SetJustifyV("MIDDLE")
            icoCd:SetShadowOffset(1, -1)
            icoCd:SetTextColor(1, 1, 1)
            f.iconOnlyCdText = icoCd
        end

        -- Border overlays: above StatusBar but below content/text (sb+10, content is sb+20)
        local borderOverlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
        borderOverlay:SetAllPoints(f)
        borderOverlay:SetFrameLevel(sb:GetFrameLevel() + 10)
        borderOverlay:EnableMouse(false)
        f.borderOverlay = borderOverlay

        local iconBorderOverlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
        if iconOnly then
            iconBorderOverlay:SetAllPoints(f)
        elseif iconRight then
            iconBorderOverlay:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iconS - 1, 0)
            iconBorderOverlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,         0)
        else
            iconBorderOverlay:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,         0)
            iconBorderOverlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iconS + 1, 0)
        end
        iconBorderOverlay:SetFrameLevel(sb:GetFrameLevel() + 11)
        iconBorderOverlay:EnableMouse(false)
        f.iconBorderOverlay = iconBorderOverlay

        f:Hide()

        -- Rotation indicator: 2px vertical divider between icon and bar
        local rotLine = f:CreateTexture(nil, "OVERLAY")
        rotLine:SetWidth(5)
        if iconOnly then
            -- No rotation line in Icon Only mode
            rotLine:Hide()
        elseif iconRight then
            rotLine:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iconS - 2, 0)
            rotLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -iconS + 3, 0)
        else
            rotLine:SetPoint("TOPLEFT",     f, "TOPLEFT",    iconS - 2, 0)
            rotLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iconS + 3, 0)
        end
        rotLine:SetColorTexture(0, 1, 0, 1)
        rotLine:Hide()
        f.rotLine = rotLine

        bars[i] = f

        -- Apply border if set
        BIT.UI:ApplyBorderToFrame(f)
    end

    -- FrameLevel fixup: borders must draw above ALL bar base frames (including
    -- bars created after them), but below their own content/text frames.
    -- We raise all borderOverlays to a shared high base, then content above that.
    local highBase = mainFrame:GetFrameLevel() + 500
    for i = 1, 7 do
        local b = bars[i]
        if b then
            b.borderOverlay:SetFrameLevel(highBase)
            b.iconBorderOverlay:SetFrameLevel(highBase + 1)
            if b.contentFrame then
                b.contentFrame:SetFrameLevel(highBase + 10 + i)
                if b.playerCdWrapper then
                    b.playerCdWrapper:SetFrameLevel(highBase + 11 + i)
                end
            end
        end
    end

    BIT.UI:ApplyClickThrough()

    -- Immediately populate the newly created (hidden) bars so there is no
    -- render frame where all bars are invisible → eliminates flicker when
    -- changing settings that trigger a full rebuild.
    BIT.UI:UpdateDisplay()

    -- Keep Party CD Bars in sync with any structural setting change
    if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
end

------------------------------------------------------------
-- Click-through control
-- • db.locked = true  → whole frame is click-through (no drag, no interact)
-- • db.clickToAnnounce = false → icons are click-through (no announce click)
------------------------------------------------------------
function BIT.UI:ApplyClickThrough()
    if not mainFrame then return end
    local db = BIT.db
    local locked    = db.locked or false
    local canAnnounce = db.clickToAnnounce or false

    -- mainFrame: needs mouse only when unlocked (for drag + pos editor click)
    mainFrame:EnableMouse(not locked)

    for i = 1, 7 do
        local b = bars[i]
        if b then
            -- iconBtn: needs mouse whenever announce is enabled.
            -- Lock only blocks dragging (mainFrame), not icon clicks.
            if b.iconBtn then
                b.iconBtn:EnableMouse(canAnnounce)
            end
            -- barWrap: needs mouse only when frame is not locked
            -- (it propagates clicks to mainFrame for dragging)
            if b.barWrap then
                b.barWrap:EnableMouse(not locked)
            end
        end
    end

    -- Lock button: only visible when frame is unlocked and visible
    if _lockBtn then
        if not locked and mainFrame:IsShown() then
            _lockBtn:ClearAllPoints()
            _lockBtn:SetPoint("TOP", mainFrame, "BOTTOM", 0, -2)
            _lockBtn:Show()
        else
            _lockBtn:Hide()
        end
    end
end

------------------------------------------------------------
-- Border helper
------------------------------------------------------------
local function ApplyBackdrop(f, path, size, r, g, b, a)
    if not f then return end
    if not path or path == "" then
        f:SetBackdrop(nil)
        return
    end
    f:SetBackdrop({
        edgeFile = path,
        edgeSize = size,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropBorderColor(r, g, b, a)
end

function BIT.UI:ApplyBorderToFrame(f)
    if not f then return end
    local db   = BIT.db
    local path = db.borderTexturePath
    local size = db.borderSize or 12
    local r    = db.borderColorR or 1
    local g    = db.borderColorG or 1
    local b    = db.borderColorB or 1
    local a    = db.borderColorA or 1
    -- Use dedicated overlay frames so border always renders above StatusBar
    ApplyBackdrop(f.borderOverlay,     path, size, r, g, b, a)
    ApplyBackdrop(f.iconBorderOverlay, path, size, r, g, b, a)
end

function BIT.UI:ApplyBorderToAll()
    for i = 1, 7 do
        if bars[i] then
            self:ApplyBorderToFrame(bars[i])
        end
    end
    -- Keep attached interrupt icons in sync with border-style changes.
    -- _aiFrames is declared later in this file; guarded so load-order
    -- quirks don't break this call if the module isn't ready yet.
    if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts._ApplyBorderToAll then
        BIT.UI.AttachedInterrupts:_ApplyBorderToAll()
    end
end

------------------------------------------------------------
-- Display update (called every 0.1s)
------------------------------------------------------------

-- Match a bar by its owner name. Prefers the explicit _ownerName we stamp
-- during ShowBar (raw character name), falls back to the display-stripped
-- _lastName for forward-compat. Without this we'd miss the own bar whenever
-- the player has a custom display name set (own name differs from UnitName).
local function MatchBarByOwner(bar, playerName)
    if not bar then return false end
    if bar._ownerName then
        return bar._ownerName == playerName
    end
    if not bar._lastName then return false end
    local stripped = bar._lastName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return stripped == playerName
end

-- hide CD text while waiting for kick outcome
function BIT.UI:SetPendingKickColor(playerName)
    for i = 1, 7 do
        local bar = bars[i]
        if MatchBarByOwner(bar, playerName) then
            bar._failedKick   = false
            bar._successKick  = false
            bar._pendingColor = true
            break
        end
    end
end
function BIT.UI:FlashFailedKick(playerName)
    if not BIT.db.showFailedKick then return end
    for i = 1, 7 do
        local bar = bars[i]
        if MatchBarByOwner(bar, playerName) then
            bar._failedKick   = true
            bar._successKick  = false
            bar._pendingColor = false
            break
        end
    end
    if BIT.db.soundEnabled and (not BIT.db.soundOwnKickOnly or playerName == BIT.myName) then
        BIT.Media:PlayKickSound(BIT.db.soundKickFailed)
    end
end

-- mark own bar green on successful interrupt
function BIT.UI:MarkSuccessKick(playerName)
    if not BIT.db.showFailedKick then return end
    for i = 1, 7 do
        local bar = bars[i]
        if MatchBarByOwner(bar, playerName) then
            bar._successKick  = true
            bar._failedKick   = false
            bar._pendingColor = false
            break
        end
    end
    if BIT.db.soundEnabled and (not BIT.db.soundOwnKickOnly or playerName == BIT.myName) then
        BIT.Media:PlayKickSound(BIT.db.soundKickSuccess)
    end
end
local _col = {0, 0, 0}
local _bg  = {0, 0, 0}

-- Rotation lookup: name → position index, rebuilt when rotation changes
local _rotOrderOf    = {}
local _rotOrderDirty = true
function BIT.UI:MarkRotationDirty() _rotOrderDirty = true end

-- Reusable party sort tables
local _sortedParty       = {}
local _restoShamanEntries = {}

function BIT.UI:UpdateDisplay()
    if not BIT.ready or not shouldShowByZone then return end
    if BIT.db.hideOutOfCombat and not BIT.inCombat and not BIT.testMode then return end

    -- Attached-icon mode runs on every tick and early-outs when disabled.
    -- It's independent of the bar rendering below.
    if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Tick then
        BIT.UI.AttachedInterrupts:Tick()
    end

    local db  = BIT.db
    local now = GetTime()
    local _, barH, _, _, _, titleH = GetBarLayout()
    if IsIconOnlyMode() then titleH = 0 end
    local barIdx = 1

    -- Rebuild rotation lookup table only when dirty
    if _rotOrderDirty then
        wipe(_rotOrderOf)
        for i, nm in ipairs(BIT.rotationOrder) do
            _rotOrderOf[nm] = i
        end
        _rotOrderDirty = false
    end

    -- Helper: fill _col with bar color (no table allocation)
    local function FillBarColor(class)
        if db.useClassColors then
            local c = BIT.CLASS_COLORS[class] or { 1, 1, 1 }
            _col[1] = c[1]; _col[2] = c[2]; _col[3] = c[3]
        else
            _col[1] = db.customColorR or 0.4
            _col[2] = db.customColorG or 0.8
            _col[3] = db.customColorB or 1.0
        end
    end

    -- Helper: fill _bg with background color (no table allocation)
    local function FillBgColor(class)
        if db.useClassColors then
            local c = BIT.CLASS_COLORS[class] or { 1, 1, 1 }
            _bg[1] = c[1] * 0.25; _bg[2] = c[2] * 0.25; _bg[3] = c[3] * 0.25
        else
            _bg[1] = db.customBgColorR or 0.1
            _bg[2] = db.customBgColorG or 0.1
            _bg[3] = db.customBgColorB or 0.1
        end
    end

    -- Helper: rotation indicator color — colored divider between icon and bar
    local function ApplyRotBorder(bar, playerName)
        if not bar.rotLine then return end
        if not db.rotationEnabled or #BIT.rotationOrder == 0 then
            bar.rotLine:Hide()
            return
        end
        local idx = _rotOrderOf[playerName]
        if not idx then
            bar.rotLine:Hide()
            return
        end
        local n      = #BIT.rotationOrder
        local offset = (idx - BIT.rotationIndex) % n
        local r, g, b
        if     offset == 0 then r, g, b = 0,    1,    0
        elseif offset == 1 then r, g, b = 1,    0.85, 0
        elseif offset == 2 then r, g, b = 1,    0.45, 0
        end
        if r then
            bar.rotLine:SetColorTexture(r, g, b, 1)
            bar.rotLine:Show()
        else
            bar.rotLine:Hide()
        end
    end

    local function ApplyBar(bar, cdEnd, baseCd, isPetSpell, spellID)
        bar.spellID = spellID
        bar.cdEnd   = cdEnd
        FillBgColor(bar._class)

        if cdEnd > now then
            local rem = cdEnd - now
            -- duration can be a tainted secret value, so pcall is needed here
            if isPetSpell == false and spellID then
                local ok, apiRem = pcall(function()
                    local cdInfo = C_Spell.GetSpellCooldown(spellID)
                    if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                        local r = (cdInfo.startTime + cdInfo.duration) - now
                        return r > 0 and r or nil
                    end
                end)
                if ok and apiRem then rem = apiRem end
            end

            local sec = math.floor(rem + 0.5)

            if iconOnly then
                -- Icon Only mode: show CD countdown centered on icon, desaturate icon
                if bar._lastCdSec ~= sec and bar.iconOnlyCdText then
                    bar._lastCdSec = sec
                    bar.iconOnlyCdText:SetText(sec > 0 and tostring(sec) or "")
                end
                if bar.iconOnlyCdText then
                    bar.iconOnlyCdText:SetTextColor(1, 1, 1)
                    bar.iconOnlyCdText:Show()
                end
                bar.icon:SetDesaturated(true)
                bar.icon:SetAlpha(0.6)
            else
                -- Only update CD text when the displayed second changes
                if bar._lastCdSec ~= sec then
                    bar._lastCdSec = sec
                    bar.playerCdText:SetText(sec > 0 and tostring(sec) or "")
                end
                -- hide text while waiting for kick outcome, show with correct color once known
                local pending = bar._pendingColor
                if pending then
                    bar.playerCdText:Hide()
                else
                    if bar._failedKick then
                        bar.playerCdText:SetTextColor(1, 0.1, 0.1)
                    elseif bar._successKick then
                        bar.playerCdText:SetTextColor(0.1, 1, 0.1)
                    else
                        bar.playerCdText:SetTextColor(1, 1, 1)
                    end
                    bar.playerCdText:Show()
                end
                if not bar._cdVisible then
                    bar.partyCdText:Hide()
                    bar._cdVisible = true
                    if bar.nameText and bar.nameShortW then
                        bar.nameText:SetWidth(bar.nameShortW)
                    end
                end

                -- Update bar value directly (was OnUpdate before)
                if baseCd > 0 then
                    local val = (db.barFillMode == "FILL") and (baseCd - rem) or rem
                    bar.cdBar:SetMinMaxValues(0, baseCd)
                    bar.cdBar:SetValue(val < 0 and 0 or val)
                end
                local cdR, cdG, cdB
                if db.useClassColors then
                    cdR, cdG, cdB = _col[1], _col[2], _col[3]
                else
                    cdR = db.cdBarColorR or 0.8
                    cdG = db.cdBarColorG or 0.2
                    cdB = db.cdBarColorB or 0.2
                    if db.cdBarFade and baseCd > 0 then
                        -- t=1 → full CD (cd color), t=0 → almost ready (ready color)
                        local t = rem / baseCd
                        if t > 1 then t = 1 elseif t < 0 then t = 0 end
                        cdR = _col[1] + (cdR - _col[1]) * t
                        cdG = _col[2] + (cdG - _col[2]) * t
                        cdB = _col[3] + (cdB - _col[3]) * t
                    end
                end
                bar.cdBar:SetStatusBarColor(cdR, cdG, cdB, 0.85)
                bar.barBg:SetVertexColor(_bg[1], _bg[2], _bg[3], 0.9)
                if bar.iconBg then bar.iconBg:SetVertexColor(_bg[1]*0.7, _bg[2]*0.7, _bg[3]*0.7, 1) end
                bar.playerCdWrapper:SetAlpha(1)
            end
        else
            if iconOnly then
                -- Icon Only mode: ready state — full color icon, no text
                if bar.iconOnlyCdText then
                    bar.iconOnlyCdText:SetText("")
                    bar.iconOnlyCdText:Hide()
                end
                bar.icon:SetDesaturated(false)
                bar.icon:SetAlpha(1)
                bar._cdVisible    = false
                bar._lastCdSec    = nil
            else
                if bar._cdVisible ~= false then
                    -- state just changed to ready
                    bar.playerCdText:Hide()
                    bar.partyCdText:Show()
                    if bar.nameText then
                        bar.nameText:SetWidth(db.showReady and bar.nameShortW or bar.nameFullW)
                    end
                    bar.cdBar:SetMinMaxValues(0, 1)
                    bar.cdBar:SetValue(0)
                    bar._cdVisible    = false
                    bar._lastCdSec    = nil
                    bar._lastCdEnd    = nil
                    bar._failedKick   = false
                    bar._successKick  = false
                    bar._pendingColor = false
                end
                -- always update color/text so settings changes apply immediately
                bar.partyCdText:SetText(db.showReady and BIT.L["READY"] or "")
                bar.partyCdText:SetTextColor(
                    db.readyColorR or 0.2,
                    db.readyColorG or 1.0,
                    db.readyColorB or 0.2)
                bar.playerCdWrapper:SetAlpha(1)
                bar.barBg:SetVertexColor(_col[1], _col[2], _col[3], 0.85)
            end
        end
    end

    local iconOnly = IsIconOnlyMode()

    local function ShowBar(bar, icon, nameStr, class, cdEnd, baseCd, isPetSpell, spellID, ownerName)
        bar:Show()
        bar._class      = class
        bar._ownerName  = ownerName  -- raw character name for FlashFailedKick/MarkSuccessKick matching
        if bar._lastIcon ~= icon then
            bar.icon:SetTexture(icon)
            bar._lastIcon = icon
        end
        bar.icon:SetDesaturated(false)
        bar.icon:SetAlpha(1)
        local nameChanged = (bar._lastName ~= nameStr)
        bar._lastName = nameStr
        if iconOnly then
            -- Icon Only mode: hide bar elements, show icon + CD overlay
            bar.nameText:Hide()
            bar.partyCdText:Hide()
            bar.playerCdText:Hide()
            if bar.cdBar then bar.cdBar:Hide() end
            if bar.barBg then bar.barBg:Hide() end
            if bar.barBgSolid then bar.barBgSolid:Hide() end
            if bar.rotLine then bar.rotLine:Hide() end
        else
            if nameChanged then
                bar.nameText:SetText(nameStr)
            end
            if db.showName == false then bar.nameText:Hide() else bar.nameText:Show() end
        end
        FillBarColor(class)
        ApplyBar(bar, cdEnd, baseCd, isPetSpell, spellID)
    end

    local function AddOwnBar()
        local mySpellData = BIT.mySpellID and BIT.ALL_INTERRUPTS[BIT.mySpellID]
        if mySpellData then
            local bar     = bars[barIdx]
            local nameStr = "|cFFFFFFFF" .. BIT.GetDisplayName(BIT.myName or "?") .. "|r"
            local isPet   = BIT.myIsPetSpell or (BIT.mySpellID
                and not C_SpellBook.IsSpellInSpellBook(BIT.mySpellID, Enum.SpellBookSpellBank.Player)
                and C_SpellBook.IsSpellInSpellBook(BIT.mySpellID, Enum.SpellBookSpellBank.Pet))
            ShowBar(bar, mySpellData.icon, nameStr, BIT.myClass,
                BIT.myKickCdEnd, BIT.myBaseCd or mySpellData.cd,
                isPet and true or false, BIT.mySpellID, BIT.myName)
            ApplyRotBorder(bar, BIT.myName)
            barIdx = barIdx + 1
        end
        for ekKey, ekInfo in pairs(BIT.myExtraKicks) do
            if barIdx > 7 then break end
            local ekData = BIT.ALL_INTERRUPTS[ekKey]
            local ekIcon = ekInfo.icon or (ekData and ekData.icon)
            if ekIcon or ekData then
                local bar     = bars[barIdx]
                local nameStr = "|cFFFFFFFF" .. BIT.GetDisplayName(BIT.myName or "?") .. "|r"
                ShowBar(bar, ekIcon or ekData.icon, nameStr, BIT.myClass,
                    ekInfo.cdEnd, ekInfo.baseCd, nil, ekKey, BIT.myName)
                barIdx = barIdx + 1
            end
        end
    end

    -- Build sorted party list — reuse module-level tables to avoid GC
    wipe(_sortedParty)
    wipe(_restoShamanEntries)
    for name, info in pairs(BIT.partyAddonUsers) do
        if name ~= BIT.myName then
            local data = BIT.ALL_INTERRUPTS[info.spellID]
            if data then
                local rem   = math.max(0, info.cdEnd - now)
                local entry = { name = name, info = info, data = data, rem = rem }
                if info.spellID == 57994 and (info.baseCd or 0) >= 30 then
                    tinsert(_restoShamanEntries, entry)
                else
                    tinsert(_sortedParty, entry)
                end
            end
        end
    end
    if db.sortMode == "CD_DESC" then
        table.sort(_sortedParty, function(a, b) return a.rem > b.rem end)
    elseif db.sortMode == "CD_ASC" then
        table.sort(_sortedParty, function(a, b) return a.rem < b.rem end)
    end
    for _, e in ipairs(_restoShamanEntries) do tinsert(_sortedParty, e) end

    local function AddPartyBars()
        if db.soloMode then return end
        for _, entry in ipairs(_sortedParty) do
            if barIdx > 7 then break end
            local name, info, data = entry.name, entry.info, entry.data
            local bar     = bars[barIdx]
            local nameStr = "|cFFFFFFFF" .. BIT.GetDisplayName(name) .. "|r"
            ShowBar(bar, data.icon, nameStr, info.class,
                info.cdEnd, info.baseCd or data.cd, nil, info.spellID, name)
            ApplyRotBorder(bar, name)
            barIdx = barIdx + 1
            if info.extraKicks then
                for _, ek in ipairs(info.extraKicks) do
                    if barIdx > 7 then break end
                    local ekData = ek.spellID and BIT.ALL_INTERRUPTS[ek.spellID]
                    local ekIcon = ek.icon or (ekData and ekData.icon)
                    if ekIcon or ekData then
                        local ebar = bars[barIdx]
                        ShowBar(ebar, ekIcon or ekData.icon, nameStr, info.class,
                            ek.cdEnd, ek.baseCd, nil, ek.spellID, name)
                        barIdx = barIdx + 1
                    end
                end
            end
        end
    end

    AddOwnBar()
    AddPartyBars()

    for i = barIdx, 7 do
        local bar = bars[i]
        if bar:IsShown() then
            bar:Hide()
            bar._lastIcon  = nil
            bar._lastName  = nil
            bar._ownerName = nil
            bar._lastCdSec = nil
            bar._cdVisible = nil
        end
    end

    if not isResizing and mainFrame then
        local numVisible = barIdx - 1
        if numVisible > 0 then
            if iconOnly then
                local icoSize = db.iconOnlySize or 36
                local icoGap  = db.iconOnlySpacing or 4
                local perRow  = db.iconOnlyPerRow or 7
                local cols    = math.min(numVisible, perRow)
                local rows    = math.ceil(numVisible / perRow)
                local w = cols * icoSize + (cols - 1) * icoGap
                local h = titleH + rows * icoSize + (rows - 1) * icoGap
                mainFrame:SetSize(w, h)
            else
                local barGap = db.barGap or 0
                mainFrame:SetSize(db.frameWidth, titleH + numVisible * barH + (numVisible - 1) * barGap)
            end
        end
    end
end

------------------------------------------------------------
-- Create main frame
------------------------------------------------------------
function BIT.UI:Create()
    local db = BIT.db
    local m  = BIT.Media

    mainFrame = CreateFrame("Frame", "BliZziInterruptsFrame", UIParent)
    mainFrame:SetSize(db.frameWidth, 200)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetAlpha(db.alpha)

    -- Normal drag when NOT using Edit Mode (respects lock)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton", "RightButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if not db.locked then self:StartMoving() end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, _, _, titleH = GetBarLayout()
        local left = self:GetLeft()
        if BIT.db.growUpward then
            local bottom = self:GetBottom()
            if left and bottom then
                BIT.charDb.posXUp = left
                BIT.charDb.posYUp = bottom
            end
        else
            local top = self:GetTop()
            if left and top then
                BIT.charDb.posX = left
                BIT.charDb.posY = top - titleH
            end
        end
        -- sync position editor if open
        if _posEditor and _posEditor:IsShown() and _posEditorRefresh then
            _posEditorRefresh()
        end
    end)

    -- ── Position Editor ──────────────────────────────────────────────────
    -- Appears below the frame when clicked while unlocked.
    -- Shows X/Y editboxes + arrow buttons for pixel-perfect placement.
    _posEditor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    _posEditor:SetSize(180, 90)
    _posEditor:SetFrameStrata("DIALOG")
    _posEditor:Hide()
    _posEditor:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    _posEditor:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    _posEditor:SetBackdropBorderColor(0, 0.8, 0.8, 0.8)

    -- Helper: read current anchor position
    local function _posGetXY()
        local _, _, _, _, _, titleH = GetBarLayout()
        if BIT.db.growUpward then
            return math.floor(BIT.charDb.posXUp or mainFrame:GetLeft() or 0),
                   math.floor(BIT.charDb.posYUp or mainFrame:GetBottom() or 0)
        else
            return math.floor(BIT.charDb.posX or mainFrame:GetLeft() or 0),
                   math.floor((BIT.charDb.posY or ((mainFrame:GetTop() or 0) - titleH)) )
        end
    end

    -- Helper: apply X/Y to frame + save
    local function _posApply(x, y)
        local _, _, _, _, _, titleH = GetBarLayout()
        mainFrame:ClearAllPoints()
        if BIT.db.growUpward then
            BIT.charDb.posXUp = x
            BIT.charDb.posYUp = y
            mainFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        else
            BIT.charDb.posX = x
            BIT.charDb.posY = y
            mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y + titleH)
        end
    end

    -- X label + editbox
    local xLabel = _posEditor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xLabel:SetPoint("TOPLEFT", _posEditor, "TOPLEFT", 8, -8)
    xLabel:SetText("|cFF00DDDDX:|r")

    local xBox = CreateFrame("EditBox", nil, _posEditor, "BackdropTemplate")
    xBox:SetSize(52, 20)
    xBox:SetPoint("LEFT", xLabel, "RIGHT", 4, 0)
    xBox:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    xBox:SetBackdropColor(0.15, 0.15, 0.15, 1)
    xBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    xBox:SetAutoFocus(false)
    xBox:SetNumeric(false)
    xBox:SetMaxLetters(6)
    xBox:SetFontObject(GameFontNormal)
    xBox:SetTextInsets(4, 4, 0, 0)
    xBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then local _, y = _posGetXY(); _posApply(v, y) end
        self:ClearFocus()
    end)
    xBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Y label + editbox
    local yLabel = _posEditor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yLabel:SetPoint("LEFT", xBox, "RIGHT", 10, 0)
    yLabel:SetText("|cFF00DDDDY:|r")

    local yBox = CreateFrame("EditBox", nil, _posEditor, "BackdropTemplate")
    yBox:SetSize(52, 20)
    yBox:SetPoint("LEFT", yLabel, "RIGHT", 4, 0)
    yBox:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    yBox:SetBackdropColor(0.15, 0.15, 0.15, 1)
    yBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    yBox:SetAutoFocus(false)
    yBox:SetNumeric(false)
    yBox:SetMaxLetters(6)
    yBox:SetFontObject(GameFontNormal)
    yBox:SetTextInsets(4, 4, 0, 0)
    yBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then local x, _ = _posGetXY(); _posApply(x, v) end
        self:ClearFocus()
    end)
    yBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Refresh editboxes from current position
    function _posEditorRefresh()
        local x, y = _posGetXY()
        xBox:SetText(tostring(x))
        yBox:SetText(tostring(y))
    end

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, _posEditor, "BackdropTemplate")
    resetBtn:SetSize(60, 20)
    resetBtn:SetPoint("TOPLEFT", _posEditor, "TOPLEFT", 8, -34)
    resetBtn:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    resetBtn:SetBackdropColor(0.12, 0.12, 0.12, 1)
    resetBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    local resetLbl = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetLbl:SetAllPoints()
    resetLbl:SetText("Reset")
    resetBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0, 0.8, 0.8, 1) end)
    resetBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end)
    resetBtn:SetScript("OnClick", function()
        BIT.charDb.posX   = nil; BIT.charDb.posY   = nil
        BIT.charDb.posXUp = nil; BIT.charDb.posYUp = nil
        BIT.UI.ApplyFramePosition()
        _posEditorRefresh()
    end)

    -- Arrow buttons: direction, dx, dy
    local arrows = {
        { sym="^",  dx= 0, dy= 1, col=1, row=1 },
        { sym="v",  dx= 0, dy=-1, col=1, row=2 },
        { sym="<",  dx=-1, dy= 0, col=0, row=2 },
        { sym=">",  dx= 1, dy= 0, col=2, row=2 },
    }
    local arrowSize = 20
    local arrowOriginX = 82
    local arrowOriginY = -36

    for _, a in ipairs(arrows) do
        local btn = CreateFrame("Button", nil, _posEditor, "BackdropTemplate")
        btn:SetSize(arrowSize, arrowSize)
        btn:SetPoint("TOPLEFT", _posEditor, "TOPLEFT",
            arrowOriginX + a.col * (arrowSize + 2),
            arrowOriginY - (a.row - 1) * (arrowSize + 2))
        btn:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
        btn:SetBackdropColor(0.12, 0.12, 0.12, 1)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints()
        lbl:SetText(a.sym)
        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0, 0.8, 0.8, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end)

        -- Hold-to-repeat: fires once immediately, then repeats after 0.3s at 0.05s intervals
        local function doMove()
            local x, y = _posGetXY()
            _posApply(x + a.dx, y + a.dy)
            _posEditorRefresh()
        end
        btn:SetScript("OnClick", doMove)
    end

    -- Toggle editor on left-click while unlocked
    mainFrame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and not BIT.db.locked then
            if _posEditor:IsShown() then
                _posEditor:Hide()
            else
                _posEditorRefresh()
                -- Position editor below the main frame
                _posEditor:ClearAllPoints()
                _posEditor:SetPoint("TOP", mainFrame, "BOTTOM", 0, -4)
                _posEditor:Show()
            end
        end
    end)

    -- Hide editor when frame is hidden (e.g. out of combat)
    mainFrame:HookScript("OnHide", function()
        _posEditor:Hide()
        if _lockBtn then _lockBtn:Hide() end
    end)
    BIT.UI.HidePosEditor = function() _posEditor:Hide() end

    -- Lock button: appears below the frame when unlocked, vanishes on click
    _lockBtn = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    _lockBtn:SetSize(40, 16)
    _lockBtn:SetFrameStrata("DIALOG")
    _lockBtn:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    _lockBtn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    _lockBtn:SetBackdropBorderColor(0.6, 0.4, 0, 0.9)
    local lockLbl = _lockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockLbl:SetAllPoints()
    lockLbl:SetText("|cFFFFCC00Lock|r")
    _lockBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.7, 0, 1) end)
    _lockBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.6, 0.4, 0, 0.9) end)
    _lockBtn:SetScript("OnClick", function()
        BIT.db.locked = true
        if BIT.UI.HidePosEditor then BIT.UI.HidePosEditor() end
        BIT.UI:RebuildBars()
    end)
    _lockBtn:Hide()

    -- Background (transparent)
    local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(m.flatTexture)
    bg:SetVertexColor(0.05, 0.05, 0.05, 0)




    -- Title
    titleText = mainFrame:CreateFontString(nil, "OVERLAY")
    do
        local titleSize = (db.titleFontSize and db.titleFontSize > 0) and db.titleFontSize or 12
        m:SetFont(titleText, titleSize)
        local align     = db.titleAlign or "CENTER"
        local initTitleH = db.showTitle and 20 or 0
        if align == "LEFT" then
            titleText:SetPoint("BOTTOMLEFT",  mainFrame, "TOPLEFT",  0, -initTitleH)
        elseif align == "RIGHT" then
            titleText:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", 0, -initTitleH)
        else
            titleText:SetPoint("BOTTOM",      mainFrame, "TOP",      0, -initTitleH)
        end
    end
    titleText:SetText(BIT.L["TITLE_TEXT"])
    titleText:SetTextColor(db.titleColorR or 0, db.titleColorG or 0.867, db.titleColorB or 0.867)
    if not db.showTitle then titleText:Hide() end

    -- Position: posX/posY stored per-character in BIT.charDb.
    -- Frame TOPLEFT = bar[1] top minus titleH, so title appears above without shifting bars.
    local function ApplyFramePosition()
        local _, _, _, _, _, titleH = GetBarLayout()
        mainFrame:ClearAllPoints()
        if BIT.db.growUpward then
            if BIT.charDb.posXUp and BIT.charDb.posYUp then
                mainFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", BIT.charDb.posXUp, BIT.charDb.posYUp)
            else
                mainFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 200)
            end
        else
            if BIT.charDb.posX and BIT.charDb.posY then
                -- posY = bar[1] top; frame TOPLEFT = bar[1] top + titleH
                mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BIT.charDb.posX, BIT.charDb.posY + titleH)
            else
                mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
            end
        end
    end
    ApplyFramePosition()
    BIT.UI.ApplyFramePosition = ApplyFramePosition

    -- Register with Edit Mode via LibEditMode
    -- This lets the user move the frame via Game Menu → Edit Mode
    local libEM = LibStub and LibStub("LibEditMode", true)
    if libEM and libEM.RegisterFrame then
        pcall(function() libEM:RegisterFrame(mainFrame, "BliZzi Interrupts", db) end)
    end

    -- Expose for Config
    BIT.UI.mainFrame = mainFrame
    BIT.UI.titleText = titleText

    mainFrame:Show()
    self:RebuildBars()
end

function BIT.UI:ApplyAutoScale()
    if not mainFrame then return end
    local _, screenHeight = GetPhysicalScreenSize()
    local scale = 1.0
    if screenHeight and screenHeight > 0 then
        scale = math.max(0.6, math.min(2.0, screenHeight / 1080))
    end
    mainFrame:SetScale(scale)
    -- Re-layout bars now that effective scale is known, so pixel snapping is correct
    BIT.UI:RebuildBars()
end
------------------------------------------------------------
-- Kick Rotation Panel
------------------------------------------------------------
local rotationPanel = nil

local function GetClassColor(playerName)
    if playerName == BIT.myName then
        local c = BIT.CLASS_COLORS[BIT.myClass]
        return c and {c[1], c[2], c[3]} or {1,1,1}
    end
    local info = BIT.partyAddonUsers[playerName]
    if info and info.class then
        local c = BIT.CLASS_COLORS[info.class]
        return c and {c[1], c[2], c[3]} or {1,1,1}
    end
    return {1, 1, 1}
end

-- Adds any party members not yet in rotationOrder (never removes existing)
local function SyncPartyToRotation()
    local inOrder = {}
    for _, n in ipairs(BIT.rotationOrder) do inOrder[n] = true end
    if BIT.myName and not inOrder[BIT.myName] then
        BIT.rotationOrder[#BIT.rotationOrder+1] = BIT.myName
        inOrder[BIT.myName] = true
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local n = UnitName(u)
            if n and not inOrder[n] then
                BIT.rotationOrder[#BIT.rotationOrder+1] = n
                inOrder[n] = true
            end
        end
    end
    BIT.db.rotationOrder = BIT.rotationOrder
    _rotOrderDirty = true
end

local ROW_H    = 32
local ROW_PAD  = 6
local PANEL_W  = 260
local HDR_H    = 48

local function BuildRotationPanel()
    if not rotationPanel then return end

    -- Always add any party members not yet in the list
    SyncPartyToRotation()

    rotationPanel.rows = rotationPanel.rows or {}
    for _, rf in ipairs(rotationPanel.rows) do rf:Hide() end

    local n = #BIT.rotationOrder
    local totalH = HDR_H + n * (ROW_H + ROW_PAD) + ROW_PAD + 44
    rotationPanel:SetSize(PANEL_W, math.max(160, totalH))

    local y = -(HDR_H + ROW_PAD)

    for i = 1, n do
        local idx  = i
        local name = BIT.rotationOrder[i]
        local f    = rotationPanel.rows[idx]

        if not f then
            f = CreateFrame("Frame", nil, rotationPanel)
            f:SetHeight(ROW_H)

            -- row background
            f.bg = f:CreateTexture(nil, "BACKGROUND")
            f.bg:SetAllPoints()
            f.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)

            -- left accent bar (colored by position: green/yellow/dim)
            f.accent = f:CreateTexture(nil, "BORDER")
            f.accent:SetWidth(3)
            f.accent:SetPoint("TOPLEFT",    f, "TOPLEFT",  0, 0)
            f.accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)

            -- position number
            f.posLabel = f:CreateFontString(nil, "OVERLAY")
            f.posLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
            f.posLabel:SetPoint("LEFT", f, "LEFT", 10, 0)
            f.posLabel:SetWidth(18)
            f.posLabel:SetJustifyH("RIGHT")

            -- player name
            f.nm = f:CreateFontString(nil, "OVERLAY")
            f.nm:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            f.nm:SetPoint("LEFT", f, "LEFT", 34, 0)
            f.nm:SetWidth(PANEL_W - 34 - 58)
            f.nm:SetJustifyH("LEFT")
            f.nm:SetWordWrap(false)

            -- up button
            f.upBtn = CreateFrame("Button", nil, f)
            f.upBtn:SetSize(22, ROW_H - 4)
            f.upBtn:SetPoint("RIGHT", f, "RIGHT", -26, 0)
            f.upBtn.tex = f.upBtn:CreateTexture(nil, "ARTWORK")
            f.upBtn.tex:SetAllPoints()
            f.upBtn.tex:SetColorTexture(0.25, 0.25, 0.25, 1)
            f.upBtn.lbl = f.upBtn:CreateFontString(nil, "OVERLAY")
            f.upBtn.lbl:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
            f.upBtn.lbl:SetAllPoints()
            f.upBtn.lbl:SetJustifyH("CENTER")
            f.upBtn.lbl:SetText("|cFFCCCCCC^|r")
            f.upBtn:SetScript("OnEnter", function(self) self.tex:SetColorTexture(0.4, 0.4, 0.4, 1) end)
            f.upBtn:SetScript("OnLeave", function(self) self.tex:SetColorTexture(0.25, 0.25, 0.25, 1) end)

            -- down button
            f.downBtn = CreateFrame("Button", nil, f)
            f.downBtn:SetSize(22, ROW_H - 4)
            f.downBtn:SetPoint("RIGHT", f, "RIGHT", -2, 0)
            f.downBtn.tex = f.downBtn:CreateTexture(nil, "ARTWORK")
            f.downBtn.tex:SetAllPoints()
            f.downBtn.tex:SetColorTexture(0.25, 0.25, 0.25, 1)
            f.downBtn.lbl = f.downBtn:CreateFontString(nil, "OVERLAY")
            f.downBtn.lbl:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
            f.downBtn.lbl:SetAllPoints()
            f.downBtn.lbl:SetJustifyH("CENTER")
            f.downBtn.lbl:SetText("|cFFCCCCCCv|r")
            f.downBtn:SetScript("OnEnter", function(self) self.tex:SetColorTexture(0.4, 0.4, 0.4, 1) end)
            f.downBtn:SetScript("OnLeave", function(self) self.tex:SetColorTexture(0.25, 0.25, 0.25, 1) end)

            rotationPanel.rows[idx] = f
        end

        f:ClearAllPoints()
        f:SetPoint("TOPLEFT",  rotationPanel, "TOPLEFT",  ROW_PAD, y)
        f:SetPoint("TOPRIGHT", rotationPanel, "TOPRIGHT", -ROW_PAD, y)

        -- accent color: offset from rotationIndex — 0=green, 1=yellow, 2=orange, rest=dim
        local n = #BIT.rotationOrder
        local offset = n > 0 and (idx - BIT.rotationIndex) % n or 0
        if     offset == 0 then f.accent:SetColorTexture(0,    1,    0,    1)
        elseif offset == 1 then f.accent:SetColorTexture(1,    0.85, 0,    1)
        elseif offset == 2 then f.accent:SetColorTexture(1,    0.45, 0,    1)
        else                    f.accent:SetColorTexture(0.35, 0.35, 0.35, 1) end

        -- position label: gold if current turn
        local isCurrent = (idx == BIT.rotationIndex) and BIT.db.rotationEnabled
        if isCurrent then
            f.posLabel:SetText("|cFFFFD100" .. idx .. ".|r")
        else
            f.posLabel:SetText("|cFF888888" .. idx .. ".|r")
        end

        -- player name with class color
        local cc = GetClassColor(name)
        f.nm:SetText(string.format("|cFF%02X%02X%02X%s|r",
            cc[1]*255, cc[2]*255, cc[3]*255, BIT.GetDisplayName(name)))

        -- up/down visibility
        if idx > 1 then
            f.upBtn:Show()
            f.upBtn:SetScript("OnClick", function()
                BIT.rotationOrder[idx], BIT.rotationOrder[idx-1] = BIT.rotationOrder[idx-1], BIT.rotationOrder[idx]
                if     BIT.rotationIndex == idx   then BIT.rotationIndex = idx - 1
                elseif BIT.rotationIndex == idx-1 then BIT.rotationIndex = idx end
                BIT.Rotation.index   = BIT.rotationIndex
                BIT.db.rotationOrder = BIT.rotationOrder
                BIT.db.rotationIndex = BIT.rotationIndex
                _rotOrderDirty = true
                BuildRotationPanel()
            end)
        else f.upBtn:Hide() end

        if idx < n then
            f.downBtn:Show()
            f.downBtn:SetScript("OnClick", function()
                BIT.rotationOrder[idx], BIT.rotationOrder[idx+1] = BIT.rotationOrder[idx+1], BIT.rotationOrder[idx]
                if     BIT.rotationIndex == idx   then BIT.rotationIndex = idx + 1
                elseif BIT.rotationIndex == idx+1 then BIT.rotationIndex = idx end
                BIT.Rotation.index   = BIT.rotationIndex
                BIT.db.rotationOrder = BIT.rotationOrder
                BIT.db.rotationIndex = BIT.rotationIndex
                _rotOrderDirty = true
                BuildRotationPanel()
            end)
        else f.downBtn:Hide() end

        f:Show()
        y = y - (ROW_H + ROW_PAD)
    end
end

function BIT.UI:ShowRotationPanel()
    if not rotationPanel then
        rotationPanel = CreateFrame("Frame", "BITRotationPanel", UIParent, "BackdropTemplate")
        rotationPanel:SetSize(PANEL_W, 320)
        rotationPanel:SetPoint("CENTER")
        rotationPanel:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        rotationPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        rotationPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        rotationPanel:SetMovable(true)
        rotationPanel:EnableMouse(true)
        rotationPanel:RegisterForDrag("LeftButton")
        rotationPanel:SetScript("OnDragStart", rotationPanel.StartMoving)
        rotationPanel:SetScript("OnDragStop",  rotationPanel.StopMovingOrSizing)
        rotationPanel:SetClampedToScreen(true)
        rotationPanel:SetFrameStrata("DIALOG")
        rotationPanel:SetFrameLevel(200)
        rotationPanel:Hide()  -- start hidden so first toggle shows it

        -- Header background
        local hdrBg = rotationPanel:CreateTexture(nil, "BACKGROUND", nil, 1)
        hdrBg:SetColorTexture(0.04, 0.04, 0.04, 1)
        hdrBg:SetPoint("TOPLEFT",  rotationPanel, "TOPLEFT",  1, -1)
        hdrBg:SetPoint("TOPRIGHT", rotationPanel, "TOPRIGHT", -1, -1)
        hdrBg:SetHeight(HDR_H - 1)

        -- Cyan accent line under header
        local hdrLine = rotationPanel:CreateTexture(nil, "BORDER")
        hdrLine:SetColorTexture(0, 0.87, 0.87, 0.8)
        hdrLine:SetHeight(1)
        hdrLine:SetPoint("TOPLEFT",  rotationPanel, "TOPLEFT",  1,  -(HDR_H))
        hdrLine:SetPoint("TOPRIGHT", rotationPanel, "TOPRIGHT", -1, -(HDR_H))

        -- Title
        local title = rotationPanel:CreateFontString(nil, "OVERLAY")
        title:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        title:SetText("|cFF00DDDD" .. (BIT.L["ROT_TITLE"] or "Kick Rotation") .. "|r")
        title:SetPoint("TOP", rotationPanel, "TOP", 0, -(HDR_H / 2) + 6)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, rotationPanel)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", rotationPanel, "TOPRIGHT", -4, -4)
        local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
        closeTex:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        closeTex:SetText("|cFFFF4444x|r")
        closeTex:SetAllPoints()
        closeTex:SetJustifyH("CENTER")
        closeBtn:SetScript("OnClick", function() rotationPanel:Hide() end)

        -- Bottom divider
        local botLine = rotationPanel:CreateTexture(nil, "BORDER")
        botLine:SetColorTexture(0.3, 0.3, 0.3, 1)
        botLine:SetHeight(1)
        botLine:SetPoint("BOTTOMLEFT",  rotationPanel, "BOTTOMLEFT",  1, 38)
        botLine:SetPoint("BOTTOMRIGHT", rotationPanel, "BOTTOMRIGHT", -1, 38)

        -- Helper: creates a styled button matching the addon theme
        local function MakeStyledBtn(label, w, h)
            local btn = CreateFrame("Button", nil, rotationPanel)
            btn:SetSize(w, h)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.10, 0.06, 0.06, 1)
            btn.bg = bg

            local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            border:SetAllPoints()
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            border:SetBackdropBorderColor(0, 0.87, 0.87, 0.8)
            btn.border = border

            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            lbl:SetText("|cFF00DDDD" .. label .. "|r")
            lbl:SetAllPoints()
            lbl:SetJustifyH("CENTER")
            btn.lbl = lbl

            btn:SetScript("OnEnter", function()
                bg:SetColorTexture(0.05, 0.18, 0.18, 1)
                border:SetBackdropBorderColor(0, 1, 1, 1)
            end)
            btn:SetScript("OnLeave", function()
                bg:SetColorTexture(0.10, 0.06, 0.06, 1)
                border:SetBackdropBorderColor(0, 0.87, 0.87, 0.8)
            end)
            btn:SetScript("OnMouseDown", function()
                bg:SetColorTexture(0.02, 0.10, 0.10, 1)
            end)
            btn:SetScript("OnMouseUp", function()
                bg:SetColorTexture(0.05, 0.18, 0.18, 1)
            end)
            return btn
        end

        -- Three equal buttons across the bottom (78px each, 4px gap, 8px margins)
        local resetBtn = MakeStyledBtn(BIT.L["ROT_BTN_RESET"] or "Reset", 78, 26)
        resetBtn:SetPoint("BOTTOMLEFT", rotationPanel, "BOTTOMLEFT", 8, 8)
        resetBtn:SetScript("OnClick", function()
            BIT.rotationOrder    = {}
            BIT.rotationIndex    = 1
            BIT.Rotation.order   = BIT.rotationOrder
            BIT.Rotation.index   = 1
            BIT.db.rotationOrder = BIT.rotationOrder
            BIT.db.rotationIndex = BIT.rotationIndex
            BuildRotationPanel()
        end)

        local refreshBtn = MakeStyledBtn(BIT.L["ROT_BTN_REFRESH"] or "Refresh", 78, 26)
        refreshBtn:SetPoint("BOTTOMLEFT", rotationPanel, "BOTTOMLEFT", 90, 8)  -- 8+78+4
        refreshBtn:SetScript("OnClick", function()
            SyncPartyToRotation()
            BuildRotationPanel()
        end)

        local syncBtn = MakeStyledBtn(BIT.L["ROT_BTN_SYNC"] or "Sync Party", 78, 26)
        syncBtn:SetPoint("BOTTOMLEFT", rotationPanel, "BOTTOMLEFT", 172, 8)  -- 8+78+4+78+4
        syncBtn:SetScript("OnClick", function()
            BIT.db.rotationOrder = BIT.rotationOrder
            BIT.db.rotationIndex = BIT.rotationIndex
            BIT.BroadcastRotation()
            print(BIT.L["ROT_SYNCED"] or "|cFF00DDDD[BliZzi Interrupts]|r Rotation synced to party.")
        end)
    end

    BuildRotationPanel()
    if rotationPanel:IsShown() then rotationPanel:Hide() else rotationPanel:Show() end
end

------------------------------------------------------------
-- Attached Interrupt Icons
--   Alternative display mode for the interrupt tracker. When active, the
--   main bars window is hidden and each party member gets their own
--   interrupt-spell icon attached next to their unit frame.
--   The Blizzard/ElvUI/Cell/Grid2/Danders frame provider detection is
--   shared with SyncCD (via BIT.SyncCD:GetPartyUnitFrame).
------------------------------------------------------------
BIT.UI.AttachedInterrupts = BIT.UI.AttachedInterrupts or {}
local AI = BIT.UI.AttachedInterrupts
local _aiFrames = {}  -- unit → { frame, icon, cooldown, text, _parent, memberName, spellID, baseCd, _lastCdEnd }

local AI_POS = {
    RIGHT  = { point = "LEFT",   relPoint = "RIGHT",  ox =  4, oy =  0 },
    LEFT   = { point = "RIGHT",  relPoint = "LEFT",   ox = -4, oy =  0 },
    TOP    = { point = "BOTTOM", relPoint = "TOP",    ox =  0, oy =  4 },
    BOTTOM = { point = "TOP",    relPoint = "BOTTOM", ox =  0, oy = -4 },
}

local function AI_GetParent(unit)
    if BIT.SyncCD and BIT.SyncCD.GetPartyUnitFrame then
        local provider = BIT.db and BIT.db.interruptAttachFrameProvider or "AUTO"
        return BIT.SyncCD:GetPartyUnitFrame(unit, provider)
    end
    return nil
end

local function AI_HideUnit(unit)
    local ctx = _aiFrames[unit]
    if ctx and ctx.frame then ctx.frame:Hide() end
end

local function AI_HideAll()
    for unit in pairs(_aiFrames) do AI_HideUnit(unit) end
end

-- Pick the interrupt spell + icon for a member. Uses BIT.Self for the local
-- player (the local player is NOT in BIT.Registry — that table only contains
-- party members). Returns: spellID, cd, texture
local function AI_ResolveSpell(memberName, unit)
    if unit == "player" then
        local sid = BIT.Self and BIT.Self.spellID
        if sid and sid > 0 then
            local data = BIT.ALL_INTERRUPTS and BIT.ALL_INTERRUPTS[sid]
            local tex  = data and data.icon
                         or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
            local cd   = (BIT.Self and BIT.Self.cachedCd) or (BIT.Self and BIT.Self.baseCd)
                         or (data and data.cd) or 15
            return sid, cd, tex
        end
        -- Secondary fallback: class default (should rarely be needed after FindInterrupt runs).
        local _, cls = UnitClass("player")
        local def = cls and BIT.CLASS_INTERRUPTS and BIT.CLASS_INTERRUPTS[cls]
        if def and def.id then
            local data = BIT.ALL_INTERRUPTS and BIT.ALL_INTERRUPTS[def.id]
            local tex  = data and data.icon
                         or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(def.id))
            return def.id, def.cd or 15, tex
        end
        return nil
    end
    local entry = BIT.Registry and BIT.Registry:Get(memberName)
    if entry and entry.spellID and entry.spellID > 0 then
        local data = BIT.ALL_INTERRUPTS and BIT.ALL_INTERRUPTS[entry.spellID]
        local tex  = data and data.icon
                     or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellID))
        local cd   = entry.baseCd or (data and data.cd) or 15
        return entry.spellID, cd, tex
    end
    return nil
end

-- Resolve the current cdEnd for an attached-icon context.
-- • Own player: BIT.Self.kickCdEnd (main kick) or extraKicks[spellID].cdEnd,
--   falling back to C_Spell.GetSpellCooldown for talent CDR accuracy.
-- • Party member: Registry entry's cdEnd (set by HandlePartyCast).
local function AI_ResolveCdEnd(ctx, unit, now)
    if unit == "player" then
        local self_ = BIT.Self
        if not self_ then return 0 end
        local cdEnd = 0
        if self_.extraKicks and self_.extraKicks[ctx.spellID]
           and self_.extraKicks[ctx.spellID].cdEnd then
            cdEnd = self_.extraKicks[ctx.spellID].cdEnd
        elseif self_.spellID == ctx.spellID and self_.kickCdEnd then
            cdEnd = self_.kickCdEnd
        end
        -- Refine with the live API — catches talent CDR (Seasoned Soldier,
        -- Coldthirst, etc.) that shortens the CD after the start time.
        -- Every access + compare on the returned struct is pcall-wrapped
        -- because the fields can be tainted secret numbers in 12.x.
        local okC, apiEnd = pcall(function()
            local info = C_Spell.GetSpellCooldown(ctx.spellID)
            if not info then return nil end
            local st, du = info.startTime, info.duration
            if not st or not du then return nil end
            if du <= 0 then return nil end
            return st + du
        end)
        if okC and apiEnd then
            local okCmp = pcall(function()
                if apiEnd > now then
                    if cdEnd == 0 or apiEnd < cdEnd then cdEnd = apiEnd end
                end
            end)
            -- If the compare itself threw (tainted apiEnd), silently fall back
            -- to the already-computed cdEnd from Self.kickCdEnd.
            if not okCmp then apiEnd = nil end
        end
        return cdEnd
    end
    local entry = BIT.Registry and BIT.Registry:Get(ctx.memberName)
    return (entry and entry.cdEnd) or 0
end

local function AI_BuildOrUpdateIcon(unit, memberName)
    local parent = AI_GetParent(unit)
    if not parent then
        AI_HideUnit(unit)
        return
    end
    local spellID, baseCd, tex = AI_ResolveSpell(memberName, unit)
    if not spellID or not tex then
        AI_HideUnit(unit)
        return
    end

    local db   = BIT.db
    local size = db.interruptAttachIconSize or 32
    local pos  = db.interruptAttachPos or "RIGHT"
    local ox   = db.interruptAttachOffsetX or 0
    local oy   = db.interruptAttachOffsetY or 0
    local cSz  = db.interruptAttachCounterSize or 14
    local cfg  = AI_POS[pos] or AI_POS.RIGHT

    local ctx = _aiFrames[unit]
    local needsNewFrame = not (ctx and ctx.frame and ctx._parent == parent)
    if needsNewFrame then
        if ctx and ctx.frame then
            ctx.frame:Hide()
            ctx.frame:SetParent(nil)
        end
        ctx = { _parent = parent }
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints(f)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Cooldown swipe overlay (Blizzard cooldown frame handles the sweep)
        f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cooldown:SetAllPoints(f)
        f.cooldown:SetDrawEdge(false)
        f.cooldown:SetDrawBling(false)
        f.cooldown:SetHideCountdownNumbers(true)  -- we draw our own text
        -- Border overlay (renders above cooldown swipe so it stays visible)
        local bo = CreateFrame("Frame", nil, f, "BackdropTemplate")
        bo:SetAllPoints(f)
        bo:SetFrameLevel(f:GetFrameLevel() + 5)
        bo:EnableMouse(false)
        f.iconBorderOverlay = bo
        f.borderOverlay     = bo  -- alias so ApplyBorderToFrame works
        -- Counter text (above everything)
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
        ctx.frame    = f
        _aiFrames[unit] = ctx
    end

    local f = ctx.frame
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint(cfg.point, parent, cfg.relPoint, cfg.ox + ox, cfg.oy + oy)
    f.icon:SetTexture(tex)
    -- Apply the same border style as the main bars.  ApplyBorderToFrame
    -- calls ApplyBackdrop on f.borderOverlay AND f.iconBorderOverlay — we
    -- aliased them to the same frame above, so a single backdrop draws.
    if BIT.UI.ApplyBorderToFrame then
        BIT.UI:ApplyBorderToFrame(f)
    end

    if BIT.Media and BIT.Media.SetFont then
        BIT.Media:SetFont(f.text, cSz)
    else
        f.text:SetFont(STANDARD_TEXT_FONT, cSz, "OUTLINE")
    end
    f.text:SetTextColor(1, 1, 1)

    ctx.memberName = memberName
    ctx.spellID    = spellID
    ctx.baseCd     = baseCd
    ctx._lastCdEnd = nil  -- force a fresh swipe on the next tick
    f:Show()
end

-- Called when party composition, settings or the display mode changes.
function AI:Rebuild()
    if not BIT.db or BIT.db.interruptDisplayMode ~= "ATTACHED" then
        AI_HideAll()
        return
    end
    -- Own icon is controlled by the "Show Own Icon on Player Frame" toggle
    -- in the Attached Display section.
    if BIT.db.interruptAttachShowOwn and BIT.myName then
        AI_BuildOrUpdateIcon("player", BIT.myName)
    else
        AI_HideUnit("player")
    end
    -- Solo Mode: only the own icon is drawn, party members are skipped.
    -- Mirror the behaviour of AddPartyBars() in the classic bars renderer.
    if BIT.db.soloMode then
        for i = 1, 4 do AI_HideUnit("party" .. i) end
        return
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local n = UnitName(u)
            if n then AI_BuildOrUpdateIcon(u, n) end
        else
            AI_HideUnit(u)
        end
    end
end

-- Cheap tick (called from the 10Hz update loop). Only touches frames that
-- are currently shown. Skips instantly when not in ATTACHED mode.
function AI:Tick()
    if not BIT.db or BIT.db.interruptDisplayMode ~= "ATTACHED" then return end
    local now   = GetTime()
    local desat = BIT.db.interruptAttachDesaturateOnCD and true or false
    for unit, ctx in pairs(_aiFrames) do
        local f = ctx.frame
        if f and f:IsShown() then
            local cdEnd = AI_ResolveCdEnd(ctx, unit, now)
            if cdEnd and cdEnd > now then
                local rem = cdEnd - now
                f.text:SetText(tostring(math.floor(rem + 0.5)))
                f.icon:SetDesaturated(desat)
                if ctx._lastCdEnd ~= cdEnd then
                    ctx._lastCdEnd = cdEnd
                    -- Derive the swipe start time. For party: use Registry's
                    -- lastKickAt; for self: cdEnd - baseCd; as a final fallback
                    -- trust the base CD. All numeric comparisons are wrapped
                    -- because durations/timestamps from the Blizzard APIs can
                    -- be secret values in 12.x (comparison throws).
                    local baseCd = ctx.baseCd or 15
                    if unit ~= "player" then
                        local entry = BIT.Registry and BIT.Registry:Get(ctx.memberName)
                        if entry and entry.lastKickAt then
                            local okD, derived = pcall(function()
                                local v = cdEnd - entry.lastKickAt
                                return v > 0 and v or nil
                            end)
                            if okD and derived then baseCd = derived end
                        end
                    else
                        -- For own player, prefer the live API's duration. Fields
                        -- on the returned SpellCooldownInfo can be tainted too,
                        -- so every read + compare is pcall-guarded.
                        local okC, info = pcall(C_Spell.GetSpellCooldown, ctx.spellID)
                        if okC and info then
                            local okDur, dur = pcall(function()
                                local d = info.duration
                                return (d and d > 0) and d or nil
                            end)
                            if okDur and dur then baseCd = dur end
                        end
                    end
                    local okCmp, isNeg = pcall(function() return baseCd <= 0 end)
                    if not okCmp or isNeg then baseCd = ctx.baseCd or 15 end
                    -- SetCooldown may propagate taint; wrap to keep the tick loop alive.
                    pcall(function()
                        f.cooldown:SetCooldown(cdEnd - baseCd, baseCd)
                    end)
                end
            else
                if ctx._lastCdEnd ~= 0 then
                    ctx._lastCdEnd = 0
                    f.cooldown:Clear()
                end
                f.text:SetText("")
                f.icon:SetDesaturated(false)
            end
        end
    end
end

-- Called from the main UI rebuild path to ensure the standalone bars window
-- is hidden when we're in ATTACHED mode (and visible otherwise).
function AI:ApplyModeToMainFrame(frame)
    if not frame then return end
    if BIT.db and BIT.db.interruptDisplayMode == "ATTACHED" then
        frame:Hide()
    end
end

-- Reapply border style to every attached icon. Hooked into BIT.UI:ApplyBorderToAll
-- so border changes from the Size & Font settings page propagate here too.
function AI:_ApplyBorderToAll()
    if not BIT.UI.ApplyBorderToFrame then return end
    for _, ctx in pairs(_aiFrames) do
        if ctx.frame then
            BIT.UI:ApplyBorderToFrame(ctx.frame)
        end
    end
end
