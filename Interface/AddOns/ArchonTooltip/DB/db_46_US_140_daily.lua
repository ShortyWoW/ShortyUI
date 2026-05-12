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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Hunter-BeastMastery','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Unknown-Unknown','Priest-Discipline','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Paladin-Holy','Warrior-Protection','Rogue-Subtlety','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-11',data={Al='Alilith:BAAALgAECgEJAQAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAAALgAFFAEJAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8GAAIBAAIJsx6WdACmAAJoDAAAAwBMAOoMAAADAFAAAQACCbMelnQApgACaAwAAAMATADqDAAAAwBQAAAA.',
As='Asecretbear:BAACLgAFFH8JAAICAAMJ8wnRKgC1AANoDAAABAAwAGkMAAADAA8A6gwAAAIADAACAAMJ8wnRKgC1AANoDAAABAAwAGkMAAADAA8A6gwAAAIADAAuAAQKfyoAAgIACAniG7oXAHkCAAIACAniG7oXAHkCAAAA.Ashvana:BAACLgAFFH8IAAIBAAMJ8x/oSQAJAQNoDAAAAwBcAGkMAAADAEcA6gwAAAIAUQABAAMJ8x/oSQAJAQNoDAAAAwBcAGkMAAADAEcA6gwAAAIAUQAuAAQKfy8AAgEACAmlJKgOAJ0CAAEACAmlJKgOAJ0CAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8aAAMDAAcJ+RIRCAB/AQdoDAAABQBOAGkMAAAFAEcAawwAAAQAKgBqDAAAAwA7AGwMAAACACcAbQwAAAEABADqDAAABgA2AAMABQmvExEIAH8BBWgMAAAFAE4AaQwAAAUARwBrDAAABAAqAG0MAAABAAQA6gwAAAYANgAEAAIJbQg8FwCfAAJqDAAAAwAJAGwMAAACACEALgAECn8iAAMDAAkJJyKZAwBpAwADAAkJJyKZAwBpAwAEAAEJ8gZ8qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8YAAIFAAcJpRVnAgDxAQdoDAAABAApAGkMAAAEAEwAawwAAAQARgBqDAAAAwA3AGwMAAACAEYAbQwAAAEAFQDqDAAABgAzAAUABwmlFWcCAPEBB2gMAAAEACkAaQwAAAQATABrDAAABABGAGoMAAADADcAbAwAAAIARgBtDAAAAQAVAOoMAAAGADMALgAECn8hAAMFAAkJgiDwAwAyAwAFAAkJgiDwAwAyAwAGAAYJ9htmHAD4AQABLgAECgkJHwAHAAMiAA==.',
Be='Berserkr:BAAALgAECgIJBAAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradrian:BAACLgAFFH8JAAIIAAMJTQ+wFQC7AANoDAAABAArAGkMAAADADoA6gwAAAIADwAIAAMJTQ+wFQC7AANoDAAABAArAGkMAAADADoA6gwAAAIADwAuAAQKfxYAAggACAm7HNEGAD4CAAgACAm6HNEGAD4CAAAA.',
Ch='Chainéd:BAAALgAECgUJCwABLgAECggJHwAJAJwjAA==.Choco:BAABLgAECn8WAAIDAAgJxhtZDAAmAghoDAAAAgA7AGkMAAACAE0AawwAAAIAOgBqDAAAAwBCAGwMAAADAEsAbQwAAAMATgDqDAAAAwBOAG4MAAAEAEUAAwAICcYbWQwAJgIIaAwAAAIAOwBpDAAAAgBNAGsMAAACADoAagwAAAMAQgBsDAAAAwBLAG0MAAADAE4A6gwAAAMATgBuDAAABABFAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAFFAUJDAAKAJ8ZAA==.Crazy:BAAALgAECgQJBQAAAA==.Creme:BAABLgAECn8jAAIDAAgJrxtiEADwAQhoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYAAwAICa8bYhAA8AEIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAABLgAECn8sAAILAAkJ8RmvBQBqAgloDAAABwBUAGkMAAAGAFcAawwAAAYASQBqDAAABQBSAGwMAAAFAEIAbQwAAAQAKwDqDAAABgBRAG4MAAAEAEYAbwwAAAEAFwALAAkJ8RmvBQBqAgloDAAABwBUAGkMAAAGAFcAawwAAAYASQBqDAAABQBSAGwMAAAFAEIAbQwAAAQAKwDqDAAABgBRAG4MAAAEAEYAbwwAAAEAFwAAAA==.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgEJAQAAAA==.',
De='Deadlyfire:BAABLgAECn8VAAQMAAYJ/wIcFgC7AAZoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQA6gwAAAMACAAMAAYJlQIcFgC7AAZoDAAAAwAJAGkMAAADAAgAawwAAAMABQBqDAAAAQAIAGwMAAABAAQA6gwAAAIABAADAAUJ8QIgTQCGAAVoDAAAAQAIAGkMAAABAAUAawwAAAEABwBqDAAAAQAIAOoMAAABAAgABAACCXwD6Y8AWQACagwAAAEACQBsDAAAAgAIAAAA.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgYJBwAAAA==.Deralan:BAABLgAECn8ZAAMHAAgJ/QYxJgAqAQhoDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAADAAwAbQwAAAMAFgDqDAAABAALAG4MAAACAAcABwAICf0GMSYAKgEIaAwAAAQAIABpDAAAAwAbAGsMAAAEAAsAagwAAAEACABsDAAAAgAMAG0MAAADABYA6gwAAAQACwBuDAAAAgAHAA0AAglwA4cbACgAAmoMAAABAAcAbAwAAAEACAAAAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIOAAkJVRyFDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAOAAkJVRyFDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAAALgAECgYJEAAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAAALgAFFAIJAgAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAAALgAFFAEJAQAAAA==.Faenghorn:BAAALgAECgUJCgABLgAFFAEJAQAPAAAAAA==.Fanah:BAAALgADCggJDgABLgAECgYJHgAQAAEeAA==.',
Fe='Fearmonger:BAAALgADCgYJBgAAAA==.Felora:BAAALgAECgEJAQAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Freshguac:BAAALgADCgEJAQAAAA==.Frozswarrior:BAAALgAECgYJBgAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8XAAIRAAYJWwr1jQDkAAZoDAAABQAQAGkMAAAFAB4AawwAAAUAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQARAAYJWwr1jQDkAAZoDAAABQAQAGkMAAAFAB4AawwAAAUAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAQJBwAHAA0JAA==.Gloomybear:BAAALgADCgEJAgAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAMJCQAIAE0PAA==.Grindëlwald:BAABLgAECn8eAAISAAgJURbGCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAEgAICVEWxgsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUAwkJAAgATQ8A.',
Gu='Guac:BAAALgAECgQJDAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgYJHgAQAAEeAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8aAAMHAAcJ9hy+AwAfAgdoDAAABQBaAGkMAAAFAFoAawwAAAQAVgBqDAAAAwBZAGwMAAACAFAAbQwAAAEABgDqDAAABgBaAAcABwmTHL4DAB8CB2gMAAAEAFoAaQwAAAQAVABrDAAABABWAGoMAAADAFkAbAwAAAIAUABtDAAAAQAGAOoMAAAGAFoADQACCaYZAwYAsQACaAwAAAEAKABpDAAAAQBaAC4ABAp/IQADBwAJCWwjgwEArgMABwAJCUojgwEArgMADQAHCaAl2wUAmwIAAAA=.Ishmonk:BAABLgAECn8qAAMTAAkJwyCNBgB8AgloDAAABgBhAGkMAAAGAGAAawwAAAYAYQBqDAAABQBdAGwMAAAFAFcAbQwAAAMAVADqDAAABgBhAG4MAAAEADsAbwwAAAEAMwAGAAcJeiQLCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAMAYQBqDAAAAwBcAGwMAAACAFcAbQwAAAEAVADqDAAABABhABMACQkvHI0GAHwCCWgMAAADAFMAaQwAAAMAVgBrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUBwkaAAcA9hwA.Ishootudead:BAAALgAECggJCAABLgAFFAcJGgAHAPYcAA==.',
Jc='Jcole:BAAALgAECgYJCAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAEJAQAPAAAAAA==.Jon:BAABLgAECn8qAAIUAAkJoB6gDwCuAgloDAAABwBUAGkMAAAFAE8AawwAAAUAVABqDAAABQBMAGwMAAAFAFQAbQwAAAQARQDqDAAABgBaAG4MAAAEAEsAbwwAAAEAOgAUAAkJoB6gDwCuAgloDAAABwBUAGkMAAAFAE8AawwAAAUAVABqDAAABQBMAGwMAAAFAFQAbQwAAAQARQDqDAAABgBaAG4MAAAEAEsAbwwAAAEAOgAAAA==.',
Ka='Kaivasyr:BAABLgAECn8VAAIUAAcJfxWoSACdAQdoDAAAAwBNAGkMAAAEADoAawwAAAQAMgBqDAAABAA7AGwMAAACADUAbQwAAAEAHQDqDAAAAwA9ABQABwl/FahIAJ0BB2gMAAADAE0AaQwAAAQAOgBrDAAABAAyAGoMAAAEADsAbAwAAAIANQBtDAAAAQAdAOoMAAADAD0AAAA=.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgUJDAAAAA==.',
Ke='Kealee:BAAALgAECgUJCwAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8GAAIUAAQJJwW1RAASAQRoDAAAAQACAGkMAAACAA8AawwAAAEAEgDqDAAAAgAQABQABAknBbVEABIBBGgMAAABAAIAaQwAAAIADwBrDAAAAQASAOoMAAACABAALgAECn8dAAMUAAgJhBPgjQC3AQAUAAgJfBPgjQC3AQAVAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMKAAYJNAXMmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAKAAYJNAXMmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAWAAEJSwGvfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8dAAIKAAgJwRedIgDKAQhoDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABABNAGwMAAAEAEEAbQwAAAMAJQDqDAAABAAyAG4MAAACADYACgAICcEXnSIAygEIaAwAAAQARwBpDAAABABKAGsMAAAEAEcAagwAAAQATQBsDAAABABBAG0MAAADACUA6gwAAAQAMgBuDAAAAgA2AAAA.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAPAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAPAAAAAA==.Littletop:BAABLgAECn8UAAIXAAgJ2geuCwAnAQhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AFwAICdoHrgsAJwEIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8gAAIRAAgJCA0XSwB2AQhoDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABQAYAG4MAAACABkAEQAICQgNF0sAdgEIaAwAAAYAHwBpDAAABQA7AGsMAAAFACEAagwAAAQAJgBsDAAABAAgAG0MAAABABkA6gwAAAUAGABuDAAAAgAZAAAA.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8nAAIBAAgJlwpkUwBUAQhoDAAABgAXAGkMAAAGACUAawwAAAYAHABqDAAABQAWAGwMAAAEAB4AbQwAAAQADADqDAAABQAqAG4MAAADAA8AAQAICZcKZFMAVAEIaAwAAAYAFwBpDAAABgAlAGsMAAAGABwAagwAAAUAFgBsDAAABAAeAG0MAAAEAAwA6gwAAAUAKgBuDAAAAwAPAAAA.Malex:BAABLgAECn8fAAIHAAkJAyIqAgAiAwloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAHAAkJAyIqAgAiAwloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMEAAMJ8BkIIwDkAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAEAAMJ8BkIIwDkAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAADAAEJQgxOMABHAAFpDAAAAQAfAC4ABAp/GwADAwAICWMcZhgAUgIAAwAHCZsdZhgAUgIABAAHCeERYUIAdwEAAS4ABAoJCR8ABwADIgA=.Marselli:BAAALgAECggJDwAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn8rAAIYAAgJYQt6HQBaAQhoDAAABwA0AGkMAAAGABUAawwAAAYAIQBqDAAABQATAGwMAAAFABgAbQwAAAQAEQDqDAAABgArAG4MAAAEAAsAGAAICWELeh0AWgEIaAwAAAcANABpDAAABgAVAGsMAAAGACEAagwAAAUAEwBsDAAABQAYAG0MAAAEABEA6gwAAAYAKwBuDAAABAALAAAA.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8WAAIRAAYJ+x3bXADMAQZoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIA6gwAAAQATwARAAYJ+x3bXADMAQZoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIA6gwAAAQATwAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECgUJBgAAAA==.',
Om='Omgimaburger:BAABLgAECn8UAAMCAAYJsRwNIwDBAQZoDAAABAA7AGkMAAAEAFoAawwAAAQATABqDAAAAwBIAGwMAAABAFIA6gwAAAQAOgACAAYJsRwNIwDBAQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAQAOgAYAAQJmQolQQCRAARoDAAAAQAeAGkMAAABABEAawwAAAEAIgBqDAAAAQAbAAAA.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIUAAkJbB1aDADLAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAUAAkJbB1aDADLAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8fAAMJAAgJnCOWBgAkAwhoDAAABgBcAGkMAAAHAGEAawwAAAUAXwBqDAAAAgBdAGwMAAACAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACQAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAAsABgm1GzEUAIIBBmgMAAADADEAaQwAAAMASwBrDAAAAgBYAGwMAAABACQA6gwAAAIATQBuDAAAAgBhAAAA.',
Ph='Phatt:BAAALgAECgcJDgAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIEAAMJGB8uHQAGAQNoDAAABABXAGkMAAADAE0A6gwAAAIASQAEAAMJGB8uHQAGAQNoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy0AAgQACAmuJJEJAN8CAAQACAmuJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAAALgAECgQJEAAAAA==.Raghnoll:BAABLgAECn8oAAIZAAgJ8BSVEgAPAghoDAAABwA5AGkMAAAGAD8AawwAAAUATwBqDAAABQBPAGwMAAAFADkAbQwAAAMAJADqDAAABwArAG4MAAACAAsAGQAICfAUlRIADwIIaAwAAAcAOQBpDAAABgA/AGsMAAAFAE8AagwAAAUATwBsDAAABQA5AG0MAAADACQA6gwAAAcAKwBuDAAAAgALAAAA.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAABLgAECn8kAAIaAAkJAQ1jEQBaAQloDAAABgBFAGkMAAAFAC8AawwAAAUAKABqDAAABAAYAGwMAAAEABQAbQwAAAMAGgDqDAAABQAhAG4MAAADABcAbwwAAAEABAAaAAkJAQ1jEQBaAQloDAAABgBFAGkMAAAFAC8AawwAAAUAKABqDAAABAAYAGwMAAAEABQAbQwAAAMAGgDqDAAABQAhAG4MAAADABcAbwwAAAEABAAAAA==.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgUJCAABLgAFFAIJAgAPAAAAAA==.Sartorius:BAABLgAECn8XAAIYAAkJ7QW8JwASAQloDAAAAwAXAGkMAAADAAcAawwAAAMAFQBqDAAAAwAYAGwMAAADABIAbQwAAAEAAQDqDAAABQAdAG4MAAABAAYAbwwAAAEADQAYAAkJ7QW8JwASAQloDAAAAwAXAGkMAAADAAcAawwAAAMAFQBqDAAAAwAYAGwMAAADABIAbQwAAAEAAQDqDAAABQAdAG4MAAABAAYAbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGQAAAA==.',
Sc='Scarthan:BAABLgAECn8gAAIUAAgJCAP1iQAOAQhoDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABQAFAG4MAAABAAkAFAAICQgD9YkADgEIaAwAAAUABQBpDAAABQAMAGsMAAAFAAUAagwAAAUAEQBsDAAABAAKAG0MAAACAAQA6gwAAAUABQBuDAAAAQAJAAAA.Sciel:BAABLgAECn8YAAIDAAcJMCGLFAB6AgdoDAAAAwBaAGkMAAAFAF4AawwAAAQAUwBqDAAAAgBcAGwMAAADAEgAbQwAAAIAUQDqDAAABQBWAAMABwkwIYsUAHoCB2gMAAADAFoAaQwAAAUAXgBrDAAABABTAGoMAAACAFwAbAwAAAMASABtDAAAAgBRAOoMAAAFAFYAAAA=.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgMJBAAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNAABAHYlAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIGAAkJLwjgIgAgAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAGAAkJLwjgIgAgAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgUJBwAAAA==.',
So='Sojaslim:BAAALgAECgkJEgAAAA==.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECgcJCgAAAA==.',
Ta='Tagmamon:BAAALgAFFAEJAQABLgAFFAcJGQAaAKEeAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAUAGwdAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8JAAIEAAMJuBwMHwD8AANoDAAABABUAGkMAAADAFAA6gwAAAIANwAEAAMJuBwMHwD8AANoDAAABABUAGkMAAADAFAA6gwAAAIANwAuAAQKfy8AAgQACQk3IygBAIsDAAQACQk3IygBAIsDAAAA.',
Ti='Tibbsrog:BAAALgADCgUJBQAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJHAAbAGIjAA==.',
To='Topaten:BAAALgAECggJDQAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8WAAIRAAgJ8QrwcACaAQhoDAAABAAvAGkMAAAEADsAawwAAAQAHgBqDAAAAwAgAGwMAAACAA8AbQwAAAEADgDqDAAAAwATAG4MAAABAAgAEQAICfEK8HAAmgEIaAwAAAQALwBpDAAABAA7AGsMAAAEAB4AagwAAAMAIABsDAAAAgAPAG0MAAABAA4A6gwAAAMAEwBuDAAAAQAIAAAA.',
Va='Vaipara:BAAALgAECgMJBAAAAA==.Varissa:BAAALgAECgkJDgAAAA==.',
Vi='Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMcAAcJKB1MFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfABwABwnSHEwVADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AEAAHCeYYjSAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
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
