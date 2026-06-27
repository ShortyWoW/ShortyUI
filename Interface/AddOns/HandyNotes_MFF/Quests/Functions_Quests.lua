--[[
                                ----o----(||)----oo----(||)----o----

                                          Functions_Quests

                                       v1.02 - 17th June 2026
                                Copyright (C) Taraezor / Chris Birch
                                         All Rights Reserved

                                ----o----(||)----oo----(||)----o----
]]

-- Summary:
	-- All quest specific handling occurs here. Pet reporting is also here too

-- Available functions:

	-- ns.QuestTooltipLines( pin )	
	-- ns.PassQuestChecks( pin )

local _, ns = ...

-- Localisations
local GetTitleForQuestID= ( ns.version < 60000 ) and C_QuestLog.GetQuestInfo or C_QuestLog.GetTitleForQuestID
local IsQuestFlaggedCompleted = C_QuestLog.IsQuestFlaggedCompleted

local ipairs = _G.ipairs

-- ---------------------------------------------------------------------------------------------------------------------------------

local function ShowQuestStatus( quest, label, colour )
	if ns.firstOne == true then
		GameTooltip:AddLine( ns.colour.prefix .."\n" ..ns.L[ label ] )
		ns.firstOne = false
	end
	local questName = "  " ..colour ..( GetTitleForQuestID( quest.id ) or
						( ( quest.name ~= nil ) and ns.StringSubstitutions( quest.name ) or
						( ( ns.L[ tostring( quest.id ) ] ~= tostring( quest.id ) ) and ns.L[ tostring( quest.id ) ] or
						ns.L[ "Quest" ] .." = " .. quest.id ) ) )
						..( quest.level and ( ns.colour.plaintext .." (" ..ns.L[ "Level" ] .." " ..quest.level ..")" ) or "" )
	local completed = IsQuestFlaggedCompleted( quest.id )
	ns.CompletionShow( completed, questName, ns.name )
	if completed == false then ns.GuideTip( quest ) end
end

function ns.QuestTooltipLines( pin )
	-- Note the use of alwaysShow here: a false setting will prevent its display. Useful to hide long quest chains
	if pin.quests then
		ns.spaceLine = ""
		for i, v in ipairs( ns.questTypes ) do
			ns.firstOne = true
			for _, q in ipairs( pin.quests ) do
				if ns.PassGeneralChecks( q ) and ( q.qType == v ) and ( q.silent == nil ) then
					if q.alwaysShow == nil or q.alwaysShow == true then
						ShowQuestStatus( q, ns.questTypesDB[ i ], ns.questColours[ i ] )
					end
				end
			end
		end
		if ns.firstOne == false then ns.spaceLine = "\n" end
		ns.GuideTip( pin.quests )
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------

function ns.PassQuestChecks( pin )
	if pin.alwaysShow ~= nil and pin.alwaysShow == true then return true end
	if pin.quests == nil then return true end
	-- The idea is to return true as soon as we encounter a quest that's not yet completed / doesn't need checking.
	-- There is scope here for the AddOn to check each quest, not all quests generally.
	-- A pin is assumed to have just the one quests set and to not have subordinate quests sets within that quests set
	-- Note that pin.alwaysShow can occur at each level
	-- Note that pin.showAfter is designed for showing only the next uncompleted quest in a chain.
		-- This chain will be presented on screen "in order" if the set data is in order
	-- The default is to show a quest type. There is no provision to not ever show a quest type but there is provision to not show
	-- a quest of a quest type after the quest has been completed - set in the ns.questTypesRequired field in the data file.
	-- Note that in this case a "repeatable" quest should always be set to "false". See the data file.
	-- The showIfCompleted is an internal data flag that's unseen by the player. Perhaps some tooltip or some other module needs
	   -- the quest to have been completed in order for something to be shown. The player's "remove on completion" is ignored
	
	if ns.PassGeneralChecks( pin.quests ) == true then
		if pin.quests.alwaysShow ~= nil and pin.quests.alwaysShow == true then return true end
		for _, q in ipairs( pin.quests ) do
			if ns.PassGeneralChecks( q ) and ( ns.PassAddOnSpecificQuestChecks == nil or
												ns.PassAddOnSpecificQuestChecks( q ) == true ) then
				if q.alwaysShow ~= nil and q.alwaysShow == true then return true end
				local continueChecking = true
				if q.showAfter then
					-- Must ensure the showAfter quest is completed. If not then fail the check for this quest
					if IsQuestFlaggedCompleted( q.showAfter ) ~= true then continueChecking = false end
				end
				if continueChecking == true then
					if q.qType == nil then return true end
						-- By design a quest must have a qType. So we'll just assume it must be shown. Therefore return true
					for i, v in ipairs( ns.questTypes ) do -- As defined in Common_Quests
						if q.qType == v then
							if _G[ ns.db ][ ns.questTypesDB[ i ] ] == nil or _G[ ns.db ][ ns.questTypesDB[ i ] ] == true then
								-- Remove on completion player option is true. If nil then assume true
								if q.showIfCompleted == nil then -- See notes above
									if IsQuestFlaggedCompleted( q.id ) == false then return true end
									-- Player requested removal on completion. But the quest is not completed, thus show it
								else
									if IsQuestFlaggedCompleted( q.id ) == true then return true end
									-- See the note above
								end
							else
								return true
								-- False. So the player is requesting non-removal on completion. ie. Do nothing, so return true
							end
						end
					end
				end
			end
		end
		-- To here if we didn't find a quest that the player wanted to see
	end
	return false
end

