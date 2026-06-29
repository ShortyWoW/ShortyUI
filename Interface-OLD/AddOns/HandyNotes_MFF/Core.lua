--[[
                                ----o----(||)----oo----(||)----o----

                                       Midsummer Fire Festival

                                       v4.09 - 29th June 2026
                                Copyright (C) Taraezor / Chris Birch
                                         All Rights Reserved

                                ----o----(||)----oo----(||)----o----
]]

local addonName, ns = ...

-- ---------------------------------------------------------------------------------------------------------------------------------

-- This AddOn has been wholly modularised and runs on a standardised core of files.
-- It's data/customisations are found in the _XXXX files.
-- Executable customisations / overrides are to be inserted here.
-- To configure use a chat command as defined in the Data_XXXX file.

-- ---------------------------------------------------------------------------------------------------------------------------------

-- Data checks. Must return true or false. Decision as to whether or not to show, regardless of any other checks

--function ns.PassAddOnSpecificPetChecks( pet )
--function ns.PassAddOnSpecificAchievementChecks( event )

local GetQuestObjectives = C_QuestLog.GetQuestObjectives

function ns.PassAddOnSpecificQuestChecks( quest )

	if quest.step == nil then return true end
	
	local infoTable = GetQuestObjectives( quest.id )
	-- Careful. The table structure can change suddenly, even while the pin is being shown. Data might be unavailable too on a
	-- fresh login. Test for existence at all levels

	if infoTable and infoTable[ quest.step ] and ( infoTable[ quest.step ].finished == false ) then
		if quest.step > 1 then
			if infoTable[ quest.step - 1 ] and ( infoTable[ quest.step - 1 ].finished == true ) then
				return true
			end
		else
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------------------------------------------------------------

-- Preceeds the showing of Tooltips. After the title/name fields and after Event/Pet/Quest modules. Right before theg guides/tips.

--function ns.AddOnSpecificTooltipLines( pin )

-- ---------------------------------------------------------------------------------------------------------------------------------

--	Return manually allocated and sized texture index into the Functions_Commons "hash" for then "return" to the HandyNotes
--  driver for displaying the pin from the HN pin iterator

-- function ns.GetAddOnSpecificTextureIndex( pin )

-- ---------------------------------------------------------------------------------------------------------------------------------

-- Custom "do end" blocks, especially timed checks/setups
