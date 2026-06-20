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

local lookup = {'Mage-Frost','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','DemonHunter-Vengeance','Druid-Guardian','Hunter-Survival','Warlock-Demonology','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-06-19',data={Ab='Abcmico:BAABLgAECn8XAAIBAAkJ3RzPGgC6AgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgABAAkJ3RzPGgC6AgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arsha:BAAALgAECgQJBAAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMCAAgJlhzqCQDDAQhoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAgAICZYc6gkAwwEIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAMABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
At='Atulock:BAAALgAECgcJCAAAAA==.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgAEAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.Batlad:BAAALgAECgEJAwAAAA==.',
Be='Beefcake:BAACLgAFFH8HAAIFAAMJHR9IJgAcAQNoDAAAAwBfAGkMAAADAFcA6gwAAAEANwAFAAMJHR9IJgAcAQNoDAAAAwBfAGkMAAADAFcA6gwAAAEANwAuAAQKf1YAAgUACQnPJfkAAHoDAAUACQnPJfkAAHoDAAAA.',
Bi='Bigsneak:BAAALgAECgEJAQAAAA==.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAUJDgAGAKIIAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAHAH0YAA==.Borgor:BAAALgAECgYJDgAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bunnie:BAAALgAECgUJDAABLgAECgYJGAAIAOUMAA==.Bus:BAABLgAFFH8GAAIJAAYJLiMJAQAKAgZoDAAAAQBiAGkMAAABAGAAawwAAAEAYwBqDAAAAQBdAGwMAAABAE4A6gwAAAEATgAJAAYJLiMJAQAKAgZoDAAAAQBiAGkMAAABAGAAawwAAAEAYwBqDAAAAQBdAGwMAAABAE4A6gwAAAEATgABLgAFFAkJHAAKAP8jAA==.',
Ca='Canttoucthis:BAAALgADCggJDAAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAABLgAFFH8GAAILAAMJFxYxHQDnAANoDAAAAgApAGkMAAABADEA6gwAAAMATwALAAMJFxYxHQDnAANoDAAAAgApAGkMAAABADEA6gwAAAMATwAAAA==.',
Ch='Cheesecrums:BAAALgADCgYJBgAAAA==.Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8TAAIHAAQJDhaTGgBCAQRoDAAABgA8AGkMAAAFADcAawwAAAIAQQDqDAAABgArAAcABAkOFpMaAEIBBGgMAAAGADwAaQwAAAUANwBrDAAAAgBBAOoMAAAGACsALgAECn81AAIHAAgJVSB2CgB8AgAHAAgJVSB2CgB8AgAAAA==.',
Cr='Criticaltuna:BAACLgAFFH8aAAMMAAUJpB3uRABAAQVoDAAABgBEAGkMAAAEAFEAawwAAAQASQBqDAAAAgBBAOoMAAAKAE8ADAAFCQgd7kQAQAEFaAwAAAYARABpDAAAAgBLAGsMAAAEAEkAagwAAAIAQQDqDAAACgBPAAIAAQn7H0oZAFoAAWkMAAACAFEALgAECn8oAAQDAAgJaB7pGQB9AQAMAAYJJBjzZACcAQADAAUJYBrpGQB9AQACAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAQJEAACAHETAA==.Deathblooms:BAACLgAFFH8QAAIJAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYACQAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACCQAICTAitgEA/wIACQAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8aAAINAAUJ3yVQCgATAgVoDAAACABiAGkMAAAHAGAAawwAAAMAXQBqDAAAAgBhAOoMAAAGAGIADQAFCd8lUAoAEwIFaAwAAAgAYgBpDAAABwBgAGsMAAADAF0AagwAAAIAYQDqDAAABgBiAC4ABAp/OAACDQAJCfgiGQUAQwMADQAJCfgiGQUAQwMAAAA=.Destiniedrud:BAAALgAECgUJCgABLgAFFAUJGgANAN8lAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAUJGgANAN8lAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgYJCQAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwAOAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8MAAIPAAQJ9BCZMwD0AARoDAAABAAqAGkMAAADACUAawwAAAEALgDqDAAABAAvAA8ABAn0EJkzAPQABGgMAAAEACoAaQwAAAMAJQBrDAAAAQAuAOoMAAAEAC8ALgAECn80AAMPAAkJhRudDQCFAgAPAAkJhRudDQCFAgAQAAIJehLXGgB2AAAAAA==.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8nAAIPAAgJGQZmAQC5AAhoDAAACAAeAGkMAAAHABEAawwAAAYADgBqDAAABQAqAGwMAAAFAA0AbQwAAAEACQDqDAAABQAPAG4MAAACAAcADwAICRkGZgEAuQAIaAwAAAgAHgBpDAAABwARAGsMAAAGAA4AagwAAAUAKgBsDAAABQANAG0MAAABAAkA6gwAAAUADwBuDAAAAgAHAAAA.',
Ea='Earthen:BAABLgAFFH8GAAIRAAQJsQ9zNwAEAQRoDAAAAwBiAGkMAAABAAQAawwAAAEABADqDAAAAQA0ABEABAmxD3M3AAQBBGgMAAADAGIAaQwAAAEABABrDAAAAQAEAOoMAAABADQAAS4ABRQFCQoAEgBjGgA=.',
El='Elfisto:BAAALgAECgEJAQAAAA==.Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elokyria:BAAALgAECgYJBwAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephana:BAAALgAECgEJAQAAAA==.Ephemeral:BAAALgAECgQJCAABLgAFFAIJBQATAMgfAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJZgAIAC4bAA==.',
Fa='Falkion:BAACLgAFFH8cAAIFAAUJQx6oAQAUAQVoDAAACgBhAGkMAAAHAEkAawwAAAMAQABqDAAAAgBEAOoMAAAGAEoABQAFCUMeqAEAFAEFaAwAAAoAYQBpDAAABwBJAGsMAAADAEAAagwAAAIARADqDAAABgBKAC4ABAp/OAACBQAJCa8g/wcA3wIABQAJCa8g/wcA3wIAAAA=.',
Fi='Fistingpower:BAAALgAECggJEwABLgAFFAQJDAAPAPQQAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.Foluspriest:BAAALgADCgUJBQABLgAECgEJAQAOAAAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8gAAIUAAkJihuHCwA1AgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAGAFMAbQwAAAIAMQDqDAAABABHAG4MAAADAEcAbwwAAAEAOQAUAAkJihuHCwA1AgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAGAFMAbQwAAAIAMQDqDAAABABHAG4MAAADAEcAbwwAAAEAOQAAAA==.',
Ge='Gemini:BAAALgAECgUJCgAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn82AAMVAAkJ6B1MBQC3AgloDAAACQBTAGkMAAAHAFEAawwAAAgAXwBqDAAABgBPAGwMAAAGAFQAbQwAAAMAJADqDAAACABTAG4MAAAFAE4AbwwAAAIARgAVAAkJ6B1MBQC3AgloDAAABwBTAGkMAAAFAFEAawwAAAYAXwBqDAAABQBPAGwMAAAFAFQAbQwAAAMAJADqDAAABwBTAG4MAAAFAE4AbwwAAAIARgAFAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgAOAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIWAAkJkSO+BAALAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAWAAkJkSO+BAALAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
It='Itchytasty:BAAALgAECgIJAgAAAA==.',
Iu='Iu:BAABLgAECn8dAAMFAAgJoQwAOgBeAQhoDAAABQAnAGkMAAAFACwAawwAAAUALwBqDAAAAwAYAGwMAAADABMA6gwAAAUAJABuDAAAAQAQAG8MAAACABcABQAICcgLADoAXgEIaAwAAAQAJwBpDAAABAAsAGsMAAAEAC8AagwAAAMAGABsDAAAAwATAOoMAAAEACQAbgwAAAEAEABvDAAAAQAIABUABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn88AAITAAkJ0w8zcACOAQloDAAACQAqAGkMAAAIADUAawwAAAcALwBqDAAABwAgAGwMAAAIACwAbQwAAAYAGwDqDAAACQA2AG4MAAAFACUAbwwAAAEAEQATAAkJ0w8zcACOAQloDAAACQAqAGkMAAAIADUAawwAAAcALwBqDAAABwAgAGwMAAAIACwAbQwAAAYAGwDqDAAACQA2AG4MAAAFACUAbwwAAAEAEQAAAA==.Jollymage:BAAALgAECgcJCQAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAITAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAATAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgAECgIJAgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAFFAIJAgAAAA==.',
Ki='Kimari:BAACLgAFFH8LAAIWAAMJPhjKAQC4AANoDAAABQBGAGkMAAADADAA6gwAAAMAQwAWAAMJPhjKAQC4AANoDAAABQBGAGkMAAADADAA6gwAAAMAQwAuAAQKfxoAAhYACQmHG0cNAHECABYACQmHG0cNAHECAAAA.Kimìltonze:BAABLgAECn8eAAIUAAkJJgzCHQBHAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAUAAkJJgzCHQBHAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAAAA==.Kite:BAAALgAECgIJAgAAAA==.',
La='Lambpie:BAAALgAECgUJDQABLgAFFAMJBwAFAB0fAA==.Lancealot:BAAALgAECgUJBQAAAA==.',
Li='Lillith:BAAALgAECgYJEgAAAA==.Lilyanna:BAAALgAECgIJAwAAAA==.Limeaid:BAACLgAFFH8PAAMQAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4ABAABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgADwABCbgUp2QAQAABaAwAAAEANQAuAAQKfzUABBAACQnxItIAAG8DABAACQnxItIAAG8DAA8ACAnfGLA3AFABAAgAAglABOxAAGQAAAEuAAUUCAkeABcApxIA.Limelight:BAAALgAECgkJEQABLgAFFAgJHgAXAKcSAA==.Limeylady:BAACLgAFFH8eAAMXAAgJpxJNEAAYAghoDAAABgBPAGkMAAAGABkAawwAAAUAKABqDAAABQAhAGwMAAACACMAbQwAAAEAMQDqDAAABABBAG4MAAABADUAFwAHCZASTRAAGAIHaAwAAAQATwBpDAAABAAZAGsMAAABACgAagwAAAUAIQBsDAAAAgAjAOoMAAACAEEAbgwAAAEANQAYAAUJphbzEABiAQVoDAAAAgA4AGkMAAACADIAawwAAAQAJgBtDAAAAQA5AOoMAAACAFcALgAECn84AAMYAAkJ1SIeBAAaAwAYAAkJ1SIeBAAaAwAXAAcJmB6/EAA2AgAAAA==.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAUJGgAMAKQdAA==.Malvado:BAACLgAFFH8QAAMCAAQJcRNcBQAxAQRoDAAABgBRAGkMAAAFAC4AawwAAAEAFwDqDAAABAAvAAIABAlxE1wFADEBBGgMAAAEAFEAaQwAAAUALgBrDAAAAQAXAOoMAAADAC8ADAACCSQEcbMAcgACaAwAAAIAEADqDAAAAQAEAC4ABAp/NAAEAgAJCVkYXgYAGAIAAgAJCVkYXgYAGAIADAAFCXER0ZUALQEAAwAECcMQWSIAnQAAAAA=.Matheney:BAEALgAFFAEJAQABLgAFFAYJCwAPAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8aAAMZAAUJdh5bBAAOAQVoDAAACQBhAGkMAAAGAF4AawwAAAIAJABqDAAAAgAqAOoMAAAHAFIAGQAFCXYeWwQADgEFaAwAAAgAYQBpDAAABQBeAGsMAAACACQAagwAAAEAKgDqDAAABQBSABoABAllHkETAPUABGgMAAABAE0AaQwAAAEAUABqDAAAAQAYAOoMAAACAEoALgAECn8rAAMZAAkJvCR/BwA6AwAZAAkJvCR/BwA6AwAaAAMJeBokIADMAAAAAA==.Minji:BAABLgAECn8ZAAIbAAkJMBbrCQAjAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAbAAkJMBbrCQAjAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8YAAQNAAcJsAhFXAAMAQdoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8AbQwAAAEABADqDAAABAAJAA0ABwmwCEVcAAwBB2gMAAACADYAaQwAAAIAJwBrDAAAAgAbAGoMAAABAAMAbAwAAAIADwBtDAAAAQAEAOoMAAACAAkAEwAECY4I3C4BgQAEaQwAAAEAFQBrDAAAAQAbAGoMAAACABMAbAwAAAIAEAAcAAUJcwMLQQBbAAVoDAAAAQAIAGkMAAABAAQAawwAAAEABwBqDAAAAQAZAOoMAAACAA4AAAA=.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
Og='Ogma:BAAALgADCgUJBQAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Os='Osiris:BAAALgADCgcJBwAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgAOAAAAAA==.',
Pr='Prey:BAABLgAECn8fAAMKAAkJvxecDAAXAgloDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAACABMAG4MAAADACgAbwwAAAEAPgAKAAkJvxecDAAXAgloDAAAAwBMAGkMAAADADkAawwAAAMASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABgBMAG4MAAADACgAbwwAAAEAPgAbAAQJNQLbLABfAARoDAAAAQACAGkMAAABAAQAawwAAAEABwDqDAAAAgAHAAAA.',
Pu='Purpp:BAAALgAFFAMJAQAAAA==.',
Py='Pyreyn:BAACLgAFFH8NAAMNAAMJdxgMKgDXAANoDAAABwA1AGkMAAAEADEA6gwAAAIAVQANAAMJdxgMKgDXAANoDAAABQA1AGkMAAACADEA6gwAAAIAVQATAAIJ1gjZKgB/AAJoDAAAAgAaAGkMAAACABIALgAECn8zAAMNAAgJEh4sHQAaAgANAAcJCR4sHQAaAgATAAgJpxe9SgDmAQAAAA==.',
Ra='Radley:BAAALgAECgYJDwABLgAFFAkJDQAaAKEVAA==.Raelilah:BAABLgAECn8iAAIHAAkJfRj9DQBIAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAHAAkJfRj9DQBIAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAAAA==.Raenia:BAAALgAECgEJAQAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIdAAcJfhRIEgCSAQdoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIAbQwAAAEAHQDqDAAABgBGAB0ABwl+FEgSAJIBB2gMAAAHAEEAaQwAAAYANwBrDAAABQArAGoMAAADACUAbAwAAAEAMgBtDAAAAQAdAOoMAAAGAEYALgAECn8YAAIdAAgJBxwOGwAsAgAdAAgJBxwOGwAsAgAAAA==.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAAOAAAAAA==.Rheolette:BAAALgAECgEJAQAAAA==.Rheolin:BAABLgAECn8UAAIeAAYJdR4uJQD6AQZoDAAABABIAGkMAAAEAFQAawwAAAQAUgBqDAAAAgBLAGwMAAADAEwA6gwAAAMASwAeAAYJdR4uJQD6AQZoDAAABABIAGkMAAAEAFQAawwAAAQAUgBqDAAAAgBLAGwMAAADAEwA6gwAAAMASwAAAA==.Rheolynx:BAABLgAECn8YAAINAAYJDiO2FQBfAgZoDAAABQBhAGkMAAAFAF8AawwAAAUAVwBqDAAAAwBXAGwMAAADAE8A6gwAAAMAWgANAAYJDiO2FQBfAgZoDAAABQBhAGkMAAAFAF8AawwAAAUAVwBqDAAAAwBXAGwMAAADAE8A6gwAAAMAWgAAAA==.Rheomei:BAAALgAECgUJCAAAAA==.Rheomoon:BAABLgAECn8ZAAIRAAcJ3xtUJQAuAgdoDAAABABJAGkMAAAEAFIAawwAAAQAUQBqDAAABABUAGwMAAADADQA6gwAAAUAYQBvDAAAAQAbABEABwnfG1QlAC4CB2gMAAAEAEkAaQwAAAQAUgBrDAAABABRAGoMAAAEAFQAbAwAAAMANADqDAAABQBhAG8MAAABABsAAAA=.',
Ri='Richelly:BAAALgAECgUJBgAAAA==.Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCQAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAABLgAECn8UAAIWAAcJvxS9LQBVAQdoDAAABQAvAGkMAAAFAEMAawwAAAMAOgBqDAAAAgAmAGwMAAACACkAbQwAAAEALQDqDAAAAgA6ABYABwm/FL0tAFUBB2gMAAAFAC8AaQwAAAUAQwBrDAAAAwA6AGoMAAACACYAbAwAAAIAKQBtDAAAAQAtAOoMAAACADoAAAA=.',
Sa='Saelydera:BAAALgAECgQJBQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCQAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgYJEAAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQAOAAAAAA==.',
Su='Suicidalone:BAAALgAECgEJAQAAAA==.',
Sy='Sylveon:BAABLgAFFH8OAAIbAAYJbyYbAQAlAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAQAYwAbAAYJbyYbAQAlAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAQAYwABLgAFFAMJBgAbAMccAA==.Syndara:BAAALgAECgUJCQAAAA==.',
Ta='Tab:BAAALgAECgkJAQAAAA==.',
Ti='Tiamatt:BAAALgAECgkJEQAAAA==.',
To='Tornheart:BAABLgAECn8uAAICAAkJCRV6BQASAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwACAAkJCRV6BQASAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMfAAkJmx8OCwC6AQloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAfAAgJPSAOCwC6AQhoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUACwACCd8a30gAlgACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAACLgAFFH8PAAIgAAQJlh4LBwBIAQRoDAAABgBZAGkMAAAEAEEAawwAAAEAUgDqDAAABABLACAABAmWHgsHAEgBBGgMAAAGAFkAaQwAAAQAQQBrDAAAAQBSAOoMAAAEAEsALgAECn8XAAIgAAgJextTCABBAgAgAAgJextTCABBAgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCQAZAGQiAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wy='Wyburn:BAAALgAECgUJCgAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
['Yø']='Yøriçk:BAAALgAECgYJEwAAAA==.',
Za='Zane:BAAALgAECgYJBwAAAA==.Zaraelina:BAAALgAECgYJCQAAAA==.',
['Çl']='Çleadon:BAAALgAECgcJDgAAAA==.',
['ßê']='ßêästÿßöÿ:BAAALgAECgcJDAAAAA==.',
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
