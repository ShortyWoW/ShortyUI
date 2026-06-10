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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-06-09',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECgUJCAAAAA==.',
Ad='Adaina:BAAALgAECgUJBQAAAA==.Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgkJGgAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8JAAIBAAMJ7w4MWwDeAANoDAAABQAiAGkMAAADADkA6gwAAAEAFgABAAMJ7w4MWwDeAANoDAAABQAiAGkMAAADADkA6gwAAAEAFgAuAAQKfzwAAwEACQkcHoMcAHMCAAEACQkcHoMcAHMCAAIAAwn5CB42AD4AAAAA.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8dAAQDAAcJ7CJ6BwAOAgdoDAAACABhAGkMAAAGAGEAawwAAAUAYgBqDAAAAwBhAGwMAAABAEQAbQwAAAEATQDqDAAABQBhAAMABQktJnoHAA4CBWgMAAAGAGEAaQwAAAUAYQBrDAAABABiAGoMAAACAGEA6gwAAAMAYQAEAAcJjBZcGwCXAQdoDAAAAQAzAGkMAAABAEUAawwAAAEATABqDAAAAQA5AGwMAAABAEQAbQwAAAEATQDqDAAAAQADAAUAAgmDFxDUAH4AAmgMAAABACoA6gwAAAEATQABLgAFFAEJAQAGAAAAAA==.Ailassa:BAAALgAFFAEJAQAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgYJDgAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBeOgABmAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAcABwmoF46AAGYBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMACAABCaMD8VQAHwABawwAAAEACQAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIJAAkJ2xBAJACzAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAJAAkJ2xBAJACzAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn85AAMKAAkJsQv9NgBsAQloDAAACgAFAGkMAAAIACQAawwAAAgAFgBqDAAACABFAGwMAAAHABwAbQwAAAUANQDqDAAACAAhAG4MAAACAA4AbwwAAAEABQAKAAkJsQv9NgBsAQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAUANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAHAAcJbhF2mAA7AQdoDAAABgBFAGkMAAADADkAawwAAAMAJQBqDAAAAQATAGwMAAABABEA6gwAAAMAQwBuDAAAAQATAAAA.Ashes:BAAALgAECgQJCQABLgAECgkJOQAKALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJEQAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.Atlas:BAAALgAECgIJAgAAAA==.',
Au='Auroranova:BAABLgAECn8sAAMHAAkJSA0raACXAQloDAAABwAsAGkMAAAGACUAawwAAAUAEwBqDAAABwA3AGwMAAAGACsAbQwAAAMANQDqDAAABgAYAG4MAAACAAwAbwwAAAIAJQAHAAkJSA0raACXAQloDAAABwAsAGkMAAAFACUAawwAAAUAEwBqDAAABgA3AGwMAAAGACsAbQwAAAMANQDqDAAABgAYAG4MAAACAAwAbwwAAAIAJQAKAAIJZwifegBQAAJpDAAAAQAJAGoMAAABACEAAAA=.',
Ax='Axél:BAAALgAECgUJDAAAAA==.',
Ba='Baddragon:BAAALgAECgYJBgABLgAFFAcJFgAHABkUAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgYJDgAAAA==.Brilleleante:BAAALgADCgkJLwAAAA==.Brochacho:BAAALgAECgcJBwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAcJIAACAAgfAA==.Canimai:BAACLgAFFH8IAAILAAIJEQdhRACBAAJoDAAABAAVAOoMAAAEAA4ACwACCREHYUQAgQACaAwAAAQAFQDqDAAABAAOAC4ABAp/KAADCwAJCYERnS0AlwEACwAJCSQPnS0AlwEADAADCacR4EIAXAAAAAA=.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAFFAEJAQAGAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIFAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAFAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8RAAMNAAQJPww2PwDaAARoDAAABQAVAGkMAAAGABYAawwAAAIADgDqDAAABABDAA0ABAk/DDY/ANoABGgMAAADABUAaQwAAAMAFgBrDAAAAQAOAOoMAAABAEMADgAECYMFvC4AzQAEaAwAAAIAFwBpDAAAAwACAGsMAAABAAgA6gwAAAMAFQAuAAQKfzYAAw4ACQkAE4YhAM8BAA4ACQkAE4YhAM8BAA0AAgnVCLeqAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8ZAAMPAAcJpiB6AAAjAgdoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAABABkAGwMAAABAAsA6gwAAAcAYwBuDAAAAQBjAA8ABglLJnoAACMCBmgMAAAFAGIAaQwAAAMAXwBrDAAABABhAGoMAAAEAGQA6gwAAAcAYwBuDAAAAQBjABAAAQnlEohUAEcAAWwMAAABADAALgAECn8vAAQPAAkJ8yUWAQC4AwAPAAkJ8yUWAQC4AwARAAYJzRiaLQCjAQAQAAMJPw5wfACTAAAAAA==.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgADCgUJBQAAAA==.Deathcrocker:BAECLgAFFH8cAAISAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwASAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAEuAAUUBwkVABEAeCQA.Decksey:BAAALgADCgEJAQABLgADCgYJCQAGAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABwAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBwkWAAcAGRQA.',
Do='Dogs:BAACLgAFFH8PAAILAAUJyiPZDgCCAQVoDAAABABiAGkMAAAEAGIAawwAAAMATQBqDAAAAQBTAOoMAAADAFsACwAFCcoj2Q4AggEFaAwAAAQAYgBpDAAABABiAGsMAAADAE0AagwAAAEAUwDqDAAAAwBbAC4ABAp/GwACCwAICesb1w0A5gIACwAICesb1w0A5gIAAS4ABRQHCRkABwA/HAA=.Domar:BAAALgAECgcJEwAAAA==.Doomslayer:BAABLgAECn8lAAQTAAkJ7BqATwDRAQloDAAACABgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAkJ7BqATwDRAQloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQASAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAFAABCVIKtToAKwABaAwAAAEAGgAAAA==.Doraei:BAABLgAECn8VAAITAAgJmw5QdAB2AQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAEwAICZsOUHQAdgEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMVAAcJthsPCADEAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABUABwm2Gw8IAMQBB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFgABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRczXACyAQloDAAACABRAGkMAAAFAFUAawwAAAUAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAHAAkJSRczXACyAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABgBKAG4MAAAEADEAbwwAAAIAMgAKAAMJIg1rZQCWAANoDAAAAgBQAGkMAAABAAUAawwAAAEADgAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgAGAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elennoxx:BAAALgAECgEJAQAAAA==.Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAUJFwAXABEjAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8rAAILAAkJVRHoIQDfAQloDAAABwA+AGkMAAAGAC0AawwAAAYAPwBqDAAABgAoAGwMAAAFACgAbQwAAAIAJgDqDAAABgAjAG4MAAADACcAbwwAAAIAHQALAAkJVRHoIQDfAQloDAAABwA+AGkMAAAGAC0AawwAAAYAPwBqDAAABgAoAGwMAAAFACgAbQwAAAIAJgDqDAAABgAjAG4MAAADACcAbwwAAAIAHQAAAA==.Felshort:BAAALgAECgEJAQABLgAFFAQJFQAQAOsfAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJCwABLgAECgYJGwAYADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8XAAMZAAgJ4ReFCgDLAQhoDAAABABUAGkMAAADAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABQDqDAAABgBdAG4MAAABAA4AGQAICeEXhQoAywEIaAwAAAMAVABpDAAAAgBhAGsMAAADAEEAagwAAAMAMwBsDAAAAgBDAG0MAAABAAUA6gwAAAYAXQBuDAAAAQAOABoAAgkQFh0EAJAAAmgMAAABAEMAaQwAAAEALQAuAAQKfyUABBkACQl9Il0NAFoDABkACQl9Il0NAFoDABoAAQnTIAcNAFkAABsAAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAITAAgJfx1zRwDoAQhoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAEwAICX8dc0cA6AEIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEALgAECgMJAwABLgAFFAcJFQARAHgkAA==.Getoffenris:BAAALgAFFAMJAwAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQIAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAIARwAIAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAIARwAKAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABwABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8dAAMcAAYJABSJCwBzAQZoDAAABgAwAGkMAAAGADkAawwAAAcAPQBqDAAAAwAgAGwMAAADADQA6gwAAAQAJAAcAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAYAAYJ8BLSKwAxAQZoDAAAAgAqAGkMAAACADEAawwAAAIAPQBqDAAAAQAgAGwMAAACADQA6gwAAAIAJAABLgAECggJHgABAJEbAA==.',
Ha='Haldrian:BAAALgAECgcJEAAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8aAAINAAYJLxW/ZAAjAQZoDAAAAgA7AGkMAAAFACQAawwAAAYAJABqDAAABQBKAGwMAAACADsA6gwAAAYAOgANAAYJLxW/ZAAjAQZoDAAAAgA7AGkMAAAFACQAawwAAAYAJABqDAAABQBKAGwMAAACADsA6gwAAAYAOgAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMdAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdAB0AAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB4AAwlDCrw2AJYAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHQAICTsh0QsAkwIAHQAICTsh0QsAkwIAHgABCYQP73UAMAAAAAA=.Hop:BAACLgAFFH8GAAIfAAMJdBOWDADbAANoDAAAAgArAGkMAAACACgA6gwAAAIAQQAfAAMJdBOWDADbAANoDAAAAgArAGkMAAACACgA6gwAAAIAQQAuAAQKfzgAAh8ACQkPHBUGAIECAB8ACQkPHBUGAIECAAAA.Hota:BAAALgAECgYJBwABLgAFFAQJCQAdAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAdAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAFFAMJAwAAAA==.',
Iv='Ivakor:BAAALgAECgYJEgAAAA==.Ivyy:BAACLgAFFH8PAAIgAAQJHSGZFgBVAQRoDAAABABWAGkMAAAFAFwAawwAAAEAPgDqDAAABQBhACAABAkdIZkWAFUBBGgMAAAEAFYAaQwAAAUAXABrDAAAAQA+AOoMAAAFAGEALgAECn8XAAIgAAgJEiK5DQDAAgAgAAgJEiK5DQDAAgABLgAFFAcJHQAYAD4ZAA==.',
Ja='Jackswagz:BAABLgAECn8pAAMNAAkJHhSEOADEAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABwA3AG4MAAAFACMAbwwAAAIAEwANAAkJHhSEOADEAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABgA3AG4MAAAEACMAbwwAAAIAEwAOAAQJbAfbbQCUAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8yAAIDAAkJUhmhBQBBAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAIAQwDqDAAABwBGAG4MAAAFAEAAbwwAAAIAKAADAAkJUhmhBQBBAgloDAAACAArAGkMAAAHAEcAawwAAAcAVwBqDAAABwA8AGwMAAAFAEgAbQwAAAIAQwDqDAAABwBGAG4MAAAFAEAAbwwAAAIAKAAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAASAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQZAAcJ6iSXMwBGAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABkABwnqJJczAEYCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAGwACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABoAAQkAADwSABcAAWoMAAABAAUAAAA=.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECggJCQAAAA==.',
Kv='Kvasir:BAABLgAECn88AAITAAkJqxyfFwC1AgloDAAACgBUAGkMAAAIAE8AawwAAAgARQBqDAAACABAAGwMAAAIAE8AbQwAAAQAQgDqDAAACQBaAG4MAAADAEsAbwwAAAIAKgATAAkJqxyfFwC1AgloDAAACgBUAGkMAAAIAE8AawwAAAgARQBqDAAACABAAGwMAAAIAE8AbQwAAAQAQgDqDAAACQBaAG4MAAADAEsAbwwAAAIAKgAAAA==.',
Ky='Kynolight:BAAALgAECgQJAwAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8WAAIHAAcJGRQQGgCRAQdoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAGwMAAABABwAbQwAAAEACADqDAAABAAvAAcABwkZFBAaAJEBB2gMAAAGAFQAaQwAAAUASABrDAAABABDAGoMAAABAB4AbAwAAAEAHABtDAAAAQAIAOoMAAAEAC8ALgAECn8gAAIHAAkJYxvaMQBbAgAHAAkJYxvaMQBbAgAAAA==.Lieb:BAAALgAECgUJAwAAAA==.Lihrna:BAAALgAECgIJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.Lushara:BAAALgAECgEJAQAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJDQAJAIsDAA==.Maegii:BAAALgADCgEJAQAAAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMSAAgJKRVaJQAgAQhoDAAABwA+AGkMAAAFAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAEwAHCV8OR48AYgEHaAwAAAYAMABpDAAABAA2AGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgASAAUJjhxaJQAgAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Mingó:BAAALgAECgUJBwAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAIRAAcJeCTgAADVAgdoDAAAAwBaAGkMAAAFAF8AawwAAAMAXQBsDAAAAQBhAG0MAAADAF0A6gwAAAUAYwBuDAAAAQBUABEABwl4JOAAANUCB2gMAAADAFoAaQwAAAUAXwBrDAAAAwBdAGwMAAABAGEAbQwAAAMAXQDqDAAABQBjAG4MAAABAFQALgAECn8VAAIRAAcJ8SXADQC3AgARAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgcJCgAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgQJBwAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Nooxi:BAAALgADCggJCAAAAA==.Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAFFAMJAwABLgAFFAUJEAASAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Nx='Nx:BAAALgAECgEJAQAAAA==.',
Ny='Nylianna:BAACLgAFFH8QAAMHAAQJcBKPXQDmAARoDAAACAA5AGkMAAABAAIAawwAAAEALwDqDAAABgBSAAcAAwlOGI9dAOYAA2gMAAAGADkAawwAAAEALwDqDAAABQBSAAoAAwkxEIYtALwAA2gMAAACACgAaQwAAAEAEQDqDAAAAQBCAC4ABAp/QAADBwAJCRgiaQwAKwMABwAJCRgiaQwAKwMACgAJCSMWihcARQIAAAA=.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Ob='Obscurity:BAAALgAFFAIJAwAAAA==.',
Og='Ogganborn:BAABLgAECn8iAAIBAAYJFR+sSgC6AQZoDAAABwBYAGkMAAAJAE0AawwAAAgAPwBqDAAAAgBeAGwMAAADAE8A6gwAAAUAVwABAAYJFR+sSgC6AQZoDAAABwBYAGkMAAAJAE0AawwAAAgAPwBqDAAAAgBeAGwMAAADAE8A6gwAAAUAVwAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hLRkwBDAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAcABwnaEtGTAEMBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8wAAMRAAkJgh3xCwBwAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAQAQgDqDAAABgBYAG4MAAADAD8AbwwAAAIAPgARAAkJoRzxCwBwAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAQAQgDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAPAAQJORK3aAB5AARqDAAAAQA7AGwMAAABADAAbgwAAAEAHABvDAAAAQA+AAAA.',
Pv='Pvtcrocker:BAEALgAFFAEJAQABLgAFFAcJFQARAHgkAA==.',
Py='Pyrithyr:BAABLgAECn8XAAMIAAgJphibEwCJAQhoDAAAAgA9AGkMAAADAF8AawwAAAMAYABqDAAAAwBhAGwMAAACACIAbQwAAAIAMADqDAAABwBjAG4MAAABAAYACAAFCW8imxMAiQEFaAwAAAEAPQBpDAAAAQBfAGsMAAABAGAAagwAAAEAYQDqDAAABgBjAAcACAn7DxN4AHYBCGgMAAABABoAaQwAAAIANwBrDAAAAgAxAGoMAAACADMAbAwAAAIAIgBtDAAAAgAwAOoMAAABAEEAbgwAAAEABgABLgAFFAEJAQAGAAAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgAECgMJAwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raelyn:BAAALgAECgUJBQABLgAFFAMJCQAhAIgiAA==.Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAABLgAECn8hAAIBAAgJ4AgqcgBUAQhoDAAABgAuAGkMAAAGABMAawwAAAUAEgBqDAAABAAVAGwMAAADAA0AbQwAAAEAGQDqDAAABwAcAG4MAAABAAYAAQAICeAIKnIAVAEIaAwAAAYALgBpDAAABgATAGsMAAAFABIAagwAAAQAFQBsDAAAAwANAG0MAAABABkA6gwAAAcAHABuDAAAAQAGAAAA.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn84AAUhAAkJQiGTBQBZAwloDAAACQBcAGkMAAAJAFcAawwAAAcAXgBqDAAABwBgAGwMAAAIAGMAbQwAAAMAVwDqDAAACQBgAG4MAAADAEAAbwwAAAEALwAhAAkJQiGTBQBZAwloDAAACABcAGkMAAAHAFcAawwAAAUAXgBqDAAABwBgAGwMAAAIAGMAbQwAAAMAVwDqDAAACQBgAG4MAAADAEAAbwwAAAEALwAfAAMJVxXhNAB6AANoDAAAAQAtAGkMAAABAD0AawwAAAEAOAAiAAEJhhtdWgBPAAFrDAAAAQBGACAAAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIMAAgJNhkRAQD/AQhoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAG8MAAABAD0ADAAICTYZEQEA/wEIaAwAAAIATgBpDAAAAgBeAGsMAAACAC8AagwAAAEAHwBtDAAAAQAsAOoMAAAEAE0AbgwAAAEAMABvDAAAAQA9AC4ABAp/HAACDAAICZsltQEAaAMADAAICZsltQEAaAMAAAA=.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIZAAYJNA7EwAAFAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAZAAYJNA7EwAAFAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAUALQAAAA==.',
Sa='Saelki:BAAALgAECgMJAwAAAA==.',
Se='Sephiran:BAABLgAECn8wAAMjAAkJ8B2lDQB2AgloDAAABwBYAGkMAAAHAFAAawwAAAcARwBqDAAABgBTAGwMAAAGAEoAbQwAAAQAOQDqDAAABwBYAG4MAAADAEsAbwwAAAEATAAjAAkJ8B2lDQB2AgloDAAABABYAGkMAAADAFAAawwAAAMARwBqDAAAAgBTAGwMAAACAEoAbQwAAAIAOQDqDAAAAwBYAG4MAAACAEsAbwwAAAEATAAeAAgJyRfbFwAMAghoDAAAAwA6AGkMAAAEAEMAawwAAAQAPwBqDAAABAA5AGwMAAAEAEsAbQwAAAIAMgDqDAAABAA6AG4MAAABADYAAAA=.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8bAAIYAAYJPCM8FgDiAQZoDAAABABhAGkMAAAHAFQAawwAAAUAXQBqDAAAAgBeAGwMAAADAFcA6gwAAAYAVwAYAAYJPCM8FgDiAQZoDAAABABhAGkMAAAHAFQAawwAAAUAXQBqDAAAAgBeAGwMAAADAFcA6gwAAAYAVwAAAA==.Shoepert:BAABLgAECn84AAILAAkJbSUlBAAiAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAALAAkJbSUlBAAiAwloDAAACgBhAGkMAAAIAGMAawwAAAgAYABqDAAACABhAGwMAAAHAF0AbQwAAAUAYADqDAAABwBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sib:BAAALgAFFAMJAwAAAA==.Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJGwAYADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
St='Stdot:BAABLgAECn8WAAITAAkJaRCBSQDhAQloDAAAAwAfAGkMAAADADAAawwAAAMAJABqDAAAAgAYAGwMAAABAC4AbQwAAAEAJgDqDAAABAAvAG4MAAADADMAbwwAAAIAIwATAAkJaRCBSQDhAQloDAAAAwAfAGkMAAADADAAawwAAAMAJABqDAAAAgAYAGwMAAABAC4AbQwAAAEAJgDqDAAABAAvAG4MAAADADMAbwwAAAIAIwAAAA==.Stormstrike:BAAALgADCgkJDwAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAGAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgcJDwAAAA==.',
Te='Tempus:BAACLgAFFH8RAAIKAAQJoh2OGQBMAQRoDAAABQBZAGkMAAAGADkAawwAAAIAQADqDAAABABbAAoABAmiHY4ZAEwBBGgMAAAFAFkAaQwAAAYAOQBrDAAAAgBAAOoMAAAEAFsALgAECn8pAAQKAAkJxBzXEgB0AgAKAAgJOx7XEgB0AgAIAAIJ3RQYNgB/AAAHAAEJ/QojnwEqAAAAAA==.Tenletters:BAAALgAFFAEJAgAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgkJJgAAAA==.Tinkernine:BAAALgADCgEJAQAAAA==.',
To='Tobofrog:BAABLgAFFH8FAAIgAAUJ3g7XIwD6AAVoDAAAAQA4AGkMAAABACsAawwAAAEAIABqDAAAAQADAOoMAAABABIAIAAFCd4O1yMA+gAFaAwAAAEAOABpDAAAAQArAGsMAAABACAAagwAAAEAAwDqDAAAAQASAAAA.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgcJDwAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAQJEAAHAHASAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQEAAgJIxSKHQCDAQhoDAAABwBDAGkMAAAFAEEAawwAAAUANgBqDAAABAAmAGwMAAADAC4AbQwAAAEAKwDqDAAABgA6AG4MAAABABoABAAICSMUih0AgwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAwAuAG0MAAABACsA6gwAAAUAOgBuDAAAAQAaAAMABQmnDBMdAKkABWgMAAACABIAaQwAAAEAJABrDAAAAQAfAGoMAAABACYA6gwAAAEAKgAFAAEJ5wFRMgEXAAFoDAAAAQAEAAAA.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIdAAcJ+ht+AwAvAgdoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwBuDAAAAQAQAB0ABwn6G34DAC8CB2gMAAAGAGMAaQwAAAUATABrDAAABABFAGoMAAADAEcAbAwAAAEASwDqDAAABwBbAG4MAAABABAALgAECn8uAAMdAAkJuh4bBQD/AgAdAAkJuh4bBQD/AgAjAAQJYQ7hVQCzAAAAAA==.Velladonna:BAAALgAECgYJBgAAAA==.Veronica:BAACLgAFFH8TAAMSAAYJWCC0DQCLAQZoDAAAAgBcAGkMAAADAGEAawwAAAMAYABqDAAABABeAGwMAAADACUA6gwAAAQAWQATAAUJmROgLQCbAQVoDAAAAQBcAGkMAAABAEkAawwAAAEAKQBsDAAAAgAZAOoMAAABABAAEgAGCSoftA0AiwEGaAwAAAEATQBpDAAAAgBhAGsMAAACAGAAagwAAAQAXgBsDAAAAQAlAOoMAAADAFkALgAECn8dAAMSAAkJVyO0AgAcAwASAAkJVyO0AgAcAwATAAYJ/Ro1fgCHAQABLgAFFAgJDgAjABAbAA==.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAUJFAAJABETAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgYJEgAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMMAAcJSRzjGABuAQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAwABgnuHeMYAG4BBmgMAAABAFAAaQwAAAEASABrDAAAAQBPAGoMAAABAEcAbAwAAAEATQDqDAAAAQBJAAsABwllGeE1AG0BB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkAAS4ABAoJCTAAIwDwHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
