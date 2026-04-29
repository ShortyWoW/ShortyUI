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

local lookup = {'Mage-Frost','Paladin-Holy','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Warlock-Demonology','Hunter-BeastMastery','Warrior-Fury','Warrior-Arms','DeathKnight-Unholy','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Druid-Restoration','Druid-Guardian','Evoker-Preservation','Warrior-Protection','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgEJAgAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Al='Alatär:BAABLgAECn8XAAIBAAcJOBMFMQAEAQABAAcJOBMFMQAEAQAAAA==.',
An='Angelona:BAACLgAFFH8FAAIBAAIJdyWXFQDZAAABAAIJdyWXFQDZAAAuAAQKfyEAAgEACAkcJl0NAFoDAAEACAkcJl0NAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn8cAAICAAgJZR3SDACzAgACAAgJZR3SDACzAgABLgABCgEJAQADAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAABLgAECn8aAAMEAAgJEhnJNgBIAgAEAAgJEhnJNgBIAgAFAAEJKwEWFgAWAAAAAA==.Archmond:BAABLgAECn8VAAMGAAcJJhcyCwCIAQAGAAYJPxUyCwCIAQAHAAMJVROsPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgMJAwAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAAALgAECgYJDgAAAA==.Ashthundér:BAAALgAECgYJEQABLgAFFAQJCgAIABYYAA==.',
Av='Avyhn:BAABLgAECn8XAAMJAAkJdSO/HgCfAgAJAAcJUCO/HgCfAgAHAAIJdyTgQQCtAAABLgAFFAYJDwAHAO0iAA==.',
Az='Azlia:BAAALgADCgIJAgAAAA==.',
Ba='Baaka:BAABLgAECn8UAAIKAAcJiAtpFABYAQAKAAcJiAtpFABYAQAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Barquiel:BAABLgAECn8VAAIFAAcJVR0PCQBEAgAFAAcJVR0PCQBEAgAAAA==.Batimo:BAAALgAECgQJBAAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAAALgAECgYJEgAAAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAAALgAFFAEJAQAAAA==.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgADAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAAALgAECgYJCAAAAA==.',
Br='Britneyspear:BAABLgAECn8cAAMLAAcJFhxWNQDUAQALAAcJ6BtWNQDUAQAMAAQJiBCmHQACAQAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8dAAINAAgJ7Bh9DwCbAQANAAgJ7Bh9DwCbAQAAAA==.Bullthing:BAABLgAECn8UAAQCAAYJYRyIQQByAQACAAUJQxuIQQByAQAEAAMJiRhz3wDOAAAFAAEJYxddPgBEAAAAAA==.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAAALgAECggJEQAAAA==.Cassyn:BAAALgAECgEJAQAAAA==.',
Ch='Chansey:BAABLgAECn8hAAIOAAgJ3x7YCACuAgAOAAgJ3x7YCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAAALgAECgYJEwAAAA==.Chipsbambee:BAAALgAECgYJEwAAAA==.Chttr:BAAALgAECgMJAwAAAA==.Chttrbox:BAACLgAFFH8OAAMPAAUJBB6OAgAoAQAPAAUJBB6OAgAoAQAQAAQJExSrDAAPAQAuAAQKfyQAAw8ACAkKJA0IAGICAA8ABgnWIw0IAGICABAACAllG88iAA4CAAAA.',
Co='Combust:BAABLgAECn8jAAIBAAgJeRteDwDJAQABAAgJeRteDwDJAQAAAA==.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgADCgcJBwAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgQJBAAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Dao:BAABLgAFFH8FAAIQAAMJ0BQvCQC6AAAQAAMJ0BQvCQC6AAAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deadrat:BAAALgAECgUJBwAAAA==.Deathvader:BAAALgADCgYJBgAAAA==.Delaomega:BAABLgAECn8cAAIRAAgJ1QrmBwAWAQARAAgJ1QrmBwAWAQAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvor:BAABLgAECn8rAAMRAAkJSRXoCgBoAgARAAkJSRXoCgBoAgANAAEJcQHJOwEbAAAAAA==.Drash:BAABLgAECn8UAAISAAUJFwtfCwAJAQASAAUJFwtfCwAJAQAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.',
Du='Dumbledore:BAABLgAECn8WAAIRAAkJNBSMDQA1AgARAAkJNBSMDQA1AgAAAA==.Dumpnloads:BAAALgADCgEJAQAAAA==.Durotagg:BAAALgAECgQJBQAAAA==.',
['Dí']='Dím:BAAALgADCgYJCQAAAA==.',
Eg='Egres:BAAALgAECgMJBwAAAA==.',
El='Elemequation:BAAALgAECgEJAgAAAA==.Elfguy:BAAALgADCgYJDAAAAA==.',
En='Endléss:BAABLgAECn8XAAITAAcJ9xliDAAHAgATAAcJ9xliDAAHAgAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAADAAAAAA==.',
Er='Erbium:BAAALgAECgMJBAAAAA==.Eremetrii:BAEALgAECgUJCQAAAA==.',
Es='Esquandolas:BAAALgADCgEJAQAAAA==.',
Ev='Evotibs:BAABLgAECn8UAAIUAAYJQA3sBgAEAQAUAAYJQA3sBgAEAQAAAA==.',
Fi='Fibaldrachi:BAAALgAECgYJEgAAAA==.',
Fr='Frosting:BAAALgAECgQJEQAAAA==.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAAALgAECgYJDgAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgEJAQAAAA==.',
Gr='Grandall:BAAALgAECgEJAgAAAA==.Gruon:BAABLgAECn8UAAIVAAUJdwjVFAC1AAAVAAUJdwjVFAC1AAAAAA==.',
Gu='Gulzan:BAAALgAECgYJCwAAAA==.',
['Gø']='Gøkû:BAAALgAECgUJBQAAAA==.',
Ha='Hacks:BAAALgAECgYJEwAAAA==.Haymakerxd:BAAALgAECgQJCAAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJCQAAAA==.Helendir:BAAALgADCgIJAgAAAA==.',
Hu='Huntercobra:BAAALgADCgMJAwAAAA==.Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8XAAMGAAcJzRvhAwBQAgAGAAcJzRvhAwBQAgAHAAEJAABmfAAjAAAAAA==.Hypernova:BAAALgADCgMJAwAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAECgQJBAAAAA==.',
Id='Iden:BAAALgAECgMJAwAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAAALgAECgYJCwAAAA==.',
In='Infernal:BAAALgAECgYJCQAAAA==.Ingo:BAAALgADCgEJAQAAAA==.Inspiremoon:BAAALgAECgYJBwAAAA==.Interror:BAAALgAECgUJCQAAAA==.',
Ir='Iranos:BAABLgAECn8WAAIEAAgJFBm/KgB5AgAEAAgJFBm/KgB5AgAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCAAAAA==.Jaraxxus:BAAALgAECgUJCAABLgAECgYJDQADAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECgYJEQADAAAAAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgMJAwAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAECgYJEgADAAAAAA==.Kanakana:BAABLgAECn8cAAIQAAcJqxzUBwDOAQAQAAcJqxzUBwDOAQAAAA==.',
Ke='Kendana:BAAALgADCgUJCAAAAA==.Keyadron:BAAALgAECgEJAgAAAA==.',
Ki='Kindly:BAAALgADCgcJEAAAAA==.Kirab:BAAALgAECgYJDAAAAA==.Kirinmor:BAAALgADCgYJBgAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAAALgAECgYJBgAAAA==.',
Ko='Kosmos:BAAALgAECgEJAQABLgAECgYJBgADAAAAAA==.',
Kr='Kreid:BAAALgAECgUJCQAAAA==.Kreìd:BAAALgADCgEJAQABLgAECgUJCQADAAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8ZAAIWAAYJqRLTIAAGAQAWAAYJqRLTIAAGAQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8bAAMXAAkJ6Bj/CQDWAgAXAAkJ6Bj/CQDWAgAYAAUJahPoIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgADCgUJBQAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8WAAIZAAgJ1wl8KACVAQAZAAgJ1wl8KACVAQAAAA==.Linestia:BAAALgADCgQJBAABLgAECgUJCAADAAAAAA==.Littlewingz:BAAALgAECgYJDwAAAA==.',
Lo='Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgEJAQAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJAwABLgAECgUJBgADAAAAAA==.Maladreks:BAAALgADCgYJDgAAAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgMJBwADAAAAAA==.Mawz:BAAALgAECgYJCgAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAABLgAECn8dAAIaAAgJQCNpCQD8AgAaAAgJQCNpCQD8AgAAAA==.Meedlefinger:BAAALgAECgQJBQAAAA==.Melathia:BAAALgAECgYJDwAAAA==.Meliza:BAAALgAECgMJAwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.',
Mu='Musclebear:BAAALgAECgcJEQAAAA==.',
My='Mythaux:BAAALgADCgMJAwABLgAECgYJEgADAAAAAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Nahmeen:BAAALgAECgEJAQABLgAECggJJQAbAEIeAA==.',
Ne='Neero:BAAALgAECgYJEQAAAA==.Nelena:BAABLgAECn8WAAIQAAYJZgqpEwAWAQAQAAYJZgqpEwAWAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Nezhyt:BAAALgAECgYJEgAAAA==.',
Ni='Nicolbolas:BAABLgAECn8eAAMXAAgJvxfQBQChAQAXAAgJvxfQBQChAQAcAAIJewISRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAABLgAFFH8HAAIPAAMJuyLUAwDMAAAPAAMJuyLUAwDMAAABLgAFFAYJFAABAK0mAA==.Notorious:BAAALgAECgMJAwAAAA==.',
Nt='Ntaicen:BAAALgADCgIJAgAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAAALgAECgQJBAAAAA==.',
Pe='Pentasaurusr:BAABLgAECn8eAAMJAAcJSh+ZQAAMAgAJAAYJSh+ZQAAMAgAHAAIJ6BkUTACJAAAAAA==.',
Po='Pookkee:BAAALgAECgUJCAAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.',
Pp='Ppat:BAAALgAECgUJCAAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAAALgAECgYJEQAAAA==.',
Re='Recmod:BAAALgAECgYJEAAAAA==.Rendover:BAAALgAECgIJAQAAAA==.Return:BAABLgAECn8aAAIdAAgJ0x/gBQDXAgAdAAgJ0x/gBQDXAgAAAA==.',
Rh='Rhimeholt:BAAALgAECgYJDwAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJAgAAAA==.',
Ry='Ryahask:BAABLgAECn8VAAIPAAcJVQ6gAwCLAQAPAAcJVQ6gAwCLAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAABLgAECn8aAAIEAAgJ5BhuLwBlAgAEAAgJ5BhuLwBlAgAAAA==.Sammyshoes:BAAALgAECgYJCgAAAA==.Sanguine:BAAALgAECgQJBAAAAA==.',
Sc='Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seeturtle:BAABLgAECn8hAAMIAAgJqiAJAwD4AQAIAAcJeyAJAwD4AQABAAcJ3BuKFQCWAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.',
Sh='Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slippie:BAAALgAECgMJAwAAAA==.',
Sm='Smell:BAABLgAECn8iAAIEAAgJKRmlLgBoAgAEAAgJKRmlLgBoAgAAAA==.',
So='Solheim:BAAALgAECgYJCwAAAA==.',
Sp='Spacemonk:BAAALgAECgQJBQAAAA==.Spire:BAAALgAECgUJDQAAAA==.Sproutling:BAAALgAECgYJEwAAAA==.',
St='Stearphen:BAAALgAECgYJDgAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJBwAAAA==.',
Sw='Swazti:BAAALgAECgYJEAAAAA==.',
Ta='Tashir:BAAALgADCgcJBwAAAA==.Taurnil:BAABLgAECn8WAAIGAAYJUhCpDABtAQAGAAYJUhCpDABtAQAAAA==.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Ti='Timika:BAAALgAECgcJEQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAMJCQAXAPIZAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAAALgADCgkJFwAAAA==.',
Va='Vaeron:BAAALgAECgMJBQAAAA==.',
Ve='Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8WAAILAAkJxgplKgAPAgALAAkJxgplKgAPAgAAAA==.Venomsecho:BAABLgAECn8aAAIeAAgJ6RVoCQA9AgAeAAgJ6RVoCQA9AgAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgADCgYJBgAAAA==.',
We='Weathergirl:BAAALgAECgcJCgAAAA==.',
Wi='Winniethefu:BAABLgAECn8fAAIfAAgJ2BiYFwAEAgAfAAgJ2BiYFwAEAgAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAADAAAAAA==.',
Wy='Wy:BAAALgAECgEJAQAAAA==.',
Xa='Xanna:BAAALgAECgEJAQAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIFAAMJDRN2AQDBAAAFAAMJDRN2AQDBAAAuAAQKfyYAAgUACAmlItsCAPwCAAUACAmlItsCAPwCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yunàlestrà:BAAALgAECgQJCwAAAA==.',
Za='Zach:BAABLgAECn8UAAIBAAgJPhhrPACFAgABAAgJPhhrPACFAgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIfAAcJiwXfOwD4AAAfAAcJiwXfOwD4AAAAAA==.',
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
