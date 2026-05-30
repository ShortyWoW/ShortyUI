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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='daily',zone=46,date='2026-05-29',data={Ak='Ako:BAAALgAECgcJCwAAAA==.',
Al='Alannaria:BAAALgAECgEJAQAAAA==.Alaris:BAAALgAFFAEJAQABLgAFFAUJIgABAN8kAA==.Alex:BAABLgAECn8ZAAMCAAkJgBdUYQCRAQloDAAAAwBDAGkMAAAEAEMAawwAAAMAQwBqDAAAAgA1AGwMAAACAEAAbQwAAAEAJwDqDAAABgBMAG4MAAADAEsAbwwAAAEAFgACAAgJKBRUYQCRAQhoDAAAAwBDAGkMAAAEAEMAawwAAAMAQwBqDAAAAQA1AGwMAAABABMA6gwAAAUATABuDAAAAgAoAG8MAAABABYAAwAFCe8XviQAEQEFagwAAAEAMABsDAAAAQBAAG0MAAABACcA6gwAAAEAQQBuDAAAAQBLAAEuAAUUBAkHAAQALgoA.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8HAAQEAAQJLgokdAC+AARoDAAAAgAXAGkMAAABABUAagwAAAEACQDqDAAAAwAgAAQAAwmRByR0AL4AA2gMAAABAAMAaQwAAAEAFQDqDAAAAwAgAAUAAQkpCfYdAEsAAWgMAAABABcABgABCQAARCcAAAABagwAAAEACQAuAAQKfzUABAQACAmQIagVAJcCAAQACAmQIagVAJcCAAYABAkgGb0lADABAAUABQlzG0cQACkBAAAA.',
Ar='Archom:BAAALgADCgYJBgAAAA==.Ares:BAAALgAECgYJBgAAAA==.',
Au='Audrey:BAACLgAFFH8HAAMHAAMJUBXKJQCJAANoDAAAAwBBAGkMAAABAAMA6gwAAAMAXgAHAAIJeg3KJQCJAAJoDAAAAwBBAGkMAAABAAMACAABCf0kAncAbgAB6gwAAAMAXgAuAAQKfyUABAgACQnYIxULAOcCAAgABwl6JBULAOcCAAcACAlnFCkWAOMBAAkACAkPGd0KAKUBAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8bAAIKAAcJ8QldPgDuAAdoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAADABcA6gwAAAUAGgBuDAAAAQADAAoABwnxCV0+AO4AB2gMAAAGAD8AaQwAAAYAFABrDAAABAARAGoMAAACACsAbAwAAAMAFwDqDAAABQAaAG4MAAABAAMAAS4ABRQDCQoACwDTCQA=.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAICAAgJKiIZGwDbAghoDAAACABhAGkMAAAHAGEAawwAAAYASwBqDAAABABZAGwMAAAEAFoAbQwAAAMAVwDqDAAABwBZAG4MAAACAEoAAgAICSoiGRsA2wIIaAwAAAgAYQBpDAAABwBhAGsMAAAGAEsAagwAAAQAWQBsDAAABABaAG0MAAADAFcA6gwAAAcAWQBuDAAAAgBKAAEuAAUUAwkKAAwA9B8A.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn82AAINAAkJ7Q9vAwDTAQloDAAACAAmAGkMAAAHADMAawwAAAgALABqDAAACAAzAGwMAAAIAD4AbQwAAAQAGQDqDAAACAAbAG4MAAACAC4AbwwAAAEAHQANAAkJ7Q9vAwDTAQloDAAACAAmAGkMAAAHADMAawwAAAgALABqDAAACAAzAGwMAAAIAD4AbQwAAAQAGQDqDAAACAAbAG4MAAACAC4AbwwAAAEAHQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIPAAYJGwf0GgAVAQZoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAGwMAAABACAA6gwAAAQAEgAPAAYJGwf0GgAVAQZoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAGwMAAABACAA6gwAAAQAEgAuAAQKfyMAAg8ACQlMGaYbACUCAA8ACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAOAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn8vAAIQAAkJGiO9AQAiAwloDAAABwBdAGkMAAAGAF4AawwAAAcAXwBqDAAABwBhAGwMAAAHAF4AbQwAAAMAWgDqDAAABwBbAG4MAAACAEsAbwwAAAEAUwAQAAkJGiO9AQAiAwloDAAABwBdAGkMAAAGAF4AawwAAAcAXwBqDAAABwBhAGwMAAAHAF4AbQwAAAMAWgDqDAAABwBbAG4MAAACAEsAbwwAAAEAUwAAAA==.Daedalos:BAAALgAECgkJCQAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgYJCQAAAA==.Danekriste:BAABLgAECn8SAAIRAAYJyQVrvACMAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAARAAYJyQVrvACMAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAAAA==.Darkenedone:BAACLgAFFH8iAAIDAAYJ2h63BwDCAQZoDAAACQBXAGkMAAAIAFoAawwAAAUAUgBqDAAABABDAGwMAAABACwA6gwAAAcAWgADAAYJ2h63BwDCAQZoDAAACQBXAGkMAAAIAFoAawwAAAUAUgBqDAAABABDAGwMAAABACwA6gwAAAcAWgAuAAQKfyEAAwMACQlCIhgEAOQCAAMACQlCIhgEAOQCAAIAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgAECgIJAgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAOAAAAAA==.Demono:BAABLgAECn8WAAIRAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgARAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgABLgAFFAcJHAASAAkjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAAALgAECgcJCQAAAA==.',
Dr='Drfrangelico:BAABLgAECn8aAAMBAAgJqBEyKQCrAQhoDAAABAA2AGkMAAAEAEYAawwAAAQAMgBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAAAwAlAG4MAAADAC0AAQAICagRMikAqwEIaAwAAAMANgBpDAAAAwBGAGsMAAADADIAagwAAAIAHQBsDAAAAgAmAG0MAAABACMA6gwAAAIAJQBuDAAAAQAtABMACAnpBqWkABIBCGgMAAABABUAaQwAAAEAFABrDAAAAQANAGoMAAABABgAbAwAAAEACQBtDAAAAQAkAOoMAAABAAkAbgwAAAIADAAAAA==.Druido:BAACLgAFFH8cAAISAAcJCSPoAgDJAgdoDAAABQBdAGkMAAAFAF0AawwAAAUAXgBqDAAAAwBaAGwMAAABAE4AbQwAAAEAUADqDAAACABgABIABwkJI+gCAMkCB2gMAAAFAF0AaQwAAAUAXQBrDAAABQBeAGoMAAADAFoAbAwAAAEATgBtDAAAAQBQAOoMAAAIAGAALgAECn8yAAMSAAkJ2CUtAADvAwASAAkJ2CUtAADvAwAPAAQJ6CFiLwBFAQAAAA==.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8VAAIUAAUJACLaAQB6AQVoDAAABgBbAGkMAAAFAFQAawwAAAMAUQBqDAAAAQAXAOoMAAAGAFoAFAAFCQAi2gEAegEFaAwAAAYAWwBpDAAABQBUAGsMAAADAFEAagwAAAEAFwDqDAAABgBaAC4ABAp/KwACFAAJCXcjKAEAJwMAFAAJCXcjKAEAJwMAAAA=.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8eAAIVAAgJ4iH9CADpAghoDAAABABbAGkMAAAFAF0AawwAAAYAWQBqDAAABQBdAGwMAAAEAFsAbQwAAAEAUQDqDAAAAwBKAG4MAAACAEwAFQAICeIh/QgA6QIIaAwAAAQAWwBpDAAABQBdAGsMAAAGAFkAagwAAAUAXQBsDAAABABbAG0MAAABAFEA6gwAAAMASgBuDAAAAgBMAAAA.',
Eo='Eocháid:BAAALgAECgEJAQABLgAFFAIJAgAOAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAAEAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMIAAcJOQUZkQD/AAdoDAAABwAKAGkMAAAHAAkAawwAAAcADQBqDAAABQAKAGwMAAAFABoAbQwAAAEABwDqDAAABAAMAAgABwk5BRmRAP8AB2gMAAAGAAoAaQwAAAYACQBrDAAABgANAGoMAAAEAAoAbAwAAAQAGgBtDAAAAQAHAOoMAAADAAwACQAGCQ0C0SYAagAGaAwAAAEABgBpDAAAAQAIAGsMAAABAAQAagwAAAEAAABsDAAAAQAEAOoMAAABAAEAAAA=.Friarstrange:BAABLgAECn8UAAIVAAYJqAxyTgD5AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAVAAYJqAxyTgD5AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMSAAkJwR0AKgAKAgloDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0AbQwAAAEAMgDqDAAABgBVAG4MAAABAEAAbwwAAAEAPQASAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQAWAAMJQhLdJAC6AANtDAAAAQA1AG4MAAABACAAbwwAAAEANgAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJQAAXAGglAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQhoDAAABAAsAGkMAAAEADYAawwAAAMAQABqDAAAAwA8AGwMAAADAC0AbQwAAAEAEwDqDAAAAwAzAG4MAAABABAAEwAICX4Q5lIA6AEIaAwAAAQALABpDAAABAA2AGsMAAADAEAAagwAAAMAPABsDAAAAwAtAG0MAAABABMA6gwAAAMAMwBuDAAAAQAQAAAA.Harakki:BAABLgAECn8vAAMYAAkJihNYCQCrAQloDAAABwBRAGkMAAAGAEMAawwAAAcALwBqDAAABwA5AGwMAAAHADMAbQwAAAMAJADqDAAABwAyAG4MAAACACUAbwwAAAEAGgAYAAgJ3xRYCQCrAQhoDAAABwBRAGkMAAAGAEMAawwAAAcALwBqDAAABwA5AGwMAAAHADMAbQwAAAMAJADqDAAABwAyAG4MAAACACUAAwABCTsKdlAAOQABbwwAAAEAGgAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCwAOAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIBAAcJ/yGDEAB+AgdoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcAbQwAAAEATgDqDAAAAwBgAAEABwn/IYMQAH4CB2gMAAAFAFMAaQwAAAYAUABrDAAABQBfAGoMAAAGAFgAbAwAAAQAVwBtDAAAAQBOAOoMAAADAGAAAAA=.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAOAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMTAAYJSRNpqgAJAQZoDAAABQA2AGkMAAAFADUAawwAAAUAOQBqDAAAAgBFAGwMAAADAC4A6gwAAAUAIgATAAYJsRBpqgAJAQZoDAAABQA2AGkMAAAFADUAawwAAAQAFwBqDAAAAQAvAGwMAAADAC4A6gwAAAUAIgAZAAIJRhZEQwA+AAJrDAAAAQA5AGoMAAABAEUAAAA=.Icytouch:BAAALgAECgYJEgAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECgkJNAAKAEkhAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8iAAITAAgJ4wcbpAATAQhoDAAABwAiAGkMAAAGABMAawwAAAcAEgBqDAAAAwAXAGwMAAADAAkAbQwAAAEAJgDqDAAABgAPAG4MAAABAAQAEwAICeMHG6QAEwEIaAwAAAcAIgBpDAAABgATAGsMAAAHABIAagwAAAMAFwBsDAAAAwAJAG0MAAABACYA6gwAAAYADwBuDAAAAQAEAAAA.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgkJEwAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8nAAILAAkJjB6MGACvAgloDAAAAwBGAGkMAAAGAFcAawwAAAYAUABqDAAABABXAGwMAAAFAF0AbQwAAAIAUADqDAAABwBIAG4MAAAFADoAbwwAAAEAUAALAAkJjB6MGACvAgloDAAAAwBGAGkMAAAGAFcAawwAAAYAUABqDAAABABXAGwMAAAFAF0AbQwAAAIAUADqDAAABwBIAG4MAAAFADoAbwwAAAEAUAAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAaAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAbAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECggJDwAAAA==.',
La='Laine:BAABLgAECn8cAAIcAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAcAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8KAAIMAAMJ9B+nEQAbAQNoDAAABQBTAGkMAAADAE4A6gwAAAIAUwAMAAMJ9B+nEQAbAQNoDAAABQBTAGkMAAADAE4A6gwAAAIAUwAuAAQKfxsAAgwACQnxIJUFAOMCAAwACQnxIJUFAOMCAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQEAAcJXB70FADHAQdoDAAABwBgAGkMAAAGAGAAawwAAAUATwBqDAAABQA5AGwMAAACAFwAbQwAAAEABgDqDAAABgBfAAQABgnvI/QUAMcBBmgMAAAHAGAAaQwAAAYAYABrDAAABABPAGoMAAADADkAbAwAAAIAXADqDAAABgBfAAUAAQkAAGQEAFsAAWoMAAACADYABgACCQ4InBUAUwACawwAAAEAIgBtDAAAAQAGAC4ABAp/JAADBAAJCbcizQQAbgMABAAJCbcizQQAbgMABgABCQAAzoAADQAAAAA=.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8eAAIdAAgJuw9/HQBpAQhoDAAABABAAGkMAAAEACcAawwAAAQALQBqDAAABQAbAGwMAAAEACcAbQwAAAIACADqDAAABQA4AG4MAAACABsAHQAICbsPfx0AaQEIaAwAAAQAQABpDAAABAAnAGsMAAAEAC0AagwAAAUAGwBsDAAABAAnAG0MAAACAAgA6gwAAAUAOABuDAAAAgAbAAAA.Lunarheals:BAABLgAECn8jAAIcAAgJ7RheFAAcAghoDAAABgBIAGkMAAAHAEIAawwAAAYARABqDAAABQBGAGwMAAAFADgAbQwAAAEAGADqDAAAAwBJAG4MAAACAE0AHAAICe0YXhQAHAIIaAwAAAYASABpDAAABwBCAGsMAAAGAEQAagwAAAUARgBsDAAABQA4AG0MAAABABgA6gwAAAMASQBuDAAAAgBNAAAA.Lunasong:BAABLgAECn8aAAIIAAkJ8wbfWwB2AQloDAAABAAdAGkMAAADABMAawwAAAQAEgBqDAAABAAlAGwMAAADAAcAbQwAAAEABwDqDAAABQAaAG4MAAABAA4AbwwAAAEAEwAIAAkJ8wbfWwB2AQloDAAABAAdAGkMAAADABMAawwAAAQAEgBqDAAABAAlAGwMAAADAAcAbQwAAAEABwDqDAAABQAaAG4MAAABAA4AbwwAAAEAEwAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyguard:BAAALgAECgUJBQABLgAECgkJJwAVAPATAA==.Martyulon:BAABLgAECn8nAAMVAAkJ8BMzHwD1AQloDAAABgBJAGkMAAAFAEcAawwAAAYAOgBqDAAABgA2AGwMAAAGAC0AbQwAAAIAEADqDAAABgBCAG4MAAABACIAbwwAAAEAJQAVAAkJ8BMzHwD1AQloDAAABQBJAGkMAAAEAEcAawwAAAUAOgBqDAAABQA2AGwMAAAFAC0AbQwAAAIAEADqDAAABgBCAG4MAAABACIAbwwAAAEAJQAMAAUJHQmiUgCmAAVoDAAAAQAeAGkMAAABABgAawwAAAEAEgBqDAAAAQAWAGwMAAABABMAAAA=.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8HAAIeAAMJyRMuAgDSAANoDAAABAA6AGkMAAACAC4A6gwAAAEALwAeAAMJyRMuAgDSAANoDAAABAA6AGkMAAACAC4A6gwAAAEALwAuAAQKfyoAAh4ACQnkHDIBAJoCAB4ACQnkHDIBAJoCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn80AAQKAAkJSSFwCACaAgloDAAACQBfAGkMAAAHAFQAawwAAAcAVQBqDAAABwBbAGwMAAAHAFEAbQwAAAMAQQDqDAAACABgAG4MAAADAF0AbwwAAAEATgAKAAgJ7SBwCACaAghoDAAABwBfAGkMAAAGAFQAawwAAAYAVQBqDAAABgBbAGwMAAAGAFEAbQwAAAMAQQDqDAAABgBgAG4MAAACAFAADAAGCdse6jUASAEGaAwAAAIASgBpDAAAAQBEAGsMAAABAEQA6gwAAAIAWgBuDAAAAQBdAG8MAAABAE4AFQACCXQKJ14AVQACagwAAAEAHgBsDAAAAQAXAAAA.Monko:BAAALgAECgEJAQABLgAFFAcJHAASAAkjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAbAFwbAA==.',
Od='Odinsknight:BAABLgAECn8lAAQYAAgJMxNICgCZAQhoDAAABwAuAGkMAAAGADEAawwAAAUANABqDAAABQAyAGwMAAAEADYAbQwAAAIAGADqDAAABgA4AG4MAAACADwAGAAICYUSSAoAmQEIaAwAAAYALgBpDAAABQAxAGsMAAAEACcAagwAAAUAMgBsDAAABAA2AG0MAAACABgA6gwAAAUAOABuDAAAAgA8AAIAAwmwATsOAVgAA2gMAAABAAQAaQwAAAEABADqDAAAAQAEAAMAAQlSFAxSADQAAWsMAAABADQAAAA=.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAAALgAECgEJAQAAAA==.',
Ph='Phreek:BAABLgAECn8dAAILAAkJdxI6eQDfAQloDAAABgA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAACAA5AG4MAAABACYAbwwAAAEAGwALAAkJdxI6eQDfAQloDAAABgA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAACAA5AG4MAAABACYAbwwAAAEAGwAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn81AAISAAkJhhS9KAD4AQloDAAACQBWAGkMAAAIAEoAawwAAAgAQABqDAAABwA4AGwMAAAHAD4AbQwAAAQAGwDqDAAABwBBAG4MAAACABAAbwwAAAEAEgASAAkJhhS9KAD4AQloDAAACQBWAGkMAAAIAEoAawwAAAgAQABqDAAABwA4AGwMAAAHAD4AbQwAAAQAGwDqDAAABwBBAG4MAAACABAAbwwAAAEAEgAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn9KAAQUAAkJDhXVCADJAQloDAAADQA3AGkMAAAKACsAawwAAAoAQABqDAAACAA0AGwMAAAIAFMAbQwAAAUAKgDqDAAADABJAG4MAAAFADEAbwwAAAMAEgAUAAkJ2BLVCADJAQloDAAACQA3AGkMAAAGACkAawwAAAYAOQBqDAAABQA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAdAAcJ9hQwGwCAAQdoDAAABAAwAGkMAAADACsAawwAAAMAQABqDAAAAwA0AGwMAAABADEAbQwAAAEAKgDqDAAABABJABEAAgkpBzHiAE4AAmkMAAABABAAawwAAAEAEwAAAA==.Racinette:BAACLgAFFH8iAAIBAAUJ3yS0CQDyAQVoDAAACQBcAGkMAAAJAF0AawwAAAUAYwBqDAAABABhAOoMAAAHAFkAAQAFCd8ktAkA8gEFaAwAAAkAXABpDAAACQBdAGsMAAAFAGMAagwAAAQAYQDqDAAABwBZAC4ABAp/GgACAQAJCfskvwUAEAMAAQAJCfskvwUAEAMAAAA=.',
Re='Rebexha:BAAALgAECgUJDQAAAA==.Redia:BAAALgAECgEJAgAAAA==.Relvanas:BAABLgAECn8iAAMfAAgJ/gbVJgBBAQhoDAAABwAPAGkMAAAGABwAawwAAAUAEABqDAAABQAxAGwMAAAEAB4AbQwAAAIABwDqDAAABAASAG4MAAABAAgAHwAICf4G1SYAQQEIaAwAAAYADwBpDAAABgAcAGsMAAAFABAAagwAAAUAMQBsDAAAAwAeAG0MAAACAAcA6gwAAAMAEgBuDAAAAQAIACAAAwkpA1AhAEAAA2gMAAABAAUAbAwAAAEADgDqDAAAAQADAAAA.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8oAAIIAAkJGwMsiAASAQloDAAABgAKAGkMAAAFAAkAawwAAAYACABqDAAABgAPAGwMAAAGAAkAbQwAAAEABADqDAAABwAGAG4MAAACAAQAbwwAAAEACQAIAAkJGwMsiAASAQloDAAABgAKAGkMAAAFAAkAawwAAAYACABqDAAABgAPAGwMAAAGAAkAbQwAAAEABADqDAAABwAGAG4MAAACAAQAbwwAAAEACQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAICAAUJCgSZdQDvAAVoDAAAAQASAGkMAAACAAkAawwAAAEACABqDAAAAgAJAOoMAAABAAQAAgAFCQoEmXUA7wAFaAwAAAEAEgBpDAAAAgAJAGsMAAABAAgAagwAAAIACQDqDAAAAQAEAAAA.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwACAAoEAA==.Scuffedfaith:BAABLgAECn8bAAMhAAgJ0BovEwAmAghoDAAABABMAGkMAAAFAF8AawwAAAUAYABqDAAAAwBfAGwMAAADADgAbQwAAAIAUgDqDAAAAwAZAG4MAAACABQAIQAHCYUdLxMAJgIHaAwAAAQATABpDAAABABfAGsMAAAEAGAAagwAAAIAXwBsDAAAAwA4AG0MAAACAFIA6gwAAAIAGQAiAAUJ4QRsSQC4AAVpDAAAAQAMAGsMAAABAA0AagwAAAEAAgDqDAAAAQAOAG4MAAACAAkAAS4ABRQFCQcAAgAKBAA=.',
Se='Sefyra:BAABLgAECn8aAAIIAAcJyBMrWwB4AQdoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAADAEkA6gwAAAUAKgBuDAAAAQAhAAgABwnIEytbAHgBB2gMAAAFADMAaQwAAAUAKwBrDAAABQA8AGoMAAACAC0AbAwAAAMASQDqDAAABQAqAG4MAAABACEAAAA=.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shamroran:BAAALgAECgEJAQAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgUJCQAAAA==.Snolo:BAABLgAECn8gAAIbAAgJWBBsLABsAQhoDAAABgA3AGkMAAAGACoAawwAAAYAKwBqDAAABQA6AGwMAAAEACsAbQwAAAEAIQDqDAAAAwA0AG4MAAABABUAGwAICVgQbCwAbAEIaAwAAAYANwBpDAAABgAqAGsMAAAGACsAagwAAAUAOgBsDAAABAArAG0MAAABACEA6gwAAAMANABuDAAAAQAVAAAA.Snowyrose:BAAALgAECgMJAwABLgAFFAMJCgAMAPQfAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAAEAFweAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8KAAIPAAMJXQUTLwCVAANoDAAABQAKAGkMAAADABQA6gwAAAIACQAPAAMJXQUTLwCVAANoDAAABQAKAGkMAAADABQA6gwAAAIACQAuAAQKfzsAAw8ACQlSDOIkAIkBAA8ACQlSDOIkAIkBABIABwl5F1JGAIgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIaAAgJVRQdMABjAQhoDAAABABIAGkMAAAEAEEAawwAAAQAMQBqDAAAAwAlAGwMAAADAFEAbQwAAAEAEwDqDAAABAA5AG4MAAABABEAGgAICVUUHTAAYwEIaAwAAAQASABpDAAABABBAGsMAAAEADEAagwAAAMAJQBsDAAAAwBRAG0MAAABABMA6gwAAAQAOQBuDAAAAQARAAAA.',
Tr='Trickydice:BAAALgAECgUJBgAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMEAAgJLBKFXACzAQhoDAAABAAnAGkMAAAEAD4AawwAAAQAPgBqDAAAAwAwAGwMAAADAD4AbQwAAAEAFADqDAAABAA1AG4MAAABABkABAAICVYRhVwAswEIaAwAAAMAJwBpDAAAAgAvAGsMAAADAD4AagwAAAMAMABsDAAAAwA+AG0MAAABABQA6gwAAAQANQBuDAAAAQAZAAUAAwlxD/kYALMAA2gMAAABAAoAaQwAAAIAPgBrDAAAAQAtAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8vAAITAAkJqx+NEQDEAgloDAAABwBbAGkMAAAGAFcAawwAAAcATgBqDAAABwBbAGwMAAAHAGAAbQwAAAMAPQDqDAAABwBcAG4MAAACAEgAbwwAAAEARAATAAkJqx+NEQDEAgloDAAABwBbAGkMAAAGAFcAawwAAAcATgBqDAAABwBbAGwMAAAHAGAAbQwAAAMAPQDqDAAABwBcAG4MAAACAEgAbwwAAAEARAAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9OAAMTAAkJtCTwAwBNAwloDAAADABeAGkMAAAMAF0AawwAAAwAYgBqDAAACgBhAGwMAAAIAGEAbQwAAAUAXwDqDAAACgBgAG4MAAAGAGEAbwwAAAMATwATAAkJtCTwAwBNAwloDAAACwBeAGkMAAAMAF0AawwAAAwAYgBqDAAACgBhAGwMAAAIAGEAbQwAAAUAXwDqDAAACQBgAG4MAAAGAGEAbwwAAAMATwAZAAIJPxmMMQCCAAJoDAAAAQAtAOoMAAABAFMAAAA=.',
Wu='Wu:BAABLgAECn8WAAIMAAgJPBCCKgBMAQhoDAAABAAuAGkMAAAFADMAawwAAAQAKgBqDAAAAgApAGwMAAACAC8AbQwAAAEAIADqDAAAAwArAG4MAAABABsADAAICTwQgioATAEIaAwAAAQALgBpDAAABQAzAGsMAAAEACoAagwAAAIAKQBsDAAAAgAvAG0MAAABACAA6gwAAAMAKwBuDAAAAQAbAAEuAAUUBAkHAAQALgoA.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAQJBwAEAC4KAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8MAAIbAAQJOQ5nKQABAQRoDAAABAAsAGkMAAAEAC0AawwAAAEAFQDqDAAAAwAiABsABAk5DmcpAAEBBGgMAAAEACwAaQwAAAQALQBrDAAAAQAVAOoMAAADACIALgAECn8yAAIbAAgJgxivGwDeAQAbAAgJgxivGwDeAQAAAA==.',
Zi='Zingispingus:BAABLgAECn8fAAIPAAgJjQf7OAARAQhoDAAABgAXAGkMAAAFABEAawwAAAUAGQBqDAAABAAQAGwMAAAEABkAbQwAAAIACgDqDAAABAATAG8MAAABAA4ADwAICY0H+zgAEQEIaAwAAAYAFwBpDAAABQARAGsMAAAFABkAagwAAAQAEABsDAAABAAZAG0MAAACAAoA6gwAAAQAEwBvDAAAAQAOAAAA.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgUJDgAOAAAAAA==.',
['ßa']='ßandamonium:BAAALgAECgYJCQAAAA==.',
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
