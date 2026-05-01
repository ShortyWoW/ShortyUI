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

local lookup = {'DeathKnight-Unholy','Shaman-Elemental','Paladin-Retribution','Druid-Restoration','Druid-Balance','Mage-Frost','Warrior-Fury','Shaman-Enhancement','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Outlaw','DemonHunter-Vengeance','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Shaman-Restoration','Mage-Fire','Hunter-BeastMastery','Druid-Feral','Rogue-Assassination','Priest-Discipline','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','DeathKnight-Blood','Druid-Guardian','Mage-Arcane',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aantoc:BAAALgADCgUJBQAAAA==.',
Ad='Adramalech:BAAALgAECgEJAgABLgAFFAQJDgABAMQdAA==.',
Ae='Aeakos:BAAALgADCgQJBQABLgAECggJHgACANQUAA==.Aelan:BAAALgADCgQJBAAAAA==.',
Ag='Agapitus:BAAALgADCgIJAgAAAA==.',
Ai='Ailuridae:BAAALgADCgcJEwAAAA==.Aimbot:BAAALgADCgQJBAAAAA==.Aisele:BAAALgAECgYJDQAAAA==.',
Al='Alathir:BAAALgAECgcJDQAAAA==.Alenton:BAAALgADCgUJBgAAAA==.Alessia:BAAALgADCgMJBAAAAA==.Alluri:BAABLgAECn8dAAIDAAgJWxVYVQDiAQADAAgJWxVYVQDiAQAAAA==.Alone:BAAALgAECgYJDQAAAA==.Althemia:BAAALgAECgQJBQAAAA==.Alunamora:BAABLgAECn8iAAIEAAgJexrsCgBaAgAEAAgJexrsCgBaAgAAAA==.Alwind:BAABLgAECn8WAAIFAAcJ/RB6FQBWAQAFAAcJ/RB6FQBWAQAAAA==.',
Am='Ambient:BAABLgAECn8VAAIGAAYJMQ5YWAAtAQAGAAYJMQ5YWAAtAQAAAA==.Amboosted:BAABLgAECn8nAAIDAAgJZRs3GgDtAQADAAgJZRs3GgDtAQAAAA==.Ameretat:BAEALgAFFAIJBAABLgAFFAQJCwAHAG8TAA==.',
An='Analani:BAAALgAECgQJBgAAAA==.Anali:BAAALgAECgQJBAAAAA==.Ancient:BAAALgAECgEJAQABLgAFFAMJBQAGABsYAA==.Ancksunamun:BAAALgAECgIJAgAAAA==.Angerr:BAAALgAECgUJDQAAAA==.Angryheals:BAAALgAECgQJBAAAAA==.Anhri:BAAALgAECgEJAQAAAA==.Animalator:BAAALgAECgEJAQAAAA==.',
Aq='Aquamann:BAAALgADCgMJBAAAAA==.',
Ar='Aranel:BAAALgAECgUJBgAAAA==.Aratiri:BAAALgADCgUJBQAAAA==.Arcamancer:BAAALgADCggJFwAAAA==.Arcannia:BAAALgADCgEJAQAAAA==.Arek:BAAALgAECgYJBwABLgAFFAUJEgAIANYeAA==.Arinthal:BAAALgAECgUJCwAAAA==.Arril:BAAALgAECgYJDAAAAA==.Artemissy:BAAALgADCgUJCAAAAA==.Artorias:BAAALgAECgEJAQAAAA==.',
As='Ashed:BAAALgAECgcJCgAAAA==.Ashenskye:BAAALgADCgUJBQAAAA==.Ashlieghee:BAAALgADCgcJDAAAAA==.Ashtari:BAAALgADCgEJAQAAAA==.Astien:BAAALgAECgMJBAAAAA==.Astra:BAAALgADCgMJAwAAAA==.',
Au='Aureille:BAAALgADCgEJAgAAAA==.Aurien:BAAALgADCgMJAwAAAA==.Autoaim:BAAALgAECgYJCgAAAA==.',
Av='Avelen:BAAALgAECgEJAwAAAA==.Avha:BAAALgAECgUJCAAAAA==.Avië:BAABLgAECn8XAAIGAAYJOBaPnACcAQAGAAYJOBaPnACcAQAAAA==.',
Ax='Axel:BAABLgAECn8VAAIJAAcJvBNbWgCSAQAJAAcJvBNbWgCSAQAAAA==.',
Ay='Aylden:BAABLgAECn8fAAMKAAYJcx4LHgDPAQAKAAYJcx4LHgDPAQAJAAQJcAo3XQCQAAAAAA==.',
Az='Azenezith:BAAALgAECgQJBAAAAA==.Azio:BAAALgAECgYJDAAAAA==.Azriah:BAAALgADCggJDwAAAA==.',
Ba='Bailas:BAAALgAECgEJAQAAAA==.Bananabear:BAAALgAECggJEwABLgAFFAQJCQALAMwdAA==.Barbiesresto:BAAALgADCgUJBQAAAA==.Barra:BAAALgAECgQJBwAAAA==.Bashshield:BAEALgAFFAEJAQAAAA==.',
Bb='Bb:BAAALgAECgcJCwAAAA==.',
Be='Bearjax:BAAALgADCgkJCQABLgAFFAIJBQAMAM8iAA==.Beastm:BAAALgADCgQJBAAAAA==.Beathed:BAAALgADCggJDgAAAA==.Beaver:BAAALgADCgIJAgAAAA==.Belencina:BAAALgAECgYJBgAAAA==.Beleynn:BAABLgAECn8UAAINAAcJigaBGAAQAQANAAcJigaBGAAQAQAAAA==.Belwyn:BAAALgADCgMJAwAAAA==.Benjofamin:BAAALgAECgMJBAAAAA==.',
Bi='Bigheelz:BAAALgAECgUJBgAAAA==.Bigpuffer:BAAALgADCgMJBAAAAA==.Bitesize:BAECLgAFFH8LAAMHAAQJbxPFEQD4AAAHAAMJGxXFEQD4AAAOAAEJaw6qCgBYAAAuAAQKfyMABA4ACQnaICEMAN8BAAcABgluJEojADsCAA4ABQlXHyEMAN8BAA8AAgklEfE6AHQAAAAA.',
Bl='Blashster:BAAALgAFFAIJAgAAAA==.',
Bo='Boaw:BAAALgAECgMJBgAAAA==.Bonemilker:BAACLgAFFH8OAAMBAAQJxB1AEwBiAQABAAQJxB1AEwBiAQAQAAMJ2RxzAQC9AAAuAAQKfy8AAxAACAk3Jm4AAGwDABAACAn/JW4AAGwDAAEACAnhJS4IAF4DAAAA.Boosieboose:BAAALgAECgYJCAAAAA==.',
Br='Brackz:BAAALgAFFAIJAgAAAA==.Brandt:BAAALgADCgEJAgAAAA==.Brannwynn:BAAALgADCgEJAQAAAA==.Brewtangclan:BAAALgAECgYJEwAAAA==.Brighter:BAAALgAECgEJAQAAAA==.Broncopally:BAAALgADCgYJFQAAAA==.Brother:BAAALgADCgEJAQAAAA==.',
Bu='Bullitproof:BAAALgADCgcJDgABLgAECggJKwADALYFAA==.Bunnkost:BAAALgADCgkJGQAAAA==.Bunnyparade:BAAALgAECgIJAgAAAA==.',
Ca='Caiden:BAAALgAECgMJAwAAAA==.Calari:BAAALgAECgMJAwAAAA==.Caledwar:BAAALgAECgYJEwAAAA==.Calthirstrap:BAAALgAFFAIJAwABLgAECgkJFwAGAGIYAA==.Carapace:BAABLgAECn8eAAIHAAcJ5A4cIgAnAQAHAAcJ5A4cIgAnAQAAAA==.Carare:BAAALgADCggJDQAAAA==.Catomaze:BAAALgAECgEJAQAAAA==.',
Ce='Ceefack:BAAALgADCgYJCgAAAA==.Celestialsky:BAAALgAECgkJAQAAAA==.Cena:BAABLgAECn8dAAINAAYJ7wgYGQAJAQANAAYJ7wgYGQAJAQAAAA==.Cethin:BAAALgAECgMJBAAAAA==.',
Ch='Chaosform:BAAALgADCgkJJgABLgAECggJIwARAE0kAA==.Chaosshot:BAABLgAECn8jAAMRAAgJTSQmBgA4AwARAAgJTSQmBgA4AwASAAEJhSPZJQBoAAAAAA==.Cherylindrea:BAAALgADCgUJCwAAAA==.Chronic:BAAALgAECgYJEAAAAA==.Chènch:BAAALgADCgEJAQABLgAECgUJDwATAAAAAA==.',
Cl='Claydemon:BAAALgAECgYJDwAAAA==.Clayman:BAAALgADCgkJCQAAAA==.Claytraps:BAAALgADCgkJJQAAAA==.Clayvicar:BAABLgAECn8mAAMUAAgJDhOlIQDWAQAUAAgJDhOlIQDWAQAVAAMJYAOaVwBgAAAAAA==.',
Co='Coridane:BAAALgAECgYJEAAAAA==.Corrum:BAAALgADCgIJAgAAAA==.Corwinfiron:BAAALgAECgYJCgAAAA==.Cotreyy:BAACLgAFFH8QAAMWAAQJnyXOBQCpAQAWAAQJnyXOBQCpAQAXAAEJIyX1DwBqAAAuAAQKfycABBYACAlKJhkRAPICABYABwnkJRkRAPICABgABQk3JvYEACMCABcABAkRIhwXAJEBAAAA.',
Cr='Cristen:BAAALgADCgUJCAAAAA==.Crobat:BAAALgAECgEJAQAAAA==.',
Cu='Cumgar:BAABLgAECn8eAAIWAAcJAhO+WAC+AQAWAAcJAhO+WAC+AQAAAA==.',
Cy='Cythera:BAACLgAFFH8SAAIIAAUJ1h7yAAAjAQAIAAUJ1h7yAAAjAQAuAAQKfxwAAggACAmOI1oEANgCAAgACAmOI1oEANgCAAAA.',
['Cá']='Cámus:BAABLgAECn8VAAIDAAYJXBeqfwB7AQADAAYJXBeqfwB7AQAAAA==.',
['Cö']='Cöffee:BAAALgAECgUJEAAAAA==.',
Da='Daammy:BAAALgADCggJCQAAAA==.Dagran:BAAALgAECgQJCQABLgAECgcJFwAJALwfAA==.Dagren:BAAALgAECgYJCQAAAA==.Dankfrost:BAAALgADCgYJCwAAAA==.Daphine:BAAALgADCgUJCwAAAA==.Darimonk:BAAALgADCgMJAwAAAA==.Darkbeautie:BAAALgAECgMJBgAAAA==.Darkcarbon:BAAALgAECgYJCwAAAA==.Darmin:BAAALgAECgEJAQAAAA==.',
De='Deathmask:BAAALgADCgEJAQAAAA==.Deepmoanpaw:BAAALgAECgYJCAAAAA==.Defnotash:BAABLgAECn8kAAIZAAkJ1x27AQAyAwAZAAkJ1x27AQAyAwAAAA==.Dellinair:BAAALgADCgEJAQAAAA==.Dementedlock:BAAALgAECgcJEQAAAA==.Demontacos:BAAALgAECgEJAQAAAA==.Derodd:BAAALgAECgQJBQAAAA==.Desolend:BAAALgADCgIJAgAAAA==.Dewkiez:BAEALgAFFAIJAwAAAA==.',
Di='Diabolicarl:BAABLgAECn8bAAIKAAgJXhA2CgCbAQAKAAgJXhA2CgCbAQAAAA==.Dibsy:BAABLgAECn8lAAIaAAgJ1h4wBwAVAgAaAAgJ1h4wBwAVAgAAAA==.Diri:BAAALgADCgcJBwABLgAECgkJIQANADUVAA==.Dis:BAAALgADCggJFgABLgAFFAIJBQAEACIBAA==.Disgrace:BAABLgAECn8ZAAIPAAgJLww8DgA7AQAPAAgJLww8DgA7AQAAAA==.Dividane:BAAALgADCgYJBgAAAA==.',
Dm='Dmossyoak:BAAALgADCgkJAgAAAA==.',
Do='Donniedipes:BAABLgAECn8bAAIBAAgJWw4sQgA4AQABAAgJWw4sQgA4AQAAAA==.Dookiez:BAEBLgAECn8ZAAIIAAgJnSNoAgAmAwAIAAgJnSNoAgAmAwABLgAFFAIJAwATAAAAAA==.Doublade:BAAALgAECgcJBwAAAA==.Doubledragin:BAABLgAECn8aAAMbAAYJARmKFQBTAQAbAAYJARmKFQBTAQAcAAMJ6gKONgBiAAAAAA==.',
Dr='Dracantar:BAAALgADCgUJBQAAAA==.Dracotako:BAAALgAECgYJCgAAAA==.Dractini:BAABLgAECn8WAAMdAAgJvQrEJABSAQAdAAcJXAvEJABSAQAbAAcJeggBMgA4AQAAAA==.Draeneiamin:BAAALgADCgMJAwABLgAECgMJBAATAAAAAA==.Dragfan:BAAALgAECgIJAgAAAA==.Dragonsniper:BAAALgAECgQJCAAAAA==.Dragore:BAABLgAECn8ZAAIHAAYJthuzNwDIAQAHAAYJthuzNwDIAQAAAA==.Druidgirls:BAACLgAFFH8FAAIEAAMJZBGTGADTAAAEAAMJZBGTGADTAAAuAAQKfygAAgQACQncGMoqAAYCAAQACQncGMoqAAYCAAAA.Dràugluin:BAAALgAFFAEJAQAAAA==.',
Du='Duasoras:BAABLgAECn8cAAIeAAgJ8QRAWwAdAQAeAAgJ8QRAWwAdAQAAAA==.Duelist:BAAALgADCgUJBQAAAA==.Dundlen:BAAALgADCggJDwABLgAECggJHwAfADYdAA==.Dunvel:BAAALgAECgMJAwAAAA==.Durogdem:BAAALgAECgIJBAAAAA==.',
Dy='Dynamite:BAAALgAECgEJAgAAAA==.',
Ea='Earthaggie:BAAALgADCgUJCwAAAA==.',
Ed='Edea:BAAALgAECgEJAQAAAA==.',
El='Elaelta:BAAALgAECgMJCQAAAA==.Eleetmage:BAAALgAECgEJAQAAAA==.Elenora:BAABLgAECn8qAAIFAAcJkwQdJQDZAAAFAAcJkwQdJQDZAAAAAA==.Elesity:BAAALgADCgEJAQABLgAFFAQJCwATAAAAAA==.Elye:BAAALgAECgMJAwABLgAECgYJEwATAAAAAA==.',
Em='Emer:BAACLgAFFH8FAAMEAAIJIgFZLwBOAAAEAAIJIgFZLwBOAAAFAAEJTAAkHgApAAAuAAQKfyAAAwUACAk0Cvk6AEkBAAUABwmfC/k6AEkBAAQABwl/BHuPALIAAAAA.',
En='Encore:BAABLgAECn8kAAIEAAgJxA2fJgBRAQAEAAgJxA2fJgBRAQAAAA==.',
Eo='Eousphorus:BAACLgAFFH8JAAIGAAQJkhcVGQBjAQAGAAQJkhcVGQBjAQAuAAQKfx4AAgYACAnRHv00AJ8CAAYACAnRHv00AJ8CAAAA.',
Er='Erathen:BAAALgAECgUJBAAAAA==.Eridi:BAAALgADCgEJAQAAAA==.Eroenice:BAAALgAECgQJBAAAAA==.',
Et='Etile:BAAALgADCgkJFgAAAA==.',
Ev='Evelleion:BAAALgAECgUJDQAAAA==.',
Ex='Exoticlord:BAABLgAECn8VAAMRAAcJYBOsQQBQAQARAAYJ5xCsQQBQAQAgAAcJABIYbgB5AAAAAA==.',
Fa='Failagos:BAAALgADCgMJAwAAAA==.Fallujah:BAAALgADCgUJBQAAAA==.',
Fe='Felicene:BAABLgAECn8fAAIhAAcJrCH5AgAqAgAhAAcJrCH5AgAqAgAAAA==.Fellynn:BAACLgAFFH8FAAIMAAIJzyK6AgDNAAAMAAIJzyK6AgDNAAAuAAQKfyYAAgwACAmjJZ8AAFsDAAwACAmjJZ8AAFsDAAAA.',
Fi='Fieperskaivu:BAABLgAECn8XAAMJAAcJvB8TIgCFAgAJAAcJvB8TIgCFAgAKAAUJMRqbNQAxAQAAAA==.Fierygrace:BAAALgADCgYJBgAAAA==.Firefalco:BAAALgADCggJCQAAAA==.',
Fl='Flameth:BAABLgAECn8aAAIWAAgJgwuPOgBEAQAWAAgJgwuPOgBEAQAAAA==.Flamingbunz:BAAALgAECgIJAgAAAA==.Flashblood:BAABLgAECn8lAAMHAAgJZSXTEADKAgAHAAgJZCXTEADKAgAOAAMJ8SKMGAA0AQAAAA==.Flashers:BAAALgAECggJBwAAAA==.Flavortown:BAAALgAECgEJAQAAAA==.',
Fo='Forgiven:BAABLgAECn8VAAIDAAcJqBrIVADjAQADAAcJqBrIVADjAQAAAA==.Foxtrót:BAAALgAECgYJDQABLgAECggJIgAPAKYgAA==.',
Fr='Freeb:BAAALgADCgYJDgABLgAECggJKwADALYFAA==.Freebzz:BAAALgADCgQJBwABLgAECggJKwADALYFAA==.Freezrorburn:BAAALgAECgQJBgAAAA==.Frostyndikit:BAAALgAECgMJAwAAAA==.',
Fu='Fu:BAAALgADCgUJBQAAAA==.Fumanchu:BAABLgAECn8iAAIPAAgJpiDDAwBGAgAPAAgJpiDDAwBGAgAAAA==.',
Ga='Gaamora:BAAALgADCgUJCwAAAA==.Gainsborough:BAAALgAECgYJBQAAAA==.Galadore:BAAALgADCgIJAwAAAA==.Garagos:BAACLgAFFH8FAAIiAAIJYhfOAwC6AAAiAAIJYhfOAwC6AAAuAAQKfyYAAiIACAknHV0CAAMCACIACAknHV0CAAMCAAAA.Gatherina:BAAALgAECgQJBgABLgAECgcJFwAJALwfAA==.',
Ge='Gebuss:BAABLgAECn8VAAIiAAcJLSWuAgDCAgAiAAcJLSWuAgDCAgAAAA==.Gempally:BAAALgADCgMJBgAAAA==.Genzo:BAAALgADCgkJDQAAAA==.',
Gh='Ghorynv:BAAALgAECgYJBgAAAA==.',
Gi='Giah:BAAALgADCgkJGwAAAA==.Giborim:BAAALgADCgEJAQAAAA==.Gigapriest:BAAALgAECgYJBgAAAA==.Gilford:BAAALgADCgUJBQAAAA==.',
Gl='Glavela:BAAALgAECgQJCQAAAA==.Gloomfist:BAAALgAECgYJEwAAAQ==.',
Go='Goochaddi:BAAALgADCgMJAwABLgAECgUJBQATAAAAAA==.',
Gr='Graven:BAAALgAECgYJBgAAAA==.Graveside:BAAALgADCgQJBAAAAA==.Grizzlock:BAAALgADCgMJAwAAAA==.',
Gu='Gulivar:BAAALgAECgUJDwABLgAECgUJDwATAAAAAA==.',
Ha='Halfrican:BAAALgAECgQJBAAAAA==.Halifaxx:BAABLgAECn8fAAMfAAgJNh3FAAAoAgAfAAgJihzFAAAoAgAGAAUJZBOfYgAWAQAAAA==.Harambee:BAAALgAECgEJAQABLgAFFAEJAQATAAAAAA==.Hariasa:BAAALgAECgMJAwAAAA==.Harmaa:BAAALgAECgYJDQAAAA==.Hawknor:BAAALgAECgYJDQAAAA==.',
He='Healenya:BAAALgAECgcJBwAAAA==.Healthcare:BAAALgAECgcJDwABLgAECggJFgAdAL0KAA==.Healywilly:BAAALgADCggJFAAAAA==.Herm:BAACLgAFFH8FAAIaAAIJ6iR2DADbAAAaAAIJ6iR2DADbAAAuAAQKfyYAAhoACAlEI48HAAMDABoACAlEI48HAAMDAAAA.',
Hi='Highbear:BAAALgAECgMJBAAAAA==.Hiryu:BAAALgADCgYJBgAAAA==.',
Ho='Holyfaxx:BAAALgADCgcJBwAAAA==.Holymidget:BAAALgADCggJDQAAAA==.Holysky:BAAALgAECgQJBgAAAA==.Holysmokes:BAAALgAECgIJAgAAAA==.Holytim:BAABLgAECn8hAAMjAAgJDxjTJQBmAQAjAAgJcBbTJQBmAQAUAAYJ4RC/RAAmAQAAAA==.Honnik:BAABLgAECn8hAAIiAAkJbhEWBAB0AgAiAAkJbhEWBAB0AgAAAA==.Hortance:BAAALgAECgcJBwAAAA==.Hothot:BAAALgAECgQJBQAAAA==.Hotsndots:BAAALgAECgEJAQAAAA==.Houndoom:BAABLgAECn8kAAIkAAgJXBSEDgCmAQAkAAgJXBSEDgCmAQAAAA==.How:BAABLgAECn8cAAMlAAgJDB2yDQB5AgAlAAgJDB2yDQB5AgAaAAEJBwgGgQAvAAAAAA==.',
Hu='Hugspotato:BAAALgADCggJCAAAAA==.Huyrak:BAAALgADCgUJBQAAAA==.',
Hy='Hypoxic:BAAALgAECgYJEAAAAA==.',
Ia='Iah:BAACLgAFFH8FAAIIAAIJygAyBQBwAAAIAAIJygAyBQBwAAAuAAQKfyIAAggACAmTCuwPALkBAAgACAmTCuwPALkBAAAA.',
Ic='Icastspells:BAAALgADCggJDAAAAA==.Icyveinuser:BAAALgADCgcJIgAAAA==.',
Ig='Ignored:BAABLgAECn8XAAMDAAgJwBXXMAB/AQADAAgJwBXXMAB/AQAmAAEJoAEjWwAZAAAAAA==.',
Il='Illidæn:BAABLgAECn8ZAAIJAAgJXhF5IQBqAQAJAAgJXhF5IQBqAQAAAA==.Illistra:BAAALgADCgYJBgABLgAECgcJDQATAAAAAA==.',
Im='Impuratus:BAAALgAECgMJBAAAAA==.',
In='Inq:BAAALgAECgYJEgAAAA==.',
Ir='Iridaceaë:BAABLgAECn8kAAMUAAgJjRU9DQDQAQAUAAgJjRU9DQDQAQAjAAMJHginRQCMAAABLgAECggJJgAlANohAA==.Ironpaw:BAAALgAECgYJDAAAAA==.Iryris:BAAALgAECgYJDwAAAA==.',
Is='Isedeath:BAACLgAFFH8FAAMBAAIJ2BHFVAChAAABAAIJ2BHFVAChAAAQAAEJtARUBwBLAAAuAAQKfycABAEACAlRHKAwAHUCAAEACAlRHKAwAHUCABAAAQnYFqYOAEwAACcAAgliAGhBAEYAAAAA.',
Ja='Jabber:BAAALgAECgQJBAAAAA==.Jabul:BAAALgADCgYJBgAAAA==.Jack:BAABLgAECn8ZAAMWAAcJXCP1SQDsAQAWAAUJBSP1SQDsAQAXAAIJDiVCFgBrAAAAAA==.Jaegerr:BAAALgAECggJEgAAAA==.Jalene:BAAALgADCgcJAwAAAA==.Jamonk:BAAALgADCgYJBwABLgADCggJCAATAAAAAA==.Jamuul:BAAALgADCggJCAAAAA==.Janton:BAABLgAECn8XAAIHAAgJBAeaGgBaAQAHAAgJBAeaGgBaAQAAAA==.Jarrhead:BAAALgAECgQJCAAAAA==.Jastor:BAAALgADCgcJDgAAAA==.',
Je='Jenaveive:BAAALgAECgQJBAAAAA==.Jethli:BAACLgAFFH8PAAIkAAQJzQ9fDwAbAQAkAAQJzQ9fDwAbAQAuAAQKfyAAAiQACAmNGScaAC4BACQACAmNGScaAC4BAAAA.',
Ji='Jigopocalyps:BAAALgADCgEJAQAAAA==.Jinn:BAAALgADCgYJBAAAAA==.',
Jj='Jjp:BAAALgADCgYJCQAAAA==.',
Jn='Jnex:BAAALgAECgEJAQAAAA==.',
Jo='Jojobeànfire:BAAALgADCgYJCwAAAA==.Joube:BAAALgAECggJEgAAAA==.',
Ju='Judgepain:BAAALgAECgEJBAAAAA==.Judgmental:BAABLgAECn8UAAMmAAgJ+A5iEgDIAQAmAAgJ+A5iEgDIAQADAAUJWgI4mQByAAAAAA==.Juicytootsie:BAABLgAECn8UAAIGAAYJdwNoBwHtAAAGAAYJdwNoBwHtAAAAAA==.Justifried:BAAALgAECgQJBAAAAA==.',
['Jä']='Jävel:BAAALgAECgYJCAAAAA==.',
Ka='Kaelysong:BAAALgAECgEJAgAAAA==.Kairah:BAAALgAECgIJAgAAAA==.Kairiandel:BAAALgAECgEJAQAAAA==.Kalï:BAAALgAECggJEQAAAA==.Karaha:BAAALgADCgcJBwAAAA==.Kayllin:BAAALgADCgYJDAAAAA==.Kaysina:BAAALgADCgUJBQAAAA==.',
Ke='Keener:BAAALgAECgUJEAAAAA==.Kelenil:BAAALgAECgEJAQABLgAECgQJBAATAAAAAA==.Kerrla:BAACLgAFFH8OAAIFAAQJqhheBwBZAQAFAAQJqhheBwBZAQAuAAQKfycAAgUACAngI54JAPsCAAUACAngI54JAPsCAAEuAAMKAQkBABMAAAAA.Keylleth:BAAALgAECgYJCwAAAA==.',
Kh='Khamari:BAAALgADCgYJBgABLgAECgUJCgATAAAAAA==.Khamnox:BAAALgAECgUJCgAAAA==.Khlamps:BAAALgADCgUJBQAAAA==.',
Ki='Kielnmsoftly:BAAALgAECgkJDQAAAA==.Kilaia:BAAALgAECgYJDAAAAA==.Kilda:BAAALgADCgcJBwAAAA==.Killerklown:BAAALgAECgUJCAAAAA==.Kirksñiper:BAAALgAECgYJDgAAAA==.Kirru:BAABLgAECn8ZAAMUAAcJbw5CTQADAQAUAAcJbw5CTQADAQAjAAMJXAG8TQBbAAAAAA==.Kirsty:BAAALgADCgMJAwAAAA==.',
Kl='Klink:BAAALgAECgUJDwAAAA==.',
Kn='Knoble:BAAALgAECgQJBgAAAA==.',
Kr='Kraisee:BAAALgADCgEJAQAAAA==.Kreatan:BAAALgADCgUJBwAAAA==.Kreaton:BAAALgAECggJDwAAAA==.Krel:BAAALgAECgEJAQAAAA==.Kryntoo:BAAALgADCggJCAAAAA==.',
Ks='Kshatriya:BAAALgADCgQJBAAAAA==.',
Ku='Kuchikix:BAAALgADCgEJAQAAAA==.Kuchíki:BAABLgAECn8YAAIlAAcJTQ6DGwAmAQAlAAcJTQ6DGwAmAQAAAA==.Kushynuggles:BAAALgADCgEJAQAAAA==.',
Kw='Kwag:BAAALgAECgcJBgAAAA==.',
La='Laaklem:BAAALgADCgkJHgAAAA==.Laei:BAAALgAECggJEAAAAA==.Lagerthaa:BAAALgADCgIJAgAAAA==.Laserfingies:BAAALgAECgUJBQAAAA==.Lastsun:BAAALgAECgYJDAAAAA==.Lauridana:BAAALgADCgEJAQAAAA==.Lavacakes:BAACLgAFFH8FAAIeAAIJYSYiFQDiAAAeAAIJYSYiFQDiAAAuAAQKfyQAAh4ACAnZJL4DADoDAB4ACAnZJL4DADoDAAAA.Lazaren:BAAALgADCgMJAwAAAA==.Lazyboy:BAABLgAECn8ZAAIHAAcJpR4DHABtAgAHAAcJpR4DHABtAgAAAA==.',
Le='Lelantoz:BAABLgAECn8ZAAIgAAYJkQkaQgAOAQAgAAYJkQkaQgAOAQAAAA==.Leliel:BAAALgADCgEJAQAAAA==.Lenailla:BAAALgADCgkJCQAAAA==.Lezibean:BAAALgADCgcJBwABLgADCggJCAATAAAAAA==.',
Li='Lidan:BAABLgAECn8VAAIiAAcJSQtjCAAVAQAiAAcJSQtjCAAVAQAAAA==.Liebli:BAAALgAECgQJBAAAAA==.Liffry:BAAALgADCgEJAQAAAA==.Lilena:BAAALgADCgkJLQAAAA==.Lilnao:BAAALgAECgcJCAAAAA==.Linaeni:BAAALgAECgQJBAAAAA==.Linaradice:BAAALgAECgcJBwAAAA==.Linkinbiox:BAAALgAECgUJCgAAAA==.',
Lo='Lockedown:BAAALgADCgkJCQAAAA==.Logyn:BAAALgAECgEJAQAAAA==.Lore:BAABLgAECn8cAAIGAAgJ1RGHQwBkAQAGAAgJ1RGHQwBkAQAAAA==.Lotsalock:BAAALgADCgcJCAAAAA==.',
Lu='Lululemons:BAAALgAECgMJBAAAAA==.',
Ly='Lyphysia:BAAALgAECgcJDQAAAA==.Lyrelia:BAAALgAECgYJDQAAAA==.Lyssiarose:BAAALgAECgYJDgAAAA==.',
Ma='Mack:BAAALgADCgEJAQAAAA==.Madbones:BAABLgAECn8XAAMWAAcJCRY5JwCSAQAWAAcJTxM5JwCSAQAYAAMJXxqLEwD2AAAAAA==.Mado:BAAALgAECggJDQAAAA==.Maeveracy:BAAALgADCgUJBQAAAA==.Mageijuana:BAABLgAECn8XAAIGAAcJ3x4PLQCvAQAGAAcJ3x4PLQCvAQAAAA==.Magicky:BAAALgAECgYJEgAAAA==.Magicsauce:BAAALgAECgYJBwAAAA==.Mahlkier:BAAALgADCgUJCwAAAA==.Maikego:BAAALgAECgMJAwAAAA==.Malchelo:BAAALgAECgcJDQAAAA==.Malfhunter:BAACLgAFFH8FAAIRAAMJ9gnjCQDeAAARAAMJ9gnjCQDeAAAuAAQKfyoAAhEACQl3GUkTAJgCABEACQl3GUkTAJgCAAAA.Maligosa:BAAALgADCgUJBQAAAA==.Manabender:BAAALgAECgIJAgAAAA==.Mangolassi:BAAALgADCgEJAQAAAA==.Manofwood:BAABLgAFFH8GAAIoAAQJ7xC/AgAVAQAoAAQJ7xC/AgAVAQAAAA==.Mantodea:BAAALgAECgEJAQAAAA==.Manus:BAAALgAECgMJBQAAAA==.Maranatha:BAAALgADCgEJAQAAAA==.Marossa:BAAALgADCgMJAwAAAA==.Marymae:BAAALgADCgUJCwAAAA==.Masskiller:BAAALgADCgIJAgAAAA==.Masumi:BAAALgADCgEJAQAAAA==.Mattikus:BAAALgAECgQJBAAAAA==.Maximilion:BAAALgAECgMJBAAAAA==.',
Me='Megrim:BAAALgADCgIJAwAAAA==.Mehrartz:BAAALgADCgYJCwAAAA==.Melyn:BAAALgADCgIJAgAAAA==.Merdocki:BAACLgAFFH8FAAIWAAIJ9Be6PgCrAAAWAAIJ9Be6PgCrAAAuAAQKfyYAAxcACAnhIcIPANIBABcABQk6H8IPANIBABYABQlgITogALMBAAAA.Merdra:BAAALgADCgcJBwAAAA==.Merdre:BAACLgAFFH8FAAMUAAIJbBWDDwCaAAAUAAIJbBWDDwCaAAAVAAEJVwB3GwAuAAAuAAQKfykAAxQACAlMHJQOAHUCABQACAlMHJQOAHUCABUABQkAAgZLAK0AAAAA.Mertele:BAAALgADCggJFwAAAA==.Messörem:BAAALgADCgYJBgAAAA==.Metasavage:BAAALgAECgQJBAABLgAECgUJBQATAAAAAA==.',
Mi='Michealhunt:BAAALgAECgUJBgAAAA==.Midory:BAAALgAECgEJAQAAAA==.Mikimukka:BAAALgADCgIJAwAAAA==.Milim:BAAALgAECgQJBQABLgAECgUJBQATAAAAAA==.Milkymocha:BAABLgAECn8ZAAIZAAcJ0xeLFgBrAQAZAAcJ0xeLFgBrAQAAAA==.Minus:BAAALgADCgMJAwAAAA==.Misfitjoker:BAAALgAECgEJAQAAAA==.Misscorona:BAAALgADCgQJBgAAAA==.Mistyque:BAAALgAECgQJCgAAAA==.Mithrond:BAAALgADCggJCgABLgAECgEJAQATAAAAAA==.',
Mo='Modercai:BAAALgAECgMJAwAAAA==.Morcant:BAAALgAECgYJCwAAAA==.Morhg:BAABLgAECn8gAAMXAAcJxgiiCQANAQAXAAcJEgiiCQANAQAWAAYJfgdGaQC8AAAAAA==.Morianoley:BAAALgADCggJEQAAAA==.Morlu:BAABLgAECn8WAAIHAAYJUSIXIQBKAgAHAAYJUSIXIQBKAgAAAA==.',
Ms='Msdonnapally:BAAALgAECgUJCQAAAA==.',
Mu='Mugnar:BAAALgADCgcJBwAAAA==.',
My='Myn:BAAALgAECgQJBAAAAA==.',
Na='Nadirya:BAEALgAECgcJCQABLgAFFAQJCwAHAG8TAA==.Nazkrul:BAAALgADCgMJAwAAAA==.',
Ne='Nellykorda:BAAALgAECgMJBQAAAA==.Neodruid:BAAALgAECgYJDwAAAA==.Nexxicus:BAAALgADCgMJAwAAAA==.',
Ni='Nightlywomen:BAAALgADCgcJDAAAAA==.Nightmehr:BAACLgAFFH8FAAIGAAMJGxh5LwAMAQAGAAMJGxh5LwAMAQAuAAQKfyIAAgYACQkcI30QAEUDAAYACQkcI30QAEUDAAAA.Nightphaze:BAAALgAECgEJAQAAAA==.Nihm:BAAALgADCgYJCgAAAA==.Nikolatte:BAAALgAECgEJAwAAAA==.Nimda:BAABLgAECn8aAAIBAAgJfiFnGwDZAgABAAgJfiFnGwDZAgAAAA==.',
No='Nosaj:BAAALgADCgkJCwAAAA==.',
Nu='Nullex:BAABLgAECn8ZAAQJAAcJnRYANwAHAQAJAAYJKRkANwAHAQAKAAEJ4wmjMgA1AAAMAAEJYAiiGwAeAAAAAA==.',
Ny='Nyki:BAAALgADCgMJAwAAAA==.',
Ob='Oberon:BAAALgADCgYJBgAAAA==.',
Od='Odlaw:BAAALgAECgcJEwAAAA==.',
Ol='Olaria:BAAALgAECgMJAwABLgAECgYJEwATAAAAAA==.Oldsaggins:BAAALgAECgUJCAAAAA==.Olikel:BAAALgADCgEJAQAAAA==.Ollymay:BAAALgAECgYJBgAAAA==.Olm:BAAALgAECgUJBQAAAA==.',
On='Onedruidtion:BAAALgAECgEJAQAAAA==.',
Op='Ophekins:BAAALgADCgcJCwAAAA==.',
Or='Orcman:BAAALgAECgEJAQAAAA==.Orheo:BAAALgADCgQJBAAAAA==.Originalchip:BAAALgAECgMJBwAAAA==.Orionmoon:BAAALgAECgcJCAAAAA==.Orlos:BAAALgAECgYJEwAAAA==.Oräkk:BAACLgAFFH8FAAIPAAMJ3RhLBwDuAAAPAAMJ3RhLBwDuAAAuAAQKfxUAAg8ABwkUHU0NADYCAA8ABwkUHU0NADYCAAAA.',
Os='Osrs:BAAALgAECgMJAwAAAA==.',
Ox='Oxelmorphs:BAAALgADCgcJCAAAAA==.',
Pa='Padrin:BAABLgAECn8VAAMRAAYJew/LUQAFAQARAAUJMA3LUQAFAQAgAAYJ3g2FWgC6AAAAAA==.Palehorsemen:BAAALgAECgUJCwAAAA==.Pandaberry:BAAALgAECgYJBwAAAA==.Pandapaws:BAACLgAFFH8HAAIeAAMJ1BKTFwDPAAAeAAMJ1BKTFwDPAAAuAAQKfyIAAh4ACQk1HyUMAL8CAB4ACQk1HyUMAL8CAAAA.Papawaas:BAAALgADCgMJAwAAAA==.Parthal:BAAALgAECgYJDQAAAA==.Partylock:BAAALgAECgMJAwABLgAECggJDgATAAAAAA==.Partyshooter:BAAALgAECggJDgAAAA==.Patmage:BAABLgAECn8eAAIGAAgJfRd5JADWAQAGAAgJfRd5JADWAQAAAA==.',
Pd='Pdiddi:BAABLgAECn8cAAMBAAgJtB/sDgBJAgABAAgJ+BvsDgBJAgAQAAYJqCD3BAD6AQAAAA==.',
Pe='Peed:BAAALgAECgYJEgAAAA==.Pellaeon:BAABLgAECn8VAAIBAAkJ2BiHSQAWAgABAAkJ2BiHSQAWAgAAAA==.',
Ph='Phexia:BAAALgAECgUJCAAAAA==.Phrostir:BAAALgAECgkJDAAAAA==.Phylactery:BAABLgAECn8lAAIBAAgJCRp4PQBCAgABAAgJCRp4PQBCAgAAAA==.',
Pi='Pierre:BAACLgAFFH8QAAIgAAQJVRSiBQBJAQAgAAQJVRSiBQBJAQAuAAQKfyUABCAACAmdIt8RAKkCACAACAnGId8RAKkCABIABQn9G5cQAFYBABEABgnpDWxOABYBAAAA.Pillgrimm:BAABLgAECn8UAAIRAAcJRhCNCgAnAQARAAcJRhCNCgAnAQAAAA==.Pirotic:BAAALgADCgcJCwAAAA==.',
Po='Poisson:BAABLgAECn8hAAINAAkJNRWEEQCUAgANAAkJNRWEEQCUAgAAAA==.Polishdir:BAAALgAECgYJEAAAAA==.Polishduo:BAAALgAFFAEJAQAAAA==.Porzingus:BAAALgADCgcJBwAAAA==.Poxi:BAABLgAECn8WAAIbAAgJDReyEwBHAgAbAAgJDReyEwBHAgAAAA==.',
Pr='Praesidiel:BAAALgAECgcJEwAAAA==.Providence:BAACLgAFFH8FAAIKAAMJig/mBgD7AAAKAAMJig/mBgD7AAAuAAQKfygAAgoACQkSI+YBAH4DAAoACQkSI+YBAH4DAAAA.Prsr:BAAALgAECgMJAwABLgAFFAQJDgABAMQdAA==.',
Pu='Pudgypaws:BAAALgAECgYJCgAAAA==.Puffed:BAAALgAECgIJAgABLgAFFAIJBQAUAGwVAA==.Punchkick:BAAALgAECgUJBwAAAA==.Purfukt:BAAALgAECgYJBgAAAA==.',
['På']='Pån:BAAALgAECgEJAQAAAA==.',
['Pè']='Pèwpéw:BAAALgAECgUJCQAAAA==.',
Qu='Quickmend:BAAALgAECgQJBgAAAA==.Quickpal:BAAALgAECgUJBwAAAA==.Quickpaw:BAACLgAFFH8FAAIlAAMJHBebDwDeAAAlAAMJHBebDwDeAAAuAAQKfyYAAiUACQkOIxgDAE0DACUACQkOIxgDAE0DAAAA.Quickshot:BAAALgADCgEJAQAAAA==.',
Ra='Raani:BAAALgADCgcJBwAAAA==.Raccoons:BAACLgAFFH8SAAIgAAUJWRvmAgBuAQAgAAUJWRvmAgBuAQAuAAQKfx0AAyAACAm6IHUbAGICACAACAm6IHUbAGICABEAAwkrCddrAI4AAAAA.Rageproof:BAABLgAECn8rAAIDAAgJtgWhSwAoAQADAAgJtgWhSwAoAQAAAA==.Ragged:BAABLgAECn8XAAIBAAgJ9SEUCACcAgABAAgJ9SEUCACcAgAAAA==.Raidbloom:BAACLgAFFH8KAAIEAAMJhiA7DAAfAQAEAAMJhiA7DAAfAQAuAAQKfxoAAgQACAnSI0kGACcDAAQACAnSI0kGACcDAAAA.Raidheal:BAAALgADCgcJBwABLgAFFAMJCgAEAIYgAA==.Rainsinger:BAAALgADCgkJBgAAAA==.Rakroth:BAAALgAECgYJDwAAAA==.Ramook:BAAALgADCgcJDQAAAA==.Randomchar:BAABLgAECn8jAAIDAAgJ9wqaQwA/AQADAAgJ9wqaQwA/AQAAAA==.Rankor:BAAALgAECgYJEAABLgAECggJJwABAIwdAA==.Rastann:BAACLgAFFH8FAAIDAAMJhhPxHQD+AAADAAMJhhPxHQD+AAAuAAQKfyUAAgMACQlWIgcOAB4DAAMACQlWIgcOAB4DAAAA.Ratrun:BAAALgAECgEJAQAAAA==.Raycharles:BAAALgAECgYJAQAAAA==.',
Re='Realir:BAAALgAECgcJDgAAAA==.Reapertoo:BAACLgAFFH8SAAIBAAUJ2iQVBgCuAQABAAUJ2iQVBgCuAQAuAAQKfygAAwEACQkrI4QHAGQDAAEACQkrI4QHAGQDABAAAQlmGaAWADYAAAAA.Recreant:BAAALgADCgYJAQAAAA==.Redbaron:BAABLgAECn8gAAIKAAkJ+BJzBgD7AQAKAAkJ+BJzBgD7AQAAAA==.Regeth:BAAALgAECgcJEwAAAA==.Repyns:BAACLgAFFH8cAAQWAAcJeh1bAwDuAQAWAAYJbB5bAwDuAQAXAAQJDBy3BQAWAQAYAAEJAADIBgBPAAAuAAQKfx4ABBYACQnwJcIIADsDABYACAnwJcIIADsDABcAAwnzIoIpABwBABgAAwlrH4cRABUBAAAA.Rethul:BAABLgAECn8YAAMbAAcJNhDtNwAXAQAbAAYJ2Q/tNwAXAQAdAAYJQASxNADHAAAAAA==.Retsü:BAAALgAECggJDwABLgAECggJFgAdAL0KAA==.',
Rh='Rhhonn:BAAALgAECgYJBgAAAA==.Rhollor:BAAALgAECgMJAwAAAA==.',
Ri='Ridic:BAABLgAECn8nAAIBAAgJjB1uGAD4AQABAAgJjB1uGAD4AQAAAA==.Rimeblade:BAAALgAECgEJAQAAAA==.',
Ro='Robutinblue:BAACLgAFFH8IAAIGAAQJjBfzFwBmAQAGAAQJjBfzFwBmAQAuAAQKfxkAAgYACAkvH1slAN0CAAYACAkvH1slAN0CAAAA.Rocklesnar:BAAALgAECgMJAwAAAA==.Rondle:BAAALgAECgIJBAAAAA==.Rozalin:BAACLgAFFH8FAAIGAAIJgRWLQwC2AAAGAAIJgRWLQwC2AAAuAAQKfyYAAgYACAm0JegKAG0DAAYACAm0JegKAG0DAAAA.Rozalinamoon:BAAALgAECgIJAgAAAA==.',
Ru='Ruffprophet:BAAALgAECgEJAQAAAA==.Rugelach:BAEALgAECgEJAQAAAA==.Rumi:BAABLgAECn8YAAIMAAcJ0hTjEQAzAQAMAAcJ0hTjEQAzAQAAAA==.Rurouni:BAAALgADCgcJBwAAAA==.',
Ry='Ryoshi:BAACLgAFFH8FAAISAAIJ8xiEDgCvAAASAAIJ8xiEDgCvAAAuAAQKfysAAhIACAkPICIDAP0CABIACAkPICIDAP0CAAAA.',
Sa='Sabotender:BAAALgADCgkJEAAAAA==.Sacredragon:BAAALgAECgUJBQAAAA==.Sacredswords:BAACLgAFFH8IAAMHAAQJ1Q31CQBGAQAHAAQJ1Q31CQBGAQAOAAEJnwMuDQBLAAAuAAQKfxkAAgcACAkiHvkVAJ0CAAcACAkiHvkVAJ0CAAAA.Saeys:BAAALgADCgMJAwAAAA==.Sandalis:BAAALgADCgQJBAABLgAECggJHQADAFsVAA==.Sandscale:BAAALgADCggJCAAAAA==.Sannctuary:BAAALgAECgYJEAAAAA==.Sapphiremist:BAAALgAECgUJCwAAAA==.Sauerkraut:BAAALgAECgcJAQAAAA==.Savagesin:BAAALgAFFAIJAgABLgAECgUJBQATAAAAAA==.Sayen:BAAALgADCgkJCQAAAA==.',
Sc='Scachity:BAABLgAECn8XAAMXAAYJ4BmuBACKAQAXAAYJ4BmuBACKAQAWAAMJxAnRgQB4AAAAAA==.Scarekroe:BAABLgAECn8fAAMaAAgJ7hsmBgAtAgAaAAgJ7hsmBgAtAgAkAAEJixR7iQAzAAAAAA==.Schein:BAAALgADCgUJCAAAAA==.Scratchers:BAABLgAECn8eAAIFAAgJ4iLMBgArAwAFAAgJ4iLMBgArAwAAAA==.',
Se='Seelina:BAAALgADCgYJBgAAAA==.Selanni:BAAALgADCgcJCAAAAA==.Sepulchre:BAAALgADCgkJEgAAAA==.Serlotte:BAAALgADCgcJEQAAAA==.',
Sh='Shadowish:BAAALgADCgEJAQAAAA==.Shadunx:BAAALgADCgIJAgABLgAECgMJAwATAAAAAA==.Shamaroo:BAAALgAECgUJBQAAAA==.Shaundakul:BAAALgADCgkJLwAAAA==.Shephion:BAAALgAECgEJAQABLgAFFAIJBQAaAOokAA==.Shiddydeps:BAAALgADCgYJCAAAAA==.Shiee:BAAALgADCgEJAQAAAA==.Shortnstack:BAAALgAECgUJDAAAAA==.Shãdow:BAAALgAECgYJCAAAAA==.',
Si='Sidetracked:BAABLgAECn8dAAIGAAgJuBg2HwDxAQAGAAgJuBg2HwDxAQAAAA==.Silanah:BAACLgAFFH8FAAIkAAIJ8BnPHgCkAAAkAAIJ8BnPHgCkAAAuAAQKfyYAAiQACAnZG+cJAO0BACQACAnZG+cJAO0BAAAA.Silverheart:BAAALgAECgcJDQAAAA==.Silvershade:BAAALgADCgEJAQAAAA==.',
Sk='Skawalker:BAACLgAFFH8FAAMhAAMJVQn9BQCXAAAhAAIJOwb9BQCXAAAEAAIJNBSFIwCOAAAuAAQKfyQAAwQACQlJI/wFAC0DAAQACQlJI/wFAC0DACEABAnCD44RAMAAAAAA.Skyleebaby:BAAALgADCgcJBwAAAA==.',
Sl='Slashers:BAAALgADCgkJCQABLgAECggJHgAFAOIiAA==.Slaynne:BAACLgAFFH8FAAIHAAIJrBKMHACXAAAHAAIJrBKMHACXAAAuAAQKfyYAAwcACAlxJIAIACQDAAcACAlxJIAIACQDAA4AAQm9CEZEADAAAAAA.Sleven:BAAALgAECgUJBwABLgAFFAEJAQATAAAAAA==.Slowfel:BAAALgADCgcJBwAAAA==.',
Sm='Smábes:BAAALgAECgQJBwAAAA==.Smäug:BAACLgAFFH8QAAMbAAYJ1hnLBACuAQAbAAUJ1hnLBACuAQAcAAEJAACfBwB1AAAuAAQKfyAABBwACAlJJNsEALUCABwABwlbI9sEALUCABsABAlcI9YkAJYBAB0ABwkcBaUmAEABAAAA.',
Sn='Snobaws:BAAALgAECgcJDQAAAA==.',
So='Sockz:BAABLgAECn8bAAINAAgJfBm3FABtAgANAAgJfBm3FABtAgAAAA==.Solria:BAABLgAECn8dAAIUAAgJghWiDADaAQAUAAgJghWiDADaAQAAAA==.Solrosenborg:BAABLgAECn8lAAIBAAgJjR8HCwB0AgABAAgJjR8HCwB0AgAAAA==.Solrosenburg:BAAALgAECgcJEgABLgAECggJJQABAI0fAA==.Sondreman:BAAALgAECggJEgAAAA==.Sorcereo:BAAALgADCgIJBQAAAA==.',
Sp='Spicychip:BAAALgADCgUJBQAAAA==.Spintwowin:BAAALgADCgUJBQAAAA==.Splashers:BAAALgADCgQJBAAAAA==.Spærkle:BAAALgAECgUJBgAAAA==.',
Sq='Squirreltag:BAAALgAECgUJCQAAAA==.',
Sr='Srmorphsalot:BAAALgAECgEJAQABLgAFFAQJEAAgAFUUAA==.',
St='Starnex:BAAALgADCgYJAQAAAA==.Statyrea:BAAALgAECgEJAQAAAA==.Stomped:BAAALgAECgcJDQAAAA==.Strikes:BAAALgAECgIJAgABLgAFFAIJBQAMAM8iAA==.Stromlac:BAAALgADCgYJBgAAAA==.Styx:BAACLgAFFH8MAAIPAAQJyiExAgCUAQAPAAQJyiExAgCUAQAuAAQKfygAAg8ACAlgJqkBAGoDAA8ACAlgJqkBAGoDAAAA.',
Su='Sukfoot:BAAALgAECgMJAwAAAA==.Sumbatadh:BAAALgAECgcJEgAAAA==.Supergooner:BAAALgAECgIJAwAAAA==.',
Sw='Swiftsoul:BAAALgADCgEJAQAAAA==.',
Sy='Sybexia:BAAALgAECgEJAQAAAA==.Sylvestris:BAAALgAECgYJEQAAAA==.',
Ta='Tabcast:BAAALgADCgUJBQAAAA==.Tacodad:BAAALgAECgQJBAAAAA==.Tacofart:BAAALgADCgMJAwAAAA==.Tacos:BAAALgAECgYJDwAAAA==.Tacotitan:BAAALgAECgkJBgAAAA==.Tailas:BAAALgAECgQJCQAAAA==.Tailyan:BAAALgADCgEJAQAAAA==.Taiyana:BAAALgADCgcJDgAAAA==.Talanthir:BAAALgADCgMJAwAAAA==.Tangie:BAAALgADCgkJHgAAAA==.Tankjob:BAAALgAECgQJDAAAAA==.Tanklorswift:BAAALgAECgEJAQAAAA==.Taojin:BAAALgAECgcJEwAAAA==.Tapandsap:BAAALgAECgEJAQAAAA==.Tatsuyâ:BAAALgADCgYJCwAAAA==.',
Te='Teapot:BAAALgAECgEJAQAAAA==.Tedoseirum:BAABLgAECn8ZAAIKAAgJuSRnAwBNAwAKAAgJuSRnAwBNAwAAAA==.Tengenthas:BAAALgAECgEJAQAAAA==.Terpyu:BAAALgAECgQJBgAAAA==.Testicuhls:BAAALgAECgYJEgAAAA==.Texasbilly:BAAALgAECgEJAQAAAA==.Texasredneck:BAAALgADCgQJAwAAAA==.',
Th='Thalchy:BAAALgAECgYJDAAAAA==.Thaydel:BAAALgADCgMJAwAAAA==.Thedtwo:BAABLgAECn8UAAIDAAYJ6Rv0ZQC0AQADAAYJ6Rv0ZQC0AQAAAA==.Thelizzah:BAAALgAECgcJEgAAAA==.Thelvaris:BAAALgAECgYJCwAAAA==.Thorgarrus:BAACLgAFFH8FAAIDAAMJhBvaFgAiAQADAAMJhBvaFgAiAQAuAAQKfyMAAgMACQl4HrQYANUCAAMACQl4HrQYANUCAAAA.',
Ti='Tigerwoodz:BAAALgAECgYJCgAAAA==.Tilbourne:BAAALgAECgEJAQAAAA==.Timfist:BAAALgAECgEJAgAAAA==.Tinada:BAAALgADCgEJAQABLgADCgEJAQATAAAAAA==.Tinytrina:BAAALgADCgYJBgAAAA==.',
To='Toddie:BAABLgAECn8aAAMgAAgJjhr3FADqAQAgAAgJjhr3FADqAQARAAMJugxTbQCJAAAAAA==.Tolkein:BAAALgADCgEJAQAAAA==.Tommyj:BAAALgAECgQJBAAAAA==.Torep:BAAALgAECgQJBAAAAA==.Tormod:BAABLgAECn8ZAAIgAAcJGhduJACJAQAgAAcJGhduJACJAQAAAA==.Tormodd:BAABLgAECn8WAAIKAAYJBA3bEwANAQAKAAYJBA3bEwANAQAAAA==.Torsyn:BAAALgAECgUJBQABLgAECggJGgAgAI4aAA==.Torvaldt:BAAALgAECgIJAgABLgAECggJGgAgAI4aAA==.',
Tr='Traedea:BAAALgAECgYJCQAAAA==.Traps:BAAALgAECgEJAgAAAA==.Trashypanda:BAACLgAFFH8QAAIpAAQJWiINAACoAQApAAQJWiINAACoAQAuAAQKfygAAikACAl+JHsAADQDACkACAl+JHsAADQDAAAA.Trinagirl:BAAALgAECgEJAQAAAA==.Tristanyia:BAAALgAECgcJEwAAAA==.Troolen:BAAALgAECgMJAwAAAA==.Tryana:BAABLgAECn8eAAIkAAcJ4gYfIAABAQAkAAcJ4gYfIAABAQAAAA==.Trystiania:BAAALgAECgYJCgAAAA==.',
Ts='Tseraphim:BAAALgADCgMJBAAAAA==.',
Tt='Tt:BAAALgAECggJEQAAAA==.',
Tu='Tuggnugg:BAAALgAECgEJAQAAAA==.Turcomund:BAAALgADCgIJAgAAAA==.',
Tw='Twentynein:BAAALgAECgcJBwAAAA==.Twentynine:BAABLgAECn8oAAQRAAgJwSA7GwBMAgARAAcJnhw7GwBMAgAgAAgJfRYFKgBtAQASAAIJ2RrAHwClAAAAAA==.',
Ty='Tyledis:BAAALgADCgkJLgABLgAFFAIJBQAkAPAZAA==.Tyr:BAACLgAFFH8LAAICAAMJeBeIEAD7AAACAAMJeBeIEAD7AAAuAAQKfx8AAwIACQnUHbgMANICAAIACQnUHbgMANICAB4AAQlwBXlqACQAAAAA.Tyrandi:BAAALgAECgQJBwAAAA==.Tyrnova:BAAALgAECgQJCAAAAA==.Tyrsa:BAAALgAECgQJBwAAAA==.',
Tz='Tzneetch:BAAALgAECgEJAQAAAA==.',
['Tï']='Tïnk:BAABLgAECn8gAAIJAAgJCxX3FwCpAQAJAAgJCxX3FwCpAQAAAA==.',
['Tö']='Töshïrö:BAAALgAECgMJBQAAAA==.',
Ub='Ubel:BAAALgADCgEJAwAAAA==.',
Ud='Udderlee:BAAALgAECgYJEgAAAA==.',
Uh='Uhope:BAAALgAECgQJBAAAAA==.',
Uk='Ukog:BAAALgAECgcJEgAAAA==.',
Um='Umbravolt:BAACLgAFFH8FAAIoAAMJWxMrBADTAAAoAAMJWxMrBADTAAAuAAQKfywAAigACQmnIR4BAFgDACgACQmnIR4BAFgDAAAA.Umineko:BAAALgAECgEJAQAAAA==.',
Un='Unravel:BAAALgADCgUJCwAAAA==.Unrealpriest:BAAALgAECgMJAwAAAA==.Unrealronin:BAABLgAECn8VAAMPAAgJpgKwGAC/AAAOAAYJkQPIJADHAAAPAAgJQgGwGAC/AAAAAA==.',
Ur='Uruchi:BAAALgADCgEJAQAAAA==.',
Va='Vaelorn:BAABLgAECn8VAAIJAAgJliDuFADaAgAJAAgJliDuFADaAgAAAA==.Vaeris:BAAALgAECgEJAQAAAA==.Vakero:BAAALgAECgYJEwAAAA==.Valeriana:BAAALgADCgQJBQAAAA==.Valice:BAAALgAECgEJAQAAAA==.Vapor:BAAALgAECgEJAgAAAA==.Vatheus:BAAALgADCgYJBgAAAA==.',
Ve='Vert:BAAALgADCgYJBgABLgAFFAMJBgAXANkGAA==.',
Vi='Vibrance:BAABLgAECn8cAAQdAAgJNCCJBQDwAgAdAAgJNCCJBQDwAgAbAAYJFBrVKgBpAQAcAAIJSRL5MgB+AAAAAA==.Vindicus:BAAALgAECgQJBQAAAA==.Viridesa:BAAALgAECgEJAQAAAA==.Vivienne:BAABLgAECn8gAAImAAgJahFaLADUAQAmAAgJahFaLADUAQAAAA==.',
Vo='Voidcore:BAABLgAECn8VAAIJAAkJWRaXFADFAQAJAAkJWRaXFADFAQAAAA==.',
Vv='Vv:BAAALgAECgMJAwAAAA==.',
Vy='Vyrinthial:BAAALgADCgUJBwAAAA==.Vyrnath:BAAALgAECgEJAQAAAA==.',
Wa='Walon:BAAALgADCgcJDgABLgAECgQJBAATAAAAAA==.Warfarmer:BAAALgAECgUJCAAAAA==.Warhawke:BAAALgADCgYJCAAAAA==.',
We='Weak:BAAALgAECgUJCwAAAA==.Weakhand:BAAALgADCgIJAwAAAA==.Webs:BAAALgADCgUJBQAAAA==.Weel:BAABLgAECn8jAAIJAAkJNRveDAAUAgAJAAkJNRveDAAUAgAAAA==.',
Wh='When:BAAALgADCgQJBAABLgAECggJHAAlAAwdAA==.Wheresdparty:BAAALgAECgEJAQAAAA==.Whilaanna:BAABLgAECn8OAAMJAAgJcg8HbQBcAQAJAAcJJBEHbQBcAQAMAAEJRgVZMQAeAAAAAA==.Whis:BAAALgAECgYJDwAAAA==.Whispernight:BAAALgADCgQJBwAAAA==.',
Wi='Widja:BAAALgADCgUJCwAAAA==.Wiilock:BAABLgAECn8dAAIWAAYJ4B4aRAD/AQAWAAYJ4B4aRAD/AQAAAA==.Wiivinelight:BAAALgAECgYJCgABLgAECgYJHQAWAOAeAA==.Wiivoker:BAAALgAECgUJBAABLgAECgYJHQAWAOAeAA==.Wildwhitwlkr:BAAALgADCgIJAwAAAA==.Wilfrid:BAAALgADCgIJAgABLgAFFAEJAQATAAAAAA==.',
Wr='Wraithlord:BAAALgADCgcJBwAAAA==.',
['Wå']='Wåffle:BAAALgAECgEJAQABLgAECgcJFQAiAC0lAA==.',
Xa='Xandari:BAAALgADCgkJDwAAAA==.Xania:BAAALgADCgYJBwAAAA==.',
['Xû']='Xûrû:BAAALgAECgYJCQAAAA==.',
Yc='Yce:BAAALgAECgYJEQAAAA==.',
Yo='Yoker:BAAALgADCgYJCwAAAA==.Yokersen:BAAALgAECgUJBQAAAA==.',
Za='Zaeladen:BAAALgAECgIJAgAAAA==.Zalorea:BAAALgAECgEJAgAAAA==.Zamrog:BAABLgAECn8oAAILAAkJ1iDeAAARAwALAAkJ1iDeAAARAwAAAA==.Zamthyr:BAAALgAECgcJCAABLgAECgkJKAALANYgAA==.Zanya:BAAALgAECgIJAgAAAA==.',
Ze='Zeiko:BAAALgADCgYJBgAAAA==.Zellah:BAAALgAECgYJBgAAAA==.Zenez:BAAALgAECgYJCwAAAA==.Zexor:BAAALgADCgYJDwAAAA==.',
Zh='Zhaoyun:BAABLgAECn8ZAAIlAAcJcBe7KwBYAQAlAAcJcBe7KwBYAQAAAA==.',
Zi='Zilkir:BAACLgAFFH8FAAMDAAIJZxy8LACtAAADAAIJZxy8LACtAAAmAAEJ4SHeGQBkAAAuAAQKfyYAAyYACAkxI9gEAB8DACYACAkxI9gEAB8DAAMABwkCIOlHAAsCAAAA.Ziran:BAAALgAECgYJCAAAAA==.Zivadhim:BAAALgAECgEJAQAAAA==.',
Zk='Zkollkrusher:BAAALgADCgYJBgAAAA==.Zkullkrushur:BAAALgAECgUJBQAAAA==.Zkvllkrusher:BAAALgADCgEJAQAAAA==.',
Zl='Zlyth:BAAALgAECgEJAQAAAA==.',
Zo='Zohan:BAAALgADCgQJBAAAAA==.Zooie:BAABLgAECn8eAAMCAAgJ1BRGDQDJAQACAAgJ1BRGDQDJAQAeAAcJHxheMwC3AQAAAA==.Zould:BAAALgAECgYJBwAAAA==.',
Zy='Zyrix:BAAALgADCgQJBAAAAA==.',
['Är']='Ärtrix:BAAALgADCgEJAQAAAA==.',
['Ät']='Ätrixx:BAAALgAECgMJAwAAAA==.',
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
