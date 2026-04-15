-- Copyright (c) 2026 BliZzi1337. All rights reserved.
-- Unauthorized copying, modification, distribution or use of this
-- software, in whole or in part, without prior written permission
-- from the copyright holder is strictly prohibited.
--[[
    Data.lua - BliZzi Interrupts
    -----------------------------------------------------------------------
    Spec-first data architecture.

    Single source of truth: BIT.SPEC_REGISTRY
      One record per WoW spec ID describing everything about that spec's
      interrupt(s). All other lookup tables (ALL_INTERRUPTS, CLASS_INTERRUPTS,
      CLASS_INTERRUPT_LIST, SPEC_INTERRUPT_OVERRIDES, etc.) are compiled
      automatically from this registry at load time.

    To add / change a spell: edit SPEC_REGISTRY only.
    -----------------------------------------------------------------------
]]

BIT = BIT or {}

------------------------------------------------------------
-- Class colours (r, g, b) — purely visual, not spell data
------------------------------------------------------------
BIT.CLASS_COLORS = {
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    DRUID       = { 1.00, 0.49, 0.04 },
    EVOKER      = { 0.20, 0.58, 0.50 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    MAGE        = { 0.41, 0.80, 0.94 },
    MONK        = { 0.00, 1.00, 0.59 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    WARRIOR     = { 0.78, 0.61, 0.43 },
}

------------------------------------------------------------
-- Spec Registry  (single source of truth)
------------------------------------------------------------
-- Each entry describes one spec:
--   class       WoW class token (string)
--   spellID     primary interrupt spell ID (number)
--   name        spell display name
--   cd          base cooldown in seconds
--   icon        texture ID or path
--   noKick      true  = spec has no interrupt
--   isPet       true  = kick is cast by a pet
--   petSpellID  server-side pet spell ID that maps to this spell
--   extraKicks  array of { spellID, cd, name, icon, talentCheck? }
------------------------------------------------------------
local SPEC_REGISTRY = {

    -------------------- Death Knight --------------------
    [250] = { class="DEATHKNIGHT", spellID=47528, name="Mind Freeze",        cd=15, icon=237527 },
    [251] = { class="DEATHKNIGHT", spellID=47528, name="Mind Freeze",        cd=15, icon=237527 },
    [252] = { class="DEATHKNIGHT", spellID=47528, name="Mind Freeze",        cd=15, icon=237527 },

    -------------------- Demon Hunter --------------------
    [577]  = { class="DEMONHUNTER", spellID=183752, name="Disrupt", cd=15, icon=1305153 },
    [581]  = { class="DEMONHUNTER", spellID=183752, name="Disrupt", cd=15, icon=1305153 },
    [1480] = { class="DEMONHUNTER", spellID=183752, name="Disrupt", cd=15, icon=1305153 },

    -------------------- Druid --------------------
    [102] = { class="DRUID", spellID=78675,  name="Solar Beam",              cd=60,
              icon=252188 },
    [103] = { class="DRUID", spellID=106839, name="Skull Bash",              cd=15, icon=236946 },
    [104] = { class="DRUID", spellID=106839, name="Skull Bash",              cd=15, icon=236946 },
    [105] = { class="DRUID", noKick=true },

    -------------------- Evoker --------------------
    [1467] = { class="EVOKER", spellID=351338, name="Quell",                 cd=18, icon=4622469 },
    [1468] = { class="EVOKER", spellID=351338, name="Quell",                 cd=18, icon=4622469 },
    [1473] = { class="EVOKER", spellID=351338, name="Quell",                 cd=18, icon=4622469 },

    -------------------- Hunter --------------------
    [253] = { class="HUNTER", spellID=147362, name="Counter Shot",           cd=24, icon=249170  },
    [254] = { class="HUNTER", spellID=147362, name="Counter Shot",           cd=24, icon=249170  },
    [255] = { class="HUNTER", spellID=187707, name="Muzzle",                 cd=15, icon=1376045 },

    -------------------- Mage --------------------
    [62]  = { class="MAGE", spellID=2139, name="Counterspell",               cd=20, icon=135856  },
    [63]  = { class="MAGE", spellID=2139, name="Counterspell",               cd=20, icon=135856  },
    [64]  = { class="MAGE", spellID=2139, name="Counterspell",               cd=20, icon=135856  },

    -------------------- Monk --------------------
    [268] = { class="MONK", spellID=116705, name="Spear Hand Strike",        cd=15, icon=608940  },
    [269] = { class="MONK", spellID=116705, name="Spear Hand Strike",        cd=15, icon=608940  },
    [270] = { class="MONK", spellID=116705, name="Spear Hand Strike",        cd=15, icon=608940  },

    -------------------- Paladin --------------------
    [65]  = { class="PALADIN", noKick=true },
    [66]  = { class="PALADIN", spellID=96231, name="Rebuke",                 cd=15, icon=523893  },
    [70]  = { class="PALADIN", spellID=96231, name="Rebuke",                 cd=15, icon=523893  },

    -------------------- Priest --------------------
    [256] = { class="PRIEST", noKick=true },
    [257] = { class="PRIEST", noKick=true },
    [258] = { class="PRIEST", spellID=15487, name="Silence",                 cd=30, icon=458230  },

    -------------------- Rogue --------------------
    [259] = { class="ROGUE", spellID=1766, name="Kick",                      cd=15, icon=132219  },
    [260] = { class="ROGUE", spellID=1766, name="Kick",                      cd=15, icon=132219  },
    [261] = { class="ROGUE", spellID=1766, name="Kick",                      cd=15, icon=132219  },

    -------------------- Shaman --------------------
    [262] = { class="SHAMAN", spellID=57994, name="Wind Shear",              cd=12, icon=136018  },
    [263] = { class="SHAMAN", spellID=57994, name="Wind Shear",              cd=12, icon=136018  },
    [264] = { class="SHAMAN", spellID=57994, name="Wind Shear",              cd=30, icon=136018  }, -- Resto: 30s

    -------------------- Warlock --------------------
    [265] = { class="WARLOCK", spellID=19647, name="Spell Lock",             cd=24, icon=136174 },
    [266] = { class="WARLOCK", spellID=119914, name="Axe Toss",              cd=30,
              icon=236316,
              isPet=true, petSpellID=89766 },
    [267] = { class="WARLOCK", spellID=19647, name="Spell Lock",             cd=24, icon=136174 },

    -------------------- Warrior --------------------
    [71]  = { class="WARRIOR", spellID=6552, name="Pummel", cd=15, icon=132938 },
    [72]  = { class="WARRIOR", spellID=6552, name="Pummel", cd=15, icon=132938 },
    [73]  = { class="WARRIOR", spellID=6552, name="Pummel", cd=15, icon=132938 },
}

BIT.SPEC_REGISTRY = SPEC_REGISTRY

------------------------------------------------------------
-- Classes that keep their interrupt even as healer spec
------------------------------------------------------------
BIT.HEALER_KEEPS_KICK = {
    SHAMAN = true,  -- Restoration Shaman keeps Wind Shear
}

------------------------------------------------------------
-- Spell alias map
-- Maps IDs that fire differently on party vs own client
-- back to the canonical player-facing spell ID.
------------------------------------------------------------
local SPELL_ALIAS_MAP = {
    [1276467] = 132409,  -- Fel Ravager summon event  -> Spell Lock extra bar
    [89766]   = 119914,  -- Felguard Axe Toss (pet)   -> Axe Toss (player-facing)
    [132409]  = 132409,  -- identity: Spell Lock extra bar resolves cleanly
}

------------------------------------------------------------
-- Talent definitions
------------------------------------------------------------
local CD_REDUCTION_DEFS = {
    [388039] = { affects=147362, reduction=2,     name="Lone Survivor"      }, -- Hunter
    [412713] = { affects=351338, pctReduction=10, name="Interwoven Threads" }, -- Evoker
    [391271] = { affects=6552,   pctReduction=10, name="Seasoned Soldier", affectsExtraKicks=true }, -- Warrior (Pummel + Spell Reflection)
}

local CD_ON_KICK_DEFS = {
    [378848] = { reduction=3, name="Coldthirst" }, -- Death Knight
}

local EXTRA_KICK_DEFS = {}

------------------------------------------------------------
-- Compiler: derive all BIT.* lookup tables from SPEC_REGISTRY
------------------------------------------------------------
local allSpells          = {}
local classInterruptList = {}
local classDefault       = {}
local specOverrides      = {}
local specNoKick         = {}
local specExtraKicks     = {}

local function registerSpell(id, name, cd, icon)
    if not id or not name then return end
    if not allSpells[id] then
        allSpells[id] = { name=name, cd=cd, icon=icon }
    end
end

local function appendClassSpell(class, spellID)
    classInterruptList[class] = classInterruptList[class] or {}
    for _, v in ipairs(classInterruptList[class]) do
        if v == spellID then return end
    end
    classInterruptList[class][#classInterruptList[class]+1] = spellID
end

-- Phase 1: register spells, build classDefault and classInterruptList.
-- classDefault must be fully resolved before specOverrides can be computed,
-- because pairs() iteration order is non-deterministic — if a spec with a
-- non-default interrupt (e.g. Solar Beam, cd=60) is visited before the
-- lowest-CD spec (Skull Bash, cd=15), it would incorrectly see itself as
-- the class default and never appear in specOverrides.
for specID, spec in pairs(SPEC_REGISTRY) do
    local cls = spec.class
    if spec.noKick then
        specNoKick[specID] = true
    else
        local sid = spec.spellID
        registerSpell(sid, spec.name, spec.cd, spec.icon)
        appendClassSpell(cls, sid)

        -- Prefer lowest-CD, non-pet interrupt as class default.
        if not classDefault[cls] or (spec.cd < classDefault[cls].cd and not spec.isPet) then
            classDefault[cls] = { id=sid, cd=spec.cd, name=spec.name }
        end

        if spec.extraKicks then
            specExtraKicks[specID] = spec.extraKicks
            for _, ek in ipairs(spec.extraKicks) do
                registerSpell(ek.spellID, ek.name, ek.cd, ek.icon)
                appendClassSpell(cls, ek.spellID)
            end
        end
    end
end

-- Phase 2: now that classDefault is fully resolved, compute specOverrides.
for specID, spec in pairs(SPEC_REGISTRY) do
    if not spec.noKick then
        local cls = spec.class
        local sid = spec.spellID
        local def = classDefault[cls]
        if def and (sid ~= def.id or spec.cd ~= def.cd) then
            specOverrides[specID] = {
                id         = sid,
                cd         = spec.cd,
                name       = spec.name,
                isPet      = spec.isPet     or nil,
                petSpellID = spec.petSpellID or nil,
            }
        end
    end
end

------------------------------------------------------------
-- Publish onto BIT namespace
------------------------------------------------------------
BIT.ALL_INTERRUPTS           = allSpells
BIT.CLASS_INTERRUPT_LIST     = classInterruptList
BIT.CLASS_INTERRUPTS         = classDefault
BIT.SPEC_INTERRUPT_OVERRIDES = specOverrides
BIT.SPEC_NO_INTERRUPT        = specNoKick
BIT.SPEC_EXTRA_KICKS         = specExtraKicks
BIT.SPELL_ALIASES            = SPELL_ALIAS_MAP
BIT.CD_REDUCTION_TALENTS     = CD_REDUCTION_DEFS
BIT.CD_ON_KICK_TALENTS       = CD_ON_KICK_DEFS
BIT.EXTRA_KICK_TALENTS       = EXTRA_KICK_DEFS

------------------------------------------------------------
-- String-keyed mirrors for taint-safe lookups (WoW 12.0)
------------------------------------------------------------
BIT.ALL_INTERRUPTS_STR       = {}
BIT.SPELL_ALIASES_STR        = {}
BIT.CD_REDUCTION_TALENTS_STR = {}
BIT.CD_ON_KICK_TALENTS_STR   = {}
BIT.EXTRA_KICK_TALENTS_STR   = {}

for id, v in pairs(BIT.ALL_INTERRUPTS)       do BIT.ALL_INTERRUPTS_STR[tostring(id)]       = v end
for id, v in pairs(BIT.SPELL_ALIASES)        do BIT.SPELL_ALIASES_STR[tostring(id)]        = v end
for id, v in pairs(BIT.CD_REDUCTION_TALENTS) do BIT.CD_REDUCTION_TALENTS_STR[tostring(id)] = v end
for id, v in pairs(BIT.CD_ON_KICK_TALENTS)   do BIT.CD_ON_KICK_TALENTS_STR[tostring(id)]   = v end
for id, v in pairs(BIT.EXTRA_KICK_TALENTS)   do BIT.EXTRA_KICK_TALENTS_STR[tostring(id)]   = v end

for aliasID, targetID in pairs(BIT.SPELL_ALIASES) do
    if BIT.ALL_INTERRUPTS[targetID] then
        BIT.ALL_INTERRUPTS_STR[tostring(aliasID)] = BIT.ALL_INTERRUPTS[targetID]
    end
end

-- Name-keyed lookup: spell name (string) → { id, cd }
-- Used by UNIT_SPELLCAST_SENT which delivers an untainted spell name
-- instead of a tainted spellID, making it the most reliable detection
-- path for party members without the addon.
BIT.ALL_INTERRUPTS_BY_NAME = {}
for id, v in pairs(BIT.ALL_INTERRUPTS) do
    if v.name then
        -- Keep the entry with the lowest CD for this name (avoids Solar Beam
        -- overwriting Skull Bash if both happened to share a name).
        local existing = BIT.ALL_INTERRUPTS_BY_NAME[v.name]
        if not existing or v.cd < existing.cd then
            BIT.ALL_INTERRUPTS_BY_NAME[v.name] = { id = id, cd = v.cd, name = v.name }
        end
    end
end

------------------------------------------------------------
-- SavedVariables defaults
------------------------------------------------------------
BIT.DEFAULTS = {
    frameWidth        = 180,
    barHeight         = 30,
    locked            = false,
    hideOutOfCombat   = false,
    language          = "auto",
    barGap            = 0,
    showTitle         = true,
    showOwnSyncCD     = true,
    syncOnlyInGroup   = false,
    titleFontSize     = 16,
    titleAlign        = "RIGHT",
    titleColorR       = 1,
    titleColorG       = 1,
    titleColorB       = 1,
    alpha             = 1.0,
    nameFontSize      = 0,
    readyFontSize     = 0,
    showName          = true,
    showReady         = true,
    clickToAnnounce      = false,
    syncCdClickAnnounce  = false,
    announceChannel      = "PARTY",
    soundEnabled         = false,
    soundKickSuccess     = "None",
    soundKickFailed      = "None",
    soundOwnKickOnly     = true,
    showInDungeon     = true,
    showInRaid        = false,
    showInOpenWorld   = true,
    showInArena       = false,
    showInBG          = false,
    fontPath          = nil,
    fontName          = nil,
    barTexturePath    = "Interface\\BUTTONS\\WHITE8X8",
    barTextureName    = "Flat",
    nameOffsetX       = 0,
    nameOffsetY       = 0,
    antiSpam          = true,
    iconSide          = "LEFT",
    barFillMode       = "DRAIN",
    sortMode          = "NONE",
    useClassColors    = true,
    customColorR      = 0.4,
    customColorG      = 0.8,
    customColorB      = 1.0,
    customBgColorR    = 0.1,
    customBgColorG    = 0.1,
    customBgColorB    = 0.1,
    borderTexturePath = nil,
    borderTextureName = "None",
    borderSize        = 2,
    borderColorR      = 0,
    borderColorG      = 0,
    borderColorB      = 0,
    borderColorA      = 1,
    disabledSpells    = {},
    rotationEnabled   = false,
    rotationOrder     = {},
    rotationIndex     = 1,
    growUpward        = false,
    frameScale        = 100,
    readyColorR       = 0.2,
    readyColorG       = 1.0,
    readyColorB       = 0.2,
    fontOutline       = "OUTLINE",  -- "NONE", "OUTLINE", "THICKOUTLINE"
    shadowOffsetX     = 0,
    shadowOffsetY     = 0,
    cdOffsetX         = 0,
    cdOffsetY         = 0,
    showFailedKick    = true,
    showWelcome       = true,
    showSyncCDs       = true,
    syncCdModeGroup      = "ATTACH",   -- mode when in a party/group: "WINDOW", "ATTACH", "BARS"
    syncCdModeRaid       = "BARS",     -- mode when in a raid: "WINDOW", "ATTACH", "BARS"
    syncCdWindowCompact  = true,       -- Standalone Window: true = no background/title, just name+icons
    syncCdFrameProvider  = "AUTO",     -- "AUTO", "ELVUI", "DANDERS", "GRID2", "BLIZZARD"
    syncCdAttachPos      = "LEFT",     -- "LEFT", "RIGHT", "TOP", "BOTTOM"
    syncCdIconSize    = 28,         -- icon size in pixels
    syncCdIconSpacing = 4,          -- gap between icons in pixels
    syncCdTooltip     = true,
    syncCdGlow        = true,          -- show buff-active glow overlay on Party CD icons
    syncCdCounterSize = 14,         -- CD countdown text size
    syncCdTimeFormat  = "MMSS",     -- "SECONDS" = 90  /  "MMSS" = 1:30
    syncCdDisabled    = { [10060] = true },   -- Power Infusion: not trackable by default
    myCustomName      = "",         -- own nickname visible to other addon users
    showCustomNames   = true,       -- display custom names set by other players
    titleOffsetY           = 3,
    -- Group Bars mode settings
    syncCdBarsLocked       = false,
    syncCdShowDEF          = true,   -- show defensive CD icons in Party CDs
    syncCdShowDMG          = true,   -- show offensive/damage CD icons in Party CDs
    syncCdCatVer           = 0,      -- bumped when a category toggle changes (forces icon rebuild)
    syncCdCatRowDMG        = "1",   -- which row Offensive CDs appear on (Attach mode)
    syncCdCatRowDEF        = "2",   -- which row Defensive CDs appear on (Attach mode)
    -- syncCdCatRowCC removed (CC tracking removed)
    syncCdAttachRowGap     = 4,     -- vertical spacing between rows (Attach mode)
    syncCdAttachOffsetX    = 0,     -- additional X offset for the attached bar
    syncCdAttachOffsetY    = 0,     -- additional Y offset for the attached bar
    syncCdTopLayout        = "COLUMNS", -- TOP attach: "ROWS" or "COLUMNS"
    syncCdBottomLayout     = "ROWS",    -- BOTTOM attach: "ROWS" or "COLUMNS"
    minimapButton          = true,     -- show minimap button
    minimapPos             = 225,      -- angle in degrees around minimap
    -- Icon Only mode (interrupt tracker)
    iconOnlyMode           = false,    -- show only icons with CD counter, no bars/names
    iconOnlySize           = 36,       -- icon size in Icon Only mode
    iconOnlySpacing        = 4,        -- gap between icons in Icon Only mode
    iconOnlyPerRow         = 7,        -- max icons per row before wrapping
    iconOnlyCounterSize    = 14,       -- CD countdown font size on icon
    iconOnlyGrowth         = "RIGHT",  -- "RIGHT" or "LEFT" — icon growth direction
}
