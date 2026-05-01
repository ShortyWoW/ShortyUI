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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Unknown-Unknown','Warlock-Destruction','Hunter-Marksmanship','Warrior-Fury','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Mage-Frost','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','DeathKnight-Unholy','Paladin-Holy','Hunter-Survival','Paladin-Retribution','Paladin-Protection','Monk-Windwalker','Druid-Feral','Druid-Guardian','DeathKnight-Blood','Priest-Discipline','Priest-Holy','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aalwein:BAABLgAECn8fAAIBAAgJ/BzjCwBDAgABAAgJ/BzjCwBDAgAAAA==.',
Ae='Aesculapius:BAABLgAECn8VAAICAAcJcRglEgD6AQACAAcJcRglEgD6AQAAAA==.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAAALgAECgMJBQAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Anonymus:BAAALgAFFAEJAQAAAA==.',
Ar='Ardwin:BAAALgADCgEJAQABLgAECgMJBwADAAAAAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAgAAAA==.',
Ba='Bambarrok:BAAALgAECgcJEgAAAA==.Bangan:BAAALgAECgEJAQAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgEJAQABLgAECgkJGQAEABkVAA==.Bepragosa:BAABLgAECn8ZAAIEAAkJGRWiCAA3AgAEAAkJGRWiCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgADCgcJEwAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECgcJDgADAAAAAA==.',
Bo='Bowguytome:BAAALgAECgcJDAABLgAECgkJIQAFAOkmAA==.',
Br='Brimscythe:BAAALgAECgEJAgAAAA==.Brownbelt:BAABLgAECn8aAAIGAAYJXRQNGgBfAQAGAAYJXRQNGgBfAQAAAA==.Brîn:BAAALgADCgcJDQAAAA==.',
Bu='Buteihunter:BAAALgAECggJEwAAAA==.',
Ca='Cadranak:BAABLgAECn8WAAIHAAgJcQzEVQCiAQAHAAgJcQzEVQCiAQAAAA==.Caiyenthi:BAABLgAECn8aAAIBAAgJMQ2aJQCDAQABAAgJMQ2aJQCDAQAAAA==.Calliesue:BAAALgADCgcJBwAAAA==.Camgor:BAAALgADCgEJAQABLgAECgMJBwADAAAAAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8UAAQGAAkJaRVqJQAtAgAGAAgJ/BZqJQAtAgAIAAQJLQnFEwDeAAAJAAEJBwjOKABAAAAAAA==.Chicharrone:BAAALgAECgYJDQAAAA==.Chizaru:BAAALgAECggJCgAAAA==.Chlorophyll:BAAALgADCgEJAQAAAA==.Chyntobelt:BAAALgAECgYJEQABLgAECgYJGgAGAF0UAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAAALgAECggJDwAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAAALgAECgQJBAAAAA==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAAALgADCgkJEAAAAA==.',
De='Deafenned:BAABLgAECn8ZAAIKAAkJcR6hPQCBAgAKAAkJcR6hPQCBAgAAAA==.Deaflynn:BAAALgAECgEJAQABLgAECgkJGQAKAHEeAA==.Deafnight:BAAALgAECgIJAgABLgAECgkJGQAKAHEeAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGQAEABkVAA==.Derrington:BAAALgAECgUJDwAAAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.',
Di='Diamante:BAABLgAECn8lAAILAAgJhxeKEwDRAQALAAgJhxeKEwDRAQAAAA==.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8dAAMMAAgJMQowGAA8AQAMAAgJMQowGAA8AQANAAQJBQJFMgCEAAAAAA==.Drellin:BAAALgAECgEJAwAAAA==.Dremu:BAABLgAECn8YAAMOAAYJxRw2EQCFAQAOAAYJxRw2EQCFAQACAAMJEw9YoACJAAAAAA==.',
Du='Duraz:BAABLgAECn8VAAICAAcJ7w8YTQBwAQACAAcJ7w8YTQBwAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJAwAAAA==.',
Eg='Eggar:BAAALgADCgYJDAABLgAECgYJGwAPAGsWAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAAALgAECgMJBwAAAA==.Elamaun:BAABLgAECn8aAAIQAAYJ/hK7HABlAQAQAAYJ/hK7HABlAQAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJBwAAAA==.',
En='English:BAAALgAECgcJDgAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAQAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Fa='Faelyna:BAABLgAECn8aAAIRAAYJvw09FAAqAQARAAYJvw09FAAqAQAAAA==.',
Fe='Felnut:BAAALgADCgEJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAABLgAECn8hAAISAAcJxCIOKQCBAgASAAcJxCIOKQCBAgAAAA==.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCggJCAAAAA==.',
Gl='Glabberghoul:BAABLgAECn8jAAIMAAkJ5RA3DgCoAQAMAAkJ5RA3DgCoAQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangmage:BAAALgAECgQJBQAAAA==.Griogair:BAAALgADCgYJEQABLgAECgMJBwADAAAAAA==.',
Ha='Hacelian:BAAALgADCgMJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwADAAAAAA==.Holyverdict:BAABLgAECn8XAAIQAAkJUSWbBQASAwAQAAkJUSWbBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8eAAILAAkJ7B0KFAB1AgALAAkJ7B0KFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Interval:BAAALgADCgcJDgABLgAECggJIAASAFkdAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAAALgAECgUJBQAAAA==.',
Je='Jeisa:BAAALgAECgUJDAAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgAAAA==.Kallotera:BAAALgAECgUJCwAAAA==.Kastoria:BAAALgADCgcJDAAAAA==.Katnipp:BAAALgAECggJEwAAAA==.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAAALgAECgQJBgAAAA==.',
Ke='Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8bAAIPAAYJaxb5OABWAQAPAAYJaxb5OABWAQAAAA==.',
Ki='Kiye:BAACLgAFFH8KAAIBAAQJNBGuDQBKAQABAAQJNBGuDQBKAQAuAAQKfygAAgEACQm8G3kPAL8CAAEACQm8G3kPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAAALgAECggJDwAAAA==.',
Ku='Kuuro:BAAALgAECgUJDgAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgUJBwAAAA==.Laughystabby:BAAALgADCgUJBQAAAA==.',
Le='Leibniz:BAAALgAECgUJCwAAAA==.Leisa:BAAALgAECgUJDQAAAA==.Lelwindae:BAAALgAECgQJBQAAAA==.',
Li='Lightgiver:BAAALgAECgUJBAAAAA==.Lighthoof:BAABLgAECn8fAAMSAAkJNh84FQDrAgASAAkJNh84FQDrAgATAAQJVBsXGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAOAAQJZQGNcgBXAAAAAA==.Liminara:BAEALgAFFAMJAwABLgAFFAUJBwABABwVAA==.Linaste:BAAALgADCgQJBAAAAA==.Lividzdk:BAABLgAECn8nAAIPAAcJ+iEvEQAyAgAPAAcJ+iEvEQAyAgAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAUAJwPAA==.',
Ly='Lynoia:BAAALgAECgUJBQAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn8YAAIGAAYJAAuyJgAKAQAGAAYJAAuyJgAKAQAAAA==.Mantequilla:BAABLgAECn8YAAIPAAcJTxy9SQAWAgAPAAcJTxy9SQAWAgAAAA==.Manthrax:BAABLgAECn8WAAILAAgJEAT+TQBLAQALAAgJEAT+TQBLAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.',
Mi='Missmolt:BAAALgAECgUJDgAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykara:BAAALgADCgYJBgAAAA==.Mykie:BAAALgADCgEJAQAAAA==.Mylor:BAABLgAECn8XAAMQAAgJBAzaNgCgAQAQAAgJBAzaNgCgAQASAAEJvw/0SAEwAAAAAA==.Myrddral:BAAALgAECgUJDQAAAA==.Mystifeyed:BAABLgAECn8dAAMVAAkJlQmOFgBQAQAVAAcJYgmOFgBQAQAWAAgJcQVjEQCjAAAAAA==.',
['Mü']='Mürsaat:BAAALgAECgYJEwAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAYJGwAXACMeAA==.Narra:BAAALgADCggJAwABLgADCgcJBwADAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQADAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn8kAAMYAAgJ/SNUAQAzAwAYAAgJciNUAQAzAwAZAAEJFCLycgBcAAAAAA==.Nimbledragon:BAAALgADCggJCgAAAA==.',
Nt='Ntayu:BAAALgAECgUJDgAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIPAAcJgxKPdQCaAQAPAAcJgxKPdQCaAQAAAA==.',
On='Onaga:BAAALgAECgQJBQAAAA==.',
Op='Opex:BAABLgAECn8aAAMBAAkJwQyfSACQAQABAAkJwQyfSACQAQAFAAEJUQBsmwATAAAAAA==.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECggJDwAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.',
Ph='Philomel:BAABLgAECn8cAAIHAAgJLBvQKwBPAgAHAAgJLBvQKwBPAgABLgAECgkJGQAKAHEeAA==.',
Pi='Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgADCgQJBAAAAA==.',
Pr='Priesthealz:BAAALgAECgEJAQABLgAECggJJgAaAKcdAA==.Pritt:BAAALgADCgcJDQABLgAECgYJDAADAAAAAA==.',
Qu='Quazu:BAAALgADCgEJAQAAAA==.',
Ra='Radagahst:BAAALgAECgUJCgAAAA==.Rarngorm:BAAALgAECgcJDQAAAA==.Ravinar:BAAALgAECgUJDAAAAA==.',
Re='Reardain:BAAALgAECgUJDQAAAA==.Received:BAAALgADCgkJDwAAAA==.Relia:BAABLgAECn8VAAMbAAkJ4g7HIQDJAQAbAAgJLw/HIQDJAQAYAAEJJgZONAA/AAAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Riverwind:BAAALgAECgUJCQAAAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAAALgAECgUJBwAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAAALgAECgYJDgAAAA==.Save:BAAALgAECgIJAwABLgAECggJHAAZAIgfAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIZAAkJ8hqdCwCXAgAZAAkJ8hqdCwCXAgAAAA==.Shallbedo:BAAALgAECgUJCQAAAA==.Shallvoker:BAABLgAECn8bAAMNAAgJCRroCgAtAgANAAgJPRboCgAtAgAMAAIJLhmSPgBXAAAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgADCgcJBwAAAA==.',
Si='Siatraler:BAAALgAECgcJDQAAAA==.Sigarette:BAACLgAFFH8bAAIXAAYJIx5JAQDVAQAXAAYJIx5JAQDVAQAuAAQKfzMAAhcACAnWJKUBAG8CABcACAnWJKUBAG8CAAAA.Silverspoon:BAAALgAECgIJAgAAAA==.Sinardi:BAABLgAECn8UAAIcAAYJugpKGADcAAAcAAYJugpKGADcAAAAAA==.',
Sk='Skoobz:BAAALgADCgEJAQAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAAALgAECgcJCAAAAA==.Skymane:BAAALgAECgYJEQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sovo:BAACLgAFFH8NAAIKAAQJ9Rm2FQBrAQAKAAQJ9Rm2FQBrAQAuAAQKfycAAgoACQlCIpIdAP8CAAoACQlCIpIdAP8CAAAA.',
Sq='Squshmepure:BAAALgAECgYJAQAAAA==.',
St='Starrin:BAAALgAECgUJDQAAAA==.Steaknquake:BAABLgAECn8aAAILAAYJWB56DgAJAgALAAYJWB56DgAJAgAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDQAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ2xgdOQDKAQABAAcJKhodOQDKAQAFAAUJ6wsKWQDhAAAAAA==.Sylvandel:BAAALgAECgUJDgAAAA==.',
Ta='Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn8kAAICAAgJKwZ9NAAGAQACAAgJKwZ9NAAGAQAAAA==.',
Th='Thalius:BAAALgAECgUJDgAAAA==.Thorandaal:BAAALgADCgkJEAAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQFAAkJ6SYDAAAZBAAFAAkJ3CYDAAAZBAARAAkJwyYIAAChAwABAAEJDyYucAByAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQAFAOkmAA==.Toomanydeths:BAABLgAECn8kAAMXAAgJ0w60DgAoAQAXAAgJ0w60DgAoAQAPAAEJqAh7IgExAAAAAA==.',
Tr='Trunx:BAAALgAECgEJAQABLgAECgkJGAAdAN8jAA==.',
Ty='Tye:BAAALgAECgQJBwAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJAwAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Ur='Ursusmanny:BAAALgAECgMJAwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Vandarin:BAAALgADCgYJEwABLgAECgMJBwADAAAAAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8kAAMeAAgJKyI+AQBhAgAeAAgJtCE+AQBhAgAfAAYJXSP+GAA9AgAAAA==.',
Ve='Velysa:BAAALgAECgYJEQAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8YAAMLAAkJwyAlCADyAgALAAkJwyAlCADyAgAgAAEJnhL3TAA6AAAAAA==.',
We='Weatherworn:BAAALgAECgYJEwAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAECgYJEwADAAAAAA==.Xerber:BAAALgADCgYJCgABLgAECgMJBwADAAAAAA==.',
Xi='Xiro:BAAALgAECgUJEAAAAA==.',
Yo='Yoril:BAAALgADCgQJBAAAAA==.',
Za='Zagiroth:BAABLgAECn8eAAMHAAgJOB13CQBCAgAHAAgJOB13CQBCAgAhAAEJFhtjJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgMJBwADAAAAAA==.',
Ze='Zebraman:BAAALgAECgcJDwAAAA==.Zeraida:BAAALgADCgcJDAAAAA==.',
['Zê']='Zêth:BAAALgADCgEJAQAAAA==.',
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
