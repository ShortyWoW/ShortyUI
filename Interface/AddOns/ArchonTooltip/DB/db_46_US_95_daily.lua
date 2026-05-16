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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Augmentation','Rogue-Outlaw','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Shaman-Enhancement','Hunter-Survival','Priest-Discipline','Paladin-Holy','Priest-Holy','Mage-Fire','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-14',data={Aa='Aayu:BAABLgAECn8mAAIBAAcJ/hsnLADGAQdoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABQAoAGwMAAAFAEoA6gwAAAYAQgBuDAAAAwBAAAEABwn+GycsAMYBB2gMAAAHAD8AaQwAAAgAUwBrDAAABABNAGoMAAAFACgAbAwAAAUASgDqDAAABgBCAG4MAAADAEAAAAA=.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUBwkbAAMAzCMA.Adranelidk:BAAALgAECgMJBwAAAA==.',
Ae='Aeromina:BAABLgAECn8YAAMBAAcJfBKyYwALAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAAAwAhAAEABwl8ErJjAAsBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAADACEABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJIgAFAH8aAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAAALgAECgYJEQAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAAALgAECgkJEwAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIHAAgJ0w+YIABlAQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcABwAICdMPmCAAZQEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAgABLgAFFAMJCgAIAGUdAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJDwAJAAAAAA==.Aussilicious:BAAALgAECggJDwAAAA==.',
Az='Azerennia:BAAALgAECgUJCQAAAA==.Azerious:BAAALgADCggJDgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8dAAIBAAYJ9QYbcQDoAAZoDAAABQASAGkMAAAGAB0AawwAAAYACwBqDAAABAAcAGwMAAAEABgA6gwAAAQABgABAAYJ9QYbcQDoAAZoDAAABQASAGkMAAAGAB0AawwAAAYACwBqDAAABAAcAGwMAAAEABgA6gwAAAQABgAAAA==.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAJAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJDwAJAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECgcJEQAAAA==.Belphegör:BAAALgADCgEJAQAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQAKAIQZAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgYJDAAJAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgUJBgAJAAAAAA==.Bro:BAAALgAECgEJAQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQAKAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8XAAILAAYJTyTHAADmAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAALAAYJTyTHAADmAQZoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAGwMAAABAF8A6gwAAAUAXAAuAAQKfyYAAgsACQnuJcMBAIYDAAsACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8hAAQMAAgJ6RYFFwDPAQhoDAAABwBWAGkMAAAHADgAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAAEAFwADAAHCaAYBRcAzwEHaAwAAAUAVgBpDAAABQA4AGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAQAXAANAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4ADgABCdwO/moAMwABbAwAAAEAJgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAJAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8oAAIPAAkJSh2PEQCuAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAPAAkJSh2PEQCuAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.',
Di='Diddyfisting:BAACLgAFFH8OAAIOAAQJZSS5AgClAQRoDAAABQBaAGkMAAAEAGAAawwAAAEAWgDqDAAABABeAA4ABAllJLkCAKUBBGgMAAAFAFoAaQwAAAQAYABrDAAAAQBaAOoMAAAEAF4ALgAECn8sAAMOAAgJIiRVBQAvAwAOAAgJIiRVBQAvAwANAAEJOgOJjwAmAAAAAA==.Divinefistin:BAEBLgAECn8yAAMNAAkJVx+9BwB1AgloDAAACABZAGkMAAAIAGEAawwAAAkAWQBqDAAABgBMAGwMAAAHAF0AbQwAAAEAPQDqDAAABwBfAG4MAAADAB0AbwwAAAEAVAANAAkJYB29BwB1AgloDAAABgBOAGkMAAAFAFIAawwAAAYASwBqDAAABQBMAGwMAAAGAF0AbQwAAAEAPQDqDAAABgBfAG4MAAADAB0AbwwAAAEAVAAOAAYJeiHaEADfAQZoDAAAAgBZAGkMAAADAGEAawwAAAMAWQBqDAAAAQA8AGwMAAABAFAA6gwAAAEARgAAAA==.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECgcJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgYJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8MAAIQAAQJRRwoCgAlAQRoDAAABABJAGkMAAAEAEoAawwAAAIATQDqDAAAAgBAABAABAlFHCgKACUBBGgMAAAEAEkAaQwAAAQASgBrDAAAAgBNAOoMAAACAEAALgAECn8zAAMQAAkJfB7MAgA4AwAQAAkJfB7MAgA4AwARAAEJAAAnWAAAAAAAAA==.',
El='Elfuego:BAAALgAECgUJCQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgYJCAAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAAALgAECgcJDAAAAA==.',
Fe='Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAAALgAECgcJDwAAAA==.Fishtotem:BAAALgADCgYJBwAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgEJBAAAAA==.Ganzar:BAACLgAFFH8FAAISAAMJyxd0UAAFAQNoDAAAAgA/AGkMAAABACIA6gwAAAIAVAASAAMJyxd0UAAFAQNoDAAAAgA/AGkMAAABACIA6gwAAAIAVAAuAAQKfxwAAhIACQn0HNEVAHYCABIACQn0HNEVAHYCAAAA.Gathan:BAAALgADCgcJEAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8gAAIGAAYJ1Q5NewAXAQZoDAAABwAlAGkMAAAGADYAawwAAAYAJQBqDAAABAA1AGwMAAAEAB8A6gwAAAUAHQAGAAYJ1Q5NewAXAQZoDAAABwAlAGkMAAAGADYAawwAAAYAJQBqDAAABAA1AGwMAAAEAB8A6gwAAAUAHQAAAA==.Gertrex:BAAALgAECgYJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgYJCAAAAA==.',
Go='Goatlord:BAABLgAECn8aAAITAAgJGg4GDABxAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAABAAhAG4MAAACADgAEwAICRoOBgwAcQEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAQAIQBuDAAAAgA4AAAA.Goatsavior:BAAALgAECgQJCQAAAA==.Goblinsrhot:BAAALgADCgYJCAAAAA==.Gotharm:BAABLgAECn8UAAIUAAYJqgyKIgAYAQZoDAAABAAkAGkMAAAEABwAawwAAAMAHwBqDAAAAQAFAGwMAAACACAA6gwAAAYAIQAUAAYJqgyKIgAYAQZoDAAABAAkAGkMAAAEABwAawwAAAMAHwBqDAAAAQAFAGwMAAACACAA6gwAAAYAIQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJCQAAAA==.',
Ha='Hahmicydal:BAAALgAECgUJEQAAAA==.Hal:BAAALgAECgIJAgAAAA==.Havökush:BAACLgAFFH8FAAILAAMJnAqoDQDZAANoDAAAAgAdAGkMAAABABsA6gwAAAIAGQALAAMJnAqoDQDZAANoDAAAAgAdAGkMAAABABsA6gwAAAIAGQAuAAQKfxoAAgsACQloHnoEAKkCAAsACQloHnoEAKkCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIVAAcJmw10HwBeAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABUABwmbDXQfAF4BB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8MAAIWAAQJZww+GQABAQRoDAAABQAoAGkMAAAEACcAawwAAAEAAwDqDAAAAgArABYABAlnDD4ZAAEBBGgMAAAFACgAaQwAAAQAJwBrDAAAAQADAOoMAAACACsALgAECn8sAAIWAAkJKhf9DgBOAgAWAAkJKhf9DgBOAgAAAA==.Holyhand:BAABLgAECn8UAAIXAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAXAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAQJDAAWAGcMAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECgYJDAAJAAAAAA==.',
Il='Ilin:BAAALgAECgYJBwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgIJAgAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8oAAIYAAkJshSXAQASAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQAYAAkJshSXAQASAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQABLgAECggJFgAZAMwWAA==.',
Is='Isabela:BAABLgAFFH8HAAIaAAIJNyQaPwDXAAJoDAAABABaAOoMAAADAF4AGgACCTckGj8A1wACaAwAAAQAWgDqDAAAAwBeAAAA.Isilian:BAAALgADCgUJCAAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAQJDgAOAGUkAA==.Judyhopp:BAABLgAECn8aAAQbAAgJWRYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAGwAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAPAAcJFxM8dwA7AQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABgAAQkAAK8OAAAAAWoMAAACAEAAAS4ABRQECQ4ADgBlJAA=.Judyhopps:BAAALgAECgYJDAABLgAFFAQJDgAOAGUkAA==.',
Ka='Kaeln:BAAALgAECgMJAwABLgAFFAMJCAAPAP8TAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgIJAgAAAA==.Kalzak:BAAALgAECgcJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJCwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECggJEQAJAAAAAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECgcJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAJAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgYJCAABLgAECgcJEQAJAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECgcJEQAJAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJCgAAAA==.',
Li='Lidravos:BAAALgADCgUJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwUCRQDJAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwUCRQDJAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABYABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJEQAEAKwVAA==.',
Ll='Lluvioso:BAACLgAFFH8HAAMSAAMJRh6oTAAPAQNoDAAAAgBKAGkMAAABAEYA6gwAAAQAVwASAAMJeR2oTAAPAQNoDAAAAgBKAGkMAAABAEYA6gwAAAIAUAACAAEJ/iEtIABiAAHqDAAAAgBXAC4ABAp/IwADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAEgABCQ4fZN8AXQAAAAA=.',
Lo='Loaf:BAAALgAECgEJAwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIcAAcJdxwrFADKAQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABgBJABwABwl3HCsUAMoBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAGAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgYJCAAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8UAAIPAAYJBAnVmQD6AAZoDAAABAAgAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAADAAwA6gwAAAUAFwAPAAYJBAnVmQD6AAZoDAAABAAgAGkMAAADABMAawwAAAMAGwBqDAAAAgAkAGwMAAADAAwA6gwAAAUAFwAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAJAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Merien:BAAALgAECgQJDQAAAA==.Meros:BAAALgAECgMJBwAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJDwAJAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgADCgcJBwAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECggJEAAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAQAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJCgABLgAECggJOAAPANAXAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAAALgAECgcJCwAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8WAAIPAAgJGRWEPADUAQhoDAAABAA4AGkMAAADACgAawwAAAMAOQBqDAAAAwAwAGwMAAAEADoAbQwAAAEAJADqDAAAAwBLAG4MAAABADUADwAICRkVhDwA1AEIaAwAAAQAOABpDAAAAwAoAGsMAAADADkAagwAAAMAMABsDAAABAA6AG0MAAABACQA6gwAAAMASwBuDAAAAQA1AAAA.',
Pa='Painless:BAAALgAECgcJEQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8RAAIPAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAPAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAuAAQKfyIAAw8ACAkOIp0YABcDAA8ACAkOIp0YABcDABgAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8sAAIXAAgJTB/xBwCVAghoDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAFwAICUwf8QcAlQIIaAwAAAcAUwBpDAAABgBbAGsMAAAGAFsAagwAAAUATgBsDAAABQBYAG0MAAAEAEwA6gwAAAcATABuDAAABAA3AAAA.',
Pr='Proctolodin:BAABLgAECn8aAAIGAAcJYxPiWwBaAQdoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAEAC4AbQwAAAIAJADqDAAABAAqAAYABwljE+JbAFoBB2gMAAAEAEMAaQwAAAQAMwBrDAAABAA0AGoMAAAEACQAbAwAAAQALgBtDAAAAgAkAOoMAAAEACoAAAA=.',
Pu='Purplefart:BAABLgAECn8eAAMdAAgJSROFGQCXAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABgA8AG4MAAACACEAHQAICUkThRkAlwEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAYAPABuDAAAAgAhABUAAQk/Gz1JAE8AAWoMAAABAEUAAAA=.',
Ql='Qlaryx:BAAALgAECgcJEQAAAA==.',
Qu='Quinner:BAABLgAECn8yAAQHAAkJ3hueBgCjAgloDAAACQBSAGkMAAAHAFIAawwAAAYAUQBqDAAACQBfAGwMAAAEAEYAbQwAAAIANQDqDAAACABBAG4MAAAEAFYAbwwAAAEALwAHAAkJ3hueBgCjAgloDAAACQBSAGkMAAAGAFIAawwAAAUAUQBqDAAACABfAGwMAAADAEYAbQwAAAEANQDqDAAABwBBAG4MAAADAFYAbwwAAAEALwAeAAQJvgU6NwCyAARrDAAAAQARAGoMAAABABMAbAwAAAEACwDqDAAAAQAKAB8AAwlTC4IuAKUAA2kMAAABABAAbQwAAAEAJABuDAAAAQAiAAAA.Qut:BAABLgAECn8cAAIgAAgJxR3yCwAGAghoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8AIAAICcUd8gsABgIIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIPAAYJRxyvUwCNAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAPAAYJRxyvUwCNAQZoDAAABQBLAGkMAAAFAFMAawwAAAUASQBqDAAABQBDAGwMAAADADsA6gwAAAcARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJEQAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgIJBQABLgAFFAMJCAAPAEgbAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDgAAAA==.Roxy:BAAALgADCgYJBgAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8xAAMhAAgJYxFaPQCQAQhoDAAACAAvAGkMAAAIADUAawwAAAgAMABqDAAABwA6AGwMAAAHADUAbQwAAAMAMADqDAAABgAlAG4MAAACABYAIQAICfUQWj0AkAEIaAwAAAgALwBpDAAABwA1AGsMAAAHADAAagwAAAYAOgBsDAAABgAtAG0MAAADADAA6gwAAAYAJQBuDAAAAgAWACIABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECgcJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8VAAMSAAYJ9AoniwDrAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAwAtAGwMAAADAB0A6gwAAAMAJQASAAYJkwkniwDrAAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAMJNQ3ZOABSAANqDAAAAQAtAGwMAAABAB0A6gwAAAEAJQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECgYJDAAJAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAJAAAAAA==.',
Si='Silk:BAABLgAECn8UAAIBAAYJ8g/JWgAiAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAABAAYJ8g/JWgAiAQZoDAAABQAxAGkMAAAEABoAawwAAAQAHQBqDAAAAgA3AGwMAAACADkA6gwAAAMAKAAAAA==.Sita:BAAALgADCgYJCAAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECgcJGgAGAGMTAA==.',
So='Sofferenza:BAAALgADCgcJEQAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8fAAMhAAgJCA6oRwBuAQhoDAAABgArAGkMAAAFADYAawwAAAUAGQBqDAAAAwAfAGwMAAADACQAbQwAAAEADgDqDAAABQAtAG4MAAADAB8AIQAICQgOqEcAbgEIaAwAAAYAKwBpDAAABQA2AGsMAAAFABkAagwAAAEAHgBsDAAAAwAkAG0MAAABAA4A6gwAAAUALQBuDAAAAwAfACMAAQkAAD1sADsAAWoMAAACAB8AAAA=.',
Sp='Spaceguy:BAABLgAECn8aAAIKAAcJhwVxPQDUAAdoDAAABAASAGkMAAAEAA0AawwAAAQADQBqDAAAAwAPAGwMAAAEAAkA6gwAAAUAFwBuDAAAAgAGAAoABwmHBXE9ANQAB2gMAAAEABIAaQwAAAQADQBrDAAABAANAGoMAAADAA8AbAwAAAQACQDqDAAABQAXAG4MAAACAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECggJHwAMAHYNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAkAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgEJBAAJAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgcJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECgYJBwAJAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIdAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAdAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECgYJDAAAAA==.',
Te='Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAQJDAAWAGcMAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAHANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8TAAIMAAUJ1BEmDgBpAQVoDAAABABHAGkMAAAEACwAawwAAAQAGQBqDAAAAwAfAOoMAAAEADcADAAFCdQRJg4AaQEFaAwAAAQARwBpDAAABAAsAGsMAAAEABkAagwAAAMAHwDqDAAABAA3AC4ABAp/HAACDAAJCWYd2AUA3AIADAAJCWYd2AUA3AIAAAA=.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJEAAAAA==.',
Ve='Veldaan:BAAALgADCgcJBwAAAA==.',
Vi='Victra:BAAALgADCgYJBgABLgAECgYJDAAJAAAAAA==.Vipe:BAAALgAECgYJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgYJDAAJAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgQJDQAAAA==.Whiteleaf:BAABLgAECn8UAAIZAAcJDQgLNAAXAQdoDAAAAwAaAGkMAAADABsAawwAAAMADgBqDAAAAwATAGwMAAADABEA6gwAAAQAGABuDAAAAQAMABkABwkNCAs0ABcBB2gMAAADABoAaQwAAAMAGwBrDAAAAwAOAGoMAAADABMAbAwAAAMAEQDqDAAABAAYAG4MAAABAAwAAAA=.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJEAAJAAAAAA==.',
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
