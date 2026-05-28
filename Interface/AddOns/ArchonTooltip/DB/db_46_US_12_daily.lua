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

local lookup = {'Mage-Frost','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','Hunter-Survival','Warlock-Demonology','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Paladin-Protection','Druid-Guardian','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-05-27',data={Ab='Abcmico:BAABLgAECn8XAAIBAAkJ3RxSFQDAAgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgABAAkJ3RxSFQDAAgloDAAABABVAGkMAAACAE8AawwAAAIARwBqDAAAAgBMAGwMAAADAEoAbQwAAAIAVgDqDAAABQBfAG4MAAACAEkAbwwAAAEAFgAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMCAAgJlhxkBwDSAQhoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAgAICZYcZAcA0gEIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAMABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgAEAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.',
Be='Beefcake:BAABLgAECn9CAAIFAAgJ9yRgDACKAghoDAAACwBhAGkMAAANAGAAawwAAAsAXQBqDAAACABjAGwMAAAIAGMAbQwAAAEAUADqDAAACgBiAG4MAAAEAGAABQAICfckYAwAigIIaAwAAAsAYQBpDAAADQBgAGsMAAALAF0AagwAAAgAYwBsDAAACABjAG0MAAABAFAA6gwAAAoAYgBuDAAABABgAAAA.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAUJDQAGAKEIAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAHAH0YAA==.Borgor:BAAALgAECgYJCQAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgUJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJFAAIAOUMAA==.',
Ca='Canttoucthis:BAAALgADCgUJBQAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAABLgAFFH8GAAIJAAMJFxadFgD8AANoDAAAAgApAGkMAAABADEA6gwAAAMATwAJAAMJFxadFgD8AANoDAAAAgApAGkMAAABADEA6gwAAAMATwAAAA==.',
Ch='Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8JAAIHAAMJtRDSHwDyAANoDAAABAA5AGkMAAACABsA6gwAAAMAKwAHAAMJtRDSHwDyAANoDAAABAA5AGkMAAACABsA6gwAAAMAKwAuAAQKfy4AAgcACAkrHxYLAFYCAAcACAkrHxYLAFYCAAAA.',
Cr='Criticaltuna:BAACLgAFFH8OAAIKAAQJDBukNQBDAQRoDAAABABEAGkMAAACAEsAawwAAAIASQDqDAAABgA7AAoABAkMG6Q1AEMBBGgMAAAEAEQAaQwAAAIASwBrDAAAAgBJAOoMAAAGADsALgAECn8oAAQDAAgJaB7pGQB9AQAKAAYJJBjzZACcAQADAAUJYBrpGQB9AQACAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAQJDgACAIcTAA==.Deathblooms:BAACLgAFFH8QAAILAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYACwAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACCwAICTAitgEA/wIACwAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8OAAIMAAQJ3SMXDwCdAQRoDAAABQBiAGkMAAAEAGAAawwAAAEASQDqDAAABABiAAwABAndIxcPAJ0BBGgMAAAFAGIAaQwAAAQAYABrDAAAAQBJAOoMAAAEAGIALgAECn84AAIMAAkJ+CLvAwBIAwAMAAkJ+CLvAwBIAwAAAA==.Destiniedrud:BAAALgAECgUJCgABLgAFFAQJDgAMAN0jAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAQJDgAMAN0jAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgEJAgAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwANAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8MAAIOAAQJAhHmJAAOAQRoDAAABAAqAGkMAAADACUAawwAAAEALgDqDAAABAAvAA4ABAkCEeYkAA4BBGgMAAAEACoAaQwAAAMAJQBrDAAAAQAuAOoMAAAEAC8ALgAECn80AAMOAAkJhRu2CwCCAgAOAAkJhRu2CwCCAgAPAAIJehL+FwB7AAAAAA==.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8jAAIOAAgJNwXiRADvAAhoDAAABwAUAGkMAAAGABEAawwAAAUADgBqDAAABQAqAGwMAAAFAA0AbQwAAAEACQDqDAAABAAJAG4MAAACAAcADgAICTcF4kQA7wAIaAwAAAcAFABpDAAABgARAGsMAAAFAA4AagwAAAUAKgBsDAAABQANAG0MAAABAAkA6gwAAAQACQBuDAAAAgAHAAAA.',
Ea='Earthen:BAABLgAFFH8GAAIQAAQJsQ86JwAcAQRoDAAAAwBiAGkMAAABAAQAawwAAAEABADqDAAAAQA0ABAABAmxDzonABwBBGgMAAADAGIAaQwAAAEABABrDAAAAQAEAOoMAAABADQAAS4ABRQFCQoAEQBjGgA=.',
El='Elfisto:BAAALgAECgEJAQAAAA==.Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephemeral:BAAALgAECgQJCAABLgAECggJJAASAHghAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJTQAIANQXAA==.',
Fa='Falkion:BAACLgAFFH8PAAIFAAQJmx0HEABcAQRoDAAABwBaAGkMAAAEAEkAawwAAAEAQQDqDAAAAwBJAAUABAmbHQcQAFwBBGgMAAAHAFoAaQwAAAQASQBrDAAAAQBBAOoMAAADAEkALgAECn82AAIFAAkJJyA7BwDVAgAFAAkJJyA7BwDVAgAAAA==.',
Fi='Fistingpower:BAAALgAECggJEgABLgAFFAQJDAAOAAIRAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8dAAITAAkJuRmeCwAYAgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAFAEsAbQwAAAEAJwDqDAAABABHAG4MAAACADMAbwwAAAEAOQATAAkJuRmeCwAYAgloDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAFAEsAbQwAAAEAJwDqDAAABABHAG4MAAACADMAbwwAAAEAOQAAAA==.',
Ge='Gemini:BAAALgAECgUJBQAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn8xAAMUAAkJLR2SBACvAgloDAAACABRAGkMAAAHAFEAawwAAAcAXwBqDAAABQBOAGwMAAAFAEcAbQwAAAMAJADqDAAABwBTAG4MAAAFAE4AbwwAAAIARgAUAAkJLR2SBACvAgloDAAABgBRAGkMAAAFAFEAawwAAAUAXwBqDAAABABOAGwMAAAEAEcAbQwAAAMAJADqDAAABgBTAG4MAAAFAE4AbwwAAAIARgAFAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgANAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIVAAkJkSN1AwAXAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAVAAkJkSN1AwAXAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
Iu='Iu:BAABLgAECn8dAAMFAAgJoQwLMQBtAQhoDAAABQAnAGkMAAAFACwAawwAAAUALwBqDAAAAwAYAGwMAAADABMA6gwAAAUAJABuDAAAAQAQAG8MAAACABcABQAICcgLCzEAbQEIaAwAAAQAJwBpDAAABAAsAGsMAAAEAC8AagwAAAMAGABsDAAAAwATAOoMAAAEACQAbgwAAAEAEABvDAAAAQAIABQABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn81AAISAAkJRg5JZwCFAQloDAAACAAdAGkMAAAHADUAawwAAAYALwBqDAAABgAZAGwMAAAHAB8AbQwAAAUAFADqDAAACAA2AG4MAAAFACUAbwwAAAEAEQASAAkJRg5JZwCFAQloDAAACAAdAGkMAAAHADUAawwAAAYALwBqDAAABgAZAGwMAAAHAB8AbQwAAAUAFADqDAAACAA2AG4MAAAFACUAbwwAAAEAEQAAAA==.Jollymage:BAAALgAECgcJCQAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAISAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAASAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgADCgcJCgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAECgkJEgAAAA==.',
Ki='Kimari:BAAALgAFFAEJAQAAAA==.Kimìltonze:BAABLgAECn8eAAITAAkJJgy7GABZAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQATAAkJJgy7GABZAQloDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcAbwwAAAEAFQAAAA==.Kite:BAAALgAECgEJAQAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAECggJQgAFAPckAA==.',
Li='Lillith:BAAALgAECgYJEgAAAA==.Lilyanna:BAAALgAECgIJAwAAAA==.Limeaid:BAACLgAFFH8PAAMPAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4AA8ABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgADgABCbgURFIARQABaAwAAAEANQAuAAQKfzUABA8ACQnxItIAAG8DAA8ACQnxItIAAG8DAA4ACAnfGGUwAFEBAAgAAglABOxAAGQAAAEuAAUUBwkTABYAoRAA.Limeylady:BAACLgAFFH8TAAMWAAcJoRBXDwDRAQdoDAAAAwBPAGkMAAADABYAawwAAAMAKABqDAAABAAhAGwMAAACACMAbQwAAAEAMQDqDAAAAwAlABYABgkwEFcPANEBBmgMAAACAE8AaQwAAAIAFgBrDAAAAQAoAGoMAAAEACEAbAwAAAIAIwDqDAAAAQAlABcABQk0FNsKAIMBBWgMAAABADgAaQwAAAEAMgBrDAAAAgAHAG0MAAABADkA6gwAAAIAVwAuAAQKfzEAAxcACQnWH/MEAOwCABcACQnWH/MEAOwCABYABwmYHr8QADYCAAAA.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAQJDgAKAAwbAA==.Malvado:BAACLgAFFH8OAAMCAAQJhxPfAgBPAQRoDAAABQBRAGkMAAAEAC4AawwAAAEAFwDqDAAABAAwAAIABAmHE98CAE8BBGgMAAADAFEAaQwAAAQALgBrDAAAAQAXAOoMAAADADAACgACCSQELJcAewACaAwAAAIAEADqDAAAAQAEAC4ABAp/NAAEAgAJCVkYUgQALgIAAgAJCVkYUgQALgIACgAFCXER0ZUALQEAAwAECcMQ0R0AoAAAAAA=.Matheney:BAAALgAFFAEJAQABLgAFFAYJCwAOAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8NAAMYAAMJYCNdCwAKAQNoDAAABgBhAGkMAAADAF4A6gwAAAQATwAZAAMJYCPZZAAOAQNoDAAABQBhAGkMAAACAF4A6gwAAAIATwAYAAMJdR5dCwAKAQNoDAAAAQBNAGkMAAABAFAA6gwAAAIASwAuAAQKfykAAxkACQliI7EIABkDABkACQlaIrEIABkDABgAAwl4GsEYAMwAAAAA.Minji:BAABLgAECn8ZAAIaAAkJMBboBwAtAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAaAAkJMBboBwAtAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8YAAQMAAcJsAhFXAAMAQdoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8AbQwAAAEABADqDAAABAAJAAwABwmwCEVcAAwBB2gMAAACADYAaQwAAAIAJwBrDAAAAgAbAGoMAAABAAMAbAwAAAIADwBtDAAAAQAEAOoMAAACAAkAEgAECY4I1AgBhgAEaQwAAAEAFQBrDAAAAQAbAGoMAAACABMAbAwAAAIAEAAbAAUJcwMFOQBbAAVoDAAAAQAIAGkMAAABAAQAawwAAAEABwBqDAAAAQAZAOoMAAACAA4AAAA=.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Os='Osiris:BAAALgADCgEJAQAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgANAAAAAA==.',
Pr='Prey:BAABLgAECn8fAAMcAAkJwhfpCQAeAgloDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAACABNAG4MAAADACgAbwwAAAEAPgAcAAkJwhfpCQAeAgloDAAAAwBMAGkMAAADADkAawwAAAMASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABgBNAG4MAAADACgAbwwAAAEAPgAaAAQJNQLbLABfAARoDAAAAQACAGkMAAABAAQAawwAAAEABwDqDAAAAgAHAAAA.',
Pu='Purpp:BAAALgAECgEJAgAAAA==.',
Py='Pyreyn:BAACLgAFFH8GAAMSAAIJ1gjZKgB/AAJoDAAABAAaAGkMAAACABIAEgACCdYI2SoAfwACaAwAAAIAGgBpDAAAAgASAAwAAQlrE/k+AD4AAWgMAAACADEALgAECn8rAAMMAAcJCR4YGQAhAgAMAAcJCR4YGQAhAgASAAYJyRPUmwAgAQAAAA==.',
Ra='Radley:BAAALgAECgYJCgABLgAFFAQJCgAYALIRAA==.Raelilah:BAABLgAECn8iAAIHAAkJfRgMCwBXAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAHAAkJfRgMCwBXAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOgDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAAAA==.Raenia:BAAALgAECgEJAQAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIdAAcJfhTACgCmAQdoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIAbQwAAAEAHQDqDAAABgBGAB0ABwl+FMAKAKYBB2gMAAAHAEEAaQwAAAYANwBrDAAABQArAGoMAAADACUAbAwAAAEAMgBtDAAAAQAdAOoMAAAGAEYALgAECn8YAAIdAAgJBxwOGwAsAgAdAAgJBxwOGwAsAgAAAA==.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAANAAAAAA==.Rheolette:BAAALgAECgEJAQAAAA==.Rheolin:BAAALgAECgQJBAAAAA==.Rheolynx:BAAALgAECgYJBgAAAA==.Rheomoon:BAAALgAECgcJDAAAAA==.',
Ri='Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCQAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAAALgAECgYJEwAAAA==.',
Sa='Saelydera:BAAALgAECgQJBQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCAAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgQJCgAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQANAAAAAA==.',
Su='Suicidalone:BAAALgAECgEJAQAAAA==.',
Sy='Sylveon:BAABLgAFFH8MAAIaAAYJbyZeAABDAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAIAYwAaAAYJbyZeAABDAgZoDAAAAgBiAGkMAAADAGMAawwAAAIAXwBqDAAAAgBiAGwMAAABAGMA6gwAAAIAYwABLgAFFAMJBgAaAMccAA==.Syndara:BAAALgAECgEJAQAAAA==.',
Ta='Tab:BAAALgAECgkJAQAAAA==.',
Ti='Tiamatt:BAAALgAECgkJEQAAAA==.',
To='Tornheart:BAABLgAECn8uAAICAAkJCRWIBQAFAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwACAAkJCRWIBQAFAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMeAAkJmx9iCQDDAQloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAeAAgJPSBiCQDDAQhoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUACQACCd8aLEIAmQACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAACLgAFFH8PAAIfAAQJox6VAwBqAQRoDAAABgBZAGkMAAAEAEEAawwAAAEAUgDqDAAABABLAB8ABAmjHpUDAGoBBGgMAAAGAFkAaQwAAAQAQQBrDAAAAQBSAOoMAAAEAEsALgAECn8XAAIfAAgJexueBgBJAgAfAAgJexueBgBJAgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAZAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwANAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wy='Wyburn:BAAALgAECgUJCAAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
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
