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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Priest-Shadow','DemonHunter-Devourer','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','Monk-Windwalker','Shaman-Restoration','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','Monk-Mistweaver','Mage-Arcane','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='daily',zone=46,date='2026-05-20',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAYJHgABAOMWAQ==.',
An='Anasazi:BAAALgAECgIJAgAAAA==.Andrémarkis:BAAALgAECgMJAwABLgAFFAYJHgABAOMWAQ==.',
Ar='Aranaya:BAAALgAECgUJCgAAAA==.',
As='Aspersio:BAABLgAECn8aAAICAAYJdRNXIAAUAQZoDAAABQAfAGkMAAAFADYAawwAAAUAIABqDAAABABRAGwMAAACAE8A6gwAAAUAMgACAAYJdRNXIAAUAQZoDAAABQAfAGkMAAAFADYAawwAAAUAIABqDAAABABRAGwMAAACAE8A6gwAAAUAMgAAAA==.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgADCgcJBwABLgAECgUJCQADAAAAAA==.Barehunt:BAAALgADCgcJBwABLgAECgUJCQADAAAAAA==.',
Be='Bedorea:BAABLgAECn8tAAMEAAgJdhgCFwAGAghoDAAACQBOAGkMAAAIAFAAawwAAAcAOABqDAAABQAyAGwMAAAFAD4AbQwAAAEABwDqDAAACQBTAG4MAAABAEUABAAICXYYAhcABgIIaAwAAAkATgBpDAAACABQAGsMAAAHADgAagwAAAUAMgBsDAAABQA+AG0MAAABAAcA6gwAAAgAUwBuDAAAAQBFAAUAAQnQBrlFAC0AAeoMAAABABEAAAA=.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Blessurheart:BAAALgAECgMJAwABLgAFFAYJHgABAOMWAQ==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAECgYJFwAGABMZAA==.Boxab:BAAALgAFFAEJAQABLgAFFAYJHgABAOMWAQ==.',
Bu='Buckchuck:BAAALgAECgcJEQAAAA==.Bumwitboba:BAABLgAECn8YAAQHAAYJdB87GAAaAgZoDAAABABNAGkMAAAEAEQAawwAAAQAWwBqDAAAAwBTAGwMAAACAF0A6gwAAAcARQAHAAYJdB87GAAaAgZoDAAABABNAGkMAAAEAEQAawwAAAMAWwBqDAAAAwBTAGwMAAACAF0A6gwAAAYARQAIAAEJ1RdFUQBHAAHqDAAAAQA9AAkAAQlzELhlADoAAWsMAAABACoAAAA=.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8ZAAIKAAYJkwZcmAC9AAZoDAAABQAMAGkMAAAEAA8AawwAAAUADwBqDAAABAAdAGwMAAACABUA6gwAAAUAEwAKAAYJkwZcmAC9AAZoDAAABQAMAGkMAAAEAA8AawwAAAUADwBqDAAABAAdAGwMAAACABUA6gwAAAUAEwAAAA==.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgIJAgAAAA==.Chironex:BAAALgAFFAIJAgAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAECgYJFwAGABMZAA==.',
Da='Daelnei:BAABLgAECn8gAAIEAAYJpAxzQwAEAQZoDAAABwAqAGkMAAAGABoAawwAAAUAGABqDAAABAA4AGwMAAAEAB4A6gwAAAYAJQAEAAYJpAxzQwAEAQZoDAAABwAqAGkMAAAGABoAawwAAAUAGABqDAAABAA4AGwMAAAEAB4A6gwAAAYAJQAAAA==.Damja:BAAALgAECgYJEgAAAA==.Darkloky:BAABLgAECn8kAAILAAgJEgjpPgD7AAhoDAAABwAjAGkMAAAGABsAawwAAAYAFABqDAAABQAdAGwMAAAEACIAbQwAAAEABQDqDAAABgARAG4MAAABAAQACwAICRII6T4A+wAIaAwAAAcAIwBpDAAABgAbAGsMAAAGABQAagwAAAUAHQBsDAAABAAiAG0MAAABAAUA6gwAAAYAEQBuDAAAAQAEAAAA.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIMAAcJtQznHgARAQdoDAAAAwA7AGkMAAADACMAawwAAAMAFQBqDAAAAwA0AGwMAAACAB4AbQwAAAEABADqDAAABQArAAwABwm1DOceABEBB2gMAAADADsAaQwAAAMAIwBrDAAAAwAVAGoMAAADADQAbAwAAAIAHgBtDAAAAQAEAOoMAAAFACsAAAA=.',
De='Debby:BAAALgAECgYJEgAAAA==.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECgYJDAAAAA==.',
Do='Donane:BAABLgAECn8VAAINAAgJhRAEJQCtAQhoDAAAAwAvAGkMAAAEAC8AawwAAAQALQBqDAAAAgAgAGwMAAADAEwAbQwAAAEACADqDAAAAwA/AG4MAAABAA8ADQAICYUQBCUArQEIaAwAAAMALwBpDAAABAAvAGsMAAAEAC0AagwAAAIAIABsDAAAAwBMAG0MAAABAAgA6gwAAAMAPwBuDAAAAQAPAAAA.',
Dr='Drimbo:BAABLgAECn8UAAMOAAYJEgJQYAB5AAZoDAAABAAEAGkMAAAEAAYAawwAAAQABABqDAAAAwALAGwMAAABAAcA6gwAAAQABAAOAAYJEgJQYAB5AAZoDAAABAAEAGkMAAAEAAYAawwAAAMABABqDAAAAwALAGwMAAABAAcA6gwAAAQABAAPAAEJ5QDsTwAVAAFrDAAAAQACAAAA.',
Du='Duareapa:BAAALgAECgYJDAAAAA==.',
Ec='Echoes:BAABLgAECn8gAAIQAAcJVh3BFQDsAQdoDAAABgBPAGkMAAAFAFYAawwAAAYAWgBqDAAABgBbAGwMAAACADkA6gwAAAYAYABuDAAAAQAoABAABwlWHcEVAOwBB2gMAAAGAE8AaQwAAAUAVgBrDAAABgBaAGoMAAAGAFsAbAwAAAIAOQDqDAAABgBgAG4MAAABACgAAAA=.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAIJAAgJDBb8GQDDAQhoDAAABgBKAGkMAAAGADsAawwAAAYAOwBqDAAABQAuAGwMAAADADwAbQwAAAEAKwDqDAAAAwA2AG4MAAABACoACQAICQwW/BkAwwEIaAwAAAYASgBpDAAABgA7AGsMAAAGADsAagwAAAUALgBsDAAAAwA8AG0MAAABACsA6gwAAAMANgBuDAAAAQAqAAAA.',
Fl='Floraa:BAAALgADCgEJAQAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMGAAYJExkQLQAtAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAJAD4AbgwAAAEAKwAGAAYJExkQLQAtAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAIAD4AbgwAAAEAKwARAAEJvgGziwAgAAHqDAAAAQAEAAAA.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAECgEJAQAAAA==.',
In='Insindia:BAAALgAECgYJCgAAAA==.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ8ghQAQAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgABAAYJjQ8ghQAQAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8mAAMSAAgJggjgRgBRAQhoDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAABgBaAGwMAAAFAA0AbQwAAAIABgDqDAAABgATAG4MAAAEAAoAEgAICYII4EYAUQEIaAwAAAIADgBpDAAAAgALAGsMAAACAAcAagwAAAMAWgBsDAAAAgANAG0MAAACAAYA6gwAAAQAEwBuDAAABAAKAAsABglNB2NPALsABmgMAAADABkAaQwAAAMAFABrDAAAAwASAGoMAAADAB0AbAwAAAMAEwDqDAAAAgAIAAAA.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8dAAMNAAcJcRKXMQBbAQdoDAAABgBGAGkMAAAFAC8AawwAAAYAHwBqDAAAAwAiAGwMAAAEACsA6gwAAAQATwBuDAAAAQAXAA0ABgn6E5cxAFsBBmgMAAAEAEYAaQwAAAMALwBrDAAABAAfAGoMAAADACIAbAwAAAIAKwDqDAAAAgBPABMABgmoDwymAAIBBmgMAAACAFoAaQwAAAIAKgBrDAAAAgAYAGwMAAACAC0A6gwAAAIAGABuDAAAAQAMAAAA.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kiril:BAAALgAECgIJAgAAAA==.Kitana:BAAALgAECgEJAQABLgAFFAYJHgABAOMWAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAECgYJFwAGABMZAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Maelle:BAACLgAFFH8eAAMBAAYJ4xZRGACOAQZoDAAABwBSAGkMAAAGAEQAawwAAAUAMwBqDAAABAAiAGwMAAABABIA6gwAAAcASAABAAYJoBZRGACOAQZoDAAABwBSAGkMAAABAEAAawwAAAQAMwBqDAAABAAiAGwMAAABABIA6gwAAAcASAAUAAIJyg9dDQCiAAJpDAAABQBEAGsMAAABAAwALgAECn8zAAQBAAgJviR4GwCwAgABAAgJFiN4GwCwAgAUAAUJySJTDAD9AQAVAAQJeB4UGAC6AAAAAA==.Magewings:BAABLgAECn8WAAIWAAYJkwyUpgAMAQZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAWAAYJkwyUpgAMAQZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Mastain:BAAALgAFFAIJAgAAAA==.',
Me='Mexcutioner:BAABLgAECn8rAAIXAAkJmBmiHQBUAgloDAAABgBSAGkMAAAGAE4AawwAAAUASgBqDAAABQBGAGwMAAAFAEsAbQwAAAQAMwDqDAAACABNAG4MAAADACoAbwwAAAEAKQAXAAkJmBmiHQBUAgloDAAABgBSAGkMAAAGAE4AawwAAAUASgBqDAAABQBGAGwMAAAFAEsAbQwAAAQAMwDqDAAACABNAG4MAAADACoAbwwAAAEAKQAAAA==.',
Mi='Mikayla:BAAALgAECgMJAwAAAA==.Miranda:BAAALgAFFAIJAwABLgAFFAYJHgABAOMWAQ==.Mixup:BAACLgAFFH8HAAIBAAQJ/QU+UADsAARoDAAAAgASAGkMAAACABYAawwAAAEAAwDqDAAAAgAQAAEABAn9BT5QAOwABGgMAAACABIAaQwAAAIAFgBrDAAAAQADAOoMAAACABAALgAECn9CAAIBAAkJfB7GDgC2AgABAAkJfB7GDgC2AgAAAA==.',
Mo='Mollan:BAAALgAECgMJBQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn81AAICAAkJtxl6CgAtAgloDAAACABRAGkMAAAIAFIAawwAAAgAPwBqDAAABwBQAGwMAAAHAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAACAAkJtxl6CgAtAgloDAAACABRAGkMAAAIAFIAawwAAAgAPwBqDAAABwBQAGwMAAAHAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAAAAA==.Mythikal:BAAALgAECgYJDQAAAA==.',
Na='Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAADAAAAAA==.',
Ot='Otekah:BAABLgAECn8aAAMNAAYJXhjOJACuAQZoDAAABQA5AGkMAAAFAFMAawwAAAUAVABqDAAABABSAGwMAAACABsA6gwAAAUAJgANAAYJXhjOJACuAQZoDAAAAwA5AGkMAAAEAFMAawwAAAQAVABqDAAAAwBSAGwMAAACABsA6gwAAAQAJgATAAUJ/AiB7wCTAAVoDAAAAgAsAGkMAAABABUAawwAAAEAEABqDAAAAQAWAOoMAAABAAkAAAA=.',
Pe='Peppanutz:BAAALgAECgUJBQAAAA==.',
Pi='Pinuno:BAAALgAECgYJEwAAAA==.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn80AAIYAAkJNQx2TAC0AQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAABwAbAG4MAAAEAAkAbwwAAAEAFgAYAAkJNQx2TAC0AQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAABwAbAG4MAAAEAAkAbwwAAAEAFgAAAA==.',
Pu='Puncho:BAABLgAECn8aAAQZAAYJtxSsLABoAQZoDAAABQA/AGkMAAAFAEoAawwAAAUARgBqDAAABAA7AGwMAAACAAkA6gwAAAUAKQAZAAYJtxSsLABoAQZoDAAAAwA/AGkMAAADAEoAawwAAAMARgBqDAAAAwA7AGwMAAABAAkA6gwAAAMAKQAGAAYJTA0UNwD7AAZoDAAAAQAYAGkMAAABAA4AawwAAAEAJwBqDAAAAQAoAGwMAAABABsA6gwAAAEAQAARAAQJcwk3ZQBXAARoDAAAAQAYAGkMAAABABgAawwAAAEAEwDqDAAAAQAbAAAA.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAWAGMPAA==.',
Ro='Roadhouse:BAAALgADCgkJCQAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAAALgAECgYJBgABLgAECgYJDAADAAAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQADAAAAAA==.Sandaexpress:BAAALgAECgQJBAABLgAECgUJCQADAAAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIYAAQJYBMCPgBFAQRoDAAAAgA1AGkMAAACADQAawwAAAEACQDqDAAAAgBTABgABAlgEwI+AEUBBGgMAAACADUAaQwAAAIANABrDAAAAQAJAOoMAAACAFMAAAA=.',
Sh='Shikaka:BAAALgAECgUJBQABLgAECgUJCQADAAAAAA==.Shme:BAACLgAFFH8QAAIWAAQJ8gsWHgBSAQRoDAAABgAsAGkMAAAFACAAawwAAAEAHgDqDAAABAAOABYABAnyCxYeAFIBBGgMAAAGACwAaQwAAAUAIABrDAAAAQAeAOoMAAAEAA4ALgAECn80AAMWAAgJ1R1RKwDFAgAWAAgJ1R1RKwDFAgAaAAEJihUGHQA4AAAAAA==.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAWAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJBwABLgAECgkJLAATAKUkAA==.Silex:BAAALgADCgIJAgAAAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQADAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAAALgAECgcJEwAAAA==.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8dAAISAAYJmhW1QgBiAQZoDAAACQBFAGkMAAAHAD4AawwAAAYAPABqDAAAAwAuAGwMAAACAB4A6gwAAAIAPgASAAYJmhW1QgBiAQZoDAAACQBFAGkMAAAHAD4AawwAAAYAPABqDAAAAwAuAGwMAAACAB4A6gwAAAIAPgAAAA==.',
Sy='Syllogica:BAACLgAFFH8GAAIbAAMJoRI3GwDyAANoDAAAAgA3AGkMAAABADMA6gwAAAMAIwAbAAMJoRI3GwDyAANoDAAAAgA3AGkMAAABADMA6gwAAAMAIwAuAAQKfxYAAhsACAmsEB4fAGYBABsACAmsEB4fAGYBAAAA.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn86AAIHAAkJGiTaAQB0AwloDAAACABZAGkMAAAIAGAAawwAAAcAYQBqDAAABwBgAGwMAAAHAFwAbQwAAAYAXADqDAAACABhAG4MAAAFAFMAbwwAAAIAVQAHAAkJGiTaAQB0AwloDAAACABZAGkMAAAIAGAAawwAAAcAYQBqDAAABwBgAGwMAAAHAFwAbQwAAAYAXADqDAAACABhAG4MAAAFAFMAbwwAAAIAVQAAAA==.',
Te='Tenderloinz:BAAALgAECgUJDwAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAINAAIJdhfZFwCGAAJoDAAABAAzAGkMAAADAEUADQACCXYX2RcAhgACaAwAAAQAMwBpDAAAAwBFAC4ABAp/KgACDQAICX8iswUAEAMADQAICX8iswUAEAMAAAA=.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgADCgQJCAAAAA==.Vannahelzing:BAAALgAECggJDAAAAA==.Vaughan:BAABLgAECn8sAAITAAkJpSS9BQApAwloDAAABwBhAGkMAAAHAGMAawwAAAYAYgBqDAAABQBcAGwMAAAGAFsAbQwAAAIAUwDqDAAABQBfAG4MAAAFAFUAbwwAAAEAYwATAAkJpSS9BQApAwloDAAABwBhAGkMAAAHAGMAawwAAAYAYgBqDAAABQBcAGwMAAAGAFsAbQwAAAIAUwDqDAAABQBfAG4MAAAFAFUAbwwAAAEAYwAAAA==.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Wa='Waffle:BAABLgAECn84AAIBAAgJSxjLNADiAQhoDAAACABMAGkMAAAIADMAawwAAAgAUQBqDAAABwAwAGwMAAAHAEoAbQwAAAUAJgDqDAAACAA4AG4MAAAFADkAAQAICUsYyzQA4gEIaAwAAAgATABpDAAACAAzAGsMAAAIAFEAagwAAAcAMABsDAAABwBKAG0MAAAFACYA6gwAAAgAOABuDAAABQA5AAAA.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whollycow:BAAALgAECgUJCQAAAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAAALgAECgUJBQABLgAECgYJFwAGABMZAA==.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgYJCgAAAA==.Zaka:BAAALgADCgEJAQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
Zu='Zulander:BAAALgAECgIJAwAAAA==.',
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
