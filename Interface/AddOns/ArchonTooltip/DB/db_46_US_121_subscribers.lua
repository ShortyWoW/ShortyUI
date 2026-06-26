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

local lookup = {'Priest-Shadow','Priest-Holy','Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Druid-Restoration','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','Rogue-Outlaw','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','Evoker-Preservation','Druid-Feral','Priest-Discipline','Monk-Mistweaver','Hunter-Marksmanship','Hunter-Survival','Warlock-Demonology','DemonHunter-Devourer','Druid-Guardian',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-25',data={As='Astaren:BAEBLgAECn8TAAMBAAkJOQkmMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABgAkAG4MAAABAAQAbwwAAAEAHgABAAkJOQkmMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABQAkAG4MAAABAAQAbwwAAAEAHgACAAEJ1hfXaABDAAHqDAAAAQA9AAAA.',
Av='Avenmonk:BAECLgAFFH8gAAIDAAcJTRxXBADsAQdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAMABwlNHFcEAOwBB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIDAAkJTyRfAQCiAwADAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAIEAAkJoBQ+GgDGAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgAEAAkJoBQ+GgDGAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAADAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8RAAIFAAcJjReGDAC1AQdoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABQA5AGwMAAABADgAbQwAAAEADQDqDAAABgBfAAUABwmNF4YMALUBB2gMAAACAFgAaQwAAAEAJgBrDAAAAQBEAGoMAAAFADkAbAwAAAEAOABtDAAAAQANAOoMAAAGAF8ALgAECn8gAAMFAAkJ2x6rBgDKAgAFAAkJ2x6rBgDKAgAGAAcJYxEccQClAQAAAA==.Brylic:BAECLgAFFH8ZAAMHAAYJPyB5DADOAQZoDAAABwBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUAbgwAAAEAKgAHAAYJAB55DADOAQZoDAAABgBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAABADMAbgwAAAEAKgADAAIJiCBGJgC6AAJoDAAAAQBQAOoMAAACAFUALgAECn8mAAMDAAgJOSMkBgAfAwADAAgJJiEkBgAfAwAHAAgJqiIyCAACAwABLgAFFAcJEQAFAI0XAA==.Brylicet:BAEALgAFFAQJBAABLgAFFAcJEQAFAI0XAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJLwAIADMiAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJQQAJAOYlAA==.',
Ch='Chataya:BAEALgAECgEJAgABLgAECgkJLgAKADwdAA==.',
Da='Dantius:BAEALgAECgcJBwABLgAFFAMJDQALAOQWAA==.Darkorin:BAECLgAFFH8TAAIMAAUJ7yQTIQCCAQVoDAAABwBiAGkMAAADAGIAawwAAAMAVgBqDAAAAQA5AOoMAAAFAF8ADAAFCe8kEyEAggEFaAwAAAcAYgBpDAAAAwBiAGsMAAADAFYAagwAAAEAOQDqDAAABQBfAC4ABAp/LQADDAAJCYklswYAZQMADAAICUsmswYAZQMADQACCcsOhooANgAAAAA=.',
Du='Duskorin:BAEBLgAFFH8MAAMKAAUJ5BieTwC3AAVoDAAAAwAvAGwMAAABACQAbQwAAAEAXwDqDAAABgAyAG4MAAABAFgACgADCYoRnk8AtwADaAwAAAMALwBsDAAAAQAkAOoMAAADADIADgADCUMVWBIAZwADbQwAAAEAUgDqDAAAAwA9AG4MAAABABMAAS4ABRQFCRMADADvJAA=.',
Fi='Fishybrew:BAEBLgAECn8tAAIHAAgJYyLMCACmAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABwAICWMizAgApgIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkOAA8AAAAA.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgkJHQAQANYYAA==.Foxdemon:BAEALgAECgUJBQABLgAECgkJHQAQANYYAA==.Foxleaf:BAEALgAECgEJAQABLgAECgkJHQAQANYYAA==.Foxorcism:BAEBLgAECn8cAAQNAAcJXxapAQCgAQdoDAAABQBUAGkMAAAFADsAawwAAAUAUwBqDAAABQA3AGwMAAACAB0AbQwAAAEABADqDAAABQBTAA0ABgnNGakBAKABBmgMAAAEAFQAaQwAAAQAOwBrDAAABABTAGoMAAAFADcAbAwAAAIAHQDqDAAABQBTAAwAAwl9BzFKAWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJABEAAQn6A+1VACQAAW0MAAABAAoAAS4ABAoJCR0AEADWGAA=.Foxox:BAEBLgAECn8dAAIQAAkJ1hhFXgDEAQloDAAABwBKAGkMAAAFAEIAawwAAAQAPgBqDAAAAQBDAGwMAAAEAE0AbQwAAAIAMwDqDAAAAwBFAG4MAAACADYAbwwAAAEANAAQAAkJ1hhFXgDEAQloDAAABwBKAGkMAAAFAEIAawwAAAQAPgBqDAAAAQBDAGwMAAAEAE0AbQwAAAIAMwDqDAAAAwBFAG4MAAACADYAbwwAAAEANAAAAA==.',
Fr='Fries:BAEBLgAFFH8FAAMEAAMJmQmjMwCTAANoDAAAAQAyAOoMAAADABIAbgwAAAEABAAEAAIJeQ2jMwCTAAJoDAAAAQAyAOoMAAADABIAEgABCdgBiBIAQgABbgwAAAEABAABLgAFFAUJCwATAE0fAA==.Frip:BAEALgAECgIJAgABLgAECgkJQQAJAOYlAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIMAAkJVgk8igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAMAAkJVgk8igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwAUADYmAA==.Guthynn:BAEBLgAECn8vAAMUAAkJNiYtAAB2AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgAUAAkJNiYtAAB2AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgASAAUJPyHBCgCIAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgAKADwdAA==.Irrofel:BAEALgAECgQJBAABLgAECgkJLgAKADwdAA==.Irrogenia:BAEBLgAECn8uAAMKAAkJPB3LEADJAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAKAAkJPB3LEADJAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAOAAIJ/QrxjABXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgAKADwdAA==.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJQQAJAOYlAA==.',
La='Larias:BAECLgAFFH8OAAIVAAUJTx0LBgCeAQVoDAAABQBgAGkMAAAEAGEAawwAAAEAFgBsDAAAAQBcAOoMAAADAEIAFQAFCU8dCwYAngEFaAwAAAUAYABpDAAABABhAGsMAAABABYAbAwAAAEAXADqDAAAAwBCAC4ABAp/IgACFQAICZUmTwIAjQMAFQAICZUmTwIAjQMAAS4ABRQJCRoAFgBmGgA=.Lariàs:BAEBLgAFFH8aAAMWAAkJZhqQAACTAgloDAAABQBVAGkMAAAEAFMAawwAAAQAOABqDAAAAQA8AGwMAAACADoAbQwAAAEARQDqDAAABgBXAG4MAAABACcAbwwAAAIAPQAWAAkJZhqQAACTAgloDAAABABVAGkMAAAEAFMAawwAAAQAOABqDAAAAQA8AGwMAAACADoAbQwAAAEARQDqDAAABgBXAG4MAAABACcAbwwAAAIAPQAXAAEJIQC1WwANAAFoDAAAAQAAAAEuAAUUCQkaABYAZhoA.Lariås:BAEBLgAFFH8VAAIHAAgJOxXFBwATAghoDAAAAwBRAGkMAAADAGEAawwAAAMAWABqDAAAAQANAGwMAAABAAYAbQwAAAIABgDqDAAABgBIAG4MAAACABwABwAICTsVxQcAEwIIaAwAAAMAUQBpDAAAAwBhAGsMAAADAFgAagwAAAEADQBsDAAAAQAGAG0MAAACAAYA6gwAAAYASABuDAAAAgAcAAEuAAUUCQkaABYAZhoA.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAYAP8PAA==.Lidathra:BAECLgAFFH8LAAIYAAQJ/w8hGwDkAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABgABAn/DyEbAOQABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIYAAkJ5hViCwAlAgAYAAkJ5hViCwAlAgAAAA==.Lidiosa:BAEBLgAECn8nAAIQAAkJdhr7JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgAQAAkJdhr7JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAYAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAYAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAYAP8PAA==.',
Lo='Lochru:BAEBLgAECn9PAAIZAAkJ4yMzAQBDAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAZAAkJ4yMzAQBDAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIWAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABYABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJEwAMAO8kAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJQQAJAOYlAA==.',
Ne='Neodefender:BAECLgAFFH8qAAINAAcJ7iTsAgDLAgdoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4AbQwAAAEASwDqDAAABwBhAA0ABwnuJOwCAMsCB2gMAAAKAGMAaQwAAAkAXgBrDAAABwBjAGoMAAAFAGMAbAwAAAMAXgBtDAAAAQBLAOoMAAAHAGEALgAECn8yAAINAAkJ5yb8AACIAwANAAkJ5yb8AACIAwAAAA==.',
No='Nosferratu:BAECLgAFFH8wAAMBAAgJyByHAQC2AghoDAAACwBjAGkMAAAIAF4AawwAAAgAWwBqDAAABgA6AGwMAAADAD4A6gwAAAoAYwBuDAAAAQAoAG8MAAABABoAAQAICcgchwEAtgIIaAwAAAsAYwBpDAAABwBeAGsMAAAHAFsAagwAAAYAOgBsDAAAAwA+AOoMAAAKAGMAbgwAAAEAKABvDAAAAQAaABoAAgk4BwA/AH0AAmkMAAABAA8AawwAAAEAFQAuAAQKf0EAAgEACQmEJtwAAHoDAAEACQmEJtwAAHoDAAAA.',
Ny='Nyfaria:BAECLgAFFH8mAAIHAAUJwhwAGgBUAQVoDAAACgBMAGkMAAAJAD0AawwAAAYARQBqDAAABABJAOoMAAAJAFYABwAFCcIcABoAVAEFaAwAAAoATABpDAAACQA9AGsMAAAGAEUAagwAAAQASQDqDAAACQBWAC4ABAp/MgACBwAJCYMkDQIAQwMABwAJCYMkDQIAQwMAAAA=.',
Ol='Oldstandard:BAEALgAECgMJAwABLgAFFAkJGgAWAGYaAA==.',
Or='Orsp:BAECLgAFFH8tAAQBAAgJMhY1AQATAghoDAAACgBiAGkMAAAIAFEAawwAAAcATABqDAAABQBHAGwMAAACAAIAbQwAAAIAKQDqDAAACgBcAG8MAAABAAQAAQAHCcEZNQEAEwIHaAwAAAoAYgBpDAAACABRAGsMAAAHAEwAagwAAAMARwBtDAAAAgApAOoMAAAKAFwAbwwAAAEABAAaAAIJPAE+FgB+AAJqDAAAAQAAAGwMAAACAAUAAgABCUYB7hQAQQABagwAAAEAAwAuAAQKfyoABAEACQk3IzsFAD0DAAEACQk3IzsFAD0DAAIAAwnKCghlAJkAABoAAwnBGSpnAGEAAAAA.Orspp:BAECLgAFFH8QAAMBAAQJzRYXGQAfAQRoDAAABQBQAGkMAAAFADsAawwAAAEANADqDAAABQAoAAEABAnNFhcZAB8BBGgMAAAFAFAAaQwAAAUAOwBrDAAAAQA0AOoMAAABACgAGgABCQkVEksAPwAB6gwAAAQANQAuAAQKfxwABAEACAkoGm4hAMwBAAEACAkoGm4hAMwBAAIABgmlCCJJABQBABoAAQm1DcNVADYAAAEuAAUUCAktAAEAMhYA.',
Pa='Pakk:BAEBLgAECn9EAAIFAAkJqyCoAABXAgloDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAGAFYAbwwAAAEASQAFAAkJqyCoAABXAgloDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAGAFYAbwwAAAEASQAAAA==.Pandoken:BAEBLgAFFH8WAAMbAAgJfxtdDABCAghoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAQAQwBuDAAAAQA/AG8MAAACAC4AGwAICX8bXQwAQgIIaAwAAAMATQBpDAAAAwBRAGsMAAAEAFIAagwAAAIARABsDAAAAQBMAOoMAAAEAEMAbgwAAAEAPwBvDAAAAgAuAAMAAglJGRosAJ0AAmgMAAABAC8AaQwAAAEAUgABLgAFFAkJLwAIADMiAA==.Pandotides:BAEALgAFFAUJAgABLgAFFAkJLwAIADMiAA==.Papadefensve:BAEALgAECgYJDgAAAA==.',
Pr='Priff:BAEBLgAECn9BAAQJAAkJ5iUSBABQAwloDAAACQBiAGkMAAAJAGEAawwAAAkAXQBqDAAABwBgAGwMAAAIAFsAbQwAAAcAYwDqDAAACgBgAG4MAAAEAGMAbwwAAAIAYgAJAAkJ2iUSBABQAwloDAAABABhAGkMAAAGAGEAawwAAAUAXQBqDAAABABgAGwMAAACAFsAbQwAAAYAYwDqDAAABABgAG4MAAAEAGMAbwwAAAIAYgAcAAcJ9yFfGABqAgdoDAAAAwBTAGkMAAADAFwAawwAAAMASgBqDAAAAgAoAGwMAAAEAFQAbQwAAAEAXwDqDAAAAwBaAB0ABQnlIUAnAGQBBWgMAAACAGIAawwAAAEASgBqDAAAAQBTAGwMAAACAFQA6gwAAAMAWQAAAA==.Priffraff:BAEALgAECggJEwABLgAECgkJQQAJAOYlAA==.',
Ra='Razamon:BAEBLgAECn8rAAMKAAkJMSH5GgBzAgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAKAAkJMSH5GgBzAgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAOAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJQAAeAG8fAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAcJEQAFAI0XAA==.',
Ro='Roukedhh:BAECLgAFFH8WAAIfAAcJxxzyGQDjAQdoDAAABQBSAGkMAAAEAEoAawwAAAMARQBqDAAAAQADAG0MAAABAD8A6gwAAAcAUQBuDAAAAQBHAB8ABwnHHPIZAOMBB2gMAAAFAFIAaQwAAAQASgBrDAAAAwBFAGoMAAABAAMAbQwAAAEAPwDqDAAABwBRAG4MAAABAEcALgAECn8eAAIfAAgJpyGQFgDPAgAfAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAEBLgAECn8WAAMGAAYJHx3PjABLAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAGAAYJHx3PjABLAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgAFAAYJggpnOwCkAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAGAB8dAA==.',
Sa='Sargala:BAEBLgAECn8yAAMJAAkJ0RrLKgAyAgloDAAACgBQAGkMAAAJAEkAawwAAAsAOABqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABwBWAG4MAAACAEcAbwwAAAEASgAJAAkJ0RrLKgAyAgloDAAACQBQAGkMAAAIAEkAawwAAAoAOABqDAAABABKAGwMAAAEAFIAbQwAAAEAFwDqDAAABwBWAG4MAAACAEcAbwwAAAEASgAdAAQJ5wW5SgCMAARoDAAAAQATAGkMAAABABIAawwAAAEABwBqDAAAAQATAAAA.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAPAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAPAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAPAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAPAAAAAA==.',
Sm='Smitehaven:BAEALgAFFAIJAgABLgAECgYJFgAGAB8dAA==.Smoothdk:BAEALgAFFAIJAgABLgAFFAUJBQAgABEFAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAUJBQAgABEFAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAUJBQAgABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJKAAWAFMdAA==.Thezdin:BAEBLgAECn8oAAIWAAkJUx35CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAWAAkJUx35CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJKAAWAFMdAA==.',
Ve='Velohm:BAEBLgAECn8gAAMbAAYJfSIpAgDDAQZoDAAACQBXAGkMAAAGAFMAawwAAAUAXABqDAAABQBXAGwMAAADAFkA6gwAAAQAWgAbAAYJfSIpAgDDAQZoDAAABwBXAGkMAAAEAFMAawwAAAMAXABqDAAAAwBXAGwMAAADAFkA6gwAAAMAWgADAAUJSAhYYgCUAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAgJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAgJAQAPAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIHAAcJXx5+BQBAAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAcABwlfHn4FAEACB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIHAAgJVyY5BQDuAgAHAAgJVyY5BQDuAgAAAA==.Zogle:BAEBLgAFFH8JAAIFAAUJGRNgIgDYAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEABQAFCRkTYCIA2AAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAcAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAHAF8eAA==.',
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
