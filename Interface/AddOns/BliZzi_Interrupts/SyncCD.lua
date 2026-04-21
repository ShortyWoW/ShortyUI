-- Copyright (c) 2026 BliZzi1337. All rights reserved.
-- Unauthorized copying, modification, distribution or use of this
-- software, in whole or in part, without prior written permission
-- from the copyright holder is strictly prohibited.
--[[
    SyncCD.lua - BliZzi_Interrupts
    ─────────────────────────────────────────────────────────
    Tracks important defensive/offensive cooldowns for party
    members who also have the addon installed.

    Two display modes (configurable in Settings → Party CDs):
      WINDOW  — standalone draggable frame, one row per player
      ATTACH  — icons anchored to existing party unit frames
                (ElvUI or Blizzard compact frames), with
                configurable side (Left/Right/Top/Bottom)

    Spell detection:
      • Own casts     — UNIT_SPELLCAST_SUCCEEDED for "player"
      • Party casts   — Aura detection (BIG_DEFENSIVE /
                        EXTERNAL_DEFENSIVE / IMPORTANT categories) with
                        evidence system (Cast, Debuff, Shield, UnitFlags,
                        FeignDeath) + duration matching against rules.
                        SYNCCD addon messages as faster alternative.

    Works for ALL party members (no addon required on their side).
    ─────────────────────────────────────────────────────────
]]

BIT.SyncCD      = BIT.SyncCD      or {}
BIT.syncCdState = BIT.syncCdState or {}

------------------------------------------------------------
-- Spell data aliases (tables live in SpellData.lua)
------------------------------------------------------------
local replacedByToBase    = BIT.SyncCD.replacedByToBase
local _syncSpellLookup    = BIT.SyncCD.spellLookup
local _syncSpellLookupStr = BIT.SyncCD.spellLookupStr

-- ── FIFO ring buffer for charge tracking ────────────────────────────
-- Fixed-size queue: oldest charge at tail(), newest at head().
-- Each slot stores the GetTime() at which that charge becomes available.
local function CreateFIFO(size)
    local q = { _buf = {}, _head = 0, _tail = 0, _size = size, _count = 0 }
    function q:push(val)
        if self._count >= self._size then
            -- overwrite oldest (advance tail)
            self._tail = self._tail % self._size + 1
        else
            self._count = self._count + 1
        end
        self._head = self._head % self._size + 1
        self._buf[self._head] = val
    end
    function q:head()
        if self._count == 0 then return 0 end
        return self._buf[self._head]
    end
    function q:tail()
        if self._count == 0 then return 0 end
        return self._buf[self._tail == 0 and 1 or self._tail]
    end
    function q:count() return self._count end
    function q:availableCharges(now)
        -- Count charges whose recharge time has passed
        local avail = 0
        local idx = self._tail == 0 and 1 or self._tail
        for i = 1, self._count do
            if self._buf[idx] <= now then avail = avail + 1 end
            idx = idx % self._size + 1
        end
        return avail
    end
    function q:nextRechargeAt()
        -- Returns the earliest future recharge time (for CD swipe display)
        local now = GetTime()
        local earliest = nil
        local idx = self._tail == 0 and 1 or self._tail
        for i = 1, self._count do
            local t = self._buf[idx]
            if t > now then
                if not earliest or t < earliest then earliest = t end
            end
            idx = idx % self._size + 1
        end
        return earliest
    end
    function q:lastRechargeAt()
        -- Returns the latest recharge time (all charges back at this time)
        local latest = 0
        local idx = self._tail == 0 and 1 or self._tail
        for i = 1, self._count do
            if self._buf[idx] > latest then latest = self._buf[idx] end
            idx = idx % self._size + 1
        end
        return latest
    end
    -- Initialize all slots as "available now" (time 0)
    for i = 1, size do
        q:push(0)
    end
    return q
end

-- Per-player per-spell charge tracker:
-- _chargeTracker[name][spellID] = { fifo=FIFO, maxCharges=N, baseCd=seconds }
local _chargeTracker = {}

local function GetChargeTracker(name, spellID, maxCharges, baseCd)
    if not _chargeTracker[name] then _chargeTracker[name] = {} end
    local ct = _chargeTracker[name][spellID]
    if ct and ct.maxCharges == maxCharges then return ct end
    -- Create or recreate if maxCharges changed
    ct = { fifo = CreateFIFO(maxCharges), maxCharges = maxCharges, baseCd = baseCd }
    _chargeTracker[name][spellID] = ct
    return ct
end

local function ClearChargeTracker(name)
    _chargeTracker[name] = nil
end

-- ── Party aura detection state ───────────────────────────────────────
-- Evidence timestamps (per unit)
local _lastCastTime       = {}  -- UNIT_SPELLCAST_SUCCEEDED
local _lastDebuffTime     = {}  -- HARMFUL aura added
local _lastShieldTime     = {}  -- UNIT_ABSORB_AMOUNT_CHANGED
local _lastUnitFlagsTime  = {}  -- UNIT_FLAGS (non-feign)
local _lastFeignDeathTime = {}  -- UNIT_FLAGS feign death transition
local _prevFeignDeath     = {}  -- previous UnitIsFeignDeath state
local _fdAuraActive       = false  -- own-player FD aura presence (UNIT_AURA-driven)
local _lastCombatDropTime = {}  -- UNIT_FLAGS: inCombat true→false
local _prevInCombat       = {}  -- previous UnitAffectingCombat state
local _lastDebuffRemovedTime = {} -- HARMFUL aura removed (for Stoneform etc.)
local _lastBuffTime       = {}  -- HELPFUL aura added
-- Tracked auras: _trackedPartyAuras[unit][auraInstanceID] = FcdTrackedAura
local _trackedPartyAuras = {}
-- Buff active end times: _buffActiveEnd[playerName][spellID] = GetTime() + buffDur
-- Declared here (above CommitCooldown) so CommitCooldown can access it.
local _buffActiveEnd = {}
-- Buff-active glow state per player per spell.
-- Set at aura-appear time via FindGlowOnAuraAppear (deferred backfill).
-- Cleared by CommitCooldown when the aura expires.
-- Timing constants
local EVIDENCE_TOLERANCE            = 0.10   -- concurrent evidence wait / deferred backfill
local CAST_WINDOW                   = 0.15   -- cast-to-aura detection window
local DURATION_TOLERANCE            = 0.30   -- measured vs expected buff duration tolerance
local CASTTIME_CONFIDENT_DIFFERENCE = 0.150  -- best caster must beat 2nd best by this margin

------------------------------------------------------------
-- Constants
------------------------------------------------------------
local NAME_W   = 80
local function ICON_SIZE() return (BIT.db and BIT.db.syncCdIconSize) or 28 end
local function ICON_PAD()  return (BIT.db and BIT.db.syncCdIconSpacing ~= nil) and BIT.db.syncCdIconSpacing or 4 end
local function ROW_H()     return ICON_SIZE() + 6 end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
-- UnitName() returns a tainted string in Midnight 12.x for party members.
-- Strategy:
--   1. Try pcall(string.format) to detaint (works in pre-Midnight).
--   2. Verify the result is actually untainted by attempting rawset as table key.
--      If rawset fails with "table index is secret", the string is still tainted → return nil.
-- Callers receive nil for any still-tainted name and skip that unit.
local function SafeUnitName(unit)
    if not unit then return nil end
    local raw = UnitName(unit)
    if not raw then return nil end
    local ok1, clean = pcall(string.format, "%s", raw)
    if not ok1 or not clean then return nil end
    -- Verify untainted: attempt to use it as a table key.
    -- In Midnight, string.format may not detaint; rawset catches the residual taint.
    local ok2 = pcall(rawset, {}, clean, true)
    return ok2 and clean or nil
end

local function IsSpellEnabled(sid)
    -- notTrackable spells (e.g. Power Infusion) are always hidden from the tracker
    local entry = _syncSpellLookup[sid]
    if entry and entry.notTrackable then return false end
    return not (BIT.db.syncCdDisabled and BIT.db.syncCdDisabled[sid])
end

local function GetCatRow(cat)
    if cat == "DMG" then return tonumber(BIT.db.syncCdCatRowDMG) or 1 end
    if cat == "DEF" then return tonumber(BIT.db.syncCdCatRowDEF) or 2 end
    -- CC tracking removed
    return 1
end

local function IsCatEnabled(cat)
    if cat == "CC"  then return false end  -- CC tracking removed
    if cat == "DEF" then return BIT.db.syncCdShowDEF ~= false end
    if cat == "DMG" then return BIT.db.syncCdShowDMG ~= false end
    return true
end

------------------------------------------------------------
-- Tooltip-based spec detection (synchronous, no inspect needed)
-- Parses "Shadow Priest" / "Holy Paladin" from unit tooltip.
------------------------------------------------------------
local _tooltipSpecMap
local function GetTooltipSpecMap()
    if _tooltipSpecMap then return _tooltipSpecMap end
    _tooltipSpecMap = {}
    if not (GetNumClasses and GetClassInfo and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID) then
        return _tooltipSpecMap
    end
    for classIdx = 1, GetNumClasses() do
        local className, _, classId = GetClassInfo(classIdx)
        if className and classId then
            for specIdx = 1, GetNumSpecializationsForClassID(classId) do
                local specId, specName = GetSpecializationInfoForClassID(classId, specIdx)
                if specId and specName then
                    _tooltipSpecMap[specName .. " " .. className] = specId
                end
            end
        end
    end
    return _tooltipSpecMap
end

local function SpecFromTooltip(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or not tooltipData then return nil end
    local specMap = GetTooltipSpecMap()
    for _, line in ipairs(tooltipData.lines) do
        if line and line.leftText and not issecretvalue(line.leftText) then
            local specId = specMap[line.leftText]
            if specId then return specId end
        end
    end
    return nil
end

local function GetSpecForPlayer(name)
    -- check SyncCD.users first (set by LibSpecialization or HELLOSYNC)
    local entry = BIT.SyncCD.users and BIT.SyncCD.users[name]
    if entry and entry.specID and entry.specID > 0 then
        return entry.specID
    end
    -- own player
    if name == BIT.myName then
        local idx = GetSpecialization()
        return idx and select(1, GetSpecializationInfo(idx))
    end
    -- fallback: check party unit frames directly
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and SafeUnitName(u) == name then
            -- Fast path: tooltip parsing (instant, no async inspect)
            local sid = SpecFromTooltip(u)
            -- Slow path: GetInspectSpecialization (requires prior inspect)
            if not sid or sid == 0 then
                sid = GetInspectSpecialization(u)
            end
            if sid and sid > 0 then
                if not BIT.SyncCD.users then BIT.SyncCD.users = {} end
                if not BIT.SyncCD.users[name] then BIT.SyncCD.users[name] = {} end
                BIT.SyncCD.users[name].specID = sid
                return sid
            end
            return nil
        end
    end
end

-- Returns a set of known talent IDs for the given player.
-- Both own player and party members use knownSpells built from C_Traits scans.
-- Own player's cache is rebuilt by ScanOwnTalents() on every talent change.
local function GetKnownTalents(name)
    local ue = BIT.SyncCD.users and BIT.SyncCD.users[name]
    return (ue and ue.knownSpells) or {}
end

-- Returns a copy of spell entry `s` with talent effects applied:
--   talentMods    → adjusts s.cd downward
--   talentCharges → adjusts s.charges
-- Only creates a new table when something actually changes.
local function ApplyTalentEffects(s, knownTalents)
    local newCd      = s.cd
    local newCharges = s.charges
    if s.talentMods then
        for talentID, reduction in pairs(s.talentMods) do
            if knownTalents[talentID] then
                newCd = math.max(1, newCd - reduction)
            end
        end
    end
    if s.talentCharges then
        for talentID, chargeCount in pairs(s.talentCharges) do
            if knownTalents[talentID] then
                newCharges = chargeCount
            end
        end
    end
    if newCd == s.cd and newCharges == s.charges then return s end
    -- shallow copy with adjusted values
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.cd      = newCd
    copy.charges = newCharges
    return copy
end

------------------------------------------------------------
-- Evidence system
------------------------------------------------------------
local function BuildEvidenceSet(unit, detectionTime)
    local ev = nil
    -- Debuff evidence
    if _lastDebuffTime[unit] and math.abs(detectionTime - _lastDebuffTime[unit]) <= EVIDENCE_TOLERANCE then
        ev = ev or {}; ev.Debuff = true
    end
    -- Shield evidence
    if _lastShieldTime[unit] and math.abs(detectionTime - _lastShieldTime[unit]) <= EVIDENCE_TOLERANCE then
        ev = ev or {}; ev.Shield = true
    end
    -- FeignDeath and UnitFlags are mutually exclusive
    local hasFD = _lastFeignDeathTime[unit] and math.abs(detectionTime - _lastFeignDeathTime[unit]) <= CAST_WINDOW
    if hasFD then
        ev = ev or {}; ev.FeignDeath = true
    else
        if _lastUnitFlagsTime[unit] and math.abs(detectionTime - _lastUnitFlagsTime[unit]) <= CAST_WINDOW then
            ev = ev or {}; ev.UnitFlags = true
        end
    end
    -- Cast evidence
    if _lastCastTime[unit] and math.abs(detectionTime - _lastCastTime[unit]) <= CAST_WINDOW then
        ev = ev or {}; ev.Cast = true
    end
    -- Combat drop evidence (for Shadowmeld, Vanish)
    if _lastCombatDropTime[unit] and math.abs(detectionTime - _lastCombatDropTime[unit]) <= EVIDENCE_TOLERANCE then
        ev = ev or {}; ev.CombatDrop = true
    end
    -- Buff evidence (concurrent helpful aura)
    if _lastBuffTime[unit] and math.abs(detectionTime - _lastBuffTime[unit]) <= EVIDENCE_TOLERANCE then
        ev = ev or {}; ev.Buff = true
    end
    -- Debuff removed evidence (for Stoneform)
    if _lastDebuffRemovedTime[unit] and math.abs(detectionTime - _lastDebuffRemovedTime[unit]) <= EVIDENCE_TOLERANCE then
        ev = ev or {}; ev.DebuffRemoved = true
    end
    return ev
end

local function SnapshotCastTimes()
    local snap = {}
    for u, t in pairs(_lastCastTime) do snap[u] = t end
    return snap
end

------------------------------------------------------------
-- Aura types signature helper (used in rule matching and devlog)
------------------------------------------------------------
local function AuraTypesSignature(auraTypes)
    local s = ""
    if auraTypes.BIG_DEFENSIVE       then s = s .. "B" end
    if auraTypes.EXTERNAL_DEFENSIVE  then s = s .. "E" end
    if auraTypes.IMPORTANT           then s = s .. "I" end
    return s
end

------------------------------------------------------------
-- Rule matching
------------------------------------------------------------
-- AuraTypes: { BIG_DEFENSIVE=true, EXTERNAL_DEFENSIVE=true, IMPORTANT=true }
-- Tri-state logic:
--   true  = aura MUST be in this category
--   false = aura MUST NOT be in this category
--   nil   = don't care
-- Note: Important=false is NOT checked.
-- IMPORTANT can co-exist with any primary category.

local function AuraTypeMatchesRule(auraTypes, rule)
    if rule.BigDefensive == true  and not auraTypes.BIG_DEFENSIVE       then return false end
    if rule.BigDefensive == false and     auraTypes.BIG_DEFENSIVE       then return false end
    if rule.ExternalDefensive == true  and not auraTypes.EXTERNAL_DEFENSIVE then return false end
    if rule.ExternalDefensive == false and     auraTypes.EXTERNAL_DEFENSIVE then return false end
    if rule.Important == true  and not auraTypes.IMPORTANT then return false end
    -- Important=false is intentionally NOT checked — treated as "don't care".
    return true
end

local function EvidenceMatchesReq(req, evidence)
    if req == nil then return true end
    if req == false then return not evidence or next(evidence) == nil end
    if type(req) == "string" then
        return evidence and evidence[req] == true
    end
    if type(req) == "table" then
        if not evidence then return false end
        for _, key in ipairs(req) do
            if not evidence[key] then return false end
        end
        return true
    end
    return true
end

-- Matches aura against rules for a specific unit.
-- Returns best matching rule or nil.
-- buffSpellId: the actual spellId of the buff (from Blizzard aura data).
-- When provided, only rules whose SpellId matches are considered.
-- This disambiguates spells with identical AuraTypes + duration (e.g. SotF vs AoT).
local function MatchRule(unit, auraTypes, measuredDur, evidence, activeCooldowns, buffSpellId, isRaidInCombat)
    local name = SafeUnitName(unit)
    if not name then return nil end

    local specID = GetSpecForPlayer(name)
    local ok, classToken = pcall(UnitClassBase or UnitClass, unit)
    if not ok or not classToken then return nil end

    -- Rule table generated from SpellData.lua. Use the bySpec/byClass structure.
    local rulesBySpec  = BIT.SyncCD._rulesBySpec
    local rulesByClass = BIT.SyncCD._rulesByClass
    if not rulesBySpec or not rulesByClass then return nil end

    local knownTalents = GetKnownTalents(name)
    local bestRule     = nil
    local fallback     = nil

    local function tryRuleList(ruleList)
        if not ruleList then return end
        for _, rule in ipairs(ruleList) do
            -- SpellId gate (strict): require the buff's spellId to be known AND match the rule.
            -- Missing spellId would otherwise let rules match on AuraTypes+Evidence+Duration alone,
            -- causing cross-spell false attributions when two defensives share those properties.
            if (not buffSpellId) or rule.SpellId ~= buffSpellId then
                -- skip: buff spellId missing or doesn't match this rule
            -- RaidInCombat gate: skip player-defensive rules for boss-applied M+ buffs
            elseif rule.RaidInCombatExclude and isRaidInCombat then
                -- skip: aura is RAID_IN_COMBAT (boss buff), not a player defensive
            -- Talent gates
            elseif rule.ExcludeIfTalent and knownTalents[rule.ExcludeIfTalent] then
                -- skip: mutually exclusive talent present
            elseif rule.RequiresTalent and not knownTalents[rule.RequiresTalent] then
                -- skip: required talent missing
            else
                -- Aura type check
                if AuraTypeMatchesRule(auraTypes, rule) then
                    -- Evidence check
                    if EvidenceMatchesReq(rule.RequiresEvidence, evidence) then
                        -- Duration check: apply talent-modified buffDur
                        local expectedDur = rule.BuffDuration
                        -- Apply talent duration modifiers if available
                        if rule._durationMods then
                            for talentID, amount in pairs(rule._durationMods) do
                                if knownTalents[talentID] then
                                    expectedDur = expectedDur + amount
                                end
                            end
                        end

                        local durMatch = false
                        if rule.CanCancelEarly then
                            local minDur = rule.MinActualDuration or 0
                            durMatch = measuredDur >= minDur and measuredDur <= (expectedDur + DURATION_TOLERANCE)
                        elseif type(rule.MinDuration) == "number" then
                            durMatch = measuredDur >= rule.MinDuration
                        elseif rule.MinDuration then
                            durMatch = measuredDur >= (expectedDur - DURATION_TOLERANCE)
                        else
                            durMatch = math.abs(measuredDur - expectedDur) <= DURATION_TOLERANCE
                        end

                        if durMatch then
                            -- Check if this spell is already on CD (deprioritize)
                            local sid = rule.SpellId
                            local alreadyActive = activeCooldowns and sid
                                and activeCooldowns[sid] and activeCooldowns[sid] > GetTime()
                            if alreadyActive then
                                if not fallback then fallback = rule end
                            else
                                bestRule = rule
                                return  -- first match wins (spec rules checked first)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Spec rules first (higher priority)
    if specID then tryRuleList(rulesBySpec[specID]) end
    -- Class rules fallback
    if not bestRule then tryRuleList(rulesByClass[classToken]) end
    -- Racial rules (race-based abilities like Shadowmeld, Stoneform)
    if not bestRule and BIT.SyncCD._rulesByRace then
        -- UnitRace returns (localizedName, raceFile) — raceFile is the locale-independent key
        local okR, _, raceFile = pcall(UnitRace, unit)
        if okR and raceFile then
            tryRuleList(BIT.SyncCD._rulesByRace[raceFile])
        end
    end

    return bestRule or fallback
end

------------------------------------------------------------
-- Build candidate-specific evidence for FindBestCandidate
------------------------------------------------------------
local function BuildCandidateEvidence(baseEvidence, castSnapshot, candidateUnit, detectionTime)
    local ev = {}
    -- Copy non-Cast evidence from the tracked aura
    if baseEvidence then
        if baseEvidence.Debuff         then ev.Debuff         = true end
        if baseEvidence.Shield         then ev.Shield         = true end
        if baseEvidence.UnitFlags      then ev.UnitFlags      = true end
        if baseEvidence.FeignDeath     then ev.FeignDeath     = true end
        if baseEvidence.CombatDrop     then ev.CombatDrop     = true end
        if baseEvidence.Buff           then ev.Buff           = true end
        if baseEvidence.DebuffRemoved  then ev.DebuffRemoved  = true end
    end
    -- Cast evidence is per-candidate: only if THIS candidate had a recent cast
    if castSnapshot and castSnapshot[candidateUnit] then
        if math.abs(detectionTime - castSnapshot[candidateUnit]) <= CAST_WINDOW then
            ev.Cast = true
        end
    end
    if next(ev) == nil then return nil end
    return ev
end

------------------------------------------------------------
-- FindBestCandidate: who cast this aura? (for externals)
------------------------------------------------------------
local function FindBestCandidate(unit, tracked, measuredDur)
    local bestRule         = nil
    local bestUnit         = nil
    local bestCastTimeDiff = nil   -- abs(aura appear - cast time), smaller = better
    local bestIsTarget     = nil

    local function consider(candidateUnit, isTarget)
        local cEvidence = BuildCandidateEvidence(tracked.Evidence, tracked.CastSnapshot,
                                                  candidateUnit, tracked.StartTime)
        local cdState = BIT.syncCdState and BIT.syncCdState[SafeUnitName(candidateUnit)]
        local rule = MatchRule(candidateUnit, tracked.AuraTypes, measuredDur, cEvidence, cdState, tracked.SpellId, tracked.IsRaidInCombat)
        if not rule then return end
        -- Non-target candidates may only claim external defensive rules.
        -- Prevents e.g. Barkskin (ExternalDefensive=false) from being attributed
        -- to the Druid when a DK's AMS appears on the scanned unit and self-match fails.
        if not isTarget and not rule.ExternalDefensive then return end

        local castTime = tracked.CastSnapshot and tracked.CastSnapshot[candidateUnit]
        -- diff = how close this cast was to the aura appearing (smaller = better)
        local castDiff = (cEvidence and cEvidence.Cast and castTime)
                         and math.abs(tracked.StartTime - castTime) or nil

        local isBetter = false
        if not bestRule then
            isBetter = true
        elseif castDiff and (not bestCastTimeDiff or castDiff < bestCastTimeDiff) then
            -- This candidate's cast was closer to the aura appear time.
            -- Only win if the margin exceeds CASTTIME_CONFIDENT_DIFFERENCE.
            local margin = bestCastTimeDiff and (bestCastTimeDiff - castDiff) or math.huge
            if margin >= CASTTIME_CONFIDENT_DIFFERENCE then
                isBetter = true
            end
        elseif not castDiff and not bestCastTimeDiff
               and tracked.AuraTypes.EXTERNAL_DEFENSIVE and not isTarget and bestIsTarget then
            -- No cast evidence on either side: prefer non-target external caster
            isBetter = true
        end

        if isBetter then
            bestRule         = rule
            bestUnit         = candidateUnit
            bestCastTimeDiff = castDiff
            bestIsTarget     = isTarget
        end
    end

    -- Check the target unit first
    consider(unit, true)
    -- Check all other party members
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not UnitIsUnit(u, unit) then
            consider(u, false)
        end
    end
    -- Also check player
    if not UnitIsUnit("player", unit) then
        consider("player", false)
    end

    return bestRule, bestUnit
end

------------------------------------------------------------
-- FindGlowOnAuraAppear: called at aura-appear time (after evidence backfill)
-- to set _buffActiveEnd so UpdateIcon shows the glow while the buff is active.
-- Skips duration check (we haven't measured duration yet).
-- Only matches rules with BuffDuration > 0 (glow candidates).
------------------------------------------------------------
local function FindGlowOnAuraAppear(unit, tracked)
    local function tryMatch(candidateUnit)
        local cName = UnitIsUnit(candidateUnit, "player") and BIT.myName or SafeUnitName(candidateUnit)
        if not cName then return nil, nil end
        local specID = GetSpecForPlayer(cName)
        local okC, classToken = pcall(UnitClassBase or UnitClass, candidateUnit)
        if not okC or not classToken then return nil, nil end

        local cEvidence = BuildCandidateEvidence(tracked.Evidence, tracked.CastSnapshot,
                                                  candidateUnit, tracked.StartTime)
        local knownTalents = GetKnownTalents(cName)
        local rulesBySpec  = BIT.SyncCD._rulesBySpec
        local rulesByClass = BIT.SyncCD._rulesByClass

        local function checkList(ruleList)
            if not ruleList then return nil end
            for _, rule in ipairs(ruleList) do
                if (rule.BuffDuration or 0) > 0 then
                    -- SpellId gate (strict): the buff's spellId must be known AND match the rule.
                    -- A missing spellId (tainted/unavailable in WoW 12.x) would otherwise let any
                    -- rule match on AuraTypes+Evidence alone, causing cross-spell false glows
                    -- (e.g. Hunter SotF aura attributed to DH Blur rule when evidence aligns).
                    if (not tracked.SpellId) or rule.SpellId ~= tracked.SpellId then
                        if BIT.devLogMode then
                            BIT.DevLog("[GLOW-MISS] " .. tostring(cName) .. " SpellId gate: buff="
                                .. tostring(tracked.SpellId) .. " rule=" .. tostring(rule.SpellId))
                        end
                    -- RaidInCombat gate: skip player-defensive rules when the aura is RAID_IN_COMBAT
                    -- (boss-applied M+ buffs).  RaidInCombatExclude=true marks rules for spells
                    -- that are never RAIDINCOMBAT (Barkskin, Ironbark …).
                    elseif rule.RaidInCombatExclude and tracked.IsRaidInCombat then
                        if BIT.devLogMode then
                            BIT.DevLog("[GLOW-MISS] " .. tostring(cName) .. " RaidInCombat gate: rule="
                                .. tostring(rule.SpellId) .. " is RIC buff, skipping")
                        end
                    elseif rule.ExcludeIfTalent and knownTalents[rule.ExcludeIfTalent] then
                    elseif rule.RequiresTalent and not knownTalents[rule.RequiresTalent] then
                    elseif not AuraTypeMatchesRule(tracked.AuraTypes, rule) then
                        if BIT.devLogMode then
                            BIT.DevLog("[GLOW-MISS] " .. tostring(cName) .. " AuraType mismatch: types="
                                .. AuraTypesSignature(tracked.AuraTypes)
                                .. " rule.Big=" .. tostring(rule.BigDefensive)
                                .. " rule.Ext=" .. tostring(rule.ExternalDefensive)
                                .. " rule.Imp=" .. tostring(rule.Important))
                        end
                    elseif not EvidenceMatchesReq(rule.RequiresEvidence, cEvidence) then
                        if BIT.devLogMode then
                            local evParts = {}
                            if cEvidence then
                                for k in pairs(cEvidence) do evParts[#evParts+1] = k end
                            end
                            BIT.DevLog("[GLOW-MISS] " .. tostring(cName)
                                .. " spell=" .. tostring(rule.SpellId)
                                .. " Evidence mismatch: req=" .. tostring(rule.RequiresEvidence)
                                .. " have=" .. (next(evParts) and table.concat(evParts, "+") or "none"))
                        end
                    else
                        return rule
                    end
                end
            end
            return nil
        end

        local rule
        if specID and rulesBySpec then rule = checkList(rulesBySpec[specID]) end
        if not rule and rulesByClass then rule = checkList(rulesByClass[classToken]) end
        if BIT.devLogMode and rule then
            BIT.DevLog("[GLOW-MATCH] " .. tostring(cName) .. " spell=" .. tostring(rule.SpellId)
                .. " types=" .. AuraTypesSignature(tracked.AuraTypes)
                .. " spellIdOnAura=" .. tostring(tracked.SpellId))
        end
        if BIT.devLogMode and not rule then
            BIT.DevLog("[GLOW-NOMATCH] " .. tostring(cName) .. " spec=" .. tostring(specID)
                .. " class=" .. tostring(classToken)
                .. " types=" .. AuraTypesSignature(tracked.AuraTypes)
                .. " spellIdOnAura=" .. tostring(tracked.SpellId))
        end
        if rule then return rule, candidateUnit end
        return nil, nil
    end

    -- Self-cast first (Desperate Prayer, etc.) — unambiguous, no ranking needed
    local rule, ruleUnit = tryMatch(unit)
    if rule then return rule, ruleUnit end

    -- External casts (Ironbark, BoP, etc.)
    -- Rank by cast time closest to aura appear.
    -- Only promote a closer candidate if margin >= CASTTIME_CONFIDENT_DIFFERENCE.
    local bestExtRule     = nil
    local bestExtUnit     = nil
    local bestExtDiff     = nil

    local function considerExt(candidateUnit)
        local r, ru = tryMatch(candidateUnit)
        if not r then return end
        -- Only external defensive rules may be attributed to a different caster.
        -- Self-cast rules (Barkskin, AMS, …) must never match via external attribution:
        -- that would trigger false positives when e.g. a DK uses AMS and the scan
        -- fails to self-match (missing evidence), then falls through to a Druid whose
        -- Barkskin class rule has no evidence requirement and the same aura types.
        if not r.ExternalDefensive then return end
        local castTime = tracked.CastSnapshot and tracked.CastSnapshot[candidateUnit]
        local diff = castTime and math.abs(tracked.StartTime - castTime) or nil
        if not bestExtRule then
            bestExtRule, bestExtUnit, bestExtDiff = r, ru, diff
        elseif diff and (not bestExtDiff or diff < bestExtDiff) then
            local margin = bestExtDiff and (bestExtDiff - diff) or math.huge
            if margin >= CASTTIME_CONFIDENT_DIFFERENCE then
                bestExtRule, bestExtUnit, bestExtDiff = r, ru, diff
            end
        end
    end

    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not UnitIsUnit(u, unit) then considerExt(u) end
    end
    if not UnitIsUnit("player", unit) then considerExt("player") end

    if bestExtRule then return bestExtRule, bestExtUnit end
    return nil, nil
end

------------------------------------------------------------
-- CommitCooldown: store the matched cooldown
------------------------------------------------------------
local function CommitCooldown(unit, tracked, rule, ruleUnit, measuredDur)
    local casterUnit = ruleUnit or unit
    local casterName = (UnitIsUnit(casterUnit, "player")) and BIT.myName or SafeUnitName(casterUnit)
    if not casterName then return end

    -- Compute talent-adjusted cooldown
    local cooldown = rule.Cooldown
    local knownTalents = GetKnownTalents(casterName)
    if BIT.debugMode and rule._cdMods then
        local talentCount = 0; for _ in pairs(knownTalents) do talentCount = talentCount + 1 end
        local modKeys = ""
        for k in pairs(rule._cdMods) do modKeys = modKeys .. k .. "=" .. tostring(knownTalents[k]) .. " " end
        print("|cff0091edBIT|r |cff88aaff[TALENT-CD]|r " .. tostring(casterName)
              .. " spell=" .. rule.SpellId .. " basCD=" .. cooldown
              .. " knownTalents=" .. talentCount .. " mods: " .. modKeys)
    end
    if rule._cdMods then
        for talentID, amount in pairs(rule._cdMods) do
            if knownTalents[talentID] then
                cooldown = math.max(1, cooldown + amount)
            end
        end
    end

    -- Remaining CD = total CD − buff duration
    local remaining = cooldown - measuredDur
    if remaining < 1 then remaining = cooldown end

    -- Skip if CD already running from addon sync message.
    -- Exception: charge-based spells may be used multiple times while a charge CD is running.
    local cdState   = BIT.syncCdState and BIT.syncCdState[casterName]
    local cdRunning = cdState and cdState[rule.SpellId]
                      and cdState[rule.SpellId] > GetTime()
    if cdRunning then
        local spellEntry = _syncSpellLookup[rule.SpellId]
        local maxCharges = (spellEntry and spellEntry.charges) or 1
        if spellEntry and spellEntry.talentCharges then
            for talentID, chargeCount in pairs(spellEntry.talentCharges) do
                if knownTalents[talentID] then maxCharges = chargeCount end
            end
        end
        if maxCharges <= 1 then return end
        -- Own player's charge tracking is handled authoritatively by Core.lua
        -- via C_Spell.GetSpellCharges; AURA-MATCH would double-count here.
        if casterName == BIT.myName then return end
    end

    if BIT.debugMode then
        print("|cff0091edBIT|r |cFFAAAAAA[AURA-MATCH]|r " .. tostring(casterName)
              .. " buff expired dur=" .. string.format("%.1f", measuredDur)
              .. "s → spellID=" .. tostring(rule.SpellId)
              .. " remainCD=" .. string.format("%.0f", remaining))
    end

    BIT.SyncCD:OnSpellUsed(casterName, rule.SpellId, remaining, cooldown)

    -- Clear buff-active glow: CommitCooldown fires when the buff ENDS,
    -- so the spell should NOT glow. OnSpellUsed above may have set _buffActiveEnd
    -- based on buffDur — override that since the buff has already expired.
    if _buffActiveEnd[casterName] then
        _buffActiveEnd[casterName][rule.SpellId] = 0
    end
end

local function GetSpellsForPlayer(name)
    local specID = GetSpecForPlayer(name)
    local isOwnPlayer  = (name == BIT.myName)
    local spells = specID and BIT.SYNC_SPELLS[specID]
    -- Party member without LibSpec talent data: skip spec spells so missing data is obvious.
    -- Racial spells (handled below) do NOT depend on spec/talent scan and are always shown.
    local hasTalentData = isOwnPlayer
    if not isOwnPlayer then
        local ue = BIT.SyncCD.users and BIT.SyncCD.users[name]
        if ue and ue.knownSpells then hasTalentData = true end
    end
    local knownTalents = GetKnownTalents(name)
    local out = {}
    if spells and hasTalentData then
    for _, s in ipairs(spells) do
        if s.replacedBy then
            if not IsCatEnabled(s.cat) then
                -- skip entire entry (base + replacement) when category is hidden
            elseif isOwnPlayer then
                -- own player: check spellbook to see which version is active
                local ok, known = pcall(C_SpellBook.IsSpellKnown, s.replacedBy.id)
                if not (ok and known) then
                    local ok2, k2 = pcall(IsPlayerSpell, s.replacedBy.id)
                    if ok2 and k2 then known = true end
                end
                if not known and knownTalents and knownTalents[s.replacedBy.id] then
                    known = true
                end
                if not known then
                    local ok3, info3 = pcall(C_Spell.GetSpellCooldown, s.replacedBy.id)
                    if ok3 and info3 then known = true end
                end
                if known then
                    if IsSpellEnabled(s.replacedBy.id) then
                        out[#out+1] = ApplyTalentEffects(s.replacedBy, knownTalents)
                    end
                else
                    if IsSpellEnabled(s.id) then
                        out[#out+1] = ApplyTalentEffects(s, knownTalents)
                    end
                end
            else
                -- party member: combine cast-history and knownSpells from inspect
                local userEntry = BIT.SyncCD.users and BIT.SyncCD.users[name]
                local ks        = userEntry and userEntry.knownSpells
                local knownRepl = userEntry and userEntry.knownReplacements and userEntry.knownReplacements[s.id]
                -- Replacement shown if: seen casting it, or talent scan confirms it
                local hasRepl = knownRepl or (ks and ks[s.replacedBy.id])
                if hasRepl and IsSpellEnabled(s.replacedBy.id) and IsCatEnabled(s.replacedBy.cat or s.cat) then
                    out[#out+1] = ApplyTalentEffects(s.replacedBy, knownTalents)
                elseif IsSpellEnabled(s.id) then
                    -- Show if: no talent data, or confirmed active, or baseline (not a talent)
                    if not ks or ks[s.id] or not s.talent then
                        out[#out+1] = ApplyTalentEffects(s, knownTalents)
                    end
                end
            end
        elseif IsSpellEnabled(s.id) and IsCatEnabled(s.cat) then
            -- Own player: verify the spell is actually learned/talented
            -- Party member: filter by inspect talent scan when available
            if isOwnPlayer then
                local ok, known = pcall(C_SpellBook.IsSpellKnown, s.id)
                -- Fallback 1: IsPlayerSpell
                if not (ok and known) then
                    local ok2, k2 = pcall(IsPlayerSpell, s.id)
                    if ok2 and k2 then known = true end
                end
                -- Fallback 2: talent scan
                if not known and knownTalents and knownTalents[s.id] then
                    known = true
                end
                -- Fallback 3: C_Spell.GetSpellCooldown returns data → spell is known
                if not known then
                    local ok3, info3 = pcall(C_Spell.GetSpellCooldown, s.id)
                    if ok3 and info3 then known = true end
                end
                if known then
                    out[#out+1] = ApplyTalentEffects(s, knownTalents)
                end
            else
                -- Party member: filter by inspect talent scan when available
                local userEntry = BIT.SyncCD.users and BIT.SyncCD.users[name]
                local ks  = userEntry and userEntry.knownSpells
                if not ks or ks[s.id] or not s.talent then
                    out[#out+1] = ApplyTalentEffects(s, knownTalents)
                end
            end
        end
    end
    end
    -- Append racial spells (e.g. Shadowmeld for Night Elf)
    local raceFile
    if isOwnPlayer then
        local okR, _, rf = pcall(UnitRace, "player")
        if okR then raceFile = rf end
    else
        local ue = BIT.SyncCD.users and BIT.SyncCD.users[name]
        raceFile = ue and ue.race
        if not raceFile then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) and SafeUnitName(u) == name then
                    local okR, _, rf = pcall(UnitRace, u)
                    if okR then raceFile = rf end
                    break
                end
            end
        end
    end
    local racialSpells = raceFile and BIT.SyncCD.byRace and BIT.SyncCD.byRace[raceFile]
    if racialSpells then
        for _, s in ipairs(racialSpells) do
            if IsSpellEnabled(s.id) and IsCatEnabled(s.cat) then
                out[#out+1] = s
            end
        end
    end

    return out
end

local function GetCdForSpell(name, sid)
    local specID       = GetSpecForPlayer(name)
    local spells       = specID and BIT.SYNC_SPELLS[specID]
    local knownTalents = GetKnownTalents(name)
    if spells then
        for _, s in ipairs(spells) do
            if s.id == sid then
                return ApplyTalentEffects(s, knownTalents).cd
            end
        end
    end
    return 30
end

------------------------------------------------------------
-- Frame detection (ElvUI, DandersFrames, or Blizzard)
------------------------------------------------------------
local function IsElvUIActive()
    return _G["ElvUI"] ~= nil or _G["ElvUF_PartyGroup1"] ~= nil
end

local function IsDandersActive()
    return _G["DandersPartyHeader"] ~= nil
end

local function IsGrid2Active()
    return _G["Grid2LayoutFrame"] ~= nil
end

local function IsCellActive()
    return _G["Cell"] ~= nil
end

-- Generic scan: iterate numbered unit buttons from an addon, match by .unit property
local function ScanUnitButtons(prefix, unit, maxSlots)
    for i = 1, maxSlots do
        local btn = _G[prefix .. i]
        if btn and btn.unit and UnitIsUnit(btn.unit, unit) then return btn end
    end
end

-- Grid2 can have multiple layout headers (Header1, Header2 … for raids)
local function ScanGrid2(unit)
    for h = 1, 8 do
        local f = ScanUnitButtons("Grid2LayoutHeader" .. h .. "UnitButton", unit, 40)
        if f then return f end
    end
end

-- Individual provider lookup functions
local function visible(f) return f and f:IsVisible() end

local function FindElvUI(unit)
    if not IsElvUIActive() then return nil end
    local group = _G["ElvUF_PartyGroup1"]
    if group then
        for i = 1, group:GetNumChildren() do
            local child = select(i, group:GetChildren())
            if visible(child) and child.unit and UnitIsUnit(child.unit, unit) then
                return child
            end
        end
    end
    if unit == "player" then
        local pf = _G["ElvUF_Player"]
        if visible(pf) then return pf end
    end
    local f = ScanUnitButtons("ElvUF_PartyGroup1UnitButton", unit, 5)
    if visible(f) then return f end
end

local function FindDanders(unit)
    if not IsDandersActive() then return nil end
    local f = ScanUnitButtons("DandersPartyHeaderUnitButton", unit, 5)
    if visible(f) then return f end
    if unit == "player" then
        local playerBtn = _G["DandersPartyHeaderUnitButton0"] or _G["DandersPlayerFrame"]
        if visible(playerBtn) then return playerBtn end
    end
end

local function FindGrid2(unit)
    if not IsGrid2Active() then return nil end
    local f = ScanGrid2(unit)
    if visible(f) then return f end
end

-- Cell unit frame detection
local function FindCell(unit)
    if not IsCellActive() then return nil end
    -- Party frames (CellPartyFrameHeader must be visible)
    local header = _G["CellPartyFrameHeader"]
    if header and header:IsVisible() then
        local f = ScanUnitButtons("CellPartyFrameHeaderUnitButton", unit, 5)
        if visible(f) then return f end
    end
    -- Solo/player frame (CellSoloFrame)
    if unit == "player" then
        local solo = _G["CellSoloFramePlayer"]
        if visible(solo) then return solo end
    end
end

local function FindBlizzard(unit)
    local pf = _G["PartyFrame"]
    if pf then
        for i = 1, 4 do
            local f = pf["MemberFrame" .. i]
            if visible(f) and f.unit and UnitIsUnit(f.unit, unit) then return f end
        end
    end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if visible(f) and f.unit and UnitIsUnit(f.unit, unit) then return f end
    end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if visible(f) and f.unit and UnitIsUnit(f.unit, unit) then return f end
    end
    if unit == "player" then
        local bf = _G["PlayerFrame"]
        if visible(bf) then return bf end
    end
end

-- Ordered AUTO detection: tries each active provider in priority order
local function FindAuto(unit)
    return FindElvUI(unit) or FindDanders(unit) or FindCell(unit) or FindGrid2(unit) or FindBlizzard(unit)
end

-- Provider key → finder function
local PROVIDER_FINDERS = {
    ELVUI    = function(unit) return FindElvUI(unit)    or FindBlizzard(unit) end,
    DANDERS  = function(unit) return FindDanders(unit)  or FindBlizzard(unit) end,
    CELL     = function(unit) return FindCell(unit)     or FindBlizzard(unit) end,
    GRID2    = function(unit) return FindGrid2(unit)    or FindBlizzard(unit) end,
    BLIZZARD = FindBlizzard,
    AUTO     = FindAuto,
}

local function GetPartyUnitFrame(unit)
    local provider = BIT.db and BIT.db.syncCdFrameProvider or "AUTO"
    local finder   = PROVIDER_FINDERS[provider] or FindAuto
    return finder(unit)
end

------------------------------------------------------------
-- Detect available frame addons (for settings UI + first-run popup)
------------------------------------------------------------
function BIT.SyncCD:GetAvailableProviders()
    local list = { { value = "AUTO", label = "Auto Detect" } }
    if IsElvUIActive()   then list[#list + 1] = { value = "ELVUI",    label = "ElvUI" }        end
    if IsDandersActive() then list[#list + 1] = { value = "DANDERS",  label = "D4 / Danders" } end
    if IsCellActive()    then list[#list + 1] = { value = "CELL",     label = "Cell" }         end
    if IsGrid2Active()   then list[#list + 1] = { value = "GRID2",    label = "Grid2" }        end
    list[#list + 1] = { value = "BLIZZARD", label = "Blizzard" }
    return list
end

-- Returns number of conflicting frame addons detected (>1 = ambiguous)
function BIT.SyncCD:CountFrameAddons()
    local n = 0
    if IsElvUIActive()   then n = n + 1 end
    if IsDandersActive() then n = n + 1 end
    if IsCellActive()    then n = n + 1 end
    if IsGrid2Active()   then n = n + 1 end
    return n
end

-- First-run popup: shown once when multiple frame addons are detected
-- and the user hasn't explicitly chosen a provider yet.
function BIT.SyncCD:ShowFrameProviderPopup()
    if _G["BITFrameProviderPopup"] then return end  -- already showing

    local providers = self:GetAvailableProviders()
    -- Build list of addon names for the message (skip AUTO and BLIZZARD)
    local addonNames = {}
    for _, p in ipairs(providers) do
        if p.value ~= "AUTO" and p.value ~= "BLIZZARD" then
            addonNames[#addonNames + 1] = p.label
        end
    end

    local f = CreateFrame("Frame", "BITFrameProviderPopup", UIParent, "BackdropTemplate")
    f:SetSize(380, 50 + #providers * 32 + 10)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetBackdrop({
        bgFile   = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0.57, 0.93, 1)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff0091edBliZzi|r|cffffa300Interrupts|r")

    local msg = f:CreateFontString(nil, "OVERLAY")
    msg:SetFont(STANDARD_TEXT_FONT, 11, "")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -6)
    msg:SetWidth(350)
    msg:SetJustifyH("CENTER")
    msg:SetText(table.concat(addonNames, " & ") .. " detected.\nWhere should Party CDs be attached?")

    local yOff = -50
    for _, p in ipairs(providers) do
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(300, 26)
        btn:SetPoint("TOP", f, "TOP", 0, yOff)
        btn:SetBackdrop({
            bgFile   = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        lbl:SetPoint("CENTER")
        lbl:SetText(p.label)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0, 0.4, 0.7, 0.9)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
        end)
        btn:SetScript("OnClick", function()
            BIT.db.syncCdFrameProvider = p.value
            BIT.db._frameProviderAsked = true
            f:Hide()
            f:SetParent(nil)
            _G["BITFrameProviderPopup"] = nil
            if BIT.SyncCD and BIT.SyncCD.Rebuild then BIT.SyncCD:Rebuild() end
            print("|cff0091edBliZzi|r|cffffa300Interrupts|r Party CDs: " .. p.label)
        end)
        yOff = yOff - 32
    end

    f:Show()
end

-- Check on first login whether the popup should be shown
function BIT.SyncCD:CheckFrameProviderFirstRun()
    if not BIT.db then return end
    if BIT.db._frameProviderAsked then return end
    if BIT.db.syncCdFrameProvider and BIT.db.syncCdFrameProvider ~= "AUTO" then
        BIT.db._frameProviderAsked = true
        return
    end
    -- Only show if 2+ frame addons are active (ambiguous)
    if self:CountFrameAddons() < 2 then return end
    self:ShowFrameProviderPopup()
end

local SPELL_ICON_OVERRIDE = BIT.SyncCD.SPELL_ICON_OVERRIDE
local CD_REDUCER_SPELLS   = BIT.SyncCD.CD_REDUCER_SPELLS

------------------------------------------------------------
-- Icon creation
------------------------------------------------------------
local function CreateIcon(parent, spellID)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(ICON_SIZE(), ICON_SIZE())

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconSrc = SPELL_ICON_OVERRIDE[spellID] or spellID
    local icon = C_Spell.GetSpellTexture(iconSrc)
    if icon then f.tex:SetTexture(icon) end

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetDrawEdge(true)
    f.cd:SetReverse(false)
    f.cd:SetHideCountdownNumbers(true)  -- suppress built-in numbers; we draw our own

    -- text holder frame above the cooldown swipe layer.
    -- Use a large offset so the swipe animation never covers cdText/chargeBadge,
    -- even if CooldownFrameTemplate bumps its own frame level during combat.
    local textHolder = CreateFrame("Frame", nil, f)
    textHolder:SetAllPoints()
    textHolder:SetFrameLevel(f:GetFrameLevel() + 20)

    f.cdText = textHolder:CreateFontString(nil, "OVERLAY")
    local cSize = (BIT.db and BIT.db.syncCdCounterSize and BIT.db.syncCdCounterSize > 0)
                  and BIT.db.syncCdCounterSize or 14
    BIT.Media:SetFont(f.cdText, cSize)
    f.cdText:SetPoint("CENTER")
    f.cdText:Hide()

    -- Charge count badge (configurable position, only shown for multi-charge spells)
    f.chargeBadge = textHolder:CreateFontString(nil, "OVERLAY")
    local chSize   = (BIT.db and BIT.db.syncCdChargeSize) or 13
    BIT.Media:SetFont(f.chargeBadge, chSize)
    f.chargeBadge:SetTextColor(1, 1, 1, 1)  -- white
    local chAnchor = (BIT.db and BIT.db.syncCdChargeAnchor) or "BOTTOMRIGHT"
    local chOffX   = (BIT.db and BIT.db.syncCdChargeOffX) or -1
    local chOffY   = (BIT.db and BIT.db.syncCdChargeOffY) or 1
    f.chargeBadge:SetPoint(chAnchor, f, chAnchor, chOffX, chOffY)
    f.chargeBadge:Hide()
    f._maxCharges = 0

    local border = f:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT",     f, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    f.border = border

    f:EnableMouse(true)
    f:SetScript("OnEnter", function()
        if not BIT.db.syncCdTooltip then return end
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(f.spellID)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" or true then return end -- Under Construction
        local okNow, sNow = pcall(string.format, "%.3f", GetTime())
        local now = okNow and tonumber(sNow) or 0
        if BIT.db.antiSpam and f.announceLockedUntil then
            local okL, sL = pcall(string.format, "%.3f", f.announceLockedUntil)
            local lockUntil = okL and tonumber(sL) or 0
            if now < lockUntil then return end
        end
        local playerName = f._playerName or "?"
        local spellName  = f._spellName  or "?"
        local cdState = BIT.syncCdState and BIT.syncCdState[f._playerName]
        local cdEnd   = cdState and cdState[f.spellID]
        local cdEndClean = 0
        if cdEnd then
            local okC, sC = pcall(string.format, "%.3f", cdEnd)
            cdEndClean = okC and tonumber(sC) or 0
        end
        local rem = math.max(0, cdEndClean - now)
        local msg
        if rem > 0.5 then
            msg = string.format(BIT.L["MSG_ANNOUNCE_CD"], playerName, spellName, rem)
        else
            msg = string.format(BIT.L["MSG_ANNOUNCE_READY"], playerName, spellName)
        end
        if issecretvalue(msg) then return end
        if IsInGroup() then
            C_ChatInfo.SendChatMessage(msg, "INSTANCE_CHAT")
        else
            print("|cff0091edBliZzi|r|cffffa300Interrupts|r " .. msg)
        end
        if BIT.db.antiSpam then
            f.announceLockedUntil = now + (rem > 0.5 and rem or 5)
        end
    end)

    f.spellID = spellID
    return f
end

local function FormatCdTime(sec)
    if BIT.db and BIT.db.syncCdTimeFormat == "MMSS" and sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    end
    return tostring(sec)
end

------------------------------------------------------------
-- Shared state tables (declared here so buff system and both modes can access them)
------------------------------------------------------------
local syncRows     = {}  -- name → { frame, nameText, icons={spellID→ico} }
local attachedBars = {}  -- unit → { frame, icons={spellID→ico} }
BIT.SyncCD._attachedBars = attachedBars  -- expose for debug commands

-- CC Window removed — CC tracking is no longer supported

------------------------------------------------------------
-- Buff-based glow system (LibButtonGlow overlay while buff is active)
-- Spells that also apply a visible buff: spellID → buffAuraID
------------------------------------------------------------
local SPELL_BUFF_MAP = BIT.SyncCD.SPELL_BUFF_MAP
local LibButtonGlow = LibStub("LibButtonGlowcustom", true)

local activeBuffs       = {}  -- name → { [buffID] = true }
-- (old _partyCdAuraState removed — replaced by _trackedPartyAuras)

local function RefreshBuffHighlights(name)
    -- For SPELL_BUFF_MAP spells (Alter Time, Meta): sync activeBuffs into _buffActiveEnd
    -- so the glow is controlled centrally by UpdateIcon via _buffActiveEnd.
    local buffs = activeBuffs[name]
    if not _buffActiveEnd[name] then _buffActiveEnd[name] = {} end
    local buffEnds = _buffActiveEnd[name]
    for spellID, buffID in pairs(SPELL_BUFF_MAP) do
        if buffs and buffs[buffID] then
            -- Buff is active — set a far-future end time (will be cleared when buff drops)
            if not buffEnds[spellID] or buffEnds[spellID] <= GetTime() then
                buffEnds[spellID] = GetTime() + 600  -- sentinel; cleared on next UNIT_AURA
            end
        else
            -- Buff dropped — clear immediately so UpdateIcon stops the glow
            if buffEnds[spellID] and buffEnds[spellID] > GetTime() then
                buffEnds[spellID] = 0
            end
        end
    end
end

do
    local buffAuraFrame = CreateFrame("Frame")
    buffAuraFrame:RegisterEvent("UNIT_AURA")
    buffAuraFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
        if not unit then return end
        local isPlayer = (unit == "player")
        if not isPlayer and not unit:find("^party%d$") then return end

        local name = isPlayer and BIT.myName or SafeUnitName(unit)
        if not name then return end

        -- ── Record evidence FIRST (before detection) ──
        -- Process aura changes at the top of this handler before detection runs.
        -- Note: aura.isHarmful is a "secret boolean" in Midnight — direct boolean
        -- test causes taint. Use IsAuraFilteredOutByInstanceID instead.
        if not isPlayer and updateInfo then
            local now = GetTime()
            -- Debuff added evidence
            if updateInfo.addedAuras then
                for _, aura in ipairs(updateInfo.addedAuras) do
                    if aura.auraInstanceID then
                        local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
                                                   unit, aura.auraInstanceID, "HARMFUL")
                        if ok and filtered == false then
                            _lastDebuffTime[unit] = now
                            break
                        end
                    end
                end
                -- Buff added evidence (concurrent helpful aura)
                for _, aura in ipairs(updateInfo.addedAuras) do
                    if aura.auraInstanceID then
                        local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
                                                   unit, aura.auraInstanceID, "HELPFUL")
                        if ok and filtered == false then
                            _lastBuffTime[unit] = now
                            break
                        end
                    end
                end
            end
            -- Debuff removed evidence (for Stoneform etc.)
            if updateInfo.removedAuraInstanceIDs then
                -- We can't check the filter type of removed auras (they're gone),
                -- so we record any removal. The evidence tolerance window and
                -- rule matching (requireDebuffRemoved) will filter false positives.
                _lastDebuffRemovedTime[unit] = now
            end
        end

        local changed = false
        if not activeBuffs[name] then activeBuffs[name] = {} end

        for spellID, buffID in pairs(SPELL_BUFF_MAP) do
            -- Shadowmeld (58984): aura is hidden on partyN (stealth). State is managed
            -- manually by the UNIT_FLAGS combat-drop trigger + auto-expire timer, so
            -- skip it here — otherwise this loop would immediately clear the buff we
            -- just set (now=false every poll because the API can't see the aura).
            if buffID == 58984 and not isPlayer then
                -- intentionally skip — manual management
            else
            local wasActive = activeBuffs[name][buffID]
            local origOk, origRet = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, buffID, "HELPFUL")
            local ok, auraData = origOk, origRet
            -- Fallback 1: GetAuraDataBySpellID sometimes throws in 12.x when its internal
            -- lookup hits tainted data (secret bool). Try without the filter arg too.
            if not ok then
                local ok2, ad2 = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, buffID)
                if ok2 then ok, auraData = true, ad2 end
            end
            -- Fallback 2: If GetAuraDataBySpellID still fails, enumerate via GetUnitAuras
            -- and match by spellId. GetUnitAuras works reliably in 12.x (used by scan path).
            if not ok then
                local okU, auras = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL")
                if okU and auras then
                    for _, ad in ipairs(auras) do
                        if ad and ad.spellId then
                            local okS, s = pcall(string.format, "%.0f", ad.spellId)
                            local sid = okS and tonumber(s)
                            if sid == buffID then
                                ok, auraData = true, ad
                                break
                            end
                        end
                    end
                    if not ok then ok = true end  -- no match, but scan succeeded
                end
            end
            local nowActive = ok and auraData ~= nil and type(auraData) == "table"
            if BIT.devLogMode and (buffID == 110909 or buffID == 58984) and (nowActive or wasActive ~= nil) then
                BIT.DevLog("[SyncCD-AURA] unit=" .. tostring(unit)
                      .. " name=" .. tostring(name)
                      .. " buffID=" .. tostring(buffID) .. " now=" .. tostring(nowActive)
                      .. " was=" .. tostring(wasActive ~= nil))
            end
            -- Extra diagnostic for Shadowmeld: log every poll on non-player units
            -- so we can see whether UNIT_AURA fires at all when the buff is applied.
            if BIT.devLogMode and buffID == 58984 and not isPlayer then
                local errStr = (not origOk) and tostring(origRet or "?"):sub(1, 80) or nil
                BIT.DevLog("[SM-POLL] unit=" .. tostring(unit)
                      .. " name=" .. tostring(name)
                      .. " ok=" .. tostring(ok)
                      .. " now=" .. tostring(nowActive)
                      .. (errStr and (" err=" .. errStr) or ""))
            end

            if nowActive ~= wasActive then
                activeBuffs[name][buffID] = nowActive or nil
                changed = true

                -- Last Resort detection: Meta buff appeared but no tracked CD running
                -- (manual cast would have set syncCdState via AnnounceSync/OnSpellUsed)
                if nowActive and buffID == 187827 then
                    local delay = isPlayer and 0 or 0.5
                    C_Timer.After(delay, function()
                        if not (activeBuffs[name] and activeBuffs[name][187827]) then return end
                        local cdState = BIT.syncCdState and BIT.syncCdState[name]
                        local cdEnd   = cdState and cdState[187827]
                        if not cdEnd or cdEnd <= GetTime() then
                            -- Last Resort triggered Meta — start CD tracking + announce for own player
                            BIT.SyncCD:OnSpellUsed(name, 187827, 120)
                            if isPlayer and BIT.Net then BIT.Net:AnnounceSync(187827, 120) end
                        end
                    end)
                elseif nowActive and spellID == 342245 then
                    -- Alter Time: buff 110909 appeared — UNIT_SPELLCAST_SUCCEEDED can miss this
                    -- (spell is still castable while buff is active, so GetSpellCooldown returns 0)
                    local delay = isPlayer and 0 or 0.5
                    C_Timer.After(delay, function()
                        if not (activeBuffs[name] and activeBuffs[name][110909]) then return end
                        local cdState = BIT.syncCdState and BIT.syncCdState[name]
                        local cdEnd   = cdState and cdState[342245]
                        if not cdEnd or cdEnd <= GetTime() then
                            BIT.SyncCD:OnSpellUsed(name, 342245, 50)
                            if isPlayer and BIT.Net then BIT.Net:AnnounceSync(342245, 50) end
                        end
                    end)
                elseif nowActive and spellID == 58984 then
                    -- Shadowmeld: racial stealth buff 58984 appeared. Cast detection via
                    -- UNIT_SPELLCAST_SUCCEEDED is unreliable for racials on party members
                    -- (tainted spellID + instant cast). Aura-based trigger is robust.
                    local delay = isPlayer and 0 or 0.5
                    C_Timer.After(delay, function()
                        if not (activeBuffs[name] and activeBuffs[name][58984]) then return end
                        local cdState = BIT.syncCdState and BIT.syncCdState[name]
                        local cdEnd   = cdState and cdState[58984]
                        if not cdEnd or cdEnd <= GetTime() then
                            BIT.SyncCD:OnSpellUsed(name, 58984, 120)
                            if isPlayer and BIT.Net then BIT.Net:AnnounceSync(58984, 120) end
                        end
                    end)
                end
            end
            end -- closes: if buffID == 58984 and not isPlayer then ... else
        end

        -- Also check buff 342245 (Alter Time spell aura, fallback if 110909 not present)
        do
            local altID  = 342245
            local wasAlt = activeBuffs[name][altID]
            local okA, adA = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, altID, "HELPFUL")
            local nowAlt   = okA and adA ~= nil
            if BIT.devLogMode and (nowAlt or wasAlt ~= nil) then
                BIT.DevLog("[SyncCD-AURA] unit=" .. tostring(unit)
                      .. " buffID=342245(alt) now=" .. tostring(nowAlt)
                      .. " was=" .. tostring(wasAlt ~= nil))
            end
            if nowAlt ~= wasAlt then
                activeBuffs[name][altID] = nowAlt or nil
                changed = true
                if nowAlt then
                    local delay = isPlayer and 0 or 0.5
                    C_Timer.After(delay, function()
                        if not (activeBuffs[name] and activeBuffs[name][altID]) then return end
                        local cdState = BIT.syncCdState and BIT.syncCdState[name]
                        local cdEnd   = cdState and cdState[342245]
                        if not cdEnd or cdEnd <= GetTime() then
                            BIT.DevLog("[SyncCD-AURA] Alter Time via alt buff -> OnSpellUsed")
                            BIT.SyncCD:OnSpellUsed(name, 342245, 50)
                            if isPlayer and BIT.Net then BIT.Net:AnnounceSync(342245, 50) end
                        end
                    end)
                end
            end
        end

        -- ── Feign Death (5384) own-player aura lifecycle ────────────────
        -- FD is not in SPELL_BUFF_MAP (its cast spellID and buff spellID are
        -- identical, but it needs special cast-time logic in OnPartySpellCast
        -- that bypasses the normal CD start). However, relying only on
        -- UNIT_FLAGS to detect the buff END is fragile:
        --   • Early cancel (damage taken during the 0.5s cast-to-FD latency)
        --     can drop the buff BEFORE UnitIsFeignDeath ever flips true,
        --     so wasFD stays false and the FD-end branch never fires.
        --   • Manual /cancelaura drops the buff without changing UnitIsFeignDeath.
        --   • Tainted C_UnitAuras.GetAuraDataBySpellID pcalls in the UpdateIcon
        --     self-cancel check silently fail, leaving the glow stuck.
        -- UNIT_AURA on "player" is non-tainted and fires reliably on buff
        -- application / removal — use it as the primary lifecycle signal.
        if isPlayer then
            local okFD, fdAura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", 5384, "HELPFUL")
            local isFdActive = okFD and fdAura ~= nil
            if _fdAuraActive and not isFdActive then
                -- Guard: only fire if we still think FD is active (prevents
                -- double-fire with UNIT_FLAGS path).
                local bEnd = _buffActiveEnd[name] and _buffActiveEnd[name][5384]
                if bEnd and bEnd > GetTime() then
                    BIT.SyncCD:OnSpellUsed(name, 5384, 30, 30)
                    _buffActiveEnd[name][5384] = 0
                    RefreshBuffHighlights(name)
                    if BIT.devLogMode then
                        BIT.DevLog("[FD] aura removed -> glow off, CD started")
                    end
                end
            end
            _fdAuraActive = isFdActive
        end

        -- ── Aura detection (Full-Scan approach) ──
        -- On every relevant UNIT_AURA, do a full scan via C_UnitAuras.GetUnitAuras()
        -- and diff against tracked state. This is more robust than processing only
        -- addedAuras/removedAuraInstanceIDs.
        -- Run for BOTH "player" AND party members:
        --   • BIG_DEFENSIVE on "player"  = own casts; CommitCooldown skips them if CD already
        --     running via UNIT_SPELLCAST_SUCCEEDED (see guard in CommitCooldown, line ~641).
        --   • EXTERNAL_DEFENSIVE on "player" = externals cast BY party members ON the local
        --     player (e.g. Ironbark, BoP). Previously skipped → glow/CD never fired.
        do
            -- Always do the full scan for all tracked units.
            -- The quick-interest-check that was here before filtered via
            -- IsAuraFilteredOutByInstanceID on addedAuras/updatedAuras, but
            -- in WoW 11.x/12.x the auraInstanceIDs in updateInfo can be
            -- tainted (secret), causing pcall failures that silently skip
            -- defensive auras (e.g. Survival of the Fittest).
            -- Full scan cost is negligible since it only runs for 1-4 party members.
            local dominated = false

            if not dominated then
                local now = GetTime()
                if not _trackedPartyAuras[unit] then _trackedPartyAuras[unit] = {} end
                local tracked = _trackedPartyAuras[unit]

                -- ── FULL SCAN: rebuild complete aura state ──
                -- Scan defensives first, then for each aura check EXTERNAL_DEFENSIVE
                -- priority. An aura gets EITHER EXTERNAL_DEFENSIVE or BIG_DEFENSIVE
                -- (not both). IMPORTANT can co-exist with either.
                local currentIds = {}

                -- 1) Collect all defensive auras (BIG + EXTERNAL combined)
                -- Also track spellId per aura instance for unambiguous rule matching.
                local defensiveAids    = {}
                local aidToSpellId     = {}  -- auraInstanceID → spellId (from Blizzard aura data)
                -- Remap table: some spells apply a buff with a different spell ID than the cast.
                -- e.g. Blur cast=198589 applies buff=212800. Without remapping the SpellId gate
                -- in MatchRule would reject the rule (212800 ≠ 198589).
                local buffIdRemap  = BIT.SyncCD.buffIdToSpellId or {}
                -- RaidInCombat flag per aura: true when the aura matches HELPFUL|RAID_IN_COMBAT.
                -- Boss-applied M+ buffs are typically RAIDINCOMBAT; player defensives (Barkskin,
                -- Ironbark …) are not. Used in checkList to prevent false positives.
                local aidToIsRIC = {}
                local ok1, bigAuras = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL|BIG_DEFENSIVE")
                if ok1 and bigAuras then
                    for _, ad in ipairs(bigAuras) do
                        if ad and ad.auraInstanceID then
                            defensiveAids[ad.auraInstanceID] = true
                            if ad.spellId then
                                local okS, ss = pcall(string.format, "%.0f", ad.spellId)
                                local sid = okS and tonumber(ss)
                                if sid then aidToSpellId[ad.auraInstanceID] = buffIdRemap[sid] or sid end
                            end
                            -- RAIDINCOMBAT flag: boss-applied M+ buffs have RIC=true; player
                            -- defensives (Barkskin, Ironbark …) have RIC=false.  Not tainted.
                            if not aidToIsRIC[ad.auraInstanceID] then
                                local okR, ric = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
                                                       unit, ad.auraInstanceID, "HELPFUL|RAID_IN_COMBAT")
                                if okR then aidToIsRIC[ad.auraInstanceID] = (ric == false) end
                            end
                            if BIT.devLogMode then
                                local rawId = ad.spellId or "?"
                                local mapped = aidToSpellId[ad.auraInstanceID] or "?"
                                BIT.DevLog("[SCAN-BIG] " .. tostring(name) .. " aid=" .. ad.auraInstanceID
                                    .. " rawId=" .. rawId .. " mapped=" .. mapped
                                    .. " ric=" .. tostring(aidToIsRIC[ad.auraInstanceID]))
                            end
                        end
                    end
                end
                local ok2, extAuras = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL|EXTERNAL_DEFENSIVE")
                if ok2 and extAuras then
                    for _, ad in ipairs(extAuras) do
                        if ad and ad.auraInstanceID then
                            defensiveAids[ad.auraInstanceID] = true
                            if ad.spellId and not aidToSpellId[ad.auraInstanceID] then
                                local okS, ss = pcall(string.format, "%.0f", ad.spellId)
                                local sid = okS and tonumber(ss)
                                if sid then aidToSpellId[ad.auraInstanceID] = buffIdRemap[sid] or sid end
                            end
                            if not aidToIsRIC[ad.auraInstanceID] then
                                local okR, ric = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
                                                       unit, ad.auraInstanceID, "HELPFUL|RAID_IN_COMBAT")
                                if okR then aidToIsRIC[ad.auraInstanceID] = (ric == false) end
                            end
                            if BIT.devLogMode then
                                local rawId = ad.spellId or "?"
                                local mapped = aidToSpellId[ad.auraInstanceID] or "?"
                                BIT.DevLog("[SCAN-EXT] " .. tostring(name) .. " aid=" .. ad.auraInstanceID
                                    .. " rawId=" .. rawId .. " mapped=" .. mapped
                                    .. " ric=" .. tostring(aidToIsRIC[ad.auraInstanceID]))
                            end
                        end
                    end
                end

                -- 2) Classify each defensive: EXTERNAL_DEFENSIVE wins over BIG_DEFENSIVE.
                for aid in pairs(defensiveAids) do
                    local isExt = false
                    local okF, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, aid, "HELPFUL|EXTERNAL_DEFENSIVE")
                    if okF and filtered == false then
                        isExt = true
                    end
                    local auraType = isExt and "EXTERNAL_DEFENSIVE" or "BIG_DEFENSIVE"
                    currentIds[aid] = { [auraType] = true }
                end

                -- 2b) Fix / add external defensive spells missed or misclassified above.
                -- GetUnitAuras("HELPFUL|EXTERNAL_DEFENSIVE") may not return externals in
                -- WoW 12.x. Worse: self-cast externals (e.g. Resto Druid casts Ironbark
                -- on themselves) are tagged BIG_DEFENSIVE by WoW, so step 2 classifies
                -- them wrong. GetAuraDataBySpellID always finds the buff reliably and we
                -- know these spell IDs are external defensives by design → force EXTERNAL.
                local extDirectIds = BIT.SyncCD._externalDefensiveSpellIds
                if extDirectIds then
                    for _, sid in ipairs(extDirectIds) do
                        local okD, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, sid, "HELPFUL")
                        if okD and ad and ad.auraInstanceID then
                            local aid = ad.auraInstanceID
                            -- Use the known spell ID (avoids tainted ad.spellId)
                            aidToSpellId[aid] = buffIdRemap[sid] or sid
                            -- RIC flag
                            if not aidToIsRIC[aid] then
                                local okR, ric = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
                                                       unit, aid, "HELPFUL|RAID_IN_COMBAT")
                                if okR then aidToIsRIC[aid] = (ric == false) end
                            end
                            -- Force EXTERNAL_DEFENSIVE (step 2 may have set BIG for self-casts)
                            if not currentIds[aid] then
                                currentIds[aid] = { EXTERNAL_DEFENSIVE = true }
                                if BIT.devLogMode then
                                    BIT.DevLog("[SCAN-EXT-DIRECT] " .. tostring(name)
                                        .. " sid=" .. sid .. " aid=" .. aid
                                        .. " ric=" .. tostring(aidToIsRIC[aid]))
                                end
                            elseif not currentIds[aid].EXTERNAL_DEFENSIVE then
                                -- Was classified BIG_DEFENSIVE (self-cast) — correct it
                                currentIds[aid] = { EXTERNAL_DEFENSIVE = true }
                                if BIT.devLogMode then
                                    BIT.DevLog("[SCAN-EXT-RECLASSIFY] " .. tostring(name)
                                        .. " sid=" .. sid .. " aid=" .. aid
                                        .. " corrected BIG→EXTERNAL_DEFENSIVE")
                                end
                            end
                        end
                    end
                end

                -- 3) IMPORTANT can co-exist with either primary type.
                local ok3, impAuras = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL|IMPORTANT")
                if ok3 and impAuras then
                    for _, ad in ipairs(impAuras) do
                        if ad and ad.auraInstanceID then
                            if currentIds[ad.auraInstanceID] then
                                currentIds[ad.auraInstanceID]["IMPORTANT"] = true
                            else
                                currentIds[ad.auraInstanceID] = { IMPORTANT = true }
                            end
                            if ad.spellId and not aidToSpellId[ad.auraInstanceID] then
                                local okS, ss = pcall(string.format, "%.0f", ad.spellId)
                                local sid = okS and tonumber(ss)
                                if sid then aidToSpellId[ad.auraInstanceID] = buffIdRemap[sid] or sid end
                            end
                            if not aidToIsRIC[ad.auraInstanceID] then
                                local okR, ric = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
                                                       unit, ad.auraInstanceID, "HELPFUL|RAID_IN_COMBAT")
                                if okR then aidToIsRIC[ad.auraInstanceID] = (ric == false) end
                            end
                            if BIT.devLogMode then
                                local rawId = ad.spellId or "?"
                                local mapped = aidToSpellId[ad.auraInstanceID] or "?"
                                BIT.DevLog("[SCAN-IMP] " .. tostring(name) .. " aid=" .. ad.auraInstanceID
                                    .. " rawId=" .. rawId .. " mapped=" .. mapped
                                    .. " ric=" .. tostring(aidToIsRIC[ad.auraInstanceID]))
                            end
                        end
                    end
                end

                -- ── Reconciliation: diff currentIds against tracked ──
                if BIT.devLogMode then
                    local count = 0
                    for aid, at in pairs(currentIds) do
                        count = count + 1
                        BIT.DevLog("[SCAN-RESULT] " .. tostring(name) .. " aid=" .. aid
                            .. " types=" .. AuraTypesSignature(at)
                            .. " spellId=" .. tostring(aidToSpellId[aid] or "?"))
                    end
                    if count == 0 then
                        BIT.DevLog("[SCAN-RESULT] " .. tostring(name) .. " NO defensive auras found")
                    end
                end
                -- Collect unmatched new IDs grouped by AuraTypes signature
                local newIdsBySig = {}
                for aid, at in pairs(currentIds) do
                    if not tracked[aid] then
                        local sig = AuraTypesSignature(at)
                        if not newIdsBySig[sig] then newIdsBySig[sig] = {} end
                        newIdsBySig[sig][#newIdsBySig[sig] + 1] = aid
                    end
                end

                -- For each tracked ID that disappeared: try to carry forward or trigger CD
                local toRemove = {}
                for oldAid, info in pairs(tracked) do
                    if not currentIds[oldAid] then
                        local sig = AuraTypesSignature(info.AuraTypes)
                        local pool = newIdsBySig[sig]
                        if pool and #pool > 0 and (now - info.StartTime) <= 5 then
                            -- Short-lived: likely a WoW full-update ID reassignment; carry forward
                            local newAid = table.remove(pool)
                            tracked[newAid] = info
                        else
                            if pool and #pool > 0 then
                                -- Aura lasted >5s: genuine expiry (not just ID reassignment).
                                -- Remove the new ID from the pool so it gets tracked fresh below.
                                table.remove(pool)
                            end
                            -- Aura truly removed → measure duration and match
                            local measuredDur = now - info.StartTime
                            local rule, ruleUnit = FindBestCandidate(unit, info, measuredDur)
                            if rule then
                                CommitCooldown(unit, info, rule, ruleUnit, measuredDur)
                            end
                        end
                        toRemove[#toRemove + 1] = oldAid
                    end
                end
                for _, oldAid in ipairs(toRemove) do
                    tracked[oldAid] = nil
                end

                -- Track new auras
                for aid, at in pairs(currentIds) do
                    if not tracked[aid] then
                        local evidence = BuildEvidenceSet(unit, now)
                        tracked[aid] = {
                            StartTime    = now,
                            AuraTypes    = at,
                            -- SpellId: the actual buff spell (from Blizzard aura data).
                            -- Used in rule matching to disambiguate spells with identical
                            -- AuraTypes and duration (e.g. Survival of the Fittest vs
                            -- Aspect of the Turtle: both BI, both 8s with talents).
                            SpellId        = aidToSpellId[aid],
                            -- IsRaidInCombat: true when the aura matches HELPFUL|RAID_IN_COMBAT.
                            -- Boss-applied M+ buffs are typically RIC; player defensives are not.
                            -- Rules with RaidInCombatExclude=true are skipped when RIC=true.
                            IsRaidInCombat = aidToIsRIC[aid],
                            Evidence     = evidence,
                            CastSnapshot = SnapshotCastTimes(),
                        }
                        -- Deferred evidence backfill (events can arrive slightly after UNIT_AURA)
                        C_Timer.After(EVIDENCE_TOLERANCE, function()
                            local entry = tracked[aid]
                            if not entry then return end
                            local newEv = BuildEvidenceSet(unit, entry.StartTime)
                            if newEv then
                                if not entry.Evidence then entry.Evidence = {} end
                                for k, v in pairs(newEv) do entry.Evidence[k] = v end
                            end
                            for u, t in pairs(_lastCastTime) do
                                if not entry.CastSnapshot[u] and math.abs(entry.StartTime - t) <= CAST_WINDOW then
                                    entry.CastSnapshot[u] = t
                                end
                            end
                            -- Try to match the aura at appear time
                            -- (no duration check yet — we haven't measured it).
                            -- Sets _buffActiveEnd so UpdateIcon shows the glow while the buff is active.
                            -- CommitCooldown (at aura removal) clears it via line 594.
                            local glowRule, glowUnit = FindGlowOnAuraAppear(unit, entry)
                            if glowRule then
                                local casterUnit = glowUnit or unit
                                local casterName = UnitIsUnit(casterUnit, "player") and BIT.myName
                                                   or SafeUnitName(casterUnit)
                                if casterName then
                                    local expectedDur = glowRule.BuffDuration
                                    if glowRule._durationMods then
                                        -- At glow-appear time always use max duration (apply all mods).
                                        -- Passive talent IDs (e.g. Improved Barkskin 327993) are not
                                        -- in LibSpec knownSpells, so talent presence can't be checked
                                        -- reliably here. Using max is safe: CommitCooldown always sets
                                        -- _buffActiveEnd=0 at the real buff expiry, so the glow never
                                        -- outlasts the actual buff.
                                        for _, amt in pairs(glowRule._durationMods) do
                                            expectedDur = expectedDur + amt
                                        end
                                    end
                                    if not _buffActiveEnd[casterName] then _buffActiveEnd[casterName] = {} end
                                    -- Only set if not already tracked by a more authoritative source
                                    -- (e.g. SYNCCD addon message already set it correctly)
                                    local existing = _buffActiveEnd[casterName][glowRule.SpellId]
                                    if not existing or existing <= GetTime() then
                                        _buffActiveEnd[casterName][glowRule.SpellId] = entry.StartTime + expectedDur
                                        if BIT.debugMode then
                                            print("|cff0091edBIT|r |cff00ff88[GLOW-SET]|r "
                                                  .. casterName
                                                  .. " spell=" .. glowRule.SpellId
                                                  .. " auraTypes=" .. AuraTypesSignature(entry.AuraTypes)
                                                  .. " spellIdOnAura=" .. tostring(entry.SpellId)
                                                  .. " ric=" .. tostring(entry.IsRaidInCombat)
                                                  .. " dur=" .. expectedDur .. "s")
                                        end
                                    end
                                end
                            end
                        end)
                        if BIT.devLogMode then
                            local evStr = "none"
                            if evidence then
                                local parts = {}
                                if evidence.Cast       then parts[#parts+1] = "Cast"   end
                                if evidence.Buff       then parts[#parts+1] = "Buff"   end
                                if evidence.Debuff     then parts[#parts+1] = "Debuff" end
                                if evidence.Shield     then parts[#parts+1] = "Shield" end
                                if evidence.UnitFlags  then parts[#parts+1] = "Flags"  end
                                if evidence.CombatDrop then parts[#parts+1] = "Drop"   end
                                evStr = #parts > 0 and table.concat(parts, "+") or "none"
                            end
                            BIT.DevLog("[AURA-TRACK] " .. tostring(name)
                                  .. " aura added aid=" .. tostring(aid)
                                  .. " types=" .. AuraTypesSignature(at)
                                  .. " ev=" .. evStr)
                        end
                    end
                end
            end -- not dominated
        end

        if changed then RefreshBuffHighlights(name) end
    end)
end

-- ── Party evidence recording (5 signal types) ───────────────────────────
-- Registers per-unit events for UNIT_SPELLCAST_SUCCEEDED, UNIT_FLAGS,
-- UNIT_AURA (harmful debuffs) and global UNIT_ABSORB_AMOUNT_CHANGED.
do
    -- Evidence frame: UNIT_SPELLCAST_SUCCEEDED + UNIT_FLAGS per party unit
    -- (Debuff evidence is recorded in buffAuraFrame above to ensure correct ordering)
    local castFrame = CreateFrame("Frame")
    castFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            _lastCastTime[unit] = GetTime()
            if unit == "player" and spellID then
                -- Own player: spellID is untainted → direct lookup works.
                -- This catches spells whose buffs are not tagged as
                -- BIG_DEFENSIVE / IMPORTANT by Blizzard (e.g. Zephyr)
                -- and would otherwise be missed by the aura-scan path.
                if BIT.SyncCD.OnPartySpellCast and BIT.myName then
                    BIT.SyncCD:OnPartySpellCast(BIT.myName, spellID)
                end
            elseif unit ~= "player" and spellID then
                local name = SafeUnitName(unit)
                if name then
                    -- Party CD detection (SyncCD spells like defensives/offensives).
                    -- UNIT_SPELLCAST_SENT only fires for "player" in Midnight (12.x),
                    -- not for party members. This UNIT_SPELLCAST_SUCCEEDED path is the
                    -- primary cast-evidence source; spellID is tainted so pcall is used.
                    if BIT.devLogMode then
                        -- spellID is tainted — tostring via pcall for safe logging
                        local okS, s = pcall(tostring, spellID)
                        BIT.DevLog("[CAST-SUCCESS] unit=" .. tostring(unit)
                              .. " name=" .. tostring(name)
                              .. " spellID=" .. (okS and s or "<taint>"))
                    end
                    if BIT.SyncCD.OnPartySpellCast then
                        BIT.SyncCD:OnPartySpellCast(name, spellID)
                    end
                end
            end
        elseif event == "UNIT_FLAGS" then
            local now = GetTime()
            -- Feign Death detection
            local isFD = UnitIsFeignDeath(unit)
            local wasFD = _prevFeignDeath[unit]
            if isFD and not wasFD then
                _lastFeignDeathTime[unit] = now
            elseif not isFD then
                _lastUnitFlagsTime[unit] = now
            end
            -- Own player FD end: start the 30s CD now (FD defers CD start
            -- until the buff ends because it can be cancelled early), and
            -- clear the glow. Party members use AURA-MATCH / other evidence
            -- paths that already handle buff-end naturally.
            -- Guarded by _buffActiveEnd: if the UNIT_AURA path already
            -- detected the buff drop (which fires earlier and more
            -- reliably), _buffActiveEnd is already 0 and we skip to avoid
            -- re-starting the CD from a later timestamp.
            if unit == "player" and wasFD and not isFD then
                local myName = BIT.myName
                if myName then
                    local bEnd = _buffActiveEnd[myName] and _buffActiveEnd[myName][5384]
                    if bEnd and bEnd > now then
                        BIT.SyncCD:OnSpellUsed(myName, 5384, 30, 30)
                        -- OnSpellUsed re-arms _buffActiveEnd from buffDur;
                        -- clear it since the buff has actually ended.
                        _buffActiveEnd[myName][5384] = 0
                        RefreshBuffHighlights(myName)
                        if BIT.devLogMode then
                            BIT.DevLog("[FD] self buff ended (UNIT_FLAGS) -> glow off, CD started")
                        end
                    end
                end
            end
            _prevFeignDeath[unit] = isFD
            -- Combat drop detection (for Shadowmeld, Vanish, etc.)
            local inCombat = UnitAffectingCombat(unit)
            if _prevInCombat[unit] and not inCombat then
                _lastCombatDropTime[unit] = now
                if BIT.devLogMode and unit ~= "player" then
                    local okR, _, rf = pcall(UnitRace, unit)
                    BIT.DevLog("[COMBAT-DROP] unit=" .. tostring(unit)
                          .. " race=" .. tostring(okR and rf or "?")
                          .. " playerInCombat=" .. tostring(UnitAffectingCombat("player")))
                end
                -- Shadowmeld fallback trigger: racials don't fire UNIT_SPELLCAST_SUCCEEDED
                -- for partyN in 12.x, and the stealth buff 58984 is hidden from
                -- C_UnitAuras on other clients. Combat drop while the rest of the
                -- group is still fighting is the most distinctive Shadowmeld signal.
                if unit ~= "player" and unit:find("^party%d$") then
                    local okR, _, raceFile = pcall(UnitRace, unit)
                    if okR and raceFile == "NightElf" and UnitAffectingCombat("player") then
                        local name = SafeUnitName(unit)
                        if name then
                            local cdState = BIT.syncCdState and BIT.syncCdState[name]
                            local cdEnd   = cdState and cdState[58984]
                            if not cdEnd or cdEnd <= now then
                                if BIT.devLogMode then
                                    BIT.DevLog("[SM-CDROP] " .. name .. " dropped combat mid-fight -> Shadowmeld")
                                end
                                BIT.SyncCD:OnSpellUsed(name, 58984, 120)
                                -- Also force-set activeBuffs so the glow shows via
                                -- RefreshBuffHighlights (buff aura is invisible on partyN)
                                if not activeBuffs[name] then activeBuffs[name] = {} end
                                activeBuffs[name][58984] = true
                                RefreshBuffHighlights(name)
                                -- Schedule buff clear after 20s (Shadowmeld max duration)
                                C_Timer.After(20, function()
                                    if activeBuffs[name] then
                                        activeBuffs[name][58984] = nil
                                        RefreshBuffHighlights(name)
                                    end
                                end)
                            end
                        end
                    end
                end
            end
            _prevInCombat[unit] = inCombat
        end
    end)

    -- Global absorb tracking (Shield evidence)
    local absorbFrame = CreateFrame("Frame")
    absorbFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    absorbFrame:SetScript("OnEvent", function(_, _, unit)
        if unit and (unit:find("^party%d$") or unit == "player") then
            _lastShieldTime[unit] = GetTime()
        end
    end)

    local function RegisterPartyEvidence()
        -- Never call UnregisterAllEvents here: that creates a brief gap where
        -- party casts are missed (GROUP_ROSTER_UPDATE fires mid-combat on deaths,
        -- achievements, etc.). RegisterUnitEvent is idempotent — safe to call
        -- multiple times. Empty unit slots fire no events, so stale registrations
        -- for departed members are harmless.
        castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        castFrame:RegisterUnitEvent("UNIT_FLAGS", "player")
        _prevFeignDeath["player"] = UnitIsFeignDeath("player")
        _prevInCombat["player"] = UnitAffectingCombat("player")
        if not IsInGroup() then return end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", u)
                castFrame:RegisterUnitEvent("UNIT_FLAGS", u)
                _prevFeignDeath[u] = UnitIsFeignDeath(u)
                _prevInCombat[u] = UnitAffectingCombat(u)
            end
        end
    end

    local rosterFrame = CreateFrame("Frame")
    rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterFrame:SetScript("OnEvent", function()
        -- Immediate call may miss party units during zone transitions (UnitExists = false
        -- on loading screens). Always retry with a delay so the final registration
        -- happens when units are actually loaded.
        RegisterPartyEvidence()
        C_Timer.After(1, RegisterPartyEvidence)
        C_Timer.After(3, RegisterPartyEvidence)
    end)
    C_Timer.After(1, RegisterPartyEvidence)
end

-- NOTE: COMBAT_LOG_EVENT_UNFILTERED cannot be used in WoW Retail 11.x (causes
-- ADDON_ACTION_FORBIDDEN taint). Instead, party cast detection is handled via
-- UNIT_SPELLCAST_SUCCEEDED in the castFrame above, which is registered per-unit
-- and does not cause taint. Combined with the widened timing windows (0.4s cast,
-- 1.0s duration tolerance) and auto-generated rules, this provides reliable
-- detection equivalent to the CLEU approach.

-- ── Inspect system REMOVED ─────────────────────────────────────────────
-- Spec & talent data now comes from addon communication + C_Traits scans.
-- GetSpecForPlayer() reads from BIT.SyncCD.users and falls back to cached
-- GetInspectSpecialization (which works for auto-inspected party members).
-- No more NotifyInspect calls, no more INSPECT_READY handling.
-- This eliminates all interference with manual player inspects.

-- Public no-op stub so existing call sites don't error
function BIT.SyncCD.InvalidateInspect() end

local function UpdateIcon(ico, cdEnd, playerName)
    local now = GetTime()
    local maxCh = ico._maxCharges or 0
    local sid   = ico.spellID or 0
    local pName = playerName or ico._playerName

    -- ── Charge badge for ALL players ────────────────────────────────
    local ownCharges, ownMaxCh  -- populated for own player below
    if maxCh > 1 and pName then
        local isOwn = (pName == BIT.myName)
        if isOwn then
            -- Own player: use C_Spell.GetSpellCharges for authoritative data.
            -- Read ALL fields: currentCharges, maxCharges, cooldownStartTime, cooldownDuration.
            -- This works in combat — DetaintNumber handles tainted secret values.
            local ok, result = pcall(C_Spell.GetSpellCharges, sid)
            if ok and result and type(result) == "table" then
                local okN, s = pcall(string.format, "%.0f", result.currentCharges)
                local charges = okN and tonumber(s) or nil
                local okM, sm = pcall(string.format, "%.0f", result.maxCharges)
                local maxC = okM and tonumber(sm) or nil
                if charges then
                    ownCharges = charges
                    ownMaxCh   = maxC
                    ico.chargeBadge:SetText(charges)
                    ico.chargeBadge:Show()
                    -- Override cdEnd from GetSpellCharges (authoritative, works in combat)
                    if charges < (maxC or maxCh) then
                        local okS, ss = pcall(string.format, "%.6f", result.cooldownStartTime)
                        local okD, sd = pcall(string.format, "%.6f", result.cooldownDuration)
                        local cdStart = okS and tonumber(ss) or nil
                        local cdDur   = okD and tonumber(sd) or nil
                        if cdStart and cdDur and cdStart > 0 and cdDur > 0 then
                            cdEnd = cdStart + cdDur
                        end
                    else
                        cdEnd = 0  -- all charges available
                    end
                end
            end
        else
            -- Party member: use FIFO charge tracker
            local ct = _chargeTracker[pName] and _chargeTracker[pName][sid]
            if ct then
                local avail = ct.fifo:availableCharges(now)
                ico.chargeBadge:SetText(avail)
                ico.chargeBadge:Show()
                -- Update cdEnd to reflect next recharge (if any charges are recharging)
                if avail < ct.maxCharges then
                    local nextR = ct.fifo:nextRechargeAt()
                    if nextR and nextR > now then cdEnd = nextR end
                end
            else
                -- No uses tracked yet → all charges available
                ico.chargeBadge:SetText(maxCh)
                ico.chargeBadge:Show()
            end
        end
    elseif ico.chargeBadge then
        ico.chargeBadge:Hide()
    end

    -- ── CD swipe + timer ────────────────────────────────────────────
    -- For charge-based spells, only show full dim when ALL charges are on CD.
    local allOnCD = false
    if maxCh > 1 and pName then
        if pName == BIT.myName then
            -- Own player: use the authoritative charge count from above
            if ownCharges and ownCharges == 0 then allOnCD = true end
        else
            local ct = _chargeTracker[pName] and _chargeTracker[pName][sid]
            if ct then
                allOnCD = ct.fifo:availableCharges(now) == 0
            end
        end
    end

    -- ── Determine if a buff is active (drives glow + suppresses CD UI) ──
    -- While the buff is active, the player still has the defensive up — showing
    -- a CD swipe/timer would be misleading. We only want the glow during that
    -- phase; the CD becomes visible once the buff ends.
    local buffActive = false
    if pName and LibButtonGlow and BIT.db.syncCdGlow then
        local buffEnd = _buffActiveEnd[pName] and _buffActiveEnd[pName][sid]
        if buffEnd and buffEnd > now then
            buffActive = true
            -- For own player: verify the buff is actually still present
            -- (handles early cancels and buffs that expire between events).
            -- GetAuraDataBySpellID can throw in 12.x when internal lookups
            -- hit a secret value from a tainted aura; fall back to enumerating
            -- HELPFUL auras via GetUnitAuras so the self-cancel still works.
            if pName == BIT.myName then
                local okA, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", sid, "HELPFUL")
                local auraPresent = okA and aura ~= nil
                local scanOk = okA
                if not okA then
                    local okU, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
                    if okU and auras then
                        scanOk = true
                        for _, ad in ipairs(auras) do
                            if ad and ad.spellId then
                                local okS, s = pcall(string.format, "%.0f", ad.spellId)
                                if okS and tonumber(s) == sid then
                                    auraPresent = true
                                    break
                                end
                            end
                        end
                    end
                end
                if scanOk and not auraPresent then
                    _buffActiveEnd[pName][sid] = 0
                    buffActive = false
                end
            end
        end
    end

    if cdEnd > now and not buffActive then
        local rem = cdEnd - now
        local cd = ico._cd or 30
        -- Start or restart the swipe when:
        --   a) CD wasn't running at all, OR
        --   b) cdEnd jumped forward significantly (charge 1 finished → charge 2 starts)
        if not ico._cdRunning or (ico._swipeCdEnd and cdEnd > ico._swipeCdEnd + 2) then
            ico.cd:SetCooldown(cdEnd - cd, cd)
            ico._cdRunning  = true
            ico._swipeCdEnd = cdEnd
        end
        local sec = math.floor(rem + 0.5)
        if ico._lastSec ~= sec then
            ico._lastSec = sec
            local txt = sec > 0 and FormatCdTime(sec) or ""
            ico.cdText:SetText(txt)
            ico.cdText:Show()
        end
        -- Charge-based: only dim fully when ALL charges are on CD
        if maxCh > 1 then
            ico.tex:SetAlpha(allOnCD and 0.3 or 0.65)
            -- Show swipe only when all charges are on CD
            ico.cd:SetDrawSwipe(allOnCD)
        else
            ico.tex:SetAlpha(0.3)
        end
    else
        if ico._cdRunning then
            ico.cd:Clear()
            ico._cdRunning  = false
            ico._swipeCdEnd = nil
            ico._lastSec    = nil
            ico.cdText:Hide()
            ico.tex:SetAlpha(1.0)
        end
    end

    -- ── Glow while buff is active (LibButtonGlow) ────────────────────
    if pName and LibButtonGlow then
        if buffActive then
            if not ico._glowActive then
                ico.cd:SetDrawSwipe(false)
                LibButtonGlow.ShowOverlayGlow(ico)
                ico._glowActive = true
            end
            -- Full brightness while buff is active
            ico.tex:SetAlpha(1.0)
        else
            if ico._glowActive then
                LibButtonGlow.HideOverlayGlow(ico)
                ico._glowActive = false
                -- Restore swipe if still on CD
                if cdEnd > now then
                    if maxCh > 1 then
                        ico.cd:SetDrawSwipe(allOnCD)
                    else
                        ico.cd:SetDrawSwipe(true)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Auto-discover party members (M+ support: no HELLO needed)
-- Scans party1-party4, creates SyncCD.users entries with class
-- and queues inspect for spec/talents. Called every rebuild.
------------------------------------------------------------
local function ScanPartyMembers()
    if not IsInGroup() then return end
    if not BIT.SyncCD.users then BIT.SyncCD.users = {} end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitIsPlayer(u) then
            local name = SafeUnitName(u)
            if name then
                local entry = BIT.SyncCD.users[name]
                if not entry then
                    local cls = (UnitClassBase or UnitClass)(u)
                    if cls then
                        BIT.SyncCD.users[name] = { class = cls }
                        entry = BIT.SyncCD.users[name]
                    end
                elseif not entry.class then
                    local cls = (UnitClassBase or UnitClass)(u)
                    if cls then entry.class = cls end
                end
                -- Store race (raceFile) for racial spell lookup
                if entry and not entry.race then
                    local okR, _, raceFile = pcall(UnitRace, u)
                    if okR and raceFile then entry.race = raceFile end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Helper: returns the active display mode for the current group type
------------------------------------------------------------
local _cachedMode    = nil   -- last mode used; nil = not yet set
local _rebuildTimer  = nil   -- debounce handle
local _ownTalentVer  = 0     -- bumped on PLAYER_TALENT_UPDATE / TRAIT_CONFIG_UPDATED

local function GetEffectiveMode()
    if IsInRaid() then
        return BIT.db.syncCdModeRaid or "BARS"
    else
        return BIT.db.syncCdModeGroup or "ATTACH"
    end
end

------------------------------------------------------------
-- Mode A: Standalone Window
------------------------------------------------------------
local syncFrame = nil

local function RebuildWindowRow(name)
    -- get class: own player, registry entry, or direct UnitClass
    local class = (name == BIT.myName) and BIT.myClass
    if not class then
        local entry = BIT.SyncCD.users and BIT.SyncCD.users[name]
        class = entry and entry.class
    end
    if not class then
        for i = 1, 4 do
            local u = "party"..i
            if UnitExists(u) and SafeUnitName(u) == name then
                class = (UnitClassBase or UnitClass)(u)
                break
            end
        end
    end

    local row = syncRows[name]
    local currentSpec = GetSpecForPlayer(name)

    if not row then
        row = { icons = {}, _lastSpec = nil }
        row.frame = CreateFrame("Frame", nil, syncFrame)
        row.frame:SetHeight(ROW_H())
        -- Forward drag to syncFrame so the window is draggable from any row area
        row.frame:EnableMouse(true)
        row.frame:RegisterForDrag("LeftButton")
        row.frame:SetScript("OnDragStart", function()
            if not BIT.db.syncCdBarsLocked then syncFrame:StartMoving() end
        end)
        row.frame:SetScript("OnDragStop", function()
            syncFrame:StopMovingOrSizing()
            if BIT.charDb then
                BIT.charDb.syncCdPosX = syncFrame:GetLeft()
                BIT.charDb.syncCdPosY = syncFrame:GetBottom()
            end
        end)
        row.nameText = row.frame:CreateFontString(nil, "OVERLAY")
        BIT.Media:SetFont(row.nameText, 11)
        row.nameText:SetPoint("LEFT", row.frame, "LEFT", 2, 0)
        row.nameText:SetWidth(NAME_W)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        syncRows[name] = row
    end

    local cc = class and BIT.CLASS_COLORS and BIT.CLASS_COLORS[class]
    if cc then row.nameText:SetTextColor(cc[1], cc[2], cc[3])
    else        row.nameText:SetTextColor(1, 1, 1) end
    row.nameText:SetText(BIT.GetDisplayName(name))

    -- only rebuild icons if spec, icon size, spacing, counter size, disabled-filter, or talents changed
    local curSize        = ICON_SIZE()
    local curSpacing     = ICON_PAD()
    local curCounterSz   = BIT.db.syncCdCounterSize or 14
    local curDisabledVer = BIT.db.syncCdDisabledVer or 0
    local curCatVer      = BIT.db.syncCdCatVer      or 0
    local curTalentVer   = (name == BIT.myName) and _ownTalentVer or 0
    if row._lastSpec ~= currentSpec or row._lastIconSize ~= curSize
       or row._lastSpacing ~= curSpacing
       or row._lastCounterSz ~= curCounterSz or row._lastDisabledVer ~= curDisabledVer
       or row._lastCatVer ~= curCatVer or row._lastTalentVer ~= curTalentVer then
        row._lastSpec        = currentSpec
        row._lastIconSize    = curSize
        row._lastSpacing     = curSpacing
        row._lastCounterSz   = curCounterSz
        row._lastDisabledVer = curDisabledVer
        row._lastCatVer      = curCatVer
        row._lastTalentVer   = curTalentVer

        local spells = GetSpellsForPlayer(name)

        -- Diff-based icon update: reuse existing icons for spells still in the
        -- list (no Hide/Show flicker for unchanged entries). Only icons for
        -- removed spells get hidden, only icons for newly added spells get created.
        local newSet = {}
        for _, s in ipairs(spells) do newSet[s.id] = true end
        for sid, ico in pairs(row.icons) do
            if not newSet[sid] then
                if ico._glowActive and LibButtonGlow then
                    LibButtonGlow.HideOverlayGlow(ico)
                    ico._glowActive = false
                end
                ico:Hide()
                row.icons[sid] = nil
            end
        end

        local x = NAME_W + 4
        for _, s in ipairs(spells) do
            local ico = row.icons[s.id]
            if not ico then
                ico = CreateIcon(row.frame, s.id)
                row.icons[s.id] = ico
            end
            ico:SetSize(ICON_SIZE(), ICON_SIZE())
            ico:ClearAllPoints()
            ico:SetPoint("LEFT", row.frame, "LEFT", x, 0)
            ico._cd         = s.cd
            ico._maxCharges = s.charges or 0
            ico._playerName = name
            ico._spellName  = s.name
            ico:Show()
            x = x + ICON_SIZE() + ICON_PAD()
        end

        row.frame:SetWidth(x + 4)
        RefreshBuffHighlights(name)
    end

    return row
end

local function ApplyWindowStyle()
    if not syncFrame then return end
    local locked  = BIT.db.syncCdBarsLocked or false
    local compact = BIT.db.syncCdWindowCompact or false

    -- Lock: SetMovable(false) is the reliable WoW way — StartMoving() becomes a no-op
    syncFrame:SetMovable(not locked)

    -- Drag handle: compact-only, and must be both hidden AND mouse-disabled when locked
    -- (SetShown(false) alone does NOT disable mouse in WoW)
    local handleActive = compact and not locked
    if syncFrame._dragHandle then
        syncFrame._dragHandle:SetShown(handleActive)
        syncFrame._dragHandle:EnableMouse(handleActive)
    end

    if compact then
        if locked then
            syncFrame:SetBackdropColor(0, 0, 0, 0)
            syncFrame:SetBackdropBorderColor(0, 0, 0, 0)
        else
            -- Unlocked compact: subtle background so the frame is findable
            syncFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
            syncFrame:SetBackdropBorderColor(0.8, 0.5, 0, 0.5)
        end
        if syncFrame._title then syncFrame._title:Hide() end
    else
        syncFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
        syncFrame:SetBackdropBorderColor(0.8, 0.5, 0, 0.7)
        if syncFrame._title then syncFrame._title:Show() end
    end

    -- Lock button: visible below the frame only when unlocked + frame shown
    if syncFrame._lockBtn then
        if not locked and syncFrame:IsShown() then
            syncFrame._lockBtn:ClearAllPoints()
            syncFrame._lockBtn:SetPoint("TOP", syncFrame, "BOTTOM", 0, -2)
            syncFrame._lockBtn:Show()
        else
            syncFrame._lockBtn:Hide()
        end
    end
end

-- Expose for Config callbacks that toggle lock/compact without a full rebuild
BIT.SyncCD.ApplyStyle = ApplyWindowStyle

local function GetPlayerClass(name)
    if name == BIT.myName then return BIT.myClass end
    if BIT.SyncCD.users and BIT.SyncCD.users[name] then
        return BIT.SyncCD.users[name].class
    end
    local e = BIT.Registry and BIT.Registry:Get(name)
    return e and e.class
end

------------------------------------------------------------
-- CC WINDOW — standalone icon grid showing only CC spells
-- from all group members, with player abbreviation on each icon
------------------------------------------------------------

-- CC Window functions removed (CC tracking removed)




local function RebuildWindow(forceFallback)
    if not syncFrame then return end
    if not BIT.db.showSyncCDs or (GetEffectiveMode() == "ATTACH" and not forceFallback) then
        syncFrame:Hide()
        return
    end
    -- Hide when solo if "only in group" is enabled
    if BIT.db.syncOnlyInGroup and not IsInGroup() then
        syncFrame:Hide()
        return
    end

    local entries = {}
    -- Own row: whenever "Show own CDs" is enabled
    if BIT.myName and BIT.myClass and BIT.db.showOwnSyncCD ~= false then
        entries[#entries+1] = BIT.myName
    end
    for name in pairs(BIT.SyncCD.users or {}) do
        if name ~= BIT.myName then entries[#entries+1] = name end
    end

    -- Hide ONLY rows that are no longer active (prevents all-icon flicker on
    -- rebuild triggers like HELLO broadcasts / talent noise events — rows that
    -- are still present stay shown throughout the rebuild).
    local activeSet = {}
    for _, name in ipairs(entries) do activeSet[name] = true end
    for name, row in pairs(syncRows) do
        if not activeSet[name] and row.frame then row.frame:Hide() end
    end

    local y, maxW = -4, 200
    for _, name in ipairs(entries) do
        local row = RebuildWindowRow(name)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", syncFrame, "TOPLEFT", 4, y)
        row.frame:Show()
        y    = y - (ROW_H() + 2)
        local rw = row.frame:GetWidth() or 0
        if rw > maxW then maxW = rw end
    end

    if #entries == 0 then
        syncFrame:SetSize(200, 40)
    else
        syncFrame:SetSize(maxW + 8, math.abs(y) + 4)
    end

    ApplyWindowStyle()
    syncFrame:Show()
end

local function UpdateWindow()
    if not syncFrame or not syncFrame:IsShown() then return end
    local now = GetTime()
    for name, row in pairs(syncRows) do
        if row.frame:IsShown() then
            local state = BIT.syncCdState[name] or {}
            for sid, ico in pairs(row.icons) do
                UpdateIcon(ico, state[sid] or 0, name)
            end
        end
    end
end

local function CreateWindowFrame()
    if syncFrame then return end

    syncFrame = CreateFrame("Frame", "BliZziSyncCDFrame", UIParent, "BackdropTemplate")
    syncFrame:SetSize(200, 40)
    syncFrame:SetFrameStrata("MEDIUM")
    syncFrame:SetClampedToScreen(true)
    syncFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    syncFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    syncFrame:SetBackdropBorderColor(0.8, 0.5, 0, 0.7)

    local title = syncFrame:CreateFontString(nil, "OVERLAY")
    BIT.Media:SetFont(title, 10)
    title:SetPoint("BOTTOMLEFT", syncFrame, "TOPLEFT", 4, 2)
    title:SetText("|cffffaa00Party CDs|r")
    syncFrame._title = title

    -- Compact-mode drag handle: thin bar at top, only shown when compact
    local dragHandle = CreateFrame("Frame", nil, syncFrame, "BackdropTemplate")
    dragHandle:SetHeight(5)
    dragHandle:SetPoint("TOPLEFT",  syncFrame, "TOPLEFT",  0, 0)
    dragHandle:SetPoint("TOPRIGHT", syncFrame, "TOPRIGHT", 0, 0)
    dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    dragHandle:SetBackdropColor(0.8, 0.5, 0, 0.5)
    dragHandle:SetFrameLevel(syncFrame:GetFrameLevel() + 20)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        if not BIT.db.syncCdBarsLocked then syncFrame:StartMoving() end
    end)
    dragHandle:SetScript("OnDragStop", function()
        syncFrame:StopMovingOrSizing()
        if BIT.charDb then
            BIT.charDb.syncCdPosX = syncFrame:GetLeft()
            BIT.charDb.syncCdPosY = syncFrame:GetBottom()
        end
    end)
    dragHandle:Hide()
    syncFrame._dragHandle = dragHandle

    syncFrame:SetMovable(true)
    syncFrame:EnableMouse(true)
    syncFrame:RegisterForDrag("LeftButton")
    syncFrame:SetScript("OnDragStart", function(self)
        if not BIT.db.syncCdBarsLocked then self:StartMoving() end
    end)
    syncFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if BIT.charDb then
            BIT.charDb.syncCdPosX = self:GetLeft()
            BIT.charDb.syncCdPosY = self:GetBottom()
        end
    end)

    if BIT.charDb and BIT.charDb.syncCdPosX then
        syncFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            BIT.charDb.syncCdPosX, BIT.charDb.syncCdPosY)
    else
        syncFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end

    -- Lock button: appears below the window when unlocked
    local lockBtn = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    lockBtn:SetSize(40, 16)
    lockBtn:SetFrameStrata("DIALOG")
    lockBtn:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    lockBtn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    lockBtn:SetBackdropBorderColor(0.6, 0.4, 0, 0.9)
    local lockLbl = lockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockLbl:SetAllPoints()
    lockLbl:SetText("|cFFFFCC00Lock|r")
    lockBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.7, 0, 1) end)
    lockBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.6, 0.4, 0, 0.9) end)
    lockBtn:SetScript("OnClick", function()
        BIT.db.syncCdBarsLocked = true
        ApplyWindowStyle()
    end)
    lockBtn:Hide()
    syncFrame._lockBtn = lockBtn

    -- Hide lock button when window hides
    syncFrame:HookScript("OnHide", function()
        if syncFrame._lockBtn then syncFrame._lockBtn:Hide() end
    end)

    syncFrame:Hide()
    BIT.SyncCD.frame = syncFrame
end

------------------------------------------------------------
-- Mode B: Attach to party unit frames
------------------------------------------------------------

local function HideAllAttached()
    for _, bar in pairs(attachedBars) do
        if bar.frame then bar.frame:Hide() end
    end
    attachedBars = {}
end

-- position anchor config: attach position → { point, relPoint, x, y, horizontal }
local ATTACH_CONFIG = {
    RIGHT  = { point = "LEFT",   relPoint = "RIGHT",  ox =  4, oy = 0, horiz = true },
    LEFT   = { point = "RIGHT",  relPoint = "LEFT",   ox = -4, oy = 0, horiz = true },
    TOP    = { point = "BOTTOM", relPoint = "TOP",    ox =  0, oy = 4, horiz = true },
    BOTTOM = { point = "TOP",    relPoint = "BOTTOM", ox =  0, oy =-4, horiz = true },
}

local function BuildAttachedBar(unit, name)
    local currentSpec   = GetSpecForPlayer(name)
    local curPos        = BIT.db.syncCdAttachPos or "LEFT"
    local curIconSize   = ICON_SIZE()
    local curSpacing    = ICON_PAD()
    local curCounterSz  = BIT.db.syncCdCounterSize or 14
    local curDisabledVer= BIT.db.syncCdDisabledVer or 0
    local curCatVer     = BIT.db.syncCdCatVer or 0
    local curRowGap     = BIT.db.syncCdAttachRowGap  or 4
    local curOffsetX    = BIT.db.syncCdAttachOffsetX or 0
    local curOffsetY    = BIT.db.syncCdAttachOffsetY or 0
    local curTopLayout    = BIT.db.syncCdTopLayout    or "COLUMNS"
    local curBottomLayout = BIT.db.syncCdBottomLayout or "ROWS"
    local _ue           = BIT.SyncCD.users and BIT.SyncCD.users[name]
    local curTalentVer  = (name == BIT.myName) and _ownTalentVer
                          or (_ue and _ue._talentVer or 0)
    -- Local aura detection works for ALL party members — no addon required on their side.
    -- No desaturation or hiding based on addon presence.

    local parentFrame   = GetPartyUnitFrame(unit)
    local existing      = attachedBars[unit]

    -- reuse existing bar only if ALL display settings AND the parent frame are unchanged
    if existing and existing.frame
       and existing._lastParentFrame == parentFrame
       and existing._lastSpec        == currentSpec
       and existing._lastPos         == curPos
       and existing._lastIconSize    == curIconSize
       and existing._lastSpacing     == curSpacing
       and existing._lastCounterSz   == curCounterSz
       and existing._lastDisabledVer == curDisabledVer
       and existing._lastCatVer      == curCatVer
       and existing._lastRowGap      == curRowGap
       and existing._lastOffsetX      == curOffsetX
       and existing._lastOffsetY      == curOffsetY
       and existing._lastTopLayout    == curTopLayout
       and existing._lastBottomLayout == curBottomLayout
       and existing._lastTalentVer    == curTalentVer then
        existing.frame:Show()
        return
    end

    if not parentFrame then
        if existing and existing.frame then existing.frame:Hide() end
        return
    end

    local spells = GetSpellsForPlayer(name)
    if #spells == 0 then
        if existing and existing.frame then existing.frame:Hide() end
        return
    end

    local pos = curPos
    local cfg = ATTACH_CONFIG[pos] or ATTACH_CONFIG.LEFT

    -- Reuse existing bar & frame if possible. Only the parent frame change
    -- (unit-frame addon replacement) forces a fresh frame, since the existing
    -- frame would be parented to a stale reference. All other changes (layout,
    -- size, spec, talents) can stay with the same frame + diff icons.
    local bar
    if existing and existing.frame and existing._lastParentFrame == parentFrame then
        bar = existing
        -- Reset anchor in case the layout moved the frame to a different corner.
        bar.frame:ClearAllPoints()
    else
        if existing and existing.frame then existing.frame:Hide() end
        bar = { icons = {} }
        bar.frame = CreateFrame("Frame", nil, parentFrame)
        bar.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 10)
    end
    bar.icons = bar.icons or {}
    bar._lastParentFrame  = parentFrame
    bar._lastSpec         = currentSpec
    bar._lastPos          = curPos
    bar._lastIconSize     = curIconSize
    bar._lastSpacing      = curSpacing
    bar._lastCounterSz    = curCounterSz
    bar._lastDisabledVer  = curDisabledVer
    bar._lastCatVer       = curCatVer
    bar._lastRowGap       = curRowGap
    bar._lastOffsetX      = curOffsetX
    bar._lastOffsetY      = curOffsetY
    bar._lastTopLayout    = curTopLayout
    bar._lastBottomLayout = curBottomLayout
    bar._lastTalentVer    = curTalentVer

    -- ── Multi-row layout: each category on its own configurable row ──
    local iSize   = ICON_SIZE()
    local iPad    = ICON_PAD()
    local ROW_GAP = curRowGap

    -- Group spells by their assigned row number
    local rowMap = {}
    for _, s in ipairs(spells) do
        local rn = GetCatRow(s.cat)
        if not rowMap[rn] then rowMap[rn] = {} end
        rowMap[rn][#rowMap[rn] + 1] = s
    end

    -- Sort row numbers so rows are always drawn top-to-bottom in order
    local rowNums = {}
    for rn in pairs(rowMap) do rowNums[#rowNums + 1] = rn end
    table.sort(rowNums)

    bar.frame:SetPoint(cfg.point, parentFrame, cfg.relPoint, cfg.ox + curOffsetX, cfg.oy + curOffsetY)

    -- Hide icons for spells no longer in the spell list (diff-based update).
    local newSet = {}
    for _, s in ipairs(spells) do newSet[s.id] = true end
    for sid, ico in pairs(bar.icons) do
        if not newSet[sid] then
            if ico._glowActive and LibButtonGlow then
                LibButtonGlow.HideOverlayGlow(ico)
                ico._glowActive = false
            end
            ico:Hide()
            bar.icons[sid] = nil
        end
    end

    -- Helper: place (create or reuse) one icon at a given anchor + offset.
    -- Reuses the existing icon for the spellID so spells still in the list
    -- don't flicker when layout/talent rebuilds fire.
    local function placeIcon(s, anchor, xOff, yOff)
        local ico = bar.icons[s.id]
        if not ico then
            ico = CreateIcon(bar.frame, s.id)
            bar.icons[s.id] = ico
        end
        ico:SetSize(iSize, iSize)
        ico:ClearAllPoints()
        ico:SetPoint(anchor, bar.frame, anchor, xOff, yOff)
        ico._cd         = s.cd
        ico._maxCharges = s.charges or 0
        ico._playerName = name
        ico._spellName  = s.name
        ico:Show()
    end

    -- Sub-layout A: COLUMNS — each category = one vertical column, growing in X.
    -- reverseY=true → build upward (TOP attach); false → build downward (BOTTOM attach).
    local function layoutColumns(reverseY)
        local maxIconsInCol = 0
        for _, rn in ipairs(rowNums) do
            if #rowMap[rn] > maxIconsInCol then maxIconsInCol = #rowMap[rn] end
        end
        bar.frame:SetSize(
            math.max(iSize, #rowNums      * iSize + math.max(0, #rowNums      - 1) * ROW_GAP),
            math.max(iSize, maxIconsInCol * iSize + math.max(0, maxIconsInCol - 1) * iPad))
        for colIdx, rn in ipairs(rowNums) do
            local xOff = (colIdx - 1) * (iSize + ROW_GAP)
            for iconIdx, s in ipairs(rowMap[rn]) do
                if reverseY then
                    placeIcon(s, "BOTTOMLEFT", xOff,  (iconIdx - 1) * (iSize + iPad))
                else
                    placeIcon(s, "TOPLEFT",    xOff, -(iconIdx - 1) * (iSize + iPad))
                end
            end
        end
    end

    -- Sub-layout B: ROWS — each category = one horizontal row, growing in Y.
    -- reverseY=true → build upward (TOP attach); false → build downward (BOTTOM attach).
    local function layoutRows(reverseY)
        local maxCols = 0
        for _, rn in ipairs(rowNums) do
            if #rowMap[rn] > maxCols then maxCols = #rowMap[rn] end
        end
        bar.frame:SetSize(
            math.max(iSize, maxCols   * iSize + math.max(0, maxCols   - 1) * iPad),
            math.max(iSize, #rowNums  * iSize + math.max(0, #rowNums  - 1) * ROW_GAP))
        for rowIdx, rn in ipairs(rowNums) do
            local yOff = reverseY
                and  (rowIdx - 1) * (iSize + ROW_GAP)   -- upward: first row at bottom
                or  -(rowIdx - 1) * (iSize + ROW_GAP)   -- downward: first row at top
            local anchor = reverseY and "BOTTOMLEFT" or "TOPLEFT"
            for colIdx, s in ipairs(rowMap[rn]) do
                placeIcon(s, anchor, (colIdx - 1) * (iSize + iPad), yOff)
            end
        end
    end

    if pos == "TOP" then
        -- Flush against bottom of unit frame, bar grows upward.
        if curTopLayout == "ROWS" then
            layoutRows(true)     -- rows stack upward, row 1 closest to unit frame
        else
            layoutColumns(true)  -- columns, icons fill bottom-to-top
        end
    elseif pos == "BOTTOM" then
        -- Flush against top of unit frame (bar frame TOP anchored there), bar grows downward.
        if curBottomLayout == "COLUMNS" then
            layoutColumns(false) -- columns, icons fill top-to-bottom
        else
            layoutRows(false)    -- rows stack downward, row 1 closest to unit frame
        end
    else
        -- ── LEFT / RIGHT: rows are horizontal strips stacked top-to-bottom ──
        -- LEFT attach:  icons fill right-to-left (flush against unit frame).
        -- RIGHT attach: icons fill left-to-right.
        local maxCols = 0
        for _, rn in ipairs(rowNums) do
            if #rowMap[rn] > maxCols then maxCols = #rowMap[rn] end
        end
        local totalW = math.max(iSize, maxCols * iSize + math.max(0, maxCols - 1) * iPad)
        local totalH = math.max(iSize, #rowNums * iSize + math.max(0, #rowNums - 1) * ROW_GAP)
        bar.frame:SetSize(totalW, totalH)

        local reverseX = (pos == "LEFT")
        for rowIdx, rn in ipairs(rowNums) do
            local yOff = -(rowIdx - 1) * (iSize + ROW_GAP)
            for colIdx, s in ipairs(rowMap[rn]) do
                local xOff
                if reverseX then
                    xOff = totalW - colIdx * iSize - (colIdx - 1) * iPad
                else
                    xOff = (colIdx - 1) * (iSize + iPad)
                end
                placeIcon(s, "TOPLEFT", xOff, yOff)
            end
        end
    end

    RefreshBuffHighlights(name)
    bar.frame:Show()
    attachedBars[unit] = bar
end

local function RebuildAttached()
    if not BIT.db.showSyncCDs or GetEffectiveMode() ~= "ATTACH" then
        HideAllAttached()
        return
    end
    if BIT.db.syncOnlyInGroup and not IsInGroup() then
        HideAllAttached()
        return
    end

    -- Build name→unit map
    local nameToUnit = {}
    if BIT.myName then nameToUnit[BIT.myName] = "player" end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local n = SafeUnitName(u)
            if n then nameToUnit[n] = u end
        end
    end

    -- Determine which units should be active
    local activeUnits = {}
    if BIT.myName and BIT.myClass and BIT.db.showOwnSyncCD ~= false then
        local unit = nameToUnit[BIT.myName]
        if unit then activeUnits[unit] = BIT.myName end
    end
    for name in pairs(BIT.SyncCD.users or {}) do
        if name ~= BIT.myName then
            local unit = nameToUnit[name]
            if unit then activeUnits[unit] = name end
        end
    end
    -- Also include party members who don't have the addon (not in SyncCD.users)
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not activeUnits[u] then
            local n = SafeUnitName(u)
            if n then activeUnits[u] = n end
        end
    end

    -- Hide bars for units no longer active (player left group etc.)
    for unit, bar in pairs(attachedBars) do
        if not activeUnits[unit] then
            if bar.frame then bar.frame:Hide() end
            attachedBars[unit] = nil
        end
    end

    -- Check if ANY unit frame actually exists before attaching
    local anyFrameFound = false
    for unit in pairs(activeUnits) do
        if GetPartyUnitFrame(unit) then
            anyFrameFound = true
            break
        end
    end

    -- No unit frames detected → fall back to standalone window
    if not anyFrameFound then
        RebuildWindow(true)
        return
    end

    -- Hide standalone window if it was showing as fallback
    if syncFrame then syncFrame:Hide() end

    -- Build/reuse bars for active units (BuildAttachedBar skips rebuild if spec unchanged)
    for unit, name in pairs(activeUnits) do
        BuildAttachedBar(unit, name)
    end
end

local function UpdateAttached()
    if not BIT.db.showSyncCDs or GetEffectiveMode() ~= "ATTACH" then return end
    for unit, bar in pairs(attachedBars) do
        if bar.frame and bar.frame:IsShown() then
            local name = (unit == "player") and BIT.myName or SafeUnitName(unit)
            if name then
                local state = BIT.syncCdState[name] or {}
                for sid, ico in pairs(bar.icons) do
                    UpdateIcon(ico, state[sid] or 0, name)
                end
            end
        end
    end
end

------------------------------------------------------------
-- GROUP BARS mode — one fill-progress bar per spell per player
-- Fully configurable, matching the interrupt-tracker feature set.
------------------------------------------------------------
local barsFrame      = nil
local groupSpellBars = {}  -- currently active spell-bar frames
local barPool        = {}  -- hidden reusable frames (never destroyed)
local barsTitle      = nil -- title FontString reference

local function GROUP_BAR_W()   return (BIT.db and BIT.db.frameWidth) or 250  end
local function GROUP_BAR_H()   return math.max(12, (BIT.db and BIT.db.barHeight) or 22) end
local function GROUP_BAR_GAP() return (BIT.db and BIT.db.barGap) or 0  end

-- GetPlayerClass: defined earlier (before CC Window section)

-- Returns {r,g,b} fill color for a given class, respecting useClassColors setting
local function GetFillColor(class)
    local db = BIT.db or {}
    if db.useClassColors ~= false then
        local c = BIT.CLASS_COLORS[class or ""] or {0.4, 0.8, 1.0}
        return c[1], c[2], c[3]
    end
    return db.customColorR or 0.4, db.customColorG or 0.8, db.customColorB or 1.0
end
local function GetBgColor(class)
    local db = BIT.db or {}
    if db.useClassColors ~= false then
        local c = BIT.CLASS_COLORS[class or ""] or {0.1, 0.1, 0.1}
        return c[1] * 0.15, c[2] * 0.15, c[3] * 0.15
    end
    return db.customBgColorR or 0.1, db.customBgColorG or 0.1, db.customBgColorB or 0.1
end

-- Apply frame-level settings (title, opacity, lock) to existing barsFrame
local function ApplyBarsFrameSettings()
    if not barsFrame then return end
    local db = BIT.db or {}
    barsFrame:SetAlpha(db.alpha or 1.0)
    if barsTitle then
        if db.showTitle ~= false then
            local fs = (db.titleFontSize and db.titleFontSize > 0) and db.titleFontSize or 12
            BIT.Media:SetFont(barsTitle, fs)
            local align  = db.titleAlign or "CENTER"
            local titleY = -2 + (db.titleOffsetY or 0)
            barsTitle:ClearAllPoints()
            if align == "LEFT" then
                barsTitle:SetPoint("BOTTOMLEFT", barsFrame, "TOPLEFT", 4, titleY)
            elseif align == "RIGHT" then
                barsTitle:SetPoint("BOTTOMRIGHT", barsFrame, "TOPRIGHT", -4, titleY)
            else
                barsTitle:SetPoint("BOTTOM", barsFrame, "TOP", 0, titleY)
            end
            barsTitle:SetTextColor(db.titleColorR or 0, db.titleColorG or 0.867, db.titleColorB or 0.867)
            barsTitle:Show()
        else
            barsTitle:Hide()
        end
    end
end

local function CreateBarsFrame()
    if barsFrame then return end
    barsFrame = CreateFrame("Frame", "BliZziSyncCDBarsFrame", UIParent)
    barsFrame:SetSize(GROUP_BAR_W() + 4, 40)
    barsFrame:SetFrameStrata("MEDIUM")
    barsFrame:SetClampedToScreen(true)
    barsFrame:SetScale((BIT.db and BIT.db.frameScale or 100) / 100)

    barsTitle = barsFrame:CreateFontString(nil, "OVERLAY")
    BIT.Media:SetFont(barsTitle, 12)
    barsTitle:SetShadowOffset(BIT.db and BIT.db.shadowOffsetX or 0, BIT.db and BIT.db.shadowOffsetY or 0)
    barsTitle:SetText("Party CDs")

    barsFrame:SetMovable(true)
    barsFrame:EnableMouse(true)
    barsFrame:RegisterForDrag("LeftButton")
    barsFrame:SetScript("OnDragStart", function(self)
        if not (BIT.db and BIT.db.syncCdBarsLocked) then self:StartMoving() end
    end)
    barsFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if BIT.charDb then
            BIT.charDb.syncCdBarsPosX = self:GetLeft()
            BIT.charDb.syncCdBarsPosY = self:GetBottom()
        end
    end)

    if BIT.charDb and BIT.charDb.syncCdBarsPosX then
        barsFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            BIT.charDb.syncCdBarsPosX, BIT.charDb.syncCdBarsPosY)
    else
        barsFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end

    ApplyBarsFrameSettings()
    barsFrame:Hide()
end

-- Creates one fill-progress spell bar.  All visual settings read from BIT.db at creation time.
local function CreateSpellBar(parent, barW, barH, spellID, playerName, class, baseCd)
    local db       = BIT.db or {}
    local iconSide = (BIT.db and BIT.db.iconSide) or "LEFT"
    local iSize    = barH
    local fontSize = (db.nameFontSize and db.nameFontSize > 0) and db.nameFontSize or 11
    local nameOffX = db.nameOffsetX or 0
    local nameOffY = db.nameOffsetY or 0
    local timerOffX= db.cdOffsetX or 0
    local timerOffY= db.cdOffsetY or 0
    local showName = db.showName ~= false

    local fr, fg, fb = GetFillColor(class)
    local bgr, bgg, bgb = GetBgColor(class)

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(barW, barH)

    -- icon anchors depend on side
    local iconL, iconR, barL
    if iconSide == "RIGHT" then
        iconL = barW - iSize; iconR = 0; barL = 0
    else
        iconL = 0;            iconR = -barW + iSize; barL = iSize
    end

    -- spell icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    if iconSide == "RIGHT" then
        icon:SetPoint("TOPLEFT",     f, "TOPRIGHT",   -iSize, 0)
        icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,    0)
    else
        icon:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,     0)
        icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iSize, 0)
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local spellTex = C_Spell.GetSpellTexture(spellID)
    if spellTex then icon:SetTexture(spellTex) end
    f.icon = icon

    -- icon dark bg
    local iconBg = f:CreateTexture(nil, "BACKGROUND")
    if iconSide == "RIGHT" then
        iconBg:SetPoint("TOPLEFT",     f, "TOPRIGHT",   -iSize, 0)
        iconBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,    0)
    else
        iconBg:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,     0)
        iconBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iSize, 0)
    end
    iconBg:SetTexture(BIT.Media.flatTexture)
    iconBg:SetVertexColor(0.1, 0.1, 0.1, 1)

    -- bar solid bg
    local barBg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    if iconSide == "RIGHT" then
        barBg:SetPoint("TOPLEFT",     f, "TOPLEFT",   0,      0)
        barBg:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -iSize,  -barH)
    else
        barBg:SetPoint("TOPLEFT",     f, "TOPLEFT",    iSize, 0)
        barBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
    end
    barBg:SetTexture(BIT.Media.flatTexture)
    barBg:SetVertexColor(0, 0, 0, 1)

    -- bar tinted bg (class or custom)
    local barBgTex = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    if iconSide == "RIGHT" then
        barBgTex:SetPoint("TOPLEFT",     f, "TOPLEFT",   0,      0)
        barBgTex:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -iSize, -barH)
    else
        barBgTex:SetPoint("TOPLEFT",     f, "TOPLEFT",    iSize, 0)
        barBgTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
    end
    BIT.Media:SetBarTexture(barBgTex)
    barBgTex:SetVertexColor(bgr, bgg, bgb, 0.9)
    f.barBgTex = barBgTex

    -- fill StatusBar
    local sb = CreateFrame("StatusBar", nil, f)
    if iconSide == "RIGHT" then
        sb:SetPoint("TOPLEFT",     f, "TOPLEFT",   0,      0)
        sb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -iSize, -barH)
    else
        sb:SetPoint("TOPLEFT",     f, "TOPLEFT",    iSize, 0)
        sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
    end
    BIT.Media:SetBarTexture(sb)
    sb:SetStatusBarColor(fr, fg, fb, 0.85)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetFrameLevel(f:GetFrameLevel() + 1)
    if sb.NineSlice   then sb.NineSlice:SetAtlas("")  sb.NineSlice:Hide() end
    if sb.BorderFrame then sb.BorderFrame:Hide() end
    f.cdBar    = sb
    f._fillR   = fr; f._fillG = fg; f._fillB = fb
    -- Pool compatibility tags
    f._iconSide = iconSide
    f._barH     = barH
    f._barW     = barW

    -- content frame (text layer above StatusBar)
    local content = CreateFrame("Frame", nil, f)
    if iconSide == "RIGHT" then
        content:SetPoint("TOPLEFT",     f, "TOPLEFT",   0,      0)
        content:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -iSize, -barH)
    else
        content:SetPoint("TOPLEFT",     f, "TOPLEFT",    iSize, 0)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,    0)
    end
    content:SetFrameLevel(sb:GetFrameLevel() + 10)

    -- player name text
    local nm = content:CreateFontString(nil, "OVERLAY")
    BIT.Media:SetFont(nm, fontSize)
    nm:SetPoint("LEFT", content, "LEFT", 4 + nameOffX, nameOffY)
    nm:SetJustifyH("LEFT")
    nm:SetWordWrap(false)
    nm:SetTextColor(1, 1, 1)
    if showName then nm:SetText(BIT.GetDisplayName(playerName)) else nm:SetText("") end
    f.nameText = nm

    -- timer / ready text
    local timer = content:CreateFontString(nil, "OVERLAY")
    local timerFontSize = (db.readyFontSize and db.readyFontSize > 0) and db.readyFontSize or fontSize
    BIT.Media:SetFont(timer, timerFontSize)
    timer:SetPoint("RIGHT", content, "RIGHT", -4 + timerOffX, timerOffY)
    timer:SetJustifyH("RIGHT")
    timer:SetTextColor(1, 1, 1)
    f.timerText = timer

    f.playerName = playerName
    f.spellID    = spellID
    f.baseCd     = baseCd
    f._class     = class
    f._cdEnd     = 0
    f._lastSec   = nil

    -- Border overlays (above StatusBar, below text content)
    local borderOverlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
    borderOverlay:SetAllPoints(f)
    borderOverlay:SetFrameLevel(sb:GetFrameLevel() + 10)
    borderOverlay:EnableMouse(false)
    f.borderOverlay = borderOverlay

    local iconBorderOverlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
    if iconSide == "RIGHT" then
        iconBorderOverlay:SetPoint("TOPLEFT",     f, "TOPRIGHT",    -iSize - 1, 0)
        iconBorderOverlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,         0)
    else
        iconBorderOverlay:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,         0)
        iconBorderOverlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", iSize + 1, 0)
    end
    iconBorderOverlay:SetFrameLevel(sb:GetFrameLevel() + 11)
    iconBorderOverlay:EnableMouse(false)
    f.iconBorderOverlay = iconBorderOverlay

    BIT.UI:ApplyBorderToFrame(f)

    return f
end

-- Returns a bar frame: reuses a compatible one from barPool (no destroy/recreate)
-- or creates a fresh one.  Updates its content and resets state in both cases.
local function AcquireBar(barW, barH, spellID, playerName, class, baseCd)
    local iconSide = (BIT.db and BIT.db.iconSide) or "LEFT"

    -- Look for a pooled frame with matching layout (iconSide + size)
    for i = #barPool, 1, -1 do
        local b = barPool[i]
        if b._iconSide == iconSide and b._barH == barH and b._barW == barW then
            table.remove(barPool, i)
            -- Update identity
            b.spellID    = spellID
            b.playerName = playerName
            b._class     = class
            b.baseCd     = baseCd
            -- Reset per-tick caches so UpdateGroupBars re-evaluates immediately
            b._lastReady     = nil
            b._lastSec       = nil
            b._lastNameShown = nil
            -- Update icon texture
            local spellTex = C_Spell.GetSpellTexture(spellID)
            if spellTex then b.icon:SetTexture(spellTex) end
            -- Update fill / bg colours
            local fr, fg, fb    = GetFillColor(class)
            local bgr, bgg, bgb = GetBgColor(class)
            b._fillR = fr; b._fillG = fg; b._fillB = fb
            b.cdBar:SetStatusBarColor(fr, fg, fb, 0.85)
            if b.barBgTex then b.barBgTex:SetVertexColor(bgr, bgg, bgb, 0.9) end
            if b.nameText  then b.nameText:SetText(BIT.GetDisplayName(playerName)) end
            BIT.UI:ApplyBorderToFrame(b)
            return b
        end
    end

    -- No compatible frame in pool — create a new one
    return CreateSpellBar(barsFrame, barW, barH, spellID, playerName, class, baseCd)
end

-- Returns a bar to the pool (hidden, ready for reuse)
local function ReleaseBar(bar)
    bar:Hide()
    table.insert(barPool, bar)
end

local function RebuildGroupBars()
    if not barsFrame then return end
    if not BIT.db.showSyncCDs or GetEffectiveMode() ~= "BARS" then
        barsFrame:Hide(); return
    end
    if BIT.db.syncOnlyInGroup and not IsInGroup() then
        barsFrame:Hide(); return
    end

    ApplyBarsFrameSettings()

    -- Return all active bars to the pool (hidden, not destroyed)
    for _, b in ipairs(groupSpellBars) do ReleaseBar(b) end
    groupSpellBars = {}

    local entries = {}
    if BIT.myName and BIT.myClass and BIT.db.showOwnSyncCD ~= false then
        entries[#entries+1] = BIT.myName
    end
    for name in pairs(BIT.SyncCD.users or {}) do
        if name ~= BIT.myName then entries[#entries+1] = name end
    end

    local db       = BIT.db or {}
    local barW     = GROUP_BAR_W()
    local barH     = GROUP_BAR_H()
    local barGap   = GROUP_BAR_GAP()
    local growUp   = db.growUpward or false
    local fillMode = db.barFillMode or "DRAIN"
    local y        = growUp and 0 or -2

    -- sort entries by CD if requested
    local sortMode = db.sortMode or "NONE"
    if sortMode ~= "NONE" then
        table.sort(entries, function(a, b)
            local ra = math.max(0, (BIT.syncCdState[a] and next(BIT.syncCdState[a]) and 0) or 0)
            local rb = math.max(0, (BIT.syncCdState[b] and next(BIT.syncCdState[b]) and 0) or 0)
            return sortMode == "CD_ASC" and ra < rb or ra > rb
        end)
    end

    local totalBars = 0
    for _, name in ipairs(entries) do
        local spells = GetSpellsForPlayer(name)
        for _, s in ipairs(spells) do
            if not (BIT.db.syncCdDisabled and BIT.db.syncCdDisabled[s.id]) then
                totalBars = totalBars + 1
            end
        end
    end

    local now = GetTime()
    local idx = 0
    for _, name in ipairs(entries) do
        local class  = GetPlayerClass(name)
        local spells = GetSpellsForPlayer(name)
        for _, s in ipairs(spells) do
            if not (BIT.db.syncCdDisabled and BIT.db.syncCdDisabled[s.id]) then
                local bar = AcquireBar(barW, barH, s.id, name, class, s.cd)
                bar:ClearAllPoints()
                if growUp then
                    bar:SetPoint("BOTTOMLEFT", barsFrame, "BOTTOMLEFT", 2, idx * (barH + barGap) + 2)
                else
                    bar:SetPoint("TOPLEFT", barsFrame, "TOPLEFT", 2, y)
                    y = y - (barH + barGap)
                end

                -- Set the correct CD state immediately so the bar never flashes empty
                local cdState = BIT.syncCdState and BIT.syncCdState[name]
                local cdEnd   = (cdState and cdState[s.id]) or 0
                if cdEnd > now then
                    local rem = cdEnd - now
                    bar.cdBar:SetMinMaxValues(0, s.cd)
                    bar.cdBar:SetValue(fillMode == "FILL" and (s.cd - rem) or rem)
                    bar._lastReady = false
                else
                    bar.cdBar:SetMinMaxValues(0, 1)
                    bar.cdBar:SetValue(1)
                    -- _lastReady = nil → UpdateGroupBars will apply ready styling on first tick
                end

                bar:Show()
                groupSpellBars[#groupSpellBars+1] = bar
                idx = idx + 1
            end
        end
    end

    local totalH = totalBars > 0 and (totalBars * (barH + barGap) - barGap + 4) or 40
    barsFrame:SetSize(barW + 4, totalH)
    barsFrame:Show()
end

local function UpdateGroupBars()
    if not barsFrame or not barsFrame:IsShown() then return end
    local now       = GetTime()
    local db        = BIT.db or {}
    local fillMode  = db.barFillMode or "DRAIN"
    local showReady = db.showReady ~= false
    local showName  = db.showName ~= false
    local showTitle = db.showTitle ~= false
    local rr = db.readyColorR or 0.2
    local rg = db.readyColorG or 1.0
    local rb = db.readyColorB or 0.2

    -- Title show/hide dynamically
    if barsTitle then
        if showTitle then barsTitle:Show() else barsTitle:Hide() end
    end

    for _, bar in ipairs(groupSpellBars) do
        if bar:IsShown() then
            -- Name text: only set when state changes to avoid flicker
            if bar.nameText then
                local wantName = showName and BIT.GetDisplayName(bar.playerName) or ""
                if bar._lastNameShown ~= wantName then
                    bar._lastNameShown = wantName
                    bar.nameText:SetText(wantName)
                end
            end

            local state  = BIT.syncCdState[bar.playerName]
            local cdEnd  = (state and state[bar.spellID]) or 0
            local baseCd = bar.baseCd or 30

            if cdEnd > now then
                -- On cooldown: drain or fill bar.
                -- SetMinMaxValues and SetStatusBarColor are cached — only called once
                -- when first entering CD state (from ready/initial) to avoid marking the
                -- bar texture dirty every tick, which causes visible flickering.
                local rem = cdEnd - now
                if bar._lastReady ~= false then
                    -- just transitioned into CD state: set min/max and colour once
                    bar.cdBar:SetMinMaxValues(0, baseCd)
                    bar.cdBar:SetStatusBarColor(bar._fillR, bar._fillG, bar._fillB, 0.85)
                end
                bar.cdBar:SetValue(fillMode == "FILL" and (baseCd - rem) or rem)

                local sec = math.floor(rem + 0.5)
                if bar._lastSec ~= sec then
                    bar._lastSec = sec
                    local fmt = (BIT.db and BIT.db.syncCdTimeFormat) or "SECONDS"
                    if fmt == "MMSS" and sec >= 60 then
                        bar.timerText:SetText(string.format("%d:%02d", math.floor(sec/60), sec%60))
                    else
                        bar.timerText:SetText(tostring(sec))
                    end
                    bar.timerText:SetTextColor(1, 1, 1)
                end
                bar.timerText:Show()
                bar._lastReady = false
            else
                -- Ready: only update once on transition to avoid per-tick re-renders.
                if not bar._lastReady then
                    bar._lastReady = true
                    bar._lastSec   = nil
                    bar.cdBar:SetMinMaxValues(0, 1)
                    bar.cdBar:SetValue(1)
                    bar.cdBar:SetStatusBarColor(bar._fillR, bar._fillG, bar._fillB, 0.85)
                    bar.timerText:SetTextColor(rr, rg, rb)
                    bar.timerText:SetText(BIT.L and BIT.L["READY"] or "Ready")
                end
                -- show/hide checked every tick so the toggle responds immediately
                if showReady then bar.timerText:Show() else bar.timerText:Hide() end
            end
        end
    end
end

-- Called by settings changes that don't need a full rebuild (title, opacity, lock)
function BIT.SyncCD:ApplyBarsSettings()
    ApplyBarsFrameSettings()
end

-- Center-preserving scale change — mirrors the Interrupt Tracker's Frame Scale logic.
function BIT.SyncCD:ScaleFrame(newPct)
    if not barsFrame then return end
    local newS = newPct / 100
    local oldS = barsFrame:GetScale()
    local cx, cy = barsFrame:GetCenter()
    if cx then
        local screenCX = cx * oldS
        local screenCY = cy * oldS
        barsFrame:SetScale(newS)
        barsFrame:ClearAllPoints()
        barsFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            screenCX / newS, screenCY / newS)
        if BIT.charDb then
            BIT.charDb.syncCdBarsPosX = barsFrame:GetLeft()
            BIT.charDb.syncCdBarsPosY = barsFrame:GetBottom()
        end
    else
        barsFrame:SetScale(newS)
    end
end

-- Lightweight in-place color update — no frame destroy/recreate, no flicker.
-- Called when color or class-color-mode settings change.
function BIT.SyncCD:UpdateColors()
    if not barsFrame or not barsFrame:IsShown() then return end
    for _, bar in ipairs(groupSpellBars) do
        local fr, fg, fb   = GetFillColor(bar._class)
        local bgr, bgg, bgb = GetBgColor(bar._class)
        bar._fillR = fr; bar._fillG = fg; bar._fillB = fb
        bar.cdBar:SetStatusBarColor(fr, fg, fb, 0.85)
        if bar.barBgTex then bar.barBgTex:SetVertexColor(bgr, bgg, bgb, 0.9) end
        bar._lastReady = nil  -- force ready-color text to re-evaluate on next tick
    end
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
local _specRetryTimer = nil
local function DoRebuild()
    _rebuildTimer = nil
    ScanPartyMembers()
    local mode = GetEffectiveMode()
    _cachedMode = mode
    if mode == "OFF" then
        HideAllAttached()
        if syncFrame then syncFrame:Hide() end
        if barsFrame then barsFrame:Hide() end
    elseif mode == "ATTACH" then
        if syncFrame  then syncFrame:Hide()  end
        if barsFrame  then barsFrame:Hide()  end
        RebuildAttached()
    elseif mode == "BARS" then
        HideAllAttached()
        if syncFrame then syncFrame:Hide() end
        RebuildGroupBars()
    else  -- WINDOW
        HideAllAttached()
        if barsFrame then barsFrame:Hide() end
        RebuildWindow()
    end
    BIT.SyncCD:RefreshCharges()

    -- If any party member still has no spec detected, schedule a retry.
    -- Tooltip/inspect may not be ready immediately after group join.
    if IsInGroup() then
        local missingSpec = false
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitIsPlayer(u) then
                local n = SafeUnitName(u)
                if n then
                    local sid = GetSpecForPlayer(n)
                    if not sid or sid == 0 then
                        missingSpec = true
                        break
                    end
                end
            end
        end
        if missingSpec then
            if _specRetryTimer then _specRetryTimer:Cancel() end
            _specRetryTimer = C_Timer.NewTimer(1.5, function()
                _specRetryTimer = nil
                if BIT.SyncCD and BIT.SyncCD.Rebuild then
                    BIT.SyncCD:Rebuild()
                end
            end)
        end
    end
end

-- Debounced rebuild: multiple rapid calls (e.g. INSPECT_READY for each raid member)
-- collapse into a single rebuild after 50 ms, eliminating flicker storms.
function BIT.SyncCD:Rebuild()
    if _rebuildTimer then _rebuildTimer:Cancel() end
    _rebuildTimer = C_Timer.NewTimer(0.05, DoRebuild)
end

-- Called when the local player's talents change (PLAYER_TALENT_UPDATE / TRAIT_CONFIG_UPDATED).
-- Scans own player's active talents via C_Traits and caches the result in
-- BIT.SyncCD.users[myName].knownSpells — same format as party member inspect data.
-- Must be called at load time and on every PLAYER_TALENT_UPDATE / TRAIT_CONFIG_UPDATED.
function BIT.SyncCD:ScanOwnTalents()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return end
    local ok0, cid = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok0 or not cid then return end
    local ok1, cfg = pcall(C_Traits.GetConfigInfo, cid)
    if not ok1 or not cfg or not cfg.treeIDs or #cfg.treeIDs == 0 then return end

    -- Scan ALL trees: class tree, spec tree, hero talent tree, etc.
    -- Previously only treeIDs[1] was scanned, missing talents in other trees
    -- (e.g. Pitch Black for Vengeance DH lives in a different tree than index 1).
    local knownSpells     = {}   -- spell IDs from ACTIVE talent nodes
    local allTalentSpells = {}   -- spell IDs from ALL talent nodes (active + inactive)
    for _, treeID in ipairs(cfg.treeIDs) do
        local ok2, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if ok2 and nodes then
            for _, nodeID in ipairs(nodes) do
                local ok3, node = pcall(C_Traits.GetNodeInfo, cid, nodeID)
                if ok3 and node then
                    -- Collect ALL entries (active + unselected choices)
                    if node.entryIDs then
                        for _, eid in ipairs(node.entryIDs) do
                            local okE, eInfo = pcall(C_Traits.GetEntryInfo, cid, eid)
                            if okE and eInfo and eInfo.definitionID then
                                local okD, dInfo = pcall(C_Traits.GetDefinitionInfo, eInfo.definitionID)
                                if okD and dInfo and dInfo.spellID then
                                    local okF, sidStr = pcall(string.format, "%.0f", dInfo.spellID)
                                    local sid = okF and tonumber(sidStr)
                                    if sid then allTalentSpells[sid] = true end
                                end
                            end
                        end
                    end
                    -- Collect ACTIVE entry spells
                    if node.activeEntry and node.activeRank and node.activeRank > 0 then
                        local ok4, entry = pcall(C_Traits.GetEntryInfo, cid, node.activeEntry.entryID)
                        if ok4 and entry and entry.definitionID then
                            local ok5, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
                            if ok5 and def and def.spellID then
                                -- Detaint spellID before using as table key (Midnight security).
                                local okF, sidStr = pcall(string.format, "%.0f", def.spellID)
                                local sid = okF and tonumber(sidStr)
                                if sid then knownSpells[sid] = true end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Name-match: map talent node spellIDs → SYNC_SPELLS ability IDs
    -- and build allTalentSpells for base-ability vs unselected-talent distinction.
    if next(knownSpells) and BIT.SyncCD.spellLookupByName then
        local talentNameSet = {}
        for talentID in pairs(knownSpells) do
            local okN, tname = pcall(C_Spell.GetSpellName, talentID)
            if okN and tname and tname ~= "" then
                talentNameSet[tname] = true
                local syncEntry = BIT.SyncCD.spellLookupByName[tname]
                if syncEntry then
                    knownSpells[syncEntry.id] = true
                end
            end
        end
        local mySpec = GetSpecialization()
        local mySpecID = mySpec and select(1, GetSpecializationInfo(mySpec))
        if mySpecID and BIT.SYNC_SPELLS[mySpecID] then
            for _, s in ipairs(BIT.SYNC_SPELLS[mySpecID]) do
                local okN, sname = pcall(C_Spell.GetSpellName, s.id)
                if okN and sname and talentNameSet[sname] then
                    allTalentSpells[s.id] = true
                end
            end
        end
    end

    if not BIT.SyncCD.users then BIT.SyncCD.users = {} end
    local me = BIT.myName
    if me then
        if not BIT.SyncCD.users[me] then BIT.SyncCD.users[me] = {} end
        BIT.SyncCD.users[me].knownSpells     = next(knownSpells) and knownSpells or nil
        BIT.SyncCD.users[me].allTalentSpells = next(allTalentSpells) and allTalentSpells or nil
        BIT.SyncCD.users[me]._hasAddon       = true
    end
end

-- Stable fingerprint of a spell-id → bool set (sorted, comma-joined).
-- Used by OnTalentChanged to detect real changes vs. noise events.
local function _spellSetFingerprint(t)
    if not t then return "" end
    local ids = {}
    for id in pairs(t) do ids[#ids+1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- Bumps _ownTalentVer so RebuildWindowRow sees a change and recreates icons from the spellbook.
--
-- SPELLS_CHANGED fires for many reasons (glyph swap, shapeshift, macro toggle,
-- sometimes transiently after casts). Previously we blindly bumped the version
-- and forced a full icon teardown/rebuild every time — visible as all-icon
-- flicker on the screen. Now we only bump + rebuild when the active talent set
-- or the full talent list actually changed.
function BIT.SyncCD:OnTalentChanged()
    local me = BIT.myName
    local prevKnown, prevAll = "", ""
    if me and self.users and self.users[me] then
        prevKnown = _spellSetFingerprint(self.users[me].knownSpells)
        prevAll   = _spellSetFingerprint(self.users[me].allTalentSpells)
    end
    self:ScanOwnTalents()
    local nowKnown, nowAll = "", ""
    if me and self.users and self.users[me] then
        nowKnown = _spellSetFingerprint(self.users[me].knownSpells)
        nowAll   = _spellSetFingerprint(self.users[me].allTalentSpells)
    end
    if prevKnown ~= nowKnown or prevAll ~= nowAll then
        _ownTalentVer = _ownTalentVer + 1
        BIT.SyncCD:Rebuild()
    end
end

-- Converts a tainted secret number to a clean Lua number.
-- string.format produces a clean string even from tainted input;
-- tonumber converts it back without taint.
local function DetaintNumber(n)
    local ok, s = pcall(string.format, "%.0f", n)
    return ok and tonumber(s) or nil
end

-- Tracks the last known charge count per spell so we can detect consumption.
-- Syncs own player's charge state from C_Spell.GetSpellCharges → syncCdState.
-- Badge display is now handled by UpdateIcon for ALL players (own + party).
-- Called after rebuild, on SPELL_UPDATE_CHARGES, and after casting a charge-based spell.
function BIT.SyncCD:RefreshCharges()
    local function syncChargeState(icons)
        for sid, ico in pairs(icons) do
            if ico._maxCharges and ico._maxCharges > 1 then
                local queryID = ico.spellID or sid

                local ok, result = pcall(C_Spell.GetSpellCharges, queryID)
                if ok and result and type(result) == "table" then
                    local charges    = DetaintNumber(result.currentCharges)
                    local maxCharges = DetaintNumber(result.maxCharges)
                    -- Use higher precision for timestamps (DetaintNumber rounds to integer)
                    local okS, ss = pcall(string.format, "%.6f", result.cooldownStartTime)
                    local okD, sd = pcall(string.format, "%.6f", result.cooldownDuration)
                    local cdStart = okS and tonumber(ss) or nil
                    local cdDur   = okD and tonumber(sd) or nil

                    if charges and maxCharges and maxCharges > 1 then
                        ico._maxCharges = maxCharges

                        if not BIT.syncCdState then BIT.syncCdState = {} end
                        if not BIT.syncCdState[BIT.myName] then
                            BIT.syncCdState[BIT.myName] = {}
                        end
                        local state = BIT.syncCdState[BIT.myName]

                        -- Directly compute cdEnd from cooldownStartTime + cooldownDuration
                        -- This is authoritative and works in combat (taint-safe via DetaintNumber).
                        if charges >= maxCharges then
                            state[sid] = 0  -- all charges available
                        elseif cdStart and cdDur and cdStart > 0 and cdDur > 0 then
                            state[sid] = cdStart + cdDur  -- next charge recharge time
                        end
                    end
                end
            end
        end
    end

    local row = syncRows[BIT.myName]
    if row then syncChargeState(row.icons) end
    for unit, bar in pairs(attachedBars) do
        local n = (unit == "player") and BIT.myName or SafeUnitName(unit)
        if n == BIT.myName then syncChargeState(bar.icons) end
    end
end

-- Lightweight update of chargeBadge style (size, anchor, offset) on existing icons
-- without full Rebuild.  Called from settings sliders for instant feedback.
function BIT.SyncCD:UpdateChargeBadgeStyle()
    local chSize   = (BIT.db and BIT.db.syncCdChargeSize) or 13
    local chAnchor = (BIT.db and BIT.db.syncCdChargeAnchor) or "BOTTOMRIGHT"
    local chOffX   = (BIT.db and BIT.db.syncCdChargeOffX) or -1
    local chOffY   = (BIT.db and BIT.db.syncCdChargeOffY) or 1
    local function applyStyle(icons)
        for _, ico in pairs(icons) do
            if ico.chargeBadge then
                BIT.Media:SetFont(ico.chargeBadge, chSize)
                ico.chargeBadge:ClearAllPoints()
                ico.chargeBadge:SetPoint(chAnchor, ico, chAnchor, chOffX, chOffY)
            end
        end
    end
    for _, row in pairs(syncRows) do applyStyle(row.icons) end
    for _, bar in pairs(attachedBars) do applyStyle(bar.icons) end
end

function BIT.SyncCD:UpdateDisplay()
    if not BIT.db.showSyncCDs then return end
    local mode = GetEffectiveMode()
    -- If the group type changed (party ↔ raid), rebuild immediately instead of
    -- drawing the wrong display mode until the next GROUP_ROSTER_UPDATE fires.
    if _cachedMode and mode ~= _cachedMode then
        BIT.SyncCD:Rebuild()
        return
    end
    _cachedMode = mode
    if mode == "ATTACH" then
        UpdateAttached()
    elseif mode == "BARS" then
        UpdateGroupBars()
    else
        UpdateWindow()
    end
end

local function ApplySpellUsed(icons, spellID, duration, playerName)
    local ico = icons[spellID]
    if not ico then
        local baseID = replacedByToBase[spellID]
        if baseID then ico = icons[baseID] end
    end
    if ico then
        local iconSrc = SPELL_ICON_OVERRIDE[spellID] or spellID
        local tex = C_Spell.GetSpellTexture(iconSrc)
        if tex then ico.tex:SetTexture(tex) end
        ico.spellID  = spellID   -- keep tooltip in sync with the actual cast spell
        ico._cd = duration

        local maxCh = ico._maxCharges or 0
        local pName = playerName or ico._playerName
        if maxCh > 1 and pName then
            -- Charge-based: let UpdateIcon handle swipe/alpha via FIFO tracker
            -- Just ensure the CD timer starts for the next recharge
            local ct = _chargeTracker[pName] and _chargeTracker[pName][spellID]
            if ct then
                local now2 = GetTime()
                local nextR = ct.fifo:nextRechargeAt()
                if nextR and nextR > now2 then
                    ico.cd:SetCooldown(nextR - duration, duration)
                    ico._swipeCdEnd = nextR
                else
                    ico.cd:SetCooldown(now2, duration)
                    ico._swipeCdEnd = now2 + duration
                end
                local avail = ct.fifo:availableCharges(now2)
                ico.cd:SetDrawSwipe(avail == 0)
                ico.tex:SetAlpha(avail == 0 and 0.3 or 0.65)
            else
                local now2 = GetTime()
                ico.cd:SetCooldown(now2, duration)
                ico._swipeCdEnd = now2 + duration
                ico.tex:SetAlpha(0.3)
            end
        else
            local now2 = GetTime()
            ico.cd:SetCooldown(now2, duration)
            ico._swipeCdEnd = now2 + duration
            ico.tex:SetAlpha(0.3)
        end
        ico._cdRunning = true
    end
end

function BIT.SyncCD:OnSpellUsed(name, spellID, duration, fullCd)
    if not BIT.syncCdState[name] then BIT.syncCdState[name] = {} end

    -- ── Charge tracking (FIFO) ────────────────────────────────────────
    -- Look up the spell entry to find maxCharges (with talent modifications).
    local spellEntry = _syncSpellLookup[spellID]
    local knownTalents = GetKnownTalents(name)
    local maxCharges = (spellEntry and spellEntry.charges) or 0
    -- Also check base spell if this is a replacedBy variant
    if (not maxCharges or maxCharges < 2) then
        local baseID = replacedByToBase and replacedByToBase[spellID]
        if baseID then
            local baseEntry = _syncSpellLookup[baseID]
            if baseEntry then
                maxCharges = baseEntry.charges or maxCharges
                -- Check base entry's talentCharges too
                if baseEntry.talentCharges then
                    for talentID, chargeCount in pairs(baseEntry.talentCharges) do
                        if knownTalents[talentID] then
                            maxCharges = chargeCount
                        end
                    end
                end
            end
        end
    end
    -- Apply talent-based charge modifications from the direct entry
    if spellEntry and spellEntry.talentCharges then
        for talentID, chargeCount in pairs(spellEntry.talentCharges) do
            if knownTalents[talentID] then
                maxCharges = chargeCount
            end
        end
    end

    if maxCharges and maxCharges > 1 then
        local ct = GetChargeTracker(name, spellID, maxCharges, duration)
        -- WoW charges recharge SEQUENTIALLY: charge 2 starts only after charge 1 finishes,
        -- and then takes the FULL cooldown (not just the remaining CD from buff expiry).
        -- When head() > now: a previous charge is still recharging → C2 queues behind it
        --   using fullCd so the timing matches the real in-game recharge.
        -- When head() <= now: no charge is pending → starts now, takes remaining CD.
        -- chargeOffset corrects empirical timing discrepancies (e.g. server/talent rounding).
        local chargeOffset = (spellEntry and spellEntry.chargeOffset) or 0
        local now = GetTime()
        local head = ct.fifo:head()
        local availableAt
        if head > now then
            availableAt = head + (fullCd or duration) + chargeOffset
        else
            availableAt = now + duration + chargeOffset
        end
        ct.fifo:push(availableAt)
        -- For charge-based spells, the "CD end" shown should be when the NEXT
        -- charge comes back (earliest future recharge), not when all charges return.
        local nextRecharge = ct.fifo:nextRechargeAt()
        BIT.syncCdState[name][spellID] = nextRecharge or (now + duration)
        if BIT.devLogMode then
            local avail = ct.fifo:availableCharges(now)
            -- Dump every FIFO slot's remaining time for precise timing diagnostics
            local fifoStr = ""
            local buf   = ct.fifo._buf
            local fsize = ct.fifo._size
            if buf and fsize then
                for i = 1, fsize do
                    if buf[i] then
                        local rem = buf[i] - now
                        fifoStr = fifoStr .. string.format("[%d]=%.1fs ", i, rem)
                    end
                end
            end
            local seqStr = head > now and ("seq head+" .. string.format("%.0f", (fullCd or duration) + chargeOffset)) or ("now+rem+" .. chargeOffset)
            BIT.DevLog("[CHARGE] " .. tostring(name)
                  .. " spell=" .. tostring(spellID)
                  .. " charges=" .. avail .. "/" .. maxCharges
                  .. " (" .. seqStr .. ")"
                  .. " rem=" .. string.format("%.1f", duration) .. "s"
                  .. " fullCd=" .. tostring(fullCd or "?")
                  .. " nextRecharge=" .. string.format("%.1f", (nextRecharge or 0) - now) .. "s"
                  .. " fifo=[" .. fifoStr:gsub("%s+$","") .. "]")
        end
    else
        BIT.syncCdState[name][spellID] = GetTime() + duration
    end
    if BIT.devLogMode then
        local hasRow = syncRows[name] ~= nil
        local hasAtt = false
        for _, bar in pairs(attachedBars) do
            local n = SafeUnitName(bar.frame and bar.frame:GetParent() and bar.frame:GetParent().unit or "")
            if not n then
                for u, b in pairs(attachedBars) do
                    local bn = (u == "player") and BIT.myName or SafeUnitName(u)
                    if bn == name then hasAtt = true; break end
                end
                break
            end
        end
        if not hasAtt then
            for u, b in pairs(attachedBars) do
                local bn = (u == "player") and BIT.myName or SafeUnitName(u)
                if bn == name then hasAtt = true; break end
            end
        end
        local attIco = false
        for u, bar in pairs(attachedBars) do
            local bn = (u == "player") and BIT.myName or SafeUnitName(u)
            if bn == name and bar.icons and bar.icons[spellID] then attIco = true; break end
        end
        BIT.DevLog("[SyncCD] OnSpellUsed: name=" .. tostring(name)
              .. " spellID=" .. tostring(spellID) .. " dur=" .. string.format("%.0f", duration)
              .. " row=" .. tostring(hasRow) .. " attBar=" .. tostring(hasAtt) .. " attIco=" .. tostring(attIco))
    end
    -- If a party member casts a spell not yet in their knownSpells, their talents
    -- changed → invalidate the inspect cache so a fresh scan triggers on next inspect.
    if name ~= BIT.myName then
        local userEntry = BIT.SyncCD.users and BIT.SyncCD.users[name]
        local ks = userEntry and userEntry.knownSpells
        if ks and not ks[spellID] then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) and SafeUnitName(u) == name then
                    BIT.SyncCD.InvalidateInspect(u)
                    break
                end
            end
        end
    end

    -- When a replacedBy spell fires, also write the base-spell key
    -- so UpdateWindow/UpdateAttached can find it via the row icon keyed by the base ID.
    local baseID = replacedByToBase[spellID]
    if baseID then
        BIT.syncCdState[name][baseID] = BIT.syncCdState[name][spellID]
        -- Remember permanently that this player has the replacement talent,
        -- so future rebuilds show the correct icon without needing another inspect.
        if name ~= BIT.myName then
            if not BIT.SyncCD.users then BIT.SyncCD.users = {} end
            if not BIT.SyncCD.users[name] then BIT.SyncCD.users[name] = {} end
            local u = BIT.SyncCD.users[name]
            if not u.knownReplacements then u.knownReplacements = {} end
            if u.knownReplacements[baseID] ~= spellID then
                u.knownReplacements[baseID] = spellID
                -- Invalidate this player's row so the next Rebuild swaps the icon
                local row = syncRows[name]
                if row then row._lastSpec = nil end
                BIT.SyncCD:Rebuild()
            end
        end
    end

    -- ── BoP / Spellwarding shared CD ─────────────────────────────────
    -- Using one starts the cooldown for the other. They share a CD slot.
    local BOP_SPELLWARD = { [1022] = 204018, [204018] = 1022 }
    local otherID = BOP_SPELLWARD[spellID]
    if otherID then
        if not BIT.syncCdState[name][otherID] or BIT.syncCdState[name][otherID] <= GetTime() then
            BIT.syncCdState[name][otherID] = BIT.syncCdState[name][spellID]
            if BIT.debugMode then
                print("|cff0091edBIT|r |cFFAAAAAA[SHARED-CD]|r " .. tostring(name)
                      .. " BoP/Spellwarding shared CD → " .. tostring(otherID))
            end
        end
    end

    -- Track buff active end time for glow
    local buffDur = spellEntry and spellEntry.buffDur
    if not buffDur and baseID then
        local baseEntry = _syncSpellLookup[baseID]
        buffDur = baseEntry and baseEntry.buffDur
    end
    if buffDur and buffDur > 0 then
        if not _buffActiveEnd[name] then _buffActiveEnd[name] = {} end
        _buffActiveEnd[name][spellID] = GetTime() + buffDur
        if baseID then _buffActiveEnd[name][baseID] = GetTime() + buffDur end
    end

    -- update window row immediately
    local row = syncRows[name]
    if row then ApplySpellUsed(row.icons, spellID, duration, name) end

    -- update group bars immediately (find matching spell bar by name+spellID)
    for _, bar in ipairs(groupSpellBars) do
        if bar.playerName == name and (bar.spellID == spellID or (replacedByToBase[spellID] and bar.spellID == replacedByToBase[spellID])) then
            bar._cdEnd   = GetTime() + duration
            bar._lastSec = nil
        end
    end

    -- update attached bar icon immediately
    for unit, bar in pairs(attachedBars) do
        local n = (unit == "player") and BIT.myName or SafeUnitName(unit)
        if n == name then ApplySpellUsed(bar.icons, spellID, duration, name) end
    end

end

------------------------------------------------------------
-- Local party-cast detection (fallback for Timed M+ where addon messages
-- are blocked with ret=11).  Called from the CLEU handler above
-- (SPELL_CAST_SUCCESS for friendly players) and as fallback from anywhere.
------------------------------------------------------------
function BIT.SyncCD:OnPartySpellCast(name, spellID)
    if not (BIT.db and BIT.db.showSyncCDs) then return end

    -- spellID from UNIT_SPELLCAST_SUCCEEDED on party members is tainted
    -- (secret value) — ANY operation on it (table index, tostring, compare)
    -- can throw "table index is secret". Split lookups into separate pcalls
    -- so the string fallback runs even if the numeric lookup throws.
    local entry, cleanID
    local ok1, e1 = pcall(function() return _syncSpellLookup[spellID] end)
    if ok1 and e1 then
        entry = e1
    else
        local ok2, s = pcall(tostring, spellID)
        if ok2 and s then
            local ok3, e3 = pcall(function() return _syncSpellLookupStr[s] end)
            if ok3 and e3 then entry = e3 end
        end
    end
    if entry then cleanID = entry.id end
    if not entry or not cleanID then return end

    -- Charge spells are tracked exclusively by AURA-MATCH for accuracy.
    -- Local detection would double-count with the aura path.
    if (entry.charges or 0) > 1 then return end

    -- Feign Death (5384) for own player: the buff can be cancelled early
    -- (damage, manual cancel) and the 30s CD only starts when the buff ENDS,
    -- NOT when the spell is cast. At cast time we only set the glow; no CD.
    -- Buff-end is detected by two independent paths (whichever fires first
    -- wins; the later one is guarded by _buffActiveEnd=0):
    --   • UNIT_AURA: observes the FD aura going from present → absent
    --   • UNIT_FLAGS: observes UnitIsFeignDeath flipping true → false
    -- UNIT_AURA is the more reliable signal (catches early cancels before
    -- the FD flag ever flips, and manual /cancelaura).
    if cleanID == 5384 and name == BIT.myName then
        local now = GetTime()
        if not _buffActiveEnd[name] then _buffActiveEnd[name] = {} end
        _buffActiveEnd[name][5384] = now + (entry.buffDur or 360)
        RefreshBuffHighlights(name)
        if BIT.devLogMode then
            BIT.DevLog("[FD] self cast -> glow on, CD deferred until buff end")
        end
        return
    end

    -- Compute effective CD: apply talent reductions for known talents.
    -- knownTalents may be empty for non-addon players; in that case we use base CD.
    local knownTalents = GetKnownTalents(name)
    local effectiveCd  = entry.cd
    if entry.talentMods then
        for talentID, reduction in pairs(entry.talentMods) do
            if knownTalents[talentID] then
                effectiveCd = math.max(1, effectiveCd - reduction)
            end
        end
    end

    -- Skip if a CD is already running (aura detection may have fired first).
    -- Use cleanID (un-tainted) for all state table accesses.
    local state     = BIT.syncCdState[name]
    local now       = GetTime()
    local cdRunning = state and state[cleanID] and state[cleanID] > now
    if not cdRunning then
        local baseID = replacedByToBase[cleanID]
        if baseID then
            cdRunning = state and state[baseID] and state[baseID] > now
        end
    end
    if cdRunning then return end

    if BIT.devLogMode then
        BIT.DevLog("[SyncCD-LOCAL] party cast: "
              .. tostring(name) .. " spell=" .. tostring(entry.name or cleanID)
              .. " cd=" .. tostring(effectiveCd))
    end

    self:OnSpellUsed(name, cleanID, effectiveCd)
end

-- Name-based variant: called from UNIT_SPELLCAST_SENT which provides untainted
-- spell names. Bypasses the tainted spellID problem on party members.
function BIT.SyncCD:OnPartySpellCastByName(name, spellName)
    if not (BIT.db and BIT.db.showSyncCDs) then return end
    -- Reject tainted values before any table index operation.
    if not spellName or issecretvalue(spellName) then return end
    local lookup = BIT.SyncCD.spellLookupByName
    if not lookup then return end
    local entry = lookup[spellName]
    if not entry then return end

    -- Charge spells are tracked exclusively by AURA-MATCH; skip local detection.
    if (entry.charges or 0) > 1 then return end

    local cleanID = entry.id
    local knownTalents = GetKnownTalents(name)
    local effectiveCd  = entry.cd
    if entry.talentMods then
        for talentID, reduction in pairs(entry.talentMods) do
            if knownTalents[talentID] then
                effectiveCd = math.max(1, effectiveCd - reduction)
            end
        end
    end

    local state     = BIT.syncCdState[name]
    local now       = GetTime()
    local cdRunning = state and state[cleanID] and state[cleanID] > now
    if not cdRunning then
        local baseID = replacedByToBase[cleanID]
        if baseID then
            cdRunning = state and state[baseID] and state[baseID] > now
        end
    end
    if cdRunning then return end

    if BIT.debugMode then
        print("|cff0091edBIT|r |cFFAAAAAA[SyncCD-SENT]|r party cast by name: "
              .. tostring(name) .. " spell=" .. tostring(spellName)
              .. " id=" .. tostring(cleanID) .. " cd=" .. tostring(effectiveCd))
    end

    self:OnSpellUsed(name, cleanID, effectiveCd)
end

------------------------------------------------------------
-- CD Reducer (e.g. Impenetrable Wall: Shield Slam → -6s on Shield Wall)
------------------------------------------------------------

-- Reduces the tracked remaining CD of `spellID` for `name` by `reduction` seconds
-- and immediately updates all visual representations.
function BIT.SyncCD:OnCDReduced(name, spellID, reduction)
    local state = BIT.syncCdState[name]
    if not state or not state[spellID] then return end
    local endTime = state[spellID]
    if endTime <= GetTime() then return end  -- already off CD, nothing to reduce

    local newEnd = math.max(GetTime() + 0.5, endTime - reduction)
    state[spellID] = newEnd

    -- Helper: re-sync a single CooldownFrame icon without restarting from zero.
    -- We preserve the original total duration so the pie-chart proportions stay correct.
    local function updateIco(ico)
        if not ico or not ico._cdRunning then return end
        local origTotal = ico._cd   -- total CD set at cast time
        local elapsed   = origTotal - (endTime - GetTime())   -- how far we were
        local newTotal  = math.max(0.5, origTotal - reduction)
        ico._cd = newTotal
        ico.cd:SetCooldown(GetTime() - elapsed, newTotal)
    end

    -- Window row icon
    local row = syncRows[name]
    if row then updateIco(row.icons[spellID]) end

    -- Attached bar icon
    for unit, bar in pairs(attachedBars) do
        local n = (unit == "player") and BIT.myName or SafeUnitName(unit)
        if n == name then updateIco(bar.icons[spellID]) end
    end

    -- Group spell bars
    for _, bar in ipairs(groupSpellBars) do
        if bar.playerName == name and bar.spellID == spellID then
            bar._cdEnd   = newEnd
            bar._lastSec = nil
        end
    end
end

-- Called from Core.lua on every own UNIT_SPELLCAST_SUCCEEDED.
-- Checks whether the cast spell triggers a CD reduction on another spell.
function BIT.SyncCD:CheckCDReducer(spellID)
    local reducer = CD_REDUCER_SPELLS[spellID]
    if not reducer then return end
    local okT, hasT = pcall(IsSpellKnown, reducer.talent)
    if not (okT and hasT) then return end
    self:OnCDReduced(BIT.myName, reducer.targetSpell, reducer.reduction)
    -- Announce the reduction to party members so their trackers stay in sync
    if BIT.Net and BIT.Net.AnnounceSync then
        -- Negative duration = CD reduction signal; party must call OnCDReduced themselves.
        -- We piggy-back on the existing SYNCCD prefix with a special negative value.
        -- (Receivers check: if dur < 0 → CDR)
        BIT.Net:AnnounceSync(reducer.targetSpell, -reducer.reduction)
    end
end

-- Restore syncCdState for own player's spells after a reload/login.
-- Reads remaining cooldown from C_Spell.GetSpellCooldown for every spell
-- that is currently on CD so the icons show the correct timer without
-- waiting for the next cast.
function BIT.SyncCD:RestoreCooldowns()
    if not BIT.myName then return end
    local spells = GetSpellsForPlayer(BIT.myName)
    if not spells or #spells == 0 then return end

    if not BIT.syncCdState then BIT.syncCdState = {} end
    if not BIT.syncCdState[BIT.myName] then BIT.syncCdState[BIT.myName] = {} end
    local state = BIT.syncCdState[BIT.myName]

    for _, s in ipairs(spells) do
        local spellID = s.id
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and info then
            local startTime, duration
            if type(info) == "table" then
                startTime = DetaintNumber(info.startTime)
                duration  = DetaintNumber(info.duration)
            else
                startTime = info  -- legacy first return
            end
            if startTime and duration and duration > 1.5 then
                local cdEnd = startTime + duration
                if cdEnd > GetTime() then
                    state[spellID] = cdEnd
                    -- Also write base-spell key if this is a replacedBy spell
                    local baseID = replacedByToBase[spellID]
                    if baseID then state[baseID] = cdEnd end
                end
            end
        end
    end
end

function BIT.SyncCD:Create()
    CreateWindowFrame()
    CreateBarsFrame()
    -- Party detection uses category + duration matching via MatchRule() —
    -- no _auraDetectMap needed. See UNIT_AURA handler.
end

------------------------------------------------------------
-- /bitcounterdebug  – diagnose missing CD counter on icons
------------------------------------------------------------
SLASH_BITCOUNTERDEBUG1 = "/bitcounterdebug"
SlashCmdList["BITCOUNTERDEBUG"] = function()
    local p = function(...) print("|cff0091edBIT-CNTR|r", ...) end
    p("=== CD Counter Debug ===")
    p("inCombat:", tostring(BIT.inCombat))
    p("GetTime:", GetTime())

    -- Check syncCdState for own player
    local myState = BIT.syncCdState and BIT.syncCdState[BIT.myName]
    if myState then
        p("syncCdState[" .. tostring(BIT.myName) .. "]:")
        for sid, endT in pairs(myState) do
            local rem = endT - GetTime()
            p("  spellID=" .. sid .. " endTime=" .. string.format("%.2f", endT)
              .. " remaining=" .. string.format("%.1f", rem) .. "s")
        end
    else
        p("syncCdState for own player: EMPTY/NIL")
    end

    -- Check attached bar icons for own player
    local foundBar = false
    for unit, bar in pairs(attachedBars) do
        local n = (unit == "player") and BIT.myName or SafeUnitName(unit)
        if n == BIT.myName then
            foundBar = true
            p("attachedBar unit=" .. unit
              .. " frameShown=" .. tostring(bar.frame and bar.frame:IsShown()))
            for sid, ico in pairs(bar.icons) do
                local state = myState and myState[sid] or 0
                local rem   = state - GetTime()
                p("  sid=" .. sid
                  .. " _cdRunning=" .. tostring(ico._cdRunning)
                  .. " _maxCharges=" .. tostring(ico._maxCharges)
                  .. " stateEnd=" .. string.format("%.2f", state)
                  .. " rem=" .. string.format("%.1f", rem)
                  .. " cdTextShown=" .. tostring(ico.cdText and ico.cdText:IsShown())
                  .. " cdTextTxt="   .. tostring(ico.cdText and ico.cdText:GetText())
                  .. " badgeShown="  .. tostring(ico.chargeBadge and ico.chargeBadge:IsShown())
                  .. " badgeTxt="    .. tostring(ico.chargeBadge and ico.chargeBadge:GetText()))
            end
        end
    end
    if not foundBar then p("No attached bar found for own player!") end
    p("=== end ===")
end

-- /bitccdbg removed (CC tracking removed)
