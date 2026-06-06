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

local lookup = {'Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Druid-Restoration','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Mage-Frost','Paladin-Protection','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Druid-Balance','Evoker-Preservation','Druid-Feral','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-05',data={As='Astaren:BAEALgAECgkJEgAAAA==.',
Av='Avenmonk:BAECLgAFFH8gAAIBAAcJTRwaAwD9AQdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAEABwlNHBoDAP0BB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIBAAkJTyRfAQCiAwABAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAICAAkJoBRoGADJAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgACAAkJoBRoGADJAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAABAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8NAAIDAAUJcxzxEgA+AQVoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AOoMAAAFAF8AAwAFCXMc8RIAPgEFaAwAAAIAWABpDAAAAQAmAGsMAAABAEQAagwAAAQAOQDqDAAABQBfAC4ABAp/IAADAwAJCdseqwYAygIAAwAJCdseqwYAygIABAAHCWMRHHEApQEAAS4ABRQFCRcABQBlIwA=.Brylic:BAECLgAFFH8XAAMFAAUJZSNWCQDWAQVoDAAABgBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUABQAFCbMgVgkA1gEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAIAXADqDAAAAQAzAAEAAQl3ITI0AGAAAeoMAAACAFUALgAECn8mAAMBAAgJOSMkBgAfAwABAAgJJiEkBgAfAwAFAAgJqiIyCAACAwAAAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJGgAGAIcgAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJOQAHAOYlAA==.',
Cm='Cmenstabber:BAECLgAFFH8KAAICAAMJbAfvKADHAANoDAAAAwARAGkMAAACAAQA6gwAAAUAIwACAAMJbAfvKADHAANoDAAAAwARAGkMAAACAAQA6gwAAAUAIwAuAAQKfyoAAgIACQmbFb4QABkCAAIACQmbFb4QABkCAAAA.',
Da='Darkorin:BAECLgAFFH8PAAIIAAUJxyQlGwCDAQVoDAAABgBhAGkMAAACAGIAawwAAAIAVgBqDAAAAQA5AOoMAAAEAF8ACAAFCcckJRsAgwEFaAwAAAYAYQBpDAAAAgBiAGsMAAACAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADCAAJCYklswYAZQMACAAICUsmswYAZQMACQACCcsOf4QANgAAAAA=.',
Du='Duskorin:BAEBLgAFFH8IAAMKAAMJ5Q9dOwCHAANoDAAAAwBGAOoMAAAEAB8AbgwAAAEAEwAKAAIJDQpdOwCHAALqDAAAAQAfAG4MAAABABMACwACCSoTqV8AcwACaAwAAAMALwDqDAAAAwAyAAEuAAUUBQkPAAgAxyQA.',
Fi='Fishybrew:BAEBLgAECn8tAAIFAAgJYyIbCACpAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABQAICWMiGwgAqQIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkGAAwAAAAA.',
Fl='Fleasfordays:BAEALgAECgIJAgABLgAFFAMJCgACAGwHAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgcJGgANANgWAA==.Foxleaf:BAEALgAECgEJAQABLgAECgcJGgANANgWAA==.Foxorcism:BAEBLgAECn8XAAQJAAcJPBWqMQCEAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAkABgl5GKoxAIQBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAgAAwl9B8w2AWQAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJAA4AAQn6A+5QACQAAW0MAAABAAoAAS4ABAoHCRoADQDYFgA=.Foxox:BAEBLgAECn8aAAINAAcJ2BbOYwCvAQdoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAABABNAG0MAAACADMA6gwAAAMARQBuDAAAAQAHAA0ABwnYFs5jAK8BB2gMAAAHAEoAaQwAAAUAQgBrDAAABAA+AGwMAAAEAE0AbQwAAAIAMwDqDAAAAwBFAG4MAAABAAcAAAA=.',
Fr='Fries:BAEALgAFFAMJBAABLgAFFAQJBwAPAKYPAA==.Frip:BAEALgAECgIJAgABLgAECgkJOQAHAOYlAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIIAAkJVgkDgABiAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAIAAkJVgkDgABiAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gr='Grimmyb:BAECLgAFFH8LAAMQAAMJABoYVwDUAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQAQAAMJhhYYVwDUAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgARAAEJWiF4DQBYAAHqDAAAAQBVAC4ABAp/JwADEQAJCZgh8gEA8QIAEQAICdsh8gEA8QIAEAAJCaEb9TwAxwEAAS4ABRQICR8AEQBMIAA=.Grìmbles:BAECLgAFFH8fAAIRAAgJTCASAAAoAghoDAAABQBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAEQAICUwgEgAAKAIIaAwAAAUAYgBpDAAACABhAGsMAAAIAGQAagwAAAEAUABsDAAAAwBYAG0MAAABAGQA6gwAAAQAWABuDAAAAQAFAC4ABAp/HQACEQAJCZ0lOAAAlwMAEQAJCZ0lOAAAlwMAAAA=.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwASADYmAA==.Guthynn:BAEBLgAECn8vAAMSAAkJNiYfAAB5AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgASAAkJNiYfAAB5AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgATAAUJPyE3CgCKAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Gw='Gwimbles:BAECLgAFFH8OAAIDAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgADAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgMACQmMHiYHAL4CAAMACQmMHiYHAL4CAAEuAAUUCAkfABEATCAA.Gwìmbles:BAEBLgAFFH8IAAMUAAUJ2QWDMABCAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAFAACCagLgzAAQgACaAwAAAIAOgDqDAAAAgABABUABAkKADxQAAMABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQICR8AEQBMIAA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgALADwdAA==.Irrogenia:BAEBLgAECn8uAAMLAAkJPB1ADwDMAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgALAAkJPB1ADwDMAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAKAAIJ/QrMgwBXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgALADwdAA==.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJOQAHAOYlAA==.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAWAP8PAA==.Lidathra:BAECLgAFFH8LAAIWAAQJ/w/qGADwAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABYABAn/D+oYAPAABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIWAAkJ5hXsCgAlAgAWAAkJ5hXsCgAlAgAAAA==.Lidiosa:BAEBLgAECn8nAAINAAkJdhopIgCOAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgANAAkJdhopIgCOAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAWAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAWAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAWAP8PAA==.',
Lo='Lochru:BAEBLgAECn9GAAIXAAkJ4yMJAQBIAwloDAAACgBhAGkMAAAJAFgAawwAAAoAUgBqDAAACABiAGwMAAAIAF4AbQwAAAcAWQDqDAAACQBfAG4MAAAGAF8AbwwAAAMAWwAXAAkJ4yMJAQBIAwloDAAACgBhAGkMAAAJAFgAawwAAAoAUgBqDAAACABiAGwMAAAIAF4AbQwAAAcAWQDqDAAACQBfAG4MAAAGAF8AbwwAAAMAWwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIYAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABgABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJDwAIAMckAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJOQAHAOYlAA==.',
Ne='Neodefender:BAECLgAFFH8pAAIJAAYJKCYHBAB9AgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAJAAYJKCYHBAB9AgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAuAAQKfzIAAgkACQnnJvwAAIgDAAkACQnnJvwAAIgDAAAA.',
No='Nosferratu:BAECLgAFFH8lAAMZAAcJvh/IAgBaAgdoDAAACQBjAGkMAAAGAF4AawwAAAYAWwBqDAAABQAcAGwMAAACAD0A6gwAAAgAYwBuDAAAAQAoABkABwm+H8gCAFoCB2gMAAAJAGMAaQwAAAUAXgBrDAAABQBbAGoMAAAFABwAbAwAAAIAPQDqDAAACABjAG4MAAABACgAGgACCTgH1DcAgAACaQwAAAEADwBrDAAAAQAVAC4ABAp/QQACGQAJCYQmsAAAgwMAGQAJCYQmsAAAgwMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8hAAIFAAUJwhwBFgBdAQVoDAAACQBMAGkMAAAIAD0AawwAAAUARQBqDAAABABJAOoMAAAHAFYABQAFCcIcARYAXQEFaAwAAAkATABpDAAACAA9AGsMAAAFAEUAagwAAAQASQDqDAAABwBWAC4ABAp/LAACBQAJCQ4kzQEARgMABQAJCQ4kzQEARgMAAAA=.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAgJHwARAEwgAA==.',
Or='Orsp:BAECLgAFFH8jAAQZAAcJgRiRBwDTAQdoDAAACABiAGkMAAAGAFEAawwAAAUATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACQBaABkABgk8HZEHANMBBmgMAAAIAGIAaQwAAAYAUQBrDAAABQBMAGoMAAACAEcAbQwAAAEAGwDqDAAACQBaABoAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQAbAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KgAEGQAJCTcjOwUAPQMAGQAJCTcjOwUAPQMAGwADCcoKCGUAmQAAGgADCcEZ30YAhgAAAAA=.Orspp:BAECLgAFFH8GAAMZAAMJfxKjKACVAANoDAAAAgBAAGkMAAACADsA6gwAAAIAEQAZAAIJOxijKACVAAJoDAAAAgBAAGkMAAACADsAGgABCQkVPEIAQgAB6gwAAAIANQAuAAQKfxwABBkACAkoGm4hAMwBABkACAkoGm4hAMwBABsABgmlCCJJABQBABoAAQm1DcNVADYAAAEuAAUUBwkjABkAgRgA.',
Pa='Pakk:BAEBLgAECn8uAAIDAAgJoiDBCACAAghoDAAACQBeAGkMAAAIAFIAawwAAAcATwBqDAAABgBQAGwMAAAGAFQAbQwAAAEAPwDqDAAABgBdAG4MAAADAFYAAwAICaIgwQgAgAIIaAwAAAkAXgBpDAAACABSAGsMAAAHAE8AagwAAAYAUABsDAAABgBUAG0MAAABAD8A6gwAAAYAXQBuDAAAAwBWAAAA.Pandoken:BAEBLgAFFH8RAAMcAAYJUh3JDQD+AQZoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAAcAAYJUh3JDQD+AQZoDAAAAwBNAGkMAAADAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAABAAIJSRnIJgCnAAJoDAAAAQAvAGkMAAABAFIAAS4ABRQJCRoABgCHIAA=.Pandotides:BAEALgAFFAUJAgABLgAFFAkJGgAGAIcgAA==.Papadefensve:BAEALgAECgYJBgAAAA==.',
Pr='Priff:BAEBLgAECn85AAQHAAkJ5iUuAwBYAwloDAAACABiAGkMAAAIAGEAawwAAAgAXQBqDAAABgBgAGwMAAAHAFsAbQwAAAYAYwDqDAAACABgAG4MAAAEAGMAbwwAAAIAYgAHAAkJ2iUuAwBYAwloDAAAAwBhAGkMAAAFAGEAawwAAAQAXQBqDAAAAwBgAGwMAAABAFsAbQwAAAUAYwDqDAAAAwBgAG4MAAAEAGMAbwwAAAIAYgAdAAcJ9yFfGABqAgdoDAAAAwBTAGkMAAADAFwAawwAAAMASgBqDAAAAgAoAGwMAAAEAFQAbQwAAAEAXwDqDAAAAwBaAB4ABQnlIR4mAGcBBWgMAAACAGIAawwAAAEASgBqDAAAAQBTAGwMAAACAFQA6gwAAAIAWQAAAA==.Priffraff:BAEALgAECgYJCwABLgAECgkJOQAHAOYlAA==.',
Ra='Razamon:BAEBLgAECn8rAAMLAAkJMSHtGAB1AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAALAAkJMSHtGAB1AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAKAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJMAAPAEEbAA==.Relsham:BAEALgAECgkJAgABLgAFFAQJCAANAFIHAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAUJFwAFAGUjAA==.',
Ro='Roukedhh:BAECLgAFFH8SAAIQAAcJKhj+GADEAQdoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAG0MAAABAD8A6gwAAAYAPQBuDAAAAQBHABAABwkqGP4YAMQBB2gMAAAEAFIAaQwAAAMASgBrDAAAAgASAGoMAAABAAMAbQwAAAEAPwDqDAAABgA9AG4MAAABAEcALgAECn8eAAIQAAgJpyGQFgDPAgAQAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAEBLgAECn8WAAMEAAYJHx1JhgBNAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAEAAYJHx1JhgBNAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgADAAYJggp0NwCrAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAEAB8dAA==.',
Sa='Sargala:BAEBLgAECn8sAAMHAAgJJhplLAAgAghoDAAACQBLAGkMAAAIAEkAawwAAAoANwBqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABgBWAG4MAAABAEcABwAICSYaZSwAIAIIaAwAAAgASwBpDAAABwBJAGsMAAAJADcAagwAAAQASgBsDAAABABSAG0MAAABABcA6gwAAAYAVgBuDAAAAQBHAB4ABAnnBQVHAJIABGgMAAABABMAaQwAAAEAEgBrDAAAAQAHAGoMAAABABMAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAMAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAMAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAMAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAMAAAAAA==.',
Sm='Smoothz:BAEALgAECgcJDAABLgAFFAUJBQAUABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJJwAYAAgdAA==.Thezdin:BAEBLgAECn8nAAIYAAkJCB1hCgA+AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAYAAkJCB1hCgA+AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJJwAYAAgdAA==.',
Ve='Velohm:BAEBLgAECn8VAAMcAAYJSQ6qWADvAAZoDAAABwBXAGkMAAAEABEAawwAAAMABABqDAAAAwAFAGwMAAABACcA6gwAAAMAQQAcAAYJSQ6qWADvAAZoDAAABQBXAGkMAAACABEAawwAAAEABABqDAAAAQAFAGwMAAABACcA6gwAAAIAQQABAAUJSAjsWwCXAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAcJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAcJAQAMAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIFAAcJXx6+AwBIAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAUABwlfHr4DAEgCB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIFAAgJVybHBADxAgAFAAgJVybHBADxAgAAAA==.Zogle:BAEBLgAFFH8JAAIDAAUJGRNhHQDmAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEAAwAFCRkTYR0A5gAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAUAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAFAF8eAA==.',
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
