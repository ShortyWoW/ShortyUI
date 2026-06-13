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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Warrior-Fury','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Hunter-Survival','DemonHunter-Devourer','Paladin-Retribution','Druid-Feral','Druid-Restoration','Druid-Balance','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Warlock-Affliction','Warrior-Protection','Priest-Holy','Hunter-Marksmanship','Mage-Arcane','Paladin-Protection','DeathKnight-Frost','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='BlackwingLair',name='US',type='daily',zone=46,date='2026-06-13',data={Af='Aftershocks:BAABLgAECn8WAAMBAAkJdxdrDwDCAQloDAAAAwBQAGkMAAADAFgAawwAAAMAPwBqDAAAAgAwAGwMAAACACQAbQwAAAIAUgDqDAAABAAtAG4MAAACAB4AbwwAAAEAMwABAAkJdxdrDwDCAQloDAAAAgBQAGkMAAACAFgAawwAAAIAPwBqDAAAAQAwAGwMAAABACQAbQwAAAEAUgDqDAAAAgAtAG4MAAABAB4AbwwAAAEAMwACAAgJnw7NVABdAQhoDAAAAQAQAGkMAAABADMAawwAAAEAMQBqDAAAAQAQAGwMAAABADMAbQwAAAEAEQDqDAAAAgBPAG4MAAABABAAAAA=.',
Ah='Ahnano:BAAALgADCgEJAQAAAA==.',
Am='Amar:BAAALgADCgUJCQAAAA==.',
Ar='Aranii:BAAALgAECgEJAgAAAA==.',
As='Assaultdeez:BAABLgAECn8UAAIDAAYJ2AotWADtAAZoDAAABAAZAGkMAAAEABsAawwAAAQAFQBqDAAAAwAjAGwMAAACAB8A6gwAAAMAIQADAAYJ2AotWADtAAZoDAAABAAZAGkMAAAEABsAawwAAAQAFQBqDAAAAwAjAGwMAAACAB8A6gwAAAMAIQABLgAECgcJCAAEAAAAAA==.Assaultme:BAAALgAECgQJBQABLgAECgcJCAAEAAAAAA==.Assaultnbatt:BAAALgADCgUJBgABLgAECgcJCAAEAAAAAA==.',
Ba='Baku:BAAALgAECgYJCgAAAA==.Balial:BAAALgAFFAIJAwAAAA==.Battlerez:BAABLgAECn8fAAMFAAcJfB8UFgAZAgdoDAAABgBeAGkMAAAGAEwAawwAAAYAWABqDAAAAwBiAGwMAAACAEQA6gwAAAcAVQBuDAAAAQBFAAUABwl8HxQWABkCB2gMAAAGAF4AaQwAAAYATABrDAAABgBYAGoMAAADAGIAbAwAAAIARADqDAAABQBVAG4MAAABAEUABgABCXkJBVgAMgAB6gwAAAIAGAAAAA==.',
Be='Bearfiend:BAAALgADCgcJBwAAAA==.',
Bj='Bj:BAAALgAECgEJAQABLgAFFAQJCgAHAK0hAA==.',
Bl='Blackthorne:BAAALgADCgcJCgAAAA==.Blightbark:BAAALgADCgUJBQAAAA==.Blopi:BAAALgAECgEJAQAAAA==.',
Bo='Bobmcbobface:BAAALgAECgEJAQABLgAECgkJKQAIAFYhAA==.',
Bu='Bubblegyatt:BAABLgAECn8ZAAIJAAYJlRxycACbAQZoDAAABQBBAGkMAAAGAE0AawwAAAQAUABqDAAABAAyAGwMAAAEAFMA6gwAAAIAOgAJAAYJlRxycACbAQZoDAAABQBBAGkMAAAGAE0AawwAAAQAUABqDAAABAAyAGwMAAAEAFMA6gwAAAIAOgABLgAECggJJgAJAEIfAA==.',
Ca='Calcio:BAAALgAFFAIJAwABLgAFFAMJBQAJAFITAA==.',
Co='Conversed:BAABLgAFFH8GAAIKAAIJMxeFEwCNAAJoDAAAAwBCAOoMAAADADQACgACCTMXhRMAjQACaAwAAAMAQgDqDAAAAwA0AAAA.Convy:BAABLgAECn8UAAMLAAkJChFpPACyAQloDAAAAwAzAGkMAAADACYAawwAAAMAGgBqDAAAAgAWAGwMAAADAD0AbQwAAAEAJwDqDAAAAwA9AG4MAAABACUAbwwAAAEANAALAAkJChFpPACyAQloDAAAAwAzAGkMAAACACYAawwAAAMAGgBqDAAAAgAWAGwMAAADAD0AbQwAAAEAJwDqDAAAAwA9AG4MAAABACUAbwwAAAEANAAMAAEJFwQQiQAmAAFpDAAAAQAKAAAA.Coreander:BAABLgAECn8UAAINAAgJ3gjUlwBGAQhoDAAABAAYAGkMAAAEAB4AawwAAAUAIwBqDAAAAgAbAGwMAAACABsAbQwAAAEADADqDAAAAQAQAG4MAAABAAwADQAICd4I1JcARgEIaAwAAAQAGABpDAAABAAeAGsMAAAFACMAagwAAAIAGwBsDAAAAgAbAG0MAAABAAwA6gwAAAEAEABuDAAAAQAMAAAA.',
Cr='Crunchboi:BAAALgAECgQJCgAAAA==.',
Da='Dab:BAABLgAECn9GAAIGAAkJ0h4zBQA2AwloDAAACgBfAGkMAAAJAFgAawwAAAkAUwBqDAAACQBhAGwMAAAIAEAAbQwAAAYAQADqDAAACwBUAG4MAAAFAFcAbwwAAAMAKwAGAAkJ0h4zBQA2AwloDAAACgBfAGkMAAAJAFgAawwAAAkAUwBqDAAACQBhAGwMAAAIAEAAbQwAAAYAQADqDAAACwBUAG4MAAAFAFcAbwwAAAMAKwAAAA==.Daberina:BAAALgADCgIJAgAAAA==.Darklider:BAAALgAECgQJBgAAAA==.',
Dc='Dcmaster:BAAALgAECgEJAwAAAA==.',
De='Deabbzy:BAABLgAECn8kAAMOAAkJ4hSeQQD7AQloDAAABQA3AGkMAAAFADAAawwAAAUAOABqDAAABAA6AGwMAAAGAEcAbQwAAAMAOQDqDAAAAwAsAG4MAAAEADwAbwwAAAEAIgAOAAkJ4hSeQQD7AQloDAAABAA3AGkMAAAEADAAawwAAAQAOABqDAAABAA6AGwMAAAGAEcAbQwAAAMAOQDqDAAAAwAsAG4MAAAEADwAbwwAAAEAIgAPAAMJwQavSABnAANoDAAAAQATAGkMAAABAA4AawwAAAEAEgAAAA==.Dedal:BAABLgAECn8ZAAIQAAgJtgoqbwBeAQhoDAAABQAoAGkMAAADABkAawwAAAIAEwBqDAAAAwAmAGwMAAACACoAbQwAAAEAEgDqDAAACAAjAG4MAAABAAkAEAAICbYKKm8AXgEIaAwAAAUAKABpDAAAAwAZAGsMAAACABMAagwAAAMAJgBsDAAAAgAqAG0MAAABABIA6gwAAAgAIwBuDAAAAQAJAAAA.',
Du='Dumbchicken:BAAALgADCgcJBwABLgAECgkJKQAIAFYhAA==.Durto:BAAALgADCgcJBwABLgAECgQJCAAEAAAAAA==.',
Dz='Dzk:BAAALgAECgEJAQAAAA==.',
El='Eldthwefour:BAABLgAECn8WAAIRAAgJYh30AQDDAghoDAAAAgBUAGkMAAACAC0AawwAAAIARwBsDAAAAwBaAG0MAAADAEAA6gwAAAQAWgBuDAAAAwBRAG8MAAADAEoAEQAICWId9AEAwwIIaAwAAAIAVABpDAAAAgAtAGsMAAACAEcAbAwAAAMAWgBtDAAAAwBAAOoMAAAEAFoAbgwAAAMAUQBvDAAAAwBKAAAA.Eldthweone:BAACLgAFFH8LAAIRAAQJCxPZBAA4AQRoDAAABABRAGkMAAACACQAawwAAAEAGADqDAAABAA0ABEABAkLE9kEADgBBGgMAAAEAFEAaQwAAAIAJABrDAAAAQAYAOoMAAAEADQALgAECn9NAAIRAAkJnh+0AQDSAgARAAkJnh+0AQDSAgAAAA==.',
Eu='Eurykrates:BAAALgADCgYJBgAAAA==.',
Fl='Flämmå:BAAALgADCgIJAgAAAA==.',
Fu='Fubase:BAAALgAECgYJBgABLgAFFAIJAwAEAAAAAA==.',
Gi='Gingergnar:BAABLgAECn8hAAMDAAkJxRrdGwANAgloDAAABABRAGkMAAAEAFsAawwAAAQARwBqDAAABABPAGwMAAAGAEIAbQwAAAMAPQDqDAAAAwBAAG4MAAAEAE0AbwwAAAEAIQADAAkJ7BjdGwANAgloDAAABABRAGkMAAAEAFsAawwAAAQARwBqDAAABABPAGwMAAAGAEIAbQwAAAMAPQDqDAAAAwBAAG4MAAADACcAbwwAAAEAIQASAAEJVx6rRQBXAAFuDAAAAQBNAAEuAAQKAwkDAAQAAAAA.',
Gr='Greyguard:BAAALgAECgYJEgAAAA==.',
Gs='Gsnairb:BAAALgAECggJDQAAAA==.',
Gu='Guillemønk:BAAALgADCgYJCQAAAA==.',
He='Healobot:BAABLgAECn8iAAITAAkJWBqfDwBrAgloDAAABQBKAGkMAAAFAFMAawwAAAUATABqDAAAAwBSAGwMAAACADQAbQwAAAIASgDqDAAACABPAG4MAAADADoAbwwAAAEAGAATAAkJWBqfDwBrAgloDAAABQBKAGkMAAAFAFMAawwAAAUATABqDAAAAwBSAGwMAAACADQAbQwAAAIASgDqDAAACABPAG4MAAADADoAbwwAAAEAGAAAAA==.',
Hu='Huldra:BAAALgADCgEJAQAAAA==.',
Hy='Hylax:BAACLgAFFH8XAAMUAAQJSyU9DACbAQRoDAAACABhAGkMAAAHAGMAawwAAAIAVwDqDAAABgBgABQABAlLJT0MAJsBBGgMAAAHAGEAaQwAAAYAYwBrDAAAAgBXAOoMAAAFAGAAEAADCcQl6SwAUQEDaAwAAAEAYQBpDAAAAQBiAOoMAAABAF4ALgAECn8tAAIUAAgJKianBQBDAwAUAAgJKianBQBDAwAAAA==.Hypnotroll:BAAALgAECgIJBQAAAA==.',
Ih='Ihuntwabbits:BAAALgADCgEJAQABLgAECgcJCAAEAAAAAA==.',
In='Inesita:BAAALgAECgIJBAAAAA==.Innelli:BAABLgAECn8gAAMNAAgJIhDqegB/AQhoDAAABgAqAGkMAAAGACYAawwAAAYAJABqDAAABAAyAGwMAAADADIAbQwAAAEAEwDqDAAABAAwAG4MAAACADUADQAICdwO6noAfwEIaAwAAAMAJABpDAAAAwAmAGsMAAADACQAagwAAAMAMgBsDAAAAgAyAG0MAAABABMA6gwAAAIAHwBuDAAAAgA1ABUABgk9DbsJAO8ABmgMAAADACoAaQwAAAMAIgBrDAAAAwAZAGoMAAABAAoAbAwAAAEAEgDqDAAAAgAwAAAA.',
Ir='Irworeeyore:BAAALgADCgUJBQAAAA==.Irworeloch:BAAALgADCgcJBwAAAA==.',
Ja='Jasaris:BAABLgAECn8hAAIWAAkJTSUTAQBLAwloDAAABABgAGkMAAAEAGMAawwAAAQAYwBqDAAABABgAGwMAAAGAGEAbQwAAAMAXQDqDAAAAwBgAG4MAAAEAGMAbwwAAAEAUgAWAAkJTSUTAQBLAwloDAAABABgAGkMAAAEAGMAawwAAAQAYwBqDAAABABgAGwMAAAGAGEAbQwAAAMAXQDqDAAAAwBgAG4MAAAEAGMAbwwAAAEAUgAAAA==.Jasarish:BAAALgAECgMJAwABLgAECgkJIQAWAE0lAA==.',
Je='Jess:BAAALgAECgEJAQAAAA==.',
Jo='Jonnathan:BAABLgAECn8lAAIDAAkJCA9ZNADZAQloDAAACAA/AGkMAAAIADAAawwAAAYAMgBqDAAAAgARAGwMAAADACgAbQwAAAEACQDqDAAABwAwAG4MAAABABcAbwwAAAEAGAADAAkJCA9ZNADZAQloDAAACAA/AGkMAAAIADAAawwAAAYAMgBqDAAAAgARAGwMAAADACgAbQwAAAEACQDqDAAABwAwAG4MAAABABcAbwwAAAEAGAAAAA==.Jounouw:BAAALgAECgQJCAAAAA==.',
Ju='Juzumaki:BAAALgADCgQJBAAAAA==.',
Ka='Kaltralak:BAAALgAECgMJCAABLgAECggJHgANAAYYAA==.',
Kh='Khalorn:BAABLgAECn8UAAIXAAkJOgVvGQAEAQloDAAAAwAKAGkMAAABAAMAawwAAAEABwBqDAAAAQAKAGwMAAADABEAbQwAAAMAEQDqDAAAAwAPAG4MAAADABIAbwwAAAIAEQAXAAkJOgVvGQAEAQloDAAAAwAKAGkMAAABAAMAawwAAAEABwBqDAAAAQAKAGwMAAADABEAbQwAAAMAEQDqDAAAAwAPAG4MAAADABIAbwwAAAIAEQAAAA==.',
Ki='Killidén:BAAALgAECgQJBQAAAA==.Kiralas:BAAALgAECgMJAwABLgAECgkJGgAFAIYUAA==.',
Ko='Komainu:BAAALgAECgYJCwAAAA==.',
Kr='Krahzkal:BAAALgADCgYJBgAAAA==.',
La='Lagat:BAAALgAECgMJAwAAAA==.',
Li='Lilithiia:BAAALgAECgcJDQAAAA==.Lirakas:BAABLgAECn8aAAMFAAkJhhQ+JQCuAQloDAAABABQAGkMAAAEAC0AawwAAAQAPABqDAAABABLAGwMAAAEADsAbQwAAAEAJADqDAAAAwA9AG4MAAABACAAbwwAAAEAKgAFAAkJhhQ+JQCuAQloDAAABABQAGkMAAADAC0AawwAAAQAPABqDAAAAQBLAGwMAAADADsAbQwAAAEAJADqDAAAAwA9AG4MAAABACAAbwwAAAEAKgAGAAMJkhSVPgC5AANpDAAAAQAhAGoMAAADADMAbAwAAAEASAAAAA==.',
Lo='Lonoa:BAAALgADCgEJAQAAAA==.',
Ma='Mackks:BAAALgAECggJEAAAAA==.Maell:BAAALgAECgQJBAAAAA==.Mariah:BAAALgAECggJDQAAAA==.Marx:BAAALgADCgIJAgAAAA==.Maysie:BAAALgADCgIJAwAAAA==.',
Mc='Mcnugget:BAAALgAECgMJBQABLgAECggJJQAYAKQhAA==.',
Me='Melgibson:BAAALgAECgkJBAAAAA==.Mercury:BAAALgAECgUJEAAAAA==.Mestrois:BAAALgADCgEJAQAAAA==.',
Mi='Milch:BAABLgAECn8iAAINAAYJJg1axAD/AAZoDAAABgAlAGkMAAAHAB0AawwAAAYAIQBqDAAABQAWAGwMAAAFACIA6gwAAAUAIQANAAYJJg1axAD/AAZoDAAABgAlAGkMAAAHAB0AawwAAAYAIQBqDAAABQAWAGwMAAAFACIA6gwAAAUAIQAAAA==.Minipriest:BAAALgAFFAQJCwABLgAFFAgJJQAZADoPAQ==.Minivoker:BAACLgAFFH8lAAMZAAgJOg/YCAAXAghoDAAABwA5AGkMAAAHAEgAawwAAAYALgBqDAAABAAVAGwMAAACABsAbQwAAAEACwDqDAAACQBJAG4MAAABAAAAGQAICToP2AgAFwIIaAwAAAUAOQBpDAAABQBIAGsMAAAEAC4AagwAAAMAFQBsDAAAAgAbAG0MAAABAAsA6gwAAAYASQBuDAAAAQAAABoABQnQGLAkADkBBWgMAAACAFsAaQwAAAIATQBrDAAAAgA/AGoMAAABADMA6gwAAAMAFQAuAAQKf0sAAxkACQk3IQsDACEDABkACQk3IQsDACEDABoACQmqIU8GAPUCAAAA.',
Mo='Moop:BAAALgAECgYJAQAAAA==.',
Ni='Nilsine:BAAALgADCgcJBwAAAA==.',
No='Noelle:BAAALgAECgIJAwAAAA==.',
Ny='Nycci:BAAALgADCgUJBwAAAA==.',
On='Onyx:BAAALgAECgcJEwAAAA==.',
Op='Oppa:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Pa='Pailiah:BAAALgAECgUJDQABLgAECgYJCgAEAAAAAA==.',
Pi='Pinkchicken:BAAALgADCgkJCwABLgAECgkJKQAIAFYhAA==.',
Po='Potadpole:BAAALgAFFAEJAQABLgAFFAYJEwAaAH4aAA==.',
Pu='Purplenerple:BAAALgAECgcJCAAAAA==.',
Qa='Qamar:BAAALgAFFAIJAwAAAA==.',
Re='Reloth:BAAALgAECggJEQAAAA==.',
Ro='Rosealee:BAAALgAECgEJAQAAAA==.',
Ru='Rune:BAABLgAECn8oAAIPAAkJdiPmAgAXAwloDAAABQBgAGkMAAAFAFwAawwAAAUAXgBqDAAABQBZAGwMAAAGAFsAbQwAAAEAWwDqDAAABQBbAG4MAAAGAF0AbwwAAAIASwAPAAkJdiPmAgAXAwloDAAABQBgAGkMAAAFAFwAawwAAAUAXgBqDAAABQBZAGwMAAAGAFsAbQwAAAEAWwDqDAAABQBbAG4MAAAGAF0AbwwAAAIASwAAAA==.',
Sa='Saiola:BAAALgAECgUJBgAAAA==.Sapphira:BAAALgADCgIJAgAAAA==.Sauriel:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Se='Sellz:BAAALgAECgMJBAAAAA==.Serf:BAACLgAFFH8FAAIMAAIJ1RU8OgCFAAJoDAAAAgA3AOoMAAADADgADAACCdUVPDoAhQACaAwAAAIANwDqDAAAAwA4AC4ABAp/NgACDAAJCZscgQwAjAIADAAJCZscgQwAjAIAAAA=.Setra:BAABLgAECn8XAAMRAAkJExX/CADRAQloDAAABABQAGkMAAADAEMAawwAAAMASABqDAAAAgAjAGwMAAAEADIAbQwAAAEAMQDqDAAAAgATAG4MAAADADcAbwwAAAEAIwARAAgJ/Rb/CADRAQhoDAAAAgBQAGkMAAADAEMAawwAAAMASABqDAAAAgAjAGwMAAAEADIAbQwAAAEAMQBuDAAAAgA3AG8MAAABACMAGwADCSgFHPYAcwADaAwAAAIACgDqDAAAAgATAG4MAAABAAkAAAA=.Settio:BAABLgAECn8bAAMTAAkJQQUJOAAXAQloDAAABAATAGkMAAAEAA0AawwAAAQAGABqDAAAAwAIAGwMAAAFABYAbQwAAAIACQDqDAAAAgAKAG4MAAACAAYAbwwAAAEABAATAAkJQQUJOAAXAQloDAAAAwATAGkMAAADAA0AawwAAAMAGABqDAAAAwAIAGwMAAAFABYAbQwAAAIACQDqDAAAAgAKAG4MAAACAAYAbwwAAAEABAAFAAMJsQKZdgBOAANoDAAAAQAJAGkMAAABAAYAawwAAAEABAAAAA==.',
Sh='Shaboom:BAAALgADCgIJAgABLgAECggJJgAJAEIfAA==.Shruggon:BAAALgADCgEJAQAAAA==.',
Sl='Slev:BAABLgAECn8lAAQYAAYJpCF2FAAlAgZoDAAAAwBFAGkMAAAGAFsAawwAAAMASgBqDAAACgBaAGwMAAAFAGMA6gwAAAoAWwAYAAYJpCF2FAAlAgZoDAAAAwBFAGkMAAAFAFsAawwAAAMASgBqDAAACABaAGwMAAAEAGMA6gwAAAkAWwAcAAMJIQ2HdQBiAANpDAAAAQAaAGwMAAABABcA6gwAAAEAMgAdAAEJAADarQAAAAFqDAAAAgA5AAAA.Slevatelli:BAAALgAECgIJAgABLgAECggJJQAYAKQhAA==.',
Sm='Smecky:BAAALgAECgEJAQAAAA==.',
So='Songoku:BAAALgAECgYJDwAAAA==.',
St='Sterey:BAAALgADCgcJCQAAAA==.Styles:BAAALgAECgcJDQABLgAECggJJgAJAEIfAA==.',
Sw='Switchout:BAAALgADCgYJBgAAAA==.',
Te='Tehkromlech:BAAALgAECgcJDwAAAA==.Tetankeo:BAABLgAECn8WAAIeAAgJkRzCEQDNAQhoDAAABQBTAGkMAAAEAFAAawwAAAMAQgBqDAAAAgBHAGwMAAACAE4AbQwAAAEAOADqDAAABABXAG4MAAABADoAHgAICZEcwhEAzQEIaAwAAAUAUwBpDAAABABQAGsMAAADAEIAagwAAAIARwBsDAAAAgBOAG0MAAABADgA6gwAAAQAVwBuDAAAAQA6AAAA.',
Tk='Tk:BAAALgADCgcJBQAAAA==.Tkdragon:BAAALgAFFAIJAgAAAA==.',
To='Tobolaeh:BAAALgAECgYJEwABLgAECgkJIgATAFgaAA==.',
Tu='Turbomoose:BAAALgAECgMJAwAAAA==.',
Ty='Tylenolplus:BAAALgAECgMJAwAAAA==.',
Ul='Ulthrax:BAAALgAECgEJAQAAAA==.',
Va='Vaedalth:BAAALgADCgQJBAABLgAECgkJGgAJANsVAA==.Vane:BAAALgAECgMJAwAAAA==.',
Ve='Veil:BAAALgAECgQJCAABLgAECgYJCgAEAAAAAA==.',
Wa='Warfrenzy:BAAALgADCgQJBAAAAA==.',
Xa='Xaletara:BAAALgADCgcJBwAAAA==.',
Xb='Xbite:BAAALgAECgQJBAAAAA==.',
Xe='Xennion:BAAALgADCgIJAgAAAA==.',
Xf='Xfallenhealz:BAAALgAECgIJAgAAAA==.Xfallenlight:BAAALgADCgcJCwAAAA==.',
Yi='Yiirn:BAABLgAECn8VAAIWAAUJ0h0zGQBNAQVoDAAABAA7AGkMAAAFAFIAawwAAAUATwBqDAAAAwBNAOoMAAAEAFMAFgAFCdIdMxkATQEFaAwAAAQAOwBpDAAABQBSAGsMAAAFAE8AagwAAAMATQDqDAAABABTAAAA.',
Yo='Yoko:BAAALgADCgIJAgAAAA==.',
Zu='Zugzugz:BAAALgAECgYJDAABLgAFFAUJGQANAFESAA==.',
['Ðr']='Ðred:BAAALgADCggJCAAAAA==.',
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
