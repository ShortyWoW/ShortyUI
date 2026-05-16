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

local lookup = {'Druid-Restoration','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Havoc','Warlock-Destruction','Shaman-Elemental','DemonHunter-Devourer','Priest-Discipline','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Paladin-Protection','Priest-Shadow','Evoker-Augmentation','DemonHunter-Vengeance','Hunter-BeastMastery',}
local provider = {region='US',realm='Smolderthorn',name='US',type='daily',zone=46,date='2026-05-14',data={Ac='Achoo:BAAALgAECgQJBwAAAA==.',
Ai='Aitnd:BAAALgADCggJDgAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Al='Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJBQABADAOAA==.Amongor:BAABLgAECn8YAAICAAYJ3h95UAAAAgZoDAAABABUAGkMAAAEAFoAawwAAAQAUABqDAAABABaAGwMAAAEAEcA6gwAAAQAUQACAAYJ3h95UAAAAgZoDAAABABUAGkMAAAEAFoAawwAAAQAUABqDAAABABaAGwMAAAEAEcA6gwAAAQAUQAAAA==.',
An='Anarisa:BAABLgAECn8tAAMDAAkJyRMvLwAIAgloDAAABwA8AGkMAAAGAD0AawwAAAYANwBqDAAABQBKAGwMAAAEADMAbQwAAAMAJQDqDAAABwAyAG4MAAAFAEYAbwwAAAIAEQADAAkJyRMvLwAIAgloDAAABAA8AGkMAAADAD0AawwAAAMANwBqDAAAAwBKAGwMAAAEADMAbQwAAAMAJQDqDAAABQAyAG4MAAAFAEYAbwwAAAIAEQAEAAUJcRGGCwAeAQVoDAAAAwA2AGkMAAADACwAawwAAAMAMwBqDAAAAgAkAOoMAAACABsAAAA=.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAUJHAAFANkfAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgMJBAAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIDAAcJkBelaQADAgdoDAAABABPAGkMAAADAEcAawwAAAMAQABqDAAAAwBYAGwMAAADADQAbQwAAAEAGgDqDAAAAwBDAAMABwmQF6VpAAMCB2gMAAAEAE8AaQwAAAMARwBrDAAAAwBAAGoMAAADAFgAbAwAAAMANABtDAAAAQAaAOoMAAADAEMAAS4ABRQDCQUAAQAwDgA=.Averse:BAACLgAFFH8GAAICAAMJXBbaXADwAANoDAAAAwBBAGkMAAACAFYA6gwAAAEAEwACAAMJXBbaXADwAANoDAAAAwBBAGkMAAACAFYA6gwAAAEAEwAuAAQKfysAAgIACAlEIDgWAHMCAAIACAlEIDgWAHMCAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECggJAwABLgAFFAIJBgAGABsLAA==.Barley:BAAALgAECgEJAQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepid:BAABLgAECn89AAMHAAkJuyM7BgA6AgloDAAACABjAGkMAAAIAGMAawwAAAkAYABqDAAACABgAGwMAAAHAF4AbQwAAAUAXQDqDAAACQBgAG4MAAAFAEMAbwwAAAIAVAAHAAYJUSE7BgA6AgZpDAAABwBjAGsMAAAHAGAAbAwAAAYAXgBtDAAAAwBEAG4MAAAFAEMAbwwAAAIAVAAIAAcJsSLVKQASAgdoDAAACABjAGkMAAABAFoAawwAAAIATQBqDAAACABgAGwMAAABAEsAbQwAAAIAXQDqDAAACQBgAAAA.',
Bl='Bluetide:BAACLgAFFH8cAAIFAAUJ2R8CBwDHAQVoDAAABwBdAGkMAAAHAEQAawwAAAUAQABqDAAAAwBaAOoMAAAGAFsABQAFCdkfAgcAxwEFaAwAAAcAXQBpDAAABwBEAGsMAAAFAEAAagwAAAMAWgDqDAAABgBbAC4ABAp/KQACBQAJCY4mHAAA7wMABQAJCY4mHAAA7wMAAAA=.',
Br='Brokemav:BAABLgAECn8vAAIJAAcJESGWAgCTAgdoDAAACABaAGkMAAAIAFsAawwAAAgAXwBqDAAABwBhAGwMAAAGAFAAbQwAAAMAPgDqDAAABwBWAAkABwkRIZYCAJMCB2gMAAAIAFoAaQwAAAgAWwBrDAAACABfAGoMAAAHAGEAbAwAAAYAUABtDAAAAwA+AOoMAAAHAFYAAAA=.Brooklin:BAABLgAECn8yAAIDAAkJnh5mHABnAgloDAAABwBfAGkMAAAHAFgAawwAAAUAVABqDAAABgBFAGwMAAAGAFIAbQwAAAUAWgDqDAAABwBPAG4MAAAFAC8AbwwAAAIAOwADAAkJnh5mHABnAgloDAAABwBfAGkMAAAHAFgAawwAAAUAVABqDAAABgBFAGwMAAAGAFIAbQwAAAUAWgDqDAAABwBPAG4MAAAFAC8AbwwAAAIAOwAAAA==.',
Bu='Busky:BAABLgAECn8fAAMFAAkJAhVaKwDfAQloDAAABQAoAGkMAAAFAD4AawwAAAUAQABqDAAABABJAGwMAAADACgAbQwAAAIANQDqDAAABAA7AG4MAAACAEIAbwwAAAEAFwAFAAkJAhVaKwDfAQloDAAABQAoAGkMAAAFAD4AawwAAAUAQABqDAAABABJAGwMAAADACgAbQwAAAIANQDqDAAABAA7AG4MAAABAEIAbwwAAAEAFwAKAAEJtROzIgA9AAFuDAAAAQAyAAAA.',
Ca='Carboncredit:BAABLgAECn8iAAIKAAkJrBAICgAyAgloDAAABQApAGkMAAAEADUAawwAAAQAPgBqDAAABAA4AGwMAAAEADAAbQwAAAQAHQDqDAAABAAuAG4MAAAEACoAbwwAAAEADwAKAAkJrBAICgAyAgloDAAABQApAGkMAAAEADUAawwAAAQAPgBqDAAABAA4AGwMAAAEADAAbQwAAAQAHQDqDAAABAAuAG4MAAAEACoAbwwAAAEADwAAAA==.Cassiopea:BAABLgAECn8YAAILAAcJ7BzUEAAEAgdoDAAABQBDAGkMAAAFAF0AawwAAAMAPwBqDAAAAgA4AGwMAAACAFsAbQwAAAEAOgDqDAAABgBWAAsABwnsHNQQAAQCB2gMAAAFAEMAaQwAAAUAXQBrDAAAAwA/AGoMAAACADgAbAwAAAIAWwBtDAAAAQA6AOoMAAAGAFYAAAA=.Caysia:BAABLgAFFH8FAAIBAAMJMA73KQDGAANoDAAAAgAwAGkMAAABABcA6gwAAAIAJQABAAMJMA73KQDGAANoDAAAAgAwAGkMAAABABcA6gwAAAIAJQAAAA==.',
Ce='Cellcept:BAAALgAECgUJCwAAAA==.',
Ch='Chareth:BAABLgAECn8lAAIDAAkJjgmDTAChAQloDAAABgAkAGkMAAAGACAAawwAAAYAIABqDAAAAwAaAGwMAAADABYAbQwAAAIABADqDAAABQAaAG4MAAAFABMAbwwAAAEAFQADAAkJjgmDTAChAQloDAAABgAkAGkMAAAGACAAawwAAAYAIABqDAAAAwAaAGwMAAADABYAbQwAAAIABADqDAAABQAaAG4MAAAFABMAbwwAAAEAFQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chinchillada:BAAALgAECgUJDwAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECggJFQAMAAMeAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJAgAAAA==.',
Da='Dabajabaza:BAABLgAECn8iAAINAAgJBwmwHQAEAQhoDAAABQAaAGkMAAAGACQAawwAAAYAGwBqDAAABQAOAGwMAAAEAAwAbQwAAAEABQDqDAAABgAnAG4MAAABAA0ADQAICQcJsB0ABAEIaAwAAAUAGgBpDAAABgAkAGsMAAAGABsAagwAAAUADgBsDAAABAAMAG0MAAABAAUA6gwAAAYAJwBuDAAAAQANAAAA.Dabergerak:BAACLgAFFH8GAAIIAAMJXCHeFgAbAQNoDAAAAwBYAGkMAAACAFAA6gwAAAEAVgAIAAMJXCHeFgAbAQNoDAAAAwBYAGkMAAACAFAA6gwAAAEAVgAuAAQKfysAAggACQmbJYwAAHADAAgACQmbJYwAAHADAAAA.Daenys:BAAALgAECgMJAwABLgAFFAcJJAAJAM0YAA==.Daggart:BAAALgAECgkJCAAAAA==.Dakrus:BAACLgAFFH8FAAIOAAMJmg0pEwDzAANoDAAAAwAtAGkMAAABAB4A6gwAAAEAHAAOAAMJmg0pEwDzAANoDAAAAwAtAGkMAAABAB4A6gwAAAEAHAAuAAQKfyMAAw8ACQnLFlIgACMCAA8ACAmpFlIgACMCAA4ABgloCoUgACgBAAAA.Dawin:BAAALgAECgEJAQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAAALgAECgYJEwABLgAECgkJNwAMALIdAA==.Deeiinndu:BAAALgADCgMJCQAAAA==.Dejanira:BAABLgAECn8gAAIBAAkJzhFWLQCVAQloDAAABAAwAGkMAAAEAC8AawwAAAQAUwBqDAAAAwA6AGwMAAAEADMAbQwAAAMAKgDqDAAABgAtAG4MAAADABgAbwwAAAEACAABAAkJzhFWLQCVAQloDAAABAAwAGkMAAAEAC8AawwAAAQAUwBqDAAAAwA6AGwMAAAEADMAbQwAAAMAKgDqDAAABgAtAG4MAAADABgAbwwAAAEACAAAAA==.Demonslayerr:BAAALgADCgMJAwAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAQAAAAAA==.',
Di='Diddily:BAAALgAECgcJEgAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8UAAIRAAYJfgaNPQAHAQZoDAAABwARAGkMAAAEABcAawwAAAIAEQBqDAAAAgARAGwMAAACAAsA6gwAAAMADAARAAYJfgaNPQAHAQZoDAAABwARAGkMAAAEABcAawwAAAIAEQBqDAAAAgARAGwMAAACAAsA6gwAAAMADAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAINAAkJNxaHCwDvAQloDAAABgBCAGkMAAAFAEsAawwAAAUAPgBqDAAABAAuAGwMAAAEADUAbQwAAAMAIQDqDAAABAA1AG4MAAAEAFEAbwwAAAEAHAANAAkJNxaHCwDvAQloDAAABgBCAGkMAAAFAEsAawwAAAUAPgBqDAAABAAuAGwMAAAEADUAbQwAAAMAIQDqDAAABAA1AG4MAAAEAFEAbwwAAAEAHAAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8aAAIIAAkJxwpvHgCZAQloDAAABAASAGkMAAAEABsAawwAAAQAJgBqDAAAAwASAGwMAAADABwAbQwAAAIAHwDqDAAAAwAeAG4MAAACABgAbwwAAAEAFAAIAAkJxwpvHgCZAQloDAAABAASAGkMAAAEABsAawwAAAQAJgBqDAAAAwASAGwMAAADABwAbQwAAAIAHwDqDAAAAwAeAG4MAAACABgAbwwAAAEAFAAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQAAAA==.Elise:BAABLgAECn8kAAMSAAkJQhckCQAvAgloDAAABQBXAGkMAAAFAEUAawwAAAUAPgBqDAAABAAkAGwMAAAEAEwAbQwAAAIAEADqDAAABgBMAG4MAAAEACUAbwwAAAEAMQASAAgJzBckCQAvAghoDAAAAwBXAGkMAAADAEUAawwAAAMAPgBqDAAAAwAkAGwMAAADAEwAbQwAAAIAEADqDAAAAwBMAG4MAAACACUACQAICQER+A4AQQEIaAwAAAIANgBpDAAAAgAXAGsMAAACADcAagwAAAEABgBsDAAAAQAUAOoMAAADAD8AbgwAAAIAJABvDAAAAQAxAAAA.Elstrid:BAABLgAECn8VAAIMAAgJAx43PAAcAghoDAAAAwBUAGkMAAAEAFMAawwAAAMATABqDAAAAwBVAGwMAAADAFEAbQwAAAEAOgDqDAAAAwBYAG4MAAABAEEADAAICQMeNzwAHAIIaAwAAAMAVABpDAAABABTAGsMAAADAEwAagwAAAMAVQBsDAAAAwBRAG0MAAABADoA6gwAAAMAWABuDAAAAQBBAAAA.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgADCgcJDAABLgAECgkJMQATACMlAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn8xAAITAAkJIyUBAQBeAwloDAAABwBiAGkMAAAHAGMAawwAAAcAYwBqDAAABgBjAGwMAAAGAGIAbQwAAAQAYQDqDAAABwBiAG4MAAAEAFEAbwwAAAEAVgATAAkJIyUBAQBeAwloDAAABwBiAGkMAAAHAGMAawwAAAcAYwBqDAAABgBjAGwMAAAGAGIAbQwAAAQAYQDqDAAABwBiAG4MAAAEAFEAbwwAAAEAVgAAAA==.',
Fe='Felbourn:BAABLgAECn8ZAAMRAAgJhCGOCADZAghoDAAABQBaAGkMAAAEAFoAawwAAAQAWgBqDAAAAgAoAGwMAAABAF4AbQwAAAEASADqDAAABgBgAG4MAAACAEIAEQAICYQhjggA2QIIaAwAAAUAWgBpDAAABABaAGsMAAADAFoAagwAAAIAKABsDAAAAQBeAG0MAAABAEgA6gwAAAUAYABuDAAAAgBCABQAAgm7CW/MAF0AAmsMAAABABoA6gwAAAEAFwAAAA==.Fendraim:BAAALgAECgQJBAABLgAECgcJCgAQAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAABLgAECn9DAAIGAAkJPiHoBQAMAwloDAAACgBhAGkMAAAKAFsAawwAAAkAWgBqDAAACQBVAGwMAAAHAFgAbQwAAAUAQwDqDAAACQBaAG4MAAAGAGEAbwwAAAIAOAAGAAkJPiHoBQAMAwloDAAACgBhAGkMAAAKAFsAawwAAAkAWgBqDAAACQBVAGwMAAAHAFgAbQwAAAUAQwDqDAAACQBaAG4MAAAGAGEAbwwAAAIAOAAAAA==.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgQJBQAAAA==.',
Ge='Gemini:BAAALgADCgcJDAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIDAAUJawSqSQASAQVoDAAAAQAPAGkMAAABAA8AawwAAAEABABqDAAAAQANAOoMAAABAAkAAwAFCWsEqkkAEgEFaAwAAAEADwBpDAAAAQAPAGsMAAABAAQAagwAAAEADQDqDAAAAQAJAAEuAAUUBgkPABUAzAYA.',
Gn='Gnarfok:BAAALgAECgQJDgAAAA==.',
Go='Goopster:BAAALgADCgcJCQAAAA==.',
Gr='Graamps:BAAALgAECgUJCAAAAA==.Gravedigger:BAABLgAECn8wAAINAAkJ2h8iBACtAgloDAAABgBEAGkMAAAHAF8AawwAAAgAXwBqDAAABgBWAGwMAAAGAFgAbQwAAAMAPgDqDAAABwBWAG4MAAAEAEIAbwwAAAEAWQANAAkJ2h8iBACtAgloDAAABgBEAGkMAAAHAF8AawwAAAgAXwBqDAAABgBWAGwMAAAGAFgAbQwAAAMAPgDqDAAABwBWAG4MAAAEAEIAbwwAAAEAWQAAAA==.',
Gu='Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgEJAQABLgAECgUJBQAQAAAAAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
In='Inarios:BAABLgAECn8fAAMVAAgJ/h3DBgCzAghoDAAABQBbAGkMAAAFAGEAawwAAAYAVABqDAAABABVAGwMAAAEAFQAbQwAAAEAOQDqDAAABQBIAG4MAAABACgAFQAICf4dwwYAswIIaAwAAAUAWwBpDAAABQBhAGsMAAAGAFQAagwAAAQAVQBsDAAABABUAG0MAAABADkA6gwAAAQASABuDAAAAQAoAAsAAQm3DCxYACsAAeoMAAABACAAAAA=.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGQAWAHEYAA==.Ironnmonk:BAABLgAECn8ZAAQWAAkJcRiBGwAnAgloDAAABQBNAGkMAAADAD0AawwAAAMASQBqDAAAAgArAGwMAAADAD4AbQwAAAIAPADqDAAAAwA8AG4MAAADAFYAbwwAAAEAEQAWAAkJcRiBGwAnAgloDAAABABNAGkMAAADAD0AawwAAAMASQBqDAAAAgArAGwMAAACAD4AbQwAAAIAPADqDAAAAwA8AG4MAAADAFYAbwwAAAEAEQAXAAEJihFLaAA2AAFsDAAAAQAsABgAAQlSBDB1ABwAAWgMAAABAAsAAAA=.',
Ja='Javlin:BAAALgAECgEJAgAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECggJFQAMAAMeAA==.',
Ju='Jujufya:BAAALgADCgYJBgABLgAECgcJDAAQAAAAAA==.Jujukni:BAAALgAECgMJAwABLgAECgcJDAAQAAAAAA==.Jujumon:BAAALgAECgcJDAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECgcJDAAQAAAAAA==.Justimp:BAABLgAECn8iAAIMAAkJOxPNKQDfAQloDAAABQBBAGkMAAAEAD0AawwAAAQAMgBqDAAABABEAGwMAAAFAEYAbQwAAAQAKQDqDAAABABDAG4MAAADABUAbwwAAAEADgAMAAkJOxPNKQDfAQloDAAABQBBAGkMAAAEAD0AawwAAAQAMgBqDAAABABEAGwMAAAFAEYAbQwAAAQAKQDqDAAABABDAG4MAAADABUAbwwAAAEADgAAAA==.',
Ka='Kanon:BAAALgAECgYJCwAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8FAAIZAAMJ2gQIIwCuAANoDAAAAgAIAGkMAAACABYA6gwAAAEABQAZAAMJ2gQIIwCuAANoDAAAAgAIAGkMAAACABYA6gwAAAEABQAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAIUAAcJlA6icgBNAQdoDAAABwAzAGkMAAAGACkAawwAAAQALQBqDAAABQAmAGwMAAADACAA6gwAAAUAIABuDAAAAQAUABQABwmUDqJyAE0BB2gMAAAHADMAaQwAAAYAKQBrDAAABAAtAGoMAAAFACYAbAwAAAMAIADqDAAABQAgAG4MAAABABQAAAA=.Konviction:BAABLgAECn8fAAMGAAkJ/RFcSQCLAQloDAAABQA3AGkMAAAFAEEAawwAAAQAQABqDAAAAwATAGwMAAADACEAbQwAAAEAEwDqDAAABwA8AG4MAAACADEAbwwAAAEAEwAGAAkJ/RFcSQCLAQloDAAABQA3AGkMAAAFAEEAawwAAAQAQABqDAAAAwATAGwMAAACACEAbQwAAAEAEwDqDAAABgA8AG4MAAACADEAbwwAAAEAEwAaAAIJZwLNPgAdAAJsDAAAAQAIAOoMAAABAAMAAAA=.',
Kr='Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAAALgAECgUJDwAAAA==.Lan:BAAALgADCgEJAQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAEBLgAECn8VAAIDAAgJOwj0fgAsAQhoDAAAAwAOAGkMAAADAB0AawwAAAMAFABqDAAAAwAPAGwMAAACAAsAbQwAAAIAFgDqDAAABAAdAG4MAAABABMAAwAICTsI9H4ALAEIaAwAAAMADgBpDAAAAwAdAGsMAAADABQAagwAAAMADwBsDAAAAgALAG0MAAACABYA6gwAAAQAHQBuDAAAAQATAAEuAAUUAgkGAAYAGwsA.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8PAAMVAAYJzAZLDQCVAQZoDAAAAwAeAGkMAAACABQAawwAAAMADgBqDAAAAwAPAGwMAAABAAQA6gwAAAMAEgAVAAYJzAZLDQCVAQZoDAAAAgAeAGkMAAACABQAawwAAAMADgBqDAAAAgAPAGwMAAABAAQA6gwAAAIAEgAbAAMJfQgXHgCWAANoDAAAAQAMAGoMAAABAA0A6gwAAAEAHgAuAAQKfyEAAxUACQmpGG4SACECABUACAk0GW4SACECABsABwmVHGEdAHcBAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIcAAMJyQGELwCmAANoDAAAAgADAGkMAAACAAYA6gwAAAEABAAcAAMJyQGELwCmAANoDAAAAgADAGkMAAACAAYA6gwAAAEABAAuAAQKfyQAAhwACQlWCjYyADcBABwACQlWCjYyADcBAAAA.Lootadots:BAAALgADCgkJHAABLgAECgYJEgAQAAAAAA==.',
Lu='Lumie:BAABLgAECn8mAAMLAAkJBCCgCADCAgloDAAABgBcAGkMAAAGAF0AawwAAAUAVQBqDAAABQBdAGwMAAAEAF0AbQwAAAIAPwDqDAAABgBUAG4MAAADADMAbwwAAAEAUQALAAkJBCCgCADCAgloDAAABABcAGkMAAAEAF0AawwAAAQAVQBqDAAABABdAGwMAAADAF0AbQwAAAIAPwDqDAAABQBUAG4MAAACADMAbwwAAAEAUQAbAAcJ4BFzHwBnAQdoDAAAAgAwAGkMAAACADkAawwAAAEANABqDAAAAQAjAGwMAAABABoA6gwAAAEAIgBuDAAAAQA2AAAA.Lumiea:BAAALgAECgEJAQABLgAECgkJJgALAAQgAA==.Lunie:BAABLgAECn8bAAIBAAgJuB4FDQCkAghoDAAABQBbAGkMAAAFAF0AawwAAAUAUABqDAAABABNAGwMAAADAFAAbQwAAAEALwDqDAAAAgBTAG4MAAACAEoAAQAICbgeBQ0ApAIIaAwAAAUAWwBpDAAABQBdAGsMAAAFAFAAagwAAAQATQBsDAAAAwBQAG0MAAABAC8A6gwAAAIAUwBuDAAAAgBKAAEuAAQKCQkmAAsABCAA.',
Ma='Magadeoz:BAAALgAECgYJDQAAAA==.Magicshow:BAABLgAECn8cAAIDAAgJ9RD8lACqAQhoDAAABAA0AGkMAAAEAC4AawwAAAMAKgBqDAAABAAmAGwMAAAEADkAbQwAAAEAEQDqDAAABwA8AG4MAAABABwAAwAICfUQ/JQAqgEIaAwAAAQANABpDAAABAAuAGsMAAADACoAagwAAAQAJgBsDAAABAA5AG0MAAABABEA6gwAAAcAPABuDAAAAQAcAAAA.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwAAAA==.Moonbelle:BAAALgAECgcJBwABLgAFFAYJDwAVAMwGAA==.',
Mu='Murthius:BAAALgADCgYJBgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAABLgAECn8ZAAMCAAgJrhm3XQDZAQhoDAAABQBCAGkMAAAEAFMAawwAAAQARQBqDAAAAQBCAGwMAAACAE0AbQwAAAIANwDqDAAABgBDAG4MAAABACgAAgAICa4Zt10A2QEIaAwAAAUAQgBpDAAAAwBTAGsMAAADAEUAagwAAAEAQgBsDAAAAgBNAG0MAAACADcA6gwAAAYAQwBuDAAAAQAoAA0AAglXBn8+AFYAAmkMAAABAAYAawwAAAEAGQAAAA==.Neiry:BAAALgADCgcJBwAAAA==.',
No='Noctislucis:BAABLgAECn8XAAMUAAkJqgouYwD8AAloDAAABAAfAGkMAAAEACYAawwAAAQAHwBqDAAAAwAQAGwMAAABAAwAbQwAAAEACgDqDAAAAQAIAG4MAAAEADIAbwwAAAEAIwAUAAcJpAkuYwD8AAdoDAAAAgAfAGkMAAACACYAawwAAAIAHwBsDAAAAQAMAOoMAAABAAgAbgwAAAEADwBvDAAAAQAjAB0ABgmRCioZANEABmgMAAACAA8AaQwAAAIAGwBrDAAAAgAfAGoMAAADABAAbQwAAAEACgBuDAAAAwAyAAAA.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAAALgAFFAIJBAABLgAFFAQJGAAWAMolAA==.Noobmonkey:BAACLgAFFH8YAAIWAAQJyiXbBAC9AQRoDAAABwBiAGkMAAAHAGIAawwAAAUAYQDqDAAABQBcABYABAnKJdsEAL0BBGgMAAAHAGIAaQwAAAcAYgBrDAAABQBhAOoMAAAFAFwALgAECn8zAAIWAAkJ+CVeAAB1AwAWAAkJ+CVeAAB1AwAAAA==.Noobwarr:BAAALgAECgYJBgABLgAFFAQJGAAWAMolAA==.Novax:BAAALgAECgMJAwAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMbAAIJsBGRGwCnAAJoDAAAAwA8AOoMAAADAB4AGwACCbARkRsApwACaAwAAAEAPADqDAAAAgAeAAsAAgm3DfYNAI4AAmgMAAACACkA6gwAAAEAHAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAAALgAECgUJDQABLgAECgcJGwAWAN0MAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAUJHAAFANkfAA==.',
Po='Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn8cAAIeAAYJwBi6RABkAQZoDAAABgBLAGkMAAAFAEYAawwAAAYAPgBqDAAAAwA/AGwMAAADAD0A6gwAAAUALgAeAAYJwBi6RABkAQZoDAAABgBLAGkMAAAFAEYAawwAAAYAPgBqDAAAAwA/AGwMAAADAD0A6gwAAAUALgAAAA==.',
Pu='Putz:BAABLgAECn86AAMUAAkJ2SBkCQC9AgloDAAACABiAGkMAAAIAF4AawwAAAcAWABqDAAABwBcAGwMAAAHAFIAbQwAAAYAXwDqDAAACABaAG4MAAAFADIAbwwAAAIASAAUAAkJ2SBkCQC9AgloDAAACABiAGkMAAAIAF4AawwAAAcAWABqDAAABwBcAGwMAAAHAFIAbQwAAAYAXwDqDAAABwBaAG4MAAAFADIAbwwAAAIASAAdAAEJ6hHkIgA0AAHqDAAAAQAtAAAA.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAUJHAAFANkfAA==.Rainbow:BAABLgAECn8iAAIYAAgJ6BtEDABZAghoDAAABQBSAGkMAAAGAFkAawwAAAYASwBqDAAABQBQAGwMAAAEAEUAbQwAAAEANADqDAAABgBZAG4MAAABAB8AGAAICegbRAwAWQIIaAwAAAUAUgBpDAAABgBZAGsMAAAGAEsAagwAAAUAUABsDAAABABFAG0MAAABADQA6gwAAAYAWQBuDAAAAQAfAAEuAAQKCQkxABMAIyUA.Rastasham:BAAALgAECgYJBgAAAA==.Ratfondler:BAACLgAFFH8FAAMXAAMJRxUHEgDuAANoDAAAAgAwAGkMAAABAEsA6gwAAAIAJwAXAAMJRxUHEgDuAANoDAAAAQAwAGkMAAABAEsA6gwAAAIAJwAYAAEJcwZ9MwA0AAFoDAAAAQAQAC4ABAp/IwADFwAJCZMg3AMA3wIAFwAJCZMg3AMA3wIAGAAECVAPiD0AwwAAAAA=.',
Re='Reialaleigh:BAAALgAECgMJAwAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAIUAAUJTBefCQCQAQVoDAAABwBEAGkMAAADAC4AawwAAAMANABqDAAAAgAPAOoMAAAGAEYAFAAFCUwXnwkAkAEFaAwAAAcARABpDAAAAwAuAGsMAAADADQAagwAAAIADwDqDAAABgBGAC4ABAp/MAACFAAJCfAfzgcATQMAFAAJCfAfzgcATQMAAAA=.Saberdiva:BAABLgAECn8pAAIGAAgJBhGkXwBRAQhoDAAABwA6AGkMAAAHACUAawwAAAQAIQBqDAAABQA6AGwMAAAGADgAbQwAAAMAGADqDAAABwAzAG4MAAACACsABgAICQYRpF8AUQEIaAwAAAcAOgBpDAAABwAlAGsMAAAEACEAagwAAAUAOgBsDAAABgA4AG0MAAADABgA6gwAAAcAMwBuDAAAAgArAAAA.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sagesteppe:BAAALgAECgQJBAAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAICAAgJKg+kVABiAQhoDAAACAAvAGkMAAAIADcAawwAAAYAMwBqDAAABABGAGwMAAADAD0AbQwAAAEACQDqDAAABAAjAG4MAAABAAsAAgAICSoPpFQAYgEIaAwAAAgALwBpDAAACAA3AGsMAAAGADMAagwAAAQARgBsDAAAAwA9AG0MAAABAAkA6gwAAAQAIwBuDAAAAQALAAAA.',
Se='Seditionist:BAABLgAECn8WAAITAAYJWgRASACrAAZoDAAABQAIAGkMAAAFAA0AawwAAAQACQBqDAAAAwAIAGwMAAADABMA6gwAAAIABAATAAYJWgRASACrAAZoDAAABQAIAGkMAAAFAA0AawwAAAQACQBqDAAAAwAIAGwMAAADABMA6gwAAAIABAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgMJAwAQAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgADCgUJBQAAAA==.',
Si='Sidthekid:BAAALgAECgIJAgAAAA==.Sinayion:BAABLgAECn8aAAIaAAYJsgTQJQCIAAZoDAAABQASAGkMAAAFAA8AawwAAAUADwBqDAAAAwAEAGwMAAADAAQA6gwAAAUABgAaAAYJsgTQJQCIAAZoDAAABQASAGkMAAAFAA8AawwAAAUADwBqDAAAAwAEAGwMAAADAAQA6gwAAAUABgAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAQAAAAAA==.',
Su='Sunarena:BAABLgAECn8cAAIGAAgJ5Q9DbwAvAQhoDAAABAAeAGkMAAAEACUAawwAAAQAFwBqDAAAAwAaAGwMAAADAEEA6gwAAAMAHABuDAAABQA0AG8MAAACAC4ABgAICeUPQ28ALwEIaAwAAAQAHgBpDAAABAAlAGsMAAAEABcAagwAAAMAGgBsDAAAAwBBAOoMAAADABwAbgwAAAUANABvDAAAAgAuAAAA.',
Ta='Tankobell:BAAALgAFFAEJAQAAAA==.',
Te='Terrible:BAAALgAECgcJAQAAAA==.',
Th='Thannatos:BAAALgADCgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Toukadh:BAAALgAECgYJAQAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8hAAIDAAcJDhdxRgC0AQdoDAAABwBWAGkMAAAFADEAawwAAAUANwBqDAAABQBMAGwMAAAEACoA6gwAAAYAUQBuDAAAAQAlAAMABwkOF3FGALQBB2gMAAAHAFYAaQwAAAUAMQBrDAAABQA3AGoMAAAFAEwAbAwAAAQAKgDqDAAABgBRAG4MAAABACUAAAA=.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAECgcJCwAAAA==.Varfus:BAACLgAFFH8cAAIdAAUJiSV3AACzAQVoDAAABwBgAGkMAAAHAGMAawwAAAUAWwBqDAAAAwBPAOoMAAAGAGEAHQAFCYkldwAAswEFaAwAAAcAYABpDAAABwBjAGsMAAAFAFsAagwAAAMATwDqDAAABgBhAC4ABAp/MwACHQAJCUgmFwAAdAMAHQAJCUgmFwAAdAMAAAA=.',
Ve='Velentre:BAAALgAECgYJCAAAAA==.',
Vi='Vichy:BAAALgAECgMJBAAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAABLgAECn8WAAIGAAcJGSSyIwCaAgdoDAAAAwBbAGkMAAACAFoAawwAAAMAYABqDAAAAwBaAGwMAAAEAFcAbQwAAAMAWgDqDAAABABjAAYABwkZJLIjAJoCB2gMAAADAFsAaQwAAAIAWgBrDAAAAwBgAGoMAAADAFoAbAwAAAQAVwBtDAAAAwBaAOoMAAAEAGMAAAA=.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn8tAAMMAAkJfiXiAQBXAwloDAAABgBiAGkMAAAGAGIAawwAAAYAYgBqDAAABgBhAGwMAAAGAGEAbQwAAAUAYADqDAAABQBhAG4MAAAEAF8AbwwAAAEAVwAMAAkJbSXiAQBXAwloDAAABQBiAGkMAAAEAGAAawwAAAUAYgBqDAAAAwAyAGwMAAAFAGEAbQwAAAUAYADqDAAABABhAG4MAAAEAF8AbwwAAAEAVwAJAAYJqiPVAwBQAgZoDAAAAQBZAGkMAAACAGIAawwAAAEAXQBqDAAAAwBhAGwMAAABAFkA6gwAAAEAVQAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgUJBQAAAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zeposo:BAABLgAECn8XAAMLAAcJphZyGwCSAQdoDAAABgBOAGkMAAAEAEYAawwAAAQALgBqDAAAAQAZAGwMAAAEAC4A6gwAAAMAOgBuDAAAAQBPAAsABwmmFnIbAJIBB2gMAAAGAE4AaQwAAAQARgBrDAAABAAuAGoMAAABABkAbAwAAAMALgDqDAAAAwA6AG4MAAABAE8AGwABCcgEOWQAKwABbAwAAAEADAABLgAECgkJOQAFAOYbAA==.Zeppo:BAAALgADCgQJBAABLgAECgkJOQAFAOYbAA==.Zeptide:BAABLgAECn85AAMFAAkJ5htsDACYAgloDAAACwBiAGkMAAALAGIAawwAAAkARwBqDAAABgBJAGwMAAADAC0AbQwAAAMAGgDqDAAACABhAG4MAAAFADoAbwwAAAEASAAFAAkJ5htsDACYAgloDAAACABiAGkMAAAHAGIAawwAAAYARwBqDAAABQBJAGwMAAACAC0AbQwAAAMAGgDqDAAACABhAG4MAAABADoAbwwAAAEASAATAAYJcRAKMwAEAQZoDAAAAwAsAGkMAAAEACwAawwAAAMAJgBqDAAAAQAXAGwMAAABABoAbgwAAAQANwAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECggJAwAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAFFAMJBQAMALoFAA==.',
Zu='Zugnuts:BAAALgADCgcJHAAAAA==.',
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
