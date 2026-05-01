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

local lookup = {'Mage-Frost','Druid-Balance','Warlock-Demonology','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Warrior-Fury','Warrior-Arms','Paladin-Protection','Shaman-Elemental','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Druid-Restoration','Priest-Shadow','Druid-Feral','Hunter-Survival','Rogue-Subtlety','Monk-Windwalker','Shaman-Enhancement','Shaman-Restoration','Warlock-Destruction','Evoker-Preservation','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','Monk-Brewmaster','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ae='Aeidail:BAACLgAFFH8SAAIBAAUJPRrxEwB7AQABAAUJPRrxEwB7AQAuAAQKfyQAAgEACAmnI0AcAAUDAAEACAmnI0AcAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAAALgAECgQJBwAAAA==.',
Ag='Agraceful:BAABLgAECn8ZAAICAAcJ9g+yFgBKAQACAAcJ9g+yFgBKAQAAAA==.',
Ai='Ailee:BAAALgAECgIJAwAAAA==.Aios:BAAALgADCgcJCQAAAA==.Aiza:BAABLgAECn8lAAMDAAgJ8RGxJQCZAQADAAgJ8RGxJQCZAQAEAAEJAAD0NwAdAAAAAA==.',
Al='Aldanil:BAAALgADCgMJAwAAAA==.',
An='Animalfriend:BAAALgADCgUJBQAAAA==.Anklesmasher:BAAALgAECgUJCQAAAA==.Anyah:BAAALgAECgQJBAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Ar='Arfaz:BAAALgAECgUJDQAAAA==.Armbrost:BAAALgAECgYJBwAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgQJBQAFAAAAAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECggJJAADAKciAA==.Astrastar:BAAALgAECgUJCQAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8ZAAIGAAcJbhP0DwCmAQAGAAcJbhP0DwCmAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQAAAA==.Beanutbutter:BAAALgADCgIJAgABLgAECgcJAQAFAAAAAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAAALgAECgMJBAAAAA==.Belwolf:BAAALgAECgIJAwAAAA==.Bergstrom:BAABLgAECn8iAAIHAAgJnxjVGQDvAQAHAAgJnxjVGQDvAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECggJJAADAKciAA==.',
Bi='Bighero:BAABLgAECn8ZAAIIAAcJwhJWbwBWAQAIAAcJwhJWbwBWAQAAAA==.',
Bl='Blakkjezus:BAAALgAECgQJBQAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8FAAIJAAQJPAiNGgCeAAAJAAQJPAiNGgCeAAAuAAQKfxwAAwkACAmdIGgZAIACAAkACAk5GWgZAIACAAoABQlJGlUYADYBAAAA.',
Bo='Boe:BAAALgAECgYJDwAAAA==.Bombacløt:BAAALgAECgUJEQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn8YAAILAAcJQx4fCACRAQALAAcJQx4fCACRAQABLgAECggJGwAMALwZAA==.Brenell:BAABLgAECn8hAAIBAAgJuCCGDwBhAgABAAgJuCCGDwBhAgAAAA==.',
Bu='Buffet:BAAALgADCgYJCQABLgAECggJFAAIAHwYAA==.Buhlitz:BAAALgAECgEJAgAAAA==.',
By='Bynis:BAABLgAECn8VAAIIAAcJ5hVbPwDpAAAIAAcJ5hVbPwDpAAAAAA==.',
Ca='Cabëla:BAAALgADCgEJAQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.',
Ch='Choal:BAAALgAECgEJAQAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIMAAYJGRAqIwAGAQAMAAYJGRAqIwAGAQAAAA==.Corious:BAAALgAECgIJAgAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.',
Cr='Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8VAAINAAcJMCU9AQB4AgANAAcJMCU9AQB4AgAAAA==.',
Da='Daemonerror:BAAALgADCgYJBgABLgAECgYJFgAOALAjAA==.Dalren:BAACLgAFFH8NAAMPAAQJRB5kBwB9AQAPAAQJRB5kBwB9AQAQAAEJuwNiCwBLAAAuAAQKfyoAAw8ACQl5JDkHAAcDAA8ACQk0JDkHAAcDABAABgnyID8MABcCAAAA.Dalryn:BAAALgAECgYJCgABLgAFFAQJDQAPAEQeAA==.Dalvix:BAAALgADCgEJAQABLgAECgcJFwAIAOocAA==.Damocles:BAAALgAECgYJDQAAAA==.Dartagnan:BAABLgAECn8dAAMRAAcJfhvZCwARAQARAAYJ9BTZCwARAQASAAQJ8x2xjwC7AAAAAA==.Darthmaul:BAABLgAECn8WAAICAAgJPg/rDwCVAQACAAgJPg/rDwCVAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJHgAAAA==.Dendiian:BAAALgAECgUJCQAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECggJFAAIAHwYAA==.Diem:BAAALgAECggJEgAAAA==.Dirtydotss:BAABLgAECn8VAAMEAAcJEgfZEgD/AAAEAAYJYQbZEgD/AAADAAYJ4QTGXwDUAAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAFAAAAAA==.Doregit:BAABLgAECn8UAAIJAAYJpBGHGwBUAQAJAAYJpBGHGwBUAQAAAA==.Dowedoes:BAABLgAECn8jAAIHAAgJxBMDJwCnAQAHAAgJxBMDJwCnAQAAAA==.',
Dr='Drachula:BAAALgAECgUJCQAAAA==.Dracultra:BAAALgAECgIJAgABLgAECggJFwATAHsgAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn8iAAIUAAgJwwzPMgAPAQAUAAgJwwzPMgAPAQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAABLgAECn8cAAMUAAcJthG0XwAzAQAUAAcJthG0XwAzAQACAAIJMQpCOgBdAAAAAA==.',
['Dö']='Dönövan:BAAALgAECgYJEAAAAA==.',
El='Eloise:BAAALgAECgQJBAAAAA==.Elvenbane:BAABLgAECn8cAAIVAAgJng8NDgCkAQAVAAgJng8NDgCkAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgYJEAAFAAAAAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Fa='Fabel:BAEBLgAECn8nAAILAAgJUiJyAQChAgALAAgJUiJyAQChAgABLgADCgEJAQAFAAAAAA==.Falahad:BAAALgAECgEJAQABLgAECgcJHQAUAO8YAA==.Faltree:BAABLgAECn8dAAQUAAcJ7xj5UwBXAQAUAAYJTRj5UwBXAQACAAcJrxenGQAwAQAWAAEJ3wFHOgAfAAAAAA==.Fathershale:BAAALgADCgMJAwAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAAALgAECgcJEQAAAA==.',
Fr='Freakadeek:BAAALgAECgYJCgABLgAECgYJFAAXAKgQAA==.Freâkadeek:BAAALgAECgIJAgABLgAECgYJFAAXAKgQAA==.Freäk:BAAALgADCgMJAwABLgAECgYJFAAXAKgQAA==.Frieren:BAABLgAECn8eAAIBAAcJTBLaVAA2AQABAAcJTBLaVAA2AQAAAA==.Frink:BAAALgADCgEJAQABLgAECggJIwAXAF0gAA==.',
Fu='Fundetected:BAAALgADCgYJBgABLgAECggJFAAIAHwYAA==.',
Ga='Gabbyo:BAAALgAECgYJDQAAAA==.Galadorn:BAABLgAECn8XAAIIAAcJ6hwTEADwAQAIAAcJ6hwTEADwAQAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgADCgYJFQAAAA==.Garga:BAAALgADCgMJBAABLgADCgcJFAAFAAAAAA==.',
Ge='Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAAALgAECgQJCwAAAA==.',
Gh='Ghallow:BAAALgAECgMJBgAAAA==.Ghosty:BAABLgAECn8cAAIYAAcJSh+RFABuAgAYAAcJSh+RFABuAgAAAA==.',
Gl='Gladur:BAAALgADCgEJAQABLgAFFAUJEgABAD0aAA==.',
Go='Goldenflame:BAAALgADCggJEQAAAA==.Goldenlily:BAAALgAECgYJEQAAAA==.Goldenmunc:BAABLgAECn8UAAIBAAcJTRFgOwB8AQABAAcJTRFgOwB8AQAAAA==.Goldenone:BAAALgAECgEJAQAAAA==.Goldenpants:BAAALgAECgcJDwAAAA==.',
Gr='Grievous:BAABLgAECn8jAAINAAgJkCVmAADyAgANAAgJkCVmAADyAgAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8VAAIGAAcJPiWuAgDRAgAGAAcJPiWuAgDRAgAAAA==.Harusen:BAAALgAECgYJDwAAAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAECgkJLQABAAIdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIPAAYJ5hfoJACVAQAPAAYJ5hfoJACVAQAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgEJAQABLgAECgcJGQAUAGQaAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgYJDwAFAAAAAA==.Hyir:BAAALgADCgYJBwABLgAECgkJLQAZAEgkAA==.',
Il='Illiya:BAAALgAECgEJAQAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgEJAQAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn8aAAQMAAcJ+AgkIQASAQAaAAYJ9we6GgAeAQAbAAcJ5AYMLAAWAQAMAAcJGgckIQASAQAAAA==.',
Je='Jek:BAAALgAECgEJAQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ka='Kaevrielle:BAEBLgAECn8UAAINAAgJMhppCQDZAQANAAgJMhppCQDZAQAAAA==.Kaison:BAAALgADCgEJAQABLgAECgcJFQAIAOYVAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAUJEgABAD0aAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAABLgAECn8XAAIBAAYJ2BXFRgBaAQABAAYJ2BXFRgBaAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgUJBwABLgAECggJLAAHAFsjAA==.Keeperodark:BAAALgAECggJEAABLgAECggJLAAHAFsjAA==.Keeperolight:BAABLgAECn8sAAMHAAgJWyMdBQDJAgAHAAgJWyMdBQDJAgATAAEJgRgFkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECggJHAAVAJ4PAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8VAAIBAAcJTBeoMAChAQABAAcJTBeoMAChAQAAAA==.',
Ko='Kodera:BAAALgAECgUJDwAAAA==.Koojo:BAAALgADCgQJBQAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ky='Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAECgYJCgAAAA==.Larew:BAAALgAECgYJEQAAAA==.Lazytemplar:BAAALgADCgMJAwABLgAECgQJBgAFAAAAAA==.',
Le='Lealla:BAABLgAECn8jAAICAAgJ7hy0BgAxAgACAAgJ7hy0BgAxAgAAAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8HAAMRAAQJXgu9BgAmAQARAAQJBgu9BgAmAQASAAIJ4wYJGgCeAAAuAAQKfyQAAxEACAnHHtIhABQCABEACAm5GdIhABQCABIAAgk+JFeHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJCwAAAA==.',
Lo='Loganshu:BAAALgADCgcJEgAAAA==.Lokan:BAABLgAECn8dAAIXAAcJdRuiCQDHAQAXAAcJdRuiCQDHAQAAAA==.Lots:BAABLgAECn8iAAMDAAcJwCNzHgC+AQADAAYJYyRzHgC+AQAcAAQJxh5FLAANAQAAAA==.',
Lu='Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAAALgAECgYJEAAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8XAAIbAAgJfxNsKgAfAQAbAAgJfxNsKgAfAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAAALgAECgUJDgAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8NAAIBAAUJkRpPGQBiAQABAAUJkRpPGQBiAQAuAAQKfxcAAgEACAmfJUEhAO4CAAEACAmfJUEhAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAFAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Mahina:BAAALgAECgIJAgAAAA==.Marcille:BAABLgAECn8aAAIBAAcJsxILhgDFAQABAAcJsxILhgDFAQAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn8nAAMSAAkJYBj1CwBCAgASAAkJYBj1CwBCAgARAAEJZACWmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn8jAAIXAAgJXSADBABOAgAXAAgJXSADBABOAgAAAA==.',
Me='Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAAALgAECgcJDgAAAA==.',
Mi='Minerwor:BAAALgAECgIJAwAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn8hAAICAAgJZQ3vEwBlAQACAAgJZQ3vEwBlAQAAAA==.',
Mo='Moarthretplz:BAAALgAECgQJBAAAAA==.Momometaru:BAAALgAECgcJEwAAAA==.Monsterbee:BAABLgAECn8lAAIDAAgJ9g3TJACdAQADAAgJ9g3TJACdAQAAAA==.',
Mu='Mustypizza:BAABLgAECn8VAAIcAAcJ8BMDBQB/AQAcAAcJ8BMDBQB/AQAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn8jAAMdAAgJEx2vAgCGAgAdAAgJEx2vAgCGAgAQAAMJwxEFCwC4AAAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECgcJCwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgIJAwAAAA==.',
Na='Narashi:BAAALgADCgIJAwAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8dAAIbAAgJ7xCsOACgAQAbAAgJ7xCsOACgAQAAAA==.',
Ne='Neameny:BAABLgAECn8jAAISAAgJAxG9GwC5AQASAAgJAxG9GwC5AQAAAA==.',
Ni='Nianji:BAAALgADCgYJCAAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Nordicpally:BAAALgADCgQJBAAAAA==.Notgim:BAAALgADCgYJBgAAAA==.',
Nu='Nubrac:BAAALgAECgcJCgAAAA==.',
Ny='Nylux:BAAALgAECgYJEwAAAA==.',
Ob='Oblivion:BAABLgAECn8kAAMDAAgJpyKKBgClAgADAAcJpyKKBgClAgAcAAEJAABLXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAAALgAECgYJDwAAAA==.Partyrocker:BAABLgAECn8UAAIXAAYJqBCTEABXAQAXAAYJqBCTEABXAQAAAA==.',
Pi='Pixae:BAABLgAECn8cAAIdAAYJjAt3DwAIAQAdAAYJjAt3DwAIAQAAAA==.Pixiechaos:BAAALgADCgUJEAABLgAECgEJAQAFAAAAAA==.',
Po='Poliahu:BAAALgADCgcJDQAAAA==.Powerplant:BAACLgAFFH8KAAISAAQJ1BoRBgB0AQASAAQJ1BoRBgB0AQAuAAQKfyYAAhIACQkaJOQDAMcCABIACQkaJOQDAMcCAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn8fAAIGAAgJwAfiGQA5AQAGAAgJwAfiGQA5AQAAAA==.',
Ra='Ragemonk:BAAALgAECgQJBgAAAA==.Ragetality:BAAALgADCgEJAQABLgAECgQJBgAFAAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Raserei:BAAALgADCgYJBwAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Ravara:BAAALgADCgYJBgABLgAECgcJFwAIAOocAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regicee:BAABLgAECn8eAAIeAAkJwx1oAgBFAgAeAAkJwx1oAgBFAgAAAA==.Retam:BAAALgADCgYJEQAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJAwAAAA==.Ripcord:BAAALgAECgQJBAAAAA==.Rizek:BAAALgAECgEJAQABLgAECgYJEAAFAAAAAA==.Rizzx:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.',
Ro='Rockdyou:BAABLgAECn8bAAIfAAgJRhukEwAcAgAfAAgJRhukEwAcAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.',
Ru='Rundvelt:BAABLgAECn8dAAILAAcJKRGCDQAnAQALAAcJKRGCDQAnAQAAAA==.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAABLgAECn8dAAIgAAcJTgtoEAAbAQAgAAcJTgtoEAAbAQAAAA==.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJBgAfAJUZAA==.',
Sk='Skoogz:BAAALgAECgcJBwAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAAALgAECgcJEwAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgADCggJFwAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8JAAMQAAQJAhbcAgDLAAAPAAMJkw3hEgDoAAAQAAMJlxbcAgDLAAAuAAQKfx4AAxAACAk/HlAGAJACABAABwm8IVAGAJACAA8AAQlOCXZhADYAAAAA.',
Sy='Sylaena:BAAALgAECgYJDAAAAA==.',
['Së']='Sërënity:BAAALgAECgQJBAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJBgAfAJUZAA==.',
Ta='Talipally:BAAALgAECgcJEgAAAA==.Taliwhacker:BAAALgADCgYJDQABLgAECgcJEgAFAAAAAA==.Talonleafgrd:BAAALgADCgYJBgAAAA==.Tanaka:BAAALgAECgYJCgAAAA==.Tanisong:BAAALgAECgEJAgAAAA==.Tassadar:BAAALgAECgEJAQAAAA==.',
Te='Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJBgAfAJUZAA==.',
Th='Thekingpunch:BAABLgAECn8WAAIOAAYJsCMQCAA3AgAOAAYJsCMQCAA3AgAAAA==.Thenle:BAAALgADCgYJBgAAAA==.Thunderblitz:BAABLgAECn8UAAITAAYJowbJKQD9AAATAAYJowbJKQD9AAAAAA==.Thurmus:BAAALgADCgkJHgAAAA==.',
Ti='Tillwar:BAABLgAECn8hAAIJAAgJIhMtDwDFAQAJAAgJIhMtDwDFAQAAAA==.',
To='Tofu:BAAALgAECgcJEwAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8YAAIUAAgJthAEHwCIAQAUAAgJthAEHwCIAQAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAAALgAECgYJEAAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8OAAIbAAQJeSHaBQCKAQAbAAQJeSHaBQCKAQAuAAQKfyMAAhsACAn9I7cHAPkCABsACAn9I7cHAPkCAAAA.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn8hAAIBAAgJIATgbwD5AAABAAgJIATgbwD5AAAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAAALgAECgYJBwAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgEJAQAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urownmother:BAAALgADCgUJBQABLgAECgcJEgAFAAAAAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAEBLgAECn8jAAMTAAgJHB01CQBEAgATAAgJHB01CQBEAgAHAAEJSgytRQEyAAAAAA==.Vanillaghost:BAAALgADCgIJAQAAAA==.',
Ve='Vearik:BAAALgADCgcJCwAAAA==.Velladoree:BAAALgAECgIJAgAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgADCgcJDAAFAAAAAA==.',
Wa='Waveygravee:BAAALgAECgEJAQAAAA==.Wavygraivy:BAAALgAECgIJAwAAAA==.',
We='Wedragon:BAAALgAECgQJCAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8KAAIfAAQJORtzEwBiAQAfAAQJORtzEwBiAQAuAAQKfxwAAh8ACAkRJFwSAA4DAB8ACAkRJFwSAA4DAAAA.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAUJDwAYABAcAA==.',
['Wå']='Wåsp:BAAALgADCgkJFwAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn8dAAIbAAcJAxirFQC8AQAbAAcJAxirFQC8AQABLgAECggJIwASAAMRAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAECgcJHgAZALQgAA==.Xrayl:BAABLgAECn8eAAMZAAcJtCB3CgDPAQAZAAYJvCF3CgDPAQAhAAEJjhvxTAA7AAAAAA==.',
Xz='Xzerocool:BAAALgAECgcJEgAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgIJAgAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgADCgMJAwAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAAALgAECgYJDQAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8UAAIBAAYJGhdQQABtAQABAAYJGhdQQABtAQAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAAALgAECgUJDgAAAA==.',
Zu='Zul:BAACLgAFFH8JAAIYAAMJNxT3DQAGAQAYAAMJNxT3DQAGAQAuAAQKfyYAAxgABwn2IgEGABsCABgABwn2IgEGABsCACIAAQnLAkEiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8VAAIYAAcJWB1cBgASAgAYAAcJWB1cBgASAgAAAA==.',
['Ða']='Ðamned:BAAALgAFFAEJAQABLgAFFAIJBgAfAJUZAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAISAAgJhA8EKgBtAQASAAgJhA8EKgBtAQAAAA==.',
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
