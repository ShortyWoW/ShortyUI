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

local lookup = {'Unknown-Unknown','Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Rogue-Subtlety','Paladin-Holy','Warrior-Protection','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-30',data={Ak='Akuma:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Al='Alilith:BAAALgAECgcJCAAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8PAAICAAcJfA5NDQADAgdoDAAAAgAuAGkMAAACABYAawwAAAIAKABqDAAAAgAhAGwMAAACADYA6gwAAAQAPABuDAAAAQACAAIABwl8Dk0NAAMCB2gMAAACAC4AaQwAAAIAFgBrDAAAAgAoAGoMAAACACEAbAwAAAIANgDqDAAABAA8AG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAIDAAIJsx6ztACQAAJoDAAABABMAOoMAAAEAFAAAwACCbMes7QAkAACaAwAAAQATADqDAAABABQAAAA.',
As='Asecretbear:BAACLgAFFH8OAAIEAAQJYQx2LAD0AARoDAAABQAwAGkMAAAEACEAawwAAAEAHADqDAAABAAPAAQABAlhDHYsAPQABGgMAAAFADAAaQwAAAQAIQBrDAAAAQAcAOoMAAAEAA8ALgAECn8zAAIEAAkJwxq7FwB5AgAEAAkJwxq7FwB5AgAAAA==.Ashvana:BAACLgAFFH8RAAIDAAQJOyBRLQB/AQRoDAAABABcAGkMAAAGAFgAawwAAAIAQwDqDAAABQBRAAMABAk7IFEtAH8BBGgMAAAEAFwAaQwAAAYAWABrDAAAAgBDAOoMAAAFAFEALgAECn85AAIDAAkJoSQ6EADZAgADAAkJoSQ6EADZAgAAAA==.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8oAAMFAAgJ+RUKCwCzAQhoDAAABwBWAGkMAAAHAF0AawwAAAYATgBqDAAABQAjAGwMAAAEACcAbQwAAAEABADqDAAACQA8AG4MAAABAB4ABQAGCVMZCgsAswEGaAwAAAcAVgBpDAAABwBdAGsMAAAGAE4AagwAAAIAIwBtDAAAAQAEAOoMAAAJADwABgADCU8JjUAAxwADagwAAAMACQBsDAAABAA7AG4MAAABAAMALgAECn8oAAMFAAkJQyKZAwBpAwAFAAkJQyKZAwBpAwAGAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8jAAIHAAgJYxkmBACbAghoDAAABQApAGkMAAAGAE4AawwAAAYARgBqDAAABQBYAGwMAAAEAFQAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABwAICWMZJgQAmwIIaAwAAAUAKQBpDAAABgBOAGsMAAAGAEYAagwAAAUAWABsDAAABABUAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBwAJCYIg8AMAMgMABwAJCYIg8AMAMgMACAAGCfYbahwA+AEAAS4ABAoJCR8ACQAEIgA=.',
Be='Bennius:BAABLgAECn8UAAIKAAgJTwtIXgByAQhoDAAABAArAGkMAAADACkAawwAAAMAGQBqDAAAAgApAGwMAAADAC0AbQwAAAEADgDqDAAAAwAaAG4MAAABAAUACgAICU8LSF4AcgEIaAwAAAQAKwBpDAAAAwApAGsMAAADABkAagwAAAIAKQBsDAAAAwAtAG0MAAABAA4A6gwAAAMAGgBuDAAAAQAFAAAA.Benwarrior:BAAALgAECgYJCQABLgAFFAYJEAALAP4aAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJEQALAGQVAA==.',
Ca='Calan:BAAALgADCgMJAwABLgAFFAMJBQAMAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAAKAJ8jAA==.Choco:BAACLgAFFH8LAAIFAAQJJhlNGQAnAQRoDAAABAA+AGkMAAACAEsAawwAAAIAOADqDAAAAwA+AAUABAkmGU0ZACcBBGgMAAAEAD4AaQwAAAIASwBrDAAAAgA4AOoMAAADAD4ALgAECn8bAAIFAAgJ5B13FAAuAgAFAAgJ5B13FAAuAgAAAA==.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
Cr='Crash:BAEALgAECgIJAgABLgAFFAYJDwANADAYAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgEJAQAAAA==.Creme:BAABLgAECn8jAAIFAAgJrxvHFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYABQAICa8bxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8MAAIOAAQJExDxEQAxAQRoDAAABQBOAGkMAAAEADQAawwAAAEACADqDAAAAgAYAA4ABAkTEPERADEBBGgMAAAFAE4AaQwAAAQANABrDAAAAQAIAOoMAAACABgALgAECn85AAIOAAkJaxwyBwCgAgAOAAkJaxwyBwCgAgAAAA==.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8WAAQPAAcJ0waLJACkAAdoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQAbQwAAAEAQgDqDAAAAwAIAA8ABgmVAoskAKQABmgMAAADAAkAaQwAAAMACABrDAAAAwAFAGoMAAABAAgAbAwAAAEABADqDAAAAgAEAAUABQnxAqFxAHQABWgMAAABAAgAaQwAAAEABQBrDAAAAQAHAGoMAAABAAgA6gwAAAEACAAGAAMJLwSoqgBSAANqDAAAAQAJAGwMAAACAAgAbQwAAAEADgAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAABLgAECn8UAAQGAAcJcBhzLQDnAQdoDAAAAgA8AGkMAAACACoAawwAAAMAOABqDAAAAgBIAGwMAAAFAFcAbQwAAAIARwDqDAAABAAuAAYABwlwGHMtAOcBB2gMAAABADwAaQwAAAIAKgBrDAAAAwA4AGoMAAACAEgAbAwAAAIAVwBtDAAAAgBHAOoMAAACAC4ABQADCT8M4WwAggADaAwAAAEAEgBsDAAAAgAmAOoMAAACACQADwABCWQOSDMANwABbAwAAAEAJAAAAA==.Deralan:BAABLgAECn8kAAMJAAkJhgrTKwBxAQloDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAFAA8AbQwAAAUAHgDqDAAABwAqAG4MAAAFABMAbwwAAAEAIwAJAAkJhgrTKwBxAQloDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAQAIAGwMAAAEAA8AbQwAAAUAHgDqDAAABwAqAG4MAAAFABMAbwwAAAEAIwAQAAIJcAOeJgAlAAJqDAAAAQAHAGwMAAABAAgAAAA=.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAKAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIRAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQARAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAABLgAECn8WAAIDAAcJjQvWlQAnAQdoDAAABwAlAGkMAAAGACkAawwAAAMAKgBqDAAAAgAcAGwMAAACABUAbQwAAAEACwDqDAAAAQAXAAMABwmNC9aVACcBB2gMAAAHACUAaQwAAAYAKQBrDAAAAwAqAGoMAAACABwAbAwAAAIAFQBtDAAAAQALAOoMAAABABcAAAA=.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCAAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIJAAMJ7wdFPgCtAANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAJAAMJ7wdFPgCtAANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8KAAMSAAUJIyMpBACcAQVoDAAAAgBfAGkMAAACAGEAawwAAAIAVwBqDAAAAgARAOoMAAACAE8AEgAECSMjKQQAnAEEaAwAAAIAXwBpDAAAAgBhAGsMAAACAFcA6gwAAAIATwATAAEJAAC3GwAAAAFqDAAAAgARAC4ABAp/KQADEgAICdAkKAMA5AIAEgAICdAkKAMA5AIAEwAHCZIgugcANwIAAAA=.Faengbrew:BAAALgAECgcJDgABLgAFFAUJCgASACMjAA==.Faenghorn:BAAALgAFFAMJBAABLgAFFAUJCgASACMjAA==.Fanah:BAAALgADCggJFgABLgAECgcJKwACAN0dAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgEJAQAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8XAAMRAAgJeQesPQA5AQhoDAAAAwALAGkMAAADABcAawwAAAMAEQBqDAAAAwAWAGwMAAAEABcAbQwAAAEADADqDAAAAwAXAG4MAAADABUAEQAICXkHrD0AOQEIaAwAAAIACwBpDAAAAgAXAGsMAAACABEAagwAAAIAFgBsDAAAAwAXAG0MAAABAAwA6gwAAAIAFwBuDAAAAgAVABQABwkVBQA7AL4AB2gMAAABAAcAaQwAAAEADwBrDAAAAQAPAGoMAAABAAcAbAwAAAEAEQDqDAAAAQANAG4MAAABAAgAAAA=.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8bAAIMAAcJYwlpxQDjAAdoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQBuDAAAAQALAAwABwljCWnFAOMAB2gMAAAGABAAaQwAAAYAHgBrDAAABgAwAGoMAAACABIAbAwAAAIADwDqDAAABAAVAG4MAAABAAsAAAA=.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJCAAVABgJAA==.Gladerbug:BAAALgAECggJCQAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJEQALAGQVAA==.Grindêlwald:BAACLgAFFH8RAAILAAQJZBXwFgAFAQRoDAAABgA5AGkMAAAFAFEAawwAAAEACQDqDAAABQBFAAsABAlkFfAWAAUBBGgMAAAGADkAaQwAAAUAUQBrDAAAAQAJAOoMAAAFAEUALgAECn8gAAILAAkJbBvrCgBJAgALAAkJbBvrCgBJAgAAAA==.Grindëlwald:BAABLgAECn8eAAIWAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFgAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUBAkRAAsAZBUA.',
Gu='Guac:BAAALgAECgUJEAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgcJKwACAN0dAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8iAAMJAAgJ4RodAgAyAghoDAAABQBaAGkMAAAGAFoAawwAAAUAVgBqDAAABQBZAGwMAAAEAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACQAICYcaHQIAMgIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAUAWQBsDAAABABQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkABAAAwkuG7sGAMYAA2gMAAABACgAaQwAAAIAWgBrDAAAAQBNAC4ABAp/JwADCQAJCXAjgwEArgMACQAJCU4jgwEArgMAEAAHCaAl2gUAmwIAAAA=.Ishmonk:BAABLgAECn8xAAMXAAkJwyDdCgB1AgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABwBhAG4MAAAEADsAbwwAAAEAMwAIAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABQBhABcACQm0HN0KAHUCCWgMAAAEAFQAaQwAAAQAXwBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkiAAkA4RoA.Ishootudead:BAAALgAECggJDwABLgAFFAgJIgAJAOEaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJDwACAHwOAA==.Jon:BAACLgAFFH8MAAIYAAQJLhF7TgAzAQRoDAAABQA/AGkMAAAEADEAawwAAAEAEwDqDAAAAgAqABgABAkuEXtOADMBBGgMAAAFAD8AaQwAAAQAMQBrDAAAAQATAOoMAAACACoALgAECn83AAIYAAkJbCDFEQDcAgAYAAkJbCDFEQDcAgAAAA==.Josito:BAAALgAECgQJBAABLgAFFAMJBQAMAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8lAAIYAAgJ9RaLSwDhAQhoDAAABQBNAGkMAAAGAD8AawwAAAYASQBqDAAABgBTAGwMAAAEADUAbQwAAAMALADqDAAABQBAAG4MAAACACIAGAAICfUWi0sA4QEIaAwAAAUATQBpDAAABgA/AGsMAAAGAEkAagwAAAYAUwBsDAAABAA1AG0MAAADACwA6gwAAAUAQABuDAAAAgAiAAAA.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8eAAMWAAcJcBBCGQA2AQdoDAAABgBQAGkMAAAGADQAawwAAAYAGABqDAAABAAiAGwMAAACACcA6gwAAAQALgBuDAAAAgAIABYABwlwEEIZADYBB2gMAAAGAFAAaQwAAAYANABrDAAABgAYAGoMAAAEACIAbAwAAAIAJwDqDAAAAwAuAG4MAAACAAgADAABCUUDGFgBJwAB6gwAAAEACAAAAA==.',
Ke='Kealee:BAABLgAECn8dAAIMAAcJaA7WjQA6AQdoDAAABgA6AGkMAAAGACEAawwAAAYALgBqDAAABAAnAGwMAAACACAA6gwAAAMAIABuDAAAAgASAAwABwloDtaNADoBB2gMAAAGADoAaQwAAAYAIQBrDAAABgAuAGoMAAAEACcAbAwAAAIAIADqDAAAAwAgAG4MAAACABIAAAA=.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIYAAQJBQbnYgAGAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABgABAkFBudiAAYBBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMYAAgJ3xRpeQBqAQAYAAgJ1xRpeQBqAQAZAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMNAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAANAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAaAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8jAAINAAkJqhcvLQD9AQloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQANAAkJqhcvLQD9AQloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAABAAAAAA==.Littletop:BAABLgAECn8UAAIbAAgJ4AdTEwD8AAhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGwAICeAHUxMA/AAIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8lAAIMAAkJThG0UAC+AQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAACABAAG4MAAADABkAbwwAAAEAUQAMAAkJThG0UAC+AQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAACABAAG4MAAADABkAbwwAAAEAUQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn80AAIDAAkJJQuHXwCXAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACAA7AG4MAAAFABQAbwwAAAIAEQADAAkJJQuHXwCXAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACAA7AG4MAAAFABQAbwwAAAIAEQAAAA==.Malex:BAABLgAECn8fAAIJAAkJBCLnBQDnAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAJAAkJBCLnBQDnAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMGAAMJ8BkJPQDUAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAGAAMJ8BkJPQDUAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAFAAEJQgzHSQA7AAFpDAAAAQAfAC4ABAp/GwADBQAICWMcahgAUQIABQAHCZsdahgAUQIABgAHCeERY0IAdwEAAS4ABAoJCR8ACQAEIgA=.Malrii:BAAALgAFFAIJAgABLgAECgkJHwAJAAQiAA==.Marselli:BAAALgAECggJEgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAACLgAFFH8GAAIcAAMJbQMhNwBvAANoDAAAAwAPAGkMAAACAAgAawwAAAEAAgAcAAMJbQMhNwBvAANoDAAAAwAPAGkMAAACAAgAawwAAAEAAgAuAAQKfzgAAhwACQnpD98bANEBABwACQnpD98bANEBAAAA.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAIMAAgJ0xzaXADMAQhoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIAbQwAAAEASgDqDAAABABPAG4MAAABADoADAAICdMc2lwAzAEIaAwAAAQAUQBpDAAABQBUAGsMAAAFAEgAagwAAAEAUwBsDAAAAwBCAG0MAAABAEoA6gwAAAQATwBuDAAAAQA6AAAA.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMEAAYJsRzHMwC6AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgAEAAYJsRzHMwC6AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAcAAUJ/A5LTAC+AAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIYAAkJbR2CIQCCAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAYAAkJbR2CIQCCAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMKAAgJnyOWBgAkAwhoDAAABwBcAGkMAAAIAGEAawwAAAYAXwBqDAAAAwBfAGwMAAADAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACgAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAA4ABwkaIxETAAMCB2gMAAAEAFIAaQwAAAQAXABrDAAAAwBfAGoMAAABAF8AbAwAAAIAXADqDAAAAgBNAG4MAAACAGEAAAA=.',
Ph='Phatt:BAABLgAECn8WAAIdAAgJSBVcFQDcAQhoDAAAAwBHAGkMAAAEADkAawwAAAQAOgBqDAAAAwBLAGwMAAACAEgAbQwAAAIAMwDqDAAAAwAwAG4MAAABABUAHQAICUgVXBUA3AEIaAwAAAMARwBpDAAABAA5AGsMAAAEADoAagwAAAMASwBsDAAAAgBIAG0MAAACADMA6gwAAAMAMABuDAAAAQAVAAAA.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIGAAMJGB8xMwD0AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAGAAMJGB8xMwD0AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy8AAgYACAmtJJEJAN8CAAYACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAIDAAYJyQh1wQDkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAADAAYJyQh1wQDkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAAAAA==.Raghnoll:BAABLgAECn8yAAMeAAkJchYZFABYAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAAEAAsAbwwAAAEANAAeAAkJchYZFABYAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAACAAsAbwwAAAEANAAMAAEJ2RaQUwFCAAFuDAAAAgA6AAAA.',
Re='Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAIfAAQJ8wR+GAC8AARoDAAABQAWAGkMAAAEAAgAawwAAAEAAwDqDAAAAgAQAB8ABAnzBH4YALwABGgMAAAFABYAaQwAAAQACABrDAAAAQADAOoMAAACABAALgAECn8xAAIfAAkJgBA9EgCvAQAfAAkJgBA9EgCvAQAAAA==.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgYJDwABLgAFFAMJBQAMAD0lAA==.Sariar:BAAALgAECgEJAQABLgAFFAMJBQAMAD0lAA==.Sartorius:BAABLgAECn8fAAIcAAkJEAkcLgBPAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAcAAkJEAkcLgBPAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGwAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIYAAkJXAP4owAaAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAYAAkJXAP4owAaAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAAAA==.Sciel:BAABLgAECn8fAAIFAAgJ3CGPFAB6AghoDAAAAwBaAGkMAAAGAF4AawwAAAUAUwBqDAAAAwBcAGwMAAAEAEgAbQwAAAMAUgDqDAAABQBWAG4MAAACAGAABQAICdwhjxQAegIIaAwAAAMAWgBpDAAABgBeAGsMAAAFAFMAagwAAAMAXABsDAAABABIAG0MAAADAFIA6gwAAAUAVgBuDAAAAgBgAAAA.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNwADAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIIAAkJLwijOgD9AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAIAAkJLwijOgD9AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8YAAIKAAcJ2hMNcgBDAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAoABwnaEw1yAEMBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJJQAfAKweAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAYAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8SAAIGAAQJ/RiuJAAwAQRoDAAABgBUAGkMAAAFAFAAawwAAAIAGgDqDAAABQBAAAYABAn9GK4kADABBGgMAAAGAFQAaQwAAAUAUABrDAAAAgAaAOoMAAAFAEAALgAECn87AAIGAAkJBSXSAQCiAwAGAAkJBSXSAQCiAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLAAgAFwlAA==.Tip:BAAALgAECgUJCQAAAA==.',
To='Topaten:BAACLgAFFH8JAAIKAAQJKAchPwAPAQRoDAAAAwASAGkMAAADABIAawwAAAEACQDqDAAAAgAbAAoABAkoByE/AA8BBGgMAAADABIAaQwAAAMAEgBrDAAAAQAJAOoMAAACABsALgAECn8aAAIKAAkJKBcIIABRAgAKAAkJKBcIIABRAgAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAIMAAkJ7hM2PwDxAQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAAMAAkJ7hM2PwDxAQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAAAAA==.',
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
['Àl']='Àlilith:BAABLgAECn8eAAIMAAkJ/BqoLwApAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACgBiAG4MAAABADQAbwwAAAEAUwAMAAkJ/BqoLwApAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACgBiAG4MAAABADQAbwwAAAEAUwAAAA==.',
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
