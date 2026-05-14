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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Hunter-BeastMastery','Rogue-Subtlety','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Warlock-Demonology','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Mage-Frost','Druid-Feral','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Devourer',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-05-13',data={As='Astaren:BAEALgAECgcJDAAAAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8FAAIBAAMJiiGYGgCNAANoDAAAAQBLAGoMAAABADAA6gwAAAMAXwABAAMJiiGYGgCNAANoDAAAAQBLAGoMAAABADAA6gwAAAMAXwAuAAQKfyAAAwEACQnbHqsGAMoCAAEACQnbHqsGAMoCAAIABwljERxxAKUBAAEuAAUUBAkNAAMAlh8A.Brylic:BAECLgAFFH8NAAIDAAQJlh/eCQB8AQRoDAAABABYAGkMAAAFAF4AawwAAAMAWQDqDAAAAQAzAAMABAmWH94JAHwBBGgMAAAEAFgAaQwAAAUAXgBrDAAAAwBZAOoMAAABADMALgAECn8hAAMEAAgJOSMkBgAfAwAEAAgJJiEkBgAfAwADAAgJqiIyCAACAwAAAA==.',
Ca='Camreon:BAEALgAFFAEJAQAAAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJLwAFAE4lAA==.',
Cm='Cmenstabber:BAEBLgAECn8kAAIGAAgJDBY6CwACAghoDAAABgA4AGkMAAAGAEoAawwAAAYARwBqDAAABQA8AGwMAAAFAFkAbQwAAAEACQDqDAAABgA0AG4MAAABACgABgAICQwWOgsAAgIIaAwAAAYAOABpDAAABgBKAGsMAAAGAEcAagwAAAUAPABsDAAABQBZAG0MAAABAAkA6gwAAAYANABuDAAAAQAoAAAA.',
Fi='Fishybrew:BAEBLgAECn8eAAIDAAYJeh+WFACtAQZoDAAABwA+AGkMAAAGAFQAawwAAAUAUgBqDAAABABXAGwMAAADAFAA6gwAAAUAXQADAAYJeh+WFACtAQZoDAAABwA+AGkMAAAGAFQAawwAAAUAUgBqDAAABABXAGwMAAADAFAA6gwAAAUAXQABLgADCgEJAQAHAAAAAA==.',
Fl='Fleasfordays:BAEALgAECgEJAQABLgAECggJJAAGAAwWAA==.',
Fo='Foxblade:BAEALgAECgUJCgABLgAECgYJFgAIAHkYAA==.Foxorcism:BAEBLgAECn8WAAMIAAYJeRiPHwCkAQZoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0A6gwAAAQAUgAIAAYJeRiPHwCkAQZoDAAAAwBSAGkMAAADADEAawwAAAMATABqDAAABAA3AGwMAAACAB0A6gwAAAQAUgAJAAMJfQcz2QBuAANoDAAAAQAqAGkMAAABAAUAawwAAAEACQAAAA==.Foxox:BAEALgAECgQJEwABLgAECgYJFgAIAHkYAA==.',
Fr='Fries:BAEALgAECgcJCgABLgAFFAQJBwAKAKYPAA==.',
Ga='Gardenweed:BAEALgAECgYJEQAAAA==.',
Gu='Guthyne:BAEALgAECgMJAwABLgAECggJIQALAMAjAA==.Guthynn:BAEBLgAECn8hAAMLAAgJwCPDAAAdAwhoDAAABwBhAGkMAAAFAFwAawwAAAUAYQBqDAAAAgBiAGwMAAABAFkAbQwAAAMAQwDqDAAABQBjAG4MAAAFAGEACwAICcAjwwAAHQMIaAwAAAUAYQBpDAAABQBcAGsMAAAFAGEAagwAAAIAYgBsDAAAAQBZAG0MAAADAEMA6gwAAAUAYwBuDAAABQBhAAwAAQnMG14dAEAAAWgMAAACAEcAAAA=.',
Ir='Irrogenia:BAEBLgAECn8oAAMNAAgJYB+7CQCwAghoDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAIANQDqDAAABwBVAG4MAAADAEAADQAICWAfuwkAsAIIaAwAAAcAYABpDAAABgBVAGsMAAAFAGEAagwAAAQARgBsDAAABABZAG0MAAACADUA6gwAAAcAVQBuDAAAAwBAAA4AAgn9Ck9ZAGQAAmkMAAABACIAawwAAAEAFQAAAA==.',
Ja='Jarik:BAEALgAECgQJCAABLgAECgkJLwAFAE4lAA==.',
Ka='Kalamazi:BAEBLgAFFH8TAAQKAAQJGh+oPAAAAQRoDAAABQBbAGkMAAAFAEwAawwAAAQARQDqDAAABQBQAAoAAwmXH6g8AAABA2gMAAAFAFsAaQwAAAEARgDqDAAABQBQAA8AAgnAFBMNAKQAAmkMAAABACQAawwAAAQARQAQAAEJxB17AwBfAAFpDAAAAwBMAAAA.',
Li='Lidariel:BAEALgAECgIJAgABLgAECggJFgAEAG4UAA==.Lidathra:BAEBLgAECn8oAAIRAAkJ1RVgBgA8AgloDAAABQAkAGkMAAAFAE4AawwAAAUAPgBqDAAABQBCAGwMAAAFAEkAbQwAAAQANQDqDAAABQAtAG4MAAAFAEIAbwwAAAEAFAARAAkJ1RVgBgA8AgloDAAABQAkAGkMAAAFAE4AawwAAAUAPgBqDAAABQBCAGwMAAAFAEkAbQwAAAQANQDqDAAABQAtAG4MAAAFAEIAbwwAAAEAFAABLgAECggJFgAEAG4UAA==.Lidiosa:BAEBLgAECn8XAAISAAYJVRFsfAArAQZoDAAABQAyAGkMAAADADQAawwAAAQAKQBqDAAAAwASAGwMAAACADAA6gwAAAYAHAASAAYJVRFsfAArAQZoDAAABQAyAGkMAAADADQAawwAAAQAKQBqDAAAAwASAGwMAAACADAA6gwAAAYAHAABLgAECggJFgAEAG4UAA==.Lidizine:BAEALgADCggJDAABLgAECggJFgAEAG4UAA==.',
Lo='Lochru:BAEBLgAECn8pAAITAAgJKxzKBAA6AghoDAAABwBdAGkMAAAGAFMAawwAAAcAUgBqDAAABQBSAGwMAAAEAEMAbQwAAAMALwDqDAAABgBMAG4MAAADADUAEwAICSscygQAOgIIaAwAAAcAXQBpDAAABgBTAGsMAAAHAFIAagwAAAUAUgBsDAAABABDAG0MAAADAC8A6gwAAAYATABuDAAAAwA1AAAA.',
Ma='Makoto:BAEBLgAECn8aAAIUAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABQABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Na='Nalfein:BAEALgADCgYJBgABLgAECgkJLwAFAE4lAA==.',
Ne='Neodefender:BAECLgAFFH8eAAIIAAUJHyY+AwAdAgVoDAAACABjAGkMAAAHAF4AawwAAAUAYwBqDAAAAwBfAOoMAAAHAGEACAAFCR8mPgMAHQIFaAwAAAgAYwBpDAAABwBeAGsMAAAFAGMAagwAAAMAXwDqDAAABwBhAC4ABAp/KwACCAAJCUIm/AAAiAMACAAJCUIm/AAAiAMAAAA=.',
No='Nosferratu:BAECLgAFFH8dAAIVAAcJUhzDAABQAgdoDAAABwBjAGkMAAAEACwAawwAAAQAWwBqDAAABQAcAGwMAAACAD0A6gwAAAYAYQBuDAAAAQAoABUABwlSHMMAAFACB2gMAAAHAGMAaQwAAAQALABrDAAABABbAGoMAAAFABwAbAwAAAIAPQDqDAAABgBhAG4MAAABACgALgAECn82AAIVAAkJVCZXAACIAwAVAAkJVCZXAACIAwAAAA==.',
Ny='Nyfaria:BAECLgAFFH8QAAIDAAQJ5QaOIAD0AARoDAAABgAZAGkMAAAFAAQAawwAAAEABgDqDAAABAAhAAMABAnlBo4gAPQABGgMAAAGABkAaQwAAAUABABrDAAAAQAGAOoMAAAEACEALgAECn8XAAIDAAkJnA6lJgDPAQADAAkJnA6lJgDPAQAAAA==.',
Or='Orsp:BAECLgAFFH8VAAQVAAcJDhSKAwCxAQdoDAAABABLAGkMAAADAEwAawwAAAMANABqDAAAAwATAGwMAAABAAIAbQwAAAEAGgDqDAAABgBKABUABgnlF4oDALEBBmgMAAAEAEsAaQwAAAMATABrDAAAAwA0AGoMAAABABMAbQwAAAEAGgDqDAAABgBKABYAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAEABQAXAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KQAEFQAJCSojOwUAPQMAFQAJCSojOwUAPQMAFwADCcoKCGUAmQAAFgADCcEZnUEAZAAAAAA=.Orspp:BAEBLgAECn8bAAQVAAcJfBhuIQDMAQdoDAAAAwBGAGkMAAAFAEUAawwAAAQAQQBqDAAABABPAGwMAAADAC8A6gwAAAcAXgBuDAAAAQAbABUABwl8GG4hAMwBB2gMAAACAEYAaQwAAAQARQBrDAAAAwBBAGoMAAACAE8AbAwAAAEALwDqDAAABABeAG4MAAABABsAFwAGCaUIIkkAFAEGaAwAAAEABwBpDAAAAQAaAGsMAAABAAgAagwAAAIAGwBsDAAAAgAvAOoMAAACAA4AFgABCbUNw1UANgAB6gwAAAEAIwABLgAFFAcJFQAVAA4UAA==.',
Pa='Pakk:BAEBLgAECn8YAAIBAAYJ9h6/DQC2AQZoDAAABgBeAGkMAAAFAE4AawwAAAQAQABqDAAAAwBJAGwMAAADAEQA6gwAAAMAWQABAAYJ9h6/DQC2AQZoDAAABgBeAGkMAAAFAE4AawwAAAQAQABqDAAAAwBJAGwMAAADAEQA6gwAAAMAWQAAAA==.Papadefensve:BAEALgADCgEJAQAAAA==.',
Pr='Priff:BAEBLgAECn8vAAQFAAkJTiV6BgDhAgloDAAABwBiAGkMAAAHAFwAawwAAAcAXQBqDAAABQBdAGwMAAAGAFQAbQwAAAUAYwDqDAAABgBgAG4MAAADAGMAbwwAAAEAYgAFAAgJnyV6BgDhAghoDAAAAwBhAGkMAAAEAFgAawwAAAMAXQBqDAAAAgBdAG0MAAAEAGMA6gwAAAIAYABuDAAAAwBjAG8MAAABAGIAGAAHCfchXxgAagIHaAwAAAMAUwBpDAAAAwBcAGsMAAADAEoAagwAAAIAKABsDAAABABUAG0MAAABAF8A6gwAAAMAWgAZAAUJ5SEDFQCMAQVoDAAAAQBiAGsMAAABAEoAagwAAAEAUwBsDAAAAgBUAOoMAAABAFkAAAA=.',
Ra='Razamon:BAEBLgAECn8rAAMNAAkJMSEzDACMAgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAANAAkJMSEzDACMAgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAOAAcJgxgLJwA8AQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAECgQJBAABLgAFFAgJGwAKAOQTAA==.Relsham:BAEALgAECgkJAgABLgAFFAQJBwASALEFAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAQJDQADAJYfAA==.',
Ro='Roukedhh:BAECLgAFFH8OAAIaAAUJGhdyJAAwAQVoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAOoMAAAEAD0AGgAFCRoXciQAMAEFaAwAAAQAUgBpDAAAAwBKAGsMAAACABIAagwAAAEAAwDqDAAABAA9AC4ABAp/GgACGgAICachkBYAzwIAGgAICachkBYAzwIAAAA=.',
Ru='Runehaven:BAEALgAECgYJDAAAAA==.',
Sa='Sargala:BAEBLgAECn8XAAIFAAYJTRT+TAA/AQZoDAAABgBLAGkMAAAFAC0AawwAAAUAMABqDAAAAgApAGwMAAACADMA6gwAAAMAJwAFAAYJTRT+TAA/AQZoDAAABgBLAGkMAAAFAC0AawwAAAUAMABqDAAAAgApAGwMAAACADMA6gwAAAMAJwAAAA==.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAHAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAHAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAHAAAAAA==.',
Th='Thezdin:BAEBLgAECn8jAAIUAAcJYhv8DgCFAQdoDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACABPABQABwliG/wOAIUBB2gMAAAGAFgAaQwAAAYATwBrDAAABgBOAGoMAAAEAD4AbAwAAAMASwBtDAAAAgASAOoMAAAIAE8AAAA=.Thezfu:BAEALgAECgEJAgABLgAECgcJIwAUAGIbAA==.',
Ve='Velohm:BAEALgAECgUJBgAAAA==.',
Zi='Zick:BAEALgAFFAYJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAYJAQAHAAAAAA==.',
Zo='Zoe:BAECLgAFFH8XAAIDAAYJQSDIAQAVAgZoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgADAAYJQSDIAQAVAgZoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgAuAAQKfygAAgMACAlKJn0GAB8DAAMACAlKJn0GAB8DAAAA.Zogle:BAEBLgAFFH8JAAIBAAUJGBNrDgARAQVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEAAQAFCRgTaw4AEQEFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBgkXAAMAQSAA.Zoog:BAEALgAECggJEwABLgAFFAYJFwADAEEgAA==.',
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
