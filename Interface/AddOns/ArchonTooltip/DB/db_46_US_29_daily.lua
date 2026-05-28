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

local lookup = {'DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Paladin-Holy','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='daily',zone=46,date='2026-05-27',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgAECgMJBAAAAA==.',
An='Andeys:BAAALgAECggJDwAAAA==.Angelius:BAAALgAFFAIJAgABLgAECgkJLgABAJgfAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgACAJkTAA==.',
Ba='Baggigy:BAACLgAFFH8HAAMDAAMJehHJDQDkAANoDAAAAgAuAGkMAAABACkA6gwAAAQALgADAAMJehHJDQDkAANoDAAAAQAuAGkMAAABACkA6gwAAAIALgABAAIJUwZfxgB+AAJoDAAAAQAXAOoMAAACAAgALgAECn8aAAQBAAYJCR28iQA2AQABAAYJ1By8iQA2AQAEAAQJQAQ2QABrAAADAAEJjBjXKABJAAAAAA==.Balance:BAABLgAFFH8IAAMFAAMJcA9oNQDGAANoDAAAAwAyAGkMAAABACEA6gwAAAQAIgAFAAMJcA9oNQDGAANoDAAAAgAyAGkMAAABACEA6gwAAAQAIgAGAAEJjgfjLQAtAAFoDAAAAQATAAAA.',
Be='Bentpanda:BAABLgAECn8WAAIHAAgJ5BWTGQC+AQhoDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAABABEABwAICeQVkxkAvgEIaAwAAAQAXQBpDAAABABMAGsMAAAEADoAagwAAAIAOQBsDAAAAgAdAG0MAAACAE8A6gwAAAMAJABuDAAAAQARAAAA.',
Bh='Bhain:BAABLgAFFH8NAAIIAAQJfxZuKQA9AQRoDAAABQBEAGkMAAAEAE0AawwAAAEAMwDqDAAAAwAhAAgABAl/Fm4pAD0BBGgMAAAFAEQAaQwAAAQATQBrDAAAAQAzAOoMAAADACEAAAA=.',
Bi='Bigcocko:BAACLgAFFH8eAAIFAAcJfRxEBACKAgdoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYAbQwAAAEANgDqDAAACABcAAUABwl9HEQEAIoCB2gMAAAHAFUAaQwAAAYAUwBrDAAABABaAGoMAAADAEEAbAwAAAEAJgBtDAAAAQA2AOoMAAAIAFwALgAECn8tAAIFAAkJhiWJAgByAwAFAAkJhiWJAgByAwAAAA==.Bigwheels:BAAALgAECgMJAwAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAFFAMJBwADAHoRAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAABLgAECn8YAAIJAAgJZRWOEwAbAghoDAAABABAAGkMAAAFAEcAawwAAAUAOgBqDAAAAQBCAGwMAAABABEAbQwAAAEAGQDqDAAABgBAAG4MAAABAEYACQAICWUVjhMAGwIIaAwAAAQAQABpDAAABQBHAGsMAAAFADoAagwAAAEAQgBsDAAAAQARAG0MAAABABkA6gwAAAYAQABuDAAAAQBGAAAA.',
Bu='Buffallo:BAABLgAECn8WAAIKAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAKAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAAAA==.',
Ca='Camouflage:BAABLgAECn9AAAIHAAkJBCXCAQAqAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAGAFgAbwwAAAQAWAAHAAkJBCXCAQAqAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAGAFgAbwwAAAQAWAAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAIAAcVAA==.Chilyn:BAAALgAECgUJCgAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAILAAYJEw6CkgDVAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwALAAYJEw6CkgDVAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAAAA==.Corrupthell:BAAALgAECgYJDwAAAA==.Cowi:BAAALgAECgYJDAABLgAECggJHwAMAOsUAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAIMAAgJShopXAAlAghoDAAABABaAGkMAAAEAEcAawwAAAMAPQBqDAAABABRAGwMAAACAEsAbQwAAAEAUQDqDAAABABCAG4MAAACABgADAAICUoaKVwAJQIIaAwAAAQAWgBpDAAABABHAGsMAAADAD0AagwAAAQAUQBsDAAAAgBLAG0MAAABAFEA6gwAAAQAQgBuDAAAAgAYAAAA.Daswassap:BAAALgAECgYJCgAAAA==.',
De='Def:BAAALgAECgEJAwAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQCAAkJmRMYMACVAQloDAAABwBCAGkMAAAFAFAAawwAAAUATABqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AG4MAAACAAsAbwwAAAEAMgACAAcJexMYMACVAQdoDAAABAA8AGkMAAAEAEAAawwAAAQAOQBqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AA0ABQk6Fvo7ACwBBWgMAAACAEIAaQwAAAEAUABrDAAAAQBMAG4MAAABAAsAbwwAAAEAMgAOAAIJrBzDegBfAAJoDAAAAQA9AG4MAAABAFUAAAA=.Driver:BAECLgAFFH8MAAMPAAQJPg3lRgAeAQRoDAAABAAWAGkMAAACAB4AbAwAAAEAKQDqDAAABQApAA8ABAnQDOVGAB4BBGgMAAADABEAaQwAAAIAHgBsDAAAAQApAOoMAAAFACkAEAABCZ0I9xsATAABaAwAAAEAFgAuAAQKfzUAAw8ACAniHvMZALkCAA8ACAniHvMZALkCABEABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAAALgAECgkJEQAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAcJEgALAD4fAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJmCT2AgAXAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgACAAkJmCT2AgAXAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frahmunda:BAAALgAECgEJAQAAAA==.Frosty:BAABLgAECn8UAAIMAAcJzw3UqACIAQdoDAAABAArAGkMAAADACsAawwAAAMAMQBqDAAAAwAgAGwMAAADABoAbQwAAAEABADqDAAAAwAqAAwABwnPDdSoAIgBB2gMAAAEACsAaQwAAAMAKwBrDAAAAwAxAGoMAAADACAAbAwAAAMAGgBtDAAAAQAEAOoMAAADACoAAAA=.Frybeam:BAAALgAECgIJAwAAAA==.',
Gi='Gilfoyle:BAAALgAECgEJBAAAAA==.Giovahni:BAACLgAFFH8MAAILAAYJ6BFKHwB7AQZoDAAAAwBJAGkMAAADACoAawwAAAEAEwBqDAAAAQAbAGwMAAABACMA6gwAAAMAOQALAAYJ6BFKHwB7AQZoDAAAAwBJAGkMAAADACoAawwAAAEAEwBqDAAAAQAbAGwMAAABACMA6gwAAAMAOQAuAAQKfzEAAgsACAnXHz4bAFgCAAsACAnXHz4bAFgCAAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIMAAcJsAVXyABYAQdoDAAABAASAGkMAAAEABMAawwAAAQAEABqDAAAAgAUAGwMAAACABAAbQwAAAEABQDqDAAAAwAKAAwABwmwBVfIAFgBB2gMAAAEABIAaQwAAAQAEwBrDAAABAAQAGoMAAACABQAbAwAAAIAEABtDAAAAQAFAOoMAAADAAoAAAA=.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAISAAgJ3hPeMgBkAQhoDAAABQAwAGkMAAAEAD8AawwAAAQAQQBqDAAABAAUAGwMAAADADMAbQwAAAEAFwDqDAAABQAxAG4MAAACADYAEgAICd4T3jIAZAEIaAwAAAUAMABpDAAABAA/AGsMAAAEAEEAagwAAAQAFABsDAAAAwAzAG0MAAABABcA6gwAAAUAMQBuDAAAAgA2AAAA.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAABLgAFFH8IAAITAAMJwRcpGADsAANoDAAAAwA0AGkMAAACAFEA6gwAAAMAMAATAAMJwRcpGADsAANoDAAAAwA0AGkMAAACAFEA6gwAAAMAMAAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJAwAAAA==.Jessiescool:BAABLgAECn8aAAIIAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAIAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIGAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAGAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAACLgAFFH8GAAIIAAMJKgzzWQDSAANoDAAAAwAiAGkMAAACADQA6gwAAAEABgAIAAMJKgzzWQDSAANoDAAAAwAiAGkMAAACADQA6gwAAAEABgAuAAQKfxkAAggABwl7JA8hAGkCAAgABwl7JA8hAGkCAAAA.',
Ka='Kalvin:BAABLgAECn8cAAIUAAgJiA5HIAByAQhoDAAABAAlAGkMAAADADMAawwAAAMAGABqDAAAAgACAGwMAAACACgAbQwAAAIABgDqDAAACgAoAG4MAAACADoAFAAICYgORyAAcgEIaAwAAAQAJQBpDAAAAwAzAGsMAAADABgAagwAAAIAAgBsDAAAAgAoAG0MAAACAAYA6gwAAAoAKABuDAAAAgA6AAAA.Kanari:BAABLgAECn8ZAAQVAAgJHBGiMwAdAQhoDAAABAAzAGkMAAAEACgAawwAAAQAMwBqDAAAAwA7AGwMAAAEADEAbQwAAAIADgDqDAAAAwA+AG4MAAABABMAFQAGCY4UojMAHQEGaAwAAAQAMwBpDAAAAgAoAGsMAAADADMAagwAAAIAOwBsDAAAAwAxAOoMAAACAD4ACQAFCQEGS0AA1AAFaQwAAAEADQBsDAAAAQAVAG0MAAACAA4A6gwAAAEABwBuDAAAAQATABYAAwnFAOlrABkAA2kMAAABAAEAawwAAAEAAgBqDAAAAQADAAAA.',
Ke='Kelak:BAAALgADCgEJAQAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgEJAwAAAA==.',
La='Lagoles:BAACLgAFFH8FAAIHAAMJIxHuHwCkAANqDAAAAQAhAGwMAAABAAwA6gwAAAMASwAHAAMJIxHuHwCkAANqDAAAAQAhAGwMAAABAAwA6gwAAAMASwAuAAQKfzYAAwcACQnPItsDAOYCAAcACQkoItsDAOYCABcACAl9H5oTAJgCAAAA.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJEAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJQAAHAAQlAA==.Leoben:BAAALgAECgEJBAAAAA==.',
Li='Liltracey:BAAALgAFFAIJAwABLgAFFAMJCAAFAHAPAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAGADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIFAAMJRRKcMgDQAANoDAAABQApAGkMAAAEABcA6gwAAAcASwAFAAMJRRKcMgDQAANoDAAABQApAGkMAAAEABcA6gwAAAcASwAuAAQKfzEAAwUACQk5IEoJAA8DAAUACQk5IEoJAA8DABgAAglmDk1sAG8AAAAA.Milo:BAAALgAFFAMJBAAAAA==.',
Mk='Mk:BAEBLgAECn87AAMNAAgJayMfBgAfAwhoDAAACgBjAGkMAAAJAGMAawwAAAkAYQBqDAAACQBhAGwMAAAHAFwAbQwAAAMAMADqDAAABwBiAG4MAAAFAGIADQAICWsjHwYAHwMIaAwAAAkAYwBpDAAACABjAGsMAAAIAGEAagwAAAgAYQBsDAAABgBcAG0MAAADADAA6gwAAAcAYgBuDAAABQBiAAIABQmmCUhQAKsABWgMAAABABUAaQwAAAEAHABrDAAAAQAeAGoMAAABAAwAbAwAAAEAEQAAAA==.',
Mo='Monzo:BAABLgAECn8jAAMBAAgJ2iEEGQDmAghoDAAABwBbAGkMAAAHAF4AawwAAAYAXwBqDAAAAwBbAGwMAAADAE0AbQwAAAIAQADqDAAABgBhAG4MAAABAFQAAQAICdohBBkA5gIIaAwAAAYAWwBpDAAABgBeAGsMAAAGAF8AagwAAAMAWwBsDAAAAwBNAG0MAAACAEAA6gwAAAYAYQBuDAAAAQBUAAQAAgnUD5I9AFwAAmgMAAABACoAaQwAAAEAJgABLgAFFAMJCAAFAHAPAA==.Morvayne:BAABLgAECn8vAAIMAAkJSRxdKgBVAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwAMAAkJSRxdKgBVAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwABLgAFFAMJBQAHACMRAA==.',
My='Myneemo:BAAALgAECggJCQAAAA==.Myro:BAABLgAECn8WAAIIAAgJrQeKlQAqAQhoDAAAAgAQAGkMAAADABoAawwAAAUADwBqDAAAAgAcAGwMAAADABMAbQwAAAEADwDqDAAABQAcAG4MAAABAA4ACAAICa0HipUAKgEIaAwAAAIAEABpDAAAAwAaAGsMAAAFAA8AagwAAAIAHABsDAAAAwATAG0MAAABAA8A6gwAAAUAHABuDAAAAQAOAAAA.',
No='Nomoneydown:BAAALgAECgEJAwAAAA==.Nosam:BAABLgAECn8bAAIPAAcJKxEAbwBNAQdoDAAACQBBAGkMAAAGAC4AawwAAAUAJABqDAAAAwBAAGwMAAABACQAbQwAAAEAJQDqDAAAAgApAA8ABwkrEQBvAE0BB2gMAAAJAEEAaQwAAAYALgBrDAAABQAkAGoMAAADAEAAbAwAAAEAJABtDAAAAQAlAOoMAAACACkAAAA=.',
Nt='Nthegreat:BAAALgAECgYJBgAAAA==.',
Nw='Nwf:BAABLgAECn8ZAAISAAcJLRiTMABwAQdoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAABAA+AGwMAAAEACMA6gwAAAQASABuDAAAAQAgABIABwktGJMwAHABB2gMAAAEAFMAaQwAAAQARABrDAAABABPAGoMAAAEAD4AbAwAAAQAIwDqDAAABABIAG4MAAABACAAAAA=.',
['Nè']='Nèbula:BAABLgAECn8WAAMZAAgJHhUEHwDuAQhoDAAABAA/AGkMAAAEAEsAawwAAAQAPQBqDAAAAgAGAGwMAAADACIAbQwAAAEAHwDqDAAAAwBbAG4MAAABAEQAGQAHCTcWBB8A7gEHaAwAAAIAPwBpDAAAAgBLAGsMAAACAD0AagwAAAEABgBtDAAAAQAfAOoMAAABAFsAbgwAAAEARAAaAAYJ6gzmIwDQAAZoDAAAAgAzAGkMAAACACMAawwAAAIAEwBqDAAAAQAxAGwMAAADACoA6gwAAAIAEQAAAA==.',
Or='Ornatas:BAACLgAFFH8MAAIbAAQJMiG/DwBpAQRoDAAABQBaAGkMAAADAFYAawwAAAEATgDqDAAAAwBUABsABAkyIb8PAGkBBGgMAAAFAFoAaQwAAAMAVgBrDAAAAQBOAOoMAAADAFQALgAECn8YAAIbAAgJtByWFQBvAgAbAAgJtByWFQBvAgAAAA==.',
Pa='Pandamonium:BAABLgAECn8dAAQOAAgJPxT8KwBWAQhoDAAABgAvAGkMAAAFADgAawwAAAYAOgBqDAAAAwBRAGwMAAABACIAbQwAAAEALQDqDAAABgA9AG4MAAABABwADgAICT8U/CsAVgEIaAwAAAUALwBpDAAABAA4AGsMAAAEADoAagwAAAIAUQBsDAAAAQAiAG0MAAABAC0A6gwAAAQAPQBuDAAAAQAcAAIABAn4A+VkAGgABGgMAAABAAQAaQwAAAEADABrDAAAAgAOAGoMAAABAA0ADQABCTgJn5cAJwAB6gwAAAIAFwAAAA==.',
Pe='Perdyblues:BAAALgAECggJEAAAAA==.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgQJBwAAAA==.',
Qi='Qiana:BAAALgAECgcJEQABLgAECgkJIQAVAL4bAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAINAAgJCQwtPADvAAhoDAAABgA8AGkMAAAFAC4AawwAAAIAEgBqDAAABAAhAGwMAAADACUAbQwAAAEABwDqDAAABQAZAG4MAAABABMADQAICQkMLTwA7wAIaAwAAAYAPABpDAAABQAuAGsMAAACABIAagwAAAQAIQBsDAAAAwAlAG0MAAABAAcA6gwAAAUAGQBuDAAAAQATAAAA.Quinoaffle:BAAALgAECgEJAQAAAA==.',
Ra='Rainootra:BAAALgAECgYJBgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAABLgAECn8eAAMMAAkJKhC7TgDTAQloDAAAAgBEAGkMAAADACgAawwAAAQAOQBqDAAABgBQAGwMAAAEAEQAbQwAAAIAGgDqDAAABgAwAG4MAAABAAEAbwwAAAIAFAAMAAkJ4w+7TgDTAQloDAAAAQBEAGkMAAACACgAawwAAAMAOQBqDAAABAA8AGwMAAACAEQAbQwAAAEAGgDqDAAAAwAqAG4MAAABAAEAbwwAAAIAFAAcAAcJGQmaCwCaAAdoDAAAAQAMAGkMAAABAAYAawwAAAEAAwBqDAAAAgBQAGwMAAACAEAAbQwAAAEABADqDAAAAwAwAAAA.',
Sc='Scylla:BAACLgAFFH8SAAIdAAcJvx0uAQBCAgdoDAAAAQA2AGkMAAAEAGEAawwAAAMAWgBqDAAAAgBEAGwMAAABAFoAbQwAAAEANwDqDAAABgBMAB0ABwm/HS4BAEICB2gMAAABADYAaQwAAAQAYQBrDAAAAwBaAGoMAAACAEQAbAwAAAEAWgBtDAAAAQA3AOoMAAAGAEwALgAECn8sAAMdAAkJACYfAADlAwAdAAkJACYfAADlAwAeAAEJpQ5FXgBCAAABLgAECgYJDwAfAAAAAA==.',
Se='Sephiroth:BAABLgAECn8VAAIIAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAIAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAAAA==.Serephant:BAAALgADCgEJAgAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgQJBQABLgAECgkJQAAHAAQlAA==.',
So='Soothe:BAABLgAECn8VAAIVAAYJ7RhzIQCdAQZoDAAABABAAGkMAAAFAE0AawwAAAQALgBqDAAAAQA6AGwMAAACADkA6gwAAAUATgAVAAYJ7RhzIQCdAQZoDAAABABAAGkMAAAFAE0AawwAAAQALgBqDAAAAQA6AGwMAAACADkA6gwAAAUATgAAAA==.',
St='Stormride:BAAALgAECgEJAQAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8fAAMIAAgJhh/GJgBNAghoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAFAFIAbQwAAAIAWQDqDAAABQBeAG4MAAABACkACAAICYYfxiYATQIIaAwAAAUAYwBpDAAABQBRAGsMAAAFAEsAagwAAAMAVQBsDAAABQBSAG0MAAABAFkA6gwAAAUAXgBuDAAAAQApABkAAQmXA6yEACwAAW0MAAABAAkAAAA=.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8JAAISAAMJcRTJKADlAANoDAAAAwA5AGkMAAABADQA6gwAAAUALgASAAMJcRTJKADlAANoDAAAAwA5AGkMAAABADQA6gwAAAUALgAuAAQKfx8AAhIACAlEH5kPAGQCABIACAlEH5kPAGQCAAAA.',
Te='Tengoo:BAAALgAECgUJBQAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIIAAIJBxWxcQCTAAJoDAAAAwA3AOoMAAACADQACAACCQcVsXEAkwACaAwAAAMANwDqDAAAAgA0AAAA.Thylight:BAAALgADCgIJAgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgEJBAAAAA==.',
Ve='Veew:BAABLgAECn8XAAMSAAgJ8RGROgC8AQhoDAAABAA8AGkMAAAEAEUAawwAAAQAOgBqDAAAAwAwAGwMAAADADcAbQwAAAEAEADqDAAAAwAsAG8MAAABABAAEgAICToRkToAvAEIaAwAAAMAPABpDAAAAwBFAGsMAAADADoAagwAAAEAMABsDAAAAgAqAG0MAAABABAA6gwAAAMALABvDAAAAQAQABMABQmyEQobABkBBWgMAAABADkAaQwAAAEAPgBrDAAAAQAGAGoMAAACACQAbAwAAAEANwAAAA==.',
Vy='Vynaca:BAAALgAECgEJBAAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8oAAIgAAgJTQyFWQB2AQhoDAAABwAjAGkMAAAGADMAawwAAAYAJwBqDAAABQAkAGwMAAAFABQAbQwAAAMAFwDqDAAABAAiAG4MAAAEABAAIAAICU0MhVkAdgEIaAwAAAcAIwBpDAAABgAzAGsMAAAGACcAagwAAAUAJABsDAAABQAUAG0MAAADABcA6gwAAAQAIgBuDAAABAAQAAAA.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgEJBAAAAA==.',
Yu='Yungmage:BAABLgAECn8dAAIMAAcJYBuQggDMAQdoDAAABgBUAGkMAAAGAF0AawwAAAUAVwBqDAAABgBSAGwMAAABAEIAbQwAAAEAEQDqDAAABABGAAwABwlgG5CCAMwBB2gMAAAGAFQAaQwAAAYAXQBrDAAABQBXAGoMAAAGAFIAbAwAAAEAQgBtDAAAAQARAOoMAAAEAEYAAAA=.',
Za='Zaifu:BAAALgAECgEJBAAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIMAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAMAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAAAA==.',
['Èl']='Èlfman:BAAALgAECgUJEQAAAA==.',
['Øm']='Ømega:BAAALgAECgEJAQAAAA==.',
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
