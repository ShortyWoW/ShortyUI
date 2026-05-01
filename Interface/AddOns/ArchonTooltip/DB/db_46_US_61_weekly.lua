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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Druid-Balance','Priest-Discipline','Shaman-Restoration','Warrior-Protection','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Warlock-Destruction','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Druid-Restoration','DeathKnight-Blood','Druid-Guardian','Priest-Holy','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abaddonmoon:BAABLgAECn8XAAIBAAYJOwdiCADdAAABAAYJOwdiCADdAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgEJAQAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ5DwDMAAACAAMJdgJ5DwDMAAAuAAQKfxUAAwIACAlAEVA9ALkBAAIACAlAEVA9ALkBAAMABAm8AoImAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8TAAMEAAYJbRV5BQCbAQAEAAUJBhh5BQCbAQAFAAMJtwsVCwCnAAAuAAQKfyAAAwQACQkUH8wVAJ8CAAQACAkpH8wVAJ8CAAUABAnMF0YMAD4BAAAA.',
Ak='Akalifato:BAAALgAECgYJDAABLgAFFAUJDwAGAGAcAA==.Akroma:BAAALgAECgIJAwAAAA==.',
Al='Alariya:BAAALgAECgEJAQAAAA==.Alistin:BAAALgAECgEJAQAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgADCgcJCAAAAA==.Archanfel:BAABLgAECn8aAAIDAAYJTwzYFAAiAQADAAYJTwzYFAAiAQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgADCgcJDgAAAA==.',
Ay='Ayonna:BAAALgAECgQJCAAAAA==.',
Az='Azar:BAAALgADCgUJBQAAAA==.',
Ba='Bandie:BAAALgAECgMJAwAAAA==.Barrakum:BAAALgAECgUJBgAAAA==.Bayn:BAAALgADCgQJCAAAAA==.',
Be='Beeftruck:BAABLgAECn8bAAMFAAcJwxuiBADwAQAFAAcJ5xqiBADwAQAEAAUJ5hmKSgB7AQAAAA==.Belletrixx:BAAALgAECgYJDgAAAA==.Berried:BAABLgAECn8lAAIHAAgJaRy+AwCiAgAHAAgJaRy+AwCiAgAAAA==.',
Bi='Biigmâc:BAAALgAECgcJEAAAAA==.Biminem:BAAALgAECgYJEwAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAAALgAECgUJDAAAAA==.',
Bo='Bodak:BAABLgAECn8bAAIIAAYJ5BnMNwCjAQAIAAYJ5BnMNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Broris:BAAALgAECgMJAwAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAABLgAECn8UAAIJAAgJjBB+CwBuAQAJAAgJjBB+CwBuAQAAAA==.Caliste:BAAALgADCgIJAgABLgAFFAQJCgAKAAkbAA==.Calityy:BAAALgADCgYJBgABLgAFFAYJCwADAGkZAA==.Camine:BAABLgAECn8dAAILAAcJnhriJgCjAQALAAcJnhriJgCjAQAAAA==.Carise:BAAALgADCgMJAwAAAA==.Castalasaras:BAAALgAECgIJAgAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAAALgAECgYJBgAAAA==.',
Co='Constäntine:BAAALgAECgQJBAAAAA==.Coriolis:BAABLgAECn8eAAMMAAYJvhkhEwBsAQAMAAYJvhkhEwBsAQANAAMJggrrMACPAAAAAA==.',
Cr='Crowléy:BAAALgAECgMJAwAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8WAAIOAAcJwQ78qgCFAQAOAAcJwQ78qgCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgQJBAAAAA==.Daliann:BAAALgAECgUJCAAAAA==.Dangerduck:BAAALgAECgQJBwAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAAALgAECgUJCgAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8eAAMJAAYJ7SbaAwBCAgAJAAYJ7SbaAwBCAgAEAAEJCSNonQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgADCgQJBAABLgAECggJKAAPAFQSAA==.',
Di='Diamondshard:BAAALgAECgEJAQAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDQAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECggJJQADADofAA==.Drosof:BAAALgADCgQJBQAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAABLgAECn8XAAIQAAYJbw3LEwAOAQAQAAYJbw3LEwAOAQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8PAAILAAUJCyK8CACVAQALAAUJCyK8CACVAQAuAAQKfyMAAwsACQk1IA0YAOsCAAsACAn9IQ0YAOsCAAEAAwnvGAIHAAoBAAAA.',
Ef='Effinsoldier:BAAALgAECgQJBQAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgAECgQJBAAAAA==.',
En='Endlessagony:BAABLgAECn8bAAILAAkJBx4qIADBAgALAAkJBx4qIADBAgAAAA==.Enyo:BAABLgAECn8XAAQRAAYJZxz/KACKAQARAAYJZxz/KACKAQASAAEJAAA1JwBVAAAPAAIJeAZ2XgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAITAAkJqBE6PQBSAQATAAkJqBE6PQBSAQAAAA==.',
Fa='Falandril:BAAALgAECggJCgAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8ZAAMEAAgJPQsSUABnAQAEAAgJPQsSUABnAQAFAAcJwgQsJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgQJBAABLgAECgYJEQAUAAAAAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgEJAQAAAA==.Foughum:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgQJBAAAAA==.',
Gi='Gilforty:BAAALgAECgcJEgAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAECggJIwAVAIkeAA==.Gloriosa:BAABLgAECn8nAAIWAAgJUA7GEgCDAQAWAAgJUA7GEgCDAQAAAA==.',
Gv='Gvendalyn:BAABLgAECn8UAAICAAYJZSVWEAATAgACAAYJZSVWEAATAgAAAA==.',
Gw='Gweyn:BAAALgADCgEJAQAAAA==.',
Gy='Gyatsò:BAABLgAECn8YAAIXAAcJ0xiTDACuAQAXAAcJ0xiTDACuAQAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECggJDwAUAAAAAA==.Harshdk:BAAALgAECggJDwAAAA==.',
He='Helel:BAABLgAECn8kAAILAAYJahf/OwBLAQALAAYJahf/OwBLAQAAAA==.',
Ho='Hops:BAAALgADCgEJAQAAAA==.',
Il='Illibanger:BAAALgADCgQJBAABLgAECgcJGwAFAMMbAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECgYJEQAUAAAAAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmöney:BAAALgAECgIJAwABLgAECgYJGwAEAD4gAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAAALgAECgcJEgAAAA==.Jardalanin:BAAALgADCgEJAQAAAA==.',
Je='Jellyfish:BAAALgAECggJEwAAAA==.Jessamyn:BAAALgAECgIJAgAAAA==.',
Jh='Jhoira:BAAALgAECgYJCQAAAA==.',
Jo='Jokko:BAAALgADCgEJAQAAAA==.Jordyy:BAABLgAECn8YAAQRAAgJYSGbIQCQAgARAAcJYSGbIQCQAgASAAIJ8yHAFwC+AAAPAAIJERNEVABxAAAAAA==.',
Ka='Kaifren:BAABLgAECn8UAAIOAAgJEQsq1ABGAQAOAAgJEQsq1ABGAQAAAA==.Kalifa:BAACLgAFFH8PAAIGAAUJYBxTCgBFAQAGAAUJYBxTCgBFAQAuAAQKfy4AAgYACAnwI1ACAMwCAAYACAnwI1ACAMwCAAAA.Kalinethe:BAAALgADCggJDgAAAA==.Karatay:BAAALgADCgEJAQAAAA==.Karrod:BAAALgAECgUJBgAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBAAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8jAAIVAAgJiR6FBgByAgAVAAgJiR6FBgByAgAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECggJIwAVAIkeAA==.',
Ko='Komayetu:BAAALgADCgYJCgAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAAALgAECgYJEwAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgcJDAAAAA==.Lazyace:BAAALgAECgIJBAAAAA==.',
Le='Lebenspender:BAABLgAECn8cAAIIAAYJryCIDAAiAgAIAAYJryCIDAAiAgAAAA==.Lextalonis:BAAALgAECgYJCAAAAA==.',
Li='Linkstery:BAABLgAECn8dAAMRAAcJfxpNUwDNAQARAAYJ5BhNUwDNAQAPAAMJ9xOwNADkAAAAAA==.',
Lo='Losvanknight:BAAALgAECgcJCAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgADCgcJBwAAAA==.Mactacolover:BAAALgADCgIJAgAAAA==.Madbomber:BAAALgAECgYJDgAAAA==.Maeze:BAAALgAECgYJEQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAABLgAECn8eAAMTAAgJ9xz9HgDQAQATAAcJjx39HgDQAQAYAAgJIgpeOgCQAQAAAA==.Mawwowow:BAABLgAECn8WAAIVAAYJVBsRIQBsAQAVAAYJVBsRIQBsAQAAAA==.Maximillius:BAAALgAECgQJBQAAAA==.Mayjoraid:BAAALgAECgEJAQAAAA==.',
Me='Meekah:BAABLgAECn8pAAIHAAgJJhkZBgBOAgAHAAgJJhkZBgBOAgAAAA==.Melbrosha:BAAALgAECgMJBgAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAZAAAgAA==.Meriks:BAAALgAECgQJCwABLgAECgUJDQAUAAAAAA==.',
Mi='Mickspooky:BAACLgAFFH8NAAILAAQJOxQFNwDxAAALAAQJOxQFNwDxAAAuAAQKfyMAAwsACAmGH00pAJUCAAsACAmGH00pAJUCABoAAwmLE44ZALAAAAEuAAQKAwkDABQAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBgAAAA==.Milfy:BAAALgADCgQJBAAAAA==.Mintie:BAABLgAECn8YAAIbAAYJvRFbDAD1AAAbAAYJvRFbDAD1AAAAAA==.',
Mo='Moozylla:BAAALgAECgYJBgAAAA==.Morrïgan:BAAALgADCgEJAQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAAALgAECgYJEwAAAA==.Mynx:BAAALgAECgcJCwAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
Na='Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgUJBQAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAAALgAECgYJCwAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nimbus:BAAALgAECgMJBAABLgAFFAYJEQAMAKEXAA==.Nixii:BAABLgAECn8XAAIGAAYJxgs1IAD7AAAGAAYJxgs1IAD7AAAAAA==.',
No='Nocticula:BAABLgAECn8jAAIcAAgJ8glpFQBkAQAcAAgJ8glpFQBkAQAAAA==.',
Ny='Nyet:BAACLgAFFH8LAAMEAAUJzQkcDgAkAQAEAAUJzQkcDgAkAQAFAAEJYQZaEgBMAAAuAAQKfxwAAgQACQm9G18cAGoCAAQACQm9G18cAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgIJAgAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwAAAA==.',
Or='Orine:BAAALgAECggJDAAAAA==.Orioz:BAACLgAFFH8KAAIKAAQJCRt9AgDzAAAKAAQJCRt9AgDzAAAuAAQKfyQAAgoACAk0IvEDAOgCAAoACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECgQJBAABLgAECgYJCAAUAAAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgADCgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJCwAGAMwbAA==.Psychomurda:BAAALgAECgYJEQABLgAECggJKQAHACYZAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Ratpack:BAAALgAECgcJAQABLgAECgcJBwAUAAAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.',
Sa='Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAAALgAECgUJCwAAAA==.',
Se='Seimie:BAAALgAECgYJDgAAAA==.Selithvia:BAAALgAECgYJDAAAAA==.Senethotsare:BAAALgAECgQJBAAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgAECgQJBAAUAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgADCgkJEQAAAA==.Shaofikx:BAABLgAECn8fAAIdAAgJ0AiUFgBMAQAdAAgJ0AiUFgBMAQAAAA==.Shenknarok:BAABLgAECn8iAAIeAAYJXhnqBwB3AQAeAAYJXhnqBwB3AQAAAA==.Sherryl:BAABLgAECn8bAAIZAAYJ+AxEMgARAQAZAAYJ+AxEMgARAQAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgEJAQAAAA==.Skyari:BAABLgAECn8ZAAIEAAYJ8yR5CAAjAgAEAAYJ8yR5CAAjAgAAAA==.Skyarii:BAAALgAECgQJBwABLgAECgYJGQAEAPMkAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8YAAILAAYJ1wGRAgFzAAALAAYJ1wGRAgFzAAAAAA==.',
Sp='Spiritshard:BAAALgADCgcJEgAAAA==.Splashmountn:BAEALgAECgQJBAABLgAECgYJDwAUAAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAAALgAECgUJCAAAAA==.Sulfurya:BAAALgAECgQJBAAAAA==.',
Sy='Sykoman:BAACLgAFFH8LAAIGAAUJzBtMBQBwAQAGAAUJzBtMBQBwAQAuAAQKfx0AAgYACAnvIXoLAN8CAAYACAnvIXoLAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgYJCAAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Teverion:BAAALgADCgcJCwAAAA==.',
Th='Therkage:BAAALgADCgcJEAAAAA==.Thesios:BAAALgADCgcJBwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thizz:BAABLgAECn8bAAIEAAYJPiD9KQASAgAEAAYJPiD9KQASAgAAAA==.',
Ti='Tinksy:BAAALgADCgEJAQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgADCggJCwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgUJBQAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgYJCgAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Va='Vacuus:BAAALgAECgcJDgAAAA==.Vahldire:BAAALgAECgMJBQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgADCgMJAwAAAA==.Varn:BAAALgADCggJCAAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJDgAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8bAAIRAAYJOQaWXwDUAAARAAYJOQaWXwDUAAAAAA==.',
Vi='Viryda:BAAALgADCggJFgAAAA==.',
Wa='Wartimebeast:BAAALgAECgUJDQAAAA==.',
We='Welp:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn8oAAMPAAgJVBJgCwALAgAPAAgJVBJgCwALAgASAAEJwwEzOAAaAAAAAA==.',
Wo='Womplock:BAAALgADCgkJFgAAAA==.',
Wr='Wrâth:BAABLgAECn8gAAIOAAgJYw54dgDlAQAOAAgJYw54dgDlAQAAAA==.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIdAAgJvBqCFQBeAgAdAAgJvBqCFQBeAgABLgAECggJGgAdALwaAA==.',
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
