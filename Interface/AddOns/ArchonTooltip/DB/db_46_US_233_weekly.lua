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

local lookup = {'Mage-Frost','Paladin-Holy','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Mage-Fire','Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Druid-Restoration','Warrior-Fury','Warrior-Arms','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Evoker-Preservation','Druid-Guardian','Rogue-Subtlety','Priest-Holy','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBAAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8ZAAIBAAgJmhWyQABsAQABAAgJmhWyQABsAQAAAA==.',
An='Angelona:BAACLgAFFH8JAAIBAAMJvSWqIQBMAQABAAMJvSWqIQBMAQAuAAQKfyIAAgEACAkcJmUNAFoDAAEACAkcJmUNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn8mAAICAAgJZR3QDACzAgACAAgJZR3QDACzAgABLgABCgEJAQADAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAABLgAECn8aAAMEAAgJEhnBNgBIAgAEAAgJEhnBNgBIAgAFAAEJKwGtLgAWAAAAAA==.Archmond:BAABLgAECn8VAAMGAAcJJhczCwCIAQAGAAYJPxUzCwCIAQAHAAMJVROsPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCAAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8UAAICAAYJbx0NFQCrAQACAAYJbx0NFQCrAQAAAA==.Ashthundér:BAABLgAECn8WAAIIAAYJKhj5BACpAQAIAAYJKhj5BACpAQABLgAFFAQJCgAJABYYAA==.',
Av='Avyhn:BAACLgAFFH8IAAIKAAQJFB6fCwB3AQAKAAQJFB6fCwB3AQAuAAQKfxcAAwoACQl1I8AeAJ8CAAoABwlQI8AeAJ8CAAcAAgl3JN5BAK0AAAEuAAUUBgkVAAoABSQA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
Ba='Baaka:BAABLgAECn8bAAILAAcJOA0MKgBtAQALAAcJOA0MKgBtAQAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Barquiel:BAABLgAECn8fAAMFAAcJpB4PCQBEAgAFAAcJpB4PCQBEAgAEAAMJpQ59eQC6AAAAAA==.Batimo:BAAALgAECgQJBAAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8ZAAIMAAcJ0h4hBwAyAgAMAAcJ0h4hBwAyAgAAAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAAALgAFFAEJAQAAAA==.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgADAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8bAAINAAgJzRh5CwBRAgANAAgJzRh5CwBRAgAAAA==.',
Br='Britneyspear:BAABLgAECn8kAAMOAAgJjRhUNQDUAQAOAAcJ6BtUNQDUAQAPAAUJXQ9zFADXAAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8fAAIQAAgJHxm5RAAnAgAQAAgJHxm5RAAnAgAAAA==.Bullthing:BAABLgAECn8VAAQCAAYJYRwLGgB8AQACAAUJQxsLGgB8AQAEAAMJiRhv3wDOAAAFAAEJYxdePgBEAAAAAA==.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn8VAAMRAAgJgxrTKwC6AQARAAcJmh7TKwC6AQASAAUJOR7TOgCWAQAAAA==.Cassyn:BAAALgAECgEJAwAAAA==.',
Ch='Chansey:BAABLgAECn8kAAIMAAkJWRzdCACuAgAMAAkJWRzdCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8ZAAMTAAYJWRkoMgCJAQATAAYJWRkoMgCJAQAUAAUJJwdUSQCzAAAAAA==.Chipsbambee:BAABLgAECn8YAAILAAYJYQ8TVgBmAQALAAYJYQ8TVgBmAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8SAAMVAAUJ9SNuAABIAQAVAAUJ9SNuAABIAQASAAQJExSvDAAPAQAuAAQKfywAAxUACQnDJT0BAKECABUABwkiJj0BAKECABIACQlDGcciAA4CAAAA.',
Co='Combust:BAABLgAECn8rAAIBAAgJTx6vEABXAgABAAgJTx6vEABXAgAAAA==.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgQJBAAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgADCgIJAgAAAA==.Dao:BAABLgAFFH8HAAISAAMJ0BR3EwDDAAASAAMJ0BR3EwDDAAAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deadrat:BAAALgAECgUJBwAAAA==.Deathvader:BAAALgADCgYJBgAAAA==.Delaomega:BAABLgAECn8gAAIWAAgJ7QqfEwDpAAAWAAgJ7QqfEwDpAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvor:BAABLgAECn8rAAMWAAkJSRXpCgBoAgAWAAkJSRXpCgBoAgAQAAEJcQHaOwEbAAAAAA==.Drash:BAABLgAECn8aAAIXAAYJDApgCwAJAQAXAAYJCwpgCwAJAQAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.',
Du='Dumbledore:BAABLgAECn8cAAIWAAkJxRWNDQA1AgAWAAkJxRWNDQA1AgAAAA==.Dumpnloads:BAAALgADCgEJAQAAAA==.Durotagg:BAAALgAECgUJBgAAAA==.',
['Dí']='Dím:BAAALgAECgEJAQAAAA==.',
Ea='Eaterofholes:BAAALgADCgMJAgAAAA==.',
Ed='Edubijes:BAAALgAECgEJAgABLgAECgcJEwADAAAAAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJAwAAAA==.Elfguy:BAAALgADCgYJDAAAAA==.',
En='Endléss:BAABLgAECn8eAAIYAAcJlhraCQDEAQAYAAcJlhraCQDEAQAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAADAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAECgkJEAAAAA==.',
Es='Esquandolas:BAAALgADCgEJAQAAAA==.',
Ev='Evotibs:BAABLgAECn8VAAIZAAYJQA0tDQD5AAAZAAYJQA0tDQD5AAAAAA==.',
Fe='Fec:BAAALgADCgEJAQABLgAECggJJAAaAE8gAA==.',
Fi='Fibaldrachi:BAABLgAECn8ZAAIbAAcJLiHaAgD+AQAbAAcJLiHaAgD+AQAAAA==.',
Fr='Frosting:BAABLgAECn8YAAIBAAcJZR6CGwAGAgABAAcJZR6CGwAGAgAAAA==.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAAALgAECgYJEQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgUJBQAAAA==.',
Gr='Grandall:BAAALgAECgEJAwAAAA==.Gruon:BAABLgAECn8aAAIcAAYJ4gk+MACUAAAcAAYJ4gk+MACUAAAAAA==.',
Gu='Gulzan:BAAALgAECgYJDwAAAA==.',
['Gø']='Gøkû:BAAALgAECgUJCQAAAA==.',
Ha='Hacks:BAABLgAECn8YAAIaAAYJcQ36EQAHAQAaAAYJcQ36EQAHAQAAAA==.Haymakerxd:BAAALgAFFAEJAQAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJCQAAAA==.Helendir:BAAALgADCgIJAgAAAA==.',
Hu='Huntercobra:BAAALgADCgQJBgAAAA==.Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8eAAQGAAcJzRvhAwBQAgAGAAcJzRvhAwBQAgAHAAQJ0hHiDwC0AAAKAAMJAQyzcACpAAAAAA==.Hypernova:BAAALgADCgMJAwAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAECgQJBAAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAAALgAECgYJEQAAAA==.',
In='Infernal:BAAALgAECgYJCQAAAA==.Ingo:BAAALgADCgcJBwAAAA==.Inspiremoon:BAAALgAECgYJDAAAAA==.Interror:BAAALgAECgYJDQAAAA==.',
Ir='Iranos:BAABLgAECn8fAAMEAAgJPxm5KgB5AgAEAAgJPxm5KgB5AgAFAAIJKwwrIQBXAAAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQADAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECgcJEwADAAAAAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgMJBgAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAECgcJGQAHACYdAA==.Kanakana:BAABLgAECn8cAAISAAcJqxxtFQC+AQASAAcJqxxtFQC+AQAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJBwAAAA==.',
Ki='Kindly:BAAALgAECgEJAQAAAA==.Kirab:BAAALgAECgYJDQAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAAALgAECgYJCwAAAA==.',
Ko='Kosmos:BAAALgAECgcJCAAAAA==.',
Kr='Kreid:BAAALgAECgUJCQAAAA==.Kreìd:BAAALgADCgEJAQABLgAECgUJCQADAAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8TAAIdAAYJqRKQdABIAQAdAAYJqRKQdABIAQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8kAAMeAAkJAh7OAgC3AgAeAAkJAh7OAgC3AgAfAAUJahPwIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgADCgUJBQAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8bAAIgAAgJVwqDKACVAQAgAAgJVwqDKACVAQAAAA==.Linestia:BAAALgAECgEJAgABLgAECgYJCgADAAAAAA==.Littlewingz:BAABLgAECn8WAAIhAAcJ0COhAQDVAgAhAAcJ0COhAQDVAgAAAA==.',
Lo='Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgEJAQAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJAwABLgAECgUJBgADAAAAAA==.Maladreks:BAAALgADCgYJDgAAAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwADAAAAAA==.Mawz:BAABLgAECn8WAAIVAAcJGhuGBADlAQAVAAcJGhuGBADlAQAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAABLgAECn8eAAINAAgJQCNnCQD8AgANAAgJQCNnCQD8AgAAAA==.Meedlefinger:BAAALgAECgQJBQAAAA==.Melathia:BAAALgAECgYJDwAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgcJAgAAAA==.',
Mu='Musclebear:BAAALgAFFAMJAwAAAA==.',
My='Mythaux:BAAALgADCgMJAwABLgAECgcJGQAHACYdAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Nahmeen:BAAALgAECgYJCgABLgAECggJLQAiAAcgAA==.',
Ne='Neero:BAABLgAECn8TAAIdAAcJyhm5FQC7AQAdAAcJyhm5FQC7AQAAAA==.Nelena:BAABLgAECn8cAAISAAYJKAsTLgALAQASAAYJKAsTLgALAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJBAAAAA==.Nezhyt:BAABLgAECn8ZAAIHAAcJJh1LAgD1AQAHAAcJJh1LAgD1AQAAAA==.',
Ni='Nicolbolas:BAABLgAECn8gAAMeAAgJvxcdCgDpAQAeAAgJvxcdCgDpAQAhAAIJewIRRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAABLgAFFH8HAAIVAAMJuyIDAwDNAAAVAAMJuyIDAwDNAAABLgAFFAYJGgABAPgmAA==.Notorious:BAAALgAECgYJCgAAAA==.',
Nt='Ntaicen:BAAALgADCgIJAgAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAAALgAECggJDAAAAA==.',
Pe='Pentasaurusr:BAABLgAECn8eAAMKAAcJSh+YQAAMAgAKAAYJSh+YQAAMAgAHAAIJ6BkbTACJAAAAAA==.',
Po='Pookkee:BAAALgAECgYJCgAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAQAAAA==.',
Pp='Ppat:BAAALgAECgUJCAAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAAALgAECgcJEwAAAA==.',
Re='Recheals:BAAALgAECgEJAQABLgAECgYJFAAjAHAYAA==.Recmod:BAABLgAECn8UAAIjAAYJcBhWKgCpAQAjAAYJcBhWKgCpAQAAAA==.Rendover:BAAALgAECgMJAwAAAA==.Return:BAABLgAECn8kAAIaAAgJTyDiBQDXAgAaAAgJTyDiBQDXAgAAAA==.',
Rh='Rhimeholt:BAABLgAECn8VAAIUAAYJtxwkDQDTAQAUAAYJtxwkDQDTAQAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJAgAAAA==.',
Ry='Ryahask:BAABLgAECn8dAAIVAAgJ0g3xBQCyAQAVAAgJ0g3xBQCyAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAABLgAECn8gAAIEAAgJSxppLwBlAgAEAAgJSxppLwBlAgAAAA==.Sammyshoes:BAAALgAECggJDAAAAA==.Sanguine:BAAALgAECgQJBAAAAA==.',
Sc='Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8jAAMJAAgJHyELAwD4AQAJAAcJECELAwD4AQABAAcJ3BtROACGAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.',
Sh='Shadow:BAAALgAECgYJBwAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slippie:BAAALgAECgMJAwAAAA==.',
Sm='Smell:BAABLgAECn8lAAIEAAgJZBmfLgBoAgAEAAgJZBmfLgBoAgAAAA==.',
So='Solheim:BAAALgAECgYJDAAAAA==.',
Sp='Spacemonk:BAAALgAECgQJBQAAAA==.Spire:BAAALgAECgUJDQAAAA==.Sproutling:BAABLgAECn8ZAAINAAYJnwcnPADhAAANAAYJnwcnPADhAAAAAA==.',
St='Stearphen:BAAALgAECgcJEAAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJCgAAAA==.',
Sw='Swazti:BAABLgAECn8ZAAIKAAgJ9g9rLQB2AQAKAAgJ9g9rLQB2AQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgcJAgADAAAAAA==.Taurnil:BAABLgAECn8cAAIGAAYJFxGrDABtAQAGAAYJFxGrDABtAQAAAA==.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Ti='Timika:BAABLgAECn8YAAMkAAcJdRFuEwB7AQAkAAcJYhFuEwB7AQAMAAYJFQhpGgARAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Ty='Typeshift:BAAALgAFFAMJAwAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAUJDgAeAIcaAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAAALgAECgYJBwAAAA==.',
Va='Vaeron:BAAALgAECgcJCQAAAA==.',
Ve='Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8bAAIOAAkJugtpKgAPAgAOAAkJugtpKgAPAgAAAA==.Venomsecho:BAABLgAECn8iAAIlAAgJ7BYaBQDNAQAlAAgJ7BYaBQDNAQAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECgMJAwAAAA==.',
We='Weathergirl:BAAALgAECgcJCgAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIUAAgJ2BiVFwADAgAUAAgJ2BiVFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAADAAAAAA==.',
Wy='Wy:BAAALgAECgEJAQAAAA==.',
Xa='Xanna:BAAALgAECgEJAQAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIFAAMJDRPAAwDDAAAFAAMJDRPAAwDDAAAuAAQKfycAAgUACAmlItwCAPsCAAUACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAAALgAECgQJCwAAAA==.',
Za='Zach:BAABLgAECn8aAAIBAAgJNxlzPACFAgABAAgJNxlzPACFAgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIUAAcJiwVaPADzAAAUAAcJiwVaPADzAAAAAA==.',
['Ðe']='Ðeath:BAAALgAECgUJBQAAAA==.',
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
