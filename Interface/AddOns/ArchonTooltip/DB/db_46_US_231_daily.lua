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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Warrior-Fury','Evoker-Devastation','Warlock-Demonology','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='daily',zone=46,date='2026-05-16',data={Ab='Abelle:BAAALgAECgQJBQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgIJAwAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgYJBgABLgAECggJFQABAOwdAA==.Anonymoose:BAAALgAECgYJDQAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgADCgUJBQAAAA==.Arykiel:BAABLgAECn8bAAICAAgJOxdURACyAQhoDAAABQBBAGkMAAAFAEgAawwAAAQARwBqDAAAAwA0AGwMAAACADcAbQwAAAEALADqDAAABgBCAG4MAAABACgAAgAICTsXVEQAsgEIaAwAAAUAQQBpDAAABQBIAGsMAAAEAEcAagwAAAMANABsDAAAAgA3AG0MAAABACwA6gwAAAYAQgBuDAAAAQAoAAAA.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAUJDQADAOkdAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAYJDwAEAN0WAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBAUGQB4AQhoDAAAAwAmAGkMAAADADcAawwAAAMAIgBqDAAABAAaAGwMAAADACkAbQwAAAIAGADqDAAABQAuAG4MAAACADYABQAICXwQFBkAeAEIaAwAAAMAJgBpDAAAAwA3AGsMAAADACIAagwAAAQAGgBsDAAAAwApAG0MAAACABgA6gwAAAUALgBuDAAAAgA2AAAA.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAABLgAECn8hAAMGAAgJ3hTtDQCaAQhoDAAABgAtAGkMAAAFAEYAawwAAAYAQABqDAAABABBAGwMAAADADQAbQwAAAEANwDqDAAABwA2AG4MAAABACAABgAICd4U7Q0AmgEIaAwAAAMALQBpDAAAAwBGAGsMAAAEAEAAagwAAAMAQQBsDAAAAwA0AG0MAAABADcA6gwAAAMANgBuDAAAAQAgAAcABQl5DlcdAP8ABWgMAAADACkAaQwAAAIAJgBrDAAAAgAfAGoMAAABAA8A6gwAAAQAJAAAAA==.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BedLAA7AQdoDAAABABFAGkMAAADAEoAawwAAAQASwBqDAAAAwAwAGwMAAABABcA6gwAAAUARQBuDAAAAQA4AAgABwn4F50sADsBB2gMAAAEAEUAaQwAAAMASgBrDAAABABLAGoMAAADADAAbAwAAAEAFwDqDAAABQBFAG4MAAABADgAAAA=.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAQAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJBQAJADUDAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQAKAAAAAA==.',
Bu='Bubbies:BAABLgAECn8eAAMLAAkJEBQKFgDRAQloDAAABQBSAGkMAAAEAEYAawwAAAMAIABqDAAAAwAnAGwMAAAEAEAAbQwAAAIANwDqDAAABwA6AG4MAAABACcAbwwAAAEAEgALAAgJnxQKFgDRAQhoDAAABQBSAGkMAAAEAEYAawwAAAMAIABqDAAAAwAnAGwMAAADAEAAbQwAAAEANwDqDAAABgA6AG8MAAABABIADAAECRwKVkEAtAAEbAwAAAEAGgBtDAAAAQATAOoMAAABABwAbgwAAAEAHQAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8bAAICAAkJ/BGqRACxAQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAAEADwAbQwAAAMALgDqDAAABAAlAG4MAAADAF4AbwwAAAIAGwACAAkJ/BGqRACxAQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAAEADwAbQwAAAMALgDqDAAABAAlAG4MAAADAF4AbwwAAAIAGwAAAA==.Chiste:BAABLgAECn8iAAINAAgJow45CgBQAQhoDAAACQBMAGkMAAAGACwAawwAAAUALABqDAAAAgAxAGwMAAAEABEAbQwAAAEADQDqDAAABgArAG4MAAABABUADQAICaMOOQoAUAEIaAwAAAkATABpDAAABgAsAGsMAAAFACwAagwAAAIAMQBsDAAABAARAG0MAAABAA0A6gwAAAYAKwBuDAAAAQAVAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwAKAAAAAA==.Coredellion:BAAALgADCgUJDAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn80AAIOAAkJoRs7CQDVAgloDAAACAAuAGkMAAAIAFMAawwAAAgAUgBqDAAABwBLAGwMAAAHAFAAbQwAAAQAHgDqDAAABgBTAG4MAAADAFIAbwwAAAEARQAOAAkJoRs7CQDVAgloDAAACAAuAGkMAAAIAFMAawwAAAgAUgBqDAAABwBLAGwMAAAHAFAAbQwAAAQAHgDqDAAABgBTAG4MAAADAFIAbwwAAAEARQABLgAFFAYJGgAPAJMYAA==.Dannica:BAAALgAECgcJCAAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgYJEQAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAFFAEJAQABLgAFFAYJDwAEAN0WAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8cAAICAAgJjQ5jWgB2AQhoDAAABAAjAGkMAAAEABIAawwAAAQAGQBqDAAAAwAnAGwMAAAFADgAbQwAAAEAIgDqDAAABgBKAG4MAAABAA4AAgAICY0OY1oAdgEIaAwAAAQAIwBpDAAABAASAGsMAAAEABkAagwAAAMAJwBsDAAABQA4AG0MAAABACIA6gwAAAYASgBuDAAAAQAOAAAA.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAMJCAAQAMocAA==.Donut:BAABLgAECn8VAAIRAAgJABKFNADoAQhoDAAAAgAIAGkMAAABAAkAawwAAAEABABsDAAAAwBIAG0MAAADAFIA6gwAAAUAQgBuDAAAAwBEAG8MAAADADcAEQAICQAShTQA6AEIaAwAAAIACABpDAAAAQAJAGsMAAABAAQAbAwAAAMASABtDAAAAwBSAOoMAAAFAEIAbgwAAAMARABvDAAAAwA3AAEuAAQKBwkWAAcASQ8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn81AAMSAAkJFyJWAQBhAwloDAAACQBiAGkMAAAJAFwAawwAAAgAYQBqDAAABwBcAGwMAAAGAGEAbQwAAAMAWgDqDAAABwBgAG4MAAADAE0AbwwAAAEAKQASAAkJFyJWAQBhAwloDAAABwBiAGkMAAAGAFwAawwAAAUAYQBqDAAABQBcAGwMAAAFAGEAbQwAAAIAWgDqDAAABgBgAG4MAAADAE0AbwwAAAEAKQATAAcJCBS5JABnAQdoDAAAAgAzAGkMAAADAEAAawwAAAMAMQBqDAAAAgA7AGwMAAABADUAbQwAAAEALADqDAAAAQArAAAA.Elizalynn:BAABLgAECn8iAAIUAAgJFRJSHACcAQhoDAAABgA5AGkMAAAGACcAawwAAAUALgBqDAAABQA1AGwMAAAEACMAbQwAAAIAKADqDAAABABZAG4MAAACAAgAFAAICRUSUhwAnAEIaAwAAAYAOQBpDAAABgAnAGsMAAAFAC4AagwAAAUANQBsDAAABAAjAG0MAAACACgA6gwAAAQAWQBuDAAAAgAIAAAA.',
Ev='Eveycakes:BAAALgAFFAEJAgABLgAFFAUJDQADAOkdAA==.',
Fe='Fengshui:BAABLgAECn8WAAIIAAkJsBFWGQDGAQloDAAAAwBGAGkMAAADAD0AawwAAAMANQBqDAAAAwA3AGwMAAADAB4AbQwAAAIAHQDqDAAAAgApAG4MAAACADEAbwwAAAEAGQAIAAkJsBFWGQDGAQloDAAAAwBGAGkMAAADAD0AawwAAAMANQBqDAAAAwA3AGwMAAADAB4AbQwAAAIAHQDqDAAAAgApAG4MAAACADEAbwwAAAEAGQAAAA==.Ferritin:BAABLgAECn8sAAIEAAkJESTcAQBjAwloDAAABwBjAGkMAAAHAGAAawwAAAcAYgBqDAAABgBjAGwMAAAGAGMAbQwAAAMAYQDqDAAABQBhAG4MAAACAFUAbwwAAAEAQAAEAAkJESTcAQBjAwloDAAABwBjAGkMAAAHAGAAawwAAAcAYgBqDAAABgBjAGwMAAAGAGMAbQwAAAMAYQDqDAAABQBhAG4MAAACAFUAbwwAAAEAQAAAAA==.Fester:BAAALgAECgEJAgAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8OAAIVAAQJDhlVEwA3AQRoDAAABQA5AGkMAAAEAD4AawwAAAIANADqDAAAAwBTABUABAkOGVUTADcBBGgMAAAFADkAaQwAAAQAPgBrDAAAAgA0AOoMAAADAFMALgAECn85AAMVAAkJWxvwDgBoAgAVAAkJWxvwDgBoAgAWAAgJbxxJEAD5AQAAAA==.',
Fo='Focaccia:BAABLgAECn8cAAIXAAkJEh3MFQCfAgloDAAAAwBZAGkMAAADAEAAawwAAAMAOwBqDAAAAwBNAGwMAAAEAFUAbQwAAAMATgDqDAAABABYAG4MAAAEAEIAbwwAAAEAPQAXAAkJEh3MFQCfAgloDAAAAwBZAGkMAAADAEAAawwAAAMAOwBqDAAAAwBNAGwMAAAEAFUAbQwAAAMATgDqDAAABABYAG4MAAAEAEIAbwwAAAEAPQAAAA==.Foxthisup:BAAALgAECgYJBgAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJEAAKAAAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAYJGgAPAJMYAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQAKAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgADCgYJBwAAAA==.Grultock:BAAALgAECgUJCwAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8iAAIOAAgJfx0bDgCWAghoDAAABgBWAGkMAAAGAEsAawwAAAUAUABqDAAABQBZAGwMAAAEAE0AbQwAAAIANADqDAAABABhAG4MAAACACwADgAICX8dGw4AlgIIaAwAAAYAVgBpDAAABgBLAGsMAAAFAFAAagwAAAUAWQBsDAAABABNAG0MAAACADQA6gwAAAQAYQBuDAAAAgAsAAAA.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgMJAwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgQJBgABLgAECgkJKQAPAAQZAA==.Hockeyhunter:BAABLgAECn8pAAIPAAkJBBkvGQBDAgloDAAABwA/AGkMAAAGAFUAawwAAAcASgBqDAAABAA5AGwMAAAEADoAbQwAAAMAVgDqDAAABgBDAG4MAAADAD4AbwwAAAEADgAPAAkJBBkvGQBDAgloDAAABwA/AGkMAAAGAFUAawwAAAcASgBqDAAABAA5AGwMAAAEADoAbQwAAAMAVgDqDAAABgBDAG4MAAADAD4AbwwAAAEADgAAAA==.Hockeylockz:BAAALgAECgYJEQABLgAECgkJKQAPAAQZAA==.Hockeysticks:BAAALgADCgMJAwABLgAECgkJKQAPAAQZAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAXANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8bAAMPAAgJ+BcSKADwAQhoDAAABABJAGkMAAAEAEgAawwAAAQASQBqDAAABAA2AGwMAAAEADgA6gwAAAQANQBuDAAAAgBCAG8MAAABACAADwAICfgXEigA8AEIaAwAAAMASQBpDAAABABIAGsMAAAEAEkAagwAAAQANgBsDAAABAA4AOoMAAAEADUAbgwAAAIAQgBvDAAAAQAgABgAAQkwCecsACsAAWgMAAABABcAAS4ABAoICSEABgDeFAA=.',
['Hè']='Hèxen:BAAALgADCgcJBgAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAAALgAECgYJEAAAAA==.',
Ig='Igneel:BAAALgADCgcJDgAAAA==.',
Je='Jedem:BAAALgADCgUJCQAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAAKAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCAAAAA==.Kazum:BAAALgAECgEJAgAAAA==.',
Ke='Keralan:BAACLgAFFH8HAAMBAAMJbx0oCABnAANoDAAAAQA6AGoMAAADAFYA6gwAAAMAXAABAAIJBSQoCABnAAJqDAAAAwBWAOoMAAADAFwAGQABCdgWoBMAUAABaAwAAAEAOgAuAAQKfyYAAwEACQkQJkUAAFcDAAEACQkQJkUAAFcDABkAAQmhFVJFAEIAAAEuAAUUBQkVABoA3CEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8gAAIJAAgJ+yOuBACWAghoDAAABQBgAGkMAAAFAFYAawwAAAUAXQBqDAAAAwBOAGwMAAADAGAAbQwAAAEAWwDqDAAABwBdAG4MAAADAFcACQAICfsjrgQAlgIIaAwAAAUAYABpDAAABQBWAGsMAAAFAF0AagwAAAMATgBsDAAAAwBgAG0MAAABAFsA6gwAAAcAXQBuDAAAAwBXAAAA.',
Kw='Kwehlewd:BAABLgAECn8YAAIbAAcJlA3bMQD8AAdoDAAABAAwAGkMAAAEACgAawwAAAQAIwBqDAAAAwAnAGwMAAADABsAbQwAAAEACgDqDAAABQAuABsABwmUDdsxAPwAB2gMAAAEADAAaQwAAAQAKABrDAAABAAjAGoMAAADACcAbAwAAAMAGwBtDAAAAQAKAOoMAAAFAC4AAAA=.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwAKAAAAAA==.Laizee:BAABLgAECn8gAAIOAAgJ3gPeVQD3AAhoDAAABQAFAGkMAAAFAA0AawwAAAUAFgBqDAAAAwAOAGwMAAADAAcAbQwAAAEABQDqDAAABwAFAG4MAAADAAQADgAICd4D3lUA9wAIaAwAAAUABQBpDAAABQANAGsMAAAFABYAagwAAAMADgBsDAAAAwAHAG0MAAABAAUA6gwAAAcABQBuDAAAAwAEAAAA.Latrice:BAABLgAECn8lAAICAAkJ6h0ZHABcAgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAACAAkJ6h0ZHABcAgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAAAAA==.Laveyan:BAEALgADCgUJCAABLgAECgQJCAAKAAAAAA==.',
Lo='Loki:BAABLgAECn8aAAISAAYJ8BoiDADLAQZoDAAABgBTAGkMAAAGAEgAawwAAAYASwBqDAAAAwA2AGwMAAACAEQA6gwAAAMAOgASAAYJ8BoiDADLAQZoDAAABgBTAGkMAAAGAEgAawwAAAYASwBqDAAAAwA2AGwMAAACAEQA6gwAAAMAOgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8jAAIcAAYJ2hYOUwA+AQZoDAAABgBIAGkMAAAHAEMAawwAAAcAKgBqDAAABAApAGwMAAAEADMA6gwAAAcAOQAcAAYJ2hYOUwA+AQZoDAAABgBIAGkMAAAHAEMAawwAAAcAKgBqDAAABAApAGwMAAAEADMA6gwAAAcAOQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIVAAkJPBotCQCqAgloDAAABgAvAGkMAAAGAD8AawwAAAYAUgBqDAAABQBQAGwMAAAEAEMAbQwAAAMAMQDqDAAAAgBWAG4MAAACAFMAbwwAAAEAKwAVAAkJPBotCQCqAgloDAAABgAvAGkMAAAGAD8AawwAAAYAUgBqDAAABQBQAGwMAAAEAEMAbQwAAAMAMQDqDAAAAgBWAG4MAAACAFMAbwwAAAEAKwAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJOAAUAL8gAA==.',
Me='Melander:BAABLgAECn8gAAIJAAkJwhuiBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABQBTAG4MAAABACoAbwwAAAEAIQAJAAkJwhuiBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABQBTAG4MAAABACoAbwwAAAEAIQAAAA==.',
Mh='Mhoram:BAAALgAECgEJAQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAMJCAAQAMocAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIRAAIJeSBxOACqAAJoDAAABABJAOoMAAAFAF0AEQACCXkgcTgAqgACaAwAAAQASQDqDAAABQBdAC4ABAp/JAACEQAICXkkfhIAmwIAEQAICXkkfhIAmwIAAAA=.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAAALgAECgcJBwABLgAECgkJIAAJAMIbAA==.Nerzhuul:BAACLgAFFH8IAAIQAAMJyhyTBQANAQNoDAAABABbAGkMAAACAEUA6gwAAAIAPAAQAAMJyhyTBQANAQNoDAAABABbAGkMAAACAEUA6gwAAAIAPAAuAAQKfy0AAhAACQmaHp4FAKkCABAACQmaHp4FAKkCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQAKAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxzsEQA7AghoDAAABQBbAGkMAAAFAEIAawwAAAUAUgBqDAAABAAtAGwMAAADAFIAbQwAAAQAMwDqDAAABQBMAG4MAAAEAEwAAwAICQMc7BEAOwIIaAwAAAUAWwBpDAAABQBCAGsMAAAFAFIAagwAAAQALQBsDAAAAwBSAG0MAAAEADMA6gwAAAUATABuDAAABABMAAAA.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIXAAYJFxXvnAAIAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAXAAYJFxXvnAAIAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMdAAgJBBtpIgDxAQhoDAAABABaAGkMAAAEAF8AawwAAAMAQwBqDAAABABCAGwMAAACADQAbQwAAAEAQQDqDAAABwBUAG4MAAABAB4AHQAGCbgdaSIA8QEGaAwAAAMAWgBpDAAAAwBfAGsMAAACAEMAagwAAAMAQgBsDAAAAQA0AOoMAAAHAFQAGwAHCdEOaTAAhQEHaAwAAAEALwBpDAAAAQA2AGsMAAABACsAagwAAAEAIwBsDAAAAQAjAG0MAAABABMAbgwAAAEAGQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJDwABLgAFFAYJDwAEAN0WAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8FAAIJAAIJNQP1GgBiAAJoDAAAAwAMAGkMAAACAAQACQACCTUD9RoAYgACaAwAAAMADABpDAAAAgAEAC4ABAp/HQACCQAICW0NKxcAOQEACQAICW0NKxcAOQEAAAA=.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgUJCAAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8eAAQUAAcJ4h4PDQBMAgdoDAAABQBPAGkMAAAFAD4AawwAAAUARABqDAAABQBHAGwMAAAEAFAAbQwAAAEAWwDqDAAABQBhABQABwniHg8NAEwCB2gMAAADAE8AaQwAAAMAPgBrDAAAAwBEAGoMAAAEAEcAbAwAAAIAUABtDAAAAQBbAOoMAAADAGEADAAFCSEaIiwAIQEFaAwAAAIAOgBpDAAAAgBDAGsMAAACAEsAagwAAAEATQBsDAAAAgBCAAsAAQk1FoxSADwAAeoMAAACADgAAS4ABRQCCQQACgAAAAA=.Raggnarr:BAACLgAFFH8PAAIeAAQJVx6yCgBjAQRoDAAABQBHAGkMAAADAFoAawwAAAMAUgDqDAAABABCAB4ABAlXHrIKAGMBBGgMAAAFAEcAaQwAAAMAWgBrDAAAAwBSAOoMAAAEAEIALgAECn80AAIeAAkJkyWfAQA8AwAeAAkJkyWfAQA8AwAAAA==.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8JAAIUAAMJSxtVEQDxAANoDAAAAwBOAGkMAAACADkA6gwAAAQASQAUAAMJSxtVEQDxAANoDAAAAwBOAGkMAAACADkA6gwAAAQASQAAAA==.Rania:BAABLgAECn8VAAIaAAgJ1CBsDQC8AghoDAAAAwBTAGkMAAADAF0AawwAAAMAWwBqDAAAAgBWAGwMAAACAFAAbQwAAAEAUgDqDAAABQBNAG4MAAACAE4AGgAICdQgbA0AvAIIaAwAAAMAUwBpDAAAAwBdAGsMAAADAFsAagwAAAIAVgBsDAAAAgBQAG0MAAABAFIA6gwAAAUATQBuDAAAAgBOAAAA.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn89AAMTAAkJnRiZEAAZAgloDAAABwBQAGkMAAAIAFMAawwAAAgAPABqDAAACABHAGwMAAAHAEYAbQwAAAYAPgDqDAAACABEAG4MAAAFADUAbwwAAAQAGAATAAgJ/RaZEAAZAghoDAAABABQAGkMAAAEAFMAawwAAAQAPABsDAAAAQAlAG0MAAAEAD4A6gwAAAQARABuDAAABQA1AG8MAAADABcAHwAICXYS9BIAswEIaAwAAAMAKABpDAAABAA9AGsMAAAEADoAagwAAAgARwBsDAAABgBGAG0MAAACACsA6gwAAAQAIABvDAAAAQAYAAAA.',
Sa='Sanctified:BAAALgAECgYJDAAAAA==.Saphíra:BAEALgAECgQJCAAAAA==.Satanick:BAAALgADCgEJAQABLgAFFAMJCAAQAMocAA==.Satanickk:BAAALgAECgEJAQABLgAFFAMJCAAQAMocAA==.',
Se='Seraph:BAABLgAECn8kAAIUAAkJqBJ4GQC3AQloDAAABgAuAGkMAAAGAD4AawwAAAYAOwBqDAAABQA4AGwMAAAFAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAbwwAAAEAOgAUAAkJqBJ4GQC3AQloDAAABgAuAGkMAAAGAD4AawwAAAYAOwBqDAAABQA4AGwMAAAFAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAbwwAAAEAOgAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgYJBgAAAA==.',
Sn='Snikit:BAAALgAECgEJAQABLgAECgkJIAAJAMIbAA==.',
So='Sojourner:BAABLgAECn8XAAMDAAYJAxFaMQBCAQZoDAAAAwAUAGkMAAAGADUAawwAAAcARQBqDAAAAQAWAGwMAAABABMA6gwAAAUATAADAAYJAxFaMQBCAQZoDAAAAgAUAGkMAAAEADUAawwAAAQARQBqDAAAAQAWAGwMAAABABMA6gwAAAQATAACAAQJzAtHsgDPAARoDAAAAQAnAGkMAAACAB0AawwAAAMAIADqDAAAAQASAAAA.',
Sp='Spoonzilla:BAABLgAECn8VAAIbAAYJ9QfRQwCoAAZoDAAABAAXAGkMAAAFABoAawwAAAQAGABqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAbAAYJ9QfRQwCoAAZoDAAABAAXAGkMAAAFABoAawwAAAQAGABqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIcAAgJ+R6hGgC0AghoDAAABQBfAGkMAAAFAE8AawwAAAUASgBqDAAABABeAGwMAAADADoAbQwAAAQAUADqDAAABgBgAG4MAAAEAEQAHAAICfkeoRoAtAIIaAwAAAUAXwBpDAAABQBPAGsMAAAFAEoAagwAAAQAXgBsDAAAAwA6AG0MAAAEAFAA6gwAAAYAYABuDAAABABEAAEuAAQKCQkRAAoAAAAA.',
Su='Supersham:BAAALgAECgEJAQAAAA==.Superspam:BAABLgAECn8gAAMdAAgJSh/kLAD7AQhoDAAABQBgAGkMAAAEAEkAawwAAAUARwBqDAAABABPAGwMAAAEAEwAbQwAAAMASgDqDAAABABTAG4MAAADAFQAHQAICUof5CwA+wEIaAwAAAQAYABpDAAAAgBJAGsMAAADAEcAagwAAAIATwBsDAAAAgBMAG0MAAACAEoA6gwAAAQAUwBuDAAAAgBUABsABwlYEmMoADMBB2gMAAABACgAaQwAAAIAJwBrDAAAAgBJAGoMAAACADMAbAwAAAIALQBtDAAAAQAdAG4MAAABADQAAAA=.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn80AAIYAAkJDiDAAQBkAgloDAAACABfAGkMAAAIAF4AawwAAAgAXQBqDAAABwBWAGwMAAAHAE4AbQwAAAQARgDqDAAABgBZAG4MAAADAEcAbwwAAAEAPgAYAAkJDiDAAQBkAgloDAAACABfAGkMAAAIAF4AawwAAAgAXQBqDAAABwBWAGwMAAAHAE4AbQwAAAQARgDqDAAABgBZAG4MAAADAEcAbwwAAAEAPgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8kAAIdAAgJhA58PABbAQhoDAAABgAYAGkMAAAGAB4AawwAAAYAMABqDAAABQAmAGwMAAAFADsAbQwAAAEABgDqDAAABgA6AG4MAAABAB4AHQAICYQOfDwAWwEIaAwAAAYAGABpDAAABgAeAGsMAAAGADAAagwAAAUAJgBsDAAABQA7AG0MAAABAAYA6gwAAAYAOgBuDAAAAQAeAAAA.Thrasherzs:BAAALgAECgEJAwAAAA==.Thy:BAAALgADCgMJAgAAAA==.',
Ti='Tinyvoid:BAABLgAECn8gAAIcAAgJlxhZMwCwAQhoDAAABQBSAGkMAAAFADcAawwAAAUATgBqDAAAAwA7AGwMAAADAEsAbQwAAAEAEwDqDAAABwBVAG4MAAADACsAHAAICZcYWTMAsAEIaAwAAAUAUgBpDAAABQA3AGsMAAAFAE4AagwAAAMAOwBsDAAAAwBLAG0MAAABABMA6gwAAAcAVQBuDAAAAwArAAAA.',
To='Togdumburz:BAACLgAFFH8KAAIgAAMJuhV5SwDpAANoDAAABAAuAGkMAAACAEAA6gwAAAQANgAgAAMJuhV5SwDpAANoDAAABAAuAGkMAAACAEAA6gwAAAQANgAuAAQKfyUAAyAACQkhGh4YAFwCACAACQkhGh4YAFwCAA0AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8VAAIaAAUJ3CHvAgD5AQVoDAAABgBhAGkMAAAFAF4AawwAAAQAXwBsDAAAAQAyAOoMAAAFAGAAGgAFCdwh7wIA+QEFaAwAAAYAYQBpDAAABQBeAGsMAAAEAF8AbAwAAAEAMgDqDAAABQBgAC4ABAp/HAAEGgAICeQh5AkA6wIAGgAICc8h5AkA6wIAFgACCckUKlwAoAAAFQACCZ0PW1oAZQAAAAA=.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECggJGwAhAIASAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAABLgAECn8ZAAMJAAgJlSJOBwBKAghoDAAABABdAGkMAAAEAF4AawwAAAUAYwBqDAAAAwBhAGwMAAADAFYAbQwAAAIAVADqDAAAAwBhAG4MAAABAEAACQAHCR8kTgcASgIHaAwAAAQAXQBpDAAABABeAGsMAAAEAGMAagwAAAIAYQBsDAAAAgBWAG0MAAABAFQA6gwAAAIAYQAiAAYJExuRGgAtAQZrDAAAAQBVAGoMAAABABMAbAwAAAEALQBtDAAAAQBIAOoMAAABAE4AbgwAAAEAQAABLgAFFAUJFQAaANwhAA==.',
Vi='Vietsham:BAABLgAECn8kAAIOAAgJehANPgBWAQhoDAAABgA/AGkMAAAGAEsAawwAAAcAHwBqDAAAAwAyAGwMAAAEAB8AbQwAAAEAFgDqDAAABgArAG4MAAADABEADgAICXoQDT4AVgEIaAwAAAYAPwBpDAAABgBLAGsMAAAHAB8AagwAAAMAMgBsDAAABAAfAG0MAAABABYA6gwAAAYAKwBuDAAAAwARAAAA.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8PAAIEAAYJ3RbfCgBIAQZoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AGwMAAABACQA6gwAAAYAVQAEAAYJ3RbfCgBIAQZoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AGwMAAABACQA6gwAAAYAVQAuAAQKfyEAAgQACAmNHIIJAPMBAAQACAmNHIIJAPMBAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJGgAdAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgADCgcJDgAKAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn84AAMUAAkJvyDkAwAUAwloDAAABgBdAGkMAAAHAGEAawwAAAcAYwBqDAAABwBRAGwMAAAGAFsAbQwAAAYAWADqDAAACABPAG4MAAAFADMAbwwAAAQARwAUAAkJvyDkAwAUAwloDAAABQBdAGkMAAAGAGEAawwAAAcAYwBqDAAABgBRAGwMAAAFAFsAbQwAAAUAWADqDAAABwBPAG4MAAAFADMAbwwAAAQARwALAAYJshFBIgBfAQZoDAAAAQA/AGkMAAABACcAagwAAAEAKQBsDAAAAQAmAG0MAAABADYA6gwAAAEAIwAAAA==.',
Ye='Yetlian:BAACLgAFFH8NAAIDAAUJ6R1WCwCcAQVoDAAABABRAGkMAAACADwAawwAAAEAWgBsDAAAAQA2AOoMAAAFAF4AAwAFCekdVgsAnAEFaAwAAAQAUQBpDAAAAgA8AGsMAAABAFoAbAwAAAEANgDqDAAABQBeAC4ABAp/IAADAwAICXEkfwYA5wIAAwAICXEkfwYA5wIAAgABCQABKVsBEwAAAAA=.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8fAAIiAAYJnyVRAQAdAgZoDAAABwBgAGkMAAAHAGQAawwAAAQAYgBqDAAABABdAGwMAAADAFcA6gwAAAYAYwAiAAYJnyVRAQAdAgZoDAAABwBgAGkMAAAHAGQAawwAAAQAYgBqDAAABABdAGwMAAADAFcA6gwAAAYAYwAuAAQKfyAAAiIACAmrIWUCAAADACIACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgQJBQAAAA==.',
Zy='Zyrahh:BAAALgADCgYJBgAAAA==.',
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
