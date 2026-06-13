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

local lookup = {'Mage-Frost','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','Hunter-Survival','Warlock-Demonology','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Paladin-Protection','Druid-Guardian','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-06-12',data={Ab='Abcmico:BAABLgAECn8XAAIBAAkJ3RwQGgC8AgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgABAAkJ3RwQGgC8AgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arsha:BAAALgAECgMJAwAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMCAAgJlhyXCQDEAQhoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAgAICZYclwkAxAEIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAMABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
At='Atulock:BAAALgAECgcJBwAAAA==.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgAEAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.Batlad:BAAALgAECgEJAgAAAA==.',
Be='Beefcake:BAACLgAFFH8FAAIFAAMJCR64JwAQAQNoDAAAAgBXAGkMAAACAFcA6gwAAAEANwAFAAMJCR64JwAQAQNoDAAAAgBXAGkMAAACAFcA6gwAAAEANwAuAAQKf1QAAgUACQnMJeAAAH0DAAUACQnMJeAAAH0DAAAA.',
Bi='Bigsneak:BAAALgAECgEJAQAAAA==.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAUJDgAGAKIIAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAHAH0YAA==.Borgor:BAAALgAECgYJCQAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgUJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJGAAIAOUMAA==.',
Ca='Canttoucthis:BAAALgADCggJDAAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAABLgAFFH8GAAIJAAMJFxYcHADoAANoDAAAAgApAGkMAAABADEA6gwAAAMATwAJAAMJFxYcHADoAANoDAAAAgApAGkMAAABADEA6gwAAAMATwAAAA==.',
Ch='Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8RAAIHAAQJnhVUGQBCAQRoDAAABQA4AGkMAAAEADcAawwAAAIAQQDqDAAABgArAAcABAmeFVQZAEIBBGgMAAAFADgAaQwAAAQANwBrDAAAAgBBAOoMAAAGACsALgAECn81AAIHAAgJVSAhCgB9AgAHAAgJVSAhCgB9AgAAAA==.',
Cr='Criticaltuna:BAACLgAFFH8aAAMKAAUJpB22QQBCAQVoDAAABgBEAGkMAAAEAFEAawwAAAQASQBqDAAAAgBBAOoMAAAKAE8ACgAFCQgdtkEAQgEFaAwAAAYARABpDAAAAgBLAGsMAAAEAEkAagwAAAIAQQDqDAAACgBPAAIAAQn7H/cXAFsAAWkMAAACAFEALgAECn8oAAQDAAgJaB7pGQB9AQAKAAYJJBjzZACcAQADAAUJYBrpGQB9AQACAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAQJDgACAHETAA==.Deathblooms:BAACLgAFFH8QAAILAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYACwAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACCwAICTAitgEA/wIACwAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8XAAIMAAUJ3yVTCQAXAgVoDAAABwBiAGkMAAAGAGAAawwAAAMAXQBqDAAAAgBhAOoMAAAFAGIADAAFCd8lUwkAFwIFaAwAAAcAYgBpDAAABgBgAGsMAAADAF0AagwAAAIAYQDqDAAABQBiAC4ABAp/OAACDAAJCfgi5QQARAMADAAJCfgi5QQARAMAAAA=.Destiniedrud:BAAALgAECgUJCgABLgAFFAUJFwAMAN8lAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAUJFwAMAN8lAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgYJCAAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwANAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8MAAIOAAQJ9BD+MAD6AARoDAAABAAqAGkMAAADACUAawwAAAEALgDqDAAABAAvAA4ABAn0EP4wAPoABGgMAAAEACoAaQwAAAMAJQBrDAAAAQAuAOoMAAAEAC8ALgAECn80AAMOAAkJhRtoDQCFAgAOAAkJhRtoDQCFAgAPAAIJehJQGgB2AAAAAA==.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8jAAIOAAgJNgVxTAD2AAhoDAAABwATAGkMAAAGABEAawwAAAUADgBqDAAABQAqAGwMAAAFAA0AbQwAAAEACQDqDAAABAAJAG4MAAACAAcADgAICTYFcUwA9gAIaAwAAAcAEwBpDAAABgARAGsMAAAFAA4AagwAAAUAKgBsDAAABQANAG0MAAABAAkA6gwAAAQACQBuDAAAAgAHAAAA.',
Ea='Earthen:BAABLgAFFH8GAAIQAAQJsQ/mNAAFAQRoDAAAAwBiAGkMAAABAAQAawwAAAEABADqDAAAAQA0ABAABAmxD+Y0AAUBBGgMAAADAGIAaQwAAAEABABrDAAAAQAEAOoMAAABADQAAS4ABRQFCQoAEQBjGgA=.',
El='Elfisto:BAAALgAECgEJAQAAAA==.Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephana:BAAALgAECgEJAQAAAA==.Ephemeral:BAAALgAECgQJCAABLgAECgkJNQASAOgjAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJYAAIAJIZAA==.',
Fa='Falkion:BAACLgAFFH8ZAAIFAAUJJh4uEwBpAQVoDAAACQBgAGkMAAAGAEkAawwAAAMAQABqDAAAAgBEAOoMAAAFAEoABQAFCSYeLhMAaQEFaAwAAAkAYABpDAAABgBJAGsMAAADAEAAagwAAAIARADqDAAABQBKAC4ABAp/OAACBQAJCa8gtgcA4QIABQAJCa8gtgcA4QIAAAA=.',
Fi='Fistingpower:BAAALgAECggJEgABLgAFFAQJDAAOAPQQAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.Foluspriest:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8gAAITAAkJihskCwA3AgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAGAFMAbQwAAAIAMQDqDAAABABHAG4MAAADAEcAbwwAAAEAOQATAAkJihskCwA3AgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAGAFMAbQwAAAIAMQDqDAAABABHAG4MAAADAEcAbwwAAAEAOQAAAA==.',
Ge='Gemini:BAAALgAECgUJCgAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn82AAMUAAkJ6B0kBQC4AgloDAAACQBTAGkMAAAHAFEAawwAAAgAXwBqDAAABgBPAGwMAAAGAFQAbQwAAAMAJADqDAAACABTAG4MAAAFAE4AbwwAAAIARgAUAAkJ6B0kBQC4AgloDAAABwBTAGkMAAAFAFEAawwAAAYAXwBqDAAABQBPAGwMAAAFAFQAbQwAAAMAJADqDAAABwBTAG4MAAAFAE4AbwwAAAIARgAFAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgANAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIVAAkJkSOQBAANAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAVAAkJkSOQBAANAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
It='Itchytasty:BAAALgAECgEJAQAAAA==.',
Iu='Iu:BAABLgAECn8dAAMFAAgJoQzyNwBlAQhoDAAABQAnAGkMAAAFACwAawwAAAUALwBqDAAAAwAYAGwMAAADABMA6gwAAAUAJABuDAAAAQAQAG8MAAACABcABQAICcgL8jcAZQEIaAwAAAQAJwBpDAAABAAsAGsMAAAEAC8AagwAAAMAGABsDAAAAwATAOoMAAAEACQAbgwAAAEAEABvDAAAAQAIABQABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn88AAISAAkJ0w8sbgCOAQloDAAACQAqAGkMAAAIADUAawwAAAcALwBqDAAABwAgAGwMAAAIACwAbQwAAAYAGwDqDAAACQA2AG4MAAAFACUAbwwAAAEAEQASAAkJ0w8sbgCOAQloDAAACQAqAGkMAAAIADUAawwAAAcALwBqDAAABwAgAGwMAAAIACwAbQwAAAYAGwDqDAAACQA2AG4MAAAFACUAbwwAAAEAEQAAAA==.Jollymage:BAAALgAECgcJCQAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAISAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAASAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgADCgcJCgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAFFAIJAgAAAA==.',
Ki='Kimari:BAACLgAFFH8IAAIVAAMJPhiKHADkAANoDAAABABGAGkMAAACADAA6gwAAAIAQwAVAAMJPhiKHADkAANoDAAABABGAGkMAAACADAA6gwAAAIAQwAuAAQKfxoAAhUACQmHGwINAHICABUACQmHGwINAHICAAAA.Kimìltonze:BAABLgAECn8eAAITAAkJJgw2HQBHAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQATAAkJJgw2HQBHAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAAAA==.Kite:BAAALgAECgIJAgAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAFFAMJBQAFAAkeAA==.',
Li='Lillith:BAAALgAECgYJEgAAAA==.Lilyanna:BAAALgAECgIJAwAAAA==.Limeaid:BAACLgAFFH8PAAMPAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4AA8ABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgADgABCbgUlWAARAABaAwAAAEANQAuAAQKfzUABA8ACQnxItIAAG8DAA8ACQnxItIAAG8DAA4ACAnfGFg2AFMBAAgAAglABOxAAGQAAAEuAAUUCAkaABYApxIA.Limelight:BAAALgAECgkJDgABLgAFFAgJGgAWAKcSAA==.Limeylady:BAACLgAFFH8aAAMWAAgJpxLpDgAdAghoDAAABQBPAGkMAAAFABkAawwAAAQAKABqDAAABAAhAGwMAAACACMAbQwAAAEAMQDqDAAABABBAG4MAAABADUAFgAHCZAS6Q4AHQIHaAwAAAQATwBpDAAABAAZAGsMAAABACgAagwAAAQAIQBsDAAAAgAjAOoMAAACAEEAbgwAAAEANQAXAAUJNBShDwBpAQVoDAAAAQA4AGkMAAABADIAawwAAAMABwBtDAAAAQA5AOoMAAACAFcALgAECn80AAMXAAkJ1SLrAwAdAwAXAAkJ1SLrAwAdAwAWAAcJmB6/EAA2AgAAAA==.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAUJGgAKAKQdAA==.Malvado:BAACLgAFFH8OAAMCAAQJcRP7BAA2AQRoDAAABQBRAGkMAAAEAC4AawwAAAEAFwDqDAAABAAvAAIABAlxE/sEADYBBGgMAAADAFEAaQwAAAQALgBrDAAAAQAXAOoMAAADAC8ACgACCSQEt64AcwACaAwAAAIAEADqDAAAAQAEAC4ABAp/NAAEAgAJCVkYKgYAGQIAAgAJCVkYKgYAGQIACgAFCXER0ZUALQEAAwAECcMQmSEAnQAAAAA=.Matheney:BAEALgAFFAEJAQABLgAFFAYJCwAOAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8XAAMYAAUJdh60RABjAQVoDAAACABhAGkMAAAFAF4AawwAAAIAJABqDAAAAgAqAOoMAAAGAFIAGAAFCXYetEQAYwEFaAwAAAcAYQBpDAAABABeAGsMAAACACQAagwAAAEAKgDqDAAABABSABkABAllHt4RAPYABGgMAAABAE0AaQwAAAEAUABqDAAAAQAYAOoMAAACAEoALgAECn8rAAMYAAkJvCQSBwA8AwAYAAkJvCQSBwA8AwAZAAMJeBpLHwDNAAAAAA==.Minji:BAABLgAECn8ZAAIaAAkJMBa5CQAiAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAaAAkJMBa5CQAiAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8YAAQMAAcJsAhFXAAMAQdoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8AbQwAAAEABADqDAAABAAJAAwABwmwCEVcAAwBB2gMAAACADYAaQwAAAIAJwBrDAAAAgAbAGoMAAABAAMAbAwAAAIADwBtDAAAAQAEAOoMAAACAAkAEgAECY4IRScBhAAEaQwAAAEAFQBrDAAAAQAbAGoMAAACABMAbAwAAAIAEAAbAAUJcwPYPwBbAAVoDAAAAQAIAGkMAAABAAQAawwAAAEABwBqDAAAAQAZAOoMAAACAA4AAAA=.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
Og='Ogma:BAAALgADCgUJBQAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Os='Osiris:BAAALgADCgcJBwAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgANAAAAAA==.',
Pr='Prey:BAABLgAECn8fAAMcAAkJvxc9DAAXAgloDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAACABMAG4MAAADACgAbwwAAAEAPgAcAAkJvxc9DAAXAgloDAAAAwBMAGkMAAADADkAawwAAAMASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABgBMAG4MAAADACgAbwwAAAEAPgAaAAQJNQLbLABfAARoDAAAAQACAGkMAAABAAQAawwAAAEABwDqDAAAAgAHAAAA.',
Pu='Purpp:BAAALgAFFAEJAQAAAA==.',
Py='Pyreyn:BAACLgAFFH8LAAMMAAMJdxg1KQDaAANoDAAABgA1AGkMAAADADEA6gwAAAIAVQAMAAMJdxg1KQDaAANoDAAABAA1AGkMAAABADEA6gwAAAIAVQASAAIJ1gjZKgB/AAJoDAAAAgAaAGkMAAACABIALgAECn8zAAMMAAgJEh6WHAAbAgAMAAcJCR6WHAAbAgASAAgJpxdASQDnAQAAAA==.',
Ra='Radley:BAAALgAECgYJDwABLgAFFAkJDQAZAKEVAA==.Raelilah:BAABLgAECn8iAAIHAAkJfRiHDQBKAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAHAAkJfRiHDQBKAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAAAA==.Raenia:BAAALgAECgEJAQAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIdAAcJfhThEACUAQdoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIAbQwAAAEAHQDqDAAABgBGAB0ABwl+FOEQAJQBB2gMAAAHAEEAaQwAAAYANwBrDAAABQArAGoMAAADACUAbAwAAAEAMgBtDAAAAQAdAOoMAAAGAEYALgAECn8YAAIdAAgJBxwOGwAsAgAdAAgJBxwOGwAsAgAAAA==.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAANAAAAAA==.Rheolette:BAAALgAECgEJAQAAAA==.Rheolin:BAAALgAECgYJEgAAAA==.Rheolynx:BAAALgAECgYJEQAAAA==.Rheomei:BAAALgAECgMJAwAAAA==.Rheomoon:BAABLgAECn8YAAIQAAcJ3xuFJwAcAgdoDAAABABJAGkMAAAEAFIAawwAAAQAUQBqDAAABABUAGwMAAADADQA6gwAAAQAYQBvDAAAAQAbABAABwnfG4UnABwCB2gMAAAEAEkAaQwAAAQAUgBrDAAABABRAGoMAAAEAFQAbAwAAAMANADqDAAABABhAG8MAAABABsAAAA=.',
Ri='Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCQAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAABLgAECn8UAAIVAAcJvxTaLABVAQdoDAAABQAvAGkMAAAFAEMAawwAAAMAOgBqDAAAAgAmAGwMAAACACkAbQwAAAEALQDqDAAAAgA6ABUABwm/FNosAFUBB2gMAAAFAC8AaQwAAAUAQwBrDAAAAwA6AGoMAAACACYAbAwAAAIAKQBtDAAAAQAtAOoMAAACADoAAAA=.',
Sa='Saelydera:BAAALgAECgQJBQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCQAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgYJEAAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQANAAAAAA==.',
Su='Suicidalone:BAAALgAECgEJAQAAAA==.',
Sy='Sylveon:BAABLgAFFH8OAAIaAAYJbyb3AAAnAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAQAYwAaAAYJbyb3AAAnAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAQAYwABLgAFFAMJBgAaAMccAA==.Syndara:BAAALgAECgUJCQAAAA==.',
Ta='Tab:BAAALgAECgkJAQAAAA==.',
Ti='Tiamatt:BAAALgAECgkJEQAAAA==.',
To='Tornheart:BAABLgAECn8uAAICAAkJCRV6BQASAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwACAAkJCRV6BQASAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMeAAkJmx+8CgC7AQloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAeAAgJPSC8CgC7AQhoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUACQACCd8a40cAlwACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAACLgAFFH8PAAIfAAQJlh6FBgBMAQRoDAAABgBZAGkMAAAEAEEAawwAAAEAUgDqDAAABABLAB8ABAmWHoUGAEwBBGgMAAAGAFkAaQwAAAQAQQBrDAAAAQBSAOoMAAAEAEsALgAECn8XAAIfAAgJexsICABBAgAfAAgJexsICABBAgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAYAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwANAAAAAA==.',
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
