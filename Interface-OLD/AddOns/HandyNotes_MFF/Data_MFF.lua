local _, ns = ...

--==================================================================================================================================
--
-- SETUP
--
--==================================================================================================================================

ns.addOnName = "MFF"									-- Used to name globals etc. Unique within the Taraezor ecosystem.
ns.eventName = ns.L[ "Midsummer Fire Festival" ]		-- The player sees this in labels and titles.
ns.engine = { version=2.08, resetEngine=2.08 }			-- Set ns.engine to {} to bypass versioning. Flags are optional. version =
														-- The engine version. resetEngine: if the saved ENGINE version is < 
														-- resetEngine then erase any saved variables. resetAddOn: Same but tests
														-- against the ADDON TOC version number.
ns.slashCommands = { "/mff" }							-- Chat command shortcuts to bring up a configuration panel. One+ Required.
ns.db = "Taraezor_" ..ns.addOnName						-- Saved variables. Uses the WoW DB system and not the Ace DB system.
ns.points = {}											-- ns.points[ mapID ] = { titles, names, achievements, quests, etc }.
ns.wordwrap = true										-- If false then code \n. If true/false then \n\n still work as usual.
ns.noZidormiCheck = false								-- Used by AddOns zones with Zidormi phases. See Functions_Common for usage.
														-- Set to true here to ignore checking maps with Zidormi phases.
ns.series = {}											-- System for allocating textures and text colours to a "Series" of map pins.
ns.optionsSeriesDefaults = { 22, 23, 34, 27, 32, 31, 29, 36, 28, 35 } -- The ns.textures[i] default for each Series. Used in Options_Common.
ns.seriesMapping = { 21, 21, 21, 21, 21, 21, 21, 21, 21, 21 } -- The start of each series in ns.tectures. Used in Functions_Common.
ns.useAsDefaultSeries =	nil								-- If no pin.series or pin.cluster then Functions_Common code will try to
														-- call ns.GetAddOnSpecificTextureIndex in Core if ns.useAsDefaultSeries
														-- is nil. Otherwise ns.useAsDefaultSeries will be a default series.

-- Remember: All colouring and translating of tooltips must be done here. Blizzard limits each line to 5/6 colours

--==================================================================================================================================
--
-- Quests Module
--
-- Whether to show One Time/Seasonal/Weekly/Daily/Repeatable quests on the "Remove When Completed" options panel.
-- Note that "repeatable" (the 5th field) should always be false as allowing the player to set this is nonsensical

ns.questTypesRequired = { false, true, false, true, false }

--==================================================================================================================================
--
-- TEXTURES
--
-- Lower numbered textures 1 to about 15 are defined in Common.

ns.textures[21] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolHighBlue"
ns.textures[22] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolHighCyan"
ns.textures[23] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolHighGold"
ns.textures[24] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolHighGreen"
ns.textures[25] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolHighLightGreen"
ns.textures[26] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolLowBlue"
ns.textures[27] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolLowGreen"
ns.textures[28] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolLowMagenta"
ns.textures[29] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\SymbolLowOrange"
ns.textures[30] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FireArcane"
ns.textures[31] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FireBlood"
ns.textures[32] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FireFel"
ns.textures[33] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FireFrost"
ns.textures[34] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FireNature"
ns.textures[35] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FireFlower"
ns.textures[36] = "Interface\\AddOns\\HandyNotes_MFF\\Textures\\FirePotion"

--==================================================================================================================================
--
-- Clusters
--
-- Used to allocate textures to pin clusters. The Pin Cluster system is separate from the Series texture system.
-- See Functions_Common for the supporting code. Code tests for ns.clusterNames ~= nil

if ns.version >= 30000 then
	ns.clusterNames = { "flavour", "extinguish2", "extinguish", "main", "wardenKeeper", "flame2", "flame"  }
	ns.clusterRadius = 6
else
	ns.clusterNames = { "flavour", "main", "extinguish", "wardenKeeper", "flame" }
	ns.clusterRadius = 5
end
ns.clusterMapping = { 21, 36 }	-- Index into the ns.textures file for the Pin cluster textures. Set to nil if there are no pin
								-- clusters. A texture is selected from this range, at random, for each pin.
								-- If ( Range Max - Range Min + 1 ) < #ns.clusterNames then repetitions will occur.

--==================================================================================================================================
--
-- SERIES
--
--==================================================================================================================================

ns.series[ 1 ] = { title=ns.L[ "Honor the Flames" ] }									-- Cyan ^
ns.series[ 2 ] = { title=ns.L[ "Desecrate/Extinguish" ] }								-- Gold ^
ns.series[ 3 ] = { title=ns.L[ "Flickering Flames" ], versionUnder=20000 }				-- Fire Nature
ns.series[ 4 ] = { title=ns.L[ "A Thief's Reward" ] }									-- Green V
ns.series[ 5 ] = { title=ns.L[ "WFK" ] .." / " ..ns.L[ "WFEK" ], versionUnder=20000 }	-- Fire Fel
ns.series[ 6 ] = { title=ns.L[ "The Festival of Fire" ], versionUnder=20000 }			-- Fire Blood
ns.series[ 7 ] = { title=ns.L[ "Striking Back" ], version=30000 }						-- Orange V
ns.series[ 8 ] = { title=ns.L[ "Torch Tossing" ], version=30000 }						-- Potion
ns.series[ 9 ] = { title=ns.L[ "ITS" ], version=120000 }								-- Magenta V
ns.series[ 10 ] = {}																	-- Flower

--==================================================================================================================================
--
-- SUMMARIES / SETS
--
--==================================================================================================================================

ns.setFlavour = { cluster="flavour", alwaysShow=true, noCoords= true, noAzeroth=true, 
			tip="Across Azeroth and Outland, brilliant bonfires have been lit to rekindle peoples’ spirits and ward off ancient "
			.."evils. Each year, new guardians are chosen to watch over the sacred flames and ensure that they are never "
			.."extinguished.\n\n((Blizzard Website 19th June 2012))\n\n((A long time ago there was also an Engineers' Explosive "
			.."Extravaganza on the calendar for US players (EU missed out) and obviously scheduled for 4th July.))\n\n"
			.."Deep within the cavernous halls of the Undermine, goblins labor and toil over their strange and fanciful "
			.."engineering  creations. When they are not constructing powerful devices of destruction, they find making fireworks "
			.."a diverting pastime. They work tirelessly over strange chemical concoctions used to produce precisely the right "
			.."color and, of course, spectacular explosions. It is an art form that comes naturally to those who find great "
			.."pleasure in making things explode in a variety of ways. Competition is fierce among the engineers as they strive "
			.."for perfection within their pyrotechnics.\n\nSince holding an exhibition indoors — particularly within range of a "
			.."goblin engineer's workshop — is completely out of the question, it was decided by the Tinkers' Union that a day "
			.."would be chosen wherein the pyrotechnicians would go out into the world and share their creations with the world "
			.."(for a modest fee, of course). For one glorious day, the sky would be alight with the fantastic creations of "
			.."engineers throughout Azeroth.\n\nWhether Alliance or Horde, these pyrotechnicians are more than happy to help you "
			.."set the sky on fire during the Engineers' Explosive Extravaganza. (Just remember, point all incendiaries away from "
			.."the face.)\n\n((Blizzard Website 6th May 2005))" }

-- Vanilla/TBC before redesign sometime during TBC
ns.ffKalimdor = ns.L[ "FFK" ]
ns.ffEK = ns.L[ "FFEK" ]

-- Vanilla/TBC before redesign sometime during TBC
ns.festival = ns.L[ "The Festival of Fire" ]
ns.setFestival = { { id=9367, name=ns.festival, qType="Seasonal", versionUnder=20000 },
				{ id=9368, name=ns.festival, qType="Seasonal", versionUnder=20000 },
				{ id=9388, name=ns.ffKalimdor, qType="Seasonal", versionUnder=20000 },
					{ id=9389, name=ns.ffEK, qType="Seasonal", versionUnder=20000 }, }

ns.setMain = { cluster="main", alwaysShow=true, noCoords= true, noAzeroth=true, quests=ns.setFestival,
			achievements={ { id=1038, faction="Alliance", criteria=true, }, { id=1034, faction="Alliance", criteria=true, },
			{ id=1035, faction="Alliance", criteria=true, }, { id=1039, faction="Horde", criteria=true, },
			{ id=1036, faction="Horde", criteria=true, }, { id=1037, faction="Horde", criteria=true, }, }, }

-- Vanilla/TBC before redesign sometime during TBC
ns.wildFKal = ns.L[ "WFK" ]
ns.wildFEK = ns.L[ "WFEK" ]

ns.setExtKalEK = { cluster="extinguish", alwaysShow=true, noCoords= true, noAzeroth=true,
			quests={ { id=9323, name=ns.wildFEK, qType="Seasonal", versionUnder=20000 },
			{ id=9322, name=ns.wildFKal, qType="Seasonal", versionUnder=20000 }, },
			achievements={ { id=1029, faction="Alliance", criteria=true, }, { id=1028, faction="Alliance", criteria=true, },
			{ id=1032, faction="Horde", criteria=true, }, { id=1031, faction="Horde", criteria=true, } } }

ns.setExtOther = { cluster="extinguish2", alwaysShow=true, noCoords= true, noAzeroth=true,
			achievements={ { id=1030, faction="Alliance", criteria=true, }, { id=6007, faction="Alliance", criteria=true, },
			{ id=6013, faction="Alliance", criteria=true, version=40000, }, { id=8042, faction="Alliance", version=50000, },
			{ id=11276, faction="Alliance", version=60000, }, { id=11278, faction="Alliance", version=70000, },
			{ id=13343, faction="Alliance", criteria=true, version=80000, }, { id=1033, faction="Horde", criteria=true, },
			{ id=6010, faction="Horde", criteria=true, }, { id=6014, faction="Horde", criteria=true, version=40000, },
			{ id=8043, faction="Horde", version=50000, }, { id=11277, faction="Horde", version=60000, },
			{ id=11279, faction="Horde", version=70000, }, { id=13342, faction="Horde", criteria=true, version=80000, } } }
						
ns.setFlameKalEK = { cluster="wardenKeeper", alwaysShow=true, noCoords= true, noAzeroth=true,
			quests={ { id=9319, name=ns.L[ "A Light in Dark Places" ], qType="Seasonal", versionUnder=20000 },
			{ id=9386, name=ns.L[ "A Light in Dark Places" ], qType="Seasonal", versionUnder=20000 } },
			achievements={ { id=1023, faction="Alliance", criteria=true, }, { id=1022, faction="Alliance", criteria=true, },
			{ id=1024, faction="Alliance", criteria=true, version=60000, }, { id=1026, faction="Horde", criteria=true, },
			{ id=1025, faction="Horde", criteria=true, }, { id=1027, faction="Horde", criteria=true, version=60000, } } }

-- King of the Fire Festival Achievement
ns.setThief = { { id=9365, faction="Alliance", name=ns.L[ "A Thief's Reward" ], qType="Seasonal" },
			{ id=9339, faction="Horde", name=ns.L[ "A Thief's Reward" ], qType="Seasonal" },
			{ id=9332, faction="Horde", name=ns.L[ "Steal Darnassus" ], qType="Seasonal"  },
			{ id=9331, faction="Horde", name=ns.L[ "Steal Ironforge" ], qType="Seasonal" },
			{ id=9330, faction="Horde", name=ns.L[ "Steal Stormwind" ], qType="Seasonal" },
			{ id=11933, faction="Horde", version=30000, name=ns.L[ "Steal Exodar" ], qType="Seasonal" },
			{ id=9325, faction="Alliance", name=ns.L[ "Steal Thunder Bluff" ], qType="Seasonal" },
			{ id=9326, faction="Alliance", name=ns.L[ "Steal Undercity" ], qType="Seasonal",
				tip="In the Ruins of Lordaeron. No need to descend" },
			{ id=9324, faction="Alliance", name=ns.L[ "Steal Orgrimmar" ], qType="Seasonal" },
			{ id=11935, faction="Alliance", version=30000, name=ns.L[ "Steal Silvermoon" ], qType="Seasonal" } }
			
ns.setFlameOther = { cluster="flame", alwaysShow=true, noCoords= true, noAzeroth=true, quests=ns.setThief,						
			achievements={ { id=1145 },
			{ id=8045, faction="Alliance", criteria=true, version=50000, versionUnder=60000, },
			{ id=13341, faction="Alliance", criteria=true, version=80000, },
			{ id=17737, faction="Alliance", criteria=true, version=100000, },
			{ id=41631, faction="Alliance", criteria=true, version=110000, },
			{ id=61336, faction="Alliance", criteria=true, version=110000, },
			{ id=8044, faction="Horde", criteria=true, version=50000, versionUnder=60000, },
			{ id=13340, faction="Horde", criteria=true, version=80000, },
			{ id=17738, faction="Horde", criteria=true, version=100000, },
			{ id=41632, faction="Horde", criteria=true, version=110000, },
			{ id=61335, faction="Horde", criteria=true, version=110000, },
			{ id=263, }, { id=271, }, { id=272, } } }

ns.setLeftOvers = { cluster="flame2", alwaysShow=true, noCoords= true, noAzeroth=true,
			achievements={ { id=1024, faction="Alliance", criteria=true, versionUnder=60000 },
			{ id=6008, faction="Alliance", criteria=true, },
			{ id=6011, faction="Alliance", criteria=true, version=40000, },
			{ id=8045, faction="Alliance", criteria=true, version=60000, },
			{ id=11283, faction="Alliance", criteria=true, version=60000, },
			{ id=11280, faction="Alliance", criteria=true, version=70000, },
			{ id=1027, faction="Horde", criteria=true, versionUnder=60000, },
			{ id=6009, faction="Horde", criteria=true, },
			{ id=6012, faction="Horde", criteria=true, version=40000, },
			{ id=8044, faction="Horde", criteria=true, version=60000, },
			{ id=11284, faction="Horde", criteria=true, version=60000, },
			{ id=11282, faction="Horde", criteria=true, version=70000, } } }

-- Vanilla/TBC before redesign sometime during TBC
ns.setLightWild = { { id=9319, name=ns.L[ "A Light in Dark PLaces" ], qType="Seasonal" },
					{ id=9386, name=ns.L[ "A Light in Dark PLaces" ], qType="Seasonal", level=25 },
					{ id=9322, name=ns.wildFKal, qType="Seasonal", },
					{ id=9323, name=ns.wildFEK, qType="Seasonal", } }

ns.setUnusual = { version=30000, { id=11886, name=ns.L[ "Unusual Activity" ], qType="Seasonal" },
				{ id=11891, name=ns.L[ "An Innocent Disguise" ], qType="Seasonal" },
				{ id=12012, name=ns.L[ "Inform the Elder" ], qType="Seasonal" },
				{ id=11917, name=ns.L[ "Striking Back" ], qType="Daily" },
				{ id=11947, name=ns.L[ "Striking Back" ], qType="Daily" },
				{ id=11948, name=ns.L[ "Striking Back" ], qType="Daily" },
				{ id=11952, name=ns.L[ "Striking Back" ], qType="Daily" },
				{ id=11953, name=ns.L[ "Striking Back" ], qType="Daily" },
				{ id=11954, name=ns.L[ "Striking Back" ], qType="Daily" } }
ns.blueCrystal = "Click one of the three blue crystals"
ns.firewatchRidge = "." .."\n\nInside the Firewatch Ridge cave. Enter here"

--==================================================================================================================================
--
-- KALIMDOR
--
--==================================================================================================================================

ns.points[ ns.map.ashenvale ] = { -- Ashenvale
	[09091233] = { series=7, version=30000, quests={ { id=11891, name=ns.L[ "An Innocent Disguise" ], qType="Seasonal" } } },
	[09491167] = { series=7, version=30000, quests={ { id=11917, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[15581909] = { series=7, version=30000, quests={ { id=11886, name=ns.L[ "Unusual Activity" ], qType="Seasonal" } } },
	[21175062] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=2 } } },
	[51356615] = { series=1, faction="Horde", version=30000, quests={ { id=11841, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[51586666] = { series=2, faction="Alliance", version=30000, quests={ { id=11765, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[64007120] = { series=3, versionUnder=20000, quests={ { id=9388, name=ns.ffKalimdor, qType="Seasonal", } } },
	[86784150] = { series=2, faction="Horde", version=30000, quests={ { id=11734, name=ns.L[ "Desecrate" ], qType="Seasonal", } } },
	[86944186] = { series=1, faction="Alliance", version=30000, quests={ { id=11805, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[12258553] = { series=1, faction="Alliance", version=40000, quests={ { id=28928, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[12709728] = { series=2, faction="Horde", version=40000, quests={ { id=28915, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[49736280] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=2 } } },
	[15959691] = { series=1, faction="Horde", version=30000, quests={ { id=11856, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[16019678] = { series=2, faction="Alliance", version=30000, quests={ { id=11780, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[40199221] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=1 } } },
	[48219359] = { series=9, version=120000,
					quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", tip="You'll finish here" },
					{ id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", tip="You'll start here" } } },
	[49949546] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=1 } } },
	[88338605] = { series=9, faction="Alliance", version=120000,
					quests={ { id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal" },
					{ id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", tip="You'll start here" } } },
}

ns.points[ ns.map.azshara ] = { -- Azshara
	[16534890] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=7 } } },
	[41304310] = { series=5, versionUnder=30000, quests={ { id=9322, name=ns.wildFKal, qType="Seasonal", } } },
	[60445343] = { series=2, faction="Alliance", version=40000, quests={ { id=28919, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[60805347] = { series=1, faction="Horde", version=40000, quests={ { id=28923, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[17009058] = { series=4, faction="Alliance", quests=ns.setThief },
	[17329067] = { series=7, faction="Horde", quests=ns.setUnusual },
	[17469057] = { series=9, faction="Horde", version=120000, quests={ { id=92185, name=ns.L[ "Frost Lord" ], qType="Seasonal" },
					{ id=92435, name=ns.L[ "ITS: Orgrimmar" ], qType="Seasonal" },
					{ id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal" },					
					{ id=92839, name="ReITS: Orgrimmar", qType="Daily" } } },
}

ns.points[ ns.map.azuremyst ] = { -- Azuremyst Isle
	[24533670] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
	[24653684] = { series=4, faction="Horde", quests=ns.setThief },
	[24723662] = { series=4, faction="Alliance", quests=ns.setThief },
	[25153688] = { series=7, faction="Alliance", quests=ns.setUnusual },
	[44485252] = { series=1, faction="Alliance", version=30000, quests={ { id=11806, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[44675267] = { series=2, faction="Horde", version=30000, quests={ { id=11735, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.bloodmyst ] = { -- Bloodmyst Isle
	[55816789] = { series=1, faction="Alliance", version=30000, quests={ { id=11809, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[55886845] = { series=2, faction="Horde", version=30000, quests={ { id=11738, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.darkshore ] = { -- Darkshore
	[28479336] = { series=7, version=30000, quests={ { id=11891, name=ns.L[ "An Innocent Disguise" ], qType="Seasonal" } } },
	[41209000] = { series=3, versionUnder=20000, quests={ { id=9388, name=ns.ffKalimdor, qType="Seasonal", } } },
	[48732265] = { series=1, faction="Alliance", version=30000, quests={ { id=11811, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[48922257] = { series=2, faction="Horde", version=30000, quests={ { id=11740, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[28839277] = { series=7, version=30000, quests={ { id=11917, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[34279938] = { series=7, version=30000, quests={ { id=11886, name=ns.L[ "Unusual Activity" ], qType="Seasonal" } } },
	[65225090] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },
	[66694295] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },
	[86861111] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=4 } } },
	[90587823] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=6 } } },
}

ns.points[ ns.map.darnassus ] = { -- Darnassus
	[62104914] = { series=7, faction="Alliance", quests=ns.setUnusual },
	[62174869] = { series=4, faction="Alliance", quests=ns.setThief },
	[63194748] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
	[63684707] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.desolace ] = { -- Desolace
	[26147691] = { series=1, faction="Horde", version=30000, quests={ { id=11845, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[26197719] = { series=2, faction="Alliance", version=30000, quests={ { id=11769, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[39853063] = { series=7, version=30000, quests={ { id=11947, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[65881693] = { series=2, faction="Horde", version=30000, quests={ { id=11741, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[66121708] = { series=1, faction="Alliance", version=30000, quests={ { id=11812, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[81953750] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=3 } } },
	[87532744] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=3 } } },

	[87554957] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[87594902] = { series=7, faction="Horde", quests=ns.setUnusual },
	[87654969] = { series=4, faction="Alliance", quests=ns.setThief },
	[87694987] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.durotar ] = { -- Durotar
	[52034717] = { series=2, faction="Alliance", version=30000, quests={ { id=11770, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[52244740] = { series=1, faction="Horde", version=30000, quests={ { id=11846, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[13255906] = { series=2, faction="Alliance", version=30000, quests={ { id=11783, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[13385935] = { series=1, faction="Horde", version=30000, quests={ { id=11859, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[27071256] = { series=9, faction="Alliance", version=120000,
					quests={ { id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal" },
					{ id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", tip="You'll start here" } } },
}

ns.points[ ns.map.dustwallow ] = { -- Dustwallow Marsh
	[33283078] = { series=2, faction="Alliance", version=30000, noZidormi=true, quests={ { id=11771, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[33433091] = { series=1, faction="Horde", version=30000, noZidormi=true, quests={ { id=11847, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[61824046] = { series=1, faction="Alliance", version=30000, noZidormi=true, quests={ { id=11815, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[62044040] = { series=2, faction="Horde", version=30000, noZidormi=true, quests={ { id=11744, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[13073115] = { series=2, faction="Alliance", version=40000, noZidormi=true, quests={ { id=28914, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[13273178] = { series=1, faction="Horde", version=40000, noZidormi=true, quests={ { id=28927, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[23743838] = { series=2, faction="Horde", version=40000, noZidormi=true, quests={ { id=28913, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[23833805] = { series=1, faction="Alliance", version=40000, noZidormi=true, quests={ { id=28926, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.felwood ] = { -- Felwood
	[49442990] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },
	[51012143] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },

	[10647455] = { series=7, version=30000, quests={ { id=11917, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[76485906] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=6 } } },
	[88944189] = { series=1, version=40000, quests={ { id=29030, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.feralas ] = { -- Feralas
	[46381430] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=4 } } },
	[46664371] = { series=2, faction="Horde", version=30000, quests={ { id=11746, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[46824370] = { series=1, faction="Alliance", version=30000, quests={ { id=11817, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[72374779] = { series=1, faction="Horde", version=30000, quests={ { id=11849, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[72434762] = { series=2, faction="Alliance", version=30000, quests={ { id=11773, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[88863146] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=5 } } },

	[65079980] = { series=1, faction="Horde", version=30000, quests={ { id=11836, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[70599525] = { series=1, faction="Alliance", version=30000, quests={ { id=11831, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[70729503] = { series=2, faction="Horde", version=30000, quests={ { id=11760, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[75418746] = { series=7, version=30000, quests={ { id=11953, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
}

ns.points[ ns.map.moonglade ] = { -- Moonglade
	[45915244] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=4 } } },
	[47763527] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=4 } } },
	[57264269] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=4 } } },
	[58735888] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=4 } } },
}

ns.points[ ns.map.mulgore ] = { -- Mulgore
	[34172219] = { series=5, faction="Horde", versionUnder=30000, quests=ns.setLightWild },
	[34182237] = { series=6, faction="Horde", versionUnder=30000, quests=ns.festival },
	[51825926] = { series=1, faction="Horde", version=30000, quests={ { id=11852, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[51935945] = { series=2, faction="Alliance", version=30000, quests={ { id=11777, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[30371386] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=3 } } },
	[34970556] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=3 } } },
	[34992381] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[35022336] = { series=7, faction="Horde", quests=ns.setUnusual },
	[35072391] = { series=4, faction="Alliance", quests=ns.setThief },
	[35102406] = { series=4, faction="Horde", quests=ns.setThief },
	[70938132] = { series=2, faction="Alliance", version=40000, quests={ { id=28914, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[71128193] = { series=1, faction="Horde", version=40000, quests={ { id=28927, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[81208829] = { series=2, faction="Horde", version=40000, quests={ { id=28913, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[81298797] = { series=1, faction="Alliance", version=40000, quests={ { id=28926, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[89300288] = { series=2, faction="Alliance", version=30000, quests={ { id=11783, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[89440317] = { series=1, faction="Horde", version=30000, quests={ { id=11859, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[90398097] = { series=2, faction="Alliance", version=30000, noZidormi=true, quests={ { id=11771, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[90548109] = { series=1, faction="Horde", version=30000, noZidormi=true, quests={ { id=11847, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.barrens ] = { -- Northern Barrens
	[22311918] = { series=9, version=120000,
					quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", tip="You'll finish here" },
					{ id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", tip="You'll start here" } } },
	[24062105] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=1 } } },
	[49865439] = { series=2, faction="Alliance", version=30000, quests={ { id=11783, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[49995466] = { series=1, faction="Horde", version=30000, quests={ { id=11859, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[62581161] = { series=9, faction="Alliance", version=120000,
					quests={ { id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal" },
					{ id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", tip="You'll start here" } } },
	[69003900] = { series=3, versionUnder=20000, quests={ { id=9388, name=ns.ffKalimdor, qType="Seasonal", } } },

	[14271780] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=1 } } },
	[85564345] = { series=2, faction="Alliance", version=30000, quests={ { id=11770, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[85754366] = { series=1, faction="Horde", version=30000, quests={ { id=11846, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.orgrimmar ] = { -- Orgrimmar
	[42533461] = { series=6, faction="Horde", versionUnder=30000, quests=ns.setFestival },
	[42633431] = { series=5, faction="Horde", versionUnder=30000, quests=ns.setLightWild },
	[46223760] = { series=4, faction="Alliance", quests=ns.setThief },
	[46603725] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[47263789] = { series=7, faction="Horde", quests=ns.setUnusual },
	[47693757] = { series=9, faction="Horde", version=120000, quests={ { id=92185, name=ns.L[ "Frost Lord" ], qType="Seasonal" },
					{ id=92435, name=ns.L[ "ITS: Orgrimmar" ], qType="Seasonal" },
					{ id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal" },					
					{ id=92839, name="ReITS: Orgrimmar", qType="Daily" } } },
	[47733819] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.silithus ] = { -- Silithus
	[50864131] = { series=1, faction="Horde", version=30000, quests={ { id=11836, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[50864166] = { series=2, faction="Alliance", version=30000, quests={ { id=11800, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[60313351] = { series=1, faction="Alliance", version=30000, quests={ { id=11831, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[60543314] = { series=2, faction="Horde", version=30000, quests={ { id=11760, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[68572018] = { series=7, version=30000, quests={ { id=11953, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[78102010] = { series=5, versionUnder=30000, quests={ { id=9322, name=ns.wildFKal, qType="Seasonal", } } },
}

ns.points[ 199 ] = { -- Southern Barrens
	[40716734] = { series=2, faction="Alliance", version=40000, quests={ { id=28914, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[40856779] = { series=1, faction="Horde", version=40000, quests={ { id=28927, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[48337223] = { series=1, faction="Alliance", version=40000, quests={ { id=28926, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[48267246] = { series=2, faction="Horde", version=40000, quests={ { id=28913, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	
	[01150525] = { series=2, faction="Horde", version=30000, quests={ { id=11741, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[01290535] = { series=1, faction="Alliance", version=30000, quests={ { id=11812, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[12749683] = { series=1, faction="Horde", version=30000, quests={ { id=11849, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[12809668] = { series=2, faction="Alliance", version=30000, quests={ { id=11773, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[12961430] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=3 } } },
	[14282505] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[14312472] = { series=7, faction="Horde", quests=ns.setUnusual },
	[14352513] = { series=4, faction="Alliance", quests=ns.setThief },
	[14372524] = { series=4, faction="Horde", quests=ns.setThief },
	[26665112] = { series=1, faction="Horde", version=30000, quests={ { id=11852, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[26745126] = { series=2, faction="Alliance", version=30000, quests={ { id=11777, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[28208152] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=5 } } },
	[54220966] = { series=2, faction="Alliance", version=30000, quests={ { id=11783, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[54320987] = { series=1, faction="Horde", version=30000, quests={ { id=11859, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[55026708] = { series=2, faction="Alliance", version=30000, noZidormi=true, quests={ { id=11771, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[55136717] = { series=1, faction="Horde", version=30000, noZidormi=true, quests={ { id=11847, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[75237393] = { series=1, faction="Alliance", version=30000, noZidormi=true, quests={ { id=11815, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[75397389] = { series=2, faction="Horde", version=30000, noZidormi=true, quests={ { id=11744, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[81890118] = { series=2, faction="Alliance", version=30000, quests={ { id=11770, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[82040135] = { series=1, faction="Horde", version=30000, quests={ { id=11846, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.stonetalon ] = { -- Stonetalon Mountains
	[49295133] = { series=1, faction="Alliance", version=40000, quests={ { id=28928, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[49505113] = { series=2, faction="Horde", version=40000, quests={ { id=28915, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[49736280] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=2 } } },
	[52916245] = { series=1, faction="Horde", version=30000, quests={ { id=11856, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[52976232] = { series=2, faction="Alliance", version=30000, quests={ { id=11780, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[59207200] = { series=3, versionUnder=20000, quests={ { id=9388, name=ns.ffKalimdor, qType="Seasonal", } } },
	[76615785] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=1 } } },

	[44598795] = { series=2, faction="Horde", version=30000, quests={ { id=11741, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[44778807] = { series=1, faction="Alliance", version=30000, quests={ { id=11812, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[58021721] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=2 } } },
	[61089597] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=3 } } },
	[84445920] = { series=9, version=120000,
					quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", tip="You'll finish here" },
					{ id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", tip="You'll start here" } } },
	[86146103] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=1 } } },
	[87523238] = { series=1, faction="Horde", version=30000, quests={ { id=11841, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[87733289] = { series=2, faction="Alliance", version=30000, quests={ { id=11765, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.tanaris ] = { -- Tanaris
	[30426420] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=7 } } },
	[30866393] = { series=9, version=120000, quests={
					{ id=92634, faction="Horde", name=ns.L[ "MJ Loch Modan" ], qType="Seasonal", tip="Loch Modan transport here!" } } },
	[31706355] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", tip="Turn in here" },
					{ id=92634, faction="Horde", name=ns.L[ "MJ Loch Modan" ], qType="Seasonal" } } },
	[49822787] = { series=1, faction="Horde", version=50000, quests={ { id=11838, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[49832812] = { series=2, faction="Alliance", version=50000, quests={ { id=11802, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[52643026] = { series=1, faction="Alliance", version=30000, quests={ { id=11833, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[52643006] = { series=2, faction="Horde", version=50000, quests={ { id=11762, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[10787666] = { series=2, faction="Alliance", version=40000, quests={ { id=28948, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[10927663] = { series=1, faction="Horde", version=40000, quests={ { id=28949, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[11167434] = { series=2, faction="Horde", version=40000, quests={ { id=28947, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[11317432] = { series=1, faction="Alliance", version=40000, quests={ { id=28950, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[20633811] = { series=1, faction="Horde", version=40000, quests={ { id=28933, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[20723785] = { series=2, faction="Alliance", version=40000, quests={ { id=28920, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[22413635] = { series=2, faction="Horde", version=40000, quests={ { id=28921, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[22453652] = { series=1, faction="Alliance", version=40000, quests={ { id=28932, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[48950493] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=6 } } },
}

ns.points[ ns.map.teldrassil ] = { -- Teldrassil
	[34114820] = { series=7, faction="Alliance", quests=ns.setUnusual },
	[34134809] = { series=4, faction="Alliance", quests=ns.setThief },
	[34404777] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
	[34534766] = { series=4, faction="Horde", quests=ns.setThief },
	[54755283] = { series=2, faction="Horde", version=30000, quests={ { id=11753, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[54885279] = { series=1, faction="Alliance", version=30000, quests={ { id=11824, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[56559198] = { series=5, faction="Alliance", versionUnder=30000, quests=ns.setLightWild },
	[56579229] = { series=6, faction="Alliance", versionUnder=30000, quests=ns.setFestival },
}

ns.points[ ns.map.theExodar ] = { -- The Exodar
	[40902558] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
	[41352611] = { series=4, faction="Horde", quests=ns.setThief },
	[41622528] = { series=4, faction="Alliance", quests=ns.setThief },
	[43282628] = { series=7, faction="Alliance", quests=ns.setUnusual },
}

ns.points[ ns.map.thousand ] = { -- Thousand Needles
	[69975651] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=6 } } },
	[71826959] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=6 } } },
	[80205939] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=6 } } },
}

ns.points[ ns.map.thunder ] = { -- Thunder Bluff
	[21012643] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[21202406] = { series=7, faction="Horde", quests=ns.setUnusual },
	[21452697] = { series=4, faction="Alliance", quests=ns.setThief },
	[21492587] = { series=5, faction="Horde", versionUnder=30000, quests=ns.setLightWild },
	[21522718] = { series=6, faction="Horde", versionUnder=30000, quests=ns.setFestival },
	[21622773] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.ungoro ] = { -- Un'Goro
	[56336635] = { series=1, faction="Horde", version=40000, quests={ { id=28933, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[56496585] = { series=2, faction="Alliance", version=40000, quests={ { id=28920, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[59796291] = { series=2, faction="Horde", version=40000, quests={ { id=28921, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[59866325] = { series=1, faction="Alliance", version=40000, quests={ { id=28932, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[70207590] = { series=5, versionUnder=30000, quests={ { id=9322, name=ns.wildFKal, qType="Seasonal", } } },

	[00193255] = { series=2, faction="Horde", version=30000, quests={ { id=11760, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[09001834] = { series=7, version=30000, quests={ { id=11953, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
}

ns.points[ ns.map.winterspring ] = { -- Winterspring
	[30304310] = { series=5, versionUnder=30000, quests={ { id=9322, name=ns.wildFKal, qType="Seasonal", } } },
	[58094725] = { series=2, faction="Alliance", version=30000, quests={ { id=11803, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[58144750] = { series=1, faction="Horde", version=30000, quests={ { id=11839, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[59764903] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=5 } } },
	[61244725] = { series=1, faction="Alliance", version=30000, quests={ { id=11834, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[61394717] = { series=2, faction="Horde", version=30000, quests={ { id=11763, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[03386743] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },
	[04935908] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },
	[26122560] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=4 } } },
	[30049617] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=6 } } },
	[42327925] = { series=1, version=40000, quests={ { id=29030, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.kalimdor ] = { -- Kalimdor
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- EASTERN KINGDOMS
--
--==================================================================================================================================

ns.points[ ns.map.arathi ] = { -- Arathi Highlands
	[32834425] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=5 } } },
	[40056668] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=5 } } },
	[44304604] = { series=1, faction="Alliance", version=30000, quests={ { id=11804, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[44574615] = { series=2, faction="Horde", version=30000, quests={ { id=11732, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[69144286] = { series=2, faction="Alliance", version=30000, quests={ { id=11764, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[69354256] = { series=1, faction="Horde", version=30000, quests={ { id=11840, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[97741363] = { series=1, faction="Horde", version=30000, quests={ { id=11860, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[97801320] = { series=2, faction="Alliance", version=30000, quests={ { id=11784, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.badlands ] = { -- Badlands
	[18745604] = { series=2, faction="Horde", version=40000, quests={ { id=28912, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[19015619] = { series=1, faction="Alliance", version=40000, quests={ { id=28925, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[23093744] = { series=1, faction="Horde", version=30000, quests={ { id=11842, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[24053709] = { series=2, faction="Alliance", version=30000, quests={ { id=11766, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[42151067] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=7 } } },
	[50824154] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=7 } } },
	[57051992] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=7 } } },

	[05668528] = { series=1, faction="Horde", version=30000, quests={ { id=11844, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[05838829] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=1 } } },
	[06008518] = { series=2, faction="Alliance", version=30000, quests={ { id=11768, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[21340448] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=1 } } },
	[32260670] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=1 } } },
}

ns.points[ ns.map.blastedLands ] = { -- Blasted Lands
	[46221378] = { series=1, faction="Horde", version=40000, quests={ { id=28930, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[46301414] = { series=2, faction="Alliance", version=40000, quests={ { id=28917, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[53603100] = { series=5, versionUnder=30000, quests={ { id=9323, name=ns.wildFEK, qType="Seasonal", } } },
	[55271506] = { series=2, faction="Horde", version=30000, quests={ { id=11737, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[55531488] = { series=1, faction="Alliance", version=30000, quests={ { id=11808, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[22170986] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
	[22271849] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
}

ns.points[ ns.map.burningSteppes ] = { -- Burning Steppes
	[23823243] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=1 } } },
	[38723712] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=1 } } },
	[51112921] = { series=1, faction="Horde", version=30000, quests={ { id=11844, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[51293215] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=1 } } },
	[51452911] = { series=2, faction="Alliance", version=30000, quests={ { id=11768, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[68346064] = { series=1, faction="Alliance", version=30000, quests={ { id=11810, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[68576018] = { series=2, faction="Horde", version=30000, quests={ { id=11739, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[00197355] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=5 } } },
	[27320406] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },
	[63860072] = { series=2, faction="Horde", version=40000, quests={ { id=28912, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[64120088] = { series=1, faction="Alliance", version=40000, quests={ { id=28925, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.deadwind ] = { -- Deadwind Pass
	[44242973] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
	[45884281] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
	[46905744] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
	[47057008] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },

	[12535030] = { series=2, faction="Horde", version=30000, quests={ { id=11743, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[12914998] = { series=1, faction="Alliance", version=30000, quests={ { id=11814, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[82136318] = { series=1, faction="Horde", version=40000, quests={ { id=28930, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[82256372] = { series=2, faction="Alliance", version=40000, quests={ { id=28917, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[95386506] = { series=2, faction="Horde", version=30000, quests={ { id=11737, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[95766479] = { series=1, faction="Alliance", version=30000, quests={ { id=11808, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.dunMorogh ] = { -- Dun Morogh
	[53704483] = { series=2, faction="Horde", version=30000, quests={ { id=11742, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[53804523] = { series=1, faction="Alliance", version=30000, quests={ { id=11813, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[61902641] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=2 } } },
	[70171558] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=2 } } },
	[74003296] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=2 } } },

	[61292505] = { series=5, faction="Alliance", versionUnder=30000, quests=ns.setLightWild },
	[61332519] = { series=6, faction="Alliance", versionUnder=30000, quests=ns.setFestival },

	[60138254] = { series=7, version=30000, quests={ { id=11952, name=ns.L[ "Striking Back" ], qType="Daily" } },
					tip=ns.blueCrystal ..ns.firewatchRidge },
	[66558245] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },
	[68512332] = { series=4, faction="Alliance", quests=ns.setThief },
	[68642324] = { series=4, faction="Horde", quests=ns.setThief },
	[68732371] = { series=7, faction="Alliance", quests=ns.setUnusual },
	[68762327] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
	[71599714] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },
	[78238662] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },
	[95856162] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=1 } } },
	[96958205] = { series=1, faction="Horde", version=30000, quests={ { id=11842, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[97568183] = { series=2, faction="Alliance", version=30000, quests={ { id=11766, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.duskwood ] = { -- Duskwood
	[03932686] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[06254803] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[09636876] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[17182184] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[19668249] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[73695461] = { series=1, faction="Alliance", version=30000, quests={ { id=11814, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[73335491] = { series=2, faction="Horde", version=30000, quests={ { id=11743, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[01260549] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
}

ns.points[ ns.map.easternP ] = { -- Eastern Plaguelands
	[57507260] = { series=5, versionUnder=30000, quests={ { id=9323, name=ns.wildFEK, qType="Seasonal", } } },
}

ns.points[ ns.map.elwynn ] = { -- Elwynn Forest
	[21218105] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[23289767] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[33609376] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[43166286] = { series=2, faction="Horde", version=30000, quests={ { id=11745, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[43476263] = { series=1, faction="Alliance", version=30000, quests={ { id=11816, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[49327229] = { series=7, faction="Alliance", version=40000, versionUnder=60000, quests=ns.setUnusual },
	[51601507] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=5 } } },
	[55942301] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=5 } } },

	[18533852] = { series=7, faction="Alliance", version=120000, quests=ns.setUnusual },
	[18613851] = { series=9, faction="Alliance", version=120000, quests={ { id=92185, name=ns.L[ "Frost Lord" ], qType="Seasonal" },
					{ id=92711, name=ns.L[ "ITS: Stormwind" ], qType="Seasonal" },
					{ id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal" },					
					{ id=92836, name="ReITS: Stormwind", qType="Daily" } } },
	[19393860] = { series=4, faction="Alliance", quests=ns.setThief },
	[19523878] = { series=4, faction="Horde", quests=ns.setThief },
	[59662758] = { series=9, faction="Horde", version=120000,
					quests={ { id=92634, name=ns.L[ "MJ Loch Modan" ], qType="Seasonal" },
					{ id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", tip="You'll start here" } } },
}

ns.points[ ns.map.eversong ] = { -- Eversong Woods
	[46445034] = { series=2, faction="Alliance", version=30000, quests={ { id=11772, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[46405060] = { series=1, faction="Horde", version=30000, quests={ { id=11848, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[55743760] = { series=7, faction="Horde", quests=ns.setUnusual },
	[55893764] = { series=4, faction="Alliance", quests=ns.setThief },
	[55943748] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[56033760] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.eversongEK ] = { -- Eversong Woods - EK i.e. 12.0.0+ Midnight
	[48916390] = { series=1, version=120000, quests={ { id=92555, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[51373010] = { series=9, version=120000, quests={ { id=92821, name=ns.L[ "ITS: Silvermoon" ], qType="Daily" } } },
	[51443037] = { series=1, version=120000, quests={ { id=92556, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[91874570] = { series=1, version=120000, quests={ { id=92557, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.ghostlands ] = { -- Ghostlands
	[46902634] = { series=1, faction="Horde", version=30000, quests={ { id=11850, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[47062604] = { series=2, faction="Alliance", version=30000, quests={ { id=11774, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.hillsbrad ] = { -- Hillsbrad Foothills
	[54554987] = { series=2, faction="Alliance", version=30000, quests={ { id=11776, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[54665009] = { series=1, faction="Horde", version=30000, quests={ { id=11853, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[54903300] = { series=3, versionUnder=30000, quests={ { id=9389, name=ns.ffEK, qType="Seasonal", } } },

	[09952761] = { series=2, faction="Alliance", version=30000, quests={ { id=11580, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[09972729] = { series=1, faction="Horde", version=30000, quests={ { id=11584, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[67921464] = { series=1, faction="Alliance", version=30000, quests={ { id=11827, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[67941486] = { series=2, faction="Horde", version=30000, quests={ { id=11756, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[77714156] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=6 } } },
	[81794009] = { series=1, faction="Alliance", version=30000, quests={ { id=11826, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[81903989] = { series=2, faction="Horde", version=30000, quests={ { id=11755, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[84708172] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=5 } } },
	[85643852] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", tip="Turn in here" },
					{ id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal" } } },
	[85783913] = { series=9, version=120000, quests={
					{ id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal", tip="Barrens transport here!" } } },
	[89042931] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=6 } } },
	[89879848] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=5 } } },
	[92918300] = { series=1, faction="Alliance", version=30000, quests={ { id=11804, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[93108308] = { series=2, faction="Horde", version=30000, quests={ { id=11732, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.ironforge ] = { -- Ironforge
	[63812533] = { series=4, faction="Alliance", quests=ns.setThief },
	[64622482] = { series=4, faction="Horde", quests=ns.setThief },
	[65142773] = { series=7, faction="Alliance", quests=ns.setUnusual },
	[65362504] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },

	[63592469] = { series=5, faction="Alliance", versionUnder=30000, quests=ns.setLightWild },
	[63842555] = { series=6, faction="Alliance", versionUnder=30000, quests=ns.setFestival },
}
					
ns.points[ ns.map.lochModan ] = { -- Loch Modan
	[20437967] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=1 } } },
	[30056586] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=1 } } },
	[32334022] = { series=2, faction="Horde", version=30000, quests={ { id=11749, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[32564095] = { series=1, faction="Alliance", version=30000, quests={ { id=11820, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[32598174] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=1 } } },
	[53926936] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", tip="Turn in here" },
					{ id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal" } } },

	[43618616] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=7 } } },
	[60199645] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=7 } } },
}

ns.points[ ns.map.northStrangle ] = { -- Northern Stranglethorn
	[21414223] = { series=7, version=30000, quests={ { id=11948, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[40585094] = { series=1, faction="Horde", version=40000, quests={ { id=28924, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[40695179] = { series=2, faction="Alliance", version=40000, quests={ { id=28911, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[51746332] = { series=2, faction="Horde", version=40000, quests={ { id=28910, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[52056355] = { series=1, faction="Alliance", version=40000, quests={ { id=28922, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[35150676] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[91540066] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
}

ns.points[ ns.map.northshire ] = { -- Northshire
	[74600111] = { series=9, faction="Horde", version=120000,
					quests={ { id=92634, name=ns.L[ "MJ Loch Modan" ], qType="Seasonal" },
					{ id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", tip="You'll start here" } } },
}

ns.points[ ns.map.quelThalas ] = { -- Quel'Thalas 12.0.0+ Midnight
	[26056148] = { series=1, version=120000, quests={ { id=92555, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[27544086] = { series=9, version=120000, quests={ { id=92821, name=ns.L[ "ITS: Silvermoon" ], qType="Daily" } } },
	[27594102] = { series=1, version=120000, quests={ { id=92556, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[52255038] = { series=1, version=120000, quests={ { id=92557, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53702660] = { series=1, version=120000, noContinent=true, noAzeroth=true,
					quests={ { id=92558, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[82501750] = { series=1, version=120000, noContinent=true, noAzeroth=true,
					quests={ { id=92559, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.redridge ] = { -- Redridge Mountains
	[24585371] = { series=2, faction="Horde", version=30000, quests={ { id=11751, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[24885338] = { series=1, faction="Alliance", version=30000, quests={ { id=11822, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[27164748] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=2 } } },
	[39685175] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=2 } } },
	[51955535] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=2 } } },
	[63535689] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=2 } } },

	[91997374] = { series=2, faction="Horde", version=40000, quests={ { id=28916, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[92047499] = { series=1, faction="Alliance", version=40000, quests={ { id=28929, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[97977307] = { series=1, faction="Horde", version=30000, quests={ { id=11857, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[98347342] = { series=2, faction="Alliance", version=30000, quests={ { id=11781, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.searingGorge ] = { -- Searing Gorge
	[15143624] = { series=7, version=30000, quests={ { id=11952, name=ns.L[ "Striking Back" ], qType="Daily" } },
					 noContinent=true, noAzeroth=true, tip=ns.blueCrystal .."." .."\n\nThis is the location inside the cave" },
	[21723606] = { series=7, version=30000, quests={ { id=11952, name=ns.L[ "Striking Back" ], qType="Daily" } },
					tip=ns.blueCrystal ..ns.firewatchRidge },
	[31907300] = { series=5, versionUnder=30000, quests={ { id=9323, name=ns.wildFEK, qType="Seasonal", } } },
	[35813586] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },
	[46896810] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },
	[61454501] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=6 } } },

	[96576055] = { series=2, faction="Horde", version=40000, quests={ { id=28912, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[96946076] = { series=1, faction="Alliance", version=40000, quests={ { id=28925, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.silvermoon ] = { -- Silvemoon City
	[68664295] = { series=7, faction="Horde", noContinent=true, quests=ns.setUnusual },
	[69274312] = { series=4, faction="Alliance", noContinent=true, quests=ns.setThief },
	[69484245] = { series=8, faction="Horde", noContinent=true, quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
	[69844298] = { series=4, faction="Horde", noContinent=true, quests=ns.setThief },

	[30709587] = { series=1, faction="Horde", version=30000, noContinent=true,
					quests={ { id=11848, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[30869481] = { series=2, faction="Alliance", version=30000, noContinent=true,
					quests={ { id=11772, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.silvermoonCity ] = { -- Silvermoon City 12.0.0+ Midnight
	[48358006] = { series=9, version=120000, quests={ { id=92821, name=ns.L[ "ITS: Silvermoon" ], qType="Daily" } } },
	[48608098] = { series=1, version=120000, quests={ { id=92556, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.silverpine ] = { -- Silverpine Forest
	[49613859] = { series=2, faction="Alliance", version=30000, quests={ { id=11580, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[49633822] = { series=1, faction="Horde", version=30000, quests={ { id=11584, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53906910] = { series=3, versionUnder=30000, quests={ { id=9389, name=ns.ffEK, qType="Seasonal", } } },
}

ns.points[ ns.map.stormwind ] = { -- Stormwind City
	[47807212] = { series=7, faction="Alliance", version=120000, quests=ns.setUnusual },
	[47987210] = { series=9, faction="Alliance", version=120000, quests={ { id=92185, name=ns.L[ "Frost Lord" ], qType="Seasonal" },
					{ id=92711, name=ns.L[ "ITS: Stormwind" ], qType="Seasonal" },
					{ id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal" },					
					{ id=92836, name="ReITS: Stormwind", qType="Daily" } } },
	[49537227] = { series=4, faction="Alliance", quests=ns.setThief },
	[49797263] = { series=4, faction="Horde", quests=ns.setThief },

	[38546129] = { series=5, faction="Alliance", versionUnder=30000, quests=ns.setLightWild },
	[39216143] = { series=6, faction="Alliance", versionUnder=30000, quests=ns.setFestival },
	[49327229] = { series=7, faction="Alliance", version=40000, versionUnder=60000, quests=ns.setUnusual },
	[50057229] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
}

ns.points[ 224 ] = { -- Stranglethorn Vale
	[32222762] = { series=7, version=30000, quests={ { id=11948, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[44223307] = { series=1, faction="Horde", version=40000, quests={ { id=28924, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[44283359] = { series=2, faction="Alliance", version=40000, quests={ { id=28911, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[51204081] = { series=2, faction="Horde", version=40000, quests={ { id=28910, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[51394095] = { series=1, faction="Alliance", version=40000, quests={ { id=28922, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[43617792] = { series=1, faction="Horde", version=30000, quests={ { id=11837, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[43677810] = { series=2, faction="Alliance", version=30000, quests={ { id=11801, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[44507607] = { series=2, faction="Horde", version=30000, quests={ { id=11761, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[44567627] = { series=1, faction="Alliance", version=30000, quests={ { id=11832, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[40820542] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[76110161] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=3 } } },
}

ns.points[ ns.map.swampOS ] = { -- Swamp of Sorrows
	[70211447] = { series=2, faction="Horde", version=40000, quests={ { id=28916, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[70251574] = { series=1, faction="Alliance", version=40000, quests={ { id=28929, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[76331377] = { series=1, faction="Horde", version=30000, quests={ { id=11857, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[76701413] = { series=2, faction="Alliance", version=30000, quests={ { id=11781, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[32108275] = { series=1, faction="Horde", version=40000, quests={ { id=28930, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[32238382] = { series=2, faction="Alliance", version=40000, quests={ { id=28917, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[45318462] = { series=2, faction="Horde", version=30000, quests={ { id=11737, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[45698435] = { series=1, faction="Alliance", version=30000, quests={ { id=11808, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 210 ] = { -- The Cape of Stranglethorn
	[50407038] = { series=1, faction="Horde", version=30000, quests={ { id=11837, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[50507069] = { series=2, faction="Alliance", version=30000, quests={ { id=11801, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[51876732] = { series=2, faction="Horde", version=30000, quests={ { id=11761, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[51976764] = { series=1, faction="Alliance", version=30000, quests={ { id=11832, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[63010877] = { series=2, faction="Horde", version=40000, quests={ { id=28910, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[63320901] = { series=1, faction="Alliance", version=40000, quests={ { id=28922, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.TheHinter ] = { -- The Hinterlands
	[09195192] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=6 } } },
	[14345007] = { series=1, faction="Alliance", version=30000, quests={ { id=11826, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[14484981] = { series=2, faction="Horde", version=30000, quests={ { id=11755, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[19204809] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", tip="Turn in here" },
					{ id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal" } } },
	[19374885] = { series=9, version=120000, quests={
					{ id=92635, faction="Alliance", name=ns.L[ "MJ Barrens" ], qType="Seasonal", tip="Barrens transport here!" } } },
	[23503645] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=6 } } },
	[61905320] = { series=5, versionUnder=30000, quests={ { id=9323, name=ns.wildFEK, qType="Seasonal", } } },
	[76647497] = { series=1, faction="Horde", version=30000, quests={ { id=11860, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[76707459] = { series=2, faction="Alliance", version=30000, quests={ { id=11784, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.tirisfal ] = { -- Tirisfal Glades
	[57055173] = { series=2, faction="Alliance", version=30000, quests={ { id=11786, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[57235175] = { series=1, faction="Horde", version=30000, quests={ { id=11862, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[61727277] = { series=5, faction="Horde", versionUnder=30000, quests=ns.setLightWild, tip="Ruins of Lordaeron. Do NOT descend" },
	[61937313] = { series=6, faction="Horde", versionUnder=30000, quests=ns.setFestival, tip="Ruins of Lordaeron. Do NOT descend" },
	[62016792] = { series=7, faction="Horde", quests=ns.setUnusual },
	[62166681] = { series=4, faction="Horde", quests=ns.setThief },
	[62286691] = { series=4, faction="Alliance", quests=ns.setThief },
	[62436684] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },

	[85596948] = { series=2, faction="Alliance", version=40000, quests={ { id=28918, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[85667020] = { series=1, faction="Horde", version=40000, quests={ { id=28931, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[99279397] = { series=1, faction="Alliance", version=30000, quests={ { id=11827, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[99309421] = { series=2, faction="Horde", version=30000, quests={ { id=11756, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.tirisfalBlight ] = { -- Tirisfal Glades Blighted
	[69466280] = { series=10, version=80000, guide="Go to Zidormi here. The event is unavailable in \"Blighted\" Tirisfal Glades.\n\n"
					.."Click on her TWICE.\n\n", noContinent=true, noAzeroth=true },
}

ns.points[ ns.map.undercity ] = { -- Undercity
	[35005000] = { series=10, version=30000, guide="Do NOT descend into the Undercity. Everything is above, in the Ruins of Lordaeron.",
					noContinent=true, noAzeroth=true },
	[65543633] = { series=5, faction="Horde", versionUnder=30000, quests=ns.setLightWild, tip="Ruins of Lordaeron. Do NOT descend" },
	[66523806] = { series=6, faction="Horde", versionUnder=30000, quests=ns.setFestival, tip="Ruins of Lordaeron. Do NOT descend" },
}

ns.points[ ns.map.westernP ] = { -- Western Plaguelands
	[29095659] = { series=2, faction="Alliance", version=40000, quests={ { id=28918, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[29165734] = { series=1, faction="Horde", version=40000, quests={ { id=28931, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[43478233] = { series=1, faction="Alliance", version=30000, quests={ { id=11827, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[43508258] = { series=2, faction="Horde", version=30000, quests={ { id=11756, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[04475378] = { series=4, faction="Horde", quests=ns.setThief },
	[04605389] = { series=4, faction="Alliance", quests=ns.setThief },
	[04755382] = { series=8, faction="Horde", quests={ { id=11922, name="Torch Tossing", qType="Seasonal" },
					{ id=11925, name="More Torch Catching", qType="Daily" }, { id=11926,  name="More Torch Tossing", qType="Daily" } } },
}

ns.points[ ns.map.westfall ] = { -- Westfall
	[34108030] = { series=3, versionUnder=30000, quests={ { id=9389, name=ns.ffEK, qType="Seasonal", } } },
	[44766206] = { series=1, faction="Alliance", version=30000, quests={ { id=11583, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[45086242] = { series=2, faction="Horde", version=30000, quests={ { id=11581, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[63361781] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[65413429] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[67205063] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[69816662] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
	[77557721] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },

	[75643042] = { series=9, version=120000, quests={ { id=92504, name=ns.L[ "ITS: S EK" ], qType="Seasonal", step=4 } } },
}

ns.points[ ns.map.wetlands ] = { -- Wetlands
	[13274717] = { series=2, faction="Horde", version=30000, quests={ { id=11757, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[13464707] = { series=1, faction="Alliance", version=30000, quests={ { id=11828, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[51101700] = { series=3, versionUnder=30000, quests={ { id=9389, name=ns.ffEK, qType="Seasonal", } } },
	[76545949] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=3 } } },

	[12219636] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=2 } } },
	[20199260] = { series=4, faction="Horde", quests=ns.setThief },
	[20039270] = { series=4, faction="Alliance", quests=ns.setThief },
	[20299316] = { series=7, faction="Alliance", quests=ns.setUnusual },
	[20339264] = { series=8, faction="Alliance",
					quests={ { id=11731, name="Torch Tossing", qType="Seasonal" }, { id=11924, name="More Torch Catching", qType="Daily" },
					{ id=11921,  name="More Torch Tossing", qType="Daily" } } },
	[22008353] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=2 } } },
}

ns.points[ ns.map.zulAman ] = { -- Zul'Aman 12.0.0+ Midnight
	[09163598] = { series=1, version=120000, quests={ { id=92555, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[11740042] = { series=9, version=120000, quests={ { id=92821, name=ns.L[ "ITS: Silvermoon" ], qType="Daily" } } },
	[11820070] = { series=1, version=120000, quests={ { id=92556, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[54351683] = { series=1, version=120000, quests={ { id=92557, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.easternK ] = { -- Eastern Kingdoms
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- THE BURNING CRUSADE / OUTLAND
--
--==================================================================================================================================

ns.points[ ns.map.bladesEdge ] = { -- Blade's Edge Mountains
	[41576590] = { series=1, faction="Alliance", version=30000, quests={ { id=11807, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[41766605] = { series=2, faction="Horde", version=30000, quests={ { id=11736, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[49925866] = { series=1, faction="Horde", version=30000, quests={ { id=11843, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[50005901] = { series=2, faction="Alliance", version=30000, quests={ { id=11767, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[93225184] = { series=2, faction="Alliance", version=30000, quests={ { id=11799, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[93943562] = { series=2, faction="Horde", version=30000, quests={ { id=11759, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[94053541] = { series=1, faction="Alliance", version=30000, quests={ { id=11830, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[94984123] = { series=1, faction="Horde", version=30000, quests={ { id=11835, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.hellfire ] = { -- Hellfire Peninsular
	[57114204] = { series=1, faction="Horde", version=30000, quests={ { id=11851, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[57164183] = { series=2, faction="Alliance", version=30000, quests={ { id=11775, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[61975836] = { series=2, faction="Horde", version=30000, quests={ { id=11747, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[62175828] = { series=1, faction="Alliance", version=30000, quests={ { id=11818, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[84855334] = { series=7, version=30000, quests={ { id=11954, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
	[84894708] = { series=7, version=30000, quests={ { id=11954, name=ns.L[ "Striking Back" ], qType="Daily" } }, tip=ns.blueCrystal },
}

ns.points[ ns.map.nagrand ] = { -- Nagrand
	[49616946] = { series=1, faction="Alliance", version=30000, quests={ { id=11821, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[49676971] = { series=2, faction="Horde", version=30000, quests={ { id=11750, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[50913414] = { series=1, faction="Horde", version=30000, quests={ { id=11854, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[51073400] = { series=2, faction="Alliance", version=30000, quests={ { id=11778, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[89824869] = { series=4, faction="Alliance", quests=ns.setThief },
	[90004872] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.netherstorm ] = { -- Netherstorm
	[31106286] = { series=2, faction="Horde", version=30000, quests={ { id=11759, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[31216266] = { series=1, faction="Alliance", version=30000, quests={ { id=11830, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[32116832] = { series=1, faction="Horde", version=30000, quests={ { id=11835, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[32286825] = { series=2, faction="Alliance", version=30000, quests={ { id=11799, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.shadowmoon ] = { -- Shadowmoon Valley
	[33403053] = { series=1, faction="Horde", version=30000, quests={ { id=11855, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[33493032] = { series=2, faction="Alliance", version=30000, quests={ { id=11779, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[39565442] = { series=2, faction="Horde", version=30000, quests={ { id=11752, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[39635464] = { series=1, faction="Alliance", version=30000, quests={ { id=11823, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[01112867] = { series=1, faction="Alliance", version=30000, quests={ { id=11825, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[01262869] = { series=2, faction="Horde", version=30000, quests={ { id=11754, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.shattrath ] = { -- Shattrath City
	[60683061] = { series=7, quests=ns.setUnusual },
	[61393192] = { series=4, faction="Alliance", quests=ns.setThief },
	[62163204] = { series=4, faction="Horde", quests=ns.setThief },
}

ns.points[ ns.map.terokkar ] = { -- Terokkar Forest
	[51944317] = { series=2, faction="Alliance", version=30000, quests={ { id=11782, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[52014291] = { series=1, faction="Horde", version=30000, quests={ { id=11858, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[54065553] = { series=1, faction="Alliance", version=30000, quests={ { id=11825, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[54225555] = { series=2, faction="Horde", version=30000, quests={ { id=11754, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[32412089] = { series=4, faction="Alliance", quests=ns.setThief },
	[32592092] = { series=4, faction="Horde", quests=ns.setThief },
	[86955743] = { series=1, faction="Horde", version=30000, quests={ { id=11855, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[87055721] = { series=2, faction="Alliance", version=30000, quests={ { id=11779, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[93228176] = { series=2, faction="Horde", version=30000, quests={ { id=11752, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[93308198] = { series=1, faction="Alliance", version=30000, quests={ { id=11823, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.zangarmarsh ] = { -- Zangarmarsh
	[35445161] = { series=1, faction="Horde", version=30000, quests={ { id=11863, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[35565176] = { series=2, faction="Alliance", version=30000, quests={ { id=11787, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[68635214] = { series=2, faction="Horde", version=30000, quests={ { id=11758, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[69795195] = { series=1, faction="Alliance", version=30000, quests={ { id=11829, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[39639401] = { series=1, faction="Horde", version=30000, quests={ { id=11854, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[39809386] = { series=2, faction="Alliance", version=30000, quests={ { id=11778, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ ns.map.outland ] = { -- Outland
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- WRATH OF THE LICH KING / NORTHREND
--
--==================================================================================================================================

ns.points[ 114 ] = { -- Borean Tundra
	[51051179] = { series=2, faction="Alliance", version=30000, quests={ { id=13441, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[51131153] = { series=1, faction="Horde", version=30000, quests={ { id=13493, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[55101995] = { series=1, faction="Alliance", version=30000, quests={ { id=13485, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[55222018] = { series=2, faction="Horde", version=30000, quests={ { id=13440, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 127 ] = { -- Crystalsong Forest
	[77627522] = { series=2, faction="Horde", version=30000, quests={ { id=13447, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[78187495] = { series=1, faction="Alliance", version=30000, quests={ { id=13491, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[79975321] = { series=1, faction="Horde", version=30000, quests={ { id=13499, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[80345272] = { series=2, faction="Alliance", version=30000, quests={ { id=13457, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[90571936] = { series=1, faction="Horde", version=30000, quests={ { id=13498, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[90841996] = { series=2, faction="Alliance", version=30000, quests={ { id=13455, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[93622359] = { series=2, faction="Horde", version=30000, quests={ { id=13446, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[93632285] = { series=1, faction="Alliance", version=30000, quests={ { id=13490, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 115 ] = { -- Dragonblight
	[38264847] = { series=1, faction="Horde", version=30000, quests={ { id=13495, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[38484819] = { series=2, faction="Alliance", version=30000, quests={ { id=13451, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[75064384] = { series=2, faction="Horde", version=30000, quests={ { id=13443, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[75294380] = { series=1, faction="Alliance", version=30000, quests={ { id=13487, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[76611171] = { series=2, faction="Horde", version=30000, quests={ { id=13447, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[76891158] = { series=1, faction="Alliance", version=30000, quests={ { id=13491, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[77760103] = { series=1, faction="Horde", version=30000, quests={ { id=13499, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[77940079] = { series=2, faction="Alliance", version=30000, quests={ { id=13457, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 116 ] = { -- Grizzly Hills
	[19136145] = { series=2, faction="Alliance", version=30000, quests={ { id=13454, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[19326116] = { series=1, faction="Horde", version=30000, quests={ { id=13497, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[33906045] = { series=1, faction="Alliance", version=30000, quests={ { id=13489, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[34186061] = { series=2, faction="Horde", version=30000, quests={ { id=13445, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[31480638] = { series=2, faction="Alliance", version=30000, quests={ { id=13458, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[31540675] = { series=1, faction="Horde", version=30000, quests={ { id=13500, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[61228393] = { series=2, faction="Alliance", version=30000, quests={ { id=13453, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[61468371] = { series=1, faction="Horde", version=30000, quests={ { id=13496, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[72018674] = { series=2, faction="Horde", version=30000, quests={ { id=13444, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[72048714] = { series=1, faction="Alliance", version=30000, quests={ { id=13488, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 117 ] = { -- Howling Fjord
	[48411334] = { series=2, faction="Alliance", version=30000, quests={ { id=13453, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[48621315] = { series=1, faction="Horde", version=30000, quests={ { id=13496, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[57771577] = { series=2, faction="Horde", version=30000, quests={ { id=13444, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[57811612] = { series=1, faction="Alliance", version=30000, quests={ { id=13488, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 118 ] = { -- Icecrown
	[09179387] = { series=2, faction="Alliance", version=30000, quests={ { id=13450, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[09319407] = { series=1, faction="Horde", version=30000, quests={ { id=13494, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[09579719] = { series=2, faction="Horde", version=30000, quests={ { id=13442, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[09739705] = { series=1, faction="Alliance", version=30000, quests={ { id=13486, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[98519305] = { series=1, faction="Horde", version=30000, quests={ { id=13499, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[98679283] = { series=2, faction="Alliance", version=30000, quests={ { id=13457, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 119 ] = { -- Sholazar Basin
	[47306147] = { series=2, faction="Alliance", version=30000, quests={ { id=13450, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[47506177] = { series=1, faction="Horde", version=30000, quests={ { id=13494, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[47886626] = { series=2, faction="Horde", version=30000, quests={ { id=13442, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[48116605] = { series=1, faction="Alliance", version=30000, quests={ { id=13486, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[29879788] = { series=2, faction="Alliance", version=30000, quests={ { id=13441, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[29979754] = { series=1, faction="Horde", version=30000, quests={ { id=13493, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 120 ] = { -- The Storm Peaks
	[40278535] = { series=1, faction="Horde", version=30000, quests={ { id=13498, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[40378558] = { series=2, faction="Alliance", version=30000, quests={ { id=13455, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[41448669] = { series=1, faction="Alliance", version=30000, quests={ { id=13490, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[41448697] = { series=2, faction="Horde", version=30000, quests={ { id=13446, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },

	[36219831] = { series=1, faction="Horde", version=30000, quests={ { id=13499, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[36359812] = { series=2, faction="Alliance", version=30000, quests={ { id=13457, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[62689638] = { series=1, faction="Alliance", version=30000, quests={ { id=13492, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[62779618] = { series=2, faction="Horde", version=30000, quests={ { id=13449, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 123 ] = { -- Wintergrasp
	[95739853] = { series=1, faction="Horde", version=30000, quests={ { id=13495, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[96159800] = { series=2, faction="Alliance", version=30000, quests={ { id=13451, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 121 ] = { -- Zul'Drak
	[40386130] = { series=1, faction="Alliance", version=30000, quests={ { id=13492, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[40516101] = { series=2, faction="Horde", version=30000, quests={ { id=13449, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[43327135] = { series=2, faction="Alliance", version=30000, quests={ { id=13458, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[43387174] = { series=1, faction="Horde", version=30000, quests={ { id=13500, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[01397604] = { series=2, faction="Horde", version=30000, quests={ { id=13447, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[01707590] = { series=1, faction="Alliance", version=30000, quests={ { id=13491, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[02686405] = { series=1, faction="Horde", version=30000, quests={ { id=13499, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[02886378] = { series=2, faction="Alliance", version=30000, quests={ { id=13457, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[08464560] = { series=1, faction="Horde", version=30000, quests={ { id=13498, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[08614592] = { series=2, faction="Alliance", version=30000, quests={ { id=13455, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[10124790] = { series=2, faction="Horde", version=30000, quests={ { id=13446, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[10134750] = { series=1, faction="Alliance", version=30000, quests={ { id=13490, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 113 ] = { -- Northrend
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- CATACLYSM
--
--==================================================================================================================================

ns.points[ 204 ] = { -- Abyssal Depths
	[96834446] = { series=1, version=40000, quests={ { id=29031, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 207 ] = { -- Deepholm
	[49405132] = { series=1, version=40000, quests={ { id=29036, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 198 ] = { -- Mount Hyjal
	[44684065] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=6 } } },
	[44835249] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=6 } } },
	[62832271] = { series=1, version=40000, quests={ { id=29030, name=ns.L[ "Honor" ], qType="Seasonal" } } },

	[06370589] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=3 } } },
	[79029228] = { series=9, version=120000, quests={ { id=92106, name=ns.L[ "ITS: N Kal" ], qType="Seasonal", step=6 } } },
}

ns.points[ 205 ] = { -- Shimmering Expanse in Vashj'ir
	[49354199] = { series=1, version=40000, quests={ { id=29031, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 241 ] = { -- Twilight Highlands
	[21194642] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=3 } } },
	[47142830] = { series=2, faction="Horde", version=40000, quests={ { id=28943, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[47262896] = { series=1, faction="Alliance", version=40000, quests={ { id=28945, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53124618] = { series=1, faction="Horde", version=40000, quests={ { id=28946, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53274636] = { series=2, faction="Alliance", version=40000, quests={ { id=28944, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[59041682] = { series=9, version=120000, quests={ { id=92503, name=ns.L[ "ITS: N EK" ], qType="Seasonal", step=4 } } },

	[08508738] = { series=2, faction="Horde", version=30000, quests={ { id=11749, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[08628777] = { series=1, faction="Alliance", version=30000, quests={ { id=11820, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 249 ] = { -- Uldum
	[52993457] = { series=2, faction="Alliance", version=40000, quests={ { id=28948, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[53153454] = { series=1, faction="Horde", version=40000, quests={ { id=28949, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53433188] = { series=2, faction="Horde", version=40000, quests={ { id=28947, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[53603185] = { series=1, faction="Alliance", version=40000, quests={ { id=28950, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[75862006] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=7 } } },
	[76361975] = { series=9, version=120000, quests={
					{ id=92634, faction="Horde", name=ns.L[ "MJ Loch Modan" ], qType="Seasonal", tip="Loch Modan transport here!" } } },
	[77341932] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", tip="Turn in here" },
					{ id=92634, faction="Horde", name=ns.L[ "MJ Loch Modan" ], qType="Seasonal" } } },
}

ns.points[ 1527 ] = { -- Uldum
	[52993457] = { series=2, faction="Alliance", version=40000, quests={ { id=28948, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[53153454] = { series=1, faction="Horde", version=40000, quests={ { id=28949, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53433188] = { series=2, faction="Horde", version=40000, quests={ { id=28947, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[53603185] = { series=1, faction="Alliance", version=40000, quests={ { id=28950, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[75862006] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", step=7 } } },
	[76361975] = { series=9, version=120000, quests={
					{ id=92634, faction="Horde", name=ns.L[ "MJ Loch Modan" ], qType="Seasonal", tip="Loch Modan transport here!" } } },
	[77341932] = { series=9, version=120000, quests={ { id=92420, name=ns.L[ "ITS: S Kal" ], qType="Seasonal", tip="Turn in here" },
					{ id=92634, faction="Horde", name=ns.L[ "MJ Loch Modan" ], qType="Seasonal" } } },
}

ns.points[ 203 ] = { -- Vashj'ir
	[64315167] = { series=1, version=40000, quests={ { id=29031, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

--==================================================================================================================================
--
-- MISTS OF PANDARIA
--
--==================================================================================================================================

ns.points[ 422 ] = { -- Dread Wastes
	[56076957] = { series=1, version=50000, quests={ { id=32497, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 418 ] = { -- Krasarang Wilds
	[73990949] = { series=1, version=50000, quests={ { id=32499, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 379 ] = { -- Kun-Lai Summit
	[71159086] = { series=1, version=50000, quests={ { id=32500, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 371 ] = { -- The Jade Forest
	[47184718] = { series=1, version=50000, quests={ { id=32498, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 390 ] = { -- Vale of Eternal Blossoms
	[77763397] = { series=1, faction="Horde", version=50000, quests={ { id=32509, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[77793366] = { series=2, faction="Alliance", version=50000, quests={ { id=32496, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[79683727] = { series=1, faction="Alliance", version=50000, quests={ { id=32510, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[79903729] = { series=2, faction="Horde", version=50000, quests={ { id=32503, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 376 ] = { -- Valley of the Four Winds
	[51815132] = { series=1, version=50000, quests={ { id=32502, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 388 ] = { -- Townlong Steppes
	[71525629] = { series=1, version=50000, quests={ { id=32501, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 424 ] = { -- Pandaria
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- WARLORDS OF DRAENOR / GARRISON
--
--==================================================================================================================================

ns.points[ 525 ] = { -- Frostfire Ridge
	[72616508] = { series=1, faction="Horde", version=70000, quests={ { id=44580, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[72706521] = { series=2, faction="Alliance", version=70000, quests={ { id=44583, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 543 ] = { -- Gorgrond
	[43929379] = { series=1, version=70000, quests={ { id=44573, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 550 ] = { -- Nagrand
	[80554770] = { series=1, version=70000, quests={ { id=44572, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 539 ] = { -- Shadowmoon Valley
	[42633599] = { series=1, faction="Alliance", version=70000, quests={ { id=44579, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[42723589] = { series=2, faction="Horde", version=70000, quests={ { id=44582, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 542 ] = { -- Spires of Arak
	[48014472] = { series=1, version=70000, quests={ { id=44570, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 535 ] = { -- Talador
	[43467181] = { series=1, version=70000, quests={ { id=44571, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 572 ] = { -- Draenor
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- LEGION / BROKEN ISLES
--
--==================================================================================================================================

ns.points[ 630 ] = { -- Azsuna
	[48262969] = { series=1, version=70000, quests={ { id=44574, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 650 ] = { -- Highmountain
	[55528445] = { series=1, version=70000, quests={ { id=44576, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 634 ] = { -- Stormheim
	[32504213] = { series=1, version=70000, quests={ { id=44577, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 680 ] = { -- Suramar
	[22905827] = { series=2, faction="Horde", version=70000, quests={ { id=44624, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[23025835] = { series=1, faction="Alliance", version=70000, quests={ { id=44613, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[30304528] = { series=2, faction="Alliance", version=70000, quests={ { id=44627, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[30464538] = { series=1, faction="Horde", version=70000, quests={ { id=44614, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 641 ] = { -- Val'sharah
	[44885793] = { series=1, version=70000, quests={ { id=44575, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 619 ] = { -- Broken Isles
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- BATTLE FOR AZEROTH / KUL TIRAS & ZANDALAR
--
--==================================================================================================================================

ns.points[ 1165 ] = { -- Dazar'alor in Zuldazar
	[35985713] = { series=1, faction="Horde", version=80000, quests={ { id=54745, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[36175692] = { series=2, faction="Alliance", version=80000, quests={ { id=54744, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 896 ] = { -- Drustvar
	[40164743] = { series=2, faction="Horde", version=80000, quests={ { id=54742, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[40224760] = { series=1, faction="Alliance", version=80000, quests={ { id=54743, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 863 ] = { -- Nazmir
	[40037430] = { series=1, faction="Horde", version=80000, quests={ { id=54747, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[40137416] = { series=2, faction="Alliance", version=80000, quests={ { id=54746, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 942 ] = { -- Stormsong Valley
	[35855133] = { series=1, faction="Alliance", version=80000, quests={ { id=54741, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[35935148] = { series=2, faction="Horde", version=80000, quests={ { id=54739, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 895 ] = { -- Tiragarde Sound
	[76334974] = { series=2, faction="Horde", version=80000, quests={ { id=54736, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
	[76354988] = { series=1, faction="Alliance", version=80000, quests={ { id=54737, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 864 ] = { -- Vol'dun
	[56014776] = { series=1, faction="Horde", version=80000, quests={ { id=54750, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[55954764] = { series=2, faction="Alliance", version=80000, quests={ { id=54749, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 862 ] = { -- Zuldazar
	[53314811] = { series=1, faction="Horde", version=80000, quests={ { id=54745, name=ns.L[ "Honor" ], qType="Seasonal" } } },
	[53374804] = { series=2, faction="Alliance", version=80000, quests={ { id=54744, name=ns.L[ "Desecrate" ], qType="Seasonal" } } },
}

ns.points[ 875 ] = { -- Zandalar
	[05008100] = ns.setFlavour,
	[05008101] = ns.setMain,
	[05008102] = ns.setExtKalEK,
	[05008103] = ns.setExtOther,
	[05008104] = ns.setFlameKalEK,
	[05008105] = ns.setFlameOther,
	[05008106] = ns.setLeftOvers,
}

ns.points[ 876 ] = { -- Kul Tiras
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- SHADOWLANDS
--
--==================================================================================================================================

--==================================================================================================================================
--
-- DRAGONFLIGHT / DRAGON ISLES
--
--==================================================================================================================================

ns.points[ 2023 ] = { -- Ohn'ahran Plains
	[63853501] = { series=1, version=100000, quests={ { id=75617, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 63923490
}

ns.points[ 2025 ] = { -- Thaldraszus
	[40436166] = { series=1, version=100000, quests={ { id=75645, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 40506169
}

ns.points[ 2024 ] = { -- The Azure Span
	[12214757] = { series=1, version=100000, quests={ { id=75640, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 12224749
}

ns.points[ 2022 ] = { -- The Waking Shores
	[45988288] = { series=1, version=100000, quests={ { id=75398, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 45928279
}


ns.points[ 2151 ] = { -- The Forbidden Reach
	[34986090] = { series=1, version=100000, quests={ { id=75647, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 34996105
}

ns.points[ 2112 ] = { -- Valdrakken
	[53396232] = { series=1, version=100000, quests={ { id=75645, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 53906252
}

ns.points[ 2133 ] = { -- Zaralek Cavern -- MUST use my DTL. HN/HBD is bugged
	[55175542] = { series=1, version=100000, quests={ { id=75650, name=ns.L[ "Honor" ], qType="Seasonal" } } }, -- Bonfire at 55235549
}

ns.points[ 2274 ] = { -- Dragon Isles
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- THE WAR WITHIN / KHAZ ALGAR
--
--==================================================================================================================================

ns.points[ 2255 ] = { -- Azj'Kahet
	[55494337] = { noAzeroth=true, series=1, version=110000, quests={ { id=87356, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 2339 ] = { -- Dornogal
	[48525151] = { series=1, version=110000, quests={ { id=87342, name=ns.L[ "Honor" ], qType="Seasonal" } }, tip="Dornogal" },
}

ns.points[ 2215 ] = { -- Hallowfall
	[42485160] = { noAzeroth=true, series=1, version=110000, quests={ { id=87355, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 2248 ] = { -- Isle of Dorn
	[47553971] = { noAzeroth=true, series=1, version=110000, quests={ { id=87342, name=ns.L[ "Honor" ], qType="Seasonal" } }, tip="Dornogal" },
}

ns.points[ 2214 ] = { -- The Ringing Deeps
	[43663261] = { noAzeroth=true, series=1, version=110000, quests={ { id=87357, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ 2274 ] = { -- Khaz Algar
	[06008100] = ns.setFlavour,
	[06008101] = ns.setMain,
	[06008102] = ns.setExtKalEK,
	[06008103] = ns.setExtOther,
	[06008104] = ns.setFlameKalEK,
	[06008105] = ns.setFlameOther,
	[06008106] = ns.setLeftOvers,
}

--==================================================================================================================================
--
-- MIDNIGHT
--
--==================================================================================================================================

ns.points[ ns.map.harandar ] = { -- Harandar 12.0.0+ Midnight
	[54245154] = { series=1, version=120000, noContinent=true, noAzeroth=true,
					quests={ { id=92559, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

ns.points[ ns.map.voidstorm ] = { -- Voidstorm 12.0.0+ Midnight
	[53567024] = { series=1, version=120000, noContinent=true, noAzeroth=true,
					quests={ { id=92558, name=ns.L[ "Honor" ], qType="Seasonal" } } },
}

