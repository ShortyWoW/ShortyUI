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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Augmentation','Unknown-Unknown','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','Priest-Holy','Mage-Fire','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-13',data={Aa='Aayu:BAABLgAECn8mAAIBAAcJ/huUJgDUAQdoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoA6gwAAAYAQgBuDAAAAwBAAAEABwn+G5QmANQBB2gMAAAHAD8AaQwAAAgAUwBrDAAABABNAGoMAAAFACgAbAwAAAUASgDqDAAABgBCAG4MAAADAEAAAAA=.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAAA.Adranelidk:BAAALgAECgMJBwAAAA==.',
Ae='Aeromina:BAABLgAECn8YAAMBAAcJfBLxXQASAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAAAwAhAAEABwl8EvFdABIBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAADACEAAwABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJIgAEAH8aAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIFAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABQAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAAALgAECgYJEQAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAAALgAECgkJEwAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIDAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIAAwACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACAwAJCbkiKAMAeAMAAwAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIGAAgJ0w9qHAB1AQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcABgAICdMPahwAdQEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAgABLgAFFAMJAwAHAAAAAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJDwAHAAAAAA==.Aussilicious:BAAALgAECggJDwAAAA==.',
Az='Azerennia:BAAALgAECgUJCQAAAA==.Azerious:BAAALgADCggJDgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8dAAIBAAYJ9QaOagDxAAZoDAAABQASAGkMAAAGAB0AawwAAAYACwBqDAAABAAcAGwMAAAEABgA6gwAAAQABgABAAYJ9QaOagDxAAZoDAAABQASAGkMAAAGAB0AawwAAAYACwBqDAAABAAcAGwMAAAEABgA6gwAAAQABgAAAA==.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAHAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJDwAHAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECgYJEQAAAA==.Belphegör:BAAALgADCgEJAQAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgMJBgAHAAAAAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgYJDAAHAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgUJBgAHAAAAAA==.Bro:BAAALgAECgEJAQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgAAAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAIIAAYJTyS4AADsAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAIAAYJTyS4AADsAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfyYAAggACQnuJcMBAIYDAAgACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8hAAQJAAgJ6RaBFADaAQhoDAAABwBWAGkMAAAHADgAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwACQAHCaAYgRQA2gEHaAwAAAUAVgBpDAAABQA4AGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAAKAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4ACwABCdwOzWcAMwABbAwAAAEAJgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAHAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8oAAIMAAkJSh0kDgDEAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAMAAkJSh0kDgDEAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.',
Di='Diddyfisting:BAACLgAFFH8OAAILAAQJZSRmAgCoAQRoDAAABQBaAGkMAAAEAGAAawwAAAEAWgDqDAAABABeAAsABAllJGYCAKgBBGgMAAAFAFoAaQwAAAQAYABrDAAAAQBaAOoMAAAEAF4ALgAECn8sAAMLAAgJIiScBAC1AgALAAgJIiScBAC1AgAKAAEJOgOJjwAmAAAAAA==.Divinefistin:BAEBLgAECn8yAAMKAAkJVx/sBgB9AgloDAAACABZAGkMAAAIAGEAawwAAAkAWQBqDAAABgBMAGwMAAAHAF0AbQwAAAEAPQDqDAAABwBfAG4MAAADAB0AbwwAAAEAVAAKAAkJYB3sBgB9AgloDAAABgBOAGkMAAAFAFIAawwAAAYASwBqDAAABQBMAGwMAAAGAF0AbQwAAAEAPQDqDAAABgBfAG4MAAADAB0AbwwAAAEAVAALAAYJeiHlDgDoAQZoDAAAAgBZAGkMAAADAGEAawwAAAMAWQBqDAAAAQA8AGwMAAABAFAA6gwAAAEARgAAAA==.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECgUJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgYJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJBwAAAA==.',
Ec='Ecks:BAACLgAFFH8MAAINAAQJRRymCQAnAQRoDAAABABJAGkMAAAEAEoAawwAAAIATQDqDAAAAgBAAA0ABAlFHKYJACcBBGgMAAAEAEkAaQwAAAQASgBrDAAAAgBNAOoMAAACAEAALgAECn8tAAMNAAkJBx7MAgA4AwANAAkJBx7MAgA4AwAOAAEJAACqVAAAAAAAAA==.',
El='Elfuego:BAAALgAECgUJCQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgYJCAAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAAALgAECgcJDAAAAA==.',
Fe='Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAAALgAECgcJDwAAAA==.Fishtotem:BAAALgADCgYJBwAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECgcJDgAAAA==.Frissbee:BAAALgADCgMJAwAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgEJBAAAAA==.Ganzar:BAACLgAFFH8FAAIPAAMJyxe3TQAHAQNoDAAAAgA/AGkMAAABACIA6gwAAAIAVAAPAAMJyxe3TQAHAQNoDAAAAgA/AGkMAAABACIA6gwAAAIAVAAuAAQKfxwAAg8ACQn0HMgRAIwCAA8ACQn0HMgRAIwCAAAA.Gathan:BAAALgADCgcJEAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8gAAIFAAYJ1Q4kcwAdAQZoDAAABwAlAGkMAAAGADYAawwAAAYAJQBqDAAABAA1AGwMAAAEAB8A6gwAAAUAHQAFAAYJ1Q4kcwAdAQZoDAAABwAlAGkMAAAGADYAawwAAAYAJQBqDAAABAA1AGwMAAAEAB8A6gwAAAUAHQAAAA==.Gertrex:BAAALgAECgYJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgYJCAAAAA==.',
Go='Goatlord:BAABLgAECn8aAAIQAAgJGg7QCgCEAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABAAhAG4MAAACADgAEAAICRoO0AoAhAEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAQAIQBuDAAAAgA4AAAA.Goatsavior:BAAALgAECgQJCQAAAA==.Goblinsrhot:BAAALgADCgYJCAAAAA==.Gotharm:BAAALgAECgYJEwAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJBgAAAA==.',
Ha='Hahmicydal:BAAALgAECgUJEQAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAABLgAECn8ZAAIIAAkJaB7CAwC4AgloDAAABQBeAGkMAAADAFUAawwAAAMATABqDAAAAwBeAGwMAAADAEsAbQwAAAMARwDqDAAAAgBSAG4MAAACAFAAbwwAAAEAOAAIAAkJaB7CAwC4AgloDAAABQBeAGkMAAADAFUAawwAAAMATABqDAAAAwBeAGwMAAADAEsAbQwAAAMARwDqDAAAAgBSAG4MAAACAFAAbwwAAAEAOAAAAA==.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIRAAcJmw3/HABkAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABEABwmbDf8cAGQBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8MAAISAAQJZwxqGAABAQRoDAAABQAoAGkMAAAEACcAawwAAAEAAwDqDAAAAgArABIABAlnDGoYAAEBBGgMAAAFACgAaQwAAAQAJwBrDAAAAQADAOoMAAACACsALgAECn8sAAISAAkJKhepDQBWAgASAAkJKhepDQBWAgAAAA==.Holyhand:BAABLgAECn8UAAITAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgATAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAQJDAASAGcMAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECgYJDAAHAAAAAA==.',
Il='Ilin:BAAALgAECgYJBwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgIJAgAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8oAAIUAAkJshRjAQAgAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQAUAAkJshRjAQAgAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQABLgAECggJFgAVAMwWAA==.',
Is='Isabela:BAABLgAFFH8HAAIWAAIJNyRdPgDXAAJoDAAABABaAOoMAAADAF4AFgACCTckXT4A1wACaAwAAAQAWgDqDAAAAwBeAAAA.Isilian:BAAALgADCgUJCAAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAQJDgALAGUkAA==.Judyhopp:BAABLgAECn8aAAQXAAgJWRYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAFwAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAMAAcJFxO+bQBIAQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABQAAQkAAE8OAAAAAWoMAAACAEAAAS4ABRQECQ4ACwBlJAA=.Judyhopps:BAAALgAECgYJDAABLgAFFAQJDgALAGUkAA==.',
Ka='Kaeln:BAAALgAECgMJAwABLgAECgYJBwAHAAAAAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgIJAgAAAA==.Kalzak:BAAALgAECgYJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJCwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECggJEQAHAAAAAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECgYJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAHAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgYJCAABLgAECgYJEQAHAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECgYJEQAHAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJCgAAAA==.',
Li='Lidravos:BAAALgADCgUJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIFAAMJPwXHQgDLAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAFAAMJPwXHQgDLAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwUACAlYHCQqAHwCAAUACAlYHCQqAHwCABIABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJEAADAKwVAA==.',
Ll='Lluvioso:BAACLgAFFH8HAAMPAAMJRh6aSQASAQNoDAAAAgBKAGkMAAABAEYA6gwAAAQAVwAPAAMJeR2aSQASAQNoDAAAAgBKAGkMAAABAEYA6gwAAAIAUAACAAEJ/iELHwBjAAHqDAAAAgBXAC4ABAp/HgADAgAJCesjWgIATAMAAgAJCU0jWgIATAMADwABCQ4f+NgAXgAAAAA=.',
Lo='Loaf:BAAALgAECgEJAwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIYAAcJdxwEEgDYAQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJABgABwl3HAQSANgBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgYJCAAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8UAAIMAAYJBAnCkQAEAQZoDAAABAAgAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAADAAwA6gwAAAUAFwAMAAYJBAnCkQAEAQZoDAAABAAgAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAADAAwA6gwAAAUAFwAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAHAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAMAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Merien:BAAALgAECgQJDQAAAA==.Meros:BAAALgAECgMJBwAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJDwAHAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgADCgcJBwAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECgcJDgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAQAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgYJCQAAAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAAALgAECgcJCwAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8WAAIMAAgJGRVLNgDfAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAAAwAwAGwMAAAEADoAbQwAAAEAJADqDAAAAwBLAG4MAAABADUADAAICRkVSzYA3wEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAMAMABsDAAABAA6AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAAALgAECgcJEQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8RAAIMAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAMAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAuAAQKfyIAAwwACAkOIp0YABcDAAwACAkOIp0YABcDABQAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8sAAITAAgJTB8LBwCdAghoDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAEwAICUwfCwcAnQIIaAwAAAcAUwBpDAAABgBbAGsMAAAGAFsAagwAAAUATgBsDAAABQBYAG0MAAAEAEwA6gwAAAcATABuDAAABAA3AAAA.',
Pr='Proctolodin:BAABLgAECn8aAAIFAAcJYxP7UwBiAQdoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAEAC4AbQwAAAIAJADqDAAABAAqAAUABwljE/tTAGIBB2gMAAAEAEMAaQwAAAQAMwBrDAAABAA0AGoMAAAEACQAbAwAAAQALgBtDAAAAgAkAOoMAAAEACoAAAA=.',
Pu='Purplefart:BAABLgAECn8cAAMZAAgJ8hKHFwCdAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABQA8AG4MAAABABoAGQAICfIShxcAnQEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAUAPABuDAAAAQAaABEAAQk/G5NGAFAAAWoMAAABAEUAAAA=.',
Ql='Qlaryx:BAAALgAECgYJEQAAAA==.',
Qu='Quinner:BAABLgAECn8qAAQGAAkJtRcNEQDiAQloDAAACABKAGkMAAAGAEcAawwAAAUARgBqDAAACABNAGwMAAADACAAbQwAAAEAJADqDAAABwBBAG4MAAADAFYAbwwAAAEALwAGAAgJEhkNEQDiAQhoDAAACABKAGkMAAAFAEcAawwAAAQARgBqDAAABwBNAGwMAAACACAA6gwAAAYAQQBuDAAAAgBWAG8MAAABAC8AGgAECb4FOjcAsgAEawwAAAEAEQBqDAAAAQATAGwMAAABAAsA6gwAAAEACgAbAAMJUwuCLgClAANpDAAAAQAQAG0MAAABACQAbgwAAAEAIgAAAA==.Qut:BAABLgAECn8cAAIcAAgJxR1wCQAgAghoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8AHAAICcUdcAkAIAIIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIMAAYJRxxzSwCaAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAMAAYJRxxzSwCaAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJEQAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgIJBQABLgAFFAMJCAAMAEgbAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDgAAAA==.Roxy:BAAALgADCgYJBgAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8xAAMdAAgJYxFCNgCfAQhoDAAACAAvAGkMAAAIADUAawwAAAgAMABqDAAABwA6AGwMAAAHADUAbQwAAAMAMADqDAAABgAlAG4MAAACABYAHQAICfUQQjYAnwEIaAwAAAgALwBpDAAABwA1AGsMAAAHADAAagwAAAYAOgBsDAAABgAtAG0MAAADADAA6gwAAAYAJQBuDAAAAgAWAB4ABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECgYJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8VAAMPAAYJ9AqVfwD8AAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAwAtAGwMAAADAB0A6gwAAAMAJQAPAAYJkwmVfwD8AAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAMJNQ1GNgBTAANqDAAAAQAtAGwMAAABAB0A6gwAAAEAJQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECgYJDAAHAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAHAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g+sUwAtAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g+sUwAtAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Sita:BAAALgADCgYJCAAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECgcJGgAFAGMTAA==.',
So='Sofferenza:BAAALgADCgcJEQAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8fAAMdAAgJCA44PwCAAQhoDAAABgArAGkMAAAFADYAawwAAAUAGQBqDAAAAwAfAGwMAAADACQAbQwAAAEADgDqDAAABQAtAG4MAAADAB8AHQAICQgOOD8AgAEIaAwAAAYAKwBpDAAABQA2AGsMAAAFABkAagwAAAEAHgBsDAAAAwAkAG0MAAABAA4A6gwAAAUALQBuDAAAAwAfAB8AAQkAAD1sADsAAWoMAAACAB8AAAA=.',
Sp='Spaceguy:BAABLgAECn8aAAIgAAcJhwVvOQDgAAdoDAAABAASAGkMAAAEAA0AawwAAAQADQBqDAAAAwAPAGwMAAAEAAkA6gwAAAUAFwBuDAAAAgAGACAABwmHBW85AOAAB2gMAAAEABIAaQwAAAQADQBrDAAABAANAGoMAAADAA8AbAwAAAQACQDqDAAABQAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECggJGgAJAGcNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAhAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgEJBAAHAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgUJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECgYJBwAHAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIZAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAZAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECgYJDAAAAA==.',
Te='Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAQJDAASAGcMAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAGANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8SAAIJAAUJEQ8XDgBfAQVoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAOoMAAADABQACQAFCREPFw4AXwEFaAwAAAQARwBpDAAABAAsAGsMAAAEABkAagwAAAMAHwDqDAAAAwAUAC4ABAp/FgACCQAJCZgc5wUA0AIACQAJCZgc5wUA0AIAAAA=.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgMJAwAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJEAAAAA==.',
Ve='Veldaan:BAAALgADCgcJBwAAAA==.',
Vi='Victra:BAAALgADCgYJBgABLgAECgYJDAAHAAAAAA==.Vipe:BAAALgAECgUJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgYJDAAHAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgQJCgAAAA==.Whiteleaf:BAABLgAECn8UAAIVAAcJDQglMAAgAQdoDAAAAwAaAGkMAAADABsAawwAAAMADgBqDAAAAwATAGwMAAADABEA6gwAAAQAGABuDAAAAQAMABUABwkNCCUwACABB2gMAAADABoAaQwAAAMAGwBrDAAAAwAOAGoMAAADABMAbAwAAAMAEQDqDAAABAAYAG4MAAABAAwAAAA=.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJEAAHAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgIJAgAAAA==.',
Xe='Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
Ze='Zeradias:BAAALgADCgYJBgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
