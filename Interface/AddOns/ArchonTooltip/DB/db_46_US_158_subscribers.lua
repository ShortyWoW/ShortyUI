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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Fire','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Holy','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Rogue-Assassination','Warrior-Arms','Mage-Arcane','Paladin-Retribution','Paladin-Protection','Druid-Balance','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-06-04',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8+AAICAAkJiCL6BAALAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAGAFYAbQwAAAUATQDqDAAACgBVAG4MAAAGAFoAbwwAAAQAXQACAAkJiCL6BAALAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAGAFYAbQwAAAUATQDqDAAACgBVAG4MAAAGAFoAbwwAAAQAXQAAAA==.Algebra:BAECLgAFFH8bAAMDAAYJwiSDAACoAQZoDAAABwBfAGkMAAAGAGEAawwAAAUAYwBqDAAAAwBaAGwMAAABAFkA6gwAAAUAWQAEAAYJfiQNGQADAgZoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAGwMAAABAFkA6gwAAAQAWQADAAUJxSSDAACoAQVoDAAAAQBfAGkMAAABAF8AawwAAAEAYQBqDAAAAQBUAOoMAAABAFgALgAECn8dAAIEAAkJoSSYCQAnAwAEAAkJoSSYCQAnAwAAAA==.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJFAAFAGweAA==.',
Ay='Ayoade:BAECLgAFFH8dAAIGAAUJ+RT3EgBMAQVoDAAABwAzAGkMAAAHAD0AawwAAAcATgBqDAAAAQAfAOoMAAAHAC0ABgAFCfkU9xIATAEFaAwAAAcAMwBpDAAABwA9AGsMAAAHAE4AagwAAAEAHwDqDAAABwAtAC4ABAp/GAADBgAICWkcnQoAjAIABgAICWkcnQoAjAIABwACCREV4zEAhwAAAS4ABRQICTQACAB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMJAAgJMBHjdQBIAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACQAICTAR43UASAEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAoAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAILAAUJawpsFgC3AAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACwAFCWsKbBYAtwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkSAAwAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDgANAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAIOAAgJnhhoBQAbAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADgAICZ4YaAUAGwIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDgAJCRghSgsAdgIADgAJCRghSgsAdgIAAAA=.Bonemommyxo:BAECLgAFFH8UAAIPAAYJEiMYCQCIAQZoDAAABQBhAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAPAAYJEiMYCQCIAQZoDAAABQBhAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg8ACQmQJRwCALsDAA8ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAgABLgAFFAMJCQAQANgfAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJGwAGAEUNAA==.',
Co='Coggettle:BAEALgADCgcJBwABLgAECggJKAARANMgAA==.',
Cr='Crustome:BAEBLgAECn8aAAISAAgJ0QeQJgBPAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEgAICdEHkCYATwEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEBLgAECn8XAAITAAkJigfLNABqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQATAAkJigfLNABqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQABLgAECggJGgASANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAYJGwADAMIkAA==.',
Da='Darkstrand:BAEALgADCgMJAwABLgAFFAMJDgANAEsdAA==.',
De='Deathhealher:BAEALgADCgEJAQABLgAECgYJFAAUAFgFAA==.Deathhunterz:BAEBLgAECn8UAAIUAAYJWAWxtACtAAZoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAACABEA6gwAAAMABgAUAAYJWAWxtACtAAZoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAACABEA6gwAAAMABgAAAA==.Demagogué:BAECLgAFFH8OAAMVAAcJFRWkEgBsAQdoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAYAQQBuDAAAAQA0ABUABgnCEaQSAGwBBmgMAAABAD0AawwAAAEACQBqDAAAAQAlAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0AAgAAwkaFbU7AOEAA2gMAAABABwAbAwAAAIAMgDqDAAAAQBTAC4ABAp/JwADFQAICfsjoQgAxgIAFQAICfsjoQgAxgIACAAHCZEcPTMA1AEAAS4ABRQICRsABgBFDQA=.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8OAAINAAMJSx0YBwAAAQNoDAAABQBGAGkMAAACAEoA6gwAAAcAUAANAAMJSx0YBwAAAQNoDAAABQBGAGkMAAACAEoA6gwAAAcAUAAuAAQKfzYAAg0ACQmeIowAADMDAA0ACQmeIowAADMDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8UAAIWAAYJUiCUCgAmAgZoDAAABABTAGkMAAAEAGAAawwAAAUAXABqDAAAAgBUAGwMAAACAC4A6gwAAAMAXQAWAAYJUiCUCgAmAgZoDAAABABTAGkMAAAEAGAAawwAAAUAXABqDAAAAgBUAGwMAAACAC4A6gwAAAMAXQAuAAQKfxcAAxYACAmLIZwGAPMCABYACAmLIZwGAPMCABcAAQl/JuNqAGsAAAEuAAUUCAk0AAgAfSAA.Dubsy:BAECLgAFFH80AAIIAAgJfSB/AAA2AghoDAAACwBQAGkMAAALAF8AawwAAAgAWwBqDAAACQBjAGwMAAABAEMAbQwAAAEALADqDAAACgBWAG4MAAABAGQACAAICX0gfwAANgIIaAwAAAsAUABpDAAACwBfAGsMAAAIAFsAagwAAAkAYwBsDAAAAQBDAG0MAAABACwA6gwAAAoAVgBuDAAAAQBkAC4ABAp/MwADCAAJCdAllgAAtAMACAAJCdAllgAAtAMAFQAECbUjmSsAhwEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Ei='Eibm:BAEALgAECgEJAQAAAA==.',
Er='Ereshin:BAEBLgAECn8YAAIIAAgJXB8dDADsAghoDAAABQBjAGkMAAADAGAAawwAAAQAWQBqDAAAAwBKAGwMAAACAE8AbQwAAAEAEgDqDAAAAwBYAG4MAAADAGAACAAICVwfHQwA7AIIaAwAAAUAYwBpDAAAAwBgAGsMAAAEAFkAagwAAAMASgBsDAAAAgBPAG0MAAABABIA6gwAAAMAWABuDAAAAwBgAAAA.',
Ev='Evieari:BAECLgAFFH8WAAMYAAYJ8xcjCgCMAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAYAAUJZBkjCgCMAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAGQAFCVAMGB0AQwEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADGQAJCdYaahsA4gEAGQAGCaYcahsA4gEAGAAHCbkZmCkApQEAAS4ABRQGCQUAGABKHwA=.Evielyssa:BAEBLgAFFH8JAAIYAAUJGRIQDwBHAQVoDAAAAgAZAGkMAAACACUAawwAAAIAMQBqDAAAAQBMAOoMAAACACoAGAAFCRkSEA8ARwEFaAwAAAIAGQBpDAAAAgAlAGsMAAACADEAagwAAAEATADqDAAAAgAqAAEuAAUUBgkFABgASh8A.Evierari:BAEBLgAFFH8FAAMYAAIJSh/QIQCZAAJoDAAAAwBQAGkMAAACAE8AGAACCUof0CEAmQACaAwAAAIAUABpDAAAAgBPABoAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8mAAMPAAYJkyQRFQADAgZoDAAACQBiAGkMAAAJAGEAawwAAAcAWgBqDAAABABVAGwMAAABAFEA6gwAAAgAYwAPAAYJkyQRFQADAgZoDAAABwBiAGkMAAAHAGEAawwAAAUAWgBqDAAAAgBVAGwMAAABAFEA6gwAAAUAYwAbAAUJtBaiCQA4AQVoDAAAAgAtAGkMAAACADwAawwAAAIAPQBqDAAAAgAkAOoMAAADAEAALgAECn8/AAMPAAkJMCZ3AgC0AwAPAAkJMCZ3AgC0AwAbAAYJpxyVCwCrAQAAAA==.',
Fe='Felshins:BAEALgADCgMJBgABLgAECggJGAAIAFwfAA==.',
Fo='Fofer:BAEBLgAECn8nAAIOAAcJASYQCQCYAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA4ABwkBJhAJAJgCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AHABCHwA=.Foil:BAEALgADCgkJGwABLgAECgkJTQAdAFslAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJGAAIAFwfAA==.',
Fs='Fshi:BAEALgAECgYJAwAAAA==.',
Fu='Funkey:BAECLgAFFH8SAAMMAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAgAWAOoMAAAEACYAFAAFCZkOlkoA+QAFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAIAFgDqDAAABAAmAAwAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwwACQmfIMQBAPwCAAwACAmzIsQBAPwCABQABgl+FqJPAIkBAAAA.',
Gr='Greatares:BAEALgAFFAMJAwAAAA==.Greathades:BAEALgAECgkJAgABLgAFFAMJAwABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAFFAMJAwABAAAAAA==.Greatodin:BAEALgAECgkJBAABLgAFFAMJAwABAAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAFFAMJAwABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAFFAMJAwABAAAAAA==.Grummel:BAECLgAFFH8NAAISAAMJACI0HwAOAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgASAAMJACI0HwAOAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgAuAAQKfycAAxIACQk8IH8JAPkCABIACQk8IH8JAPkCAB4AAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIdAAMJSxQdNADWAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAdAAMJSxQdNADWAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJNAAIAH0gAA==.',
Hr='Hrtenjoyer:BAEBLgAECn8YAAIXAAkJ4R3qBgDRAgloDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAABABaAGwMAAAEAE8AbQwAAAEAUgDqDAAAAgBaAG4MAAACAFQAbwwAAAEAHQAXAAkJ4R3qBgDRAgloDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAABABaAGwMAAAEAE8AbQwAAAEAUgDqDAAAAgBaAG4MAAACAFQAbwwAAAEAHQABLgAFFAUJDAAPAMIcAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAYJJgAPAJMkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAUALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIfAAkJWhZcDQAFAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAfAAkJWhZcDQAFAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIUAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAFAAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACFAAHCaEl/h0AVQIAFAAHCaEl/h0AVQIAAS4ABRQICRsABgBFDQA=.',
Ja='Jail:BAEBLgAECn8oAAMgAAkJJCJLAAAuAwloDAAABwBhAGkMAAAFAF4AawwAAAYARwBqDAAABABcAGwMAAAEAF8AbQwAAAMAUgDqDAAABQBgAG4MAAAEAGIAbwwAAAIAPgAgAAkJJCJLAAAuAwloDAAABQBhAGkMAAAEAF4AawwAAAQARwBqDAAAAwBcAGwMAAADAF8AbQwAAAIAUgDqDAAAAwBgAG4MAAACAGIAbwwAAAEAPgAEAAkJbRWvOQApAgloDAAAAgA4AGkMAAABADwAawwAAAIAMQBqDAAAAQBEAGwMAAABACMAbQwAAAEAMwDqDAAAAgBMAG4MAAACAEAAbwwAAAEALQAAAA==.',
Ka='Katestinks:BAECLgAFFH8MAAMPAAUJwhyHMACEAQVoDAAAAwBZAGkMAAADAFkAawwAAAIAEgBqDAAAAQAJAOoMAAADAGEADwAECcIchzAAhAEEaAwAAAMAWQBpDAAAAwBZAGsMAAACABIA6gwAAAMAYQAcAAEJAABBWgAAAAFqDAAAAQAJAC4ABAp/KwADDwAJCdAjeAUASQMADwAJCdAjeAUASQMAHAABCbYKsVkAKgAAAAA=.',
Ke='Kelandrea:BAECLgAFFH8IAAIhAAMJ2w9gYQDYAANoDAAAAwAWAGkMAAABAD0A6gwAAAQAJgAhAAMJ2w9gYQDYAANoDAAAAwAWAGkMAAABAD0A6gwAAAQAJgAuAAQKfx0ABCEACQmhGtgiAJ4CACEACQmhGtgiAJ4CABAAAgnSEPeBAHAAACIAAgkzF+tFAEAAAAAA.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAaAEobAA==.Kirkpriest:BAEBLgAECn8mAAIaAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAaAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECggJJQAjAGQfAA==.',
Kr='Kregazi:BAECLgAFFH8MAAIcAAQJYhjLFQAeAQRoDAAABAA7AGkMAAAEAEMAawwAAAEAXADqDAAAAwAdABwABAliGMsVAB4BBGgMAAAEADsAaQwAAAQAQwBrDAAAAQBcAOoMAAADAB0ALgAECn8xAAIcAAkJyCIpBQDPAgAcAAkJyCIpBQDPAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIYAAcJZiHEDQB5AgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABgABwlmIcQNAHkCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCR8AEgD5IQA=.',
La='Larissaqt:BAECLgAFFH8jAAIaAAcJthUpBgDxAQdoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAUAUABuDAAAAgAPABoABwm2FSkGAPEBB2gMAAAHAFMAaQwAAAYASgBrDAAABwAdAGoMAAAGACAAbAwAAAIAMQDqDAAABQBQAG4MAAACAA8ALgAECn8yAAIaAAkJDiOOAgA9AwAaAAkJDiOOAgA9AwAAAA==.',
Li='Lilylock:BAEALgAECgEJAQABLgAECgkJHQATABcdAA==.Lilyweave:BAEBLgAECn8dAAQTAAkJFx02EwBPAgloDAAAAwBLAGkMAAAEAFcAawwAAAQAVwBqDAAABQBiAGwMAAAEAFEAbQwAAAMAPQDqDAAAAgBaAG4MAAADAD4AbwwAAAEAMQATAAkJFx02EwBPAgloDAAAAgBLAGkMAAADAFcAawwAAAQAVwBqDAAABQBiAGwMAAADAFEAbQwAAAMAPQDqDAAAAgBaAG4MAAADAD4AbwwAAAEAMQAkAAIJDQ88PQBjAAJoDAAAAQAYAGkMAAABADQAHwABCTcMwkIAMwABbAwAAAEAHwAAAA==.Lioshi:BAEALgAECgYJCQABLgAFFAQJEwAEAOEbAA==.',
Ma='Maildaddy:BAECLgAFFH8bAAIGAAgJRQ1lCQD2AQhoDAAABQAwAGkMAAAFAEMAawwAAAUALQBqDAAAAwAmAGwMAAABAAoAbQwAAAEACADqDAAABgAxAG4MAAABAAQABgAICUUNZQkA9gEIaAwAAAUAMABpDAAABQBDAGsMAAAFAC0AagwAAAMAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAYAMQBuDAAAAQAEAC4ABAp/JAAEBgAICYkcfAkARQIABgAHCSUgfAkARQIAAgAFCSgRKjcAGwEABwADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8PAAMYAAQJyhqoDwA/AQRoDAAABABFAGkMAAAEADgAawwAAAMAPADqDAAABABXABgABAnKGqgPAD8BBGgMAAAEAEUAaQwAAAMAOABrDAAAAwA8AOoMAAADAFcAGQACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADGQAICc4ZmQwAbgIAGQAICc4ZmQwAbgIAGAAECSYMg1wAwQAAAS4ABRQICTQACAB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJFAAUAFgFAA==.Merarite:BAEALgAFFAIJAgAAAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEwAEAOEbAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8XAAIhAAUJ6BNsOwAmAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAwAxAOoMAAAFAB8AIQAFCegTbDsAJgEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAMAMQDqDAAABQAfAC4ABAp/SwACIQAJCc0hXQkAFAMAIQAJCc0hXQkAFAMAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEBLgAFFH8FAAIhAAMJihRJVQDvAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQAhAAMJihRJVQDvAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQABLgAFFAMJCAAhANsPAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAVAH8aAA==.Nixei:BAEBLgAECn8UAAIVAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAFQAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAECLgAFFH8KAAIYAAQJeRtpDwBCAQRoDAAAAwBOAGkMAAADAFEAawwAAAIAOgDqDAAAAgA+ABgABAl5G2kPAEIBBGgMAAADAE4AaQwAAAMAUQBrDAAAAgA6AOoMAAACAD4ALgAECn8eAAIYAAkJvSNeBAA0AwAYAAkJvSNeBAA0AwAAAA==.',
['Ní']='Nítedragon:BAEALgAECgEJAQABLgAECgcJFAAGAFAgAA==.',
Ow='Owlenjoyer:BAECLgAFFH8GAAIjAAMJRxWRKgDFAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAjAAMJRxWRKgDFAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAuAAQKfx8AAiMACQmGGiEMAIYCACMACQmGGiEMAIYCAAEuAAUUBQkMAA8AwhwA.',
Pa='Palashin:BAEBLgAECn8UAAIQAAYJCR5MHQALAgZoDAAABABgAGkMAAAEAEwAawwAAAQAVABqDAAAAwBHAGwMAAABADAA6gwAAAQAUwAQAAYJCR5MHQALAgZoDAAABABgAGkMAAAEAEwAawwAAAQAVABqDAAAAwBHAGwMAAABADAA6gwAAAQAUwABLgAECggJGAAIAFwfAA==.',
Pe='Personnelkid:BAEALgAECgcJDQABLgAECgkJPwAYAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIEAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUABAAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDgABLgAFFAgJGwAGAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMOAAkJNhBAIACaAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAOAAkJ8Q5AIACaAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAXAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAABLgAFFAIJAgABAAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEgAMACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8fAAISAAUJ+SHfEABsAQVoDAAACQBcAGkMAAAJAFUAawwAAAYASgBqDAAAAwBdAOoMAAAEAF4AEgAFCfkh3xAAbAEFaAwAAAkAXABpDAAACQBVAGsMAAAGAEoAagwAAAMAXQDqDAAABABeAC4ABAp/QQADEgAJCYglvgQA4QIAEgAJCVklvgQA4QIAHgACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJDQASAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Se='Serenytey:BAEALgAECgcJDQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJGAAIAFwfAA==.Shinthyr:BAEBLgAECn8YAAIYAAcJ5R4eFQA0AgdoDAAABQBTAGkMAAAEAFUAawwAAAQAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABgABwnlHh4VADQCB2gMAAAFAFMAaQwAAAQAVQBrDAAABABdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRgACABcHwA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9NAAMdAAkJWyU8AQDHAwloDAAACwBdAGkMAAAKAGIAawwAAAoAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAdAAkJWyU8AQDHAwloDAAACQBdAGkMAAAKAGIAawwAAAgAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAjAAIJhiGgWgCXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAIOAAgJVhFULABMAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADgAICVYRVCwATAEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkWABwA6CAA.',
Th='Therapygap:BAEBLgAECn8wAAQYAAgJHBMiJQCLAQhoDAAACABMAGkMAAAJADwAawwAAAUANwBqDAAABgAdAGwMAAAJADQAbQwAAAMALwDqDAAABwA8AG4MAAABAAgAGAAHCVcVIiUAiwEHaAwAAAUATABpDAAABQA8AGsMAAAEADcAagwAAAUAHQBsDAAABwA0AG0MAAADAC8A6gwAAAYAPAAaAAYJKwqEVgCpAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAZAAEJfAPBfQAhAAFuDAAAAQAIAAEuAAQKCQk/ABgAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAgJFwAWAKQaAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJGwAGAEUNAA==.',
Tw='Twomonk:BAEALgAFFAEJAQABLgAFFAIJBgAXAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDgANAEsdAA==.',
Us='Usurah:BAECLgAFFH8aAAIhAAgJvBSyCgD4AQhoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+AG4MAAABACoAIQAICbwUsgoA+AEIaAwAAAYATgBpDAAABgBWAGsMAAADAEEAagwAAAMAPABsDAAAAgAbAG0MAAABAAgA6gwAAAQAPgBuDAAAAQAqAC4ABAp/KwADIQAJCYAixAkAQwMAIQAJCYAixAkAQwMAIgAFCVgcCRoAOAEAAAA=.',
Vi='Vindh:BAECLgAFFH8SAAMUAAUJugflUADlAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAFAAFCboH5VAA5QAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAAwAAQkOBq4RACkAAeoMAAABAA8ALgAECn8oAAQUAAkJtxVdPQD/AQAUAAkJtxVdPQD/AQAMAAIJOgPSLQA9AAAlAAEJAAA6fAAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIUAAkJshELQAC8AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAUAAkJshELQAC8AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJEAAWAFsdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIPAAkJxhAmUwDAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAPAAkJxhAmUwDAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8lAAMjAAgJZB+pDQBxAghoDAAABgBTAGkMAAAGAFYAawwAAAUAUABqDAAABABLAGwMAAAGAFMAbQwAAAIASgDqDAAABgBUAG4MAAACAEYAIwAICWQfqQ0AcQIIaAwAAAYAUwBpDAAABgBWAGsMAAAFAFAAagwAAAQASwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAgBGAB0AAwmYCWmWAHgAA2wMAAABACIAbQwAAAEAHQDqDAAAAQAJAAAA.',
Zh='Zhuröng:BAECLgAFFH8TAAIEAAQJ4Rs/RABOAQRoDAAABgBVAGkMAAAGAE4AawwAAAQAKgDqDAAAAwBPAAQABAnhGz9EAE4BBGgMAAAGAFUAaQwAAAYATgBrDAAABAAqAOoMAAADAE8ALgAECn8nAAIEAAkJrh/KTQBNAgAEAAkJrh/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8WAAIcAAUJ6CDmDgBoAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAFAFQAHAAFCegg5g4AaAEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABQBUAC4ABAp/JQACHAAICY4haQQABQMAHAAICY4haQQABQMAAAA=.',
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
