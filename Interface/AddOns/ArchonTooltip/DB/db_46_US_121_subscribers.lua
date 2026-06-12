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

local lookup = {'Priest-Shadow','Priest-Holy','Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Paladin-Protection','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warrior-Protection','Evoker-Preservation','Druid-Feral','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-11',data={As='Astaren:BAEBLgAECn8TAAMBAAkJOQnGMABVAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABgAkAG4MAAABAAQAbwwAAAEAHgABAAkJOQnGMABVAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABQAkAG4MAAABAAQAbwwAAAEAHgACAAEJ1hdaZgBDAAHqDAAAAQA9AAAA.',
Av='Avenmonk:BAECLgAFFH8gAAIDAAcJTRytAwD3AQdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAMABwlNHK0DAPcBB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIDAAkJTyRfAQCiAwADAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAIEAAkJoBRpGQDIAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgAEAAkJoBRpGQDIAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAADAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8PAAIFAAYJ2BeAEABsAQZoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AG0MAAABAA0A6gwAAAYAXwAFAAYJ2BeAEABsAQZoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AG0MAAABAA0A6gwAAAYAXwAuAAQKfyAAAwUACQnbHqsGAMoCAAUACQnbHqsGAMoCAAYABwljERxxAKUBAAAA.Brylic:BAECLgAFFH8YAAMHAAUJZSPQCgDRAQVoDAAABwBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUABwAFCbMg0AoA0QEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAIAXADqDAAAAQAzAAMAAgmIIF4kALwAAmgMAAABAFAA6gwAAAIAVQAuAAQKfyYAAwMACAk5IyQGAB8DAAMACAkmISQGAB8DAAcACAmqIjIIAAIDAAEuAAUUBgkPAAUA2BcA.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAgJEQAIAFIdAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJOQAJAOYlAA==.',
Cm='Cmenstabber:BAECLgAFFH8LAAIEAAMJbAeVKwDCAANoDAAAAwARAGkMAAACAAQA6gwAAAYAIwAEAAMJbAeVKwDCAANoDAAAAwARAGkMAAACAAQA6gwAAAYAIwAuAAQKfy4AAgQACQn2FfAPACgCAAQACQn2FfAPACgCAAAA.',
Da='Darkorin:BAECLgAFFH8PAAIKAAUJxyTEHwB8AQVoDAAABgBhAGkMAAACAGIAawwAAAIAVgBqDAAAAQA5AOoMAAAEAF8ACgAFCcckxB8AfAEFaAwAAAYAYQBpDAAAAgBiAGsMAAACAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADCgAJCYklswYAZQMACgAICUsmswYAZQMACwACCcsO4YcANgAAAAA=.',
Du='Duskorin:BAEBLgAFFH8KAAMMAAQJwhWoSwC3AARoDAAAAwAvAGwMAAABACQA6gwAAAUAMgBuDAAAAQBYAAwAAwmKEahLALcAA2gMAAADAC8AbAwAAAEAJADqDAAAAwAyAA0AAgnND1w8AI8AAuoMAAACAD0AbgwAAAEAEwABLgAFFAUJDwAKAMckAA==.',
Fi='Fishybrew:BAEBLgAECn8tAAIHAAgJYyKICACnAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABwAICWMiiAgApwIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkKAA4AAAAA.',
Fl='Fleasfordays:BAEALgAECgIJAgABLgAFFAMJCwAEAGwHAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgcJGwAPAHgZAA==.Foxleaf:BAEALgAECgEJAQABLgAECgcJGwAPAHgZAA==.Foxorcism:BAEBLgAECn8XAAQLAAcJPBUsMwCCAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAsABgl5GCwzAIIBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAoAAwl9BzFCAWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJABAAAQn6A7RTACQAAW0MAAABAAoAAS4ABAoHCRsADwB4GQA=.Foxox:BAEBLgAECn8bAAIPAAcJeBmXWgDLAQdoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAABABNAG0MAAACADMA6gwAAAMARQBuDAAAAgA2AA8ABwl4GZdaAMsBB2gMAAAHAEoAaQwAAAUAQgBrDAAABAA+AGwMAAAEAE0AbQwAAAIAMwDqDAAAAwBFAG4MAAACADYAAAA=.',
Fr='Fries:BAEALgAFFAMJBAABLgAFFAQJBwARAKYPAA==.Frip:BAEALgAECgIJAgABLgAECgkJOQAJAOYlAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIKAAkJVgmMhQBfAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAKAAkJVgmMhQBfAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gr='Grimmyb:BAECLgAFFH8LAAMSAAMJABqXXADRAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQASAAMJhhaXXADRAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgATAAEJWiGaDgBYAAHqDAAAAQBVAC4ABAp/JwADEwAJCZgh8gEA8QIAEwAICdsh8gEA8QIAEgAJCaEbqz4AyAEAAS4ABRQJCSEAEwCYHQA=.Grìmbles:BAECLgAFFH8hAAITAAkJmB0SAAAoAgloDAAABgBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAbwwAAAEAGwATAAkJmB0SAAAoAgloDAAABgBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAbwwAAAEAGwAuAAQKfx0AAhMACQmdJTgAAJcDABMACQmdJTgAAJcDAAAA.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwAUADYmAA==.Guthynn:BAEBLgAECn8vAAMUAAkJNiYnAAB3AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgAUAAkJNiYnAAB3AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgAVAAUJPyGLCgCIAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Gw='Gwimbles:BAECLgAFFH8OAAIFAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAFAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgUACQmMHiYHAL4CAAUACQmMHiYHAL4CAAEuAAUUCQkhABMAmB0A.Gwìmbles:BAEBLgAFFH8IAAMWAAUJ2QV/NQBBAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAFgACCagLfzUAQQACaAwAAAIAOgDqDAAAAgABABcABAkKAPNUAAQABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQJCSEAEwCYHQA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgAMADwdAA==.Irrogenia:BAEBLgAECn8uAAMMAAkJPB0jEADKAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAMAAkJPB0jEADKAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgANAAIJ/QrSiABXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgAMADwdAA==.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJOQAJAOYlAA==.',
La='Larias:BAECLgAFFH8OAAIYAAUJTx0LBgCeAQVoDAAABQBgAGkMAAAEAGEAawwAAAEAFgBsDAAAAQBcAOoMAAADAEIAGAAFCU8dCwYAngEFaAwAAAUAYABpDAAABABhAGsMAAABABYAbAwAAAEAXADqDAAAAwBCAC4ABAp/IgACGAAICZUmTwIAjQMAGAAICZUmTwIAjQMAAS4ABRQECQoAGQBPHgA=.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAaAP8PAA==.Lidathra:BAECLgAFFH8LAAIaAAQJ/w8qGgDkAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABoABAn/DyoaAOQABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIaAAkJ5hUrCwAkAgAaAAkJ5hUrCwAkAgAAAA==.Lidiosa:BAEBLgAECn8nAAIPAAkJdhriIwCLAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgAPAAkJdhriIwCLAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAaAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAaAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAaAP8PAA==.',
Lo='Lochru:BAEBLgAECn9PAAIbAAkJ4yMkAQBGAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAbAAkJ4yMkAQBGAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIZAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABkABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJDwAKAMckAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJOQAJAOYlAA==.',
Ne='Neodefender:BAECLgAFFH8pAAILAAYJKCbsBAB2AgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQALAAYJKCbsBAB2AgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAuAAQKfzIAAgsACQnnJvwAAIgDAAsACQnnJvwAAIgDAAAA.',
No='Nosferratu:BAECLgAFFH8lAAMBAAcJvh85AQApAgdoDAAACQBjAGkMAAAGAF4AawwAAAYAWwBqDAAABQAcAGwMAAACAD0A6gwAAAgAYwBuDAAAAQAoAAEABwm+HzkBACkCB2gMAAAJAGMAaQwAAAUAXgBrDAAABQBbAGoMAAAFABwAbAwAAAIAPQDqDAAACABjAG4MAAABACgAHAACCTgHuDsAfgACaQwAAAEADwBrDAAAAQAVAC4ABAp/QQACAQAJCYQmxgAAfgMAAQAJCYQmxgAAfgMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8kAAIHAAUJwhwlGABYAQVoDAAACgBMAGkMAAAJAD0AawwAAAUARQBqDAAABABJAOoMAAAIAFYABwAFCcIcJRgAWAEFaAwAAAoATABpDAAACQA9AGsMAAAFAEUAagwAAAQASQDqDAAACABWAC4ABAp/LAACBwAJCQ4k8AEARAMABwAJCQ4k8AEARAMAAAA=.',
Ol='Oldstandard:BAEALgAECgMJAwABLgAFFAQJCgAZAE8eAA==.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAkJIQATAJgdAA==.',
Or='Orsp:BAECLgAFFH8mAAQBAAcJgRi8CADOAQdoDAAACQBiAGkMAAAHAFEAawwAAAYATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACQBaAAEABgk8HbwIAM4BBmgMAAAJAGIAaQwAAAcAUQBrDAAABgBMAGoMAAACAEcAbQwAAAEAGwDqDAAACQBaABwAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQACAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KgAEAQAJCTcjOwUAPQMAAQAJCTcjOwUAPQMAAgADCcoKCGUAmQAAHAADCcEZ30YAhgAAAAA=.Orspp:BAECLgAFFH8KAAMBAAQJCROaIQDaAARoDAAAAwBAAGkMAAADADsAawwAAAEANADqDAAAAwARAAEAAwkJF5ohANoAA2gMAAADAEAAaQwAAAMAOwBrDAAAAQA0ABwAAQkJFeNGAEAAAeoMAAADADUALgAECn8cAAQBAAgJKBpuIQDMAQABAAgJKBpuIQDMAQACAAYJpQgiSQAUAQAcAAEJtQ3DVQA2AAABLgAFFAcJJgABAIEYAA==.',
Pa='Pakk:BAEBLgAECn81AAIFAAgJOSFxCACKAghoDAAACgBeAGkMAAAJAFoAawwAAAgAUgBqDAAABwBXAGwMAAAHAFQAbQwAAAEAPwDqDAAABwBdAG4MAAAEAFYABQAICTkhcQgAigIIaAwAAAoAXgBpDAAACQBaAGsMAAAIAFIAagwAAAcAVwBsDAAABwBUAG0MAAABAD8A6gwAAAcAXQBuDAAABABWAAAA.Pandoken:BAEBLgAFFH8RAAMIAAYJUh1UEAD3AQZoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAAIAAYJUh1UEAD3AQZoDAAAAwBNAGkMAAADAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAADAAIJSRkHKgCdAAJoDAAAAQAvAGkMAAABAFIAAAA=.Pandotides:BAEALgAFFAUJAgABLgAFFAgJEQAIAFIdAA==.Papadefensve:BAEALgAECgYJCgAAAA==.',
Pr='Priff:BAEBLgAECn85AAQJAAkJ5iWkAwBTAwloDAAACABiAGkMAAAIAGEAawwAAAgAXQBqDAAABgBgAGwMAAAHAFsAbQwAAAYAYwDqDAAACABgAG4MAAAEAGMAbwwAAAIAYgAJAAkJ2iWkAwBTAwloDAAAAwBhAGkMAAAFAGEAawwAAAQAXQBqDAAAAwBgAGwMAAABAFsAbQwAAAUAYwDqDAAAAwBgAG4MAAAEAGMAbwwAAAIAYgAdAAcJ9yFfGABqAgdoDAAAAwBTAGkMAAADAFwAawwAAAMASgBqDAAAAgAoAGwMAAAEAFQAbQwAAAEAXwDqDAAAAwBaAB4ABQnlIRMnAGYBBWgMAAACAGIAawwAAAEASgBqDAAAAQBTAGwMAAACAFQA6gwAAAIAWQAAAA==.Priffraff:BAEALgAECggJEwABLgAECgkJOQAJAOYlAA==.',
Ra='Razamon:BAEBLgAECn8rAAMMAAkJMSERGgB0AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAMAAkJMSERGgB0AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAANAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJOAARAIgcAA==.Relsham:BAEALgAECgkJAgABLgAFFAQJCAAPAFIHAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAYJDwAFANgXAA==.',
Ro='Roukedhh:BAECLgAFFH8VAAISAAcJeRuhGQDTAQdoDAAABQBSAGkMAAAEAEoAawwAAAMARQBqDAAAAQADAG0MAAABAD8A6gwAAAYAPQBuDAAAAQBHABIABwl5G6EZANMBB2gMAAAFAFIAaQwAAAQASgBrDAAAAwBFAGoMAAABAAMAbQwAAAEAPwDqDAAABgA9AG4MAAABAEcALgAECn8eAAISAAgJpyGQFgDPAgASAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAEBLgAECn8WAAMGAAYJHx1sigBMAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAGAAYJHx1sigBMAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgAFAAYJggq3OQCnAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAGAB8dAA==.',
Sa='Sargala:BAEBLgAECn8sAAMJAAgJJhogLwAaAghoDAAACQBLAGkMAAAIAEkAawwAAAoANwBqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABgBWAG4MAAABAEcACQAICSYaIC8AGgIIaAwAAAgASwBpDAAABwBJAGsMAAAJADcAagwAAAQASgBsDAAABABSAG0MAAABABcA6gwAAAYAVgBuDAAAAQBHAB4ABAnnBQJJAJAABGgMAAABABMAaQwAAAEAEgBrDAAAAQAHAGoMAAABABMAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAOAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAOAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAOAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAOAAAAAA==.',
Sm='Smitehaven:BAEALgAECgIJAgABLgAECgYJFgAGAB8dAA==.Smoothdk:BAEALgAFFAIJAgABLgAFFAUJBQAWABEFAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAUJBQAWABEFAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAUJBQAWABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJJwAZAAgdAA==.Thezdin:BAEBLgAECn8nAAIZAAkJCB0ICwA4AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAZAAkJCB0ICwA4AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJJwAZAAgdAA==.',
Ve='Velohm:BAEBLgAECn8bAAMIAAYJ6CGTGQBDAgZoDAAACABXAGkMAAAFAFAAawwAAAQAXABqDAAABABXAGwMAAACAFIA6gwAAAQAWgAIAAYJ6CGTGQBDAgZoDAAABgBXAGkMAAADAFAAawwAAAIAXABqDAAAAgBXAGwMAAACAFIA6gwAAAMAWgADAAUJSAg3XwCWAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAcJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAcJAQAOAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIHAAcJXx6QBABEAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAcABwlfHpAEAEQCB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIHAAgJVyYBBQDvAgAHAAgJVyYBBQDvAgAAAA==.Zogle:BAEBLgAFFH8JAAIFAAUJGRPnHwDgAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEABQAFCRkT5x8A4AAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAcAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAHAF8eAA==.',
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
