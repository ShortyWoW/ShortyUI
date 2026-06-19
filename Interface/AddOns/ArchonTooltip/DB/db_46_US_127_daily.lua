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

local lookup = {'Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Guardian','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-06-18',data={Aa='Aamon:BAAALgAECgEJAQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgUJDAAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8dAAIBAAYJDAIVOgBAAAZoDAAACAAEAGkMAAAGAAoAawwAAAYABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJDAIVOgBAAAZoDAAACAAEAGkMAAAGAAoAawwAAAYABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJDwAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh0ZMgDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh0ZMgDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIgUbABUCAAIACAnWIgUbABUCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDwAAAA==.',
Bo='Bootybleaps:BAABLgAFFH8GAAIDAAMJcBKPJgDTAANoDAAAAgAtAGkMAAACADQA6gwAAAIAKwADAAMJcBKPJgDTAANoDAAAAgAtAGkMAAACADQA6gwAAAIAKwAAAA==.Bootybsneaks:BAACLgAFFH8iAAIEAAYJziJICwDlAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAEAAYJziJICwDlAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAuAAQKfzYAAwQACQn5I9wDAAQDAAQACQn5I9wDAAQDAAUAAQl8FkgmADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIGAAYJ5AsjJwDTAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAGAAYJ5AsjJwDTAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMHAAYJUBqBLQDIAQZoDAAABAAsAGkMAAAEADcAawwAAAQARQBqDAAABgBDAGwMAAADAEYA6gwAAAQAYAAHAAYJUBqBLQDIAQZoDAAAAgAsAGkMAAACADcAawwAAAIARQBqDAAABABDAGwMAAADAEYA6gwAAAQAYAAIAAQJORaPTgDGAARoDAAAAgBBAGkMAAACADgAawwAAAIAMABqDAAAAgAuAAAA.Bullievit:BAACLgAFFH8OAAIJAAUJMxTAIQATAQVoDAAABAA8AGkMAAACACkAawwAAAMAIQBqDAAAAQAQAOoMAAAEAEcACQAFCTMUwCEAEwEFaAwAAAQAPABpDAAAAgApAGsMAAADACEAagwAAAEAEADqDAAABABHAC4ABAp/JAADCQAJCV4djBsA7gEACQAJCV4djBsA7gEACgAECS0FPJ4AjgAAAAA=.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMLAAkJRBEsCwDHAQloDAAACQArAGkMAAAJACYAawwAAAgAKgBqDAAACQAtAGwMAAAIADQAbQwAAAcAIADqDAAACQAkAG4MAAAHAFgAbwwAAAQAEwALAAkJRBEsCwDHAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAIADQAbQwAAAcAIADqDAAACAAkAG4MAAAHAFgAbwwAAAQAEwAMAAUJ7QB7WgA4AAVoDAAAAQADAGkMAAABAAAAawwAAAEAAQBqDAAAAQAJAOoMAAABAAMAAAA=.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAINAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwANAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgYJDwAAAA==.Chunly:BAABLgAECn8jAAQOAAkJShtMCwCOAgloDAAABABPAGkMAAAGAEcAawwAAAYASgBqDAAABABKAGwMAAACAEIAbQwAAAIARwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAOAAkJShtMCwCOAgloDAAABABPAGkMAAAEAEcAawwAAAQASgBqDAAAAwBKAGwMAAACAEIAbQwAAAIARwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAIAAMJIg4abgBoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQAHAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8YAAIPAAgJQxFqGQBxAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABgA1AG4MAAACADIADwAICUMRahkAcQEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAYANQBuDAAAAgAyAAAA.Cmorbones:BAAALgADCgUJBQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAOAD4kAA==.Cordi:BAAALgAECgEJAQAAAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMQAAkJcBN0IADWAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgAQAAkJkBF0IADWAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgARAAYJcBBhDwAVAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8aAAISAAgJFRzbNABFAghoDAAABQBTAGkMAAAFAE8AawwAAAUAOgBqDAAABABUAGwMAAABADsA6gwAAAQASgBuDAAAAQA0AG8MAAABAF4AEgAICRUc2zQARQIIaAwAAAUAUwBpDAAABQBPAGsMAAAFADoAagwAAAQAVABsDAAAAQA7AOoMAAAEAEoAbgwAAAEANABvDAAAAQBeAAAA.Davik:BAABLgAECn8YAAITAAYJ/gwyRwDyAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwATAAYJ/gwyRwDyAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAFFAIJAQAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIUAAgJJw2MlgBHAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAACAB0AFAAICScNjJYARwEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAgAdAAAA.',
Dr='Dracarsynimz:BAEALgAFFAIJAgAAAQ==.Dracene:BAABLgAECn8bAAIVAAgJBQiBJADxAAhoDAAABAAmAGkMAAAFABwAawwAAAUACQBqDAAAAgAUAGwMAAADAB0AbQwAAAIACQDqDAAABQAOAG4MAAABAA4AFQAICQUIgSQA8QAIaAwAAAQAJgBpDAAABQAcAGsMAAAFAAkAagwAAAIAFABsDAAAAwAdAG0MAAACAAkA6gwAAAUADgBuDAAAAQAOAAAA.Dragosa:BAAALgAECgMJBgABLgAFFAIJBAAWAAAAAA==.Driver:BAAALgAFFAMJAgABLgAFFAUJDwAXALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAWAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMHAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAHAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAIAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMYAAgJkxQ4HwAJAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AGAAICZMUOB8ACQIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABQAAQnxBNa8ASUAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hpzIwDaAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABMAAwmwGXMjANoAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABkAAwnJD6cxAMgAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEGQAJCUodVwgA8AIAGQAJCUodVwgA8AIAEwAICeUcAw4AowIAGgACCTkIMnEAYgAAAAA=.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAwAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAOAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8NAAIbAAQJZyCtKwBbAQRoDAAABABfAGkMAAADAFwAawwAAAEAMwDqDAAABQBbABsABAlnIK0rAFsBBGgMAAAEAF8AaQwAAAMAXABrDAAAAQAzAOoMAAAFAFsALgAECn9JAAIbAAkJiCVpAgBqAwAbAAkJiCVpAgBqAwAAAA==.',
Im='Imnotyourdad:BAAALgAECgEJAQAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAbAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIOAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAA4ABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8UAAIKAAYJwA/BHAB0AQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAYASAAKAAYJwA/BHAB0AQZoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAGwMAAABABMA6gwAAAYASAAuAAQKfzEAAwoACQmzIcAFAFsDAAoACQmzIcAFAFsDAAkAAQkAAGmwAAAAAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIUAAYJCBUEJAB4AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAUAAYJCBUEJAB4AQZoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAGwMAAABAD0A6gwAAAMAOwAuAAQKfygAAhQACQlGIc4XALQCABQACQlGIc4XALQCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx1MAgCQAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEwAICScdTAIAkAIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEwAJCSUmQAEAwAMAEwAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIcAAYJMQ7svAACAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAcAAYJMQ7svAACAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn8+AAMTAAkJdROOHADgAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADQBEAG4MAAAFABgAbwwAAAMAKwATAAkJdROOHADgAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwAZAAEJSwwZfQAvAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8MAAIZAAQJtBeTAQCcAARoDAAABABDAGkMAAAEADUAawwAAAEAOQDqDAAAAwBAABkABAm0F5MBAJwABGgMAAAEAEMAaQwAAAQANQBrDAAAAQA5AOoMAAADAEAAAAA=.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIPAAkJZiIlBgCtAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAPAAkJZiIlBgCtAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIPAAkJHx6/BQC3AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAPAAkJHx6/BQC3AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAQJDwAMAMAaAA==.',
Me='Melarac:BAABLgAECn8XAAQKAAgJMws6awDzAAhoDAAABAAJAGkMAAAEACAAawwAAAQADABqDAAAAwAjAGwMAAABAFgA6gwAAAUADABuDAAAAQASAG8MAAABABMACgAHCdsHOmsA8wAHaAwAAAEACQBpDAAAAQAgAGsMAAABAAwAagwAAAEAIwDqDAAAAQAMAG4MAAABABIAbwwAAAEAEwAJAAYJjQlXUADMAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAdAAUJ1AblVgBeAAVoDAAAAgATAGkMAAACABEAawwAAAIADwBqDAAAAQANAOoMAAACABAAAAA=.',
Mi='Minibow:BAAALgAECgQJBgAAAA==.Minimagic:BAACLgAFFH8XAAMSAAUJNRyBUwA2AQVoDAAABgBOAGkMAAAFAEwAawwAAAMATQBqDAAAAQBWAOoMAAAIADgAEgAFCTUcgVMANgEFaAwAAAUATgBpDAAABQBMAGsMAAADAE0AagwAAAEAVgDqDAAACAA4AB4AAQkECEMHAEAAAWgMAAABABQALgAECn88AAISAAkJSCTDCgAjAwASAAkJSCTDCgAjAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monker:BAABLgAECn8hAAQHAAgJzh4lHAA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEABwAHCa4eJRwANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAIAAUJ7htEMQA9AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoADgAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.Mookake:BAAALgADCgMJAwAAAA==.',
Mu='Muth:BAAALgAECgYJCwAAAA==.Muthra:BAAALgAECgEJAQABLgAECgYJCwAWAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgYJCwAWAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAISAAIJ8xuQmACbAAJoDAAABABIAOoMAAAEAEYAEgACCfMbkJgAmwACaAwAAAQASADqDAAABABGAC4ABAp/OAACEgAICV8j+yAA8AIAEgAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgcJEwAAAA==.',
Ni='Niftyshiftyy:BAAALgADCgMJAwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIQAAQJpBS0KgAcAQRoDAAAAgBWAGkMAAABAC0AawwAAAEAFwDqDAAAAgA5ABAABAmkFLQqABwBBGgMAAACAFYAaQwAAAEALQBrDAAAAQAXAOoMAAACADkALgAECn8ZAAIQAAkJACOkAwAzAwAQAAkJACOkAwAzAwABLgAFFAkJKQAQAFMaAA==.Nitalzit:BAAALgAECgIJAgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIQANAH0WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAOAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJBgAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIcAAQJ1gQRkADrAARoDAAAAgAPAGkMAAABAAgAawwAAAEABgDqDAAAAQATABwABAnWBBGQAOsABGgMAAACAA8AaQwAAAEACABrDAAAAQAGAOoMAAABABMALgAECn8eAAIcAAkJJBQ5SQDmAQAcAAkJJBQ5SQDmAQAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Ph='Pharrel:BAAALgADCgMJAwAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAOAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMDAAgJ2R7wBwB3AghoDAAABABcAGkMAAAFAF0AawwAAAUARwBqDAAAAgBeAGwMAAADAEkAbQwAAAIATgDqDAAABQBaAG4MAAABADUAAwAICdke8AcAdwIIaAwAAAQAXABpDAAABABdAGsMAAAFAEcAagwAAAIAXgBsDAAAAwBJAG0MAAACAE4A6gwAAAUAWgBuDAAAAQA1AAIAAQntGWCZAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgYJCwAWAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAFFAEJAQABLgAFFAYJFAAKAMAPAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhSmLwCQAQdoDAAABQBEAGkMAAAFAD0AawwAAAIARABqDAAAAgBEAGwMAAABABkAbQwAAAEAEgDqDAAABABFAAIABwlSFKYvAJABB2gMAAAFAEQAaQwAAAUAPQBrDAAAAgBEAGoMAAACAEQAbAwAAAEAGQBtDAAAAQASAOoMAAAEAEUAAAA=.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAGAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDwAAAA==.',
Sh='Shammtastiç:BAABLgAECn8/AAIfAAkJIhhdGgAOAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAADABRAG4MAAAGAE8AbwwAAAIAIgAfAAkJIhhdGgAOAgloDAAACgBPAGkMAAAKAFIAawwAAAsATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAADABRAG4MAAAGAE8AbwwAAAIAIgAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMcAAgJsg18eQBxAQhoDAAABgAvAGkMAAAHAB8AawwAAAcAEwBqDAAABgAoAGwMAAAGADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAHAAICbINfHkAcQEIaAwAAAYALwBpDAAABgAfAGsMAAAHABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAsABAn8BWIyAFMABGkMAAABABIAagwAAAIACQBsDAAAAQATAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8nAAMEAAcJoxmmCQAGAgdoDAAACQBfAGkMAAAJAGEAawwAAAgASQBqDAAABAAnAG0MAAABAAUA6gwAAAcAWwBuDAAAAQAfAAQABwmjGaYJAAYCB2gMAAAJAF8AaQwAAAgAYQBrDAAACABJAGoMAAAEACcAbQwAAAEABQDqDAAABwBbAG4MAAABAB8ABQABCTkNPAYAXAABaQwAAAEAIQAuAAQKfyoAAwQACQkPJCgCAJADAAQACQkPJCgCAJADAAUABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIGAAUJaReBBgBFAQVoDAAAAwA6AGkMAAACACIAagwAAAEANwBsDAAAAQA7AOoMAAADAFcABgAFCWkXgQYARQEFaAwAAAMAOgBpDAAAAgAiAGoMAAABADcAbAwAAAEAOwDqDAAAAwBXAC4ABAp/GwACBgAJCfYhOwQA3QIABgAJCfYhOwQA3QIAAAA=.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8wAAMRAAgJyRkeAABZAQhoDAAACQBRAGkMAAAJAEEAawwAAAkASwBqDAAABgBIAGwMAAAGAFAAbQwAAAEAOwDqDAAABwBWAG4MAAABAA4AEQAHCSYdHgAAWQEHaAwAAAkAUQBpDAAABABBAGsMAAAGAEsAagwAAAYASABsDAAABgBQAG0MAAABADsA6gwAAAYAVgAQAAQJawwuZQCrAARpDAAABQAkAGsMAAADACcA6gwAAAEAJQBuDAAAAQAOAAEuAAUUBAkPAAwAwBoA.Syrieal:BAACLgAFFH8PAAIMAAQJwBpeFwAuAQRoDAAABQBOAGkMAAAEAEkAawwAAAEASgDqDAAABQAvAAwABAnAGl4XAC4BBGgMAAAFAE4AaQwAAAQASQBrDAAAAQBKAOoMAAAFAC8ALgAECn9DAAMMAAkJ1B/VBgCwAgAMAAkJwB7VBgCwAgALAAgJZhigCAACAgAAAA==.',
Ta='Taiyla:BAACLgAFFH8KAAISAAQJoQb9cgD6AARoDAAAAwAcAGkMAAADABMAawwAAAEABgDqDAAAAwANABIABAmhBv1yAPoABGgMAAADABwAaQwAAAMAEwBrDAAAAQAGAOoMAAADAA0ALgAECn8+AAISAAkJpha5MQBSAgASAAkJpha5MQBSAgAAAA==.Talithiala:BAAALgAECgYJEAAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMHAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ABwAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAA4ABwmKCqpeAJ0AB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8YAAIGAAgJzg8sFgBnAQhoDAAAAgAZAGkMAAADADcAawwAAAMAMQBqDAAAAwA0AGwMAAAEADEAbQwAAAIAKwDqDAAABgAaAG4MAAABACIABgAICc4PLBYAZwEIaAwAAAIAGQBpDAAAAwA3AGsMAAADADEAagwAAAMANABsDAAABAAxAG0MAAACACsA6gwAAAYAGgBuDAAAAQAiAAAA.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJCQABLgAFFAYJFAAKAMAPAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECggJGgASABUcAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAgAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAhAAcJBw3xGwAhAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORnBFQBjAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAhAAYJORnBFQBjAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKAAaABwcAA==.Unilock:BAACLgAFFH8KAAIXAAQJ8RQuSwAwAQRoDAAAAwAwAGkMAAADAFIAawwAAAEALwDqDAAAAwAjABcABAnxFC5LADABBGgMAAADADAAaQwAAAMAUgBrDAAAAQAvAOoMAAADACMALgAECn8gAAIXAAkJshmXKAA5AgAXAAkJshmXKAA5AgABLgAFFAcJKAAaABwcAA==.Unipray:BAACLgAFFH8oAAMaAAcJHByLBQAJAgdoDAAACABAAGkMAAAIAF8AawwAAAcAOgBqDAAABQBXAGwMAAABACsAbQwAAAEANgDqDAAACgBjABoABwkcHIsFAAkCB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAIAGMAEwAFCZ8aUBUAOgEFaAwAAAQASQBpDAAAAwBOAGsMAAADADcAagwAAAIASwDqDAAAAgBBAC4ABAp/JwADGgAJCbAiUAEAbwMAGgAJCbAiUAEAbwMAEwAHCeseWh4A0wEAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIeAAYJcgENFABMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAeAAYJcgENFABMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgADCgEJAQABLgAFFAYJFAAKAMAPAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAgJLAAcADUlAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAWAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRavAgAfAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRavAgAfAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIbAAgJARBGVACmAQhoDAAABwBEAGkMAAAIADAAawwAAAoAIwBqDAAABQAeAGwMAAAGAEEAbQwAAAQADADqDAAABQAeAG4MAAAGABkAGwAICQEQRlQApgEIaAwAAAcARABpDAAACAAwAGsMAAAKACMAagwAAAUAHgBsDAAABgBBAG0MAAAEAAwA6gwAAAUAHgBuDAAABgAZAAAA.',
Yo='You:BAABLgAECn8kAAIMAAkJsxcEFgC6AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAMAAkJsxcEFgC6AQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8HAAMMAAMJMB7sHgDvAANoDAAAAgAzAGkMAAABAFAA6gwAAAQAYwAMAAMJMB7sHgDvAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAYwAcAAEJ4wJaJAEyAAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAWAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCAAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxVOJQC+AQhoDAAAAwAtAGkMAAAFADwAawwAAAUASQBqDAAAAgBQAGwMAAADAEMAbQwAAAIAMgDqDAAAAwAzAG4MAAABACQAHwAICZcVTiUAvgEIaAwAAAMALQBpDAAABQA8AGsMAAAFAEkAagwAAAIAUABsDAAAAwBDAG0MAAACADIA6gwAAAMAMwBuDAAAAQAkAAAA.Zeuz:BAAALgADCgEJAQAAAA==.',
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
