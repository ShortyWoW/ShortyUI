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

local lookup = {'Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-06-14',data={Aa='Aamon:BAAALgAECgEJAQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgUJCwAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8aAAIBAAYJYAFKOQBAAAZoDAAABwADAGkMAAAFAAIAawwAAAUABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJYAFKOQBAAAZoDAAABwADAGkMAAAFAAIAawwAAAUABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJDwAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh35MADnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh35MADnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIo4aABgCAAIACAnWIo4aABgCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDwAAAA==.',
Bo='Bootybleaps:BAABLgAFFH8GAAIDAAMJcBJuJQDUAANoDAAAAgAtAGkMAAACADQA6gwAAAIAKwADAAMJcBJuJQDUAANoDAAAAgAtAGkMAAACADQA6gwAAAIAKwAAAA==.Bootybsneaks:BAACLgAFFH8iAAIEAAYJziKYCgDoAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAEAAYJziKYCgDoAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAuAAQKfzYAAwQACQn5I8wDAAUDAAQACQn5I8wDAAUDAAUAAQl8Fu4lADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIGAAYJ5AuDJgDTAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAGAAYJ5AuDJgDTAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMHAAYJUBrCLADHAQZoDAAABAAsAGkMAAAEADcAawwAAAQARQBqDAAABgBDAGwMAAADAEYA6gwAAAQAYAAHAAYJUBrCLADHAQZoDAAAAgAsAGkMAAACADcAawwAAAIARQBqDAAABABDAGwMAAADAEYA6gwAAAQAYAAIAAQJORb8TQDGAARoDAAAAgBBAGkMAAACADgAawwAAAIAMABqDAAAAgAuAAEuAAQKCAkkAAkAGhwA.Bullievit:BAACLgAFFH8OAAIKAAUJMxT2IAATAQVoDAAABAA8AGkMAAACACkAawwAAAMAIQBqDAAAAQAQAOoMAAAEAEcACgAFCTMU9iAAEwEFaAwAAAQAPABpDAAAAgApAGsMAAADACEAagwAAAEAEADqDAAABABHAC4ABAp/JAADCgAJCV4dTxsA7QEACgAJCV4dTxsA7QEACwAECS0FPJ4AjgAAAAA=.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMMAAkJRBHHCgDNAQloDAAACQArAGkMAAAJACYAawwAAAgAKgBqDAAACQAtAGwMAAAIADQAbQwAAAcAIADqDAAACQAkAG4MAAAHAFgAbwwAAAQAEwAMAAkJRBHHCgDNAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAIADQAbQwAAAcAIADqDAAACAAkAG4MAAAHAFgAbwwAAAQAEwANAAUJ7QB2WQA4AAVoDAAAAQADAGkMAAABAAAAawwAAAEAAQBqDAAAAQAJAOoMAAABAAMAAAA=.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAIOAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAOAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgYJDwAAAA==.Chunly:BAABLgAECn8dAAQPAAkJMBVVFQANAgloDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAPAAkJMBVVFQANAgloDAAAAwA7AGkMAAADAD0AawwAAAMAMQBqDAAAAgAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAIAAMJIg5TbQBoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQAHAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8YAAIQAAgJQxEcGQBxAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABgA1AG4MAAACADIAEAAICUMRHBkAcQEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAYANQBuDAAAAgAyAAAA.Cmorbones:BAAALgADCgUJBQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAPAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMRAAkJcBPWHwDZAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgARAAkJkBHWHwDZAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgASAAYJcBAxDwAVAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8VAAITAAcJ0hg2YQC7AQdoDAAABABOAGkMAAAEAEYAawwAAAQALgBqDAAAAwBUAGwMAAABADsA6gwAAAQASgBuDAAAAQA0ABMABwnSGDZhALsBB2gMAAAEAE4AaQwAAAQARgBrDAAABAAuAGoMAAADAFQAbAwAAAEAOwDqDAAABABKAG4MAAABADQAAAA=.Davik:BAABLgAECn8YAAIUAAYJ/gxARgD1AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAUAAYJ/gxARgD1AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJCgAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIVAAgJJw3IkwBKAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAACAB0AFQAICScNyJMASgEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAgAdAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAARAEILAQ==.Dracene:BAABLgAECn8bAAIWAAgJBQgqJADxAAhoDAAABAAmAGkMAAAFABwAawwAAAUACQBqDAAAAgAUAGwMAAADAB0AbQwAAAIACQDqDAAABQAOAG4MAAABAA4AFgAICQUIKiQA8QAIaAwAAAQAJgBpDAAABQAcAGsMAAAFAAkAagwAAAIAFABsDAAAAwAdAG0MAAACAAkA6gwAAAUADgBuDAAAAQAOAAAA.Dragosa:BAAALgAECgMJAwABLgAFFAIJBAAXAAAAAA==.Driver:BAAALgAFFAMJAgABLgAFFAUJDwAYALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAXAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMHAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAHAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAIAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMZAAgJkxTuHgAKAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AGQAICZMU7h4ACgIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABUAAQnxBNW3ASUAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMUAAQJ8hqPIgDbAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABQAAwmwGY8iANsAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABoAAwnJD4swAMkAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEGgAJCUodLwgA8gIAGgAJCUodLwgA8gIAFAAICeUcAw4AowIAGwACCTkIMnEAYgAAAAA=.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAPAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8MAAIcAAQJZyA7KQBdAQRoDAAABABfAGkMAAADAFwAawwAAAEAMwDqDAAABABbABwABAlnIDspAF0BBGgMAAAEAF8AaQwAAAMAXABrDAAAAQAzAOoMAAAEAFsALgAECn9JAAIcAAkJiCVUAgBrAwAcAAkJiCVUAgBrAwAAAA==.',
Im='Imnotyourdad:BAAALgADCgMJAwAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAcAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIPAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAA8ABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8TAAILAAYJ8A7BGwB2AQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAUAOwALAAYJ8A7BGwB2AQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAUAOwAuAAQKfy8AAgsACQmzIaIFAFsDAAsACQmzIaIFAFsDAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIVAAYJCBUgIgB5AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAVAAYJCBUgIgB5AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAuAAQKfygAAhUACQlGIWkXALUCABUACQlGIWkXALUCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAIUAAgJJx0EAgCTAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAFAAICScdBAIAkwIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACFAAJCSUmQAEAwAMAFAAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIdAAYJMQ5GugAEAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAdAAYJMQ5GugAEAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn8+AAMUAAkJdROcGwDnAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADQBEAG4MAAAFABgAbwwAAAMAKwAUAAkJdROcGwDnAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwAaAAEJSwxcewAvAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8KAAIaAAQJtBd5IwAqAQRoDAAAAwBDAGkMAAADADUAawwAAAEAOQDqDAAAAwBAABoABAm0F3kjACoBBGgMAAADAEMAaQwAAAMANQBrDAAAAQA5AOoMAAADAEAAAAA=.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIQAAkJZiIHBgCuAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAQAAkJZiIHBgCuAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIQAAkJHx6nBQC4AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAQAAkJHx6nBQC4AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAQJDwANAMAaAA==.',
Me='Melarac:BAABLgAECn8XAAQLAAgJMwukagDyAAhoDAAABAAJAGkMAAAEACAAawwAAAQADABqDAAAAwAjAGwMAAABAFgA6gwAAAUADABuDAAAAQASAG8MAAABABMACwAHCdsHpGoA8gAHaAwAAAEACQBpDAAAAQAgAGsMAAABAAwAagwAAAEAIwDqDAAAAQAMAG4MAAABABIAbwwAAAEAEwAKAAYJjQluTwDMAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAJAAUJ1AY4VQBeAAVoDAAAAgATAGkMAAACABEAawwAAAIADwBqDAAAAQANAOoMAAACABAAAAA=.',
Mi='Minibow:BAAALgAECgMJBAAAAA==.Minimagic:BAACLgAFFH8XAAMTAAUJNRzfUABBAQVoDAAABgBOAGkMAAAFAEwAawwAAAMATQBqDAAAAQBWAOoMAAAIADgAEwAFCTUc31AAQQEFaAwAAAUATgBpDAAABQBMAGsMAAADAE0AagwAAAEAVgDqDAAACAA4AB4AAQkECOQGAEAAAWgMAAABABQALgAECn88AAITAAkJSCSCCgAkAwATAAkJSCSCCgAkAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monker:BAABLgAECn8hAAQHAAgJzh6pGwA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEABwAHCa4eqRsANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAIAAUJ7hvmMAA9AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoADwAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAXAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAXAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAITAAIJ8xuWlgCeAAJoDAAABABIAOoMAAAEAEYAEwACCfMblpYAngACaAwAAAQASADqDAAABABGAC4ABAp/OAACEwAICV8j+yAA8AIAEwAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJEgAAAA==.',
Ni='Niftyshiftyy:BAAALgADCgMJAwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIRAAQJpBRPKQAfAQRoDAAAAgBWAGkMAAABAC0AawwAAAEAFwDqDAAAAgA5ABEABAmkFE8pAB8BBGgMAAACAFYAaQwAAAEALQBrDAAAAQAXAOoMAAACADkALgAECn8ZAAIRAAkJACObAwA0AwARAAkJACObAwA0AwABLgAFFAgJKAARAPIbAA==.Nitalzit:BAAALgADCgUJCAAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIQAOAH0WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAPAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgAUAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIdAAQJ1gQSjQDrAARoDAAAAgAPAGkMAAABAAgAawwAAAEABgDqDAAAAQATAB0ABAnWBBKNAOsABGgMAAACAA8AaQwAAAEACABrDAAAAQAGAOoMAAABABMALgAECn8eAAIdAAkJJBShSADmAQAdAAkJJBShSADmAQAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAPAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMDAAgJ2R7OBwB3AghoDAAABABcAGkMAAAFAF0AawwAAAUARwBqDAAAAgBeAGwMAAADAEkAbQwAAAIATgDqDAAABQBaAG4MAAABADUAAwAICdkezgcAdwIIaAwAAAQAXABpDAAABABdAGsMAAAFAEcAagwAAAIAXgBsDAAAAwBJAG0MAAACAE4A6gwAAAUAWgBuDAAAAQA1AAIAAQntGe2XAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAXAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAYJEwALAPAOAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhReLwCRAQdoDAAABQBEAGkMAAAFAD0AawwAAAIARABqDAAAAgBEAGwMAAABABkAbQwAAAEAEgDqDAAABABFAAIABwlSFF4vAJEBB2gMAAAFAEQAaQwAAAUAPQBrDAAAAgBEAGoMAAACAEQAbAwAAAEAGQBtDAAAAQASAOoMAAAEAEUAAAA=.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAGAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDwAAAA==.',
Sh='Shammtastiç:BAABLgAECn88AAIfAAkJThcCGgAPAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACwBRAG4MAAAFAEwAbwwAAAEAFQAfAAkJThcCGgAPAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACwBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAAUACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMdAAgJsg1ceABxAQhoDAAABgAvAGkMAAAHAB8AawwAAAcAEwBqDAAABgAoAGwMAAAGADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAHQAICbINXHgAcQEIaAwAAAYALwBpDAAABgAfAGsMAAAHABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAwABAn8BYkxAFMABGkMAAABABIAagwAAAIACQBsDAAAAQATAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8nAAMEAAcJoxn2CAAIAgdoDAAACQBfAGkMAAAJAGEAawwAAAgASQBqDAAABAAnAG0MAAABAAUA6gwAAAcAWwBuDAAAAQAfAAQABwmjGfYIAAgCB2gMAAAJAF8AaQwAAAgAYQBrDAAACABJAGoMAAAEACcAbQwAAAEABQDqDAAABwBbAG4MAAABAB8ABQABCTkNPAYAXAABaQwAAAEAIQAuAAQKfyoAAwQACQkPJCgCAJADAAQACQkPJCgCAJADAAUABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIGAAUJaRd8BgA9AQVoDAAAAwA6AGkMAAACACIAagwAAAEANwBsDAAAAQA7AOoMAAADAFcABgAFCWkXfAYAPQEFaAwAAAMAOgBpDAAAAgAiAGoMAAABADcAbAwAAAEAOwDqDAAAAwBXAC4ABAp/GwACBgAJCfYhOwQA3QIABgAJCfYhOwQA3QIAAAA=.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8sAAMSAAgJ8xgmBgDtAQhoDAAACABMAGkMAAAJAEEAawwAAAgASwBqDAAABgBIAGwMAAAFAFAAbQwAAAEAOwDqDAAABgBMAG4MAAABAA4AEgAHCS0cJgYA7QEHaAwAAAgATABpDAAABABBAGsMAAAFAEsAagwAAAYASABsDAAABQBQAG0MAAABADsA6gwAAAUATAARAAQJaww2YwCtAARpDAAABQAkAGsMAAADACcA6gwAAAEAJQBuDAAAAQAOAAEuAAUUBAkPAA0AwBoA.Syrieal:BAACLgAFFH8PAAINAAQJwBqrFgAxAQRoDAAABQBOAGkMAAAEAEkAawwAAAEASgDqDAAABQAvAA0ABAnAGqsWADEBBGgMAAAFAE4AaQwAAAQASQBrDAAAAQBKAOoMAAAFAC8ALgAECn9CAAMNAAkJ1B+1BgCyAgANAAkJwB61BgCyAgAMAAgJZhiJCAADAgAAAA==.',
Ta='Taiyla:BAACLgAFFH8KAAITAAQJoQbJcAADAQRoDAAAAwAcAGkMAAADABMAawwAAAEABgDqDAAAAwANABMABAmhBslwAAMBBGgMAAADABwAaQwAAAMAEwBrDAAAAQAGAOoMAAADAA0ALgAECn8+AAITAAkJphYmMQBSAgATAAkJphYmMQBSAgAAAA==.Talithiala:BAAALgAECgYJEAAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMHAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ABwAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAA8ABwmKCkpdAJ8AB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8XAAIGAAcJORD+GQA5AQdoDAAAAgAZAGkMAAADADcAawwAAAMAMQBqDAAAAwA0AGwMAAAEADEAbQwAAAIAKwDqDAAABgAaAAYABwk5EP4ZADkBB2gMAAACABkAaQwAAAMANwBrDAAAAwAxAGoMAAADADQAbAwAAAQAMQBtDAAAAgArAOoMAAAGABoAAAA=.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJBQABLgAFFAYJEwALAPAOAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECgcJFQATANIYAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAgAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAhAAcJBw13GwAiAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORmEFQBkAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAhAAYJORmEFQBkAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKAAbABwcAA==.Unilock:BAACLgAFFH8KAAIYAAQJ8RReSQAxAQRoDAAAAwAwAGkMAAADAFIAawwAAAEALwDqDAAAAwAjABgABAnxFF5JADEBBGgMAAADADAAaQwAAAMAUgBrDAAAAQAvAOoMAAADACMALgAECn8gAAIYAAkJshkNKAA7AgAYAAkJshkNKAA7AgABLgAFFAcJKAAbABwcAA==.Unipray:BAACLgAFFH8oAAMbAAcJHBwiBQAKAgdoDAAACABAAGkMAAAIAF8AawwAAAcAOgBqDAAABQBXAGwMAAABACsAbQwAAAEANgDqDAAACgBjABsABwkcHCIFAAoCB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAIAGMAFAAFCZ8ajBQAPAEFaAwAAAQASQBpDAAAAwBOAGsMAAADADcAagwAAAIASwDqDAAAAgBBAC4ABAp/JwADGwAJCbAiUAEAbwMAGwAJCbAiUAEAbwMAFAAHCeseJh4A1AEAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIeAAYJcgGXEwBMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAeAAYJcgGXEwBMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgADCgEJAQABLgAFFAYJEwALAPAOAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJKwAdAEklAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAXAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRakAgAfAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRakAgAfAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIcAAgJARAWUwCnAQhoDAAABwBEAGkMAAAIADAAawwAAAoAIwBqDAAABQAeAGwMAAAGAEEAbQwAAAQADADqDAAABQAeAG4MAAAGABkAHAAICQEQFlMApwEIaAwAAAcARABpDAAACAAwAGsMAAAKACMAagwAAAUAHgBsDAAABgBBAG0MAAAEAAwA6gwAAAUAHgBuDAAABgAZAAAA.',
Yo='You:BAABLgAECn8kAAINAAkJsxe7FQC8AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAANAAkJsxe7FQC8AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8HAAMNAAMJMB7yHQDzAANoDAAAAgAzAGkMAAABAFAA6gwAAAQAYwANAAMJMB7yHQDzAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAYwAdAAEJ4wK7HQEyAAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAXAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCAAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxXkJAC/AQhoDAAAAwAtAGkMAAAFADwAawwAAAUASQBqDAAAAgBQAGwMAAADAEMAbQwAAAIAMgDqDAAAAwAzAG4MAAABACQAHwAICZcV5CQAvwEIaAwAAAMALQBpDAAABQA8AGsMAAAFAEkAagwAAAIAUABsDAAAAwBDAG0MAAACADIA6gwAAAMAMwBuDAAAAQAkAAAA.Zeuz:BAAALgADCgEJAQAAAA==.',
Zu='Zumadin:BAAALgADCgkJBwAAAA==.Zummev:BAAALgADCgYJBAAAAA==.',
['Æs']='Æsham:BAAALgADCgQJBAAAAA==.',
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
