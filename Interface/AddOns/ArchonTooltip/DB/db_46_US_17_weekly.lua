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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','Unknown-Unknown','Druid-Restoration','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Mage-Frost','DemonHunter-Devourer','Warrior-Protection','Paladin-Holy','Druid-Balance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Vengeance','Warlock-Affliction','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Rogue-Subtlety','Monk-Mistweaver','Evoker-Preservation','Shaman-Enhancement','DeathKnight-Blood','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aanaleaa:BAAALgAECgUJCgAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAAALgAECgcJDQABLgAECgkJHwABAIQkAA==.Adellon:BAAALgAFFAIJAwAAAA==.Adhar:BAAALgAECgEJAQAAAA==.Adrielle:BAABLgAECn8aAAICAAYJWRt2UwBMAQACAAYJWRt2UwBMAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn8aAAIDAAgJlhRsJwDJAQADAAgJlhRsJwDJAQAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAYJFQAEAI8eAA==.',
Ai='Airphobic:BAAALgAECgIJCQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECgYJEgAFAAAAAA==.Akakaji:BAAALgAECgYJEgAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIGAAgJMxxsFACSAgAGAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgQJBAAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgYJDgAAAA==.Anomander:BAAALgAECgYJEwAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAAALgAECgcJEAABLgAECgkJHwABAIQkAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAABLgAECn8WAAMHAAcJQx1JDgAJAgAHAAcJQx1JDgAJAgAIAAEJAADBSgARAAAAAA==.Argig:BAAALgADCgcJCAAAAA==.Arienca:BAABLgAECn8wAAMJAAkJJwxGFgCYAQADAAkJYgryLwCjAQAJAAgJ5gpGFgCYAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Asu:BAAALgAECgYJEgAAAA==.',
At='At:BAABLgAECn8XAAIKAAYJyhULqACJAQAKAAYJyhULqACJAQABLgAECgkJHwABAIQkAA==.',
Au='Aubrey:BAACLgAFFH8JAAIGAAQJYgdSJgC6AAAGAAQJYgdSJgC6AAAuAAQKfxQAAgYACQlzCp9SAFwBAAYACQlzCp9SAFwBAAAA.',
Av='Avengion:BAAALgAECgUJCQAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAUJDgAGAMEYAA==.Beldent:BAAALgAECgQJBgAAAA==.',
Bl='Blazegrave:BAAALgADCgMJAwABLgAECggJHwAKANQOAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgUJDgAFAAAAAA==.Blazerunner:BAABLgAECn8fAAIKAAgJ1A6aRQCWAQAKAAgJ1A6aRQCWAQAAAA==.Blazesmasher:BAAALgADCgkJEwABLgAECggJHwAKANQOAA==.Blitzkreig:BAAALgAECgYJDgAAAA==.Bluefoot:BAAALgAECgUJCwAAAA==.Blured:BAABLgAECn8qAAILAAkJaSMkAgA1AwALAAkJaSMkAgA1AwAAAA==.',
Bo='Booty:BAABLgAECn8oAAIMAAkJpSLAAQDnAgAMAAkJpSLAAQDnAgAAAA==.',
Br='Brightblayde:BAABLgAECn8VAAICAAYJChHoaAAbAQACAAYJChHoaAAbAQAAAA==.Brynhildre:BAABLgAECn8UAAINAAcJfgtRRABmAQANAAcJfgtRRABmAQABLgAFFAQJCQAGAGIHAA==.',
Bu='Buum:BAAALgAECgUJCgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
Ca='Cachelyn:BAAALgADCgcJBwAAAA==.Cali:BAACLgAFFH8YAAILAAYJ1BzqBwC8AQALAAYJ1BzqBwC8AQAuAAQKfyMAAgsACAmkIeISAOgCAAsACAmkIeISAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIKAAgJYh5GGQBTAgAKAAgJYh5GGQBTAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCQAFAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCQAFAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8HAAIGAAUJkw+ADwBZAQAGAAUJkw+ADwBZAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Choom:BAABLgAECn8fAAMGAAkJuhUMNgDQAQAGAAkJuhUMNgDQAQAOAAYJjRPmLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Chronocide:BAABLgAECn8qAAIPAAkJ1B8MDAAZAgAPAAkJ1B8MDAAZAgAAAA==.Chronophasia:BAAALgADCgkJGAAAAA==.Chroños:BAAALgAECgYJBgAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8QAAILAAUJPhxZHQA1AQALAAUJPhxZHQA1AQAuAAQKfxsAAgsACAnoI4sQAPoCAAsACAnoI4sQAPoCAAAA.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIGAAgJsxpRGwDpAQAGAAgJsxpRGwDpAQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgADCgYJDgAAAA==.Croh:BAABLgAECn8aAAMQAAgJpBNXVAD0AQAQAAgJpBNXVAD0AQARAAQJawb1DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.',
Cy='Cynestra:BAAALgAECgYJCgAAAA==.',
Da='Dadudadu:BAACLgAFFH8SAAICAAYJXA6TDgA1AQACAAYJXA6TDgA1AQAuAAQKfzQAAgIACQkZIHcWAOICAAIACQkZIHcWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8VAAISAAUJFyWeAQC3AQASAAUJFyWeAQC3AQAuAAQKfyoAAhIACAnJJLECAG8DABIACAnJJLECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAATAOcVAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgEJAQAAAA==.Darkwingfish:BAABLgAECn8pAAILAAkJrRRwHgDSAQALAAkJrRRwHgDSAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAAALgAECgUJCQAAAA==.Dayman:BAAALgAECgcJBwAAAA==.',
De='Deadweight:BAAALgAECgcJCAAAAA==.Decày:BAAALgAECgcJDwAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Dethblow:BAAALgAECgMJBwAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAABLgAECn8ZAAMUAAkJ/AaYOQAhAQAUAAkJ/AaYOQAhAQAPAAYJSQfaUQD/AAAAAA==.',
Dk='Dklot:BAAALgAFFAEJAQAAAA==.',
Dr='Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8nAAIVAAgJwxkpLwCRAQAVAAgJwxkpLwCRAQAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBAAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAICAAkJ8RtdFgDjAgACAAkJ8RtdFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMLAAkJ1yaKAwCTAwALAAkJ1yaKAwCTAwAWAAQJfhprCQBBAQAAAA==.',
En='Enkeke:BAABLgAECn8wAAIQAAkJgBy2EQBuAgAQAAkJgBy2EQBuAgAAAA==.',
Er='Eresanna:BAAALgAECgEJBAAAAA==.',
Es='Esdeath:BAAALgAECgQJBQABLgAFFAMJAwAFAAAAAA==.Estus:BAAALgAECgcJDQAAAA==.',
Ex='Extremefear:BAABLgAECn8cAAMJAAgJhxMeEgDFAAADAAQJ/hLybQDvAAAJAAUJ6hMeEgDFAAAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8NAAMDAAQJVSWYCACtAQADAAQJxiSYCACtAQAXAAEJYSYvBAB1AAAuAAQKfx4AAwMACAnPJc8rAF8CAAMABwn9I88rAF8CAAkAAgkmJFE3ANgAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAAALgAECgcJEwAAAA==.Fenrisul:BAAALgADCgIJAgAAAA==.Feralshunter:BAACLgAFFH8IAAITAAQJ5xWlBwBGAQATAAQJ5xWlBwBGAQAuAAQKfzIAAhMACQn/II0QALgCABMACQn/II0QALgCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Forfoxsake:BAABLgAECn8iAAIYAAgJjx/EBwBSAgAYAAgJjx/EBwBSAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8OAAIGAAUJwRjTCQCeAQAGAAUJwRjTCQCeAQAAAA==.Furrów:BAAALgADCgcJBwAAAA==.',
['Fû']='Fûrrow:BAAALgAECgEJAgAAAA==.',
Ga='Gallindral:BAABLgAECn82AAILAAkJUh1+BgDBAgALAAkJUh1+BgDBAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gatito:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.Gauthus:BAAALgAECggJCAAAAA==.',
Ge='Genericnpc:BAAALgAECgUJBwAAAA==.Geobrando:BAABLgAECn8wAAMUAAkJ7x5tCwDHAgAUAAkJ7x5tCwDHAgAPAAMJmxF5ZgCpAAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8PAAICAAQJGx2GDwBpAQACAAQJGx2GDwBpAQAuAAQKf1sABAIACQl4JUcBAGIDAAIACQl4JUcBAGIDAA0ACAnzGFcMAE8CAAEABAnLBpUmAGUAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJCgABLgAECggJHwAKANQOAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAAALgAECgYJDQAAAA==.Gnova:BAABLgAECn8bAAIKAAYJvB+FQwCdAQAKAAYJvB+FQwCdAQAAAA==.',
Go='Gorian:BAAALgAECgcJBQAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgADCgcJGAAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIUAAgJhhdiHAA2AgAUAAgJhhdiHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAYJGAALANQcAA==.Harle:BAAALgAECgYJDgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIKAAcJWgvJYABQAQAKAAcJWgvJYABQAQABLgAFFAYJEgACAFwOAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAICAAgJZSEqDAChAgACAAgJZSEqDAChAgABLgAFFAUJFwAPAAcdAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMZAAkJNB3/DACFAgAaAAkJaBi2CQCfAgAZAAgJqx7/DACFAgABLgAFFAUJDgAGAMEYAA==.Holyshortguy:BAAALgAECgMJBAAAAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAIHAAgJLhziLAAAAgAHAAgJLhziLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8FAAIHAAMJFhA5GgDkAAAHAAMJFhA5GgDkAAAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
In='Inai:BAAALgADCgcJCQABLgAFFAMJAwAFAAAAAA==.Invizww:BAAALgAECgMJAwAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAINAAgJph/dEACLAgANAAgJph/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgADCgYJDQABLgAFFAUJDQATAFYUAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIGAAkJjyD3AgBKAwAGAAkJjyD3AgBKAwAAAA==.Jaymick:BAAALgAECgYJDQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBQAAAA==.',
Je='Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECgYJCQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAYJFQAEAI8eAA==.Jorls:BAACLgAFFH8VAAMEAAYJjx5LAgDeAQAEAAYJjx5LAgDeAQAaAAEJWAEgGwBDAAAuAAQKfxsABAQACQkFHlIIAP8CAAQACQkFHlIIAP8CABoABAnSCck8AMQAABkAAglAAgN2AFEAAAAA.',
Ju='Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kalfu:BAABLgAECn8XAAMVAAgJyB1GEABTAgAVAAgJyB1GEABTAgATAAYJoBX3OQB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgMJAwAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ki='Kittêh:BAAALgADCgMJAwAAAA==.',
Kn='Knathor:BAAALgAECgMJAwABLgAECgcJDgAFAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8UAAICAAgJmRrNWADYAQACAAgJmRrNWADYAQAAAA==.Krazermonk:BAABLgAECn8cAAISAAkJxBuVCwD/AQASAAkJxBuVCwD/AQAAAA==.Kristysavage:BAABLgAECn8TAAIVAAcJ1hxnOADMAQAVAAcJ1hxnOADMAQAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJCQAAAA==.',
Le='Lealta:BAAALgAECgUJBQAAAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Li='Lichdawg:BAABLgAFFH8HAAIRAAQJbQZiAwASAQARAAQJbQZiAwASAQAAAA==.Lilzayna:BAAALgADCgIJAgABLgAECgUJBgAFAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQAFAAAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8iAAIbAAkJnxSZCAAbAgAbAAkJnxSZCAAbAgAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8VAAIDAAUJ9g8XFwA3AQADAAUJ9g8XFwA3AQAuAAQKfyYAAwMACAmFHQ0mAHoCAAMACAmFHQ0mAHoCAAkAAQnWFcNsADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJAwAFAAAAAA==.Lover:BAABLgAECn8hAAIZAAgJjCFJBQCxAgAZAAgJjCFJBQCxAgAAAA==.',
Lu='Lubu:BAAALgAFFAMJAwAAAA==.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJBgABLgAECgcJGAAaAFcQAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJAgAAAA==.Luev:BAAALgAECgYJBwAAAA==.Lumiette:BAAALgAECgYJCQAAAA==.',
Ly='Lynai:BAAALgAECgUJCAAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8LAAIbAAMJeCBrDAAdAQAbAAMJeCBrDAAdAQAuAAQKfyUAAhsACQmSJIIEAFADABsACQmSJIIEAFADAAAA.',
Ma='Mabil:BAABLgAECn8UAAQDAAcJOxJcVgApAQADAAYJdA1cVgApAQAXAAQJVhWcGAC2AAAJAAIJNgwIKQAxAAAAAA==.Macktimus:BAABLgAECn8VAAIJAAcJhRasBQCeAQAJAAcJhRasBQCeAQAAAA==.Magictonyp:BAAALgAECgEJAQAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBAAFAAAAAA==.Magna:BAABLgAECn8hAAIHAAgJ8BEDFwCvAQAHAAgJ8BEDFwCvAQAAAA==.Makili:BAAALgAECgIJAwAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.',
Mc='Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.',
Mi='Minnow:BAAALgAECgUJCQAAAA==.Mintchip:BAAALgAECgYJCwAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAKAOoWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQAFAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
My='Mysternia:BAAALgAECgYJDgAAAA==.Myyagie:BAAALgADCgUJDAAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMcAAgJ5AtFMQAzAQAcAAgJ5AtFMQAzAQASAAEJWgY7ZwAsAAAAAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJBgABLgAECgcJDgAFAAAAAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECgcJDQAFAAAAAA==.Notorckrag:BAABLgAECn8vAAIYAAkJdiDVAgDaAgAYAAkJdiDVAgDaAgAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgIJBAAAAA==.',
Ol='Oldrecipe:BAAALgAFFAIJAwAAAA==.Oliange:BAABLgAECn8cAAIKAAgJ+QoIUwByAQAKAAgJ+QoIUwByAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQAFAAAAAA==.Originalgank:BAAALgAECgYJCgAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECgYJBgAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAAALgAECgYJCwAAAA==.',
Pl='Plushie:BAAALgAECgYJCwAAAA==.',
Po='Pooqy:BAACLgAFFH8HAAIQAAQJpSKGDwCXAQAQAAQJpSKGDwCXAQAuAAQKfxYAAhAACAlWIrUkAKsCABAACAlWIrUkAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAECgcJBwABLgAFFAUJCQACADQZAA==.',
Pr='Pritej:BAAALgAECgYJCQABLgAFFAIJAwAFAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJBAABLgAFFAMJAwAFAAAAAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Ra='Ragel:BAABLgAECn8cAAIOAAcJ6RumEADKAQAOAAcJ6RumEADKAQAAAA==.Rainesage:BAABLgAECn8YAAIEAAgJ2hnNCgAXAgAEAAgJ2hnNCgAXAgAAAA==.Ralphel:BAAALgAECgYJEgAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAdALQMAA==.Ravendark:BAAALgADCgcJCQAAAA==.Rayozap:BAAALgAECgQJBAAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.',
Rh='Rhondaa:BAAALgAECgYJEAAAAA==.Rhubarb:BAABLgAECn8tAAMHAAkJayV9AwDTAgAHAAgJgCR9AwDTAgAIAAYJTyWuAgCQAgAAAA==.',
Ro='Rohiem:BAABLgAECn8lAAIHAAgJ1BfjDQAOAgAHAAgJ1BfjDQAOAgAAAA==.',
Ry='Ryan:BAABLgAECn8eAAICAAkJYh4UHADBAgACAAkJYh4UHADBAgAAAA==.Rylorthas:BAACLgAFFH8VAAIZAAUJ6xgpBQB5AQAZAAUJ6xgpBQB5AQAuAAQKfysAAhkACQnTG8oSAEoCABkACQnTG8oSAEoCAAAA.Rylosh:BAAALgADCgYJBgABLgAFFAUJFQAZAOsYAA==.',
Sa='Sabot:BAAALgAECgYJDQAAAA==.Sabrook:BAAALgADCgEJAQAAAA==.Salazar:BAAALgAECgEJAQAAAA==.Sam:BAAALgAECgIJAgAAAA==.Satisfied:BAAALgAECgQJCwAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBAAAAA==.',
Se='Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamerica:BAACLgAFFH8QAAIeAAUJNCHgAQBuAQAeAAUJNCHgAQBuAQAuAAQKfyYAAx4ACQm2IsACABYDAB4ACQm2IsACABYDAA8ABAlTHVA/AE0BAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8bAAIVAAcJShwxHgDnAQAVAAcJShwxHgDnAQAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgADCgkJEgAAAA==.Skyleax:BAACLgAFFH8IAAMQAAQJDQq/NwArAQAQAAQJDQq/NwArAQARAAEJuwLcCgBAAAAuAAQKfxgABBAACQkTIEEuAH8CABAACQnpHEEuAH8CABEABAkVHkQMAPAAAB8AAQn7D0NLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIQAAkJywRcmQBNAQAQAAkJywRcmQBNAQAAAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8eAAQdAAgJVRUQCQDRAQAdAAcJBBYQCQDRAQAgAAYJRQf+JQDzAAAhAAYJ1gaZRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAECgcJGAAaAFcQAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgADCgcJBwAAAA==.',
Sv='Svelana:BAABLgAECn8dAAISAAgJayF0DQCkAgASAAgJayF0DQCkAgAAAA==.',
Sy='Syb:BAAALgAECgYJDgAAAA==.Sylphrena:BAACLgAFFH8IAAIEAAQJrxT1CgBNAQAEAAQJrxT1CgBNAQAuAAQKfycAAgQACQnLIkABADADAAQACQnLIkABADADAAAA.Syssana:BAAALgAECgEJAwAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAQAAAA==.',
Th='Theinsider:BAABLgAECn8rAAMDAAkJmB+KDAAWAwADAAkJmB+KDAAWAwAJAAUJkA+mKwARAQAAAA==.Thenezath:BAAALgADCgQJBAAAAA==.Theoutsider:BAAALgAECgYJCAABLgAECgkJKwADAJgfAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgQJBAAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAAALgAECgYJCgABLgAFFAUJFwAPAAcdAA==.Tomatoteng:BAACLgAFFH8JAAICAAUJNBmIEABlAQACAAUJNBmIEABlAQAuAAQKfyAAAgIACQmPJH0DAJsDAAIACQmPJH0DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAAALgAECgQJBwAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAALANcmAA==.Tranza:BAAALgAECggJEwAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAAMAKUiAA==.Trinshunter:BAABLgAECn8fAAQVAAcJHxgJJgC8AQAVAAcJHxgJJgC8AQAiAAEJ6gnCLwA0AAATAAEJ4gEimgAZAAABLgAFFAQJDgACAFQLAA==.',
Tx='Tx:BAACLgAFFH8XAAIPAAUJBx3xCQBbAQAPAAUJBx3xCQBbAQAuAAQKfygAAg8ACAmLIVALACUCAA8ACAmLIVALACUCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgQJCwAAAA==.',
Va='Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgYJDQAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIKAAkJ6haWLwDiAQAKAAkJ6haWLwDiAQAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIKAAgJ/w/0QACkAQAKAAgJ/w/0QACkAQAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQAAAA==.Wtfmate:BAAALgADCgYJCQAAAA==.Wtfmonk:BAABLgAECn8dAAIcAAkJKhTrHQDGAQAcAAkJKhTrHQDGAQAAAA==.',
Xa='Xaioli:BAABLgAECn8gAAMDAAkJXCUrBAAKAwADAAkJXCUrBAAKAwAJAAIJwyF7RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAAALgAECgYJDgAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgADCggJIwAAAA==.',
Ya='Yazmo:BAACLgAFFH8KAAIEAAMJHCI7DQA3AQAEAAMJHCI7DQA3AQAuAAQKfzMAAgQACAn+Ir8EAJgCAAQACAn+Ir8EAJgCAAAA.',
Yu='Yuuky:BAACLgAFFH8HAAIGAAMJ9AtbJQC/AAAGAAMJ9AtbJQC/AAAuAAQKfyEAAgYACAk0GfkkACYCAAYACAk0GfkkACYCAAAA.',
Za='Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMdAAgJtAySHAChAQAdAAgJtAySHAChAQAgAAEJSwfIGQApAAAAAA==.',
Ze='Zendrov:BAABLgAECn8ZAAIhAAgJOgT6MADhAAAhAAgJOgT6MADhAAAAAA==.Zenpai:BAAALgAECgEJBQAAAA==.',
Zi='Ziillah:BAAALgAECgEJAQAAAA==.Zinogre:BAABLgAECn8jAAIeAAkJgBG8BAATAgAeAAkJgBG8BAATAgAAAA==.',
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
