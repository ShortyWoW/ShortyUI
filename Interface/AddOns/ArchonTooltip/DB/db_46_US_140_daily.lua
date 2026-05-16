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

local lookup = {'Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Paladin-Retribution','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Paladin-Holy','Warrior-Protection','Rogue-Subtlety','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='daily',zone=46,date='2026-05-14',data={Al='Alilith:BAAALgAECgEJAQAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8IAAIBAAcJrAN2CQDXAQdoDAAAAQAQAGkMAAABAAQAawwAAAEABABqDAAAAQAGAGwMAAABAAMA6gwAAAIAGwBuDAAAAQACAAEABwmsA3YJANcBB2gMAAABABAAaQwAAAEABABrDAAAAQAEAGoMAAABAAYAbAwAAAEAAwDqDAAAAgAbAG4MAAABAAIAAAA=.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8GAAICAAIJsx5KfQCkAAJoDAAAAwBMAOoMAAADAFAAAgACCbMeSn0ApAACaAwAAAMATADqDAAAAwBQAAAA.',
As='Asecretbear:BAACLgAFFH8JAAIDAAMJ8wkLLgC1AANoDAAABAAwAGkMAAADAA8A6gwAAAIADAADAAMJ8wkLLgC1AANoDAAABAAwAGkMAAADAA8A6gwAAAIADAAuAAQKfyoAAgMACAniG7sXAHkCAAMACAniG7sXAHkCAAAA.Ashvana:BAACLgAFFH8KAAICAAMJ8x8/UQADAQNoDAAAAwBcAGkMAAAEAEcA6gwAAAMAUQACAAMJ8x8/UQADAQNoDAAAAwBcAGkMAAAEAEcA6gwAAAMAUQAuAAQKfzAAAgIACAmlJMATAIUCAAIACAmlJMATAIUCAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8hAAMEAAgJ1ROZBgCmAQhoDAAABgBOAGkMAAAGAF0AawwAAAUAMQBqDAAABAAjAGwMAAADACcAbQwAAAEABADqDAAABwA8AG4MAAABAB4ABAAGCVQWmQYApgEGaAwAAAYATgBpDAAABgBdAGsMAAAFADEAagwAAAEAIwBtDAAAAQAEAOoMAAAHADwABQADCf8HricA3AADagwAAAMACQBsDAAAAwAwAG4MAAABAAMALgAECn8oAAMEAAkJRCKZAwBpAwAEAAkJRCKZAwBpAwAFAAEJ8gZ9qAAmAAAAAA==.',
Ba='Balanced:BAACLgAFFH8fAAIGAAgJKxkVAQC/AghoDAAABQApAGkMAAAFAE4AawwAAAUARgBqDAAABABYAGwMAAADAFAAbQwAAAEAFQDqDAAABwBjAG4MAAABACIABgAICSsZFQEAvwIIaAwAAAUAKQBpDAAABQBOAGsMAAAFAEYAagwAAAQAWABsDAAAAwBQAG0MAAABABUA6gwAAAcAYwBuDAAAAQAiAC4ABAp/IQADBgAJCYIg8AMAMgMABgAJCYIg8AMAMgMABwAGCfYbahwA+AEAAS4ABAoJCR8ACAAEIgA=.',
Be='Berserkr:BAAALgAECgMJBgAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Ch='Chainéd:BAAALgAECgUJCwABLgAECggJHwAJAJwjAA==.Choco:BAACLgAFFH8GAAIEAAMJDBUsGwDsAANoDAAAAwAhAGkMAAABAEsA6gwAAAIANAAEAAMJDBUsGwDsAANoDAAAAwAhAGkMAAABAEsA6gwAAAIANAAuAAQKfxcAAgQACAklHUENADQCAAQACAklHUENADQCAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAFFAUJDAAKAJ8ZAA==.Crazy:BAAALgAECgQJBQAAAA==.Creme:BAABLgAECn8jAAIEAAgJrxvHFQBtAghoDAAABQBIAGkMAAAFAEkAawwAAAUAWgBqDAAABQBHAGwMAAAEADwAbQwAAAMAOgDqDAAABQBGAG4MAAADAEYABAAICa8bxxUAbQIIaAwAAAUASABpDAAABQBJAGsMAAAFAFoAagwAAAUARwBsDAAABAA8AG0MAAADADoA6gwAAAUARgBuDAAAAwBGAAAA.',
Cy='Cynestrya:BAACLgAFFH8FAAILAAIJpBlbFwC0AAJoDAAAAwBOAGkMAAACADQACwACCaQZWxcAtAACaAwAAAMATgBpDAAAAgA0AC4ABAp/LAACCwAJCfEZPAgASgIACwAJCfEZPAgASgIAAAA=.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgEJAQAAAA==.',
De='Deadlyfire:BAABLgAECn8VAAQMAAYJ/wLKGACtAAZoDAAABAAJAGkMAAAEAAgAawwAAAQABwBqDAAAAwAIAGwMAAADAAQA6gwAAAMACAAMAAYJlQLKGACtAAZoDAAAAwAJAGkMAAADAAgAawwAAAMABQBqDAAAAQAIAGwMAAABAAQA6gwAAAIABAAEAAUJ8QJeVAB9AAVoDAAAAQAIAGkMAAABAAUAawwAAAEABwBqDAAAAQAIAOoMAAABAAgABQACCXwD6Y8AWQACagwAAAEACQBsDAAAAgAIAAAA.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgYJCgAAAA==.Deralan:BAABLgAECn8dAAMIAAgJ/Qa9LAAYAQhoDAAABAAgAGkMAAADABsAawwAAAQACwBqDAAAAgAIAGwMAAAEAAwAbQwAAAQAFgDqDAAABQALAG4MAAADAAcACAAICf0GvSwAGAEIaAwAAAQAIABpDAAAAwAbAGsMAAAEAAsAagwAAAEACABsDAAAAwAMAG0MAAAEABYA6gwAAAUACwBuDAAAAwAHAA0AAglwA+UdACUAAmoMAAABAAcAbAwAAAEACAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAJAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIOAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAOAAkJVRyGDgDgAgloDAAABQBQAGkMAAAEAFsAawwAAAQAWwBqDAAABABLAGwMAAAEAGEAbQwAAAMAPQDqDAAAAwBJAG4MAAABADcAbwwAAAEAHQAAAA==.Dominatus:BAAALgAECgYJEAAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAAALgAFFAIJBAAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAABLgAECn8cAAMPAAgJ/B12CwCmAQhoDAAABgBKAGkMAAAFAF8AawwAAAQAYgBqDAAAAwBZAGwMAAADAFwAbQwAAAEALQDqDAAABABEAG4MAAACAD4ADwAICfwddgsApgEIaAwAAAYASgBpDAAABABfAGsMAAAEAGIAagwAAAMAWQBsDAAAAwBcAG0MAAABAC0A6gwAAAMARABuDAAAAQA+ABAAAwmbE0EbALwAA2kMAAABAD8A6gwAAAEAKQBuDAAAAQAtAAAA.Faengbrew:BAAALgADCgkJCQABLgAECggJHAAPAPwdAA==.Faenghorn:BAAALgAECgUJCgABLgAECggJHAAPAPwdAA==.Fanah:BAAALgADCggJDgABLgAECgYJHgABAAEeAA==.',
Fe='Fearmonger:BAAALgAECgEJAQAAAA==.Felora:BAAALgAECgEJAQAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Freshguac:BAAALgADCgEJAQAAAA==.Frozswarrior:BAAALgAECgcJDQAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8aAAIRAAYJWwqTnADcAAZoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQARAAYJWwqTnADcAAZoDAAABgAQAGkMAAAGAB4AawwAAAYAMABqDAAAAgASAGwMAAACAA8A6gwAAAQAFQAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAMJAwASAAAAAA==.Gloomybear:BAAALgADCgEJAgAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAMJDAATAJQTAA==.Grindêlwald:BAACLgAFFH8MAAITAAMJlBOqFQDPAANoDAAABQArAGkMAAAEAFEA6gwAAAMAGAATAAMJlBOqFQDPAANoDAAABQArAGkMAAAEAFEA6gwAAAMAGAAuAAQKfxcAAhMACAm7HKMIAC4CABMACAm7HKMIAC4CAAAA.Grindëlwald:BAABLgAECn8eAAIUAAgJURbHCwANAghoDAAABQAfAGkMAAAFAFIAawwAAAUATgBqDAAABABAAGwMAAAEAE4AbQwAAAIAIADqDAAABABHAG4MAAABABkAFAAICVEWxwsADQIIaAwAAAUAHwBpDAAABQBSAGsMAAAFAE4AagwAAAQAQABsDAAABABOAG0MAAACACAA6gwAAAQARwBuDAAAAQAZAAEuAAUUAwkMABMAlBMA.',
Gu='Guac:BAAALgAECgQJDAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgYJHgABAAEeAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8eAAMIAAgJ2xo7AgB1AghoDAAABQBaAGkMAAAFAFoAawwAAAQAVgBqDAAABABZAGwMAAADAFAAbQwAAAEABgDqDAAABwBaAG4MAAABACQACAAICYcaOwIAdQIIaAwAAAQAWgBpDAAABABUAGsMAAAEAFYAagwAAAQAWQBsDAAAAwBQAG0MAAABAAYA6gwAAAcAWgBuDAAAAQAkAA0AAgmmGQQGALEAAmgMAAABACgAaQwAAAEAWgAuAAQKfycAAwgACQlsI4MBAK4DAAgACQlKI4MBAK4DAA0ABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8wAAMVAAkJxiAHCABvAgloDAAABwBhAGkMAAAHAGAAawwAAAcAYQBqDAAABgBdAGwMAAAGAFcAbQwAAAQAVADqDAAABgBhAG4MAAAEADsAbwwAAAEAMwAHAAcJeiQNCgDXAgdoDAAAAwBhAGkMAAADAGAAawwAAAQAYQBqDAAABABcAGwMAAADAFcAbQwAAAIAVADqDAAABABhABUACQnKHAcIAG8CCWgMAAAEAFUAaQwAAAQAYABrDAAAAwBVAGoMAAACAF0AbAwAAAMAQQBtDAAAAgA1AOoMAAACAFwAbgwAAAQAOwBvDAAAAQAzAAEuAAUUCAkeAAgA2xoA.Ishootudead:BAAALgAECggJCAABLgAFFAgJHgAIANsaAA==.',
Jc='Jcole:BAAALgAECgYJCAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJCAABAKwDAA==.Jon:BAACLgAFFH8FAAIWAAIJcRP1aQCrAAJoDAAAAwA/AGkMAAACACMAFgACCXET9WkAqwACaAwAAAMAPwBpDAAAAgAjAC4ABAp/KgACFgAJCaAe4xUAkAIAFgAJCaAe4xUAkAIAAAA=.Josito:BAAALgADCggJCAABLgAECgcJFgAWAAckAA==.',
Ka='Kaivasyr:BAABLgAECn8VAAIWAAcJfxWaUwCOAQdoDAAAAwBNAGkMAAAEADoAawwAAAQAMgBqDAAABAA7AGwMAAACADUAbQwAAAEAHQDqDAAAAwA9ABYABwl/FZpTAI4BB2gMAAADAE0AaQwAAAQAOgBrDAAABAAyAGoMAAAEADsAbAwAAAIANQBtDAAAAQAdAOoMAAADAD0AAAA=.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgYJEgAAAA==.',
Ke='Kealee:BAAALgAECgYJEQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIWAAQJBQaoRQAiAQRoDAAAAgAKAGkMAAAEABAAawwAAAIAEgDqDAAAAwAQABYABAkFBqhFACIBBGgMAAACAAoAaQwAAAQAEABrDAAAAgASAOoMAAADABAALgAECn8iAAMWAAgJ4BSwUQCTAQAWAAgJ2BSwUQCTAQAXAAQJ6gzsDwDDAAAAAA==.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMKAAYJNAXOmgDkAAZoDAAABQAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAKAAYJNAXOmgDkAAZoDAAABAAUAGkMAAAEAAgAawwAAAQADgBqDAAAAgAJAGwMAAACAA4A6gwAAAQACAAYAAEJSwGxfQAgAAFoDAAAAQADAAAA.',
Le='Leyanis:BAABLgAECn8dAAIKAAgJwRd4KwC6AQhoDAAABABHAGkMAAAEAEoAawwAAAQARwBqDAAABABNAGwMAAAEAEEAbQwAAAMAJQDqDAAABAAyAG4MAAACADYACgAICcEXeCsAugEIaAwAAAQARwBpDAAABABKAGsMAAAEAEcAagwAAAQATQBsDAAABABBAG0MAAADACUA6gwAAAQAMgBuDAAAAgA2AAAA.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAASAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAASAAAAAA==.Littletop:BAABLgAECn8UAAIZAAgJ2ge2DQAPAQhoDAAAAwAWAGkMAAADABgAawwAAAMAFwBqDAAAAwAPAGwMAAADABgAbQwAAAEABADqDAAAAwAbAG4MAAABAA4AGQAICdoHtg0ADwEIaAwAAAMAFgBpDAAAAwAYAGsMAAADABcAagwAAAMADwBsDAAAAwAYAG0MAAABAAQA6gwAAAMAGwBuDAAAAQAOAAAA.',
Lo='Lostfaith:BAABLgAECn8iAAIRAAgJCA1oWABjAQhoDAAABgAfAGkMAAAFADsAawwAAAUAIQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGQDqDAAABgAYAG4MAAADABkAEQAICQgNaFgAYwEIaAwAAAYAHwBpDAAABQA7AGsMAAAFACEAagwAAAQAJgBsDAAABAAgAG0MAAABABkA6gwAAAYAGABuDAAAAwAZAAAA.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8nAAICAAgJlwrPYQBBAQhoDAAABgAXAGkMAAAGACUAawwAAAYAHABqDAAABQAWAGwMAAAEAB4AbQwAAAQADADqDAAABQAqAG4MAAADAA8AAgAICZcKz2EAQQEIaAwAAAYAFwBpDAAABgAlAGsMAAAGABwAagwAAAUAFgBsDAAABAAeAG0MAAAEAAwA6gwAAAUAKgBuDAAAAwAPAAAA.Malex:BAABLgAECn8fAAIIAAkJBCIRAwAKAwloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAIAAkJBCIRAwAKAwloDAAABABcAGkMAAAEAFwAawwAAAQAXABqDAAABABjAGwMAAAEAGEAbQwAAAMAWwDqDAAABABUAG4MAAADAFMAbwwAAAEAPQAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8Bl5JgDjAANoDAAAAgA7AGkMAAADAFMA6gwAAAEAOAAFAAMJ8Bl5JgDjAANoDAAAAgA7AGkMAAACAFMA6gwAAAEAOAAEAAEJQgwWNgBAAAFpDAAAAQAfAC4ABAp/GwADBAAICWMcahgAUQIABAAHCZsdahgAUQIABQAHCeERY0IAdwEAAS4ABAoJCR8ACAAEIgA=.Marselli:BAAALgAECggJDwAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn8rAAIaAAgJYQsrIwBAAQhoDAAABwA0AGkMAAAGABUAawwAAAYAIQBqDAAABQATAGwMAAAFABgAbQwAAAQAEQDqDAAABgArAG4MAAAEAAsAGgAICWELKyMAQAEIaAwAAAcANABpDAAABgAVAGsMAAAGACEAagwAAAUAEwBsDAAABQAYAG0MAAAEABEA6gwAAAYAKwBuDAAABAALAAAA.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8WAAIRAAYJ+x3aXADMAQZoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIA6gwAAAQATwARAAYJ+x3aXADMAQZoDAAABABRAGkMAAAFAFQAawwAAAUASABqDAAAAQBTAGwMAAADAEIA6gwAAAQATwAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECgUJBgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRzUJgC9AQZoDAAABQA7AGkMAAAFAFoAawwAAAUATABqDAAABABIAGwMAAACAFIA6gwAAAUAOgADAAYJsRzUJgC9AQZoDAAAAwA7AGkMAAADAFoAawwAAAMATABqDAAAAgBIAGwMAAABAFIA6gwAAAUAOgAaAAUJ/A6JNwDKAAVoDAAAAgAeAGkMAAACACoAawwAAAIAIgBqDAAAAgAbAGwMAAABAC4AAAA=.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIWAAkJbB0uEQCyAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAWAAkJbB0uEQCyAgloDAAABgBiAGkMAAAGAFAAawwAAAYARwBqDAAABgBXAGwMAAAGAFYAbQwAAAQAWADqDAAABwBVAG4MAAAEACMAbwwAAAEANwAAAA==.',
Pe='Pepe:BAABLgAECn8fAAMJAAgJnCOWBgAkAwhoDAAABgBcAGkMAAAHAGEAawwAAAUAXwBqDAAAAgBdAGwMAAACAF0AbQwAAAEATwDqDAAABQBRAG4MAAADAGEACQAICecilgYAJAMIaAwAAAMAXABpDAAABABhAGsMAAADAF8AagwAAAIAXQBsDAAAAQBdAG0MAAABAE8A6gwAAAMAUQBuDAAAAQBUAAsABgm1GzYUAIIBBmgMAAADADEAaQwAAAMASwBrDAAAAgBYAGwMAAABACQA6gwAAAIATQBuDAAAAgBhAAAA.',
Ph='Phatt:BAAALgAECgcJDgAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB/FHwADAQNoDAAABABXAGkMAAADAE0A6gwAAAIASQAFAAMJGB/FHwADAQNoDAAABABXAGkMAAADAE0A6gwAAAIASQAuAAQKfy4AAgUACAmuJJEJAN8CAAUACAmuJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8WAAICAAYJvAh0iADwAAZoDAAABgAdAGkMAAAFABYAawwAAAUACQBqDAAAAQAZAGwMAAABAB0A6gwAAAQAFAACAAYJvAh0iADwAAZoDAAABgAdAGkMAAAFABYAawwAAAUACQBqDAAAAQAZAGwMAAABAB0A6gwAAAQAFAAAAA==.Raghnoll:BAABLgAECn8oAAIbAAgJ8BQ/FgD8AQhoDAAABwA5AGkMAAAGAD8AawwAAAUATwBqDAAABQBPAGwMAAAFADkAbQwAAAMAJADqDAAABwArAG4MAAACAAsAGwAICfAUPxYA/AEIaAwAAAcAOQBpDAAABgA/AGsMAAAFAE8AagwAAAUATwBsDAAABQA5AG0MAAADACQA6gwAAAcAKwBuDAAAAgALAAAA.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8FAAIcAAIJ8wRvGQBmAAJoDAAAAwAWAGkMAAACAAMAHAACCfMEbxkAZgACaAwAAAMAFgBpDAAAAgADAC4ABAp/JAACHAAJCQENqBMATAEAHAAJCQENqBMATAEAAAA=.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgUJCQABLgAECgcJFgAWAAckAA==.Sartorius:BAABLgAECn8XAAIaAAkJ7QV5LAAEAQloDAAAAwAXAGkMAAADAAcAawwAAAMAFQBqDAAAAwAYAGwMAAADABIAbQwAAAEAAQDqDAAABQAdAG4MAAABAAYAbwwAAAEADQAaAAkJ7QV5LAAEAQloDAAAAwAXAGkMAAADAAcAawwAAAMAFQBqDAAAAwAYAGwMAAADABIAbQwAAAEAAQDqDAAABQAdAG4MAAABAAYAbwwAAAEADQAAAA==.Satiate:BAAALgADCgYJGQAAAA==.',
Sc='Scarthan:BAABLgAECn8gAAIWAAgJCAPKlQACAQhoDAAABQAFAGkMAAAFAAwAawwAAAUABQBqDAAABQARAGwMAAAEAAoAbQwAAAIABADqDAAABQAFAG4MAAABAAkAFgAICQgDypUAAgEIaAwAAAUABQBpDAAABQAMAGsMAAAFAAUAagwAAAUAEQBsDAAABAAKAG0MAAACAAQA6gwAAAUABQBuDAAAAQAJAAAA.Sciel:BAABLgAECn8YAAIEAAcJMCGPFAB6AgdoDAAAAwBaAGkMAAAFAF4AawwAAAQAUwBqDAAAAgBcAGwMAAADAEgAbQwAAAIAUQDqDAAABQBWAAQABwkwIY8UAHoCB2gMAAADAFoAaQwAAAUAXgBrDAAABABTAGoMAAACAFwAbAwAAAMASABtDAAAAgBRAOoMAAAFAFYAAAA=.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgMJBAAAAA==.Selkhis:BAAALgAECgQJBAAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNgACAHYlAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwiJJwAVAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAHAAkJLwiJJwAVAQloDAAABAAMAGkMAAAEABoAawwAAAQALQBqDAAAAwAXAGwMAAAEABgAbQwAAAEABwDqDAAAAwANAG4MAAACABAAbwwAAAEAFQAAAA==.',
Si='Sizzlesham:BAAALgAECgUJBwAAAA==.',
So='Sojaslim:BAABLgAECn8YAAIJAAcJ2hNmRQBiAQdoDAAABgBEAGkMAAAFAD4AawwAAAUATQBqDAAAAgA3AGwMAAADACQA6gwAAAIAPABuDAAAAQAAAAkABwnaE2ZFAGIBB2gMAAAGAEQAaQwAAAUAPgBrDAAABQBNAGoMAAACADcAbAwAAAMAJADqDAAAAgA8AG4MAAABAAAAAAA=.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAcJHAAcAFgfAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAWAGwdAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8NAAIFAAQJIRiEFQA6AQRoDAAABQBUAGkMAAAEAFAAawwAAAEAGgDqDAAAAwA3AAUABAkhGIQVADoBBGgMAAAFAFQAaQwAAAQAUABrDAAAAQAaAOoMAAADADcALgAECn8zAAIFAAkJBSW0AACzAwAFAAkJBSW0AACzAwAAAA==.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJHAAdAGIjAA==.',
To='Topaten:BAAALgAFFAIJAgAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8WAAIRAAgJ8QrwcACaAQhoDAAABAAvAGkMAAAEADsAawwAAAQAHgBqDAAAAwAgAGwMAAACAA8AbQwAAAEADgDqDAAAAwATAG4MAAABAAgAEQAICfEK8HAAmgEIaAwAAAQALwBpDAAABAA7AGsMAAAEAB4AagwAAAMAIABsDAAAAgAPAG0MAAABAA4A6gwAAAMAEwBuDAAAAQAIAAAA.',
Va='Vaipara:BAAALgAECgMJBAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMeAAcJKB1NFQAzAgdoDAAABAAkAGkMAAADAEIAawwAAAUATgBqDAAAAwBLAGwMAAAGAFwAbQwAAAIATgDqDAAABQBfAB4ABwnSHE0VADMCB2gMAAADACQAaQwAAAIAQgBrDAAABABOAGoMAAACAEYAbAwAAAIAWwBtDAAAAQBOAOoMAAAEAF8AAQAHCeYYjyAAjwEHaAwAAAEAIwBpDAAAAQA2AGsMAAABADUAagwAAAEASwBsDAAABABcAG0MAAABAEkA6gwAAAEAPQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgASAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.',
['Àl']='Àlilith:BAAALgAECgcJEwAAAA==.',
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
