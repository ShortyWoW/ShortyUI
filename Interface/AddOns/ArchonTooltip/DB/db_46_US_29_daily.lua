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

local lookup = {'DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='daily',zone=46,date='2026-05-20',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgAECgMJBAAAAA==.',
An='Andeys:BAAALgAECgcJDgAAAA==.Angelius:BAAALgAECgYJCQABLgAECgkJLgABAJYfAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgACAJkTAA==.',
Ba='Baggigy:BAABLgAECn8ZAAMBAAYJ1ByDfAA/AQZoDAAABQBdAGkMAAAFAFMAawwAAAUASgBqDAAAAgA2AGwMAAACADgA6gwAAAYAPAABAAYJ1ByDfAA/AQZoDAAABABdAGkMAAAEAFMAawwAAAQASgBqDAAAAgA2AGwMAAACADgA6gwAAAUAPAADAAQJQASXOgBrAARoDAAAAQANAGkMAAABAAUAawwAAAEACADqDAAAAQAQAAAA.Balance:BAABLgAFFH8IAAMEAAMJcA8vLwDJAANoDAAAAwAyAGkMAAABACEA6gwAAAQAIgAEAAMJcA8vLwDJAANoDAAAAgAyAGkMAAABACEA6gwAAAQAIgAFAAEJjgcSIgAuAAFoDAAAAQATAAAA.',
Be='Bentpanda:BAABLgAECn8WAAIGAAgJ5BWCFgDHAQhoDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAABABEABgAICeQVghYAxwEIaAwAAAQAXQBpDAAABABMAGsMAAAEADoAagwAAAIAOQBsDAAAAgAdAG0MAAACAE8A6gwAAAMAJABuDAAAAQARAAAA.',
Bh='Bhain:BAABLgAFFH8KAAIHAAQJYhEmKgAxAQRoDAAABAA+AGkMAAADAB4AawwAAAEAMwDqDAAAAgAhAAcABAliESYqADEBBGgMAAAEAD4AaQwAAAMAHgBrDAAAAQAzAOoMAAACACEAAAA=.',
Bi='Bigcocko:BAACLgAFFH8cAAIEAAYJqx2+BQA1AgZoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYA6gwAAAcAXAAEAAYJqx2+BQA1AgZoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAAAwBBAGwMAAABACYA6gwAAAcAXAAuAAQKfysAAgQACQmGJYkCAHIDAAQACQmGJYkCAHIDAAAA.Bigwheels:BAAALgAECgMJAwAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAECgYJGQABANQcAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAABLgAECn8UAAIIAAcJEhSuGQDJAQdoDAAAAwBAAGkMAAAEAEcAawwAAAQAMgBqDAAAAQBCAGwMAAABABEAbQwAAAEAGQDqDAAABgBAAAgABwkSFK4ZAMkBB2gMAAADAEAAaQwAAAQARwBrDAAABAAyAGoMAAABAEIAbAwAAAEAEQBtDAAAAQAZAOoMAAAGAEAAAAA=.',
Bu='Buffallo:BAABLgAECn8WAAIJAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAJAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAAAA==.',
Ca='Camouflage:BAABLgAECn8+AAIGAAkJpyR7AQAtAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAFAFgAbwwAAAMAUQAGAAkJpyR7AQAtAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAFAFgAbwwAAAMAUQAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAHAAcVAA==.Chilyn:BAAALgAECgQJBQAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIKAAYJEw4BhADmAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAKAAYJEw4BhADmAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAAAA==.Corrupthell:BAAALgAECgYJCwAAAA==.Cowi:BAAALgAECgQJBwAAAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAILAAgJRxopXAAlAghoDAAABABaAGkMAAAEAEcAawwAAAMAPQBqDAAABABRAGwMAAACAEsAbQwAAAEAUQDqDAAABABCAG4MAAACABgACwAICUcaKVwAJQIIaAwAAAQAWgBpDAAABABHAGsMAAADAD0AagwAAAQAUQBsDAAAAgBLAG0MAAABAFEA6gwAAAQAQgBuDAAAAgAYAAAA.Daswassap:BAAALgAECgUJBQAAAA==.',
De='Def:BAAALgAECgEJAgAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQCAAkJmRMYMACVAQloDAAABwBCAGkMAAAFAFAAawwAAAUATABqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AG4MAAACAAsAbwwAAAEAMgACAAcJexMYMACVAQdoDAAABAA8AGkMAAAEAEAAawwAAAQAOQBqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AAwABQk6Fvo7ACwBBWgMAAACAEIAaQwAAAEAUABrDAAAAQBMAG4MAAABAAsAbwwAAAEAMgANAAIJrBz6aABgAAJoDAAAAQA9AG4MAAABAFUAAAA=.Driver:BAECLgAFFH8KAAIOAAQJ0AwaOgAkAQRoDAAAAwARAGkMAAACAB4AbAwAAAEAKQDqDAAABAApAA4ABAnQDBo6ACQBBGgMAAADABEAaQwAAAIAHgBsDAAAAQApAOoMAAAEACkALgAECn81AAMOAAgJ4h7zGQC5AgAOAAgJ4h7zGQC5AgAPAAYJ4hjRFACkAQAAAA==.',
['Dä']='Däenerys:BAAALgAECggJDgAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAcJEgAKAD0fAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJlyRoAgAeAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgACAAkJlyRoAgAeAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frosty:BAABLgAECn8UAAILAAcJzw3UqACIAQdoDAAABAArAGkMAAADACsAawwAAAMAMQBqDAAAAwAgAGwMAAADABoAbQwAAAEABADqDAAAAwAqAAsABwnPDdSoAIgBB2gMAAAEACsAaQwAAAMAKwBrDAAAAwAxAGoMAAADACAAbAwAAAMAGgBtDAAAAQAEAOoMAAADACoAAAA=.Frybeam:BAAALgAECgEJAgAAAA==.',
Gi='Gilfoyle:BAAALgAECgEJAwAAAA==.Giovahni:BAACLgAFFH8GAAIKAAMJrA1NSADVAANoDAAAAgAlAGkMAAACACoA6gwAAAIAGQAKAAMJrA1NSADVAANoDAAAAgAlAGkMAAACACoA6gwAAAIAGQAuAAQKfzEAAgoACAnWH6YXAGICAAoACAnWH6YXAGICAAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAILAAcJsAVXyABYAQdoDAAABAASAGkMAAAEABMAawwAAAQAEABqDAAAAgAUAGwMAAACABAAbQwAAAEABQDqDAAAAwAKAAsABwmwBVfIAFgBB2gMAAAEABIAaQwAAAQAEwBrDAAABAAQAGoMAAACABQAbAwAAAIAEABtDAAAAQAFAOoMAAADAAoAAAA=.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAIQAAgJ3hNjLQBrAQhoDAAABQAwAGkMAAAEAD8AawwAAAQAQQBqDAAABAAUAGwMAAADADMAbQwAAAEAFwDqDAAABQAxAG4MAAACADYAEAAICd4TYy0AawEIaAwAAAUAMABpDAAABAA/AGsMAAAEAEEAagwAAAQAFABsDAAAAwAzAG0MAAABABcA6gwAAAUAMQBuDAAAAgA2AAAA.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAAALgAFFAMJAwAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJAwAAAA==.Jessiescool:BAABLgAECn8aAAIHAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAHAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIFAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAFAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAABLgAECn8YAAIHAAcJwCMvHwBlAgdoDAAABABgAGkMAAAFAFwAawwAAAQAWwBqDAAAAwBfAGwMAAACAGAA6gwAAAUAXQBuDAAAAQBOAAcABwnAIy8fAGUCB2gMAAAEAGAAaQwAAAUAXABrDAAABABbAGoMAAADAF8AbAwAAAIAYADqDAAABQBdAG4MAAABAE4AAAA=.',
Ka='Kalvin:BAABLgAECn8bAAIRAAgJiQ57HAB+AQhoDAAABAAlAGkMAAADADMAawwAAAMAGABqDAAAAgACAGwMAAACACgAbQwAAAIABgDqDAAACQAoAG4MAAACADoAEQAICYkOexwAfgEIaAwAAAQAJQBpDAAAAwAzAGsMAAADABgAagwAAAIAAgBsDAAAAgAoAG0MAAACAAYA6gwAAAkAKABuDAAAAgA6AAAA.Kanari:BAABLgAECn8YAAQSAAcJchKDLwAjAQdoDAAABAAzAGkMAAAEACgAawwAAAQAMwBqDAAAAwA7AGwMAAAEADEAbQwAAAIADgDqDAAAAwA+ABIABgmOFIMvACMBBmgMAAAEADMAaQwAAAIAKABrDAAAAwAzAGoMAAACADsAbAwAAAMAMQDqDAAAAgA+AAgABAmQBdpCAK4ABGkMAAABAA0AbAwAAAEAFQBtDAAAAgAOAOoMAAABAAcAEwADCcUA6WsAGQADaQwAAAEAAQBrDAAAAQACAGoMAAABAAMAAAA=.',
Ke='Kelak:BAAALgADCgEJAQAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgEJAwAAAA==.',
La='Lagoles:BAABLgAECn82AAMGAAkJzyL6AgDzAgloDAAACABiAGkMAAAIAGEAawwAAAgAYQBqDAAABgBiAGwMAAAGAFYAbQwAAAUAWADqDAAABwBNAG4MAAAEAEYAbwwAAAIAXwAGAAkJKCL6AgDzAgloDAAAAwBiAGkMAAADAGEAawwAAAMAYQBqDAAAAwBiAGwMAAACAFYAbQwAAAEATADqDAAAAQBMAG4MAAABAEYAbwwAAAIAXwAUAAgJfR+aEwCYAghoDAAABQBVAGkMAAAFAFQAawwAAAUAVgBqDAAAAwBRAGwMAAAEAFEAbQwAAAQAWADqDAAABgBNAG4MAAADADsAAAA=.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJDAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJPgAGAKckAA==.Leoben:BAAALgAECgEJAwAAAA==.',
Li='Liltracey:BAAALgAECgUJCgABLgAFFAMJCAAEAHAPAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAFADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIEAAMJRRKFLADUAANoDAAABQApAGkMAAAEABcA6gwAAAcASwAEAAMJRRKFLADUAANoDAAABQApAGkMAAAEABcA6gwAAAcASwAuAAQKfzEAAwQACQk5ICwIABADAAQACQk5ICwIABADABUAAglmDk1sAG8AAAAA.',
Mk='Mk:BAEBLgAECn87AAMMAAgJayMfBgAfAwhoDAAACgBjAGkMAAAJAGMAawwAAAkAYQBqDAAACQBhAGwMAAAHAFwAbQwAAAMAMADqDAAABwBiAG4MAAAFAGIADAAICWsjHwYAHwMIaAwAAAkAYwBpDAAACABjAGsMAAAIAGEAagwAAAgAYQBsDAAABgBcAG0MAAADADAA6gwAAAcAYgBuDAAABQBiAAIABQmmCT1LAK0ABWgMAAABABUAaQwAAAEAHABrDAAAAQAeAGoMAAABAAwAbAwAAAEAEQAAAA==.',
Mo='Monzo:BAABLgAECn8jAAMBAAgJ2iEEGQDmAghoDAAABwBbAGkMAAAHAF4AawwAAAYAXwBqDAAAAwBbAGwMAAADAE0AbQwAAAIAQADqDAAABgBhAG4MAAABAFQAAQAICdohBBkA5gIIaAwAAAYAWwBpDAAABgBeAGsMAAAGAF8AagwAAAMAWwBsDAAAAwBNAG0MAAACAEAA6gwAAAYAYQBuDAAAAQBUAAMAAgnUD5I9AFwAAmgMAAABACoAaQwAAAEAJgABLgAFFAMJCAAEAHAPAA==.Morvayne:BAABLgAECn8vAAILAAkJSRx0JABjAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwALAAkJSRx0JABjAgloDAAABwBQAGkMAAAHAEoAawwAAAYASQBqDAAABABZAGwMAAAEAFIAbQwAAAQAOgDqDAAABgBaAG4MAAAGAEcAbwwAAAMALwABLgAECgkJNgAGAM8iAA==.',
My='Myneemo:BAAALgAECgQJAwAAAA==.Myro:BAABLgAECn8VAAIHAAgJ4AZhhgA5AQhoDAAAAgAQAGkMAAADABoAawwAAAUADwBqDAAAAgAcAGwMAAADABMAbQwAAAEADwDqDAAABAAOAG4MAAABAA4ABwAICeAGYYYAOQEIaAwAAAIAEABpDAAAAwAaAGsMAAAFAA8AagwAAAIAHABsDAAAAwATAG0MAAABAA8A6gwAAAQADgBuDAAAAQAOAAAA.',
No='Nomoneydown:BAAALgAECgEJAwAAAA==.Nosam:BAABLgAECn8XAAIOAAcJixCQbQBAAQdoDAAACABBAGkMAAAFACgAawwAAAQAIQBqDAAAAgA8AGwMAAABACQAbQwAAAEAJADqDAAAAgApAA4ABwmLEJBtAEABB2gMAAAIAEEAaQwAAAUAKABrDAAABAAhAGoMAAACADwAbAwAAAEAJABtDAAAAQAkAOoMAAACACkAAAA=.',
Nt='Nthegreat:BAAALgAECgUJBQAAAA==.',
Nw='Nwf:BAABLgAECn8ZAAIQAAcJLRgvKwB3AQdoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAABAA+AGwMAAAEACMA6gwAAAQASABuDAAAAQAgABAABwktGC8rAHcBB2gMAAAEAFMAaQwAAAQARABrDAAABABPAGoMAAAEAD4AbAwAAAQAIwDqDAAABABIAG4MAAABACAAAAA=.',
['Nè']='Nèbula:BAAALgAECgYJDAAAAA==.',
Or='Ornatas:BAACLgAFFH8MAAIWAAQJMiHhCwB7AQRoDAAABQBaAGkMAAADAFYAawwAAAEATgDqDAAAAwBUABYABAkyIeELAHsBBGgMAAAFAFoAaQwAAAMAVgBrDAAAAQBOAOoMAAADAFQALgAECn8YAAIWAAgJtByWFQBvAgAWAAgJtByWFQBvAgAAAA==.',
Pa='Pandamonium:BAABLgAECn8dAAQNAAgJPBT8KwBWAQhoDAAABgAvAGkMAAAFADgAawwAAAYAOgBqDAAAAwBRAGwMAAABACIAbQwAAAEALQDqDAAABgA9AG4MAAABABwADQAICTwU/CsAVgEIaAwAAAUALwBpDAAABAA4AGsMAAAEADoAagwAAAIAUQBsDAAAAQAiAG0MAAABAC0A6gwAAAQAPQBuDAAAAQAcAAIABAn4A7ZeAGoABGgMAAABAAQAaQwAAAEADABrDAAAAgAOAGoMAAABAA0ADAABCTgJy4gAKQAB6gwAAAIAFwAAAA==.',
Pe='Perdyblues:BAAALgAECggJEAAAAA==.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgQJBQAAAA==.',
Qi='Qiana:BAAALgAECgYJCgABLgAECgkJIQASAL4bAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAIMAAgJCAyFNQD7AAhoDAAABgA8AGkMAAAFAC4AawwAAAIAEgBqDAAABAAhAGwMAAADACUAbQwAAAEABwDqDAAABQAZAG4MAAABABMADAAICQgMhTUA+wAIaAwAAAYAPABpDAAABQAuAGsMAAACABIAagwAAAQAIQBsDAAAAwAlAG0MAAABAAcA6gwAAAUAGQBuDAAAAQATAAAA.',
Ra='Rainootra:BAAALgADCgIJAgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAAALgAECggJEQAAAA==.',
Sc='Scylla:BAACLgAFFH8SAAIXAAcJvx0uAQBCAgdoDAAAAQA2AGkMAAAEAGEAawwAAAMAWgBqDAAAAgBEAGwMAAABAFoAbQwAAAEANwDqDAAABgBMABcABwm/HS4BAEICB2gMAAABADYAaQwAAAQAYQBrDAAAAwBaAGoMAAACAEQAbAwAAAEAWgBtDAAAAQA3AOoMAAAGAEwALgAECn8sAAMXAAkJACYfAADlAwAXAAkJACYfAADlAwAYAAEJpQ5FXgBCAAABLgAECgYJDwAZAAAAAA==.',
Se='Sephiroth:BAABLgAECn8VAAIHAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAHAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAAAA==.Serephant:BAAALgADCgEJAQAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgQJBQABLgAECgkJPgAGAKckAA==.',
So='Soothe:BAAALgAECgYJEAAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8eAAMHAAcJFyKpLAAjAgdoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAFAFIAbQwAAAIAWQDqDAAABQBeAAcABwkXIqksACMCB2gMAAAFAGMAaQwAAAUAUQBrDAAABQBLAGoMAAADAFUAbAwAAAUAUgBtDAAAAQBZAOoMAAAFAF4AGgABCZQDTHwALAABbQwAAAEACQAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8HAAIQAAIJXhI9MQCSAAJoDAAAAwA5AOoMAAAEACQAEAACCV4SPTEAkgACaAwAAAMAOQDqDAAABAAkAC4ABAp/HgACEAAICUMf+AwAcAIAEAAICUMf+AwAcAIAAAA=.',
Te='Tengoo:BAAALgAECgQJBAAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIHAAIJBxU+XwCgAAJoDAAAAwA3AOoMAAACADQABwACCQcVPl8AoAACaAwAAAMANwDqDAAAAgA0AAAA.Thylight:BAAALgADCgIJAgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgEJAwAAAA==.',
Ve='Veew:BAABLgAECn8XAAMQAAgJ8RGROgC8AQhoDAAABAA8AGkMAAAEAEUAawwAAAQAOgBqDAAAAwAwAGwMAAADADcAbQwAAAEAEADqDAAAAwAsAG8MAAABABAAEAAICToRkToAvAEIaAwAAAMAPABpDAAAAwBFAGsMAAADADoAagwAAAEAMABsDAAAAgAqAG0MAAABABAA6gwAAAMALABvDAAAAQAQABsABQmyEQobABkBBWgMAAABADkAaQwAAAEAPgBrDAAAAQAGAGoMAAACACQAbAwAAAEANwAAAA==.',
Vy='Vynaca:BAAALgAECgEJAwAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8oAAIcAAgJTQyATwB4AQhoDAAABwAjAGkMAAAGADMAawwAAAYAJwBqDAAABQAkAGwMAAAFABQAbQwAAAMAFwDqDAAABAAiAG4MAAAEABAAHAAICU0MgE8AeAEIaAwAAAcAIwBpDAAABgAzAGsMAAAGACcAagwAAAUAJABsDAAABQAUAG0MAAADABcA6gwAAAQAIgBuDAAABAAQAAAA.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgEJAwAAAA==.',
Yu='Yungmage:BAABLgAECn8dAAILAAcJYBuQggDMAQdoDAAABgBUAGkMAAAGAF0AawwAAAUAVwBqDAAABgBSAGwMAAABAEIAbQwAAAEAEQDqDAAABABGAAsABwlgG5CCAMwBB2gMAAAGAFQAaQwAAAYAXQBrDAAABQBXAGoMAAAGAFIAbAwAAAEAQgBtDAAAAQARAOoMAAAEAEYAAAA=.',
Za='Zaifu:BAAALgAECgEJAwAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAILAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQALAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAAAA==.',
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
