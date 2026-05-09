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

local lookup = {'Mage-Frost','Paladin-Holy','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Mage-Fire','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','Druid-Restoration','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Priest-Holy','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAIBAAgJQxerTwB7AQABAAgJQxerTwB7AQAAAA==.',
An='Angelona:BAACLgAFFH8NAAIBAAQJCSNNEgCdAQABAAQJCSNNEgCdAQAuAAQKfyIAAgEACAkcJmQNAFoDAAEACAkcJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn8qAAICAAgJoyDQDACzAgACAAgJoyDQDACzAgABLgABCgEJAgADAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAABLgAECn8aAAMEAAgJEhm/NgBIAgAEAAgJEhm/NgBIAgAFAAEJLQHKOgAUAAAAAA==.Archmond:BAABLgAECn8VAAMGAAcJJhczCwCIAQAGAAYJPxUzCwCIAQAHAAMJVROsPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCQAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8bAAICAAcJ8Rk4EQAQAgACAAcJ8Rk4EQAQAgAAAA==.Ashthundér:BAABLgAECn8WAAIIAAYJKhj5BACpAQAIAAYJKhj5BACpAQABLgAFFAQJCwAJAMMZAA==.',
Av='Avyhn:BAACLgAFFH8IAAIKAAQJGR4JFgBdAQAKAAQJGR4JFgBdAQAuAAQKfxcAAwoACQl8I8AeAJ8CAAoABwlYI8AeAJ8CAAcAAgl3JOBBAK0AAAEuAAUUBwkcAAoARCMA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
Ba='Baaka:BAABLgAECn8jAAMLAAgJrQxKMQCIAQALAAgJrQxKMQCIAQAMAAEJyQGYQgAnAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Barquiel:BAABLgAECn8iAAMFAAgJ8R3hBAAuAgAFAAgJ8R3hBAAuAgAEAAMJpg5qnwCyAAAAAA==.Batimo:BAAALgAECgQJBAAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8fAAMNAAgJEBwMCQBJAgANAAcJ+x4MCQBJAgAOAAEJNQu1UQA1AAAAAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAAALgAFFAIJAwAAAA==.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgADAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8cAAIPAAgJ0RiDEQBEAgAPAAgJ0RiDEQBEAgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMQAAgJlRgeFAAaAQARAAcJ6xtVNQDUAQAQAAUJZg8eFAAaAQAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAISAAkJXRfyLgC+AQASAAkJXRfyLgC+AQAAAA==.Bullthing:BAABLgAECn8bAAQCAAgJbh/PDABIAgACAAcJYh7PDABIAgAEAAQJCRZ03wDOAAAFAAEJYxdbPgBEAAAAAA==.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn8dAAMTAAgJgxtmEgDIAQATAAcJxh9mEgDIAQAUAAUJaiDSOgCWAQAAAA==.Cassyn:BAAALgAECgEJAwAAAA==.',
Ch='Chansey:BAABLgAECn8kAAINAAkJWRzcCACuAgANAAkJWRzcCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8gAAMVAAcJNhojGAB2AQAVAAcJNhojGAB2AQAWAAUJJwdVSQCzAAAAAA==.Chipsbambee:BAABLgAECn8cAAILAAgJUw0VPABdAQALAAgJUw0VPABdAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8YAAMXAAYJkSK8AACuAQAXAAUJBCW8AACuAQAUAAUJ2xKzDAAPAQAuAAQKfywAAxcACQnDJTACAJICABcABwkjJjACAJICABQACQlGGcQiAA4CAAAA.',
Co='Combust:BAABLgAECn80AAIBAAkJ+hzdCgDMAgABAAkJ+hzdCgDMAgAAAA==.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgQJBAAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgADCgIJAgAAAA==.Dao:BAACLgAFFH8HAAIUAAMJzBR6EwDDAAAUAAMJzBR6EwDDAAAuAAQKfxUAAxQACAnEHMQSAIACABQACAnEHMQSAIACABMABAl+BNpLAHMAAAAA.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deadrat:BAAALgAECgUJBwAAAA==.Deathvader:BAAALgADCgYJBgAAAA==.Delaomega:BAABLgAECn8pAAMYAAkJgwqqEgBJAQAYAAkJgwqqEgBJAQASAAEJjQZc6gAyAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvor:BAABLgAECn8uAAMYAAkJShXoCgBoAgAYAAkJShXoCgBoAgASAAEJcQHgOwEbAAAAAA==.Drash:BAABLgAECn8gAAIZAAYJwwyiCQAAAQAZAAYJwwyiCQAAAQAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.',
Du='Duhai:BAAALgAECgUJAwAAAA==.Dumbledore:BAABLgAECn8lAAIYAAkJUhcHBwAjAgAYAAkJUhcHBwAjAgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgUJBQAAAA==.',
Ea='Eaterofholes:BAAALgADCgMJAgAAAA==.',
Ed='Edubijes:BAAALgAECgMJAwABLgAECgcJFgARAAYOAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgYJDAAAAA==.',
En='Endléss:BAABLgAECn8lAAIMAAcJuhsYDQDTAQAMAAcJuhsYDQDTAQAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAADAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAEJAQAAAA==.',
Es='Eshwyn:BAAALgAECgUJBQAAAA==.Esquandolas:BAAALgADCgEJAQAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMaAAcJGAy3DQAQAQAaAAcJGAy3DQAQAQAMAAUJZQZ+IwDeAAAAAA==.',
Fe='Fec:BAAALgADCgEJAQABLgAECggJKAAbAFAgAA==.',
Fi='Fibaldrachi:BAABLgAECn8hAAIcAAgJsCN6AQCiAgAcAAgJsCN6AQCiAgAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAABLgAECn8fAAIBAAgJ6h3nGABWAgABAAgJ6h3nGABWAgAAAA==.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8WAAITAAYJ5RtPKQDKAQATAAYJ5RtPKQDKAQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDAAAAA==.',
Gr='Grandall:BAAALgAECgEJAwAAAA==.Gruon:BAABLgAECn8gAAIdAAYJOAtXKgDyAAAdAAYJOAtXKgDyAAAAAA==.',
Gu='Gulzan:BAAALgAFFAEJAQAAAA==.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8cAAIbAAgJ9gyMDwBqAQAbAAgJ9gyMDwBqAQAAAA==.Haymakerxd:BAAALgAFFAEJAgAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Hu='Huntercobra:BAAALgADCgUJBwAAAA==.Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8iAAQGAAgJWRvhAwBQAgAGAAgJWRvhAwBQAgAHAAQJ2hE0FACvAAAKAAMJCgzTjgCmAAAAAA==.Hypernova:BAAALgADCgMJAwAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAECgQJBAAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8XAAIBAAYJrAc/jAD6AAABAAYJrAc/jAD6AAAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgcJBwAAAA==.Inspiremoon:BAAALgAECgYJDAAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ir='Iranos:BAABLgAECn8fAAMEAAgJQRm4KgB5AgAEAAgJQRm4KgB5AgAFAAIJLgx7KQBWAAAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQADAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECgcJFgARAAYOAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgQJBwAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAECggJIQAHALQdAA==.Kanakana:BAABLgAECn8gAAIUAAgJvBu4EwAXAgAUAAgJvBu4EwAXAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAAALgAECgcJEQAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAAALgAECggJDwAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Kosmos:BAAALgAECgcJCAAAAA==.',
Kr='Kreid:BAAALgAECgUJCwAAAA==.Kreìd:BAAALgADCgEJAQABLgAECgUJCwADAAAAAA==.',
Ky='Kyrr:BAAALgAECggJCAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8bAAIeAAgJahLELwB4AQAeAAgJahLELwB4AQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMfAAkJTh4pBAC/AgAfAAkJTh4pBAC/AgAgAAUJHBTrIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgADCgUJBQAAAA==.Lilia:BAAALgAFFAcJBAAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8fAAIOAAkJ1QrUHwA+AQAOAAkJ1QrUHwA+AQAAAA==.Linestia:BAAALgAECgEJAgABLgAECgYJCgADAAAAAA==.Littlewingz:BAABLgAECn8cAAIhAAcJISRlAgDWAgAhAAcJISRlAgDWAgAAAA==.',
Lo='Lockinflame:BAAALgADCgQJBAABLgAFFAQJCwAJAMMZAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgEJAQAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgADAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwADAAAAAA==.Mawz:BAABLgAECn8YAAIXAAgJtRzWAwA6AgAXAAgJtRzWAwA6AgAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAABLgAECn8gAAIPAAkJ6yJjCQD8AgAPAAkJ6yJjCQD8AgAAAA==.Meedlefinger:BAAALgAECgQJBQAAAA==.Melathia:BAABLgAECn8WAAIKAAcJzAnWZgD/AAAKAAcJzAnWZgD/AAAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgcJAgAAAA==.',
Mu='Musclebear:BAABLgAFFH8HAAIiAAQJagdgDwAwAQAiAAQJagdgDwAwAQAAAA==.',
My='Mythaux:BAAALgADCgMJAwABLgAECggJIQAHALQdAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Ne='Neero:BAABLgAECn8YAAIeAAcJfxtKHgDTAQAeAAcJfxtKHgDTAQAAAA==.Nelena:BAABLgAECn8jAAIUAAcJDAp0NgAwAQAUAAcJDAp0NgAwAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJBQAAAA==.Nezhyt:BAABLgAECn8hAAIHAAgJtB2iAQBeAgAHAAgJtB2iAQBeAgAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMfAAkJNRYYCgApAgAfAAkJNRYYCgApAgAhAAIJewITRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAABLgAFFH8HAAIXAAMJtyJBBAAUAQAXAAMJtyJBBAAUAQABLgAFFAYJIAABAPgmAA==.Notorious:BAAALgAECggJEgAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn8UAAMfAAgJOAuJKQAHAQAfAAYJtweJKQAHAQAhAAcJdANjFgDdAAAAAA==.',
Pe='Pentasaurusr:BAABLgAECn8eAAMKAAcJSh+SQAAMAgAKAAYJSh+SQAAMAgAHAAIJ6BkcTACJAAAAAA==.',
Pl='Platemedic:BAAALgAECgMJAwAAAA==.',
Po='Pookkee:BAAALgAECgYJCgAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAgAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8WAAQRAAcJBg54JgBBAQARAAcJPgt4JgBBAQAbAAMJ3BSdIAC4AAAQAAIJtwaBPwA5AAAAAA==.',
Re='Recheals:BAAALgAECgIJAgABLgAECgcJFgAiAGwVAA==.Recmod:BAABLgAECn8WAAIiAAcJbBV+GQA2AQAiAAcJbBV+GQA2AQAAAA==.Rendover:BAAALgAECgYJBgAAAA==.Return:BAABLgAECn8oAAIbAAgJUCDiBQDXAgAbAAgJUCDiBQDXAgAAAA==.',
Rh='Rhimeholt:BAABLgAECn8cAAIWAAcJixsCDgALAgAWAAcJixsCDgALAgAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJAgAAAA==.',
Ry='Ryahask:BAABLgAECn8lAAIXAAgJtRD3BwCsAQAXAAgJtRD3BwCsAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAABLgAECn8kAAIEAAkJpRsTJADzAQAEAAkJpRsTJADzAQAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMJAAkJ7x4LAwD4AQAJAAcJZyELAwD4AQABAAgJJhqTMwDSAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.',
Sh='Shadow:BAAALgAECgYJDQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slippie:BAAALgAECgMJAwAAAA==.',
Sm='Smell:BAABLgAECn8uAAIEAAkJlhhFFgBJAgAEAAkJlhhFFgBJAgAAAA==.',
So='Solheim:BAAALgAECgYJDQAAAA==.',
Sp='Spacemonk:BAAALgAECgQJBQAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8gAAIPAAcJAQgfQwAGAQAPAAcJAQgfQwAGAQAAAA==.',
St='Stearphen:BAAALgAECggJEgAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJCgAAAA==.',
Sw='Swazti:BAABLgAECn8cAAIKAAgJXhHyKwC1AQAKAAgJXhHyKwC1AQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgcJAgADAAAAAA==.Taurnil:BAABLgAECn8jAAIGAAcJShjYAwC0AQAGAAcJShjYAwC0AQAAAA==.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Ti='Timika:BAABLgAECn8gAAMjAAgJpRRLEQDbAQAjAAgJgRRLEQDbAQANAAYJ+wkbIQAiAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Ty='Typeshift:BAABLgAFFH8HAAIkAAQJbRt5AgBTAQAkAAQJbRt5AgBTAQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAUJEwAfAIQaAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAAALgAECgYJCgAAAA==.',
Va='Vaeron:BAAALgAECgcJEQAAAA==.',
Ve='Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8bAAIRAAkJvwtlKgAPAgARAAkJvwtlKgAPAgAAAA==.Venomsecho:BAABLgAECn8jAAIlAAkJ1hQyBgDnAQAlAAkJ1hQyBgDnAQAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECgUJBQAAAA==.',
We='Weathergirl:BAAALgAECgcJCgAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIWAAgJ0BiUFwADAgAWAAgJ0BiUFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAADAAAAAA==.',
Wy='Wy:BAAALgAECgYJCQAAAA==.',
Xa='Xanna:BAAALgAECgEJAQAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIFAAMJGhN9BQC/AAAFAAMJGhN9BQC/AAAuAAQKfycAAgUACAmlItsCAPsCAAUACAmlItsCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAAALgAECgQJCwAAAA==.',
Za='Zach:BAABLgAECn8aAAIBAAgJOBluPACFAgABAAgJOBluPACFAgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIWAAcJiwVZPADzAAAWAAcJiwVZPADzAAAAAA==.',
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
