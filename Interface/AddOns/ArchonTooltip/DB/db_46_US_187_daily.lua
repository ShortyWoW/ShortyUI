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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-14',data={Aa='Aandheeog:BAAALgAECggJDwAAAA==.',
Ab='Absqwas:BAAALgAECgEJAQAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgUJCAAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8yAAMBAAkJFB6/DACbAgloDAAABQBVAGkMAAAFAEsAawwAAAgAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAABAAkJFB6/DACbAgloDAAABABVAGkMAAAFAEsAawwAAAcAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAACAAIJsAK2gQBAAAJoDAAAAQAEAGsMAAABAAkAAAA=.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8SAAQDAAUJwCV6BwAOAgVoDAAABgBhAGkMAAAEAGAAawwAAAMAXwBqDAAAAQBhAOoMAAAEAGEAAwAFCcAlegcADgIFaAwAAAUAYQBpDAAABABgAGsMAAADAF8AagwAAAEAYQDqDAAAAgBhAAQAAgmDF0GaAIUAAmgMAAABACoA6gwAAAEATQAFAAEJXgEpVQAUAAHqDAAAAQADAAAA.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgUJCAAAAA==.Aneesa:BAABLgAECn8eAAMGAAcJqBcbSQCMAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAYABwmoFxtJAIwBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMABwABCaMDND0AIQABawwAAAEACQAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIIAAkJ2xCWFQDDAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAIAAkJ2xCWFQDDAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn8yAAMJAAkJsguWJQB/AQloDAAACQAFAGkMAAAHACQAawwAAAcAFgBqDAAABwBFAGwMAAAGABwAbQwAAAQANQDqDAAABwAhAG4MAAACAA4AbwwAAAEABQAJAAkJsguWJQB/AQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAQANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAGAAUJlBPakADwAAVoDAAABQBFAGkMAAACADkAawwAAAIAJQDqDAAAAgBDAG4MAAABABMAAAA=.Ashes:BAAALgAECgQJCQABLgAECgkJMgAJALILAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJBwAAAA==.',
Au='Auroranova:BAABLgAECn8jAAMGAAgJIQumXwBRAQhoDAAABgAkAGkMAAAGACUAawwAAAUAEwBqDAAABgAgAGwMAAAFACsAbQwAAAEAIQDqDAAABQAYAG4MAAABAAUABgAICSELpl8AUQEIaAwAAAYAJABpDAAABQAlAGsMAAAFABMAagwAAAUAIABsDAAABQArAG0MAAABACEA6gwAAAUAGABuDAAAAQAFAAkAAglnCM9fAFIAAmkMAAABAAkAagwAAAEAIQAAAA==.',
Ax='Axél:BAAALgAECgUJCAAAAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCAAAAA==.',
Br='Braei:BAAALgAECgUJCAAAAA==.Brilleleante:BAAALgADCgYJEwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAYJEQACAGQhAA==.Canimai:BAABLgAECn8mAAMKAAgJHhEzJgBjAQhoDAAABgA0AGkMAAAGADAAawwAAAYALwBqDAAABAAzAGwMAAAEAC0AbQwAAAMAIQDqDAAABgAjAG4MAAADACwACgAICWsOMyYAYwEIaAwAAAYANABpDAAABgAwAGsMAAAGAC8AagwAAAMAGwBsDAAAAgAXAG0MAAADACEA6gwAAAYAIwBuDAAAAgASAAsAAwmnEVowAGYAA2oMAAABADMAbAwAAAIALQBuDAAAAQAsAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJDgAMAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8KAAMNAAMJQQ3uLwC4AANoDAAABAALAGkMAAAEABYA6gwAAAIAQwANAAMJQQ3uLwC4AANoDAAAAgALAGkMAAACABYA6gwAAAEAQwAOAAMJNgRsIwCvAANoDAAAAgAXAGkMAAACAAIA6gwAAAEABgAuAAQKfykAAw4ACAnwEMohAGoBAA4ACAnwEMohAGoBAA0AAQkkB+yQADQAAAAA.',
Cu='Cubes:BAACLgAFFH8XAAMPAAYJcR96AAAjAgZoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAGwMAAABAAsA6gwAAAcAYwAPAAUJMiZ6AAAjAgVoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAOoMAAAHAGMAEAABCeUSHCwATQABbAwAAAEAMAAuAAQKfy0ABA8ACQm1JRYBALgDAA8ACQm1JRYBALgDABEABgnNGJotAKMBABAAAwk/DtlHAJUAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deathcrocker:BAECLgAFFH8cAAISAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwASAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABwBhAGwMAAADAF8A6gwAAAYAYwAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAEuAAUUBwkSABEAAiMA.Decksey:BAAALgADCgEJAQABLgADCgYJCQAMAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIGAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABgAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBQkTAAYA3hgA.',
Do='Dogs:BAACLgAFFH8LAAIKAAQJxBp0DwBAAQRoDAAAAwBKAGkMAAADAFMAawwAAAIAGADqDAAAAwBbAAoABAnEGnQPAEABBGgMAAADAEoAaQwAAAMAUwBrDAAAAgAYAOoMAAADAFsALgAECn8bAAIKAAgJ6xvXDQDmAgAKAAgJ6xvXDQDmAgABLgAFFAcJFQAGAOcbAA==.Domar:BAAALgAECgUJDAAAAA==.Doomslayer:BAABLgAECn8lAAQTAAkJ7BqgKwD3AQloDAAACABgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAkJ7BqgKwD3AQloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQASAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAFAABCVIKRyAALAABaAwAAAEAGgAAAA==.Doraei:BAABLgAECn8VAAITAAgJmg4RSACJAQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAEwAICZoOEUgAiQEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMVAAcJtht4BADgAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABUABwm2G3gEAOABB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFgABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8hAAMGAAkJSRe/MQDcAQloDAAABwBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAGAAkJSRe/MQDcAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAJAAEJYB91XQBYAAFoDAAAAQBQAAAA.',
Ea='Easy:BAAALgAECgIJBQABLgAECgYJBgAMAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJEAAXADEbAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8aAAIKAAgJDhAIHQCkAQhoDAAABQA+AGkMAAAEACcAawwAAAQAPQBqDAAABAAoAGwMAAADACgAbQwAAAEAEQDqDAAABAAaAG4MAAABACcACgAICQ4QCB0ApAEIaAwAAAUAPgBpDAAABAAnAGsMAAAEAD0AagwAAAQAKABsDAAAAwAoAG0MAAABABEA6gwAAAQAGgBuDAAAAQAnAAAA.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8UAAIYAAcJ5xqFCgDLAQdoDAAAAwBUAGkMAAACAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABADqDAAABgBdABgABwnnGoUKAMsBB2gMAAADAFQAaQwAAAIAYQBrDAAAAwBBAGoMAAADADMAbAwAAAIAQwBtDAAAAQAEAOoMAAAGAF0ALgAECn8hAAQYAAkJfSJdDQBaAwAYAAkJfSJdDQBaAwAZAAEJ0yAHDQBZAAAaAAEJGw8dGgBHAAAAAA==.Froslass:BAABLgAECn8ZAAITAAgJfh0EKAAIAghoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAEwAICX4dBCgACAIIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgUJCgAAAA==.',
Gl='Gloryhammer:BAABLgAECn8kAAQHAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAEARwAHAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAEARwAJAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABgABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8YAAMbAAYJIBKJCwBzAQZoDAAABQAwAGkMAAAFADkAawwAAAYAOQBqDAAAAwAgAGwMAAACACAA6gwAAAMAJAAbAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAcAAYJEBEsHwAkAQZoDAAAAQAqAGkMAAABADEAawwAAAEAOQBqDAAAAQAgAGwMAAABACAA6gwAAAEAJAABLgAECggJHgABAJAbAA==.',
Gr='Gripmedaddy:BAAALgAECgcJCwAAAA==.',
Ha='Haldrian:BAAALgAECgUJCAAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgYJEwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMdAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdAB0AAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB4AAwlDCiEhALUAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHQAICTsh0QsAkwIAHQAICTsh0QsAkwIAHgABCYQPllIAMQAAAAA=.Hop:BAABLgAECn8pAAIfAAkJhRtaAwCHAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAfAAkJhRtaAwCHAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAdAMkYAA==.Hotamnk:BAAALgAFFAIJAgABLgAFFAQJCQAdAMkYAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.Ironborn:BAAALgAECgQJBwAAAA==.',
Iv='Ivakor:BAAALgAECgUJDQAAAA==.Ivyy:BAACLgAFFH8MAAIgAAMJACQoEgAzAQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAgAAMJACQoEgAzAQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAuAAQKfxcAAiAACAkSIrkNAMACACAACAkSIrkNAMACAAAA.',
Ja='Jackswagz:BAABLgAECn8lAAMNAAkJgRNoJQDAAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABgA3AG4MAAADAB8AbwwAAAEACQANAAkJgRNoJQDAAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABQA3AG4MAAACAB8AbwwAAAEACQAOAAQJbAcsSgCkAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8nAAIDAAgJPxbtBQDXAQhoDAAABwArAGkMAAAGAEcAawwAAAYAVwBqDAAABgA8AGwMAAAEADQAbQwAAAEAEwDqDAAABgBGAG4MAAADADQAAwAICT8W7QUA1wEIaAwAAAcAKwBpDAAABgBHAGsMAAAGAFcAagwAAAYAPABsDAAABAA0AG0MAAABABMA6gwAAAYARgBuDAAAAwA0AAAA.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECgcJEwAMAAAAAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDAAAAA==.',
Ke='Kev:BAABLgAECn8qAAQYAAcJ6SRUHABnAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABgABwnpJFQcAGcCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAGgACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABkAAQkAADwSABcAAWoMAAABAAUAAAA=.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn8hAAITAAcJahpJRQCSAQdoDAAABwBUAGkMAAAFAEEAawwAAAUAMgBqDAAABQAxAGwMAAAEAEsAbQwAAAIAQgDqDAAABQA/ABMABwlqGklFAJIBB2gMAAAHAFQAaQwAAAUAQQBrDAAABQAyAGoMAAAFADEAbAwAAAQASwBtDAAAAgBCAOoMAAAFAD8AAAA=.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8TAAIGAAUJ3hg4CgBbAQVoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAOoMAAADAB4ABgAFCd4YOAoAWwEFaAwAAAYAVABpDAAABQBIAGsMAAAEAEMAagwAAAEAHgDqDAAAAwAeAC4ABAp/HQACBgAICTQd2jEAWwIABgAICTQd2jEAWwIAAAA=.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJBwAIAOACAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8eAAMSAAgJKRUIFwBFAQhoDAAABgA+AGkMAAAEAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAEwAHCTwNR48AYgEHaAwAAAUALgBpDAAAAwAmAGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgASAAUJjhwIFwBFAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgMJBAAAAA==.Mistake:BAAALgAECgYJEAAAAA==.',
Mo='Mockra:BAAALgAECgQJBAAAAA==.Monkcrocker:BAECLgAFFH8SAAIRAAcJAiMeAADgAgdoDAAAAwBaAGkMAAAFAF8AawwAAAMAXQBsDAAAAQBhAG0MAAACAEoA6gwAAAMAWwBuDAAAAQBUABEABwkCIx4AAOACB2gMAAADAFoAaQwAAAUAXwBrDAAAAwBdAGwMAAABAGEAbQwAAAIASgDqDAAAAwBbAG4MAAABAFQALgAECn8VAAIRAAcJ8SXADQC3AgARAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgMJAwAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCggJFQAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgUJBwABLgAFFAMJCgASAHENAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8JAAMGAAIJRxtySgCxAAJoDAAABQA5AOoMAAAEAFIABgACCUcbckoAsQACaAwAAAQAOQDqDAAABABSAAkAAQlpCAs2ADcAAWgMAAABABUALgAECn8wAAMGAAkJiiBpDAArAwAGAAkJiiBpDAArAwAJAAMJthYCUQCHAAAAAA==.',
Og='Ogganborn:BAABLgAECn8UAAIBAAUJJhu0VgAsAQVoDAAABABOAGkMAAAGAEsAawwAAAUALQBsDAAAAQA7AOoMAAAEAFcAAQAFCSYbtFYALAEFaAwAAAQATgBpDAAABgBLAGsMAAAFAC0AbAwAAAEAOwDqDAAABABXAAAA.',
On='Oneira:BAAALgADCggJDgAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIGAAcJ2RIhXQBXAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAYABwnZEiFdAFcBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8tAAMRAAkJZhynBgCOAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAARAAkJZhynBgCOAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAPAAIJIRNlYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAAALgAECgUJBwAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAAALgAECgYJEQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8vAAQhAAgJXiF6DQCdAghoDAAACABcAGkMAAAIAFcAawwAAAUAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAACACcAIQAICV4heg0AnQIIaAwAAAcAXABpDAAABgBXAGsMAAAEAFQAagwAAAYAYABsDAAABwBjAG0MAAADAFcA6gwAAAgAYABuDAAAAgAnAB8AAwlXFf4gAIcAA2gMAAABAC0AaQwAAAEAPQBrDAAAAQA4ACAAAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8NAAILAAcJZRkRAQD/AQdoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAAsABwllGREBAP8BB2gMAAACAE4AaQwAAAIAXgBrDAAAAgAvAGoMAAABAB8AbQwAAAEALADqDAAABABNAG4MAAABADAALgAECn8cAAILAAgJmyW1AQBoAwALAAgJmyW1AQBoAwAAAA==.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8ZAAIYAAYJNA4liAAbAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAQALQAYAAYJNA4liAAbAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAQALQAAAA==.',
Sa='Saelki:BAAALgADCgkJBwAAAA==.',
Se='Sephiran:BAABLgAECn8oAAMiAAgJ7h3TCgBFAghoDAAABgBYAGkMAAAGAFAAawwAAAYARwBqDAAABQBTAGwMAAAFAEoAbQwAAAQAOQDqDAAABQBYAG4MAAADAEsAIgAICe4d0woARQIIaAwAAAQAWABpDAAAAwBQAGsMAAADAEcAagwAAAIAUwBsDAAAAgBKAG0MAAACADkA6gwAAAIAWABuDAAAAgBLAB4ACAmOFyARAPUBCGgMAAACADoAaQwAAAMAPgBrDAAAAwA/AGoMAAADADkAbAwAAAMASwBtDAAAAgAyAOoMAAADADoAbgwAAAEANgAAAA==.',
Sh='Shagra:BAAALgAECgUJCAAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8WAAIcAAYJPCNdDAD/AQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAcAAYJPCNdDAD/AQZoDAAAAwBhAGkMAAAGAFQAawwAAAQAXQBqDAAAAQBeAGwMAAACAFcA6gwAAAYAVwAAAA==.Shoepert:BAABLgAECn8xAAIKAAkJbSX2AABVAwloDAAACQBhAGkMAAAHAGMAawwAAAcAYABqDAAABwBhAGwMAAAGAF0AbQwAAAQAYADqDAAABgBiAG4MAAACAFcAbwwAAAEAYAAKAAkJbSX2AABVAwloDAAACQBhAGkMAAAHAGMAawwAAAcAYABqDAAABwBhAGwMAAAGAF0AbQwAAAQAYADqDAAABgBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAMAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgUJCAAAAA==.',
Te='Tempus:BAACLgAFFH8KAAIJAAMJjx4NGQADAQNoDAAABABZAGkMAAAEADkA6gwAAAIAVwAJAAMJjx4NGQADAQNoDAAABABZAGkMAAAEADkA6gwAAAIAVwAuAAQKfx8AAwkACAnFG18kAAACAAkACAnFG18kAAACAAYAAQn9CkUsATIAAAAA.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgYJFwAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJAgAAAA==.',
Ty='Tyrgrim:BAAALgAECgUJCAAAAA==.',
Ul='Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgAMAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAABLgAECn8aAAQFAAgJHxT8EACfAQhoDAAABgBDAGkMAAAEAEEAawwAAAQANgBqDAAAAwAmAGwMAAACAC4AbQwAAAEAKgDqDAAABQA6AG4MAAABABoABQAICR8U/BAAnwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAgAuAG0MAAABACoA6gwAAAUAOgBuDAAAAQAaAAQAAQnnAbTpABkAAWgMAAABAAQAAwABCT8BSCsAEQABaAwAAAEAAwAAAA==.',
Va='Valalexis:BAAALgADCgcJBwAAAA==.',
Ve='Velawynn:BAACLgAFFH8aAAIdAAYJix9pAQAeAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwAdAAYJix9pAQAeAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwAuAAQKfy4AAx0ACQm6HhsFAP8CAB0ACQm6HhsFAP8CACIABAleDu86AMAAAAAA.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAISAAUJxRMcBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEgAFCcUTHAQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/FAADEgAICdwdNBIA6AEAEgAICfwcNBIA6AEAEwAGCf0aNX4AhwEAAAA=.',
Vh='Vhenir:BAAALgADCgUJCwAAAA==.',
Vi='Vixa:BAAALgAECgMJAwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAECgUJBQABLgAFFAQJCgAIAAIMAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJCwAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMLAAcJSRykDgCYAQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAsABgnuHaQOAJgBBmgMAAABAFAAaQwAAAEASABrDAAAAQBPAGoMAAABAEcAbAwAAAEATQDqDAAAAQBJAAoABwllGYQfAJEBB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkAAS4ABAoICSgAIgDuHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
