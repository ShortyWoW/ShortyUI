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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Hunter-BeastMastery','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Paladin-Holy','Warrior-Protection','Rogue-Subtlety','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-10',data={Al='Alilith:BAAALgAECgEJAQAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAAALgAFFAEJAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8GAAIBAAIJsx5HcQCmAAJoDAAAAwBMAOoMAAADAFAAAQACCbMeR3EApgACaAwAAAMATADqDAAAAwBQAAAA.',
As='Asecretbear:BAACLgAFFH8JAAICAAMJ8wmrKQC1AANoDAAABAAwAGkMAAADAA8A6gwAAAIADAACAAMJ8wmrKQC1AANoDAAABAAwAGkMAAADAA8A6gwAAAIADAAuAAQKfycAAgIACAniG7oXAHkCAAIACAniG7oXAHkCAAAA.Ashvana:BAACLgAFFH8IAAIBAAMJ8x8/RwAKAQNoDAAAAwBcAGkMAAADAEcA6gwAAAIAUQABAAMJ8x8/RwAKAQNoDAAAAwBcAGkMAAADAEcA6gwAAAIAUQAuAAQKfy8AAgEACAmlJO0NAJ0CAAEACAmlJO0NAJ0CAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8aAAMDAAcJ+RKDBwCAAQdoDAAABQBOAGkMAAAFAEcAawwAAAQAKgBqDAAAAwA7AGwMAAACACcAbQwAAAEABADqDAAABgA2AAMABQmvE4MHAIABBWgMAAAFAE4AaQwAAAUARwBrDAAABAAqAG0MAAABAAQA6gwAAAYANgAEAAIJbQg8FwCfAAJqDAAAAwAJAGwMAAACACEALgAECn8iAAMDAAkJJyKZAwBpAwADAAkJJyKZAwBpAwAEAAEJ8gZ8qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8YAAIFAAcJpRVABAAKAgdoDAAABAApAGkMAAAEAEwAawwAAAQARgBqDAAAAwA3AGwMAAACAEYAbQwAAAEAFQDqDAAABgAzAAUABwmlFUAEAAoCB2gMAAAEACkAaQwAAAQATABrDAAABABGAGoMAAADADcAbAwAAAIARgBtDAAAAQAVAOoMAAAGADMALgAECn8hAAMFAAkJgiDwAwAyAwAFAAkJgiDwAwAyAwAGAAYJ9htnHAD4AQABLgAECggJFgAHAE4iAA==.',
Be='Berserkr:BAAALgAECgIJBAAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradrian:BAABLgAFFH8JAAIIAAMJTQ8BFQC7AANoDAAABAArAGkMAAADADoA6gwAAAIADwAIAAMJTQ8BFQC7AANoDAAABAArAGkMAAADADoA6gwAAAIADwAAAA==.',
Ch='Chainéd:BAAALgAECgUJCAABLgAECggJHwAJAJwjAA==.Choco:BAABLgAECn8WAAIDAAgJxhv8CwAmAghoDAAAAgA7AGkMAAACAE0AawwAAAIAOgBqDAAAAwBCAGwMAAADAEsAbQwAAAMATgDqDAAAAwBOAG4MAAAEAEUAAwAICcYb/AsAJgIIaAwAAAIAOwBpDAAAAgBNAGsMAAACADoAagwAAAMAQgBsDAAAAwBLAG0MAAADAE4A6gwAAAMATgBuDAAABABFAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAFFAQJCwAKAJ8ZAA==.Crazy:BAAALgAECgQJBQAAAA==.Creme:BAABLgAECn8jAAIDAAgJrxvxDwDvAQhoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYAAwAICa8b8Q8A7wEIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAABLgAECn8sAAILAAkJ8RllBQBqAgloDAAABwBUAGkMAAAGAFcAawwAAAYASQBqDAAABQBSAGwMAAAFAEIAbQwAAAQAKwDqDAAABgBRAG4MAAAEAEYAbwwAAAEAFwALAAkJ8RllBQBqAgloDAAABwBUAGkMAAAGAFcAawwAAAYASQBqDAAABQBSAGwMAAAFAEIAbQwAAAQAKwDqDAAABgBRAG4MAAAEAEYAbwwAAAEAFwAAAA==.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgEJAQAAAA==.',
De='Deadlyfire:BAABLgAECn8VAAQMAAYJ/wKGFQC7AAZoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQA6gwAAAMACAAMAAYJlQKGFQC7AAZoDAAAAwAJAGkMAAADAAgAawwAAAMABQBqDAAAAQAIAGwMAAABAAQA6gwAAAIABAADAAUJ8QJ/SwCGAAVoDAAAAQAIAGkMAAABAAUAawwAAAEABwBqDAAAAQAIAOoMAAABAAgABAACCXwD6Y8AWQACagwAAAEACQBsDAAAAgAIAAAA.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgYJBwAAAA==.Deralan:BAABLgAECn8ZAAMHAAgJ/QZTJQAqAQhoDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAADAAwAbQwAAAMAFgDqDAAABAALAG4MAAACAAcABwAICf0GUyUAKgEIaAwAAAQAIABpDAAAAwAbAGsMAAAEAAsAagwAAAEACABsDAAAAgAMAG0MAAADABYA6gwAAAQACwBuDAAAAgAHAA0AAglwA/caACgAAmoMAAABAAcAbAwAAAEACAAAAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIOAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAOAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAAALgAECgYJEAAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAAALgAFFAIJAgAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAAALgAFFAEJAQAAAA==.Faenghorn:BAAALgAECgUJCgABLgAFFAEJAQAPAAAAAA==.Fanah:BAAALgADCggJDgAAAA==.',
Fe='Fearmonger:BAAALgADCgYJBgAAAA==.Felora:BAAALgAECgEJAQAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Freshguac:BAAALgADCgEJAQAAAA==.Frozswarrior:BAAALgAECgYJBgAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8XAAIQAAYJWwpwiwDiAAZoDAAABQAQAGkMAAAFAB4AawwAAAUAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAQAAYJWwpwiwDiAAZoDAAABQAQAGkMAAAFAB4AawwAAAUAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAQJBwAHAA0JAA==.Gloomybear:BAAALgADCgEJAgAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAMJCQAIAE0PAA==.Grindëlwald:BAABLgAECn8eAAIRAAgJURbGCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAEQAICVEWxgsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUAwkJAAgATQ8A.',
Gu='Guac:BAAALgAECgQJDAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgADCggJDgAPAAAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8aAAMHAAcJ9hx/AwAhAgdoDAAABQBaAGkMAAAFAFoAawwAAAQAVgBqDAAAAwBZAGwMAAACAFAAbQwAAAEABgDqDAAABgBaAAcABwmTHH8DACECB2gMAAAEAFoAaQwAAAQAVABrDAAABABWAGoMAAADAFkAbAwAAAIAUABtDAAAAQAGAOoMAAAGAFoADQACCaYZAwYAsQACaAwAAAEAKABpDAAAAQBaAC4ABAp/IQADBwAJCWwjgwEArgMABwAJCUojgwEArgMADQAHCaAl2wUAmwIAAAA=.Ishmonk:BAABLgAECn8hAAMGAAgJ5CELCgDXAghoDAAABQBhAGkMAAAFAGAAawwAAAUAYQBqDAAABABcAGwMAAAEAFcAbQwAAAIAVADqDAAABQBhAG4MAAADAC8ABgAHCXokCwoA1wIHaAwAAAMAYQBpDAAAAwBgAGsMAAADAGEAagwAAAMAXABsDAAAAgBXAG0MAAABAFQA6gwAAAQAYQASAAgJPBxNDwCkAghoDAAAAgBTAGkMAAACAFYAawwAAAIAVQBqDAAAAQBQAGwMAAACAEAAbQwAAAEANQDqDAAAAQBVAG4MAAADAC8AAS4ABRQHCRoABwD2HAA=.Ishootudead:BAAALgAECggJCAABLgAFFAcJGgAHAPYcAA==.',
Jc='Jcole:BAAALgAECgYJCAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAEJAQAPAAAAAA==.Jon:BAABLgAECn8qAAITAAkJoB4aDwCsAgloDAAABwBUAGkMAAAFAE8AawwAAAUAVABqDAAABQBMAGwMAAAFAFQAbQwAAAQARQDqDAAABgBaAG4MAAAEAEsAbwwAAAEAOgATAAkJoB4aDwCsAgloDAAABwBUAGkMAAAFAE8AawwAAAUAVABqDAAABQBMAGwMAAAFAFQAbQwAAAQARQDqDAAABgBaAG4MAAAEAEsAbwwAAAEAOgAAAA==.',
Ka='Kaivasyr:BAAALgAECgYJEwAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgUJDAAAAA==.',
Ke='Kealee:BAAALgAECgUJCwAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8GAAITAAQJJwV6QgAUAQRoDAAAAQACAGkMAAACAA8AawwAAAEAEgDqDAAAAgAQABMABAknBXpCABQBBGgMAAABAAIAaQwAAAIADwBrDAAAAQASAOoMAAACABAALgAECn8dAAMTAAgJhBPhjQC3AQATAAgJfBPhjQC3AQAUAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMKAAYJNAXLmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAKAAYJNAXLmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAVAAEJSwGvfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8dAAIKAAgJwRe8IQDIAQhoDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABABNAGwMAAAEAEEAbQwAAAMAJQDqDAAABAAyAG4MAAACADYACgAICcEXvCEAyAEIaAwAAAQARwBpDAAABABKAGsMAAAEAEcAagwAAAQATQBsDAAABABBAG0MAAADACUA6gwAAAQAMgBuDAAAAgA2AAAA.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAPAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAPAAAAAA==.Littletop:BAABLgAECn8UAAIWAAgJ2gdPCwAoAQhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AFgAICdoHTwsAKAEIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8gAAIQAAgJCA23SQBzAQhoDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABQAYAG4MAAACABkAEAAICQgNt0kAcwEIaAwAAAYAHwBpDAAABQA7AGsMAAAFACEAagwAAAQAJgBsDAAABAAgAG0MAAABABkA6gwAAAUAGABuDAAAAgAZAAAA.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8nAAIBAAgJlwpjUQBUAQhoDAAABgAXAGkMAAAGACUAawwAAAYAHABqDAAABQAWAGwMAAAEAB4AbQwAAAQADADqDAAABQAqAG4MAAADAA8AAQAICZcKY1EAVAEIaAwAAAYAFwBpDAAABgAlAGsMAAAGABwAagwAAAUAFgBsDAAABAAeAG0MAAAEAAwA6gwAAAUAKgBuDAAAAwAPAAAA.Malex:BAABLgAECn8WAAIHAAgJTiKKBQCZAghoDAAAAwBVAGkMAAADAFoAawwAAAMAXABqDAAAAwBhAGwMAAADAGEAbQwAAAIAWwDqDAAAAwBSAG4MAAACAEoABwAICU4iigUAmQIIaAwAAAMAVQBpDAAAAwBaAGsMAAADAFwAagwAAAMAYQBsDAAAAwBhAG0MAAACAFsA6gwAAAMAUgBuDAAAAgBKAAAA.Malrien:BAACLgAFFH8GAAMEAAMJ8Bm1IQDkAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAEAAMJ8Bm1IQDkAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAADAAEJQgyCLgBIAAFpDAAAAQAfAC4ABAp/GwADAwAICWMcZxgAUgIAAwAHCZsdZxgAUgIABAAHCeERYUIAdwEAAS4ABAoICRYABwBOIgA=.Marselli:BAAALgAECggJDwAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn8rAAIXAAgJYQuAHABeAQhoDAAABwA0AGkMAAAGABUAawwAAAYAIQBqDAAABQATAGwMAAAFABgAbQwAAAQAEQDqDAAABgArAG4MAAAEAAsAFwAICWELgBwAXgEIaAwAAAcANABpDAAABgAVAGsMAAAGACEAagwAAAUAEwBsDAAABQAYAG0MAAAEABEA6gwAAAYAKwBuDAAABAALAAAA.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8VAAIQAAYJ+x3dXADMAQZoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAACAEIA6gwAAAQATwAQAAYJ+x3dXADMAQZoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAACAEIA6gwAAAQATwAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECgUJBgAAAA==.',
Om='Omgimaburger:BAABLgAECn8UAAMCAAYJsRw9IgDAAQZoDAAABAA7AGkMAAAEAFoAawwAAAQATABqDAAAAwBIAGwMAAABAFIA6gwAAAQAOgACAAYJsRw9IgDAAQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAQAOgAXAAQJmQruPwCRAARoDAAAAQAeAGkMAAABABEAawwAAAEAIgBqDAAAAQAbAAAA.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAITAAkJbB3QCwDKAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwATAAkJbB3QCwDKAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8fAAMJAAgJnCOXBgAkAwhoDAAABgBcAGkMAAAHAGEAawwAAAUAXwBqDAAAAgBdAGwMAAACAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACQAICecilwYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAAsABgm1GzEUAIIBBmgMAAADADEAaQwAAAMASwBrDAAAAgBYAGwMAAABACQA6gwAAAIATQBuDAAAAgBhAAAA.',
Ph='Phatt:BAAALgAECgYJDAAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIEAAMJGB/rGwAGAQNoDAAABABXAGkMAAADAE0A6gwAAAIASQAEAAMJGB/rGwAGAQNoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfyoAAgQACAmuJJEJAN8CAAQACAmuJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAAALgAECgQJEAAAAA==.Raghnoll:BAABLgAECn8oAAIYAAgJ8BQoEgAQAghoDAAABwA5AGkMAAAGAD8AawwAAAUATwBqDAAABQBPAGwMAAAFADkAbQwAAAMAJADqDAAABwArAG4MAAACAAsAGAAICfAUKBIAEAIIaAwAAAcAOQBpDAAABgA/AGsMAAAFAE8AagwAAAUATwBsDAAABQA5AG0MAAADACQA6gwAAAcAKwBuDAAAAgALAAAA.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAABLgAECn8kAAIZAAkJAQ3qEABbAQloDAAABgBFAGkMAAAFAC8AawwAAAUAKABqDAAABAAYAGwMAAAEABQAbQwAAAMAGgDqDAAABQAhAG4MAAADABcAbwwAAAEABAAZAAkJAQ3qEABbAQloDAAABgBFAGkMAAAFAC8AawwAAAUAKABqDAAABAAYAGwMAAAEABQAbQwAAAMAGgDqDAAABQAhAG4MAAADABcAbwwAAAEABAAAAA==.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgUJCAABLgAFFAIJAgAPAAAAAA==.Sartorius:BAAALgAECgYJDgAAAA==.Satiate:BAAALgADCgYJGQAAAA==.',
Sc='Scarthan:BAABLgAECn8gAAITAAgJCAPHhwAKAQhoDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABQAFAG4MAAABAAkAEwAICQgDx4cACgEIaAwAAAUABQBpDAAABQAMAGsMAAAFAAUAagwAAAUAEQBsDAAABAAKAG0MAAACAAQA6gwAAAUABQBuDAAAAQAJAAAA.Sciel:BAABLgAECn8YAAIDAAcJMCGMFAB6AgdoDAAAAwBaAGkMAAAFAF4AawwAAAQAUwBqDAAAAgBcAGwMAAADAEgAbQwAAAIAUQDqDAAABQBWAAMABwkwIYwUAHoCB2gMAAADAFoAaQwAAAUAXgBrDAAABABTAGoMAAACAFwAbAwAAAMASABtDAAAAgBRAOoMAAAFAFYAAAA=.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgMJBAAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNAABAHYlAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIGAAkJLwjxIQAiAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAGAAkJLwjxIQAiAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgUJBwAAAA==.',
So='Sojaslim:BAAALgAECgkJEgAAAA==.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECgcJCgAAAA==.',
Ta='Tagmamon:BAAALgAFFAEJAQABLgAFFAcJGQAZAKEeAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgATAGwdAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8JAAIEAAMJuBzVHQD8AANoDAAABABUAGkMAAADAFAA6gwAAAIANwAEAAMJuBzVHQD8AANoDAAABABUAGkMAAADAFAA6gwAAAIANwAuAAQKfy8AAgQACQk3IxABAIsDAAQACQk3IxABAIsDAAAA.',
Ti='Tibbsrog:BAAALgADCgUJBQAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJHAAaAGIjAA==.',
To='Topaten:BAAALgAECggJDQAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8WAAIQAAgJ8Qr0cACaAQhoDAAABAAvAGkMAAAEADsAawwAAAQAHgBqDAAAAwAgAGwMAAACAA8AbQwAAAEADgDqDAAAAwATAG4MAAABAAgAEAAICfEK9HAAmgEIaAwAAAQALwBpDAAABAA7AGsMAAAEAB4AagwAAAMAIABsDAAAAgAPAG0MAAABAA4A6gwAAAMAEwBuDAAAAQAIAAAA.',
Va='Vaipara:BAAALgAECgMJBAAAAA==.Varissa:BAAALgAECgkJDgAAAA==.',
Vi='Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMbAAcJKB1MFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfABsABwnSHEwVADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AHAAHCeYYjSAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAPAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.',
['Àl']='Àlilith:BAAALgAECgcJEgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
