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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Discipline','Priest-Holy','Mage-Fire','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Priest-Shadow','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-26',data={Aa='Aayu:BAABLgAECn8pAAIBAAgJFRmaPADJAQhoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoAbQwAAAEAEwDqDAAABwBCAG4MAAAEAEAAAQAICRUZmjwAyQEIaAwAAAcAPwBpDAAACABTAGsMAAAEAE0AagwAAAUAKABsDAAABQBKAG0MAAABABMA6gwAAAcAQgBuDAAABABAAAAA.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUCQkmAAMApSIA.Adranelidk:BAAALgAECgYJDgAAAA==.',
Ae='Aeromina:BAABLgAECn8aAAMBAAcJ/BNfawBGAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAABQA4AAEABwn8E19rAEYBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAAFADgABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8ZAAQHAAgJzxwJDgDRAQhoDAAABQBBAGkMAAAEAFoAawwAAAQARQBqDAAAAwBbAGwMAAACAE0AbQwAAAIAIADqDAAABABQAG4MAAABAFIABwAGCfsbCQ4A0QEGaAwAAAIAQQBpDAAAAgBaAGsMAAACAEUAagwAAAIAWwBtDAAAAQAgAOoMAAACAFAACAAICdsLAzUAPQEIaAwAAAIAHwBpDAAAAgAyAGsMAAACADcAagwAAAEACQBsDAAAAgAeAG0MAAABABAA6gwAAAIAEwBuDAAAAQAIAAkAAQlGFtA8ADsAAWgMAAABADkAAAA=.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAABLgAECn8YAAIKAAkJXwUg3wDBAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAKAAkJXwUg3wDBAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w+1LgBgAQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcACAAICdMPtS4AYAEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJBAABLgAFFAQJDwALABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJEgAMAAAAAA==.Aussilicious:BAAALgAECggJEgAAAA==.',
Az='Azerennia:BAAALgAECgcJCQAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8kAAIBAAgJiAW0gwASAQhoDAAABgASAGkMAAAHAB0AawwAAAcACwBqDAAABQAcAGwMAAAEABgAbQwAAAEAAwDqDAAABQAGAG4MAAABAAYAAQAICYgFtIMAEgEIaAwAAAYAEgBpDAAABwAdAGsMAAAHAAsAagwAAAUAHABsDAAABAAYAG0MAAABAAMA6gwAAAUABgBuDAAAAQAGAAAA.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAMAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJEgAMAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECggJEQAAAA==.Belphegör:BAAALgAECgYJBwAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQANAIQZAA==.Beydoon:BAAALgAECgMJBQAAAA==.',
Bl='Blindmagg:BAAALgAECgIJAgABLgAECggJEwAMAAAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgcJDAAMAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJBwABLgAECggJEQAMAAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAAMAAAAAA==.Bro:BAAALgAECgUJCAAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQANAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAIOAAYJTyQPAQCuAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAOAAYJTyQPAQCuAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfygAAg4ACQnuJcMBAIYDAA4ACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQPAAgJKhjWHwDmAQhoDAAACABWAGkMAAAIAFEAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwADwAHCQ8a1h8A5gEHaAwAAAYAVgBpDAAABgBRAGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAAQAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4AEQABCdwOQIYAMgABbAwAAAEAJgAAAA==.Cartheron:BAAALgAECgkJAQAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAMAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAABLgAECn8oAAIKAAkJSh24HwCLAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAKAAkJSh24HwCLAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8WAAIRAAUJwCWzAwC5AQVoDAAABwBiAGkMAAAGAGMAawwAAAMAXQBqDAAAAQBCAOoMAAAFAF4AEQAFCcAlswMAuQEFaAwAAAcAYgBpDAAABgBjAGsMAAADAF0AagwAAAEAQgDqDAAABQBeAC4ABAp/LgADEQAJCd4jzgQA7wIAEQAJCd4jzgQA7wIAEAABCToDiY8AJgAAAAA=.Divinefistin:BAECLgAFFH8IAAIQAAMJqxvJIwAHAQNoDAAAAwBCAGkMAAACADIA6gwAAAMAXwAQAAMJqxvJIwAHAQNoDAAAAwBCAGkMAAACADIA6gwAAAMAXwAuAAQKfzYAAxAACQmMIvYKAGwCABAACQnLHfYKAGwCABEABwkPIl0PADQCAAAA.Divinepain:BAEALgAECgIJAgABLgAFFAMJCAAQAKsbAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8PAAISAAYJKxpcCgBYAQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAMAQAASAAYJKxpcCgBYAQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAMAQAAuAAQKfzMAAxIACQl8HswCADgDABIACQl8HswCADgDABMAAQkAAOt1AAAAAAAA.',
El='Elfuego:BAAALgAECgYJCgAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8aAAIGAAgJIRXcTgDEAQhoDAAABAAzAGkMAAAEAEwAawwAAAQALwBqDAAAAwAlAGwMAAADABsAbQwAAAEAQADqDAAABABDAG4MAAADACsABgAICSEV3E4AxAEIaAwAAAQAMwBpDAAABABMAGsMAAAEAC8AagwAAAMAJQBsDAAAAwAbAG0MAAABAEAA6gwAAAQAQwBuDAAAAwArAAAA.Fatima:BAAALgAECgEJAQAAAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAABLgAECn8VAAIFAAcJBAXvEAD8AAdoDAAAAwANAGkMAAADABEAawwAAAMADQBqDAAAAgASAGwMAAAEAAsA6gwAAAQACwBuDAAAAgAJAAUABwkEBe8QAPwAB2gMAAADAA0AaQwAAAMAEQBrDAAAAwANAGoMAAACABIAbAwAAAQACwDqDAAABAALAG4MAAACAAkAAAA=.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAMAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBgAAAA==.Ganzar:BAACLgAFFH8KAAIUAAMJUSRvRwA2AQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAUAAMJUSRvRwA2AQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAuAAQKfyQAAhQACQkpII8KAAQDABQACQkpII8KAAQDAAAA.Gathan:BAAALgADCgcJFgAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8nAAMGAAgJCRFThwBIAQhoDAAACAAnAGkMAAAHADYAawwAAAcALQBqDAAABQA1AGwMAAAEAB8AbQwAAAEASADqDAAABgAeAG4MAAABAB4ABgAHCSIPU4cASAEHaAwAAAgAJwBpDAAABwA2AGsMAAAHAC0AagwAAAUANQBsDAAABAAfAOoMAAAGAB4AbgwAAAEAHgAVAAEJIQODhQArAAFtDAAAAQAIAAAA.Gertrex:BAAALgAECggJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8cAAIWAAgJdQ74EQBlAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABQAoAG4MAAADADgAFgAICXUO+BEAZQEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAUAKABuDAAAAwA4AAAA.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8aAAIXAAkJKwyTFQDiAQloDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAbwwAAAEAHQAXAAkJKwyTFQDiAQloDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAbwwAAAEAHQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJDwAAAA==.',
Ha='Hahmicydal:BAABLgAECn8XAAQYAAYJHgcEHQCjAAZoDAAABQAUAGkMAAAEABYAawwAAAUAEQBqDAAAAwAXAGwMAAABAAMA6gwAAAUAGQAYAAYJXwYEHQCjAAZoDAAAAQAKAGkMAAADABYAawwAAAMAEQBqDAAAAgAXAGwMAAABAAMA6gwAAAMAGQAZAAUJrgW1HgB7AAVoDAAABAAUAGkMAAABABUAawwAAAEABQBqDAAAAQARAOoMAAACAAoAGgABCeYBtkEBFwABawwAAAEABAAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAACLgAFFH8HAAIOAAMJKgxsEwDSAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAOAAMJKgxsEwDSAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAuAAQKfxoAAg4ACQlnHnkIAIACAA4ACQlnHnkIAIACAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIbAAcJmw2uKwBPAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABsABwmbDa4rAE8BB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8QAAIVAAUJKQpSGgApAQVoDAAABgAoAGkMAAAFACcAawwAAAIAAwBqDAAAAQADAOoMAAACACsAFQAFCSkKUhoAKQEFaAwAAAYAKABpDAAABQAnAGsMAAACAAMAagwAAAEAAwDqDAAAAgArAC4ABAp/LAACFQAJCSoXSRcALwIAFQAJCSoXSRcALwIAAAA=.Holyhand:BAABLgAECn8UAAIcAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAcAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAUJEAAVACkKAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJEwAMAAAAAA==.',
Il='Ilin:BAAALgAECgYJBwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8tAAIdAAkJTBYOAgArAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAHAC8AbQwAAAUANwDqDAAABgA5AG4MAAAFAEoAbwwAAAMAPQAdAAkJTBYOAgArAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAHAC8AbQwAAAUANwDqDAAABgA5AG4MAAAFAEoAbwwAAAMAPQABLgAECggJFgAeAM0WAA==.',
Is='Isabela:BAABLgAFFH8IAAIfAAIJsyRrTwDUAAJoDAAABABaAOoMAAAEAGEAHwACCbMka08A1AACaAwAAAQAWgDqDAAABABhAAAA.Isharadai:BAAALgADCgMJAwAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgEJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJFgARAMAlAA==.Judyhopp:BAABLgAECn8aAAQgAAgJWhYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAIAAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAKAAcJFxM/mAA0AQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7AB0AAQkAAJwSAAAAAWoMAAACAEAAAS4ABRQFCRYAEQDAJQA=.Judyhopps:BAAALgAECgYJDAABLgAFFAUJFgARAMAlAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAQJCwAgAHkTAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAYJGgAcAO0bAA==.Kaluanights:BAAALgADCgMJAwAAAA==.Kalzak:BAAALgAECggJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgUJEwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJGgANAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECggJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAMAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgkJDwABLgAECggJEQAMAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECggJEQAMAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgYJEwAAAA==.',
Li='Lidravos:BAAALgADCgYJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwXzYQC1AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwXzYQC1AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABUABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJFAAEAJ0WAA==.',
Ll='Lluvioso:BAACLgAFFH8KAAMUAAMJRh7JbAD3AANoDAAAAwBKAGkMAAACAEYA6gwAAAUAVwAUAAMJeR3JbAD3AANoDAAAAwBKAGkMAAACAEYA6gwAAAMAUAACAAEJ/iFbKwBZAAHqDAAAAgBXAC4ABAp/IwADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAFAABCQ4fhh4BVgAAAAA=.',
Lo='Loaf:BAAALgAECgYJCwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIhAAcJeByMHQC3AQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJACEABwl4HIwdALcBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8XAAIKAAcJ6Al8mQAyAQdoDAAABQAhAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAAEABwAbQwAAAEAEwDqDAAABQAXAAoABwnoCXyZADIBB2gMAAAFACEAaQwAAAMAEwBrDAAAAwAbAGoMAAACACQAbAwAAAQAHABtDAAAAQATAOoMAAAFABcAAAA=.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAMAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAAMAAAAAA==.Merien:BAABLgAECn8YAAIBAAYJfAdekgDyAAZoDAAABgAWAGkMAAAFAB0AawwAAAUAEwBqDAAAAgAbAGwMAAABAA0A6gwAAAUACwABAAYJfAdekgDyAAZoDAAABgAWAGkMAAAFAB0AawwAAAUAEwBqDAAAAgAbAGwMAAABAA0A6gwAAAUACwAAAA==.Meros:BAAALgAECgYJDgAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJEgAMAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBQAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECggJEAAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJCgABLgAECgkJSQAKAOcZAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAABLgAECn8YAAIZAAgJ6RJnCAC1AQhoDAAABAA6AGkMAAAEADIAawwAAAQAMQBqDAAABABDAGwMAAADADUAbQwAAAEAMwDqDAAAAwA9AG4MAAABAA0AGQAICekSZwgAtQEIaAwAAAQAOgBpDAAABAAyAGsMAAAEADEAagwAAAQAQwBsDAAAAwA1AG0MAAABADMA6gwAAAMAPQBuDAAAAQANAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8ZAAIKAAgJPxW5UgDOAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAABAAwAGwMAAAGADwAbQwAAAEAJADqDAAAAwBLAG4MAAABADUACgAICT8VuVIAzgEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAQAMABsDAAABgA8AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAABLgAECn8YAAIbAAcJFg2eKwBPAQdoDAAABQAzAGkMAAAEABMAawwAAAQAIgBqDAAAAgAsAGwMAAACAA0AbQwAAAIADQDqDAAABQA6ABsABwkWDZ4rAE8BB2gMAAAFADMAaQwAAAQAEwBrDAAABAAiAGoMAAACACwAbAwAAAIADQBtDAAAAgANAOoMAAAFADoAAAA=.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAIKAAgJUxw5BQCQAghoDAAABgBdAGkMAAAFAGMAawwAAAQAUwBqDAAAAwBgAGwMAAADAEAAbQwAAAEAEQDqDAAABAA+AG4MAAACAFUACgAICVMcOQUAkAIIaAwAAAYAXQBpDAAABQBjAGsMAAAEAFMAagwAAAMAYABsDAAAAwBAAG0MAAABABEA6gwAAAQAPgBuDAAAAgBVAC4ABAp/JwADCgAICWAinRgAFwMACgAICWAinRgAFwMAHQABCQAAHREALgAAAAA=.Powerwordhug:BAABLgAECn8tAAIcAAkJnx3ECQCvAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAcAAkJnx3ECQCvAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAAAA==.',
Pr='Proctolodin:BAABLgAECn8jAAIGAAgJCBOvXgCcAQhoDAAABQBLAGkMAAAFADMAawwAAAQANABqDAAABAAkAGwMAAAGAC4AbQwAAAQALwDqDAAABgAzAG4MAAABAA4ABgAICQgTr14AnAEIaAwAAAUASwBpDAAABQAzAGsMAAAEADQAagwAAAQAJABsDAAABgAuAG0MAAAEAC8A6gwAAAYAMwBuDAAAAQAOAAAA.',
Pu='Purplefart:BAABLgAECn8kAAMiAAkJlxIpGgDXAQloDAAABwBKAGkMAAAGAD0AawwAAAUAMQBqDAAABQA2AGwMAAABAB0AbQwAAAIAJwDqDAAABwA8AG4MAAACACEAbwwAAAEAIAAiAAkJlxIpGgDXAQloDAAABwBKAGkMAAAGAD0AawwAAAUAMQBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABwA8AG4MAAACACEAbwwAAAEAIAAbAAEJPxuOXQBMAAFqDAAAAQBFAAAA.',
Ql='Qlaryx:BAAALgAECggJEQAAAA==.',
Qu='Quinner:BAACLgAFFH8HAAIIAAMJqhBTNADIAANoDAAAAwAzAGkMAAACAEAA6gwAAAIACwAIAAMJqhBTNADIAANoDAAAAwAzAGkMAAACAEAA6gwAAAIACwAuAAQKfzIABAgACQneG5QLAIoCAAgACQneG5QLAIoCAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAILAAgJxh0BFgDOAQhoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8ACwAICcYdARYAzgEIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIKAAYJRxzjeABwAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAKAAYJRxzjeABwAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJFwAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgMJCAAAAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECggJEgAMAAAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMaAAgJxxKrTgCfAQhoDAAACQA8AGkMAAAJADUAawwAAAkAMABqDAAABwA6AGwMAAAIADUAbQwAAAQAMADqDAAABwAlAG4MAAADACIAGgAICVkSq04AnwEIaAwAAAkAPABpDAAACAA1AGsMAAAIADAAagwAAAYAOgBsDAAABwAtAG0MAAAEADAA6gwAAAcAJQBuDAAAAwAiABkABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECggJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8bAAMCAAYJFg2cLgDDAAZoDAAABQAhAGkMAAAFABkAawwAAAUAFwBqDAAABAAtAGwMAAAEACMA6gwAAAQAMQAUAAYJkwlrvwDdAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAYJKwucLgDDAAZoDAAAAQAhAGkMAAABAAEAawwAAAEAFwBqDAAAAgAtAGwMAAACACMA6gwAAAIAMQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECggJEwAMAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAMAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g+efwAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g+efwAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Silren:BAAALgAECgEJAQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECggJIwAGAAgTAA==.',
So='Sofferenza:BAAALgADCgcJFwAAAA==.Sorulus:BAAALgAECgEJAQAAAA==.Souldance:BAABLgAECn8rAAMaAAkJARZ4JwArAgloDAAABwA6AGkMAAAHAEcAawwAAAcANgBqDAAABAAnAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAaAAkJwBV4JwArAgloDAAABwA6AGkMAAAGAEIAawwAAAYANgBqDAAAAQAeAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAYAAMJQA4/KwBXAANpDAAAAQBHAGsMAAABAAEAagwAAAMAJwAAAA==.',
Sp='Spaceguy:BAABLgAECn8gAAINAAcJGQjJSQDlAAdoDAAABQAkAGkMAAAFACIAawwAAAUADQBqDAAABAAPAGwMAAAFAAkA6gwAAAYAFwBuDAAAAgAGAA0ABwkZCMlJAOUAB2gMAAAFACQAaQwAAAUAIgBrDAAABQANAGoMAAAEAA8AbAwAAAUACQDqDAAABgAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECgkJJAAQANgNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAjAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgIJBgAMAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgcJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECgYJBwAMAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Talie:BAAALgADCgUJBQAAAA==.Taliria:BAABLgAECn8eAAIiAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAiAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECggJEwAAAA==.',
Te='Tenshiro:BAAALgADCgYJCwAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAECgYJBgABLgAECggJEQAMAAAAAA==.',
To='Toblakai:BAAALgADCgUJBQABLgAECgkJAQAMAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAQAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAUJEAAVACkKAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8UAAIPAAYJXBDzEQCYAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAPAAYJXBDzEQCYAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAuAAQKfyMAAg8ACQnmIGsEAEsDAA8ACQnmIGsEAEsDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgcJEgAAAA==.',
Ve='Veldaan:BAAALgADCgcJDAAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJEwAMAAAAAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECgcJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgADCgIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJEwAMAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8UAAIkAAYJEgi9bwDMAAZoDAAABQAhAGkMAAAGADEAawwAAAQADgBqDAAAAQAQAGwMAAABAAMA6gwAAAMABgAkAAYJEgi9bwDMAAZoDAAABQAhAGkMAAAGADEAawwAAAQADgBqDAAAAQAQAGwMAAABAAMA6gwAAAMABgAAAA==.Whiteleaf:BAABLgAECn8eAAIeAAgJkwpjNABaAQhoDAAABAAaAGkMAAAEABsAawwAAAQAEABqDAAAAwATAGwMAAAFACcAbQwAAAEAFQDqDAAABgAkAG4MAAADABUAHgAICZMKYzQAWgEIaAwAAAQAGgBpDAAABAAbAGsMAAAEABAAagwAAAMAEwBsDAAABQAnAG0MAAABABUA6gwAAAYAJABuDAAAAwAVAAAA.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgcJEgAMAAAAAA==.',
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
