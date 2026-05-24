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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-23',data={Ad='Advvy:BAEALgAECgUJDgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn84AAICAAkJgCLRBAABAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQACAAkJgCLRBAABAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQAAAA==.Algebra:BAECLgAFFH8VAAIDAAUJ6SQBHQCvAQVoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAOoMAAAEAFkAAwAFCekkAR0ArwEFaAwAAAYAWwBpDAAABQBhAGsMAAAEAGMAagwAAAIAWgDqDAAABABZAC4ABAp/HQACAwAJCaEkUwcAMQMAAwAJCaEkUwcAMQMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgYJDgAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJDgAEAAYeAA==.',
Ay='Ayoade:BAECLgAFFH8UAAIFAAQJohTwCgA8AQRoDAAABQAzAGkMAAAFAD0AawwAAAUANADqDAAABQAtAAUABAmiFPAKADwBBGgMAAAFADMAaQwAAAUAPQBrDAAABQA0AOoMAAAFAC0ALgAECn8YAAMFAAgJaRydCgCMAgAFAAgJaRydCgCMAgAGAAIJERXjMQCHAAABLgAFFAgJKgAHAH0gAA==.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJMBH7aQBSAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICTAR+2kAUgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAIKAAUJawrlDgDHAAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACgAFCWsK5Q4AxwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkRAAsAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJCgAMALMWAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAINAAgJnhjsAgAoAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADQAICZ4Y7AIAKAIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LAACDQAJCWMgmAoA4AIADQAJCWMgmAoA4AIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIOAAYJqCJeDQD8AQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAOAAYJqCJeDQD8AQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg4ACQmQJRwCALsDAA4ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.Crustorc:BAEALgAECgcJCAABLgAECgYJEgABAAAAAA==.',
De='Deathhunterz:BAEALgAECgUJDAAAAA==.Demagogué:BAECLgAFFH8KAAMPAAYJfhOiJQDTAAZoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAQAKgAPAAQJ5guiJQDTAARrDAAAAQAJAGoMAAABACUAbQwAAAEAJwDqDAAABAAqAAcAAglvD8lJAIkAAmgMAAABABwAbAwAAAIAMgAuAAQKfx4AAw8ACAnvI30IALQCAA8ACAnvI30IALQCAAcABwnaGYs1AKoBAAEuAAUUBwkVAAUA8A4A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8KAAIMAAMJsxZNCACpAANoDAAABABGAGkMAAABABkA6gwAAAUATwAMAAMJsxZNCACpAANoDAAABABGAGkMAAABABkA6gwAAAUATwAuAAQKfy0AAgwACQkRIBIBAOYCAAwACQkRIBIBAOYCAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8LAAIQAAYJUiArBgA8AgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAQAAYJUiArBgA8AgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAuAAQKfxcAAxAACAmLIZwGAPMCABAACAmLIZwGAPMCABEAAQl/JgxeAG0AAAEuAAUUCAkqAAcAfSAA.Dubsy:BAECLgAFFH8qAAIHAAgJfSB/AAA2AghoDAAACQBQAGkMAAAJAF8AawwAAAYAWwBqDAAABwBjAGwMAAABAEMAbQwAAAEALADqDAAACABWAG4MAAABAGQABwAICX0gfwAANgIIaAwAAAkAUABpDAAACQBfAGsMAAAGAFsAagwAAAcAYwBsDAAAAQBDAG0MAAABACwA6gwAAAgAVgBuDAAAAQBkAC4ABAp/MgADBwAJCdAllgAAtAMABwAJCdAllgAAtAMADwADCfQiDDsAGQEAAAA=.',
Eh='Ehanee:BAEALgAFFAEJAQAAAA==.',
Er='Ereshin:BAEALgAECggJDwAAAA==.',
Ev='Evieari:BAECLgAFFH8WAAMSAAYJ8xfoBgCiAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgASAAUJZBnoBgCiAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAEwAFCVAM8hUAaQEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADEwAJCdYaEBgA5gEAEwAGCaYcEBgA5gEAEgAHCbkZmCkApQEAAS4ABRQDCQUAEgBKHwA=.Evielyssa:BAEALgAECgYJDwABLgAFFAMJBQASAEofAA==.Evierari:BAEBLgAFFH8FAAMSAAIJSh9fHQCgAAJoDAAAAwBQAGkMAAACAE8AEgACCUofXx0AoAACaAwAAAIAUABpDAAAAgBPABQAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8bAAMOAAUJkiTPCgB8AQVoDAAABwBiAGkMAAAHAGEAawwAAAUATgBqDAAAAgA3AOoMAAAGAGMADgAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABUABQndD58IACcBBWgMAAABACoAaQwAAAEAOgBrDAAAAQArAGoMAAABACQA6gwAAAEAEQAuAAQKfz8AAw4ACQkwJncCALQDAA4ACQkwJncCALQDABUABgmnHBsJALABAAAA.',
Fo='Fofer:BAEBLgAECn8iAAINAAcJkiUHCQCGAgdoDAAABwBhAGkMAAAHAF4AawwAAAcAYwBqDAAABABhAGwMAAAEAGIAbQwAAAEAWQDqDAAABABgAA0ABwmSJQcJAIYCB2gMAAAHAGEAaQwAAAcAXgBrDAAABwBjAGoMAAAEAGEAbAwAAAQAYgBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AFgBCHwA=.Foil:BAEALgADCgkJCQABLgAECgkJRAAXAFMlAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECggJDwABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8RAAMLAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAGAAFCZkOaTwACQEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAsAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwsACQmfIMQBAPwCAAsACAmzIsQBAPwCABgABgl+FkVGAJEBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8LAAIZAAMJACKIGAAjAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAZAAMJACKIGAAjAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAuAAQKfycAAxkACQk8IH8JAPkCABkACQk8IH8JAPkCABoAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIXAAMJSxSdKwDnAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAXAAMJSxSdKwDnAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJKgAHAH0gAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJGwAOAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAYALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIbAAkJWhbnCgASAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAbAAkJWhbnCgASAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIYAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAGAAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACGAAHCaElQRoAWQIAGAAHCaElQRoAWQIAAS4ABRQHCRUABQDwDgA=.',
Ke='Kelandrea:BAECLgAFFH8HAAIcAAIJ7AvMbgCUAAJoDAAAAwAWAOoMAAAEACYAHAACCewLzG4AlAACaAwAAAMAFgDqDAAABAAmAC4ABAp/HAAEHAAJCaEa2CIAngIAHAAJCaEa2CIAngIAHQACCdIQ94EAcAAAHgACCTMX/j0AQAAAAAA=.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAUAEobAA==.Kirkpriest:BAEBLgAECn8mAAIUAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAUAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJFgAfAKocAA==.',
Kr='Kregazi:BAECLgAFFH8JAAIWAAQJYhiYEAAqAQRoDAAAAwA7AGkMAAADAEMAawwAAAEAXADqDAAAAgAdABYABAliGJgQACoBBGgMAAADADsAaQwAAAMAQwBrDAAAAQBcAOoMAAACAB0ALgAECn8uAAIWAAkJlCIvBADUAgAWAAkJlCIvBADUAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8XAAISAAcJZiGCCwCGAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAgBVAGwMAAACAEAA6gwAAAMAWwBuDAAAAgBXABIABwlmIYILAIYCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAACAFUAbAwAAAIAQADqDAAAAwBbAG4MAAACAFcAAS4ABRQFCRgAGQBgIQA=.',
La='Larissaqt:BAECLgAFFH8cAAIUAAYJ0xKqCACVAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAUAAYJ0xKqCACVAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAuAAQKfyAAAhQACAnUIJIUAAQCABQACAnUIJIUAAQCAAAA.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8VAAIFAAcJ8A5wCADlAQdoDAAABAAwAGkMAAAEAEMAawwAAAQALQBqDAAAAgAmAGwMAAABAAoAbQwAAAEACADqDAAABQAxAAUABwnwDnAIAOUBB2gMAAAEADAAaQwAAAQAQwBrDAAABAAtAGoMAAACACYAbAwAAAEACgBtDAAAAQAIAOoMAAAFADEALgAECn8kAAQFAAgJiRxwCABFAgAFAAcJJSBwCABFAgACAAUJKBEqNwAbAQAGAAMJHBzfJwDiAAAAAA==.Maxxy:BAEBLgAECn8cAAIXAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAXAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMSAAQJ+A0KFAD3AARoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUABIABAldDQoUAPcABGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AEwACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADEwAICc4ZmQwAbgIAEwAICc4ZmQwAbgIAEgAECSYMg1wAwQAAAS4ABRQICSoABwB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgUJDAABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgANADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8SAAIcAAUJ6BOMKwA4AQVoDAAABQAzAGkMAAAEAD4AawwAAAMAOgBqDAAAAgAxAOoMAAAEAB8AHAAFCegTjCsAOAEFaAwAAAUAMwBpDAAABAA+AGsMAAADADoAagwAAAIAMQDqDAAABAAfAC4ABAp/PAACHAAJCVUhGxEAxAIAHAAJCVUhGxEAxAIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEALgAECgkJAgABLgAFFAIJBwAcAOwLAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAPAH8aAA==.Nixei:BAEBLgAECn8UAAIPAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYADwAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAISAAkJvSNFAwBEAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwASAAkJvSNFAwBEAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCQABLgAECggJDwABAAAAAA==.',
Pe='Personnelkid:BAEALgAECgYJBwABLgAECgkJPAASAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJBgABLgAFFAcJFQAFAPAOAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMNAAkJNhC6HACgAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwANAAkJ8Q66HACgAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwARAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQALACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8YAAIZAAUJYCE3DAB1AQVoDAAACABcAGkMAAAIAFUAawwAAAQARABqDAAAAQBdAOoMAAADAF4AGQAFCWAhNwwAdQEFaAwAAAgAXABpDAAACABVAGsMAAAEAEQAagwAAAEAXQDqDAAAAwBeAC4ABAp/PwADGQAJCYglvAMA7QIAGQAJCVklvAMA7QIAGgACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCwAZAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJDwABAAAAAA==.Shinthyr:BAEBLgAECn8VAAISAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABIABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICQ8AAQAAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgYJDgABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAQABLgAECgYJDgABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9EAAMXAAkJUyXxAADKAwloDAAACgBdAGkMAAAJAGIAawwAAAkAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAXAAkJUyXxAADKAwloDAAACABdAGkMAAAJAGIAawwAAAcAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAfAAIJhiFeUQCXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAINAAgJVhE3KABRAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADQAICVYRNygAUQEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBAkUABYAxiAA.',
Th='Therapygap:BAEBLgAECn8oAAQSAAgJgBLtIgCJAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABQAdAGwMAAAIADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgAEgAHCaYU7SIAiQEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAQAHQBsDAAABgA0AG0MAAABACMA6gwAAAUAPAAUAAYJKwrLTACsAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAATAAEJfANkbgAhAAFuDAAAAQAIAAEuAAQKCQk8ABIAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwAQAHYbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAcJFQAFAPAOAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJCgAMALMWAA==.',
Us='Usurah:BAECLgAFFH8YAAIcAAYJDBmgEQCRAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAcAAYJDBmgEQCRAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAuAAQKfysAAxwACQmAIsQJAEMDABwACQmAIsQJAEMDAB4ABQlYHOoWADsBAAAA.',
Vi='Vindh:BAECLgAFFH8PAAMYAAUJugduQwDxAAVoDAAABQAXAGkMAAADABUAawwAAAIACABqDAAAAQAJAOoMAAAEABgAGAAFCboHbkMA8QAFaAwAAAUAFwBpDAAAAwAVAGsMAAACAAgAagwAAAEACQDqDAAAAwAYAAsAAQkOBhYOACsAAeoMAAABAA8ALgAECn8oAAQYAAkJtxVdPQD/AQAYAAkJtxVdPQD/AQALAAIJOgOWKAA9AAAgAAEJAABPagAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIYAAkJshFbOADEAQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAYAAkJshFbOADEAQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
Ya='Yaav:BAEBLgAECn8XAAIOAAkJxhB8SQDDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAOAAkJxhB8SQDDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8WAAIfAAcJqhxXHAC4AQdoDAAABABKAGkMAAAEAFYAawwAAAMATwBqDAAAAgA7AGwMAAAEAEgA6gwAAAQAVABuDAAAAQAqAB8ABwmqHFccALgBB2gMAAAEAEoAaQwAAAQAVgBrDAAAAwBPAGoMAAACADsAbAwAAAQASADqDAAABABUAG4MAAABACoAAAA=.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhpMQQBCAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGkxBAEIBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx/KTQBNAgADAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8UAAIWAAQJxiDxCgBwAQRoDAAABwBbAGkMAAAGAEQAawwAAAMAXQDqDAAABABSABYABAnGIPEKAHABBGgMAAAHAFsAaQwAAAYARABrDAAAAwBdAOoMAAAEAFIALgAECn8lAAIWAAgJjiFpBAAFAwAWAAgJjiFpBAAFAwAAAA==.',
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
