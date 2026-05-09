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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Demonology','DeathKnight-Blood','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Warlock-Destruction','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Priest-Discipline','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Paladin-Protection','Priest-Shadow','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Achoo:BAAALgAECgQJBwAAAA==.',
Ai='Aitnd:BAAALgADCggJDgAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Al='Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAIJAgABAAAAAA==.Amongor:BAABLgAECn8YAAICAAYJ3h9wUAAAAgACAAYJ3h9wUAAAAgAAAA==.',
An='Anarisa:BAABLgAECn8oAAMDAAkJoxPAIgAcAgADAAkJoxPAIgAcAgAEAAUJcRGCCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAUJFgAFALEcAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgEJAgAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIDAAcJkBeiaQADAgADAAcJkBeiaQADAgABLgAFFAIJAgABAAAAAA==.Averse:BAACLgAFFH8FAAICAAIJqR3IZgCrAAACAAIJqR3IZgCrAAAuAAQKfyEAAgIACAnLGzEXAEICAAIACAnLGzEXAEICAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECggJAwABLgAECggJEwABAAAAAA==.Barley:BAAALgADCgQJBwAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepid:BAABLgAECn8rAAMGAAgJByI0CADNAQAHAAYJUiLRKQATAgAGAAUJXyA0CADNAQAAAA==.',
Bl='Bluetide:BAACLgAFFH8WAAIFAAUJsRxKBwChAQAFAAUJsRxKBwChAQAuAAQKfyAAAgUACQmaJVgCAF8DAAUACQmaJVgCAF8DAAAA.',
Br='Brokemav:BAABLgAECn8pAAIIAAcJuiCYAgCTAgAIAAcJuiCYAgCTAgAAAA==.Brooklin:BAABLgAECn8xAAIDAAkJnh6/EgCDAgADAAkJnh6/EgCDAgAAAA==.Bruutal:BAAALgAECgEJAQAAAA==.',
Bu='Busky:BAABLgAECn8eAAMFAAgJgRZYKwDfAQAFAAgJgRZYKwDfAQAJAAEJtRM8HQBAAAAAAA==.',
Ca='Carboncredit:BAABLgAECn8iAAIJAAkJrBAHCgAyAgAJAAkJrBAHCgAyAgAAAA==.Cassiopea:BAABLgAECn8VAAIKAAcJ5Bi3EgDJAQAKAAcJ5Bi3EgDJAQAAAA==.Caysia:BAAALgAFFAIJAgAAAA==.',
Ce='Cellcept:BAAALgAECgUJCgAAAA==.',
Ch='Chareth:BAABLgAECn8iAAIDAAgJpQnoVABtAQADAAgJpQnoVABtAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chinchillada:BAAALgAECgUJDAAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECgcJFAALALseAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
Da='Dabajabaza:BAABLgAECn8bAAIMAAcJnghxHQDXAAAMAAcJnghxHQDXAAAAAA==.Dabergerak:BAABLgAECn8hAAIHAAkJuCPsAAA5AwAHAAkJuCPsAAA5AwAAAA==.Daenys:BAAALgAECgMJAwABLgAFFAcJHwALAM0YAA==.Daggart:BAAALgAECgkJCAAAAA==.Dakrus:BAABLgAECn8jAAMNAAkJyxZJIAAjAgANAAgJqRZJIAAjAgAOAAYJaArNGQA4AQAAAA==.Dawin:BAAALgADCgEJAQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAAALgAECgUJCQABLgAECggJKAALADkSAA==.Deeiinndu:BAAALgADCgMJBgAAAA==.Dejanira:BAABLgAECn8gAAIPAAkJzhEoJgCbAQAPAAkJzhEoJgCbAQAAAA==.Demonslayerr:BAAALgADCgMJAwAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAABAAAAAA==.',
Di='Diddily:BAAALgAECgYJDwAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCggJFAAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAAALgAECgYJEQAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8iAAIMAAgJvhW4DQCWAQAMAAgJvhW4DQCWAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8ZAAIHAAgJKAtDHgB3AQAHAAgJKAtDHgB3AQAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQAAAA==.Elise:BAABLgAECn8jAAMQAAgJzBcjCQAvAgAQAAgJzBcjCQAvAgAIAAcJmBD4DgBBAQAAAA==.Elstrid:BAABLgAECn8UAAILAAcJux4wPAAcAgALAAcJux4wPAAcAgAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgADCgcJDAABLgAECggJJwARAH8lAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn8nAAIRAAgJfyXKAgDuAgARAAgJfyXKAgDuAgAAAA==.',
Fe='Felbourn:BAABLgAECn8ZAAMSAAgJhCGNCADZAgASAAgJhCGNCADZAgATAAIJuwllzABdAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAABLgAECn8yAAIUAAkJoBzYCADGAgAUAAkJoBzYCADGAgAAAA==.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgQJBAAAAA==.',
Ge='Gemini:BAAALgADCgcJDAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIDAAUJawR8PQAXAQADAAUJawR8PQAXAQABLgAFFAUJDgAVAM0HAA==.',
Gn='Gnarfok:BAAALgAECgMJCgAAAA==.',
Go='Goopster:BAAALgADCgcJCQAAAA==.',
Gr='Graamps:BAAALgAECgUJCAAAAA==.Gravedigger:BAABLgAECn8oAAIMAAgJPx7NBgApAgAMAAgJPx7NBgApAgAAAA==.',
Gu='Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgEJAQABLgAECggJHgAWAAkZAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
In='Inarios:BAABLgAECn8YAAMVAAcJBiBhBgCOAgAVAAcJBiBhBgCOAgAKAAEJtwyATgAwAAAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGQAXAHEYAA==.Ironnmonk:BAABLgAECn8ZAAQXAAkJcRiAGwAnAgAXAAkJcRiAGwAnAgAYAAEJihG7WAA6AAAZAAEJUgQudQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgEJAgAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECgcJFAALALseAA==.',
Ju='Jujufya:BAAALgADCgYJBgABLgAECgYJBwABAAAAAA==.Jujukni:BAAALgADCgUJCAABLgAECgYJBwABAAAAAA==.Jujumon:BAAALgAECgYJBwAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECgYJBwABAAAAAA==.Justimp:BAABLgAECn8iAAILAAkJOxOvHgD4AQALAAkJOxOvHgD4AQAAAA==.',
Ka='Kanon:BAAALgAECgUJBQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8FAAIaAAMJ2gT1HAC5AAAaAAMJ2gT1HAC5AAAAAA==.',
Ko='Konsistency:BAABLgAECn8ZAAITAAcJlA6dcgBNAQATAAcJlA6dcgBNAQAAAA==.Konviction:BAABLgAECn8YAAMUAAgJOBF9fACBAQAUAAgJOBF9fACBAQAbAAEJewG0TgAVAAAAAA==.',
Kr='Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAAALgAECgUJDAAAAA==.Lan:BAAALgADCgEJAQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAEALgAECggJEwAAAA==.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8OAAMVAAUJzQfDCABRAQAVAAUJzQfDCABRAQAcAAMJfQjAGQCZAAAuAAQKfxwAAxUACQmpGGkSACECABUACAk0GWkSACECABwABwmmF0IhAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIdAAMJxQFSKACtAAAdAAMJxQFSKACtAAAuAAQKfyEAAh0ACAkICzIyADcBAB0ACAkICzIyADcBAAAA.Lootadots:BAAALgADCgkJEwABLgAECgYJDAABAAAAAA==.',
Lu='Lumie:BAABLgAECn8kAAMKAAgJDSChCADCAgAKAAgJDSChCADCAgAcAAcJ4BGjGAB4AQAAAA==.Lunie:BAAALgAECgYJDQABLgAECggJJAAKAA0gAA==.',
Ma='Magadeoz:BAAALgAECgYJDAAAAA==.Magicshow:BAABLgAECn8bAAIDAAgJ7Q/2lACqAQADAAgJ7Q/2lACqAQAAAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwAAAA==.',
Mu='Murthius:BAAALgADCgEJAQAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAABLgAECn8YAAMCAAgJBRmuXQDZAQACAAgJBRmuXQDZAQAMAAIJVwZ8PgBWAAAAAA==.Neiry:BAAALgADCgcJBwAAAA==.',
No='Noctislucis:BAAALgAECgcJDwAAAA==.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAAALgAFFAEJAQABLgAFFAQJFQAXADklAA==.Noobmonkey:BAACLgAFFH8VAAIXAAQJOSXlAwC5AQAXAAQJOSXlAwC5AQAuAAQKfyoAAhcACQk1JR8EAEsDABcACQk1JR8EAEsDAAAA.Noobwarr:BAAALgAECgYJBgABLgAFFAQJFQAXADklAA==.Novax:BAAALgAECgMJAwAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMcAAIJsBF/FwCpAAAcAAIJsBF/FwCpAAAKAAIJtw30DQCOAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAAALgAECgUJDQABLgAECgcJEwABAAAAAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAUJFgAFALEcAA==.',
Po='Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn8WAAIWAAYJSxfgOgBhAQAWAAYJSxfgOgBhAQAAAA==.',
Pu='Putz:BAABLgAECn85AAITAAkJ2SD0BQDLAgATAAkJ2SD0BQDLAgAAAA==.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAUJFgAFALEcAA==.Rainbow:BAABLgAECn8bAAIZAAcJIx5lCgBGAgAZAAcJIx5lCgBGAgABLgAECggJJwARAH8lAA==.Rastasham:BAAALgADCgkJEAAAAA==.Ratfondler:BAABLgAECn8gAAMYAAkJkyBVAgD0AgAYAAkJkyBVAgD0AgAZAAIJmA7tRQBlAAAAAA==.',
Re='Reialaleigh:BAAALgAECgMJAwAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAITAAUJTBedCQCQAQATAAUJTBedCQCQAQAuAAQKfysAAhMACQnwH84HAE0DABMACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn8kAAIUAAgJ9w9dTgBbAQAUAAgJ9w9dTgBbAQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Sagesteppe:BAAALgAECgQJBAAAAA==.',
Sc='Scotticus:BAABLgAECn8aAAICAAgJ8wflZQAXAQACAAgJ8wflZQAXAQAAAA==.',
Se='Seditionist:BAAALgAECgYJEQAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgADCgUJBQAAAA==.',
Si='Sidthekid:BAAALgADCgkJEQAAAA==.Sinayion:BAABLgAECn8UAAIbAAYJ5gOrIgCBAAAbAAYJ5gOrIgCBAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAABAAAAAA==.',
Su='Sunarena:BAABLgAECn8aAAIUAAgJ/g1uXgAyAQAUAAgJ/g1uXgAyAQAAAA==.',
Ta='Tankobell:BAAALgAECgcJEAAAAA==.',
Th='Thannatos:BAAALgADCgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8hAAIDAAcJDhedNwDEAQADAAcJDhedNwDEAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAECgMJBQAAAA==.Varfus:BAACLgAFFH8WAAIeAAUJViRrAACiAQAeAAUJViRrAACiAQAuAAQKfyoAAh4ACQnmJa8AAFQDAB4ACQnmJa8AAFQDAAAA.',
Ve='Velentre:BAAALgAECgIJAgAAAA==.',
Vi='Vichy:BAAALgAECgMJBAAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAABLgAECn8WAAIUAAcJGSSuIwCaAgAUAAcJGSSuIwCaAgAAAA==.',
Wo='Wouka:BAABLgAECn8tAAMLAAkJfiUDAQBsAwALAAkJbSUDAQBsAwAIAAYJqiPVAwBQAgAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgMJAwAAAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zeposo:BAABLgAECn8WAAMKAAYJRhUCIABIAQAKAAYJRhUCIABIAQAcAAEJyASpVgAtAAABLgAECggJLQAFAJEZAA==.Zeptide:BAABLgAECn8tAAMFAAgJkRlOEwAcAgAFAAgJkRlOEwAcAgARAAYJIhCQKQAVAQAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECgIJAwAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAECggJMgALALwXAA==.',
Zu='Zugnuts:BAAALgADCgcJFgAAAA==.',
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
