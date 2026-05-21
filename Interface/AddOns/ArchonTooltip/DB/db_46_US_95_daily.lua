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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Shaman-Enhancement','Hunter-Survival','Priest-Discipline','Priest-Holy','Mage-Fire','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Priest-Shadow','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-20',data={Aa='Aayu:BAABLgAECn8nAAIBAAgJFRmUMwDXAQhoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoAbQwAAAEAEwDqDAAABgBCAG4MAAADAEAAAQAICRUZlDMA1wEIaAwAAAcAPwBpDAAACABTAGsMAAAEAE0AagwAAAUAKABsDAAABQBKAG0MAAABABMA6gwAAAYAQgBuDAAAAwBAAAAA.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUCQkkAAMAIyIA.Adranelidk:BAAALgAECgQJDAAAAA==.',
Ae='Aeromina:BAABLgAECn8YAAMBAAcJfBLyXwBIAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAAAwAhAAEABwl8EvJfAEgBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAADACEABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANobAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8YAAQHAAgJzxzkDADTAQhoDAAABQBBAGkMAAAEAFoAawwAAAQARQBqDAAAAwBbAGwMAAACAE0AbQwAAAEAIADqDAAABABQAG4MAAABAFIABwAGCfsb5AwA0wEGaAwAAAIAQQBpDAAAAgBaAGsMAAACAEUAagwAAAIAWwBtDAAAAQAgAOoMAAACAFAACAAHCcUMYDoADgEHaAwAAAIAHwBpDAAAAgAyAGsMAAACADcAagwAAAEACQBsDAAAAgAeAOoMAAACABMAbgwAAAEACAAJAAEJRhbQPAA7AAFoDAAAAQA5AAAA.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAABLgAECn8YAAIKAAkJXwWo0QDEAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAKAAkJXwWo0QDEAAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w8gKwBgAQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcACAAICdMPICsAYAEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAwABLgAFFAQJDgALABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJEgAMAAAAAA==.Aussilicious:BAAALgAECggJEgAAAA==.',
Az='Azerennia:BAAALgAECgcJCQAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8kAAIBAAgJiAWJdgAWAQhoDAAABgASAGkMAAAHAB0AawwAAAcACwBqDAAABQAcAGwMAAAEABgAbQwAAAEAAwDqDAAABQAGAG4MAAABAAYAAQAICYgFiXYAFgEIaAwAAAYAEgBpDAAABwAdAGsMAAAHAAsAagwAAAUAHABsDAAABAAYAG0MAAABAAMA6gwAAAUABgBuDAAAAQAGAAAA.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAMAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJEgAMAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECggJEQAAAA==.Belphegör:BAAALgAECgQJBAAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQANAIQZAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgcJDAAMAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJBwABLgAECggJEQAMAAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJBwAMAAAAAA==.Bro:BAAALgAECgUJCAAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQANAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAIOAAYJTyR6AQDVAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAOAAYJTyR6AQDVAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfygAAg4ACQnuJcMBAIYDAA4ACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQPAAgJKhijGwDnAQhoDAAACABWAGkMAAAIAFEAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwADwAHCQ8aoxsA5wEHaAwAAAYAVgBpDAAABgBRAGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAAQAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4AEQABCdwOA3wAMgABbAwAAAEAJgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAMAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8oAAIKAAkJSh0NGwCTAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAKAAkJSh0NGwCTAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.',
Di='Diddyfisting:BAACLgAFFH8VAAIRAAQJwCWtAgC+AQRoDAAABwBiAGkMAAAGAGMAawwAAAMAXQDqDAAABQBeABEABAnAJa0CAL4BBGgMAAAHAGIAaQwAAAYAYwBrDAAAAwBdAOoMAAAFAF4ALgAECn8uAAMRAAkJ3iPaAwD5AgARAAkJ3iPaAwD5AgAQAAEJOgOJjwAmAAAAAA==.Divinefistin:BAECLgAFFH8HAAIQAAMJIhgeJgDtAANoDAAAAwBCAGkMAAACADIA6gwAAAIARAAQAAMJIhgeJgDtAANoDAAAAwBCAGkMAAACADIA6gwAAAIARAAuAAQKfzYAAxAACQmMIpEJAHYCABAACQnLHZEJAHYCABEABwkPIpoNADsCAAAA.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8OAAISAAUJRRwjDQAYAQVoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AOoMAAADAEAAEgAFCUUcIw0AGAEFaAwAAAQASQBpDAAABABKAGsMAAACAE0AagwAAAEANgDqDAAAAwBAAC4ABAp/MwADEgAJCXwezAIAOAMAEgAJCXwezAIAOAMAEwABCQAA+GkAAAAAAAA=.',
El='Elfuego:BAAALgAECgYJCgAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgcJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8UAAIGAAcJPxN+ZwB3AQdoDAAAAwAzAGkMAAADAEwAawwAAAMAHQBqDAAAAgAaAGwMAAACABsA6gwAAAQAQwBuDAAAAwArAAYABwk/E35nAHcBB2gMAAADADMAaQwAAAMATABrDAAAAwAdAGoMAAACABoAbAwAAAIAGwDqDAAABABDAG4MAAADACsAAAA=.',
Fe='Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAAALgAECgcJEAAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgEJBQAAAA==.Ganzar:BAACLgAFFH8KAAIUAAMJUSRNQABCAQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAUAAMJUSRNQABCAQNoDAAABABgAGkMAAADAGEA6gwAAAMAVAAuAAQKfyQAAhQACQknIIoIAAoDABQACQknIIoIAAoDAAAA.Gathan:BAAALgADCgcJEAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8nAAMGAAgJBxEhegBQAQhoDAAACAAnAGkMAAAHADYAawwAAAcALQBqDAAABQA1AGwMAAAEAB8AbQwAAAEASADqDAAABgAeAG4MAAABAB4ABgAHCSIPIXoAUAEHaAwAAAgAJwBpDAAABwA2AGsMAAAHAC0AagwAAAUANQBsDAAABAAfAOoMAAAGAB4AbgwAAAEAHgAVAAEJGQMRfgArAAFtDAAAAQAHAAAA.Gertrex:BAAALgAECgcJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgcJDwAAAA==.',
Go='Goatlord:BAABLgAECn8cAAIWAAgJcw7IDwBqAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABQAoAG4MAAADADgAFgAICXMOyA8AagEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAUAKABuDAAAAwA4AAAA.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgcJDwAAAA==.Gotharm:BAABLgAECn8YAAIXAAgJ7At0GwCZAQhoDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABgAhAG4MAAABABgAFwAICewLdBsAmQEIaAwAAAUAJABpDAAABQAcAGsMAAADACcAagwAAAEABQBsDAAAAgAgAG0MAAABABIA6gwAAAYAIQBuDAAAAQAYAAAA.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJDAAAAA==.',
Ha='Hahmicydal:BAAALgAECgYJEgAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAACLgAFFH8HAAIOAAMJKgxbEADVAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAOAAMJKgxbEADVAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAuAAQKfxoAAg4ACQloHjEHAIsCAA4ACQloHjEHAIsCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIYAAcJmw05JwBYAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABgABwmbDTknAFgBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8QAAIVAAUJKQooFgA6AQVoDAAABgAoAGkMAAAFACcAawwAAAIAAwBqDAAAAQADAOoMAAACACsAFQAFCSkKKBYAOgEFaAwAAAYAKABpDAAABQAnAGsMAAACAAMAagwAAAEAAwDqDAAAAgArAC4ABAp/LAACFQAJCSoXqBQAMwIAFQAJCSoXqBQAMwIAAAA=.Holyhand:BAABLgAECn8UAAIZAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAZAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAUJEAAVACkKAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJEgAMAAAAAA==.',
Il='Ilin:BAAALgAECgYJBwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8pAAIaAAkJshQZAgAMAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAIAPQAaAAkJshQZAgAMAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAIAPQABLgAECggJFgAbAMwWAA==.',
Is='Isabela:BAABLgAFFH8IAAIcAAIJsyQkRwDYAAJoDAAABABaAOoMAAAEAGEAHAACCbMkJEcA2AACaAwAAAQAWgDqDAAABABhAAAA.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgEJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAQJFQARAMAlAA==.Judyhopp:BAABLgAECn8aAAQdAAgJWRYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAHQAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAKAAcJFxO9jQA3AQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABoAAQkAANMQAAAAAWoMAAACAEAAAS4ABRQECRUAEQDAJQA=.Judyhopps:BAAALgAECgYJDAABLgAFFAQJFQARAMAlAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAQJCgAKAJsPAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgMJAwAAAA==.Kalzak:BAAALgAECggJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJDgAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJFgANALgTAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECggJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAMAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgcJDwABLgAECggJEQAMAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECggJEQAMAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJEQAAAA==.',
Li='Lidravos:BAAALgADCgYJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwXpUwDAAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwXpUwDAAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABUABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJEQAEAKwVAA==.',
Ll='Lluvioso:BAACLgAFFH8IAAMUAAMJRh4iXwADAQNoDAAAAgBKAGkMAAABAEYA6gwAAAUAVwAUAAMJeR0iXwADAQNoDAAAAgBKAGkMAAABAEYA6gwAAAMAUAACAAEJ/iH4JQBdAAHqDAAAAgBXAC4ABAp/IwADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAFAABCQ4fhwgBWAAAAAA=.',
Lo='Loaf:BAAALgAECgEJBgAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIeAAcJdxy4GgC6AQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJAB4ABwl3HLgaALoBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgcJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8UAAIKAAYJBAlPtgDyAAZoDAAABAAgAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAADAAwA6gwAAAUAFwAKAAYJBAlPtgDyAAZoDAAABAAgAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAADAAwA6gwAAAUAFwAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAMAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Merien:BAAALgAECgUJEgAAAA==.Meros:BAAALgAECgQJDAAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJEgAMAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgQJBAAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECggJEAAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAQAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJCgABLgAECgkJPgAKABwXAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAAALgAECgcJEQAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8YAAIKAAgJGRUnTgDJAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAABAAwAGwMAAAFADoAbQwAAAEAJADqDAAAAwBLAG4MAAABADUACgAICRkVJ04AyQEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAQAMABsDAAABQA6AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAABLgAECn8YAAIYAAcJFg3KJgBcAQdoDAAABQAzAGkMAAAEABMAawwAAAQAIgBqDAAAAgAsAGwMAAACAA0AbQwAAAIADQDqDAAABQA6ABgABwkWDcomAFwBB2gMAAAFADMAaQwAAAQAEwBrDAAABAAiAGoMAAACACwAbAwAAAIADQBtDAAAAgANAOoMAAAFADoAAAA=.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8YAAIKAAcJcB0ICABDAgdoDAAABQBdAGkMAAAFAGMAawwAAAQAUwBqDAAAAwBgAGwMAAACABoA6gwAAAQAPgBuDAAAAQBVAAoABwlwHQgIAEMCB2gMAAAFAF0AaQwAAAUAYwBrDAAABABTAGoMAAADAGAAbAwAAAIAGgDqDAAABAA+AG4MAAABAFUALgAECn8nAAMKAAgJYCKdGAAXAwAKAAgJYCKdGAAXAwAaAAEJAAAdEQAuAAAAAA==.Powerwordhug:BAABLgAECn8tAAIZAAkJoB1SCAC4AgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAZAAkJoB1SCAC4AgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAAAA==.',
Pr='Proctolodin:BAABLgAECn8eAAIGAAgJPBIWXACRAQhoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAFAC4AbQwAAAMAKADqDAAABQAzAG4MAAABAA4ABgAICTwSFlwAkQEIaAwAAAQAQwBpDAAABAAzAGsMAAAEADQAagwAAAQAJABsDAAABQAuAG0MAAADACgA6gwAAAUAMwBuDAAAAQAOAAAA.',
Pu='Purplefart:BAABLgAECn8eAAMfAAgJSRM5IQCHAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABgA8AG4MAAACACEAHwAICUkTOSEAhwEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAYAPABuDAAAAgAhABgAAQk/G39VAE4AAWoMAAABAEUAAAA=.',
Ql='Qlaryx:BAAALgAECggJEQAAAA==.',
Qu='Quinner:BAACLgAFFH8GAAIIAAMJqhCFLQDXAANoDAAAAwAzAGkMAAACAEAA6gwAAAEACwAIAAMJqhCFLQDXAANoDAAAAwAzAGkMAAACAEAA6gwAAAEACwAuAAQKfzIABAgACQneGzIKAIwCAAgACQneGzIKAIwCAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAILAAgJxR0IEwDeAQhoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8ACwAICcUdCBMA3gEIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIKAAYJRxykbgB2AQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAKAAYJRxykbgB2AQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJFwAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgMJCAABLgAFFAMJCQAKAEgbAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDwAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8xAAMgAAgJYxEeTgCPAQhoDAAACAAvAGkMAAAIADUAawwAAAgAMABqDAAABwA6AGwMAAAHADUAbQwAAAMAMADqDAAABgAlAG4MAAACABYAIAAICfUQHk4AjwEIaAwAAAgALwBpDAAABwA1AGsMAAAHADAAagwAAAYAOgBsDAAABgAtAG0MAAADADAA6gwAAAYAJQBuDAAAAgAWACEABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECggJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8VAAMUAAYJ9ApQrwDmAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAwAtAGwMAAADAB0A6gwAAAMAJQAUAAYJkwlQrwDmAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAMJNQ0GQgBNAANqDAAAAQAtAGwMAAABAB0A6gwAAAEAJQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECggJEgAMAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAMAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g8ZdAAcAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g8ZdAAcAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Sita:BAAALgADCgcJDwAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECggJHgAGADwSAA==.',
So='Sofferenza:BAAALgADCgcJEQAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8lAAMgAAkJthHeMQDuAQloDAAABgArAGkMAAAGAEIAawwAAAYANgBqDAAAAwAfAGwMAAADACQAbQwAAAEADgDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAgAAkJthHeMQDuAQloDAAABgArAGkMAAAGAEIAawwAAAYANgBqDAAAAQAeAGwMAAADACQAbQwAAAEADgDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAiAAEJAAA9bAA7AAFqDAAAAgAfAAAA.',
Sp='Spaceguy:BAABLgAECn8bAAINAAcJjAU3SwDKAAdoDAAABAASAGkMAAAEAA0AawwAAAQADQBqDAAAAwAPAGwMAAAFAAkA6gwAAAUAFwBuDAAAAgAGAA0ABwmMBTdLAMoAB2gMAAAEABIAaQwAAAQADQBrDAAABAANAGoMAAADAA8AbAwAAAUACQDqDAAABQAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECgkJIAAPAN8MAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAjAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgEJBQAMAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgcJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECgYJBwAMAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIfAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAfAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECggJEgAAAA==.',
Te='Tenshiro:BAAALgADCgYJCwAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAQAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAUJEAAVACkKAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8UAAIPAAYJXBDADQCiAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAPAAYJXBDADQCiAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAuAAQKfxwAAg8ACQlmHYAIANECAA8ACQlmHYAIANECAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJEAAAAA==.',
Ve='Veldaan:BAAALgADCgcJBwAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJEgAMAAAAAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECgcJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJEgAMAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgYJEgAAAA==.Whiteleaf:BAABLgAECn8XAAIbAAcJhgmgPAAhAQdoDAAAAwAaAGkMAAADABsAawwAAAMADgBqDAAAAwATAGwMAAAEAB8A6gwAAAUAGABuDAAAAgAVABsABwmGCaA8ACEBB2gMAAADABoAaQwAAAMAGwBrDAAAAwAOAGoMAAADABMAbAwAAAQAHwDqDAAABQAYAG4MAAACABUAAAA=.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJEAAMAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgIJAgAAAA==.',
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
