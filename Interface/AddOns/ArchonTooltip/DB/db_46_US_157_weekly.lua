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

local lookup = {'Priest-Shadow','Unknown-Unknown','Mage-Frost','Priest-Discipline','DeathKnight-Blood','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','DeathKnight-Unholy','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Shaman-Restoration','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Druid-Restoration','Druid-Balance','Mage-Arcane','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Preservation','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaralia:BAABLgAECn8cAAIBAAgJjh3kEgBfAgABAAgJjh3kEgBfAgAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ad='Adarae:BAAALgAECgMJBAAAAA==.Ademal:BAAALgADCgUJBQAAAA==.Adic:BAAALgAECgMJAwAAAA==.',
Ae='Aeria:BAAALgAECgEJAQAAAA==.Aerwen:BAAALgAECgYJCgAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgYJCwACAAAAAA==.',
Al='Alarielle:BAAALgAECgQJBAABLgAECgYJFQADACoPAA==.Alearia:BAAALgADCgEJAQAAAA==.Alewynt:BAAALgAECgEJAgAAAA==.Altiv:BAAALgAECgQJBAAAAA==.Altzilla:BAAALgAECgEJAgAAAA==.Alyvien:BAAALgADCgMJAwAAAA==.',
Am='Amalthea:BAAALgADCgYJCQAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgADCgEJAgAAAA==.Arîane:BAAALgADCgIJAwAAAA==.',
As='Asapferg:BAAALgAECgcJBwAAAA==.Ashaman:BAABLgAECn8VAAIEAAUJlgHnRQCLAAAEAAUJlgHnRQCLAAAAAA==.Astanah:BAAALgAECgcJEwAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgEJAQAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAMJBQAFAI0WAA==.',
Be='Beastkraven:BAAALgAECgUJBQAAAA==.',
Bi='Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAAALgAECgUJCAAAAA==.Bloodedge:BAAALgAECgYJDgAAAA==.',
Bo='Bobbyswagger:BAAALgAECgEJAQAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Brentobox:BAAALgAECgYJDgAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAABLgAECn8aAAIBAAgJPw7QCwA1AQABAAgJPw7QCwA1AQAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgIJAgAAAA==.Caltora:BAAALgADCggJEQAAAA==.Cannelle:BAAALgAECgQJBQAAAA==.Carden:BAAALgAECgYJDgAAAA==.Carimknight:BAAALgAECgQJBAAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8WAAIGAAgJFiR4CwAmAwAGAAgJFiR4CwAmAwAAAA==.Charlas:BAAALgADCgUJBQAAAA==.Chesstickle:BAAALgAECgUJBwAAAA==.Chillywillie:BAAALgAECgUJEAAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgADCgcJBwAAAA==.Chrodne:BAAALgADCggJGwAAAA==.Chromax:BAAALgADCgUJBQAAAA==.Chucknorrîs:BAAALgADCgEJAQAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJAwAAAA==.Clintbarton:BAAALgAECgMJAwAAAA==.Cloudstrike:BAAALgAECgEJAQAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgQJBQAAAA==.',
Ct='Cthullu:BAABLgAFFH8FAAIFAAMJjRYmBwB9AAAFAAMJjRYmBwB9AAAAAA==.',
['Cø']='Cøldshoulder:BAAALgAECgYJEAAAAA==.',
Da='Dabi:BAAALgAECgMJAwAAAA==.Daemon:BAAALgAECgYJEAAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAABLgAECn8iAAQHAAgJnhsBJACDAgAHAAgJnhsBJACDAgAIAAQJXxLaKAAfAQAJAAEJuRmfBwBMAAAAAA==.',
De='Deathsend:BAAALgAECgQJCAAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAAALgAECgUJBgAAAA==.Deepstate:BAAALgADCgkJGwAAAA==.Deimosz:BAAALgAECgYJBwABLgAFFAEJAQACAAAAAA==.Demonicade:BAABLgAECn8WAAMHAAYJeQ0cIgAUAQAHAAUJeQ0cIgAUAQAIAAEJAABVdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.',
Di='Dima:BAABLgAECn8YAAIKAAYJxR5wDACoAQAKAAYJxR5wDACoAQAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgADCgkJIQAAAA==.',
Dn='Dne:BAABLgAECn8dAAILAAgJ8A56YgDMAQALAAgJ8A56YgDMAQAAAA==.',
Do='Donavon:BAABLgAECn8gAAIMAAgJSx64EgB9AgAMAAgJSx64EgB9AgAAAA==.Dornnbryda:BAAALgAECgUJBwAAAA==.',
Dr='Drackothyr:BAABLgAECn8WAAMNAAYJeSH5AQCLAQANAAYJsCD5AQCLAQAOAAIJEBiyWABbAAAAAA==.Drecarus:BAAALgAECgYJCwAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAMJBQAFAI0WAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Ec='Echidna:BAAALgADCggJDQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgUJDQAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAAALgAECgYJDgAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAAALgAECgYJEQAAAA==.',
['Eö']='Eöath:BAAALgAECgQJBgAAAA==.',
Fa='Falaurenta:BAAALgAECgUJBwAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgADCgcJDAAAAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJBQAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAAALgAECgUJCAAAAA==.',
Ga='Gailinn:BAAALgAECgMJAwAAAA==.Galreth:BAAALgAECgEJAwAAAA==.Ganon:BAAALgAECgYJCgAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn8WAAIPAAgJuRZJFAAPAQAPAAgJuRZJFAAPAQAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8aAAIQAAgJ9wsZGwBzAQAQAAgJ9wsZGwBzAQAAAA==.',
Ha='Hanuufalem:BAAALgAECgYJDAAAAA==.Hassad:BAAALgADCgcJDQAAAA==.',
He='Healaton:BAAALgAECgYJCwAAAA==.Healmonger:BAAALgAECgYJDAAAAA==.Healpants:BAAALgAECgMJBQAAAA==.Heruin:BAAALgAECgcJCwAAAA==.',
Hi='Hilgasmic:BAAALgAECgEJAgAAAA==.',
Ho='Hohenhaim:BAAALgAECgYJCwAAAA==.Holly:BAAALgAECgMJBAAAAA==.Holykal:BAEALgAECgYJEgAAAA==.Hope:BAAALgADCgYJBgABLgAECgYJGAARAM4dAA==.Horse:BAACLgAFFH8SAAISAAUJUwKDBQArAQASAAUJUwKDBQArAQAuAAQKfy8AAhIACQl9Ee0EAN4BABIACQl9Ee0EAN4BAAAA.',
Ic='Icu:BAAALgAECgQJBgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgMJBwAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAAALgAECgYJEAAAAA==.',
Ju='Jun:BAACLgAFFH8NAAIGAAUJsyLUBADgAQAGAAUJsyLUBADgAQAuAAQKfy8AAwYACQkUJVkAADsDAAYACQkUJVkAADsDABEABwmMJEsJAM4CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kaho:BAAALgAECgEJAQAAAA==.Karkas:BAAALgADCgkJFQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAAALgAECgcJEgAAAA==.Kateera:BAAALgAECgYJCQABLgAECggJEAACAAAAAA==.',
Ke='Kearyn:BAAALgAECggJEAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kevrad:BAAALgADCgYJBgAAAA==.',
Kh='Khephris:BAABLgAECn8VAAIDAAYJKg9AMwD7AAADAAYJKg9AMwD7AAAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn8YAAIDAAgJciGmHgD6AgADAAgJciGmHgD6AgAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAgAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCggJCAAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgEJAgAAAA==.Lazermoose:BAAALgAECgYJDQAAAA==.',
Le='Leap:BAAALgAECgUJBgABLgAFFAIJAwACAAAAAA==.Leonîdas:BAAALgAECgEJAQAAAA==.',
Li='Lightrider:BAAALgAECgQJBQAAAA==.Lionroar:BAACLgAFFH8LAAITAAQJghnRBAA3AQATAAQJghnRBAA3AQAuAAQKfykAAxMACAldIX0SAKICABMACAldIX0SAKICABQABglaEzg1AGkBAAAA.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lorellei:BAAALgAECgYJCwAAAA==.Lothgow:BAAALgADCgQJBAAAAA==.Lourdes:BAAALgAECgQJBwAAAA==.',
Lu='Luxus:BAAALgADCgcJDwAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAgABLgAFFAMJBQAFAI0WAA==.',
Ma='Maggzz:BAAALgAECgEJAQAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJBwAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAAALgAECgYJEAAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgUJCwACAAAAAA==.Mewzi:BAAALgAECgQJBAAAAA==.',
Mi='Miah:BAAALgAECgYJEAAAAA==.Miip:BAAALgADCgYJCgAAAA==.Milkyflower:BAAALgAECgUJBgAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgACAAAAAA==.',
Mo='Mograins:BAABLgAECn8lAAMHAAgJnh4IBwABAgAHAAYJsR8IBwABAgAIAAIJLBh2QwCnAAAAAA==.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgADCgkJIQAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Mu='Muffinn:BAAALgAECggJEwAAAA==.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECggJEQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgUJBQAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAAALgAECgMJAwAAAA==.',
Na='Nala:BAAALgAFFAIJAgAAAA==.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgACAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAAALgAECgUJEQAAAA==.',
Ni='Niame:BAAALgAECgYJDAAAAA==.Nitraina:BAAALgADCgUJBgAAAA==.Niyabelle:BAAALgAECgUJCwAAAA==.',
No='Noether:BAAALgAECgYJCwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.',
Oa='Oakmane:BAAALgAECgMJAwAAAA==.',
Ok='Okamí:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.',
Ol='Oleevia:BAABLgAECn8XAAIBAAYJFxbsCQBRAQABAAYJFxbsCQBRAQAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Oreiel:BAAALgADCgIJAgAAAA==.Orgdh:BAACLgAFFH8SAAIGAAUJvxSSCgCFAQAGAAUJvxSSCgCFAQAuAAQKfy8AAgYACQkaHwIBAOQCAAYACQkaHwIBAOQCAAAA.Orgdynamite:BAAALgAECgQJBwAAAA==.',
Pa='Paedragon:BAAALgADCgkJIQAAAA==.Paladareian:BAABLgAECn8VAAIMAAgJ0hJ+DwBEAQAMAAgJ0hJ+DwBEAQAAAA==.Pandalin:BAAALgAECgMJAwABLgAECgQJBAACAAAAAA==.',
Pe='Pejbolt:BAAALgAECgYJCAABLgAFFAUJDQAGALMiAA==.Pennywiseit:BAAALgADCgYJBgAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAAALgAECgYJBwAAAA==.',
Pi='Pinheadd:BAAALgAECgQJAwAAAA==.Pink:BAAALgADCgYJBgAAAA==.',
Pm='Pmsm:BAAALgAECgQJBAAAAA==.',
Po='Powerslavé:BAAALgAECgQJBAAAAA==.',
Pr='Priestitoot:BAAALgAECgQJBgAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.',
Qu='Qudenos:BAAALgAECgQJBQAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJDAAAAA==.Raiden:BAAALgAECgYJEwAAAA==.Rawr:BAAALgAECgEJAQAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAECgQJBQAAAA==.Revoker:BAAALgADCgcJFQABLgAECgYJGAARAM4dAA==.Rexarg:BAAALgAECgQJDAAAAA==.',
Ri='Riels:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAEJAQACAAAAAA==.Rockbìter:BAAALgAFFAEJAQAAAA==.Rockthyr:BAAALgAECgQJBQABLgAFFAEJAQACAAAAAA==.Rojas:BAAALgAECgQJBAAAAA==.',
['Ré']='Réåper:BAAALgAECgcJDQAAAA==.',
['Rö']='Römana:BAAALgAECgUJCQAAAA==.',
Sa='Saaran:BAAALgAECgQJBAAAAA==.Sandoriel:BAAALgADCgYJCQAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAEJAgACAAAAAA==.',
Sc='Scarellia:BAAALgAECgQJBAAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn8YAAIDAAYJ2xwSHwBaAQADAAYJ2xwSHwBaAQAAAA==.',
Sh='Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAAALgADCgcJCwAAAA==.Shamwowolio:BAAALgAECgUJBgABLgAECggJGgABAD8OAA==.Shatterfrost:BAABLgAECn8XAAMVAAYJhRaACgA1AQAVAAUJIBOACgA1AQADAAYJjw/rMAAFAQAAAA==.Shayd:BAAALgAECgYJBgABLgAECgYJGAARAM4dAA==.Shiggles:BAAALgAECgQJBAABLgAECgcJCgACAAAAAA==.Shirraz:BAAALgADCgYJBwAAAA==.',
Si='Sicksdeep:BAACLgAFFH8GAAMWAAMJbgf7BwCBAAAWAAIJ7wX7BwCBAAAXAAIJXgVCDwBSAAAuAAQKfxoAAxYABwlKGPcJAAoCABYABwlKGPcJAAoCABcABQltCY1sAAQBAAAA.',
Sk='Skelmirson:BAAALgADCgYJBgAAAA==.Skewpin:BAAALgADCgQJBAAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn8ZAAIYAAgJERq1BQAmAQAYAAgJERq1BQAmAQAAAA==.',
Sl='Slamma:BAACLgAFFH8SAAIXAAUJhSCRAACVAQAXAAUJhSCRAACVAQAuAAQKfy8AAxcACQl5JjMAAPgDABcACQl5JjMAAPgDABYAAQmpIvEOAGYAAAAA.Slicedbread:BAAALgAFFAMJBAABLgAFFAUJDAAMAE4hAA==.',
Sm='Smokadaganga:BAAALgAECgYJBgAAAA==.',
Sn='Snoball:BAAALgAECgEJAQAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Sols:BAAALgAECgYJDAAAAA==.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgADCgQJBgAAAA==.',
Sp='Spatula:BAAALgADCgYJCQAAAA==.Speoghii:BAAALgAECgYJBwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAAALgAECgUJCQAAAA==.',
St='Starhoof:BAAALgADCgYJBgAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAAALgAECgIJAgAAAA==.Stillfrazier:BAAALgAECgUJDQAAAA==.',
Su='Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgMJAwAAAA==.',
Sv='Svarog:BAAALgAECgYJCwABLgAFFAIJAgACAAAAAA==.',
['Sö']='Söphie:BAAALgAECgkJBgAAAA==.',
Ta='Tainema:BAAALgAECgYJCQAAAA==.Talangi:BAAALgAECgcJBwAAAA==.Taurriel:BAABLgAECn8VAAIKAAYJtxubDQCaAQAKAAYJtxubDQCaAQAAAA==.Tazzm:BAAALgAECgYJBgAAAA==.',
Te='Teranok:BAAALgAECggJEwAAAA==.Terozon:BAAALgAECgUJBwAAAA==.',
Th='Tharianrex:BAABLgAECn8XAAIZAAgJSiJqAwD6AgAZAAgJSiJqAwD6AgAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Them:BAAALgAECgUJCQAAAA==.Thoir:BAACLgAFFH8SAAIPAAUJYSAiAQD/AQAPAAUJYSAiAQD/AQAuAAQKfzAAAg8ACQkZJPoAAJgDAA8ACQkZJPoAAJgDAAEuAAUUBQkSABIAUwIA.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tickells:BAABLgAECn8YAAMBAAgJzAdRCgBLAQABAAgJzAdRCgBLAQAEAAYJLwVSNQD6AAAAAA==.Tipsylorcet:BAABLgAECn8VAAIaAAYJahssBwCKAQAaAAYJahssBwCKAQAAAA==.',
Tr='Tricktìckler:BAAALgADCgkJIQAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECgUJCwAAAA==.Turiell:BAAALgADCgkJEwAAAA==.',
Ty='Tybird:BAAALgAECgYJDgAAAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgcJCAAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAUJEgABAFYeAA==.Ulyssi:BAACLgAFFH8SAAIBAAUJVh5qAgDXAQABAAUJVh5qAgDXAQAuAAQKfy8AAgEACQmhJDwAACcDAAEACQmhJDwAACcDAAAA.',
Va='Valethara:BAAALgADCgIJAgAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgMJBgAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgEJAgAAAA==.Ven:BAABLgAECn8WAAIBAAYJxwaJEQDfAAABAAYJxwaJEQDfAAAAAA==.Venturecap:BAAALgAECgIJBQAAAA==.Verxina:BAAALgAECgUJEAAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAAALgADCgYJBgAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgIJAgACAAAAAA==.',
Vu='Vullrog:BAABLgAECn8XAAIYAAgJCxJ3JgDyAQAYAAgJCxJ3JgDyAQAAAA==.',
We='Weehunt:BAAALgAECgYJDgAAAA==.',
Wh='Whez:BAAALgAECgUJBgAAAA==.',
Wi='Wicka:BAABLgAECn8XAAIPAAcJoiSrAQCdAgAPAAcJoiSrAQCdAgAAAA==.Widowfang:BAAALgAECgUJCgAAAA==.Wikka:BAAALgAECgIJAwAAAA==.Wildriver:BAAALgAECgUJDwAAAA==.',
Xa='Xaehyun:BAACLgAFFH8SAAMbAAUJOSRfAACXAQAbAAQJOSRfAACXAQAcAAEJMiXqCQBwAAAuAAQKfzAAAxsACQm8JhAAAAoEABsACQm8JhAAAAoEABwABQlEHRQhAKwBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8YAAQRAAYJzh0lKgBzAQARAAUJhB0lKgBzAQAGAAQJoRKcmwDhAAAdAAMJqR95GADaAAAAAA==.Xanni:BAABLgAECn8kAAMeAAgJrgjADgAZAQAeAAgJrgjADgAZAQAPAAMJkQN/iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8SAAIFAAUJDxQeBQBSAQAFAAUJDxQeBQBSAQAuAAQKfy8AAgUACQljIlAAAO0CAAUACQljIlAAAO0CAAAA.Xmrpmonk:BAAALgAECgYJBwABLgAFFAUJEgAFAA8UAA==.',
Xo='Xohan:BAABLgAECn8gAAIXAAkJyxyzAAC3AgAXAAkJyxyzAAC3AgAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAAALgAECgMJAwAAAA==.',
Yo='Yoyiek:BAAALgAECgEJAQAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8SAAIfAAUJkxz6AADXAQAfAAUJkxz6AADXAQAuAAQKfy8AAx8ACQkaIYIAAOACAB8ACQkaIYIAAOACAA0ABAlZHuAhABsBAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAIJAgACAAAAAA==.Zanne:BAACLgAFFH8FAAIYAAIJrBHbBQCUAAAYAAIJrBHbBQCUAAAuAAQKfxoAAhgACAkyHY8ZAFsCABgACAkyHY8ZAFsCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgADCgcJDAAAAA==.',
Ze='Zehara:BAAALgAECgcJDAAAAA==.Zenovesh:BAAALgADCggJCAAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJBwAAAA==.',
Zl='Zlot:BAECLgAFFH8SAAQKAAUJABt1AwBmAQAKAAQJyRp1AwBmAQAYAAMJJgsEGADTAAAgAAEJFAyPBwBTAAAuAAQKfy8AAwoACQmqJSUAAFoDAAoACQmNJSUAAFoDABgABwkbHtQXAGsCAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAAALgAECgMJAwAAAA==.',
['Úl']='Úlfa:BAAALgAECgYJBwAAAA==.',
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
