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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Evoker-Augmentation','Paladin-Holy','Hunter-Survival','Warrior-Fury','Warrior-Protection','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-30',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECgUJCAAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCggJEwAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8JAAIBAAMJ7w4dTQDnAANoDAAABQAiAGkMAAADADkA6gwAAAEAFgABAAMJ7w4dTQDnAANoDAAABQAiAGkMAAADADkA6gwAAAEAFgAuAAQKfzwAAwEACQkcHsoYAHsCAAEACQkcHsoYAHsCAAIAAwn5CHIyAD8AAAAA.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8dAAQDAAcJ7CJ6BwAOAgdoDAAACABhAGkMAAAGAGEAawwAAAUAYgBqDAAAAwBhAGwMAAABAEQAbQwAAAEATQDqDAAABQBhAAMABQktJnoHAA4CBWgMAAAGAGEAaQwAAAUAYQBrDAAABABiAGoMAAACAGEA6gwAAAMAYQAEAAcJjBafGACcAQdoDAAAAQAzAGkMAAABAEUAawwAAAEATABqDAAAAQA5AGwMAAABAEQAbQwAAAEATQDqDAAAAQADAAUAAgmDF/LGAHsAAmgMAAABACoA6gwAAAEATQABLgAECggJFgAGAFMYAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgYJDgAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBdYdgBnAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAcABwmoF1h2AGcBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMABgABCaMDQk8AHwABawwAAAEACQAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIIAAkJ2xDNIQCwAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAIAAkJ2xDNIQCwAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn85AAMJAAkJsQv6MwBtAQloDAAACgAFAGkMAAAIACQAawwAAAgAFgBqDAAACABFAGwMAAAHABwAbQwAAAUANQDqDAAACAAhAG4MAAACAA4AbwwAAAEABQAJAAkJsQv6MwBtAQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAUANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAHAAcJbhFvjAA9AQdoDAAABgBFAGkMAAADADkAawwAAAMAJQBqDAAAAQATAGwMAAABABEA6gwAAAMAQwBuDAAAAQATAAAA.Ashes:BAAALgAECgQJCQABLgAECgkJOQAJALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJDwAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.Atlas:BAAALgAECgIJAgAAAA==.',
Au='Auroranova:BAABLgAECn8rAAMHAAkJKg2kXwCYAQloDAAABwAsAGkMAAAGACUAawwAAAUAEwBqDAAABwA3AGwMAAAGACsAbQwAAAMANQDqDAAABgAYAG4MAAACAAwAbwwAAAEAIgAHAAkJKg2kXwCYAQloDAAABwAsAGkMAAAFACUAawwAAAUAEwBqDAAABgA3AGwMAAAGACsAbQwAAAMANQDqDAAABgAYAG4MAAACAAwAbwwAAAEAIgAJAAIJZwjCdABRAAJpDAAAAQAJAGoMAAABACEAAAA=.',
Ax='Axél:BAAALgAECgUJCQAAAA==.',
Ba='Baddragon:BAAALgAECgIJAQABLgAFFAYJFQAHAHgXAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgYJDgAAAA==.Brilleleante:BAAALgADCggJHgAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAcJHAAKAAgfAA==.Canimai:BAACLgAFFH8GAAILAAIJzQFfQABtAAJoDAAAAwAEAOoMAAADAAQACwACCc0BX0AAbQACaAwAAAMABADqDAAAAwAEAC4ABAp/JwADCwAJCYERmyoAlwEACwAJCSQPmyoAlwEADAADCacR+j4AXQAAAAA=.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJDgANAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIFAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAFAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8PAAMOAAQJPwygNgDqAARoDAAABQAVAGkMAAAFABYAawwAAAEADgDqDAAABABDAA4ABAk/DKA2AOoABGgMAAADABUAaQwAAAMAFgBrDAAAAQAOAOoMAAABAEMADwADCTAGKDIAowADaAwAAAIAFwBpDAAAAgACAOoMAAADABUALgAECn8zAAMPAAkJpRLHKQCJAQAPAAgJbBPHKQCJAQAOAAIJ1QgnnwBmAAAAAA==.',
Cu='Cubes:BAACLgAFFH8ZAAMQAAcJpiB6AAAjAgdoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAABABkAGwMAAABAAsA6gwAAAcAYwBuDAAAAQBjABAABglLJnoAACMCBmgMAAAFAGIAaQwAAAMAXwBrDAAABABhAGoMAAAEAGQA6gwAAAcAYwBuDAAAAQBjABEAAQnlEqxGAEoAAWwMAAABADAALgAECn8vAAQQAAkJ8yUWAQC4AwAQAAkJ8yUWAQC4AwASAAYJzRiaLQCjAQARAAMJPw7fbQCUAAAAAA==.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgADCgUJBQAAAA==.Deathcrocker:BAECLgAFFH8cAAITAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwATAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwAuAAQKfxoAAhMACQkDJmwAAMsDABMACQkDJmwAAMsDAAEuAAUUBwkVABIAeCQA.Decksey:BAAALgADCgEJAQABLgADCgYJCQANAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABwAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBgkVAAcAeBcA.',
Do='Dogs:BAACLgAFFH8PAAILAAUJyiPSCgCNAQVoDAAABABiAGkMAAAEAGIAawwAAAMATQBqDAAAAQBTAOoMAAADAFsACwAFCcoj0goAjQEFaAwAAAQAYgBpDAAABABiAGsMAAADAE0AagwAAAEAUwDqDAAAAwBbAC4ABAp/GwACCwAICesb1w0A5gIACwAICesb1w0A5gIAAS4ABRQHCRkABwA/HAA=.Domar:BAAALgAECgYJEgAAAA==.Doomslayer:BAABLgAECn8lAAQUAAkJ7BqZSQDTAQloDAAACABgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQAUAAkJ7BqZSQDTAQloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAFQABCVIKjjgAGQABaAwAAAEAGgAAAA==.Doraei:BAABLgAECn8VAAIUAAgJmw4obQB2AQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAFAAICZsOKG0AdgEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMWAAcJthslBwDIAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABYABwm2GyUHAMgBB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFwABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRdiVAC0AQloDAAACABRAGkMAAAFAFUAawwAAAUAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAHAAkJSRdiVAC0AQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAJAAMJIg1PYACYAANoDAAAAgBQAGkMAAABAAUAawwAAAEADgAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgANAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJFQAYADwjAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8pAAILAAkJSxD3IADVAQloDAAABwA+AGkMAAAGAC0AawwAAAYAPwBqDAAABgAoAGwMAAAFACgAbQwAAAEAEQDqDAAABgAjAG4MAAADACcAbwwAAAEAHQALAAkJSxD3IADVAQloDAAABwA+AGkMAAAGAC0AawwAAAYAPwBqDAAABgAoAGwMAAAFACgAbQwAAAEAEQDqDAAABgAjAG4MAAADACcAbwwAAAEAHQAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJCgABLgAECgYJFgAZADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8XAAMaAAgJ4ReFCgDLAQhoDAAABABUAGkMAAADAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABQDqDAAABgBdAG4MAAABAA4AGgAICeEXhQoAywEIaAwAAAMAVABpDAAAAgBhAGsMAAADAEEAagwAAAMAMwBsDAAAAgBDAG0MAAABAAUA6gwAAAYAXQBuDAAAAQAOABsAAgkQFv8CAJEAAmgMAAABAEMAaQwAAAEALQAuAAQKfyUABBoACQl9Il0NAFoDABoACQl9Il0NAFoDABsAAQnTIAcNAFkAABwAAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAIUAAgJfx31QQDqAQhoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAFAAICX8d9UEA6gEIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEALgAECgMJAwABLgAFFAcJFQASAHgkAA==.Getoffenris:BAAALgAFFAMJAwAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQGAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAIARwAGAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAIARwAJAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABwABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8dAAMdAAYJABSJCwBzAQZoDAAABgAwAGkMAAAGADkAawwAAAcAPQBqDAAAAwAgAGwMAAADADQA6gwAAAQAJAAdAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAZAAYJ8BKsKAA2AQZoDAAAAgAqAGkMAAACADEAawwAAAIAPQBqDAAAAQAgAGwMAAACADQA6gwAAAIAJAABLgAECggJHgABAJEbAA==.',
Ha='Haldrian:BAAALgAECgYJDgAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8UAAIOAAYJ7RTwXgAhAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAQAOgAOAAYJ7RTwXgAhAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAQAOgAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMeAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdAB4AAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB8AAwlDCsQvAJ0AA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHgAICTsh0QsAkwIAHgAICTsh0QsAkwIAHwABCYQP0GsAMQAAAAA=.Hop:BAABLgAECn82AAIgAAkJDxxQBQCCAgloDAAACABVAGkMAAAIAFEAawwAAAgASwBqDAAABgBGAGwMAAAFAFMAbQwAAAQAJgDqDAAACABQAG4MAAAFAD4AbwwAAAIARAAgAAkJDxxQBQCCAgloDAAACABVAGkMAAAIAFEAawwAAAgASwBqDAAABgBGAGwMAAAFAFMAbQwAAAQAJgDqDAAACABQAG4MAAAFAD4AbwwAAAIARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAeAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAeAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAECgUJDAAAAA==.',
Iv='Ivakor:BAAALgAECgYJDgAAAA==.Ivyy:BAACLgAFFH8PAAIhAAQJHSGuEQBhAQRoDAAABABWAGkMAAAFAFwAawwAAAEAPgDqDAAABQBhACEABAkdIa4RAGEBBGgMAAAEAFYAaQwAAAUAXABrDAAAAQA+AOoMAAAFAGEALgAECn8XAAIhAAgJEiK5DQDAAgAhAAgJEiK5DQDAAgABLgAFFAcJHQAZAD4ZAA==.',
Ja='Jackswagz:BAABLgAECn8pAAMOAAkJHhQrNADFAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABwA3AG4MAAAFACMAbwwAAAIAEwAOAAkJHhQrNADFAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABgA3AG4MAAAEACMAbwwAAAIAEwAPAAQJbAdMZACcAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8wAAIDAAkJABfRBQArAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAEAEwDqDAAABwBGAG4MAAAFAEAAbwwAAAEAKAADAAkJABfRBQArAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAEAEwDqDAAABwBGAG4MAAAFAEAAbwwAAAEAKAAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAATAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQaAAcJ6iS2LwBDAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABoABwnqJLYvAEMCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAHAACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABsAAQkAADwSABcAAWoMAAABAAUAAAA=.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECggJCQAAAA==.',
Kv='Kvasir:BAABLgAECn86AAIUAAkJAxwZGgCWAgloDAAACgBUAGkMAAAIAE8AawwAAAgARQBqDAAACABAAGwMAAAHAEsAbQwAAAQAQgDqDAAACABRAG4MAAADAEsAbwwAAAIAKgAUAAkJAxwZGgCWAgloDAAACgBUAGkMAAAIAE8AawwAAAgARQBqDAAACABAAGwMAAAHAEsAbQwAAAQAQgDqDAAACABRAG4MAAADAEsAbwwAAAIAKgAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8VAAIHAAYJeBfRGQB6AQZoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAGwMAAABABwA6gwAAAQALwAHAAYJeBfRGQB6AQZoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAGwMAAABABwA6gwAAAQALwAuAAQKfx0AAgcACAk0HdoxAFsCAAcACAk0HdoxAFsCAAAA.Lieb:BAAALgAECgMJAwAAAA==.Lihrna:BAAALgAECgIJAgAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJDQAIAIsDAA==.Maegii:BAAALgADCgEJAQAAAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMTAAgJKRVXIgAlAQhoDAAABwA+AGkMAAAFAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAFAAHCV8OR48AYgEHaAwAAAYAMABpDAAABAA2AGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgATAAUJjhxXIgAlAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAISAAcJeCRmAADgAgdoDAAAAwBaAGkMAAAFAF8AawwAAAMAXQBsDAAAAQBhAG0MAAADAF0A6gwAAAUAYwBuDAAAAQBUABIABwl4JGYAAOACB2gMAAADAFoAaQwAAAUAXwBrDAAAAwBdAGwMAAABAGEAbQwAAAMAXQDqDAAABQBjAG4MAAABAFQALgAECn8VAAISAAcJ8SXADQC3AgASAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgYJCQAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgQJBwAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgcJEwABLgAFFAUJEAATAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8LAAMHAAIJRxt0cACeAAJoDAAABwA5AOoMAAAEAFIABwACCUcbdHAAngACaAwAAAYAOQDqDAAABABSAAkAAQlpCOtCADcAAWgMAAABABUALgAECn87AAMHAAkJqSFpDAArAwAHAAkJqSFpDAArAwAJAAkJIxZ+FQBKAgAAAA==.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Og='Ogganborn:BAABLgAECn8eAAIBAAYJFR8VQwDBAQZoDAAABgBYAGkMAAAIAE0AawwAAAcAPwBqDAAAAQBeAGwMAAADAE8A6gwAAAUAVwABAAYJFR8VQwDBAQZoDAAABgBYAGkMAAAIAE0AawwAAAcAPwBqDAAAAQBeAGwMAAADAE8A6gwAAAUAVwAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hJBiQBDAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAcABwnaEkGJAEMBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8uAAMSAAkJoRzxCgBzAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAASAAkJoRzxCgBzAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAQAAIJIRNlYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAEALgAFFAEJAQABLgAFFAcJFQASAHgkAA==.',
Py='Pyrithyr:BAABLgAECn8WAAMGAAgJUxjIEgCCAQhoDAAAAgA9AGkMAAADAF8AawwAAAMAYABqDAAAAwBhAGwMAAACACIAbQwAAAIAMADqDAAABgBdAG4MAAABAAYABgAFCeAhyBIAggEFaAwAAAEAPQBpDAAAAQBfAGsMAAABAGAAagwAAAEAYQDqDAAABQBdAAcACAn7D6ByAG4BCGgMAAABABoAaQwAAAIANwBrDAAAAgAxAGoMAAACADMAbAwAAAIAIgBtDAAAAgAwAOoMAAABAEEAbgwAAAEABgAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAQABkcAA==.Railiana:BAABLgAECn8dAAIBAAYJUAklkgAAAQZoDAAABgAuAGkMAAAGABMAawwAAAUAEgBqDAAABAAVAGwMAAADAA0A6gwAAAUAFQABAAYJUAklkgAAAQZoDAAABgAuAGkMAAAGABMAawwAAAUAEgBqDAAABAAVAGwMAAADAA0A6gwAAAUAFQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8yAAUiAAkJ0SDeCwDxAgloDAAACABcAGkMAAAIAFcAawwAAAYAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAADAEAAbwwAAAEALwAiAAkJ0SDeCwDxAgloDAAABwBcAGkMAAAGAFcAawwAAAQAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAADAEAAbwwAAAEALwAgAAMJVxXELwB6AANoDAAAAQAtAGkMAAABAD0AawwAAAEAOAAjAAEJhhuWUABPAAFrDAAAAQBGACEAAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAQAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIMAAgJNhkRAQD/AQhoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAG8MAAABAD0ADAAICTYZEQEA/wEIaAwAAAIATgBpDAAAAgBeAGsMAAACAC8AagwAAAEAHwBtDAAAAQAsAOoMAAAEAE0AbgwAAAEAMABvDAAAAQA9AC4ABAp/HAACDAAICZsltQEAaAMADAAICZsltQEAaAMAAAA=.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIaAAYJNA7VtQD8AAZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAaAAYJNA7VtQD8AAZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAAAA==.',
Sa='Saelki:BAAALgADCgkJBwAAAA==.',
Se='Sephiran:BAABLgAECn8wAAMkAAkJ8B1XDAByAgloDAAABwBYAGkMAAAHAFAAawwAAAcARwBqDAAABgBTAGwMAAAGAEoAbQwAAAQAOQDqDAAABwBYAG4MAAADAEsAbwwAAAEATAAkAAkJ8B1XDAByAgloDAAABABYAGkMAAADAFAAawwAAAMARwBqDAAAAgBTAGwMAAACAEoAbQwAAAIAOQDqDAAAAwBYAG4MAAACAEsAbwwAAAEATAAfAAgJyRfIFQAKAghoDAAAAwA6AGkMAAAEAEMAawwAAAQAPwBqDAAABAA5AGwMAAAEAEsAbQwAAAIAMgDqDAAABAA6AG4MAAABADYAAAA=.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8WAAIZAAYJPCPMFgDOAQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAZAAYJPCPMFgDOAQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAAAA==.Shoepert:BAABLgAECn84AAILAAkJbSU8AwApAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAALAAkJbSU8AwApAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJFgAZADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
St='Stdot:BAABLgAECn8UAAIUAAgJuA+AXgCZAQhoDAAAAwAfAGkMAAADADAAawwAAAMAJABqDAAAAgAYAGwMAAABAC4A6gwAAAQALwBuDAAAAwAzAG8MAAABABMAFAAICbgPgF4AmQEIaAwAAAMAHwBpDAAAAwAwAGsMAAADACQAagwAAAIAGABsDAAAAQAuAOoMAAAEAC8AbgwAAAMAMwBvDAAAAQATAAAA.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgANAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgYJDgAAAA==.',
Te='Tempus:BAACLgAFFH8PAAIJAAQJdBfiGgAwAQRoDAAABQBZAGkMAAAFADkAawwAAAEAAQDqDAAABABbAAkABAl0F+IaADABBGgMAAAFAFkAaQwAAAUAOQBrDAAAAQABAOoMAAAEAFsALgAECn8nAAQJAAgJPx15EwBfAgAJAAgJPx15EwBfAgAGAAEJqRdOQQBGAAAHAAEJ/QozgwEsAAAAAA==.Tenletters:BAAALgAFFAEJAQAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCggJHgAAAA==.Tinkernine:BAAALgADCgEJAQAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgYJDgAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAIJCwAHAEcbAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQEAAgJIxSwGgCHAQhoDAAABwBDAGkMAAAFAEEAawwAAAUANgBqDAAABAAmAGwMAAADAC4AbQwAAAEAKwDqDAAABgA6AG4MAAABABoABAAICSMUsBoAhwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAwAuAG0MAAABACsA6gwAAAUAOgBuDAAAAQAaAAMABQmnDB0bAKkABWgMAAACABIAaQwAAAEAJABrDAAAAQAfAGoMAAABACYA6gwAAAEAKgAFAAEJ5wHQIgEQAAFoDAAAAQAEAAAA.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIeAAcJ+hs2AgBAAgdoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwBuDAAAAQAQAB4ABwn6GzYCAEACB2gMAAAGAGMAaQwAAAUATABrDAAABABFAGoMAAADAEcAbAwAAAEASwDqDAAABwBbAG4MAAABABAALgAECn8uAAMeAAkJuh4bBQD/AgAeAAkJuh4bBQD/AgAkAAQJYQ6ITAC2AAAAAA==.Velladonna:BAAALgAECgYJBgAAAA==.Veronica:BAACLgAFFH8HAAITAAUJxRMcBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEwAFCcUTHAQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/HQADEwAJCVcjQQIAIwMAEwAJCVcjQQIAIwMAFAAGCf0aNX4AhwEAAS4ABRQGCQYAJAAFGQA=.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAQJDwAIAEcOAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgYJEgAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMMAAcJSRzSFgB1AQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAwABgnuHdIWAHUBBmgMAAABAFAAaQwAAAEASABrDAAAAQBPAGoMAAABAEcAbAwAAAEATQDqDAAAAQBJAAsABwllGRwyAG4BB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkAAS4ABAoJCTAAJADwHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
