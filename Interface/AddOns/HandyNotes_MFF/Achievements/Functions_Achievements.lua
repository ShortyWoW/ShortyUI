--[[
                                ----o----(||)----oo----(||)----o----

                                       Functions_Achievements

                                       v1.01 - 23rd June 2026
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
local GetAchievementCriteriaInfo = GetAchievementCriteriaInfo
local GetAchievementInfo = GetAchievementInfo
local GetAchievementNumCriteria = GetAchievementNumCriteria

local ipairs, select = _G.ipairs, select

-- ---------------------------------------------------------------------------------------------------------------------------------

local function ShowAchievementStatus( a, criteria, detail )

	local _, aName, _, completedA, _, _, _, description = GetAchievementInfo( a.id )
	if ns.firstOne == true then
		GameTooltip:AddLine( "\n" ..ns.colour.prefix ..ns.L[ "Achievements" ] )
		ns.firstOne = false
	end
	ns.CompletionShow( completedA, ( ( ns.colour.achieveH or ns.colour.highlight ) ..( ( a.name == nil ) and aName
									or ( ns.StringSubstitutions( a.name ) ) ) ) )

	local continue = ( a.criteria == nil ) and criteria or a.criteria
	if continue == false then
		if completedA == false then ns.GuideTip( a ) end
		return
	end

	local numCriteria = GetAchievementNumCriteria( a.id )
	if numCriteria == nil then
		if completedA == false then ns.GuideTip( a ) end
		return
	end
		
	local iStart, iEnd = a.iStart or a.index or 1, a.iEnd or a.index or numCriteria
	if iStart == iEnd then
		if numCriteria ~= iStart then continue = false end
	elseif iStart > iEnd then
		if ( numCriteria < iStart ) or ( iEnd < 1 ) then continue = false end
	else
		if ( numCriteria < iEnd ) or ( iStart < 1 ) then continue = false end
	end	
	if continue == false then
		if completedA == false then ns.GuideTip( a ) end
		return
	end

	for i = iStart, iEnd do
		local cName, cType, completedC, _, _, charName, _, assetID = GetAchievementCriteriaInfo( a.id, i )
		continue = true
		if ( a.onlyShowUncompleted ~= nil ) and ( a.onlyShowUncompleted == true) and ( completedC == true ) then
			continue = false
		end
		if continue == true then
			ns.CompletionShow( completedC, ( ( ns.colour.achieveI or ns.colour.guide or ns.colour.plaintext ) .."  " ..cName ) )
		end
	end

	if description == nil then
		if completedA == false then ns.GuideTip( a ) end
		return
	end
	if ( a.detail == nil ) then
		if ( detail == nil ) or ( detail == 0 ) then
			continue = false
		elseif ( detail == 1 ) and ( completedA == true ) then
			continue = false
		end
	elseif a.detail == 0 then
		continue = false
	else
		if ( a.detail == 1 ) and ( completedA == true ) then
			continue = false
		end
	end
	if continue == false then
		if completedA == false then ns.GuideTip( a ) end
		return
	end

	GameTooltip:AddLine( ( ns.colour.achieveD or ns.colour.plaintext ) ..description )
	if completedA == false then ns.GuideTip( a ) end
end

function ns.AchievementTooltipLines( pin )
	-- The player can easily get swamped with data here, thus the pin.detail and pin.criteria flags
		-- criteria = false or nil : achievement name only
		-- criteria = true  : achievement name plus a line per criteria if such exist
		-- detail = 0 or nil : no description data
		-- detail = 1 : description data if uncompleted
		-- detail = 2 : description data always		
	-- Note the use of alwaysShow here: a false setting will prevent its display
	if ns.version < 30002 then return end -- Achievements didn't exist prior to WotLK.
	if pin.achievements then
		ns.spaceLine = ""
		ns.firstOne = true
		local criteria, detail = ( pin.achievements.criteria or false ), ( pin.achievements.detail or 0 )
		for _, a in ipairs( pin.achievements ) do
			if ns.PassGeneralChecks( a ) then
				if a.alwaysShow == nil or a.alwaysShow == true then
					ShowAchievementStatus( a, criteria, detail )
				end
			end
		end
		if ns.firstOne == false then ns.spaceLine = "\n" end
		ns.GuideTip( pin.achievements )
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------

function ns.PassAchievementChecks( pin )
	if pin.alwaysShow ~= nil and pin.alwaysShow == true then return true end
	if pin.achievements == nil then return true end
	if ns.version < 30002 then return true end -- Achievements didn't exist prior to WotLK. So we'll ignore them for now.
	-- The idea is to return true as soon as we encounter an achievement that's not yet completed / doesn't need checking.
	-- There is scope here for the AddOn to check each achievement, not all achievements generally.
	-- A pin is assumed to have just the one achievements set and to not have subordinate achievements sets within that set
	-- Note that pin.alwaysShow can occur at each level
	if ns.PassGeneralChecks( pin.achievements ) == true then
		if pin.achievements.alwaysShow ~= nil and pin.achievements.alwaysShow == true then return true end
		if _G[ ns.db ][ "Achievements" ] == nil or _G[ ns.db ][ "Achievements" ] == true then
			-- ie: the default is to remove when completed
			for _,a in ipairs( pin.achievements ) do			
				if ns.PassGeneralChecks( a ) and ( ns.PassAddOnSpecificAchievementChecks == nil or
						ns.PassAddOnSpecificAchievementChecks( a ) == true ) then
					if a.alwaysShow ~= nil and a.alwaysShow == true then return true end
					local completed = select( 4, GetAchievementInfo( a.id ) )
					if a.showIfCompleted ~= nil then				
						if completed == true then return true end						
					elseif completed == false then
						return true
					end
				end
			end
		else
			return true
		end
	end
	return false
end