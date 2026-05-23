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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Protection','Paladin-Retribution','Evoker-Augmentation','Paladin-Holy','Hunter-Survival','Warrior-Fury','Warrior-Protection','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-22',data={Aa='Aandheeog:BAAALgAECggJDwAAAA==.',
Ab='Absqwas:BAAALgAECgQJBAAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgcJDwAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8yAAMBAAkJFB4AGABqAgloDAAABQBVAGkMAAAFAEsAawwAAAgAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAABAAkJFB4AGABqAgloDAAABABVAGkMAAAFAEsAawwAAAcAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAACAAIJsAK2gQBAAAJoDAAAAQAEAGsMAAABAAkAAAA=.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8XAAQDAAUJLSZ6BwAOAgVoDAAABwBhAGkMAAAFAGEAawwAAAQAYgBqDAAAAgBhAOoMAAAFAGEAAwAFCS0megcADgIFaAwAAAYAYQBpDAAABQBhAGsMAAAEAGIAagwAAAIAYQDqDAAAAwBhAAQAAgmDF0u6AIAAAmgMAAABACoA6gwAAAEATQAFAAEJXgFfZQATAAHqDAAAAQADAAEuAAQKCAkVAAYACRgA.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgYJDgAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBccawB2AQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAcABwmoFxxrAHYBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMABgABCaMDUkgAHwABawwAAAEACQAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIIAAkJ2xBxHgC9AQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAIAAkJ2xBxHgC9AQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn85AAMJAAkJsQsgMABuAQloDAAACgAFAGkMAAAIACQAawwAAAgAFgBqDAAACABFAGwMAAAHABwAbQwAAAUANQDqDAAACAAhAG4MAAACAA4AbwwAAAEABQAJAAkJsQsgMABuAQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAUANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAHAAcJbhGGfgBOAQdoDAAABgBFAGkMAAADADkAawwAAAMAJQBqDAAAAQATAGwMAAABABEA6gwAAAMAQwBuDAAAAQATAAAA.Ashes:BAAALgAECgQJCQABLgAECgkJOQAJALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJDQAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.Atlas:BAAALgAECgIJAgAAAA==.',
Au='Auroranova:BAABLgAECn8mAAMHAAgJhAvtdwBbAQhoDAAABgAkAGkMAAAGACUAawwAAAUAEwBqDAAABgAgAGwMAAAFACsAbQwAAAIAIQDqDAAABgAYAG4MAAACAAwABwAICYQL7XcAWwEIaAwAAAYAJABpDAAABQAlAGsMAAAFABMAagwAAAUAIABsDAAABQArAG0MAAACACEA6gwAAAYAGABuDAAAAgAMAAkAAglnCHJtAFIAAmkMAAABAAkAagwAAAEAIQAAAA==.',
Ax='Axél:BAAALgAECgUJCQAAAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgYJDgAAAA==.Brilleleante:BAAALgADCggJGgAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAYJGgAKANIjAA==.Canimai:BAABLgAECn8mAAMLAAgJHxEmMwBUAQhoDAAABgA0AGkMAAAGADAAawwAAAYALwBqDAAABAAzAGwMAAAEAC0AbQwAAAMAIQDqDAAABgAjAG4MAAADACwACwAICWsOJjMAVAEIaAwAAAYANABpDAAABgAwAGsMAAAGAC8AagwAAAMAGwBsDAAAAgAXAG0MAAADACEA6gwAAAYAIwBuDAAAAgASAAwAAwmnEUo5AGIAA2oMAAABADMAbAwAAAIALQBuDAAAAQAsAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJDgANAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8LAAMOAAMJQQ14PgCyAANoDAAABAALAGkMAAAEABYA6gwAAAMAQwAOAAMJQQ14PgCyAANoDAAAAgALAGkMAAACABYA6gwAAAEAQwAPAAMJMAYfKwCvAANoDAAAAgAXAGkMAAACAAIA6gwAAAIAFQAuAAQKfy0AAw8ACQm+ETQnAIIBAA8ACAljEjQnAIIBAA4AAgnVCDuRAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8ZAAMQAAcJpiAsAQArAgdoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAABABkAGwMAAABAAsA6gwAAAcAYwBuDAAAAQBjABAABglLJiwBACsCBmgMAAAFAGIAaQwAAAMAXwBrDAAABABhAGoMAAAEAGQA6gwAAAcAYwBuDAAAAQBjABEAAQnlEnk5AE0AAWwMAAABADAALgAECn8vAAQQAAkJ8yUWAQC4AwAQAAkJ8yUWAQC4AwASAAYJzRiaLQCjAQARAAMJPw7NXgCUAAAAAA==.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgADCgEJAQAAAA==.Deathcrocker:BAECLgAFFH8cAAITAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwATAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwAuAAQKfxoAAhMACQkDJmwAAMsDABMACQkDJmwAAMsDAAEuAAUUBwkTABIABCMA.Decksey:BAAALgADCgEJAQABLgADCgYJCQANAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABwAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBQkUAAcAixoA.',
Do='Dogs:BAACLgAFFH8PAAILAAUJyiMtBwCYAQVoDAAABABiAGkMAAAEAGIAawwAAAMATQBqDAAAAQBTAOoMAAADAFsACwAFCcojLQcAmAEFaAwAAAQAYgBpDAAABABiAGsMAAADAE0AagwAAAEAUwDqDAAAAwBbAC4ABAp/GwACCwAICesb1w0A5gIACwAICesb1w0A5gIAAS4ABRQHCRUABwDnGwA=.Domar:BAAALgAECgYJEgAAAA==.Doomslayer:BAABLgAECn8lAAQUAAkJ7BqZQgDYAQloDAAACABgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQAUAAkJ7BqZQgDYAQloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAFQABCVIK+ysAKwABaAwAAAEAGgAAAA==.Doraei:BAABLgAECn8VAAIUAAgJmw7HYgB+AQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAFAAICZsOx2IAfgEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMWAAcJthsmBgDOAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABYABwm2GyYGAM4BB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFwABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRd6SQDIAQloDAAACABRAGkMAAAFAFUAawwAAAUAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAHAAkJSRd6SQDIAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAJAAMJIg04WgCZAANoDAAAAgBQAGkMAAABAAUAawwAAAEADgAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgANAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJEgAYAMcgAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8iAAILAAkJOxBSHgDVAQloDAAABgA+AGkMAAAFAC0AawwAAAUAPQBqDAAABQAoAGwMAAAEACgAbQwAAAEAEQDqDAAABQAjAG4MAAACACcAbwwAAAEAHQALAAkJOxBSHgDVAQloDAAABgA+AGkMAAAFAC0AawwAAAUAPQBqDAAABQAoAGwMAAAEACgAbQwAAAEAEQDqDAAABQAjAG4MAAACACcAbwwAAAEAHQAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJBgABLgAECgYJFgAZADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8VAAIaAAgJ4RewEAD/AQhoDAAAAwBUAGkMAAACAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABQDqDAAABgBdAG4MAAABAA4AGgAICeEXsBAA/wEIaAwAAAMAVABpDAAAAgBhAGsMAAADAEEAagwAAAMAMwBsDAAAAgBDAG0MAAABAAUA6gwAAAYAXQBuDAAAAQAOAC4ABAp/JQAEGgAJCX0iXQ0AWgMAGgAJCX0iXQ0AWgMAGwABCdMgBw0AWQAAHAABCRsPHRoARwAAAAA=.Froslass:BAABLgAECn8ZAAIUAAgJfx3OOwDuAQhoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAFAAICX8dzjsA7gEIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAFFAMJAwAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQGAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAIARwAGAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAIARwAJAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABwABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8YAAMdAAYJIBKJCwBzAQZoDAAABQAwAGkMAAAFADkAawwAAAYAOQBqDAAAAwAgAGwMAAACACAA6gwAAAMAJAAdAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAZAAYJEBFcKgATAQZoDAAAAQAqAGkMAAABADEAawwAAAEAOQBqDAAAAQAgAGwMAAABACAA6gwAAAEAJAABLgAECggJHgABAJEbAA==.',
Gr='Gripmedaddy:BAAALgAECggJEgAAAA==.',
Ha='Haldrian:BAAALgAECgYJDgAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8UAAIOAAYJ7RQTVgAiAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAQAOgAOAAYJ7RQTVgAiAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAQAOgAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMeAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdAB4AAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB8AAwlDCo0oALAAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHgAICTsh0QsAkwIAHgAICTsh0QsAkwIAHwABCYQPZmIAMQAAAAA=.Hop:BAABLgAECn8yAAIgAAkJshujBACHAgloDAAABwBVAGkMAAAHAFEAawwAAAcASwBqDAAABgBGAGwMAAAFAFMAbQwAAAQAJgDqDAAABwBJAG4MAAAFAD4AbwwAAAIARAAgAAkJshujBACHAgloDAAABwBVAGkMAAAHAFEAawwAAAcASwBqDAAABgBGAGwMAAAFAFMAbQwAAAQAJgDqDAAABwBJAG4MAAAFAD4AbwwAAAIARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAeAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAeAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAECgQJBwAAAA==.',
Iv='Ivakor:BAAALgAECgYJDgAAAA==.Ivyy:BAACLgAFFH8OAAIhAAQJHSHPDQBxAQRoDAAABABWAGkMAAAFAFwAawwAAAEAPgDqDAAABABhACEABAkdIc8NAHEBBGgMAAAEAFYAaQwAAAUAXABrDAAAAQA+AOoMAAAEAGEALgAECn8XAAIhAAgJEiK5DQDAAgAhAAgJEiK5DQDAAgABLgAFFAcJHQAZAD4ZAA==.',
Ja='Jackswagz:BAABLgAECn8nAAMOAAkJ8BMpMADBAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABgA3AG4MAAAEAB8AbwwAAAIAEwAOAAkJ8BMpMADBAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABQA3AG4MAAADAB8AbwwAAAIAEwAPAAQJbAdzWwCdAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8vAAIDAAkJZxZ4BQAhAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAEAEwDqDAAABwBGAG4MAAAEADQAbwwAAAEAKAADAAkJZxZ4BQAhAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAEAEwDqDAAABwBGAG4MAAAEADQAbwwAAAEAKAAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAATAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQaAAcJ6iS4KgBQAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABoABwnqJLgqAFACB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAHAACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABsAAQkAADwSABcAAWoMAAABAAUAAAA=.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECgcJBwAAAA==.',
Kv='Kvasir:BAABLgAECn8pAAIUAAgJxhrFPQDnAQhoDAAACABUAGkMAAAGAEEAawwAAAYANgBqDAAABgA+AGwMAAAFAEsAbQwAAAMAQgDqDAAABgA/AG4MAAABAEUAFAAICcYaxT0A5wEIaAwAAAgAVABpDAAABgBBAGsMAAAGADYAagwAAAYAPgBsDAAABQBLAG0MAAADAEIA6gwAAAYAPwBuDAAAAQBFAAAA.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8UAAIHAAUJixo4CgBbAQVoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAOoMAAAEAC8ABwAFCYsaOAoAWwEFaAwAAAYAVABpDAAABQBIAGsMAAAEAEMAagwAAAEAHgDqDAAABAAvAC4ABAp/HQACBwAICTQd2jEAWwIABwAICTQd2jEAWwIAAAA=.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJCwAIAPQCAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8eAAMTAAgJKRWgHgArAQhoDAAABgA+AGkMAAAEAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAFAAHCTwNR48AYgEHaAwAAAUALgBpDAAAAwAmAGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgATAAUJjhygHgArAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8TAAISAAcJBCNRAADUAgdoDAAAAwBaAGkMAAAFAF8AawwAAAMAXQBsDAAAAQBhAG0MAAACAEsA6gwAAAQAWwBuDAAAAQBUABIABwkEI1EAANQCB2gMAAADAFoAaQwAAAUAXwBrDAAAAwBdAGwMAAABAGEAbQwAAAIASwDqDAAABABbAG4MAAABAFQALgAECn8VAAISAAcJ8SXADQC3AgASAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgYJCQAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCgkJHQAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgcJEQABLgAFFAQJDgATAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8KAAMHAAIJRxuiXgCqAAJoDAAABgA5AOoMAAAEAFIABwACCUcbol4AqgACaAwAAAUAOQDqDAAABABSAAkAAQlpCBc/ADcAAWgMAAABABUALgAECn82AAMHAAkJiiBpDAArAwAHAAkJiiBpDAArAwAJAAkJIxb4EgBRAgAAAA==.',
Og='Ogganborn:BAABLgAECn8VAAIBAAUJuhz6UwB1AQVoDAAABABOAGkMAAAGAEsAawwAAAUALQBsDAAAAgBPAOoMAAAEAFcAAQAFCboc+lMAdQEFaAwAAAQATgBpDAAABgBLAGsMAAAFAC0AbAwAAAIATwDqDAAABABXAAAA.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgADCggJDgAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hIIfQBRAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAcABwnaEgh9AFEBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8uAAMSAAkJoRzECQB5AgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAASAAkJoRzECQB5AgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAQAAIJIRNlYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAABLgAECn8VAAMGAAgJCRiBEQB9AQhoDAAAAgA9AGkMAAADAF8AawwAAAMAYABqDAAAAwBhAGwMAAACACIAbQwAAAIAMADqDAAABQBYAG4MAAABAAYABwAICfsPD2IAigEIaAwAAAEAGgBpDAAAAgA3AGsMAAACADEAagwAAAIAMwBsDAAAAgAiAG0MAAACADAA6gwAAAEAQQBuDAAAAQAGAAYABQleIYERAH0BBWgMAAABAD0AaQwAAAEAXwBrDAAAAQBgAGoMAAABAGEA6gwAAAQAWAAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAQABkcAA==.Railiana:BAABLgAECn8XAAIBAAYJIwm6hQD+AAZoDAAABQAuAGkMAAAFABMAawwAAAQAEgBqDAAAAwAVAGwMAAACAA0A6gwAAAQAEwABAAYJIwm6hQD+AAZoDAAABQAuAGkMAAAFABMAawwAAAQAEgBqDAAAAwAVAGwMAAACAA0A6gwAAAQAEwAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8vAAQiAAgJXiEVEgCaAghoDAAACABcAGkMAAAIAFcAawwAAAUAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAACACcAIgAICV4hFRIAmgIIaAwAAAcAXABpDAAABgBXAGsMAAAEAFQAagwAAAYAYABsDAAABwBjAG0MAAADAFcA6gwAAAgAYABuDAAAAgAnACAAAwlXFQUqAH8AA2gMAAABAC0AaQwAAAEAPQBrDAAAAQA4ACEAAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAQAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIMAAgJNhkRAQD/AQhoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAG8MAAABAD0ADAAICTYZEQEA/wEIaAwAAAIATgBpDAAAAgBeAGsMAAACAC8AagwAAAEAHwBtDAAAAQAsAOoMAAAEAE0AbgwAAAEAMABvDAAAAQA9AC4ABAp/HAACDAAICZsltQEAaAMADAAICZsltQEAaAMAAAA=.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIaAAYJNA6MqAARAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAaAAYJNA6MqAARAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAAAA==.',
Sa='Saelki:BAAALgADCgkJBwAAAA==.',
Se='Sephiran:BAABLgAECn8wAAMjAAkJ8B2XCgCCAgloDAAABwBYAGkMAAAHAFAAawwAAAcARwBqDAAABgBTAGwMAAAGAEoAbQwAAAQAOQDqDAAABwBYAG4MAAADAEsAbwwAAAEATAAjAAkJ8B2XCgCCAgloDAAABABYAGkMAAADAFAAawwAAAMARwBqDAAAAgBTAGwMAAACAEoAbQwAAAIAOQDqDAAAAwBYAG4MAAACAEsAbwwAAAEATAAfAAgJyRc+EwAXAghoDAAAAwA6AGkMAAAEAEMAawwAAAQAPwBqDAAABAA5AGwMAAAEAEsAbQwAAAIAMgDqDAAABAA6AG4MAAABADYAAAA=.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8WAAIZAAYJPCORFADVAQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAZAAYJPCORFADVAQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAAAA==.Shoepert:BAABLgAECn84AAILAAkJbSVnAgA0AwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAALAAkJbSVnAgA0AwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgANAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgYJDgAAAA==.',
Te='Tempus:BAACLgAFFH8OAAIJAAQJdBdRFwA5AQRoDAAABQBZAGkMAAAFADkAawwAAAEAAQDqDAAAAwBbAAkABAl0F1EXADkBBGgMAAAFAFkAaQwAAAUAOQBrDAAAAQABAOoMAAADAFsALgAECn8kAAQJAAgJphyYEwBKAgAJAAgJphyYEwBKAgAHAAEJ/Qr4XQExAAAGAAEJqwxFRAAqAAAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCggJHgAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJAwAAAA==.',
Ty='Tyrgrim:BAAALgAECgYJDgAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAIJCgAHAEcbAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8aAAQFAAgJIxSAFwCPAQhoDAAABgBDAGkMAAAEAEEAawwAAAQANgBqDAAAAwAmAGwMAAACAC4AbQwAAAEAKwDqDAAABQA6AG4MAAABABoABQAICSMUgBcAjwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAgAuAG0MAAABACsA6gwAAAUAOgBuDAAAAQAaAAQAAQnnATwLARgAAWgMAAABAAQAAwABCT8BbzMAEQABaAwAAAEAAwAAAA==.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIeAAcJ+htZAQBWAgdoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwBuDAAAAQAQAB4ABwn6G1kBAFYCB2gMAAAGAGMAaQwAAAUATABrDAAABABFAGoMAAADAEcAbAwAAAEASwDqDAAABwBbAG4MAAABABAALgAECn8uAAMeAAkJuh4bBQD/AgAeAAkJuh4bBQD/AgAjAAQJYQ4JSQC4AAAAAA==.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAITAAUJxRMcBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEwAFCcUTHAQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/FAADEwAICdwdNBIA6AEAEwAICfwcNBIA6AEAFAAGCf0aNX4AhwEAAAA=.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgMJAwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAQJDgAIABQNAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJDAAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMMAAcJSRxyFAB/AQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAwABgnuHXIUAH8BBmgMAAABAFAAaQwAAAEASABrDAAAAQBPAGoMAAABAEcAbAwAAAEATQDqDAAAAQBJAAsABwllGXYtAHIBB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkAAS4ABAoJCTAAIwDwHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
Zy='Zynri:BAAALgADCgYJBwAAAA==.',
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
