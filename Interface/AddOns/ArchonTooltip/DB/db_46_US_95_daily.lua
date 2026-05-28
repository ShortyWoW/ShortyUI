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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Shaman-Enhancement','Hunter-Survival','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Priest-Discipline','Priest-Holy','Mage-Fire','Mage-Arcane','Shaman-Elemental','Druid-Balance','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','Druid-Restoration','Warrior-Fury',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-27',data={Aa='Aayu:BAABLgAECn8pAAIBAAgJFRlSPQDLAQhoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoAbQwAAAEAEwDqDAAABwBCAG4MAAAEAEAAAQAICRUZUj0AywEIaAwAAAcAPwBpDAAACABTAGsMAAAEAE0AagwAAAUAKABsDAAABQBKAG0MAAABABMA6gwAAAcAQgBuDAAABABAAAAA.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUCQktAAMAOCMA.Adranelidk:BAAALgAECgYJEAAAAA==.',
Ae='Aeromina:BAABLgAECn8bAAMBAAcJ/BO3awBJAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAABgA4AAEABwn8E7drAEkBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAAGADgABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8hAAQHAAgJhCDVAwDoAghoDAAABgBKAGkMAAAFAFoAawwAAAUAUgBqDAAABABbAGwMAAADAGIAbQwAAAMAVwDqDAAABQBQAG4MAAACAD0ABwAICYQg1QMA6AIIaAwAAAMASgBpDAAAAwBaAGsMAAADAFIAagwAAAMAWwBsDAAAAQBiAG0MAAACAFcA6gwAAAMAUABuDAAAAQA9AAgACAnbC2Y3ACsBCGgMAAACAB8AaQwAAAIAMgBrDAAAAgA3AGoMAAABAAkAbAwAAAIAHgBtDAAAAQAQAOoMAAACABMAbgwAAAEACAAJAAEJRhbQPAA7AAFoDAAAAQA5AAAA.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAABLgAECn8YAAIKAAkJXwXn3gC0AAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAKAAkJXwXn3gC0AAloDAAAAwABAGkMAAAEACgAawwAAAQAKwBqDAAAAwAWAGwMAAACAAAAbQwAAAIAAADqDAAAAwAYAG4MAAACAAAAbwwAAAEAAAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w93MABQAQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcACAAICdMPdzAAUAEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgMJBgABLgAFFAMJBAALAIwNAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJEgAMAAAAAA==.Aussilicious:BAAALgAECggJEgAAAA==.',
Az='Azerennia:BAAALgAECgcJCgAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8sAAIBAAgJRQaUdAA1AQhoDAAABwASAGkMAAAIAB0AawwAAAgACwBqDAAABgAcAGwMAAAFAB8AbQwAAAIACQDqDAAABgAHAG4MAAACAAYAAQAICUUGlHQANQEIaAwAAAcAEgBpDAAACAAdAGsMAAAIAAsAagwAAAYAHABsDAAABQAfAG0MAAACAAkA6gwAAAYABwBuDAAAAgAGAAAA.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAMAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJEgAMAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECggJEgAAAA==.Belphegör:BAAALgAECgYJCAAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgMJBgAMAAAAAA==.Beydoon:BAAALgAECgMJBQAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJFQABAAkdAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgcJDAAMAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJBwABLgAECggJEQAMAAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAAMAAAAAA==.Bro:BAAALgAECgUJDQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgAAAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAINAAYJTyQPAQCuAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAANAAYJTyQPAQCuAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfygAAg0ACQnuJcMBAIYDAA0ACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQOAAgJKhhtIADkAQhoDAAACABWAGkMAAAIAFEAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwADgAHCQ8abSAA5AEHaAwAAAYAVgBpDAAABgBRAGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAAPAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4AEAABCdwOFogAMgABbAwAAAEAJgAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAMAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAABLgAECn8oAAIKAAkJSh0dIACEAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAKAAkJSh0dIACEAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8aAAIQAAUJwCXKAwC4AQVoDAAACABiAGkMAAAHAGMAawwAAAQAXQBqDAAAAQBCAOoMAAAGAF4AEAAFCcAlygMAuAEFaAwAAAgAYgBpDAAABwBjAGsMAAAEAF0AagwAAAEAQgDqDAAABgBeAC4ABAp/MAADEAAJCd4j9QQA7gIAEAAJCd4j9QQA7gIADwABCToDiY8AJgAAAAA=.Divinefistin:BAECLgAFFH8KAAIPAAMJqByhIgALAQNoDAAABABCAGkMAAADADoA6gwAAAMAXwAPAAMJqByhIgALAQNoDAAABABCAGkMAAADADoA6gwAAAMAXwAuAAQKfzYAAw8ACQmMIjELAGsCAA8ACQnLHTELAGsCABAABwkPIqsPADMCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAMJCgAPAKgcAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8QAAIRAAYJ6RuQCAB5AQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAQAVgARAAYJ6RuQCAB5AQZoDAAABABJAGkMAAAEAEoAawwAAAIATQBqDAAAAQA2AGwMAAABAC0A6gwAAAQAVgAuAAQKfzMAAxEACQl8HswCADgDABEACQl8HswCADgDABIAAQkAAK53AAAAAAAA.',
El='Elfuego:BAAALgAECgYJCgAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8dAAIGAAgJ0xUcSQDRAQhoDAAABQBAAGkMAAAFAEwAawwAAAUALwBqDAAAAwAlAGwMAAADABsAbQwAAAEAQADqDAAABABDAG4MAAADACsABgAICdMVHEkA0QEIaAwAAAUAQABpDAAABQBMAGsMAAAFAC8AagwAAAMAJQBsDAAAAwAbAG0MAAABAEAA6gwAAAQAQwBuDAAAAwArAAAA.Fatima:BAAALgAECgEJAQAAAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAABLgAECn8WAAIFAAcJBAUvEQD6AAdoDAAAAwANAGkMAAADABEAawwAAAMADQBqDAAAAgASAGwMAAAFAAsA6gwAAAQACwBuDAAAAgAJAAUABwkEBS8RAPoAB2gMAAADAA0AaQwAAAMAEQBrDAAAAwANAGoMAAACABIAbAwAAAUACwDqDAAABAALAG4MAAACAAkAAAA=.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAMAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8NAAITAAMJtySgRQBBAQNoDAAABQBjAGkMAAAEAGEA6gwAAAQAVAATAAMJtySgRQBBAQNoDAAABQBjAGkMAAAEAGEA6gwAAAQAVAAuAAQKfyUAAhMACQkpIMYKAAMDABMACQkpIMYKAAMDAAAA.Gathan:BAAALgADCgcJFgAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8vAAMGAAgJaBJtWwChAQhoDAAACQA4AGkMAAAIAEMAawwAAAgALgBqDAAABgA6AGwMAAAFAB8AbQwAAAIAKgDqDAAABwAmAG4MAAACAC8ABgAICWgSbVsAoQEIaAwAAAkAOABpDAAACABDAGsMAAAIAC4AagwAAAYAOgBsDAAABQAfAG0MAAABACoA6gwAAAcAJgBuDAAAAgAvABQAAQkhA3WGACsAAW0MAAABAAgAAAA=.Gertrex:BAAALgAECggJDQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIVAAkJMw8lDQC3AQloDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABgAyAG4MAAADADgAbwwAAAEAKQAVAAkJMw8lDQC3AQloDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABgAyAG4MAAADADgAbwwAAAEAKQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8aAAIWAAkJKwzVFQDiAQloDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAbwwAAAEAHQAWAAkJKwzVFQDiAQloDAAABQAkAGkMAAAFABwAawwAAAMAJwBqDAAAAQAFAGwMAAACACAAbQwAAAEAEgDqDAAABwAnAG4MAAABABgAbwwAAAEAHQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJDwAAAA==.',
Ha='Hahmicydal:BAABLgAECn8ZAAQXAAcJ9wc3FwDbAAdoDAAABQAUAGkMAAAEABYAawwAAAUAEQBqDAAAAwAXAGwMAAACABIAbQwAAAEAEADqDAAABQAZABcABwkSBjcXANsAB2gMAAAEABQAaQwAAAEAFQBrDAAAAQAFAGoMAAABABEAbAwAAAEAEgBtDAAAAQAQAOoMAAACAAoAGAAGCV8GWh0AowAGaAwAAAEACgBpDAAAAwAWAGsMAAADABEAagwAAAIAFwBsDAAAAQADAOoMAAADABkAGQABCeYBRUQBFwABawwAAAEABAAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAACLgAFFH8HAAINAAMJKgzeEwDOAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwANAAMJKgzeEwDOAANoDAAAAwAeAGkMAAABABsA6gwAAAMAIwAuAAQKfxoAAg0ACQlnHqkIAH4CAA0ACQlnHqkIAH4CAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIaAAcJmw3/KwBJAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABoABwmbDf8rAEkBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8VAAIUAAUJCwsiGQA2AQVoDAAABwAoAGkMAAAGACcAawwAAAMAAwBqDAAAAgAOAOoMAAADACsAFAAFCQsLIhkANgEFaAwAAAcAKABpDAAABgAnAGsMAAADAAMAagwAAAIADgDqDAAAAwArAC4ABAp/LAACFAAJCSoXphcALgIAFAAJCSoXphcALgIAAAA=.Holyhand:BAABLgAECn8UAAIbAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAbAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAUJFQAUAAsLAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJFQABAAkdAA==.',
Il='Ilin:BAAALgAECggJDwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8tAAIcAAkJTBY2AgAdAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAHAC8AbQwAAAUANwDqDAAABgA5AG4MAAAFAEoAbwwAAAMAPQAcAAkJTBY2AgAdAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAHAC8AbQwAAAUANwDqDAAABgA5AG4MAAAFAEoAbwwAAAMAPQAAAA==.',
Is='Isabela:BAABLgAFFH8IAAILAAIJsyQDUADTAAJoDAAABABaAOoMAAAEAGEACwACCbMkA1AA0wACaAwAAAQAWgDqDAAABABhAAAA.Isharadai:BAAALgADCgMJAwAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgEJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJGgAQAMAlAA==.Judyhopp:BAABLgAECn8aAAQdAAgJWhYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAHQAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAKAAcJFxNTkgA0AQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABwAAQkAAA8TAAAAAWoMAAACAEAAAS4ABRQFCRoAEADAJQA=.Judyhopps:BAAALgAECgYJDAABLgAFFAUJGgAQAMAlAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAQJDAAdAPkXAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAYJGwAbAE4dAA==.Kaluanights:BAAALgADCgMJAwAAAA==.Kalzak:BAAALgAECggJEgAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIZAAYJ2wYGrQDZAAZoDAAABgAQAGkMAAAGABEAawwAAAYAHABqDAAAAgAYAGwMAAABAAgA6gwAAAQADwAZAAYJ2wYGrQDZAAZoDAAABgAQAGkMAAAGABEAawwAAAYAHABqDAAAAgAYAGwMAAABAAgA6gwAAAQADwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJGgAeAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECggJEgAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAMAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgkJDwABLgAECggJEgAMAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECggJEQAMAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8YAAIUAAYJ6xDCOgBAAQZoDAAABQBBAGkMAAAFACEAawwAAAUALwBqDAAAAwAsAOoMAAAFADwAbgwAAAEABwAUAAYJ6xDCOgBAAQZoDAAABQBBAGkMAAAFACEAawwAAAUALwBqDAAAAwAsAOoMAAAFADwAbgwAAAEABwAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwW9YwC0AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwW9YwC0AANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABQABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJFAAEAJ0WAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMTAAMJ4h+QZwAIAQNoDAAABABKAGkMAAADAFMA6gwAAAYAVwATAAMJFB+QZwAIAQNoDAAABABKAGkMAAADAFMA6gwAAAQAUAACAAEJ/iEYLABZAAHqDAAAAgBXAC4ABAp/IwADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAEwABCQ4f+iEBVQAAAAA=.',
Lo='Loaf:BAAALgAECgYJEQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIfAAcJeBzuHQC3AQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJAB8ABwl4HO4dALcBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8fAAIKAAgJmgs/dwBqAQhoDAAABgAqAGkMAAAEACMAawwAAAQAGwBqDAAAAwAtAGwMAAAFAB0AbQwAAAIAGwDqDAAABgAXAG4MAAABABYACgAICZoLP3cAagEIaAwAAAYAKgBpDAAABAAjAGsMAAAEABsAagwAAAMALQBsDAAABQAdAG0MAAACABsA6gwAAAYAFwBuDAAAAQAWAAAA.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAMAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAAMAAAAAA==.Merien:BAABLgAECn8YAAIBAAYJfAc/lADyAAZoDAAABgAWAGkMAAAFAB0AawwAAAUAEwBqDAAAAgAbAGwMAAABAA0A6gwAAAUACwABAAYJfAc/lADyAAZoDAAABgAWAGkMAAAFAB0AawwAAAUAEwBqDAAAAgAbAGwMAAABAA0A6gwAAAUACwAAAA==.Meros:BAAALgAECgYJEAAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJEgAMAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBQAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.',
Ne='Nebüla:BAAALgAECggJEAAAAA==.Necrökush:BAAALgAECgYJAQAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJCgABLgAFFAIJCAAKAHoLAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAABLgAECn8YAAIXAAgJ6RKkCACyAQhoDAAABAA6AGkMAAAEADIAawwAAAQAMQBqDAAABABDAGwMAAADADUAbQwAAAEAMwDqDAAAAwA9AG4MAAABAA0AFwAICekSpAgAsgEIaAwAAAQAOgBpDAAABAAyAGsMAAAEADEAagwAAAQAQwBsDAAAAwA1AG0MAAABADMA6gwAAAMAPQBuDAAAAQANAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAQAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8ZAAIKAAgJPxW7UwDEAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAABAAwAGwMAAAGADwAbQwAAAEAJADqDAAAAwBLAG4MAAABADUACgAICT8Vu1MAxAEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAQAMABsDAAABgA8AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAABLgAECn8YAAIaAAcJFg1lLgA6AQdoDAAABQAzAGkMAAAEABMAawwAAAQAIgBqDAAAAgAsAGwMAAACAA0AbQwAAAIADQDqDAAABQA6ABoABwkWDWUuADoBB2gMAAAFADMAaQwAAAQAEwBrDAAABAAiAGoMAAACACwAbAwAAAIADQBtDAAAAgANAOoMAAAFADoAAAA=.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAIKAAgJUxysBQCPAghoDAAABgBdAGkMAAAFAGMAawwAAAQAUwBqDAAAAwBgAGwMAAADAEAAbQwAAAEAEQDqDAAABAA+AG4MAAACAFUACgAICVMcrAUAjwIIaAwAAAYAXQBpDAAABQBjAGsMAAAEAFMAagwAAAMAYABsDAAAAwBAAG0MAAABABEA6gwAAAQAPgBuDAAAAgBVAC4ABAp/JwADCgAICWAinRgAFwMACgAICWAinRgAFwMAHAABCQAAHREALgAAAAA=.Powerwordhug:BAABLgAECn8tAAIbAAkJnx0ICgCuAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAbAAkJnx0ICgCuAgloDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAbwwAAAEAKQAAAA==.',
Pr='Proctolodin:BAABLgAECn8jAAIGAAgJCBMnXwCYAQhoDAAABQBLAGkMAAAFADMAawwAAAQANABqDAAABAAkAGwMAAAGAC4AbQwAAAQALwDqDAAABgAzAG4MAAABAA4ABgAICQgTJ18AmAEIaAwAAAUASwBpDAAABQAzAGsMAAAEADQAagwAAAQAJABsDAAABgAuAG0MAAAEAC8A6gwAAAYAMwBuDAAAAQAOAAAA.',
Pu='Purplefart:BAABLgAECn8kAAMgAAkJlxKUGgDMAQloDAAABwBKAGkMAAAGAD0AawwAAAUAMQBqDAAABQA2AGwMAAABAB0AbQwAAAIAJwDqDAAABwA8AG4MAAACACEAbwwAAAEAIAAgAAkJlxKUGgDMAQloDAAABwBKAGkMAAAGAD0AawwAAAUAMQBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABwA8AG4MAAACACEAbwwAAAEAIAAaAAEJPxvlXQBMAAFqDAAAAQBFAAAA.',
Ql='Qlaryx:BAAALgAECggJEQAAAA==.',
Qu='Quinner:BAACLgAFFH8JAAIIAAMJtxDMMwDNAANoDAAABAAzAGkMAAADAEAA6gwAAAIACwAIAAMJtxDMMwDNAANoDAAABAAzAGkMAAADAEAA6gwAAAIACwAuAAQKfzIABAgACQneG7kLAIICAAgACQneG7kLAIICAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIhAAgJxh1dFgDNAQhoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8AIQAICcYdXRYAzQEIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIKAAYJRxwGeABpAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAKAAYJRxwGeABpAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJFwAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgMJCAABLgAFFAMJCgAKAMcfAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECggJEgAMAAAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMZAAgJxxJUTwCdAQhoDAAACQA8AGkMAAAJADUAawwAAAkAMABqDAAABwA6AGwMAAAIADUAbQwAAAQAMADqDAAABwAlAG4MAAADACIAGQAICVkSVE8AnQEIaAwAAAkAPABpDAAACAA1AGsMAAAIADAAagwAAAYAOgBsDAAABwAtAG0MAAAEADAA6gwAAAcAJQBuDAAAAwAiABcABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECggJEQAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8bAAMCAAYJFg05LwDDAAZoDAAABQAhAGkMAAAFABkAawwAAAUAFwBqDAAABAAtAGwMAAAEACMA6gwAAAQAMQATAAYJkwlZwQDdAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAYJKws5LwDDAAZoDAAAAQAhAGkMAAABAAEAawwAAAEAFwBqDAAAAgAtAGwMAAACACMA6gwAAAIAMQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECggJFQABAAkdAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAMAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g9agQAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g9agQAaAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Silren:BAAALgAECgQJBAAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgUJCgABLgAECggJIwAGAAgTAA==.',
So='Sofferenza:BAAALgADCgcJFwAAAA==.Sorulus:BAAALgAECgEJAQAAAA==.Souldance:BAABLgAECn8rAAMZAAkJARYlKAAoAgloDAAABwA6AGkMAAAHAEcAawwAAAcANgBqDAAABAAnAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAZAAkJwBUlKAAoAgloDAAABwA6AGkMAAAGAEIAawwAAAYANgBqDAAAAQAeAGwMAAAEAEkAbQwAAAIALQDqDAAABgA+AG4MAAAFADQAbwwAAAEAHwAYAAMJQA60KwBXAANpDAAAAQBHAGsMAAABAAEAagwAAAMAJwAAAA==.',
Sp='Spaceguy:BAABLgAECn8gAAIeAAcJGQilSgDlAAdoDAAABQAkAGkMAAAFACIAawwAAAUADQBqDAAABAAPAGwMAAAFAAkA6gwAAAYAFwBuDAAAAgAGAB4ABwkZCKVKAOUAB2gMAAAFACQAaQwAAAUAIgBrDAAABQANAGoMAAAEAA8AbAwAAAUACQDqDAAABgAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECgkJJAAPANgNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAiAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgIJBwAMAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECggJEQAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJDwAMAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Talie:BAAALgADCgUJBQAAAA==.Taliria:BAABLgAECn8eAAIgAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAgAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAABLgAECn8VAAIBAAgJCR3JJgAlAghoDAAAAwBGAGkMAAADAFEAawwAAAMAUgBqDAAAAwBeAGwMAAACAFAAbQwAAAMAUwDqDAAAAgAxAG4MAAACAEcAAQAICQkdySYAJQIIaAwAAAMARgBpDAAAAwBRAGsMAAADAFIAagwAAAMAXgBsDAAAAgBQAG0MAAADAFMA6gwAAAIAMQBuDAAAAgBHAAAA.',
Te='Tenshiro:BAAALgADCgYJCwAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAECgYJBgABLgAECggJEQAMAAAAAA==.',
To='Toblakai:BAAALgADCgUJBQABLgAECgkJAgAMAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAQAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAUJFQAUAAsLAA==.',
Uz='Uzumaki:BAABLgAECn8VAAIQAAgJrBU8FwDdAQhoDAAAAwBDAGkMAAADAEkAawwAAAMAOwBqDAAAAwAvAGwMAAADAEQAbQwAAAEAEwDqDAAABAA/AG4MAAABACQAEAAICawVPBcA3QEIaAwAAAMAQwBpDAAAAwBJAGsMAAADADsAagwAAAMALwBsDAAAAwBEAG0MAAABABMA6gwAAAQAPwBuDAAAAQAkAAAA.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8UAAIOAAYJXBCNEgCTAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAOAAYJXBCNEgCTAQZoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAGwMAAABABcA6gwAAAQANwAuAAQKfyMAAg4ACQnmIIUEAEkDAA4ACQnmIIUEAEkDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECggJEwAAAA==.',
Ve='Veldaan:BAAALgADCgkJDgAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJFQABAAkdAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECgcJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJFQABAAkdAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8VAAIjAAYJFQmIbQDUAAZoDAAABQAhAGkMAAAGADEAawwAAAQADgBqDAAAAQAQAGwMAAABAAMA6gwAAAQAFQAjAAYJFQmIbQDUAAZoDAAABQAhAGkMAAAGADEAawwAAAQADgBqDAAAAQAQAGwMAAABAAMA6gwAAAQAFQAAAA==.Whiteleaf:BAABLgAECn8eAAIkAAgJkwoWNQBZAQhoDAAABAAaAGkMAAAEABsAawwAAAQAEABqDAAAAwATAGwMAAAFACcAbQwAAAEAFQDqDAAABgAkAG4MAAADABUAJAAICZMKFjUAWQEIaAwAAAQAGgBpDAAABAAbAGsMAAAEABAAagwAAAMAEwBsDAAABQAnAG0MAAABABUA6gwAAAYAJABuDAAAAwAVAAAA.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECggJEwAMAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgMJBAAAAA==.',
Xe='Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
['Yî']='Yîn:BAAALgAECgEJAQAAAA==.',
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
