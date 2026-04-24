------------------------------------------------------------
-- BliZzi Interrupts — Custom Settings Window
-- Modern dark UI with sidebar navigation, toggles,
-- color pickers, custom dropdowns.  Opened via /blizzi.
------------------------------------------------------------
local _, BIT_NS = ...
local L   -- set in Init (locale not ready at parse time)

BIT.SettingsUI = BIT.SettingsUI or {}

------------------------------------------------------------
-- ── Style constants ──────────────────────────────────────
------------------------------------------------------------
local ACCENT    = { 0, 0.75, 0.85 }      -- cyan
local ACCENT2   = { 0.90, 0.55, 0.10 }   -- orange
local BG        = { 0.06, 0.06, 0.08 }   -- main bg
local SIDEBAR   = { 0.09, 0.09, 0.11 }   -- sidebar bg
local WIDGET_BG = { 0.12, 0.12, 0.14 }   -- input bg
local BORDER    = { 0.20, 0.20, 0.24 }   -- subtle border
local TEXT      = { 0.90, 0.90, 0.92 }   -- primary text
local TEXT_DIM  = { 0.55, 0.55, 0.60 }   -- secondary text
local WHITE8    = "Interface\\Buttons\\WHITE8X8"

local SIDEBAR_W   = 180
local CONTENT_PAD = 16
local WIDGET_H    = 28
local SECTION_H   = 32
local GAP         = 6
local WIN_W       = 780
local WIN_H       = 560

------------------------------------------------------------
-- ── Helpers ──────────────────────────────────────────────
------------------------------------------------------------
local mainFrame, contentScroll, contentChild, sidebarBtns
local activePage = nil
local pages = {}

local function RGB(t) return t[1], t[2], t[3] end

local function ApplyFont(fs, size, flags)
    local font = BIT.Media and BIT.Media.font or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(font, size, flags or "")
end

--- Locale-safe string lookup.  Uses rawget so the metatable
--- fallback (which returns the key itself) is bypassed.
local function LS(key, fb)
    if not L then return fb end
    local v = rawget(L, key)
    return v or fb
end

--- Build dropdown option list from a BIT.Media:GetAvailable*() list.
--- Each entry has .name (display string) used as both value and label.
local function MediaOpts(getListFn)
    local opts = {}
    if BIT.Media and getListFn then
        for _, e in ipairs(getListFn()) do
            opts[#opts+1] = { value = e.name, label = e.name }
        end
    end
    return opts
end

local function MakeBg(f, r, g, b, a)
    f:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
                     insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(r, g, b, a or 0.95)
    f:SetBackdropBorderColor(RGB(BORDER))
end

local function Refresh()
    if activePage and pages[activePage] and pages[activePage].refresh then
        pages[activePage].refresh()
    end
    -- Rebuild the interrupt tracker bars (handles size, font, color, layout changes)
    if BIT.UI then
        if BIT.UI.RebuildBars then BIT.UI:RebuildBars() end
        if BIT.UI.CheckZoneVisibility then BIT.UI:CheckZoneVisibility() end
    end
    -- Rebuild party CD tracker (Rebuild() debounces internally at 50ms)
    if BIT.SyncCD and BIT.SyncCD.Rebuild then
        BIT.SyncCD:Rebuild()
    end
    -- Apply frame scale
    if BIT.UI and BIT.UI.mainFrame and BIT.db then
        BIT.UI.mainFrame:SetScale((BIT.db.frameScale or 100) / 100)
    end
end

------------------------------------------------------------
-- ── Widget Factory ───────────────────────────────────────
------------------------------------------------------------

-- Reusable pool for dropdown popups
local dropdownPopup

------------------------------------------------------------
-- Toggle (modern switch)
------------------------------------------------------------
local function CreateToggle(parent, label, getter, setter, indent, disabled)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, WIDGET_H)

    -- track
    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    track:SetSize(36, 18)
    track:SetPoint("LEFT", indent or 0, 0)
    MakeBg(track, 0.18, 0.18, 0.20, 1)

    -- thumb
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(RGB(ACCENT))

    local function UpdateVisual()
        if disabled then
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
            thumb:SetColorTexture(0.3, 0.3, 0.3)
            track:SetBackdropColor(0.12, 0.12, 0.13, 1)
            return
        end
        local on = getter()
        if on then
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 20, 0)
            thumb:SetColorTexture(RGB(ACCENT))
            track:SetBackdropColor(ACCENT[1] * 0.3, ACCENT[2] * 0.3, ACCENT[3] * 0.3, 1)
        else
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
            thumb:SetColorTexture(0.45, 0.45, 0.48)
            track:SetBackdropColor(0.18, 0.18, 0.20, 1)
        end
    end
    UpdateVisual()

    -- click
    if not disabled then
        track:EnableMouse(true)
        track:SetScript("OnMouseDown", function()
            setter(not getter())
            UpdateVisual()
            Refresh()
        end)
    end

    -- label
    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, 12)
    lbl:SetPoint("LEFT", track, "RIGHT", 8, 0)
    if disabled then
        lbl:SetTextColor(0.4, 0.4, 0.4)
    else
        lbl:SetTextColor(RGB(TEXT))
    end
    lbl:SetText(label)

    -- "Under Construction" hint for disabled toggles
    if disabled then
        local hint = f:CreateFontString(nil, "OVERLAY")
        ApplyFont(hint, 10)
        hint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        hint:SetJustifyH("RIGHT")
        hint:SetText("|cffff8800Under Construction|r")
    end

    f._update = UpdateVisual
    return f
end

------------------------------------------------------------
-- Slider
------------------------------------------------------------
local function CreateSlider(parent, label, minV, maxV, step, getter, setter, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, WIDGET_H + 4)

    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, 11)
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetTextColor(RGB(TEXT_DIM))
    lbl:SetText(label)

    -- value text
    local valTxt = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(valTxt, 11)
    valTxt:SetPoint("TOPRIGHT", 0, 0)
    valTxt:SetTextColor(RGB(TEXT))

    -- slider
    local sl = CreateFrame("Slider", nil, f, "MinimalSliderTemplate")
    sl:SetSize(f:GetWidth() - 60, 14)
    sl:SetPoint("BOTTOMLEFT", 0, 0)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    sl:SetValue(getter())

    -- edit box (right of slider)
    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    eb:SetSize(50, 18)
    eb:SetPoint("LEFT", sl, "RIGHT", 6, 0)
    MakeBg(eb, RGB(WIDGET_BG))
    eb:SetAutoFocus(false)
    ApplyFont(eb, 11)
    eb:SetTextColor(RGB(TEXT))
    eb:SetJustifyH("CENTER")
    local initVal = getter()
    eb:SetText(fmt and fmt(initVal) or tostring(math.floor(initVal + 0.5)))

    local _lastApplied
    local function UpdateVal(v)
        v = math.max(minV, math.min(maxV, v))
        if v == _lastApplied then return end
        _lastApplied = v
        setter(v)
        sl:SetValue(v)
        eb:SetText(fmt and fmt(v) or tostring(math.floor(v + 0.5)))
        valTxt:SetText("")
        Refresh()
    end

    sl:SetScript("OnValueChanged", function(_, v)
        UpdateVal(v)
    end)
    -- Live update during drag: OnValueChanged may not fire on every frame,
    -- so poll the slider value while mouse is held down.
    sl:HookScript("OnMouseDown", function()
        sl:SetScript("OnUpdate", function()
            UpdateVal(sl:GetValue())
        end)
    end)
    sl:HookScript("OnMouseUp", function()
        sl:SetScript("OnUpdate", nil)
        UpdateVal(sl:GetValue())
    end)
    eb:SetScript("OnEnterPressed", function(self)
        local raw = self:GetText():gsub("[^%d%.%-]", "")  -- strip px, %, etc.
        local n = tonumber(raw)
        if n then UpdateVal(n) end
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f._update = function()
        sl:SetValue(getter())
        eb:SetText(fmt and fmt(getter()) or tostring(math.floor(getter() + 0.5)))
    end
    return f
end

------------------------------------------------------------
-- Dropdown (custom popup)
------------------------------------------------------------
local function CreateDropdown(parent, label, options, getter, setter)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, WIDGET_H)

    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, 11)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetTextColor(RGB(TEXT_DIM))
    lbl:SetText(label)

    -- button
    local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
    btn:SetSize(180, 22)
    btn:SetPoint("RIGHT", 0, 0)
    MakeBg(btn, RGB(WIDGET_BG))

    local btnText = btn:CreateFontString(nil, "OVERLAY")
    ApplyFont(btnText, 11)
    btnText:SetPoint("LEFT", 6, 0)
    btnText:SetTextColor(RGB(TEXT))

    local arrow = btn:CreateFontString(nil, "OVERLAY")
    ApplyFont(arrow, 10)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTextColor(RGB(TEXT_DIM))
    arrow:SetText("v")

    local function UpdateText()
        local cur = getter()
        for _, opt in ipairs(options) do
            if opt.value == cur then
                btnText:SetText(opt.label)
                return
            end
        end
        btnText:SetText(tostring(cur))
    end
    UpdateText()

    btn:SetScript("OnClick", function()
        -- close existing
        if dropdownPopup and dropdownPopup:IsShown() then
            dropdownPopup:Hide()
            return
        end
        if not dropdownPopup then
            dropdownPopup = CreateFrame("Frame", "BIT_DropdownPopup", UIParent, "BackdropTemplate")
            dropdownPopup:SetFrameStrata("TOOLTIP")
            dropdownPopup:SetFrameLevel(200)
            dropdownPopup:SetClampedToScreen(true)
            dropdownPopup.items = {}

            -- scroll frame inside popup
            local sf = CreateFrame("ScrollFrame", nil, dropdownPopup, "UIPanelScrollFrameTemplate")
            sf:SetPoint("TOPLEFT", 2, -2)
            sf:SetPoint("BOTTOMRIGHT", -20, 2)
            dropdownPopup.scrollFrame = sf

            local child = CreateFrame("Frame", nil, sf)
            child:SetWidth(1) -- set dynamically
            child:SetHeight(1)
            sf:SetScrollChild(child)
            dropdownPopup.scrollChild = child

            -- mouse wheel on the popup itself
            dropdownPopup:EnableMouseWheel(true)
            dropdownPopup:SetScript("OnMouseWheel", function(_, delta)
                local cur = sf:GetVerticalScroll()
                local max = sf:GetVerticalScrollRange()
                sf:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 22 * 3)))
            end)
        end
        local popup = dropdownPopup
        local child = popup.scrollChild
        local sf    = popup.scrollFrame
        -- clear old
        for _, item in ipairs(popup.items) do item:Hide() end
        wipe(popup.items)

        local itemH   = 22
        local maxShow = 10
        local w       = btn:GetWidth()
        local visH    = math.min(#options, maxShow) * itemH + 4
        popup:ClearAllPoints()
        popup:SetSize(w, visH)
        popup:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        MakeBg(popup, 0.10, 0.10, 0.12, 0.98)
        popup:SetBackdropBorderColor(RGB(ACCENT))

        child:SetWidth(w - (#options > maxShow and 22 or 4))
        child:SetHeight(#options * itemH)

        -- hide scrollbar when not needed
        if sf.ScrollBar then
            if #options > maxShow then sf.ScrollBar:Show() else sf.ScrollBar:Hide() end
        end

        for i, opt in ipairs(options) do
            local item = CreateFrame("Button", nil, child)
            item:SetSize(child:GetWidth(), itemH)
            item:SetPoint("TOPLEFT", 0, -(i - 1) * itemH)
            local itxt = item:CreateFontString(nil, "OVERLAY")
            ApplyFont(itxt, 11)
            itxt:SetPoint("LEFT", 6, 0)
            itxt:SetTextColor(RGB(TEXT))
            itxt:SetText(opt.label)
            -- highlight current selection
            if opt.value == getter() then
                itxt:SetTextColor(RGB(ACCENT))
            end
            local hl = item:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
            item:SetScript("OnClick", function()
                setter(opt.value)
                UpdateText()
                popup:Hide()
                Refresh()
            end)
            popup.items[i] = item
        end
        sf:SetVerticalScroll(0)
        popup:Show()
        -- close on outside click
        popup:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                self:Hide()
            end
        end)
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(RGB(ACCENT))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(RGB(BORDER))
    end)

    f._update = UpdateText
    return f
end

------------------------------------------------------------
-- Color Swatch (opens Blizzard ColorPicker)
------------------------------------------------------------
local function CreateColorSwatch(parent, label, getR, getG, getB, setColor, getA, setA)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, WIDGET_H)

    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, 11)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetTextColor(RGB(TEXT_DIM))
    lbl:SetText(label)

    -- swatch
    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(60, 20)
    sw:SetPoint("RIGHT", 0, 0)
    sw:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    sw:SetBackdropBorderColor(0.3, 0.3, 0.3)

    -- hex text
    local hex = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(hex, 10)
    hex:SetPoint("RIGHT", sw, "LEFT", -8, 0)
    hex:SetTextColor(RGB(TEXT_DIM))

    local function UpdateSwatch()
        local r, g, b = getR(), getG(), getB()
        sw:SetBackdropColor(r, g, b, 1)
        hex:SetText(string.format("#%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    end
    UpdateSwatch()

    sw:SetScript("OnClick", function()
        local info = {}
        info.r, info.g, info.b = getR(), getG(), getB()
        info.hasOpacity = (getA ~= nil)
        info.opacity = getA and (1 - getA()) or 1
        info.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            setColor(r, g, b)
            if setA and info.hasOpacity then
                setA(1 - ColorPickerFrame:GetColorAlpha())
            end
            UpdateSwatch()
            Refresh()
        end
        info.cancelFunc = function(prev)
            setColor(prev.r, prev.g, prev.b)
            if setA and prev.a then setA(prev.a) end
            UpdateSwatch()
            Refresh()
        end
        info.opacityFunc = info.swatchFunc
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    sw:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
    sw:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3) end)

    f._update = UpdateSwatch
    return f
end

------------------------------------------------------------
-- Section Header (collapsible)
------------------------------------------------------------
local function CreateSectionHeader(parent, label, stateKey)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, SECTION_H)

    local line = f:CreateTexture(nil, "BACKGROUND")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3)

    local arrowFs = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(arrowFs, 10)
    arrowFs:SetPoint("LEFT", 0, 0)
    arrowFs:SetTextColor(RGB(ACCENT))

    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, 13, "OUTLINE")
    lbl:SetPoint("LEFT", 16, 0)
    lbl:SetTextColor(RGB(TEXT))
    lbl:SetText(label)

    f._expanded = (BIT.db and BIT.db.sectionExpanded and BIT.db.sectionExpanded[stateKey] ~= false) or true
    f._children = {}
    f._stateKey = stateKey

    local function UpdateArrow()
        arrowFs:SetText(f._expanded and "v" or ">")
    end
    UpdateArrow()

    f:SetScript("OnClick", function()
        f._expanded = not f._expanded
        if BIT.db and BIT.db.sectionExpanded then
            BIT.db.sectionExpanded[f._stateKey] = f._expanded
        end
        UpdateArrow()
        -- When re-expanding, run every `_update` callback first so that
        -- `_dynamic` widgets reclaim their correct visibility. Collapsing
        -- hides children via `w:Hide()`, which wipes the state that the
        -- _update closures normally maintain — without this pass, those
        -- widgets would stay hidden in `IsShown()` terms and the layout
        -- would continue skipping them.
        if f._expanded and pages[activePage] and pages[activePage].refresh then
            pages[activePage].refresh()
        end
        if pages[activePage] and pages[activePage].layout then
            pages[activePage].layout()
        end
    end)

    f:SetScript("OnEnter", function() lbl:SetTextColor(RGB(ACCENT)) end)
    f:SetScript("OnLeave", function() lbl:SetTextColor(RGB(TEXT)) end)

    return f
end

------------------------------------------------------------
-- Label (info line)
------------------------------------------------------------
local function CreateLabel(parent, text, size, col)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, (size or 11) + 4)
    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, size or 11)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetPoint("RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(col and col[1] or TEXT_DIM[1], col and col[2] or TEXT_DIM[2], col and col[3] or TEXT_DIM[3])
    lbl:SetText(text)
    lbl:SetWordWrap(true)
    -- adjust height to text
    f:SetScript("OnShow", function()
        f:SetHeight(math.max((size or 11) + 4, lbl:GetStringHeight() + 4))
    end)
    return f
end

------------------------------------------------------------
-- Spell Filter Panel (tabbed list with checkboxes + icons)
-- spells: flat list of { id, label, class, className }
-- getter(sid): returns true if spell is enabled
-- setter(sid, enabled): sets spell enabled/disabled
-- tabs: optional { { label, spells }, ... } for multi-tab mode
------------------------------------------------------------
local function CreateSpellFilterPanel(parent, spells, getter, setter, tabs)
    local PANEL_W  = parent:GetWidth() - CONTENT_PAD * 2
    local PANEL_H  = 320
    local ROW_H    = 24
    local TAB_H    = 26
    local BTN_H    = 28
    local ICON_SZ  = 20

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
    MakeBg(panel, 0.08, 0.08, 0.10, 1)

    -- Tab data: if tabs provided, use them; otherwise single-tab with all spells
    local tabDefs = tabs or { { label = "All", spells = spells } }
    local activeTab = 1
    local checkboxes = {}  -- all checkbox references for Check/Uncheck All

    -- ── Tab bar ──────────────────────────────────────────────
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", 4, -4)
    tabBar:SetPoint("TOPRIGHT", -4, -4)
    tabBar:SetHeight(TAB_H)

    local tabBtns = {}
    local tabW = math.floor((PANEL_W - 8) / #tabDefs)

    -- ── Scroll area ──────────────────────────────────────────
    local listTop = TAB_H + 8
    local listH   = PANEL_H - listTop - BTN_H - 12

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -listTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, BTN_H + 10)

    -- Style the scrollbar
    local sb = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if sb then
        sb:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -16)
        sb:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 16)
    end

    local listChild = CreateFrame("Frame", nil, scrollFrame)
    listChild:SetWidth(PANEL_W - 32)
    scrollFrame:SetScrollChild(listChild)

    -- ── Build rows for a spell list ──────────────────────────
    local function PopulateList(spellList)
        -- Clear existing rows
        for _, cb in ipairs(checkboxes) do
            cb:GetParent():Hide()
            cb:GetParent():SetParent(nil)
        end
        wipe(checkboxes)

        local yOff = 0
        for i, s in ipairs(spellList) do
            local row = CreateFrame("Frame", nil, listChild)
            row:SetSize(listChild:GetWidth(), ROW_H)
            row:SetPoint("TOPLEFT", 0, -yOff)

            -- Alternating row bg
            if i % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0.03)
            end

            -- Highlight on hover
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(RGB(ACCENT))
            hl:SetAlpha(0.08)

            -- Checkbox
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("LEFT", 4, 0)
            cb._spellId = s.id

            if s.notTrackable then
                -- Not trackable: permanently unchecked and disabled
                cb:SetChecked(false)
                cb:Disable()
                cb:SetAlpha(0.35)
            else
                cb:SetChecked(getter(s.id))
                cb:SetScript("OnClick", function(self)
                    local checked = self:GetChecked()
                    setter(s.id, checked)
                end)
                checkboxes[#checkboxes+1] = cb
            end

            -- Spell icon
            local iconID = C_Spell.GetSpellTexture(s.id)
            if iconID then
                local ico = row:CreateTexture(nil, "ARTWORK")
                ico:SetSize(ICON_SZ, ICON_SZ)
                ico:SetPoint("LEFT", cb, "RIGHT", 4, 0)
                ico:SetTexture(iconID)
                ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if s.notTrackable then ico:SetDesaturated(true) end

                -- Icon border
                local icoBorder = row:CreateTexture(nil, "OVERLAY")
                icoBorder:SetSize(ICON_SZ + 2, ICON_SZ + 2)
                icoBorder:SetPoint("CENTER", ico)
                icoBorder:SetColorTexture(0, 0, 0, 0)
                -- Thin black edge via nested frame
                local icoBg = CreateFrame("Frame", nil, row, "BackdropTemplate")
                icoBg:SetSize(ICON_SZ + 2, ICON_SZ + 2)
                icoBg:SetPoint("CENTER", ico)
                icoBg:SetBackdrop({ edgeFile = WHITE8, edgeSize = 1 })
                icoBg:SetBackdropBorderColor(0, 0, 0, 0.8)
            end

            -- Spell name + class
            local nameStr = row:CreateFontString(nil, "OVERLAY")
            ApplyFont(nameStr, 11)
            nameStr:SetPoint("LEFT", cb, "RIGHT", ICON_SZ + 10, 0)
            nameStr:SetJustifyH("LEFT")

            if s.notTrackable then
                -- Show name (dimmed) + "Aktuell nicht trackbar" hint on the right
                local cc = BIT.CLASS_COLORS and BIT.CLASS_COLORS[s.class]
                local cr, cg, cb2 = cc and cc[1] or 0.6, cc and cc[2] or 0.6, cc and cc[3] or 0.6
                local classHex = string.format("%02x%02x%02x",
                    math.floor(cr * 255), math.floor(cg * 255), math.floor(cb2 * 255))
                nameStr:SetText(s.label .. "  |cff" .. classHex .. "(" .. (s.className or s.class) .. ")|r")
                nameStr:SetTextColor(0.5, 0.5, 0.5)

                local hintStr = row:CreateFontString(nil, "OVERLAY")
                ApplyFont(hintStr, 10)
                hintStr:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                hintStr:SetText("|cffff8800" .. LS("NOT_TRACKABLE", "Currently not trackable") .. "|r")
                hintStr:SetJustifyH("RIGHT")

                -- No mouse interaction for not-trackable rows
                row:EnableMouse(false)
            else
                nameStr:SetPoint("RIGHT", row, "RIGHT", -6, 0)

                -- Class-colored class name suffix
                local cc = BIT.CLASS_COLORS and BIT.CLASS_COLORS[s.class]
                local cr, cg, cb2 = cc and cc[1] or 0.6, cc and cc[2] or 0.6, cc and cc[3] or 0.6
                local classHex = string.format("%02x%02x%02x",
                    math.floor(cr * 255), math.floor(cg * 255), math.floor(cb2 * 255))
                nameStr:SetText(s.label .. "  |cff" .. classHex .. "(" .. (s.className or s.class) .. ")|r")
                nameStr:SetTextColor(RGB(TEXT))

                -- Click row to toggle
                row:EnableMouse(true)
                row:SetScript("OnMouseDown", function()
                    cb:SetChecked(not cb:GetChecked())
                    setter(s.id, cb:GetChecked())
                end)

                -- Spell tooltip on hover
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(s.id)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            yOff = yOff + ROW_H
        end

        listChild:SetHeight(math.max(1, yOff))
        scrollFrame:SetVerticalScroll(0)
    end

    -- ── Tab button styling + switching ───────────────────────
    local function SetActiveTab(idx)
        activeTab = idx
        PopulateList(tabDefs[idx].spells)
        for ti, btn in ipairs(tabBtns) do
            if ti == idx then
                btn.bg:SetColorTexture(RGB(ACCENT))
                btn.bg:SetAlpha(0.25)
                btn.text:SetTextColor(RGB(ACCENT))
            else
                btn.bg:SetColorTexture(0.15, 0.15, 0.18, 1)
                btn.bg:SetAlpha(1)
                btn.text:SetTextColor(RGB(TEXT_DIM))
            end
        end
    end

    for ti, td in ipairs(tabDefs) do
        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(tabW - 2, TAB_H - 2)
        btn:SetPoint("LEFT", (ti - 1) * tabW + 1, 0)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        btn.bg = bg

        local txt = btn:CreateFontString(nil, "OVERLAY")
        ApplyFont(txt, 11, "OUTLINE")
        txt:SetPoint("CENTER")
        txt:SetText(td.label)
        btn.text = txt

        btn:SetScript("OnClick", function() SetActiveTab(ti) end)
        btn:SetScript("OnEnter", function()
            if ti ~= activeTab then btn.bg:SetColorTexture(0.2, 0.2, 0.24, 1) end
        end)
        btn:SetScript("OnLeave", function()
            if ti ~= activeTab then btn.bg:SetColorTexture(0.15, 0.15, 0.18, 1) end
        end)

        tabBtns[ti] = btn
    end

    -- ── Bottom buttons: Check All / Uncheck All ──────────────
    local btnW = math.floor((PANEL_W - 16) / 2)

    local function MakeBottomBtn(label, xOff, color, onClick)
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(btnW, BTN_H)
        btn:SetPoint("BOTTOMLEFT", 6 + xOff, 6)
        MakeBg(btn, 0.14, 0.14, 0.16, 1)

        local txt = btn:CreateFontString(nil, "OVERLAY")
        ApplyFont(txt, 11)
        txt:SetPoint("CENTER")
        txt:SetTextColor(color[1], color[2], color[3])
        txt:SetText(label)

        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.24, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.14, 0.14, 0.16, 1)
        end)
        return btn
    end

    MakeBottomBtn("Check All", 0, { 0.3, 0.9, 0.3 }, function()
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(true)
            setter(cb._spellId, true)
        end
    end)

    MakeBottomBtn("Uncheck All", btnW + 4, { 0.9, 0.3, 0.3 }, function()
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(false)
            setter(cb._spellId, false)
        end
    end)

    -- Init first tab
    SetActiveTab(1)

    return panel
end

------------------------------------------------------------
-- EditBox (text input)
------------------------------------------------------------
local function CreateEditBox(parent, label, getter, setter, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth() - CONTENT_PAD * 2, WIDGET_H)

    local lbl = f:CreateFontString(nil, "OVERLAY")
    ApplyFont(lbl, 11)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetTextColor(RGB(TEXT_DIM))
    lbl:SetText(label)

    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    eb:SetSize(width or 160, 20)
    eb:SetPoint("RIGHT", 0, 0)
    MakeBg(eb, RGB(WIDGET_BG))
    eb:SetAutoFocus(false)
    ApplyFont(eb, 11)
    eb:SetTextColor(RGB(TEXT))
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetText(getter() or "")
    eb:SetScript("OnEnterPressed", function(self)
        setter(self:GetText())
        self:ClearFocus()
        Refresh()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f._update = function() eb:SetText(getter() or "") end
    return f
end

------------------------------------------------------------
-- ── Main Frame ───────────────────────────────────────────
------------------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "BIT_SettingsFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(WIN_W, WIN_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)

    -- backdrop with glow
    mainFrame:SetBackdrop({
        bgFile = WHITE8,
        edgeFile = WHITE8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    mainFrame:SetBackdropColor(RGB(BG))
    mainFrame:SetBackdropBorderColor(ACCENT[1] * 0.5, ACCENT[2] * 0.5, ACCENT[3] * 0.5, 0.8)

    -- outer glow line
    local glow = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", -1, 1)
    glow:SetPoint("BOTTOMRIGHT", 1, -1)
    glow:SetBackdrop({ edgeFile = WHITE8, edgeSize = 2 })
    glow:SetBackdropBorderColor(ACCENT[1] * 0.25, ACCENT[2] * 0.25, ACCENT[3] * 0.25, 0.5)

    -- ── Title bar ────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetHeight(36)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.08, 0.08, 0.10, 1)

    local titleLine = titleBar:CreateTexture(nil, "ARTWORK")
    titleLine:SetHeight(1)
    titleLine:SetPoint("BOTTOMLEFT")
    titleLine:SetPoint("BOTTOMRIGHT")
    titleLine:SetColorTexture(ACCENT[1] * 0.4, ACCENT[2] * 0.4, ACCENT[3] * 0.4, 0.8)

    -- logo icon
    local logo = titleBar:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", 8, 0)
    logo:SetTexture("Interface\\AddOns\\BliZzi_Interrupts\\Media\\icon")
    logo:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    ApplyFont(titleText, 14, "OUTLINE")
    titleText:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    titleText:SetText("|cff0091edBliZzi|r|cffffa300Interrupts|r  |cff666666Settings|r")

    -- version
    local verText = titleBar:CreateFontString(nil, "OVERLAY")
    ApplyFont(verText, 10)
    verText:SetPoint("RIGHT", -40, 0)
    verText:SetTextColor(RGB(TEXT_DIM))
    verText:SetText("v" .. (BIT.VERSION or "?"))

    -- close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -4, 0)
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY")
    ApplyFont(closeX, 16)
    closeX:SetPoint("CENTER")
    closeX:SetText("X")
    closeX:SetTextColor(0.6, 0.6, 0.6)
    closeBtn:SetScript("OnEnter", function() closeX:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeX:SetTextColor(0.6, 0.6, 0.6) end)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- ── Sidebar ──────────────────────────────────────────
    local sidebar = CreateFrame("Frame", nil, mainFrame)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", 0, -36)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)

    local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(RGB(SIDEBAR))

    local sbLine = sidebar:CreateTexture(nil, "ARTWORK")
    sbLine:SetWidth(1)
    sbLine:SetPoint("TOPRIGHT", 0, 0)
    sbLine:SetPoint("BOTTOMRIGHT", 0, 0)
    sbLine:SetColorTexture(RGB(BORDER))

    mainFrame._sidebar = sidebar
    sidebarBtns = {}

    -- ── Social links (bottom of sidebar) ─────────────────
    local function CreateSocialLink(parent, yOff, iconPath, text, color, url)
        local linkBtn = CreateFrame("Button", nil, parent)
        linkBtn:SetSize(SIDEBAR_W - 2, 24)
        linkBtn:SetPoint("BOTTOMLEFT", 1, yOff)

        local ico = linkBtn:CreateTexture(nil, "ARTWORK")
        ico:SetSize(16, 16)
        ico:SetPoint("LEFT", 12, 0)
        ico:SetTexture(iconPath)

        local lbl = linkBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(lbl, 11)
        lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        lbl:SetTextColor(color[1], color[2], color[3], 0.7)
        lbl:SetText(text)

        linkBtn:SetScript("OnEnter", function()
            lbl:SetTextColor(color[1], color[2], color[3], 1)
            GameTooltip:SetOwner(linkBtn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(url, 1, 1, 1)
            GameTooltip:Show()
        end)
        linkBtn:SetScript("OnLeave", function()
            lbl:SetTextColor(color[1], color[2], color[3], 0.7)
            GameTooltip:Hide()
        end)

        return linkBtn
    end

    -- Separator line above links
    local linkSep = sidebar:CreateTexture(nil, "ARTWORK")
    linkSep:SetHeight(1)
    linkSep:SetPoint("BOTTOMLEFT", 12, 54)
    linkSep:SetPoint("BOTTOMRIGHT", -12, 54)
    linkSep:SetColorTexture(RGB(BORDER))

    CreateSocialLink(sidebar, 28,
        "Interface\\AddOns\\BliZzi_Interrupts\\Media\\twitch",
        "twitch.tv/BliZzi1337",
        { 0.57, 0.27, 1.0 },  -- Twitch purple
        "twitch.tv/BliZzi1337")

    CreateSocialLink(sidebar, 6,
        "Interface\\AddOns\\BliZzi_Interrupts\\Media\\discord",
        "discord.gg/BliZzi1337",
        { 0.35, 0.40, 0.95 },  -- Discord blurple
        "discord.gg/BliZzi1337")

    -- ── Content area ─────────────────────────────────────
    local contentArea = CreateFrame("Frame", nil, mainFrame)
    contentArea:SetPoint("TOPLEFT", SIDEBAR_W + 1, -36)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 0)

    contentScroll = CreateFrame("ScrollFrame", nil, contentArea, "UIPanelScrollFrameTemplate")
    contentScroll:SetPoint("TOPLEFT", 0, 0)
    contentScroll:SetPoint("BOTTOMRIGHT", -24, 0)

    contentChild = CreateFrame("Frame", nil, contentScroll)
    contentChild:SetWidth(contentArea:GetWidth() - 24)
    contentChild:SetHeight(1) -- auto-resized
    contentScroll:SetScrollChild(contentChild)

    -- style scrollbar
    local sb = contentScroll.ScrollBar
    if sb then
        sb:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -4, -18)
        sb:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -4, 18)
    end

    -- ESC to close
    tinsert(UISpecialFrames, "BIT_SettingsFrame")

    -- When settings close, re-check fade state so hideOutOfCombat kicks in
    mainFrame:SetScript("OnHide", function()
        if BIT.UI and BIT.UI.CheckZoneVisibility then
            BIT.UI:CheckZoneVisibility()
        end
    end)

    mainFrame:Hide()
end

------------------------------------------------------------
-- ── Sidebar Button ───────────────────────────────────────
------------------------------------------------------------
local function CreateSidebarBtn(idx, label, iconPath)
    local sidebar = mainFrame._sidebar
    local btn = CreateFrame("Button", nil, sidebar)
    btn:SetSize(SIDEBAR_W - 2, 32)
    btn:SetPoint("TOPLEFT", 1, -(idx - 1) * 33 - 8)

    -- active indicator (cyan left line)
    local indicator = btn:CreateTexture(nil, "ARTWORK")
    indicator:SetWidth(3)
    indicator:SetPoint("TOPLEFT", 0, 0)
    indicator:SetPoint("BOTTOMLEFT", 0, 0)
    indicator:SetColorTexture(RGB(ACCENT))
    indicator:Hide()
    btn._indicator = indicator

    -- bg highlight
    local bgHl = btn:CreateTexture(nil, "BACKGROUND")
    bgHl:SetAllPoints()
    bgHl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.08)
    bgHl:Hide()
    btn._bgHl = bgHl

    -- icon (optional)
    if iconPath then
        local ico = btn:CreateTexture(nil, "OVERLAY")
        ico:SetSize(16, 16)
        ico:SetPoint("LEFT", 12, 0)
        ico:SetTexture(iconPath)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local text = btn:CreateFontString(nil, "OVERLAY")
    ApplyFont(text, 12)
    text:SetPoint("LEFT", iconPath and 34 or 12, 0)
    text:SetTextColor(RGB(TEXT_DIM))
    text:SetText(label)
    btn._text = text

    btn:SetScript("OnEnter", function()
        if activePage ~= label then
            bgHl:Show()
            text:SetTextColor(RGB(TEXT))
        end
    end)
    btn:SetScript("OnLeave", function()
        if activePage ~= label then
            bgHl:Hide()
            text:SetTextColor(RGB(TEXT_DIM))
        end
    end)
    btn:SetScript("OnClick", function()
        BIT.SettingsUI:ShowPage(label)
    end)

    sidebarBtns[label] = btn
    return btn
end

------------------------------------------------------------
-- ── Page System ──────────────────────────────────────────
------------------------------------------------------------
local function LayoutWidgets(widgetList)
    local y = -CONTENT_PAD
    local currentSection = nil
    for _, w in ipairs(widgetList) do
        if w._stateKey then
            -- Section header. Supports `_dynamic` + `_update` the same way
            -- child widgets do: if the update callback hid the header,
            -- children of this section are collapsed to zero height too.
            currentSection = w
            if w._dynamic and not w:IsShown() then
                -- Entire section hidden — no layout slot, no gap.
            else
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", contentChild, "TOPLEFT", CONTENT_PAD, y)
                w:Show()
                y = y - SECTION_H - 2
            end
        elseif currentSection then
            -- child of a section
            local sectionHidden = currentSection._dynamic and not currentSection:IsShown()
            if sectionHidden then
                -- Parent section is hidden → hide child entirely, no gap.
                w:Hide()
            elseif currentSection._expanded then
                if w._dynamic and not w:IsShown() then
                    -- conditional widget hidden by _update — skip, no gap
                else
                    w:ClearAllPoints()
                    w:SetPoint("TOPLEFT", contentChild, "TOPLEFT", CONTENT_PAD, y)
                    if not w._dynamic then w:Show() end
                    local wh = w:GetHeight()
                    y = y - wh - (wh > 0 and GAP or 0)
                end
            else
                w:Hide()
            end
        else
            -- no section yet — just place it
            if w._dynamic and not w:IsShown() then
                -- conditional widget hidden — skip, no gap
            else
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", contentChild, "TOPLEFT", CONTENT_PAD, y)
                if not w._dynamic then w:Show() end
                local wh = w:GetHeight()
                y = y - wh - (wh > 0 and GAP or 0)
            end
        end
    end
    contentChild:SetHeight(math.abs(y) + 20)
end

local function RegisterPage(name, buildFunc)
    pages[name] = { build = buildFunc, widgets = nil }
end

------------------------------------------------------------
-- ── Category: General ────────────────────────────────────
------------------------------------------------------------
local function BuildGeneral()
    local w = {}
    local p = contentChild

    -- General
    w[#w+1] = CreateSectionHeader(p, "General", "sui_gen_general")
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_WELCOME", "Show Welcome Message"),
        function() return BIT.db.showWelcome end,
        function(v) BIT.db.showWelcome = v end)

    -- Announce
    w[#w+1] = CreateSectionHeader(p, "Announce", "sui_gen_announce")
    w[#w+1] = CreateToggle(p, LS("CB_CLICK_ANNOUNCE", "Click to Announce Interrupt"),
        function() return false end, function() end, nil, true)
    w[#w+1] = CreateToggle(p, LS("CB_SYNC_CD_CLICK_ANNOUNCE", "Click on icon to post Party CD status"),
        function() return false end, function() end, nil, true)
    w[#w+1] = CreateToggle(p, LS("CB_ANTI_SPAM", "Anti-Spam"),
        function() return false end, function() end, nil, true)

    -- Language
    w[#w+1] = CreateSectionHeader(p, LS("SEC_LANGUAGE", "Language"), "sui_gen_lang")
    w[#w+1] = CreateDropdown(p, LS("SEC_LANGUAGE", "Language"),
        { { value = "auto",  label = "Auto" },
          { value = "enUS",  label = "English" },
          { value = "deDE",  label = "Deutsch" },
          { value = "frFR",  label = "Francais" },
          { value = "esES",  label = "Espanol" },
          { value = "ruRU",  label = "Russian" },
          { value = "tlhTLH", label = "tlhIngan" } },
        function() return BIT.db.language or "auto" end,
        function(v) BIT.db.language = v; if BIT.ApplyLocale then BIT:ApplyLocale() end end)

    -- Custom Name
    w[#w+1] = CreateSectionHeader(p, "Custom Name", "sui_gen_cnames")
    w[#w+1] = CreateToggle(p, "Show Custom Names",
        function() return BIT.db.showCustomNames end,
        function(v) BIT.db.showCustomNames = v end)
    -- Per-character nickname (stored in BIT.charDb.myCustomName)
    w[#w+1] = CreateEditBox(p, LS("CUSTOM_NAMES_NICK_CHAR", "Character Nickname"),
        function() return (BIT.charDb and BIT.charDb.myCustomName) or "" end,
        function(v)
            if not BIT.charDb then return end
            BIT.charDb.myCustomName = v
            if BIT.Self and BIT.Self.BroadcastHello then BIT.Self:BroadcastHello() end
        end)
    -- Global override: use the same nickname on every character
    w[#w+1] = CreateToggle(p, LS("CUSTOM_NAMES_USE_GLOBAL", "Use Global Nickname (overrides per-character)"),
        function() return BIT.db.useGlobalCustomName end,
        function(v)
            BIT.db.useGlobalCustomName = v
            if BIT.Self and BIT.Self.BroadcastHello then BIT.Self:BroadcastHello() end
        end)
    w[#w+1] = CreateEditBox(p, LS("CUSTOM_NAMES_NICK_GLOBAL", "Global Nickname"),
        function() return BIT.db.globalCustomName or "" end,
        function(v)
            BIT.db.globalCustomName = v
            if BIT.db.useGlobalCustomName and BIT.Self and BIT.Self.BroadcastHello then
                BIT.Self:BroadcastHello()
            end
        end)

    -- Minimap Button
    w[#w+1] = CreateSectionHeader(p, "Minimap", "sui_gen_minimap")
    w[#w+1] = CreateToggle(p, "Show Minimap Button",
        function()
            local iconDB = BliZziInterruptsMinimapDB
            return not (iconDB and iconDB.hide)
        end,
        function(v)
            local ldbi = LibStub and LibStub("LibDBIcon-1.0", true)
            if ldbi then
                if not BliZziInterruptsMinimapDB then BliZziInterruptsMinimapDB = {} end
                BliZziInterruptsMinimapDB.hide = not v
                if v then ldbi:Show("BliZziInterrupts")
                else ldbi:Hide("BliZziInterrupts") end
            end
        end)

    return w
end

------------------------------------------------------------
-- ── Category: Interrupt Tracker ──────────────────────────
------------------------------------------------------------
local function BuildInterrupts()
    local w = {}
    local p = contentChild

    -- General
    w[#w+1] = CreateSectionHeader(p, "General", "sui_int_gen")
    w[#w+1] = CreateToggle(p, LS("SEC_TEST_MODE", "Test Mode"),
        function() return BIT.testMode end,
        function(v) if v then BIT:StartTestMode() else BIT:StopTestMode() end end)
    w[#w+1] = CreateToggle(p, LS("SEC_SOLO_MODE", "Solo Mode") .. " |cFF888888(" .. LS("SEC_SOLO_MODE_HINT", "only your own interrupt is tracked") .. ")|r",
        function() return BIT.db.soloMode end,
        function(v)
            BIT.db.soloMode = v
            if BIT.UI.UpdateDisplay then BIT.UI:UpdateDisplay() end
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end)
    w[#w+1] = CreateToggle(p, LS("CB_HIDE_OUT_OF_COMBAT", "Hide Out of Combat"),
        function() return BIT.db.hideOutOfCombat end,
        function(v) BIT.db.hideOutOfCombat = v end)
    w[#w+1] = CreateToggle(p, LS("ROT_ENABLE", "Enable Kick Rotation"),
        function() return BIT.db.rotationEnabled end,
        function(v) BIT.db.rotationEnabled = v end)
    w[#w+1] = CreateSlider(p, LS("SL_OPACITY", "Opacity"), 10, 100, 5,
        function() return (BIT.db.alpha or 1) * 100 end,
        function(v) BIT.db.alpha = v / 100 end,
        function(v) return math.floor(v) .. "%" end)

    -- Display mode selector + mode-scoped bar-window options
    w[#w+1] = CreateSectionHeader(p, "Display Mode", "sui_int_displaymode")

    -- Forward declarations so the dropdown setter can re-evaluate the
    -- mode-scoped widgets on change and trigger a page re-layout.
    local lockToggle, growToggle, iconPosDD, barFillDD, sortDD
    local function _syncBarsOnlyVisibility()
        local bars = (BIT.db.interruptDisplayMode or "BARS") == "BARS"
        local setVis = function(wd)
            if not wd then return end
            if bars then wd:Show() else wd:Hide() end
        end
        setVis(lockToggle)
        setVis(growToggle)
        setVis(iconPosDD)
        setVis(barFillDD)
        setVis(sortDD)
        if pages and pages[activePage] and pages[activePage].layout then
            pages[activePage].layout()
        end
    end

    -- Forward declaration: the Attached-Display sync closure is defined
    -- later in this function (after the section is built). Calling it via
    -- a local upvalue that gets assigned before the first layout pass.
    local _syncAttachedVisibility = function() end  -- replaced below

    w[#w+1] = CreateDropdown(p, "Display Mode",
        { { value = "BARS",     label = "Bars / Window" },
          { value = "ATTACHED", label = "Attached to Unit Frames" } },
        function() return BIT.db.interruptDisplayMode or "BARS" end,
        function(v)
            BIT.db.interruptDisplayMode = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
            if BIT.UI.CheckZoneVisibility then BIT.UI:CheckZoneVisibility(true) end
            _syncBarsOnlyVisibility()
            _syncAttachedVisibility()
        end)

    -- Bars/Window-only options: Lock Position + Grow Upward. These belong
    -- to the classic bars renderer and make no sense for the attached
    -- per-member icons, so they are hidden when mode is "ATTACHED".
    lockToggle = CreateToggle(p, LS("CB_LOCK_POSITION", "Lock Position"),
        function() return BIT.db.locked end,
        function(v) BIT.db.locked = v end)
    lockToggle._dynamic = true
    lockToggle._update  = _syncBarsOnlyVisibility
    w[#w+1] = lockToggle

    growToggle = CreateToggle(p, LS("CB_GROW_UPWARD", "Grow Upward"),
        function() return BIT.db.growUpward end,
        function(v) BIT.db.growUpward = v end)
    growToggle._dynamic = true
    growToggle._update  = _syncBarsOnlyVisibility
    w[#w+1] = growToggle

    iconPosDD = CreateDropdown(p, LS("SEC_ICON_POSITION", "Icon Position"),
        { { value = "LEFT",  label = "Left" },
          { value = "RIGHT", label = "Right" } },
        function() return BIT.db.iconSide or "LEFT" end,
        function(v) BIT.db.iconSide = v end)
    iconPosDD._dynamic = true
    iconPosDD._update  = _syncBarsOnlyVisibility
    w[#w+1] = iconPosDD

    barFillDD = CreateDropdown(p, LS("SEC_BAR_FILL", "Bar Fill Mode"),
        { { value = "DRAIN", label = "Drain" },
          { value = "FILL",  label = "Fill" } },
        function() return BIT.db.barFillMode or "DRAIN" end,
        function(v) BIT.db.barFillMode = v end)
    barFillDD._dynamic = true
    barFillDD._update  = _syncBarsOnlyVisibility
    w[#w+1] = barFillDD

    sortDD = CreateDropdown(p, LS("SEC_SORT_ORDER", "Sort Order"),
        { { value = "NONE",    label = "None" },
          { value = "CD_ASC",  label = "CD Ascending" },
          { value = "CD_DESC", label = "CD Descending" } },
        function() return BIT.db.sortMode or "NONE" end,
        function(v) BIT.db.sortMode = v end)
    sortDD._dynamic = true
    sortDD._update  = _syncBarsOnlyVisibility
    w[#w+1] = sortDD

    -- Apply initial visibility right after creation so the first layout
    -- pass already honors the current display mode.
    _syncBarsOnlyVisibility()

    -- Attached-mode widgets. All of these live directly under the existing
    -- "Display Mode" section header (no separate section of their own), are
    -- marked _dynamic, and hide away when the user is in Bars/Window mode.
    -- `_syncAttachedOnlyVisibility` owns the show/hide logic and is invoked
    -- by the Display Mode dropdown via the forward-declared
    -- `_syncAttachedVisibility` upvalue above.
    local attachedWidgets = {}  -- collect references for the visibility updater
    local function _syncAttachedOnlyVisibility()
        local attached = (BIT.db.interruptDisplayMode or "BARS") == "ATTACHED"
        for _, wd in ipairs(attachedWidgets) do
            if attached then wd:Show() else wd:Hide() end
        end
        if pages and pages[activePage] and pages[activePage].layout then
            pages[activePage].layout()
        end
    end
    _syncAttachedVisibility = _syncAttachedOnlyVisibility  -- wire forward-decl

    -- Helper: register a widget into both the page widget list and the
    -- local attachedWidgets group, stamping it as _dynamic with the right
    -- _update callback so a full page re-layout respects its visibility.
    local function registerAttached(wd)
        wd._dynamic = true
        wd._update  = _syncAttachedOnlyVisibility
        attachedWidgets[#attachedWidgets + 1] = wd
        w[#w + 1] = wd
    end

    -- All attached-display widgets live directly under the "Display Mode"
    -- section (no separate "Attached Display" header). They appear only
    -- when the Display Mode dropdown is set to "Attached to Unit Frames".
    -- Frame Provider (reuses the SyncCD provider-detection list)
    local attachProviderOpts = (BIT.SyncCD and BIT.SyncCD.GetAvailableProviders)
        and BIT.SyncCD:GetAvailableProviders()
        or  { { value = "AUTO", label = "Auto Detect" }, { value = "BLIZZARD", label = "Blizzard" } }
    registerAttached(CreateDropdown(p, "Attach to Frames",
        attachProviderOpts,
        function() return BIT.db.interruptAttachFrameProvider or "AUTO" end,
        function(v)
            BIT.db.interruptAttachFrameProvider = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end))
    registerAttached(CreateDropdown(p, "Attach Position",
        { { value = "LEFT",   label = "Left" },
          { value = "RIGHT",  label = "Right" },
          { value = "TOP",    label = "Top" },
          { value = "BOTTOM", label = "Bottom" } },
        function() return BIT.db.interruptAttachPos or "RIGHT" end,
        function(v)
            BIT.db.interruptAttachPos = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end))
    registerAttached(CreateSlider(p, "Offset X", -100, 100, 1,
        function() return BIT.db.interruptAttachOffsetX or 0 end,
        function(v)
            BIT.db.interruptAttachOffsetX = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end,
        function(v) return math.floor(v) .. "px" end))
    registerAttached(CreateSlider(p, "Offset Y", -100, 100, 1,
        function() return BIT.db.interruptAttachOffsetY or 0 end,
        function(v)
            BIT.db.interruptAttachOffsetY = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end,
        function(v) return math.floor(v) .. "px" end))
    registerAttached(CreateSlider(p, "Icon Size", 12, 64, 1,
        function() return BIT.db.interruptAttachIconSize or 32 end,
        function(v)
            BIT.db.interruptAttachIconSize = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end,
        function(v) return math.floor(v) .. "px" end))
    registerAttached(CreateSlider(p, "Counter Text Size", 6, 28, 1,
        function() return BIT.db.interruptAttachCounterSize or 14 end,
        function(v)
            BIT.db.interruptAttachCounterSize = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end,
        function(v) return math.floor(v) .. "px" end))
    registerAttached(CreateToggle(p, "Desaturate on Cooldown",
        function() return BIT.db.interruptAttachDesaturateOnCD ~= false end,
        function(v) BIT.db.interruptAttachDesaturateOnCD = v end))
    registerAttached(CreateToggle(p, "Show Own Icon on Player Frame",
        function() return BIT.db.interruptAttachShowOwn ~= false end,
        function(v)
            BIT.db.interruptAttachShowOwn = v
            if BIT.UI.AttachedInterrupts and BIT.UI.AttachedInterrupts.Rebuild then
                BIT.UI.AttachedInterrupts:Rebuild()
            end
        end))

    -- Apply initial visibility so the first layout pass respects the mode.
    _syncAttachedOnlyVisibility()

    -- (Icon Only Mode was removed in 3.3.8 — use the new "Attached to Unit
    --  Frames" display mode above for a compact per-player layout.)

    -- Visibility
    w[#w+1] = CreateSectionHeader(p, "Visibility", "sui_int_vis")
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_DUNGEON", "Show in Dungeon"),
        function() return BIT.db.showInDungeon end,
        function(v) BIT.db.showInDungeon = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_RAID", "Show in Raid"),
        function() return BIT.db.showInRaid end,
        function(v) BIT.db.showInRaid = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_WORLD", "Show in Open World"),
        function() return BIT.db.showInOpenWorld end,
        function(v) BIT.db.showInOpenWorld = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_ARENA", "Show in Arena"),
        function() return BIT.db.showInArena end,
        function(v) BIT.db.showInArena = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_BG", "Show in Battleground"),
        function() return BIT.db.showInBG end,
        function(v) BIT.db.showInBG = v end)

    -- Failed Kick
    w[#w+1] = CreateSectionHeader(p, "Failed Kick Detection", "sui_int_fk")
    w[#w+1] = CreateToggle(p, LS("CB_FAILED_KICK", "Show Failed Kick Detection"),
        function() return BIT.db.showFailedKick end,
        function(v) BIT.db.showFailedKick = v end)

    -- Sounds
    w[#w+1] = CreateSectionHeader(p, "Sounds", "sui_int_snd")
    w[#w+1] = CreateToggle(p, LS("CB_SOUND_ENABLED", "Sound Enabled"),
        function() return BIT.db.soundEnabled end,
        function(v) BIT.db.soundEnabled = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SOUND_OWN_ONLY", "Only Own Kicks"),
        function() return BIT.db.soundOwnKickOnly end,
        function(v) BIT.db.soundOwnKickOnly = v end)
    w[#w+1] = CreateDropdown(p, LS("DD_SOUND_SUCCESS", "Kick Success Sound"),
        MediaOpts(function() return BIT.Media:GetAvailableSounds() end),
        function() return BIT.db.soundKickSuccess or "None" end,
        function(v) BIT.db.soundKickSuccess = v end)
    w[#w+1] = CreateDropdown(p, LS("DD_SOUND_FAILED", "Kick Failed Sound"),
        MediaOpts(function() return BIT.Media:GetAvailableSounds() end),
        function() return BIT.db.soundKickFailed or "None" end,
        function(v) BIT.db.soundKickFailed = v end)

    return w
end

------------------------------------------------------------
-- ── Category: Size & Font ────────────────────────────────
------------------------------------------------------------
local function BuildSizeFont()
    local w = {}
    local p = contentChild

    -- Frame
    w[#w+1] = CreateSectionHeader(p, "Frame", "sui_sf_frame")
    w[#w+1] = CreateSlider(p, LS("SL_WIDTH", "Frame Width"), 10, 500, 1,
        function() return BIT.db.frameWidth or 180 end,
        function(v) BIT.db.frameWidth = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_BAR_HEIGHT", "Bar Height"), 14, 60, 1,
        function() return BIT.db.barHeight or 30 end,
        function(v) BIT.db.barHeight = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_BAR_GAP", "Bar Gap"), -1, 40, 1,
        function() return BIT.db.barGap or 0 end,
        function(v) BIT.db.barGap = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_FRAME_SCALE", "Frame Scale"), 10, 200, 5,
        function() return BIT.db.frameScale or 100 end,
        function(v) BIT.db.frameScale = v end,
        function(v) return math.floor(v) .. "%" end)

    -- Font
    w[#w+1] = CreateSectionHeader(p, "Font", "sui_sf_font")
    w[#w+1] = CreateDropdown(p, "Font",
        MediaOpts(function() return BIT.Media:GetAvailableFonts() end),
        function() return BIT.db.fontName or BIT.Media.fontName or "Default" end,
        function(v)
            for _, e in ipairs(BIT.Media:GetAvailableFonts()) do
                if e.name == v then
                    BIT.db.fontPath = e.path; BIT.db.fontName = e.name
                    BIT.Media.font  = e.path; BIT.Media.fontName = e.name
                    break
                end
            end
        end)

    -- Bar Texture
    w[#w+1] = CreateSectionHeader(p, "Bar Texture", "sui_sf_bartex")
    w[#w+1] = CreateDropdown(p, "Bar Texture",
        MediaOpts(function() return BIT.Media:GetAvailableTextures() end),
        function() return BIT.db.barTextureName or BIT.Media.barTextureName or "Flat" end,
        function(v)
            for _, e in ipairs(BIT.Media:GetAvailableTextures()) do
                if e.name == v then
                    BIT.db.barTexturePath = e.path; BIT.db.barTextureName = e.name
                    BIT.Media.barTexture  = e.path; BIT.Media.barTextureName = e.name
                    break
                end
            end
        end)

    -- Border
    w[#w+1] = CreateSectionHeader(p, "Border", "sui_sf_border")
    w[#w+1] = CreateDropdown(p, "Border Texture",
        MediaOpts(function() return BIT.Media:GetAvailableBorders() end),
        function() return BIT.db.borderTextureName or "None" end,
        function(v)
            for _, e in ipairs(BIT.Media:GetAvailableBorders()) do
                if e.name == v then
                    BIT.db.borderTexturePath = e.path
                    BIT.db.borderTextureName = e.name
                    if BIT.UI and BIT.UI.ApplyBorderToAll then BIT.UI:ApplyBorderToAll() end
                    break
                end
            end
        end)
    w[#w+1] = CreateSlider(p, "Border Size", 1, 24, 1,
        function() return BIT.db.borderSize or 12 end,
        function(v) BIT.db.borderSize = v; if BIT.UI and BIT.UI.ApplyBorderToAll then BIT.UI:ApplyBorderToAll() end end,
        function(v) return math.floor(v) .. "px" end)

    -- Title
    w[#w+1] = CreateSectionHeader(p, "Title Bar", "sui_sf_title")
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_TITLE", "Show Title"),
        function() return BIT.db.showTitle end,
        function(v) BIT.db.showTitle = v end)
    w[#w+1] = CreateSlider(p, LS("SL_FONT_TITLE", "Title Font Size"), 0, 36, 1,
        function() return BIT.db.titleFontSize or 16 end,
        function(v) BIT.db.titleFontSize = v end,
        function(v) return v == 0 and "Auto" or (math.floor(v) .. "px") end)
    w[#w+1] = CreateDropdown(p, "Title Alignment",
        { { value = "LEFT", label = "Left" }, { value = "CENTER", label = "Center" }, { value = "RIGHT", label = "Right" } },
        function() return BIT.db.titleAlign or "RIGHT" end,
        function(v) BIT.db.titleAlign = v end)
    w[#w+1] = CreateSlider(p, "Title Offset Y", -30, 30, 1,
        function() return BIT.db.titleOffsetY or 3 end,
        function(v) BIT.db.titleOffsetY = v end,
        function(v) return math.floor(v) .. "px" end)

    -- Name
    w[#w+1] = CreateSectionHeader(p, "Name", "sui_sf_name")
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_NAME", "Show Name"),
        function() return BIT.db.showName end,
        function(v) BIT.db.showName = v end)
    w[#w+1] = CreateSlider(p, LS("SL_FONT_NAME", "Name Font Size"), 0, 24, 1,
        function() return BIT.db.nameFontSize or 0 end,
        function(v) BIT.db.nameFontSize = v end,
        function(v) return v == 0 and "Auto" or (math.floor(v) .. "px") end)
    w[#w+1] = CreateSlider(p, "Name Offset X", -100, 100, 1,
        function() return BIT.db.nameOffsetX or 0 end,
        function(v) BIT.db.nameOffsetX = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, "Name Offset Y", -20, 20, 1,
        function() return BIT.db.nameOffsetY or 0 end,
        function(v) BIT.db.nameOffsetY = v end,
        function(v) return math.floor(v) .. "px" end)

    -- CD / Ready
    w[#w+1] = CreateSectionHeader(p, "CD / Ready", "sui_sf_cd")
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_READY", "Show Ready Text"),
        function() return BIT.db.showReady end,
        function(v) BIT.db.showReady = v end)
    w[#w+1] = CreateSlider(p, LS("SL_FONT_CD", "CD Font Size"), 0, 24, 1,
        function() return BIT.db.readyFontSize or 0 end,
        function(v) BIT.db.readyFontSize = v end,
        function(v) return v == 0 and "Auto" or (math.floor(v) .. "px") end)
    w[#w+1] = CreateSlider(p, "CD Offset X", -50, 50, 1,
        function() return BIT.db.cdOffsetX or 0 end,
        function(v) BIT.db.cdOffsetX = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, "CD Offset Y", -50, 50, 1,
        function() return BIT.db.cdOffsetY or 0 end,
        function(v) BIT.db.cdOffsetY = v end,
        function(v) return math.floor(v) .. "px" end)

    -- Outline & Shadow
    w[#w+1] = CreateSectionHeader(p, "Outline & Shadow", "sui_sf_outline")
    w[#w+1] = CreateDropdown(p, LS("DD_FONT_OUTLINE", "Font Outline"),
        { { value = "NONE", label = "None" }, { value = "OUTLINE", label = "Outline" }, { value = "THICKOUTLINE", label = "Thick" } },
        function() return BIT.db.fontOutline or "OUTLINE" end,
        function(v)
            BIT.db.fontOutline = v
            BIT.Media:Load()
            BIT.UI:RebuildBars()
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)
    w[#w+1] = CreateSlider(p, "Shadow X", -5, 5, 1,
        function() return BIT.db.shadowOffsetX or 0 end,
        function(v)
            BIT.db.shadowOffsetX = v
            BIT.UI:RebuildBars()
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)
    w[#w+1] = CreateSlider(p, "Shadow Y", -5, 5, 1,
        function() return BIT.db.shadowOffsetY or 0 end,
        function(v)
            BIT.db.shadowOffsetY = v
            BIT.UI:RebuildBars()
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)

    return w
end

------------------------------------------------------------
-- ── Category: Colors ─────────────────────────────────────
------------------------------------------------------------
local function BuildColors()
    local w = {}
    local p = contentChild

    w[#w+1] = CreateSectionHeader(p, "Bar Color", "sui_col_bar")
    w[#w+1] = CreateToggle(p, LS("COLOR_CLASS", "Use Class Colors"),
        function() return BIT.db.useClassColors end,
        function(v)
            BIT.db.useClassColors = v
            if pages[activePage] and pages[activePage].refresh then pages[activePage].refresh() end
            if pages[activePage] and pages[activePage].layout  then pages[activePage].layout()  end
        end)
    local fadeToggle = CreateToggle(p, LS("COLOR_CD_FADE", 'Fade (Looks good with "Fill" Option)'),
        function() return BIT.db.cdBarFade end,
        function(v) BIT.db.cdBarFade = v end)
    fadeToggle._dynamic = true
    fadeToggle._update = function()
        if BIT.db.useClassColors then
            fadeToggle:Hide()
        else
            fadeToggle:Show()
        end
    end
    fadeToggle._update()
    w[#w+1] = fadeToggle
    w[#w+1] = CreateColorSwatch(p, LS("COLOR_CUSTOM", "Ready Bar"),
        function() return BIT.db.customColorR or 0.4 end,
        function() return BIT.db.customColorG or 0.8 end,
        function() return BIT.db.customColorB or 1.0 end,
        function(r, g, b) BIT.db.customColorR = r; BIT.db.customColorG = g; BIT.db.customColorB = b end)
    w[#w+1] = CreateColorSwatch(p, LS("COLOR_CD_BAR", "Cooldown Bar"),
        function() return BIT.db.cdBarColorR or 0.8 end,
        function() return BIT.db.cdBarColorG or 0.2 end,
        function() return BIT.db.cdBarColorB or 0.2 end,
        function(r, g, b) BIT.db.cdBarColorR = r; BIT.db.cdBarColorG = g; BIT.db.cdBarColorB = b end)

    w[#w+1] = CreateSectionHeader(p, "Title Color", "sui_col_title")
    w[#w+1] = CreateColorSwatch(p, "Title Color",
        function() return BIT.db.titleColorR or 1.0 end,
        function() return BIT.db.titleColorG or 0.867 end,
        function() return BIT.db.titleColorB or 0.867 end,
        function(r, g, b) BIT.db.titleColorR = r; BIT.db.titleColorG = g; BIT.db.titleColorB = b end)

    -- ── Name Color ───────────────────────────────────────────
    -- Controls the player-name text color in the interrupt tracker bars.
    -- The color picker is hidden while the Use-Class-Colors toggle is on,
    -- since the per-class color wins in that mode.
    w[#w+1] = CreateSectionHeader(p, "Name Color", "sui_col_name")
    w[#w+1] = CreateToggle(p, "Use Class Colors (Names)",
        function() return BIT.db.nameColorUseClass end,
        function(v)
            BIT.db.nameColorUseClass = v
            if pages[activePage] and pages[activePage].refresh then pages[activePage].refresh() end
            if pages[activePage] and pages[activePage].layout  then pages[activePage].layout()  end
            if BIT.UI.UpdateDisplay then BIT.UI:UpdateDisplay() end
        end)
    local nameSwatch = CreateColorSwatch(p, "Name Color",
        function() return BIT.db.nameColorR or 1.0 end,
        function() return BIT.db.nameColorG or 1.0 end,
        function() return BIT.db.nameColorB or 1.0 end,
        function(r, g, b)
            BIT.db.nameColorR = r
            BIT.db.nameColorG = g
            BIT.db.nameColorB = b
            if BIT.UI.UpdateDisplay then BIT.UI:UpdateDisplay() end
        end)
    nameSwatch._dynamic = true
    nameSwatch._update  = function()
        if BIT.db.nameColorUseClass then nameSwatch:Hide() else nameSwatch:Show() end
    end
    nameSwatch._update()
    w[#w+1] = nameSwatch

    w[#w+1] = CreateSectionHeader(p, "Background Color", "sui_col_bg")
    w[#w+1] = CreateColorSwatch(p, "Background Color",
        function() return BIT.db.customBgColorR or 0.1 end,
        function() return BIT.db.customBgColorG or 0.1 end,
        function() return BIT.db.customBgColorB or 0.1 end,
        function(r, g, b) BIT.db.customBgColorR = r; BIT.db.customBgColorG = g; BIT.db.customBgColorB = b end)

    w[#w+1] = CreateSectionHeader(p, "Border Color", "sui_col_border")
    w[#w+1] = CreateColorSwatch(p, "Border Color",
        function() return BIT.db.borderColorR or 0 end,
        function() return BIT.db.borderColorG or 0 end,
        function() return BIT.db.borderColorB or 0 end,
        function(r, g, b) BIT.db.borderColorR = r; BIT.db.borderColorG = g; BIT.db.borderColorB = b end,
        function() return BIT.db.borderColorA or 1.0 end,
        function(a) BIT.db.borderColorA = a end)

    w[#w+1] = CreateSectionHeader(p, "Ready / CD Color", "sui_col_ready")
    w[#w+1] = CreateColorSwatch(p, "Ready Color",
        function() return BIT.db.readyColorR or 0.2 end,
        function() return BIT.db.readyColorG or 1.0 end,
        function() return BIT.db.readyColorB or 0.2 end,
        function(r, g, b) BIT.db.readyColorR = r; BIT.db.readyColorG = g; BIT.db.readyColorB = b end)

    return w
end

------------------------------------------------------------
-- ── Category: Party CDs ──────────────────────────────────
------------------------------------------------------------
local function BuildPartyCDs()
    local w = {}
    local p = contentChild

    -- General
    w[#w+1] = CreateSectionHeader(p, "General", "sui_pcd_gen")
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_SYNC_CDS", "Show Party CD Tracker"),
        function() return BIT.db.showSyncCDs end,
        function(v) BIT.db.showSyncCDs = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SYNC_ONLY_GROUP", "Show Only in Group"),
        function() return BIT.db.syncOnlyInGroup end,
        function(v) BIT.db.syncOnlyInGroup = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_OWN_SYNC", "Show Own Cooldowns"),
        function() return BIT.db.showOwnSyncCD end,
        function(v) BIT.db.showOwnSyncCD = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_DMG", "Show Offensives"),
        function() return BIT.db.syncCdShowDMG end,
        function(v) BIT.db.syncCdShowDMG = v; BIT.db.syncCdCatVer = (BIT.db.syncCdCatVer or 0) + 1 end)
    w[#w+1] = CreateToggle(p, LS("CB_SHOW_DEF", "Show Defensives"),
        function() return BIT.db.syncCdShowDEF end,
        function(v) BIT.db.syncCdShowDEF = v; BIT.db.syncCdCatVer = (BIT.db.syncCdCatVer or 0) + 1 end)
    w[#w+1] = CreateToggle(p, LS("CB_SYNC_TOOLTIP", "Show Spell Tooltips"),
        function() return BIT.db.syncCdTooltip end,
        function(v) BIT.db.syncCdTooltip = v end)
    w[#w+1] = CreateToggle(p, LS("CB_SYNC_GLOW", "Show Buff Glow"),
        function() return BIT.db.syncCdGlow end,
        function(v) BIT.db.syncCdGlow = v end)

    -- Display & Layout
    w[#w+1] = CreateSectionHeader(p, "Display & Layout", "sui_pcd_layout")
    w[#w+1] = CreateDropdown(p, LS("SYNC_DISPLAY_MODE_GROUP", "Mode (Group)"),
        { { value = "ATTACH", label = "Attached" }, { value = "WINDOW", label = "Window" },
          { value = "BARS", label = "Bars" }, { value = "OFF", label = "Off" } },
        function() return BIT.db.syncCdModeGroup or "ATTACH" end,
        function(v) BIT.db.syncCdModeGroup = v end)
    w[#w+1] = CreateDropdown(p, LS("SYNC_DISPLAY_MODE_RAID", "Mode (Raid)"),
        { { value = "BARS", label = "Bars" }, { value = "WINDOW", label = "Window" },
          { value = "ATTACH", label = "Attached" }, { value = "OFF", label = "Off" } },
        function() return BIT.db.syncCdModeRaid or "BARS" end,
        function(v) BIT.db.syncCdModeRaid = v end)
    -- Frame Provider (which unit frames to attach to)
    local providerOpts = (BIT.SyncCD and BIT.SyncCD.GetAvailableProviders)
        and BIT.SyncCD:GetAvailableProviders()
        or  { { value = "AUTO", label = "Auto Detect" }, { value = "BLIZZARD", label = "Blizzard" } }
    w[#w+1] = CreateDropdown(p, "Attach to Frames",
        providerOpts,
        function() return BIT.db.syncCdFrameProvider or "AUTO" end,
        function(v)
            BIT.db.syncCdFrameProvider = v
            BIT.db._frameProviderAsked = true
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)
    w[#w+1] = CreateDropdown(p, LS("SYNC_ATTACH_POS", "Attach Position"),
        { { value = "LEFT", label = "Left" }, { value = "RIGHT", label = "Right" },
          { value = "TOP", label = "Top" }, { value = "BOTTOM", label = "Bottom" } },
        function() return BIT.db.syncCdAttachPos or "LEFT" end,
        function(v) BIT.db.syncCdAttachPos = v end)
    w[#w+1] = CreateToggle(p, LS("CB_BARS_LOCKED", "Lock Position"),
        function() return BIT.db.syncCdBarsLocked end,
        function(v) BIT.db.syncCdBarsLocked = v end)
    w[#w+1] = CreateDropdown(p, LS("SYNC_TOP_LAYOUT", "Top — Layout"),
        { { value = "COLUMNS", label = "Columns" }, { value = "ROWS", label = "Rows" } },
        function() return BIT.db.syncCdTopLayout or "COLUMNS" end,
        function(v)
            BIT.db.syncCdTopLayout = v
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)
    w[#w+1] = CreateDropdown(p, LS("SYNC_BOTTOM_LAYOUT", "Bottom — Layout"),
        { { value = "ROWS", label = "Rows" }, { value = "COLUMNS", label = "Columns" } },
        function() return BIT.db.syncCdBottomLayout or "ROWS" end,
        function(v)
            BIT.db.syncCdBottomLayout = v
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)

    -- Category Row Assignment
    w[#w+1] = CreateSectionHeader(p, "Category Rows", "sui_pcd_rows")
    local rowOpts = {
        { value = "1", label = "Row 1" },
        { value = "2", label = "Row 2" },
        { value = "3", label = "Row 3" },
    }
    local function bumpCatVer()
        BIT.db.syncCdCatVer = (BIT.db.syncCdCatVer or 0) + 1
        if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
    end
    w[#w+1] = CreateDropdown(p, LS("DD_CAT_ROW_DMG", "Offensives — Row"), rowOpts,
        function() return tostring(BIT.db.syncCdCatRowDMG or "1") end,
        function(v) BIT.db.syncCdCatRowDMG = v; bumpCatVer() end)
    w[#w+1] = CreateDropdown(p, LS("DD_CAT_ROW_DEF", "Defensives — Row"), rowOpts,
        function() return tostring(BIT.db.syncCdCatRowDEF or "2") end,
        function(v) BIT.db.syncCdCatRowDEF = v; bumpCatVer() end)
    -- Icons & Text
    w[#w+1] = CreateSectionHeader(p, "Icons & Text", "sui_pcd_icons")
    w[#w+1] = CreateSlider(p, LS("SL_SYNC_ICON_SIZE", "Icon Size"), 12, 48, 1,
        function() return BIT.db.syncCdIconSize or 28 end,
        function(v) BIT.db.syncCdIconSize = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_SYNC_ICON_SPACING", "Icon Spacing"), 0, 20, 1,
        function() return BIT.db.syncCdIconSpacing or 4 end,
        function(v) BIT.db.syncCdIconSpacing = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_ATTACH_ROW_GAP", "Row Spacing"), 0, 20, 1,
        function() return BIT.db.syncCdAttachRowGap or 4 end,
        function(v) BIT.db.syncCdAttachRowGap = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, "Offset X", -100, 100, 1,
        function() return BIT.db.syncCdAttachOffsetX or 0 end,
        function(v) BIT.db.syncCdAttachOffsetX = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, "Offset Y", -100, 100, 1,
        function() return BIT.db.syncCdAttachOffsetY or 0 end,
        function(v) BIT.db.syncCdAttachOffsetY = v end,
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_SYNC_COUNTER_SIZE", "Counter Text Size"), 6, 24, 1,
        function() return BIT.db.syncCdCounterSize or 14 end,
        function(v) BIT.db.syncCdCounterSize = v end,
        function(v) return math.floor(v) .. "px" end)

    -- ── Charges ─────────────────────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("SEC_PCD_CHARGES", "Charges"), "sui_pcd_charges")
    local function chargeStyleSetter(key, def)
        return function(v)
            BIT.db[key] = v
            if BIT.SyncCD and BIT.SyncCD.UpdateChargeBadgeStyle then
                BIT.SyncCD:UpdateChargeBadgeStyle()
            end
        end
    end
    w[#w+1] = CreateSlider(p, LS("SL_CHARGE_SIZE", "Badge Size"), 6, 24, 1,
        function() return BIT.db.syncCdChargeSize or 13 end,
        chargeStyleSetter("syncCdChargeSize"),
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateDropdown(p, LS("DD_CHARGE_ANCHOR", "Anchor"),
        { { value = "TOPLEFT",     label = "Top Left" },
          { value = "TOP",         label = "Top" },
          { value = "TOPRIGHT",    label = "Top Right" },
          { value = "LEFT",        label = "Left" },
          { value = "CENTER",      label = "Center" },
          { value = "RIGHT",       label = "Right" },
          { value = "BOTTOMLEFT",  label = "Bottom Left" },
          { value = "BOTTOM",      label = "Bottom" },
          { value = "BOTTOMRIGHT", label = "Bottom Right" } },
        function() return BIT.db.syncCdChargeAnchor or "BOTTOMRIGHT" end,
        chargeStyleSetter("syncCdChargeAnchor"))
    w[#w+1] = CreateSlider(p, LS("SL_CHARGE_OFFSET_X", "Offset X"), -20, 20, 1,
        function() return BIT.db.syncCdChargeOffX or -1 end,
        chargeStyleSetter("syncCdChargeOffX"),
        function(v) return math.floor(v) .. "px" end)
    w[#w+1] = CreateSlider(p, LS("SL_CHARGE_OFFSET_Y", "Offset Y"), -20, 20, 1,
        function() return BIT.db.syncCdChargeOffY or 1 end,
        chargeStyleSetter("syncCdChargeOffY"),
        function(v) return math.floor(v) .. "px" end)

    -- ── Spell Filters — Party CDs ───────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, "Spell Filters", "sui_pcd_spellfilter")

    local SPEC_TO_CLASS = {
        [250]="DEATHKNIGHT",[251]="DEATHKNIGHT",[252]="DEATHKNIGHT",
        [577]="DEMONHUNTER",[581]="DEMONHUNTER",[1480]="DEMONHUNTER",
        [102]="DRUID",[103]="DRUID",[104]="DRUID",[105]="DRUID",
        [1467]="EVOKER",[1468]="EVOKER",[1473]="EVOKER",
        [253]="HUNTER",[254]="HUNTER",[255]="HUNTER",
        [62]="MAGE",[63]="MAGE",[64]="MAGE",
        [268]="MONK",[269]="MONK",[270]="MONK",
        [65]="PALADIN",[66]="PALADIN",[70]="PALADIN",
        [256]="PRIEST",[257]="PRIEST",[258]="PRIEST",
        [259]="ROGUE",[260]="ROGUE",[261]="ROGUE",
        [262]="SHAMAN",[263]="SHAMAN",[264]="SHAMAN",
        [265]="WARLOCK",[266]="WARLOCK",[267]="WARLOCK",
        [71]="WARRIOR",[72]="WARRIOR",[73]="WARRIOR",
    }
    local PCD_CLASS_DISPLAY = {
        DEATHKNIGHT="DK", DEMONHUNTER="DH",
        DRUID="Druid", EVOKER="Evoker", HUNTER="Hunter",
        MAGE="Mage", MONK="Monk", PALADIN="Paladin",
        PRIEST="Priest", ROGUE="Rogue", SHAMAN="Shaman",
        WARLOCK="Warlock", WARRIOR="Warrior",
    }

    -- Build flat spell list with category + class from BIT.SYNC_SPELLS
    local pcdSpells = {}
    local seenSpell = {}
    if BIT.SYNC_SPELLS then
        for specID, spells in pairs(BIT.SYNC_SPELLS) do
            local cls = SPEC_TO_CLASS[specID]
            if cls then
                for _, s in ipairs(spells) do
                    if not seenSpell[s.id] then
                        seenSpell[s.id] = true
                        pcdSpells[#pcdSpells+1] = {
                            id           = s.id,
                            label        = s.name,
                            class        = cls,
                            className    = PCD_CLASS_DISPLAY[cls] or cls,
                            cat          = s.cat or "DEF",
                            notTrackable = s.notTrackable,
                        }
                    end
                end
            end
        end
        table.sort(pcdSpells, function(a, b)
            if a.class ~= b.class then return a.class < b.class end
            return a.label < b.label
        end)
    end

    -- Split into tab groups: DEF, DMG
    local pcdDef, pcdDmg = {}, {}
    for _, s in ipairs(pcdSpells) do
        if s.cat == "DEF" then pcdDef[#pcdDef+1] = s
        elseif s.cat == "DMG" then pcdDmg[#pcdDmg+1] = s end
    end

    -- Build racial list from BIT.SyncCD.byRace (Shadowmeld, Stoneform, …).
    -- Racials have no class affiliation — use class="RACIAL" so the panel's
    -- CLASS_COLORS lookup falls back to neutral gray; race name is shown
    -- as the suffix (e.g. "Shadowmeld (Night Elf)").
    local PCD_RACE_DISPLAY = {
        NightElf = "Night Elf",
        Dwarf    = "Dwarf",
    }
    local pcdRacial = {}
    if BIT.SyncCD and BIT.SyncCD.byRace then
        for raceKey, entries in pairs(BIT.SyncCD.byRace) do
            for _, s in ipairs(entries) do
                pcdRacial[#pcdRacial+1] = {
                    id        = s.id,
                    label     = s.name,
                    class     = "RACIAL",
                    className = PCD_RACE_DISPLAY[raceKey] or raceKey,
                    cat       = s.cat or "DEF",
                }
            end
        end
        table.sort(pcdRacial, function(a, b)
            if a.className ~= b.className then return a.className < b.className end
            return a.label < b.label
        end)
    end

    local pcdGetter = function(sid) return not (BIT.db.syncCdDisabled and BIT.db.syncCdDisabled[sid]) end
    local pcdSetter = function(sid, enabled)
        if not BIT.db.syncCdDisabled then BIT.db.syncCdDisabled = {} end
        BIT.db.syncCdDisabled[sid] = not enabled or nil
        BIT.db.syncCdDisabledVer = (BIT.db.syncCdDisabledVer or 0) + 1
        if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
    end

    w[#w+1] = CreateSpellFilterPanel(p, pcdDef, pcdGetter, pcdSetter, {
        { label = "Def",    spells = pcdDef    },
        { label = "Off",    spells = pcdDmg    },
        { label = "Racial", spells = pcdRacial },
    })

    return w
end

------------------------------------------------------------
-- ── Category: Smart Misdirect ────────────────────────────
--   Hunter: Misdirection (34477)
--   Rogue : Tricks of the Trade (57934)
--   For any other class we render a short "not available"
--   notice so the page never silently goes blank.
------------------------------------------------------------
local function BuildSmartMisdirect()
    local w = {}
    local p = contentChild

    local myClass = BIT.Self and BIT.Self.class or BIT.myClass
    local eligible = (myClass == "HUNTER" or myClass == "ROGUE")

    w[#w+1] = CreateSectionHeader(p, LS("SMD_SEC_GENERAL", "General"), "sui_smd_gen")

    if not eligible then
        w[#w+1] = CreateLabel(p,
            "|cffff8800" .. LS("SMD_DESC_CLASS", "Only Hunters and Rogues can use Smart Misdirect.") .. "|r",
            12)
        return w
    end

    w[#w+1] = CreateLabel(p, LS("SMD_DESC",
        "Automatically re-targets Misdirection / Tricks of the Trade based on your group, focus and tanks."),
        11)
    w[#w+1] = CreateToggle(p, LS("SMD_ENABLED", "Enable Smart Misdirect"),
        function() return BIT.db.smartMdEnabled end,
        function(v)
            BIT.db.smartMdEnabled = v
            if not BIT.SmartMisdirect then return end
            if v then
                if BIT.SmartMisdirect.CreateButtons then BIT.SmartMisdirect:CreateButtons() end
                if BIT.SmartMisdirect.QueueUpdate   then BIT.SmartMisdirect:QueueUpdate()   end
            else
                if BIT.SmartMisdirect.ClearButtons  then BIT.SmartMisdirect:ClearButtons()  end
            end
        end)
    w[#w+1] = CreateToggle(p, LS("SMD_ANNOUNCE_TARGET", "Announce target change in chat"),
        function() return BIT.db.smartMdAnnounceTarget end,
        function(v) BIT.db.smartMdAnnounceTarget = v end)

    -- ── Targeting ───────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("SMD_SEC_TARGETING", "Targeting"), "sui_smd_target")
    w[#w+1] = CreateToggle(p, LS("SMD_PRIORITIZE_FOCUS", "Prefer Focus target (if in group)"),
        function() return BIT.db.smartMdPrioritizeFocus end,
        function(v)
            BIT.db.smartMdPrioritizeFocus = v
            if BIT.SmartMisdirect then BIT.SmartMisdirect:QueueUpdate() end
        end)
    if myClass == "HUNTER" then
        w[#w+1] = CreateToggle(p, LS("SMD_INCLUDE_PET", "Fallback to own pet (Hunter)"),
            function() return BIT.db.smartMdIncludePet end,
            function(v)
                BIT.db.smartMdIncludePet = v
                if BIT.SmartMisdirect then BIT.SmartMisdirect:QueueUpdate() end
            end)
    end
    w[#w+1] = CreateDropdown(p, LS("SMD_TANK_METHOD", "Tank Selection"),
        { { value = "byRole",          label = LS("SMD_METHOD_BY_ROLE",    "By Role (TANK)") },
          { value = "roleAndMainTank", label = LS("SMD_METHOD_ROLE_AND_MT","Role + Main Tank") },
          { value = "mainTankFirst",   label = LS("SMD_METHOD_MT_FIRST",   "Main Tank first") },
          { value = "mainTankOnly",    label = LS("SMD_METHOD_MT_ONLY",    "Main Tank only") } },
        function() return BIT.db.smartMdTankMethod or "byRole" end,
        function(v)
            BIT.db.smartMdTankMethod = v
            if BIT.SmartMisdirect then BIT.SmartMisdirect:QueueUpdate() end
        end)

    -- ── Manual Override ─────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("SMD_SEC_OVERRIDE", "Manual Override"), "sui_smd_over")
    w[#w+1] = CreateLabel(p, LS("SMD_OVERRIDE_HINT", "Leave empty to disable."), 11)
    w[#w+1] = CreateEditBox(p, LS("SMD_OVERRIDE_NAME", "Player Name"),
        function() return BIT.db.smartMdManualName or "" end,
        function(v)
            BIT.db.smartMdManualName = v or ""
            if BIT.SmartMisdirect then BIT.SmartMisdirect:QueueUpdate() end
        end)
    w[#w+1] = CreateEditBox(p, LS("SMD_OVERRIDE_REALM", "Realm (cross-realm only)"),
        function() return BIT.db.smartMdManualRealm or "" end,
        function(v)
            BIT.db.smartMdManualRealm = v or ""
            if BIT.SmartMisdirect then BIT.SmartMisdirect:QueueUpdate() end
        end)
    -- Clear button
    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, WIDGET_H)
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(160, 24)
        btn:SetPoint("LEFT", 0, 0)
        MakeBg(btn, 0.18, 0.10, 0.10, 1)
        local txt = btn:CreateFontString(nil, "OVERLAY")
        ApplyFont(txt, 11)
        txt:SetPoint("CENTER")
        txt:SetTextColor(1, 0.5, 0.5)
        txt:SetText(LS("SMD_OVERRIDE_CLEAR", "Clear Override"))
        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        btn:SetScript("OnClick", function()
            if BIT.SmartMisdirect and BIT.SmartMisdirect.ClearManualOverride then
                BIT.SmartMisdirect:ClearManualOverride(false)
            end
            -- Force a rebuild so the two EditBox widgets re-read the empty value
            if pages[activePage] and pages[activePage].layout then
                pages[activePage].layout()
            end
            Refresh()
        end)
        w[#w+1] = f
    end

    -- ── Macro ───────────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("SMD_SEC_MACRO", "Macro"), "sui_smd_macro")
    w[#w+1] = CreateLabel(p, LS("SMD_MACRO_HINT",
        "Creates a per-character macro you can drag onto your action bar."), 11)
    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, WIDGET_H + 6)

        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(220, 26)
        btn:SetPoint("LEFT", 0, 0)
        MakeBg(btn, 0.15, 0.15, 0.18, 1)
        local txt = btn:CreateFontString(nil, "OVERLAY")
        ApplyFont(txt, 12)
        txt:SetPoint("CENTER")
        txt:SetTextColor(RGB(ACCENT))
        txt:SetText(LS("SMD_MACRO_BTN", "Create / Update Macro"))
        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        btn:SetScript("OnClick", function()
            if not BIT.SmartMisdirect or not BIT.SmartMisdirect.CreateMacro then return end
            if InCombatLockdown() then
                txt:SetTextColor(1, 0.4, 0.4)
                txt:SetText("|cffff5555" .. LS("SMD_MACRO_IN_COMBAT",
                    "Cannot create macros while in combat.") .. "|r")
                C_Timer.After(3, function()
                    txt:SetTextColor(RGB(ACCENT))
                    txt:SetText(LS("SMD_MACRO_BTN", "Create / Update Macro"))
                end)
                return
            end
            local idx, created, updated = BIT.SmartMisdirect:CreateMacro()
            if idx then
                txt:SetText("|cFF00FF00" .. (created and "Created!" or "Updated!") .. "|r")
                C_Timer.After(2, function()
                    txt:SetTextColor(RGB(ACCENT))
                    txt:SetText(LS("SMD_MACRO_BTN", "Create / Update Macro"))
                end)
            end
        end)

        w[#w+1] = f
    end

    return w
end

------------------------------------------------------------
-- ── Category: Profiles ───────────────────────────────────
------------------------------------------------------------
local function BuildProfiles()
    local w = {}
    local p = contentChild

    -- ── Character Profiles ──────────────────────────────
    w[#w+1] = CreateSectionHeader(p, "Character Profiles", "sui_prof_chars")

    -- Current character info
    w[#w+1] = CreateLabel(p, "Current: |cFFFFD700" .. (BIT.charKey or "?") .. "|r", 12)

    -- Save button (as a clickable label row)
    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, WIDGET_H)

        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(120, 24)
        saveBtn:SetPoint("LEFT", 0, 0)
        MakeBg(saveBtn, 0.15, 0.15, 0.18, 1)

        local saveTxt = saveBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(saveTxt, 11)
        saveTxt:SetPoint("CENTER")
        saveTxt:SetTextColor(RGB(ACCENT))
        saveTxt:SetText("Save Current")

        saveBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        saveBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        saveBtn:SetScript("OnClick", function()
            BIT.SaveCharProfile()
            saveTxt:SetText("|cFF00FF00Saved!|r")
            C_Timer.After(2, function() saveTxt:SetTextColor(RGB(ACCENT)); saveTxt:SetText("Save Current") end)
        end)

        w[#w+1] = f
    end

    -- Other character profiles — copy buttons
    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, 10) -- height set dynamically

        local charRows = {}
        f._update = function()
            for _, r in ipairs(charRows) do r:Hide() end
            wipe(charRows)

            local others = BIT.GetOtherCharProfiles and BIT.GetOtherCharProfiles() or {}
            if #others == 0 then
                local empty = f:CreateFontString(nil, "OVERLAY")
                ApplyFont(empty, 11)
                empty:SetPoint("TOPLEFT", 0, 0)
                empty:SetTextColor(RGB(TEXT_DIM))
                empty:SetText("No other character profiles saved yet.")
                charRows[1] = CreateFrame("Frame", nil, f)
                charRows[1]:SetSize(1, 18)
                charRows[1]:SetPoint("TOPLEFT")
                f:SetHeight(20)
                return
            end

            local rowH = 26
            for i, key in ipairs(others) do
                local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
                row:SetSize(f:GetWidth(), rowH)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 2))
                MakeBg(row, i % 2 == 0 and 0.10 or 0.13, 0.10, i % 2 == 0 and 0.10 or 0.13, 1)

                local nameLbl = row:CreateFontString(nil, "OVERLAY")
                ApplyFont(nameLbl, 11)
                nameLbl:SetPoint("LEFT", 8, 0)
                nameLbl:SetTextColor(RGB(TEXT))
                nameLbl:SetText(key)

                local capturedKey = key

                local delBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                delBtn:SetSize(60, 20)
                delBtn:SetPoint("RIGHT", -4, 0)
                MakeBg(delBtn, 0.18, 0.10, 0.10, 1)

                local delTxt = delBtn:CreateFontString(nil, "OVERLAY")
                ApplyFont(delTxt, 10)
                delTxt:SetPoint("CENTER")
                delTxt:SetTextColor(1, 0.5, 0.5)
                delTxt:SetText("Delete")

                delBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4) end)
                delBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                delBtn:SetScript("OnClick", function()
                    StaticPopup_Show("BIT_CONFIRM_DELETE_PROFILE", capturedKey, nil, {
                        key = capturedKey,
                        onSuccess = function() if f._update then f._update() end; Refresh() end,
                    })
                end)

                local copyBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                copyBtn:SetSize(60, 20)
                copyBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
                MakeBg(copyBtn, 0.15, 0.15, 0.18, 1)

                local copyTxt = copyBtn:CreateFontString(nil, "OVERLAY")
                ApplyFont(copyTxt, 10)
                copyTxt:SetPoint("CENTER")
                copyTxt:SetTextColor(RGB(ACCENT))
                copyTxt:SetText("Copy")

                copyBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
                copyBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                copyBtn:SetScript("OnClick", function()
                    StaticPopup_Show("BIT_CONFIRM_COPY_PROFILE", capturedKey, nil, {
                        key = capturedKey,
                        onSuccess = function()
                            copyTxt:SetText("|cFF00FF00Done!|r")
                            C_Timer.After(2, function() copyTxt:SetTextColor(RGB(ACCENT)); copyTxt:SetText("Copy") end)
                            Refresh()
                        end,
                    })
                end)

                charRows[#charRows+1] = row
            end
            f:SetHeight(#others * (rowH + 2))
        end
        f._update()
        w[#w+1] = f
    end

    -- ── Global Default Profile ──────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("PROFILE_GLOBAL", "Global Default"), "sui_prof_global")

    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, WIDGET_H)

        local statusLbl = f:CreateFontString(nil, "OVERLAY")
        ApplyFont(statusLbl, 11)
        statusLbl:SetPoint("LEFT", 0, 0)

        local function RefreshStatus()
            if BIT.HasGlobalProfile and BIT.HasGlobalProfile() then
                statusLbl:SetTextColor(0.4, 1, 0.4)
                statusLbl:SetText(LS("PROFILE_GLOBAL_SAVED", "Saved"))
            else
                statusLbl:SetTextColor(RGB(TEXT_DIM))
                statusLbl:SetText(LS("PROFILE_GLOBAL_NONE", "Not saved"))
            end
        end
        RefreshStatus()

        local applyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        applyBtn:SetSize(140, 24)
        applyBtn:SetPoint("RIGHT", 0, 0)
        MakeBg(applyBtn, 0.15, 0.15, 0.18, 1)
        local applyTxt = applyBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(applyTxt, 11)
        applyTxt:SetPoint("CENTER")
        applyTxt:SetTextColor(RGB(ACCENT))
        applyTxt:SetText(LS("PROFILE_BTN_APPLY_GLOBAL", "Apply Global"))
        applyBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        applyBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        applyBtn:SetScript("OnClick", function()
            if BIT.ApplyGlobalProfile and BIT.ApplyGlobalProfile() then
                applyTxt:SetText("|cFF00FF00Done!|r")
                C_Timer.After(2, function()
                    applyTxt:SetTextColor(RGB(ACCENT))
                    applyTxt:SetText(LS("PROFILE_BTN_APPLY_GLOBAL", "Apply Global"))
                end)
                Refresh()
            end
        end)

        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(140, 24)
        saveBtn:SetPoint("RIGHT", applyBtn, "LEFT", -6, 0)
        MakeBg(saveBtn, 0.15, 0.15, 0.18, 1)
        local saveTxt = saveBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(saveTxt, 11)
        saveTxt:SetPoint("CENTER")
        saveTxt:SetTextColor(RGB(ACCENT))
        saveTxt:SetText(LS("PROFILE_BTN_SAVE_GLOBAL", "Save as Global"))
        saveBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        saveBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        saveBtn:SetScript("OnClick", function()
            if BIT.SaveGlobalProfile then
                BIT.SaveGlobalProfile()
                RefreshStatus()
                saveTxt:SetText("|cFF00FF00Saved!|r")
                C_Timer.After(2, function()
                    saveTxt:SetTextColor(RGB(ACCENT))
                    saveTxt:SetText(LS("PROFILE_BTN_SAVE_GLOBAL", "Save as Global"))
                end)
            end
        end)

        local delBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        delBtn:SetSize(80, 24)
        delBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
        MakeBg(delBtn, 0.18, 0.10, 0.10, 1)
        local delTxt = delBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(delTxt, 11)
        delTxt:SetPoint("CENTER")
        delTxt:SetTextColor(1, 0.5, 0.5)
        delTxt:SetText(LS("PROFILE_BTN_DELETE_GLOBAL", "Delete"))
        delBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4) end)
        delBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        delBtn:SetScript("OnClick", function()
            if not (BIT.HasGlobalProfile and BIT.HasGlobalProfile()) then return end
            StaticPopup_Show("BIT_CONFIRM_DELETE_GLOBAL", nil, nil, {
                onSuccess = function() RefreshStatus() end,
            })
        end)

        w[#w+1] = f
    end

    w[#w+1] = CreateToggle(p, LS("PROFILE_AUTO_APPLY", "Auto-apply to new characters"),
        function() return BIT.db.useGlobalDefault end,
        function(v) BIT.db.useGlobalDefault = v end)

    -- ── Spec Profiles ────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("PROFILE_SPEC", "Spec Profiles"), "sui_prof_spec")

    w[#w+1] = CreateToggle(p, LS("PROFILE_AUTO_APPLY_SPEC", "Auto-apply on spec change"),
        function() return BIT.db.useSpecProfile end,
        function(v) BIT.db.useSpecProfile = v end)

    -- Row list: show all 3-4 specs of the player's class, each with status + buttons.
    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, 10)

        local specRows = {}
        f._update = function()
            for _, r in ipairs(specRows) do r:Hide() end
            wipe(specRows)

            -- Enumerate the player's class specs.
            local classID = select(3, UnitClass("player"))
            local numSpecs = classID and GetNumSpecializationsForClassID
                             and GetNumSpecializationsForClassID(classID) or 0
            if numSpecs == 0 then
                local empty = f:CreateFontString(nil, "OVERLAY")
                ApplyFont(empty, 11)
                empty:SetPoint("TOPLEFT", 0, 0)
                empty:SetTextColor(RGB(TEXT_DIM))
                empty:SetText(LS("PROFILE_SPEC_NONE", "No specs available."))
                specRows[1] = empty
                f:SetHeight(20)
                return
            end

            local curSpec = BIT.GetCurrentSpecID and BIT.GetCurrentSpecID()
            local rowH    = 26
            for i = 1, numSpecs do
                local specID, specName = GetSpecializationInfoForClassID(classID, i)
                if specID then
                    local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
                    row:SetSize(f:GetWidth(), rowH)
                    row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 2))
                    MakeBg(row, i % 2 == 0 and 0.10 or 0.13, 0.10, i % 2 == 0 and 0.10 or 0.13, 1)

                    local nameLbl = row:CreateFontString(nil, "OVERLAY")
                    ApplyFont(nameLbl, 11)
                    nameLbl:SetPoint("LEFT", 8, 0)
                    if specID == curSpec then
                        nameLbl:SetTextColor(1, 0.84, 0)  -- gold for current spec
                        nameLbl:SetText(specName .. "  |cFF888888(current)|r")
                    else
                        nameLbl:SetTextColor(RGB(TEXT))
                        nameLbl:SetText(specName)
                    end

                    local hasProf = BIT.HasSpecProfile and BIT.HasSpecProfile(specID)
                    local statusLbl = row:CreateFontString(nil, "OVERLAY")
                    ApplyFont(statusLbl, 10)
                    statusLbl:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)
                    if hasProf then
                        statusLbl:SetTextColor(0.4, 1, 0.4)
                        statusLbl:SetText(LS("PROFILE_GLOBAL_SAVED", "Saved"))
                    else
                        statusLbl:SetTextColor(RGB(TEXT_DIM))
                        statusLbl:SetText(LS("PROFILE_GLOBAL_NONE", "Not saved"))
                    end

                    local capturedSpecID = specID
                    local capturedName   = specName

                    -- Delete
                    local delBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                    delBtn:SetSize(60, 20)
                    delBtn:SetPoint("RIGHT", -4, 0)
                    MakeBg(delBtn, 0.18, 0.10, 0.10, 1)
                    local delTxt = delBtn:CreateFontString(nil, "OVERLAY")
                    ApplyFont(delTxt, 10); delTxt:SetPoint("CENTER")
                    delTxt:SetTextColor(1, 0.5, 0.5); delTxt:SetText(LS("PROFILE_BTN_DELETE", "Delete"))
                    delBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4) end)
                    delBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                    delBtn:SetScript("OnClick", function()
                        if not (BIT.HasSpecProfile and BIT.HasSpecProfile(capturedSpecID)) then return end
                        StaticPopup_Show("BIT_CONFIRM_DELETE_SPEC_PROFILE", capturedName, nil, {
                            specID    = capturedSpecID,
                            onSuccess = function() if f._update then f._update() end end,
                        })
                    end)

                    -- Apply
                    local applyBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                    applyBtn:SetSize(60, 20)
                    applyBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
                    MakeBg(applyBtn, 0.15, 0.15, 0.18, 1)
                    local applyTxt = applyBtn:CreateFontString(nil, "OVERLAY")
                    ApplyFont(applyTxt, 10); applyTxt:SetPoint("CENTER")
                    applyTxt:SetTextColor(RGB(ACCENT)); applyTxt:SetText(LS("PROFILE_BTN_APPLY", "Apply"))
                    applyBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
                    applyBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                    applyBtn:SetScript("OnClick", function()
                        if BIT.ApplySpecProfile and BIT.ApplySpecProfile(capturedSpecID) then
                            applyTxt:SetText("|cFF00FF00Done!|r")
                            C_Timer.After(2, function()
                                applyTxt:SetTextColor(RGB(ACCENT))
                                applyTxt:SetText(LS("PROFILE_BTN_APPLY", "Apply"))
                            end)
                            Refresh()
                        end
                    end)

                    -- Save (only enabled for current spec — you can't save settings of another spec)
                    local saveBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                    saveBtn:SetSize(60, 20)
                    saveBtn:SetPoint("RIGHT", applyBtn, "LEFT", -4, 0)
                    MakeBg(saveBtn, 0.15, 0.15, 0.18, 1)
                    local saveTxt = saveBtn:CreateFontString(nil, "OVERLAY")
                    ApplyFont(saveTxt, 10); saveTxt:SetPoint("CENTER")
                    if specID == curSpec then
                        saveTxt:SetTextColor(RGB(ACCENT)); saveTxt:SetText(LS("PROFILE_BTN_SAVE_SHORT", "Save"))
                        saveBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
                        saveBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                        saveBtn:SetScript("OnClick", function()
                            if BIT.SaveSpecProfile and BIT.SaveSpecProfile(capturedSpecID) then
                                saveTxt:SetText("|cFF00FF00Saved!|r")
                                if f._update then f._update() end
                                C_Timer.After(2, function()
                                    if saveTxt and saveTxt.SetText then
                                        saveTxt:SetTextColor(RGB(ACCENT))
                                        saveTxt:SetText(LS("PROFILE_BTN_SAVE_SHORT", "Save"))
                                    end
                                end)
                            end
                        end)
                    else
                        saveTxt:SetTextColor(RGB(TEXT_DIM))
                        saveTxt:SetText(LS("PROFILE_BTN_SAVE_SHORT", "Save"))
                        saveBtn:EnableMouse(false)
                    end

                    specRows[#specRows+1] = row
                end
            end
            f:SetHeight(math.max(20, numSpecs * (rowH + 2)))
        end
        f._update()
        w[#w+1] = f
    end

    -- ── Role Profiles ────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, LS("PROFILE_ROLE", "Role Profiles"), "sui_prof_role")

    w[#w+1] = CreateToggle(p, LS("PROFILE_AUTO_APPLY_ROLE", "Auto-apply on role change"),
        function() return BIT.db.useRoleProfile end,
        function(v) BIT.db.useRoleProfile = v end)

    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, 10)

        local roleRows   = {}
        local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
        local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

        f._update = function()
            for _, r in ipairs(roleRows) do r:Hide() end
            wipe(roleRows)

            local curRole = BIT.GetCurrentRole and BIT.GetCurrentRole()
            local rowH    = 26
            for i, role in ipairs(ROLE_ORDER) do
                local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
                row:SetSize(f:GetWidth(), rowH)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 2))
                MakeBg(row, i % 2 == 0 and 0.10 or 0.13, 0.10, i % 2 == 0 and 0.10 or 0.13, 1)

                local nameLbl = row:CreateFontString(nil, "OVERLAY")
                ApplyFont(nameLbl, 11)
                nameLbl:SetPoint("LEFT", 8, 0)
                if role == curRole then
                    nameLbl:SetTextColor(1, 0.84, 0)
                    nameLbl:SetText(ROLE_LABEL[role] .. "  |cFF888888(current)|r")
                else
                    nameLbl:SetTextColor(RGB(TEXT))
                    nameLbl:SetText(ROLE_LABEL[role])
                end

                local hasProf = BIT.HasRoleProfile and BIT.HasRoleProfile(role)
                local statusLbl = row:CreateFontString(nil, "OVERLAY")
                ApplyFont(statusLbl, 10)
                statusLbl:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)
                if hasProf then
                    statusLbl:SetTextColor(0.4, 1, 0.4)
                    statusLbl:SetText(LS("PROFILE_GLOBAL_SAVED", "Saved"))
                else
                    statusLbl:SetTextColor(RGB(TEXT_DIM))
                    statusLbl:SetText(LS("PROFILE_GLOBAL_NONE", "Not saved"))
                end

                local capturedRole = role

                -- Delete
                local delBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                delBtn:SetSize(60, 20)
                delBtn:SetPoint("RIGHT", -4, 0)
                MakeBg(delBtn, 0.18, 0.10, 0.10, 1)
                local delTxt = delBtn:CreateFontString(nil, "OVERLAY")
                ApplyFont(delTxt, 10); delTxt:SetPoint("CENTER")
                delTxt:SetTextColor(1, 0.5, 0.5); delTxt:SetText(LS("PROFILE_BTN_DELETE", "Delete"))
                delBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4) end)
                delBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                delBtn:SetScript("OnClick", function()
                    if not (BIT.HasRoleProfile and BIT.HasRoleProfile(capturedRole)) then return end
                    StaticPopup_Show("BIT_CONFIRM_DELETE_ROLE_PROFILE", ROLE_LABEL[capturedRole], nil, {
                        role      = capturedRole,
                        onSuccess = function() if f._update then f._update() end end,
                    })
                end)

                -- Apply
                local applyBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                applyBtn:SetSize(60, 20)
                applyBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
                MakeBg(applyBtn, 0.15, 0.15, 0.18, 1)
                local applyTxt = applyBtn:CreateFontString(nil, "OVERLAY")
                ApplyFont(applyTxt, 10); applyTxt:SetPoint("CENTER")
                applyTxt:SetTextColor(RGB(ACCENT)); applyTxt:SetText(LS("PROFILE_BTN_APPLY", "Apply"))
                applyBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
                applyBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                applyBtn:SetScript("OnClick", function()
                    if BIT.ApplyRoleProfile and BIT.ApplyRoleProfile(capturedRole) then
                        applyTxt:SetText("|cFF00FF00Done!|r")
                        C_Timer.After(2, function()
                            applyTxt:SetTextColor(RGB(ACCENT))
                            applyTxt:SetText(LS("PROFILE_BTN_APPLY", "Apply"))
                        end)
                        Refresh()
                    end
                end)

                -- Save (always enabled — saves current settings into this role slot)
                local saveBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                saveBtn:SetSize(60, 20)
                saveBtn:SetPoint("RIGHT", applyBtn, "LEFT", -4, 0)
                MakeBg(saveBtn, 0.15, 0.15, 0.18, 1)
                local saveTxt = saveBtn:CreateFontString(nil, "OVERLAY")
                ApplyFont(saveTxt, 10); saveTxt:SetPoint("CENTER")
                saveTxt:SetTextColor(RGB(ACCENT)); saveTxt:SetText(LS("PROFILE_BTN_SAVE_SHORT", "Save"))
                saveBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
                saveBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
                saveBtn:SetScript("OnClick", function()
                    if BIT.SaveRoleProfile and BIT.SaveRoleProfile(capturedRole) then
                        saveTxt:SetText("|cFF00FF00Saved!|r")
                        if f._update then f._update() end
                        C_Timer.After(2, function()
                            if saveTxt and saveTxt.SetText then
                                saveTxt:SetTextColor(RGB(ACCENT))
                                saveTxt:SetText(LS("PROFILE_BTN_SAVE_SHORT", "Save"))
                            end
                        end)
                    end
                end)

                roleRows[#roleRows+1] = row
            end
            f:SetHeight(#ROLE_ORDER * (rowH + 2))
        end
        f._update()
        w[#w+1] = f
    end

    -- ── Export ───────────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, "Export", "sui_prof_export")

    -- Export checkboxes + button + output box
    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, 110)

        -- checkboxes
        local chkSettings = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        chkSettings:SetSize(20, 20)
        chkSettings:SetPoint("TOPLEFT", 0, 0)
        chkSettings:SetChecked(true)
        local chkSettingsLbl = f:CreateFontString(nil, "OVERLAY")
        ApplyFont(chkSettingsLbl, 11)
        chkSettingsLbl:SetPoint("LEFT", chkSettings, "RIGHT", 4, 0)
        chkSettingsLbl:SetTextColor(RGB(TEXT))
        chkSettingsLbl:SetText("Settings")

        local chkPos = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        chkPos:SetSize(20, 20)
        chkPos:SetPoint("LEFT", chkSettingsLbl, "RIGHT", 16, 0)
        chkPos:SetChecked(false)
        local chkPosLbl = f:CreateFontString(nil, "OVERLAY")
        ApplyFont(chkPosLbl, 11)
        chkPosLbl:SetPoint("LEFT", chkPos, "RIGHT", 4, 0)
        chkPosLbl:SetTextColor(RGB(TEXT))
        chkPosLbl:SetText("Position")

        -- Export output box
        local exportBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        exportBox:SetSize(f:GetWidth(), 22)
        exportBox:SetPoint("TOPLEFT", 0, -28)
        MakeBg(exportBox, RGB(WIDGET_BG))
        exportBox:SetAutoFocus(false)
        ApplyFont(exportBox, 10)
        exportBox:SetTextColor(RGB(TEXT))
        exportBox:SetTextInsets(6, 6, 0, 0)
        exportBox:SetText("")
        exportBox._val = ""
        exportBox:SetScript("OnChar", function(self) self:SetText(self._val or "") end)
        exportBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        -- Export button
        local exportBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        exportBtn:SetSize(100, 24)
        exportBtn:SetPoint("TOPLEFT", 0, -56)
        MakeBg(exportBtn, 0.15, 0.15, 0.18, 1)

        local exportTxt = exportBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(exportTxt, 11)
        exportTxt:SetPoint("CENTER")
        exportTxt:SetTextColor(RGB(ACCENT))
        exportTxt:SetText("Export")

        exportBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        exportBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        exportBtn:SetScript("OnClick", function()
            local s = chkSettings:GetChecked()
            local pos = chkPos:GetChecked()
            if not s and not pos then
                exportBox:SetText("Select at least one option.")
                return
            end
            local str = BIT.ExportProfile(s, pos)
            exportBox._val = str
            exportBox:SetText(str)
            exportBox:HighlightText()
            exportBox:SetFocus()
        end)

        w[#w+1] = f
    end

    -- ── Import ──────────────────────────────────────────
    w[#w+1] = CreateSectionHeader(p, "Import", "sui_prof_import")

    do
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(p:GetWidth() - CONTENT_PAD * 2, 80)

        -- Import input box
        local importBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        importBox:SetSize(f:GetWidth(), 22)
        importBox:SetPoint("TOPLEFT", 0, 0)
        MakeBg(importBox, RGB(WIDGET_BG))
        importBox:SetAutoFocus(false)
        ApplyFont(importBox, 10)
        importBox:SetTextColor(RGB(TEXT))
        importBox:SetTextInsets(6, 6, 0, 0)
        importBox:SetText("")
        importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        -- Status label
        local statusLbl = f:CreateFontString(nil, "OVERLAY")
        ApplyFont(statusLbl, 11)
        statusLbl:SetPoint("TOPLEFT", 0, -56)
        statusLbl:SetTextColor(RGB(TEXT_DIM))
        statusLbl:SetText("")

        -- Import button
        local importBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        importBtn:SetSize(100, 24)
        importBtn:SetPoint("TOPLEFT", 0, -28)
        MakeBg(importBtn, 0.15, 0.15, 0.18, 1)

        local importTxt = importBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(importTxt, 11)
        importTxt:SetPoint("CENTER")
        importTxt:SetTextColor(RGB(ACCENT))
        importTxt:SetText("Import")

        importBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        importBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        importBtn:SetScript("OnClick", function()
            local str = importBox:GetText()
            local ok, msg = BIT.ImportProfile(str)
            if ok then
                statusLbl:SetTextColor(0.2, 1.0, 0.2)
                statusLbl:SetText(msg)
                importBox:SetText("")
                -- Refresh current page widgets after import
                if activePage and pages[activePage] and pages[activePage].refresh then
                    pages[activePage].refresh()
                end
            else
                statusLbl:SetTextColor(1.0, 0.3, 0.3)
                statusLbl:SetText(msg)
            end
        end)

        -- Clear button
        local clearBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        clearBtn:SetSize(80, 24)
        clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
        MakeBg(clearBtn, 0.15, 0.15, 0.18, 1)

        local clearTxt = clearBtn:CreateFontString(nil, "OVERLAY")
        ApplyFont(clearTxt, 11)
        clearTxt:SetPoint("CENTER")
        clearTxt:SetTextColor(RGB(TEXT_DIM))
        clearTxt:SetText("Clear")

        clearBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(RGB(ACCENT)) end)
        clearBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(RGB(BORDER)) end)
        clearBtn:SetScript("OnClick", function()
            importBox:SetText("")
            statusLbl:SetText("")
        end)

        w[#w+1] = f
    end

    return w
end

------------------------------------------------------------
-- ── ShowPage ─────────────────────────────────────────────
------------------------------------------------------------
function BIT.SettingsUI:ShowPage(name)
    if not pages[name] then return end

    -- hide old widgets
    if activePage and pages[activePage] and pages[activePage].widgets then
        for _, w in ipairs(pages[activePage].widgets) do w:Hide() end
    end

    -- update sidebar
    for k, btn in pairs(sidebarBtns) do
        if k == name then
            btn._indicator:Show()
            btn._bgHl:Show()
            btn._text:SetTextColor(RGB(TEXT))
        else
            btn._indicator:Hide()
            btn._bgHl:Hide()
            btn._text:SetTextColor(RGB(TEXT_DIM))
        end
    end

    activePage = name
    local page = pages[name]

    -- build on first show
    if not page.widgets then
        page.widgets = page.build()
    end

    -- layout
    page.layout = function() LayoutWidgets(page.widgets) end
    page.refresh = function()
        for _, w in ipairs(page.widgets) do
            if w._update then w._update() end
        end
    end

    -- Run every widget's `_update` callback now that `page.layout` exists.
    -- This is essential for `_dynamic` widgets whose visibility depends on
    -- other settings (e.g. mode-scoped options in the Interrupts page):
    -- their `_update` closures call `page.layout()` internally, and that
    -- closure only has a layout to invoke after this function is assigned.
    page.refresh()
    page.layout()

    contentScroll:SetVerticalScroll(0)
end

------------------------------------------------------------
-- ── Public API ───────────────────────────────────────────
------------------------------------------------------------
function BIT.SettingsUI:Toggle()
    if not mainFrame then
        self:Init()
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        if not activePage then
            self:ShowPage("General")
        end
    end
end

function BIT.SettingsUI:Init()
    L = BIT.L

    CreateMainFrame()

    -- Register pages
    RegisterPage("General",        BuildGeneral)
    RegisterPage("Interrupts",     BuildInterrupts)
    RegisterPage("Size & Font",    BuildSizeFont)
    RegisterPage("Colors",         BuildColors)
    RegisterPage("Party CDs",      BuildPartyCDs)
    RegisterPage("Smart Misdirect",BuildSmartMisdirect)
    RegisterPage("Profiles",       BuildProfiles)

    -- Create sidebar buttons
    CreateSidebarBtn(1, "General",        136243) -- Interface/misc
    CreateSidebarBtn(2, "Interrupts",     236281) -- Ability_kick
    CreateSidebarBtn(3, "Size & Font",    134063) -- inv_misc_note_01
    CreateSidebarBtn(4, "Colors",         134572) -- inv_misc_gem_variety1
    CreateSidebarBtn(5, "Party CDs",      236440) -- Spell_holy_powerwordbarrier
    -- Smart Misdirect: only show sidebar entry for Hunter / Rogue so the page
    -- is invisible to classes that cannot use the feature.
    local _cls = BIT.Self and BIT.Self.class or BIT.myClass
    local _smdIdx = 6
    if _cls == "HUNTER" or _cls == "ROGUE" then
        CreateSidebarBtn(6, "Smart Misdirect", 132180) -- ability_hunter_misdirection
        _smdIdx = 7
    end
    CreateSidebarBtn(_smdIdx, "Profiles",  134400) -- inv_misc_note_05

    -- Adjust contentChild width after frame is visible
    mainFrame:HookScript("OnShow", function()
        contentChild:SetWidth(WIN_W - SIDEBAR_W - 26)
    end)
end

------------------------------------------------------------
-- ── Slash command hook (called from Core.lua) ────────────
------------------------------------------------------------
function BIT.SettingsUI:HookSlash()
    -- Override existing slash commands to open our UI
    SLASH_BLIZZI1       = "/blizzi"
    SLASH_BLIZZI2       = "/bitset"
    SLASH_BLIZZI3       = "/bliset"
    SLASH_BLIZZI4       = "/interrupts"
    SlashCmdList["BLIZZI"] = function(msg)
        msg = strtrim(msg or "")
        if msg == "rotation" or msg == "rot" then
            if BIT.Rotation and BIT.Rotation.ToggleEditor then BIT.Rotation:ToggleEditor() end
        elseif msg == "profile" then
            BIT.SettingsUI:Toggle()
            BIT.SettingsUI:ShowPage("Profiles")
        elseif msg == "test" then
            BIT.testMode = not BIT.testMode
            print("|cff0091edBIT|r Test mode " .. (BIT.testMode and "ON" or "OFF"))
        elseif msg == "debug" then
            BIT.debugMode = not BIT.debugMode
            print("|cff0091edBIT|r Debug mode " .. (BIT.debugMode and "ON" or "OFF"))
        else
            BIT.SettingsUI:Toggle()
        end
    end
end

------------------------------------------------------------
-- ── Minimap Button (LibDBIcon) ──────────────────────────
------------------------------------------------------------
function BIT.SettingsUI:CreateMinimapButton()
    if self.minimapBtn then return end

    local ldb  = LibStub and LibStub("LibDataBroker-1.1", true)
    local ldbi = LibStub and LibStub("LibDBIcon-1.0", true)
    if not ldb or not ldbi then return end

    local ICON = "Interface\\AddOns\\BliZzi_Interrupts\\Media\\icon"

    -- Create a LibDataBroker data object (like BugSack does)
    local dataObj = ldb:NewDataObject("BliZziInterrupts", {
        type = "data source",
        text = "BliZzi Interrupts",
        icon = ICON,
        OnClick = function(_, button)
            if IsShiftKeyDown() then
                BIT:StartTestMode()
            elseif button == "LeftButton" then
                BIT.SettingsUI:Toggle()
            elseif button == "RightButton" then
                if BIT.UI and BIT.UI.ShowRotationPanel then
                    BIT.UI:ShowRotationPanel()
                end
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cff0091edBliZzi|r|cffffa300Interrupts|r", 1, 1, 1)
            tt:AddLine(" ")
            tt:AddLine("|cFFFFD700Left-Click|r  Open Settings", 0.8, 0.8, 0.8)
            tt:AddLine("|cFFFFD700Right-Click|r  Kick Rotation", 0.8, 0.8, 0.8)
            tt:AddLine("|cFFFFD700Shift-Click|r  Toggle Test Mode", 0.8, 0.8, 0.8)
            tt:AddLine("|cFFFFD700Drag|r  Move Button", 0.8, 0.8, 0.8)
        end,
    })

    -- Initialize the SavedVariable DB for icon position/visibility
    if not BliZziInterruptsMinimapDB then
        BliZziInterruptsMinimapDB = {}
    end

    -- Migrate old position if user had the custom minimap button before
    if BIT.db.minimapPos and not BliZziInterruptsMinimapDB.minimapPos then
        BliZziInterruptsMinimapDB.minimapPos = BIT.db.minimapPos
    end
    if BIT.db.minimapButton == false and BliZziInterruptsMinimapDB.hide == nil then
        BliZziInterruptsMinimapDB.hide = true
    end

    -- Register with LibDBIcon — handles positioning, dragging, border, background
    ldbi:Register("BliZziInterrupts", dataObj, BliZziInterruptsMinimapDB)

    self.minimapBtn = ldbi:GetMinimapButton("BliZziInterrupts")
end
