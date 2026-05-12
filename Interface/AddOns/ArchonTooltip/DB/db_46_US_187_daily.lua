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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-12',data={Aa='Aandheeog:BAAALgAECgYJDAAAAA==.',
Ab='Absqwas:BAAALgADCggJEgAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgUJBQAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8yAAMBAAkJFB5KCQCzAgloDAAABQBVAGkMAAAFAEsAawwAAAgAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAABAAkJFB5KCQCzAgloDAAABABVAGkMAAAFAEsAawwAAAcAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAACAAIJsAK2gQBAAAJoDAAAAQAEAGsMAAABAAkAAAA=.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8SAAQDAAUJwCV6BwAOAgVoDAAABgBhAGkMAAAEAGAAawwAAAMAXwBqDAAAAQBhAOoMAAAEAGEAAwAFCcAlegcADgIFaAwAAAUAYQBpDAAABABgAGsMAAADAF8AagwAAAEAYQDqDAAAAgBhAAQAAgmDF2aQAIkAAmgMAAABACoA6gwAAAEATQAFAAEJXgHNUAAWAAHqDAAAAQADAAAA.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgMJAwAAAA==.Aneesa:BAABLgAECn8eAAMGAAcJqBcgPgCfAQdoDAAABgBHAGkMAAAGAEgAawwAAAYAMABqDAAABQBIAGwMAAAEADEA6gwAAAIANgBuDAAAAQBDAAYABwmoFyA+AJ8BB2gMAAAGAEcAaQwAAAYASABrDAAABQAwAGoMAAAFAEgAbAwAAAQAMQDqDAAAAgA2AG4MAAABAEMABwABCaMDXDoAIQABawwAAAEACQAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8ZAAIIAAgJLRC9GQCHAQhoDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABQA5AG4MAAABABcACAAICS0QvRkAhwEIaAwAAAQAOwBpDAAABAA5AGsMAAAEACQAagwAAAMALABsDAAAAwAnAG0MAAABAA8A6gwAAAUAOQBuDAAAAQAXAAAA.Ashbahn:BAABLgAECn8rAAMJAAkJPQr1JAB0AQloDAAACAAFAGkMAAAGACQAawwAAAYAFgBqDAAABgBFAGwMAAAFABUAbQwAAAMAGwDqDAAABgAhAG4MAAACAA4AbwwAAAEABQAJAAkJPQr1JAB0AQloDAAAAwAFAGkMAAAEACQAawwAAAQAFgBqDAAABgBFAGwMAAAFABUAbQwAAAMAGwDqDAAABAAhAG4MAAABAA4AbwwAAAEABQAGAAUJlBMpggD/AAVoDAAABQBFAGkMAAACADkAawwAAAIAJQDqDAAAAgBDAG4MAAABABMAAAA=.Ashes:BAAALgAECgQJCQABLgAECgkJKwAJAD0KAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJBwAAAA==.',
Au='Auroranova:BAABLgAECn8dAAMGAAgJMggCZAA8AQhoDAAABQAWAGkMAAAFABoAawwAAAQAEABqDAAABQAgAGwMAAAEABIAbQwAAAEAIQDqDAAABAAYAG4MAAABAAUABgAICTIIAmQAPAEIaAwAAAUAFgBpDAAABAAaAGsMAAAEABAAagwAAAUAIABsDAAABAASAG0MAAABACEA6gwAAAQAGABuDAAAAQAFAAkAAQnEA9p1ACIAAWkMAAABAAkAAAA=.',
Ax='Axél:BAAALgAECgQJBwAAAA==.',
Be='Berringer:BAAALgAECgQJCgAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCAAAAA==.',
Br='Braei:BAAALgAECgMJAwAAAA==.Brilleleante:BAAALgADCgYJEAAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAAAAA==.Canimai:BAABLgAECn8lAAMKAAgJHhFTIQBxAQhoDAAABgA0AGkMAAAGADAAawwAAAYALwBqDAAABAAzAGwMAAAEAC0AbQwAAAMAIQDqDAAABQAjAG4MAAADACwACgAICWsOUyEAcQEIaAwAAAYANABpDAAABgAwAGsMAAAGAC8AagwAAAMAGwBsDAAAAgAXAG0MAAADACEA6gwAAAUAIwBuDAAAAgASAAsAAwmnEbktAGcAA2oMAAABADMAbAwAAAIALQBuDAAAAQAsAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJCgAMAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAEAAYJnwVXlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8HAAMNAAMJfwGHIgCnAANoDAAAAwACAGkMAAADAAIA6gwAAAEABgANAAMJfwGHIgCnAANoDAAAAQACAGkMAAACAAIA6gwAAAEABgAOAAIJtwYGHACIAAJoDAAAAgALAGkMAAABABYALgAECn8lAAMNAAgJWhCBHQB5AQANAAgJWhCBHQB5AQAOAAEJJAc8iQA0AAAAAA==.',
Cu='Cubes:BAACLgAFFH8WAAMPAAYJcR96AAAjAgZoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAGwMAAABAAsA6gwAAAYAYwAPAAUJMiZ6AAAjAgVoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAOoMAAAGAGMAEAABCeUS8ygAUAABbAwAAAEAMAAuAAQKfy0ABA8ACQm1JRYBALgDAA8ACQm1JRYBALgDABEABgnNGJotAKMBABAAAwk/Dv5BAJoAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJAwAAAA==.',
De='Deathcrocker:BAECLgAFFH8aAAISAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABgBhAGwMAAADAF8A6gwAAAUAYwASAAYJoCVLAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABgBhAGwMAAADAF8A6gwAAAUAYwAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAEuAAUUBwkPABEArSIA.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIGAAgJBBcmTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABgAICQQXJk0A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBQkTAAYA3hgA.',
Do='Dogs:BAACLgAFFH8LAAIKAAQJxBp8DQBDAQRoDAAAAwBKAGkMAAADAFMAawwAAAIAGADqDAAAAwBbAAoABAnEGnwNAEMBBGgMAAADAEoAaQwAAAMAUwBrDAAAAgAYAOoMAAADAFsALgAECn8bAAIKAAgJ6xvXDQDmAgAKAAgJ6xvXDQDmAgABLgAFFAcJFQAGAOcbAA==.Domar:BAAALgAECgQJBwAAAA==.Doomslayer:BAABLgAECn8kAAMTAAkJ7Bo4IwANAgloDAAABwBgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAkJ7Bo4IwANAgloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQASAAUJgAL3MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAAAA=.Doraei:BAAALgAECggJDgAAAA==.Dothippo:BAABLgAECn8qAAMUAAcJthvCAwDtAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABQABwm2G8IDAO0BB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFQABCRYEdSgBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8gAAIGAAkJSReIKQDvAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAGAAkJSReIKQDvAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAAAA==.',
Ea='Easy:BAAALgAECgIJBAABLgAECgYJBgAMAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJDQAWAPEXAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAAALgAECgcJEwAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fr='Freezing:BAAALgAECgEJAgAAAA==.Frieren:BAACLgAFFH8SAAIXAAcJ5xqFCgDLAQdoDAAAAgBUAGkMAAACAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABADqDAAABQBdABcABwnnGoUKAMsBB2gMAAACAFQAaQwAAAIAYQBrDAAAAwBBAGoMAAADADMAbAwAAAIAQwBtDAAAAQAEAOoMAAAFAF0ALgAECn8hAAQXAAkJfSJdDQBaAwAXAAkJfSJdDQBaAwAYAAEJ0yAHDQBZAAAZAAEJGw8dGgBHAAAAAA==.Froslass:BAABLgAECn8VAAITAAgJSRppKgDpAQhoDAAABABeAGkMAAADAFkAawwAAAMASgBqDAAAAwAzAGwMAAADADQAbQwAAAEAJgDqDAAAAwBRAG4MAAABACkAEwAICUkaaSoA6QEIaAwAAAQAXgBpDAAAAwBZAGsMAAADAEoAagwAAAMAMwBsDAAAAwA0AG0MAAABACYA6gwAAAMAUQBuDAAAAQApAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgQJBQAAAA==.',
Gl='Gloryhammer:BAABLgAECn8jAAQHAAgJARuNCABPAghoDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYABwAICQEbjQgATwIIaAwAAAUAYABpDAAABQBeAGsMAAAFAFYAagwAAAMAXwBsDAAAAwBFAG0MAAACACEA6gwAAAUATwBuDAAAAQAWAAkABQkoBcZrAMsABWkMAAABAAkAawwAAAEAHgBqDAAAAQAAAGwMAAABABQA6gwAAAEABAAGAAEJaxmmQwEzAAFoDAAAAQBBAAAA.',
Go='Gobbs:BAABLgAECn8YAAMaAAYJIBKJCwBzAQZoDAAABQAwAGkMAAAFADkAawwAAAYAOQBqDAAAAwAgAGwMAAACACAA6gwAAAMAJAAaAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAbAAYJEBEgGwA3AQZoDAAAAQAqAGkMAAABADEAawwAAAEAOQBqDAAAAQAgAGwMAAABACAA6gwAAAEAJAABLgAECggJHgABAJAbAA==.',
Gr='Gripmedaddy:BAAALgAECgIJAgAAAA==.',
Ha='Haldrian:BAAALgAECgMJAwAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgYJEwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMcAAQJyRimCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdABwAAwkwHaYKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB0AAwlDCmEfALcAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHAAICTsh0QsAkwIAHAAICTsh0QsAkwIAHQABCYQPGk4AMQAAAAA=.Hop:BAABLgAECn8pAAIeAAkJhRujAgCUAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAeAAkJhRujAgCUAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAcAMkYAA==.Hotamnk:BAAALgAECgMJAwABLgAFFAQJCQAcAMkYAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.Ironborn:BAAALgAECgQJBwAAAA==.',
Iv='Ivakor:BAAALgAECgUJDQAAAA==.Ivyy:BAACLgAFFH8MAAIfAAMJACQfEgA3AQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAfAAMJACQfEgA3AQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAuAAQKfxcAAh8ACAkSIrkNAMACAB8ACAkSIrkNAMACAAEuAAUUBQkXABsA1SIA.',
Ja='Jackswagz:BAABLgAECn8hAAMOAAkJgRNrIQDDAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABQA3AG4MAAACAB8AbwwAAAEACQAOAAkJgRNrIQDDAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAFAD8AbQwAAAIAJADqDAAABAA3AG4MAAACAB8AbwwAAAEACQANAAMJCQdcTwCBAANsDAAAAQAaAG0MAAABABMA6gwAAAEACAAAAA==.Jaszuny:BAABLgAECn8gAAIDAAgJVRRWBgCvAQhoDAAABgArAGkMAAAFAD4AawwAAAUATgBqDAAABQA8AGwMAAADAC0AbQwAAAEAEwDqDAAABQA+AG4MAAACADQAAwAICVUUVgYArwEIaAwAAAYAKwBpDAAABQA+AGsMAAAFAE4AagwAAAUAPABsDAAAAwAtAG0MAAABABMA6gwAAAUAPgBuDAAAAgA0AAAA.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAgABLgAECgcJEwAMAAAAAA==.Kasho:BAAALgAECgEJAQAAAA==.Katsumotosan:BAAALgADCggJDAAAAA==.',
Ke='Kev:BAABLgAECn8qAAQXAAcJ6SQ8FwB3AgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABcABwnpJDwXAHcCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAGQACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABgAAQkAADwSABcAAWoMAAABAAUAAAA=.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn8hAAITAAcJahphOACuAQdoDAAABwBUAGkMAAAFAEEAawwAAAUAMgBqDAAABQAxAGwMAAAEAEsAbQwAAAIAQgDqDAAABQA/ABMABwlqGmE4AK4BB2gMAAAHAFQAaQwAAAUAQQBrDAAABQAyAGoMAAAFADEAbAwAAAQASwBtDAAAAgBCAOoMAAAFAD8AAAA=.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8TAAIGAAUJ3hg4CgBbAQVoDAAABgBUAGkMAAAFAEgAawwAAAQAQwBqDAAAAQAeAOoMAAADAB4ABgAFCd4YOAoAWwEFaAwAAAYAVABpDAAABQBIAGsMAAAEAEMAagwAAAEAHgDqDAAAAwAeAC4ABAp/HQACBgAICTQd2jEAWwIABgAICTQd2jEAWwIAAAA=.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAECgkJGAAIACsIAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8ZAAMTAAcJeQ1HjwBiAQdoDAAABQAuAGkMAAADACYAawwAAAQAIwBqDAAABAAtAGwMAAACAB0AbQwAAAIABwDqDAAABQAyABMABwk8DUePAGIBB2gMAAAFAC4AaQwAAAMAJgBrDAAAAgAfAGoMAAAEAC0AbAwAAAIAHQBtDAAAAgAHAOoMAAAFADIAEgABCbENvUYALQABawwAAAIAIwAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgEJAQAAAA==.Mistake:BAAALgAECgYJEAAAAA==.',
Mo='Mockra:BAAALgAECgEJAQABLgAECgIJAgAMAAAAAA==.Monkcrocker:BAECLgAFFH8PAAIRAAcJrSIYAADYAgdoDAAAAgBYAGkMAAAEAF8AawwAAAIAWQBsDAAAAQBhAG0MAAACAEoA6gwAAAMAWwBuDAAAAQBUABEABwmtIhgAANgCB2gMAAACAFgAaQwAAAQAXwBrDAAAAgBZAGwMAAABAGEAbQwAAAIASgDqDAAAAwBbAG4MAAABAFQALgAECn8VAAIRAAcJ8SXADQC3AgARAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgMJAwAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCggJFQAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgUJBwABLgAFFAMJBwASACoHAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8JAAMGAAIJRxt9RgCzAAJoDAAABQA5AOoMAAAEAFIABgACCUcbfUYAswACaAwAAAQAOQDqDAAABABSAAkAAQlpCIMzADcAAWgMAAABABUALgAECn8wAAMGAAkJiiDzCQDOAgAGAAkJiiDzCQDOAgAJAAMJthb/PgDTAAAAAA==.',
Og='Ogganborn:BAABLgAECn8UAAIBAAUJJhsBTAA9AQVoDAAABABOAGkMAAAGAEsAawwAAAUALQBsDAAAAQA7AOoMAAAEAFcAAQAFCSYbAUwAPQEFaAwAAAQATgBpDAAABgBLAGsMAAAFAC0AbAwAAAEAOwDqDAAABABXAAAA.',
On='Oneira:BAAALgADCggJDgAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIGAAcJ2RJTUgBnAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAYABwnZElNSAGcBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8tAAMRAAkJZhx3BQCbAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAARAAkJZhx3BQCbAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAPAAIJIRNlYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAAALgAECgUJBwAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAAALgAECgYJEQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8vAAQgAAgJXiHRCwCkAghoDAAACABcAGkMAAAIAFcAawwAAAUAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAACACcAIAAICV4h0QsApAIIaAwAAAcAXABpDAAABgBXAGsMAAAEAFQAagwAAAYAYABsDAAABwBjAG0MAAADAFcA6gwAAAgAYABuDAAAAgAnAB4AAwlXFZQeAIoAA2gMAAABAC0AaQwAAAEAPQBrDAAAAQA4AB8AAQkoAv+OAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8NAAILAAcJZRkRAQD/AQdoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAAsABwllGREBAP8BB2gMAAACAE4AaQwAAAIAXgBrDAAAAgAvAGoMAAABAB8AbQwAAAEALADqDAAABABNAG4MAAABADAALgAECn8cAAILAAgJmyW1AQBoAwALAAgJmyW1AQBoAwAAAA==.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8ZAAIXAAYJNA7RegAuAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAQALQAXAAYJNA7RegAuAQZoDAAABQAuAGkMAAAFABoAawwAAAUAKABqDAAAAwAQAGwMAAADABYA6gwAAAQALQAAAA==.',
Sa='Saelki:BAAALgADCgkJBwAAAA==.',
Se='Sephiran:BAABLgAECn8oAAMhAAgJ7h2GCABZAghoDAAABgBYAGkMAAAGAFAAawwAAAYARwBqDAAABQBTAGwMAAAFAEoAbQwAAAQAOQDqDAAABQBYAG4MAAADAEsAIQAICe4dhggAWQIIaAwAAAQAWABpDAAAAwBQAGsMAAADAEcAagwAAAIAUwBsDAAAAgBKAG0MAAACADkA6gwAAAIAWABuDAAAAgBLAB0ACAmOFzkOAAYCCGgMAAACADoAaQwAAAMAPgBrDAAAAwA/AGoMAAADADkAbAwAAAMASwBtDAAAAgAyAOoMAAADADoAbgwAAAEANgAAAA==.',
Sh='Shagra:BAAALgAECgUJBQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAAALgAECgYJEQAAAA==.Shoepert:BAABLgAECn8qAAIKAAkJ7CTfAABQAwloDAAACABhAGkMAAAGAGMAawwAAAYAWgBqDAAABgBhAGwMAAAFAF0AbQwAAAMAXADqDAAABQBiAG4MAAACAFcAbwwAAAEAYAAKAAkJ7CTfAABQAwloDAAACABhAGkMAAAGAGMAawwAAAYAWgBqDAAABgBhAGwMAAAFAF0AbQwAAAMAXADqDAAABQBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAMAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgMJAwAAAA==.',
Te='Tempus:BAACLgAFFH8HAAIJAAMJjx5/FwAFAQNoDAAAAwBZAGkMAAADADkA6gwAAAEAVwAJAAMJjx5/FwAFAQNoDAAAAwBZAGkMAAADADkA6gwAAAEAVwAuAAQKfxwAAwkACAkOG18kAAACAAkACAkOG18kAAACAAYAAQnJAtxOAS0AAAAA.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgYJFAAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJAgAAAA==.',
Ty='Tyrgrim:BAAALgAECgMJAwAAAA==.',
Ul='Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgAMAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAABLgAECn8ZAAMFAAgJHxTzDgCrAQhoDAAABQBDAGkMAAAEAEEAawwAAAQANgBqDAAAAwAmAGwMAAACAC4AbQwAAAEAKgDqDAAABQA6AG4MAAABABoABQAICR8U8w4AqwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAgAuAG0MAAABACoA6gwAAAUAOgBuDAAAAQAaAAQAAQnnAU/hABkAAWgMAAABAAQAAAA=.',
Va='Valalexis:BAAALgADCgcJBwAAAA==.',
Ve='Velawynn:BAACLgAFFH8ZAAIcAAYJix8eAQAgAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAYAWwAcAAYJix8eAQAgAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAYAWwAuAAQKfy4AAxwACQm6HhsFAP8CABwACQm6HhsFAP8CACEABAleDro3AMQAAAAA.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAISAAUJxRMcBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEgAFCcUTHAQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/FAADEgAICdwdNBIA6AEAEgAICfwcNBIA6AEAEwAGCf0aNX4AhwEAAAA=.',
Vh='Vhenir:BAAALgADCgUJCwAAAA==.',
Vi='Vixa:BAAALgAECgMJAwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAECgUJBQABLgAFFAQJBgAIAAQJAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJCwAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMLAAcJSRzVDACkAQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAoABwllGZoZAKoBB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkACwAGCe4d1QwApAEGaAwAAAEAUABpDAAAAQBIAGsMAAABAE8AagwAAAEARwBsDAAAAQBNAOoMAAABAEkAAS4ABAoICSgAIQDuHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
