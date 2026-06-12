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

local lookup = {'Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-06-11',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgUJCQAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8aAAIBAAYJYAErOABBAAZoDAAABwADAGkMAAAFAAIAawwAAAUABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJYAErOABBAAZoDAAABwADAGkMAAAFAAIAawwAAAUABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJDwAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh1mLwDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh1mLwDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIikaABkCAAIACAnWIikaABkCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDwAAAA==.',
Bo='Bootybleaps:BAAALgAFFAMJAwAAAA==.Bootybsneaks:BAACLgAFFH8iAAIDAAYJziLZCQDrAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQADAAYJziLZCQDrAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAuAAQKfzUAAwMACQkiI8MEAOkCAAMACQkiI8MEAOkCAAQAAQl8FmolADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIFAAYJ5AuVJQDVAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAFAAYJ5AuVJQDVAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMGAAYJUBqgKwDHAQZoDAAABAAsAGkMAAAEADcAawwAAAQARQBqDAAABgBDAGwMAAADAEYA6gwAAAQAYAAGAAYJUBqgKwDHAQZoDAAAAgAsAGkMAAACADcAawwAAAIARQBqDAAABABDAGwMAAADAEYA6gwAAAQAYAAHAAQJORZFTQDGAARoDAAAAgBBAGkMAAACADgAawwAAAIAMABqDAAAAgAuAAEuAAQKCAkkAAgAGhwA.Bullievit:BAACLgAFFH8OAAIJAAUJMxTUHwAUAQVoDAAABAA8AGkMAAACACkAawwAAAMAIQBqDAAAAQAQAOoMAAAEAEcACQAFCTMU1B8AFAEFaAwAAAQAPABpDAAAAgApAGsMAAADACEAagwAAAEAEADqDAAABABHAC4ABAp/JAADCQAJCV4d7BoA7gEACQAJCV4d7BoA7gEACgAECS0FPJ4AjgAAAAA=.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMLAAkJRBGLCgDOAQloDAAACQArAGkMAAAJACYAawwAAAgAKgBqDAAACQAtAGwMAAAIADQAbQwAAAcAIADqDAAACQAkAG4MAAAHAFgAbwwAAAQAEwALAAkJRBGLCgDOAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAIADQAbQwAAAcAIADqDAAACAAkAG4MAAAHAFgAbwwAAAQAEwAMAAUJ7QDBVwA5AAVoDAAAAQADAGkMAAABAAAAawwAAAEAAQBqDAAAAQAJAOoMAAABAAMAAAA=.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAINAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwANAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgYJDQAAAA==.Chunly:BAABLgAECn8dAAQOAAkJMBXWFAAPAgloDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAOAAkJMBXWFAAPAgloDAAAAwA7AGkMAAADAD0AawwAAAMAMQBqDAAAAgAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAHAAMJIg5dbABoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQAGAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8XAAIPAAgJOhHHGAByAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABQA1AG4MAAACADIADwAICToRxxgAcgEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAUANQBuDAAAAgAyAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAOAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMQAAkJcBNxHwDZAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgAQAAkJkBFxHwDZAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgARAAYJcBAQDwAWAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8UAAISAAcJ0hh/YAC8AQdoDAAABABOAGkMAAAEAEYAawwAAAQALgBqDAAAAwBUAGwMAAABADsA6gwAAAMASgBuDAAAAQA0ABIABwnSGH9gALwBB2gMAAAEAE4AaQwAAAQARgBrDAAABAAuAGoMAAADAFQAbAwAAAEAOwDqDAAAAwBKAG4MAAABADQAAAA=.Davik:BAABLgAECn8YAAITAAYJ/gw0RQD1AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwATAAYJ/gw0RQD1AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJCgAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIUAAgJJw2jkQBKAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAACAB0AFAAICScNo5EASgEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAgAdAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAQAEILAQ==.Dracene:BAABLgAECn8bAAIVAAgJBQimIwDxAAhoDAAABAAmAGkMAAAFABwAawwAAAUACQBqDAAAAgAUAGwMAAADAB0AbQwAAAIACQDqDAAABQAOAG4MAAABAA4AFQAICQUIpiMA8QAIaAwAAAQAJgBpDAAABQAcAGsMAAAFAAkAagwAAAIAFABsDAAAAwAdAG0MAAACAAkA6gwAAAUADgBuDAAAAQAOAAAA.Dragosa:BAAALgAECgMJAwABLgAFFAIJBAAWAAAAAA==.Driver:BAAALgAFFAMJAgABLgAFFAUJDwAXALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAWAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMGAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAGAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAHAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMYAAgJkxSEHgAKAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AGAAICZMUhB4ACgIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABQAAQnxBFixASUAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hqDIQDbAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABMAAwmwGYMhANsAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABkAAwnJDxEvAMkAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEGQAJCUodAwgA8wIAGQAJCUodAwgA8wIAEwAICeUcAw4AowIAGgACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAOAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8MAAIbAAQJZyCiJQBlAQRoDAAABABfAGkMAAADAFwAawwAAAEAMwDqDAAABABbABsABAlnIKIlAGUBBGgMAAAEAF8AaQwAAAMAXABrDAAAAQAzAOoMAAAEAFsALgAECn9JAAIbAAkJiCUdAgBtAwAbAAkJiCUdAgBtAwAAAA==.',
Im='Imnotyourdad:BAAALgADCgMJAwAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAbAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIOAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAA4ABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8TAAIKAAYJ8A5xGgCBAQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAUAOwAKAAYJ8A5xGgCBAQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAUAOwAuAAQKfy8AAgoACQmzIYAFAFwDAAoACQmzIYAFAFwDAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIUAAYJCBUgIAB7AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAUAAYJCBUgIAB7AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAuAAQKfygAAhQACQlGIbYWALYCABQACQlGIbYWALYCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx3GAQCbAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEwAICScdxgEAmwIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEwAJCSUmQAEAwAMAEwAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIcAAYJMQ4cuAAEAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAcAAYJMQ4cuAAEAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn8+AAMTAAkJdRM7GwDnAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADQBEAG4MAAAFABgAbwwAAAMAKwATAAkJdRM7GwDnAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwAZAAEJSwz/eAAvAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8IAAIZAAMJExgwLADfAANoDAAAAwBDAGkMAAACADUA6gwAAAMAQAAZAAMJExgwLADfAANoDAAAAwBDAGkMAAACADUA6gwAAAMAQAAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIPAAkJZiLaBQCwAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAPAAkJZiLaBQCwAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIPAAkJHx5+BQC5AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAPAAkJHx5+BQC5AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAQJDAAMAMAaAA==.',
Me='Melarac:BAABLgAECn8XAAQKAAgJMwvnaQDyAAhoDAAABAAJAGkMAAAEACAAawwAAAQADABqDAAAAwAjAGwMAAABAFgA6gwAAAUADABuDAAAAQASAG8MAAABABMACgAHCdsH52kA8gAHaAwAAAEACQBpDAAAAQAgAGsMAAABAAwAagwAAAEAIwDqDAAAAQAMAG4MAAABABIAbwwAAAEAEwAJAAYJjQkxTgDNAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAIAAUJ1AYdUwBeAAVoDAAAAgATAGkMAAACABEAawwAAAIADwBqDAAAAQANAOoMAAACABAAAAA=.',
Mi='Minibow:BAAALgAECgIJAwAAAA==.Minimagic:BAACLgAFFH8XAAMSAAUJNRzuTQBGAQVoDAAABgBOAGkMAAAFAEwAawwAAAMATQBqDAAAAQBWAOoMAAAIADgAEgAFCTUc7k0ARgEFaAwAAAUATgBpDAAABQBMAGsMAAADAE0AagwAAAEAVgDqDAAACAA4AB0AAQkECH0GAEAAAWgMAAABABQALgAECn88AAISAAkJSCQkCgAmAwASAAkJSCQkCgAmAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQGAAgJzh77GgA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEABgAHCa4e+xoANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAHAAUJ7htpMAA9AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoADgAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAISAAIJ8xsxkwCjAAJoDAAABABIAOoMAAAEAEYAEgACCfMbMZMAowACaAwAAAQASADqDAAABABGAC4ABAp/OAACEgAICV8j+yAA8AIAEgAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJEgAAAA==.',
Ni='Niftyshiftyy:BAAALgADCgMJAwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIQAAQJpBQIKAAiAQRoDAAAAgBWAGkMAAABAC0AawwAAAEAFwDqDAAAAgA5ABAABAmkFAgoACIBBGgMAAACAFYAaQwAAAEALQBrDAAAAQAXAOoMAAACADkALgAECn8ZAAIQAAkJACONAwA0AwAQAAkJACONAwA0AwABLgAFFAgJIgAQAPIbAA==.Nitalzit:BAAALgADCgQJBwAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQAWAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAOAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8fAAIcAAkJJBSSRgDsAQloDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUAbQwAAAEAKADqDAAABQAvAG4MAAABADMAbwwAAAIAJgAcAAkJJBSSRgDsAQloDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUAbQwAAAEAKADqDAAABQAvAG4MAAABADMAbwwAAAIAJgAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAOAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMeAAgJ2R6kBwB4AghoDAAABABcAGkMAAAFAF0AawwAAAUARwBqDAAAAgBeAGwMAAADAEkAbQwAAAIATgDqDAAABQBaAG4MAAABADUAHgAICdkepAcAeAIIaAwAAAQAXABpDAAABABdAGsMAAAFAEcAagwAAAIAXgBsDAAAAwBJAG0MAAACAE4A6gwAAAUAWgBuDAAAAQA1AAIAAQntGW2VAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAWAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAYJEwAKAPAOAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhSWLgCSAQdoDAAABQBEAGkMAAAFAD0AawwAAAIARABqDAAAAgBEAGwMAAABABkAbQwAAAEAEgDqDAAABABFAAIABwlSFJYuAJIBB2gMAAAFAEQAaQwAAAUAPQBrDAAAAgBEAGoMAAACAEQAbAwAAAEAGQBtDAAAAQASAOoMAAAEAEUAAAA=.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAFAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn88AAIfAAkJTheGGQAQAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACwBRAG4MAAAFAEwAbwwAAAEAFQAfAAkJTheGGQAQAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACwBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMcAAgJsg0VdQB2AQhoDAAABgAvAGkMAAAHAB8AawwAAAcAEwBqDAAABgAoAGwMAAAGADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAHAAICbINFXUAdgEIaAwAAAYALwBpDAAABgAfAGsMAAAHABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAsABAn8BUMwAFMABGkMAAABABIAagwAAAIACQBsDAAAAQATAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8nAAMDAAcJoxktCAAPAgdoDAAACQBfAGkMAAAJAGEAawwAAAgASQBqDAAABAAnAG0MAAABAAUA6gwAAAcAWwBuDAAAAQAfAAMABwmjGS0IAA8CB2gMAAAJAF8AaQwAAAgAYQBrDAAACABJAGoMAAAEACcAbQwAAAEABQDqDAAABwBbAG4MAAABAB8ABAABCTkNPAYAXAABaQwAAAEAIQAuAAQKfyoAAwMACQkPJCgCAJADAAMACQkPJCgCAJADAAQABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIFAAUJaRfABQBMAQVoDAAAAwA6AGkMAAACACIAagwAAAEANwBsDAAAAQA7AOoMAAADAFcABQAFCWkXwAUATAEFaAwAAAMAOgBpDAAAAgAiAGoMAAABADcAbAwAAAEAOwDqDAAAAwBXAC4ABAp/GwACBQAJCfYhOwQA3QIABQAJCfYhOwQA3QIAAAA=.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8sAAMRAAgJ8xgQBgDuAQhoDAAACABMAGkMAAAJAEEAawwAAAgASwBqDAAABgBIAGwMAAAFAFAAbQwAAAEAOwDqDAAABgBMAG4MAAABAA4AEQAHCS0cEAYA7gEHaAwAAAgATABpDAAABABBAGsMAAAFAEsAagwAAAYASABsDAAABQBQAG0MAAABADsA6gwAAAUATAAQAAQJawzaYQCtAARpDAAABQAkAGsMAAADACcA6gwAAAEAJQBuDAAAAQAOAAEuAAUUBAkMAAwAwBoA.Syrieal:BAACLgAFFH8MAAIMAAQJwBplFQA0AQRoDAAABABOAGkMAAADAEkAawwAAAEASgDqDAAABAAvAAwABAnAGmUVADQBBGgMAAAEAE4AaQwAAAMASQBrDAAAAQBKAOoMAAAEAC8ALgAECn9BAAMMAAkJ1B99BgC0AgAMAAkJwB59BgC0AgALAAcJDhncCgDGAQAAAA==.',
Ta='Taiyla:BAACLgAFFH8HAAISAAQJ9wU9bwADAQRoDAAAAgAcAGkMAAACAA0AawwAAAEABgDqDAAAAgANABIABAn3BT1vAAMBBGgMAAACABwAaQwAAAIADQBrDAAAAQAGAOoMAAACAA0ALgAECn8+AAISAAkJphZuMABUAgASAAkJphZuMABUAgAAAA==.Talithiala:BAAALgAECgYJDwAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMGAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ABgAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAA4ABwmKCsJbAJ8AB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8WAAIFAAcJJxCAGQA6AQdoDAAAAgAZAGkMAAADADcAawwAAAMAMQBqDAAAAwA0AGwMAAAEADEAbQwAAAIAKwDqDAAABQAZAAUABwknEIAZADoBB2gMAAACABkAaQwAAAMANwBrDAAAAwAxAGoMAAADADQAbAwAAAQAMQBtDAAAAgArAOoMAAAFABkAAAA=.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJBQABLgAFFAYJEwAKAPAOAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECgcJFAASANIYAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAgAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAhAAcJBw2mGgAnAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORkZFQBmAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAhAAYJORkZFQBmAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKAAaABwcAA==.Unilock:BAACLgAFFH8KAAIXAAQJ8RSpRgAzAQRoDAAAAwAwAGkMAAADAFIAawwAAAEALwDqDAAAAwAjABcABAnxFKlGADMBBGgMAAADADAAaQwAAAMAUgBrDAAAAQAvAOoMAAADACMALgAECn8gAAIXAAkJshlqJwA8AgAXAAkJshlqJwA8AgABLgAFFAcJKAAaABwcAA==.Unipray:BAACLgAFFH8oAAMaAAcJHByqBAAQAgdoDAAACABAAGkMAAAIAF8AawwAAAcAOgBqDAAABQBXAGwMAAABACsAbQwAAAEANgDqDAAACgBjABoABwkcHKoEABACB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAIAGMAEwAFCZ8atxMAPQEFaAwAAAQASQBpDAAAAwBOAGsMAAADADcAagwAAAIASwDqDAAAAgBBAC4ABAp/JwADGgAJCbAiUAEAbwMAGgAJCbAiUAEAbwMAEwAHCese0hQARwIAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIdAAYJcgH3EgBMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAdAAYJcgH3EgBMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgADCgEJAQABLgAFFAYJEwAKAPAOAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJKwAcAEklAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAWAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRaQAgAgAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRaQAgAgAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIbAAgJARAeUQCqAQhoDAAABwBEAGkMAAAIADAAawwAAAoAIwBqDAAABQAeAGwMAAAGAEEAbQwAAAQADADqDAAABQAeAG4MAAAGABkAGwAICQEQHlEAqgEIaAwAAAcARABpDAAACAAwAGsMAAAKACMAagwAAAUAHgBsDAAABgBBAG0MAAAEAAwA6gwAAAUAHgBuDAAABgAZAAAA.',
Yo='You:BAABLgAECn8kAAIMAAkJsxdSFQC+AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAMAAkJsxdSFQC+AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8GAAMMAAMJXh2FHgDoAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAXQAMAAMJXh2FHgDoAANoDAAAAgAzAGkMAAABAFAA6gwAAAIAXQAcAAEJ4wK3FgEyAAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAWAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCAAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxU0JAC/AQhoDAAAAwAtAGkMAAAFADwAawwAAAUASQBqDAAAAgBQAGwMAAADAEMAbQwAAAIAMgDqDAAAAwAzAG4MAAABACQAHwAICZcVNCQAvwEIaAwAAAMALQBpDAAABQA8AGsMAAAFAEkAagwAAAIAUABsDAAAAwBDAG0MAAACADIA6gwAAAMAMwBuDAAAAQAkAAAA.Zeuz:BAAALgADCgEJAQAAAA==.',
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
