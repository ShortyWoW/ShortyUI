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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Rogue-Subtlety','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Paladin-Protection','Mage-Frost','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Druid-Feral','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-BeastMastery',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-05-27',data={As='Astaren:BAEALgAECgcJDgAAAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8JAAIBAAMJiiFjJACSAANoDAAAAQBLAGoMAAADADkA6gwAAAUAXwABAAMJiiFjJACSAANoDAAAAQBLAGoMAAADADkA6gwAAAUAXwAuAAQKfyAAAwEACQnbHqsGAMoCAAEACQnbHqsGAMoCAAIABwljERxxAKUBAAEuAAUUBQkWAAMANSMA.Brylic:BAECLgAFFH8WAAMDAAUJNSNtBgDlAQVoDAAABgBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAQBaAOoMAAADAFUAAwAFCYMgbQYA5QEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAEAWgDqDAAAAQAzAAQAAQl3ISUtAGQAAeoMAAACAFUALgAECn8mAAMEAAgJOSMkBgAfAwAEAAgJJiEkBgAfAwADAAgJqiIyCAACAwAAAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAgJCAAFAAwdAA==.',
Cm='Cmenstabber:BAECLgAFFH8HAAIGAAMJCQeuJADAAANoDAAAAwARAGkMAAABAAEA6gwAAAMAIwAGAAMJCQeuJADAAANoDAAAAwARAGkMAAABAAEA6gwAAAMAIwAuAAQKfykAAgYACQmlFAIRAAYCAAYACQmlFAIRAAYCAAAA.',
Da='Darkorin:BAECLgAFFH8PAAIHAAUJxyS2EgCSAQVoDAAABgBhAGkMAAACAGIAawwAAAIAVgBqDAAAAQA5AOoMAAAEAF8ABwAFCcckthIAkgEFaAwAAAYAYQBpDAAAAgBiAGsMAAACAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADBwAJCYklswYAZQMABwAICUsmswYAZQMACAACCcsOaH0AOAAAAAA=.',
Du='Duskorin:BAEBLgAFFH8GAAIJAAIJKhNDUQCCAAJoDAAAAwAvAOoMAAADADIACQACCSoTQ1EAggACaAwAAAMALwDqDAAAAwAyAAEuAAUUBQkPAAcAxyQA.',
Fi='Fishybrew:BAEBLgAECn8sAAIDAAgJPyJNBwCpAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAABAFoAAwAICT8iTQcAqQIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAQBaAAEuAAMKAQkBAAoAAAAA.',
Fl='Fleasfordays:BAEALgAECgEJAQABLgAFFAMJBwAGAAkHAA==.',
Fo='Foxblade:BAEALgAECgcJDAABLgAECgcJFwAIADwVAA==.Foxleaf:BAEALgAECgEJAQABLgAECgcJFwAIADwVAA==.Foxorcism:BAEBLgAECn8XAAQIAAcJPBVfLgCHAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAgABgl5GF8uAIcBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAcAAwl9B1YsAV0AA2gMAAABACoAaQwAAAEABQBrDAAAAQAJAAsAAQn6A/5JACcAAW0MAAABAAoAAAA=.Foxox:BAEBLgAECn8XAAIMAAYJExpvaQCLAQZoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAAAwBNAG0MAAABADIA6gwAAAMARQAMAAYJExpvaQCLAQZoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAAAwBNAG0MAAABADIA6gwAAAMARQABLgAECgcJFwAIADwVAA==.',
Fr='Fries:BAEALgAECgcJCgABLgAFFAQJBwANAKYPAA==.',
Ga='Gardenweed:BAEBLgAECn8eAAIHAAcJdgrhpgAOAQdoDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABAAXAAcABwl2CuGmAA4BB2gMAAAFACMAaQwAAAUAGgBrDAAABQATAGoMAAAFABoAbAwAAAUAKABtDAAAAQAPAOoMAAAEABcAAAA=.',
Gr='Grimmyb:BAECLgAFFH8LAAMOAAMJABphSwDhAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQAOAAMJhhZhSwDhAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgAPAAEJWiFiCwBbAAHqDAAAAQBVAC4ABAp/JwADDwAJCZgh8gEA8QIADwAICdsh8gEA8QIADgAJCaEb8jYA0AEAAS4ABRQICR8ADwBMIAA=.Grìmbles:BAECLgAFFH8fAAIPAAgJTCASAAAoAghoDAAABQBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUADwAICUwgEgAAKAIIaAwAAAUAYgBpDAAACABhAGsMAAAIAGQAagwAAAEAUABsDAAAAwBYAG0MAAABAGQA6gwAAAQAWABuDAAAAQAFAC4ABAp/HQACDwAJCZ0lOAAAlwMADwAJCZ0lOAAAlwMAAAA=.',
Gu='Guthyne:BAEALgAECgMJAwABLgAECgkJIgAQAOYjAA==.Guthynn:BAEBLgAECn8iAAMQAAkJ5iPDAAAdAwloDAAABwBhAGkMAAAFAFwAawwAAAUAYQBqDAAAAgBiAGwMAAABAFkAbQwAAAMAQwDqDAAABQBjAG4MAAAFAGEAbwwAAAEAXgAQAAkJ5iPDAAAdAwloDAAABQBhAGkMAAAFAFwAawwAAAUAYQBqDAAAAgBiAGwMAAABAFkAbQwAAAMAQwDqDAAABQBjAG4MAAAFAGEAbwwAAAEAXgARAAEJzBteHQBAAAFoDAAAAgBHAAAA.',
Gw='Gwimbles:BAECLgAFFH8OAAIBAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgABAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgEACQmMHiYHAL4CAAEACQmMHiYHAL4CAAEuAAUUCAkfAA8ATCAA.Gwìmbles:BAEBLgAFFH8IAAMSAAUJ2QWEJgBFAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAEgACCagLhCYARQACaAwAAAIAOgDqDAAAAgABABMABAkKAHxGAAMABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQICR8ADwBMIAA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgAJADwdAA==.Irrogenia:BAEBLgAECn8uAAMJAAkJPB0gDQDQAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAJAAkJPB0gDQDQAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAUAAIJ/QodegBXAAJpDAAAAQAiAGsMAAABABUAAAA=.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAVAP8PAA==.Lidathra:BAECLgAFFH8LAAIVAAQJ/w/jFQAPAQRoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABUABAn/D+MVAA8BBGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIVAAkJ5hX/CQArAgAVAAkJ5hX/CQArAgAAAA==.Lidiosa:BAEBLgAECn8eAAIMAAgJ9xONXACrAQhoDAAABgAyAGkMAAAEADkAawwAAAQAKQBqDAAAAwASAGwMAAADADAAbQwAAAEAJwDqDAAACAArAG4MAAABAEwADAAICfcTjVwAqwEIaAwAAAYAMgBpDAAABAA5AGsMAAAEACkAagwAAAMAEgBsDAAAAwAwAG0MAAABACcA6gwAAAgAKwBuDAAAAQBMAAEuAAUUBAkLABUA/w8A.Lidishi:BAEALgAECgYJBgABLgAFFAQJCwAVAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAVAP8PAA==.',
Lo='Lochru:BAEBLgAECn87AAIWAAkJhiGQAQAVAwloDAAACQBhAGkMAAAIAFgAawwAAAkAUgBqDAAABwBiAGwMAAAHAF4AbQwAAAYATwDqDAAACABfAG4MAAAEAFQAbwwAAAEAQAAWAAkJhiGQAQAVAwloDAAACQBhAGkMAAAIAFgAawwAAAkAUgBqDAAABwBiAGwMAAAHAF4AbQwAAAYATwDqDAAACABfAG4MAAAEAFQAbwwAAAEAQAAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIXAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABcABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJDwAHAMckAA==.',
Ne='Neodefender:BAECLgAFFH8oAAIIAAYJKCZmAgCKAgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAACAF4A6gwAAAcAYQAIAAYJKCZmAgCKAgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAACAF4A6gwAAAcAYQAuAAQKfzIAAggACQnnJvwAAIgDAAgACQnnJvwAAIgDAAAA.',
No='Nosferratu:BAECLgAFFH8lAAMYAAcJvh+wAQBwAgdoDAAACQBjAGkMAAAGAF4AawwAAAYAWwBqDAAABQAcAGwMAAACAD0A6gwAAAgAYwBuDAAAAQAoABgABwm+H7ABAHACB2gMAAAJAGMAaQwAAAUAXgBrDAAABQBbAGoMAAAFABwAbAwAAAIAPQDqDAAACABjAG4MAAABACgAGQACCTgHWzEAhwACaQwAAAEADwBrDAAAAQAVAC4ABAp/QQACGAAJCYQmgQAAfAMAGAAJCYQmgQAAfAMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8bAAIDAAUJuxlWFQBNAQVoDAAACABLAGkMAAAHADkAawwAAAQALABqDAAAAgBJAOoMAAAGAFYAAwAFCbsZVhUATQEFaAwAAAgASwBpDAAABwA5AGsMAAAEACwAagwAAAIASQDqDAAABgBWAC4ABAp/KgACAwAJCeQgygIAHQMAAwAJCeQgygIAHQMAAAA=.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAgJHwAPAEwgAA==.',
Or='Orsp:BAECLgAFFH8fAAQYAAcJQhiIBQDdAQdoDAAABwBeAGkMAAAFAFEAawwAAAQATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACABaABgABgnwHIgFAN0BBmgMAAAHAF4AaQwAAAUAUQBrDAAABABMAGoMAAACAEcAbQwAAAEAGwDqDAAACABaABkAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQAaAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KgAEGAAJCTcjOwUAPQMAGAAJCTcjOwUAPQMAGgADCcoKCGUAmQAAGQADCcEZI1cAYgAAAAA=.Orspp:BAECLgAFFH8GAAMYAAMJfxK8IwCgAANoDAAAAgBAAGkMAAACADsA6gwAAAIAEQAYAAIJOxi8IwCgAAJoDAAAAgBAAGkMAAACADsAGQABCQkVJTkATAAB6gwAAAIANQAuAAQKfxwABBgACAkoGm4hAMwBABgACAkoGm4hAMwBABoABgmlCCJJABQBABkAAQm1DcNVADYAAAEuAAUUBwkfABgAQhgA.',
Pa='Pakk:BAEBLgAECn8mAAIBAAcJKCHjCwAsAgdoDAAACABeAGkMAAAHAE4AawwAAAYATwBqDAAABQBOAGwMAAAFAEsA6gwAAAUAXQBuDAAAAgBWAAEABwkoIeMLACwCB2gMAAAIAF4AaQwAAAcATgBrDAAABgBPAGoMAAAFAE4AbAwAAAUASwDqDAAABQBdAG4MAAACAFYAAAA=.Pandoken:BAEBLgAFFH8IAAIFAAUJDB3+DwCwAQVoDAAAAgBNAGkMAAACAE8AawwAAAIAUgBqDAAAAQBEAOoMAAABAEAABQAFCQwd/g8AsAEFaAwAAAIATQBpDAAAAgBPAGsMAAACAFIAagwAAAEARADqDAAAAQBAAAAA.Pandotides:BAEALgAFFAUJAgABLgAFFAgJCAAFAAwdAA==.Papadefensve:BAEALgADCgEJAQAAAA==.',
Ra='Razamon:BAEBLgAECn8rAAMJAAkJMSHrFQB6AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAJAAkJMSHrFQB6AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAUAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJIgANAGgSAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAUJFgADADUjAA==.',
Ro='Roukedhh:BAECLgAFFH8QAAIOAAYJcRf1HwB3AQZoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAG0MAAABAD8A6gwAAAUAPQAOAAYJcRf1HwB3AQZoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAG0MAAABAD8A6gwAAAUAPQAuAAQKfx4AAg4ACAmnIZAWAM8CAA4ACAmnIZAWAM8CAAAA.',
Ru='Runehaven:BAEBLgAECn8WAAMCAAYJHx19fABPAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgACAAYJHx19fABPAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgABAAYJggo+MwCsAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgACAB8dAA==.',
Sa='Sargala:BAEBLgAECn8jAAIbAAcJJRfURgCsAQdoDAAACABLAGkMAAAHAEkAawwAAAgANwBqDAAAAwBKAGwMAAADAFIAbQwAAAEAFwDqDAAABQAsABsABwklF9RGAKwBB2gMAAAIAEsAaQwAAAcASQBrDAAACAA3AGoMAAADAEoAbAwAAAMAUgBtDAAAAQAXAOoMAAAFACwAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAKAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAKAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAKAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAKAAAAAA==.',
Sm='Smoothz:BAEALgAECgcJDAABLgAFFAUJBQASABEFAA==.',
Th='Thez:BAEALgADCgYJCAABLgAECgcJJQAXAGobAA==.Thezdin:BAEBLgAECn8lAAIXAAcJahsKEgDnAQdoDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPABcABwlqGwoSAOcBB2gMAAAGAFgAaQwAAAYATwBrDAAABgBOAGoMAAAEAD4AbAwAAAMASwBtDAAAAgASAOoMAAAKAE8AAAA=.Thezfu:BAEALgAECgEJAwABLgAECgcJJQAXAGobAA==.',
Ve='Velohm:BAEALgAECgUJEAAAAA==.',
Zi='Zick:BAEALgAFFAYJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAYJAQAKAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIDAAcJXx5CAgBXAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAMABwlfHkICAFcCB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIDAAgJVyYoBADzAgADAAgJVyYoBADzAgAAAA==.Zogle:BAEBLgAFFH8JAAIBAAUJGRMsGAD1AAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEAAQAFCRkTLBgA9QAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAMAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAADAF8eAA==.',
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
