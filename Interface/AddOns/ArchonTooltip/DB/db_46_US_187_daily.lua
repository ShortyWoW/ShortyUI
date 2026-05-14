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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','Unknown-Unknown','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-13',data={Aa='Aandheeog:BAAALgAECggJDwAAAA==.',
Ab='Absqwas:BAAALgAECgEJAQAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgUJCAAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8yAAMBAAkJFB45CgCtAgloDAAABQBVAGkMAAAFAEsAawwAAAgAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAABAAkJFB45CgCtAgloDAAABABVAGkMAAAFAEsAawwAAAcAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAACAAIJsAK2gQBAAAJoDAAAAQAEAGsMAAABAAkAAAA=.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8SAAQDAAUJwCV6BwAOAgVoDAAABgBhAGkMAAAEAGAAawwAAAMAXwBqDAAAAQBhAOoMAAAEAGEAAwAFCcAlegcADgIFaAwAAAUAYQBpDAAABABgAGsMAAADAF8AagwAAAEAYQDqDAAAAgBhAAQAAgmDF9GTAIgAAmgMAAABACoA6gwAAAEATQAFAAEJXgGPUgAWAAHqDAAAAQADAAAA.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgMJAwAAAA==.Aneesa:BAABLgAECn8eAAMGAAcJqBfJQQCVAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAYABwmoF8lBAJUBB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMABwABCaMDjTsAIQABawwAAAEACQAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIIAAkJ2xBZEgDTAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAIAAkJ2xBZEgDTAQloDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABgA5AG4MAAACAB8AbwwAAAEALwAAAA==.Ashbahn:BAABLgAECn8yAAMJAAkJsgugIgCLAQloDAAACQAFAGkMAAAHACQAawwAAAcAFgBqDAAABwBFAGwMAAAGABwAbQwAAAQANQDqDAAABwAhAG4MAAACAA4AbwwAAAEABQAJAAkJsgugIgCLAQloDAAABAAFAGkMAAAFACQAawwAAAUAFgBqDAAABwBFAGwMAAAGABwAbQwAAAQANQDqDAAABQAhAG4MAAABAA4AbwwAAAEABQAGAAUJlBMJiAD1AAVoDAAABQBFAGkMAAACADkAawwAAAIAJQDqDAAAAgBDAG4MAAABABMAAAA=.Ashes:BAAALgAECgQJCQABLgAECgkJMgAJALILAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJBwAAAA==.',
Au='Auroranova:BAABLgAECn8jAAMGAAgJIQuuWABWAQhoDAAABgAkAGkMAAAGACUAawwAAAUAEwBqDAAABgAgAGwMAAAFACsAbQwAAAEAIQDqDAAABQAYAG4MAAABAAUABgAICSELrlgAVgEIaAwAAAYAJABpDAAABQAlAGsMAAAFABMAagwAAAUAIABsDAAABQArAG0MAAABACEA6gwAAAUAGABuDAAAAQAFAAkAAglnCPxcAFMAAmkMAAABAAkAagwAAAEAIQAAAA==.',
Ax='Axél:BAAALgAECgQJBwAAAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCAAAAA==.',
Br='Braei:BAAALgAECgMJAwAAAA==.Brilleleante:BAAALgADCgYJEwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAYJEQACAGQhAA==.Canimai:BAABLgAECn8lAAMKAAgJHhGqIgBuAQhoDAAABgA0AGkMAAAGADAAawwAAAYALwBqDAAABAAzAGwMAAAEAC0AbQwAAAMAIQDqDAAABQAjAG4MAAADACwACgAICWsOqiIAbgEIaAwAAAYANABpDAAABgAwAGsMAAAGAC8AagwAAAMAGwBsDAAAAgAXAG0MAAADACEA6gwAAAUAIwBuDAAAAgASAAsAAwmnEbsuAGYAA2oMAAABADMAbAwAAAIALQBuDAAAAQAsAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8KAAMMAAMJQQ1nLgC5AANoDAAABAALAGkMAAAEABYA6gwAAAIAQwAMAAMJQQ1nLgC5AANoDAAAAgALAGkMAAACABYA6gwAAAEAQwANAAMJNgQ4IgC1AANoDAAAAgAXAGkMAAACAAIA6gwAAAEABgAuAAQKfykAAw0ACAnwEModAH0BAA0ACAnwEModAH0BAAwAAQkkB16MADQAAAAA.',
Cu='Cubes:BAACLgAFFH8XAAMOAAYJcR96AAAjAgZoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAGwMAAABAAsA6gwAAAcAYwAOAAUJMiZ6AAAjAgVoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAOoMAAAHAGMADwABCeUSZioAUAABbAwAAAEAMAAuAAQKfy0ABA4ACQm1JRYBALgDAA4ACQm1JRYBALgDABAABgnNGJotAKMBAA8AAwk/DgxEAJkAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deathcrocker:BAECLgAFFH8aAAIRAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABgBhAGwMAAADAF8A6gwAAAUAYwARAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABgBhAGwMAAADAF8A6gwAAAUAYwAuAAQKfxoAAhEACQkDJmwAAMsDABEACQkDJmwAAMsDAAEuAAUUBwkPABAArSIA.Decksey:BAAALgADCgEJAQABLgADCgYJCQASAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIGAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABgAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBQkTAAYA3hgA.',
Do='Dogs:BAACLgAFFH8LAAIKAAQJxBouDgBCAQRoDAAAAwBKAGkMAAADAFMAawwAAAIAGADqDAAAAwBbAAoABAnEGi4OAEIBBGgMAAADAEoAaQwAAAMAUwBrDAAAAgAYAOoMAAADAFsALgAECn8bAAIKAAgJ6xvXDQDmAgAKAAgJ6xvXDQDmAgABLgAFFAcJFQAGAOcbAA==.Domar:BAAALgAECgQJBwAAAA==.Doomslayer:BAABLgAECn8kAAMTAAkJ7BpQJQAJAgloDAAABwBgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAkJ7BpQJQAJAgloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQARAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAAAA=.Doraei:BAABLgAECn8VAAITAAgJmg59PgCeAQhoDAAAAwApAGkMAAADADUAawwAAAMALwBqDAAAAwA5AGwMAAADACsAbQwAAAEAFgDqDAAAAwAlAG4MAAACABAAEwAICZoOfT4AngEIaAwAAAMAKQBpDAAAAwA1AGsMAAADAC8AagwAAAMAOQBsDAAAAwArAG0MAAABABYA6gwAAAMAJQBuDAAAAgAQAAAA.Dothippo:BAABLgAECn8qAAMUAAcJthsCBADpAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABQABwm2GwIEAOkBB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFQABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8gAAIGAAkJSRc7KwDpAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAGAAkJSRc7KwDpAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAAAA==.',
Ea='Easy:BAAALgAECgIJBQABLgAECgYJBgASAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJDQAWAPEXAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8WAAIKAAgJvgzuIAB5AQhoDAAABQA+AGkMAAADACEAawwAAAMAJQBqDAAAAwAbAGwMAAACAAoAbQwAAAEAEQDqDAAABAAaAG4MAAABACcACgAICb4M7iAAeQEIaAwAAAUAPgBpDAAAAwAhAGsMAAADACUAagwAAAMAGwBsDAAAAgAKAG0MAAABABEA6gwAAAQAGgBuDAAAAQAnAAAA.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8UAAIXAAcJ5xqFCgDLAQdoDAAAAwBUAGkMAAACAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABADqDAAABgBdABcABwnnGoUKAMsBB2gMAAADAFQAaQwAAAIAYQBrDAAAAwBBAGoMAAADADMAbAwAAAIAQwBtDAAAAQAEAOoMAAAGAF0ALgAECn8hAAQXAAkJfSJdDQBaAwAXAAkJfSJdDQBaAwAYAAEJ0yAHDQBZAAAZAAEJGw8dGgBHAAAAAA==.Froslass:BAABLgAECn8ZAAITAAgJfh1bIQAeAghoDAAABQBeAGkMAAADAFkAawwAAAMASgBqDAAABAA9AGwMAAAEAEIAbQwAAAEAJgDqDAAAAwBRAG4MAAACAFQAEwAICX4dWyEAHgIIaAwAAAUAXgBpDAAAAwBZAGsMAAADAEoAagwAAAQAPQBsDAAABABCAG0MAAABACYA6gwAAAMAUQBuDAAAAgBUAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgQJBQAAAA==.',
Gl='Gloryhammer:BAABLgAECn8kAAQHAAkJHBuNCABPAgloDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYAbwwAAAEARwAHAAkJHBuNCABPAgloDAAABQBgAGkMAAAFAF4AawwAAAUAVgBqDAAAAwBfAGwMAAADAEUAbQwAAAIAIQDqDAAABQBPAG4MAAABABYAbwwAAAEARwAJAAUJKAXGawDLAAVpDAAAAQAJAGsMAAABAB4AagwAAAEAAABsDAAAAQAUAOoMAAABAAQABgABCWsZpkMBMwABaAwAAAEAQQAAAA==.',
Go='Gobbs:BAABLgAECn8YAAMaAAYJIBKJCwBzAQZoDAAABQAwAGkMAAAFADkAawwAAAYAOQBqDAAAAwAgAGwMAAACACAA6gwAAAMAJAAaAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAbAAYJEBE+HAAzAQZoDAAAAQAqAGkMAAABADEAawwAAAEAOQBqDAAAAQAgAGwMAAABACAA6gwAAAEAJAABLgAECggJHgABAJAbAA==.',
Gr='Gripmedaddy:BAAALgAECgUJBwAAAA==.',
Ha='Haldrian:BAAALgAECgMJAwAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgYJEwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMcAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdABwAAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB0AAwlDCi8gALUAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHAAICTsh0QsAkwIAHAAICTsh0QsAkwIAHQABCYQP608AMQAAAAA=.Hop:BAABLgAECn8pAAIeAAkJhRvaAgCRAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAeAAkJhRvaAgCRAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAcAMkYAA==.Hotamnk:BAAALgAFFAIJAgABLgAFFAQJCQAcAMkYAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.Ironborn:BAAALgAECgQJBwAAAA==.',
Iv='Ivakor:BAAALgAECgUJDQAAAA==.Ivyy:BAACLgAFFH8MAAIfAAMJACRGEQA2AQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAfAAMJACRGEQA2AQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAuAAQKfxcAAh8ACAkSIrkNAMACAB8ACAkSIrkNAMACAAEuAAUUBgkaABsAbh0A.',
Ja='Jackswagz:BAABLgAECn8lAAMMAAkJgROYIgDDAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAHAD8AbQwAAAQAJADqDAAABgA3AG4MAAADAB8AbwwAAAEACQAMAAkJgROYIgDDAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABQA3AG4MAAACAB8AbwwAAAEACQANAAQJbAfARgCpAARsDAAAAQAaAG0MAAABABMA6gwAAAEACABuDAAAAQAVAAAA.Jaszuny:BAABLgAECn8jAAIDAAgJ1BRQBgC4AQhoDAAABwArAGkMAAAFAD4AawwAAAUATgBqDAAABQA8AGwMAAADAC0AbQwAAAEAEwDqDAAABgBGAG4MAAADADQAAwAICdQUUAYAuAEIaAwAAAcAKwBpDAAABQA+AGsMAAAFAE4AagwAAAUAPABsDAAAAwAtAG0MAAABABMA6gwAAAYARgBuDAAAAwA0AAAA.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECgcJEwASAAAAAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDAAAAA==.',
Ke='Kev:BAABLgAECn8qAAQXAAcJ6SSnGABzAgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABcABwnpJKcYAHMCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAGQACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABgAAQkAADwSABcAAWoMAAABAAUAAAA=.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn8hAAITAAcJahqjOwCoAQdoDAAABwBUAGkMAAAFAEEAawwAAAUAMgBqDAAABQAxAGwMAAAEAEsAbQwAAAIAQgDqDAAABQA/ABMABwlqGqM7AKgBB2gMAAAHAFQAaQwAAAUAQQBrDAAABQAyAGoMAAAFADEAbAwAAAQASwBtDAAAAgBCAOoMAAAFAD8AAAA=.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8TAAIGAAUJ3hg4CgBbAQVoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAOoMAAADAB4ABgAFCd4YOAoAWwEFaAwAAAYAVABpDAAABQBIAGsMAAAEAEMAagwAAAEAHgDqDAAAAwAeAC4ABAp/HQACBgAICTQd2jEAWwIABgAICTQd2jEAWwIAAAA=.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJBwAIAOACAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8eAAMRAAgJKRW6FABPAQhoDAAABgA+AGkMAAAEAFQAawwAAAUATABqDAAABQBOAGwMAAACAB0AbQwAAAIABwDqDAAABQAyAG4MAAABAEUAEwAHCTwNR48AYgEHaAwAAAUALgBpDAAAAwAmAGsMAAACAB8AagwAAAQALQBsDAAAAgAdAG0MAAACAAcA6gwAAAUAMgARAAUJjhy6FABPAQVoDAAAAQA+AGkMAAABAFQAawwAAAMATABqDAAAAQBOAG4MAAABAEUAAAA=.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgMJBAAAAA==.Mistake:BAAALgAECgYJEAAAAA==.',
Mo='Mockra:BAAALgAECgQJBAAAAA==.Monkcrocker:BAECLgAFFH8PAAIQAAcJrSIcAADYAgdoDAAAAgBYAGkMAAAEAF8AawwAAAIAWQBsDAAAAQBhAG0MAAACAEoA6gwAAAMAWwBuDAAAAQBUABAABwmtIhwAANgCB2gMAAACAFgAaQwAAAQAXwBrDAAAAgBZAGwMAAABAGEAbQwAAAIASgDqDAAAAwBbAG4MAAABAFQALgAECn8VAAIQAAcJ8SXADQC3AgAQAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgMJAwAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCggJFQAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgUJBwABLgAFFAMJCgARAHENAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8JAAMGAAIJRxsmSACyAAJoDAAABQA5AOoMAAAEAFIABgACCUcbJkgAsgACaAwAAAQAOQDqDAAABABSAAkAAQlpCKk0ADcAAWgMAAABABUALgAECn8wAAMGAAkJiiBpDAArAwAGAAkJiiBpDAArAwAJAAMJthYCTgCLAAAAAA==.',
Og='Ogganborn:BAABLgAECn8UAAIBAAUJJhvtTgA6AQVoDAAABABOAGkMAAAGAEsAawwAAAUALQBsDAAAAQA7AOoMAAAEAFcAAQAFCSYb7U4AOgEFaAwAAAQATgBpDAAABgBLAGsMAAAFAC0AbAwAAAEAOwDqDAAABABXAAAA.',
On='Oneira:BAAALgADCggJDgAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIGAAcJ2RKfVQBeAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAYABwnZEp9VAF4BB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8tAAMQAAkJZhzQBQCYAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAQAAkJZhzQBQCYAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAOAAIJIRNlYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAAALgAECgUJBwAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAOABkcAA==.Railiana:BAAALgAECgYJEQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8vAAQgAAgJXiFdDACkAghoDAAACABcAGkMAAAIAFcAawwAAAUAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAACACcAIAAICV4hXQwApAIIaAwAAAcAXABpDAAABgBXAGsMAAAEAFQAagwAAAYAYABsDAAABwBjAG0MAAADAFcA6gwAAAgAYABuDAAAAgAnAB4AAwlXFUQfAIoAA2gMAAABAC0AaQwAAAEAPQBrDAAAAQA4AB8AAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAOAJwPAA==.',
Ru='Ruby:BAACLgAFFH8NAAILAAcJZRkRAQD/AQdoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAAsABwllGREBAP8BB2gMAAACAE4AaQwAAAIAXgBrDAAAAgAvAGoMAAABAB8AbQwAAAEALADqDAAABABNAG4MAAABADAALgAECn8cAAILAAgJmyW1AQBoAwALAAgJmyW1AQBoAwAAAA==.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8ZAAIXAAYJNA6yfwAlAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAQALQAXAAYJNA6yfwAlAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAQALQAAAA==.',
Sa='Saelki:BAAALgADCgkJBwAAAA==.',
Se='Sephiran:BAABLgAECn8oAAMhAAgJ7h0YCQBUAghoDAAABgBYAGkMAAAGAFAAawwAAAYARwBqDAAABQBTAGwMAAAFAEoAbQwAAAQAOQDqDAAABQBYAG4MAAADAEsAIQAICe4dGAkAVAIIaAwAAAQAWABpDAAAAwBQAGsMAAADAEcAagwAAAIAUwBsDAAAAgBKAG0MAAACADkA6gwAAAIAWABuDAAAAgBLAB0ACAmOF/0OAAECCGgMAAACADoAaQwAAAMAPgBrDAAAAwA/AGoMAAADADkAbAwAAAMASwBtDAAAAgAyAOoMAAADADoAbgwAAAEANgAAAA==.',
Sh='Shagra:BAAALgAECgUJBQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAAALgAECgYJEQAAAA==.Shoepert:BAABLgAECn8xAAIKAAkJbSWjAABmAwloDAAACQBhAGkMAAAHAGMAawwAAAcAYABqDAAABwBhAGwMAAAGAF0AbQwAAAQAYADqDAAABgBiAG4MAAACAFcAbwwAAAEAYAAKAAkJbSWjAABmAwloDAAACQBhAGkMAAAHAGMAawwAAAcAYABqDAAABwBhAGwMAAAGAF0AbQwAAAQAYADqDAAABgBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgASAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgMJAwAAAA==.',
Te='Tempus:BAACLgAFFH8KAAIJAAMJjx4PGAAFAQNoDAAABABZAGkMAAAEADkA6gwAAAIAVwAJAAMJjx4PGAAFAQNoDAAABABZAGkMAAAEADkA6gwAAAIAVwAuAAQKfx8AAwkACAnFG18kAAACAAkACAnFG18kAAACAAYAAQn9CnkmATIAAAAA.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgYJFwAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJAgAAAA==.',
Ty='Tyrgrim:BAAALgAECgMJAwAAAA==.',
Ul='Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgASAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAABLgAECn8aAAQFAAgJHxSLDwCpAQhoDAAABgBDAGkMAAAEAEEAawwAAAQANgBqDAAAAwAmAGwMAAACAC4AbQwAAAEAKgDqDAAABQA6AG4MAAABABoABQAICR8Uiw8AqQEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAgAuAG0MAAABACoA6gwAAAUAOgBuDAAAAQAaAAQAAQnnATDlABkAAWgMAAABAAQAAwABCT8ByCkAEQABaAwAAAEAAwAAAA==.',
Va='Valalexis:BAAALgADCgcJBwAAAA==.',
Ve='Velawynn:BAACLgAFFH8aAAIcAAYJix89AQAfAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwAcAAYJix89AQAfAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAcAWwAuAAQKfy4AAxwACQm6HhsFAP8CABwACQm6HhsFAP8CACEABAleDlo4AMQAAAAA.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAIRAAUJxRMcBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEQAFCcUTHAQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/FAADEQAICdwdNBIA6AEAEQAICfwcNBIA6AEAEwAGCf0aNX4AhwEAAAA=.',
Vh='Vhenir:BAAALgADCgUJCwAAAA==.',
Vi='Vixa:BAAALgAECgMJAwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAECgUJBQABLgAFFAQJCgAIAAIMAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJCwAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMLAAcJSRxSDQChAQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAoABwllGeEaAKUBB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkACwAGCe4dUg0AoQEGaAwAAAEAUABpDAAAAQBIAGsMAAABAE8AagwAAAEARwBsDAAAAQBNAOoMAAABAEkAAS4ABAoICSgAIQDuHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
Zy='Zynri:BAAALgADCgYJBwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
