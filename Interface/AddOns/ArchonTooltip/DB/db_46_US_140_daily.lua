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

local lookup = {'Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Unknown-Unknown','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Rogue-Subtlety','Paladin-Holy','Warrior-Protection','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-20',data={Al='Alilith:BAAALgAECgEJAgAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8IAAIBAAcJrAMpDQDKAQdoDAAAAQAQAGkMAAABAAQAawwAAAEABABqDAAAAQAGAGwMAAABAAMA6gwAAAIAGwBuDAAAAQACAAEABwmsAykNAMoBB2gMAAABABAAaQwAAAEABABrDAAAAQAEAGoMAAABAAYAbAwAAAEAAwDqDAAAAgAbAG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAICAAIJsx7FkQCkAAJoDAAABABMAOoMAAAEAFAAAgACCbMexZEApAACaAwAAAQATADqDAAABABQAAAA.',
As='Asecretbear:BAACLgAFFH8NAAIDAAMJvAwhMgC/AANoDAAABQAwAGkMAAAEACEA6gwAAAQADwADAAMJvAwhMgC/AANoDAAABQAwAGkMAAAEACEA6gwAAAQADwAuAAQKfzAAAgMACQnDGrsXAHkCAAMACQnDGrsXAHkCAAAA.Ashvana:BAACLgAFFH8MAAICAAMJ8x8wYAABAQNoDAAAAwBcAGkMAAAFAEcA6gwAAAQAUQACAAMJ8x8wYAABAQNoDAAAAwBcAGkMAAAFAEcA6gwAAAQAUQAuAAQKfzYAAgIACQmfJDAMAOQCAAIACQmfJDAMAOQCAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8hAAMEAAgJ1RMfCQChAQhoDAAABgBOAGkMAAAGAF0AawwAAAUAMQBqDAAABAAjAGwMAAADACcAbQwAAAEABADqDAAABwA8AG4MAAABAB4ABAAGCVQWHwkAoQEGaAwAAAYATgBpDAAABgBdAGsMAAAFADEAagwAAAEAIwBtDAAAAQAEAOoMAAAHADwABQADCf8HGTIA0wADagwAAAMACQBsDAAAAwAwAG4MAAABAAMALgAECn8oAAMEAAkJRCKZAwBpAwAEAAkJRCKZAwBpAwAFAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8fAAIGAAgJKxlWAgCcAghoDAAABQApAGkMAAAFAE4AawwAAAUARgBqDAAABABYAGwMAAADAFAAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABgAICSsZVgIAnAIIaAwAAAUAKQBpDAAABQBOAGsMAAAFAEYAagwAAAQAWABsDAAAAwBQAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBgAJCYIg8AMAMgMABgAJCYIg8AMAMgMABwAGCfYbahwA+AEAAS4ABAoJCR8ACAAEIgA=.',
Be='Berserkr:BAAALgAECgUJCwAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAMJDwAJAEMbAA==.',
Ca='Calan:BAAALgADCgMJAwABLgAFFAMJBQAKAD0lAA==.',
Ch='Chainéd:BAAALgAECgUJCwABLgAECggJJAALAJ8jAA==.Choco:BAACLgAFFH8GAAIEAAMJDBWfIADmAANoDAAAAwAhAGkMAAABAEsA6gwAAAIANAAEAAMJDBWfIADmAANoDAAAAwAhAGkMAAABAEsA6gwAAAIANAAuAAQKfxcAAgQACAklHXUTABYCAAQACAklHXUTABYCAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAFFAUJDQAMABIaAA==.Crazy:BAAALgAECgYJDAAAAA==.Creme:BAABLgAECn8jAAIEAAgJrxvHFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYABAAICa8bxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8IAAINAAMJmBJFFQD2AANoDAAABABOAGkMAAADADQA6gwAAAEACwANAAMJmBJFFQD2AANoDAAABABOAGkMAAADADQA6gwAAAEACwAuAAQKfzUAAg0ACQnYG5YGAJUCAA0ACQnYG5YGAJUCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgEJAQAAAA==.',
De='Deadlyfire:BAABLgAECn8VAAQOAAYJ/wKjHgCkAAZoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQA6gwAAAMACAAOAAYJlQKjHgCkAAZoDAAAAwAJAGkMAAADAAgAawwAAAMABQBqDAAAAQAIAGwMAAABAAQA6gwAAAIABAAEAAUJ8QKhZAB0AAVoDAAAAQAIAGkMAAABAAUAawwAAAEABwBqDAAAAQAIAOoMAAABAAgABQACCXwD6Y8AWQACagwAAAEACQBsDAAAAgAIAAAA.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgYJCwAAAA==.Deralan:BAABLgAECn8dAAMIAAgJ/QZANwAdAQhoDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAEAAwAbQwAAAQAFgDqDAAABQALAG4MAAADAAcACAAICf0GQDcAHQEIaAwAAAQAIABpDAAAAwAbAGsMAAAEAAsAagwAAAEACABsDAAAAwAMAG0MAAAEABYA6gwAAAUACwBuDAAAAwAHAA8AAglwA2oiACUAAmoMAAABAAcAbAwAAAEACAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAALAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIQAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAQAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAAALgAECgYJEAAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCAAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8HAAIIAAMJbAYKNQC0AANoDAAAAwAZAGkMAAADABMA6gwAAAEAAwAIAAMJbAYKNQC0AANoDAAAAwAZAGkMAAADABMA6gwAAAEAAwAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8FAAIRAAQJnCBrAwCDAQRoDAAAAQBcAGkMAAABAFMAawwAAAEATgDqDAAAAgBPABEABAmcIGsDAIMBBGgMAAABAFwAaQwAAAEAUwBrDAAAAQBOAOoMAAACAE8ALgAECn8hAAMRAAgJ0CRbAgDoAgARAAgJ0CRbAgDoAgASAAMJHhZCHwDEAAAAAA==.Faengbrew:BAAALgAECgcJDgABLgAFFAQJBQARAJwgAA==.Faenghorn:BAAALgAECgUJCgABLgAFFAQJBQARAJwgAA==.Fanah:BAAALgADCggJDgABLgAECgYJJAABAKUeAA==.',
Fe='Fearmonger:BAAALgAECgEJAQAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Freshguac:BAAALgADCgEJAQAAAA==.Frozswarrior:BAAALgAECggJDgAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8aAAIKAAYJWwrLrwAkAQZoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAKAAYJWwrLrwAkAQZoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAMJAwATAAAAAA==.Gladerbug:BAAALgAECggJCAAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAMJDwAJAEMbAA==.Grindêlwald:BAACLgAFFH8PAAIJAAMJQxvxFQDsAANoDAAABgA5AGkMAAAFAFEA6gwAAAQARQAJAAMJQxvxFQDsAANoDAAABgA5AGkMAAAFAFEA6gwAAAQARQAuAAQKfx0AAgkACQlrG5MIAFgCAAkACQlrG5MIAFgCAAAA.Grindëlwald:BAABLgAECn8eAAIUAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFAAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUAwkPAAkAQxsA.',
Gu='Guac:BAAALgAECgQJDAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgYJJAABAKUeAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8eAAMIAAgJ2xraAwBoAghoDAAABQBaAGkMAAAFAFoAawwAAAQAVgBqDAAABABZAGwMAAADAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACAAICYca2gMAaAIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAQAWQBsDAAAAwBQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkAA8AAgmmGQQGALEAAmgMAAABACgAaQwAAAEAWgAuAAQKfycAAwgACQlsI4MBAK4DAAgACQlKI4MBAK4DAA8ABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMVAAkJwyAnCQB9AgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABwBhAG4MAAAEADsAbwwAAAEAMwAHAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABQBhABUACQm0HCcJAH0CCWgMAAAEAFQAaQwAAAQAXwBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkeAAgA2xoA.Ishootudead:BAAALgAECggJDwABLgAFFAgJHgAIANsaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJCAABAKwDAA==.Jon:BAACLgAFFH8IAAIWAAMJXBL7XAD4AANoDAAABAA/AGkMAAADACMA6gwAAAEAKQAWAAMJXBL7XAD4AANoDAAABAA/AGkMAAADACMA6gwAAAEAKQAuAAQKfzMAAhYACQmQH10RANACABYACQmQH10RANACAAAA.Josito:BAAALgADCggJDQABLgAFFAMJBQAKAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8dAAIWAAgJvBRWTQDMAQhoDAAABABNAGkMAAAFAD8AawwAAAUAMgBqDAAABQBCAGwMAAADADUAbQwAAAIAKwDqDAAABAA9AG4MAAABABYAFgAICbwUVk0AzAEIaAwAAAQATQBpDAAABQA/AGsMAAAFADIAagwAAAUAQgBsDAAAAwA1AG0MAAACACsA6gwAAAQAPQBuDAAAAQAWAAAA.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgYJEgAAAA==.',
Ke='Kealee:BAAALgAECgYJEQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIWAAQJBQYqUgAZAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABYABAkFBipSABkBBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMWAAgJ4BQKawB+AQAWAAgJ2BQKawB+AQAXAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMMAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAMAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAYAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8gAAIMAAgJwReJOQC2AQhoDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABQBNAGwMAAAFAEEAbQwAAAQAJQDqDAAABAAyAG4MAAACADYADAAICcEXiTkAtgEIaAwAAAQARwBpDAAABABKAGsMAAAEAEcAagwAAAUATQBsDAAABQBBAG0MAAAEACUA6gwAAAQAMgBuDAAAAgA2AAAA.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAATAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAATAAAAAA==.Littletop:BAABLgAECn8UAAIZAAgJ2gdVEAAHAQhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGQAICdoHVRAABwEIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8jAAIKAAkJZA+tRgDJAQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABgAYAG4MAAADABkAbwwAAAEAUQAKAAkJZA+tRgDJAQloDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABgAYAG4MAAADABkAbwwAAAEAUQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8wAAICAAkJ5AmQXgCDAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAABgAqAG4MAAAEAA8AbwwAAAEADAACAAkJ5AmQXgCDAQloDAAABwAXAGkMAAAHACUAawwAAAcAHABqDAAABgAWAGwMAAAFAB4AbQwAAAUADADqDAAABgAqAG4MAAAEAA8AbwwAAAEADAAAAA==.Malex:BAABLgAECn8fAAIIAAkJBCLlBAD1AgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAIAAkJBCLlBAD1AgloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8Bk7LwDgAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAFAAMJ8Bk7LwDgAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAEAAEJQgxOPgA/AAFpDAAAAQAfAC4ABAp/GwADBAAICWMcahgAUQIABAAHCZsdahgAUQIABQAHCeERY0IAdwEAAS4ABAoJCR8ACAAEIgA=.Malrii:BAAALgAECggJCAABLgAECgkJHwAIAAQiAA==.Marselli:BAAALgAECggJEgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn80AAIaAAkJLg7vGwCwAQloDAAACAA0AGkMAAAHAB8AawwAAAcAKABqDAAABgApAGwMAAAGAB0AbQwAAAUAEQDqDAAABwA/AG4MAAAFACQAbwwAAAEAEgAaAAkJLg7vGwCwAQloDAAACAA0AGkMAAAHAB8AawwAAAcAKABqDAAABgApAGwMAAAGAB0AbQwAAAUAEQDqDAAABwA/AG4MAAAFACQAbwwAAAEAEgAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAIKAAgJ1RzaXADMAQhoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIAbQwAAAEASgDqDAAABABPAG4MAAABADoACgAICdUc2lwAzAEIaAwAAAQAUQBpDAAABQBUAGsMAAAFAEgAagwAAAEAUwBsDAAAAwBCAG0MAAABAEoA6gwAAAQATwBuDAAAAQA6AAAA.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRyyLgC7AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgADAAYJsRyyLgC7AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAaAAUJ/A7VQgDFAAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIWAAkJbB1qGgCXAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAWAAkJbB1qGgCXAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMLAAgJnyOWBgAkAwhoDAAABwBcAGkMAAAIAGEAawwAAAYAXwBqDAAAAwBfAGwMAAADAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACwAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAA0ABwkaI7EPAA8CB2gMAAAEAFIAaQwAAAQAXABrDAAAAwBfAGoMAAABAF8AbAwAAAIAXADqDAAAAgBNAG4MAAACAGEAAAA=.',
Ph='Phatt:BAABLgAECn8WAAIbAAgJRxVhEQDwAQhoDAAAAwBHAGkMAAAEADkAawwAAAQAOgBqDAAAAwBLAGwMAAACAEgAbQwAAAIAMwDqDAAAAwAwAG4MAAABABUAGwAICUcVYREA8AEIaAwAAAMARwBpDAAABAA5AGsMAAAEADoAagwAAAMASwBsDAAAAgBIAG0MAAACADMA6gwAAAMAMABuDAAAAQAVAAAA.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB8zKAD/AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAFAAMJGB8zKAD/AANoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy4AAgUACAmuJJEJAN8CAAUACAmuJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8WAAICAAYJvAg5rADrAAZoDAAABgAdAGkMAAAFABYAawwAAAUACQBqDAAAAQAZAGwMAAABAB0A6gwAAAQAFAACAAYJvAg5rADrAAZoDAAABgAdAGkMAAAFABYAawwAAAUACQBqDAAAAQAZAGwMAAABAB0A6gwAAAQAFAAAAA==.Raghnoll:BAABLgAECn8vAAMcAAgJrhbCFgAfAghoDAAACAA5AGkMAAAHAGAAawwAAAYATwBqDAAABgBPAGwMAAAGADkAbQwAAAMAJADqDAAACAAuAG4MAAADAAsAHAAICa4WwhYAHwIIaAwAAAgAOQBpDAAABwBgAGsMAAAGAE8AagwAAAYATwBsDAAABgA5AG0MAAADACQA6gwAAAgALgBuDAAAAgALAAoAAQlKCY9XATAAAW4MAAABABcAAAA=.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8IAAIdAAMJsQUWGACbAANoDAAABAAWAGkMAAADAAUA6gwAAAEAEAAdAAMJsQUWGACbAANoDAAABAAWAGkMAAADAAUA6gwAAAEAEAAuAAQKfy0AAh0ACQlWDl8SAJIBAB0ACQlWDl8SAJIBAAAA.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgYJDwABLgAFFAMJBQAKAD0lAA==.Sartorius:BAABLgAECn8fAAIaAAkJEAnAJwBWAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAaAAkJEAnAJwBWAQloDAAABAAZAGkMAAAEACAAawwAAAQAFQBqDAAABAAYAGwMAAAEACEAbQwAAAIAEADqDAAABgAdAG4MAAACAA0AbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGQAAAA==.',
Sc='Scarthan:BAABLgAECn8hAAIWAAgJCAM4sAD8AAhoDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABQAFAG4MAAACAAkAFgAICQgDOLAA/AAIaAwAAAUABQBpDAAABQAMAGsMAAAFAAUAagwAAAUAEQBsDAAABAAKAG0MAAACAAQA6gwAAAUABQBuDAAAAgAJAAAA.Sciel:BAABLgAECn8eAAIEAAgJrh+PFAB6AghoDAAAAwBaAGkMAAAGAF4AawwAAAUAUwBqDAAAAwBcAGwMAAAEAEgAbQwAAAMAUQDqDAAABQBWAG4MAAABADkABAAICa4fjxQAegIIaAwAAAMAWgBpDAAABgBeAGsMAAAFAFMAagwAAAMAXABsDAAABABIAG0MAAADAFEA6gwAAAUAVgBuDAAAAQA5AAAA.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNgACAHYlAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwh/MgAKAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAHAAkJLwh/MgAKAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8YAAILAAcJ2hPBYABKAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAsABwnaE8FgAEoBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJIQAdAIYeAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAWAGwdAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8OAAIFAAQJIRj2GwA4AQRoDAAABQBUAGkMAAAEAFAAawwAAAEAGgDqDAAABAA3AAUABAkhGPYbADgBBGgMAAAFAFQAaQwAAAQAUABrDAAAAQAaAOoMAAAEADcALgAECn87AAIFAAkJBSUfAQCpAwAFAAkJBSUfAQCpAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJIwAeABckAA==.',
To='Topaten:BAACLgAFFH8FAAILAAMJFwa4RADTAANoDAAAAgAIAGkMAAACAAoA6gwAAAEAGwALAAMJFwa4RADTAANoDAAAAgAIAGkMAAACAAoA6gwAAAEAGwAuAAQKfxYAAgsACQnxFDMgAC8CAAsACQnxFDMgAC8CAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8eAAIKAAgJBhBGYwCAAQhoDAAABQAvAGkMAAAFADsAawwAAAUAKQBqDAAABAAgAGwMAAADADQAbQwAAAIAEwDqDAAABAAeAG4MAAACACMACgAICQYQRmMAgAEIaAwAAAUALwBpDAAABQA7AGsMAAAFACkAagwAAAQAIABsDAAAAwA0AG0MAAACABMA6gwAAAQAHgBuDAAAAgAjAAAA.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgQJBAATAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgQJBAAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMfAAcJKB1NFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfAB8ABwnSHE0VADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AAQAHCeYYjyAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgATAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAECgkJBgATAAAAAA==.',
['Àl']='Àlilith:BAABLgAECn8UAAIKAAcJ1BYxVADlAQdoDAAAAgA2AGkMAAADAEkAawwAAAIAQQBqDAAAAgA9AGwMAAACAFEAbQwAAAEAEgDqDAAACAA4AAoABwnUFjFUAOUBB2gMAAACADYAaQwAAAMASQBrDAAAAgBBAGoMAAACAD0AbAwAAAIAUQBtDAAAAQASAOoMAAAIADgAAAA=.',
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
