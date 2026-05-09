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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Druid-Balance','Shaman-Elemental','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Warlock-Destruction','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood','Priest-Holy','Rogue-Assassination','Paladin-Holy','Druid-Restoration','Druid-Guardian','Paladin-Protection','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abaddonmoon:BAABLgAECn8XAAIBAAYJOwfuCwDLAAABAAYJOwfuCwDLAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgEJAQAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ6DwDMAAACAAMJdgJ6DwDMAAAuAAQKfxUAAwIACAlAEVM9ALkBAAIACAlAEVM9ALkBAAMABAm8AoMmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8YAAMEAAYJnxh4BQCbAQAEAAUJBRx4BQCbAQAFAAMJ4gzuEACiAAAuAAQKfyAAAwQACQkUH8kVAJ8CAAQACAkpH8kVAJ8CAAUABAnMF/QRADIBAAAA.',
Ak='Akalifato:BAAALgAFFAMJAwABLgAFFAUJFQAGAB4eAA==.Akroma:BAAALgAECgIJAwAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgADCgMJAwABLgAECggJGgAHAM8IAA==.Alistin:BAAALgAECgQJBQAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgADCgcJCAAAAA==.Archanfel:BAABLgAECn8gAAIDAAYJ5wy+GwAmAQADAAYJ5wy+GwAmAQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgYJBgAAAA==.',
Ay='Ayonna:BAAALgAECgUJDAAAAA==.',
Az='Azar:BAAALgADCgUJBQAAAA==.',
Ba='Bandie:BAAALgAECgQJBwAAAA==.Barksalot:BAAALgADCgEJAQAAAA==.Barrakum:BAAALgAECgUJCwAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8HAAMFAAMJZRPNEwCFAAAEAAIJ+BVxIgCdAAAFAAIJtwjNEwCFAAAuAAQKfyEAAwUABwn6Id4FAA4CAAUABwnyHd4FAA4CAAQABQmnINUoADMBAAAA.Belletrixx:BAAALgAECgYJDwAAAA==.Berried:BAABLgAECn8uAAIIAAkJRx79AgANAwAIAAkJRx79AgANAwAAAA==.',
Bi='Biigmâc:BAAALgAECgcJEAAAAA==.Biminem:BAABLgAECn8YAAIJAAcJShXUCACVAQAJAAcJShXUCACVAQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAAALgAECgYJEQABLgAECggJHgAEAEkVAA==.',
Bo='Bodak:BAABLgAECn8bAAIKAAYJ5BnMNwCjAQAKAAYJ5BnMNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Broris:BAAALgAECgMJAwAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAABLgAECn8UAAILAAgJjBC8DwBnAQALAAgJjBC8DwBnAQAAAA==.Caliste:BAAALgADCgIJAgABLgAFFAQJDgAJAFgeAA==.Calityy:BAAALgADCgYJBgABLgAFFAYJDwADAEIfAA==.Camine:BAABLgAECn8lAAIMAAgJsRnXJQDpAQAMAAgJsRnXJQDpAQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgMJAwAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAAALgAECgYJDAAAAA==.',
Co='Constäntine:BAAALgAECgQJBAAAAA==.Coriolis:BAABLgAECn8kAAMNAAYJ3hkgGgBtAQANAAYJ3hkgGgBtAQAOAAMJggrnMACPAAAAAA==.',
Cr='Crowléy:BAAALgAECgQJBwAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIPAAcJwQ79qgCFAQAPAAcJwQ79qgCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgQJBQAAAA==.Daliann:BAAALgAECgYJCQAAAA==.Damnation:BAAALgAECgYJBgAAAA==.Dangerduck:BAAALgAECgUJDAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAAALgAECgYJCwAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8kAAMLAAYJ9yaUBQBHAgALAAYJ9yaUBQBHAgAEAAEJCSNpnQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgADCgQJBAABLgAECggJLgAQANgTAA==.',
Di='Diamondshard:BAAALgAECgIJAwAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDQAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECggJKwADADofAA==.Drosof:BAAALgADCgYJCwAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAABLgAECn8XAAIRAAYJbw1/GgAKAQARAAYJbw1/GgAKAQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8PAAIMAAUJCyKTFACAAQAMAAUJCyKTFACAAQAuAAQKfyMAAwwACQk1IA0YAOsCAAwACAn9IQ0YAOsCAAEAAwnvGPIJAPgAAAAA.',
['Dö']='Döctorfate:BAAALgAECgYJBgAAAA==.',
Ef='Effinsoldier:BAAALgAECgQJDAAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgAECgQJBQAAAA==.',
En='Endlessagony:BAABLgAECn8eAAIMAAkJBx4oIADBAgAMAAkJBx4oIADBAgAAAA==.Endlessice:BAAALgAECgQJBAAAAA==.Enyo:BAABLgAECn8fAAQSAAYJ3R8GJwDMAQASAAYJ3R8GJwDMAQATAAEJAAA0JwBVAAAQAAIJeAZ0XgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIUAAkJqBHBYQC/AQAUAAkJqBHBYQC/AQAAAA==.',
Fa='Falandril:BAAALgAECggJDwAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgMJAwAVAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8mAAMEAAkJMQ7gFADEAQAEAAkJMQ7gFADEAQAFAAcJwgQrJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgUJCQABLgAECgYJEgAVAAAAAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgEJAQAAAA==.Foughum:BAAALgADCgUJBQABLgAECgMJAwAVAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgYJCQAAAA==.',
Gi='Gilforty:BAAALgAECgcJEgAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAECggJJQAWAKoeAA==.Gloriosa:BAABLgAECn8vAAIXAAkJBQ5CFAC7AQAXAAkJBQ5CFAC7AQAAAA==.',
Gv='Gvendalyn:BAABLgAECn8cAAICAAcJaCY5CQCiAgACAAcJaCY5CQCiAgAAAA==.',
Gw='Gweyn:BAAALgADCgQJBQAAAA==.',
Gy='Gyatsò:BAABLgAECn8ZAAIYAAgJsxiVDADvAQAYAAgJsxiVDADvAQAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECggJFwAMAMgWAA==.Harshdk:BAABLgAECn8XAAIMAAgJyBaUJwDgAQAMAAgJyBaUJwDgAQAAAA==.',
He='Helel:BAABLgAECn8qAAMMAAYJmxf4UwBBAQAMAAYJahf4UwBBAQAZAAYJ5RHNFwAOAQAAAA==.',
Ho='Hops:BAAALgAECgIJAgAAAA==.',
Il='Illibanger:BAAALgAECgcJBwABLgAFFAMJBwAFAGUTAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECgYJEgAVAAAAAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmöney:BAAALgAFFAEJAQAAAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAABLgAECn8ZAAIPAAcJBx4oLADxAQAPAAcJBx4oLADxAQAAAA==.Jardalanin:BAAALgADCgEJAQAAAA==.',
Je='Jellyfish:BAABLgAECn8VAAMaAAgJMg5qGACMAQAaAAgJRgxqGACMAQAIAAgJxwf4GABrAQAAAA==.Jessamyn:BAAALgAECgMJAwAAAA==.',
Jh='Jhoira:BAAALgAECgYJCgAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8gAAQSAAkJ3h9KEABjAgASAAgJ3h9KEABjAgATAAIJ8yHCFwC+AAAQAAIJERNDVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8HAAIPAAIJ8xKVXQCrAAAPAAIJ8xKVXQCrAAAuAAQKfxUAAg8ACQkfDCF6AB0BAA8ACQkfDCF6AB0BAAAA.Kalifa:BAACLgAFFH8VAAIGAAUJHh5sCABrAQAGAAUJHh5sCABrAQAuAAQKfy4AAgYACAnwI8cDAMQCAAYACAnwI8cDAMQCAAAA.Kalinethe:BAAALgAECgEJAQAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECgUJBgAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBQAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8lAAIWAAgJqh4oDABtAgAWAAgJqh4oDABtAgAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECggJJQAWAKoeAA==.',
Ko='Komayetu:BAAALgADCgYJDgAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8XAAIbAAYJ9wO2EAACAQAbAAYJ9wO2EAACAQAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgcJEQAAAA==.Lazyace:BAAALgAECgIJBAAAAA==.',
Le='Lebenspender:BAABLgAECn8iAAIKAAYJWiKeDwBDAgAKAAYJWiKeDwBDAgAAAA==.Lextalonis:BAAALgAECgYJCAAAAA==.',
Li='Linkstery:BAABLgAECn8jAAMSAAgJYRhHUwDNAQASAAcJkhZHUwDNAQAQAAMJfRWvNADkAAAAAA==.',
Lo='Losvanknight:BAAALgAECgcJCAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgADCggJDAAAAA==.Mactacolover:BAAALgADCgUJBQAAAA==.Madbomber:BAAALgAECgYJDgAAAA==.Maeze:BAAALgAECgYJEgAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8GAAIcAAQJwhSMDgBFAQAcAAQJwhSMDgBFAQAuAAQKfyIAAxQACAk0H4sYADcCABQACAk0H4sYADcCABwACAkiCmE6AJABAAAA.Mawwowow:BAABLgAECn8cAAIWAAYJOhv0MgBpAQAWAAYJOhv0MgBpAQAAAA==.Maximillius:BAAALgAECgQJBQAAAA==.Mayjoraid:BAAALgAECgEJAQAAAA==.',
Me='Meekah:BAABLgAECn8xAAIIAAgJox/SAwDmAgAIAAgJox/SAwDmAgAAAA==.Melbrosha:BAAALgAECgQJCgAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAdAAAgAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQAVAAAAAA==.',
Mi='Mickspooky:BAACLgAFFH8UAAIMAAQJtxRbLQBFAQAMAAQJtxRbLQBFAQAuAAQKfycAAwwACAmZH0UpAJUCAAwACAmZH0UpAJUCABkAAwmLE4YjAKkAAAEuAAQKAwkDABUAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBgAAAA==.Milfy:BAAALgADCgQJBAABLgADCgUJBQAVAAAAAA==.Mintie:BAABLgAECn8eAAIeAAYJlBPMDwALAQAeAAYJlBPMDwALAQAAAA==.',
Mo='Moozylla:BAAALgAECggJCQAAAA==.Morrïgan:BAAALgAECgEJAQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8aAAIHAAgJzwgQJQAvAQAHAAgJzwgQJQAvAQAAAA==.Mynx:BAAALgAECgcJDAAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
Na='Nadira:BAAALgADCgYJBgABLgAECgYJEQAVAAAAAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAAALgAECgYJDAAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nimbus:BAAALgAECgMJBAABLgAFFAcJEwANACIUAA==.Nixii:BAABLgAECn8dAAIGAAYJGwzyKQD1AAAGAAYJGwzyKQD1AAAAAA==.',
No='Nocticula:BAABLgAECn8qAAIaAAgJ9QnvHQBaAQAaAAgJ9QnvHQBaAQAAAA==.',
Ny='Nyet:BAACLgAFFH8PAAMEAAUJOBDcDwAyAQAEAAUJOBDcDwAyAQAFAAEJYgbAGgBHAAAuAAQKfxwAAgQACQm9G1wcAGoCAAQACQm9G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgIJAgAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwAAAA==.',
Or='Orine:BAAALgAECggJDwAAAA==.Orioz:BAACLgAFFH8OAAIJAAQJWB5BAgBiAQAJAAQJWB5BAgBiAQAuAAQKfyQAAgkACAk0IvEDAOgCAAkACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECgUJBQABLgAECgYJCAAVAAAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgADCgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJDAAGAMwbAA==.Psychomurda:BAABLgAECn8cAAMUAAYJpAtWbgAQAQAUAAYJpAtWbgAQAQAfAAMJ/gcDJQBuAAABLgAECggJMQAIAKMfAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Ratpack:BAAALgAECgcJAQABLgAECgcJBwAVAAAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgADCgEJAQAAAA==.',
Sa='Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAAALgAECgUJCwAAAA==.',
Se='Seimie:BAAALgAECgcJEAAAAA==.Selithvia:BAAALgAECgYJDQAAAA==.Senethotsare:BAAALgAECgQJBQAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgAECgQJBQAVAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgEJAQAAAA==.Shaofikx:BAABLgAECn8kAAIgAAgJlQp5HQBIAQAgAAgJlQp5HQBIAQAAAA==.Shenknarok:BAABLgAECn8rAAIhAAYJ0xtxCQCPAQAhAAYJ0xtxCQCPAQAAAA==.Sherryl:BAABLgAECn8hAAIdAAYJlQ6uPgAZAQAdAAYJlQ6uPgAZAQAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgEJAQAAAA==.Skyari:BAABLgAECn8ZAAIEAAYJ8ySbDQATAgAEAAYJ8ySbDQATAgAAAA==.Skyarii:BAAALgAECgQJBwABLgAECgYJGQAEAPMkAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8aAAIMAAYJXQKMngCkAAAMAAYJXQKMngCkAAAAAA==.',
Sp='Spiritshard:BAAALgADCgcJEgAAAA==.Splashmountn:BAEALgAECgQJBQABLgAECgYJDwAVAAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAAALgAECgkJEQAAAA==.Sulfurya:BAAALgAECgQJBQAAAA==.',
Sy='Sykoman:BAACLgAFFH8MAAMGAAUJzBuhCQBeAQAGAAUJzBuhCQBeAQAdAAEJ5QCzSAAvAAAuAAQKfx0AAgYACAnvIXgLAN8CAAYACAnvIXgLAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDQAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgIJAgAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Therkage:BAAALgADCgcJEAAAAA==.Thesios:BAAALgADCgcJBwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thizz:BAABLgAECn8cAAIEAAYJPiD5KQASAgAEAAYJPiD5KQASAgABLgAFFAEJAQAVAAAAAA==.',
Ti='Tinksy:BAAALgADCgEJAQABLgADCgUJBQAVAAAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgADCggJCwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJBgAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgYJCgAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAAALgAECgUJBwABLgAECgYJCwAVAAAAAA==.',
Va='Vacuus:BAABLgAECn8XAAITAAgJRwgRBgBaAQATAAgJRwgRBgBaAQAAAA==.Vahldire:BAAALgAECgQJBwAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgADCgMJAwAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8hAAISAAYJxwbJbwDrAAASAAYJxwbJbwDrAAAAAA==.',
Vi='Viryda:BAAALgADCggJFgABLgAECggJJQAeAJcJAA==.',
Vo='Voidgram:BAAALgADCgQJBAAAAA==.',
Wa='Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn8uAAMQAAgJ2BNhCwALAgAQAAgJ2BNhCwALAgATAAEJwwEyOAAaAAAAAA==.',
Wo='Womplock:BAAALgAECgIJAgAAAA==.',
Wr='Wrâth:BAABLgAECn8oAAIPAAgJqBPlNQDKAQAPAAgJqBPlNQDKAQAAAA==.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIgAAgJvBqBFQBeAgAgAAgJvBqBFQBeAgABLgAECggJGgAgALwaAA==.',
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
