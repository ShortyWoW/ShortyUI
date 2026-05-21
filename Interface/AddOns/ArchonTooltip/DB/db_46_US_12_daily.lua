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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Unknown-Unknown','Warlock-Demonology','DemonHunter-Vengeance','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Evoker-Preservation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Paladin-Protection','Druid-Guardian','Monk-Brewmaster','Hunter-Marksmanship','Hunter-Survival','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-05-20',data={Ab='Abcmico:BAAALgAFFAQJBAAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMBAAgJlhzFBQDgAQhoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAQAICZYcxQUA4AEIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAIABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
Az='Azuth:BAAALgADCgYJAQAAAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.',
Be='Beefcake:BAABLgAECn86AAIDAAgJ9yQ3CwCGAghoDAAACgBhAGkMAAAMAGAAawwAAAoAXQBqDAAABwBjAGwMAAAGAGMAbQwAAAEAUADqDAAACQBiAG4MAAADAGAAAwAICfckNwsAhgIIaAwAAAoAYQBpDAAADABgAGsMAAAKAF0AagwAAAcAYwBsDAAABgBjAG0MAAABAFAA6gwAAAkAYgBuDAAAAwBgAAAA.',
Bj='Bjorn:BAAALgAECgMJAwAAAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAEAHYYAA==.Borgor:BAAALgAECgUJCAAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgUJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJDwAFAAAAAA==.',
Ca='Canttoucthis:BAAALgADCgUJBQAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAAALgAFFAIJAwAAAA==.',
Ch='Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8IAAIEAAMJiRA1GwDyAANoDAAAAwA3AGkMAAACABsA6gwAAAMAKwAEAAMJiRA1GwDyAANoDAAAAwA3AGkMAAACABsA6gwAAAMAKwAuAAQKfy0AAgQACAnHHlkKAFECAAQACAnHHlkKAFECAAAA.',
Cr='Criticaltuna:BAACLgAFFH8MAAIGAAQJDBulKgBJAQRoDAAABABEAGkMAAACAEsAawwAAAIASQDqDAAABAA7AAYABAkMG6UqAEkBBGgMAAAEAEQAaQwAAAIASwBrDAAAAgBJAOoMAAAEADsALgAECn8oAAQCAAgJaB7pGQB9AQAGAAYJJBjzZACcAQACAAUJYRrpGQB9AQABAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAMJCgABAD0TAA==.Deathblooms:BAACLgAFFH8QAAIHAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYABwAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACBwAICTAitgEA/wIABwAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8KAAIIAAMJRiZIFABMAQNoDAAABABiAGkMAAADAGAA6gwAAAMAYgAIAAMJRiZIFABMAQNoDAAABABiAGkMAAADAGAA6gwAAAMAYgAuAAQKfzYAAggACQn4IhgDAE0DAAgACQn4IhgDAE0DAAAA.Destiniedrud:BAAALgAECgUJBQABLgAFFAMJCgAIAEYmAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAMJCgAIAEYmAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgEJAgAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwAFAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8IAAIJAAMJzgzALwDOAANoDAAAAwAdAGkMAAACABUA6gwAAAMALwAJAAMJzgzALwDOAANoDAAAAwAdAGkMAAACABUA6gwAAAMALwAuAAQKfzQAAwkACQl5GywKAIwCAAkACQl5GywKAIwCAAoAAgl6EiEWAHsAAAAA.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8cAAIJAAgJ2gSAPgD8AAhoDAAABgASAGkMAAAFABEAawwAAAQADgBqDAAABAAXAGwMAAAEAAkAbQwAAAEACQDqDAAAAwAJAG4MAAABAAcACQAICdoEgD4A/AAIaAwAAAYAEgBpDAAABQARAGsMAAAEAA4AagwAAAQAFwBsDAAABAAJAG0MAAABAAkA6gwAAAMACQBuDAAAAQAHAAAA.',
Ea='Earthen:BAAALgAFFAQJBAAAAA==.',
El='Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephemeral:BAAALgAECgQJBwABLgAECggJHQALAAwgAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAAALgAECgkJAwABLgAECgkJSQAMAP0ZAA==.',
Fa='Falkion:BAACLgAFFH8MAAIDAAMJ+h6eHAARAQNoDAAABgBaAGkMAAADAEkA6gwAAAMASQADAAMJ+h6eHAARAQNoDAAABgBaAGkMAAADAEkA6gwAAAMASQAuAAQKfzYAAgMACQkcIHYFAOUCAAMACQkcIHYFAOUCAAAA.',
Fi='Fistingpower:BAAALgAECgYJCgABLgAFFAMJCAAJAM4MAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8aAAINAAgJdxnODgDJAQhoDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAEAD4AbQwAAAEAJwDqDAAABABHAG4MAAABADMADQAICXcZzg4AyQEIaAwAAAQAXABpDAAABABJAGsMAAAEAEAAagwAAAQALQBsDAAABAA+AG0MAAABACcA6gwAAAQARwBuDAAAAQAzAAAA.',
Ge='Gemini:BAAALgAECgQJBAAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn8vAAMOAAkJ2xucBACaAgloDAAACABRAGkMAAAHAFEAawwAAAcAXwBqDAAABQBOAGwMAAAFAEcAbQwAAAMAJADqDAAABgA8AG4MAAAEAEkAbwwAAAIARgAOAAkJ2xucBACaAgloDAAABgBRAGkMAAAFAFEAawwAAAUAXwBqDAAABABOAGwMAAAEAEcAbQwAAAMAJADqDAAABQA8AG4MAAAEAEkAbwwAAAIARgADAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgMJAwAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgAFAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIPAAkJkSOkAgAiAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAPAAkJkSOkAgAiAwloDAAABgBaAGkMAAAGAGMAawwAAAYAXwBqDAAABgBbAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAFAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
Iu='Iu:BAABLgAECn8dAAMDAAgJoQxvKwB2AQhoDAAABQAnAGkMAAAFACwAawwAAAUALwBqDAAAAwAYAGwMAAADABMA6gwAAAUAJABuDAAAAQAQAG8MAAACABcAAwAICcgLbysAdgEIaAwAAAQAJwBpDAAABAAsAGsMAAAEAC8AagwAAAMAGABsDAAAAwATAOoMAAAEACQAbgwAAAEAEABvDAAAAQAIAA4ABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Jolly:BAABLgAECn81AAILAAkJRg6MVQChAQloDAAACAAdAGkMAAAHADUAawwAAAYALwBqDAAABgAZAGwMAAAHAB8AbQwAAAUAFADqDAAACAA2AG4MAAAFACUAbwwAAAEAEQALAAkJRg6MVQChAQloDAAACAAdAGkMAAAHADUAawwAAAYALwBqDAAABgAZAGwMAAAHAB8AbQwAAAUAFADqDAAACAA2AG4MAAAFACUAbwwAAAEAEQAAAA==.Jollymage:BAAALgAECgEJAgAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAILAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAALAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgADCgcJCgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAECgkJCQAAAA==.',
Ki='Kimari:BAAALgAFFAEJAQAAAA==.Kimìltonze:BAABLgAECn8dAAINAAgJswz9GgAtAQhoDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AG4MAAABAAcADQAICbMM/RoALQEIaAwAAAUATgBpDAAABQAiAGsMAAAFABMAagwAAAMAEQBsDAAAAwARAG0MAAACAA0A6gwAAAUANgBuDAAAAQAHAAAA.Kite:BAAALgAECgEJAQAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAECggJOgADAPckAA==.',
Li='Lillith:BAAALgAECgYJEQAAAA==.Lilyanna:BAAALgAECgIJAgAAAA==.Limeaid:BAACLgAFFH8PAAMKAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4AAoABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgACQABCbgUyEgASwABaAwAAAEANQAuAAQKfzIABAoACQnxItIAAG8DAAoACQnxItIAAG8DAAkACAnfGDssAFkBAAwAAglABOxAAGQAAAEuAAUUBgkPABAAyAwA.Limeylady:BAACLgAFFH8PAAMQAAYJyAyUDQDEAQZoDAAAAgAhAGkMAAACABEAawwAAAIAKABqDAAABAAhAGwMAAACACMA6gwAAAMAJQAQAAYJyAyUDQDEAQZoDAAAAQAhAGkMAAABABEAawwAAAEAKABqDAAABAAhAGwMAAACACMA6gwAAAEAJQARAAQJkBPVEAA6AQRoDAAAAQA4AGkMAAABADIAawwAAAEABgDqDAAAAgBXAC4ABAp/LgADEQAJCVUgxgcApwIAEQAICUIgxgcApwIAEAAHCZgevxAANgIAAAA=.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAQJDAAGAAwbAA==.Malvado:BAACLgAFFH8KAAMBAAMJPRPoAwD+AANoDAAABABSAGkMAAADAC4A6gwAAAMAEgABAAMJPRPoAwD+AANoDAAAAgBSAGkMAAADAC4A6gwAAAIAEgAGAAIJJASBiAB9AAJoDAAAAgAQAOoMAAABAAQALgAECn80AAQBAAkJWRhKAwBBAgABAAkJWRhKAwBBAgAGAAUJcRHRlQAtAQACAAQJuhBCGwCjAAAAAA==.Matheney:BAAALgAFFAEJAQABLgAFFAYJCwAJAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8MAAMSAAMJYCM+CAAQAQNoDAAABgBhAGkMAAADAF4A6gwAAAMATwATAAMJYCPfUwAfAQNoDAAABQBhAGkMAAACAF4A6gwAAAIATwASAAMJOh0+CAAQAQNoDAAAAQBNAGkMAAABAFAA6gwAAAEAQQAuAAQKfygAAxMACQlYIscGACEDABMACQlYIscGACEDABIAAgl7GvocAIAAAAAA.Minji:BAABLgAECn8ZAAIUAAkJLhbJBgAwAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAUAAkJLhbJBgAwAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8XAAQIAAYJ0QlFXAAMAQZoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8A6gwAAAQACQAIAAYJ0QlFXAAMAQZoDAAAAgA2AGkMAAACACcAawwAAAIAGwBqDAAAAQADAGwMAAACAA8A6gwAAAIACQALAAQJjggQ9ACMAARpDAAAAQAVAGsMAAABABsAagwAAAIAEwBsDAAAAgAQABUABQlzA98zAFwABWgMAAABAAgAaQwAAAEABABrDAAAAQAHAGoMAAABABkA6gwAAAIADgAAAA==.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Pr='Prey:BAABLgAECn8dAAMWAAgJehcwDADUAQhoDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABwBKAG4MAAADACgAFgAICXoXMAwA1AEIaAwAAAMATABpDAAAAwA5AGsMAAADAEsAagwAAAMARABsDAAAAwBGAG0MAAABABkA6gwAAAUASgBuDAAAAwAoABQABAk1AtssAF8ABGgMAAABAAIAaQwAAAEABABrDAAAAQAHAOoMAAACAAcAAAA=.',
Pu='Purpp:BAAALgAECgEJAgAAAA==.',
Py='Pyreyn:BAABLgAECn8mAAMIAAcJIB2BGgD8AQdoDAAABgAqAGkMAAAGAFkAawwAAAYAUQBqDAAABQBAAGwMAAAEAE8A6gwAAAcAQwBuDAAABABgAAgABwkgHYEaAPwBB2gMAAAEACoAaQwAAAYAWQBrDAAABQBRAGoMAAAEAEAAbAwAAAQATwDqDAAABQBDAG4MAAAEAGAACwAECfYSS9kAtAAEaAwAAAIAJABrDAAAAQAvAGoMAAABADQA6gwAAAIAPQAAAA==.',
Ra='Radley:BAAALgAECgUJBQAAAA==.Raelilah:BAABLgAECn8iAAIEAAkJdhj1CABoAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOQDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAEAAkJdhj1CABoAgloDAAABgBAAGkMAAAFAEcAawwAAAUAPgBqDAAABABNAGwMAAAEAEgAbQwAAAIAOQDqDAAABQBRAG4MAAACACoAbwwAAAEAMAAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIXAAcJfBS9BwCvAQdoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIAbQwAAAEAHQDqDAAABgBGABcABwl8FL0HAK8BB2gMAAAHAEEAaQwAAAYANwBrDAAABQArAGoMAAADACUAbAwAAAEAMgBtDAAAAQAdAOoMAAAGAEYALgAECn8YAAIXAAgJBxwOGwAsAgAXAAgJBxwOGwAsAgAAAA==.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAAFAAAAAA==.Rheolin:BAAALgADCgEJAQAAAA==.Rheomoon:BAAALgAECgQJBgAAAA==.',
Ri='Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCAAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAAALgAECgYJEwAAAA==.',
Sa='Saelydera:BAAALgAECgEJAQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCAAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgQJCgAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQAFAAAAAA==.',
Su='Suicidalone:BAAALgADCgcJEwAAAA==.',
Sy='Sylveon:BAABLgAFFH8GAAIUAAUJxyT6AAC5AQVoDAAAAQBiAGkMAAACAF0AawwAAAEAWABqDAAAAQBiAOoMAAABAGAAFAAFCcck+gAAuQEFaAwAAAEAYgBpDAAAAgBdAGsMAAABAFgAagwAAAEAYgDqDAAAAQBgAAEuAAUUAwkGABQAxxwA.',
Ta='Tab:BAAALgAECgcJAQAAAA==.',
Ti='Tiamatt:BAAALgAECggJEAAAAA==.',
To='Tornheart:BAABLgAECn8uAAIBAAkJCRVZBAAVAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwABAAkJCRVZBAAVAgloDAAABwA9AGkMAAAFAEIAawwAAAYANABqDAAABAAaAGwMAAAFABQAbQwAAAUANgDqDAAABwA1AG4MAAAFAEoAbwwAAAIALwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgQJBwAAAA==.Tubbycoin:BAABLgAECn8fAAMYAAkJmx8rCADMAQloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAYAAgJPSArCADMAQhoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUAGQACCd8a2zwAnQACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAACLgAFFH8MAAIaAAMJWR2fBgAHAQNoDAAABQBTAGkMAAADAEEA6gwAAAQASwAaAAMJWR2fBgAHAQNoDAAABQBTAGkMAAADAEEA6gwAAAQASwAuAAQKfxcAAhoACAl3G18FAFQCABoACAl3G18FAFQCAAAA.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAATAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwAFAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wy='Wyburn:BAAALgAECgQJBgAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
['Yø']='Yøriçk:BAAALgAECgYJEgAAAA==.',
Za='Zane:BAAALgAECgYJBwAAAA==.Zaraelina:BAAALgAECgYJCQAAAA==.',
['Çl']='Çleadon:BAAALgAECgcJDgAAAA==.',
['ßê']='ßêästÿßöÿ:BAAALgAECgUJBQABLgAECgYJBwAFAAAAAA==.',
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
