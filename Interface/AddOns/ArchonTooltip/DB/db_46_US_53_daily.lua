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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Warrior-Protection','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','Monk-Mistweaver','Mage-Arcane','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='daily',zone=46,date='2026-06-06',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAQ==.',
An='Anasazi:BAAALgAECgMJBwAAAA==.Andrémarkis:BAAALgAECgQJBgABLgAFFAcJIAABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRNdIABGAQdoDAAABQAfAGkMAAAFADYAawwAAAUAIABqDAAABABRAGwMAAACAE8AbQwAAAEAMwDqDAAABwAyAAIABwmZE10gAEYBB2gMAAAFAB8AaQwAAAUANgBrDAAABQAgAGoMAAAEAFEAbAwAAAIATwBtDAAAAQAzAOoMAAAHADIAAAA=.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Barehunt:BAAALgADCgkJCQABLgAFFAIJAgADAAAAAA==.',
Be='Bedorea:BAABLgAECn81AAMEAAkJQBrHDwB0AgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACQBTAG4MAAADAE4AbwwAAAEAOAAEAAkJQBrHDwB0AgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACABTAG4MAAADAE4AbwwAAAEAOAAFAAEJ0Aa5RQAtAAHqDAAAAQARAAAA.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAABLgAFFH8HAAMGAAQJZRJmFgDXAARoDAAAAgAyAGkMAAACADEAawwAAAIATQDqDAAAAQAKAAYAAwkbF2YWANcAA2gMAAABADIAaQwAAAEAMQBrDAAAAgBNAAUAAwmqDO4kAMQAA2gMAAABACoAaQwAAAEAKwDqDAAAAQAKAAAA.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIAABAMQTAQ==.Bloodweiser:BAAALgAECgYJEQAAAA==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAFFAIJAgADAAAAAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIHAAgJyRioEADNAQhoDAAABAA6AGkMAAAEAEgAawwAAAMAMwBqDAAAAwBSAGwMAAAFAEkAbQwAAAEASADqDAAAAwA/AG4MAAABADMABwAICckYqBAAzQEIaAwAAAQAOgBpDAAABABIAGsMAAADADMAagwAAAMAUgBsDAAABQBJAG0MAAABAEgA6gwAAAMAPwBuDAAAAQAzAAAA.Bumwitboba:BAABLgAECn8dAAQIAAYJdB87GAAaAgZoDAAABQBNAGkMAAAFAEQAawwAAAUAWwBqDAAABABTAGwMAAADAF0A6gwAAAcARQAIAAYJdB87GAAaAgZoDAAABABNAGkMAAAEAEQAawwAAAMAWwBqDAAABABTAGwMAAADAF0A6gwAAAYARQAJAAQJeg2aWACGAARoDAAAAQAQAGkMAAABABQAawwAAAEAKADqDAAAAQA9AAoAAQlzEOV6ADgAAWsMAAABACoAAAA=.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8cAAILAAcJ3AZYmADjAAdoDAAABQAMAGkMAAAEAA8AawwAAAUADwBqDAAABAAdAGwMAAACABUAbQwAAAEAFADqDAAABwATAAsABwncBliYAOMAB2gMAAAFAAwAaQwAAAQADwBrDAAABQAPAGoMAAAEAB0AbAwAAAIAFQBtDAAAAQAUAOoMAAAHABMAAAA=.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgMJAwAAAA==.Chironex:BAABLgAFFH8HAAIMAAUJnxOvIQBNAQVoDAAAAgBLAGkMAAABABAAawwAAAEAOABqDAAAAQA5AOoMAAACACwADAAFCZ8TryEATQEFaAwAAAIASwBpDAAAAQAQAGsMAAABADgAagwAAAEAOQDqDAAAAgAsAAAA.',
Co='Cofee:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.',
Da='Daelnei:BAABLgAECn8nAAIEAAcJeRD7NwBfAQdoDAAACAAuAGkMAAAHACIAawwAAAYAGABqDAAABQA4AGwMAAAFACoA6gwAAAcAOQBuDAAAAQAuAAQABwl5EPs3AF8BB2gMAAAIAC4AaQwAAAcAIgBrDAAABgAYAGoMAAAFADgAbAwAAAUAKgDqDAAABwA5AG4MAAABAC4AAAA=.Damja:BAABLgAECn8UAAIEAAYJwQcvZQC5AAZoDAAABAASAGkMAAAEABYAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAEAAYJwQcvZQC5AAZoDAAABAASAGkMAAAEABYAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAAAA==.Darkloky:BAABLgAECn85AAINAAgJxg3kOABEAQhoDAAACgAjAGkMAAAJACcAawwAAAkALgBqDAAABwA3AGwMAAAHACoAbQwAAAIADwDqDAAACQAXAG4MAAAEACsADQAICcYN5DgARAEIaAwAAAoAIwBpDAAACQAnAGsMAAAJAC4AagwAAAcANwBsDAAABwAqAG0MAAACAA8A6gwAAAkAFwBuDAAABAArAAAA.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIOAAcJtQznHgARAQdoDAAAAwA7AGkMAAADACMAawwAAAMAFQBqDAAAAwA0AGwMAAACAB4AbQwAAAEABADqDAAABQArAA4ABwm1DOceABEBB2gMAAADADsAaQwAAAMAIwBrDAAAAwAVAGoMAAADADQAbAwAAAIAHgBtDAAAAQAEAOoMAAAFACsAAAA=.',
De='Debby:BAABLgAECn8fAAIMAAgJzRTnMQDeAQhoDAAABgAtAGkMAAAFACoAawwAAAUAOgBqDAAABAA3AGwMAAADAEMAbQwAAAEALQDqDAAABgA3AG4MAAABADgADAAICc0U5zEA3gEIaAwAAAYALQBpDAAABQAqAGsMAAAFADoAagwAAAQANwBsDAAAAwBDAG0MAAABAC0A6gwAAAYANwBuDAAAAQA4AAAA.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECgYJDAAAAA==.',
Do='Donane:BAABLgAECn8bAAIPAAgJ1xSAIwDeAQhoDAAAAwAvAGkMAAAEAC8AawwAAAUARABqDAAAAwAgAGwMAAAEAEwAbQwAAAMAOADqDAAAAwA/AG4MAAACACIADwAICdcUgCMA3gEIaAwAAAMALwBpDAAABAAvAGsMAAAFAEQAagwAAAMAIABsDAAABABMAG0MAAADADgA6gwAAAMAPwBuDAAAAgAiAAAA.',
Dr='Drimbo:BAABLgAECn8XAAMQAAcJLwKuawCJAAdoDAAABAAEAGkMAAAEAAYAawwAAAQABABqDAAAAwALAGwMAAABAAcAbQwAAAEABgDqDAAABgAFABAABwkvAq5rAIkAB2gMAAAEAAQAaQwAAAQABgBrDAAAAwAEAGoMAAADAAsAbAwAAAEABwBtDAAAAQAGAOoMAAAGAAUAEQABCeUA7E8AFQABawwAAAEAAgAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECggJEwADAAAAAA==.',
Ec='Echoes:BAABLgAECn8nAAISAAgJ+B4EDQB9AghoDAAACABeAGkMAAAHAFsAawwAAAcAWwBqDAAABgBbAGwMAAADAEsAbQwAAAEAQQDqDAAABgBgAG4MAAABACgAEgAICfgeBA0AfQIIaAwAAAgAXgBpDAAABwBbAGsMAAAHAFsAagwAAAYAWwBsDAAAAwBLAG0MAAABAEEA6gwAAAYAYABuDAAAAQAoAAAA.Ectomage:BAAALgAECgEJAQAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAIKAAgJCxaLIAC5AQhoDAAABgBKAGkMAAAGADsAawwAAAYAOwBqDAAABQAuAGwMAAADADwAbQwAAAEAKwDqDAAAAwA2AG4MAAABACoACgAICQsWiyAAuQEIaAwAAAYASgBpDAAABgA7AGsMAAAGADsAagwAAAUALgBsDAAAAwA8AG0MAAABACsA6gwAAAMANgBuDAAAAQAqAAAA.',
Fl='Floraa:BAAALgAECgQJBQAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMTAAYJExkENAAnAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAJAD4AbgwAAAEAKwATAAYJExkENAAnAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAIAD4AbgwAAAEAKwAUAAEJvgGziwAgAAHqDAAAAQAEAAEuAAUUAgkCAAMAAAAA.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.Hornstar:BAAALgAECgEJAQAAAA==.',
Ik='Ikarro:BAAALgAFFAEJAgAAAA==.',
Il='Illidave:BAABLgAECn8UAAMVAAgJgAYmMgDmAAhoDAAAAwATAGkMAAADABIAawwAAAMADQBqDAAAAwAOAGwMAAADAA8AbQwAAAEACgDqDAAAAwAcAG4MAAABAAkAFQAICckFJjIA5gAIaAwAAAMAEwBpDAAAAwASAGsMAAADAA0AagwAAAMADgBsDAAAAwAPAG0MAAABAAoA6gwAAAIADwBuDAAAAQAJABYAAQkoC402ACEAAeoMAAABABwAAAA=.',
In='Insindia:BAAALgAECggJEgAAAA==.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ+EmQAFAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgABAAYJjQ+EmQAFAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8oAAMMAAkJqwmjVQBPAQloDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAABgBaAGwMAAAFAA0AbQwAAAIABgDqDAAABgATAG4MAAAFAAoAbwwAAAEAMAAMAAgJggijVQBPAQhoDAAAAgAOAGkMAAACAAsAawwAAAIABwBqDAAAAwBaAGwMAAACAA0AbQwAAAIABgDqDAAABAATAG4MAAAEAAoADQAICUIHpUYACQEIaAwAAAMAGQBpDAAAAwAUAGsMAAADABIAagwAAAMAHQBsDAAAAwATAOoMAAACAAgAbgwAAAEAEQBvDAAAAQATAAAA.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMPAAcJcRI5OgBVAQdoDAAABwBGAGkMAAAGAC8AawwAAAgAHwBqDAAABAAiAGwMAAAFACsA6gwAAAQATwBuDAAAAQAXAA8ABgn6Ezk6AFUBBmgMAAAEAEYAaQwAAAMALwBrDAAABAAfAGoMAAADACIAbAwAAAIAKwDqDAAAAgBPABcABwm3EI6XADkBB2gMAAADAFoAaQwAAAMAKgBrDAAABAAoAGoMAAABABYAbAwAAAMALQDqDAAAAgAYAG4MAAABAAwAAAA=.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAECgYJBgABLgAFFAcJIAABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAFFAIJAgADAAAAAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8gAAMBAAcJxBOaGwDBAQdoDAAABwBSAGkMAAAGAEQAawwAAAUAMwBqDAAABAAiAGwMAAABABIAbQwAAAEACgDqDAAACABIAAEABwmNE5obAMEBB2gMAAAHAFIAaQwAAAEAQABrDAAABAAzAGoMAAAEACIAbAwAAAEAEgBtDAAAAQAKAOoMAAAIAEgAGAACCcoPXQ0AogACaQwAAAUARABrDAAAAQAMAC4ABAp/MwAEAQAICb4keBsAsAIAAQAICRYjeBsAsAIAGAAFCckiUwwA/QEAGQAECXgeFBgAugAAAAA=.Magewings:BAABLgAECn8WAAIaAAYJkwyawAADAQZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAaAAYJkwyawAADAQZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn9BAAIbAAkJvxwIGACKAgloDAAACABSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAIAFIAbQwAAAcAVADqDAAACgBNAG4MAAAGADEAbwwAAAIANgAbAAkJvxwIGACKAgloDAAACABSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAIAFIAbQwAAAcAVADqDAAACgBNAG4MAAAGADEAbwwAAAIANgAAAA==.',
Mi='Mikayla:BAAALgAECgYJCAAAAA==.Miranda:BAAALgAFFAQJBwABLgAFFAcJIAABAMQTAQ==.Misobeastie:BAAALgAECgYJCwAAAA==.Mixup:BAACLgAFFH8RAAIBAAUJ3RXXQQA3AQVoDAAABAAoAGkMAAAEAE0AawwAAAMAJgBqDAAAAgA5AOoMAAAEAEMAAQAFCd0V10EANwEFaAwAAAQAKABpDAAABABNAGsMAAADACYAagwAAAIAOQDqDAAABABDAC4ABAp/SwACAQAJCXIgLg4A1QIAAQAJCXIgLg4A1QIAAAA=.',
Mo='Mollan:BAAALgAECgcJDAAAAA==.Monkeys:BAAALgAFFAEJAQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxlyDgAXAgloDAAACQBRAGkMAAAJAFIAawwAAAkAPwBqDAAACABQAGwMAAAIAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAACAAkJtxlyDgAXAgloDAAACABRAGkMAAAIAFIAawwAAAgAPwBqDAAABwBQAGwMAAAHAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAAcAAUJkgph3ADNAAVoDAAAAQAdAGkMAAABAB0AawwAAAEAIwBqDAAAAQAUAGwMAAABAAwAAAA=.Mythikal:BAABLgAECn8XAAIcAAcJuA1ligBHAQdoDAAAAwAtAGkMAAADACMAawwAAAMAHwBqDAAAAwAlAGwMAAAEACgAbQwAAAEAFwDqDAAABgAiABwABwm4DWWKAEcBB2gMAAADAC0AaQwAAAMAIwBrDAAAAwAfAGoMAAADACUAbAwAAAQAKABtDAAAAQAXAOoMAAAGACIAAAA=.',
Na='Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAADAAAAAA==.',
No='Notthefather:BAAALgAECgYJBwAAAA==.',
Ot='Otekah:BAABLgAECn8eAAMPAAcJsBc9IgDnAQdoDAAABQA5AGkMAAAFAFMAawwAAAUAVABqDAAABABSAGwMAAACABsAbQwAAAIAMgDqDAAABwAmAA8ABwmwFz0iAOcBB2gMAAADADkAaQwAAAQAUwBrDAAABABUAGoMAAADAFIAbAwAAAIAGwBtDAAAAgAyAOoMAAAGACYAFwAFCfwIZBoBiQAFaAwAAAIALABpDAAAAQAVAGsMAAABABAAagwAAAEAFgDqDAAAAQAJAAAA.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8eAAIVAAgJMw6eIQBYAQhoDAAABAAeAGkMAAAFACYAawwAAAUALQBqDAAABAAnAGwMAAACACsAbQwAAAIAGADqDAAABwAoAG4MAAABACAAFQAICTMOniEAWAEIaAwAAAQAHgBpDAAABQAmAGsMAAAFAC0AagwAAAQAJwBsDAAAAgArAG0MAAACABgA6gwAAAcAKABuDAAAAQAgAAAA.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIcAAkJNQwoXgClAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgAcAAkJNQwoXgClAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQdAAcJfhLJOwBoAQdoDAAABQA/AGkMAAAFAEoAawwAAAUARgBqDAAABAA7AGwMAAACAAkAbQwAAAIADQDqDAAABwApAB0ABgm3FMk7AGgBBmgMAAADAD8AaQwAAAMASgBrDAAAAwBGAGoMAAADADsAbAwAAAEACQDqDAAAAwApABMABwnKDEw1ACEBB2gMAAABABgAaQwAAAEADgBrDAAAAQAnAGoMAAABACgAbAwAAAEAGwBtDAAAAQAaAOoMAAADAEAAFAAECXMJEHsAUQAEaAwAAAEAGABpDAAAAQAYAGsMAAABABMA6gwAAAEAGwAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAaAGMPAA==.',
Ro='Roadhouse:BAAALgADCgkJEwAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAAALgAECggJEwAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQADAAAAAA==.Sandaexpress:BAAALgAFFAIJAgAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIcAAQJYBNvXAAvAQRoDAAAAgA1AGkMAAACADQAawwAAAEACQDqDAAAAgBTABwABAlgE29cAC8BBGgMAAACADUAaQwAAAIANABrDAAAAQAJAOoMAAACAFMAAAA=.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAIJAgADAAAAAA==.Shme:BAACLgAFFH8QAAIaAAQJ8gsWHgBSAQRoDAAABgAsAGkMAAAFACAAawwAAAEAHgDqDAAABAAOABoABAnyCxYeAFIBBGgMAAAGACwAaQwAAAUAIABrDAAAAQAeAOoMAAAEAA4ALgAECn80AAMaAAgJ1R1RKwDFAgAaAAgJ1R1RKwDFAgAeAAEJihUGHQA4AAAAAA==.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAaAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAQJCwAXADMlAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAQJCwAXADMlAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQADAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8dAAQEAAgJLgxaSAAbAQhoDAAABQAyAGkMAAAFABEAawwAAAYAKgBqDAAAAgAoAGwMAAADABMA6gwAAAMAFgBuDAAABAAYAG8MAAABACgABAAHCSULWkgAGwEHaAwAAAMAMgBpDAAAAwARAGsMAAAEACoAagwAAAIAKABsDAAAAgATAOoMAAACABYAbgwAAAIAEgAGAAUJagawNQCUAAVoDAAAAgApAGkMAAACAAEAawwAAAIACwBsDAAAAQALAOoMAAABAA8ABQACCdQMZlUAbgACbgwAAAIAGABvDAAAAQAoAAAA.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8jAAIMAAcJVBh8LwDqAQdoDAAACgBFAGkMAAAIAE4AawwAAAcARwBqDAAABABMAGwMAAADAEUA6gwAAAIAPgBuDAAAAQAHAAwABwlUGHwvAOoBB2gMAAAKAEUAaQwAAAgATgBrDAAABwBHAGoMAAAEAEwAbAwAAAMARQDqDAAAAgA+AG4MAAABAAcAAAA=.',
Sy='Syllogica:BAACLgAFFH8XAAIfAAQJQBa+FgBKAQRoDAAABgBCAGkMAAAHADMAawwAAAMAMADqDAAABwA9AB8ABAlAFr4WAEoBBGgMAAAGAEIAaQwAAAcAMwBrDAAAAwAwAOoMAAAHAD0ALgAECn8WAAIfAAgJrBDYJgBPAQAfAAgJrBDYJgBPAQAAAA==.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9RAAIIAAkJkCTiAQCJAwloDAAACgBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAAKAGEAbQwAAAkAYQDqDAAACwBhAG4MAAAIAFMAbwwAAAMAVQAIAAkJkCTiAQCJAwloDAAACgBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAAKAGEAbQwAAAkAYQDqDAAACwBhAG4MAAAIAFMAbwwAAAMAVQAAAA==.',
Te='Tenderloinz:BAAALgAECgUJEQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Toothandclaw:BAAALgADCgMJAwAAAA==.Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIPAAIJdhfZFwCGAAJoDAAABAAzAGkMAAADAEUADwACCXYX2RcAhgACaAwAAAQAMwBpDAAAAwBFAC4ABAp/KgACDwAICX8iswUAEAMADwAICX8iswUAEAMAAAA=.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJEQAAAA==.Vaughan:BAACLgAFFH8LAAIXAAQJMyWYEQC3AQRoDAAAAwBjAGkMAAADAGAAawwAAAIAVwDqDAAAAwBhABcABAkzJZgRALcBBGgMAAADAGMAaQwAAAMAYABrDAAAAgBXAOoMAAADAGEALgAECn8tAAIXAAkJpiTfCQAQAwAXAAkJpiTfCQAQAwAAAA==.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Vy='Vynathenin:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAABLgAECn87AAIBAAgJ/BnlOADxAQhoDAAACABMAGkMAAAIADMAawwAAAgAUQBqDAAABwAwAGwMAAAIAEoAbQwAAAYAPgDqDAAACQA+AG4MAAAFADkAAQAICfwZ5TgA8QEIaAwAAAgATABpDAAACAAzAGsMAAAIAFEAagwAAAcAMABsDAAACABKAG0MAAAGAD4A6gwAAAkAPgBuDAAABQA5AAAA.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whatacombo:BAAALgAECgUJBQABLgAFFAIJAgADAAAAAA==.Whollycow:BAAALgAECgUJCgABLgAFFAIJAgADAAAAAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAAALgAFFAIJAgAAAA==.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgYJCgAAAA==.Zaka:BAAALgADCgEJAQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
Zu='Zulander:BAAALgAECgQJCAAAAA==.',
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
