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

local lookup = {'Shaman-Restoration','Warlock-Destruction','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Hunter-Survival','Hunter-Marksmanship','Evoker-Augmentation','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Enhancement','Monk-Brewmaster','Paladin-Protection','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','Warrior-Protection','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Druid-Balance','Warlock-Demonology','DemonHunter-Havoc','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Warrior-Arms','Rogue-Assassination','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aartoo:BAAALgADCgUJBwAAAA==.',
Ac='Ace:BAAALgAECgQJBQAAAA==.Ackreshanot:BAAALgAECgUJDQABLgAFFAQJDwABAGEdAA==.Acuminada:BAAALgADCgUJBQAAAA==.Acuna:BAABLgAECn8cAAICAAcJGBOFBwBrAQACAAcJGBOFBwBrAQAAAA==.',
Ad='Adamantine:BAAALgAECgcJEQAAAA==.',
Ae='Aere:BAAALgAECgYJDwAAAA==.Aerotika:BAAALgADCgcJBwAAAA==.',
Ai='Airz:BAABLgAECn8fAAIDAAcJQhnsDQANAgADAAcJQhnsDQANAgAAAA==.',
Ak='Akennethpaly:BAAALgADCgQJBwAAAA==.Aknou:BAAALgADCgQJBAAAAA==.Akrichie:BAAALgAECgEJAQABLgAFFAYJEAAEAIkMAA==.Akudama:BAAALgAECgUJCAAAAA==.Akâkiôs:BAABLgAECn8bAAIFAAgJthT9EQDMAQAFAAgJthT9EQDMAQAAAA==.',
Al='Aladorman:BAABLgAECn8UAAIGAAcJtQeOTQAlAQAGAAcJtQeOTQAlAQAAAA==.Albertlin:BAAALgAECggJEwAAAA==.Aldin:BAAALgAECgUJDgAAAA==.Aleisterr:BAAALgADCgEJAQAAAA==.Alexpaladin:BAAALgADCgEJAQAAAA==.Altarya:BAAALgAECgYJBgABLgAECgcJDgAHAAAAAA==.Altex:BAABLgAECn8kAAIIAAkJ3xmHGQBSAgAIAAkJ3xmHGQBSAgAAAA==.Altexa:BAAALgADCgMJAwABLgAFFAEJAgAHAAAAAA==.Altriimus:BAAALgAECgQJCgAAAA==.',
Am='Amakuagsak:BAABLgAECn8cAAIGAAYJjg+PWQADAQAGAAYJjg+PWQADAQAAAA==.Amicus:BAABLgAECn8bAAIJAAYJug1rQQANAQAJAAYJug1rQQANAQAAAA==.',
An='Anadarmas:BAAALgAECgUJBwAAAA==.Ancestor:BAAALgADCgUJBQAAAA==.Aneki:BAAALgAECgEJAQAAAA==.Angelcastiel:BAAALgADCgEJAQAAAA==.Anothertalas:BAAALgAECgIJAQAAAA==.Anthracss:BAAALgAECgQJBAAAAA==.Anthren:BAAALgADCgYJBgABLgAECgIJAwAHAAAAAA==.Anthrun:BAAALgADCgEJAgABLgAECgIJAwAHAAAAAA==.',
Ao='Aoifè:BAAALgAECgMJCQAAAA==.',
Ap='Apollo:BAABLgAECn8iAAMKAAgJyRreKwDOAQAKAAgJyRreKwDOAQALAAMJdgfYdQCjAAAAAA==.Apolynnae:BAAALgADCgMJAwABLgAFFAEJAQAHAAAAAA==.Apolynnæ:BAAALgAFFAEJAQAAAA==.',
Aq='Aquanoria:BAAALgADCggJEwAAAA==.',
Ar='Aragaren:BAAALgAECgYJBgAAAA==.Arasthel:BAAALgAECggJCwAAAA==.Arthalion:BAAALgAECgEJAQAAAA==.Arvellonwen:BAAALgADCgEJAQAAAA==.Aryasilly:BAAALgAECgUJBQAAAA==.',
As='Ascalapha:BAAALgAECgcJBwAAAA==.Ashe:BAACLgAFFH8XAAMMAAUJXSY5AQC+AQAMAAQJTSU5AQC+AQANAAUJ2RvDCQB9AQAuAAQKfzAAAw0ACQmhJkEAAPADAA0ACQmdJkEAAPADAAwABQmYJfQOALoBAAAA.',
At='Attabubble:BAAALgADCgEJAQABLgAFFAUJDwAGAF0fAA==.Attaraxia:BAACLgAFFH8PAAIGAAUJXR8WEABZAQAGAAUJXR8WEABZAQAuAAQKfycAAwYACQkSI/sJAPgCAAYACQkSI/sJAPgCAA0AAQm4AYOZABsAAAAA.',
Au='Aure:BAAALgADCgMJAwAAAA==.Aurelith:BAAALgADCgMJBAAAAA==.Auvona:BAAALgAECgYJCAAAAA==.',
Av='Avalora:BAAALgADCgcJCQAAAA==.',
Az='Azaleth:BAAALgAECgYJBgAAAA==.Azavin:BAABLgAECn8WAAILAAgJNAwKNgCkAQALAAgJNAwKNgCkAQABLgAECgcJFwAOALQVAA==.',
Ba='Babba:BAAALgADCgQJBAAAAA==.Baegar:BAAALgAECggJCQAAAA==.Bakugo:BAACLgAFFH8QAAIEAAQJ+hMwEQA+AQAEAAQJ+hMwEQA+AQAuAAQKfyUABAQACQnoH8EJAJ4CAAQACQnxHcEJAJ4CAA8ABgmNH+8gANsBABAABgkhF6YZAG8BAAAA.Bamfbutcher:BAABLgAECn8aAAIRAAkJXhd5DwD8AQARAAkJXhd5DwD8AQAAAA==.Banang:BAAALgADCgUJBQAAAA==.Barrimen:BAABLgAECn8fAAIKAAgJZQv+SQBnAQAKAAgJZQv+SQBnAQAAAA==.Bartolomew:BAAALgAECggJIwAAAQ==.Bashton:BAAALgADCgMJAwAAAA==.Bastian:BAAALgADCgEJAQAAAA==.Batboy:BAAALgAECgYJEgAAAA==.',
Be='Bealzabung:BAAALgADCgMJAwABLgAECgQJBwAHAAAAAA==.Bedemere:BAAALgAECgEJAQAAAA==.Beepers:BAABLgAECn8fAAIGAAkJKw6zJQC+AQAGAAkJKw6zJQC+AQAAAA==.Behodahlia:BAABLgAECn8cAAIDAAgJvwgUJQAfAQADAAgJvwgUJQAfAQAAAA==.Benezra:BAAALgAECgEJAQAAAA==.Bexurk:BAABLgAECn8YAAMSAAgJTAXtDAA5AQASAAgJTAXtDAA5AQAFAAEJwgNpbgAnAAAAAA==.',
Bi='Biaku:BAAALgADCgIJAgAAAA==.Bibleman:BAAALgADCgIJAgABLgAECgcJFwADACAYAA==.Bigbilly:BAAALgADCgkJCQAAAA==.Bigcalcium:BAABLgAECn8nAAIKAAgJ/yWMBgBmAwAKAAgJ/yWMBgBmAwAAAA==.Bigdemon:BAAALgAECgcJCwAAAA==.Bighimbo:BAABLgAECn8VAAIDAAYJUiBIDAAlAgADAAYJUiBIDAAlAgAAAA==.Biltix:BAACLgAFFH8NAAITAAQJNSEpBwCIAQATAAQJNSEpBwCIAQAuAAQKfyIAAhMACQnpHsgSAHwCABMACQnpHsgSAHwCAAAA.Bimzelx:BAAALgAECgMJBQAAAA==.Bipolar:BAAALgAECgUJDAAAAA==.Bitterblood:BAAALgAECgYJEgAAAA==.',
Bl='Blanche:BAAALgADCgYJBgAAAA==.Blastgamer:BAAALgAECgMJBQAAAA==.Blindbob:BAAALgADCgUJBwAAAA==.Blueb:BAAALgADCgkJEgABLgAFFAMJBgAPAMgSAA==.',
Bo='Bocaj:BAAALgADCgEJAQABLgAECggJKgAIACMdAA==.Boltbourne:BAAALgADCgUJBQAAAA==.Bolyn:BAAALgAECgIJAgAAAA==.Bonami:BAAALgADCgYJBgAAAA==.Bongwizard:BAAALgADCgUJBQAAAA==.Booshi:BAABLgAECn8cAAIJAAgJbhUbNwDLAQAJAAgJbhUbNwDLAQAAAA==.Bowiiesenpai:BAABLgAECn8iAAIQAAkJAR/WBACWAgAQAAkJAR/WBACWAgAAAA==.Bowmarc:BAABLgAECn8cAAIKAAkJFw2aPQCNAQAKAAkJFw2aPQCNAQAAAA==.Boykisser:BAAALgAECgUJBQAAAA==.',
Br='Bravehearth:BAAALgAECgIJAwABLgAECgQJBwAHAAAAAA==.Brewcifer:BAAALgADCgYJBgAAAA==.Brightxan:BAABLgAECn8iAAIUAAkJpxdbCgApAgAUAAkJpxdbCgApAgAAAA==.Broamdar:BAAALgAECgkJBgAAAA==.Brotha:BAAALgADCgUJCgAAAA==.Brownbeard:BAABLgAECn8aAAIVAAgJPBKABACjAQAVAAgJPBKABACjAQAAAA==.',
Bu='Bubbapriest:BAAALgADCgMJAwAAAA==.Bubbashaman:BAAALgAECgYJDQAAAA==.Budgetsushi:BAAALgADCgcJCwAAAA==.Burninator:BAABLgAECn8ZAAQWAAkJ4hWFEwCrAQAWAAYJrhmFEwCrAQAOAAkJYBGvIgCpAQAXAAIJJw1JQABoAAAAAA==.Bus:BAABLgAFFH8LAAIYAAUJhCIaAQD5AQAYAAUJhCIaAQD5AQABLgAFFAgJDgAZAH8fAA==.Butterrs:BAAALgAECgUJEAAAAQ==.Butterz:BAABLgAECn8fAAIFAAkJuB5DCwDkAgAFAAkJuB5DCwDkAgABLgAECgUJEAAHAAAAAA==.',
Ca='Cadjin:BAAALgAECgEJAQAAAA==.Caelan:BAAALgAECgcJDAAAAA==.Caloren:BAABLgAECn8pAAMaAAgJUiHACgB/AgAaAAgJUiHACgB/AgAbAAEJ0RleGwBIAAAAAA==.Calqlated:BAAALgADCgYJBgABLgAECggJEgAHAAAAAA==.Caorou:BAAALgADCgYJBgAAAA==.Captflower:BAAALgADCgUJBQAAAA==.',
Ce='Cedrid:BAAALgAECgIJBAAAAA==.Cenauria:BAAALgADCgYJBgAAAA==.',
Ch='Chanit:BAABLgAECn8dAAIKAAgJHxWaKADdAQAKAAgJHxWaKADdAQAAAA==.Chaosbeast:BAAALgADCgEJAQAAAA==.Charuzu:BAAALgAECggJEwAAAA==.Chaurana:BAABLgAECn8eAAIbAAgJGRZiBgCYAQAbAAgJGRZiBgCYAQAAAA==.Chenzio:BAAALgADCgUJBQAAAA==.Chikorita:BAAALgAECgcJDgAAAA==.Chilidan:BAAALgAECgIJAgAAAA==.Chimichurri:BAAALgAECgMJAwAAAA==.Chipo:BAAALgAECgEJAgAAAA==.Chrilynn:BAABLgAECn8ZAAMKAAYJWxkrRAB5AQAKAAYJWxkrRAB5AQAUAAQJhRJFKADHAAAAAA==.Chuwee:BAAALgADCgIJAgAAAA==.',
Ci='Cind:BAAALgADCgcJCAABLgAECgcJAQAHAAAAAA==.Cinderatrath:BAACLgAFFH8TAAIWAAUJnxLkAQBOAQAWAAUJnxLkAQBOAQAuAAQKfyoAAhYACAkRIkkDAOsCABYACAkRIkkDAOsCAAAA.Cindoreon:BAAALgAECgcJAQAAAA==.',
Cn='Cnydemon:BAAALgADCgEJAQAAAA==.',
Co='Corsaro:BAAALgAECgQJCwAAAA==.Corvixius:BAABLgAECn8YAAIRAAcJSwptLgAVAQARAAcJSwptLgAVAQAAAA==.',
Cr='Crunchwrap:BAAALgAECgYJEAAAAA==.',
Cu='Cuigy:BAABLgAECn8ZAAIBAAcJiCFUDgBSAgABAAcJiCFUDgBSAgAAAA==.',
Cy='Cyriene:BAABLgAECn8ZAAIGAAYJhw8pTwAgAQAGAAYJhw8pTwAgAQAAAA==.Cyrik:BAABLgAECn8XAAMcAAgJFR3NBwDUAQAcAAgJFR3NBwDUAQACAAUJYhEXKQAeAQAAAA==.',
Da='Daevas:BAAALgADCgEJAQABLgAECgcJFwADACAYAA==.Danksinatra:BAABLgAECn8aAAIdAAgJPRVLJwDiAQAdAAgJPRVLJwDiAQAAAA==.Danté:BAABLgAECn8cAAIIAAcJ/Ru4UgA/AgAIAAcJ/Ru4UgA/AgAAAA==.Dardorian:BAAALgAECgEJAgAAAA==.Darkfist:BAAALgAECgUJBgAAAA==.Darko:BAAALgAECgQJCgAAAA==.Darou:BAABLgAECn8YAAMVAAgJZA0qCQBKAQAVAAgJZA0qCQBKAQAeAAEJHQL1TwAVAAAAAA==.Daylen:BAABLgAECn8aAAIPAAgJ5A9pFwCWAQAPAAgJ5A9pFwCWAQAAAA==.',
De='Deactrim:BAAALgAFFAEJAQAAAA==.Deadploo:BAAALgADCgMJAwAAAA==.Deadpòól:BAAALgADCgUJBQABLgAECgIJAgAHAAAAAA==.Deafknights:BAAALgAECgQJBwABLgAFFAEJAgAHAAAAAA==.Deathgoat:BAAALgADCgIJAgAAAA==.Deku:BAAALgAECgQJCgABLgAECggJHAAZABkWAA==.Demiglace:BAABLgAECn8oAAQTAAgJmSaDAQAZAwATAAgJmSaDAQAZAwAfAAEJMRl/UQBIAAADAAEJxxTBaAAwAAABLgAFFAcJHgAaAL8gAA==.Demonfloozie:BAAALgADCgkJCQAAAA==.Demongal:BAAALgADCgQJBAAAAA==.Dendrada:BAABLgAECn8aAAIdAAgJqR7CEQBuAgAdAAgJqR7CEQBuAgAAAA==.Dewbie:BAACLgAFFH8JAAIMAAQJdRqsBAByAQAMAAQJdRqsBAByAQAuAAQKfyQAAgwACQktFzkJABICAAwACQktFzkJABICAAAA.',
Di='Dirtyshim:BAAALgAECgMJAwAAAA==.Dizimo:BAABLgAECn8ZAAIJAAcJOyNpCADFAgAJAAcJOyNpCADFAgAAAA==.',
Dm='Dminn:BAAALgAECgQJBQAAAA==.',
Do='Dogmeat:BAACLgAFFH8LAAIGAAQJeRxVAgB6AQAGAAQJeRxVAgB6AQAuAAQKfx8AAgYABwmgIqUWAIMCAAYABwmgIqUWAIMCAAEuAAUUBgkMACAAhBAA.Doncowleone:BAAALgADCgMJAwABLgAECgQJBwAHAAAAAA==.Doomslayer:BAAALgADCgcJDgAAAA==.Doreniel:BAAALgAECgkJAgAAAA==.Dormo:BAAALgAECgcJBwABLgAECgcJFwADACAYAA==.Dotisa:BAAALgAECgYJDQAAAA==.',
Dr='Draxker:BAABLgAECn8cAAIWAAgJtw6zBQB+AQAWAAgJtw6zBQB+AQAAAA==.Dreadmourne:BAAALgAECgUJBQAAAA==.Drfumanchu:BAAALgADCgUJCAABLgAECgQJBwAHAAAAAA==.Druddigon:BAAALgAECgUJBgABLgAECggJEgAHAAAAAA==.',
Du='Duna:BAABLgAECn8VAAIIAAYJQQrnhQAGAQAIAAYJQQrnhQAGAQAAAA==.Duvidressra:BAABLgAECn8jAAMcAAgJwg1EBQB4AQAcAAgJwg1EBQB4AQAhAAMJTAV0/QBgAAAAAA==.',
Dx='Dxmvn:BAAALgADCgEJAQAAAA==.',
Dy='Dyingmight:BAAALgAECgQJBAAAAA==.',
['Dä']='Dävïs:BAAALgAECggJEwABLgAECgkJEAAHAAAAAA==.',
Ed='Edea:BAAALgAECgQJBwAAAA==.Edisonn:BAACLgAFFH8HAAIhAAQJrAztLwANAQAhAAQJrAztLwANAQAuAAQKfyQAAyEACAkiHmMRAFkCACEACAkiHmMRAFkCAAIAAwl/HDw7AMcAAAAA.',
El='Eldarya:BAAALgAECgUJBgAAAA==.Eldermoon:BAAALgAECgYJCAAAAA==.Elghinn:BAABLgAECn8rAAIiAAgJqROlDAC3AQAiAAgJqROlDAC3AQAAAA==.Ellie:BAABLgAECn8oAAIGAAgJUx5rFAAtAgAGAAgJUx5rFAAtAgAAAA==.Elponch:BAAALgAECgcJBgAAAA==.Elroy:BAABLgAECn8pAAIKAAgJbxOiNACrAQAKAAgJbxOiNACrAQAAAA==.',
Em='Embold:BAACLgAFFH8WAAINAAYJaSIPAgBRAgANAAYJaSIPAgBRAgAuAAQKfy0AAg0ACQnqJWYAAOcDAA0ACQnqJWYAAOcDAAAA.Emernantus:BAABLgAECn8mAAIUAAgJvw4jEgAeAQAUAAgJvw4jEgAeAQAAAA==.Emozi:BAABLgAECn8sAAMhAAkJ1hHUHgD4AQAhAAkJEhHUHgD4AQAcAAYJoBHOCwB9AQAAAA==.',
Eu='Eunbyeol:BAABLgAECn8jAAIRAAgJcxscFADLAQARAAgJcxscFADLAQAAAA==.',
Ex='Excidium:BAAALgAECgYJDQAAAA==.Expired:BAAALgAECgUJBQAAAA==.',
Fa='Faeria:BAABLgAECn8hAAIPAAcJVRoSDgAGAgAPAAcJVRoSDgAGAgAAAA==.Fangwalker:BAAALgAECgQJDgAAAA==.Farmerdotcom:BAAALgADCgEJAQAAAA==.Fatnchunkydk:BAABLgAECn8ZAAIeAAYJggzGHgDMAAAeAAYJggzGHgDMAAAAAA==.Fatpigeon:BAAALgAECgYJCgAAAA==.',
Fe='Feeblemind:BAABLgAECn8aAAIGAAcJaBj6NAB5AQAGAAcJaBj6NAB5AQAAAA==.Feesherman:BAABLgAFFH8IAAIKAAQJKyTIBQCvAQAKAAQJKyTIBQCvAQAAAA==.Feli:BAABLgAECn8ZAAIRAAgJmQtGHACGAQARAAgJmQtGHACGAQAAAA==.Felldor:BAAALgADCgUJAgAAAA==.Felmommy:BAAALgADCgYJBgAAAA==.Felrindan:BAAALgAECgYJDAAAAA==.Felscream:BAAALgADCgUJBQAAAA==.Fender:BAABLgAECn8bAAIjAAgJrBWXBgDZAQAjAAgJrBWXBgDZAQAAAA==.Ferchrian:BAAALgADCgEJAQAAAA==.',
Fi='Finfangfoom:BAAALgAECgQJBwAAAA==.Fingertoes:BAABLgAECn8qAAMIAAgJIx3YHAA9AgAIAAgJIx3YHAA9AgAkAAEJNxBADQA9AAAAAA==.Fistamista:BAAALgAECggJDAAAAA==.Fizban:BAAALgADCggJFAAAAA==.',
Fl='Flaygar:BAAALgAECgYJDAAAAA==.Flory:BAABLgAECn8qAAIKAAkJLxtcEAB5AgAKAAkJLxtcEAB5AgAAAA==.Flowpro:BAAALgADCgMJAwAAAA==.Flyinweasle:BAAALgAECgUJBQAAAA==.',
Fo='Foundation:BAAALgAECgYJCgAAAA==.Foxxycontin:BAABLgAECn8cAAQPAAcJEBDnMAB9AQAPAAcJEBDnMAB9AQAEAAIJ5gZ1PQBXAAAQAAEJFQZ3ZgAsAAAAAA==.',
Fr='Freemay:BAAALgAECgUJBQAAAA==.Frostyrican:BAAALgAECgEJAQAAAA==.',
Fu='Fuglybaby:BAAALgADCgUJBQAAAA==.',
Fw='Fwakos:BAAALgADCgUJCQAAAA==.',
['Fé']='Fénnie:BAAALgADCgMJAwAAAA==.',
Ga='Gaivahros:BAABLgAECn8VAAIKAAgJuwRtcwAFAQAKAAgJuwRtcwAFAQAAAA==.Gakpaladin:BAABLgAECn8rAAIUAAgJ8hwaBQAnAgAUAAgJ8hwaBQAnAgAAAA==.Galileo:BAAALgAECgYJEQAAAA==.Garland:BAAALgAECgcJDQAAAA==.',
Ge='Gerasstrois:BAAALgAECgcJEQABLgAECggJIwAcAMINAA==.Gerionier:BAAALgADCgEJAQABLgAECgYJEAAHAAAAAA==.Gethael:BAAALgAECgIJAwAAAA==.',
Gh='Ghalathor:BAAALgAECgQJBAAAAA==.',
Gl='Glimsy:BAAALgADCgYJCQAAAA==.Glittermilk:BAAALgADCgUJBQAAAA==.Glizzyglock:BAAALgADCgUJAwABLgAECggJKgAIACMdAA==.',
Go='Golosan:BAABLgAECn8iAAITAAkJJR3OBQCCAgATAAkJJR3OBQCCAgAAAA==.Goododie:BAABLgAECn8bAAIKAAYJux0GPQCPAQAKAAYJux0GPQCPAQAAAA==.Gordil:BAAALgAECgUJBQAAAA==.Gorokan:BAAALgAECgIJAwAAAA==.',
Gr='Grayback:BAAALgAECgcJBgABLgAFFAEJAgAHAAAAAA==.Grimsdeath:BAAALgADCgUJBQAAAA==.',
Gu='Guila:BAABLgAECn8eAAIhAAgJiQycPAB1AQAhAAgJiQycPAB1AQAAAA==.Gulaken:BAAALgAECgYJEAAAAA==.',
Ha='Hafnia:BAAALgAECgcJEgAAAA==.Hai:BAAALgAECgEJAQAAAA==.Halphion:BAAALgADCgYJBwABLgAECggJGQALAOIcAA==.Hangry:BAAALgAECgEJAQAAAA==.Hanoe:BAAALgADCgYJBgAAAA==.Haoasakura:BAABLgAECn86AAIKAAkJ/iIxAwAoAwAKAAkJ/iIxAwAoAwAAAA==.Haybuse:BAABLgAECn8nAAIMAAkJkCBjAwCiAgAMAAkJkCBjAwCiAgAAAA==.',
He='Healmd:BAAALgADCgMJAwAAAA==.Healsforhugs:BAAALgADCgMJAwAAAA==.Healzforfood:BAAALgAECgYJCQAAAA==.Healzyou:BAAALgADCgMJAwAAAA==.Heap:BAABLgAECn8jAAIZAAkJdA2pEQBbAQAZAAkJdA2pEQBbAQAAAA==.Hectavius:BAAALgAECgEJAgAAAA==.Hells:BAAALgAECgEJAQAAAA==.Hellslinger:BAAALgAECgQJBwAAAA==.Hewnoshaqa:BAABLgAECn8cAAIGAAgJ9wzrNAB5AQAGAAgJ9wzrNAB5AQAAAA==.Hexeñ:BAABLgAECn8WAAIBAAgJAhNlHQDGAQABAAgJAhNlHQDGAQAAAA==.Hexorcist:BAACLgAFFH8MAAIBAAQJRxt+EwAoAQABAAQJRxt+EwAoAQAuAAQKfxcAAwEACAnPGYUbADwCAAEACAnPGYUbADwCAAUAAwnVGbtaANkAAAAA.',
Hi='Hickerbilly:BAAALgAECgkJEAAAAA==.Higgintoot:BAAALgAECgIJAgABLgAECggJGgAMADwPAA==.Hitormist:BAABLgAECn8XAAIDAAcJIBiUEADnAQADAAcJIBiUEADnAQAAAA==.',
Ho='Holyshoot:BAAALgAECgMJBQAAAA==.Holyspanks:BAAALgADCgEJAQABLgAECggJIgAOAEoaAA==.Horous:BAAALgADCgkJAgAAAA==.Hotdoog:BAAALgADCgUJBgABLgAECgQJCgAHAAAAAA==.',
Hr='Hruuli:BAAALgAECgIJAgAAAA==.',
Hu='Hungweilow:BAAALgADCgUJBgABLgAECgQJBwAHAAAAAA==.Huugar:BAABLgAECn8cAAIFAAYJGg9cLwD3AAAFAAYJGg9cLwD3AAAAAA==.Huulhai:BAAALgAECgYJBgAAAA==.',
['Hæ']='Hædés:BAABLgAECn8bAAIUAAgJLxtfBgD+AQAUAAgJLxtfBgD+AQAAAA==.',
Ib='Ibeamwork:BAAALgAECgcJEAAAAA==.',
Ic='Icoulddowork:BAAALgADCgQJBAABLgAECgcJEAAHAAAAAA==.Icyconjurer:BAAALgADCgMJAwAAAA==.',
Id='Idoworkz:BAAALgADCgcJBwABLgAECgcJEAAHAAAAAA==.',
Ii='Iiquorice:BAAALgAECgMJAwAAAA==.',
Ik='Ikazuchi:BAABLgAECn8kAAIVAAgJfRcPAwDzAQAVAAgJfRcPAwDzAQAAAA==.',
Il='Illcutabish:BAABLgAECn8rAAIlAAkJZRjvBwApAgAlAAkJZRjvBwApAgAAAA==.',
Im='Imk:BAABLgAECn8cAAMaAAgJ8RCZLQCBAQAaAAgJ8RCZLQCBAQAbAAMJNALYGQBTAAAAAA==.',
In='Ineedatarget:BAAALgADCgEJAQAAAA==.Intbuff:BAAALgAECgIJAgABLgAECgYJDwAHAAAAAA==.Invadiah:BAAALgAECgcJDQAAAA==.Invited:BAAALgAFFAEJAQAAAA==.',
Io='Iock:BAEALgAECgUJCAAAAA==.',
Ir='Ironarms:BAAALgADCgUJBQAAAA==.',
Iw='Iwdominate:BAAALgAECgYJCQAAAA==.',
Iy='Iyana:BAAALgAECgMJBgAAAA==.',
Iz='Izümi:BAABLgAECn8cAAIMAAgJ6BbNCgD2AQAMAAgJ6BbNCgD2AQAAAA==.',
Ja='Jazz:BAAALgADCgcJDgAAAA==.',
Je='Jennypoo:BAABLgAECn84AAMJAAkJgx3RBQD4AgAJAAkJgx3RBQD4AgAgAAIJQwoDTQBQAAAAAA==.Jessd:BAAALgAECgIJBAAAAA==.',
Ji='Jild:BAAALgAECgQJBwAAAA==.Jinwoosung:BAAALgAECgYJDQAAAA==.',
Jo='Johnwarrior:BAABLgAECn8YAAIRAAgJehpaDwD9AQARAAgJehpaDwD9AQAAAA==.Jorrix:BAABLgAECn8kAAIKAAcJ2hR7NwCgAQAKAAcJ2hR7NwCgAQAAAA==.',
Ju='Juduspriestt:BAABLgAECn8iAAIKAAgJXhUmMAC8AQAKAAgJXhUmMAC8AQAAAA==.Jurt:BAAALgADCgcJDQAAAA==.',
Ka='Kaalysto:BAAALgADCgMJAwAAAA==.Kadao:BAAALgAECgIJAgAAAA==.Kaekko:BAAALgADCgYJBgABLgAECgkJIAAKAOMcAA==.Kaeko:BAABLgAECn8dAAIQAAgJFRxqEACAAgAQAAgJFRxqEACAAgABLgAECgkJIAAKAOMcAA==.Kaelathaniel:BAABLgAECn8pAAMhAAgJUw4aNgCMAQAhAAgJUQ4aNgCMAQACAAEJeA7DdQAvAAAAAA==.Kalerito:BAABLgAECn8jAAIJAAgJ/SBXBwDYAgAJAAgJ/SBXBwDYAgAAAA==.Kalistae:BAABLgAECn8cAAMQAAgJex7gBgBlAgAQAAgJex7gBgBlAgAPAAEJ6h+/cwBZAAAAAA==.Kallivath:BAAALgADCgYJCAAAAA==.Kamdrixa:BAAALgADCgYJDAAAAA==.Kardie:BAAALgAECgUJBQAAAA==.Karinus:BAAALgADCgUJBQAAAA==.Karkaroff:BAAALgAECgcJAwABLgAFFAEJAgAHAAAAAA==.Karl:BAABLgAECn8dAAIIAAUJYQwmlwDkAAAIAAUJYQwmlwDkAAABLgAECgYJCgAHAAAAAA==.Karlack:BAAALgADCgUJBQAAAA==.Kaserr:BAACLgAFFH8RAAIlAAUJpBxlCABmAQAlAAUJpBxlCABmAQAuAAQKfygAAiUACQksIOYCAHcDACUACQksIOYCAHcDAAAA.Kayserdh:BAAALgAECgYJEQAAAA==.Kazaf:BAAALgAECgQJEQAAAA==.',
Ke='Keeirian:BAAALgADCgEJAQAAAA==.Keikoh:BAABLgAECn8gAAIKAAkJ4xzRCwCkAgAKAAkJ4xzRCwCkAgAAAA==.Keitrek:BAABLgAECn8rAAILAAgJBgvsHgCPAQALAAgJBgvsHgCPAQAAAA==.Kelleta:BAAALgAECgYJBgAAAA==.Kelthias:BAAALgADCgYJCgAAAA==.Kelypsoc:BAAALgAECgQJBgAAAA==.Kenichï:BAAALgAECgYJDwABLgAECggJFgABAAITAA==.Keomag:BAAALgAECgQJBwAAAA==.Kerwîck:BAABLgAECn8XAAILAAgJFhL8FwDMAQALAAgJFhL8FwDMAQAAAA==.Keyen:BAABLgAECn8hAAILAAgJjQdzKQBCAQALAAgJjQdzKQBCAQAAAA==.',
Kh='Khallan:BAABLgAECn8cAAIJAAgJDQbGQQAMAQAJAAgJDQbGQQAMAQAAAA==.Khazsz:BAABLgAECn8ZAAMZAAYJMiK5BwA6AgAZAAYJMiK5BwA6AgAjAAMJ/RSpJACuAAAAAA==.',
Ki='Kibalion:BAAALgAECggJDgAAAA==.Kiljaezyn:BAAALgAECgEJAgAAAA==.Killbent:BAAALgAECgUJCwAAAA==.Kilowatts:BAAALgADCgYJBgAAAA==.Kimjongwork:BAAALgAECgEJAQABLgAECgcJEAAHAAAAAA==.Kinnky:BAABLgAECn8bAAIIAAgJcBVVNgDIAQAIAAgJcBVVNgDIAQAAAA==.Kino:BAAALgAECgUJCQAAAA==.Kiratsuna:BAAALgAECgYJBgAAAA==.Kiriya:BAABLgAECn8YAAIJAAcJPQd5SgDpAAAJAAcJPQd5SgDpAAAAAA==.Kismiasu:BAAALgAECgYJBwAAAA==.Kitticakes:BAAALgADCgUJBQAAAA==.Kivdruid:BAACLgAFFH8HAAIJAAUJBAabFAAqAQAJAAUJBAabFAAqAQAuAAQKfyAAAwkACQmyGD0NAHoCAAkACQmyGD0NAHoCACAABAk4Dy9AAIEAAAAA.Kivpriest:BAAALgAFFAMJAwABLgAFFAUJBwAJAAQGAA==.',
Kk='Kkty:BAAALgADCgQJBwAAAA==.',
Ko='Koore:BAABLgAECn8cAAIUAAgJWhxBBQAiAgAUAAgJWhxBBQAiAgAAAA==.Korraavatar:BAAALgAECgIJAgAAAA==.',
Kp='Kpop:BAABLgAECn8TAAIaAAgJrx8MCwB7AgAaAAgJrx8MCwB7AgAAAA==.Kpopkhan:BAABLgAECn8PAAIaAAgJJQz6awBfAQAaAAgJJQz6awBfAQAAAA==.',
Kr='Kreettip:BAABLgAECn8iAAIPAAgJ0hEeLACXAQAPAAgJ0hEeLACXAQAAAA==.Krispy:BAAALgADCggJCAABLgAECggJKAAJAGYZAA==.',
Ku='Kugamoo:BAABLgAECn8hAAIgAAkJqxWtEgCxAQAgAAkJqxWtEgCxAQAAAA==.Kulgen:BAAALgADCgIJAgAAAA==.Kurgen:BAABLgAECn8bAAIKAAYJkRN6WwA5AQAKAAYJkRN6WwA5AQAAAA==.',
Ky='Kylex:BAAALgAECgEJAgAAAA==.Kyuyoung:BAAALgAECgEJAQABLgAECggJIwARAHMbAA==.',
['Kà']='Kàkárót:BAAALgADCgcJEwAAAA==.',
['Kí']='Kísámé:BAAALgAECgEJAQABLgAECggJHAAMAOgWAA==.',
La='Lamasacre:BAAALgAECgEJAQAAAA==.Lannybarby:BAABLgAECn8cAAIKAAYJ4wYqiwDXAAAKAAYJ4wYqiwDXAAAAAA==.Laotzu:BAABLgAECn8ZAAMOAAgJ0wi7LgBNAQAOAAcJNQm7LgBNAQAXAAgJ7AN3JwA4AQABLgAECgkJCgAHAAAAAA==.',
Lc='Lckdown:BAAALgAECggJEgAAAA==.',
Le='Legomyegolas:BAABLgAECn8aAAQGAAgJciIyCACvAgAGAAgJciIyCACvAgANAAMJNxpiWgDaAAAMAAEJAABPKgBdAAAAAA==.Leviticus:BAAALgADCgEJAQAAAA==.',
Li='Liara:BAAALgADCgEJAQAAAA==.Licentious:BAAALgADCgIJAgAAAA==.Lightsauce:BAAALgAECgYJCQAAAA==.Lilianis:BAAALgAECgIJAgAAAA==.Lilybloom:BAAALgAECgQJBAAAAA==.',
Lo='Loden:BAACLgAFFH8SAAIdAAQJuR6HEQBbAQAdAAQJuR6HEQBbAQAuAAQKfx4AAh0ACQk2IwsZAOYCAB0ACQk2IwsZAOYCAAAA.Lodex:BAAALgAECgEJAQAAAA==.Lokthal:BAAALgADCgYJBgAAAA==.Lootzu:BAAALgAECgkJAQAAAA==.Lovi:BAABLgAECn8iAAIBAAgJsxqkFAAPAgABAAgJsxqkFAAPAgAAAA==.',
Lu='Luckyboi:BAAALgAECgYJEwAAAA==.Luckymonk:BAABLgAECn8dAAQTAAkJAw7LGQBnAQATAAkJXw3LGQBnAQADAAQJMQMuRgBkAAAfAAIJQgkqRwBiAAABLgAECgYJEwAHAAAAAA==.Lucyl:BAAALgAECgMJAwAAAA==.Lumina:BAAALgAECgYJDwAAAA==.Lunaruu:BAAALgADCgEJAQAAAA==.Lusciifi:BAACLgAFFH8TAAIKAAUJUyStBQCwAQAKAAUJUyStBQCwAQAuAAQKfyUAAgoACAnUJRoGAGwDAAoACAnUJRoGAGwDAAAA.Luvva:BAAALgAECgIJAgAAAA==.',
Ly='Lykie:BAABLgAECn8mAAIUAAkJuxv6BwBbAgAUAAkJuxv6BwBbAgAAAA==.Lykiechi:BAAALgAECgYJBgABLgAECgkJJgAUALsbAA==.Lyllith:BAAALgADCgYJBgAAAA==.Lyone:BAABLgAECn8VAAIYAAcJKx/zBgAbAgAYAAcJKx/zBgAbAgAAAA==.',
['Lú']='Lúvaa:BAABLgAECn8mAAMdAAkJZiBSBwDnAgAdAAkJZiBSBwDnAgAeAAMJPSOiJAAbAQAAAA==.',
Ma='Maahun:BAAALgAECgEJAgAAAA==.Macavity:BAAALgAECgEJAQAAAA==.Maficwar:BAABLgAECn8tAAIYAAkJFRoOBQBZAgAYAAkJFRoOBQBZAgAAAA==.Mageyuwu:BAAALgAECgEJAQAAAA==.Magikkisback:BAAALgAECgcJEAAAAA==.Manarez:BAAALgAECgYJCgAAAA==.Mandorius:BAAALgAECgcJEgAAAA==.Manywagons:BAAALgAECgcJDQABLgAFFAkJLgAIAKYhAA==.Margherita:BAAALgAECgUJBQAAAA==.Mariora:BAAALgAECgEJAQAAAA==.Masacre:BAAALgAECgQJCAAAAA==.Mavalynal:BAAALgADCgcJEgAAAA==.Mavdeath:BAAALgAFFAIJAwAAAA==.Mavidari:BAABLgAECn8ZAAIaAAgJDB4dIQCKAgAaAAgJDB4dIQCKAgAAAA==.',
Mc='Mchammered:BAAALgADCgMJBgAAAA==.',
Me='Meeshie:BAACLgAFFH8GAAIPAAMJyBKSDgDnAAAPAAMJyBKSDgDnAAAuAAQKfy0ABA8ACAlkGjsQAGQCAA8ACAlkGjsQAGQCABAABwnjC4QeAEgBAAQABQngEqQqANQAAAAA.Meleys:BAAALgADCgcJCAAAAA==.',
Mi='Midoriya:BAACLgAFFH8PAAQhAAQJvyYoBgDHAQAhAAQJvyYoBgDHAQAcAAEJNCZTBAByAAACAAEJNhdcEwBYAAAuAAQKfyMABCEACQk+JmoMAI0CACEABwkTJmoMAI0CAAIAAwn5JZQhAEgBABwAAgmBJmsQAHEAAAAA.Mightyhunts:BAAALgAECgQJBQAAAA==.Mikuzume:BAAALgAECgUJCAAAAA==.Milkmage:BAABLgAECn8lAAIIAAgJux5EFQBwAgAIAAgJux5EFQBwAgAAAA==.Mintt:BAAALgAECgEJAQAAAA==.Mishima:BAAALgADCgMJAwAAAA==.Miznewbooty:BAABLgAECn8rAAMEAAkJqQ9RDAAMAgAEAAkJqQ9RDAAMAgAQAAQJog5URADaAAAAAA==.',
Mo='Moggark:BAAALgADCgcJCwAAAA==.Monknack:BAAALgAECgQJBAAAAA==.Moondofrond:BAAALgAECgIJAgAAAA==.Moonq:BAABLgAECn8bAAIJAAgJbQaPQgAJAQAJAAgJbQaPQgAJAQAAAA==.Moorti:BAABLgAECn8VAAMIAAYJ/Ru0TwB7AQAIAAYJ/Ru0TwB7AQAkAAEJww7yHAA5AAAAAA==.Moosaurus:BAABLgAECn8dAAIbAAgJqBE/CQBGAQAbAAgJqBE/CQBGAQAAAA==.Mosrael:BAAALgADCgEJAgAAAA==.',
Mu='Muffy:BAABLgAECn8VAAIXAAcJaA5aDgBeAQAXAAcJaA5aDgBeAQAAAA==.Muggyx:BAAALgADCgUJBQAAAA==.Multishoted:BAAALgADCgEJAQAAAA==.Murlouh:BAAALgADCgUJCAAAAA==.Mushudoobey:BAAALgAECgIJAgABLgAECggJIAAIAHQgAA==.',
My='Mylthrad:BAAALgADCgMJAwAAAA==.Mythnarra:BAACLgAFFH8OAAMbAAQJciRdAACpAQAbAAQJciRdAACpAQAaAAEJUgd3XgBEAAAuAAQKfy0AAxsACQnyJRUAAGoDABsACQnyJRUAAGoDABoABAl0Hf02AFoBAAAA.',
['Mí']='Mísanthrope:BAAALgAECgQJCQAAAA==.',
['Mô']='Mônster:BAAALgAECgUJCQAAAA==.',
['Mö']='Mönk:BAACLgAFFH8FAAIDAAMJthfeCgD7AAADAAMJthfeCgD7AAAuAAQKfx4AAgMACAmsHskMAIYCAAMACAmsHskMAIYCAAAA.',
['Mø']='Mønstèr:BAAALgAECgcJDAAAAA==.',
Na='Nachtimbess:BAAALgADCgYJBgABLgAFFAEJAQAHAAAAAA==.Nadaline:BAAALgADCgcJBwAAAA==.Nadíne:BAACLgAFFH8HAAIIAAMJoQsMSwDzAAAIAAMJoQsMSwDzAAAuAAQKfxwAAggACQkSHjtDAG4CAAgACQkSHjtDAG4CAAAA.Naha:BAAALgAECgkJBwAAAA==.Naimi:BAAALgAECgYJEAAAAA==.Nanukimon:BAABLgAECn8YAAMBAAYJQwtcQAACAQABAAYJQwtcQAACAQASAAYJNAqnEAD2AAAAAA==.Nastymcdirty:BAAALgADCgcJBwAAAA==.',
Ne='Nelivath:BAAALgAECgEJAQAAAA==.Nene:BAABLgAFFH8FAAIIAAIJUA+QYwCiAAAIAAIJUA+QYwCiAAAAAA==.Nevaera:BAABLgAECn8XAAIIAAcJBg5xWABkAQAIAAcJBg5xWABkAQAAAA==.',
Ni='Nichan:BAAALgAECgEJAwAAAA==.Nick:BAACLgAFFH8eAAMdAAYJ7hYiFwB4AQAdAAUJ7hYiFwB4AQAeAAEJAAA/FwA+AAAuAAQKfy0AAh0ACQmSI/0EAIQDAB0ACQmSI/0EAIQDAAAA.Nightcraft:BAAALgAECgEJAQAAAA==.Nightshine:BAAALgAECgcJEQAAAA==.Nikor:BAABLgAECn8VAAIUAAYJBxllDQBiAQAUAAYJBxllDQBiAQAAAA==.Nisan:BAAALgADCgcJBwAAAA==.',
No='Noah:BAAALgAECgIJAgAAAA==.Nocabevoli:BAAALgADCgUJBQABLgAECgIJAwAHAAAAAA==.Nokorii:BAABLgAECn8bAAIPAAYJwRH/HwBIAQAPAAYJwRH/HwBIAQAAAA==.Nomecoma:BAAALgAECgQJAQAAAA==.Nomercy:BAAALgAECgEJAQAAAA==.Norgatha:BAAALgAECgUJCwAAAA==.Notches:BAAALgAECgQJBwAAAA==.Nowheres:BAAALgAECgIJAwABLgAECgUJDgAHAAAAAA==.Noxturn:BAABLgAECn8VAAIGAAgJtBFEUQB1AQAGAAgJtBFEUQB1AQAAAA==.',
Nu='Nuikang:BAAALgAECgEJAQAAAA==.',
Ny='Nyxx:BAAALgAECgYJDQABLgAECgUJCQAHAAAAAA==.',
['Nè']='Nèlo:BAABLgAECn8cAAIYAAgJoQuEEwAxAQAYAAgJoQuEEwAxAQAAAA==.',
Oc='Oceansoul:BAABLgAECn8ZAAMcAAYJ1yDHAwBTAgAcAAYJ1yDHAwBTAgAhAAUJDhh4OgB9AQAAAA==.',
Oh='Ohh:BAAALgADCgMJAQAAAA==.Ohthathurtu:BAAALgADCgEJAQAAAA==.',
Ok='Ok:BAAALgADCgYJCgAAAA==.',
On='Ondestra:BAAALgAECgIJAgAAAA==.',
Op='Oppenheimerx:BAAALgADCgMJBQAAAA==.',
Or='Orave:BAABLgAECn8VAAIPAAYJ9x5HDQASAgAPAAYJ9x5HDQASAgAAAA==.Origin:BAAALgAECgIJAwABLgAECgcJEQAHAAAAAA==.Orionah:BAAALgAECgcJCgAAAA==.',
Os='Osywar:BAAALgAECgYJEwABLgAFFAEJAQAHAAAAAA==.',
Ou='Oulawdpriest:BAACLgAFFH8QAAIQAAYJ7gmtBQCDAQAQAAYJ7gmtBQCDAQAuAAQKfy8ABBAACAndHkgMAL4CABAACAndHkgMAL4CAAQAAgk4HFFDAJoAAA8AAgkHFWpzAFoAAAAA.',
Ov='Overture:BAABLgAECn8VAAMJAAYJmw3lRwDzAAAJAAYJmw3lRwDzAAAgAAQJBxADXgCqAAAAAA==.',
Pa='Palaslap:BAAALgADCgMJAwAAAA==.Panacea:BAAALgAECgYJCQABLgAECgcJBwAHAAAAAA==.Parkour:BAAALgAECgcJEwAAAA==.Pastorale:BAAALgADCgYJBgABLgAECgkJCgAHAAAAAA==.Patata:BAAALgADCgIJAgAAAA==.Paully:BAAALgAECgQJBgAAAA==.Paullymorph:BAABLgAECn8hAAIIAAkJCyHUDAC4AgAIAAkJCyHUDAC4AgAAAA==.Pawpawbear:BAAALgADCgEJAQAAAA==.Payal:BAAALgADCgQJBAABLgAFFAQJBwAhAKwMAA==.',
Pe='Pewpewkitti:BAAALgADCgUJBQAAAA==.',
Ph='Phenyl:BAABLgAECn8cAAIDAAkJJAksHABpAQADAAkJJAksHABpAQAAAA==.Pheurton:BAAALgAECgkJBwAAAA==.',
Pi='Pintobeans:BAAALgAECgcJBwAAAA==.Pithers:BAAALgAECgQJBgAAAA==.',
Pl='Plasmor:BAAALgAECggJCAAAAA==.',
Po='Ponchohunter:BAAALgADCgEJAQAAAA==.Pooh:BAAALgADCgEJAQABLgAECgcJFwADACAYAA==.Poohpocket:BAAALgADCgQJAwAAAA==.Popkorn:BAACLgAFFH8eAAMaAAcJvyDNAACJAgAaAAYJvyDNAACJAgAbAAEJAAAQBABqAAAuAAQKfx8ABBoACAmSJrUQAPgCABoACAlYJLUQAPgCACIABQmUIbkqAHABABsAAQlnJW0iAG8AAAAA.Popkornvoke:BAAALgAECgMJAwABLgAFFAcJHgAaAL8gAA==.Poplocks:BAAALgADCgIJAwABLgAECgYJBgAHAAAAAA==.Porrana:BAABLgAECn8bAAMRAAcJByGqCgA9AgARAAcJqCCqCgA9AgAmAAEJIx1dMgBWAAAAAA==.Powaqa:BAABLgAECn8nAAICAAgJAwPcFACqAAACAAgJAwPcFACqAAAAAA==.',
Ps='Psy:BAAALgAECggJEQAAAA==.',
Pu='Pumpkinspice:BAAALgAECgUJBQAAAA==.Punchkin:BAABLgAECn8bAAMDAAkJEhfGCwAvAgADAAkJEhfGCwAvAgAfAAEJWwJMiQAmAAAAAA==.Purify:BAAALgAECgQJBQABLgAFFAUJFAADADslAA==.Puzzledmonk:BAAALgADCgcJDQAAAA==.',
Qu='Quasient:BAAALgAECgQJBAAAAA==.Quickspell:BAABLgAECn8hAAIIAAgJwR/cGwBDAgAIAAgJwR/cGwBDAgAAAA==.Quickstep:BAAALgAECgkJBwAAAA==.',
Ra='Rabidpopcorn:BAAALgADCgcJBwAAAA==.Radaghast:BAABLgAECn8cAAIZAAgJGRZ8BwC+AQAZAAgJGRZ8BwC+AQAAAA==.Raedyyn:BAABLgAECn8bAAIOAAgJqw/HFwCEAQAOAAgJqw/HFwCEAQAAAA==.Ragarth:BAAALgAECgYJBgAAAA==.Ragendecay:BAABLgAECn8cAAIdAAgJWhMTMAC5AQAdAAgJWhMTMAC5AQAAAA==.Ragequits:BAACLgAFFH8XAAMRAAcJ2R81AABcAgARAAYJRCM1AABcAgAmAAIJQRQTCgBbAAAuAAQKfycAAxEACQmbJpcAAN8DABEACQmbJpcAAN8DACYABgnPJXwFABoCAAAA.Ragæ:BAAALgAECgYJBwAAAA==.Rakshassa:BAABLgAECn8VAAIGAAgJLRj0IwDGAQAGAAgJLRj0IwDGAQAAAA==.Ralcar:BAABLgAECn8VAAIaAAYJcR+nHwDKAQAaAAYJcR+nHwDKAQAAAA==.Razrscale:BAAALgAECgUJBQAAAA==.',
Re='Redhuntsman:BAAALgAECgIJAwAAAA==.Regrow:BAAALgAECgYJDwAAAA==.Renstrider:BAAALgAECgUJBQAAAA==.',
Rh='Rheas:BAAALgAECgIJAQAAAA==.Rholdentodor:BAAALgADCgUJBQABLgAECgcJCQAHAAAAAA==.',
Ro='Rockabye:BAAALgAECgUJBQABLgAFFAMJCQAdAEUVAA==.Rohra:BAABLgAECn8mAAIJAAgJAA6RLwBjAQAJAAgJAA6RLwBjAQAAAA==.Rombaz:BAAALgAFFAEJAQAAAA==.Ronspoomage:BAAALgADCgkJEQAAAA==.Rosemary:BAAALgADCgQJBAAAAA==.Roóz:BAAALgAECgQJEQAAAA==.',
Ru='Ruah:BAAALgAECgEJAQAAAA==.Runecast:BAAALgADCgcJFQAAAA==.',
Ry='Rynk:BAABLgAECn8pAAITAAgJGyWDAgDkAgATAAgJGyWDAgDkAgAAAA==.Rynkidari:BAAALgAECgkJCQABLgAECggJKQATABslAA==.Ryuoxel:BAAALgAFFAEJAQAAAA==.',
['Rá']='Rágnarok:BAAALgADCgMJAwAAAA==.Ráwkfist:BAABLgAFFH8PAAIOAAUJyhtWDgBeAQAOAAUJyhtWDgBeAQAAAA==.',
Sa='Sabbybunnee:BAAALgADCgcJDAAAAA==.Sabertrek:BAAALgADCgMJAwAAAA==.Saelyrinth:BAAALgADCgUJCAAAAA==.Saltybonez:BAAALgADCgUJBQAAAA==.Sambor:BAAALgAECgkJEgAAAA==.Sarapheena:BAABLgAECn8nAAIBAAkJ2RSBGgDeAQABAAkJ2RSBGgDeAQAAAA==.Saravian:BAAALgADCgUJBQAAAA==.Sardeench:BAAALgAECgEJAQAAAA==.Satanbomb:BAAALgAECgEJAgAAAA==.Satansbride:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.Saterli:BAACLgAFFH8KAAIPAAQJiQwQDAAMAQAPAAQJiQwQDAAMAQAuAAQKfy8AAw8ACAlhFOcTALsBAA8ACAlhFOcTALsBABAABgmXAyA1ALgAAAAA.Saturno:BAAALgAECggJEAAAAA==.Saucypirate:BAABLgAECn8VAAIIAAYJbQ7TcQAtAQAIAAYJbQ7TcQAtAQAAAA==.Saulgoodman:BAAALgADCgMJAwAAAA==.Sauronknight:BAABLgAFFH8JAAIdAAMJRRUgSQD8AAAdAAMJRRUgSQD8AAAAAA==.',
Sc='Scalvert:BAAALgAECgcJCQAAAA==.Scalypanda:BAABLgAECn8nAAMOAAkJQhOVDQDzAQAOAAkJQhOVDQDzAQAWAAIJ0gzQNABuAAAAAA==.Scamander:BAAALgAFFAEJAgAAAA==.Scarléth:BAAALgADCggJCgAAAA==.Scoobs:BAAALgAECgQJCQAAAA==.Scorpinom:BAAALgADCgQJBAAAAA==.Sculi:BAAALgADCgcJBwAAAA==.Scurge:BAAALgAECgIJAgAAAA==.Scuttle:BAAALgADCgIJBQABLgAECgcJFwADACAYAA==.',
Se='Sei:BAAALgADCgIJAgAAAA==.Seiishiro:BAABLgAECn8fAAMgAAcJuQh4JgALAQAgAAcJuQh4JgALAQAJAAEJTATe4gAiAAAAAA==.Seldon:BAABLgAECn8dAAIKAAYJ2xzLPACPAQAKAAYJ2xzLPACPAQAAAA==.Semiosphere:BAAALgAECgkJAgAAAA==.Sennistian:BAAALgADCgMJBAABLgAECggJIwAcAMINAA==.Senyor:BAABLgAECn8iAAIUAAgJoBoMBgAJAgAUAAgJoBoMBgAJAgAAAA==.Seraphiel:BAAALgAECgYJEAAAAA==.Seraphymm:BAAALgAECgcJEAAAAA==.',
Sh='Shacklebolt:BAABLgAECn8iAAMhAAgJLhjuJAB/AgAhAAgJLhjuJAB/AgACAAQJWg+8MwDoAAABLgAFFAEJAgAHAAAAAA==.Shadowsneak:BAABLgAECn8aAAInAAYJlwxDCgAkAQAnAAYJlwxDCgAkAQAAAA==.Shaelistra:BAABLgAECn8cAAIjAAYJOBVqDABRAQAjAAYJOBVqDABRAQAAAA==.Shalai:BAAALgADCggJDgAAAA==.Shalilama:BAACLgAFFH8PAAIBAAQJYR3oFQAZAQABAAQJYR3oFQAZAQAuAAQKfz4AAgEACQk6JeMAAJ0DAAEACQk6JeMAAJ0DAAAA.Shamanana:BAAALgAECgYJCwAAAA==.Shamboli:BAAALgADCgUJBQAAAA==.Shanazure:BAABLgAECn8iAAMOAAgJShqAEQDDAQAOAAgJZBiAEQDDAQAWAAcJyhM6EwCuAQAAAA==.Sheikai:BAAALgADCggJGAAAAA==.Shenderp:BAABLgAECn8cAAMPAAYJVRGZIgA0AQAPAAYJVRGZIgA0AQAQAAIJowJqWwBIAAAAAA==.Shinerbock:BAABLgAECn8YAAIDAAcJBwztJQAYAQADAAcJBwztJQAYAQAAAA==.Shivä:BAAALgADCgcJCgABLgAECggJGwAFALYUAA==.Shriven:BAAALgAECgIJAgAAAA==.',
Si='Sianvar:BAAALgAECggJDQAAAA==.Silastraza:BAAALgAECgEJAQAAAA==.Silvanus:BAAALgAECgMJAwAAAA==.Silverjustis:BAABLgAECn8hAAIKAAgJywXNZAAkAQAKAAgJywXNZAAkAQAAAA==.Siwe:BAABLgAECn8nAAQSAAgJfB+ZAgB9AgASAAgJfB+ZAgB9AgABAAcJVR2QEQAtAgAFAAEJpBJegwA8AAAAAA==.',
Sk='Skadoosh:BAABLgAECn8YAAIfAAYJjSRcCgAUAgAfAAYJjSRcCgAUAgAAAA==.Skribblez:BAABLgAECn8dAAMLAAcJeyESDgA3AgALAAYJPCESDgA3AgAKAAcJkR9sQwAaAgAAAA==.Skrilled:BAABLgAECn8oAAIGAAYJSxE7SAA0AQAGAAYJSxE7SAA0AQAAAA==.',
Sl='Slackback:BAAALgAECgkJBAABLgAFFAQJDgAFALsYAA==.Sloot:BAAALgAECgYJDgAAAA==.Slughorn:BAAALgAECgcJBQABLgAFFAEJAgAHAAAAAA==.Slyv:BAAALgADCgcJBwAAAA==.',
Sm='Smellidan:BAAALgADCgEJAwAAAA==.Smïte:BAAALgAECgUJDgAAAA==.',
Sn='Snape:BAAALgAECgQJBQAAAA==.Snowcones:BAAALgAECgcJDwAAAA==.Snowman:BAAALgAECgMJBQAAAA==.Snw:BAAALgAECgcJEwAAAA==.',
So='Soul:BAACLgAFFH8HAAIjAAMJJBZhBAATAQAjAAMJJBZhBAATAQAuAAQKfxwAAiMACQlwIdAEAMoCACMACQlwIdAEAMoCAAAA.Soulls:BAAALgAECgIJAgAAAA==.Soulsy:BAAALgAECgEJAgAAAA==.Sourgrip:BAABLgAECn8hAAIVAAkJwhgTAgA1AgAVAAkJwhgTAgA1AgAAAA==.',
Sp='Splendorae:BAABLgAECn8nAAILAAkJqhRXFADuAQALAAkJqhRXFADuAQAAAA==.Sprints:BAABLgAECn8oAAIBAAgJQxhQFwD4AQABAAgJQxhQFwD4AQAAAA==.Spritz:BAAALgAECgEJAQAAAA==.Sprylf:BAAALgADCgMJBAAAAA==.Spwany:BAABLgAECn8WAAQRAAgJ3ApcJgBCAQARAAcJeQVcJgBCAQAYAAUJoA0UKgDwAAAmAAEJAADpSAAAAAAAAA==.Spyderelite:BAABLgAECn8pAAICAAgJSxW8AwDhAQACAAgJSxW8AwDhAQAAAA==.',
Sq='Squeekems:BAAALgAECgIJAwAAAA==.Squirrel:BAAALgAECgkJEwAAAA==.',
St='Stainedhero:BAAALgADCgEJAQAAAA==.Stankstarstu:BAAALgADCgYJCAABLgAECgQJBwAHAAAAAA==.Starspeaker:BAABLgAECn8YAAMJAAYJAAWhVwC6AAAJAAYJAAWhVwC6AAAgAAIJiQPZdwBFAAAAAA==.Starykniight:BAAALgADCgMJAwABLgAECgcJFwADACAYAA==.Steveaustin:BAAALgAECgcJEgABLgAECgcJFwADACAYAA==.Stinkypeen:BAAALgAECgIJAgAAAA==.Stonecypher:BAAALgAECgYJDgAAAA==.Stoogotz:BAAALgADCgYJCAAAAA==.Stormlesbian:BAAALgADCgUJBQAAAA==.',
Su='Suhe:BAAALgADCggJDgAAAA==.Sundaresh:BAAALgADCgMJAwAAAA==.Sunwing:BAABLgAECn8nAAIPAAkJRhyTDwBqAgAPAAkJRhyTDwBqAgAAAA==.Sutileza:BAAALgADCgMJAwABLgAECgYJFQAJAJsNAA==.Suvien:BAAALgAECgUJBwAAAA==.',
Sw='Swagette:BAAALgADCgcJBwAAAA==.Swingkitti:BAAALgAECgYJDQAAAA==.',
Sx='Sxtitan:BAAALgAECggJEQAAAA==.',
Sy='Sylvarian:BAABLgAECn8dAAIoAAgJvw6IAgCVAQAoAAgJvw6IAgCVAQAAAA==.Synareth:BAAALgAECgEJAQAAAA==.Syrodeus:BAAALgAECgQJBAAAAA==.',
Sz='Szz:BAABLgAECn8nAAIWAAkJvCQwAABcAwAWAAkJvCQwAABcAwAAAA==.',
['Sÿ']='Sÿn:BAAALgADCgcJFwAAAA==.',
Ta='Taelgar:BAAALgAECgcJEgAAAA==.Tanthalos:BAAALgAECgQJCAABLgAECggJGgAMADwPAA==.Targaryenelf:BAAALgADCgMJBAAAAA==.Taterdotz:BAAALgAECggJEwAAAA==.Tatortwats:BAAALgAECgYJDgAAAA==.Tatyrra:BAAALgADCgUJBQAAAA==.Tayswift:BAAALgADCgQJBAABLgAECgUJEAAHAAAAAA==.',
Te='Tenast:BAAALgADCgIJAgAAAA==.Tepicoyotl:BAABLgAECn8eAAIBAAYJrROmRABvAQABAAYJrROmRABvAQAAAA==.',
Th='Thaymor:BAAALgADCgkJIQAAAA==.Thelonecone:BAACLgAFFH8PAAMVAAQJfRZBAgBAAQAVAAQJeRNBAgBAAQAdAAQJlQ8ZJQABAQAuAAQKf0QAAx0ACAnOJIUVAPsCAB0ACAkfIoUVAPsCABUACAlEI+QCAHkCAAAA.Theoganth:BAAALgAECgYJBgAAAA==.Theraphee:BAAALgADCgcJDQAAAA==.Therimor:BAABLgAECn8YAAMBAAcJoQhSRwDjAAABAAYJZglSRwDjAAAFAAEJHwHncwAXAAAAAA==.Theronshan:BAAALgADCggJEgAAAA==.Thevoid:BAAALgAECgkJCgAAAA==.Thomwizard:BAAALgAECgMJAwAAAA==.Thongrin:BAAALgADCgcJBwAAAA==.Thormorn:BAAALgADCgEJAgAAAA==.Thornarlenan:BAAALgADCgkJDgAAAA==.Thunnha:BAACLgAFFH8GAAIhAAMJaxrONAD+AAAhAAMJaxrONAD+AAAuAAQKfyAAAyEACAmgIlwKAKQCACEACAmgIlwKAKQCAAIAAQkcG05mAEMAAAAA.Thurlando:BAAALgADCgIJBAAAAA==.',
Ti='Tierali:BAAALgAECgMJAwAAAA==.',
To='Toastedsushi:BAAALgAECgUJCAAAAA==.Toetagg:BAAALgAECgIJAwAAAA==.Toobooku:BAAALgADCgEJAQAAAA==.Toofwess:BAAALgADCgkJCQABLgAECgcJFwADACAYAA==.Torí:BAAALgADCgYJCAAAAA==.Tosala:BAAALgAECgYJEQAAAA==.Totemkiller:BAABLgAECn8jAAIFAAgJBBHEGgB5AQAFAAgJBBHEGgB5AQAAAA==.Totemtwiddlr:BAABLgAECn8UAAIFAAgJuRzEFAB3AgAFAAgJuRzEFAB3AgABLgAFFAEJAgAHAAAAAA==.',
Tr='Traael:BAABLgAECn8fAAIGAAgJ4xZQJADEAQAGAAgJ4xZQJADEAQAAAA==.Trashbeard:BAAALgADCgIJAgAAAA==.Treebranch:BAAALgAECgEJAQAAAA==.Treesap:BAABLgAECn8nAAIpAAkJrxraAQA6AgApAAkJrxraAQA6AgAAAA==.Trinityeve:BAAALgAECgQJCAAAAA==.Trnz:BAAALgAFFAEJAQABLgAFFAEJAgAHAAAAAA==.Trnzlock:BAAALgAFFAEJAgAAAA==.',
Tu='Tulanii:BAAALgADCgMJAgAAAA==.Tularana:BAABLgAECn8cAAIIAAkJHRXZJQANAgAIAAkJHRXZJQANAgABLgAFFAEJAQAHAAAAAA==.Tumble:BAAALgAECgcJEwAAAA==.Tummyissues:BAAALgAECgIJAgAAAA==.Tums:BAAALgAECgQJCQAAAA==.',
Tw='Twignberryz:BAAALgADCgYJCQABLgAECgQJBwAHAAAAAA==.Twinkie:BAABLgAECn8VAAIhAAgJ5Qg7jgA8AQAhAAgJ5Qg7jgA8AQAAAA==.Twodogz:BAABLgAECn8hAAIGAAcJ+yIpEQBKAgAGAAcJ+yIpEQBKAgAAAA==.',
Ty='Tyious:BAABLgAECn8oAAMdAAkJDBy7GQAxAgAdAAkJDBy7GQAxAgAeAAYJCAuNLADaAAAAAA==.Tyndara:BAABLgAECn8cAAIKAAYJoBAhXQA1AQAKAAYJoBAhXQA1AQAAAA==.',
['Tü']='Tüesdaÿ:BAAALgAECgcJCwAAAA==.',
Uc='Uchihazephyr:BAAALgADCgIJAgABLgAFFAQJDwABAGEdAA==.',
Un='Unbeat:BAAALgAECggJDwAAAA==.Unbeliever:BAAALgAECggJCAAAAA==.Unhoe:BAAALgADCggJEgAAAA==.Unholussie:BAACLgAFFH8JAAIdAAQJowtuNQAyAQAdAAQJowtuNQAyAQAuAAQKfysAAh0ACAkeHcEZADECAB0ACAkeHcEZADECAAAA.Unholybowner:BAAALgADCgcJDAAAAA==.Unstablè:BAAALgAECgUJCQAAAA==.',
Ur='Ursane:BAABLgAECn8qAAIRAAkJmRtGBgCNAgARAAkJmRtGBgCNAgAAAA==.Ursully:BAABLgAECn8cAAIZAAYJySB1BwC/AQAZAAYJySB1BwC/AQAAAA==.',
Uz='Uzi:BAAALgAECgYJCwAAAA==.',
Va='Vaardux:BAABLgAECn8ZAAMLAAgJ4hxdCACOAgALAAgJ4hxdCACOAgAKAAUJRiIYWADaAQAAAA==.Vaelithra:BAAALgADCgEJAQAAAA==.Valamarl:BAAALgADCgcJCAAAAA==.Valkeria:BAAALgAECgQJBQAAAA==.Valíthria:BAAALgAECgYJCAAAAA==.Vampulla:BAABLgAECn8dAAIaAAgJBwhtUQAFAQAaAAgJBwhtUQAFAQAAAA==.Vanncint:BAAALgAECgQJBAAAAA==.Vanndrygos:BAAALgAECgYJEAAAAA==.Varea:BAAALgAECgIJAgAAAA==.Vashie:BAAALgAECggJEQAAAA==.',
Ve='Veigar:BAAALgAECgcJDgABLgAFFAUJFwAMAF0mAA==.Velanis:BAAALgADCgUJBwAAAA==.Velmir:BAAALgAECgkJBwAAAA==.Velorius:BAAALgAECgEJAgAAAA==.Vexus:BAACLgAFFH8OAAIFAAQJuxh6CwBNAQAFAAQJuxh6CwBNAQAuAAQKfyIAAgUACAmcI8AJAPcCAAUACAmcI8AJAPcCAAAA.Vexuss:BAAALgAECgkJAgABLgAFFAQJDgAFALsYAA==.',
Vi='Vidya:BAAALgADCgMJAwAAAA==.Vivifyght:BAAALgAECgEJAQAAAA==.',
Vl='Vladios:BAAALgAECgYJCgAAAA==.',
Vo='Voidwraith:BAAALgADCgEJAQAAAA==.Vordarian:BAABLgAECn8dAAMDAAgJ4gv0HwBHAQADAAgJ4gv0HwBHAQATAAMJlAFOTQBkAAAAAA==.',
Vy='Vynciaagn:BAAALgADCgcJEgAAAA==.',
Wa='Wafflehouse:BAABLgAECn8WAAIdAAgJoxwfGgAuAgAdAAgJoxwfGgAuAgAAAA==.Walolas:BAAALgADCgcJEAAAAA==.Wamiya:BAAALgAECgEJAgAAAA==.Warbatt:BAAALgADCggJCAAAAA==.Watchmeburst:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgAECgMJAwAAAA==.',
Wh='Whaler:BAABLgAECn8dAAIRAAgJpyIGBgCSAgARAAgJpyIGBgCSAgAAAA==.Whìndy:BAAALgAECgQJBgABLgAECgYJDwAHAAAAAA==.',
Wi='Wildspanks:BAAALgADCgYJCQAAAA==.',
Wo='Wowoo:BAAALgAECgcJCAAAAA==.',
Xe='Xenos:BAAALgAECgIJAwAAAA==.Xenyodk:BAABLgAECn8dAAIdAAkJISDpDACeAgAdAAkJISDpDACeAgAAAA==.Xenyovoker:BAAALgAECgkJBAAAAA==.',
Xi='Xideris:BAABLgAECn8sAAIXAAkJXiLDAAB3AwAXAAkJXiLDAAB3AwAAAA==.Xiderís:BAAALgAECgYJBgAAAA==.',
Xt='Xtraxtra:BAABLgAECn8oAAMJAAgJZhm9HABWAgAJAAgJZhm9HABWAgAgAAgJ6Q7FFwB9AQAAAA==.',
Ya='Yaku:BAAALgAECgUJCAAAAA==.',
Ye='Yetzi:BAAALgADCgIJAgAAAA==.Yetzibel:BAAALgADCgQJBAAAAA==.',
Yo='Yoan:BAAALgAFFAIJAwAAAQ==.Yoga:BAAALgAECgcJEQAAAA==.Yonicbonnet:BAABLgAECn8YAAIJAAYJLAuaRwD0AAAJAAYJLAuaRwD0AAAAAA==.Yoondo:BAAALgAECgUJBwAAAA==.Yorde:BAAALgADCgcJBwAAAA==.',
Ys='Ysandrell:BAAALgADCgMJAwAAAA==.Yshtola:BAABLgAECn8aAAIBAAgJQRf9EQApAgABAAgJQRf9EQApAgAAAA==.',
Yu='Yuffie:BAAALgAECgQJBAAAAA==.Yunara:BAACLgAFFH8FAAIaAAMJxh72JQAZAQAaAAMJxh72JQAZAQAuAAQKfyEAAhoABwmmIUYQAEECABoABwmmIUYQAEECAAEuAAUUBQkXAAwAXSYA.Yunge:BAAALgADCgQJBAAAAA==.',
Za='Zabra:BAAALgAECgYJEgAAAA==.Zachpally:BAAALgADCgUJBQAAAA==.Zahvoker:BAABLgAECn8VAAIWAAYJ3AjACgDvAAAWAAYJ3AjACgDvAAAAAA==.Zapkitti:BAAALgADCgQJBAAAAA==.Zareline:BAAALgAECgQJBgAAAA==.Zathaeus:BAABLgAECn8kAAIaAAkJdhUVFgALAgAaAAkJdhUVFgALAgAAAA==.Zaylian:BAABLgAECn8lAAIiAAgJBRoFCQD+AQAiAAgJBRoFCQD+AQAAAA==.Zayragossa:BAABLgAFFH8HAAIhAAIJKCBXTQC6AAAhAAIJKCBXTQC6AAAAAA==.',
Ze='Zeerkk:BAABLgAECn8mAAIhAAgJsxq6GgAQAgAhAAgJsxq6GgAQAgAAAA==.Zelanta:BAAALgADCgQJBAAAAA==.Zergmark:BAAALgADCgMJAwAAAA==.Zero:BAAALgADCgIJAgAAAA==.',
Zo='Zoomzoom:BAAALgADCgIJAgAAAA==.Zouris:BAAALgAECgQJBgAAAA==.',
Zt='Ztaziki:BAAALgADCgQJBAAAAA==.',
Zu='Zulkraa:BAAALgAECgUJCgAAAA==.Zulmex:BAAALgAECgYJCwAAAA==.Zunda:BAAALgAECgkJBwAAAA==.Zurtogg:BAABLgAECn8cAAMRAAgJRxb7EgDWAQARAAgJwBX7EgDWAQAmAAMJVxQGJQDFAAAAAA==.',
['Ài']='Àirén:BAAALgAECgEJAQAAAA==.',
['Îc']='Îcey:BAAALgAECgMJAwAAAA==.',
['Ön']='Öndi:BAAALgADCgYJBgAAAA==.',
['ßr']='ßrûh:BAAALgADCgEJAQAAAA==.',
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
