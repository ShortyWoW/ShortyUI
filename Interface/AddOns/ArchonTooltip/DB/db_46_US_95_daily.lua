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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Rogue-Assassination','DeathKnight-Unholy','Paladin-Holy','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Discipline','Priest-Holy','Mage-Fire','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Priest-Shadow','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-24',data={Aa='Aayu:BAABLgAECn8pAAIBAAgJFRmaOgDLAQhoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoAbQwAAAEAEwDqDAAABwBCAG4MAAAEAEAAAQAICRUZmjoAywEIaAwAAAcAPwBpDAAACABTAGsMAAAEAE0AagwAAAUAKABsDAAABQBKAG0MAAABABMA6gwAAAcAQgBuDAAABABAAAAA.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUCQkmAAMApSIA.Adranelidk:BAAALgAECgYJDgAAAA==.',
Ae='Aeromina:BAABLgAECn8aAAMBAAcJ/BOHaABGAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAABQA4AAEABwn8E4doAEYBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAAFADgABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgAAAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIFAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABQAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8ZAAQGAAgJzxzKDQDRAQhoDAAABQBBAGkMAAAEAFoAawwAAAQARQBqDAAAAwBbAGwMAAACAE0AbQwAAAIAIADqDAAABABQAG4MAAABAFIABgAGCfsbyg0A0QEGaAwAAAIAQQBpDAAAAgBaAGsMAAACAEUAagwAAAIAWwBtDAAAAQAgAOoMAAACAFAABwAICdsL5jMAPQEIaAwAAAIAHwBpDAAAAgAyAGsMAAACADcAagwAAAEACQBsDAAAAgAeAG0MAAABABAA6gwAAAIAEwBuDAAAAQAIAAgAAQlGFtA8ADsAAWgMAAABADkAAAA=.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAABLgAECn8YAAIJAAkJXwWz2wDCAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAJAAkJXwWz2wDCAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIHAAgJ0w/PLQBgAQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcABwAICdMPzy0AYAEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAwABLgAFFAQJDwAKABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJEgALAAAAAA==.Aussilicious:BAAALgAECggJEgAAAA==.',
Az='Azerennia:BAAALgAECgcJCQAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8kAAIBAAgJiAWDgAASAQhoDAAABgASAGkMAAAHAB0AawwAAAcACwBqDAAABQAcAGwMAAAEABgAbQwAAAEAAwDqDAAABQAGAG4MAAABAAYAAQAICYgFg4AAEgEIaAwAAAYAEgBpDAAABwAdAGsMAAAHAAsAagwAAAUAHABsDAAABAAYAG0MAAABAAMA6gwAAAUABgBuDAAAAQAGAAAA.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAALAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJEgALAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECggJEQAAAA==.Belphegör:BAAALgAECgYJBwAAAA==.Bencicil:BAAALgAECgYJDgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQAMAIQZAA==.Beydoon:BAAALgAECgIJBAAAAA==.',
Bl='Blindmagg:BAAALgAECgIJAgABLgAECggJEwALAAAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgcJDAALAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJBwABLgAECggJEQALAAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJBwALAAAAAA==.Bro:BAAALgAECgUJCAAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQAMAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAINAAYJTyQmAgDJAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAANAAYJTyQmAgDJAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfygAAg0ACQnuJcMBAIYDAA0ACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQOAAgJKhjLHgDmAQhoDAAACABWAGkMAAAIAFEAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwADgAHCQ8ayx4A5gEHaAwAAAYAVgBpDAAABgBRAGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAAPAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4AEAABCdwO5IIAMgABbAwAAAEAJgAAAA==.Cartheron:BAAALgAECgkJAQAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgALAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8oAAIJAAkJSh22HgCMAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAJAAkJSh22HgCMAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8WAAIQAAUJwCVZAwC6AQVoDAAABwBiAGkMAAAGAGMAawwAAAMAXQBqDAAAAQBCAOoMAAAFAF4AEAAFCcAlWQMAugEFaAwAAAcAYgBpDAAABgBjAGsMAAADAF0AagwAAAEAQgDqDAAABQBeAC4ABAp/LgADEAAJCd4jiAQA8AIAEAAJCd4jiAQA8AIADwABCToDiY8AJgAAAAA=.Divinefistin:BAECLgAFFH8IAAIPAAMJqxuOIgAIAQNoDAAAAwBCAGkMAAACADIA6gwAAAMAXwAPAAMJqxuOIgAIAQNoDAAAAwBCAGkMAAACADIA6gwAAAMAXwAuAAQKfzYAAw8ACQmMIqkKAG0CAA8ACQnLHakKAG0CABAABwkPIvMOADQCAAAA.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8PAAIRAAYJKxqpCQBcAQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAMAQAARAAYJKxqpCQBcAQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAMAQAAuAAQKfzMAAxEACQl8HswCADgDABEACQl8HswCADgDABIAAQkAAEtyAAAAAAAA.',
El='Elfuego:BAAALgAECgYJCgAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8aAAIFAAgJIRWZTADEAQhoDAAABAAzAGkMAAAEAEwAawwAAAQALwBqDAAAAwAlAGwMAAADABsAbQwAAAEAQADqDAAABABDAG4MAAADACsABQAICSEVmUwAxAEIaAwAAAQAMwBpDAAABABMAGsMAAAEAC8AagwAAAMAJQBsDAAAAwAbAG0MAAABAEAA6gwAAAQAQwBuDAAAAwArAAAA.',
Fe='Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAABLgAECn8VAAITAAcJBAWVEAD9AAdoDAAAAwANAGkMAAADABEAawwAAAMADQBqDAAAAgASAGwMAAAEAAsA6gwAAAQACwBuDAAAAgAJABMABwkEBZUQAP0AB2gMAAADAA0AaQwAAAMAEQBrDAAAAwANAGoMAAACABIAbAwAAAQACwDqDAAABAALAG4MAAACAAkAAAA=.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwALAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBgAAAA==.Ganzar:BAACLgAFFH8KAAIUAAMJUSTRSAA5AQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAUAAMJUSTRSAA5AQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAuAAQKfyQAAhQACQkpIBIKAAQDABQACQkpIBIKAAQDAAAA.Gathan:BAAALgADCgcJEAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8nAAMFAAgJCRFRhABIAQhoDAAACAAnAGkMAAAHADYAawwAAAcALQBqDAAABQA1AGwMAAAEAB8AbQwAAAEASADqDAAABgAeAG4MAAABAB4ABQAHCSIPUYQASAEHaAwAAAgAJwBpDAAABwA2AGsMAAAHAC0AagwAAAUANQBsDAAABAAfAOoMAAAGAB4AbgwAAAEAHgAVAAEJIQNfgwArAAFtDAAAAQAIAAAA.Gertrex:BAAALgAECggJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8cAAIWAAgJdQ5kEQBlAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABQAoAG4MAAADADgAFgAICXUOZBEAZQEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAUAKABuDAAAAwA4AAAA.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8aAAIXAAkJKwwJFQDiAQloDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAbwwAAAEAHQAXAAkJKwwJFQDiAQloDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAbwwAAAEAHQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJDAAAAA==.',
Ha='Hahmicydal:BAABLgAECn8XAAQYAAYJHgduHACjAAZoDAAABQAUAGkMAAAEABYAawwAAAUAEQBqDAAAAwAXAGwMAAABAAMA6gwAAAUAGQAYAAYJXwZuHACjAAZoDAAAAQAKAGkMAAADABYAawwAAAMAEQBqDAAAAgAXAGwMAAABAAMA6gwAAAMAGQAZAAUJrgW1HgB7AAVoDAAABAAUAGkMAAABABUAawwAAAEABQBqDAAAAQARAOoMAAACAAoAGgABCeYBTzwBFwABawwAAAEABAAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAACLgAFFH8HAAINAAMJKgyNEgDUAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwANAAMJKgyNEgDUAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAuAAQKfxoAAg0ACQlnHjAIAIECAA0ACQlnHjAIAIECAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIbAAcJmw2LKgBUAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABsABwmbDYsqAFQBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8QAAIVAAUJKQpBGQApAQVoDAAABgAoAGkMAAAFACcAawwAAAIAAwBqDAAAAQADAOoMAAACACsAFQAFCSkKQRkAKQEFaAwAAAYAKABpDAAABQAnAGsMAAACAAMAagwAAAEAAwDqDAAAAgArAC4ABAp/LAACFQAJCSoXvhYAMAIAFQAJCSoXvhYAMAIAAAA=.Holyhand:BAABLgAECn8UAAIcAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAcAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAUJEAAVACkKAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJEwALAAAAAA==.',
Il='Ilin:BAAALgAECgYJBwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8tAAIdAAkJTBb+AQAsAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAHAC8AbQwAAAUANwDqDAAABgA5AG4MAAAFAEoAbwwAAAMAPQAdAAkJTBb+AQAsAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAHAC8AbQwAAAUANwDqDAAABgA5AG4MAAAFAEoAbwwAAAMAPQABLgAECggJFgAeAM0WAA==.',
Is='Isabela:BAABLgAFFH8IAAIfAAIJsyTITADVAAJoDAAABABaAOoMAAAEAGEAHwACCbMkyEwA1QACaAwAAAQAWgDqDAAABABhAAAA.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgEJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJFgAQAMAlAA==.Judyhopp:BAABLgAECn8aAAQgAAgJWhYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAIAAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAJAAcJFxPdlQA0AQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7AB0AAQkAAPoRAAAAAWoMAAACAEAAAS4ABRQFCRYAEADAJQA=.Judyhopps:BAAALgAECgYJDAABLgAFFAUJFgAQAMAlAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAQJCwAgAHkTAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgADCgMJAwABLgAFFAYJGgAcAO0bAA==.Kaluanights:BAAALgADCgMJAwAAAA==.Kalzak:BAAALgAECggJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJEgAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJGgAMAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECggJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAALAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgkJDwABLgAECggJEQALAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECggJEQALAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJEQAAAA==.',
Li='Lidravos:BAAALgADCgYJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIFAAMJPwW8XQC9AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAFAAMJPwW8XQC9AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwUACAlYHCQqAHwCAAUACAlYHCQqAHwCABUABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJEQAEAKUVAA==.',
Ll='Lluvioso:BAACLgAFFH8KAAMUAAMJRh7AaQD7AANoDAAAAwBKAGkMAAACAEYA6gwAAAUAVwAUAAMJeR3AaQD7AANoDAAAAwBKAGkMAAACAEYA6gwAAAMAUAACAAEJ/iEiKgBZAAHqDAAAAgBXAC4ABAp/IwADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAFAABCQ4fqRcBVgAAAAA=.',
Lo='Loaf:BAAALgAECgYJCwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIhAAcJeBzkHAC3AQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJACEABwl4HOQcALcBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8XAAIJAAcJ6AnylgAyAQdoDAAABQAhAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAAEABwAbQwAAAEAEwDqDAAABQAXAAkABwnoCfKWADIBB2gMAAAFACEAaQwAAAMAEwBrDAAAAwAbAGoMAAACACQAbAwAAAQAHABtDAAAAQATAOoMAAAFABcAAAA=.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwALAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJBwALAAAAAA==.Merien:BAABLgAECn8YAAIBAAYJfAf5jgDyAAZoDAAABgAWAGkMAAAFAB0AawwAAAUAEwBqDAAAAgAbAGwMAAABAA0A6gwAAAUACwABAAYJfAf5jgDyAAZoDAAABgAWAGkMAAAFAB0AawwAAAUAEwBqDAAAAgAbAGwMAAABAA0A6gwAAAUACwAAAA==.Meros:BAAALgAECgYJDgAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJEgALAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBQAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECggJEAAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJCgABLgAECgkJSQAJAOcZAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAABLgAECn8YAAIZAAgJ6RIICAC4AQhoDAAABAA6AGkMAAAEADIAawwAAAQAMQBqDAAABABDAGwMAAADADUAbQwAAAEAMwDqDAAAAwA9AG4MAAABAA0AGQAICekSCAgAuAEIaAwAAAQAOgBpDAAABAAyAGsMAAAEADEAagwAAAQAQwBsDAAAAwA1AG0MAAABADMA6gwAAAMAPQBuDAAAAQANAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8ZAAIJAAgJPxXsUADPAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAABAAwAGwMAAAGADwAbQwAAAEAJADqDAAAAwBLAG4MAAABADUACQAICT8V7FAAzwEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAQAMABsDAAABgA8AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAABLgAECn8YAAIbAAcJFg0uKgBWAQdoDAAABQAzAGkMAAAEABMAawwAAAQAIgBqDAAAAgAsAGwMAAACAA0AbQwAAAIADQDqDAAABQA6ABsABwkWDS4qAFYBB2gMAAAFADMAaQwAAAQAEwBrDAAABAAiAGoMAAACACwAbAwAAAIADQBtDAAAAgANAOoMAAAFADoAAAA=.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAIJAAgJUxx2BACTAghoDAAABgBdAGkMAAAFAGMAawwAAAQAUwBqDAAAAwBgAGwMAAADAEAAbQwAAAEAEQDqDAAABAA+AG4MAAACAFUACQAICVMcdgQAkwIIaAwAAAYAXQBpDAAABQBjAGsMAAAEAFMAagwAAAMAYABsDAAAAwBAAG0MAAABABEA6gwAAAQAPgBuDAAAAgBVAC4ABAp/JwADCQAICWAinRgAFwMACQAICWAinRgAFwMAHQABCQAAHREALgAAAAA=.Powerwordhug:BAABLgAECn8tAAIcAAkJnx1iCQCwAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAcAAkJnx1iCQCwAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAAAA==.',
Pr='Proctolodin:BAABLgAECn8eAAIFAAgJPBL7ZgCDAQhoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAFAC4AbQwAAAMAKADqDAAABQAzAG4MAAABAA4ABQAICTwS+2YAgwEIaAwAAAQAQwBpDAAABAAzAGsMAAAEADQAagwAAAQAJABsDAAABQAuAG0MAAADACgA6gwAAAUAMwBuDAAAAQAOAAAA.',
Pu='Purplefart:BAABLgAECn8eAAMiAAgJSBMBJACDAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABgA8AG4MAAACACEAIgAICUgTASQAgwEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAYAPABuDAAAAgAhABsAAQk/GyFbAE0AAWoMAAABAEUAAAA=.',
Ql='Qlaryx:BAAALgAECggJEQAAAA==.',
Qu='Quinner:BAACLgAFFH8HAAIHAAMJqhCJMgDMAANoDAAAAwAzAGkMAAACAEAA6gwAAAIACwAHAAMJqhCJMgDMAANoDAAAAwAzAGkMAAACAEAA6gwAAAIACwAuAAQKfzIABAcACQneG1kLAIkCAAcACQneG1kLAIkCAAYABAm+BTo3ALIAAAgAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIKAAgJxh0iFQDTAQhoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8ACgAICcYdIhUA0wEIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIJAAYJRxzfdgBwAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAJAAYJRxzfdgBwAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJFwAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgMJCAABLgAFFAMJCgAJAMcfAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDwAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECggJEgALAAAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMaAAgJxxIeTQCfAQhoDAAACQA8AGkMAAAJADUAawwAAAkAMABqDAAABwA6AGwMAAAIADUAbQwAAAQAMADqDAAABwAlAG4MAAADACIAGgAICVkSHk0AnwEIaAwAAAkAPABpDAAACAA1AGsMAAAIADAAagwAAAYAOgBsDAAABwAtAG0MAAAEADAA6gwAAAcAJQBuDAAAAwAiABkABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECggJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8bAAMCAAYJFg2NLQDEAAZoDAAABQAhAGkMAAAFABkAawwAAAUAFwBqDAAABAAtAGwMAAAEACMA6gwAAAQAMQAUAAYJkwmyuwDdAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAYJKwuNLQDEAAZoDAAAAQAhAGkMAAABAAEAawwAAAEAFwBqDAAAAgAtAGwMAAACACMA6gwAAAIAMQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECggJEwALAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAALAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g+EfAAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g+EfAAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Silren:BAAALgAECgEJAQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECggJHgAFADwSAA==.',
So='Sofferenza:BAAALgADCgcJFwAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8rAAMaAAkJARaQJgArAgloDAAABwA6AGkMAAAHAEcAawwAAAcANgBqDAAABAAnAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAaAAkJwBWQJgArAgloDAAABwA6AGkMAAAGAEIAawwAAAYANgBqDAAAAQAeAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAYAAMJQA53KgBXAANpDAAAAQBHAGsMAAABAAEAagwAAAMAJwAAAA==.',
Sp='Spaceguy:BAABLgAECn8gAAIMAAcJGQhiSADlAAdoDAAABQAkAGkMAAAFACIAawwAAAUADQBqDAAABAAPAGwMAAAFAAkA6gwAAAYAFwBuDAAAAgAGAAwABwkZCGJIAOUAB2gMAAAFACQAaQwAAAUAIgBrDAAABQANAGoMAAAEAA8AbAwAAAUACQDqDAAABgAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECgkJJAAPANgNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAjAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgIJBgALAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgcJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECgYJBwALAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Talie:BAAALgADCgUJBQAAAA==.Taliria:BAABLgAECn8eAAIiAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAiAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECggJEwAAAA==.',
Te='Tenshiro:BAAALgADCgYJCwAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAECgUJBQAAAA==.',
To='Toblakai:BAAALgADCgUJBQABLgAECgkJAQALAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAQAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAUJEAAVACkKAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAHANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8UAAIOAAYJXBDjEACYAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAOAAYJXBDjEACYAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAuAAQKfyMAAg4ACQnmIDwEAEoDAA4ACQnmIDwEAEoDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJEAAAAA==.',
Ve='Veldaan:BAAALgADCgcJDAAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJEwALAAAAAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECgcJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgADCgIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJEwALAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8UAAIkAAYJEgg8bgDLAAZoDAAABQAhAGkMAAAGADEAawwAAAQADgBqDAAAAQAQAGwMAAABAAMA6gwAAAMABgAkAAYJEgg8bgDLAAZoDAAABQAhAGkMAAAGADEAawwAAAQADgBqDAAAAQAQAGwMAAABAAMA6gwAAAMABgAAAA==.Whiteleaf:BAABLgAECn8XAAIeAAcJhgmeQAAdAQdoDAAAAwAaAGkMAAADABsAawwAAAMADgBqDAAAAwATAGwMAAAEAB8A6gwAAAUAGABuDAAAAgAVAB4ABwmGCZ5AAB0BB2gMAAADABoAaQwAAAMAGwBrDAAAAwAOAGoMAAADABMAbAwAAAQAHwDqDAAABQAYAG4MAAACABUAAAA=.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJEAALAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgMJBAAAAA==.',
Xe='Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
Ze='Zeradias:BAAALgADCgYJBgAAAA==.',
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
