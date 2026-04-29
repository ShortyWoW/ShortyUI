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

local lookup = {'Rogue-Outlaw','Unknown-Unknown','Druid-Balance','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Shaman-Elemental','DeathKnight-Frost','Monk-Brewmaster','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Priest-Discipline','Warrior-Fury','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','Druid-Restoration','Mage-Frost','Paladin-Protection','Mage-Arcane','Hunter-Marksmanship','Evoker-Augmentation','Warrior-Arms','Hunter-Survival',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aevie:BAAALgADCgkJEwAAAA==.',
Af='Afterlìfe:BAAALgAECgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alorillan:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJCQABLgAECgcJEgACAAAAAA==.',
An='Andelynn:BAAALgADCgYJBgAAAA==.',
Ap='Applejuic:BAAALgAECgMJBQAAAA==.Appless:BAAALgADCgIJAgAAAA==.',
Ar='Araylia:BAABLgAECn8ZAAIDAAgJ/AwWNQBpAQADAAgJ/AwWNQBpAQAAAA==.Aridella:BAAALgAECgYJCwAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwACAAAAAA==.',
Au='Autumn:BAAALgADCgEJAgAAAA==.',
Av='Avena:BAAALgADCgEJAQAAAA==.',
Az='Azaizel:BAAALgAECgUJCQABLgAECgYJBgACAAAAAA==.Azusie:BAABLgAECn8ZAAIEAAcJ3w47EQCjAQAEAAcJ3w47EQCjAQAAAA==.',
Ba='Baddate:BAAALgADCggJDgAAAA==.Baddragøn:BAABLgAECn8fAAMFAAgJ0w+vAgDhAQAFAAgJ0w+vAgDhAQAGAAEJzQNoQgArAAAAAA==.Bangen:BAAALgAECgYJDQAAAA==.Bastria:BAAALgAECgYJDAAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAECggJHwAHAPQhAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECgcJFAAIALISAA==.Billywitchdr:BAABLgAECn8UAAIIAAcJshJ3MwCLAQAIAAcJshJ3MwCLAQAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJDgACAAAAAA==.',
Bl='Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8fAAIJAAgJvxK6AQCNAQAJAAgJvxK6AQCNAQAAAA==.',
Bo='Boltspark:BAAALgADCgIJAgAAAA==.Bowlenciaga:BAAALgADCgEJAQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgYJBgAAAA==.Brainfart:BAAALgADCgUJBQABLgAECgUJDAACAAAAAA==.Breloom:BAAALgADCgEJAQAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgYJBgAAAA==.',
Ca='Cariandria:BAAALgADCgkJDgAAAA==.',
Ch='Charbaby:BAAALgAECgQJBAAAAA==.Charming:BAABLgAECn8YAAIKAAgJoxnCHAAdAgAKAAgJoxnCHAAdAgAAAA==.Chelseah:BAAALgAECgYJDAABLgAECgYJDQACAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECggJEgAAAA==.',
Co='Coldknight:BAAALgAECgUJCAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAAALgAECgMJCAAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Cornpop:BAAALgAECgIJAgAAAA==.Cowret:BAABLgAECn8dAAMLAAgJ1RBkKwDaAQALAAgJ1RBkKwDaAQAMAAEJAAC5aAAAAAAAAA==.',
Cr='Crystalwolf:BAAALgAECgUJCAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAAALgAECgQJDgAAAA==.Darkjager:BAABLgAECn8eAAIHAAgJ6xiDCgDBAQAHAAgJ6xiDCgDBAQAAAA==.Darkways:BAAALgADCgMJAwAAAA==.Darlah:BAAALgAECgEJAQAAAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDQAAAA==.',
De='Deadcobra:BAAALgAECgcJDwAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgMJBgACAAAAAA==.Debtknight:BAABLgAECn8XAAINAAcJQRaNEwB2AQANAAcJQRaNEwB2AQAAAA==.Dehumidifier:BAABLgAECn8ZAAMOAAgJ8BmRGgAHAgAOAAgJ8BmRGgAHAgAPAAEJNwi6IQAzAAAAAA==.Deltria:BAAALgAECgQJBAAAAA==.Demonicron:BAAALgADCgMJAwAAAA==.Demonrot:BAAALgAECgQJBAAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8WAAIQAAgJnBnABgAKAgAQAAgJnBnABgAKAgAAAA==.Devussi:BAABLgAECn8WAAIQAAcJXxQXVQCkAQAQAAcJXxQXVQCkAQAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAAAAA==.Donangus:BAABLgAECn8UAAIRAAcJwQ4AJABzAQARAAcJwQ4AJABzAQAAAA==.Dotero:BAAALgAECgEJAgAAAA==.',
Dr='Dracreina:BAAALgAECgQJDwAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAAALgAECgYJEAAAAA==.',
Dv='Dvsmage:BAAALgAECgMJBgAAAA==.',
Eg='Egaik:BAAALgAECgEJAQAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elissauna:BAAALgAECgEJAQAAAA==.Elylea:BAAALgAECgcJEQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgEJAgAAAA==.Falabala:BAAALgADCgcJBwAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgQJBAAAAA==.Feorahir:BAAALgADCgYJBgAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8aAAIHAAgJVQ4kEAB/AQAHAAgJVQ4kEAB/AQAAAA==.Firereina:BAAALgADCgcJCAABLgAECgQJDwACAAAAAA==.',
Fl='Fleurminator:BAABLgAECn8ZAAISAAgJKRDROgC6AQASAAgJKRDROgC6AQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8UAAITAAcJvBxqDwAVAgATAAcJvBxqDwAVAgAAAA==.',
Fr='Frieia:BAAALgAECgQJCgAAAA==.Frostiilocks:BAAALgAECgEJAQAAAA==.Frostitutte:BAAALgAECgUJCwAAAA==.',
Ga='Galakrosh:BAABLgAECn8gAAMUAAgJcB1BFwDJAgAUAAgJcB1BFwDJAgAVAAEJAAB0YwBIAAAAAA==.Galarína:BAABLgAECn8cAAMWAAgJ4SG9EgA6AgAWAAYJ6iG9EgA6AgAXAAgJYxxZGQAXAgAAAA==.Gandora:BAABLgAECn8ZAAMNAAgJ5xM7XwDVAQANAAgJ5xM7XwDVAQAJAAEJ/wOWCQAzAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8aAAMSAAgJ9BlyDwAzAQAYAAYJWBdoIAA9AQASAAgJZhVyDwAzAQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gl='Glomps:BAAALgAECgIJAgABLgAECgcJFgAMADcUAA==.',
Gr='Greasemunkey:BAAALgAECgYJDwAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAABLgAECn8jAAIMAAgJzCEfFgDlAgAMAAgJzCEfFgDlAgAAAA==.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hamburger:BAAALgAECgYJDAAAAA==.Hampter:BAAALgAECgYJCQABLgAECggJFQAPANkaAA==.',
Ho='Holybean:BAAALgADCgcJBwABLgAECgMJBgACAAAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJBgAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgADCgEJAQAAAA==.',
Hu='Humzashaind:BAAALgAECgUJCQAAAA==.Huntt:BAAALgADCgcJBwAAAA==.',
In='Inferbloom:BAAALgADCgkJDwABLgAFFAIJBAACAAAAAA==.Infernum:BAAALgAFFAIJBAAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ja='Jackyvoker:BAAALgAECggJEwAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgYJDQACAAAAAA==.',
Ji='Jinksey:BAAALgAECgcJCwAAAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgEJAQAAAA==.',
Ka='Kalidormi:BAAALgAECgIJAgAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kayelalynn:BAABLgAECn8UAAMDAAgJwQ2bPwAzAQADAAgJwQ2bPwAzAQAZAAMJNgEewgBDAAAAAA==.',
Kd='Kd:BAAALgADCgMJAwAAAA==.',
Ke='Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8dAAIKAAgJXSCCBADYAQAKAAgJXSCCBADYAQAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAABLgAECn8XAAIQAAcJEhvLDACtAQAQAAcJEhvLDACtAQABLgABCgQJBAACAAAAAA==.',
Kh='Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJCwAAAA==.Kicsi:BAAALgADCgYJBQAAAA==.Kilan:BAAALgAECgQJDQAAAA==.Killinrage:BAAALgAECgYJCgAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFAAaANoXAA==.',
Kr='Krynj:BAAALgAFFAEJAQAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn8XAAIHAAcJXBZAEAB+AQAHAAcJXBZAEAB+AQAAAA==.Kyokin:BAABLgAECn8VAAMMAAcJbwt6KAACAQAMAAYJpw16KAACAQAbAAUJ2gIhNAB4AAAAAA==.Kyzula:BAAALgAECgIJAwAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAQAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilylocks:BAAALgAECgYJCAAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.',
Lo='Lockology:BAAALgAECgEJAgAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAABLgAECn8dAAIcAAgJihu0AQCpAgAcAAgJihu0AQCpAgABLgAECggJGgASAOEbAA==.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAABLgAECn8iAAIZAAgJkBXHDACHAQAZAAgJkBXHDACHAQAAAA==.Lyniah:BAAALgAECgEJAQAAAA==.',
Ma='Maelius:BAABLgAECn8ZAAILAAgJRBntIgAIAgALAAgJRBntIgAIAgAAAA==.Maggrus:BAAALgAECgUJDAAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8YAAIdAAgJdxHyAgCTAQAdAAgJdxHyAgCTAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Matheney:BAAALgAFFAMJAwABLgAECgcJHAAeAK0eAA==.Maxnem:BAAALgADCggJCAABLgAECggJGgADAC0PAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgEJAQAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgMJBAAAAA==.Melidin:BAAALgAECgcJDAAAAA==.Melinda:BAAALgADCgYJBgAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgUJCAAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAAALgAECgUJCgAAAA==.',
Mo='Monk:BAAALgAECggJDgAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgMJBQAAAA==.',
Mu='Murdalok:BAAALgAECggJEwAAAA==.',
My='Mystahmurdah:BAAALgADCgQJBwABLgADCgcJCwACAAAAAA==.Mysterioñ:BAAALgAECgQJCwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJCgAAAA==.',
Na='Nasine:BAAALgAECgYJCAAAAA==.Natstryker:BAABLgAECn8eAAQKAAgJzCNSAwAEAgAXAAYJiiJEFQBCAgAKAAgJaiNSAwAEAgAWAAIJbgeWYQBJAAAAAA==.Naturemyth:BAAALgAECgEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8YAAIQAAYJchDLHgASAQAQAAYJchDLHgASAQAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
No='Nonaha:BAAALgADCgkJDAAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Oo='Oolong:BAAALgADCgQJBAAAAA==.',
Or='Organa:BAAALgAECgQJCQAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgADCgMJAwAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJCgACAAAAAA==.',
Pe='Petal:BAAALgAECgYJBgABLgAECggJDgACAAAAAA==.',
Pl='Plowmcballs:BAABLgAECn8VAAIMAAYJlREufgB+AQAMAAYJlREufgB+AQAAAA==.Plugley:BAAALgAECgYJEAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAAALgAECgYJEAAAAA==.Potooòooóoo:BAAALgAECgUJEwAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAQAAAA==.',
Py='Pygos:BAAALgAECggJEwAAAA==.',
['Pë']='Përdü:BAAALgAECgQJBAAAAA==.',
Ra='Raegnarok:BAAALgADCgkJDwAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgYJDQACAAAAAA==.Raigeki:BAAALgADCgEJAgAAAA==.Ralphie:BAAALgADCgYJBgAAAA==.Ratapew:BAAALgAECgQJBAAAAA==.Ratheen:BAABLgAECn8UAAIMAAYJEBGPkwBWAQAMAAYJEBGPkwBWAQAAAA==.Raytar:BAABLgAECn8WAAMDAAcJLSCnEQCOAgADAAcJLSCnEQCOAgAZAAIJrRzymgCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECggJHwAFANMPAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgADCgMJAQABLgAECgUJEQACAAAAAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Rogun:BAAALgADCgkJCQAAAA==.Ros:BAAALgADCgYJCQAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn8cAAIIAAgJuQWBEQD5AAAIAAgJuQWBEQD5AAAAAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIPAAgJHRWoGAAcAgAPAAgJHRWoGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAAALgAECgQJCgAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Scrapster:BAAALgAECgUJBQAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBQABLgAECgcJFgADAGwVAA==.Seshiro:BAAALgAECgQJBAABLgAECgcJHAAbAK4kAA==.',
Sh='Shadoweave:BAAALgAFFAIJAgABLgAFFAYJEwAHAAwQAA==.Shalalia:BAAALgADCgYJCwAAAA==.Shentsu:BAAALgAECgkJEgAAAA==.Shhanks:BAAALgADCgUJBQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAAALgAECgYJDAAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgADCgcJDgAAAA==.',
Sm='Smokeyb:BAAALgAECgYJEgAAAA==.',
Sn='Sneevie:BAAALgAECgUJBgAAAA==.Snorehees:BAABLgAECn8UAAMHAAgJwgxgNwDRAQAHAAgJwgxgNwDRAQAdAAEJXQAOnAAMAAAAAA==.',
So='Songstar:BAABLgAECn8XAAIHAAgJviKbEgCiAgAHAAgJviKbEgCiAgAAAA==.Soullraven:BAAALgADCgYJGgAAAA==.',
Sp='Spy:BAAALgAECgEJAQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAAALgAECgUJCAAAAA==.Stacy:BAAALgADCgEJAgABLgAECgQJCAACAAAAAA==.Starblaze:BAAALgAECgUJBgAAAA==.Starseek:BAAALgAECgYJEwAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarlick:BAAALgAECgYJEQAAAA==.Sugarpop:BAABLgAECn8lAAILAAgJEB+FEgB+AgALAAgJEB+FEgB+AgAAAA==.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAcJGQANAH4eAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQAAAA==.',
Ta='Taediah:BAAALgAECgIJAgAAAA==.Tamius:BAAALgADCgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgEJAQAAAA==.Thesarius:BAAALgAECggJEwAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAACAAAAAA==.',
Ti='Tiestto:BAAALgAECgQJBQAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8ZAAIaAAYJvAfoNgDpAAAaAAYJvAfoNgDpAAAAAA==.Toetagger:BAAALgAECgYJEAAAAA==.Tofino:BAAALgAECgEJAQAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tonimâster:BAAALgAECgIJBAAAAA==.Toyotama:BAAALgAECgUJCgAAAA==.',
Tr='Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgYJDQACAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAAALgAECgUJCAAAAA==.Tyshus:BAAALgAECgIJBAAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAgAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgUJCAACAAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgAAAA==.',
Va='Valarion:BAABLgAECn8aAAIfAAcJWQpiFQBVAQAfAAcJWQpiFQBVAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAAALgADCgUJBQAAAA==.Valinis:BAAALgADCggJDwAAAA==.Valorían:BAABLgAECn8eAAMSAAgJ2RqdHQBhAgASAAgJqRqdHQBhAgAYAAIJqRVKPABqAAAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn8qAAIaAAgJVx/PBwAsAgAaAAgJVx/PBwAsAgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJDAACAAAAAA==.',
Vo='Voidwa:BAAALgAECgYJCAAAAA==.Volbain:BAAALgAECgQJEAAAAA==.Volklin:BAABLgAECn8YAAMHAAYJcxTeTQB/AQAHAAYJcxTeTQB/AQAgAAMJBAZfJwB+AAAAAA==.Voltagex:BAABLgAECn8UAAIQAAcJGBciRwDXAQAQAAcJGBciRwDXAQAAAA==.',
Vu='Vulpsinculta:BAAALgAECgQJCwAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8aAAIDAAcJXQpMPABDAQADAAcJXQpMPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn8bAAMNAAgJsQknpwAzAQANAAcJUAonpwAzAQATAAEJ/QW5FQAlAAAAAA==.Wildkitty:BAAALgAECgYJBgAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wt='Wtfguën:BAAALgAECgQJDQAAAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8WAAIDAAcJbBVZJgDKAQADAAcJbBVZJgDKAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yu='Yuck:BAAALgAECgEJAQAAAA==.',
Yy='Yy:BAAALgAECgUJCwAAAA==.',
Ze='Zeuzco:BAAALgAECgkJDwAAAA==.',
['Ál']='Áltá:BAABLgAECn8YAAMUAAgJNRUYRwD1AQAUAAgJNRUYRwD1AQAVAAIJMwyoCgBwAAAAAA==.',
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
