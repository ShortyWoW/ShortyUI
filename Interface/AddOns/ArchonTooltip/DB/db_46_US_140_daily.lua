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

local lookup = {'Unknown-Unknown','Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Monk-Brewmaster','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Rogue-Subtlety','Paladin-Holy','Warrior-Protection','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-29',data={Ak='Akuma:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Al='Alilith:BAAALgAECgcJCAAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8PAAICAAcJfA70DAAEAgdoDAAAAgAuAGkMAAACABYAawwAAAIAKABqDAAAAgAhAGwMAAACADYA6gwAAAQAPABuDAAAAQACAAIABwl8DvQMAAQCB2gMAAACAC4AaQwAAAIAFgBrDAAAAgAoAGoMAAACACEAbAwAAAIANgDqDAAABAA8AG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAIDAAIJsx4YsgCQAAJoDAAABABMAOoMAAAEAFAAAwACCbMeGLIAkAACaAwAAAQATADqDAAABABQAAAA.',
As='Asecretbear:BAACLgAFFH8OAAIEAAQJYQzhKwD0AARoDAAABQAwAGkMAAAEACEAawwAAAEAHADqDAAABAAPAAQABAlhDOErAPQABGgMAAAFADAAaQwAAAQAIQBrDAAAAQAcAOoMAAAEAA8ALgAECn8zAAIEAAkJwxq7FwB5AgAEAAkJwxq7FwB5AgAAAA==.Ashvana:BAACLgAFFH8RAAIDAAQJOyCqKwCAAQRoDAAABABcAGkMAAAGAFgAawwAAAIAQwDqDAAABQBRAAMABAk7IKorAIABBGgMAAAEAFwAaQwAAAYAWABrDAAAAgBDAOoMAAAFAFEALgAECn85AAIDAAkJoSQDEADaAgADAAkJoSQDEADaAgAAAA==.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8oAAMFAAgJ+RWjCgC0AQhoDAAABwBWAGkMAAAHAF0AawwAAAYATgBqDAAABQAjAGwMAAAEACcAbQwAAAEABADqDAAACQA8AG4MAAABAB4ABQAGCVMZowoAtAEGaAwAAAcAVgBpDAAABwBdAGsMAAAGAE4AagwAAAIAIwBtDAAAAQAEAOoMAAAJADwABgADCU8Jdz8AxwADagwAAAMACQBsDAAABAA7AG4MAAABAAMALgAECn8oAAMFAAkJQyKZAwBpAwAFAAkJQyKZAwBpAwAGAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8jAAIHAAgJYxnuAwCcAghoDAAABQApAGkMAAAGAE4AawwAAAYARgBqDAAABQBYAGwMAAAEAFQAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABwAICWMZ7gMAnAIIaAwAAAUAKQBpDAAABgBOAGsMAAAGAEYAagwAAAUAWABsDAAABABUAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBwAJCYIg8AMAMgMABwAJCYIg8AMAMgMACAAGCfYbahwA+AEAAS4ABAoJCR8ACQAEIgA=.',
Be='Bennius:BAABLgAECn8UAAIKAAgJTwtOXQByAQhoDAAABAArAGkMAAADACkAawwAAAMAGQBqDAAAAgApAGwMAAADAC0AbQwAAAEADgDqDAAAAwAaAG4MAAABAAUACgAICU8LTl0AcgEIaAwAAAQAKwBpDAAAAwApAGsMAAADABkAagwAAAIAKQBsDAAAAwAtAG0MAAABAA4A6gwAAAMAGgBuDAAAAQAFAAAA.Benwarrior:BAAALgAECgYJCQABLgAFFAQJBgALAIcXAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJEQAMAGQVAA==.',
Ca='Calan:BAAALgADCgMJAwABLgAFFAMJBQANAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAAKAJ8jAA==.Choco:BAACLgAFFH8LAAIFAAQJJhmfGAApAQRoDAAABAA+AGkMAAACAEsAawwAAAIAOADqDAAAAwA+AAUABAkmGZ8YACkBBGgMAAAEAD4AaQwAAAIASwBrDAAAAgA4AOoMAAADAD4ALgAECn8bAAIFAAgJ5B1IFAAuAgAFAAgJ5B1IFAAuAgAAAA==.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
Cr='Crash:BAEALgAECgIJAgABLgAFFAYJDwAOADAYAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgEJAQAAAA==.Creme:BAABLgAECn8jAAIFAAgJrxvHFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYABQAICa8bxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8MAAIPAAQJExCqEQAxAQRoDAAABQBOAGkMAAAEADQAawwAAAEACADqDAAAAgAYAA8ABAkTEKoRADEBBGgMAAAFAE4AaQwAAAQANABrDAAAAQAIAOoMAAACABgALgAECn85AAIPAAkJaxwVBwChAgAPAAkJaxwVBwChAgAAAA==.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8WAAQQAAcJ0wYfJACkAAdoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQAbQwAAAEAQgDqDAAAAwAIABAABgmVAh8kAKQABmgMAAADAAkAaQwAAAMACABrDAAAAwAFAGoMAAABAAgAbAwAAAEABADqDAAAAgAEAAUABQnxArJwAHQABWgMAAABAAgAaQwAAAEABQBrDAAAAQAHAGoMAAABAAgA6gwAAAEACAAGAAMJLwQUqQBSAANqDAAAAQAJAGwMAAACAAgAbQwAAAEADgAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgcJEgAAAA==.Deralan:BAABLgAECn8kAAMJAAkJhgpzKwBxAQloDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAFAA8AbQwAAAUAHgDqDAAABwAqAG4MAAAFABMAbwwAAAEAIwAJAAkJhgpzKwBxAQloDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAQAIAGwMAAAEAA8AbQwAAAUAHgDqDAAABwAqAG4MAAAFABMAbwwAAAEAIwARAAIJcANUJgAlAAJqDAAAAQAHAGwMAAABAAgAAAA=.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAKAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAISAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQASAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAABLgAECn8WAAIDAAcJjQvNlAAnAQdoDAAABwAlAGkMAAAGACkAawwAAAMAKgBqDAAAAgAcAGwMAAACABUAbQwAAAEACwDqDAAAAQAXAAMABwmNC82UACcBB2gMAAAHACUAaQwAAAYAKQBrDAAAAwAqAGoMAAACABwAbAwAAAIAFQBtDAAAAQALAOoMAAABABcAAAA=.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCAAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIJAAMJ7wdFPQCwAANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAJAAMJ7wdFPQCwAANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8KAAMTAAUJIyMMBACcAQVoDAAAAgBfAGkMAAACAGEAawwAAAIAVwBqDAAAAgARAOoMAAACAE8AEwAECSMjDAQAnAEEaAwAAAIAXwBpDAAAAgBhAGsMAAACAFcA6gwAAAIATwAUAAEJAAD6GgAAAAFqDAAAAgARAC4ABAp/KQADEwAICdAkFAMA5QIAEwAICdAkFAMA5QIAFAAHCZIgoQcAOAIAAAA=.Faengbrew:BAAALgAECgcJDgABLgAFFAUJCgATACMjAA==.Faenghorn:BAAALgAFFAMJBAABLgAFFAUJCgATACMjAA==.Fanah:BAAALgADCggJDgABLgAECgcJKwACAN0dAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgEJAQAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8XAAMSAAgJeQfsPAA7AQhoDAAAAwALAGkMAAADABcAawwAAAMAEQBqDAAAAwAWAGwMAAAEABcAbQwAAAEADADqDAAAAwAXAG4MAAADABUAEgAICXkH7DwAOwEIaAwAAAIACwBpDAAAAgAXAGsMAAACABEAagwAAAIAFgBsDAAAAwAXAG0MAAABAAwA6gwAAAIAFwBuDAAAAgAVABUABwkVBVs6AL4AB2gMAAABAAcAaQwAAAEADwBrDAAAAQAPAGoMAAABAAcAbAwAAAEAEQDqDAAAAQANAG4MAAABAAgAAAA=.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8bAAINAAcJYwmmwwDjAAdoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQBuDAAAAQALAA0ABwljCabDAOMAB2gMAAAGABAAaQwAAAYAHgBrDAAABgAwAGoMAAACABIAbAwAAAIADwDqDAAABAAVAG4MAAABAAsAAAA=.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJCAAWABgJAA==.Gladerbug:BAAALgAECggJCQAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJEQAMAGQVAA==.Grindêlwald:BAACLgAFFH8RAAIMAAQJZBVZFgAGAQRoDAAABgA5AGkMAAAFAFEAawwAAAEACQDqDAAABQBFAAwABAlkFVkWAAYBBGgMAAAGADkAaQwAAAUAUQBrDAAAAQAJAOoMAAAFAEUALgAECn8gAAIMAAkJbBvKCgBKAgAMAAkJbBvKCgBKAgAAAA==.Grindëlwald:BAABLgAECn8eAAIXAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFwAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUBAkRAAwAZBUA.',
Gu='Guac:BAAALgAECgUJEAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgcJKwACAN0dAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8iAAMJAAgJ4RodAgAyAghoDAAABQBaAGkMAAAGAFoAawwAAAUAVgBqDAAABQBZAGwMAAAEAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACQAICYcaHQIAMgIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAUAWQBsDAAABABQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkABEAAwkuG60GAMYAA2gMAAABACgAaQwAAAIAWgBrDAAAAQBNAC4ABAp/JwADCQAJCXAjgwEArgMACQAJCU4jgwEArgMAEQAHCaAl2gUAmwIAAAA=.Ishmonk:BAABLgAECn8xAAMLAAkJwyDCCgB1AgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABwBhAG4MAAAEADsAbwwAAAEAMwAIAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABQBhAAsACQm0HMIKAHUCCWgMAAAEAFQAaQwAAAQAXwBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkiAAkA4RoA.Ishootudead:BAAALgAECggJDwABLgAFFAgJIgAJAOEaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJDwACAHwOAA==.Jon:BAACLgAFFH8MAAIYAAQJLhEnTQAzAQRoDAAABQA/AGkMAAAEADEAawwAAAEAEwDqDAAAAgAqABgABAkuESdNADMBBGgMAAAFAD8AaQwAAAQAMQBrDAAAAQATAOoMAAACACoALgAECn83AAIYAAkJbCCAEQDdAgAYAAkJbCCAEQDdAgAAAA==.Josito:BAAALgAECgQJBAABLgAFFAMJBQANAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8lAAIYAAgJ9RYWSwDiAQhoDAAABQBNAGkMAAAGAD8AawwAAAYASQBqDAAABgBTAGwMAAAEADUAbQwAAAMALADqDAAABQBAAG4MAAACACIAGAAICfUWFksA4gEIaAwAAAUATQBpDAAABgA/AGsMAAAGAEkAagwAAAYAUwBsDAAABAA1AG0MAAADACwA6gwAAAUAQABuDAAAAgAiAAAA.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8eAAMXAAcJcBAMGQA2AQdoDAAABgBQAGkMAAAGADQAawwAAAYAGABqDAAABAAiAGwMAAACACcA6gwAAAQALgBuDAAAAgAIABcABwlwEAwZADYBB2gMAAAGAFAAaQwAAAYANABrDAAABgAYAGoMAAAEACIAbAwAAAIAJwDqDAAAAwAuAG4MAAACAAgADQABCUUDGFgBJwAB6gwAAAEACAAAAA==.',
Ke='Kealee:BAABLgAECn8dAAINAAcJaA5hjAA6AQdoDAAABgA6AGkMAAAGACEAawwAAAYALgBqDAAABAAnAGwMAAACACAA6gwAAAMAIABuDAAAAgASAA0ABwloDmGMADoBB2gMAAAGADoAaQwAAAYAIQBrDAAABgAuAGoMAAAEACcAbAwAAAIAIADqDAAAAwAgAG4MAAACABIAAAA=.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIYAAQJBQbAYQAGAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABgABAkFBsBhAAYBBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMYAAgJ3xTbeABrAQAYAAgJ1xTbeABrAQAZAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMOAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAOAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAaAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8jAAIOAAkJqhfCLAD+AQloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQAOAAkJqhfCLAD+AQloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAABAAAAAA==.Littletop:BAABLgAECn8UAAIbAAgJ4AcNEwD/AAhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGwAICeAHDRMA/wAIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8lAAINAAkJThHkTwC+AQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAACABAAG4MAAADABkAbwwAAAEAUQANAAkJThHkTwC+AQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAACABAAG4MAAADABkAbwwAAAEAUQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn80AAIDAAkJJQt2XgCYAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACAA7AG4MAAAFABQAbwwAAAIAEQADAAkJJQt2XgCYAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACAA7AG4MAAAFABQAbwwAAAIAEQAAAA==.Malex:BAABLgAECn8fAAIJAAkJBCLYBQDnAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAJAAkJBCLYBQDnAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMGAAMJ8Bn7OwDUAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAGAAMJ8Bn7OwDUAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAFAAEJQgy8SAA7AAFpDAAAAQAfAC4ABAp/GwADBQAICWMcahgAUQIABQAHCZsdahgAUQIABgAHCeERY0IAdwEAAS4ABAoJCR8ACQAEIgA=.Malrii:BAAALgAFFAIJAgABLgAECgkJHwAJAAQiAA==.Marselli:BAAALgAECggJEgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAACLgAFFH8GAAIcAAMJbQNONgBvAANoDAAAAwAPAGkMAAACAAgAawwAAAEAAgAcAAMJbQNONgBvAANoDAAAAwAPAGkMAAACAAgAawwAAAEAAgAuAAQKfzgAAhwACQnpD5kbANIBABwACQnpD5kbANIBAAAA.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAINAAgJ0xzaXADMAQhoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIAbQwAAAEASgDqDAAABABPAG4MAAABADoADQAICdMc2lwAzAEIaAwAAAQAUQBpDAAABQBUAGsMAAAFAEgAagwAAAEAUwBsDAAAAwBCAG0MAAABAEoA6gwAAAQATwBuDAAAAQA6AAAA.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMEAAYJsRyAMwC6AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgAEAAYJsRyAMwC6AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAcAAUJ/A6rSwC+AAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIYAAkJbR3rIACEAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAYAAkJbR3rIACEAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMKAAgJnyOWBgAkAwhoDAAABwBcAGkMAAAIAGEAawwAAAYAXwBqDAAAAwBfAGwMAAADAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACgAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAA8ABwkaI9USAAMCB2gMAAAEAFIAaQwAAAQAXABrDAAAAwBfAGoMAAABAF8AbAwAAAIAXADqDAAAAgBNAG4MAAACAGEAAAA=.',
Ph='Phatt:BAABLgAECn8WAAIdAAgJSBUpFQDdAQhoDAAAAwBHAGkMAAAEADkAawwAAAQAOgBqDAAAAwBLAGwMAAACAEgAbQwAAAIAMwDqDAAAAwAwAG4MAAABABUAHQAICUgVKRUA3QEIaAwAAAMARwBpDAAABAA5AGsMAAAEADoAagwAAAMASwBsDAAAAgBIAG0MAAACADMA6gwAAAMAMABuDAAAAQAVAAAA.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIGAAMJGB8BMgD1AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAGAAMJGB8BMgD1AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy8AAgYACAmtJJEJAN8CAAYACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAIDAAYJyQgJwADkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAADAAYJyQgJwADkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAAAAA==.Raghnoll:BAABLgAECn8yAAMeAAkJchboEwBZAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAAEAAsAbwwAAAEANAAeAAkJchboEwBZAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAACAAsAbwwAAAEANAANAAEJ2RaNUAFCAAFuDAAAAgA6AAAA.',
Re='Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAIfAAQJ8wT5FwDBAARoDAAABQAWAGkMAAAEAAgAawwAAAEAAwDqDAAAAgAQAB8ABAnzBPkXAMEABGgMAAAFABYAaQwAAAQACABrDAAAAQADAOoMAAACABAALgAECn8xAAIfAAkJgBD7EQCyAQAfAAkJgBD7EQCyAQAAAA==.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgYJDwABLgAFFAMJBQANAD0lAA==.Sariar:BAAALgAECgEJAQABLgAFFAMJBQANAD0lAA==.Sartorius:BAABLgAECn8fAAIcAAkJEAmiLQBPAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAcAAkJEAmiLQBPAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGwAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIYAAkJXAMcowAbAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAYAAkJXAMcowAbAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAAAA==.Sciel:BAABLgAECn8fAAIFAAgJ3CGPFAB6AghoDAAAAwBaAGkMAAAGAF4AawwAAAUAUwBqDAAAAwBcAGwMAAAEAEgAbQwAAAMAUgDqDAAABQBWAG4MAAACAGAABQAICdwhjxQAegIIaAwAAAMAWgBpDAAABgBeAGsMAAAFAFMAagwAAAMAXABsDAAABABIAG0MAAADAFIA6gwAAAUAVgBuDAAAAgBgAAAA.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNgADAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIIAAkJLwgcOgD+AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAIAAkJLwgcOgD+AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8YAAIKAAcJ2hPvcABEAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAoABwnaE+9wAEQBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJJQAfAKweAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAYAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8SAAIGAAQJ/RivIwAxAQRoDAAABgBUAGkMAAAFAFAAawwAAAIAGgDqDAAABQBAAAYABAn9GK8jADEBBGgMAAAGAFQAaQwAAAUAUABrDAAAAgAaAOoMAAAFAEAALgAECn87AAIGAAkJBSXBAQCjAwAGAAkJBSXBAQCjAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLAAgAFwlAA==.Tip:BAAALgAECgUJCQAAAA==.',
To='Topaten:BAACLgAFFH8JAAIKAAQJKAfWPQAQAQRoDAAAAwASAGkMAAADABIAawwAAAEACQDqDAAAAgAbAAoABAkoB9Y9ABABBGgMAAADABIAaQwAAAMAEgBrDAAAAQAJAOoMAAACABsALgAECn8aAAIKAAkJKBeXHwBRAgAKAAkJKBeXHwBRAgAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAINAAkJ7hNePgDxAQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAANAAkJ7hNePgDxAQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgQJBAABAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgQJBAAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMhAAcJKB1NFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfACEABwnSHE0VADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AAgAHCeUYjyAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgABAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAUJEAAeALoZAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAECgkJBgABAAAAAA==.',
['Àl']='Àlilith:BAABLgAECn8eAAINAAkJ/BoLLwApAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACgBiAG4MAAABADQAbwwAAAEAUwANAAkJ/BoLLwApAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACgBiAG4MAAABADQAbwwAAAEAUwAAAA==.',
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
