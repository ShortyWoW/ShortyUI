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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Unknown-Unknown','Paladin-Retribution','Evoker-Augmentation','Shaman-Elemental','DemonHunter-Havoc','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Warrior-Protection','Warlock-Demonology','Priest-Discipline','Paladin-Holy','Druid-Balance','Mage-Fire','Priest-Holy','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Priest-Shadow',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aayu:BAABLgAECn8ZAAIBAAcJiRZJFABZAQABAAcJiRZJFABZAQAAAA==.',
Ad='Addie:BAEBLgAFFH8FAAICAAIJ4hZtDgCDAAACAAIJ4hZtDgCDAAABLgAFFAYJFAADAIskAA==.Adranelidk:BAAALgADCgkJGwAAAA==.',
Ae='Aeromina:BAABLgAECn8XAAMBAAYJ7xMrIAAAAQABAAYJ7xMrIAAAAQAEAAEJZABCnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJDgAFAAAAAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpLNQBNAgAGAAgJAxpLNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJBwAAAA==.Alphabet:BAAALgADCgIJAgAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgADCgMJAwAAAA==.',
An='Ancalagon:BAAALgAECgYJCwAAAA==.Angelic:BAAALgAECgIJAgAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxkzGwCqAAAEAAIJLxkzGwCqAAAuAAQKfx8AAgQACQm5IiQDAHYDAAQACQm5IiQDAHYDAAAA.',
As='Ashveil:BAABLgAECn8bAAIHAAcJkwv5DQALAQAHAAcJkwv5DQALAQAAAA==.Asray:BAAALgADCgEJAQABLgADCgIJAgAFAAAAAA==.',
Au='Aussiesauce:BAAALgADCgcJBgABLgAECgUJBwAFAAAAAA==.Aussilicious:BAAALgAECgUJBwAAAA==.',
Az='Azerennia:BAAALgAECgUJCQAAAA==.Azrokke:BAAALgAECgUJCAAAAA==.',
Ba='Babetter:BAAALgAECgYJCwAAAA==.Baby:BAAALgAECgYJBgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAFAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECgUJBwAFAAAAAA==.',
Be='Beerless:BAAALgAECgUJCwAAAA==.Bencicil:BAAALgAECgUJCgAAAA==.Berkleyf:BAAALgADCgYJCQABLgAECggJHAAIAHgZAA==.Beydoon:BAAALgAECgEJAwAAAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgUJCAABLgAECgUJCwAFAAAAAA==.',
Br='Brain:BAAALgAECgEJAQAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Bro:BAAALgADCgEJAQAAAA==.',
Bu='Bunky:BAAALgAECgEJAgABLgAECggJHAAIAHgZAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8MAAIJAAQJESQLAQCuAQAJAAQJESQLAQCuAQAuAAQKfyMAAgkACAmcJsABAIYDAAkACAmcJsABAIYDAAAA.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8UAAMKAAcJ+w5ZYADBAAAKAAUJGQVZYADBAAALAAUJCRUpEgC/AAAAAA==.',
Ce='Cellynna:BAAALgADCggJEQAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAFAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECgUJDwAAAA==.',
Cy='Cynla:BAAALgAECgEJAQAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.David:BAABLgAECn8WAAIMAAgJ6BxoMACxAgAMAAgJ6BxoMACxAgAAAA==.',
Db='Dbsheep:BAAALgAECgIJAgAAAA==.',
De='Deezhealz:BAAALgAECgMJAwAAAA==.',
Di='Diddyfisting:BAACLgAFFH8GAAINAAMJ0CI/AgAmAQANAAMJ0CI/AgAmAQAuAAQKfyIAAw0ACAnvIlUFAC8DAA0ACAnvIlUFAC8DAAoAAQk6A3yPACYAAAAA.Divinefistin:BAEBLgAECn8cAAIKAAgJsxg7BwCJAQAKAAgJsxg7BwCJAQAAAA==.',
Dn='Dnova:BAAALgAECgIJAwAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCQAAAA==.Dornadions:BAAALgAECgYJCgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECgUJBgAAAA==.Draka:BAAALgAECgYJBwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgUJCwAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJBQAAAA==.',
Ec='Ecks:BAACLgAFFH8HAAIOAAMJQhR5BAC/AAAOAAMJQhR5BAC/AAAuAAQKfyYAAg4ACQn1HckCADgDAA4ACQn1HckCADgDAAAA.',
El='Elfuego:BAAALgAECgMJBAAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.',
Er='Erodorina:BAAALgAECgEJAQAAAA==.',
Et='Etir:BAABLgAECn8UAAIMAAcJMAySHwBYAQAMAAcJMAySHwBYAQAAAA==.',
Ev='Eviljoke:BAAALgADCgYJCAAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAAALgAECgEJAQAAAA==.',
Fi='Findinnan:BAAALgAECgUJBQAAAA==.Fishtotem:BAAALgADCgYJBwAAAA==.',
Fl='Flor:BAAALgADCgYJBgAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECgUJCAAAAA==.Frissbee:BAAALgADCgMJAwAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgEJAgAAAA==.Ganzar:BAAALgAECggJEwAAAA==.Gathan:BAAALgADCgQJBAAAAA==.',
Ge='Genderdruid:BAAALgADCgIJAgAAAA==.Genge:BAAALgAECgYJDgAAAA==.Gertrex:BAAALgAECgUJCwAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.',
Gl='Glennhelen:BAAALgADCgYJCAAAAA==.',
Go='Goatlord:BAAALgAECgYJDQAAAA==.Goatsavior:BAAALgAECgMJBQAAAA==.Goblinsrhot:BAAALgADCgYJCAAAAA==.Gotharm:BAAALgAECgQJBQAAAA==.',
Gr='Grester:BAABLgAECn8YAAIPAAgJrQtOFQBmAQAPAAgJrQtOFQBmAQAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAAALgADCgkJGQAAAA==.',
Ha='Hahmicydal:BAAALgAECgQJBwAAAA==.Hal:BAAALgADCgYJEQAAAA==.Havökush:BAAALgAECggJDwAAAA==.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgADCgEJAQAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIQAAcJmA0NBwCDAQAQAAcJmA0NBwCDAQAAAA==.Holyguard:BAACLgAFFH8FAAIRAAIJbA7cCQCIAAARAAIJbA7cCQCIAAAuAAQKfyQAAhEACAmsEksJAK8BABEACAmsEksJAK8BAAAA.Holyhand:BAAALgAECgYJDgABLgAFFAIJBQARAGwOAA==.',
Ic='Ickis:BAAALgADCgkJCQABLgAECgYJBgAFAAAAAA==.',
Il='Ilin:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Illidres:BAAALgADCgQJBAAAAA==.',
In='Influenza:BAAALgADCgQJCQAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAAALgAECggJEwAAAA==.',
Is='Isilian:BAAALgADCgUJCAAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgUJBwABLgAFFAMJBgANANAiAA==.Judyhopp:BAAALgAECgYJEgABLgAFFAMJBgANANAiAA==.Judyhopps:BAAALgAECgYJCgABLgAFFAMJBgANANAiAA==.',
Ka='Kaeln:BAAALgAECgMJAwABLgAECgYJBwAFAAAAAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kaluanights:BAAALgADCgIJAgAAAA==.Kalzak:BAAALgAECgUJCwAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAAALgADCgIJAQAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kiwistunna:BAAALgAECgYJDAAAAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAAALgAECgUJCwAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAFAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgEJAQAAAA==.',
La='Ladiemacbeth:BAAALgADCgYJCAABLgAECgUJCwAFAAAAAA==.Lanwynne:BAAALgADCgUJBAABLgAECgUJCwAFAAAAAA==.Laxion:BAAALgADCgkJFAAAAA==.',
Le='Leafs:BAAALgADCggJCAAAAA==.Leggo:BAAALgADCgcJEAAAAA==.',
Li='Lidravos:BAAALgADCgUJBQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8FAAIGAAMJOgVAKACXAAAGAAMJOgVAKACXAAAuAAQKfx4AAwYACAlYHCYqAHwCAAYACAlYHCYqAHwCABEABAnYAWl6AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAQJBgAEAL8MAA==.',
Ll='Lluvioso:BAABLgAECn8dAAICAAkJNiNXAgBMAwACAAkJNiNXAgBMAwAAAA==.',
Lo='Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8cAAISAAYJRB3nCQBPAQASAAYJRB3nCQBPAQAAAA==.',
Lu='Lunarbelle:BAAALgADCgYJCAAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAAALgAECgUJBwAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAFAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJaRw9HwBKAgABAAgJaRw9HwBKAgAEAAMJ+AV8cQB4AAAAAA==.',
Me='Merien:BAAALgAECgEJAQAAAA==.Meros:BAAALgADCgkJIwAAAA==.',
Mo='Monstrosoh:BAAALgAECgMJAwAAAA==.Moonstrudels:BAAALgADCgUJBwAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Natea:BAAALgAECgMJBQAAAA==.',
Ne='Nebüla:BAAALgAECgUJCAAAAA==.Neska:BAAALgAECgUJBgABLgAECgcJDQAFAAAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgADCgMJBAAAAA==.',
No='Norinna:BAAALgAECgMJAwAAAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAAALgAECgYJDAAAAA==.',
Pa='Painless:BAAALgAECgMJAgAAAA==.',
Ph='Phloemie:BAAALgADCgMJAwAAAA==.',
Po='Powerhøuse:BAACLgAFFH8LAAIMAAUJhBxiCQDUAQAMAAUJhBxiCQDUAQAuAAQKfx4AAwwACAkBIpkYABcDAAwACAkBIpkYABcDABMAAQkAABwRAC4AAAAA.Powerwordhug:BAABLgAECn8ZAAIUAAgJTxwfFgAsAgAUAAgJTxwfFgAsAgAAAA==.',
Pr='Proctolodin:BAAALgAECgYJDAAAAA==.',
Pu='Purplefart:BAAALgAECgYJEQAAAA==.',
Ql='Qlaryx:BAAALgAECgUJCwAAAA==.',
Qu='Quinner:BAABLgAECn8aAAQHAAgJMxYUJQCUAQAHAAcJihcUJQCUAQAVAAQJvgU0NwCyAAAWAAMJUwt2LgClAAAAAA==.Qut:BAABLgAECn8WAAIXAAYJGR9uBADBAQAXAAYJGR9uBADBAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAAALgAECgUJCwAAAA==.',
Ri='Riptoe:BAAALgADCgcJCwAAAA==.',
Ro='Rokey:BAAALgAECgIJAwABLgAFFAIJAgAFAAAAAA==.Rolling:BAAALgADCgEJAQAAAA==.Ronmaru:BAAALgAECgcJBwAAAA==.Roxy:BAAALgADCgYJBgAAAA==.',
Sa='Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn8aAAMPAAYJVhGCGgBBAQAPAAYJdRCCGgBBAQAYAAQJ9xIsFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAAALgAECgUJCgAAAA==.Seiken:BAAALgAECgcJEQAAAA==.Selas:BAAALgAECgQJBAAAAA==.Seryiana:BAAALgAECgEJAQAAAA==.',
Sh='Shadowflood:BAAALgAECgMJAwAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBAABLgAECgIJAgAFAAAAAA==.',
Si='Silk:BAAALgAECgMJBAAAAA==.Sita:BAAALgADCgYJCAAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgIJBAABLgAECgYJDAAFAAAAAA==.',
So='Sorulus:BAAALgADCgYJBgAAAA==.Souldance:BAABLgAECn8bAAMPAAcJqQ3/HAAzAQAPAAcJqQ3/HAAzAQAZAAEJAAArbAA7AAAAAA==.',
Sp='Spaceguy:BAAALgAECgYJEAAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJAwABLgAECgYJEgAFAAAAAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAAALgAECgUJCwAAAA==.',
Sw='Swato:BAAALgAECgEJAQAAAA==.',
Sy='Sylaang:BAAALgAECgEJAQAAAA==.',
Ta='Taliria:BAABLgAECn8aAAIaAAYJeBhNJgClAQAaAAYJeBhNJgClAQAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAAALgAECgYJBgAAAA==.',
Te='Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgADCgUJBQAAAA==.',
To='Torryn:BAAALgADCgYJBgAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.',
Uz='Uzumaki:BAAALgAECgEJAQAAAA==.',
Va='Vajrajavin:BAAALgAECgIJAgABLgAECgcJGwAHAJMLAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAAALgAFFAMJAwAAAA==.Valasca:BAAALgADCgcJBwAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECgQJBAAAAA==.',
Vi='Victra:BAAALgADCgYJBgABLgAECgYJBgAFAAAAAA==.Vipe:BAAALgAECgUJCAAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgYJBgAFAAAAAA==.',
Wa='Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAAALgAECgMJBQAAAA==.Whiteleaf:BAAALgAECgYJDAAAAA==.',
Wi='Wisdom:BAAALgADCgcJBwABLgAECgQJBAAFAAAAAA==.',
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
