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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Evoker-Preservation','Warlock-Destruction','Warlock-Demonology','Paladin-Protection','Warrior-Protection','Druid-Guardian','Druid-Feral','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','Warlock-Affliction','Warrior-Arms','Monk-Mistweaver','Priest-Shadow','Paladin-Retribution','DeathKnight-Frost','DemonHunter-Devourer','Shaman-Enhancement','Monk-Windwalker','Rogue-Subtlety','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','Monk-Brewmaster','Druid-Balance','Paladin-Holy','Druid-Restoration','Rogue-Outlaw','Priest-Holy','Priest-Discipline','DemonHunter-Havoc','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaliyah:BAAALgADCgUJBQAAAA==.',
Ab='Abnah:BAAALgAECgYJBwAAAA==.',
Ac='Acacia:BAAALgADCgcJCAAAAA==.Acesso:BAAALgAECgQJBgAAAA==.',
Ad='Adeonatus:BAAALgAECgYJDAAAAA==.',
Ae='Aecheron:BAAALgAECgIJAwABLgAECgQJBQABAAAAAA==.Aeliniani:BAAALgAECgQJCAAAAA==.Aellis:BAAALgAECgMJAwAAAA==.Aelvion:BAAALgAECgcJEwAAAA==.Aewep:BAAALgADCgcJBwAAAA==.',
Ag='Agronon:BAAALgAECgIJAgAAAA==.',
Ah='Ahsterius:BAAALgAECgEJAQAAAA==.',
Ai='Aimtokill:BAABLgAECn8fAAICAAgJMhsbIABFAgACAAgJMhsbIABFAgABLgADCgYJDAABAAAAAA==.Air:BAAALgAECgYJDgAAAA==.',
Ak='Akaruianubis:BAAALgADCgYJBgAAAA==.Akidao:BAAALgAECgYJCgAAAA==.',
Al='Alamír:BAAALgAECgEJAQAAAA==.Alastor:BAAALgADCggJCAAAAA==.Alchio:BAAALgADCgUJDQAAAA==.Alderian:BAAALgAECgQJBgAAAA==.Aldáron:BAAALgADCgUJBwAAAA==.Alexhunt:BAACLgAFFH8VAAMCAAYJqBxFAQCVAQACAAQJnyFFAQCVAQADAAUJERM8BADFAAAuAAQKfykABAIACQmaIzQMAOACAAIACAk2ITQMAOACAAQACAkoH7cEAMcCAAMACAlaIpQRAKoCAAAA.Alexmages:BAAALgAFFAMJAwABLgAFFAYJFQACAKgcAA==.Alexmonks:BAAALgAECgYJBwABLgAFFAYJFQACAKgcAA==.Alexpriest:BAAALgAECgEJAQABLgAFFAYJFQACAKgcAA==.Alexrogues:BAAALgADCgMJAwABLgAFFAYJFQACAKgcAA==.Alinth:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Alisaie:BAAALgADCgcJCgAAAA==.Allaris:BAAALgADCgcJDgAAAA==.Alleralle:BAAALgADCgQJBAAAAA==.Alphacurse:BAAALgAECgEJAQAAAA==.Alplarn:BAAALgAECgUJCAAAAA==.Altero:BAAALgAECgcJBwABLgAECggJLAAFAEMNAA==.Althsar:BAAALgADCgEJAQAAAA==.Alvaru:BAAALgADCgEJAQAAAA==.',
Am='Amandalin:BAAALgADCgkJCQAAAA==.Amanuk:BAAALgAECgEJAQAAAA==.Amitie:BAAALgADCgkJCQAAAA==.Amorlorisy:BAAALgADCgkJCQABLgAECgIJAgABAAAAAA==.',
An='Anahith:BAAALgADCgEJAQAAAA==.Andromebruh:BAAALgADCgMJAwAAAA==.Angelcain:BAAALgAECgUJCAAAAA==.Angelest:BAAALgADCgUJBQAAAA==.Anitwa:BAAALgAECgYJCgAAAA==.Anointed:BAAALgADCgQJBAAAAA==.Anomari:BAAALgADCgcJCgAAAA==.Anteritum:BAAALgAECgcJDQAAAA==.Antivaxer:BAABLgAECn8dAAMGAAgJZyJfAQAWAwAGAAgJZyJfAQAWAwAHAAEJ0QK6LwEhAAAAAA==.',
Ap='Apkuggull:BAAALgADCgQJBAAAAA==.Apothecus:BAAALgADCgUJBQAAAA==.Applejakx:BAAALgAECgQJBAAAAA==.Apsylar:BAAALgAECgQJBQAAAA==.',
Ar='Arandiel:BAAALgADCgYJBgAAAA==.Aranina:BAAALgAECgQJCAAAAA==.Arcuss:BAAALgAECgYJBgABLgAFFAUJEwAIAHckAA==.Argoliath:BAAALgAECgQJCAAAAA==.Arimas:BAAALgAECgEJAQAAAA==.Arisen:BAAALgADCgIJAgAAAA==.Arkenox:BAAALgADCgIJAgAAAA==.Arrwyn:BAAALgAECgIJAgABLgAFFAUJFAAJAHIfAA==.Artemois:BAAALgAECgEJAQAAAA==.Articdemon:BAAALgADCgIJAgAAAA==.Artilleri:BAAALgAECgMJAwAAAA==.',
As='Asandi:BAAALgAECgIJAwAAAA==.Asatralth:BAAALgAECgYJEAAAAA==.Ascoobis:BAAALgAECgYJDwAAAA==.Asheryo:BAAALgADCgQJBQAAAA==.Ashè:BAAALgADCgcJBwAAAA==.Assphyxiate:BAAALgADCgMJBAAAAA==.Astandia:BAAALgADCgcJDQAAAA==.',
At='Athenz:BAAALgADCgMJAwAAAA==.',
Au='Auntiemmy:BAAALgADCgUJBQAAAA==.Auðr:BAAALgADCggJDQAAAA==.',
Ay='Aymine:BAABLgAECn8VAAMKAAcJUB2gDAC/AQAKAAUJdB+gDAC/AQALAAYJGxjuFwBAAQAAAA==.Ayroon:BAAALgADCgIJAgAAAA==.',
Az='Azunä:BAAALgADCgQJBAAAAA==.',
Ba='Baabayaga:BAAALgADCgEJAQAAAA==.Babihotdog:BAAALgAECgYJCgAAAA==.Babylego:BAAALgAECgYJCwABLgAFFAYJEwAMAGwdAA==.Baddragõn:BAABLgAECn8gAAQNAAgJtxXBFQAsAgANAAgJtxXBFQAsAgAFAAgJIBXIEgAUAgAOAAMJNA5cMACUAAABLgAECggJGQAHALYeAA==.Badmir:BAAALgADCgcJFAAAAA==.Badwolff:BAAALgAECgMJBQAAAA==.Baerog:BAAALgAECgQJCgAAAA==.Bahleil:BAAALgADCgMJAgAAAA==.Bajheera:BAAALgAECgYJBwABLgAECgcJCAABAAAAAA==.Bandaidzz:BAAALgADCgYJBwAAAA==.Banf:BAAALgAECgUJDQAAAA==.Baodabao:BAACLgAFFH8QAAIPAAQJexe3CABbAQAPAAQJexe3CABbAQAuAAQKfywAAw8ACAlDInM9AIICAA8ACAlDInM9AIICABAAAQnoGwAcADwAAAAA.Baodibao:BAAALgAECgQJBAAAAA==.Baokemeng:BAAALgADCgEJAQAAAA==.Baptism:BAAALgADCgcJBwAAAA==.Barbiequeue:BAAALgAECgcJEAAAAA==.Basillock:BAAALgADCgMJAwAAAA==.Bater:BAABLgAECn8UAAIRAAkJHA24aQC5AQARAAkJHA24aQC5AQAAAA==.Batguy:BAAALgADCgEJAQAAAA==.Bawana:BAAALgAECgQJBwAAAA==.Baycon:BAAALgAECgYJDgAAAA==.',
Be='Beammiah:BAAALgADCgQJBAAAAA==.Beanslol:BAAALgADCgYJBgAAAA==.Bearbella:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.Bearsizepope:BAAALgADCgIJAgAAAA==.Beciala:BAAALgADCgYJDAAAAA==.Beelzaboot:BAABLgAECn8ZAAIHAAgJth7aBQAXAgAHAAgJth7aBQAXAgAAAA==.Beepah:BAAALgAECgQJBwAAAA==.Beepbeepbeep:BAAALgADCgIJAgAAAA==.Belanor:BAABLgAECn8nAAIMAAgJ5RybAgA1AgAMAAgJ5RybAgA1AgAAAA==.Belrain:BAAALgADCgMJAwAAAA==.Berry:BAABLgAECn8iAAIKAAkJPSNSAQBIAwAKAAkJPSNSAQBIAwAAAA==.Bertilak:BAAALgAECgQJCAAAAA==.Betrayer:BAAALgADCgcJDAAAAA==.Beudreaux:BAAALgAECgUJCQABLgAECgYJDAABAAAAAA==.',
Bi='Bigbahungas:BAAALgAECgcJDgAAAA==.Bigdamfury:BAAALgADCgcJBwAAAA==.Biglebroski:BAAALgAECgQJBAAAAA==.Bigload:BAAALgAECgYJCwAAAA==.Bignipsmcgee:BAAALgAECgQJBQAAAA==.Bigpumper:BAAALgAECgMJAwAAAA==.Bigstepladdr:BAAALgAECgMJBAAAAA==.Bigwîlly:BAAALgADCgYJBgAAAA==.Bigwïlly:BAAALgAECgIJAgAAAA==.Billibones:BAAALgAECgYJDgAAAA==.Binebine:BAAALgADCgIJAgAAAA==.Bingisdingis:BAAALgAECgYJBgAAAA==.Biolimit:BAABLgAECn8UAAQGAAgJ+hwsBgBtAgAGAAcJ7x8sBgBtAgAHAAMJpQsn2wCjAAASAAEJFSFvKABPAAAAAA==.Bixxnogath:BAAALgAECgMJBgAAAA==.',
Bl='Blacktastic:BAAALgAECgYJCgAAAA==.Blaith:BAAALgAECgMJBQAAAA==.Blastee:BAABLgAECn8cAAMCAAgJ1SExDgDLAgACAAgJ1SExDgDLAgADAAEJkg3gjQAtAAAAAA==.Bleudrius:BAAALgADCgUJCQAAAA==.',
Bo='Bonknika:BAAALgAECgQJBAAAAA==.Bono:BAAALgADCgQJBAAAAA==.Boonney:BAAALgAECggJEAAAAA==.Bossdragoon:BAAALgADCgcJBwAAAA==.',
Br='Brewfroster:BAAALgADCgUJBQABLgADCgUJBQABAAAAAA==.Brewparz:BAAALgADCgEJAQABLgADCgUJBQABAAAAAA==.Brewschi:BAAALgADCgEJAQAAAA==.Brewtality:BAAALgADCgMJAwAAAA==.Broggdrasil:BAAALgADCgEJAQAAAA==.Brolek:BAAALgADCgEJAQAAAA==.Bronlai:BAAALgADCgEJAQAAAA==.Bronzehoofs:BAAALgAECgEJAQAAAA==.Browen:BAAALgAECgYJDQABLgAECggJHQATADIdAA==.',
Bu='Bubbydubs:BAAALgAECgYJCwAAAA==.Buffchadwell:BAAALgAECgIJAgAAAA==.Busti:BAAALgAECgMJBAAAAA==.',
Bw='Bwoodmorgan:BAAALgAECgYJCAAAAA==.',
Ca='Cahoots:BAAALgAECgcJDwABLgAFFAMJBgAUAEINAA==.Cahri:BAAALgADCgYJBgAAAA==.Cairdis:BAAALgAECgUJBQAAAA==.Calamitea:BAABLgAECn8YAAIVAAgJxQk0JAC2AQAVAAgJxQk0JAC2AQAAAA==.Callmemissak:BAAALgADCgYJCgAAAA==.Camyr:BAAALgAECgcJDwAAAA==.Canon:BAAALgAECgQJBAAAAA==.Capsloxx:BAABLgAECn8fAAIHAAgJ9A31EwBxAQAHAAgJ9A31EwBxAQAAAA==.Carchàroth:BAAALgADCgIJAgAAAA==.Carriongolem:BAAALgADCgUJBQAAAA==.Catacombs:BAAALgADCgYJBgAAAA==.Cathio:BAAALgAECgYJCgAAAA==.Cazel:BAAALgADCgcJBwAAAA==.Cazualty:BAAALgADCgYJCQAAAA==.',
Ce='Ceevee:BAAALgADCgEJAQAAAA==.Celasong:BAAALgAECgMJAwAAAA==.Celticpali:BAAALgAECgIJAgAAAA==.',
Ch='Chance:BAAALgAECgEJAQAAAA==.Charavia:BAAALgADCgMJAgAAAA==.Cheeseydruid:BAAALgAECgEJAQAAAA==.Chesty:BAAALgADCgUJBQAAAA==.Chibis:BAAALgAECgMJAwAAAA==.Chilimbalam:BAAALgADCgcJCgAAAA==.Chippedbeef:BAAALgAECgEJAQAAAA==.Chirott:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Chiwi:BAAALgADCgEJAQAAAA==.Chocogeta:BAAALgAECgMJAwAAAA==.Chordius:BAAALgAECgMJBgABLgAECgUJCQABAAAAAA==.Chrispeacox:BAAALgADCgQJBQAAAA==.Chuckfinley:BAABLgAECn8gAAIWAAkJnROnSwAAAgAWAAkJnROnSwAAAgAAAA==.',
Ci='Cileymyrus:BAAALgADCgcJBwAAAA==.Circeka:BAAALgADCgEJAQAAAA==.Cirrusdawn:BAAALgAECgUJDAAAAA==.Ciskà:BAAALgAECgEJAQAAAA==.',
Cl='Cladow:BAAALgAECgEJAQAAAA==.Clag:BAAALgADCgYJCQAAAA==.',
Cm='Cmtwopercent:BAAALgAECgYJBgAAAA==.',
Co='Coldsteak:BAAALgADCgUJBQAAAA==.Coleridge:BAAALgADCgEJAQAAAA==.Conqor:BAAALgAECgcJAQAAAA==.Cootiegobble:BAAALgADCgIJAgAAAA==.Copepatch:BAABLgAECn8aAAIWAAcJXB9tMQBdAgAWAAcJXB9tMQBdAgAAAA==.Cosmicshaman:BAAALgAECgYJEAAAAA==.Cowout:BAAALgADCgQJBAAAAA==.',
Cr='Craigory:BAAALgADCggJDgAAAA==.Creasie:BAAALgAECgIJAwAAAA==.Crescendoll:BAAALgAECgQJBQABLgAECggJIgACAN8UAA==.Crossyx:BAAALgADCgYJCAAAAA==.Cruelerr:BAAALgADCgUJCQABLgAECggJHAAIAOEWAA==.Crushgroove:BAABLgAECn8VAAIMAAgJTwgPQgCcAQAMAAgJTwgPQgCcAQAAAA==.Crustacean:BAAALgAECgMJAwAAAA==.Cryptosec:BAAALgAECgEJAwAAAA==.Crìxús:BAEBLgAECn8aAAIMAAcJjSTJGACFAgAMAAcJjSTJGACFAgAAAA==.',
Cu='Cuckliddell:BAABLgAECn8ZAAIWAAcJZyHtCQDtAQAWAAcJZyHtCQDtAQAAAA==.Culpritz:BAAALgADCgIJAgAAAA==.Curanne:BAAALgADCgMJAwAAAA==.Cursedmango:BAAALgAECgQJBAAAAA==.',
Cy='Cyndrin:BAAALgAFFAMJBAAAAA==.Cypriest:BAAALgAECgEJAQAAAA==.',
Da='Daddi:BAABLgAECn8VAAIEAAYJrAugFwBRAQAEAAYJrAugFwBRAQAAAA==.Daddyfatsaks:BAAALgAECgEJAQAAAA==.Daerper:BAACLgAFFH8HAAIXAAMJOQ8RAQAFAQAXAAMJOQ8RAQAFAQAuAAQKfyIAAhcACAkZHnsCAJICABcACAkZHnsCAJICAAAA.Danayro:BAAALgADCgUJBQAAAA==.Dangernoddle:BAAALgADCgIJAgAAAA==.Darg:BAAALgAECgQJBgAAAA==.Darklego:BAACLgAFFH8TAAMMAAYJbB1iAQDzAQAMAAUJKyNiAQDzAQATAAEJcQYrBgBWAAAuAAQKfxwAAwwACAnzI7UOAN4CAAwABwlnJbUOAN4CABMABAmhItIPAJ8BAAAA.Darknite:BAAALgAFFAIJBAABLgAFFAUJFAAJAHIfAA==.Darkpole:BAAALgAECgkJDgABLgAFFAYJEAAHAMMhAA==.Darksign:BAAALgAECgQJBAAAAA==.Dasarran:BAAALgADCgMJAwABLgAECgYJDgABAAAAAA==.Davemage:BAAALgAECgQJBAAAAA==.Davidpaine:BAAALgAECgUJCQABLgAECgcJGQAWAGchAA==.',
De='Deadshif:BAAALgADCgEJAgAAAA==.Deathamoz:BAAALgADCgUJBQAAAA==.Deathflame:BAAALgADCgYJCAAAAA==.Deathmoo:BAAALgADCgIJAgAAAA==.Deathzeil:BAAALgAECgEJAQAAAA==.Decitt:BAAALgADCgcJAQAAAA==.Delillama:BAAALgADCgcJBwAAAA==.Dementik:BAAALgAECgIJAgAAAA==.Demeriel:BAAALgAECgYJDAAAAA==.Demolior:BAAALgADCgkJDwAAAA==.Demonlego:BAAALgAECgQJBAABLgAFFAYJEwAMAGwdAA==.Demonsita:BAAALgADCgEJAQABLgAECgcJFgAPAEIbAA==.Demonzong:BAAALgAECgYJEwAAAA==.Dendrometa:BAAALgADCgkJGQAAAA==.Deniron:BAAALgAECgIJAgAAAA==.Denkai:BAABLgAECn8ZAAIPAAgJVxxyWAAwAgAPAAgJVxxyWAAwAgAAAA==.Denzite:BAAALgAECgQJBQABLgAECggJGQAPAFccAA==.Derfla:BAAALgADCgUJBQAAAA==.Derkdigler:BAAALgADCgcJBwAAAA==.Destnny:BAAALgAECgEJAQAAAA==.',
Di='Dillpo:BAABLgAECn8eAAIWAAgJEyPTEwD0AgAWAAgJEyPTEwD0AgAAAA==.Dimitrea:BAABLgAECn8gAAIYAAgJeB+nGQC6AgAYAAgJeB+nGQC6AgAAAA==.Dioress:BAAALgAECgUJDgAAAA==.Dirtytramp:BAAALgADCgYJCQAAAA==.Dis:BAABLgAECn8ZAAQGAAgJthIkIABRAQAHAAcJsA62bgCDAQAGAAUJcBEkIABRAQASAAEJBhfrKwBHAAABLgAFFAUJEQAZAIQfAA==.Discabled:BAAALgAECgQJBAAAAA==.Diyanå:BAABLgAECn8VAAICAAYJOhsyDwCJAQACAAYJOhsyDwCJAQAAAA==.',
Dj='Djack:BAAALgADCgEJAQAAAA==.Djdrac:BAAALgADCggJEQAAAA==.',
Do='Dolphinzz:BAAALgADCgcJDQAAAA==.Domainsita:BAABLgAECn8WAAIPAAcJQhuJVgA1AgAPAAcJQhuJVgA1AgAAAA==.Donze:BAAALgAECgYJDQABLgAFFAQJDAAaAPYJAA==.Donzm:BAACLgAFFH8MAAMaAAQJ9glpAgAfAQAaAAQJ9glpAgAfAQAUAAMJtwPIDQDEAAAuAAQKfxwAAxQACAmcCooxADQBABQABwnaCooxADQBABoABAkkGcI6ADIBAAAA.Dorkan:BAAALgAECgQJCAAAAA==.Double:BAAALgADCgcJDgAAAA==.Doublestuf:BAAALgAECgMJBAAAAA==.Doughbeam:BAAALgADCgUJCwABLgAFFAUJCwAYAGYNAA==.',
Dr='Dracthick:BAAALgAECgYJEQAAAA==.Dragil:BAAALgADCgUJBQAAAA==.Dragofenix:BAAALgAECgYJCgAAAA==.Dragonbender:BAEALgAECgUJCgAAAA==.Dragonchan:BAABLgAECn8fAAIYAAgJOCEjBABSAgAYAAgJOCEjBABSAgAAAA==.Drakunal:BAAALgAECgUJBwAAAA==.Dralnya:BAAALgAECgYJCgAAAA==.Dreamender:BAAALgAECgYJEQAAAA==.Dreamweaver:BAAALgADCgYJCgAAAA==.Droknor:BAAALgAECgUJDwAAAA==.Drpiranha:BAABLgAECn8XAAIRAAcJPB5NQAA3AgARAAcJPB5NQAA3AgAAAA==.Druidic:BAAALgADCgEJAQAAAA==.Druidllama:BAAALgAECgYJEwAAAA==.Druindar:BAAALgADCgMJAwABLgAECggJJwAMAOUcAA==.Druqs:BAAALgAECgEJAQAAAA==.Drxvo:BAAALgADCgYJBwAAAA==.Dryleaf:BAAALgAECgQJBAAAAA==.Drágon:BAAALgADCgEJAgAAAA==.',
Du='Dudewithpets:BAAALgADCgYJCAAAAA==.Durahar:BAABLgAECn8YAAIPAAgJ5At2hADIAQAPAAgJ5At2hADIAQAAAA==.Duskfallen:BAAALgADCgIJAgAAAA==.',
Dy='Dyspo:BAAALgADCgIJAQAAAA==.',
Eb='Ebbur:BAAALgAECgIJAgAAAA==.',
Ed='Edir:BAAALgADCggJCAAAAA==.',
El='Elderian:BAAALgAECgcJEAAAAA==.Elemenope:BAAALgAECgUJCgAAAA==.Elesa:BAAALgADCgQJBQAAAA==.Elfondeu:BAAALgAECgMJBwAAAA==.Elguasonbb:BAAALgADCgUJBQAAAA==.Elidori:BAABLgAECn8dAAIbAAYJOBgbJwC/AQAbAAYJOBgbJwC/AQAAAA==.Elitegamerx:BAAALgAECgQJCgAAAA==.Elmerfuudd:BAAALgADCgYJBgAAAA==.Elpuchita:BAAALgADCgIJAgAAAA==.Elrich:BAAALgAECgQJCgAAAA==.Elska:BAAALgADCgMJAwAAAA==.',
Em='Emashasha:BAAALgAECgUJCQAAAA==.Emmabeth:BAAALgADCgIJAgAAAA==.',
En='Engelbert:BAABLgAECn8UAAIQAAYJSx3IAwAjAgAQAAYJSx3IAwAjAgAAAA==.Envari:BAAALgADCgQJBQAAAA==.Enyeto:BAABLgAECn8dAAITAAgJMh2LBACkAgATAAgJMh2LBACkAgAAAA==.',
Eq='Equinemayo:BAAALgADCggJCAAAAA==.',
Er='Eriara:BAAALgADCgUJBQAAAA==.Ermaghaku:BAAALgAECgQJBQAAAA==.Ermbear:BAAALgAECgcJCQAAAA==.Ermy:BAAALgADCgIJAgAAAA==.Eroder:BAAALgAECgEJAQAAAA==.Erodrelae:BAAALgAECgMJAwAAAA==.Eroviaevia:BAAALgAECgQJBAAAAA==.',
Et='Etard:BAAALgAECgEJAQAAAA==.Etyr:BAAALgADCgMJAwAAAA==.',
Ev='Evanahumpyou:BAAALgAECgUJBQAAAA==.',
Ex='Excedrino:BAAALgAECgMJAwAAAA==.Exemplary:BAABLgAECn8lAAIWAAgJDyKfBQA9AgAWAAgJDyKfBQA9AgAAAA==.Existenz:BAAALgADCgEJAQAAAA==.Extravaganzá:BAAALgAECgQJEAAAAA==.Exyled:BAAALgAECgQJBgAAAA==.',
Ez='Ezekeel:BAAALgAECgYJEwAAAA==.',
Fa='Facilis:BAAALgAECgUJBgAAAA==.Fakelock:BAAALgAECgYJCwAAAA==.Fathôm:BAABLgAECn8WAAIcAAYJOhPEQwA5AQAcAAYJOhPEQwA5AQAAAA==.Favolla:BAAALgAECggJDAAAAA==.',
Fe='Felburner:BAAALgADCgUJBQAAAA==.Felgazelle:BAAALgAECgQJBAAAAA==.Felshaman:BAAALgADCgcJCAAAAA==.Felvein:BAAALgAECgEJAgAAAA==.Fendroth:BAAALgAECgYJCAAAAA==.',
Fi='Fifi:BAAALgADCgQJBAAAAA==.Firestack:BAAALgADCgMJAwAAAA==.Fiskerton:BAAALgADCgQJBAABLgAFFAMJCAAcAB8cAA==.',
Fl='Flamefenix:BAAALgAECgUJBgAAAA==.Florabella:BAAALgAECgIJAgAAAA==.Flurpymcdoof:BAAALgAECgYJBwAAAA==.',
Fo='Forbiddyn:BAABLgAECn8eAAMHAAgJcRdtRAD+AQAHAAcJcRdtRAD+AQAGAAIJ4hPvTACHAAAAAA==.Forlash:BAABLgAECn8UAAIHAAYJIgvwLwDHAAAHAAYJIgvwLwDHAAAAAA==.Forsa:BAAALgAECgEJAQAAAA==.Fotmheals:BAAALgAECgcJCAABLgAFFAcJGgAFABEXAA==.Foxiefoxy:BAAALgADCgkJEQAAAA==.Foxikins:BAABLgAECn8UAAIWAAYJXxspBwGIAAAWAAYJXxspBwGIAAAAAA==.',
Fr='Frawnix:BAAALgAECgQJBAAAAA==.Freyasflight:BAAALgAECgMJAwAAAA==.Freyjá:BAAALgAECgYJBgAAAA==.Frostflight:BAAALgADCgYJBgAAAA==.Frostgoblin:BAAALgADCgEJAQAAAA==.Frystealer:BAAALgADCgYJBgAAAA==.',
Fu='Furidas:BAABLgAECn8XAAIJAAcJDh4qDABJAgAJAAcJDh4qDABJAgAAAA==.Furry:BAAALgAECgMJAwAAAA==.Fuse:BAAALgAECgEJAgAAAA==.',
Fy='Fyrload:BAAALgADCgYJCQAAAA==.',
['Fö']='Föxfïre:BAAALgADCgYJCQAAAA==.',
Ga='Gagetko:BAAALgAECgYJDAAAAA==.Galaz:BAABLgAECn8jAAIdAAgJMyFTAQC3AgAdAAgJMyFTAQC3AgAAAA==.Galdèus:BAABLgAECn8aAAMYAAcJ3wslIgD9AAAYAAcJ3wslIgD9AAAeAAMJJATSJwBIAAAAAA==.Galedyr:BAAALgADCgIJAQABLgAECggJGQAfAEAhAA==.Gallade:BAAALgADCgMJAgAAAA==.Gallya:BAAALgAECgYJDQAAAA==.Gallyy:BAAALgAECgQJBAAAAA==.Ganon:BAAALgADCgcJBwAAAA==.Garddonntog:BAAALgADCgMJAwAAAA==.Garogg:BAABLgAECn8VAAIJAAgJFhwTEAAHAgAJAAgJFhwTEAAHAgAAAA==.Garotomoreno:BAAALgADCgcJEwAAAA==.Gaulis:BAAALgAECgYJCgAAAA==.',
Ge='Gehena:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.Gelin:BAABLgAECn8YAAIWAAYJfxF1IAAsAQAWAAYJfxF1IAAsAQAAAA==.Gelthalos:BAAALgAECgYJCgAAAA==.Gelthildris:BAAALgAECgUJBgAAAA==.Gertzunter:BAAALgADCgUJBwAAAA==.Geøffknight:BAAALgADCgEJAQAAAA==.',
Gh='Ghostfacewon:BAAALgAECgcJBgAAAA==.Ghztlly:BAAALgADCgIJAgAAAA==.',
Gi='Giggleshammy:BAAALgADCgEJAQAAAA==.Gigih:BAAALgADCgkJEQAAAA==.Giilvas:BAAALgAECgYJCQABLgAECggJJwAMAOUcAA==.Giirthquakee:BAAALgADCgIJAgABLgAECgQJBQABAAAAAA==.Gilthunder:BAAALgAECgYJEQAAAA==.Girlyouthicc:BAAALgAECgYJDwAAAA==.Girthbrøøks:BAAALgADCgMJBAABLgAECggJHAAcAAkYAA==.',
Gl='Glorygold:BAAALgADCgEJAgAAAA==.',
Gn='Gnobebryant:BAAALgADCgcJBwAAAA==.Gnomesaying:BAAALgAECgIJAgAAAA==.',
Go='Goldenhood:BAAALgADCgQJBAAAAA==.Gongoa:BAAALgADCgYJBwAAAA==.Gonnan:BAAALgADCgMJAwAAAA==.Gooddragon:BAAALgAECgYJCgABLgAECggJHwAaAG8eAA==.Gorgibite:BAABLgAFFH8GAAIKAAIJOx52AwC1AAAKAAIJOx52AwC1AAAAAA==.Gorgigammi:BAAALgAFFAEJAQAAAA==.Gotanks:BAAALgADCgYJBgAAAA==.Gotcowbell:BAAALgAECgUJDQAAAA==.',
Gp='Gpathome:BAABLgAECn8bAAQFAAgJ4BlRCgCQAgAFAAgJ4BlRCgCQAgANAAEJiBb0HgBCAAAOAAEJAAD5RQAdAAAAAA==.',
Gr='Graustakhan:BAAALgADCgcJCAAAAA==.Grenvar:BAAALgADCgkJFgAAAA==.Grigdor:BAACLgAFFH8HAAMGAAMJdAvqDQCeAAAHAAIJHwojGQCkAAAGAAIJ4ArqDQCeAAAuAAQKfyUAAwYACAmYHv8EAIwCAAcACAkPHh4fAJ0CAAYACAmFHP8EAIwCAAAA.Grimdeth:BAAALgAECgcJAQAAAA==.Grimnur:BAAALgADCgUJBQAAAA==.Grynchyn:BAABLgAECn8bAAIGAAkJphFXBwBTAgAGAAkJphFXBwBTAgAAAA==.',
Gu='Guass:BAABLgAECn8jAAIgAAgJeB8qAgA6AgAgAAgJeB8qAgA6AgAAAA==.Guhguhguh:BAAALgAECgQJBwAAAA==.Guuoth:BAAALgADCgQJBAAAAA==.',
Gz='Gzip:BAAALgAECgQJBAAAAA==.',
['Gð']='Gðd:BAAALgAECgcJBgAAAA==.',
['Gù']='Gùndèr:BAABLgAECn8eAAIPAAcJxBibWwAnAgAPAAcJxBibWwAnAgAAAA==.',
Ha='Hadish:BAAALgADCgMJAwAAAA==.Haeresis:BAAALgAECgQJBAAAAA==.Haist:BAAALgAECgEJAQAAAA==.Hakira:BAAALgAECgYJCgAAAA==.Hakushu:BAABLgAECn8pAAIfAAgJVBzXEACSAgAfAAgJVBzXEACSAgAAAA==.Haldir:BAAALgADCgMJAwAAAA==.Haliburton:BAAALgADCggJCgAAAA==.Hannizmonk:BAEALgAECgQJBgABLgAECggJFwAYAEMKAA==.Hanyiu:BAABLgAECn8fAAQaAAgJbx5fCwDEAgAaAAgJbx5fCwDEAgAUAAgJOiDADACIAgAfAAEJ+w8fIgBBAAAAAA==.Haramhabibi:BAAALgAECgEJAQAAAA==.Harymanchest:BAAALgADCgQJAwAAAA==.Haze:BAAALgADCgYJBQAAAA==.',
He='Healsgoodman:BAAALgAECgQJBAAAAA==.Heidr:BAAALgADCggJCAAAAA==.Hellother:BAAALgAECgYJBgAAAA==.Hellviera:BAAALgAECgEJAQAAAA==.Hellymental:BAAALgADCgEJAQABLgADCgkJEQABAAAAAA==.Henrick:BAAALgAECgYJCQAAAA==.Hepokeher:BAAALgAECgcJDgAAAA==.Hernog:BAABLgAECn8YAAIZAAgJ0A9pAwCXAQAZAAgJ0A9pAwCXAQAAAA==.Herpales:BAAALgADCgEJAQAAAA==.Hesti:BAAALgAECgEJAQAAAA==.Hexmenixy:BAAALgAECgYJCwAAAA==.Heyitstim:BAAALgADCgcJBwAAAA==.',
Hh='Hh:BAAALgAECgIJAQAAAA==.',
Ho='Holikaw:BAAALgAFFAEJAQAAAA==.Holybibble:BAAALgAECgEJAQAAAA==.Holybox:BAAALgAECggJDAAAAA==.Holyfady:BAAALgAECgMJBQAAAA==.Holyfenix:BAAALgADCgYJBwAAAA==.Holyfilers:BAAALgADCgcJBwAAAA==.Holygrail:BAAALgAECgIJAgAAAA==.Holyhal:BAAALgAECgQJBAAAAA==.Holynixy:BAAALgAECgYJCAAAAA==.Homewreckerr:BAAALgADCgQJAgAAAA==.Hotstuffbaby:BAAALgAECgMJAwAAAA==.',
Hu='Hudini:BAABLgAECn8eAAIPAAcJriDPCQANAgAPAAcJriDPCQANAgAAAA==.Huntcakes:BAAALgAECgEJAQAAAA==.Hurcolo:BAAALgAECgUJBQAAAA==.',
Hy='Hynil:BAAALgADCgUJBQAAAA==.Hypal:BAABLgAECn8VAAQhAAcJRAtNUwAtAQAhAAYJBwxNUwAtAQAWAAMJfQji/wCVAAAIAAEJPBFzQgA0AAABLgAFFAQJCQAiAM4OAA==.Hypd:BAACLgAFFH8JAAIiAAQJzg74BQAbAQAiAAQJzg74BQAbAQAuAAQKfyMAAyIACAkYHY8eAEoCACIABwnkHo8eAEoCACAABwlRF4smAMkBAAAA.Hypev:BAABLgAECn8VAAQFAAgJGw+/LQAEAQAFAAUJwg6/LQAEAQAOAAUJ1Am9KgDHAAANAAMJMhUvFQCuAAABLgAFFAQJCQAiAM4OAA==.Hypm:BAAALgAECgUJDgABLgAFFAQJCQAiAM4OAA==.Hyps:BAAALgAECgEJAgABLgAFFAQJCQAiAM4OAA==.',
['Hä']='Häppyfeet:BAABLgAECn8XAAIfAAgJ1RvwGwAjAgAfAAgJ1RvwGwAjAgAAAA==.',
['Hè']='Hèllenkeller:BAAALgAECgQJBwABLgAECggJGgAcAJQbAA==.',
['Hø']='Hølygirth:BAAALgADCgMJAwAAAA==.',
Ib='Ibichi:BAAALgAECgEJAQAAAA==.Ibuff:BAAALgAECgYJCgAAAA==.Iby:BAABLgAECn8ZAAMUAAgJ3hYAJgCEAQAUAAgJ3hYAJgCEAQAaAAEJ/QFFigAjAAAAAA==.',
Ic='Icescreamcow:BAAALgADCgUJBAAAAA==.',
Il='Iloveeggroll:BAABLgAECn8fAAMiAAkJwx5bEgCjAgAiAAkJwx5bEgCjAgAgAAMJhwV7bABtAAAAAA==.',
Im='Imjongingyu:BAAALgAECgYJBwAAAA==.Impwrangler:BAAALgADCgYJBgAAAA==.Imstressed:BAAALgADCgMJAwAAAA==.Imtrying:BAAALgADCgQJAwAAAA==.',
In='Invìctús:BAABLgAECn8bAAIPAAgJFRUgEADBAQAPAAgJFRUgEADBAQAAAA==.',
Io='Ionalafe:BAAALgADCgIJAgAAAA==.',
Ip='Ipconfig:BAAALgAECggJEgAAAA==.Ipeenaked:BAAALgADCgEJAQAAAA==.',
Is='Isaburo:BAAALgAECgUJBQAAAA==.Isellrocks:BAAALgADCgEJAQAAAA==.Ishiftmyself:BAAALgAECgIJAgAAAA==.',
It='Ithir:BAAALgADCgkJEQAAAA==.Itscdonkick:BAAALgAECgMJAwAAAA==.Itsemma:BAAALgAECgYJEAAAAA==.',
Iz='Izalith:BAAALgAECgEJAwAAAA==.Izzat:BAAALgADCgEJAQAAAA==.',
Ja='Jaanus:BAAALgADCgUJBQAAAA==.Jabalwa:BAAALgADCgYJDwAAAA==.Jackod:BAAALgADCgEJAQABLgAECggJHQAPAF0cAA==.Jackodes:BAAALgADCgIJAgABLgAECggJHQAPAF0cAA==.Jackodm:BAABLgAECn8dAAIPAAgJXRzhKQDLAgAPAAgJXRzhKQDLAgAAAA==.Jackoh:BAAALgADCgcJBwABLgAECggJHQAPAF0cAA==.Jareth:BAAALgAECgEJAQAAAA==.Jawo:BAAALgAECgUJEAAAAA==.Jaxerhoff:BAAALgAECgMJAwAAAA==.',
Je='Jedewo:BAAALgADCgQJBAAAAA==.Jekk:BAABLgAECn8UAAIfAAgJnA8+LQClAQAfAAgJnA8+LQClAQAAAA==.Jekyll:BAAALgAECgMJBAAAAA==.',
Jh='Jhette:BAAALgADCgMJAwAAAA==.Jhoro:BAAALgAECgUJCAAAAA==.',
Ji='Jimmyfister:BAAALgADCgYJCAAAAA==.Jinux:BAAALgADCgMJBAAAAA==.',
Jo='Joeworgen:BAAALgADCgUJCAAAAA==.Johandavis:BAAALgADCgYJBwAAAA==.Johnnysinz:BAABLgAECn8YAAIWAAcJVh3gPwAmAgAWAAcJVh3gPwAmAgAAAA==.Johnnyzyns:BAABLgAECn8cAAIcAAgJCRgAGQBMAgAcAAgJCRgAGQBMAgAAAA==.Johnret:BAAALgAECgYJCQABLgAECgcJGQAWAGchAA==.Jonnytsunami:BAAALgAECgYJBgAAAA==.Joshd:BAAALgADCgMJBwAAAA==.',
Jp='Jp:BAACLgAFFH8XAAIUAAYJaCYJAACnAgAUAAYJaCYJAACnAgAuAAQKfz0AAxQACQmoJgMAABgEABQACQmoJgMAABgEABoAAQnIA2GFACsAAAAA.',
Ju='Jung:BAABLgAECn8bAAIfAAgJgiOAAADfAgAfAAgJgiOAAADfAgAAAA==.Junglefever:BAAALgADCgYJCgAAAA==.Justices:BAAALgADCgMJAwAAAA==.Juulbear:BAAALgADCggJCAAAAA==.',
Ka='Kagàmin:BAAALgAECgEJAQAAAA==.Kahrein:BAAALgAECggJDAAAAA==.Kainssoul:BAAALgADCgQJBgAAAA==.Kaizenith:BAAALgADCgIJAgAAAA==.Kalarin:BAAALgADCgYJBgAAAA==.Kalipriest:BAAALgAECggJBgAAAA==.Kalipso:BAABLgAECn8iAAIHAAgJJxMLDwCaAQAHAAgJJxMLDwCaAQAAAA==.Kamode:BAAALgADCgcJBwAAAA==.Kamwar:BAAALgAECgQJEwABLgAECgcJFAAjAL0bAA==.Kaoticbear:BAAALgADCgUJBQAAAA==.Karideer:BAAALgAECgYJEgAAAA==.Karidyr:BAAALgADCgYJBgAAAA==.Karmand:BAAALgADCgEJAQAAAA==.Kasades:BAAALgADCgUJBQAAAA==.Kasamir:BAAALgAECgYJDQABLgAECgcJBwABAAAAAA==.Kataraxtis:BAAALgAECgEJAQAAAA==.Kaylax:BAAALgAECgQJCQAAAA==.Kaylost:BAAALgADCgUJEQAAAA==.Kaylub:BAABLgAECn8bAAIHAAgJLgu+GQBGAQAHAAgJLgu+GQBGAQAAAA==.Kazrim:BAAALgAECgEJAQAAAA==.Kaztor:BAAALgAECgQJBgAAAA==.',
Ke='Kearà:BAAALgAECgQJBgAAAA==.Kekipo:BAAALgAECgcJEwAAAA==.Keldhar:BAAALgAECgYJEAAAAA==.Kelvo:BAAALgAECgIJAgAAAA==.Kerash:BAAALgADCgkJHgAAAA==.Kevindrd:BAAALgADCgYJBwAAAA==.Kevintt:BAAALgAECgUJDgAAAA==.Keys:BAABLgAECn8XAAIYAAYJ9hIsFwBFAQAYAAYJ9hIsFwBFAQAAAA==.',
Kh='Kho:BAAALgAECgYJCQAAAA==.Kháld:BAAALgADCgIJAgAAAA==.',
Ki='Kiaa:BAAALgADCggJCQAAAA==.Kisora:BAAALgADCgEJAQAAAA==.Kissybeer:BAAALgADCgYJCAAAAA==.Kitherla:BAAALgAECgYJBgAAAA==.Kizara:BAAALgADCgYJBgAAAA==.',
Kn='Knanwai:BAAALgADCgIJAgAAAA==.Knugget:BAABLgAECn8XAAIRAAcJXxpvDQCxAQARAAcJXxpvDQCxAQAAAA==.',
Ko='Koitetsu:BAAALgAECgEJAQABLgAFFAQJEwAPAHsaAA==.Korgigammi:BAACLgAFFH8HAAIfAAMJ6RlYBwD5AAAfAAMJ6RlYBwD5AAAuAAQKfxYAAx8ABwmGID4XAE0CAB8ABwmGID4XAE0CABQABgkFGiMeAMYBAAAA.Korgigamus:BAABLgAECn8aAAMNAAcJcCRzDgCOAgANAAcJcCRzDgCOAgAOAAYJkhQAHABQAQABLgAFFAMJBwAfAOkZAA==.Korily:BAAALgAECgQJBAAAAA==.Kozdiniar:BAAALgAFFAEJAQABLgAFFAQJDQAMAOQgAA==.Kozurai:BAAALgAFFAEJAQABLgAFFAQJDQAMAOQgAA==.',
Kr='Kristree:BAAALgADCgEJAQAAAA==.Kritin:BAAALgADCgcJBwAAAA==.',
Ks='Kshan:BAAALgADCgUJBQAAAA==.',
Ku='Kugot:BAABLgAECn8iAAIdAAgJ1xyqBQAFAgAdAAgJ1xyqBQAFAgAAAA==.Kunigunda:BAAALgADCgkJEAAAAA==.Kushed:BAAALgAECgQJBwAAAA==.',
Ky='Kydrea:BAAALgADCgkJFwAAAA==.Kydrin:BAAALgADCgEJAQABLgADCgkJFwABAAAAAA==.Kyne:BAAALgAECgUJCgAAAA==.',
['Kâ']='Kânê:BAAALgAECgYJDwAAAA==.',
['Kñ']='Kñuckles:BAAALgADCgEJAQAAAA==.',
['Kø']='Køjiro:BAAALgAECgUJBQAAAA==.',
['Kú']='Kúsúri:BAAALgADCgcJDAAAAA==.',
La='Ladrón:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.Lagrima:BAAALgAECgEJAgAAAA==.Lamish:BAAALgADCgEJAQAAAA==.Lancel:BAAALgADCgIJAgABLgAECggJHQATADIdAA==.Largetuna:BAAALgAECgYJDAAAAA==.Larien:BAAALgAECgYJBgAAAA==.Larkos:BAAALgADCgYJCgAAAA==.Lassamyna:BAAALgADCgUJCAAAAA==.Latías:BAAALgADCgEJAQAAAA==.',
Le='Lebabo:BAAALgADCgEJAQAAAA==.Leechygos:BAAALgAECgYJDgAAAA==.Leetyeets:BAAALgAECgEJAQAAAA==.Legar:BAAALgADCggJCQAAAA==.Legenddairy:BAAALgAECgMJBAAAAA==.Leitris:BAAALgAECgEJAQAAAA==.Leoonidas:BAAALgAECgIJAgABLgAECgYJHgAgAIweAA==.Lexinight:BAAALgADCgQJBQAAAA==.',
Lh='Lhunter:BAAALgAECgEJAQAAAA==.',
Li='Licked:BAAALgAECgMJBAAAAA==.Lickmyarrows:BAABLgAECn8eAAIDAAgJgxiXHgAuAgADAAgJgxiXHgAuAgAAAA==.Lickmyhorns:BAAALgAECgQJBgABLgAECggJHgADAIMYAA==.Liddo:BAAALgAFFAEJAQAAAA==.Liendrah:BAECLgAFFH8OAAIeAAUJ5hjQAABBAQAeAAUJ5hjQAABBAQAuAAQKfywAAh4ACQmXIm8AAHIDAB4ACQmXIm8AAHIDAAAA.Lightwaves:BAAALgADCgUJBAAAAA==.Lildoinkz:BAAALgADCgcJCwAAAA==.Lilet:BAABLgAECn8bAAIJAAgJ3BRjBACJAQAJAAgJ3BRjBACJAQAAAA==.Lilitsune:BAAALgAECgMJCQAAAA==.Lilsmalls:BAAALgADCgEJAQAAAA==.Lilyiffer:BAABLgAECn8bAAMcAAkJOx+0CgDrAgAcAAkJOx+0CgDrAgAZAAEJ3A04LAA1AAAAAA==.Limer:BAAALgAECgEJAQAAAA==.Linareyna:BAAALgADCgMJBAAAAA==.Lionisa:BAAALgADCgYJBgAAAA==.Lisri:BAAALgAECgYJEgAAAA==.Littlefenrir:BAAALgADCgIJAgAAAA==.Littlepeewee:BAAALgAECgQJBAAAAA==.Lizolio:BAAALgAECgYJEAAAAA==.',
Ll='Llomel:BAAALgADCgYJDQAAAA==.',
Lo='Lockdoc:BAAALgADCggJCQAAAA==.Locknasty:BAAALgADCgQJBAAAAA==.Locturnal:BAAALgAECgMJAwAAAA==.Lohhano:BAAALgAECgIJAgAAAA==.Lorhana:BAAALgAECgMJBAAAAA==.Lornix:BAAALgADCggJDQAAAA==.Louanna:BAAALgADCgIJAgAAAA==.',
Lu='Lucilla:BAAALgAECgQJBgAAAA==.Ludamage:BAAALgAECgMJAwAAAA==.Luminolus:BAAALgAECgEJAgAAAA==.Lunastri:BAAALgAECgUJCAAAAA==.Lussprodz:BAAALgADCgYJCgAAAA==.Luurg:BAAALgAECgEJAQAAAA==.',
Ly='Lyan:BAAALgADCgUJCAAAAA==.Lyonel:BAAALgAECgUJDgAAAA==.',
Ma='Machi:BAAALgAECgYJBgAAAA==.Madara:BAAALgAECgQJBwAAAA==.Madkittycat:BAAALgAECgQJCAABLgAFFAUJDQAbANUSAA==.Maelyan:BAAALgADCgIJAgAAAA==.Magickid:BAAALgAECgcJEAAAAA==.Magicmojo:BAAALgAECgMJAwAAAA==.Magikkosa:BAABLgAECn8cAAIkAAgJtyCiBwDRAgAkAAgJtyCiBwDRAgAAAA==.Magipaw:BAABLgAECn8cAAIPAAgJGxnZEQCzAQAPAAgJGxnZEQCzAQAAAA==.Makkura:BAAALgADCgYJBgAAAA==.Malekíth:BAAALgAECgEJAQAAAA==.Malifex:BAAALgADCgUJBQAAAA==.Mambaspeed:BAAALgAECgQJBwABLgAECgQJDAABAAAAAA==.Manchufu:BAAALgAECgYJBgABLgAECgkJGwAcADsfAA==.Manorable:BAAALgADCgEJAQABLgAECgcJCgABAAAAAA==.Mappet:BAAALgAECgUJCgAAAA==.Marcelecelle:BAAALgADCgEJAQAAAA==.Marfil:BAAALgAECgQJBAAAAA==.Marilynz:BAAALgADCgcJBwAAAA==.Markedones:BAAALgADCgYJBgAAAA==.Marliia:BAAALgADCgMJAwAAAA==.Marryheal:BAAALgAECgEJAQAAAA==.Marrylanders:BAABLgAECn8cAAIPAAgJ4RrZTgBKAgAPAAgJ4RrZTgBKAgAAAA==.Martiul:BAAALgAECgQJBAAAAA==.Matangkad:BAAALgADCgYJBgAAAA==.Matildra:BAAALgADCgcJBwAAAA==.Maulfather:BAAALgADCgYJCgAAAA==.Mawmá:BAAALgAECgYJCgAAAA==.Mazzy:BAAALgADCgMJAwAAAA==.',
Mc='Mchealinyo:BAAALgADCgcJCgAAAA==.Mclùven:BAAALgAECgYJDAAAAA==.',
Me='Meanstreak:BAAALgAECgMJBwABLgAECggJBwABAAAAAA==.Meech:BAAALgADCgMJBAABLgAECgcJCgABAAAAAA==.Meevo:BAAALgADCgcJBwAAAA==.Melaan:BAAALgADCgQJBAAAAA==.Meliar:BAAALgADCgQJBAAAAA==.Mellie:BAAALgADCgcJDwAAAA==.Melmei:BAABLgAECn8XAAMUAAcJJge0EADVAAAUAAYJEQa0EADVAAAaAAEJ3QHyJQAkAAAAAA==.Meowiarty:BAAALgADCgQJBgAAAA==.Meribella:BAAALgADCgkJFQAAAA==.Meryller:BAAALgAECgQJBwAAAA==.Meszyra:BAACLgAFFH8LAAIOAAQJ/xlIAAByAQAOAAQJ/xlIAAByAQAuAAQKfyoAAg4ACAlaJEQCABMDAA4ACAlaJEQCABMDAAAA.Meta:BAAALgAECgcJAQAAAA==.Metrik:BAAALgAECgQJBAAAAA==.',
Mi='Miamour:BAAALgADCgIJAgAAAA==.Midnightmf:BAAALgAECgMJBAAAAA==.Minwrith:BAAALgADCgIJAgAAAA==.Mirriam:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.Misogolden:BAAALgAECgQJCAAAAA==.Missfyre:BAAALgAECgUJBwAAAA==.Mittenss:BAAALgAECgMJCgAAAA==.Mittenza:BAAALgAECgYJBwAAAA==.Mixelplix:BAAALgAECgYJDAAAAA==.',
Mo='Mobpsycho:BAAALgADCgQJBAAAAA==.Mochhii:BAAALgADCgEJAQAAAA==.Moistkite:BAAALgAECgMJCAAAAA==.Molari:BAAALgAECgQJBgAAAA==.Monkdynasty:BAAALgADCgEJAQAAAA==.Monkusky:BAAALgAECgYJCgAAAA==.Moofury:BAAALgADCgYJCwAAAA==.Mooneshine:BAAALgADCgYJCwAAAA==.Moonreaper:BAAALgADCgcJBwABLgAECgYJEQABAAAAAA==.Mooseknuck:BAAALgAECgYJEAAAAA==.Morallirael:BAAALgADCgUJBQABLgADCgcJBwABAAAAAA==.Mordath:BAAALgAECgMJBAAAAA==.Mordoom:BAAALgAECgQJBQAAAA==.Morikai:BAAALgAECgYJCQAAAA==.Mosag:BAAALgADCggJDQAAAA==.Moushou:BAABLgAECn8cAAIiAAgJgw/bDgBpAQAiAAgJgw/bDgBpAQAAAA==.',
Ms='Mspacman:BAAALgAECgYJCgAAAA==.',
Mu='Muehzen:BAAALgAECgQJBAAAAA==.Muffinstumps:BAAALgAECgQJBwAAAA==.Muffintopper:BAABLgAECn8aAAIcAAgJlBsoEwCHAgAcAAgJlBsoEwCHAgAAAA==.Murricant:BAAALgADCgMJAwAAAA==.Mutovenator:BAAALgAECgEJAQAAAA==.Muulubu:BAAALgADCgUJBQAAAA==.',
My='Myrnn:BAAALgADCgIJAgAAAA==.Myrrha:BAACLgAFFH8JAAIFAAQJyRjvAgBcAQAFAAQJyRjvAgBcAQAuAAQKfyMABAUACAniJT8BAHsDAAUACAniJT8BAHsDAA0AAwm3F9waAGQAAA4AAQlbIEU4AFYAAAAA.Mythicalzomb:BAAALgADCgUJCgAAAA==.',
['Må']='Mårky:BAAALgADCgYJBgAAAA==.',
['Më']='Mërlyn:BAAALgAECgUJBQAAAA==.',
['Mï']='Mïnerva:BAAALgAECgYJEAAAAA==.',
['Mô']='Mônah:BAAALgAECgEJAQAAAA==.',
['Mö']='Mörena:BAABLgAECn8cAAIcAAgJuRwdEgCSAgAcAAgJuRwdEgCSAgAAAA==.',
Na='Nachtritter:BAAALgAECggJDwAAAA==.Naemera:BAAALgADCgEJAQAAAA==.Nahvispro:BAAALgAECgYJDAAAAA==.Namárië:BAAALgAECgQJBAAAAA==.Naobito:BAAALgADCgEJAwAAAA==.Narraice:BAAALgAECgQJBAAAAA==.Natch:BAAALgAECgMJBAAAAA==.',
Ne='Nef:BAABLgAECn8UAAIRAAgJBhDyDwCXAQARAAgJBhDyDwCXAQAAAA==.Neimi:BAAALgAECgUJCAAAAA==.Neitis:BAAALgAECgcJBgAAAA==.Nekkra:BAAALgAECgcJEAAAAA==.Neodela:BAAALgADCgYJBgAAAA==.Nerdchillpal:BAAALgADCgIJAgAAAA==.Nestor:BAAALgADCgYJBgAAAA==.Nethaur:BAAALgAECgYJBgAAAA==.Nevidia:BAAALgADCgkJGwAAAA==.',
Ni='Nikruun:BAAALgADCgEJAQAAAA==.Nishkavel:BAAALgADCgkJDwAAAA==.Nitewang:BAACLgAFFH8UAAIJAAUJch99AQDRAQAJAAUJch99AQDRAQAuAAQKfxUAAgkACAl6IZ8HAK4CAAkACAl6IZ8HAK4CAAAA.Nitewing:BAAALgAECgcJDAABLgAFFAUJFAAJAHIfAA==.Nixhty:BAAALgADCgQJBwAAAA==.',
No='Noctaro:BAABLgAECn8sAAQFAAgJQw0tBACLAQAFAAgJQw0tBACLAQANAAYJmg+sPQD1AAAOAAQJlwkBLAC8AAAAAA==.Noctero:BAAALgAECgMJAwABLgAECggJLAAFAEMNAA==.Nodae:BAAALgAFFAMJAwAAAA==.Nohaki:BAAALgADCgEJAQAAAA==.Nokedli:BAAALgADCgQJBAAAAA==.Nokona:BAAALgADCgkJCgAAAA==.Nolifejack:BAAALgAECgQJBQAAAA==.Nopel:BAAALgADCgcJBwAAAA==.Northrup:BAAALgAECgEJAgAAAA==.Nosramus:BAAALgADCgIJAgAAAA==.Nossena:BAAALgAECgUJBgABLgAECgYJDgABAAAAAA==.Nosy:BAAALgAECgQJCwAAAA==.Notbunni:BAABLgAECn8dAAIlAAgJJw0XCQBMAQAlAAgJJw0XCQBMAQABLgAECgUJBgABAAAAAA==.Notkug:BAAALgADCgcJBwABLgAECggJIgAdANccAA==.Notpizza:BAACLgAFFH8LAAIYAAUJZg2pEwA0AQAYAAUJZg2pEwA0AQAuAAQKfxwAAhgACAlhIOMnAGUCABgACAlhIOMnAGUCAAAA.Noyased:BAAALgADCgEJAgAAAA==.',
Nu='Nutofhair:BAAALgAECgEJAgAAAA==.',
Ny='Nysselys:BAAALgAECgIJAgAAAA==.',
['Ná']='Nárázumono:BAACLgAFFH8GAAIbAAMJ0QthBgAAAQAbAAMJ0QthBgAAAQAuAAQKfxcAAxsABwk+G8oYAD8CABsABwk+G8oYAD8CACMAAwnECxoLAJYAAAEuAAMKBwkMAAEAAAAA.',
['Nï']='Nïcci:BAAALgAECgEJAQAAAA==.',
Ob='Obiwonkenobi:BAAALgADCgYJCgAAAA==.Obnixa:BAABLgAECn8UAAIEAAcJPRgLDQD6AQAEAAcJPRgLDQD6AQAAAA==.Obrox:BAAALgADCgEJAQAAAA==.',
Of='Ofchildren:BAABLgAECn8XAAIFAAYJ5BDABQBGAQAFAAYJ5BDABQBGAQAAAA==.',
Og='Oglok:BAAALgADCgEJAQAAAA==.',
Ol='Oleimaaranub:BAAALgAECgMJAwAAAA==.Olivez:BAAALgADCgQJBAAAAA==.',
Om='Omgitsronnie:BAAALgAECgYJBgAAAA==.Omnishield:BAAALgAECggJDAAAAA==.',
Op='Opithel:BAACLgAFFH8HAAIYAAMJ4iRrBgBEAQAYAAMJ4iRrBgBEAQAuAAQKfyQAAhgACAmOJj8EAIQDABgACAmOJj8EAIQDAAAA.Oppalina:BAAALgAECgcJDwAAAA==.Oprahwndfury:BAAALgADCgYJBgAAAA==.',
Or='Orawm:BAABLgAECn8ZAAIfAAgJQCHsCAD5AgAfAAgJQCHsCAD5AgAAAA==.Oriko:BAABLgAECn8XAAMZAAcJaQ5UBABuAQAZAAcJaQ5UBABuAQAdAAIJ0wRejgBdAAAAAA==.Ortlynn:BAAALgADCgkJHAAAAA==.Oríllas:BAACLgAFFH8HAAIMAAMJ7Bl4BgD7AAAMAAMJ7Bl4BgD7AAAuAAQKfykAAgwACAltJPcHACoDAAwACAltJPcHACoDAAAA.',
Os='Osric:BAAALgAECgcJDwAAAA==.',
Ot='Othergreen:BAABLgAECn8cAAINAAcJ6hOQHgDPAQANAAcJ6hOQHgDPAQAAAA==.',
Oy='Oyumi:BAACLgAFFH8JAAIiAAQJOiQjAgCVAQAiAAQJOiQjAgCVAQAuAAQKfxoAAiIACAnqJdsCAGkDACIACAnqJdsCAGkDAAEuAAUUBgkQACEADSUA.',
Pa='Pachaia:BAAALgAECgEJAgAAAA==.Pactita:BAAALgAECgMJAwABLgAECgUJBQABAAAAAA==.Paech:BAAALgADCgYJCQAAAA==.Pairädice:BAABLgAECn8lAAIZAAkJah6oAwDxAgAZAAkJah6oAwDxAgAAAA==.Paladingo:BAAALgADCgcJEQABLgAFFAMJBgAUAMYMAA==.Palatics:BAAALgADCgEJAQAAAA==.Pallymorph:BAABLgAECn8bAAIWAAYJFhURkABcAQAWAAYJFhURkABcAQAAAA==.Palswarlock:BAAALgAECgMJCAAAAA==.Pamplemousse:BAAALgAECgcJBwAAAA==.Pandussy:BAAALgAECgEJAwAAAA==.Paperknîves:BAAALgAECgcJBwAAAA==.Passing:BAAALgADCgYJBgAAAA==.Paulgambino:BAAALgAECgQJCAAAAA==.',
Pe='Pellwar:BAAALgADCgcJCQAAAA==.Perineumraw:BAAALgADCgcJDgAAAA==.Perritus:BAAALgAECgUJCwAAAA==.Petme:BAAALgAECgYJCQABLgAECgkJIgAKAD0jAA==.Petuh:BAAALgADCgUJBgAAAA==.',
Ph='Phephraan:BAAALgAECgYJDQAAAA==.Phwaz:BAAALgAECgQJBwAAAA==.',
Pi='Pinktress:BAABLgAECn8ZAAICAAcJiw4aRACfAQACAAcJiw4aRACfAQAAAA==.Pinkyparty:BAAALgADCgMJAwAAAA==.',
Pk='Pkcontrol:BAAALgAECgEJAQAAAA==.Pkmantra:BAAALgADCgMJBgAAAA==.',
Pl='Plzndavis:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.',
Po='Polyhaladin:BAAALgADCgMJAwABLgAECggJGgAcAJQbAA==.Polymorphine:BAAALgAECgcJEwAAAA==.Popadot:BAAALgADCgIJAgAAAA==.Porkbuns:BAAALgADCgcJBwAAAA==.Portalaway:BAAALgADCgEJAQAAAA==.Possecutor:BAACLgAFFH8OAAIVAAQJCA+rAgBAAQAVAAQJCA+rAgBAAQAuAAQKfycAAhUACAm4IG4LAMwCABUACAm4IG4LAMwCAAAA.',
Pr='Prabis:BAAALgAECgYJCgAAAA==.Prayrie:BAAALgAECgMJAwAAAA==.Primeer:BAABLgAECn8cAAIMAAgJyxYGBQDjAQAMAAgJyxYGBQDjAQAAAA==.Pryîto:BAAALgAECgUJBgAAAA==.',
Pt='Ptownfunk:BAEALgAECgQJBAAAAA==.',
Pu='Pumachaka:BAABLgAECn8WAAMGAAYJwAzUBQDjAAAGAAYJwAzUBQDjAAAHAAEJ5QLbWwApAAAAAA==.Pureogs:BAAALgADCgEJAQAAAA==.Purplehazes:BAAALgADCgIJAgAAAA==.',
Pv='Pvtjokr:BAAALgADCgYJBgABLgAECggJGgAcAJQbAA==.',
Qu='Quikcrusader:BAAALgADCgIJAgAAAA==.Quikshift:BAAALgADCgQJBAAAAA==.Quilanne:BAAALgADCgMJAwAAAA==.Quixos:BAAALgAECgMJAwAAAA==.',
Qw='Qwertysquid:BAAALgAECgQJBAAAAA==.',
Ra='Ragezon:BAAALgAECgMJAwAAAA==.Rageßait:BAAALgADCgEJAQAAAA==.Rahaydin:BAAALgAECgYJDgAAAA==.Raijzu:BAAALgAECgYJBgAAAA==.Ranashi:BAAALgAECgYJDgAAAA==.Randmholes:BAAALgADCggJCAAAAA==.Randomfatguy:BAAALgADCgEJAQAAAA==.Randysavage:BAAALgADCgUJCAAAAA==.Raphaela:BAAALgADCgcJBwABLgAECgQJBAABAAAAAA==.Rathrus:BAABLgAECn8bAAMeAAYJRh4gCgDGAQAeAAYJRh4gCgDGAQAmAAYJ9AuwOAAhAQAAAA==.Raxmanus:BAAALgAECgYJDAAAAA==.Rayzac:BAABLgAECn8dAAIPAAgJxg2cGQB7AQAPAAgJxg2cGQB7AQAAAA==.',
Re='Realize:BAAALgAECgYJBQAAAA==.Reapblood:BAABLgAECn8lAAQmAAgJ8Bf5EgBAAgAmAAgJVRf5EgBAAgAeAAcJhRQ4EABNAQAYAAEJ3QJR6QApAAAAAA==.Reaperz:BAAALgADCgEJAQAAAA==.Redbulis:BAAALgADCgkJEQAAAA==.Redbulls:BAAALgADCgYJBgAAAA==.Rednuth:BAAALgADCgkJDwAAAA==.Redstein:BAAALgADCgQJBAAAAA==.Reglith:BAAALgAECgUJCQAAAA==.Reilini:BAAALgAECggJDgAAAA==.Remedium:BAAALgADCgEJAQAAAA==.Reusins:BAABLgAECn8VAAIMAAYJZxAgUwBdAQAMAAYJZxAgUwBdAQAAAA==.Reyae:BAAALgAECgMJAwAAAA==.Reydar:BAAALgAECgEJAQAAAA==.Reàp:BAAALgADCgUJDAAAAA==.',
Ri='Rickiebear:BAAALgADCgcJEgAAAA==.Rikimaruu:BAAALgADCgcJDQAAAA==.Rikkiemortis:BAAALgADCgcJDAAAAA==.Riotshield:BAAALgAECgcJBwAAAA==.',
Ro='Roastedchuck:BAAALgAECgQJCgAAAA==.Rontsu:BAAALgADCgcJBwAAAA==.Roosterdd:BAAALgADCgEJAQAAAA==.Rooted:BAAALgADCgcJEAAAAA==.Roshar:BAAALgADCgkJEgAAAA==.Rotorsdk:BAAALgAECgcJCwAAAA==.Rotorslock:BAAALgADCgUJBQAAAA==.Rottlock:BAAALgADCgMJAwAAAA==.',
Ru='Rueldalf:BAAALgAECgUJDgAAAA==.Rugaar:BAAALgAECgYJEgAAAA==.Ruïn:BAAALgADCgIJAwAAAA==.',
Ry='Rykudo:BAAALgAECgQJBgAAAA==.',
['Rê']='Rêd:BAAALgAECgUJCQAAAA==.Rêmi:BAAALgADCgcJDAAAAA==.',
Sa='Saladosh:BAAALgADCgkJFQAAAA==.Sallie:BAAALgADCggJDQAAAA==.Sallielune:BAAALgADCgcJBwAAAA==.Salliepallie:BAAALgADCgMJAwAAAA==.Saltyevoker:BAAALgADCgIJAgAAAA==.Samlock:BAABLgAECn8rAAIGAAcJvhyUBgBkAgAGAAcJvhyUBgBkAgAAAA==.Sanitized:BAAALgAECgEJAQAAAA==.Sanzaemon:BAAALgAECgQJBAAAAA==.Saqa:BAAALgAECgUJBQAAAA==.Sarevok:BAAALgADCgcJDwABLgAECgYJCQABAAAAAA==.Satyrlord:BAAALgAECgYJBgAAAA==.Saucing:BAAALgADCgYJBgAAAA==.Save:BAAALgADCgQJBAAAAA==.Savella:BAAALgAECgcJDgAAAA==.',
Sc='Scarletblade:BAACLgAFFH8GAAIWAAMJORB1FgD4AAAWAAMJORB1FgD4AAAuAAQKfxsAAxYACAkmJJ4NACEDABYACAkmJJ4NACEDAAgAAwkqEp4tAKIAAAAA.Schamwoww:BAAALgAECgYJDQAAAA==.Schizm:BAAALgADCgQJBAAAAA==.Schmidt:BAAALgAECgcJBgAAAA==.Schulkzu:BAAALgADCgEJAQAAAA==.Scubar:BAAALgAECgQJCAAAAA==.Scyllabus:BAAALgADCgkJCQAAAA==.',
Sd='Sdtempest:BAAALgAECgMJAwAAAA==.',
Se='Seafox:BAAALgAECgMJBQAAAA==.Seance:BAAALgADCgYJBgAAAA==.Sear:BAACLgAFFH8GAAIYAAMJNg8WDgDrAAAYAAMJNg8WDgDrAAAuAAQKfxgAAhgABwk8Gqo+APoBABgABwk8Gqo+APoBAAAA.Seiðkona:BAAALgAECgUJEgAAAA==.Senorcalzone:BAAALgAECgYJEgAAAA==.',
Sh='Shadowbinder:BAAALgADCgYJBgAAAA==.Shadowjacker:BAAALgAECgYJEAAAAA==.Shakyswayze:BAAALgADCgkJEgAAAA==.Shamiam:BAAALgAECgIJAgAAAA==.Shamwowan:BAAALgAECgIJAgAAAA==.Shapeshifta:BAAALgADCgQJBAAAAA==.Sharkcoochie:BAAALgAECgMJBAAAAA==.Sharktank:BAAALgAECgQJBgAAAA==.Shataree:BAAALgADCgQJAgAAAA==.Shatterer:BAAALgADCgUJBQAAAA==.Shazzno:BAAALgADCgUJBQAAAA==.Sherenax:BAAALgAECgcJBAAAAA==.Shimbiosis:BAAALgAECgYJBgABLgAFFAQJDAADAJMWAA==.Shineup:BAAALgAECgMJAwAAAA==.Shädøw:BAAALgADCgkJEAAAAA==.',
Si='Sinvalk:BAAALgADCgcJEgAAAA==.Sithtauren:BAAALgADCgEJAQAAAA==.Situuna:BAAALgADCggJCAAAAA==.',
Sk='Skysong:BAAALgAECgYJEAABLgAECggJJQALAM4lAA==.',
Sl='Sleezyaf:BAAALgAECgQJBgAAAA==.Slxm:BAABLgAECn8XAAIJAAcJ7x8MDABLAgAJAAcJ7x8MDABLAgAAAA==.Slycraf:BAAALgADCgkJCQAAAA==.',
Sn='Sneakrat:BAAALgADCgQJBAAAAA==.Sneakydoinkz:BAAALgADCgYJBgAAAA==.Sneederson:BAAALgAECgEJAQAAAA==.',
So='Socketss:BAAALgAECgEJAQAAAA==.Sohjinra:BAAALgAECgQJDgAAAA==.Solammath:BAAALgAECgUJDAAAAA==.Sololvling:BAAALgAECgUJCQAAAA==.Somewunn:BAAALgAECgIJAgAAAA==.Sovereign:BAACLgAFFH8QAAIWAAQJuRvXAgBrAQAWAAQJuRvXAgBrAQAuAAQKfygAAhYACQkuJO8DAI8DABYACQkuJO8DAI8DAAAA.',
Sp='Sp:BAAALgAECgYJAgAAAA==.Spacebacon:BAAALgADCgYJBgAAAA==.Spark:BAAALgAECgMJAwAAAA==.Spenjamin:BAAALgAECgYJCgAAAA==.Spills:BAAALgADCgQJAwAAAA==.Spinnspal:BAAALgADCgIJAwAAAA==.Splaash:BAAALgAECgEJAQAAAA==.Spoogydoogy:BAAALgADCgcJCwAAAA==.Spronny:BAAALgAECgEJAQAAAA==.Spruo:BAAALgAECgEJAQAAAA==.',
Sq='Squirtles:BAAALgAECgYJDAAAAA==.',
St='Staggsette:BAAALgAECgMJBAAAAA==.Stanleyfu:BAAALgAECgYJCAAAAA==.Starzadin:BAAALgADCgQJBAAAAA==.Stealthfire:BAABLgAECn8lAAMLAAgJziUfAAAYAwALAAgJziUfAAAYAwAKAAEJCB6yKwBJAAAAAA==.Stonekin:BAAALgADCgEJAQAAAA==.Stormburm:BAAALgAECgMJBAAAAA==.Storming:BAAALgADCgEJAQAAAA==.Stormstrikes:BAAALgADCgYJCAAAAA==.Stormvalk:BAAALgADCgUJEQAAAA==.Strongw:BAAALgAECgUJBgAAAA==.Stylish:BAABLgAECn8kAAMCAAkJnSGIBgAlAwACAAkJIR2IBgAlAwADAAgJAhlPIwAJAgAAAA==.Stíffler:BAAALgAECgcJCgAAAA==.',
Su='Sugaboomboom:BAAALgAECgcJEQAAAA==.Sumwon:BAAALgAECgQJBAABLgAECggJHAAIAOEWAA==.Sumwuun:BAABLgAECn8cAAMIAAgJ4RYqEADDAQAIAAgJ9BMqEADDAQAWAAYJyhMhhwBsAQAAAA==.Sunarr:BAAALgAECgYJBgAAAA==.Superace:BAACLgAFFH8MAAIcAAQJ+gmWDAAlAQAcAAQJ+gmWDAAlAQAuAAQKfyIAAhwACAkFHZsRAJcCABwACAkFHZsRAJcCAAAA.Surlydude:BAAALgADCgIJAgAAAA==.',
Sw='Swaxxy:BAABLgAECn8gAAQlAAcJyRAwIQCKAQAlAAcJtA4wIQCKAQAVAAcJbw9bCABwAQAkAAQJBgttXADBAAAAAA==.Swiftys:BAAALgAECgYJEwAAAA==.Swiftyswayze:BAAALgADCgkJGQAAAA==.Swissy:BAAALgADCgYJBgAAAA==.Swordsoul:BAAALgAECgYJBwAAAA==.',
Sy='Synde:BAAALgAECgYJBgAAAA==.Synkalock:BAAALgAECgUJCAAAAA==.Synkareaper:BAAALgADCgcJCgABLgAECgUJCAABAAAAAA==.Synkaweeds:BAAALgADCgcJEQABLgAECgUJCAABAAAAAA==.Synrya:BAAALgADCgEJAQAAAA==.',
Sz='Szupernova:BAAALgADCgUJCgAAAA==.',
['Sí']='Símon:BAAALgADCgcJEgABLgAECgUJFAAYAD0TAA==.',
Ta='Taappy:BAAALgAECgMJAwAAAA==.Tacostuffing:BAAALgAECgMJBAAAAA==.Tagorn:BAAALgAECgMJBAAAAA==.Tahnaylla:BAAALgADCgEJAQAAAA==.Tail:BAABLgAECn8UAAIMAAYJ4hYWEQAfAQAMAAYJ4hYWEQAfAQAAAA==.Tails:BAAALgAECgQJCAAAAA==.Tajomaru:BAAALgAECgEJAQAAAA==.Takutaki:BAAALgADCgkJCwABLgAECgEJAQABAAAAAA==.Talaith:BAAALgADCgEJAQAAAA==.Talamandas:BAAALgADCgMJAwAAAA==.Talyethe:BAAALgADCgYJCQAAAA==.Tanato:BAAALgADCgQJBgAAAA==.Tanmand:BAAALgAECgUJCQAAAA==.Tanthora:BAAALgAECgIJAwAAAA==.Taqa:BAAALgAECgYJDwAAAA==.Tastybeef:BAABLgAECn8UAAIkAAcJ2haqHgDqAQAkAAcJ2haqHgDqAQABLgAFFAMJBgAUAMYMAA==.Tastyfísh:BAAALgAECgYJDAAAAA==.Tastytotems:BAAALgADCgEJAQAAAA==.Tauri:BAAALgADCgkJGgAAAA==.Taxxí:BAAALgADCgYJCgAAAA==.Tayschrenn:BAAALgAECgMJAwAAAA==.',
Te='Tealura:BAAALgADCgYJCQABLgADCgcJBwABAAAAAA==.Teddymouse:BAAALgADCgcJBwABLgAECgYJEQABAAAAAA==.Telyon:BAAALgAECgEJAgAAAA==.Tenfists:BAAALgAECgEJAQAAAA==.Termo:BAAALgAECgQJBgAAAA==.Texasftw:BAAALgAECgEJAQAAAA==.Texmonk:BAACLgAFFH8GAAIUAAMJxgzcBgDNAAAUAAMJxgzcBgDNAAAuAAQKfxcAAxQABwm9IckNAHoCABQABwm9IckNAHoCABoABAkJE4BBABIBAAAA.Texásftw:BAAALgADCgEJAQAAAA==.',
Tf='Tfcdk:BAAALgADCgYJCgAAAA==.',
Th='Thardinein:BAAALgAECgQJCAAAAA==.Thassal:BAAALgAECgEJAQAAAA==.Thebutler:BAACLgAFFH8OAAMHAAUJBxmQBQDFAQAHAAUJBxmQBQDFAQAGAAEJBw3+FgBRAAAuAAQKfxcABAcACAnRIMcoAG4CAAcACAk9H8coAG4CABIAAglXI9kZAKkAAAYAAgl3B3hSAHcAAAAA.Thekeres:BAAALgAECgEJAQAAAA==.Thussy:BAAALgAECgYJCgAAAA==.',
Ti='Timy:BAAALgADCgQJBAAAAA==.Timøthy:BAAALgAECgYJDQAAAA==.Tinasha:BAEBLgAECn8XAAIYAAgJQwq3HQAZAQAYAAgJQwq3HQAZAQAAAA==.Tinman:BAAALgADCgIJAgAAAA==.Tinyperrind:BAAALgADCgIJBAAAAA==.Tinyrage:BAAALgAECgUJBQAAAA==.Tipper:BAAALgAECgYJBgAAAA==.Tiqep:BAAALgAECgcJCQAAAA==.Tirria:BAAALgADCgUJBQAAAA==.',
Tk='Tkaniaa:BAAALgADCgQJBgAAAA==.Tkaniy:BAAALgADCgUJCgAAAA==.',
To='Toaztdoinks:BAAALgADCgcJCQAAAA==.Toaztdoinkz:BAAALgADCgYJDAAAAA==.Togsly:BAAALgADCgMJAwABLgAECggJIgAdANccAA==.Tombo:BAABLgAECn8UAAIHAAYJ1gaCrgD8AAAHAAYJ1gaCrgD8AAAAAA==.Tones:BAAALgAECgEJAQAAAA==.Tossdirt:BAACLgAFFH8RAAMZAAUJhB+MAADTAQAZAAUJ2R6MAADTAQAcAAUJPBQuAgBdAQAuAAQKfyYAAxkACQlLIrcAAJQDABkACQkkIrcAAJQDABwACAmUHEIMANcCAAAA.Toxle:BAAALgAECgQJCAAAAA==.',
Tr='Tracked:BAAALgAECgIJAgAAAA==.Trackerjack:BAAALgAECgkJCwAAAA==.Traditor:BAAALgADCgMJAwAAAA==.Trakshot:BAAALgADCgcJBwABLgAFFAUJDwADAGEVAA==.Treetoucher:BAAALgAECggJEwAAAA==.Trilldemon:BAAALgAECgcJBQAAAA==.Trippdaddy:BAAALgADCggJCAAAAA==.Triva:BAAALgAECgEJAQAAAA==.Truedamage:BAAALgAECgYJCQAAAA==.Truefaith:BAAALgAECgcJCAAAAA==.',
Tu='Tuluga:BAAALgADCgMJAwABLgAECgUJCQABAAAAAA==.Tunadruid:BAAALgAECgEJAQAAAA==.Tunasat:BAAALgAECgYJCQAAAA==.Tunnzz:BAAALgAECgIJBAAAAA==.',
Tw='Twinkle:BAAALgAECgEJAQAAAA==.',
Tx='Txcreekwoo:BAAALgADCgEJAgAAAA==.',
Ty='Tyestus:BAAALgADCgMJBQAAAA==.Typhal:BAABLgAECn8jAAIWAAgJbCFpBwAVAgAWAAgJbCFpBwAVAgAAAA==.',
['Tá']='Táxxi:BAAALgAECgEJAQAAAA==.',
['Té']='Téllah:BAABLgAECn8pAAIPAAgJlxybMACwAgAPAAgJlxybMACwAgAAAA==.',
Ug='Ugluk:BAAALgADCgUJBgAAAA==.',
Uh='Uhtan:BAAALgAECgYJDAAAAA==.',
Un='Unbeleafable:BAAALgADCgYJBgAAAA==.Ungee:BAABLgAECn8WAAIEAAYJ5x1VEAC+AQAEAAYJ5x1VEAC+AQAAAA==.Unicornz:BAAALgADCgQJBQAAAA==.Unicornzz:BAAALgADCgYJCwAAAA==.Unikorn:BAAALgADCgUJBQAAAA==.Unnamedlock:BAAALgADCgUJBwAAAA==.Unnaturall:BAABLgAECn8iAAIRAAkJrRwAJQCpAgARAAkJrRwAJQCpAgAAAA==.',
Ur='Uronar:BAAALgAECgUJCQAAAA==.Urthron:BAABLgAECn8VAAIPAAcJxAffLQATAQAPAAcJxAffLQATAQAAAA==.',
Us='Ushibaalushi:BAACLgAFFH8GAAIPAAMJYgRjFQDeAAAPAAMJYgRjFQDeAAAuAAQKfxoAAw8ABwmMGVlgABoCAA8ABwmMGVlgABoCACcAAQlWBlcRACwAAAAA.Ushiokami:BAAALgADCgcJDAABLgAFFAMJBgAPAGIEAA==.Usumbich:BAAALgAECgEJAQAAAA==.',
Ut='Utaan:BAAALgADCgkJFQABLgAECgYJDAABAAAAAA==.Utz:BAAALgAECggJDwAAAA==.',
Uw='Uwumage:BAAALgADCgIJAgAAAA==.',
Va='Vaelthar:BAAALgADCgUJCwAAAA==.Vanastan:BAAALgADCgMJBAAAAA==.Vanhealings:BAAALgADCgYJBgAAAA==.',
Ve='Velerunar:BAAALgADCgEJAQAAAA==.Velkrin:BAAALgADCgYJDQAAAA==.Vellia:BAAALgADCgIJAgAAAA==.Vemin:BAAALgADCgkJEQAAAA==.Venomenon:BAAALgAECgQJDAAAAA==.Verdereina:BAAALgADCgYJEwAAAA==.Veroshia:BAAALgAECgMJBAAAAA==.Vexea:BAAALgAECgMJAwABLgAECggJFQADACofAA==.',
Vi='Vinçent:BAAALgAECgIJAgAAAA==.Virali:BAABLgAECn8aAAIIAAgJ0Qm7HgATAQAIAAgJ0Qm7HgATAQAAAA==.Virescent:BAAALgAECgQJBQAAAA==.Virulant:BAAALgADCgMJAwAAAA==.Vispper:BAABLgAECn8VAAIoAAcJgg/VCAC8AQAoAAcJgg/VCAC8AQAAAA==.',
Vk='Vkdk:BAABLgAECn8dAAIRAAgJ3BEtEACVAQARAAgJ3BEtEACVAQAAAA==.Vkm:BAAALgAECgEJAgAAAA==.',
Vo='Vociva:BAAALgAECgYJEgAAAA==.Volvur:BAAALgAECgQJBwAAAA==.Voxmachina:BAAALgAECgYJCQAAAA==.',
Vr='Vriknort:BAABLgAECn8dAAIMAAgJZRUEJgApAgAMAAgJZRUEJgApAgAAAA==.Vromiaris:BAAALgAECgEJAgAAAA==.',
Vy='Vykaji:BAAALgADCgMJAwAAAA==.Vyllin:BAABLgAECn8jAAIIAAgJthNmBABtAQAIAAgJthNmBABtAQAAAA==.Vynarran:BAAALgAECgEJAQAAAA==.Vyradox:BAAALgAECgUJCAABLgAFFAQJBQAHAFkMAA==.',
Wa='Waffels:BAAALgADCgEJAQAAAA==.Walaje:BAAALgADCgEJAQAAAA==.Warq:BAAALgADCgYJBgAAAA==.Warwithin:BAAALgADCgkJDQAAAA==.',
We='Weebscum:BAAALgAECgEJAQAAAA==.',
Wh='Whiskeybacon:BAAALgAECgQJBQAAAA==.Whitewater:BAAALgAECgQJBAAAAA==.Whoyoumadat:BAAALgADCgYJBwAAAA==.',
Wi='Wichlock:BAAALgADCgEJAQAAAA==.Willowblessu:BAACLgAFFH8LAAIlAAQJ8QR2BQATAQAlAAQJ8QR2BQATAQAuAAQKfyYAAiUACQkQFtwSABsCACUACQkQFtwSABsCAAAA.Winna:BAAALgAECgYJCAAAAA==.Wishofloki:BAABLgAECn8bAAIUAAYJ6x1hGAD8AQAUAAYJ6x1hGAD8AQAAAA==.Wisly:BAAALgAECgIJAgAAAA==.',
Wo='Wolfellence:BAAALgADCgEJAgAAAA==.Wolfpriest:BAAALgADCgQJBgAAAA==.Wolty:BAAALgADCgUJCAAAAA==.',
Wr='Wrayvin:BAAALgADCgkJBQAAAA==.Wrek:BAAALgADCgEJAQAAAA==.Wrekhaus:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.',
Wu='Wuschlong:BAAALgAECgQJBAAAAA==.',
Wy='Wylinda:BAAALgADCgMJAwAAAA==.',
['Wâ']='Wârden:BAAALgADCgMJAwAAAA==.',
Xa='Xalgage:BAAALgAECgMJBAAAAA==.Xalgor:BAAALgAECgIJAgAAAA==.Xanaduke:BAAALgADCgEJAQAAAA==.',
Xd='Xdead:BAAALgADCgEJAQAAAA==.',
Xe='Xeghyss:BAAALgADCgQJBAAAAA==.Xelyres:BAAALgAECgYJDAAAAA==.',
Xi='Xiidra:BAAALgADCgcJCAABLgAFFAMJBAABAAAAAA==.Xingxingren:BAAALgAECgYJDQAAAA==.Xiouyu:BAAALgAECgEJAQAAAA==.',
Xy='Xylaa:BAAALgADCgIJAgAAAA==.',
['Xá']='Xándric:BAABLgAECn8hAAIWAAgJnhvVLQBsAgAWAAgJnhvVLQBsAgAAAA==.',
['Xé']='Xénos:BAAALgAECgIJAgAAAA==.',
Ya='Yamaiko:BAAALgAECgYJBgAAAA==.Yaoibl:BAAALgAECgIJAgAAAA==.',
Ye='Yeralt:BAAALgAECgUJBQAAAA==.',
Yi='Yidaizongshi:BAAALgADCgkJDAAAAA==.Yinhak:BAAALgAECgEJAQAAAA==.Yivory:BAAALgAECgYJEQAAAA==.',
Yo='Yodel:BAAALgAECgEJAgAAAA==.Yokux:BAABLgAECn8nAAQgAAgJFSBXDwCrAgAgAAgJFSBXDwCrAgAiAAYJdSEFIgA2AgALAAQJ6wleIwC7AAAAAA==.Yokuz:BAAALgADCgcJCgABLgAECggJJwAgABUgAA==.',
Ys='Ysora:BAABLgAECn8XAAMCAAcJxwy7VgBkAQACAAcJxwy7VgBkAQADAAEJGwEDmgAZAAAAAA==.',
Yu='Yungdarb:BAAALgADCgYJBgABLgAECggJGwAnAOkaAA==.Yurdond:BAAALgAECgMJBAAAAA==.',
Za='Zaivama:BAAALgAECgIJAgAAAA==.Zalthor:BAAALgAECgEJAQAAAA==.Zaranthari:BAAALgADCgkJCgAAAA==.Zarindela:BAACLgAFFH8TAAIPAAQJexpaBgBuAQAPAAQJexpaBgBuAQAuAAQKf0oAAycACQldIXYBAJMCAA8ACQlOIWYlAN0CACcABwnvHnYBAJMCAAAA.Zarvandel:BAABLgAECn8WAAIYAAcJIAewKwDHAAAYAAcJIAewKwDHAAAAAA==.',
Ze='Zeenalizard:BAAALgAECgUJEQAAAA==.Zelay:BAAALgAECgMJBAAAAA==.Zelkarion:BAAALgADCgEJAQAAAA==.Zellik:BAAALgADCgUJCAAAAA==.Zenaxus:BAAALgADCgcJEAAAAA==.Zendoh:BAAALgADCgQJBAAAAA==.Zephius:BAAALgADCgQJDgAAAA==.Zeromana:BAAALgADCgcJBwAAAA==.',
Zh='Zhaoo:BAAALgADCgQJBAAAAA==.',
Zi='Zixxiee:BAAALgADCgkJCQAAAA==.',
Zo='Zoraxus:BAAALgADCgEJAQAAAA==.',
Zu='Zulraven:BAAALgADCgcJCAAAAA==.',
Zy='Zyraen:BAAALgADCgIJAQABLgADCgcJBwABAAAAAA==.Zyzyy:BAAALgADCgMJAwAAAA==.',
['Áf']='Áfterlight:BAAALgADCgIJAgAAAA==.',
['Ðe']='Ðeimor:BAAALgAECgQJBgABLgAECgcJCAABAAAAAA==.',
['ßi']='ßiz:BAABLgAECn8YAAIVAAcJARC6DgAKAQAVAAcJARC6DgAKAQAAAA==.',
['ßâ']='ßâßygirl:BAAALgAECgUJBgAAAA==.',
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
