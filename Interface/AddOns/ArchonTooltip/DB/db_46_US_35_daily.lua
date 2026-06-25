local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Hunter-Survival','DemonHunter-Devourer','Paladin-Retribution','Druid-Feral','Druid-Restoration','Druid-Balance','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Warlock-Affliction','Priest-Holy','Hunter-Marksmanship','Mage-Arcane','Paladin-Protection','DeathKnight-Frost','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='BlackwingLair',name='US',type='daily',zone=46,date='2026-06-24',data={Af='Aftershocks:BAABLgAECn8fAAQBAAkJgRuyDwC3AQloDAAABABQAGkMAAAEAFgAawwAAAQAPwBqDAAAAwBUAGwMAAADADwAbQwAAAIAUgDqDAAABQBRAG4MAAADAB4AbwwAAAMASQABAAkJiRiyDwC3AQloDAAAAgBQAGkMAAADAFgAawwAAAMAPwBqDAAAAQAwAGwMAAABACQAbQwAAAEAUgDqDAAAAgAtAG4MAAACAB4AbwwAAAMASQACAAgJnw4tVgBdAQhoDAAAAQAQAGkMAAABADMAawwAAAEAMQBqDAAAAQAQAGwMAAABADMAbQwAAAEAEQDqDAAAAgBPAG4MAAABABAAAwAECQUXv10AywAEaAwAAAEAIgBqDAAAAQBUAGwMAAABADwA6gwAAAEAUQAAAA==.',
Ah='Ahnano:BAAALgADCgEJAQAAAA==.',
Am='Amar:BAAALgADCgUJCQAAAA==.',
Ar='Aranii:BAAALgAECgEJAgAAAA==.',
As='Assaultdeez:BAABLgAECn8VAAMEAAYJ2AosWgDoAAZoDAAABAAZAGkMAAAEABsAawwAAAQAFQBqDAAAAwAjAGwMAAACAB8A6gwAAAQAIQAEAAYJ2AosWgDoAAZoDAAABAAZAGkMAAAEABsAawwAAAQAFQBqDAAAAwAjAGwMAAACAB8A6gwAAAMAIQAFAAEJ0QHACAAWAAHqDAAAAQAEAAEuAAQKBwkIAAYAAAAA.Assaultme:BAAALgAECgQJBQABLgAECgcJCAAGAAAAAA==.Assaultnbatt:BAAALgADCgUJBgABLgAECgcJCAAGAAAAAA==.',
Az='Azriel:BAAALgAECgEJAQAAAA==.',
Ba='Baku:BAAALgAECgYJCwAAAA==.Balial:BAAALgAFFAIJAwAAAA==.Battlerez:BAABLgAECn8fAAMHAAcJfB9NFgAYAgdoDAAABgBeAGkMAAAGAEwAawwAAAYAWABqDAAAAwBiAGwMAAACAEQA6gwAAAcAVQBuDAAAAQBFAAcABwl8H00WABgCB2gMAAAGAF4AaQwAAAYATABrDAAABgBYAGoMAAADAGIAbAwAAAIARADqDAAABQBVAG4MAAABAEUACAABCXkJBVgAMgAB6gwAAAIAGAAAAA==.',
Be='Bearfiend:BAAALgADCgcJBwAAAA==.',
Bj='Bj:BAAALgAECgEJAQABLgAFFAQJCgAJAK0hAA==.',
Bl='Blackthorne:BAAALgADCgcJCgAAAA==.Blightbark:BAAALgADCgUJBQAAAA==.Blopi:BAAALgAECgEJAQAAAA==.',
Bo='Bobmcbobface:BAAALgAECgEJAQABLgAECgkJKQAKAFYhAA==.',
Bu='Bubblegyatt:BAABLgAECn8ZAAILAAYJlRxycACbAQZoDAAABQBBAGkMAAAGAE0AawwAAAQAUABqDAAABAAyAGwMAAAEAFMA6gwAAAIAOgALAAYJlRxycACbAQZoDAAABQBBAGkMAAAGAE0AawwAAAQAUABqDAAABAAyAGwMAAAEAFMA6gwAAAIAOgABLgAECggJJgALAEIfAA==.',
Ca='Calcio:BAAALgAFFAIJAwABLgAFFAMJBQALAFITAA==.',
Co='Conversed:BAABLgAFFH8HAAIMAAIJMxd+FACNAAJoDAAAAwBCAOoMAAAEADQADAACCTMXfhQAjQACaAwAAAMAQgDqDAAABAA0AAAA.Convy:BAABLgAECn8UAAMNAAkJChFpPACyAQloDAAAAwAzAGkMAAADACYAawwAAAMAGgBqDAAAAgAWAGwMAAADAD0AbQwAAAEAJwDqDAAAAwA9AG4MAAABACUAbwwAAAEANAANAAkJChFpPACyAQloDAAAAwAzAGkMAAACACYAawwAAAMAGgBqDAAAAgAWAGwMAAADAD0AbQwAAAEAJwDqDAAAAwA9AG4MAAABACUAbwwAAAEANAAOAAEJFwQQiQAmAAFpDAAAAQAKAAAA.Coreander:BAABLgAECn8UAAIPAAgJ3ggcmgBFAQhoDAAABAAYAGkMAAAEAB4AawwAAAUAIwBqDAAAAgAbAGwMAAACABsAbQwAAAEADADqDAAAAQAQAG4MAAABAAwADwAICd4IHJoARQEIaAwAAAQAGABpDAAABAAeAGsMAAAFACMAagwAAAIAGwBsDAAAAgAbAG0MAAABAAwA6gwAAAEAEABuDAAAAQAMAAAA.',
Cr='Crunchboi:BAAALgAECgQJCgAAAA==.',
Da='Dab:BAABLgAECn9PAAIIAAkJlh9RAAD/AgloDAAACwBfAGkMAAAKAFgAawwAAAoAUwBqDAAACgBhAGwMAAAJAEoAbQwAAAcARADqDAAADABVAG4MAAAGAFoAbwwAAAQAKwAIAAkJlh9RAAD/AgloDAAACwBfAGkMAAAKAFgAawwAAAoAUwBqDAAACgBhAGwMAAAJAEoAbQwAAAcARADqDAAADABVAG4MAAAGAFoAbwwAAAQAKwAAAA==.Daberina:BAAALgAECgEJAQAAAA==.Darklider:BAAALgAECgQJBgAAAA==.',
Dc='Dcmaster:BAAALgAECgEJAwAAAA==.',
De='Deabbzy:BAABLgAECn8kAAMQAAkJ4hQbQwD5AQloDAAABQA3AGkMAAAFADAAawwAAAUAOABqDAAABAA6AGwMAAAGAEcAbQwAAAMAOQDqDAAAAwAsAG4MAAAEADwAbwwAAAEAIgAQAAkJ4hQbQwD5AQloDAAABAA3AGkMAAAEADAAawwAAAQAOABqDAAABAA6AGwMAAAGAEcAbQwAAAMAOQDqDAAAAwAsAG4MAAAEADwAbwwAAAEAIgARAAMJwQavSQBnAANoDAAAAQATAGkMAAABAA4AawwAAAEAEgAAAA==.Dedal:BAABLgAECn8ZAAISAAgJtgpacQBeAQhoDAAABQAoAGkMAAADABkAawwAAAIAEwBqDAAAAwAmAGwMAAACACoAbQwAAAEAEgDqDAAACAAjAG4MAAABAAkAEgAICbYKWnEAXgEIaAwAAAUAKABpDAAAAwAZAGsMAAACABMAagwAAAMAJgBsDAAAAgAqAG0MAAABABIA6gwAAAgAIwBuDAAAAQAJAAAA.',
Du='Dumbchicken:BAAALgADCgcJBwABLgAECgkJKQAKAFYhAA==.Durto:BAAALgADCgcJBwABLgAECgQJCAAGAAAAAA==.',
Dz='Dzk:BAAALgAECgEJAQAAAA==.',
El='Eldthwefour:BAABLgAECn8bAAITAAgJbx4IAgDBAghoDAAAAgBUAGkMAAACAC0AawwAAAIARwBsDAAABABaAG0MAAAEAEIA6gwAAAUAWgBuDAAABABcAG8MAAAEAFIAEwAICW8eCAIAwQIIaAwAAAIAVABpDAAAAgAtAGsMAAACAEcAbAwAAAQAWgBtDAAABABCAOoMAAAFAFoAbgwAAAQAXABvDAAABABSAAAA.Eldthweone:BAACLgAFFH8LAAITAAQJCxMuBQA1AQRoDAAABABRAGkMAAACACQAawwAAAEAGADqDAAABAA0ABMABAkLEy4FADUBBGgMAAAEAFEAaQwAAAIAJABrDAAAAQAYAOoMAAAEADQALgAECn9VAAITAAkJ7R/NAQDQAgATAAkJ7R/NAQDQAgAAAA==.',
Eu='Eurykrates:BAAALgADCgYJBgAAAA==.',
Fl='Flämmå:BAAALgADCgIJAgAAAA==.',
Fu='Fubase:BAAALgAECgYJBgABLgAFFAIJBQAKAFQJAA==.',
Gi='Gingergnar:BAABLgAECn8hAAMEAAkJxRpSHAALAgloDAAABABRAGkMAAAEAFsAawwAAAQARwBqDAAABABPAGwMAAAGAEIAbQwAAAMAPQDqDAAAAwBAAG4MAAAEAE0AbwwAAAEAIQAEAAkJ7BhSHAALAgloDAAABABRAGkMAAAEAFsAawwAAAQARwBqDAAABABPAGwMAAAGAEIAbQwAAAMAPQDqDAAAAwBAAG4MAAADACcAbwwAAAEAIQAFAAEJVx74RgBXAAFuDAAAAQBNAAEuAAQKAwkDAAYAAAAA.',
Gr='Greyguard:BAAALgAECggJEwAAAA==.',
Gs='Gsnairb:BAAALgAECgkJDgAAAA==.',
Gu='Guillemønk:BAAALgADCgYJCQAAAA==.',
He='Healobot:BAABLgAECn8jAAIUAAkJJR3lDwBrAgloDAAABQBKAGkMAAAFAFMAawwAAAUATABqDAAAAwBSAGwMAAACADQAbQwAAAIASgDqDAAACABPAG4MAAADADoAbwwAAAIAWQAUAAkJJR3lDwBrAgloDAAABQBKAGkMAAAFAFMAawwAAAUATABqDAAAAwBSAGwMAAACADQAbQwAAAIASgDqDAAACABPAG4MAAADADoAbwwAAAIAWQAAAA==.',
Hu='Huldra:BAAALgADCgEJAQAAAA==.',
Hy='Hylax:BAACLgAFFH8XAAMVAAQJSyWvDACWAQRoDAAACABhAGkMAAAHAGMAawwAAAIAVwDqDAAABgBgABUABAlLJa8MAJYBBGgMAAAHAGEAaQwAAAYAYwBrDAAAAgBXAOoMAAAFAGAAEgADCcQlMjAATwEDaAwAAAEAYQBpDAAAAQBiAOoMAAABAF4ALgAECn8tAAIVAAgJKianBQBDAwAVAAgJKianBQBDAwAAAA==.Hypnotroll:BAAALgAECgIJBQAAAA==.',
Ih='Ihuntwabbits:BAAALgADCgEJAQABLgAECgcJCAAGAAAAAA==.',
In='Inesita:BAAALgAECgIJBAAAAA==.Innelli:BAABLgAECn8gAAMPAAgJIhDIfAB+AQhoDAAABgAqAGkMAAAGACYAawwAAAYAJABqDAAABAAyAGwMAAADADIAbQwAAAEAEwDqDAAABAAwAG4MAAACADUADwAICdwOyHwAfgEIaAwAAAMAJABpDAAAAwAmAGsMAAADACQAagwAAAMAMgBsDAAAAgAyAG0MAAABABMA6gwAAAIAHwBuDAAAAgA1ABYABgk9DfUJAO8ABmgMAAADACoAaQwAAAMAIgBrDAAAAwAZAGoMAAABAAoAbAwAAAEAEgDqDAAAAgAwAAAA.',
Ir='Irworeeyore:BAAALgADCgUJBQAAAA==.Irworeloch:BAAALgADCgcJBwAAAA==.',
Ja='Jasaris:BAABLgAECn8hAAIXAAkJTSUgAQBKAwloDAAABABgAGkMAAAEAGMAawwAAAQAYwBqDAAABABgAGwMAAAGAGEAbQwAAAMAXQDqDAAAAwBgAG4MAAAEAGMAbwwAAAEAUgAXAAkJTSUgAQBKAwloDAAABABgAGkMAAAEAGMAawwAAAQAYwBqDAAABABgAGwMAAAGAGEAbQwAAAMAXQDqDAAAAwBgAG4MAAAEAGMAbwwAAAEAUgAAAA==.Jasarish:BAAALgAECgMJAwABLgAECgkJIQAXAE0lAA==.',
Je='Jess:BAAALgAECgEJAQAAAA==.',
Jo='Jonnathan:BAABLgAECn8lAAIEAAkJCA9ZNADZAQloDAAACAA/AGkMAAAIADAAawwAAAYAMgBqDAAAAgARAGwMAAADACgAbQwAAAEACQDqDAAABwAwAG4MAAABABcAbwwAAAEAGAAEAAkJCA9ZNADZAQloDAAACAA/AGkMAAAIADAAawwAAAYAMgBqDAAAAgARAGwMAAADACgAbQwAAAEACQDqDAAABwAwAG4MAAABABcAbwwAAAEAGAAAAA==.Jounouw:BAAALgAECgQJCAAAAA==.',
Ju='Juzumaki:BAAALgADCgQJBAAAAA==.',
Ka='Kaltralak:BAAALgAECgMJCAABLgAECggJHgAPAAYYAA==.',
Ke='Ketheric:BAAALgAECgcJBwAAAA==.',
Kh='Khalorn:BAABLgAECn8UAAIYAAkJOgVtGgD9AAloDAAAAwAKAGkMAAABAAMAawwAAAEABwBqDAAAAQAKAGwMAAADABEAbQwAAAMAEQDqDAAAAwAPAG4MAAADABIAbwwAAAIAEQAYAAkJOgVtGgD9AAloDAAAAwAKAGkMAAABAAMAawwAAAEABwBqDAAAAQAKAGwMAAADABEAbQwAAAMAEQDqDAAAAwAPAG4MAAADABIAbwwAAAIAEQAAAA==.',
Ki='Killidén:BAAALgAECgQJBQAAAA==.Kiralas:BAAALgAECgMJAwABLgAECgkJGgAHAIYUAA==.Kirein:BAAALgADCgcJBwAAAA==.',
Ko='Komainu:BAABLgAECn8UAAIZAAYJNx7eAQDHAQZoDAAABABRAGkMAAAEAFUAawwAAAUAUwBqDAAAAgBPAGwMAAADAEEA6gwAAAIARQAZAAYJNx7eAQDHAQZoDAAABABRAGkMAAAEAFUAawwAAAUAUwBqDAAAAgBPAGwMAAADAEEA6gwAAAIARQAAAA==.',
Kr='Krahzkal:BAAALgADCgYJBgAAAA==.',
La='Lagat:BAAALgAECgMJAwAAAA==.',
Li='Lilithiia:BAAALgAECgcJDQAAAA==.Lirakas:BAABLgAECn8aAAMHAAkJhhQ+JQCuAQloDAAABABQAGkMAAAEAC0AawwAAAQAPABqDAAABABLAGwMAAAEADsAbQwAAAEAJADqDAAAAwA9AG4MAAABACAAbwwAAAEAKgAHAAkJhhQ+JQCuAQloDAAABABQAGkMAAADAC0AawwAAAQAPABqDAAAAQBLAGwMAAADADsAbQwAAAEAJADqDAAAAwA9AG4MAAABACAAbwwAAAEAKgAIAAMJkhSVPgC5AANpDAAAAQAhAGoMAAADADMAbAwAAAEASAAAAA==.',
Lo='Lonoa:BAAALgADCgEJAQAAAA==.',
Ma='Mackks:BAAALgAECggJEAAAAA==.Maell:BAAALgAECgQJBAAAAA==.Mariah:BAAALgAECgkJDgAAAA==.Marx:BAAALgADCgIJAgAAAA==.Maysie:BAAALgADCgIJAwAAAA==.',
Mc='Mcnugget:BAAALgAECgMJBQABLgAFFAMJBQAZADccAA==.',
Me='Melgibson:BAAALgAECgkJCgAAAA==.Mercury:BAAALgAECgUJEAAAAA==.Mestrois:BAAALgADCgEJAQAAAA==.',
Mi='Milch:BAABLgAECn8oAAIPAAcJnRGyrAAnAQdoDAAABwAlAGkMAAAIACsAawwAAAcAIQBqDAAABgAcAGwMAAAGAEYAbQwAAAEANADqDAAABQAhAA8ABwmdEbKsACcBB2gMAAAHACUAaQwAAAgAKwBrDAAABwAhAGoMAAAGABwAbAwAAAYARgBtDAAAAQA0AOoMAAAFACEAAAA=.Minipriest:BAAALgAFFAQJCwABLgAFFAgJJwAaALMQAQ==.Minivoker:BAACLgAFFH8nAAMaAAgJsxBYCQAWAghoDAAACABXAGkMAAAHAEgAawwAAAYALgBqDAAABAAVAGwMAAACABsAbQwAAAEACwDqDAAACgBJAG4MAAABAAAAGgAICbMQWAkAFgIIaAwAAAYAVwBpDAAABQBIAGsMAAAEAC4AagwAAAMAFQBsDAAAAgAbAG0MAAABAAsA6gwAAAYASQBuDAAAAQAAABsABQkNH28mADUBBWgMAAACAFsAaQwAAAIATQBrDAAAAgA/AGoMAAABADMA6gwAAAQAVQAuAAQKf0sAAxoACQk3IRkDACEDABoACQk3IRkDACEDABsACQmqIW0GAPQCAAAA.',
Mo='Moop:BAAALgAECgYJAQAAAA==.',
Ni='Nilsine:BAAALgADCgcJBwAAAA==.',
No='Noelle:BAAALgAECgIJAwAAAA==.',
Ny='Nycci:BAAALgADCgUJBwAAAA==.',
On='Onyx:BAAALgAECgcJEwAAAA==.',
Op='Oppa:BAAALgAECgEJAgABLgAFFAIJAwAGAAAAAA==.',
Pa='Pailiah:BAAALgAECgUJDQABLgAECgYJCwAGAAAAAA==.',
Pi='Pinkchicken:BAAALgADCgkJCwABLgAECgkJKQAKAFYhAA==.',
Po='Potadpole:BAAALgAFFAEJAQABLgAFFAYJEwAbAH4aAA==.',
Pu='Purplenerple:BAAALgAECgcJCAAAAA==.',
Qa='Qamar:BAAALgAFFAIJAwAAAA==.',
Re='Reloth:BAAALgAECggJEQAAAA==.',
Ro='Rosealee:BAAALgAECgEJAQAAAA==.',
Ru='Rune:BAABLgAECn8sAAIRAAkJdiP+AgAVAwloDAAABQBgAGkMAAAFAFwAawwAAAUAXgBqDAAABQBZAGwMAAAGAFsAbQwAAAIAWwDqDAAABwBbAG4MAAAHAF0AbwwAAAIASwARAAkJdiP+AgAVAwloDAAABQBgAGkMAAAFAFwAawwAAAUAXgBqDAAABQBZAGwMAAAGAFsAbQwAAAIAWwDqDAAABwBbAG4MAAAHAF0AbwwAAAIASwAAAA==.',
Sa='Saiola:BAAALgAECgUJBgAAAA==.Sapphira:BAAALgADCgIJAgAAAA==.Sauriel:BAAALgAECgEJAgABLgAFFAIJAwAGAAAAAA==.',
Se='Sellz:BAAALgAECgMJBAAAAA==.Serf:BAACLgAFFH8GAAIOAAIJ1RXvOwCFAAJoDAAAAgA3AOoMAAAEADgADgACCdUV7zsAhQACaAwAAAIANwDqDAAABAA4AC4ABAp/NgACDgAJCZsc1QwAigIADgAJCZsc1QwAigIAAAA=.Setra:BAABLgAECn8XAAMTAAkJExVBCQDQAQloDAAABABQAGkMAAADAEMAawwAAAMASABqDAAAAgAjAGwMAAAEADIAbQwAAAEAMQDqDAAAAgATAG4MAAADADcAbwwAAAEAIwATAAgJ/RZBCQDQAQhoDAAAAgBQAGkMAAADAEMAawwAAAMASABqDAAAAgAjAGwMAAAEADIAbQwAAAEAMQBuDAAAAgA3AG8MAAABACMAHAADCSgFBPoAcAADaAwAAAIACgDqDAAAAgATAG4MAAABAAkAAAA=.Settio:BAABLgAECn8bAAMUAAkJQQXmOAAXAQloDAAABAATAGkMAAAEAA0AawwAAAQAGABqDAAAAwAIAGwMAAAFABYAbQwAAAIACQDqDAAAAgAKAG4MAAACAAYAbwwAAAEABAAUAAkJQQXmOAAXAQloDAAAAwATAGkMAAADAA0AawwAAAMAGABqDAAAAwAIAGwMAAAFABYAbQwAAAIACQDqDAAAAgAKAG4MAAACAAYAbwwAAAEABAAHAAMJsQJreQBMAANoDAAAAQAJAGkMAAABAAYAawwAAAEABAAAAA==.',
Sh='Shaboom:BAAALgADCgIJAgABLgAECggJJgALAEIfAA==.Shruggon:BAAALgADCgEJAQAAAA==.',
Sl='Slev:BAACLgAFFH8FAAIZAAMJNxxkMADzAANoDAAAAgBEAGkMAAACAEsA6gwAAAEASAAZAAMJNxxkMADzAANoDAAAAgBEAGkMAAACAEsA6gwAAAEASAAuAAQKfyUABBkABgmkIXYUACUCABkABgmkIXYUACUCAB0AAwkhDYd3AGIAAB4AAQkAAMevAAAAAAAA.Slevatelli:BAAALgAECgIJAgABLgAFFAMJBQAZADccAA==.',
Sm='Smecky:BAAALgAECgEJAQAAAA==.',
So='Songoku:BAAALgAECgYJDwAAAA==.',
St='Sterey:BAAALgADCgcJCQAAAA==.Styles:BAAALgAECgcJDQABLgAECggJJgALAEIfAA==.',
Sw='Switchout:BAAALgADCgYJBgAAAA==.',
Te='Tehkromlech:BAAALgAECgcJDwAAAA==.Tetankeo:BAABLgAECn8WAAIfAAgJkRw/EgDNAQhoDAAABQBTAGkMAAAEAFAAawwAAAMAQgBqDAAAAgBHAGwMAAACAE4AbQwAAAEAOADqDAAABABXAG4MAAABADoAHwAICZEcPxIAzQEIaAwAAAUAUwBpDAAABABQAGsMAAADAEIAagwAAAIARwBsDAAAAgBOAG0MAAABADgA6gwAAAQAVwBuDAAAAQA6AAAA.',
Ti='Timeover:BAAALgADCgEJAQAAAA==.',
Tk='Tk:BAAALgADCgcJBQAAAA==.Tkdragon:BAAALgAFFAIJBAAAAA==.',
To='Tobolaeh:BAABLgAECn8UAAMLAAcJnBwRdwCAAQdoDAAABQBKAGkMAAAEAFMAawwAAAMASQBqDAAAAQA1AGwMAAACAFsA6gwAAAQASgBuDAAAAQArAAsABgmuHhF3AIABBmgMAAAFAEoAaQwAAAQAUwBrDAAAAwBJAGoMAAABADUAbAwAAAEAWwDqDAAAAwBGABcAAwl6GGszAJUAA2wMAAABAEYA6gwAAAEASgBuDAAAAQArAAEuAAQKCQkjABQAJR0A.',
Tu='Turbomoose:BAAALgAECgMJAwAAAA==.',
Ty='Tylenolplus:BAAALgAECgMJAwAAAA==.',
Ul='Ulthrax:BAAALgAECgEJAQAAAA==.',
Va='Vaedalth:BAAALgADCgQJBAABLgAECgkJGgALANsVAA==.Vane:BAAALgAECgMJAwAAAA==.',
Ve='Veil:BAAALgAECgQJCAABLgAECgYJCwAGAAAAAA==.',
Wa='Warfrenzy:BAAALgAECgIJAgAAAA==.',
Xa='Xaletara:BAAALgADCgcJBwAAAA==.',
Xb='Xbite:BAAALgAECgQJBAAAAA==.',
Xe='Xennion:BAAALgADCgIJAgAAAA==.',
Xf='Xfallenhealz:BAAALgAECgIJAgAAAA==.Xfallenlight:BAAALgADCgcJCwAAAA==.',
Yi='Yiirn:BAABLgAECn8YAAIXAAUJlB/9FgBpAQVoDAAABQBNAGkMAAAGAFIAawwAAAUATwBqDAAAAwBNAOoMAAAFAFMAFwAFCZQf/RYAaQEFaAwAAAUATQBpDAAABgBSAGsMAAAFAE8AagwAAAMATQDqDAAABQBTAAAA.',
Yo='Yoko:BAAALgADCgIJAgAAAA==.',
Zu='Zugzugz:BAAALgAECgYJEQABLgAFFAYJHAAPAGAPAA==.',
['Ðr']='Ðred:BAAALgAECgEJAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
