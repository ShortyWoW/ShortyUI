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
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-06-17',data={Aa='Aamon:BAAALgAECgEJAQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgUJDAAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8aAAIBAAYJYAESOgBAAAZoDAAABwADAGkMAAAFAAIAawwAAAUABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJYAESOgBAAAZoDAAABwADAGkMAAAFAAIAawwAAAUABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJDwAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh39MQDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh39MQDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIgEbABUCAAIACAnWIgEbABUCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDwAAAA==.',
Bo='Bootybleaps:BAABLgAFFH8GAAIDAAMJcBJqJgDUAANoDAAAAgAtAGkMAAACADQA6gwAAAIAKwADAAMJcBJqJgDUAANoDAAAAgAtAGkMAAACADQA6gwAAAIAKwAAAA==.Bootybsneaks:BAACLgAFFH8iAAIEAAYJziI8CwDlAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAEAAYJziI8CwDlAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAuAAQKfzYAAwQACQn5I9kDAAQDAAQACQn5I9kDAAQDAAUAAQl8FkMmADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIGAAYJ5AsXJwDTAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAGAAYJ5AsXJwDTAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMHAAYJUBpxLQDIAQZoDAAABAAsAGkMAAAEADcAawwAAAQARQBqDAAABgBDAGwMAAADAEYA6gwAAAQAYAAHAAYJUBpxLQDIAQZoDAAAAgAsAGkMAAACADcAawwAAAIARQBqDAAABABDAGwMAAADAEYA6gwAAAQAYAAIAAQJORaATgDGAARoDAAAAgBBAGkMAAACADgAawwAAAIAMABqDAAAAgAuAAEuAAQKCAkkAAkAGhwA.Bullievit:BAACLgAFFH8OAAIKAAUJMxS4IQATAQVoDAAABAA8AGkMAAACACkAawwAAAMAIQBqDAAAAQAQAOoMAAAEAEcACgAFCTMUuCEAEwEFaAwAAAQAPABpDAAAAgApAGsMAAADACEAagwAAAEAEADqDAAABABHAC4ABAp/JAADCgAJCV4dhxsA7gEACgAJCV4dhxsA7gEACwAECS0FPJ4AjgAAAAA=.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMMAAkJRBEnCwDHAQloDAAACQArAGkMAAAJACYAawwAAAgAKgBqDAAACQAtAGwMAAAIADQAbQwAAAcAIADqDAAACQAkAG4MAAAHAFgAbwwAAAQAEwAMAAkJRBEnCwDHAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAIADQAbQwAAAcAIADqDAAACAAkAG4MAAAHAFgAbwwAAAQAEwANAAUJ7QBuWgA4AAVoDAAAAQADAGkMAAABAAAAawwAAAEAAQBqDAAAAQAJAOoMAAABAAMAAAA=.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAIOAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAOAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgYJDwAAAA==.Chunly:BAABLgAECn8jAAQPAAkJShtJCwCOAgloDAAABABPAGkMAAAGAEcAawwAAAYASgBqDAAABABKAGwMAAACAEIAbQwAAAIARwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAPAAkJShtJCwCOAgloDAAABABPAGkMAAAEAEcAawwAAAQASgBqDAAAAwBKAGwMAAACAEIAbQwAAAIARwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAIAAMJIg4KbgBoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQAHAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8YAAIQAAgJQxFiGQBxAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABgA1AG4MAAACADIAEAAICUMRYhkAcQEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAYANQBuDAAAAgAyAAAA.Cmorbones:BAAALgADCgUJBQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAPAD4kAA==.Cordi:BAAALgAECgEJAQAAAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMRAAkJcBNwIADWAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgARAAkJkBFwIADWAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgASAAYJcBBgDwAVAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8aAAITAAgJFRzXNABFAghoDAAABQBTAGkMAAAFAE8AawwAAAUAOgBqDAAABABUAGwMAAABADsA6gwAAAQASgBuDAAAAQA0AG8MAAABAF4AEwAICRUc1zQARQIIaAwAAAUAUwBpDAAABQBPAGsMAAAFADoAagwAAAQAVABsDAAAAQA7AOoMAAAEAEoAbgwAAAEANABvDAAAAQBeAAAA.Davik:BAABLgAECn8YAAIUAAYJ/gwkRwDyAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAUAAYJ/gwkRwDyAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAFFAIJAQAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIVAAgJJw1plgBHAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAACAB0AFQAICScNaZYARwEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAgAdAAAA.',
Dr='Dracarsynimz:BAEALgAFFAIJAgAAAQ==.Dracene:BAABLgAECn8bAAIWAAgJBQh7JADxAAhoDAAABAAmAGkMAAAFABwAawwAAAUACQBqDAAAAgAUAGwMAAADAB0AbQwAAAIACQDqDAAABQAOAG4MAAABAA4AFgAICQUIeyQA8QAIaAwAAAQAJgBpDAAABQAcAGsMAAAFAAkAagwAAAIAFABsDAAAAwAdAG0MAAACAAkA6gwAAAUADgBuDAAAAQAOAAAA.Dragosa:BAAALgAECgMJBgABLgAFFAIJBAAXAAAAAA==.Driver:BAAALgAFFAMJAgABLgAFFAUJDwAYALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAXAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMHAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAHAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAIAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMZAAgJkxQ0HwAJAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AGQAICZMUNB8ACQIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABUAAQnxBEu8ASUAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMUAAQJ8hpdIwDaAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABQAAwmwGV0jANoAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABoAAwnJD5YxAMgAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEGgAJCUodUggA8AIAGgAJCUodUggA8AIAFAAICeUcAw4AowIAGwACCTkIMnEAYgAAAAA=.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAwAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAPAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8MAAIcAAQJZyBeKwBbAQRoDAAABABfAGkMAAADAFwAawwAAAEAMwDqDAAABABbABwABAlnIF4rAFsBBGgMAAAEAF8AaQwAAAMAXABrDAAAAQAzAOoMAAAEAFsALgAECn9JAAIcAAkJiCVoAgBqAwAcAAkJiCVoAgBqAwAAAA==.',
Im='Imnotyourdad:BAAALgADCgMJAwAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAcAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIPAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAA8ABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8TAAILAAYJ8A6tHAB0AQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAUAOwALAAYJ8A6tHAB0AQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAUAOwAuAAQKfzEAAwsACQmzIb4FAFsDAAsACQmzIb4FAFsDAAoAAQkAAD+wAAAAAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIVAAYJCBXUIwB4AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAVAAYJCBXUIwB4AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAuAAQKfygAAhUACQlGIckXALQCABUACQlGIckXALQCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAIUAAgJJx1FAgCQAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAFAAICScdRQIAkAIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACFAAJCSUmQAEAwAMAFAAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIdAAYJMQ4zvAAEAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAdAAYJMQ4zvAAEAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn8+AAMUAAkJdROIHADgAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADQBEAG4MAAAFABgAbwwAAAMAKwAUAAkJdROIHADgAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwAaAAEJSwzofAAvAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8MAAIaAAQJtBdOAACrAARoDAAABABDAGkMAAAEADUAawwAAAEAOQDqDAAAAwBAABoABAm0F04AAKsABGgMAAAEAEMAaQwAAAQANQBrDAAAAQA5AOoMAAADAEAAAAA=.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIQAAkJZiIjBgCtAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAQAAkJZiIjBgCtAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIQAAkJHx6+BQC3AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAQAAkJHx6+BQC3AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAQJDwANAMAaAA==.',
Me='Melarac:BAABLgAECn8XAAQLAAgJMwstawDzAAhoDAAABAAJAGkMAAAEACAAawwAAAQADABqDAAAAwAjAGwMAAABAFgA6gwAAAUADABuDAAAAQASAG8MAAABABMACwAHCdsHLWsA8wAHaAwAAAEACQBpDAAAAQAgAGsMAAABAAwAagwAAAEAIwDqDAAAAQAMAG4MAAABABIAbwwAAAEAEwAKAAYJjQlGUADMAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAJAAUJ1AbMVgBeAAVoDAAAAgATAGkMAAACABEAawwAAAIADwBqDAAAAQANAOoMAAACABAAAAA=.',
Mi='Minibow:BAAALgAECgQJBgAAAA==.Minimagic:BAACLgAFFH8XAAMTAAUJNRxRUwA2AQVoDAAABgBOAGkMAAAFAEwAawwAAAMATQBqDAAAAQBWAOoMAAAIADgAEwAFCTUcUVMANgEFaAwAAAUATgBpDAAABQBMAGsMAAADAE0AagwAAAEAVgDqDAAACAA4AB4AAQkECDoHAEAAAWgMAAABABQALgAECn88AAITAAkJSCS8CgAjAwATAAkJSCS8CgAjAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monker:BAABLgAECn8hAAQHAAgJzh4ZHAA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEABwAHCa4eGRwANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAIAAUJ7hs/MQA9AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoADwAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.Mookake:BAAALgADCgMJAwAAAA==.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAXAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAXAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAITAAIJ8xtamACbAAJoDAAABABIAOoMAAAEAEYAEwACCfMbWpgAmwACaAwAAAQASADqDAAABABGAC4ABAp/OAACEwAICV8j+yAA8AIAEwAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJEgAAAA==.',
Ni='Niftyshiftyy:BAAALgADCgMJAwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIRAAQJpBSgKgAcAQRoDAAAAgBWAGkMAAABAC0AawwAAAEAFwDqDAAAAgA5ABEABAmkFKAqABwBBGgMAAACAFYAaQwAAAEALQBrDAAAAQAXAOoMAAACADkALgAECn8ZAAIRAAkJACOiAwAzAwARAAkJACOiAwAzAwABLgAFFAgJKAARAPIbAA==.Nitalzit:BAAALgAECgIJAgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIQAOAH0WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAPAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgAUAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJBgAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIdAAQJ1gTNjwDrAARoDAAAAgAPAGkMAAABAAgAawwAAAEABgDqDAAAAQATAB0ABAnWBM2PAOsABGgMAAACAA8AaQwAAAEACABrDAAAAQAGAOoMAAABABMALgAECn8eAAIdAAkJJBRDSQDnAQAdAAkJJBRDSQDnAQAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Ph='Pharrel:BAAALgADCgMJAwAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAPAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMDAAgJ2R7wBwB2AghoDAAABABcAGkMAAAFAF0AawwAAAUARwBqDAAAAgBeAGwMAAADAEkAbQwAAAIATgDqDAAABQBaAG4MAAABADUAAwAICdke8AcAdgIIaAwAAAQAXABpDAAABABdAGsMAAAFAEcAagwAAAIAXgBsDAAAAwBJAG0MAAACAE4A6gwAAAUAWgBuDAAAAQA1AAIAAQntGTSZAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAXAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAFFAEJAQABLgAFFAYJEwALAPAOAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhSdLwCQAQdoDAAABQBEAGkMAAAFAD0AawwAAAIARABqDAAAAgBEAGwMAAABABkAbQwAAAEAEgDqDAAABABFAAIABwlSFJ0vAJABB2gMAAAFAEQAaQwAAAUAPQBrDAAAAgBEAGoMAAACAEQAbAwAAAEAGQBtDAAAAQASAOoMAAAEAEUAAAA=.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAGAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDwAAAA==.',
Sh='Shammtastiç:BAABLgAECn8/AAIfAAkJIhhYGgAOAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAADABRAG4MAAAGAE8AbwwAAAIAIgAfAAkJIhhYGgAOAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAADABRAG4MAAAGAE8AbwwAAAIAIgAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAAUACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMdAAgJsg2HeQBxAQhoDAAABgAvAGkMAAAHAB8AawwAAAcAEwBqDAAABgAoAGwMAAAGADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAHQAICbINh3kAcQEIaAwAAAYALwBpDAAABgAfAGsMAAAHABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAwABAn8BVAyAFMABGkMAAABABIAagwAAAIACQBsDAAAAQATAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8nAAMEAAcJoxmaCQAGAgdoDAAACQBfAGkMAAAJAGEAawwAAAgASQBqDAAABAAnAG0MAAABAAUA6gwAAAcAWwBuDAAAAQAfAAQABwmjGZoJAAYCB2gMAAAJAF8AaQwAAAgAYQBrDAAACABJAGoMAAAEACcAbQwAAAEABQDqDAAABwBbAG4MAAABAB8ABQABCTkNPAYAXAABaQwAAAEAIQAuAAQKfyoAAwQACQkPJCgCAJADAAQACQkPJCgCAJADAAUABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIGAAUJaRd9BgBFAQVoDAAAAwA6AGkMAAACACIAagwAAAEANwBsDAAAAQA7AOoMAAADAFcABgAFCWkXfQYARQEFaAwAAAMAOgBpDAAAAgAiAGoMAAABADcAbAwAAAEAOwDqDAAAAwBXAC4ABAp/GwACBgAJCfYhOwQA3QIABgAJCfYhOwQA3QIAAAA=.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8wAAMSAAgJyRkNAABiAQhoDAAACQBRAGkMAAAJAEEAawwAAAkASwBqDAAABgBIAGwMAAAGAFAAbQwAAAEAOwDqDAAABwBWAG4MAAABAA4AEgAHCSYdDQAAYgEHaAwAAAkAUQBpDAAABABBAGsMAAAGAEsAagwAAAYASABsDAAABgBQAG0MAAABADsA6gwAAAYAVgARAAQJawwaZQCrAARpDAAABQAkAGsMAAADACcA6gwAAAEAJQBuDAAAAQAOAAEuAAUUBAkPAA0AwBoA.Syrieal:BAACLgAFFH8PAAINAAQJwBpHFwAuAQRoDAAABQBOAGkMAAAEAEkAawwAAAEASgDqDAAABQAvAA0ABAnAGkcXAC4BBGgMAAAFAE4AaQwAAAQASQBrDAAAAQBKAOoMAAAFAC8ALgAECn9DAAMNAAkJ1B/TBgCwAgANAAkJwB7TBgCwAgAMAAgJZhieCAACAgAAAA==.',
Ta='Taiyla:BAACLgAFFH8KAAITAAQJoQbTcgD6AARoDAAAAwAcAGkMAAADABMAawwAAAEABgDqDAAAAwANABMABAmhBtNyAPoABGgMAAADABwAaQwAAAMAEwBrDAAAAQAGAOoMAAADAA0ALgAECn8+AAITAAkJpha2MQBSAgATAAkJpha2MQBSAgAAAA==.Talithiala:BAAALgAECgYJEAAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMHAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ABwAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAA8ABwmKCo1eAJ0AB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8YAAIGAAgJzg8qFgBnAQhoDAAAAgAZAGkMAAADADcAawwAAAMAMQBqDAAAAwA0AGwMAAAEADEAbQwAAAIAKwDqDAAABgAaAG4MAAABACIABgAICc4PKhYAZwEIaAwAAAIAGQBpDAAAAwA3AGsMAAADADEAagwAAAMANABsDAAABAAxAG0MAAACACsA6gwAAAYAGgBuDAAAAQAiAAAA.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJCQABLgAFFAYJEwALAPAOAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECggJGgATABUcAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAgAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAhAAcJBw3oGwAhAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORm6FQBjAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAhAAYJORm6FQBjAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKAAbABwcAA==.Unilock:BAACLgAFFH8KAAIYAAQJ8RQJSwAwAQRoDAAAAwAwAGkMAAADAFIAawwAAAEALwDqDAAAAwAjABgABAnxFAlLADABBGgMAAADADAAaQwAAAMAUgBrDAAAAQAvAOoMAAADACMALgAECn8gAAIYAAkJshmOKAA5AgAYAAkJshmOKAA5AgABLgAFFAcJKAAbABwcAA==.Unipray:BAACLgAFFH8oAAMbAAcJHByEBQAJAgdoDAAACABAAGkMAAAIAF8AawwAAAcAOgBqDAAABQBXAGwMAAABACsAbQwAAAEANgDqDAAACgBjABsABwkcHIQFAAkCB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAIAGMAFAAFCZ8aRhUAOgEFaAwAAAQASQBpDAAAAwBOAGsMAAADADcAagwAAAIASwDqDAAAAgBBAC4ABAp/JwADGwAJCbAiUAEAbwMAGwAJCbAiUAEAbwMAFAAHCeseVR4A0wEAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIeAAYJcgEGFABMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAeAAYJcgEGFABMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgADCgEJAQABLgAFFAYJEwALAPAOAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAgJLAAdADUlAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAXAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRauAgAfAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRauAgAfAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIcAAgJARAyVACmAQhoDAAABwBEAGkMAAAIADAAawwAAAoAIwBqDAAABQAeAGwMAAAGAEEAbQwAAAQADADqDAAABQAeAG4MAAAGABkAHAAICQEQMlQApgEIaAwAAAcARABpDAAACAAwAGsMAAAKACMAagwAAAUAHgBsDAAABgBBAG0MAAAEAAwA6gwAAAUAHgBuDAAABgAZAAAA.',
Yo='You:BAABLgAECn8kAAINAAkJsxcBFgC6AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAANAAkJsxcBFgC6AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8HAAMNAAMJMB7PHgDvAANoDAAAAgAzAGkMAAABAFAA6gwAAAQAYwANAAMJMB7PHgDvAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAYwAdAAEJ4wKaIwEyAAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAXAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCAAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxVIJQC+AQhoDAAAAwAtAGkMAAAFADwAawwAAAUASQBqDAAAAgBQAGwMAAADAEMAbQwAAAIAMgDqDAAAAwAzAG4MAAABACQAHwAICZcVSCUAvgEIaAwAAAMALQBpDAAABQA8AGsMAAAFAEkAagwAAAIAUABsDAAAAwBDAG0MAAACADIA6gwAAAMAMwBuDAAAAQAkAAAA.Zeuz:BAAALgADCgEJAQAAAA==.',
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
