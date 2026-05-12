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

local lookup = {'DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Hunter-Survival','Druid-Restoration','Shaman-Restoration','Unknown-Unknown','DemonHunter-Devourer','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Paladin-Retribution','Druid-Guardian','Rogue-Subtlety','Hunter-Marksmanship','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='daily',zone=46,date='2026-05-11',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgADCgQJBAAAAA==.',
An='Andeys:BAAALgAECgYJCgAAAA==.Angelius:BAAALgAECgMJAwABLgAECgkJKQABAJYfAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHQACAJkTAA==.',
Ba='Baggigy:BAABLgAECn8ZAAMBAAYJ1ByYSwBqAQZoDAAABQBdAGkMAAAFAFMAawwAAAUASgBqDAAAAgA2AGwMAAACADgA6gwAAAYAPAABAAYJ1ByYSwBqAQZoDAAABABdAGkMAAAEAFMAawwAAAQASgBqDAAAAgA2AGwMAAACADgA6gwAAAUAPAADAAQJQAQ4LQB4AARoDAAAAQANAGkMAAABAAUAawwAAAEACADqDAAAAQAQAAAA.Balance:BAAALgAFFAIJAwAAAA==.',
Be='Bentpanda:BAABLgAECn8WAAIEAAgJ5BWODADrAQhoDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAABABEABAAICeQVjgwA6wEIaAwAAAQAXQBpDAAABABMAGsMAAAEADoAagwAAAIAOQBsDAAAAgAdAG0MAAACAE8A6gwAAAMAJABuDAAAAQARAAAA.',
Bh='Bhain:BAAALgAFFAIJAwAAAA==.',
Bi='Bigcocko:BAACLgAFFH8aAAIFAAYJqx0pAwA2AgZoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYA6gwAAAUAXAAFAAYJqx0pAwA2AgZoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYA6gwAAAUAXAAuAAQKfyYAAgUACQlvJYoCAHIDAAUACQlvJYoCAHIDAAAA.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAECgYJGQABANQcAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAAALgAECgYJEQAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAIGAAkJ/AwrOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAGAAkJ/AwrOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAAAA==.',
Ca='Camouflage:BAABLgAECn81AAIEAAkJwyPiAAA1AwloDAAACABiAGkMAAAIAGEAawwAAAcAYgBqDAAABwBeAGwMAAAGAFMAbQwAAAQAWgDqDAAABwBiAG4MAAAEAFMAbwwAAAIAUQAEAAkJwyPiAAA1AwloDAAACABiAGkMAAAIAGEAawwAAAcAYgBqDAAABwBeAGwMAAAGAFMAbQwAAAQAWgDqDAAABwBiAG4MAAAEAFMAbwwAAAIAUQAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBAAHAAAAAA==.Chilyn:BAAALgADCgIJAgAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIIAAYJEw54XgD0AAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAIAAYJEw54XgD0AAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAAAA==.Corrupthell:BAAALgAECgYJCwAAAA==.Cowi:BAAALgAECgQJBwAAAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAIJAAgJRxomXAAlAghoDAAABABaAGkMAAAEAEcAawwAAAMAPQBqDAAABABRAGwMAAACAEsAbQwAAAEAUQDqDAAABABCAG4MAAACABgACQAICUcaJlwAJQIIaAwAAAQAWgBpDAAABABHAGsMAAADAD0AagwAAAQAUQBsDAAAAgBLAG0MAAABAFEA6gwAAAQAQgBuDAAAAgAYAAAA.Daswassap:BAAALgAECgUJBQAAAA==.',
De='Def:BAAALgAECgEJAQAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8dAAQCAAkJmRMWMACVAQloDAAABwBCAGkMAAAFAFAAawwAAAUATABqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AG4MAAABAAsAbwwAAAEAMgACAAcJexMWMACVAQdoDAAABAA8AGkMAAAEAEAAawwAAAQAOQBqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AAoABQk6FvQ7ACwBBWgMAAACAEIAaQwAAAEAUABrDAAAAQBMAG4MAAABAAsAbwwAAAEAMgALAAEJ2xfxYgBEAAFoDAAAAQA9AAAA.Driver:BAECLgAFFH8JAAIMAAQJ0AzAKAArAQRoDAAAAwARAGkMAAACAB4AbAwAAAEAKQDqDAAAAwApAAwABAnQDMAoACsBBGgMAAADABEAaQwAAAIAHgBsDAAAAQApAOoMAAADACkALgAECn81AAMMAAgJ4h7zGQC5AgAMAAgJ4h7zGQC5AgANAAYJ4hjRFACkAQAAAA==.',
['Dä']='Däenerys:BAAALgAECgcJBwAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAYJEAAIAMYhAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJlyQrAQA4AwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgACAAkJlyQrAQA4AwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHQACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frosty:BAABLgAECn8UAAIJAAcJzw3SqACIAQdoDAAABAArAGkMAAADACsAawwAAAMAMQBqDAAAAwAgAGwMAAADABoAbQwAAAEABADqDAAAAwAqAAkABwnPDdKoAIgBB2gMAAAEACsAaQwAAAMAKwBrDAAAAwAxAGoMAAADACAAbAwAAAMAGgBtDAAAAQAEAOoMAAADACoAAAA=.Frybeam:BAAALgADCgQJBQAAAA==.',
Gi='Gilfoyle:BAAALgAECgEJAQAAAA==.Giovahni:BAABLgAECn8rAAIIAAgJiR+tEABPAghoDAAABwBgAGkMAAAHAFIAawwAAAcAWQBqDAAABQBOAGwMAAAFAE4AbQwAAAQARADqDAAABQBVAG4MAAADAD8ACAAICYkfrRAATwIIaAwAAAcAYABpDAAABwBSAGsMAAAHAFkAagwAAAUATgBsDAAABQBOAG0MAAAEAEQA6gwAAAUAVQBuDAAAAwA/AAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHQACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIJAAcJsAVWyABYAQdoDAAABAASAGkMAAAEABMAawwAAAQAEABqDAAAAgAUAGwMAAACABAAbQwAAAEABQDqDAAAAwAKAAkABwmwBVbIAFgBB2gMAAAEABIAaQwAAAQAEwBrDAAABAAQAGoMAAACABQAbAwAAAIAEABtDAAAAQAFAOoMAAADAAoAAAA=.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8aAAIOAAgJ6hLFHgCAAQhoDAAABQAwAGkMAAAEAD8AawwAAAQAQQBqDAAABAAUAGwMAAADADMAbQwAAAEAFwDqDAAABAAtAG4MAAABACkADgAICeoSxR4AgAEIaAwAAAUAMABpDAAABAA/AGsMAAAEAEEAagwAAAQAFABsDAAAAwAzAG0MAAABABcA6gwAAAQALQBuDAAAAQApAAAA.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAQAAAA==.Janaria:BAAALgAECgYJDQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJAQAAAA==.Jessiescool:BAABLgAECn8aAAIPAAYJNQ7dewAIAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAPAAYJNQ7dewAIAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIQAAkJMw4vEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAQAAkJMw4vEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAAALgAFFAIJAgAAAA==.',
Ka='Kalvin:BAABLgAECn8VAAIRAAcJywr9HQAbAQdoDAAABAAlAGkMAAACACMAawwAAAMAGABqDAAAAgACAGwMAAACACgAbQwAAAEAAQDqDAAABwAZABEABwnLCv0dABsBB2gMAAAEACUAaQwAAAIAIwBrDAAAAwAYAGoMAAACAAIAbAwAAAIAKABtDAAAAQABAOoMAAAHABkAAAA=.Kanari:BAAALgAECgYJDwAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgEJAQAAAA==.',
La='Lagoles:BAABLgAECn8wAAMEAAkJgSF7AQAJAwloDAAABwBiAGkMAAAHAGEAawwAAAcAYQBqDAAABQBiAGwMAAAFAFYAbQwAAAUAWADqDAAABwBNAG4MAAAEAEYAbwwAAAEARQAEAAkJ2iB7AQAJAwloDAAAAgBiAGkMAAACAGEAawwAAAIAYQBqDAAAAgBiAGwMAAABAFYAbQwAAAEATADqDAAAAQBMAG4MAAABAEYAbwwAAAEARQASAAgJfR+YEwCYAghoDAAABQBVAGkMAAAFAFQAawwAAAUAVgBqDAAAAwBRAGwMAAAEAFEAbQwAAAQAWADqDAAABgBNAG4MAAADADsAAAA=.Landis:BAAALgAECgUJDAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJNQAEAMMjAA==.Leoben:BAAALgAECgEJAQAAAA==.',
Li='Liltracey:BAAALgAECgUJCgABLgAFFAIJAwAHAAAAAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAQADMOAA==.',
Mi='Miggles:BAACLgAFFH8MAAIFAAMJKhGdJQDMAANoDAAABAAkAGkMAAADABIA6gwAAAUASwAFAAMJKhGdJQDMAANoDAAABAAkAGkMAAADABIA6gwAAAUASwAuAAQKfyIAAwUACQnIHvcQALACAAUACQnIHvcQALACABMAAglmDkxsAG8AAAAA.',
Mk='Mk:BAABLgAECn8wAAMKAAgJDiMdBgAfAwhoDAAACABjAGkMAAAHAGMAawwAAAcAYQBqDAAACABhAGwMAAAGAFYAbQwAAAMAMADqDAAABgBiAG4MAAADAGIACgAICQ4jHQYAHwMIaAwAAAcAYwBpDAAABgBjAGsMAAAGAGEAagwAAAcAYQBsDAAABQBWAG0MAAADADAA6gwAAAYAYgBuDAAAAwBiAAIABQmmCek6ALkABWgMAAABABUAaQwAAAEAHABrDAAAAQAeAGoMAAABAAwAbAwAAAEAEQAAAA==.',
Mo='Monzo:BAABLgAECn8dAAMBAAgJWCEEGQDmAghoDAAABgBSAGkMAAAGAF4AawwAAAUAXwBqDAAAAgBIAGwMAAACAE0AbQwAAAIAQADqDAAABQBhAG4MAAABAFQAAQAICVghBBkA5gIIaAwAAAUAUgBpDAAABQBeAGsMAAAFAF8AagwAAAIASABsDAAAAgBNAG0MAAACAEAA6gwAAAUAYQBuDAAAAQBUAAMAAgnUD5E9AFwAAmgMAAABACoAaQwAAAEAJgABLgAFFAIJAwAHAAAAAA==.Morvayne:BAABLgAECn8vAAIJAAkJSRxzEgCWAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwAJAAkJSRxzEgCWAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwABLgAECgkJMAAEAIEhAA==.',
My='Myneemo:BAAALgAECgQJAwAAAA==.Myro:BAAALgAECgUJBwAAAA==.',
No='Nomoneydown:BAAALgAECgEJAQAAAA==.Nosam:BAABLgAECn8XAAIMAAcJixC3TABOAQdoDAAACABBAGkMAAAFACgAawwAAAQAIQBqDAAAAgA8AGwMAAABACQAbQwAAAEAJADqDAAAAgApAAwABwmLELdMAE4BB2gMAAAIAEEAaQwAAAUAKABrDAAABAAhAGoMAAACADwAbAwAAAEAJABtDAAAAQAkAOoMAAACACkAAAA=.',
Nt='Nthegreat:BAAALgAECgUJBQAAAA==.',
Nw='Nwf:BAABLgAECn8WAAIOAAYJ5RheJgBNAQZoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAAAwA+AGwMAAADAA8A6gwAAAQASAAOAAYJ5RheJgBNAQZoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAAAwA+AGwMAAADAA8A6gwAAAQASAAAAA==.',
['Nè']='Nèbula:BAAALgAECgYJBgAAAA==.',
Or='Ornatas:BAACLgAFFH8HAAIUAAMJDR9DFQAWAQNoDAAABABaAGkMAAACAD8A6gwAAAEAVAAUAAMJDR9DFQAWAQNoDAAABABaAGkMAAACAD8A6gwAAAEAVAAuAAQKfxcAAhQACAmpHJEVAG8CABQACAmpHJEVAG8CAAAA.',
Pa='Pandamonium:BAABLgAECn8cAAQLAAcJkxT+KwBWAQdoDAAABgAvAGkMAAAFADgAawwAAAYAOgBqDAAAAwBRAGwMAAABACIA6gwAAAYAPQBuDAAAAQAcAAsABwmTFP4rAFYBB2gMAAAFAC8AaQwAAAQAOABrDAAABAA6AGoMAAACAFEAbAwAAAEAIgDqDAAABAA9AG4MAAABABwAAgAECfgDiEwAcwAEaAwAAAEABABpDAAAAQAMAGsMAAACAA4AagwAAAEADQAKAAEJOAkbbwApAAHqDAAAAgAXAAAA.',
Pe='Perdyblues:BAAALgAECggJEAAAAA==.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgEJAQAAAA==.',
Qi='Qiana:BAAALgAECgQJBAAAAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAIKAAgJCAwSJgAKAQhoDAAABgA8AGkMAAAFAC4AawwAAAIAEgBqDAAABAAhAGwMAAADACUAbQwAAAEABwDqDAAABQAZAG4MAAABABMACgAICQgMEiYACgEIaAwAAAYAPABpDAAABQAuAGsMAAACABIAagwAAAQAIQBsDAAAAwAlAG0MAAABAAcA6gwAAAUAGQBuDAAAAQATAAAA.',
Ra='Rainootra:BAAALgADCgIJAgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHQACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHQACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAAALgAECggJDQAAAA==.',
Sc='Scylla:BAACLgAFFH8SAAIVAAcJvx0tAQBBAgdoDAAAAQA2AGkMAAAEAGEAawwAAAMAWgBqDAAAAgBEAGwMAAABAFoAbQwAAAEANwDqDAAABgBMABUABwm/HS0BAEECB2gMAAABADYAaQwAAAQAYQBrDAAAAwBaAGoMAAACAEQAbAwAAAEAWgBtDAAAAQA3AOoMAAAGAEwALgAECn8sAAMVAAkJACYfAADlAwAVAAkJACYfAADlAwAWAAEJpQ5AXgBCAAABLgAECgYJDwAHAAAAAA==.',
Se='Sephiroth:BAABLgAECn8VAAIPAAkJDhSGQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAPAAkJDhSGQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgQJBQABLgAECgkJNQAEAMMjAA==.',
So='Soothe:BAAALgAECgYJCwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8ZAAIPAAYJOCElMADOAQZoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAADAEkA6gwAAAQAXgAPAAYJOCElMADOAQZoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAADAEkA6gwAAAQAXgAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8GAAIOAAIJXhLAJgCaAAJoDAAAAwA5AOoMAAADACQADgACCV4SwCYAmgACaAwAAAMAOQDqDAAAAwAkAC4ABAp/FwACDgAICQ4dDRUAzwEADgAICQ4dDRUAzwEAAAA=.',
Te='Tengoo:BAAALgAECgQJBAAAAA==.',
Th='Thewaitress:BAAALgAFFAIJBAAAAA==.Thylight:BAAALgADCgIJAgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgEJAQAAAA==.',
Ve='Veew:BAABLgAECn8XAAMOAAgJ8RGQOgC8AQhoDAAABAA8AGkMAAAEAEUAawwAAAQAOgBqDAAAAwAwAGwMAAADADcAbQwAAAEAEADqDAAAAwAsAG8MAAABABAADgAICToRkDoAvAEIaAwAAAMAPABpDAAAAwBFAGsMAAADADoAagwAAAEAMABsDAAAAgAqAG0MAAABABAA6gwAAAMALABvDAAAAQAQABcABQmyEQkbABkBBWgMAAABADkAaQwAAAEAPgBrDAAAAQAGAGoMAAACACQAbAwAAAEANwAAAA==.',
Vy='Vynaca:BAAALgAECgEJAQAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8gAAIYAAgJTQwZNwCBAQhoDAAABgAjAGkMAAAFADMAawwAAAUAJwBqDAAABAAkAGwMAAAEABQAbQwAAAIAFwDqDAAAAwAiAG4MAAADABAAGAAICU0MGTcAgQEIaAwAAAYAIwBpDAAABQAzAGsMAAAFACcAagwAAAQAJABsDAAABAAUAG0MAAACABcA6gwAAAMAIgBuDAAAAwAQAAAA.',
Wo='Wontan:BAAALgAECgcJBwAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgEJAQAAAA==.',
Yu='Yungmage:BAABLgAECn8aAAIJAAcJOhmPggDMAQdoDAAABQBVAGkMAAAFAEEAawwAAAQAUQBqDAAABgBSAGwMAAABAEIAbQwAAAEAEQDqDAAABABGAAkABwk6GY+CAMwBB2gMAAAFAFUAaQwAAAUAQQBrDAAABABRAGoMAAAGAFIAbAwAAAEAQgBtDAAAAQARAOoMAAAEAEYAAAA=.',
Za='Zaifu:BAAALgAECgEJAQAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIJAAkJABhQRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAJAAkJABhQRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAAAA==.',
['Èl']='Èlfman:BAAALgAECgUJCgAAAA==.',
['Øm']='Ømega:BAAALgAECgEJAQAAAA==.',
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
