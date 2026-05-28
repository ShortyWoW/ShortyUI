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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Holy','Rogue-Subtlety','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-27',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn84AAICAAkJgCIOBQD5AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQACAAkJgCIOBQD5AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQAAAA==.Algebra:BAECLgAFFH8VAAIDAAUJ6SStIQCqAQVoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAOoMAAAEAFkAAwAFCekkrSEAqgEFaAwAAAYAWwBpDAAABQBhAGsMAAAEAGMAagwAAAIAWgDqDAAABABZAC4ABAp/HQACAwAJCaEkEAgAJgMAAwAJCaEkEAgAJgMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJDgAEAOodAA==.',
Ay='Ayoade:BAECLgAFFH8ZAAIFAAUJ+RTxDwBpAQVoDAAABgAzAGkMAAAGAD0AawwAAAYATgBqDAAAAQAfAOoMAAAGAC0ABQAFCfkU8Q8AaQEFaAwAAAYAMwBpDAAABgA9AGsMAAAGAE4AagwAAAEAHwDqDAAABgAtAC4ABAp/GAADBQAICWkcnQoAjAIABQAICWkcnQoAjAIABgACCREV4zEAhwAAAS4ABRQICS8ABwB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJMBG4bgBOAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICTARuG4ATgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAIKAAUJawpHEQDDAAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACgAFCWsKRxEAwwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkRAAsAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDQAMAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAINAAgJnhiiAwAkAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADQAICZ4YogMAJAIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDQAJCRghOQoAeQIADQAJCRghOQoAeQIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIOAAYJqCI2EQDzAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAOAAYJqCI2EQDzAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg4ACQmQJRwCALsDAA4ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAQABLgAFFAMJBgAPAI8fAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJFgAFAEUNAA==.',
Cr='Crustome:BAEBLgAECn8aAAIQAAgJ0QfBIwBUAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEAAICdEHwSMAVAEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEALgAECgcJDgABLgAECggJGgAQANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAUJFQADAOkkAA==.',
De='Deathhunterz:BAEALgAECgYJDQAAAA==.Demagogué:BAECLgAFFH8MAAMRAAYJORWmGAAjAQZoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAUAQQARAAUJGxGmGAAjAQVoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBtDAAAAQAnAOoMAAAFAEEABwACCW8Pjk8AiQACaAwAAAEAHABsDAAAAgAyAC4ABAp/JAADEQAICfsjqAcAygIAEQAICfsjqAcAygIABwAHCZEcQC8A1gEAAS4ABRQICRYABQBFDQA=.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8NAAIMAAMJSx0bCQCoAANoDAAABQBGAGkMAAACAEoA6gwAAAYAUAAMAAMJSx0bCQCoAANoDAAABQBGAGkMAAACAEoA6gwAAAYAUAAuAAQKfy8AAgwACQmTIdIAAAUDAAwACQmTIdIAAAUDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8PAAISAAYJUiBwBwA2AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQASAAYJUiBwBwA2AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAuAAQKfxcAAxIACAmLIZwGAPMCABIACAmLIZwGAPMCABMAAQl/Jh5jAG0AAAEuAAUUCAkvAAcAfSAA.Dubsy:BAECLgAFFH8vAAIHAAgJfSB/AAA2AghoDAAACgBQAGkMAAAKAF8AawwAAAcAWwBqDAAACABjAGwMAAABAEMAbQwAAAEALADqDAAACQBWAG4MAAABAGQABwAICX0gfwAANgIIaAwAAAoAUABpDAAACgBfAGsMAAAHAFsAagwAAAgAYwBsDAAAAQBDAG0MAAABACwA6gwAAAkAVgBuDAAAAQBkAC4ABAp/MgADBwAJCdAllgAAtAMABwAJCdAllgAAtAMAEQADCfQi2T0AGQEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEALgAECggJEQAAAA==.',
Ev='Evieari:BAECLgAFFH8WAAMUAAYJ8xfRBwCcAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAUAAUJZBnRBwCcAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAFQAFCVAMQRgAXAEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADFQAJCdYacRgA5QEAFQAGCaYccRgA5QEAFAAHCbkZmCkApQEAAS4ABRQDCQUAFABKHwA=.Evielyssa:BAEALgAFFAQJBAABLgAFFAMJBQAUAEofAA==.Evierari:BAEBLgAFFH8FAAMUAAIJSh+vHgCdAAJoDAAAAwBQAGkMAAACAE8AFAACCUofrx4AnQACaAwAAAIAUABpDAAAAgBPABYAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8gAAMOAAUJkiTPCgB8AQVoDAAACABiAGkMAAAIAGEAawwAAAYATgBqDAAAAwA3AOoMAAAHAGMADgAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABcABQl3FncHAD8BBWgMAAACAC0AaQwAAAIAPABrDAAAAgA9AGoMAAACACQA6gwAAAIAPgAuAAQKfz8AAw4ACQkwJncCALQDAA4ACQkwJncCALQDABcABgmnHNwJAKgBAAAA.',
Fe='Felshins:BAEALgADCgMJAwABLgAECggJEQABAAAAAA==.',
Fo='Fofer:BAEBLgAECn8nAAINAAcJASY7CACZAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA0ABwkBJjsIAJkCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AGABCHwA=.Foil:BAEALgADCgkJEgABLgAECgkJRAAZAFMlAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJEQABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8RAAMLAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAGgAFCZkO7UAABAEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAsAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwsACQmfIMQBAPwCAAsACAmzIsQBAPwCABoABgl+FnpJAIwBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8LAAIQAAMJACLJGgAcAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAQAAMJACLJGgAcAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAuAAQKfycAAxAACQk8IH8JAPkCABAACQk8IH8JAPkCABsAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIZAAMJSxSGLgDmAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAZAAMJSxSGLgDmAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJLwAHAH0gAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJIAAOAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAaALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIcAAkJWhb4CwAKAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAcAAkJWhb4CwAKAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIaAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAGgAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACGgAHCaElvxsAVQIAGgAHCaElvxsAVQIAAS4ABRQICRYABQBFDQA=.',
Ke='Kelandrea:BAECLgAFFH8HAAIdAAIJ3gtbeACLAAJoDAAAAwAWAOoMAAAEACYAHQACCd4LW3gAiwACaAwAAAMAFgDqDAAABAAmAC4ABAp/HQAEHQAJCaEa2CIAngIAHQAJCaEa2CIAngIADwACCdIQ94EAcAAAHgACCTMXKEEAQAAAAS4ABRQDCQMAAQAAAAA=.',
Ki='Kitowatt:BAEALgAECgYJCgABLgAECggJHQAfAFcdAA==.',
Kr='Kregazi:BAECLgAFFH8JAAIYAAQJYhhmEgAmAQRoDAAAAwA7AGkMAAADAEMAawwAAAEAXADqDAAAAgAdABgABAliGGYSACYBBGgMAAADADsAaQwAAAMAQwBrDAAAAQBcAOoMAAACAB0ALgAECn8wAAIYAAkJyCJHBADXAgAYAAkJyCJHBADXAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIUAAcJZiFdDACDAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABQABwlmIV0MAIMCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCRgAEABgIQA=.',
La='Larissaqt:BAECLgAFFH8cAAIWAAYJ0xI3CgCJAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAWAAYJ0xI3CgCJAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAuAAQKfykAAhYACQneIUADABUDABYACQneIUADABUDAAAA.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8WAAIFAAgJRQ2cBgAWAghoDAAABAAwAGkMAAAEAEMAawwAAAQALQBqDAAAAgAmAGwMAAABAAoAbQwAAAEACADqDAAABQAxAG4MAAABAAQABQAICUUNnAYAFgIIaAwAAAQAMABpDAAABABDAGsMAAAEAC0AagwAAAIAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAUAMQBuDAAAAQAEAC4ABAp/JAAEBQAICYkc9AgARQIABQAHCSUg9AgARQIAAgAFCSgRKjcAGwEABgADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIZAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAZAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8KAAMUAAQJMBQrEQAZAQRoDAAAAwBFAGkMAAADADgAawwAAAIAPADqDAAAAgAUABQABAmWEysRABkBBGgMAAADAEUAaQwAAAIAOABrDAAAAgA8AOoMAAABAA0AFQACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADFQAICc4ZmQwAbgIAFQAICc4ZmQwAbgIAFAAECSYMg1wAwQAAAS4ABRQICS8ABwB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJDQABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgANADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8WAAIdAAUJ6BMHMQAsAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAgAxAOoMAAAFAB8AHQAFCegTBzEALAEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAIAMQDqDAAABQAfAC4ABAp/RAACHQAJCZMhPRAAzgIAHQAJCZMhPRAAzgIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEALgAFFAMJAwAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAARAH8aAA==.Nixei:BAEBLgAECn8UAAIRAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAEQAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAIUAAkJvSOkAwBAAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAUAAkJvSOkAwBAAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCQABLgAECggJEQABAAAAAA==.',
Pe='Personnelkid:BAEALgAECgYJBwABLgAECgkJPAAUAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDAABLgAFFAgJFgAFAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMNAAkJNhAnHgCcAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwANAAkJ8Q4nHgCcAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwATAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQALACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8YAAIQAAUJYCEsDgBvAQVoDAAACABcAGkMAAAIAFUAawwAAAQARABqDAAAAQBdAOoMAAADAF4AEAAFCWAhLA4AbwEFaAwAAAgAXABpDAAACABVAGsMAAAEAEQAagwAAAEAXQDqDAAAAwBeAC4ABAp/QQADEAAJCYglFAQA6AIAEAAJCVklFAQA6AIAGwACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCwAQAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Se='Serenytey:BAEALgAECgcJDQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJEQABAAAAAA==.Shinthyr:BAEBLgAECn8VAAIUAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABQABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICREAAQAAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9EAAMZAAkJUyUPAQDJAwloDAAACgBdAGkMAAAJAGIAawwAAAkAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAZAAkJUyUPAQDJAwloDAAACABdAGkMAAAJAGIAawwAAAcAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAfAAIJhiEVVQCXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAINAAgJVhHMKQBOAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADQAICVYRzCkATgEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkVABgAxiAA.',
Th='Therapygap:BAEBLgAECn8qAAQUAAgJHBPXIwCMAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABQAdAGwMAAAIADQAbQwAAAIALwDqDAAABwA8AG4MAAABAAgAFAAHCVcV1yMAjAEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAQAHQBsDAAABgA0AG0MAAACAC8A6gwAAAYAPAAWAAYJKwpVUQCZAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAVAAEJfAOXcwAhAAFuDAAAAQAIAAEuAAQKCQk8ABQAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwASAHYbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJFgAFAEUNAA==.',
Tw='Twomonk:BAEALgAECgIJAwABLgAFFAIJBgATAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDQAMAEsdAA==.',
Us='Usurah:BAECLgAFFH8ZAAIdAAcJcxXhDAC2AQdoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+AB0ABwlzFeEMALYBB2gMAAAGAE4AaQwAAAYAVgBrDAAAAwBBAGoMAAADADwAbAwAAAIAGwBtDAAAAQAIAOoMAAAEAD4ALgAECn8rAAMdAAkJgCLECQBDAwAdAAkJgCLECQBDAwAeAAUJWBwMGAA6AQAAAA==.',
Vi='Vindh:BAECLgAFFH8SAAMaAAUJugdGRwDvAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAGgAFCboHRkcA7wAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAAsAAQkOBlUPACsAAeoMAAABAA8ALgAECn8oAAQaAAkJtxVdPQD/AQAaAAkJtxVdPQD/AQALAAIJOgObKgA9AAAgAAEJAAAEcQAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIaAAkJshFgPAC6AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAaAAkJshFgPAC6AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJDgASADkdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIOAAkJxhDcTADDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAOAAkJxhDcTADDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8dAAIfAAgJVx0MEQA4AghoDAAABQBKAGkMAAAFAFYAawwAAAQAUABqDAAAAwA7AGwMAAAFAFMAbQwAAAEASgDqDAAABQBUAG4MAAABACoAHwAICVcdDBEAOAIIaAwAAAUASgBpDAAABQBWAGsMAAAEAFAAagwAAAMAOwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAQAqAAAA.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhqyRgBBAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGrJGAEEBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx/KTQBNAgADAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8VAAIYAAUJxiBQDABsAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAEAFIAGAAFCcYgUAwAbAEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABABSAC4ABAp/JQACGAAICY4haQQABQMAGAAICY4haQQABQMAAAA=.',
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
