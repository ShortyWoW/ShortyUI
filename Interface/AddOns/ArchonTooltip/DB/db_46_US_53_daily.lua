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
local provider = {region='US',realm='Chromaggus',name='US',type='daily',zone=46,date='2026-06-17',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAQ==.',
An='Anasazi:BAAALgAECgcJCwAAAA==.Andrémarkis:BAAALgAECgQJBwABLgAFFAcJIAABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRNYIgA/AQdoDAAABQAfAGkMAAAFADYAawwAAAUAIABqDAAABABRAGwMAAACAE8AbQwAAAEAMwDqDAAABwAyAAIABwmZE1giAD8BB2gMAAAFAB8AaQwAAAUANgBrDAAABQAgAGoMAAAEAFEAbAwAAAIATwBtDAAAAQAzAOoMAAAHADIAAAA=.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAFFAEJAQABLgAFFAMJBwADAMUTAA==.Barehunt:BAAALgADCgkJCQABLgAFFAMJBwADAMUTAA==.',
Be='Bedorea:BAABLgAECn81AAMEAAkJQBotEQBtAgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACQBTAG4MAAADAE4AbwwAAAEAOAAEAAkJQBotEQBtAgloDAAACgBaAGkMAAAJAFAAawwAAAgAOABqDAAABgBYAGwMAAAGAFQAbQwAAAEABwDqDAAACABTAG4MAAADAE4AbwwAAAEAOAAFAAEJ0Aa5RQAtAAHqDAAAAQARAAAA.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAABLgAFFH8JAAMGAAUJGRNjGQDMAAVoDAAAAgAyAGkMAAACADEAawwAAAIATQBqDAAAAQAOAOoMAAACABIABgADCRsXYxkAzAADaAwAAAEAMgBpDAAAAQAxAGsMAAACAE0ABQAECZsNeCkAxgAEaAwAAAEAKgBpDAAAAQArAGoMAAABAA4A6gwAAAIAEgAAAA==.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIAABAMQTAQ==.Bloodweiser:BAABLgAECn8WAAMHAAYJSBJoOQAWAQZoDAAABAAuAGkMAAAFAC4AawwAAAUALgBqDAAABAA/AGwMAAADADUA6gwAAAEAKQAHAAYJSBJoOQAWAQZoDAAABAAuAGkMAAAEAC4AawwAAAQALgBqDAAABAA/AGwMAAADADUA6gwAAAEAKQAIAAIJqAWrkQA/AAJpDAAAAQAOAGsMAAABAA4AAAA=.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAFFAUJBwAJAGQUAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIKAAgJyRg+EgDMAQhoDAAABAA6AGkMAAAEAEgAawwAAAMAMwBqDAAAAwBSAGwMAAAFAEkAbQwAAAEASADqDAAAAwA/AG4MAAABADMACgAICckYPhIAzAEIaAwAAAQAOgBpDAAABABIAGsMAAADADMAagwAAAMAUgBsDAAABQBJAG0MAAABAEgA6gwAAAMAPwBuDAAAAQAzAAAA.Bullship:BAAALgADCgYJBgAAAA==.Bumwitboba:BAABLgAECn8dAAQLAAYJdB87GAAaAgZoDAAABQBNAGkMAAAFAEQAawwAAAUAWwBqDAAABABTAGwMAAADAF0A6gwAAAcARQALAAYJdB87GAAaAgZoDAAABABNAGkMAAAEAEQAawwAAAMAWwBqDAAABABTAGwMAAADAF0A6gwAAAYARQAMAAQJeg3lXwB+AARoDAAAAQAQAGkMAAABABQAawwAAAEAKADqDAAAAQA9AA0AAQlzEHOCADgAAWsMAAABACoAAAA=.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8cAAIJAAcJ3AbRnwDjAAdoDAAABQAMAGkMAAAEAA8AawwAAAUADwBqDAAABAAdAGwMAAACABUAbQwAAAEAFADqDAAABwATAAkABwncBtGfAOMAB2gMAAAFAAwAaQwAAAQADwBrDAAABQAPAGoMAAAEAB0AbAwAAAIAFQBtDAAAAQAUAOoMAAAHABMAAAA=.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgQJBgAAAA==.Chironex:BAABLgAFFH8IAAIOAAUJnxOZJwBIAQVoDAAAAgBLAGkMAAABABAAawwAAAEAOABqDAAAAQA5AOoMAAADACwADgAFCZ8TmScASAEFaAwAAAIASwBpDAAAAQAQAGsMAAABADgAagwAAAEAOQDqDAAAAwAsAAAA.Chuleta:BAAALgAECgQJBQAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAFFAUJBwAJAGQUAA==.Conjuresnacc:BAAALgAECgEJAQAAAA==.',
Da='Daelnei:BAABLgAECn8vAAIEAAcJIRFDAAD7AAdoDAAACgA4AGkMAAAJACIAawwAAAgAGABqDAAABQA4AGwMAAAFACoA6gwAAAkAOQBuDAAAAQAuAAQABwkhEUMAAPsAB2gMAAAKADgAaQwAAAkAIgBrDAAACAAYAGoMAAAFADgAbAwAAAUAKgDqDAAACQA5AG4MAAABAC4AAAA=.Damja:BAABLgAECn8WAAIEAAYJagpnYgDOAAZoDAAABQAwAGkMAAAFABoAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAEAAYJagpnYgDOAAZoDAAABQAwAGkMAAAFABoAawwAAAMACwBqDAAAAQACAGwMAAABAAkA6gwAAAcAJAAAAA==.Darkloky:BAABLgAECn8+AAIPAAgJPQ4jOwBJAQhoDAAACwAjAGkMAAAKAC8AawwAAAoALgBqDAAACAA3AGwMAAAHACoAbQwAAAIADwDqDAAACgAXAG4MAAAEACsADwAICT0OIzsASQEIaAwAAAsAIwBpDAAACgAvAGsMAAAKAC4AagwAAAgANwBsDAAABwAqAG0MAAACAA8A6gwAAAoAFwBuDAAABAArAAAA.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIQAAcJtQznHgARAQdoDAAAAwA7AGkMAAADACMAawwAAAMAFQBqDAAAAwA0AGwMAAACAB4AbQwAAAEABADqDAAABQArABAABwm1DOceABEBB2gMAAADADsAaQwAAAMAIwBrDAAAAwAVAGoMAAADADQAbAwAAAIAHgBtDAAAAQAEAOoMAAAFACsAAAA=.',
De='Debby:BAABLgAECn8gAAIOAAgJzRTuNADeAQhoDAAABgAtAGkMAAAFACoAawwAAAUAOgBqDAAABAA3AGwMAAADAEMAbQwAAAEALQDqDAAABwA3AG4MAAABADgADgAICc0U7jQA3gEIaAwAAAYALQBpDAAABQAqAGsMAAAFADoAagwAAAQANwBsDAAAAwBDAG0MAAABAC0A6gwAAAcANwBuDAAAAQA4AAAA.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECggJDwAAAA==.',
Do='Donane:BAABLgAECn8fAAIRAAgJOhcyHQAZAghoDAAAAwAvAGkMAAAEAC8AawwAAAUARABqDAAABQBNAGwMAAAFAEwAbQwAAAMAOADqDAAABABDAG4MAAACACIAEQAICToXMh0AGQIIaAwAAAMALwBpDAAABAAvAGsMAAAFAEQAagwAAAUATQBsDAAABQBMAG0MAAADADgA6gwAAAQAQwBuDAAAAgAiAAAA.',
Dr='Drimbo:BAABLgAECn8XAAMSAAcJLwKRcQCHAAdoDAAABAAEAGkMAAAEAAYAawwAAAQABABqDAAAAwALAGwMAAABAAcAbQwAAAEABgDqDAAABgAFABIABwkvApFxAIcAB2gMAAAEAAQAaQwAAAQABgBrDAAAAwAEAGoMAAADAAsAbAwAAAEABwBtDAAAAQAGAOoMAAAGAAUAEwABCeUA7E8AFQABawwAAAEAAgAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECggJFAAUACEUAA==.',
Ec='Echoes:BAABLgAECn8nAAIVAAgJ+B7ZDQB8AghoDAAACABeAGkMAAAHAFsAawwAAAcAWwBqDAAABgBbAGwMAAADAEsAbQwAAAEAQQDqDAAABgBgAG4MAAABACgAFQAICfge2Q0AfAIIaAwAAAgAXgBpDAAABwBbAGsMAAAHAFsAagwAAAYAWwBsDAAAAwBLAG0MAAABAEEA6gwAAAYAYABuDAAAAQAoAAAA.Ectomage:BAAALgAECgQJBAAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAINAAgJCxbVIgCxAQhoDAAABgBKAGkMAAAGADsAawwAAAYAOwBqDAAABQAuAGwMAAADADwAbQwAAAEAKwDqDAAAAwA2AG4MAAABACoADQAICQsW1SIAsQEIaAwAAAYASgBpDAAABgA7AGsMAAAGADsAagwAAAUALgBsDAAAAwA8AG0MAAABACsA6gwAAAMANgBuDAAAAQAqAAAA.',
Fl='Floraa:BAAALgAECgYJCwAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMHAAYJExn9NQAlAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAJAD4AbgwAAAEAKwAHAAYJExn9NQAlAQZoDAAABAA9AGkMAAAEAEwAawwAAAQATQBqDAAAAQAbAOoMAAAIAD4AbgwAAAEAKwAIAAEJvgGziwAgAAHqDAAAAQAEAAEuAAUUBQkHAAkAZBQA.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAFFAEJAwAAAA==.',
Il='Illidave:BAABLgAECn8aAAMWAAgJdglHGgDLAAhoDAAABAAnAGkMAAAEADAAawwAAAQADQBqDAAABAAjAGwMAAAEABMAbQwAAAEACgDqDAAABAAcAG4MAAABAAkAFwAICckFIzYA4wAIaAwAAAMAEwBpDAAAAwASAGsMAAADAA0AagwAAAMADgBsDAAAAwAPAG0MAAABAAoA6gwAAAIADwBuDAAAAQAJABYABglyC0caAMsABmgMAAABACcAaQwAAAEAMABrDAAAAQAKAGoMAAABACMAbAwAAAEAEwDqDAAAAgAcAAAA.',
In='Insindia:BAABLgAECn8WAAIXAAgJ8gnaKQAvAQhoDAAABAAlAGkMAAAEACIAawwAAAQAGABqDAAAAwAVAGwMAAACABIA6gwAAAMAEwBuDAAAAQAQAG8MAAABABkAFwAICfIJ2ikALwEIaAwAAAQAJQBpDAAABAAiAGsMAAAEABgAagwAAAMAFQBsDAAAAgASAOoMAAADABMAbgwAAAEAEABvDAAAAQAZAAAA.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ96oAD+AAZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgABAAYJjQ96oAD+AAZoDAAABQA5AGkMAAAFABsAawwAAAUAHABqDAAABAA7AGwMAAACACsA6gwAAAUAKgAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8oAAMOAAkJqwn8WgBMAQloDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAABgBaAGwMAAAFAA0AbQwAAAIABgDqDAAABgATAG4MAAAFAAoAbwwAAAEAMAAOAAgJggj8WgBMAQhoDAAAAgAOAGkMAAACAAsAawwAAAIABwBqDAAAAwBaAGwMAAACAA0AbQwAAAIABgDqDAAABAATAG4MAAAEAAoADwAICUIHMEsACAEIaAwAAAMAGQBpDAAAAwAUAGsMAAADABIAagwAAAMAHQBsDAAAAwATAOoMAAACAAgAbgwAAAEAEQBvDAAAAQATAAAA.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMRAAcJcRL8PABSAQdoDAAABwBGAGkMAAAGAC8AawwAAAgAHwBqDAAABAAiAGwMAAAFACsA6gwAAAQATwBuDAAAAQAXABEABgn6E/w8AFIBBmgMAAAEAEYAaQwAAAMALwBrDAAABAAfAGoMAAADACIAbAwAAAIAKwDqDAAAAgBPABgABwm3EEegADcBB2gMAAADAFoAaQwAAAMAKgBrDAAABAAoAGoMAAABABYAbAwAAAMALQDqDAAAAgAYAG4MAAABAAwAAAA=.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAFFAUJBwAJAGQUAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8gAAMBAAcJxBOIJAC5AQdoDAAABwBSAGkMAAAGAEQAawwAAAUAMwBqDAAABAAiAGwMAAABABIAbQwAAAEACgDqDAAACABIAAEABwmNE4gkALkBB2gMAAAHAFIAaQwAAAEAQABrDAAABAAzAGoMAAAEACIAbAwAAAEAEgBtDAAAAQAKAOoMAAAIAEgAGQACCcoPXQ0AogACaQwAAAUARABrDAAAAQAMAC4ABAp/MwAEAQAICb4keBsAsAIAAQAICRYjeBsAsAIAGQAFCckiUwwA/QEAGgAECXgeFBgAugAAAAA=.Magewings:BAABLgAECn8WAAIbAAYJkwzqyQD6AAZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAbAAYJkwzqyQD6AAZoDAAABAAoAGkMAAAEAB8AawwAAAQAHABqDAAABAAhAGwMAAACACEA6gwAAAQAGwAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Manitaur:BAAALgAECgEJAQAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn9GAAIcAAkJ1R1hFwCbAgloDAAACQBSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAJAFIAbQwAAAgAVADqDAAACwBNAG4MAAAHAEcAbwwAAAIANgAcAAkJ1R1hFwCbAgloDAAACQBSAGkMAAAIAE4AawwAAAgATwBqDAAACABSAGwMAAAJAFIAbQwAAAgAVADqDAAACwBNAG4MAAAHAEcAbwwAAAIANgAAAA==.',
Mi='Mikayla:BAAALgAECgcJCgAAAA==.Miranda:BAAALgAFFAQJCQABLgAFFAcJIAABAMQTAQ==.Misobeastie:BAAALgAECgYJEAAAAA==.Mixup:BAACLgAFFH8RAAIBAAUJ3RUNTAAuAQVoDAAABAAoAGkMAAAEAE0AawwAAAMAJgBqDAAAAgA5AOoMAAAEAEMAAQAFCd0VDUwALgEFaAwAAAQAKABpDAAABABNAGsMAAADACYAagwAAAIAOQDqDAAABABDAC4ABAp/SwACAQAJCXIgjw8A0AIAAQAJCXIgjw8A0AIAAAA=.',
Mo='Mollan:BAAALgAECgcJDAAAAA==.Monkeys:BAAALgAFFAMJAQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxnSDwAOAgloDAAACQBRAGkMAAAJAFIAawwAAAkAPwBqDAAACABQAGwMAAAIAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAACAAkJtxnSDwAOAgloDAAACABRAGkMAAAIAFIAawwAAAgAPwBqDAAABwBQAGwMAAAHAFoAbQwAAAIAPADqDAAABwBGAG4MAAAFACkAbwwAAAEAJAADAAUJkgoA6QDKAAVoDAAAAQAdAGkMAAABAB0AawwAAAEAIwBqDAAAAQAUAGwMAAABAAwAAAA=.Mythikal:BAABLgAECn8bAAIDAAgJXA8YbQCMAQhoDAAAAwAtAGkMAAADACMAawwAAAMAHwBqDAAABABNAGwMAAAFACgAbQwAAAIARgDqDAAABgAiAG4MAAABABEAAwAICVwPGG0AjAEIaAwAAAMALQBpDAAAAwAjAGsMAAADAB8AagwAAAQATQBsDAAABQAoAG0MAAACAEYA6gwAAAYAIgBuDAAAAQARAAAA.',
Na='Nagini:BAAALgAECgQJBgAAAA==.Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAAdAAAAAA==.',
Ne='Necropheelia:BAAALgAECgEJAQAAAA==.',
No='Notthefather:BAAALgAECgcJDQAAAA==.',
Ot='Otekah:BAABLgAECn8mAAMRAAgJWBhyGgAwAghoDAAABgA5AGkMAAAGAFMAawwAAAYAVABqDAAABQBSAGwMAAADACsAbQwAAAMAMgDqDAAACAAmAG4MAAABADkAEQAICVgYchoAMAIIaAwAAAQAOQBpDAAABQBTAGsMAAAFAFQAagwAAAQAUgBsDAAAAwArAG0MAAADADIA6gwAAAcAJgBuDAAAAQA5ABgABQn8CC0oAYkABWgMAAACACwAaQwAAAEAFQBrDAAAAQAQAGoMAAABABYA6gwAAAEACQAAAA==.',
Ov='Overthereman:BAAALgAECgQJBAABLgAFFAMJBwADAMUTAA==.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8mAAIXAAgJMw5DJABVAQhoDAAABQAeAGkMAAAGACYAawwAAAYALQBqDAAABQAnAGwMAAADACsAbQwAAAMAGADqDAAACAAoAG4MAAACACAAFwAICTMOQyQAVQEIaAwAAAUAHgBpDAAABgAmAGsMAAAGAC0AagwAAAUAJwBsDAAAAwArAG0MAAADABgA6gwAAAgAKABuDAAAAgAgAAAA.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIDAAkJNQzyZACeAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgADAAkJNQzyZACeAQloDAAACAAuAGkMAAAIADcAawwAAAgANABqDAAABwAmAGwMAAAGABEAbQwAAAMAEQDqDAAACQAbAG4MAAAEAAkAbwwAAAEAFgAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQeAAcJfhISQQBpAQdoDAAABQA/AGkMAAAFAEoAawwAAAUARgBqDAAABAA7AGwMAAACAAkAbQwAAAIADQDqDAAABwApAB4ABgm3FBJBAGkBBmgMAAADAD8AaQwAAAMASgBrDAAAAwBGAGoMAAADADsAbAwAAAEACQDqDAAAAwApAAcABwnKDJE3AB4BB2gMAAABABgAaQwAAAEADgBrDAAAAQAnAGoMAAABACgAbAwAAAEAGwBtDAAAAQAaAOoMAAADAEAACAAECXMJvIIAUQAEaAwAAAEAGABpDAAAAQAYAGsMAAABABMA6gwAAAEAGwAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAbAGMPAA==.',
Ro='Roadhouse:BAAALgAECgQJBAAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAABLgAECn8UAAIUAAgJIRSNFwDlAQhoDAAAAwBIAGkMAAADADsAawwAAAMALwBqDAAAAgAqAGwMAAACABIAbQwAAAEAKgDqDAAABQBLAG4MAAABACsAFAAICSEUjRcA5QEIaAwAAAMASABpDAAAAwA7AGsMAAADAC8AagwAAAIAKgBsDAAAAgASAG0MAAABACoA6gwAAAUASwBuDAAAAQArAAAA.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQAdAAAAAA==.Sandaexpress:BAABLgAFFH8HAAIDAAMJxRN3AQBgAANoDAAABABHAGkMAAABACkA6gwAAAIAJgADAAMJxRN3AQBgAANoDAAABABHAGkMAAABACkA6gwAAAIAJgAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIDAAQJYBPuaAAnAQRoDAAAAgA1AGkMAAACADQAawwAAAEACQDqDAAAAgBTAAMABAlgE+5oACcBBGgMAAACADUAaQwAAAIANABrDAAAAQAJAOoMAAACAFMAAAA=.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAMJBwADAMUTAA==.Shme:BAACLgAFFH8QAAIbAAQJ8gsWHgBSAQRoDAAABgAsAGkMAAAFACAAawwAAAEAHgDqDAAABAAOABsABAnyCxYeAFIBBGgMAAAGACwAaQwAAAUAIABrDAAAAQAeAOoMAAAEAA4ALgAECn80AAMbAAgJ1R1RKwDFAgAbAAgJ1R1RKwDFAgAfAAEJihUGHQA4AAAAAA==.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAbAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAUJDQAYADMlAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAUJDQAYADMlAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQAdAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8dAAQEAAgJLgw2TQARAQhoDAAABQAyAGkMAAAFABEAawwAAAYAKgBqDAAAAgAoAGwMAAADABMA6gwAAAMAFgBuDAAABAAYAG8MAAABACgABAAHCSULNk0AEQEHaAwAAAMAMgBpDAAAAwARAGsMAAAEACoAagwAAAIAKABsDAAAAgATAOoMAAACABYAbgwAAAIAEgAGAAUJagbLOACSAAVoDAAAAgApAGkMAAACAAEAawwAAAIACwBsDAAAAQALAOoMAAABAA8ABQACCdQM6VoAbgACbgwAAAIAGABvDAAAAQAoAAAA.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8kAAIOAAcJVBiaMgDoAQdoDAAACgBFAGkMAAAIAE4AawwAAAcARwBqDAAABABMAGwMAAADAEUA6gwAAAMAPgBuDAAAAQAHAA4ABwlUGJoyAOgBB2gMAAAKAEUAaQwAAAgATgBrDAAABwBHAGoMAAAEAEwAbAwAAAMARQDqDAAAAwA+AG4MAAABAAcAAAA=.',
Sy='Syllogica:BAACLgAFFH8XAAIgAAQJQBYvGgBEAQRoDAAABgBCAGkMAAAHADMAawwAAAMAMADqDAAABwA9ACAABAlAFi8aAEQBBGgMAAAGAEIAaQwAAAcAMwBrDAAAAwAwAOoMAAAHAD0ALgAECn8WAAIgAAgJrBD7KABPAQAgAAgJrBD7KABPAQAAAA==.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Tankeybell:BAAALgAECgkJAQAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9WAAILAAkJkCQ1AgCFAwloDAAACwBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAALAGEAbQwAAAoAYQDqDAAADABhAG4MAAAJAFMAbwwAAAMAVQALAAkJkCQ1AgCFAwloDAAACwBZAGkMAAAKAGAAawwAAAoAYgBqDAAACgBgAGwMAAALAGEAbQwAAAoAYQDqDAAADABhAG4MAAAJAFMAbwwAAAMAVQAAAA==.',
Te='Tenderloinz:BAAALgAECgUJEQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Tokkia:BAAALgAECggJCAAAAA==.Toothandclaw:BAAALgADCgMJAwAAAA==.Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIRAAIJdhfZFwCGAAJoDAAABAAzAGkMAAADAEUAEQACCXYX2RcAhgACaAwAAAQAMwBpDAAAAwBFAC4ABAp/KgACEQAICX8iswUAEAMAEQAICX8iswUAEAMAAAA=.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJEQAAAA==.Vaughan:BAACLgAFFH8NAAIYAAUJMyXLFwCwAQVoDAAAAwBjAGkMAAADAGAAawwAAAIAVwBqDAAAAQAxAOoMAAAEAGEAGAAFCTMlyxcAsAEFaAwAAAMAYwBpDAAAAwBgAGsMAAACAFcAagwAAAEAMQDqDAAABABhAC4ABAp/LQACGAAJCaYkVQsACwMAGAAJCaYkVQsACwMAAAA=.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Vy='Vynathenin:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAACLgAFFH8GAAIBAAQJMwaxbwDiAARoDAAAAQAfAGkMAAABABYAawwAAAEABADqDAAAAwAEAAEABAkzBrFvAOIABGgMAAABAB8AaQwAAAEAFgBrDAAAAQAEAOoMAAADAAQALgAECn89AAIBAAgJvBrJNQACAgABAAgJvBrJNQACAgAAAA==.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgAdAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whatacombo:BAAALgAECgYJBwABLgAFFAMJBwADAMUTAA==.Whollycow:BAAALgAFFAEJAQABLgAFFAMJBwADAMUTAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAABLgAFFH8HAAIJAAUJZBRvPwAqAQVoDAAAAgBOAGkMAAABACMAawwAAAEAEgBqDAAAAQAuAOoMAAACAEwACQAFCWQUbz8AKgEFaAwAAAIATgBpDAAAAQAjAGsMAAABABIAagwAAAEALgDqDAAAAgBMAAAA.',
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
