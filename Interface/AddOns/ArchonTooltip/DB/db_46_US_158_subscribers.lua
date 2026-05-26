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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Rogue-Subtlety','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-26',data={Ad='Advvy:BAEALgAECgUJEQAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn84AAICAAkJgCICBQACAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQACAAkJgCICBQACAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQAAAA==.Algebra:BAECLgAFFH8VAAIDAAUJ6SSIIACsAQVoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAOoMAAAEAFkAAwAFCekkiCAArAEFaAwAAAYAWwBpDAAABQBhAGsMAAAEAGMAagwAAAIAWgDqDAAABABZAC4ABAp/HQACAwAJCaEk2QcALwMAAwAJCaEk2QcALwMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJDgAEAOodAA==.',
Ay='Ayoade:BAECLgAFFH8ZAAIFAAUJ+RR/DwByAQVoDAAABgAzAGkMAAAGAD0AawwAAAYATgBqDAAAAQAfAOoMAAAGAC0ABQAFCfkUfw8AcgEFaAwAAAYAMwBpDAAABgA9AGsMAAAGAE4AagwAAAEAHwDqDAAABgAtAC4ABAp/GAADBQAICWkcnQoAjAIABQAICWkcnQoAjAIABgACCREV4zEAhwAAAS4ABRQICSoABwB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJMBEebQBSAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICTARHm0AUgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAIKAAUJawp5EADGAAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACgAFCWsKeRAAxgAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkRAAsAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJCgAMALMWAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAINAAgJnhhqAwAnAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADQAICZ4YagMAJwIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LAACDQAJCWMgmAoA4AIADQAJCWMgmAoA4AIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIOAAYJqCLuDwD2AQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAOAAYJqCLuDwD2AQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg4ACQmQJRwCALsDAA4ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJFgAFAEUNAA==.',
Cr='Crustome:BAEBLgAECn8aAAIPAAgJ0QdOIwBUAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8ADwAICdEHTiMAVAEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEALgAECgcJDgABLgAECggJGgAPANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAUJFQADAOkkAA==.',
De='Deathhunterz:BAEALgAECgYJDQAAAA==.Demagogué:BAECLgAFFH8KAAMQAAYJfhMWKADRAAZoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAQAKgAQAAQJ5gsWKADRAARrDAAAAQAJAGoMAAABACUAbQwAAAEAJwDqDAAABAAqAAcAAglvDzdOAIkAAmgMAAABABwAbAwAAAIAMgAuAAQKfyQAAxAACAn7I4MHAMoCABAACAn7I4MHAMoCAAcABwmRHJguANcBAAEuAAUUCAkWAAUARQ0A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8KAAIMAAMJsxbsCACpAANoDAAABABGAGkMAAABABkA6gwAAAUATwAMAAMJsxbsCACpAANoDAAABABGAGkMAAABABkA6gwAAAUATwAuAAQKfy8AAgwACQmTIc0AAAYDAAwACQmTIc0AAAYDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8PAAIRAAYJUiAgBwA6AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQARAAYJUiAgBwA6AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAuAAQKfxcAAxEACAmLIZwGAPMCABEACAmLIZwGAPMCABIAAQl/JtRhAG0AAAEuAAUUCAkqAAcAfSAA.Dubsy:BAECLgAFFH8qAAIHAAgJfSB/AAA2AghoDAAACQBQAGkMAAAJAF8AawwAAAYAWwBqDAAABwBjAGwMAAABAEMAbQwAAAEALADqDAAACABWAG4MAAABAGQABwAICX0gfwAANgIIaAwAAAkAUABpDAAACQBfAGsMAAAGAFsAagwAAAcAYwBsDAAAAQBDAG0MAAABACwA6gwAAAgAVgBuDAAAAQBkAC4ABAp/MgADBwAJCdAllgAAtAMABwAJCdAllgAAtAMAEAADCfQiHT0AGQEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEALgAECggJEAAAAA==.',
Ev='Evieari:BAECLgAFFH8WAAMTAAYJ8xfBBwCgAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgATAAUJZBnBBwCgAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAFAAFCVAMjhcAZgEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADFAAJCdYawhgA5QEAFAAGCaYcwhgA5QEAEwAHCbkZmCkApQEAAS4ABRQDCQUAEwBKHwA=.Evielyssa:BAEALgAFFAQJBAABLgAFFAMJBQATAEofAA==.Evierari:BAEBLgAFFH8FAAMTAAIJSh/XHgCgAAJoDAAAAwBQAGkMAAACAE8AEwACCUof1x4AoAACaAwAAAIAUABpDAAAAgBPABUAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8gAAMOAAUJkiTPCgB8AQVoDAAACABiAGkMAAAIAGEAawwAAAYATgBqDAAAAwA3AOoMAAAHAGMADgAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABYABQl3Fh4HAEUBBWgMAAACAC0AaQwAAAIAPABrDAAAAgA9AGoMAAACACQA6gwAAAIAPgAuAAQKfz8AAw4ACQkwJncCALQDAA4ACQkwJncCALQDABYABgmnHKkJALABAAAA.',
Fe='Felshins:BAEALgADCgMJAwABLgAECggJEAABAAAAAA==.',
Fo='Fofer:BAEBLgAECn8nAAINAAcJASYeCACaAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA0ABwkBJh4IAJoCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AFwBCHwA=.Foil:BAEALgADCgkJEgABLgAECgkJRAAYAFMlAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJEAABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8RAAMLAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAGQAFCZkOzz8ABgEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAsAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwsACQmfIMQBAPwCAAsACAmzIsQBAPwCABkABgl+FsVIAJABAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8LAAIPAAMJACI3GgAfAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAPAAMJACI3GgAfAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAuAAQKfycAAw8ACQk8IH8JAPkCAA8ACQk8IH8JAPkCABoAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIYAAMJSxT0LQDmAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAYAAMJSxT0LQDmAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJKgAHAH0gAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJIAAOAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAZALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIbAAkJWhaSCwAOAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAbAAkJWhaSCwAOAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIZAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAGQAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACGQAHCaElSBsAWQIAGQAHCaElSBsAWQIAAS4ABRQICRYABQBFDQA=.',
Ke='Kelandrea:BAECLgAFFH8HAAIcAAIJ3gvydQCMAAJoDAAAAwAWAOoMAAAEACYAHAACCd4L8nUAjAACaAwAAAMAFgDqDAAABAAmAC4ABAp/HQAEHAAJCaEa2CIAngIAHAAJCaEa2CIAngIAHQACCdIQ94EAcAAAHgACCTMXYkAAQAAAAS4ABRQDCQMAAQAAAAA=.',
Ki='Kitowatt:BAEALgAECgYJCgABLgAECggJHQAfAFcdAA==.',
Kr='Kregazi:BAECLgAFFH8JAAIXAAQJYhj+EQAmAQRoDAAAAwA7AGkMAAADAEMAawwAAAEAXADqDAAAAgAdABcABAliGP4RACYBBGgMAAADADsAaQwAAAMAQwBrDAAAAQBcAOoMAAACAB0ALgAECn8uAAIXAAkJlCJ3BADSAgAXAAkJlCJ3BADSAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAITAAcJZiEVDACEAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABMABwlmIRUMAIQCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCRgADwBgIQA=.',
La='Larissaqt:BAECLgAFFH8cAAIVAAYJ0xLaCQCMAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAVAAYJ0xLaCQCMAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAuAAQKfykAAhUACQneIS0DACEDABUACQneIS0DACEDAAAA.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8WAAIFAAgJRQ0rBgAgAghoDAAABAAwAGkMAAAEAEMAawwAAAQALQBqDAAAAgAmAGwMAAABAAoAbQwAAAEACADqDAAABQAxAG4MAAABAAQABQAICUUNKwYAIAIIaAwAAAQAMABpDAAABABDAGsMAAAEAC0AagwAAAIAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAUAMQBuDAAAAQAEAC4ABAp/JAAEBQAICYkc1ggARQIABQAHCSUg1ggARQIAAgAFCSgRKjcAGwEABgADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIYAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAYAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMTAAQJ+A0iFQD3AARoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUABMABAldDSIVAPcABGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AFAACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADFAAICc4ZmQwAbgIAFAAICc4ZmQwAbgIAEwAECSYMg1wAwQAAAS4ABRQICSoABwB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJDQABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgANADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8SAAIcAAUJ6BPULwAuAQVoDAAABQAzAGkMAAAEAD4AawwAAAMAOgBqDAAAAgAxAOoMAAAEAB8AHAAFCegT1C8ALgEFaAwAAAUAMwBpDAAABAA+AGsMAAADADoAagwAAAIAMQDqDAAABAAfAC4ABAp/PwACHAAJCVUh4REAxAIAHAAJCVUh4REAxAIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEALgAFFAMJAwAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAQAH8aAA==.Nixei:BAEBLgAECn8UAAIQAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAEAAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAITAAkJvSOHAwBCAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwATAAkJvSOHAwBCAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCQABLgAECggJEAABAAAAAA==.',
Pe='Personnelkid:BAEALgAECgYJBwABLgAECgkJPAATAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDAABLgAFFAgJFgAFAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMNAAkJNhCpHQCfAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwANAAkJ8Q6pHQCfAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwASAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQALACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8YAAIPAAUJYCGdDQByAQVoDAAACABcAGkMAAAIAFUAawwAAAQARABqDAAAAQBdAOoMAAADAF4ADwAFCWAhnQ0AcgEFaAwAAAgAXABpDAAACABVAGsMAAAEAEQAagwAAAEAXQDqDAAAAwBeAC4ABAp/PwADDwAJCYgl+QMA6QIADwAJCVkl+QMA6QIAGgACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCwAPAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Se='Serenytey:BAEALgAECgcJDQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJEAABAAAAAA==.Shinthyr:BAEBLgAECn8VAAITAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABMABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRAAAQAAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9EAAMYAAkJUyUJAQDJAwloDAAACgBdAGkMAAAJAGIAawwAAAkAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAYAAkJUyUJAQDJAwloDAAACABdAGkMAAAJAGIAawwAAAcAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAfAAIJhiEcVACXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAINAAgJVhGGKQBPAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADQAICVYRhikATwEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkVABcAxiAA.',
Th='Therapygap:BAEBLgAECn8qAAQTAAgJHBMNJACIAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABQAdAGwMAAAIADQAbQwAAAIALwDqDAAABwA8AG4MAAABAAgAEwAHCVcVDSQAiAEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAQAHQBsDAAABgA0AG0MAAACAC8A6gwAAAYAPAAVAAYJKwrmTwCqAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAUAAEJfAPKcgAhAAFuDAAAAQAIAAEuAAQKCQk8ABMAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwARAHYbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJFgAFAEUNAA==.',
Tw='Twomonk:BAEALgAECgIJAwABLgAFFAIJBgASAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJCgAMALMWAA==.',
Us='Usurah:BAECLgAFFH8ZAAIcAAcJcxVRDAC4AQdoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+ABwABwlzFVEMALgBB2gMAAAGAE4AaQwAAAYAVgBrDAAAAwBBAGoMAAADADwAbAwAAAIAGwBtDAAAAQAIAOoMAAAEAD4ALgAECn8rAAMcAAkJgCLECQBDAwAcAAkJgCLECQBDAwAeAAUJWBzNFwA6AQAAAA==.',
Vi='Vindh:BAECLgAFFH8PAAMZAAUJugf1RgDuAAVoDAAABQAXAGkMAAADABUAawwAAAIACABqDAAAAQAJAOoMAAAEABgAGQAFCboH9UYA7gAFaAwAAAUAFwBpDAAAAwAVAGsMAAACAAgAagwAAAEACQDqDAAAAwAYAAsAAQkOBgMPACsAAeoMAAABAA8ALgAECn8oAAQZAAkJtxVdPQD/AQAZAAkJtxVdPQD/AQALAAIJOgMWKgA9AAAgAAEJAABZbwAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIZAAkJshFiOgDCAQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAZAAkJshFiOgDCAQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJCwARALgYAA==.',
Ya='Yaav:BAEBLgAECn8XAAIOAAkJxhAUTADDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAOAAkJxhAUTADDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8dAAIfAAgJVx3NEAA5AghoDAAABQBKAGkMAAAFAFYAawwAAAQAUABqDAAAAwA7AGwMAAAFAFMAbQwAAAEASgDqDAAABQBUAG4MAAABACoAHwAICVcdzRAAOQIIaAwAAAUASgBpDAAABQBWAGsMAAAEAFAAagwAAAMAOwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAQAqAAAA.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhp+RQBCAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGn5FAEIBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx/KTQBNAgADAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8VAAIXAAUJxiANDABtAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAEAFIAFwAFCcYgDQwAbQEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABABSAC4ABAp/JQACFwAICY4haQQABQMAFwAICY4haQQABQMAAAA=.',
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
