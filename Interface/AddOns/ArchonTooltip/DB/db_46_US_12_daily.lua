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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','Warlock-Demonology','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Paladin-Protection','Druid-Guardian','Monk-Brewmaster','Hunter-Marksmanship','Hunter-Survival','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-05-22',data={Ab='Abcmico:BAAALgAFFAQJBAAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMBAAgJlhyMBgDZAQhoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAQAICZYcjAYA2QEIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAIABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgADAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.',
Be='Beefcake:BAABLgAECn88AAIEAAgJ9yQbDACCAghoDAAACgBhAGkMAAAMAGAAawwAAAoAXQBqDAAABwBjAGwMAAAHAGMAbQwAAAEAUADqDAAACQBiAG4MAAAEAGAABAAICfckGwwAggIIaAwAAAoAYQBpDAAADABgAGsMAAAKAF0AagwAAAcAYwBsDAAABwBjAG0MAAABAFAA6gwAAAkAYgBuDAAABABgAAAA.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAQJDAAFAFIKAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAGAH0YAA==.Borgor:BAAALgAECgYJCQAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgUJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJFAAHAOUMAA==.',
Ca='Canttoucthis:BAAALgADCgUJBQAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAAALgAFFAIJAwAAAA==.',
Ch='Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8IAAIGAAMJiRAyHQDyAANoDAAAAwA3AGkMAAACABsA6gwAAAMAKwAGAAMJiRAyHQDyAANoDAAAAwA3AGkMAAACABsA6gwAAAMAKwAuAAQKfy4AAgYACAkrHwYKAF0CAAYACAkrHwYKAF0CAAAA.',
Cr='Criticaltuna:BAACLgAFFH8MAAIIAAQJDBuiLwBFAQRoDAAABABEAGkMAAACAEsAawwAAAIASQDqDAAABAA7AAgABAkMG6IvAEUBBGgMAAAEAEQAaQwAAAIASwBrDAAAAgBJAOoMAAAEADsALgAECn8oAAQCAAgJaB7pGQB9AQAIAAYJJBjzZACcAQACAAUJYBrpGQB9AQABAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAMJCgABABETAA==.Deathblooms:BAACLgAFFH8QAAIJAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYACQAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACCQAICTAitgEA/wIACQAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8KAAIKAAMJRiZkFQBKAQNoDAAABABiAGkMAAADAGAA6gwAAAMAYgAKAAMJRiZkFQBKAQNoDAAABABiAGkMAAADAGAA6gwAAAMAYgAuAAQKfzgAAgoACQn4IoADAEsDAAoACQn4IoADAEsDAAAA.Destiniedrud:BAAALgAECgUJCgABLgAFFAMJCgAKAEYmAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAMJCgAKAEYmAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgEJAgAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwALAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8IAAIMAAMJzgx9MgDKAANoDAAAAwAdAGkMAAACABUA6gwAAAMALwAMAAMJzgx9MgDKAANoDAAAAwAdAGkMAAACABUA6gwAAAMALwAuAAQKfzQAAwwACQmFG/MKAIkCAAwACQmFG/MKAIkCAA0AAgl6EroWAHsAAAAA.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8dAAIMAAgJ2wS3QAD8AAhoDAAABgASAGkMAAAFABEAawwAAAQADgBqDAAABAAXAGwMAAAEAAkAbQwAAAEACQDqDAAAAwAJAG4MAAACAAcADAAICdsEt0AA/AAIaAwAAAYAEgBpDAAABQARAGsMAAAEAA4AagwAAAQAFwBsDAAABAAJAG0MAAABAAkA6gwAAAMACQBuDAAAAgAHAAAA.',
Ea='Earthen:BAABLgAFFH8FAAIOAAQJsQ/PIgAdAQRoDAAAAgBiAGkMAAABAAQAawwAAAEABADqDAAAAQA0AA4ABAmxD88iAB0BBGgMAAACAGIAaQwAAAEABABrDAAAAQAEAOoMAAABADQAAAA=.',
El='Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephemeral:BAAALgAECgQJBwABLgAECggJHgAPANUgAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJSgAHANQXAA==.',
Fa='Falkion:BAACLgAFFH8MAAIEAAMJ+h5QHwAIAQNoDAAABgBaAGkMAAADAEkA6gwAAAMASQAEAAMJ+h5QHwAIAQNoDAAABgBaAGkMAAADAEkA6gwAAAMASQAuAAQKfzYAAgQACQknIDsGAN4CAAQACQknIDsGAN4CAAAA.',
Fi='Fistingpower:BAAALgAECggJEgABLgAFFAMJCAAMAM4MAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8dAAIQAAkJuRmaCgAgAgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAFAEsAbQwAAAEAJwDqDAAABABHAG4MAAACADMAbwwAAAEAOQAQAAkJuRmaCgAgAgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAFAEsAbQwAAAEAJwDqDAAABABHAG4MAAACADMAbwwAAAEAOQAAAA==.',
Ge='Gemini:BAAALgAECgQJBAAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn8vAAMRAAkJ3BsbBQCVAgloDAAACABRAGkMAAAHAFEAawwAAAcAXwBqDAAABQBOAGwMAAAFAEcAbQwAAAMAJADqDAAABgA8AG4MAAAEAEkAbwwAAAIARgARAAkJ3BsbBQCVAgloDAAABgBRAGkMAAAFAFEAawwAAAUAXwBqDAAABABOAGwMAAAEAEcAbQwAAAMAJADqDAAABQA8AG4MAAAEAEkAbwwAAAIARgAEAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgALAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAISAAkJkSPwAgAcAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAASAAkJkSPwAgAcAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
Iu='Iu:BAABLgAECn8dAAMEAAgJoQyCLQByAQhoDAAABQAnAGkMAAAFACwAawwAAAUALwBqDAAAAwAYAGwMAAADABMA6gwAAAUAJABuDAAAAQAQAG8MAAACABcABAAICcgLgi0AcgEIaAwAAAQAJwBpDAAABAAsAGsMAAAEAC8AagwAAAMAGABsDAAAAwATAOoMAAAEACQAbgwAAAEAEABvDAAAAQAIABEABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn81AAIPAAkJRg5CWwCaAQloDAAACAAdAGkMAAAHADUAawwAAAYALwBqDAAABgAZAGwMAAAHAB8AbQwAAAUAFADqDAAACAA2AG4MAAAFACUAbwwAAAEAEQAPAAkJRg5CWwCaAQloDAAACAAdAGkMAAAHADUAawwAAAYALwBqDAAABgAZAGwMAAAHAB8AbQwAAAUAFADqDAAACAA2AG4MAAAFACUAbwwAAAEAEQAAAA==.Jollymage:BAAALgAECgEJAgAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAIPAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAPAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgADCgcJCgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAECgkJCQAAAA==.',
Ki='Kimari:BAAALgAFFAEJAQAAAA==.Kimìltonze:BAABLgAECn8eAAIQAAkJJgzBFgBiAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAQAAkJJgzBFgBiAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAAAA==.Kite:BAAALgAECgEJAQAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAECggJPAAEAPckAA==.',
Li='Lillith:BAAALgAECgYJEQAAAA==.Lilyanna:BAAALgAECgIJAgAAAA==.Limeaid:BAACLgAFFH8PAAMNAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4AA0ABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgADAABCbgUrkwASQABaAwAAAEANQAuAAQKfzIABA0ACQnxItIAAG8DAA0ACQnxItIAAG8DAAwACAnfGDQuAFcBAAcAAglABOxAAGQAAAEuAAUUBwkQABMAtg0A.Limeylady:BAACLgAFFH8QAAMTAAcJtg3aDgDCAQdoDAAAAgAhAGkMAAACABEAawwAAAIAKABqDAAABAAhAGwMAAACACMAbQwAAAEAMQDqDAAAAwAlABMABgnIDNoOAMIBBmgMAAABACEAaQwAAAEAEQBrDAAAAQAoAGoMAAAEACEAbAwAAAIAIwDqDAAAAQAlABQABQkdFDkJAIsBBWgMAAABADgAaQwAAAEAMgBrDAAAAQAGAG0MAAABADkA6gwAAAIAVwAuAAQKfy4AAxQACQlWIHsIAKQCABQACAlDIHsIAKQCABMABwmYHr8QADYCAAAA.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAQJDAAIAAwbAA==.Malvado:BAACLgAFFH8KAAMBAAMJERPDBAD4AANoDAAABABRAGkMAAADAC4A6gwAAAMAEgABAAMJERPDBAD4AANoDAAAAgBRAGkMAAADAC4A6gwAAAIAEgAIAAIJJARvjQB9AAJoDAAAAgAQAOoMAAABAAQALgAECn80AAQBAAkJWRjJAwA3AgABAAkJWRjJAwA3AgAIAAUJcRHRlQAtAQACAAQJwxA9HACgAAAAAA==.Matheney:BAAALgAFFAEJAQABLgAFFAYJCwAMAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8MAAMVAAMJYCMSCgAIAQNoDAAABgBhAGkMAAADAF4A6gwAAAMATwAWAAMJYCPvWgAVAQNoDAAABQBhAGkMAAACAF4A6gwAAAIATwAVAAMJOh0SCgAIAQNoDAAAAQBNAGkMAAABAFAA6gwAAAEAQQAuAAQKfygAAxYACQlaIowHABwDABYACQlaIowHABwDABUAAgl7GoEeAH8AAAAA.Minji:BAABLgAECn8ZAAIXAAkJMBZXBwAuAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAXAAkJMBZXBwAuAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8XAAQKAAYJ0QlFXAAMAQZoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8A6gwAAAQACQAKAAYJ0QlFXAAMAQZoDAAAAgA2AGkMAAACACcAawwAAAIAGwBqDAAAAQADAGwMAAACAA8A6gwAAAIACQAPAAQJjggw/QCIAARpDAAAAQAVAGsMAAABABsAagwAAAIAEwBsDAAAAgAQABgABQlzA7c1AFsABWgMAAABAAgAaQwAAAEABABrDAAAAQAHAGoMAAABABkA6gwAAAIADgAAAA==.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgALAAAAAA==.',
Pr='Prey:BAABLgAECn8dAAMZAAgJeRcqDQDQAQhoDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABwBKAG4MAAADACgAGQAICXkXKg0A0AEIaAwAAAMATABpDAAAAwA5AGsMAAADAEsAagwAAAMARABsDAAAAwBGAG0MAAABABkA6gwAAAUASgBuDAAAAwAoABcABAk1AtssAF8ABGgMAAABAAIAaQwAAAEABABrDAAAAQAHAOoMAAACAAcAAAA=.',
Pu='Purpp:BAAALgAECgEJAgAAAA==.',
Py='Pyreyn:BAACLgAFFH8GAAMPAAIJ1gjZKgB/AAJoDAAABAAaAGkMAAACABIADwACCdYI2SoAfwACaAwAAAIAGgBpDAAAAgASAAoAAQlrE+Y8AD4AAWgMAAACADEALgAECn8mAAMKAAcJIB0NHAD5AQAKAAcJIB0NHAD5AQAPAAQJ9hL+3wCzAAAAAA==.',
Ra='Radley:BAAALgAECgUJBQABLgAECgkJPwAVADUjAA==.Raelilah:BAABLgAECn8iAAIGAAkJfRjWCQBhAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAGAAkJfRjWCQBhAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIaAAcJfhTZCACqAQdoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIAbQwAAAEAHQDqDAAABgBGABoABwl+FNkIAKoBB2gMAAAHAEEAaQwAAAYANwBrDAAABQArAGoMAAADACUAbAwAAAEAMgBtDAAAAQAdAOoMAAAGAEYALgAECn8YAAIaAAgJBxwOGwAsAgAaAAgJBxwOGwAsAgAAAA==.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAALAAAAAA==.Rheolin:BAAALgAECgEJAQAAAA==.Rheomoon:BAAALgAECgUJBwAAAA==.',
Ri='Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCAAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAAALgAECgYJEwAAAA==.',
Sa='Saelydera:BAAALgAECgEJAQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCAAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgQJCgAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQALAAAAAA==.',
Su='Suicidalone:BAAALgADCgcJEwAAAA==.',
Sy='Sylveon:BAABLgAFFH8GAAIXAAUJxyQ5AQC0AQVoDAAAAQBiAGkMAAACAF0AawwAAAEAWABqDAAAAQBiAOoMAAABAGAAFwAFCcckOQEAtAEFaAwAAAEAYgBpDAAAAgBdAGsMAAABAFgAagwAAAEAYgDqDAAAAQBgAAEuAAUUAwkGABcAxxwA.',
Ta='Tab:BAAALgAECgcJAQAAAA==.',
Ti='Tiamatt:BAAALgAECggJEAAAAA==.',
To='Tornheart:BAABLgAECn8uAAIBAAkJCRXoBAANAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwABAAkJCRXoBAANAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMbAAkJmx+wCADHAQloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAbAAgJPSCwCADHAQhoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUAHAACCd8aaz4AnAACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAACLgAFFH8NAAIdAAQJER5XAwBhAQRoDAAABQBTAGkMAAADAEEAawwAAAEAUgDqDAAABABLAB0ABAkRHlcDAGEBBGgMAAAFAFMAaQwAAAMAQQBrDAAAAQBSAOoMAAAEAEsALgAECn8XAAIdAAgJexsLBgBLAgAdAAgJexsLBgBLAgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAWAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwALAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wy='Wyburn:BAAALgAECgUJCAAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
['Yø']='Yøriçk:BAAALgAECgYJEgAAAA==.',
Za='Zane:BAAALgAECgYJBwAAAA==.Zaraelina:BAAALgAECgYJCQAAAA==.',
['Çl']='Çleadon:BAAALgAECgcJDgAAAA==.',
['ßê']='ßêästÿßöÿ:BAAALgAECgUJBQABLgAECgYJBwALAAAAAA==.',
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
