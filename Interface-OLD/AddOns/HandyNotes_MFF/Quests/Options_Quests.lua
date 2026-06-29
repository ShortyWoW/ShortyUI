local _, ns = ...

-- ---------------------------------------------------------------------------------------------------------------------------------

function ns.InterfaceOptionsQuests()

	if ns.removeWhenCompleted == nil then
		-- Will be initiated in the Achievements/Pets/Quests module - whichever the API loads first
		ns.removeWhenCompleted = Settings.RegisterVerticalLayoutSubcategory( ns.optionsCategory,
			( ns.colour.achieveH or ns.colour.quests or ns.colour.subH or ns.colour.highlight ) ..ns.L[ "Remove When Completed" ] )
	end

	-- ns.questTypesDB is defined in Common_Quests

	for i = 1, #ns.questTypesRequired do
		if ns.questTypesRequired[ i ] == true then
			local name = ns.colour.highlight ..ns.StringSubstitutions( ns.L[ ns.questTypesDB[ i ] ] )
			local variableKey = ns.questTypesDB[ i ]
			local variable = ns.db .."_" ..variableKey
			local tooltip = ns.colour.plaintext ..ns.StringSubstitutions( ns.L[ ns.questTypesDB[ i ] .."Desc" ] )
			local defaultValue = true
			local setting = Settings.RegisterAddOnSetting( ns.removeWhenCompleted, variable, variableKey, _G[ ns.db ],
						type( defaultValue ), name, defaultValue )			
			Settings.CreateCheckbox( ns.removeWhenCompleted, setting, tooltip )
		end	
	end
end