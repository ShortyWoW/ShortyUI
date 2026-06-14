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

local lookup = {'Mage-Frost','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','DemonHunter-Vengeance','Druid-Guardian','Hunter-Survival','Warlock-Demonology','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Paladin-Protection','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-06-14',data={Ab='Abcmico:BAABLgAECn8XAAIBAAkJ3RxPGgC6AgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgABAAkJ3RxPGgC6AgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arsha:BAAALgAECgQJBAAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMCAAgJlhzDCQDEAQhoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAgAICZYcwwkAxAEIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAMABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
At='Atulock:BAAALgAECgcJCAAAAA==.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgAEAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.Batlad:BAAALgAECgEJAwAAAA==.',
Be='Beefcake:BAACLgAFFH8FAAIFAAMJCR6ZKAAPAQNoDAAAAgBXAGkMAAACAFcA6gwAAAEANwAFAAMJCR6ZKAAPAQNoDAAAAgBXAGkMAAACAFcA6gwAAAEANwAuAAQKf1QAAgUACQnMJesAAH0DAAUACQnMJesAAH0DAAAA.',
Bi='Bigsneak:BAAALgAECgEJAQAAAA==.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAUJDgAGAKIIAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAHAH0YAA==.Borgor:BAAALgAECgYJDgAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgUJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJGAAIAOUMAA==.Bus:BAABLgAFFH8GAAIJAAYJLiPxAAAKAgZoDAAAAQBiAGkMAAABAGAAawwAAAEAYwBqDAAAAQBdAGwMAAABAE4A6gwAAAEATgAJAAYJLiPxAAAKAgZoDAAAAQBiAGkMAAABAGAAawwAAAEAYwBqDAAAAQBdAGwMAAABAE4A6gwAAAEATgABLgAFFAkJHAAKAP8jAA==.',
Ca='Canttoucthis:BAAALgADCggJDAAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAABLgAFFH8GAAILAAMJFxahHADoAANoDAAAAgApAGkMAAABADEA6gwAAAMATwALAAMJFxahHADoAANoDAAAAgApAGkMAAABADEA6gwAAAMATwAAAA==.',
Ch='Cheesecrums:BAAALgADCgQJBAAAAA==.Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8RAAIHAAQJnhXfGQBCAQRoDAAABQA4AGkMAAAEADcAawwAAAIAQQDqDAAABgArAAcABAmeFd8ZAEIBBGgMAAAFADgAaQwAAAQANwBrDAAAAgBBAOoMAAAGACsALgAECn81AAIHAAgJVSBQCgB9AgAHAAgJVSBQCgB9AgAAAA==.',
Cr='Criticaltuna:BAACLgAFFH8aAAMMAAUJpB0pQwBAAQVoDAAABgBEAGkMAAAEAFEAawwAAAQASQBqDAAAAgBBAOoMAAAKAE8ADAAFCQgdKUMAQAEFaAwAAAYARABpDAAAAgBLAGsMAAAEAEkAagwAAAIAQQDqDAAACgBPAAIAAQn7H4MYAFoAAWkMAAACAFEALgAECn8oAAQDAAgJaB7pGQB9AQAMAAYJJBjzZACcAQADAAUJYBrpGQB9AQACAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAQJDgACAHETAA==.Deathblooms:BAACLgAFFH8QAAIJAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYACQAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACCQAICTAitgEA/wIACQAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8XAAINAAUJ3yWdCQAVAgVoDAAABwBiAGkMAAAGAGAAawwAAAMAXQBqDAAAAgBhAOoMAAAFAGIADQAFCd8lnQkAFQIFaAwAAAcAYgBpDAAABgBgAGsMAAADAF0AagwAAAIAYQDqDAAABQBiAC4ABAp/OAACDQAJCfgiAAUAQwMADQAJCfgiAAUAQwMAAAA=.Destiniedrud:BAAALgAECgUJCgABLgAFFAUJFwANAN8lAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAUJFwANAN8lAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgYJCAAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwAOAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8MAAIPAAQJ9BAiMgD2AARoDAAABAAqAGkMAAADACUAawwAAAEALgDqDAAABAAvAA8ABAn0ECIyAPYABGgMAAAEACoAaQwAAAMAJQBrDAAAAQAuAOoMAAAEAC8ALgAECn80AAMPAAkJhRt7DQCGAgAPAAkJhRt7DQCGAgAQAAIJehKKGgB2AAAAAA==.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8jAAIPAAgJNgU3TQD2AAhoDAAABwATAGkMAAAGABEAawwAAAUADgBqDAAABQAqAGwMAAAFAA0AbQwAAAEACQDqDAAABAAJAG4MAAACAAcADwAICTYFN00A9gAIaAwAAAcAEwBpDAAABgARAGsMAAAFAA4AagwAAAUAKgBsDAAABQANAG0MAAABAAkA6gwAAAQACQBuDAAAAgAHAAAA.',
Ea='Earthen:BAABLgAFFH8GAAIRAAQJsQ8MNgAEAQRoDAAAAwBiAGkMAAABAAQAawwAAAEABADqDAAAAQA0ABEABAmxDww2AAQBBGgMAAADAGIAaQwAAAEABABrDAAAAQAEAOoMAAABADQAAS4ABRQFCQoAEgBjGgA=.',
El='Elfisto:BAAALgAECgEJAQAAAA==.Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elokyria:BAAALgAECgYJBwAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephana:BAAALgAECgEJAQAAAA==.Ephemeral:BAAALgAECgQJCAABLgAECgkJNQATAOgjAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJYAAIAJIZAA==.',
Fa='Falkion:BAACLgAFFH8ZAAIFAAUJJh64EwBoAQVoDAAACQBgAGkMAAAGAEkAawwAAAMAQABqDAAAAgBEAOoMAAAFAEoABQAFCSYeuBMAaAEFaAwAAAkAYABpDAAABgBJAGsMAAADAEAAagwAAAIARADqDAAABQBKAC4ABAp/OAACBQAJCa8g3gcA4QIABQAJCa8g3gcA4QIAAAA=.',
Fi='Fistingpower:BAAALgAECggJEgABLgAFFAQJDAAPAPQQAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.Foluspriest:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8gAAIUAAkJihtQCwA2AgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAGAFMAbQwAAAIAMQDqDAAABABHAG4MAAADAEcAbwwAAAEAOQAUAAkJihtQCwA2AgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAGAFMAbQwAAAIAMQDqDAAABABHAG4MAAADAEcAbwwAAAEAOQAAAA==.',
Ge='Gemini:BAAALgAECgUJCgAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn82AAMVAAkJ6B03BQC3AgloDAAACQBTAGkMAAAHAFEAawwAAAgAXwBqDAAABgBPAGwMAAAGAFQAbQwAAAMAJADqDAAACABTAG4MAAAFAE4AbwwAAAIARgAVAAkJ6B03BQC3AgloDAAABwBTAGkMAAAFAFEAawwAAAYAXwBqDAAABQBPAGwMAAAFAFQAbQwAAAMAJADqDAAABwBTAG4MAAAFAE4AbwwAAAIARgAFAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgAOAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIWAAkJkSOjBAAMAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAWAAkJkSOjBAAMAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
It='Itchytasty:BAAALgAECgIJAgAAAA==.',
Iu='Iu:BAABLgAECn8dAAMFAAgJoQyOOABlAQhoDAAABQAnAGkMAAAFACwAawwAAAUALwBqDAAAAwAYAGwMAAADABMA6gwAAAUAJABuDAAAAQAQAG8MAAACABcABQAICcgLjjgAZQEIaAwAAAQAJwBpDAAABAAsAGsMAAAEAC8AagwAAAMAGABsDAAAAwATAOoMAAAEACQAbgwAAAEAEABvDAAAAQAIABUABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn88AAITAAkJ0w9TbwCOAQloDAAACQAqAGkMAAAIADUAawwAAAcALwBqDAAABwAgAGwMAAAIACwAbQwAAAYAGwDqDAAACQA2AG4MAAAFACUAbwwAAAEAEQATAAkJ0w9TbwCOAQloDAAACQAqAGkMAAAIADUAawwAAAcALwBqDAAABwAgAGwMAAAIACwAbQwAAAYAGwDqDAAACQA2AG4MAAAFACUAbwwAAAEAEQAAAA==.Jollymage:BAAALgAECgcJCQAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAITAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAATAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgAECgIJAgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAFFAIJAgAAAA==.',
Ki='Kimari:BAACLgAFFH8IAAIWAAMJPhguHQDkAANoDAAABABGAGkMAAACADAA6gwAAAIAQwAWAAMJPhguHQDkAANoDAAABABGAGkMAAACADAA6gwAAAIAQwAuAAQKfxoAAhYACQmHGxkNAHICABYACQmHGxkNAHICAAAA.Kimìltonze:BAABLgAECn8eAAIUAAkJJgx8HQBHAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAUAAkJJgx8HQBHAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAAAA==.Kite:BAAALgAECgIJAgAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAFFAMJBQAFAAkeAA==.',
Li='Lillith:BAAALgAECgYJEgAAAA==.Lilyanna:BAAALgAECgIJAwAAAA==.Limeaid:BAACLgAFFH8PAAMQAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4ABAABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgADwABCbgUe2IAQAABaAwAAAEANQAuAAQKfzUABBAACQnxItIAAG8DABAACQnxItIAAG8DAA8ACAnfGMA2AFMBAAgAAglABOxAAGQAAAEuAAUUCAkaABcApxIA.Limelight:BAAALgAECgkJEQABLgAFFAgJGgAXAKcSAA==.Limeylady:BAACLgAFFH8aAAMXAAgJpxJ9DwAcAghoDAAABQBPAGkMAAAFABkAawwAAAQAKABqDAAABAAhAGwMAAACACMAbQwAAAEAMQDqDAAABABBAG4MAAABADUAFwAHCZASfQ8AHAIHaAwAAAQATwBpDAAABAAZAGsMAAABACgAagwAAAQAIQBsDAAAAgAjAOoMAAACAEEAbgwAAAEANQAYAAUJNBR0EABjAQVoDAAAAQA4AGkMAAABADIAawwAAAMABwBtDAAAAQA5AOoMAAACAFcALgAECn84AAMYAAkJ1SIIBAAdAwAYAAkJ1SIIBAAdAwAXAAcJmB6/EAA2AgAAAA==.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAUJGgAMAKQdAA==.Malvado:BAACLgAFFH8OAAMCAAQJcRMqBQAzAQRoDAAABQBRAGkMAAAEAC4AawwAAAEAFwDqDAAABAAvAAIABAlxEyoFADMBBGgMAAADAFEAaQwAAAQALgBrDAAAAQAXAOoMAAADAC8ADAACCSQEtbAAcgACaAwAAAIAEADqDAAAAQAEAC4ABAp/NAAEAgAJCVkYSAYAGQIAAgAJCVkYSAYAGQIADAAFCXER0ZUALQEAAwAECcMQ1iEAnQAAAAA=.Matheney:BAEALgAFFAEJAQABLgAFFAYJCwAPAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8XAAMZAAUJdh6fRgBhAQVoDAAACABhAGkMAAAFAF4AawwAAAIAJABqDAAAAgAqAOoMAAAGAFIAGQAFCXYen0YAYQEFaAwAAAcAYQBpDAAABABeAGsMAAACACQAagwAAAEAKgDqDAAABABSABoABAllHogSAPYABGgMAAABAE0AaQwAAAEAUABqDAAAAQAYAOoMAAACAEoALgAECn8rAAMZAAkJvCRFBwA7AwAZAAkJvCRFBwA7AwAaAAMJeBqwHwDNAAAAAA==.Minji:BAABLgAECn8ZAAIbAAkJMBbVCQAiAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAbAAkJMBbVCQAiAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8YAAQNAAcJsAhFXAAMAQdoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8AbQwAAAEABADqDAAABAAJAA0ABwmwCEVcAAwBB2gMAAACADYAaQwAAAIAJwBrDAAAAgAbAGoMAAABAAMAbAwAAAIADwBtDAAAAQAEAOoMAAACAAkAEwAECY4I/ykBhAAEaQwAAAEAFQBrDAAAAQAbAGoMAAACABMAbAwAAAIAEAAcAAUJcwNxQABbAAVoDAAAAQAIAGkMAAABAAQAawwAAAEABwBqDAAAAQAZAOoMAAACAA4AAAA=.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
Og='Ogma:BAAALgADCgUJBQAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Os='Osiris:BAAALgADCgcJBwAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgAOAAAAAA==.',
Pr='Prey:BAABLgAECn8fAAMKAAkJvxdxDAAXAgloDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAACABMAG4MAAADACgAbwwAAAEAPgAKAAkJvxdxDAAXAgloDAAAAwBMAGkMAAADADkAawwAAAMASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABgBMAG4MAAADACgAbwwAAAEAPgAbAAQJNQLbLABfAARoDAAAAQACAGkMAAABAAQAawwAAAEABwDqDAAAAgAHAAAA.',
Pu='Purpp:BAAALgAFFAMJAQAAAA==.',
Py='Pyreyn:BAACLgAFFH8LAAMNAAMJdxhEKQDYAANoDAAABgA1AGkMAAADADEA6gwAAAIAVQANAAMJdxhEKQDYAANoDAAABAA1AGkMAAABADEA6gwAAAIAVQATAAIJ1gjZKgB/AAJoDAAAAgAaAGkMAAACABIALgAECn8zAAMNAAgJEh7fHAAbAgANAAcJCR7fHAAbAgATAAgJpxcNSgDnAQAAAA==.',
Ra='Radley:BAAALgAECgYJDwABLgAFFAkJDQAaAKEVAA==.Raelilah:BAABLgAECn8iAAIHAAkJfRi4DQBKAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAHAAkJfRi4DQBKAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAAAA==.Raenia:BAAALgAECgEJAQAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIdAAcJfhR5EQCTAQdoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIAbQwAAAEAHQDqDAAABgBGAB0ABwl+FHkRAJMBB2gMAAAHAEEAaQwAAAYANwBrDAAABQArAGoMAAADACUAbAwAAAEAMgBtDAAAAQAdAOoMAAAGAEYALgAECn8YAAIdAAgJBxwOGwAsAgAdAAgJBxwOGwAsAgAAAA==.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAAOAAAAAA==.Rheolette:BAAALgAECgEJAQAAAA==.Rheolin:BAAALgAECgYJEgAAAA==.Rheolynx:BAABLgAECn8YAAINAAYJDiN1FQBgAgZoDAAABQBhAGkMAAAFAF8AawwAAAUAVwBqDAAAAwBXAGwMAAADAE8A6gwAAAMAWgANAAYJDiN1FQBgAgZoDAAABQBhAGkMAAAFAF8AawwAAAUAVwBqDAAAAwBXAGwMAAADAE8A6gwAAAMAWgAAAA==.Rheomei:BAAALgAECgUJCAAAAA==.Rheomoon:BAABLgAECn8ZAAIRAAcJ3xvQJAAuAgdoDAAABABJAGkMAAAEAFIAawwAAAQAUQBqDAAABABUAGwMAAADADQA6gwAAAUAYQBvDAAAAQAbABEABwnfG9AkAC4CB2gMAAAEAEkAaQwAAAQAUgBrDAAABABRAGoMAAAEAFQAbAwAAAMANADqDAAABQBhAG8MAAABABsAAAA=.',
Ri='Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCQAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAABLgAECn8UAAIWAAcJvxRJLQBVAQdoDAAABQAvAGkMAAAFAEMAawwAAAMAOgBqDAAAAgAmAGwMAAACACkAbQwAAAEALQDqDAAAAgA6ABYABwm/FEktAFUBB2gMAAAFAC8AaQwAAAUAQwBrDAAAAwA6AGoMAAACACYAbAwAAAIAKQBtDAAAAQAtAOoMAAACADoAAAA=.',
Sa='Saelydera:BAAALgAECgQJBQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCQAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgYJEAAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQAOAAAAAA==.',
Su='Suicidalone:BAAALgAECgEJAQAAAA==.',
Sy='Sylveon:BAABLgAFFH8OAAIbAAYJbyYBAQAjAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAQAYwAbAAYJbyYBAQAjAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAQAYwABLgAFFAMJBgAbAMccAA==.Syndara:BAAALgAECgUJCQAAAA==.',
Ta='Tab:BAAALgAECgkJAQAAAA==.',
Ti='Tiamatt:BAAALgAECgkJEQAAAA==.',
To='Tornheart:BAABLgAECn8uAAICAAkJCRV6BQASAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwACAAkJCRV6BQASAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMeAAkJmx/jCgC7AQloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAeAAgJPSDjCgC7AQhoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUACwACCd8ai0gAlgACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAACLgAFFH8PAAIfAAQJlh65BgBLAQRoDAAABgBZAGkMAAAEAEEAawwAAAEAUgDqDAAABABLAB8ABAmWHrkGAEsBBGgMAAAGAFkAaQwAAAQAQQBrDAAAAQBSAOoMAAAEAEsALgAECn8XAAIfAAgJexsoCABBAgAfAAgJexsoCABBAgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAZAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
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
