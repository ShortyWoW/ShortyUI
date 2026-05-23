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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Shaman-Enhancement','Hunter-Survival','Priest-Discipline','Priest-Holy','Mage-Fire','Warrior-Fury','Mage-Arcane','Druid-Balance','Priest-Shadow','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-22',data={Aa='Aayu:BAABLgAECn8pAAIBAAgJFRnCNwDQAQhoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoAbQwAAAEAEwDqDAAABwBCAG4MAAAEAEAAAQAICRUZwjcA0AEIaAwAAAcAPwBpDAAACABTAGsMAAAEAE0AagwAAAUAKABsDAAABQBKAG0MAAABABMA6gwAAAcAQgBuDAAABABAAAAA.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUCQkmAAMApSIA.Adranelidk:BAAALgAECgYJDgAAAA==.',
Ae='Aeromina:BAABLgAECn8aAAMBAAcJ/BOYZQBHAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAABQA4AAEABwn8E5hlAEcBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAAFADgABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8ZAAQHAAgJzxxsDQDSAQhoDAAABQBBAGkMAAAEAFoAawwAAAQARQBqDAAAAwBbAGwMAAACAE0AbQwAAAIAIADqDAAABABQAG4MAAABAFIABwAGCfsbbA0A0gEGaAwAAAIAQQBpDAAAAgBaAGsMAAACAEUAagwAAAIAWwBtDAAAAQAgAOoMAAACAFAACAAICdsLqzIAPQEIaAwAAAIAHwBpDAAAAgAyAGsMAAACADcAagwAAAEACQBsDAAAAgAeAG0MAAABABAA6gwAAAIAEwBuDAAAAQAIAAkAAQlGFtA8ADsAAWgMAAABADkAAAA=.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAABLgAECn8YAAIKAAkJXwXU1gDEAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAKAAkJXwXU1gDEAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w/KLABgAQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcACAAICdMPyiwAYAEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAwABLgAFFAMJBAALAIwNAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJEgAMAAAAAA==.Aussilicious:BAAALgAECggJEgAAAA==.',
Az='Azerennia:BAAALgAECgcJCQAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8kAAIBAAgJiAWzewAVAQhoDAAABgASAGkMAAAHAB0AawwAAAcACwBqDAAABQAcAGwMAAAEABgAbQwAAAEAAwDqDAAABQAGAG4MAAABAAYAAQAICYgFs3sAFQEIaAwAAAYAEgBpDAAABwAdAGsMAAAHAAsAagwAAAUAHABsDAAABAAYAG0MAAABAAMA6gwAAAUABgBuDAAAAQAGAAAA.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAMAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJEgAMAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECggJEQAAAA==.Belphegör:BAAALgAECgUJBQAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQANAIQZAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bl='Blindmagg:BAAALgAECgIJAgABLgAECggJEwAMAAAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgcJDAAMAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJBwABLgAECggJEQAMAAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJBwAMAAAAAA==.Bro:BAAALgAECgUJCAAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQANAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAIOAAYJTyTcAQDMAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAOAAYJTyTcAQDMAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfygAAg4ACQnuJcMBAIYDAA4ACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQPAAgJKhhzHQDmAQhoDAAACABWAGkMAAAIAFEAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwADwAHCQ8acx0A5gEHaAwAAAYAVgBpDAAABgBRAGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAAQAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4AEQABCdwOHn8AMgABbAwAAAEAJgAAAA==.Cartheron:BAAALgAECgkJAQAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAMAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8oAAIKAAkJSh2THQCOAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAKAAkJSh2THQCOAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8WAAIRAAUJwCUiAwC7AQVoDAAABwBiAGkMAAAGAGMAawwAAAMAXQBqDAAAAQBCAOoMAAAFAF4AEQAFCcAlIgMAuwEFaAwAAAcAYgBpDAAABgBjAGsMAAADAF0AagwAAAEAQgDqDAAABQBeAC4ABAp/LgADEQAJCd4jTwQA8gIAEQAJCd4jTwQA8gIAEAABCToDiY8AJgAAAAA=.Divinefistin:BAECLgAFFH8IAAIQAAMJqxs7IQAKAQNoDAAAAwBCAGkMAAACADIA6gwAAAMAXwAQAAMJqxs7IQAKAQNoDAAAAwBCAGkMAAACADIA6gwAAAMAXwAuAAQKfzYAAxAACQmMIl8KAG8CABAACQnLHV8KAG8CABEABwkPIn8OADUCAAAA.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8PAAISAAYJKxrsCABfAQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAMAQAASAAYJKxrsCABfAQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAMAQAAuAAQKfzMAAxIACQl8HswCADgDABIACQl8HswCADgDABMAAQkAADBuAAAAAAAA.',
El='Elfuego:BAAALgAECgYJCgAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgcJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8aAAIGAAgJIRXsSQDHAQhoDAAABAAzAGkMAAAEAEwAawwAAAQALwBqDAAAAwAlAGwMAAADABsAbQwAAAEAQADqDAAABABDAG4MAAADACsABgAICSEV7EkAxwEIaAwAAAQAMwBpDAAABABMAGsMAAAEAC8AagwAAAMAJQBsDAAAAwAbAG0MAAABAEAA6gwAAAQAQwBuDAAAAwArAAAA.',
Fe='Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAABLgAECn8VAAIFAAcJBAU1EAD9AAdoDAAAAwANAGkMAAADABEAawwAAAMADQBqDAAAAgASAGwMAAAEAAsA6gwAAAQACwBuDAAAAgAJAAUABwkEBTUQAP0AB2gMAAADAA0AaQwAAAMAEQBrDAAAAwANAGoMAAACABIAbAwAAAQACwDqDAAABAALAG4MAAACAAkAAAA=.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBgAAAA==.Ganzar:BAACLgAFFH8KAAIUAAMJUSSORAA7AQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAUAAMJUSSORAA7AQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAuAAQKfyQAAhQACQkpIHkJAAYDABQACQkpIHkJAAYDAAAA.Gathan:BAAALgADCgcJEAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8nAAMGAAgJCRHVfwBLAQhoDAAACAAnAGkMAAAHADYAawwAAAcALQBqDAAABQA1AGwMAAAEAB8AbQwAAAEASADqDAAABgAeAG4MAAABAB4ABgAHCSIP1X8ASwEHaAwAAAgAJwBpDAAABwA2AGsMAAAHAC0AagwAAAUANQBsDAAABAAfAOoMAAAGAB4AbgwAAAEAHgAVAAEJIQPIgAArAAFtDAAAAQAIAAAA.Gertrex:BAAALgAECggJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgcJDwAAAA==.',
Go='Goatlord:BAABLgAECn8cAAIWAAgJdQ7BEABmAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABQAoAG4MAAADADgAFgAICXUOwRAAZgEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAUAKABuDAAAAwA4AAAA.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgcJDwAAAA==.Gotharm:BAABLgAECn8ZAAIXAAgJQQztGwCcAQhoDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAFwAICUEM7RsAnAEIaAwAAAUAJABpDAAABQAcAGsMAAADACcAagwAAAEABQBsDAAAAgAgAG0MAAABABIA6gwAAAcAJwBuDAAAAQAYAAAA.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJDAAAAA==.',
Ha='Hahmicydal:BAAALgAECgYJEgAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAACLgAFFH8HAAIOAAMJKgycEQDVAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAOAAMJKgycEQDVAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAuAAQKfxoAAg4ACQlnHtAHAIQCAA4ACQlnHtAHAIQCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIYAAcJmw0SKQBWAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABgABwmbDRIpAFYBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8QAAIVAAUJKQq1FwA1AQVoDAAABgAoAGkMAAAFACcAawwAAAIAAwBqDAAAAQADAOoMAAACACsAFQAFCSkKtRcANQEFaAwAAAYAKABpDAAABQAnAGsMAAACAAMAagwAAAEAAwDqDAAAAgArAC4ABAp/LAACFQAJCSoX8hUAMQIAFQAJCSoX8hUAMQIAAAA=.Holyhand:BAABLgAECn8UAAIZAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAZAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAUJEAAVACkKAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJEwAMAAAAAA==.',
Il='Ilin:BAAALgAECgYJBwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8pAAIaAAkJsxQ9AgAMAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAIAPQAaAAkJsxQ9AgAMAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAIAPQABLgAECggJFgAbAM0WAA==.',
Is='Isabela:BAABLgAFFH8IAAILAAIJsyQnSgDWAAJoDAAABABaAOoMAAAEAGEACwACCbMkJ0oA1gACaAwAAAQAWgDqDAAABABhAAAA.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgEJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJFgARAMAlAA==.Judyhopp:BAABLgAECn8aAAQcAAgJWhYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAHAAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAKAAcJFxORkgA2AQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABoAAQkAAF0RAAAAAWoMAAACAEAAAS4ABRQFCRYAEQDAJQA=.Judyhopps:BAAALgAECgYJDAABLgAFFAUJFgARAMAlAA==.',
Ka='Kaeln:BAAALgAFFAMJAwAAAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgMJAwAAAA==.Kalzak:BAAALgAECggJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJEgAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJFgANALkTAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECggJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAMAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgcJDwABLgAECggJEQAMAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECggJEQAMAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJEQAAAA==.',
Li='Lidravos:BAAALgADCgYJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwUiWQC+AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwUiWQC+AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABUABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJEQAEAKUVAA==.',
Ll='Lluvioso:BAACLgAFFH8KAAMUAAMJRh49ZQD8AANoDAAAAwBKAGkMAAACAEYA6gwAAAUAVwAUAAMJeR09ZQD8AANoDAAAAwBKAGkMAAACAEYA6gwAAAMAUAACAAEJ/iExKABaAAHqDAAAAgBXAC4ABAp/IwADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAFAABCQ4f+xABVwAAAAA=.',
Lo='Loaf:BAAALgAECgYJCwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIdAAcJeBwhHAC3AQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJAB0ABwl4HCEcALcBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgcJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8XAAIKAAcJ6AlhkwA1AQdoDAAABQAhAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAAEABwAbQwAAAEAEwDqDAAABQAXAAoABwnoCWGTADUBB2gMAAAFACEAaQwAAAMAEwBrDAAAAwAbAGoMAAACACQAbAwAAAQAHABtDAAAAQATAOoMAAAFABcAAAA=.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAMAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJBwAMAAAAAA==.Merien:BAAALgAECgUJEgAAAA==.Meros:BAAALgAECgYJDgAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJEgAMAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBQAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECggJEAAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAQAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJCgABLgAECgkJSQAKAOcZAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAAALgAECgcJEQAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8ZAAIKAAgJPxWhTgDRAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAABAAwAGwMAAAGADwAbQwAAAEAJADqDAAAAwBLAG4MAAABADUACgAICT8VoU4A0QEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAQAMABsDAAABgA8AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAABLgAECn8YAAIYAAcJFg2xKABZAQdoDAAABQAzAGkMAAAEABMAawwAAAQAIgBqDAAAAgAsAGwMAAACAA0AbQwAAAIADQDqDAAABQA6ABgABwkWDbEoAFkBB2gMAAAFADMAaQwAAAQAEwBrDAAABAAiAGoMAAACACwAbAwAAAIADQBtDAAAAgANAOoMAAAFADoAAAA=.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8YAAIKAAcJcB2sCQA+AgdoDAAABQBdAGkMAAAFAGMAawwAAAQAUwBqDAAAAwBgAGwMAAACABoA6gwAAAQAPgBuDAAAAQBVAAoABwlwHawJAD4CB2gMAAAFAF0AaQwAAAUAYwBrDAAABABTAGoMAAADAGAAbAwAAAIAGgDqDAAABAA+AG4MAAABAFUALgAECn8nAAMKAAgJYCKdGAAXAwAKAAgJYCKdGAAXAwAaAAEJAAAdEQAuAAAAAA==.Powerwordhug:BAABLgAECn8tAAIZAAkJnx0ICQCzAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAZAAkJnx0ICQCzAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAAAA==.',
Pr='Proctolodin:BAABLgAECn8eAAIGAAgJPBIUYwCHAQhoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAFAC4AbQwAAAMAKADqDAAABQAzAG4MAAABAA4ABgAICTwSFGMAhwEIaAwAAAQAQwBpDAAABAAzAGsMAAAEADQAagwAAAQAJABsDAAABQAuAG0MAAADACgA6gwAAAUAMwBuDAAAAQAOAAAA.',
Pu='Purplefart:BAABLgAECn8eAAMeAAgJSBPdIgCGAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABgA8AG4MAAACACEAHgAICUgT3SIAhgEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAYAPABuDAAAAgAhABgAAQk/G2dYAE0AAWoMAAABAEUAAAA=.',
Ql='Qlaryx:BAAALgAECggJEQAAAA==.',
Qu='Quinner:BAACLgAFFH8HAAIIAAMJqhBDMADTAANoDAAAAwAzAGkMAAACAEAA6gwAAAIACwAIAAMJqhBDMADTAANoDAAAAwAzAGkMAAACAEAA6gwAAAIACwAuAAQKfzIABAgACQneG/oKAIkCAAgACQneG/oKAIkCAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIfAAgJxh1jFADXAQhoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8AHwAICcYdYxQA1wEIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIKAAYJRxxYdAByAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAKAAYJRxxYdAByAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJFwAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgMJCAABLgAFFAMJCgAKAMcfAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDwAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMgAAgJxxINSwChAQhoDAAACQA8AGkMAAAJADUAawwAAAkAMABqDAAABwA6AGwMAAAIADUAbQwAAAQAMADqDAAABwAlAG4MAAADACIAIAAICVkSDUsAoQEIaAwAAAkAPABpDAAACAA1AGsMAAAIADAAagwAAAYAOgBsDAAABwAtAG0MAAAEADAA6gwAAAcAJQBuDAAAAwAiACEABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECggJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8VAAMUAAYJ9Ar/tQDhAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAwAtAGwMAAADAB0A6gwAAAMAJQAUAAYJkwn/tQDhAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAMJNQ1mRABMAANqDAAAAQAtAGwMAAABAB0A6gwAAAEAJQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECggJEwAMAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAMAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g/keAAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g/keAAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Sita:BAAALgADCgcJDwAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECggJHgAGADwSAA==.',
So='Sofferenza:BAAALgADCgcJEQAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8rAAMgAAkJARYtJQAtAgloDAAABwA6AGkMAAAHAEcAawwAAAcANgBqDAAABAAnAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAgAAkJwBUtJQAtAgloDAAABwA6AGkMAAAGAEIAawwAAAYANgBqDAAAAQAeAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAiAAMJQA6oKQBXAANpDAAAAQBHAGsMAAABAAEAagwAAAMAJwAAAA==.',
Sp='Spaceguy:BAABLgAECn8gAAINAAcJGQiBRgDlAAdoDAAABQAkAGkMAAAFACIAawwAAAUADQBqDAAABAAPAGwMAAAFAAkA6gwAAAYAFwBuDAAAAgAGAA0ABwkZCIFGAOUAB2gMAAAFACQAaQwAAAUAIgBrDAAABQANAGoMAAAEAA8AbAwAAAUACQDqDAAABgAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECgkJJAAQANgNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAjAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgIJBgAMAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgcJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECgYJBwAMAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIeAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAeAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECggJEwAAAA==.',
Te='Tenshiro:BAAALgADCgYJCwAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAQAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAUJEAAVACkKAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8UAAIPAAYJXBCXDwCaAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAPAAYJXBCXDwCaAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAuAAQKfyMAAg8ACQnmIBAEAEoDAA8ACQnmIBAEAEoDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJEAAAAA==.',
Ve='Veldaan:BAAALgADCgcJCwAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJEwAMAAAAAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECgcJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJEwAMAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgYJEgAAAA==.Whiteleaf:BAABLgAECn8XAAIbAAcJhgnPPgAeAQdoDAAAAwAaAGkMAAADABsAawwAAAMADgBqDAAAAwATAGwMAAAEAB8A6gwAAAUAGABuDAAAAgAVABsABwmGCc8+AB4BB2gMAAADABoAaQwAAAMAGwBrDAAAAwAOAGoMAAADABMAbAwAAAQAHwDqDAAABQAYAG4MAAACABUAAAA=.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJEAAMAAAAAA==.',
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
