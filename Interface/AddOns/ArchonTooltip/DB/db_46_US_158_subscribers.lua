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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Fire','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Holy','Rogue-Subtlety','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-29',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn86AAICAAkJgCI2BQD1AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQACAAkJgCI2BQD1AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQAAAA==.Algebra:BAECLgAFFH8aAAMDAAUJPSViAAC0AQVoDAAABwBfAGkMAAAGAGEAawwAAAUAYwBqDAAAAwBaAOoMAAAFAFkAAwAFCcUkYgAAtAEFaAwAAAEAXwBpDAAAAQBfAGsMAAABAGEAagwAAAEAVADqDAAAAQBYAAQABQnpJIEkAKQBBWgMAAAGAFsAaQwAAAUAYQBrDAAABABjAGoMAAACAFoA6gwAAAQAWQAuAAQKfx0AAgQACQmhJHYIACQDAAQACQmhJHYIACQDAAAA.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJDgAFAOodAA==.',
Ay='Ayoade:BAECLgAFFH8ZAAIGAAUJ+RTzEABfAQVoDAAABgAzAGkMAAAGAD0AawwAAAYATgBqDAAAAQAfAOoMAAAGAC0ABgAFCfkU8xAAXwEFaAwAAAYAMwBpDAAABgA9AGsMAAAGAE4AagwAAAEAHwDqDAAABgAtAC4ABAp/GAADBgAICWkcnQoAjAIABgAICWkcnQoAjAIABwACCREV4zEAhwAAAS4ABRQICS8ACAB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMJAAgJMBFkcQBLAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACQAICTARZHEASwEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAoAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAILAAUJawonEwC/AAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACwAFCWsKJxMAvwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkSAAwAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDQANAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAIOAAgJnhgzBAAfAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADgAICZ4YMwQAHwIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDgAJCRghmAoAeAIADgAJCRghmAoAeAIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIPAAYJqCK6EwDuAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAPAAYJqCK6EwDuAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg8ACQmQJRwCALsDAA8ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAQABLgAFFAMJBgAQAI8fAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJFgAGAEUNAA==.',
Cr='Crustome:BAEBLgAECn8aAAIRAAgJ0Qe3JABRAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEQAICdEHtyQAUQEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEALgAECgcJDgABLgAECggJGgARANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAUJGgADAD0lAA==.',
De='Deathhunterz:BAEALgAECgYJDgAAAA==.Demagogué:BAECLgAFFH8NAAMSAAcJFRVBDwB4AQdoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0ABIABgnCEUEPAHgBBmgMAAABAD0AawwAAAEACQBqDAAAAQAlAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0AAgAAglvDwlTAIQAAmgMAAABABwAbAwAAAIAMgAuAAQKfycAAxIACAn7I+UHAMoCABIACAn7I+UHAMoCAAgABwmRHI4wANUBAAEuAAUUCAkWAAYARQ0A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8NAAINAAMJSx1RBgACAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAANAAMJSx1RBgACAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAAuAAQKfy8AAg0ACQmTIdoAAAQDAA0ACQmTIdoAAAQDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8PAAITAAYJUiBOCAAvAgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQATAAYJUiBOCAAvAgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAuAAQKfxcAAxMACAmLIZwGAPMCABMACAmLIZwGAPMCABQAAQl/JmplAG0AAAEuAAUUCAkvAAgAfSAA.Dubsy:BAECLgAFFH8vAAIIAAgJfSB/AAA2AghoDAAACgBQAGkMAAAKAF8AawwAAAcAWwBqDAAACABjAGwMAAABAEMAbQwAAAEALADqDAAACQBWAG4MAAABAGQACAAICX0gfwAANgIIaAwAAAoAUABpDAAACgBfAGsMAAAHAFsAagwAAAgAYwBsDAAAAQBDAG0MAAABACwA6gwAAAkAVgBuDAAAAQBkAC4ABAp/MwADCAAJCdAllgAAtAMACAAJCdAllgAAtAMAEgAECbUjqikAhwEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEBLgAECn8VAAIIAAgJSB9vCwDpAghoDAAABABiAGkMAAADAGAAawwAAAQAWQBqDAAAAwBKAGwMAAACAE8AbQwAAAEAEgDqDAAAAgBWAG4MAAACAGAACAAICUgfbwsA6QIIaAwAAAQAYgBpDAAAAwBgAGsMAAAEAFkAagwAAAMASgBsDAAAAgBPAG0MAAABABIA6gwAAAIAVgBuDAAAAgBgAAAA.',
Ev='Evieari:BAECLgAFFH8WAAMVAAYJ8xeCCACSAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAVAAUJZBmCCACSAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAFgAFCVAMwxkAUwEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADFgAJCdYaRxkA5AEAFgAGCaYcRxkA5AEAFQAHCbkZmCkApQEAAS4ABRQGCQUAFQBKHwA=.Evielyssa:BAEALgAFFAQJBAABLgAFFAYJBQAVAEofAA==.Evierari:BAEBLgAFFH8FAAMVAAIJSh9LHwCbAAJoDAAAAwBQAGkMAAACAE8AFQACCUofSx8AmwACaAwAAAIAUABpDAAAAgBPABcAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8gAAMPAAUJkiTPCgB8AQVoDAAACABiAGkMAAAIAGEAawwAAAYATgBqDAAAAwA3AOoMAAAHAGMADwAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABgABQl3FnAIADsBBWgMAAACAC0AaQwAAAIAPABrDAAAAgA9AGoMAAACACQA6gwAAAIAPgAuAAQKfz8AAw8ACQkwJncCALQDAA8ACQkwJncCALQDABgABgmnHJQJAKYBAAAA.',
Fe='Felshins:BAEALgADCgMJBgABLgAECggJFQAIAEgfAA==.',
Fo='Fofer:BAEBLgAECn8nAAIOAAcJASaBCACZAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA4ABwkBJoEIAJkCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AGQBCHwA=.Foil:BAEALgADCgkJEgABLgAECgkJTQAaAFslAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJFQAIAEgfAA==.',
Fu='Funkey:BAECLgAFFH8SAAMMAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAgAWAOoMAAAEACYAGwAFCZkOLEQA/gAFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAIAFgDqDAAABAAmAAwAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwwACQmfIMQBAPwCAAwACAmzIsQBAPwCABsABgl+FuxKAIsBAAAA.',
Gr='Greatares:BAEALgAECgkJCQAAAA==.Greathades:BAEALgAECgkJAgABLgAECgkJCQABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJCQABAAAAAA==.Greatodin:BAEALgAECgkJBAABLgAECgkJCQABAAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAECgkJCQABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJCQABAAAAAA==.Grummel:BAECLgAFFH8NAAIRAAMJACJQHAAVAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgARAAMJACJQHAAVAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgAuAAQKfycAAxEACQk8IH8JAPkCABEACQk8IH8JAPkCABwAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIaAAMJSxTLMADbAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAaAAMJSxTLMADbAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJLwAIAH0gAA==.',
Hr='Hrtenjoyer:BAEALgAECgcJEQABLgAFFAQJCAAPAJQaAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJIAAPAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAbALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIdAAkJWhZwDAAIAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAdAAkJWhZwDAAIAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIbAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAGwAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACGwAHCaElpxwAUwIAGwAHCaElpxwAUwIAAS4ABRQICRYABgBFDQA=.',
Ka='Katestinks:BAECLgAFFH8IAAIPAAQJlBr9NwBgAQRoDAAAAgBXAGkMAAACAFMAawwAAAEABADqDAAAAwBhAA8ABAmUGv03AGABBGgMAAACAFcAaQwAAAIAUwBrDAAAAQAEAOoMAAADAGEALgAECn8jAAMPAAkJ9iJQBgA3AwAPAAkJ9iJQBgA3AwAZAAEJtgpjVQAqAAAAAA==.',
Ke='Kelandrea:BAECLgAFFH8HAAIeAAIJ3gspfgCHAAJoDAAAAwAWAOoMAAAEACYAHgACCd4LKX4AhwACaAwAAAMAFgDqDAAABAAmAC4ABAp/HQAEHgAJCaEa2CIAngIAHgAJCaEa2CIAngIAEAACCdIQ94EAcAAAHwACCTMXqEIAQAAAAS4ABRQDCQUAHgDVFAA=.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAXAEobAA==.Kirkpriest:BAEBLgAECn8mAAIXAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAXAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECggJHQAgAFcdAA==.',
Kr='Kregazi:BAECLgAFFH8MAAIZAAQJYhjpEgAlAQRoDAAABAA7AGkMAAAEAEMAawwAAAEAXADqDAAAAwAdABkABAliGOkSACUBBGgMAAAEADsAaQwAAAQAQwBrDAAAAQBcAOoMAAADAB0ALgAECn8wAAIZAAkJyCKcBADUAgAZAAkJyCKcBADUAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIVAAcJZiHNDAB/AgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABUABwlmIc0MAH8CB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCR0AEQD5IQA=.',
La='Larissaqt:BAECLgAFFH8hAAIXAAcJ0hHhBQDeAQdoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAQAGwBuDAAAAQAIABcABwnSEeEFAN4BB2gMAAAHAFMAaQwAAAYASgBrDAAABwAdAGoMAAAGACAAbAwAAAIAMQDqDAAABAAbAG4MAAABAAgALgAECn8pAAIXAAkJ3iFtAwATAwAXAAkJ3iFtAwATAwAAAA==.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAAEAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8WAAIGAAgJRQ1oBwANAghoDAAABAAwAGkMAAAEAEMAawwAAAQALQBqDAAAAgAmAGwMAAABAAoAbQwAAAEACADqDAAABQAxAG4MAAABAAQABgAICUUNaAcADQIIaAwAAAQAMABpDAAABABDAGsMAAAEAC0AagwAAAIAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAUAMQBuDAAAAQAEAC4ABAp/JAAEBgAICYkcFAkARQIABgAHCSUgFAkARQIAAgAFCSgRKjcAGwEABwADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIaAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAaAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8KAAMVAAQJMBQ3EgAQAQRoDAAAAwBFAGkMAAADADgAawwAAAIAPADqDAAAAgAUABUABAmWEzcSABABBGgMAAADAEUAaQwAAAIAOABrDAAAAgA8AOoMAAABAA0AFgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADFgAICc4ZmQwAbgIAFgAICc4ZmQwAbgIAFQAECSYMg1wAwQAAAS4ABRQICS8ACAB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJDgABAAAAAA==.Merarite:BAEALgAECgkJEAABLgAECgkJNgAOADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAAEAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8XAAIeAAUJ6BNdNAAoAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAwAxAOoMAAAFAB8AHgAFCegTXTQAKAEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAMAMQDqDAAABQAfAC4ABAp/RAACHgAJCZMh4BEAwgIAHgAJCZMh4BEAwgIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEBLgAFFH8FAAIeAAMJ1RRGTADzAANoDAAAAgAuAGkMAAABAB4A6gwAAAIAUgAeAAMJ1RRGTADzAANoDAAAAgAuAGkMAAABAB4A6gwAAAIAUgAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAASAH8aAA==.Nixei:BAEBLgAECn8UAAISAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAEgAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAECLgAFFH8GAAIVAAQJ3hlTEAAlAQRoDAAAAgBIAGkMAAACAFEAawwAAAEAOgDqDAAAAQA0ABUABAneGVMQACUBBGgMAAACAEgAaQwAAAIAUQBrDAAAAQA6AOoMAAABADQALgAECn8eAAIVAAkJvSPgAwA8AwAVAAkJvSPgAwA8AwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJFAAGAFAgAA==.',
Ow='Owlenjoyer:BAECLgAFFH8GAAIgAAMJRxUJJwDGAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAgAAMJRxUJJwDGAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAuAAQKfx8AAiAACQmGGjQLAIsCACAACQmGGjQLAIsCAAEuAAUUBAkIAA8AlBoA.',
Pa='Palashin:BAEALgAECgYJDwABLgAECggJFQAIAEgfAA==.',
Pe='Personnelkid:BAEALgAECgYJCAABLgAECgkJPAAVAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIEAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUABAAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDAABLgAFFAgJFgAGAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMOAAkJNhDoHgCbAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAOAAkJ8Q7oHgCbAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAUAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEgAMACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8dAAIRAAUJ+SF7DgBzAQVoDAAACQBcAGkMAAAJAFUAawwAAAUASgBqDAAAAgBdAOoMAAAEAF4AEQAFCfkhew4AcwEFaAwAAAkAXABpDAAACQBVAGsMAAAFAEoAagwAAAIAXQDqDAAABABeAC4ABAp/QQADEQAJCYglSgQA5QIAEQAJCVklSgQA5QIAHAACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJDQARAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJFQAIAEgfAA==.Shinthyr:BAEBLgAECn8YAAIVAAcJ5R4eFQA0AgdoDAAABQBTAGkMAAAEAFUAawwAAAQAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABUABwnlHh4VADQCB2gMAAAFAFMAaQwAAAQAVQBrDAAABABdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRUACABIHwA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9NAAMaAAkJWyUVAQDKAwloDAAACwBdAGkMAAAKAGIAawwAAAoAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAaAAkJWyUVAQDKAwloDAAACQBdAGkMAAAKAGIAawwAAAgAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAgAAIJhiHKVgCXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAIOAAgJVhGqKgBNAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADgAICVYRqioATQEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkVABkAxiAA.',
Th='Therapygap:BAEBLgAECn8wAAQVAAgJHBN8IwCRAQhoDAAACABMAGkMAAAJADwAawwAAAUANwBqDAAABgAdAGwMAAAJADQAbQwAAAMALwDqDAAABwA8AG4MAAABAAgAFQAHCVcVfCMAkQEHaAwAAAUATABpDAAABQA8AGsMAAAEADcAagwAAAUAHQBsDAAABwA0AG0MAAADAC8A6gwAAAYAPAAXAAYJKwoZUwCYAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAWAAEJfAMgdgAhAAFuDAAAAQAIAAEuAAQKCQk8ABUAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAgJFwATAKQaAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJFgAGAEUNAA==.',
Tw='Twomonk:BAEALgAFFAEJAQABLgAFFAIJBgAUAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDQANAEsdAA==.',
Us='Usurah:BAECLgAFFH8ZAAIeAAcJcxUfDwCtAQdoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+AB4ABwlzFR8PAK0BB2gMAAAGAE4AaQwAAAYAVgBrDAAAAwBBAGoMAAADADwAbAwAAAIAGwBtDAAAAQAIAOoMAAAEAD4ALgAECn8rAAMeAAkJgCLECQBDAwAeAAkJgCLECQBDAwAfAAUJWBzAGAA5AQAAAA==.',
Vi='Vindh:BAECLgAFFH8SAAMbAAUJugdYSgDqAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAGwAFCboHWEoA6gAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAAwAAQkOBgcQACsAAeoMAAABAA8ALgAECn8oAAQbAAkJtxVdPQD/AQAbAAkJtxVdPQD/AQAMAAIJOgOAKwA9AAAhAAEJAAAhdAAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIbAAkJshGPPgC1AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAbAAkJshGPPgC1AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJDwATADkdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIPAAkJxhAkTwDBAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAPAAkJxhAkTwDBAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8dAAIgAAgJVx2MEQA3AghoDAAABQBKAGkMAAAFAFYAawwAAAQAUABqDAAAAwA7AGwMAAAFAFMAbQwAAAEASgDqDAAABQBUAG4MAAABACoAIAAICVcdjBEANwIIaAwAAAUASgBpDAAABQBWAGsMAAAEAFAAagwAAAMAOwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAQAqAAAA.',
Zh='Zhuröng:BAECLgAFFH8QAAIEAAQJnhoESwA3AQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAQABAmeGgRLADcBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIEAAkJlx/KTQBNAgAEAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8VAAIZAAUJxiAuDQBmAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAEAFIAGQAFCcYgLg0AZgEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABABSAC4ABAp/JQACGQAICY4haQQABQMAGQAICY4haQQABQMAAAA=.',
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
