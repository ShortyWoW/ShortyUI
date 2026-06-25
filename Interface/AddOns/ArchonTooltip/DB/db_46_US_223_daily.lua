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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Druid-Feral','Druid-Guardian','Druid-Balance','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-BeastMastery','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Druid-Restoration','Mage-Fire','Mage-Arcane','Monk-Mistweaver','Paladin-Protection','Warrior-Protection','Priest-Shadow',}
local provider = {region='US',realm='TolBarad',name='US',type='daily',zone=46,date='2026-06-24',data={Ae='Aelarion:BAAALgADCgIJAgAAAA==.',
Ai='Airfryer:BAABLgAECn8wAAMBAAgJvR07BAA/AghoDAAACABUAGkMAAAIAFAAawwAAAoAWgBqDAAABwBNAGwMAAAEAEsAbQwAAAMALwDqDAAABgA9AG4MAAACAFwAAQAICb0dOwQAPwIIaAwAAAcAVABpDAAABwBQAGsMAAAIAFoAagwAAAcATQBsDAAABABLAG0MAAADAC8A6gwAAAYAPQBuDAAAAgBcAAIAAwlAEM3nAI8AA2gMAAABACMAaQwAAAEAIgBrDAAAAgA2AAEuAAQKCAkzAAMA+CAA.',
Aj='Ajorc:BAABLgAECn8aAAIEAAcJKhuaCgAdAgdoDAAAAwA9AGkMAAAEAEsAawwAAAQATgBqDAAABAA6AGwMAAADADkA6gwAAAQASgBuDAAABABFAAQABwkqG5oKAB0CB2gMAAADAD0AaQwAAAQASwBrDAAABABOAGoMAAAEADoAbAwAAAMAOQDqDAAABABKAG4MAAAEAEUAAAA=.Ajudando:BAACLgAFFH8lAAMEAAYJNh8pAgC+AQZoDAAACQBZAGkMAAAJAFYAawwAAAUAVgBqDAAAAQAtAGwMAAABAEYA6gwAAAwAQwAEAAYJgx4pAgC+AQZoDAAAAwBZAGkMAAADAFYAawwAAAEAVgBqDAAAAQAtAGwMAAABAEYA6gwAAAQAOgAFAAQJthPqEQD1AARoDAAABgAlAGkMAAAGAE0AawwAAAQAEwDqDAAACABDAC4ABAp/RgAEBAAJCbsfVgcAZQIABAAICfIiVgcAZQIABQAJCTQY8hMAuAEABgACCbQKzm8AYAAAAAA=.',
Ak='Akindart:BAAALgAFFAEJAQAAAA==.',
An='Anneliese:BAAALgAECgQJBAAAAA==.',
Ar='Aranaki:BAAALgAECgEJAQAAAA==.Arc:BAAALgAECgIJBAAAAA==.Arcadeshadow:BAAALgAECgYJDgABLgAECgcJCwAHAAAAAA==.Arkanjjo:BAAALgAECgEJAQAAAA==.Arkhin:BAAALgADCgYJBgABLgAECgQJBAAHAAAAAA==.Artesuda:BAAALgAECgIJAwAAAA==.Artorus:BAAALgAECgIJAgAAAA==.',
Au='Aurelya:BAAALgAECgcJCgAAAA==.',
Aw='Awrelius:BAAALgADCgUJDAAAAA==.',
Ay='Ayuub:BAAALgAECgQJBAAAAA==.',
Az='Aznat:BAAALgAECgYJDgABLgAECgkJJgAIAK0ZAA==.',
Ba='Bachir:BAAALgAECgUJBQAAAA==.Balduco:BAAALgAECgQJDQABLgAFFAEJAQAHAAAAAA==.Barkernth:BAABLgAECn8hAAIJAAgJwRXaFQC2AQhoDAAABQBFAGkMAAAFAEUAawwAAAUARgBqDAAABQA3AGwMAAAFADUAbQwAAAEADwDqDAAABgBVAG8MAAABABoACQAICcEV2hUAtgEIaAwAAAUARQBpDAAABQBFAGsMAAAFAEYAagwAAAUANwBsDAAABQA1AG0MAAABAA8A6gwAAAYAVQBvDAAAAQAaAAAA.Baródius:BAAALgADCgQJBwAAAA==.Batatadoci:BAABLgAECn8VAAIKAAgJqggMvAAOAQhoDAAAAwASAGkMAAADACsAawwAAAMAGwBqDAAAAwATAGwMAAADABIAbQwAAAEACADqDAAAAwAPAG4MAAACABcACgAICaoIDLwADgEIaAwAAAMAEgBpDAAAAwArAGsMAAADABsAagwAAAMAEwBsDAAAAwASAG0MAAABAAgA6gwAAAMADwBuDAAAAgAXAAAA.',
Be='Bellatryx:BAAALgAECgEJAQAAAA==.Benx:BAAALgAECgQJAQAAAA==.',
Bi='Bianca:BAAALgAECgcJCAAAAA==.Bispopelado:BAAALgADCgcJBwAAAA==.',
Br='Brunnoo:BAAALgAECgUJCAABLgAECggJGAALAKgaAA==.Brutaal:BAAALgADCgUJBQAAAA==.Brutállus:BAAALgADCgcJBwAAAA==.',
Ca='Calangosauro:BAAALgAFFAIJBAAAAA==.Capetalista:BAAALgADCgIJAgABLgAECggJKgALAAocAA==.',
Ch='Chinchanchen:BAAALgAECgQJBQAAAA==.',
Co='Coqueiro:BAAALgADCgYJBgAAAA==.Cowtholic:BAAALgAECgQJBAABLgAECgcJDAAHAAAAAA==.',
Cr='Cremador:BAAALgAECgYJEQAAAA==.',
Cy='Cyrannus:BAAALgAECgMJAwABLgAECggJMwADAPggAA==.',
Da='Dabura:BAAALgADCgEJBQAAAA==.Dam:BAAALgADCgYJBgAAAA==.',
De='Deabu:BAAALgADCgQJBQAAAA==.Demethryus:BAAALgADCgYJBgAAAA==.Dennath:BAAALgAECgQJBgAAAA==.Ders:BAAALgADCgEJAQAAAA==.Devilton:BAABLgAECn89AAMMAAgJaRSWSQCqAQhoDAAACgA0AGkMAAAJAD4AawwAAAkAMABqDAAACAAqAGwMAAAHADkAbQwAAAQAGwDqDAAACwAzAG4MAAADAEEADAAICcATlkkAqgEIaAwAAAoANABpDAAACQA+AGsMAAAJADAAagwAAAgAKgBsDAAABwA5AG0MAAAEABsA6gwAAAoAMwBuDAAAAgA1AA0AAgnIFVMFAIEAAuoMAAABAC4AbgwAAAEAQQAAAA==.',
Di='Diericshaman:BAAALgADCgUJBQAAAA==.',
Dk='Dkagulino:BAAALgAECgMJAwABLgAFFAMJCAAOAJQgAA==.',
Do='Domri:BAABLgAECn8bAAIOAAgJaCAHHwBLAghoDAAABQBeAGkMAAAEAF8AawwAAAQAWwBqDAAABABaAGwMAAAEAFYAbQwAAAEAIADqDAAABABVAG4MAAABAF4ADgAICWggBx8ASwIIaAwAAAUAXgBpDAAABABfAGsMAAAEAFsAagwAAAQAWgBsDAAABABWAG0MAAABACAA6gwAAAQAVQBuDAAAAQBeAAAA.Donnus:BAABLgAECn81AAILAAkJfyDPIQCWAgloDAAACABeAGkMAAAHAFkAawwAAAgAUABqDAAABgBQAGwMAAAFAFMAbQwAAAQASwDqDAAABwBYAG4MAAAFAEsAbwwAAAMATgALAAkJfyDPIQCWAgloDAAACABeAGkMAAAHAFkAawwAAAgAUABqDAAABgBQAGwMAAAFAFMAbQwAAAQASwDqDAAABwBYAG4MAAAFAEsAbwwAAAMATgAAAA==.Doomhand:BAAALgAECgQJBAAAAA==.Dormin:BAAALgADCgUJBQAAAA==.Dorotty:BAAALgAECgUJBgAAAA==.',
Dr='Dragolancer:BAAALgAECgMJAwAAAA==.Drakonvolk:BAABLgAECn86AAMDAAkJvyOvDAAHAwloDAAACQBUAGkMAAAIAF8AawwAAAcAVgBqDAAABgBXAGwMAAAGAF0AbQwAAAMAWgDqDAAACgBaAG4MAAAHAF8AbwwAAAIAXwADAAkJ1SKvDAAHAwloDAAACABOAGkMAAAHAF8AawwAAAYATgBqDAAABABEAGwMAAAFAF0AbQwAAAMAWgDqDAAABwBaAG4MAAADAFoAbwwAAAIAXwAPAAcJLyDRAwA9AgdoDAAAAQBUAGkMAAABAE4AawwAAAEAVgBqDAAAAgBXAGwMAAABAEQA6gwAAAMAUQBuDAAABABfAAAA.Drevanir:BAAALgADCggJCAAAAA==.Druidzuda:BAAALgADCgEJAQAAAA==.',
Du='Dudah:BAAALgAECgEJAQAAAA==.',
['Dé']='Dégell:BAAALgAECgUJCQAAAA==.',
Ed='Edy:BAABLgAECn8WAAIOAAkJ1SNLBQA9AwloDAAAAgBdAGkMAAACAF0AawwAAAIAXABqDAAAAgBBAGwMAAACAF4AbQwAAAIAWQDqDAAABQBWAG4MAAACAF0AbwwAAAMAWAAOAAkJ1SNLBQA9AwloDAAAAgBdAGkMAAACAF0AawwAAAIAXABqDAAAAgBBAGwMAAACAF4AbQwAAAIAWQDqDAAABQBWAG4MAAACAF0AbwwAAAMAWAAAAA==.',
Ee='Eelai:BAAALgADCgQJBAAAAA==.',
Ei='Einheriar:BAAALgADCgUJBQAAAA==.',
El='Elanya:BAAALgAECgUJCAAAAA==.Elidaryel:BAABLgAECn80AAIMAAkJFSA4EADAAgloDAAABwBeAGkMAAAHAFkAawwAAAcAWgBqDAAABgBVAGwMAAAFAFIAbQwAAAUATADqDAAACABeAG4MAAAFAFMAbwwAAAIALQAMAAkJFSA4EADAAgloDAAABwBeAGkMAAAHAFkAawwAAAcAWgBqDAAABgBVAGwMAAAFAFIAbQwAAAUATADqDAAACABeAG4MAAAFAFMAbwwAAAIALQAAAA==.Elma:BAAALgAECgEJAgABLgAECgkJJgACAHQdAA==.Elrondperedh:BAAALgAECgMJBAAAAA==.',
Er='Eryeth:BAAALgAECgYJBwABLgAECgkJJgAIAK0ZAA==.',
Ex='Excloud:BAAALgAECgUJBQAAAA==.',
Fa='Faephine:BAABLgAECn8VAAIGAAkJQgc/BADMAAloDAAAAwAWAGkMAAADACIAawwAAAMAGQBqDAAAAwAaAGwMAAADAAwAbQwAAAEACADqDAAAAwAOAG4MAAABAAkAbwwAAAEAFgAGAAkJQgc/BADMAAloDAAAAwAWAGkMAAADACIAawwAAAMAGQBqDAAAAwAaAGwMAAADAAwAbQwAAAEACADqDAAAAwAOAG4MAAABAAkAbwwAAAEAFgAAAA==.Fallora:BAAALgADCgYJBgAAAA==.',
Fe='Felithia:BAAALgADCgQJBAABLgAFFAUJEQAPAKoRAA==.',
Fr='Fred:BAAALgAECgUJCQAAAA==.Frozenrune:BAABLgAECn8lAAMPAAgJ1B/zBAD8AQhoDAAABgBhAGkMAAAFAFwAawwAAAUAXwBqDAAABQBbAGwMAAAFAF4AbQwAAAMAMgDqDAAABQBcAG4MAAADAC8ADwAGCeEk8wQA/AEGaAwAAAMAYQBpDAAAAgBcAGsMAAACAF8AagwAAAIAWwBsDAAAAgBeAOoMAAACAFwACQAICWAWyRIA4AEIaAwAAAMAKQBpDAAAAwBEAGsMAAADAEsAagwAAAMAQQBsDAAAAwAxAG0MAAADADIA6gwAAAMARABuDAAAAwAvAAAA.',
Fu='Fuleco:BAABLgAECn8vAAMQAAgJ4CPrCwAoAghoDAAACABjAGkMAAAIAGIAawwAAAcAWQBqDAAABgBjAGwMAAAFAFgAbQwAAAEAXwDqDAAACQBhAG4MAAADAEoAEAAGCaUi6wsAKAIGaAwAAAEAYABpDAAAAQBXAGsMAAAGAFkAbAwAAAQAWADqDAAAAgBfAG4MAAABAEoAEQAICXQhURwACwIIaAwAAAcAYwBpDAAABwBiAGsMAAABAFAAagwAAAYAYwBsDAAAAQA5AG0MAAABAF8A6gwAAAcAYQBuDAAAAgBHAAAA.',
Ga='Gablle:BAACLgAFFH8LAAISAAMJ2h/BFgALAQNoDAAABABNAGkMAAACAFIA6gwAAAUAVAASAAMJ2h/BFgALAQNoDAAABABNAGkMAAACAFIA6gwAAAUAVAAuAAQKfzYAAxIACQneDc8pAG0BABIACQneDc8pAG0BABMACQkbBeE0ACsBAAAA.Gabrielstone:BAAALgAECgQJBgAAAA==.Gabriwel:BAAALgAECgQJDgAAAA==.',
Gl='Glimmuln:BAABLgAECn8qAAMUAAYJjQnpggDZAAZoDAAACQAYAGkMAAAIACMAawwAAAYAFwBqDAAABAAMAGwMAAAGAAkA6gwAAAkAKgAUAAYJjQnpggDZAAZoDAAABwAYAGkMAAAHACMAawwAAAYAFwBqDAAABAAMAGwMAAAEAAkA6gwAAAkAKgAVAAMJewWCDgAwAANoDAAAAgATAGkMAAABAAAAbAwAAAIAFgAAAA==.Glimwr:BAAALgAECgQJEQAAAA==.',
Go='Gordorc:BAAALgAECgEJAQAAAA==.Gorvok:BAAALgADCgMJAwAAAA==.',
Gr='Grongos:BAAALgAFFAEJAQAAAA==.Grumps:BAAALgADCgcJBwAAAA==.',
Gu='Gudeath:BAAALgAECgcJBwAAAA==.Gueber:BAAALgAECgYJDAAAAA==.Gueberlin:BAAALgADCgQJBAAAAA==.Guebernir:BAAALgADCgYJDAAAAA==.',
Ha='Hakoda:BAAALgAECgEJAQAAAA==.Harggoth:BAAALgAECggJEQAAAA==.',
He='Hergor:BAABLgAECn8vAAQVAAkJRBP/JgC0AQloDAAABgBAAGkMAAAEADwAawwAAAUAKQBqDAAABgBAAGwMAAAHACsAbQwAAAYAIwDqDAAABwBIAG4MAAAEACgAbwwAAAIAIgAVAAkJRBP/JgC0AQloDAAABABAAGkMAAAEADwAawwAAAUAKQBqDAAABABAAGwMAAAGACsAbQwAAAQAIwDqDAAAAwBIAG4MAAAEACgAbwwAAAEAIgAUAAUJxAwyjADCAAVoDAAAAgAbAGoMAAABAAgAbQwAAAIASADqDAAABAAsAG8MAAABAAsAFgACCb0IHywANQACagwAAAEAAABsDAAAAQAWAAAA.Hexdrinker:BAAALgAECgEJAQABLgAECgEJAgAHAAAAAA==.',
Ir='Irmasuelen:BAAALgAECgYJCwAAAA==.',
Je='Jeh:BAAALgAECgMJAwAAAA==.Jeje:BAAALgAECgQJBwAAAA==.',
Jo='Jorgebenjorg:BAAALgAECgEJAQAAAA==.',
Ka='Kalanguin:BAAALgADCgEJAQAAAA==.Kandarai:BAAALgAECgIJAgAAAA==.Kate:BAABLgAECn8jAAIXAAkJZxS6MgDUAQloDAAABQBHAGkMAAAFAD4AawwAAAUATgBqDAAABAAxAGwMAAADACwAbQwAAAIAGgDqDAAABgA9AG4MAAADADgAbwwAAAIAEgAXAAkJZxS6MgDUAQloDAAABQBHAGkMAAAFAD4AawwAAAUATgBqDAAABAAxAGwMAAADACwAbQwAAAIAGgDqDAAABgA9AG4MAAADADgAbwwAAAIAEgAAAA==.',
Ke='Kessig:BAAALgAFFAEJAQAAAA==.',
Kh='Khylin:BAAALgAECgUJCAAAAA==.',
Kl='Klimorin:BAAALgADCgMJBAAAAA==.',
Ko='Kouta:BAAALgAECgEJAQAAAA==.',
Kr='Krzero:BAAALgADCgIJAgABLgAECgkJOgADAL8jAA==.',
Lc='Lcabronehboy:BAABLgAECn8kAAILAAcJThfyaQCoAQdoDAAABQA4AGkMAAAEADsAawwAAAQALQBqDAAABwAtAGwMAAAEAD8A6gwAAAoATwBuDAAAAgA1AAsABwlOF/JpAKgBB2gMAAAFADgAaQwAAAQAOwBrDAAABAAtAGoMAAAHAC0AbAwAAAQAPwDqDAAACgBPAG4MAAACADUAAAA=.',
Le='Lexan:BAABLgAECn8yAAQVAAgJ5RIdNgBhAQhoDAAACAAkAGkMAAAHADEAawwAAAcALgBqDAAABgBDAGwMAAAGAC0AbQwAAAQAIADqDAAACQA3AG4MAAADAEgAFQAICcEQHTYAYQEIaAwAAAcAJABpDAAABgAxAGsMAAAGAC4AagwAAAUAQwBsDAAABQAtAG0MAAADACAA6gwAAAgANwBuDAAAAQAhABYABwnODI8DAI0AB2gMAAABABQAaQwAAAEAGABrDAAAAQAZAGoMAAABAAgAbAwAAAEADQDqDAAAAQAoAG4MAAABAEgAFAACCfMJKroAWQACbQwAAAEAIABuDAAAAQASAAAA.',
Li='Liadine:BAAALgADCgYJBwAAAA==.Linlygan:BAAALgADCgQJBAAAAA==.Lissão:BAABLgAECn8kAAMJAAkJBB7tCQB0AgloDAAABgBHAGkMAAAGAFAAawwAAAYAUABqDAAABABTAGwMAAAEADoAbQwAAAIASQDqDAAABgBUAG4MAAABAFAAbwwAAAEAVQAJAAkJBB7tCQB0AgloDAAABgBHAGkMAAAGAFAAawwAAAYAUABqDAAABABTAGwMAAAEADoAbQwAAAIASQDqDAAABQBUAG4MAAABAFAAbwwAAAEAVQADAAEJ8QCTPAEZAAHqDAAAAQACAAAA.',
Lu='Lucoa:BAAALgADCgUJBQABLgAECgkJJgACAHQdAA==.Luhanar:BAAALgAECgYJCwABLgAECgkJOgADAL8jAA==.',
Ly='Lylithe:BAAALgAECgEJAQAAAA==.',
Ma='Madow:BAABLgAECn8mAAICAAkJdB3tGQCIAgloDAAABgA9AGkMAAAGAFAAawwAAAYATQBqDAAABABZAGwMAAAEAFAAbQwAAAIALgDqDAAACABcAG4MAAABAEgAbwwAAAEAWgACAAkJdB3tGQCIAgloDAAABgA9AGkMAAAGAFAAawwAAAYATQBqDAAABABZAGwMAAAEAFAAbQwAAAIALgDqDAAACABcAG4MAAABAEgAbwwAAAEAWgAAAA==.Magmafire:BAABLgAECn85AAMYAAkJwiIfAQDAAgloDAAABQBjAGkMAAAEAGAAawwAAAMAWwBqDAAACQBfAGwMAAAIAEwAbQwAAAgAWADqDAAABwBbAG4MAAAHAFEAbwwAAAYAVwAYAAkJaiEfAQDAAgloDAAAAQBKAGkMAAACAGAAawwAAAIAWwBqDAAABwBfAGwMAAAFAEkAbQwAAAYAWADqDAAABQBbAG4MAAAHAFEAbwwAAAYAVwAZAAcJ8x/XAgBYAgdoDAAABABjAGkMAAACAFcAawwAAAEAVQBqDAAAAgAbAGwMAAADAEwAbQwAAAIANADqDAAAAgBYAAAA.Magronego:BAAALgAECgYJCAAAAA==.Malakain:BAAALgAECgQJBQAAAA==.Mayha:BAAALgAECgUJCQABLgAECggJHwAKAHoWAA==.Mazakita:BAAALgADCgMJAwAAAA==.',
Me='Mellahel:BAAALgADCgUJBQAAAA==.',
Mi='Mitsy:BAABLgAECn8dAAMaAAYJfh+VAwBXAQZoDAAABQBSAGkMAAAGAFYAawwAAAYATgBqDAAAAwBNAGwMAAADAEMA6gwAAAYAWgAaAAYJfh+VAwBXAQZoDAAABABSAGkMAAAEAFYAawwAAAQATgBqDAAAAQBNAGwMAAABAEMA6gwAAAQAWgASAAYJDAt6PwAcAQZoDAAAAQANAGkMAAACACkAawwAAAIAJABqDAAAAgAlAGwMAAACABgA6gwAAAIAGgAAAA==.',
Mo='Morevil:BAAALgADCgQJBAAAAA==.Morterubra:BAABLgAECn8zAAMDAAgJ+CD+HwCJAghoDAAADQBbAGkMAAAHAF8AawwAAAoAXABqDAAABQBgAGwMAAADAFQAbQwAAAIANwDqDAAACABQAG4MAAADAFsAAwAICfgg/h8AiQIIaAwAAAsAWwBpDAAABQBfAGsMAAAIAFwAagwAAAMAYABsDAAAAgBUAG0MAAACADcA6gwAAAgAUABuDAAAAwBbAAkABQmgCypAAI4ABWgMAAACADIAaQwAAAIAHgBrDAAAAgAUAGoMAAACAAwAbAwAAAEAEAAAAA==.Mosa:BAABLgAECn8gAAIUAAgJPg5wTwB0AQhoDAAABgBUAGkMAAAGACEAawwAAAYAHgBqDAAAAgAkAGwMAAADADEAbQwAAAEAEgDqDAAABwAeAG4MAAABAAgAFAAICT4OcE8AdAEIaAwAAAYAVABpDAAABgAhAGsMAAAGAB4AagwAAAIAJABsDAAAAwAxAG0MAAABABIA6gwAAAcAHgBuDAAAAQAIAAAA.Mozart:BAAALgAECgYJBgAAAA==.',
Mu='Mulkzagoon:BAAALgADCgQJBgAAAA==.Murodan:BAAALgAECgQJBAAAAA==.Musphelheim:BAAALgADCgcJBwAAAA==.',
['Mö']='Mörrigan:BAAALgAECgUJBQAAAA==.',
Na='Nadruk:BAABLgAECn8jAAIUAAcJuh7wHQAsAgdoDAAABQBaAGkMAAAFAEEAawwAAAUAVABqDAAABgBQAGwMAAAFAE4AbQwAAAIAOgDqDAAABwBbABQABwm6HvAdACwCB2gMAAAFAFoAaQwAAAUAQQBrDAAABQBUAGoMAAAGAFAAbAwAAAUATgBtDAAAAgA6AOoMAAAHAFsAAAA=.Natalia:BAAALgAECgkJDQAAAA==.',
Ne='Neon:BAAALgAECgYJCgAAAA==.Neskau:BAAALgAECgEJAQABLgAECggJMgAVAOUSAA==.Nevinha:BAAALgADCgEJAQAAAA==.Neymardacaça:BAAALgADCgIJAgAAAA==.',
Ni='Nidaime:BAABLgAECn8aAAILAAgJRhNQ0gBJAQhoDAAABAApAGkMAAAEAEQAawwAAAUAQABqDAAABABFAGwMAAABACkAbQwAAAEAFQDqDAAABQA4AG4MAAACADMACwAICUYTUNIASQEIaAwAAAQAKQBpDAAABABEAGsMAAAFAEAAagwAAAQARQBsDAAAAQApAG0MAAABABUA6gwAAAUAOABuDAAAAgAzAAAA.',
No='Noach:BAAALgADCgMJAwABLgAFFAEJAQAHAAAAAA==.Nocro:BAAALgADCgEJAQAAAA==.',
Oa='Oathkeeper:BAAALgAECgMJAwAAAA==.',
Od='Odahviing:BAAALgAECgYJDAABLgAECggJMwADAPggAA==.',
Oi='Oicasada:BAAALgADCgMJBAAAAA==.',
Op='Optix:BAAALgAECgMJAwAAAA==.',
Ox='Oxylus:BAABLgAECn8cAAIXAAgJqxHnOwCkAQhoDAAABQBDAGkMAAAFAEIAawwAAAUAOwBqDAAABAAkAGwMAAAEACYAbQwAAAEAHADqDAAAAwAtAG4MAAABABMAFwAICasR5zsApAEIaAwAAAUAQwBpDAAABQBCAGsMAAAFADsAagwAAAQAJABsDAAABAAmAG0MAAABABwA6gwAAAMALQBuDAAAAQATAAAA.',
Pa='Padremario:BAAALgADCgEJAgAAAA==.Palahorda:BAAALgADCgUJBQAAAA==.Panchorf:BAABLgAECn89AAIbAAgJEwgzJADzAAhoDAAACgAWAGkMAAAJABoAawwAAAkAEwBqDAAACAAGAGwMAAAHABEAbQwAAAQAEgDqDAAACwASAG4MAAADABUAGwAICRMIMyQA8wAIaAwAAAoAFgBpDAAACQAaAGsMAAAJABMAagwAAAgABgBsDAAABwARAG0MAAAEABIA6gwAAAsAEgBuDAAAAwAVAAAA.',
Pe='Pescador:BAAALgAECgcJEAAAAA==.Pevê:BAAALgAECgcJCQAAAA==.',
Po='Porcentagem:BAAALgAECgEJAgABLgAECgMJCAAHAAAAAA==.',
Pr='Prihunter:BAABLgAECn89AAIOAAgJaQx8aAByAQhoDAAACgAcAGkMAAAJACYAawwAAAkAKABqDAAACAAZAGwMAAAHABcAbQwAAAQAIwDqDAAACwAkAG4MAAADABMADgAICWkMfGgAcgEIaAwAAAoAHABpDAAACQAmAGsMAAAJACgAagwAAAgAGQBsDAAABwAXAG0MAAAEACMA6gwAAAsAJABuDAAAAwATAAAA.Primanocte:BAAALgADCgYJBgAAAA==.',
Pu='Pudincessa:BAAALgAECgUJBwAAAA==.',
Ra='Rafikii:BAACLgAFFH8GAAIFAAMJRwKBPgAyAANoDAAAAwAGAGkMAAABAAAA6gwAAAIACQAFAAMJRwKBPgAyAANoDAAAAwAGAGkMAAABAAAA6gwAAAIACQAuAAQKfx0AAgUACAndApAgAJoAAAUACAndApAgAJoAAAAA.Randel:BAAALgADCgQJBAAAAA==.Raswell:BAAALgADCgEJAQAAAA==.',
Re='Rellana:BAAALgADCgIJAgAAAA==.',
Rh='Rhadamants:BAAALgAECgIJAgAAAA==.',
Ri='Richard:BAAALgADCggJBQAAAA==.Ritaa:BAABLgAECn8cAAIKAAcJSxuaRwAMAgdoDAAABABFAGkMAAAEAEAAawwAAAYAQgBqDAAABAAzAGwMAAAEAD4A6gwAAAMASQBuDAAAAwBSAAoABwlLG5pHAAwCB2gMAAAEAEUAaQwAAAQAQABrDAAABgBCAGoMAAAEADMAbAwAAAQAPgDqDAAAAwBJAG4MAAADAFIAAAA=.Rizúl:BAAALgAECgQJBAAAAA==.',
Rl='Rldsbvb:BAABLgAECn8mAAIIAAkJrRnxDwAxAgloDAAABgBEAGkMAAAHAFcAawwAAAYAQwBqDAAABAA2AGwMAAAEAFIAbQwAAAIATQDqDAAABwA7AG4MAAABAB8AbwwAAAEANAAIAAkJrRnxDwAxAgloDAAABgBEAGkMAAAHAFcAawwAAAYAQwBqDAAABAA2AGwMAAAEAFIAbQwAAAIATQDqDAAABwA7AG4MAAABAB8AbwwAAAEANAAAAA==.',
Ro='Rokigame:BAAALgADCgEJAQABLgAECgIJAwAHAAAAAA==.Rotgaz:BAAALgAECgQJBwAAAA==.',
Sa='Sabedetudo:BAAALgAECgEJAgAAAA==.Sadomie:BAABLgAECn80AAIOAAkJ7hi4MQAVAgloDAAACABHAGkMAAAGADcAawwAAAQAOQBqDAAABQA/AGwMAAAHAFIAbQwAAAYANQDqDAAABgBIAG4MAAAGAFYAbwwAAAQAHgAOAAkJ7hi4MQAVAgloDAAACABHAGkMAAAGADcAawwAAAQAOQBqDAAABQA/AGwMAAAHAFIAbQwAAAYANQDqDAAABgBIAG4MAAAGAFYAbwwAAAQAHgAAAA==.',
Sh='Shagratth:BAAALgADCgcJDQAAAA==.Shalthear:BAAALgAECgIJAwABLgAECgkJJgACAHQdAA==.Shindi:BAAALgADCgQJBQAAAA==.Shreka:BAAALgAECgYJEgAAAA==.',
Si='Silaleas:BAAALgAECgkJEwAAAA==.Sin:BAAALgAECgIJAgAAAA==.',
Sk='Skiff:BAAALgAECgEJAgAAAA==.',
Sn='Snoxxie:BAAALgAECgEJAQABLgAECgEJAgAHAAAAAA==.',
So='Solana:BAAALgADCgYJBgAAAA==.',
Sr='Srjhon:BAAALgAECgEJAgAAAA==.',
Sw='Sweej:BAABLgAFFH8IAAMFAAMJyxYPGADFAANoDAAAAwBBAGkMAAACACoA6gwAAAMAQgAFAAMJyxYPGADFAANoDAAAAwBBAGkMAAACACoA6gwAAAIAQgAXAAEJ/gVGdgAvAAHqDAAAAQAPAAAA.',
Ta='Tacalypau:BAAALgADCgYJBgAAAA==.Tahir:BAAALgAECgYJCgAAAA==.Taichi:BAAALgAECgEJAgAAAA==.Taima:BAAALgAFFAIJBAAAAA==.',
Te='Teldaran:BAAALgAECgQJCAAAAA==.',
Th='Thebrunovest:BAABLgAECn8ZAAIDAAYJEhD/ygDvAAZoDAAABAAyAGkMAAAEAD0AawwAAAQAIABqDAAABAAtAGwMAAADACoA6gwAAAYAEwADAAYJEhD/ygDvAAZoDAAABAAyAGkMAAAEAD0AawwAAAQAIABqDAAABAAtAGwMAAADACoA6gwAAAYAEwAAAA==.Thortrevan:BAABLgAECn8sAAIOAAgJ0h2ZEAC1AghoDAAACQBgAGkMAAAIAFYAawwAAAoAWABqDAAABAAxAGwMAAAEAEkAbQwAAAEAQgDqDAAABgBPAG4MAAACACsADgAICdIdmRAAtQIIaAwAAAkAYABpDAAACABWAGsMAAAKAFgAagwAAAQAMQBsDAAABABJAG0MAAABAEIA6gwAAAYATwBuDAAAAgArAAAA.Thrain:BAABLgAECn8fAAIcAAcJexl6HQBJAQdoDAAABgBOAGkMAAAFAFIAawwAAAUAPgBqDAAABAAmAGwMAAAEACoAbQwAAAEAOwDqDAAABgBCABwABwl7GXodAEkBB2gMAAAGAE4AaQwAAAUAUgBrDAAABQA+AGoMAAAEACYAbAwAAAQAKgBtDAAAAQA7AOoMAAAGAEIAAAA=.',
Ti='Tiffah:BAABLgAECn8pAAILAAkJ5yGTEwDkAgloDAAABQBcAGkMAAAFAFUAawwAAAUAVQBqDAAABABfAGwMAAAGAFYAbQwAAAMAUwDqDAAABwBaAG4MAAAEAFUAbwwAAAIAVgALAAkJ5yGTEwDkAgloDAAABQBcAGkMAAAFAFUAawwAAAUAVQBqDAAABABfAGwMAAAGAFYAbQwAAAMAUwDqDAAABwBaAG4MAAAEAFUAbwwAAAIAVgAAAA==.Tinth:BAAALgADCgEJAQAAAA==.Tixi:BAAALgAECgcJBwAAAA==.',
To='Toranaar:BAAALgAECgUJCAABLgAECgkJFgAOANUjAA==.Torresmo:BAAALgAECgEJAQAAAA==.Totahealer:BAAALgAECgMJBQABLgAFFAEJAQAHAAAAAA==.',
Tr='Traix:BAAALgAECgYJEgAAAA==.Trememoita:BAAALgAECgMJAwAAAA==.',
Uh='Uheal:BAAALgAECgMJAwAAAA==.',
Ut='Utherjr:BAAALgAECgMJAwAAAA==.',
Va='Vanthyn:BAAALgAECgEJAQAAAA==.',
Ve='Veccia:BAAALgADCgIJAgAAAA==.Veltharys:BAAALgADCgIJAgAAAA==.',
Vh='Vherk:BAAALgADCgQJBAAAAA==.',
Vi='Visemir:BAAALgADCgQJBAAAAA==.',
We='Wenasnoches:BAAALgADCggJDAAAAA==.',
Wh='Whitetusk:BAAALgADCgcJBwAAAA==.',
Wo='Wonderkast:BAAALgAECgEJAQABLgAFFAgJIAAdABQfAA==.',
Wu='Wurdulak:BAAALgADCgEJBQAAAA==.',
Xa='Xamelo:BAABLgAECn89AAIUAAgJ+iPqBwAxAwhoDAAACgBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABcAGwMAAAHAGAAbQwAAAQAWwDqDAAACwBgAG4MAAADAEQAFAAICfoj6gcAMQMIaAwAAAoAYQBpDAAACQBgAGsMAAAJAGEAagwAAAgAXABsDAAABwBgAG0MAAAEAFsA6gwAAAsAYABuDAAAAwBEAAAA.',
Xi='Xicobruxo:BAAALgAECgUJBgAAAA==.',
Yo='Yona:BAABLgAECn8VAAICAAYJPwqqzAC5AAZoDAAABAAYAGkMAAAEABUAawwAAAUAJQBqDAAABAAtAGwMAAABAB0A6gwAAAMAEgACAAYJPwqqzAC5AAZoDAAABAAYAGkMAAAEABUAawwAAAUAJQBqDAAABAAtAGwMAAABAB0A6gwAAAMAEgABLgAECggJHwAKAHoWAA==.',
Yu='Yushy:BAAALgAFFAMJBAAAAA==.',
Za='Zadockn:BAAALgAECgQJBgAAAA==.',
Zu='Zughy:BAAALgAECgYJCQABLgAFFAgJIAAdABQfAA==.',
['Zé']='Zédaplanta:BAABLgAECn8fAAIXAAYJ+hO1SQBoAQZoDAAACABVAGkMAAAHAD8AawwAAAYAMwBqDAAABAAiAGwMAAABAA0A6gwAAAUAOgAXAAYJ+hO1SQBoAQZoDAAACABVAGkMAAAHAD8AawwAAAYAMwBqDAAABAAiAGwMAAABAA0A6gwAAAUAOgAAAA==.',
['Är']='Ärkin:BAAALgAECgYJCQABLgAECggJMwADAPggAA==.',
['Ðe']='Ðeath:BAAALgAECgYJEgABLgAECggJLwAQAOAjAA==.',
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
