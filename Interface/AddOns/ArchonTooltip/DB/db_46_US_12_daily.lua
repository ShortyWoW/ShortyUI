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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Unknown-Unknown','Warlock-Demonology','DemonHunter-Vengeance','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Evoker-Preservation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Paladin-Protection','Druid-Guardian','Monk-Brewmaster','Hunter-Marksmanship','Hunter-Survival','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='daily',zone=46,date='2026-05-13',data={Ab='Abcmico:BAAALgAECgkJEAAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMBAAgJlhy7AgAcAghoDAAABwBZAGkMAAAFADUAawwAAAUAUwBqDAAABABUAGwMAAAFAFIAbQwAAAQAPgDqDAAABgBFAG4MAAACAEcAAQAICZYcuwIAHAIIaAwAAAYAWQBpDAAABAA1AGsMAAAEAFMAagwAAAQAVABsDAAABQBSAG0MAAAEAD4A6gwAAAUARQBuDAAAAgBHAAIABAmkEVw0AOUABGgMAAABAFMAaQwAAAEAMQBrDAAAAQAEAOoMAAABACoAAAA=.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJJQADAMsOAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.',
Be='Beefcake:BAABLgAECn80AAIEAAgJ9yQ3BwCRAghoDAAACQBhAGkMAAALAGAAawwAAAkAXQBqDAAABgBjAGwMAAAGAGMAbQwAAAEAUADqDAAACABiAG4MAAACAGAABAAICfckNwcAkQIIaAwAAAkAYQBpDAAACwBgAGsMAAAJAF0AagwAAAYAYwBsDAAABgBjAG0MAAABAFAA6gwAAAgAYgBuDAAAAgBgAAAA.',
Bj='Bjorn:BAAALgADCgUJAwABLgAFFAQJDAAFAFIKAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECggJGgAGAFQWAA==.Borgor:BAAALgAECgUJCAAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgQJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJCQAHAAAAAA==.',
Ca='Canttoucthis:BAAALgADCgUJBQAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAAALgAFFAEJAQAAAA==.',
Ch='Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAABLgAECn8mAAIGAAgJSBm1CQAbAghoDAAABgBUAGkMAAAGAEYAawwAAAYAXABqDAAABQBLAGwMAAAFADgAbQwAAAMAFwDqDAAABgA9AG4MAAABAD8ABgAICUgZtQkAGwIIaAwAAAYAVABpDAAABgBGAGsMAAAGAFwAagwAAAUASwBsDAAABQA4AG0MAAADABcA6gwAAAYAPQBuDAAAAQA/AAAA.',
Cr='Criticaltuna:BAACLgAFFH8KAAIIAAQJOxYcJQA7AQRoDAAABABFAGkMAAACAEwAawwAAAEAFgDqDAAAAwA7AAgABAk7FhwlADsBBGgMAAAEAEUAaQwAAAIATABrDAAAAQAWAOoMAAADADsALgAECn8oAAQCAAgJaB7pGQB9AQAIAAYJJBjzZACcAQACAAUJYRrpGQB9AQABAAEJlx8xJQBdAAAAAA==.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAMJBgABAP4KAA==.Deathblooms:BAACLgAFFH8QAAIJAAUJkR1SAACgAQVoDAAABABWAGkMAAAEAEsAawwAAAMANgBqDAAAAgAMAOoMAAADAFYACQAFCZEdUgAAoAEFaAwAAAQAVgBpDAAABABLAGsMAAADADYAagwAAAIADADqDAAAAwBWAC4ABAp/KgACCQAICTAitgEA/wIACQAICTAitgEA/wIAAAA=.Destinie:BAACLgAFFH8GAAIKAAMJUybRDwBQAQNoDAAAAwBiAGkMAAACAGAA6gwAAAEAYgAKAAMJUybRDwBQAQNoDAAAAwBiAGkMAAACAGAA6gwAAAEAYgAuAAQKfzAAAgoACQmKIs8DABUDAAoACQmKIs8DABUDAAAA.Destiniedrud:BAAALgAECgUJBQABLgAFFAMJBgAKAFMmAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAMJBgAKAFMmAA==.',
Di='Dimlock:BAAALgAECggJCgAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwAHAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8HAAILAAMJzgyIJwDVAANoDAAAAwAdAGkMAAACABUA6gwAAAIALwALAAMJzgyIJwDVAANoDAAAAwAdAGkMAAACABUA6gwAAAIALwAuAAQKfy4AAwsACQl+GhsGAJoCAAsACQl+GhsGAJoCAAwAAgl6EpoRAIQAAAAA.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8cAAILAAgJ2gQ0LgAGAQhoDAAABgASAGkMAAAFABEAawwAAAQADgBqDAAABAAXAGwMAAAEAAkAbQwAAAEACQDqDAAAAwAJAG4MAAABAAcACwAICdoENC4ABgEIaAwAAAYAEgBpDAAABQARAGsMAAAEAA4AagwAAAQAFwBsDAAABAAJAG0MAAABAAkA6gwAAAMACQBuDAAAAQAHAAAA.',
El='Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emrauld:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephemeral:BAAALgAECgMJAwABLgAECggJFQANAPocAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJOQAOAP0ZAA==.',
Fa='Falkion:BAACLgAFFH8IAAIEAAMJZh6hGgD4AANoDAAABQBWAGkMAAACAEkA6gwAAAEASQAEAAMJZh6hGgD4AANoDAAABQBWAGkMAAACAEkA6gwAAAEASQAuAAQKfzAAAgQACQmLH6AEAMwCAAQACQmLH6AEAMwCAAAA.',
Fi='Fistingpower:BAAALgAECgUJCAABLgAFFAMJBwALAM4MAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8aAAIPAAgJdxn1CQDnAQhoDAAABABcAGkMAAAEAEkAawwAAAQAQABqDAAABAAtAGwMAAAEAD4AbQwAAAEAJwDqDAAABABHAG4MAAABADMADwAICXcZ9QkA5wEIaAwAAAQAXABpDAAABABJAGsMAAAEAEAAagwAAAQALQBsDAAABAA+AG0MAAABACcA6gwAAAQARwBuDAAAAQAzAAAA.',
Ge='Gemini:BAAALgADCgUJBwAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn8mAAMQAAkJkhdZBQBEAgloDAAABwBIAGkMAAAGAD8AawwAAAYAXwBqDAAABABKAGwMAAAEAEQAbQwAAAIAJADqDAAABQA6AG4MAAADADAAbwwAAAEAJgAQAAkJ8xZZBQBEAgloDAAABQA8AGkMAAAEAD8AawwAAAQAXwBqDAAAAwBKAGwMAAADAEQAbQwAAAIAJADqDAAABAA6AG4MAAADADAAbwwAAAEAJgAEAAYJHhYYRwCIAQZoDAAAAgBIAGkMAAACADQAawwAAAIAPABqDAAAAQAeAGwMAAABADEA6gwAAAEALwAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIRAAkJoCNTAQA/AwloDAAABgBaAGkMAAAGAGMAawwAAAYAYABqDAAABgBcAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAARAAkJoCNTAQA/AwloDAAABgBaAGkMAAAGAGMAawwAAAYAYABqDAAABgBcAGwMAAAGAF0AbQwAAAcAXADqDAAABwBhAG4MAAAEAF8AbwwAAAMAQAAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAECggJDQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAHAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
Iu='Iu:BAABLgAECn8XAAMQAAgJVQiZJADIAAhoDAAABAAOAGkMAAAEACUAawwAAAQAFgBqDAAAAgAJAGwMAAACAA8A6gwAAAQAEwBuDAAAAQAQAG8MAAACABcABAAICZEFmGkADwEIaAwAAAMACwBpDAAAAwAPAGsMAAADABMAagwAAAIACQBsDAAAAgAPAOoMAAADAAwAbgwAAAEAEABvDAAAAQAIABAABQkqCZkkAMgABWgMAAABAA4AaQwAAAEAJQBrDAAAAQAWAOoMAAABABMAbwwAAAEAFwAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Jolly:BAABLgAECn8sAAINAAgJ4g3XXgBHAQhoDAAABwAdAGkMAAAGADUAawwAAAUAKABqDAAABQAZAGwMAAAGABMAbQwAAAQAFADqDAAABwA2AG4MAAAEAB4ADQAICeIN114ARwEIaAwAAAcAHQBpDAAABgA1AGsMAAAFACgAagwAAAUAGQBsDAAABgATAG0MAAAEABQA6gwAAAcANgBuDAAABAAeAAAA.Jollymage:BAAALgAECgEJAgAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAINAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAANAAkJJA0JTQD7AQloDAAABAA1AGkMAAAEACYAawwAAAQAJQBqDAAABAAeAGwMAAAEACIAbQwAAAMAEgDqDAAAAwAuAG4MAAACAAsAbwwAAAEAHAAAAA==.Kathadin:BAAALgADCgcJCgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.',
Ki='Kimari:BAAALgAFFAEJAQAAAA==.Kimìltonze:BAABLgAECn8cAAIPAAcJTA4+GAALAQdoDAAABQBOAGkMAAAFACIAawwAAAUAEwBqDAAAAwARAGwMAAADABEAbQwAAAIADQDqDAAABQA2AA8ABwlMDj4YAAsBB2gMAAAFAE4AaQwAAAUAIgBrDAAABQATAGoMAAADABEAbAwAAAMAEQBtDAAAAgANAOoMAAAFADYAAAA=.Kite:BAAALgAECgEJAQAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAECggJNAAEAPckAA==.',
Li='Lillith:BAAALgAECgYJEQAAAA==.Lilyanna:BAAALgAECgEJAQAAAA==.Limeaid:BAACLgAFFH8PAAMMAAQJ6h1HAgBoAQRoDAAABABQAGkMAAAEAFkAawwAAAMAUADqDAAABAA4AAwABAnqHUcCAGgBBGgMAAADAFAAaQwAAAQAWQBrDAAAAwBQAOoMAAAEADgACwABCbgUHD0ATgABaAwAAAEANQAuAAQKfzEABAwACQnxItIAAG8DAAwACQnxItIAAG8DAAsACAnfGDcbAH8BAA4AAglABOxAAGQAAAEuAAUUBgkNABIA1AwA.Limeylady:BAACLgAFFH8NAAMSAAYJ1AyXCQDMAQZoDAAAAgAhAGkMAAACABEAawwAAAIAKABqDAAABAAhAGwMAAABACMA6gwAAAIAJQASAAYJ1AyXCQDMAQZoDAAAAQAhAGkMAAABABEAawwAAAEAKABqDAAABAAhAGwMAAABACMA6gwAAAEAJQATAAQJTw36DwAsAQRoDAAAAQA4AGkMAAABADIAawwAAAEABgDqDAAAAQAXAC4ABAp/IQADEgAJCYsfrA0AFQIAEgAHCZgerA0AFQIAEwAGCbcajBUArwEAAAA=.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAQJCgAIADsWAA==.Malvado:BAACLgAFFH8GAAMBAAMJ/gokBQCeAANoDAAAAwA4AGkMAAACABcA6gwAAAEABAABAAIJiA8kBQCeAAJoDAAAAQA4AGkMAAACABcACAACCSQE23cAfQACaAwAAAIAEADqDAAAAQAEAC4ABAp/LgAEAQAJCX4WTAMA+wEAAQAJCT8VTAMA+wEACAAFCXERr3sA5gAAAgAECboQABcApgAAAAA=.Matheney:BAAALgAECggJCAABLgAFFAQJBQALAEQKAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8IAAIUAAMJxCA2RAAiAQNoDAAABQBhAGkMAAACAF4A6gwAAAEAOwAUAAMJxCA2RAAiAQNoDAAABQBhAGkMAAACAF4A6gwAAAEAOwAuAAQKfyEAAxQACQn9IWEIAO4CABQACQn9IWEIAO4CABUAAgl7GmESAJQAAAAA.Minji:BAABLgAECn8ZAAIWAAkJLhZUBABOAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAWAAkJLhZUBABOAgloDAAAAwBLAGkMAAADAEsAawwAAAMAPgBqDAAAAwA4AGwMAAADACsAbQwAAAMAOADqDAAAAwA3AG4MAAADADkAbwwAAAEAGgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8XAAQKAAYJ0QlFXAAMAQZoDAAAAwA2AGkMAAAEACcAawwAAAQAGwBqDAAABAADAGwMAAAEAA8A6gwAAAQACQAKAAYJ0QlFXAAMAQZoDAAAAgA2AGkMAAACACcAawwAAAIAGwBqDAAAAQADAGwMAAACAA8A6gwAAAIACQANAAQJjghzxACSAARpDAAAAQAVAGsMAAABABsAagwAAAIAEwBsDAAAAgAQABcABQlzA8QqAGIABWgMAAABAAgAaQwAAAEABABrDAAAAQAHAGoMAAABABkA6gwAAAIADgAAAA==.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgcJBwAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Pr='Prey:BAABLgAECn8bAAMYAAgJehcTCADfAQhoDAAABABMAGkMAAAEADkAawwAAAQASwBqDAAAAwBEAGwMAAADAEYAbQwAAAEAGQDqDAAABgBKAG4MAAACACgAGAAICXoXEwgA3wEIaAwAAAMATABpDAAAAwA5AGsMAAADAEsAagwAAAMARABsDAAAAwBGAG0MAAABABkA6gwAAAQASgBuDAAAAgAoABYABAk1AtssAF8ABGgMAAABAAIAaQwAAAEABABrDAAAAQAHAOoMAAACAAcAAAA=.',
Pu='Purpp:BAAALgAECgEJAQAAAA==.',
Py='Pyreyn:BAABLgAECn8lAAMKAAcJJx1tEwARAgdoDAAABgAqAGkMAAAGAFkAawwAAAYAUgBqDAAABQBAAGwMAAAEAE8A6gwAAAYAQwBuDAAABABgAAoABwknHW0TABECB2gMAAAEACoAaQwAAAYAWQBrDAAABQBSAGoMAAAEAEAAbAwAAAQATwDqDAAABQBDAG4MAAAEAGAADQAECRITQakAvQAEaAwAAAIAJQBrDAAAAQAvAGoMAAABADQA6gwAAAEAPQAAAA==.',
Ra='Radley:BAAALgAECgQJAwABLgAECgkJNQAUAKkjAA==.Raelilah:BAABLgAECn8aAAIGAAgJVBbGFwBKAghoDAAABQA+AGkMAAAEAC0AawwAAAQAPgBqDAAAAwA9AGwMAAADADoAbQwAAAIAOQDqDAAABABRAG4MAAABAB8ABgAICVQWxhcASgIIaAwAAAUAPgBpDAAABAAtAGsMAAAEAD4AagwAAAMAPQBsDAAAAwA6AG0MAAACADkA6gwAAAQAUQBuDAAAAQAfAAAA.',
Re='Reptar:BAACLgAFFH8cAAIZAAYJShZqCQCBAQZoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIA6gwAAAYARgAZAAYJShZqCQCBAQZoDAAABwBBAGkMAAAGADcAawwAAAUAKwBqDAAAAwAlAGwMAAABADIA6gwAAAYARgAuAAQKfxgAAhkACAkHHA4bACwCABkACAkHHA4bACwCAAAA.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAAHAAAAAA==.Rheolin:BAAALgADCgEJAQAAAA==.Rheomoon:BAAALgAECgQJBgAAAA==.',
Ri='Ricki:BAAALgAECgMJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCAAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAAALgAECgYJEQAAAA==.',
Sa='Saelydera:BAAALgADCgYJCQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJBwAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJCwAAAA==.',
Si='Silverthorn:BAAALgAECgQJBgAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgUJBQAHAAAAAA==.',
Su='Suicidalone:BAAALgADCgcJEwAAAA==.',
Sy='Sylveon:BAAALgAFFAEJAQAAAA==.',
Ti='Tiamatt:BAAALgAECggJEAAAAA==.',
To='Tornheart:BAABLgAECn8lAAIBAAkJDBN6BQASAgloDAAABgAzAGkMAAAEAEIAawwAAAUAMwBqDAAAAwAaAGwMAAAEABQAbQwAAAQALgDqDAAABgAzAG4MAAAEAEEAbwwAAAEAIwABAAkJDBN6BQASAgloDAAABgAzAGkMAAAEAEIAawwAAAUAMwBqDAAAAwAaAGwMAAAEABQAbQwAAAQALgDqDAAABgAzAG4MAAAEAEEAbwwAAAEAIwAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgQJBwAAAA==.Tubbycoin:BAABLgAECn8fAAMaAAkJmx+0BAAGAgloDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAADAEUAbwwAAAEARQAaAAgJPSC0BAAGAghoDAAABQBaAGkMAAAFAFkAawwAAAUAWABqDAAABABPAGwMAAAEAEkAbQwAAAMAWwDqDAAAAQBJAG4MAAACAEUAGwACCd8aQC8AqAACbgwAAAEAQwBvDAAAAQBFAAAA.Tulkas:BAABLgAFFH8JAAIcAAMJoB0EBQASAQNoDAAABABTAGkMAAACAEQA6gwAAAMASwAcAAMJoB0EBQASAQNoDAAABABTAGkMAAACAEQA6gwAAAMASwAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAUAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgADCgUJBQABLgAECgYJDgAHAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wy='Wyburn:BAAALgAECgQJBQAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
['Yø']='Yøriçk:BAAALgAECgYJEQAAAA==.',
Za='Zane:BAAALgAECgYJBwAAAA==.Zaraelina:BAAALgAECgYJCQAAAA==.',
['Çl']='Çleadon:BAAALgAECgcJDQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
