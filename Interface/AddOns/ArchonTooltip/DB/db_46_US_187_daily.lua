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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Hunter-Survival','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-06-07',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECgUJCAAAAA==.',
Ad='Adaina:BAAALgAECgUJBQAAAA==.Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgkJGgAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8JAAIBAAMJ7w60WADeAANoDAAABQAiAGkMAAADADkA6gwAAAEAFgABAAMJ7w60WADeAANoDAAABQAiAGkMAAADADkA6gwAAAEAFgAuAAQKfzwAAwEACQkcHt8bAHQCAAEACQkcHt8bAHQCAAIAAwn5CHo1AD4AAAAA.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8dAAQDAAcJ7CJ6BwAOAgdoDAAACABhAGkMAAAGAGEAawwAAAUAYgBqDAAAAwBhAGwMAAABAEQAbQwAAAEATQDqDAAABQBhAAMABQktJnoHAA4CBWgMAAAGAGEAaQwAAAUAYQBrDAAABABiAGoMAAACAGEA6gwAAAMAYQAEAAcJjBb0GgCYAQdoDAAAAQAzAGkMAAABAEUAawwAAAEATABqDAAAAQA5AGwMAAABAEQAbQwAAAEATQDqDAAAAQADAAUAAgmDF03SAH4AAmgMAAABACoA6gwAAAEATQABLgAFFAEJAQAGAAAAAA==.Ailassa:BAAALgAFFAEJAQAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgYJDgAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBcSfwBmAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAcABwmoFxJ/AGYBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMACAABCaMDIFQAHwABawwAAAEACQAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIJAAkJ2xDAIwC1AQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAJAAkJ2xDAIwC1AQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn85AAMKAAkJsQuRNgBsAQloDAAACgAFAGkMAAAIACQAawwAAAgAFgBqDAAACABFAGwMAAAHABwAbQwAAAUANQDqDAAACAAhAG4MAAACAA4AbwwAAAEABQAKAAkJsQuRNgBsAQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAUANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAHAAcJbhHklgA7AQdoDAAABgBFAGkMAAADADkAawwAAAMAJQBqDAAAAQATAGwMAAABABEA6gwAAAMAQwBuDAAAAQATAAAA.Ashes:BAAALgAECgQJCQABLgAECgkJOQAKALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJEAAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.Atlas:BAAALgAECgIJAgAAAA==.',
Au='Auroranova:BAABLgAECn8sAAMHAAkJSA0TZwCXAQloDAAABwAsAGkMAAAGACUAawwAAAUAEwBqDAAABwA3AGwMAAAGACsAbQwAAAMANQDqDAAABgAYAG4MAAACAAwAbwwAAAIAJQAHAAkJSA0TZwCXAQloDAAABwAsAGkMAAAFACUAawwAAAUAEwBqDAAABgA3AGwMAAAGACsAbQwAAAMANQDqDAAABgAYAG4MAAACAAwAbwwAAAIAJQAKAAIJZwjMeQBQAAJpDAAAAQAJAGoMAAABACEAAAA=.',
Ax='Axél:BAAALgAECgUJCQAAAA==.',
Ba='Baddragon:BAAALgAECgYJBgABLgAFFAYJFQAHAHgXAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgYJDgAAAA==.Brilleleante:BAAALgADCgkJLAAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAcJIAALAAgfAA==.Canimai:BAACLgAFFH8IAAIMAAIJEQc7QwCBAAJoDAAABAAVAOoMAAAEAA4ADAACCREHO0MAgQACaAwAAAQAFQDqDAAABAAOAC4ABAp/KAADDAAJCYERJS0AlwEADAAJCSQPJS0AlwEADQADCacROUIAXAAAAAA=.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAFFAEJAQAGAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIFAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAFAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8RAAMOAAQJPwzqPQDaAARoDAAABQAVAGkMAAAGABYAawwAAAIADgDqDAAABABDAA4ABAk/DOo9ANoABGgMAAADABUAaQwAAAMAFgBrDAAAAQAOAOoMAAABAEMADwAECYMFsC0AzwAEaAwAAAIAFwBpDAAAAwACAGsMAAABAAgA6gwAAAMAFQAuAAQKfzUAAw8ACQkAE0QhAM0BAA8ACQkAE0QhAM0BAA4AAgnVCLeoAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8ZAAMQAAcJpiB6AAAjAgdoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAABABkAGwMAAABAAsA6gwAAAcAYwBuDAAAAQBjABAABglLJnoAACMCBmgMAAAFAGIAaQwAAAMAXwBrDAAABABhAGoMAAAEAGQA6gwAAAcAYwBuDAAAAQBjABEAAQnlEjxSAEcAAWwMAAABADAALgAECn8vAAQQAAkJ8yUWAQC4AwAQAAkJ8yUWAQC4AwASAAYJzRiaLQCjAQARAAMJPw4yegCTAAAAAA==.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgADCgUJBQAAAA==.Deathcrocker:BAECLgAFFH8cAAITAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwATAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwAuAAQKfxoAAhMACQkDJmwAAMsDABMACQkDJmwAAMsDAAEuAAUUBwkVABIAeCQA.Decksey:BAAALgADCgEJAQABLgADCgYJCQAGAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABwAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBgkVAAcAeBcA.',
Do='Dogs:BAACLgAFFH8PAAIMAAUJyiMsDgCDAQVoDAAABABiAGkMAAAEAGIAawwAAAMATQBqDAAAAQBTAOoMAAADAFsADAAFCcojLA4AgwEFaAwAAAQAYgBpDAAABABiAGsMAAADAE0AagwAAAEAUwDqDAAAAwBbAC4ABAp/GwACDAAICesb1w0A5gIADAAICesb1w0A5gIAAS4ABRQHCRkABwA/HAA=.Domar:BAAALgAECgcJEwAAAA==.Doomslayer:BAABLgAECn8lAAQUAAkJ7Bq0TgDRAQloDAAACABgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQAUAAkJ7Bq0TgDRAQloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAFQABCVIKnjkAKwABaAwAAAEAGgAAAA==.Doraei:BAABLgAECn8VAAIUAAgJmw4zcwB2AQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAFAAICZsOM3MAdgEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMWAAcJthvlBwDEAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABYABwm2G+UHAMQBB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFwABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRcJWwCyAQloDAAACABRAGkMAAAFAFUAawwAAAUAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAHAAkJSRcJWwCyAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAKAAMJIg2kZACWAANoDAAAAgBQAGkMAAABAAUAawwAAAEADgAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgAGAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elennoxx:BAAALgAECgEJAQAAAA==.Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAUJFwAYABEjAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8rAAIMAAkJVRGFIQDfAQloDAAABwA+AGkMAAAGAC0AawwAAAYAPwBqDAAABgAoAGwMAAAFACgAbQwAAAIAJgDqDAAABgAjAG4MAAADACcAbwwAAAIAHQAMAAkJVRGFIQDfAQloDAAABwA+AGkMAAAGAC0AawwAAAYAPwBqDAAABgAoAGwMAAAFACgAbQwAAAIAJgDqDAAABgAjAG4MAAADACcAbwwAAAIAHQAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJCwABLgAECgYJGwAZADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8XAAMaAAgJ4ReFCgDLAQhoDAAABABUAGkMAAADAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABQDqDAAABgBdAG4MAAABAA4AGgAICeEXhQoAywEIaAwAAAMAVABpDAAAAgBhAGsMAAADAEEAagwAAAMAMwBsDAAAAgBDAG0MAAABAAUA6gwAAAYAXQBuDAAAAQAOABsAAgkQFu4DAJAAAmgMAAABAEMAaQwAAAEALQAuAAQKfyUABBoACQl9Il0NAFoDABoACQl9Il0NAFoDABsAAQnTIAcNAFkAABwAAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAIUAAgJfx2mRgDoAQhoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAFAAICX8dpkYA6AEIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEALgAECgMJAwABLgAFFAcJFQASAHgkAA==.Getoffenris:BAAALgAFFAMJAwAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQIAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAIARwAIAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAIARwAKAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABwABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8dAAMdAAYJABSJCwBzAQZoDAAABgAwAGkMAAAGADkAawwAAAcAPQBqDAAAAwAgAGwMAAADADQA6gwAAAQAJAAdAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAZAAYJ8BJbKwAxAQZoDAAAAgAqAGkMAAACADEAawwAAAIAPQBqDAAAAQAgAGwMAAACADQA6gwAAAIAJAABLgAECggJHgABAJEbAA==.',
Ha='Haldrian:BAAALgAECgcJEAAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8WAAIOAAYJ7RSKZAAgAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAYAOgAOAAYJ7RSKZAAgAQZoDAAAAgA7AGkMAAAEACAAawwAAAUAJABqDAAABABKAGwMAAABADsA6gwAAAYAOgAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMeAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdAB4AAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB8AAwlDCq01AJYAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHgAICTsh0QsAkwIAHgAICTsh0QsAkwIAHwABCYQPUHQAMAAAAAA=.Hop:BAACLgAFFH8GAAIgAAMJdBMrDADhAANoDAAAAgArAGkMAAACACgA6gwAAAIAQQAgAAMJdBMrDADhAANoDAAAAgArAGkMAAACACgA6gwAAAIAQQAuAAQKfzgAAiAACQkPHPUFAIECACAACQkPHPUFAIECAAAA.Hota:BAAALgAECgYJBwABLgAFFAQJCQAeAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAeAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAECgUJEAAAAA==.',
Iv='Ivakor:BAAALgAECgYJDgAAAA==.Ivyy:BAACLgAFFH8PAAIhAAQJHSG/FQBYAQRoDAAABABWAGkMAAAFAFwAawwAAAEAPgDqDAAABQBhACEABAkdIb8VAFgBBGgMAAAEAFYAaQwAAAUAXABrDAAAAQA+AOoMAAAFAGEALgAECn8XAAIhAAgJEiK5DQDAAgAhAAgJEiK5DQDAAgABLgAFFAcJHQAZAD4ZAA==.',
Ja='Jackswagz:BAABLgAECn8pAAMOAAkJHhTGNwDEAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABwA3AG4MAAAFACMAbwwAAAIAEwAOAAkJHhTGNwDEAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABgA3AG4MAAAEACMAbwwAAAIAEwAPAAQJbAeRbACUAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8yAAIDAAkJUhmGBQBBAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAIAQwDqDAAABwBGAG4MAAAFAEAAbwwAAAIAKAADAAkJUhmGBQBBAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAIAQwDqDAAABwBGAG4MAAAFAEAAbwwAAAIAKAAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAATAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQaAAcJ6iTrMgBHAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABoABwnqJOsyAEcCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAHAACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABsAAQkAADwSABcAAWoMAAABAAUAAAA=.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECggJCQAAAA==.',
Kv='Kvasir:BAABLgAECn88AAIUAAkJqxwqFwC1AgloDAAACgBUAGkMAAAIAE8AawwAAAgARQBqDAAACABAAGwMAAAIAE8AbQwAAAQAQgDqDAAACQBaAG4MAAADAEsAbwwAAAIAKgAUAAkJqxwqFwC1AgloDAAACgBUAGkMAAAIAE8AawwAAAgARQBqDAAACABAAGwMAAAIAE8AbQwAAAQAQgDqDAAACQBaAG4MAAADAEsAbwwAAAIAKgAAAA==.',
Ky='Kynolight:BAAALgAECgQJAwAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8VAAIHAAYJeBc4CgBbAQZoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAGwMAAABABwA6gwAAAQALwAHAAYJeBc4CgBbAQZoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAGwMAAABABwA6gwAAAQALwAuAAQKfyAAAgcACQljG9oxAFsCAAcACQljG9oxAFsCAAAA.Lieb:BAAALgAECgMJAwAAAA==.Lihrna:BAAALgAECgIJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.Lushara:BAAALgAECgEJAQAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJDQAJAIsDAA==.Maegii:BAAALgADCgEJAQAAAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMTAAgJKRX1JAAgAQhoDAAABwA+AGkMAAAFAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAFAAHCV8OR48AYgEHaAwAAAYAMABpDAAABAA2AGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgATAAUJjhz1JAAgAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Mingó:BAAALgAECgUJBwAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAISAAcJeCTAAADXAgdoDAAAAwBaAGkMAAAFAF8AawwAAAMAXQBsDAAAAQBhAG0MAAADAF0A6gwAAAUAYwBuDAAAAQBUABIABwl4JMAAANcCB2gMAAADAFoAaQwAAAUAXwBrDAAAAwBdAGwMAAABAGEAbQwAAAMAXQDqDAAABQBjAG4MAAABAFQALgAECn8VAAISAAcJ8SXADQC3AgASAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgcJCgAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgQJBwAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Nooxi:BAAALgADCggJCAAAAA==.Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAFFAMJAwABLgAFFAUJEAATAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Nx='Nx:BAAALgAECgEJAQAAAA==.',
Ny='Nylianna:BAACLgAFFH8PAAMKAAMJMRDJLAC+AANoDAAACAAoAGkMAAABABEA6gwAAAYAQgAKAAMJMRDJLAC+AANoDAAAAgAoAGkMAAABABEA6gwAAAEAQgAHAAIJRxvFfQCdAAJoDAAABgA5AOoMAAAFAFIALgAECn9AAAMHAAkJGCKcDwDgAgAHAAkJGCKcDwDgAgAKAAkJIxZBFwBFAgAAAA==.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Ob='Obscurity:BAAALgAFFAIJAwAAAA==.',
Og='Ogganborn:BAABLgAECn8iAAIBAAYJFR9qSQC7AQZoDAAABwBYAGkMAAAJAE0AawwAAAgAPwBqDAAAAgBeAGwMAAADAE8A6gwAAAUAVwABAAYJFR9qSQC7AQZoDAAABwBYAGkMAAAJAE0AawwAAAgAPwBqDAAAAgBeAGwMAAADAE8A6gwAAAUAVwAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hJVkgBDAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAcABwnaElWSAEMBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8wAAMSAAkJgh3LCwBxAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAQAQgDqDAAABgBYAG4MAAADAD8AbwwAAAIAPgASAAkJoRzLCwBxAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAQAAQJORKCZwB5AARqDAAAAQA7AGwMAAABADAAbgwAAAEAHABvDAAAAQA+AAAA.',
Pv='Pvtcrocker:BAEALgAFFAEJAQABLgAFFAcJFQASAHgkAA==.',
Py='Pyrithyr:BAABLgAECn8XAAMIAAgJphhgEwCJAQhoDAAAAgA9AGkMAAADAF8AawwAAAMAYABqDAAAAwBhAGwMAAACACIAbQwAAAIAMADqDAAABwBjAG4MAAABAAYACAAFCW8iYBMAiQEFaAwAAAEAPQBpDAAAAQBfAGsMAAABAGAAagwAAAEAYQDqDAAABgBjAAcACAn7D752AHYBCGgMAAABABoAaQwAAAIANwBrDAAAAgAxAGoMAAACADMAbAwAAAIAIgBtDAAAAgAwAOoMAAABAEEAbgwAAAEABgABLgAFFAEJAQAGAAAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgAECgMJAwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raelyn:BAAALgAECgUJBQABLgAFFAMJCQAiAIgiAA==.Raevaela:BAAALgADCgQJBwABLgAECgcJFQAQABkcAA==.Railiana:BAABLgAECn8hAAIBAAgJ3wjYcABUAQhoDAAABgAuAGkMAAAGABMAawwAAAUAEgBqDAAABAAVAGwMAAADAA0AbQwAAAEAGQDqDAAABwAcAG4MAAABAAYAAQAICd8I2HAAVAEIaAwAAAYALgBpDAAABgATAGsMAAAFABIAagwAAAQAFQBsDAAAAwANAG0MAAABABkA6gwAAAcAHABuDAAAAQAGAAAA.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn84AAUiAAkJQiF0BQBaAwloDAAACQBcAGkMAAAJAFcAawwAAAcAXgBqDAAABwBgAGwMAAAIAGMAbQwAAAMAVwDqDAAACQBgAG4MAAADAEAAbwwAAAEALwAiAAkJQiF0BQBaAwloDAAACABcAGkMAAAHAFcAawwAAAUAXgBqDAAABwBgAGwMAAAIAGMAbQwAAAMAVwDqDAAACQBgAG4MAAADAEAAbwwAAAEALwAgAAMJVxUeNAB6AANoDAAAAQAtAGkMAAABAD0AawwAAAEAOAAjAAEJhhvcWABPAAFrDAAAAQBGACEAAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAQAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAINAAgJNhkRAQD/AQhoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAG8MAAABAD0ADQAICTYZEQEA/wEIaAwAAAIATgBpDAAAAgBeAGsMAAACAC8AagwAAAEAHwBtDAAAAQAsAOoMAAAEAE0AbgwAAAEAMABvDAAAAQA9AC4ABAp/HAACDQAICZsltQEAaAMADQAICZsltQEAaAMAAAA=.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIaAAYJNA6PvgAIAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAaAAYJNA6PvgAIAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAAAA==.',
Sa='Saelki:BAAALgAECgMJAwAAAA==.',
Se='Sephiran:BAABLgAECn8wAAMkAAkJ8B1zDQB3AgloDAAABwBYAGkMAAAHAFAAawwAAAcARwBqDAAABgBTAGwMAAAGAEoAbQwAAAQAOQDqDAAABwBYAG4MAAADAEsAbwwAAAEATAAkAAkJ8B1zDQB3AgloDAAABABYAGkMAAADAFAAawwAAAMARwBqDAAAAgBTAGwMAAACAEoAbQwAAAIAOQDqDAAAAwBYAG4MAAACAEsAbwwAAAEATAAfAAgJyRedFwAMAghoDAAAAwA6AGkMAAAEAEMAawwAAAQAPwBqDAAABAA5AGwMAAAEAEsAbQwAAAIAMgDqDAAABAA6AG4MAAABADYAAAA=.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8bAAIZAAYJPCP0FQDiAQZoDAAABABhAGkMAAAHAFQAawwAAAUAXQBqDAAAAgBeAGwMAAADAFcA6gwAAAYAVwAZAAYJPCP0FQDiAQZoDAAABABhAGkMAAAHAFQAawwAAAUAXQBqDAAAAgBeAGwMAAADAFcA6gwAAAYAVwAAAA==.Shoepert:BAABLgAECn84AAIMAAkJbSX9AwAjAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAAMAAkJbSX9AwAjAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sib:BAAALgAFFAMJAwAAAA==.Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJGwAZADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
St='Stdot:BAABLgAECn8WAAIUAAkJaRDASADhAQloDAAAAwAfAGkMAAADADAAawwAAAMAJABqDAAAAgAYAGwMAAABAC4AbQwAAAEAJgDqDAAABAAvAG4MAAADADMAbwwAAAIAIwAUAAkJaRDASADhAQloDAAAAwAfAGkMAAADADAAawwAAAMAJABqDAAAAgAYAGwMAAABAC4AbQwAAAEAJgDqDAAABAAvAG4MAAADADMAbwwAAAIAIwAAAA==.Stormstrike:BAAALgADCgYJBgAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAGAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgcJDwAAAA==.',
Te='Tempus:BAACLgAFFH8RAAIKAAQJoh3oGABPAQRoDAAABQBZAGkMAAAGADkAawwAAAIAQADqDAAABABbAAoABAmiHegYAE8BBGgMAAAFAFkAaQwAAAYAOQBrDAAAAgBAAOoMAAAEAFsALgAECn8pAAQKAAkJxByTEgB1AgAKAAgJOx6TEgB1AgAIAAIJ3RSBNQB/AAAHAAEJ/QoPmwEqAAAAAA==.Tenletters:BAAALgAFFAEJAgAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgkJJgAAAA==.Tinkernine:BAAALgADCgEJAQAAAA==.',
To='Tobofrog:BAABLgAFFH8FAAIhAAUJ3g4gIwD8AAVoDAAAAQA4AGkMAAABACsAawwAAAEAIABqDAAAAQADAOoMAAABABIAIQAFCd4OICMA/AAFaAwAAAEAOABpDAAAAQArAGsMAAABACAAagwAAAEAAwDqDAAAAQASAAAA.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgcJDwAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAMJDwAKADEQAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQEAAgJIxQeHQCDAQhoDAAABwBDAGkMAAAFAEEAawwAAAUANgBqDAAABAAmAGwMAAADAC4AbQwAAAEAKwDqDAAABgA6AG4MAAABABoABAAICSMUHh0AgwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAwAuAG0MAAABACsA6gwAAAUAOgBuDAAAAQAaAAMABQmnDLIcAKkABWgMAAACABIAaQwAAAEAJABrDAAAAQAfAGoMAAABACYA6gwAAAEAKgAFAAEJ5wEYLwEXAAFoDAAAAQAEAAAA.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIeAAcJ+hs9AwAwAgdoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwBuDAAAAQAQAB4ABwn6Gz0DADACB2gMAAAGAGMAaQwAAAUATABrDAAABABFAGoMAAADAEcAbAwAAAEASwDqDAAABwBbAG4MAAABABAALgAECn8uAAMeAAkJuh4bBQD/AgAeAAkJuh4bBQD/AgAkAAQJYQ42VQCzAAAAAA==.Velladonna:BAAALgAECgYJBgAAAA==.Veronica:BAACLgAFFH8TAAMTAAYJWCBKDQCNAQZoDAAAAgBcAGkMAAADAGEAawwAAAMAYABqDAAABABeAGwMAAADACUA6gwAAAQAWQAUAAUJmRObKwCdAQVoDAAAAQBcAGkMAAABAEkAawwAAAEAKQBsDAAAAgAZAOoMAAABABAAEwAGCSofSg0AjQEGaAwAAAEATQBpDAAAAgBhAGsMAAACAGAAagwAAAQAXgBsDAAAAQAlAOoMAAADAFkALgAECn8dAAMTAAkJVyOlAgAdAwATAAkJVyOlAgAdAwAUAAYJ/Ro1fgCHAQABLgAFFAgJDgAkABAbAA==.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQAAAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgYJEgAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMNAAcJSRyLGABvAQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAA0ABgnuHYsYAG8BBmgMAAABAFAAaQwAAAEASABrDAAAAQBPAGoMAAABAEcAbAwAAAEATQDqDAAAAQBJAAwABwllGUQ1AG0BB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkAAS4ABAoJCTAAJADwHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
