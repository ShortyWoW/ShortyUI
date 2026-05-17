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

local lookup = {'DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Hunter-Survival','Paladin-Retribution','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Druid-Guardian','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='daily',zone=46,date='2026-05-16',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgADCgQJBAAAAA==.',
An='Andeys:BAAALgAECgYJCgAAAA==.Angelius:BAAALgAECgYJCAABLgAECgkJLgABAJYfAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHQACAJkTAA==.',
Ba='Baggigy:BAABLgAECn8ZAAMBAAYJ1Bz0bABBAQZoDAAABQBdAGkMAAAFAFMAawwAAAUASgBqDAAAAgA2AGwMAAACADgA6gwAAAYAPAABAAYJ1Bz0bABBAQZoDAAABABdAGkMAAAEAFMAawwAAAQASgBqDAAAAgA2AGwMAAACADgA6gwAAAUAPAADAAQJQAQQNQBwAARoDAAAAQANAGkMAAABAAUAawwAAAEACADqDAAAAQAQAAAA.Balance:BAAALgAFFAIJAwAAAA==.',
Be='Bentpanda:BAABLgAECn8WAAIEAAgJ5BUYEwDIAQhoDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAABABEABAAICeQVGBMAyAEIaAwAAAQAXQBpDAAABABMAGsMAAAEADoAagwAAAIAOQBsDAAAAgAdAG0MAAACAE8A6gwAAAMAJABuDAAAAQARAAAA.',
Bh='Bhain:BAABLgAFFH8GAAIFAAMJgxDGPQDyAANoDAAAAwA+AGkMAAACAB4A6gwAAAEAIQAFAAMJgxDGPQDyAANoDAAAAwA+AGkMAAACAB4A6gwAAAEAIQAAAA==.',
Bi='Bigcocko:BAACLgAFFH8bAAIGAAYJqx19BAA1AgZoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYA6gwAAAYAXAAGAAYJqx19BAA1AgZoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYA6gwAAAYAXAAuAAQKfysAAgYACQmGJYkCAHIDAAYACQmGJYkCAHIDAAAA.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAECgYJGQABANQcAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAAALgAECgYJEQAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAIHAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAHAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAAAA==.',
Ca='Camouflage:BAABLgAECn8+AAIEAAkJpyQUAQA1AwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAFAFgAbwwAAAMAUQAEAAkJpyQUAQA1AwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAFAFgAbwwAAAMAUQAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAFAAcVAA==.Chilyn:BAAALgADCgUJBgAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIIAAYJEw4YeADdAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAIAAYJEw4YeADdAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAAAA==.Corrupthell:BAAALgAECgYJCwAAAA==.Cowi:BAAALgAECgQJBwAAAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAIJAAgJRxopXAAlAghoDAAABABaAGkMAAAEAEcAawwAAAMAPQBqDAAABABRAGwMAAACAEsAbQwAAAEAUQDqDAAABABCAG4MAAACABgACQAICUcaKVwAJQIIaAwAAAQAWgBpDAAABABHAGsMAAADAD0AagwAAAQAUQBsDAAAAgBLAG0MAAABAFEA6gwAAAQAQgBuDAAAAgAYAAAA.Daswassap:BAAALgAECgUJBQAAAA==.',
De='Def:BAAALgAECgEJAQAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8dAAQCAAkJmRMYMACVAQloDAAABwBCAGkMAAAFAFAAawwAAAUATABqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AG4MAAABAAsAbwwAAAEAMgACAAcJexMYMACVAQdoDAAABAA8AGkMAAAEAEAAawwAAAQAOQBqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AAoABQk6Fvo7ACwBBWgMAAACAEIAaQwAAAEAUABrDAAAAQBMAG4MAAABAAsAbwwAAAEAMgALAAEJ2xfxYgBEAAFoDAAAAQA9AAAA.Driver:BAECLgAFFH8KAAIMAAQJ0AwOMwApAQRoDAAAAwARAGkMAAACAB4AbAwAAAEAKQDqDAAABAApAAwABAnQDA4zACkBBGgMAAADABEAaQwAAAIAHgBsDAAAAQApAOoMAAAEACkALgAECn81AAMMAAgJ4h7zGQC5AgAMAAgJ4h7zGQC5AgANAAYJ4hjRFACkAQAAAA==.',
['Dä']='Däenerys:BAAALgAECgcJBwAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAYJEQAIAMYhAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJlyTwAQAiAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgACAAkJlyTwAQAiAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHQACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frosty:BAABLgAECn8UAAIJAAcJzw3UqACIAQdoDAAABAArAGkMAAADACsAawwAAAMAMQBqDAAAAwAgAGwMAAADABoAbQwAAAEABADqDAAAAwAqAAkABwnPDdSoAIgBB2gMAAAEACsAaQwAAAMAKwBrDAAAAwAxAGoMAAADACAAbAwAAAMAGgBtDAAAAQAEAOoMAAADACoAAAA=.Frybeam:BAAALgAECgEJAQAAAA==.',
Gi='Gilfoyle:BAAALgAECgEJAgAAAA==.Giovahni:BAABLgAECn8xAAIIAAgJ1h8OFABhAghoDAAACABgAGkMAAAIAFIAawwAAAgAWQBqDAAABgBOAGwMAAAGAFQAbQwAAAUARADqDAAABQBVAG4MAAADAD8ACAAICdYfDhQAYQIIaAwAAAgAYABpDAAACABSAGsMAAAIAFkAagwAAAYATgBsDAAABgBUAG0MAAAFAEQA6gwAAAUAVQBuDAAAAwA/AAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHQACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIJAAcJsAVXyABYAQdoDAAABAASAGkMAAAEABMAawwAAAQAEABqDAAAAgAUAGwMAAACABAAbQwAAAEABQDqDAAAAwAKAAkABwmwBVfIAFgBB2gMAAAEABIAaQwAAAQAEwBrDAAABAAQAGoMAAACABQAbAwAAAIAEABtDAAAAQAFAOoMAAADAAoAAAA=.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8aAAIOAAgJ6hIsKgBfAQhoDAAABQAwAGkMAAAEAD8AawwAAAQAQQBqDAAABAAUAGwMAAADADMAbQwAAAEAFwDqDAAABAAtAG4MAAABACkADgAICeoSLCoAXwEIaAwAAAUAMABpDAAABAA/AGsMAAAEAEEAagwAAAQAFABsDAAAAwAzAG0MAAABABcA6gwAAAQALQBuDAAAAQApAAAA.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAgAAAA==.Janaria:BAAALgAECgYJDQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJAgAAAA==.Jessiescool:BAABLgAECn8aAAIFAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAFAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIPAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAPAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAAALgAFFAMJBAAAAA==.',
Ka='Kalvin:BAABLgAECn8YAAIQAAcJJwyxIQAoAQdoDAAABAAlAGkMAAADADMAawwAAAMAGABqDAAAAgACAGwMAAACACgAbQwAAAIABgDqDAAACAAZABAABwknDLEhACgBB2gMAAAEACUAaQwAAAMAMwBrDAAAAwAYAGoMAAACAAIAbAwAAAIAKABtDAAAAgAGAOoMAAAIABkAAAA=.Kanari:BAABLgAECn8UAAQRAAYJjhTvKgAoAQZoDAAABAAzAGkMAAAEACgAawwAAAQAMwBqDAAAAwA7AGwMAAADADEA6gwAAAIAPgARAAYJjhTvKgAoAQZoDAAABAAzAGkMAAACACgAawwAAAMAMwBqDAAAAgA7AGwMAAADADEA6gwAAAIAPgASAAEJIwVpXQAoAAFpDAAAAQANABMAAwnFAOlrABkAA2kMAAABAAEAawwAAAEAAgBqDAAAAQADAAAA.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgEJAgAAAA==.',
La='Lagoles:BAABLgAECn8wAAMEAAkJgSEkAwDYAgloDAAABwBiAGkMAAAHAGEAawwAAAcAYQBqDAAABQBiAGwMAAAFAFYAbQwAAAUAWADqDAAABwBNAG4MAAAEAEYAbwwAAAEARQAEAAkJ2iAkAwDYAgloDAAAAgBiAGkMAAACAGEAawwAAAIAYQBqDAAAAgBiAGwMAAABAFYAbQwAAAEATADqDAAAAQBMAG4MAAABAEYAbwwAAAEARQAUAAgJfR+aEwCYAghoDAAABQBVAGkMAAAFAFQAawwAAAUAVgBqDAAAAwBRAGwMAAAEAFEAbQwAAAQAWADqDAAABgBNAG4MAAADADsAAAA=.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJDAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJPgAEAKckAA==.Leoben:BAAALgAECgEJAgAAAA==.',
Li='Liltracey:BAAALgAECgUJCgABLgAFFAIJAwAVAAAAAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAPADMOAA==.',
Mi='Miggles:BAACLgAFFH8NAAIGAAMJKhF+KgDMAANoDAAABAAkAGkMAAADABIA6gwAAAYASwAGAAMJKhF+KgDMAANoDAAABAAkAGkMAAADABIA6gwAAAYASwAuAAQKfykAAwYACQnGH3AOAKMCAAYACQnGH3AOAKMCABYAAglmDk1sAG8AAAAA.',
Mk='Mk:BAEBLgAECn83AAMKAAgJayMfBgAfAwhoDAAACQBjAGkMAAAIAGMAawwAAAgAYQBqDAAACQBhAGwMAAAHAFwAbQwAAAMAMADqDAAABwBiAG4MAAAEAGIACgAICWsjHwYAHwMIaAwAAAgAYwBpDAAABwBjAGsMAAAHAGEAagwAAAgAYQBsDAAABgBcAG0MAAADADAA6gwAAAcAYgBuDAAABABiAAIABQmmCUxFAK0ABWgMAAABABUAaQwAAAEAHABrDAAAAQAeAGoMAAABAAwAbAwAAAEAEQAAAA==.',
Mo='Monzo:BAABLgAECn8jAAMBAAgJ2iEEGQDmAghoDAAABwBbAGkMAAAHAF4AawwAAAYAXwBqDAAAAwBbAGwMAAADAE0AbQwAAAIAQADqDAAABgBhAG4MAAABAFQAAQAICdohBBkA5gIIaAwAAAYAWwBpDAAABgBeAGsMAAAGAF8AagwAAAMAWwBsDAAAAwBNAG0MAAACAEAA6gwAAAYAYQBuDAAAAQBUAAMAAgnUD5I9AFwAAmgMAAABACoAaQwAAAEAJgABLgAFFAIJAwAVAAAAAA==.Morvayne:BAABLgAECn8vAAIJAAkJSRzpHgBoAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwAJAAkJSRzpHgBoAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwABLgAECgkJMAAEAIEhAA==.',
My='Myneemo:BAAALgAECgQJAwAAAA==.Myro:BAAALgAECgUJCAAAAA==.',
No='Nomoneydown:BAAALgAECgEJAgAAAA==.Nosam:BAABLgAECn8XAAIMAAcJixAzZQA2AQdoDAAACABBAGkMAAAFACgAawwAAAQAIQBqDAAAAgA8AGwMAAABACQAbQwAAAEAJADqDAAAAgApAAwABwmLEDNlADYBB2gMAAAIAEEAaQwAAAUAKABrDAAABAAhAGoMAAACADwAbAwAAAEAJABtDAAAAQAkAOoMAAACACkAAAA=.',
Nt='Nthegreat:BAAALgAECgUJBQAAAA==.',
Nw='Nwf:BAABLgAECn8WAAIOAAYJ5RgIPQCwAQZoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAAAwA+AGwMAAADAA8A6gwAAAQASAAOAAYJ5RgIPQCwAQZoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAAAwA+AGwMAAADAA8A6gwAAAQASAAAAA==.',
['Nè']='Nèbula:BAAALgAECgYJCAAAAA==.',
Or='Ornatas:BAACLgAFFH8HAAIXAAMJDR9yGQAIAQNoDAAABABaAGkMAAACAD8A6gwAAAEAVAAXAAMJDR9yGQAIAQNoDAAABABaAGkMAAACAD8A6gwAAAEAVAAuAAQKfxgAAhcACAnDHJYVAG8CABcACAnDHJYVAG8CAAAA.',
Pa='Pandamonium:BAABLgAECn8cAAQLAAcJkxT8KwBWAQdoDAAABgAvAGkMAAAFADgAawwAAAYAOgBqDAAAAwBRAGwMAAABACIA6gwAAAYAPQBuDAAAAQAcAAsABwmTFPwrAFYBB2gMAAAFAC8AaQwAAAQAOABrDAAABAA6AGoMAAACAFEAbAwAAAEAIgDqDAAABAA9AG4MAAABABwAAgAECfgDKVgAagAEaAwAAAEABABpDAAAAQAMAGsMAAACAA4AagwAAAEADQAKAAEJOAmBfAApAAHqDAAAAgAXAAAA.',
Pe='Perdyblues:BAAALgAECggJEAAAAA==.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgEJAQAAAA==.',
Qi='Qiana:BAAALgAECgQJBAABLgAECgkJIQARAL4bAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAIKAAgJCAxsMAD2AAhoDAAABgA8AGkMAAAFAC4AawwAAAIAEgBqDAAABAAhAGwMAAADACUAbQwAAAEABwDqDAAABQAZAG4MAAABABMACgAICQgMbDAA9gAIaAwAAAYAPABpDAAABQAuAGsMAAACABIAagwAAAQAIQBsDAAAAwAlAG0MAAABAAcA6gwAAAUAGQBuDAAAAQATAAAA.',
Ra='Rainootra:BAAALgADCgIJAgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHQACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHQACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAAALgAECggJEQAAAA==.',
Sc='Scylla:BAACLgAFFH8SAAIYAAcJvx0uAQBCAgdoDAAAAQA2AGkMAAAEAGEAawwAAAMAWgBqDAAAAgBEAGwMAAABAFoAbQwAAAEANwDqDAAABgBMABgABwm/HS4BAEICB2gMAAABADYAaQwAAAQAYQBrDAAAAwBaAGoMAAACAEQAbAwAAAEAWgBtDAAAAQA3AOoMAAAGAEwALgAECn8sAAMYAAkJACYfAADlAwAYAAkJACYfAADlAwAZAAEJpQ5FXgBCAAABLgAECgYJDwAVAAAAAA==.',
Se='Sephiroth:BAABLgAECn8VAAIFAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAFAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgQJBQABLgAECgkJPgAEAKckAA==.',
So='Soothe:BAAALgAECgYJCwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8aAAIFAAYJ7iHqPQDEAQZoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAEAFIA6gwAAAQAXgAFAAYJ7iHqPQDEAQZoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAEAFIA6gwAAAQAXgAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8HAAIOAAIJXhKDLACTAAJoDAAAAwA5AOoMAAAEACQADgACCV4SgywAkwACaAwAAAMAOQDqDAAABAAkAC4ABAp/FwACDgAICQ4dZR4ArAEADgAICQ4dZR4ArAEAAAA=.',
Te='Tengoo:BAAALgAECgQJBAAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIFAAIJBxUiUwCnAAJoDAAAAwA3AOoMAAACADQABQACCQcVIlMApwACaAwAAAMANwDqDAAAAgA0AAAA.Thylight:BAAALgADCgIJAgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgEJAgAAAA==.',
Ve='Veew:BAABLgAECn8XAAMOAAgJ8RGROgC8AQhoDAAABAA8AGkMAAAEAEUAawwAAAQAOgBqDAAAAwAwAGwMAAADADcAbQwAAAEAEADqDAAAAwAsAG8MAAABABAADgAICToRkToAvAEIaAwAAAMAPABpDAAAAwBFAGsMAAADADoAagwAAAEAMABsDAAAAgAqAG0MAAABABAA6gwAAAMALABvDAAAAQAQABoABQmyEQobABkBBWgMAAABADkAaQwAAAEAPgBrDAAAAQAGAGoMAAACACQAbAwAAAEANwAAAA==.',
Vy='Vynaca:BAAALgAECgEJAgAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8gAAIbAAgJTQzaSABuAQhoDAAABgAjAGkMAAAFADMAawwAAAUAJwBqDAAABAAkAGwMAAAEABQAbQwAAAIAFwDqDAAAAwAiAG4MAAADABAAGwAICU0M2kgAbgEIaAwAAAYAIwBpDAAABQAzAGsMAAAFACcAagwAAAQAJABsDAAABAAUAG0MAAACABcA6gwAAAMAIgBuDAAAAwAQAAAA.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgEJAgAAAA==.',
Yu='Yungmage:BAABLgAECn8aAAIJAAcJNxmQggDMAQdoDAAABQBUAGkMAAAFAEEAawwAAAQAUQBqDAAABgBSAGwMAAABAEIAbQwAAAEAEQDqDAAABABGAAkABwk3GZCCAMwBB2gMAAAFAFQAaQwAAAUAQQBrDAAABABRAGoMAAAGAFIAbAwAAAEAQgBtDAAAAQARAOoMAAAEAEYAAAA=.',
Za='Zaifu:BAAALgAECgEJAgAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIJAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAJAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAAAA==.',
['Èl']='Èlfman:BAAALgAECgUJDwAAAA==.',
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
