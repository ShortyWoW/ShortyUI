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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Mage-Frost','DemonHunter-Devourer','Warrior-Protection','Paladin-Holy','Druid-Balance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Vengeance','Monk-Brewmaster','Paladin-Protection','Priest-Holy','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Warlock-Affliction','Monk-Mistweaver','Evoker-Preservation','Warrior-Arms','Shaman-Enhancement','DeathKnight-Blood','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aanaleaa:BAAALgAECgUJCgAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAAALgAECgYJCgABLgAECgcJEAABAAAAAA==.Adellon:BAAALgAFFAEJAQAAAA==.Adhar:BAAALgADCgMJAQAAAA==.Adrielle:BAABLgAECn8ZAAICAAYJyxlHQgBDAQACAAYJyxlHQgBDAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAAALgAECgcJEgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAYJFQADAI8eAA==.',
Ai='Airphobic:BAAALgAECgIJBwAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECgYJEgABAAAAAA==.Akakaji:BAAALgAECgYJEgAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIEAAgJMxxvFACSAgAEAAgJMxxvFACSAgAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgYJDgAAAA==.Anomander:BAAALgAECgYJEgAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAAALgAECgcJEAAAAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAAALgAECgcJEAAAAA==.Argig:BAAALgADCgcJCAAAAA==.Arienca:BAABLgAECn8qAAMFAAkJqgtIFgCYAQAFAAgJ5gpIFgCYAQAGAAkJBAhJJwCSAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Asu:BAAALgAECgYJCwAAAA==.',
At='At:BAABLgAECn8WAAIHAAYJyhULqACJAQAHAAYJyhULqACJAQABLgAECgcJEAABAAAAAA==.',
Au='Aubrey:BAACLgAFFH8GAAIEAAQJUQeQGwDAAAAEAAQJUQeQGwDAAAAuAAQKfxQAAgQACQlzCqJSAFwBAAQACQlzCqJSAFwBAAAA.',
Av='Avengion:BAAALgAECgUJCQAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgQJBAABLgAFFAUJCQAEAI8OAA==.Beldent:BAAALgAECgQJBQAAAA==.',
Bl='Blazeofglory:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Blazerunner:BAABLgAECn8XAAIHAAcJmw6sSwBMAQAHAAcJmw6sSwBMAQAAAA==.Blazesmasher:BAAALgADCgkJDQABLgAECgcJFwAHAJsOAA==.Blitzkreig:BAAALgAECgUJCgAAAA==.Bluefoot:BAAALgAECgMJAwAAAA==.Blured:BAABLgAECn8kAAIIAAkJ2iJuAQAdAwAIAAkJ2iJuAQAdAwAAAA==.',
Bo='Booty:BAABLgAECn8oAAIJAAkJpSLTAAD4AgAJAAkJpSLTAAD4AgAAAA==.',
Br='Brightblayde:BAAALgAECgYJDQAAAA==.Brynhildre:BAABLgAECn8UAAIKAAcJfgtORABmAQAKAAcJfgtORABmAQABLgAFFAQJBgAEAFEHAA==.',
Bu='Buum:BAAALgAECgUJCgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
Ca='Cachelyn:BAAALgADCgcJBwAAAA==.Cali:BAACLgAFFH8UAAIIAAUJqh4vCgBlAQAIAAUJqh4vCgBlAQAuAAQKfyMAAggACAmkIecSAOgCAAgACAmkIecSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIHAAgJYh7ZDwBeAgAHAAgJYh7ZDwBeAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCQABAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCQABAAAAAA==.Cephus:BAAALgAFFAQJBAAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Choom:BAABLgAECn8fAAMEAAkJuhUNNgDQAQAEAAkJuhUNNgDQAQALAAYJjRPfLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Chronocide:BAABLgAECn8jAAIMAAgJ7R8NEACpAgAMAAgJ7R8NEACpAgAAAA==.Chronophasia:BAAALgADCgkJDwAAAA==.Chroños:BAAALgADCgEJAQAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8LAAIIAAUJ+huLFAAmAQAIAAUJ+huLFAAmAQAuAAQKfxoAAggACAkiIo8QAPoCAAgACAkiIo8QAPoCAAAA.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgQJBQAAAA==.',
Co='Connerr:BAABLgAECn8YAAIEAAgJwRqfEgD1AQAEAAgJwRqfEgD1AQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgADCgUJBQAAAA==.Croh:BAABLgAECn8aAAMNAAgJpBNgVAD0AQANAAgJpBNgVAD0AQAOAAQJawb0DwCcAAAAAA==.',
Cy='Cynestra:BAAALgAECgUJBgAAAA==.',
Da='Dadudadu:BAACLgAFFH8NAAICAAUJfA2TDgA1AQACAAUJfA2TDgA1AQAuAAQKfy8AAgIACQmnHHoWAOICAAIACQmnHHoWAOICAAAA.Daffo:BAAALgAECgEJAQAAAA==.Daftmonk:BAACLgAFFH8QAAIPAAUJOiRsAQCdAQAPAAUJOiRsAQCdAQAuAAQKfyoAAg8ACAnJJLICAG8DAA8ACAnJJLICAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAECgkJLQAQAA8dAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgEJAQAAAA==.Darkwingfish:BAABLgAECn8iAAIIAAkJCRQiJABcAQAIAAkJCRQiJABcAQAAAA==.Dartran:BAAALgADCgIJBQAAAA==.Dasarus:BAAALgAECgQJBAAAAA==.Dayman:BAAALgAECgYJBgAAAA==.',
De='Deadweight:BAAALgAECgYJBgAAAA==.Decày:BAAALgAECgcJDwAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Dethblow:BAAALgAECgIJBQAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAABLgAECn8ZAAMRAAkJ/AYkKgAiAQARAAkJ/AYkKgAiAQAMAAYJSQfTUQD/AAAAAA==.',
Dk='Dklot:BAAALgAFFAEJAQAAAA==.',
Dr='Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8iAAISAAgJ1BRPLgBYAQASAAgJ1BRPLgBYAQAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBAAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAICAAkJ8RthFgDjAgACAAkJ8RthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMIAAkJ1yaLAwCTAwAIAAkJ1yaLAwCTAwATAAQJfhoVBwBPAQAAAA==.',
En='Enkeke:BAABLgAECn8qAAINAAkJBxvtDABfAgANAAkJBxvtDABfAgAAAA==.',
Er='Eresanna:BAAALgAECgEJAwAAAA==.',
Es='Esdeath:BAAALgAECgQJBAABLgAFFAIJAgABAAAAAA==.Estus:BAAALgAECgYJCwAAAA==.',
Ex='Extremefear:BAABLgAECn8UAAMFAAYJ9hYWLgADAQAFAAQJNBcWLgADAQAGAAMJYBWpawC2AAAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8JAAIGAAQJsCS0BAC2AQAGAAQJsCS0BAC2AQAuAAQKfxwAAwYACAnPJc4rAF8CAAYABwn9I84rAF8CAAUAAgkmJFY3ANgAAAAA.Fenrisfangs:BAAALgAECgYJDAAAAA==.Fenrisul:BAAALgADCgIJAgAAAA==.Feralshunter:BAABLgAECn8tAAIQAAkJDx1qEAC2AgAQAAkJDx1qEAC2AgAAAA==.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Forfoxsake:BAABLgAECn8iAAIUAAgJjx8OBQBcAgAUAAgJjx8OBQBcAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8JAAIEAAUJjw7aEAAYAQAEAAUJjw7aEAAYAQAAAA==.',
['Fû']='Fûrrow:BAAALgAECgEJAgAAAA==.',
Ga='Gallindral:BAABLgAECn8vAAIIAAkJVh0lAwDIAgAIAAkJVh0lAwDIAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gatito:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.Gauthus:BAAALgAECgYJBgAAAA==.',
Ge='Genericnpc:BAAALgAECgUJBwAAAA==.Geobrando:BAABLgAECn8qAAMRAAkJ3h5tCwDHAgARAAkJ3h5tCwDHAgAMAAMJmxF3ZgCpAAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8LAAICAAQJOhwACQBtAQACAAQJOhwACQBtAQAuAAQKf0EABAIACQmvI3ICAAoDAAIACQmvI3ICAAoDAAoABwk3GEQMABMCABUAAglQALcuABUAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJCQABLgAECgcJFwAHAJsOAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgADCgcJDQAAAA==.',
Gn='Gnosh:BAAALgAECgUJCQAAAA==.Gnova:BAABLgAECn8YAAIHAAYJjR5XawD/AQAHAAYJjR5XawD/AQAAAA==.',
Go='Gorian:BAAALgAECgcJAgAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgADCgcJEgAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIRAAgJhhdiHAA2AgARAAgJhhdiHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAUJFAAIAKoeAA==.Harle:BAAALgAECgUJCgAAAA==.Hatari:BAAALgADCgYJCgAAAA==.',
He='Hektate:BAAALgAECgcJEAABLgAFFAUJDQACAHwNAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAAALgAECggJEwABLgAFFAUJEgAMAAUdAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8dAAMWAAkJNB0DDQCFAgAXAAkJaBi3CQCfAgAWAAgJqx4DDQCFAgABLgAFFAUJCQAEAI8OAA==.Holyshortguy:BAAALgAECgMJBAAAAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8UAAIYAAgJQRjlLAAAAgAYAAgJQRjlLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAAALgAFFAIJAgAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
In='Inai:BAAALgADCgcJBwABLgAFFAIJAgABAAAAAA==.Invizww:BAAALgADCgMJAwAAAA==.',
Ir='Ircapslock:BAAALgAECgQJBgAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIKAAgJph+PBwBlAgAKAAgJph+PBwBlAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgADCgYJDQABLgAFFAUJCgAQAL8RAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8rAAIEAAkJjiCpAQBTAwAEAAkJjiCpAQBTAwAAAA==.Jaymick:BAAALgAECgUJCQAAAA==.',
Je='Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECgYJCQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAYJFQADAI8eAA==.Jorls:BAACLgAFFH8VAAMDAAYJjx5LAgDeAQADAAYJjx5LAgDeAQAXAAEJWAEcGwBDAAAuAAQKfxsABAMACQkFHlMIAP8CAAMACQkFHlMIAP8CABcABAnSCcg8AMQAABYAAglAAvx1AFEAAAAA.',
Ju='Jusdatip:BAAALgAECgMJCAAAAA==.',
Ka='Kalfu:BAABLgAECn8XAAMSAAgJyB0fEgACAgASAAgJyB0fEgACAgAQAAYJoBWuOQB5AQAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgMJAwAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ki='Kittêh:BAAALgADCgMJAwAAAA==.',
Kn='Knathor:BAAALgAECgMJAwABLgAECgcJDgABAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAAALgAECggJEgAAAA==.Krazermonk:BAABLgAECn8bAAIPAAkJuRvbBwAGAgAPAAkJuRvbBwAGAgAAAA==.Kristysavage:BAAALgAECgcJEwAAAA==.',
Ku='Kurosakí:BAAALgADCgcJBwAAAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECgEJAQAAAA==.',
Le='Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAQAAAA==.',
Li='Lichdawg:BAAALgAECgEJAQAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQABAAAAAA==.Livvela:BAABLgAECn8cAAIZAAgJPBL9GwAfAgAZAAgJPBL9GwAfAgAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8TAAIGAAUJkA/PGQA5AQAGAAUJkA/PGQA5AQAuAAQKfyYAAwYACAmFHQ8mAHoCAAYACAmFHQ8mAHoCAAUAAQnWFcNsADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJAgABAAAAAA==.Lover:BAABLgAECn8fAAIWAAgJdCE3BACSAgAWAAgJdCE3BACSAgAAAA==.',
Lu='Lubu:BAAALgAFFAIJAgAAAA==.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgMJBQABLgAECgQJDwABAAAAAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luev:BAAALgAECgYJBwAAAA==.Lumiette:BAAALgAECgYJCQAAAA==.',
Ly='Lynai:BAAALgAECgEJAQAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8IAAIZAAMJYRtoDAAdAQAZAAMJYRtoDAAdAQAuAAQKfyMAAhkACQnpI4IEAFADABkACQnpI4IEAFADAAAA.',
Ma='Mabil:BAABLgAECn8UAAQGAAcJOxLOPwAyAQAGAAYJdA3OPwAyAQAaAAQJVhWbGAC2AAAFAAIJNgxHIQA0AAAAAA==.Macktimus:BAAALgAECgcJDQAAAA==.Mage:BAAALgAECgkJBwAAAA==.Magictonyp:BAAALgAECgEJAQAAAA==.Magicznstuff:BAAALgADCgEJAQABLgAECgMJBAABAAAAAA==.Magna:BAABLgAECn8ZAAIYAAgJrhEGEAC7AQAYAAgJrhEGEAC7AQAAAA==.Makili:BAAALgAECgEJAgAAAA==.Maladrix:BAAALgAECgQJCwAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Mc='Mchunter:BAAALgAECgMJAwAAAA==.',
Me='Menphina:BAAALgADCgcJBwAAAA==.Merigold:BAAALgAECgEJAQAAAA==.',
Mi='Minnow:BAAALgAECgUJCQAAAA==.Mintchip:BAAALgAECgYJCwAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAHAOoWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJCwABAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
My='Mysternia:BAAALgAECgUJCgAAAA==.Myyagie:BAAALgADCgUJDAAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMbAAgJ5AtHMQAzAQAbAAgJ5AtHMQAzAQAPAAEJWgbkTQAvAAAAAA==.Natureborne:BAAALgAECgQJBAAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJBgAAAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAECgcJCQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Notorckrag:BAABLgAECn8pAAIUAAkJRSC8AgCsAgAUAAkJRSC8AgCsAgAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgQJBgAAAA==.',
Oa='Oathbringer:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgIJAgAAAA==.',
Ol='Oldrecipe:BAAALgAFFAEJAQAAAA==.Oliange:BAABLgAECn8aAAIHAAgJsQn3QgBlAQAHAAgJsQn3QgBlAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQABAAAAAA==.Originalgank:BAAALgAECgUJCQAAAA==.',
Pa='Papanell:BAAALgADCgUJBwAAAA==.',
Pe='Peachcobbler:BAAALgADCgkJEAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAAALgAECgYJBwAAAA==.',
Pl='Plushie:BAAALgAECgYJCwAAAA==.',
Po='Pooqy:BAABLgAECn8WAAINAAgJViK8JACrAgANAAgJViK8JACrAgAAAA==.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAECgcJBwABLgAFFAUJCQACADQZAA==.',
Pr='Pritej:BAAALgAECgYJCQABLgAFFAIJAgABAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgEJAQABLgAFFAIJAgABAAAAAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Ra='Ragel:BAABLgAECn8VAAILAAYJ6BlfFQBXAQALAAYJ6BlfFQBXAQAAAA==.Rainesage:BAAALgAECgYJEAAAAA==.Ralphel:BAAALgAECgUJDAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAcALQMAA==.Ravendark:BAAALgADCgcJCQAAAA==.Rayozap:BAAALgAECgQJBAAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.',
Rh='Rhondaa:BAAALgAECgYJEAAAAA==.Rhubarb:BAABLgAECn8lAAMYAAgJ1CSyAQDiAgAYAAgJKCSyAQDiAgAdAAEJCCV2IQBsAAAAAA==.',
Ro='Rohiem:BAABLgAECn8dAAIYAAgJ/RIFDgDTAQAYAAgJ/RIFDgDTAQAAAA==.',
Ry='Ryan:BAABLgAECn8eAAICAAkJYh4XHADBAgACAAkJYh4XHADBAgAAAA==.Rylorthas:BAACLgAFFH8QAAIWAAQJLBnBBAA6AQAWAAQJLBnBBAA6AQAuAAQKfysAAhYACQnTG8sSAEoCABYACQnTG8sSAEoCAAAA.Rylosh:BAAALgADCgYJBgABLgAFFAQJEAAWACwZAA==.',
Sa='Sabot:BAAALgAECgUJCQAAAA==.Salazar:BAAALgAECgEJAQAAAA==.Satisfied:BAAALgAECgQJBwAAAA==.',
Sc='Scottmonk:BAAALgAECgIJAgAAAA==.',
Se='Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamerica:BAACLgAFFH8NAAIeAAUJryAJAQAgAQAeAAUJryAJAQAgAQAuAAQKfyYAAx4ACQm2IsACABYDAB4ACQm2IsACABYDAAwABAlTHU8/AE0BAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8WAAISAAcJoBpmGQDJAQASAAcJoBpmGQDJAQAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgADCgkJEAAAAA==.Skyleax:BAACLgAFFH8FAAMNAAMJegomOgDnAAANAAMJegomOgDnAAAOAAEJuwKtBwBGAAAuAAQKfxgABA0ACQkTIEcuAH8CAA0ACQnpHEcuAH8CAA4ABAkVHkQMAPAAAB8AAQn7D0JLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAINAAkJywRZmQBNAQANAAkJywRZmQBNAQAAAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8VAAQgAAcJkgcDJgDzAAAgAAYJRQcDJgDzAAAhAAYJ2QaYRgDBAAAcAAEJtBqtHQBNAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAgABLgAECgQJDwABAAAAAA==.Steppers:BAAALgADCgEJAQAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgADCgcJBwAAAA==.',
Sv='Svelana:BAABLgAECn8XAAIPAAgJ6yB0DQCkAgAPAAgJ6yB0DQCkAgAAAA==.',
Sy='Syb:BAAALgAECgUJCgAAAA==.Sylphrena:BAABLgAECn8gAAIDAAkJox+iCwDJAgADAAkJox+iCwDJAgAAAA==.Syssana:BAAALgAECgEJAgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJDQAAAA==.',
Te='Telafar:BAAALgAECgkJAQAAAA==.',
Th='Theinsider:BAABLgAECn8rAAMGAAkJmB+MDAAWAwAGAAkJmB+MDAAWAwAFAAUJkA+nKwARAQAAAA==.Thenezath:BAAALgADCgQJBAAAAA==.Theoutsider:BAAALgAECgIJAgABLgAECgkJKwAGAJgfAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJBwAAAA==.Tigerbait:BAAALgADCgkJFwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Tomatoteng:BAACLgAFFH8JAAICAAUJNBmlIQCpAAACAAUJNBmlIQCpAAAuAAQKfyAAAgIACQmPJH4DAJsDAAIACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAAALgAECgQJBwAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAIANcmAA==.Tranza:BAAALgAECggJEgAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAAJAKUiAA==.Trinshunter:BAABLgAECn8YAAQSAAcJVBIWRQCcAQASAAcJVBIWRQCcAQAiAAEJ6gnBLwA0AAAQAAEJ4gEVmgAZAAABLgAFFAQJDQACAAALAA==.',
Tx='Tx:BAACLgAFFH8SAAIMAAUJBR2GBQBtAQAMAAUJBR2GBQBtAQAuAAQKfyMAAgwACAlZIUQQAKcCAAwACAlZIUQQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgQJCwAAAA==.',
Va='Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgYJDQAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIHAAkJ6hZeIQDmAQAHAAkJ6hZeIQDmAQAAAA==.Wetheals:BAAALgAECgMJBQAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8cAAIHAAgJ6g+ENgCMAQAHAAgJ6g+ENgCMAQAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQAAAA==.Wtfmate:BAAALgADCgYJCQAAAA==.Wtfmonk:BAABLgAECn8dAAIbAAkJKhTsHQDGAQAbAAkJKhTsHQDGAQAAAA==.',
Xa='Xaioli:BAABLgAECn8gAAMGAAkJXCUgAgAXAwAGAAkJXCUgAgAXAwAFAAIJwyF6RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAAALgAECgUJCgAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgADCgcJGAAAAA==.',
Ya='Yazmo:BAACLgAFFH8GAAIDAAMJqhiLCgAUAQADAAMJqhiLCgAUAQAuAAQKfzMAAgMACAn+IqoCAKICAAMACAn+IqoCAKICAAAA.',
Yu='Yuuky:BAABLgAECn8hAAIEAAgJNBn6JAAmAgAEAAgJNBn6JAAmAgAAAA==.',
Za='Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMcAAgJtAyPHAChAQAcAAgJtAyPHAChAQAgAAEJSwfAFAArAAAAAA==.',
Ze='Zendrov:BAAALgAECggJEgAAAA==.Zenpai:BAAALgAECgEJAwAAAA==.',
Zi='Ziillah:BAAALgAECgEJAQAAAA==.Zinogre:BAABLgAECn8bAAIeAAgJZQuZBgCcAQAeAAgJZQuZBgCcAQAAAA==.',
['Äp']='Äpollo:BAAALgAECgEJAgAAAA==.',
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
