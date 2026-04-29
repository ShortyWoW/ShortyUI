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

local lookup = {'Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Druid-Balance','Priest-Discipline','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Warrior-Protection','Warlock-Destruction','DeathKnight-Frost','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Monk-Mistweaver','Paladin-Holy','Druid-Restoration','Priest-Holy','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abaddonmoon:BAAALgAECgYJEQAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgADCgEJAQAAAA==.Ahnari:BAACLgAFFH8FAAIBAAMJdgJ0DwDMAAABAAMJdgJ0DwDMAAAuAAQKfxUAAwEACAlAEVc9ALkBAAEACAlAEVc9ALkBAAIABAm8An8mAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8PAAMDAAYJBhXuAQBpAQADAAUJBhjuAQBpAQAEAAIJ/QbGBQBaAAAuAAQKfyAAAwMACQkUH9MVAJ8CAAMACAkpH9MVAJ8CAAQABAnMFw0FAEIBAAAA.',
Ak='Akalifato:BAAALgAECgIJAgABLgAFFAQJCgAFAJ8bAA==.Akroma:BAAALgAECgIJAwAAAA==.',
Al='Alariya:BAAALgADCgMJAwAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgADCgcJCAAAAA==.Archanfel:BAABLgAECn8UAAICAAYJHQzwFwBNAQACAAYJHQzwFwBNAQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgADCgcJDgAAAA==.',
Ay='Ayonna:BAAALgAECgMJBAAAAA==.',
Az='Azar:BAAALgADCgUJBQAAAA==.',
Ba='Bandie:BAAALgADCgkJEwAAAA==.Barrakum:BAAALgAECgEJAQAAAA==.Bayn:BAAALgADCgQJCAAAAA==.',
Be='Beeftruck:BAABLgAECn8UAAMEAAYJIxYWBABjAQADAAUJ5hmFSgB7AQAEAAYJWRQWBABjAQAAAA==.Berried:BAABLgAECn8dAAIGAAgJBxhaAwAKAgAGAAgJBxhaAwAKAgAAAA==.',
Bi='Biigmâc:BAAALgAECgcJEAAAAA==.Biminem:BAAALgAECgUJCwAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAAALgAECgQJBwAAAA==.',
Bo='Bodak:BAABLgAECn8VAAIHAAYJ5BnGDgBTAQAHAAYJ5BnGDgBTAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Broris:BAAALgAECgMJAwAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAAALgAECgYJDQAAAA==.Caliste:BAAALgADCgIJAgABLgAFFAMJBgAIAKgZAA==.Calityy:BAAALgADCgYJBgABLgAFFAUJBgACAMITAA==.Camine:BAABLgAECn8WAAIJAAcJFRfZVwDqAQAJAAcJFRfZVwDqAQAAAA==.Castalasaras:BAAALgAECgIJAgAAAA==.Castorsilver:BAAALgADCgQJBAAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAAALgAECgYJBgAAAA==.',
Co='Constäntine:BAAALgADCggJDQAAAA==.Coriolis:BAABLgAECn8YAAMKAAYJhBiFCQBOAQAKAAYJhBiFCQBOAQALAAMJggrmMACPAAAAAA==.',
Cr='Crowléy:BAAALgADCgkJEwAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8UAAIMAAcJwQ4DqwCFAQAMAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgADCgkJEQAAAA==.Daliann:BAAALgAECgMJAwAAAA==.Dangerduck:BAAALgAECgIJAwAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAAALgAECgQJBQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8YAAMNAAYJ3iZ0AQA+AgANAAYJ3iZ0AQA+AgADAAEJCSNZnQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgADCgQJBAABLgAECggJKAAOAFQSAA==.',
Di='Diamondshard:BAAALgAECgEJAQAAAA==.',
Dr='Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDQAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECggJGQACAI4eAA==.Drosof:BAAALgADCgQJBQAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAAALgAECgYJDgAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8KAAIJAAQJhxoPBAByAQAJAAQJhxoPBAByAQAuAAQKfyAAAwkACQk1IAoYAOsCAAkACAn9IQoYAOsCAA8AAgl+E68FAKYAAAAA.',
Ef='Effinsoldier:BAAALgAECgEJAQAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgADCgkJEQAAAA==.',
En='Endlessagony:BAABLgAECn8VAAIJAAgJQx0lIADBAgAJAAgJQx0lIADBAgAAAA==.Enyo:BAABLgAECn8XAAQQAAYJZxwFEQCJAQAQAAYJZxwFEQCJAQARAAEJAAA0JwBVAAAOAAIJeAZuXgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8UAAISAAgJ3A7FYQC/AQASAAgJ3A7FYQC/AQAAAA==.',
Fa='Falandril:BAAALgAECgcJBwAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8VAAMDAAgJGAoNUABnAQADAAgJFQoNUABnAQAEAAYJGQUoJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgMJAwABLgAECgYJCwATAAAAAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Gi='Gilforty:BAAALgAECgYJCwAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAECggJGgAUAIgZAA==.Gloriosa:BAABLgAECn8eAAIVAAgJTwvPDQAGAQAVAAgJTwvPDQAGAQAAAA==.',
Gv='Gvendalyn:BAAALgAECgYJEwAAAA==.',
Gw='Gweyn:BAAALgADCgEJAQAAAA==.',
Gy='Gyatsò:BAAALgAECgcJEQAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECgcJBwATAAAAAA==.Harshdk:BAAALgAECgcJBwAAAA==.',
He='Helel:BAABLgAECn8eAAIJAAYJzRaqFwBVAQAJAAYJzRaqFwBVAQAAAA==.',
Ho='Hops:BAAALgADCgEJAQAAAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECgYJCwATAAAAAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmöney:BAAALgAECgIJAwABLgAECgcJFgACAPkfAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAAALgAECgYJCwAAAA==.',
Je='Jellyfish:BAAALgAECggJCQAAAA==.Jessamyn:BAAALgAECgIJAgAAAA==.',
Jh='Jhoira:BAAALgAECgUJBgAAAA==.',
Jo='Jordyy:BAABLgAECn8XAAQQAAgJYSGaIQCQAgAQAAcJYSGaIQCQAgARAAIJ8yHCFwC+AAAOAAIJERM7VABxAAAAAA==.',
Ka='Kaifren:BAAALgAFFAIJAwAAAA==.Kalifa:BAACLgAFFH8KAAIFAAQJnxs+BAAlAQAFAAQJnxs+BAAlAQAuAAQKfysAAgUACAnwI8cAALwCAAUACAnwI8cAALwCAAAA.Kalinethe:BAAALgADCggJDgAAAA==.Karatay:BAAALgADCgEJAQAAAA==.Karrod:BAAALgAECgUJBgAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgADCggJEAAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8aAAIUAAgJiBkpDQCoAQAUAAgJiBkpDQCoAQAAAA==.',
Ko='Komayetu:BAAALgADCgMJBAAAAA==.',
Kr='Kraas:BAAALgADCgcJCQAAAA==.Krateis:BAAALgAECgYJDwAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgUJBQAAAA==.Lazyace:BAAALgAECgIJAwAAAA==.',
Le='Lebenspender:BAABLgAECn8VAAIHAAYJqiDiBAAbAgAHAAYJqiDiBAAbAgAAAA==.Lextalonis:BAAALgAECgEJAQAAAA==.',
Li='Linkstery:BAABLgAECn8WAAMQAAcJdRlLUwDNAQAQAAYJ5BhLUwDNAQAOAAMJ2RCwNADkAAAAAA==.',
Lo='Losvanknight:BAAALgAECgEJAgAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Mactacolover:BAAALgADCgIJAgAAAA==.Madbomber:BAAALgAECgYJDgAAAA==.Maeze:BAAALgAECgYJCwAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAABLgAECn8eAAMSAAgJ9xzLCwDWAQASAAcJjx3LCwDWAQAWAAgJIgpeOgCQAQAAAA==.Mawwowow:BAABLgAECn8WAAIUAAYJLRnNGQAyAQAUAAYJLRnNGQAyAQAAAA==.Maximillius:BAAALgAECgMJBAABLgAECgYJDAATAAAAAA==.',
Me='Meekah:BAABLgAECn8hAAIGAAgJHhiPAgA3AgAGAAgJHhiPAgA3AgAAAA==.Melbrosha:BAAALgAECgIJAgAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAXAAAgAA==.Meriks:BAAALgAECgQJCgABLgAECgUJDQATAAAAAA==.',
Mi='Mickspooky:BAACLgAFFH8IAAIJAAMJYhV0FQCxAAAJAAMJYhV0FQCxAAAuAAQKfxwAAgkACAmGH0YpAJUCAAkACAmGH0YpAJUCAAEuAAQKAwkDABMAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBQAAAA==.Milfy:BAAALgADCgQJBAAAAA==.Mintie:BAAALgAECgYJEgAAAA==.',
Mo='Moozylla:BAAALgADCgcJCQAAAA==.Morrïgan:BAAALgADCgEJAQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAAALgAECgYJEQAAAA==.Mynx:BAAALgAECgYJCgAAAA==.',
['Må']='Mårsh:BAAALgADCgQJBAAAAA==.',
Na='Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgQJBAAAAA==.',
Ne='Neona:BAAALgADCgkJEQAAAA==.Neriv:BAAALgAECgQJBAAAAA==.Nexaladin:BAAALgADCgIJAgAAAA==.',
Ni='Nimbus:BAAALgAECgMJBAABLgAFFAYJEAAKAAwVAA==.Nixii:BAAALgAECgYJEQAAAA==.',
No='Nocticula:BAABLgAECn8ZAAIYAAYJwwJaEwC5AAAYAAYJwwJaEwC5AAAAAA==.',
Ny='Nyet:BAACLgAFFH8HAAIDAAQJowcZDgAkAQADAAQJowcZDgAkAQAuAAQKfxoAAgMACAk7HWMcAGoCAAMACAk7HWMcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgIJAgAAAA==.',
Oh='Ohnarr:BAAALgADCgUJCQAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwAAAA==.',
Ol='Olaf:BAAALgAECgMJAwAAAA==.',
Or='Orine:BAAALgAECggJDAAAAA==.Orioz:BAACLgAFFH8GAAIIAAMJqBnBAgAaAQAIAAMJqBnBAgAaAQAuAAQKfx0AAggACAknIvEDAOgCAAgACAknIvEDAOgCAAAA.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgADCgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAQJBwAFAHQXAA==.Psychomurda:BAAALgAECgQJCgABLgAECggJIQAGAB4YAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.',
Sa='Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAAALgAECgUJBwAAAA==.',
Se='Seimie:BAAALgAECgYJCAAAAA==.Selithvia:BAAALgAECgQJBQAAAA==.Senethotsare:BAAALgADCgkJEQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgADCgkJEAATAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgADCgkJEQAAAA==.Shaofikx:BAABLgAECn8XAAIZAAYJcQhTEADuAAAZAAYJcQhTEADuAAAAAA==.Shenknarok:BAABLgAECn8hAAIaAAYJXhnpBABDAQAaAAYJXhnpBABDAQAAAA==.Sherryl:BAABLgAECn8VAAIXAAYJCQigHQDJAAAXAAYJCQigHQDJAAAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgEJAQAAAA==.Skyari:BAAALgAECgYJEwAAAA==.Skyarii:BAAALgAECgQJBQABLgAECgYJEwATAAAAAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8VAAIJAAQJnAF3AgFzAAAJAAQJnAF3AgFzAAAAAA==.',
Sp='Spiritshard:BAAALgADCgcJFAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAAALgAECgQJBQAAAA==.Sulfurya:BAAALgADCgkJEQAAAA==.',
Sy='Sykoman:BAACLgAFFH8HAAIFAAQJdBftCwArAQAFAAQJdBftCwArAQAuAAQKfx0AAgUACAnvIXkLAN8CAAUACAnvIXkLAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgUJBQAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Teverion:BAAALgADCgcJCwAAAA==.',
Th='Therkage:BAAALgADCgcJEAAAAA==.Thesios:BAAALgADCgEJAQAAAA==.Thizz:BAABLgAECn8ZAAIDAAYJPiD4KQASAgADAAYJPiD4KQASAgABLgAECgcJFgACAPkfAA==.',
Ti='Tinksy:BAAALgADCgEJAQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgADCggJCwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgADCgUJBQAAAA==.Toxious:BAAALgADCgcJDQAAAA==.',
Tp='Tpaman:BAAALgADCggJDgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgYJCgAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Va='Vacuus:BAAALgAECgcJCQAAAA==.Vahldire:BAAALgAECgIJAwAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varn:BAAALgADCggJCAAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJDgAAAA==.Velnyxia:BAAALgAECgEJAQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velzyra:BAAALgAECgYJCgAAAA==.Vestara:BAAALgAECgYJBgAAAA==.Veylara:BAABLgAECn8VAAIQAAYJ8AXrKgDgAAAQAAYJ8AXrKgDgAAAAAA==.',
Vi='Viryda:BAAALgADCggJFAAAAA==.',
Wa='Wartimebeast:BAAALgAECgUJCQAAAA==.',
We='Welp:BAAALgADCgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn8oAAMOAAgJVBJcCwALAgAOAAgJVBJcCwALAgARAAEJwwEzOAAaAAAAAA==.',
Wo='Womplock:BAAALgADCgkJEgAAAA==.',
Wr='Wrâth:BAABLgAECn8fAAIMAAgJYw6CdgDlAQAMAAgJYw6CdgDlAQAAAA==.',
Wy='Wydwen:BAAALgADCgQJBQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIZAAgJvBqAFQBeAgAZAAgJvBqAFQBeAgABLgAECggJGgAZALwaAA==.',
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
