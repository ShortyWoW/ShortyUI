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

local lookup = {'Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Rogue-Subtlety','Paladin-Holy','Warrior-Protection','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-06-03',data={Ak='Akuma:BAAALgAECgEJAwAAAA==.',
Al='Alilith:BAAALgAECgcJCAAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8PAAIBAAcJfA70DgD6AQdoDAAAAgAuAGkMAAACABYAawwAAAIAKABqDAAAAgAhAGwMAAACADYA6gwAAAQAPABuDAAAAQACAAEABwl8DvQOAPoBB2gMAAACAC4AaQwAAAIAFgBrDAAAAgAoAGoMAAACACEAbAwAAAIANgDqDAAABAA8AG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAICAAIJsx5KvgCQAAJoDAAABABMAOoMAAAEAFAAAgACCbMeSr4AkAACaAwAAAQATADqDAAABABQAAAA.',
As='Asecretbear:BAACLgAFFH8OAAIDAAQJYQzJLgDwAARoDAAABQAwAGkMAAAEACEAawwAAAEAHADqDAAABAAPAAMABAlhDMkuAPAABGgMAAAFADAAaQwAAAQAIQBrDAAAAQAcAOoMAAAEAA8ALgAECn8zAAIDAAkJwxq7FwB5AgADAAkJwxq7FwB5AgAAAA==.Asecretwolf:BAAALgAECgUJBQAAAA==.Ashvana:BAACLgAFFH8RAAICAAQJOyD/MgB7AQRoDAAABABcAGkMAAAGAFgAawwAAAIAQwDqDAAABQBRAAIABAk7IP8yAHsBBGgMAAAEAFwAaQwAAAYAWABrDAAAAgBDAOoMAAAFAFEALgAECn85AAICAAkJoSQyEQDXAgACAAkJoSQyEQDXAgAAAA==.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8oAAMEAAgJ+RXcDACtAQhoDAAABwBWAGkMAAAHAF0AawwAAAYATgBqDAAABQAjAGwMAAAEACcAbQwAAAEABADqDAAACQA8AG4MAAABAB4ABAAGCVMZ3AwArQEGaAwAAAcAVgBpDAAABwBdAGsMAAAGAE4AagwAAAIAIwBtDAAAAQAEAOoMAAAJADwABQADCU8JxEIAxwADagwAAAMACQBsDAAABAA7AG4MAAABAAMALgAECn8oAAMEAAkJQyKZAwBpAwAEAAkJQyKZAwBpAwAFAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8jAAIGAAgJYxk2BQCPAghoDAAABQApAGkMAAAGAE4AawwAAAYARgBqDAAABQBYAGwMAAAEAFQAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABgAICWMZNgUAjwIIaAwAAAUAKQBpDAAABgBOAGsMAAAGAEYAagwAAAUAWABsDAAABABUAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBgAJCYIg8AMAMgMABgAJCYIg8AMAMgMABwAGCfYbahwA+AEAAS4ABAoJCR8ACAAEIgA=.',
Be='Bennius:BAABLgAECn8VAAIJAAgJ0AtmXACAAQhoDAAABAArAGkMAAADACkAawwAAAMAGQBqDAAAAgApAGwMAAADAC0AbQwAAAEADgDqDAAAAwAaAG4MAAACAA4ACQAICdALZlwAgAEIaAwAAAQAKwBpDAAAAwApAGsMAAADABkAagwAAAIAKQBsDAAAAwAtAG0MAAABAA4A6gwAAAMAGgBuDAAAAgAOAAAA.Benwarrior:BAAALgAECgYJDQABLgAFFAYJEAAKAP4aAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bi='Bigbeech:BAAALgAECgQJBAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJEQAKAGQVAA==.',
Ca='Calan:BAAALgADCgUJCAABLgAFFAMJBQALAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAAJAJ8jAA==.Choco:BAACLgAFFH8LAAIEAAQJJhl2GwAkAQRoDAAABAA+AGkMAAACAEsAawwAAAIAOADqDAAAAwA+AAQABAkmGXYbACQBBGgMAAAEAD4AaQwAAAIASwBrDAAAAgA4AOoMAAADAD4ALgAECn8bAAIEAAgJ5B1vFQAsAgAEAAgJ5B1vFQAsAgAAAA==.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAgABLgAECgQJBQAMAAAAAA==.',
Cr='Crash:BAEALgAECgIJAgABLgAFFAYJEAANADAYAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgEJAgAAAA==.Creme:BAABLgAECn8kAAIEAAgJGR3HFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABgBfAG4MAAADAEYABAAICRkdxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAYAXwBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8MAAIOAAQJExACEwAtAQRoDAAABQBOAGkMAAAEADQAawwAAAEACADqDAAAAgAYAA4ABAkTEAITAC0BBGgMAAAFAE4AaQwAAAQANABrDAAAAQAIAOoMAAACABgALgAECn86AAIOAAkJaxydBwCcAgAOAAkJaxydBwCcAgAAAA==.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8WAAQPAAcJ0wY+JgCkAAdoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQAbQwAAAEAQgDqDAAAAwAIAA8ABgmVAj4mAKQABmgMAAADAAkAaQwAAAMACABrDAAAAwAFAGoMAAABAAgAbAwAAAEABADqDAAAAgAEAAQABQnxAoN1AHQABWgMAAABAAgAaQwAAAEABQBrDAAAAQAHAGoMAAABAAgA6gwAAAEACAAFAAMJLwRcsABSAANqDAAAAQAJAGwMAAACAAgAbQwAAAEADgAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAABLgAECn8WAAQFAAgJABx5JAAgAghoDAAAAgA8AGkMAAACACoAawwAAAMAOABqDAAAAgBIAGwMAAAFAFcAbQwAAAIARwDqDAAABQBeAG4MAAABAFcABQAHCSEbeSQAIAIHaAwAAAEAPABpDAAAAgAqAGsMAAADADgAagwAAAIASABsDAAAAgBXAG0MAAACAEcA6gwAAAMAXgAEAAMJPwykcACCAANoDAAAAQASAGwMAAACACYA6gwAAAIAJAAPAAIJYw0XLABtAAJsDAAAAQAkAG4MAAABAB8AAAA=.Deralan:BAABLgAECn8kAAMIAAkJhgq+KwCCAQloDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAFAA8AbQwAAAUAHgDqDAAABwAqAG4MAAAFABMAbwwAAAEAIwAIAAkJhgq+KwCCAQloDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAQAIAGwMAAAEAA8AbQwAAAUAHgDqDAAABwAqAG4MAAAFABMAbwwAAAEAIwAQAAIJcAPcJwAkAAJqDAAAAQAHAGwMAAABAAgAAAA=.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAJAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgABLgAFFAQJCAARAP4YAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIRAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQARAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAABLgAECn8WAAICAAcJjQsumgAnAQdoDAAABwAlAGkMAAAGACkAawwAAAMAKgBqDAAAAgAcAGwMAAACABUAbQwAAAEACwDqDAAAAQAXAAIABwmNCy6aACcBB2gMAAAHACUAaQwAAAYAKQBrDAAAAwAqAGoMAAACABwAbAwAAAIAFQBtDAAAAQALAOoMAAABABcAAAA=.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCAAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIIAAMJ7wfWQQCpAANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAIAAMJ7wfWQQCpAANoDAAAAwAZAGkMAAADABMA6gwAAAIADwAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8LAAMSAAUJIyPBBACYAQVoDAAAAgBfAGkMAAACAGEAawwAAAIAVwBqDAAAAgARAOoMAAADAE8AEgAECSMjwQQAmAEEaAwAAAIAXwBpDAAAAgBhAGsMAAACAFcA6gwAAAMATwATAAEJAACUHgAAAAFqDAAAAgARAC4ABAp/KQADEgAICdAkWgMA5AIAEgAICdAkWgMA5AIAEwAHCZIgLQgANgIAAAA=.Faengbrew:BAAALgAECgcJDgABLgAFFAUJCwASACMjAA==.Faenghorn:BAABLgAFFH8IAAISAAQJ5CNWBACkAQRoDAAAAgBaAGkMAAACAFwAawwAAAEAXQDqDAAAAwBaABIABAnkI1YEAKQBBGgMAAACAFoAaQwAAAIAXABrDAAAAQBdAOoMAAADAFoAAS4ABRQFCQsAEgAjIwA=.Fanah:BAAALgADCggJFgABLgAECgcJKwABAN0dAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgEJAQAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8XAAMRAAgJeQd5PwA5AQhoDAAAAwALAGkMAAADABcAawwAAAMAEQBqDAAAAwAWAGwMAAAEABcAbQwAAAEADADqDAAAAwAXAG4MAAADABUAEQAICXkHeT8AOQEIaAwAAAIACwBpDAAAAgAXAGsMAAACABEAagwAAAIAFgBsDAAAAwAXAG0MAAABAAwA6gwAAAIAFwBuDAAAAgAVABQABwkVBdE9ALwAB2gMAAABAAcAaQwAAAEADwBrDAAAAQAPAGoMAAABAAcAbAwAAAEAEQDqDAAAAQANAG4MAAABAAgAAAA=.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8gAAILAAcJtwnPyADtAAdoDAAABwAQAGkMAAAHAB8AawwAAAcAMABqDAAAAwAUAGwMAAADABMA6gwAAAQAFQBuDAAAAQALAAsABwm3Cc/IAO0AB2gMAAAHABAAaQwAAAcAHwBrDAAABwAwAGoMAAADABQAbAwAAAMAEwDqDAAABAAVAG4MAAABAAsAAAA=.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJCAAVABgJAA==.Gladerbug:BAAALgAECggJCQAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Go='Gordenesh:BAAALgADCgUJBQAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJEQAKAGQVAA==.Grindêlwald:BAACLgAFFH8RAAIKAAQJZBXyGAD/AARoDAAABgA5AGkMAAAFAFEAawwAAAEACQDqDAAABQBFAAoABAlkFfIYAP8ABGgMAAAGADkAaQwAAAUAUQBrDAAAAQAJAOoMAAAFAEUALgAECn8gAAIKAAkJbBtlCwBHAgAKAAkJbBtlCwBHAgAAAA==.Grindëlwald:BAABLgAECn8eAAIWAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFgAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUBAkRAAoAZBUA.',
Gu='Guac:BAAALgAECgUJEAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgcJKwABAN0dAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8iAAMIAAgJ4RodAgAyAghoDAAABQBaAGkMAAAGAFoAawwAAAUAVgBqDAAABQBZAGwMAAAEAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACAAICYcaHQIAMgIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAUAWQBsDAAABABQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkABAAAwkuGxEHAMUAA2gMAAABACgAaQwAAAIAWgBrDAAAAQBNAC4ABAp/JwADCAAJCXAjgwEArgMACAAJCU4jgwEArgMAEAAHCaAl2gUAmwIAAAA=.Ishmonk:BAABLgAECn8xAAMXAAkJwyBJCwB0AgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABwBhAG4MAAAEADsAbwwAAAEAMwAHAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABQBhABcACQm0HEkLAHQCCWgMAAAEAFQAaQwAAAQAXwBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkiAAgA4RoA.Ishootudead:BAAALgAECggJDwABLgAFFAgJIgAIAOEaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJDwABAHwOAA==.Jon:BAACLgAFFH8MAAIYAAQJLhFDUwAwAQRoDAAABQA/AGkMAAAEADEAawwAAAEAEwDqDAAAAgAqABgABAkuEUNTADABBGgMAAAFAD8AaQwAAAQAMQBrDAAAAQATAOoMAAACACoALgAECn84AAIYAAkJbCDcEgDgAgAYAAkJbCDcEgDgAgAAAA==.Josito:BAAALgAECgQJBAABLgAFFAMJBQALAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8sAAIYAAgJ1BekRQAAAghoDAAABgBNAGkMAAAHAEYAawwAAAcASQBqDAAABwBUAGwMAAAFADUAbQwAAAQANADqDAAABgBBAG4MAAACACIAGAAICdQXpEUAAAIIaAwAAAYATQBpDAAABwBGAGsMAAAHAEkAagwAAAcAVABsDAAABQA1AG0MAAAEADQA6gwAAAYAQQBuDAAAAgAiAAAA.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8eAAMWAAcJcBD9GQA2AQdoDAAABgBQAGkMAAAGADQAawwAAAYAGABqDAAABAAiAGwMAAACACcA6gwAAAQALgBuDAAAAgAIABYABwlwEP0ZADYBB2gMAAAGAFAAaQwAAAYANABrDAAABgAYAGoMAAAEACIAbAwAAAIAJwDqDAAAAwAuAG4MAAACAAgACwABCUUDGFgBJwAB6gwAAAEACAAAAA==.',
Ke='Kealee:BAABLgAECn8dAAILAAcJaA6elAA7AQdoDAAABgA6AGkMAAAGACEAawwAAAYALgBqDAAABAAnAGwMAAACACAA6gwAAAMAIABuDAAAAgASAAsABwloDp6UADsBB2gMAAAGADoAaQwAAAYAIQBrDAAABgAuAGoMAAAEACcAbAwAAAIAIADqDAAAAwAgAG4MAAACABIAAAA=.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgAECgIJAgAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIYAAQJBQaDZwACAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABgABAkFBoNnAAIBBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMYAAgJ3xTTfQBxAQAYAAgJ1xTTfQBxAQAZAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMNAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAANAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAaAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8jAAINAAkJqheELgAAAgloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQANAAkJqheELgAAAgloDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJgDqDAAABQAyAG4MAAADAEIAbwwAAAEALQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAMAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAMAAAAAA==.Littletop:BAABLgAECn8UAAIbAAgJ4AcEFAD8AAhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGwAICeAHBBQA/AAIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8lAAILAAkJThHZTwDKAQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAACABAAG4MAAADABkAbwwAAAEAUQALAAkJThHZTwDKAQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAACABAAG4MAAADABkAbwwAAAEAUQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn81AAICAAkJJwsyYgCXAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACQA7AG4MAAAFABQAbwwAAAIAEQACAAkJJwsyYgCXAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAACQA7AG4MAAAFABQAbwwAAAIAEQAAAA==.Malex:BAABLgAECn8fAAIIAAkJBCInBgDvAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAIAAkJBCInBgDvAgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8BnpQQDKAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAFAAMJ8BnpQQDKAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAEAAEJQgy0TQA7AAFpDAAAAQAfAC4ABAp/GwADBAAICWMcahgAUQIABAAHCZsdahgAUQIABQAHCeERY0IAdwEAAS4ABAoJCR8ACAAEIgA=.Malrii:BAAALgAFFAIJAgABLgAECgkJHwAIAAQiAA==.Marselli:BAAALgAECggJEgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAACLgAFFH8GAAIcAAMJbQPeOQBvAANoDAAAAwAPAGkMAAACAAgAawwAAAEAAgAcAAMJbQPeOQBvAANoDAAAAwAPAGkMAAACAAgAawwAAAEAAgAuAAQKfzkAAhwACQnpDxodAM4BABwACQnpDxodAM4BAAAA.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAILAAgJ0xzaXADMAQhoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIAbQwAAAEASgDqDAAABABPAG4MAAABADoACwAICdMc2lwAzAEIaAwAAAQAUQBpDAAABQBUAGsMAAAFAEgAagwAAAEAUwBsDAAAAwBCAG0MAAABAEoA6gwAAAQATwBuDAAAAQA6AAAA.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRzqNAC6AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgADAAYJsRzqNAC6AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAcAAUJ/A6MTgC+AAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIYAAkJbR3OIgCIAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAYAAkJbR3OIgCIAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMJAAgJnyOWBgAkAwhoDAAABwBcAGkMAAAIAGEAawwAAAYAXwBqDAAAAwBfAGwMAAADAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACQAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAA4ABwkaI7gTAAECB2gMAAAEAFIAaQwAAAQAXABrDAAAAwBfAGoMAAABAF8AbAwAAAIAXADqDAAAAgBNAG4MAAACAGEAAAA=.',
Ph='Phatt:BAABLgAECn8aAAIdAAgJWhcZEgAGAghoDAAABABTAGkMAAAFADkAawwAAAUATQBqDAAAAwBLAGwMAAACAEgAbQwAAAIAMwDqDAAABAA3AG4MAAABABUAHQAICVoXGRIABgIIaAwAAAQAUwBpDAAABQA5AGsMAAAFAE0AagwAAAMASwBsDAAAAgBIAG0MAAACADMA6gwAAAQANwBuDAAAAQAVAAAA.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB/wNQDxAANoDAAABABXAGkMAAADAE0A6gwAAAIASQAFAAMJGB/wNQDxAANoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy8AAgUACAmtJJEJAN8CAAUACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAICAAYJyQhCxwDkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAACAAYJyQhCxwDkAAZoDAAABwAdAGkMAAAGABYAawwAAAYACQBqDAAAAgAZAGwMAAABAB0A6gwAAAUAFAAAAA==.Raghnoll:BAABLgAECn8yAAMeAAkJchbnFABYAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAAEAAsAbwwAAAEANAAeAAkJchbnFABYAgloDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACQAuAG4MAAACAAsAbwwAAAEANAALAAEJ2RYCXwFCAAFuDAAAAgA6AAAA.',
Re='Renöwned:BAAALgAECgQJBAABLgAECgQJBQAMAAAAAA==.Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAIfAAQJ8wQPGgC4AARoDAAABQAWAGkMAAAEAAgAawwAAAEAAwDqDAAAAgAQAB8ABAnzBA8aALgABGgMAAAFABYAaQwAAAQACABrDAAAAQADAOoMAAACABAALgAECn8yAAIfAAkJgBAXEwCsAQAfAAkJgBAXEwCsAQAAAA==.',
Ry='Ryuuko:BAAALgAECgEJAQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAABLgAECn8YAAMUAAcJdxUGGACKAQdoDAAABAAkAGkMAAAEAEAAawwAAAUAQABqDAAABAAlAGwMAAADAEoAbQwAAAEAFgDqDAAAAwBCABQABwl3FQYYAIoBB2gMAAACACQAaQwAAAIAQABrDAAAAwBAAGoMAAADACUAbAwAAAMASgBtDAAAAQAWAOoMAAABAEIAEQAFCTsEOXUAgAAFaAwAAAIADABpDAAAAgASAGsMAAACAAQAagwAAAEACwDqDAAAAgAIAAEuAAUUAwkFAAsAPSUA.Sariar:BAAALgAECgEJAQABLgAFFAMJBQALAD0lAA==.Sartorius:BAABLgAECn8gAAIcAAkJNwl6LwBOAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABwAgAG4MAAACAA0AbwwAAAEADQAcAAkJNwl6LwBOAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABwAgAG4MAAACAA0AbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGwAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIYAAkJXANeowAsAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAYAAkJXANeowAsAQloDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABgAKAG4MAAADAAkAbwwAAAEACQAAAA==.Sciel:BAABLgAECn8fAAIEAAgJ3CGPFAB6AghoDAAAAwBaAGkMAAAGAF4AawwAAAUAUwBqDAAAAwBcAGwMAAAEAEgAbQwAAAMAUgDqDAAABQBWAG4MAAACAGAABAAICdwhjxQAegIIaAwAAAMAWgBpDAAABgBeAGsMAAAFAFMAagwAAAMAXABsDAAABABIAG0MAAADAFIA6gwAAAUAVgBuDAAAAgBgAAAA.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNwACAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwiYPAD8AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAHAAkJLwiYPAD8AAloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8YAAIJAAcJ2hMxdgBDAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAkABwnaEzF2AEMBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAABLgAECn8UAAMKAAgJHgx0JQAWAQhoDAAABQAtAGkMAAAGACsAawwAAAIAEwBqDAAAAgATAGwMAAABAAcAbQwAAAEACQDqDAAAAgBaAG8MAAABAAAACgAICR4MdCUAFgEIaAwAAAUALQBpDAAABQArAGsMAAACABMAagwAAAIAEwBsDAAAAQAHAG0MAAABAAkA6gwAAAIAWgBvDAAAAQAAAAIAAQlHA7QoASwAAWkMAAABAAgAAAA=.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJJQAfAKweAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAYAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8SAAIFAAQJ/RhwJwAsAQRoDAAABgBUAGkMAAAFAFAAawwAAAIAGgDqDAAABQBAAAUABAn9GHAnACwBBGgMAAAGAFQAaQwAAAUAUABrDAAAAgAaAOoMAAAFAEAALgAECn87AAIFAAkJBSUHAgCgAwAFAAkJBSUHAgCgAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLAAgAFwlAA==.Tip:BAAALgAECgUJCgAAAA==.',
To='Topaten:BAACLgAFFH8JAAIJAAQJKAfZQwALAQRoDAAAAwASAGkMAAADABIAawwAAAEACQDqDAAAAgAbAAkABAkoB9lDAAsBBGgMAAADABIAaQwAAAMAEgBrDAAAAQAJAOoMAAACABsALgAECn8aAAIJAAkJKBetIQBPAgAJAAkJKBetIQBPAgAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAILAAkJ7hMJPwD7AQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAALAAkJ7hMJPwD7AQloDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABgBdAG4MAAADAEUAbwwAAAEAGAAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgQJBQAMAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgQJBQAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMhAAcJKB1NFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfACEABwnSHE0VADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AAQAHCeUYjyAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
Vo='Vondramach:BAAALgAECgEJAQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAMAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAUJFAAeALoZAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAFFAQJCAARAP4YAA==.',
['Àl']='Àlilith:BAABLgAECn8eAAILAAkJ/BoQMgApAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACgBiAG4MAAABADQAbwwAAAEAUwALAAkJ/BoQMgApAgloDAAAAwBJAGkMAAAEAEwAawwAAAMAQQBqDAAAAwA9AGwMAAADAFEAbQwAAAIAFQDqDAAACgBiAG4MAAABADQAbwwAAAEAUwAAAA==.',
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
