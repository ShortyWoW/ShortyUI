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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Warrior-Arms','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Shaman-Restoration',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='daily',zone=46,date='2026-06-03',data={Ab='Abs:BAAALgADCgEJAQAAAA==.',
Ak='Ako:BAAALgAECgkJDgAAAA==.',
Al='Alannaria:BAAALgAECgEJAQAAAA==.Alaris:BAAALgAFFAIJAgABLgAFFAUJIgABAN8kAA==.Alex:BAABLgAECn8ZAAMCAAkJgBejZQCPAQloDAAAAwBDAGkMAAAEAEMAawwAAAMAQwBqDAAAAgA1AGwMAAACAEAAbQwAAAEAJwDqDAAABgBMAG4MAAADAEsAbwwAAAEAFgACAAgJKBSjZQCPAQhoDAAAAwBDAGkMAAAEAEMAawwAAAMAQwBqDAAAAQA1AGwMAAABABMA6gwAAAUATABuDAAAAgAoAG8MAAABABYAAwAFCe8XhSYADwEFagwAAAEAMABsDAAAAQBAAG0MAAABACcA6gwAAAEAQQBuDAAAAQBLAAEuAAUUBQkLAAQA+AgA.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8LAAQEAAUJ+Ah2WQD/AAVoDAAAAwAXAGkMAAACABUAawwAAAEADQBqDAAAAgAJAOoMAAADACAABAAECYsIdlkA/wAEaAwAAAIAEwBpDAAAAgAVAGsMAAABAA0A6gwAAAMAIAAFAAEJKQk3IABLAAFoDAAAAQAXAAYAAQkAAH0pAAAAAWoMAAACAAkALgAECn81AAQEAAgJkCHHFgCUAgAEAAgJkCHHFgCUAgAGAAQJIBm9JQAwAQAFAAUJcxtHEAApAQAAAA==.',
Ar='Archom:BAAALgADCgYJBgAAAA==.Ares:BAAALgAECgYJBgAAAA==.',
At='Ataris:BAAALgAECgUJCAAAAA==.',
Au='Audrey:BAACLgAFFH8HAAMHAAMJUBXKJwCJAANoDAAAAwBBAGkMAAABAAMA6gwAAAMAXgAHAAIJeg3KJwCJAAJoDAAAAwBBAGkMAAABAAMACAABCf0kXYAAbQAB6gwAAAMAXgAuAAQKfyUABAgACQnYIyIMAOQCAAgABwl6JCIMAOQCAAcACAlnFBIXAOEBAAkACAkPGUQLAKMBAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8bAAIKAAcJ8QkZQADuAAdoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAADABcA6gwAAAUAGgBuDAAAAQADAAoABwnxCRlAAO4AB2gMAAAGAD8AaQwAAAYAFABrDAAABAARAGoMAAACACsAbAwAAAMAFwDqDAAABQAaAG4MAAABAAMAAS4ABRQDCQoACwDTCQA=.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAICAAgJKiIZGwDbAghoDAAACABhAGkMAAAHAGEAawwAAAYASwBqDAAABABZAGwMAAAEAFoAbQwAAAMAVwDqDAAABwBZAG4MAAACAEoAAgAICSoiGRsA2wIIaAwAAAgAYQBpDAAABwBhAGsMAAAGAEsAagwAAAQAWQBsDAAABABaAG0MAAADAFcA6gwAAAcAWQBuDAAAAgBKAAEuAAUUAwkKAAwA9B8A.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn88AAINAAkJUxPVAgAGAgloDAAACQA+AGkMAAAHADMAawwAAAgALABqDAAACQAzAGwMAAAJAD4AbQwAAAUAGQDqDAAACQBFAG4MAAACAC4AbwwAAAIAIQANAAkJUxPVAgAGAgloDAAACQA+AGkMAAAHADMAawwAAAgALABqDAAACQAzAGwMAAAJAD4AbQwAAAUAGQDqDAAACQBFAG4MAAACAC4AbwwAAAIAIQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIPAAYJGwdEHQAVAQZoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAGwMAAABACAA6gwAAAQAEgAPAAYJGwdEHQAVAQZoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAGwMAAABACAA6gwAAAQAEgAuAAQKfyMAAg8ACQlMGaYbACUCAA8ACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAOAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn81AAIQAAkJfyO3AQArAwloDAAACABeAGkMAAAGAF4AawwAAAcAXwBqDAAACABhAGwMAAAIAF4AbQwAAAQAWgDqDAAACABbAG4MAAACAEsAbwwAAAIAWgAQAAkJfyO3AQArAwloDAAACABeAGkMAAAGAF4AawwAAAcAXwBqDAAACABhAGwMAAAIAF4AbQwAAAQAWgDqDAAACABbAG4MAAACAEsAbwwAAAIAWgAAAA==.Daedalos:BAAALgAECgkJCQAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgYJCgAAAA==.Danekriste:BAABLgAECn8SAAIRAAYJyQVHvwCYAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAARAAYJyQVHvwCYAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAAAA==.Darkenedone:BAACLgAFFH8jAAIDAAYJ2h5NCQC7AQZoDAAACQBXAGkMAAAIAFoAawwAAAUAUgBqDAAABABDAGwMAAABACwA6gwAAAgAWgADAAYJ2h5NCQC7AQZoDAAACQBXAGkMAAAIAFoAawwAAAUAUgBqDAAABABDAGwMAAABACwA6gwAAAgAWgAuAAQKfyEAAwMACQlCIoYEAOECAAMACQlCIoYEAOECAAIAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgAECggJCwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAOAAAAAA==.Demono:BAABLgAECn8WAAIRAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgARAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgABLgAFFAcJHQASAAkjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAABLgAECn8XAAITAAgJ8QXxMgDoAAhoDAAAAwAHAGkMAAADABIAawwAAAMAEQBqDAAAAwAVAGwMAAACAAgAbQwAAAIAEwDqDAAABAAQAG4MAAADABIAEwAICfEF8TIA6AAIaAwAAAMABwBpDAAAAwASAGsMAAADABEAagwAAAMAFQBsDAAAAgAIAG0MAAACABMA6gwAAAQAEABuDAAAAwASAAAA.',
Dr='Drfrangelico:BAABLgAECn8aAAMBAAgJqBG8KgCrAQhoDAAABAA2AGkMAAAEAEYAawwAAAQAMgBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAAAwAlAG4MAAADAC0AAQAICagRvCoAqwEIaAwAAAMANgBpDAAAAwBGAGsMAAADADIAagwAAAIAHQBsDAAAAgAmAG0MAAABACMA6gwAAAIAJQBuDAAAAQAtABQACAnpBq2nABwBCGgMAAABABUAaQwAAAEAFABrDAAAAQANAGoMAAABABgAbAwAAAEACQBtDAAAAQAkAOoMAAABAAkAbgwAAAIADAAAAA==.Druido:BAACLgAFFH8dAAISAAcJCSNKAQARAgdoDAAABQBdAGkMAAAFAF0AawwAAAUAXgBqDAAAAwBaAGwMAAABAE4AbQwAAAEAUADqDAAACQBgABIABwkJI0oBABECB2gMAAAFAF0AaQwAAAUAXQBrDAAABQBeAGoMAAADAFoAbAwAAAEATgBtDAAAAQBQAOoMAAAJAGAALgAECn8yAAMSAAkJ2CUtAADvAwASAAkJ2CUtAADvAwAPAAQJ6CE0MQBEAQAAAA==.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8ZAAIVAAUJ2yL6AQCCAQVoDAAABwBbAGkMAAAGAFQAawwAAAQAWgBqDAAAAgAsAOoMAAAGAFoAFQAFCdsi+gEAggEFaAwAAAcAWwBpDAAABgBUAGsMAAAEAFoAagwAAAIALADqDAAABgBaAC4ABAp/KwACFQAJCXcjKAEAJwMAFQAJCXcjKAEAJwMAAAA=.',
Du='Dumdum:BAAALgAECgUJCgAAAA==.',
En='Enjoyby:BAABLgAECn8fAAIWAAgJ4iGmCQDpAghoDAAABABbAGkMAAAFAF0AawwAAAYAWQBqDAAABQBdAGwMAAAEAFsAbQwAAAEAUQDqDAAAAwBKAG4MAAADAEwAFgAICeIhpgkA6QIIaAwAAAQAWwBpDAAABQBdAGsMAAAGAFkAagwAAAUAXQBsDAAABABbAG0MAAABAFEA6gwAAAMASgBuDAAAAwBMAAAA.',
Eo='Eocháid:BAAALgAFFAIJAgABLgAFFAIJAgAOAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAAEAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMIAAcJOQWAlwD/AAdoDAAABwAKAGkMAAAHAAkAawwAAAcADQBqDAAABQAKAGwMAAAFABoAbQwAAAEABwDqDAAABAAMAAgABwk5BYCXAP8AB2gMAAAGAAoAaQwAAAYACQBrDAAABgANAGoMAAAEAAoAbAwAAAQAGgBtDAAAAQAHAOoMAAADAAwACQAGCQ0CQygAaQAGaAwAAAEABgBpDAAAAQAIAGsMAAABAAQAagwAAAEAAABsDAAAAQAEAOoMAAABAAEAAAA=.Friarstrange:BAABLgAECn8UAAIWAAYJqAyNUwD6AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAWAAYJqAyNUwD6AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMSAAkJwR0AKgAKAgloDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0AbQwAAAEAMgDqDAAABgBVAG4MAAABAEAAbwwAAAEAPQASAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQAXAAMJQhIOJwC6AANtDAAAAQA1AG4MAAABACAAbwwAAAEANgAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJQAATAGglAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAIUAAgJfhDmUgDoAQhoDAAABAAsAGkMAAAEADYAawwAAAMAQABqDAAAAwA8AGwMAAADAC0AbQwAAAEAEwDqDAAAAwAzAG4MAAABABAAFAAICX4Q5lIA6AEIaAwAAAQALABpDAAABAA2AGsMAAADAEAAagwAAAMAPABsDAAAAwAtAG0MAAABABMA6gwAAAMAMwBuDAAAAQAQAAAA.Harakki:BAABLgAECn81AAMYAAkJ3BO3CgC3AQloDAAACABRAGkMAAAGAEMAawwAAAcALwBqDAAACAA8AGwMAAAIADoAbQwAAAQAJADqDAAACAAyAG4MAAACACUAbwwAAAIAGgAYAAgJPBW3CgC3AQhoDAAACABRAGkMAAAGAEMAawwAAAcALwBqDAAACAA8AGwMAAAIADoAbQwAAAMAJADqDAAABwAyAG4MAAACACUAAwADCXsIb0EAdwADbQwAAAEABwDqDAAAAQAfAG8MAAACABoAAAA=.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCwAOAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIBAAcJ/yFuEQB8AgdoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcAbQwAAAEATgDqDAAAAwBgAAEABwn/IW4RAHwCB2gMAAAFAFMAaQwAAAYAUABrDAAABQBfAGoMAAAGAFgAbAwAAAQAVwBtDAAAAQBOAOoMAAADAGAAAAA=.Hopseng:BAAALgADCgcJCAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAOAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMUAAYJSRPbtAAIAQZoDAAABQA2AGkMAAAFADUAawwAAAUAOQBqDAAAAgBFAGwMAAADAC4A6gwAAAUAIgAUAAYJsRDbtAAIAQZoDAAABQA2AGkMAAAFADUAawwAAAQAFwBqDAAAAQAvAGwMAAADAC4A6gwAAAUAIgAZAAIJRhYQRgA+AAJrDAAAAQA5AGoMAAABAEUAAAA=.Icytouch:BAAALgAECgYJEgAAAA==.',
Il='Illijim:BAAALgAECgQJBQABLgAECgkJOQAKAOshAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAIUAAgJ4wc8pgAfAQhoDAAACAAiAGkMAAAHABMAawwAAAgAEgBqDAAAAwAXAGwMAAADAAkAbQwAAAEAJgDqDAAABwAPAG4MAAABAAQAFAAICeMHPKYAHwEIaAwAAAgAIgBpDAAABwATAGsMAAAIABIAagwAAAMAFwBsDAAAAwAJAG0MAAABACYA6gwAAAcADwBuDAAAAQAEAAAA.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAABLgAECn8VAAIBAAkJmw5OTAD6AAloDAAAAgAsAGkMAAACAAQAawwAAAIAEQBqDAAAAgAbAGwMAAABACIAbQwAAAEALQDqDAAABQAbAG4MAAAEAEkAbwwAAAIAPAABAAkJmw5OTAD6AAloDAAAAgAsAGkMAAACAAQAawwAAAIAEQBqDAAAAgAbAGwMAAABACIAbQwAAAEALQDqDAAABQAbAG4MAAAEAEkAbwwAAAIAPAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8wAAILAAkJySDlDgD7AgloDAAABABYAGkMAAAHAFcAawwAAAcAXQBqDAAABQBYAGwMAAAGAGAAbQwAAAMAUADqDAAACABOAG4MAAAGADoAbwwAAAIAVgALAAkJySDlDgD7AgloDAAABABYAGkMAAAHAFcAawwAAAcAXQBqDAAABQBYAGwMAAAGAGAAbQwAAAMAUADqDAAACABOAG4MAAAGADoAbwwAAAIAVgAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAaAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAbAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECggJDwAAAA==.',
Kw='Kwaichang:BAAALgAECgEJAQAAAA==.',
La='Laine:BAABLgAECn8cAAIcAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAcAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8KAAIMAAMJ9B8AEwAYAQNoDAAABQBTAGkMAAADAE4A6gwAAAIAUwAMAAMJ9B8AEwAYAQNoDAAABQBTAGkMAAADAE4A6gwAAAIAUwAuAAQKfyAAAgwACQnHIjQDACYDAAwACQnHIjQDACYDAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQEAAcJXB6yGQC/AQdoDAAABwBgAGkMAAAGAGAAawwAAAUATwBqDAAABQA5AGwMAAACAFwAbQwAAAEABgDqDAAABgBfAAQABgnvI7IZAL8BBmgMAAAHAGAAaQwAAAYAYABrDAAABABPAGoMAAADADkAbAwAAAIAXADqDAAABgBfAAUAAQkAAGQEAFsAAWoMAAACADYABgACCQ4InBUAUwACawwAAAEAIgBtDAAAAQAGAC4ABAp/JAADBAAJCbcizQQAbgMABAAJCbcizQQAbgMABgABCQAAzoAADQAAAAA=.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8fAAIdAAgJuw9KHwBmAQhoDAAABABAAGkMAAAEACcAawwAAAQALQBqDAAABQAbAGwMAAAEACcAbQwAAAIACADqDAAABQA4AG4MAAADABsAHQAICbsPSh8AZgEIaAwAAAQAQABpDAAABAAnAGsMAAAEAC0AagwAAAUAGwBsDAAABAAnAG0MAAACAAgA6gwAAAUAOABuDAAAAwAbAAAA.Lunarheals:BAABLgAECn8kAAIcAAgJ7RiGFQAUAghoDAAABgBIAGkMAAAHAEIAawwAAAYARABqDAAABQBGAGwMAAAFADgAbQwAAAEAGADqDAAAAwBJAG4MAAADAE0AHAAICe0YhhUAFAIIaAwAAAYASABpDAAABwBCAGsMAAAGAEQAagwAAAUARgBsDAAABQA4AG0MAAABABgA6gwAAAMASQBuDAAAAwBNAAAA.Lunasong:BAABLgAECn8gAAIIAAkJSwd0XACAAQloDAAABQAdAGkMAAADABMAawwAAAQAEgBqDAAABQAlAGwMAAAEAAsAbQwAAAIACgDqDAAABgAaAG4MAAABAA4AbwwAAAIAEwAIAAkJSwd0XACAAQloDAAABQAdAGkMAAADABMAawwAAAQAEgBqDAAABQAlAGwMAAAEAAsAbQwAAAIACgDqDAAABgAaAG4MAAABAA4AbwwAAAIAEwAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martibishop:BAAALgADCgYJBQABLgAECgkJLAAWAIkUAA==.Martyguard:BAAALgAECgYJBgABLgAECgkJLAAWAIkUAA==.Martyulon:BAABLgAECn8sAAMWAAkJiRS2HwABAgloDAAABwBJAGkMAAAFAEcAawwAAAYAOgBqDAAABwA2AGwMAAAHAC0AbQwAAAMAHgDqDAAABgBCAG4MAAABACIAbwwAAAIAJQAWAAkJiRS2HwABAgloDAAABgBJAGkMAAAEAEcAawwAAAUAOgBqDAAABgA2AGwMAAAGAC0AbQwAAAMAHgDqDAAABgBCAG4MAAABACIAbwwAAAIAJQAMAAUJHQmiVQCmAAVoDAAAAQAeAGkMAAABABgAawwAAAEAEgBqDAAAAQAWAGwMAAABABMAAAA=.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8HAAIeAAMJyROZAgDRAANoDAAABAA6AGkMAAACAC4A6gwAAAEALwAeAAMJyROZAgDRAANoDAAABAA6AGkMAAACAC4A6gwAAAEALwAuAAQKfyoAAh4ACQnkHFwBAIwCAB4ACQnkHFwBAIwCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn85AAQKAAkJ6yG4CACbAgloDAAACQBfAGkMAAAHAFQAawwAAAcAVQBqDAAABwBbAGwMAAAIAFIAbQwAAAQAQQDqDAAACQBgAG4MAAAEAF0AbwwAAAIAWgAKAAgJ/yC4CACbAghoDAAABwBfAGkMAAAGAFQAawwAAAYAVQBqDAAABgBbAGwMAAAHAFIAbQwAAAMAQQDqDAAABgBgAG4MAAACAFAADAAGCZ4f4T4A8gAGaAwAAAIASgBpDAAAAQBEAGsMAAABAEQA6gwAAAMAWgBuDAAAAgBdAG8MAAACAFoAFgADCcUKJ14AVQADagwAAAEAHgBsDAAAAQAXAG0MAAABAB0AAAA=.Monko:BAAALgAECgEJAQABLgAFFAcJHQASAAkjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAbAFwbAA==.',
Od='Odinsknight:BAABLgAECn8mAAQYAAgJdRRsCgC9AQhoDAAABwAuAGkMAAAGADEAawwAAAUANABqDAAABQAyAGwMAAAEADYAbQwAAAIAGADqDAAABgA4AG4MAAADAFMAGAAICccTbAoAvQEIaAwAAAYALgBpDAAABQAxAGsMAAAEACcAagwAAAUAMgBsDAAABAA2AG0MAAACABgA6gwAAAUAOABuDAAAAwBTAAIAAwmwATsOAVgAA2gMAAABAAQAaQwAAAEABADqDAAAAQAEAAMAAQlSFItVADQAAWsMAAABADQAAAA=.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAAALgAFFAMJAwAAAA==.',
Ph='Phreek:BAABLgAECn8dAAILAAkJdxI6eQDfAQloDAAABgA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAACAA5AG4MAAABACYAbwwAAAEAGwALAAkJdxI6eQDfAQloDAAABgA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAACAA5AG4MAAABACYAbwwAAAEAGwAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn84AAISAAkJhhTnKQD4AQloDAAACQBWAGkMAAAIAEoAawwAAAgAQABqDAAABwA4AGwMAAAHAD4AbQwAAAUAGwDqDAAACABBAG4MAAADABAAbwwAAAEAEgASAAkJhhTnKQD4AQloDAAACQBWAGkMAAAIAEoAawwAAAgAQABqDAAABwA4AGwMAAAHAD4AbQwAAAUAGwDqDAAACABBAG4MAAADABAAbwwAAAEAEgAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn9KAAQVAAkJDhVgCQDBAQloDAAADQA3AGkMAAAKACsAawwAAAoAQABqDAAACAA0AGwMAAAIAFMAbQwAAAUAKgDqDAAADABJAG4MAAAFADEAbwwAAAMAEgAVAAkJ2BJgCQDBAQloDAAACQA3AGkMAAAGACkAawwAAAYAOQBqDAAABQA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAdAAcJ9hSzHAB/AQdoDAAABAAwAGkMAAADACsAawwAAAMAQABqDAAAAwA0AGwMAAABADEAbQwAAAEAKgDqDAAABABJABEAAgkpByXsAE4AAmkMAAABABAAawwAAAEAEwAAAA==.Racinette:BAACLgAFFH8iAAIBAAUJ3yTyCgDuAQVoDAAACQBcAGkMAAAJAF0AawwAAAUAYwBqDAAABABhAOoMAAAHAFkAAQAFCd8k8goA7gEFaAwAAAkAXABpDAAACQBdAGsMAAAFAGMAagwAAAQAYQDqDAAABwBZAC4ABAp/GgACAQAJCfskvwUAEAMAAQAJCfskvwUAEAMAAAA=.',
Re='Rebexha:BAABLgAECn8UAAILAAgJ8AWIpgAnAQhoDAAABAARAGkMAAAEABMAawwAAAQAFABqDAAAAQAVAGwMAAACAAsAbQwAAAEADgDqDAAAAwARAG4MAAABAAQACwAICfAFiKYAJwEIaAwAAAQAEQBpDAAABAATAGsMAAAEABQAagwAAAEAFQBsDAAAAgALAG0MAAABAA4A6gwAAAMAEQBuDAAAAQAEAAAA.Redia:BAAALgAECgUJDAAAAA==.Relvanas:BAABLgAECn8kAAMfAAgJ/gZ6KAA/AQhoDAAABwAPAGkMAAAGABwAawwAAAUAEABqDAAABQAxAGwMAAAEAB4AbQwAAAIABwDqDAAABQASAG4MAAACAAgAHwAICf4GeigAPwEIaAwAAAYADwBpDAAABgAcAGsMAAAFABAAagwAAAUAMQBsDAAAAwAeAG0MAAACAAcA6gwAAAQAEgBuDAAAAgAIACAAAwkpA4ciAEAAA2gMAAABAAUAbAwAAAEADgDqDAAAAQADAAAA.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8uAAIIAAkJ4wNKggAqAQloDAAABwATAGkMAAAFAAkAawwAAAYACABqDAAABwAPAGwMAAAHAAkAbQwAAAIACADqDAAACAAGAG4MAAACAAQAbwwAAAIADQAIAAkJ4wNKggAqAQloDAAABwATAGkMAAAFAAkAawwAAAYACABqDAAABwAPAGwMAAAHAAkAbQwAAAIACADqDAAACAAGAG4MAAACAAQAbwwAAAIADQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAICAAUJCgQ0fgDvAAVoDAAAAQASAGkMAAACAAkAawwAAAEACABqDAAAAgAJAOoMAAABAAQAAgAFCQoENH4A7wAFaAwAAAEAEgBpDAAAAgAJAGsMAAABAAgAagwAAAIACQDqDAAAAQAEAAAA.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwACAAoEAA==.Scuffedfaith:BAABLgAECn8bAAMhAAgJ0Bo4FAArAghoDAAABABMAGkMAAAFAF8AawwAAAUAYABqDAAAAwBfAGwMAAADADgAbQwAAAIAUgDqDAAAAwAZAG4MAAACABQAIQAHCYUdOBQAKwIHaAwAAAQATABpDAAABABfAGsMAAAEAGAAagwAAAIAXwBsDAAAAwA4AG0MAAACAFIA6gwAAAIAGQAiAAUJ4QRsSQC4AAVpDAAAAQAMAGsMAAABAA0AagwAAAEAAgDqDAAAAQAOAG4MAAACAAkAAS4ABRQFCQcAAgAKBAA=.',
Se='Sefyra:BAABLgAECn8bAAIIAAgJBRKZSgCyAQhoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAADAEkA6gwAAAUAKgBuDAAAAQAhAG8MAAABABMACAAICQUSmUoAsgEIaAwAAAUAMwBpDAAABQArAGsMAAAFADwAagwAAAIALQBsDAAAAwBJAOoMAAAFACoAbgwAAAEAIQBvDAAAAQATAAAA.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shamroran:BAAALgAECgEJAgAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgYJCgAAAA==.Snolo:BAABLgAECn8gAAIbAAgJWBB8LgByAQhoDAAABgA3AGkMAAAGACoAawwAAAYAKwBqDAAABQA6AGwMAAAEACsAbQwAAAEAIQDqDAAAAwA0AG4MAAABABUAGwAICVgQfC4AcgEIaAwAAAYANwBpDAAABgAqAGsMAAAGACsAagwAAAUAOgBsDAAABAArAG0MAAABACEA6gwAAAMANABuDAAAAQAVAAAA.Snowyrose:BAAALgAECgMJAwABLgAFFAMJCgAMAPQfAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAABLgAFFH8GAAMjAAQJtxskIQBMAQRoDAAAAQA3AGkMAAABAFQAbAwAAAEAQwDqDAAAAwBMACMABAm3GyQhAEwBBGgMAAABADcAaQwAAAEAVABsDAAAAQBDAOoMAAACAEwAGgABCdEBVVIAMgAB6gwAAAEABAABLgAFFAcJIAAEAFweAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8KAAIPAAMJXQVIMgCVAANoDAAABQAKAGkMAAADABQA6gwAAAIACQAPAAMJXQVIMgCVAANoDAAABQAKAGkMAAADABQA6gwAAAIACQAuAAQKf0AAAxIACQlMGXo3AKwBABIACAnCF3o3AKwBAA8ACQlADgYiAKYBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIaAAgJVRRLMgBjAQhoDAAABABIAGkMAAAEAEEAawwAAAQAMQBqDAAAAwAlAGwMAAADAFEAbQwAAAEAEwDqDAAABAA5AG4MAAABABEAGgAICVUUSzIAYwEIaAwAAAQASABpDAAABABBAGsMAAAEADEAagwAAAMAJQBsDAAAAwBRAG0MAAABABMA6gwAAAQAOQBuDAAAAQARAAAA.',
Tr='Trickydice:BAAALgAECggJDQAAAA==.Trust:BAAALgADCgEJAQAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ty='Tysreaper:BAACLgAFFH8GAAIEAAMJgw44bQDSAANoDAAAAgAWAGkMAAACABUA6gwAAAIAQgAEAAMJgw44bQDSAANoDAAAAgAWAGkMAAACABUA6gwAAAIAQgAuAAQKfxgAAwQACAksEoVcALMBAAQACAlWEYVcALMBAAUAAwlxD/kYALMAAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn81AAIUAAkJbyGnDAD1AgloDAAACABbAGkMAAAGAFcAawwAAAcATgBqDAAACABbAGwMAAAIAGAAbQwAAAQARADqDAAACABcAG4MAAACAEgAbwwAAAIAYQAUAAkJbyGnDAD1AgloDAAACABbAGkMAAAGAFcAawwAAAcATgBqDAAACABbAGwMAAAIAGAAbQwAAAQARADqDAAACABcAG4MAAACAEgAbwwAAAIAYQAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9OAAMUAAkJtCSEBABNAwloDAAADABeAGkMAAAMAF0AawwAAAwAYgBqDAAACgBhAGwMAAAIAGEAbQwAAAUAXwDqDAAACgBgAG4MAAAGAGEAbwwAAAMATwAUAAkJtCSEBABNAwloDAAACwBeAGkMAAAMAF0AawwAAAwAYgBqDAAACgBhAGwMAAAIAGEAbQwAAAUAXwDqDAAACQBgAG4MAAAGAGEAbwwAAAMATwAZAAIJPxmAMwCCAAJoDAAAAQAtAOoMAAABAFMAAAA=.',
Wu='Wu:BAABLgAECn8WAAIMAAgJPBAULQBHAQhoDAAABAAuAGkMAAAFADMAawwAAAQAKgBqDAAAAgApAGwMAAACAC8AbQwAAAEAIADqDAAAAwArAG4MAAABABsADAAICTwQFC0ARwEIaAwAAAQALgBpDAAABQAzAGsMAAAEACoAagwAAAIAKQBsDAAAAgAvAG0MAAABACAA6gwAAAMAKwBuDAAAAQAbAAEuAAUUBQkLAAQA+AgA.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAUJCwAEAPgIAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8PAAIbAAQJOQ4pLQD5AARoDAAABQAsAGkMAAAFAC0AawwAAAEAFQDqDAAABAAiABsABAk5DiktAPkABGgMAAAFACwAaQwAAAUALQBrDAAAAQAVAOoMAAAEACIALgAECn80AAIbAAkJRhfiFAApAgAbAAkJRhfiFAApAgAAAA==.',
Zi='Zingispingus:BAABLgAECn8fAAIPAAgJjQexOwAOAQhoDAAABgAXAGkMAAAFABEAawwAAAUAGQBqDAAABAAQAGwMAAAEABkAbQwAAAIACgDqDAAABAATAG8MAAABAA4ADwAICY0HsTsADgEIaAwAAAYAFwBpDAAABQARAGsMAAAFABkAagwAAAQAEABsDAAABAAZAG0MAAACAAoA6gwAAAQAEwBvDAAAAQAOAAAA.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECggJFQATAH0aAA==.',
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
