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
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-27',data={Ak='Akuma:BAAALgAECgEJAQAAAA==.',
Al='Alilith:BAAALgAECgEJAgAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8JAAIBAAcJjgSmEAC/AQdoDAAAAQAQAGkMAAABAAQAawwAAAEABABqDAAAAQAGAGwMAAABAAMA6gwAAAMAKwBuDAAAAQACAAEABwmOBKYQAL8BB2gMAAABABAAaQwAAAEABABrDAAAAQAEAGoMAAABAAYAbAwAAAEAAwDqDAAAAwArAG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAICAAIJsx6vqgCTAAJoDAAABABMAOoMAAAEAFAAAgACCbMer6oAkwACaAwAAAQATADqDAAABABQAAAA.',
As='Asecretbear:BAACLgAFFH8OAAIDAAQJYQwDKgD9AARoDAAABQAwAGkMAAAEACEAawwAAAEAHADqDAAABAAPAAMABAlhDAMqAP0ABGgMAAAFADAAaQwAAAQAIQBrDAAAAQAcAOoMAAAEAA8ALgAECn8zAAIDAAkJwxq7FwB5AgADAAkJwxq7FwB5AgAAAA==.Ashvana:BAACLgAFFH8RAAICAAQJOyDMJwCFAQRoDAAABABcAGkMAAAGAFgAawwAAAIAQwDqDAAABQBRAAIABAk7IMwnAIUBBGgMAAAEAFwAaQwAAAYAWABrDAAAAgBDAOoMAAAFAFEALgAECn85AAICAAkJoSQ0DwDdAgACAAkJoSQ0DwDdAgAAAA==.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8iAAMEAAgJ1RP4DACHAQhoDAAABgBOAGkMAAAGAF0AawwAAAUAMQBqDAAABAAjAGwMAAADACcAbQwAAAEABADqDAAACAA8AG4MAAABAB4ABAAGCVQW+AwAhwEGaAwAAAYATgBpDAAABgBdAGsMAAAFADEAagwAAAEAIwBtDAAAAQAEAOoMAAAIADwABQADCf8HRzsA0QADagwAAAMACQBsDAAAAwAwAG4MAAABAAMALgAECn8oAAMEAAkJQyKZAwBpAwAEAAkJQyKZAwBpAwAFAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8fAAIGAAgJKRnZAwCRAghoDAAABQApAGkMAAAFAE4AawwAAAUARgBqDAAABABYAGwMAAADAFAAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABgAICSkZ2QMAkQIIaAwAAAUAKQBpDAAABQBOAGsMAAAFAEYAagwAAAQAWABsDAAAAwBQAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBgAJCYIg8AMAMgMABgAJCYIg8AMAMgMABwAGCfYbahwA+AEAAS4ABAoJCR8ACAAEIgA=.',
Be='Bennius:BAAALgAECggJDgAAAA==.Benwarrior:BAAALgAECgYJCQABLgAFFAYJEAAJAP4aAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJEQAJAGQVAA==.',
Ca='Calan:BAAALgADCgMJAwABLgAFFAMJBQAKAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAALAJ8jAA==.Choco:BAACLgAFFH8LAAIEAAQJJhnGFgAuAQRoDAAABAA+AGkMAAACAEsAawwAAAIAOADqDAAAAwA+AAQABAkmGcYWAC4BBGgMAAAEAD4AaQwAAAIASwBrDAAAAgA4AOoMAAADAD4ALgAECn8bAAIEAAgJ5B2fEwAwAgAEAAgJ5B2fEwAwAgAAAA==.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.',
Cr='Crash:BAAALgAECgIJAgABLgAFFAYJDwANADAYAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgEJAQAAAA==.Creme:BAABLgAECn8jAAIEAAgJrxvHFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYABAAICa8bxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8JAAIOAAMJSBTkFwDzAANoDAAABABOAGkMAAADADQA6gwAAAIAGAAOAAMJSBTkFwDzAANoDAAABABOAGkMAAADADQA6gwAAAIAGAAuAAQKfzkAAg4ACQlrHMwGAKMCAA4ACQlrHMwGAKMCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8WAAQPAAcJ0wYKIwCkAAdoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQAbQwAAAEAQgDqDAAAAwAIAA8ABgmVAgojAKQABmgMAAADAAkAaQwAAAMACABrDAAAAwAFAGoMAAABAAgAbAwAAAEABADqDAAAAgAEAAQABQnxAm1uAHQABWgMAAABAAgAaQwAAAEABQBrDAAAAQAHAGoMAAABAAgA6gwAAAEACAAFAAMJLwTWpQBSAANqDAAAAQAJAGwMAAACAAgAbQwAAAEADgAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgcJEAAAAA==.Deralan:BAABLgAECn8fAAMIAAgJ4gcaOwAZAQhoDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAEAAwAbQwAAAQAFgDqDAAABgASAG4MAAAEAA8ACAAICeIHGjsAGQEIaAwAAAQAIABpDAAAAwAbAGsMAAAEAAsAagwAAAEACABsDAAAAwAMAG0MAAAEABYA6gwAAAYAEgBuDAAABAAPABAAAglwA5glACUAAmoMAAABAAcAbAwAAAEACAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAALAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIRAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQARAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAABLgAECn8WAAICAAcJjQvtkQAnAQdoDAAABwAlAGkMAAAGACkAawwAAAMAKgBqDAAAAgAcAGwMAAACABUAbQwAAAEACwDqDAAAAQAXAAIABwmNC+2RACcBB2gMAAAHACUAaQwAAAYAKQBrDAAAAwAqAGoMAAACABwAbAwAAAIAFQBtDAAAAQALAOoMAAABABcAAAA=.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCAAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIIAAMJ7weoOgC0AANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAIAAMJ7weoOgC0AANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8JAAMSAAUJIyOjAwCfAQVoDAAAAgBfAGkMAAACAGEAawwAAAIAVwBqDAAAAQARAOoMAAACAE8AEgAECSMjowMAnwEEaAwAAAIAXwBpDAAAAgBhAGsMAAACAFcA6gwAAAIATwATAAEJAAAvGQAAAAFqDAAAAQARAC4ABAp/KQADEgAICdAk8gIA5QIAEgAICdAk8gIA5QIAEwAHCZIgSAcAPQIAAAA=.Faengbrew:BAAALgAECgcJDgABLgAFFAUJCQASACMjAA==.Faenghorn:BAAALgAFFAMJBAABLgAFFAUJCQASACMjAA==.Fanah:BAAALgADCggJDgABLgAECgcJKwABAN0dAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgEJAQAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgMJAwAAAA==.Frozswarrior:BAABLgAECn8VAAMRAAgJJgffPAA2AQhoDAAAAwALAGkMAAADABcAawwAAAMAEQBqDAAAAwAWAGwMAAADABEAbQwAAAEADADqDAAAAwAXAG4MAAACABUAEQAICSEH3zwANgEIaAwAAAIACwBpDAAAAgAXAGsMAAACABEAagwAAAIAFgBsDAAAAgARAG0MAAABAAwA6gwAAAIAFwBuDAAAAQAVABQABwkVBbk4AL4AB2gMAAABAAcAaQwAAAEADwBrDAAAAQAPAGoMAAABAAcAbAwAAAEAEQDqDAAAAQANAG4MAAABAAgAAAA=.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8bAAIKAAcJYwnLrwAkAQdoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQBuDAAAAQALAAoABwljCcuvACQBB2gMAAAGABAAaQwAAAYAHgBrDAAABgAwAGoMAAACABIAbAwAAAIADwDqDAAABAAVAG4MAAABAAsAAAA=.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJCAAVABgJAA==.Gladerbug:BAAALgAECggJCQAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJEQAJAGQVAA==.Grindêlwald:BAACLgAFFH8RAAIJAAQJZBU8FQAMAQRoDAAABgA5AGkMAAAFAFEAawwAAAEACQDqDAAABQBFAAkABAlkFTwVAAwBBGgMAAAGADkAaQwAAAUAUQBrDAAAAQAJAOoMAAAFAEUALgAECn8gAAIJAAkJbBtPCgBNAgAJAAkJbBtPCgBNAgAAAA==.Grindëlwald:BAABLgAECn8eAAIWAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFgAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUBAkRAAkAZBUA.',
Gu='Guac:BAAALgAECgUJEAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgcJKwABAN0dAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8eAAMIAAgJ3BodAgAyAghoDAAABQBaAGkMAAAFAFoAawwAAAQAVgBqDAAABABZAGwMAAADAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACAAICYcaHQIAMgIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAQAWQBsDAAAAwBQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkABAAAgmmGQQGALEAAmgMAAABACgAaQwAAAEAWgAuAAQKfycAAwgACQlwI4MBAK4DAAgACQlOI4MBAK4DABAABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMXAAkJwyBtCgB2AgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABwBhAG4MAAAEADsAbwwAAAEAMwAHAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABQBhABcACQm0HG0KAHYCCWgMAAAEAFQAaQwAAAQAXwBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkeAAgA3BoA.Ishootudead:BAAALgAECggJDwABLgAFFAgJHgAIANwaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJCQABAI4EAA==.Jon:BAACLgAFFH8JAAIYAAMJdRJkaQDuAANoDAAABAA/AGkMAAADACMA6gwAAAIAKgAYAAMJdRJkaQDuAANoDAAABAA/AGkMAAADACMA6gwAAAIAKgAuAAQKfzcAAhgACQlsIMQQAN8CABgACQlsIMQQAN8CAAAA.Josito:BAAALgADCggJDQABLgAFFAMJBQAKAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8lAAIYAAgJ9RbLSADlAQhoDAAABQBNAGkMAAAGAD8AawwAAAYASQBqDAAABgBTAGwMAAAEADUAbQwAAAMALADqDAAABQBAAG4MAAACACIAGAAICfUWy0gA5QEIaAwAAAUATQBpDAAABgA/AGsMAAAGAEkAagwAAAYAUwBsDAAABAA1AG0MAAADACwA6gwAAAUAQABuDAAAAgAiAAAA.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8XAAMWAAcJxQ5yGgAjAQdoDAAABQBQAGkMAAAFADQAawwAAAUAGABqDAAAAwAiAGwMAAABABQA6gwAAAMAJwBuDAAAAQAIABYABwnFDnIaACMBB2gMAAAFAFAAaQwAAAUANABrDAAABQAYAGoMAAADACIAbAwAAAEAFADqDAAAAgAnAG4MAAABAAgACgABCUUDGFgBJwAB6gwAAAEACAAAAA==.',
Ke='Kealee:BAABLgAECn8WAAIKAAcJnQwqjgA3AQdoDAAABQA6AGkMAAAFACEAawwAAAUAJABqDAAAAwAnAGwMAAABABIA6gwAAAIAHABuDAAAAQASAAoABwmdDCqOADcBB2gMAAAFADoAaQwAAAUAIQBrDAAABQAkAGoMAAADACcAbAwAAAEAEgDqDAAAAgAcAG4MAAABABIAAAA=.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIYAAQJBQYbXgAOAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABgABAkFBhteAA4BBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMYAAgJ3xTRdQBuAQAYAAgJ1xTRdQBuAQAZAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMNAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAANAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAaAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8jAAINAAkJqhcmKwADAgloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQANAAkJqhcmKwADAgloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAMAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAMAAAAAA==.Littletop:BAABLgAECn8UAAIbAAgJ4AeNEgAAAQhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGwAICeAHjRIAAAEIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8kAAIKAAkJGxCFUwC1AQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABwAnAG4MAAADABkAbwwAAAEAUQAKAAkJGxCFUwC1AQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABwAnAG4MAAADABkAbwwAAAEAUQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn80AAICAAkJJQsCXACaAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACAA7AG4MAAAFABQAbwwAAAIAEQACAAkJJQsCXACaAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACAA7AG4MAAAFABQAbwwAAAIAEQAAAA==.Malex:BAABLgAECn8fAAIIAAkJBCKpBQDrAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAIAAkJBCKpBQDrAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8BkrOADdAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAFAAMJ8BkrOADdAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAEAAEJQgyQRQA8AAFpDAAAAQAfAC4ABAp/GwADBAAICWMcahgAUQIABAAHCZsdahgAUQIABQAHCeERY0IAdwEAAS4ABAoJCR8ACAAEIgA=.Malrii:BAAALgAECggJCAABLgAECgkJHwAIAAQiAA==.Marselli:BAAALgAECggJEgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn84AAIcAAkJ6Q/AGgDTAQloDAAACAA0AGkMAAAHAB8AawwAAAcAKABqDAAABgApAGwMAAAGAB0AbQwAAAUAEQDqDAAACQBfAG4MAAAGACQAbwwAAAIAFgAcAAkJ6Q/AGgDTAQloDAAACAA0AGkMAAAHAB8AawwAAAcAKABqDAAABgApAGwMAAAGAB0AbQwAAAUAEQDqDAAACQBfAG4MAAAGACQAbwwAAAIAFgAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAIKAAgJ0xzaXADMAQhoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIAbQwAAAEASgDqDAAABABPAG4MAAABADoACgAICdMc2lwAzAEIaAwAAAQAUQBpDAAABQBUAGsMAAAFAEgAagwAAAEAUwBsDAAAAwBCAG0MAAABAEoA6gwAAAQATwBuDAAAAQA6AAAA.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRyLMgC6AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgADAAYJsRyLMgC6AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAcAAUJ/A4wSgC+AAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIYAAkJbR1wHwCHAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAYAAkJbR1wHwCHAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMLAAgJnyOWBgAkAwhoDAAABwBcAGkMAAAIAGEAawwAAAYAXwBqDAAAAwBfAGwMAAADAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACwAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAA4ABwkaIzYSAAYCB2gMAAAEAFIAaQwAAAQAXABrDAAAAwBfAGoMAAABAF8AbAwAAAIAXADqDAAAAgBNAG4MAAACAGEAAAA=.',
Ph='Phatt:BAABLgAECn8WAAIdAAgJSBVSFADiAQhoDAAAAwBHAGkMAAAEADkAawwAAAQAOgBqDAAAAwBLAGwMAAACAEgAbQwAAAIAMwDqDAAAAwAwAG4MAAABABUAHQAICUgVUhQA4gEIaAwAAAMARwBpDAAABAA5AGsMAAAEADoAagwAAAMASwBsDAAAAgBIAG0MAAACADMA6gwAAAMAMABuDAAAAQAVAAAA.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB9TMAD5AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAFAAMJGB9TMAD5AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy8AAgUACAmtJJEJAN8CAAUACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAICAAYJyQglvADkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAACAAYJyQglvADkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAAAAA==.Raghnoll:BAABLgAECn8yAAMeAAkJchZiEwBaAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAAEAAsAbwwAAAEANAAeAAkJchZiEwBaAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAACAAsAbwwAAAEANAAKAAEJ2RaXSQFEAAFuDAAAAgA6AAAA.',
Re='Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8JAAIfAAMJsQWtGwCVAANoDAAABAAWAGkMAAADAAUA6gwAAAIAEAAfAAMJsQWtGwCVAANoDAAABAAWAGkMAAADAAUA6gwAAAIAEAAuAAQKfzEAAh8ACQmAEEYRALcBAB8ACQmAEEYRALcBAAAA.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgYJDwABLgAFFAMJBQAKAD0lAA==.Sariar:BAAALgADCgYJBgABLgAFFAMJBQAKAD0lAA==.Sartorius:BAABLgAECn8fAAIcAAkJEAluLABQAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAcAAkJEAluLABQAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGwAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIYAAkJXAPdnwAcAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAYAAkJXAPdnwAcAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAAAA==.Sciel:BAABLgAECn8fAAIEAAgJ3CGPFAB6AghoDAAAAwBaAGkMAAAGAF4AawwAAAUAUwBqDAAAAwBcAGwMAAAEAEgAbQwAAAMAUgDqDAAABQBWAG4MAAACAGAABAAICdwhjxQAegIIaAwAAAMAWgBpDAAABgBeAGsMAAAFAFMAagwAAAMAXABsDAAABABIAG0MAAADAFIA6gwAAAUAVgBuDAAAAgBgAAAA.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNgACAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwjDOAD/AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAHAAkJLwjDOAD/AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8YAAILAAcJ2hP1bQBEAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAsABwnaE/VtAEQBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJIQAfAIYeAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAYAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8SAAIFAAQJ/RgrIgA1AQRoDAAABgBUAGkMAAAFAFAAawwAAAIAGgDqDAAABQBAAAUABAn9GCsiADUBBGgMAAAGAFQAaQwAAAUAUABrDAAAAgAaAOoMAAAFAEAALgAECn87AAIFAAkJBSWSAQCkAwAFAAkJBSWSAQCkAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJKwAgAGkkAA==.Tip:BAAALgAECgUJCQAAAA==.',
To='Topaten:BAACLgAFFH8GAAILAAMJFwa2UgDJAANoDAAAAgAIAGkMAAACAAoA6gwAAAIAGwALAAMJFwa2UgDJAANoDAAAAgAIAGkMAAACAAoA6gwAAAIAGwAuAAQKfxoAAgsACQkoFxgeAFMCAAsACQkoFxgeAFMCAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAIKAAkJ7hODOwD7AQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAAKAAkJ7hODOwD7AQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgQJBAAMAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgQJBAAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMhAAcJKB1NFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfACEABwnSHE0VADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AAQAHCeUYjyAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAMAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAUJEAAeALoZAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAECgkJBgAMAAAAAA==.',
['Àl']='Àlilith:BAABLgAECn8dAAIKAAkJ/BqOLQAvAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACQBiAG4MAAABADQAbwwAAAEAUwAKAAkJ/BqOLQAvAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACQBiAG4MAAABADQAbwwAAAEAUwAAAA==.',
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
