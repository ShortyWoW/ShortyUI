-- Copyright (c) 2026 BliZzi1337. All rights reserved.
-- Unauthorized copying, modification, distribution or use of this
-- software, in whole or in part, without prior written permission
-- from the copyright holder is strictly prohibited.
--[[
    SpellData.lua - BliZzi_Interrupts
    ─────────────────────────────────────────────────────────
    Spell database for the Party CD / CC tracker system.
    Loaded BEFORE SyncCD.lua so all tables are ready at init.
    ─────────────────────────────────────────────────────────
    buffDur = expected self-buff duration in seconds.
    Used by the party aura detection: when a BIG_DEFENSIVE or IMPORTANT
    aura expires, its measured duration is matched against buffDur to
    identify the spell.  nil = no trackable buff.
]]

BIT.SyncCD = BIT.SyncCD or {}

------------------------------------------------------------
-- Class-wide spells (shared by all specs of a class).
-- Merged into each spec's list at the bottom of this file.
--
-- talent = true  → spell lives in the talent tree.
--   Only shown for party members when confirmed in their
--   knownSpells (from inspect talent scan).
--   WITHOUT this flag the spell is treated as a baseline
--   ability and always shown regardless of talent data.
------------------------------------------------------------
------------------------------------------------------------
-- Racial abilities (keyed by clientFileString race name).
-- Merged per-player at runtime via C_CreatureInfo race lookup.
------------------------------------------------------------
local byRace = {
    NightElf = {
        { id = 58984, cd = 120, cat = "DEF", name = "Shadowmeld", buffDur = 0 },
    },
    Dwarf = {
        { id = 20594, cd = 120, cat = "DEF", name = "Stoneform", buffDur = 8 },
    },
}
BIT.SyncCD.byRace = byRace

local byClass = {
    DEATHKNIGHT = {
        { id = 48707, cd =  60, cat = "DEF", name = "Anti-Magic Shell", buffDur = 5,
          talentMods = { [205727] = 20 } },                                  -- Anti-Magic Barrier: -20s
        { id = 48792, cd = 120, cat = "DEF", name = "Icebound Fortitude", buffDur = 8 },
    },
    DEMONHUNTER = {},
    DRUID = {
        -- noAutoRule: manual _rulesByClass["DRUID"] rules handle aura detection
        -- with _durationMods (Improved Barkskin 327993: +4s). Auto-rule would
        -- be generated without _durationMods and would take spec-rule priority.
        { id = 22812, cd = 60, cat = "DEF", name = "Barkskin", buffDur = 8, noAutoRule = true },
    },
    EVOKER = {
        { id = 363916, cd = 90, cat = "DEF", name = "Obsidian Scales", buffDur = 12, talent = true, charges = 2,
          talentMods = { [412713] = 10 }, chargeOffset = 2 },  -- Obsidian Bulwark -10s; +4s offset corrects empirical CD discrepancy
    },
    HUNTER = {
        { id = 186265, cd = 180, cat = "DEF", name = "Aspect of the Turtle", buffDur = 8, noAutoRule = true,
          talentMods = { [266921] = 30, [1258485] = 30 } },                      -- Born To Be Wild -30s | Improved Aspect of the Turtle -30s
        { id = 264735, cd =  90, cat = "DEF", name = "Survival of the Fittest", buffDur = 8, talent = true,
          talentCharges = { [459450] = 2 } },                                  -- 2nd charge talent
        { id =   5384, cd =  30, cat = "DEF", name = "Feign Death", buffDur = 360 },  -- 6 min max, always cancelled early
    },
    MAGE = {
        { id =  45438, cd = 240, cat = "DEF", name = "Ice Block", buffDur = 10,
          replacedBy = { id = 414659, cd = 240, name = "Ice Cold", buffDur = 6 } },
        { id = 342245, cd =  50, cat = "DEF", name = "Alter Time", buffDur = 10, talent = true },
    },
    MONK = {
        { id = 115203, cd = 120, cat = "DEF", name = "Fortifying Brew", buffDur = 15, buffId = 120954 },
    },
    PALADIN = {
        { id =   642, cd = 300, cat = "DEF", name = "Divine Shield", buffDur = 8 },
        { id =  1022, cd = 300, cat = "DEF", name = "Blessing of Protection", buffDur = 10,
          replacedBy = { id = 204018, cd = 300, name = "Blessing of Spellwarding", buffDur = 10 } },
        { id =  6940, cd = 120, cat = "DEF", name = "Blessing of Sacrifice", buffDur = 12, talent = true },
        { id =  1044, cd =  25, cat = "DEF", name = "Blessing of Freedom", buffDur = 8, talent = true },
        { id = 393108, cd =  45, cat = "DEF", name = "Gift of the Golden Valkyr", buffDur = 4, talent = true },  -- cheat death, applies GoAK
    },
    PRIEST = {
        { id = 19236, cd = 90, cat = "DEF", name = "Desperate Prayer", buffDur = 10, talent = true,
          talentMods = { [238100] = 20 } },                                  -- Angel's Mercy: -20s
    },
    ROGUE = {
        { id = 31224, cd = 120, cat = "DEF", name = "Cloak of Shadows", buffDur = 5 },
        { id =  5277, cd = 120, cat = "DEF", name = "Evasion", buffDur = 10 },
        { id =  1856, cd = 120, cat = "DEF", name = "Vanish", buffDur = 3 },
    },
    SHAMAN = {
        { id = 108271, cd = 120, cat = "DEF", name = "Astral Shift", buffDur = 12 },
    },
    WARLOCK = {
        { id = 104773, cd = 180, cat = "DEF", name = "Unending Resolve", buffDur = 8 },
    },
    WARRIOR = {},
}

------------------------------------------------------------
-- Spec-specific spells  (SpecID → list)
-- CD/buffDur values per spec.
------------------------------------------------------------
local bySpec = {

    -- ── Death Knight ─────────────────────────────────────
    -- Blood
    [250] = {
        { id = 55233, cd =  90, cat = "DEF", name = "Vampiric Blood", buffDur = 10 },
    },
    -- Frost
    [251] = {
        { id = 51271, cd = 45, cat = "DMG", name = "Pillar of Frost", buffDur = 12, talent = true },
    },
    -- Unholy
    [252] = {},

    -- ── Demon Hunter ─────────────────────────────────────
    -- Havoc
    [577] = {
        { id = 198589, cd = 60, cat = "DEF", name = "Blur", buffDur = 10, charges = 2, buffId = 212800 },
    },
    -- Vengeance
    [581] = {
        { id = 204021, cd =  60, cat = "DEF", name = "Fiery Brand", buffDur = 12,
          talentMods    = { [389732] = 12 },   -- Down in Flames: -12s
          talentCharges = { [389732] = 2  },   -- Down in Flames: 2 charges
        },
        { id = 187827, cd = 120, cat = "DEF", name = "Metamorphosis", buffDur = 15 },
        { id = 196718, cd = 300, cat = "DEF", name = "Darkness", buffDur = 8, talent = true,
          talentMods = { [212593] = 120 } },                                  -- Pitch Black: -120s
        { id = 209258, cd = 480, cat = "DEF", name = "Last Resort", buffDur = 15, talent = true },  -- cheat death, applies Meta
    },
    -- Devourer (Hero spec)
    [1480] = {
        { id = 198589, cd = 60, cat = "DEF", name = "Blur", buffDur = 10, charges = 2, buffId = 212800 },
        { id = 209258, cd = 480, cat = "DEF", name = "Last Resort", buffDur = 15, talent = true },  -- cheat death, applies Meta
    },

    -- ── Druid ─────────────────────────────────────────────
    -- Balance
    [102] = {
        { id = 194223, cd = 180, cat = "DMG", name = "Celestial Alignment", buffDur = 20, talent = true,
          replacedBy = { id = 102560, cd = 180, name = "Incarnation: Chosen of Elune", buffDur = 20 } },
    },
    -- Feral
    [103] = {
        { id = 106951, cd = 180, cat = "DMG", name = "Berserk", buffDur = 15, talent = true,
          replacedBy = { id = 102543, cd = 180, name = "Incarnation: Avatar of Ashamane", buffDur = 20 } },
    },
    -- Guardian
    [104] = {
        { id =  50334, cd = 180, cat = "DEF", name = "Berserk", buffDur = 15, talent = true,
          replacedBy = { id = 102558, cd = 180, name = "Incarnation: Guardian of Ursoc", buffDur = 30 } },
    },
    -- Restoration
    [105] = {
        { id = 102342, cd =  90, cat = "DEF", name = "Ironbark", buffDur = 12, talent = true,
          talentMods = { [197061] = 15 } },                                  -- Stonebark: -15s
    },

    -- ── Evoker ────────────────────────────────────────────
    -- Devastation
    [1467] = {
        { id = 375087, cd = 120, cat = "DMG", name = "Dragonrage", buffDur = 18, talent = true },
    },
    -- Preservation
    [1468] = {
        { id = 357170, cd =  60, cat = "DEF", name = "Time Dilation", buffDur = 8, talent = true },
    },
    -- Augmentation
    [1473] = {},

    -- ── Hunter ────────────────────────────────────────────
    -- Beast Mastery
    [253] = {},
    -- Marksmanship
    [254] = {
        { id = 288613, cd = 120, cat = "DMG", name = "Trueshot", buffDur = 15, talent = true },
    },
    -- Survival
    [255] = {
        { id = 1250646, cd = 90, cat = "DMG", name = "Takedown", buffDur = 8, talent = true },
    },

    -- ── Mage ──────────────────────────────────────────────
    -- Arcane
    [62] = {
        { id = 365350, cd =  90, cat = "DMG", name = "Arcane Surge", buffDur = 15, talent = true },
        { id =  55342, cd = 120, cat = "DEF", name = "Mirror Image", talent = true },  -- summon, no trackable self-buff
        { id = 110959, cd = 120, cat = "DEF", name = "Greater Invisibility", buffDur = 20, talent = true,
          talentMods = { [210476] = 60 } },                                  -- Master of Escape: -60s
    },
    -- Fire
    [63] = {
        { id = 190319, cd = 120, cat = "DMG", name = "Combustion", buffDur = 10, talent = true },
        { id =  55342, cd = 120, cat = "DEF", name = "Mirror Image", talent = true },
        { id = 110959, cd = 120, cat = "DEF", name = "Greater Invisibility", buffDur = 20, talent = true,
          talentMods = { [210476] = 60 } },                                  -- Master of Escape: -60s
    },
    -- Frost
    [64] = {
        { id =  55342, cd = 120, cat = "DEF", name = "Mirror Image", talent = true },
        { id = 110959, cd = 120, cat = "DEF", name = "Greater Invisibility", buffDur = 20, talent = true,
          talentMods = { [210476] = 60 } },                                  -- Master of Escape: -60s
    },

    -- ── Monk ──────────────────────────────────────────────
    -- Brewmaster
    [268] = {
        { id = 132578, cd = 120, cat = "DMG", name = "Invoke Niuzao, the Black Ox", buffDur = 25, talent = true },
    },
    -- Windwalker
    [269] = {},
    -- Mistweaver
    [270] = {
        { id = 116849, cd = 120, cat = "DEF", name = "Life Cocoon", buffDur = 12 },
    },

    -- ── Paladin ───────────────────────────────────────────
    -- Holy
    [65] = {
        { id =  31884, cd = 120, cat = "DMG", name = "Avenging Wrath", buffDur = 12, talent = true,
          replacedBy = { id = 216331, cd = 60, name = "Avenging Crusader", buffDur = 10 } },
        { id =    498, cd =  60, cat = "DEF", name = "Divine Protection", buffDur = 8, talent = true },
    },
    -- Protection
    [66] = {
        { id =  31884, cd = 120, cat = "DMG", name = "Avenging Wrath", buffDur = 25, talent = true,
          replacedBy = { id = 389539, cd = 120, name = "Sentinel", buffDur = 20 } },
        { id =  31850, cd =  90, cat = "DEF", name = "Ardent Defender", buffDur = 8 },
        { id =  86659, cd = 180, cat = "DEF", name = "Guardian of Ancient Kings", buffDur = 8 },
        { id =    498, cd =  60, cat = "DEF", name = "Divine Protection", buffDur = 8, talent = true },
    },
    -- Retribution
    [70] = {
        { id =  31884, cd =  60, cat = "DMG", name = "Avenging Wrath", buffDur = 24, talent = true },
        { id = 255937, cd =  30, cat = "DMG", name = "Wake of Ashes", buffDur = 8, talent = true },
        { id =    498, cd =  60, cat = "DEF", name = "Divine Protection", buffDur = 8, talent = true },
    },

    -- ── Priest ────────────────────────────────────────────
    -- Discipline
    [256] = {
        { id = 33206, cd = 180, cat = "DEF", name = "Pain Suppression", buffDur = 8 },
    },
    -- Holy
    [257] = {
        { id = 64843, cd = 180, cat = "DEF", name = "Divine Hymn", buffDur = 5 },
        { id = 47788, cd = 180, cat = "DEF", name = "Guardian Spirit", buffDur = 10 },
    },
    -- Shadow
    [258] = {
        { id = 228260, cd = 120, cat = "DMG", name = "Voidform", buffDur = 20, talent = true },
        { id =  47585, cd = 120, cat = "DEF", name = "Dispersion", buffDur = 6,
          talentMods = { [289162] = 30 } },                                  -- Intangibility: -30s
    },

    -- ── Rogue ─────────────────────────────────────────────
    -- Assassination
    [259] = {},
    -- Outlaw
    [260] = {
        { id = 13750, cd = 180, cat = "DMG", name = "Adrenaline Rush", buffDur = 20, talent = true },
    },
    -- Subtlety
    [261] = {
        { id = 121471, cd =  90, cat = "DMG", name = "Shadow Blades", buffDur = 16, talent = true },
        { id = 185313, cd =  20, cat = "DMG", name = "Shadow Dance", buffDur = 6, talent = true },
    },

    -- ── Shaman ────────────────────────────────────────────
    -- Elemental
    [262] = {
        { id = 114050, cd = 180, cat = "DMG", name = "Ascendance", buffDur = 15, talent = true },
    },
    -- Enhancement
    [263] = {
        { id = 114051, cd = 180, cat = "DMG", name = "Ascendance", buffDur = 15, talent = true },
    },
    -- Restoration
    [264] = {
        { id = 114052, cd = 180, cat = "DEF", name = "Ascendance", buffDur = 15, talent = true },
    },

    -- ── Warlock ───────────────────────────────────────────
    -- Affliction / Demonology / Destruction
    [265] = {},
    [266] = {},
    [267] = {},

    -- ── Warrior ───────────────────────────────────────────
    -- Arms
    [71] = {
        { id = 107574, cd =  90, cat = "DMG", name = "Avatar", buffDur = 20, talent = true },
        { id = 118038, cd = 120, cat = "DEF", name = "Die by the Sword", buffDur = 8, talent = true },
    },
    -- Fury
    [72] = {
        { id = 107574, cd =  90, cat = "DMG", name = "Avatar", buffDur = 20, talent = true },
        { id = 184364, cd = 120, cat = "DEF", name = "Enraged Regeneration", buffDur = 8, talent = true },
    },
    -- Protection
    [73] = {
        { id = 107574, cd =  90, cat = "DMG", name = "Avatar", buffDur = 20, talent = true },
        { id =    871, cd = 180, cat = "DEF", name = "Shield Wall", buffDur = 8,
          talentMods    = { [397103] = 60 },   -- Defender's Aegis: -60s  → 120s
          talentCharges = { [397103] = 2  },   -- Defender's Aegis: 2 charges
        },
    },
}

------------------------------------------------------------
-- SpecID → class name mapping (for byClass merge)
------------------------------------------------------------
local specToClass = {
    [250] = "DEATHKNIGHT", [251] = "DEATHKNIGHT", [252] = "DEATHKNIGHT",
    [577] = "DEMONHUNTER", [581] = "DEMONHUNTER", [1480] = "DEMONHUNTER",
    [102] = "DRUID", [103] = "DRUID", [104] = "DRUID", [105] = "DRUID",
    [1467] = "EVOKER", [1468] = "EVOKER", [1473] = "EVOKER",
    [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [62] = "MAGE", [63] = "MAGE", [64] = "MAGE",
    [268] = "MONK", [269] = "MONK", [270] = "MONK",
    [65] = "PALADIN", [66] = "PALADIN", [70] = "PALADIN",
    [256] = "PRIEST", [257] = "PRIEST", [258] = "PRIEST",
    [259] = "ROGUE", [260] = "ROGUE", [261] = "ROGUE",
    [262] = "SHAMAN", [263] = "SHAMAN", [264] = "SHAMAN",
    [265] = "WARLOCK", [266] = "WARLOCK", [267] = "WARLOCK",
    [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR",
}

------------------------------------------------------------
-- Icon overrides: spellID → alternative spellID used for icon texture
-- (e.g. when the buff icon differs from the spell icon)
------------------------------------------------------------
BIT.SyncCD.SPELL_ICON_OVERRIDE = {}

------------------------------------------------------------
-- CD reducer spells: casting spellID reduces another spell's CD
-- trigger spellID → { talent = talentID, targetSpell = spellID, reduction = seconds }
------------------------------------------------------------
BIT.SyncCD.CD_REDUCER_SPELLS = {
    -- Shield Slam → -6s on Shield Wall via Impenetrable Wall talent
    [23922] = { talent = 383430, targetSpell = 871, reduction = 6 },
}

------------------------------------------------------------
-- Spell → Buff-Aura mapping  (for green highlight system)
-- spellID → buffAuraID  (when they differ)
------------------------------------------------------------
BIT.SyncCD.SPELL_BUFF_MAP = {
    [342245] = 110909,  -- Alter Time: spell=342245, buff aura=110909
    [187827] = 187827,  -- Metamorphosis: same ID
    [58984]  = 58984,   -- Shadowmeld (Night Elf racial): stealth buff 58984 on cast
}

------------------------------------------------------------
-- Merge byClass into each spec → final BIT.SYNC_SPELLS
-- (CC spells removed — cannot be reliably tracked)
------------------------------------------------------------
BIT.SYNC_SPELLS = {}
for specID, specSpells in pairs(bySpec) do
    local merged = {}
    -- spec-specific first
    for _, s in ipairs(specSpells) do
        merged[#merged + 1] = s
    end
    -- then class-wide
    local className = specToClass[specID]
    if className and byClass[className] then
        for _, s in ipairs(byClass[className]) do
            merged[#merged + 1] = s
        end
    end
    BIT.SYNC_SPELLS[specID] = merged
end

------------------------------------------------------------
-- Build lookup tables used by SyncCD.lua
------------------------------------------------------------
-- replacedByToBase: replacedBy.id → base spell id
-- spellLookup:      spellID → spell entry  (for OnPartySpellCast)
-- spellLookupStr:   tostring(spellID) → spell entry  (tainted fallback)
BIT.SyncCD.replacedByToBase = {}
BIT.SyncCD.spellLookup      = {}
BIT.SyncCD.spellLookupStr   = {}

-- spellLookupByName: localized spell name → spell entry  (for UNIT_SPELLCAST_SENT)
BIT.SyncCD.spellLookupByName = {}

-- buffIdToSpellId: buff aura spell ID → cast spell ID
-- Some spells apply a buff with a DIFFERENT spell ID than the cast spell.
-- e.g. Blur: cast=198589, buff aura=212800.
-- SyncCD uses this to remap the aura's spellId so rule matching works correctly.
BIT.SyncCD.buffIdToSpellId = {}

for _, spells in pairs(BIT.SYNC_SPELLS) do
    for _, s in ipairs(spells) do
        BIT.SyncCD.spellLookup[s.id] = s
        BIT.SyncCD.spellLookupStr[tostring(s.id)] = s
        if s.buffId then
            BIT.SyncCD.buffIdToSpellId[s.buffId] = s.id
        end
        if s.replacedBy then
            BIT.SyncCD.replacedByToBase[s.replacedBy.id] = s.id
            BIT.SyncCD.spellLookup[s.replacedBy.id] = s.replacedBy
            BIT.SyncCD.spellLookupStr[tostring(s.replacedBy.id)] = s.replacedBy
        end
    end
end

-- Register racial spells in lookups
if BIT.SyncCD.byRace then
    for _, raceSpells in pairs(BIT.SyncCD.byRace) do
        for _, s in ipairs(raceSpells) do
            BIT.SyncCD.spellLookup[s.id] = s
            BIT.SyncCD.spellLookupStr[tostring(s.id)] = s
        end
    end
end

-- Build name-based lookup (uses localized spell names from GetSpellInfo)
-- This enables CD detection via UNIT_SPELLCAST_SENT which provides untainted
-- spell names, bypassing the tainted spellID problem on party members.
do
    local allEntries = {}
    for _, spells in pairs(BIT.SYNC_SPELLS) do
        for _, s in ipairs(spells) do
            allEntries[#allEntries + 1] = s
            if s.replacedBy then allEntries[#allEntries + 1] = s.replacedBy end
        end
    end
    -- Include racial spells
    if BIT.SyncCD.byRace then
        for _, raceSpells in pairs(BIT.SyncCD.byRace) do
            for _, s in ipairs(raceSpells) do
                allEntries[#allEntries + 1] = s
            end
        end
    end
    for _, s in ipairs(allEntries) do
        local ok, name = pcall(C_Spell.GetSpellName, s.id)
        if ok and name and name ~= "" then
            -- Only store if not already mapped (first entry wins — higher-spec-priority)
            if not BIT.SyncCD.spellLookupByName[name] then
                BIT.SyncCD.spellLookupByName[name] = s
            end
        end
    end
end

------------------------------------------------------------
-- Aura detection rules (bySpec + byClass).
-- Each rule: SpellId, BuffDuration, Cooldown, BigDefensive, ExternalDefensive,
--            Important, RequiresEvidence, CanCancelEarly, MinDuration,
--            RequiresTalent, ExcludeIfTalent, _cdMods, _durationMods
------------------------------------------------------------
BIT.SyncCD._rulesBySpec = {
    [65] = { -- Holy Paladin
        { SpellId=31884,  BuffDuration=12, Cooldown=120, Important=true,  BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true, ExcludeIfTalent=216331,
          _cdMods = { [1241511] = -30 } }, -- Avenging Wrath (Call of the Righteous -30s)
        { SpellId=216331, BuffDuration=10, Cooldown=60,  Important=true,  BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true, RequiresTalent=216331,
          _cdMods = { [1241511] = -15 } }, -- Avenging Crusader (Call of the Righteous -15s)
        { SpellId=642,    BuffDuration=8,  Cooldown=300, BigDefensive=true,  ExternalDefensive=false, Important=true,  RequiresEvidence={"Cast","Debuff","UnitFlags"}, CanCancelEarly=true,
          _cdMods = { [114154] = -90 } }, -- Divine Shield (Unbreakable Spirit -30%)
        { SpellId=498,    BuffDuration=8,  Cooldown=60,  BigDefensive=true,  Important=true,  ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [114154] = -18 } }, -- Divine Protection (Unbreakable Spirit -30%)
        { SpellId=204018, BuffDuration=10, Cooldown=300, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast", RequiresTalent=5692,
          _cdMods = { [384909] = -60 } }, -- Spellwarding (Blessed Protector -60s)
        { SpellId=1022,   BuffDuration=10, Cooldown=300, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast", ExcludeIfTalent=5692,
          _cdMods = { [384909] = -60 } }, -- BoP (Blessed Protector -60s)
        { SpellId=6940,   BuffDuration=12, Cooldown=120, ExternalDefensive=true, BigDefensive=false, Important=false, RequiresEvidence="Cast",
          _cdMods = { [384820] = -15 } }, -- Sacrifice (Sacrifice of the Just -15s)
    },
    [66] = { -- Protection Paladin
        { SpellId=31884,  BuffDuration=25, Cooldown=120, Important=true,  ExternalDefensive=false, BigDefensive=false, MinDuration=true, RequiresEvidence="Cast", ExcludeIfTalent=389539,
          _cdMods = { [204074] = -60 } }, -- AW (Righteous Protector -50%)
        { SpellId=389539, BuffDuration=20, Cooldown=120, Important=true,  ExternalDefensive=false, BigDefensive=false, MinDuration=true, RequiresEvidence="Cast", RequiresTalent=389539, ExcludeIfTalent=31884,
          _cdMods = { [204074] = -60 } }, -- Sentinel (Righteous Protector -50%)
        { SpellId=642,    BuffDuration=8,  Cooldown=300, BigDefensive=true,  ExternalDefensive=false, Important=true,  RequiresEvidence={"Cast","Debuff","UnitFlags"}, CanCancelEarly=true,
          _cdMods = { [114154] = -90, [378425] = -45 } }, -- Divine Shield (Unbreakable Spirit -30%, Aegis of Light -15%)
        { SpellId=31850,  BuffDuration=8,  Cooldown=90,  BigDefensive=true,  Important=true,  ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [114154] = -27 } }, -- Ardent Defender (Unbreakable Spirit -30%)
        { SpellId=86659,  BuffDuration=8,  Cooldown=180, BigDefensive=true,  Important=false, ExternalDefensive=false, RequiresEvidence="Cast" }, -- Guardian of Ancient Kings
        { SpellId=204018, BuffDuration=10, Cooldown=300, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast", RequiresTalent=5692,
          _cdMods = { [384909] = -60, [378425] = -45 } }, -- Spellwarding (Blessed Protector -60s, Aegis -15%)
        { SpellId=1022,   BuffDuration=10, Cooldown=300, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast", ExcludeIfTalent=5692,
          _cdMods = { [384909] = -60, [378425] = -45 } }, -- BoP (Blessed Protector -60s, Aegis -15%)
        { SpellId=6940,   BuffDuration=12, Cooldown=120, ExternalDefensive=true, BigDefensive=false, Important=false, RequiresEvidence="Cast",
          _cdMods = { [384820] = -60 } }, -- Sacrifice (Sacrifice of the Just -60s)
    },
    [70] = { -- Retribution Paladin
        { SpellId=31884,  BuffDuration=24, Cooldown=60,  Important=true,  ExternalDefensive=false, BigDefensive=false, RequiresEvidence="Cast", ExcludeIfTalent=458359 }, -- AW
        { SpellId=642,    BuffDuration=8,  Cooldown=300, BigDefensive=true,  ExternalDefensive=false, Important=true,  RequiresEvidence={"Cast","Debuff","UnitFlags"}, CanCancelEarly=true,
          _cdMods = { [114154] = -90 } }, -- Divine Shield (Unbreakable Spirit -30%)
        { SpellId=403876, BuffDuration=8,  Cooldown=90,  Important=true,  ExternalDefensive=false, BigDefensive=false, RequiresEvidence={"Cast","Shield"},
          _cdMods = { [114154] = -27 } }, -- Divine Protection Ret (Unbreakable Spirit -30%)
        { SpellId=204018, BuffDuration=10, Cooldown=300, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast", RequiresTalent=5692,
          _cdMods = { [384909] = -60 } }, -- Spellwarding (Blessed Protector -60s)
        { SpellId=1022,   BuffDuration=10, Cooldown=300, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast", ExcludeIfTalent=5692,
          _cdMods = { [384909] = -60 } }, -- BoP (Blessed Protector -60s)
        { SpellId=6940,   BuffDuration=12, Cooldown=120, ExternalDefensive=true, BigDefensive=false, Important=false, RequiresEvidence="Cast",
          _cdMods = { [384820] = -60 } }, -- Sacrifice (Sacrifice of the Just -60s)
    },
    [62]  = { { SpellId=365350, BuffDuration=15, Cooldown=90,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true } }, -- Arcane Surge
    [63]  = { { SpellId=190319, BuffDuration=10, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true,
          _cdMods = { [1254194] = -60 } } }, -- Combustion (Kindling -60s)
    [71]  = { -- Arms Warrior
        { SpellId=118038, BuffDuration=8,  Cooldown=120, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [391271] = -12 } }, -- Die by the Sword
        { SpellId=118038, BuffDuration=8,  Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [391271] = -12 } }, -- Die by the Sword (IMPORTANT fallback)
        { SpellId=107574, BuffDuration=20, Cooldown=90,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true, RequiresTalent=107574 }, -- Avatar
    },
    [72]  = { -- Fury Warrior
        { SpellId=184364, BuffDuration=8,  Cooldown=108, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast", RequiresTalent=184364 }, -- Enraged Regen
        { SpellId=184364, BuffDuration=8,  Cooldown=108, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast", RequiresTalent=184364 }, -- Enraged Regen (IMPORTANT fallback)
        { SpellId=184364, BuffDuration=11, Cooldown=108, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast", RequiresTalent=184364 }, -- Enraged Regen +3s
        { SpellId=184364, BuffDuration=11, Cooldown=108, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast", RequiresTalent=184364 }, -- Enraged Regen +3s (IMPORTANT fallback)
        { SpellId=107574, BuffDuration=20, Cooldown=90,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true, RequiresTalent=107574 },
    },
    [73]  = { -- Protection Warrior
        { SpellId=871,    BuffDuration=8,  Cooldown=180, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [397103] = -60 } }, -- Shield Wall
        { SpellId=871,    BuffDuration=8,  Cooldown=180, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [397103] = -60 } }, -- Shield Wall (IMPORTANT fallback)
        { SpellId=107574, BuffDuration=20, Cooldown=90,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true, RequiresTalent=107574 },
    },
    [250] = { -- Blood Death Knight
        { SpellId=55233, BuffDuration=10, Cooldown=90, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- Vampiric Blood
        { SpellId=55233, BuffDuration=10, Cooldown=90, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- VB (IMPORTANT fallback)
        { SpellId=55233, BuffDuration=12, Cooldown=90, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- VB +2s
        { SpellId=55233, BuffDuration=12, Cooldown=90, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- VB +2s (IMPORTANT fallback)
        { SpellId=55233, BuffDuration=14, Cooldown=90, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- VB +4s
        { SpellId=55233, BuffDuration=14, Cooldown=90, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- VB +4s (IMPORTANT fallback)
    },
    [251] = { { SpellId=51271, BuffDuration=12, Cooldown=45, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true } }, -- Pillar of Frost
    [256] = { { SpellId=33206, BuffDuration=8, Cooldown=180, ExternalDefensive=true, BigDefensive=false, Important=false, RequiresEvidence="Cast" } }, -- Pain Suppression
    [257] = { -- Holy Priest
        { SpellId=47788, BuffDuration=10, Cooldown=180, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast" }, -- Guardian Spirit
        { SpellId=64843, BuffDuration=5,  Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, CanCancelEarly=true, RequiresEvidence="Cast",
          _cdMods = { [419110] = -60 } }, -- Divine Hymn (Seraphic Crescendo -60s)
    },
    [258] = { -- Shadow Priest
        { SpellId=47585,  BuffDuration=6,  Cooldown=120, BigDefensive=true,  ExternalDefensive=false, Important=true, CanCancelEarly=true, RequiresEvidence={"Cast","UnitFlags"},
          _cdMods = { [288733] = -30 } }, -- Dispersion (BIG_DEFENSIVE)
        { SpellId=228260, BuffDuration=20, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false,
          CanCancelEarly=true, MinActualDuration=7, RequiresEvidence="Cast" }, -- Voidform (vor Dispersion-Fallback: Mindestdauer 7s > Dispersions max 6.3s)
        { SpellId=47585,  BuffDuration=6,  Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=true, CanCancelEarly=true, RequiresEvidence={"Cast","UnitFlags"},
          _cdMods = { [288733] = -30 } }, -- Dispersion (IMPORTANT fallback)
    },
    [102] = { { SpellId=102560, BuffDuration=20, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true,
          _cdMods = { [468743] = -60, [390378] = -60 } } }, -- Incarnation: CoE (Whirling Stars / Orbital Strike -60s)
    [103] = { -- Feral Druid
        { SpellId=106951, BuffDuration=15, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, MinDuration=true, RequiresTalent=106951, ExcludeIfTalent=102543,
          _cdMods = { [391174] = -60, [391548] = -30 } }, -- Berserk (Heart of the Lion -60s, Ashamane's Guidance -30s)
        { SpellId=102543, BuffDuration=20, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", RequiresTalent=102543,
          _cdMods = { [391174] = -60, [391548] = -30 } }, -- Incarnation (Heart of the Lion -60s, Ashamane's Guidance -30s)
    },
    [104] = { { SpellId=102558, BuffDuration=30, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast" } }, -- Incarnation: Guardian of Ursoc
    [105] = { { SpellId=102342, BuffDuration=12, Cooldown=90, ExternalDefensive=true, BigDefensive=false, Important=false,
          _cdMods = { [382552] = -20 },
          _durationMods = { [392116] = 4 } } }, -- Ironbark (Improved Ironbark -20s CD | Regenerative Heartwood 392116: +4s dur)
    [268] = { -- Brewmaster Monk
        { SpellId=132578, BuffDuration=25, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [450989] = -25 } }, -- Invoke Niuzao (Efficient Reduction -25s)
        { SpellId=115203, BuffDuration=15, Cooldown=360, BigDefensive=true, Important=false, ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [388813] = -120 } }, -- Fortifying Brew (Expeditious Fortification -120s)
    },
    [270] = { { SpellId=116849, BuffDuration=12, Cooldown=120, ExternalDefensive=true, BigDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence="Cast",
          _cdMods = { [202424] = -45 } } }, -- Life Cocoon (Chrysalis -45s)
    [577] = { -- Havoc DH
        { SpellId=198589, BuffDuration=10, Cooldown=60, BigDefensive=true,  ExternalDefensive=false, Important=true,  RequiresEvidence="Cast" }, -- Blur
        { SpellId=198589, BuffDuration=10, Cooldown=60, BigDefensive=false, ExternalDefensive=false, Important=true,  RequiresEvidence="Cast" }, -- Blur (IMPORTANT fallback)
    },
    [1480] = { -- Devourer DH
        { SpellId=198589, BuffDuration=10, Cooldown=60, BigDefensive=true,  ExternalDefensive=false, Important=false, RequiresEvidence="Cast" }, -- Blur
        { SpellId=198589, BuffDuration=10, Cooldown=60, BigDefensive=false, ExternalDefensive=false, Important=false, RequiresEvidence="Cast" }, -- Blur (BIG_DEF fallback)
    },
    [581] = { -- Vengeance Demon Hunter
        { SpellId=204021, BuffDuration=12, Cooldown=60, BigDefensive=true,  ExternalDefensive=false, Important=false, MinDuration=true, RequiresEvidence="Cast",
          _cdMods = { [389732] = -12 } }, -- Fiery Brand
        { SpellId=204021, BuffDuration=12, Cooldown=60, BigDefensive=false, ExternalDefensive=false, Important=false, MinDuration=true, RequiresEvidence="Cast",
          _cdMods = { [389732] = -12 } }, -- Fiery Brand (BIG_DEF fallback)
        { SpellId=187827, BuffDuration=15, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast" }, -- Metamorphosis
        { SpellId=187827, BuffDuration=20, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast" }, -- Metamorphosis +5s
    },
    [254] = { -- Marksmanship Hunter
        { SpellId=288613, BuffDuration=15, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [260404] = -30 } }, -- Trueshot (Calling the Shots -30s)
        { SpellId=288613, BuffDuration=17, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [260404] = -30 } }, -- Trueshot +2s
    },
    [255] = { -- Survival Hunter
        { SpellId=1250646, BuffDuration=8,  Cooldown=90, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [1251790] = -30 } }, -- Coordinated Assault
        { SpellId=1250646, BuffDuration=10, Cooldown=90, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast",
          _cdMods = { [1251790] = -30 } }, -- Coordinated Assault +2s
    },
    [261] = { -- Subtlety Rogue
        { SpellId=121471, BuffDuration=16, Cooldown=90, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast" }, -- Shadow Blades
        { SpellId=121471, BuffDuration=18, Cooldown=90, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast" },
        { SpellId=121471, BuffDuration=20, Cooldown=90, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast" },
        { SpellId=185313, BuffDuration=6,  Cooldown=20, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence={"Cast","Buff"} }, -- Shadow Dance
    },
    [262] = { -- Elemental Shaman
        { SpellId=114050, BuffDuration=15, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=114050, RequiresEvidence="Cast" }, -- Ascendance
        { SpellId=114050, BuffDuration=18, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=114050, RequiresEvidence="Cast" }, -- Ascendance +3s (Preeminence)
    },
    [263] = { -- Enhancement Shaman
        { SpellId=384352, BuffDuration=8,  Cooldown=60,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=384352, RequiresEvidence="Cast" }, -- Doomwinds
        { SpellId=384352, BuffDuration=10, Cooldown=60,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=384352, RequiresEvidence="Cast" }, -- Doomwinds +2s (Thorim's Invocation)
        { SpellId=114051, BuffDuration=15, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=114051, RequiresEvidence="Cast" }, -- Ascendance (Enhancement)
    },
    [264] = { -- Restoration Shaman
        { SpellId=114052, BuffDuration=15, Cooldown=180, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=114052, RequiresEvidence="Cast" }, -- Ascendance (Resto)
    },
    [1467] = { { SpellId=375087, BuffDuration=18, Cooldown=120, Important=true, BigDefensive=false, ExternalDefensive=false, RequiresEvidence="Cast", MinDuration=true } }, -- Dragonrage
    [1468] = { { SpellId=357170, BuffDuration=8,  Cooldown=60,  ExternalDefensive=true, BigDefensive=false, Important=false, RequiresEvidence="Cast",
          _cdMods = { [376204] = -10 } } }, -- Time Dilation (Just in Time -10s)
    [1473] = { { SpellId=363916, BuffDuration=13.4, Cooldown=80, BigDefensive=true, ExternalDefensive=false, Important=true, RequiresEvidence="Cast", MinDuration=true } }, -- Obsidian Scales Aug (Obsidian Bulwark assumed)
}

BIT.SyncCD._rulesByClass = {
    PALADIN = {
        { SpellId=642,    BuffDuration=8,  Cooldown=300, BigDefensive=true,  Important=true,  ExternalDefensive=false, RequiresEvidence={"Cast","Debuff","UnitFlags"}, CanCancelEarly=true,
          _cdMods = { [114154] = -90 } }, -- Divine Shield
        { SpellId=1044,   BuffDuration=8,  Cooldown=25,  Important=true,  ExternalDefensive=false, BigDefensive=false, CanCancelEarly=true, RequiresEvidence="Cast" }, -- Blessing of Freedom
        { SpellId=204018, BuffDuration=10, Cooldown=45,  ExternalDefensive=true, Important=false, BigDefensive=false, CanCancelEarly=true, RequiresEvidence="Cast", RequiresTalent=5692,
          _cdMods = { [384909] = -60 } }, -- Spellwarding (Blessed Protector -60s)
        { SpellId=1022,   BuffDuration=10, Cooldown=300, ExternalDefensive=true, Important=false, BigDefensive=false, CanCancelEarly=true, RequiresEvidence="Cast", ExcludeIfTalent=5692,
          _cdMods = { [384909] = -60 } }, -- BoP (Blessed Protector -60s)
    },
    WARRIOR = {},
    MAGE = {
        { SpellId=45438,  BuffDuration=10, Cooldown=240, BigDefensive=true, ExternalDefensive=false, Important=true, CanCancelEarly=true, RequiresEvidence={"Cast","Debuff"}, ExcludeIfTalent=414659,
          _cdMods = { [382424] = -60, [1265517] = -30 } }, -- Ice Block
        { SpellId=414659, BuffDuration=6,  Cooldown=240, BigDefensive=true, ExternalDefensive=false, Important=true, RequiresEvidence={"Cast","Debuff"}, RequiresTalent=414659,
          _cdMods = { [382424] = -60, [1265517] = -30 } }, -- Ice Cold
        { SpellId=342245, BuffDuration=10, Cooldown=50,  BigDefensive=true,  ExternalDefensive=false, Important=true,  CanCancelEarly=true, RequiresEvidence="Cast",
          _cdMods = { [1255166] = -10 } }, -- Alter Time (BIG_DEFENSIVE + IMPORTANT)
        { SpellId=342245, BuffDuration=10, Cooldown=50,  BigDefensive=false, ExternalDefensive=false, Important=true,  CanCancelEarly=true, RequiresEvidence="Cast",
          _cdMods = { [1255166] = -10 } }, -- Alter Time (IMPORTANT-only fallback)
        { SpellId=110959, BuffDuration=20, Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence={"Cast","CombatDrop","UnitFlags"} }, -- Greater Invisibility
    },
    HUNTER = {
        { SpellId=186265, BuffDuration=8, Cooldown=180, BigDefensive=true,  ExternalDefensive=false, Important=true, CanCancelEarly=true, RequiresEvidence={"Cast","UnitFlags"},
          _cdMods = { [1258485] = -30, [266921] = -30 } }, -- Turtle (BIG_DEFENSIVE+IMPORTANT)
        { SpellId=186265, BuffDuration=8, Cooldown=180, BigDefensive=false, ExternalDefensive=false, Important=true, CanCancelEarly=true, RequiresEvidence={"Cast","UnitFlags"},
          _cdMods = { [1258485] = -30, [266921] = -30 } }, -- Turtle (IMPORTANT only fallback)
        { SpellId=264735, BuffDuration=8, Cooldown=90,  BigDefensive=true,  ExternalDefensive=false, Important=true, MinDuration=3.5, RequiresEvidence="Cast" }, -- SotF (min 3.5s: excludes 3s Dark Ranger SotF from Exhilaration)
        { SpellId=264735, BuffDuration=8, Cooldown=90,  BigDefensive=false, ExternalDefensive=false, Important=true, MinDuration=3.5, RequiresEvidence="Cast" }, -- SotF (IMPORTANT fallback)
        { SpellId=5384,   BuffDuration=360, Cooldown=30, BigDefensive=false, ExternalDefensive=false, Important=false, CanCancelEarly=true, RequiresEvidence={"Cast","UnitFlags","FeignDeath"} }, -- Feign Death
    },
    DRUID = {
        { SpellId=22812, BuffDuration=8, Cooldown=60, BigDefensive=true,  ExternalDefensive=false, Important=true,
          RaidInCombatExclude=true, _durationMods = { [327993] = 4 } }, -- Barkskin (Improved Barkskin 327993: +4s)
        { SpellId=22812, BuffDuration=8, Cooldown=60, BigDefensive=false, ExternalDefensive=false, Important=true,
          RaidInCombatExclude=true, _durationMods = { [327993] = 4 } }, -- Barkskin (IMPORTANT fallback)
    },
    ROGUE = {
        { SpellId=5277,  BuffDuration=10, Cooldown=120, Important=true,  ExternalDefensive=false, BigDefensive=false, RequiresEvidence="Cast" }, -- Evasion
        { SpellId=31224, BuffDuration=5,  Cooldown=120, BigDefensive=true, ExternalDefensive=false, Important=false, RequiresEvidence="Cast" }, -- Cloak of Shadows
        { SpellId=1856,  BuffDuration=3,  Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=false, RequiresEvidence={"Cast","Buff","CombatDrop","UnitFlags"} }, -- Vanish
    },
    DEATHKNIGHT = {
        { SpellId=48707, BuffDuration=5, Cooldown=60,  BigDefensive=true,  Important=true, ExternalDefensive=false, CanCancelEarly=true, RequiresEvidence={"Cast","Shield"},
          _cdMods = { [205727] = -20, [457574] = 20 } }, -- AMS
        { SpellId=48707, BuffDuration=5, Cooldown=60,  BigDefensive=false, Important=true, ExternalDefensive=false, CanCancelEarly=true, RequiresEvidence={"Cast","Shield"},
          _cdMods = { [205727] = -20, [457574] = 20 } }, -- AMS (IMPORTANT fallback)
        { SpellId=48707, BuffDuration=7, Cooldown=60,  BigDefensive=true,  Important=true, ExternalDefensive=false, CanCancelEarly=true, RequiresEvidence={"Cast","Shield"},
          _cdMods = { [205727] = -20, [457574] = 20 } }, -- AMS + AMB
        { SpellId=48707, BuffDuration=7, Cooldown=60,  BigDefensive=false, Important=true, ExternalDefensive=false, CanCancelEarly=true, RequiresEvidence={"Cast","Shield"},
          _cdMods = { [205727] = -20, [457574] = 20 } }, -- AMS + AMB (IMPORTANT fallback)
        { SpellId=48792, BuffDuration=8, Cooldown=120, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- Icebound Fortitude
        { SpellId=48792, BuffDuration=8, Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast" }, -- IBF (IMPORTANT fallback)
    },
    DEMONHUNTER = {
        { SpellId=198589, BuffDuration=10, Cooldown=60, BigDefensive=true,  ExternalDefensive=false, Important=true,  RequiresEvidence="Cast" }, -- Blur
        { SpellId=198589, BuffDuration=10, Cooldown=60, BigDefensive=false, ExternalDefensive=false, Important=true,  RequiresEvidence="Cast" }, -- Blur (IMPORTANT fallback)
    },
    MONK = {
        { SpellId=115203, BuffDuration=15, Cooldown=120, BigDefensive=true,  ExternalDefensive=false, Important=false, RequiresEvidence="Cast",
          _cdMods = { [388813] = -30 } }, -- Fortifying Brew
        { SpellId=115203, BuffDuration=15, Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=false, RequiresEvidence="Cast",
          _cdMods = { [388813] = -30 } }, -- Fortifying Brew (BIG_DEF fallback)
    },
    SHAMAN = {
        { SpellId=108271, BuffDuration=12, Cooldown=120, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [381647] = -30 } }, -- Astral Shift
        { SpellId=108271, BuffDuration=12, Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [381647] = -30 } }, -- Astral Shift (IMPORTANT fallback)
    },
    WARLOCK = {
        { SpellId=104773, BuffDuration=8,  Cooldown=180, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [386659] = -45 } }, -- Unending Resolve
        { SpellId=104773, BuffDuration=8,  Cooldown=180, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [386659] = -45 } }, -- Unending Resolve (IMPORTANT fallback)
        { SpellId=212295, BuffDuration=3,  Cooldown=45,  Important=true, BigDefensive=false, ExternalDefensive=false, RequiresTalent=3624, CanCancelEarly=true, RequiresEvidence="Cast" }, -- Nether Ward
    },
    PRIEST = {
        -- Desperate Prayer: flagged BIG_DEFENSIVE+IMPORTANT, some WoW versions only IMPORTANT.
        -- Add both variants so detection works regardless of which flags Blizzard applies.
        { SpellId=19236, BuffDuration=10, Cooldown=90, BigDefensive=true,  ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [238100] = -20 } }, -- Desperate Prayer (BIG_DEFENSIVE + IMPORTANT)
        { SpellId=19236, BuffDuration=10, Cooldown=90, BigDefensive=false, ExternalDefensive=false, Important=true, RequiresEvidence="Cast",
          _cdMods = { [238100] = -20 } }, -- Desperate Prayer (IMPORTANT only — fallback)
    },
    EVOKER = {
        { SpellId=363916, BuffDuration=12, Cooldown=80, BigDefensive=true, ExternalDefensive=false, Important=true, RequiresEvidence="Cast", MinDuration=true }, -- Obsidian Scales (Obsidian Bulwark assumed)
    },
}

------------------------------------------------------------
-- Racial detection rules (per-race evidence)
-- These are checked separately since racials are race-based,
-- not class/spec-based. MatchRule queries these via race lookup.
------------------------------------------------------------
BIT.SyncCD._rulesByRace = {
    NightElf = {
        { SpellId=58984,  BuffDuration=0,  Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=false, MinDuration=true, RequiresEvidence={"Cast","Buff","CombatDrop","UnitFlags"} }, -- Shadowmeld
    },
    Dwarf = {
        { SpellId=20594,  BuffDuration=8,  Cooldown=120, BigDefensive=false, ExternalDefensive=false, Important=false, RequiresEvidence={"Cast","DebuffRemoved"} }, -- Stoneform
    },
}

------------------------------------------------------------
-- Auto-generate fallback rules from SYNC_SPELLS for spells
-- that have a buffDur but no manually-defined rule above.
-- This closes the detection gap: if the CLEU path misses a
-- cast, the aura-based path can still match and start the CD.
------------------------------------------------------------
do
    local specToClass = {
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

    -- Collect IDs already covered by manual rules
    local coveredBySpec  = {}
    local coveredByClass = {}
    for specID, rules in pairs(BIT.SyncCD._rulesBySpec) do
        for _, r in ipairs(rules) do coveredBySpec[specID .. "_" .. r.SpellId] = true end
    end
    for cls, rules in pairs(BIT.SyncCD._rulesByClass) do
        for _, r in ipairs(rules) do coveredByClass[cls .. "_" .. r.SpellId] = true end
    end

    -- Generate missing rules from SYNC_SPELLS entries with buffDur
    local seenSpec  = {}
    local seenClass = {}
    for specID, spells in pairs(BIT.SYNC_SPELLS) do
        local cls = specToClass[specID]
        if cls then
        for _, s in ipairs(spells) do
            local entries = { s }
            if s.replacedBy then entries[2] = s.replacedBy end
            for _, spell in ipairs(entries) do
                if spell.buffDur and spell.buffDur > 0 and spell.cd and spell.cd > 0 and not spell.noAutoRule then
                    local isDef = (spell.cat == "DEF")
                    local isExt = false  -- externals already have manual rules
                    local autoRule = {
                        SpellId           = spell.id,
                        BuffDuration      = spell.buffDur,
                        Cooldown          = spell.cd,
                        BigDefensive      = isDef,
                        ExternalDefensive = isExt,
                        Important         = true,
                        RequiresEvidence  = "Cast",
                        CanCancelEarly    = true,  -- safe default: accept shorter durations
                    }
                    -- Copy talent CD mods. talentCdMods uses negative values (direct add).
                    -- talentMods uses positive reductions (negated here for CommitCooldown).
                    if spell.talentCdMods then
                        autoRule._cdMods = spell.talentCdMods
                    elseif spell.talentMods then
                        autoRule._cdMods = {}
                        for tid, reduction in pairs(spell.talentMods) do
                            autoRule._cdMods[tid] = -reduction  -- talentMods=+20 → _cdMods=-20
                        end
                    end

                    -- Add to spec rules if not already covered
                    local specKey = specID .. "_" .. spell.id
                    if not coveredBySpec[specKey] and not seenSpec[specKey] then
                        seenSpec[specKey] = true
                        if not BIT.SyncCD._rulesBySpec[specID] then
                            BIT.SyncCD._rulesBySpec[specID] = {}
                        end
                        local t = BIT.SyncCD._rulesBySpec[specID]
                        t[#t + 1] = autoRule
                    end

                    -- Add to class rules if not already covered (only once per class+spell)
                    local classKey = cls .. "_" .. spell.id
                    if not coveredByClass[classKey] and not seenClass[classKey] then
                        seenClass[classKey] = true
                        if not BIT.SyncCD._rulesByClass[cls] then
                            BIT.SyncCD._rulesByClass[cls] = {}
                        end
                        local t = BIT.SyncCD._rulesByClass[cls]
                        t[#t + 1] = autoRule
                    end
                end
            end
        end
        end -- if cls
    end
end

-- Build lookup of external defensive spell IDs for direct aura checks.
-- GetUnitAuras("HELPFUL|EXTERNAL_DEFENSIVE") may miss externals in WoW 12.x;
-- GetAuraDataBySpellID is used as a reliable fallback for these spells.
do
    local seen = {}
    local ids  = {}
    for _, rules in pairs(BIT.SyncCD._rulesBySpec) do
        for _, r in ipairs(rules) do
            if r.ExternalDefensive and r.SpellId and not seen[r.SpellId] then
                seen[r.SpellId] = true
                ids[#ids + 1] = r.SpellId
            end
        end
    end
    for _, rules in pairs(BIT.SyncCD._rulesByClass) do
        for _, r in ipairs(rules) do
            if r.ExternalDefensive and r.SpellId and not seen[r.SpellId] then
                seen[r.SpellId] = true
                ids[#ids + 1] = r.SpellId
            end
        end
    end
    BIT.SyncCD._externalDefensiveSpellIds = ids
end
