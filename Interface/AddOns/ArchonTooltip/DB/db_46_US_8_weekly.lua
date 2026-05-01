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

local lookup = {'Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Restoration','Warlock-Demonology','DemonHunter-Havoc','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Hunter-Survival','Warrior-Arms','DeathKnight-Unholy','Paladin-Protection','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abomination:BAAALgAECgUJCAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAIBAAUJhCIVBwBiAQABAAUJhCIVBwBiAQAuAAQKfxYAAwEABwlGJmEMAMkCAAEABwlGJmEMAMkCAAIAAQmaFTt1AEEAAAEuAAUUBwkhAAMAESYA.Adedine:BAAALgADCgYJBwAAAA==.Adina:BAAALgAFFAEJAQAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAEAAAAAA==.',
Al='Alianicus:BAAALgADCgIJAgAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJBwAAAA==.Arieon:BAAALgAECgIJAgAAAA==.',
As='Ashfallen:BAAALgAECgQJBgAAAA==.',
At='Atthegates:BAABLgAECn8gAAIFAAgJlxwLBQBuAgAFAAgJlxwLBQBuAgAAAA==.',
Au='Audric:BAABLgAECn8gAAIGAAgJQgxDEACKAQAGAAgJQgxDEACKAQAAAA==.Auryx:BAAALgADCgMJAwAAAA==.',
Az='Azrel:BAAALgAECgUJBQAAAA==.',
Ba='Baddragon:BAACLgAFFH8OAAQHAAUJ1R6yAABzAQAHAAUJxBuyAABzAQAIAAMJ/CBzDgAaAQAJAAEJxAcpFgBMAAAuAAQKfyIABAcACAlEJUQKADoCAAgABgmOJXcQAHECAAcABwkBHEQKADoCAAkAAQk0CYxJAC8AAAAA.Balji:BAAALgAECgIJAgAAAA==.Balto:BAACLgAFFH8SAAIKAAUJeSYsAADJAQAKAAUJeSYsAADJAQAuAAQKfyYAAgoACQnqJhQAAAUEAAoACQnqJhQAAAUEAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bayleef:BAABLgAECn8mAAILAAgJVhuvDwAYAgALAAgJVhuvDwAYAgAAAA==.',
Be='Beardik:BAAALgAECgUJCAAAAA==.Beccs:BAAALgADCgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAECggJGAAMADEOAA==.Beldr:BAAALgAECgYJCwAAAA==.Benito:BAAALgAECgUJDAAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brotherhood:BAAALgAECggJCAAAAA==.Brujita:BAAALgADCgEJAQAAAA==.Brujochingon:BAAALgAECgcJEgAAAA==.Brèè:BAABLgAECn8pAAINAAkJ4xz1BwDkAgANAAkJ4xz1BwDkAgAAAA==.',
Ca='Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAEALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Chiz:BAABLgAECn8XAAIOAAYJMBn+iQC+AQAOAAYJMBn+iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAABLgAECn8YAAIMAAgJMQ4xJgCWAQAMAAgJMQ4xJgCWAQAAAA==.',
Co='Conall:BAABLgAECn8kAAIPAAgJPBkqHQDbAQAPAAgJPBkqHQDbAQAAAA==.Confetti:BAAALgAECgUJCwAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJEgAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Da='Dajova:BAAALgAECgMJAwAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgADCgcJDAAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJAQAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgEJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAEAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMCAAYJagwBHAAFAQACAAYJagwBHAAFAQAQAAYJdwbgQgDTAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8mAAMQAAgJWBBxJACPAQAQAAgJWBBxJACPAQACAAcJvg7LFgAzAQAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAQAAAA==.Dragonsloot:BAACLgAFFH8LAAMIAAQJ+w2rDgAWAQAIAAQJ+w2rDgAWAQAJAAIJVwFZFABvAAAuAAQKfygABAgACQk4GdAIAAECAAgACQk4GdAIAAECAAkABwmeBC8PAAwBAAcAAQk1GMs7AD4AAAAA.Draks:BAAALgADCgUJBQAAAA==.Drizzitt:BAAALgAECgQJBAAAAA==.Drubeastin:BAABLgAECn8VAAIRAAcJmhjNJwB4AQARAAcJmhjNJwB4AQAAAA==.Druidia:BAAALgADCgYJBgAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Ec='Eclemage:BAAALgAECgQJCwAAAA==.',
El='Elementtamer:BAAALgADCgIJAgAAAA==.',
Es='Esh:BAABLgAECn8aAAMMAAgJxCEGJwB1AgAMAAYJwiMGJwB1AgASAAQJSRljIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgADCgEJAQAAAA==.Evilemt:BAAALgAECgEJAgAAAA==.Evilmt:BAAALgADCgEJBAAAAA==.',
Fa='Faîth:BAAALgAECgUJBQABLgAECggJHwAOAEweAA==.',
Fo='Forgiven:BAACLgAFFH8FAAITAAQJ9h8lCAB4AQATAAQJ9h8lCAB4AQAuAAQKfxcAAhMABgmKJU0nAEsBABMABgmKJU0nAEsBAAAA.',
Fr='Frogsbreath:BAAALgAECgYJBwAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgADCgEJAQAAAA==.',
Ga='Gairmet:BAAALgADCgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECgEJAQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgADCggJCQAAAA==.Gullveig:BAAALgAECgcJEwAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Harami:BAAALgAECgUJBQAAAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8bAAIOAAcJSBJeOwB8AQAOAAcJSBJeOwB8AQAAAA==.Hellmagi:BAAALgAECgcJDAAAAA==.Helmon:BAAALgAECgMJAwAAAA==.Hexson:BAABLgAECn8XAAQMAAgJqhIJbQCHAQAMAAgJqhIJbQCHAQASAAQJUQ0pUQB6AAAUAAEJ6AlUDwBEAAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMVAAcJJhAiQACAAQAVAAcJJhAiQACAAQAWAAMJ7R0vJwDtAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8ZAAIPAAcJ0CMrAAB3AgAPAAcJ0CMrAAB3AgAuAAQKfxwAAg8ACAlrJi0FAHoDAA8ACAlrJi0FAHoDAAAA.Hordeforsure:BAABLgAECn8UAAMXAAYJLh5LMACxAQAXAAYJGh5LMACxAQARAAEJbiARuABTAAABLgAFFAcJGQAPANAjAA==.Hornfu:BAAALgAECgIJAgAAAA==.',
Hu='Humanwolf:BAAALgAECgEJAQAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Inovar:BAACLgAFFH8FAAIMAAMJYB+cIAAfAQAMAAMJYB+cIAAfAQAuAAQKfxkAAgwABwmMIeoeAJ4CAAwABwmMIeoeAJ4CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAQAAAA==.',
Iz='Izugzug:BAAALgAFFAIJAwABLgAFFAUJDwACAMwXAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAECggJJgAPABglAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAAALgAECgIJAgABLgAECggJKQAYAIsUAA==.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwAAAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAABLgAECn8VAAMNAAYJ8BU8DgBXAQANAAYJ8BU8DgBXAQAZAAMJTgSZIwBlAAAAAA==.Kangarooz:BAAALgAECgUJBwAAAA==.Karlthuzad:BAAALgAECgQJBAAAAA==.Katrint:BAABLgAECn8YAAMaAAYJ7yOGDwB2AQAaAAYJ7yOGDwB2AQAbAAMJ2xt/FQCiAAAAAA==.',
Ke='Kekson:BAAALgADCgEJAQAAAA==.',
Kh='Kheliyah:BAACLgAFFH8MAAMcAAQJFiKrAwB0AQAcAAQJFiKrAwB0AQAGAAEJRQ24FABRAAAuAAQKfxoAAhwACAmgHgAIAMsCABwACAmgHgAIAMsCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAQJBwAOAIsFAA==.Kiramouse:BAABLgAFFH8JAAMMAAQJnxVTIgD7AAAMAAMJIBNTIgD7AAASAAEJGh1GEQBdAAAAAA==.Kirawrxd:BAAALgADCgEJAQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAUJDwACAMwXAA==.',
Ky='Kyrié:BAABLgAECn8XAAIcAAYJgCG9HgDqAQAcAAYJgCG9HgDqAQAAAA==.',
La='Lanzadora:BAAALgAECgQJBAAAAA==.',
Le='Leiya:BAAALgAECgQJCAAAAA==.',
Li='Liability:BAABLgAECn8dAAIdAAgJKAR8FADoAAAdAAgJKAR8FADoAAAAAA==.Linez:BAAALgADCgQJBAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAABLgAECn8mAAIRAAgJBiCSCABvAgARAAgJBiCSCABvAgAAAA==.',
Ma='Magital:BAAALgADCgcJCwABLgAFFAQJCwAIAPsNAA==.Makisan:BAAALgAECgcJDQAAAA==.',
Mc='Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgADCgYJDgAAAA==.Melara:BAAALgAECgEJAQAAAA==.Meowmeowmeow:BAAALgADCgYJBgAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8hAAIeAAgJxxdSAgDkAQAeAAgJxxdSAgDkAQAAAA==.Mikeoxlongg:BAAALgAECgMJAwAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgAECgIJAgAAAA==.',
Na='Naianasha:BAAALgAECgIJAgABLgAECgUJDgAEAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn8tAAILAAkJMCAgAgA7AwALAAkJMCAgAgA7AwAAAA==.',
Ne='Nenizaurio:BAAALgAECgIJAgAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgIJAQAAAA==.Noma:BAAALgADCgEJAQAAAA==.',
Nu='Nuxo:BAAALgAECgIJAQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgUJBgAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIfAAMJUBkFAgAQAQAfAAMJUBkFAgAQAQABLgAFFAUJEgAKAHkmAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgMJBQAAAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.',
Pn='Pnkrweb:BAAALgAECgcJDgAAAA==.',
Po='Poudi:BAAALgADCgYJBgABLgAECgQJBAAEAAAAAA==.',
Pr='Profitt:BAABLgAECn8lAAIOAAgJLB+mDQBzAgAOAAgJLB+mDQBzAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAABLgAECn8mAAIPAAgJGCWxBQC+AgAPAAgJGCWxBQC+AgAAAA==.Quâsar:BAAALgAECggJCAABLgAECggJHwAOAEweAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQAAAA==.Rabbidlight:BAAALgAECgYJEQAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasoon:BAAALgAECgUJBgAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8ZAAIPAAcJWxoYIQDEAQAPAAcJWxoYIQDEAQAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCAAEAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgMJAwAAAA==.Satoru:BAAALgAECgEJAQAAAA==.Saurfang:BAAALgADCgEJAQAAAA==.',
Se='Segen:BAAALgAECgQJCQAAAA==.Semip:BAAALgAECgQJCgAAAA==.Sen:BAABLgAECn8fAAMRAAgJuyMpBQCnAgARAAgJJiIpBQCnAgAXAAYJ7CH+IwAEAgAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgEJAQABLgAECgUJCAAEAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaitan:BAAALgAECgUJCgAAAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgADCgEJAQAAAA==.Shîver:BAABLgAECn8fAAIOAAgJTB6kKQDMAgAOAAgJTB6kKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8PAAICAAUJzBcTBQBJAQACAAUJzBcTBQBJAQAuAAQKfycAAwIACQnhHLAHAAADAAIACQnhHLAHAAADAAEAAwmXFK5iALcAAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAEAAAAAA==.Skyhealer:BAAALgAECgMJAwAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.',
Sn='Snipedyou:BAAALgAECgEJAQAAAA==.Snomed:BAABLgAFFH8GAAIUAAIJOiLWAADaAAAUAAIJOiLWAADaAAABLgAFFAUJEgAKAHkmAA==.',
So='Soleah:BAAALgAECgEJAQAAAA==.',
Sp='Spillgar:BAAALgAECgYJEQAAAA==.',
St='Stantic:BAACLgAFFH8MAAQRAAYJaAebDQDvAAARAAQJhwubDQDvAAAXAAMJJAE4IwBjAAAgAAEJHALeFQBHAAAuAAQKfx0AAxEACAmgHzsgAEQCABEACAnBGzsgAEQCABcABwmeG6shABUCAAAA.Statuskwo:BAAALgAECgUJBgABLgAECggJGAAMADEOAA==.Stevethuzad:BAAALgAECgQJBAAAAA==.Stormydaniel:BAAALgAECgEJAQAAAA==.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swagadin:BAAALgAECgcJBwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8aAAITAAgJohxEDgAEAgATAAgJohxEDgAEAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAECgIJAwAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAABLgAECn8ZAAIDAAgJjCDRBADwAQADAAgJjCDRBADwAQAAAA==.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgIJAgAEAAAAAA==.Trigodun:BAABLgAECn8iAAMFAAgJxxc5JAA1AgAFAAgJ6hQ5JAA1AgAhAAIJXhN5HgCDAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECggJGgATAKIcAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgQJCQAAAA==.',
Un='Undedagaindk:BAABLgAFFH8aAAIiAAYJMR8HAgAAAgAiAAYJMR8HAgAAAgAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAAALgAECgYJCAAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAAALgAECgUJDgAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8fAAQjAAgJ8xGcFwBbAQAjAAgJyQ6cFwBbAQAPAAQJ5g4v2wDWAAAYAAEJ7QEboQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8XAAICAAgJvx3GBQA4AgACAAgJvx3GBQA4AgAAAA==.',
Vy='Vyrric:BAAALgAECgcJEwAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgUJBQAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAUJEgAKAHkmAA==.',
Wh='Whitelove:BAABLgAECn8hAAMkAAgJ+Rj8BwAaAgAkAAcJhBv8BwAaAgAcAAQJaw03ZACdAAAAAA==.Whitest:BAAALgAECgYJBgAAAA==.Whixx:BAAALgADCgEJAQABLgAECggJFwAlAM4RAA==.Whý:BAAALgAECgYJCwAAAA==.',
Wi='Wikm:BAAALgAECgQJCAAAAA==.Wildseeker:BAAALgAECgMJAwAAAA==.Wiseoldman:BAAALgAECgcJDwAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wu='Wulrick:BAAALgAECgcJDgAAAA==.',
Xa='Xalithrya:BAAALgAECgUJBQABLgAECggJJgAPABglAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn8ZAAIVAAcJMBGDJQA/AQAVAAcJMBGDJQA/AQAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgADCgcJBwAAAA==.',
Yo='Yorna:BAAALgADCgEJAQAAAA==.',
Za='Zapey:BAABLgAECn8XAAIlAAgJzhFgCABsAQAlAAgJzhFgCABsAQAAAA==.',
Ze='Zem:BAAALgAECgYJBgAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAABLgAECn8VAAMVAAgJQRmfPQCKAQAVAAUJxxufPQCKAQAWAAcJ6Rx3HgAkAQAAAA==.',
Zo='Zoomies:BAAALgAECgYJBgABLgAECggJGAAJACogAA==.',
['Zé']='Zémzel:BAAALgAECgQJBQAAAA==.',
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
