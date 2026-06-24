local _, ns = ...

-- ---------------------------------------------------------------------------------------------------------------------------------

function ns.InterfaceOptionsAchievements()

	if ns.removeWhenCompleted == nil then
		-- Will be initiated in the Achievements/Pets/Quests module - whichever the API loads first
		ns.removeWhenCompleted = Settings.RegisterVerticalLayoutSubcategory( ns.optionsCategory,
			( ns.colour.achieveH or ns.colour.quests or ns.colour.subH or ns.colour.highlight ) ..ns.L[ "Remove When Completed" ] )
	end

	local name = ns.colour.highlight ..ns.L[ "Achievements" ]
	local variableKey = "Achievements"
	local variable = ns.db .."_" ..variableKey
	local tooltip = ns.colour.plaintext ..ns.L[ "AchievementsDesc" ]
	local defaultValue = true
	local setting = Settings.RegisterAddOnSetting( ns.removeWhenCompleted, variable, variableKey, _G[ ns.db ], type( defaultValue ),
				name, defaultValue )
	Settings.CreateCheckbox( ns.removeWhenCompleted, setting, tooltip )
end