local _, ns = ...

-- ---------------------------------------------------------------------------------------------------------------------------------

function ns.InterfaceOptionsAddOnSpecific()

	-- Insert additional options for the options panel here. Copy code blocks from Options_Common

-- ---------------------------------------------------------------------------------------------------------------------------------

	ns.optionsTextures = Settings.RegisterVerticalLayoutSubcategory( ns.optionsCategory,
		( ns.colour.achieveH or ns.colour.quests or ns.colour.subH or ns.colour.highlight ) ..ns.L[ "Textures" ] )
	
	local extraChoices = { ns.colour.plaintext ..ns.L[ "Symbol" ] .." ^ " ..ns.L[ "Blue" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." ^ " ..ns.L[ "Cyan" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." ^ " ..ns.L[ "Gold" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." ^ " ..ns.L[ "Green" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." ^ " ..ns.L[ "Light Green" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." V " ..ns.L[ "Blue" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." V " ..ns.L[ "Green" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." V " ..ns.L[ "Magenta" ],
				ns.colour.plaintext ..ns.L[ "Symbol" ] .." V " ..ns.L[ "Orange" ],
				ns.colour.plaintext ..ns.L[ "Fire" ] ..ns.L[ "Arcane" ],
				ns.colour.plaintext ..ns.L[ "Fire" ] ..ns.L[ "Blood" ],
				ns.colour.plaintext ..ns.L[ "Fire" ] ..ns.L[ "Fel" ],
				ns.colour.plaintext ..ns.L[ "Fire" ] ..ns.L[ "Frost" ],
				ns.colour.plaintext ..ns.L[ "Fire" ] ..ns.L[ "Nature" ],
				ns.colour.plaintext ..ns.L[ "Flower" ],
				ns.colour.plaintext ..ns.L[ "Potion" ] }

	-- Textures here are added onto the basic/standard textures that are already in ns.textures in Common.

	ns.optionsSeries[ 1 ] = extraChoices
	ns.optionsSeries[ 2 ] = extraChoices
	ns.optionsSeries[ 3 ] = extraChoices
	ns.optionsSeries[ 4 ] = extraChoices
	ns.optionsSeries[ 5 ] = extraChoices
	ns.optionsSeries[ 6 ] = extraChoices
	ns.optionsSeries[ 7 ] = extraChoices
	ns.optionsSeries[ 8 ] = extraChoices
	ns.optionsSeries[ 9 ] = extraChoices
	ns.optionsSeries[ 10 ] = extraChoices

	ns.SetupAddOnSpecificOptions()
	Settings.RegisterAddOnCategory( ns.optionsTextures )
end