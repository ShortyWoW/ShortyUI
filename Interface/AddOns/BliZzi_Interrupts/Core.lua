-- Copyright (c) 2026 BliZzi1337. All rights reserved.
-- Unauthorized copying, modification, distribution or use of this
-- software, in whole or in part, without prior written permission
-- from the copyright holder is strictly prohibited.
--[[
    Core.lua - BliZzi Interrupts
    -----------------------------------------------------------------------
    Module-based architecture:
      BIT.Taint    — tainted spell-ID resolution
      BIT.Net      — addon message communication
      BIT.Self     — own player state
      BIT.Registry — party member registry
      BIT.Inspect  — inspect queue
      BIT.Rotation — kick rotation
    -----------------------------------------------------------------------
]]

BIT = BIT or {}
BIT.VERSION    = "3.3.6"
BIT.SyncCD      = BIT.SyncCD      or {}
BIT.SyncCD.users = BIT.SyncCD.users or {}  -- name → {class, specID} — only HELLO senders, never touched by interrupt system
BIT.syncCdState = BIT.syncCdState or {}

------------------------------------------------------------
-- Shared runtime flags
------------------------------------------------------------
BIT.ready      = false
BIT.inCombat   = false
BIT.testMode   = false
BIT.debugMode  = false
BIT.devLogMode = false  -- silent log: captures to buffer, no chat output

------------------------------------------------------------
-- Dev log buffer (in-memory circular buffer, max 600 entries)
-- Used by /bitdevlog + /bitdevdump for post-run analysis.
------------------------------------------------------------
do
    local _buf     = {}
    local _BUF_MAX = 2000   -- large enough for a full M+ attempt
    local _t0      = GetTime()

    -- BIT.DevLog(msg): verbose/spammy events → buffer only, never chat.
    --   Activate with /bitdevlog, review with /bitdevdump [N] [filter].
    --   Important events (GLOW-ON, AURA-MATCH, etc.) use plain print()
    --   when BIT.debugMode is on — those are NOT routed through here.
    function BIT.DevLog(msg)
        if not BIT.devLogMode then return end
        local rel   = string.format("%7.2f", GetTime() - _t0)
        local entry = "[" .. rel .. "] " .. msg
        _buf[#_buf + 1] = entry
        if #_buf > _BUF_MAX then table.remove(_buf, 1) end
    end

    function BIT.DevLogStart()
        _buf = {}
        _t0  = GetTime()
    end

    -- /bitdevdump [N] [filter]
    -- N       = how many lines to show (default 80, 0 = all)
    -- filter  = optional keyword; only lines containing it are shown
    function BIT.DevLogDump(args)
        local nStr, filter = (args or ""):match("^(%S*)%s*(.-)%s*$")
        local n = tonumber(nStr) == 0 and #_buf or (tonumber(nStr) or 80)
        if #_buf == 0 then
            print("|cffff9900BIT DevLog|r buffer is empty — use /bitdevlog to start")
            return
        end
        local matched = {}
        for i = math.max(1, #_buf - n + 1), #_buf do
            if filter == "" or _buf[i]:find(filter, 1, true) then
                matched[#matched + 1] = _buf[i]
            end
        end
        local filterNote = filter ~= "" and (" filter=|cffffd700" .. filter .. "|r") or ""
        print("|cffff9900BIT DevLog|r === " .. #matched .. " lines" .. filterNote .. " (buffer: " .. #_buf .. ") ===")
        for _, line in ipairs(matched) do print(line) end
        print("|cffff9900BIT DevLog|r === end ===")
    end

    -- Returns a shallow copy of the log buffer for use by the report window.
    function BIT.DevLogGetBuffer()
        local copy = {}
        for i = 1, #_buf do copy[i] = _buf[i] end
        return copy
    end

    -- Returns recording start time so the report can show elapsed time.
    function BIT.DevLogGetStartTime() return _t0 end
end

------------------------------------------------------------
-- Effective custom name resolver
-- Returns the nickname that should be broadcast for this
-- character. If "Use Global Custom Name" is enabled, the
-- account-wide globalCustomName wins; otherwise the
-- per-character charDb.myCustomName is used.
------------------------------------------------------------
function BIT.GetEffectiveCustomName()
    if not BIT.db then return "" end
    if BIT.db.useGlobalCustomName and BIT.db.globalCustomName and BIT.db.globalCustomName ~= "" then
        return BIT.db.globalCustomName
    end
    local perChar = BIT.charDb and BIT.charDb.myCustomName
    if perChar and perChar ~= "" then return perChar end
    return ""
end

------------------------------------------------------------
-- Custom display name lookup
-- Returns the user-defined nickname for a player, or the
-- original name if no custom name is set.
------------------------------------------------------------
function BIT.GetDisplayName(name)
    if not name then return nil end
    if not (BIT.db and BIT.db.showCustomNames ~= false) then return name end
    -- Own custom name
    if name == BIT.myName then
        local own = BIT.GetEffectiveCustomName and BIT.GetEffectiveCustomName() or ""
        if own ~= "" then return own end
    end
    -- Custom name received from other addon users
    local users = BIT.SyncCD and BIT.SyncCD.users
    if users then
        local u = users[name]
        if u and u.customName then return u.customName end
    end
    return name
end

------------------------------------------------------------
-- BIT.Taint  — resolve tainted spell IDs from C-land
-- Uses a hidden Slider whose OnValueChanged callback fires
-- from C++ context, stripping the taint from secret values.
------------------------------------------------------------
do
    local _slider = CreateFrame("Slider", nil, UIParent)
    _slider:SetMinMaxValues(0, 9999999)
    _slider:SetSize(1, 1)
    _slider:Hide()

    local _result = nil
    _slider:SetScript("OnValueChanged", function(_, v) _result = v end)

    BIT.Taint = {}

    --- Attempt to resolve a (possibly tainted) spell ID.
    --- Returns the canonical interrupt spell ID, or nil.
    function BIT.Taint:Resolve(rawID)
        _result = nil

        -- Fast path: untainted numeric ID works directly
        local directOk, directHit = pcall(function()
            return BIT.ALL_INTERRUPTS[rawID]
        end)
        if directOk and directHit then
            return BIT.SPELL_ALIASES[rawID] or rawID
        end

        -- String path: tostring() often works even on tainted values.
        -- NOTE: tostring() on a tainted value returns a *tainted* string in WoW.
        --       A tainted string still cannot be used as a table index, so every
        --       lookup that uses idStr must itself be wrapped in pcall.
        local strOk, idStr = pcall(tostring, rawID)
        if strOk and idStr then
            local aliasOk, aliasTarget = pcall(function()
                return BIT.SPELL_ALIASES_STR[idStr]
            end)
            if aliasOk and aliasTarget then
                local hitOk, hit = pcall(function()
                    return BIT.ALL_INTERRUPTS[aliasTarget]
                end)
                if hitOk and hit then
                    return aliasTarget
                end
            end
            local hitOk, hit = pcall(function()
                return BIT.ALL_INTERRUPTS_STR[idStr]
            end)
            if hitOk and hit then
                local numOk, num = pcall(tonumber, idStr)
                return (numOk and num) or nil
            end
        end

        -- Slider path: push value through C++ OnValueChanged to strip taint.
        -- IMPORTANT: the two SetValue calls must be in SEPARATE pcalls.
        -- If they share one pcall, SetValue(0) fires OnValueChanged(_result=0),
        -- then SetValue(rawID) fails silently (tainted) — leaving _result=0,
        -- which the _result~=0 guard below rejects, giving a false nil.
        pcall(_slider.SetValue, _slider, 0)   -- reset; may set _result=0
        _result = nil                          -- clear so we know if rawID fires
        local sliderOk = pcall(_slider.SetValue, _slider, rawID)

        if sliderOk and _result and _result ~= 0 then
            local s = tostring(_result)
            if BIT.ALL_INTERRUPTS_STR[s] then
                if BIT.debugMode then
                    print("|cff0091edBliZzi|r|cffffa300Interrupts|r |cFFAAAAAA[DBG]|r Taint.Resolve: " .. BIT.ALL_INTERRUPTS_STR[s].name
                          .. " (str=" .. s .. ") via slider")
                end
                local num = tonumber(s)
                return num and (BIT.SPELL_ALIASES[num] or num) or nil
            end
        end

        return nil
    end
end

------------------------------------------------------------
-- BIT.Net  — addon message communication
--
-- Protocol (v1, pipe-free semicolon format):
--   B1;HELLO;class;spellID;cd    — announce self on join (requires interrupt spell)
--   B1;HELLOSYNC;class           — announce self for Party CDs (works without interrupt)
--   B1;KICK;spellID;cd           — own interrupt cast
--   B1;ROT;p1,p2,...;idx         — full rotation broadcast
--   B1;RIDX;idx                  — rotation index update only
------------------------------------------------------------
local recentCasts = {}   -- name → { t, spellID } — last known interrupt cast per player
------------------------------------------------------------
do
    local PREFIX  = "BliZziIT"
    local HDR     = "B1"
    local SEP     = ";"

    BIT.Net = {}

    -- Send to party. Covers home groups, instance groups (M+/LFG), and raids.
    -- Falls back to whispering each member only when all broadcast channels fail.
    local function Transmit(payload)
        local inHome     = IsInGroup(LE_PARTY_CATEGORY_HOME)
        local inInstance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)

        if BIT.debugMode then
            print(string.format(
                "BIT-NET Transmit: inHome=%s inInstance=%s LE_HOME=%s LE_INST=%s payload=%s",
                tostring(inHome), tostring(inInstance),
                tostring(LE_PARTY_CATEGORY_HOME), tostring(LE_PARTY_CATEGORY_INSTANCE),
                tostring(payload):sub(1, 60)))
        end

        if inHome or inInstance then
            -- ret == 0 means success in Midnight's C_ChatInfo.SendAddonMessage.
            -- ret == 11 means Timed M+ has blocked all addon channels.
            -- Any other value (e.g. 5 = not in instance) is an error — do NOT
            -- treat non-zero ret as success (non-zero is truthy in Lua but wrong).
            local channel = inInstance and "INSTANCE_CHAT" or "PARTY"
            local ok, ret = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, channel)
            if BIT.debugMode then
                print(string.format("BIT-NET   %s send: ok=%s ret=%s", channel, tostring(ok), tostring(ret)))
            end
            if ok and ret == 0 then
                BIT._addonMsgBlocked = false   -- messages are working
                return
            end
            if ok and ret == 11 then BIT._addonMsgBlocked = true end  -- Timed M+ block
            -- INSTANCE_CHAT failed (ret≠0) → try PARTY as fallback
            if inInstance then
                ok, ret = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, "PARTY")
                if BIT.debugMode then
                    print(string.format("BIT-NET   PARTY fallback: ok=%s ret=%s", tostring(ok), tostring(ret)))
                end
                if ok and ret == 0 then
                    BIT._addonMsgBlocked = false
                    return
                end
                if ok and ret == 11 then BIT._addonMsgBlocked = true end
            end
        end

        -- Last resort: whisper each party member individually
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitIsPlayer(u) then
                local ok, name, realm = pcall(UnitFullName, u)
                if ok and name then
                    local target = (realm and realm ~= "") and (name .. "-" .. realm) or name
                    local wok, wret = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", target)
                    if BIT.debugMode then
                        print(string.format("BIT-NET   WHISPER->%s: ok=%s ret=%s", target, tostring(wok), tostring(wret)))
                    end
                    if wok and wret == 0 then BIT._addonMsgBlocked = false end
                    if wok and wret == 11 then BIT._addonMsgBlocked = true end
                end
            end
        end
    end

    local function Msg(...) return table.concat({HDR, ...}, SEP) end

    function BIT.Net:AnnounceHello(class, spellID, cd)
        local cn = BIT.GetEffectiveCustomName and BIT.GetEffectiveCustomName() or ""
        if cn ~= "" then
            Transmit(Msg("HELLO", class, spellID, cd, cn))
        else
            Transmit(Msg("HELLO", class, spellID, cd))
        end
    end

    function BIT.Net:AnnounceKick(spellID, cd)
        Transmit(Msg("KICK", spellID, cd))
    end

    function BIT.Net:AnnounceFailedKick()
        Transmit(Msg("FAILKICK"))
    end

    function BIT.Net:AnnounceSuccessKick()
        Transmit(Msg("SUCCESSKICK"))
    end

    function BIT.Net:AnnounceSync(spellID, duration)
        Transmit(Msg("SYNCCD", spellID, duration))
    end

    function BIT.Net:AnnounceSyncHello(class)
        local cn = BIT.GetEffectiveCustomName and BIT.GetEffectiveCustomName() or ""
        -- Include own specID so receivers don't need to inspect
        local specID = ""
        local idx = GetSpecialization and GetSpecialization()
        if idx then
            local sid = select(1, GetSpecializationInfo(idx))
            if sid then specID = tostring(sid) end
        end
        if cn ~= "" then
            Transmit(Msg("HELLOSYNC", class, cn, specID))
        else
            Transmit(Msg("HELLOSYNC", class, "", specID))
        end
    end

    function BIT.Net:SyncRotation(order, idx)
        Transmit(Msg("ROT", table.concat(order, ","), idx))
    end

    function BIT.Net:SyncRotationIndex(idx)
        Transmit(Msg("RIDX", idx))
    end

    -- Dispatch table: command → handler(parts, senderName)
    local dispatch = {}

    dispatch["HELLO"] = function(parts, sender)
        local cls    = parts[3]
        local sid    = tonumber(parts[4])
        local baseCd = tonumber(parts[5])
        local customName = parts[6] and parts[6] ~= "" and parts[6] or nil
        if BIT.debugMode then
            print(string.format("BIT-NET HELLO from %s: cls=%s sid=%s classOk=%s spellOk=%s cn=%s",
                tostring(sender), tostring(cls), tostring(sid),
                tostring(cls and BIT.CLASS_COLORS[cls] ~= nil),
                tostring(sid and BIT.ALL_INTERRUPTS[sid] ~= nil),
                tostring(customName)))
        end
        if cls and BIT.CLASS_COLORS[cls] and sid and BIT.ALL_INTERRUPTS[sid] then
            local entry      = BIT.Registry:GetOrCreate(sender)
            entry.class      = cls
            entry.spellID    = sid
            entry.isNonAddon = nil   -- legacy cleanup
            if baseCd and baseCd > 0 then entry.baseCd = baseCd end
            BIT.Registry:MarkAddon(sender)
            -- populate SyncCD's own user table (independent of interrupt registry)
            if BIT.SyncCD and BIT.SyncCD.users then
                BIT.SyncCD.users[sender] = BIT.SyncCD.users[sender] or {}
                BIT.SyncCD.users[sender].class      = cls
                BIT.SyncCD.users[sender]._hasAddon   = true
                BIT.SyncCD.users[sender].customName  = customName
            end
            BIT.Self:BroadcastHello()
            BIT.Inspect:Invalidate(sender)
            -- rebuild SyncCD (LibSpec will provide talent data asynchronously)
            C_Timer.After(0.1, function()
                if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
            end)
            C_Timer.After(3.0, function()
                if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
            end)
        end
    end

    dispatch["HELLOSYNC"] = function(parts, sender)
        local cls = parts[3]
        local customName = parts[4] and parts[4] ~= "" and parts[4] or nil
        local specID     = tonumber(parts[5])  -- added: sender includes own specID
        if BIT.debugMode then
            print(string.format("BIT-NET HELLOSYNC from %s: cls=%s classOk=%s cn=%s spec=%s",
                tostring(sender), tostring(cls),
                tostring(cls and BIT.CLASS_COLORS[cls] ~= nil),
                tostring(customName), tostring(specID)))
        end
        if not cls or not BIT.CLASS_COLORS[cls] then return end
        if BIT.SyncCD and BIT.SyncCD.users then
            BIT.SyncCD.users[sender] = BIT.SyncCD.users[sender] or {}
            BIT.SyncCD.users[sender].class      = cls
            BIT.SyncCD.users[sender]._hasAddon   = true
            BIT.SyncCD.users[sender].customName  = customName
            -- Use specID from message immediately (no inspect wait needed)
            if specID and specID > 0 then
                BIT.SyncCD.users[sender].specID = specID
            end
        end
        -- reply once so the sender also knows about us
        BIT.Self:BroadcastSyncHello()
        BIT.Inspect:Invalidate(sender)
        C_Timer.After(0.1, function()
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)
        C_Timer.After(3.0, function()
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
        end)
    end

    dispatch["KICK"] = function(parts, sender)
        local sid = tonumber(parts[3])
        local cd  = tonumber(parts[4])
        if cd and cd > 0 then
            -- update recentCasts for mob-interrupt correlation
            if sid then recentCasts[sender] = { t = GetTime(), spellID = sid } end
            local entry = BIT.Registry:Get(sender)
            if entry then
                local now = GetTime()

                -- Check if sid belongs to an extraKick bar (e.g. Fel Ravager 132409
                -- for a Demonology Warlock whose main spell is Axe Toss 119914).
                -- If so, update that specific extraKick cdEnd instead of the main bar.
                local routedToExtra = false
                if sid and entry.extraKicks then
                    for _, ek in ipairs(entry.extraKicks) do
                        if ek.spellID == sid then
                            ek.cdEnd = now + cd
                            routedToExtra = true
                            break
                        end
                    end
                end

                if not routedToExtra then
                    -- Normal case: update main interrupt bar
                    entry.cdEnd  = now + cd
                    entry.baseCd = cd
                end

                BIT.Rotation:OnKick(sender)
                if BIT.debugMode then
                    local nm = sid and BIT.ALL_INTERRUPTS[sid] and BIT.ALL_INTERRUPTS[sid].name or "?"
                    print("|cff0091edBliZzi|r|cffffa300Interrupts|r |cFFAAAAAA[DBG]|r KICK msg: " .. sender .. " → " .. nm
                          .. " cd=" .. cd .. "s" .. (routedToExtra and " [extraKick]" or ""))
                end
            end
        end
    end

    dispatch["ROT"] = function(parts, sender)
        local playerStr = parts[3]
        local idx       = tonumber(parts[4])
        if playerStr and idx then
            local names = {}
            for n in playerStr:gmatch("[^,]+") do names[#names+1] = n end
            BIT.Rotation:ApplySync(names, idx)
        end
    end

    dispatch["RIDX"] = function(parts, sender)
        local idx = tonumber(parts[3])
        if idx then BIT.Rotation:ApplyIndex(idx) end
    end

    dispatch["FAILKICK"] = function(parts, sender)
        if BIT.db.showFailedKick and BIT.UI and BIT.UI.FlashFailedKick then
            BIT.UI:FlashFailedKick(sender)
        end
    end

    dispatch["SUCCESSKICK"] = function(parts, sender)
        if BIT.db.showFailedKick and BIT.UI and BIT.UI.MarkSuccessKick then
            BIT.UI:MarkSuccessKick(sender)
        end
    end

    dispatch["SYNCCD"] = function(parts, sender)
        -- SYNCCD network sync disabled; CD tracking runs via aura detection only.
        -- CD reductions (negative dur) are still applied for OnCDReduced mechanics.
        local sid = tonumber(parts[3])
        local dur = tonumber(parts[4])
        if not (sid and dur and BIT.SyncCD) then return end
        if dur < 0 then
            if BIT.SyncCD.OnCDReduced then
                BIT.SyncCD:OnCDReduced(sender, sid, -dur)
            end
        end
    end

    -- PING handler: always prints so receive-test works without debugMode
    dispatch["PING"] = function(parts, sender)
        print("|cff00ff80BIT-NET|r PING RECEIVED from " .. tostring(sender)
              .. " — addon communication working!")
    end

    function BIT.Net:OnMessage(msgPrefix, message, channel, sender)
        if BIT.debugMode and msgPrefix == PREFIX then
            print(string.format("BIT-NET RECV: prefix=%s channel=%s sender=%s msg=%s",
                tostring(msgPrefix), tostring(channel), tostring(sender),
                tostring(message):sub(1, 80)))
        end
        if msgPrefix ~= PREFIX then return end
        local shortName = Ambiguate(sender, "short")
        local parts = { strsplit(SEP, message) }
        if parts[1] ~= HDR then return end
        local cmd = parts[2]
        if shortName == BIT.Self.name then return end
        local handler = dispatch[cmd]
        if handler then handler(parts, shortName) end
    end

    function BIT.Net:Register()
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
end

------------------------------------------------------------
-- BIT.Registry  — party member state
------------------------------------------------------------
do
    BIT.Registry = {}
    local _data = {}   -- name → entry table
    local _addonUsers = {}  -- name → true, only players who sent HELLO

    function BIT.Registry:Get(name)     return _data[name] end
    function BIT.Registry:Remove(name)  _data[name] = nil end  -- does NOT remove from addonUsers
    function BIT.Registry:All()         return _data end
    function BIT.Registry:AddonUsers()  return _addonUsers end
    function BIT.Registry:MarkAddon(name) _addonUsers[name] = true end
    function BIT.Registry:RemoveFromGroup(name)  -- call when player leaves group
        _data[name] = nil
        _addonUsers[name] = nil
    end

    function BIT.Registry:GetOrCreate(name)
        if not _data[name] then
            _data[name] = { cdEnd = 0 }
        end
        return _data[name]
    end

    function BIT.Registry:Purge(keepNames)
        for name in pairs(_data) do
            if not keepNames[name] then _data[name] = nil end
        end
        -- only remove addon users who are no longer in group
        for name in pairs(_addonUsers) do
            if not keepNames[name] then _addonUsers[name] = nil end
        end
    end

    function BIT.Registry:Clear()
        for k in pairs(_data) do _data[k] = nil end
        for k in pairs(_addonUsers) do _addonUsers[k] = nil end
    end

    -- back-compat alias used by UI.lua / Profile.lua
    BIT.partyAddonUsers = _data
end

------------------------------------------------------------
-- BIT.Self  — own player state + helpers
------------------------------------------------------------
do
    BIT.Self = {
        name        = nil,
        class       = nil,
        spellID     = nil,
        baseCd      = nil,
        cachedCd    = nil,
        kickCdEnd   = 0,
        isPetSpell  = false,
        extraKicks  = {},   -- spellID → { baseCd, cdEnd, name, icon }
        lastHello   = 0,
    }

    -- Back-compat aliases used by UI.lua and other modules
    -- (kept as references so mutations stay in sync)
    local S = BIT.Self
    BIT.myName       = nil  -- updated on init
    BIT.myClass      = nil
    BIT.mySpellID    = nil
    BIT.myCachedCD   = nil
    BIT.myBaseCd     = nil
    BIT.myKickCdEnd  = 0
    BIT.myIsPetSpell = false
    BIT.myExtraKicks = {}

    local function SyncCompat()
        BIT.myName       = S.name
        BIT.myClass      = S.class
        BIT.mySpellID    = S.spellID
        BIT.myCachedCD   = S.cachedCd
        BIT.myBaseCd     = S.baseCd
        BIT.myKickCdEnd  = S.kickCdEnd
        BIT.myIsPetSpell = S.isPetSpell
        BIT.myExtraKicks = S.extraKicks
    end

    function BIT.Self:UpdateFromPlayer()
        self.name  = UnitName("player")
        local _, cls = UnitClass("player")
        self.class = cls
        SyncCompat()
    end

    function BIT.Self:ReadBaseCd()
        if not self.spellID then return end
        -- Trust spec-override CD; only let cachedCd refine it
        local specIndex = GetSpecialization()
        local specID    = specIndex and GetSpecializationInfo(specIndex)
        local ov = specID and BIT.SPEC_INTERRUPT_OVERRIDES[specID]
        if ov and ov.id == self.spellID then
            if self.cachedCd and self.cachedCd > 1.5 then
                self.baseCd = self.cachedCd
            end
            SyncCompat(); return
        end
        local ok, ms = pcall(GetSpellBaseCooldown, self.spellID)
        if ok and ms then
            local clean = tonumber(string.format("%.0f", ms))
            if clean and clean > 0 then self.baseCd = clean / 1000 end
        end
        if self.cachedCd and self.cachedCd > 1.5 then
            self.baseCd = self.cachedCd
        end
        SyncCompat()
    end

    function BIT.Self:CacheCooldown()
        if not self.spellID or InCombatLockdown() then return end
        if self.isPetSpell or not C_SpellBook.IsSpellInSpellBook(self.spellID, Enum.SpellBookSpellBank.Player) then return end
        local ok, info = pcall(C_Spell.GetSpellCooldown, self.spellID)
        if not ok or not info then return end
        local ok2, dur = pcall(function() return info.duration end)
        if not ok2 or not dur then return end
        local clean = tonumber(string.format("%.1f", dur))
        if clean and clean > 1.5 then
            self.cachedCd = clean
            self.baseCd   = clean
            SyncCompat()
        end
    end

    function BIT.Self:BroadcastHello()
        if not self.class or not self.spellID then return end
        local now = GetTime()
        if now - self.lastHello < 3 then return end
        self.lastHello = now
        self:ReadBaseCd()
        local cd = self.baseCd or BIT.ALL_INTERRUPTS[self.spellID].cd
        BIT.Net:AnnounceHello(self.class, self.spellID, cd)
    end

    function BIT.Self:BroadcastSyncHello()
        if not self.class then return end
        local now = GetTime()
        -- separate rate limit so it doesn't conflict with interrupt HELLO
        if self.lastSyncHello and now - self.lastSyncHello < 3 then return end
        self.lastSyncHello = now
        BIT.Net:AnnounceSyncHello(self.class)
    end

    function BIT.Self:OnOwnKick(spellID)
        local now = GetTime()

        -- mark own bar green immediately, revert to red if no mob interrupt in 0.6s
        local function markAndWatch(barSpellID)
            if BIT.db.showFailedKick and BIT.UI and BIT.UI.SetPendingKickColor then
                BIT.UI:SetPendingKickColor(self.name)
            end
            self._pendingKickAt = now
            C_Timer.After(0.6, function()
                if self._pendingKickAt == now then
                    self._pendingKickAt = nil
                    if BIT.db.showFailedKick and BIT.UI and BIT.UI.FlashFailedKick then
                        BIT.UI:FlashFailedKick(self.name)
                        BIT.Net:AnnounceFailedKick()
                    end
                end
            end)
        end

        if self.extraKicks[spellID] then
            local cd = self.extraKicks[spellID].baseCd
            self.extraKicks[spellID].cdEnd = now + cd
            SyncCompat()
            BIT.Net:AnnounceKick(spellID, cd)
            BIT.Rotation:OnKick(self.name)
            markAndWatch(spellID)
            return
        end
        if self.spellID and spellID ~= self.spellID then
            local data = BIT.ALL_INTERRUPTS[spellID]
            if data then
                self.extraKicks[spellID] = { baseCd=data.cd, cdEnd=now+data.cd }
                SyncCompat()
                BIT.Net:AnnounceKick(spellID, data.cd)
                BIT.Rotation:OnKick(self.name)
                markAndWatch(spellID)
                return
            end
        end
        local cd = self.cachedCd or self.baseCd or BIT.ALL_INTERRUPTS[spellID].cd
        self.kickCdEnd = now + cd
        SyncCompat()
        BIT.Net:AnnounceKick(spellID, cd)
        BIT.Rotation:OnKick(self.name)
        markAndWatch(spellID)
    end

    function BIT.Self:FindInterrupt()
        local prevSpell    = self.spellID
        local prevExtras   = self.extraKicks
        self.spellID       = nil
        self.isPetSpell    = false
        self.extraKicks    = {}

        local specIndex = GetSpecialization()
        local specID    = specIndex and GetSpecializationInfo(specIndex)

        if specID and BIT.SPEC_NO_INTERRUPT[specID] then
            if prevSpell then self.cachedCd = nil; self.baseCd = nil end
            SyncCompat(); return
        end

        -- Spec override
        local ov = specID and BIT.SPEC_INTERRUPT_OVERRIDES[specID]
        if ov then
            if ov.isPet then
                local known = C_SpellBook.IsSpellInSpellBook(ov.id, Enum.SpellBookSpellBank.Pet)
                    or (ov.petSpellID and C_SpellBook.IsSpellInSpellBook(ov.petSpellID, Enum.SpellBookSpellBank.Pet))
                    or C_SpellBook.IsSpellInSpellBook(ov.id, Enum.SpellBookSpellBank.Player)
                if not known then
                    if C_SpellBook.IsSpellKnown(ov.id) then known=true end
                end
                if known then
                    self.spellID    = ov.id
                    self.baseCd     = ov.cd
                    self.isPetSpell = true
                end
            else
                self.spellID    = ov.id
                self.baseCd     = ov.cd
                self.isPetSpell = false
            end
        end

        -- Spec extra kicks (always present for this spec)
        local specExtras = specID and BIT.SPEC_EXTRA_KICKS[specID]
        local specManaged = {}
        if specExtras then
            for _, ex in ipairs(specExtras) do
                specManaged[ex.spellID] = true
                local checkID = ex.talentCheck or ex.spellID
                local known   = C_SpellBook.IsSpellInSpellBook(checkID, Enum.SpellBookSpellBank.Player) or C_SpellBook.IsSpellInSpellBook(checkID, Enum.SpellBookSpellBank.Pet)
                if not known then
                    if C_SpellBook.IsSpellKnown(checkID) then known=true end
                end
                if known then
                    self.extraKicks[ex.spellID] = {
                        baseCd      = ex.cd,
                        cdEnd       = (prevExtras[ex.spellID] and prevExtras[ex.spellID].cdEnd) or 0,
                        name        = ex.name,
                        icon        = ex.icon,
                        talentCheck = ex.talentCheck,
                    }
                end
            end
        end

        -- Class spell list
        local spellList = self.class and BIT.CLASS_INTERRUPT_LIST[self.class]
        if spellList then
            for _, sid in ipairs(spellList) do
                local known = C_SpellBook.IsSpellInSpellBook(sid, Enum.SpellBookSpellBank.Player) or C_SpellBook.IsSpellInSpellBook(sid, Enum.SpellBookSpellBank.Pet)
                if not known then
                    if C_SpellBook.IsSpellKnown(sid) then known=true end
                end
                if known then
                    if not self.spellID then
                        self.spellID = sid
                    elseif sid ~= self.spellID and not self.extraKicks[sid] and not specManaged[sid] then
                        local data = BIT.ALL_INTERRUPTS[sid]
                        if data then
                            self.extraKicks[sid] = {
                                baseCd = data.cd,
                                cdEnd  = (prevExtras[sid] and prevExtras[sid].cdEnd) or 0,
                            }
                        end
                    end
                end
            end
        end

        if self.spellID ~= prevSpell then
            self.cachedCd = nil
            if not self.baseCd and self.spellID then self:ReadBaseCd() end
        end

        -- Own talent scan
        self:ScanOwnTalents()
        SyncCompat()
    end

    function BIT.Self:ScanOwnTalents()
        if not self.spellID then return end
        if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return end
        local ok0, cid = pcall(C_ClassTalents.GetActiveConfigID)
        if not ok0 or not cid then return end
        local ok1, cfg = pcall(C_Traits.GetConfigInfo, cid)
        if not ok1 or not cfg or not cfg.treeIDs or #cfg.treeIDs == 0 then return end
        local ok2, nodes = pcall(C_Traits.GetTreeNodes, cfg.treeIDs[1])
        if not ok2 or not nodes then return end

        for _, nodeID in ipairs(nodes) do
            local ok3, node = pcall(C_Traits.GetNodeInfo, cid, nodeID)
            if ok3 and node and node.activeEntry and node.activeRank and node.activeRank > 0 then
                local ok4, entry = pcall(C_Traits.GetEntryInfo, cid, node.activeEntry.entryID)
                if ok4 and entry and entry.definitionID then
                    local ok5, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
                    if ok5 and def and def.spellID then
                        local dsid = def.spellID
                        local dsidStr; do local ok,s = pcall(tostring, dsid); if ok then dsidStr=s end end
                        local talent = (pcall(function() return BIT.CD_REDUCTION_TALENTS[dsid] end)
                                        and BIT.CD_REDUCTION_TALENTS[dsid])
                                        or (dsidStr and BIT.CD_REDUCTION_TALENTS_STR[dsidStr])
                        if talent and talent.affects == self.spellID then
                            local base = self.baseCd or BIT.ALL_INTERRUPTS[self.spellID].cd
                            local newCd
                            if talent.pctReduction then
                                newCd = math.floor(base * (1 - talent.pctReduction/100) + 0.5)
                            else
                                newCd = base - talent.reduction
                            end
                            self.baseCd = math.max(1, newCd)
                            -- also reduce extra kicks if talent says so
                            if talent.affectsExtraKicks and self.extraKicks then
                                for _, ek in pairs(self.extraKicks) do
                                    local ekBase = ek.baseCd or 0
                                    if ekBase > 0 then
                                        local ekNew
                                        if talent.pctReduction then
                                            ekNew = math.floor(ekBase * (1 - talent.pctReduction/100) + 0.5)
                                        else
                                            ekNew = ekBase - talent.reduction
                                        end
                                        ek.baseCd = math.max(1, ekNew)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- BIT.Inspect  — lightweight stub (inspect queue removed)
-- All talent data now comes from LibSpecialization.
-- We keep the table for back-compat with code that
-- references noKick / done / Invalidate.
------------------------------------------------------------
do
    BIT.Inspect = {
        queue   = {},
        busy    = false,
        current = nil,
        done    = {},   -- name → true
        noKick  = {},   -- name → true (healer / no interrupt)
    }

    -- back-compat
    BIT.inspectQueue       = BIT.Inspect.queue
    BIT.inspectBusy        = false
    BIT.inspectUnit        = nil
    BIT.inspectedPlayers   = BIT.Inspect.done
    BIT.noInterruptPlayers = BIT.Inspect.noKick

    -- No-op stubs — kept so existing call sites don't error
    function BIT.Inspect:Enqueue()  end
    function BIT.Inspect:QueueAll() end
    function BIT.Inspect:Process()  end
    function BIT.Inspect:OnReady()  end

    function BIT.Inspect:Invalidate(name)
        self.done[name]   = nil
        self.noKick[name] = nil
    end

end

------------------------------------------------------------
-- LibSpecialization integration  —  taint-free talent data
-- Players with compatible addons share their talent export string.
-- We decode it to build knownSpells WITHOUT inspect taint.
------------------------------------------------------------
do
    local LibSpec = LibStub and LibStub("LibSpecialization", true)
    if LibSpec then
        -- Decode a talent export string → { [spellID] = true } for all selected talents.
        -- Uses VIEW_TRAIT_CONFIG to traverse the tree (no taint), and the encoded
        -- talent string from LibSpec for the player's actual selections.
        local function ParseTalentString(specId, talentStr)
            if not talentStr or talentStr == "" then
                if BIT.debugMode then print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r no talentStr") end
                return nil
            end
            if not (C_ClassTalents and C_Traits and ImportDataStreamMixin
                    and Constants and Constants.TraitConsts) then
                if BIT.debugMode then print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r missing APIs") end
                return nil
            end

            -- Initialise a view loadout so GetNodeInfo works for any spec
            local viewCfg = Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
            local ok1 = pcall(C_ClassTalents.InitializeViewLoadout, specId, 100)
            if not ok1 then
                if BIT.debugMode then print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r InitializeViewLoadout failed specId=" .. tostring(specId)) end
                return nil
            end
            pcall(C_ClassTalents.ViewLoadout, {})

            -- Ordered node list for this spec's tree
            local ok2, treeId = pcall(C_ClassTalents.GetTraitTreeForSpec, specId)
            if not ok2 or not treeId then
                if BIT.debugMode then print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r GetTraitTreeForSpec failed specId=" .. tostring(specId)) end
                return nil
            end
            local ok3, nodeIds = pcall(C_Traits.GetTreeNodes, treeId)
            if not ok3 or not nodeIds then
                if BIT.debugMode then print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r GetTreeNodes failed treeId=" .. tostring(treeId)) end
                return nil
            end

            -- Build talent map: nodeID_choiceIdx → spellID
            local tmap = {}
            for _, nid in ipairs(nodeIds) do
                local ok4, node = pcall(C_Traits.GetNodeInfo, viewCfg, nid)
                if ok4 and node and node.ID ~= 0 and node.entryIDs then
                    for ci, eid in ipairs(node.entryIDs) do
                        local ok5, ei = pcall(C_Traits.GetEntryInfo, viewCfg, eid)
                        if ok5 and ei and ei.definitionID then
                            local ok6, di = pcall(C_Traits.GetDefinitionInfo, ei.definitionID)
                            if ok6 and di and di.spellID then
                                tmap[nid .. "_" .. ci] = di.spellID
                            end
                        end
                    end
                end
            end

            -- Decode export string header: version(8) + specId(16) + treeHash(128)
            local ok7, stream = pcall(CreateAndInitFromMixin, ImportDataStreamMixin, talentStr)
            if not ok7 or not stream then
                if BIT.debugMode then print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r stream init failed") end
                return nil
            end
            local version  = stream:ExtractValue(8)
            local encSpec  = stream:ExtractValue(16)
            stream:ExtractValue(128) -- treeHash → discard
            local expectedVer = C_Traits.GetLoadoutSerializationVersion and
                                C_Traits.GetLoadoutSerializationVersion() or 2
            if version ~= expectedVer or encSpec ~= specId then
                if BIT.debugMode then
                    print("|cff0091edBIT|r |cffff4444[TALENT-PARSE]|r version/spec mismatch"
                          .. " version=" .. version .. " expected=" .. expectedVer
                          .. " encSpec=" .. encSpec .. " specId=" .. tostring(specId))
                end
                return nil
            end

            -- Decode each node's talent entry in tree order
            local known = {}
            for _, nid in ipairs(nodeIds) do
                local selected = stream:ExtractValue(1) == 1
                local choiceIdx = 1
                if selected then
                    local purchased = stream:ExtractValue(1) == 1
                    if purchased then
                        local notMax = stream:ExtractValue(1) == 1
                        if notMax then stream:ExtractValue(6) end     -- rank bits
                        local isChoice = stream:ExtractValue(1) == 1
                        if isChoice then
                            choiceIdx = stream:ExtractValue(2) + 1
                        end
                    end
                    local sid = tmap[nid .. "_" .. choiceIdx]
                    if sid then known[sid] = true end
                end
            end
            return next(known) and known or nil
        end

        -- Register for group-wide spec/talent callbacks
        LibSpec.RegisterGroup(BIT, function(specId, role, position, playerName, talentStr)
            if not playerName or playerName == "" then return end
            local shortName = playerName:match("^([^%-]+)") or playerName
            -- Skip own player — we use ScanOwnTalents for ourselves
            local myName = UnitName("player")
            if shortName == myName then return end

            -- Store specID immediately (no inspect needed)
            if not BIT.SyncCD.users then BIT.SyncCD.users = {} end
            if not BIT.SyncCD.users[shortName] then BIT.SyncCD.users[shortName] = {} end
            local u = BIT.SyncCD.users[shortName]
            if specId and specId > 0 then
                u.specID      = specId
                u._hasLibSpec = true
            end

            -- Store class from unit info if missing
            if not u.class then
                for i = 1, 4 do
                    local unit = "party" .. i
                    if UnitExists(unit) and UnitName(unit) == shortName then
                        local _, cls = UnitClass(unit)
                        if cls then u.class = cls end
                        break
                    end
                end
            end

            -- Parse talent export string → knownSpells
            if talentStr and talentStr ~= "" and specId and specId > 0 then
                local knownSpells = ParseTalentString(specId, talentStr)
                if knownSpells then
                    -- Name-match: bridge talent-node IDs → SYNC_SPELLS ability IDs
                    -- Check issecretvalue before any string comparison
                    if BIT.SyncCD and BIT.SyncCD.spellLookupByName then
                        local additions = {}
                        for sid in pairs(knownSpells) do
                            local okN, tname = pcall(C_Spell.GetSpellName, sid)
                            if okN and tname and not issecretvalue(tname) then
                                local syncEntry = BIT.SyncCD.spellLookupByName[tname]
                                if syncEntry and not knownSpells[syncEntry.id] then
                                    additions[syncEntry.id] = true
                                end
                            end
                        end
                        for sid in pairs(additions) do knownSpells[sid] = true end
                    end
                    u.knownSpells     = knownSpells
                    u._talentVer      = (u._talentVer or 0) + 1
                    u._libSpecTalents = true

                    -- Persist to SavedVariables: resilient against /reload in M+
                    -- (addon messages are blocked in M+ after reload → LibSpec can't re-broadcast)
                    if BIT.db then
                        local guid
                        for i = 1, 4 do
                            local unit = "party" .. i
                            if UnitExists(unit) and UnitName(unit) == shortName then
                                guid = UnitGUID(unit)
                                break
                            end
                        end
                        if guid then
                            BIT.db.syncCDCache = BIT.db.syncCDCache or {}
                            BIT.db.syncCDCache[guid] = {
                                name        = shortName,
                                class       = u.class,
                                specID      = specId,
                                knownSpells = knownSpells,
                            }
                        end
                    end

                    if BIT.debugMode then
                        local cnt = 0; for _ in pairs(knownSpells) do cnt = cnt + 1 end
                        print("|cff00ff00BIT-LibSpec|r " .. shortName
                              .. " specID=" .. tostring(specId)
                              .. " knownSpells=" .. cnt
                              -- Specific talent checks for debugging CD reductions:
                              .. " |cffaaaaaa238100(Angel's Mercy)=" .. tostring(knownSpells[238100] == true) .. "|r")
                    end
                end
            end

            -- Update interrupt tracker registry with spec override.
            -- Use GetOrCreate for non-default interrupt specs (e.g. Solar Beam for Balance)
            -- to handle the race where LibSpec fires before AutoRegisterPartyByClass runs.
            if specId and specId > 0 then
                if BIT.SPEC_NO_INTERRUPT[specId] then
                    BIT.Registry:Remove(shortName)
                    BIT.Inspect.noKick[shortName] = true
                else
                    -- Kickable spec: clear stale noKick (e.g. Resto→Balance)
                    BIT.Inspect.noKick[shortName] = nil
                    local ov = BIT.SPEC_INTERRUPT_OVERRIDES[specId]
                    if ov and not ov.isPet then
                        local regEntry = BIT.Registry:GetOrCreate(shortName)
                        if not regEntry.class then
                            for i = 1, 4 do
                                local pu = "party" .. i
                                if UnitExists(pu) and UnitName(pu) == shortName then
                                    local _, cls = UnitClass(pu)
                                    if cls then regEntry.class = cls end
                                    break
                                end
                            end
                        end
                        if not regEntry.cdEnd or regEntry.cdEnd == 0 then regEntry.cdEnd = 0 end
                        regEntry.spellID    = ov.id
                        regEntry.baseCd     = ov.cd
                        regEntry.extraKicks = {}
                    end
                    -- class-default specs (e.g. Feral → Skull Bash): let AutoRegisterPartyByClass handle those
                end
            end

            -- Rebuild SyncCD to reflect new data
            if BIT.SyncCD and BIT.SyncCD.Rebuild then
                C_Timer.After(0.2, function() BIT.SyncCD:Rebuild() end)
            end
        end)

        if BIT.debugMode then
            print("|cff00ff00BIT|r LibSpecialization loaded — talent data via addon communication")
        end
    end
end

------------------------------------------------------------
-- BIT.Rotation  — kick rotation logic
------------------------------------------------------------
do
    BIT.Rotation = {
        order = {},
        index = 1,
    }

    -- back-compat
    BIT.rotationOrder = BIT.Rotation.order
    BIT.rotationIndex = BIT.Rotation.index

    local function Persist()
        BIT.db.rotationOrder = BIT.Rotation.order
        BIT.db.rotationIndex = BIT.Rotation.index
        BIT.rotationOrder    = BIT.Rotation.order
        BIT.rotationIndex    = BIT.Rotation.index
        if BIT.UI and BIT.UI.MarkRotationDirty then BIT.UI:MarkRotationDirty() end
    end

    function BIT.Rotation:OnKick(kickerName)
        if not BIT.db or not BIT.db.rotationEnabled then return end
        if #self.order == 0 then return end
        if self.order[self.index] ~= kickerName then return end
        self.index = self.index % #self.order + 1
        Persist()
        BIT.Net:SyncRotationIndex(self.index)
    end

    function BIT.Rotation:Broadcast()
        if #self.order == 0 then return end
        BIT.Net:SyncRotation(self.order, self.index)
    end

    function BIT.Rotation:ApplySync(names, idx)
        self.order = names
        self.index = math.max(1, math.min(idx, #names))
        Persist()
    end

    function BIT.Rotation:ApplyIndex(idx)
        if #self.order == 0 then return end
        self.index = math.max(1, math.min(idx, #self.order))
        Persist()
    end

    function BIT.Rotation:Restore()
        self.order = BIT.db.rotationOrder or {}
        self.index = BIT.db.rotationIndex or 1
        BIT.rotationOrder = self.order
        BIT.rotationIndex = self.index
        if BIT.UI and BIT.UI.MarkRotationDirty then BIT.UI:MarkRotationDirty() end
    end

    -- Public back-compat wrappers used by UI.lua
    BIT.AdvanceRotation   = function(name) BIT.Rotation:OnKick(name) end
    BIT.BroadcastRotation = function()     BIT.Rotation:Broadcast()  end
end

------------------------------------------------------------
-- Party management helpers
------------------------------------------------------------

-- Restore cached party talent data (from BIT.db.syncCDCache).
-- Called on PLAYER_ENTERING_WORLD and again after GROUP_ROSTER_UPDATE timers,
-- because CleanPartyList can wipe SyncCD.users during zone transitions.
function BIT:RestoreSyncCDCache()
    if not (BIT.db and BIT.db.syncCDCache and BIT.SyncCD) then return end
    BIT.SyncCD.users = BIT.SyncCD.users or {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid   = UnitGUID(unit)
            local cached = guid and BIT.db.syncCDCache[guid]
            if cached and cached.knownSpells then
                local pname = UnitName(unit) or cached.name
                if pname and not (BIT.SyncCD.users[pname] and BIT.SyncCD.users[pname].knownSpells) then
                    BIT.SyncCD.users[pname] = BIT.SyncCD.users[pname] or {}
                    local u = BIT.SyncCD.users[pname]
                    u.specID      = cached.specID
                    u.class       = cached.class
                    u.knownSpells = cached.knownSpells
                    u._fromCache  = true
                end
            end
        end
    end
end

function BIT:CleanPartyList()
    if self.testMode then return end
    local active = {}
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then active[UnitName(u)] = true end
    end
    -- Safety: during zone transitions (loading screens) UnitExists temporarily returns
    -- false for all party members even though the group is still intact. Purging here
    -- would wipe all Registry and SyncCD data. Skip the purge and let the next
    -- GROUP_ROSTER_UPDATE (when units are loaded) do the cleanup instead.
    if next(active) == nil and IsInGroup() then return end
    BIT.Registry:Purge(active)
    -- also remove from SyncCD.users if they left the group
    if BIT.SyncCD and BIT.SyncCD.users then
        for name in pairs(BIT.SyncCD.users) do
            if not active[name] then BIT.SyncCD.users[name] = nil end
        end
    end
    for name in pairs(BIT.Inspect.noKick) do
        if not active[name] then
            BIT.Inspect.noKick[name] = nil
            BIT.Inspect.done[name]   = nil
        end
    end
    for name in pairs(BIT.Inspect.done) do
        if not active[name] then BIT.Inspect.done[name] = nil end
    end
    if BIT._nonAddonSpecCache then
        for name in pairs(BIT._nonAddonSpecCache) do
            if not active[name] then BIT._nonAddonSpecCache[name] = nil end
        end
    end
    BIT.Self:BroadcastHello()
    C_Timer.After(0.1, function()
        if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
    end)
end

-- Persistent spec cache for non-addon party members
BIT._nonAddonSpecCache = BIT._nonAddonSpecCache or {}

-- Apply the spec override from a fresh GetInspectSpecialization read
local function RetrySpecOverride(name, unitHint)
    local entry = BIT.Registry:Get(name)
    if not entry then return end
    local u
    if unitHint and UnitExists(unitHint) and UnitName(unitHint) == name then
        u = unitHint
    else
        for i = 1, 4 do
            local pu = "party" .. i
            if UnitExists(pu) and UnitName(pu) == name then u = pu; break end
        end
    end
    if not u then return end
    local specID = GetInspectSpecialization(u)
    if not (specID and specID > 0) then return false end
    BIT._nonAddonSpecCache[name] = specID
    if BIT.SPEC_NO_INTERRUPT[specID] then
        BIT.Registry:Remove(name)
        BIT.Inspect.noKick[name] = true
        if BIT.UI and BIT.UI.RebuildBars then BIT.UI:RebuildBars() end
        return true
    end
    local ov = BIT.SPEC_INTERRUPT_OVERRIDES[specID]
    if ov and not ov.isPet then
        local changed = (entry.spellID ~= ov.id) or (entry.baseCd ~= ov.cd)
        entry.spellID    = ov.id
        entry.baseCd     = ov.cd
        entry.cdEnd      = 0
        entry.extraKicks = {}
        if changed and BIT.UI and BIT.UI.RebuildBars then BIT.UI:RebuildBars() end
    end
    return true
end

-- Schedule progressively longer retries to cover slow dungeon inspect data
local function ScheduleSpecRetries(name, unitHint)
    for _, delay in ipairs({ 1, 2, 4, 8, 15, 25 }) do
        C_Timer.After(delay, function()
            RetrySpecOverride(name, unitHint)
        end)
    end
end

function BIT:AutoRegisterPartyByClass()
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local name  = UnitName(u)
            local _, cls = UnitClass(u)
            if name and cls and BIT.CLASS_INTERRUPTS[cls] then
                local role       = UnitGroupRolesAssigned(u)
                local skipHealer = (role == "HEALER" and not BIT.HEALER_KEEPS_KICK[cls])
                if not skipHealer and not BIT.Inspect.noKick[name] then
                    local kick     = BIT.CLASS_INTERRUPTS[cls]
                    local existing = BIT.Registry:Get(name)
                    if not existing then
                        local entry   = BIT.Registry:GetOrCreate(name)
                        entry.class   = cls
                        entry.spellID = kick.id
                        entry.baseCd  = kick.cd
                        entry.cdEnd   = 0
                        local specID = GetInspectSpecialization(u)
                        if not (specID and specID > 0) then
                            specID = BIT._nonAddonSpecCache[name]
                        end
                        local specApplied = false
                        if specID and specID > 0 then
                            local ov = BIT.SPEC_INTERRUPT_OVERRIDES[specID]
                            if ov and not ov.isPet then
                                entry.spellID = ov.id
                                entry.baseCd  = ov.cd
                                specApplied = true
                            elseif BIT.SPEC_NO_INTERRUPT[specID] then
                                BIT.Registry:Remove(name)
                                BIT.Inspect.noKick[name] = true
                                specApplied = true
                            else
                                specApplied = true
                            end
                        end
                        if not specApplied then
                            ScheduleSpecRetries(name, u)
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Spell cast handling (own + party)
------------------------------------------------------------
function BIT:HandlePartyCast(unit, spellID, memberName)
    local now = GetTime()
    if memberName == BIT.Self.name then return end

    local resolvedID = BIT.SPELL_ALIASES[spellID] or spellID

    -- Demo Warlock edge-case: primary is Axe Toss (119914, pet).
    -- When the Felhunter is active instead of Felguard, Spell Lock fires
    -- as 19647 — but the extra-kick bar tracks 132409. Remap here so
    -- the correct bar gets updated without globally aliasing 19647.
    if resolvedID == 19647 then
        local e = BIT.Registry:Get(memberName)
        if e and e.spellID == 119914 then resolvedID = 132409 end
    end
    local entry = BIT.Registry:Get(memberName)

    if entry then
        local isExtra = false
        if entry.extraKicks then
            for _, ek in ipairs(entry.extraKicks) do
                if resolvedID == ek.spellID or spellID == ek.spellID then
                    ek.cdEnd = now + ek.baseCd
                    isExtra  = true
                    break
                end
            end
        end
        if not isExtra then
            local spellData = BIT.ALL_INTERRUPTS[resolvedID]
            if entry.spellID and resolvedID ~= entry.spellID and spellData then
                -- The observed spell differs from what we have registered.
                -- Check if this spell belongs to the same class as a known
                -- spec-specific main interrupt (e.g. Balance Solar Beam vs
                -- Feral Skull Bash).  If it does, this is a spec-switch:
                -- update the main bar rather than creating a spurious extra bar.
                local cls = entry.class
                local isClassMainInterrupt = cls and (function()
                    local list = BIT.CLASS_INTERRUPT_LIST[cls]
                    if not list then return false end
                    for _, id in ipairs(list) do
                        if id == resolvedID then return true end
                    end
                    return false
                end)()

                if isClassMainInterrupt then
                    -- Spec switch detected via cast — correct the registry entry
                    -- so the bar shows the right spell and CD from now on.
                    entry.spellID = resolvedID
                    entry.baseCd  = spellData.cd
                    entry.cdEnd   = now + spellData.cd
                    entry.lastKickAt = now
                    BIT.Inspect:Invalidate(memberName)
                else
                    -- Genuinely different spell (extra kick talent etc.)
                    if not entry.extraKicks then entry.extraKicks = {} end
                    local found = false
                    for _, ek in ipairs(entry.extraKicks) do
                        if ek.spellID == resolvedID then
                            ek.cdEnd = now + ek.baseCd
                            found = true; break
                        end
                    end
                    if not found then
                        local d = BIT.ALL_INTERRUPTS[resolvedID]
                        entry.extraKicks[#entry.extraKicks+1] = {
                            spellID=resolvedID, baseCd=d.cd, cdEnd=now+d.cd, name=d.name
                        }
                    end
                end
            else
                -- Spell matches registered spell — use the spell's own CD,
                -- NOT entry.baseCd which may be stale from a previous spec.
                local cd = (spellData and spellData.cd)
                        or entry.baseCd
                        or 15
                entry.cdEnd      = now + cd
                entry.lastKickAt = now
            end
        end
    end
    -- Players without the addon are auto-registered via AutoRegisterPartyByClass()
    -- so their casts are tracked here just like addon users.
end

------------------------------------------------------------
-- Signal-correlation interrupt detection (WilduTools approach)
--
-- Instead of trying to match casts to mob interrupts with loose
-- timing windows, we use a tight signal tape:
--   1) UNIT_SPELLCAST_SUCCEEDED on party/partypet → "cast" signal
--   2) UNIT_SPELLCAST_INTERRUPTED on nameplates   → "interrupt" signal
--   3) UNIT_AURA on nameplates                    → "aura" signal (suppress false positives)
--
-- Signals are correlated within a 55ms window. When a cast matches
-- an interrupt, we trigger the CD via HandlePartyCast / OnOwnKick.
-- Player casts are handled directly (no correlation needed).
------------------------------------------------------------
local signalTape       = {}
local signalSeq        = 0
local needsCorrelation = false
local lastCorrelateAt  = 0

local SIGNAL_RETENTION   = 0.35   -- seconds to keep signals
local CORRELATE_INTERVAL = 0.04   -- min seconds between correlations
local MATCH_WINDOW       = 0.055  -- cast ↔ interrupt match window
local AURA_SUPPRESS      = 0.028  -- aura within this window suppresses interrupt

local function PushSignal(kind, unit)
    signalSeq = signalSeq + 1
    signalTape[#signalTape + 1] = {
        seq      = signalSeq,
        kind     = kind,       -- "cast" | "interrupt" | "aura"
        unit     = unit,
        at       = GetTime(),
        consumed = false,
    }
    needsCorrelation = true
end

local function PruneSignalTape(now)
    local kept = {}
    local minAt = now - SIGNAL_RETENTION
    for i = 1, #signalTape do
        local s = signalTape[i]
        if s and s.at and s.at >= minAt then
            kept[#kept + 1] = s
        end
    end
    signalTape = kept
end

-- Resolve which party member name owns a unit (handles partypet → owner)
local function ResolvePartyName(unit)
    if not unit then return nil, nil end
    if unit:find("^partypet") then
        local idx = unit:match("partypet(%d)")
        if idx then
            local ownerUnit = "party" .. idx
            return UnitName(ownerUnit), ownerUnit
        end
        return nil, nil
    end
    return UnitName(unit), unit
end

-- Check if a spellID is a known interrupt, return the interrupt data + clean ID
local function ResolveInterruptSpell(spellID)
    -- Try spell name lookup first, but only if the name is NOT tainted.
    -- Use issecretvalue() to detect tainted strings from party events.
    -- If tainted, skip name lookup entirely — fall through to ID-based lookup below.
    local ok, spellName = pcall(C_Spell.GetSpellName, spellID)
    local cleanName
    if ok and spellName and not issecretvalue(spellName) then
        cleanName = spellName
    end
    if cleanName then
        local data = BIT.ALL_INTERRUPTS_BY_NAME[cleanName]
        if data then return data, data.id, cleanName end
    end
    -- Try C_Spell.GetBaseSpell for clean ID
    local cleanID = spellID
    local ok2, baseID = pcall(C_Spell.GetBaseSpell, spellID)
    if ok2 and baseID then cleanID = baseID end
    -- Direct ID lookup
    -- Never return a tainted spellName — use d.name from our own table instead.
    -- cleanName is already guaranteed untainted (nil if spellName was tainted).
    local ok3, d = pcall(function() return BIT.ALL_INTERRUPTS[cleanID] end)
    if ok3 and d then return d, cleanID, (cleanName or d.name) end
    -- Alias lookup
    local ok4, aliasTarget = pcall(function() return BIT.SPELL_ALIASES[cleanID] end)
    if ok4 and aliasTarget then
        local ok5, d2 = pcall(function() return BIT.ALL_INTERRUPTS[aliasTarget] end)
        if ok5 and d2 then return d2, aliasTarget, (cleanName or d2.name) end
    end
    return nil, nil, cleanName  -- nil if tainted, cleanName if untainted own-player spell
end

-- Trigger a party member's interrupt CD (called when correlation matches)
local function TriggerPartyCooldown(unit, memberName)
    if not memberName then return end
    local rc = recentCasts[memberName]
    if not rc then return end
    local castID = type(rc) == "table" and rc.spellID or nil
    if castID and BIT.HandlePartyCast then
        BIT:HandlePartyCast(unit, castID, memberName)
    end
end

local function CorrelateSignals()
    local now = GetTime()
    if not needsCorrelation then return end
    if now - lastCorrelateAt < CORRELATE_INTERVAL then return end
    lastCorrelateAt = now
    PruneSignalTape(now)

    local casts      = {}
    local interrupts = {}
    local auras      = {}

    for i = 1, #signalTape do
        local s = signalTape[i]
        if s and not s.consumed then
            if s.kind == "cast"      then casts[#casts + 1] = s
            elseif s.kind == "interrupt" then interrupts[#interrupts + 1] = s
            elseif s.kind == "aura"      then auras[#auras + 1] = s
            end
        end
    end

    if #interrupts == 0 or #casts == 0 then
        needsCorrelation = false
        return
    end

    -- Take the freshest interrupt signal
    table.sort(interrupts, function(a, b) return (a.at or 0) < (b.at or 0) end)
    local freshest = interrupts[#interrupts]

    -- If multiple interrupt signals arrived nearly simultaneously (< 18ms),
    -- it's likely a multi-hit (AoE stun, etc.) — suppress all of them
    local clustered = 0
    for i = 1, #interrupts do
        if math.abs((interrupts[i].at or 0) - (freshest.at or 0)) <= 0.018 then
            clustered = clustered + 1
        end
    end
    if clustered > 1 then
        for i = 1, #interrupts do interrupts[i].consumed = true end
        needsCorrelation = false
        return
    end

    -- Suppress if an aura event on the same nameplate arrived within 28ms
    -- (indicates a buff/debuff change, not a real interrupt)
    for i = 1, #auras do
        if auras[i].unit == freshest.unit then
            if math.abs((freshest.at or 0) - (auras[i].at or 0)) <= AURA_SUPPRESS then
                freshest.consumed = true
                needsCorrelation = false
                return
            end
        end
    end

    -- Find the best matching cast signal within 55ms window
    local bestCast = nil
    local bestDiff = math.huge
    for i = 1, #casts do
        local diff = math.abs((freshest.at or 0) - (casts[i].at or 0))
        if diff <= MATCH_WINDOW and diff < bestDiff then
            bestDiff = diff
            bestCast = casts[i]
        end
    end

    freshest.consumed = true

    if bestCast then
        bestCast.consumed = true
        -- bestCast.unit is the party unit that cast the interrupt
        local memberName, ownerUnit = ResolvePartyName(bestCast.unit)
        if memberName and ownerUnit then
            TriggerPartyCooldown(ownerUnit, memberName)
        end

        -- Own player success-kick feedback
        if bestCast.unit == "player" then
            if BIT.Self and BIT.Self._pendingKickAt then
                BIT.Self._pendingKickAt = nil
                if BIT.db.showFailedKick and BIT.UI and BIT.UI.MarkSuccessKick then
                    BIT.UI:MarkSuccessKick(BIT.Self.name)
                    BIT.Net:AnnounceSuccessKick()
                end
            end
        end
    end

    needsCorrelation = false
end

------------------------------------------------------------
-- Unified event frame for interrupt detection
-- Handles: party casts, nameplate interrupts, nameplate auras
------------------------------------------------------------
local _interruptFrame = CreateFrame("Frame")
_interruptFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
_interruptFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
_interruptFrame:RegisterEvent("UNIT_AURA")

_interruptFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not unit then return end

        -- Own player + pet: CD handled by _playerFrame below,
        -- but we still push a "cast" signal so the correlation can
        -- confirm the success-kick (MarkSuccessKick feedback).
        if unit == "player" or unit == "pet" then
            -- Check if this is an interrupt spell
            local _, spellID2 = ...
            if spellID2 then
                local data2 = ResolveInterruptSpell(spellID2)
                if data2 then PushSignal("cast", "player") end
            end
            return
        end

        -- Only party/partypet units
        if not unit:find("^party") then return end

        local memberName, ownerUnit = ResolvePartyName(unit)
        if not memberName then return end

        local _, spellID = ...  -- castGUID, spellID
        local data, cleanID, spellName = ResolveInterruptSpell(spellID)

        -- Store as interrupt cast signal for correlation.
        -- In Midnight (12.x), spellID from party UNIT_SPELLCAST_SUCCEEDED is tainted,
        -- so ResolveInterruptSpell will return nil. Fall back to the registry-known
        -- interrupt spell for this player (WilduTools approach: trust the known spell,
        -- don't require the runtime ID to be readable).
        if data then
            recentCasts[memberName] = { t = GetTime(), spellID = data.id }
            PushSignal("cast", unit)
        elseif not spellName then
            -- Name lookup failed entirely (tainted spellID AND GetSpellName failed).
            -- Fall back to the registered interrupt for this player — but ONLY if
            -- that interrupt is not currently on cooldown. If it is on CD, this
            -- unidentified cast cannot be the registered interrupt (e.g. Tail Swipe
            -- being used while Quell is still recharging), so skip the signal to
            -- prevent falsely resetting the interrupt CD.
            local entry = BIT.Registry:Get(memberName)
            if entry and entry.spellID and entry.spellID > 0 then
                local isOnCD = entry.cdEnd and entry.cdEnd > GetTime()
                if not isOnCD then
                    recentCasts[memberName] = { t = GetTime(), spellID = entry.spellID }
                    PushSignal("cast", unit)
                end
            end
        end

        -- SyncCD: detect offensive/defensive CDs (always, regardless of interrupt)
        if spellName and BIT.SyncCD and BIT.SyncCD.OnPartySpellCastByName then
            BIT.SyncCD:OnPartySpellCastByName(memberName, spellName)
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Only care about nameplate units (mobs being interrupted)
        if unit and unit:find("^nameplate") then
            PushSignal("interrupt", unit)
        end

    elseif event == "UNIT_AURA" then
        -- Only care about nameplate units (for false-positive suppression)
        if unit and unit:find("^nameplate") then
            PushSignal("aura", unit)
        end
    end
end)

-- Run correlation every frame via OnUpdate
_interruptFrame:SetScript("OnUpdate", function()
    if needsCorrelation then
        CorrelateSignals()
    end
end)

-- Back-compat: RegisterPartyWatchers is called from many places.
-- Now a no-op since we use a single generic event frame.
BIT._slotWatcherActive = {}
function BIT:RegisterPartyWatchers() end

------------------------------------------------------------
-- Own cast frame
------------------------------------------------------------
local _playerFrame = CreateFrame("Frame")
_playerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
_playerFrame:SetScript("OnEvent", function(_, _, unit, castGUID, spellID)
    if unit == "pet" then
        -- Pet spellID is tainted in WoW 12.0 Midnight
        local usedID

        -- Try direct numeric hit first
        local ok, hit = pcall(function() return BIT.ALL_INTERRUPTS[spellID] end)
        if ok and hit then usedID = spellID end

        -- Try alias via string
        if not usedID then
            local ok2, s = pcall(tostring, spellID)
            if ok2 and s then
                local target = BIT.SPELL_ALIASES_STR[s]
                if target and BIT.ALL_INTERRUPTS[target] then usedID = target end
                if not usedID and BIT.ALL_INTERRUPTS_STR[s] then usedID = tonumber(s) end
            end
        end

        -- Slider fallback
        if not usedID then usedID = BIT.Taint:Resolve(spellID) end

        if usedID then
            BIT.Self:OnOwnKick(usedID)
        end
    else
        -- Player cast: spellID is untainted.
        -- Check ALL_INTERRUPTS directly first, then fall back to SPELL_ALIASES
        -- (e.g. Grimoire: Fel Ravager fires as 1276467 which aliases to 132409).
        local usedID
        if BIT.ALL_INTERRUPTS[spellID] then
            usedID = spellID
        else
            local alias = BIT.SPELL_ALIASES[spellID]
            if alias and BIT.ALL_INTERRUPTS[alias] then
                usedID = alias
            end
        end
        if usedID then
            BIT.Self:OnOwnKick(usedID)
        end
        -- check SyncCD spells
        if BIT.db.showSyncCDs and BIT.SyncCD and BIT.SyncCD.OnSpellUsed then
            if BIT.debugMode then
                print("|cff0091edBIT|r |cFFAAAAAA[SyncCD]|r player cast spellID=" .. tostring(spellID))
            end
            local specIdx = GetSpecialization()
            local specID  = specIdx and select(1, GetSpecializationInfo(specIdx))
            local spells  = specID and BIT.SYNC_SPELLS and BIT.SYNC_SPELLS[specID]
            if spells then
                for _, s in ipairs(spells) do
                    local matchedSpell = nil
                    if s.id == spellID then
                        matchedSpell = s
                    elseif s.replacedBy and s.replacedBy.id == spellID then
                        matchedSpell = s.replacedBy
                    end
                    if matchedSpell then
                        -- Use cached C_Traits talent scan for own player (IsSpellKnown
                        -- does not work for passive talent modifiers like Pitch Black).
                        local ownKS = BIT.SyncCD.users
                                      and BIT.SyncCD.users[BIT.myName]
                                      and BIT.SyncCD.users[BIT.myName].knownSpells

                        -- Step 1: always apply talent CD reductions from the talent scan.
                        -- This is the primary source of truth — the API may return the
                        -- base CD (without talent mods) in Midnight.
                        local realDur = matchedSpell.cd
                        if matchedSpell.talentMods and ownKS then
                            for talentID, reduction in pairs(matchedSpell.talentMods) do
                                if ownKS[talentID] then
                                    realDur = math.max(1, realDur - reduction)
                                end
                            end
                        end

                        -- Step 2: cross-check with C_Spell.GetSpellCooldown.
                        -- Use min(talentCalc, apiDur) so the API can only make the
                        -- value shorter, never longer. This prevents Midnight returning
                        -- the base CD (e.g. 300s) from overriding a correctly calculated
                        -- talent-reduced value (e.g. 180s with Pitch Black).
                        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
                        if ok and cdInfo then
                            local ok2, apiDur = pcall(function()
                                if cdInfo.duration and cdInfo.duration > 1.5 then
                                    return tonumber(string.format("%.1f", cdInfo.duration))
                                end
                            end)
                            if ok2 and apiDur then
                                realDur = math.min(realDur, apiDur)
                            end
                        end

                        -- Effective charges: base value + any talent-granted charges
                        local effectiveCharges = matchedSpell.charges or 0
                        if matchedSpell.talentCharges and ownKS then
                            for talentID, chargeCount in pairs(matchedSpell.talentCharges) do
                                if ownKS[talentID] then
                                    effectiveCharges = chargeCount
                                    break
                                end
                            end
                        end

                        if BIT.debugMode then
                            print("|cff0091edBIT|r |cFFAAAAAA[SyncCD]|r MATCH " .. tostring(matchedSpell.name or "?")
                                  .. " realDur=" .. tostring(realDur)
                                  .. " cdFromApi=" .. tostring(cdFromApi)
                                  .. " effectiveCharges=" .. tostring(effectiveCharges)
                                  .. " ownKS=" .. tostring(ownKS ~= nil))
                        end

                        -- Charge-based spells: realDur is already correctly set above
                        -- (from API or talentMods). Just let OnSpellUsed run normally.
                        -- RefreshCharges handles the badge and clears state when
                        -- all charges are back.
                        -- Don't restart if CD is already running.
                        -- For charge spells: 2nd cast (1→0) should keep the existing
                        -- timer (shows when first charge returns), not reset to full CD.
                        -- RefreshCharges acts as backup if state was 0 due to race condition.
                        local _existing = BIT.syncCdState and BIT.syncCdState[BIT.myName]
                        local _cdRunning = _existing and _existing[spellID] and _existing[spellID] > GetTime()
                        if not _cdRunning then
                            -- Delay by 0.5s so the API returns the correct talent-modified
                            -- CD duration instead of the base value it gives at cast time.
                            local castSpellID = spellID
                            local castRealDur = realDur
                            C_Timer.After(0.5, function()
                                local finalDur = castRealDur
                                local ok3, info3 = pcall(C_Spell.GetSpellCooldown, castSpellID)
                                if ok3 and info3 then
                                    local du
                                    pcall(function()
                                        if info3.duration and info3.duration > 1.5 then
                                            du = tonumber(string.format("%.1f", info3.duration))
                                        end
                                    end)
                                    if du then
                                        finalDur = math.min(finalDur, du)
                                    end
                                end
                                BIT.SyncCD:OnSpellUsed(BIT.myName, castSpellID, finalDur)
                            end)
                        end

                        break
                    end
                end
            end
        end
        -- Check CD reducer spells (e.g. Shield Slam → -6s on Shield Wall via Impenetrable Wall)
        if BIT.db.showSyncCDs and BIT.SyncCD and BIT.SyncCD.CheckCDReducer then
            BIT.SyncCD:CheckCDReducer(spellID)
        end
    end
end)

------------------------------------------------------------
-- Initialize
------------------------------------------------------------
function BIT:Initialize()
    BIT.UI     = BIT.UI     or {}
    BIT.Media  = BIT.Media  or {}
    BIT.Config = BIT.Config or {}

    BliZziInterruptsSavedVars     = BliZziInterruptsSavedVars     or {}
    BliZziInterruptsSavedVarsChar = BliZziInterruptsSavedVarsChar or {}
    self.db     = BliZziInterruptsSavedVars
    self.charDb = BliZziInterruptsSavedVarsChar

    for k, v in pairs(BIT.DEFAULTS) do
        if self.db[k] == nil then self.db[k] = v end
    end

    -- Restore debug mode from saved vars (persists across reloads)
    if self.db.debugMode then
        BIT.debugMode = true
        print("|cffff4444BIT|r Debug mode ON (persistent — /bitdebug to toggle off)")
    end

    -- Per-character profile: build a stable key and load saved settings if present
    local pName  = UnitName("player") or "Unknown"
    local pRealm = GetNormalizedRealmName() or GetRealmName() or "Unknown"
    BIT.charKey  = pName .. "-" .. pRealm
    if self.db.useGlobalDefault    == nil then self.db.useGlobalDefault    = false end
    if self.db.useSpecProfile      == nil then self.db.useSpecProfile      = false end
    if self.db.useRoleProfile      == nil then self.db.useRoleProfile      = false end
    if self.db.useGlobalCustomName == nil then self.db.useGlobalCustomName = false end
    if self.db.globalCustomName    == nil then self.db.globalCustomName    = ""    end

    -- Migration: legacy db.myCustomName was account-wide; move it to per-character
    -- storage so every character can keep its own nickname. Only migrate if the
    -- current character has no per-character name yet and a legacy value exists.
    if self.charDb.myCustomName == nil then
        if self.db.myCustomName and self.db.myCustomName ~= "" then
            self.charDb.myCustomName = self.db.myCustomName
        else
            self.charDb.myCustomName = ""
        end
    end
    -- Wipe legacy account-wide key so it doesn't leak to other chars
    self.db.myCustomName = nil

    -- Profile selection priority (highest → lowest):
    --   1. Spec profile (matches current specID)
    --   2. Role profile (matches current role: TANK/HEALER/DAMAGER)
    --   3. Global default profile
    --   4. Character profile (this charKey)
    --   5. DEFAULTS (already applied above)
    --
    -- NOTE: spec/role resolution requires GetSpecialization() which may return nil
    -- during Initialize (talent data not loaded yet). In that case spec/role
    -- profiles are applied later by PLAYER_SPECIALIZATION_CHANGED / PLAYER_LOGIN.
    local hasCharProfile = self.db.charProfiles and self.db.charProfiles[BIT.charKey]
    local applyGlobal    = self.db.useGlobalDefault and self.db.globalProfile
    local applyChar      = hasCharProfile
    local snap = nil

    -- Spec profile
    if self.db.useSpecProfile and self.db.specProfiles then
        local idx  = GetSpecialization and GetSpecialization()
        local sid  = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
        if sid and self.db.specProfiles[sid] then
            snap = self.db.specProfiles[sid]
        end
    end

    -- Role profile (fallback if no spec profile)
    if not snap and self.db.useRoleProfile and self.db.roleProfiles then
        local idx  = GetSpecialization and GetSpecialization()
        local role
        if idx then
            role = select(5, GetSpecializationInfo(idx))
        end
        if not role then role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") end
        if role and self.db.roleProfiles[role] then
            snap = self.db.roleProfiles[role]
        end
    end

    -- Global default (fallback)
    if not snap and applyGlobal then
        snap = self.db.globalProfile
    end

    -- Character profile (lowest fallback)
    if not snap and applyChar then
        snap = self.db.charProfiles[BIT.charKey]
    end

    if snap then
        for k in pairs(BIT.DEFAULTS) do
            if snap[k] ~= nil then self.db[k] = snap[k] end
        end
        if snap.fontPath then self.db.fontPath = snap.fontPath end
        if snap.fontName then self.db.fontName = snap.fontName end
        if snap._posX      then self.charDb.posX            = snap._posX      end
        if snap._posY      then self.charDb.posY            = snap._posY      end
        if snap._posXUp    then self.charDb.posXUp          = snap._posXUp    end
        if snap._posYUp    then self.charDb.posYUp          = snap._posYUp    end
        if snap._syncX     then self.charDb.syncCdBarsPosX  = snap._syncX     end
        if snap._syncY     then self.charDb.syncCdBarsPosY  = snap._syncY     end
        if snap._syncIconX then self.charDb.syncCdPosX      = snap._syncIconX end
        if snap._syncIconY then self.charDb.syncCdPosY      = snap._syncIconY end
    end

    -- Remove old anchor keys; positions stored as absolute coords only
    self.db.posPoint    = nil
    self.db.posRelPoint = nil

    -- One-time migration: posX/posY global → per-char
    if self.db.posX and not self.charDb.posX then
        self.charDb.posX = self.db.posX
        self.charDb.posY = self.db.posY
    end
    self.db.posX = nil
    self.db.posY = nil

    BIT:ApplyLocale()
    BIT.Net:Register()

    -- rebuild spell name lookup with localized names
    do
        BIT.ALL_INTERRUPTS_BY_NAME = {}
        for id, v in pairs(BIT.ALL_INTERRUPTS) do
            local info = C_Spell.GetSpellInfo(id)
            local localName = info and info.name
            if localName then
                local existing = BIT.ALL_INTERRUPTS_BY_NAME[localName]
                if not existing or v.cd < existing.cd then
                    BIT.ALL_INTERRUPTS_BY_NAME[localName] = { id = id, cd = v.cd }
                end
            end
        end
    end

    BIT.Self:UpdateFromPlayer()
    BIT.Media:Load()
    BIT.UI:Create()
    if BIT.SyncCD and BIT.SyncCD.Create then BIT.SyncCD:Create() end
    -- Scan own talents immediately so talentMods/talentCharges work from first load.
    if BIT.SyncCD and BIT.SyncCD.ScanOwnTalents then BIT.SyncCD:ScanOwnTalents() end
    C_Timer.After(0.5, function()
        if BIT.SyncCD and BIT.SyncCD.ScanOwnTalents then BIT.SyncCD:ScanOwnTalents() end
        if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
    end)
    BIT.UI:ApplyAutoScale()
    -- Apply saved frame scale (SetScale on mainFrame, default 100%)
    if BIT.UI.mainFrame then
        BIT.UI.mainFrame:SetScale((self.db.frameScale or 100) / 100)
    end
    -- Hook slash commands to open the custom settings UI
    if BIT.SettingsUI and BIT.SettingsUI.HookSlash then
        BIT.SettingsUI:HookSlash()
    end
    -- Create minimap button
    if BIT.SettingsUI and BIT.SettingsUI.CreateMinimapButton then
        BIT.SettingsUI:CreateMinimapButton()
    end
    BIT.Self:FindInterrupt()
    BIT.Rotation:Restore()

    self.ready = true

    if self.updateTicker then self.updateTicker:Cancel() end
    self.updateTicker = C_Timer.NewTicker(0.1, function()
        BIT.UI:UpdateDisplay()
        if BIT.SyncCD and BIT.SyncCD.UpdateDisplay then BIT.SyncCD:UpdateDisplay() end
    end)

    -- Restore own CD timers after reload/login.
    -- Short delay so ScanOwnTalents and GetSpellsForPlayer have valid data.
    C_Timer.After(1.5, function()
        if BIT.SyncCD and BIT.SyncCD.RestoreCooldowns then
            BIT.SyncCD:RestoreCooldowns()
        end
    end)

    -- Periodic re-inspect to pick up spec changes
    C_Timer.After(2, function() BIT.Self:BroadcastHello() end)

    -- Smart Misdirect (Hunter/Rogue extra feature — self-gates on class)
    if BIT.SmartMisdirect and BIT.SmartMisdirect.Initialize then
        BIT.SmartMisdirect:Initialize()
    end
end

------------------------------------------------------------
-- Main event dispatcher  (table-driven, not if/elseif)
------------------------------------------------------------
local eventHandlers = {}

eventHandlers["ADDON_LOADED"] = function(addon)
    if addon == "BliZzi_Interrupts" then BIT:Initialize() end
end

eventHandlers["PLAYER_LOGIN"] = function()
    if BIT.ready and BIT.db and not BIT.db.fontPath then
        BIT.Media:Load()
        BIT.UI:RebuildBars()
    end
    if BIT.db and BIT.db.showWelcome ~= false then
        print(string.format(BIT.L["MSG_WELCOME"] or "|cff0091edBliZzi|r|cffffa300Interrupts|r v%s — type |cFFFFD700/blizzi|r to open settings.", BIT.VERSION))
    end
end

eventHandlers["CHAT_MSG_ADDON"] = function(prefix, msg, channel, sender)
    BIT.Net:OnMessage(prefix, msg, channel, sender)
end
eventHandlers["CHAT_MSG_ADDON_LOGGED"] = eventHandlers["CHAT_MSG_ADDON"]

eventHandlers["SPELL_UPDATE_COOLDOWN"] = function()
    BIT.Self:CacheCooldown()
    BIT.UI:UpdateDisplay()
end

eventHandlers["SPELLS_CHANGED"] = function()
    BIT.Self:FindInterrupt()
    BIT.Self:BroadcastHello()
    if BIT.Self.class == "WARLOCK" then
        C_Timer.After(1.5, function() BIT.Self:FindInterrupt() end)
        C_Timer.After(3.0, function() BIT.Self:FindInterrupt() end)
    end
    if BIT.SyncCD and BIT.SyncCD.OnTalentChanged then BIT.SyncCD:OnTalentChanged() end
end

eventHandlers["PLAYER_TALENT_UPDATE"] = function()
    if BIT.SyncCD and BIT.SyncCD.OnTalentChanged then BIT.SyncCD:OnTalentChanged() end
end

eventHandlers["TRAIT_CONFIG_UPDATED"] = function()
    if BIT.SyncCD and BIT.SyncCD.OnTalentChanged then BIT.SyncCD:OnTalentChanged() end
end

eventHandlers["SPELL_UPDATE_CHARGES"] = function()
    if BIT.SyncCD and BIT.SyncCD.RefreshCharges then BIT.SyncCD:RefreshCharges() end
end

eventHandlers["PLAYER_REGEN_ENABLED"] = function()
    BIT.inCombat = false
    BIT.Self:CacheCooldown()
    BIT.UI:CheckZoneVisibility()
    -- Flush any frames whose SetPropagateMouseClicks was deferred because we were
    -- in combat when RebuildBars ran (protected function in 11.x/12.x).
    if BIT._pendingPropagate then
        for _, fr in ipairs(BIT._pendingPropagate) do
            if fr and fr.SetPropagateMouseClicks then
                pcall(fr.SetPropagateMouseClicks, fr, true)
            end
        end
        BIT._pendingPropagate = nil
    end
    -- Smart Misdirect: any update queued during combat runs now that it's safe
    -- to change secure-frame attributes again.
    if BIT.SmartMisdirect and BIT.SmartMisdirect.ProcessQueuedUpdate then
        BIT.SmartMisdirect._updateQueued = true
        BIT.SmartMisdirect:ProcessQueuedUpdate()
    end
end

eventHandlers["PLAYER_REGEN_DISABLED"] = function()
    BIT.inCombat = true
    BIT.UI:CheckZoneVisibility()
end

-- INSPECT_READY removed — talent data now comes from LibSpecialization

-- Tracks the previously active spec so the Save-on-switch path knows which slot
-- to update. Declared upvalue so it persists across event fires. Set on login by
-- the initial PLAYER_SPECIALIZATION_CHANGED that fires after entering the world.
local _bitLastSpecID = nil

eventHandlers["PLAYER_SPECIALIZATION_CHANGED"] = function(unit)
    -- ── Self-path: handle spec-profile / role-profile auto-apply ──
    if not unit or unit == "player" then
        if BIT.db then
            local newSpec = BIT.GetCurrentSpecID and BIT.GetCurrentSpecID()
            if newSpec then
                -- Save previous spec's settings if that slot already has a profile.
                if _bitLastSpecID and _bitLastSpecID ~= newSpec
                   and BIT.db.useSpecProfile and BIT.db.specProfiles
                   and BIT.db.specProfiles[_bitLastSpecID]
                   and BIT.SaveSpecProfile
                then
                    BIT.SaveSpecProfile(_bitLastSpecID)
                end
                _bitLastSpecID = newSpec

                -- Apply new spec/role profile if auto-apply is active.
                local applied = false
                if BIT.db.useSpecProfile and BIT.ApplySpecProfile and BIT.HasSpecProfile
                   and BIT.HasSpecProfile(newSpec)
                then
                    applied = BIT.ApplySpecProfile(newSpec)
                end
                if not applied and BIT.db.useRoleProfile and BIT.ApplyRoleProfile
                   and BIT.HasRoleProfile and BIT.HasRoleProfile()
                then
                    BIT.ApplyRoleProfile()
                end
            end
        end
        -- Smart Misdirect: in case the player swapped from Hunter-spec-A to
        -- Hunter-spec-B (same class), the spell is unchanged but the role
        -- might have — requeue a target recalc.
        if BIT.SmartMisdirect then
            if BIT.SmartMisdirect.OnSpecChanged then BIT.SmartMisdirect:OnSpecChanged() end
            if BIT.SmartMisdirect.QueueUpdate    then BIT.SmartMisdirect:QueueUpdate()    end
        end
    end

    -- ── Other-unit path: existing party-member inspect / kick-tracking logic ──
    if unit and unit ~= "player" then
        local name = UnitName(unit)
        if name then
            BIT.Inspect:Invalidate(name)
            local _, cls = UnitClass(unit)
            local specID = GetInspectSpecialization(unit)
            if not (specID and specID > 0) then specID = nil end

            local isAddonUser = BIT.Registry:AddonUsers()[name]
            local hasEntry    = BIT.Registry:Get(name) ~= nil

            -- Nothing to work with at all
            if not specID and not hasEntry and not isAddonUser then return end

            -- noKick spec → remove entry, mark noKick, done
            if specID and BIT.SPEC_NO_INTERRUPT[specID] then
                if hasEntry then BIT.Registry:Remove(name) end
                BIT.Inspect.noKick[name] = true
                return
            end

            -- Kickable spec: clear any stale noKick (e.g. Resto→Balance)
            BIT.Inspect.noKick[name] = nil

            -- For non-addon players with no entry: only create when spec is known.
            -- Do NOT use UnitGroupRolesAssigned here — role can be stale after a
            -- spec switch (e.g. still "HEALER" right after switching from Resto).
            -- SPEC_NO_INTERRUPT already handled above, so any spec that reaches
            -- here is a kicker by definition.
            if not hasEntry and not isAddonUser and not specID then return end

            local entry = BIT.Registry:GetOrCreate(name)
            entry.class = cls
            if hasEntry then entry.cdEnd = 0 end

            if specID then
                local ov = BIT.SPEC_INTERRUPT_OVERRIDES[specID]
                if ov and not ov.isPet then
                    entry.spellID = ov.id
                    entry.baseCd  = ov.cd
                elseif not entry.spellID then
                    -- No override → class default
                    local classDef = BIT.CLASS_INTERRUPTS[cls]
                    if classDef then
                        entry.spellID = classDef.id
                        entry.baseCd  = classDef.cd
                        entry.cdEnd   = 0
                    end
                end
                entry.extraKicks = {}
            end

            -- Retry after 1s: GetInspectSpecialization may return 0 immediately
            C_Timer.After(1, function()
                if not specID then
                    local retrySpec = GetInspectSpecialization(unit)
                    if retrySpec and retrySpec > 0 then
                        local retryEntry = BIT.Registry:Get(name)
                        if retryEntry then
                            BIT.Inspect.noKick[name] = nil
                            local ov = BIT.SPEC_INTERRUPT_OVERRIDES[retrySpec]
                            if ov and not ov.isPet then
                                retryEntry.spellID = ov.id
                                retryEntry.baseCd  = ov.cd
                                retryEntry.extraKicks = {}
                            elseif BIT.SPEC_NO_INTERRUPT[retrySpec] then
                                BIT.Registry:Remove(name)
                                BIT.Inspect.noKick[name] = true
                            end
                        end
                    end
                end
                if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
            end)
        end
    end
end

eventHandlers["UNIT_PET"] = function(unit)
    if unit == "player" then
        C_Timer.After(0.5, function() BIT.Self:FindInterrupt() end)
        C_Timer.After(1.5, function() BIT.Self:FindInterrupt() end)
        C_Timer.After(3.0, function() BIT.Self:FindInterrupt() end)
    end
    BIT:RegisterPartyWatchers()
    if unit and unit:find("^party") then
        local name = UnitName(unit)
        if name then
            BIT.Inspect:Invalidate(name)
        end
    end
end

eventHandlers["ROLE_CHANGED_INFORM"] = function()
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local name   = UnitName(u)
            local _, cls = UnitClass(u)
            local role   = UnitGroupRolesAssigned(u)
            if name and role == "HEALER" and not BIT.HEALER_KEEPS_KICK[cls] and BIT.Registry:Get(name) then
                BIT.Registry:Remove(name)
                BIT.Inspect.noKick[name] = true
            end
        end
    end
    -- Smart Misdirect: a role change can promote / demote a tank.
    if BIT.SmartMisdirect and BIT.SmartMisdirect.QueueUpdate then
        BIT.SmartMisdirect:QueueUpdate()
    end
end

eventHandlers["GROUP_ROSTER_UPDATE"] = function()
    BIT:CleanPartyList()
    BIT:RegisterPartyWatchers()
    BIT:AutoRegisterPartyByClass()
    C_Timer.After(1, function()
        -- Retry watcher registration: UnitExists may have been false on the
        -- immediate call above (WoW hasn't populated the unit data yet).
        BIT:RegisterPartyWatchers()
        BIT:AutoRegisterPartyByClass()
        BIT.Self:BroadcastHello()
        BIT.Self:BroadcastSyncHello()
        if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
    end)
    C_Timer.After(3, function()
        -- Second retry for slow-loading instances/phasing
        BIT:RegisterPartyWatchers()
        BIT:AutoRegisterPartyByClass()
        -- Re-restore cache: CleanPartyList may have wiped SyncCD.users entries
        -- during a zone transition (when UnitExists was temporarily false).
        -- By now (3s later) all units should be loaded.
        BIT:RestoreSyncCDCache()
    end)
    C_Timer.After(5, function()
        if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
    end)
    -- Smart Misdirect: recompute the target list when the roster changes.
    if BIT.SmartMisdirect and BIT.SmartMisdirect.QueueUpdate then
        BIT.SmartMisdirect:QueueUpdate()
    end
end

eventHandlers["PLAYER_LOGOUT"] = function()
    BIT.SaveCharProfile()
    if BIT.db and BIT.db.useGlobalDefault and BIT.db.globalProfile and BIT.SaveGlobalProfile then
        BIT.SaveGlobalProfile()
    end
    -- Auto-save active spec profile on logout if user opted in — lets the current
    -- spec's settings follow the player across characters on the same spec.
    if BIT.db and BIT.db.useSpecProfile and BIT.SaveSpecProfile then
        local sid = BIT.GetCurrentSpecID and BIT.GetCurrentSpecID()
        if sid and BIT.db.specProfiles and BIT.db.specProfiles[sid] then
            BIT.SaveSpecProfile(sid)
        end
    end
    -- Same for role profile: only overwrite if the user already has one saved for
    -- this role, to avoid creating unintended profiles on first logout.
    if BIT.db and BIT.db.useRoleProfile and BIT.SaveRoleProfile then
        local role = BIT.GetCurrentRole and BIT.GetCurrentRole()
        if role and BIT.db.roleProfiles and BIT.db.roleProfiles[role] then
            BIT.SaveRoleProfile(role)
        end
    end
end

eventHandlers["PLAYER_ENTERING_WORLD"] = function()
    BIT.inCombat = InCombatLockdown()
    BIT.Net:Register()

    -- Restore cached party talent data so spells are visible immediately after /reload.
    -- Needed because addon messages (LibSpec) are blocked in M+ after reload.
    -- LibSpec will overwrite this with fresh data as soon as communication resumes.
    BIT:RestoreSyncCDCache()

    -- Clear stale healer/no-kick and inspect state on every zone transition.
    -- Specs can change between dungeons; a Holy Paladin might be Retribution next run.
    BIT.Inspect.noKick = {}
    BIT.Inspect.done   = {}
    BIT.noInterruptPlayers = BIT.Inspect.noKick
    BIT.inspectedPlayers   = BIT.Inspect.done

    BIT.UI:CheckZoneVisibility()
    BIT:RegisterPartyWatchers()
    BIT:AutoRegisterPartyByClass()

    -- Re-apply saved frame position after zone transition.
    -- WoW can reset frame anchors when loading into a new instance/area,
    -- causing the tracker to drift. A short delay lets the UI fully settle first.
    C_Timer.After(0.2, function()
        if BIT.UI.ApplyFramePosition then
            BIT.UI.ApplyFramePosition()
        end
    end)

    C_Timer.After(1, function() BIT:AutoRegisterPartyByClass() end)
    C_Timer.After(3, function()
        BIT.Self:FindInterrupt()
        BIT.Self:BroadcastHello()
        BIT.Self:BroadcastSyncHello()
        BIT:AutoRegisterPartyByClass()
    end)
    -- Check for frame provider conflict on first login (ElvUI + Danders etc.)
    C_Timer.After(3, function()
        if BIT.SyncCD and BIT.SyncCD.CheckFrameProviderFirstRun then
            BIT.SyncCD:CheckFrameProviderFirstRun()
        end
    end)
    -- staggered SyncCD rebuilds to catch late HELLO + LibSpec data
    C_Timer.After(4,  function() if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end end)
    C_Timer.After(8,  function() if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end end)
    C_Timer.After(15, function() if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end end)
    -- Smart Misdirect: zone transitions / instance boundaries change unit tokens.
    if BIT.SmartMisdirect and BIT.SmartMisdirect.QueueUpdate then
        C_Timer.After(2, function() BIT.SmartMisdirect:QueueUpdate() end)
    end
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("GROUP_ROSTER_UPDATE")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("CHAT_MSG_ADDON")
ef:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ef:RegisterEvent("SPELLS_CHANGED")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")
-- ef:RegisterEvent("INSPECT_READY")  -- removed: no more inspect queue
ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ef:RegisterEvent("PLAYER_TALENT_UPDATE")
ef:RegisterEvent("TRAIT_CONFIG_UPDATED")
ef:RegisterEvent("SPELL_UPDATE_CHARGES")
ef:RegisterEvent("UNIT_PET")
ef:RegisterEvent("ROLE_CHANGED_INFORM")
ef:RegisterEvent("PLAYER_LOGOUT")

ef:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    local h = eventHandlers[event]
    if h then h(a1, a2, a3, a4) end
end)

------------------------------------------------------------
-- Test Mode
------------------------------------------------------------
local TEST_POOL = {
    { name="Jvyx",       class="DRUID",       spellID=106839 },
    { name="Klââsaim",   class="HUNTER",      spellID=187707 },
    { name="Kînglóuie",  class="DRUID",       spellID=106839 },
    { name="Mírajane",   class="MAGE",        spellID=2139   },
    { name="Hoschling",  class="MAGE",        spellID=2139   },
    { name="Frozenerza", class="DEATHKNIGHT", spellID=47528  },
    { name="Pandavii",   class="DEMONHUNTER", spellID=183752 },
    { name="Skytecc",    class="PALADIN",     spellID=96231  },
    { name="Wyrax",      class="WARRIOR",     spellID=6552   },
    { name="Àdrîk",     class="DRUID",       spellID=106839 },
    { name="Schmidich",  class="WARRIOR",     spellID=6552   },
    { name="Saddihunt",  class="HUNTER",      spellID=147362 },
    { name="Ragebûrn",  class="WARLOCK",     spellID=19647  },
    { name="Weebz",      class="MAGE",        spellID=2139   },
    { name="Akhíra",    class="WARLOCK",     spellID=119914 },
}

local _testSlots     = {}
local _testLoopTimer = nil

local function TestNextPlayer()
    local avail = {}
    for _, p in ipairs(TEST_POOL) do
        if not BIT.Registry:Get(p.name) then avail[#avail+1] = p end
    end
    if #avail == 0 then return TEST_POOL[math.random(1, #TEST_POOL)] end
    return avail[math.random(1, #avail)]
end

local function TestLoop()
    if not BIT.testMode then return end
    local now = GetTime()

    for i, name in ipairs(_testSlots) do
        local entry = BIT.Registry:Get(name)
        if entry then
            if entry.waitUntil then
                if now >= entry.waitUntil then
                    entry.cdEnd     = now + entry.baseCd
                    entry.waitUntil = nil
                end
            elseif now >= entry.cdEnd then
                BIT.Registry:Remove(name)
                local p    = TestNextPlayer()
                local data = BIT.ALL_INTERRUPTS[p.spellID]
                local cd   = data and data.cd or 15
                local e    = BIT.Registry:GetOrCreate(p.name)
                e.class     = p.class
                e.spellID   = p.spellID
                e.baseCd    = cd
                e.cdEnd     = now
                e.waitUntil = now + math.random(1, 6)
                _testSlots[i] = p.name
            end
        end
    end

    if now >= BIT.Self.kickCdEnd then
        BIT.Self.kickCdEnd = now + (BIT.Self.baseCd or 15)
        BIT.myKickCdEnd    = BIT.Self.kickCdEnd
    end

    BIT.UI:UpdateDisplay()
    _testLoopTimer = C_Timer.After(0.5, TestLoop)
end

function BIT:StartTestMode()
    if self.testMode then self:StopTestMode(); return end
    self.testMode = true
    self.ready    = true

    self._savedRegistry  = {}
    for k, v in pairs(BIT.Registry:All()) do self._savedRegistry[k] = v end
    self._savedSelf = {
        spellID   = BIT.Self.spellID,
        kickCdEnd = BIT.Self.kickCdEnd,
        name      = BIT.Self.name,
    }

    -- Use real player name/class so the own bar shows correctly
    local realName  = UnitName("player") or "You"
    local _, realCls = UnitClass("player")
    local testOwnSpell = BIT.Self.spellID
    local testOwnCd    = BIT.Self.baseCd or 15
    -- Fallback if no interrupt found (e.g. Holy Paladin in test)
    if not testOwnSpell then
        testOwnSpell = realCls and BIT.CLASS_INTERRUPTS[realCls] and BIT.CLASS_INTERRUPTS[realCls].id or 183752
        testOwnCd    = realCls and BIT.CLASS_INTERRUPTS[realCls] and BIT.CLASS_INTERRUPTS[realCls].cd or 15
    end

    BIT.Registry:Clear()
    _testSlots = {}
    local now = GetTime()

    local pool = {}
    for _, p in ipairs(TEST_POOL) do pool[#pool+1] = p end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    for i = 1, 4 do
        local p  = pool[i]
        local d  = BIT.ALL_INTERRUPTS[p.spellID]
        local cd = d and d.cd or 15
        local e  = BIT.Registry:GetOrCreate(p.name)
        e.class   = p.class
        e.spellID = p.spellID
        e.baseCd  = cd
        if i % 2 == 0 then
            e.cdEnd = now + (cd * i / 4)
        else
            e.cdEnd     = now
            e.waitUntil = now + math.random(2, 6)
        end
        _testSlots[i] = p.name
    end

    BIT.Self.name      = realName
    BIT.Self.spellID   = testOwnSpell
    BIT.Self.baseCd    = testOwnCd
    BIT.Self.kickCdEnd = now + 8
    BIT.myName         = BIT.Self.name
    BIT.mySpellID      = BIT.Self.spellID
    BIT.myKickCdEnd    = BIT.Self.kickCdEnd

    BIT.UI:CheckZoneVisibility(true)
    _testLoopTimer = C_Timer.After(0.5, TestLoop)
    print(BIT.L["MSG_TEST_ON"])
end

function BIT:StopTestMode()
    self.testMode  = false
    _testLoopTimer = nil
    _testSlots     = {}

    BIT.Registry:Clear()
    if self._savedRegistry then
        for k, v in pairs(self._savedRegistry) do
            BIT.Registry:GetOrCreate(k)
            for field, val in pairs(v) do
                BIT.Registry:Get(k)[field] = val
            end
        end
    end

    if self._savedSelf then
        BIT.Self.spellID   = self._savedSelf.spellID
        BIT.Self.kickCdEnd = self._savedSelf.kickCdEnd
        BIT.Self.name      = self._savedSelf.name
        BIT.mySpellID      = BIT.Self.spellID
        BIT.myKickCdEnd    = BIT.Self.kickCdEnd
        BIT.myName         = BIT.Self.name
    end

    self._savedRegistry = nil
    self._savedSelf     = nil

    BIT.UI:CheckZoneVisibility()
    BIT.UI:UpdateDisplay()
    print(BIT.L["MSG_TEST_OFF"])
end

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
SLASH_BLIZZITEST1 = "/bittest"
SlashCmdList["BLIZZITEST"] = function() BIT:StartTestMode() end

SLASH_BITROTATION1 = "/bitrotation"
SlashCmdList["BITROTATION"] = function() BIT.UI:ShowRotationPanel() end

--- /bitdevlog — toggle silent dev log (no chat spam; use /bitdevdump to review)
SLASH_BITDEVLOG1 = "/bitdevlog"
SlashCmdList["BITDEVLOG"] = function()
    BIT.devLogMode = not BIT.devLogMode
    if BIT.devLogMode then
        BIT.DevLogStart()
        print("|cffff9900BIT DevLog|r ON — logging silently. Use |cffffd700/bitdevdump|r to review.")
    else
        print("|cffff9900BIT DevLog|r OFF")
    end
end

--- /bitdevdump [N] [filter] — print last N entries, optionally filtered by keyword
--- Examples: /bitdevdump 200 363916   (Obsidian Scales)
---           /bitdevdump 100 GLOW-SET (all glow triggers)
---           /bitdevdump 0 GLOW-MISS  (all misses, entire buffer)
SLASH_BITDEVDUMP1 = "/bitdevdump"
SlashCmdList["BITDEVDUMP"] = function(args) BIT.DevLogDump(args) end

-- /bitreport — open the graphical debug report window
SLASH_BITREPORT1 = "/bitreport"
SlashCmdList["BITREPORT"] = function() if BIT.ToggleDebugReport then BIT.ToggleDebugReport() end end

SLASH_BLIZZIDEBUG1 = "/bitdebug"
SlashCmdList["BLIZZIDEBUG"] = function()
    BIT.debugMode = not BIT.debugMode
    -- Persist across reloads via saved vars
    if BIT.db then BIT.db.debugMode = BIT.debugMode end
    if BIT.debugMode then
        print(BIT.L["MSG_DEBUG_ON"])
        local count = 0
        for _ in pairs(BIT.Registry:All()) do count = count + 1 end
        print(BIT.L["MSG_DEBUG_PARTY"] .. " " .. count)
        for name, info in pairs(BIT.Registry:All()) do
            print("  |cFFAAAAFF" .. name .. "|r " .. tostring(info.class)
                  .. " sid=" .. tostring(info.spellID)
                  .. " baseCd=" .. tostring(info.baseCd))
        end
    else
        print(BIT.L["MSG_DEBUG_OFF"])
    end
end

-- /bitnetdebug — test addon message sending and receiving
SLASH_BITNETDEBUG1 = "/bitnetdebug"
SlashCmdList["BITNETDEBUG"] = function()
    local p = function(msg) print("|cff00ff80BIT-NET|r " .. msg) end
    p("=== Net Debug ===")
    p("LE_PARTY_CATEGORY_HOME="     .. tostring(LE_PARTY_CATEGORY_HOME))
    p("LE_PARTY_CATEGORY_INSTANCE=" .. tostring(LE_PARTY_CATEGORY_INSTANCE))
    p("IsInGroup(HOME)="     .. tostring(IsInGroup(LE_PARTY_CATEGORY_HOME)))
    p("IsInGroup(INSTANCE)=" .. tostring(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)))
    p("IsInGroup()="         .. tostring(IsInGroup()))
    p("IsInRaid()="          .. tostring(IsInRaid()))
    p("Registered prefix: "  .. tostring(C_ChatInfo.IsAddonMessagePrefixRegistered("BliZziIT")))

    -- Test SendAddonMessage on all channels
    p("--- SendAddonMessage ---")
    local channels = { "PARTY", "INSTANCE_CHAT", "RAID", "RAID_WARNING" }
    for _, ch in ipairs(channels) do
        local ok, ret = pcall(C_ChatInfo.SendAddonMessage, "BliZziIT", "B1;PING", ch)
        p("  " .. ch .. ": ok=" .. tostring(ok) .. " ret=" .. tostring(ret))
    end

    -- Test SendAddonMessageLogged (newer API)
    p("--- SendAddonMessageLogged ---")
    if C_ChatInfo.SendAddonMessageLogged then
        for _, ch in ipairs(channels) do
            local ok, ret = pcall(C_ChatInfo.SendAddonMessageLogged, "BliZziIT", "B1;PING", ch)
            p("  " .. ch .. ": ok=" .. tostring(ok) .. " ret=" .. tostring(ret))
        end
    else
        p("  SendAddonMessageLogged: NOT AVAILABLE")
    end

    -- Test WHISPER to each party member
    p("--- WHISPER to party members ---")
    local whisperSent = false
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitIsPlayer(u) then
            local ok, name, realm = pcall(UnitFullName, u)
            if ok and name then
                local target = (realm and realm ~= "") and (name .. "-" .. realm) or name
                local wok, wret = pcall(C_ChatInfo.SendAddonMessage, "BliZziIT", "B1;PING", "WHISPER", target)
                p("  WHISPER->" .. tostring(target) .. ": ok=" .. tostring(wok) .. " ret=" .. tostring(wret))
                whisperSent = true
            end
        end
    end
    if not whisperSent then p("  No party members found") end

    p("--- PING sent to PARTY — watch for BIT-NET PING RECEIVED on other client ---")
    pcall(C_ChatInfo.SendAddonMessage, "BliZziIT", "B1;PING", "PARTY")
    p("=== end ===")
end

-- /bitapidebug — check critical WoW APIs for Midnight compatibility
SLASH_BITAPIDEBUG1 = "/bitapidebug"
SlashCmdList["BITAPIDEBUG"] = function()
    local p = function(msg) print("|cffff9900BIT-API|r " .. msg) end
    p("=== API Debug (Midnight) ===")

    -- Spec detection
    local ok, specIdx = pcall(GetSpecialization)
    p("GetSpecialization(): ok=" .. tostring(ok) .. " val=" .. tostring(specIdx))

    if ok and specIdx then
        local ok2, sid, name, desc, icon, bg, role, cls = pcall(GetSpecializationInfo, specIdx)
        p("GetSpecializationInfo(" .. tostring(specIdx) .. "): ok=" .. tostring(ok2)
          .. " specID=" .. tostring(sid) .. " name=" .. tostring(name) .. " class=" .. tostring(cls))

        if ok2 and sid then
            local entry = BIT.SPEC_REGISTRY and BIT.SPEC_REGISTRY[sid]
            p("SPEC_REGISTRY[" .. tostring(sid) .. "]: " .. (entry and ("found → " .. tostring(entry.name)) or "NIL (spec not tracked!)"))
        end
    end

    -- Class detection
    local ok3, cls, clsToken = pcall(UnitClass, "player")
    p("UnitClass(player): ok=" .. tostring(ok3) .. " cls=" .. tostring(cls) .. " token=" .. tostring(clsToken))

    -- Party inspect
    p("--- Party members ---")
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local n = UnitName(u)
            local ok4, pCls, pToken = pcall(UnitClass, u)
            local ok5, pSpec = pcall(GetInspectSpecialization, u)
            p("  " .. tostring(u) .. " " .. tostring(n)
              .. " cls=" .. tostring(pToken)
              .. " spec=" .. tostring(pSpec))
        end
    end

    -- C_Traits availability
    p("--- C_Traits ---")
    p("C_ClassTalents.GetActiveConfigID: " .. tostring(C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or "N/A"))
    p("C_Traits.GetTreeNodes: " .. tostring(C_Traits and C_Traits.GetTreeNodes ~= nil))
    p("C_Traits.GetNodeInfo: " .. tostring(C_Traits and C_Traits.GetNodeInfo ~= nil))

    -- Key spell APIs
    p("--- Spell APIs ---")
    p("C_Spell.GetSpellCooldown: " .. tostring(C_Spell and C_Spell.GetSpellCooldown ~= nil))
    p("C_Spell.GetSpellCharges:  " .. tostring(C_Spell and C_Spell.GetSpellCharges ~= nil))
    p("C_SpellBook.IsSpellKnown: " .. tostring(C_SpellBook and C_SpellBook.IsSpellKnown ~= nil))

    p("=== end ===")
end

-- /bitcdrdebug — diagnose talentMods / talentCharges for own player
SLASH_BITCDRDEBUG1 = "/bitcdrdebug"
SlashCmdList["BITCDRDEBUG"] = function()
    local p = function(msg) print("|cff0091edBIT-CDR|r " .. msg) end
    local me = BIT.myName
    p("=== Party CD Talent Debug for: " .. tostring(me) .. " ===")

    -- 1. knownSpells cache
    local ue = BIT.SyncCD and BIT.SyncCD.users and BIT.SyncCD.users[me]
    local ks = ue and ue.knownSpells
    if not ks then
        p("|cFFFF4444knownSpells = nil|r  (ScanOwnTalents() produced no data)")
    else
        local n = 0; for _ in pairs(ks) do n = n + 1 end
        p("knownSpells: " .. n .. " entries")
        -- Check specific talent IDs we care about
        local watchIDs = { 389732, 397103, 384072 }  -- Down in Flames, Defender's Aegis, Impenetrable Wall
        local names    = { [389732]="Down in Flames", [397103]="Defender's Aegis", [384072]="Impenetrable Wall" }
        for _, tid in ipairs(watchIDs) do
            local found = ks[tid] and "|cFF44FF44YES|r" or "|cFFFF4444NO|r"
            p("  [" .. tid .. "] " .. (names[tid] or "?") .. " → " .. found)
        end
    end

    -- 2. Spell entries returned by GetSpellsForPlayer
    p("--- GetSpellsForPlayer results ---")
    local specIdx = GetSpecialization()
    local specID  = specIdx and select(1, GetSpecializationInfo(specIdx))
    p("specID = " .. tostring(specID))
    local spells = specID and BIT.SYNC_SPELLS and BIT.SYNC_SPELLS[specID]
    if spells then
        for _, s in ipairs(spells) do
            local watch = { [871]=true, [204021]=true, [23920]=true }
            if watch[s.id] then
                p("  BASE [" .. s.id .. "] " .. s.name
                  .. " cd=" .. s.cd
                  .. " charges=" .. tostring(s.charges)
                  .. " talentMods=" .. tostring(s.talentMods ~= nil)
                  .. " talentCharges=" .. tostring(s.talentCharges ~= nil))
            end
        end
    end

    -- 3. ScanOwnTalents on-demand and show result
    p("--- Running ScanOwnTalents() now ---")
    if BIT.SyncCD and BIT.SyncCD.ScanOwnTalents then
        BIT.SyncCD:ScanOwnTalents()
        local ue2 = BIT.SyncCD.users and BIT.SyncCD.users[me]
        local ks2 = ue2 and ue2.knownSpells
        if not ks2 then
            p("|cFFFF4444Still nil after scan.|r")
        else
            local n2 = 0; for _ in pairs(ks2) do n2 = n2 + 1 end
            p("Scan OK — " .. n2 .. " spells found")
            local watchIDs = { 389732, 397103, 384072 }
            local names    = { [389732]="Down in Flames", [397103]="Defender's Aegis", [384072]="Impenetrable Wall" }
            for _, tid in ipairs(watchIDs) do
                local found = ks2[tid] and "|cFF44FF44YES|r" or "|cFFFF4444NO|r"
                p("  [" .. tid .. "] " .. (names[tid] or "?") .. " → " .. found)
            end
        end
    else
        p("|cFFFF4444ScanOwnTalents not available|r")
    end
    p("=== end ===")
end

-- /bitchargedebug — diagnose why charge badge is not showing
SLASH_BITCHARGEDEBUG1 = "/bitchargedebug"
SlashCmdList["BITCHARGEDEBUG"] = function()
    local p = function(msg) print("|cff0091edBIT-CHARGE|r " .. msg) end
    p("=== Charge Badge Debug ===")

    -- 1. Query C_Spell.GetSpellCharges for Fiery Brand and Shield Wall directly
    local testIDs = { [204021] = "Fiery Brand", [871] = "Shield Wall" }
    for sid, sname in pairs(testIDs) do
        local ok, result = pcall(C_Spell.GetSpellCharges, sid)
        p(sname .. " (" .. sid .. "): ok=" .. tostring(ok) .. " result=" .. tostring(result) .. " type=" .. type(result))
        if ok and result and type(result) == "table" then
            local okC, c = pcall(function() return BIT.Taint:Resolve(result.currentCharges) end)
            local okM, m = pcall(function() return BIT.Taint:Resolve(result.maxCharges) end)
            p("  currentCharges: okC=" .. tostring(okC) .. " val=" .. tostring(c))
            p("  maxCharges:     okM=" .. tostring(okM) .. " val=" .. tostring(m))
        elseif ok and result then
            p("  (legacy) currentCharges=" .. tostring(result))
        end
    end

    -- 2. Check icons in attached bars and window rows
    local checked = 0
    local function checkIcons(icons, source)
        for sid, ico in pairs(icons) do
            if sid == 204021 or sid == 871 then
                checked = checked + 1
                p("Icon sid=" .. sid .. " source=" .. source
                  .. " _maxCharges=" .. tostring(ico._maxCharges)
                  .. " spellID=" .. tostring(ico.spellID)
                  .. " badgeShown=" .. tostring(ico.chargeBadge and ico.chargeBadge:IsShown()))
            end
        end
    end
    if BIT.SyncCD then
        for unit, bar in pairs(BIT.SyncCD._attachedBars or {}) do
            checkIcons(bar.icons or {}, "attach:" .. tostring(unit))
        end
    end
    if checked == 0 then
        p("|cFFFFAA00No Fiery Brand/Shield Wall icons found in attachedBars.|r")
        p("Forcing RefreshCharges now...")
        if BIT.SyncCD and BIT.SyncCD.RefreshCharges then
            BIT.SyncCD:RefreshCharges()
            p("Done.")
        end
    end
    p("=== end ===")
end
