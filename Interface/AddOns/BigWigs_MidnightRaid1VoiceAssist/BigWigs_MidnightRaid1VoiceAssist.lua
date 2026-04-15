local addonName, ns = ...
local db
local encounterID = 0

local LSM = LibStub("LibSharedMedia-3.0", true)
if not LSM then return end
local MediaType_SOUND = LSM.MediaType.SOUND

--------------------------------------------------------------------------------
-- PERMANENT DEFAULTS
--------------------------------------------------------------------------------
local defaultMappingMale = {
     -- Imperator Averzian
	["1251361"] = { { sound = "!Adds_Soon", trigger = 5, label="Shadows Advance", enabled = true} },
    ["1249262"] = { 
		{ sound = "!Soak_Soon", trigger = 5, label="Umbral Colapse", enabled = true},
		{ sound = "!Soak", trigger = 1, label="Umbral Colapse", enabled = true}
	},
	["1260712"] = { 
        { sound = "!Get_Ready_To_Dodge", trigger = 5, label="Oblivions Wrath", enabled = true },
        { sound = "!Dodge", trigger = 1, label="Oblivions Wrath", enabled = true } 
    },
    ["1258883"] = { { sound = "!Knockback_Incoming", trigger = 5, label="Void Fall", enabled = true} },

    -- Vorasius 
    ["1256855"] = { { sound = "!Beam_Incoming_Look_At_Boss", trigger = 5, label="Void Breath", enabled = true } },
    ["1254199"] = { { sound = "!Adds_Soon", trigger = 5, label="Parasite Expulsion", enabled = true } },
    ["1241692"] = { { sound = "!Rings_Incoming", trigger = 5, label="Shadowclaw Slam", enabled = true } },
    ["1260052"] = { { sound = "!Knockback_Incoming", trigger = 5, label="Primordial Roar", enabled = true } },

    -- Fallen King Salhadaar
    ["1247738"] = { { sound = "!Orbs_Soon", trigger = 5, label="Void Convergence", enabled = true } },
    ["1246175"] = { { sound = "!Damage_Amp_Soon", trigger = 5, label="Entropic Unraveling", enabled = true } },
    ["1250803"] = { { sound = "!Dodge_Spikes_Soon", trigger = 5, label="Shattering Twilight", enabled = true  } },
    ["1254081"] = { { sound = "!Interrupt_Incoming", trigger = 3, label="Fractured Projection", enabled = true } },

    -- Vaelgor & Ezzorak
    ["1249748"] = { { sound = "!Get_In_Barrier_Soon", trigger = 5, label="Midnight Flames", enabled = true  } },
    ["1262623"] = { { sound = "!Frontal_Beam_And_Pull_In_Soon", trigger = 5, label="Nullbeam", enabled = true } },
    ["1244221"] = { { sound = "!Breath_Soon", trigger = 5, label="Dread Breath", enabled = true } },
    ["1245391"] = { { sound = "!Soak_Orb_Soon", trigger = 5, label="Gloom", enabled = true } },
    ["1244917"] = { { sound = "!Loose_Stack_And_Adds_Soon", trigger = 5, label="Void Howl", enabled = true } },

    -- Lightblinded Vanguard
    ["1248449"] = { { sound = "!Run_Away_From_Boss", trigger = 5, label="Aura Of Wrath", enabled = true } },
    ["1248983"] = { { sound = "!Soak_Player_Circles_And_Dodge_Soon", trigger = 5, label="Execution Sentence", enabled = true } },
    ["1246162"] = { { sound = "!Run_Away_And_Dodge_Soon", trigger = 5, label="Aura Of Devotion", enabled = true } },
	["1248644"] = { 
        { sound = "!Get_Ready_To_Dodge", trigger = 5, label="Divine Toll", enabled = true  },
        { sound = "!Dodge", trigger = 1, label="Divine Toll", enabled = true  } 
    },
    ["1248451"] = { { sound = "!Run_Away_And_Dont_Hit_Senn", trigger = 5, label="Aura Of Peace", enabled = true } },
    ["1248674"] = { 
		{ sound = "!Bait_Charge", trigger = 5, label="Sacred Shield", enabled = true }, 
		{ sound = "!Break_Shield", trigger = 1, label="Sacred Shield", enabled = true } 
	},
    ["1276243"] = { { sound = "!Add_Soon", trigger = 5, label="Zealous Spirit", enabled = true } },
	["empowered_divine_storm"] = { { sound = "!Tornadoes_Soon", trigger = 5, label="Empowered Divine Storm", enabled = true } },


    -- Chimaerus
    ["1262289"] = { { sound = "!Tank_Soak_Soon", trigger = 5, label="Alndust Upheaval", enabled = true } },
    ["1258610"] = { { sound = "!Adds_Soon", trigger = 5, label="Rift Emergence", enabled = true } },
    ["1272726"] = { { sound = "!Frontal_Soon", trigger = 5, label="Rending Tear", enabled = true } },
    ["1245396"] = { { sound = "!Knockback_Incoming", trigger = 1, label="Consume", enabled = true } },
    ["1245486"] = { { sound = "!Bait_Breath", trigger = 5, label="Corrupted Devastation", enabled = true } },
    ["1245406"] = { { sound = "!Boss_Landing_Soon_-_Use_Defensive", trigger = 5, label="Ravenous Dive", enabled = true } },
	["1264756"] = { { sound = "!Madness_Debuff_Soon", trigger = 5, label="Rift Madness", enabled = true } },

    -- Belo'ren
	["1242515"] = { { sound = "!Color_Swap_Soon", trigger = 5, label="Voidlight Convergence", enabled = true } },
    ["1241282"] = { { sound = "!Add_Soon", trigger = 5, label="Embers Of Beloren", enabled = true } },
    ["light_void_dive"] = { 
		{ sound = "!Soak_Soon", trigger = 5, label="Light/Void Dive", enabled = true},
		{ sound = "!Soak", trigger = 1, label="Light/Void Dive", enabled = true}
	},
	["1242981"] = { { sound = "!Soak_Your_Colored_Orb_Soon", trigger = 5, label="Radiant Echoes", enabled = true } },
    ["1242260"] = { { sound = "!Soak_Player_Lines_Soon", trigger = 5, label="Infused Quills", enabled = true } },
    ["1246709"] = { { sound = "!Boss_Landing_Soon", trigger = 5, label="Death Drop", enabled = true } },


    -- Alleria
    ["1233602"] = { { sound = "!Arrows_Incoming", trigger = 5, label="Silverstrike Arrow", enabled = true  } },
    ["1243743"] = { { sound = "!Player_Silence_Incoming", trigger = 1, label="Interrupting Tremor", enabled = true  } },
    ["1237614"] = { { sound = "!Line_Incoming", trigger = 5, label="Ranger Captins Mark", enabled = true } },
	["1246918"] = { { sound = "!Break_Shield_Soon", trigger = 5, label="Cosmic Barrier", enabled = true  } },
    ["1245874"] = { { sound = "!Get_Ready_To_Dodge", trigger = 5, label="Orbiting Matter", enabled = true } },
	["1255368"] = { { sound = "!Bait", trigger = 5, label="Void Expulsion", enabled = true } },
	["1238843"] = { { sound = "!Next_Platform", trigger = 5, label="Devouring Cosmos", enabled = true } },
	
	-- Midnight
	["1279420"] = { { sound = "!Beams_Incoming", trigger = 5, label="Dark Quasar", enabled = true } },
	["1253915"] = { { sound = "!Glaives_Incoming_Look_At_Boss", trigger = 5, label="Heaven's Glaives", enabled = true } },
	["1249620"] = { { sound = "!Memory_Game_Soon", trigger = 5, label="Deaths Dirge", enabled = true } },
	["1251386"] = { 
		{ sound = "!Shield_And_Crystal_Soon", trigger = 5, label="Safeguard Prism", enabled = true},
		{ sound = "!CC_Adds", trigger = 1, label="Safeguard Prism", enabled = true}
	},
	["1284525"] = { 
		{ sound = "!Beam_Soak_Soon", trigger = 5, label="Galvanize", enabled = true},
		{ sound = "!Soak", trigger = 1, label="Galvanize", enabled = true}
	},
	["1282412"] = { 
        { sound = "!Get_Ready_To_Dodge", trigger = 5, label="Core Harvest", enabled = true  },
        { sound = "!Dodge", trigger = 1, label="Core Harvest", enabled = true  } 
    },
	["1250898"] = { 
        { sound = "!Beam_Incoming_Get_Ready_To_Move", trigger = 5, label="The Dark Archangel", enabled = true  },
        { sound = "!Move", trigger = 1, label="The Dark Archangel", enabled = true  } 
    },
	["1266388"] = { { sound = "!Find_Empty_Space", trigger = 5, label="Dark Constellation", enabled = true } },
    ["1266897"] = { 
		{ sound = "!Soak_Soon", trigger = 5, label="Light Siphon", enabled = true},
		{ sound = "!Soak", trigger = 1, label="Light Siphon", enabled = true}
	},

	-- Misc
    ["stages"]  = { { sound = "!Phasing_Soon", trigger = 5, label="Phase Change", enabled = true } },
}

local defaultMappingFemale = {
     -- Imperator Averzian
	["1251361"] = { { sound = "!Adds_Soon_V2", trigger = 5, label="Shadows Advance", enabled = true} },
    ["1249262"] = { 
		{ sound = "!Soak_Soon_V2", trigger = 5, label="Umbral Colapse", enabled = true},
		{ sound = "!Soak_V2", trigger = 1, label="Umbral Colapse", enabled = true}
	},
	["1260712"] = { 
        { sound = "!Get_Ready_To_Dodge_V2", trigger = 5, label="Oblivions Wrath", enabled = true },
        { sound = "!Dodge_V2", trigger = 1, label="Oblivions Wrath", enabled = true } 
    },
    ["1258883"] = { { sound = "!Knockback_Incoming_V2", trigger = 5, label="Void Fall", enabled = true} },

    -- Vorasius 
    ["1256855"] = { { sound = "!Beam_Incoming_Look_At_Boss_V2", trigger = 5, label="Void Breath", enabled = true } },
    ["1254199"] = { { sound = "!Adds_Soon_V2", trigger = 5, label="Parasite Expulsion", enabled = true } },
    ["1241692"] = { { sound = "!Rings_Incoming_V2", trigger = 5, label="Shadowclaw Slam", enabled = true } },
    ["1260052"] = { { sound = "!Knockback_Incoming_V2", trigger = 5, label="Primordial Roar", enabled = true } },

    -- Fallen King Salhadaar
    ["1247738"] = { { sound = "!Orbs_Soon_V2", trigger = 5, label="Void Convergence", enabled = true } },
    ["1246175"] = { { sound = "!Damage_Amp_Soon_V2", trigger = 5, label="Entropic Unraveling", enabled = true } },
    ["1250803"] = { { sound = "!Dodge_Spikes_Soon_V2", trigger = 5, label="Shattering Twilight", enabled = true  } },
    ["1254081"] = { { sound = "!Interrupt_Incoming_V2", trigger = 3, label="Fractured Projection", enabled = true } },

    -- Vaelgor & Ezzorak
    ["1249748"] = { { sound = "!Get_In_Barrier_Soon_V2", trigger = 5, label="Midnight Flames", enabled = true  } },
    ["1262623"] = { { sound = "!Frontal_Beam_And_Pull_In_Soon_V2", trigger = 5, label="Nullbeam", enabled = true } },
    ["1244221"] = { { sound = "!Breath_Soon_V2", trigger = 5, label="Dread Breath", enabled = true } },
    ["1245391"] = { { sound = "!Soak_Orb_Soon_V2", trigger = 5, label="Gloom", enabled = true } },
    ["1244917"] = { { sound = "!Loose_Stack_And_Adds_Soon_V2", trigger = 5, label="Void Howl", enabled = true } },

    -- Lightblinded Vanguard
    ["1248449"] = { { sound = "!Run_Away_From_Boss_V2", trigger = 5, label="Aura Of Wrath", enabled = true } },
    ["1248983"] = { { sound = "!Soak_Player_Circles_And_Dodge_Soon_V2", trigger = 5, label="Execution Sentence", enabled = true } },
    ["1246162"] = { { sound = "!Run_Away_And_Dodge_Soon_V2", trigger = 5, label="Aura Of Devotion", enabled = true } },
	["1248644"] = { 
        { sound = "!Get_Ready_To_Dodge_V2", trigger = 5, label="Divine Toll", enabled = true  },
        { sound = "!Dodge_V2", trigger = 1, label="Divine Toll", enabled = true  } 
    },
    ["1248451"] = { { sound = "!Run_Away_And_Dont_Hit_Senn_V2", trigger = 5, label="Aura Of Peace", enabled = true } },
    ["1248674"] = { 
		{ sound = "!Bait_Charge_V2", trigger = 5, label="Sacred Shield", enabled = true }, 
		{ sound = "!Break_Shield_V2", trigger = 1, label="Sacred Shield", enabled = true } 
	},
    ["1276243"] = { { sound = "!Add_Soon_V2", trigger = 5, label="Zealous Spirit", enabled = true } },
	["empowered_divine_storm"] = { { sound = "!Tornadoes_Soon_V2", trigger = 5, label="Empowered Divine Storm", enabled = true } },


    -- Chimaerus
    ["1262289"] = { { sound = "!Tank_Soak_Soon_V2", trigger = 5, label="Alndust Upheaval", enabled = true } },
    ["1258610"] = { { sound = "!Adds_Soon_V2", trigger = 5, label="Rift Emergence", enabled = true } },
    ["1272726"] = { { sound = "!Frontal_Soon_V2", trigger = 5, label="Rending Tear", enabled = true } },
    ["1245396"] = { { sound = "!Knockback_Incoming_V2", trigger = 1, label="Consume", enabled = true } },
    ["1245486"] = { { sound = "!Bait_Breath_V2", trigger = 5, label="Corrupted Devastation", enabled = true } },
    ["1245406"] = { { sound = "!Boss_Landing_Soon_-_Use_Defensive_V2", trigger = 5, label="Ravenous Dive", enabled = true } },
	["1264756"] = { { sound = "!Madness_Debuff_Soon_V2", trigger = 5, label="Rift Madness", enabled = true } },

    -- Belo'ren
	["1242515"] = { { sound = "!Color_Swap_Soon_V2", trigger = 5, label="Voidlight Convergence", enabled = true } },
    ["1241282"] = { { sound = "!Add_Soon_V2", trigger = 5, label="Embers Of Beloren", enabled = true } },
    ["light_void_dive"] = { 
		{ sound = "!Soak_Soon_V2", trigger = 5, label="Light/Void Dive", enabled = true},
		{ sound = "!Soak_V2", trigger = 1, label="Light/Void Dive", enabled = true}
	},
	["1242981"] = { { sound = "!Soak_Your_Colored_Orb_Soon_V2", trigger = 5, label="Radiant Echoes", enabled = true } },
    ["1242260"] = { { sound = "!Soak_Player_Lines_Soon_V2", trigger = 5, label="Infused Quills", enabled = true } },
    ["1246709"] = { { sound = "!Boss_Landing_Soon_V2", trigger = 5, label="Death Drop", enabled = true } },

    -- Alleria
    ["1233602"] = { { sound = "!Arrows_Incoming_V2", trigger = 5, label="Silverstrike Arrow", enabled = true  } },
    ["1243743"] = { { sound = "!Player_Silence_Incoming_V2", trigger = 1, label="Interrupting Tremor", enabled = true  } },
    ["1237614"] = { { sound = "!Line_Incoming_V2", trigger = 5, label="Ranger Captins Mark", enabled = true } },
	["1246918"] = { { sound = "!Break_Shield_Soon_V2", trigger = 5, label="Cosmic Barrier", enabled = true  } },
    ["1245874"] = { { sound = "!Get_Ready_To_Dodge_V2", trigger = 5, label="Orbiting Matter", enabled = true } },
	["1255368"] = { { sound = "!Bait_V2", trigger = 5, label="Void Expulsion", enabled = true } },
	["1238843"] = { { sound = "!Next_Platform_V2", trigger = 5, label="Devouring Cosmos", enabled = true } },
	
	-- Midnight
	["1279420"] = { { sound = "!Beams_Incoming_V2", trigger = 5, label="Dark Quasar", enabled = true } },
	["1253915"] = { { sound = "!Glaives_Incoming_Look_At_Boss_V2", trigger = 5, label="Heaven's Glaives", enabled = true } },
	["1249620"] = { { sound = "!Memory_Game_Soon_V2", trigger = 5, label="Deaths Dirge", enabled = true } },
	["1251386"] = { 
		{ sound = "!Shield_And_Crystal_Soon_V2", trigger = 5, label="Safeguard Prism", enabled = true},
		{ sound = "!CC_Adds_V2", trigger = 1, label="Safeguard Prism", enabled = true}
	},
	["1284525"] = { 
		{ sound = "!Beam_Soak_Soon_V2", trigger = 5, label="Galvanize", enabled = true},
		{ sound = "!Soak_V2", trigger = 1, label="Galvanize", enabled = true}
	},
	["1282412"] = { 
        { sound = "!Get_Ready_To_Dodge_V2", trigger = 5, label="Core Harvest", enabled = true  },
        { sound = "!Dodge_V2", trigger = 1, label="Core Harvest", enabled = true  } 
    },
	["1250898"] = { 
        { sound = "!Beam_Incoming_Get_Ready_To_Move_V2", trigger = 5, label="The Dark Archangel", enabled = true  },
        { sound = "!Move_V2", trigger = 1, label="The Dark Archangel", enabled = true  } 
    },
	["1266388"] = { { sound = "!Find_Empty_Space_V2", trigger = 5, label="Dark Constellation", enabled = true } },
    ["1266897"] = { 
		{ sound = "!Soak_Soon_V2", trigger = 5, label="Light Siphon", enabled = true},
		{ sound = "!Soak_V2", trigger = 1, label="Light Siphon", enabled = true}
	},

	-- Misc
    ["stages"]  = { { sound = "!Phasing_Soon_V2", trigger = 5, label="Phase Change", enabled = true } },
}

--------------------------------------------------------------------------------
-- TIMER TRACKING
--------------------------------------------------------------------------------
local activeTimers = {}

local function ResetEncounter()
    encounterID = encounterID + 1
end
--------------------------------------------------------------------------------
-- DB INIT
--------------------------------------------------------------------------------
local function PrepareEntry(spellID, entry)
    local cleanLabel = (entry.label or "Alert"):gsub("%s+", "")
    entry.dbKey = tostring(spellID) .. "_" .. cleanLabel .. "_" .. (entry.trigger or 0)
    return entry
end

local function InitDB()
    BigWigs_MidnightRaid1VoiceAssistDB = BigWigs_MidnightRaid1VoiceAssistDB or {}
    db = BigWigs_MidnightRaid1VoiceAssistDB

    db.pos = db.pos or { point = "CENTER", x = 0, y = 0 }
    db.soundEnabled = db.soundEnabled or {}
    db.soundChoice = db.soundChoice or {}
    db.activeCues = db.activeCues or {}
    db.initialized = db.initialized or false
	db.voiceGender = db.voiceGender or "male"

    if not db.initialized then
        local source = (db.voiceGender == "female") and defaultMappingFemale or defaultMappingMale
		for spellID, entries in pairs(source) do
            local sID = tostring(spellID)
            db.activeCues[sID] = {}

            for _, entry in ipairs(entries) do
                table.insert(db.activeCues[sID], PrepareEntry(sID, {
                    sound = entry.sound,
                    trigger = entry.trigger,
                    label = entry.label,
                    enabled = entry.enabled
                }))
            end
        end

        db.initialized = true
    else
        for sID, entries in pairs(db.activeCues) do
            for _, entry in ipairs(entries) do
                if not entry.dbKey then PrepareEntry(sID, entry) end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- RESET LOGIC
--------------------------------------------------------------------------------

local function CheckForMissing()
    local source = (db.voiceGender == "female") and defaultMappingFemale or defaultMappingMale
    for sID, entries in pairs(source) do
        if not db.activeCues[tostring(sID)] then return true end
        for _, def in ipairs(entries) do
            local found = false
            for _, cur in ipairs(db.activeCues[tostring(sID)]) do
                if cur.trigger == def.trigger and cur.label == def.label then 
                    found = true 
                    break 
                end
            end
            if not found then return true end
        end
    end
    return false
end

local function ResetToDefaults()
    local source = (db.voiceGender == "female") and defaultMappingFemale or defaultMappingMale
    for spellID, entries in pairs(source) do
        local sID = tostring(spellID)
        db.activeCues[sID] = db.activeCues[sID] or {}
        for _, defaultEntry in ipairs(entries) do
            local found = false
            for _, currentEntry in ipairs(db.activeCues[sID]) do
                if currentEntry.trigger == defaultEntry.trigger and currentEntry.label == defaultEntry.label then
                    found = true
                    break
                end
            end
            if not found then
                local newEntry = {
                    sound = defaultEntry.sound,
                    trigger = defaultEntry.trigger,
                    label = defaultEntry.label,
                    enabled = defaultEntry.enabled
                }
                PrepareEntry(sID, newEntry)
                table.insert(db.activeCues[sID], newEntry)
            end
        end
    end
    ReloadUI() 
end

--------------------------------------------------------------------------------
-- UI HELPERS
--------------------------------------------------------------------------------
local function CreateToggle(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(40, 18)
    btn:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    btn.text:SetAllPoints()
    return btn
end

local function DeleteAllCues()
    wipe(db.soundEnabled)
    wipe(db.soundChoice)
    wipe(db.activeCues)
end

--------------------------------------------------------------------------------
-- MAIN UI FRAME
--------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "FoxLabMainFrame", UIParent, "BackdropTemplate")
frame:SetSize(580, 450)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetFrameStrata("HIGH")
frame:Hide()

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db.pos.point, db.pos.x, db.pos.y = point, x, y
end)

frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
frame:SetBackdropBorderColor(0.4, 0.8, 1)
frame.bg = frame:CreateTexture(nil, "BACKGROUND")
frame.bg:SetAllPoints()
frame.bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetPoint("TOPLEFT", 10, -10)
frame.title:SetText("Fox Lab Studio")

frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
frame.closeBtn:SetSize(20, 20) 
frame.closeBtn:SetPoint("TOPRIGHT", -5, -8)
frame.closeBtn:SetScript("OnClick", function() frame:Hide() end)

frame.resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
frame.resetBtn:SetSize(110, 22)
frame.resetBtn:SetPoint("TOPRIGHT", -35, -8)
frame.resetBtn:SetText("Sync Defaults")

-- Visual Update for the Button
local function UpdateResetButtonVisuals()
    if CheckForMissing() then
       frame.resetBtn.Text:SetTextColor(0, 1, 0)
        frame.resetBtn.hasUpdates = true
    else
        frame.resetBtn.hasUpdates = false
    end
end

frame.resetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reset / Sync Defaults")
    if self.hasUpdates then
        GameTooltip:AddLine("NEW defaults are available!", 0, 1, 0)
        GameTooltip:AddLine("Clicking this will ADD missing cues to your list.", 1, 1, 1)
    else
        GameTooltip:AddLine("All default cues are already in your list.", 1, 1, 1)
    end
    GameTooltip:Show()
end)
frame.resetBtn:SetScript("OnLeave", GameTooltip_Hide)
frame.resetBtn:SetScript("OnClick", function() StaticPopup_Show("MVA_RESET") end)
frame:HookScript("OnShow", UpdateResetButtonVisuals)

frame.deleteAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
frame.deleteAllBtn:SetSize(110, 22)
frame.deleteAllBtn:SetPoint("RIGHT", frame.resetBtn, "LEFT", -5, 0)
frame.deleteAllBtn:SetText("Delete All")
frame.deleteAllBtn:SetScript("OnClick", function()
    StaticPopup_Show("MVA_DELETE_ALL")
end)

StaticPopupDialogs["MVA_RESET"] = {
    text = "Reset all settings. Choose a voice gender or cancel.",
    button1 = "Male",
    button2 = "Female",
    button3 = "Cancel", 
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,

    -- Triggers when "Male" (button1) is clicked
    OnAccept = function()
        db.voiceGender = "male"
        ResetToDefaults()
        ReloadUI()
    end,

    -- Triggers when "Female" (button2) is clicked
    OnCancel = function()
        db.voiceGender = "female"
        ResetToDefaults()
        ReloadUI()
    end,

    -- Triggers when "Cancel" (button3) is clicked
    OnAlt = function()
        -- Do nothing, just closes the popup
    end,
}

StaticPopupDialogs["MVA_DELETE_ALL"] = {
    text = "Delete ALL cues and settings?",
    button1 = "Yes",
    button2 = "No",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function()
        DeleteAllCues()
        ReloadUI()
    end,
}
--------------------------------------------------------------------------------
-- ROW CONSTRUCTION
--------------------------------------------------------------------------------
local soundPicker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
soundPicker:SetSize(200, 260)
soundPicker:SetFrameStrata("TOOLTIP") 
soundPicker:SetFrameLevel(100)
soundPicker:Hide()
soundPicker:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
soundPicker:SetBackdropColor(0, 0, 0, 0.95)
soundPicker:SetBackdropBorderColor(0.4, 0.8, 1) 

soundPicker.scroll = CreateFrame("ScrollFrame", nil, soundPicker, "UIPanelScrollFrameTemplate")
soundPicker.scroll:SetPoint("TOPLEFT", 4, -4)
soundPicker.scroll:SetPoint("BOTTOMRIGHT", -26, 4)

soundPicker.content = CreateFrame("Frame", nil, soundPicker.scroll)
soundPicker.content:SetSize(170, 1)
soundPicker.scroll:SetScrollChild(soundPicker.content)

local function OpenSoundPicker(parent, currentKey, updateTextFunc)
    if soundPicker:IsShown() and soundPicker.owner == parent then 
        soundPicker:Hide() 
        return 
    end

    soundPicker:SetParent(parent)
    soundPicker:ClearAllPoints()
    soundPicker:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    soundPicker.owner = parent
    soundPicker:Show()

	if not soundPicker._initialized then
		soundPicker:RegisterEvent("PLAYER_REGEN_DISABLED")
		soundPicker:SetScript("OnEvent", function(self)
			self:Hide()
		end)
		soundPicker._initialized = true
	end

	soundPicker:SetScript("OnUpdate", function(self)
		if not self:IsShown() then return end

		if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
			if not self:IsMouseOver() and not self.owner:IsMouseOver() then
				self:Hide()
			end
		end
	end)

    local children = { soundPicker.content:GetChildren() }
    for _, child in ipairs(children) do child:Hide() end

    local sounds = LSM:List(MediaType_SOUND)
    soundPicker.content.buttons = soundPicker.content.buttons or {}

    for i, name in ipairs(sounds) do
        local btn = soundPicker.content.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, soundPicker.content)
            btn:SetSize(165, 18)
            btn:SetPoint("TOPLEFT", 0, -(i-1) * 18)
            
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text:SetPoint("LEFT", 4, 0)
            btn.text:SetPoint("RIGHT", -4, 0)
            btn.text:SetJustifyH("LEFT")
            btn.text:SetWordWrap(false)
            
            local tex = btn:CreateTexture(nil, "HIGHLIGHT")
            tex:SetAllPoints()
            tex:SetColorTexture(1, 1, 1, 0.1)
            btn:SetHighlightTexture(tex)
            
            soundPicker.content.buttons[i] = btn
        end

        btn.text:SetText(name)
        btn:SetScript("OnClick", function()
            db.soundChoice[currentKey] = name
            updateTextFunc(name)
            local path = LSM:Fetch(MediaType_SOUND, name)
            if path then PlaySoundFile(path, "Master") end
            soundPicker:Hide()
        end)
        btn:Show()
    end

    soundPicker.content:SetHeight(#sounds * 18)
    soundPicker.scroll:SetVerticalScroll(0)
end


local function CreateRow(parent, spellID, cfg, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(520, 24)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 26)

    local cleanLabel = (cfg.label or "Alert"):gsub("%s+", "")
    local key = cfg.dbKey or (tostring(spellID) .. "_" .. cleanLabel .. "_" .. (cfg.trigger or 0))

    ---------------------------------------------------------
    -- SPELL ID
    ---------------------------------------------------------
    local idTxt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    idTxt:SetPoint("LEFT", 5, 0)
    idTxt:SetWidth(65) 
    idTxt:SetJustifyH("LEFT")
    idTxt:SetWordWrap(false)
    idTxt:SetText(spellID)

    ---------------------------------------------------------
    -- LABEL 
    ---------------------------------------------------------
    local fullLabelText = string.format("%s (%ds)", cfg.label or "Alert", cfg.trigger or 0)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 75, 0)
    label:SetWidth(160) 
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(fullLabelText)

    ---------------------------------------------------------
    -- TOOLTIP SENSOR
    ---------------------------------------------------------
    local sensor = CreateFrame("Frame", nil, row)
    sensor:SetPoint("TOPLEFT", idTxt, "TOPLEFT")
    sensor:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT")
    sensor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Cue Information", 1, 1, 1)
        GameTooltip:AddLine(" ") -- Spacer
        GameTooltip:AddDoubleLine("Spell ID / Name:", spellID, 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Label:", cfg.label or "Alert", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Trigger Time:", (cfg.trigger or 0) .. "s before expiry", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:Show()
    end)
    sensor:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ---------------------------------------------------------
    -- SOUND PICKER BUTTON
    ---------------------------------------------------------
    local soundBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    soundBtn:SetSize(170, 20)
    soundBtn:SetPoint("LEFT", 240, 0)
    soundBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", 
        edgeFile = "Interface\\Buttons\\WHITE8X8", 
        edgeSize = 1,
    })
    soundBtn:SetBackdropColor(0.1, 0.1, 0.1, 1)
    soundBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    soundBtn.text = soundBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soundBtn.text:SetPoint("LEFT", 5, 0)
    soundBtn.text:SetPoint("RIGHT", -5, 0)
    soundBtn.text:SetJustifyH("LEFT")
    soundBtn.text:SetWordWrap(false)  
    soundBtn.text:SetText(db.soundChoice[key] or cfg.sound or "Select Sound")

    soundBtn:SetScript("OnClick", function(self)
        OpenSoundPicker(self, key, function(newName) self.text:SetText(newName) end)
    end)

    ---------------------------------------------------------
    -- TEST SOUND BUTTON
    ---------------------------------------------------------
    local test = CreateFrame("Button", nil, row)
    test:SetSize(20, 20)
    test:SetPoint("LEFT", 420, 0)
    local tex = test:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Common\\VoiceChat-Speaker")
    tex:SetAllPoints(test)
    test:SetNormalTexture(tex)
    
    test:SetScript("OnClick", function()
        local selected = db.soundChoice[key] or cfg.sound
        local path = LibStub("LibSharedMedia-3.0"):Fetch("sound", selected)
        if path then PlaySoundFile(path, "Master") end
    end)

    ---------------------------------------------------------
    -- ENABLE/DISABLE TOGGLE
    ---------------------------------------------------------
    local toggle = CreateToggle(row)
    toggle:SetPoint("LEFT", 455, 0)
    
    local function UpdateToggle()
        local enabled = db.soundEnabled[key] ~= false
        toggle.text:SetText(enabled and "ON" or "OFF")
        toggle.text:SetTextColor(enabled and 0 or 1, enabled and 1 or 0, 0)
    end

    toggle:SetScript("OnClick", function()
        db.soundEnabled[key] = not (db.soundEnabled[key] ~= false)
        UpdateToggle()
    end)
    UpdateToggle()

    ---------------------------------------------------------
    -- DELETE BUTTON
    ---------------------------------------------------------
    local del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    del:SetSize(20, 20)
    del:SetPoint("LEFT", 500, 0)
    del:SetScript("OnClick", function()
        local entries = db.activeCues[tostring(spellID)]
        if entries then
            for i = #entries, 1, -1 do
                if entries[i].trigger == cfg.trigger and entries[i].label == cfg.label then
                    table.remove(entries, i)
                    break
                end
            end
            if #entries == 0 then db.activeCues[tostring(spellID)] = nil end
        end
        BuildUI()
        UpdateResetButtonVisuals()
    end)
end

--------------------------------------------------------------------------------
-- BUILD UI
--------------------------------------------------------------------------------
function BuildUI(filter)
    if not frame.content then return end
    filter = filter and filter:lower() or ""
    
    local children = { frame.content:GetChildren() }
    for _, child in ipairs(children) do 
        child:Hide() 
        child:SetParent(nil) 
    end

    local index = 1
    local sortedKeys = {}
    for k in pairs(db.activeCues) do table.insert(sortedKeys, k) end
    table.sort(sortedKeys)

    for _, spellID in ipairs(sortedKeys) do
        for _, cfg in ipairs(db.activeCues[spellID]) do
            local label = (cfg.label or ""):lower()
            if filter == "" or label:find(filter, 1, true) or spellID:find(filter, 1, true) then
                CreateRow(frame.content, spellID, cfg, index)
                index = index + 1
            end
        end
    end
    frame.content:SetHeight(index * 26)
end

--------------------------------------------------------------------------------
-- INPUT AREA
--------------------------------------------------------------------------------
local function CreateInput(name, width, xOffset)
    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(width, 20)
    edit:SetPoint("BOTTOMLEFT", xOffset, 45)
    edit:SetAutoFocus(false)
    local label = edit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", 0, 2)
    label:SetText(name)
    return edit
end

local spellInput = CreateInput("Bigwigs ID", 70, 15)
local triggerInput = CreateInput("Trigger (sec)", 70, 95)
local labelInput = CreateInput("Label", 120, 175)

local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
addBtn:SetSize(80, 22)
addBtn:SetPoint("BOTTOMLEFT", 310, 44)
addBtn:SetText("Add Cue")
addBtn:SetScript("OnClick", function()
    local sID = tostring(spellInput:GetText())
    local trig = tonumber(triggerInput:GetText())
    local lbl = labelInput:GetText()
    
    if sID ~= "" and trig then
        if not lbl or lbl == "" then lbl = "Custom" end
        
        db.activeCues[sID] = db.activeCues[sID] or {}
        local newEntry = {
            sound = "!Targeted",
            trigger = trig,
            label = lbl,
            enabled = true
        }
        PrepareEntry(sID, newEntry)
        
        table.insert(db.activeCues[sID], newEntry)
        
        spellInput:SetText(""); triggerInput:SetText(""); labelInput:SetText("")
        BuildUI()
    end
end)

--------------------------------------------------------------------------------
-- SEARCH BOX 
--------------------------------------------------------------------------------
local searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
searchBox:SetSize(180, 20)
searchBox:SetPoint("LEFT", frame.title, "RIGHT", 20, -2)
searchBox:SetAutoFocus(false)

searchBox:SetScript("OnTextChanged", function(self)
    SearchBoxTemplate_OnTextChanged(self)
    local text = self:GetText()
    BuildUI(text)
end)

searchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    BuildUI("")
end)

searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
--------------------------------------------------------------------------------
-- BAR HANDLER
--------------------------------------------------------------------------------
local function barHandler(_, _, key, _, duration)
    local entries = db.activeCues[tostring(key)]
    if not entries then return end

    local currentEncounter = encounterID

    for i = 1, #entries do
        local cfg = entries[i]
        local dbKey = cfg.dbKey

        if db.soundEnabled[dbKey] ~= false then
            local delay = duration - cfg.trigger

            if delay >= 0 then
                C_Timer.After(delay, function()
                    if currentEncounter ~= encounterID then return end

                    local selected = db.soundChoice[dbKey] or cfg.sound
                    local soundPath = LSM:Fetch(MediaType_SOUND, selected, true)

                    if soundPath then
                        PlaySoundFile(soundPath, "Master")
                    end
                end)
            end
        end
    end
end
--------------------------------------------------------------------------------
-- SCROLL & SETUP
--------------------------------------------------------------------------------
frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
frame.scroll:SetPoint("TOPLEFT", 10, -40)
frame.scroll:SetPoint("BOTTOMRIGHT", -30, 90)

frame.content = CreateFrame("Frame", nil, frame.scroll)
frame.content:SetSize(520, 1)
frame.scroll:SetScrollChild(frame.content)

--------------------------------------------------------------------------------
-- INITIALIZATION & SLASH COMMANDS
--------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, arg1)
    if arg1 ~= addonName then return end
    
    InitDB()
    frame:ClearAllPoints()
    frame:SetPoint(db.pos.point, UIParent, db.pos.point, db.pos.x, db.pos.y)
    BuildUI()
    
    table.insert(UISpecialFrames, "FoxLabMainFrame")
    loader:UnregisterEvent("ADDON_LOADED")
end)

SLASH_MVA1 = "/mva"
SlashCmdList["MVA"] = function() frame:SetShown(not frame:IsShown()) end

--------------------------------------------------------------------------------
-- REGISTER BIGWIGS MESSAGES
--------------------------------------------------------------------------------
BigWigsLoader.RegisterMessage(addonName, "BigWigs_StartBar", barHandler)
BigWigsLoader.RegisterMessage(addonName, "BigWigs_OnBossWin", ResetEncounter)
BigWigsLoader.RegisterMessage(addonName, "BigWigs_OnBossWipe", ResetEncounter)