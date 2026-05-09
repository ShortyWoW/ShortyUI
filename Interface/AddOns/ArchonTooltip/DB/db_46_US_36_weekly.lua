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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','Monk-Brewmaster','DeathKnight-Unholy','Mage-Frost','Evoker-Augmentation','DeathKnight-Frost','Evoker-Preservation','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Rogue-Outlaw','Druid-Guardian','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aalduin:BAAALgAECgEJAgABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCAAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgADCggJEQAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAQJCQACAFMZAQ==.',
Af='Affli:BAACLgAFFH8HAAIDAAMJ/hSyOwDmAAADAAMJ/hSyOwDmAAAuAAQKfygAAgMACAmuIEAbALECAAMACAmuIEAbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8eAAIFAAgJXhFkDQCNAQAFAAgJXhFkDQCNAQAAAA==.Aiupriesty:BAABLgAECn8YAAMGAAcJ2QfqJQAVAQAGAAcJ2QfqJQAVAQAHAAMJ/xFqYQCrAAABLgAECggJHgAFAF4RAA==.',
Ak='Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAAALgAECgEJAQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAAALgAECgQJBgAAAA==.Aleinara:BAAALgAECgQJCgAAAA==.Aleridin:BAABLgAECn8rAAIIAAkJHiV8AABjAwAIAAkJHiV8AABjAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAAALgAFFAIJAgAAAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Andsey:BAAALgAECgMJAwAAAA==.Annore:BAABLgAECn8aAAIJAAkJPBARKwDPAQAJAAkJPBARKwDPAQAAAA==.Antihero:BAABLgAECn8hAAIJAAkJeCN2DgAnAwAJAAkJeCN2DgAnAwAAAA==.',
Aq='Aquiell:BAABLgAECn8WAAIKAAYJ0BF3aQA+AQAKAAYJ0BF3aQA+AQAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8KAAIFAAQJChyBBgBEAQAFAAQJChyBBgBEAQAuAAQKfzIAAwUACAnxI1oCAMMCAAUACAnxI1oCAMMCAAQABQnNEOMyAP8AAAAA.Arkenomu:BAABLgAECn8bAAILAAgJLRGnFQCXAQALAAgJLRGnFQCXAQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8jAAMMAAgJCgi9BwAuAQAMAAgJCgi9BwAuAQAJAAYJsAHJ7AClAAAAAA==.Asclepius:BAABLgAECn8dAAINAAgJURCNCgCpAQANAAgJURCNCgCpAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Asmira:BAAALgADCgYJCAAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn8ZAAMOAAYJhh2ADQDxAQAOAAYJ9RyADQDxAQAPAAQJwRrpagAnAQAAAA==.',
At='Atsunvhi:BAAALgAECgQJBgAAAA==.',
Av='Avadakedevra:BAABLgAECn8ZAAMOAAYJJhXxFQBhAQAOAAYJJhXxFQBhAQAPAAEJKwpEzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azreal:BAAALgAECgYJBgAAAA==.Azumok:BAAALgADCgEJAQAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bakedbean:BAAALgAECgEJAgABLgAECgkJHAAQAFglAA==.Barackobooma:BAAALgADCgcJBwAAAA==.Bazerker:BAAALgADCgIJAgAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8WAAIKAAcJSAsLrACDAQAKAAcJSAsLrACDAQAAAA==.',
Be='Belgaria:BAABLgAECn8dAAMRAAYJ4BWsDwA/AQASAAYJNQ9hlQBSAQARAAYJqhWsDwA/AQAAAA==.Berryknight:BAABLgAECn8kAAMJAAgJfxqYKADbAQAJAAgJfxqYKADbAQAMAAIJ3g9oEABxAAAAAA==.Berryqt:BAAALgAECgQJCAAAAA==.Bewlzeye:BAAALgAECgIJAgAAAA==.',
Bi='Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8OAAIHAAQJLyUmAwCuAQAHAAQJLyUmAwCuAQAuAAQKfx0AAgcACAmWJIkDACIDAAcACAmWJIkDACIDAAAA.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodydk:BAAALgADCgMJAwAAAA==.Bluezugzug:BAAALgAECgIJAwAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8qAAITAAkJnBXpAwA3AgATAAkJnBXpAwA3AgAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgADCgcJBwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn8pAAMGAAgJkyLpAwC0AgAGAAgJkyLpAwC0AgAUAAEJaBbiVgA0AAAAAA==.Bonsaichi:BAAALgAECgEJAQAAAA==.Bownyxia:BAACLgAFFH8JAAILAAMJQBaKEQD1AAALAAMJQBaKEQD1AAAuAAQKfzYAAwsACQnGIqUBADQDAAsACQnGIqUBADQDABUABAlHDvIpAM4AAAEuAAUUBwkeAAkAFRwA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAcJHgAJABUcAA==.Bowties:BAACLgAFFH8eAAMJAAcJFRzSAgAkAgAJAAYJFRzSAgAkAgAWAAEJAAA8GQA4AAAuAAQKf0MAAwkACQmTJhYAAJ8DAAkACQmTJhYAAJ8DABYACQk3GHgKAHECAAAA.',
Br='Braxchud:BAABLgAECn8eAAIXAAcJRRJuIABLAQAXAAcJRRJuIABLAQAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAIKAAkJixsuDwCiAgAKAAkJixsuDwCiAgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8NAAIQAAQJPBL6IAAqAQAQAAQJPBL6IAAqAQAuAAQKfx0AAhAACQl3GzgHALQCABAACQl3GzgHALQCAAEuAAUUBwkeAAkAFRwA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgcJBwABLgAECgYJFQAEACMkAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgMJCgAAAA==.',
Ca='Caarrl:BAAALgAECgMJBQAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBAAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgADCgQJBQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgADCgUJBQAAAA==.Cayllia:BAABLgAECn8ZAAMYAAkJmyKPBABFAwAYAAgJ3iSPBABFAwAZAAgJDCL0GwAiAgAAAA==.',
Ce='Celaris:BAAALgAECgMJBQAAAA==.',
Ch='Chaolang:BAAALgAECgIJAgAAAA==.Chataykay:BAAALgAECgYJCQAAAA==.Cherrypepsï:BAABLgAECn8bAAMHAAkJkA7YKwCYAQAHAAkJkA7YKwCYAQAUAAUJdgbsOADgAAAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8VAAIaAAgJMxMmBACkAQAaAAgJMxMmBACkAQAAAA==.Citrus:BAABLgAECn8oAAIOAAgJyhWKCwDrAQAOAAgJyhWKCwDrAQAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBQAAAA==.Cliqmonk:BAAALgAECgcJBgAAAA==.',
Cn='Cn:BAABLgAECn8oAAISAAkJnyBDBQD7AgASAAkJnyBDBQD7AgAAAA==.',
Co='Cocoabutter:BAABLgAECn8YAAIKAAYJzA9cbwAyAQAKAAYJzA9cbwAyAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAAKAIsbAA==.Codeman:BAABLgAECn8qAAIWAAkJxSFWAQANAwAWAAkJxSFWAQANAwAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJKgAWAMUhAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8PAAMbAAUJfg1aCgAqAQAbAAUJfg1aCgAqAQAcAAQJhBUUEAAgAQAuAAQKf0kAAxwACQlMI0IBAH8DABwACQlMI0IBAH8DABsABAkmHLYmAPgAAAAA.Contemplate:BAAALgAECgMJBwAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAECggJGAABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.',
Cu='Culluh:BAAALgADCgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAAALgAECgYJEgAAAA==.',
Cz='Czin:BAABLgAECn8VAAMEAAYJIySCDgAHAgAEAAYJIySCDgAHAgAFAAEJkQm+SwAlAAAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgEJAgAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJBwAAAA==.Deathverses:BAACLgAFFH8gAAIdAAUJ2SZqAgDSAQAdAAUJ2SZqAgDSAQAuAAQKfy4AAh0ACQniJicCAJYDAB0ACQniJicCAJYDAAAA.Deerslayer:BAAALgAECgcJDQAAAA==.Deezknights:BAAALgAECgQJBQABLgAECgYJCgABAAAAAA==.Delter:BAABLgAECn8UAAIdAAgJuxx9HwAqAgAdAAgJuxx9HwAqAgABLgAECggJFAAdALscAA==.Deltritus:BAACLgAFFH8QAAIKAAUJ4Rm4HgBrAQAKAAUJ4Rm4HgBrAQAuAAQKfyIAAgoACQnyH6IHAPUCAAoACQnyH6IHAPUCAAEuAAQKCAkUAB0AuxwA.Demoan:BAABLgAECn8tAAIeAAkJBiNfAAAiAwAeAAkJBiNfAAAiAwAAAA==.Demonbiscuit:BAAALgAECgcJEQAAAA==.Derpydawg:BAAALgAECgEJAQABLgAFFAQJBQAJAHoaAA==.Deviancy:BAAALgAECggJDAABLgAECggJIgAcAPcfAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAAALgAECgYJDgAAAA==.Dikslapp:BAABLgAECn8eAAIfAAkJJyD0AQDpAgAfAAkJJyD0AQDpAgAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Ditto:BAACLgAFFH8FAAIWAAMJ5AsrFgCeAAAWAAMJ5AsrFgCeAAAuAAQKfy4ABBYACAlZHH4IAP4BABYACAlZHH4IAP4BAAwAAwlBDtwPAJ4AAAkAAQmLCizoADQAAAAA.',
Dl='Dlitinaro:BAABLgAECn8rAAMJAAkJJR9mCADWAgAJAAkJJR9mCADWAgAWAAMJwgT9PgBUAAAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMNAAMJoBd3DQAHAQANAAMJoBd3DQAHAQALAAEJHgnrOgBDAAAuAAQKfxkAAw0ACAlvJLcDACEDAA0ACAlvJLcDACEDAAsAAwlZGidOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Donoph:BAABLgAECn8qAAICAAkJ3CG6AgAjAwACAAkJ3CG6AgAjAwAAAA==.Doomar:BAABLgAECn8mAAIDAAkJMyFFBgDfAgADAAkJMyFFBgDfAgAAAA==.Doomsamdi:BAAALgAECgEJAQABLgAECgkJJgADADMhAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8bAAMDAAgJegg3UgA0AQADAAgJcAY3UgA0AQAgAAYJ0AfuMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgADCgcJFgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8eAAMVAAYJjAy5HwAwAQAVAAYJyAu5HwAwAQALAAUJgApqNgDHAAAAAA==.Drugar:BAAALgAECgUJDgAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEh8CFQDCAAAEAAIJEh8CFQDCAAAuAAQKfxYAAgQACAneHa8SALkCAAQACAneHa8SALkCAAEuAAUUCAkjABMAAx8A.',
Du='Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgQJBgAAAA==.',
Dy='Dynabol:BAABLgAECn8cAAMQAAkJWCXgAABnAwAQAAkJWCXgAABnAwAeAAMJViL2EgAiAQAAAA==.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAQJBQAJAHoaAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgADCgEJAQAAAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8uAAIEAAkJKRkNCABrAgAEAAkJKRkNCABrAgAAAA==.Faolsabre:BAABLgAECn8bAAIJAAYJ2A37XgAnAQAJAAYJ2A37XgAnAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgAOAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn8vAAIhAAkJgxAMBQAMAgAhAAkJgxAMBQAMAgAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8aAAIYAAgJsBVJJgCaAQAYAAgJsBVJJgCaAQAAAA==.',
Fo='Folid:BAAALgADCgcJCAAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgMJBgAAAA==.',
Fu='Furrywhaco:BAAALgAECggJCgAAAA==.Fuzzyspells:BAAALgAECgIJAgAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMSAAgJLxv1SwD/AQASAAYJsB71SwD/AQARAAYJ6hLMEQAjAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn8mAAMiAAgJ2QUmHgALAQAiAAgJxQUmHgALAQAjAAYJsAKREQDuAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBAAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQKAAgJsiQ0HwD4AgAKAAgJnSQ0HwD4AgAkAAEJnCZEFQBzAAAlAAEJiSQ/DABrAAABLgAECgkJHAAQAFglAA==.',
Gr='Grawler:BAAALgADCgkJJwAAAA==.Greeny:BAAALgAECgQJDAAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgEJAQABLgAECgcJAgABAAAAAA==.',
Gu='Gumgumfury:BAAALgAECgMJBwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJDQAYALcPAA==.Halzlok:BAAALgAECgUJEAAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAQJCgAFAAocAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJIwAYAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAECgcJEQABAAAAAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgEJAQAAAA==.',
Im='Imysteriöus:BAABLgAECn8jAAMYAAgJBiWCAgBbAwAYAAgJBiWCAgBbAwAhAAYJCRSHEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAABLgAFFH8JAAICAAQJsxFLEgAhAQACAAQJsxFLEgAhAQAAAA==.Indishaman:BAAALgAECgMJAwAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJKAASAJ8gAA==.',
Is='Ishamael:BAABLgAECn8mAAIGAAkJVBKKDQDxAQAGAAkJVBKKDQDxAQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8GAAIVAAQJfw1wAgAyAQAVAAQJfw1wAgAyAQAuAAQKfyoAAhUACQmyIXYAAAcDABUACQmyIXYAAAcDAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jaythirian:BAABLgAECn8YAAMmAAcJrQ6IEACUAQAmAAcJrQ6IEACUAQAEAAQJ1gQMgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8NAAIYAAQJtw8LGAAQAQAYAAQJtw8LGAAQAQAuAAQKfykAAxgACAk2HNcWAH8CABgACAk2HNcWAH8CABkABgn3FcIgADEBAAAA.Jessup:BAACLgAFFH8GAAMnAAMJNB7IBAC+AAAnAAIJPR/IBAC+AAAiAAIJMBloGgCkAAAuAAQKfyYAAyIACQn8IX4EAFADACIACQn8IX4EAFADACcAAgmwGoUMAJkAAAAA.',
Jh='Jhara:BAAALgAECgYJEwAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAABLgAECn8iAAQUAAkJIyJWBQCuAgAUAAkJIyJWBQCuAgAGAAQJbBpfNQBAAQAHAAEJfRSvewA6AAABLgAFFAIJAgABAAAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECgUJCAAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgQJBQAAAA==.Kamekazi:BAAALgADCgYJBgAAAA==.Kariva:BAABLgAECn8hAAIHAAkJBA6CEwC/AQAHAAkJBA6CEwC/AQAAAA==.Katacemic:BAAALgAECgUJCwAAAA==.Katastrophic:BAAALgADCggJEAAAAA==.Katazul:BAABLgAECn8fAAMgAAgJhQqqJgArAQADAAgJMgcxSwBHAQAgAAYJzgqqJgArAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.',
Ke='Keelanllan:BAAALgAECgYJEAAAAA==.Keilun:BAEALgAECgYJCQAAAA==.Kew:BAAALgAECgQJBQAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECggJHQANAFEQAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJGwALAC0RAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Ko='Koggmaw:BAAALgAECgUJCQABLgAFFAQJDQAYALcPAA==.Koral:BAAALgADCgkJEAAAAA==.Korengall:BAAALgADCgkJCQAAAA==.',
Kr='Kralj:BAAALgAECgQJBAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJKgAWAMUhAA==.Kungfuhealya:BAABLgAECn8eAAMcAAgJxwUsKQADAQAcAAgJxwUsKQADAQAbAAEJzQGDbwAcAAAAAA==.Kuraj:BAAALgADCgkJFwAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAASAPMbAA==.Larrydale:BAABLgAECn8ZAAMPAAgJTxwTGQByAgAPAAgJTxwTGQByAgAOAAEJqQMAMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAASAPMbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn8YAAMWAAYJtgcXIwCtAAAWAAYJ6gYXIwCtAAAJAAQJIAX5qACOAAAAAA==.',
Le='Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgIJAwAAAA==.Leondis:BAABLgAECn8pAAIPAAkJhh9TBgDMAgAPAAkJhh9TBgDMAgAAAA==.Lexipriest:BAACLgAFFH8UAAMHAAUJzBOGBACIAQAHAAUJYBOGBACIAQAUAAMJiQtcEADHAAAuAAQKfzYAAwcACQnCHvcCAAIDAAcACQlvHvcCAAIDABQACAkwHYQIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgYJEgABAAAAAA==.Lockmonster:BAAALgAECgEJAQAAAA==.Locksteady:BAAALgAECgUJBgAAAA==.Lorp:BAAALgAECgYJBwAAAA==.Lotglock:BAAALgAECgkJBAAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAIQAAgJRh1WHwDMAQAQAAgJRh1WHwDMAQAAAA==.Lumosmaxiima:BAAALgAECgcJBAAAAA==.Lunadesangre:BAAALgAECgEJAQAAAA==.Lunarette:BAAALgAECgIJAwAAAA==.',
Ly='Lydax:BAABLgAECn8UAAISAAcJ8xsWOgCYAQASAAcJ8xsWOgCYAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAAALgAECgUJBQAAAA==.Madkingzack:BAABLgAECn8VAAMEAAkJbx7/AgDlAgAEAAkJbx7/AgDlAgAmAAEJywZfQQAsAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAAALgAECgQJCgAAAA==.Mallikii:BAABLgAECn8bAAMYAAkJ0hu6MADoAQAYAAkJ0hu6MADoAQAZAAQJrSP3NwBZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8cAAIKAAkJyA01WgBgAQAKAAkJyA01WgBgAQAAAA==.Marigosa:BAAALgAECgcJCwAAAA==.Marnolkas:BAAALgADCggJCAABLgAECgMJAwABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAAALgAECggJEwAAAA==.Mattdemon:BAAALgAECgcJAgAAAA==.Maudib:BAABLgAECn8VAAIoAAgJSBWcDQAwAQAoAAgJSBWcDQAwAQAAAA==.Mawile:BAAALgAECgQJBAAAAA==.',
Me='Meautiful:BAAALgADCgQJBAAAAA==.Medusa:BAAALgAECgQJBgAAAA==.Meesha:BAAALgAECgIJAgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAAALgAECgQJBgAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQgAAgJBA97HABqAQAgAAcJYw57HABqAQADAAUJ/wrZxQDNAAAaAAEJ2hVlLgBBAAAAAA==.Merkxi:BAABLgAECn8gAAIOAAgJRCCnBAB3AgAOAAgJRCCnBAB3AgAAAA==.Messe:BAABLgAECn8rAAInAAgJ5hzvAQA0AgAnAAgJ5hzvAQA0AgAAAA==.Methious:BAAALgAECggJEwAAAA==.',
Mi='Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8PAAIIAAUJHQh6GgABAQAIAAUJHQh6GgABAQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECgUJCQAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonsguard:BAAALgADCgcJCgABLgAECgIJAgABAAAAAA==.Moovit:BAAALgAECgMJBQAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.',
My='Myströnghand:BAAALgAECgYJBgAAAA==.',
Na='Nagumo:BAABLgAECn8fAAMDAAgJbAP9aAD6AAADAAgJNwP9aAD6AAAgAAYJYAPwOQDMAAAAAA==.Nala:BAAALgAECggJEAABLgAFFAQJDQAYALcPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAABLgAECn8sAAMLAAgJGRhXGgBsAQALAAcJEhdXGgBsAQANAAcJYhJTDwBKAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8GAAIQAAMJEx8iJQAcAQAQAAMJEx8iJQAcAQAuAAQKfygAAxAACQmiJfMAANgDABAACQmiJfMAANgDAB4AAQmqFBEdAD0AAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgADCgkJCQAAAA==.Nivan:BAAALgAECgEJAQAAAA==.Niço:BAAALgAFFAEJAgAAAA==.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIYAAkJJRs3HgBNAgAYAAkJJRs3HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAECggJGAAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
['Nï']='Nï:BAAALgADCgUJBQAAAA==.',
Oa='Oakmoss:BAAALgADCgcJBgAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECgcJCAAAAA==.',
Ol='Ollamh:BAAALgADCgEJAQAAAA==.',
Om='Ombravuota:BAAALgAECgcJEQAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMgAAkJwSMoCwANAgAgAAUJrCMoCwANAgADAAUJhCMDRQD8AQAAAA==.Orcleave:BAAALgAFFAEJAQAAAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Paboo:BAAALgAECgMJAwAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8aAAIKAAgJlhipNADOAQAKAAgJlhipNADOAQAAAA==.Perturabo:BAAALgAECgEJAQAAAA==.',
Ph='Phoenyx:BAAALgAECgYJEQAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMPAAcJDh20JAAqAgAPAAcJDh20JAAqAgAdAAMJdQt9awCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJHAAKAMgNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgADCgYJCgAAAA==.',
Qu='Quorra:BAAALgADCgcJCwAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8qAAIEAAkJcB7/AwDEAgAEAAkJcB7/AwDEAgAAAA==.Rakagar:BAABLgAECn8pAAISAAgJGx9lFQBOAgASAAgJGx9lFQBOAgAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8SAAIcAAUJ+xicBwCsAQAcAAUJ+xicBwCsAQAuAAQKfysAAhwACQkaHVkOAHECABwACQkaHVkOAHECAAAA.Reyz:BAABLgAECn8ZAAIcAAgJHBWAIQCnAQAcAAgJHBWAIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQAAAA==.',
Rh='Rhaegos:BAAALgAECgMJAwAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8VAAIEAAYJTR3AOwC2AQAEAAYJTR3AOwC2AQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAECggJFAAPALshAA==.',
['Rë']='Rëz:BAAALgADCgYJBgAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8oAAMfAAkJ3R8VAwC0AgAfAAkJ3R8VAwC0AgAQAAYJTBmRMAB0AQABLgAECgkJKwAJACUfAA==.Scripts:BAAALgAECgYJEQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJHAAKAMgNAA==.',
Sh='Shale:BAABLgAECn82AAMNAAkJjhnSAwCEAgANAAkJjhnSAwCEAgALAAYJ9giiRQDGAAAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAAALgAFFAEJAQAAAA==.Sharaiya:BAABLgAECn8bAAIYAAYJTwXSgQDVAAAYAAYJTwXSgQDVAAAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAAALgAECgUJDwABLgAECggJIQAEAFAYAA==.Sioux:BAAALgAECgMJAwAAAA==.',
Sk='Skippybmm:BAAALgAECgQJBwABLgAECgYJEgABAAAAAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgEJAQABLgAECggJKwAnAOYcAA==.',
Sm='Smexyshâmmy:BAAALgAECgQJBQAAAA==.',
So='Solaire:BAACLgAFFH8GAAIRAAMJmhTZBADPAAARAAMJmhTZBADPAAAuAAQKfywAAhEACQn8ILgBADMDABEACQn8ILgBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJth48BQDzAgADAAkJth48BQDzAgABLgAFFAUJFAAQANAfAA==.Soulful:BAAALgAECgYJBgAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAYALcPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAAALgAECgYJEgAAAA==.Spot:BAAALgAECgUJBgABLgAECgkJHAAKAMgNAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgEJAQAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn8hAAMOAAgJHhlPBwA3AgAOAAgJ+RhPBwA3AgAdAAcJKBXuCwAtAQAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECgIJAwABAAAAAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8UAAIgAAYJHhclCABbAQAgAAYJHhclCABbAQAAAA==.Tankinit:BAAALgAECgMJCgAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgADCgcJFAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIRAAMJswgFBACcAAARAAMJswgFBACcAAAuAAQKfyUAAhEACAkJHXwGAIACABEACAkJHXwGAIACAAAA.Tenzink:BAABLgAECn8mAAIcAAkJGxwpBQDBAgAcAAkJGxwpBQDBAgAAAA==.',
Th='Thalon:BAAALgAECgMJAwABLgAECggJLwAJAK0iAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgADCgIJAgAAAA==.Thedkfreak:BAAALgAECgYJBgABLgAECgcJFAASAAceAA==.Thedru:BAABLgAECn8pAAIYAAgJ9wvvNQBAAQAYAAgJ9wvvNQBAAQAAAA==.Thrus:BAAALgAECgQJBAABLgAECggJKwAnAOYcAA==.Théworld:BAAALgAECgIJAgAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgEJAQABLgAECggJGgAKAJYYAA==.',
Tl='Tlnks:BAAALgADCgQJBAAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAAALgAECgcJCgAAAA==.',
Tr='Traler:BAAALgAECgEJAQABLgAECgkJLwAhAIMQAA==.Tralzitashan:BAABLgAECn8nAAMkAAkJagxbAgDLAQAkAAkJagxbAgDLAQAKAAQJzAMHIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAIKAAcJWhquZQAMAgAKAAcJWhquZQAMAgAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgADCgMJAwAAAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgADCgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAAALgAECgUJCQAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAAALgAFFAMJBAAAAA==.Unglausp:BAABLgAECn8dAAIGAAgJ/R7ODQCmAgAGAAgJ/R7ODQCmAgABLgAFFAMJBAABAAAAAA==.',
Uz='Uzington:BAACLgAFFH8QAAIFAAQJ5g+YCgAHAQAFAAQJ5g+YCgAHAQAuAAQKfyYAAgUACQm0HPAIAI8CAAUACQm0HPAIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgEJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAAALgAECgUJCQAAAA==.Valorien:BAABLgAECn8ZAAISAAgJFBmhIgD7AQASAAgJFBmhIgD7AQAAAA==.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgAOAC0jAA==.Velinieron:BAABLgAECn8eAAIOAAkJLSPHAgC5AgAOAAkJLSPHAgC5AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgAOAC0jAA==.Vellash:BAAALgAECgYJEwAAAA==.Vendétta:BAABLgAECn8iAAIPAAgJGxDVOgBhAQAPAAgJGxDVOgBhAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8WAAIKAAcJ0Qi/bQA1AQAKAAcJ0Qi/bQA1AQAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgIJAgABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgADCggJCAAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8UAAIPAAUJygwIYwDnAAAPAAUJygwIYwDnAAAAAA==.',
Vy='Vynlandis:BAABLgAECn8oAAIJAAgJRxmpHQAWAgAJAAgJRxmpHQAWAgAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAYALcPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAAALgAECgYJBQAAAA==.Werebray:BAAALgAECgYJCgABLgAFFAIJAgABAAAAAA==.',
Wh='Whaco:BAABLgAECn8fAAIRAAgJiRvMBQARAgARAAgJiRvMBQARAgAAAA==.Whatisaggro:BAABLgAECn8YAAIEAAYJbR51GQCbAQAEAAYJbR51GQCbAQAAAA==.Whispertree:BAABLgAECn8ZAAIZAAgJdSDRGABBAgAZAAgJdSDRGABBAgAAAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECgYJHgAVAIwMAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8FAAIJAAQJehqqOwAeAQAJAAQJehqqOwAeAQAuAAQKfyMAAgkACQkXIV8NAC8DAAkACQkXIV8NAC8DAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8nAAQWAAcJNxnoFADDAQAWAAYJmh3oFADDAQAJAAcJsQbTgwDZAAAMAAIJcxhKEgBsAAAAAA==.Wixypoo:BAABLgAECn8iAAMIAAgJlhcvFACcAQAIAAgJlhcvFACcAQAcAAEJ5wGDYwAfAAAAAA==.',
Wo='Wockyslush:BAABLgAECn8fAAIiAAkJLiTmCAADAwAiAAkJLiTmCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMLAAkJWRgXCABSAgALAAkJWRgXCABSAgAVAAYJwAMlKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8WAAIpAAYJ1R/2HwAfAgApAAYJ1R/2HwAfAgAAAA==.',
Wy='Wyyn:BAABLgAECn8nAAIKAAcJ8QsuYABSAQAKAAcJ8QsuYABSAQAAAA==.',
Xa='Xanboi:BAABLgAECn8qAAMOAAkJ7CHzAAAlAwAOAAkJ7CHzAAAlAwAPAAIJ6iK0iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8GAAIEAAQJ+xknCQBYAQAEAAQJ+xknCQBYAQAuAAQKfyUAAgQACAmwIBQNAO0CAAQACAmwIBQNAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Ys='Ysar:BAAALgAECgcJDwAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMVAAcJ6RqFDgDyAQAVAAYJkB+FDgDyAQALAAYJGxdBIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECgYJHQARAOAVAA==.',
Ze='Zeebu:BAABLgAECn8VAAIOAAYJiAlJHAAiAQAOAAYJiAlJHAAiAQAAAA==.Zenboi:BAABLgAECn8cAAIQAAgJ3hUWQwDnAQAQAAgJ3hUWQwDnAQAAAA==.Zephryyn:BAAALgAECgYJBgAAAA==.',
Zh='Zhilan:BAAALgAECgQJBQAAAA==.',
Zi='Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAMJBgAnADQeAA==.Zophos:BAAALgAECggJCAAAAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgEJAgAAAA==.Zuzuk:BAAALgAECggJDwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAAALgAECgcJBwAAAA==.',
['Zú']='Zúz:BAAALgAECgcJCAAAAA==.',
['Áß']='Áßomination:BAAALgAECgIJAwAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAABLgAECn8hAAIpAAgJXgtDQgD6AAApAAgJXgtDQgD6AAAAAA==.',
['Ði']='Ðittø:BAAALgAECgYJAgABLgAFFAMJBQAWAOQLAA==.',
['Ðÿ']='Ðÿlån:BAAALgAECgEJAQAAAA==.',
['Öd']='Ödorodun:BAAALgAECgEJAgAAAA==.',
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
