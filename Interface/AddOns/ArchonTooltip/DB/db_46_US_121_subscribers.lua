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

local lookup = {'Priest-Shadow','Priest-Holy','Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Druid-Restoration','Hunter-BeastMastery','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Paladin-Protection','Rogue-Assassination','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warrior-Protection','Evoker-Preservation','Druid-Feral','Priest-Discipline','Monk-Mistweaver','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-12',data={As='Astaren:BAEBLgAECn8TAAMBAAkJOQkHMQBVAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABgAkAG4MAAABAAQAbwwAAAEAHgABAAkJOQkHMQBVAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABQAkAG4MAAABAAQAbwwAAAEAHgACAAEJ1hfEZgBDAAHqDAAAAQA9AAAA.',
Av='Avenmonk:BAECLgAFFH8gAAIDAAcJTRzyAwDvAQdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAMABwlNHPIDAO8BB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIDAAkJTyRfAQCiAwADAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAIEAAkJoBSbGQDIAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgAEAAkJoBSbGQDIAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAADAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8PAAIFAAYJ2Bf7EABrAQZoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AG0MAAABAA0A6gwAAAYAXwAFAAYJ2Bf7EABrAQZoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AG0MAAABAA0A6gwAAAYAXwAuAAQKfyAAAwUACQnbHqsGAMoCAAUACQnbHqsGAMoCAAYABwljERxxAKUBAAAA.Brylic:BAECLgAFFH8YAAMHAAUJZSMzCwDQAQVoDAAABwBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUABwAFCbMgMwsA0AEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAIAXADqDAAAAQAzAAMAAgmIIGAkALsAAmgMAAABAFAA6gwAAAIAVQAuAAQKfyYAAwMACAk5IyQGAB8DAAMACAkmISQGAB8DAAcACAmqIjIIAAIDAAEuAAUUBgkPAAUA2BcA.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJIQAIAIEhAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJOQAJAOYlAA==.',
Cm='Cmenstabber:BAECLgAFFH8LAAIEAAMJbAcHLADBAANoDAAAAwARAGkMAAACAAQA6gwAAAYAIwAEAAMJbAcHLADBAANoDAAAAwARAGkMAAACAAQA6gwAAAYAIwAuAAQKfy4AAgQACQn2FREQACcCAAQACQn2FREQACcCAAAA.',
Da='Dantius:BAEALgADCgcJBwABLgAFFAMJCgAKAE4VAA==.Darkorin:BAECLgAFFH8PAAILAAUJxyTVIAB6AQVoDAAABgBhAGkMAAACAGIAawwAAAIAVgBqDAAAAQA5AOoMAAAEAF8ACwAFCcck1SAAegEFaAwAAAYAYQBpDAAAAgBiAGsMAAACAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADCwAJCYklswYAZQMACwAICUsmswYAZQMADAACCcsOUogANgAAAAA=.',
Du='Duskorin:BAEBLgAFFH8KAAMNAAQJwhWdTAC3AARoDAAAAwAvAGwMAAABACQA6gwAAAUAMgBuDAAAAQBYAA0AAwmKEZ1MALcAA2gMAAADAC8AbAwAAAEAJADqDAAAAwAyAA4AAgnNDzs9AI8AAuoMAAACAD0AbgwAAAEAEwABLgAFFAUJDwALAMckAA==.',
Fi='Fishybrew:BAEBLgAECn8tAAIHAAgJYyKWCACmAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABwAICWMilggApgIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkKAA8AAAAA.',
Fl='Fleasfordays:BAEALgAECgIJAgABLgAFFAMJCwAEAGwHAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgcJGwAQAHgZAA==.Foxleaf:BAEALgAECgEJAQABLgAECgcJGwAQAHgZAA==.Foxorcism:BAEBLgAECn8XAAQMAAcJPBVoMwCCAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAwABgl5GGgzAIIBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAsAAwl9B5FDAWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJABEAAQn6AyxUACQAAW0MAAABAAoAAS4ABAoHCRsAEAB4GQA=.Foxox:BAEBLgAECn8bAAIQAAcJeBkdWwDLAQdoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAABABNAG0MAAACADMA6gwAAAMARQBuDAAAAgA2ABAABwl4GR1bAMsBB2gMAAAHAEoAaQwAAAUAQgBrDAAABAA+AGwMAAAEAE0AbQwAAAIAMwDqDAAAAwBFAG4MAAACADYAAAA=.',
Fr='Fries:BAEBLgAFFH8FAAMEAAMJmQnDMQCTAANoDAAAAQAyAOoMAAADABIAbgwAAAEABAAEAAIJeQ3DMQCTAAJoDAAAAQAyAOoMAAADABIAEgABCdgBRBIAQgABbgwAAAEABAABLgAFFAQJBwATAKYPAA==.Frip:BAEALgAECgIJAgABLgAECgkJOQAJAOYlAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAILAAkJVgkohgBfAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQALAAkJVgkohgBfAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gr='Grimmyb:BAECLgAFFH8LAAMUAAMJABoVXgDMAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQAUAAMJhhYVXgDMAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgAVAAEJWiHUDgBXAAHqDAAAAQBVAC4ABAp/JwADFQAJCZgh8gEA8QIAFQAICdsh8gEA8QIAFAAJCaEb7z4AyAEAAS4ABRQJCSEAFQCYHQA=.Grìmbles:BAECLgAFFH8hAAIVAAkJmB0SAAAoAgloDAAABgBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAbwwAAAEAGwAVAAkJmB0SAAAoAgloDAAABgBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAbwwAAAEAGwAuAAQKfx0AAhUACQmdJTgAAJcDABUACQmdJTgAAJcDAAAA.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwAWADYmAA==.Guthynn:BAEBLgAECn8vAAMWAAkJNiYoAAB3AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgAWAAkJNiYoAAB3AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgASAAUJPyGYCgCIAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Gw='Gwimbles:BAECLgAFFH8OAAIFAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAFAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgUACQmMHiYHAL4CAAUACQmMHiYHAL4CAAEuAAUUCQkhABUAmB0A.Gwìmbles:BAEBLgAFFH8IAAMXAAUJ2QWQNgBBAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAFwACCagLkDYAQQACaAwAAAIAOgDqDAAAAgABABgABAkKANdVAAQABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQJCSEAFQCYHQA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgANADwdAA==.Irrogenia:BAEBLgAECn8uAAMNAAkJPB1GEADKAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgANAAkJPB1GEADKAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAOAAIJ/QqPiQBXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgANADwdAA==.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJOQAJAOYlAA==.',
La='Larias:BAECLgAFFH8OAAIZAAUJTx0LBgCeAQVoDAAABQBgAGkMAAAEAGEAawwAAAEAFgBsDAAAAQBcAOoMAAADAEIAGQAFCU8dCwYAngEFaAwAAAUAYABpDAAABABhAGsMAAABABYAbAwAAAEAXADqDAAAAwBCAC4ABAp/IgACGQAICZUmTwIAjQMAGQAICZUmTwIAjQMAAS4ABRQFCQsAGgALHQA=.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAbAP8PAA==.Lidathra:BAECLgAFFH8LAAIbAAQJ/w9lGgDlAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABsABAn/D2UaAOUABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIbAAkJ5hU0CwAkAgAbAAkJ5hU0CwAkAgAAAA==.Lidiosa:BAEBLgAECn8nAAIQAAkJdhotJACKAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgAQAAkJdhotJACKAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAbAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAbAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAbAP8PAA==.',
Lo='Lochru:BAEBLgAECn9PAAIcAAkJ4yMlAQBFAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAcAAkJ4yMlAQBFAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIaAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABoABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJDwALAMckAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJOQAJAOYlAA==.',
Ne='Neodefender:BAECLgAFFH8qAAIMAAcJ7iR2AgDPAgdoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4AbQwAAAEASwDqDAAABwBhAAwABwnuJHYCAM8CB2gMAAAKAGMAaQwAAAkAXgBrDAAABwBjAGoMAAAFAGMAbAwAAAMAXgBtDAAAAQBLAOoMAAAHAGEALgAECn8yAAIMAAkJ5yb8AACIAwAMAAkJ5yb8AACIAwAAAA==.',
No='Nosferratu:BAECLgAFFH8lAAMBAAcJvh85AQApAgdoDAAACQBjAGkMAAAGAF4AawwAAAYAWwBqDAAABQAcAGwMAAACAD0A6gwAAAgAYwBuDAAAAQAoAAEABwm+HzkBACkCB2gMAAAJAGMAaQwAAAUAXgBrDAAABQBbAGoMAAAFABwAbAwAAAIAPQDqDAAACABjAG4MAAABACgAHQACCTgHZTwAfgACaQwAAAEADwBrDAAAAQAVAC4ABAp/QQACAQAJCYQmyQAAfgMAAQAJCYQmyQAAfgMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8lAAIHAAUJwhyMGABXAQVoDAAACgBMAGkMAAAJAD0AawwAAAYARQBqDAAABABJAOoMAAAIAFYABwAFCcIcjBgAVwEFaAwAAAoATABpDAAACQA9AGsMAAAGAEUAagwAAAQASQDqDAAACABWAC4ABAp/LAACBwAJCQ4k+gEARAMABwAJCQ4k+gEARAMAAAA=.',
Ol='Oldstandard:BAEALgAECgMJAwABLgAFFAUJCwAaAAsdAA==.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAkJIQAVAJgdAA==.',
Or='Orsp:BAECLgAFFH8mAAQBAAcJgRgMCQDMAQdoDAAACQBiAGkMAAAHAFEAawwAAAYATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACQBaAAEABgk8HQwJAMwBBmgMAAAJAGIAaQwAAAcAUQBrDAAABgBMAGoMAAACAEcAbQwAAAEAGwDqDAAACQBaAB0AAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQACAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KgAEAQAJCTcjOwUAPQMAAQAJCTcjOwUAPQMAAgADCcoKCGUAmQAAHQADCcEZ30YAhgAAAAA=.Orspp:BAECLgAFFH8KAAMBAAQJCRP7IQDaAARoDAAAAwBAAGkMAAADADsAawwAAAEANADqDAAAAwARAAEAAwkJF/shANoAA2gMAAADAEAAaQwAAAMAOwBrDAAAAQA0AB0AAQkJFatHAEAAAeoMAAADADUALgAECn8cAAQBAAgJKBpuIQDMAQABAAgJKBpuIQDMAQACAAYJpQgiSQAUAQAdAAEJtQ3DVQA2AAABLgAFFAcJJgABAIEYAA==.',
Pa='Pakk:BAEBLgAECn81AAIFAAgJOSGCCACKAghoDAAACgBeAGkMAAAJAFoAawwAAAgAUgBqDAAABwBXAGwMAAAHAFQAbQwAAAEAPwDqDAAABwBdAG4MAAAEAFYABQAICTkhgggAigIIaAwAAAoAXgBpDAAACQBaAGsMAAAIAFIAagwAAAcAVwBsDAAABwBUAG0MAAABAD8A6gwAAAcAXQBuDAAABABWAAAA.Pandoken:BAEBLgAFFH8RAAMeAAYJUh3aEAD2AQZoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAAeAAYJUh3aEAD2AQZoDAAAAwBNAGkMAAADAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAADAAIJSRlBKgCdAAJoDAAAAQAvAGkMAAABAFIAAS4ABRQJCSEACACBIQA=.Pandotides:BAEALgAFFAUJAgABLgAFFAkJIQAIAIEhAA==.Papadefensve:BAEALgAECgYJCgAAAA==.',
Pr='Priff:BAEBLgAECn85AAQJAAkJ5iXAAwBSAwloDAAACABiAGkMAAAIAGEAawwAAAgAXQBqDAAABgBgAGwMAAAHAFsAbQwAAAYAYwDqDAAACABgAG4MAAAEAGMAbwwAAAIAYgAJAAkJ2iXAAwBSAwloDAAAAwBhAGkMAAAFAGEAawwAAAQAXQBqDAAAAwBgAGwMAAABAFsAbQwAAAUAYwDqDAAAAwBgAG4MAAAEAGMAbwwAAAIAYgAfAAcJ9yFfGABqAgdoDAAAAwBTAGkMAAADAFwAawwAAAMASgBqDAAAAgAoAGwMAAAEAFQAbQwAAAEAXwDqDAAAAwBaACAABQnlIRwnAGUBBWgMAAACAGIAawwAAAEASgBqDAAAAQBTAGwMAAACAFQA6gwAAAIAWQAAAA==.Priffraff:BAEALgAECggJEwABLgAECgkJOQAJAOYlAA==.',
Ra='Razamon:BAEBLgAECn8rAAMNAAkJMSFLGgB0AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAANAAkJMSFLGgB0AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAOAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJOAATAIgcAA==.Relsham:BAEALgAECgkJAgABLgAFFAQJCAAQAFIHAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAYJDwAFANgXAA==.',
Ro='Roukedhh:BAECLgAFFH8WAAIUAAcJxxx0FwDoAQdoDAAABQBSAGkMAAAEAEoAawwAAAMARQBqDAAAAQADAG0MAAABAD8A6gwAAAcAUQBuDAAAAQBHABQABwnHHHQXAOgBB2gMAAAFAFIAaQwAAAQASgBrDAAAAwBFAGoMAAABAAMAbQwAAAEAPwDqDAAABwBRAG4MAAABAEcALgAECn8eAAIUAAgJpyGQFgDPAgAUAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAEBLgAECn8WAAMGAAYJHx2OigBLAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAGAAYJHx2OigBLAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgAFAAYJggr/OQCnAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAGAB8dAA==.',
Sa='Sargala:BAEBLgAECn8sAAMJAAgJJhqOLwAZAghoDAAACQBLAGkMAAAIAEkAawwAAAoANwBqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABgBWAG4MAAABAEcACQAICSYaji8AGQIIaAwAAAgASwBpDAAABwBJAGsMAAAJADcAagwAAAQASgBsDAAABABSAG0MAAABABcA6gwAAAYAVgBuDAAAAQBHACAABAnnBS1JAJAABGgMAAABABMAaQwAAAEAEgBrDAAAAQAHAGoMAAABABMAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAPAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAPAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAPAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAPAAAAAA==.',
Sm='Smitehaven:BAEALgAECgIJAgABLgAECgYJFgAGAB8dAA==.Smoothdk:BAEALgAFFAIJAgABLgAFFAUJBQAXABEFAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAUJBQAXABEFAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAUJBQAXABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJJwAaAAgdAA==.Thezdin:BAEBLgAECn8nAAIaAAkJCB0jCwA3AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAaAAkJCB0jCwA3AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJJwAaAAgdAA==.',
Ve='Velohm:BAEBLgAECn8bAAMeAAYJ6CG6GQBDAgZoDAAACABXAGkMAAAFAFAAawwAAAQAXABqDAAABABXAGwMAAACAFIA6gwAAAQAWgAeAAYJ6CG6GQBDAgZoDAAABgBXAGkMAAADAFAAawwAAAIAXABqDAAAAgBXAGwMAAACAFIA6gwAAAMAWgADAAUJSAjGXwCWAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAgJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAgJAQAPAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIHAAcJXx7HBABDAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAcABwlfHscEAEMCB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIHAAgJVyYLBQDuAgAHAAgJVyYLBQDuAgAAAA==.Zogle:BAEBLgAFFH8JAAIFAAUJGRNeIADgAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEABQAFCRkTXiAA4AAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAcAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAHAF8eAA==.',
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
