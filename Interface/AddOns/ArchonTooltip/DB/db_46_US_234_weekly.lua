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

local lookup = {'Mage-Frost','Druid-Balance','Warlock-Demonology','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Druid-Restoration','Priest-Shadow','Paladin-Protection','Druid-Feral','Hunter-Survival','Rogue-Subtlety','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Restoration','Warlock-Destruction','Evoker-Preservation','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','Monk-Brewmaster','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ae='Aeidail:BAACLgAFFH8OAAIBAAUJQRnlEwB7AQABAAUJQRnlEwB7AQAuAAQKfyIAAgEACAnDID0cAAUDAAEACAnDID0cAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAAALgAECgMJBgAAAA==.',
Ag='Agraceful:BAABLgAECn8YAAICAAcJlw+CCQBWAQACAAcJlw+CCQBWAQAAAA==.',
Ai='Ailee:BAAALgAECgEJAQAAAA==.Aios:BAAALgADCgUJAwAAAA==.Aiza:BAABLgAECn8lAAMDAAgJ8RHrDQCkAQADAAgJ8RHrDQCkAQAEAAEJAAD0NwAdAAAAAA==.',
Al='Aldanil:BAAALgADCgMJAwAAAA==.',
An='Animalfriend:BAAALgADCgUJBQAAAA==.Anklesmasher:BAAALgAECgUJCQAAAA==.Anyah:BAAALgAECgEJAQAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Ar='Arfaz:BAAALgAECgQJCgAAAA==.Armbrost:BAAALgAECgYJBwAAAA==.Artimås:BAAALgADCgEJAQAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgADCgUJBQABLgAECgYJCwAFAAAAAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECggJHAADAGkiAA==.Astrastar:BAAALgAECgMJBAAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8ZAAIGAAcJbhMSBgC5AQAGAAcJbhMSBgC5AQAAAA==.',
Be='Beanutbutter:BAAALgADCgIJAgAAAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAAALgAECgMJBAAAAA==.Belwolf:BAAALgAECgIJAgAAAA==.Bergstrom:BAABLgAECn8aAAIHAAgJuRHoGABbAQAHAAgJuRHoGABbAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECggJHAADAGkiAA==.',
Bi='Bighero:BAABLgAECn8YAAIIAAcJwhJVbwBWAQAIAAcJwhJVbwBWAQAAAA==.',
Bl='Blakkjezus:BAAALgAECgQJBAAAAA==.Blitzbolts:BAAALgAECgEJAQAAAA==.Bludo:BAABLgAECn8bAAMJAAgJqx1uGQCAAgAJAAgJORluGQCAAgAKAAQJexdTGAA2AQAAAA==.',
Bo='Boe:BAAALgAECgUJCQAAAA==.Bombacløt:BAAALgAECgQJCwAAAA==.Bowdirte:BAAALgAECgUJBgAAAA==.',
Br='Brastin:BAAALgAECgcJEgABLgAECgcJGQALAC8aAA==.Brenell:BAABLgAECn8aAAIBAAgJXByuCAAdAgABAAgJXByuCAAdAgAAAA==.',
Bu='Buffet:BAAALgADCgYJCQABLgAECgcJFgAIANoaAA==.Buhlitz:BAAALgAECgEJAQAAAA==.',
By='Bynis:BAABLgAECn8UAAIIAAcJvxVpGwAnAQAIAAcJvxVpGwAnAQAAAA==.',
Ca='Cabëla:BAAALgADCgEJAQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.',
Ch='Choal:BAAALgAECgEJAQAAAA==.',
Ci='Cinnamongirl:BAAALgAECgYJCwAAAA==.',
Co='Corahin:BAABLgAECn8bAAILAAYJGRAhEAAJAQALAAYJGRAhEAAJAQAAAA==.Corious:BAAALgAECgIJAgAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.',
Cr='Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAAALgAECgYJDgAAAA==.',
Da='Dalren:BAACLgAFFH8KAAMMAAQJQBhVCwBDAQAMAAQJQBhVCwBDAQANAAEJuwNiCwBLAAAuAAQKfykAAwwACQkLJDcHAAcDAAwACQnHIzcHAAcDAA0ABgnyID4MABcCAAAA.Dalryn:BAAALgAECgIJBAABLgAFFAQJCgAMAEAYAA==.Dalvix:BAAALgADCgEJAQABLgAECgYJEwAFAAAAAA==.Damocles:BAAALgAECgYJDQAAAA==.Dartagnan:BAABLgAECn8dAAMOAAcJfhv/BQAdAQAOAAYJ9BT/BQAdAQAPAAQJ8x2tjwC7AAAAAA==.Darthmaul:BAAALgAECggJDgAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJFQAAAA==.Dendiian:BAAALgAECgQJBAAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgcJFgAIANoaAA==.Diem:BAAALgAECggJEgAAAA==.Dirtydotss:BAABLgAECn8VAAMEAAcJEgfaEgD/AAAEAAYJYQbaEgD/AAADAAYJ4QT1KwDbAAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAFAAAAAA==.Doregit:BAAALgAECgYJDgAAAA==.Dowedoes:BAABLgAECn8bAAIHAAgJBhOdEwCEAQAHAAgJBhOdEwCEAQAAAA==.',
Dr='Drachula:BAAALgAECgMJBAAAAA==.Dracultra:BAAALgAECgIJAgABLgAECgcJFQAQAL4gAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn8aAAIRAAcJegyeXQA5AQARAAcJegyeXQA5AQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAABLgAECn8aAAMRAAcJthGzXwAzAQARAAcJthGzXwAzAQACAAEJCggCIgA1AAAAAA==.',
['Dö']='Dönövan:BAAALgAECgUJCgAAAA==.',
El='Eloise:BAAALgADCgkJIwAAAA==.Elvenbane:BAABLgAECn8UAAISAAgJAQ2kBwB/AQASAAgJAQ2kBwB/AQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgUJCQAFAAAAAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Fa='Fabel:BAEBLgAECn8fAAITAAgJEyDWAABnAgATAAgJEyDWAABnAgABLgAECgkJBAAFAAAAAA==.Faltree:BAABLgAECn8cAAQRAAcJCBf6UwBXAQARAAYJFRb6UwBXAQACAAcJrxc8CwA6AQAUAAEJ3wFAOgAfAAAAAA==.Fathershale:BAAALgADCgMJAwAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAAALgAECgQJCgAAAA==.',
Fr='Freakadeek:BAAALgAECgUJBwABLgAECgUJDQAFAAAAAA==.Freâkadeek:BAAALgADCgkJCgABLgAECgUJDQAFAAAAAA==.Freäk:BAAALgADCgMJAwABLgAECgUJDQAFAAAAAA==.Frieren:BAABLgAECn8XAAIBAAcJ0A/8kwCrAQABAAcJ0A/8kwCrAQAAAA==.Frink:BAAALgADCgEJAQABLgAECggJGwAVAP0eAA==.',
Ga='Gabbyo:BAAALgAECgYJBwAAAA==.Galadorn:BAAALgAECgYJEwAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgADCgUJEAAAAA==.Garga:BAAALgADCgMJBAABLgADCgcJFAAFAAAAAA==.',
Ge='Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAAALgAECgQJBwAAAA==.',
Gh='Ghallow:BAAALgAECgMJAwAAAA==.Ghosty:BAABLgAECn8aAAIWAAcJSh+TFABuAgAWAAcJSh+TFABuAgAAAA==.',
Go='Goldenflame:BAAALgADCgcJCgAAAA==.Goldenlily:BAAALgAECgYJDQAAAA==.Goldenmunc:BAAALgAECgYJDQAAAA==.Goldenone:BAAALgAECgEJAQAAAA==.Goldenpants:BAAALgAECgYJDQAAAA==.',
Gr='Grievous:BAABLgAECn8bAAIXAAgJmCQ5AADOAgAXAAgJmCQ5AADOAgAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAAALgAECgYJDgAAAA==.Harusen:BAAALgAECgQJBwAAAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAECggJJwABAPUdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgEJAQAAAA==.Hornreaper:BAABLgAECn8bAAIMAAYJ5hfhJACVAQAMAAYJ5hfhJACVAQAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgEJAQABLgAECgcJEwAFAAAAAA==.Hurin:BAAALgAECgcJDgAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgQJBwAFAAAAAA==.Hyir:BAAALgADCgYJBwABLgAECggJKAAYAFgkAA==.',
Il='Illiya:BAAALgADCggJHQAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAAALgAECgcJEwAAAA==.',
Je='Jek:BAAALgAECgEJAQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ka='Kaevrielle:BAEALgAECgcJEgAAAA==.Kaison:BAAALgADCgEJAQABLgAECgcJFAAIAL8VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAUJDgABAEEZAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAAALgAECgYJDQAAAA==.Katakuri:BAAALgAECgEJAQAAAA==.',
Ke='Keeper:BAAALgAECgUJBgABLgAECggJJAAHAEQiAA==.Keeperodark:BAAALgAECgcJCAABLgAECggJJAAHAEQiAA==.Keeperolight:BAABLgAECn8kAAMHAAgJRCJoDwATAwAHAAgJRCJoDwATAwAQAAEJgRj+jwBAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECggJFAASAAENAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAAALgAECgYJDgAAAA==.',
Ko='Kodera:BAAALgAECgQJCgAAAA==.Koojo:BAAALgADCgQJBQAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAECgYJCgAAAA==.Larew:BAAALgAECgUJCwAAAA==.Lazytemplar:BAAALgADCgMJAwABLgAECgIJAgAFAAAAAA==.',
Le='Lealla:BAABLgAECn8bAAICAAgJhxoZAwAKAgACAAgJhxoZAwAKAgAAAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8FAAMOAAQJ1wbtBQCRAAAPAAIJ4wYAGgCeAAAOAAMJEwbtBQCRAAAuAAQKfyIAAw4ACAl3G9IhABQCAA4ACAkBFtIhABQCAA8AAgk+JFCHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgEJAQABLgAECggJIAAZAFYjAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgQJBQAAAA==.',
Lo='Loganshu:BAAALgADCgcJEgAAAA==.Lokan:BAABLgAECn8cAAIVAAcJdRszAwDTAQAVAAcJdRszAwDTAQAAAA==.Lots:BAABLgAECn8hAAMDAAcJwCMWCwDEAQADAAYJYyQWCwDEAQAaAAQJxh5GLAANAQAAAA==.',
Lu='Ludafists:BAAALgADCgYJBgAAAA==.Ludakris:BAAALgAECgYJCwAAAA==.Lumanoth:BAAALgADCgEJAQAAAA==.',
Ly='Lyna:BAABLgAECn8VAAIZAAcJHhQERwBlAQAZAAcJHhQERwBlAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAAALgAECgQJCAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8IAAIBAAQJ4xaOGABoAQABAAQJ4xaOGABoAQAuAAQKfxcAAgEACAmfJT8hAO4CAAEACAmfJT8hAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAFAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Mahina:BAAALgADCgYJGQAAAA==.Marcille:BAABLgAECn8ZAAIBAAcJkRIchgDFAQABAAcJkRIchgDFAQAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn8fAAMPAAgJLRk4CADlAQAPAAgJLRk4CADlAQAOAAEJZACSmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn8bAAIVAAgJ/R6jAQAuAgAVAAgJ/R6jAQAuAgAAAA==.',
Me='Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAAALgAECgQJBwAAAA==.',
Mi='Minerwor:BAAALgAECgEJAQAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn8ZAAICAAYJrgyUDgAJAQACAAYJrgyUDgAJAQAAAA==.',
Mo='Moarthretplz:BAAALgADCgUJBQABLgAECggJIAAZAFYjAA==.Momometaru:BAAALgAECgUJDAAAAA==.Monsterbee:BAABLgAECn8dAAIDAAcJOA3QFABpAQADAAcJOA3QFABpAQAAAA==.',
Mu='Mustypizza:BAAALgAECgYJDgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn8bAAMbAAgJjhsNAQB1AgAbAAgJjhsNAQB1AgANAAEJehbROwA+AAAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECgQJBAAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgEJAQAAAA==.',
Na='Narashi:BAAALgADCgIJAwAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8bAAIZAAcJLRKpOACgAQAZAAcJLRKpOACgAQAAAA==.',
Ne='Neameny:BAABLgAECn8bAAIPAAgJ0RAfCgDHAQAPAAgJ0RAfCgDHAQAAAA==.',
Ni='Nianji:BAAALgADCgYJCAAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Nordicpally:BAAALgADCgQJBAAAAA==.',
Nu='Nubrac:BAAALgAECgMJAwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn8cAAMDAAgJaSKHAgB8AgADAAcJaSKHAgB8AgAaAAEJAABCXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgcJEwAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAAALgAECgUJDQAAAA==.Partyrocker:BAAALgAECgUJDQAAAA==.',
Pi='Pixae:BAABLgAECn8bAAIbAAYJjAvXBgAfAQAbAAYJjAvXBgAfAQAAAA==.Pixiechaos:BAAALgADCgUJEAABLgADCgYJEQAFAAAAAA==.',
Po='Poliahu:BAAALgADCgcJBwAAAA==.Powerplant:BAACLgAFFH8GAAIPAAQJOxGkBAA1AQAPAAQJOxGkBAA1AQAuAAQKfyIAAg8ACAk1JCgIAA4DAA8ACAk1JCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn8XAAIGAAgJ+Qa+CwA4AQAGAAgJ+Qa+CwA4AQAAAA==.',
Ra='Ragemonk:BAAALgAECgIJAgAAAA==.Ragetality:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Raserei:BAAALgADCgEJAQAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Ravara:BAAALgADCgYJBgABLgAECgYJEwAFAAAAAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regicee:BAABLgAECn8ZAAIcAAgJMxzSAQAaAgAcAAgJMxzSAQAaAgAAAA==.Retam:BAAALgADCgYJCwAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJAQAAAA==.Rizek:BAAALgAECgEJAQABLgAECgUJCQAFAAAAAA==.',
Ro='Rockdyou:BAABLgAECn8XAAIdAAcJSRwrBwAOAgAdAAcJSRwrBwAOAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.',
Ru='Rundvelt:BAABLgAECn8cAAITAAcJKRFPBgAsAQATAAcJKRFPBgAsAQAAAA==.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sapkick:BAAALgAECgEJAwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shadeabel:BAEALgAECgkJBAAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAABLgAECn8cAAIeAAcJRAtnBwAgAQAeAAcJRAtnBwAgAQAAAA==.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAECggJFQAdAFUhAA==.',
Sk='Skoogz:BAAALgAECgcJBAAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAAALgAECgcJEwAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgADCgcJEAAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8GAAMMAAQJRArdEgDoAAAMAAMJkw3dEgDoAAANAAIJnQKdBwB2AAAuAAQKfxoAAw0ACAk/HlEGAJACAA0ABwm8IVEGAJACAAwAAQlOCW1hADYAAAAA.',
['Së']='Sërënity:BAAALgAECgEJAQAAAA==.',
['Sí']='Sín:BAAALgAECgcJCAABLgAECggJFQAdAFUhAA==.',
Ta='Talipally:BAAALgAECgYJDwAAAA==.Taliwhacker:BAAALgADCgQJCAAAAA==.Talonleafgrd:BAAALgADCgYJBgAAAA==.Tanaka:BAAALgAECgUJBQAAAA==.Tanisong:BAAALgAECgEJAQAAAA==.Tassadar:BAAALgAECgEJAQAAAA==.',
Te='Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAECggJFQAdAFUhAA==.',
Th='Thekingpunch:BAAALgAECgUJEAAAAA==.Thunderblitz:BAAALgAECgYJDwAAAA==.Thurmus:BAAALgADCgkJFQAAAA==.',
Ti='Tillwar:BAABLgAECn8ZAAIJAAgJhBEfTQBxAQAJAAgJhBEfTQBxAQAAAA==.',
To='Tofu:BAAALgAECgYJEgAAAA==.',
Tr='Treibh:BAABLgAECn8YAAIRAAgJthC3CwCaAQARAAgJthC3CwCaAQAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAAALgAECgYJCgAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8KAAIZAAQJeCGrAQCQAQAZAAQJeCGrAQCQAQAuAAQKfyIAAhkACAn9I7UHAPkCABkACAn9I7UHAPkCAAAA.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn8dAAIBAAgJjwM/LgARAQABAAgJjwM/LgARAQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAAALgAECgEJAQAAAA==.',
['Tî']='Tîlldeath:BAAALgADCgEJAQAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urownmother:BAAALgADCgUJBQABLgAECgYJCwAFAAAAAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAEBLgAECn8iAAMQAAgJHB1OAwBRAgAQAAgJHB1OAwBRAgAHAAEJSgyGRQEyAAAAAA==.Vanillaghost:BAAALgADCgIJAQAAAA==.',
Ve='Vearik:BAAALgADCgUJBQAAAA==.Velladoree:BAAALgAECgIJAgAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgADCgcJDAAFAAAAAA==.',
Wa='Waveygravee:BAAALgADCgcJFQAAAA==.Wavygraivy:BAAALgAECgEJAQAAAA==.',
We='Wedragon:BAAALgAECgQJCAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8HAAIdAAQJlRl7DwD8AAAdAAQJlRl7DwD8AAAuAAQKfxsAAh0ACAnrI1USAA4DAB0ACAnrI1USAA4DAAAA.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAMJCgAWANAUAA==.',
['Wå']='Wåsp:BAAALgADCgkJDwAAAA==.',
Xb='Xb:BAAALgAECgcJAgAAAA==.',
Xh='Xhexana:BAABLgAECn8XAAIZAAcJdhUAPgCJAQAZAAcJdhUAPgCJAQABLgAECggJGwAPANEQAA==.',
Xr='Xrayl:BAABLgAECn8dAAMYAAcJtCDFAwDTAQAYAAYJvCHFAwDTAQAfAAEJjhucIgA/AAAAAA==.',
Xz='Xzerocool:BAAALgAECgYJCwAAAA==.',
Ya='Yannii:BAAALgADCgUJCAAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgADCgcJEwAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAAALgAECgYJBwAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAAALgAECgYJDwAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAAALgAECgQJCwAAAA==.',
Zu='Zul:BAACLgAFFH8GAAIWAAMJHQ+LBgD8AAAWAAMJHQ+LBgD8AAAuAAQKfyQAAxYABwn2ImQCABUCABYABwn2ImQCABUCACAAAQnLAj4iACQAAAAA.',
Zy='Zykoz:BAAALgAECgYJDgAAAA==.',
['Ða']='Ðamned:BAAALgAECgYJDgABLgAECggJFQAdAFUhAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8ZAAIPAAYJKxLOGQAuAQAPAAYJKxLOGQAuAQAAAA==.',
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
