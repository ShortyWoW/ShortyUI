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

local lookup = {'Mage-Frost','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Blood','Unknown-Unknown','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Druid-Restoration','Priest-Shadow','Druid-Feral','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Warrior-Protection','Monk-Brewmaster','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ae='Aeidail:BAACLgAFFH8WAAIBAAUJmRr1EwB7AQABAAUJmRr1EwB7AQAuAAQKfyQAAgEACAmnI0AcAAUDAAEACAmnI0AcAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAAALgAECgYJEAAAAA==.',
Ag='Agraceful:BAABLgAECn8bAAICAAgJoBErFQCWAQACAAgJoBErFQCWAQAAAA==.',
Ai='Ailee:BAAALgAECgIJAwAAAA==.Aios:BAAALgADCgcJCQAAAA==.Aiza:BAACLgAFFH8HAAIDAAMJYQQ4TgC4AAADAAMJYQQ4TgC4AAAuAAQKfykAAwMACAkBEj0zAJcBAAMACAkBEj0zAJcBAAQAAQkAAPM3AB0AAAAA.',
Al='Aldanil:BAAALgADCgMJAwAAAA==.',
An='Animalfriend:BAAALgADCgUJBQAAAA==.Anklesmasher:BAAALgAECgUJCQAAAA==.Anyah:BAAALgAECgQJCAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Ar='Arfaz:BAABLgAECn8XAAMFAAUJBhUBbQAIAQAFAAUJBhUBbQAIAQAGAAMJoARXNQBAAAAAAA==.Armbrost:BAAALgAECgYJCAAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECggJDgAHAAAAAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECgkJLQADANQjAA==.Astrastar:BAAALgAECgUJDAAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAIIAAcJZhNSFwCXAQAIAAcJZhNSFwCXAQAAAA==.Barlz:BAAALgADCgMJAwAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAECgcJHgAFAEYbAA==.Beanutbutter:BAAALgADCgIJAgABLgAECgcJHgAFAEYbAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAAALgAECgYJCwAAAA==.Belonara:BAAALgADCgIJAgAAAA==.Belwolf:BAAALgAECgIJBQAAAA==.Bergstrom:BAABLgAECn8qAAIJAAgJ3BrBGgAoAgAJAAgJ3BrBGgAoAgAAAA==.Betrayer:BAAALgADCgQJAwABLgAECgkJLQADANQjAA==.',
Bi='Biancaneve:BAAALgADCgIJAgAAAA==.Bighero:BAABLgAECn8aAAIKAAcJERNYbwBWAQAKAAcJERNYbwBWAQAAAA==.',
Bl='Blakkjezus:BAAALgAECgQJBQAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8IAAMLAAQJohIwGgDkAAALAAQJlAwwGgDkAAAMAAEJTxsKFwBXAAAuAAQKfx4AAwsACQl6IWYZAIACAAsACAk5GWYZAIACAAwABgl9HFQYADYBAAAA.',
Bo='Boe:BAABLgAECn8VAAINAAYJmARDEgDcAAANAAYJmARDEgDcAAAAAA==.Bombacløt:BAABLgAECn8YAAMOAAcJbQ78CQA2AQAOAAcJbQ78CQA2AQADAAQJQAiXjACrAAAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn8gAAIPAAgJ0B3gAwBYAgAPAAgJ0B3gAwBYAgABLgAECggJIAAQAOAcAA==.Brenell:BAABLgAECn8qAAIBAAkJxiADCgDWAgABAAkJxiADCgDWAgAAAA==.',
Bu='Buffet:BAAALgAECgQJBAABLgAECgkJHQAKAEwYAA==.Buhlitz:BAAALgAECgEJAgAAAA==.',
By='Bynis:BAABLgAECn8dAAIKAAgJ5hMsMwBoAQAKAAgJ5hMsMwBoAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.',
Ch='Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIQAAYJGxBELgD8AAAQAAYJGxBELgD8AAAAAA==.Corious:BAAALgAECgQJBQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.',
Cr='Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8dAAIRAAgJZSXMAADiAgARAAgJZSXMAADiAgAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgYJHAASAPMjAA==.Dalren:BAACLgAFFH8QAAMTAAQJRx70CwB1AQATAAQJRx70CwB1AQAUAAEJuwNlCwBLAAAuAAQKfzUAAxMACQkqJdAEAKgCABMACQnnJNAEAKgCABQABgnyIEAMABcCAAAA.Dalryn:BAAALgAECgYJCwABLgAFFAQJEAATAEceAA==.Dalvix:BAAALgADCgEJAQABLgAECgcJHAAKAAoeAA==.Damocles:BAAALgAECgYJEAAAAA==.Dartagnan:BAABLgAECn8eAAMVAAcJqRxNDwD4AAAVAAYJ9xRNDwD4AAAWAAUJLh4+fQChAAAAAA==.Darthmaul:BAABLgAECn8fAAICAAkJjw8yDwDdAQACAAkJjw8yDwDdAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJIwAAAA==.Dendiian:BAAALgAECgYJDwAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgkJHQAKAEwYAA==.Diem:BAABLgAECn8YAAIWAAgJyw1OMACMAQAWAAgJyw1OMACMAQAAAA==.Dirtydotss:BAABLgAECn8VAAMEAAcJFwfYEgD/AAAEAAYJYQbYEgD/AAADAAYJ5wT3fADNAAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAHAAAAAA==.Doregit:BAABLgAECn8bAAILAAcJBB1jDgAIAgALAAcJBB1jDgAIAgAAAA==.Dowedoes:BAABLgAECn8sAAIJAAkJDhMDIQAEAgAJAAkJDhMDIQAEAgAAAA==.',
Dr='Drachula:BAAALgAECgUJDAAAAA==.Dracultra:BAAALgAECgIJAgABLgAECgkJIAAXAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn8nAAIYAAkJeA62JwCRAQAYAAkJeA62JwCRAQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAABLgAECn8dAAMYAAcJthGzXwAzAQAYAAcJthGzXwAzAQACAAIJNApBSQBcAAAAAA==.',
['Dö']='Dönövan:BAABLgAECn8XAAIJAAcJJg/tTABfAQAJAAcJJg/tTABfAQAAAA==.',
El='Eloise:BAAALgAECgQJBAAAAA==.Elvenbane:BAABLgAECn8dAAIZAAkJSQ51EADKAQAZAAkJSQ51EADKAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgYJEAAHAAAAAA==.',
En='Enable:BAAALgAFFAEJAQAAAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Fa='Fabel:BAABLgAECn8nAAIPAAgJTyJYAgCWAgAPAAgJTyJYAgCWAgABLgAFFAEJAQAHAAAAAA==.Falahad:BAAALgAECgEJAQABLgAECgcJHgAYAPEYAA==.Faltree:BAABLgAECn8eAAQYAAcJ8Rj4UwBXAQAYAAYJTxj4UwBXAQACAAcJfhgTIAA2AQAaAAEJ3wFIOgAfAAAAAA==.Fathershale:BAAALgADCgQJBAAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8VAAMXAAgJoB9wKABJAQAXAAcJJB9wKABJAQAJAAYJ5xAqYAAuAQAAAA==.',
Fr='Freakadeek:BAAALgAECgcJDAABLgAECgcJFgAbAGoOAA==.Freâkadeek:BAAALgAECgIJAgABLgAECgcJFgAbAGoOAA==.Freäk:BAAALgADCgMJAwABLgAECgcJFgAbAGoOAA==.Frieren:BAABLgAECn8mAAIBAAgJEhP0OgC3AQABAAgJEhP0OgC3AQAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJLAAbABchAA==.',
Fu='Fundetected:BAAALgADCgYJBgABLgAECgkJHQAKAEwYAA==.',
Ga='Gabbyo:BAAALgAECgYJEwAAAA==.Galadorn:BAABLgAECn8cAAIKAAcJCh4RFgALAgAKAAcJCh4RFgALAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJBwAAAA==.Garga:BAAALgADCgMJBAABLgADCgkJHAAHAAAAAA==.',
Ge='Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAAALgAECgYJEAAAAA==.',
Gh='Ghallow:BAAALgAECgQJCgAAAA==.Ghosty:BAACLgAFFH8JAAIcAAQJOxViCwBTAQAcAAQJOxViCwBTAQAuAAQKfx4AAhwABwlBII8UAG4CABwABwlBII8UAG4CAAAA.',
Gi='Gimp:BAAALgAECgEJAQAAAA==.',
Gl='Gladur:BAAALgADCgEJAQABLgAFFAUJFgABAJkaAA==.',
Go='Goldenflame:BAAALgAECgUJBQAAAA==.Goldenlily:BAAALgAECgYJEQAAAA==.Goldenmunc:BAABLgAECn8cAAIBAAgJZxJZOQC9AQABAAgJZxJZOQC9AQAAAA==.Goldenone:BAAALgAECgEJAQAAAA==.Goldenpants:BAABLgAECn8WAAILAAgJ8hC5FwCpAQALAAgJ8hC5FwCpAQAAAA==.',
Gr='Grievous:BAABLgAECn8sAAIRAAkJ2CQzAABUAwARAAkJ2CQzAABUAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8WAAIIAAgJFSMMAwAAAwAIAAgJFSMMAwAAAwAAAA==.Harusen:BAABLgAECn8WAAIdAAgJMR6QAQBYAgAdAAgJMR6QAQBYAgAAAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAIJBQABAAMcAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAITAAYJ5hfmJACVAQATAAYJ5hfmJACVAQAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgEJAQABLgAECggJIQAYAP8bAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECggJFgAdADEeAA==.Hyir:BAAALgADCgYJBwABLgAFFAMJBQAeADsWAA==.',
Il='Illiya:BAAALgAECgMJBAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJBgAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn8jAAQQAAkJTw5wEwC8AQAQAAkJTw5wEwC8AQANAAYJ9we5GgAeAQAfAAcJ5AZiPAATAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgYJBgABLgAECgkJHQAKAEwYAA==.',
Ka='Kaevrielle:BAEBLgAECn8eAAMRAAkJjBvUAgA9AgARAAkJjBvUAgA9AgAgAAEJVgpdQwAwAAAAAA==.Kaison:BAAALgADCgQJBAABLgAECggJHQAKAOYTAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAUJFgABAJkaAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAABLgAECn8XAAIBAAYJ2BW8XgBVAQABAAYJ2BW8XgBVAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgUJBwABLgAECggJNQAJANAkAA==.Keeperodark:BAAALgAECggJEAABLgAECggJNQAJANAkAA==.Keeperolight:BAABLgAECn81AAMJAAgJ0CQLBwDfAgAJAAgJ0CQLBwDfAgAXAAEJgRgPkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECgkJHQAZAEkOAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8dAAIBAAgJNhTzOAC/AQABAAgJNhTzOAC/AQAAAA==.',
Ko='Kodera:BAAALgAECgUJEwAAAA==.Koojo:BAAALgADCgQJBQAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAHAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAECggJDQAAAA==.Larew:BAABLgAECn8XAAIJAAYJZRZPUABVAQAJAAYJZRZPUABVAQAAAA==.Lazytemplar:BAAALgADCgMJAwABLgAECgUJCwAHAAAAAA==.',
Le='Lealla:BAABLgAECn8sAAICAAkJuB6rAwDJAgACAAkJuB6rAwDJAgAAAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8LAAMVAAQJ/gzPCQAkAQAVAAQJ/gzPCQAkAQAWAAIJ4wYMGgCeAAAuAAQKfyYAAxUACQkFHWohABsCABUACQmYGGohABsCABYAAgk+JFCHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgEJAQABLgAFFAIJBwAfAHImAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJCwAAAA==.',
Lo='Loganshu:BAAALgADCgcJEgAAAA==.Lokan:BAABLgAECn8eAAIbAAcJ/RzsDADWAQAbAAcJ/RzsDADWAQAAAA==.Lots:BAABLgAECn8jAAMDAAcJyyOCLwBPAgADAAYJaSSCLwBPAgAOAAQJ3h5GLAANAQAAAA==.',
Lu='Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8YAAIPAAgJCBjmBgDuAQAPAAgJCBjmBgDuAQAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIfAAkJpRNnHQDGAQAfAAkJpRNnHQDGAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8UAAMXAAYJ+BlaKQBCAQAXAAYJ+BlaKQBCAQAJAAEJQwSiVQEoAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhp+DQC8AQABAAYJBhp+DQC8AQAuAAQKfxcAAgEACAmfJUIhAO4CAAEACAmfJUIhAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAHAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Mahina:BAAALgAECgIJAgAAAA==.Marcille:BAABLgAECn8bAAIBAAcJYRMEhgDFAQABAAcJYRMEhgDFAQAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn8yAAMWAAkJ0Rk+DAB9AgAWAAkJ0Rk+DAB9AgAVAAEJZACkmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn8sAAIbAAkJFyF2AQAAAwAbAAkJFyF2AQAAAwAAAA==.',
Me='Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAAALgAECggJEQAAAA==.',
Mi='Minerwor:BAAALgAECgIJAwAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn8qAAICAAkJSA+BDwDZAQACAAkJSA+BDwDZAQAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAIJBwAfAHImAA==.Mohji:BAAALgAFFAEJAQABLgAFFAYJFQAhAKcUAA==.Momometaru:BAABLgAECn8bAAQDAAgJEBTLJgDNAQADAAgJIhPLJgDNAQAOAAUJNhRwJgAsAQAEAAEJPBgFFQBHAAAAAA==.Monsterbee:BAABLgAECn8tAAIDAAgJBA9nMgCaAQADAAgJBA9nMgCaAQAAAA==.',
Mu='Mustypizza:BAABLgAECn8dAAIOAAgJihUTBADRAQAOAAgJihUTBADRAQAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn8sAAMiAAkJyx5/AQAdAwAiAAkJyx5/AQAdAwAUAAMJxRH7DQCtAAAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Narashi:BAAALgAECgQJBAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8iAAIfAAgJSxGlLgBYAQAfAAgJSxGlLgBYAQAAAA==.',
Ne='Neameny:BAABLgAECn8sAAIWAAkJWRD4GwD1AQAWAAkJWRD4GwD1AQAAAA==.',
Ni='Nianji:BAAALgADCgYJCwAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgQJBAAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgEJAQAAAA==.Nubrac:BAAALgAECggJCwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn8tAAMDAAkJ1CPhAgArAwADAAkJ1CPhAgArAwAOAAEJAABIXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8XAAIQAAgJVQ/RGQCBAQAQAAgJVQ/RGQCBAQAAAA==.Partyrocker:BAABLgAECn8WAAIbAAcJag5rEwB/AQAbAAcJag5rEwB/AQAAAA==.',
Pi='Pixae:BAABLgAECn8dAAIiAAYJmgsAFAAAAQAiAAYJmgsAFAAAAQAAAA==.Pixiechaos:BAAALgADCgYJEgABLgAECgEJAQAHAAAAAA==.',
Po='Poliahu:BAAALgADCggJDgAAAA==.Porthoss:BAAALgADCgcJBwAAAA==.Powerplant:BAACLgAFFH8OAAIWAAQJbCKRBQCQAQAWAAQJbCKRBQCQAQAuAAQKfyYAAhYACQkcJCkIAA4DABYACQkcJCkIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn8oAAIIAAkJMwwwFgCiAQAIAAkJMwwwFgCiAQAAAA==.',
Ra='Ragemonk:BAAALgAECgUJCwAAAA==.Ragetality:BAAALgADCgEJAQABLgAECgUJCwAHAAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Raserei:BAAALgADCgYJBwAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Ravara:BAAALgADCgYJBgABLgAECgcJHAAKAAoeAA==.Rayné:BAAALgADCgMJAwAAAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regice:BAAALgAECgcJBwABLgAECgkJIgAGAKQeAA==.Regicee:BAABLgAECn8iAAMGAAkJpB4lAwCpAgAGAAkJpB4lAwCpAgAFAAEJ1Qd65AA3AAAAAA==.Retam:BAAALgADCgYJEQAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJAwAAAA==.Ripcord:BAAALgAECgUJCAAAAA==.Rizek:BAAALgAECgIJAgABLgAECgYJEAAHAAAAAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8fAAIFAAgJlRxZHQAYAgAFAAgJlRxZHQAYAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAAALgAECgUJBwAAAA==.',
Ru='Rundvelt:BAABLgAECn8eAAIPAAcJOhH7EQAgAQAPAAcJOhH7EQAgAQAAAA==.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgEJAQAAAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAABLgAECn8eAAIjAAcJsQvlFQAWAQAjAAcJsQvlFQAWAQAAAA==.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJBgAFAJUZAA==.',
Sk='Skoogz:BAAALgAECgkJCAAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQeAAcJyRkpLwBtAQAeAAYJCxYpLwBtAQAkAAYJrhzmOABmAQASAAEJUwKHYwAfAAAAAA==.Soulfulgingr:BAAALgADCgIJAgAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgIJAgAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8NAAMUAAQJfRcwBADFAAATAAQJvQvmEgDoAAAUAAMJmRYwBADFAAAuAAQKfyYAAxQACAkpIVEGAJACABQABwm8IVEGAJACABMAAwnxHI88AKsAAAAA.',
Sy='Sylaena:BAAALgAECgYJDAAAAA==.',
['Së']='Sërënity:BAAALgAECgQJCAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJBgAFAJUZAA==.',
Ta='Talipally:BAABLgAECn8UAAIJAAgJ1w84fwB7AQAJAAgJ1w84fwB7AQAAAA==.Taliwhacker:BAAALgADCgYJDQABLgAECggJFAAJANcPAA==.Talonleafgrd:BAAALgADCgYJBgAAAA==.Tanaka:BAAALgAECgcJEQAAAA==.Tanisong:BAAALgAECgEJAgAAAA==.Tassadar:BAAALgAECgEJAQAAAA==.',
Te='Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJBgAFAJUZAA==.',
Th='Thekingpunch:BAABLgAECn8cAAISAAYJ8yNCCQBdAgASAAYJ8yNCCQBdAgAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thunderblitz:BAABLgAECn8bAAIXAAcJPggqKgA9AQAXAAcJPggqKgA9AQAAAA==.Thurmus:BAAALgADCgkJIwAAAA==.',
Ti='Tillwar:BAABLgAECn8qAAILAAkJ2BhwBwB2AgALAAkJ2BhwBwB2AgAAAA==.',
To='Tofu:BAABLgAECn8bAAIFAAgJIBQZJgDoAQAFAAgJIBQZJgDoAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8YAAIYAAgJuxBiKwB7AQAYAAgJuxBiKwB7AQAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8XAAIWAAcJPw34OwBdAQAWAAcJPw34OwBdAQAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8SAAIfAAQJ7iFeCQCHAQAfAAQJ7iFeCQCHAQAuAAQKfyUAAh8ACQkrJLkHAPkCAB8ACQkrJLkHAPkCAAAA.Tukkit:BAAALgAECgMJAwAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn8rAAIBAAgJwQTSbgAzAQABAAgJwQTSbgAzAQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAAALgAECgcJCQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgIJAgAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFQAJAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFQAJAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8FAAMXAAMJDxdFIwCHAAAXAAIJzw9FIwCHAAAJAAEJawJ3YQBFAAAuAAQKfyQAAxcACAkaHTAWAF8CABcACAkaHTAWAF8CAAkAAgnbCadFATIAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.',
Ve='Vearik:BAAALgADCgcJCwAAAA==.Velladoree:BAAALgAECgQJBQAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgADCgcJDAAHAAAAAA==.',
Wa='Waveygravee:BAAALgAECgIJAwAAAA==.Wavygraivy:BAAALgAECgIJAwAAAA==.',
We='Wedragon:BAAALgAECgQJCAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8KAAIFAAQJOxuCJgBSAQAFAAQJOxuCJgBSAQAuAAQKfxwAAgUACAkSJFkSAA4DAAUACAkSJFkSAA4DAAAA.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAUJFAAcALUgAA==.',
['Wå']='Wåsp:BAAALgADCgkJHAAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn8lAAIfAAgJXBUcFgACAgAfAAgJXBUcFgACAgABLgAECgkJLAAWAFkQAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJBgAeAKMYAA==.Xrayl:BAACLgAFFH8GAAMeAAMJoxgvFAC1AAAeAAIJ7B0vFAC1AAAkAAEJEA5COwBEAAAuAAQKfx8AAx4ABwm3IFoOANMBAB4ABgm/IVoOANMBACQAAQmOG/1gADsAAAAA.',
Xz='Xzerocool:BAABLgAECn8VAAQJAAgJvRNTOwCUAQAJAAgJvRNTOwCUAQAPAAIJsBPRJABwAAAXAAEJmQMraAAqAAAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgMJAwAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgADCgMJAwAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8VAAIUAAgJHBC+BACkAQAUAAgJHBC+BACkAQAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8YAAIBAAcJYxcHPQCxAQABAAcJYxcHPQCxAQAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn8YAAICAAUJYQvyNgCwAAACAAUJYQvyNgCwAAAAAA==.',
Zu='Zul:BAACLgAFFH8MAAIcAAMJpB8hEAAkAQAcAAMJpB8hEAAkAQAuAAQKfycAAxwABwn2IgcMANcCABwABwn2IgcMANcCACUAAQnLAkEiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8dAAIcAAgJYR+YBAB/AgAcAAgJYR+YBAB/AgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8UAAIQAAYJ8htwIwA4AQAQAAYJ8htwIwA4AQABLgAFFAIJBgAFAJUZAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIWAAgJhQ8kPQBZAQAWAAgJhQ8kPQBZAQAAAA==.',
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
