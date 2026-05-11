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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Augmentation','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Shaman-Enhancement','Warlock-Demonology','Priest-Discipline','Paladin-Holy','Priest-Holy','Mage-Fire','Warrior-Fury','Mage-Arcane','Druid-Balance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='daily',zone=46,date='2026-05-10',data={Aa='Aayu:BAABLgAECn8hAAIBAAcJsRrzKgCmAQdoDAAABwA/AGkMAAAIAFMAawwAAAQATQBqDAAABAAoAGwMAAAEADYA6gwAAAUAQgBuDAAAAQBAAAEABwmxGvMqAKYBB2gMAAAHAD8AaQwAAAgAUwBrDAAABABNAGoMAAAEACgAbAwAAAQANgDqDAAABQBCAG4MAAABAEAAAAA=.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZyDgCDAAJqDAAABQAqAOoMAAABADoAAgACCeIWcg4AgwACagwAAAUAKgDqDAAAAQA6AAEuAAUUBwkbAAMAzCMA.Adranelidk:BAAALgAECgIJBAAAAA==.',
Ae='Aeromina:BAABLgAECn8YAAMBAAcJfBIKVAAUAQdoDAAABQBMAGkMAAAFAEAAawwAAAUANwBqDAAAAwApAGwMAAACABkAbQwAAAEAHADqDAAAAwAhAAEABwl8EgpUABQBB2gMAAAFAEwAaQwAAAUAQABrDAAABAA3AGoMAAADACkAbAwAAAIAGQBtDAAAAQAcAOoMAAADACEABAABCWQAWpwACgABawwAAAEAAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJIAAFADQaAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAghoDAAABABVAGkMAAAEAGEAawwAAAMAXQBqDAAAAwBJAGwMAAADAE0AbQwAAAEAEgDqDAAABABKAG4MAAABABMABgAICQMaQzUATQIIaAwAAAQAVQBpDAAABABhAGsMAAADAF0AagwAAAMASQBsDAAAAwBNAG0MAAABABIA6gwAAAQASgBuDAAAAQATAAAA.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAAALgAECgYJEQAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBQAAAA==.',
Ap='April:BAAALgAECgkJEwAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlPGwCqAAJoDAAAAwAuAGkMAAADAFIABAACCS8ZTxsAqgACaAwAAAMALgBpDAAAAwBSAC4ABAp/HwACBAAJCbkiJwMAeAMABAAJCbkiJwMAeAMAAAA=.',
As='Ashveil:BAABLgAECn8qAAIHAAgJ0w8HGgB6AQhoDAAABwAwAGkMAAAHADIAawwAAAcANABqDAAABgAdAGwMAAAGAC0AbQwAAAIADADqDAAABQAzAG4MAAACABcABwAICdMPBxoAegEIaAwAAAcAMABpDAAABwAyAGsMAAAHADQAagwAAAYAHQBsDAAABgAtAG0MAAACAAwA6gwAAAUAMwBuDAAAAgAXAAAA.Asray:BAAALgAECgIJAgABLgAFFAMJAwAIAAAAAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJDwAIAAAAAA==.Aussilicious:BAAALgAECggJDwAAAA==.',
Az='Azerennia:BAAALgAECgUJCQAAAA==.Azerious:BAAALgADCggJDgAAAA==.Azreya:BAAALgAECgEJAQAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8XAAIBAAYJlQYIbQDQAAZoDAAABAASAGkMAAAFAB0AawwAAAUACQBqDAAAAwAUAGwMAAADABYA6gwAAAMABAABAAYJlQYIbQDQAAZoDAAABAASAGkMAAAFAB0AawwAAAUACQBqDAAAAwAUAGwMAAADABYA6gwAAAMABAAAAA==.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAIAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJDwAIAAAAAA==.',
Be='Beerless:BAAALgAECgYJEQAAAA==.Belphegör:BAAALgADCgEJAQAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgkJHQAJAIQZAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgYJDAAIAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgUJBgAIAAAAAA==.Bro:BAAALgADCgIJAwAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAECgkJHQAJAIQZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8VAAIKAAUJFCQPAQCuAQVoDAAABwBfAGkMAAAGAF4AawwAAAMAVgBqDAAAAQBWAOoMAAAEAFwACgAFCRQkDwEArgEFaAwAAAcAXwBpDAAABgBeAGsMAAADAFYAagwAAAEAVgDqDAAABABcAC4ABAp/JgACCgAJCe4lwgEAhgMACgAJCe4lwgEAhgMAAAA=.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8gAAQLAAgJXhSxFwCjAQhoDAAABwBWAGkMAAAHADgAawwAAAYASwBqDAAAAQAbAGwMAAADABoAbQwAAAEAGgDqDAAABABOAG4MAAADACgACwAHCbgVsRcAowEHaAwAAAUAVgBpDAAABQA4AGsMAAAEAEsAbAwAAAEAGgBtDAAAAQAaAOoMAAAEAE4AbgwAAAMAKAAMAAUJGQVVYADBAAVoDAAAAgANAGkMAAACABAAawwAAAIABwBqDAAAAQAEAGwMAAABAA4ADQABCdwOg18ANgABbAwAAAEAJgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAIAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8nAAIOAAgJgiBAFACAAghoDAAABgBIAGkMAAAFAF4AawwAAAYAVgBqDAAABQBRAGwMAAAFAFkAbQwAAAMATwDqDAAABQBNAG4MAAAEAFIADgAICYIgQBQAgAIIaAwAAAYASABpDAAABQBeAGsMAAAGAFYAagwAAAUAUQBsDAAABQBZAG0MAAADAE8A6gwAAAUATQBuDAAABABSAAAA.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.',
Di='Diddyfisting:BAACLgAFFH8NAAINAAQJZST6AQCqAQRoDAAABQBaAGkMAAAEAGAAawwAAAEAWgDqDAAAAwBeAA0ABAllJPoBAKoBBGgMAAAFAFoAaQwAAAQAYABrDAAAAQBaAOoMAAADAF4ALgAECn8jAAMNAAgJ7yJUBQAvAwANAAgJ7yJUBQAvAwAMAAEJOgOLjwAmAAAAAA==.Divinefistin:BAABLgAECn8vAAMMAAkJeR06BgCAAgloDAAABwBOAGkMAAAHAFIAawwAAAgATQBqDAAABgBMAGwMAAAHAF0AbQwAAAEAPQDqDAAABwBfAG4MAAADAB0AbwwAAAEAVAAMAAkJYB06BgCAAgloDAAABgBOAGkMAAAFAFIAawwAAAYASwBqDAAABQBMAGwMAAAGAF0AbQwAAAEAPQDqDAAABgBfAG4MAAADAB0AbwwAAAEAVAANAAYJbB2ZEgCqAQZoDAAAAQBMAGkMAAACAEYAawwAAAIATQBqDAAAAQA8AGwMAAABAFAA6gwAAAEARgAAAA==.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECgUJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgYJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJBwAAAA==.',
Ec='Ecks:BAACLgAFFH8LAAIPAAQJRRxOCAAwAQRoDAAABABJAGkMAAAEAEoAawwAAAIATQDqDAAAAQBAAA8ABAlFHE4IADABBGgMAAAEAEkAaQwAAAQASgBrDAAAAgBNAOoMAAABAEAALgAECn8tAAMPAAkJBx7LAgA4AwAPAAkJBx7LAgA4AwAQAAEJAADkTQAAAAAAAA==.',
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
Ga='Gametheory:BAAALgAECgEJBAAAAA==.Ganzar:BAABLgAECn8bAAIRAAkJ9BwmDwCTAgloDAAAAwBXAGkMAAADAEUAawwAAAMAVABqDAAAAwBVAGwMAAADAGAAbQwAAAMARQDqDAAABQBcAG4MAAADAC0AbwwAAAEALwARAAkJ9BwmDwCTAgloDAAAAwBXAGkMAAADAEUAawwAAAMAVABqDAAAAwBVAGwMAAADAGAAbQwAAAMARQDqDAAABQBcAG4MAAADAC0AbwwAAAEALwAAAA==.Gathan:BAAALgADCgYJDwAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8aAAIGAAYJ1Q25cQAUAQZoDAAABgAlAGkMAAAFADQAawwAAAUAIQBqDAAAAwA1AGwMAAADAB8A6gwAAAQAFgAGAAYJ1Q25cQAUAQZoDAAABgAlAGkMAAAFADQAawwAAAUAIQBqDAAAAwA1AGwMAAADAB8A6gwAAAQAFgAAAA==.Gertrex:BAAALgAECgYJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgYJCAAAAA==.',
Go='Goatlord:BAABLgAECn8YAAISAAgJ6A3VCQCIAQhoDAAABAAmAGkMAAAEACcAawwAAAMAGwBqDAAAAwAYAGwMAAAEAB8AbQwAAAIAGQDqDAAAAwAhAG4MAAABADUAEgAICegN1QkAiAEIaAwAAAQAJgBpDAAABAAnAGsMAAADABsAagwAAAMAGABsDAAABAAfAG0MAAACABkA6gwAAAMAIQBuDAAAAQA1AAAA.Goatsavior:BAAALgAECgQJCQAAAA==.Goblinsrhot:BAAALgADCgYJCAAAAA==.Gotharm:BAAALgAECgYJEwAAAA==.',
Gr='Grester:BAABLgAECn8ZAAITAAgJzguGSABUAQhoDAAABAATAGkMAAAEADoAawwAAAMAIABqDAAABAAVAGwMAAADACMAbQwAAAIAHQDqDAAAAwAXAG4MAAACAAsAEwAICc4LhkgAVAEIaAwAAAQAEwBpDAAABAA6AGsMAAADACAAagwAAAQAFQBsDAAAAwAjAG0MAAACAB0A6gwAAAMAFwBuDAAAAgALAAAA.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJBQAAAA==.',
Ha='Hahmicydal:BAAALgAECgUJEQAAAA==.Hal:BAAALgADCgcJHgAAAA==.Havökush:BAABLgAECn8ZAAIKAAkJaB4UAwDAAgloDAAABQBeAGkMAAADAFUAawwAAAMATABqDAAAAwBeAGwMAAADAEsAbQwAAAMARwDqDAAAAgBSAG4MAAACAFAAbwwAAAEAOAAKAAkJaB4UAwDAAgloDAAABQBeAGkMAAADAFUAawwAAAMATABqDAAAAwBeAGwMAAADAEsAbQwAAAMARwDqDAAAAgBSAG4MAAACAFAAbwwAAAEAOAAAAA==.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIUAAcJmw2TGgBqAQdoDAAABgArAGkMAAAEAB4AawwAAAUAKgBqDAAAAwAgAGwMAAACADEAbQwAAAEAEQDqDAAABQAbABQABwmbDZMaAGoBB2gMAAAGACsAaQwAAAQAHgBrDAAABQAqAGoMAAADACAAbAwAAAIAMQBtDAAAAQARAOoMAAAFABsAAAA=.Holyguard:BAACLgAFFH8IAAIVAAMJCRBOHADSAANoDAAABAAoAGkMAAADACcA6gwAAAEAKwAVAAMJCRBOHADSAANoDAAABAAoAGkMAAADACcA6gwAAAEAKwAuAAQKfysAAhUACAljGPAQAB4CABUACAljGPAQAB4CAAAA.Holyhand:BAABLgAECn8UAAIWAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgAWAAYJAg4DSQAVAQZoDAAABAAYAGkMAAADAB4AawwAAAIAFABqDAAABAAoAGwMAAAFAFgA6gwAAAIACgABLgAFFAMJCAAVAAkQAA==.',
Ic='Ickis:BAAALgADCgkJCQABLgAECgYJDAAIAAAAAA==.',
Il='Ilin:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgIJAgAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8oAAIXAAkJshQ1AQAmAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQAXAAkJshQ1AQAmAgloDAAABQA8AGkMAAAFAC4AawwAAAQANQBqDAAABQAgAGwMAAAGAC8AbQwAAAQAMgDqDAAABgA5AG4MAAAEAC4AbwwAAAEAPQABLgAECggJFgAYAMwWAA==.',
Is='Isabela:BAAALgAFFAIJBAAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAQJDQANAGUkAA==.Judyhopp:BAABLgAECn8aAAQZAAgJWRYxCAB2AQhoDAAAAwBMAGkMAAADAE8AawwAAAMAQwBqDAAABwBAAGwMAAAFAD8AbQwAAAEAIgDqDAAAAwA7AG4MAAABABQAGQAHCbASMQgAdgEHaAwAAAIATABpDAAAAQA5AGsMAAABAEMAagwAAAMAGABsDAAABAAZAOoMAAABACYAbgwAAAEAFAAOAAcJFxOCaABHAQdoDAAAAQAAAGkMAAACAE8AawwAAAIAOABqDAAAAgAzAGwMAAABAD8AbQwAAAEAIgDqDAAAAgA7ABcAAQkAAHMNAAAAAWoMAAACAEAAAS4ABRQECQ0ADQBlJAA=.Judyhopps:BAAALgAECgYJDAABLgAFFAQJDQANAGUkAA==.',
Ka='Kaeln:BAAALgAECgMJAwABLgAFFAMJCAAOAP8TAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgIJAgAAAA==.Kalzak:BAAALgAECgYJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJBwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECggJEQAIAAAAAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECgYJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAIAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgYJCAABLgAECgYJEQAIAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECgYJEQAIAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgUJCQAAAA==.',
Li='Lidravos:BAAALgADCgUJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwXpPADNAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAGAAMJPwXpPADNAANoDAAABQAUAGkMAAADAAgA6gwAAAIACwAuAAQKfyEAAwYACAlYHCAqAHwCAAYACAlYHCAqAHwCABUABAnYAXt6AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAYJDwAEAJgYAA==.',
Ll='Lluvioso:BAABLgAECn8eAAMCAAkJ6yNaAgBMAwloDAAABQBjAGkMAAAEAGMAawwAAAQAXQBqDAAAAwBjAGwMAAADAGAAbQwAAAIAWQDqDAAABQBhAG4MAAACAE8AbwwAAAIATwACAAkJTSNaAgBMAwloDAAABQBjAGkMAAAEAGMAawwAAAQAXQBqDAAAAwBjAGwMAAADAGAAbQwAAAIAWQDqDAAABQBhAG4MAAACAE8AbwwAAAEAQgARAAEJDh9qzQBeAAFvDAAAAQBPAAAA.',
Lo='Loaf:BAAALgAECgEJAwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8eAAIaAAcJdxy0EADWAQdoDAAABQBVAGkMAAAGAFsAawwAAAYAVABqDAAABABLAGwMAAADACgAbQwAAAEAPgDqDAAABQBJABoABwl3HLQQANYBB2gMAAAFAFUAaQwAAAYAWwBrDAAABgBUAGoMAAAEAEsAbAwAAAMAKABtDAAAAQA+AOoMAAAFAEkAAAA=.',
Lu='Lunarbelle:BAAALgADCgYJCAAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAAALgAECgYJDgAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAIAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw4HwBKAghoDAAABABZAGkMAAAEAFoAawwAAAIAVgBqDAAAAwBPAGwMAAABAE8AbQwAAAEAMQDqDAAABABNAG4MAAACACQAAQAICW4cOB8ASgIIaAwAAAMAWQBpDAAAAwBaAGsMAAACAFYAagwAAAMATwBsDAAAAQBPAG0MAAABADEA6gwAAAMATQBuDAAAAgAkAAQAAwn4BZRxAHgAA2gMAAABABEAaQwAAAEAGADqDAAAAQAEAAAA.',
Me='Merien:BAAALgAECgQJDQAAAA==.Meros:BAAALgAECgIJBAAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJDwAIAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgADCgcJBwAAAA==.Narasil:BAAALgADCgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECgcJDgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAQAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgYJCQABLgAECggJNgAOANAXAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAAALgAECgcJCwAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAAALgAECgcJEQAAAA==.',
Pa='Painless:BAAALgAECgcJEQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Powerhøuse:BAACLgAFFH8RAAIOAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAOAAYJShp2CQDUAQZoDAAABABdAGkMAAAEAF4AawwAAAMAUwBqDAAAAgAnAGwMAAABAAIA6gwAAAMAPgAuAAQKfyIAAw4ACAkOIp0YABcDAA4ACAkOIp0YABcDABcAAQkAAB4RAC4AAAAA.Powerwordhug:BAABLgAECn8sAAIWAAgJTB8nBgCiAghoDAAABwBTAGkMAAAGAFsAawwAAAYAWwBqDAAABQBOAGwMAAAFAFgAbQwAAAQATADqDAAABwBMAG4MAAAEADcAFgAICUwfJwYAogIIaAwAAAcAUwBpDAAABgBbAGsMAAAGAFsAagwAAAUATgBsDAAABQBYAG0MAAAEAEwA6gwAAAcATABuDAAABAA3AAAA.',
Pr='Proctolodin:BAABLgAECn8aAAIGAAcJYxPeTQBnAQdoDAAABABDAGkMAAAEADMAawwAAAQANABqDAAABAAkAGwMAAAEAC4AbQwAAAIAJADqDAAABAAqAAYABwljE95NAGcBB2gMAAAEAEMAaQwAAAQAMwBrDAAABAA0AGoMAAAEACQAbAwAAAQALgBtDAAAAgAkAOoMAAAEACoAAAA=.',
Pu='Purplefart:BAABLgAECn8bAAIbAAgJ8hJBFQCkAQhoDAAABgBKAGkMAAAFAD0AawwAAAQALgBqDAAAAwA2AGwMAAABAB0AbQwAAAIAJwDqDAAABQA8AG4MAAABABoAGwAICfISQRUApAEIaAwAAAYASgBpDAAABQA9AGsMAAAEAC4AagwAAAMANgBsDAAAAQAdAG0MAAACACcA6gwAAAUAPABuDAAAAQAaAAAA.',
Ql='Qlaryx:BAAALgAECgYJEQAAAA==.',
Qu='Quinner:BAABLgAECn8pAAQHAAkJtRd+DwDlAQloDAAACABKAGkMAAAGAEcAawwAAAUARgBqDAAABwBNAGwMAAADACAAbQwAAAEAJADqDAAABwBBAG4MAAADAFYAbwwAAAEALwAHAAgJEhl+DwDlAQhoDAAACABKAGkMAAAFAEcAawwAAAQARgBqDAAABgBNAGwMAAACACAA6gwAAAYAQQBuDAAAAgBWAG8MAAABAC8AHAAECb4FNzcAsgAEawwAAAEAEQBqDAAAAQATAGwMAAABAAsA6gwAAAEACgAdAAMJUwuCLgClAANpDAAAAQAQAG0MAAABACQAbgwAAAEAIgAAAA==.Qut:BAABLgAECn8cAAIeAAgJxR3hBwAxAghoDAAABgBbAGkMAAAEAE8AawwAAAQAUwBqDAAABABYAGwMAAAEAE0AbQwAAAEAKADqDAAABABRAG4MAAABAE8AHgAICcUd4QcAMQIIaAwAAAYAWwBpDAAABABPAGsMAAAEAFMAagwAAAQAWABsDAAABABNAG0MAAABACgA6gwAAAQAUQBuDAAAAQBPAAAA.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8XAAIOAAYJQhtFTQCIAQZoDAAABABLAGkMAAAEAFEAawwAAAQAQQBqDAAABABDAGwMAAABADgA6gwAAAYARgAOAAYJQhtFTQCIAQZoDAAABABLAGkMAAAEAFEAawwAAAQAQQBqDAAABABDAGwMAAABADgA6gwAAAYARgAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJEQAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgIJBQABLgAFFAIJBAAIAAAAAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDgAAAA==.Roxy:BAAALgADCgYJBgAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAQAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8pAAMTAAgJRxDeOACHAQhoDAAABwAuAGkMAAAHADUAawwAAAcAKABqDAAABgA6AGwMAAAGADUAbQwAAAIAMADqDAAABQAjAG4MAAABAA0AEwAICdkP3jgAhwEIaAwAAAcALgBpDAAABgA1AGsMAAAGACgAagwAAAUAOgBsDAAABQAtAG0MAAACADAA6gwAAAUAIwBuDAAAAQANAB8ABAn3EiwUAO0ABGkMAAABADUAawwAAAEAJgBqDAAAAQASAGwMAAABADUAAAA=.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECgYJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8VAAMRAAYJ9ApPdwD/AAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAwAtAGwMAAADAB0A6gwAAAMAJQARAAYJkwlPdwD/AAZoDAAABAAgAGkMAAAEABkAawwAAAQADQBqDAAAAgAoAGwMAAACABYA6gwAAAIAGwACAAMJNQ0uMwBUAANqDAAAAQAtAGwMAAABAB0A6gwAAAEAJQAAAA==.Seryiana:BAAALgAECgIJBAAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECgYJDAAIAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAIAAAAAA==.',
Si='Silk:BAAALgAECgYJDgAAAA==.Sita:BAAALgADCgYJCAAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECgcJGgAGAGMTAA==.',
So='Sofferenza:BAAALgADCgYJEAAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8fAAMTAAgJCA6yOgCBAQhoDAAABgArAGkMAAAFADYAawwAAAUAGQBqDAAAAwAfAGwMAAADACQAbQwAAAEADgDqDAAABQAtAG4MAAADAB8AEwAICQgOsjoAgQEIaAwAAAYAKwBpDAAABQA2AGsMAAAFABkAagwAAAEAHgBsDAAAAwAkAG0MAAABAA4A6gwAAAUALQBuDAAAAwAfACAAAQkAADtsADsAAWoMAAACAB8AAAA=.',
Sp='Spaceguy:BAABLgAECn8XAAIJAAcJhwXuNQDiAAdoDAAABAASAGkMAAAEAA0AawwAAAQADQBqDAAAAwAPAGwMAAADAAkA6gwAAAQAFwBuDAAAAQAGAAkABwmHBe41AOIAB2gMAAAEABIAaQwAAAQADQBrDAAABAANAGoMAAADAA8AbAwAAAMACQDqDAAABAAXAG4MAAABAAYAAAA=.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECggJGQALAGcNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAhAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgEJBAAIAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgUJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIbAAYJehhUJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAbAAYJehhUJgClAQZoDAAABgBGAGkMAAAGAD8AawwAAAYAQQBqDAAAAwAvAGwMAAADADcA6gwAAAYAOwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECgYJDAAAAA==.',
Te='Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAMJCAAVAAkQAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgUJCQABLgAECggJKgAHANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8NAAILAAUJVAqxDgBCAQVoDAAAAwBAAGkMAAADAA8AawwAAAMAGQBqDAAAAQAGAOoMAAADABQACwAFCVQKsQ4AQgEFaAwAAAMAQABpDAAAAwAPAGsMAAADABkAagwAAAEABgDqDAAAAwAUAC4ABAp/FgACCwAJCZgc0gQA2AIACwAJCZgc0gQA2AIAAAA=.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgMJAwAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJCwAAAA==.',
Vi='Victra:BAAALgADCgYJBgABLgAECgYJDAAIAAAAAA==.Vipe:BAAALgAECgUJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgYJDAAIAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgQJCQAAAA==.Whiteleaf:BAAALgAECgcJEwAAAA==.',
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
