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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Mage-Arcane','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='daily',zone=46,date='2026-06-16',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAQ==.',
An='Anasazi:BAAALgAECgYJCgAAAA==.Andrémarkis:BAAALgAECgQJBwABLgAFFAcJIAABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRM2IgA/AQdoDAAABQAfAGkMAAAFADYAawwAAAUAIABqDAAABABRAGwMAAACAE8AbQwAAAEAMwDqDAAABwAyAAIABwmZEzYiAD8BB2gMAAAFAB8AaQwAAAUANgBrDAAABQAgAGoMAAAEAFEAbAwAAAIATwBtDAAAAQAzAOoMAAAHADIAAAA=.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAFFAEJAQABLgAFFAMJBgADAMUTAA==.Barehunt:BAAALgADCgkJCQABLgAFFAMJBgADAMUTAA==.',
Be='Bedorea:BAABLgAECn81AAMEAAkJQBocEQBtAgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACQBTAG4MAAADAE4AbwwAAAEAOAAEAAkJQBocEQBtAgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACABTAG4MAAADAE4AbwwAAAEAOAAFAAEJ0Aa5RQAtAAHqDAAAAQARAAAA.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAABLgAFFH8IAAMGAAQJGRMmGQDMAARoDAAAAgAyAGkMAAACADEAawwAAAIATQDqDAAAAgASAAYAAwkbFyYZAMwAA2gMAAABADIAaQwAAAEAMQBrDAAAAgBNAAUAAwmbDTspAMYAA2gMAAABACoAaQwAAAEAKwDqDAAAAgASAAAA.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIAABAMQTAQ==.Bloodweiser:BAABLgAECn8WAAMHAAYJSBJXOQAWAQZoDAAABAAuAGkMAAAFAC4AawwAAAUALgBqDAAABAA/AGwMAAADADUA6gwAAAEAKQAHAAYJSBJXOQAWAQZoDAAABAAuAGkMAAAEAC4AawwAAAQALgBqDAAABAA/AGwMAAADADUA6gwAAAEAKQAIAAIJqAUukQA/AAJpDAAAAQAOAGsMAAABAA4AAAA=.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAFFAUJBwAJAGQUAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIKAAgJyRgsEgDMAQhoDAAABAA6AGkMAAAEAEgAawwAAAMAMwBqDAAAAwBSAGwMAAAFAEkAbQwAAAEASADqDAAAAwA/AG4MAAABADMACgAICckYLBIAzAEIaAwAAAQAOgBpDAAABABIAGsMAAADADMAagwAAAMAUgBsDAAABQBJAG0MAAABAEgA6gwAAAMAPwBuDAAAAQAzAAAA.Bullship:BAAALgADCgYJBgAAAA==.Bumwitboba:BAABLgAECn8dAAQLAAYJdB87GAAaAgZoDAAABQBNAGkMAAAFAEQAawwAAAUAWwBqDAAABABTAGwMAAADAF0A6gwAAAcARQALAAYJdB87GAAaAgZoDAAABABNAGkMAAAEAEQAawwAAAMAWwBqDAAABABTAGwMAAADAF0A6gwAAAYARQAMAAQJeg1SXwCAAARoDAAAAQAQAGkMAAABABQAawwAAAEAKADqDAAAAQA9AA0AAQlzECCCADgAAWsMAAABACoAAAA=.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8cAAIJAAcJ3AZznwDjAAdoDAAABQAMAGkMAAAEAA8AawwAAAUADwBqDAAABAAdAGwMAAACABUAbQwAAAEAFADqDAAABwATAAkABwncBnOfAOMAB2gMAAAFAAwAaQwAAAQADwBrDAAABQAPAGoMAAAEAB0AbAwAAAIAFQBtDAAAAQAUAOoMAAAHABMAAAA=.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgQJBgAAAA==.Chironex:BAABLgAFFH8IAAIOAAUJnxNUJwBIAQVoDAAAAgBLAGkMAAABABAAawwAAAEAOABqDAAAAQA5AOoMAAADACwADgAFCZ8TVCcASAEFaAwAAAIASwBpDAAAAQAQAGsMAAABADgAagwAAAEAOQDqDAAAAwAsAAAA.Chuleta:BAAALgAECgQJBQAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAFFAUJBwAJAGQUAA==.Conjuresnacc:BAAALgAECgEJAQAAAA==.',
Da='Daelnei:BAABLgAECn8rAAIEAAcJIRF2OQBfAQdoDAAACQA4AGkMAAAIACIAawwAAAcAGABqDAAABQA4AGwMAAAFACoA6gwAAAgAOQBuDAAAAQAuAAQABwkhEXY5AF8BB2gMAAAJADgAaQwAAAgAIgBrDAAABwAYAGoMAAAFADgAbAwAAAUAKgDqDAAACAA5AG4MAAABAC4AAAA=.Damja:BAABLgAECn8WAAIEAAYJagoeYgDOAAZoDAAABQAwAGkMAAAFABoAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAEAAYJagoeYgDOAAZoDAAABQAwAGkMAAAFABoAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAAAA==.Darkloky:BAABLgAECn8+AAIPAAgJPQ4EOwBJAQhoDAAACwAjAGkMAAAKAC8AawwAAAoALgBqDAAACAA3AGwMAAAHACoAbQwAAAIADwDqDAAACgAXAG4MAAAEACsADwAICT0OBDsASQEIaAwAAAsAIwBpDAAACgAvAGsMAAAKAC4AagwAAAgANwBsDAAABwAqAG0MAAACAA8A6gwAAAoAFwBuDAAABAArAAAA.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIQAAcJtQznHgARAQdoDAAAAwA7AGkMAAADACMAawwAAAMAFQBqDAAAAwA0AGwMAAACAB4AbQwAAAEABADqDAAABQArABAABwm1DOceABEBB2gMAAADADsAaQwAAAMAIwBrDAAAAwAVAGoMAAADADQAbAwAAAIAHgBtDAAAAQAEAOoMAAAFACsAAAA=.',
De='Debby:BAABLgAECn8gAAIOAAgJzRTGNADeAQhoDAAABgAtAGkMAAAFACoAawwAAAUAOgBqDAAABAA3AGwMAAADAEMAbQwAAAEALQDqDAAABwA3AG4MAAABADgADgAICc0UxjQA3gEIaAwAAAYALQBpDAAABQAqAGsMAAAFADoAagwAAAQANwBsDAAAAwBDAG0MAAABAC0A6gwAAAcANwBuDAAAAQA4AAAA.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECggJDwAAAA==.',
Do='Donane:BAABLgAECn8fAAIRAAgJOhcuHQAaAghoDAAAAwAvAGkMAAAEAC8AawwAAAUARABqDAAABQBNAGwMAAAFAEwAbQwAAAMAOADqDAAABABDAG4MAAACACIAEQAICToXLh0AGgIIaAwAAAMALwBpDAAABAAvAGsMAAAFAEQAagwAAAUATQBsDAAABQBMAG0MAAADADgA6gwAAAQAQwBuDAAAAgAiAAAA.',
Dr='Drimbo:BAABLgAECn8XAAMSAAcJLwIscQCHAAdoDAAABAAEAGkMAAAEAAYAawwAAAQABABqDAAAAwALAGwMAAABAAcAbQwAAAEABgDqDAAABgAFABIABwkvAixxAIcAB2gMAAAEAAQAaQwAAAQABgBrDAAAAwAEAGoMAAADAAsAbAwAAAEABwBtDAAAAQAGAOoMAAAGAAUAEwABCeUA7E8AFQABawwAAAEAAgAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECggJFAAUACEUAA==.',
Ec='Echoes:BAABLgAECn8nAAIVAAgJ+B7TDQB8AghoDAAACABeAGkMAAAHAFsAawwAAAcAWwBqDAAABgBbAGwMAAADAEsAbQwAAAEAQQDqDAAABgBgAG4MAAABACgAFQAICfge0w0AfAIIaAwAAAgAXgBpDAAABwBbAGsMAAAHAFsAagwAAAYAWwBsDAAAAwBLAG0MAAABAEEA6gwAAAYAYABuDAAAAQAoAAAA.Ectomage:BAAALgAECgQJBAAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAINAAgJCxbAIgCxAQhoDAAABgBKAGkMAAAGADsAawwAAAYAOwBqDAAABQAuAGwMAAADADwAbQwAAAEAKwDqDAAAAwA2AG4MAAABACoADQAICQsWwCIAsQEIaAwAAAYASgBpDAAABgA7AGsMAAAGADsAagwAAAUALgBsDAAAAwA8AG0MAAABACsA6gwAAAMANgBuDAAAAQAqAAAA.',
Fl='Floraa:BAAALgAECgYJCwAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMHAAYJExnnNQAlAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAJAD4AbgwAAAEAKwAHAAYJExnnNQAlAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAIAD4AbgwAAAEAKwAIAAEJvgGziwAgAAHqDAAAAQAEAAEuAAUUBQkHAAkAZBQA.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAFFAEJAwAAAA==.',
Il='Illidave:BAABLgAECn8aAAMWAAgJdgkzGgDLAAhoDAAABAAnAGkMAAAEADAAawwAAAQADQBqDAAABAAjAGwMAAAEABMAbQwAAAEACgDqDAAABAAcAG4MAAABAAkAFwAICckF9TUA4wAIaAwAAAMAEwBpDAAAAwASAGsMAAADAA0AagwAAAMADgBsDAAAAwAPAG0MAAABAAoA6gwAAAIADwBuDAAAAQAJABYABglyCzMaAMsABmgMAAABACcAaQwAAAEAMABrDAAAAQAKAGoMAAABACMAbAwAAAEAEwDqDAAAAgAcAAAA.',
In='Insindia:BAABLgAECn8VAAIXAAgJ8QmmKQAvAQhoDAAABAAlAGkMAAAEACIAawwAAAQAGABqDAAAAwAVAGwMAAACABIA6gwAAAIAEwBuDAAAAQAQAG8MAAABABkAFwAICfEJpikALwEIaAwAAAQAJQBpDAAABAAiAGsMAAAEABgAagwAAAMAFQBsDAAAAgASAOoMAAACABMAbgwAAAEAEABvDAAAAQAZAAAA.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ8znwADAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgABAAYJjQ8znwADAQZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8oAAMOAAkJqwm+WgBMAQloDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAABgBaAGwMAAAFAA0AbQwAAAIABgDqDAAABgATAG4MAAAFAAoAbwwAAAEAMAAOAAgJggi+WgBMAQhoDAAAAgAOAGkMAAACAAsAawwAAAIABwBqDAAAAwBaAGwMAAACAA0AbQwAAAIABgDqDAAABAATAG4MAAAEAAoADwAICUIH/UoACAEIaAwAAAMAGQBpDAAAAwAUAGsMAAADABIAagwAAAMAHQBsDAAAAwATAOoMAAACAAgAbgwAAAEAEQBvDAAAAQATAAAA.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMRAAcJcRLGPABUAQdoDAAABwBGAGkMAAAGAC8AawwAAAgAHwBqDAAABAAiAGwMAAAFACsA6gwAAAQATwBuDAAAAQAXABEABgn6E8Y8AFQBBmgMAAAEAEYAaQwAAAMALwBrDAAABAAfAGoMAAADACIAbAwAAAIAKwDqDAAAAgBPABgABwm3EE+gADcBB2gMAAADAFoAaQwAAAMAKgBrDAAABAAoAGoMAAABABYAbAwAAAMALQDqDAAAAgAYAG4MAAABAAwAAAA=.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAFFAUJBwAJAGQUAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8gAAMBAAcJxBMNJAC5AQdoDAAABwBSAGkMAAAGAEQAawwAAAUAMwBqDAAABAAiAGwMAAABABIAbQwAAAEACgDqDAAACABIAAEABwmNEw0kALkBB2gMAAAHAFIAaQwAAAEAQABrDAAABAAzAGoMAAAEACIAbAwAAAEAEgBtDAAAAQAKAOoMAAAIAEgAGQACCcoPXQ0AogACaQwAAAUARABrDAAAAQAMAC4ABAp/MwAEAQAICb4keBsAsAIAAQAICRYjeBsAsAIAGQAFCckiUwwA/QEAGgAECXgeFBgAugAAAAA=.Magewings:BAABLgAECn8WAAIbAAYJkwyHyQD6AAZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAbAAYJkwyHyQD6AAZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Manitaur:BAAALgAECgEJAQAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn9GAAIcAAkJ1R1DFwCbAgloDAAACQBSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAJAFIAbQwAAAgAVADqDAAACwBNAG4MAAAHAEcAbwwAAAIANgAcAAkJ1R1DFwCbAgloDAAACQBSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAJAFIAbQwAAAgAVADqDAAACwBNAG4MAAAHAEcAbwwAAAIANgAAAA==.',
Mi='Mikayla:BAAALgAECgcJCgAAAA==.Miranda:BAAALgAFFAQJCQABLgAFFAcJIAABAMQTAQ==.Misobeastie:BAAALgAECgYJEAAAAA==.Mixup:BAACLgAFFH8RAAIBAAUJ3RWdSwAuAQVoDAAABAAoAGkMAAAEAE0AawwAAAMAJgBqDAAAAgA5AOoMAAAEAEMAAQAFCd0VnUsALgEFaAwAAAQAKABpDAAABABNAGsMAAADACYAagwAAAIAOQDqDAAABABDAC4ABAp/SwACAQAJCXIggA8A0QIAAQAJCXIggA8A0QIAAAA=.',
Mo='Mollan:BAAALgAECgcJDAAAAA==.Monkeys:BAAALgAFFAMJAQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxnADwAOAgloDAAACQBRAGkMAAAJAFIAawwAAAkAPwBqDAAACABQAGwMAAAIAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAACAAkJtxnADwAOAgloDAAACABRAGkMAAAIAFIAawwAAAgAPwBqDAAABwBQAGwMAAAHAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAADAAUJkgpj6ADKAAVoDAAAAQAdAGkMAAABAB0AawwAAAEAIwBqDAAAAQAUAGwMAAABAAwAAAA=.Mythikal:BAABLgAECn8bAAIDAAgJXA/abACMAQhoDAAAAwAtAGkMAAADACMAawwAAAMAHwBqDAAABABNAGwMAAAFACgAbQwAAAIARgDqDAAABgAiAG4MAAABABEAAwAICVwP2mwAjAEIaAwAAAMALQBpDAAAAwAjAGsMAAADAB8AagwAAAQATQBsDAAABQAoAG0MAAACAEYA6gwAAAYAIgBuDAAAAQARAAAA.',
Na='Nagini:BAAALgAECgQJBgAAAA==.Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAAdAAAAAA==.',
Ne='Necropheelia:BAAALgAECgEJAQAAAA==.',
No='Notthefather:BAAALgAECgcJDQAAAA==.',
Ot='Otekah:BAABLgAECn8mAAMRAAgJWBhtGgAxAghoDAAABgA5AGkMAAAGAFMAawwAAAYAVABqDAAABQBSAGwMAAADACsAbQwAAAMAMgDqDAAACAAmAG4MAAABADkAEQAICVgYbRoAMQIIaAwAAAQAOQBpDAAABQBTAGsMAAAFAFQAagwAAAQAUgBsDAAAAwArAG0MAAADADIA6gwAAAcAJgBuDAAAAQA5ABgABQn8CNEnAYkABWgMAAACACwAaQwAAAEAFQBrDAAAAQAQAGoMAAABABYA6gwAAAEACQAAAA==.',
Ov='Overthereman:BAAALgAECgQJBAABLgAFFAMJBgADAMUTAA==.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8mAAIXAAgJMw4hJABVAQhoDAAABQAeAGkMAAAGACYAawwAAAYALQBqDAAABQAnAGwMAAADACsAbQwAAAMAGADqDAAACAAoAG4MAAACACAAFwAICTMOISQAVQEIaAwAAAUAHgBpDAAABgAmAGsMAAAGAC0AagwAAAUAJwBsDAAAAwArAG0MAAADABgA6gwAAAgAKABuDAAAAgAgAAAA.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIDAAkJNQytZACeAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgADAAkJNQytZACeAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQeAAcJfhLSQABpAQdoDAAABQA/AGkMAAAFAEoAawwAAAUARgBqDAAABAA7AGwMAAACAAkAbQwAAAIADQDqDAAABwApAB4ABgm3FNJAAGkBBmgMAAADAD8AaQwAAAMASgBrDAAAAwBGAGoMAAADADsAbAwAAAEACQDqDAAAAwApAAcABwnKDIA3AB4BB2gMAAABABgAaQwAAAEADgBrDAAAAQAnAGoMAAABACgAbAwAAAEAGwBtDAAAAQAaAOoMAAADAEAACAAECXMJT4IAUQAEaAwAAAEAGABpDAAAAQAYAGsMAAABABMA6gwAAAEAGwAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAbAGMPAA==.',
Ro='Roadhouse:BAAALgAECgQJBAAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAABLgAECn8UAAIUAAgJIRR8FwDlAQhoDAAAAwBIAGkMAAADADsAawwAAAMALwBqDAAAAgAqAGwMAAACABIAbQwAAAEAKgDqDAAABQBLAG4MAAABACsAFAAICSEUfBcA5QEIaAwAAAMASABpDAAAAwA7AGsMAAADAC8AagwAAAIAKgBsDAAAAgASAG0MAAABACoA6gwAAAUASwBuDAAAAQArAAAA.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQAdAAAAAA==.Sandaexpress:BAABLgAFFH8GAAIDAAMJxRNimgDZAANoDAAAAwBHAGkMAAABACkA6gwAAAIAJgADAAMJxRNimgDZAANoDAAAAwBHAGkMAAABACkA6gwAAAIAJgAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIDAAQJYBMnaAAnAQRoDAAAAgA1AGkMAAACADQAawwAAAEACQDqDAAAAgBTAAMABAlgEydoACcBBGgMAAACADUAaQwAAAIANABrDAAAAQAJAOoMAAACAFMAAAA=.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAMJBgADAMUTAA==.Shme:BAACLgAFFH8QAAIbAAQJ8gsWHgBSAQRoDAAABgAsAGkMAAAFACAAawwAAAEAHgDqDAAABAAOABsABAnyCxYeAFIBBGgMAAAGACwAaQwAAAUAIABrDAAAAQAeAOoMAAAEAA4ALgAECn80AAMbAAgJ1R1RKwDFAgAbAAgJ1R1RKwDFAgAfAAEJihUGHQA4AAAAAA==.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAbAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAQJDAAYADMlAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAQJDAAYADMlAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQAdAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8dAAQEAAgJLgwFTQARAQhoDAAABQAyAGkMAAAFABEAawwAAAYAKgBqDAAAAgAoAGwMAAADABMA6gwAAAMAFgBuDAAABAAYAG8MAAABACgABAAHCSULBU0AEQEHaAwAAAMAMgBpDAAAAwARAGsMAAAEACoAagwAAAIAKABsDAAAAgATAOoMAAACABYAbgwAAAIAEgAGAAUJagawOACSAAVoDAAAAgApAGkMAAACAAEAawwAAAIACwBsDAAAAQALAOoMAAABAA8ABQACCdQMl1oAbgACbgwAAAIAGABvDAAAAQAoAAAA.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8jAAIOAAcJVBhwMgDoAQdoDAAACgBFAGkMAAAIAE4AawwAAAcARwBqDAAABABMAGwMAAADAEUA6gwAAAIAPgBuDAAAAQAHAA4ABwlUGHAyAOgBB2gMAAAKAEUAaQwAAAgATgBrDAAABwBHAGoMAAAEAEwAbAwAAAMARQDqDAAAAgA+AG4MAAABAAcAAAA=.',
Sy='Syllogica:BAACLgAFFH8XAAIgAAQJQBb5GQBEAQRoDAAABgBCAGkMAAAHADMAawwAAAMAMADqDAAABwA9ACAABAlAFvkZAEQBBGgMAAAGAEIAaQwAAAcAMwBrDAAAAwAwAOoMAAAHAD0ALgAECn8WAAIgAAgJrBD0KABPAQAgAAgJrBD0KABPAQAAAA==.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9WAAILAAkJkCQvAgCFAwloDAAACwBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAALAGEAbQwAAAoAYQDqDAAADABhAG4MAAAJAFMAbwwAAAMAVQALAAkJkCQvAgCFAwloDAAACwBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAALAGEAbQwAAAoAYQDqDAAADABhAG4MAAAJAFMAbwwAAAMAVQAAAA==.',
Te='Tenderloinz:BAAALgAECgUJEQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Tokkia:BAAALgAECggJCAAAAA==.Toothandclaw:BAAALgADCgMJAwAAAA==.Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIRAAIJdhfZFwCGAAJoDAAABAAzAGkMAAADAEUAEQACCXYX2RcAhgACaAwAAAQAMwBpDAAAAwBFAC4ABAp/KgACEQAICX8iswUAEAMAEQAICX8iswUAEAMAAAA=.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJEQAAAA==.Vaughan:BAACLgAFFH8MAAIYAAQJMyVFFwCwAQRoDAAAAwBjAGkMAAADAGAAawwAAAIAVwDqDAAABABhABgABAkzJUUXALABBGgMAAADAGMAaQwAAAMAYABrDAAAAgBXAOoMAAAEAGEALgAECn8tAAIYAAkJpiRJCwAMAwAYAAkJpiRJCwAMAwAAAA==.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Vy='Vynathenin:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAACLgAFFH8GAAIBAAQJMwZDbwDiAARoDAAAAQAfAGkMAAABABYAawwAAAEABADqDAAAAwAEAAEABAkzBkNvAOIABGgMAAABAB8AaQwAAAEAFgBrDAAAAQAEAOoMAAADAAQALgAECn89AAIBAAgJvBrNNQADAgABAAgJvBrNNQADAgAAAA==.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgAdAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whatacombo:BAAALgAECgYJBwABLgAFFAMJBgADAMUTAA==.Whollycow:BAAALgAFFAEJAQABLgAFFAMJBgADAMUTAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAABLgAFFH8HAAIJAAUJZBT6PgAqAQVoDAAAAgBOAGkMAAABACMAawwAAAEAEgBqDAAAAQAuAOoMAAACAEwACQAFCWQU+j4AKgEFaAwAAAIATgBpDAAAAQAjAGsMAAABABIAagwAAAEALgDqDAAAAgBMAAAA.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgYJCgAAAA==.Zaka:BAAALgADCgEJAQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
Zu='Zulander:BAAALgAECgQJDAAAAA==.',
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
