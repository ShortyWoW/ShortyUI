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
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-28',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn86AAICAAkJgCIdBQD2AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQACAAkJgCIdBQD2AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQAAAA==.Algebra:BAECLgAFFH8aAAMDAAUJPSVNAAC4AQVoDAAABwBfAGkMAAAGAGEAawwAAAUAYwBqDAAAAwBaAOoMAAAFAFkAAwAFCcUkTQAAuAEFaAwAAAEAXwBpDAAAAQBfAGsMAAABAGEAagwAAAEAVADqDAAAAQBYAAQABQnpJIEiAKcBBWgMAAAGAFsAaQwAAAUAYQBrDAAABABjAGoMAAACAFoA6gwAAAQAWQAuAAQKfx0AAgQACQmhJEIIACUDAAQACQmhJEIIACUDAAAA.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJDgAFAOodAA==.',
Ay='Ayoade:BAECLgAFFH8ZAAIGAAUJ+RR6EABhAQVoDAAABgAzAGkMAAAGAD0AawwAAAYATgBqDAAAAQAfAOoMAAAGAC0ABgAFCfkUehAAYQEFaAwAAAYAMwBpDAAABgA9AGsMAAAGAE4AagwAAAEAHwDqDAAABgAtAC4ABAp/GAADBgAICWkcnQoAjAIABgAICWkcnQoAjAIABwACCREV4zEAhwAAAS4ABRQICS8ACAB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMJAAgJMBGubwBOAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACQAICTARrm8ATgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAoAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAILAAUJawpJEgC/AAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACwAFCWsKSRIAvwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkRAAwAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDQANAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAIOAAgJnhjoAwAhAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADgAICZ4Y6AMAIQIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDgAJCRghZAoAeQIADgAJCRghZAoAeQIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIPAAYJqCJPEgDxAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAPAAYJqCJPEgDxAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg8ACQmQJRwCALsDAA8ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAQABLgAFFAMJBgAQAI8fAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJFgAGAEUNAA==.',
Cr='Crustome:BAEBLgAECn8aAAIRAAgJ0QdEJABRAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEQAICdEHRCQAUQEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEALgAECgcJDgABLgAECggJGgARANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAUJGgADAD0lAA==.',
De='Deathhunterz:BAEALgAECgYJDQAAAA==.Demagogué:BAECLgAFFH8MAAMSAAYJORVxGQAhAQZoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAUAQQASAAUJGxFxGQAhAQVoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBtDAAAAQAnAOoMAAAFAEEACAACCW8PjFAAhwACaAwAAAEAHABsDAAAAgAyAC4ABAp/JgADEgAICfsjyQcAyQIAEgAICfsjyQcAyQIACAAHCZEc9y8A1QEAAS4ABRQICRYABgBFDQA=.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8NAAINAAMJSx0rBgAGAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAANAAMJSx0rBgAGAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAAuAAQKfy8AAg0ACQmTIdcAAAUDAA0ACQmTIdcAAAUDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8PAAITAAYJUiDKBwA0AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQATAAYJUiDKBwA0AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAuAAQKfxcAAxMACAmLIZwGAPMCABMACAmLIZwGAPMCABQAAQl/JjRkAG0AAAEuAAUUCAkvAAgAfSAA.Dubsy:BAECLgAFFH8vAAIIAAgJfSB/AAA2AghoDAAACgBQAGkMAAAKAF8AawwAAAcAWwBqDAAACABjAGwMAAABAEMAbQwAAAEALADqDAAACQBWAG4MAAABAGQACAAICX0gfwAANgIIaAwAAAoAUABpDAAACgBfAGsMAAAHAFsAagwAAAgAYwBsDAAAAQBDAG0MAAABACwA6gwAAAkAVgBuDAAAAQBkAC4ABAp/MgADCAAJCdAllgAAtAMACAAJCdAllgAAtAMAEgADCfQiiT4AGQEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEBLgAECn8VAAIIAAgJSB8uCwDqAghoDAAABABiAGkMAAADAGAAawwAAAQAWQBqDAAAAwBKAGwMAAACAE8AbQwAAAEAEgDqDAAAAgBWAG4MAAACAGAACAAICUgfLgsA6gIIaAwAAAQAYgBpDAAAAwBgAGsMAAAEAFkAagwAAAMASgBsDAAAAgBPAG0MAAABABIA6gwAAAIAVgBuDAAAAgBgAAAA.',
Ev='Evieari:BAECLgAFFH8WAAMVAAYJ8xf+BwCaAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAVAAUJZBn+BwCaAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAFgAFCVAM2RgAWgEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADFgAJCdYa4RgA5AEAFgAGCaYc4RgA5AEAFQAHCbkZmCkApQEAAS4ABRQGCQUAFQBKHwA=.Evielyssa:BAEALgAFFAQJBAABLgAFFAYJBQAVAEofAA==.Evierari:BAEBLgAFFH8FAAMVAAIJSh/aHgCdAAJoDAAAAwBQAGkMAAACAE8AFQACCUof2h4AnQACaAwAAAIAUABpDAAAAgBPABcAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8gAAMPAAUJkiTPCgB8AQVoDAAACABiAGkMAAAIAGEAawwAAAYATgBqDAAAAwA3AOoMAAAHAGMADwAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABgABQl3Fu0HADsBBWgMAAACAC0AaQwAAAIAPABrDAAAAgA9AGoMAAACACQA6gwAAAIAPgAuAAQKfz8AAw8ACQkwJncCALQDAA8ACQkwJncCALQDABgABgmnHCMKAKcBAAAA.',
Fe='Felshins:BAEALgADCgMJBgABLgAECggJFQAIAEgfAA==.',
Fo='Fofer:BAEBLgAECn8nAAIOAAcJASZaCACZAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA4ABwkBJloIAJkCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AGQBCHwA=.Foil:BAEALgADCgkJEgABLgAECgkJRAAaAFMlAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJFQAIAEgfAA==.',
Fu='Funkey:BAECLgAFFH8RAAMMAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAGwAFCZkOb0IAAgEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAwAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwwACQmfIMQBAPwCAAwACAmzIsQBAPwCABsABgl+FqdKAIwBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8MAAIRAAMJACJ5GwAZAQNoDAAABgBbAGkMAAACAE8A6gwAAAQAWgARAAMJACJ5GwAZAQNoDAAABgBbAGkMAAACAE8A6gwAAAQAWgAuAAQKfycAAxEACQk8IH8JAPkCABEACQk8IH8JAPkCABwAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIaAAMJSxRMLwDjAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAaAAMJSxRMLwDjAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJLwAIAH0gAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJIAAPAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAbALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIdAAkJWhY1DAAJAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAdAAkJWhY1DAAJAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIbAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAGwAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACGwAHCaElOxwAVAIAGwAHCaElOxwAVAIAAS4ABRQICRYABgBFDQA=.',
Ke='Kelandrea:BAECLgAFFH8HAAIeAAIJ3guXegCLAAJoDAAAAwAWAOoMAAAEACYAHgACCd4Ll3oAiwACaAwAAAMAFgDqDAAABAAmAC4ABAp/HQAEHgAJCaEa2CIAngIAHgAJCaEa2CIAngIAEAACCdIQ94EAcAAAHwACCTMX8UEAQAAAAS4ABRQDCQMAAQAAAAA=.',
Ki='Kitowatt:BAEALgAECgYJCgABLgAECggJHQAgAFcdAA==.',
Kr='Kregazi:BAECLgAFFH8JAAIZAAQJYhiKEwAcAQRoDAAAAwA7AGkMAAADAEMAawwAAAEAXADqDAAAAgAdABkABAliGIoTABwBBGgMAAADADsAaQwAAAMAQwBrDAAAAQBcAOoMAAACAB0ALgAECn8wAAIZAAkJyCJqBADWAgAZAAkJyCJqBADWAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIVAAcJZiGWDACCAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABUABwlmIZYMAIICB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCRsAEQBgIQA=.',
La='Larissaqt:BAECLgAFFH8gAAIXAAYJtxQQCQCXAQZoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAQAGwAXAAYJtxQQCQCXAQZoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAQAGwAuAAQKfykAAhcACQneIVUDABQDABcACQneIVUDABQDAAAA.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAAEAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8WAAIGAAgJRQ0HBwAOAghoDAAABAAwAGkMAAAEAEMAawwAAAQALQBqDAAAAgAmAGwMAAABAAoAbQwAAAEACADqDAAABQAxAG4MAAABAAQABgAICUUNBwcADgIIaAwAAAQAMABpDAAABABDAGsMAAAEAC0AagwAAAIAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAUAMQBuDAAAAQAEAC4ABAp/JAAEBgAICYkc+AgARQIABgAHCSUg+AgARQIAAgAFCSgRKjcAGwEABwADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIaAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAaAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8KAAMVAAQJMBSsEQAUAQRoDAAAAwBFAGkMAAADADgAawwAAAIAPADqDAAAAgAUABUABAmWE6wRABQBBGgMAAADAEUAaQwAAAIAOABrDAAAAgA8AOoMAAABAA0AFgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADFgAICc4ZmQwAbgIAFgAICc4ZmQwAbgIAFQAECSYMg1wAwQAAAS4ABRQICS8ACAB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJDQABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgAOADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAAEAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8WAAIeAAUJ6BNaMgAsAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAgAxAOoMAAAFAB8AHgAFCegTWjIALAEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAIAMQDqDAAABQAfAC4ABAp/RAACHgAJCZMhuBAAygIAHgAJCZMhuBAAygIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEALgAFFAMJAwAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAASAH8aAA==.Nixei:BAEBLgAECn8UAAISAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAEgAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAECLgAFFH8GAAIVAAQJ3hkKEAAnAQRoDAAAAgBIAGkMAAACAFEAawwAAAEAOgDqDAAAAQA0ABUABAneGQoQACcBBGgMAAACAEgAaQwAAAIAUQBrDAAAAQA6AOoMAAABADQALgAECn8eAAIVAAkJvSPIAwA+AwAVAAkJvSPIAwA+AwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCgABLgAECggJFQAIAEgfAA==.',
Pe='Personnelkid:BAEALgAECgYJCAABLgAECgkJPAAVAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIEAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUABAAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDAABLgAFFAgJFgAGAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMOAAkJNhCHHgCcAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAOAAkJ8Q6HHgCcAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAUAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQAMACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8bAAIRAAUJYCFdDgBxAQVoDAAACQBcAGkMAAAJAFUAawwAAAQARABqDAAAAQBdAOoMAAAEAF4AEQAFCWAhXQ4AcQEFaAwAAAkAXABpDAAACQBVAGsMAAAEAEQAagwAAAEAXQDqDAAABABeAC4ABAp/QQADEQAJCYglMgQA5gIAEQAJCVklMgQA5gIAHAACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJDAARAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Se='Serenytey:BAEALgAECgcJDQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJFQAIAEgfAA==.Shinthyr:BAEBLgAECn8VAAIVAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABUABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRUACABIHwA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9EAAMaAAkJUyUWAQDIAwloDAAACgBdAGkMAAAJAGIAawwAAAkAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAaAAkJUyUWAQDIAwloDAAACABdAGkMAAAJAGIAawwAAAcAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAgAAIJhiEAVgCXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAIOAAgJVhE8KgBOAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADgAICVYRPCoATgEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkVABkAxiAA.',
Th='Therapygap:BAEBLgAECn8qAAQVAAgJHBNHJACLAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABQAdAGwMAAAIADQAbQwAAAIALwDqDAAABwA8AG4MAAABAAgAFQAHCVcVRyQAiwEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAQAHQBsDAAABgA0AG0MAAACAC8A6gwAAAYAPAAXAAYJKwpoUgCYAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAWAAEJfAPfdAAhAAFuDAAAAQAIAAEuAAQKCQk8ABUAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwATAHYbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJFgAGAEUNAA==.',
Tw='Twomonk:BAEALgAFFAEJAQABLgAFFAIJBgAUAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDQANAEsdAA==.',
Us='Usurah:BAECLgAFFH8ZAAIeAAcJcxX4DQCwAQdoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+AB4ABwlzFfgNALABB2gMAAAGAE4AaQwAAAYAVgBrDAAAAwBBAGoMAAADADwAbAwAAAIAGwBtDAAAAQAIAOoMAAAEAD4ALgAECn8rAAMeAAkJgCLECQBDAwAeAAkJgCLECQBDAwAfAAUJWBx1GAA6AQAAAA==.',
Vi='Vindh:BAECLgAFFH8SAAMbAAUJugeeSADuAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAGwAFCboHnkgA7gAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAAwAAQkOBq8PACsAAeoMAAABAA8ALgAECn8oAAQbAAkJtxVdPQD/AQAbAAkJtxVdPQD/AQAMAAIJOgMjKwA9AAAhAAEJAADCcgAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIbAAkJshEqPQC6AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAbAAkJshEqPQC6AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJDwATADkdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIPAAkJxhAqTgDCAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAPAAkJxhAqTgDCAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8dAAIgAAgJVx1SEQA4AghoDAAABQBKAGkMAAAFAFYAawwAAAQAUABqDAAAAwA7AGwMAAAFAFMAbQwAAAEASgDqDAAABQBUAG4MAAABACoAIAAICVcdUhEAOAIIaAwAAAUASgBpDAAABQBWAGsMAAAEAFAAagwAAAMAOwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAQAqAAAA.',
Zh='Zhuröng:BAECLgAFFH8QAAIEAAQJnhqrSAA6AQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAQABAmeGqtIADoBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIEAAkJlx/KTQBNAgAEAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8VAAIZAAUJxiCMDABpAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAEAFIAGQAFCcYgjAwAaQEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABABSAC4ABAp/JQACGQAICY4haQQABQMAGQAICY4haQQABQMAAAA=.',
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
