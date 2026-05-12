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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Augmentation','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','Priest-Holy','Mage-Fire','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-12',data={Aa='Aayu:BAABLgAECn8hAAIBAAcJqhofKQDBAQdoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABAAoAGwMAAAEADYA6gwAAAUAQgBuDAAAAQBAAAEABwmqGh8pAMEBB2gMAAAHAD8AaQwAAAgAUwBrDAAABABNAGoMAAAEACgAbAwAAAQANgDqDAAABQBCAG4MAAABAEAAAAA=.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWdg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUBwkbAAMAzCMA.Adranelidk:BAAALgAECgIJBAAAAA==.',
Ae='Aeromina:BAABLgAECn8YAAMBAAcJfBL5WgAUAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAAAwAhAAEABwl8EvlaABQBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAADACEABAABCWQAWJwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJIAAFADQaAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAAALgAECgYJEQAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAAALgAECgkJEwAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZWBsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiKAMAeAMABAAJCbkiKAMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIHAAgJ0w8bGwB7AQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcABwAICdMPGxsAewEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAgABLgAFFAMJAwAIAAAAAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJDwAIAAAAAA==.Aussilicious:BAAALgAECggJDwAAAA==.',
Az='Azerennia:BAAALgAECgUJCQAAAA==.Azerious:BAAALgADCggJDgAAAA==.Azreya:BAAALgAECgEJAQAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8XAAIBAAYJlQbWcADZAAZoDAAABAASAGkMAAAFAB0AawwAAAUACQBqDAAAAwAUAGwMAAADABYA6gwAAAMABAABAAYJlQbWcADZAAZoDAAABAASAGkMAAAFAB0AawwAAAUACQBqDAAAAwAUAGwMAAADABYA6gwAAAMABAAAAA==.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAIAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJDwAIAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAAALgAECgYJEQAAAA==.Belphegör:BAAALgADCgEJAQAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQAJAIQZAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgYJDAAIAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgUJBgAIAAAAAA==.Bro:BAAALgADCgIJAwAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQAJAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8VAAIKAAUJFCQPAQCuAQVoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAOoMAAAEAFwACgAFCRQkDwEArgEFaAwAAAcAXwBpDAAABgBeAGsMAAADAFYAagwAAAEAVgDqDAAABABcAC4ABAp/JgACCgAJCe4lwwEAhgMACgAJCe4lwwEAhgMAAAA=.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8gAAQLAAgJXhQRGQCiAQhoDAAABwBWAGkMAAAHADgAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAADACgACwAHCbgVERkAogEHaAwAAAUAVgBpDAAABQA4AGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAMAKAAMAAUJGQVXYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4ADQABCdwOK2MANgABbAwAAAEAJgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAIAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8oAAIOAAkJSh0FDQDJAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAOAAkJSh0FDQDJAgloDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIAbwwAAAEAEQAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.',
Di='Diddyfisting:BAACLgAFFH8NAAINAAQJZSQ5AgCpAQRoDAAABQBaAGkMAAAEAGAAawwAAAEAWgDqDAAAAwBeAA0ABAllJDkCAKkBBGgMAAAFAFoAaQwAAAQAYABrDAAAAQBaAOoMAAADAF4ALgAECn8jAAMNAAgJ7yJVBQAvAwANAAgJ7yJVBQAvAwAMAAEJOgOJjwAmAAAAAA==.Divinefistin:BAEBLgAECn8vAAMMAAkJeR2XBgCAAgloDAAABwBOAGkMAAAHAFIAawwAAAgATQBqDAAABgBMAGwMAAAHAF0AbQwAAAEAPQDqDAAABwBfAG4MAAADAB0AbwwAAAEAVAAMAAkJYB2XBgCAAgloDAAABgBOAGkMAAAFAFIAawwAAAYASwBqDAAABQBMAGwMAAAGAF0AbQwAAAEAPQDqDAAABgBfAG4MAAADAB0AbwwAAAEAVAANAAYJbB2QEwCpAQZoDAAAAQBMAGkMAAACAEYAawwAAAIATQBqDAAAAQA8AGwMAAABAFAA6gwAAAEARgAAAA==.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECgUJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgYJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJBwAAAA==.',
Ec='Ecks:BAACLgAFFH8LAAIPAAQJRRw9CQAsAQRoDAAABABJAGkMAAAEAEoAawwAAAIATQDqDAAAAQBAAA8ABAlFHD0JACwBBGgMAAAEAEkAaQwAAAQASgBrDAAAAgBNAOoMAAABAEAALgAECn8tAAMPAAkJBx7MAgA4AwAPAAkJBx7MAgA4AwAQAAEJAAAXUgAAAAAAAA==.',
El='Elfuego:BAAALgAECgUJCQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgYJCAAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAAALgAECgcJDAAAAA==.',
Fe='Fenrisulfr:BAAALgADCgYJBgAAAA==.',
Fi='Findinnan:BAAALgAECgcJDAAAAA==.Fishtotem:BAAALgADCgYJBwAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECgcJDgAAAA==.Frissbee:BAAALgADCgMJAwAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgEJBAAAAA==.Ganzar:BAABLgAECn8bAAIRAAkJ9BxpEACSAgloDAAAAwBXAGkMAAADAEUAawwAAAMAVABqDAAAAwBVAGwMAAADAGAAbQwAAAMARQDqDAAABQBcAG4MAAADAC0AbwwAAAEALwARAAkJ9BxpEACSAgloDAAAAwBXAGkMAAADAEUAawwAAAMAVABqDAAAAwBVAGwMAAADAGAAbQwAAAMARQDqDAAABQBcAG4MAAADAC0AbwwAAAEALwAAAA==.Gathan:BAAALgADCgcJEAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8aAAIGAAYJ1Q28dQAYAQZoDAAABgAlAGkMAAAFADQAawwAAAUAIQBqDAAAAwA1AGwMAAADAB8A6gwAAAQAFgAGAAYJ1Q28dQAYAQZoDAAABgAlAGkMAAAFADQAawwAAAUAIQBqDAAAAwA1AGwMAAADAB8A6gwAAAQAFgAAAA==.Gertrex:BAAALgAECgYJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgYJCAAAAA==.',
Go='Goatlord:BAABLgAECn8YAAISAAgJ6A1jCgCIAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAAAwAhAG4MAAABADUAEgAICegNYwoAiAEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAMAIQBuDAAAAQA1AAAA.Goatsavior:BAAALgAECgQJCQAAAA==.Goblinsrhot:BAAALgADCgYJCAAAAA==.Gotharm:BAAALgAECgYJEwAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJBgAAAA==.',
Ha='Hahmicydal:BAAALgAECgUJEQAAAA==.Hal:BAAALgADCgcJHgAAAA==.Havökush:BAABLgAECn8ZAAIKAAkJaB57AwC7AgloDAAABQBeAGkMAAADAFUAawwAAAMATABqDAAAAwBeAGwMAAADAEsAbQwAAAMARwDqDAAAAgBSAG4MAAACAFAAbwwAAAEAOAAKAAkJaB57AwC7AgloDAAABQBeAGkMAAADAFUAawwAAAMATABqDAAAAwBeAGwMAAADAEsAbQwAAAMARwDqDAAAAgBSAG4MAAACAFAAbwwAAAEAOAAAAA==.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAITAAcJmw3hGwBqAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABMABwmbDeEbAGoBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8IAAIUAAMJCRB9HgDFAANoDAAABAAoAGkMAAADACcA6gwAAAEAKwAUAAMJCRB9HgDFAANoDAAABAAoAGkMAAADACcA6gwAAAEAKwAuAAQKfywAAhQACQkqFxkNAFgCABQACQkqFxkNAFgCAAAA.Holyhand:BAABLgAECn8UAAIVAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAVAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAMJCAAUAAkQAA==.',
Ic='Ickis:BAAALgADCgkJCQABLgAECgYJDAAIAAAAAA==.',
Il='Ilin:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgIJAgAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8oAAIWAAkJshRMAQAjAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQAWAAkJshRMAQAjAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQABLgAECggJFgAXAMwWAA==.',
Is='Isabela:BAABLgAFFH8FAAIYAAIJNyTLPADXAAJoDAAAAwBaAOoMAAACAF4AGAACCTckyzwA1wACaAwAAAMAWgDqDAAAAgBeAAAA.Isilian:BAAALgADCgUJCAAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAQJDQANAGUkAA==.Judyhopp:BAABLgAECn8aAAQZAAgJWRYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAGQAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAOAAcJFxNmawBMAQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABYAAQkAAPENAAAAAWoMAAACAEAAAS4ABRQECQ0ADQBlJAA=.Judyhopps:BAAALgAECgYJDAABLgAFFAQJDQANAGUkAA==.',
Ka='Kaeln:BAAALgAECgMJAwABLgAFFAMJCAAOAP8TAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgIJAgAAAA==.Kalzak:BAAALgAECgYJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJCwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECggJEQAIAAAAAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECgYJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAIAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgYJCAABLgAECgYJEQAIAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECgYJEQAIAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJCQAAAA==.',
Li='Lidravos:BAAALgADCgUJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwXiQADNAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwXiQADNAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABQABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAYJDwAEAJgYAA==.',
Ll='Lluvioso:BAACLgAFFH8GAAMRAAMJRh6TTwAAAQNoDAAAAgBKAGkMAAABAEYA6gwAAAMAVwARAAMJshaTTwAAAQNoDAAAAgBKAGkMAAABAEYA6gwAAAEAHAACAAEJ/iFCHgBkAAHqDAAAAgBXAC4ABAp/HgADAgAJCesjWgIATAMAAgAJCU0jWgIATAMAEQABCQ4fm9QAXgAAAAA=.',
Lo='Loaf:BAAALgAECgEJAwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8eAAIaAAcJdxzZEQDTAQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABQBJABoABwl3HNkRANMBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAFAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgYJCAAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAAALgAECgYJDgAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAIAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOh8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZZxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Merien:BAAALgAECgQJDQAAAA==.Meros:BAAALgAECgIJBAAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJDwAIAAAAAA==.',
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
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAAALgAECgcJEQAAAA==.',
Pa='Painless:BAAALgAECgcJEQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8RAAIOAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAOAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAuAAQKfyIAAw4ACAkOIp0YABcDAA4ACAkOIp0YABcDABYAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8sAAIVAAgJTB+1BgChAghoDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAFQAICUwftQYAoQIIaAwAAAcAUwBpDAAABgBbAGsMAAAGAFsAagwAAAUATgBsDAAABQBYAG0MAAAEAEwA6gwAAAcATABuDAAABAA3AAAA.',
Pr='Proctolodin:BAABLgAECn8aAAIGAAcJYxPUUABrAQdoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAEAC4AbQwAAAIAJADqDAAABAAqAAYABwljE9RQAGsBB2gMAAAEAEMAaQwAAAQAMwBrDAAABAA0AGoMAAAEACQAbAwAAAQALgBtDAAAAgAkAOoMAAAEACoAAAA=.',
Pu='Purplefart:BAABLgAECn8cAAMbAAgJ8hI5FgCkAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAABAA2AGwMAAABAB0AbQwAAAIAJwDqDAAABQA8AG4MAAABABoAGwAICfISORYApAEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAUAPABuDAAAAQAaABMAAQk/G9JEAFEAAWoMAAABAEUAAAA=.',
Ql='Qlaryx:BAAALgAECgYJEQAAAA==.',
Qu='Quinner:BAABLgAECn8pAAQHAAkJtRc3EADmAQloDAAACABKAGkMAAAGAEcAawwAAAUARgBqDAAABwBNAGwMAAADACAAbQwAAAEAJADqDAAABwBBAG4MAAADAFYAbwwAAAEALwAHAAgJEhk3EADmAQhoDAAACABKAGkMAAAFAEcAawwAAAQARgBqDAAABgBNAGwMAAACACAA6gwAAAYAQQBuDAAAAgBWAG8MAAABAC8AHAAECb4FOjcAsgAEawwAAAEAEQBqDAAAAQATAGwMAAABAAsA6gwAAAEACgAdAAMJUwuCLgClAANpDAAAAQAQAG0MAAABACQAbgwAAAEAIgAAAA==.Qut:BAABLgAECn8cAAIeAAgJxR2tCAAoAghoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8AHgAICcUdrQgAKAIIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8YAAIOAAYJexsaUACMAQZoDAAABABLAGkMAAAEAFEAawwAAAQAQQBqDAAABABDAGwMAAACADsA6gwAAAYARgAOAAYJexsaUACMAQZoDAAABABLAGkMAAAEAFEAawwAAAQAQQBqDAAABABDAGwMAAACADsA6gwAAAYARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJEQAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgIJBQABLgAFFAIJBgAOAOodAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDgAAAA==.Roxy:BAAALgADCgYJBgAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAQAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8pAAMfAAgJRxAHOwCJAQhoDAAABwAuAGkMAAAHADUAawwAAAcAKABqDAAABgA6AGwMAAAGADUAbQwAAAIAMADqDAAABQAjAG4MAAABAA0AHwAICdkPBzsAiQEIaAwAAAcALgBpDAAABgA1AGsMAAAGACgAagwAAAUAOgBsDAAABQAtAG0MAAACADAA6gwAAAUAIwBuDAAAAQANACAABAn3EisUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECgYJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8VAAMRAAYJ9ArnewD/AAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAwAtAGwMAAADAB0A6gwAAAMAJQARAAYJkwnnewD/AAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAMJNQ39NABUAANqDAAAAQAtAGwMAAABAB0A6gwAAAEAJQAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECgYJDAAIAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAIAAAAAA==.',
Si='Silk:BAAALgAECgYJDgAAAA==.Sita:BAAALgADCgYJCAAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECgcJGgAGAGMTAA==.',
So='Sofferenza:BAAALgADCgcJEQAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8fAAMfAAgJCA7ePACDAQhoDAAABgArAGkMAAAFADYAawwAAAUAGQBqDAAAAwAfAGwMAAADACQAbQwAAAEADgDqDAAABQAtAG4MAAADAB8AHwAICQgO3jwAgwEIaAwAAAYAKwBpDAAABQA2AGsMAAAFABkAagwAAAEAHgBsDAAAAwAkAG0MAAABAA4A6gwAAAUALQBuDAAAAwAfACEAAQkAAD1sADsAAWoMAAACAB8AAAA=.',
Sp='Spaceguy:BAABLgAECn8XAAIJAAcJhwXNNwDiAAdoDAAABAASAGkMAAAEAA0AawwAAAQADQBqDAAAAwAPAGwMAAADAAkA6gwAAAQAFwBuDAAAAQAGAAkABwmHBc03AOIAB2gMAAAEABIAaQwAAAQADQBrDAAABAANAGoMAAADAA8AbAwAAAMACQDqDAAABAAXAG4MAAABAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECggJGgALAGcNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAiAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgEJBAAIAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgUJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIbAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAbAAYJehhWJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECgYJDAAAAA==.',
Te='Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAMJCAAUAAkQAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgUJCQABLgAECggJKgAHANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8OAAILAAUJqAr1DwBBAQVoDAAAAwBAAGkMAAADAA8AawwAAAMAGQBqDAAAAgAKAOoMAAADABQACwAFCagK9Q8AQQEFaAwAAAMAQABpDAAAAwAPAGsMAAADABkAagwAAAIACgDqDAAAAwAUAC4ABAp/FgACCwAJCZgcagUA1gIACwAJCZgcagUA1gIAAAA=.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgMJAwAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJCwAAAA==.',
Ve='Veldaan:BAAALgADCgcJBwAAAA==.',
Vi='Victra:BAAALgADCgYJBgABLgAECgYJDAAIAAAAAA==.Vipe:BAAALgAECgUJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgYJDAAIAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgQJCQAAAA==.Whiteleaf:BAABLgAECn8UAAIXAAcJDQiDLgAjAQdoDAAAAwAaAGkMAAADABsAawwAAAMADgBqDAAAAwATAGwMAAADABEA6gwAAAQAGABuDAAAAQAMABcABwkNCIMuACMBB2gMAAADABoAaQwAAAMAGwBrDAAAAwAOAGoMAAADABMAbAwAAAMAEQDqDAAABAAYAG4MAAABAAwAAAA=.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJCwAIAAAAAA==.',
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
