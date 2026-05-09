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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Augmentation','Rogue-Outlaw','Unknown-Unknown','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Shaman-Enhancement','Warlock-Demonology','Priest-Discipline','Paladin-Holy','Priest-Holy','Mage-Fire','Warrior-Fury','Mage-Arcane','Druid-Balance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aayu:BAABLgAECn8bAAIBAAcJMhptOQBnAQABAAcJMhptOQBnAQAAAA==.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZwDgCDAAACAAIJ4hZwDgCDAAABLgAFFAcJGwADAMwjAA==.Adranelidk:BAAALgAECgIJBAAAAA==.',
Ae='Aeromina:BAABLgAECn8YAAMBAAcJfhJZUQAaAQABAAcJfhJZUQAaAQAEAAEJZABTnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJIAAFADYaAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgIJAgAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAAALgAECgYJEQAAAA==.Angelic:BAAALgAECgIJAgAAAA==.',
Ap='April:BAAALgAECgkJEwAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlGGwCqAAAEAAIJLxlGGwCqAAAuAAQKfx8AAgQACQm5IiYDAHgDAAQACQm5IiYDAHgDAAAA.',
As='Ashveil:BAABLgAECn8qAAIHAAgJ0w+HGAB9AQAHAAgJ0w+HGAB9AQAAAA==.Asray:BAAALgAECgIJAgABLgAFFAMJBwAIAE8bAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECgYJDAAJAAAAAA==.Aussilicious:BAAALgAECgYJDAAAAA==.',
Az='Azerennia:BAAALgAECgUJCQAAAA==.Azerious:BAAALgADCgUJBgAAAA==.Azreya:BAAALgAECgEJAQAAAA==.Azrokke:BAAALgAECgcJDgAAAA==.',
Ba='Babetter:BAABLgAECn8XAAIBAAYJlQaSZQDgAAABAAYJlQaSZQDgAAAAAA==.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAJAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECgYJDAAJAAAAAA==.',
Be='Beerless:BAAALgAECgYJEQAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECgMJBgAJAAAAAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgYJDAAJAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Bro:BAAALgADCgIJAwAAAA==.',
Bu='Bunky:BAAALgAECgMJBgAAAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8VAAIKAAUJFCQPAQCuAQAKAAUJFCQPAQCuAQAuAAQKfyYAAgoACQntJcIBAIYDAAoACQntJcIBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8gAAQLAAgJXBQdFgCmAQALAAcJthUdFgCmAQAMAAUJGQVSYADBAAANAAEJ3A44WwA2AAAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgABLgADCgcJDgAJAAAAAA==.Crims:BAAALgADCgcJDgAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgcJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8mAAIOAAgJgCC1EgCDAgAOAAgJgCC1EgCDAgAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.',
Di='Diddyfisting:BAACLgAFFH8NAAINAAQJZSTbAQCuAQANAAQJZSTbAQCuAQAuAAQKfyMAAw0ACAnvIlQFAC8DAA0ACAnvIlQFAC8DAAwAAQk6A4mPACYAAAAA.Divinefistin:BAEBLgAECn8vAAMMAAkJeB3PBQCCAgAMAAkJXx3PBQCCAgANAAYJbB2FEQCsAQAAAA==.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECgUJBgAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgYJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJBwAAAA==.',
Ec='Ecks:BAACLgAFFH8LAAIPAAQJRRxiBwA2AQAPAAQJRRxiBwA2AQAuAAQKfy0AAw8ACQkHHssCADgDAA8ACQkHHssCADgDABAAAQkAALlIAAAAAAAA.',
El='Elfuego:BAAALgAECgQJCAAAAA==.',
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
Ga='Gametheory:BAAALgAECgEJBAAAAA==.Ganzar:BAABLgAECn8bAAIRAAkJ8xzyDQCUAgARAAkJ8xzyDQCUAgAAAA==.Gathan:BAAALgADCgYJDwAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAABLgAECn8aAAIGAAYJ1Q0RagAZAQAGAAYJ1Q0RagAZAQAAAA==.Gertrex:BAAALgAECgYJDAAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgYJCAAAAA==.',
Go='Goatlord:BAABLgAECn8YAAISAAgJ5w0oCQCNAQASAAgJ5w0oCQCNAQAAAA==.Goatsavior:BAAALgAECgQJCQAAAA==.Goblinsrhot:BAAALgADCgYJCAAAAA==.Gotharm:BAAALgAECgYJEQAAAA==.',
Gr='Grester:BAABLgAECn8ZAAITAAgJxwuARQBYAQATAAgJxwuARQBYAQAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgAECgQJBQAAAA==.',
Ha='Hahmicydal:BAAALgAECgUJDAAAAA==.Hal:BAAALgADCgcJHgAAAA==.Havökush:BAABLgAECn8ZAAIKAAkJZx7WAgC/AgAKAAkJZx7WAgC/AgAAAA==.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIUAAcJmA3sGABsAQAUAAcJmA3sGABsAQAAAA==.Holyguard:BAACLgAFFH8IAAIVAAMJCBBRGgDSAAAVAAMJCBBRGgDSAAAuAAQKfysAAhUACAlhGHcPACUCABUACAlhGHcPACUCAAAA.Holyhand:BAABLgAECn8UAAIWAAYJAQ7+SAAVAQAWAAYJAQ7+SAAVAQABLgAFFAMJCAAVAAgQAA==.',
Ic='Ickis:BAAALgADCgkJCQABLgAECgYJDAAJAAAAAA==.',
Il='Ilin:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.Illidres:BAAALgADCgQJBAAAAA==.',
In='Influenza:BAAALgADCgQJCQAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8jAAIXAAgJRhP3AQDEAQAXAAgJRhP3AQDEAQABLgAECggJFgAYAMkWAA==.',
Is='Isabela:BAAALgAFFAIJBAAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgUJBwABLgAFFAQJDQANAGUkAA==.Judyhopp:BAABLgAECn8aAAQZAAgJVBYwCAB2AQAZAAcJqxIwCAB2AQAOAAcJFBNjYgBNAQAXAAEJAADODAAAAAABLgAFFAQJDQANAGUkAA==.Judyhopps:BAAALgAECgYJCgABLgAFFAQJDQANAGUkAA==.',
Ka='Kaeln:BAAALgAECgMJAwABLgAECgYJBwAJAAAAAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kaluanights:BAAALgADCgIJAgAAAA==.Kalzak:BAAALgAECgYJEQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgAECgQJBwAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECggJEQAJAAAAAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECgYJEQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAJAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgYJCAABLgAECgYJEQAJAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECgYJEQAJAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAAALgAECgQJBQAAAA==.',
Li='Lidravos:BAAALgADCgUJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPAU4OADOAAAGAAMJPAU4OADOAAAuAAQKfyEAAwYACAlYHCAqAHwCAAYACAlYHCAqAHwCABUABAnYAXd6AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAYJDwAEAI0YAA==.',
Ll='Lluvioso:BAABLgAECn8dAAICAAkJNiNaAgBMAwACAAkJNiNaAgBMAwAAAA==.',
Lo='Loaf:BAAALgAECgEJAwAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8eAAIaAAcJcBywDwDWAQAaAAcJcBywDwDWAQAAAA==.',
Lu='Lunarbelle:BAAALgADCgYJCAAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAAALgAECgYJDgAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAJAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJaRw4HwBKAgABAAgJaRw4HwBKAgAEAAMJ+AWOcQB4AAAAAA==.',
Me='Merien:BAAALgAECgQJCQAAAA==.Meros:BAAALgAECgIJBAAAAA==.',
Mo='Monstrosoh:BAAALgAECgQJCAAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECgYJDAAJAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgADCgcJBwAAAA==.Narasil:BAAALgADCgEJAQAAAA==.Natea:BAAALgAECgYJCwAAAA==.',
Ne='Nebüla:BAAALgAECgcJDgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAQAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgYJCQAAAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAAALgAECgQJBAAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgADCgQJBAAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAAALgAECgcJEQAAAA==.',
Pa='Painless:BAAALgAECgQJCwAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Powerhøuse:BAACLgAFFH8LAAIOAAUJhBxyCQDUAQAOAAUJhBxyCQDUAQAuAAQKfyIAAw4ACAkOIpsYABcDAA4ACAkOIpsYABcDABcAAQkAAB4RAC4AAAAA.Powerwordhug:BAABLgAECn8sAAIWAAgJTB+aBQCpAgAWAAgJTB+aBQCpAgAAAA==.',
Pr='Proctolodin:BAABLgAECn8aAAIGAAcJYRMoSABtAQAGAAcJYRMoSABtAQAAAA==.',
Pu='Purplefart:BAABLgAECn8bAAIbAAgJ3BLvEwCkAQAbAAgJ3BLvEwCkAQAAAA==.',
Ql='Qlaryx:BAAALgAECgYJEQAAAA==.',
Qu='Quinner:BAABLgAECn8pAAQHAAkJtRewDgDlAQAHAAgJEhmwDgDlAQAcAAQJvgU0NwCyAAAdAAMJUwt4LgClAAAAAA==.Qut:BAABLgAECn8cAAIeAAgJvx0IBwA8AgAeAAgJvx0IBwA8AgAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8XAAIOAAYJQhvySQCKAQAOAAYJQhvySQCKAQAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgADCgcJEQAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAECgIJBQABLgAFFAIJBAAJAAAAAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJDQAAAA==.Roxy:BAAALgADCgYJBgAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAQAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8pAAMTAAgJRxDDNACRAQATAAgJ2Q/DNACRAQAfAAQJ9xIsFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECgYJEAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAAALgAECgYJDwAAAA==.Seryiana:BAAALgAECgIJBAAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECgYJDAAJAAAAAA==.',
Sh='Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAJAAAAAA==.',
Si='Silk:BAAALgAECgYJDgAAAA==.Sita:BAAALgADCgYJCAAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgQJCQABLgAECgcJGgAGAGETAA==.',
So='Sofferenza:BAAALgADCgYJDAAAAA==.Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8fAAMTAAgJBg4/NwCIAQATAAgJBg4/NwCIAQAgAAEJAAAzbAA7AAAAAA==.',
Sp='Spaceguy:BAABLgAECn8XAAIhAAcJhwVRMwDjAAAhAAcJhwVRMwDjAAAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJAwABLgAECggJGQALAGcNAA==.Starwind:BAAALgAECgYJBgAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAiAOEZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAwABLgAECgEJBAAJAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgUJEAAAAA==.',
Sw='Swato:BAAALgAECgEJAQAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Taliria:BAABLgAECn8eAAIbAAYJeBhSJgClAQAbAAYJeBhSJgClAQAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECgYJDAAAAA==.',
Te='Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
To='Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAMJCAAVAAgQAA==.',
Uz='Uzumaki:BAAALgAECgYJDQAAAA==.',
Va='Vajrajavin:BAAALgAECgUJCAABLgAECggJKgAHANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8NAAILAAUJVAqgDQBDAQALAAUJVAqgDQBDAQAuAAQKfxYAAgsACQmWHGAEANwCAAsACQmWHGAEANwCAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgMJAwAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgUJCwAAAA==.',
Vi='Victra:BAAALgADCgYJBgABLgAECgYJDAAJAAAAAA==.Vipe:BAAALgAECgUJCgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgYJDAAJAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgQJCQAAAA==.Whiteleaf:BAAALgAECgcJEwAAAA==.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgUJCwAJAAAAAA==.',
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
