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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Warlock-Demonology','Rogue-Subtlety','Evoker-Preservation','Mage-Frost','Warrior-Protection','Monk-Mistweaver','Druid-Balance','Monk-Brewmaster','Shaman-Restoration','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Shaman-Elemental','Shaman-Enhancement','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aeterna:BAAALgAECgQJBQAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECggJHAABACITAA==.Allure:BAABLgAECn8WAAMCAAYJGR4mDAC/AQACAAYJGR4mDAC/AQADAAQJ4QuSpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhpbEQBGAgAEAAgJyhpbEQBGAgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn8wAAIFAAgJ7BB4GwCtAQAFAAgJ7BB4GwCtAQAAAA==.Amoralibash:BAAALgAECgYJCwAAAA==.',
An='Anguskhan:BAAALgADCgMJBgAAAA==.Anhafel:BAABLgAECn8hAAIDAAYJtRRfSgAZAQADAAYJtRRfSgAZAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ap='Apocalipze:BAAALgADCgYJBgAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAQJCwAGALkXAA==.Arileous:BAAALgAECgUJBQAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.',
As='Asmoodeus:BAAALgAECgEJAgABLgAECggJHwAHAKoPAA==.Aspp:BAAALgAECgYJEQAAAA==.',
Au='Augpress:BAAALgAECgcJDQAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Bi='Bijou:BAAALgADCgkJIAAAAA==.',
Bl='Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgYJBwAAAA==.Blutopic:BAAALgADCgUJBwAAAA==.',
Br='Briar:BAAALgAECgEJAQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAAALgAECgQJBgAAAA==.Bucksdk:BAAALgAFFAEJAQAAAA==.Buckshotheal:BAAALgADCgYJBwABLgAFFAEJAQAIAAAAAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Cantmilkthis:BAAALgADCgIJAQAAAA==.Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJCQABLgAECggJHgAJAMQYAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgADCgkJGQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn8eAAMJAAgJxBiqCABRAgAJAAgJxBiqCABRAgAKAAUJEQa1QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgMJBAAIAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgYJCwAIAAAAAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJBgAAAA==.Dave:BAAALgAECggJEwABLgABCgIJAgAIAAAAAA==.',
De='Deathzdemize:BAACLgAFFH8iAAMLAAgJdyCeAACWAgALAAcJdyCeAACWAgAMAAEJAABrFABPAAAuAAQKfzIABAsACQmDJecAAN0DAAsACQmDJecAAN0DAAwABQnaJKYQAAACAA0ABAmDFVYNANgAAAAA.Decay:BAABLgAECn8oAAIOAAkJQx64CQCtAgAOAAkJQx64CQCtAgABLgAECgYJIQAHAPIlAA==.Demonbane:BAABLgAECn8gAAMCAAgJnhrQBwAbAgACAAgJnhrQBwAbAgADAAYJdAm3YwDXAAAAAA==.',
Di='Diancie:BAAALgADCgEJAQAAAA==.Dirtpear:BAAALgAECgcJEQAAAA==.',
Dr='Dragonaddon:BAAALgAECgUJBQAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAAALgAECgUJDgAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgMJBgAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDQAIAAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
En='Endymion:BAABLgAECn8YAAIFAAgJlhNsFADuAQAFAAgJlhNsFADuAQAAAA==.',
Et='Eternity:BAACLgAFFH8LAAIGAAQJuRczEQBVAQAGAAQJuRczEQBVAQAuAAQKfygAAgYACQkUIisMAOACAAYACQkUIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJAwAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECgcJCQAAAA==.',
Fa='Facetheclaw:BAAALgAECgUJBQABLgAECggJEQAIAAAAAA==.Facetheflame:BAAALgAECgEJAQABLgAECggJEQAIAAAAAA==.Facethegem:BAAALgAECggJEQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECggJEQAIAAAAAA==.Facethezoom:BAAALgADCgcJBwABLgAECggJEQAIAAAAAA==.Father:BAAALgAECgEJAQABLgAECgQJBQAIAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8FAAIDAAIJvRDxRgCVAAADAAIJvRDxRgCVAAAuAAQKfxcAAwMACQnYGGMSACoCAAMABwk5IGMSACoCAAIACQmXA0EqAHMBAAEuAAUUBgkTAA8A/hoA.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJCAAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8gAAIQAAgJGApXDwBKAQAQAAgJGApXDwBKAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.',
Fr='Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIRAAgJvAa3YwBKAQARAAgJvAa3YwBKAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8ZAAMBAAgJMhVeFgC1AQABAAgJwRReFgC1AQASAAEJSQn3OQAlAAAAAA==.',
Ga='Galairn:BAAALgADCggJCQAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8cAAIBAAgJIhPIFQC7AQABAAgJIhPIFQC7AQAAAA==.Gasaiyuno:BAAALgAECgYJDgAAAA==.',
Ge='Geves:BAAALgAECgUJDwAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAMJBgATAHcDAA==.',
He='Hedgehog:BAAALgAECgQJBwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAAALgAECgcJEwAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgYJDgAAAA==.Holyyoshi:BAABLgAECn8WAAIHAAgJCRGiVgDeAQAHAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Im='Impearsmoke:BAAALgADCgUJBQABLgAECgcJEQAIAAAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAIAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAAALgAECgUJBwAAAA==.',
Ja='Jab:BAABLgAECn8fAAIMAAcJPBA5GwDsAAAMAAcJPBA5GwDsAAAAAA==.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8cAAMLAAgJLhPgWwAuAQAMAAcJiBV1HABoAQALAAcJkgjgWwAuAQAAAA==.Jaspper:BAAALgAECgUJBQABLgAECggJHAALAC4TAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn8jAAIUAAcJ5iJdBwBhAgAUAAcJ5iJdBwBhAgAAAA==.Jinu:BAAALgAECgcJEQAAAA==.Jiéqu:BAABLgAECn8WAAIVAAYJSB+TEADEAQAVAAYJSB+TEADEAQAAAA==.',
Jo='Joker:BAABLgAECn8XAAIGAAcJAQd1VgALAQAGAAcJAQd1VgALAQAAAA==.Jomama:BAAALgAECgYJDQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNR8TBADCAgABAAkJNR8TBADCAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECgYJFgAVAEgfAA==.Kes:BAAALgAECgUJCgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAIAAAAAA==.',
Kr='Kristiani:BAAALgADCgIJAgAAAA==.',
La='Lad:BAAALgAECgQJBAAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgADCgcJDAAAAA==.',
Le='Leaffy:BAAALgAECgEJAgABLgAECggJGwAWAPQZAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECgMJBQAAAA==.',
Li='Lilthiccy:BAAALgADCgUJBQABLgAECgYJDQAIAAAAAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Meliôdas:BAAALgAECgEJBQAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgADCgMJAwABLgAECgcJBwAIAAAAAA==.Mooädib:BAAALgAECgEJAQAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwAAAA==.Mysteia:BAABLgAECn8fAAITAAgJWxzZCQBQAgATAAgJWxzZCQBQAgAAAA==.',
['Mà']='Màkina:BAAALgAECgYJEwAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgEJAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAQJCwAGALkXAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8VAAMHAAYJRxWxngBBAQAHAAYJMhSxngBBAQAXAAQJ0wcKMgCFAAABLgAFFAIJAgAIAAAAAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAIJAgAIAAAAAA==.',
Ni='Nihilist:BAABLgAECn8ZAAIMAAgJpxsMCwDFAQAMAAgJpxsMCwDFAQAAAA==.Nimbuss:BAAALgAECgcJDAAAAA==.Nitequilz:BAABLgAECn8mAAIWAAgJnx6wCAChAgAWAAgJnx6wCAChAgAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJGwAAAA==.Obijuan:BAAALgAECgUJCwAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAAALgAECgUJDAAAAA==.Outcastbrew:BAABLgAECn8UAAIVAAgJ+SFuBwAOAwAVAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pi='Pine:BAAALgAECgYJDwAAAA==.',
Pl='Plateguy:BAAALgADCgQJAwAAAA==.',
Po='Poxx:BAAALgAECgQJBAABLgAFFAYJEwAPAP4aAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgMJAwAAAA==.Raksi:BAAALgADCgIJAgAAAA==.Ranker:BAAALgADCgQJBQAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8GAAMTAAMJdwOvGwCdAAATAAMJdwOvGwCdAAAVAAIJAQhNNABtAAAAAA==.Rhayvoke:BAABLgAECn8XAAQYAAcJyxc0HQDdAQAYAAcJkxc0HQDdAQAQAAMJ2gtuOgCWAAAZAAEJGRllOgBHAAABLgAFFAMJBgATAHcDAA==.',
Ri='Rills:BAAALgAECgEJAQAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAAALgAFFAIJBAABLgAFFAgJIgALAHcgAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAIAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8kAAIKAAgJTRkqDQD2AQAKAAgJTRkqDQD2AQAAAA==.Rynron:BAAALgAECgQJBgAAAA==.',
Sa='Sabeatris:BAAALgAECgUJCAAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAAALgAECgQJCQAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgcJDwAIAAAAAA==.',
Se='Sempiternal:BAACLgAFFH8LAAIFAAQJ/A4pEwAaAQAFAAQJ/A4pEwAaAQAuAAQKfy8AAgUACQlOEVEtAM8BAAUACQlOEVEtAM8BAAAA.',
Sh='Shadowsmite:BAAALgAECggJEgAAAA==.Shaunanigans:BAAALgAECgYJBwAAAA==.Shaunsdh:BAAALgAECgEJAQABLgAECgYJBwAIAAAAAA==.Shaunwick:BAAALgAECgQJBAABLgAECgYJBwAIAAAAAA==.Shego:BAABLgAECn8UAAMLAAcJQiGyMQBxAgALAAcJOiCyMQBxAgAMAAIJHSLALABpAAAAAA==.Sheltered:BAABLgAECn8hAAIHAAYJ8iUdHAAfAgAHAAYJ8iUdHAAfAgAAAA==.',
Si='Sinadora:BAAALgAECgUJAgAAAA==.Sinakra:BAABLgAECn8fAAIHAAgJqg+HPgCKAQAHAAgJqg+HPgCKAQAAAA==.',
Sl='Slapdaddy:BAAALgADCgkJGAAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8TAAIPAAYJ/hqCAwCiAQAPAAYJ/hqCAwCiAQAuAAQKfx8AAg8ACQmVJAECAJcDAA8ACQmVJAECAJcDAAAA.',
Sp='Spritz:BAAALgAECgUJCQAAAA==.',
St='Stampede:BAAALgADCggJFgAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgIJAgAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Straya:BAABLgAECn8aAAIWAAgJeBIOHADRAQAWAAgJeBIOHADRAQAAAA==.',
Ta='Tahirrah:BAABLgAECn8YAAIGAAgJXhUVJADFAQAGAAgJXhUVJADFAQAAAA==.Talindra:BAABLgAECn8VAAIMAAgJaQbIGgDwAAAMAAgJaQbIGgDwAAAAAA==.Tanis:BAAALgAECgEJAgAAAA==.',
Te='Temperånce:BAABLgAECn8wAAMEAAkJ7AxOMABfAQAEAAkJ7AxOMABfAQAaAAgJKgnjCwBaAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJBQAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgADCgEJAgAAAA==.Thumpers:BAAALgADCgYJEQAAAA==.',
Ti='Tino:BAABLgAECn8iAAIFAAgJfh77EwBzAgAFAAgJfh77EwBzAgAAAA==.',
Tm='Tmnt:BAAALgAECgcJEAAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8XAAQbAAgJug/VJQAqAQAbAAcJvQ/VJQAqAQAWAAMJvxrvRQDqAAAcAAQJgQpjGQBrAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJDwAAAA==.',
Ts='Tsilihin:BAAALgAECgEJAQAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgATAA0eAA==.Tsurenity:BAACLgAFFH8GAAITAAIJDR6nDgCyAAATAAIJDR6nDgCyAAAuAAQKfxkAAhMACAm+IjAEACwDABMACAm+IjAEACwDAAAA.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAECggJBAABLgAECggJIAATAFILAA==.',
Va='Valerus:BAAALgAECgMJBAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAgJHAATAMAYAA==.Varr:BAAALgAECgMJAwAAAA==.Vayeda:BAABLgAECn8hAAIRAAgJBCMlDAC/AgARAAgJBCMlDAC/AgAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAIJAgAIAAAAAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAQAAAA==.',
Xe='Xetz:BAAALgAECgQJCgAAAA==.Xezar:BAACLgAFFH8LAAQKAAUJRwjBDADeAAAKAAQJRwjBDADeAAAJAAIJ2AUZJgBQAAAdAAEJgAf2HQBJAAAuAAQKfyEABAoACQkLGy0PAJECAAoACQkLGy0PAJECAB0ABwnrHJgWACcCAAkAAwmXH8YyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn8hAAMRAAgJBQ0eTgB/AQARAAgJBQ0eTgB/AQAeAAQJpwNnFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAABLgAECn8cAAIJAAgJGxMwFACgAQAJAAgJGxMwFACgAQAAAA==.',
Za='Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zeroh:BAAALgAECgYJDQAAAA==.',
Zi='Zigzagger:BAAALgAECgQJBgAAAA==.',
Zn='Zna:BAAALgAECgUJBgAAAA==.',
['Øø']='Øø:BAAALgAECgYJEAAAAA==.',
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
