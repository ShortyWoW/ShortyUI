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

local lookup = {'DeathKnight-Unholy','Shaman-Elemental','Paladin-Retribution','Druid-Restoration','Druid-Balance','Mage-Frost','DemonHunter-Devourer','Warrior-Fury','Shaman-Enhancement','DemonHunter-Havoc','Druid-Guardian','Rogue-Outlaw','DemonHunter-Vengeance','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','Rogue-Assassination','Hunter-Survival','Hunter-Marksmanship','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Druid-Feral','Mage-Fire','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','DeathKnight-Blood','Mage-Arcane',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aantoc:BAAALgADCgUJBQAAAA==.',
Ad='Adramalech:BAAALgAECgEJAgABLgAFFAUJDwABAGIcAA==.',
Ae='Aeakos:BAAALgADCgQJBQABLgAECggJHwACAMEUAA==.Aelan:BAAALgADCgQJBAAAAA==.Aeryana:BAAALgADCgMJAwAAAA==.',
Ag='Agapitus:BAAALgADCgIJAgAAAA==.',
Ai='Ailuridae:BAAALgADCgcJEwAAAA==.Aimbot:BAAALgADCgUJCQAAAA==.Aisele:BAAALgAECgYJDgAAAA==.',
Al='Alathir:BAAALgAECgcJDQAAAA==.Alenton:BAAALgADCgUJBgAAAA==.Alessia:BAAALgADCgMJBAAAAA==.Alluri:BAABLgAECn8hAAIDAAkJyRhzLQDHAQADAAkJyRhzLQDHAQAAAA==.Alone:BAAALgAECgYJDgAAAA==.Althemia:BAAALgAECgQJBQAAAA==.Alunamora:BAABLgAECn8mAAIEAAgJdhzJCwCNAgAEAAgJdhzJCwCNAgAAAA==.Alwind:BAABLgAECn8WAAIFAAcJ+xAoHQBLAQAFAAcJ+xAoHQBLAQAAAA==.',
Am='Ambient:BAABLgAECn8aAAIGAAYJMg7bcQAtAQAGAAYJMg7bcQAtAQAAAA==.Amboosted:BAABLgAECn8tAAIDAAgJtxsNJADzAQADAAgJtxsNJADzAQAAAA==.Ameretat:BAEBLgAFFH8IAAIHAAIJIBvvQQCiAAAHAAIJIBvvQQCiAAABLgAFFAQJDgAIAN0TAA==.',
An='Analani:BAAALgAECgQJBgAAAA==.Anali:BAAALgAECgQJBwAAAA==.Ancient:BAAALgAECgEJAQABLgAFFAMJBQAGAFcXAA==.Ancksunamun:BAAALgAECgIJAgAAAA==.Angerr:BAAALgAECgUJDQAAAA==.Angryheals:BAAALgAECgQJBwAAAA==.Anhri:BAAALgAECgEJAQAAAA==.Animalator:BAAALgAECgEJAQAAAA==.',
Aq='Aquamann:BAAALgADCgMJBAAAAA==.',
Ar='Aranel:BAAALgAECgYJCQAAAA==.Aratiri:BAAALgADCgUJBQAAAA==.Arcamancer:BAAALgADCggJFwAAAA==.Arcannia:BAAALgADCgEJAQAAAA==.Arek:BAAALgAECgYJBwABLgAFFAUJFAAJANseAA==.Arinthal:BAAALgAECgUJDQAAAA==.Arril:BAAALgAECgYJDQAAAA==.Artemissy:BAAALgADCgUJDQAAAA==.Artorias:BAAALgAECgEJAgAAAA==.',
As='Ashed:BAAALgAECgcJDAAAAA==.Ashenskye:BAAALgADCgUJBQAAAA==.Ashlieghee:BAAALgADCgcJDAAAAA==.Ashtari:BAAALgADCgEJAQAAAA==.Astien:BAAALgAECgMJBwAAAA==.Astra:BAAALgADCgMJAwAAAA==.',
Au='Aureille:BAAALgADCgEJAgAAAA==.Aurien:BAAALgADCgMJAwAAAA==.Autoaim:BAAALgAECgYJDwAAAA==.',
Av='Avelen:BAAALgAECgEJAwAAAA==.Avha:BAAALgAECgUJCwAAAA==.Avië:BAABLgAECn8XAAIGAAYJOBaNnACcAQAGAAYJOBaNnACcAQAAAA==.',
Ax='Axel:BAABLgAECn8WAAIHAAcJvBNdWgCSAQAHAAcJvBNdWgCSAQAAAA==.',
Ay='Aylden:BAABLgAECn8gAAMKAAYJcx4MHgDPAQAKAAYJcx4MHgDPAQAHAAUJnwgcdQCuAAAAAA==.',
Az='Azenezith:BAAALgAECgQJBAAAAA==.Azio:BAAALgAECgYJDAAAAA==.Azriah:BAAALgADCggJDwAAAA==.',
Ba='Bailas:BAAALgAECgEJAQAAAA==.Bananabear:BAABLgAECn8VAAILAAgJiiWGAQA+AwALAAgJiiWGAQA+AwABLgAFFAQJCQAMAMwdAA==.Barbiesresto:BAAALgADCgUJBQAAAA==.Bargs:BAAALgADCgMJAwAAAA==.Barra:BAAALgAECgQJBwAAAA==.Bashshield:BAEALgAFFAEJAQAAAA==.',
Bb='Bb:BAAALgAECgcJCwAAAA==.',
Be='Bearjax:BAAALgADCgkJCQABLgAFFAIJBwANANcjAA==.Beastm:BAAALgADCgQJBAAAAA==.Beathed:BAAALgAECgQJBAAAAA==.Beaver:BAAALgADCgIJAgAAAA==.Belanova:BAAALgAECgYJBwAAAA==.Belencina:BAAALgAECgYJBgAAAA==.Beleynn:BAABLgAECn8UAAIOAAcJigZZHwACAQAOAAcJigZZHwACAQAAAA==.Belwyn:BAAALgADCgMJAwAAAA==.Benjofamin:BAAALgAECgcJCgAAAA==.',
Bi='Bigheelz:BAAALgAECgUJBgAAAA==.Bigpuffer:BAAALgADCgMJBAAAAA==.Bitesize:BAECLgAFFH8OAAMIAAQJ3RPHEQD4AAAIAAQJExLHEQD4AAAPAAEJaw6tCgBYAAAuAAQKfyMABA8ACQnaIB8MAN8BAAgABgluJEgjADsCAA8ABQlXHx8MAN8BABAAAgklEe06AHQAAAAA.',
Bl='Blashster:BAAALgAFFAIJAwAAAA==.',
Bo='Boaw:BAAALgAECgMJBgAAAA==.Bonemilker:BAACLgAFFH8PAAMBAAUJYhy+CgCzAQABAAUJYhy+CgCzAQARAAMJ2Rx0AQC9AAAuAAQKfzMAAxEACAlIJm4AAGwDABEACAn/JW4AAGwDAAEACAn/JS8IAF4DAAAA.Boosieboose:BAAALgAECgYJCAAAAA==.',
Br='Brackz:BAABLgAECn8aAAIEAAgJEBi0EgA2AgAEAAgJEBi0EgA2AgAAAA==.Brandt:BAAALgADCgEJAgAAAA==.Brannwynn:BAAALgADCgEJAQAAAA==.Breelyssa:BAAALgAECgcJBwAAAA==.Brewtangclan:BAAALgAECgYJEwAAAA==.Brighter:BAAALgAECgEJAQAAAA==.Broncopally:BAAALgADCgYJGwAAAA==.Brother:BAAALgADCgEJAQABLgAECggJKgAGAHEaAA==.Bryaan:BAABLgAFFH8FAAIDAAUJwATSMgDsAAADAAUJwATSMgDsAAAAAA==.',
Bu='Bullitproof:BAAALgADCgcJDgABLgAECggJMQADANgJAA==.Bunnkost:BAAALgADCgkJGQAAAA==.Bunnyparade:BAAALgAECgMJBQAAAA==.',
Ca='Caiden:BAAALgAECgMJAwAAAA==.Calari:BAAALgAECgQJBwAAAA==.Caledwar:BAABLgAECn8bAAIDAAYJ+RCTWwA5AQADAAYJ+RCTWwA5AQAAAA==.Calthirstrap:BAABLgAFFH8HAAIBAAQJ8g3ONAA0AQABAAQJ8g3ONAA0AQABLgAECgkJFwAGAGIYAA==.Camvoker:BAAALgADCgEJAQAAAA==.Carapace:BAABLgAECn8mAAIIAAgJfw0oIABrAQAIAAgJfw0oIABrAQAAAA==.Carare:BAAALgADCggJDQAAAA==.Catomaze:BAAALgAECgEJAQAAAA==.',
Ce='Ceefack:BAAALgAECgQJCAAAAA==.Celestialsky:BAAALgAECgkJAQAAAA==.Celicel:BAAALgADCgcJBwAAAA==.Cena:BAABLgAECn8kAAMSAAcJGguCCABOAQASAAcJGQuCCABOAQAOAAYJ7wgPIAD8AAAAAA==.Cethin:BAAALgAECgMJBwAAAA==.',
Ch='Chaosform:BAAALgADCgkJJgABLgAFFAIJBgATAEMjAA==.Chaosshot:BAACLgAFFH8GAAMTAAIJQyM9EgDKAAATAAIJQyM9EgDKAAAUAAEJRCEwIwBlAAAuAAQKfyQAAxQACAlNJDEGADkDABQACAlNJDEGADkDABMAAQmLJIsxAGwAAAAA.Cherylindrea:BAAALgADCgYJEQAAAA==.Chronic:BAABLgAECn8YAAIDAAgJZA9pPwCHAQADAAgJZA9pPwCHAQAAAA==.Chènch:BAAALgADCgEJAQABLgAECgUJEgAVAAAAAA==.',
Ci='Cindera:BAAALgADCggJCAAAAA==.',
Cl='Claydemon:BAAALgAECgYJEAAAAA==.Clayman:BAAALgAECgYJBgAAAA==.Claytraps:BAAALgADCgkJJQAAAA==.Clayvicar:BAACLgAFFH8GAAMWAAIJ5AQqGgBtAAAWAAIJ5AQqGgBtAAAXAAEJYgDrFwA3AAAuAAQKfycAAxYACAkOE6chANYBABYACAkOE6chANYBABcAAwlgA5lXAGAAAAAA.',
Co='Coridane:BAABLgAECn8VAAIWAAYJHhRaHwBNAQAWAAYJHhRaHwBNAQAAAA==.Corrum:BAAALgADCgIJAgAAAA==.Corwinfiron:BAAALgAECgcJEQAAAA==.Cotreyy:BAACLgAFFH8RAAMYAAQJnyUoBgC+AQAYAAQJnyUoBgC+AQAZAAEJIyX6DwBqAAAuAAQKfycABBgACAlKJhcRAPICABgABwnkJRcRAPICABoABQk3JvcEACMCABkABAkRIhsXAJEBAAAA.',
Cr='Cristen:BAAALgADCgYJCQAAAA==.Crobat:BAAALgAECgYJCAAAAA==.Crypitc:BAAALgADCgMJAwAAAA==.',
Cu='Cumgar:BAABLgAECn8fAAIYAAgJlBG7WAC+AQAYAAgJlBG7WAC+AQAAAA==.',
Cy='Cythera:BAACLgAFFH8UAAIJAAUJ2x5/AQB8AQAJAAUJ2x5/AQB8AQAuAAQKfx4AAgkACQkcJFsEANgCAAkACQkcJFsEANgCAAAA.',
['Cá']='Cámus:BAABLgAECn8ZAAIDAAYJZxmrfwB7AQADAAYJZxmrfwB7AQAAAA==.',
['Cö']='Cöffee:BAAALgAECgUJEAAAAA==.',
Da='Daammy:BAAALgADCggJEAAAAA==.Dagran:BAAALgAECgQJCQABLgAECgcJFwAHALwfAA==.Dagren:BAAALgAECgYJCQAAAA==.Dankfrost:BAAALgADCgcJEgAAAA==.Daphine:BAAALgADCgYJEQAAAA==.Darimonk:BAAALgADCgMJAwAAAA==.Darkbeautie:BAAALgAECgYJDAAAAA==.Darkcarbon:BAAALgAECgYJDwAAAA==.Darmin:BAAALgAECgEJAQAAAA==.',
De='Deathmask:BAAALgADCgEJAQAAAA==.Deepdarkdank:BAAALgADCgEJAQAAAA==.Deepmoanpaw:BAAALgAECgYJCQAAAA==.Defnotash:BAACLgAFFH8GAAIbAAMJ7A3kBQC0AAAbAAMJ7A3kBQC0AAAuAAQKfyQAAhsACQnXHboBADIDABsACQnXHboBADIDAAAA.Dellinair:BAAALgADCgEJAQAAAA==.Dementedlock:BAAALgAECgcJEQAAAA==.Demontacos:BAAALgAECgYJBwAAAA==.Derodd:BAAALgAECgQJBQAAAA==.Desolend:BAAALgADCgIJAgAAAA==.Dewkiez:BAEALgAFFAIJBAAAAA==.',
Di='Diabolicarl:BAABLgAECn8eAAIKAAgJ2RKQDQCnAQAKAAgJ2RKQDQCnAQAAAA==.Dibsy:BAABLgAECn8zAAIcAAkJCSHBAQANAwAcAAkJCSHBAQANAwAAAA==.Diri:BAAALgADCgcJBwABLgAECgkJIQAOADUVAA==.Dis:BAAALgADCggJFgABLgAFFAIJBwAEACMBAA==.Disgrace:BAABLgAECn8gAAIQAAgJDw2QEQBKAQAQAAgJDw2QEQBKAQAAAA==.Dividane:BAAALgADCgYJBgAAAA==.',
Dm='Dmossyoak:BAAALgADCgkJAgAAAA==.',
Do='Donniedipes:BAABLgAECn8hAAIBAAgJoQ+KSgBbAQABAAgJoQ+KSgBbAQAAAA==.Dookiez:BAEBLgAECn8ZAAIJAAgJnSNoAgAmAwAJAAgJnSNoAgAmAwABLgAFFAIJBAAVAAAAAA==.Doublade:BAAALgAECgcJBwAAAA==.Doubledragin:BAABLgAECn8gAAMdAAYJ3xmrGQBxAQAdAAYJ3xmrGQBxAQAeAAMJ6gKNNgBiAAAAAA==.',
Dr='Dracantar:BAAALgADCgUJBQAAAA==.Dracotako:BAAALgAECgYJCwAAAA==.Dractini:BAABLgAECn8ZAAMfAAgJvQrEJABSAQAfAAcJXAvEJABSAQAdAAcJfQ7/MQA4AQABLgAFFAcJIgAgAGQRAA==.Draeneiamin:BAAALgADCgMJAwABLgAECgcJCgAVAAAAAA==.Dragfan:BAAALgAECgIJAgAAAA==.Dragonsniper:BAAALgAECgQJCAAAAA==.Dragore:BAABLgAECn8ZAAIIAAYJthuyNwDIAQAIAAYJthuyNwDIAQAAAA==.Druidgirls:BAACLgAFFH8IAAIEAAMJPxEIIwDJAAAEAAMJPxEIIwDJAAAuAAQKfygAAgQACQncGMQqAAYCAAQACQncGMQqAAYCAAAA.Dràugluin:BAAALgAFFAEJAQAAAA==.',
Du='Duasoras:BAABLgAECn8fAAIhAAgJ9QRbRADwAAAhAAgJ9QRbRADwAAAAAA==.Duelist:BAAALgADCgUJBQAAAA==.Dundlen:BAAALgADCggJDwABLgAFFAIJBQAGAOQDAA==.Dunvel:BAAALgAECgMJAwAAAA==.Durogdem:BAAALgAECgIJBAAAAA==.',
Dy='Dynamite:BAAALgAECgEJAwAAAA==.',
Ea='Earthaggie:BAAALgADCgYJEQAAAA==.',
Ed='Edea:BAAALgAECgEJAQAAAA==.Ederon:BAAALgADCgcJBwAAAA==.',
El='Elaelta:BAAALgAECgMJCQAAAA==.Eleetmage:BAAALgAECgEJAQAAAA==.Elenora:BAABLgAECn8tAAIFAAgJYwQbKgDzAAAFAAgJYwQbKgDzAAAAAA==.Elesity:BAAALgADCgEJAQABLgAFFAQJEAAVAAAAAA==.Elye:BAAALgAECgMJAwABLgAECgYJEwAVAAAAAA==.',
Em='Emer:BAACLgAFFH8HAAMEAAIJIwGrPQBLAAAEAAIJIwGrPQBLAAAFAAIJOwCbLAAQAAAuAAQKfycAAwUACAk0Cv86AEkBAAUABwmfC/86AEkBAAQABwnWBrZmAIoAAAAA.',
En='Encore:BAACLgAFFH8FAAIEAAMJpQLyKwCbAAAEAAMJpQLyKwCbAAAuAAQKfywAAgQACAmGEWAnAJMBAAQACAmGEWAnAJMBAAAA.',
Eo='Eousphorus:BAACLgAFFH8NAAIGAAQJ/hjiJQBcAQAGAAQJ/hjiJQBcAQAuAAQKfyMAAgYACAmXIPg0AJ8CAAYACAmXIPg0AJ8CAAAA.',
Er='Erathen:BAAALgAECgUJBAAAAA==.Eridi:BAAALgADCgEJAQAAAA==.Eroenice:BAAALgAECgQJBAAAAA==.',
Et='Etile:BAAALgADCgkJFgAAAA==.',
Ev='Evelleion:BAABLgAECn8VAAMiAAgJyRHaJwCzAQAiAAgJKxDaJwCzAQAUAAQJDhFDWgDbAAAAAA==.',
Ex='Exoticlord:BAABLgAECn8eAAMiAAgJyRmOFAArAgAiAAgJyRmOFAArAgAUAAYJ6BDeQQBQAQAAAA==.',
Fa='Failagos:BAAALgADCgMJAwAAAA==.Fallujah:BAAALgADCgUJBQAAAA==.',
Fe='Felicene:BAABLgAECn8nAAIjAAgJOyQWAQDsAgAjAAgJOyQWAQDsAgAAAA==.Fellynn:BAACLgAFFH8HAAINAAIJ1yN6AwDOAAANAAIJ1yN6AwDOAAAuAAQKfycAAg0ACAmjJZ8AAFsDAA0ACAmjJZ8AAFsDAAAA.',
Fi='Fieperskaivu:BAABLgAECn8XAAMHAAcJvB8QIgCFAgAHAAcJvB8QIgCFAgAKAAUJMRqhNQAxAQAAAA==.Fierygrace:BAAALgADCgYJBgAAAA==.Firefalco:BAAALgADCggJCQAAAA==.',
Fl='Flameth:BAACLgAFFH8FAAIYAAIJvQGQbgBnAAAYAAIJvQGQbgBnAAAuAAQKfxsAAhgACAnwCw9NAEIBABgACAnwCw9NAEIBAAAA.Flamingbunz:BAAALgAECgIJAgAAAA==.Flashblood:BAACLgAFFH8KAAIIAAMJaSMwEQAqAQAIAAMJaSMwEQAqAQAuAAQKfygAAwgACQnVJM0QAMoCAAgACQnVJM0QAMoCAA8AAwnxIosYADQBAAAA.Flashers:BAAALgAECggJBwAAAA==.Flavortown:BAAALgAECgIJAgAAAA==.',
Fo='Forgiven:BAABLgAECn8VAAIDAAcJqBrJVADjAQADAAcJqBrJVADjAQAAAA==.Foxtrót:BAABLgAECn8UAAIiAAcJ0QyBSwArAQAiAAcJ0QyBSwArAQABLgAECggJJAAQAJIiAA==.',
Fr='Freeb:BAAALgAECgMJBQABLgAECggJMQADANgJAA==.Freebzz:BAAALgADCgQJBwABLgAECggJMQADANgJAA==.Freezrorburn:BAAALgAECgYJCgAAAA==.Frostyndikit:BAAALgAECgMJAwAAAA==.',
Fu='Fu:BAAALgADCgUJBQAAAA==.Fumanchu:BAABLgAECn8kAAIQAAgJkiK/AgCwAgAQAAgJkiK/AgCwAgAAAA==.',
Ga='Gaamora:BAAALgADCgYJEQAAAA==.Gainsborough:BAAALgAECggJBwAAAA==.Galadore:BAAALgADCgIJAwAAAA==.Garagos:BAACLgAFFH8HAAISAAIJeRd7BQC3AAASAAIJeRd7BQC3AAAuAAQKfycAAhIACAknHW0DAP4BABIACAknHW0DAP4BAAAA.Gatherina:BAAALgAECgQJBgABLgAECgcJFwAHALwfAA==.',
Ge='Gebuss:BAABLgAECn8VAAISAAcJLSWuAgDCAgASAAcJLSWuAgDCAgAAAA==.Gempally:BAAALgADCgMJBgAAAA==.Genzo:BAAALgAECgQJBQAAAA==.',
Gh='Ghorynv:BAAALgAECgYJBgAAAA==.',
Gi='Giah:BAAALgAECgYJBgAAAA==.Giborim:BAAALgADCgEJAQAAAA==.Gigapriest:BAAALgAECgYJBgAAAA==.Gilford:BAAALgADCgUJBgAAAA==.',
Gl='Glavela:BAAALgAECgYJDQAAAA==.Gloomfist:BAAALgAECgYJEwAAAQ==.',
Go='Goochaddi:BAAALgADCgMJAwABLgAECgUJBQAVAAAAAA==.',
Gr='Graven:BAAALgAECgcJBwAAAA==.Graveside:BAAALgAECgEJAQAAAA==.Greymist:BAAALgADCgEJAQAAAA==.Grizzlock:BAAALgADCgMJAwAAAA==.',
Gu='Gulivar:BAAALgAECgUJEgAAAA==.Gunnerrata:BAAALgAECgUJBQAAAA==.',
Ha='Halfrican:BAAALgAECgQJBAAAAA==.Halifaxx:BAACLgAFFH8FAAMGAAIJ5AOwbgCLAAAGAAIJ5AOwbgCLAAAkAAEJNQGOAgBGAAAuAAQKfyAAAyQACAlNH1UBAAoCACQACAmKHFUBAAoCAAYABgk7FbpYAGQBAAAA.Happygilmore:BAAALgADCgYJBwAAAA==.Harambee:BAAALgAECgEJAQABLgAFFAMJBAAVAAAAAA==.Hariasa:BAAALgAECgMJAwAAAA==.Harlyquin:BAAALgAECgIJAgAAAA==.Harmaa:BAAALgAECgYJDgAAAA==.Hawknor:BAAALgAECgYJEAAAAA==.',
He='Headpool:BAAALgAECgQJBAABLgAECgUJBQAVAAAAAA==.Healenya:BAAALgAECgcJBwAAAA==.Healthcare:BAAALgAECgcJDwABLgAFFAcJIgAgAGQRAA==.Healywilly:BAAALgADCggJGQAAAA==.Herm:BAACLgAFFH8FAAIcAAIJ6iTyEQDYAAAcAAIJ6iTyEQDYAAAuAAQKfyYAAhwACAlEI40HAAMDABwACAlEI40HAAMDAAAA.',
Hi='Highbear:BAAALgAECgUJCQAAAA==.Hiryu:BAAALgADCgYJBgAAAA==.',
Ho='Holyfaxx:BAAALgAECgUJBQAAAA==.Holymidget:BAAALgADCggJDQAAAA==.Holysky:BAAALgAECgQJCQAAAA==.Holysmokes:BAAALgAECgUJBwAAAA==.Holytim:BAABLgAECn8hAAMgAAgJDxhMGQBoAQAgAAgJcBZMGQBoAQAWAAYJ4RDHRAAmAQAAAA==.Honnik:BAABLgAECn8hAAISAAkJbhEWBAB0AgASAAkJbhEWBAB0AgAAAA==.Hortance:BAAALgAECgcJBwAAAA==.Hothot:BAAALgAECgQJBQAAAA==.Hotsndots:BAAALgAECgEJAQAAAA==.Houndoom:BAABLgAECn8kAAIlAAgJXBSdFACYAQAlAAgJXBSdFACYAQAAAA==.How:BAACLgAFFH8HAAImAAMJxRc3CwDzAAAmAAMJxRc3CwDzAAAuAAQKfxwAAyYACAkMHbINAHkCACYACAkMHbINAHkCABwAAQkHCAqBAC8AAAAA.',
Hu='Hugspotato:BAAALgAECgIJAgAAAA==.Huyrak:BAAALgADCgUJBQAAAA==.',
Hy='Hypoxic:BAAALgAECgYJEAAAAA==.',
Ia='Iah:BAACLgAFFH8FAAIJAAIJygALCABpAAAJAAIJygALCABpAAAuAAQKfyIAAgkACAmTCukPALkBAAkACAmTCukPALkBAAAA.',
Ic='Icastspells:BAAALgAECgUJBAAAAA==.Icritmepants:BAAALgAECgMJAwAAAA==.Icyveinuser:BAAALgADCgcJIwAAAA==.',
Ig='Ignored:BAABLgAECn8fAAMDAAgJyRikIgD7AQADAAgJyRikIgD7AQAnAAEJoAH4bwAZAAAAAA==.',
Il='Illidæn:BAABLgAECn8ZAAIHAAgJPBHjMwBmAQAHAAgJPBHjMwBmAQAAAA==.Illistra:BAAALgADCgYJBgABLgAECgcJDQAVAAAAAA==.',
Im='Impuratus:BAAALgAECgMJBQAAAA==.',
In='Inq:BAABLgAECn8VAAIGAAgJ3hzIGwBDAgAGAAgJ3hzIGwBDAgAAAA==.',
Ir='Iridaceaë:BAABLgAECn8vAAMWAAkJ1xspBADXAgAWAAkJ1xspBADXAgAgAAMJHgioRQCMAAABLgAECgkJKgAmAHEhAA==.Ironpaw:BAABLgAECn8UAAIcAAYJShCjIAAgAQAcAAYJShCjIAAgAQAAAA==.Iryris:BAABLgAECn8bAAIFAAYJgAf0LwDTAAAFAAYJgAf0LwDTAAAAAA==.',
Is='Isedeath:BAACLgAFFH8HAAMBAAIJ1hHpdACeAAABAAIJ1hHpdACeAAARAAEJtwQuCgBHAAAuAAQKfy4ABAEACAlSHJgwAHUCAAEACAlSHJgwAHUCACgAAgliAGtBAEYAABEAAQnbFlYUAEQAAAAA.',
Ja='Jabber:BAAALgAECgUJCQABLgAECggJGAADAGQPAA==.Jabul:BAAALgADCgYJBgAAAA==.Jack:BAABLgAECn8jAAMYAAgJhSMREABmAgAYAAYJNiMREABmAgAZAAIJXSX3GgBsAAAAAA==.Jaegerr:BAAALgAECggJEwAAAA==.Jalene:BAAALgADCgcJAwAAAA==.Jamonk:BAAALgADCgYJBwABLgADCggJCAAVAAAAAA==.Jamuul:BAAALgADCggJCAAAAA==.Janton:BAABLgAECn8XAAIIAAgJAAekJABMAQAIAAgJAAekJABMAQAAAA==.Jarrhead:BAAALgAECgUJDQAAAA==.Jastor:BAAALgADCgcJDgAAAA==.Jaxirl:BAAALgAECgUJBQAAAA==.',
Je='Jenaveive:BAAALgAECgQJBAAAAA==.Jethli:BAACLgAFFH8UAAIlAAUJtxDYFAAdAQAlAAUJtxDYFAAdAQAuAAQKfyAAAiUACAmNGeApALoBACUACAmNGeApALoBAAAA.',
Ji='Jigopocalyps:BAAALgADCgEJAQAAAA==.Jinn:BAAALgADCgYJBAAAAA==.',
Jj='Jjp:BAAALgADCgYJCQAAAA==.',
Jn='Jnex:BAAALgAECgEJAQAAAA==.',
Jo='Jojobeànfire:BAAALgADCgcJDQAAAA==.Joube:BAAALgAECggJEgAAAA==.',
Ju='Judgepain:BAAALgAECgEJBQAAAA==.Judgmental:BAABLgAECn8WAAMnAAgJmA8IGwCxAQAnAAgJmA8IGwCxAQADAAYJaQLfsgCPAAAAAA==.Juicytootsie:BAABLgAECn8UAAIGAAYJdwNpBwHtAAAGAAYJdwNpBwHtAAAAAA==.Justifried:BAAALgAECgQJBAAAAA==.',
['Jä']='Jävel:BAAALgAECgYJCQAAAA==.',
Ka='Kaelysong:BAAALgAECgMJBAAAAA==.Kairah:BAAALgAECgIJBAAAAA==.Kairiandel:BAAALgAECgEJAQAAAA==.Kaivig:BAAALgAECgEJAQAAAA==.Kalï:BAABLgAECn8YAAIiAAgJsh4TDAB+AgAiAAgJsh4TDAB+AgAAAA==.Karaha:BAAALgADCgcJBwAAAA==.Kayllin:BAAALgADCgYJDAAAAA==.Kaysina:BAAALgADCgUJBQAAAA==.',
Ke='Keener:BAABLgAECn8WAAMIAAYJhiF8EADwAQAIAAYJhiF8EADwAQAQAAIJMBNkOQB/AAAAAA==.Kelenil:BAAALgAECgEJAQABLgAECgQJBAAVAAAAAA==.Kerrla:BAACLgAFFH8TAAIFAAUJjBkdCwBTAQAFAAUJjBkdCwBTAQAuAAQKfycAAgUACAngI5wJAPsCAAUACAngI5wJAPsCAAEuAAMKAQkBABUAAAAA.Keylleth:BAAALgAECgYJDAAAAA==.',
Kh='Khamari:BAAALgADCgYJBgABLgAECgYJEAAVAAAAAA==.Khamnox:BAAALgAECgYJEAAAAA==.Khlamps:BAAALgADCgYJBgAAAA==.',
Ki='Kielnmsoftly:BAABLgAECn8WAAIBAAkJ5BSLHgARAgABAAkJ5BSLHgARAgAAAA==.Kilaia:BAABLgAECn8UAAIiAAYJkxCxRgA5AQAiAAYJkxCxRgA5AQAAAA==.Kilda:BAAALgADCgcJBwAAAA==.Killerklown:BAAALgAECgUJCAAAAA==.Kirksñiper:BAAALgAECgYJDgAAAA==.Kirru:BAABLgAECn8jAAQWAAgJFA6FGgB3AQAWAAgJFA6FGgB3AQAgAAMJXAG8TQBbAAAXAAIJZgMBTABDAAAAAA==.Kirsty:BAAALgADCgMJAwAAAA==.',
Kl='Klink:BAAALgAECgUJDwABLgAECgUJEgAVAAAAAA==.',
Kn='Knoble:BAAALgAECgQJCAAAAA==.',
Kr='Kraisee:BAAALgADCgEJAQAAAA==.Kreatan:BAAALgADCgUJBwAAAA==.Kreaton:BAAALgAECggJEQAAAA==.Krel:BAAALgAECgEJAQAAAA==.Kryntoo:BAAALgADCggJCAAAAA==.Kryptix:BAAALgADCgYJCAAAAA==.',
Ks='Kshatriya:BAAALgADCgQJBAAAAA==.',
Ku='Kuchikix:BAAALgAECgEJAQAAAA==.Kuchíki:BAABLgAECn8ZAAImAAcJTQ4MJQAfAQAmAAcJTQ4MJQAfAQAAAA==.Kushynuggles:BAAALgADCgEJAQAAAA==.',
Kw='Kwag:BAAALgAECgcJBgAAAA==.',
La='Laaklem:BAAALgADCgkJHgAAAA==.Laei:BAAALgAECggJEAAAAA==.Lagerthaa:BAAALgADCgIJAgAAAA==.Laserfingies:BAAALgAECgUJBgAAAA==.Lastsun:BAABLgAECn8UAAIGAAcJmQ1dVwBnAQAGAAcJmQ1dVwBnAQAAAA==.Lauridana:BAAALgADCgEJAQAAAA==.Lavacakes:BAACLgAFFH8HAAIhAAIJYSaRHwDfAAAhAAIJYSaRHwDfAAAuAAQKfyUAAiEACAnZJL8DADoDACEACAnZJL8DADoDAAAA.Lazaren:BAAALgADCgMJAwAAAA==.Lazyboy:BAABLgAECn8ZAAIIAAcJpR4AHABtAgAIAAcJpR4AHABtAgAAAA==.',
Le='Lelantoz:BAABLgAECn8eAAIiAAYJuAlKVwAJAQAiAAYJuAlKVwAJAQAAAA==.Leliel:BAAALgADCgEJAQAAAA==.Lenailla:BAAALgADCgkJCQAAAA==.Lezibean:BAAALgADCgcJBwABLgAECgIJAgAVAAAAAA==.',
Li='Lidan:BAABLgAECn8bAAISAAgJGA8lBwByAQASAAgJGA8lBwByAQAAAA==.Liebli:BAAALgAECgQJBAAAAA==.Liffry:BAAALgADCgEJAQAAAA==.Lilena:BAAALgADCgkJLQAAAA==.Lilnao:BAAALgAECgcJCAAAAA==.Linaeni:BAAALgAECgQJBAAAAA==.Linaradice:BAAALgAECggJDwAAAA==.Linkinbiox:BAAALgAECgUJCgAAAA==.',
Lo='Lockedown:BAAALgADCgkJCQAAAA==.Logyn:BAAALgAECgMJBAAAAA==.Lore:BAABLgAECn8cAAIGAAgJ1RHsWQBhAQAGAAgJ1RHsWQBhAQAAAA==.Lotsalock:BAAALgADCgcJCwAAAA==.',
Lu='Lululemons:BAAALgAECgMJBAAAAA==.',
Ly='Lyphysia:BAAALgAECgcJDQAAAA==.Lyrelia:BAAALgAECgYJDgAAAA==.Lyssiarose:BAAALgAECgYJEQAAAA==.',
['Lë']='Lëucocrystal:BAAALgADCgEJAgAAAA==.',
Ma='Mack:BAAALgADCgEJAQAAAA==.Madbones:BAABLgAECn8YAAMYAAgJbBSTKgC7AQAYAAgJFhKTKgC7AQAaAAMJXxqKEwD2AAAAAA==.Mado:BAAALgAECggJEQAAAA==.Maeveracy:BAAALgADCgUJBQAAAA==.Mageijuana:BAABLgAECn8bAAIGAAgJDh4aGwBHAgAGAAgJDh4aGwBHAgAAAA==.Magicky:BAABLgAECn8YAAIGAAYJlBWUXABaAQAGAAYJlBWUXABaAQAAAA==.Magicsauce:BAAALgAECgYJBwAAAA==.Mahlkier:BAAALgADCgYJEQAAAA==.Maikego:BAAALgAECgUJCAAAAA==.Malchelo:BAAALgAECggJEAAAAA==.Malfhunter:BAACLgAFFH8FAAIUAAMJmgktDgDXAAAUAAMJmgktDgDXAAAuAAQKfyoAAhQACQl3GfUSAJ4CABQACQl3GfUSAJ4CAAAA.Maligosa:BAAALgADCgUJBQAAAA==.Manabender:BAAALgAECgIJAgAAAA==.Mangolassi:BAAALgADCgEJAQAAAA==.Manofwood:BAABLgAFFH8JAAILAAQJUBEdBAAJAQALAAQJUBEdBAAJAQAAAA==.Mantodea:BAAALgAECgQJAQAAAA==.Manus:BAAALgAECgMJBQAAAA==.Maranatha:BAAALgADCgEJAQAAAA==.Marossa:BAAALgADCgMJAwAAAA==.Marymae:BAAALgADCgYJEQAAAA==.Masskiller:BAAALgADCgIJAgAAAA==.Masumi:BAAALgADCgEJAQAAAA==.Mattikus:BAAALgAECgQJCAAAAA==.Maximilion:BAAALgAECgYJCgAAAA==.',
Me='Megrim:BAAALgADCgIJAwAAAA==.Mehrartz:BAAALgADCgYJCwAAAA==.Melyn:BAAALgADCgIJAgAAAA==.Merdocki:BAACLgAFFH8HAAMZAAIJ+ReQEABXAAAYAAIJ+RdnXACUAAAZAAEJURWQEABXAAAuAAQKfycAAxkACAnhIcMPANIBABkABQk6H8MPANIBABgABQlgIRQuAKsBAAAA.Merdra:BAAALgADCggJCAAAAA==.Merdre:BAACLgAFFH8HAAQWAAIJaxX1FQCPAAAWAAIJaxX1FQCPAAAgAAIJHAxKIQCJAAAXAAEJVAB4IwAtAAAuAAQKfzIABBYACAmLHI8OAHUCABYACAlLHI8OAHUCACAABgkSGF8SALYBABcABQkAAgdLAK0AAAAA.Mertele:BAAALgAECgQJBAAAAA==.Messörem:BAAALgADCgYJBgAAAA==.Metasavage:BAAALgAECgQJBAABLgAECgUJBQAVAAAAAA==.',
Mi='Michealhunt:BAAALgAECgcJCAAAAA==.Midory:BAAALgAECgEJAQAAAA==.Mikimukka:BAAALgADCgIJAwAAAA==.Milim:BAAALgAECgQJBQABLgAECgUJBQAVAAAAAA==.Milkymocha:BAABLgAECn8jAAIbAAgJZxmTBgD5AQAbAAgJZxmTBgD5AQAAAA==.Minus:BAAALgADCgMJAwAAAA==.Misfitjoker:BAAALgAECgEJAQAAAA==.Misscorona:BAAALgADCggJDQAAAA==.Mistyque:BAAALgAECgQJCgAAAA==.Mithrond:BAAALgADCggJCgABLgAECgEJAQAVAAAAAA==.',
Mo='Modercai:BAAALgAECgQJBAAAAA==.Monkeymann:BAAALgADCgYJBgAAAA==.Morcant:BAAALgAECgYJDAAAAA==.Morhg:BAABLgAECn8jAAMZAAgJ1Qi4DAAGAQAYAAgJkAehXQAWAQAZAAcJFgi4DAAGAQAAAA==.Morianoley:BAAALgADCggJEwAAAA==.Morlu:BAABLgAECn8dAAIIAAYJKCMXIQBKAgAIAAYJKCMXIQBKAgAAAA==.',
Ms='Msdonnapally:BAAALgAECgUJCQAAAA==.',
Mu='Mugnar:BAAALgADCgcJBwAAAA==.',
My='Myn:BAAALgAECgQJBAABLgAECgYJBgAVAAAAAA==.',
Na='Nadirya:BAEALgAECgcJCQABLgAFFAQJDgAIAN0TAA==.Nazkrul:BAAALgADCgMJAwAAAA==.',
Ne='Nellykorda:BAAALgAECgMJBQAAAA==.Neodruid:BAAALgAECgYJEAAAAA==.Nexxicus:BAAALgADCgMJAwAAAA==.',
Ni='Nightlywomen:BAAALgADCgcJDAAAAA==.Nightmehr:BAACLgAFFH8FAAIGAAMJVxdzQwADAQAGAAMJVxdzQwADAQAuAAQKfyIAAgYACQkcI3wQAEUDAAYACQkcI3wQAEUDAAAA.Nightphaze:BAAALgAECgEJAQABLgAECggJGAADAGQPAA==.Nihm:BAAALgADCgcJEQAAAA==.Nikolatte:BAAALgAECgEJAwAAAA==.Nimda:BAABLgAECn8aAAIBAAgJfiFmGwDZAgABAAgJfiFmGwDZAgAAAA==.',
No='Nosaj:BAAALgADCgkJCwAAAA==.',
Nu='Nullex:BAABLgAECn8jAAQHAAgJ+hU9JACwAQAHAAgJ+hU9JACwAQAKAAEJ8wkkRgApAAANAAEJZQgpIwAeAAAAAA==.',
Ny='Nyki:BAAALgAECgEJAQAAAA==.',
Ob='Oberon:BAAALgADCgYJBgAAAA==.',
Od='Odlaw:BAABLgAECn8XAAIXAAcJxwisIgArAQAXAAcJxwisIgArAQAAAA==.',
Ol='Olaria:BAAALgAECgQJBQABLgAECgcJGgAiAOoRAA==.Oldsaggins:BAAALgAECgcJDwAAAA==.Olikel:BAAALgADCgEJAQAAAA==.Ollymay:BAAALgAECgYJBgAAAA==.Olm:BAAALgAECgUJBQAAAA==.',
On='Onedruidtion:BAAALgAECgMJAwAAAA==.',
Op='Ophekins:BAAALgADCgcJCwAAAA==.',
Or='Orcman:BAAALgAECgEJAQAAAA==.Orheo:BAAALgADCgQJBAAAAA==.Originalchip:BAAALgAECgQJCwAAAA==.Orionmoon:BAAALgAECgcJCAAAAA==.Orlos:BAABLgAECn8aAAIiAAcJ6hEoMgCFAQAiAAcJ6hEoMgCFAQAAAA==.Oräkk:BAACLgAFFH8HAAIQAAMJSRlNBwDuAAAQAAMJSRlNBwDuAAAuAAQKfxUAAhAABwkUHU0NADYCABAABwkUHU0NADYCAAAA.',
Os='Osrs:BAAALgAECgMJAwAAAA==.',
Ox='Oxelmorphs:BAAALgADCgcJCwAAAA==.',
Pa='Padrin:BAABLgAECn8fAAMiAAgJdRZuHADyAQAiAAgJdRZuHADyAQAUAAUJMA3jUQAFAQAAAA==.Palehorsemen:BAAALgAECgUJCwAAAA==.Pandaberry:BAAALgAECgYJBwAAAA==.Pandapaws:BAACLgAFFH8KAAIhAAMJnBqEHQDuAAAhAAMJnBqEHQDuAAAuAAQKfysAAiEACQnNISsEAAIDACEACQnNISsEAAIDAAAA.Pandomonium:BAAALgADCgIJAgAAAA==.Papawaas:BAAALgAECgEJAQAAAA==.Parthal:BAAALgAECgYJEwAAAA==.Partylock:BAAALgAECgMJAwABLgAECggJEAAVAAAAAA==.Partyshooter:BAAALgAECggJEAAAAA==.Patmage:BAABLgAECn8kAAIGAAgJmBfLMADdAQAGAAgJmBfLMADdAQABLgAFFAQJDQAFAJQPAA==.',
Pd='Pdiddi:BAABLgAECn8dAAMBAAgJ0h/HGAA3AgABAAgJFxzHGAA3AgARAAYJqCD3BAD6AQAAAA==.',
Pe='Peed:BAAALgAECgcJEwAAAA==.Pellaeon:BAABLgAECn8VAAIBAAkJ2BiFSQAWAgABAAkJ2BiFSQAWAgAAAA==.',
Ph='Phexia:BAAALgAECgUJCAAAAA==.Phlan:BAEALgAECgQJBAAAAA==.Phrostir:BAAALgAECgkJDAAAAA==.Phylactery:BAABLgAECn8lAAIBAAgJCRp1PQBCAgABAAgJCRp1PQBCAgAAAA==.',
Pi='Pierre:BAACLgAFFH8VAAQiAAUJQxmiBQBJAQAiAAQJQxmiBQBJAQATAAIJEA3pFQCmAAAUAAEJAABRIAAAAAAuAAQKfyUABCIACAmRItwRAKkCACIACAnGIdwRAKkCABMABQmTG+sXAEwBABQABgnpDX9OABYBAAAA.Pillgrimm:BAABLgAECn8bAAIUAAgJLhFnBwCVAQAUAAgJLhFnBwCVAQAAAA==.Pinktax:BAAALgAECgcJBwAAAA==.Pirotic:BAAALgADCgcJCwAAAA==.',
Po='Poisson:BAABLgAECn8hAAIOAAkJNRWCEQCUAgAOAAkJNRWCEQCUAgAAAA==.Polishdir:BAAALgAECgYJEAAAAA==.Polishduo:BAAALgAFFAEJAQAAAA==.Porzingus:BAAALgADCgcJBwAAAA==.Poxi:BAABLgAECn8WAAIdAAgJDRerEwBHAgAdAAgJDRerEwBHAgAAAA==.',
Pr='Praesidiel:BAABLgAECn8WAAIXAAcJIxd3GwABAgAXAAcJIxd3GwABAgAAAA==.Presxia:BAAALgADCgYJBgAAAA==.Providence:BAACLgAFFH8IAAIKAAMJYA8/CgDzAAAKAAMJYA8/CgDzAAAuAAQKfygAAgoACQkSI+YBAH4DAAoACQkSI+YBAH4DAAAA.Prsr:BAAALgAECgMJAwABLgAFFAUJDwABAGIcAA==.',
Pu='Pudgypaws:BAAALgAECgYJCwAAAA==.Puffed:BAAALgAECgIJAgABLgAFFAIJBwAWAGsVAA==.Punchkick:BAAALgAECgUJBwAAAA==.Purfukt:BAAALgAECgYJBgAAAA==.',
['På']='Pån:BAAALgAECgEJAQAAAA==.',
['Pè']='Pèwpéw:BAAALgAECgUJCQAAAA==.',
Qu='Quickmend:BAAALgAECgQJBgAAAA==.Quickpal:BAAALgAECgUJBwAAAA==.Quickpaw:BAACLgAFFH8IAAImAAMJPRf8FQDWAAAmAAMJPRf8FQDWAAAuAAQKfyYAAiYACQkOIxUDAE0DACYACQkOIxUDAE0DAAAA.Quickshot:BAAALgADCgEJAQAAAA==.',
Ra='Raani:BAAALgADCgcJBwAAAA==.Raccoons:BAACLgAFFH8UAAIiAAUJqh7mAgBuAQAiAAUJqh7mAgBuAQAuAAQKfx8AAyIACQnUIHIbAGICACIACQnUIHIbAGICABQAAwkrCWpqAJQAAAAA.Rageproof:BAABLgAECn8xAAIDAAgJ2AmQVQBHAQADAAgJ2AmQVQBHAQAAAA==.Ragged:BAACLgAFFH8FAAIBAAMJcBgtUwDoAAABAAMJcBgtUwDoAAAuAAQKfx0AAgEACAk3Ih4MAKcCAAEACAk3Ih4MAKcCAAAA.Raidbloom:BAACLgAFFH8PAAIEAAMJgiA9DAAfAQAEAAMJgiA9DAAfAQAuAAQKfxsAAgQACQlXI0YGACcDAAQACQlXI0YGACcDAAAA.Raidheal:BAABLgAFFH8FAAIgAAIJNwaEIgB+AAAgAAIJNwaEIgB+AAABLgAFFAMJDwAEAIIgAA==.Rakroth:BAAALgAECgYJDwAAAA==.Ramook:BAAALgADCgkJDwAAAA==.Randomchar:BAABLgAECn8qAAMDAAgJ9A6YWgA7AQADAAgJ7wuYWgA7AQAbAAUJORGtGADRAAAAAA==.Rankor:BAAALgAECgYJEAABLgAECggJLgABAIQeAA==.Rastann:BAACLgAFFH8IAAIDAAMJ7hRMKwADAQADAAMJ7hRMKwADAQAuAAQKfyUAAgMACQlWIgQOAB4DAAMACQlWIgQOAB4DAAAA.Ratrun:BAAALgAECgEJAQAAAA==.Raycharles:BAAALgAECgYJAQAAAA==.',
Re='Realir:BAAALgAECggJDwAAAA==.Reapertoo:BAACLgAFFH8XAAMBAAUJ2SS0DACmAQABAAUJ2SS0DACmAQAoAAEJAAAtMQAAAAAuAAQKfywAAwEACQlAJIYHAGQDAAEACQlAJIYHAGQDABEAAQlmGaAWADYAAAAA.Recreant:BAAALgADCgYJAQAAAA==.Redbaron:BAABLgAECn8jAAIKAAkJfBSWCQDzAQAKAAkJfBSWCQDzAQAAAA==.Regeth:BAAALgAECgcJEwAAAA==.Repyns:BAACLgAFFH8iAAQYAAgJeRpcAwDuAQAYAAcJzBlcAwDuAQAZAAQJDBy6BQAWAQAaAAIJ8iWfBABsAAAuAAQKfx4ABBgACQnwJcIIADsDABgACAnwJcIIADsDABkAAwnzIn8pABwBABoAAwlrH4cRABUBAAAA.Retep:BAAALgADCgEJAQABLgAECgMJBwAVAAAAAA==.Rethul:BAABLgAECn8iAAMdAAgJfBCAGAB9AQAdAAgJfBCAGAB9AQAfAAYJQwTzHgB1AAAAAA==.Retsü:BAAALgAECggJDwABLgAFFAcJIgAgAGQRAA==.',
Rh='Rhhonn:BAAALgAECgYJCgAAAA==.Rhollor:BAAALgAECgMJAwAAAA==.',
Ri='Ridic:BAABLgAECn8uAAIBAAgJhB7eHgAPAgABAAgJhB7eHgAPAgAAAA==.Rimeblade:BAAALgAECgMJAwAAAA==.',
Ro='Robutinblue:BAACLgAFFH8NAAIGAAUJjhelJgBbAQAGAAUJjhelJgBbAQAuAAQKfxsAAgYACAkvH1slAN0CAAYACAkvH1slAN0CAAAA.Rocklesnar:BAAALgAECgMJAwAAAA==.Rondle:BAAALgAECgIJBAAAAA==.Rootbeerd:BAAALgAECgYJBgAAAA==.Roshak:BAAALgAECgEJAgAAAA==.Rozalin:BAACLgAFFH8HAAIGAAIJ5x2SVgC+AAAGAAIJ5x2SVgC+AAAuAAQKfycAAgYACAm0JekKAG0DAAYACAm0JekKAG0DAAAA.Rozalinamoon:BAAALgAECgIJAgAAAA==.',
Ru='Ruffprophet:BAAALgAECgEJAQAAAA==.Rugelach:BAEALgAECgEJAQABLgAECgQJBAAVAAAAAA==.Rumi:BAABLgAECn8bAAINAAgJrBOoBgCPAQANAAgJrBOoBgCPAQAAAA==.Rurouni:BAAALgADCgcJBwAAAA==.',
Ry='Ryoshi:BAACLgAFFH8HAAITAAIJ+hgXFACyAAATAAIJ+hgXFACyAAAuAAQKfywAAhMACAkPICIDAP0CABMACAkPICIDAP0CAAAA.',
Sa='Sabotender:BAAALgADCgkJEAAAAA==.Sacredragon:BAAALgAECggJCgAAAA==.Sacredswords:BAACLgAFFH8MAAMIAAQJ9RiuCgBOAQAIAAQJ9RiuCgBOAQAPAAEJnwMxDQBLAAAuAAQKfxkAAggACAkiHvUVAJ0CAAgACAkiHvUVAJ0CAAAA.Saeys:BAAALgADCgMJAwAAAA==.Sandalis:BAAALgADCgYJBwABLgAECgkJIQADAMkYAA==.Sandscale:BAAALgADCggJCAAAAA==.Sannctuary:BAAALgAECgYJEAAAAA==.Sapphiremist:BAAALgAECgYJEQAAAA==.Sauerkraut:BAAALgAECgcJAQAAAA==.Savagesin:BAAALgAFFAIJAgABLgAECgUJBQAVAAAAAA==.Sayen:BAAALgADCgkJCQAAAA==.',
Sc='Scachity:BAABLgAECn8ZAAMZAAgJyRmmAgAZAgAZAAgJyRmmAgAZAgAYAAMJxAlLowB0AAAAAA==.Scarekroe:BAABLgAECn8lAAMcAAgJZxzACAA0AgAcAAgJZxzACAA0AgAlAAEJixR+iQAzAAAAAA==.Schein:BAAALgADCgUJDQAAAA==.Scratchers:BAABLgAECn8eAAIFAAgJ4iLKBgArAwAFAAgJ4iLKBgArAwAAAA==.',
Se='Seelina:BAAALgADCgYJBgAAAA==.Sehëthi:BAAALgAECggJCwAAAA==.Selanni:BAAALgADCgcJCAAAAA==.Sepulchre:BAAALgAECgYJBgAAAA==.Serlotte:BAAALgADCgcJEQAAAA==.',
Sh='Shadowish:BAAALgADCgEJAQAAAA==.Shadunx:BAAALgADCgIJAgABLgAECgMJAwAVAAAAAA==.Shamaroo:BAAALgAECgUJBQAAAA==.Shaundakul:BAAALgAECgYJBgAAAA==.Shephion:BAAALgAECgEJAQABLgAFFAIJBQAcAOokAA==.Shiee:BAAALgADCgEJAQAAAA==.Shortnstack:BAABLgAECn8aAAIiAAcJIREYNQB4AQAiAAcJIREYNQB4AQAAAA==.Shãdow:BAAALgAECgYJDgAAAA==.',
Si='Sidetracked:BAABLgAECn8jAAIGAAgJ0hizKwDzAQAGAAgJ0hizKwDzAQAAAA==.Silanah:BAACLgAFFH8HAAIlAAIJ9Bm7KQChAAAlAAIJ9Bm7KQChAAAuAAQKfygAAiUACAndG88NAOoBACUACAndG88NAOoBAAAA.Silverheart:BAAALgAECgcJDQAAAA==.Silvershade:BAAALgADCgEJAQAAAA==.',
Sk='Skawalker:BAACLgAFFH8IAAMjAAMJqQ2UBwCmAAAjAAIJMQyUBwCmAAAEAAIJLhRMMACHAAAuAAQKfyQAAwQACQlJI/kFAC0DAAQACQlJI/kFAC0DACMABAnCDyMXALsAAAAA.Skyleebaby:BAAALgADCgcJBwAAAA==.',
Sl='Slashers:BAAALgADCgkJCQABLgAECggJHgAFAOIiAA==.Slaynne:BAACLgAFFH8HAAIIAAIJtiL5HQC/AAAIAAIJtiL5HQC/AAAuAAQKfy4AAwgACAm1JH0IACQDAAgACAm1JH0IACQDAA8AAQm9CEZEADAAAAAA.Sleven:BAAALgAECgUJCAABLgAFFAEJAQAVAAAAAA==.Slowfel:BAAALgADCgcJBwAAAA==.',
Sm='Smábes:BAAALgAECgQJBwAAAA==.Smäug:BAACLgAFFH8RAAMdAAYJpxmyCACjAQAdAAUJpxmyCACjAQAeAAEJAACiBwB1AAAuAAQKfyAABB4ACAlJJN4EALUCAB4ABwlbI94EALUCAB0ABAlcI9UkAJYBAB8ABwkcBaUmAEABAAAA.',
Sn='Snobaws:BAAALgAECggJDgAAAA==.',
So='Sockz:BAABLgAECn8bAAIOAAgJfBm0FABtAgAOAAgJfBm0FABtAgAAAA==.Solria:BAABLgAECn8mAAIWAAkJcRXgDAAYAgAWAAkJcRXgDAAYAgAAAA==.Solrosenborg:BAABLgAECn8nAAIBAAkJAx/rCgC0AgABAAkJAx/rCgC0AgAAAA==.Solrosenburg:BAAALgAECgcJEgABLgAECgkJJwABAAMfAA==.Sondreman:BAABLgAECn8aAAMjAAgJiwlgDABSAQAjAAgJiwlgDABSAQAEAAIJoABW5gAfAAAAAA==.Sorcereo:BAAALgADCgIJBQAAAA==.',
Sp='Spicychip:BAAALgADCgUJBQAAAA==.Spintwowin:BAAALgADCgUJBQAAAA==.Splashers:BAAALgADCgQJBAAAAA==.Spookyghost:BAAALgADCgMJAwAAAA==.Spærkle:BAAALgAECgUJBgAAAA==.',
Sq='Squirreltag:BAAALgAECgUJCQAAAA==.',
Sr='Srmorphsalot:BAAALgAECgEJAQABLgAFFAUJFQAiAEMZAA==.',
St='Starnex:BAAALgADCgYJAQAAAA==.Statyrea:BAAALgAECgEJAQAAAA==.Stomped:BAAALgAECgcJDQAAAA==.Strikes:BAAALgAECgYJCAABLgAFFAIJBwANANcjAA==.Stromlac:BAAALgADCgYJBgAAAA==.Styx:BAACLgAFFH8QAAIQAAQJwSGYAwCHAQAQAAQJwSGYAwCHAQAuAAQKfykAAhAACAlgJqkBAGoDABAACAlgJqkBAGoDAAAA.',
Su='Sukfoot:BAAALgAECgMJAwAAAA==.Sumbatadh:BAABLgAECn8aAAMKAAgJlgwkEgBoAQAKAAgJlgwkEgBoAQAHAAEJPgPu7wAiAAAAAA==.Supergooner:BAAALgAFFAEJAQABLgAFFAUJFQAcAKQhAA==.',
Sw='Swiftsoul:BAAALgADCgEJAQAAAA==.',
Sy='Sybexia:BAAALgAECgEJAQAAAA==.Sylvestris:BAABLgAECn8WAAIEAAgJNBtYLgDzAQAEAAgJNBtYLgDzAQAAAA==.',
Ta='Tabcast:BAAALgADCgUJBQAAAA==.Tacodad:BAAALgAECgQJBAAAAA==.Tacofart:BAAALgADCgMJAwAAAA==.Tacos:BAAALgAECgYJDwAAAA==.Tacotitan:BAAALgAECgkJBgAAAA==.Tailas:BAAALgAECgYJEQAAAA==.Tailyan:BAAALgADCgEJAQAAAA==.Taiyana:BAAALgADCgcJDgAAAA==.Talanthir:BAAALgADCgMJAwAAAA==.Tangie:BAAALgADCgkJHgAAAA==.Tankjob:BAAALgAECgQJDQAAAA==.Tanklorswift:BAAALgAECgIJBQAAAA==.Taojin:BAABLgAECn8UAAQSAAcJfA9lCgAgAQAOAAUJ5hALOwBBAQASAAcJIw5lCgAgAQAMAAEJ5gECEAAbAAAAAA==.Taojïn:BAAALgAECgEJAQAAAA==.Tapandsap:BAAALgAECgEJAQAAAA==.Tatsuyâ:BAAALgADCgYJCwAAAA==.',
Te='Teapot:BAAALgAECgEJAQAAAA==.Tedoseirum:BAABLgAECn8dAAIKAAkJyCRnAwBNAwAKAAkJyCRnAwBNAwAAAA==.Tengenthas:BAAALgAECgEJAQAAAA==.Terpyu:BAAALgAECgYJDgAAAA==.Testicuhls:BAAALgAECgYJEwAAAA==.Texasbilly:BAAALgAECgYJBQAAAA==.Texasredneck:BAAALgADCgQJAwAAAA==.',
Th='Thalchy:BAAALgAECgYJDAAAAA==.Thaydel:BAAALgADCgMJAwAAAA==.Thedtwo:BAABLgAECn8XAAIDAAYJWR33ZQC0AQADAAYJWR33ZQC0AQAAAA==.Thelizzah:BAABLgAECn8UAAMDAAcJxgy4cgAHAQADAAYJcQq4cgAHAQAnAAIJXwBrnQAsAAAAAA==.Thelvaris:BAAALgAECgYJCwAAAA==.Thorgarrus:BAACLgAFFH8IAAIDAAMJTxvqIwAdAQADAAMJTxvqIwAdAQAuAAQKfyMAAgMACQl4HrEYANUCAAMACQl4HrEYANUCAAAA.',
Ti='Tigerwoodz:BAAALgAECgYJCgAAAA==.Tilbourne:BAAALgAECgEJAQAAAA==.Timfist:BAAALgAECgUJBwAAAA==.Tinada:BAAALgADCgEJAQABLgADCgEJAQAVAAAAAA==.Tinytrina:BAAALgADCgYJBgAAAA==.',
To='Toddie:BAABLgAECn8dAAMiAAgJQBzHGwD2AQAiAAgJQBzHGwD2AQAUAAMJugxjbQCJAAAAAA==.Tolkein:BAAALgADCgEJAQAAAA==.Tommyj:BAAALgAECgQJBAAAAA==.Torep:BAAALgAECgQJBAAAAA==.Tormod:BAABLgAECn8bAAIiAAgJKRiKIQDTAQAiAAgJKRiKIQDTAQAAAA==.Tormodd:BAABLgAECn8aAAIKAAYJ4w0RGgAOAQAKAAYJ4w0RGgAOAQAAAA==.Torsyn:BAAALgAECgUJBQABLgAECggJHQAiAEAcAA==.Torvaldt:BAAALgAECgIJAgABLgAECggJHQAiAEAcAA==.',
Tr='Traedea:BAAALgAECgYJCQAAAA==.Traps:BAAALgAECggJCgAAAA==.Trashypanda:BAACLgAFFH8VAAIpAAUJDCMZAACiAQApAAUJDCMZAACiAQAuAAQKfykAAikACAmAJHsAADQDACkACAmAJHsAADQDAAAA.Trinagirl:BAAALgAECgYJBQAAAA==.Tristanyia:BAABLgAECn8VAAImAAgJLxjzCwAsAgAmAAgJLxjzCwAsAgAAAA==.Troolen:BAAALgAECgMJBgAAAA==.Tryana:BAABLgAECn8nAAIlAAgJIQbfJAAYAQAlAAgJIQbfJAAYAQAAAA==.Trystiania:BAAALgAECgYJDwAAAA==.',
Ts='Tseraphim:BAAALgADCgMJBAAAAA==.',
Tt='Tt:BAAALgAECggJEwAAAA==.',
Tu='Tuggnugg:BAAALgAECgEJAQAAAA==.Turcomund:BAAALgADCgIJAgAAAA==.',
Tw='Twentynein:BAAALgAECgcJBwAAAA==.Twentynine:BAABLgAECn8vAAQTAAgJaiEBCgADAgAUAAcJnhyYGwBMAgATAAcJMxwBCgADAgAiAAgJfhY1PQBZAQAAAA==.',
Ty='Tyledis:BAAALgAECgUJBQABLgAFFAIJBwAlAPQZAA==.Tyr:BAACLgAFFH8LAAICAAMJeBfbDgAAAQACAAMJeBfbDgAAAQAuAAQKfx8AAwIACQnUHbkMANICAAIACQnUHbkMANICACEAAQlwBdOJACQAAAAA.Tyrandi:BAAALgAFFAQJBAAAAA==.Tyrnova:BAAALgAECgQJCAAAAA==.Tyrsa:BAAALgAECgQJBwAAAA==.',
Tz='Tzneetch:BAAALgAECgEJAQAAAA==.',
['Tï']='Tïnk:BAABLgAECn8gAAIHAAgJCxUCJgCmAQAHAAgJCxUCJgCmAQABLgAFFAIJAgAVAAAAAA==.',
['Tö']='Töshïrö:BAAALgAECgQJCQAAAA==.',
Ub='Ubel:BAAALgADCgEJAwAAAA==.',
Ud='Udderlee:BAAALgAECgYJEwAAAA==.',
Uh='Uhope:BAAALgAECgQJBwAAAA==.',
Uk='Ukog:BAAALgAECggJEwAAAA==.',
Um='Umbravolt:BAACLgAFFH8IAAILAAMJgBg2BQDjAAALAAMJgBg2BQDjAAAuAAQKfywAAgsACQmnIR0BAFgDAAsACQmnIR0BAFgDAAAA.Umineko:BAAALgAECgEJAQAAAA==.',
Un='Unravel:BAAALgADCgYJEQAAAA==.Unrealpriest:BAAALgAECgMJAwAAAA==.Unrealronin:BAABLgAECn8cAAMQAAgJRgShGwDeAAAQAAgJxwKhGwDeAAAPAAYJmgXHJADHAAAAAA==.',
Ur='Uruchi:BAAALgADCgEJAQAAAA==.',
Va='Vaelorn:BAABLgAECn8VAAIHAAgJliDrFADaAgAHAAgJliDrFADaAgAAAA==.Vaelun:BAAALgADCggJCwAAAA==.Vaeris:BAAALgAECgEJAQAAAA==.Vakero:BAAALgAECgYJEwAAAA==.Valeriana:BAAALgADCgQJBQAAAA==.Valice:BAAALgAECgEJAQAAAA==.Vapor:BAAALgAECgEJAgAAAA==.Vatheus:BAAALgADCgYJBgAAAA==.Vathion:BAAALgAECgMJAwAAAA==.',
Ve='Vert:BAAALgADCgYJBgABLgAFFAQJCQAZAIAJAA==.',
Vi='Vibrance:BAABLgAECn8cAAQfAAgJNCCIBQDwAgAfAAgJNCCIBQDwAgAdAAYJFBrTKgBpAQAeAAIJSRL2MgB+AAAAAA==.Vindicus:BAAALgAECgQJBgAAAA==.Viridesa:BAAALgAECgQJAQAAAA==.Vivienne:BAABLgAECn8jAAInAAkJahJZLADVAQAnAAkJahJZLADVAQAAAA==.',
Vo='Voidcore:BAABLgAECn8cAAIHAAkJMBq2DwBHAgAHAAkJMBq2DwBHAgAAAA==.',
Vv='Vv:BAAALgAECgMJAwAAAA==.',
Vy='Vyagra:BAAALgAECgYJBgAAAA==.Vyrinthial:BAAALgADCgUJBwAAAA==.Vyrnath:BAAALgAECgEJAQAAAA==.',
Wa='Walon:BAAALgADCgcJDgABLgAECgYJBgAVAAAAAA==.Warfarmer:BAAALgAECgUJDAAAAA==.Warhawke:BAAALgADCgYJCAAAAA==.',
We='Weak:BAAALgAECgYJDQAAAA==.Weakhand:BAAALgADCgIJAwAAAA==.Webs:BAAALgADCgUJBQAAAA==.Weel:BAACLgAFFH8FAAIHAAMJeAx8NgDYAAAHAAMJeAx8NgDYAAAuAAQKfyQAAgcACQk1G8IVAA4CAAcACQk1G8IVAA4CAAAA.',
Wh='When:BAAALgADCgQJBAABLgAFFAMJBwAmAMUXAA==.Wheresdparty:BAAALgAECgEJAQAAAA==.Whilaanna:BAACLgAFFH8JAAIHAAUJqwwXKAARAQAHAAUJqwwXKAARAQAuAAQKfw4AAwcACAlyDwhtAFwBAAcABwkkEQhtAFwBAA0AAQlGBVUxAB4AAAAA.Whis:BAAALgAECgYJEgAAAA==.Whispernight:BAAALgADCgYJDQAAAA==.',
Wi='Widja:BAAALgADCgYJEQAAAA==.Wiilock:BAABLgAECn8dAAIYAAYJ4B4URAD/AQAYAAYJ4B4URAD/AQAAAA==.Wiivinelight:BAAALgAECgYJCgABLgAECgYJHQAYAOAeAA==.Wiivoker:BAAALgAECgUJBAABLgAECgYJHQAYAOAeAA==.Wildhus:BAAALgAECgUJBQAAAA==.Wildwhitwlkr:BAAALgADCgMJBQAAAA==.Wilfrid:BAAALgADCgIJAgABLgAFFAEJAQAVAAAAAA==.',
Wr='Wraithlord:BAAALgADCgcJBwAAAA==.',
['Wå']='Wåffle:BAAALgAECgEJAQABLgAECgcJFQASAC0lAA==.',
Xa='Xandari:BAAALgADCgkJDwAAAA==.Xania:BAAALgADCgYJBwAAAA==.',
Xe='Xenzel:BAAALgAECgIJAgAAAA==.',
Xx='Xxbadwar:BAAALgADCgEJAQAAAA==.',
['Xû']='Xûrû:BAAALgAECgYJCQAAAA==.',
Yc='Yce:BAABLgAECn8UAAMfAAYJUxKiEQAjAQAfAAYJUxKiEQAjAQAeAAMJjA2fDgCfAAAAAA==.',
Yo='Yoker:BAAALgADCgYJCwAAAA==.Yokersen:BAAALgAECgUJBQAAAA==.',
Za='Zaeladen:BAAALgAECgMJBQAAAA==.Zalorea:BAAALgAECgEJAgAAAA==.Zamorak:BAAALgADCgQJBAAAAA==.Zamrog:BAACLgAFFH8HAAIMAAMJkh/bAgAcAQAMAAMJkh/bAgAcAQAuAAQKfygAAgwACQnWIN4AABEDAAwACQnWIN4AABEDAAAA.Zamthyr:BAAALgAECgcJCAABLgAFFAMJBwAMAJIfAA==.Zanya:BAAALgAECgMJBQAAAA==.',
Ze='Zeiko:BAAALgAECgQJBAAAAA==.Zellah:BAAALgAECgcJDwAAAA==.Zenez:BAAALgAECgYJDAAAAA==.Zexor:BAAALgADCgYJDwAAAA==.Zeäl:BAAALgAECgEJAQAAAA==.',
Zh='Zhaoyun:BAABLgAECn8jAAImAAgJHxdZDQAVAgAmAAgJHxdZDQAVAgAAAA==.',
Zi='Zilen:BAAALgADCgUJBQAAAA==.Zilkir:BAACLgAFFH8HAAMnAAIJJyQhHADCAAAnAAIJJyQhHADCAAADAAIJaxwhQACrAAAuAAQKfy0AAycACAkxI9cEAB8DACcACAkxI9cEAB8DAAMABwmAIOlHAAsCAAAA.Ziran:BAAALgAECgYJCAAAAA==.Zivadhim:BAAALgAECgQJAQAAAA==.',
Zk='Zkollkrusher:BAAALgADCgYJBgAAAA==.Zkullkrushur:BAAALgAECgUJBQAAAA==.Zkvllkrusher:BAAALgADCgEJAQAAAA==.',
Zl='Zlyth:BAAALgAECgQJCQAAAA==.',
Zo='Zohan:BAAALgAECgMJAwAAAA==.Zooie:BAABLgAECn8fAAMCAAgJwRRPEwC9AQACAAgJwRRPEwC9AQAhAAgJ3hZcMwC3AQAAAA==.Zould:BAAALgAECgYJCwAAAA==.',
Zy='Zyrix:BAAALgADCgQJBAAAAA==.',
['Àr']='Àrthàs:BAAALgAECgcJBwAAAA==.',
['Är']='Ärtrix:BAAALgADCgEJAQAAAA==.',
['Ät']='Ätrixx:BAAALgAECgMJBQAAAA==.',
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
