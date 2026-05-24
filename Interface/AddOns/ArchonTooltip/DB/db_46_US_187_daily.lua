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
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-24',data={Aa='Aandheeog:BAAALgAECggJDwAAAA==.',
Ab='Absqwas:BAAALgAECgUJBgAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgcJDwAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8GAAIBAAIJuw+6XQCZAAJoDAAABAAiAGkMAAACAC0AAQACCbsPul0AmQACaAwAAAQAIgBpDAAAAgAtAC4ABAp/OwADAQAJCRQeAxcAdQIAAQAJCRQeAxcAdQIAAgADCfkIxS8AQAAAAAA=.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8XAAQDAAUJLSZ6BwAOAgVoDAAABwBhAGkMAAAFAGEAawwAAAQAYgBqDAAAAgBhAOoMAAAFAGEAAwAFCS0megcADgIFaAwAAAYAYQBpDAAABQBhAGsMAAAEAGIAagwAAAIAYQDqDAAAAwBhAAQAAgmDF2a+AH4AAmgMAAABACoA6gwAAAEATQAFAAEJXgHIaAATAAHqDAAAAQADAAEuAAQKCAkVAAYACRgA.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgYJDgAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBdQbwBxAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAcABwmoF1BvAHEBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMABgABCaMDVEoAHwABawwAAAEACQAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIIAAkJ2xA8HwC+AQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAIAAkJ2xA8HwC+AQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn85AAMJAAkJsQtEMQBuAQloDAAACgAFAGkMAAAIACQAawwAAAgAFgBqDAAACABFAGwMAAAHABwAbQwAAAUANQDqDAAACAAhAG4MAAACAA4AbwwAAAEABQAJAAkJsQtEMQBuAQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAUANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAHAAcJbhEMgwBKAQdoDAAABgBFAGkMAAADADkAawwAAAMAJQBqDAAAAQATAGwMAAABABEA6gwAAAMAQwBuDAAAAQATAAAA.Ashes:BAAALgAECgQJCQABLgAECgkJOQAJALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJDQAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.Atlas:BAAALgAECgIJAgAAAA==.',
Au='Auroranova:BAABLgAECn8mAAMHAAgJhAvmewBYAQhoDAAABgAkAGkMAAAGACUAawwAAAUAEwBqDAAABgAgAGwMAAAFACsAbQwAAAIAIQDqDAAABgAYAG4MAAACAAwABwAICYQL5nsAWAEIaAwAAAYAJABpDAAABQAlAGsMAAAFABMAagwAAAUAIABsDAAABQArAG0MAAACACEA6gwAAAYAGABuDAAAAgAMAAkAAglnCLdvAFIAAmkMAAABAAkAagwAAAEAIQAAAA==.',
Ax='Axél:BAAALgAECgUJCQAAAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgYJDgAAAA==.Brilleleante:BAAALgADCggJGgAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAYJGgAKANIjAA==.Canimai:BAABLgAECn8mAAMLAAgJHxGqNABTAQhoDAAABgA0AGkMAAAGADAAawwAAAYALwBqDAAABAAzAGwMAAAEAC0AbQwAAAMAIQDqDAAABgAjAG4MAAADACwACwAICWsOqjQAUwEIaAwAAAYANABpDAAABgAwAGsMAAAGAC8AagwAAAMAGwBsDAAAAgAXAG0MAAADACEA6gwAAAYAIwBuDAAAAgASAAwAAwmnEXg6AGIAA2oMAAABADMAbAwAAAIALQBuDAAAAQAsAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJDgANAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8LAAMOAAMJQQ2mQQCxAANoDAAABAALAGkMAAAEABYA6gwAAAMAQwAOAAMJQQ2mQQCxAANoDAAAAgALAGkMAAACABYA6gwAAAEAQwAPAAMJMAbhLACvAANoDAAAAgAXAGkMAAACAAIA6gwAAAIAFQAuAAQKfzAAAw8ACQm+EVkoAIIBAA8ACAljElkoAIIBAA4AAgnVCESVAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8ZAAMQAAcJpiBCAQAqAgdoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAABABkAGwMAAABAAsA6gwAAAcAYwBuDAAAAQBjABAABglLJkIBACoCBmgMAAAFAGIAaQwAAAMAXwBrDAAABABhAGoMAAAEAGQA6gwAAAcAYwBuDAAAAQBjABEAAQnlEv08AEwAAWwMAAABADAALgAECn8vAAQQAAkJ8yUWAQC4AwAQAAkJ8yUWAQC4AwASAAYJzRiaLQCjAQARAAMJPw4LYwCVAAAAAA==.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgADCgEJAQAAAA==.Deathcrocker:BAECLgAFFH8cAAITAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwATAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwAuAAQKfxoAAhMACQkDJmwAAMsDABMACQkDJmwAAMsDAAEuAAUUBwkTABIABCMA.Decksey:BAAALgADCgEJAQABLgADCgYJCQANAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABwAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBQkUAAcAixoA.',
Do='Dogs:BAACLgAFFH8PAAILAAUJyiPcBwCVAQVoDAAABABiAGkMAAAEAGIAawwAAAMATQBqDAAAAQBTAOoMAAADAFsACwAFCcoj3AcAlQEFaAwAAAQAYgBpDAAABABiAGsMAAADAE0AagwAAAEAUwDqDAAAAwBbAC4ABAp/GwACCwAICesb1w0A5gIACwAICesb1w0A5gIAAS4ABRQHCRUABwDnGwA=.Domar:BAAALgAECgYJEgAAAA==.Doomslayer:BAABLgAECn8lAAQUAAkJ7BpxRADWAQloDAAACABgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQAUAAkJ7BpxRADWAQloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAFQABCVIKMy4AKwABaAwAAAEAGgAAAA==.Doraei:BAABLgAECn8VAAIUAAgJmw6AZgB5AQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAFAAICZsOgGYAeQEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMWAAcJthtdBgDMAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABYABwm2G10GAMwBB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFwABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSReWTQDCAQloDAAACABRAGkMAAAFAFUAawwAAAUAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAHAAkJSReWTQDCAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAJAAMJIg0xXACYAANoDAAAAgBQAGkMAAABAAUAawwAAAEADgAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgANAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJEgAYAMcgAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8iAAILAAkJOxDUHwDPAQloDAAABgA+AGkMAAAFAC0AawwAAAUAPQBqDAAABQAoAGwMAAAEACgAbQwAAAEAEQDqDAAABQAjAG4MAAACACcAbwwAAAEAHQALAAkJOxDUHwDPAQloDAAABgA+AGkMAAAFAC0AawwAAAUAPQBqDAAABQAoAGwMAAAEACgAbQwAAAEAEQDqDAAABQAjAG4MAAACACcAbwwAAAEAHQAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJBgABLgAECgYJFgAZADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8VAAIaAAgJ4Re3EgD2AQhoDAAAAwBUAGkMAAACAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABQDqDAAABgBdAG4MAAABAA4AGgAICeEXtxIA9gEIaAwAAAMAVABpDAAAAgBhAGsMAAADAEEAagwAAAMAMwBsDAAAAgBDAG0MAAABAAUA6gwAAAYAXQBuDAAAAQAOAC4ABAp/JQAEGgAJCX0iXQ0AWgMAGgAJCX0iXQ0AWgMAGwABCdMgBw0AWQAAHAABCRsPHRoARwAAAAA=.Froslass:BAABLgAECn8ZAAIUAAgJfx1jPQDsAQhoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAFAAICX8dYz0A7AEIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAFFAMJAwAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQGAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAIARwAGAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAIARwAJAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABwABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8cAAMdAAYJchKJCwBzAQZoDAAABgAwAGkMAAAGADkAawwAAAcAPQBqDAAAAwAgAGwMAAACACAA6gwAAAQAJAAdAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAZAAYJYhHfJwAsAQZoDAAAAgAqAGkMAAACADEAawwAAAIAPQBqDAAAAQAgAGwMAAABACAA6gwAAAIAJAABLgAECggJHgABAJEbAA==.',
Gr='Gripmedaddy:BAAALgAECggJEgAAAA==.',
Ha='Haldrian:BAAALgAECgYJDgAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8UAAIOAAYJ7RSTWAAiAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAQAOgAOAAYJ7RSTWAAiAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAQAOgAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMeAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdAB4AAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB8AAwlDClYqAK4AA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHgAICTsh0QsAkwIAHgAICTsh0QsAkwIAHwABCYQPQ2UAMQAAAAA=.Hop:BAABLgAECn82AAIgAAkJDxyXBACQAgloDAAACABVAGkMAAAIAFEAawwAAAgASwBqDAAABgBGAGwMAAAFAFMAbQwAAAQAJgDqDAAACABQAG4MAAAFAD4AbwwAAAIARAAgAAkJDxyXBACQAgloDAAACABVAGkMAAAIAFEAawwAAAgASwBqDAAABgBGAGwMAAAFAFMAbQwAAAQAJgDqDAAACABQAG4MAAAFAD4AbwwAAAIARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAeAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAeAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAECgQJBwAAAA==.',
Iv='Ivakor:BAAALgAECgYJDgAAAA==.Ivyy:BAACLgAFFH8PAAIhAAQJHSEQDwBuAQRoDAAABABWAGkMAAAFAFwAawwAAAEAPgDqDAAABQBhACEABAkdIRAPAG4BBGgMAAAEAFYAaQwAAAUAXABrDAAAAQA+AOoMAAAFAGEALgAECn8XAAIhAAgJEiK5DQDAAgAhAAgJEiK5DQDAAgABLgAFFAcJHQAZAD4ZAA==.',
Ja='Jackswagz:BAABLgAECn8nAAMOAAkJ8BOwMQDBAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABgA3AG4MAAAEAB8AbwwAAAIAEwAOAAkJ8BOwMQDBAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABQA3AG4MAAADAB8AbwwAAAIAEwAPAAQJbAfmXQCdAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8vAAIDAAkJZxbEBQAdAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAEAEwDqDAAABwBGAG4MAAAEADQAbwwAAAEAKAADAAkJZxbEBQAdAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAEAEwDqDAAABwBGAG4MAAAEADQAbwwAAAEAKAAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAATAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQaAAcJ6iT9KwBOAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABoABwnqJP0rAE4CB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAHAACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABsAAQkAADwSABcAAWoMAAABAAUAAAA=.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECgcJBwAAAA==.',
Kv='Kvasir:BAABLgAECn8yAAIUAAkJexmGJQBOAgloDAAACQBUAGkMAAAHAEEAawwAAAcANgBqDAAABwBAAGwMAAAGAEsAbQwAAAQAQgDqDAAABwA/AG4MAAACAEUAbwwAAAEAKgAUAAkJexmGJQBOAgloDAAACQBUAGkMAAAHAEEAawwAAAcANgBqDAAABwBAAGwMAAAGAEsAbQwAAAQAQgDqDAAABwA/AG4MAAACAEUAbwwAAAEAKgAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8UAAIHAAUJixo4CgBbAQVoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAOoMAAAEAC8ABwAFCYsaOAoAWwEFaAwAAAYAVABpDAAABQBIAGsMAAAEAEMAagwAAAEAHgDqDAAABAAvAC4ABAp/HQACBwAICTQd2jEAWwIABwAICTQd2jEAWwIAAAA=.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJCwAIAPQCAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8eAAMTAAgJKRWyHwApAQhoDAAABgA+AGkMAAAEAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAFAAHCTwNR48AYgEHaAwAAAUALgBpDAAAAwAmAGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgATAAUJjhyyHwApAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8TAAISAAcJBCNgAADSAgdoDAAAAwBaAGkMAAAFAF8AawwAAAMAXQBsDAAAAQBhAG0MAAACAEsA6gwAAAQAWwBuDAAAAQBUABIABwkEI2AAANICB2gMAAADAFoAaQwAAAUAXwBrDAAAAwBdAGwMAAABAGEAbQwAAAIASwDqDAAABABbAG4MAAABAFQALgAECn8VAAISAAcJ8SXADQC3AgASAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgYJCQAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgcJEQABLgAFFAQJDgATAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8KAAMHAAIJRxvMYwCoAAJoDAAABgA5AOoMAAAEAFIABwACCUcbzGMAqAACaAwAAAUAOQDqDAAABABSAAkAAQlpCB1AADcAAWgMAAABABUALgAECn82AAMHAAkJiiBpDAArAwAHAAkJiiBpDAArAwAJAAkJIxawEwBPAgAAAA==.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Og='Ogganborn:BAABLgAECn8aAAIBAAUJbR0JUgCAAQVoDAAABQBOAGkMAAAHAEsAawwAAAYANgBsDAAAAwBPAOoMAAAFAFcAAQAFCW0dCVIAgAEFaAwAAAUATgBpDAAABwBLAGsMAAAGADYAbAwAAAMATwDqDAAABQBXAAAA.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hKGgQBNAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAcABwnaEoaBAE0BB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8uAAMSAAkJoRz7CQB4AgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAASAAkJoRz7CQB4AgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAQAAIJIRNlYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAABLgAECn8VAAMGAAgJCRgCEgB9AQhoDAAAAgA9AGkMAAADAF8AawwAAAMAYABqDAAAAwBhAGwMAAACACIAbQwAAAIAMADqDAAABQBYAG4MAAABAAYABwAICfsP4WUAhgEIaAwAAAEAGgBpDAAAAgA3AGsMAAACADEAagwAAAIAMwBsDAAAAgAiAG0MAAACADAA6gwAAAEAQQBuDAAAAQAGAAYABQleIQISAH0BBWgMAAABAD0AaQwAAAEAXwBrDAAAAQBgAGoMAAABAGEA6gwAAAQAWAAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAQABkcAA==.Railiana:BAABLgAECn8dAAIBAAYJUAmBiAAAAQZoDAAABgAuAGkMAAAGABMAawwAAAUAEgBqDAAABAAVAGwMAAADAA0A6gwAAAUAFQABAAYJUQmBiAAAAQZoDAAABgAuAGkMAAAGABMAawwAAAUAEgBqDAAABAAVAGwMAAADAA0A6gwAAAUAFQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8vAAQiAAgJXiGLEgCZAghoDAAACABcAGkMAAAIAFcAawwAAAUAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAACACcAIgAICV4hixIAmQIIaAwAAAcAXABpDAAABgBXAGsMAAAEAFQAagwAAAYAYABsDAAABwBjAG0MAAADAFcA6gwAAAgAYABuDAAAAgAnACAAAwlXFXgrAH8AA2gMAAABAC0AaQwAAAEAPQBrDAAAAQA4ACEAAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAQAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIMAAgJNhkRAQD/AQhoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAG8MAAABAD0ADAAICTYZEQEA/wEIaAwAAAIATgBpDAAAAgBeAGsMAAACAC8AagwAAAEAHwBtDAAAAQAsAOoMAAAEAE0AbgwAAAEAMABvDAAAAQA9AC4ABAp/HAACDAAICZsltQEAaAMADAAICZsltQEAaAMAAAA=.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIaAAYJNA7crAAOAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAaAAYJNA7crAAOAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAAAA==.',
Sa='Saelki:BAAALgADCgkJBwAAAA==.',
Se='Sephiran:BAABLgAECn8wAAMjAAkJ8B0KCwCAAgloDAAABwBYAGkMAAAHAFAAawwAAAcARwBqDAAABgBTAGwMAAAGAEoAbQwAAAQAOQDqDAAABwBYAG4MAAADAEsAbwwAAAEATAAjAAkJ8B0KCwCAAgloDAAABABYAGkMAAADAFAAawwAAAMARwBqDAAAAgBTAGwMAAACAEoAbQwAAAIAOQDqDAAAAwBYAG4MAAACAEsAbwwAAAEATAAfAAgJyRfrEwAWAghoDAAAAwA6AGkMAAAEAEMAawwAAAQAPwBqDAAABAA5AGwMAAAEAEsAbQwAAAIAMgDqDAAABAA6AG4MAAABADYAAAA=.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8WAAIZAAYJPCMmFQDSAQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAZAAYJPCMmFQDSAQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAAAA==.Shoepert:BAABLgAECn84AAILAAkJbSWXAgAxAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAALAAkJbSWXAgAxAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgMJAwABLgAECgYJFgAZADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgANAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgYJDgAAAA==.',
Te='Tempus:BAACLgAFFH8OAAIJAAQJdBcAGAA0AQRoDAAABQBZAGkMAAAFADkAawwAAAEAAQDqDAAAAwBbAAkABAl0FwAYADQBBGgMAAAFAFkAaQwAAAUAOQBrDAAAAQABAOoMAAADAFsALgAECn8kAAQJAAgJphxhFABIAgAJAAgJphxhFABIAgAHAAEJ/QoLZwExAAAGAAEJqwwxRgAqAAAAAA==.Tenletters:BAAALgAFFAEJAQAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCggJHgAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgYJDgAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAIJCgAHAEcbAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAQAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8aAAQFAAgJIxRFGACNAQhoDAAABgBDAGkMAAAEAEEAawwAAAQANgBqDAAAAwAmAGwMAAACAC4AbQwAAAEAKwDqDAAABQA6AG4MAAABABoABQAICSMURRgAjQEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAgAuAG0MAAABACsA6gwAAAUAOgBuDAAAAQAaAAQAAQnnAWIRARcAAWgMAAABAAQAAwABCT8B+jQAEQABaAwAAAEAAwAAAA==.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIeAAcJ+htqAQBVAgdoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwBuDAAAAQAQAB4ABwn6G2oBAFUCB2gMAAAGAGMAaQwAAAUATABrDAAABABFAGoMAAADAEcAbAwAAAEASwDqDAAABwBbAG4MAAABABAALgAECn8uAAMeAAkJuh4bBQD/AgAeAAkJuh4bBQD/AgAjAAQJYQ7tSgC4AAAAAA==.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAITAAUJxRMcBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEwAFCcUTHAQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/FAADEwAICdwdNBIA6AEAEwAICfwcNBIA6AEAFAAGCf0aNX4AhwEAAAA=.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAQJDgAIABQNAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJDAAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMMAAcJSRwPFQB9AQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAwABgnuHQ8VAH0BBmgMAAABAFAAaQwAAAEASABrDAAAAQBPAGoMAAABAEcAbAwAAAEATQDqDAAAAQBJAAsABwllGeEuAHEBB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkAAS4ABAoJCTAAIwDwHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
