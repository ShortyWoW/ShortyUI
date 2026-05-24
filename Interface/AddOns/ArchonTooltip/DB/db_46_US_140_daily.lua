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

local lookup = {'Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Paladin-Retribution','Hunter-BeastMastery','Unknown-Unknown','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Rogue-Subtlety','Paladin-Holy','Warrior-Protection','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-23',data={Al='Alilith:BAAALgAECgEJAgAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8JAAIBAAcJjgSjDgDNAQdoDAAAAQAQAGkMAAABAAQAawwAAAEABABqDAAAAQAGAGwMAAABAAMA6gwAAAMAKwBuDAAAAQACAAEABwmOBKMOAM0BB2gMAAABABAAaQwAAAEABABrDAAAAQAEAGoMAAABAAYAbAwAAAEAAwDqDAAAAwArAG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAICAAIJsx5bngCZAAJoDAAABABMAOoMAAAEAFAAAgACCbMeW54AmQACaAwAAAQATADqDAAABABQAAAA.',
As='Asecretbear:BAACLgAFFH8NAAIDAAMJvAxWNQC8AANoDAAABQAwAGkMAAAEACEA6gwAAAQADwADAAMJvAxWNQC8AANoDAAABQAwAGkMAAAEACEA6gwAAAQADwAuAAQKfzAAAgMACQnDGrsXAHkCAAMACQnDGrsXAHkCAAAA.Ashvana:BAACLgAFFH8MAAICAAMJ8x+iaQD2AANoDAAAAwBcAGkMAAAFAEcA6gwAAAQAUQACAAMJ8x+iaQD2AANoDAAAAwBcAGkMAAAFAEcA6gwAAAQAUQAuAAQKfzYAAgIACQmhJLAOANgCAAIACQmhJLAOANgCAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8iAAMEAAgJ1RPyCgCXAQhoDAAABgBOAGkMAAAGAF0AawwAAAUAMQBqDAAABAAjAGwMAAADACcAbQwAAAEABADqDAAACAA8AG4MAAABAB4ABAAGCVQW8goAlwEGaAwAAAYATgBpDAAABgBdAGsMAAAFADEAagwAAAEAIwBtDAAAAQAEAOoMAAAIADwABQADCf8HnjYA0gADagwAAAMACQBsDAAAAwAwAG4MAAABAAMALgAECn8oAAMEAAkJQyKZAwBpAwAEAAkJQyKZAwBpAwAFAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8fAAIGAAgJKRkiAwCUAghoDAAABQApAGkMAAAFAE4AawwAAAUARgBqDAAABABYAGwMAAADAFAAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABgAICSkZIgMAlAIIaAwAAAUAKQBpDAAABQBOAGsMAAAFAEYAagwAAAQAWABsDAAAAwBQAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBgAJCYIg8AMAMgMABgAJCYIg8AMAMgMABwAGCfYbahwA+AEAAS4ABAoJCR8ACAAEIgA=.',
Be='Bennius:BAAALgAECgMJAwAAAA==.Berserkr:BAAALgAECgUJCwAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAMJDwAJAEMbAA==.',
Ca='Calan:BAAALgADCgMJAwABLgAFFAMJBQAKAD0lAA==.',
Ch='Chainéd:BAAALgAECgUJCwABLgAECggJJAALAJ8jAA==.Choco:BAACLgAFFH8GAAIEAAMJDBUGJADcAANoDAAAAwAhAGkMAAABAEsA6gwAAAIANAAEAAMJDBUGJADcAANoDAAAAwAhAGkMAAABAEsA6gwAAAIANAAuAAQKfxcAAgQACAknHVEVABICAAQACAknHVEVABICAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAFFAUJDQANABIaAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgEJAQAAAA==.Creme:BAABLgAECn8jAAIEAAgJrxvHFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYABAAICa8bxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8IAAIOAAMJmBJBFwDuAANoDAAABABOAGkMAAADADQA6gwAAAEACwAOAAMJmBJBFwDuAANoDAAABABOAGkMAAADADQA6gwAAAEACwAuAAQKfzgAAg4ACQliHDoGAKYCAA4ACQliHDoGAKYCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8WAAQPAAcJ0waiIACkAAdoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQAbQwAAAEAQgDqDAAAAwAIAA8ABgmVAqIgAKQABmgMAAADAAkAaQwAAAMACABrDAAAAwAFAGoMAAABAAgAbAwAAAEABADqDAAAAgAEAAQABQnxAmppAHQABWgMAAABAAgAaQwAAAEABQBrDAAAAQAHAGoMAAABAAgA6gwAAAEACAAFAAMJLwSxnQBSAANqDAAAAQAJAGwMAAACAAgAbQwAAAEADgAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgcJDwAAAA==.Deralan:BAABLgAECn8fAAMIAAgJ4gctNwAqAQhoDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAEAAwAbQwAAAQAFgDqDAAABgASAG4MAAAEAA8ACAAICeIHLTcAKgEIaAwAAAQAIABpDAAAAwAbAGsMAAAEAAsAagwAAAEACABsDAAAAwAMAG0MAAAEABYA6gwAAAYAEgBuDAAABAAPABAAAglwA98jACUAAmoMAAABAAcAbAwAAAEACAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAALAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgABLgAFFAQJBQARAAkTAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIRAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQARAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAABLgAECn8VAAICAAYJ+wxdowD/AAZoDAAABwAlAGkMAAAGACkAawwAAAMAKgBqDAAAAgAcAGwMAAACABUA6gwAAAEAFwACAAYJ+wxdowD/AAZoDAAABwAlAGkMAAAGACkAawwAAAMAKgBqDAAAAgAcAGwMAAACABUA6gwAAAEAFwAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCAAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8HAAIIAAMJbAY/OQCsAANoDAAAAwAZAGkMAAADABMA6gwAAAEAAwAIAAMJbAY/OQCsAANoDAAAAwAZAGkMAAADABMA6gwAAAEAAwAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8GAAMSAAUJnCAXBACBAQVoDAAAAQBcAGkMAAABAFMAawwAAAEATgBqDAAAAQARAOoMAAACAE8AEgAECZwgFwQAgQEEaAwAAAEAXABpDAAAAQBTAGsMAAABAE4A6gwAAAIATwATAAEJAABhFgAAAAFqDAAAAQARAC4ABAp/KQADEgAICdAksAIA5gIAEgAICdAksAIA5gIAEwAHCZIg3gYAPgIAAAA=.Faengbrew:BAAALgAECgcJDgABLgAFFAUJBgASAJwgAA==.Faenghorn:BAAALgAECgUJCgABLgAFFAUJBgASAJwgAA==.Fanah:BAAALgADCggJDgABLgAECgYJJAABAKUeAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgEJAQAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Frozswarrior:BAABLgAECn8VAAMRAAgJJgc2OgA3AQhoDAAAAwALAGkMAAADABcAawwAAAMAEQBqDAAAAwAWAGwMAAADABEAbQwAAAEADADqDAAAAwAXAG4MAAACABUAEQAICSEHNjoANwEIaAwAAAIACwBpDAAAAgAXAGsMAAACABEAagwAAAIAFgBsDAAAAgARAG0MAAABAAwA6gwAAAIAFwBuDAAAAQAVABQABwkVBW40AMMAB2gMAAABAAcAaQwAAAEADwBrDAAAAQAPAGoMAAABAAcAbAwAAAEAEQDqDAAAAQANAG4MAAABAAgAAAA=.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8aAAIKAAYJWwrLrwAkAQZoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAKAAYJWwrLrwAkAQZoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAQJBwAVABgJAA==.Gladerbug:BAAALgAECggJCAAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAMJDwAJAEMbAA==.Grindêlwald:BAACLgAFFH8PAAIJAAMJQxsSGQDhAANoDAAABgA5AGkMAAAFAFEA6gwAAAQARQAJAAMJQxsSGQDhAANoDAAABgA5AGkMAAAFAFEA6gwAAAQARQAuAAQKfx0AAgkACQlsG4MJAFACAAkACQlsG4MJAFACAAAA.Grindëlwald:BAABLgAECn8eAAIWAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFgAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUAwkPAAkAQxsA.',
Gu='Guac:BAAALgAECgQJDAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgYJJAABAKUeAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8eAAMIAAgJ3BodAgAyAghoDAAABQBaAGkMAAAFAFoAawwAAAQAVgBqDAAABABZAGwMAAADAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACAAICYcaHQIAMgIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAQAWQBsDAAAAwBQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkABAAAgmmGQQGALEAAmgMAAABACgAaQwAAAEAWgAuAAQKfycAAwgACQlwI4MBAK4DAAgACQlOI4MBAK4DABAABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMXAAkJwyDaCQB5AgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABwBhAG4MAAAEADsAbwwAAAEAMwAHAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABQBhABcACQm0HNoJAHkCCWgMAAAEAFQAaQwAAAQAXwBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkeAAgA3BoA.Ishootudead:BAAALgAECggJDwABLgAFFAgJHgAIANwaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJCQABAI4EAA==.Jon:BAACLgAFFH8IAAIYAAMJXBL5YwDuAANoDAAABAA/AGkMAAADACMA6gwAAAEAKQAYAAMJXBL5YwDuAANoDAAABAA/AGkMAAADACMA6gwAAAEAKQAuAAQKfzYAAhgACQlZIK8PAOYCABgACQlZIK8PAOYCAAAA.Josito:BAAALgADCggJDQABLgAFFAMJBQAKAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8dAAIYAAgJvBT7UgDGAQhoDAAABABNAGkMAAAFAD8AawwAAAUAMgBqDAAABQBCAGwMAAADADUAbQwAAAIAKwDqDAAABAA9AG4MAAABABYAGAAICbwU+1IAxgEIaAwAAAQATQBpDAAABQA/AGsMAAAFADIAagwAAAUAQgBsDAAAAwA1AG0MAAACACsA6gwAAAQAPQBuDAAAAQAWAAAA.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8XAAMWAAcJxQ4iGQAkAQdoDAAABQBQAGkMAAAFADQAawwAAAUAGABqDAAAAwAiAGwMAAABABQA6gwAAAMAJwBuDAAAAQAIABYABwnFDiIZACQBB2gMAAAFAFAAaQwAAAUANABrDAAABQAYAGoMAAADACIAbAwAAAEAFADqDAAAAgAnAG4MAAABAAgACgABCUUDGFgBJwAB6gwAAAEACAAAAA==.',
Ke='Kealee:BAABLgAECn8WAAIKAAcJnQzNiAA+AQdoDAAABQA6AGkMAAAFACEAawwAAAUAJABqDAAAAwAnAGwMAAABABIA6gwAAAIAHABuDAAAAQASAAoABwmdDM2IAD4BB2gMAAAFADoAaQwAAAUAIQBrDAAABQAkAGoMAAADACcAbAwAAAEAEgDqDAAAAgAcAG4MAAABABIAAAA=.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIYAAQJBQawWAAPAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABgABAkFBrBYAA8BBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMYAAgJ4BSTcQB6AQAYAAgJ2BSTcQB6AQAZAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMNAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAANAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAaAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8jAAINAAkJqhcfKQAHAgloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQANAAkJqhcfKQAHAgloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAMAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAMAAAAAA==.Littletop:BAABLgAECn8UAAIbAAgJ4AdwEQACAQhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGwAICeAHcBEAAgEIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8jAAIKAAkJZQ9aTQDBAQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABgAYAG4MAAADABkAbwwAAAEAUQAKAAkJZQ9aTQDBAQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABgAYAG4MAAADABkAbwwAAAEAUQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8zAAICAAkJ1gqWWgCTAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAABwA0AG4MAAAFABQAbwwAAAIAEQACAAkJ1gqWWgCTAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAABwA0AG4MAAAFABQAbwwAAAIAEQAAAA==.Malex:BAABLgAECn8fAAIIAAkJBCJoBQDzAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAIAAkJBCJoBQDzAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8Bm2MwDeAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAFAAMJ8Bm2MwDeAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAEAAEJQgy4QgA9AAFpDAAAAQAfAC4ABAp/GwADBAAICWMcahgAUQIABAAHCZsdahgAUQIABQAHCeERY0IAdwEAAS4ABAoJCR8ACAAEIgA=.Malrii:BAAALgAECggJCAABLgAECgkJHwAIAAQiAA==.Marselli:BAAALgAECggJEgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn83AAIcAAkJTg/TGgDFAQloDAAACAA0AGkMAAAHAB8AawwAAAcAKABqDAAABgApAGwMAAAGAB0AbQwAAAUAEQDqDAAACABSAG4MAAAGACQAbwwAAAIAFgAcAAkJTg/TGgDFAQloDAAACAA0AGkMAAAHAB8AawwAAAcAKABqDAAABgApAGwMAAAGAB0AbQwAAAUAEQDqDAAACABSAG4MAAAGACQAbwwAAAIAFgAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAIKAAgJ0xzaXADMAQhoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIAbQwAAAEASgDqDAAABABPAG4MAAABADoACgAICdMc2lwAzAEIaAwAAAQAUQBpDAAABQBUAGsMAAAFAEgAagwAAAEAUwBsDAAAAwBCAG0MAAABAEoA6gwAAAQATwBuDAAAAQA6AAAA.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRzgMAC6AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgADAAYJsRzgMAC6AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAcAAUJ/A7iRgC+AAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIYAAkJbR1MHQCSAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAYAAkJbR1MHQCSAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMLAAgJnyOWBgAkAwhoDAAABwBcAGkMAAAIAGEAawwAAAYAXwBqDAAAAwBfAGwMAAADAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACwAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAA4ABwkaIzsRAAkCB2gMAAAEAFIAaQwAAAQAXABrDAAAAwBfAGoMAAABAF8AbAwAAAIAXADqDAAAAgBNAG4MAAACAGEAAAA=.',
Ph='Phatt:BAABLgAECn8WAAIdAAgJSBXkEgDpAQhoDAAAAwBHAGkMAAAEADkAawwAAAQAOgBqDAAAAwBLAGwMAAACAEgAbQwAAAIAMwDqDAAAAwAwAG4MAAABABUAHQAICUgV5BIA6QEIaAwAAAMARwBpDAAABAA5AGsMAAAEADoAagwAAAMASwBsDAAAAgBIAG0MAAACADMA6gwAAAMAMABuDAAAAQAVAAAA.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB8CLAD7AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAFAAMJGB8CLAD7AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy4AAgUACAmtJJEJAN8CAAUACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAICAAYJyQgYtADkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAACAAYJyQgYtADkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAAAAA==.Raghnoll:BAABLgAECn8vAAMeAAgJrhaYGAAbAghoDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACAAuAG4MAAADAAsAHgAICa4WmBgAGwIIaAwAAAgAOQBpDAAABwBgAGsMAAAGAE8AagwAAAYATwBsDAAABgA5AG0MAAADACQA6gwAAAgALgBuDAAAAgALAAoAAQlKCdFlATAAAW4MAAABABcAAAA=.',
Re='Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8IAAIfAAMJsQXLGQCbAANoDAAABAAWAGkMAAADAAUA6gwAAAEAEAAfAAMJsQXLGQCbAANoDAAABAAWAGkMAAADAAUA6gwAAAEAEAAuAAQKfzAAAh8ACQmBD5MRAKcBAB8ACQmBD5MRAKcBAAAA.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgYJDwABLgAFFAMJBQAKAD0lAA==.Sartorius:BAABLgAECn8fAAIcAAkJEAlvKgBQAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAcAAkJEAlvKgBQAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGQAAAA==.',
Sc='Scarthan:BAABLgAECn8hAAIYAAgJCANmtwD6AAhoDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABQAFAG4MAAACAAkAGAAICQgDZrcA+gAIaAwAAAUABQBpDAAABQAMAGsMAAAFAAUAagwAAAUAEQBsDAAABAAKAG0MAAACAAQA6gwAAAUABQBuDAAAAgAJAAAA.Sciel:BAABLgAECn8eAAIEAAgJsR+PFAB6AghoDAAAAwBaAGkMAAAGAF4AawwAAAUAUwBqDAAAAwBcAGwMAAAEAEgAbQwAAAMAUgDqDAAABQBWAG4MAAABADkABAAICbEfjxQAegIIaAwAAAMAWgBpDAAABgBeAGsMAAAFAFMAagwAAAMAXABsDAAABABIAG0MAAADAFIA6gwAAAUAVgBuDAAAAQA5AAAA.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNgACAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwiQNQABAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAHAAkJLwiQNQABAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8YAAILAAcJ2hPcZwBFAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAsABwnaE9xnAEUBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJIQAfAIYeAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAYAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8OAAIFAAQJIRjZHwAxAQRoDAAABQBUAGkMAAAEAFAAawwAAAEAGgDqDAAABAA3AAUABAkhGNkfADEBBGgMAAAFAFQAaQwAAAQAUABrDAAAAQAaAOoMAAAEADcALgAECn87AAIFAAkJBSVdAQCmAwAFAAkJBSVdAQCmAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJIwAgAB8kAA==.',
To='Topaten:BAACLgAFFH8FAAILAAMJFwYfTADJAANoDAAAAgAIAGkMAAACAAoA6gwAAAEAGwALAAMJFwYfTADJAANoDAAAAgAIAGkMAAACAAoA6gwAAAEAGwAuAAQKfxkAAgsACQkbF3gbAFcCAAsACQkbF3gbAFcCAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8hAAIKAAkJ4RGfQgDfAQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABQAzAG4MAAADAEUAbwwAAAEAGAAKAAkJ4RGfQgDfAQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABQAzAG4MAAADAEUAbwwAAAEAGAAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgQJBAAMAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgQJBAAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMhAAcJKB1NFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfACEABwnSHE0VADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AAQAHCeUYjyAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAMAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAFFAQJBQARAAkTAA==.',
['Àl']='Àlilith:BAABLgAECn8dAAIKAAkJ/BprKgA2AgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACQBiAG4MAAABADQAbwwAAAEAUwAKAAkJ/BprKgA2AgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACQBiAG4MAAABADQAbwwAAAEAUwAAAA==.',
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
