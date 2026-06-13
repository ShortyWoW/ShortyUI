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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','Monk-Mistweaver','Mage-Arcane','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='daily',zone=46,date='2026-06-12',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAQ==.',
An='Anasazi:BAAALgAECgYJCgAAAA==.Andrémarkis:BAAALgAECgQJBwABLgAFFAcJIAABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRO0IQBBAQdoDAAABQAfAGkMAAAFADYAawwAAAUAIABqDAAABABRAGwMAAACAE8AbQwAAAEAMwDqDAAABwAyAAIABwmZE7QhAEEBB2gMAAAFAB8AaQwAAAUANgBrDAAABQAgAGoMAAAEAFEAbAwAAAIATwBtDAAAAQAzAOoMAAAHADIAAAA=.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAFFAEJAQABLgAFFAMJBAADAAAAAA==.Barehunt:BAAALgADCgkJCQABLgAFFAMJBAADAAAAAA==.',
Be='Bedorea:BAABLgAECn81AAMEAAkJQBqyEABvAgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACQBTAG4MAAADAE4AbwwAAAEAOAAEAAkJQBqyEABvAgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACABTAG4MAAADAE4AbwwAAAEAOAAFAAEJ0Aa5RQAtAAHqDAAAAQARAAAA.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAABLgAFFH8IAAMGAAQJGROWGADOAARoDAAAAgAyAGkMAAACADEAawwAAAIATQDqDAAAAgASAAYAAwkbF5YYAM4AA2gMAAABADIAaQwAAAEAMQBrDAAAAgBNAAUAAwmbDVEnAMgAA2gMAAABACoAaQwAAAEAKwDqDAAAAgASAAAA.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIAABAMQTAQ==.Bloodweiser:BAABLgAECn8WAAMHAAYJSBLLOAAWAQZoDAAABAAuAGkMAAAFAC4AawwAAAUALgBqDAAABAA/AGwMAAADADUA6gwAAAEAKQAHAAYJSBLLOAAWAQZoDAAABAAuAGkMAAAEAC4AawwAAAQALgBqDAAABAA/AGwMAAADADUA6gwAAAEAKQAIAAIJqAUtjgA/AAJpDAAAAQAOAGsMAAABAA4AAAA=.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAFFAUJBwAJAGQUAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIKAAgJyRimEQDMAQhoDAAABAA6AGkMAAAEAEgAawwAAAMAMwBqDAAAAwBSAGwMAAAFAEkAbQwAAAEASADqDAAAAwA/AG4MAAABADMACgAICckYphEAzAEIaAwAAAQAOgBpDAAABABIAGsMAAADADMAagwAAAMAUgBsDAAABQBJAG0MAAABAEgA6gwAAAMAPwBuDAAAAQAzAAAA.Bumwitboba:BAABLgAECn8dAAQLAAYJdB87GAAaAgZoDAAABQBNAGkMAAAFAEQAawwAAAUAWwBqDAAABABTAGwMAAADAF0A6gwAAAcARQALAAYJdB87GAAaAgZoDAAABABNAGkMAAAEAEQAawwAAAMAWwBqDAAABABTAGwMAAADAF0A6gwAAAYARQAMAAQJeg2pXACEAARoDAAAAQAQAGkMAAABABQAawwAAAEAKADqDAAAAQA9AA0AAQlzEFJ/ADgAAWsMAAABACoAAAA=.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8cAAIJAAcJ3AbtnADjAAdoDAAABQAMAGkMAAAEAA8AawwAAAUADwBqDAAABAAdAGwMAAACABUAbQwAAAEAFADqDAAABwATAAkABwncBu2cAOMAB2gMAAAFAAwAaQwAAAQADwBrDAAABQAPAGoMAAAEAB0AbAwAAAIAFQBtDAAAAQAUAOoMAAAHABMAAAA=.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgQJBgAAAA==.Chironex:BAABLgAFFH8IAAIOAAUJnxNkJQBJAQVoDAAAAgBLAGkMAAABABAAawwAAAEAOABqDAAAAQA5AOoMAAADACwADgAFCZ8TZCUASQEFaAwAAAIASwBpDAAAAQAQAGsMAAABADgAagwAAAEAOQDqDAAAAwAsAAAA.Chuleta:BAAALgAECgQJBQAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAFFAUJBwAJAGQUAA==.',
Da='Daelnei:BAABLgAECn8rAAIEAAcJIRGHOABjAQdoDAAACQA4AGkMAAAIACIAawwAAAcAGABqDAAABQA4AGwMAAAFACoA6gwAAAgAOQBuDAAAAQAuAAQABwkhEYc4AGMBB2gMAAAJADgAaQwAAAgAIgBrDAAABwAYAGoMAAAFADgAbAwAAAUAKgDqDAAACAA5AG4MAAABAC4AAAA=.Damja:BAABLgAECn8UAAIEAAYJwQe0aAC5AAZoDAAABAASAGkMAAAEABYAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAEAAYJwQe0aAC5AAZoDAAABAASAGkMAAAEABYAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAAAA==.Darkloky:BAABLgAECn85AAIPAAgJxg0sOwBEAQhoDAAACgAjAGkMAAAJACcAawwAAAkALgBqDAAABwA3AGwMAAAHACoAbQwAAAIADwDqDAAACQAXAG4MAAAEACsADwAICcYNLDsARAEIaAwAAAoAIwBpDAAACQAnAGsMAAAJAC4AagwAAAcANwBsDAAABwAqAG0MAAACAA8A6gwAAAkAFwBuDAAABAArAAAA.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIQAAcJtQznHgARAQdoDAAAAwA7AGkMAAADACMAawwAAAMAFQBqDAAAAwA0AGwMAAACAB4AbQwAAAEABADqDAAABQArABAABwm1DOceABEBB2gMAAADADsAaQwAAAMAIwBrDAAAAwAVAGoMAAADADQAbAwAAAIAHgBtDAAAAQAEAOoMAAAFACsAAAA=.',
De='Debby:BAABLgAECn8gAAIOAAgJzRTPMwDeAQhoDAAABgAtAGkMAAAFACoAawwAAAUAOgBqDAAABAA3AGwMAAADAEMAbQwAAAEALQDqDAAABwA3AG4MAAABADgADgAICc0UzzMA3gEIaAwAAAYALQBpDAAABQAqAGsMAAAFADoAagwAAAQANwBsDAAAAwBDAG0MAAABAC0A6gwAAAcANwBuDAAAAQA4AAAA.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECggJDwAAAA==.',
Do='Donane:BAABLgAECn8bAAIRAAgJ1xSZJADdAQhoDAAAAwAvAGkMAAAEAC8AawwAAAUARABqDAAAAwAgAGwMAAAEAEwAbQwAAAMAOADqDAAAAwA/AG4MAAACACIAEQAICdcUmSQA3QEIaAwAAAMALwBpDAAABAAvAGsMAAAFAEQAagwAAAMAIABsDAAABABMAG0MAAADADgA6gwAAAMAPwBuDAAAAgAiAAAA.',
Dr='Drimbo:BAABLgAECn8XAAMSAAcJLwIybwCHAAdoDAAABAAEAGkMAAAEAAYAawwAAAQABABqDAAAAwALAGwMAAABAAcAbQwAAAEABgDqDAAABgAFABIABwkvAjJvAIcAB2gMAAAEAAQAaQwAAAQABgBrDAAAAwAEAGoMAAADAAsAbAwAAAEABwBtDAAAAQAGAOoMAAAGAAUAEwABCeUA7E8AFQABawwAAAEAAgAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECggJFAAUACEUAA==.',
Ec='Echoes:BAABLgAECn8nAAIVAAgJ+B6pDQB8AghoDAAACABeAGkMAAAHAFsAawwAAAcAWwBqDAAABgBbAGwMAAADAEsAbQwAAAEAQQDqDAAABgBgAG4MAAABACgAFQAICfgeqQ0AfAIIaAwAAAgAXgBpDAAABwBbAGsMAAAHAFsAagwAAAYAWwBsDAAAAwBLAG0MAAABAEEA6gwAAAYAYABuDAAAAQAoAAAA.Ectomage:BAAALgAECgQJBAAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAINAAgJCxYPIgC0AQhoDAAABgBKAGkMAAAGADsAawwAAAYAOwBqDAAABQAuAGwMAAADADwAbQwAAAEAKwDqDAAAAwA2AG4MAAABACoADQAICQsWDyIAtAEIaAwAAAYASgBpDAAABgA7AGsMAAAGADsAagwAAAUALgBsDAAAAwA8AG0MAAABACsA6gwAAAMANgBuDAAAAQAqAAAA.',
Fl='Floraa:BAAALgAECgYJCwAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMHAAYJExlNNQAmAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAJAD4AbgwAAAEAKwAHAAYJExlNNQAmAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAIAD4AbgwAAAEAKwAIAAEJvgGziwAgAAHqDAAAAQAEAAEuAAUUBQkHAAkAZBQA.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAFFAEJAwAAAA==.',
Il='Illidave:BAABLgAECn8UAAMWAAgJgAZ/NADmAAhoDAAAAwATAGkMAAADABIAawwAAAMADQBqDAAAAwAOAGwMAAADAA8AbQwAAAEACgDqDAAAAwAcAG4MAAABAAkAFgAICckFfzQA5gAIaAwAAAMAEwBpDAAAAwASAGsMAAADAA0AagwAAAMADgBsDAAAAwAPAG0MAAABAAoA6gwAAAIADwBuDAAAAQAJABcAAQkoC9k4ACEAAeoMAAABABwAAAA=.',
In='Insindia:BAABLgAECn8VAAIWAAgJ8Ql1KAAxAQhoDAAABAAlAGkMAAAEACIAawwAAAQAGABqDAAAAwAVAGwMAAACABIA6gwAAAIAEwBuDAAAAQAQAG8MAAABABkAFgAICfEJdSgAMQEIaAwAAAQAJQBpDAAABAAiAGsMAAAEABgAagwAAAMAFQBsDAAAAgASAOoMAAACABMAbgwAAAEAEABvDAAAAQAZAAAA.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ8xnQADAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgABAAYJjQ8xnQADAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8oAAMOAAkJqwkNWQBMAQloDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAABgBaAGwMAAAFAA0AbQwAAAIABgDqDAAABgATAG4MAAAFAAoAbwwAAAEAMAAOAAgJgggNWQBMAQhoDAAAAgAOAGkMAAACAAsAawwAAAIABwBqDAAAAwBaAGwMAAACAA0AbQwAAAIABgDqDAAABAATAG4MAAAEAAoADwAICUIHXkkACQEIaAwAAAMAGQBpDAAAAwAUAGsMAAADABIAagwAAAMAHQBsDAAAAwATAOoMAAACAAgAbgwAAAEAEQBvDAAAAQATAAAA.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMRAAcJcRLUOwBUAQdoDAAABwBGAGkMAAAGAC8AawwAAAgAHwBqDAAABAAiAGwMAAAFACsA6gwAAAQATwBuDAAAAQAXABEABgn6E9Q7AFQBBmgMAAAEAEYAaQwAAAMALwBrDAAABAAfAGoMAAADACIAbAwAAAIAKwDqDAAAAgBPABgABwm3EKqdADcBB2gMAAADAFoAaQwAAAMAKgBrDAAABAAoAGoMAAABABYAbAwAAAMALQDqDAAAAgAYAG4MAAABAAwAAAA=.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAECgYJBwABLgAFFAcJIAABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAFFAUJBwAJAGQUAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8gAAMBAAcJxBPiIAC8AQdoDAAABwBSAGkMAAAGAEQAawwAAAUAMwBqDAAABAAiAGwMAAABABIAbQwAAAEACgDqDAAACABIAAEABwmNE+IgALwBB2gMAAAHAFIAaQwAAAEAQABrDAAABAAzAGoMAAAEACIAbAwAAAEAEgBtDAAAAQAKAOoMAAAIAEgAGQACCcoPXQ0AogACaQwAAAUARABrDAAAAQAMAC4ABAp/MwAEAQAICb4keBsAsAIAAQAICRYjeBsAsAIAGQAFCckiUwwA/QEAGgAECXgeFBgAugAAAAA=.Magewings:BAABLgAECn8WAAIbAAYJkww4xgD/AAZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAbAAYJkww4xgD/AAZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn9GAAIcAAkJ1R1RFgCdAgloDAAACQBSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAJAFIAbQwAAAgAVADqDAAACwBNAG4MAAAHAEcAbwwAAAIANgAcAAkJ1R1RFgCdAgloDAAACQBSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAJAFIAbQwAAAgAVADqDAAACwBNAG4MAAAHAEcAbwwAAAIANgAAAA==.',
Mi='Mikayla:BAAALgAECgcJCQAAAA==.Miranda:BAAALgAFFAQJBwABLgAFFAcJIAABAMQTAQ==.Misobeastie:BAAALgAECgYJEAAAAA==.Mixup:BAACLgAFFH8RAAIBAAUJ3RWDSAAxAQVoDAAABAAoAGkMAAAEAE0AawwAAAMAJgBqDAAAAgA5AOoMAAAEAEMAAQAFCd0Vg0gAMQEFaAwAAAQAKABpDAAABABNAGsMAAADACYAagwAAAIAOQDqDAAABABDAC4ABAp/SwACAQAJCXIg9g4A0gIAAQAJCXIg9g4A0gIAAAA=.',
Mo='Mollan:BAAALgAECgcJDAAAAA==.Monkeys:BAAALgAFFAMJAQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxllDwARAgloDAAACQBRAGkMAAAJAFIAawwAAAkAPwBqDAAACABQAGwMAAAIAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAACAAkJtxllDwARAgloDAAACABRAGkMAAAIAFIAawwAAAgAPwBqDAAABwBQAGwMAAAHAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAAdAAUJkgpm5ADKAAVoDAAAAQAdAGkMAAABAB0AawwAAAEAIwBqDAAAAQAUAGwMAAABAAwAAAA=.Mythikal:BAABLgAECn8YAAIdAAgJtwzceABuAQhoDAAAAwAtAGkMAAADACMAawwAAAMAHwBqDAAAAwAlAGwMAAAEACgAbQwAAAEAFwDqDAAABgAiAG4MAAABABEAHQAICbcM3HgAbgEIaAwAAAMALQBpDAAAAwAjAGsMAAADAB8AagwAAAMAJQBsDAAABAAoAG0MAAABABcA6gwAAAYAIgBuDAAAAQARAAAA.',
Na='Nagini:BAAALgAECgQJBAAAAA==.Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAADAAAAAA==.',
No='Notthefather:BAAALgAECgYJCAAAAA==.',
Ot='Otekah:BAABLgAECn8mAAMRAAgJWBjxGQAyAghoDAAABgA5AGkMAAAGAFMAawwAAAYAVABqDAAABQBSAGwMAAADACsAbQwAAAMAMgDqDAAACAAmAG4MAAABADkAEQAICVgY8RkAMgIIaAwAAAQAOQBpDAAABQBTAGsMAAAFAFQAagwAAAQAUgBsDAAAAwArAG0MAAADADIA6gwAAAcAJgBuDAAAAQA5ABgABQn8CPsiAYkABWgMAAACACwAaQwAAAEAFQBrDAAAAQAQAGoMAAABABYA6gwAAAEACQAAAA==.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8mAAIWAAgJMw4vIwBYAQhoDAAABQAeAGkMAAAGACYAawwAAAYALQBqDAAABQAnAGwMAAADACsAbQwAAAMAGADqDAAACAAoAG4MAAACACAAFgAICTMOLyMAWAEIaAwAAAUAHgBpDAAABgAmAGsMAAAGAC0AagwAAAUAJwBsDAAAAwArAG0MAAADABgA6gwAAAgAKABuDAAAAgAgAAAA.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIdAAkJNQy/YgCfAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgAdAAkJNQy/YgCfAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQeAAcJfhIPPwBoAQdoDAAABQA/AGkMAAAFAEoAawwAAAUARgBqDAAABAA7AGwMAAACAAkAbQwAAAIADQDqDAAABwApAB4ABgm3FA8/AGgBBmgMAAADAD8AaQwAAAMASgBrDAAAAwBGAGoMAAADADsAbAwAAAEACQDqDAAAAwApAAcABwnKDPk2AB4BB2gMAAABABgAaQwAAAEADgBrDAAAAQAnAGoMAAABACgAbAwAAAEAGwBtDAAAAQAaAOoMAAADAEAACAAECXMJ4X8AUQAEaAwAAAEAGABpDAAAAQAYAGsMAAABABMA6gwAAAEAGwAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAbAGMPAA==.',
Ro='Roadhouse:BAAALgAECgQJBAAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAABLgAECn8UAAIUAAgJIRTVFgDrAQhoDAAAAwBIAGkMAAADADsAawwAAAMALwBqDAAAAgAqAGwMAAACABIAbQwAAAEAKgDqDAAABQBLAG4MAAABACsAFAAICSEU1RYA6wEIaAwAAAMASABpDAAAAwA7AGsMAAADAC8AagwAAAIAKgBsDAAAAgASAG0MAAABACoA6gwAAAUASwBuDAAAAQArAAAA.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQADAAAAAA==.Sandaexpress:BAAALgAFFAMJBAAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIdAAQJYBOSYwAsAQRoDAAAAgA1AGkMAAACADQAawwAAAEACQDqDAAAAgBTAB0ABAlgE5JjACwBBGgMAAACADUAaQwAAAIANABrDAAAAQAJAOoMAAACAFMAAAA=.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAMJBAADAAAAAA==.Shme:BAACLgAFFH8QAAIbAAQJ8gsWHgBSAQRoDAAABgAsAGkMAAAFACAAawwAAAEAHgDqDAAABAAOABsABAnyCxYeAFIBBGgMAAAGACwAaQwAAAUAIABrDAAAAQAeAOoMAAAEAA4ALgAECn80AAMbAAgJ1R1RKwDFAgAbAAgJ1R1RKwDFAgAfAAEJihUGHQA4AAAAAA==.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAbAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAQJDAAYADMlAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAQJDAAYADMlAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQADAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8dAAQEAAgJLgxtSwAXAQhoDAAABQAyAGkMAAAFABEAawwAAAYAKgBqDAAAAgAoAGwMAAADABMA6gwAAAMAFgBuDAAABAAYAG8MAAABACgABAAHCSULbUsAFwEHaAwAAAMAMgBpDAAAAwARAGsMAAAEACoAagwAAAIAKABsDAAAAgATAOoMAAACABYAbgwAAAIAEgAGAAUJaga4NwCSAAVoDAAAAgApAGkMAAACAAEAawwAAAIACwBsDAAAAQALAOoMAAABAA8ABQACCdQMolgAbgACbgwAAAIAGABvDAAAAQAoAAAA.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8jAAIOAAcJVBhyMQDpAQdoDAAACgBFAGkMAAAIAE4AawwAAAcARwBqDAAABABMAGwMAAADAEUA6gwAAAIAPgBuDAAAAQAHAA4ABwlUGHIxAOkBB2gMAAAKAEUAaQwAAAgATgBrDAAABwBHAGoMAAAEAEwAbAwAAAMARQDqDAAAAgA+AG4MAAABAAcAAAA=.',
Sy='Syllogica:BAACLgAFFH8XAAIgAAQJQBb6GABEAQRoDAAABgBCAGkMAAAHADMAawwAAAMAMADqDAAABwA9ACAABAlAFvoYAEQBBGgMAAAGAEIAaQwAAAcAMwBrDAAAAwAwAOoMAAAHAD0ALgAECn8WAAIgAAgJrBAwKABPAQAgAAgJrBAwKABPAQAAAA==.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9WAAILAAkJkCQXAgCHAwloDAAACwBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAALAGEAbQwAAAoAYQDqDAAADABhAG4MAAAJAFMAbwwAAAMAVQALAAkJkCQXAgCHAwloDAAACwBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAALAGEAbQwAAAoAYQDqDAAADABhAG4MAAAJAFMAbwwAAAMAVQAAAA==.',
Te='Tenderloinz:BAAALgAECgUJEQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Tokkia:BAAALgAECggJCAAAAA==.Toothandclaw:BAAALgADCgMJAwAAAA==.Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIRAAIJdhfZFwCGAAJoDAAABAAzAGkMAAADAEUAEQACCXYX2RcAhgACaAwAAAQAMwBpDAAAAwBFAC4ABAp/KgACEQAICX8iswUAEAMAEQAICX8iswUAEAMAAAA=.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJEQAAAA==.Vaughan:BAACLgAFFH8MAAIYAAQJMyUmFQCyAQRoDAAAAwBjAGkMAAADAGAAawwAAAIAVwDqDAAABABhABgABAkzJSYVALIBBGgMAAADAGMAaQwAAAMAYABrDAAAAgBXAOoMAAAEAGEALgAECn8tAAIYAAkJpiTfCgANAwAYAAkJpiTfCgANAwAAAA==.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Vy='Vynathenin:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAACLgAFFH8GAAIBAAQJMwaFbADjAARoDAAAAQAfAGkMAAABABYAawwAAAEABADqDAAAAwAEAAEABAkzBoVsAOMABGgMAAABAB8AaQwAAAEAFgBrDAAAAQAEAOoMAAADAAQALgAECn89AAIBAAgJvBrrNAADAgABAAgJvBrrNAADAgAAAA==.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whatacombo:BAAALgAECgUJBQABLgAFFAMJBAADAAAAAA==.Whollycow:BAAALgAFFAEJAQABLgAFFAMJBAADAAAAAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAABLgAFFH8HAAIJAAUJZBQbPAAuAQVoDAAAAgBOAGkMAAABACMAawwAAAEAEgBqDAAAAQAuAOoMAAACAEwACQAFCWQUGzwALgEFaAwAAAIATgBpDAAAAQAjAGsMAAABABIAagwAAAEALgDqDAAAAgBMAAAA.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgYJCgAAAA==.Zaka:BAAALgADCgEJAQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
Zu='Zulander:BAAALgAECgQJCwAAAA==.',
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
