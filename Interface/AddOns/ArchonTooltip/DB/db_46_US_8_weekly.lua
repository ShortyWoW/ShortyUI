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

local lookup = {'Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Evoker-Augmentation','Warrior-Fury','Priest-Shadow','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Druid-Restoration','Warlock-Demonology','DemonHunter-Havoc','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Priest-Holy','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Hunter-Survival','DemonHunter-Devourer','Warrior-Arms','DeathKnight-Unholy','Paladin-Protection','Paladin-Holy','Priest-Discipline',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abomination:BAAALgAECgUJCAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAIBAAUJhCISBwBiAQABAAUJhCISBwBiAQAuAAQKfxYAAwEABwlGJmEMAMkCAAEABwlGJmEMAMkCAAIAAQmaFTB1AEEAAAEuAAUUBwkbAAMAESYA.Adedine:BAAALgADCgYJBwAAAA==.Adina:BAAALgAFFAEJAQAAAA==.',
Al='Alianicus:BAAALgADCgIJAgAAAA==.',
Am='Amalthea:BAAALgADCgkJDgAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJBwAAAA==.Arieon:BAAALgAECgIJAgABLgAECggJHgAEAOcVAA==.',
As='Ashfallen:BAAALgAECgMJAwAAAA==.',
At='Atthegates:BAABLgAECn8ZAAIFAAcJcx7xBADlAQAFAAcJcx7xBADlAQAAAA==.',
Au='Audric:BAABLgAECn8YAAIGAAcJ0wnbDQAXAQAGAAcJ0wnbDQAXAQAAAA==.',
Az='Azrel:BAAALgAECgUJBQAAAA==.',
Ba='Baddragon:BAACLgAFFH8JAAMHAAUJ1R4+AQDBAAAEAAMJ/CBvDgAaAQAHAAMJRRc+AQDBAAAuAAQKfyEABAcACAlEJUMKADoCAAQABgmLJXMQAHECAAcABwkBHEMKADoCAAgAAQk0CYlJAC8AAAAA.Balji:BAAALgAECgIJAgAAAA==.Balto:BAACLgAFFH8OAAIJAAUJUCMtAACfAQAJAAUJUCMtAACfAQAuAAQKfyYAAgkACQnqJhQAAAUEAAkACQnqJhQAAAUEAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bayleef:BAABLgAECn8fAAIKAAgJaBe/CADTAQAKAAgJaBe/CADTAQAAAA==.',
Be='Beardik:BAAALgAECgUJCAAAAA==.Beccs:BAAALgADCgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAECggJGAALADEOAA==.Beldr:BAAALgAECgYJCwAAAA==.Benito:BAAALgAECgUJCgAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brotherhood:BAAALgAECggJCAAAAA==.Brujita:BAAALgADCgEJAQAAAA==.Brujochingon:BAAALgAECgYJCwAAAA==.Brèè:BAABLgAECn8gAAIMAAkJIxryBwDkAgAMAAkJIxryBwDkAgAAAA==.',
Ca='Calice:BAAALgADCgEJAQAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAAALgADCgMJAwABLgAECgEJAQANAAAAAA==.Chiz:BAABLgAECn8XAAIOAAYJMBkPigC+AQAOAAYJMBkPigC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAABLgAECn8YAAILAAgJMQ5RDgCgAQALAAgJMQ5RDgCgAQAAAA==.',
Co='Conall:BAABLgAECn8gAAIPAAgJQhjOOABAAgAPAAgJQhjOOABAAgAAAA==.Confetti:BAAALgAECgQJBgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJEgAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Da='Dajova:BAAALgADCgQJBwAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgADCgcJDAABLgAECgQJBwANAAAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgADCgEJAQAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgEJAgAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgANAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAAALgAECgYJDwAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8fAAMQAAgJWBA5JACTAQAQAAgJWBA5JACTAQACAAcJ/g3FCQA2AQAAAA==.',
Dr='Dragonsloot:BAACLgAFFH8HAAIEAAQJHQaqDgAWAQAEAAQJHQaqDgAWAQAuAAQKfx8ABAQACQlNF9QNAJgCAAQACQlNF9QNAJgCAAgABQmjBQ8JANUAAAcAAQk1GMI7AD4AAAAA.Draks:BAAALgADCgUJBQAAAA==.Drizzitt:BAAALgAECgQJBAAAAA==.Drubeastin:BAABLgAECn8VAAIRAAcJmhgaEACAAQARAAcJmhgaEACAAQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Ec='Eclemage:BAAALgAECgQJCwAAAA==.',
El='Elementtamer:BAAALgADCgIJAgAAAA==.',
Es='Esh:BAABLgAECn8ZAAMLAAgJxCEFJwB1AgALAAYJwiMFJwB1AgASAAQJSRlhIwA9AQAAAA==.',
Ev='Evilemt:BAAALgAECgEJAQAAAA==.Evilmt:BAAALgADCgEJAwAAAA==.',
Fa='Faîth:BAAALgAECgQJBAABLgAECggJHgAOAFweAA==.',
Fo='Forgiven:BAAALgAFFAEJAQAAAA==.',
Fr='Frogsbreath:BAAALgAECgQJBAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Ga='Gairmet:BAAALgADCgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECgEJAQAAAA==.',
Gr='Grimwhisper:BAAALgAECgEJAQAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgADCggJCQAAAA==.Gullveig:BAAALgAECgYJCwAAAA==.Guxxi:BAAALgADCgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJDgAAAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8UAAIOAAYJsRKUIQBNAQAOAAYJsRKUIQBNAQAAAA==.Hellmagi:BAAALgAECgcJDAAAAA==.Helmon:BAAALgAECgMJAwAAAA==.Hexson:BAABLgAECn8WAAQLAAcJYhMDbQCHAQALAAcJYhMDbQCHAQASAAQJUQ0jUQB6AAATAAEJ6AlKCABEAAAAAA==.',
Hi='Hizø:BAAALgAECgcJEgAAAA==.',
Ho='Hordeelf:BAACLgAFFH8XAAIPAAYJlSMnAAAQAgAPAAYJlSMnAAAQAgAuAAQKfxwAAg8ACAlrJiYFAHoDAA8ACAlrJiYFAHoDAAAA.Hordeforsure:BAABLgAECn8UAAMUAAYJLh5HMACxAQAUAAYJGh5HMACxAQARAAEJbiD+twBTAAABLgAFFAYJFwAPAJUjAA==.',
Hu='Humanwolf:BAAALgAECgEJAQAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Inovar:BAABLgAECn8UAAILAAcJ5B/sHgCeAgALAAcJ5B/sHgCeAgAAAA==.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Iz='Izugzug:BAAALgAECgQJBAABLgAFFAQJCgACADIRAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAECggJIgAPAJIjAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Jugjugs:BAAALgADCgUJBQAAAA==.Juice:BAAALgAECgcJAgAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBgAAAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAAALgAECgYJDQAAAA==.Kangarooz:BAAALgAECgQJBgAAAA==.Karlthuzad:BAAALgADCgkJEQAAAA==.Katrint:BAAALgAFFAEJAQAAAA==.',
Ke='Kekson:BAAALgADCgEJAQAAAA==.',
Kh='Kheliyah:BAACLgAFFH8IAAMVAAMJ1Bx7BgATAQAVAAMJ1Bx7BgATAQAGAAEJRQ2zFABRAAAuAAQKfxoAAhUACAmgHv8HAMsCABUACAmgHv8HAMsCAAAA.',
Ki='Kippo:BAEALgAECgEJAgAAAA==.Kiramouse:BAABLgAFFH8GAAMLAAQJ9RJUIgD7AAALAAMJlA9UIgD7AAASAAEJGh1HEQBdAAAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAQJCgACADIRAA==.',
Ky='Kyrié:BAAALgAECgYJEAAAAA==.',
La='Lanzadora:BAAALgADCgkJEAAAAA==.',
Le='Leiya:BAAALgAECgQJCAAAAA==.',
Li='Liability:BAABLgAECn8bAAIWAAgJKARQCwDIAAAWAAgJKARQCwDIAAAAAA==.Linez:BAAALgADCgQJBAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAABLgAECn8iAAIRAAgJYhyFBgAFAgARAAgJYhyFBgAFAgAAAA==.',
Ma='Magital:BAAALgADCgQJBAABLgAFFAQJBwAEAB0GAA==.Makisan:BAAALgAECgcJCwAAAA==.',
Mc='Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgADCgYJCQAAAA==.Melara:BAAALgAECgEJAQAAAA==.Meowmeowmeow:BAAALgADCgYJBgAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8ZAAIXAAcJChjcBQDPAQAXAAcJChjcBQDPAQAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgADCgQJAwAAAA==.',
Na='Naianasha:BAAALgADCgYJCAABLgAECgUJCAANAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn8kAAIKAAkJHB7yAAADAwAKAAkJHB7yAAADAwAAAA==.',
Ne='Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgADCgEJAQAAAA==.Noma:BAAALgADCgEJAQAAAA==.',
Nu='Nuxo:BAAALgADCgcJDAAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCAAAAA==.',
Ol='Olakunei:BAAALgAECgEJAQAAAA==.Olunara:BAAALgAECgQJBgAAAA==.',
On='Onepiece:BAABLgAFFH8FAAIYAAMJ/goYAQDkAAAYAAMJ/goYAQDkAAABLgAFFAUJDgAJAFAjAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgMJBQABLgAECgUJBwANAAAAAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.',
Pn='Pnkrweb:BAAALgAECgYJDQAAAA==.',
Po='Poudi:BAAALgADCgYJBgABLgAECgcJBQANAAAAAA==.',
Pr='Profitt:BAABLgAECn8cAAIOAAgJhBwoDQDiAQAOAAgJhBwoDQDiAQAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAABLgAECn8iAAIPAAgJkiNuCgA9AwAPAAgJkiNuCgA9AwAAAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQAAAA==.Rabbidlight:BAAALgAECgYJDQAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasoon:BAAALgAECgEJAQAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAAALgAECgYJEgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCAANAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Satoru:BAAALgADCgMJBAAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAYJFgALAGsfAA==.',
Se='Segen:BAAALgAECgQJBQAAAA==.Semip:BAAALgAECgQJBgAAAA==.Sen:BAABLgAECn8ZAAMRAAcJOyJmEQByAQAUAAYJaB/9IwAEAgARAAYJzh5mEQByAQAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgEJAQABLgAECgUJCAANAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaitan:BAAALgAECgUJCAAAAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shîver:BAABLgAECn8eAAIOAAgJXB6mKQDMAgAOAAgJXB6mKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8KAAICAAQJMhEVAgAwAQACAAQJMhEVAgAwAQAuAAQKfyYAAwIACQlKG7AHAAADAAIACQlKG7AHAAADAAEAAwmXFLRiALcAAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwANAAAAAA==.Skyhealer:BAAALgAECgMJAwAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.',
Sn='Snipedyou:BAAALgADCgcJBwAAAA==.Snomed:BAAALgAFFAIJBAABLgAFFAUJDgAJAFAjAA==.',
Sp='Spillgar:BAAALgAECgYJDwAAAA==.',
St='Stantic:BAACLgAFFH8MAAQRAAYJaAeWDQDvAAARAAQJhwuWDQDvAAAUAAMJJAE0IwBjAAAZAAEJHAL3BwBMAAAuAAQKfx0AAxEACAmgHzsgAEQCABEACAnBGzsgAEQCABQABwmeG6ohABUCAAAA.Statuskwo:BAAALgAECgMJAwABLgAECggJGAALADEOAA==.Stevethuzad:BAAALgADCgkJEAAAAA==.Stormydaniel:BAAALgAECgEJAQAAAA==.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swagadin:BAAALgAECgcJBwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8ZAAIaAAcJ2ByeCQDZAQAaAAcJ2ByeCQDZAQAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgEJAQAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgADCgYJBwAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAABLgAECn8ZAAIDAAgJjCA9AQBTAgADAAgJjCA9AQBTAgAAAA==.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgIJAgANAAAAAA==.Trigodun:BAABLgAECn8hAAMFAAgJxxc1JAA1AgAFAAgJ6hQ1JAA1AgAbAAIJXhNADQCBAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgcJGQAaANgcAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgQJCAAAAA==.',
Un='Undedagaindk:BAABLgAFFH8UAAIcAAUJ7yIxAgD1AQAcAAUJ7yIxAgD1AQAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanillasquid:BAAALgAECgQJBgAAAA==.Vaxis:BAAALgAECgUJCAAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8XAAQdAAcJBhOaFwBbAQAdAAcJVA+aFwBbAQAPAAQJ5g4z2wDWAAAeAAEJ7QEHoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8XAAICAAgJvx3iAQA5AgACAAgJvx3iAQA5AgAAAA==.',
Vy='Vyrric:BAAALgAECgYJDAAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgUJBQAAAA==.',
We='Wetdog:BAAALgADCgUJBQABLgAFFAUJDgAJAFAjAA==.',
Wh='Whitelove:BAABLgAECn8ZAAMfAAcJ1RnjAwDwAQAfAAcJ1RnjAwDwAQAVAAMJgQ82ZACdAAAAAA==.Whitest:BAAALgADCgcJCwAAAA==.Whixx:BAAALgADCgEJAQABLgAECgcJEwANAAAAAA==.Whý:BAAALgAECgYJCwAAAA==.',
Wi='Wikm:BAAALgAECgQJCAAAAA==.Wildseeker:BAAALgAECgMJAwAAAA==.Wiseoldman:BAAALgAECgcJDwAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wu='Wulrick:BAAALgAECgcJDAAAAA==.',
Xa='Xandyr:BAAALgADCgUJBQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAAALgAECgYJEgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.',
Za='Zapey:BAAALgAECgcJEwAAAA==.',
Ze='Zem:BAAALgADCggJCQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAAALgAFFAEJAQAAAA==.',
Zo='Zoomies:BAAALgADCgYJCAABLgAECgYJFQAIAAoiAA==.',
['Zé']='Zémzel:BAAALgADCgcJDgAAAA==.',
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
