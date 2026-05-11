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
local provider = {region='US',realm='Sentinels',name='US',type='daily',zone=46,date='2026-05-10',data={Aa='Aandheeog:BAAALgAECgYJDAAAAA==.',
Ab='Absqwas:BAAALgADCggJEgAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8yAAMBAAkJFB4PCAC1AgloDAAABQBVAGkMAAAFAEsAawwAAAgAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAABAAkJFB4PCAC1AgloDAAABABVAGkMAAAFAEsAawwAAAcAWwBqDAAABwAyAGwMAAAHAFcAbQwAAAUAQwDqDAAABwBNAG4MAAAFAEYAbwwAAAEAPAACAAIJsAK2gQBAAAJoDAAAAQAEAGsMAAABAAkAAAA=.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8SAAQDAAUJwCV6BwAOAgVoDAAABgBhAGkMAAAEAGAAawwAAAMAXwBqDAAAAQBhAOoMAAAEAGEAAwAFCcAlegcADgIFaAwAAAUAYQBpDAAABABgAGsMAAADAF8AagwAAAEAYQDqDAAAAgBhAAQAAgmDFxqLAIcAAmgMAAABACoA6gwAAAEATQAFAAEJXgGWTQAWAAHqDAAAAQADAAAA.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgMJAwAAAA==.Aneesa:BAABLgAECn8YAAMGAAcJ3BVycAAWAQdoDAAABQBHAGkMAAAFAEgAawwAAAUAMABqDAAABABIAGwMAAADADEA6gwAAAEAGgBuDAAAAQBDAAYABwncFXJwABYBB2gMAAAFAEcAaQwAAAUASABrDAAABAAwAGoMAAAEAEgAbAwAAAMAMQDqDAAAAQAaAG4MAAABAEMABwABCaMDYDgAIQABawwAAAEACQAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8ZAAIIAAgJLRCtGACGAQhoDAAABAA7AGkMAAAEADkAawwAAAQAJABqDAAAAwAsAGwMAAADACcAbQwAAAEADwDqDAAABQA5AG4MAAABABcACAAICS0QrRgAhgEIaAwAAAQAOwBpDAAABAA5AGsMAAAEACQAagwAAAMALABsDAAAAwAnAG0MAAABAA8A6gwAAAUAOQBuDAAAAQAXAAAA.Ashbahn:BAABLgAECn8rAAMJAAkJPQqWIwB3AQloDAAACAAFAGkMAAAGACQAawwAAAYAFgBqDAAABgBFAGwMAAAFABUAbQwAAAMAGwDqDAAABgAhAG4MAAACAA4AbwwAAAEABQAJAAkJPQqWIwB3AQloDAAAAwAFAGkMAAAEACQAawwAAAQAFgBqDAAABgBFAGwMAAAFABUAbQwAAAMAGwDqDAAABAAhAG4MAAABAA4AbwwAAAEABQAGAAUJlBPaegABAQVoDAAABQBFAGkMAAACADkAawwAAAIAJQDqDAAAAgBDAG4MAAABABMAAAA=.Ashes:BAAALgAECgQJCQABLgAECgkJKwAJAD0KAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJBwAAAA==.',
Au='Auroranova:BAABLgAECn8dAAMGAAgJMgiCYAA4AQhoDAAABQAWAGkMAAAFABoAawwAAAQAEABqDAAABQAgAGwMAAAEABIAbQwAAAEAIQDqDAAABAAYAG4MAAABAAUABgAICTIIgmAAOAEIaAwAAAUAFgBpDAAABAAaAGsMAAAEABAAagwAAAUAIABsDAAABAASAG0MAAABACEA6gwAAAQAGABuDAAAAQAFAAkAAQnEA8NxACIAAWkMAAABAAkAAAA=.',
Ax='Axél:BAAALgAECgQJBwAAAA==.',
Be='Berringer:BAAALgAECgQJCgAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCAAAAA==.',
Br='Braei:BAAALgAECgMJAwAAAA==.Brilleleante:BAAALgADCgYJCwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAYJEQACAGQhAA==.Canimai:BAABLgAECn8lAAMKAAgJHhGyHwBzAQhoDAAABgA0AGkMAAAGADAAawwAAAYALwBqDAAABAAzAGwMAAAEAC0AbQwAAAMAIQDqDAAABQAjAG4MAAADACwACgAICWsOsh8AcwEIaAwAAAYANABpDAAABgAwAGsMAAAGAC8AagwAAAMAGwBsDAAAAgAXAG0MAAADACEA6gwAAAUAIwBuDAAAAgASAAsAAwmnEXQrAG4AA2oMAAABADMAbAwAAAIALQBuDAAAAQAsAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJCgAMAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVWlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAEAAYJnwVWlgDwAAZoDAAABQAPAGkMAAAEAA4AawwAAAUADgBqDAAAAgARAGwMAAACAAsA6gwAAAMADwAAAA==.Crisspy:BAACLgAFFH8HAAMNAAMJfwG4IACoAANoDAAAAwACAGkMAAADAAIA6gwAAAEABgANAAMJfwG4IACoAANoDAAAAQACAGkMAAACAAIA6gwAAAEABgAOAAIJtwYDHACIAAJoDAAAAgALAGkMAAABABYALgAECn8lAAMNAAgJWhAbHAB6AQANAAgJWhAbHAB6AQAOAAEJJAecgwA0AAAAAA==.',
Cu='Cubes:BAACLgAFFH8WAAMPAAYJcR95AAAjAgZoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAGwMAAABAAsA6gwAAAYAYwAPAAUJMiZ5AAAjAgVoDAAABQBiAGkMAAADAF8AawwAAAQAYQBqDAAAAwBkAOoMAAAGAGMAEAABCeUSICYAUAABbAwAAAEAMAAuAAQKfy0ABA8ACQm1JRYBALgDAA8ACQm1JRYBALgDABEABgnNGJktAKMBABAAAwk/DpQ+AJoAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJAwAAAA==.',
De='Deathcrocker:BAECLgAFFH8aAAISAAYJoCVKAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABgBhAGwMAAADAF8A6gwAAAUAYwASAAYJoCVKAACGAgZoDAAABQBfAGkMAAADAGAAawwAAAQAXgBqDAAABgBhAGwMAAADAF8A6gwAAAUAYwAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAEuAAUUBwkPABEArSIA.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIGAAgJBBcnTQD7AQhoDAAAAwBKAGkMAAADAEwAawwAAAMASQBqDAAAAwAgAGwMAAADAEUAbQwAAAEAIgDqDAAABQBAAG4MAAABABMABgAICQQXJ00A+wEIaAwAAAMASgBpDAAAAwBMAGsMAAADAEkAagwAAAMAIABsDAAAAwBFAG0MAAABACIA6gwAAAUAQABuDAAAAQATAAEuAAUUBAkSAAYA3hgA.',
Do='Dogs:BAACLgAFFH8LAAIKAAQJxBraCwBMAQRoDAAAAwBKAGkMAAADAFMAawwAAAIAGADqDAAAAwBbAAoABAnEGtoLAEwBBGgMAAADAEoAaQwAAAMAUwBrDAAAAgAYAOoMAAADAFsALgAECn8bAAIKAAgJ6xvXDQDmAgAKAAgJ6xvXDQDmAgABLgAFFAcJFQAGAOcbAA==.Domar:BAAALgAECgQJBwAAAA==.Doomslayer:BAABLgAECn8kAAMTAAkJ7BoJIQAOAgloDAAABwBgAGkMAAAFAFcAawwAAAUARQBqDAAABABUAGwMAAADAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQATAAkJ7BoJIQAOAgloDAAABgBgAGkMAAAEAFcAawwAAAQARQBqDAAAAwBUAGwMAAACAD0AbQwAAAEAJwDqDAAABwBKAG4MAAADAFsAbwwAAAEAHQASAAUJgAL1MwCgAAVoDAAAAQADAGkMAAABAAUAawwAAAEACABqDAAAAQAIAGwMAAABAAgAAAA=.Doraei:BAAALgAECgYJDAAAAA==.Dothippo:BAABLgAECn8qAAMUAAcJthuXAwDvAQdoDAAACABUAGkMAAAHAEwAawwAAAcASABqDAAABgApAGwMAAAFAFUAbQwAAAIAHADqDAAABwBOABQABwm2G5cDAO8BB2gMAAAIAFQAaQwAAAYATABrDAAABwBIAGoMAAAGACkAbAwAAAUAVQBtDAAAAgAcAOoMAAAHAE4AFQABCRYEcigBKQABaQwAAAEACgAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8gAAIGAAkJSRf1JgDvAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAGAAkJSRf1JgDvAQloDAAABgBRAGkMAAAEAFUAawwAAAQAQABqDAAAAwAyAGwMAAACABAAbQwAAAIANgDqDAAABQBKAG4MAAAEADEAbwwAAAIAMgAAAA==.',
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
Fr='Freezing:BAAALgAECgEJAgAAAA==.Frieren:BAACLgAFFH8SAAIXAAcJ5xqECgDLAQdoDAAAAgBUAGkMAAACAGEAawwAAAMAQQBqDAAAAwAzAGwMAAACAEMAbQwAAAEABADqDAAABQBdABcABwnnGoQKAMsBB2gMAAACAFQAaQwAAAIAYQBrDAAAAwBBAGoMAAADADMAbAwAAAIAQwBtDAAAAQAEAOoMAAAFAF0ALgAECn8hAAQXAAkJfSJeDQBaAwAXAAkJfSJeDQBaAwAYAAEJ0yAHDQBZAAAZAAEJGw8dGgBHAAAAAA==.Froslass:BAABLgAECn8VAAITAAgJSRooKADpAQhoDAAABABeAGkMAAADAFkAawwAAAMASgBqDAAAAwAzAGwMAAADADQAbQwAAAEAJgDqDAAAAwBRAG4MAAABACkAEwAICUkaKCgA6QEIaAwAAAQAXgBpDAAAAwBZAGsMAAADAEoAagwAAAMAMwBsDAAAAwA0AG0MAAABACYA6gwAAAMAUQBuDAAAAQApAAAA.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgQJBQAAAA==.',
Gl='Gloryhammer:BAABLgAECn8jAAQHAAgJARuMCABPAghoDAAABgBgAGkMAAAGAF4AawwAAAYAVgBqDAAABABfAGwMAAAEAEUAbQwAAAIAIQDqDAAABgBPAG4MAAABABYABwAICQEbjAgATwIIaAwAAAUAYABpDAAABQBeAGsMAAAFAFYAagwAAAMAXwBsDAAAAwBFAG0MAAACACEA6gwAAAUATwBuDAAAAQAWAAkABQkoBcVrAMsABWkMAAABAAkAawwAAAEAHgBqDAAAAQAAAGwMAAABABQA6gwAAAEABAAGAAEJaxmjQwEzAAFoDAAAAQBBAAAA.',
Go='Gobbs:BAABLgAECn8YAAMaAAYJIBKJCwBzAQZoDAAABQAwAGkMAAAFADkAawwAAAYAOQBqDAAAAwAgAGwMAAACACAA6gwAAAMAJAAaAAYJ4g+JCwBzAQZoDAAABAAwAGkMAAAEADkAawwAAAUAJgBqDAAAAgAZAGwMAAABABsA6gwAAAIAHwAbAAYJEBFDGgA3AQZoDAAAAQAqAGkMAAABADEAawwAAAEAOQBqDAAAAQAgAGwMAAABACAA6gwAAAEAJAABLgAECggJHgABAJAbAA==.',
Gr='Gripmedaddy:BAAALgADCgcJBwAAAA==.',
Ha='Haldrian:BAAALgAECgMJAwAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgYJEwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMcAAQJyRinCgC6AARoDAAABABXAGkMAAADAE8AawwAAAEAOQDqDAAAAQAdABwAAwkwHacKALoAA2gMAAADAFcAaQwAAAIATwBrDAAAAQA5AB0AAwlDCtQdALcAA2gMAAABADAAaQwAAAEAAADqDAAAAQAdAC4ABAp/FwADHAAICTsh0gsAkwIAHAAICTsh0gsAkwIAHQABCYQPM0sAMQAAAAA=.Hop:BAABLgAECn8pAAIeAAkJhRtyAgCRAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAeAAkJhRtyAgCRAgloDAAABgBVAGkMAAAGAFEAawwAAAYASwBqDAAABQBGAGwMAAAEAFMAbQwAAAMAIgDqDAAABgBJAG4MAAAEAD4AbwwAAAEARAAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAcAMkYAA==.Hotamnk:BAAALgAECgMJAwABLgAFFAQJCQAcAMkYAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.Ironborn:BAAALgAECgQJBwAAAA==.',
Iv='Ivakor:BAAALgAECgUJCgAAAA==.Ivyy:BAACLgAFFH8MAAIfAAMJACS/EAA4AQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAfAAMJACS/EAA4AQNoDAAABABWAGkMAAAEAFwA6gwAAAQAYQAuAAQKfxcAAh8ACAkSIrYNAMACAB8ACAkSIrYNAMACAAAA.',
Ja='Jackswagz:BAABLgAECn8hAAMOAAkJgROIHwDHAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAGAD8AbQwAAAMAJADqDAAABQA3AG4MAAACAB8AbwwAAAEACQAOAAkJgROIHwDHAQloDAAABABbAGkMAAAEADUAawwAAAQAPwBqDAAABAArAGwMAAAFAD8AbQwAAAIAJADqDAAABAA3AG4MAAACAB8AbwwAAAEACQANAAMJCQeQTACBAANsDAAAAQAaAG0MAAABABMA6gwAAAEACAAAAA==.Jaszuny:BAABLgAECn8gAAIDAAgJVRQABgCvAQhoDAAABgArAGkMAAAFAD4AawwAAAUATgBqDAAABQA8AGwMAAADAC0AbQwAAAEAEwDqDAAABQA+AG4MAAACADQAAwAICVUUAAYArwEIaAwAAAYAKwBpDAAABQA+AGsMAAAFAE4AagwAAAUAPABsDAAAAwAtAG0MAAABABMA6gwAAAUAPgBuDAAAAgA0AAAA.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAgABLgAECgcJDAAMAAAAAA==.Kasho:BAAALgAECgEJAQAAAA==.Katsumotosan:BAAALgADCggJDAAAAA==.',
Ke='Kev:BAABLgAECn8qAAQXAAcJ6SS2FQB2AgdoDAAACABiAGkMAAAHAF4AawwAAAcAYABqDAAABgBcAGwMAAAFAGAAbQwAAAIAUQDqDAAABwBjABcABwnpJLYVAHYCB2gMAAAIAGIAaQwAAAcAXgBrDAAABwBgAGoMAAAFAFwAbAwAAAQAYABtDAAAAgBRAOoMAAAGAGMAGQACCTIk2w8AxAACbAwAAAEAWwDqDAAAAQBdABgAAQkAADwSABcAAWoMAAABAAUAAAA=.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn8hAAITAAcJahqoNQCuAQdoDAAABwBUAGkMAAAFAEEAawwAAAUAMgBqDAAABQAxAGwMAAAEAEsAbQwAAAIAQgDqDAAABQA/ABMABwlqGqg1AK4BB2gMAAAHAFQAaQwAAAUAQQBrDAAABQAyAGoMAAAFADEAbAwAAAQASwBtDAAAAgBCAOoMAAAFAD8AAAA=.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8SAAIGAAQJ3hg2CgBbAQRoDAAABgBUAGkMAAAFAEgAawwAAAQAQwDqDAAAAwAeAAYABAneGDYKAFsBBGgMAAAGAFQAaQwAAAUASABrDAAABABDAOoMAAADAB4ALgAECn8dAAIGAAgJNB3ZMQBbAgAGAAgJNB3ZMQBbAgAAAA==.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAECgkJGAAIACsIAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8ZAAMTAAcJeQ1GjwBiAQdoDAAABQAuAGkMAAADACYAawwAAAQAIwBqDAAABAAtAGwMAAACAB0AbQwAAAIABwDqDAAABQAyABMABwk8DUaPAGIBB2gMAAAFAC4AaQwAAAMAJgBrDAAAAgAfAGoMAAAEAC0AbAwAAAIAHQBtDAAAAgAHAOoMAAAFADIAEgABCbENukYALQABawwAAAIAIwAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgEJAQAAAA==.Mistake:BAAALgAECgYJEAAAAA==.',
Mo='Mockra:BAAALgADCgEJAQABLgAECgIJAgAMAAAAAA==.Monkcrocker:BAECLgAFFH8PAAIRAAcJrSIOAADZAgdoDAAAAgBYAGkMAAAEAF8AawwAAAIAWQBsDAAAAQBhAG0MAAACAEoA6gwAAAMAWwBuDAAAAQBUABEABwmtIg4AANkCB2gMAAACAFgAaQwAAAQAXwBrDAAAAgBZAGwMAAABAGEAbQwAAAIASgDqDAAAAwBbAG4MAAABAFQALgAECn8VAAIRAAcJ8SXADQC3AgARAAcJ8SXADQC3AgAAAA==.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgMJAwAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCggJFQAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgQJBAABLgAFFAMJBwASACoHAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8JAAMGAAIJRxsdQgCzAAJoDAAABQA5AOoMAAAEAFIABgACCUcbHUIAswACaAwAAAQAOQDqDAAABABSAAkAAQlpCIQwAD4AAWgMAAABABUALgAECn8wAAMGAAkJiiD4CADOAgAGAAkJiiD4CADOAgAJAAMJthY3PADaAAAAAA==.',
Og='Ogganborn:BAABLgAECn8UAAIBAAUJJhtBRgA8AQVoDAAABABOAGkMAAAGAEsAawwAAAUALQBsDAAAAQA7AOoMAAAEAFcAAQAFCSYbQUYAPAEFaAwAAAQATgBpDAAABgBLAGsMAAAFAC0AbAwAAAEAOwDqDAAABABXAAAA.',
On='Oneira:BAAALgADCggJDQAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIGAAcJ2RKtTQBoAQdoDAAABQA6AGkMAAAFAEoAawwAAAUAKwBqDAAABAA8AGwMAAACACMAbQwAAAIAEQDqDAAABAA8AAYABwnZEq1NAGgBB2gMAAAFADoAaQwAAAUASgBrDAAABQArAGoMAAAEADwAbAwAAAIAIwBtDAAAAgARAOoMAAAEADwAAAA=.',
Pr='Priestigory:BAABLgAECn8tAAMRAAkJZhweBQCbAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABwBGAGwMAAAGAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAARAAkJZhweBQCbAgloDAAACABUAGkMAAAGAEwAawwAAAYAVQBqDAAABgBGAGwMAAAFAE0AbQwAAAMAPQDqDAAABgBYAG4MAAACAD8AbwwAAAEALAAPAAIJIRNiYwCBAAJqDAAAAQA7AGwMAAABADAAAAA=.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAAALgAECgUJBwAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAAALgAECgUJEAAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8vAAQgAAgJXiEHCwCkAghoDAAACABcAGkMAAAIAFcAawwAAAUAVABqDAAABgBgAGwMAAAHAGMAbQwAAAMAVwDqDAAACABgAG4MAAACACcAIAAICV4hBwsApAIIaAwAAAcAXABpDAAABgBXAGsMAAAEAFQAagwAAAYAYABsDAAABwBjAG0MAAADAFcA6gwAAAgAYABuDAAAAgAnAB4AAwlXFfMcAIoAA2gMAAABAC0AaQwAAAEAPQBrDAAAAQA4AB8AAQkoAvyOAB4AAWkMAAABAAUAAAA=.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8NAAILAAcJZRkPAQD/AQdoDAAAAgBOAGkMAAACAF4AawwAAAIALwBqDAAAAQAfAG0MAAABACwA6gwAAAQATQBuDAAAAQAwAAsABwllGQ8BAP8BB2gMAAACAE4AaQwAAAIAXgBrDAAAAgAvAGoMAAABAB8AbQwAAAEALADqDAAABABNAG4MAAABADAALgAECn8cAAILAAgJmyW0AQBoAwALAAgJmyW0AQBoAwAAAA==.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8VAAIXAAYJNA7qdwAoAQZoDAAABAAuAGkMAAAEABoAawwAAAQAKABqDAAAAgAQAGwMAAADABYA6gwAAAQALQAXAAYJNA7qdwAoAQZoDAAABAAuAGkMAAAEABoAawwAAAQAKABqDAAAAgAQAGwMAAADABYA6gwAAAQALQAAAA==.',
Sa='Saelki:BAAALgADCgcJBwAAAA==.',
Se='Sephiran:BAABLgAECn8oAAMhAAgJ7h3tBwBaAghoDAAABgBYAGkMAAAGAFAAawwAAAYARwBqDAAABQBTAGwMAAAFAEoAbQwAAAQAOQDqDAAABQBYAG4MAAADAEsAIQAICe4d7QcAWgIIaAwAAAQAWABpDAAAAwBQAGsMAAADAEcAagwAAAIAUwBsDAAAAgBKAG0MAAACADkA6gwAAAIAWABuDAAAAgBLAB0ACAmOF3UNAAcCCGgMAAACADoAaQwAAAMAPgBrDAAAAwA/AGoMAAADADkAbAwAAAMASwBtDAAAAgAyAOoMAAADADoAbgwAAAEANgAAAA==.',
Sh='Shagra:BAAALgAECgUJBQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAAALgAECgUJEAAAAA==.Shoepert:BAABLgAECn8qAAIKAAkJ7CSyAABWAwloDAAACABhAGkMAAAGAGMAawwAAAYAWgBqDAAABgBhAGwMAAAFAF0AbQwAAAMAXADqDAAABQBiAG4MAAACAFcAbwwAAAEAYAAKAAkJ7CSyAABWAwloDAAACABhAGkMAAAGAGMAawwAAAYAWgBqDAAABgBhAGwMAAAFAF0AbQwAAAMAXADqDAAABQBiAG4MAAACAFcAbwwAAAEAYAAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAMAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgMJAwAAAA==.',
Te='Tempus:BAACLgAFFH8HAAIJAAMJjx4BFgANAQNoDAAAAwBZAGkMAAADADkA6gwAAAEAVwAJAAMJjx4BFgANAQNoDAAAAwBZAGkMAAADADkA6gwAAAEAVwAuAAQKfxwAAwkACAkOG18kAAACAAkACAkOG18kAAACAAYAAQnJAthOAS0AAAAA.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgYJDwAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJAgAAAA==.',
Ty='Tyrgrim:BAAALgAECgMJAwAAAA==.',
Ul='Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgAMAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAABLgAECn8ZAAMFAAgJHxQ2DgCrAQhoDAAABQBDAGkMAAAEAEEAawwAAAQANgBqDAAAAwAmAGwMAAACAC4AbQwAAAEAKgDqDAAABQA6AG4MAAABABoABQAICR8UNg4AqwEIaAwAAAQAQwBpDAAABABBAGsMAAAEADYAagwAAAMAJgBsDAAAAgAuAG0MAAABACoA6gwAAAUAOgBuDAAAAQAaAAQAAQnnATHZABkAAWgMAAABAAQAAAA=.',
Va='Valalexis:BAAALgADCgcJBwAAAA==.',
Ve='Velawynn:BAACLgAFFH8ZAAIcAAYJix/cAAAkAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAYAWwAcAAYJix/cAAAkAgZoDAAABgBjAGkMAAAFAEwAawwAAAQARQBqDAAAAwBHAGwMAAABAEsA6gwAAAYAWwAuAAQKfy4AAxwACQm6HhwFAP8CABwACQm6HhwFAP8CACEABAleDoQ1AMQAAAAA.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAISAAUJxRMZBABvAQVpDAAAAQA1AGsMAAABABYAagwAAAIAOABsDAAAAQAlAOoMAAACAFkAEgAFCcUTGQQAbwEFaQwAAAEANQBrDAAAAQAWAGoMAAACADgAbAwAAAEAJQDqDAAAAgBZAC4ABAp/FAADEgAICdwdNBIA6AEAEgAICfwcNBIA6AEAEwAGCf0aM34AhwEAAAA=.',
Vh='Vhenir:BAAALgADCgUJCwAAAA==.',
Vi='Vixa:BAAALgAECgMJAwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAECgUJBQAAAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJCwAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMLAAcJSRxADACoAQdoDAAABgBQAGkMAAAFAFAAawwAAAUAUQBqDAAABQBPAGwMAAADAE0AbQwAAAEAKQDqDAAABABJAAoABwllGeIXAK4BB2gMAAAFAEcAaQwAAAQAUABrDAAABABRAGoMAAAEAE8AbAwAAAIASQBtDAAAAQApAOoMAAADACkACwAGCe4dQAwAqAEGaAwAAAEAUABpDAAAAQBIAGsMAAABAE8AagwAAAEARwBsDAAAAQBNAOoMAAABAEkAAS4ABAoICSgAIQDuHQA=.Zinjari:BAAALgADCgEJAQAAAA==.',
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
